---@diagnostic disable: undefined-global
--
-- Equiniti Shareview Portfolio — MoneyMoney Web Banking Extension
-- Plugin Homepage: https://github.com/rosch100/Shareview-MoneyMoney
-- https://portfolio.shareview.co.uk
-- Dokumentation: README.md (Hub: https://github.com/rosch100/moneymoney-extensions)
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 1.04,
  url         = "https://portfolio.shareview.co.uk",
  services    = {"Shareview"},
  description = "Equiniti Shareview Portfolio - Direct Login (Username + Password + DOB + MFA)"
}

local CONSTANTS = {
  legacyAccountNumber = "shareview-portfolio",
  accountNumberPrefix = "SV.",
  baseUrl     = "https://portfolio.shareview.co.uk",
  loginUrl    = "https://portfolio.shareview.co.uk/7/Portfolio/default/en/anonymous/Pages/Login.aspx",
  holdingsUrl = "https://portfolio.shareview.co.uk/7/portfolio/default/en/Active/Pages/holdingssummary.aspx",
  logoutUrl   = "https://portfolio.shareview.co.uk/7/Auth/Logoff.aspx",
  adfsUrl     = "https://www.equiniti.com/adfs/ls/",
  trustUrl    = "https://portfolio.shareview.co.uk/_trust/",
  allowedHosts = {
    "portfolio.shareview.co.uk",
    "www.equiniti.com",
  },
  userAgent   = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}

local CREDENTIAL_REJECTION_MARKERS = {
  "username or password",
  "user id or password",
  "incorrect password",
  "invalid credentials",
  "details you have entered are incorrect",
}

local connection
local session = { cookies = "", persistedConnection = false }

local function trim(text)
  if not text then return "" end
  return (text:gsub("^%s*(.-)%s*$", "%1"))
end

local function normalizeAccountKey(key)
  if key == nil then
    return ""
  end
  return trim(tostring(key)):lower()
end

local function accountKeysMatch(storedKey, currentKey)
  storedKey = normalizeAccountKey(storedKey)
  currentKey = normalizeAccountKey(currentKey)
  if storedKey == "" or currentKey == "" then
    return true
  end
  return storedKey == currentKey
end

local function htmlDecode(text)
  if not text then return "" end
  text = text:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
             :gsub("&quot;", "\""):gsub("&#39;", "'"):gsub("&nbsp;", " ")
  text = text:gsub("&#x([%da-fA-F]+);", function(h)
    local n = tonumber(h, 16); return n and string.char(n) or ""
  end)
  text = text:gsub("&#(%d+);", function(d)
    local n = tonumber(d); return n and string.char(n) or ""
  end)
  return text
end

local function stripTags(s)
  if not s then return "" end
  return trim(htmlDecode((s:gsub("<[^>]+>", " "):gsub("%s+", " "))))
end

function parseDobString(raw)
  if not raw then return nil, nil, nil end
  local d, m, y = trim(raw):match("^(%d+)[%./%-](%d+)[%./%-](%d+)$")
  if not d then return nil, nil, nil end
  return tonumber(d), tonumber(m), tonumber(y)
end

function isValidDob(day, month, year)
  if not (day and month and year) then return false end
  if day   < 1    or day   > 31   then return false end
  if month < 1    or month > 12   then return false end
  if year  < 1900 or year  > 2100 then return false end
  return true
end

function parseUsernameDob(rawUsername)
  if not rawUsername or rawUsername == "" then return nil end
  local user, dob = rawUsername:match("^([^|]+)|(.+)$")
  if not user then return trim(rawUsername) end
  return trim(user), parseDobString(dob)
end

--- Login identity without DOB suffix (multi-login accountKey / accountNumber).
function shareviewLoginUsername(rawUsername)
  local user = parseUsernameDob(rawUsername)
  if type(user) ~= "string" or user == "" then
    return nil
  end
  return user
end

function shareviewAccountNumberForUsername(username)
  if type(username) ~= "string" or username == "" then
    return nil
  end
  return CONSTANTS.accountNumberPrefix .. username
end

function shareviewAccountNameForUsername(username)
  if type(username) ~= "string" or username == "" then
    return "Shareview"
  end
  return "Shareview (" .. username .. ")"
end

