param(
    [switch]$WhatIf,
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

Write-Host "Clearing project cache (.godot)"
Remove-PathSafe -Path $script:ProjectCacheDir -WhatIf:$WhatIf
