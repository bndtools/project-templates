param(
    [Parameter(Mandatory = $true)]
    [string] $Workspace,
    [string] $BndJar = (Join-Path $HOME "biz.aQute.bnd.jar")
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$env:BND_MIN_WORKSPACE = (Resolve-Path $Workspace).Path
$env:BND_JAR = (Resolve-Path $BndJar).Path

Push-Location $repoRoot
try {
    & python -m unittest discover -s tests -p "test_min_workspace_templates.py" -v
    exit $LASTEXITCODE
} finally {
    Pop-Location
}