# Bibliotheca: inspect Kafka analytics topics and read Flink output.
# Assumes kubectl is already configured for the correct EKS cluster.

$Namespace = "library"
$KafkaPod = "kafka-0"
$BootstrapServer = "kafka:9092"
$MaxMessages = 10
$ConsumerTimeoutMs = 10000

function Invoke-KafkaConsumer {
    param(
        [Parameter(Mandatory = $true)][string]$Topic
    )

    Write-Host "`n=== First $MaxMessages messages from $Topic ===" -ForegroundColor Cyan
    Write-Host "Reading from the beginning; stops after $MaxMessages messages or $ConsumerTimeoutMs ms without a new message.`n"

    $output = @(
        & kubectl exec $KafkaPod -n $Namespace -- /opt/kafka/bin/kafka-console-consumer.sh `
            --bootstrap-server $BootstrapServer `
            --topic $Topic `
            --from-beginning `
            --max-messages $MaxMessages `
            --timeout-ms $ConsumerTimeoutMs 2>&1 |
            ForEach-Object { "$_" }
    )
    $consumerExitCode = $LASTEXITCODE
    $outputText = $output -join "`n"

    # Kafka's console consumer reports an idle timeout as a TimeoutException.
    # That is expected when it has read all available records, so hide that stack/error
    # and report the number of records consumed instead.
    $isExpectedTimeout = $outputText -match 'TimeoutException|Error processing message'
    $countMatch = [regex]::Match($outputText, 'Processed a total of (\d+) messages')

    foreach ($line in $output) {
        if ($line -match 'ERROR Error processing message|org\.apache\.kafka\.common\.errors\.TimeoutException|^\s*at\s+') {
            continue
        }
        if ($line -match '^\s*\(org\.apache\.kafka\.tools\.consumer\.ConsoleConsumer\)\s*$') {
            continue
        }
        if ($line.Trim()) {
            Write-Host $line
        }
    }

    if ($countMatch.Success) {
        $messageCount = [int]$countMatch.Groups[1].Value
        if ($messageCount -gt 0) {
            Write-Host "Read $messageCount message(s) from '$Topic'." -ForegroundColor Green
        }
        else {
            Write-Host "No messages found in '$Topic' during the $($ConsumerTimeoutMs / 1000)-second wait." -ForegroundColor Yellow
        }
    }
    elseif ($consumerExitCode -ne 0) {
        Write-Host "Consumer command failed for '$Topic' (exit code $consumerExitCode). Check the Kafka pod and topic." -ForegroundColor Red
        if (-not $isExpectedTimeout) {
            $output | ForEach-Object { Write-Host $_ }
        }
    }
}

Write-Host "`n=== Kafka pods ===" -ForegroundColor Cyan
kubectl get pods -n $Namespace | Select-String "kafka"
if ($LASTEXITCODE -ne 0) { throw "Could not list pods in namespace '$Namespace'." }

Write-Host "`n=== Kafka topics ===" -ForegroundColor Cyan
$topicOutput = @(
    & kubectl exec $KafkaPod -n $Namespace -- /opt/kafka/bin/kafka-topics.sh `
        --bootstrap-server $BootstrapServer --list 2>&1 |
        ForEach-Object { "$_" }
)
if ($LASTEXITCODE -ne 0) {
    $topicOutput | ForEach-Object { Write-Host $_ }
    throw "Could not list Kafka topics. Check that '$KafkaPod' is running."
}

$topics = @($topicOutput | Where-Object { $_.Trim() })
$topics | ForEach-Object { Write-Host $_ }

# Prefer the newest timestamped demo output topic (the bounded Flink demo),
# then also inspect the long-lived v1 output topic.
$demoTopic = $topics |
    Where-Object { $_ -match '^library\.analytics\.results\.demo\.\d+$' } |
    Sort-Object -Descending |
    Select-Object -First 1

$topicsToInspect = @()
if ($demoTopic) { $topicsToInspect += $demoTopic }
if ($topics -contains "library.analytics.results.v1") {
    $topicsToInspect += "library.analytics.results.v1"
}

if ($topicsToInspect.Count -eq 0) {
    Write-Host "`nNo analytics results topics were found." -ForegroundColor Yellow
    Write-Host "Look for library.analytics.results.demo.<timestamp> or library.analytics.results.v1."
}
else {
    foreach ($topic in $topicsToInspect) {
        Write-Host "`n=== Topic details: $topic ===" -ForegroundColor Cyan
        kubectl exec $KafkaPod -n $Namespace -- /opt/kafka/bin/kafka-topics.sh `
            --bootstrap-server $BootstrapServer --describe --topic $topic
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Could not describe '$topic'; skipping its messages." -ForegroundColor Yellow
            continue
        }

        Invoke-KafkaConsumer -Topic $topic
    }
}

Write-Host "`nDone." -ForegroundColor Green
