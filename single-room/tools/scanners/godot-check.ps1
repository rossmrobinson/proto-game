param(
    [string]$ProjectRoot = "$PSScriptRoot/../.."
)

$project = Resolve-Path $ProjectRoot
$godot = $env:GODOT_PATH

if (-not $godot) {
    Write-Host "GODOT_PATH not set. Set it to your Godot executable path."
    exit 2
}

$output = & $godot --headless --editor --quit --path $project 2>&1
$exitCode = $LASTEXITCODE

if ($output) {
    $output | ForEach-Object { Write-Host $_ }
}

if ($exitCode -ne 0) {
    exit $exitCode
}

$errorPatterns = @(
    "SCRIPT ERROR:"
    "Parse Error:"
    "Compile Error:"
    "Failed to load script"
    "is not compiling"
)

$joined = ($output | Out-String)
foreach ($pattern in $errorPatterns) {
    if ($joined -match [regex]::Escape($pattern)) {
        Write-Host "Godot check detected compile errors in output."
        exit 1
    }
}

exit 0
