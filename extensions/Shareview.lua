--
-- Equiniti Shareview Portfolio — MoneyMoney Web Banking Extension
-- https://portfolio.shareview.co.uk
-- Dokumentation: docs/LUA-EXTENSIONS.md
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking {
  version = "1.0.0",
  url = "https://portfolio.shareview.co.uk",
  services = {"Shareview"},
  description = "Equiniti Shareview Portfolio - Direct Login (Username|DOB + Password + MFA) und Cookie Import"
}

local CONSTANTS = {
  baseUrl = "https://portfolio.shareview.co.uk",
  loginUrl = "https://portfolio.shareview.co.uk/7/Portfolio/default/en/anonymous/Pages/Login.aspx",
  holdingsUrl = "https://portfolio.shareview.co.uk/7/portfolio/default/en/Active/Pages/holdingssummary.aspx",
  logoutUrl = "https://portfolio.shareview.co.uk/7/Auth/Logoff.aspx",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
  -- ASP.NET WebForms Steuer-IDs (aus HAR-Capture des Login-Formulars)
  field = {
    username  = "ctl00$SPWebPartManager1$g_82244877_0bab_4d69_9780_dbb1a7f3fbea$UserLocate2UC1$rpt$ctl00$txtInput",
    day       = "ctl00$SPWebPartManager1$g_82244877_0bab_4d69_9780_dbb1a7f3fbea$UserLocate2UC1$rpt$ctl01$dtInput$drpDay",
    month     = "ctl00$SPWebPartManager1$g_82244877_0bab_4d69_9780_dbb1a7f3fbea$UserLocate2UC1$rpt$ctl01$dtInput$drpMonth",
    year      = "ctl00$SPWebPartManager1$g_82244877_0bab_4d69_9780_dbb1a7f3fbea$UserLocate2UC1$rpt$ctl01$dtInput$drpYear",
    password  = "ctl00$SPWebPartManager1$g_82244877_0bab_4d69_9780_dbb1a7f3fbea$UserLocate2UC1$rpt$ctl02$txtInput",
    locateBtn = "ctl00$SPWebPartManager1$g_82244877_0bab_4d69_9780_dbb1a7f3fbea$UserLocate2UC1$btnLocate"
  }
}

local connection
local session = { cookies = "" }

-- ============================================================================
-- Hilfsfunktionen
-- ============================================================================

local function trim(text)
  if not text then return "" end
  return (text:gsub("^%s*(.-)%s*$", "%1"))
end

local function htmlDecode(text)
  if not text then return "" end
  text = text:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
             :gsub("&quot;", "\""):gsub("&#39;", "'"):gsub("&nbsp;", " ")
  text = text:gsub("&#x([%da-fA-F]+);", function(h)
    local n = tonumber(h, 16)
    return n and string.char(n) or ""
  end)
  text = text:gsub("&#(%d+);", function(d)
    local n = tonumber(d)
    return n and string.char(n) or ""
  end)
  return text
end

local function stripTags(html)
  if not html then return "" end
  return trim(htmlDecode((html:gsub("<[^>]+>", " "):gsub("%s+", " "))))
end

-- urlencode: Lua 5.1 hat keine eingebaute Funktion, MoneyMoney stellt MM.urlencode bereit
local function urlencode(value)
  if value == nil then return "" end
  return MM.urlencode(tostring(value))
end

-- VIEWSTATE und ähnliche Hidden-Felder aus HTML extrahieren
local function extractHidden(html, name)
  if not html or not name then return nil end
  local quoted = name:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
  local pattern = '<input[^>]*name="' .. quoted .. '"[^>]*value="([^"]*)"'
  local value = html:match(pattern)
  if value then return htmlDecode(value) end
  pattern = '<input[^>]*value="([^"]*)"[^>]*name="' .. quoted .. '"'
  value = html:match(pattern)
  if value then return htmlDecode(value) end
  return nil
end

-- DOB aus username-Feld parsen: "username|DD.MM.YYYY" oder "username|DD/MM/YYYY"
function parseUsernameDob(rawUsername)
  if not rawUsername or rawUsername == "" then
    return nil, nil, nil, nil
  end
  local user, dob = rawUsername:match("^([^|]+)|(.+)$")
  if not user then
    return trim(rawUsername), nil, nil, nil
  end
  user = trim(user)
  dob = trim(dob)
  local d, m, y = dob:match("^(%d+)[%./%-](%d+)[%./%-](%d+)$")
  if not d or not m or not y then
    return user, nil, nil, nil
  end
  local dn, mn, yn = tonumber(d), tonumber(m), tonumber(y)
  if not dn or not mn or not yn then
    return user, nil, nil, nil
  end
  return user, dn, mn, yn
