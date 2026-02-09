param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

. "$PSScriptRoot/cache-utils.ps1" -ProjectRoot $ProjectRoot

function Get-DirSizeBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) {
        return 0
    }
    try {
        $bytes = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction Stop |
            Measure-Object -Property Length -Sum |
            Select-Object -ExpandProperty Sum
        if (-not $bytes) {
            return 0
        }
        return [int64]$bytes
    } catch {
        return 0
    }
}

function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -lt 1024) { return "$Bytes B" }
    if ($Bytes -lt 1048576) { return "{0:N1} KB" -f ($Bytes / 1024.0) }
    if ($Bytes -lt 1073741824) { return "{0:N1} MB" -f ($Bytes / 1048576.0) }
    return "{0:N2} GB" -f ($Bytes / 1073741824.0)
}

$projectCacheSize = Get-DirSizeBytes -Path $script:ProjectCacheDir
$userDataSize = Get-DirSizeBytes -Path $script:UserDataDir
$logsDir = if ($script:UserDataDir) { Join-Path $script:UserDataDir "logs" } else { "" }
$logsSize = Get-DirSizeBytes -Path $logsDir
$globalSize = Get-DirSizeBytes -Path $script:GlobalCacheDir

Write-Host "Project root: $script:ProjectRoot"
Write-Host "Project name: $script:ProjectName"
Write-Host "Project cache: $script:ProjectCacheDir ($([string](Format-Bytes -Bytes $projectCacheSize)))"
Write-Host "User data dir: $script:UserDataDir ($([string](Format-Bytes -Bytes $userDataSize)))"
Write-Host "Logs dir: $logsDir ($([string](Format-Bytes -Bytes $logsSize)))"
Write-Host "Global cache dir: $script:GlobalCacheDir ($([string](Format-Bytes -Bytes $globalSize)))"
