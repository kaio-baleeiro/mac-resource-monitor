import Foundation
import MacResourceMonitorCore
import MacResourceMonitorMCPCore

@main
struct MacResourceMonitorMCP {
    static func main() {
        let reader = MetricsReader()

        // CPU utilization is calculated from two samples. Warm up the reader
        // so the first request from an agent returns a useful value.
        _ = reader.read()
        Thread.sleep(forTimeInterval: 0.15)
        _ = reader.read()

        let handler = MCPRequestHandler(snapshotProvider: { reader.read() })
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let response = handler.handle(line: line) else { continue }
            FileHandle.standardOutput.write(response)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
