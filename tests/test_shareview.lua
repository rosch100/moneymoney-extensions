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

-- Test: parseUsernameDob (Pipe-Komfort-Pfad)
local user, d, m, y = parseUsernameDob("rosch100|01.01.1970")
assertEq(user, "rosch100", "parseUsernameDob.user")
assertEq(d, 1, "parseUsernameDob.day")
assertEq(m, 1, "parseUsernameDob.month")
assertEq(y, 1970, "parseUsernameDob.year")

-- Username ohne Pipe → DOB wird per Multi-Step nachgefragt
local u2, d2 = parseUsernameDob("user")
assertEq(u2, "user", "parseUsernameDob.user-only.name")
assertEq(d2, nil, "parseUsernameDob.user-only.day=nil")

local u3, d3, m3, y3 = parseUsernameDob("rosch100|1/1/1970")
assertEq(u3, "rosch100", "parseUsernameDob.slash.user")
assertEq(d3, 1, "parseUsernameDob.slash.day")
assertEq(y3, 1970, "parseUsernameDob.slash.year")

local u4, d4 = parseUsernameDob("name|invalid")
assertEq(u4, "name", "parseUsernameDob.invalid.user")
assertEq(d4, nil, "parseUsernameDob.invalid.day=nil")

-- Test: parseDobString (standalone, für Multi-Step-Eingabe)
local dx, mx, yx = parseDobString("01.01.1970")
assertEq(dx, 1, "parseDobString.dotted.day")
assertEq(mx, 1, "parseDobString.dotted.month")
assertEq(yx, 1970, "parseDobString.dotted.year")

local ds, ms, ys = parseDobString("  1/1/1970  ")
assertEq(ds, 1, "parseDobString.trim+slash.day")
assertEq(ys, 1970, "parseDobString.trim+slash.year")

local dh, mh, yh = parseDobString("1-1-1970")
assertEq(dh, 1, "parseDobString.dash.day")
assertEq(yh, 1970, "parseDobString.dash.year")

local dn = parseDobString("garbage")
assertEq(dn, nil, "parseDobString.garbage.day=nil")

local dnil = parseDobString(nil)
assertEq(dnil, nil, "parseDobString.nil.day=nil")

-- Test: isValidDob (Range-Check)
assertEq(isValidDob(1, 1, 1970), true, "isValidDob.normal")
assertEq(isValidDob(31, 12, 2099), true, "isValidDob.edge.upper")
assertEq(isValidDob(1, 1, 1900), true, "isValidDob.edge.lower")
assertEq(isValidDob(0, 1, 1970), false, "isValidDob.day=0")
assertEq(isValidDob(32, 1, 1970), false, "isValidDob.day=32")
assertEq(isValidDob(1, 0, 1970), false, "isValidDob.month=0")
assertEq(isValidDob(1, 13, 1970), false, "isValidDob.month=13")
assertEq(isValidDob(1, 1, 1899), false, "isValidDob.year=1899")
assertEq(isValidDob(1, 1, 2101), false, "isValidDob.year=2101")
assertEq(isValidDob(nil, 1, 1970), false, "isValidDob.nil.day")

-- Test: parseCurrencyValue (GBX → GBP)
local amount, native, raw = parseCurrencyValue("GBX|247.0000|99|1|.|,|6")
assertNear(amount, 2.47, "parseCurrencyValue.GBX.price.gbp")
assertEq(native, "GBX", "parseCurrencyValue.GBX.native")
assertNear(raw, 247.0, "parseCurrencyValue.GBX.raw")

local amount2, native2 = parseCurrencyValue("GBP|1000.00000000||0|.|,|")
assertNear(amount2, 1000.00, "parseCurrencyValue.GBP.amount")
assertEq(native2, "GBP", "parseCurrencyValue.GBP.native")

local amount3, native3 = parseCurrencyValue("GBX|100000.0000||0|.|,|")
assertNear(amount3, 1000.00, "parseCurrencyValue.GBX.value.gbp")
assertEq(native3, "GBX", "parseCurrencyValue.GBX.value.native")

