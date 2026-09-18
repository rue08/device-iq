<#
Device Health Copilot - Windows telemetry spike.
Read-only. No admin rights required for any of these calls (each is wrapped
so one unsupported/blocked class doesn't kill the rest of the script).
Mirrors the Android/macOS probes already validated for this project:
battery condition + cycle/capacity signals, storage, RAM, thermal.
#>

$ErrorActionPreference = "Continue"
$result = [ordered]@{}

function Try-Get {
    param([string]$Label, [scriptblock]$Block)
    try {
        $value = & $Block
        if ($null -eq $value) { return "NULL" }
        return $value
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

# --- Device identity ---
$cs = Try-Get "cs" { Get-CimInstance -ClassName Win32_ComputerSystem }
$os = Try-Get "os" { Get-CimInstance -ClassName Win32_OperatingSystem }
$result["manufacturer"] = Try-Get "manufacturer" { $cs.Manufacturer }
$result["model"] = Try-Get "model" { $cs.Model }
$result["os_caption"] = Try-Get "os_caption" { $os.Caption }
$result["os_version"] = Try-Get "os_version" { $os.Version }
$result["timestamp"] = (Get-Date).ToString("o")

# --- Battery: standard Win32_Battery (broad compatibility, coarse data) ---
$battery = Try-Get "battery" { Get-CimInstance -ClassName Win32_Battery }
$result["win32_battery_status"] = Try-Get "status" { $battery.BatteryStatus }
$result["win32_estimated_charge_remaining_percent"] = Try-Get "charge" { $battery.EstimatedChargeRemaining }
$result["win32_design_voltage_mV"] = Try-Get "voltage" { $battery.DesignVoltage }
$result["win32_estimated_runtime_min"] = Try-Get "runtime" { $battery.EstimatedRunTime }

# --- Battery: root\wmi low-level battery classes (real cycle count / capacity, if supported) ---
$result["wmi_BatteryCycleCount"] = Try-Get "cyclecount" {
    (Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount).CycleCount
}
$result["wmi_BatteryStaticData_DesignedCapacity_mWh"] = Try-Get "design" {
    (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData).DesignedCapacity
}
$result["wmi_BatteryFullChargedCapacity_mWh"] = Try-Get "fullcharge" {
    (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity).FullChargedCapacity
}
$bstatus = Try-Get "bstatus" { Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus }
$result["wmi_BatteryStatus_RemainingCapacity_mWh"] = Try-Get "remcap" { $bstatus.RemainingCapacity }
$result["wmi_BatteryStatus_Voltage_mV"] = Try-Get "volt" { $bstatus.Voltage }
$result["wmi_BatteryStatus_ChargeRate_mW"] = Try-Get "chgrate" { $bstatus.ChargeRate }
$result["wmi_BatteryStatus_DischargeRate_mW"] = Try-Get "dischgrate" { $bstatus.DischargeRate }
$result["wmi_BatteryStatus_Charging"] = Try-Get "charging" { $bstatus.Charging }
$result["wmi_BatteryStatus_Discharging"] = Try-Get "discharging" { $bstatus.Discharging }

# --- Battery: official powercfg battery report (human-readable, ground truth to cross-check against) ---
$reportDir = $PSScriptRoot
$htmlPath = Join-Path $reportDir "battery-report.html"
$xmlPath = Join-Path $reportDir "battery-report.xml"
$result["powercfg_html_report"] = Try-Get "pchtml" {
    powercfg /batteryreport /output $htmlPath | Out-Null
    if (Test-Path $htmlPath) { "generated: $htmlPath" } else { "FAILED - file not created" }
}
$result["powercfg_xml_report"] = Try-Get "pcxml" {
    powercfg /batteryreport /output $xmlPath /xml | Out-Null
    if (Test-Path $xmlPath) { "generated: $xmlPath" } else { "FAILED - file not created" }
}
# Best-effort grep of the XML for headline figures, without depending on exact schema
$result["powercfg_xml_grep"] = Try-Get "pcgrep" {
    if (Test-Path $xmlPath) {
        $raw = Get-Content $xmlPath -Raw
        $hits = [regex]::Matches($raw, '<(CycleCount|DesignCapacity|FullChargeCapacity)>(.*?)</\1>')
        ($hits | ForEach-Object { "$($_.Groups[1].Value)=$($_.Groups[2].Value)" }) -join "; "
    } else { "N/A - xml report missing" }
}

# --- Thermal (unreliable across OEMs - expect this to fail on many machines, that's a real finding) ---
$result["thermal_zone_temp_tenthsKelvin"] = Try-Get "thermal" {
    (Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature).CurrentTemperature
}

# --- Storage ---
$disk = Try-Get "disk" { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" }
$result["storage_total_bytes"] = Try-Get "tot" { $disk.Size }
$result["storage_free_bytes"] = Try-Get "free" { $disk.FreeSpace }

# --- RAM ---
$result["ram_total_KB"] = Try-Get "ramtot" { $os.TotalVisibleMemorySize }
$result["ram_free_KB"] = Try-Get "ramfree" { $os.FreePhysicalMemory }

# --- Output ---
$outPath = Join-Path $PSScriptRoot "telemetry-windows.json"
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outPath -Encoding utf8

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
$result | Format-List
Write-Host ""
Write-Host "Saved to: $outPath" -ForegroundColor Green
Write-Host "Also check battery-report.html in this folder (open in a browser) for a human-readable cross-check." -ForegroundColor Green
