<#
DeviceIQ - Windows background agent.
Tray-icon app: pairs with your account (text-code pairing, not QR), then
pushes a telemetry snapshot on a timer using the same WMI/powercfg reads
validated in agents-windows-poc/telemetry-probe.ps1.

Run manually for testing:
    powershell.exe -ExecutionPolicy Bypass -File .\DeviceIQAgent.ps1
Install as a background agent: see install-task.ps1.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Config ---------------------------------------------------------------

# Deployed backend (OCI VM, Docker Compose behind nginx/certbot). For local dev against a
# backend on another machine, use that machine's LAN IP, e.g.
# "http://192.168.1.10:4000" - localhost here would mean this Windows machine.
$BackendBaseUrl = "https://deviceiq.duckdns.org"

# Public Firebase Web API Key - not a secret, see backend/.env.example.
$FirebaseWebApiKey = "AIzaSyCCoLdGsaHcJ5ZFaojjVQ2DtpiFtsRT-m8"

$SnapshotIntervalMs = 10 * 60 * 1000   # "every ~5-15 min, tunable"
$PairingPollIntervalMs = 3000

$CredentialsDir = Join-Path $env:LOCALAPPDATA "DeviceIQAgent"
$CredentialsPath = Join-Path $CredentialsDir "credentials.json"
$LogPath = Join-Path $CredentialsDir "agent.log"

# --- Logging ----------------------------------------------------------------
# Runs hidden via Task Scheduler with no console, unlike the macOS agent
# which gets stdout/stderr redirected to a file by launchd for free - so
# failures need an explicit log or they're invisible.

function Write-Log([string]$Message) {
    New-Item -ItemType Directory -Force -Path $CredentialsDir | Out-Null
    "$(Get-Date -Format 'o')  $Message" | Add-Content -Path $LogPath
}

# --- Credential storage -----------------------------------------------------

function Save-Credentials([string]$DeviceId, [string]$RefreshToken) {
    New-Item -ItemType Directory -Force -Path $CredentialsDir | Out-Null
    @{ deviceId = $DeviceId; refreshToken = $RefreshToken } | ConvertTo-Json | Set-Content -Path $CredentialsPath -Encoding utf8
}

