param(
    [int]$Port = 13000,
    [switch]$NoBrowser,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Kubeconfig = Join-Path $RepositoryRoot ".local\kubeconfig"
$LocalDirectory = Join-Path $RepositoryRoot ".local"
$PidFile = Join-Path $LocalDirectory "grafana-port-forward.pid"
$StdoutLog = Join-Path $LocalDirectory "grafana-port-forward.stdout.log"
$StderrLog = Join-Path $LocalDirectory "grafana-port-forward.stderr.log"

if (-not (Test-Path -LiteralPath $Kubeconfig)) {
    throw "Kubeconfig was not found at $Kubeconfig"
}

function Stop-GrafanaForward {
    if (Test-Path -LiteralPath $PidFile) {
        $ForwardPid = [int](Get-Content -LiteralPath $PidFile -Raw).Trim()
        $ForwardProcess = Get-Process -Id $ForwardPid -ErrorAction SilentlyContinue
        if ($ForwardProcess) {
            Stop-Process -Id $ForwardPid -Force
            Write-Host "Stopped Grafana port-forward process $ForwardPid."
        }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) {
    Stop-GrafanaForward
    exit 0
}

if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    Write-Host "Grafana is already available at http://127.0.0.1:$Port"
    if (-not $NoBrowser) {
        Start-Process "http://127.0.0.1:$Port/d/library-services-live"
    }
    exit 0
}

$KubectlArguments = @(
    "--kubeconfig", "`"$Kubeconfig`"",
    "--insecure-skip-tls-verify=true",
    "-n", "observability",
    "port-forward",
    "service/library-observability-grafana",
    "${Port}:80",
    "--address", "127.0.0.1"
)

$Ready = $false
$ForwardProcess = $null
for ($ConnectionAttempt = 1; $ConnectionAttempt -le 3 -and -not $Ready; $ConnectionAttempt++) {
    $ForwardProcess = Start-Process `
        -FilePath "kubectl" `
        -ArgumentList $KubectlArguments `
        -WorkingDirectory $RepositoryRoot `
        -RedirectStandardOutput $StdoutLog `
        -RedirectStandardError $StderrLog `
        -PassThru

    Set-Content -LiteralPath $PidFile -Value $ForwardProcess.Id

    for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
        Start-Sleep -Milliseconds 500
        if ($ForwardProcess.HasExited) {
            break
        }
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
            $Ready = $true
            break
        }
    }

    if (-not $Ready -and $ForwardProcess.HasExited -and $ConnectionAttempt -lt 3) {
        Start-Sleep -Seconds 2
    }
}

if (-not $Ready) {
    $ErrorText = if (Test-Path $StderrLog) { Get-Content $StderrLog -Raw } else { "unknown kubectl error" }
    throw "Could not start Grafana port-forward after three attempts: $ErrorText"
}

$GrafanaUrl = "http://127.0.0.1:$Port/d/library-services-live"
Write-Host "Grafana is available at $GrafanaUrl"
Write-Host "Port-forward PID: $($ForwardProcess.Id)"
Write-Host "Stop it with: powershell -ExecutionPolicy Bypass -File .\scripts\launch-grafana.ps1 -Stop"

if (-not $NoBrowser) {
    Start-Process $GrafanaUrl
}
