# Thin wrapper to build_all.ps1 for convenience
param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$Args)

# Ensure UTF-8 to avoid mojibake
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script = Join-Path $PSScriptRoot 'build_all.ps1'
if (-not (Test-Path $script)) {
  Write-Host "[ERROR] build_all.ps1 not found next to build.ps1" -ForegroundColor Red
  exit 1
}

# Forward all args
& powershell -ExecutionPolicy Bypass -NoProfile -File $script @Args
exit $LASTEXITCODE
