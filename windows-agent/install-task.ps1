<#
Registers DeviceIQAgent.ps1 to run at logon under the current user, no
admin/elevation required - matches the Phase 1b requirement in PROJECT.md
that the core telemetry reads need no special permissions.

Run manually (not via the agent):
    powershell.exe -ExecutionPolicy Bypass -File .\install-task.ps1
#>

$ScriptPath = Join-Path $PSScriptRoot "DeviceIQAgent.ps1"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "DeviceIQAgent" -Action $Action -Trigger $Trigger -Settings $Settings `
    -Description "Device Health Copilot background agent" -Force

Write-Host "Installed. It will start at next logon, or run it now with:"
Write-Host "  Start-ScheduledTask -TaskName DeviceIQAgent"