end

-- Sammelt alle Hidden- und sonstigen Initial-Werte aus dem HTML in der
-- Reihenfolge, in der sie im DOM stehen (entspricht dem Browser-POST).
-- Override-Werte aus `fields` ersetzen ggf. bestehende Hidden-Werte.
local function buildFormBody(html, fields)
  local seen = {}
  local parts = {}

  -- 1) Override-Felder zuerst registrieren, damit Hidden-Duplikate übersprungen werden
  local overrides = {}
  for _, pair in ipairs(fields) do
    overrides[pair[1]] = pair[2]
  end

  -- 2) Alle Hidden-Inputs aus dem HTML in DOM-Reihenfolge übernehmen
  for tag in html:gmatch("<input[^>]+>") do
    local typ = tag:match('type="([^"]+)"')
    if not typ or typ:lower() == "hidden" then
      local name = tag:match('name="([^"]+)"')
      local value = tag:match('value="([^"]*)"') or ""
      if name and not seen[name] then
        seen[name] = true
        local effective = overrides[name]
        if effective == nil then effective = htmlDecode(value) end
        table.insert(parts, urlencode(name) .. "=" .. urlencode(effective))
      end
    end
  end

  -- 3) Override-Felder, die nicht als Hidden im DOM vorkommen, anhängen
  for _, pair in ipairs(fields) do
    if not seen[pair[1]] then
      seen[pair[1]] = true
      table.insert(parts, urlencode(pair[1]) .. "=" .. urlencode(pair[2]))
    end
  end

  return table.concat(parts, "&")
end

local function requestHtml(method, url, body, contentType, extraHeaders)
  local headers = {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-GB,en;q=0.9",
    ["Cookie"] = session.cookies
  }
  if extraHeaders then
    for k, v in pairs(extraHeaders) do headers[k] = v end
  end
  local response, _, _ = connection:request(method, url, body, contentType, headers)
  local newCookies = connection:getCookies()
  if newCookies and newCookies ~= "" then
    session.cookies = newCookies
  end
  return response
end

-- Currency-Format aus Shareview-HTML parsen: z.B. "GBX|10.0000|99|1|.|,|6"
-- Rückgabe: amountInGbp (Number), nativeCurrency ("GBP"|"GBX"|"USD"|...), nativeAmount (Number)
function parseCurrencyValue(raw)
  if not raw then return nil, nil, nil end
  local parts = {}
  for part in (raw .. "|"):gmatch("([^|]*)|") do
    table.insert(parts, part)
  end
  if #parts < 2 then return nil, nil, nil end
  local currency = trim(parts[1])
  local value = tonumber(parts[2])
  if not value then return nil, nil, nil end
  -- GBX = britische Pence; MoneyMoney rechnet in GBP
  if currency == "GBX" or currency == "GBp" then
    return value / 100, "GBX", value
  end
  return value, currency, value
end

-- Erste currencyChange-/currencyChangeIgnoreNative-Span finden, deren "original"-Sub-Span
-- den Native-Wert enthält. Rückgabe: native-Currency-String oder nil.
local function findFirstCurrencySpan(html, pattern)
  if not html then return nil end
  return html:match(pattern)
end

-- ============================================================================
-- WebBanking-Lifecycle
-- ============================================================================

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and (bankCode == "Shareview" or bankCode == "Equiniti Shareview")
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  connection = Connection()
  connection.language = "en-GB"
  connection.useragent = CONSTANTS.userAgent

  if step == 1 then
    return loginStep1(credentials)
  elseif step == 2 then
    return loginStep2(credentials)
  end
  return LoginFailed
end

-- ============================================================================
-- Login Step 1: Cookie-Import oder Username+DOB+Password POST
-- ============================================================================

