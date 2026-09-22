import Foundation
import IOKit
import IOKit.ps

// Ports the validated macOS spike into real reads instead of shelling out
// to ioreg/pmset/df/vm_stat - a real app should use ProcessInfo.thermalState
// etc. instead of scraping CLI text, since that output format isn't a
// stable contract across OS versions.
enum Telemetry {
    struct Snapshot {
        var batteryLevelPercent: Int?
        var isCharging: Bool?
        var voltageMv: Int?
        var cycleCount: Int?
        var designCapacityMah: Int?
        var fullChargeCapacityMah: Int?
        var storageTotalBytes: Int64?
        var storageFreeBytes: Int64?
        var ramTotalBytes: Int64?
        var ramFreeBytes: Int64?
        var thermalStatus: String?
        var raw: [String: Any]

        var jsonPayload: [String: Any] {
            var payload: [String: Any] = ["raw": raw]
            if let batteryLevelPercent { payload["batteryLevelPercent"] = batteryLevelPercent }
            if let isCharging { payload["isCharging"] = isCharging }
            if let voltageMv { payload["voltageMv"] = voltageMv }
            if let cycleCount { payload["cycleCount"] = cycleCount }
            if let designCapacityMah { payload["designCapacityMah"] = designCapacityMah }
            if let fullChargeCapacityMah { payload["fullChargeCapacityMah"] = fullChargeCapacityMah }
            if let storageTotalBytes { payload["storageTotalBytes"] = storageTotalBytes }
            if let storageFreeBytes { payload["storageFreeBytes"] = storageFreeBytes }
            if let ramTotalBytes { payload["ramTotalBytes"] = ramTotalBytes }
            if let ramFreeBytes { payload["ramFreeBytes"] = ramFreeBytes }
            if let thermalStatus { payload["thermalStatus"] = thermalStatus }
            return payload
        }
    }

    static func collect() -> Snapshot {
        var snapshot = Snapshot(raw: [:])
        readBattery(into: &snapshot)
        readThermal(into: &snapshot)
        readStorage(into: &snapshot)
        readMemory(into: &snapshot)
        return snapshot
    }

    // MARK: - Battery (IOKit AppleSmartBattery)

    private static func readBattery(into snapshot: inout Snapshot) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var propsUnmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsUnmanaged?.takeRetainedValue() as? [String: Any]
        else { return }

        // On Apple Silicon, the design/full-charge capacity fields live
        // nested under "BatteryData" (confirmed empirically via `ioreg` on
        // the dev Mac); older Intel Macs exposed them top-level. Check
        // both, preferring top-level if present.
        let batteryData = props["BatteryData"] as? [String: Any] ?? [:]

        snapshot.batteryLevelPercent = props["CurrentCapacity"] as? Int
        snapshot.isCharging = props["IsCharging"] as? Bool
        snapshot.voltageMv = props["Voltage"] as? Int
        snapshot.cycleCount = props["CycleCount"] as? Int

        // IOKit reports these natively in mAh - stored as-is, no unit
        // conversion (see schema.prisma - Windows' powercfg/WMI equivalents
        // are natively in mWh instead, a known cross-platform unit mismatch
        // in this column, not converted either).
        snapshot.designCapacityMah = (props["DesignCapacity"] as? Int) ?? (batteryData["DesignCapacity"] as? Int)
        snapshot.fullChargeCapacityMah = (props["NominalChargeCapacity"] as? Int)
            ?? (props["FullChargeCapacity"] as? Int)
            ?? (batteryData["NominalChargeCapacity"] as? Int)
            ?? (batteryData["FullChargeCapacity"] as? Int)

        snapshot.raw["fullyCharged"] = props["FullyCharged"] as? Bool
        snapshot.raw["externalConnected"] = props["ExternalConnected"] as? Bool
    }

    // MARK: - Thermal

    private static func readThermal(into snapshot: inout Snapshot) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: snapshot.thermalStatus = "NOMINAL"
        case .fair: snapshot.thermalStatus = "FAIR"
        case .serious: snapshot.thermalStatus = "SERIOUS"
        case .critical: snapshot.thermalStatus = "CRITICAL"
        @unknown default: snapshot.thermalStatus = "UNKNOWN"
        }
    }

    // MARK: - Storage

    private static func readStorage(into snapshot: inout Snapshot) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return }

        if let total = values.volumeTotalCapacity {
            snapshot.storageTotalBytes = Int64(total)
        }
        if let available = values.volumeAvailableCapacityForImportantUsage {
            snapshot.storageFreeBytes = available
        }
    }

    // MARK: - Memory

    private static func readMemory(into snapshot: inout Snapshot) {
        snapshot.ramTotalBytes = Int64(ProcessInfo.processInfo.physicalMemory)

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        // Matches `vm_stat`'s "Pages free" figure, the same call validated
        // in the original spike.
        snapshot.ramFreeBytes = Int64(stats.free_count) * Int64(pageSize)
    }
}
