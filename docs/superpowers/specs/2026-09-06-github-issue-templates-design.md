# GitHub Issue Templates für MoneyMoney-Plugins

Datum: 2026-09-06

Status: **Design freigegeben** (Brainstorming)

## Ziel

Für alle acht Lua-Plugin-Repositories einheitliche, deutschsprachige
GitHub Issue Forms (Bug + Feature) bereitstellen. Melder werden zu
LUA-/Web-Banking-relevanten Angaben geführt. MoneyMoney-Logs und
vertrauliche Daten sind explizit und nach Best Practice geregelt:
verschlüsselte Logdateien dem Maintainer nicht nutzbar machen und
nicht anhängen; nur redigierte Protokoll-Ausschnitte bzw. Screenshots.

## Entscheidungen (fest)

| Thema | Wahl |
| --- | --- |
| Issue-Arten | Bug-Report + Feature-Request |
| Ablage | Identisch in jedem Plugin-Repo unter `.github/ISSUE_TEMPLATE/` |
| Pflege | SSOT im Hub + Sync in die Plugin-Repos; knapper README-Link |
| Sprache | Nur Deutsch |
| Form | GitHub Issue Forms (YAML) |
| Diagnose | Keine verschlüsselten Logs; redigierte Protokollfenster-Ausschnitte und/oder Screenshots |

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
- Sync-Skript (pwsh), das die YAML-Dateien in die lokalen Plugin-Checkouts kopiert
- Kein automatischer Commit/Push in die Plugin-Repos

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
| `README.md` | Pflegehinweis und Sync-Anleitung |

### Pro Plugin

```text
.github/ISSUE_TEMPLATE/
  bug_report.yml
  feature_request.yml
  config.yml
```

Inhalt = 1:1-Kopie der Hub-SSOT-YAML (kein plugin-spezifischer Text in den
Forms, damit Sync trivial bleibt).

### Sync

- Skript z. B. `scripts/Sync-IssueTemplates.ps1` (`#Requires -Version 7`)
- Quelle: `docs/issue-templates/*.yml`
- Ziel: jedes `*-MoneyMoney/.github/ISSUE_TEMPLATE/`
- Nur Dateisystem; Commit/Push bleibt manuell je Plugin-Repo

### README je Plugin

Kurzer Abschnitt „Fehler & Ideen“ mit Link auf
`https://github.com/rosch100/<Repo>/issues/new/choose`.
Kein langer Datenschutz-Text in der README (Detail steht im Bug-Template).

## Datenschutz & Logs (Best Practice)

### Hintergrund

MoneyMoney speichert Protokolldateien standardmäßig so, dass sie
**verschlüsselt** sind und nur MoneyMoney sie lesen kann. Maintainer der
Community-Plugins können diese Dateien **nicht** entschlüsseln. Anhängen
solcher Dateien hilft der Diagnose nicht und kann trotzdem
vertrauliche Inhalte transportieren.

Zusätzlich können Klartext-Ausschnitte aus dem Protokollfenster und
Screenshots Secrets enthalten (Cookies, Tokens, Kontodaten).

### Regeln für Melder (im Bug-Template sichtbar)

1. **Keine** MoneyMoney-`.log`-Dateien und keine sonstigen verschlüsselten
   Diagnose-Archive anhängen.
2. Stattdessen: Text aus **Fenster → Protokollfenster** und/oder Screenshot
   davon — vorher redigieren.
3. **Nie** posten: Passwörter, Cookie-Strings (`COOKIE:…`), Session-Tokens,
   OTP/TAN, vollständige Kontonummern/IBAN/PAN, unnötige Login-E-Mails,
   personenbezogene Bestell-/Vertragsdaten, HAR-Dateien mit Auth-Headern.
4. **Erlaubt** nach Redaktion: Extension-Fehlermeldungen, URLs ohne
   Query-Secrets, HTTP-Status, kurze `print`-Zeilen, MoneyMoney- und
   Extension-Version, OS-Version, Reproduktionsschritte.

### Feature-Template

Kein Log-Upload. Pflicht-Checkbox: keine Zugangsdaten und keine
personenbezogenen Beispieldaten.

### Maintainer-Hinweis (SSOT-README)

Wenn trotz Hinweis eine Logdatei angehängt wird: Issue kommentieren, dass
die Datei nicht lesbar/nutzbar ist, und um redigierten Protokoll-Ausschnitt
bitten; Anhang nicht weiterverbreiten.

## Bug-Formular (`bug_report.yml`)

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
| Bestätigung: keine verschlüsselte Logdatei | checkboxes | ja |
| Bestätigung: Inhalte redigiert | checkboxes | ja |

Labels (sofern im Repo vorhanden): `bug`. Fehlen Labels, Forms ohne
Label-Referenz oder nur dokumentiert — Sync darf keine fehlschlagenden
Label-IDs erzwingen; `labels: [bug]` nur wenn alle Repos das Label haben
oder GitHub fehlende Labels ignoriert. **Umsetzung:** Labels in den Forms
setzen; fehlende Labels einmalig in den Repos anlegen (`bug`, `enhancement`).

## Feature-Formular (`feature_request.yml`)

| Element | Typ | Pflicht |
| --- | --- | --- |
| Problem / Motivation | textarea | ja |
| Vorgeschlagene Lösung | textarea | ja |
| Alternativen | textarea | nein |
| Betroffener Ablauf | dropdown: Login, Kontenliste, Abruf/Umsätze, Cookie-Import, Sonstiges | nein |
| Keine Zugangsdaten / keine personenbezogenen Beispiele | checkboxes | ja |

Label: `enhancement` (siehe Label-Hinweis oben).

## `config.yml`

```yaml
blank_issues_enabled: false
contact_links:
  - name: Hub-Dokumentation
    url: https://github.com/rosch100/moneymoney-extensions
    about: Gemeinsame Infos, Cookie-Helper und technische Docs
```

## Akzeptanzkriterien

1. Hub enthält SSOT-YAML + Pflege-README + Sync-Skript.
2. Alle acht Plugin-Repos haben `.github/ISSUE_TEMPLATE/` mit denselben
   drei YAML-Dateien.
3. „New issue“ zeigt Bug- und Feature-Form; Blank Issues sind aus.
4. Bug-Form nennt explizit: verschlüsselte Logs unbrauchbar für Maintainer;
   Verbot von Secrets und Log-Anhängen; redigierte Alternativen.
5. Jede Plugin-README verlinkt auf `issues/new/choose`.
6. Keine Secrets oder Klartext-Beispiele mit echten Credentials in den
   Templates.

## Risiken

| Risiko | Mitigation |
| --- | --- |
| Drift zwischen Hub und Plugins | Sync-Skript; SSOT nur im Hub ändern |
| Melder hängen trotzdem Logs an | Template-Text + Maintainer-Antwortvorlage in SSOT-README |
| Label fehlen in manchen Repos | Labels `bug` / `enhancement` vor erstem Issue anlegen |
| Plugin-Repos sind eigene Gits | Sync nur lokal; Commit pro Repo bewusst |

## Umsetzungsreihenfolge (für Plan)

1. Hub-SSOT und Sync-Skript anlegen
2. Templates in alle acht Plugin-Checkouts synchronisieren
3. Labels prüfen/anlegen
4. README-Abschnitte in allen Plugins
5. Kurzverweis im Hub-README/Docs-Index auf `docs/issue-templates/`
