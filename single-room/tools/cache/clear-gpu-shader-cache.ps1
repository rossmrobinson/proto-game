param(
    [switch]$WhatIf
)

$gpuCache = $env:GPU_SHADER_CACHE_DIR
if (-not $gpuCache) {
    Write-Host "GPU_SHADER_CACHE_DIR not set. Set it to your driver shader cache path."
    exit 2
}

Write-Host "Clearing GPU shader cache"
if (-not (Test-Path $gpuCache)) {
    Write-Host "Path not found. Skipping."
    exit 0
}

if ($WhatIf) {
    Write-Host "Dry-run only. Nothing deleted."
    exit 0
}

Remove-Item -Recurse -Force $gpuCache
