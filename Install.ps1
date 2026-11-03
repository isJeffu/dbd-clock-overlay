# Hands over to scripts\Install.ps1. Kept here because v1.0.3's updater runs
# "Install.ps1" from the top of the downloaded package.
param([string]$Dest, [string]$LinkDir, [switch]$Update, [switch]$NoDownload, [string]$AutoStart, [string]$StartNow)
& (Join-Path $PSScriptRoot 'scripts\Install.ps1') @PSBoundParameters