function Load-Credentials {
    if (-not (Test-Path $CredentialsPath)) { return $null }
    try { return Get-Content $CredentialsPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Clear-Credentials {
    if (Test-Path $CredentialsPath) { Remove-Item $CredentialsPath -Force }
}

# --- Session state (in-memory idToken cache, refreshed via refreshToken) ---

$Script:DeviceId = $null
$Script:RefreshToken = $null
$Script:IdToken = $null
$Script:IdTokenExpiresAt = [DateTime]::MinValue

$existing = Load-Credentials
if ($existing) {
    $Script:DeviceId = $existing.deviceId
    $Script:RefreshToken = $existing.refreshToken
}

function Get-CurrentIdToken {
    if ($Script:IdToken -and (Get-Date) -lt $Script:IdTokenExpiresAt.AddSeconds(-60)) {
        return $Script:IdToken
    }
    if (-not $Script:RefreshToken) { throw "Not paired yet" }

    $uri = "https://securetoken.googleapis.com/v1/token?key=$FirebaseWebApiKey"
    $body = @{ grant_type = "refresh_token"; refresh_token = $Script:RefreshToken } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json"

    $Script:IdToken = $response.id_token
    $Script:RefreshToken = $response.refresh_token
    $Script:IdTokenExpiresAt = (Get-Date).AddSeconds([int]$response.expires_in)
    Save-Credentials -DeviceId $Script:DeviceId -RefreshToken $Script:RefreshToken
    return $Script:IdToken
}

function Complete-Pairing([string]$DeviceId, [string]$CustomToken) {
    $uri = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=$FirebaseWebApiKey"
    $body = @{ token = $CustomToken; returnSecureToken = $true } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json"

    $Script:DeviceId = $DeviceId
    $Script:IdToken = $response.idToken
    $Script:RefreshToken = $response.refreshToken
    $Script:IdTokenExpiresAt = (Get-Date).AddSeconds([int]$response.expiresIn)
    Save-Credentials -DeviceId $DeviceId -RefreshToken $Script:RefreshToken
}

# --- Backend API ------------------------------------------------------------

function New-PendingPairing {
    Invoke-RestMethod -Uri "$BackendBaseUrl/devices/pending-pairing" -Method Post
}

function Get-PairingStatus([string]$Token) {
    Invoke-RestMethod -Uri "$BackendBaseUrl/devices/pending-pairing/$Token/status" -Method Get
}

function Send-Snapshot([hashtable]$Payload) {
    $idToken = Get-CurrentIdToken
    $headers = @{ Authorization = "Bearer $idToken" }
    $body = $Payload | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$BackendBaseUrl/devices/$($Script:DeviceId)/snapshots" -Method Post -Headers $headers -Body $body -ContentType "application/json"
}

# --- Telemetry (ported from agents-windows-poc/telemetry-probe.ps1) --------

function Try-Value([scriptblock]$Block) {
    # Get-CimInstance reports failures as non-terminating errors, which a
    # try/catch ignores and which print red text to the console. Stop makes
    # them catchable, so a WMI class the OEM doesn't implement just yields $null.
    $ErrorActionPreference = "Stop"
    try { return & $Block } catch { return $null }
}

function Get-Telemetry {
    $result = @{ raw = @{} }

    $battery = Try-Value { Get-CimInstance -ClassName Win32_Battery }
    $bstatus = Try-Value { Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus }
    $os = Try-Value { Get-CimInstance -ClassName Win32_OperatingSystem }
    $disk = Try-Value { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" }

    # Battery level + charging state: prefer the low-level BatteryStatus
    # bool (validated as self-consistent), fall back to Win32_Battery's
    # coarser enum.
    $result.batteryLevelPercent = Try-Value { [int]$battery.EstimatedChargeRemaining }
    if ($null -ne $bstatus -and $null -ne $bstatus.Charging) {
        $result.isCharging = [bool]$bstatus.Charging
    } else {
        $chargingStates = 6, 7, 8, 9
        $result.isCharging = Try-Value { $chargingStates -contains [int]$battery.BatteryStatus }
    }

    $voltageMv = Try-Value { [int]$bstatus.Voltage }
    if (-not $voltageMv) { $voltageMv = Try-Value { [int]$battery.DesignVoltage } }
    $result.voltageMv = $voltageMv

    # Cycle count: root\wmi first (cross-validated exactly against
    # powercfg), fall back to the powercfg XML report.
    $cycleCount = Try-Value { (Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount).CycleCount }

    # Design/full-charge capacity: root\wmi BatteryStaticData is known to
    # fail outright on some OEMs (confirmed in the spike) - always have the
    # powercfg XML fallback ready.
    $designCapacityMwh = Try-Value { (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData).DesignedCapacity }
    $fullChargeCapacityMwh = Try-Value { (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity).FullChargedCapacity }

    if (-not $cycleCount -or -not $designCapacityMwh -or -not $fullChargeCapacityMwh) {
        $xmlPath = Join-Path $env:TEMP "deviceiq-battery-report.xml"
        Try-Value { powercfg /batteryreport /output $xmlPath /xml | Out-Null } | Out-Null
        if (Test-Path $xmlPath) {
            $raw = Get-Content $xmlPath -Raw
            if (-not $cycleCount) {
                $m = [regex]::Match($raw, '<CycleCount>(\d+)</CycleCount>')
                if ($m.Success) { $cycleCount = [int]$m.Groups[1].Value }
            }
            if (-not $designCapacityMwh) {
                $m = [regex]::Match($raw, '<DesignCapacity>(\d+)</DesignCapacity>')
                if ($m.Success) { $designCapacityMwh = [int]$m.Groups[1].Value }
            }
            if (-not $fullChargeCapacityMwh) {
                $m = [regex]::Match($raw, '<FullChargeCapacity>(\d+)</FullChargeCapacity>')
                if ($m.Success) { $fullChargeCapacityMwh = [int]$m.Groups[1].Value }
            }
        }
    }
    $result.cycleCount = $cycleCount

    # Schema column is named *Mah, but powercfg/WMI report these natively in
    # mWh (cross-validated: 35701 mWh, 51310 mWh), so convert to mAh
    # (mAh = mWh * 1000 / V) so both platforms use one unit. Use the
    # battery's nominal DesignVoltage: the live voltage swings with charge
    # level and would make the absolute mAh drift between snapshots. Fall back
    # to live voltage only if DesignVoltage isn't reported.
    $designVoltageMv = Try-Value { [int]$battery.DesignVoltage }
    $conversionVoltageMv = if ($designVoltageMv -and $designVoltageMv -gt 0) { $designVoltageMv } else { $voltageMv }
    if ($conversionVoltageMv -and $conversionVoltageMv -gt 0) {
        if ($designCapacityMwh) { $result.designCapacityMah = [int](($designCapacityMwh * 1000.0) / $conversionVoltageMv) }
        if ($fullChargeCapacityMwh) { $result.fullChargeCapacityMah = [int](($fullChargeCapacityMwh * 1000.0) / $conversionVoltageMv) }
        $result.raw.conversionVoltageMv = $conversionVoltageMv
    }
    $result.raw.designCapacityMwh = $designCapacityMwh
    $result.raw.fullChargeCapacityMwh = $fullChargeCapacityMwh

    # Storage - already bytes.
    $result.storageTotalBytes = Try-Value { [int64]$disk.Size }
    $result.storageFreeBytes = Try-Value { [int64]$disk.FreeSpace }

    # RAM - Win32_OperatingSystem reports KB, not bytes.
    $result.ramTotalBytes = Try-Value { [int64]$os.TotalVisibleMemorySize * 1024 }
    $result.ramFreeBytes = Try-Value { [int64]$os.FreePhysicalMemory * 1024 }

    # Thermal deliberately omitted - MSAcpi_ThermalZoneTemperature requires
    # admin and fails for a standard user (confirmed in the spike). No point
    # prompting for elevation just for this one field.
    $result.thermalStatus = $null

    return $result
}

# --- Pairing window (text code + copy button, not QR) ----------------------

function Show-PairingWindow {
    $pending = New-PendingPairing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Link This Laptop"
    $form.Width = 340
    $form.Height = 220
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Scan the QR (or enter this code) in the DeviceIQ app:"
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $form.Controls.Add($label)

    $codeBox = New-Object System.Windows.Forms.TextBox
    $codeBox.Text = $pending.token
    $codeBox.ReadOnly = $true
    $codeBox.Width = 280
    $codeBox.Location = New-Object System.Drawing.Point(20, 50)
    $form.Controls.Add($codeBox)

    $copyButton = New-Object System.Windows.Forms.Button
    $copyButton.Text = "Copy to Clipboard"
    $copyButton.Width = 130
    $copyButton.Location = New-Object System.Drawing.Point(20, 85)
    $copyButton.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($pending.token) })
    $form.Controls.Add($copyButton)

    # The pairing page draws the QR in the browser. The token sits after the
    # # so it is never sent to the server; see backend/src/public/pair.html.
    $qrButton = New-Object System.Windows.Forms.Button
    $qrButton.Text = "Show QR code"
    $qrButton.Width = 130
    $qrButton.Location = New-Object System.Drawing.Point(160, 85)
    $qrButton.Add_Click({ Start-Process "$BackendBaseUrl/pair#$($pending.token)" })
    $form.Controls.Add($qrButton)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Waiting for phone to enter this code…"
    $statusLabel.AutoSize = $true
    $statusLabel.Location = New-Object System.Drawing.Point(20, 125)
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($statusLabel)

    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = $PairingPollIntervalMs
    $pollTimer.Add_Tick({
        try {
            $status = Get-PairingStatus -Token $pending.token
            if ($status.claimed) {
                $pollTimer.Stop()
                if ($status.deviceId -and $status.deviceToken) {
                    $statusLabel.Text = "Paired! Finishing setup…"
                    Complete-Pairing -DeviceId $status.deviceId -CustomToken $status.deviceToken
                    $statusLabel.Text = "Done."
                    Update-TrayStatus "Status: not synced yet"
                    $form.Close()
                } else {
                    $statusLabel.Text = "Already claimed - close and reopen to retry."
                }
            }
        } catch {
            $statusLabel.Text = "Error: $($_.Exception.Message)"
            Write-Log "Pairing error: $($_.Exception.Message)"
        }
    })
    $pollTimer.Start()
    $form.Add_FormClosed({ $pollTimer.Stop(); $pollTimer.Dispose() })

    $form.ShowDialog() | Out-Null
}

# --- Tray icon ---------------------------------------------------------------

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$notifyIcon.Text = "DeviceIQAgent"
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = $contextMenu.Items.Add($(if ($Script:DeviceId) { "Status: not synced yet" } else { "Status: not paired" }))
$statusItem.Enabled = $false
$contextMenu.Items.Add("-") | Out-Null
$pairItem = $contextMenu.Items.Add($(if ($Script:DeviceId) { "Re-link This Device..." } else { "Link This Device..." }))
$syncItem = $contextMenu.Items.Add("Sync Now")
$syncItem.Enabled = [bool]$Script:DeviceId
$contextMenu.Items.Add("-") | Out-Null
$exitItem = $contextMenu.Items.Add("Exit")

function Update-TrayStatus([string]$Text) {
    $statusItem.Text = $Text
}

function Invoke-Sync {
    if (-not $Script:DeviceId) {
        Update-TrayStatus "Status: not paired"
        return
    }
    try {
        Send-Snapshot -Payload (Get-Telemetry) | Out-Null
        Update-TrayStatus "Status: synced at $(Get-Date -Format 't')"
    } catch {
        $err = $_
        $status = Try-Value { [int]$err.Exception.Response.StatusCode }
        $detail = "$($err.ErrorDetails.Message) $($err.Exception.Message)"
        # 403/404 from our backend: device unlinked. A 400 from Firebase's
        # token refresh naming a missing/disabled user or dead refresh token:
        # the account was deleted.
        $unlinked = $status -eq 403 -or $status -eq 404 -or
            ($status -eq 400 -and $detail -match 'USER_NOT_FOUND|USER_DISABLED|TOKEN_EXPIRED|INVALID_REFRESH_TOKEN')
        if ($unlinked) {
            # Drop the saved credentials and offer re-pairing instead of
            # failing every sync from now on.
            Clear-Credentials
            $Script:DeviceId = $null
            $Script:RefreshToken = $null
            $Script:IdToken = $null
            $pairItem.Text = "Link This Device..."
            $syncItem.Enabled = $false
            Update-TrayStatus "Status: unlinked - link this device again"
            Write-Log "Device unlinked by the backend ($status); credentials cleared"
        } else {
            Update-TrayStatus "Sync error: $($err.Exception.Message)"
            Write-Log "Sync error: $($err.Exception.Message)"
        }
    }
}

$pairItem.Add_Click({
    Show-PairingWindow
    $pairItem.Text = $(if ($Script:DeviceId) { "Re-link This Device..." } else { "Link This Device..." })
    $syncItem.Enabled = [bool]$Script:DeviceId
    if ($Script:DeviceId) { Invoke-Sync }
})
$syncItem.Add_Click({ Invoke-Sync })
$exitItem.Add_Click({
    $notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$notifyIcon.ContextMenuStrip = $contextMenu

$syncTimer = New-Object System.Windows.Forms.Timer
$syncTimer.Interval = $SnapshotIntervalMs
$syncTimer.Add_Tick({ Invoke-Sync })
$syncTimer.Start()

# The interval timer's first tick is a full interval away, so a restarted agent
# would sit on "not synced yet" for 10 minutes. Sync once shortly after launch
# (delayed so the message loop is running and the tray icon is already up).
if ($Script:DeviceId) {
    $startupTimer = New-Object System.Windows.Forms.Timer
    $startupTimer.Interval = 2000
    $startupTimer.Add_Tick({
        $startupTimer.Stop()
        $startupTimer.Dispose()
        Invoke-Sync
    })
    $startupTimer.Start()
}

# Ctrl+C would stop this script's pipeline while the tray icon's message loop
# keeps running, after which every menu click throws PipelineStoppedException.
# Read it as plain input instead and quit from the tray menu's Exit. (Throws
# when there is no console, e.g. when started hidden - nothing to guard then.)
try { [Console]::TreatControlCAsInput = $true } catch { }

try {
    [System.Windows.Forms.Application]::Run()
} finally {
    # Never leave an unclickable ghost icon behind.
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
}
