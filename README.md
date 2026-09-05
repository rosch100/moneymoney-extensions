# MoneyMoney Extensions Hub

Gemeinsame Tools und Dokumentation für [MoneyMoney](https://moneymoney.app)-Web-Banking-Erweiterungen.

Repository: https://github.com/rosch100/moneymoney-extensions

Die **Lua-Erweiterungen** liegen in eigenen Repositories (siehe Übersicht).
Dieses Hub enthält den MoneyMoney Helper, Cookie-Export-Skripte und den Docs-Index.

## Signiert vs. Eigenrepos

Die Lua-Dateien in den Eigenrepos sind **unsigniert**. Eine über
[MoneyMoney Extensions](https://moneymoney.app/extensions/) veröffentlichte
**signierte** Version entspricht **nicht** automatisch dem Stand aus dem
jeweiligen `rosch100`-Repository.

Unsignierte Plugins brauchen MoneyMoney-**Beta** und deaktivierte
Signaturprüfung (*MoneyMoney → Einstellungen → Erweiterungen*).

## Übersicht

| Erweiterung | Repository | Version | Kurz |
|-------------|------------|---------|------|
| [Amazon](https://github.com/rosch100/Amazon-MoneyMoney) | [Amazon-MoneyMoney](https://github.com/rosch100/Amazon-MoneyMoney) | **2.01** | Bestellungen von amazon.de |
| [Bank of America](https://github.com/rosch100/Bank-of-America-MoneyMoney) | [Bank-of-America-MoneyMoney](https://github.com/rosch100/Bank-of-America-MoneyMoney) | **0.92 Beta** | Cookie-Import |
| [Fidelity](https://github.com/rosch100/Fidelity-MoneyMoney) | [Fidelity-MoneyMoney](https://github.com/rosch100/Fidelity-MoneyMoney) | **0.93 Beta** | Cookie-Import |
| [Givve Prepaid](https://github.com/rosch100/Givve-MoneyMoney) | [Givve-MoneyMoney](https://github.com/rosch100/Givve-MoneyMoney) | **1.00** | Prepaid-Karten, E-Mail/Passwort und E-Mail-Code |
| [Pluxee Benefits](https://github.com/rosch100/Pluxee-MoneyMoney) | [Pluxee-MoneyMoney](https://github.com/rosch100/Pluxee-MoneyMoney) | **1.00** | Benefits, E-Mail, Captcha und E-Mail-Code |
| [MLP Versicherungen](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney) | [MLP-Versicherungen-MoneyMoney](https://github.com/rosch100/MLP-Versicherungen-MoneyMoney) | **0.92 Beta** | Kundenportal; Cookie oder Login |
| [Presidential Bank](https://github.com/rosch100/Presidential-Bank-MoneyMoney) | [Presidential-Bank-MoneyMoney](https://github.com/rosch100/Presidential-Bank-MoneyMoney) | **1.09** | Login und MFA; Cookie optional |
| [Shareview](https://github.com/rosch100/Shareview-MoneyMoney) | [Shareview-MoneyMoney](https://github.com/rosch100/Shareview-MoneyMoney) | **1.04** | Login, Geburtsdatum und MFA; Cookie optional |

**Mehrere Logins:** Dieselbe Erweiterung mehrfach mit unterschiedlichen
Zugangsdaten anlegen — jeder Bankzugang hat seine eigene Sitzung.

**MLP Bank vs. MLP Versicherungen:** Das FinTS-Giro der MLP Bank ist ein
separates MoneyMoney-Produkt. Diese Erweiterung betrifft nur
Versicherungsverträge im Kundenportal.

Technische Details und Tests: [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md).

## Installation

1. `.lua` aus dem jeweiligen Eigenrepo laden
2. Nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/` kopieren (oder `./link_ext.sh` im Eigenrepo)
3. Signaturprüfung in MoneyMoney ausschalten; Beta nutzen

Details stehen in der README des jeweiligen Plugins.

## Cookie-Import (Beta-Erweiterungen)

Passwortfeld in MoneyMoney:

```
COOKIE:name=value;name2=value2
```

### Ablauf (empfohlen: MoneyMoney Helper)

1. Im Browser vollständig einloggen (inkl. MFA)
2. Kontoseite bzw. Vertragsübersicht öffnen
3. Cookies mit der **MoneyMoney Helper**-Erweiterung kopieren
4. `COOKIE:…`-String als Passwort in MoneyMoney einfügen

### 1. Browser-Erweiterung (empfohlen)

1. Installation: [browser-extension/README.md](browser-extension/README.md)
2. Safari → **Einstellungen → Erweiterungen** → **MoneyMoney Helper** aktivieren
   (bzw. in Chrome/Firefox die entpackte Erweiterung laden)
3. Bank-Seite öffnen; Cookies kopieren; in MoneyMoney einfügen

Der Helper unterstützt derzeit **Bank of America**, **Fidelity** und
**MLP Versicherungen**. Presidential Bank und Shareview: Cookies manuell oder
per HAR (siehe unten).

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
| [browser-extension/README.md](browser-extension/README.md) | MoneyMoney Helper (Nutzer) |
| [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md) | Technik, Tests, Amazon-Einstellungen |
| [docs/ENGINE-API-GAPS.md](docs/ENGINE-API-GAPS.md) | Engine-API-Lücken / Roadmap |
| [docs/superpowers/specs/2026-09-04-multi-login-localstorage-design.md](docs/superpowers/specs/2026-09-04-multi-login-localstorage-design.md) | Multi-Login (Design) |

## Entwicklung (Hub)

Lokal: Lua 5.4, Python 3.11. Extension-Tests liegen in den Eigenrepos
(Befehle: [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md)).

Hub-Tests:

```bash
python3 tests/test_external_scripts_conformance.py
python3 tests/test_workflow_security.py
python3 tests/test_cookie_export_config.py
python3 tests/test_browser_extension_manifest.py
node tests/test_cookie_export.mjs
```

MoneyMoney Helper: Konfiguration und Logik unter `browser-extension/`. Nach
Änderungen Safari-Ressourcen syncen:

```bash
python3 scripts/sync_safari_extension_resources.py
```

Danach Chrome/Firefox neu laden bzw. Safari per Xcode Run.

CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Lizenz

MIT
