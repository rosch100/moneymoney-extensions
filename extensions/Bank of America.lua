--
-- Bank of America — MoneyMoney Web Banking Extension (Beta 0.9, Cookie-Import)
-- https://www.bankofamerica.com
-- Dokumentation: docs/LUA-EXTENSIONS.md
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 0.90,
  url         = "https://secure.bankofamerica.com",
  services    = {"Bank of America"},
  description = "Bank of America — Beta (Cookie-Import)"
}

local CONSTANTS = {
  baseUrl = "https://secure.bankofamerica.com",
  bankCode = "BOA",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15",
  loginPartnerId = "7AB3CF1341CA460A84D1167C04F8F5E4",
  loginInitContainerUrl = "https://secure.bankofamerica.com/login/rest/sas/sparta/ls/entry/v2/initContainer",
  loginInitAuthUrl = "https://secure.bankofamerica.com/ahloginws/rest/sas/sparta/ls/v2/initAuthentication",
  loginVerifyUrl = "https://secure.bankofamerica.com/ahloginws/rest/sas/sparta/ls/v2/verifyAuthentication",
  loginStepUpUrl = "https://secure.bankofamerica.com/ahloginws/rest/sas/sparta/ls/secure/v3/initiateStepUp",
  loginSendCodeUrl = "https://secure.bankofamerica.com/ahloginws/rest/sas/sparta/ls/secure/v2/sendCode",
  loginValidateCodeUrl = "https://secure.bankofamerica.com/ahloginws/rest/sas/sparta/ls/secure/v2/validateCode",
  loginSignInGoUrl = "https://secure.bankofamerica.com/myaccounts/signin/signIn.go?returnSiteIndicator=GAIEC&langPref=en-us&request_locale=en-us&capturemode=N&newuser=false",
  signOnScreenUrl = "https://secure.bankofamerica.com/login/sign-in/signOnV2Screen.go",
  signOnPostUrl = "https://secure.bankofamerica.com/login/sign-in/internal/entry/signOnV2.go",
  signOnSuccessUrl = "https://secure.bankofamerica.com/login/sign-in/signOnSuccessRedirect.go",
  authCodeInitUrl = "https://secure.bankofamerica.com/login/authcode/authCodeInitialize.go?acw_page_id=VIPAA-OTP-ELECTIVE&inScript=true",
  authCodeDisplayUrl = "https://secure.bankofamerica.com/login/authcode/authcodeDisplay.go",
  sendAuthCodeUrl = "https://secure.bankofamerica.com/login/authcode/sendAuthCode.go",
  validateAuthCodeUrl = "https://secure.bankofamerica.com/login/authcode/validateAuthCode.go",
  validateChallengeUrl = "https://secure.bankofamerica.com/login/sign-in/validateChallengeAnswerV2.go",
  loginReferer = "https://secure.bankofamerica.com/login/sign-in/signOnV2Screen.go",
  loginOrigin = "https://secure.bankofamerica.com",
}

local connection
local session = { cookies = "", adxToken = "", statementPageUrl = "", persistedConnection = false }

local DEBUG_PREFIX = "BoA-DEBUG:"

function boaDebugLog(message)
  if type(message) ~= "string" or message == "" then
    return
  end
  if MM and type(MM.printStatus) == "function" then
    MM.printStatus(DEBUG_PREFIX .. " " .. message)
  end
end

function boaDebugShortUrl(url)
  if type(url) ~= "string" then
    return "(keine URL)"
  end
  local path = url:match("^https?://[^/]+(.+)$")
  if path then
    return path
  end
  return url
end

function boaDebugLen(value)
  if type(value) ~= "string" then
    return 0
  end
  return #value
end

function boaDebugSummarizeCredentials(username, password)
  local userLen = boaDebugLen(username)
  local passLen = boaDebugLen(password)
  local parts = {
    "credentials: onlineId.len=" .. tostring(userLen),
    "passcode.len=" .. tostring(passLen),
  }
  if userLen == 0 then
    table.insert(parts, "WARN onlineId leer")
  end
  if passLen == 0 then
    table.insert(parts, "WARN passcode leer")
  end
  if password and password:match("^COOKIE:") then
    table.insert(parts, "modus=COOKIE-Import")
  end
  return table.concat(parts, ", ")
end

