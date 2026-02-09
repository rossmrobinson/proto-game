param(
    [switch]$IncludeGlobal,
    [switch]$WhatIf,
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

Write-Host "Clearing project cache (.godot)"
Remove-PathSafe -Path $script:ProjectCacheDir -WhatIf:$WhatIf

if (-not $script:UserDataDir) {
    Write-Host "User data dir not resolved. Set GODOT_USERDATA_DIR or APPDATA."
} else {
    Write-Host "Clearing user data dir"
    Remove-PathSafe -Path $script:UserDataDir -WhatIf:$WhatIf
}

if ($IncludeGlobal) {
    if (-not $script:GlobalCacheDir) {
        Write-Host "Global cache dir not set. Set GODOT_GLOBAL_CACHE_DIR to use this."
    } else {
        Write-Host "Clearing global Godot cache"
        Remove-PathSafe -Path $script:GlobalCacheDir -WhatIf:$WhatIf
    }
}
