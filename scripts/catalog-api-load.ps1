param(
    [string]$BaseUrl = "http://k8s-library-libraryp-5f1873da46-493571967.us-east-1.elb.amazonaws.com",
    [int]$Count = 50,
    [int]$Concurrency = 10,
    [int]$TimeoutSeconds = 30,
    [string]$TitlePrefix = "HPA catalog load"
)

$ErrorActionPreference = "Stop"

if ($Count -lt 1) {
    throw "-Count must be at least 1."
}

if ($Concurrency -lt 1) {
    throw "-Concurrency must be at least 1."
}

if ($TimeoutSeconds -lt 1) {
    throw "-TimeoutSeconds must be at least 1."
}

$BaseUrl = $BaseUrl.TrimEnd('/')
$endpoint = "$BaseUrl/api/catalog/books"
$runId = [Guid]::NewGuid().ToString("N")
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$results = [System.Collections.Generic.List[object]]::new()

Write-Host "Catalog API load" -ForegroundColor Cyan
Write-Host "Endpoint: $endpoint"
Write-Host "Requests: $Count"
Write-Host "Concurrency: $Concurrency"
Write-Host "Each successful request creates one book in DynamoDB."

try {
    for ($batchStart = 0; $batchStart -lt $Count; $batchStart += $Concurrency) {
        $batchEnd = [Math]::Min($batchStart + $Concurrency, $Count)
        $pending = [System.Collections.Generic.List[object]]::new()

        for ($index = $batchStart; $index -lt $batchEnd; $index++) {
            $payload = @{
                title  = "$TitlePrefix $runId-$($index + 1)"
                author = "Cloud Computing Demo"
            } | ConvertTo-Json -Compress

            $content = [System.Net.Http.StringContent]::new(
                $payload,
                [System.Text.Encoding]::UTF8,
                "application/json"
            )

            $pending.Add([pscustomobject]@{
                Index   = $index + 1
                Content = $content
                Task    = $client.PostAsync($endpoint, $content)
            })
        }

        foreach ($request in $pending) {
            try {
                $response = $request.Task.GetAwaiter().GetResult()
                $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $results.Add([pscustomobject]@{
                    Request = $request.Index
                    Status  = [int]$response.StatusCode
                    Body    = $responseBody
                })
            }
            catch {
                $results.Add([pscustomobject]@{
                    Request = $request.Index
                    Status  = 0
                    Body    = $_.Exception.Message
                })
            }
            finally {
                $request.Content.Dispose()
            }
        }

        $completed = $results.Count
        Write-Progress -Activity "Sending catalog API requests" -Status "$completed of $Count" -PercentComplete (($completed / $Count) * 100)
    }
}
finally {
    $client.Dispose()
    Write-Progress -Activity "Sending catalog API requests" -Completed
}

$successful = @($results | Where-Object { $_.Status -eq 201 })
$failed = @($results | Where-Object { $_.Status -ne 201 })

Write-Host "Created: $($successful.Count)"
Write-Host "Failed:  $($failed.Count)"

if ($successful.Count -gt 0) {
    Write-Host "Created book responses:" -ForegroundColor Green
    $successful | ForEach-Object { $_.Body }
}

if ($failed.Count -gt 0) {
    Write-Host "Failed requests:" -ForegroundColor Red
    $failed | Format-Table Request, Status, Body -AutoSize
    exit 1
}
