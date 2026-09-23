import Foundation
import IOKit
import Darwin

public enum MetricStatus: String, Sendable, Equatable {
    case available
    case warmingUp
    case unavailable
    case failed
}

public struct ProcessUsage: Identifiable, Sendable {
    public let pid: Int32
    public let name: String
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let memoryBytes: UInt64

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        name: String,
        cpuUsage: Double,
        memoryUsage: Double,
        memoryBytes: UInt64
    ) {
        self.pid = pid
        self.name = name
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.memoryBytes = memoryBytes
    }
}

public struct ResourceSnapshot: Sendable {
    public let cpuUsage: Double?
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64
    public let diskUsed: UInt64
    public let diskTotal: UInt64
    public let gpuUsage: Double?
    public let gpuName: String?
    public let networkDownloadRate: Double
    public let networkUploadRate: Double
    public let processes: [ProcessUsage]
    public let updatedAt: Date
    public let cpuStatus: MetricStatus
    public let memoryStatus: MetricStatus
    public let diskStatus: MetricStatus
    public let gpuStatus: MetricStatus
    public let networkStatus: MetricStatus
    public let processStatus: MetricStatus
    public let collectionDuration: TimeInterval

    public init(
        cpuUsage: Double?,
        memoryUsed: UInt64,
        memoryTotal: UInt64,
        diskUsed: UInt64,
        diskTotal: UInt64,
        gpuUsage: Double?,
        gpuName: String?,
        networkDownloadRate: Double,
        networkUploadRate: Double,
        processes: [ProcessUsage],
        updatedAt: Date = Date(),
        cpuStatus: MetricStatus = .available,
        memoryStatus: MetricStatus = .available,
        diskStatus: MetricStatus = .available,
        gpuStatus: MetricStatus = .available,
        networkStatus: MetricStatus = .available,
        processStatus: MetricStatus = .available,
        collectionDuration: TimeInterval = 0
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.gpuUsage = gpuUsage
        self.gpuName = gpuName
        self.networkDownloadRate = networkDownloadRate
        self.networkUploadRate = networkUploadRate
        self.processes = processes
        self.updatedAt = updatedAt
        self.cpuStatus = cpuStatus
        self.memoryStatus = memoryStatus
        self.diskStatus = diskStatus
        self.gpuStatus = gpuStatus
        self.networkStatus = networkStatus
        self.processStatus = processStatus
        self.collectionDuration = collectionDuration
    }

    public var memoryUsage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    public var diskUsage: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }
}

public final class MetricsReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.macresourcemonitor.metrics", qos: .utility)
    private var previousCPU: [UInt64]?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?

    public init() {}

    public func read() -> ResourceSnapshot {
        queue.sync { readLocked() }
    }

    public func readAsync() async -> ResourceSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readLocked())
            }
        }
    }

    public func resetBaselines() {
        queue.sync {
            previousCPU = nil
            previousNetwork = nil
        }
    }

    private func readLocked() -> ResourceSnapshot {
        let startedAt = Date()
        let cpu = readCPU()
        let memory = readMemory()
        let disk = readDisk()
        let gpu = readGPU()
        let network = readNetwork()
        let processes = readProcesses()

        return ResourceSnapshot(
            cpuUsage: cpu.value,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            gpuUsage: gpu.usage,
            gpuName: gpu.name,
            networkDownloadRate: network.download,
            networkUploadRate: network.upload,
            processes: processes.value,
            updatedAt: Date(),
            cpuStatus: cpu.status,
            memoryStatus: memory.status,
            diskStatus: disk.status,
            gpuStatus: gpu.status,
            networkStatus: network.status,
            processStatus: processes.status,
            collectionDuration: Date().timeIntervalSince(startedAt)
        )
    }

    private func readCPU() -> (value: Double?, status: MetricStatus) {
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

        guard result == KERN_SUCCESS, let cpuInfo else { return (nil, .failed) }
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
        guard let previousCPU else { return (nil, .warmingUp) }

        let deltaTotal = totals.reduce(0, +) - previousCPU.reduce(0, +)
        let deltaIdle = totals[Int(CPU_STATE_IDLE)] - previousCPU[Int(CPU_STATE_IDLE)]
        guard deltaTotal > 0 else { return (nil, .failed) }
        return (min(max(1 - Double(deltaIdle) / Double(deltaTotal), 0), 1), .available)
    }

    private func readMemory() -> (used: UInt64, total: UInt64, status: MetricStatus) {
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
        guard result == KERN_SUCCESS, total > 0 else { return (0, total, .failed) }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return (min(usedPages * pageSize, total), total, .available)
    }

    private func readDisk() -> (used: UInt64, total: UInt64, status: MetricStatus) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            )
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
            guard total > 0 else { return (0, 0, .unavailable) }
            return (total > available ? total - available : 0, total, .available)
        } catch {
            return (0, 0, .failed)
        }
    }

    private func readGPU() -> (usage: Double?, name: String?, status: MetricStatus) {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (nil, nil, .unavailable)
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
                    return (min(max(value / 100, 0), 1), model, .available)
                }
            }
            service = IOIteratorNext(iterator)
        }
        return (nil, nil, .unavailable)
    }

    private func readNetwork() -> (download: Double, upload: Double, status: MetricStatus) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let addresses else { return (0, 0, .failed) }
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
        guard let previousNetwork else { return (0, 0, .warmingUp) }
        let elapsed = max(now.timeIntervalSince(previousNetwork.date), 0.1)
        let download = Double(received >= previousNetwork.received ? received - previousNetwork.received : 0) / elapsed
        let upload = Double(sent >= previousNetwork.sent ? sent - previousNetwork.sent : 0) / elapsed
        return (download, upload, .available)
    }

    private func readProcesses() -> (value: [ProcessUsage], status: MetricStatus) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,pmem=,rss=,comm="]
        process.standardOutput = output

        do {
            try process.run()
            // Drain stdout before waiting: a busy Mac can produce enough output
            // to fill the pipe and deadlock the producer if we wait first.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return ([], .failed) }

            guard let text = String(data: data, encoding: .utf8) else { return ([], .failed) }

            let processes: [ProcessUsage] = text.split(whereSeparator: \.isNewline).compactMap { line -> ProcessUsage? in
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
            return (processes, .available)
        } catch {
            return ([], .failed)
        }
    }
}
