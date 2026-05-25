-- Lokaler Funktions-Test der Shareview-Parser gegen die echten HAR-Daten.
-- Lädt die Extension nicht über die WebBanking-Engine, sondern stubbt
-- die nötigen Globals und prüft Parser-Ausgaben.

-- WebBanking/Connection/MM stubben
function WebBanking(_) end

ProtocolWebBanking = "WebBanking"
AccountTypePortfolio = 5
LoginFailed = "LoginFailed"

MM = {
  printStatus = function(msg) io.stderr:write("[STATUS] " .. msg .. "\n") end,
  urlencode = function(s)
    return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end
}

function Connection() return { request = function() end, getCookies = function() return "" end } end

-- Extension laden
dofile("extensions/Shareview.lua")

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

local function assertNear(actual, expected, label)
  local eps = 0.001
  if math.abs((actual or 0) - expected) < eps then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected~" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

-- Test: parseUsernameDob
local user, d, m, y = parseUsernameDob("rosch100|01.01.1970")
assertEq(user, "rosch100", "parseUsernameDob.user")
assertEq(d, 9, "parseUsernameDob.day")
assertEq(m, 7, "parseUsernameDob.month")
assertEq(y, 1968, "parseUsernameDob.year")

local u2, d2 = parseUsernameDob("user")
assertEq(u2, "user", "parseUsernameDob.user-only.name")
assertEq(d2, nil, "parseUsernameDob.user-only.day=nil")

local u3, d3, m3, y3 = parseUsernameDob("max.mustermann|9/7/1968")
assertEq(u3, "max.mustermann", "parseUsernameDob.slash.user")
assertEq(d3, 9, "parseUsernameDob.slash.day")
assertEq(y3, 1968, "parseUsernameDob.slash.year")

-- Test: parseCurrencyValue (GBX → GBP)
local amount, native, raw = parseCurrencyValue("GBX|10.0000|99|1|.|,|6")
assertNear(amount, 2.47, "parseCurrencyValue.GBX.price.gbp")
assertEq(native, "GBX", "parseCurrencyValue.GBX.native")
assertNear(raw, 247.0, "parseCurrencyValue.GBX.raw")

local amount2, native2 = parseCurrencyValue("GBP|1000.00000000||0|.|,|")
assertNear(amount2, 634.79, "parseCurrencyValue.GBP.amount")
assertEq(native2, "GBP", "parseCurrencyValue.GBP.native")

local amount3, native3 = parseCurrencyValue("GBX|100000.0000||0|.|,|")
assertNear(amount3, 634.79, "parseCurrencyValue.GBX.value.gbp")
assertEq(native3, "GBX", "parseCurrencyValue.GBX.value.native")

-- Test: parseHoldings/parseTotalIndicativeValue gegen echtes HAR-HTML
local f = io.open("/tmp/holdings.html", "rb")
if not f then
  print("SKIP  /tmp/holdings.html nicht vorhanden — HTML-Parser-Test übersprungen.")
  os.exit(0)
end
local html = f:read("*all")
f:close()

local total, totalCcy = parseTotalIndicativeValue(html)
assertNear(total, 634.79, "parseTotalIndicativeValue.amount")
assertEq(totalCcy, "GBP", "parseTotalIndicativeValue.currency")

local secs = parseHoldings(html)
assertEq(#secs, 1, "parseHoldings.count")

local s = secs[1]
print()
print("Erste Position:")
for k, v in pairs(s) do
  print(string.format("  %-26s = %s", k, tostring(v)))
end

assertEq(s.name, "Example Corp (Aberdeen Share Account)", "parseHoldings.name")
assertEq(s.isin, "GB0000000001", "parseHoldings.isin")
assertEq(s.securityNumber, "1234567890", "parseHoldings.securityNumber")
assertEq(s.quantity, 257, "parseHoldings.quantity")
assertNear(s.price, 2.47, "parseHoldings.price")
assertNear(s.amount, 634.79, "parseHoldings.amount")
assertEq(s.currencyOfPrice, "GBP", "parseHoldings.currencyOfPrice")
assertEq(s.currencyOfOriginalAmount, "GBP", "parseHoldings.currencyOfOriginalAmount")

print()
print("ALL TESTS PASSED")