-- Test: parseHoldings/parseTotalIndicativeValue gegen echtes HAR-HTML
do
  -- Inline Fixture: bewusst minimal, aber so aufgebaut, dass die Regex/XPath-Matches
  -- in `parseTotalIndicativeValue` und `parseHoldingRow` exakt greifen.
  local html = [[
<div id="TotalIndicativeValue"><span class="currencyChange">GBP|1000.00000000||0|.|,|</span></div>
<table>
  <tr class="summaryDataItemRow" id="row1">
    <td headers="holding"><strong>Example Corp (Share Account)</strong><br/>Shareholder Ref No:1234567890</td>
    <td headers="quantity"><bdo>100</bdo></td>
    <td headers="price"><span class="original">GBX|1000.0000|99|1|.|,|6</span></td>
    <td headers="value"><span class="original">GBP|1000.00000000||0|.|,|</span></td>
    externalid=GB0000000001
  </tr>
</table>
]]

  local total, totalCcy = parseTotalIndicativeValue(html)
  assertNear(total, 1000.00, "parseTotalIndicativeValue.amount")
  assertEq(totalCcy, "GBP", "parseTotalIndicativeValue.currency")

  local secs = parseHoldings(html)
  assertEq(#secs, 1, "parseHoldings.count")

  local s = secs[1]
  print()
  print("Erste Position:")
  for k, v in pairs(s) do
    print(string.format("  %-26s = %s", k, tostring(v)))
  end

  assertEq(s.name, "Example Corp (Share Account)", "parseHoldings.name")
  assertEq(s.isin, "GB0000000001", "parseHoldings.isin")
  assertEq(s.securityNumber, "1234567890", "parseHoldings.securityNumber")
  assertEq(s.quantity, 100, "parseHoldings.quantity")
  assertNear(s.price, 10.00, "parseHoldings.price")
  assertNear(s.amount, 1000.00, "parseHoldings.amount")
  assertEq(s.currencyOfPrice, "GBP", "parseHoldings.currencyOfPrice")
  assertEq(s.currencyOfOriginalAmount, "GBP", "parseHoldings.currencyOfOriginalAmount")
end

-- Additional edge cases (Coverage)
do
  -- parseCurrencyValue: nil / ungültig
  local a, b, c = parseCurrencyValue(nil)
  assertEq(a, nil, "parseCurrencyValue.nil.amount")
  assertEq(b, nil, "parseCurrencyValue.nil.currency")
  assertEq(c, nil, "parseCurrencyValue.nil.nativeAmount")

  local a2, b2, c2 = parseCurrencyValue("NOTACCUR|abc")
  assertEq(a2, nil, "parseCurrencyValue.invalid.amount")
  assertEq(b2, nil, "parseCurrencyValue.invalid.currency")
  assertEq(c2, nil, "parseCurrencyValue.invalid.nativeAmount")

  -- parseHoldings: nil input -> leere Liste
  local secs = parseHoldings(nil)
  assertEq(#secs, 0, "parseHoldings.nil=empty")

  -- parseHoldingRow: invalid ISIN (wrong format) -> empty string
  local html2 = [[
<table>
  <tr class="summaryDataItemRow" id="row2">
    <td headers="holding"><strong>Example Position</strong><br/>Shareholder Ref No:REF-123</td>
    <td headers="quantity"><bdo>1</bdo></td>
    <td headers="price"><span class="original">GBX|100.0000|99|1|.|,|6</span></td>
    <td headers="value"><span class="original">GBP|1.00||0|.|,|</span></td>
    externalid=INVALID_ISIN
  </tr>
</table>
]]
  local secs2 = parseHoldings(html2)
  assertEq(#secs2, 1, "parseHoldings.count.invalid-isin")
  assertEq(secs2[1].name, "Example Position", "parseHoldingRow.htmlDecode.name")
  assertEq(secs2[1].isin, "", "parseHoldingRow.invalid-isin=empty")
end

-- extractLoginError / isLoggedInPage / isMfaPage
do
  local function nodeWithText(text)
    return { text = function() return text end }
  end

  local htmlNode = {
    xpath = function(_, xp)
      if xp:find("ErrorMessage", 1, true) then
        return nodeWithText("  Something went wrong  ")
      end
      return nil
    end
  }

  local err = extractLoginError(htmlNode)
  assertEq(err, "Something went wrong", "extractLoginError.trim")

  local htmlNode2 = {
    xpath = function(_, xp)
      -- return only whitespace -> should be ignored, then return nil
      return nodeWithText("   ")
    end
  }
  local err2 = extractLoginError(htmlNode2)
  assertEq(err2, nil, "extractLoginError.whitespace=nil")

  assertEq(isLoggedInPage('noTotal but id="TotalIndicativeValue"'), true, "isLoggedInPage.TotalIndicativeValue")
  assertEq(isLoggedInPage("My Holdings Summary"), true, "isLoggedInPage.MyHoldingsSummary")
  assertEq(isMfaPage("Bitte authentication code eingeben"), true, "isMfaPage.authentication-code")
  assertEq(isMfaPage(nil), false, "isMfaPage.nil=false")
end

print()
print("ALL TESTS PASSED")
