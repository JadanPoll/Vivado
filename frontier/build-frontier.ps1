param(
    [string]$Source,
    [string]$Output,
    [string]$CaseDirectory = 'C:\Vivado\work\cases\SRL16E'
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot
$workspace = Split-Path $repository
$node = Join-Path $workspace '.frontier\toolchain\node-v22.23.4-win-x64\node.exe'
if (-not $Source) { $Source = Join-Path $repository 'PRODUCTION_GRADE' }
if (-not $Output) { $Output = Join-Path $repository 'Frontier_Grade' }
$candidate = "$Output.candidate-$PID"
$oracleOutput = Join-Path 'C:\Vivado\work' "frontier-oracle-$PID"

if (-not (Test-Path -LiteralPath $node -PathType Leaf)) {
    throw "Pinned Node 22.23.4 is absent: $node"
}
if (-not (Test-Path -LiteralPath $CaseDirectory -PathType Container)) {
    throw "SRL16E oracle case is absent: $CaseDirectory"
}

try {
    & $node (Join-Path $PSScriptRoot 'package-frontier.mjs') $Source $candidate
    if ($LASTEXITCODE -ne 0) { throw 'Frontier packaging failed' }

    $env:FPGA_ASSET_DIR = $candidate
    $env:PNR_CASE_DIR = $CaseDirectory
    $env:PNR_OUTPUT_DIR = $oracleOutput
    $env:PNR_ONLY = Split-Path $CaseDirectory -Leaf
    $env:PNR_TOP = 'top'
    & $node (Join-Path $repository 'tests\headless-pnr-matrix.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'SRL16E promotion oracle failed' }

    $fasm = Get-ChildItem -LiteralPath $oracleOutput -Recurse -Filter 'original.fasm' | Select-Object -First 1
    if (-not $fasm -or -not (Select-String -LiteralPath $fasm.FullName -Quiet -Pattern '\.SRL$')) {
        throw 'SRL16E promotion oracle did not emit an SRL FASM feature'
    }

    $env:PNR_RESULT_DIR = $fasm.DirectoryName
    & $node (Join-Path $repository 'tests\headless-serv-fasm-audit.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'FASM coverage oracle failed' }
    & $node (Join-Path $repository 'tests\headless-serv-bitgen.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Frames2Bit oracle failed' }

    if (Test-Path -LiteralPath $Output) {
        $backup = "$Output.previous-$(Get-Date -Format 'yyyyMMddTHHmmss')"
        [IO.Directory]::Move($Output, $backup)
        Write-Host "FRONTIER_PREVIOUS=$backup"
    }
    [IO.Directory]::Move($candidate, $Output)
} finally {
    Remove-Item Env:FPGA_ASSET_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:PNR_CASE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:PNR_OUTPUT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:PNR_RESULT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:PNR_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:PNR_TOP -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $candidate) {
        Remove-Item -LiteralPath $candidate -Recurse -Force
    }
    if (Test-Path -LiteralPath $oracleOutput) {
        Remove-Item -LiteralPath $oracleOutput -Recurse -Force
    }
}

Write-Host "FRONTIER_STATUS=PASS"
Write-Host "FRONTIER_OUTPUT=$Output"
