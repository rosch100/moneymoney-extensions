# Issue-Templates (SSOT)

Einheitliche GitHub Issue Forms für alle MoneyMoney-Lua-Plugin-Repositories.

Design: [2026-09-06-github-issue-templates-design.md](../superpowers/specs/2026-09-06-github-issue-templates-design.md)

## Dateien

| Datei | Zweck |
| --- | --- |
| `bug_report.yml` | Bug-Form |
| `feature_request.yml` | Feature-Form |
| `config.yml` | Blank Issues aus; Link zum Hub |

Nur diese drei YAML-Dateien werden in die Plugin-Repos kopiert — nicht diese README.

## Sync

Vom Hub-Root:

```powershell
pwsh -NoProfile -File scripts/Sync-IssueTemplates.ps1
```

Erwartet die Checkouts `*-MoneyMoney/` neben dem Hub. Fehlende Ordner
brechen mit Fehler ab (kein stilles Überspringen).

Commit und Push in den Plugin-Repos sind manuell.

## Labels

In jedem Plugin-Repo müssen `bug` und `enhancement` existieren, bevor die
Forms genutzt werden:

```powershell
gh label create bug --color d73a4a --description "Fehler" --repo rosch100/<Repo>
gh label create enhancement --color a2eeef --description "Verbesserung" --repo rosch100/<Repo>
```

(Bereits vorhandene Labels: `gh` meldet einen Fehler — dann ignorieren.)

## Maintainer-Antwortvorlage

Wenn ein Issue trotzdem eine Logdatei oder Secrets enthält:

> Danke für den Report. Angehängte MoneyMoney-Logdateien bzw. Diagnose-Archive
> können wir als Community-Maintainer in der Regel **nicht** auswerten (oft nur
> für MoneyMoney lesbar) und sie können vertrauliche Daten enthalten.
>
> Bitte den Anhang entfernen bzw. das Issue bereinigen und stattdessen einen
> **redigierten** Ausschnitt aus **Fenster → Protokollfenster** (Text) nachreichen.
> Keine Passwörter, Cookies (`COOKIE:…`), Tokens, OTP/TAN oder vollständigen
> Kontonummern posten.

Anhänge nicht weiterverbreiten.