function loginStep1(credentials)
  local rawUsername = credentials[1]
  local password = credentials[2]

  if not password or password == "" then
    return LoginFailed
  end

  if password:match("^COOKIE:") then
    return loginWithImportedCookies(password:sub(8))
  end

  local username, day, month, year = parseUsernameDob(rawUsername)
  if not username or username == "" then
    return "Bitte Username im Format \"username|TT.MM.JJJJ\" eingeben (Geburtsdatum erforderlich)."
  end
  if not day or not month or not year then
    return "Geburtsdatum fehlt. Username-Format: \"username|TT.MM.JJJJ\" (z.B. max.mustermann|01.01.1970)."
  end
  if day < 1 or day > 31 or month < 1 or month > 12 or year < 1900 or year > 2100 then
    return "Ungültiges Geburtsdatum. Format: TT.MM.JJJJ."
  end

  MM.printStatus("Shareview: Login-Seite laden...")
  local loginPage = requestHtml("GET", CONSTANTS.loginUrl)
  if not loginPage then
    return "Login fehlgeschlagen: Login-Seite nicht erreichbar."
  end

  if not extractHidden(loginPage, "__VIEWSTATE") then
    return "Login fehlgeschlagen: VIEWSTATE nicht gefunden (Seitenstruktur geändert?)."
  end

  MM.printStatus("Shareview: Zugangsdaten senden...")
  local formBody = buildFormBody(loginPage, {
    {"__EVENTTARGET", CONSTANTS.field.locateBtn},
    {"__EVENTARGUMENT", ""},
    {"CurrencyFeedUrl", "/7/Pages/CurrencyExchangeFeed.aspx?s=/7/Portfolio/default/en/anonymous/"},
    {"ctl00$IsCurrencyConversionAndFormattingEnabled", "true"},
    {"ctl00$CurrentCurrencyConversionSelection", "GBP"},
    {"ctl00$IsNativeCurrencyOptionSelected", "false"},
    {"ctl00$IsCurrencyConvertAndFormatPrivate", "false"},
    {CONSTANTS.field.username, username},
    {CONSTANTS.field.day, tostring(day)},
    {CONSTANTS.field.month, tostring(month)},
    {CONSTANTS.field.year, tostring(year)},
    {CONSTANTS.field.password, password}
  })

  local mfaPage = requestHtml("POST", CONSTANTS.loginUrl, formBody,
    "application/x-www-form-urlencoded",
    { ["Origin"] = CONSTANTS.baseUrl, ["Referer"] = CONSTANTS.loginUrl })

  if not mfaPage then
    return "Login fehlgeschlagen: Keine Antwort vom Server."
  end

  -- Erfolgsfall: bereits eingeloggt (kein MFA nötig — selten, aber möglich)
  if isLoggedInPage(mfaPage) then
    MM.printStatus("Shareview: Login ohne MFA erfolgreich.")
    return nil
  end

  -- Fehler-Erkennung: typische Login-Fehlermeldungen
  local loginError = extractLoginError(mfaPage)
  if loginError then
    return "Login fehlgeschlagen: " .. loginError
  end

  if not isMfaPage(mfaPage) then
    return "Login fehlgeschlagen: Unerwartete Antwort. Bitte Zugangsdaten und Geburtsdatum prüfen."
  end

  session.mfaHtml = mfaPage
  return {
    title = "Shareview Authentifizierung",
    challenge = "Bitte den 6-stelligen Authentication Code aus der Shareview-App oder E-Mail eingeben.",
    label = "Authentication Code"
  }
end

-- ============================================================================
-- Login Step 2: 6-stelligen MFA-Code senden
-- ============================================================================

