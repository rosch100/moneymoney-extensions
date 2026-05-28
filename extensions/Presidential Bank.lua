--
-- Presidential Bank — MoneyMoney Web Banking Extension
-- https://www.presidentialpcbanking.com
-- Dokumentation: docs/LUA-EXTENSIONS.md
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 1.00,
  url         = "https://www.presidentialpcbanking.com",
  services    = {"Presidential Bank"},
  description = "Presidential Bank - MFA and Cookie Import"
}

local CONSTANTS = {
  baseUrl = "https://www.presidentialpcbanking.com",
  authApi = "https://www.presidentialpcbanking.com/auth-olb/live/v1",
  acctsApi = "https://www.presidentialpcbanking.com/accts-olb/live/v1",
  bankCode = "255073345"
}

local connection
local session = {}

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Presidential Bank"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local storage = rawget(_G, "LocalStorage")
  local accountKey = credentials and credentials[1] or ""
  local canReuse =
    storage and storage.connection and storage.connectionAccountKey == accountKey

  if canReuse then
    connection = storage.connection
    session.persistedConnection = true
  else
    connection = Connection()
    if storage then
      storage.connection = connection
      storage.connectionAccountKey = accountKey
      session.persistedConnection = true
    else
      session.persistedConnection = false
    end
  end
  connection.language = "en-US"
  connection.useragent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"

  if storage and accountKey ~= "" then
    migratePresidentialSessionStorage(storage)
    restorePersistedSessionState(storage, accountKey)
  end

  if step == 1 then
    return handleLoginStep1(credentials)
  end

  if session.waitingForMethodSelection then
    return handleMethodSelection(credentials[1])
  end
  if session.waitingForMfaCode then
    return verifyMfaCode(credentials[1])
  end
  if session.waitingForCookieImport then
    return handleCookieImportStep(credentials)
  end

  return LoginFailed
end

function handleLoginStep1(credentials)
  local username = credentials[1]
  local password = credentials[2]

  if password and password:match("^COOKIE:") then
    return loginWithImportedCookies(password:sub(8))
  end

  local storage = rawget(_G, "LocalStorage")
  local accountKey = username or ""

  if storage then
    migratePresidentialSessionStorage(storage)
  end

  if storage then
    local jarResult = tryConnectionJarLogin(storage, accountKey)
    if jarResult ~= false then
      return jarResult
    end
  end

  if storage and canRestorePersistedSession(storage, accountKey) then
    local persistedResult = tryPersistedLogin(storage, accountKey)
    if persistedResult ~= false then
      return persistedResult
    end
  end

  if storage and accountKey ~= "" then
    storage.connectionAccountKey = accountKey
  end

  local loginFormData = "testcookie=false&testjs=true&dscheck=1&userid=" .. MM.urlencode(username) .. "&password=" .. MM.urlencode(password)
  local externalResponse = connection:request(
    "POST",
    CONSTANTS.authApi .. "/external-login",
    loginFormData,
    "application/x-www-form-urlencoded",
    {
      ["Accept"] = "application/json, text/plain, */*",
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Origin"] = CONSTANTS.baseUrl,
      ["Referer"] = CONSTANTS.baseUrl .. "/dbank/live/app/external-login"
    }
  )

  if not externalResponse then
    return LoginFailed
  end

  syncSessionCookies()

  local extLoginData = parseJson(externalResponse)
  if extLoginData and (extLoginData.targetView == "error" or extLoginData.errorMessage) then
    return LoginFailed
  end

  -- POST to login/redirect
  local redirectResponse = connection:request(
    "POST",
    CONSTANTS.authApi .. "/login/redirect?mfaLSO=",
    "{}",
    "application/json",
    withCookieHeader({
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/json",
      ["Origin"] = CONSTANTS.baseUrl,
      ["Referer"] = CONSTANTS.baseUrl .. "/dbank/live/app/external-login"
    })
  )

  if not redirectResponse then
    return LoginFailed
  end

  syncSessionCookies()

  return getMfaConfig()
end

function getMfaConfig()
  local mfaConfigResponse = connection:request("GET", CONSTANTS.authApi .. "/mfa/config", nil, nil, withCookieHeader({
    ["Accept"] = "application/json",
    ["Referer"] = CONSTANTS.baseUrl .. "/dbank/live/app/mfa"
  }))

  if not mfaConfigResponse then
    return LoginFailed
  end

  syncSessionCookies()

  local mfaData = parseJson(mfaConfigResponse)

  if not mfaData then
    return LoginFailed
  end

  session.mfaConfig = mfaData
  session.csrfToken = extractCsrfToken(mfaData)
  if session.csrfToken then
    mergeSessionCookie("CSRFToken", session.csrfToken)
  end
  session.mfaMethods = extractMfaMethods(mfaData)

  if #session.mfaMethods == 0 then
    session.waitingForMfaCode = true
    return mfaCodeChallenge(nil)
  end

  session.waitingForMethodSelection = true
  return buildMfaSelectionChallenge()
end

function extractCsrfToken(mfaData)
  if mfaData.pageProps and mfaData.pageProps.CSRFToken then
    return mfaData.pageProps.CSRFToken
  elseif mfaData.targetData and mfaData.targetData.CSRFToken then
    return mfaData.targetData.CSRFToken
  elseif mfaData.globalEnvProps and mfaData.globalEnvProps.globalIFS then
    return mfaData.globalEnvProps.globalIFS.guid
  end
  return nil
end

function extractMfaMethods(mfaData)
  local methods = {}

  if not (mfaData.targetData and mfaData.targetData.destinations) then
    return methods
  end

  local destinations = mfaData.targetData.destinations
  if type(destinations) == "string" then
    destinations = parseJson(destinations) or {}
  end

  if type(destinations) ~= "table" then
    return methods
  end

  for _, dest in ipairs(destinations) do
    if dest.activated then
      local method = buildMfaMethod(dest)
      if method then
        table.insert(methods, method)
      end
    end
  end

  return methods
end

