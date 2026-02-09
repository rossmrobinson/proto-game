param(
    [switch]$WhatIf,
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

Write-Host "Nuclear cache clear: project + user + global + GPU shader"

& "$PSScriptRoot/clear-all-caches.ps1" -ProjectRoot $ProjectRoot -IncludeGlobal -WhatIf:$WhatIf
& "$PSScriptRoot/clear-gpu-shader-cache.ps1" -WhatIf:$WhatIf
