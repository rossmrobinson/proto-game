param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

function Get-ProjectRoot {
    param([string]$Root)
    return (Resolve-Path $Root)
}

function Get-ProjectName {
    param([string]$Root)
    $projectFile = Join-Path $Root "project.godot"
    if (-not (Test-Path $projectFile)) {
        return ""
    }
    $line = Select-String -Path $projectFile -Pattern "config/name" | Select-Object -First 1
    if (-not $line) {
        return ""
    }
    if ($line.Line -match 'config/name="([^"]+)"') {
        return $Matches[1]
    }
    return ""
}

function Get-UserDataDir {
    param([string]$ProjectName)
    if ($env:GODOT_USERDATA_DIR) {
        return $env:GODOT_USERDATA_DIR
    }
    if (-not $ProjectName) {
        return ""
    }
    if ($env:APPDATA) {
        return (Join-Path $env:APPDATA "Godot/app_userdata/$ProjectName")
    }
    if ($env:USERPROFILE) {
        return (Join-Path $env:USERPROFILE "AppData/Roaming/Godot/app_userdata/$ProjectName")
    }
    return ""
}

function Get-ProjectCacheDir {
    param([string]$Root)
    return (Join-Path $Root ".godot")
}

function Get-GlobalCacheDir {
    if ($env:GODOT_GLOBAL_CACHE_DIR) {
        return $env:GODOT_GLOBAL_CACHE_DIR
    }
    return ""
}

function Remove-PathSafe {
    param(
        [string]$Path,
        [switch]$WhatIf
    )
    if (-not $Path) {
        Write-Host "No path provided"
        return
    }
    Write-Host "Target: $Path"
    if (-not (Test-Path $Path)) {
        Write-Host "Path not found. Skipping."
        return
    }
    if ($WhatIf) {
        Write-Host "Dry-run only. Nothing deleted."
        return
    }
    Remove-Item -Recurse -Force $Path
}

$script:ProjectRoot = Get-ProjectRoot -Root $ProjectRoot
$script:ProjectName = Get-ProjectName -Root $script:ProjectRoot
$script:UserDataDir = Get-UserDataDir -ProjectName $script:ProjectName
$script:ProjectCacheDir = Get-ProjectCacheDir -Root $script:ProjectRoot
$script:GlobalCacheDir = Get-GlobalCacheDir