function isLegacyShareviewAccountNumber(accountNumber)
  return accountNumber == CONSTANTS.legacyAccountNumber
end

function knownAccountsIncludeLegacyShareview(knownAccounts)
  if type(knownAccounts) ~= "table" then
    return false
  end
  for _, acc in ipairs(knownAccounts) do
    if type(acc) == "table" and isLegacyShareviewAccountNumber(acc.accountNumber) then
      return true
    end
  end
  return false
end

function matchesActiveShareviewAccount(accountNumber)
  if type(accountNumber) ~= "string" or accountNumber == "" then
    return false
  end
  -- Existing MoneyMoney accounts keep shareview-portfolio; still refresh.
  if isLegacyShareviewAccountNumber(accountNumber) then
    return type(session.loginUsername) == "string" and session.loginUsername ~= ""
  end
  local expected = session.accountNumber
  return type(expected) == "string" and accountNumber == expected
end

function parseCurrencyValue(raw)
  if not raw then return nil, nil, nil end
  local parts = {}
  for part in (raw .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
  if #parts < 2 then return nil, nil, nil end
  local currency = trim(parts[1])
  local value = tonumber(parts[2])
  if not value then return nil, nil, nil end
  if currency == "GBX" or currency == "GBp" then return value / 100, "GBX", value end
  return value, currency, value
end

local function normalizeCurrency(c)
  if c == "GBX" or c == "GBp" then return "GBP" end
  if not c or c == "" then return nil end
  return c
end

local function submitForm(formNode)
  if not formNode or formNode:length() == 0 then
    return nil, "Form-Element nicht gefunden (XPath traf nicht)."
  end
  -- Empty action posts to the current document URL (already on an allowlisted host).
  local action = formNode:attr("action")
  if type(action) == "string" and trim(action) ~= "" then
    local _, actionErr = checkFederationFormAction(action)
    if actionErr then
      return nil, actionErr
    end
  end
  local content = connection:request(formNode:submit())
  return content
end

local function mfaChallenge(text)
  return {
    title     = "Shareview Authentifizierung",
    challenge = text or "Bitte den 6-stelligen Authentication Code aus der Shareview-App oder E-Mail eingeben.",
    label     = "Authentication Code"
  }
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Shareview"
end

function restoreShareviewConnection(accountKey)
  local storage = rawget(_G, "LocalStorage")
  accountKey = accountKey or ""
  if not storage then
    connection = Connection()
    session.persistedConnection = false
    connection.language = "en-GB"
    connection.useragent = CONSTANTS.userAgent
    return false
  end

  storage.connectionsByAccount = storage.connectionsByAccount or {}
  local entry = storage.connectionsByAccount[accountKey]
  if storage.connection ~= nil and storage.connectionAccountKey == accountKey then
    entry = entry or {}
    entry.connection = storage.connection
    if type(storage.sessionCookies) == "string"
        and storage.sessionCookies ~= ""
        and entry.sessionCookies == nil then
      entry.sessionCookies = storage.sessionCookies
    end
    storage.connectionsByAccount[accountKey] = entry
  end
  local canReuse = entry ~= nil and entry.connection ~= nil
  if canReuse then
    connection = entry.connection
    session.persistedConnection = true
  else
    connection = Connection()
    entry = entry or {}
    entry.connection = connection
    storage.connectionsByAccount[accountKey] = entry
    session.persistedConnection = true
  end
  storage.connection = connection
  storage.connectionAccountKey = accountKey
  connection.language = "en-GB"
  connection.useragent = CONSTANTS.userAgent
  return canReuse
end

function applyShareviewCookieHeader(cookieHeader)
  local formatted = trim(cookieHeader or "")
  if formatted == "" then
    return false
  end
  session.cookies = formatted
  if connection and type(connection.setCookie) == "function" then
    for pair in formatted:gmatch("[^;]+") do
      local name, value = pair:match("^%s*([^=]+)=(.+)$")
      if name and value then
        pcall(function()
          connection:setCookie(trim(name) .. "=" .. trim(value))
        end)
      end
    end
  end
  return true
end

function collectShareviewCookieHeader()
  if connection and type(connection.getCookies) == "function" then
    local jarCookies = connection:getCookies()
    if type(jarCookies) == "string" and jarCookies ~= "" then
      return jarCookies
    end
  end
  if type(session.cookies) == "string" and session.cookies ~= "" then
    return session.cookies
  end
  return nil
end

function persistShareviewSessionCookies()
  local cookies = collectShareviewCookieHeader()
  if not cookies or not cookies:match("FedAuth=") then
    return false
  end
  local storage = rawget(_G, "LocalStorage")
  if not storage then
    session.cookies = cookies
    return false
  end
  local accountKey = session.accountKey or storage.connectionAccountKey or ""
  if accountKey == "" then
    return false
  end
  storage.connectionsByAccount = storage.connectionsByAccount or {}
  local entry = storage.connectionsByAccount[accountKey] or {}
  entry.connection = connection
  entry.sessionCookies = cookies
  storage.connectionsByAccount[accountKey] = entry
  storage.sessionCookies = cookies
  storage.sessionAccountKey = accountKey
  storage.connection = connection
  storage.connectionAccountKey = accountKey
  session.cookies = cookies
  return true
end

function tryRestoreShareviewSessionCookies(accountKey)
  local storage = rawget(_G, "LocalStorage")
  if not storage then
    return false
  end
  accountKey = accountKey or ""
  local cookies = nil
  local entry = storage.connectionsByAccount and storage.connectionsByAccount[accountKey]
  if entry and type(entry.sessionCookies) == "string" and entry.sessionCookies ~= "" then
    cookies = entry.sessionCookies
  elseif type(storage.sessionCookies) == "string" and storage.sessionCookies ~= "" then
    if accountKeysMatch(storage.sessionAccountKey or "", accountKey) then
      cookies = storage.sessionCookies
    end
  end
  if not cookies or not cookies:match("FedAuth=") then
    return false
  end
  return applyShareviewCookieHeader(cookies)
end

function tryHoldingsWithCurrentSession()
  local holdings = connection:get(CONSTANTS.holdingsUrl)
  if holdings and holdings ~= "" and isLoggedInPage(holdings) then
    session.holdingsHtmlString = holdings
    persistShareviewSessionCookies()
    return true
  end
  return false
end

function bindShareviewLoginIdentity(rawUsername)
  local username = shareviewLoginUsername(rawUsername)
  if not username then
    session.loginUsername = nil
    session.accountNumber = nil
    return nil
  end
  session.loginUsername = username
  session.accountNumber = shareviewAccountNumberForUsername(username)
  return username
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  if step == 1 then
    local rawUsername = credentials and credentials[1] or ""
    local accountKey = bindShareviewLoginIdentity(rawUsername) or rawUsername
    session.accountKey = accountKey
    restoreShareviewConnection(accountKey)

    if tryHoldingsWithCurrentSession() then
      return nil
    end
    if tryRestoreShareviewSessionCookies(accountKey) and tryHoldingsWithCurrentSession() then
      return nil
    end
    return loginStep1(credentials, interactive)
  end
  restoreShareviewConnection(session.accountKey or "")
  if session.awaitingDob then return submitDobAndLogin(credentials[1]) end
  if session.awaitingMfa then return submitMfaCode(credentials) end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end

function loginStep1(credentials, interactive)
  local rawUsername = credentials[1]
  local password    = credentials[2]

  if not password or password == "" then return "Bitte ein Shareview-Passwort eingeben." end
  if password:match("^COOKIE:") then return loginWithImportedCookies(password:sub(8)) end

  local username, day, month, year = parseUsernameDob(rawUsername)
  if not username or username == "" then
    return "Bitte einen Shareview-Benutzernamen eingeben."
  end

  if day and month and year then
    if not isValidDob(day, month, year) then
      return "Ungültiges Geburtsdatum im Benutzernamen. Format: \"username|TT.MM.JJJJ\"."
    end
    return submitCredentials(username, password, day, month, year)
  end

  if interactive == false then
    return "Geburtsdatum fehlt. Bitte den Benutzernamen einmalig als \"username|TT.MM.JJJJ\" speichern (z.B. \"" .. username .. "|01.01.1970\"), damit das automatische Sync funktioniert."
  end

  session.awaitingDob = true
  session.pendingUsername = username
  session.pendingPassword = password
  return {
    title     = "Geburtsdatum erforderlich",
    challenge = "Bitte das Geburtsdatum für Shareview eingeben (Format TT.MM.JJJJ).\n\nTipp: Speichere es dauerhaft als Teil des Benutzernamens (\"" .. username .. "|01.01.1970\"), dann entfällt diese Abfrage künftig.",
    label     = "Geburtsdatum (TT.MM.JJJJ)"
  }
end

function submitDobAndLogin(dobRaw)
  session.awaitingDob = false
  local username, password = session.pendingUsername, session.pendingPassword
  session.pendingUsername, session.pendingPassword = nil, nil
  if not username or not password then
    return "Anmeldesitzung für das Geburtsdatum abgelaufen. Bitte erneut anmelden."
  end

  local day, month, year = parseDobString(dobRaw)
  if not isValidDob(day, month, year) then
    return "Ungültiges Geburtsdatum. Erwartet: TT.MM.JJJJ (z.B. 01.01.1970)."
  end
  return submitCredentials(username, password, day, month, year)
end

function submitCredentials(username, password, day, month, year)
  local content = connection:get(CONSTANTS.loginUrl)
  if not content or content == "" then
    return "Login fehlgeschlagen: Login-Seite nicht erreichbar."
  end

  local html = HTML(content)

  html:xpath('//input[contains(@id, "UserLocate2UC1_rpt_ctl00_txtInput")]'):attr("value", username)
  html:xpath('//input[contains(@id, "UserLocate2UC1_rpt_ctl02_txtInput")]'):attr("value", password)
  html:xpath('//select[contains(@id, "drpDay")]/option[@value="'   .. day   .. '"]'):attr("selected", "selected")
  html:xpath('//select[contains(@id, "drpMonth")]/option[@value="' .. month .. '"]'):attr("selected", "selected")
  html:xpath('//select[contains(@id, "drpYear")]/option[@value="'  .. year  .. '"]'):attr("selected", "selected")

  local locateBtn = html:xpath('//input[contains(@id, "btnLocate") or contains(@name, "btnLocate")]'):attr("name")
  html:xpath('//input[@name="__EVENTTARGET"]'):attr("value", locateBtn or "")

  local mfaContent, submitErr = submitForm(html:xpath('//form[@name="aspnetForm"]'))
  if submitErr then return "Login fehlgeschlagen: " .. submitErr end
  if not mfaContent or mfaContent == "" then
    return "Login fehlgeschlagen: Keine Antwort vom Server."
  end

  if isLoggedInPage(mfaContent) then
    session.holdingsHtmlString = mfaContent
    persistShareviewSessionCookies()
    return nil
  end

  local loginError = extractLoginError(HTML(mfaContent))
  if loginError then
    if isCredentialRejectionMessage(loginError) then
      return LoginFailed
    end
    return "Login fehlgeschlagen: " .. loginError
  end
  if not isMfaPage(mfaContent) then
    return "Login fehlgeschlagen: Unerwartete Antwort. Bitte Zugangsdaten und Geburtsdatum prüfen."
  end

  session.mfaHtmlString = mfaContent
  session.awaitingMfa = true
  return mfaChallenge()
end

function submitMfaCode(credentials)
  if not session.mfaHtmlString then
    return "MFA-Session abgelaufen. Bitte erneut anmelden."
  end

  local code = credentials[1]
  if not code or not code:match("^%s*%d+%s*$") then
    return mfaChallenge("Ungültiger Authentication Code (nur Ziffern). Bitte erneut eingeben.")
  end
  code = trim(code)

  local mfaHtml = HTML(session.mfaHtmlString)
  mfaHtml:xpath('//input[contains(@id, "txtVerificationCode") or contains(@name, "txtVerificationCode")]'):attr("value", code)
  local submitBtn = mfaHtml:xpath('//input[contains(@id, "btnSubmitOtp") or contains(@name, "btnSubmitOtp")]'):attr("name")
  mfaHtml:xpath('//input[@name="__EVENTTARGET"]'):attr("value", submitBtn or "")

  local otpResponse, submitErr = submitForm(mfaHtml:xpath('//form[@name="aspnetForm"]'))

  if submitErr then
    session.awaitingMfa = false
    session.mfaHtmlString = nil
    return "MFA fehlgeschlagen: " .. submitErr
  end
  if not otpResponse then
    session.awaitingMfa = false
    session.mfaHtmlString = nil
    return "MFA fehlgeschlagen: Keine Antwort vom Server."
  end

  if otpResponse:match("Please enter a 6 digit Authentication Code")
     or otpResponse:match('id="otpErrorLabelWrapper"[^>]*>%s*<span>') then
    session.mfaHtmlString = otpResponse
    return mfaChallenge("Authentication Code abgelehnt. Bitte erneut versuchen.")
  end

  session.awaitingMfa = false
  session.mfaHtmlString = nil
  local hopContent, hopErr = followFederationHops(otpResponse, 5)
  return finishMfaAfterFederation(hopContent, hopErr)
end

function finishMfaAfterFederation(hopContent, hopErr)
  if hopErr then
    return hopErr
  end
  if tryHoldingsWithCurrentSession() then
    return nil
  end
  return "MFA fehlgeschlagen. Bitte Anmeldung erneut starten; bei wiederholten Fehlversuchen kann das Konto temporaer gesperrt sein."
end

function resolveFederationActionUrl(action)
  action = trim(action)
  if action == "" then
    return nil, "Federation-Hop: Form action fehlt"
  end
  if action:match("^https?://") then
    if not action:match("^https://") then
      return nil, "Federation-Hop: nur https:// erlaubt"
    end
    return action, nil
  end
  if action:sub(1, 1) == "/" then
    return CONSTANTS.baseUrl .. action, nil
  end
  action = action:gsub("^%./", "")
  return CONSTANTS.baseUrl .. "/" .. action, nil
end

function hostFromUrl(url)
  if type(url) ~= "string" or url == "" then
    return nil
  end
  local host = url:match("^https?://([^/?#]+)")
  if not host then
    return nil
  end
  host = host:lower()
  host = host:gsub(":443$", ""):gsub(":80$", "")
  return host
end

function isAllowedFederationHost(host)
  if not host or host == "" then
    return false
  end
  host = host:lower()
  for _, allowed in ipairs(CONSTANTS.allowedHosts) do
    if host == allowed:lower() then
      return true
    end
  end
  return false
end

function checkFederationFormAction(action)
  local absolute, resolveErr = resolveFederationActionUrl(action)
  if resolveErr then
    return nil, resolveErr
  end
  local host = hostFromUrl(absolute)
  if not host then
    return nil, "Federation-Hop: Form action ohne Host"
  end
  if not isAllowedFederationHost(host) then
    return nil, "Federation-Hop zu nicht erlaubtem Host: " .. host
  end
  return absolute, nil
end

function followFederationHops(content, maxHops)
  for _ = 1, (maxHops or 5) do
    if not content or content == "" then return content, nil end
    local html = HTML(content)
    local form = html:xpath('//form[@name="hiddenform"]')
    local title = html:xpath('//title'):text() or ""
    local isAutoPost = title:match("Working") ~= nil
                       or content:match("document%.forms%[0%]%.submit") ~= nil
                       or content:match('<form[^>]+name="hiddenform"') ~= nil
    if not isAutoPost or not form or form:length() == 0 then return content, nil end

    local action = form:attr("action")
    local _, actionErr = checkFederationFormAction(action)
    if actionErr then
      return nil, actionErr
    end

    local nextContent, hopErr = submitForm(form)
    if hopErr then
      return nil, hopErr
    end
    content = nextContent
  end
  return content, nil
end

function loginWithImportedCookies(cookieString)
  local formatted = trim(cookieString)
  if formatted:match(",") and not formatted:match(";") then
    formatted = formatted:gsub("%s*,%s*", "; ")
  end
  if not formatted:match("=") then
    return "Ungültiges Cookie-Format. Erwartet: name=value;name2=value2"
  end
  if not formatted:match("FedAuth=") then
    return "FedAuth-Cookie fehlt. Bitte erneut nach erfolgreichem Login exportieren."
  end

  local response = connection:request("GET", CONSTANTS.holdingsUrl, nil, nil, {
    ["Accept"]          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-GB,en;q=0.9",
    ["Cookie"]          = formatted
  })

  if not response or not isLoggedInPage(response) then
    return "Cookie-Import fehlgeschlagen. Cookies abgelaufen — bitte erneut exportieren."
  end

  applyShareviewCookieHeader(formatted)
  session.holdingsHtmlString = response
  persistShareviewSessionCookies()
  return nil
end

function isLoggedInPage(content)
  if not content then return false end
  if content:match('id="TotalIndicativeValue"') then return true end
  if content:match("My Holdings Summary") then return true end
  if content:find("holdingssummary", 1, true) and content:match("BaseHoldingSummaryUC1") then
    return true
  end
  return false
end

function isMfaPage(content)
  if not content then return false end
  return content:lower():find("authentication code", 1, true) ~= nil
end

function extractLoginError(htmlNode)
  if not htmlNode then return nil end
  local candidates = {
    '//*[contains(@class, "ErrorMessage")]',
    '//*[contains(@id, "lblError")]',
    '//*[contains(@id, "ErrorLabel")]'
  }
  for _, xp in ipairs(candidates) do
    local node = htmlNode:xpath(xp)
    if node then
      local text = trim(node:text() or "")
      if text ~= "" then return text end
    end
  end
  return nil
end

function isCredentialRejectionMessage(message)
  if type(message) ~= "string" then
    return false
  end
  local normalized = message:lower()
  for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
    if normalized:find(marker, 1, true) then
      return true
    end
  end
  return false
end

function ListAccounts(knownAccounts)
  if not session.holdingsHtmlString then
    session.holdingsHtmlString = connection:get(CONSTANTS.holdingsUrl)
  end
  if not session.holdingsHtmlString or not isLoggedInPage(session.holdingsHtmlString) then
    return "Holdings-Seite nicht zugänglich. Session abgelaufen?"
  end
  local username = session.loginUsername
  local accountNumber = session.accountNumber
  if type(username) ~= "string" or username == ""
      or type(accountNumber) ~= "string" or accountNumber == "" then
    return "Shareview: Login-Benutzername fehlt für die Kontonummer."
  end
  -- Keep offering the legacy number when MoneyMoney already has that account.
  if knownAccountsIncludeLegacyShareview(knownAccounts) then
    accountNumber = CONSTANTS.legacyAccountNumber
  end
  return {
    {
      name          = shareviewAccountNameForUsername(username),
      accountNumber = accountNumber,
      portfolio     = true,
      currency      = "GBP",
      type          = AccountTypePortfolio,
      bankCode      = "Shareview"
    }
  }
end

function RefreshAccount(account, since)
  if not account or type(account.accountNumber) ~= "string" then
    error("Shareview: Kontoabruf für unbekanntes Konto nicht möglich.")
  end
  if not matchesActiveShareviewAccount(account.accountNumber) then
    error("Shareview: Kontoabruf für unbekanntes Konto nicht möglich.")
  end

  local html = connection:get(CONSTANTS.holdingsUrl)
  if not html then
    error("Shareview: Kontoabruf fehlgeschlagen, Holdings-Seite nicht erreichbar.")
  end
  session.holdingsHtmlString = html
  if not isLoggedInPage(html) then
    error("Shareview: Kontoabruf fehlgeschlagen, Holdings-Seite ist nicht authentifiziert.")
  end
  if not html:find("summaryDataItemRow", 1, true) then
    error("Shareview: Positionsbereich fehlt in der Serverantwort.")
  end

  local securities, incompletePositions = parseHoldings(html)
  if incompletePositions > 0 then
    error("Shareview: Kontoabruf enthält unvollständige Portfoliodaten.")
  end
  local balance = parseTotalIndicativeValue(html)
  if balance == nil and #securities == 0 then
    error("Shareview: Kontoabruf lieferte keine vollständigen Portfoliodaten.")
  end

  local portfolio = { securities = securities }
  if balance ~= nil then
    portfolio.balance = balance
  end
  return portfolio
end

function parseTotalIndicativeValue(htmlString)
  if not htmlString then return nil, nil end
  local block = htmlString:match('id="TotalIndicativeValue"[^>]*>%s*<span[^>]*>([^<]+)<')
                or htmlString:match('id="TotalIndicativeValue".-currencyChange[^>]*>([^<]+)<')
  if not block then return nil, nil end
  local amount, native = parseCurrencyValue(block)
  return amount, normalizeCurrency(native)
end

function parseHoldings(htmlString)
  local securities = {}
  local incompletePositions = 0
  if not htmlString then return securities, incompletePositions end
  for row in htmlString:gmatch('<tr[^>]*summaryDataItemRow[^>]*>(.-)</tr>') do
    local sec = parseHoldingRow(row)
    if sec then
      securities[#securities + 1] = sec
    else
      incompletePositions = incompletePositions + 1
    end
  end
  return securities, incompletePositions
end

local function extractIsin(row)
  -- Lua-Patterns kennen kein {n}; daher per Längen-/Format-Check validieren.
  local candidate = row:match("externalid=([A-Z0-9]+)") or ""
  if #candidate == 12 and candidate:match("^[A-Z][A-Z][A-Z0-9]+[0-9]$") then
    return candidate
  end
  return ""
end

local function extractCurrencyCell(cell)
  if not cell then return nil end
  return cell:match('<span class="original">([^<]+)</span>')
      or cell:match('currencyChange[^>]*>([^<]+)<span')
      or cell:match('currencyChangeIgnoreNative[^>]*>([^<]+)<span')
end

function parseHoldingRow(row)
  if not row then return nil end

  local holdingCell = row:match('headers="holding"[^>]*>(.-)</td>') or ""
  local name = trim(htmlDecode(holdingCell:match("<strong>%s*([^<]+)%s*</strong>") or ""))
  if name == "" then return nil end

  local subAccount = holdingCell:match("</strong>%s*<br/?>%s*([^<]+)")
  if subAccount then subAccount = trim(htmlDecode(subAccount)) end
  local fullName = name
  if subAccount and subAccount ~= "" and not subAccount:match("Shareholder Ref") then
    fullName = name .. " (" .. subAccount .. ")"
  end

  local shareholderRef = trim(holdingCell:match("Shareholder Ref No:%s*([%w%-]+)") or "")

  local quantityCell = row:match('headers="quantity"[^>]*>(.-)</td>') or ""
  local quantityStr  = (quantityCell:match('<bdo[^>]*>%s*([%d%.,]+)%s*</bdo>') or stripTags(quantityCell) or ""):gsub(",", "")
  local quantity     = tonumber(quantityStr)
  if quantity == nil then return nil end

  local priceCell = row:match('headers="price"[^>]*>(.-)</td>')
  local pricePerShare, priceNative = parseCurrencyValue(extractCurrencyCell(priceCell))

  local valueCell = row:match('headers="value"[^>]*>(.-)</td>')
  local amount, valueNative = parseCurrencyValue(extractCurrencyCell(valueCell))

  if not amount and pricePerShare and quantity > 0 then
    amount = pricePerShare * quantity
  end
  if not pricePerShare and amount and quantity > 0 then
    pricePerShare = amount / quantity
    priceNative = valueNative
  end
  local priceCurrency = normalizeCurrency(priceNative)
  local amountCurrency = normalizeCurrency(valueNative or priceNative)
  if not pricePerShare or not amount or not priceCurrency or not amountCurrency then
    return nil
  end

  return {
    name                     = fullName,
    isin                     = extractIsin(row),
    securityNumber           = shareholderRef,
    quantity                 = quantity,
    price                    = pricePerShare,
    currencyOfPrice          = priceCurrency,
    amount                   = amount,
    currencyOfOriginalAmount = amountCurrency
  }
end

function EndSession()
  local wasPersisted = session.persistedConnection == true
  local storage = rawget(_G, "LocalStorage")
  local accountKey = session.accountKey or ""
  if wasPersisted then
    persistShareviewSessionCookies()
  elseif connection then
    pcall(function() connection:get(CONSTANTS.logoutUrl) end)
  end
  session.pendingUsername = nil
  session.pendingPassword = nil
  session = { cookies = "", persistedConnection = false }
  connection = nil
  if storage == nil then
    return
  end
  if not wasPersisted and accountKey ~= "" and type(storage.connectionsByAccount) == "table" then
    storage.connectionsByAccount[accountKey] = nil
    if storage.sessionAccountKey == accountKey then
      storage.sessionCookies = nil
      storage.sessionAccountKey = nil
    end
  end
  if storage.connectionAccountKey == accountKey then
    storage.connection = nil
    storage.connectionAccountKey = nil
  end
end

-- SIGNATURE: MCwCFFzhulB5Xr0AiLOy1JfsxEVytmTCAhRSUgPXjZTslcSYZD0Lvuf8GsFgcQ==
