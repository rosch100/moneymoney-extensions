-- Unit-Tests für Login-Hilfsfunktionen in `extensions/Bank of America.lua`.

function WebBanking(_) end

ProtocolWebBanking = "WebBanking"
LoginFailed = "LoginFailed"

AccountTypeGiro = 1
AccountTypeCreditCard = 3

Connection = function()
  return {
    language = "en-US",
    useragent = "test",
    request = function()
      return nil
    end,
    getCookies = function()
      return ""
    end,
  }
end

MM = {
  printStatus = function(msg)
    -- Test-Stubs schlucken Debug-Ausgabe
  end,
  urlencode = function(str)
    return (tostring(str):gsub(" ", "+"))
  end,
  base64Encode = function(data)
    return "b64:" .. data
  end,
  aes128encrypt = function(key, iv, data, mode)
    if key and data then
      return "cipher:" .. data .. ":" .. tostring(mode or "default")
    end
    return nil
  end,
  rsaPkcs8decode = function(pemOrDer)
    if type(pemOrDer) == "string" and pemOrDer:find("PUBLIC KEY") then
      return { n = "mod", e = "exp" }
    end
    return nil
  end,
  rsaEncrypt = function(keyTable, plaintext, paddingSpec)
    if keyTable and plaintext and paddingSpec then
      return "cipher:" .. plaintext .. ":" .. paddingSpec
    end
    return nil
  end,
}

local function assertEq(actual, expected, label)
  if actual == expected then
    print("OK    " .. label .. " = " .. tostring(actual))
  else
    print("FAIL  " .. label .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    os.exit(1)
  end
end

local function assertTrue(value, label)
  if value then
    print("OK    " .. label)
  else
    print("FAIL  " .. label)
    os.exit(1)
  end
end

JSON = function(str)
  return {
    dictionary = function()
      local pageId = str:match('"xswPageId"%s*:%s*"([^"]+)"')
      if pageId then
        return { xswPageId = pageId }
      end
      return {}
    end,
    array = function()
      return {}
    end,
  }
end

dofile("extensions/Bank of America.lua")

assertTrue(canUseAcwCrypto(), "canUseAcwCrypto")
assertTrue(canUseRsaLogin(), "canUseRsaLogin")

local padded = zeroPadToBlockSize("selectedContact|0|contactType|text", 16)
assertEq(#padded, 48, "zeroPadToBlockSize.length")

local encrypted, encErr = acwAesEncrypt("123456", "92CE60497D95E320")
assertTrue(encrypted ~= nil and encrypted:match("^b64:"), "acwAesEncrypt")
assertEq(encErr, nil, "acwAesEncrypt.error")

local csrf = parseCsrfFromSignOnScreen('<input name="csrfTokenHidden" value="abc123def45678" id="csrfTokenHidden"/>')
assertEq(csrf, "abc123def45678", "parseCsrfFromSignOnScreen")

local key = parseAcwEncryptKey('var xswInitSettings = { acwEncryptKey:"92CE60497D95E320" }')
assertEq(key, "92CE60497D95E320", "parseAcwEncryptKey")

local jsonp = parseJsonpPayload('jQuery123({"xswPageId":"ok"})')
assertTrue(jsonp and jsonp.xswPageId == "ok", "parseJsonpPayload")

local token = extractHiddenInputValue("<input name='validationToken' value='abc%2Bdef'/>", "validationToken")
assertEq(token, "abc%2Bdef", "extractHiddenInputValue")

assertTrue(isSignOnSuccessRedirect("https://secure.bankofamerica.com/login/sign-in/signOnSuccessRedirect.go"), "isSignOnSuccessRedirect")
assertTrue(isSignOnCredentialError("https://secure.bankofamerica.com/login/sign-in/signOnV2Screen.go?msg=InvalidCredentialsExceptionV2"), "isSignOnCredentialError")
assertTrue(isSignOnCredentialErrorPage("<p>The information you entered doesn't match our records.</p>"), "isSignOnCredentialErrorPage")

local snippet = extractSignOnErrorSnippet("<p class=\"TLu_ERROR\">The information you entered doesn't match our records.</p>")
assertTrue(snippet and snippet:match("doesn't match"), "extractSignOnErrorSnippet")

local credSummary = boaDebugSummarizeCredentials("user123", "secret")
assertTrue(credSummary:match("onlineId%.len=7"), "boaDebugSummarizeCredentials.onlineId")
assertTrue(credSummary:match("passcode%.len=6"), "boaDebugSummarizeCredentials.passcode")
assertTrue(credSummary:match("WARN") == nil, "boaDebugSummarizeCredentials.noWarn")

local emptySummary = boaDebugSummarizeCredentials("", "")
assertTrue(emptySummary:match("WARN onlineId leer"), "boaDebugSummarizeCredentials.emptyUser")
assertTrue(emptySummary:match("WARN passcode leer"), "boaDebugSummarizeCredentials.emptyPass")

local blockedMsg = directLoginUnavailableMessage()
assertTrue(blockedMsg:match("Cookie%-Import"), "directLoginUnavailableMessage")
assertTrue(blockedMsg:match("WebbankingBrowser"), "directLoginUnavailableMessage.browser")

local formBody = buildSignOnFormBody("csrf123456789abc", "user123", "secretpass")
assertTrue(formBody:match("onlineId="), "buildSignOnFormBody.onlineId")
assertTrue(formBody:match("_ib="), "buildSignOnFormBody._ib")
assertTrue(not formBody:match("f_variable="), "buildSignOnFormBody.noFingerprint")

local sessionKey = {
  keyId = "hsm_enc_v1_authhub-key",
  publicKey = "MIIBIjAN",
  algo = "RSA/NONE/OAEPWithSHA256AndMGF1Padding",
}

local envelope = buildCipherEnvelope(sessionKey, "cipherbytes")
assertTrue(envelope ~= nil and envelope:match("^b64:"), "buildCipherEnvelope")

local cipherValue, cipherError = encryptCredential(sessionKey, "user123")
assertTrue(cipherValue ~= nil, "encryptCredential")
assertTrue(cipherValue:match("^b64:"), "encryptCredential.base64")
assertEq(cipherError, nil, "encryptCredential.error")

local ra = buildClientSignalsRa()
assertTrue(type(ra) == "string" and ra ~= "", "buildClientSignalsRa")

assertEq(parseLoginApiError('{"errorInfo":[{"code":"invalid","description":"Bad login"}]}'), "Bad login", "parseLoginApiError")
assertTrue(isLoginCompletionOk('{"completion":{"code":"100","value":"ALLOW"}}'), "isLoginCompletionOk")

local contact = extractSecuredContactPoint('{"securedContactPoints":[{"deliveryMethod":"TEXT","maskedContactPoint":{"value":"XXX-1234"}}]}')
assertEq(contact.deliveryMethod, "TEXT", "extractSecuredContactPoint")

assertTrue(isAuthenticatedAccountPage('<html>Ending in 1234 balance</html>'), "isAuthenticatedAccountPage.ok")
assertTrue(not isAuthenticatedAccountPage('<html>Sign In</html>'), "isAuthenticatedAccountPage.login")

print("All BoA login helper tests passed.")
