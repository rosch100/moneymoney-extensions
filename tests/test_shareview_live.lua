-- Live-Integrationstest für extensions/Shareview.lua gegen die echte Site.
-- Stubs MoneyMoneys Connection-API mit curl + Cookie-Jar.
--
-- Verwendung:
--   lua test_shareview_live.lua step1 <username> <dob:TT.MM.JJJJ> <password>
--   lua test_shareview_live.lua step2 <otp>
--
-- Anstatt der Argumente können auch ENV-Variablen genutzt werden:
--   SHAREVIEW_USERNAME, SHAREVIEW_DOB, SHAREVIEW_PASSWORD
--
-- Zustand zwischen Aufrufen: /tmp/shareview-test/

local STATE_DIR  = "/tmp/shareview-test"
local COOKIE_JAR = STATE_DIR .. "/cookies.txt"
local STATE_FILE = STATE_DIR .. "/state.lua"
local LAST_HTML  = STATE_DIR .. "/last.html"

os.execute("mkdir -p " .. STATE_DIR)

-- ============================================================================
-- MoneyMoney-API stubben (vor dofile)
-- ============================================================================

ProtocolWebBanking = "WebBanking"
AccountTypePortfolio = 5
LoginFailed = "LoginFailed"

function WebBanking(_) end