function boaDebugSummarizeFormBody(body)
  if type(body) ~= "string" or body == "" then
    return "formBody: leer"
  end

  local fieldLengths = {}
  for part in body:gmatch("[^&]+") do
    local key, value = part:match("^([^=]+)=(.*)$")
    if key then
      local decoded = value
      if MM and type(MM.urldecode) == "function" then
        local ok, decodedValue = pcall(MM.urldecode, value)
        if ok and type(decodedValue) == "string" then
          decoded = decodedValue
        end
      end
      if key == "passcode" or key == "new-passcode" then
        fieldLengths[key] = "len=" .. tostring(#decoded) .. " (redacted)"
      elseif key == "onlineId" then
        fieldLengths[key] = "len=" .. tostring(#decoded)
      else
        fieldLengths[key] = "len=" .. tostring(#decoded)
      end
    end
  end

  local orderedKeys = {
    "csrfTokenHidden", "onlineId", "passcode", "_ib", "webAuthAPI", "_u2support",
  }
  local parts = { "formBody.totalLen=" .. tostring(#body) }
  for _, key in ipairs(orderedKeys) do
    if fieldLengths[key] then
      table.insert(parts, key .. "=" .. fieldLengths[key])
    end
  end
  for key, summary in pairs(fieldLengths) do
    local known = false
    for _, orderedKey in ipairs(orderedKeys) do
      if orderedKey == key then
        known = true
        break
      end
    end
    if not known then
      table.insert(parts, key .. "=" .. summary)
    end
  end

  return table.concat(parts, ", ")
end

function extractSignOnErrorSnippet(html)
  if type(html) ~= "string" or html == "" then
    return nil
  end
  if html:match("doesn't match our records") or html:match("doesn?t match our records") then
    return "The information you entered doesn't match our records."
  end
  if html:match("InvalidCredentialsExceptionV2") then
    return "InvalidCredentialsExceptionV2"
  end
  local title = html:match('class="title TLu_ERROR">([^<]+)')
  if title and title ~= "" then
    return title:gsub("%s+", " "):match("^%s*(.-)%s*$")
  end
  local vipaaError = html:match('class="TLu_ERROR"[^>]*>%s*<li>([^<]+)')
  if vipaaError and vipaaError ~= "" then
    return vipaaError:gsub("%s+", " "):match("^%s*(.-)%s*$")
  end
  return nil
end

function boaDebugSummarizeResponse(method, url, response, respHeaders)
  local parts = {
    method .. " " .. boaDebugShortUrl(url),
    "response.len=" .. tostring(boaDebugLen(response)),
  }

  local location = extractResponseHeader(respHeaders, "Location")
  if location and location ~= "" then
    table.insert(parts, "Location=" .. boaDebugShortUrl(location))
  else
    table.insert(parts, "Location=(nicht in Headers, evtl. Redirect bereits gefolgt)")
  end

  local cookieLen = boaDebugLen(session.cookies)
  table.insert(parts, "cookies.len=" .. tostring(cookieLen))
  if session.cookies and session.cookies:match("SMSESSION=") then
    table.insert(parts, "SMSESSION=ja")
  else
    table.insert(parts, "SMSESSION=nein")
  end

  local errorSnippet = extractSignOnErrorSnippet(response)
  if errorSnippet then
    table.insert(parts, "error=" .. errorSnippet)
  end

  if isSignOnCredentialErrorPage(response) then
    table.insert(parts, "detected=credential-error-page")
  elseif isSignOnSuccessRedirect(location) then
    table.insert(parts, "detected=signOnSuccessRedirect")
  elseif isDirectAccountRedirect(location) then
    table.insert(parts, "detected=direct-account-redirect")
  end

  return table.concat(parts, " | ")
end

function boaDebugLogRequest(method, url, body)
  boaDebugLog(method .. " " .. boaDebugShortUrl(url))
  if body and body ~= "" then
    boaDebugLog(boaDebugSummarizeFormBody(body))
  end
end

function boaDebugLogResponse(method, url, response, respHeaders, context)
  local summary = boaDebugSummarizeResponse(method, url, response, respHeaders)
  if context and context ~= "" then
    summary = summary .. " | context=" .. context
  end
  boaDebugLog(summary)
end

local function trimCookiePart(value)
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function mergeCookies(existingCookies, newCookies)
  if not newCookies or newCookies == "" then
    return existingCookies or ""
  end

  local cookieMap = {}
  if existingCookies and existingCookies ~= "" then
    for part in existingCookies:gmatch("[^;]+") do
      local name, value = part:match("^([^=]+)=(.+)$")
      if name then
        cookieMap[trimCookiePart(name)] = trimCookiePart(value)
      end
    end
  end

  for part in newCookies:gmatch("[^;]+") do
    local name, value = part:match("^([^=]+)=(.+)$")
    if name then
      cookieMap[trimCookiePart(name)] = trimCookiePart(value)
    end
  end

  local merged = {}
  for name, value in pairs(cookieMap) do
    table.insert(merged, name .. "=" .. value)
  end
  return table.concat(merged, "; ")
end

local function refreshSessionCookies()
  if not connection or type(connection.getCookies) ~= "function" then
    return
  end
  local newCookies = connection:getCookies()
  if newCookies and newCookies ~= "" then
    session.cookies = mergeCookies(session.cookies, newCookies)
  end
end

local function syncCookieHeader(requestHeaders)
  requestHeaders["Cookie"] = session.cookies
end

-- connection:request liefert (content, charset, mimeType, filename, headers).
-- Wir verwenden nur content + mimeType (Letzteres fuer PDF-Erkennung in
-- GetStatement); der charset-Wert (z.B. "utf-8") wird mit `_` verworfen,
-- damit Caller ihn nicht versehentlich als HTTP-Status interpretieren.
local function performGet(url, requestHeaders, refererUrl)
  if refererUrl then
    requestHeaders["Referer"] = refererUrl
  end
  syncCookieHeader(requestHeaders)
  local response, _, mimeType = connection:request("GET", url, nil, nil, requestHeaders)
  refreshSessionCookies()
  syncCookieHeader(requestHeaders)
  return response, mimeType
end

local function performPost(url, postData, contentType, requestHeaders, refererUrl)
  if refererUrl then
    requestHeaders["Referer"] = refererUrl
  end
  syncCookieHeader(requestHeaders)
  local body = postData or ""
  local response, _, mimeType = connection:request("POST", url, body, contentType, requestHeaders)
  refreshSessionCookies()
  syncCookieHeader(requestHeaders)
  return response, mimeType
end

local function performRequest(method, url, body, contentType, requestHeaders, refererUrl)
  if refererUrl then
    requestHeaders["Referer"] = refererUrl
  end
  syncCookieHeader(requestHeaders)
  local response, _, mimeType, _, respHeaders = connection:request(
    method, url, body, contentType, requestHeaders
  )
  refreshSessionCookies()
  syncCookieHeader(requestHeaders)
  return response, mimeType, respHeaders
end

local function buildRequestHeaders(refererUrl)
  local headers = {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["User-Agent"] = CONSTANTS.userAgent,
    ["Sec-Fetch-Site"] = "same-origin",
    ["Sec-Fetch-Mode"] = "navigate",
    ["Sec-Fetch-Dest"] = "document",
    ["Cookie"] = session.cookies
  }
  if refererUrl then
    headers["Referer"] = refererUrl
  end
  return headers
end

local function buildAjaxPostHeaders(refererUrl)
  return {
    ["Accept"] = "*/*",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Origin"] = CONSTANTS.baseUrl,
    ["User-Agent"] = CONSTANTS.userAgent,
    ["Sec-Fetch-Site"] = "same-origin",
    ["Sec-Fetch-Mode"] = "cors",
    ["Sec-Fetch-Dest"] = "empty",
    ["X-Requested-With"] = "XMLHttpRequest",
    ["Referer"] = refererUrl,
    ["Cookie"] = session.cookies
  }
end

local function buildJsonPostHeaders(refererUrl)
  return {
    ["Accept"] = "*/*",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Content-Type"] = "application/json; charset=UTF-8",
    ["Origin"] = CONSTANTS.baseUrl,
    ["User-Agent"] = CONSTANTS.userAgent,
    ["Sec-Fetch-Site"] = "same-origin",
    ["Sec-Fetch-Mode"] = "cors",
    ["Sec-Fetch-Dest"] = "empty",
    ["Referer"] = refererUrl,
    ["Cookie"] = session.cookies
  }
end

local function buildPdfGetHeaders(refererUrl)
  return {
    ["Accept"] = "application/pdf,application/octet-stream,*/*",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["User-Agent"] = CONSTANTS.userAgent,
    ["Sec-Fetch-Site"] = "same-origin",
    ["Sec-Fetch-Mode"] = "navigate",
    ["Sec-Fetch-Dest"] = "document",
    ["Referer"] = refererUrl,
    ["Cookie"] = session.cookies
  }
end

local function extractStatementPageUrl(html)
  for urlMatch in html:gmatch('["\']([^"\']*mycommunications/statements/statement%.go[^"\']*)["\']') do
    local url = urlMatch:gsub("&amp;", "&")
    if url:sub(1, 1) == "/" then
      url = CONSTANTS.baseUrl .. url
    elseif not url:find("^http") then
      url = CONSTANTS.baseUrl .. "/" .. url
    end
    return url
  end
  return nil
end

local function rememberStatementPageUrl(html, adxToken)
  local statementUrl = extractStatementPageUrl(html)
  if statementUrl then
    session.statementPageUrl = statementUrl
    return
  end

  local profileEligibility = html:match("profileEligibilty=([A-Z0-9]+)")
  if not profileEligibility or not adxToken then
    return
  end

  local returnSiteIndicator = html:match("returnSiteIndicator=([A-Z]+)") or "GAIMW"
  session.statementPageUrl = CONSTANTS.baseUrl ..
    "/mycommunications/statements/statement.go?request_locale=en-us" ..
    "&profileEligibilty=" .. profileEligibility ..
    "&adx=" .. adxToken ..
    "&source=adc&returnSiteIndicator=" .. returnSiteIndicator
end

local function buildStatementPageUrl(adxToken)
  if session.statementPageUrl and session.statementPageUrl ~= "" then
    local url = session.statementPageUrl:gsub("&amp;", "&")
    if adxToken and not url:find("adx=") then
      url = url .. (url:find("%?") and "&" or "?") .. "adx=" .. adxToken
    end
    return url
  end

  return CONSTANTS.baseUrl ..
    "/mycommunications/statements/statement.go?request_locale=en-us&source=adc&adx=" .. adxToken
end

local function normalizeStatementPeriodUrl(urlMatch)
  local url = urlMatch:gsub("&amp;", "&")
  if url:sub(1, 1) == "/" then
    url = CONSTANTS.baseUrl .. url
  elseif not url:find("^http") then
    if url:find("account%-details%.go") then
      url = CONSTANTS.baseUrl .. "/myaccounts/details/card/" .. url
    else
      url = CONSTANTS.baseUrl .. "/" .. url
    end
  end

  if not url:find("filter=") then
    if url:find("%?") then
      url = url .. "&filter=0&sort=0&order=0"
    else
      url = url .. "?filter=0&sort=0&order=0"
    end
  end

  return url
end

local function mergeTransactions(allTransactions, seenTransactions, pageTransactions)
  for _, trans in ipairs(pageTransactions) do
    local key = (trans.bookingDate or "") .. "|" .. (trans.purpose or "") .. "|" .. tostring(trans.amount)
    if not seenTransactions[key] then
      seenTransactions[key] = true
      table.insert(allTransactions, trans)
    end
  end
end

local function isActivityTransactionUrl(urlMatch)
  if urlMatch:find("download%-transactions%.go") then
    return false
  end
  if urlMatch:find("downloadStmtFromDateList") then
    return false
  end
  return urlMatch:find("target=stmtFromDateList") or
         urlMatch:find("target=stmtFromPreviousLink") or
         urlMatch:find("target=stmtFromNextLink")
end

local function extractGotoSelectTransTop(html)
  local lower = html:lower()
  local selectStart = lower:find('id="goto_select_trans_top"', 1, true)
  if not selectStart then
    return nil
  end
  local selectEnd = lower:find("</select>", selectStart)
  if not selectEnd then
    return nil
  end
  return html:sub(selectStart, selectEnd + 9)
end

local function extractActivityPeriodOptions(html)
  local options = {}
  local section = extractGotoSelectTransTop(html)
  if not section then
    return options
  end

  local pos = 1
  while true do
    local optStart, optEnd = section:lower():find("<option", pos)
    if not optStart then
      break
    end
    local optClose = section:lower():find("</option>", optEnd + 1)
    if not optClose then
      break
    end
    local optionHtml = section:sub(optStart, optClose + 9)
    pos = optClose + 9

    local urlMatch = optionHtml:match('value="([^"]*target=stmtFromDateList[^"]*)"')
    local label = optionHtml:match(">([^<]+)</option>")
    if urlMatch and label and isActivityTransactionUrl(urlMatch) then
      table.insert(options, {
        label = label:gsub("^%s*", ""):gsub("%s*$", ""),
        url = normalizeStatementPeriodUrl(urlMatch)
      })
    end
  end

  return options
end

local function collectActivityPeriodLabels(html)
  local labels = {}
  local seen = {}
  for _, opt in ipairs(extractActivityPeriodOptions(html)) do
    if not seen[opt.label] then
      seen[opt.label] = true
      table.insert(labels, opt.label)
    end
  end
  return labels
end

local function findActivityPeriodUrl(html, periodLabel)
  for _, opt in ipairs(extractActivityPeriodOptions(html)) do
    if opt.label == periodLabel then
      return opt.url
    end
  end
  return nil
end

local function updateAdxFromResponse(response, adxToken)
  local responseAdx = response:match('adx=["\']?([0-9a-f]+)') or
                      response:match('["\']adx["\']%s*[:=]%s*["\']?([0-9a-f]+)')
  if responseAdx then
    session.adxToken = responseAdx
    return responseAdx
  end
  return adxToken
end

local function asActivityDateListUrl(url)
  if not url then
    return nil
  end
  return url:gsub("target=stmtFromPreviousLink", "target=stmtFromDateList")
           :gsub("target=stmtFromNextLink", "target=stmtFromDateList")
end

local function extractPreviousPeriodUrl(html)
  for urlMatch in html:gmatch('["\']([^"\']*target=stmtFromPreviousLink[^"\']*)["\']') do
    if isActivityTransactionUrl(urlMatch) then
      return asActivityDateListUrl(normalizeStatementPeriodUrl(urlMatch))
    end
  end
  return nil
end

local function warmupActivitySession(requestHeaders, refererUrl)
  performGet(
    CONSTANTS.baseUrl .. "/myaccounts/accounts-overview/topNav.go",
    requestHeaders,
    refererUrl
  )
end

local function warmupStatementSession(adxToken, accountDetailsReferer)
  local refererUrl = accountDetailsReferer or
    CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go?filter=0&sort=0&order=0"
  local requestHeaders = buildRequestHeaders(refererUrl)
  local statementUrl = buildStatementPageUrl(adxToken)
  local response = performGet(statementUrl, requestHeaders, refererUrl)
  if not response then
    return buildStatementPageUrl(adxToken)
  end

  rememberStatementPageUrl(response, adxToken)
  updateAdxFromResponse(response, adxToken)
  return buildStatementPageUrl(session.adxToken or adxToken)
end

local function ensureAdxInUrl(url, adxToken)
  if not adxToken or url:find("adx=") then
    return url
  end
  if url:find("%?") then
    return url .. "&adx=" .. adxToken
  end
  return url .. "?adx=" .. adxToken
end

local function shouldStopForSince(pageTransactions, sinceTimestamp)
  if not sinceTimestamp or #pageTransactions == 0 then
    return false
  end
  for _, trans in ipairs(pageTransactions) do
    if trans.bookingDate >= sinceTimestamp then
      return false
    end
  end
  return true
end

-- Load Activity periods via Go to: dropdown (stmtFromDateList).
local function loadActivityTransactionsChain(startHtml, adxToken, sinceTimestamp, seenTransactions, allTransactions, requestHeaders, refererUrl, maxPages)
  local currentHtml = startHtml
  local periodLabels = collectActivityPeriodLabels(startHtml)
  local pagesLoaded = 0

  if #periodLabels == 0 then
    mergeTransactions(allTransactions, seenTransactions, parseTransactionsFromPage(startHtml, sinceTimestamp, requestHeaders, refererUrl))
    return 1
  end

  for _, periodLabel in ipairs(periodLabels) do
    if pagesLoaded >= maxPages then
      break
    end

    local periodUrl = findActivityPeriodUrl(currentHtml, periodLabel)
    if not periodUrl then
      periodUrl = extractPreviousPeriodUrl(currentHtml)
    end

    if periodUrl then
      periodUrl = ensureAdxInUrl(periodUrl, adxToken)
      local response = performGet(periodUrl, requestHeaders, refererUrl)
      if response then
        currentHtml = response
        refererUrl = periodUrl
        adxToken = updateAdxFromResponse(response, adxToken)
      end
    end

    local pageTransactions = parseTransactionsFromPage(currentHtml, sinceTimestamp, requestHeaders, refererUrl)
    mergeTransactions(allTransactions, seenTransactions, pageTransactions)
    pagesLoaded = pagesLoaded + 1

    if shouldStopForSince(pageTransactions, sinceTimestamp) then
      break
    end
  end

  return pagesLoaded
end

local function ensureConnection()
  if not connection then
    local storage = rawget(_G, "LocalStorage")
    if storage and storage.connection then
      connection = storage.connection
    else
      connection = Connection()
      if storage then
        storage.connection = connection
      end
    end
    connection.language = "en-US"
  end
end

function encodeJson(obj)
  if JSON then
    local ok, result = pcall(function() return JSON():set(obj):json() end)
    if ok and type(result) == "string" then
      return result
    end
  end
  if type(obj) ~= "table" then
    if type(obj) == "string" then
      return string.format("%q", obj)
    end
    if type(obj) == "boolean" then
      return obj and "true" or "false"
    end
    if obj == nil then
      return "null"
    end
    return tostring(obj)
  end

  local parts = {}
  if #obj > 0 then
    for _, value in ipairs(obj) do
      table.insert(parts, encodeJson(value))
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  for key, value in pairs(obj) do
    local encodedValue
    if type(value) == "table" then
      encodedValue = encodeJson(value)
    elseif type(value) == "string" then
      encodedValue = string.format("%q", value)
    elseif type(value) == "boolean" then
      encodedValue = value and "true" or "false"
    elseif type(value) == "number" then
      encodedValue = tostring(value)
    else
      encodedValue = "null"
    end
    table.insert(parts, string.format("%q", key) .. ":" .. encodedValue)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function parseJson(jsonStr)
  if type(jsonStr) ~= "string" or jsonStr == "" then
    return nil
  end
  jsonStr = jsonStr:match("^%s*(.-)%s*$")
  if not jsonStr:match("^[%[{]") then
    return nil
  end
  if JSON then
    local ok, result = pcall(function() return JSON(jsonStr):dictionary() end)
    if ok and type(result) == "table" then
      return result
    end
    ok, result = pcall(function() return JSON(jsonStr):array() end)
    if ok and type(result) == "table" then
      return result
    end
  end
  return nil
end

function base64Encode(data)
  if type(data) ~= "string" then
    return nil
  end
  if type(MM.base64Encode) == "function" then
    return MM.base64Encode(data)
  end
  if type(MM.base64encode) == "function" then
    return MM.base64encode(data)
  end
  return nil
end

function canUseRsaLogin()
  return type(MM.rsaEncrypt) == "function"
end

function buildLoginFilterRules()
  return {
    { value = "CONSUMER", name = "PLATFORM" },
    { value = "BOA", name = "BRAND" },
    { value = "WEB", name = "CHANNEL" },
    { value = "SignInIdPwd", name = "FLOW" },
  }
end

function buildClientSignalsRa()
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local payload = {
    client_signals = {
      session = {
        brand = "GWIM",
        timestamp = timestamp,
        activity = "login",
        url = CONSTANTS.loginReferer,
        user_agent = CONSTANTS.userAgent,
        ip = nil,
      },
      device = {
        browser = "Safari",
        browser_version = "26.5",
        os = "macOS",
        platform = "MacIntel",
        language = "en-US",
      },
      behavior = {
        keystroke_event_count = 0,
      },
    },
  }
  local jsonPayload = encodeJson(payload)
  local encoded = base64Encode(jsonPayload)
  if not encoded then
    return nil
  end
  return encoded
end

function decodeSpkiPublicKey(spkiB64)
  if type(spkiB64) ~= "string" or spkiB64 == "" then
    return nil
  end
  if type(MM.rsaPkcs8decode) ~= "function" then
    return nil
  end

  local pem = "-----BEGIN PUBLIC KEY-----\n" .. spkiB64 .. "\n-----END PUBLIC KEY-----"
  local ok, keyTable = pcall(MM.rsaPkcs8decode, pem)
  if ok and type(keyTable) == "table" then
    return keyTable
  end

  ok, keyTable = pcall(MM.rsaPkcs8decode, spkiB64)
  if ok and type(keyTable) == "table" then
    return keyTable
  end

  return nil
end

function buildCipherEnvelope(sessionKey, encryptedBinary)
  if type(sessionKey) ~= "table" or type(encryptedBinary) ~= "string" or encryptedBinary == "" then
    return nil
  end
  local encryptedData = base64Encode(encryptedBinary)
  if not encryptedData then
    return nil
  end

  local envelope = {
    keyId = sessionKey.keyId,
    publicKey = sessionKey.publicKey,
    algo = sessionKey.algo,
    encryptedData = encryptedData,
  }
  local envelopeJson = encodeJson(envelope)
  return base64Encode(envelopeJson)
end

function encryptCredential(sessionKey, plaintext)
  if type(plaintext) ~= "string" or plaintext == "" then
    return nil, "Leerer Anmeldedaten-Wert"
  end
  if not canUseRsaLogin() then
    return nil, "MM.rsaEncrypt nicht verfügbar"
  end

  local keyTable = decodeSpkiPublicKey(sessionKey.publicKey)
  if not keyTable then
    return nil, "Public Key konnte nicht dekodiert werden"
  end

  local paddingSpecs = { "pkcs1-oaep sha256", "pkcs1-oaep sha256 sha1" }
  for _, paddingSpec in ipairs(paddingSpecs) do
    local ok, encryptedBinary = pcall(function()
      return MM.rsaEncrypt(keyTable, plaintext, paddingSpec)
    end)
    if ok and type(encryptedBinary) == "string" and encryptedBinary ~= "" then
      local cipherValue = buildCipherEnvelope(sessionKey, encryptedBinary)
      if cipherValue then
        return cipherValue
      end
    end
  end

  return nil, "RSA-Verschlüsselung fehlgeschlagen"
end

function buildTokenSet(tokenType, cipherValue)
  return {
    type = tokenType,
    value = {
      cipherData = {
        value = cipherValue,
      },
    },
  }
end

local function buildLoginApiHeaders()
  return {
    ["Accept"] = "application/json",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Content-Type"] = "application/json",
    ["Cache-Control"] = "max-age=0",
    ["Origin"] = CONSTANTS.loginOrigin,
    ["Referer"] = CONSTANTS.loginReferer,
    ["User-Agent"] = CONSTANTS.userAgent,
    ["APP-NAME"] = "CONSUMER",
    ["Cookie"] = session.cookies,
  }
end

local function performLoginApiPost(url, bodyTable)
  ensureConnection()
  local headers = buildLoginApiHeaders()
  local body = encodeJson(bodyTable)
  syncCookieHeader(headers)
  local response = connection:request("POST", url, body, "application/json", headers)
  refreshSessionCookies()
  syncCookieHeader(headers)
  return response
end

function parseLoginApiError(response)
  if type(response) ~= "string" or response == "" then
    return "Keine Antwort vom Login-Server."
  end
  local data = parseJson(response)
  if data and type(data.errorInfo) == "table" and data.errorInfo[1] then
    local info = data.errorInfo[1]
    if type(info) == "table" then
      if info.description and info.description ~= "" then
        return info.description
      end
      if info.code and info.code ~= "" then
        return info.code
      end
    end
  end

  local description = response:match('"description"%s*:%s*"([^"]+)"')
  if description and description ~= "" then
    return description
  end
  local code = response:match('"errorInfo"%s*:%s*%[%s*{%s*"code"%s*:%s*"([^"]+)"')
  if code and code ~= "" then
    return code
  end

  return nil
end

function isLoginCompletionOk(response)
  if type(response) ~= "string" or response == "" then
    return false
  end
  local data = parseJson(response)
  if data
    and type(data.completion) == "table"
    and tostring(data.completion.code) == "100" then
    return true
  end
  return response:match('"completion"%s*:%s*{%s*"code"%s*:%s*"100"') ~= nil
end

function fetchLoginSessionKey()
  local body = {
    partnerId = CONSTANTS.loginPartnerId,
    filterRules = buildLoginFilterRules(),
    passkeyCapabilities = { supportsPasskeys = true },
  }
  local response = performLoginApiPost(CONSTANTS.loginInitContainerUrl, body)
  local errorMessage = parseLoginApiError(response)
  if errorMessage then
    return nil, errorMessage
  end
  if not isLoginCompletionOk(response) then
    return nil, "Login-Initialisierung fehlgeschlagen."
  end

  local data = parseJson(response)
  if not data or type(data.sessionPublicKey) ~= "string" or data.sessionPublicKey == "" then
    return nil, "Kein sessionPublicKey in initContainer-Antwort."
  end

  return {
    keyId = data.keyId or "hsm_enc_v1_authhub-key",
    publicKey = data.sessionPublicKey,
    algo = data.algo or "RSA/NONE/OAEPWithSHA256AndMGF1Padding",
  }
end

function submitOnlineId(sessionKey, username)
  local cipherValue, encryptError = encryptCredential(sessionKey, username)
  if not cipherValue then
    return nil, encryptError or "Benutzername konnte nicht verschlüsselt werden."
  end

  local body = {
    partnerId = CONSTANTS.loginPartnerId,
    filterRules = buildLoginFilterRules(),
    tokenSets = { buildTokenSet("ONLINE_ID", cipherValue) },
  }
  local response = performLoginApiPost(CONSTANTS.loginInitAuthUrl, body)
  local errorMessage = parseLoginApiError(response)
  if errorMessage then
    return nil, errorMessage
  end
  if not isLoginCompletionOk(response) then
    return nil, "initAuthentication fehlgeschlagen."
  end

  return cipherValue
end

function buildVerifyProcessRules()
  local rules = {
    { value = CONSTANTS.loginPartnerId, name = "PARTNER_ID" },
    { value = "false", name = "SAVE_ONLINE_ID" },
  }
  local clientSignals = buildClientSignalsRa()
  if clientSignals then
    table.insert(rules, { value = clientSignals, name = "_RA" })
  end
  return rules
end

function verifyCredentials(sessionKey, username, password, onlineIdCipher)
  local passwordCipher, passwordError = encryptCredential(sessionKey, password)
  if not passwordCipher then
    return nil, passwordError or "Passwort konnte nicht verschlüsselt werden."
  end

  local body = {
    processRules = buildVerifyProcessRules(),
    tokenSets = {
      buildTokenSet("ONLINE_ID", onlineIdCipher),
      buildTokenSet("PASSWORD", passwordCipher),
    },
  }
  local response = performLoginApiPost(CONSTANTS.loginVerifyUrl, body)
  local errorMessage = parseLoginApiError(response)
  if errorMessage then
    return nil, errorMessage
  end
  if not isLoginCompletionOk(response) then
    return nil, "verifyAuthentication fehlgeschlagen."
  end

  return true
end

function buildMfaProcessRules()
  return {
    { name = "SourceChannel", value = "VMA" },
    { name = "Profile", value = "A01" },
    { name = "AuthenticationContext", value = "SGNONCHLNG" },
  }
end

function extractSecuredContactPoint(response)
  local data = parseJson(response)
  if data then
    local candidates = {
      data.securedContactPoint,
      data.securedContactPoints and data.securedContactPoints[1],
      data.contactPoints and data.contactPoints[1],
      data.authenticationMethods and data.authenticationMethods[1],
    }
    for _, candidate in ipairs(candidates) do
      if type(candidate) == "table" then
        return candidate
      end
    end
  end

  local deliveryMethod = response:match('"deliveryMethod"%s*:%s*"([^"]+)"')
  local maskedValue = response:match('"maskedContactPoint"%s*:%s*{%s*"value"%s*:%s*"([^"]+)"')
  if deliveryMethod or maskedValue then
    return {
      deliveryMethod = deliveryMethod or "TEXT",
      maskedContactPoint = {
        value = maskedValue or "",
        description = "Masked Phone Number",
      },
    }
  end

  return nil
end

function initiateMfaStepUp()
  local body = {
    processRules = {
      { name = "AuthenticationContext", value = "SGNONCHLNG" },
      { name = "U2F_ENABLED", value = "true" },
    },
    filterRules = {
      { value = "CONSUMER", name = "BRAND" },
      { value = "WEB", name = "CHANNEL" },
    },
  }
  local response = performLoginApiPost(CONSTANTS.loginStepUpUrl, body)
  local errorMessage = parseLoginApiError(response)
  if errorMessage then
    return nil, errorMessage
  end
  if not isLoginCompletionOk(response) then
    return nil, "initiateStepUp fehlgeschlagen."
  end

  local contactPoint = extractSecuredContactPoint(response)
  if not contactPoint then
    return nil, "Keine MFA-Kontaktmethode in initiateStepUp-Antwort gefunden."
  end

  return contactPoint
end

function sendMfaCode(contactPoint)
  local body = {
    securedContactPoint = contactPoint,
    processRules = buildMfaProcessRules(),
  }
  local response = performLoginApiPost(CONSTANTS.loginSendCodeUrl, body)
  local errorMessage = parseLoginApiError(response)
  if errorMessage then
    return nil, errorMessage
  end
  if not isLoginCompletionOk(response) then
    return nil, "sendCode fehlgeschlagen."
  end

  local masked = ""
  if type(contactPoint.maskedContactPoint) == "table" then
    masked = contactPoint.maskedContactPoint.value or ""
  end
  return masked
end

function validateMfaCode(code)
  if type(code) ~= "string" or code:match("^%s*$") then
    return nil, "Leerer MFA-Code."
  end

  local body = {
    authenticationCode = code:match("^%s*(.-)%s*$"),
    processRules = buildMfaProcessRules(),
  }
  local response = performLoginApiPost(CONSTANTS.loginValidateCodeUrl, body)
  local errorMessage = parseLoginApiError(response)
  if errorMessage then
    return nil, errorMessage
  end
  if not isLoginCompletionOk(response) then
    return nil, "validateCode fehlgeschlagen."
  end

  return true
end

function extractResponseHeader(respHeaders, headerName)
  if not respHeaders or not headerName then
    return nil
  end
  local lowerName = headerName:lower()
  if type(respHeaders) == "table" then
    for key, value in pairs(respHeaders) do
      if type(key) == "string" and key:lower() == lowerName and type(value) == "string" then
        return value
      end
    end
    for _, entry in ipairs(respHeaders) do
      if type(entry) == "table" and type(entry.name) == "string" and entry.name:lower() == lowerName then
        return entry.value
      end
    end
  elseif type(respHeaders) == "string" then
    for line in respHeaders:gmatch("[^\r\n]+") do
      local name, value = line:match("^([^:]+):%s*(.+)$")
      if name and name:lower() == lowerName then
        return value
      end
    end
  end
  return nil
end

function buildFormUrlEncoded(fields)
  local parts = {}
  for key, value in pairs(fields) do
    table.insert(parts, MM.urlencode(key) .. "=" .. MM.urlencode(tostring(value)))
  end
  return table.concat(parts, "&")
end

function zeroPadToBlockSize(data, blockSize)
  if type(data) ~= "string" then
    return nil
  end
  local remainder = #data % blockSize
  if remainder == 0 then
    return data
  end
  return data .. string.rep("\0", blockSize - remainder)
end

function canUseAcwCrypto()
  return type(MM.aes128encrypt) == "function" and type(MM.urlencode) == "function"
end

function acwAesEncrypt(plaintext, keyString)
  if type(plaintext) ~= "string" or type(keyString) ~= "string" or keyString == "" then
    return nil, "Ungültige ACW-Verschlüsselungsparameter."
  end
  if type(MM.aes128encrypt) ~= "function" then
    return nil, "MM.aes128encrypt nicht verfügbar."
  end

  local padded = zeroPadToBlockSize(plaintext, 16)
  if not padded then
    return nil, "ACW-Padding fehlgeschlagen."
  end

  local key = keyString
  local iv = ""
  local modes = { "aes128 ecb", "aes-128-ecb" }
  for _, mode in ipairs(modes) do
    local ok, cipher = pcall(MM.aes128encrypt, key, iv, padded, mode)
    if ok and type(cipher) == "string" and #cipher > 0 then
      local encoded = base64Encode(cipher)
      if encoded then
        return encoded
      end
    end
  end

  local ok, cipher = pcall(MM.aes128encrypt, key, iv, padded)
  if ok and type(cipher) == "string" and #cipher > 0 then
    local encoded = base64Encode(cipher)
    if encoded then
      return encoded
    end
  end

  return nil, "ACW-Verschlüsselung fehlgeschlagen."
end

function parseJsonpPayload(response)
  if type(response) ~= "string" or response == "" then
    return nil
  end
  local jsonPart = response:match("%((.+)%);?$")
  if not jsonPart then
    return nil
  end
  return parseJson(jsonPart)
end

function extractHiddenInputValue(html, fieldName)
  if type(html) ~= "string" or type(fieldName) ~= "string" then
    return nil
  end
  local patterns = {
    'name=["\']' .. fieldName .. '["\']%s+value=["\']([^"\']+)["\']',
    'value=["\']([^"\']+)["\']%s+name=["\']' .. fieldName .. '["\']',
  }
  for _, pattern in ipairs(patterns) do
    local value = html:match(pattern)
    if value and value ~= "" then
      return value
    end
  end
  return nil
end

function parseCsrfFromSignOnScreen(html)
  return extractHiddenInputValue(html, "csrfTokenHidden")
end

function parseAcwEncryptKey(html)
  if type(html) ~= "string" then
    return nil
  end
  return html:match('acwEncryptKey:%s*["\']([^"\']+)["\']')
    or html:match('acwEncryptKey%s*=%s*["\']([^"\']+)["\']')
end

function buildSignOnIbJson()
  return encodeJson({
    oidkeypress = false,
    oidpaste = true,
    pckeypress = false,
    pcpaste = true,
    userAgent = CONSTANTS.userAgent,
    pwMan = false,
  })
end

function buildSignOnFormBody(csrfToken, username, password)
  local fields = {
    csrfTokenHidden = csrfToken,
    lpOlbResetErrorCounter = "0",
    lpPasscodeErrorCounter = "0",
    contGsid = "",
    mouseCapturedEvents = "",
    onlineId = username,
    passcode = password,
    ["new-passcode"] = "",
    _ib = buildSignOnIbJson(),
    _u2support = "-1",
    webAuthAPI = "true",
  }

  return buildFormUrlEncoded(fields)
end

function buildJsonpCallback()
  local ts = tostring(os.time())
  return "jQuery" .. ts .. "000_" .. ts
end

function isSignOnCredentialError(location)
  if type(location) ~= "string" then
    return false
  end
  return location:match("InvalidCredentialsExceptionV2") ~= nil
    or location:match("msg=Invalid") ~= nil
end

function isSignOnCredentialErrorPage(response)
  if type(response) ~= "string" or response == "" then
    return false
  end
  return response:match("InvalidCredentialsExceptionV2") ~= nil
    or response:match("doesn't match our records") ~= nil
    or response:match("doesn?t match our records") ~= nil
    or response:match("The information you entered") ~= nil
    or response:match("Invalid User ID or Password") ~= nil
end

function isSignOnSuccessRedirect(location)
  if type(location) ~= "string" then
    return false
  end
  return location:match("signOnSuccessRedirect%.go") ~= nil
end

function isDirectAccountRedirect(location)
  if type(location) ~= "string" then
    return false
  end
  return location:match("myaccounts/signin/signIn%.go") ~= nil
    or location:match("myaccounts/details") ~= nil
end

function extractMaskedPhoneFromAuthCodeHtml(html)
  if type(html) ~= "string" then
    return nil
  end
  return html:match("XXX%-XXX%-(%d+)")
    or html:match("XXX%-XXX%-(%d%d%d%d)")
    or html:match("<b>%s*XXX%-XXX%-([^<]+)</b>")
end

function fetchSignOnCsrfToken()
  boaDebugLog("Login Schritt 1/2: CSRF von signOnV2Screen laden")
  local headers = buildRequestHeaders(nil)
  boaDebugLogRequest("GET", CONSTANTS.signOnScreenUrl, nil)
  local response, _, respHeaders = performRequest(
    "GET", CONSTANTS.signOnScreenUrl, nil, nil, headers, nil
  )
  boaDebugLogResponse("GET", CONSTANTS.signOnScreenUrl, response, respHeaders, "csrf-fetch")
  if not response or response == "" then
    boaDebugLog("CSRF-Fetch fehlgeschlagen: leere Antwort")
    return nil, "Login-Seite ohne Antwort."
  end
  local csrf = parseCsrfFromSignOnScreen(response)
  if not csrf then
    boaDebugLog("CSRF-Fetch fehlgeschlagen: Token nicht im HTML")
    return nil, "CSRF-Token auf der Login-Seite nicht gefunden."
  end
  boaDebugLog("CSRF ok, len=" .. tostring(#csrf))
  return csrf
end

function postSignOnCredentials(username, password, csrfToken)
  boaDebugLog("Login Schritt 2/2: signOnV2 POST")
  boaDebugLog(boaDebugSummarizeCredentials(username, password))
  local headers = buildRequestHeaders(CONSTANTS.signOnScreenUrl)
  headers["Content-Type"] = "application/x-www-form-urlencoded"
  headers["Origin"] = CONSTANTS.loginOrigin
  local body = buildSignOnFormBody(csrfToken, username, password)
  boaDebugLogRequest("POST", CONSTANTS.signOnPostUrl, body)
  local response, _, respHeaders = performRequest(
    "POST", CONSTANTS.signOnPostUrl, body, "application/x-www-form-urlencoded", headers, CONSTANTS.signOnScreenUrl
  )
  boaDebugLogResponse("POST", CONSTANTS.signOnPostUrl, response, respHeaders, "signOn-post")
  local location = extractResponseHeader(respHeaders, "Location")
  if isSignOnCredentialError(location) or isSignOnCredentialErrorPage(response) then
    local reason = "credential-error"
    if isSignOnCredentialError(location) then
      reason = reason .. "+location"
    end
    if isSignOnCredentialErrorPage(response) then
      reason = reason .. "+html"
    end
    boaDebugLog("Login abgelehnt: " .. reason)
    return nil, "Benutzername oder Passwort ungültig."
  end
  if isDirectAccountRedirect(location) then
    boaDebugLog("Login erfolgreich ohne MFA (direct account redirect)")
    if location then
      performGet(location, buildRequestHeaders(CONSTANTS.signOnScreenUrl), CONSTANTS.signOnScreenUrl)
    end
    return { directLogin = true }
  end
  if not isSignOnSuccessRedirect(location) then
    if isSignOnCredentialErrorPage(response) then
      boaDebugLog("Login abgelehnt: credential-error-page ohne Location-Header")
      return nil, "Benutzername oder Passwort ungültig."
    end
    boaDebugLog("Login fehlgeschlagen: unerwartete Antwort/Weiterleitung")
    return nil, "Login fehlgeschlagen (unerwartete Weiterleitung)."
  end

  boaDebugLog("Login Passwort ok, MFA folgt (signOnSuccessRedirect)")
  performGet(CONSTANTS.signOnSuccessUrl, buildRequestHeaders(CONSTANTS.signOnScreenUrl), CONSTANTS.signOnScreenUrl)
  return { directLogin = false }
end

function initializeAuthCodeWidget()
  boaDebugLog("MFA Schritt 1/4: authCodeInitialize")
  local referer = CONSTANTS.signOnSuccessUrl
  local headers = buildRequestHeaders(referer)
  boaDebugLogRequest("GET", CONSTANTS.authCodeInitUrl, nil)
  local initResponse = performGet(CONSTANTS.authCodeInitUrl, headers, referer)
  boaDebugLog("authCodeInitialize response.len=" .. tostring(boaDebugLen(initResponse)))
  if not initResponse or initResponse == "" then
    return nil, "Auth-Code-Widget konnte nicht initialisiert werden."
  end

  local encryptKey = parseAcwEncryptKey(initResponse)
  if not encryptKey then
    boaDebugLog("acwEncryptKey nicht in authCodeInitialize gefunden")
    return nil, "acwEncryptKey nicht gefunden."
  end
  boaDebugLog("acwEncryptKey ok, len=" .. tostring(#encryptKey))

  local callback = buildJsonpCallback()
  local displayUrl = CONSTANTS.authCodeDisplayUrl
    .. "?request_locale=en-us&callback=" .. MM.urlencode(callback)
    .. "&_=" .. tostring(os.time())
  local ajaxHeaders = buildAjaxPostHeaders(referer)
  ajaxHeaders["Accept"] = "application/javascript, */*;q=0.1"
  boaDebugLogRequest("GET", displayUrl, nil)
  local displayResponse = performGet(displayUrl, ajaxHeaders, referer)
  boaDebugLog("authcodeDisplay response.len=" .. tostring(boaDebugLen(displayResponse)))
  if not displayResponse or displayResponse == "" then
    return nil, "Auth-Code-Anzeige fehlgeschlagen."
  end

  return {
    encryptKey = encryptKey,
    callback = callback,
  }
end

function sendAuthCodeRequest(authState)
  if not authState or not authState.encryptKey then
    return nil, "Auth-Code-Status unvollständig."
  end

  boaDebugLog("MFA Schritt 2/4: sendAuthCode (SMS anfordern)")
  local requestPlaintext = "selectedContact|0|contactType|text"
  local requestToken, encryptError = acwAesEncrypt(requestPlaintext, authState.encryptKey)
  if not requestToken then
    boaDebugLog("sendAuthCode Verschlüsselung fehlgeschlagen: " .. tostring(encryptError))
    return nil, encryptError or "Auth-Code-Anforderung konnte nicht verschlüsselt werden."
  end
  boaDebugLog("acw_request_token erzeugt, len=" .. tostring(#requestToken))

  local callback = authState.callback or buildJsonpCallback()
  local url = CONSTANTS.sendAuthCodeUrl
    .. "?callback=" .. MM.urlencode(callback)
    .. "&acw_request_token=" .. MM.urlencode(requestToken)
    .. "&action=processACWRequest"
    .. "&_=" .. tostring(os.time())
  local referer = CONSTANTS.signOnSuccessUrl
  local ajaxHeaders = buildAjaxPostHeaders(referer)
  ajaxHeaders["Accept"] = "application/javascript, */*;q=0.1"
  boaDebugLogRequest("GET", url, nil)
  local response = performGet(url, ajaxHeaders, referer)
  boaDebugLog("sendAuthCode response.len=" .. tostring(boaDebugLen(response)))
  if not response or response == "" then
    return nil, "SMS-Code konnte nicht angefordert werden."
  end

  local payload = parseJsonpPayload(response)
  local htmlSource = payload and payload.htmlSource or response
  local masked = extractMaskedPhoneFromAuthCodeHtml(htmlSource)
  if masked and masked ~= "" then
    boaDebugLog("SMS gesendet an XXX-XXX-" .. masked)
    return "XXX-XXX-" .. masked
  end
  boaDebugLog("sendAuthCode ok, Telefonnummer nicht im Response erkannt")
  return "Ihr registriertes Gerät"
end

function validateAuthCodeAndFinish(code, authState)
  if not authState or not authState.encryptKey then
    return nil, "Auth-Code-Status unvollständig."
  end
  if type(code) ~= "string" or code:match("^%s*$") then
    return nil, "Leerer MFA-Code."
  end
  code = code:match("^%s*(.-)%s*$")

  boaDebugLog("MFA Schritt 3/4: validateAuthCode, code.len=" .. tostring(#code))
  local enterToken, encryptError = acwAesEncrypt(code, authState.encryptKey)
  if not enterToken then
    boaDebugLog("validateAuthCode Verschlüsselung fehlgeschlagen: " .. tostring(encryptError))
    return nil, encryptError or "MFA-Code konnte nicht verschlüsselt werden."
  end
  boaDebugLog("acw_enter_token erzeugt, len=" .. tostring(#enterToken))

  local callback = authState.callback or buildJsonpCallback()
  local url = CONSTANTS.validateAuthCodeUrl
    .. "?callback=" .. MM.urlencode(callback)
    .. "&acw_enter_token=" .. MM.urlencode(enterToken)
    .. "&action=processACWEnter"
    .. "&_=" .. tostring(os.time())
  local referer = CONSTANTS.signOnSuccessUrl
  local ajaxHeaders = buildAjaxPostHeaders(referer)
  ajaxHeaders["Accept"] = "application/javascript, */*;q=0.1"
  boaDebugLogRequest("GET", url, nil)
  local response = performGet(url, ajaxHeaders, referer)
  boaDebugLog("validateAuthCode response.len=" .. tostring(boaDebugLen(response)))
  if not response or response == "" then
    return nil, "MFA-Validierung ohne Antwort."
  end

  local payload = parseJsonpPayload(response)
  local htmlSource = payload and payload.htmlSource or response
  local csrfToken = extractHiddenInputValue(htmlSource, "csrfTokenHidden")
  local validationToken = extractHiddenInputValue(htmlSource, "validationToken")
  if not csrfToken or not validationToken then
    if response:match("error") or response:match("Error") then
      boaDebugLog("validateAuthCode: Server meldet Fehler im JSONP-Response")
      return nil, "Ungültiger Authentifizierungscode."
    end
    boaDebugLog("validateAuthCode: csrf/validationToken fehlen im Response")
    return nil, "Validierungstoken nach MFA nicht gefunden."
  end
  boaDebugLog("validateAuthCode ok, validationToken.len=" .. tostring(#validationToken))

  boaDebugLog("MFA Schritt 4/4: validateChallengeAnswerV2 POST")
  local headers = buildRequestHeaders(referer)
  headers["Content-Type"] = "application/x-www-form-urlencoded"
  headers["Origin"] = CONSTANTS.loginOrigin
  local body = buildFormUrlEncoded({
    csrfTokenHidden = csrfToken,
    validationToken = validationToken,
  })
  boaDebugLogRequest("POST", CONSTANTS.validateChallengeUrl, body)
  local challengeResponse, _, respHeaders = performRequest(
    "POST", CONSTANTS.validateChallengeUrl, body, "application/x-www-form-urlencoded", headers, referer
  )
  boaDebugLogResponse("POST", CONSTANTS.validateChallengeUrl, challengeResponse, respHeaders, "mfa-finish")
  local location = extractResponseHeader(respHeaders, "Location")
  if location then
    performGet(location, buildRequestHeaders(referer), referer)
  else
    performGet(CONSTANTS.loginSignInGoUrl, buildRequestHeaders(referer), referer)
  end

  if not verifyActiveSession() then
    boaDebugLog("Session nach MFA nicht verifiziert")
    return nil, "Login abgeschlossen, aber Session nicht verifiziert."
  end
  boaDebugLog("Login + MFA erfolgreich, Session verifiziert")
  return true
end

function performSignOnV2Login(username, password)
  boaDebugLog("=== signOnV2 Login start ===")
  boaDebugLog("APIs: urlencode=" .. tostring(type(MM.urlencode) == "function")
    .. ", aes128encrypt=" .. tostring(type(MM.aes128encrypt) == "function")
    .. ", base64Encode=" .. tostring(type(MM.base64Encode) == "function" or type(MM.base64encode) == "function"))
  if type(MM.urlencode) ~= "function" then
    return "MM.urlencode nicht verfügbar."
  end

  local csrfToken, csrfError = fetchSignOnCsrfToken()
  if not csrfToken then
    boaDebugLog("Abbruch: " .. tostring(csrfError))
    return csrfError or "CSRF-Token konnte nicht geladen werden."
  end

  local signOnResult, signOnError = postSignOnCredentials(username, password, csrfToken)
  if not signOnResult then
    boaDebugLog("Abbruch: " .. tostring(signOnError))
    return signOnError or "Anmeldung fehlgeschlagen."
  end

  if signOnResult.directLogin then
    if verifyActiveSession() then
      boaDebugLog("=== Login ohne MFA abgeschlossen ===")
      return nil
    end
    boaDebugLog("Direct login ohne verifizierte Session")
    return "Login ohne MFA, aber Session nicht verifiziert."
  end

  if not canUseAcwCrypto() then
    boaDebugLog("MFA blockiert: MM.aes128encrypt fehlt")
    return "Bank of America MFA benötigt MM.aes128encrypt.\n\nCookie-Import: COOKIE:SMSESSION=...;SSOTOKEN=..."
  end

  local authState, authError = initializeAuthCodeWidget()
  if not authState then
    boaDebugLog("Abbruch MFA-Init: " .. tostring(authError))
    return authError or "MFA-Widget konnte nicht geladen werden."
  end

  session.loginFlow = "signOnV2"
  session.authCodeState = authState

  local maskedContact, sendError = sendAuthCodeRequest(authState)
  if not maskedContact and sendError then
    boaDebugLog("Abbruch sendAuthCode: " .. tostring(sendError))
    return sendError
  end

  session.awaitingMfaCode = true
  session.mfaMaskedContact = maskedContact or "Ihr registriertes Gerät"
  boaDebugLog("=== MFA-Code angefordert, warte auf Eingabe ===")
  return {
    id = 2,
    title = "Bank of America",
    challenge = "Bitte den Authentifizierungscode eingeben"
      .. (session.mfaMaskedContact ~= "" and (" (" .. session.mfaMaskedContact .. ").") or "."),
    label = "Authentication Code",
  }
end

function submitSignOnV2Mfa(code)
  boaDebugLog("=== MFA-Schritt (Benutzereingabe) ===")
  boaDebugLog("mfaCode.len=" .. tostring(boaDebugLen(code)))
  local validated, validateError = validateAuthCodeAndFinish(code, session.authCodeState)
  if not validated then
    boaDebugLog("MFA fehlgeschlagen: " .. tostring(validateError))
    return {
      id = 2,
      title = "Bank of America",
      challenge = validateError or "Ungültiger Code. Bitte erneut eingeben.",
      label = "Authentication Code",
    }
  end

  session.awaitingMfaCode = false
  session.authCodeState = nil
  session.loginFlow = nil
  session.mfaMaskedContact = nil
  boaDebugLog("=== Login komplett ===")
  return nil
end

function completeLoginNavigation()
  local headers = buildRequestHeaders(CONSTANTS.loginReferer)
  local response = performGet(CONSTANTS.loginSignInGoUrl, headers, CONSTANTS.loginReferer)
  refreshSessionCookies()
  if not response then
    return nil, "signIn.go ohne Antwort."
  end
  return true
end

function isAuthenticatedAccountPage(response)
  if not response then
    return false
  end

  local hasAccountData = response:match("Ending in")
    or response:match("ending in")
    or response:match("account%-details")
    or response:match("Account Overview")
    or response:match("balance")

  local isLoginPage = response:match("Sign In")
    or response:match("Sign in")
    or response:match("Log In")
    or response:match("Log in")
    or response:match("Enter your user ID")
    or response:match("Bank of America %- Banking, Credit Cards")
    or response:match("choose the card that works for you")

  return hasAccountData and not isLoginPage
end

function verifyActiveSession()
  if not session.cookies or session.cookies == "" then
    session.cookies = connection and connection:getCookies() or session.cookies
  end
  if not session.cookies or session.cookies == "" then
    return false
  end

  local testHeaders = buildRequestHeaders(nil)
  local testResponse = performGet(
    CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go",
    testHeaders,
    CONSTANTS.baseUrl .. "/"
  )

  if isAuthenticatedAccountPage(testResponse) then
    rememberStatementPageUrl(testResponse, session.adxToken)
    updateAdxFromResponse(testResponse, session.adxToken)
    return true
  end

  return false
end

function restoreLoginConnection(accountKey)
  local storage = rawget(_G, "LocalStorage")
  local canReuse = storage and storage.connection and storage.connectionAccountKey == accountKey
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
  connection.useragent = CONSTANTS.userAgent
  session.cookies = connection:getCookies() or session.cookies
end

function directLoginUnavailableMessage()
  return "Direct-Login (User ID + Passwort) ist in Lua ohne Browser-Runtime nicht möglich.\n\n"
    .. "BoA verlangt Anti-Fraud-Daten vom JavaScript der Loginseite "
    .. "(BioCatch _ia, ThreatMetrix f_variable/pm_fp, Script-Hashes _sc) — "
    .. "nicht nachbaubar per reinem HTTP.\n\n"
    .. "Cookie-Import (empfohlen):\n"
    .. "1. Im Browser bei secure.bankofamerica.com einloggen (inkl. MFA)\n"
    .. "2. Cookies exportieren (HAR oder DevTools)\n"
    .. "3. MoneyMoney Passwort: COOKIE:SMSESSION=...;SSOTOKEN=...\n\n"
    .. "HAR: python3 scripts/extract-boa-cookies.py login.har\n\n"
    .. "Für Direct-Login fehlt die Engine-API WebbankingBrowser.\n"
    .. "Details: docs/ENGINE-API-GAPS.md"
end

function performPasswordLogin(username, password)
  boaDebugLog("Direct-Login blockiert: Browser-Fingerprint erforderlich")
  return directLoginUnavailableMessage()
end

function performSpartaPasswordLogin(username, password)
  if not canUseRsaLogin() then
    return "Bank of America benötigt MM.rsaEncrypt für den Sparta-Login.\n\nCookie-Import: COOKIE:SMSESSION=...;SSOTOKEN=..."
  end

  local sessionKey, keyError = fetchLoginSessionKey()
  if not sessionKey then
    return keyError or "Public Key konnte nicht geladen werden."
  end

  local onlineIdCipher, onlineError = submitOnlineId(sessionKey, username)
  if not onlineIdCipher then
    return onlineError or "Benutzername-Schritt fehlgeschlagen."
  end

  session.loginSessionKey = sessionKey
  session.onlineIdCipher = onlineIdCipher

  local verified, verifyError = verifyCredentials(sessionKey, username, password, onlineIdCipher)
  if not verified then
    return verifyError or "Passwort-Verifikation fehlgeschlagen."
  end

  local contactPoint, stepUpError = initiateMfaStepUp()
  if not contactPoint then
    return stepUpError or "MFA-Initialisierung fehlgeschlagen."
  end

  session.mfaContactPoint = contactPoint
  local maskedContact, sendError = sendMfaCode(contactPoint)
  if not maskedContact and sendError then
    return sendError
  end

  session.awaitingMfaCode = true
  session.mfaMaskedContact = maskedContact or "Ihr registriertes Gerät"
  return {
    id = 2,
    title = "Bank of America",
    challenge = "Bitte den Authentifizierungscode eingeben"
      .. (session.mfaMaskedContact ~= "" and (" (" .. session.mfaMaskedContact .. ").") or "."),
    label = "Authentication Code",
  }
end

function submitMfaLoginStep(code)
  if session.loginFlow == "signOnV2" then
    return submitSignOnV2Mfa(code)
  end

  local validated, validateError = validateMfaCode(code)
  if not validated then
    return {
      id = 2,
      title = "Bank of America",
      challenge = validateError or "Ungültiger Code. Bitte erneut eingeben.",
      label = "Authentication Code",
    }
  end

  local completed, navError = completeLoginNavigation()
  if not completed then
    return navError or "Login-Abschluss fehlgeschlagen."
  end

  if not verifyActiveSession() then
    return "Login abgeschlossen, aber Session nicht verifiziert. Bitte erneut versuchen."
  end

  session.awaitingMfaCode = false
  session.mfaContactPoint = nil
  session.onlineIdCipher = nil
  session.loginSessionKey = nil
  return nil
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Bank of America"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local username = credentials and credentials[1] or ""
  local password = credentials and credentials[2] or ""
  local accountKey = username or ""

  boaDebugLog("InitializeSession2 step=" .. tostring(step) .. ", " .. boaDebugSummarizeCredentials(username, password))

  restoreLoginConnection(accountKey)

  if password and password:match("^COOKIE:") then
    boaDebugLog("Modus: Cookie-Import")
    return loginWithImportedCookies(password:sub(8))
  end

  if step == 1 then
    if verifyActiveSession() then
      boaDebugLog("Bestehende Session noch gültig, Login übersprungen")
      return nil
    end

    if username == "" or password == "" then
      boaDebugLog("Abbruch: Credentials leer")
      return "Cookie-Import erforderlich: Passwort = COOKIE:SMSESSION=...;SSOTOKEN=...\n\n"
        .. directLoginUnavailableMessage()
    end

    return performPasswordLogin(username, password)
  end

  if session.awaitingMfaCode then
    boaDebugLog("InitializeSession2 MFA step")
    return submitMfaLoginStep(credentials and credentials[1] or "")
  end

  boaDebugLog("InitializeSession2: LoginFailed (kein MFA pending)")
  return LoginFailed
end

function loginWithImportedCookies(cookieString)
  local formattedCookies = cookieString:gsub("^%s*(.-)%s*$", "%1")

  if formattedCookies:match(",") and not formattedCookies:match(";") then
    formattedCookies = formattedCookies:gsub("%s*,%s*", "; ")
  end

  if not formattedCookies:match("=") then
    return "Invalid cookie format. Use: name=value;name2=value2"
  end

  local hasSMSession = formattedCookies:match("SMSESSION=[^;]+")

  if not hasSMSession then
    return "ERROR: SMSESSION cookie not found!\n\n" ..
           "This is the MAIN session cookie and is REQUIRED.\n" ..
           "Please copy ALL cookies from browser (including SMSESSION).\n" ..
           "Make sure you are logged in to www.bankofamerica.com first."
  end

  session.cookies = formattedCookies

  local testHeaders = buildRequestHeaders(nil)
  local testResponse = performGet(
    CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go",
    testHeaders,
    CONSTANTS.baseUrl .. "/"
  )

  if testResponse then
    local hasAccountData = testResponse:match("Ending in") or
                          testResponse:match("ending in") or
                          testResponse:match("account%-details") or
                          testResponse:match("Account Overview") or
                          testResponse:match("balance")

    local isLoginPage = testResponse:match("Sign In") or
                       testResponse:match("Sign in") or
                       testResponse:match("Log In") or
                       testResponse:match("Log in") or
                       testResponse:match("Enter your user ID") or
                       testResponse:match("Bank of America %- Banking, Credit Cards") or
                       testResponse:match("choose the card that works for you")

    if hasAccountData and not isLoginPage then
      rememberStatementPageUrl(testResponse, session.adxToken)
      updateAdxFromResponse(testResponse, session.adxToken)
      return nil
    end

    if isLoginPage then
      return "SESSION EXPIRED OR INVALID - redirected to login/marketing page.\n\n" ..
             "Your cookies have expired or are incomplete.\n\n" ..
             "TO FIX:\n" ..
             "1. Open browser and go to www.bankofamerica.com\n" ..
             "2. Login with your credentials\n" ..
             "3. After successful login, open DevTools (F12/Cmd+Opt+I)\n" ..
             "4. Go to Application/Storage -> Cookies\n" ..
             "5. Select 'secure.bankofamerica.com'\n" ..
             "6. Copy ALL cookies with their values\n" ..
             "7. Paste into MoneyMoney password field as: COOKIE:SMSESSION=...;SSOTOKEN=...\n\n" ..
             "CRITICAL: Copy cookies immediately after login - they expire quickly!"
    end
  end

  return nil
end

function ListAccounts(knownAccounts)
  if not session.cookies or session.cookies == "" then
    return "No active session. Please use Cookie Import Mode."
  end


  local accounts = {}

  local requestHeaders = buildRequestHeaders(CONSTANTS.baseUrl .. "/")
  local response = performGet(
    CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go",
    requestHeaders,
    CONSTANTS.baseUrl .. "/"
  )

  if not response then
    return "Failed to fetch accounts (no response from server). Cookies may be expired - please re-import fresh cookies."
  end

  rememberStatementPageUrl(response, session.adxToken)
  updateAdxFromResponse(response, session.adxToken)

  if response:match("Sign In") or response:match("Enter your user ID") or
     response:match("Bank of America %- Banking, Credit Cards") then
    return "SESSION EXPIRED - Cookies no longer valid.\n\n" ..
           "Please copy FRESH cookies from your browser:\n" ..
           "1. Login to www.bankofamerica.com\n" ..
           "2. Open DevTools -> Application -> Cookies\n" ..
           "3. Copy all cookies for secure.bankofamerica.com\n" ..
           "4. Update the COOKIE: string in MoneyMoney"
  end

  for accountSection in response:gmatch('TL_NPI_AcctName[^>]*>([\0-\255]-)</span>') do
    local accountName = accountSection:gsub("^%s*", ""):gsub("%s*$", "")
    local maskedNum = accountName:match("%-%s*(%d%d%d%d)%s*$") or accountName:match("(%d%d%d%d)%s*$")
    
    if not maskedNum then
      maskedNum = accountSection:match("%*%*(%d%d%d%d)") or accountSection:match("ending in%s+(%d%d%d%d)")
    end

    if maskedNum then
      local displayName = accountName or ("BoA Account *" .. maskedNum)
      displayName = displayName:gsub("^%s*", ""):gsub("%s*$", "")

      local accountType = AccountTypeGiro
      if displayName:lower():find("card") or displayName:lower():find("credit") or response:find("/card/") then
        accountType = AccountTypeCreditCard
      end

      local alreadyExists = false
      for _, acc in ipairs(accounts) do
        if acc.accountNumber == maskedNum then
          alreadyExists = true
          break
        end
      end

      if not alreadyExists then
        table.insert(accounts, {
          name = displayName,
          accountNumber = maskedNum,
          bankCode = CONSTANTS.bankCode,
          currency = "USD",
          type = accountType,
          attributes = { "statements" }
        })
      end
    end
  end
  
  if #accounts == 0 then
    for num in response:gmatch("Ending in%s+(%d%d%d%d)") do
      local maskedNum = num
      local displayName = "BoA Account *" .. maskedNum
      
      local alreadyExists = false
      for _, acc in ipairs(accounts) do if acc.accountNumber == maskedNum then alreadyExists = true; break end end
      
      if not alreadyExists then
        table.insert(accounts, {
          name = displayName,
          accountNumber = maskedNum,
          bankCode = CONSTANTS.bankCode,
          currency = "USD",
          type = AccountTypeGiro,
          attributes = { "statements" }
        })
      end
    end
  end
  
  -- Final fallback if still no accounts found
  if #accounts == 0 then
    table.insert(accounts, {
      name = "BoA Account (needs manual setup)",
      accountNumber = "0000",
      bankCode = CONSTANTS.bankCode,
      currency = "USD",
      type = AccountTypeGiro,
      attributes = { "statements" }
    })
  end

  return accounts
end

local function stripHtmlTags(fragment)
  return fragment:gsub("<[^>]+>", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeTransactionDetailUrl(urlMatch)
  local url = urlMatch:gsub("&amp;", "&")
  if url:sub(1, 1) == "/" then
    url = CONSTANTS.baseUrl .. url
  elseif not url:find("^http") then
    url = CONSTANTS.baseUrl .. "/" .. url
  end
  return url
end

local function extractTransactionDetailUrl(row)
  local urlMatch = row:match('rel="([^"]*transaction%-details%.go[^"]*)"')
  if urlMatch then
    return normalizeTransactionDetailUrl(urlMatch)
  end
  return nil
end

local function parseTransactionDetailsHtml(html)
  if not html or html == "" then
    return nil
  end

  local details = {}
  local tableHtml = html:match('class="trans%-expanded%-details"[^>]*>([\0-\255]-)</table>') or html

  for row in tableHtml:gmatch("<tr[^>]*>([\0-\255]-)</tr>") do
    if row:find("first-expanded-cell", 1, true) and row:find("second-expanded-cell", 1, true) then
      local label = row:match("first%-expanded%-cell[^>]*>([\0-\255]-)</t[dh]>")
      local value = row:match("second%-expanded%-cell[^>]*>([\0-\255]-)</t[dh]>")
      if label and value then
        label = stripHtmlTags(label):gsub(":$", "")
        value = stripHtmlTags(value)
        if label ~= "" and value ~= "" then
          details[label] = value
        end
      end
    end
  end

  local merchant = html:match('class="lblMerchantNameVal">([^<]+)<')
  if merchant and merchant ~= "" then
    details["Merchant Name"] = merchant:gsub("^%s+", ""):gsub("%s+$", "")
  end

  local category = html:match('class="lblCategoryName">([^<]+)<')
  if category and category ~= "" then
    details["Transaction Category"] = category:gsub("^%s+", ""):gsub("%s+$", "")
  end

  if next(details) == nil then
    return nil
  end
  return details
end

local function applyTransactionDetails(trans, details)
  local merchant = details["Merchant Name"]
  if merchant and merchant ~= "" then
    trans.name = merchant
  end

  local transType = details["Transaction type"]
  if transType and transType ~= "" then
    trans.bookingText = transType
  end

  local refNum = details["Reference number"]
  if refNum and refNum ~= "" then
    trans.endToEndReference = refNum
  end

  local purposeLines = {}
  if merchant and merchant ~= "" then
    table.insert(purposeLines, merchant)
  elseif trans.purpose and trans.purpose ~= "" then
    table.insert(purposeLines, trans.purpose)
  end

  if details["Transaction Category"] then
    table.insert(purposeLines, "Category: " .. details["Transaction Category"])
  end
  if details["Card type"] then
    table.insert(purposeLines, "Card: " .. details["Card type"])
  end
  if details["Online Purchase"] then
    table.insert(purposeLines, "Online purchase: " .. details["Online Purchase"])
  end
  if refNum and refNum ~= "" then
    table.insert(purposeLines, "Reference: " .. refNum)
  end

  if #purposeLines > 0 then
    trans.purpose = table.concat(purposeLines, "\n")
  end
end

local function enrichTransactionsWithDetails(transactions, requestHeaders, refererUrl)
  if not refererUrl or refererUrl == "" then
    return
  end

  local detailHeaders = buildAjaxPostHeaders(refererUrl)
  for _, trans in ipairs(transactions) do
    local detailUrl = trans._detailUrl
    trans._detailUrl = nil
    if detailUrl then
      local detailHtml = performPost(detailUrl, "", nil, detailHeaders, refererUrl)
      if detailHtml and detailHtml ~= "" then
        local details = parseTransactionDetailsHtml(detailHtml)
        if details then
          applyTransactionDetails(trans, details)
        end
      end
    end
  end
end

local function parseTransactionRow(row, sinceTimestamp)
  local rowLower = row:lower()

  local isHeaderRow = rowLower:find('<th') or rowLower:find('trans%-thead%-wrap') or rowLower:find('icon%-legend%-head')
  local isBalanceRow = rowLower:find('beginning%-balance%-row') or rowLower:find('beginning%-balance%-msg')
  local isNoTransRow = rowLower:find('no%-trans%-from%-filt')
  if isHeaderRow or isBalanceRow or isNoTransRow then
    return nil
  end

  local hasTransDesc = rowLower:find('trans%-desc') or row:find('TL_NPI_TransDesc') or rowLower:find('fmt%-txn%-desc')
  local hasTransAmount = rowLower:find('trans%-amount') or row:find('TL_NPI_Amt') or rowLower:find('ta%-rt')
  local hasIconType = rowLower:find('icon%-type%-')
  local hasDateCell = rowLower:find('trans%-date%-cell') or rowLower:find('date%-td')
  if not hasTransDesc and not hasTransAmount and not hasIconType and not hasDateCell then
    return nil
  end

  local dateStr = nil
  local mm, dd, yyyy = row:match('[Tt]ransaction [Dd]ate:%s*(%d%d)/(%d%d)/(%d%d%d%d)')
  if mm and dd and yyyy then
    dateStr = mm .. '/' .. dd .. '/' .. yyyy
  end
  if not dateStr then
    mm, dd, yyyy = row:match('>(%d%d)/(%d%d)/(%d%d%d%d)<')
    if mm and dd and yyyy then
      dateStr = mm .. '/' .. dd .. '/' .. yyyy
    end
  end
  if not dateStr then
    local dateStart = rowLower:find('trans%-date%-cell') or rowLower:find('date%-td')
    if dateStart then
      local dateCellEnd = rowLower:find('</td>', dateStart) or #row
      local dateCell = row:sub(dateStart, dateCellEnd)
      mm, dd, yyyy = dateCell:match('(%d%d)/(%d%d)/(%d%d%d%d)')
      if mm and dd and yyyy then
        dateStr = mm .. '/' .. dd .. '/' .. yyyy
      elseif dateCell:lower():match('pending') then
        dateStr = 'Pending'
      end
    end
  end

  local desc = row:match('alt="Expand transaction for Transaction date: %d%d/%d%d/%d%d%d%d%s+([^"]+)"')
  if desc then
    desc = desc:gsub("^%s*", ""):gsub("%s*$", "")
  end

  if not desc or desc == "" then
    desc = row:match('expand%-trans%-from%-desc[^>]*>.-%</span>%s*([^<]+)<')
    if desc then
      desc = desc:gsub("^%s*", ""):gsub("%s*$", "")
    end
  end

  if not desc or desc == "" then
    local descStart = rowLower:find('trans%-desc%-cell') or row:find('TL_NPI_TransDesc') or rowLower:find('fmt%-txn%-desc')
    if descStart then
      local descSection = row:sub(descStart, descStart + 1000)
      for text in descSection:gmatch('>([^<]+)<') do
        local trimmed = text:gsub("^%s*", ""):gsub("%s*$", "")
        trimmed = trimmed:gsub("Expand transaction for Transaction date: %d%d/%d%d/%d%d%d%d%s*", "")
        if trimmed ~= "" and not trimmed:find("Expand transaction") and not trimmed:find("Type Temporary Transactions") and not trimmed:find("Type&nbsp;") then
          desc = trimmed
          break
        end
      end
    end
  end

  local amountStr = nil
  local amtStart = rowLower:find('trans%-amount%-cell') or row:find('TL_NPI_Amt') or rowLower:find('ta%-rt')
  if amtStart then
    local amountSection = row:sub(amtStart, amtStart + 200)
    amountStr = amountSection:match('>%s*([%-+%$]?%$?[%d%.,]+)%s*<') or
                amountSection:match('>%s*(%-%$[%d%.,]+)%s*<') or
                amountSection:match('>%s*(%$[%d%.,]+)%s*<')
  end

  if not desc or desc == "" or not amountStr then
    return nil
  end

  desc = desc:gsub("^%s*", ""):gsub("%s*$", "")

  local amount = 0
  local isNegativeInHtml = amountStr:match("^%s*%-") or amountStr:match("%-%$")
  local cleanAmountStr = amountStr:gsub("%$", ""):gsub(",", "")
  amount = tonumber((cleanAmountStr)) or 0

  local bookingDate = os.time()
  local valutaDate = os.time()

  if dateStr then
    dateStr = dateStr:gsub("^%s*", ""):gsub("%s*$", "")
    if dateStr == "Pending" or dateStr:lower():match('pending') then
      local now = os.date("*t")
      bookingDate = os.time({year = now.year, month = now.month, day = now.day, hour = 0, min = 0, sec = 0})
      valutaDate = bookingDate
    else
      mm, dd, yyyy = dateStr:match("(%d%d)/(%d%d)/(%d%d%d%d)")
      if mm and dd and yyyy then
        bookingDate = os.time({year = tonumber(yyyy), month = tonumber(mm), day = tonumber(dd)})
        valutaDate = bookingDate
      end
    end
  end

  local transType = nil
  local relStart = rowLower:find('rel="', rowLower:find('icon%-type'))
  if relStart then
    local typeStart = relStart + 5
    local typeEnd = row:find('"', typeStart)
    if typeEnd then
      transType = row:sub(typeStart, typeEnd - 1)
    end
  end
  if not transType or transType == "" then
    transType = row:match('icon%-type%-([%w%-]+)')
  end

  local isPurchase = (transType == "CH" or transType == "CR" or transType == "DC" or
                    transType == "TT" or transType == "FE" or transType == "WD" or
                    transType == "P" or transType == "Purchase" or transType == "purchase" or
                    transType == "generic-debit" or transType == "withdrawal" or transType == "bank-charge" or
                    transType == "purchase")
  local isPayment = (transType == "PY" or transType == "PM" or transType == "RC" or
                   transType == "OP" or transType == "Payment" or transType == "payment" or
                   transType == "generic-credit" or transType == "deposit-recur" or transType == "payment-recur" or
                   transType == "payment")

  if isPurchase and amount > 0 then
    amount = -amount
  elseif isPayment and amount < 0 then
    amount = math.abs(amount)
  elseif isNegativeInHtml then
    amount = math.abs(amount)
  else
    amount = -math.abs(amount)
  end

  if sinceTimestamp and bookingDate < sinceTimestamp then
    if dateStr ~= "Pending" and not dateStr:lower():match('pending') then
      return nil
    end
  end

  local detailUrl = extractTransactionDetailUrl(row)

  return {
    bookingDate = bookingDate,
    valutaDate = valutaDate,
    purpose = desc,
    amount = amount,
    currency = "USD",
    _detailUrl = detailUrl
  }
end

function parseTransactionsFromPage(response, sinceTimestamp, requestHeaders, refererUrl)
  local transactions = {}
  local seen = {}

  local function addTransactionFromRow(row)
    local trans = parseTransactionRow(row, sinceTimestamp)
    if trans then
      local key = trans.bookingDate .. "|" .. trans.purpose .. "|" .. tostring(trans.amount)
      if not seen[key] then
        seen[key] = true
        table.insert(transactions, trans)
      end
    end
  end

  local tbodyStart = response:lower():find('<tbody class="trans%-tbody%-wrap"')
  if tbodyStart then
    local tbodyEnd = response:lower():find("</tbody>", tbodyStart)
    if tbodyEnd then
      local tbody = response:sub(tbodyStart, tbodyEnd + 8)
      local searchPos = 1
      while true do
        local trStart, trStartEnd = tbody:lower():find("<tr[^>]*>", searchPos)
        if not trStart then
          break
        end
        local trEnd = tbody:lower():find("</tr>", trStartEnd + 1)
        if not trEnd then
          break
        end
        addTransactionFromRow(tbody:sub(trStart, trEnd + 5))
        searchPos = trEnd + 5
      end
    end
  end

  if #transactions == 0 then
    local pos = 1
    while true do
      local markerPos = response:lower():find("trans%-first%-row", pos)
      if not markerPos then
        break
      end

      local trStart = response:lower():find("<tr", math.max(1, markerPos - 400))
      if not trStart then
        pos = markerPos + 1
      else
        local trEnd = response:lower():find("</tr>", markerPos)
        if not trEnd then
          break
        end
        addTransactionFromRow(response:sub(trStart, trEnd + 5))
        pos = trEnd + 5
      end
    end
  end


  if requestHeaders and refererUrl and #transactions > 0 then
    enrichTransactionsWithDetails(transactions, requestHeaders, refererUrl)
  end

  return transactions
end

function RefreshAccount(account, since)
  if not account or not account.accountNumber then
    return { balance = 0, transactions = {} }
  end

  if not session.cookies or session.cookies == "" then
    return { balance = 0, transactions = {} }
  end

  local sinceTimestamp = since

  local allTransactions = {}
  local seenTransactions = {}
  local maxPages = 24
  local currentUrl = CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go"
  local refererUrl = CONSTANTS.baseUrl .. "/myaccounts/accounts-overview/topNav.go"
  local requestHeaders = buildRequestHeaders(refererUrl)

  warmupActivitySession(requestHeaders, CONSTANTS.baseUrl .. "/")

  local firstPageResponse = performGet(
    currentUrl .. "?filter=0&sort=0&order=0",
    requestHeaders,
    refererUrl
  )
  
  if not firstPageResponse then
    return { balance = 0, transactions = {} }
  end

  rememberStatementPageUrl(firstPageResponse, session.adxToken)

  local balance = 0
  local balStr = firstPageResponse:match('[Ss]tatement [Bb]alance:.-TL_NPI_L1">%$?([%d%.,]+)') or
                 firstPageResponse:match('[Cc]urrent [Bb]alance:.-TL_NPI_L1">%$?([%d%.,]+)') or
                 firstPageResponse:match('[Tt]otal [Cc]redit [Aa]vailable:.-TL_NPI_L1">%$?([%d%.,]+)')
  
  if balStr then
    balance = tonumber((balStr:gsub(",", ""))) or 0
    if account.type == AccountTypeCreditCard and firstPageResponse:lower():find("statement balance") then
      balance = -balance
    end
  end

  local adxToken = firstPageResponse:match('adx=["\']?([0-9a-f]+)') or 
                   firstPageResponse:match('["\']adx["\']%s*[:=]%s*["\']?([0-9a-f]+)')
  if adxToken then
    session.adxToken = adxToken
  end

  refererUrl = currentUrl .. "?filter=0&sort=0&order=0"

  loadActivityTransactionsChain(
    firstPageResponse,
    adxToken,
    sinceTimestamp,
    seenTransactions,
    allTransactions,
    requestHeaders,
    refererUrl,
    maxPages
  )

  return { balance = balance, transactions = allTransactions }
end

function EndSession()
  -- Do not call signoff here: MoneyMoney invokes GetAvailableStatements/GetStatement
  -- after EndSession(), and signoff can invalidate the statements API session.
end

local function resolveAdxToken(adxToken)
  if adxToken and adxToken ~= "" then
    return adxToken
  end
  if session.adxToken and session.adxToken ~= "" then
    return session.adxToken
  end

  local requestHeaders = buildRequestHeaders(CONSTANTS.baseUrl .. "/")
  local response = performGet(
    CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go?filter=0&sort=0&order=0",
    requestHeaders,
    CONSTANTS.baseUrl .. "/"
  )

  if not response then
    return nil
  end

  rememberStatementPageUrl(response, adxToken)
  adxToken = updateAdxFromResponse(response, adxToken)
  return adxToken
end

local function appendParsedStatement(statements, seenDocIds, docId, docName, dateStr, adxToken, sinceTimestamp)
  local y, m, d = dateStr:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  local bookingDate = os.time()
  if y and m and d then
    bookingDate = os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d)})
  end

  if sinceTimestamp and bookingDate < sinceTimestamp then
    return
  end
  if seenDocIds[docId] then
    return
  end

  seenDocIds[docId] = true
  table.insert(statements, {
    id = docId .. "|" .. adxToken,
    type = "Statement",
    name = docName,
    periodEnd = os.date("%Y-%m-%d", bookingDate),
    generatedDate = os.date("%Y-%m-%d", bookingDate),
    formats = "PDF"
  })
end

local function parseStatementsFromGatherResponse(jsonResponse, adxToken, sinceTimestamp, seenDocIds, statements)
  if not jsonResponse or jsonResponse == "" then
    return
  end

  local documentList = jsonResponse:match('"documentList"%s*:%s*(%b[])')
  local searchText = documentList or jsonResponse
  for docId, docName, dateStr in searchText:gmatch('"docId"%s*:%s*"([^"]+)"[^}]-"docDisplayName"%s*:%s*"([^"]+)"[^}]-"date"%s*:%s*"([^"]+)"') do
    appendParsedStatement(statements, seenDocIds, docId, docName, dateStr, adxToken, sinceTimestamp)
  end
end

function fetchStatementDocuments(adxToken, sinceTimestamp)
  local statements = {}
  local seenDocIds = {}

  adxToken = resolveAdxToken(adxToken)
  if not adxToken then
    return statements
  end


  local accountDetailsReferer = CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go?filter=0&sort=0&order=0"
  local statementReferer = warmupStatementSession(adxToken, accountDetailsReferer)
  adxToken = session.adxToken or adxToken

  local gatherUrl = CONSTANTS.baseUrl .. "/ogateway/dsviewdocuments/omni/statements/v1/gatherDocuments"
  local postHeaders = buildJsonPostHeaders(statementReferer)

  local currentYear = os.date("%Y")
  local bootstrapData = '{"adx":"' .. adxToken .. '","year":"' .. currentYear .. '","docCategoryId":"0000"}'
  local bootstrapResponse = performPost(gatherUrl, bootstrapData, "application/json; charset=UTF-8", postHeaders, statementReferer)
  if bootstrapResponse and bootstrapResponse ~= "" then
    parseStatementsFromGatherResponse(bootstrapResponse, adxToken, sinceTimestamp, seenDocIds, statements)
  end

  local years = {currentYear, tostring(tonumber(currentYear) - 1)}
  for _, year in ipairs(years) do
    local postData = '{"year":"' .. year .. '","adx":"' .. adxToken .. '","docCategoryId":"DISPFLD001","lang":"en-US"}'
    local stmtResponse = performPost(gatherUrl, postData, "application/json; charset=UTF-8", postHeaders, statementReferer)

    if stmtResponse and stmtResponse ~= "" then
      parseStatementsFromGatherResponse(stmtResponse, adxToken, sinceTimestamp, seenDocIds, statements)
    end
  end

  return statements
end

local function buildKnownIdentifierSet(knownIdentifiers)
  local knownSet = {}
  if type(knownIdentifiers) ~= "table" then
    return knownSet
  end

  for key, value in pairs(knownIdentifiers) do
    if type(key) == "number" and type(value) == "string" then
      knownSet[value] = true
    elseif type(key) == "string" then
      knownSet[key] = true
    end
  end
  return knownSet
end

local function parseStatementCreationDate(periodEnd)
  if not periodEnd then
    return os.time()
  end
  local y, m, d = periodEnd:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if y and m and d then
    return os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d)})
  end
  return os.time()
end

local function downloadStatementPdf(docId, adxToken)
  adxToken = resolveAdxToken(adxToken)
  if not docId or not adxToken then
    return nil, "missing document information"
  end

  local accountDetailsReferer = CONSTANTS.baseUrl .. "/myaccounts/details/card/account-details.go?filter=0&sort=0&order=0"
  local statementReferer = warmupStatementSession(adxToken, accountDetailsReferer)
  adxToken = session.adxToken or adxToken
  local postHeaders = buildJsonPostHeaders(statementReferer)

  local downloadUrl = CONSTANTS.baseUrl .. "/ogateway/dsviewdocuments/omni/statements/v1/docViewDownload" ..
    "?adx=" .. MM.urlencode(adxToken) ..
    "&documentId=" .. MM.urlencode(docId) ..
    "&adaDocumentFlag=N" ..
    "&menuFlag=download" ..
    "&request_locale=en-US"

  local pdfHeaders = buildPdfGetHeaders(statementReferer)
  local response, mimeType = performGet(downloadUrl, pdfHeaders, statementReferer)

  if response and (response:sub(1, 4) == "%PDF" or (mimeType and mimeType:lower():find("pdf"))) then
    return response, nil
  end

  local postData = '{"adx":"' .. adxToken .. '","docId":"' .. docId .. '","docCategoryId":"DISPFLD001"}'
  response, mimeType = performPost(
    CONSTANTS.baseUrl .. "/ogateway/dsviewdocuments/omni/statements/v1/retrieveDocument",
    postData,
    "application/json; charset=UTF-8",
    postHeaders,
    statementReferer
  )

  if response then
    if response:sub(1, 4) == "%PDF" or (mimeType and mimeType:lower():find("pdf")) then
      return response, nil
    end
    local pdfBase64 = response:match('"pdfData"%s*:%s*"([^"]+)"') or response:match('"documentData"%s*:%s*"([^"]+)"')
    if pdfBase64 and MM.base64Decode then
      local pdf = MM.base64Decode(pdfBase64)
      if pdf and pdf:sub(1, 4) == "%PDF" then
        return pdf, nil
      end
    end
  end

  if response and (response:sub(1, 200):find("html") or response:sub(1, 200):find("<!DOCTYPE")) then
    return nil, "server returned HTML instead of PDF"
  end

  if mimeType then
    return nil, "unexpected response (mimeType " .. tostring(mimeType) .. ")"
  end
  return nil, "no response from server"
end

function FetchStatements(accounts, knownIdentifiers)
  ensureConnection()

  if not session.cookies or session.cookies == "" then
    return "No active session cookies for statement download"
  end

  local knownSet = buildKnownIdentifierSet(knownIdentifiers)
  local downloadedStatements = {}
  local availableStatements = fetchStatementDocuments(session.adxToken, nil)

  for _, statementMeta in ipairs(availableStatements) do
    local identifier = statementMeta.id or ((statementMeta.name or "statement") .. "|" .. (statementMeta.periodEnd or ""))
    if not knownSet[identifier] then
      local docId, adxToken = identifier:match("([^|]+)|(.+)")
      local pdf = downloadStatementPdf(docId, adxToken)
      if pdf then
        table.insert(downloadedStatements, {
          creationDate = parseStatementCreationDate(statementMeta.periodEnd),
          name = statementMeta.name or "Statement",
          identifier = identifier,
          pdf = pdf,
          filename = (statementMeta.name or "statement"):gsub("[^%w%-_ ]", "") .. ".pdf"
        })
      end
    end
  end

  return { statements = downloadedStatements }
end

function GetAvailableStatements(account, since)
  ensureConnection()

  if not session.cookies or session.cookies == "" then
    return nil
  end

  local sinceTimestamp = since
  local statements = fetchStatementDocuments(session.adxToken, sinceTimestamp)

  if #statements == 0 then
    return {}
  end

  return statements
end

function GetStatement(account, statementId)
  ensureConnection()

  if not session.cookies or session.cookies == "" then
    return "Could not download statement: session expired"
  end

  local docId, adxToken = statementId:match("([^|]+)|(.+)")
  if not docId then
    docId = statementId
  end

  local pdf, err = downloadStatementPdf(docId, adxToken)
  if pdf then
    return pdf
  end

  return "Could not download statement: " .. tostring(err)
end

function DownloadStatement(account, statement)
  local statementId = statement
  if type(statement) == "table" then
    statementId = statement.id or statement.statementId
  end
  return GetStatement(account, statementId)
end
