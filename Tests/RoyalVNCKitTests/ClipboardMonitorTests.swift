import XCTest
@testable import RoyalVNCKit

#if os(macOS) || os(iOS)
final class ClipboardMonitorTests: XCTestCase {
    func testDeferredStartActivatesMonitoring() async {
        await checkLifecycle(stopBeforeStart: false)
    }

    func testStopCancelsDeferredStart() async {
        await checkLifecycle(stopBeforeStart: true)
    }

    private func checkLifecycle(stopBeforeStart: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                let monitor = VNCClipboardMonitor(clipboard: VNCClipboard(),
                    monitoringInterval: 60, tolerance: 0)
                monitor.startMonitoring()
                if stopBeforeStart { monitor.stopMonitoring() }
                DispatchQueue.main.async {
                    XCTAssertEqual(monitor.isMonitoring, !stopBeforeStart)
                    monitor.stopMonitoring()
                    XCTAssertFalse(monitor.isMonitoring)
                    continuation.resume()
                }
            }
        }
    }
}
#endif
