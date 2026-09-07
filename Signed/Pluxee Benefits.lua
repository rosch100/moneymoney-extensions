--
-- Plugin Homepage: https://github.com/rosch100/Pluxee-MoneyMoney
-- Pluxee Benefits — MoneyMoney Web Banking Extension
-- Portal: https://consumers.pluxee.de  OIDC: https://connect.pluxee.app
-- API: https://api.pluxee.app/gl/eva/bff
-- Dokumentation: README.md (Hub: https://github.com/rosch100/moneymoney-extensions)
-- API: https://moneymoney.app/api/webbanking/
--
-- Dateiname und services[] = "Pluxee Benefits" (Title Case, identisch; Marke +
-- Produkttyp wie "Givve Prepaid" / "Amazon Bestellungen" — nicht nur "Pluxee").
--

WebBanking{
  version     = 1.00,
  url         = "https://consumers.pluxee.de",
  services    = {"Pluxee Benefits"},
  description = "Pluxee Benefits Card — E-Mail/OTP (Passwort nur wenn Formular)"
}

local CONSTANTS = {
  portalUrl = "https://consumers.pluxee.de",
  oidcAuthority = "https://connect.pluxee.app/op",
  authorizeUrl = "https://connect.pluxee.app/op/oidc/auth",
  tokenUrl = "https://connect.pluxee.app/op/oidc/token",
  redirectUri = "https://consumers.pluxee.de/oidc/callback",
  clientId = "bf400a61-2659-4269-9363-ebd2029adaa2",
  scope = "openid profile email offline_access",
  bffBase = "https://api.pluxee.app/gl/eva/bff",
  country = "de",
  -- Öffentlicher SPA-Key (Live-Bundle consumers.pluxee.de, 2026-09-05)
  apimSubscriptionKey = "f2b9fb99716f43a38b01867a0aeaf687",
  allowedHosts = {
    "consumers.pluxee.de",
    "connect.pluxee.app",
    "api.pluxee.app",
  },
  serviceName = "Pluxee Benefits",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
  transactionLimit = 99,
  -- SPA-API ohne Offset; Folge-Seiten per toDate (YYYY-MM-DD).
  transactionMaxPages = 50,
}

-- Connect-/Token-Antworten (OIDC + UI-HTML); analog givve Card.
local CREDENTIAL_REJECTION_MARKERS = {
  "invalid_grant",
  "invalid_client",
  "access_denied",
  "invalid credentials",
  "invalid email",
  "invalid password",
  "unauthorized",
  "login failed",
  "falsche",
  "ungültig",
  "ungueltig",
  "incorrect",
  "wrong password",
  "wrong code",
  "otp invalid",
  "code invalid",
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
    error("Pluxee: URL fehlt")
  end
  if not url:match("^https://") then
    error("Pluxee: nur https:// erlaubt")
  end
  if not hostAllowed(url) then
    error("Pluxee: Host nicht erlaubt: " .. tostring(url))
  end
  return url
end

-- Compact SHA-256 + base64url for PKCE (MoneyMoney has no built-in digest).
local function bit_band(a, b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 and bb == 1 then
      r = r + m
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function bit_bor(a, b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa == 1 or bb == 1 then
      r = r + m
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function bit_bxor(a, b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local aa = a % 2
    local bb = b % 2
    if aa ~= bb then
      r = r + m
    end
    a = (a - aa) / 2
    b = (b - bb) / 2
    m = m * 2
  end
  return r
end

local function bit_bnot(a)
  return 4294967295 - a
end

local function bit_rshift(a, n)
  return math.floor(a / (2 ^ n)) % 4294967296
end

local function bit_lshift(a, n)
  return (a * (2 ^ n)) % 4294967296
end

local function bit_ror(x, n)
  return bit_bor(bit_rshift(x, n), bit_lshift(x, 32 - n))
end

function sha256(msg)
  local k = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local bytes = { string.byte(msg, 1, #msg) }
  local bitLen = #bytes * 8
  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end
  for i = 7, 0, -1 do
    bytes[#bytes + 1] = math.floor(bitLen / (2 ^ (8 * i))) % 256
  end
  for i = 1, #bytes, 64 do
    local w = {}
    for j = 0, 15 do
      local b = i + j * 4
      w[j] = bytes[b] * 16777216 + bytes[b + 1] * 65536 + bytes[b + 2] * 256 + bytes[b + 3]
    end
    for j = 16, 63 do
      local s0 = bit_bxor(bit_bxor(bit_ror(w[j - 15], 7), bit_ror(w[j - 15], 18)), bit_rshift(w[j - 15], 3))
      local s1 = bit_bxor(bit_bxor(bit_ror(w[j - 2], 17), bit_ror(w[j - 2], 19)), bit_rshift(w[j - 2], 10))
      w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % 4294967296
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for j = 0, 63 do
      local S1 = bit_bxor(bit_bxor(bit_ror(e, 6), bit_ror(e, 11)), bit_ror(e, 25))
      local ch = bit_bxor(bit_band(e, f), bit_band(bit_bnot(e), g))
      local temp1 = (h + S1 + ch + k[j + 1] + w[j]) % 4294967296
      local S0 = bit_bxor(bit_bxor(bit_ror(a, 2), bit_ror(a, 13)), bit_ror(a, 22))
      local maj = bit_bxor(bit_bxor(bit_band(a, b), bit_band(a, c)), bit_band(b, c))
      local temp2 = (S0 + maj) % 4294967296
      h = g
      g = f
      f = e
      e = (d + temp1) % 4294967296
      d = c
      c = b
      b = a
      a = (temp1 + temp2) % 4294967296
    end
    h0 = (h0 + a) % 4294967296
    h1 = (h1 + b) % 4294967296
    h2 = (h2 + c) % 4294967296
    h3 = (h3 + d) % 4294967296
    h4 = (h4 + e) % 4294967296
    h5 = (h5 + f) % 4294967296
    h6 = (h6 + g) % 4294967296
    h7 = (h7 + h) % 4294967296
  end
  local out = {}
  for _, v in ipairs({ h0, h1, h2, h3, h4, h5, h6, h7 }) do
    for i = 3, 0, -1 do
      out[#out + 1] = string.char(math.floor(v / (256 ^ i)) % 256)
    end
  end
  return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64urlEncode(raw)
  local t = {}
  for i = 1, #raw, 3 do
    local a, b, c = string.byte(raw, i, i + 2)
    b = b or 0
    c = c or 0
    local n = a * 65536 + b * 256 + c
    local n1 = math.floor(n / 262144) % 64
    local n2 = math.floor(n / 4096) % 64
    local n3 = math.floor(n / 64) % 64
    local n4 = n % 64
    t[#t + 1] = B64:sub(n1 + 1, n1 + 1)
    t[#t + 1] = B64:sub(n2 + 1, n2 + 1)
    if i + 1 <= #raw then
      t[#t + 1] = B64:sub(n3 + 1, n3 + 1)
    end
    if i + 2 <= #raw then
      t[#t + 1] = B64:sub(n4 + 1, n4 + 1)
    end
  end
  return table.concat(t):gsub("+", "-"):gsub("/", "_")
end

function pkcePair()
  local raw = {}
  for i = 1, 32 do
    raw[i] = string.char(math.random(0, 255))
  end
  local verifier = base64urlEncode(table.concat(raw))
  local challenge = base64urlEncode(sha256(verifier))
  return verifier, challenge
end

function urlEncode(s)
  if MM and MM.urlencode then
    return MM.urlencode(tostring(s))
  end
  return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

function buildAuthorizeUrl(codeChallenge, state)
  return CONSTANTS.authorizeUrl
    .. "?client_id="
    .. urlEncode(CONSTANTS.clientId)
    .. "&redirect_uri="
    .. urlEncode(CONSTANTS.redirectUri)
    .. "&response_type=code"
    .. "&scope="
    .. urlEncode(CONSTANTS.scope)
    .. "&code_challenge="
    .. urlEncode(codeChallenge)
    .. "&code_challenge_method=S256"
    .. "&state="
    .. urlEncode(state or "mm")
    .. "&prompt=login"
    .. "&ui_locales=de"
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

function loginHtmlHasEmailField(html)
  if type(html) ~= "string" then
    return false
  end
  local lower = html:lower()
  return lower:find('name="login"', 1, true) ~= nil
    or lower:find("input-login", 1, true) ~= nil
    or lower:find("login-submission", 1, true) ~= nil
end

function htmlHasHcaptcha(htmlLower)
  return type(htmlLower) == "string"
    and (htmlLower:find("hcaptcha", 1, true) ~= nil or htmlLower:find("h-captcha", 1, true) ~= nil)
end

function classifyLoginHtml(html)
  if type(html) ~= "string" or html == "" then
    return "unknown"
  end
  local lower = html:lower()
  local hasEmailField = loginHtmlHasEmailField(html)
  -- Passwort / OTP vor Captcha: Verifikationsseiten tragen oft noch hCaptcha in NEXT_DATA.
  if lower:find('name="password"', 1, true) or lower:find('type="password"', 1, true)
      or lower:find("type='password'", 1, true) then
    return "password"
  end
  if lower:find("email-address-verification", 1, true)
      or lower:find("email_address_ownership_validation", 1, true)
      or lower:find("address-validation", 1, true)
      or lower:find('name="code"', 1, true)
      or lower:find("otp_label", 1, true)
      or lower:find("einmalcode", 1, true)
      or lower:find("one-time", 1, true)
      or lower:find("bestätigungscode", 1, true)
      or lower:find("verifizierungscode", 1, true)
      or lower:find("überprüfe dein postfach", 1, true)
      or lower:find("ueberpruefe dein postfach", 1, true) then
    return "otp"
  end
  if htmlHasHcaptcha(lower) then
    return "captcha"
  end
  if hasEmailField or lower:find("e-mail-adresse", 1, true) then
    return "email"
  end
  return "unknown"
end

function captchaBlockedMessage()
  return "Pluxee: Login blockiert durch hCaptcha auf connect.pluxee.app — "
    .. "Site-Key fehlt oder Captcha konnte nicht gestartet werden."
end

function extractHcaptchaSiteKey(html)
  if type(html) ~= "string" or html == "" then
    return nil
  end
  local key = html:match('"siteKey"%s*:%s*"([%w%-]+)"')
    or html:match("'siteKey'%s*:%s*'([%w%-]+)'")
    or html:match("[?&]sitekey=([%w%-]+)")
  if type(key) == "string" and key ~= "" then
    return key
  end
  return nil
end

function setPendingLoginPage(html, currentUrl)
  session.pendingLoginHtml = html
  session.pendingLoginUrl = currentUrl
end

function beginLoginCaptchaChallenge(html, currentUrl)
  local siteKey = extractHcaptchaSiteKey(html)
  if not siteKey then
    return captchaBlockedMessage()
  end
  session.awaitingCaptcha = true
  setPendingLoginPage(html, currentUrl)
  return hCaptchaInteractiveChallenge(siteKey, currentUrl)
end

function hCaptchaInteractiveChallenge(siteKey, refererUrl)
  if type(siteKey) ~= "string" or siteKey == "" then
    return captchaBlockedMessage()
  end
  local referer = refererUrl
  if type(referer) ~= "string" or referer == "" then
    referer = CONSTANTS.authorizeUrl
  end
  -- Offizielle MM-WebBanking-Captcha-Variante (invisible hCaptcha).
  local challenge = "https://js.hcaptcha.com/1/api.js?sitekey="
    .. urlEncode(siteKey)
    .. "&referer="
    .. urlEncode(referer)
  return {
    title = "Pluxee Authentifizierung",
    challenge = challenge,
  }
end

function connectionBaseUrl(fallback)
  if connection and type(connection.getBaseURL) == "function" then
    local ok, base = pcall(function()
      return connection:getBaseURL()
    end)
    if ok and type(base) == "string" and base:match("^https://") and hostAllowed(base) then
      return base
    end
  end
  return fallback
end

function isCredentialRejection(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  local lower = text:lower()
  for _, marker in ipairs(CREDENTIAL_REJECTION_MARKERS) do
    if lower:find(marker, 1, true) then
      return true
    end
  end
  return false
end

function credentialRejectionOr(message)
  if isCredentialRejection(message) then
    return LoginFailed
  end
  return message
end

function emailOtpChallenge(message)
  return {
    title = "Pluxee Authentifizierung",
    challenge = message or "Bitte den Code aus der Pluxee-E-Mail eingeben.",
    label = "E-Mail-Code",
  }
end

function jsonStringEscape(s)
  return tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
end

function extractInteractionIdFromUrl(url)
  if type(url) ~= "string" or url == "" then
    return nil
  end
  local id = url:match("/op/interaction/([^/?#]+)/")
    or url:match("/interaction/([^/?#]+)/")
  if isSafeOidcInteractionId(id) then
    return id
  end
  return nil
end

function isSafeOidcInteractionId(id)
  return type(id) == "string"
    and id ~= ""
    and #id <= 128
    and id:match("^[%w%-]+$") ~= nil
end

function allowedOidcOpUrl(op)
  if type(op) ~= "string" or op == "" then
    return nil
  end
  local cleaned = op:gsub("/$", "")
  if cleaned:match("^https://") and hostAllowed(cleaned) then
    return cleaned
  end
  return nil
end

function extractOtpPageMeta(html, currentUrl)
  local meta = {
    interactionId = nil,
    opUrl = CONSTANTS.oidcAuthority,
    nbCodesSent = 0,
    hcaptchaCredits = nil,
    siteKey = nil,
  }
  -- Live: URL-Pfad /interaction/{id}/… ist die Server-Session; NEXT_DATA.interactionId
  -- kann abweichen (Log 2026-09-05: x1trdcwy… vs. 62e25790…).
  meta.interactionId = extractInteractionIdFromUrl(currentUrl)
  if type(html) ~= "string" or html == "" then
    return meta
  end
  if not meta.interactionId then
    local fromHtml = html:match('"interactionId"%s*:%s*"([^"]+)"')
    if isSafeOidcInteractionId(fromHtml) then
      meta.interactionId = fromHtml
    end
  end
  local op = html:match('"opUrl"%s*:%s*"([^"]+)"')
  local allowedOp = allowedOidcOpUrl(op)
  if allowedOp then
    meta.opUrl = allowedOp
  end
  local n = html:match('"nbCodesSent"%s*:%s*(%d+)')
  if n then
    meta.nbCodesSent = tonumber(n) or 0
  end
  local credits = html:match('"hcaptchaCredits"%s*:%s*(%-?%d+)')
  if credits then
    meta.hcaptchaCredits = tonumber(credits)
  end
  meta.siteKey = extractHcaptchaSiteKey(html)
  return meta
end

function otpResendUrl(meta)
  if type(meta) ~= "table" or not isSafeOidcInteractionId(meta.interactionId) then
    return nil
  end
  local base = allowedOidcOpUrl(meta.opUrl) or CONSTANTS.oidcAuthority
  base = tostring(base):gsub("/$", "")
  return base .. "/interaction/" .. meta.interactionId .. "/email_address_ownership_validation"
end

function buildResendOtpJson(hcaptchaToken)
  if type(hcaptchaToken) == "string" and trim(hcaptchaToken) ~= "" then
    return '{"action":"resend-address-validation","h-captcha-response":"'
      .. jsonStringEscape(trim(hcaptchaToken))
      .. '"}'
  end
  return '{"action":"resend-address-validation"}'
end

function otpResendNeedsCaptcha(meta)
  return type(meta) == "table"
    and type(meta.hcaptchaCredits) == "number"
    and meta.hcaptchaCredits <= 0
end

function sendOtpEmailCode(meta, hcaptchaToken)
  local url = otpResendUrl(meta)
  if not url then
    return "Pluxee: OTP-Versand — interactionId fehlt."
  end
  assertAllowedUrl(url)
  local raw = apiRequest("POST", url, buildResendOtpJson(hcaptchaToken), nil, "application/json")
  if type(raw) ~= "string" then
    return "Pluxee: OTP-E-Mail konnte nicht angefordert werden (leere Antwort)."
  end
  if isCredentialRejection(raw) then
    return LoginFailed
  end
  if raw:find("e_generic", 1, true) or raw:find("e_max_sending", 1, true) then
    return "Pluxee: OTP-E-Mail konnte nicht angefordert werden."
  end
  local payload = parseJson(raw)
  if payload and (payload.error or payload.message) then
    return "Pluxee: OTP-E-Mail konnte nicht angefordert werden."
  end
  if payload and (type(payload.lastCodeSent) == "table" or payload.hcaptchaCredits ~= nil) then
    return nil
  end
  local n = raw:match('"nbCodesSent"%s*:%s*(%d+)')
  if n and tonumber(n) and tonumber(n) > 0 then
    return nil
  end
  -- SPA: leerer Body / {} nach Erfolg kommt vor.
  if raw == "" or raw == "{}" then
    return nil
  end
  if payload then
    return nil
  end
  return "Pluxee: OTP-E-Mail konnte nicht angefordert werden."
end

function ensureOtpEmailRequested(html, currentUrl)
  if session.otpEmailRequested then
    return nil
  end
  local meta = extractOtpPageMeta(html, currentUrl)
  if meta.nbCodesSent > 0 then
    session.otpEmailRequested = true
    return nil
  end
  if otpResendNeedsCaptcha(meta) then
    local siteKey = meta.siteKey
    if type(siteKey) ~= "string" or siteKey == "" then
      return captchaBlockedMessage()
    end
    session.awaitingOtpResendCaptcha = true
    setPendingLoginPage(html, currentUrl)
    session.otpPageMeta = meta
    return hCaptchaInteractiveChallenge(siteKey, currentUrl)
  end
  local err = sendOtpEmailCode(meta, nil)
  if err then
    return err
  end
  session.otpEmailRequested = true
  return nil
end

function moneyAmountFromPluxee(amountTable)
  if type(amountTable) ~= "table" or type(amountTable.value) ~= "number" then
    return nil
  end
  local exp = amountTable.exponent
  if type(exp) ~= "number" then
    exp = 2
  end
  return amountTable.value / (10 ^ exp)
end

function benefitBalance(benefit)
  if type(benefit) ~= "table" then
    return nil
  end
  return moneyAmountFromPluxee(benefit.amount)
end

function cardLast4(card)
  if type(card) ~= "table" then
    return ""
  end
  if type(card.panLastFourDigits) == "string" and card.panLastFourDigits ~= "" then
    return card.panLastFourDigits
  end
  local masked = card.maskedPan
  if type(masked) == "string" then
    local dig = masked:match("(%d%d%d%d)%s*$")
    if dig then
      return dig
    end
  end
  if type(card.cardId) == "string" and #card.cardId >= 4 then
    return card.cardId:sub(-4)
  end
  return ""
end

function cardAccountNumber(card)
  if type(card) ~= "table" then
    error("Pluxee: Karte für Kontonummer fehlt")
  end
  -- Live: maskedPan z. B. "XXXX 6138" — unverändert aus der API übernehmen (wie givve voucher.number).
  if type(card.maskedPan) == "string" and trim(card.maskedPan) ~= "" then
    return trim(card.maskedPan)
  end
  local last4 = cardLast4(card)
  if last4 == "" then
    error("Pluxee: Kartennummer (maskedPan) fehlt")
  end
  return "XXXX " .. last4
end

function legacyDotsAccountNumber(card)
  local last4 = cardLast4(card)
  if last4 == "" then
    return nil
  end
  return "····" .. last4
end

function legacyAccountNumberForBenefit(benefit)
  if type(benefit) ~= "table" or type(benefit.benefitId) ~= "string" or trim(benefit.benefitId) == "" then
    error("Pluxee: benefitId für Kontonummer fehlt")
  end
  return "pluxee." .. trim(benefit.benefitId):lower()
end

-- Kontonummer = API-maskedPan; bei mehreren Benefits mit gleicher Nummer: Suffix benefitId.
function accountNumberForBenefit(card, benefit, panUsageCount)
  local base = cardAccountNumber(card)
  if type(panUsageCount) == "number" and panUsageCount > 1 then
    return base .. " " .. trim(benefit.benefitId):lower()
  end
  return base
end

function benefitDisplayName(card, benefit)
  if type(benefit) == "table" and type(benefit.name) == "string" and trim(benefit.name) ~= "" then
    return trim(benefit.name)
  end
  if type(card) == "table" and type(card.name) == "string" and trim(card.name) ~= "" then
    return trim(card.name)
  end
  return "Pluxee"
end

function accountNameForBenefit(card, benefit, disambiguate)
  local name = benefitDisplayName(card, benefit)
  if not disambiguate then
    return name
  end
  local last4 = cardLast4(card)
  if last4 ~= "" then
    return name .. " " .. last4
  end
  return name
end

function panUsageCounts(rows)
  local counts = {}
  if type(rows) ~= "table" then
    return counts
  end
  for i = 1, #rows do
    local pan = cardAccountNumber(rows[i].card)
    counts[pan] = (counts[pan] or 0) + 1
  end
  return counts
end

function rowMatchesAccountNumber(row, accountNumber, panCounts)
  if type(row) ~= "table" or type(accountNumber) ~= "string" or accountNumber == "" then
    return false
  end
  local pan = cardAccountNumber(row.card)
  local usage = type(panCounts) == "table" and panCounts[pan] or 1
  if accountNumber == accountNumberForBenefit(row.card, row.benefit, usage) then
    return true
  end
  if accountNumber == legacyAccountNumberForBenefit(row.benefit) then
    return true
  end
  if usage == 1 and accountNumber == pan then
    return true
  end
  local dots = legacyDotsAccountNumber(row.card)
  if usage == 1 and dots and accountNumber == dots then
    return true
  end
  return false
end

function iterWalletBenefits(cards)
  local rows = {}
  if type(cards) ~= "table" then
    return rows
  end
  for i = 1, #cards do
    local card = cards[i]
    if type(card) == "table" and type(card.cardId) == "string" and type(card.benefits) == "table" then
      for j = 1, #card.benefits do
        local benefit = card.benefits[j]
        if type(benefit) == "table" and type(benefit.benefitId) == "string" and benefit.benefitId ~= "" then
          rows[#rows + 1] = { card = card, benefit = benefit }
        end
      end
    end
  end
  return rows
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

function amountForBenefitTransaction(tx, benefitId)
  if type(tx) ~= "table" then
    return nil
  end
  if type(benefitId) == "string" and benefitId ~= "" and type(tx.splitData) == "table" then
    local sum = 0
    local found = false
    local currency = nil
    for i = 1, #tx.splitData do
      local split = tx.splitData[i]
      if type(split) == "table" and split.uniqueWalletId == benefitId then
        local amt = moneyAmountFromPluxee(split.splitAmount)
        if amt ~= nil then
          sum = sum + amt
          found = true
          if type(split.splitAmount) == "table" and type(split.splitAmount.currency) == "string" then
            currency = split.splitAmount.currency
          end
        end
      end
    end
    if found then
      return sum, currency
    end
    return nil, nil
  end
  return moneyAmountFromPluxee(tx.amount), nil
end

function isApprovedPluxeeTransaction(tx)
  if type(tx) ~= "table" then
    return false
  end
  local status = tx.status
  if type(status) ~= "string" or status == "" then
    return false
  end
  return status:upper() == "APPROVED"
end

function mapPluxeeTransaction(tx, benefitId)
  if type(tx) ~= "table" then
    return nil
  end
  if not isApprovedPluxeeTransaction(tx) then
    return nil
  end
  if type(benefitId) == "string" and benefitId ~= "" then
    local matched = false
    if type(tx.splitData) == "table" then
      for i = 1, #tx.splitData do
        local split = tx.splitData[i]
        if type(split) == "table" and split.uniqueWalletId == benefitId then
          matched = true
          break
        end
      end
    end
    if not matched then
      return nil
    end
  end
  local amount, splitCurrency = amountForBenefitTransaction(tx, benefitId)
  local ts = parseIsoDateTimeToTimestamp(tx.date)
  local name = nil
  if type(tx.merchantName) == "string" and trim(tx.merchantName) ~= "" then
    name = trim(tx.merchantName)
  elseif type(tx.description) == "string" and trim(tx.description) ~= "" then
    name = trim(tx.description)
  end
  if not name or amount == nil or not ts then
    return nil
  end
  local currency = "EUR"
  if type(splitCurrency) == "string" and splitCurrency ~= "" then
    currency = splitCurrency
  elseif type(tx.amount) == "table" and type(tx.amount.currency) == "string" and tx.amount.currency ~= "" then
    currency = tx.amount.currency
  end
  local bookingKey = tx.id
  if type(benefitId) == "string" and benefitId ~= "" and type(bookingKey) == "string" then
    bookingKey = bookingKey .. ":" .. benefitId
  end
  return {
    bookingDate = ts,
    name = name,
    amount = amount,
    bookingKey = bookingKey,
    currency = currency,
  }
end

function parseTransactionsPayload(payload, sinceTimestamp, benefitId)
  local out = {}
  if type(payload) ~= "table" or type(payload.transactions) ~= "table" then
    return out
  end
  for i = 1, #payload.transactions do
    local mapped = mapPluxeeTransaction(payload.transactions[i], benefitId)
    if mapped then
      if sinceTimestamp == nil or mapped.bookingDate >= sinceTimestamp then
        out[#out + 1] = mapped
      end
    end
  end
  return out
end

function dayBeforeYmd(ymd)
  if type(ymd) ~= "string" then
    return nil
  end
  local y, m, d = ymd:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then
    return nil
  end
  local t = os.time({
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = 12,
    min = 0,
    sec = 0,
  })
  if not t then
    return nil
  end
  return os.date("%Y-%m-%d", t - 86400)
end

function oldestTransactionIsoDate(transactions)
  local oldest = nil
  if type(transactions) ~= "table" then
    return nil
  end
  for i = 1, #transactions do
    local tx = transactions[i]
    local d = type(tx) == "table" and tx.date or nil
    if type(d) == "string" and d ~= "" then
      if not oldest or d < oldest then
        oldest = d
      end
    end
  end
  return oldest
end

function nextPaginationToDate(previousToDate, oldestIso)
  local ymd = nil
  if type(oldestIso) == "string" then
    ymd = oldestIso:match("^(%d%d%d%d%-%d%d%-%d%d)")
  end
  if not ymd then
    return nil
  end
  if previousToDate == ymd then
    return dayBeforeYmd(ymd)
  end
  return ymd
end

function appendUniqueMappedTransactions(out, seen, mapped)
  if type(mapped) ~= "table" then
    return
  end
  for i = 1, #mapped do
    local tx = mapped[i]
    local key = tx.bookingKey
    if type(key) ~= "string" or key == "" then
      key = tostring(tx.bookingDate) .. ":" .. tostring(tx.amount) .. ":" .. tostring(tx.name)
    end
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = tx
    end
  end
end

function pluxeeApiErrorMessage(payload)
  if type(payload) ~= "table" then
    return nil
  end
  if type(payload.transactions) == "table" or type(payload.cards) == "table" then
    return nil
  end
  if type(payload.validationErrors) == "table" and #payload.validationErrors > 0 then
    local first = payload.validationErrors[1]
    if type(first) == "table" and type(first.message) == "string" and first.message ~= "" then
      return "Pluxee: " .. first.message
    end
  end
  if type(payload.message) == "string" and payload.message ~= "" and type(payload.code) == "number" then
    return "Pluxee: " .. payload.message
  end
  return nil
end

function parseWalletCards(payload)
  if type(payload) ~= "table" or type(payload.cards) ~= "table" then
    return {}
  end
  return payload.cards
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

function persistTokens(storage, accountKey, accessToken, refreshToken, expiresAt)
  local entry = getConnectionEntry(storage, accountKey)
  if not entry then
    return
  end
  entry.accessToken = accessToken
  entry.refreshToken = refreshToken
  entry.expiresAt = expiresAt
  storage.connectionAccountKey = accountKey
  storage.accessToken = accessToken
  storage.refreshToken = refreshToken
  storage.expiresAt = expiresAt
end

function restoreTokens(storage, accountKey)
  if not storage or accountKey == "" then
    return nil, nil, nil
  end
  local entry = storage.connectionsByAccount and storage.connectionsByAccount[accountKey]
  local access = entry and entry.accessToken
  local refresh = entry and entry.refreshToken
  local expiresAt = entry and entry.expiresAt
  if (not access or access == "") and storage.connectionAccountKey == accountKey then
    access = storage.accessToken
    refresh = storage.refreshToken
    expiresAt = storage.expiresAt
  end
  if type(access) == "string" and access ~= "" then
    session.accessToken = access
    session.refreshToken = refresh
    session.expiresAt = expiresAt
    return access, refresh, expiresAt
  end
  return nil, nil, nil
end

function apiHeaders(accessToken)
  local headers = {
    ["Accept"] = "application/json",
    ["Accept-Language"] = "de-DE,de;q=0.9",
    ["User-Agent"] = CONSTANTS.userAgent,
    ["ocp-apim-subscription-key"] = CONSTANTS.apimSubscriptionKey,
    ["Origin"] = CONSTANTS.portalUrl,
    ["Referer"] = CONSTANTS.portalUrl .. "/",
  }
  if type(accessToken) == "string" and accessToken ~= "" then
    headers["Authorization"] = "Bearer " .. accessToken
  end
  return headers
end

function apiRequest(method, url, body, accessToken, contentType)
  assertAllowedUrl(url)
  return connection:request(method, url, body, contentType, apiHeaders(accessToken))
end

function walletUrl()
  return CONSTANTS.bffBase .. "/v2/" .. CONSTANTS.country .. "/cards"
end

function transactionsUrl(cardId, opts)
  if type(opts) == "number" then
    opts = { limit = opts }
  elseif type(opts) ~= "table" then
    opts = {}
  end
  local lim = opts.limit or CONSTANTS.transactionLimit
  local query = "limit=" .. tostring(lim)
  if type(opts.benefitId) == "string" and opts.benefitId ~= "" then
    query = query .. "&benefitId=" .. urlEncode(opts.benefitId)
  end
  if type(opts.toDate) == "string" and opts.toDate ~= "" then
    query = query .. "&toDate=" .. urlEncode(opts.toDate)
  end
  return CONSTANTS.bffBase
    .. "/v2/"
    .. CONSTANTS.country
    .. "/cards/"
    .. urlEncode(cardId)
    .. "/transactions?"
    .. query
end

function fetchCardTransactions(cardId, benefitId)
  -- Live 2026-09-05: Portal lädt ohne fromDate (limit=99) die volle Historie
  -- (81 Tx ab 2023-05). Mit fromDate=MoneyMoney-since (z. B. 2025-09-06) nur
  -- 8 Tx ab 2025-10-01 → MM: „ältere Umsätze nicht verfügbar“.
  local out = {}
  local seen = {}
  local toDate = nil
  local limit = CONSTANTS.transactionLimit
  local maxPages = CONSTANTS.transactionMaxPages or 50

  for _page = 1, maxPages do
    local url = transactionsUrl(cardId, {
      limit = limit,
      benefitId = benefitId,
      toDate = toDate,
    })
    local txRaw = apiRequest("GET", url, nil, session.accessToken)
    local txPayload = parseJson(txRaw)
    if not txPayload then
      return nil, "Pluxee: Umsätze konnten nicht gelesen werden."
    end
    local apiErr = pluxeeApiErrorMessage(txPayload)
    if apiErr then
      return nil, apiErr
    end
    local batch = txPayload.transactions
    if type(batch) ~= "table" then
      batch = {}
    end
    appendUniqueMappedTransactions(
      out,
      seen,
      parseTransactionsPayload(txPayload, nil, benefitId)
    )
    if #batch < limit then
      break
    end
    local oldestIso = oldestTransactionIsoDate(batch)
    local nextTo = nextPaginationToDate(toDate, oldestIso)
    if not nextTo or nextTo == toDate then
      break
    end
    toDate = nextTo
  end
  return out, nil
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

function probeWallet(accessToken)
  local raw = apiRequest("GET", walletUrl(), nil, accessToken)
  local payload = parseJson(raw)
  if payload and type(payload.cards) == "table" then
    return payload
  end
  return nil
end

function exchangeRefreshToken(refreshToken)
  if type(refreshToken) ~= "string" or refreshToken == "" then
    return nil
  end
  local body = "grant_type=refresh_token"
    .. "&refresh_token="
    .. urlEncode(refreshToken)
    .. "&client_id="
    .. urlEncode(CONSTANTS.clientId)
  local raw = apiRequest("POST", CONSTANTS.tokenUrl, body, nil, "application/x-www-form-urlencoded")
  local payload = parseJson(raw)
  if not payload or type(payload.access_token) ~= "string" or payload.access_token == "" then
    return nil
  end
  return payload
end

function applyTokenPayload(payload, storage, accountKey)
  local access = payload.access_token
  local refresh = payload.refresh_token
  local expiresIn = payload.expires_in
  local expiresAt = nil
  if type(expiresIn) == "number" then
    expiresAt = os.time() + expiresIn
  end
  session.accessToken = access
  session.refreshToken = refresh
  session.expiresAt = expiresAt
  if storage then
    persistTokens(storage, accountKey, access, refresh, expiresAt)
  end
end

function buildLoginSubmissionBody(email, hcaptchaToken)
  local body = "action=login-submission&login=" .. urlEncode(normalizeEmail(email))
  if type(hcaptchaToken) == "string" and trim(hcaptchaToken) ~= "" then
    body = body .. "&h-captcha-response=" .. urlEncode(trim(hcaptchaToken))
  end
  return body
end

function buildPasswordSubmissionBody(password)
  return "password=" .. urlEncode(tostring(password or ""))
end

function buildOtpSubmissionBody(code)
  -- Live Connect DE (2026-09-05): action=address-validation, Feld name="code".
  return "action=address-validation"
    .. "&isWebAuthnAvailable=false"
    .. "&code="
    .. urlEncode(trim(tostring(code or "")))
end

function extractFormAction(html, currentUrl)
  if type(html) ~= "string" then
    return nil
  end
  local action = html:match('<form[^>]*action="([^"]+)"')
    or html:match("<form[^>]*action='([^']+)'")
  if not action or action == "" then
    if type(currentUrl) == "string" and currentUrl:match("^https://") then
      assertAllowedUrl(currentUrl)
      return currentUrl
    end
    return nil
  end
  if action:match("^https://") then
    assertAllowedUrl(action)
    return action
  end
  if action:sub(1, 1) == "/" then
    local origin = (currentUrl or ""):match("^(https://[^/]+)")
    if not origin then
      return nil
    end
    local abs = origin .. action
    assertAllowedUrl(abs)
    return abs
  end
  return nil
end

function postLoginForm(html, currentUrl, body, missingActionMessage)
  local action = extractFormAction(html, currentUrl)
  if not action then
    return nil, missingActionMessage
  end
  local response = apiRequest(
    "POST",
    action,
    body,
    nil,
    "application/x-www-form-urlencoded"
  )
  return response, nil
end

function submitLoginEmail(html, currentUrl, email, hcaptchaToken)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    if type(hcaptchaToken) ~= "string" or trim(hcaptchaToken) == "" then
      return nil, captchaBlockedMessage()
    end
    if not loginHtmlHasEmailField(html) then
      return nil, "Pluxee: E-Mail-Feld auf Captcha-Login-Seite fehlt."
    end
  elseif kind ~= "email" then
    return nil, "Pluxee: E-Mail-Login-Seite erwartet, erhalten: " .. tostring(kind)
  end
  return postLoginForm(
    html,
    currentUrl,
    buildLoginSubmissionBody(email, hcaptchaToken),
    "Pluxee: Form-action für E-Mail-Login fehlt."
  )
end

function submitLoginPassword(html, currentUrl, password)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return nil, captchaBlockedMessage()
  end
  if kind ~= "password" then
    return nil, "Pluxee: Passwort-Seite erwartet."
  end
  if trim(tostring(password or "")) == "" then
    return nil, "Pluxee: Passwort erforderlich (Portal zeigt Passwortfeld)."
  end
  return postLoginForm(
    html,
    currentUrl,
    buildPasswordSubmissionBody(password),
    "Pluxee: Form-action für Passwort fehlt."
  )
end

function submitLoginOtp(html, currentUrl, code)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return nil, captchaBlockedMessage()
  end
  if kind ~= "otp" then
    return nil, "Pluxee: OTP-Seite erwartet."
  end
  if trim(tostring(code or "")) == "" then
    return nil, emailOtpChallenge("Bitte den E-Mail-Code eingeben.")
  end
  return postLoginForm(
    html,
    currentUrl,
    buildOtpSubmissionBody(code),
    "Pluxee: Form-action für OTP fehlt."
  )
end

function parseCallbackCode(urlOrBody)
  return parseCallbackQueryValue(urlOrBody, "code")
end

function parseCallbackState(urlOrBody)
  return parseCallbackQueryValue(urlOrBody, "state")
end

function parseCallbackQueryValue(urlOrBody, name)
  if type(urlOrBody) ~= "string" or type(name) ~= "string" or name == "" then
    return nil
  end
  local source = urlOrBody
  -- HTML-Antworten: nur echte Callback-URLs, nicht jedes Query-Param im Markup.
  if urlOrBody:find("<!DOCTYPE", 1, true) or urlOrBody:find("<html", 1, true)
      or urlOrBody:find("<!doctype", 1, true) then
    source = urlOrBody:match("https://consumers%.pluxee%.de/oidc/callback%?[^%s\"'<>]+")
    if not source then
      return nil
    end
  end
  return decodeCallbackCode(source:match("[?&]" .. name .. "=([^&]+)"))
end

function oauthCallbackStateError(urlOrBody)
  local expected = session.oauthState
  if type(expected) ~= "string" or expected == "" then
    return "Pluxee: OAuth state fehlt in der Session."
  end
  local got = parseCallbackState(urlOrBody)
  if type(got) ~= "string" or got == "" then
    return "Pluxee: OAuth state fehlt in der Callback-URL."
  end
  if got ~= expected then
    return "Pluxee: OAuth state ungültig."
  end
  return nil
end

function authorizationCodeFromTrustedCallback(urlOrBody)
  local code = parseCallbackCode(urlOrBody)
  if not code then
    return nil, nil
  end
  local stateErr = oauthCallbackStateError(urlOrBody)
  if stateErr then
    return nil, stateErr
  end
  return code, nil
end

function decodeCallbackCode(code)
  if type(code) ~= "string" or code == "" then
    return nil
  end
  if MM and MM.urldecode then
    return MM.urldecode(code)
  end
  return code:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
end

function exchangeAuthorizationCode(code)
  if type(code) ~= "string" or code == "" then
    return nil, "Pluxee: Authorization-Code fehlt."
  end
  if type(session.codeVerifier) ~= "string" or session.codeVerifier == "" then
    return nil, "Pluxee: PKCE code_verifier fehlt."
  end
  local body = "grant_type=authorization_code"
    .. "&code="
    .. urlEncode(code)
    .. "&redirect_uri="
    .. urlEncode(CONSTANTS.redirectUri)
    .. "&client_id="
    .. urlEncode(CONSTANTS.clientId)
    .. "&code_verifier="
    .. urlEncode(session.codeVerifier)
  local raw = apiRequest("POST", CONSTANTS.tokenUrl, body, nil, "application/x-www-form-urlencoded")
  local payload = parseJson(raw)
  if not payload or type(payload.access_token) ~= "string" or payload.access_token == "" then
    if isCredentialRejection(raw) then
      return nil, LoginFailed
    end
    return nil, "Pluxee: Token-Tausch fehlgeschlagen."
  end
  return payload, nil
end

function resetLoginChallengeSessionFields()
  session.awaitingMfa = false
  session.awaitingCaptcha = false
  session.awaitingOtpResendCaptcha = false
  session.hcaptchaToken = nil
  session.otpEmailRequested = nil
  session.otpPageMeta = nil
  session.codeVerifier = nil
  session.oauthState = nil
  session.passwordSubmitted = nil
  session.otpSubmitted = nil
  session.pendingLoginHtml = nil
  session.pendingLoginUrl = nil
end

function completeLoginWithAuthorizationCode(code)
  local payload, tokenErr = exchangeAuthorizationCode(code)
  if tokenErr then
    return tokenErr
  end
  local storage = rawget(_G, "LocalStorage")
  applyTokenPayload(payload, storage, session.accountKey)
  if not ensureWalletPayload() then
    return "Pluxee: Login ok, aber Wallet nicht lesbar."
  end
  resetLoginChallengeSessionFields()
  return nil
end

function continueLoginAfterResponse(response, currentUrl)
  -- Nach OTP/Consent folgt Redirect auf oidc/callback?code=…; der Code steckt in
  -- der finalen URL (getBaseURL), nicht im SPA-HTML-Body (Live-Log 2026-09-05).
  currentUrl = connectionBaseUrl(currentUrl)
  local haystack = tostring(response or "")
  local cbCode, stateErr = authorizationCodeFromTrustedCallback(currentUrl)
  if stateErr then
    return stateErr
  end
  if not cbCode then
    cbCode, stateErr = authorizationCodeFromTrustedCallback(haystack)
    if stateErr then
      return stateErr
    end
  end
  if cbCode then
    return completeLoginWithAuthorizationCode(cbCode)
  end
  local kind = classifyLoginHtml(haystack)
  if kind == "captcha" then
    if type(session.hcaptchaToken) == "string" and session.hcaptchaToken ~= "" then
      session.hcaptchaToken = nil
      return "Pluxee: hCaptcha ungültig oder abgelaufen. Bitte erneut anmelden."
    end
    return beginLoginCaptchaChallenge(haystack, currentUrl)
  end
  if kind == "password" then
    session.hcaptchaToken = nil
    if session.passwordSubmitted then
      return LoginFailed
    end
    local pw = session.pendingPassword or ""
    local nextHtml, err = submitLoginPassword(haystack, currentUrl, pw)
    if err then
      return err
    end
    session.passwordSubmitted = true
    setPendingLoginPage(nextHtml, connectionBaseUrl(currentUrl))
    return continueLoginAfterResponse(nextHtml, session.pendingLoginUrl)
  end
  if kind == "otp" then
    session.hcaptchaToken = nil
    if session.otpSubmitted and isCredentialRejection(haystack) then
      session.awaitingMfa = false
      return LoginFailed
    end
    setPendingLoginPage(haystack, currentUrl)
    local sendResult = ensureOtpEmailRequested(haystack, currentUrl)
    if sendResult ~= nil then
      return sendResult
    end
    session.awaitingMfa = true
    return emailOtpChallenge(nil)
  end
  if isCredentialRejection(haystack) then
    session.awaitingMfa = false
    return LoginFailed
  end
  if kind == "email" then
    return captchaBlockedMessage() .. " (E-Mail-Schritt erneut — Captcha erwartet.)"
  end
  -- Consent-/Zwischen-HTML ohne code: ggf. Base-URL erneut prüfen.
  local again, againErr = authorizationCodeFromTrustedCallback(connectionBaseUrl(currentUrl))
  if againErr then
    return againErr
  end
  if again then
    return completeLoginWithAuthorizationCode(again)
  end
  return "Pluxee: Unerwartete Login-Antwort von connect.pluxee.app."
end

function startOidcLogin()
  local verifier, challenge = pkcePair()
  session.codeVerifier = verifier
  session.oauthState = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
  local url = buildAuthorizeUrl(challenge, session.oauthState)
  local html = apiRequest("GET", url, nil, nil)
  local finalUrl = connectionBaseUrl(url)
  local kind = classifyLoginHtml(html)
  if kind == "captcha" then
    return beginLoginCaptchaChallenge(html, finalUrl)
  end
  if kind == "email" then
    local response, err = submitLoginEmail(html, finalUrl, session.accountKey, nil)
    if err then
      return err
    end
    setPendingLoginPage(response, finalUrl)
    return continueLoginAfterResponse(response, finalUrl)
  end
  if kind == "password" then
    setPendingLoginPage(html, finalUrl)
    return continueLoginAfterResponse(html, finalUrl)
  end
  if kind == "otp" then
    setPendingLoginPage(html, finalUrl)
    local sendResult = ensureOtpEmailRequested(html, finalUrl)
    if sendResult ~= nil then
      return sendResult
    end
    session.awaitingMfa = true
    return emailOtpChallenge(nil)
  end
  return "Pluxee: Unerwartete Login-Seite von connect.pluxee.app."
end

function tryReuseStoredWallet(storage, email)
  local access, refresh = restoreTokens(storage, email)
  if not access then
    return false
  end
  local wallet = probeWallet(access)
  if wallet then
    session.walletPayload = wallet
    return true
  end
  if refresh then
    local refreshed = exchangeRefreshToken(refresh)
    if refreshed then
      applyTokenPayload(refreshed, storage, email)
      if ensureWalletPayload() then
        return true
      end
    end
  end
  session.accessToken = nil
  return false
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  local email = normalizeEmail(credentials and credentials[1])
  local password = credentials and credentials[2] or ""
  local storage = rawget(_G, "LocalStorage")

  if step == 1 then
    if email == "" then
      return "Bitte die Pluxee-E-Mail-Adresse eingeben."
    end
    session = { accountKey = email, pendingPassword = password }
    if storage then
      stripNonSerializableConnections(storage)
      getConnectionEntry(storage, email)
      storage.connectionAccountKey = email
    end
    ensureConnection()

    if tryReuseStoredWallet(storage, email) then
      return nil
    end

    if interactive == false then
      return "Pluxee: Interaktive Anmeldung (E-Mail-OTP) erforderlich."
    end
    return startOidcLogin()
  end

  ensureConnection()
  if session.awaitingCaptcha then
    local token = interactiveCredentialToken(credentials)
    local html = session.pendingLoginHtml
    local currentUrl = session.pendingLoginUrl
    if not token then
      local siteKey = extractHcaptchaSiteKey(html)
      session.awaitingCaptcha = true
      return hCaptchaInteractiveChallenge(siteKey, currentUrl)
    end
    session.awaitingCaptcha = false
    session.hcaptchaToken = token
    local response, err = submitLoginEmail(html, currentUrl, session.accountKey, session.hcaptchaToken)
    if err then
      return err
    end
    session.pendingLoginHtml = response
    return continueLoginAfterResponse(response, currentUrl)
  end
  if session.awaitingOtpResendCaptcha then
    local token = interactiveCredentialToken(credentials)
    local html = session.pendingLoginHtml
    local currentUrl = session.pendingLoginUrl
    local meta = session.otpPageMeta or extractOtpPageMeta(html, currentUrl)
    if not token then
      session.awaitingOtpResendCaptcha = true
      return hCaptchaInteractiveChallenge(meta.siteKey or extractHcaptchaSiteKey(html), currentUrl)
    end
    session.awaitingOtpResendCaptcha = false
    local err = sendOtpEmailCode(meta, token)
    if err then
      return err
    end
    session.otpEmailRequested = true
    session.awaitingMfa = true
    return emailOtpChallenge("Code wurde angefordert. Bitte den Code aus der Pluxee-E-Mail eingeben.")
  end
  if session.awaitingMfa then
    local code = credentials and credentials[1]
    local html = session.pendingLoginHtml
    local currentUrl = session.pendingLoginUrl
    local response, err = submitLoginOtp(html, currentUrl, code)
    if type(err) == "table" then
      return err
    end
    if err then
      return err
    end
    session.otpSubmitted = true
    session.pendingLoginHtml = response
    return continueLoginAfterResponse(response, currentUrl)
  end
  return "Anmeldesitzung abgelaufen. Bitte erneut anmelden."
end

function rememberBenefitAccountAliases(number, ref, card, benefit, panCount)
  session.benefitsByAccountNumber[number] = ref
  session.benefitsByAccountNumber[legacyAccountNumberForBenefit(benefit)] = ref
  local dots = legacyDotsAccountNumber(card)
  if dots and panCount == 1 then
    session.benefitsByAccountNumber[dots] = ref
  end
end

function interactiveCredentialToken(credentials)
  local token = credentials and credentials[1]
  if type(token) ~= "string" or trim(token) == "" then
    return nil
  end
  return trim(token)
end

function sessionAccessMissingMessage()
  if type(session.accessToken) ~= "string" or session.accessToken == "" then
    return "Pluxee: Session fehlt — bitte anmelden."
  end
  return nil
end

function ensureWalletPayload()
  local wallet = session.walletPayload
  if wallet then
    return wallet
  end
  wallet = probeWallet(session.accessToken)
  if not wallet then
    return nil
  end
  session.walletPayload = wallet
  return wallet
end

function ListAccounts(knownAccounts)
  local missing = sessionAccessMissingMessage()
  if missing then
    return missing
  end
  ensureConnection()
  local wallet = ensureWalletPayload()
  if not wallet then
    return "Pluxee: Kontenliste konnte nicht gelesen werden."
  end
  local cards = parseWalletCards(wallet)
  local rows = iterWalletBenefits(cards)
  if #rows == 0 then
    return "Pluxee: Kein Benefit im Wallet gefunden."
  end
  local accounts = {}
  session.benefitsByAccountNumber = {}
  local disambiguate = #rows > 1
  local panCounts = panUsageCounts(rows)
  for i = 1, #rows do
    local card = rows[i].card
    local benefit = rows[i].benefit
    local balance = benefitBalance(benefit)
    if balance == nil then
      return "Pluxee: Saldo für Benefit fehlt."
    end
    local pan = cardAccountNumber(card)
    local number = accountNumberForBenefit(card, benefit, panCounts[pan])
    local ref = {
      cardId = card.cardId,
      benefitId = benefit.benefitId,
    }
    rememberBenefitAccountAliases(number, ref, card, benefit, panCounts[pan])
    accounts[#accounts + 1] = {
      name = accountNameForBenefit(card, benefit, disambiguate),
      accountNumber = number,
      currency = "EUR",
      balance = balance,
      type = AccountTypeCreditCard,
    }
  end
  return accounts
end

function benefitBalanceById(wallet, benefitId)
  if type(wallet) ~= "table" or type(benefitId) ~= "string" or benefitId == "" then
    return nil
  end
  for _, row in ipairs(iterWalletBenefits(parseWalletCards(wallet))) do
    if row.benefit.benefitId == benefitId then
      return benefitBalance(row.benefit)
    end
  end
  return nil
end

function resolveBenefitRefForAccount(account)
  local accountNumber = type(account) == "table" and account.accountNumber or nil
  if type(accountNumber) ~= "string" or accountNumber == "" then
    return nil, nil, "Pluxee: Benefit passt nicht zur Kontonummer."
  end
  local ref = session.benefitsByAccountNumber and session.benefitsByAccountNumber[accountNumber]
  if type(ref) == "table" and ref.cardId and ref.benefitId then
    return ref.cardId, ref.benefitId, nil
  end
  local wallet = ensureWalletPayload()
  if not wallet then
    return nil, nil, "Pluxee: Wallet für Umsätze nicht lesbar."
  end
  local rows = iterWalletBenefits(parseWalletCards(wallet))
  if #rows < 1 then
    return nil, nil, "Pluxee: Benefit für Umsätze nicht gefunden."
  end
  local counts = panUsageCounts(rows)
  for i = 1, #rows do
    if rowMatchesAccountNumber(rows[i], accountNumber, counts) then
      return rows[i].card.cardId, rows[i].benefit.benefitId, nil
    end
  end
  return nil, nil, "Pluxee: Benefit passt nicht zur Kontonummer."
end

function RefreshAccount(account, since)
  -- MoneyMoney übergibt since; Historie wird bewusst ohne API-fromDate geladen
  -- (sonst MM-Warnung „ältere Umsätze…“, Live 2026-09-05).
  local _ = since
  local missing = sessionAccessMissingMessage()
  if missing then
    return missing
  end
  ensureConnection()
  local cardId, benefitId, resolveErr = resolveBenefitRefForAccount(account)
  if resolveErr then
    return resolveErr
  end

  local wallet = ensureWalletPayload()
  local balance = benefitBalanceById(wallet, benefitId)
  if balance == nil then
    return "Pluxee: Saldo konnte nicht gelesen werden."
  end

  local transactions, txErr = fetchCardTransactions(cardId, benefitId)
  if txErr then
    return txErr
  end
  return {
    balance = balance,
    transactions = transactions,
  }
end

function EndSession()
  local storage = rawget(_G, "LocalStorage")
  if storage then
    stripNonSerializableConnections(storage)
  end
  session.pendingPassword = nil
  resetLoginChallengeSessionFields()
  connection = nil
end

-- SIGNATURE: MC0CFQCHwCNQHj0Ql+ZdpG1VD3RTFM2A+QIUO7uNEajRFgClCHfqiziDCyiOixs=
