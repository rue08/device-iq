package com.deviceiq.device_iq

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Ports the validated native probe logic into a MethodChannel the Flutter
// side can call. Two documented gotchas baked in here rather than left to
// the caller:
//  - battery level/voltage/temperature/health come from the sticky
//    ACTION_BATTERY_CHANGED broadcast, not BatteryManager.isCharging(),
//    which the spike found reports false while visibly charging.
//  - cycle count has no real, non-stubbed source on Android - deliberately
//    not read here.
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.deviceiq.device_iq/telemetry"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "collect") {
                result.success(collectTelemetry())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun collectTelemetry(): Map<String, Any?> {
        val batteryStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING

        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val levelFromManager = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val level = if (levelFromManager in 0..100) {
            levelFromManager
        } else {
            val rawLevel = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (rawLevel >= 0 && scale > 0) (rawLevel * 100 / scale) else null
        }

        val voltageMv = batteryStatus?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it >= 0 }
        val temperatureTenthsC = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)?.takeIf { it >= 0 }
        val healthEnum = batteryStatus?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)?.takeIf { it >= 0 }

        val thermalStatus: String? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                thermalStatusName(powerManager.currentThermalStatus)
            } else {
                null
            }

        val dataStat = StatFs(applicationContext.dataDir.path)
        val storageTotalBytes = dataStat.totalBytes
        val storageFreeBytes = dataStat.availableBytes

        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        return mapOf(
            "batteryLevelPercent" to level,
            "isCharging" to isCharging,
            "voltageMv" to voltageMv,
            "healthEnum" to healthEnum,
            "temperatureTenthsC" to temperatureTenthsC,
            "storageTotalBytes" to storageTotalBytes,
            "storageFreeBytes" to storageFreeBytes,
            "ramTotalBytes" to memInfo.totalMem,
            "ramFreeBytes" to memInfo.availMem,
            "thermalStatus" to thermalStatus,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "raw" to mapOf(
                "statusEnum" to status,
                "batteryPropertyCapacity" to levelFromManager,
            ),
        )
    }

    private fun thermalStatusName(status: Int): String = when (status) {
        PowerManager.THERMAL_STATUS_NONE -> "NONE"
        PowerManager.THERMAL_STATUS_LIGHT -> "LIGHT"
        PowerManager.THERMAL_STATUS_MODERATE -> "MODERATE"
        PowerManager.THERMAL_STATUS_SEVERE -> "SEVERE"
        PowerManager.THERMAL_STATUS_CRITICAL -> "CRITICAL"
        PowerManager.THERMAL_STATUS_EMERGENCY -> "EMERGENCY"
        PowerManager.THERMAL_STATUS_SHUTDOWN -> "SHUTDOWN"
        else -> "UNKNOWN"
    }
}
