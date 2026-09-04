# Lua-Extensions — Hub-Index

Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).
Installation und Cookie-Helper: [README](../README.md).

Die Lua-Quellen liegen in **eigenen Repositories**. Dieses Dokument ist nur der Hub-Index.

## Versionierung

| Version | Bedeutung |
|---------|-----------|
| **0.91 / 0.92** | Beta — Cookie-Import ist der unterstützte Anmeldeweg |
| **1.01 / 1.02 / 1.03** | Direct-Login mit MFA (optional Cookie-Import) |
| **2.0 / 2.01** | Amazon-Bestellungen (Service-Name `Amazon`) |

Signierte Fremdversionen entsprechen nicht automatisch den Eigenrepos
(siehe [README](../README.md#signiert-vs-eigenrepos)).

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

Service-Name: `Amazon` (nicht `Amazon Orders`, Koexistenz mit anderer Listung).
Host-Whitelist der Extension: `www.amazon.de`.

---

## Bank of America — Beta 0.92

**Repo:** [Bank-of-America-MoneyMoney](https://github.com/rosch100/Bank-of-America-MoneyMoney)

Cookie-Import: `COOKIE:SMSESSION=…;SSOTOKEN=…;LSESSIONID=…`.
HAR: `python3 scripts/extract-boa-cookies.py login.har`.

---

## Fidelity — Beta 0.92

**Repo:** [Fidelity-MoneyMoney](https://github.com/rosch100/Fidelity-MoneyMoney)

Cookie-Import über Portfolio Summary. Direct-Login blockiert (Akamai + MFA).

---

## MLP Versicherungen — Beta 0.92

**Repo:** [MLP-Versicherungen-MoneyMoney](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney)

Cookie-Import: `VUSESSIONID` von `vue.mlp.de`. JWE/SecureGo wenn Engine-Krypto da;
siehe [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).

---

## Presidential Bank — 1.02

**Repo:** [Presidential-Bank-MoneyMoney](https://github.com/rosch100/Presidential-Bank-MoneyMoney)

Username/Passwort + MFA; optional `COOKIE:SESSION_TOKEN=…;rftoken=…`.

---

## Shareview — 1.03

**Repo:** [Shareview-MoneyMoney](https://github.com/rosch100/Shareview-MoneyMoney)

Username/Passwort + Geburtsdatum + MFA. Federation-Hosts in der Extension
als Konstanten: `portfolio.shareview.co.uk`, `www.equiniti.com` (ADFS).
Optional `COOKIE:FedAuth=…`.
