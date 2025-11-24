using module .\Modules\FFU.Constants\FFU.Constants.psm1

Write-Host "=== Testing FFU.Constants Module ===" -ForegroundColor Green

# Test module loaded
Write-Host "`n1. Module Loading:" -ForegroundColor Cyan
Write-Host "   Constants module loaded successfully" -ForegroundColor Green

# Test path constants
Write-Host "`n2. Path Constants:" -ForegroundColor Cyan
Write-Host "   DEFAULT_WORKING_DIR: $([FFUConstants]::DEFAULT_WORKING_DIR)"
Write-Host "   DEFAULT_VM_DIR: $([FFUConstants]::DEFAULT_VM_DIR)"
Write-Host "   DEFAULT_CAPTURE_DIR: $([FFUConstants]::DEFAULT_CAPTURE_DIR)"

# Test VM configuration constants
Write-Host "`n3. VM Configuration:" -ForegroundColor Cyan
Write-Host "   DEFAULT_VM_MEMORY: $([FFUConstants]::DEFAULT_VM_MEMORY) bytes ($(([FFUConstants]::DEFAULT_VM_MEMORY)/1GB)GB)"
Write-Host "   DEFAULT_VHDX_SIZE: $([FFUConstants]::DEFAULT_VHDX_SIZE) bytes ($(([FFUConstants]::DEFAULT_VHDX_SIZE)/1GB)GB)"
Write-Host "   DEFAULT_VM_PROCESSORS: $([FFUConstants]::DEFAULT_VM_PROCESSORS)"

# Test validation limits
Write-Host "`n4. Validation Limits:" -ForegroundColor Cyan
Write-Host "   MIN_VM_MEMORY: $(([FFUConstants]::MIN_VM_MEMORY)/1GB)GB"
Write-Host "   MAX_VM_MEMORY: $(([FFUConstants]::MAX_VM_MEMORY)/1GB)GB"
Write-Host "   MIN_VHDX_SIZE: $(([FFUConstants]::MIN_VHDX_SIZE)/1GB)GB"
Write-Host "   MAX_VHDX_SIZE: $(([FFUConstants]::MAX_VHDX_SIZE)/1GB)GB"

# Test timeout constants
Write-Host "`n5. Timeout Constants (seconds):" -ForegroundColor Cyan
Write-Host "   VM_STARTUP_TIMEOUT: $([FFUConstants]::VM_STARTUP_TIMEOUT)"
Write-Host "   DISM_PACKAGE_TIMEOUT: $([FFUConstants]::DISM_PACKAGE_TIMEOUT)"

# Test wait times
Write-Host "`n6. Wait Times:" -ForegroundColor Cyan
Write-Host "   DISM_SERVICE_WAIT: $([FFUConstants]::DISM_SERVICE_WAIT) seconds"
Write-Host "   VM_STATE_POLL_INTERVAL: $([FFUConstants]::VM_STATE_POLL_INTERVAL) seconds"
Write-Host "   DISM_CLEANUP_WAIT: $([FFUConstants]::DISM_CLEANUP_WAIT) seconds"
Write-Host "   PROCESS_POLL_INTERVAL_MS: $([FFUConstants]::PROCESS_POLL_INTERVAL_MS) ms"

# Test retry configuration
Write-Host "`n7. Retry Configuration:" -ForegroundColor Cyan
Write-Host "   MAX_DISM_SERVICE_RETRIES: $([FFUConstants]::MAX_DISM_SERVICE_RETRIES)"
Write-Host "   MAX_COPYPE_RETRIES: $([FFUConstants]::MAX_COPYPE_RETRIES)"
Write-Host "   MAX_PACKAGE_RETRIES: $([FFUConstants]::MAX_PACKAGE_RETRIES)"
Write-Host "   RETRY_DELAY: $([FFUConstants]::RETRY_DELAY) seconds"

# Test helper methods
Write-Host "`n8. Helper Methods:" -ForegroundColor Cyan
Write-Host "   GetWorkingDirectory(): $([FFUConstants]::GetWorkingDirectory())"
Write-Host "   GetVMDirectory(): $([FFUConstants]::GetVMDirectory())"
Write-Host "   GetCaptureDirectory(): $([FFUConstants]::GetCaptureDirectory())"

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
