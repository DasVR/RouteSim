# ==============================================
# RouteSim GitHub Push Script (DasVR/RouteSim)
# Run from project root:
#   .\setup-routesim-github.ps1
# ==============================================

$ErrorActionPreference = "Stop"
$ProjectPath = "c:\Users\airfr\OneDrive\Desktop\RouteSim\StikDebug"
$GitHubUsername = "DasVR"
$RepoName = "RouteSim"
$RepoRemote = "https://github.com/$GitHubUsername/$RepoName.git"

Write-Host ""
Write-Host "RouteSim push to DasVR/RouteSim..." -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ProjectPath)) {
    throw "Project path not found: $ProjectPath"
}
Set-Location $ProjectPath

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Installing GitHub CLI..." -ForegroundColor Yellow
    winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) not found. Restart PowerShell and run again."
    }
}

$null = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub CLI not logged in. Starting auth flow..." -ForegroundColor Yellow
    gh auth login
}

# Keep StephenDev0/StikDebug as upstream if origin still points there
$originUrl = git remote get-url origin 2>$null
if ($originUrl -and $originUrl -like "*StephenDev0/StikDebug*") {
    $upstreamExists = git remote get-url upstream 2>$null
    if (-not $upstreamExists) {
        Write-Host "Renaming origin to upstream (StikDebug reference)..." -ForegroundColor Yellow
        git remote rename origin upstream
    }
}

$currentOrigin = git remote get-url origin 2>$null
if (-not $currentOrigin) {
    Write-Host "Adding origin: $RepoRemote" -ForegroundColor Yellow
    git remote add origin $RepoRemote
} elseif ($currentOrigin -ne $RepoRemote) {
    Write-Host "Setting origin: $RepoRemote" -ForegroundColor Yellow
    git remote set-url origin $RepoRemote
}

git branch -M main

$ffiPath = Join-Path $ProjectPath "StikDebug\idevice\libidevice_ffi.a"
if (-not (Test-Path $ffiPath)) {
    throw "Missing StikDebug\idevice\libidevice_ffi.a - CI requires this file."
}
$ffiSizeMB = [math]::Round((Get-Item $ffiPath).Length / 1MB, 1)
Write-Host "Found libidevice_ffi.a ($($ffiSizeMB) MB)" -ForegroundColor Green

Write-Host "Staging all files..." -ForegroundColor Yellow
git add -A

$status = git status --porcelain
if ($status) {
    $commitMessage = @"
RouteSim: public release for DasVR/RouteSim

- Full RouteSim fork (RoutePlayer, Tunnel, Simulation, Routes, Features)
- CI: build_ipa.yml produces RouteSim-Debug.ipa
- CI: swift_tests.yml for unit tests
- NOTICE.md, CONTRIBUTING.md, issue templates
- Fix OnboardingView compile errors, remove unused CodeEditorView SPM
"@
    git commit -m $commitMessage
    Write-Host "Commit created." -ForegroundColor Green
} else {
    Write-Host "Nothing new to commit." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Force-pushing to $RepoRemote (replaces remote stub)..." -ForegroundColor Cyan
git push -u origin main --force

Write-Host "Setting repository topics..." -ForegroundColor Yellow
gh repo edit "$GitHubUsername/$RepoName" `
    --add-topic ios `
    --add-topic swiftui `
    --add-topic location-simulation `
    --add-topic developer-tools `
    --add-topic routes `
    --add-topic gpx `
    --add-topic gtfs `
    --add-topic life360-testing `
    --add-topic mapkit `
    --add-topic sideloading

Write-Host "Triggering Build Debug IPA workflow..." -ForegroundColor Cyan
gh workflow run "Build Debug IPA" --repo "$GitHubUsername/$RepoName"

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "  Repo:    https://github.com/$GitHubUsername/$RepoName" -ForegroundColor Yellow
Write-Host "  Actions: https://github.com/$GitHubUsername/$RepoName/actions" -ForegroundColor Yellow
Write-Host ""
Write-Host "Download RouteSim-Debug.ipa from Artifacts when the build is green." -ForegroundColor Cyan
Write-Host "If the build fails, paste the error from the failing step." -ForegroundColor Gray
Write-Host ""
