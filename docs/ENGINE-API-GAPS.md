# Offene Punkte für Direct-Login

Cookie-Import funktioniert. Für Username/Passwort-Login in Lua fehlen bzw. fehlten Engine-Erweiterungen.
Bei den Beta-Plugins bleibt Username/Passwort trotzdem verdrahtet, soweit möglich
(BoA Sparta, MLP JWE/Klartext); Fidelity ist durch Akamai in Lua blockiert.

| Extension | Blocker | Engine-API |
|-----------|---------|------------|
| Bank of America | Anti-Fraud-Fingerprint nur im Browser (`signOnV2.go`); Sparta-Login braucht RSA | `MM.rsaEncrypt`; `WebbankingBrowser` — **nicht geplant** (Stand Adams 2026-09) |
| Fidelity | Akamai (`_abck`, `bm_*`) + MFA | `WebbankingBrowser` — **nicht geplant** |
| MLP Versicherungen | JWE (`RSA-OAEP-512`, `A256GCM`); ohne Krypto: Klartext-Versuch, oft JOSE/403 | `MM.aes256encrypt(…, "aes256 gcm", aad)`; `MM.rsaEncrypt(…, "pkcs1-oaep sha512")` |

Branch `feature/mm-crypto-jwe-ready` (MLP): JWE nutzt **nur** OAEP-SHA-512 (kein SHA-256
unter `alg=RSA-OAEP-512`). Ab MoneyMoney **2.5.2** greifen `MM.aes256encrypt(…, "aes256 gcm", aad)`
und `MM.rsaEncrypt(…, "pkcs1-oaep sha512")` ohne weitere Padding-Wahl.

Extension-Repos: [LUA-EXTENSIONS.md](LUA-EXTENSIONS.md).

## MLP — Krypto-APIs

JWE-Parameter: `alg` RSA-OAEP-512, `enc` A256GCM, `kid` `cas-pin-encryption-prod-v2`

```lua
MM.aes256encrypt(key, iv, plaintext, "aes256 gcm", aad) → ciphertext, tag   -- MM ≥ 2.5.2
MM.rsaEncrypt(keyTable, plaintext, "pkcs1-oaep sha512") → ciphertext   -- MM ≥ 2.5.2
MM.rsaEncrypt(keyTable, plaintext, "pkcs1-oaep sha256") → ciphertext   -- vorhanden; MLP-JWE nutzt es nicht
MM.rsaDecrypt(...)  -- analog, inkl. sha512 ab 2.5.2
```

## Ed25519 (MoneyMoney ≥ 2.5.2)

```lua
MM.ecGenerateKeys("ed25519")
MM.ecSign(key, data, "eddsa")
MM.ecVerify(key, data, signature, "eddsa")
```

## WebbankingBrowser

Für Lua-Extensions **nicht geplant**. Dokumentierte Alternative: Extension gibt
eine `https://`-URL als Challenge zurück; MoneyMoney öffnet ein Fenster
(OAuth-Weiterleitung, Host muss freigeschaltet sein) und liefert nur den
Rückgabeparameter — keine Cookies.

Historisches API-Beispiel (nicht verfügbar):

```lua
WebbankingBrowser{
  allowedUrls = { "https://example.bank/*" },
  startUrl = "https://example.bank/login",
  successUrlPattern = "https://example.bank/accounts/.*",
  onSuccess = function(cookies, connection) end,
}
```