function buildMfaMethod(dest)
  local method = {
    id = dest.id and dest.id.value,
    protocol = dest.protocol,
    contactInfo = dest.contactInfo or "",
    telephoneCountryCode = dest.telephoneCountryCode
  }

  local protocolMap = {
    TOTP = { name = "Authenticator App (TOTP)", type = "totp" },
    SMS = { name = "Text me at " .. method.contactInfo, type = "sms" },
    VOICE = { name = "Call me at " .. method.contactInfo, type = "voice" },
    EMAIL = { name = "Email me at " .. method.contactInfo, type = "email" }
  }

  local mapped = protocolMap[dest.protocol]
  if not mapped then
    return nil
  end

  method.name = mapped.name
  method.type = mapped.type
  return method
end

function buildMfaSelectionChallenge(prefix)
  local options = {}
  for i, method in ipairs(session.mfaMethods) do
    table.insert(options, i .. ". " .. method.name)
  end
  local body = "Select verification method:\n\n" .. table.concat(options, "\n") .. "\n\nEnter number:"
  return {
    title = "Two-Factor Authentication",
    challenge = (prefix and prefix .. "\n\n" or "") .. body,
    label = "Option (1-" .. #session.mfaMethods .. ")"
  }
end

function mfaCodeChallenge(method, prefix)
  local isPushed = method and method.type and method.type ~= "totp"
  local body
  if isPushed then
    body = "A code has been sent to " .. method.name .. ".\n\nEnter the code:"
  else
    body = "Enter the 6-digit code from your Authenticator app:"
  end
  return {
    title = "Two-Factor Authentication",
    challenge = (prefix and prefix .. "\n\n" or "") .. body,
    label = isPushed and "Verification Code" or "TOTP Code"
  }
end

function handleMethodSelection(userInput)
  if not session.cookies or session.cookies == "" then
    session.waitingForMethodSelection = false
    return "MFA verification failed: No active session"
  end

  local methodIndex = tonumber(userInput)
  if not methodIndex or methodIndex < 1 or methodIndex > #session.mfaMethods then
    -- Selection-State erhalten, User soll erneut waehlen.
    return buildMfaSelectionChallenge(
      "Invalid selection. Please enter a number between 1 and " .. #session.mfaMethods .. "."
    )
  end

  session.selectedMfaMethod = session.mfaMethods[methodIndex]
  session.waitingForMethodSelection = false
  session.waitingForMfaCode = true

  -- TOTP: direkt mfa/submit ohne mfa/select (Browser-Flow).
  if session.selectedMfaMethod.type ~= "totp" then
    local buttonError = pressMfaVirtualButton(session.selectedMfaMethod)
    if buttonError then
      session.waitingForMethodSelection = true
      session.waitingForMfaCode = false
      session.selectedMfaMethod = nil
      return buildMfaSelectionChallenge(buttonError)
    end
  end

  return mfaCodeChallenge(session.selectedMfaMethod)
end

function mfaVirtualButtonLabel(method)
  local labels = {
    totp = "Enter code",
    sms = "Text me",
    voice = "Call me",
    email = "Email me"
  }
  if not method or not method.type then
    return "MFA"
  end
  return labels[method.type] or method.protocol
end

function buildMfaSelectUrl(method)
  return CONSTANTS.authApi .. "/mfa/select?type=" .. method.type
end

function buildMfaSubmitUrl(method, cookieoptin)
  local optin = cookieoptin == false and "false" or "true"
  return CONSTANTS.authApi .. "/mfa/submit?displayMethod=" .. method.protocol .. "&type=OTP&cookieoptin=" .. optin
end

function jsonEscapeString(value)
  if value == nil then
    return ""
  end
  return tostring(value)
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
end

function buildMfaSelectBody(method)
  session.csrfToken = session.csrfToken or extractCsrfTokenFromCookies(session.cookies) or ""
  return '{"destId":"' .. jsonEscapeString(method.id) ..
    '","csrftoken":"' .. jsonEscapeString(session.csrfToken) .. '"}'
end

function buildMfaSubmitBody(method, code)
  session.csrfToken = session.csrfToken or extractCsrfTokenFromCookies(session.cookies) or ""
  local destId = method and method.id
  if method and method.type == "totp" and not destId then
    destId = findTotpId() or ""
  end
  return '{"destId":"' .. jsonEscapeString(destId or "") ..
    '","csrftoken":"' .. jsonEscapeString(session.csrfToken) ..
    '","otp":"' .. jsonEscapeString(code) .. '"}'
end

function isMfaSelectSuccess(response)
  if not response or response == "" then
    return false
  end
  local data = parseJson(response)
  if not data or data.errorCode then
    return false
  end
  return data.result == "success"
end

function pressMfaVirtualButton(method)
  session.csrfToken = session.csrfToken or extractCsrfTokenFromCookies(session.cookies) or ""

  local selectUrl = buildMfaSelectUrl(method)
  local body = buildMfaSelectBody(method)

  local response, _, _, _, respHeaders = connection:request(
    "POST",
    selectUrl,
    body,
    "application/json",
    buildApiHeaders()
  )

  applyResponseCookies(respHeaders)
  syncSessionCookies()

  if not isMfaSelectSuccess(response) then
    local data = parseJson(response)
    if data and data.errorCode then
      return "MFA-Button fehlgeschlagen (Fehler " .. tostring(data.errorCode) ..
             "). Bitte andere Methode waehlen oder Login neu starten."
    end
    return "MFA-Button fehlgeschlagen. Bitte andere Methode waehlen oder Login neu starten."
  end

  return nil
end

