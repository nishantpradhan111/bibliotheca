param(
    [Parameter(Position = 0)]
    [string]$Name,

    [switch]$Json
)

$ErrorActionPreference = "Stop"

# Resolve the repository root from this script, so the command works from any
# PowerShell working directory and after a terminal is reopened.
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$InfraDirectory = Join-Path $RepositoryRoot "infra"

if (-not (Test-Path -LiteralPath (Join-Path $InfraDirectory "outputs.tf"))) {
    throw "Terraform configuration was not found at $InfraDirectory"
}

$Arguments = @("-chdir=$InfraDirectory", "output")
if ($Json) {
    $Arguments += "-json"
}
if ($Name) {
    $Arguments += $Name
}

& terraform @Arguments
exit $LASTEXITCODE
