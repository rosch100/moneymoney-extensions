# Lua-Extensions — Hub-Index

Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).
Installation und Cookie-Helper: [README](../README.md).

Die Lua-Quellen liegen in **eigenen Repositories**. Dieses Dokument ist der technische Hub-Index (Tests, Internas, Amazon-Einstellungen).

## Versionierung

| Version | Bedeutung |
|---------|-----------|
| **0.91 / 0.92 / 0.93** | Beta — Cookie-Import empfohlen; Username/Passwort bleibt, soweit Engine-APIs reichen |
| **1.00** | Givve Prepaid / Pluxee Benefits — Direct-Login (E-Mail/OTP; Pluxee zusätzlich hCaptcha) |
| **1.01 / 1.02 / 1.04 / 1.09** | Direct-Login mit MFA (optional Cookie-Import); Shareview Multi-Login (1.04); Presidential 1.09 Private-Device-Persistenz |
| **2.0 / 2.01** | Amazon-Bestellungen (Service-Name `Amazon Bestellungen`); 2.01 Multi-Login-Isolation |

Signierte Fremdversionen entsprechen nicht automatisch den Eigenrepos
(siehe [README](../README.md#signiert-vs-eigenrepos)).

**Multi-Login:** Mehrere Bankzugänge derselben Extension mit unterschiedlichen
Logins. Sessions: `LocalStorage.connectionsByAccount` bzw. Amazon
`LocalStorage.logins[<email>]`. Spec:
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
Host-Whitelist: `www.amazon.de`.
Auth: Username/Passwort (kein Cookie-Import).
Multi-Login: Harvest-/Cache-State in `LocalStorage.logins[<email>]`.

Konten: gemeinsames Konto **Amazon** (Nummer = Login-E-Mail); bei persönlich +
geschäftlich zusätzlich Unterkonten mit Personen- bzw. Firmennamen
(Nummer = `AO.` + Kunden-ID ohne führendes `A`). Kontoart *Sonstige*.
Alt-Services/-Nummern (`Amazon`, `mix` / `sub:*` / `normal` / …) werden nicht
mehr aktualisiert.

### Amazon — Einstellungen und Verhalten

Konto → Einstellungen → Notizen. Standardfelder werden beim Anlegen bzw. bei
*Nach neuen Konten suchen* gesetzt; ein normaler Abruf ändert die Tabelle nicht.

| Feld | Bedeutung |
|------|-----------|
| `resetCache` | Cache leeren und Historie neu einlesen. Nach Schema-Upgrade den Wert **ändern** (nicht denselben wie zuvor), dann aktualisieren. |
| `blacklistOrders` | Bestellnummern (kommagetrennt), die nicht als Umsätze ausgegeben werden. Älteres Feld `blackListOrders` wird weiter gelesen. |
| `rescanOrder` | Eine Bestellnummer, deren Details beim nächsten Abruf neu geladen werden. |
| `keepStorno` | `true`: Buchung und Storno behalten. Standard: `false`. |
| `nameMaxLength` | Max. Länge der Titelzeile; `0` = ungekürzt (Standard). |

Zusätzliche Felder (ohne Standard in der Notiztabelle):

| Feld | Bedeutung |
|------|-----------|
| `limitOrders` | Grenze je Filter-Batch und getrennt für Bestelldetails (Standard je 250). |
| `scanFiltersMonths` | Maximales Alter der Bestellübersichtsfilter; `0` = alle Jahre beim vollständigen Import. |
| `cookieLanguage` | Sprachkennung, falls die Amazon-Seite nicht Deutsch ist. |
| `orderDetailsUrl` | Nur wenn Amazon den Detail-Pfad ändert. |

**Erstimport:** Zugang mehrfach aktualisieren, bis nichts Offenes mehr gemeldet
wird. Beim Einrichten (`ListAccounts`) noch keine Umsätze. Gemeinsames Konto
*Amazon*: Round-Robin (ein Batch je Unterkonto pro Aktualisierung).
Geschäftliches Unterkonto hat Vorrang. Offener Platzhalter: Referenz
`AMAZON-INCOMPLETE-HARVEST`, Betrag 0.

**Buchungen:** Bestellnummer unter **Referenz**, Titel = Artikelname. Eigene
Buchungen u. a. für Versand, Erstattung, Rückgabe, Rücksendekosten, **Amazon
Ausgleich**. Volle Erstattung/Rückgabe/Storno standardmäßig weggelassen
(`keepStorno`).

**Update von Altversionen:** Konten löschen und unter *Amazon Bestellungen* neu
anlegen. Cache-Version 23 verlangt vollständigen Neuimport; danach `resetCache`
auf einen **neuen** Wert setzen.

**Business-Abruf:** Analytics `PAST_12_MONTHS` und ältere `CUSTOM_RANGE`; max.
sechs Berichts-Jobs je Aktualisierung; Rollup max. 250 Seiten.

### Amazon — Entwicklerwerkzeuge

Im Eigenrepo (Standard-Container):

- `./webCache_on.sh` / `./webCache_off.sh` / `./clean_webCache.sh`
- `./toggleCleanLocalStorage.sh`

Offline-Tests: siehe `test/README.md` im Amazon-Repo.

---

## Bank of America — Beta 0.92

**Repo:** [Bank-of-America-MoneyMoney](https://github.com/rosch100/Bank-of-America-MoneyMoney)

Cookie-Import: `COOKIE:SMSESSION=…;SSOTOKEN=…;LSESSIONID=…`.
Username/Passwort (Sparta + MFA) wenn `MM.rsaEncrypt` verfügbar; sonst Cookie.
HAR: `python3 scripts/extract-boa-cookies.py login.har` (Hub).

Tests (Eigenrepo-Root):

```sh
python3 tests/test_conformance.py
luajit tests/test_boa_login.lua
```

---

## Fidelity — Beta 0.93

**Repo:** [Fidelity-MoneyMoney](https://github.com/rosch100/Fidelity-MoneyMoney)

Cookie-Import über Portfolio Summary (`COOKIE:ATC=…;ET=…` u. a.).
Username/Passwort in Lua derzeit nicht möglich (Akamai + MFA) — siehe
[ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).
HAR: `python3 scripts/extract-fidelity-cookies.py export.har` (Hub).

Tests (Eigenrepo-Root):

```sh
python3 tests/test_conformance.py
luajit tests/test_fidelity_cookie_import.lua
luajit tests/test_fidelity_asset_allocation_fallback.lua
```

---

## Givve Prepaid — 1.00

**Repo:** [Givve-MoneyMoney](https://github.com/rosch100/Givve-MoneyMoney)

Service-Name / Dateiname: `Givve Prepaid` / `Givve Prepaid.lua` (Title Case,
identisch; nicht `Givve Card` — Kollision mit MoneyMoney’s eingebauter
Kreditkarte).
Portal: `card.givve.com`, API: `www.givve.com`.
Login E-Mail/Passwort + E-Mail-OTP (`POST /api/authorizations`,
`client_id=givve-card-web`). Host-Allowlist: `card.givve.com`, `www.givve.com`.
Kontoname `givve` bzw. `givve ****<last4>`; Kontonummer = maskierte PAN
(`voucher.number`); Inhaber aus `GET …/voucher_owners/me`. Umsätze analog Builtin
(`name`/`purpose`/`valueDate`/`booked`). Multi-Login über `connectionsByAccount`.
Alte Nummer `givve.<voucherId>` wird weiter erkannt; für Anzeige-PAN Konto neu anlegen.

Tests (Eigenrepo-Root):

```sh
python3 tests/test_conformance.py
luajit tests/test_givve.lua
```

---

## Pluxee Benefits — 1.00

**Repo:** [Pluxee-MoneyMoney](https://github.com/rosch100/Pluxee-MoneyMoney)

Service-Name / Dateiname: `Pluxee Benefits` / `Pluxee Benefits.lua`.
Portal: `consumers.pluxee.de`, OIDC: `connect.pluxee.app`, BFF: `api.pluxee.app/gl/eva/bff`.
Login E-Mail / invisible hCaptcha / OTP (Passwort nur wenn Formularfeld);
OAuth-`state` und Host-Allowlist; Token-Reuse über `connectionsByAccount`.
Kontonummer = API-`maskedPan` (bei gleicher PAN Suffix `benefitId`);
Anzeigename ein Konto `{Benefit-Name}`, mehrere `{Benefit-Name} {last4}`;
ein Konto **pro Benefit**; Umsätze nur `APPROVED`, gefiltert über
`splitData.uniqueWalletId`, Pagination per `toDate`.
Saldo/Umsätze `GET /v2/de/cards` und `…/transactions`.

Tests (Eigenrepo-Root):

```sh
test -x .venv/bin/python && .venv/bin/python tests/test_conformance.py || python3 tests/test_conformance.py
lua tests/test_pluxee.lua
```

---

## MLP Versicherungen — Beta 0.92

**Repo:** [MLP-Versicherungen-MoneyMoney](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney)

Cookie-Import: `VUSESSIONID` von `vue.mlp.de`. Username/Passwort: JWE
(`RSA-OAEP-512` + `A256GCM`) wenn `MM.aes256gcm` und OAEP-SHA-512 da sind,
sonst Klartext-Versuch, danach Cookie-Fallback; siehe
[ENGINE-API-GAPS.md](ENGINE-API-GAPS.md) und Branch `feature/mm-crypto-jwe-ready`.
HAR: `python3 scripts/extract-mlp-cookies.py export.har` (Hub).

Tests (Eigenrepo-Root):

```sh
python3 tests/test_conformance.py
luajit tests/test_mlp_kundenportal.lua
```

---

## Presidential Bank — 1.09

**Repo:** [Presidential-Bank-MoneyMoney](https://github.com/rosch100/Presidential-Bank-MoneyMoney)

Username/Passwort + MFA; optional `COOKIE:SESSION_TOKEN=…;rftoken=…`.
Private-Device (`MAF_IB_*`) als Cookie-Header-String in LocalStorage — nach
MoneyMoney-Neustart kein erneutes TOTP, wenn das Gerät registriert wurde.
HAR: `python3 scripts/extract-presidential-cookies.py export.har` (Hub).

Tests (Eigenrepo-Root):

```sh
python3 tests/test_conformance.py
luajit tests/test_presidential_bank.lua
```

---

## Shareview — 1.04

**Repo:** [Shareview-MoneyMoney](https://github.com/rosch100/Shareview-MoneyMoney)

Username/Passwort + Geburtsdatum + MFA. Federation-Hosts:
`portfolio.shareview.co.uk`, `www.equiniti.com` (ADFS).
Optional `COOKIE:FedAuth=…`.
Kontonummer neuer Konten `SV.<username>`; bestehendes `shareview-portfolio`
wird weiter aktualisiert. Multi-Login: ein Bankzugang je Login.
HAR: `python3 scripts/extract-shareview-cookies.py export.har` (Hub).

Tests (Eigenrepo-Root):

```sh
python3 tests/test_conformance.py
luajit tests/test_shareview.lua
```
