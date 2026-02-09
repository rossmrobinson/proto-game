param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

$project = Resolve-Path $ProjectRoot
$python = $env:PYTHON
if (-not $python) {
    $python = "python"
}

$errors = 0

function Run-Scanner {
    param([string]$Script)
    Write-Host "Running $Script"
    & $python "$PSScriptRoot/$Script" --root $project
    if ($LASTEXITCODE -ne 0) {
        $script:errors = 1
    }
}

Run-Scanner "hardcoded-values-scan.py"
Run-Scanner "layer-mask-audit.py"
Run-Scanner "unused-resource-scan.py"
Run-Scanner "todo-tracker.py"
Run-Scanner "complexity-scan.py"
Run-Scanner "scene-validator.py"

if ($env:GODOT_PATH) {
    Write-Host "Running Godot check"
    & "$PSScriptRoot/godot-check.ps1" -ProjectRoot $project
    if ($LASTEXITCODE -ne 0) {
        $errors = 1
    }
} else {
    Write-Host "GODOT_PATH not set. Skipping Godot check."
}

if ($errors -ne 0) {
    exit 1
}

Write-Host "All scanners passed"
exit 0