function verifyMfaCode(code)
  if not session.cookies or session.cookies == "" then
    session.waitingForMfaCode = false
    return "MFA verification failed: No active session"
  end

  local method = session.selectedMfaMethod

  -- Format-Vorpruefung: leere/nicht-numerische Eingabe -> Retry-Challenge.
  if not code or not code:match("^%s*%d+%s*$") then
    return mfaCodeChallenge(method, "Invalid code (digits only). Please try again.")
  end
  code = code:gsub("^%s*(.-)%s*$", "%1")

  session.csrfToken = session.csrfToken or extractCsrfTokenFromCookies(session.cookies) or ""

  local submitUrl = buildMfaSubmitUrl(method or { protocol = "TOTP", type = "totp" })
  local body = buildMfaSubmitBody(method, code)
  local mfaResponse, _, _, _, mfaHeaders = connection:request(
    "POST", submitUrl, body, "application/json", buildApiHeaders()
  )

  if not mfaResponse then
    session.waitingForMfaCode = false
    return "MFA verification failed: No response from server"
  end

  applyResponseCookies(mfaHeaders)
  syncSessionCookies()
  markPrivateDeviceFromCookies()

  if not isMfaSuccess(mfaResponse) then
    local data = parseJson(mfaResponse)
    if isMfaSessionError(data) then
      session.waitingForMfaCode = false
      return "MFA fehlgeschlagen: Session oder CSRF ungültig (Fehler " ..
             tostring(data.errorCode) .. "). Bitte Login abbrechen und erneut starten."
    end
    if data then
      local freshCsrf = extractCsrfToken(data)
      if freshCsrf then
        session.csrfToken = freshCsrf
      end
    end
    session.waitingForMfaCode = true
    return mfaCodeChallenge(method, "Invalid code. Please try again.")
  end

  session.waitingForMfaCode = false
  return finalizeLogin(mfaResponse)
end

function isMfaSessionError(data)
  if not data or data.errorCode == nil then
    return false
  end
  local code = tostring(data.errorCode)
  -- 10000: Session/CSRF/Request ungültig — kein OTP-Retry (verhindert Endlosschleife)
  return code == "10000" or code == "99999" or code == "24001"
end

function trim(value)
  if not value then
    return ""
  end
  return value:gsub("^%s*(.-)%s*$", "%1")
end

function mergeSessionCookie(name, value)
  name = trim(name)
  value = trim(value)
  if name == "" or value == "" then
    return
  end

  session.cookies = session.cookies or ""
  local pattern = name .. "=[^;]*"
  if session.cookies:find(name .. "=", 1, true) then
    session.cookies = session.cookies:gsub(pattern, name .. "=" .. value)
  elseif session.cookies ~= "" then
    session.cookies = session.cookies .. "; " .. name .. "=" .. value
  else
    session.cookies = name .. "=" .. value
  end

  if name == "rftoken" then
    session.rftoken = value
  end

  if connection and type(connection.setCookie) == "function" then
    pcall(function()
      connection:setCookie(name .. "=" .. value)
    end)
  end
end

function mergeCookieHeaderIntoSession(cookieHeader)
  if not cookieHeader or cookieHeader == "" then
    return
  end
  for pair in cookieHeader:gmatch("[^;]+") do
    local name, value = pair:match("^%s*([^=]+)=(.+)$")
    if name and value then
      mergeSessionCookie(name, value)
    end
  end
end

function applySetCookieLine(cookieLine)
  if not cookieLine or cookieLine == "" then
    return
  end
  local name, value = cookieLine:match("^%s*([^=]+)=([^;]+)")
  if name and value then
    mergeSessionCookie(name, value)
  end
end

function applyResponseCookies(headers)
  if not headers then
    return
  end

  if type(headers) == "string" then
    for line in headers:gmatch("[^\r\n]+") do
      local cookieLine = line:match("^[Ss]et%-[Cc]ookie:%s*(.+)$")
      if cookieLine then
        applySetCookieLine(cookieLine)
      end
    end
    return
  end

  if type(headers) ~= "table" then
    return
  end

  for key, value in pairs(headers) do
    if type(key) == "string" and key:lower() == "set-cookie" then
      if type(value) == "table" then
        for _, cookieLine in ipairs(value) do
          applySetCookieLine(tostring(cookieLine))
        end
      else
        applySetCookieLine(tostring(value))
      end
    end
  end

  for _, entry in ipairs(headers) do
    if type(entry) == "table" and entry.name and entry.name:lower() == "set-cookie" then
      applySetCookieLine(tostring(entry.value))
    end
  end
end

function syncSessionCookies()
  if not connection or type(connection.getCookies) ~= "function" then
    return
  end
  local jarCookies = connection:getCookies()
  if jarCookies and jarCookies ~= "" then
    mergeCookieHeaderIntoSession(jarCookies)
  end
end

function sessionCookiesFromHeader(cookieHeader)
  local map = {}
  if not cookieHeader or cookieHeader == "" then
    return map
  end
  for pair in cookieHeader:gmatch("[^;]+") do
    local name, value = pair:match("^%s*([^=]+)=(.+)$")
    if name and value then
      map[trim(name)] = trim(value)
    end
  end
  return map
end

function applySessionCookieMap(cookieMap)
  if type(cookieMap) ~= "table" then
    return
  end
  for name, value in pairs(cookieMap) do
    if type(name) == "string" and type(value) == "string" and name ~= "" and value ~= "" then
      mergeSessionCookie(name, value)
    end
  end
end

function normalizeAccountKey(key)
  if key == nil then
    return ""
  end
  return trim(tostring(key)):lower()
end

function accountKeysMatch(storedKey, currentKey)
  storedKey = normalizeAccountKey(storedKey)
  currentKey = normalizeAccountKey(currentKey)
  if storedKey == "" or currentKey == "" then
    return true
  end
  return storedKey == currentKey
end

function collectPresidentialSessionCookies()
  syncSessionCookies()
  local map = sessionCookiesFromHeader(session.cookies or "")
  if connection and type(connection.getCookies) == "function" then
    local success, jarCookies = pcall(function()
      return connection:getCookies()
    end)
    if success and jarCookies and jarCookies ~= "" then
      for name, value in pairs(sessionCookiesFromHeader(jarCookies)) do
        map[name] = value
      end
    end
  end
  return map
end

