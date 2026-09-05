# Lua-Extensions — Hub-Index

Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).
Installation und Cookie-Helper: [README](../README.md).

Die Lua-Quellen liegen in **eigenen Repositories**. Dieses Dokument ist nur der Hub-Index.

## Versionierung

| Version | Bedeutung |
|---------|-----------|
| **0.91 / 0.92** | Beta — Cookie-Import empfohlen; Username/Passwort bleibt, soweit Engine-APIs reichen |
| **1.01 / 1.02** | Direct-Login mit MFA (optional Cookie-Import) |
| **2.0** | Amazon-Bestellungen (Service-Name `Amazon Bestellungen`) |

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

## Amazon — 2.0

**Repo:** [Amazon-MoneyMoney](https://github.com/rosch100/Amazon-MoneyMoney)

Service-Name: `Amazon Bestellungen` (nicht `Amazon Orders`; nicht nur `Amazon`,
wegen Kollision mit MoneyMoney’s Amazon-Kreditkarte).
Host-Whitelist der Extension: `www.amazon.de`.

---

## Bank of America — Beta 0.91

**Repo:** [Bank-of-America-MoneyMoney](https://github.com/rosch100/Bank-of-America-MoneyMoney)

Cookie-Import: `COOKIE:SMSESSION=…;SSOTOKEN=…;LSESSIONID=…`.
Username/Passwort (Sparta + MFA) wenn `MM.rsaEncrypt` verfügbar; sonst Cookie.
HAR: `python3 scripts/extract-boa-cookies.py login.har`.

---

## Fidelity — Beta 0.92

**Repo:** [Fidelity-MoneyMoney](https://github.com/rosch100/Fidelity-MoneyMoney)

Cookie-Import über Portfolio Summary. Username/Passwort in Lua derzeit nicht
möglich (Akamai + MFA) — siehe [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).

---

## Givve Prepaid — 1.05

**Repo:** [Givve-MoneyMoney](https://github.com/rosch100/Givve-MoneyMoney)

Service-Name / Dateiname: `Givve Prepaid` / `Givve Prepaid.lua` (Title Case,
identisch; nicht `Givve Card` — Kollision mit MoneyMoney’s eingebauter
Kreditkarte; analog `Amazon Bestellungen` vs. `Amazon-Kreditkarte`).
Portal: `card.givve.com`, API: `www.givve.com`.
Login E-Mail/Passwort + E-Mail-OTP (`POST /api/authorizations`,
`client_id=givve-card-web`). Host-Allowlist: `card.givve.com`, `www.givve.com`.
Kontoname `givve` bzw. `givve ****<last4>`; Kontonummer = maskierte PAN
(`voucher.number`); Inhaber aus `GET …/voucher_owners/me`. Umsätze analog Builtin
(`name`/`purpose`/`valueDate`/`booked`). Multi-Login über `connectionsByAccount`.
Konto anlegen: **Andere** (nicht IBAN/BLZ) → **Givve Prepaid**.

---

## Pluxee Benefits — 1.00

**Repo:** [Pluxee-MoneyMoney](https://github.com/rosch100/Pluxee-MoneyMoney)

Service-Name / Dateiname: `Pluxee Benefits` / `Pluxee Benefits.lua` (Title Case,
identisch; Marke + Produkttyp wie *Givve Prepaid* / *Amazon Bestellungen*).
Portal: `consumers.pluxee.de`, OIDC: `connect.pluxee.app`, BFF: `api.pluxee.app/gl/eva/bff`.
Login E-Mail / hCaptcha / OTP (Passwort nur wenn Formularfeld); OAuth-`state` und
Host-Allowlist; Token-Reuse über `connectionsByAccount`.
Kontonummer = API-`maskedPan` (z. B. `XXXX 6138`; bei gleicher PAN Suffix `benefitId`);
Anzeigename ein Konto `{Benefit-Name}`, mehrere `{Benefit-Name} {last4}`;
ein Konto **pro Benefit**; Umsätze nur `APPROVED`, gefiltert über
`splitData.uniqueWalletId`, Pagination per `toDate`.
Saldo/Umsätze `GET /v2/de/cards` und `…/transactions`.
Konto anlegen: **Andere** (nicht IBAN/BLZ) → **Pluxee Benefits**.

---

## MLP Versicherungen — Beta 0.91

**Repo:** [MLP-Versicherungen-MoneyMoney](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney)

Cookie-Import: `VUSESSIONID` von `vue.mlp.de`. Username/Passwort: JWE/SecureGo
wenn Engine-Krypto da, sonst Klartext-Versuch, danach Cookie-Fallback;
siehe [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).

---

## Presidential Bank — 1.01

**Repo:** [Presidential-Bank-MoneyMoney](https://github.com/rosch100/Presidential-Bank-MoneyMoney)

Username/Passwort + MFA; optional `COOKIE:SESSION_TOKEN=…;rftoken=…`.

---

## Shareview — 1.02

**Repo:** [Shareview-MoneyMoney](https://github.com/rosch100/Shareview-MoneyMoney)

Username/Passwort + Geburtsdatum + MFA. Federation-Hosts in der Extension
als Konstanten: `portfolio.shareview.co.uk`, `www.equiniti.com` (ADFS).
Optional `COOKIE:FedAuth=…`.