function loginStep2(credentials)
  local code = credentials[1]
  if not code or not code:match("^%s*%d+%s*$") then
    return "Ungültiger Authentication Code: nur Ziffern erwartet."
  end
  code = trim(code)

  local mfaHtml = session.mfaHtml
  if not mfaHtml then
    return LoginFailed
  end

  local mfaSubmitField, mfaCodeField = findMfaFields(mfaHtml)
  if not mfaSubmitField or not mfaCodeField then
    return "MFA-Feld nicht gefunden (Seitenstruktur geändert?). Bitte Cookie-Import verwenden."
  end

  MM.printStatus("Shareview: Authentication Code senden...")
  local formBody = buildFormBody(mfaHtml, {
    {"__EVENTTARGET", mfaSubmitField},
    {"__EVENTARGUMENT", ""},
    {mfaCodeField, code}
  })

  local response = requestHtml("POST", CONSTANTS.loginUrl, formBody,
    "application/x-www-form-urlencoded",
    { ["Origin"] = CONSTANTS.baseUrl, ["Referer"] = CONSTANTS.loginUrl })

  session.mfaHtml = nil

  if not response then
    return "MFA fehlgeschlagen: Keine Antwort vom Server."
  end

  -- Bei OTP-Fehler bleibt die MFA-Seite stehen
  if response:match("Please enter a 6 digit Authentication Code")
     or response:match('id="otpErrorLabelWrapper"[^>]*>%s*<span>') then
    return "Authentication Code abgelehnt. Bitte erneut versuchen."
  end

  -- Erfolgsfall: ADFS/WS-Federation Auto-Post-Form folgen
  response = followAutoPostForms(response, 5)

  -- Holdings-Seite testen
  local holdings = requestHtml("GET", CONSTANTS.holdingsUrl)
  if holdings and isLoggedInPage(holdings) then
    session.holdingsHtml = holdings
    MM.printStatus("Shareview: Login erfolgreich.")
    return nil
  end

  if response and response:lower():match("authentication code") then
    return "Authentication Code abgelehnt. Bitte erneut versuchen."
  end
  return "MFA fehlgeschlagen. Bitte Cookie-Import verwenden."
end

