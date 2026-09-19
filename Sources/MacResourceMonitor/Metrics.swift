import Foundation
import IOKit
import Darwin

struct ProcessUsage: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}

struct ResourceSnapshot: Sendable {
    let cpuUsage: Double?
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let diskUsed: UInt64
    let diskTotal: UInt64
    let gpuUsage: Double?
    let gpuName: String?
    let networkDownloadRate: Double
    let networkUploadRate: Double
    let processes: [ProcessUsage]
    let updatedAt: Date

    var memoryUsage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskUsage: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }
}

final class MetricsReader {
    private var previousCPU: [UInt64]?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?

    func read() -> ResourceSnapshot {
        let cpu = readCPU()
        let memory = readMemory()
        let disk = readDisk()
        let gpu = readGPU()
        let network = readNetwork()
        let processes = readProcesses()

        return ResourceSnapshot(
            cpuUsage: cpu,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            gpuUsage: gpu.usage,
            gpuName: gpu.name,
            networkDownloadRate: network.download,
            networkUploadRate: network.upload,
            processes: processes,
            updatedAt: Date()
        )
    }

    private func readCPU() -> Double? {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var totals = Array(repeating: UInt64(0), count: 4)
        for index in 0..<Int(cpuCount) {
            let offset = index * Int(CPU_STATE_MAX)
            for state in 0..<4 {
                totals[state] += UInt64(cpuInfo[offset + state])
            }
        }

        defer { previousCPU = totals }
        guard let previousCPU else { return nil }

        let deltaTotal = totals.reduce(0, +) - previousCPU.reduce(0, +)
        let deltaIdle = totals[Int(CPU_STATE_IDLE)] - previousCPU[Int(CPU_STATE_IDLE)]
        guard deltaTotal > 0 else { return nil }
        return min(max(1 - Double(deltaIdle) / Double(deltaTotal), 0), 1)
    }

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return (min(usedPages * pageSize, total), total)
    }

    private func readDisk() -> (used: UInt64, total: UInt64) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            )
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
            return (total > available ? total - available : 0, total)
        } catch {
            return (0, 0)
        }
    }

    private func readGPU() -> (usage: Double?, name: String?) {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let currentService = service
            defer { IOObjectRelease(currentService) }
            let statsKey = "PerformanceStatistics" as CFString
            let modelKey = "model" as CFString
            let stats = IORegistryEntryCreateCFProperty(currentService, statsKey, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            let model = IORegistryEntryCreateCFProperty(currentService, modelKey, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String

            if let stats {
                let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
                    ?? (stats["Renderer Utilization %"] as? NSNumber)?.doubleValue
                if let value {
                    return (min(max(value / 100, 0), 1), model)
                }
            }
            service = IOIteratorNext(iterator)
        }
        return (nil, nil)
    }

    private func readNetwork() -> (download: Double, upload: Double) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = addresses
        while let interface = current {
            let flags = interface.pointee.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            if isUp && !isLoopback,
               let data = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received += UInt64(data.pointee.ifi_ibytes)
                sent += UInt64(data.pointee.ifi_obytes)
            }
            current = interface.pointee.ifa_next
        }

        let now = Date()
        defer { previousNetwork = (received, sent, now) }
        guard let previousNetwork else { return (0, 0) }
        let elapsed = max(now.timeIntervalSince(previousNetwork.date), 0.1)
        let download = Double(received >= previousNetwork.received ? received - previousNetwork.received : 0) / elapsed
        let upload = Double(sent >= previousNetwork.sent ? sent - previousNetwork.sent : 0) / elapsed
        return (download, upload)
    }

    private func readProcesses() -> [ProcessUsage] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,pmem=,rss=,comm="]
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 5,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let memory = Double(fields[2]),
                  let residentKB = UInt64(fields[3]) else { return nil }

            let command = String(fields[4])
            let name = command.split(separator: "/").last.map(String.init) ?? command
            return ProcessUsage(
                pid: pid,
                name: name,
                cpuUsage: max(cpu, 0),
                memoryUsage: max(memory / 100, 0),
                memoryBytes: residentKB * 1024
            )
        }
    }
}
