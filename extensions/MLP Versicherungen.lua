-- MLP Versicherungen — MoneyMoney Web Banking Extension
-- https://kundenportal.mlp.de
-- API: https://moneymoney.app/api/webbanking/
--
-- Authentifizierung: Cookie-Import (VUSESSIONID von vue.mlp.de erforderlich)
-- Version: 1.00

WebBanking{
  version     = 1.00,
  url         = "https://kundenportal.mlp.de",
  services    = {"MLP Versicherungen"},
  description = "MLP Versicherungen - Cookie-Import (VUSESSIONID von vue.mlp.de)"
}

local CONSTANTS = {
  baseUrl           = "https://kundenportal.mlp.de",
  authBaseUrl       = "https://financepilot-pe.mlp.de",
  loginPageUrl      = "https://kundenportal.mlp.de/login",
  userAgent         = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15"
}

local connection
local session = {
  contracts = {},
  state = nil,
  username = nil,
  password = nil,
  mfaToken = nil,
  sessionCookies = {}
}

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "MLP Versicherungen"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  if step == 1 then
    return loginStep1(credentials, interactive)
  end

  if session.state == "awaitingMfa" then
    return submitMfaCode(credentials[1])
  end

  return LoginFailed
end

function loginStep1(credentials, interactive)
  local username = credentials[1]
  local password = credentials[2]

  connection = Connection()
  connection.language = "de-DE"
  connection.useragent = CONSTANTS.userAgent

  session.username = username
  session.password = password
  session.state = nil
  session.sessionCookies = {}

  MM.printStatus("MLP: Initialisiere Session...")

  collectSessionCookies()

  local initContent = connection:get(CONSTANTS.authBaseUrl .. "/services_auth/auth-backend/public/session-lifetime-extension.html")
  if initContent then
    collectSessionCookies()
  end

  if password and password:match("^COOKIE:") then
    parseCookieString(password:sub(8))
    return tryCookieAuth()
  end

  if not username or username == "" or not password or password == "" then
    return tryCookieAuth()
  end

  MM.printStatus("MLP: Authentifiziere mit Username/Passwort...")
  local loginResult = performLogin(username, password)

  if loginResult.success then
    session.state = nil
    if loadContracts() then
      return nil
    else
      return "Login erfolgreich, aber keine Versicherungsverträge gefunden."
    end
  end

  if loginResult.requiresMfa then
    session.state = "awaitingMfa"
    session.mfaToken = loginResult.mfaToken
    return {
      title     = "SecureGo Plus Bestätigung",
      challenge = "Bitte bestätigen Sie den Login in Ihrer SecureGo Plus App auf Ihrem Smartphone.\n\nÖffnen Sie die SecureGo Plus App und bestätigen Sie die Push-Benachrichtigung.",
      label     = "TAN (falls Push nicht funktioniert)"
    }
  end

  if loginResult.error and (loginResult.error:find("403") or loginResult.error:find("JOSE")) then
    return tryCookieAuth()
  end

  return loginResult.error or "Login fehlgeschlagen."
end

