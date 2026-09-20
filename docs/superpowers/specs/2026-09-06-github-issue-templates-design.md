# GitHub Issue Templates für MoneyMoney-Plugins

Datum: 2026-09-06

Status: **Implementiert** (2026-09-20); Conformity-Remediation 2026-09-20

## Ziel

Für alle acht Lua-Plugin-Repositories einheitliche, deutschsprachige
GitHub Issue Forms (Bug + Feature) bereitstellen. Melder werden zu
Lua-/Web-Banking-relevanten Angaben geführt. MoneyMoney-Logs und
vertrauliche Daten sind explizit und nach Best Practice geregelt:
Logdateien nicht anhängen; verschlüsselte App-Logs sind für Maintainer
nicht nutzbar; nur redigierte Protokollfenster-Ausschnitte bzw.
Screenshots.

## Entscheidungen (fest)

| Thema | Wahl |
| --- | --- |
| Issue-Arten | Bug-Report + Feature-Request |
| Ablage | Identisch in jedem Plugin-Repo unter `.github/ISSUE_TEMPLATE/` |
| Pflege | SSOT im Hub + Sync in die Plugin-Repos; knapper README-Link |
| Sprache | Nur Deutsch |
| Form | GitHub Issue Forms (YAML) |
| Diagnose | Keine Logdatei-Anhänge; redigierte Protokollfenster-Ausschnitte und/oder Screenshots |

## Scope

### Repos (Plugin)

- Amazon-MoneyMoney
- Bank-of-America-MoneyMoney
- Fidelity-MoneyMoney
- Givve-MoneyMoney
- MLP-Versicherungen-MoneyMoney
- Pluxee-MoneyMoney
- Presidential-Bank-MoneyMoney
- Shareview-MoneyMoney

### Hub

- SSOT unter `docs/issue-templates/`
- Sync-Skript `scripts/Sync-IssueTemplates.ps1` (`#Requires -Version 7`),
  das die YAML-Dateien in die lokalen Plugin-Checkouts kopiert
- Kein automatischer Commit/Push in die Plugin-Repos
- Hub selbst erhält **keine** Issue-Templates (Issues bleiben in den
  Plugin-Repos)

### Nicht-Ziele

- Support-/Frage-Template
- Englische Templates
- Zentrale Issues nur im Hub
- CI, Label-Bots, Issue-Forms-Validierung außerhalb GitHub
- Änderung der Lua-Skripte oder Logging-Implementierung

## Dateistruktur

### Hub-SSOT (`docs/issue-templates/`)

| Datei | Zweck |
| --- | --- |
| `bug_report.yml` | Bug-Form |
| `feature_request.yml` | Feature-Form |
| `config.yml` | Template-Auswahl; Blank Issues aus |
| `README.md` | Pflege, Sync-Aufruf, Maintainer-Antwortvorlage |

### Pro Plugin

```text
.github/ISSUE_TEMPLATE/
  bug_report.yml
  feature_request.yml
  config.yml
```

Inhalt der drei YAML-Dateien = 1:1-Kopie der Hub-SSOT-YAML (kein
plugin-spezifischer Text in den Forms). Die Hub-`README.md` wird
**nicht** in die Plugin-Repos kopiert.

### Sync

- Skript: `scripts/Sync-IssueTemplates.ps1`
- Quelle: `docs/issue-templates/{bug_report,feature_request,config}.yml`
- Ziel: jedes `*-MoneyMoney/.github/ISSUE_TEMPLATE/` (Verzeichnis anlegen
  falls fehlend)
- Nur Dateisystem; Commit/Push bleibt manuell je Plugin-Repo
- Bei fehlendem Plugin-Checkout: Fehler melden, nicht still überspringen

### README je Plugin

Kurzer Abschnitt „Fehler & Ideen“ mit Link auf
`https://github.com/rosch100/<Repo>/issues/new/choose`.
Kein langer Datenschutz-Text in der README (Detail steht im Bug-Template).

## Datenschutz & Logs (Best Practice)

### Hintergrund

MoneyMoney führt ein Protokoll (**Fenster → Protokollfenster**). Die von der
App persistierten Protokolldateien sind für Dritte/Maintainer typischerweise
**nicht lesbar** (app-seitige Verschlüsselung bzw. nur MoneyMoney-intern
nutzbar). Community-Maintainer können solche Dateien **nicht** auswerten.
Anhängen hilft der Diagnose nicht und kann trotzdem vertrauliche Inhalte
transportieren.

Das **Protokollfenster** selbst zeigt Klartext. Ausschnitte und Screenshots
können Secrets enthalten (Cookies, Tokens, Kontodaten) und müssen redigiert
werden.

Unabhängig vom Dateiformat: **keine** Logdateien an Issues anhängen.

### Regeln für Melder (im Bug-Template sichtbar)

1. **Keine** MoneyMoney-`.log`-Dateien und keine sonstigen Diagnose-/Trace-
   Archive anhängen (verschlüsselt = für Maintainer nutzlos; Klartext =
   Geheimnisrisiko).
2. Stattdessen: Text aus **Fenster → Protokollfenster** und/oder Screenshot
   davon — vorher redigieren.
3. **Nie** posten: Passwörter, Cookie-Strings (`COOKIE:…`), Session-Tokens,
   OTP/TAN, vollständige Kontonummern/IBAN/PAN, unnötige Login-E-Mails,
   personenbezogene Bestell-/Vertragsdaten, HAR-Dateien, LocalStorage-/
   webCache-Dumps, Roh-Exports aus dem MoneyMoney Helper.
