--
-- Plugin Homepage: https://github.com/rosch100/Givve-MoneyMoney
-- Givve Prepaid — MoneyMoney Web Banking Extension
-- Portal: https://card.givve.com  API: https://www.givve.com
-- Dokumentation: README.md (Hub: https://github.com/rosch100/moneymoney-extensions)
-- API: https://moneymoney.app/api/webbanking/
--
-- Dateiname und services[] = "Givve Prepaid" (nicht "Givve Card": Kollision mit
-- MoneyMoney's eingebauter Kreditkarte — analog Amazon Bestellungen vs. Amazon-Kreditkarte).
--

WebBanking{
  version     = 1.00,
  url         = "https://card.givve.com",
  services    = {"Givve Prepaid"},
  description = "Givve Prepaid - E-Mail/Passwort + E-Mail-OTP (Benefit-Karte)"
}

local CONSTANTS = {
  baseUrl = "https://card.givve.com",
  authorizationsUrl = "https://www.givve.com/api/authorizations",
  vouchersUrl = "https://www.givve.com/api/voucher_owners/me/vouchers",
  meUrl = "https://www.givve.com/api/voucher_owners/me",
  clientId = "givve-card-web",
  acceptVersion = "v2",
  allowedHosts = { "card.givve.com", "www.givve.com" },
  serviceName = "Givve Prepaid",
  userAgent = "givve Card/8.1.1 (web)",
  vouchersPageSize = 25,
}

local CREDENTIAL_REJECTION_MARKERS = {
  "invalid email or password",
  "invalid credentials",
  "unauthorized",
  "falsche",
  "login failed",
}

local connection
local session = {}

function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function normalizeEmail(raw)
  return trim(tostring(raw or "")):lower()
end

function normalizeAccountKey(raw)
  return normalizeEmail(raw)
end

function last4FromVoucher(voucher)
  if type(voucher) ~= "table" or type(voucher.number) ~= "string" then
    return nil
  end
  return voucher.number:match("(%d%d%d%d)%s*$")
end

-- Sichtte Kartennummer (API liefert maskierte PAN, z. B. 521965******6363).
function accountNumberForVoucher(voucher)
  if type(voucher) ~= "table" or type(voucher.number) ~= "string" or voucher.number == "" then
    error("givve Card: Kartennummer für Kontonummer fehlt")
  end
  return voucher.number
end

-- Ein Konto: "givve"; mehrere: "givve ****6363".
function accountNameForVoucher(voucher, voucherCount)
  local count = voucherCount or 1
  if count <= 1 then
    return "givve"
  end
  local last4 = last4FromVoucher(voucher)
  if last4 then
    return "givve ****" .. last4
  end
  return "givve"
end

function isLegacyVoucherAccountNumber(accountNumber)
  if type(accountNumber) ~= "string" then
    return false
  end
  -- Neue Kontonummern sind maskierte PANs (enthalten *); Alt: givve.<voucherId>
  if accountNumber:find("%*", 1, true) then
    return false
  end
  return accountNumber:match("^givve%.[^%s]+$") ~= nil
end

function voucherIdFromLegacyAccountNumber(accountNumber)
  if not isLegacyVoucherAccountNumber(accountNumber) then
    return nil
  end
  return accountNumber:match("^givve%.(.+)$")
end

function findVoucherForAccountNumber(vouchers, accountNumber)
  if type(vouchers) ~= "table" or type(accountNumber) ~= "string" or accountNumber == "" then
    return nil
  end
  local legacyId = voucherIdFromLegacyAccountNumber(accountNumber)
  for i = 1, #vouchers do
    local voucher = vouchers[i]
    if type(voucher) == "table" then
      if legacyId and voucher.id == legacyId then
        return voucher
      end
      if type(voucher.number) == "string" and voucher.number == accountNumber then
        return voucher
      end
    end
  end
  return nil
end

-- Erste doppelte Anzeige-PAN in der Liste, sonst nil (kein stilles Map-Overwrite).
function firstDuplicateVoucherNumber(vouchers)
  if type(vouchers) ~= "table" then
    return nil
  end
  local seen = {}
  for i = 1, #vouchers do
    local voucher = vouchers[i]
    if type(voucher) == "table" and type(voucher.number) == "string" and voucher.number ~= "" then
      if seen[voucher.number] then
        return voucher.number
      end
      seen[voucher.number] = true
    end
  end
  return nil
end

function resolveVoucherIdForAccount(account)
  local accountNumber = account and account.accountNumber
  if type(accountNumber) ~= "string" or accountNumber == "" then
    return nil, "givve Card: Kontonummer fehlt."
  end
  local map = session.vouchersByAccountNumber
  if type(map) == "table" and type(map[accountNumber]) == "string" and map[accountNumber] ~= "" then
    return map[accountNumber], nil
  end
  local legacyId = voucherIdFromLegacyAccountNumber(accountNumber)
  if legacyId then
    return legacyId, nil
  end
  local vouchers = session.vouchersList
  if type(vouchers) ~= "table" then
    local err
    vouchers, err = fetchAllVouchers(session.accessToken)
    if not vouchers then
      return nil, err
    end
    session.vouchersList = vouchers
  end
  local voucher = findVoucherForAccountNumber(vouchers, accountNumber)
  if not voucher or type(voucher.id) ~= "string" or voucher.id == "" then
    return nil, "givve Card: Kein Voucher zur Kontonummer."
  end
  return voucher.id, nil
end

function vouchersListUrl(pageNumber)
  local page = pageNumber or 1
  return CONSTANTS.vouchersUrl
    .. "?page%5Bnumber%5D="
    .. tostring(page)
    .. "&page%5Bsize%5D="
    .. tostring(CONSTANTS.vouchersPageSize)
end

function vouchersFromListPayload(payload)
  local out = {}
  if type(payload) ~= "table" or type(payload.data) ~= "table" then
    return out
  end
  local data = payload.data
  for i = 1, #data do
    if type(data[i]) == "table" and type(data[i].id) == "string" and data[i].id ~= "" then
      out[#out + 1] = data[i]
    end
  end
  return out
end

function firstVoucherFromListPayload(payload)
  local list = vouchersFromListPayload(payload)
  return list[1]
end

function hostAllowed(urlOrHost)
  if type(urlOrHost) ~= "string" or urlOrHost == "" then
    return false
  end
  local host = urlOrHost
  if host:match("^https?://") then
    host = host:match("^https?://([^/?#]+)") or ""
  end
  host = host:lower():gsub(":443$", ""):gsub(":80$", "")
  for _, allowed in ipairs(CONSTANTS.allowedHosts) do
    if host == allowed then
      return true
    end
  end
  return false
end

function assertAllowedUrl(url)
  if type(url) ~= "string" or url == "" then
    error("givve Card: URL fehlt")
  end
  if not url:match("^https://") then
    error("givve Card: nur https:// erlaubt")
  end
  if not hostAllowed(url) then
    error("givve Card: Host nicht erlaubt: " .. tostring(url))
  end
  return url
end

function jsonEscapeString(value)
  if value == nil then
    return ""
  end
  return tostring(value)
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
end

function buildAuthorizationBody(identifier, password, otp)
  local parts = {
    '"identifier":"' .. jsonEscapeString(identifier) .. '"',
    '"password":"' .. jsonEscapeString(password) .. '"',
    '"accessors":["voucher_owner"]',
    '"client_id":"' .. jsonEscapeString(CONSTANTS.clientId) .. '"',
  }
  if type(otp) == "string" and trim(otp) ~= "" then
    parts[#parts + 1] = '"otp":"' .. jsonEscapeString(trim(otp)) .. '"'
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function parseJson(str)
  if type(str) ~= "string" or str == "" then
    return nil
  end
  local ok, result = pcall(function()
    return JSON(str):dictionary()
  end)
  if ok then
    return result
  end
  return nil
end

function classifyAuthPayload(payload)
  if type(payload) ~= "table" then
    return "unknown"
  end
  local data = payload.data
  if type(data) ~= "table" then
    data = payload
  end
  local status = data.auth_status
  if status == "otp_required" then
    return "mfa"
  end
  if status == "authenticated" and type(data.access_token) == "string" and data.access_token ~= "" then
    return "ok"
  end
  local errText = ""
  if type(payload.error) == "string" then
    errText = payload.error
  elseif type(payload.message) == "string" then
    errText = payload.message
  elseif type(data.message) == "string" then
    errText = data.message
  end
  local lower = errText:lower()
  for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
    if lower:find(marker, 1, true) then
      return "login_failed"
    end
  end
  return "unknown"
end

function classifyAuthJson(jsonText)
  local payload = parseJson(jsonText)
  if not payload then
    if type(jsonText) == "string" then
      local lower = jsonText:lower()
      if lower:find("otp_required", 1, true) then
        return "mfa"
      end
      if lower:find('"auth_status":"authenticated"', 1, true)
          or lower:find('"auth_status": "authenticated"', 1, true) then
        return "ok"
      end
      for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
        if lower:find(marker, 1, true) then
          return "login_failed"
        end
      end
    end
    return "unknown"
  end
  return classifyAuthPayload(payload)
end

function extractAccessToken(payload)
  if type(payload) ~= "table" then
    return nil
  end
  local data = payload.data
  if type(data) ~= "table" then
    data = payload
  end
  if type(data.access_token) == "string" and data.access_token ~= "" then
    return data.access_token
  end
  return nil
end

function extractRefreshToken(payload)
  if type(payload) ~= "table" then
    return nil
  end
  local data = payload.data
  if type(data) ~= "table" then
    data = payload
  end
  if type(data.refresh_token) == "string" and data.refresh_token ~= "" then
    return data.refresh_token
  end
  return nil
end

function emailMfaChallenge(message)
  return {
    title = "givve Card Authentifizierung",
    challenge = message or "Bitte den Code aus der givve-E-Mail eingeben.",
    label = "E-Mail-Code"
  }
end

function centsToAmount(cents)
  if type(cents) ~= "number" then
    return nil
  end
  return cents / 100
end

function parseBalanceFromVoucher(voucher)
  if type(voucher) ~= "table" then
    return nil
  end
  local balance = voucher.balance
  if type(balance) == "table" and type(balance.cents) == "number" then
    return centsToAmount(balance.cents)
  end
  return nil
end

function parseIsoDateTimeToTimestamp(iso)
  if type(iso) ~= "string" or iso == "" then
    return nil
  end
  local y, m, d, hh, mm, ss = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then
    y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    hh, mm, ss = 12, 0, 0
  end
  if not y then
    return nil
  end
  return os.time({
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(hh) or 12,
    min = tonumber(mm) or 0,
    sec = tonumber(ss) or 0,
  })
end

function collapseWhitespace(s)
  if type(s) ~= "string" then
    return ""
  end
  return trim((s:gsub("%s+", " ")))
end

function categoryIncludes(group, needle)
  if type(group) ~= "table" or type(group.category) ~= "table" then
    return false
  end
  for i = 1, #group.category do
    if group.category[i] == needle then
      return true
    end
  end
  return false
end

-- Wie MoneyMoney-Builtin „Givve Card“: nur gebuchte ok-Umsätze, keine Info/Status.
function transactionGroupIsImportable(group)
  if type(group) ~= "table" then
    return false
  end
  if categoryIncludes(group, "informational") or categoryIncludes(group, "status_change") then
    return false
  end
  local status = group.status
  if type(status) ~= "table" then
    return false
  end
  local hasOk = false
  for i = 1, #status do
    if status[i] == "invalid_amount" then
      return false
    end
    if status[i] == "ok" then
      hasOk = true
    end
  end
  return hasOk
end

function purposeFromMerchantDescription(merchantName, description)
  local desc = trim(tostring(description or ""))
  if desc == "" then
    return nil
  end
  if desc:find("\\", 1, true) then
    local parts = {}
    for part in desc:gmatch("([^\\]+)") do
      local p = trim(part)
      if p ~= "" then
        parts[#parts + 1] = p
      end
    end
    if #parts >= 2 then
      local startIdx = 1
      if type(merchantName) == "string" and merchantName ~= "" and parts[1] == merchantName then
        startIdx = 2
      end
      local rest = collapseWhitespace(table.concat(parts, " ", startIdx, #parts))
      if rest ~= "" then
        return rest
      end
    end
    return nil
  end
  if type(merchantName) == "string" and merchantName ~= "" then
    if desc:sub(1, #merchantName) == merchantName then
      local rest = collapseWhitespace(desc:sub(#merchantName + 1))
      if rest ~= "" then
        return rest
      end
    end
  end
  return nil
end

-- Builtin: name = "Load : LoadOrder : PLxxxx -", purpose = Hex-IDs danach.
function splitLoadDescription(description)
  local desc = trim(tostring(description or ""))
  if desc == "" then
    return nil, nil
  end
  local namePart, purposePart = desc:match("^(Load%s*:.-P[Ll]%d+%s*%-)%s*(.+)$")
  if namePart and purposePart then
    return trim(namePart), collapseWhitespace(purposePart)
  end
  return desc, nil
end

function transactionNameAndPurpose(group)
  if type(group) ~= "table" then
    return nil, nil
  end
  if categoryIncludes(group, "load") or categoryIncludes(group, "balance_adjustment") then
    if type(group.description) == "string" and trim(group.description) ~= "" then
      return splitLoadDescription(group.description)
    end
    return "Aufladung", nil
  end
  local merchant = nil
  if type(group.merchant_name) == "string" and trim(group.merchant_name) ~= "" then
    merchant = trim(group.merchant_name)
  end
  if merchant then
    return merchant, purposeFromMerchantDescription(merchant, group.description)
  end
  if type(group.description) == "string" and trim(group.description) ~= "" then
    return collapseWhitespace(group.description), nil
  end
  return nil, nil
end

function mapTransactionGroup(group)
  if type(group) ~= "table" or not transactionGroupIsImportable(group) then
    return nil
  end
  local amountTable = group.amount
  if type(amountTable) ~= "table" or type(amountTable.cents) ~= "number" then
    return nil
  end
  local amount = centsToAmount(amountTable.cents)
  local name, purpose = transactionNameAndPurpose(group)
  local bookingTs = parseIsoDateTimeToTimestamp(group.first_booked_at or group.latest_booked_at)
  local valueTs = parseIsoDateTimeToTimestamp(group.latest_booked_at or group.first_booked_at) or bookingTs
  if not name or amount == nil or not bookingTs then
    return nil
  end
  local currency = "EUR"
  if type(amountTable.currency) == "string" and amountTable.currency ~= "" then
    currency = amountTable.currency
  end
  local tx = {
    bookingDate = bookingTs,
    valueDate = valueTs,
    name = name,
    amount = amount,
    bookingKey = group.id,
    currency = currency,
    booked = true,
  }
  if type(purpose) == "string" and purpose ~= "" then
    tx.purpose = purpose
  end
  if type(group.mcc) == "table" and type(group.mcc.description) == "string" and trim(group.mcc.description) ~= "" then
    tx.bookingText = trim(group.mcc.description)
  elseif categoryIncludes(group, "load") then
    tx.bookingText = "Aufladung"
  elseif categoryIncludes(group, "purchase") then
    tx.bookingText = "Kauf"
  end
  return tx
end

function parseTransactionsFromGroupsPayload(payload, sinceTimestamp)
  local out = {}
  if type(payload) ~= "table" then
    return out
  end
  local data = payload.data
  if type(data) ~= "table" then
    return out
  end
  for i = 1, #data do
    local mapped = mapTransactionGroup(data[i])
    if mapped then
      if sinceTimestamp == nil or mapped.bookingDate >= sinceTimestamp then
        out[#out + 1] = mapped
      end
    end
  end
  return out
end

function parseOwnerNameFromMePayload(payload)
  if type(payload) ~= "table" or type(payload.data) ~= "table" then
    return nil
  end
  local data = payload.data
  if type(data.name) == "string" and trim(data.name) ~= "" then
    return trim(data.name)
  end
  local first = trim(tostring(data.first_name or ""))
  local last = trim(tostring(data.last_name or ""))
  local combined = collapseWhitespace(first .. " " .. last)
  if combined ~= "" then
    return combined
  end
  return nil
end

function fetchOwnerName(accessToken)
  local ok, raw = pcall(function()
    return apiRequest("GET", CONSTANTS.meUrl, nil, accessToken)
  end)
  if not ok or type(raw) ~= "string" then
    return nil
  end
  return parseOwnerNameFromMePayload(parseJson(raw))
end

function ensureOwnerName()
  if type(session.ownerName) == "string" and session.ownerName ~= "" then
    return session.ownerName
  end
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return nil
  end
  -- Optional: Login/Sync darf nicht scheitern, wenn nur der Inhabername fehlt.
  local name = fetchOwnerName(session.accessToken)
  if name then
    session.ownerName = name
  end
  return session.ownerName
end

function stripNonSerializableConnections(storage)
  if type(storage) ~= "table" then
    return
  end
  storage.connection = nil
  if type(storage.connectionsByAccount) == "table" then
    for _, entry in pairs(storage.connectionsByAccount) do
      if type(entry) == "table" then
        entry.connection = nil
      end
    end
  end
end

function getConnectionEntry(storage, accountKey)
  if not storage then
    return nil
  end
  storage.connectionsByAccount = storage.connectionsByAccount or {}
  local entry = storage.connectionsByAccount[accountKey]
  if not entry then
    entry = {}
    storage.connectionsByAccount[accountKey] = entry
  end
  return entry
end

function persistTokens(storage, accountKey, accessToken, refreshToken)
  local entry = getConnectionEntry(storage, accountKey)
  if not entry then
    return
  end
  entry.accessToken = accessToken
  entry.refreshToken = refreshToken
  storage.connectionAccountKey = accountKey
  storage.accessToken = accessToken
  storage.refreshToken = refreshToken
end

function restoreTokens(storage, accountKey)
  if not storage or accountKey == "" then
    return nil, nil
  end
  local entry = storage.connectionsByAccount and storage.connectionsByAccount[accountKey]
  local access = entry and entry.accessToken
  local refresh = entry and entry.refreshToken
  if (not access or access == "") and storage.connectionAccountKey == accountKey then
    access = storage.accessToken
    refresh = storage.refreshToken
  end
  if type(access) == "string" and access ~= "" then
    session.accessToken = access
    session.refreshToken = refresh
    return access, refresh
  end
  return nil, nil
end

function apiHeaders(accessToken)
  local headers = {
    ["Accept"] = "*/*",
    ["Accept-Language"] = "de,en-US;q=0.9,en;q=0.8",
    ["Accept-Version"] = CONSTANTS.acceptVersion,
    ["Content-Type"] = "application/json",
    ["Origin"] = CONSTANTS.baseUrl,
    ["Referer"] = CONSTANTS.baseUrl .. "/",
    ["User-Agent"] = CONSTANTS.userAgent,
  }
  if type(accessToken) == "string" and accessToken ~= "" then
    headers["Authorization"] = "Bearer " .. accessToken
  end
  return headers
end

function apiRequest(method, url, body, accessToken)
  assertAllowedUrl(url)
  local headers = apiHeaders(accessToken)
  return connection:request(method, url, body, body and "application/json" or nil, headers)
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == CONSTANTS.serviceName
end

function ensureConnection()
  if not connection then
    connection = Connection()
  end
  connection.language = "de-DE"
  connection.useragent = CONSTANTS.userAgent
end

function loginWithPassword(email, password, interactive)
  local body = buildAuthorizationBody(email, password, nil)
  local response = apiRequest("POST", CONSTANTS.authorizationsUrl, body, nil)
  local kind = classifyAuthJson(response)
  if kind == "login_failed" then
    return LoginFailed
  end
  if kind == "mfa" then
    if interactive == false then
      return "givve Card: E-Mail-OTP erforderlich — bitte interaktiv anmelden."
    end
    session.awaitingMfa = true
    session.pendingEmail = email
    session.pendingPassword = password
    return emailMfaChallenge(nil)
  end
  if kind == "ok" then
    local payload = parseJson(response)
    local access = extractAccessToken(payload)
    local refresh = extractRefreshToken(payload)
    if not access then
      return "givve Card: Login ohne access_token."
    end
    session.accessToken = access
    session.refreshToken = refresh
    session.awaitingMfa = false
    local storage = rawget(_G, "LocalStorage")
    if storage then
      persistTokens(storage, session.accountKey, access, refresh)
    end
    ensureOwnerName()
    return nil
  end
  if type(response) == "string" and #response > 0 then
    local lower = response:lower()
    for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
      if lower:find(marker, 1, true) then
        return LoginFailed
      end
    end
  end
  return "givve Card: Unerwartete Login-Antwort."
end

function submitEmailMfaCode(code)
  local email = session.pendingEmail
  local password = session.pendingPassword
  if not email or not password then
    session.awaitingMfa = false
    return "Anmeldesitzung für OTP abgelaufen. Bitte erneut anmelden."
  end
  if type(code) ~= "string" or trim(code) == "" then
    session.awaitingMfa = true
    return emailMfaChallenge("Bitte den E-Mail-Code eingeben.")
  end
  local body = buildAuthorizationBody(email, password, code)
  local response = apiRequest("POST", CONSTANTS.authorizationsUrl, body, nil)
  local kind = classifyAuthJson(response)
  if kind == "mfa" then
    session.awaitingMfa = true
    return emailMfaChallenge("Code ungültig oder abgelaufen. Bitte neuen Code prüfen.")
  end
  if kind == "login_failed" then
    session.awaitingMfa = false
    session.pendingEmail = nil
    session.pendingPassword = nil
    return LoginFailed
  end
  if kind == "ok" then
    local payload = parseJson(response)
    local access = extractAccessToken(payload)
    local refresh = extractRefreshToken(payload)
    if not access then
      return "givve Card: OTP-Login ohne access_token."
    end
    session.accessToken = access
    session.refreshToken = refresh
    session.awaitingMfa = false
    session.pendingEmail = nil
    session.pendingPassword = nil
    local storage = rawget(_G, "LocalStorage")
    if storage then
      persistTokens(storage, session.accountKey, access, refresh)
    end
    ensureOwnerName()
    return nil
  end
  return "givve Card: Unerwartete OTP-Antwort."
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local email = normalizeEmail(credentials and credentials[1])
  local password = credentials and credentials[2] or ""
  local storage = rawget(_G, "LocalStorage")

  if step == 1 then
    if email == "" then
      return "Bitte die givve-E-Mail-Adresse eingeben."
    end
    session = { accountKey = email }
    if storage then
      stripNonSerializableConnections(storage)
      getConnectionEntry(storage, email)
      storage.connectionAccountKey = email
    end
    ensureConnection()

    local access = select(1, restoreTokens(storage, email))
    if access then
      session.accessToken = access
      local vouchers = fetchAllVouchers(access)
      if vouchers then
        session.vouchersList = vouchers
        ensureOwnerName()
        return nil
      end
      session.accessToken = nil
    end

    if password == "" then
      return "Bitte das givve-Passwort eingeben."
    end
    return loginWithPassword(email, password, interactive)
  end

  ensureConnection()
  if session.awaitingMfa then
    -- Folgeschritt: MoneyMoney liefert den Challenge-Wert als credentials[1]
    return submitEmailMfaCode(credentials and credentials[1])
  end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end

function isoTimestampForApi(unixTs)
  if type(unixTs) ~= "number" then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%S.000", unixTs)
end

function transactionGroupsUrl(voucherId, sinceTimestamp)
  local url = CONSTANTS.vouchersUrl
    .. "/"
    .. voucherId
    .. "/transaction_groups?page%5Bnumber%5D=1&page%5Bsize%5D=250&skip_meta_totals=true"
  local iso = isoTimestampForApi(sinceTimestamp)
  if iso then
    url = url .. "&filter%5Blatest_booked_at%5D%5B%24gte%5D=" .. MM.urlencode(iso)
  end
  return url
end

function fetchVouchersPage(accessToken, pageNumber)
  local raw = apiRequest("GET", vouchersListUrl(pageNumber), nil, accessToken)
  return parseJson(raw)
end

function fetchAllVouchers(accessToken)
  local all = {}
  local page = 1
  local totalPages = 1
  while page <= totalPages do
    local payload = fetchVouchersPage(accessToken, page)
    if not payload then
      return nil, "givve Card: Kontenliste konnte nicht gelesen werden."
    end
    local pageVouchers = vouchersFromListPayload(payload)
    for i = 1, #pageVouchers do
      all[#all + 1] = pageVouchers[i]
    end
    local meta = payload.meta
    if type(meta) == "table" and type(meta.total_pages) == "number" and meta.total_pages > 0 then
      totalPages = meta.total_pages
    else
      totalPages = page
    end
    page = page + 1
    if page > 50 then
      return nil, "givve Card: Zu viele Voucher-Seiten."
    end
  end
  return all
end

function ListAccounts(knownAccounts)
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "givve Card: Session fehlt - bitte anmelden."
  end
  ensureConnection()
  local vouchers = session.vouchersList
  if type(vouchers) ~= "table" then
    local err
    vouchers, err = fetchAllVouchers(session.accessToken)
    if not vouchers then
      return err
    end
    session.vouchersList = vouchers
  end
  if #vouchers == 0 then
    return "givve Card: Keine Karte (Voucher) im Konto gefunden."
  end
  local duplicateNumber = firstDuplicateVoucherNumber(vouchers)
  if duplicateNumber then
    return "givve Card: Mehrere Karten mit derselben Nummer (" .. duplicateNumber .. ")."
  end
  session.vouchersByAccountNumber = {}
  local owner = ensureOwnerName()
  local accounts = {}
  for i = 1, #vouchers do
    local voucher = vouchers[i]
    local balance = parseBalanceFromVoucher(voucher)
    if balance == nil then
      return "givve Card: Saldo konnte nicht gelesen werden."
    end
    local number = accountNumberForVoucher(voucher)
    if type(voucher.id) ~= "string" or voucher.id == "" then
      return "givve Card: Voucher-ID fehlt."
    end
    session.vouchersByAccountNumber[number] = voucher.id
    local account = {
      name = accountNameForVoucher(voucher, #vouchers),
      accountNumber = number,
      currency = (type(voucher.currency) == "string" and voucher.currency ~= "" and voucher.currency) or "EUR",
      balance = balance,
      type = AccountTypeCreditCard,
    }
    if type(owner) == "string" and owner ~= "" then
      account.owner = owner
    end
    accounts[#accounts + 1] = account
  end
  return accounts
end

function RefreshAccount(account, since)
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "givve Card: Session fehlt - bitte anmelden."
  end
  ensureConnection()
  local voucherId, resolveErr = resolveVoucherIdForAccount(account)
  if not voucherId then
    return resolveErr
  end

  local voucherRaw = apiRequest("GET", CONSTANTS.vouchersUrl .. "/" .. voucherId, nil, session.accessToken)
  local voucherPayload = parseJson(voucherRaw)
  local voucher = voucherPayload and voucherPayload.data or nil
  local balance = parseBalanceFromVoucher(voucher)
  if balance == nil then
    return "givve Card: Saldo konnte nicht gelesen werden."
  end

  local txUrl = transactionGroupsUrl(voucherId, since)
  local txRaw = apiRequest("GET", txUrl, nil, session.accessToken)
  local txPayload = parseJson(txRaw)
  if not txPayload then
    return "givve Card: Umsätze konnten nicht gelesen werden."
  end
  local txs = parseTransactionsFromGroupsPayload(txPayload, since)
  return {
    balance = balance,
    transactions = txs,
  }
end

function EndSession()
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
  end
  session.pendingPassword = nil
  session.pendingEmail = nil
  session.awaitingMfa = false
  -- Tokens in Map behalten für Multi-Login / Neustart
  connection = nil
end

-- SIGNATURE: MCwCFFfE99f4qLwmP/cKkesiouwu5zzIAhQZlkHmxRi5z+h8akjFkgmwHRr3gw==