function tryCookieAuth()
  local hasVuSession = session.sessionCookies.VUSESSIONID and session.sessionCookies.VUSESSIONID ~= ""

  if not hasVuSession then
    local cookieHeader = buildCookieHeader()
    if cookieHeader == "" then
      return "Cookie-Import erforderlich:\n\n" ..
             "1. Melden Sie sich im Browser am MLP Kundenportal an\n" ..
             "2. Öffnen Sie die Vertragsübersicht (damit vue.mlp.de geladen wird)\n" ..
             "3. DevTools → Application → Cookies → https://vue.mlp.de\n" ..
             "4. Kopieren Sie VUSESSIONID und BIGipServervue.mlp.de\n" ..
             "5. Fügen Sie sie in MoneyMoney als 'Cookies' ein (Format: Name=Wert; Name2=Wert2)"
    else
      return "Cookie-Import: VUSESSIONID fehlt\n\n" ..
             "Für die MLP Versicherungen-API wird VUSESSIONID von vue.mlp.de benötigt.\n\n" ..
             "Bitte stellen Sie sicher, dass Sie:\n" ..
             "1. Am MLP Kundenportal angemeldet sind\n" ..
             "2. Die Vertragsübersicht geöffnet haben (für vue.mlp.de Cookies)\n" ..
             "3. VUSESSIONID aus https://vue.mlp.de kopiert haben"
    end
  end

  MM.printStatus("MLP: Versuche Authentifizierung mit Cookies...")

  if isAuthenticated() then
    if loadContracts() then
      return nil
    else
      return "Authentifiziert, aber keine Versicherungsverträge gefunden."
    end
  end

  return "Cookie-Authentifizierung fehlgeschlagen.\n\n" ..
         "Mögliche Ursachen:\n" ..
         "- Cookies sind abgelaufen (Session nur kurze Zeit gültig)\n" ..
         "- VUSESSIONID fehlt oder ist ungültig\n" ..
         "- SSL-Zertifikat für vue.mlp.de nicht bestätigt\n\n" ..
         "Bitte frische Cookies aus dem Browser exportieren."
end

