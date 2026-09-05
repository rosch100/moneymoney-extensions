# MoneyMoney Extensions Hub

Gemeinsame Tools und Dokumentation für [MoneyMoney](https://moneymoney.app)-Web-Banking-Extensions.

Repository: https://github.com/rosch100/moneymoney-extensions

Die **Lua-Extensions selbst** liegen in eigenen Repositories (siehe Übersicht).
Dieses Hub behält MoneyMoney Helper, Cookie-Export-Skripte und den Docs-Index.

## Signiert vs. Eigenrepos

Die Lua-Dateien in den Eigenrepos sind **unsigniert**. Eine ggf. über
[MoneyMoney Extensions](https://moneymoney.app/extensions/) veröffentlichte
**signierte** Version entspricht **nicht** automatisch dem Stand aus dem
jeweiligen `rosch100`-Repository.

Unsignierte Plugins setzen voraus: MoneyMoney-**Beta** und deaktivierte
Signaturprüfung (*MoneyMoney → Einstellungen → Erweiterungen*).

## Übersicht

| Extension | Repo | Version | Status |
|-----------|------|---------|--------|
| [Amazon](https://github.com/rosch100/Amazon-MoneyMoney) | [Amazon-MoneyMoney](https://github.com/rosch100/Amazon-MoneyMoney) | **2.0** | Service *Amazon Bestellungen*; Umsätze (amazon.de) |
| [Bank of America](https://github.com/rosch100/Bank-of-America-MoneyMoney) | [Bank-of-America-MoneyMoney](https://github.com/rosch100/Bank-of-America-MoneyMoney) | **0.91 Beta** | Cookie-Import; Username/Passwort (Sparta) wenn Engine-API da |
| [Fidelity](https://github.com/rosch100/Fidelity-MoneyMoney) | [Fidelity-MoneyMoney](https://github.com/rosch100/Fidelity-MoneyMoney) | **0.92 Beta** | Cookie-Import (Username/Passwort in Lua: Akamai-Blocker) |
| [givve Card](https://github.com/rosch100/Givve-MoneyMoney) | [Givve-MoneyMoney](https://github.com/rosch100/Givve-MoneyMoney) | **1.00** | Service *Givve Card*; E-Mail/Passwort + E-Mail-OTP; ein Konto pro Voucher (`card.givve.com` / API `www.givve.com`) |
| [Pluxee](https://github.com/rosch100/Pluxee-MoneyMoney) | [Pluxee-MoneyMoney](https://github.com/rosch100/Pluxee-MoneyMoney) | **0.91** Beta | E-Mail/OTP (Passwort wenn Formular); Saldo + Umsätze (`consumers.pluxee.de` / BFF) |
| [MLP Versicherungen](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney) | [MLP-Versicherungen-MoneyMoney](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney) | **0.91 Beta** | Cookie-Import; Username/Passwort (JWE oder Klartext-Fallback) |
| [Presidential Bank](https://github.com/rosch100/Presidential-Bank-MoneyMoney) | [Presidential-Bank-MoneyMoney](https://github.com/rosch100/Presidential-Bank-MoneyMoney) | **1.01** | Username/Passwort + MFA; Cookie optional |
| [Shareview](https://github.com/rosch100/Shareview-MoneyMoney) | [Shareview-MoneyMoney](https://github.com/rosch100/Shareview-MoneyMoney) | **1.02** | Username/Passwort + DOB + MFA; Cookie optional |

**MLP Bank vs. MLP Versicherungen:** FinTS-Giro (MLP Bank) ist ein separates
MoneyMoney-Produkt. Die Extension deckt nur Versicherungsverträge über
`vue.mlp.de` ab.

Kurzindex und technische Notizen: [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md).

## Installation

1. `.lua` aus dem jeweiligen Eigenrepo klonen oder Raw-URL laden
2. Nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/` kopieren (oder `./link_ext.sh` im Eigenrepo)
3. Signaturprüfung in MoneyMoney deaktivieren; Beta nutzen

## Cookie-Import (Beta-Extensions)

Passwortfeld in MoneyMoney:

```
COOKIE:name=value;name2=value2
```

### Ablauf (empfohlen: Safari Extension)

1. Im Browser vollständig einloggen (inkl. MFA)
2. Kontoseite / Vertragsübersicht öffnen
3. Cookies mit der **MoneyMoney Helper**-Extension kopieren (siehe unten)
4. `COOKIE:…`-String als Passwort in MoneyMoney einfügen

### 1. Safari Extension (empfohlen)

1. Extension bauen/starten: siehe [browser-extension/README.md](browser-extension/README.md)
2. Safari → **Einstellungen → Erweiterungen** → **MoneyMoney Helper** aktivieren
3. Bank-Seite öffnen; Cookies kopieren; in MoneyMoney einfügen

### 2. Export per HAR (Alternative)

| Bank | Befehl | Wichtige Cookies |
|------|--------|------------------|
| Bank of America | `python3 scripts/extract-boa-cookies.py export.har` | `SMSESSION`, `SSOTOKEN`, `LSESSIONID` |
| Fidelity | `python3 scripts/extract-fidelity-cookies.py export.har` | `_abck`, `bm_sz`, `ATC`, `ET`, … |
| MLP Versicherungen | `python3 scripts/extract-mlp-cookies.py export.har` | `VUSESSIONID` von `vue.mlp.de` |
| Presidential Bank | `python3 scripts/extract-presidential-cookies.py export.har` | `SESSION_TOKEN`, `rftoken` |
| Shareview | `python3 scripts/extract-shareview-cookies.py export.har` | `FedAuth` |

### 3. Tampermonkey (optional)

`scripts/moneymoney-cookie-exporter.user.js` — **Alt+C** auf der Kontoseite.

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/) | Offizielle Extension-API |
| [browser-extension/README.md](browser-extension/README.md) | MoneyMoney Helper |
| [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md) | Hub-Index der Extensions |
| [docs/ENGINE-API-GAPS.md](docs/ENGINE-API-GAPS.md) | Engine-API-Lücken / Roadmap |

## Entwicklung (Hub)

Lokal: Lua 5.4, Python 3.11. Extension-Tests liegen in den Eigenrepos.

```bash
python3 tests/test_external_scripts_conformance.py
python3 tests/test_workflow_security.py
python3 tests/test_cookie_export_config.py
python3 tests/test_browser_extension_manifest.py
node tests/test_cookie_export.mjs
```

CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Lizenz

MIT
