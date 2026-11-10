# Copies this addon into the WoW: Forever AddOns folder.
#   powershell -ExecutionPolicy Bypass -File deploy.ps1
param(
	[string]$AddOns = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
)
$ErrorActionPreference = 'Stop'
$dst = Join-Path $AddOns 'PallyPower_EllesmereUI'
New-Item -ItemType Directory -Force $dst | Out-Null
robocopy $PSScriptRoot $dst *.toc *.lua /PURGE /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
Write-Host "Installed to $dst"
