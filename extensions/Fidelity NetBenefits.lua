WebBanking{
  version     = 0.12,
  url         = "https://www.fidelity.com",
  services    = {"Fidelity NetBenefits"},
  description = "Get securities and their current value from the Fidelity NetBenefits website"
}

local CONSTANTS = {
  homepage = "https://www.fidelity.com",
  login = "https://login.fidelity.com/ftgw/Fas/Fidelity/RtlCust/Login/Init",
  logout = "https://www.fidelity.com/logout",
  overview = "https://www.fidelity.com/account-overview",
  position = "https://www.fidelity.com/account-positions"
}

local g_cookies = ""

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Fidelity NetBenefits"
end

function InitializeSession(protocol, bankCode, username, username2, password, username3)
  local connection = Connection()
  connection:get(CONSTANTS.homepage)

  local url, postContent, contentType, headers = buildLoginRequest(username, password)
  local content = connection:request("POST", url, postContent, contentType, headers)

  if content:match("We are Sorry.*Technical Issue") then
    return "Fidelity is having technical issues or is throttling your logins. Please try again later."
  end

  g_cookies = connection:getCookies() or ""
end

function ListAccounts(knownAccounts)
  local connection = Connection()
  local html = HTML(connection:request("GET", CONSTANTS.homepage, nil, nil, {["Cookie"] = g_cookies}))

  local accountName = html:xpath('//*[@id="tile3"]/h2'):text()
  if not accountName or accountName == "" then
    return "Could not find account name. Please verify login was successful."
  end

  local stockPlanLink = html:xpath('//*[@id="espp-tables"]/div[contains(@class, "full-transaction-history")]//a'):attr("href")
  local accountNumber = stockPlanLink:match("?ACCOUNT=(%w+)_.*")

  if not accountNumber or accountNumber == "" then
    return "Could not find any Fidelity accounts. Make sure you have active positions in your account."
  end

  local subAccount = html:xpath('//*[@id="tile3"]/div[2]'):text():match(".*(%a%d+)$")

  return {{
    name = toTitleCase(accountName),
    accountNumber = accountNumber,
    subAccount = subAccount,
    portfolio = true,
    currency = "USD",
    type = AccountTypePortfolio
  }}
end

function RefreshAccount(account, since)
  if not account.accountNumber or account.accountNumber == "" then
    return "Could not refresh account: Invalid account number."
  end

  local headers = {
    ["Cookie"] = g_cookies,
    ["Accept"] = "application/json"
  }

  local connection = Connection()
  local response = connection:request("GET", CONSTANTS.position .. account.accountNumber, nil, nil, headers)
  local json = JSON(response):dictionary()

  return {
    balance = extractBalance(json),
    securities = extractSecurities(json)
  }
end

function EndSession()
  local connection = Connection()
  connection:request("GET", CONSTANTS.logout, nil, nil, {["Cookie"] = g_cookies})
  g_cookies = ""
end

function buildLoginRequest(username, password)
  local content = "username=" .. username .. "&password=" .. password .. "&SavedIdInd=N"
  local abck = "_abck=B0C2C284ED0000FBD02EC595F6E7BEDE~0~YAAQbplkX7sqg+19AQAA/mss8gfv0+1yssAIYX4JeFH09Cm/z4nwujGbqNFquNW5PeFKzcOspQqK6GqjT17SSS/N3Gul3L5E3sl20Jexeh6nEhUzoD2nmCwCceHCBRaE+TfZ9N53lCQh3f5GBzn2g5wKVjQWb8JIke0MFKtmbv5S9WrSQcMLBBQSvNcz3tdIDYxoNMT5aKEHYHQZI6zKJQajihZzKIW1Fw4R5Bs/pqoIYXWRZgMQu1AqfQSaEZwVwvn6M55buPglQu5CTGFCJgSE9qgoSNO365SgIFWnkGmBzJOEXm/XoxZBQt0bjUjLn91nmtCikgOY5AQS7Xj5tFol9o4yiEMCSljpVE/FYKBIT7lupiCN65WXRbPu/UXgLuOLClTF20MGGt884byal4dJvIxY0M8jo+Ya~-1~-1~-1; "
  local cookie = "JSESSIONID=" .. randomJsessionId() .. "; " .. abck

  return CONSTANTS.login, content, "application/x-www-form-urlencoded; charset=UTF-8", { Cookie = cookie }
end

function extractBalance(json)
  local details = json.accountDetails
  if not details then return 0 end

  local balance = details.displayAccountsBalance
  if not balance then return 0 end

  return balance.totalClosingMktVal and balance.totalClosingMktVal.value or 0
end

function extractSecurities(json)
  local exchangeRate = json.exchangeRate
  local toCurrency = exchangeRate and exchangeRate.toCurrency or "USD"
  local fromCurrency = exchangeRate and exchangeRate.fromCurrency or "USD"
  local rate = exchangeRate and exchangeRate.rate or 1

  local securities = {}
  local positions = json.position or {}

  for _, pos in pairs(positions) do
    local quantity = parseNumber(pos.quantity)
    if quantity == 0 then quantity = 1 end

    local security = {
      name = pos.secDesc or "Unknown",
      quantity = quantity,
      amount = pos.displayPositionBalance and pos.displayPositionBalance.closingMktValue and pos.displayPositionBalance.closingMktValue.value or 0,
      originalCurrencyAmount = pos.assetPositionBalance and pos.assetPositionBalance.closingMktValue and pos.assetPositionBalance.closingMktValue.value or 0,
      currencyOfOriginalAmount = fromCurrency,
      price = pos.displayPositionBalance and pos.displayPositionBalance.closingPrice and pos.displayPositionBalance.closingPrice.value or 0,
      exchangeRate = rate
    }

    local totalCostBasis = pos.displayPositionBalance and pos.displayPositionBalance.totalCostBasis and pos.displayPositionBalance.totalCostBasis.value
    if totalCostBasis then
      security.purchasePrice = totalCostBasis / quantity
    end

    table.insert(securities, security)
  end

  return securities
end

function parseNumber(str)
  if not str then return 0 end
  if type(str) == "number" then return str end

  local cleaned = str:gsub(",", "")
  return tonumber(cleaned) or 0
end

function toTitleCase(str)
  if not str then return "" end

  local result = {}
  local inWord = false

  for i = 1, #str do
    local char = str:sub(i, i)
    if inWord then
      table.insert(result, char:lower())
      inWord = not char:match("%s")
    else
      table.insert(result, char:upper())
      inWord = char:match("%S") ~= nil
    end
  end

  return table.concat(result)
end

function randomJsessionId()
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local length = 32
  local charTable = {}

  for c in chars:gmatch(".") do
    table.insert(charTable, c)
  end

  math.randomseed(os.time())

  local result = {}
  for i = 1, length do
    table.insert(result, charTable[math.random(1, #charTable)])
  end

  return table.concat(result)
end

-- SIGNATURE: MC0CFHIfFHe8ii5TZK6XSx+0/7xyxQvrAhUAlhdF/KAMB+rzav61p+KAWJxQ9JM=
