# =============================================================================
# Etrna Chain Dev — PowerShell Anvil Launcher (Windows)
# =============================================================================
# Usage: .\start-anvil.ps1 [-Fork]
# =============================================================================

param(
    [switch]$Fork
)

$SnapshotDir = "D:\ETRNA\chains\snapshots"
New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null

if ($Fork) {
    Write-Host ">> Starting Anvil with mainnet fork..." -ForegroundColor Cyan
    # Load env if available
    if (Test-Path "$PSScriptRoot\..\docker\.env") {
        Get-Content "$PSScriptRoot\..\docker\.env" | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
            }
        }
    }
    $forkUrl = if ($env:FORK_RPC_URL) { $env:FORK_RPC_URL } else { "https://eth-mainnet.g.alchemy.com/v2/demo" }
    
    anvil `
        --fork-url $forkUrl `
        --host 0.0.0.0 `
        --port 8545 `
        --accounts 10 `
        --balance 10000 `
        --block-time 1 `
        --state "$SnapshotDir\fork-state.json"
} else {
    Write-Host ">> Starting local Anvil chain..." -ForegroundColor Cyan
    anvil `
        --host 0.0.0.0 `
        --port 8545 `
        --accounts 10 `
        --balance 10000 `
        --block-time 1 `
        --state "$SnapshotDir\local-state.json"
}
