#Requires -Version 7
<#
.SYNOPSIS
  Kopiert Hub-Issue-Template-YAML in alle lokalen *-MoneyMoney-Checkouts.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDir = Join-Path $RepoRoot 'docs/issue-templates'
$templateFiles = @(
    'bug_report.yml'
    'feature_request.yml'
    'config.yml'
)

foreach ($name in $templateFiles) {
    $path = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "SSOT-Datei fehlt: $path"
    }
}

$pluginDirs = Get-ChildItem -LiteralPath $RepoRoot -Directory -Filter '*-MoneyMoney' |
    Sort-Object -Property Name

if ($pluginDirs.Count -eq 0) {
    throw "Keine Plugin-Checkouts (*-MoneyMoney) unter $RepoRoot"
}

$expected = @(
    'Amazon-MoneyMoney'
    'Bank-of-America-MoneyMoney'
    'Fidelity-MoneyMoney'
    'Givve-MoneyMoney'
    'MLP-Versicherungen-MoneyMoney'
    'Pluxee-MoneyMoney'
    'Presidential-Bank-MoneyMoney'
    'Shareview-MoneyMoney'
)

$foundNames = @($pluginDirs | ForEach-Object Name)
foreach ($name in $expected) {
    if ($foundNames -notcontains $name) {
        throw "Erwarteter Plugin-Checkout fehlt: $name"
    }
}

foreach ($plugin in $pluginDirs) {
    if ($expected -notcontains $plugin.Name) {
        Write-Warning "Unerwarteter Ordner übersprungen: $($plugin.Name)"
        continue
    }

    $targetDir = Join-Path $plugin.FullName '.github/ISSUE_TEMPLATE'
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    foreach ($name in $templateFiles) {
        $src = Join-Path $sourceDir $name
        $dst = Join-Path $targetDir $name
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    Write-Output "Synced $($plugin.Name)"
}

Write-Output "Fertig: $($expected.Count) Plugin-Repos aktualisiert."