MM = {
  printStatus = function(msg) io.stderr:write("    [MM] " .. msg .. "\n") end,
  urlencode = function(s)
    return (tostring(s):gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end
}

-- ============================================================================
-- Connection-Stub via curl
-- ============================================================================

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*all")
  f:close()
  return content
end

local function writeFile(path, content)
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

local requestCounter = 0
local requestPrefix = "req"

local function curlRequest(method, url, body, contentType, headers, useragent)
  requestCounter = requestCounter + 1
  local idx = string.format("%03d", requestCounter)
  local bodyFile = STATE_DIR .. "/" .. requestPrefix .. "-" .. idx .. ".body"
  local respFile = STATE_DIR .. "/" .. requestPrefix .. "-" .. idx .. ".resp.body"
  local hdrFile  = STATE_DIR .. "/" .. requestPrefix .. "-" .. idx .. ".resp.headers"

  local args = {
    "curl", "-sS", "-L",
    "-c", shellQuote(COOKIE_JAR),
    "-b", shellQuote(COOKIE_JAR),
    "-X", method,
    "-D", shellQuote(hdrFile),
    "-o", shellQuote(respFile),
    "-A", shellQuote(useragent or "Mozilla/5.0"),
    "-w", "'%{http_code}'",
    "--max-time", "60",
    "--compressed",
    -- 411-Vermeidung: Expect-Header unterdrücken
    "-H", shellQuote("Expect:"),
    -- Bei 30x-Redirect POST nicht in GET umwandeln (--post301/302/303 deaktivieren)
    "--post301", "--post302",
  }

  if headers then
    for k, v in pairs(headers) do
      -- Cookie-Header ignorieren: curl-Jar ist Source-of-Truth
      if k:lower() ~= "cookie" then
        table.insert(args, "-H")
        table.insert(args, shellQuote(k .. ": " .. v))
      end
    end
  end

  if contentType and not (headers and (headers["Content-Type"] or headers["content-type"])) then
    table.insert(args, "-H")
    table.insert(args, shellQuote("Content-Type: " .. contentType))
  end

  if body and body ~= "" then
    writeFile(bodyFile, body)
    table.insert(args, "--data-binary")
    table.insert(args, "@" .. shellQuote(bodyFile))
  end

  table.insert(args, shellQuote(url))

  local cmd = table.concat(args, " ")
  io.stderr:write(string.format("    [HTTP %s] %s %s (%d B body)\n",
    idx, method, url, body and #body or 0))
  local p = io.popen(cmd .. " 2>&1", "r")
  local httpCode = (p and p:read("*all")) or ""
  if p then p:close() end

  local respBody = readFile(respFile) or ""
  io.stderr:write(string.format("    [HTTP %s] -> %s, %d bytes\n",
    idx, httpCode:gsub("'", ""), #respBody))
  return respBody
end

local function readCookieJarAsString()
  local content = readFile(COOKIE_JAR)
  if not content then return "" end
  local pairs_ = {}
  for line in content:gmatch("[^\n]+") do
    if not line:match("^#") and line ~= "" then
      -- Netscape-Format: domain  flag  path  secure  expiry  name  value
      local parts = {}
      for f in line:gmatch("[^\t]+") do
        table.insert(parts, f)
      end
      if #parts >= 7 then
        local name = parts[6]
        local value = parts[7]
        table.insert(pairs_, name .. "=" .. value)
      end
    end
  end
  return table.concat(pairs_, "; ")
end

function Connection()
  local conn = { language = "en-GB", useragent = "Mozilla/5.0" }
  function conn:request(method, url, body, contentType, headers)
    local resp = curlRequest(method, url, body, contentType, headers, self.useragent)
    return resp, "utf-8", "text/html", nil, {}
  end
  function conn:getCookies()
    return readCookieJarAsString()
  end
  return conn
end

-- ============================================================================
-- State-Persistierung zwischen Skript-Aufrufen
-- ============================================================================

local function saveState(state)
  local lines = { "return {" }
  for k, v in pairs(state) do
    if type(v) == "string" then
      table.insert(lines, string.format("  [%q] = %q,", k, v))
    end
  end
  table.insert(lines, "}")
  writeFile(STATE_FILE, table.concat(lines, "\n"))
end

local function loadState()
  if io.open(STATE_FILE, "rb") then
    return dofile(STATE_FILE)
  end
  return {}
end

-- ============================================================================
-- Extension laden
-- ============================================================================

dofile("extensions/Shareview.lua")

-- Zugriff auf in Shareview.lua als `local` deklarierte Variablen via Upvalue-API.
local function findUpvalueIndex(funcRef, name)
  for i = 1, math.huge do
    local n = debug.getupvalue(funcRef, i)
    if not n then return nil end
    if n == name then return i end
  end
end

local function getInternalUpvalue(funcRef, name)
  local i = findUpvalueIndex(funcRef, name)
  if not i then return nil end
  local _, v = debug.getupvalue(funcRef, i)
  return v
end

local function setInternalUpvalue(funcRef, name, value)
  local i = findUpvalueIndex(funcRef, name)
  if not i then error("Upvalue '" .. name .. "' nicht gefunden in Closure") end
  debug.setupvalue(funcRef, i, value)
end

-- session als Upvalue ist in Funktionen verfügbar, die session direkt
-- referenzieren (loginStep2 nutzt session.mfaHtml). connection wird in
-- InitializeSession2 direkt zugewiesen.
session = getInternalUpvalue(loginStep2, "session")
if not session then error("session-Upvalue nicht gefunden") end

local function ensureConnection()
  if not getInternalUpvalue(InitializeSession2, "connection") then
    setInternalUpvalue(InitializeSession2, "connection", Connection())
  end
end

-- ============================================================================
-- Test-Modi
-- ============================================================================

local function fail(msg)
  io.stderr:write("\n[FAIL] " .. tostring(msg) .. "\n")
  os.exit(1)
end

local function step1(username, dob, password)
  if not username or username == "" then fail("Username fehlt") end
  if not dob or dob == "" then fail("Geburtsdatum fehlt (TT.MM.JJJJ)") end
  if not password or password == "" then fail("Passwort fehlt") end

  -- Frische Session: alte Cookies/State weg
  os.execute("rm -f " .. shellQuote(COOKIE_JAR) .. " " .. shellQuote(STATE_FILE) .. " " .. shellQuote(LAST_HTML))

  local credentials = { username .. "|" .. dob, password }

  io.stderr:write("\n=== Step 1: Login mit Username + DOB + Passwort ===\n\n")
  local result = InitializeSession2(ProtocolWebBanking, "Shareview", 1, credentials, false)

  if result == nil then
    -- Login ohne MFA erfolgreich (selten)
    io.stderr:write("\n[OK] Login ohne MFA erfolgreich.\n")
    saveState({ phase = "logged_in" })
    return runListAndRefresh()
  end

  if type(result) == "string" then
    -- MFA-HTML zwischenspeichern, falls vorhanden
    if session and session.mfaHtml then
      writeFile(LAST_HTML, session.mfaHtml)
    end
    fail("Login Step 1 lieferte Fehler: " .. result)
  end

  if type(result) == "table" and result.title then
    io.stderr:write("\n[OK] MFA-Prompt erhalten:\n")
    io.stderr:write("       title: " .. tostring(result.title) .. "\n")
    io.stderr:write("       challenge: " .. tostring(result.challenge) .. "\n")
    io.stderr:write("       label: " .. tostring(result.label) .. "\n\n")

    -- mfaHtml wegspeichern, damit step2 ihn aus state restaurieren kann
    if session and session.mfaHtml then
      writeFile(LAST_HTML, session.mfaHtml)
      saveState({ phase = "awaiting_otp" })
      io.stderr:write("[NEXT] Bitte den 6-stelligen Authentication Code aus E-Mail/App senden:\n")
      io.stderr:write("       lua test_shareview_live.lua step2 <CODE>\n\n")
      return
    end
    fail("MFA-HTML konnte nicht gespeichert werden")
  end

  fail("Unerwarteter Rückgabewert von Step 1: " .. tostring(result))
end

local function step2(otp)
  if not otp or otp == "" then fail("OTP fehlt") end
  local state = loadState()
  if state.phase ~= "awaiting_otp" then
    fail("Kein offener MFA-Schritt. Erst step1 ausführen.")
  end

  -- mfaHtml aus Datei in session global wiederherstellen (Extension nutzt session.mfaHtml)
  local mfaHtml = readFile(LAST_HTML)
  if not mfaHtml then fail("MFA-HTML nicht im State (last.html fehlt)") end
  session.mfaHtml = mfaHtml

  -- Cookies wurden über den curl-Jar persistiert; aktualisierten Stand in session.cookies spiegeln
  session.cookies = readCookieJarAsString()

  io.stderr:write("\n=== Step 2: Authentication Code senden ===\n\n")
  local result = InitializeSession2(ProtocolWebBanking, "Shareview", 2, { otp }, false)

  if result ~= nil then
    fail("Step 2 lieferte Fehler: " .. tostring(result))
  end

  io.stderr:write("\n[OK] Login mit MFA erfolgreich.\n")
  saveState({ phase = "logged_in" })
  return runListAndRefresh()
end

function runListAndRefresh()
  io.stderr:write("\n=== ListAccounts ===\n\n")
  local accounts = ListAccounts({})
  if type(accounts) == "string" then fail("ListAccounts: " .. accounts) end

  for i, a in ipairs(accounts) do
    io.stderr:write(string.format("  [%d] name=%q  accountNumber=%q  currency=%s  type=%s\n",
      i, a.name or "", a.accountNumber or "", tostring(a.currency), tostring(a.type)))
  end

  io.stderr:write("\n=== RefreshAccount ===\n\n")
  local result = RefreshAccount(accounts[1], nil)
  if type(result) == "string" then fail("RefreshAccount: " .. result) end

  io.stderr:write(string.format("  balance: %s GBP\n", tostring(result.balance)))
  io.stderr:write(string.format("  securities: %d\n", #result.securities))
  for _, s in ipairs(result.securities) do
    io.stderr:write(string.format("    - %-50s qty=%-8s price=%-10s amount=%-12s isin=%s\n",
      s.name or "", tostring(s.quantity), tostring(s.price), tostring(s.amount), tostring(s.isin)))
  end

  io.stderr:write("\n[DONE] Live-Test erfolgreich.\n")
  io.stderr:write("Tipp: Cookie-Jar liegt in " .. COOKIE_JAR .. " — bei Bedarf 'rm -rf " .. STATE_DIR .. "' nach dem Test.\n")
end

-- ============================================================================
-- CLI
-- ============================================================================

local mode = arg[1]
if mode == "step1" then
  requestPrefix = "step1"
  local user = arg[2] or os.getenv("SHAREVIEW_USERNAME")
  local dob  = arg[3] or os.getenv("SHAREVIEW_DOB")
  local pw   = arg[4] or os.getenv("SHAREVIEW_PASSWORD")
  step1(user, dob, pw)
elseif mode == "step2" then
  requestPrefix = "step2"
  step2(arg[2])
elseif mode == "replay" then
  requestPrefix = "replay"
  -- Wiederverwendet die letzte OTP-Response (SAML-Token), führt Federation-Hops + Holdings aus
  local replayFile = arg[2] or (STATE_DIR .. "/step2-001.resp.body")
  local html = readFile(replayFile)
  if not html then fail("Replay-Datei nicht gefunden: " .. replayFile) end

  io.stderr:write(string.format("\n=== Replay: SAML-Federation-Form aus %s (%d Bytes) ===\n\n", replayFile, #html))

  ensureConnection()
  session.cookies = readCookieJarAsString()
  html = followAutoPostForms(html, 5)

  local conn = getInternalUpvalue(InitializeSession2, "connection")
  local holdings = conn:request("GET", "https://portfolio.shareview.co.uk/7/portfolio/default/en/Active/Pages/holdingssummary.aspx")
  if holdings and isLoggedInPage(holdings) then
    session.holdingsHtml = holdings
    io.stderr:write("\n[OK] Replay erfolgreich, Login etabliert.\n")
    saveState({ phase = "logged_in" })
    runListAndRefresh()
  else
    fail("Holdings-Seite nicht zugänglich nach Replay (FedAuth fehlt? SAML-Replay vom ADFS abgelehnt?)")
  end
elseif mode == "cleanup" then
  os.execute("rm -rf " .. shellQuote(STATE_DIR))
  io.stderr:write("State entfernt: " .. STATE_DIR .. "\n")
else
  io.stderr:write([[
Verwendung:
  lua test_shareview_live.lua step1 <username> <TT.MM.JJJJ> <password>
  lua test_shareview_live.lua step2 <otp>
  lua test_shareview_live.lua cleanup

ENV (alternativ zu Step1-Argumenten):
  SHAREVIEW_USERNAME, SHAREVIEW_DOB, SHAREVIEW_PASSWORD
]])
  os.exit(2)
end
