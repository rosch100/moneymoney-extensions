---@diagnostic disable: undefined-global
--
-- Equiniti Shareview Portfolio (XPath-Variante) — MoneyMoney Web Banking Extension
-- https://portfolio.shareview.co.uk
--
-- Diese Variante ersetzt das manuelle Pattern-Parsing aus Shareview.lua
-- durch MoneyMoneys integrierte HTML/XPath-API (HTML(...), :xpath, :submit).
-- Vorteile:
--   * Robust gegen ASP.NET-VIEWSTATE-Änderungen (alle hidden inputs werden
--     vom :submit()-Builder automatisch eingesammelt).
--   * Verträglich mit literalen '>'/'/>' im SAML-`wresult`-Wert (echter
--     HTML-Parser statt fragiler Lua-Patterns).
--   * Kürzerer und klarerer Code für Form-Handling.
-- Nachteile:
--   * Nur in MoneyMoney verifizierbar — der lokale curl-Test-Harness
--     (test_shareview_live.lua) kann HTML(...) und :submit() nicht stubben.
--   * Manche XPath-Locator hängen von der API-Version von MoneyMoney ab;
--     bei Änderungen ggf. Locator-Schreibweise nachziehen.
-- Service-Name "Shareview-XPath" → parallel zu Shareview installierbar.
--
-- Login-Flow:
--   Step 1: GET Login.aspx → Form via XPath ausfüllen (Username, DOB-Selects,
--           Passwort, __EVENTTARGET) → :submit()
--   Step 2: 6-stelliger OTP in MFA-Form → :submit() → ADFS/SAML-Federation-Hops
--           via :submit() (HTML/XPath erkennt die hiddenform automatisch)
--           → Holdings.aspx
--

WebBanking {
  version = "1.0.0",
  url = "https://portfolio.shareview.co.uk",
  services = {"Shareview-XPath"},
  description = "Equiniti Shareview Portfolio (XPath-Variante; experimentell, nutzt HTML/XPath/submit-API)"
}

