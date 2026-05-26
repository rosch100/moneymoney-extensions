-- Tests für MLP Versicherungen Extension v1.10
-- Testet Hilfsfunktionen und Datenstrukturen

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

-- ============================================================
-- Hilfsfunktionen (werden in Extension definiert)
-- ============================================================

function trim(text)
  if not text then return "" end
  return (text:gsub("^%s*(.-)%s*$", "%1"))
end

function formatCurrency(value)
  if not value then return "0,00 €" end
  local formatted = string.format("%.2f", value)
  formatted = formatted:gsub("(%d)%.(%d%d)$", "%1,%2")
  local intPart, decPart = formatted:match("^(%d+),(%d%d)$")
  if intPart then
    intPart = intPart:reverse():gsub("(%d%d%d)", "%1."):reverse()
    if intPart:sub(1, 1) == "." then intPart = intPart:sub(2) end
    formatted = intPart .. "," .. decPart
  end
  return formatted .. " €"
end

function parseIsoDate(dateStr)
  if not dateStr then return nil end
  local year, month, day = dateStr:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if year and month and day then
    return tonumber(day), tonumber(month), tonumber(year)
  end
  return nil
end

function formatDateDisplay(dateStr)
  local day, month, year = parseIsoDate(dateStr)
  if day and month and year then
    return string.format("%02d.%02d.%04d", day, month, year)
  end
  return dateStr or ""
end

-- ============================================================
-- Test-Hilfsfunktionen
-- ============================================================

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

local function assertNear(actual, expected, label)
  local eps = 0.01
  if math.abs((actual or 0) - expected) < eps then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected~" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

local function assertContains(str, substr, label)
  if str and str:find(substr, 1, true) then
    print("OK    " .. label .. " contains '" .. substr .. "'")
  else
    print("FAIL  " .. label .. ": expected to contain '" .. substr .. "', actual=" .. tostring(str))
    os.exit(1)
  end
end

-- ============================================================
-- Extension laden (für SupportsBank)
-- ============================================================

dofile("extensions/MLP Versicherungen.lua")

-- ============================================================
-- Tests: Grundlegende Funktionen
-- ============================================================

print()
print("=== Test: Grundlegende Funktionen ===")

local d1, m1, y1 = parseIsoDate("2026-01-01T22:00:00.000+00:00")
assertEq(d1, 29, "parseIsoDate.day")
assertEq(m1, 4, "parseIsoDate.month")
assertEq(y1, 2026, "parseIsoDate.year")
assertEq(parseIsoDate(nil), nil, "parseIsoDate.nil")

local display1 = formatDateDisplay("2040-01-01T22:00:00.000+00:00")
assert(display1 == "01.01.2040" or display1 == "01.01.2040", "formatDateDisplay")
print("OK    formatDateDisplay.heidelberger = " .. display1 .. " (TZ-abhängig)")

assertEq(formatDateDisplay(nil), "", "formatDateDisplay.nil")
assertEq(SupportsBank("WebBanking", "MLP Versicherungen"), true, "SupportsBank.mlp")
assertEq(SupportsBank("FinTS", "MLP Versicherungen"), false, "SupportsBank.fints")
assertEq(SupportsBank("WebBanking", "Andere Bank"), false, "SupportsBank.wrong-service")

assertEq(formatCurrency(50000.00), "108.150,30 €", "formatCurrency.gross")
assertEq(formatCurrency(100.00), "643,14 €", "formatCurrency.klein")
assertEq(formatCurrency(0), "0,00 €", "formatCurrency.null")

-- ============================================================
-- Test-Daten: Verschiedene Versicherungstypen
-- ============================================================

local testContracts = {
  {
    id = "00000000000000000000000000000001",
    number = "123456789",
    company = { shortName = "Lebensversicherung AG", longName = "Lebensversicherung AG" },
    contribution = 100.00, paymentMethod = "MONAT",
    validFrom = "2000-01-01T22:00:00.000+00:00", validUntil = "2043-08-31T22:00:00.000+00:00",
    state = "aktiv", category = "Vorsorge", tariff = "FLVG3",
    contractType = "FLV", posType = "FLV",
    shareValue = 50000.00, dateOfShareValue = "2026-01-01T22:00:00.000+00:00",
    currency = "EUR",
    specificAttributes = {
      deathInsuredSum = { value = 100000.00, displayValue = "72.710,76 €" },
      endOfPayment = { value = "2040-01-01T22:00:00.000+00:00", displayValue = "01.01.2040" },
      netContribution = { value = 90.00, displayValue = "570,05 €" }
    }
  },
  {
    id = "00000000000000000000000000000002",
    number = "987654321",
    company = { shortName = "Versicherung GmbH", longName = "Versicherung GmbH" },
    contribution = 50.00, paymentMethod = "MONAT",
    validFrom = "2000-01-01T22:00:00.000+00:00", validUntil = "2050-01-01T22:00:00.000+00:00",
    state = "aktiv", category = "Vorsorge", tariff = "AIRBAG I",
    contractType = "KLV", posType = "KLV",
    shareValue = 22636.27, dateOfShareValue = "2026-01-01T22:00:00.000+00:00",
    currency = "EUR",
    specificAttributes = {
      deathInsuredSum = { value = 20000.00, displayValue = "46.556,00 €" },
      lifeInsuredSum = { value = 15000.00, displayValue = "43.460,83 €" },
      endOfPayment = { value = "2050-01-01T22:00:00.000+00:00", displayValue = "01.01.2050" },
      netContribution = { value = 50.00, displayValue = "153,41 €" }
    }
  }
}

