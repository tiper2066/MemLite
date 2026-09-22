import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshMemory()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshMemory()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func refreshMemory() {
        guard let snapshot = try? MemoryReader.read() else {
            return
        }
        statusItemController.update(
            snapshot: snapshot,
            menuHighlighted: statusItemController.isMenuOpen
        )
    }

    #if DEBUG
    var debugStatusController: StatusItemController {
        statusItemController
    }
    #endif
}
