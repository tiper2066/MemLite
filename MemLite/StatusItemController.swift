import AppKit

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
    private var snapshot: MemorySnapshot?
    private var rendered: RenderState?
    private var menuIsOpen = false
    private var isCleaningJunk = false

    var isMenuOpen: Bool {
        menuIsOpen
    }

    override init() {
        detailItems = (0..<7).map { _ in
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        super.init()
        statusItem.menu = makeMenu()
        applyMenuBarIcon()
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scan = JunkCleaner.scan()
            DispatchQueue.main.async {
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
        isCleaningJunk = false
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        detailItems.forEach(menu.addItem)
        menu.addItem(.separator())

        let junkItem = NSMenuItem(
            title: "정크 파일 정리…",
            action: #selector(cleanJunkFiles),
            keyEquivalent: ""
        )
        junkItem.target = self
        menu.addItem(junkItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func applyMenuBarIcon() {
        guard let image = NSImage(named: "MenuBarIcon") else {
            return
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.imageScaling = .scaleProportionallyDown
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

    private func applyDetailLines(_ lines: [MemoryDetailLine]) {
        for (item, line) in zip(detailItems, lines) {
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
