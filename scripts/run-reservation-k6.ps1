param(
    [string]$BaseUrl = "http://k8s-library-libraryp-5f1873da46-493571967.us-east-1.elb.amazonaws.com",
    [string]$BookId = "78b082b2-5f62-49a3-8f9d-f0b4e656ae09",
    [string]$MemberId = "f2573e6a-5119-4cdc-a63d-1b64fec78ab6",
    [switch]$NoGrafana,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$K6Script = Join-Path $RepositoryRoot "scripts\k6\reservation-load.js"
$GrafanaLauncher = Join-Path $RepositoryRoot "scripts\launch-grafana.ps1"
$BaseUrl = $BaseUrl.TrimEnd('/')

if (-not (Test-Path -LiteralPath $K6Script)) {
    throw "Reservation k6 script was not found at $K6Script"
}

if (-not $NoGrafana -and -not (Test-Path -LiteralPath $GrafanaLauncher)) {
    throw "Grafana launcher was not found at $GrafanaLauncher"
}

if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 is not installed or is not available on PATH. Install k6 before running this script."
}

$env:BASE_URL = $BaseUrl
$env:BOOK_ID = $BookId
$env:MEMBER_ID = $MemberId

Write-Host "Reservation k6 load test" -ForegroundColor Cyan
Write-Host "Base URL: $env:BASE_URL"
Write-Host "Book ID: $env:BOOK_ID"
Write-Host "Member ID: $env:MEMBER_ID"
Write-Host "The test is read-only and runs for approximately six minutes."

if ($DryRun) {
    Write-Host "Dry run: k6 was not started." -ForegroundColor Yellow
    exit 0
}

if (-not $NoGrafana) {
    Write-Host "Starting Grafana dashboard and local port-forward..." -ForegroundColor Yellow
    & powershell -ExecutionPolicy Bypass -File $GrafanaLauncher
    if ($LASTEXITCODE -ne 0) {
        throw "Grafana could not be started; k6 was not run."
    }
}

& k6 run $K6Script
exit $LASTEXITCODE
