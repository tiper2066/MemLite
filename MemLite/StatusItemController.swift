import AppKit
import ServiceManagement

enum MenuBarTitle {
    static func make(
        text: String,
        pressure: MemoryPressureLevel,
        highlighted: Bool,
        font: NSFont
    ) -> NSAttributedString {
        let split = text.splitUsedAndRemainder()
        let usedColor = highlighted ? NSColor.labelColor : pressure.menuBarColor
        let result = NSMutableAttributedString(
            string: split.used,
            attributes: attributes(font: font, color: usedColor)
        )
        result.append(NSAttributedString(
            string: split.remainder,
            attributes: attributes(font: font, color: .labelColor)
        ))
        return result
    }

    private static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
        ]
    }
}

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let detailItems: [NSMenuItem]
    private let junkDetailItems: [NSMenuItem]
    private let openAtLoginItem: NSMenuItem
    private let versionItem: NSMenuItem
    private var snapshot: MemorySnapshot?
    private var rendered: RenderState?
    private var lastJunkScan: JunkScanResult?
    private var menuIsOpen = false
    private var isCleaningJunk = false
    private var isScanningJunk = false
    private var junkScanGeneration = 0

    var isMenuOpen: Bool {
        menuIsOpen
    }

    override init() {
        detailItems = (0..<7).map { _ in
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        junkDetailItems = (0..<4).map { _ in
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        openAtLoginItem = NSMenuItem(
            title: "로그인 시 열기",
            action: #selector(toggleOpenAtLogin),
            keyEquivalent: ""
        )
        versionItem = NSMenuItem(title: Self.versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        super.init()
        openAtLoginItem.target = self
        statusItem.button?.image = nil
        statusItem.menu = makeMenu()
        refreshOpenAtLoginState()
        applyJunkLines(JunkCleaner.calculatingMenuLines)
    }

    @discardableResult
    func update(snapshot: MemorySnapshot, menuHighlighted: Bool) -> Bool {
        self.snapshot = snapshot
        let state = RenderState(
            text: snapshot.menuBarText,
            pressure: snapshot.pressure,
            highlighted: menuHighlighted || menuIsOpen,
            details: snapshot.detailLines
        )
        guard rendered != state else {
            return false
        }
        rendered = state
        applyMenuBarTitle(state)
        applyDetailLines(state.details)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refreshOpenAtLoginState()
        refreshJunkDetails()
        let latest = (try? MemoryReader.read()) ?? snapshot
        guard let latest else { return }
        update(snapshot: latest, menuHighlighted: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        guard let snapshot else { return }
        update(snapshot: snapshot, menuHighlighted: false)
    }

    @objc private func cleanJunkFiles() {
        guard !isCleaningJunk else { return }
        isCleaningJunk = true
        if let lastJunkScan, !isScanningJunk {
            confirmJunkDeletion(lastJunkScan)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scan = JunkCleaner.scan()
            DispatchQueue.main.async {
                self?.lastJunkScan = scan
                self?.isScanningJunk = false
                self?.applyJunkLines(JunkCleaner.menuLines(for: scan))
                self?.confirmJunkDeletion(scan)
            }
        }
    }

    private func confirmJunkDeletion(_ scan: JunkScanResult) {
        let alert = NSAlert()
        alert.messageText = "정크 파일 정리"
        alert.informativeText = JunkCleaner.confirmationText(for: scan)
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "지우기")
        guard alert.runModal() == .alertSecondButtonReturn else {
            isCleaningJunk = false
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let deletedBytes = JunkCleaner.delete(scan)
            DispatchQueue.main.async {
                self?.showDeletedJunk(bytes: deletedBytes)
            }
        }
    }

    private func showDeletedJunk(bytes: UInt64) {
        let alert = NSAlert()
        alert.messageText = "정크 파일 정리"
        alert.informativeText = JunkCleaner.deletedText(bytes: bytes)
        alert.addButton(withTitle: "확인")
        alert.runModal()
        lastJunkScan = nil
        applyJunkLines(JunkCleaner.calculatingMenuLines)
        isCleaningJunk = false
    }

    @objc private func toggleOpenAtLogin() {
        let shouldEnable = SMAppService.mainApp.status != .enabled
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 시 열기"
            alert.informativeText = "로그인 항목을 바꾸지 못했습니다. 응용 프로그램 폴더에 설치한 뒤 다시 시도해 주세요."
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
        refreshOpenAtLoginState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        detailItems.forEach(menu.addItem)
        menu.addItem(.separator())
        junkDetailItems.forEach(menu.addItem)
        menu.addItem(.separator())

        let junkItem = NSMenuItem(
            title: "정크 파일 정리…",
            action: #selector(cleanJunkFiles),
            keyEquivalent: ""
        )
        junkItem.target = self
        menu.addItem(junkItem)
        menu.addItem(openAtLoginItem)
        menu.addItem(.separator())

        menu.addItem(versionItem)
        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func refreshOpenAtLoginState() {
        openAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private static var versionTitle: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MemLite"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "\(name) \(version)"
    }

    private func applyMenuBarTitle(_ state: RenderState) {
        let font = statusItem.button?.font ?? NSFont.menuBarFont(ofSize: 0)
        statusItem.button?.attributedTitle = MenuBarTitle.make(
            text: state.text,
            pressure: state.pressure,
            highlighted: state.highlighted,
            font: font
        )
    }

    private func refreshJunkDetails() {
        if let lastJunkScan {
            applyJunkLines(JunkCleaner.menuLines(for: lastJunkScan))
        } else {
            applyJunkLines(JunkCleaner.calculatingMenuLines)
        }
        guard !isScanningJunk, !isCleaningJunk else { return }
        isScanningJunk = true
        junkScanGeneration += 1
        let generation = junkScanGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scan = JunkCleaner.scan()
            DispatchQueue.main.async {
                guard let self, generation == self.junkScanGeneration else { return }
                self.lastJunkScan = scan
                self.isScanningJunk = false
                self.applyJunkLines(JunkCleaner.menuLines(for: scan))
            }
        }
    }

    private func applyDetailLines(_ lines: [MemoryDetailLine]) {
        applyLines(lines, to: detailItems)
    }

    private func applyJunkLines(_ lines: [MemoryDetailLine]) {
        applyLines(lines, to: junkDetailItems)
    }

    private func applyLines(_ lines: [MemoryDetailLine], to items: [NSMenuItem]) {
        for (item, line) in zip(items, lines) {
            item.title = "\(line.name)  \(line.value)"
            item.image = nil
        }
    }

    private struct RenderState: Equatable {
        let text: String
        let pressure: MemoryPressureLevel
        let highlighted: Bool
        let details: [MemoryDetailLine]
    }

    #if DEBUG
    var debugMenu: NSMenu {
        statusItem.menu ?? NSMenu()
    }

    var debugTitle: NSAttributedString {
        statusItem.button?.attributedTitle ?? NSAttributedString()
    }

    var debugButtonImage: NSImage? {
        statusItem.button?.image
    }
    #endif
}

private extension MemoryPressureLevel {
    var menuBarColor: NSColor {
        switch self {
        case .normal:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .urgent, .critical:
            return .systemRed
        }
    }
}

private extension String {
    func splitUsedAndRemainder() -> (used: String, remainder: String) {
        guard let separator = range(of: " / ") else {
            return (self, "")
        }
        return (String(self[..<separator.lowerBound]), String(self[separator.lowerBound...]))
    }
}
