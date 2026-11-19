<#
.SYNOPSIS
    Собирает архив релиза и файл контрольных сумм SHA256.

.DESCRIPTION
    Формирует ZIP с полным набором файлов, необходимых для запуска
    (Start.cmd, Run-Simulator.ps1, lib/), считает SHA256 и выводит
    готовый текст для релиза на GitHub.

.EXAMPLE
    .\build\Build-Release.ps1 -Version 1.1.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'out')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$name = 'Discord.Games.Simulator.' + $Version
$staging = Join-Path $OutputDirectory $name

# Файлы, без которых симулятор не запустится.
$includes = @(
    'Start.cmd'
    'Run-Simulator.ps1'
    'lib/SimulatorCore.ps1'
    'lib/Placeholder.cs'
    'README.md'
    'LICENSE'
    'CHANGELOG.md'
)

if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

foreach ($relative in $includes) {
    $source = Join-Path $projectRoot $relative
    if (-not (Test-Path -LiteralPath $source)) {
        throw ('Отсутствует обязательный файл: {0}' -f $relative)
    }
    $destination = Join-Path $staging $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

# Проверка, что в архив не попали рабочие данные.
$unwanted = Get-ChildItem -LiteralPath $staging -Recurse -Include '*.exe', 'history.csv', '*.log'
if ($unwanted) {
    throw ('В архив попали рабочие файлы: {0}' -f (($unwanted | ForEach-Object FullName) -join ', '))
}

$zipPath = Join-Path $OutputDirectory ($name + '.zip')
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -CompressionLevel Optimal

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$sumsPath = Join-Path $OutputDirectory 'SHA256SUMS.txt'
('{0}  {1}' -f $hash, (Split-Path -Path $zipPath -Leaf)) |
    Set-Content -LiteralPath $sumsPath -Encoding ASCII

Write-Host ''
Write-Host ('Готово: {0}' -f $zipPath) -ForegroundColor Green
Write-Host ('SHA256: {0}' -f $hash) -ForegroundColor Cyan
Write-Host ('Суммы:  {0}' -f $sumsPath)
Write-Host ''
Write-Host 'Приложите к релизу ZIP и SHA256SUMS.txt.' -ForegroundColor Yellow