-- Browser-Auto-Submit von <form action="..." method="POST">-Pages nachstellen
-- (WS-Federation/SAML-Federation: Server liefert eine Page mit hiddenform,
-- die via JS submit()'d wird; curl macht das nicht von selbst).
function followAutoPostForms(html, maxHops)
  maxHops = maxHops or 5
  for hop = 1, maxHops do
    if not html or html == "" then return html end
    local action = html:match('<form[^>]-method="POST"[^>]-action="([^"]+)"')
                 or html:match('<form[^>]-action="([^"]+)"[^>]-method="POST"')
                 or html:match('<form[^>]-method="post"[^>]-action="([^"]+)"')
    if not action then return html end

    -- Indikator: Auto-Post (entweder body onload oder Title "Working...")
    local isAutoPost = html:match("document%.forms%[0%]%.submit") ~= nil
                       or html:match("<title[^>]*>%s*Working") ~= nil
                       or html:match('<form[^>]+name="hiddenform"') ~= nil
    if not isAutoPost then return html end

    action = htmlDecode(action)
    local parts = {}
    -- ADFS/SAML-Forms (XHTML <input ... />) enthalten im wresult-Value
    -- literal '>'/'/>' (HTML5-kompatibel), daher matcht ein Pattern wie
    -- '<input[^>]+>' oder '<input.-/>' das Tag falsch.
    -- Robust: direkt name="X" value="..." /> als Pair extrahieren
    -- (non-greedy value bis zum nächsten '"' direkt vor '/>').
    -- Pre-Filter auf die hiddenform-Section, damit wir keine fremden Inputs einsammeln.
    local formStart = html:find('<form[^>]-name="hiddenform"')
                    or html:find('<form[^>]+method="POST"')
                    or 1
    local formEnd = html:find("</form>", formStart, true) or #html
    local formHtml = html:sub(formStart, formEnd)

    for name, value in formHtml:gmatch('name="([^"]+)"%s+value="(.-)"%s*/>') do
      table.insert(parts, urlencode(name) .. "=" .. urlencode(htmlDecode(value)))
    end
    local body = table.concat(parts, "&")

    MM.printStatus(string.format("Shareview: Federation-Hop %d -> %s", hop, action))
    html = requestHtml("POST", action, body, "application/x-www-form-urlencoded", {
      ["Origin"] = CONSTANTS.baseUrl,
      ["Referer"] = CONSTANTS.baseUrl .. "/"
    })
  end
  return html
end

-- ============================================================================
-- Cookie-Import-Modus
-- ============================================================================

function loginWithImportedCookies(cookieString)
  MM.printStatus("Shareview: Importierte Cookies verwenden...")
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

  session.cookies = formatted
  local holdings = requestHtml("GET", CONSTANTS.holdingsUrl)
  if not holdings then
    return "Cookie-Import fehlgeschlagen: Holdings-Seite nicht erreichbar."
  end
  if not isLoggedInPage(holdings) then
    return "Cookie-Import fehlgeschlagen. Cookies abgelaufen — bitte erneut exportieren."
  end

  session.holdingsHtml = holdings
  MM.printStatus("Shareview: Cookie-Import erfolgreich.")
  return nil
end

-- ============================================================================
-- Login-Status-Erkennung
-- ============================================================================

function isLoggedInPage(html)
  if not html then return false end
  if html:match('id="TotalIndicativeValue"') then return true end
  if html:match("My Holdings Summary") then return true end
  if html:find("holdingssummary", 1, true) and html:match("BaseHoldingSummaryUC1") then
    return true
  end
  return false
end

function isMfaPage(html)
  if not html then return false end
  return (html:lower():find("authentication code", 1, true) ~= nil)
end

function extractLoginError(html)
  if not html then return nil end
  local err = html:match('class="[^"]*ErrorMessage[^"]*"[^>]*>%s*([^<]-)%s*<')
              or html:match('id="[^"]*lblError[^"]*"[^>]*>%s*([^<]-)%s*<')
              or html:match('id="[^"]*ErrorLabel[^"]*"[^>]*>%s*([^<]-)%s*<')
  if err and err ~= "" then
    err = trim(htmlDecode(err))
    if err ~= "" then return err end
  end
  return nil
end

function findMfaFields(html)
  if not html then return nil, nil end
  -- OTP-Eingabefeld endet exakt auf "txtVerificationCode" / "VerificationCode"
  -- (wichtig: Eingabefeld zuerst spezifisch matchen, BEVOR ähnliche Submit-Button-Namen wie "btnSubmitOtp" greifen)
  local codeField = html:match('name="([^"]-txtVerificationCode)"')
                   or html:match('name="([^"]-VerificationCode)"')
                   or html:match('name="([^"]-txtOtp)"')
                   or html:match('name="([^"]-AuthenticationCode)"')
  -- Submit-Button: ASP.NET-Postback-Target (wird per __EVENTTARGET adressiert)
  local submitField = html:match('name="([^"]-btnSubmitOtp)"')
                     or html:match('name="([^"]-btnVerifyOtp)"')
                     or html:match('name="([^"]-btnVerify)"')
  return submitField, codeField
end

-- ============================================================================
-- ListAccounts: konsolidiertes Portfolio-Konto
-- ============================================================================

function ListAccounts(knownAccounts)
  MM.printStatus("Shareview: Konten ermitteln...")
  if not session.holdingsHtml then
    session.holdingsHtml = requestHtml("GET", CONSTANTS.holdingsUrl)
  end
  if not session.holdingsHtml or not isLoggedInPage(session.holdingsHtml) then
    return "Holdings-Seite nicht zugänglich. Session abgelaufen?"
  end

  local accounts = {
    {
      name = "Shareview Portfolio",
      accountNumber = "shareview-portfolio",
      portfolio = true,
      currency = "GBP",
      type = AccountTypePortfolio,
      bankCode = "Shareview"
    }
  }
  return accounts
end

-- ============================================================================
-- RefreshAccount: Holdings aus HTML extrahieren
-- ============================================================================

function RefreshAccount(account, since)
  MM.printStatus("Shareview: Portfolio aktualisieren...")
  if not session.holdingsHtml then
    session.holdingsHtml = requestHtml("GET", CONSTANTS.holdingsUrl)
  end
  if not session.holdingsHtml then
    return "Holdings-Seite nicht erreichbar."
  end

  local html = session.holdingsHtml
  local securities = parseHoldings(html)
  local balance, balanceCurrency = parseTotalIndicativeValue(html)

  if not balance or balance == 0 then
    -- Fallback: Summe aus Einzelpositionen bilden
    balance = 0
    for _, sec in ipairs(securities) do
      balance = balance + (sec.amount or 0)
    end
    balanceCurrency = balanceCurrency or "GBP"
  end

  return {
    balance = balance,
    securities = securities
  }
end

function parseTotalIndicativeValue(html)
  if not html then return nil, nil end
  local block = html:match('id="TotalIndicativeValue"[^>]*>%s*<span[^>]*>([^<]+)<')
  if not block then
    block = html:match('id="TotalIndicativeValue".-currencyChange[^>]*>([^<]+)<')
  end
  if not block then return nil, nil end
  local amount, native = parseCurrencyValue(block)
  return amount, native and (native == "GBX" and "GBP" or native) or "GBP"
end

function parseHoldings(html)
  local securities = {}
  if not html then return securities end

  -- Alle <tr>-Zeilen mit summaryDataItemRow extrahieren
  for row in html:gmatch('<tr[^>]*summaryDataItemRow[^>]*>(.-)</tr>') do
    local sec = parseHoldingRow(row)
    if sec then table.insert(securities, sec) end
  end
  return securities
end

function parseHoldingRow(row)
  if not row then return nil end

  -- Name + Sub-Account-Beschreibung aus erstem <td headers="holding">
  local holdingCell = row:match('headers="holding"[^>]*>(.-)</td>') or ""
  local name = holdingCell:match("<strong>%s*([^<]+)%s*</strong>") or ""
  local subAccount = holdingCell:match("</strong>%s*<br/?>%s*([^<]+)")
  if subAccount then subAccount = trim(htmlDecode(subAccount)) end
  name = trim(htmlDecode(name))
  if name == "" then return nil end

  local fullName = name
  if subAccount and subAccount ~= "" and not subAccount:match("Shareholder Ref") then
    fullName = name .. " (" .. subAccount .. ")"
  end

  -- Shareholder Ref No → securityNumber
  local shareholderRef = holdingCell:match("Shareholder Ref No:%s*([%w%-]+)") or ""
  shareholderRef = trim(shareholderRef)

  -- ISIN aus Morningstar-URL extrahieren (sofern vorhanden).
  -- Lua-Patterns kennen kein {n}, daher per Längenprüfung validieren.
  local isinCandidate = row:match("externalid=([A-Z0-9]+)") or ""
  local isin = ""
  if #isinCandidate == 12 and isinCandidate:match("^[A-Z][A-Z][A-Z0-9]+[0-9]$") then
    isin = isinCandidate
  end

  -- Quantity aus <bdo class="PrivacyAware">N</bdo>
  local quantityCell = row:match('headers="quantity"[^>]*>(.-)</td>') or ""
  local quantityStr = quantityCell:match('<bdo[^>]*>%s*([%d%.,]+)%s*</bdo>')
                     or stripTags(quantityCell)
  quantityStr = (quantityStr or ""):gsub(",", "")
  local quantity = tonumber(quantityStr) or 0

  -- Preis aus headers="price" → currencyChange-Span (Format: "GBX|10.0000|...")
  local priceCell = row:match('headers="price"[^>]*>(.-)</td>') or ""
  local priceRaw = priceCell:match('<span class="original">([^<]+)</span>')
                   or priceCell:match('currencyChange[^>]*>([^<]+)<span')
                   or priceCell:match('currencyChangeIgnoreNative[^>]*>([^<]+)<span')
  local pricePerShare, priceNative = parseCurrencyValue(priceRaw)

  -- Wert aus headers="value"
  local valueCell = row:match('headers="value"[^>]*>(.-)</td>') or ""
  local valueRaw = valueCell:match('<span class="original">([^<]+)</span>')
                   or valueCell:match('currencyChange[^>]*>([^<]+)<span')
                   or valueCell:match('currencyChangeIgnoreNative[^>]*>([^<]+)<span')
  local amount, valueNative = parseCurrencyValue(valueRaw)

  if not amount and pricePerShare and quantity > 0 then
    amount = pricePerShare * quantity
  end

  -- GBX → GBP-Normalisierung erfolgt bereits in parseCurrencyValue
  local currencyOfPrice = priceNative
  if currencyOfPrice == "GBX" or currencyOfPrice == "GBp" then currencyOfPrice = "GBP" end
  if not currencyOfPrice or currencyOfPrice == "" then currencyOfPrice = "GBP" end

  local currencyOfAmount = valueNative
  if currencyOfAmount == "GBX" or currencyOfAmount == "GBp" then currencyOfAmount = "GBP" end
  if not currencyOfAmount or currencyOfAmount == "" then currencyOfAmount = "GBP" end

  return {
    name = fullName,
    isin = isin,
    securityNumber = shareholderRef,
    quantity = quantity,
    price = pricePerShare or 0,
    currencyOfPrice = currencyOfPrice,
    amount = amount or 0,
    currencyOfOriginalAmount = currencyOfAmount
  }
end

-- ============================================================================
-- EndSession
-- ============================================================================

function EndSession()
  if session.cookies and session.cookies ~= "" then
    pcall(function()
      requestHtml("GET", CONSTANTS.logoutUrl)
    end)
  end
  session = { cookies = "" }
end

-- SIGNATURE: <unsigned>