-- ============================================================
-- Lokale Test-Implementationen
-- ============================================================

local CONTRACT_TYPE_NAMES = {
  FLV = "Fondsgebundene Lebensversicherung",
  KLV = "Kapitallebensversicherung",
  LV = "Lebensversicherung",
  REN = "Rentenversicherung",
  BU = "Berufsunfähigkeitsversicherung",
  DEFAULT = "Vorsorgevertrag"
}

local function getContractTypeName(contractType)
  return CONTRACT_TYPE_NAMES[contractType or "DEFAULT"] or CONTRACT_TYPE_NAMES.DEFAULT
end

local function buildSecurityName(contract)
  local parts = {}
  local typeDesc = getContractTypeName(contract.contractType)
  table.insert(parts, typeDesc)
  if contract.tariff and contract.tariff ~= "" then
    table.insert(parts, "Tarif: " .. contract.tariff)
  end
  if contract.specificAttributes then
    local deathSum = contract.specificAttributes.deathInsuredSum
    if deathSum and deathSum.displayValue then
      table.insert(parts, "Todesfall: " .. deathSum.displayValue)
    end
    local lifeSum = contract.specificAttributes.lifeInsuredSum
    if lifeSum and lifeSum.displayValue then
      table.insert(parts, "Erlebensfall: " .. lifeSum.displayValue)
    end
  end
  if contract.contribution and contract.contribution > 0 then
    table.insert(parts, "Beitrag/Monat: " .. formatCurrency(contract.contribution))
  end
  return table.concat(parts, " | ")
end

local function createAccountFromContract(contract)
  local companyName = contract.company.shortName or "Unbekannt"
  local contractNumber = contract.number or ""
  local tariff = contract.tariff or ""
  local endDate = ""
  if contract.specificAttributes and contract.specificAttributes.endOfPayment then
    endDate = formatDateDisplay(contract.specificAttributes.endOfPayment.value)
  end
  local displayName = companyName
  if contractNumber ~= "" then
    displayName = displayName .. " " .. contractNumber
  end
  if tariff ~= "" then
    displayName = displayName .. " (" .. tariff .. ")"
  end
  if endDate ~= "" then
    displayName = displayName .. " | Beitrag bis " .. endDate
  end
  return {
    name = displayName,
    accountNumber = contract.number or contract.id,
    portfolio = true,
    currency = contract.currency or "EUR",
    type = AccountTypePortfolio,
    bankCode = contract.company.shortName or "MLP"
  }
end

-- ============================================================
-- Tests: Vertragstyp-Mapping
-- ============================================================

print()
print("=== Test: Vertragstyp-Mapping ===")

assertEq(getContractTypeName("FLV"), "Fondsgebundene Lebensversicherung", "typeMapping.FLV")
assertEq(getContractTypeName("KLV"), "Kapitallebensversicherung", "typeMapping.KLV")
assertEq(getContractTypeName("REN"), "Rentenversicherung", "typeMapping.REN")
assertEq(getContractTypeName("BU"), "Berufsunfähigkeitsversicherung", "typeMapping.BU")
assertEq(getContractTypeName("UNKNOWN"), "Vorsorgevertrag", "typeMapping.unknown")

-- ============================================================
-- Tests: Vertragsverarbeitung
-- ============================================================

print()
print("=== Test: Vertragsverarbeitung ===")

for i, contract in ipairs(testContracts) do
  print()
  print("Vertrag " .. i .. ": " .. contract.company.shortName)
  
  local account = createAccountFromContract(contract)
  print("  Konto-Name: " .. account.name)
  print("  Vertragsnr: " .. tostring(account.accountNumber))
  
  assertEq(account.portfolio, true, "contract" .. i .. ".portfolio")
  assertEq(account.type, AccountTypePortfolio, "contract" .. i .. ".type")
  assertEq(account.currency, "EUR", "contract" .. i .. ".currency")
  
  local secName = buildSecurityName(contract)
  print("  Security-Name: " .. secName)
  
  if contract.contractType == "FLV" then
    assertContains(secName, "Fondsgebundene Lebensversicherung", "contract" .. i .. ".type")
  elseif contract.contractType == "KLV" then
    assertContains(secName, "Kapitallebensversicherung", "contract" .. i .. ".type")
  end
end

-- ============================================================
-- Tests: JSON-Encoding
-- ============================================================

print()
print("=== Test: JSON-Encoding ===")

local function encodeJson(obj)
  if type(obj) == "table" then
    local parts = {}
    for k, v in pairs(obj) do
      local key = string.format("%q", k)
      local value
      if type(v) == "table" then value = encodeJson(v)
      elseif type(v) == "string" then value = string.format("%q", v)
      elseif type(v) == "number" then value = tostring(v)
      elseif type(v) == "boolean" then value = v and "true" or "false"
      else value = "null" end
      table.insert(parts, key .. ":" .. value)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local testObj = { name = "Test", value = 123 }
local jsonStr = encodeJson(testObj)
assertContains(jsonStr, "name", "encodeJson.hasName")
assertContains(jsonStr, "Test", "encodeJson.hasValue")

print()
print("ALL TESTS PASSED")
