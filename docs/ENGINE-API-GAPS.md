# Fehlende MoneyMoney-Engine-Funktionen

Drei Beta-Extensions (0.9) scheitern am **Direct-Login** (Username/Passwort in Lua ohne Browser). Cookie-Import nutzt vorhandene Engine-APIs; Details zu Login und Abruf stehen in [LUA-EXTENSIONS.md](LUA-EXTENSIONS.md).

Engine-Stand: MoneyMoney 2.4.71 (512)

## Übersicht

| Extension | Blocker | Fehlende Engine-API |
|-----------|---------|---------------------|
| [Bank of America](#bank-of-america) | Anti-Fraud-Fingerprint nur im Browser | `WebbankingBrowser` |
| [Fidelity](#fidelity) | Akamai Bot Manager + MFA | `WebbankingBrowser` |
| [MLP Versicherungen](#mlp-versicherungen) | JWE (`A256GCM`, `RSA-OAEP-512`) | `MM.aes256gcm`, `MM.rsaEncrypt` mit SHA-512; alternativ `WebbankingBrowser` |

---

## WebbankingBrowser

In der MoneyMoney-Binary existiert Infrastruktur für eingebetteten Browser und OAuth (`webbankingBrowser:allowedUrls`, `oAuthCallback`, `moneymoney-app://oauth…`). Für Lua-Extensions fehlt eine **dokumentierte, nutzbare API**.

**Ziel:** Nutzer authentifiziert sich im eingebetteten Browser (inkl. MFA). Die Extension übernimmt danach Session-Cookies in `connection` / `LocalStorage.connection`.

**Mindest-Anforderungen:**

| Anforderung | Beschreibung |
|-------------|--------------|
| URL-Whitelist | Pro Extension erlaubte Hosts/Pfade |
| Start-URL | Bank-Loginseite |
| Erfolgs-Erkennung | URL-Muster oder Callback, wenn Session steht |
| Cookie-Übernahme | Cookies in `connection` schreiben |

Beispiel-Skelett (exakte Signatur an die Engine anpassen):

```lua
WebbankingBrowser{
  allowedUrls = { "https://example.bank/*" },
  startUrl = "https://example.bank/login",
  successUrlPattern = "https://example.bank/accounts/.*",
  onSuccess = function(cookies, connection) end,
}
```

Betrifft: Bank of America, Fidelity; optional MLP (OAuth über `financepilot-pe.mlp.de`).

---

## Bank of America

**Extension:** `extensions/Bank of America.lua`

### Blocker

Der Login (`POST signOnV2.go`) verlangt neben User ID und Passwort **Anti-Fraud-Daten** vom JavaScript der Loginseite:

| Feld | Herkunft | In Lua nachbaubar? |
|------|----------|-------------------|
| `_ia` | BioCatch | Nein |
| `f_variable` | ThreatMetrix | Nein |
| `pm_fp` | Profiling Manager | Nein |
| `_sc` | Hashes geladener Skripte | Nein |
| `_ib` | UA, Paste-Flags | Ja |

Ohne die Browser-Felder antwortet BoA mit `InvalidCredentialsExceptionV2`, obwohl die Zugangsdaten korrekt sind. MFA (`MM.aes128encrypt`) scheitert am gleichen Punkt.

### Fehlende Engine-API

`WebbankingBrowser` für `secure.bankofamerica.com`.

### Vorhandene Engine-APIs (für den Login-Pfad relevant)

| API | Status |
|-----|--------|
| `connection:setCookie`, `connection:getCookies` | vorhanden |
| `LocalStorage.connection` | vorhanden |
| `MM.urlencode`, `MM.aes128encrypt` | vorhanden |

---

## Fidelity

**Extension:** `extensions/Fidelity.lua`

### Blocker

| Thema | Detail |
|-------|--------|
| Akamai Bot Manager | Cookies `_abck`, `bm_sz`, `bm_s`, `bm_sv` nur per Browser-JS |
| MFA | OTP-Schritte; Session erst nach abschließendem `POST /user/session/login` |
| Reines HTTP | Ohne Akamai: blockierte Antwort oder fehlende Session-Tokens |

### Fehlende Engine-API

`WebbankingBrowser` für `digital.fidelity.com` / `ecaap.fidelity.com`.

### Vorhandene Engine-APIs (für den Login-Pfad relevant)

| API | Status |
|-----|--------|
| `connection:getCookies`, Cookie-Header | vorhanden |
| `LocalStorage.connection` | vorhanden |

---

## MLP Versicherungen

**Extension:** `extensions/MLP Versicherungen.lua`

### Blocker: JWE-Login

Das Kundenportal erwartet Credentials als **JOSE/JWE** (`Content-Type: application/jose`):

| JWE-Parameter | Wert |
|---------------|------|
| `alg` | RSA-OAEP-512 |
| `enc` | A256GCM |
| `kid` | `cas-pin-encryption-prod-v2` (aus JWKS) |

### Fehlend: `MM.aes256gcm`

Benötigt für A256GCM (Payload + Authentication Tag).

**Status in 2.4.71:**

```
MM.aes256gcm  → nil
MM.aes128gcm  → nil
MM.aesgcm     → nil
MM.aes256encrypt(..., "aes256 gcm") → kein Roundtrip
```

**Vorschlag:**

```lua
MM.aes256gcm(key, iv, plaintext, aad?) → ciphertext, tag
-- key: 32 Byte, iv: 12 Byte, aad: JWE Protected Header (Base64URL)
```

### Fehlend: RSA-OAEP mit SHA-512

Benötigt für Verschlüsselung des Content Encryption Key mit dem MLP JWKS Public Key.

**Status:** `MM.rsaEncrypt` unterstützt `"pkcs1-oaep sha256"`, nicht `"pkcs1-oaep sha512"`.

**Vorschlag:**

```lua
MM.rsaEncrypt(keyTable, plaintext, "pkcs1-oaep sha512") → ciphertext
```

### Alternative

`WebbankingBrowser` für OAuth auf `financepilot-pe.mlp.de`, danach Cookie-Übernahme.

### Vorhandene Engine-APIs (für JWE relevant)

| API | Status |
|-----|--------|
| `MM.aes256encrypt` / `decrypt` (`"aes256 cbc"`) | vorhanden |
| `MM.rsaEncrypt` (`"pkcs1-oaep sha256"`) | vorhanden |
| `MM.random`, `MM.base64urlencode`, `MM.hmac256` | vorhanden |
| `connection:setCookie`, `connection:getCookies` | vorhanden |
| `LocalStorage.connection` | vorhanden |

---

## Priorität

1. **`WebbankingBrowser`** — Direct-Login für Bank of America und Fidelity; optional für MLP
2. **`MM.aes256gcm` + `pkcs1-oaep sha512`** — MLP Direct-Login ohne Browser

---

## OAuth / URL-Callback (Binary-Glue)

Extensions können interne Objective-C-Methoden nicht direkt aufrufen. Callback-Daten werden über `InitializeSession2(..., step, credentials, ...)` dispatcht.

Ablauf: URL-Ereignis → `LuaModules.processUrls` → OAuth-Controller → `LuaModules.oAuthCallback`

Relevante Strings aus der Binary:

- `UrlSchemeHandler.getUrl:withReplyEvent:`
- `GURL`
- `LuaModules.processUrls`
- `oAuthControllers`
- `LuaModules.oAuthCallback:`
- `moneymoney-app://oauth%@%@%@`
- `InitializeSession2`

Beispiel: `moneymoney-app://oauth@provider@state?code=abc&state=xyz`
