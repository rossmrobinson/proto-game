param(
    [switch]$All,
    [switch]$WhatIf,
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

if (-not $script:UserDataDir) {
    Write-Host "User data dir not resolved. Set GODOT_USERDATA_DIR or APPDATA."
    exit 2
}

if ($All) {
    Write-Host "Clearing user data dir"
    Remove-PathSafe -Path $script:UserDataDir -WhatIf:$WhatIf
    exit 0
}

$logsDir = Join-Path $script:UserDataDir "logs"
Write-Host "Clearing user logs only"
Remove-PathSafe -Path $logsDir -WhatIf:$WhatIf
