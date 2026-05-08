#Requires -Version 5.1
param(
    [switch]$SkipExport,
    [switch]$SkipPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Config ------------------------------------------------------------------

# Path to Godot 4 executable - adjust if yours is elsewhere
$GodotExe  = "C:\Users\tomko\Desktop\Godot.exe"

$Registry       = "docker.tomko.dk"
$RelayTag       = "$Registry/hellbreaker-relay:latest"
$RelayProxyTag  = "$Registry/hellbreaker-relay-proxy:latest"
$GameTag        = "$Registry/hellbreaker-game:latest"

$ProjectDir = $PSScriptRoot

# --- Helpers -----------------------------------------------------------------

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Die($msg)  { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- Prerequisites -----------------------------------------------------------

Step "Checking prerequisites"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Die "docker not found in PATH"
}

if (-not $SkipExport) {
    $candidates = @(
        $GodotExe,
        "C:\Program Files\Godot Engine\Godot.exe",
        "$env:LOCALAPPDATA\Programs\Godot\Godot.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) { Die "Godot not found. Set GodotExe at the top of deploy.ps1" }
    $GodotExe = $found
    Write-Host "  Godot : $GodotExe"
}

Write-Host "  Docker: OK"

# --- Godot HTML5 export ------------------------------------------------------

if (-not $SkipExport) {
    Step "Exporting Godot project as HTML5"

    $distDir = Join-Path $ProjectDir "dist"
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

    Push-Location $ProjectDir
    try {
        & $GodotExe --headless --export-release "Web" "dist/HellBreaker.html"
        if ($LASTEXITCODE -ne 0) { Die "Godot export failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path (Join-Path $distDir "HellBreaker.html"))) {
        Die "Export finished but dist/HellBreaker.html not found"
    }
    Write-Host "  Export OK - dist/ ready"
} else {
    Write-Host "  Skipping Godot export"
}

# --- Docker builds -----------------------------------------------------------

Push-Location $ProjectDir

Step "Building relay image        ($RelayTag)"
docker build -f deploy/Dockerfile.relay -t $RelayTag .
if ($LASTEXITCODE -ne 0) { Die "Relay image build failed" }

Step "Building relay-proxy image  ($RelayProxyTag)"
docker build -f deploy/Dockerfile.relay-proxy -t $RelayProxyTag deploy/
if ($LASTEXITCODE -ne 0) { Die "Relay-proxy image build failed" }

Step "Building game image         ($GameTag)"
docker build -f deploy/Dockerfile.game -t $GameTag .
if ($LASTEXITCODE -ne 0) { Die "Game image build failed" }

Pop-Location

# --- Push --------------------------------------------------------------------

if (-not $SkipPush) {
    Step "Pushing to $Registry"

    docker push $RelayTag
    if ($LASTEXITCODE -ne 0) { Die "Push relay failed - are you logged in? Run: docker login $Registry" }

    docker push $RelayProxyTag
    if ($LASTEXITCODE -ne 0) { Die "Push relay-proxy failed" }

    docker push $GameTag
    if ($LASTEXITCODE -ne 0) { Die "Push game failed" }

    Write-Host "`nDone. Pull and redeploy the stack in Portainer." -ForegroundColor Green
    Write-Host "  Stack file: deploy/stack.yml" -ForegroundColor Green
} else {
    Write-Host "`nImages built locally (push skipped)." -ForegroundColor Yellow
    Write-Host "  $RelayTag"
    Write-Host "  $RelayProxyTag"
    Write-Host "  $GameTag"
}