function migratePresidentialSessionStorage(storage)
  if type(storage.presidentialSessionCookies) == "table" then
    return
  end
  local legacy = storage.presidentialSession
  local cookieMap = {}
  if type(legacy) == "table" then
    if type(legacy.sessionCookies) == "table" then
      cookieMap = legacy.sessionCookies
    elseif type(legacy.cookies) == "string" and legacy.cookies ~= "" then
      cookieMap = sessionCookiesFromHeader(legacy.cookies)
    end
    if legacy.accountKey then
      storage.presidentialSessionAccountKey = legacy.accountKey
    end
    if legacy.rftoken then
      storage.presidentialRftoken = legacy.rftoken
    end
    if legacy.csrfToken then
      storage.presidentialCsrfToken = legacy.csrfToken
    end
    if legacy.deviceRegisteredPrivate == true then
      storage.presidentialDevicePrivate = true
    end
    if legacy.loginComplete == true then
      storage.presidentialLoginComplete = true
    end
  end
  storage.presidentialSessionCookies = cookieMap
end

function getPersistedSessionSnapshot(storage)
  if not storage then
    return nil
  end
  migratePresidentialSessionStorage(storage)
  if type(storage.presidentialSessionCookies) ~= "table" then
    return nil
  end
  return {
    accountKey = storage.presidentialSessionAccountKey or "",
    sessionCookies = storage.presidentialSessionCookies,
    rftoken = storage.presidentialRftoken,
    csrfToken = storage.presidentialCsrfToken,
    deviceRegisteredPrivate = storage.presidentialDevicePrivate == true,
    loginComplete = storage.presidentialLoginComplete == true
  }
end

function clearPersistedSessionStorage(storage)
  if not storage then
    return
  end
  storage.presidentialSession = nil
  storage.presidentialSessionCookies = nil
  storage.presidentialSessionAccountKey = nil
  storage.presidentialRftoken = nil
  storage.presidentialCsrfToken = nil
  storage.presidentialDevicePrivate = nil
  storage.presidentialLoginComplete = nil
end

function canRestorePersistedSession(storage, accountKey)
  local saved = getPersistedSessionSnapshot(storage)
  if not saved then
    return false
  end
  local privateDevice =
    saved.deviceRegisteredPrivate or hasPrivateDeviceCookieInMap(saved.sessionCookies)
  if privateDevice then
    return true
  end
  if not accountKeysMatch(saved.accountKey, accountKey) then
    return false
  end
  if saved.loginComplete ~= true then
    return false
  end
  if saved.sessionCookies.SESSION_TOKEN then
    return true
  end
  return false
end

function persistSessionState(storage)
  if not storage then
    return
  end
  syncSessionCookies()
  session.csrfToken = extractCsrfTokenFromCookies(session.cookies) or session.csrfToken
  if hasPrivateDeviceCookie() then
    session.deviceRegisteredPrivate = true
  end
  local accountKey = storage.connectionAccountKey or ""
  if accountKey == "" and storage.presidentialSessionAccountKey then
    accountKey = storage.presidentialSessionAccountKey
  end
  local cookieMap = collectPresidentialSessionCookies()
  storage.presidentialSessionCookies = cookieMap
  storage.presidentialSessionAccountKey = accountKey
  storage.presidentialRftoken = session.rftoken
  storage.presidentialCsrfToken = session.csrfToken
  storage.presidentialDevicePrivate = session.deviceRegisteredPrivate == true
  storage.presidentialLoginComplete = session.loginComplete == true
  storage.presidentialSession = nil
end

function restorePersistedSessionState(storage, accountKey)
  local saved = getPersistedSessionSnapshot(storage)
  if not saved then
    return false
  end
  local privateDevice =
    saved.deviceRegisteredPrivate or hasPrivateDeviceCookieInMap(saved.sessionCookies)
  if not accountKeysMatch(saved.accountKey, accountKey) and not privateDevice then
    return false
  end

  applySessionCookieMap(saved.sessionCookies)
  if type(saved.rftoken) == "string" and saved.rftoken ~= "" then
    session.rftoken = saved.rftoken
    mergeSessionCookie("rftoken", saved.rftoken)
  end
  if type(saved.csrfToken) == "string" and saved.csrfToken ~= "" then
    session.csrfToken = saved.csrfToken
  end
  if saved.deviceRegisteredPrivate then
    session.deviceRegisteredPrivate = true
  end
  if saved.loginComplete then
    session.loginComplete = true
  end
  return true
end

function tryVerifyPersistedSession(storage, accountKey)
  syncSessionCookies()

  if not session.cookies or session.cookies == "" then
    return false
  end
  if not session.cookies:match("SESSION_TOKEN") then
    return false
  end

  local homeReferer = CONSTANTS.baseUrl .. "/dbank/live/app/home"
  local authtokenContent = performApiRequest(
    "GET",
    CONSTANTS.authApi .. "/user/authtoken",
    nil,
    nil,
    homeReferer
  )
  collectRftokenFromResponses(authtokenContent)
  updateDevicePrivateFromAuthtoken(authtokenContent)

  if verifySessionWithHistory() or verifySessionWithAccounts() then
    session.loginComplete = true
    persistSessionState(storage)
    return nil
  end

  clearPersistedSessionStorage(storage)
  return false
end

function tryConnectionJarLogin(storage, accountKey)
  if not storage or not storage.connection then
    return false
  end
  syncSessionCookies()
  local hasSessionToken = session.cookies and session.cookies:match("SESSION_TOKEN")
  local hasPrivate = hasPrivateDeviceCookie()
  if not hasSessionToken and not hasPrivate then
    return false
  end
  if storage.connectionAccountKey and accountKey ~= "" then
    if not accountKeysMatch(storage.connectionAccountKey, accountKey) and not hasPrivate then
      return false
    end
  end
  return tryVerifyPersistedSession(storage, accountKey)
end

function tryPersistedLogin(storage, accountKey)
  if not canRestorePersistedSession(storage, accountKey) then
    return false
  end
  if not restorePersistedSessionState(storage, accountKey) then
    return false
  end
  return tryVerifyPersistedSession(storage, accountKey)
end

function updateDevicePrivateFromAuthtoken(content)
  if markPrivateDeviceFromCookies() then
    return
  end
  local data = parseJson(content)
  if not data or type(data.mfaInfo) ~= "table" then
    return
  end
  if data.mfaInfo.computerPrivate == true then
    session.deviceRegisteredPrivate = true
  end
  if type(data.mfaInfo.mfaCookies) == "table" and #data.mfaInfo.mfaCookies > 0 then
    session.deviceRegisteredPrivate = true
  end
