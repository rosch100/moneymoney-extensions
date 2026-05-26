-- Unit-Tests für ausgewählte Pure-Logik in `extensions/Presidential Bank.lua`.
-- Diese Tests stubben die nötigen MoneyMoney-Globals, damit keine echten HTTP-Requests passieren.

function WebBanking(_) end

ProtocolWebBanking = "WebBanking"

-- MoneyMoney-Typen (numerische Values sind im Extension-Code nur für Gleichheit relevant).
AccountTypeGiro = 1
AccountTypeSavings = 2
AccountTypeCreditCard = 3
AccountTypeLoan = 4
AccountTypeSecurities = 5

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
  assertEq(name, "ABC My Entity", "parseTransactionDescription.pattern1.name")
  assertEq(purpose, "Withdrawal - My Entity", "parseTransactionDescription.pattern1.purpose")
end

-- parseTransactionDescription: Pattern 2 (prefix / NAME - DETAILS)
do
  local name, purpose = parseTransactionDescription("Deposit / Name - Details")
  assertEq(name, "Some Name", "parseTransactionDescription.pattern2.name")
  assertEq(purpose, "Deposit - Details", "parseTransactionDescription.pattern2.purpose")
end

-- parseTransactionDescription: Pattern 3 (Before / After - no mandatory dash in first slash)
do
  local name, purpose = parseTransactionDescription("Prefix / Name - Details")
  assertEq(name, "After Name", "parseTransactionDescription.pattern3.name")
  assertEq(purpose, "Before - After Details", "parseTransactionDescription.pattern3.purpose")
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
  assertEq(v4, "unknown", "extractAccountNumber.nil")
end

-- mapAccountType
do
  assertEq(mapAccountType("checking"), AccountTypeGiro, "mapAccountType.checking")
  assertEq(mapAccountType("savings"), AccountTypeSavings, "mapAccountType.savings")
  assertEq(mapAccountType("credit"), AccountTypeCreditCard, "mapAccountType.credit")
  assertEq(mapAccountType("loan"), AccountTypeLoan, "mapAccountType.loan")
  assertEq(mapAccountType("investment"), AccountTypeSecurities, "mapAccountType.investment")
  assertEq(mapAccountType("unknown-type"), AccountTypeGiro, "mapAccountType.unknown-fallback")
end

-- isValidAccountId
do
  assertEq(isValidAccountId("0"), false, "isValidAccountId.zero")
  assertEq(isValidAccountId("PLACEHOLDER"), false, "isValidAccountId.placeholder")
  assertEq(isValidAccountId("0000000000"), false, "isValidAccountId.all-zeros")
  assertEq(isValidAccountId("12345"), true, "isValidAccountId.valid")
end

-- parseDate: YYYY-MM-DD + US MM/DD/YYYY
do
  local ymd = os.time({ year = 2024, month = 1, day = 2 })
  local parsed = parseDate("2024-01-02")
  assertEq(parsed, ymd, "parseDate.ymd")

  local mdY = os.time({ year = 1968, month = 9, day = 7 })
  local parsed2 = parseDate("9/7/1968")
  assertEq(parsed2, mdY, "parseDate.mdy")
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

-- buildApiHeaders (requires only cookies param)
do
  local h = buildApiHeaders("A=B")
  assertEq(h["Cookie"], "A=B", "buildApiHeaders.Cookie")
  assertEq(h["X-Requested-With"], "XMLHttpRequest", "buildApiHeaders.X-Requested-With")
  assertEq(h["Content-Type"], "application/json", "buildApiHeaders.Content-Type")
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
  assertEq(pj.a, 1, "parseJson.good.value")
  assertEq(parseJson(nil), nil, "parseJson.nil")
  assertEq(parseJson("bad"), nil, "parseJson.invalid->nil")

  assertEq(isMfaSuccess("outerErr"), false, "isMfaSuccess.errorCode=false")
  assertEq(isMfaSuccess("outerSuccess"), true, "isMfaSuccess.targetView-success=true")
  assertEq(isMfaSuccess("outerResult"), true, "isMfaSuccess.result.success=true")
end

print("ALL PRESIDENTIAL BANK UNIT TESTS PASSED")

