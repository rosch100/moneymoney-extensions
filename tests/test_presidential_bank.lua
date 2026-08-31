-- Unit-Tests für ausgewählte Pure-Logik in `extensions/Presidential Bank.lua`.
-- Diese Tests stubben die nötigen MoneyMoney-Globals, damit keine echten HTTP-Requests passieren.

function WebBanking(_) end

ProtocolWebBanking = "WebBanking"
LoginFailed = "LoginFailed"

-- MoneyMoney-Typen (numerische Values sind im Extension-Code nur für Gleichheit relevant).
AccountTypeGiro = 1
AccountTypeSavings = 2
AccountTypeCreditCard = 3
AccountTypeLoan = 4
AccountTypeSecurities = 5

local presidentialResponses = {}
function Connection()
  return {
    request = function()
      return table.remove(presidentialResponses, 1)
    end,
    getCookies = function()
      return ""
    end,
  }
end

MM = {
  printStatus = function() end,
  urlencode = function(value)
    return tostring(value)
  end,
}

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

local function assertNear(actual, expected, eps, label)
  eps = eps or 0.001
  if math.abs((actual or 0) - expected) < eps then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected~" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

-- Load extension (defines globals we test)
dofile("extensions/Presidential Bank.lua")

-- normalizeWhitespace
assertEq(normalizeWhitespace("  a   b  "), "a b", "normalizeWhitespace.compress")
assertEq(normalizeWhitespace("   "), "", "normalizeWhitespace.trim-empty")

-- parseTransactionDescription: Pattern 1 (prefix + ENTITY / NAME - DETAILS)
do
  local name, purpose = parseTransactionDescription("Withdrawal / Empfänger - Details  ")
  assertEq(name, "Empfänger", "parseTransactionDescription.pattern1.name")
  assertEq(purpose, "Withdrawal - Details", "parseTransactionDescription.pattern1.purpose")
end

-- parseTransactionDescription: Pattern 2 (prefix / NAME - DETAILS)
do
  local name, purpose = parseTransactionDescription("Deposit / Name - Details")
  assertEq(name, "Name", "parseTransactionDescription.pattern2.name")
  assertEq(purpose, "Deposit - Details", "parseTransactionDescription.pattern2.purpose")
end

-- parseTransactionDescription: Pattern 3 (Before / After - no mandatory dash in first slash)
do
  local name, purpose = parseTransactionDescription("Prefix / Name - Details")
  assertEq(name, "Name", "parseTransactionDescription.pattern3.name")
  assertEq(purpose, "Prefix - Details", "parseTransactionDescription.pattern3.purpose")
end

-- parseTransactionDescription: fallback (simple description)
do
  local name, purpose = parseTransactionDescription("Just a plain string")
  assertEq(name, "", "parseTransactionDescription.fallback.name")
  assertEq(purpose, "Just a plain string", "parseTransactionDescription.fallback.purpose")
end

-- extractAccountNumber
do
  local v1 = extractAccountNumber("123")
  assertEq(v1, "123", "extractAccountNumber.string")

  local v2 = extractAccountNumber({ hostValue = "HOST-1", displayValue = "DISP-1" })
  assertEq(v2, "HOST-1", "extractAccountNumber.table.hostValue")

  local v3 = extractAccountNumber({ displayValue = "DISP-2" })
  assertEq(v3, "DISP-2", "extractAccountNumber.table.displayValue")

  local v4 = extractAccountNumber(nil)
  assertEq(v4, nil, "extractAccountNumber.nil")
end