end

function hasPrivateDeviceCookieInMap(cookieMap)
  if type(cookieMap) ~= "table" then
    return false
  end
  for name in pairs(cookieMap) do
    if type(name) == "string" and name:match("^MAF_IB_") then
      return true
    end
  end
  return false
end

function hasPrivateDeviceCookie(cookies)
  cookies = cookies or session.cookies or ""
  if cookies:match("MAF_IB_") then
    return true
  end
  return hasPrivateDeviceCookieInMap(sessionCookiesFromHeader(cookies))
end

function markPrivateDeviceFromCookies()
  if not hasPrivateDeviceCookie() then
    return false
  end
  if not session.deviceRegisteredPrivate then
    session.deviceRegisteredPrivate = true
  end
  return true
end

function withCookieHeader(headers)
  syncSessionCookies()
  headers["Cookie"] = session.cookies or ""
  return headers
end

function buildLoginUpdateBody()
  local csrf = session.csrfToken or extractCsrfTokenFromCookies(session.cookies) or ""
  if csrf == "" then
    return "{}"
  end
  return JSON():set({ csrftoken = csrf }):json()
end

function performLoginUpdate(referer)
  syncSessionCookies()
  local headers = withCookieHeader({
    ["Accept"] = "application/json, text/plain, */*",
    ["Origin"] = CONSTANTS.baseUrl,
    ["Referer"] = referer,
    ["X-Requested-With"] = "XMLHttpRequest"
  })
  local response, _, _, _, respHeaders = connection:request(
    "POST",
    CONSTANTS.authApi .. "/login/update",
    "",
    nil,
    headers
  )
  applyResponseCookies(respHeaders)
  syncSessionCookies()
  return response
end

function performApiRequest(method, url, body, contentType, referer)
  syncSessionCookies()
  local headers = withCookieHeader({
    ["Accept"] = "application/json, text/plain, */*",
    ["Origin"] = CONSTANTS.baseUrl,
    ["Referer"] = referer,
    ["X-Requested-With"] = "XMLHttpRequest"
  })
  if method == "POST" then
    headers["Content-Type"] = contentType or "application/json"
  end
  local response, _, _, _, respHeaders = connection:request(
    method, url, body, contentType, headers
  )
  applyResponseCookies(respHeaders)
  syncSessionCookies()
  return response
end

function applyConfigCsrf(data)
  if not data then
    return
  end
  local csrf = extractCsrfToken(data)
  if csrf then
    session.csrfToken = csrf
  end
end

function fetchPostLoginConfig(referer)
  local configUrl = CONSTANTS.authApi .. "/login/postlogin/config"
  local content = performApiRequest("GET", configUrl, nil, nil, referer)
  local data = parseJson(content)
  if data then
    session.postLoginConfig = data
    applyConfigCsrf(data)
    return data
  end
  return nil
end

function collectRftokenFromResponses(...)
  for i = 1, select("#", ...) do
    local text = select(i, ...)
    local token = extractRftokenFromText(text)
    if token then
      session.rftoken = token
      mergeSessionCookie("rftoken", token)
      return token
    end
  end

  local fromCookies = extractCookieValue(session.cookies, "rftoken")
  if fromCookies then
    session.rftoken = fromCookies
    return fromCookies
  end

  return session.rftoken
end

function isApiErrorResponse(response)
  local data = parseJson(response)
  return data and data.errorCode ~= nil
end

function extractPostLoginUrl(mfaResponse)
  if not mfaResponse or mfaResponse == "" then
    return nil
  end

  local data = parseJson(mfaResponse)
  if not data then
    return nil
  end

  local resultUrl = data.resultURL
  if not resultUrl and data.result then
    local inner = parseJson(data.result)
    if inner then
      resultUrl = inner.resultURL
    end
  end

  if not resultUrl or resultUrl == "" then
    return nil
  end

  if resultUrl:match("^https?://") then
    return resultUrl
  end
  if resultUrl:match("^/app/") then
    return CONSTANTS.baseUrl .. "/dbank/live" .. resultUrl
  end
  if resultUrl:match("^/dbank/") then
    return CONSTANTS.baseUrl .. resultUrl
  end
  return CONSTANTS.baseUrl .. resultUrl
end

function followPostLoginRedirect(mfaResponse)
  local postLoginUrl = extractPostLoginUrl(mfaResponse) or (CONSTANTS.baseUrl .. "/dbank/live/app/postLogin")
  connection:request(
    "GET",
    postLoginUrl,
    nil,
    nil,
    withCookieHeader({
      ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      ["Referer"] = CONSTANTS.baseUrl .. "/dbank/live/app/mfa"
    })
  )
  syncSessionCookies()
end

function extractRftokenFromText(text)
  if not text then
    return nil
  end
  local v = text:match('[Rr][Ff]token"%s*:%s*"([^"%s]+)"')
  if v then
    return v
  end
  v = text:match('[Rr][Ff]token"%s*:%s*([^"%s,}]+)')
  if v then
    return v
  end
  return text:match('[Rr][Ff]token[^%w%-_%.]*["\']?([%w%-_%.]+)["\']?')
end

function activateOlbSession(mfaResponse, postLoginReferer)
  local homeUrl = CONSTANTS.baseUrl .. "/dbank/live/app/home"

  collectRftokenFromResponses(mfaResponse)

  performLoginUpdate(postLoginReferer)

  local homeHtml = performApiRequest("GET", homeUrl, nil, nil, postLoginReferer)
  collectRftokenFromResponses(homeHtml)

  performApiRequest(
    "POST",
    CONSTANTS.baseUrl .. "/site-olb/live/v1/home/config",
    "",
    "multipart/form-data",
    homeUrl
  )
  performApiRequest(
    "GET",
    CONSTANTS.acctsApi .. "/home/config?previewExperienceId",
    nil,
    nil,
    homeUrl
  )
  syncSessionCookies()
  collectRftokenFromResponses()
end

