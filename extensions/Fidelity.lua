--
-- Fidelity Investments — MoneyMoney Web Banking Extension (Beta 0.9, Cookie-Import)
-- https://www.fidelity.com
-- Dokumentation: docs/LUA-EXTENSIONS.md
-- API: https://moneymoney.app/api/webbanking/
--

WebBanking{
  version     = 0.91,
  url         = "https://www.fidelity.com",
  services    = {"Fidelity"},
  description = "Fidelity Investments — Beta (Cookie-Import)"
}

local CONSTANTS = {
  loginApi = "https://ecaap.fidelity.com/user/factor/password/authentication",
  sessionApi = "https://ecaap.fidelity.com/user/session/login",
  graphqlApi = "https://digital.fidelity.com/ftgw/digital/picoserver/api/graphql",
  activityApi = "https://digital.fidelity.com/ftgw/digital/webactivity/api/graphql",
  documentsApi = "https://digital.fidelity.com/ftgw/digital/documents/api/graphql",
  portfolioSummary = "https://digital.fidelity.com/ftgw/digital/portfolio/summary",
  portfolioGetContextApi = "https://digital.fidelity.com/ftgw/digital/portfolio/api/GetContext",
  assetAllocationApi = "https://digital.fidelity.com/ftgw/digital/performance-api/v1/asset-allocation",
  activityPage = "https://digital.fidelity.com/ftgw/digital/portfolio/activity",
  documentsPage = "https://digital.fidelity.com/ftgw/digital/portfolio/documents",
  logoutUrl = "https://www.fidelity.com/logout"
}

local connection
local session = { cookies = "", persistedConnection = false }

local function extractCookieValue(cookieString, cookieName)
  if not cookieString or cookieString == "" or not cookieName or cookieName == "" then
    return nil
  end

  -- Cookie-Format ist i.d.R. "a=b; c=d". Wir parsen robust via Split & Key-Vergleich.
  for part in cookieString:gmatch("([^;]+)") do
    -- trim
    local token = part:match("^%s*(.-)%s*$")
    if token and token ~= "" then
      local k, v = token:match("^([^=]+)=(.*)$")
      if k and v and k == cookieName then
        local trimmedV = v:match("^%s*(.-)%s*$")
        if trimmedV and trimmedV ~= "" then
          return trimmedV
        end
        return nil
      end
    end
  end

  return nil
end

local function trimCookiePart(value)
  if value == nil then
    return ""
  end
  return tostring(value):match("^%s*(.-)%s*$")
end

