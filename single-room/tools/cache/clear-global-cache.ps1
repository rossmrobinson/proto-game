param(
    [switch]$WhatIf,
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

if (-not $script:GlobalCacheDir) {
    Write-Host "Global cache dir not set. Set GODOT_GLOBAL_CACHE_DIR to use this."
    exit 2
}

Write-Host "Clearing global Godot cache"
Remove-PathSafe -Path $script:GlobalCacheDir -WhatIf:$WhatIf
