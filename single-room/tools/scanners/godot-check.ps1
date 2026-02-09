param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

$project = Resolve-Path $ProjectRoot
$godot = $env:GODOT_PATH

if (-not $godot) {
    Write-Host "GODOT_PATH not set. Set it to your Godot executable path."
    exit 2
}

& $godot --headless --check-only --path $project
exit $LASTEXITCODE