-- Cookie Header-Merging:
-- - bestehende Session-Cookies bleiben erhalten
-- - neue Cookies überschreiben nur den jeweiligen Cookie-Wert (per Name)
-- - Cookie-Reihenfolge bleibt möglichst stabil (erst vorhandene, dann neue)
local function mergeCookies(existingCookies, newCookies)
  existingCookies = existingCookies or ""
  newCookies = newCookies or ""
  if existingCookies == "" then
    return newCookies
  end
  if newCookies == "" then
    return existingCookies
  end

  local existingParts = {}
  local existingIndex = {}
  for part in existingCookies:gmatch("([^;]+)") do
    local token = trimCookiePart(part)
    if token ~= "" then
      local k, v = token:match("^([^=]+)=(.*)$")
      k = trimCookiePart(k)
      v = trimCookiePart(v)
      if k ~= "" then
        existingIndex[k] = #existingParts + 1
        existingParts[#existingParts + 1] = { name = k, value = v }
      end
    end
  end

  local newMap = {}
  local newOrder = {}
  local newIndex = {}
  for part in newCookies:gmatch("([^;]+)") do
    local token = trimCookiePart(part)
    if token ~= "" then
      local k, v = token:match("^([^=]+)=(.*)$")
      k = trimCookiePart(k)
      v = trimCookiePart(v)
      if k ~= "" and v ~= "" then
        newMap[k] = v
        if newIndex[k] == nil then
          newIndex[k] = true
          newOrder[#newOrder + 1] = k
        end
      end
    end
  end

  -- Update vorhandene Teile.
  for i = 1, #existingParts do
    local name = existingParts[i].name
    if newMap[name] ~= nil then
      existingParts[i].value = newMap[name]
    end
  end

  -- Neue Cookie-Namen anhängen.
  for i = 1, #newOrder do
    local name = newOrder[i]
    if existingIndex[name] == nil then
      existingParts[#existingParts + 1] = { name = name, value = newMap[name] }
    end
  end

  local merged = {}
  for i = 1, #existingParts do
    merged[i] = existingParts[i].name .. "=" .. existingParts[i].value
  end

  return table.concat(merged, "; ")
end

local function getContextQuery()
  return {
    operationName = "GetContext",
    variables = {},
    query = [[query GetContext {
      getContext {
        person {
          assets {
            acctNum
            acctType
            acctSubType
            acctSubTypeDesc
            gainLossBalanceDetail {
              totalMarketVal
              __typename
            }
            __typename
          }
          __typename
        }
        __typename
      }
    }]]
  }
end

local function isAuthenticatedViaGraphql()
  if not session.cookies or session.cookies == "" then
    return false
  end

  local headers = {
    ["Accept"] = "*/*",
    ["Content-Type"] = "application/json",
    ["Cookie"] = session.cookies,
    ["Origin"] = "https://digital.fidelity.com",
    ["Referer"] = CONSTANTS.portfolioSummary,
    ["apollographql-client-version"] = "0.0.0"
  }

  local response, _ = connection:request(
    "POST",
    CONSTANTS.graphqlApi .. "?ref_at=portsum",
    JSON():set(getContextQuery()):json(),
    "application/json",
    headers
  )

  if not response or type(response) ~= "string" then
    return false
  end

  local success, data = pcall(function() return JSON(response):dictionary() end)
  if not success or not data or not data.data or not data.data.getContext then
    return false
  end

  local person = data.data.getContext.person
  local assets = person and person.assets
  return type(assets) == "table" and #assets > 0
end

local function isAuthenticatedViaPortfolioGetContext()
  if not session.cookies or session.cookies == "" then
    return false
  end

  local headers = {
    ["Accept"] = "*/*",
    ["Content-Type"] = "application/json",
    ["Cookie"] = session.cookies,
    ["Origin"] = "https://digital.fidelity.com",
    ["Referer"] = CONSTANTS.portfolioSummary
  }

  local response, _, mimeType = connection:request(
    "POST",
    CONSTANTS.portfolioGetContextApi,
    JSON():set({}):json(),
    "application/json",
    headers
  )

  if not response or type(response) ~= "string" then
    return false
  end

  if response:find("<!doctype html", 1, false) or (mimeType and mimeType:find("html")) then
    return false
  end

  local success, data = pcall(function() return JSON(response):dictionary() end)
  if not success or not data then
    return false
  end

  -- Typical HAR contains totalMarketVal and/or assets-containing context.
  if data.totalMarketVal ~= nil then
    return true
  end

  if data.getContext and data.getContext.person and data.getContext.person.assets then
    return type(data.getContext.person.assets) == "table"
  end

  return false
end

local function isAuthenticated()
  if isAuthenticatedViaGraphql() then
    return true
  end

  MM.printStatus("Cookie-Validierung via GraphQL fehlgeschlagen; versuche GetContext...")
  return isAuthenticatedViaPortfolioGetContext()
end

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and (bankCode == "Fidelity" or bankCode == "Fidelity Investments")
end

function InitializeSession(protocol, bankCode, username, username2, password, username3)
  local storage = rawget(_G, "LocalStorage")
  local accountKey = username or ""
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

  -- Apply in case we reused an existing connection object.
  connection.language = "en-US"
  connection.useragent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"

  -- Cookie import mode
  if password and password:match("^COOKIE:") then
    return loginWithImportedCookies(password:sub(8))
  end

  -- If persisted cookies are still valid, skip the bot-protected login flow.
  session.cookies = mergeCookies(session.cookies, connection:getCookies() or "")
  if session.cookies ~= "" and (session.cookies:match("ATC") or session.cookies:match("ET")) then
    if isAuthenticated() then
      return nil
    end
  end

  if username == "" or password == "" or username == nil or password == nil then
    return "Cookie-Import erforderlich: Passwort = COOKIE:ATC=...;ET=...\n\n"
      .. directLoginUnavailableMessage()
  end

  return directLoginUnavailableMessage()
end

function directLoginUnavailableMessage()
  return "Direct-Login (Username/Passwort) ist in Lua ohne Browser-Runtime nicht möglich.\n\n"
    .. "Fidelity schützt die Login-API (ecaap.fidelity.com) mit Akamai Bot Manager "
    .. "(_abck, bm_* Cookies) und Multi-Faktor-Authentifizierung — "
    .. "nicht nachbaubar per reinem HTTP.\n\n"
    .. "Cookie-Import (empfohlen):\n"
    .. "1. Im Browser bei digital.fidelity.com einloggen (inkl. MFA)\n"
    .. "2. Cookies exportieren (HAR oder Tampermonkey)\n"
    .. "3. MoneyMoney Passwort: COOKIE:ATC=...;ET=...\n\n"
    .. "HAR: python3 scripts/extract-fidelity-cookies.py login.har\n\n"
    .. "Für Direct-Login fehlt die Engine-API WebbankingBrowser.\n"
    .. "Details: docs/ENGINE-API-GAPS.md"
end

-- Für künftige WebbankingBrowser-Anbindung; derzeit nicht aufgerufen (Akamai/MFA).
function performFidelityPasswordLogin(username, password)
  MM.printStatus("Logging in to Fidelity...")

  local _, _ = connection:request("GET", "https://digital.fidelity.com/prgw/digital/signin/retail", nil, nil, {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9"
  })
  session.cookies = mergeCookies(session.cookies, connection:getCookies() or "")

  local loginBody = JSON():set({
    username = username,
    password = password,
    deviceInfo = { deviceType = "browser", browser = "Safari", os = "MacOS" }
  }):json()

  local loginHeaders = {
    ["Accept"] = "*/*",
    ["Content-Type"] = "application/json",
    ["Cookie"] = session.cookies,
    ["Origin"] = "https://digital.fidelity.com",
    ["Referer"] = "https://digital.fidelity.com/",
    ["AppId"] = "RETAIL-CC-LOGIN-SDK",
    ["Token-Location"] = "HEADER",
    ["Accept-Token-Type"] = "ET",
    ["Accept-Token-Location"] = "HEADER"
  }

  local loginResponse, _, mimeType = connection:request("POST", CONSTANTS.loginApi, loginBody, "application/json", loginHeaders)
  session.cookies = mergeCookies(session.cookies, connection:getCookies() or session.cookies)

  if not loginResponse then
    return "Login failed: No response from server"
  end

  if mimeType and mimeType:find("json") then
    local success, jsonData = pcall(function() return JSON(loginResponse):dictionary() end)
    if success and jsonData then
      if jsonData.sysMsgs and jsonData.sysMsgs.sysMsg then
        local sysMsg = jsonData.sysMsgs.sysMsg[1] or jsonData.sysMsgs.sysMsg
        if sysMsg then
          return "Login failed: " .. (sysMsg.message or sysMsg.detail or "Unknown error")
        end
      end
      if jsonData.error or jsonData.errorCode then
        return LoginFailed
      end
      if jsonData.token or jsonData.accessToken then
        return nil
      end
    end
  end

  if session.cookies:match("ATC") or session.cookies:match("ET") then
    MM.printStatus("Login successful")
    return nil
  end

  return "Login failed. Try Cookie Import mode with 'COOKIE:' prefix."
end

function loginWithImportedCookies(cookieString)
  MM.printStatus("Using imported cookies...")

  -- Convert comma-separated to semicolon-separated if needed
  local formattedCookies = cookieString:gsub("^%s*(.-)%s*$", "%1")
  if formattedCookies:match(",") and not formattedCookies:match(";") then
    formattedCookies = formattedCookies:gsub("%s*,%s*", "; ")
  end

  if not formattedCookies:match("=") then
    return "Invalid cookie format. Use: name=value;name2=value2"
  end

  session.cookies = formattedCookies

  if isAuthenticated() then
    MM.printStatus("Cookie import successful")
    return nil
  end

  return "Cookie import failed. Please copy fresh cookies from browser."
end

function ListAccounts(knownAccounts)
  MM.printStatus("Fetching Fidelity accounts...")
  local headers = {
    ["Accept"] = "*/*",
    ["Content-Type"] = "application/json",
    ["Cookie"] = session.cookies,
    ["Origin"] = "https://digital.fidelity.com",
    ["Referer"] = CONSTANTS.portfolioSummary
  }

  local response, _, mimeType = connection:request(
    "POST",
    CONSTANTS.portfolioGetContextApi,
    JSON():set({}):json(),
    "application/json",
    headers
  )
  local newCookies = connection:getCookies() or ""
  if newCookies ~= "" and extractCookieValue(newCookies, "portsum_.csrf") then
    session.cookies = mergeCookies(session.cookies, newCookies)
  end

  if not response or type(response) ~= "string" or (mimeType and mimeType:find("html")) then
    return "Failed to fetch accounts"
  end

  local accounts = {}
  local success, data = pcall(function() return JSON(response):dictionary() end)
  local person = data and data.getContext and data.getContext.person or nil
  local assets = person and person.assets or nil

  if success and assets and type(assets) == "table" then
    for _, acc in ipairs(assets) do
      local acctTypeDesc = acc.acctSubTypeDesc or acc.acctType or "Account"
      table.insert(accounts, {
        name = "Fidelity " .. acctTypeDesc,
        accountNumber = acc.acctNum,
        accountType = acc.acctType or "Brokerage",
        accountSubType = acc.acctSubType or "Mutual Fund",
        portfolio = true,
        currency = "USD",
        type = AccountTypePortfolio,
        bankCode = "Fidelity"
      })
    end
  end

  if #accounts == 0 then
    return "No accounts found"
  end

  return accounts
end

function RefreshAccount(account, since)
  if not account or not account.accountNumber then
    return { balance = 0, securities = {} }
  end

  MM.printStatus("Refreshing account: " .. account.name)

  local headers = {
    ["Accept"] = "*/*",
    ["Content-Type"] = "application/json",
    ["Cookie"] = session.cookies,
    ["Origin"] = "https://digital.fidelity.com",
    ["Referer"] = CONSTANTS.portfolioSummary,
    ["apollographql-client-version"] = "0.0.0"
  }

  local function fetchGraphqlPositions()
    local positionsQuery = {
      operationName = "GetPositions",
      variables = {
        acctList = {
          {
            acctNum = account.accountNumber,
            acctType = account.accountType or "Brokerage",
            acctSubType = account.accountSubType or "Mutual Fund",
            preferenceDetail = false
          }
        },
        customerId = ""
      },
      query = [[query GetPositions($acctList: [PositionAccountInput], $customerId: String) {
        getPosition(acctList: $acctList, customerId: $customerId) {
          position {
            acctDetails {
              acctDetail {
                acctNum
                positionDetails {
                  positionDetail {
                    symbol
                    cusip
                    securityDescription
                    quantity
                    marketValDetail {
                      marketVal
                      totalGainLoss
                      __typename
                    }
                    __typename
                  }
                  __typename
                }
                __typename
              }
              __typename
            }
            __typename
          }
          topBottomPositions {
            symbol
            lastPrice
            __typename
          }
          __typename
        }
      }]]
    }

    local response, _, mimeType = connection:request(
      "POST",
      CONSTANTS.graphqlApi .. "?ref_at=portsum",
      JSON():set(positionsQuery):json(),
      "application/json",
      headers
    )
    -- GraphQL kann fehlschlagen (z.B. 404) und dabei kann `connection:getCookies()`
    -- ggf. das Cookie-Jar wieder auf einen weniger vollständigen Stand bringen
    -- (fehlende portsum_.csrf Cookies). Für den REST-Fallback ist dann
    -- die ursprüngliche `session.cookies` (aus Cookie-Import) entscheidend.
    local newCookies = connection:getCookies() or ""
    if newCookies ~= "" and extractCookieValue(newCookies, "portsum_.csrf") then
      -- Nur aktualisieren, wenn wirklich der kritische portsum_.csrf Wert dabei ist.
      -- Sonst kann es passieren, dass nach einem GraphQL-Fehlschlag nur Teil-Cookies
      -- im Jar landen und der REST-Fallback dann "ports=false" sieht.
      session.cookies = mergeCookies(session.cookies, newCookies)
    end
    if not response or type(response) ~= "string" then
      return nil
    end

    if response:find("<!doctype html", 1, false) or (mimeType and mimeType:find("html")) then
      return nil
    end

    local success, data = pcall(function() return JSON(response):dictionary() end)
    if not success or not data or not data.data or not data.data.getPosition then
      return nil
    end

    return data
  end

  local localData = fetchGraphqlPositions()
  if localData then
    local securities = {}
    local totalBalance = 0
    local priceLookup = {}

    if localData.data.getPosition.topBottomPositions then
      for _, pos in ipairs(localData.data.getPosition.topBottomPositions) do
        if pos.symbol and pos.lastPrice then
          priceLookup[pos.symbol] = tonumber(pos.lastPrice) or 0
        end
      end
    end

    if localData.data.getPosition.position and localData.data.getPosition.position.acctDetails and localData.data.getPosition.position.acctDetails.acctDetail then
      for _, acct in ipairs(localData.data.getPosition.position.acctDetails.acctDetail) do
        if acct.positionDetails and acct.positionDetails.positionDetail then
          for _, pos in ipairs(acct.positionDetails.positionDetail) do
            local symbol = pos.symbol or ""
            local quantity = tonumber(pos.quantity) or 0
            local marketVal = 0
            local totalGainLoss = 0

            if pos.marketValDetail then
              marketVal = tonumber(pos.marketValDetail.marketVal) or 0
              totalGainLoss = tonumber(pos.marketValDetail.totalGainLoss) or 0
            end

            local currentPrice = priceLookup[symbol] or 0
            if currentPrice == 0 and quantity > 0 then
              currentPrice = marketVal / quantity
            end

            local purchasePrice = 0
            if quantity > 0 and marketVal > 0 then
              local costBasis = marketVal - totalGainLoss
              purchasePrice = costBasis / quantity
            end

            table.insert(securities, {
              name = pos.securityDescription or symbol or "Unknown",
              isin = pos.cusip or "",
              securityNumber = symbol,
              quantity = quantity,
              price = currentPrice,
              purchasePrice = purchasePrice,
              amount = marketVal,
              currencyOfPrice = "USD",
              currencyOfOriginalAmount = "USD"
            })

            totalBalance = totalBalance + marketVal
          end
        end
      end
    end

    return { balance = totalBalance, securities = securities }
  end

  -- REST-Fallback: asset-allocation liefert mindestens Marktwerte (Balance).
  local restHeadersBase = {
    -- HAR (digital.fidelity.com/ftgw/digital/portfolio/performance) verwendet eine "json, text/plain"-Accept-Matrix
    ["Accept"] = "application/json, text/plain, */*",
    ["Content-Type"] = "application/json",
    ["Cookie"] = session.cookies,
    ["Origin"] = "https://digital.fidelity.com",
    -- Für performance-api sind Referer/Context relevant.
    ["Referer"] = "https://digital.fidelity.com/ftgw/digital/portfolio/performance",
    -- In HAR ist bei vielen performance-api Calls zusätzlich ein IP-Override Header gesetzt.
    ["x-override-ip"] = "true",
    ["X-Requested-With"] = "XMLHttpRequest"
  }

  local body = {
    includeAggregate = true,
    includeHoldingsDetails = true,
    includeGranular = true,
    excludeEquityStyle = false,
    excludeBondStyle = false,
    accounts = {
      {
        accountNum = account.accountNumber,
        -- Fidelitys `asset-allocation` scheint diese Felder (zumindest im HAR) für die Anfrageform
        -- eng zu erwarten; deshalb konstant setzen und nur `accountNum` variieren.
        accountType = "Brokerage",
        accountSubType = "Mutual Fund"
      }
    }
  }

  local csrfPorts = extractCookieValue(session.cookies, "portsum_.csrf")
  local csrfPortsum = extractCookieValue(session.cookies, "PORTSUM_XSRF-TOKEN")

  local function isHtmlLogin(resp, mt)
    if not resp or type(resp) ~= "string" then
      return false
    end
    return resp:find("<!doctype html", 1, false)
      or (mt and mt:find("html"))
      or (resp:find("<html", 1, false) ~= nil)
  end

  local function fetchAssetAllocationWithCsrf(csrfToken)
    local restHeaders = {}
    for k, v in pairs(restHeadersBase) do
      restHeaders[k] = v
    end
    if csrfToken then
      -- Einige Fidelity-Endpunkte akzeptieren "x-csrf-token" statt "X-XSRF-TOKEN".
      restHeaders["x-csrf-token"] = csrfToken
    end

    local response, _, mimeType = connection:request(
      "POST",
      CONSTANTS.assetAllocationApi,
      JSON():set(body):json(),
      "application/json",
      restHeaders
    )
    local newCookies = connection:getCookies() or ""
    if newCookies ~= "" and extractCookieValue(newCookies, "portsum_.csrf") then
      session.cookies = mergeCookies(session.cookies, newCookies)
    end

    if not response or type(response) ~= "string" then
      return nil, mimeType
    end
    return response, mimeType
  end

  -- Deterministisch: bevorzugt PORTSUM_XSRF-TOKEN, sonst portsum_.csrf.
  local csrfTokenPreferred = csrfPortsum or csrfPorts
  local response, mimeType = fetchAssetAllocationWithCsrf(csrfTokenPreferred)

  if not response or type(response) ~= "string" then
    return { balance = 0, securities = {} }
  end

  if isHtmlLogin(response, mimeType) then
    return "Fidelity: performance-api Session ungültig (Login-Seite bekommen). Bitte Cookie Import mit frischen Cookies wiederholen (PORTSUM_XSRF-TOKEN / portsum_.csrf prüfen)."
  end

  local success, data = pcall(function() return JSON(response):dictionary() end)
  if not success or not data then
    return { balance = 0, securities = {} }
  end

  -- Fidelity liefert asset-allocation oft als { assetAllocation: { ... } }.
  local payload = data
  if data.assetAllocation and type(data.assetAllocation) == "table" then
    payload = data.assetAllocation
  end

  local totalBalance = tonumber(payload.overallMarketValue) or 0
  local holdings = payload.holdingsDetails
  if not holdings and payload.aggregateStyleDetail and payload.aggregateStyleDetail.holdingDetails then
    holdings = payload.aggregateStyleDetail.holdingDetails
  end

  if totalBalance == 0 and holdings and type(holdings) == "table" then
    -- Fallback: Balance aus holdingsDetails aufsummieren.
    for _, h in ipairs(holdings) do
      local marketValue = tonumber(h.marketValue) or 0
      totalBalance = totalBalance + marketValue
    end
  end

  local securities = {}
  if holdings and type(holdings) == "table" then
    for _, h in ipairs(holdings) do
      local symbol = h.symbol or ""
      local name = h.longName or h.name or symbol
      if not name or name == "" then
        name = "Unknown"
      end

      local quantity = tonumber(h.quantity) or 0
      local marketValue = tonumber(h.marketValue) or 0
      local rawPrice = tonumber(h.price)
      local price = rawPrice or 0

      -- Wenn Preis fehlt, kann man ihn aus Marktwert/Anzahl ableiten.
      if rawPrice == nil and quantity > 0 then
        price = marketValue / quantity
      end

      table.insert(securities, {
        name = name,
        isin = h.cusip or "",
        securityNumber = symbol,
        quantity = quantity,
        price = price,
        purchasePrice = 0,
        amount = marketValue,
        currencyOfPrice = "USD",
        currencyOfOriginalAmount = "USD"
      })
    end
  end

  return { balance = totalBalance, securities = securities }
end

function EndSession()
  -- If we keep a persisted connection in LocalStorage, avoid logging out,
  -- otherwise we would invalidate the session cookie jar.
  if session.cookies and session.cookies ~= "" and not session.persistedConnection then
    pcall(function()
      connection:request("GET", CONSTANTS.logoutUrl, nil, nil, { ["Cookie"] = session.cookies })
    end)
  end
  MM.printStatus("Logged out")
end
