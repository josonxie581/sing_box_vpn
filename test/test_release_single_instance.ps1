# Test single instance functionality for release build
Write-Host "=== Testing Release Build Single Instance ===" -ForegroundColor Green

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
    Write-Host "Release executable not found: $exePath" -ForegroundColor Red
    Write-Host "Run 'flutter build windows --release' first" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found release executable: $exePath" -ForegroundColor Green

# Test 1: Start first instance
Write-Host "`n--- Test 1: Starting First Instance ---" -ForegroundColor Cyan
$process1 = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal
Write-Host "First instance started (PID: $($process1.Id))" -ForegroundColor Green

# Wait for app to fully start
Write-Host "Waiting for app to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

# Check if first instance is still running
$firstInstanceRunning = Get-Process | Where-Object { $_.Id -eq $process1.Id }
if ($firstInstanceRunning) {
    Write-Host "First instance is running successfully" -ForegroundColor Green
} else {
    Write-Host "ERROR: First instance exited unexpectedly!" -ForegroundColor Red
    exit 1
}

# Test 2: Try to start second instance
Write-Host "`n--- Test 2: Attempting Second Instance ---" -ForegroundColor Cyan
$process2 = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal
Write-Host "Second instance attempt (PID: $($process2.Id))" -ForegroundColor Yellow

# Wait and observe
Start-Sleep -Seconds 5

# Check process status
$runningProcesses = Get-Process | Where-Object { $_.ProcessName -like "*gsou*" }
$processCount = $runningProcesses.Count

Write-Host "`n=== Test Results ===" -ForegroundColor Green
Write-Host "Running Gsou processes: $processCount" -ForegroundColor $(if ($processCount -eq 1) { "Green" } else { "Red" })

if ($processCount -eq 1) {
    Write-Host "SUCCESS - Single instance working correctly in release build" -ForegroundColor Green
    $runningProcess = $runningProcesses[0]
    Write-Host "Running process PID: $($runningProcess.Id)" -ForegroundColor Green
} elseif ($processCount -eq 0) {
    Write-Host "ERROR - No instances running (possible crash)" -ForegroundColor Red
} else {
    Write-Host "ERROR - Multiple instances running:" -ForegroundColor Red
    foreach ($proc in $runningProcesses) {
        Write-Host "  - PID: $($proc.Id)" -ForegroundColor Red
    }
}

# Wait for user confirmation
Write-Host "`nPress any key to cleanup and test second instance activation..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Test 3: Second instance activation
Write-Host "`n--- Test 3: Second Instance Window Activation ---" -ForegroundColor Cyan
$process3 = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal
Start-Sleep -Seconds 3

$finalProcesses = Get-Process | Where-Object { $_.ProcessName -like "*gsou*" }
$finalCount = $finalProcesses.Count

if ($finalCount -eq 1) {
    Write-Host "SUCCESS - Second instance correctly activated existing window" -ForegroundColor Green
} else {
    Write-Host "WARNING - Unexpected process count: $finalCount" -ForegroundColor Yellow
}

Write-Host "`nPress any key to cleanup all processes..." -ForegroundColor Yellow
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

Write-Host "`nRelease build single instance test completed!" -ForegroundColor Green