function performLogin(username, password)
  local loginPayload = {
    username = username,
    password = password,
    deviceInfo = { deviceType = "BROWSER", userAgent = CONSTANTS.userAgent }
  }

  local jsonBody = encodeJson(loginPayload)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json, text/plain, */*",
    ["Origin"] = "https://financepilot-pe.mlp.de",
    ["Referer"] = "https://financepilot-pe.mlp.de/"
  }

  local cookieHeader = buildCookieHeader()
  if cookieHeader ~= "" then
    headers["Cookie"] = cookieHeader
  end

  local content = connection:request(
    "POST",
    CONSTANTS.authBaseUrl .. "/services_auth/auth-backend/api/authentication/login",
    jsonBody,
    "application/json",
    headers
  )

  if not content then
    return { success = false, error = "Keine Antwort vom Login-Server." }
  end

  collectSessionCookies()

  if content:find('"error":') and content:find("403") then
    return { success = false, error = "Authentifizierung fehlgeschlagen (403). Die API erwartet möglicherweise verschlüsselte Credentials (JOSE/JWE)." }
  end

  local response = parseJson(content)
  if not response then
    if content:find("challenge") or content:find("mfa") or content:find("tan") then
      return { success = false, requiresMfa = true, mfaToken = "detected" }
    end
    if isAuthenticated() then
      return { success = true }
    end
    return { success = false, error = "Ungültige Server-Antwort." }
  end

  if response.challengeType or response.mfaRequired or response.requiresSecondFactor then
    return { success = false, requiresMfa = true, mfaToken = response.challengeToken }
  end

  if response.error or response.errorMessage then
    return { success = false, error = response.errorMessage or response.error }
  end

  if response.success or response.authenticated or isAuthenticated() then
    return { success = true }
  end

  return { success = false, error = "Login-Status unbekannt." }
end

function submitMfaCode(tanCode)
  if not session.mfaToken then
    return "MFA-Session abgelaufen. Bitte neu einloggen."
  end

  MM.printStatus("MLP: Übermittle MFA...")

  local mfaPayload = {
    challengeToken = session.mfaToken,
    tan = tanCode and trim(tanCode) or nil,
    confirmPush = not tanCode or trim(tanCode) == ""
  }

  local jsonBody = encodeJson(mfaPayload)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json"
  }

  local cookieHeader = buildCookieHeader()
  if cookieHeader ~= "" then
    headers["Cookie"] = cookieHeader
  end

  local content = connection:request(
    "POST",
    CONSTANTS.authBaseUrl .. "/services_auth/auth-backend/api/authentication/mfa",
    jsonBody,
    "application/json",
    headers
  )

  if not content then
    return "Keine Antwort bei MFA."
  end

  collectSessionCookies()

  local response = parseJson(content)
  if not response then
    if isAuthenticated() then
      session.state = nil
      if loadContracts() then return nil end
    end
    return "Ungültige MFA-Antwort."
  end

  if response.error then
    session.state = "awaitingMfa"
    return {
      title = "SecureGo Plus",
      challenge = "Fehler: " .. (response.errorMessage or response.error) .. "\n\nBitte erneut versuchen:",
      label = "TAN"
    }
  end

  if response.success or response.authenticated then
    session.state = nil
    if loadContracts() then
      return nil
    else
      return "MFA erfolgreich, aber keine Vertragsdaten."
    end
  end

  if response.pending or response.waiting then
    session.state = "awaitingMfa"
    return {
      title = "SecureGo Plus",
      challenge = "Warte auf Bestätigung...\n\nBitte in der App bestätigen oder TAN eingeben:",
      label = "TAN"
    }
  end

  return "Unbekannter MFA-Status."
end

function collectSessionCookies()
  local success, cookies = pcall(function()
    return connection:getCookies()
  end)
  if success and cookies and cookies ~= "" then
    collectSessionCookiesFromText(cookies)
  end
end

function collectSessionCookiesFromText(cookieText)
  if not cookieText then return end

  local jsession = cookieText:match("JSESSIONID=([^;,%s]+)")
  if jsession then session.sessionCookies.JSESSIONID = jsession end

  local casSession = cookieText:match("CAS_SESSION=([^;,%s]+)")
  if casSession then session.sessionCookies.CAS_SESSION = casSession end

  local casSSession = cookieText:match("CAS_S_SESSION=([^;,%s]+)")
  if casSSession then session.sessionCookies.CAS_S_SESSION = casSSession end

  local casDevice = cookieText:match("CAS_DEVICE_SESSION=([^;,%s]+)")
  if casDevice then session.sessionCookies.CAS_DEVICE_SESSION = casDevice end

  local vuSession = cookieText:match("VUSESSIONID=([^;,%s]+)")
  if vuSession then session.sessionCookies.VUSESSIONID = vuSession end

  local bigipServer = cookieText:match("BIGipServervue%.mlp%.de=([^;,%s]+)")
  if bigipServer then session.sessionCookies.BIGipServervue_mlp_de = bigipServer end
end

function parseCookieString(cookieString)
  if not cookieString or cookieString == "" then return end

  local seen = {}
  local pos = 1
  local len = #cookieString

  while pos <= len do
    local nextSemi = cookieString:find(";", pos) or len + 1
    local part = cookieString:sub(pos, nextSemi - 1)

    local eqPos = part:find("=", 1, true)
    if eqPos then
      local name = trim(part:sub(1, eqPos - 1))
      local value = trim(part:sub(eqPos + 1))

      if name ~= "" then
        local storageName = name
        if storageName == "VUSESSIONID" and seen["VUSESSIONID"] then
          storageName = "VUSESSIONID2"
        end
        seen[storageName] = true
        session.sessionCookies[storageName] = value
      end
    end

    pos = nextSemi + 1
  end
end

function buildCookieHeader(forVueApi)
  if forVueApi == nil then forVueApi = true end
  local parts = {}

  if forVueApi then
    local vuSessionId = session.sessionCookies.VUSESSIONID
    if vuSessionId and vuSessionId ~= "" then
      table.insert(parts, "VUSESSIONID=" .. vuSessionId)
      if session.sessionCookies.VUSESSIONID2 and session.sessionCookies.VUSESSIONID2 ~= "" then
        table.insert(parts, "VUSESSIONID=" .. session.sessionCookies.VUSESSIONID2)
      end
    end
    for name, value in pairs(session.sessionCookies) do
      if name:find("^BIGipServervue") or name:find("^TS01") then
        table.insert(parts, name .. "=" .. value)
      end
    end
  else
    for name, value in pairs(session.sessionCookies) do
      if not name:find("^VUSESSIONID") and not name:find("^BIGipServervue") then
        table.insert(parts, name .. "=" .. value)
      end
    end
  end

  return table.concat(parts, "; ")
end

function tryConsentCall()
  local authCookieHeader = buildCookieHeader(false)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json, text/plain, */*",
    ["Accept-Language"] = "de-DE,de;q=0.9",
    ["Origin"] = "https://financepilot-pe.mlp.de",
    ["Referer"] = "https://financepilot-pe.mlp.de/",
    ["Sec-Fetch-Site"] = "same-origin",
    ["Sec-Fetch-Mode"] = "cors",
    ["Sec-Fetch-Dest"] = "empty",
    ["User-Agent"] = CONSTANTS.userAgent
  }
  if authCookieHeader ~= "" then
    headers["Cookie"] = authCookieHeader
  end

  local payload = '{"useBrowserDetection":false}'

  local success, contentOrError = pcall(function()
    return connection:request(
      "POST",
      CONSTANTS.authBaseUrl .. "/services_auth/auth-backend/api/consent/execution",
      payload,
      "application/json",
      headers
    )
  end)

  if success and contentOrError then
    collectSessionCookies()
    return true
  end
  return false
