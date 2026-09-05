# MLP JWE ready for MoneyMoney crypto APIs

**Status:** Implementiert (Branch `feature/mm-crypto-jwe-ready`)

## Goal

MLP-JWE (`alg=RSA-OAEP-512`, `enc=A256GCM`) nur mit korrektem Padding und
`MM.aes256gcm`, sobald MoneyMoney die angekündigten APIs liefert.

## Problem

`encryptCekWithRsa` fiel auf `pkcs1-oaep sha256` zurück, während der JWE-Header
weiterhin `RSA-OAEP-512` behauptete.

## Approach

1. CEK-Verschlüsselung nur mit `"pkcs1-oaep sha512"`.
2. JWE-Capability: `MM.random`, `MM.base64urlencode`, `MM.rsaEncrypt`,
   `MM.aes256gcm`/`aesgcm`, und erfolgreicher OAEP-SHA-512-Probe.
3. Login: JWE wenn ready; sonst Klartext, dann Cookie (unverändert).
4. Scope: nur MLP (+ Hub-Docs). BoA/Fidelity nicht betroffen.

## Out of scope

- Ed25519
- Fidelity / WebbankingBrowser
- BoA Sparta (nutzt SHA-256)
