# Offene Punkte für Direct-Login (Beta 0.9)

Cookie-Import funktioniert. Für Username/Passwort-Login in Lua fehlen Engine-Erweiterungen.

| Extension | Blocker | Fehlende Engine-API |
|-----------|---------|---------------------|
| Bank of America | Anti-Fraud-Fingerprint nur im Browser (`signOnV2.go`) | `WebbankingBrowser` |
| Fidelity | Akamai (`_abck`, `bm_*`) + MFA | `WebbankingBrowser` |
| MLP Versicherungen | JWE (`RSA-OAEP-512`, `A256GCM`) | `MM.aes256gcm`; RSA-OAEP mit SHA-512 wird bevorzugt, SHA-256 ist als kompatible Variante implementiert; alternativ `WebbankingBrowser` |

Extension-Details: [LUA-EXTENSIONS.md](LUA-EXTENSIONS.md)

## MLP — fehlende Krypto-APIs

JWE-Parameter: `alg` RSA-OAEP-512, `enc` A256GCM, `kid` `cas-pin-encryption-prod-v2`

```lua
MM.aes256gcm(key, iv, plaintext, aad?) → ciphertext, tag   -- fehlt
MM.rsaEncrypt(keyTable, plaintext, "pkcs1-oaep sha512") → ciphertext   -- bevorzugt
MM.rsaEncrypt(keyTable, plaintext, "pkcs1-oaep sha256") → ciphertext   -- implementierte Alternative
```

## WebbankingBrowser — Beispiel

```lua
WebbankingBrowser{
  allowedUrls = { "https://example.bank/*" },
  startUrl = "https://example.bank/login",
  successUrlPattern = "https://example.bank/accounts/.*",
  onSuccess = function(cookies, connection) end,
}
```
