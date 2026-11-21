param(
    [string]$BaseUrl = "http://k8s-library-libraryp-5f1873da46-493571967.us-east-1.elb.amazonaws.com",
    [string]$Kubeconfig = ".local/kubeconfig",
    [string]$BookId,
    [string]$MemberId,
    [switch]$RunLoad
)

$ErrorActionPreference = "Stop"
$env:KUBECONFIG = $Kubeconfig
$BaseUrl = $BaseUrl.TrimEnd('/')

Write-Host "=== Digital Library live demo ===" -ForegroundColor Cyan
Write-Host "ALB: $BaseUrl"

Write-Host "`n--- API readiness and metrics ---" -ForegroundColor Yellow
$routes = @("member", "catalog", "reservations", "loans", "availability", "fine", "notifications")
foreach ($route in $routes) {
    $ready = Invoke-WebRequest -UseBasicParsing "$BaseUrl/api/$route/ready"
    $metrics = Invoke-WebRequest -UseBasicParsing "$BaseUrl/api/$route/metrics"
    Write-Host ("{0,-15} ready={1} metrics={2}" -f $route, $ready.StatusCode, $metrics.StatusCode)
}

Write-Host "`n--- Pods, services, ingress, HPAs ---" -ForegroundColor Yellow
kubectl --insecure-skip-tls-verify=true get pods -A -o wide
kubectl --insecure-skip-tls-verify=true get svc,ingress,hpa -n library

Write-Host "`n--- Argo CD ---" -ForegroundColor Yellow
kubectl --insecure-skip-tls-verify=true get applications -n argocd

if ($RunLoad) {
    if ([string]::IsNullOrWhiteSpace($BookId) -or [string]::IsNullOrWhiteSpace($MemberId)) {
        throw "-BookId and -MemberId are required with -RunLoad"
    }
    Write-Host "`n--- k6 sustained read-only load ---" -ForegroundColor Yellow
    $env:BASE_URL = $BaseUrl
    $env:BOOK_ID = $BookId
    $env:MEMBER_ID = $MemberId
    k6 run scripts/k6/reservation-load.js
}

Write-Host "`nDemo checks completed." -ForegroundColor Green
