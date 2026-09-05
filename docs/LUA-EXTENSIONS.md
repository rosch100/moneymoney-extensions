# Lua-Extensions — Hub-Index

Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).
Installation und Cookie-Helper: [README](../README.md).

Die Lua-Quellen liegen in **eigenen Repositories**. Dieses Dokument ist nur der Hub-Index.

## Versionierung

| Version | Bedeutung |
|---------|-----------|
| **0.91 / 0.92 / 0.93** | Beta — Cookie-Import empfohlen; Username/Passwort bleibt, soweit Engine-APIs reichen |
| **1.01 / 1.02 / 1.03 / 1.09** | Direct-Login mit MFA (optional Cookie-Import); Shareview Multi-Login; Presidential 1.09 Private-Device-Persistenz |
| **2.0 / 2.01** | Amazon-Bestellungen (Service-Name `Amazon Bestellungen`); 2.01 Multi-Login-Isolation |

Signierte Fremdversionen entsprechen nicht automatisch den Eigenrepos
(siehe [README](../README.md#signiert-vs-eigenrepos)).

**Multi-Login:** Mehrere Bankzugänge derselben Extension mit unterschiedlichen
Logins — Spec
[2026-09-04-multi-login-localstorage-design.md](superpowers/specs/2026-09-04-multi-login-localstorage-design.md).

## Engine-Ablauf

1. `SupportsBank`
2. `InitializeSession` / `InitializeSession2`
3. `ListAccounts`
4. `RefreshAccount`
5. optional Kontoauszüge
6. `EndSession`

---

## Amazon — 2.01

**Repo:** [Amazon-MoneyMoney](https://github.com/rosch100/Amazon-MoneyMoney)

Service-Name: `Amazon Bestellungen` (nicht `Amazon Orders`; nicht nur `Amazon`,
wegen Kollision mit MoneyMoney’s Amazon-Kreditkarte).
Host-Whitelist der Extension: `www.amazon.de`.
Multi-Login: Harvest-/Cache-State in `LocalStorage.logins[<email>]`.

---

## Bank of America — Beta 0.92

**Repo:** [Bank-of-America-MoneyMoney](https://github.com/rosch100/Bank-of-America-MoneyMoney)

Cookie-Import: `COOKIE:SMSESSION=…;SSOTOKEN=…;LSESSIONID=…`.
Username/Passwort (Sparta + MFA) wenn `MM.rsaEncrypt` verfügbar; sonst Cookie.
HAR: `python3 scripts/extract-boa-cookies.py login.har`.

---

## Fidelity — Beta 0.93

**Repo:** [Fidelity-MoneyMoney](https://github.com/rosch100/Fidelity-MoneyMoney)

Cookie-Import über Portfolio Summary. Username/Passwort in Lua derzeit nicht
möglich (Akamai + MFA) — siehe [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).

---

## MLP Versicherungen — Beta 0.92

**Repo:** [MLP-Versicherungen-MoneyMoney](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney)

Cookie-Import: `VUSESSIONID` von `vue.mlp.de`. Username/Passwort: JWE
(`RSA-OAEP-512` + `A256GCM`) wenn `MM.aes256gcm` und OAEP-SHA-512 da sind,
sonst Klartext-Versuch, danach Cookie-Fallback; siehe
[ENGINE-API-GAPS.md](ENGINE-API-GAPS.md) und Branch `feature/mm-crypto-jwe-ready`.

---

## Presidential Bank — 1.09

**Repo:** [Presidential-Bank-MoneyMoney](https://github.com/rosch100/Presidential-Bank-MoneyMoney)

Username/Passwort + MFA; optional `COOKIE:SESSION_TOKEN=…;rftoken=…`.
Private-Device (`MAF_IB_*`) als Cookie-Header-String in LocalStorage — nach
MoneyMoney-Neustart kein erneutes TOTP, wenn das Gerät registriert wurde.

---

## Shareview — 1.03

**Repo:** [Shareview-MoneyMoney](https://github.com/rosch100/Shareview-MoneyMoney)

Username/Passwort + Geburtsdatum + MFA. Federation-Hosts in der Extension
als Konstanten: `portfolio.shareview.co.uk`, `www.equiniti.com` (ADFS).
Optional `COOKIE:FedAuth=…`.
Kontonummer neuer Konten `SV.<username>`; bestehendes `shareview-portfolio`
wird weiter aktualisiert.
