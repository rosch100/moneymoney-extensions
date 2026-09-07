# Notizen: Antwort an Michael Adams (Freigabe)

Stand nach Umsetzung der Sicherheitsrückmeldungen und Folge-Feedback (2026-09-07).

## Amazon

- Neuer Service-Name: **Amazon Bestellungen** (nicht „Amazon Orders“, nicht nur „Amazon“)
- Dateiname: **`amazon-bestellungen.lua`** (nicht `amazon-orders.lua` = Beutling;
  statt Adams’ Zwischenname `amazon-orders-2.lua`)
- Version: **2.0**
- Top-Level-`print`/stdout entfernt (Signierscript verbietet Ausgabe auf oberster Ebene)
- Absolute `http(s)://`-URLs werden gegen `https://www.amazon.de` / `baseurl` geprüft; fremde Hosts lösen einen Fehler aus
- Runtime-Requests (inkl. Form-Actions) und Account-Note-Overrides laufen über dieselbe Host-Prüfung
- `AccountTypeOther`: Fix kommt mit dem nächsten MoneyMoney-Update (kein Extension-Workaround)
- Inhalt inkl. Adams-Signatur übernommen; Website-Download bitte unter **`amazon-bestellungen.lua`** bereitstellen
- Repo: https://github.com/rosch100/Amazon-MoneyMoney

## Shareview

- Version: **1.02**
- Federation-Hosts als Konstanten (für Whitelist):
  - `portfolio.shareview.co.uk`
  - `www.equiniti.com` (ADFS: `https://www.equiniti.com/adfs/ls/`)
- Auto-Post `hiddenform` und Login/MFA-Form-Actions nur noch zu diesen Hosts; sonst Fehler ohne weiteren Request
- Repo: https://github.com/rosch100/Shareview-MoneyMoney

## Presidential Bank

- Version: **1.01**
- Absolute `resultURL` nur zu `www.presidentialpcbanking.com`
- Signierte Datei von Adams in GitHub übernommen
- Eigenes Repo: https://github.com/rosch100/Presidential-Bank-MoneyMoney

## Pluxee Benefits

- Signierte Datei von Adams in GitHub übernommen
- Repo: https://github.com/rosch100/Pluxee-MoneyMoney

## Bank of America

- Request-URL-Allowlist `secure.bankofamerica.com`
- Base64-API korrigiert: MoneyMoney bietet **`MM.base64`** und **`MM.base64decode`**
  (nicht `MM.base64Encode` / `MM.base64encode` / `MM.base64Decode`)
- Nach dem Base64-Fix muss Adams die Datei **neu signieren** (alte Signatur passt nicht mehr)
- Repo: https://github.com/rosch100/Bank-of-America-MoneyMoney

## Weitere Eigenrepos

- https://github.com/rosch100/Fidelity-MoneyMoney
- https://github.com/rosch100/MLP-Versicherungen-MoneyMoney (kein `load()` auf Server-JSON; JWKS/iframe Host-Allowlist)

Hub (Helper/Scripts/Docs): https://github.com/rosch100/moneymoney-extensions

## Whitelist / Engine

- Extension-URLs werden in die Whitelist der nächsten MoneyMoney-Version aufgenommen
- Zur Kenntnis: RSA-OAEP SHA-512 / Ed25519 im nächsten MM-Update;
  `WebbankingBrowser` für Lua nicht geplant — vermerkt in `docs/ENGINE-API-GAPS.md`
