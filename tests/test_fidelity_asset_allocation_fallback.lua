-- Unit-Test: fidelity RefreshAccount GraphQL -> REST-Fallback

function WebBanking(_) end
ProtocolWebBanking = "WebBanking"

AccountTypePortfolio = 5
LoginFailed = "LoginFailed"

local capturedRequests = {}

local importedCookies = "ATC=ok; _abck=abck; PORTSUM_XSRF-TOKEN=token1; portsum_.csrf=token2;"

function Connection()
  return {
    language = "",
    useragent = "",
    getCookies = function()
      return importedCookies
    end,
    request = function(self, method, url, body, contentType, headers)
      capturedRequests[#capturedRequests + 1] = {
        method = method,
        url = url,
        body = body,
        headers = headers
      }

      -- Session validation (cookie import):
      if url and url:find("portfolio/api/GetContext", 1, true) then
        return "GETCONTEXT_OK", nil
      end

      if url and url:find("picoserver/api/graphql", 1, true) then
        -- Make GraphQL unusable so RefreshAccount falls back.
        return "<!doctype html><html>Not Found</html>", nil, "text/html"
      end

      -- REST fallback for holdings + overall balance:
      if url and url:find("performance-api/v1/asset-allocation", 1, true) then
        local csrf = headers and headers["x-csrf-token"] or nil
        if csrf == "token2" then
          return "<!doctype html><html>Login</html>", nil, "text/html"
        end
        return "ASSETALLOCATION_OK", nil, "application/json; charset=utf-8"
      end

      return "NOTHING", nil
    end
  }
end

MM = {
  printStatus = function(_) end,
  urlencode = function(s) return tostring(s) end
}

JSON = function(input)
  return {
    set = function(self, _)
      return self
    end,
    json = function()
      return "{}"
    end,
    dictionary = function()
      if input == "GETCONTEXT_OK" then
        return {
          totalMarketVal = "22060.27",
          getContext = {
            person = {
              assets = {
                {
                  acctNum = "2AN338907",
                  acctType = "Brokerage",
                  acctSubType = "Mutual Fund",
                  acctSubTypeDesc = "Account"
                }
              }
            }
          }
        }
      end

      if input == "ASSETALLOCATION_OK" then
        return {
          overallMarketValue = "22060.27",
          holdingsDetails = {
            {
              accountNum = "2AN338907",
              cusip = "315911743",
              symbol = "FSMAX",
              name = "Fidelity Extended Market Index Fund",
              marketValue = 22060.27
            }
          }
        }
      end

      error("unexpected JSON input")
    end
  }
end

dofile("extensions/Fidelity.lua")

-- Cookie import triggers InitializeSession and sets session.cookies.
local result = InitializeSession(
  ProtocolWebBanking,
  "Fidelity",
  nil,
  nil,
  "COOKIE:ATC=ok; _abck=abck; PORTSUM_XSRF-TOKEN=token1; portsum_.csrf=token2;",
  nil
)
if result ~= nil then
  print("FAIL InitializeSession: expected nil, got:", tostring(result))
  os.exit(1)
end

capturedRequests = {}

local account = {
  name = "Fidelity Test",
  accountNumber = "2AN338907",
  accountType = "Brokerage",
  accountSubType = "Mutual Fund"
}

local out = RefreshAccount(account, nil)

if type(out) ~= "table" then
  print("FAIL RefreshAccount: expected table")
  os.exit(1)
end

if tostring(out.balance) ~= "22060.27" then
  print("FAIL RefreshAccount.balance: expected=22060.27 actual=" .. tostring(out.balance))
  os.exit(1)
end

-- Verify fallback endpoint was called.
local assetCalls = {}
for _, req in ipairs(capturedRequests) do
  if req.url and req.url:find("performance-api/v1/asset-allocation", 1, true) then
    assetCalls[#assetCalls + 1] = req
  end
end

if #assetCalls < 1 then
  print("FAIL: asset-allocation fallback endpoint not called; captured requests:")
  for _, req in ipairs(capturedRequests) do
    print(req.method .. " " .. tostring(req.url))
    if req.headers and req.url and req.url:find("performance-api/v1/asset-allocation", 1, true) then
      print("  x-csrf-token=" .. tostring(req.headers["x-csrf-token"]))
    end
  end
  os.exit(1)
end

if #assetCalls ~= 1 then
  print("FAIL: expected exactly one asset-allocation call, got=" .. tostring(#assetCalls))
  os.exit(1)
end

if assetCalls[1].headers["x-csrf-token"] ~= "token1" then
  print("FAIL: asset-allocation call should use PORTSUM_XSRF-TOKEN token1")
  os.exit(1)
end

print("ALL FIDELITY ASSET-ALLOCATION FALLBACK UNIT TESTS PASSED")