4. **Erlaubt** nach Redaktion: Extension-Fehlermeldungen, URLs ohne
   Query-Secrets, HTTP-Status, kurze `print`-Zeilen, MoneyMoney- und
   Extension-Version, OS-Version, Reproduktionsschritte.

### Feature-Template

Kurzer Markdown-Hinweis: keine Logs, keine Zugangsdaten.
Pflicht-Checkbox: keine Zugangsdaten und keine personenbezogenen
Beispieldaten.

### Maintainer-Antwortvorlage (Pflichtinhalt der SSOT-`README.md`)

Wenn trotz Hinweis eine Logdatei oder Secrets angehängt werden:

1. Issue kommentieren: Anhang ist für Maintainer nicht auswertbar bzw.
   enthält mutmaßlich Vertrauliches.
2. Um redigierten Protokollfenster-Ausschnitt (Text) bitten.
3. Anhang nicht weiterverbreiten; Melder bitten, den Anhang zu entfernen
   bzw. das Issue zu bereinigen.

## Bug-Formular (`bug_report.yml`)

Form-Metadaten (GitHub-Pflicht): `name`, `description`, `title` (Prefix
z. B. `"[Bug]: "`), `labels: [bug]`, `body`.

| Element | Typ | Pflicht |
| --- | --- | --- |
| Datenschutz-/Log-Hinweis | markdown | — |
| Kurzbeschreibung | input | ja |
| Erwartetes Verhalten | textarea | ja |
| Tatsächliches Verhalten | textarea | ja |
| Schritte zur Reproduktion | textarea | ja |
| MoneyMoney-Version (inkl. Beta?) | input | ja |
| Extension-Version und Quelle (signiert vs. Repo) | input | ja |
| macOS-Version | input | ja |
| Auth-Weg | dropdown: Username/Passwort, Cookie-Import, MFA, unklar | ja |
| Redigierter Protokoll-Ausschnitt / Screenshot-Hinweis | textarea | nein |
| Bestätigung: keine Secrets | checkboxes | ja |
| Bestätigung: keine Logdatei angehängt | checkboxes | ja |
| Bestätigung: Inhalte redigiert | checkboxes | ja |

### Labels

Vor dem ersten produktiven Issue in jedem Plugin-Repo die Labels `bug` und
`enhancement` anlegen (GitHub UI oder `gh label create`). Die Forms setzen
`labels: [bug]` bzw. `labels: [enhancement]`. Keine alternative
„ohne Labels“-Variante — eine Policy, keine Verzweigung.

## Feature-Formular (`feature_request.yml`)

Form-Metadaten: `name`, `description`, `title` (Prefix z. B.
`"[Feature]: "`), `labels: [enhancement]`, `body`.

| Element | Typ | Pflicht |
| --- | --- | --- |
| Datenschutz-Kurzhinweis | markdown | — |
| Problem / Motivation | textarea | ja |
| Vorgeschlagene Lösung | textarea | ja |
| Alternativen | textarea | nein |
| Betroffener Ablauf | dropdown: Login, Kontenliste, Abruf/Umsätze, Cookie-Import, Sonstiges | nein |
| Keine Zugangsdaten / keine personenbezogenen Beispiele | checkboxes | ja |

## `config.yml`

```yaml
blank_issues_enabled: false
contact_links:
  - name: Hub-Dokumentation
    url: https://github.com/rosch100/moneymoney-extensions
    about: Gemeinsame Infos, Cookie-Helper und technische Docs
```

## Akzeptanzkriterien

1. Hub enthält SSOT-YAML + Pflege-README (inkl. Maintainer-Antwortvorlage)
   + `scripts/Sync-IssueTemplates.ps1`.
2. Alle acht Plugin-Repos haben `.github/ISSUE_TEMPLATE/` mit denselben
   drei YAML-Dateien.
3. „New issue“ zeigt Bug- und Feature-Form; Blank Issues sind aus.
4. Bug-Form nennt explizit: Logdateien nicht anhängen; verschlüsselte/
   app-interne Logs für Maintainer nicht auswertbar; Verbot von Secrets;
   redigierte Protokollfenster-Alternativen.
5. Jede Plugin-README verlinkt auf `issues/new/choose`.
6. Hub-README bzw. Docs-Index verweist auf `docs/issue-templates/`.
7. Labels `bug` und `enhancement` existieren in allen acht Plugin-Repos.
8. Keine Secrets oder Klartext-Beispiele mit echten Credentials in den
   Templates.

## Risiken

| Risiko | Mitigation |
| --- | --- |
| Drift zwischen Hub und Plugins | Sync-Skript; SSOT nur im Hub ändern |
| Melder hängen trotzdem Logs an | Template-Text + Maintainer-Antwortvorlage in SSOT-README |
| Label fehlen in manchen Repos | Labels vor Rollout anlegen (Akzeptanzkriterium 7) |
| Plugin-Repos sind eigene Gits | Sync nur lokal; Commit pro Repo bewusst |
| Klartext-Logs wirken „hilfreich“ | Template: jede Logdatei verboten, nicht nur „verschlüsselte“ |

## Umsetzungsreihenfolge (für Plan)

1. Hub-SSOT und `scripts/Sync-IssueTemplates.ps1` anlegen
2. Templates in alle acht Plugin-Checkouts synchronisieren
3. Labels `bug` / `enhancement` prüfen/anlegen
4. README-Abschnitte in allen Plugins
5. Kurzverweis im Hub-README/Docs-Index auf `docs/issue-templates/`
