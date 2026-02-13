param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

$project = Resolve-Path $ProjectRoot
$python = $env:PYTHON
if (-not $python) {
    $python = "python"
}

$errors = 0

$scanners = @(
    "bone-map-alignment-scan.py"
    "hardcoded-values-scan.py"
    "layer-mask-audit.py"
    "unused-resource-scan.py"
    "todo-tracker.py"
    "complexity-scan.py"
    "scene-validator.py"
)

foreach ($scanner in $scanners) {
    Write-Host "Running $scanner"
    & $python "$PSScriptRoot/$scanner" --root $project
    if ($LASTEXITCODE -ne 0) {
        $errors = 1
    }
}

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
