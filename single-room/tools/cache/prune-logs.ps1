param(
    [int]$Days = 7,
    [switch]$WhatIf,
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

if (-not $script:UserDataDir) {
    Write-Host "User data dir not resolved. Set GODOT_USERDATA_DIR or APPDATA."
    exit 2
}

$logsDir = Join-Path $script:UserDataDir "logs"
if (-not (Test-Path $logsDir)) {
    Write-Host "Logs dir not found. Nothing to prune."
    exit 0
}

$cutoff = (Get-Date).AddDays(-$Days)
$files = Get-ChildItem -Path $logsDir -File -Recurse | Where-Object { $_.LastWriteTime -lt $cutoff }

if ($WhatIf) {
    Write-Host "Dry-run: would delete $($files.Count) log file(s) older than $Days days"
    $files | ForEach-Object { Write-Host "- $($_.FullName)" }
    exit 0
}

$files | Remove-Item -Force
Write-Host "Deleted $($files.Count) log file(s) older than $Days days"
