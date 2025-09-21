# Test single instance functionality
Write-Host "=== Testing Single Instance Functionality ===" -ForegroundColor Green

# Check if gsou process is already running
$existingProcess = Get-Process | Where-Object { $_.ProcessName -like "*gsou*" } | Select-Object -First 1

if ($existingProcess) {
    Write-Host "Found running application (PID: $($existingProcess.Id))" -ForegroundColor Yellow
    Write-Host "Terminating existing process for testing..." -ForegroundColor Yellow
    Stop-Process -Id $existingProcess.Id -Force
    Start-Sleep -Seconds 2
}

$exePath = "build\windows\x64\runner\Release\Gsou.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "Executable not found: $exePath" -ForegroundColor Red
    exit 1
}

Write-Host "Found executable: $exePath" -ForegroundColor Green

# Start first instance
Write-Host "`n--- Starting First Instance ---" -ForegroundColor Cyan
$process1 = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal
Write-Host "First instance started (PID: $($process1.Id))" -ForegroundColor Green

# Wait for app to fully start
Write-Host "Waiting for app to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Try to start second instance
Write-Host "`n--- Attempting to Start Second Instance ---" -ForegroundColor Cyan
$process2 = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal

# Wait and observe
Start-Sleep -Seconds 3

# Check process status
$runningProcesses = Get-Process | Where-Object { $_.ProcessName -like "*gsou*" }
$processCount = $runningProcesses.Count

Write-Host "`n=== Test Results ===" -ForegroundColor Green
Write-Host "Running Gsou processes: $processCount" -ForegroundColor $(if ($processCount -eq 1) { "Green" } else { "Red" })

if ($processCount -eq 1) {
    Write-Host "SUCCESS - Single instance working correctly" -ForegroundColor Green
    $runningProcess = $runningProcesses[0]
    Write-Host "Running process PID: $($runningProcess.Id)" -ForegroundColor Green
} elseif ($processCount -eq 0) {
    Write-Host "ERROR - No instances running" -ForegroundColor Red
} else {
    Write-Host "ERROR - Multiple instances running:" -ForegroundColor Red
    foreach ($proc in $runningProcesses) {
        Write-Host "  - PID: $($proc.Id)" -ForegroundColor Red
    }
}

# Wait for user confirmation
Write-Host "`nPress any key to cleanup processes..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Cleanup all processes
Write-Host "`nCleaning up processes..." -ForegroundColor Cyan
$allProcesses = Get-Process | Where-Object { $_.ProcessName -like "*gsou*" }
foreach ($proc in $allProcesses) {
    try {
        Stop-Process -Id $proc.Id -Force
        Write-Host "Terminated process PID: $($proc.Id)" -ForegroundColor Green
    } catch {
        Write-Host "Cannot terminate process PID: $($proc.Id) - $_" -ForegroundColor Red
    }
}

Write-Host "`nTest completed!" -ForegroundColor Green