function verifySessionWithAccounts()
  local homeReferer = CONSTANTS.baseUrl .. "/dbank/live/app/home"
  for _, suffix in ipairs({ "?external=false", "?internal=false" }) do
    local url = CONSTANTS.acctsApi .. "/accounts" .. suffix
    local response = performApiRequest("GET", url, nil, nil, homeReferer)
    if response and (response:match("accountNumber") or response:match("accountsresponse")) then
      return true
    end
  end
  return false
end

function verifySessionWithHistory()
  local acctUrl = CONSTANTS.acctsApi .. "/history?allowAccountsCall=true&getExportAccountNums=true&getxuseraccts&locationId&pageId=history&transfers_display_xuser_accounts"
  if session.rftoken then
    acctUrl = acctUrl .. "&rftoken=" .. MM.urlencode(session.rftoken)
  end

  local response = connection:request("GET", acctUrl, nil, nil, buildRequestHeaders())
  syncSessionCookies()

  if response and (response:match("accountsresponse") or response:match("otherAccounts")) then
    return true
  end
  return false
end

function finalizeLogin(mfaResponse)
  local postLoginReferer = CONSTANTS.baseUrl .. "/dbank/live/app/postLogin"
  local homeReferer = CONSTANTS.baseUrl .. "/dbank/live/app/home"

  followPostLoginRedirect(mfaResponse)
  activateOlbSession(mfaResponse, postLoginReferer)

  local authtokenContent = performApiRequest(
    "GET",
    CONSTANTS.authApi .. "/user/authtoken",
    nil,
    nil,
    homeReferer
  )

  collectRftokenFromResponses(authtokenContent, mfaResponse)
  updateDevicePrivateFromAuthtoken(authtokenContent)

  if verifySessionWithAccounts() or verifySessionWithHistory() then
    session.loginComplete = true
    persistSessionState(rawget(_G, "LocalStorage"))
    return nil
  end

  if session.cookies and session.cookies:match("SESSION_TOKEN") and session.rftoken then
    session.loginComplete = true
    persistSessionState(rawget(_G, "LocalStorage"))
    return nil
  end

  if session.cookies and session.cookies:match("SESSION_TOKEN") then
    return "Login fehlgeschlagen: rftoken nicht zugaenglich (SESSION_TOKEN ok, aber Folge-Calls nicht authentifizierbar)."
  end

  return LoginFailed
end

function findTotpId()
  if not session.mfaMethods then
    return nil
  end
  for _, m in ipairs(session.mfaMethods) do
    if m.type == "totp" then
      return m.id
    end
  end
  return nil
end

function isMfaSuccess(response)
  local data = parseJson(response)
  if not data then
    return false
  end

  if data.errorCode then
    return false
  end

  if data.targetView == "success" or data.targetView == "redirect" then
    return true
  end

  if data.result then
    local result = parseJson(data.result)
    if result and result.success == "success" then
      return true
    end
  end

  return false
end

function ListAccounts(knownAccounts)
  if not hasValidSession() then
    return "No active session"
  end

  local acctUrl = CONSTANTS.acctsApi .. "/history?allowAccountsCall=true&getExportAccountNums=true&getxuseraccts&locationId&pageId=history&transfers_display_xuser_accounts"
  if session.rftoken then
    acctUrl = acctUrl .. "&rftoken=" .. MM.urlencode(session.rftoken)
  end

  local response = performApiRequest(
    "GET",
    acctUrl,
    nil,
    nil,
    CONSTANTS.baseUrl .. "/dbank/live/app/home"
  )
  if response then
    local data = parseJson(response)
    if data then
      local accountsData = data.accountsresponse or data.otherAccounts
      if accountsData then
        return parseAccounts(accountsData)
      end
    end
  end

  local homeReferer = CONSTANTS.baseUrl .. "/dbank/live/app/home"
  for _, suffix in ipairs({ "?external=false", "?internal=false" }) do
    local url = CONSTANTS.acctsApi .. "/accounts" .. suffix
    local response = performApiRequest("GET", url, nil, nil, homeReferer)
    if response then
      local data = parseJson(response)
      if data then
        local accountsData = data.accounts or data.accountsresponse or data.otherAccounts
        if accountsData then
          return parseAccounts(accountsData)
        end
      end
    end
  end

  return "Account discovery failed"
end

function buildMaskedAccountSuffix(actualNumber, displayAccountNumber)
  if type(displayAccountNumber) == "string" and displayAccountNumber ~= "" then
    return displayAccountNumber
  end
  if actualNumber ~= "unknown" and #actualNumber >= 4 then
    return "*" .. actualNumber:sub(-4)
  end
  return "*XXXX"
end

function buildWebsiteAccountLabel(acc, actualNumber, displayAccountNumber)
  local masked = buildMaskedAccountSuffix(actualNumber, displayAccountNumber)
  local nickname = trim(acc.nickname or "")
  if nickname == "" then
    nickname = trim(acc.description or "")
  end
  if nickname ~= "" and not masked:find(nickname, 1, true) then
    return nickname .. " " .. masked
  end
  return masked
end

function buildAccountNumberForMoneyMoney(acc, actualNumber, displayAccountNumber)
  return buildWebsiteAccountLabel(acc, actualNumber, displayAccountNumber)
end

function parseAccounts(accountsResponse)
  local accounts = {}

  for _, acc in ipairs(accountsResponse) do
    local actualNumber = extractAccountNumber(acc.accountNumber)
    local accountNumber = buildAccountNumberForMoneyMoney(acc, actualNumber, acc.displayAccountNumber)
    local accountName = acc.nickname or acc.description or "Presidential Account"

    table.insert(accounts, {
      name = accountName,
      accountNumber = accountNumber,
      bankCode = CONSTANTS.bankCode,
      currency = "USD",
      type = mapAccountType(acc.accountType or acc.category),
      _internalId = acc.id,
      _balance = acc.balance or acc.availableBalance or 0
    })
  end

  return accounts
end

function extractAccountNumber(accountNumber)
  if type(accountNumber) == "table" then
    return accountNumber.hostValue or accountNumber.displayValue or "unknown"
  elseif type(accountNumber) == "string" then
    return accountNumber
  end
  return "unknown"
end