end

function isAuthenticated()
  local hasVuSession = session.sessionCookies.VUSESSIONID and session.sessionCookies.VUSESSIONID ~= ""

  if hasVuSession then
    local vueCookieHeader = buildCookieHeader(true)
    local headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json, text/plain, */*",
      ["Accept-Language"] = "de-DE,de;q=0.9",
      ["Referer"] = "https://vue.mlp.de/vu/client/",
      ["Sec-Fetch-Site"] = "same-origin",
      ["Sec-Fetch-Mode"] = "cors",
      ["Sec-Fetch-Dest"] = "empty",
      ["User-Agent"] = CONSTANTS.userAgent
    }
    if vueCookieHeader ~= "" then
      headers["Cookie"] = vueCookieHeader
    end

    local success, contentOrError = pcall(function()
      return connection:request("GET", "https://vue.mlp.de/vu/api/contract/list", nil, nil, headers)
    end)

    if success and contentOrError then
      if contentOrError:find("403") or contentOrError:find("error") or contentOrError:find("<!doctype") then
        if tryConsentCall() then
          success, contentOrError = pcall(function()
            return connection:request("GET", "https://vue.mlp.de/vu/api/contract/list", nil, nil, headers)
          end)
        end
      end

      local data = parseJson(contentOrError)
      if (data and data.contractList) or (contentOrError and contentOrError:find('"contractList"')) then
        return true
      end
    else
      if tryConsentCall() then
        success, contentOrError = pcall(function()
          return connection:request("GET", "https://vue.mlp.de/vu/api/contract/list", nil, nil, headers)
        end)
        if success and contentOrError then
          local data = parseJson(contentOrError)
          if (data and data.contractList) or (contentOrError and contentOrError:find('"contractList"')) then
            return true
          end
        end
      end
    end
  end

  return false
end

function loadContracts()
  MM.printStatus("MLP: Lade Vertragsdaten...")

  local vueCookieHeader = buildCookieHeader(true)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json, text/plain, */*",
    ["Accept-Language"] = "de-DE,de;q=0.9",
    ["Referer"] = "https://vue.mlp.de/vu/client/",
    ["Sec-Fetch-Site"] = "same-origin",
    ["Sec-Fetch-Mode"] = "cors",
    ["Sec-Fetch-Dest"] = "empty",
    ["User-Agent"] = CONSTANTS.userAgent
  }
  if vueCookieHeader ~= "" then
    headers["Cookie"] = vueCookieHeader
  end

  local success, content = pcall(function()
    return connection:request("GET", "https://vue.mlp.de/vu/api/contract/list", nil, nil, headers)
  end)

  if success and content then
    if content:find("403") or content:find("error") or content:find("<!doctype") then
      if tryConsentCall() then
        success, content = pcall(function()
          return connection:request("GET", "https://vue.mlp.de/vu/api/contract/list", nil, nil, headers)
        end)
      end
    end
  elseif not success or not content then
    if tryConsentCall() then
      success, content = pcall(function()
        return connection:request("GET", "https://vue.mlp.de/vu/api/contract/list", nil, nil, headers)
      end)
    end
  end

  if success and content then
    local apiData = parseJson(content)
    if apiData and apiData.contractList then
      local contracts = parseVueContracts(apiData.contractList)
      if #contracts > 0 then
        session.contracts = contracts
        MM.printStatus("MLP: " .. #session.contracts .. " Vertrag(e) geladen.")
        return true
      end
    end
  end

  local authCookieHeader = buildCookieHeader(false)
  headers["Cookie"] = authCookieHeader
  content = connection:get(CONSTANTS.baseUrl .. "/api/vertraege", nil, headers)
  if content then
    local apiData = parseJson(content)
    if apiData then
      local contracts = parseApiContracts(apiData)
      if #contracts > 0 then
        session.contracts = contracts
        MM.printStatus("MLP: " .. #session.contracts .. " Vertrag(e) geladen.")
        return true
      end
    end
  end

  return false
end

function parseVueContracts(contractList)
  local contracts = {}
  if type(contractList) ~= "table" then return contracts end
  for _, item in ipairs(contractList) do
    if type(item) == "table" then
      local contract = mapVueContractToInternal(item)
      if contract then table.insert(contracts, contract) end
    end
  end
  return contracts
end

function parseApiContracts(apiData)
  local contracts = {}
  local items = apiData.contracts or apiData.vertraege or apiData.items or apiData
  if type(items) ~= "table" then return contracts end
  if #items == 0 and (items.id or items.number) then items = { items } end
  for _, item in ipairs(items) do
    if type(item) == "table" then
      local contract = mapApiContractToInternal(item)
      if contract then table.insert(contracts, contract) end
    end
  end
  return contracts
end

function mapVueContractToInternal(item)
  if not item then return nil end
  local contractNumber = item.number or item.id
  if not contractNumber then return nil end

  local contractType, tariff
  if item.posTypeList and type(item.posTypeList) == "table" and #item.posTypeList > 0 then
    local bestPos = item.posTypeList[1]
    for _, posType in ipairs(item.posTypeList) do
      if posType.type == "HV" then
        bestPos = posType
        break
      elseif posType.type == "BS" and bestPos.type ~= "HV" then
        bestPos = posType
      end
    end
    contractType = bestPos.contractType or bestPos.posType
    tariff = bestPos.posTypeShort
  end

  local shareValue = tonumber(item.shareValue) or 0
  local contribution = tonumber(item.contribution) or 0

  return {
    id = item.id or contractNumber,
    number = contractNumber,
    company = {
      shortName = item.companyShortName or "Unbekannt",
      longName = item.companyLongName or item.companyShortName or "Unbekannt"
    },
    contribution = contribution,
    validFrom = item.created,
    state = "aktiv",
    tariff = tariff,
    contractType = contractType,
    shareValue = shareValue,
    currency = "EUR",
    specificAttributes = {
      netContribution = { value = contribution, displayValue = formatCurrency(contribution) }
    }
  }
end

function mapApiContractToInternal(item)
  if not item then return nil end
  local company = item.company or {}
  local companyShort = company.shortName or company.name or "Unbekannt"
  local contractNumber = item.number or item.contractNumber or item.vertragsnummer or item.id
  if not contractNumber then return nil end

  local contractType = item.contractType or item.vertragsArt or item.posType or item.type
  local shareValue = tonumber(item.shareValue or item.rueckkaufswert or item.value) or 0
  local contribution = tonumber(item.contribution or item.beitrag or item.premium) or 0

  local specificAttrs = item.specificAttributes or item.details or {}
  local deathSum = specificAttrs.deathInsuredSum or specificAttrs.todesfallsumme
  local lifeSum = specificAttrs.lifeInsuredSum or specificAttrs.erlebensfallsumme
  local endOfPayment = specificAttrs.endOfPayment or specificAttrs.beitragszahlungsende

  return {
    id = item.id or contractNumber,
    number = contractNumber,
    company = { shortName = companyShort, longName = company.longName or companyShort },
    contribution = contribution,
    validFrom = item.validFrom or item.beginn,
    validUntil = item.validUntil or item.ende,
    state = item.state or item.status or "aktiv",
    tariff = item.tariff or item.tarif,
    contractType = contractType,
    shareValue = shareValue,
    currency = item.currency or "EUR",
    specificAttributes = {
      deathInsuredSum = normalizeAttributeValue(deathSum),
      lifeInsuredSum = normalizeAttributeValue(lifeSum),
      endOfPayment = normalizeAttributeValue(endOfPayment),
      netContribution = { value = contribution, displayValue = formatCurrency(contribution) }
    }
  }
end

function normalizeAttributeValue(attr)
  if not attr then return nil end
  if type(attr) == "table" then
    return {
      value = attr.value or attr.wert,
      displayValue = attr.displayValue or attr.anzeigeWert or tostring(attr.value or attr.wert)
    }
  end
  return { value = attr, displayValue = tostring(attr) }
end

function ListAccounts(knownAccounts)
  if not session.contracts or #session.contracts == 0 then
    return "Keine Vertragsdaten verfügbar."
  end

  local accounts = {}
  for _, contract in ipairs(session.contracts) do
    table.insert(accounts, createAccountFromContract(contract))
  end
  return accounts
end

function createAccountFromContract(contract)
  local companyName = contract.company.shortName or "Unbekannt"
  local contractNumber = contract.number or ""
  local tariff = contract.tariff or ""
  local endDate = ""
  if contract.specificAttributes and contract.specificAttributes.endOfPayment then
    endDate = formatDateDisplay(contract.specificAttributes.endOfPayment.value)
  end

  local displayName = companyName
  if contractNumber ~= "" then displayName = displayName .. " " .. contractNumber end
  if tariff ~= "" then displayName = displayName .. " (" .. tariff .. ")" end
  if endDate ~= "" then displayName = displayName .. " | Beitrag bis " .. endDate end

  return {
    name = displayName,
    accountNumber = contract.number or contract.id,
    portfolio = true,
    currency = contract.currency or "EUR",
    type = AccountTypePortfolio,
    bankCode = contract.company.shortName or "MLP"
  }
end

function RefreshAccount(account, since)
  local contract = findContractByNumber(account.accountNumber)
  if not contract then return "Vertrag nicht gefunden." end

  local shareValue = contract.shareValue or 0
  local currency = contract.currency or "EUR"
  local security = {
    name = buildSecurityName(contract),
    isin = "",
    securityNumber = contract.number or "",
    quantity = 1,
    price = shareValue,
    currencyOfPrice = currency,
    amount = shareValue,
    currencyOfOriginalAmount = currency,
    purchasePrice = calculateTotalContributions(contract)
  }

  return { balance = shareValue, securities = { security } }
end

function findContractByNumber(accountNumber)
  if not session.contracts then return nil end
  for _, contract in ipairs(session.contracts) do
    if contract.number == accountNumber or contract.id == accountNumber then return contract end
  end
  return nil
end

function buildSecurityName(contract)
  local parts = { getContractTypeName(contract.contractType) }
  if contract.tariff and contract.tariff ~= "" then table.insert(parts, "Tarif: " .. contract.tariff) end
  if contract.specificAttributes then
    local ds = contract.specificAttributes.deathInsuredSum
    if ds and ds.displayValue then table.insert(parts, "Todesfall: " .. ds.displayValue) end
    local ls = contract.specificAttributes.lifeInsuredSum
    if ls and ls.displayValue then table.insert(parts, "Erlebensfall: " .. ls.displayValue) end
  end
  if contract.contribution and contract.contribution > 0 then
    table.insert(parts, "Beitrag/Monat: " .. formatCurrency(contract.contribution))
  end
  return table.concat(parts, " | ")
end

local CONTRACT_TYPE_NAMES = {
  FLV = "Fondsgebundene Lebensversicherung",
  KLV = "Kapitallebensversicherung",
  LV = "Lebensversicherung",
  REN = "Rentenversicherung",
  BU = "Berufsunfähigkeitsversicherung",
  BUZ = "Berufsunfähigkeits-Zusatz",
  BAV = "Betriebliche Altersvorsorge",
  RIESTER = "Riester-Rente",
  RUERUP = "Rürup-Rente",
  DEFAULT = "Vorsorgevertrag"
}

function getContractTypeName(contractType)
  return CONTRACT_TYPE_NAMES[contractType or "DEFAULT"] or CONTRACT_TYPE_NAMES.DEFAULT
end

function calculateTotalContributions(contract)
  if not contract.contribution or contract.contribution <= 0 then return 0 end
  local day, month, year = parseIsoDate(contract.validFrom)
  if not year then return 0 end
  local currentDate = os.date("*t")
  local monthsElapsed = (currentDate.year - year) * 12 + (currentDate.month - month)
  return contract.contribution * math.max(0, monthsElapsed)
end

function EndSession()
  session = { contracts = {}, state = nil, username = nil, password = nil, mfaToken = nil, sessionCookies = {} }
  connection = nil
  MM.printStatus("MLP: Session beendet.")
end

function trim(text)
  return text and (text:gsub("^%s*(.-)%s*$", "%1")) or ""
end

function formatCurrency(value)
  if not value then return "0,00 €" end
  local formatted = string.format("%.2f", value):gsub("(%d)%.(%d%d)$", "%1,%2")
  local intPart, decPart = formatted:match("^(%d+),(%d%d)$")
  if intPart then
    intPart = intPart:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    formatted = intPart .. "," .. decPart
  end
  return formatted .. " €"
end

function parseIsoDate(dateStr)
  if not dateStr then return nil end
  local y, m, d = dateStr:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  return d and tonumber(d), m and tonumber(m), y and tonumber(y)
end

function formatDateDisplay(dateStr)
  local d, m, y = parseIsoDate(dateStr)
  return d and string.format("%02d.%02d.%04d", d, m, y) or dateStr or ""
end

function encodeJson(obj)
  if JSON then
    local success, result = pcall(function() return JSON():set(obj):json() end)
    if success and result then return result end
  end
  if type(obj) == "table" then
    local isArray, parts = #obj > 0, {}
    if isArray then
      for _, v in ipairs(obj) do table.insert(parts, encodeJson(v)) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(obj) do
        local val = type(v) == "table" and encodeJson(v) or (type(v) == "string" and string.format("%q", v) or (type(v) == "number" and tostring(v) or (type(v) == "boolean" and tostring(v) or "null")))
        table.insert(parts, string.format("%q", k) .. ":" .. val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return type(obj) == "string" and string.format("%q", obj) or tostring(obj)
end

function parseJson(jsonStr)
  if not jsonStr or jsonStr == "" then return nil end
  jsonStr = trim(jsonStr)
  if not jsonStr:match("^[%{%[]") then return nil end
  if JSON then
    local success, result = pcall(function() return JSON(jsonStr):dictionary() end)
    if success and result then return result end
    success, result = pcall(function() return JSON(jsonStr):array() end)
    if success and result then return result end
  end
  local normalized = jsonStr:gsub('"([^"]+)":', '["%1"] = '):gsub("%[", "{"):gsub("%]", "}"):gsub("true", "true"):gsub("false", "false"):gsub("null", "nil")
  local func = load("return " .. normalized, "json", "t", {})
  if func then
    local success, result = pcall(func)
    if success and type(result) == "table" then return result end
  end
  return nil
end
