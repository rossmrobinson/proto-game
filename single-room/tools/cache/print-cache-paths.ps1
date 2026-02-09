param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

Write-Host "Project root: $script:ProjectRoot"
Write-Host "Project name: $script:ProjectName"
Write-Host "Project cache: $script:ProjectCacheDir"
Write-Host "User data dir: $script:UserDataDir"
Write-Host "Global cache dir: $script:GlobalCacheDir"