function mapAccountType(accountType)
  if not accountType then
    return AccountTypeGiro
  end

  local typeMap = {
    checking = AccountTypeGiro,
    savings = AccountTypeSavings,
    credit = AccountTypeCreditCard,
    card = AccountTypeCreditCard,
    loan = AccountTypeLoan,
    mortgage = AccountTypeLoan,
    investment = AccountTypeSecurities,
    brokerage = AccountTypeSecurities
  }

  local mapped = typeMap[accountType:lower():match("^(%a+)")]
  return mapped or AccountTypeGiro
end

function RefreshAccount(account, since)
  if not account then
    return { balance = 0, transactions = {} }
  end

  if not hasValidSession() then
    return { balance = 0, transactions = {} }
  end

  local accountId = resolveAccountId(account)
  if not accountId then
    return { balance = 0, transactions = {} }
  end

  local startDate, endDate = calculateDateRange(since)
  local url = buildTransactionsUrl(accountId, startDate, endDate)

  local response = connection:request("GET", url, nil, nil, buildRequestHeaders())
  updateCookies()

  if not response then
    return { balance = 0, transactions = {} }
  end

  local data = parseJson(response)
  if not data or not data.transactionsresponse then
    return { balance = 0, transactions = {} }
  end

  return parseTransactions(data.transactionsresponse)
end

function resolveAccountId(account)
  if account._internalId and account._internalId ~= "" then
    return account._internalId
  end

  local discovered = ListAccounts({})
  if type(discovered) ~= "table" then
    return nil
  end

  for _, acc in ipairs(discovered) do
    if acc.accountNumber == account.accountNumber then
      return acc._internalId
    end
    if acc._internalId == account.accountNumber then
      return acc._internalId
    end
    if acc.name == account.name and acc.name ~= "" then
      return acc._internalId
    end
  end

  if #discovered == 1 then
    return discovered[1]._internalId
  end

  return nil
end

function isValidAccountId(accountId)
  return accountId and accountId ~= "" and accountId ~= "0" and accountId ~= "PLACEHOLDER" and accountId ~= "0000000000"
end

function calculateDateRange(since)
  local endDate = os.date("%Y-%m-%d %H:%M:%S", os.time())
  local now = os.time()
  local oneYearAgo = os.time({year = os.date("%Y", now) - 1, month = os.date("%m", now), day = os.date("%d", now)})

  local startDate
  if since and since > oneYearAgo then
    startDate = os.date("%Y-%m-%d %H:%M:%S", since)
  else
    local tenYearsAgo = os.time({year = os.date("%Y", now) - 10, month = 1, day = 1})
    startDate = os.date("%Y-%m-%d %H:%M:%S", tenYearsAgo)
  end

  return startDate, endDate
end

function buildTransactionsUrl(accountId, startDate, endDate)
  local url = CONSTANTS.acctsApi .. "/history/transactions?accountId=" .. MM.urlencode(accountId)
    .. "&dateRangeEnd=" .. MM.urlencode(endDate)
    .. "&dateRangeStart=" .. MM.urlencode(startDate)
    .. "&locationId=&locationName=&pageId=history"
  -- Add rftoken as URL parameter (like browser does)
  if session.rftoken then
    url = url .. "&rftoken=" .. MM.urlencode(session.rftoken)
  end
  return url
end

function parseTransactions(transactionsResponse)
  local balance = 0
  local transactions = {}

  for _, tx in ipairs(transactionsResponse) do
    local txAmount = tonumber(tx.amount) or 0
    local isCredit = tx.creditTransaction or false
    local txType = tx.transactionType or ""

    if txType:lower() == "withdrawal" or txType:lower() == "debit" or isCredit == false then
      txAmount = -math.abs(txAmount)
    else
      txAmount = math.abs(txAmount)
    end

    if tx.ledgerBalance then
      balance = tonumber(tx.ledgerBalance) or balance
    end

    local name, purpose = parseTransactionDescription(tx.generatedDescription or "")

    table.insert(transactions, {
      bookingDate = parseDate(tx.transactionDate),
      valueDate = parseDate(tx.transactionDate),
      amount = txAmount,
      purpose = purpose,
      name = name
    })
  end

  return { balance = balance, transactions = transactions }
end

function parseTransactionDescription(description)
  if not description or description == "" then
    return "", ""
  end

  -- Pattern: "Type ENTITY / NAME - DETAILS"
  local prefix, entity, detail = description:match("^([^/]+)%s+([^/]+)%s*/%s*([^%-]+)%-%s*(.+)$")
  if prefix and entity and detail then
    local name = normalizeWhitespace(entity .. " " .. detail)
    local purpose = normalizeWhitespace(prefix .. " - " .. detail)
    return name, purpose
  end

  -- Pattern: "Type / NAME - DETAILS"
  local prefix2, name2, detail2 = description:match("^([^/]+)%s*/%s*([^%-]+)%-%s*(.+)$")
  if prefix2 and name2 and detail2 then
    return normalizeWhitespace(name2), normalizeWhitespace(prefix2 .. " - " .. detail2)
  end

  -- Pattern: "Before / After" (no dash)
  local beforeSlash, afterSlash = description:match("^(.-)%s*/%s*(.+)$")
  if beforeSlash and afterSlash then
    local slashName, slashDetail = afterSlash:match("^(.-)%s*%-%s*(.+)$")
    if slashName and slashDetail then
      return normalizeWhitespace(slashName), normalizeWhitespace(beforeSlash .. " - " .. slashDetail)
    end
    return normalizeWhitespace(afterSlash), normalizeWhitespace(beforeSlash)
  end

  -- Simple description, no slash/dash
  return "", description
end

function normalizeWhitespace(str)
  return str:gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
end