-- buildWebsiteAccountLabel
do
  local fullAccount = "12345678"
  local maskSuffix = "*5678"
  local nickname = "Checking"

  local websiteLabel = buildWebsiteAccountLabel(
    { nickname = nickname },
    "unknown",
    nickname .. " " .. maskSuffix
  )
  assertEq(websiteLabel, nickname .. " " .. maskSuffix, "buildWebsiteAccountLabel.fromApi")

  local fromFull = buildWebsiteAccountLabel(
    { nickname = nickname },
    fullAccount,
    maskSuffix
  )
  assertEq(fromFull, nickname .. " " .. maskSuffix, "buildWebsiteAccountLabel.neverExposesFullNumber")

  local fallback = buildWebsiteAccountLabel(
    { nickname = nickname },
    nil,
    maskSuffix
  )
  assertEq(fallback, nickname .. " " .. maskSuffix, "buildWebsiteAccountLabel.fallbackToWebsiteLabel")

  local maskedOnly = buildWebsiteAccountLabel({}, fullAccount, nil)
  assertEq(maskedOnly, maskSuffix, "buildWebsiteAccountLabel.maskedOnly")
end

-- parseAccounts
do
  local fullAccount = "12345678"
  local maskSuffix = "*5678"
  local nickname = "Checking"

  local accounts = parseAccounts({
    {
      id = "D0",
      nickname = nickname,
      accountNumber = fullAccount,
      accountType = "checking"
    }
  })
  assertEq(#accounts, 1, "parseAccounts.count")
  assertEq(accounts[1].accountNumber, nickname .. " " .. maskSuffix, "parseAccounts.accountNumber.maskedOnly")
  assertEq(accounts[1]._internalId, "D0", "parseAccounts.internalId")

  local maskedAccounts = parseAccounts({
    {
      id = "D1",
      nickname = nickname,
      accountNumber = { displayValue = maskSuffix },
      displayAccountNumber = maskSuffix,
      accountType = "checking"
    }
  })
  assertEq(maskedAccounts[1].accountNumber, nickname .. " " .. maskSuffix, "parseAccounts.accountNumber.websiteFallback")

  local availableBalanceAccounts = parseAccounts({
    {
      id = "D2",
      nickname = nickname,
      accountNumber = fullAccount,
      accountType = "checking",
      balance = "invalid",
      availableBalance = "42.50",
    }
  })
  assertEq(availableBalanceAccounts[1]._balance, 42.5,
    "parseAccounts.usesValidAvailableBalance")

  local missingNumberOk = pcall(parseAccounts, {
    {id = "D3", nickname = nickname, accountType = "checking"}
  })
  assertEq(missingNumberOk, false, "parseAccounts.rejectsMissingNumber")

  local missingNameOk = pcall(parseAccounts, {
    {id = "D4", accountNumber = fullAccount, accountType = "checking"}
  })
  assertEq(missingNameOk, false, "parseAccounts.rejectsMissingName")

  local unknownTypeOk = pcall(parseAccounts, {
    {id = "D5", nickname = nickname, accountNumber = fullAccount, accountType = "unknown"}
  })
  assertEq(unknownTypeOk, false, "parseAccounts.rejectsUnknownType")
end

assertEq(
  _G.classifyLoginRedirectError({targetView = "consumer_login"}),
  "Anmeldeserver meldet eine ungültige Login-Weiterleitung.",
  "classifyLoginRedirectError.consumerLogin")

-- mapAccountType
do
  assertEq(mapAccountType("checking"), AccountTypeGiro, "mapAccountType.checking")
  assertEq(mapAccountType("savings"), AccountTypeSavings, "mapAccountType.savings")
  assertEq(mapAccountType("credit"), AccountTypeCreditCard, "mapAccountType.credit")
  assertEq(mapAccountType("loan"), AccountTypeLoan, "mapAccountType.loan")
  assertEq(mapAccountType("investment"), AccountTypeSecurities, "mapAccountType.investment")
  assertEq(mapAccountType("unknown-type"), nil, "mapAccountType.unknown")
end

-- isValidAccountId
do
  assertEq(isValidAccountId("0"), false, "isValidAccountId.zero")
  assertEq(isValidAccountId("PLACEHOLDER"), false, "isValidAccountId.placeholder")
  assertEq(isValidAccountId("0000000000"), false, "isValidAccountId.all-zeros")
  assertEq(isValidAccountId("987654321"), true, "isValidAccountId.valid")
end

-- parseDate: YYYY-MM-DD + US MM/DD/YYYY
do
  local ymd = os.time({ year = 2026, month = 1, day = 1 })
  local parsed = parseDate("2026-01-01")
  assertEq(parsed, ymd, "parseDate.ymd")

  local mdY = os.time({ year = 1970, month = 1, day = 1 })
  local parsed2 = parseDate("1/1/1970")
  assertEq(parsed2, mdY, "parseDate.mdy")
  assertEq(parseDate("2026-02-31"), nil, "parseDate.rejectsInvalidCalendarDay")
end

-- extractCookieValue
do
  local c = "SESSION_TOKEN=AAA; rftoken=BBB; other=CCC"
  assertEq(extractCookieValue(c, "rftoken"), "BBB", "extractCookieValue.rftoken")
  assertEq(extractCookieValue(c, "missing"), nil, "extractCookieValue.missing=nil")
  assertEq(extractCookieValue(nil, "rftoken"), nil, "extractCookieValue.nil.cookies")
end

-- extractCsrfTokenFromCookies
do
  local c = "CSRFToken=XYZ; SESSION_TOKEN=AAA"
  assertEq(extractCsrfTokenFromCookies(c), "XYZ", "extractCsrfTokenFromCookies.ok")
  assertEq(extractCsrfTokenFromCookies("nope=1"), nil, "extractCsrfTokenFromCookies.none=nil")
end

-- buildApiHeaders / mergeSessionCookie / buildLoginUpdateBody / applyResponseCookies
do
  function JSON()
    return {
      set = function(_, tbl)
        return {
          json = function()
            if tbl.mfaInfo and tbl.mfaInfo.computerPrivate then
              return '{"csrftoken":"' .. tbl.csrftoken .. '","mfaInfo":{"computerPrivate":true}}'
            end
            if tbl.csrftoken then
              return '{"csrftoken":"' .. tbl.csrftoken .. '"}'
            end
            return "{}"
          end
        }
      end
    }
  end

  mergeSessionCookie("SESSION_TOKEN", "AAA")
  mergeSessionCookie("CSRFToken", "XYZ")
  local h = buildApiHeaders()
  assertEq(h["Cookie"], "SESSION_TOKEN=AAA; CSRFToken=XYZ", "buildApiHeaders.Cookie")
  assertEq(h["X-Requested-With"], "XMLHttpRequest", "buildApiHeaders.X-Requested-With")

  mergeSessionCookie("rftoken", "RF-99")
  h = buildApiHeaders()
  assertEq(extractCookieValue(h["Cookie"], "rftoken"), "RF-99", "mergeSessionCookie.rftoken")

  mergeSessionCookie("rftoken", "RF-NEW")
  h = buildApiHeaders()
  assertEq(extractCookieValue(h["Cookie"], "rftoken"), "RF-NEW", "mergeSessionCookie.update")

  assertEq(buildLoginUpdateBody(), '{"csrftoken":"XYZ"}', "buildLoginUpdateBody.fromCookieCsrf")

  mergeSessionCookie("MAF_IB_testdevice", "trust-token")
  assertEq(hasPrivateDeviceCookie(), true, "hasPrivateDeviceCookie.mafIb")
  assertEq(hasPrivateDeviceCookieInMap({ MAF_IB_abc = "x" }), true, "hasPrivateDeviceCookieInMap.mafIb")
  assertEq(hasPrivateDeviceCookie("SESSION_TOKEN=1"), false, "hasPrivateDeviceCookie.withoutMaf")

  applyResponseCookies({ { name = "Set-Cookie", value = "rftoken=FROM-HEADER; Path=/" } })
  h = buildApiHeaders()
  assertEq(extractCookieValue(h["Cookie"], "rftoken"), "FROM-HEADER", "applyResponseCookies.setCookieEntry")
end

-- buildMfaSelectUrl / buildMfaSubmitUrl / mfaVirtualButtonLabel / buildMfaSelectBody / buildMfaSubmitBody / isMfaSelectSuccess
do
  local methods = {
    { protocol = "SMS", type = "sms", id = "sms-1", label = "Text me" },
    { protocol = "VOICE", type = "voice", id = "voice-1", label = "Call me" },
    { protocol = "EMAIL", type = "email", id = "email-1", label = "Email me" },
    { protocol = "TOTP", type = "totp", id = "totp-1", label = "Enter code" }
  }

  for _, method in ipairs(methods) do
    local base = "https://www.presidentialpcbanking.com/auth-olb/live/v1/mfa/"
    assertEq(
      buildMfaSelectUrl(method),
      base .. "select?type=" .. method.type,
      "buildMfaSelectUrl." .. method.type
    )
    assertEq(
      buildMfaSubmitUrl(method),
      base .. "submit?displayMethod=" .. method.protocol .. "&type=OTP&cookieoptin=true",
      "buildMfaSubmitUrl." .. method.type
    )
    assertEq(
      buildMfaSubmitUrl(method, false),
      base .. "submit?displayMethod=" .. method.protocol .. "&type=OTP&cookieoptin=false",
      "buildMfaSubmitUrl.noCookieoptin." .. method.type
    )
    assertEq(mfaVirtualButtonLabel(method), method.label, "mfaVirtualButtonLabel." .. method.type)
  end

  mergeSessionCookie("CSRFToken", "XYZ")

  assertEq(
    buildMfaSelectBody(methods[3]),
    '{"destId":"email-1","csrftoken":"XYZ"}',
    "buildMfaSelectBody.email"
  )
  assertEq(
    buildMfaSubmitBody(methods[3], "891726"),
    '{"destId":"email-1","csrftoken":"XYZ","otp":"891726"}',
    "buildMfaSubmitBody.email"
  )

  function JSON(str)
    if str == "select-ok" then
      return { dictionary = function() return { result = "success" } end }
    end
    if str == "select-err" then
      return { dictionary = function() return { errorCode = "24001" } end }
    end
    return { dictionary = function() return nil end }
  end

  assertEq(isMfaSelectSuccess("select-ok"), true, "isMfaSelectSuccess.ok")
  assertEq(isMfaSelectSuccess("select-err"), false, "isMfaSelectSuccess.error")
  assertEq(isMfaSelectSuccess(nil), false, "isMfaSelectSuccess.nil")
end
do
  assertEq(isMfaSessionError({ errorCode = "10000" }), true, "isMfaSessionError.10000")
  assertEq(isMfaSessionError({ errorCode = 10000 }), true, "isMfaSessionError.10000num")
  assertEq(isMfaSessionError({ errorCode = "25108" }), false, "isMfaSessionError.wrongCode")
  assertEq(isMfaSessionError(nil), false, "isMfaSessionError.nil")
end

-- extractPostLoginUrl / extractRftokenFromText
do
  function JSON(str)
    if str == "direct" then
      return { dictionary = function() return { resultURL = "/app/postLogin" } end }
    end
    if str == "nested" then
      return { dictionary = function() return { result = "inner" } end }
    end
    if str == "inner" then
      return { dictionary = function() return { success = "success", resultURL = "/app/postLogin" } end }
    end
    if str == "token" then
      return { dictionary = function() return { rftoken = "RF-123" } end }
    end
    return { dictionary = function() return nil end }
  end

  local url = extractPostLoginUrl("direct")
  assertEq(url, "https://www.presidentialpcbanking.com/dbank/live/app/postLogin", "extractPostLoginUrl.direct")

  local url2 = extractPostLoginUrl("nested")
  assertEq(url2, "https://www.presidentialpcbanking.com/dbank/live/app/postLogin", "extractPostLoginUrl.nested")

  assertEq(extractRftokenFromText('{"rftoken":"RF-123"}'), "RF-123", "extractRftokenFromText.json")
end

-- persistSessionState / restorePersistedSessionState
do
  mergeSessionCookie("SESSION_TOKEN", "PERSIST-AAA")
  mergeSessionCookie("CSRFToken", "PERSIST-XYZ")
  mergeSessionCookie("rftoken", "RF-PERSIST")

  local storage = {}
  persistSessionState(storage)
  assertEq(type(storage.presidentialSessionCookies), "table", "persistSessionState.sessionCookies")
  assertEq(storage.presidentialSessionCookies.SESSION_TOKEN, "PERSIST-AAA", "persistSessionState.sessionCookies.SESSION_TOKEN")
  assertEq(storage.presidentialRftoken, "RF-PERSIST", "persistSessionState.rftoken")
  assertEq(storage.presidentialCsrfToken, "PERSIST-XYZ", "persistSessionState.csrfToken")
  assertEq(storage.presidentialSession, nil, "persistSessionState.noLegacyNested")

  local storagePrivate = {
    connectionAccountKey = "user1",
    presidentialSessionCookies = { SESSION_TOKEN = "PRIV-1", MAF_IB_test = "x" },
    presidentialSessionAccountKey = "user1",
    presidentialDevicePrivate = true
  }
  assertEq(canRestorePersistedSession(storagePrivate, "user1"), true, "canRestorePersistedSession.privateDevice")
  assertEq(canRestorePersistedSession(storagePrivate, "user2"), true, "canRestorePersistedSession.privateIgnoresKey")
  assertEq(accountKeysMatch("User1", "user1"), true, "accountKeysMatch.caseInsensitive")

  local storageOther = {
    presidentialSessionCookies = { SESSION_TOKEN = "X" },
    presidentialSessionAccountKey = "user1",
    presidentialLoginComplete = true
  }
  assertEq(canRestorePersistedSession(storageOther, "user2"), false, "canRestorePersistedSession.wrongAccount")

  restorePersistedSessionState({
    presidentialSessionCookies = {
      SESSION_TOKEN = "RESTORED",
      CSRFToken = "REST-CSRF",
      rftoken = "RF-RESTORED"
    },
    presidentialRftoken = "RF-RESTORED",
    presidentialCsrfToken = "REST-CSRF",
    presidentialSessionAccountKey = "user1"
  }, "user1")
  local headers = buildApiHeaders()
  assertEq(extractCsrfTokenFromCookies(headers["Cookie"]), "REST-CSRF", "restorePersistedSessionState.csrfToken")
  assertEq(headers["Cookie"]:match("SESSION_TOKEN=RESTORED") ~= nil, true, "restorePersistedSessionState.cookies")
  assertEq(headers["Cookie"]:match("rftoken=RF%-RESTORED") ~= nil, true, "restorePersistedSessionState.rftoken")
end

-- parseJson / isMfaSuccess with JSON stub
do
  local jsonMap = {
    good = { a = 1 },
    outerErr = { errorCode = "X" },
    outerSuccess = { targetView = "success" },
    outerResult = { result = "INNER" },
    INNER = { success = "success" }
  }

  function JSON(str)
    if str == "bad" then error("boom") end
    local v = jsonMap[str]
    return {
      dictionary = function()
        return v
      end
    }
  end

  local pj = parseJson("good")
  assertEq(type(pj), "table", "parseJson.good.type")
  if not pj then
    error("parseJson.good returned nil")
  end
  assertEq(pj.a, 1, "parseJson.good.value")
  assertEq(parseJson(nil), nil, "parseJson.nil")
  assertEq(parseJson("bad"), nil, "parseJson.invalid->nil")

  assertEq(isMfaSuccess("outerErr"), false, "isMfaSuccess.errorCode=false")
  assertEq(isMfaSuccess("outerSuccess"), true, "isMfaSuccess.targetView-success=true")
  assertEq(isMfaSuccess("outerResult"), true, "isMfaSuccess.result.success=true")
end

-- Technische Loginfehler dürfen gespeicherte Zugangsdaten nicht invalidieren.
do
  local authFailures = {}
  local function checkTransient(value, label)
    if type(value) == "string" and value ~= "" and value ~= LoginFailed then
      print("OK    " .. label)
    else
      authFailures[#authFailures + 1] = label .. "=" .. tostring(value)
      print("FAIL  " .. label)
    end
  end

  JSON = function(value)
    return {
      dictionary = function()
        if value == "SERVER_ERROR" then
          return {
            targetView = "error",
            errorMessage = "Service temporarily unavailable",
          }
        end
        if value == "BAD_CREDENTIALS" then
          return {
            targetView = "error",
            errorMessage = "Invalid user ID or password",
          }
        end
        if value == "{}" then
          return {}
        end
        if value == "bad" then
          error("invalid JSON")
        end
        return nil
      end,
    }
  end

  local missingState = InitializeSession2(
    ProtocolWebBanking,
    "Presidential Bank",
    2,
    {"user", "secret"},
    true)
  checkTransient(missingState, "InitializeSession2.missingState.transient")

  presidentialResponses = {}
  local noExternalResponse = handleLoginStep1({"user", "secret"})
  checkTransient(noExternalResponse, "handleLoginStep1.noExternalResponse.transient")

  presidentialResponses = {"SERVER_ERROR"}
  local technicalApiError = handleLoginStep1({"user", "secret"})
  checkTransient(technicalApiError, "handleLoginStep1.technicalApiError.transient")

  presidentialResponses = {"BAD_CREDENTIALS"}
  local rejectedCredentials = handleLoginStep1({"user", "wrong"})
  assertEq(rejectedCredentials, LoginFailed, "handleLoginStep1.rejectedCredentials")

  presidentialResponses = {"{}"}
  local noRedirectResponse = handleLoginStep1({"user", "secret"})
  checkTransient(noRedirectResponse, "handleLoginStep1.noRedirectResponse.transient")

  presidentialResponses = {}
  local noMfaConfig = getMfaConfig()
  checkTransient(noMfaConfig, "getMfaConfig.noResponse.transient")

  presidentialResponses = {"bad"}
  local invalidMfaConfig = getMfaConfig()
  checkTransient(invalidMfaConfig, "getMfaConfig.invalidResponse.transient")

  presidentialResponses = {"{}"}
  getMfaConfig()
  mergeSessionCookie("SESSION_TOKEN", "ACTIVE")
  presidentialResponses = {"bad"}
  local invalidMfaResponse = verifyMfaCode("123456")
  checkTransient(invalidMfaResponse, "verifyMfaCode.invalidResponse.transient")

  EndSession()
  followPostLoginRedirect = function() end
  activateOlbSession = function() end
  performApiRequest = function() return nil end
  collectRftokenFromResponses = function() end
  updateDevicePrivateFromAuthtoken = function() end
  verifySessionWithAccounts = function() return false end
  verifySessionWithHistory = function() return false end
  local incompleteSession = finalizeLogin("{}")
  checkTransient(incompleteSession, "finalizeLogin.incompleteSession.transient")

  if #authFailures > 0 then
    error("Auth error classification failed: " .. table.concat(authFailures, ", "))
  end
end

local invalidRefreshOk, invalidRefreshError = pcall(RefreshAccount, nil, nil)
assertEq(invalidRefreshOk, false, "RefreshAccount.propagatesInvalidAccount")
assertEq(
  type(invalidRefreshError) == "string"
    and invalidRefreshError:find("Kontoabruf", 1, true) ~= nil,
  true,
  "RefreshAccount.invalidAccountMessage")

local missingBalanceOk, missingBalanceError = pcall(parseTransactions, {}, nil)
assertEq(missingBalanceOk, false, "parseTransactions.requiresBalance")
assertEq(
  type(missingBalanceError) == "string"
    and missingBalanceError:find("Kontostand", 1, true) ~= nil,
  true,
  "parseTransactions.missingBalanceMessage")
local emptyTransactions = parseTransactions({}, 12.34)
assertEq(emptyTransactions.balance, 12.34, "parseTransactions.accountBalance")
local retainedAccountBalance = parseTransactions(
  {
    {
      amount = "1.00",
      creditTransaction = false,
      transactionDate = "2026-08-31",
      ledgerBalance = "9.99",
      generatedDescription = "Debit",
    },
  },
  12.34)
assertEq(retainedAccountBalance.balance, 12.34,
  "parseTransactions.prefersProvidedAccountBalance")
local invalidAmountOk, invalidAmountError = pcall(
  parseTransactions,
  {
    {
      amount = "invalid",
      transactionDate = "2026-08-31",
      generatedDescription = "Invalid amount",
    }
  },
  12.34)
assertEq(invalidAmountOk, false, "parseTransactions.rejectsInvalidAmount")
assertEq(
  type(invalidAmountError) == "string"
    and invalidAmountError:find("Umsatzbetrag", 1, true) ~= nil,
  true,
  "parseTransactions.invalidAmountMessage")
local invalidDateOk, invalidDateError = pcall(
  parseTransactions,
  {
    {
      amount = "12.34",
      creditTransaction = false,
      transactionDate = "invalid",
      generatedDescription = "Invalid date",
    }
  },
  12.34)
assertEq(invalidDateOk, false, "parseTransactions.rejectsInvalidDate")
assertEq(
  type(invalidDateError) == "string"
    and invalidDateError:find("Umsatzdatum", 1, true) ~= nil,
  true,
  "parseTransactions.invalidDateMessage")

local originalListAccounts = ListAccounts
ListAccounts = function()
  return {
    {
      accountNumber = "Checking *9999",
      name = "Different account",
      _internalId = "OTHER-ID",
    },
  }
end
assertEq(
  resolveAccountId({ accountNumber = "Checking *1234", name = "Expected account" }),
  nil,
  "resolveAccountId.rejectsUnmatchedSingleAccount")
ListAccounts = function()
  return {
    { accountNumber = "Checking *1111", name = "Shared", _internalId = "ID-1" },
    { accountNumber = "Checking *2222", name = "Shared", _internalId = "ID-2" },
  }
end
assertEq(
  resolveAccountId({ accountNumber = "Checking *9999", name = "Shared" }),
  nil,
  "resolveAccountId.rejectsAmbiguousName")
assertEq(
  resolveAccountId({_internalId = "0", accountNumber = "Checking *9999"}),
  nil,
  "resolveAccountId.rejectsInvalidStoredId")
ListAccounts = function()
  return {
    {
      accountNumber = "Checking *1234",
      name = "Expected account",
      _internalId = "MATCH-ID",
      _balance = 98.76,
    },
  }
end
local resolvedAccountId, resolvedBalance = resolveAccountId({
  accountNumber = "Checking *1234",
  name = "Expected account",
})
assertEq(resolvedAccountId, "MATCH-ID", "resolveAccountId.exactNumber")
assertEq(resolvedBalance, 98.76, "resolveAccountId.propagatesDiscoveredBalance")
ListAccounts = originalListAccounts

local missingDirectionOk, missingDirectionError = pcall(
  parseTransactions,
  {
    {
      amount = "12.34",
      transactionDate = "2026-08-31",
      generatedDescription = "Unknown direction",
    },
  },
  12.34)
assertEq(missingDirectionOk, false, "parseTransactions.requiresDirection")
assertEq(
  type(missingDirectionError) == "string"
    and missingDirectionError:find("Umsatzrichtung", 1, true) ~= nil,
  true,
  "parseTransactions.missingDirectionMessage")

print("ALL PRESIDENTIAL BANK UNIT TESTS PASSED")