local CONSTANTS = {
  baseUrl = "https://portfolio.shareview.co.uk",
  loginUrl = "https://portfolio.shareview.co.uk/7/Portfolio/default/en/anonymous/Pages/Login.aspx",
  holdingsUrl = "https://portfolio.shareview.co.uk/7/portfolio/default/en/Active/Pages/holdingssummary.aspx",
  logoutUrl = "https://portfolio.shareview.co.uk/7/Auth/Logoff.aspx",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
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

-- DOB aus username-Feld parsen: "username|DD.MM.YYYY"
local function parseUsernameDob(rawUsername)
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

-- Currency-Format aus Shareview-HTML parsen: z.B. "GBX|10.0000|99|1|.|,|6"
-- Rückgabe: amountInGbp (Number), nativeCurrency ("GBP"|"GBX"|...), nativeAmount (Number)
local function parseCurrencyValue(raw)
  if not raw then return nil, nil, nil end
  local parts = {}
  for part in (raw .. "|"):gmatch("([^|]*)|") do
    table.insert(parts, part)
  end
  if #parts < 2 then return nil, nil, nil end
  local currency = trim(parts[1])
  local value = tonumber(parts[2])
  if not value then return nil, nil, nil end
  if currency == "GBX" or currency == "GBp" then
    return value / 100, "GBX", value
  end
  return value, currency, value
end

-- ============================================================================
-- HTTP-Wrapper (Connection:request mit Header-Defaults)
-- ============================================================================

local function get(url)
  return connection:get(url)
end

-- Submitted ein Form-Element (HTML/XPath-Node) und liefert den Response-Content.
-- :submit() returnt den 5-Tupel (method, url, body, contentType, headers),
-- den Connection:request konsumiert.
local function submitForm(formNode)
  local method, url, body, contentType, headers = formNode:submit()
  return connection:request(method, url, body, contentType, headers)
end

-- ============================================================================
-- WebBanking-Lifecycle
-- ============================================================================

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and (bankCode == "Shareview-XPath")
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  if step == 1 then
    connection = Connection()
    connection.language = "en-GB"
    connection.useragent = CONSTANTS.userAgent
    return loginStep1(credentials)
  elseif step == 2 then
    return loginStep2(credentials)
  end
  return LoginFailed
end

-- ============================================================================
-- Login Step 1: Cookie-Import oder Username+DOB+Password via HTML/XPath
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
  local content = get(CONSTANTS.loginUrl)
  if not content or content == "" then
    return "Login fehlgeschlagen: Login-Seite nicht erreichbar."
  end

  local html = HTML(content)

  -- Form-Felder ausfüllen. Die ASP.NET-IDs enthalten dynamische GUIDs;
  -- daher arbeiten wir mit `contains(@id, "...")`-Substring-Matches:
  --   Username: <input ... id="...UserLocate2UC1_rpt_ctl00_txtInput">
  --   Password: <input ... id="...UserLocate2UC1_rpt_ctl02_txtInput">
  --   DOB:      <select ... id="...UserLocate2UC1_rpt_ctl01_dtInput_drpDay">
  --             (analog drpMonth, drpYear)
  html:xpath('//input[contains(@id, "UserLocate2UC1_rpt_ctl00_txtInput")]')
      :attr("value", username)
  html:xpath('//input[contains(@id, "UserLocate2UC1_rpt_ctl02_txtInput")]')
      :attr("value", password)

  -- DOB-Dropdowns: Für jedes <select> die passende <option> als selected markieren.
  html:xpath('//select[contains(@id, "drpDay")]/option[@value="' .. day .. '"]')
      :attr("selected", "selected")
  html:xpath('//select[contains(@id, "drpMonth")]/option[@value="' .. month .. '"]')
      :attr("selected", "selected")
  html:xpath('//select[contains(@id, "drpYear")]/option[@value="' .. year .. '"]')
      :attr("selected", "selected")

  -- ASP.NET-Postback: __EVENTTARGET muss auf den Locate-Button zeigen.
  -- Wir holen den Button-Namen direkt aus dem DOM, statt die ID hart zu codieren.
  local locateBtnName = html:xpath('//input[contains(@id, "btnLocate") or contains(@name, "btnLocate")]')
                            :attr("name")
  html:xpath('//input[@name="__EVENTTARGET"]'):attr("value", locateBtnName or "")

  MM.printStatus("Shareview: Zugangsdaten senden...")
  local mfaContent = submitForm(html:xpath('//form[@id="aspnetForm"]'))
  if not mfaContent or mfaContent == "" then
    return "Login fehlgeschlagen: Keine Antwort vom Server."
  end

  -- Erfolgsfall: bereits eingeloggt (selten; OTP-Flow ist Standard)
  if isLoggedInPage(mfaContent) then
    session.holdingsHtmlString = mfaContent
    MM.printStatus("Shareview: Login ohne MFA erfolgreich.")
    return nil
  end

  local loginError = extractLoginError(HTML(mfaContent))
  if loginError then
    return "Login fehlgeschlagen: " .. loginError
  end

  if not isMfaPage(mfaContent) then
    return "Login fehlgeschlagen: Unerwartete Antwort. Bitte Zugangsdaten und Geburtsdatum prüfen."
  end

  session.mfaHtmlString = mfaContent
  return {
    title = "Shareview Authentifizierung",
    challenge = "Bitte den 6-stelligen Authentication Code aus der Shareview-App oder E-Mail eingeben.",
    label = "Authentication Code"
  }
end

-- ============================================================================
-- Login Step 2: 6-stelligen OTP senden, Federation-Hops via :submit()
-- ============================================================================

function loginStep2(credentials)
  local code = credentials[1]
  if not code or not code:match("^%s*%d+%s*$") then
    return "Ungültiger Authentication Code: nur Ziffern erwartet."
  end
  code = trim(code)

  if not session.mfaHtmlString then
    return LoginFailed
  end

  local mfaHtml = HTML(session.mfaHtmlString)

  -- OTP-Eingabefeld (typischer Name endet auf "txtVerificationCode")
  mfaHtml:xpath('//input[contains(@id, "txtVerificationCode") or contains(@name, "txtVerificationCode")]')
         :attr("value", code)

  -- Submit-Button als __EVENTTARGET setzen (wieder ASP.NET-Postback)
  local submitBtnName = mfaHtml:xpath('//input[contains(@id, "btnSubmitOtp") or contains(@name, "btnSubmitOtp")]')
                               :attr("name")
  mfaHtml:xpath('//input[@name="__EVENTTARGET"]'):attr("value", submitBtnName or "")

  MM.printStatus("Shareview: Authentication Code senden...")
  local otpResponse = submitForm(mfaHtml:xpath('//form[@id="aspnetForm"]'))

  session.mfaHtmlString = nil

  if not otpResponse then
    return "MFA fehlgeschlagen: Keine Antwort vom Server."
  end

  -- OTP abgelehnt → MFA-Page bleibt sichtbar
  if otpResponse:match("Please enter a 6 digit Authentication Code")
     or otpResponse:match('id="otpErrorLabelWrapper"[^>]*>%s*<span>') then
    return "Authentication Code abgelehnt. Bitte erneut versuchen."
  end

  -- Federation-Hops folgen (WS-Federation/SAML 1.1).
  -- :submit() der hiddenform sammelt alle hidden inputs (incl. wresult mit
  -- literalen '>'-Zeichen) korrekt — kein manuelles Pattern-Parsing nötig.
  otpResponse = followFederationHops(otpResponse, 5)

  -- Holdings-Test: erst nach erfolgreichem ADFS-Round-Trip ist FedAuth gesetzt
  local holdings = get(CONSTANTS.holdingsUrl)
  if holdings and isLoggedInPage(holdings) then
    session.holdingsHtmlString = holdings
    MM.printStatus("Shareview: Login erfolgreich.")
    return nil
  end

  if otpResponse and otpResponse:lower():match("authentication code") then
    return "Authentication Code abgelehnt. Bitte erneut versuchen."
  end
  return "MFA fehlgeschlagen. Bitte Cookie-Import verwenden."
end

-- Browser-Auto-Submit von <form name="hiddenform" method="POST">-Pages
-- nachstellen (ADFS / WS-Federation). HTML/XPath/submit liest die Form
-- als echtes DOM und sammelt alle hidden inputs zuverlässig ein.
function followFederationHops(content, maxHops)
  maxHops = maxHops or 5
  for hop = 1, maxHops do
    if not content or content == "" then return content end
    local html = HTML(content)
    local form = html:xpath('//form[@name="hiddenform"]')
    -- Heuristik: nur weiterspringen, wenn die Page eine Auto-Post-Form ist
    local title = html:xpath('//title'):text() or ""
    local isAutoPost = title:match("Working") ~= nil
                       or content:match("document%.forms%[0%]%.submit") ~= nil
                       or content:match('<form[^>]+name="hiddenform"') ~= nil
    if not isAutoPost then return content end
    if not form then return content end

    MM.printStatus(string.format("Shareview: Federation-Hop %d", hop))
    content = submitForm(form)
  end
  return content
end

-- ============================================================================
-- Cookie-Import-Modus (unverändert zur Pattern-Variante)
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

  -- HTTP-Wrapper mit explizitem Cookie-Header (Connection:get nutzt
  -- ansonsten den eigenen Cookie-Jar).
  local response = connection:request("GET", CONSTANTS.holdingsUrl, nil, nil, {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-GB,en;q=0.9",
    ["Cookie"] = formatted
  })

  if not response or not isLoggedInPage(response) then
    return "Cookie-Import fehlgeschlagen. Cookies abgelaufen — bitte erneut exportieren."
  end

  session.cookies = formatted
  session.holdingsHtmlString = response
  MM.printStatus("Shareview: Cookie-Import erfolgreich.")
  return nil
end

-- ============================================================================
-- Login-Status / Fehler-Erkennung
-- ============================================================================

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
  return (content:lower():find("authentication code", 1, true) ~= nil)
end

-- HTML-Node-basierte Fehler-Extraktion
function extractLoginError(htmlNode)
  if not htmlNode then return nil end
  -- Verschiedene Fehler-Container der Shareview-Login-Page
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

-- ============================================================================
-- ListAccounts: konsolidiertes Portfolio-Konto
-- ============================================================================

function ListAccounts(knownAccounts)
  MM.printStatus("Shareview: Konten ermitteln...")
  if not session.holdingsHtmlString then
    session.holdingsHtmlString = get(CONSTANTS.holdingsUrl)
  end
  if not session.holdingsHtmlString or not isLoggedInPage(session.holdingsHtmlString) then
    return "Holdings-Seite nicht zugänglich. Session abgelaufen?"
  end

  return {
    {
      name = "Shareview Portfolio",
      accountNumber = "shareview-portfolio",
      portfolio = true,
      currency = "GBP",
      type = AccountTypePortfolio,
      bankCode = "Shareview-XPath"
    }
  }
end

-- ============================================================================
-- RefreshAccount: Holdings aus HTML extrahieren (XPath, mit Pattern-Fallback)
-- ============================================================================

function RefreshAccount(account, since)
  MM.printStatus("Shareview: Portfolio aktualisieren...")
  if not session.holdingsHtmlString then
    session.holdingsHtmlString = get(CONSTANTS.holdingsUrl)
  end
  if not session.holdingsHtmlString then
    return "Holdings-Seite nicht erreichbar."
  end

  local htmlString = session.holdingsHtmlString
  local securities = parseHoldings(htmlString)
  local balance, balanceCurrency = parseTotalIndicativeValue(htmlString)

  if not balance or balance == 0 then
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

function parseTotalIndicativeValue(htmlString)
  if not htmlString then return nil, nil end
  local block = htmlString:match('id="TotalIndicativeValue"[^>]*>%s*<span[^>]*>([^<]+)<')
  if not block then
    block = htmlString:match('id="TotalIndicativeValue".-currencyChange[^>]*>([^<]+)<')
  end
  if not block then return nil, nil end
  local amount, native = parseCurrencyValue(block)
  return amount, native and (native == "GBX" and "GBP" or native) or "GBP"
end

-- Holdings-Tabellen-Parsing: Pattern-basiert (gleiche Logik wie Shareview.lua),
-- da die Holdings-Page stabil ist und das Parsing dort bereits live verifiziert.
-- Ein XPath-Refactor an dieser Stelle würde den Mehrwert nur marginal erhöhen.
function parseHoldings(htmlString)
  local securities = {}
  if not htmlString then return securities end
  for row in htmlString:gmatch('<tr[^>]*summaryDataItemRow[^>]*>(.-)</tr>') do
    local sec = parseHoldingRow(row)
    if sec then table.insert(securities, sec) end
  end
  return securities
end

function parseHoldingRow(row)
  if not row then return nil end

  local function stripTags(s)
    if not s then return "" end
    return trim(htmlDecode((s:gsub("<[^>]+>", " "):gsub("%s+", " "))))
  end

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

  local shareholderRef = trim(holdingCell:match("Shareholder Ref No:%s*([%w%-]+)") or "")

  -- ISIN aus Morningstar-URL (?externalid=GB00...)
  local isinCandidate = row:match("externalid=([A-Z0-9]+)") or ""
  local isin = ""
  if #isinCandidate == 12 and isinCandidate:match("^[A-Z][A-Z][A-Z0-9]+[0-9]$") then
    isin = isinCandidate
  end

  local quantityCell = row:match('headers="quantity"[^>]*>(.-)</td>') or ""
  local quantityStr = quantityCell:match('<bdo[^>]*>%s*([%d%.,]+)%s*</bdo>') or stripTags(quantityCell)
  quantityStr = (quantityStr or ""):gsub(",", "")
  local quantity = tonumber(quantityStr) or 0

  local priceCell = row:match('headers="price"[^>]*>(.-)</td>') or ""
  local priceRaw = priceCell:match('<span class="original">([^<]+)</span>')
                   or priceCell:match('currencyChange[^>]*>([^<]+)<span')
                   or priceCell:match('currencyChangeIgnoreNative[^>]*>([^<]+)<span')
  local pricePerShare, priceNative = parseCurrencyValue(priceRaw)

  local valueCell = row:match('headers="value"[^>]*>(.-)</td>') or ""
  local valueRaw = valueCell:match('<span class="original">([^<]+)</span>')
                   or valueCell:match('currencyChange[^>]*>([^<]+)<span')
                   or valueCell:match('currencyChangeIgnoreNative[^>]*>([^<]+)<span')
  local amount, valueNative = parseCurrencyValue(valueRaw)

  if not amount and pricePerShare and quantity > 0 then
    amount = pricePerShare * quantity
  end

  local function normalizeCurrency(c)
    if c == "GBX" or c == "GBp" then return "GBP" end
    if not c or c == "" then return "GBP" end
    return c
  end

  return {
    name = fullName,
    isin = isin,
    securityNumber = shareholderRef,
    quantity = quantity,
    price = pricePerShare or 0,
    currencyOfPrice = normalizeCurrency(priceNative),
    amount = amount or 0,
    currencyOfOriginalAmount = normalizeCurrency(valueNative)
  }
end

-- ============================================================================
-- EndSession
-- ============================================================================

function EndSession()
  if connection then
    pcall(function() get(CONSTANTS.logoutUrl) end)
  end
  session = { cookies = "" }
  connection = nil
end

-- SIGNATURE: <unsigned>