function loginWithImportedCookies(cookieString)
  cookieString = cookieString:gsub("^COOKIE:", "")

  local formattedCookies = cookieString:gsub("^%s*(.-)%s*$", "%1")

  if not formattedCookies:match("=") then
    return "Invalid cookie format. Use: name=value;name2=value2"
  end

  if not formattedCookies:match("SESSION_TOKEN") or not formattedCookies:match("rftoken=") then
    return "Cookie import failed: Required cookies (SESSION_TOKEN, rftoken) not found."
  end

  session.rftoken = formattedCookies:match("rftoken=([^;]+)")
  session.cookies = formattedCookies
  session.cookieImportMode = true

  local testResponse = connection:request("GET",
    CONSTANTS.authApi .. "/user/authtoken",
    nil, nil, buildRequestHeaders())

  if testResponse and testResponse:match("{") then
    local acctUrl = CONSTANTS.acctsApi .. "/history?allowAccountsCall=true&getExportAccountNums=true&getxuseraccts&locationId&pageId=history&transfers_display_xuser_accounts"
    if session.rftoken then
      acctUrl = acctUrl .. "&rftoken=" .. MM.urlencode(session.rftoken)
    end
    local acctResponse = connection:request("GET", acctUrl, nil, nil, buildRequestHeaders())
    if acctResponse and (acctResponse:match("accountsresponse") or acctResponse:match("otherAccounts")) then
      return nil
    end
  end

  return "Cookie import failed (403 Forbidden). The bank rejected the cookies. This is likely due to: (1) IP address binding - cookies only work from same IP as browser, (2) Cloudflare security checks, or (3) Session already expired."
end

function handleCookieImportStep(credentials)
  local cookieString = credentials[1]

  if not cookieString or cookieString == "" then
    session.waitingForCookieImport = nil
    return "Cookie import cancelled. Please try again with valid cookies from your browser."
  end

  cookieString = cookieString:gsub("^COOKIE:", "")

  local formattedCookies = cookieString:gsub("^%s*(.-)%s*$", "%1")

  if not formattedCookies:match("rftoken=") then
    return {
      title = "Cookie Import Required",
      challenge = "Cookie string must include rftoken. Please copy the COMPLETE Cookie header from your browser (including SESSION_TOKEN and rftoken).",
      label = "Cookie string"
    }
  end

  session.rftoken = formattedCookies:match("rftoken=([^;]+)")
  session.cookies = formattedCookies
  session.cookieImportMode = true
  session.waitingForCookieImport = nil

  local testUrl = CONSTANTS.acctsApi .. "/history?allowAccountsCall=true&getExportAccountNums=true&getxuseraccts&locationId&pageId=history&transfers_display_xuser_accounts"
  if session.rftoken then
    testUrl = testUrl .. "&rftoken=" .. MM.urlencode(session.rftoken)
  end
  local testResponse = connection:request("GET", testUrl, nil, nil, buildRequestHeaders())

  if testResponse and (testResponse:match("accountsresponse") or testResponse:match("otherAccounts")) then
    return nil
  end

  local body = testResponse and testResponse:lower() or ""
  if body:find("forbidden") or body:find("unauthorized") or body:find("\"status\"%s*:%s*40") then
    return "Cookie import failed: Invalid or expired session. Please login to Presidential Bank in your browser again, copy fresh cookies from DevTools → Network (including SESSION_TOKEN and rftoken), and retry."
  end
  if body:find("internal server error") or body:find("\"status\"%s*:%s*500") then
    session.waitingForCookieImport = true
    return {
      title = "Cookie Import - Server Error",
      challenge = "The server returned an internal error. This may be temporary.\n\nPlease try again with the same cookies, or get fresh cookies from your browser:",
      label = "Cookie string"
    }
  end

  return "Cookie import failed. The session may be expired or the cookies are incomplete. Please login to Presidential Bank in your browser, copy fresh cookies from DevTools → Network (including SESSION_TOKEN and rftoken), and retry."
end

function hasValidSession()
  if session.loginComplete then
    return true
  end
  return session.cookies and session.cookies ~= "" and session.cookies:match("SESSION_TOKEN")
end

function buildApiHeaders(referer)
  return withCookieHeader({
    ["Accept"] = "application/json, text/plain, */*",
    ["Content-Type"] = "application/json",
    ["Origin"] = CONSTANTS.baseUrl,
    ["Referer"] = referer or (CONSTANTS.baseUrl .. "/dbank/live/app/mfa"),
    ["X-Requested-With"] = "XMLHttpRequest"
  })
end

function buildRequestHeaders()
  return withCookieHeader({
    ["Accept"] = "*/*",
    ["Accept-Language"] = "de-DE,de;q=0.9",
    ["Referer"] = CONSTANTS.baseUrl .. "/dbank/live/app/home/olb/history?accountId=D0",
    ["Sec-Fetch-Dest"] = "empty",
    ["Sec-Fetch-Mode"] = "cors",
    ["Sec-Fetch-Site"] = "same-origin",
    ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15"
  })
end

function extractCookieValue(cookies, name)
  if not cookies then return nil end
  return cookies:match(name .. "=([^;]+)")
end

function updateCookies()
  if session.cookieImportMode then
    return
  end
  syncSessionCookies()
end

function parseJson(str)
  if not str then
    return nil
  end

  local success, result = pcall(function()
    return JSON(str):dictionary()
  end)

  if success then
    return result
  end
  return nil
end

function parseDate(dateStr)
  if not dateStr or dateStr == "" then
    return nil
  end

  -- ISO format: YYYY-MM-DD
  local year, month, day = dateStr:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if year and month and day then
    return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
  end

  -- US format: MM/DD/YYYY
  month, day, year = dateStr:match("(%d%d?)/(%d%d?)/(%d%d%d%d)")
  if month and day and year then
    return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
  end

  return nil
end

function extractCsrfTokenFromCookies(cookies)
  if not cookies then
    return nil
  end
  return cookies:match("CSRFToken=([^;]+)")
end

function EndSession()
  local storage = rawget(_G, "LocalStorage")

  if session.persistedConnection and storage and session.loginComplete then
    persistSessionState(storage)
    return
  end

  if session.cookies and session.cookies ~= "" and not session.persistedConnection then
    pcall(function()
      connection:request("GET", CONSTANTS.baseUrl .. "/dbank/live/app/logout?reason=userlogout", nil, nil, {})
    end)
    if storage then
      clearPersistedSessionStorage(storage)
    end
  end

  session = {}
end
