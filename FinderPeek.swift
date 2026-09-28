// FinderPeek — auto-hide the Finder sidebar.
// The sidebar stays hidden; push the pointer to the left edge of a Finder
// window and it slides in. Move away and it hides again.
// Works through the Accessibility API: reads the window tree to see whether
// the sidebar is showing, and presses View ▸ Show/Hide Sidebar (⌃⌘S) to toggle.

import Cocoa
import ServiceManagement

// MARK: - Accessibility helpers

private func attr(_ e: AXUIElement, _ key: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
}
private func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, "AXChildren") as? [AXUIElement]) ?? [] }
private func role(_ e: AXUIElement) -> String? { attr(e, "AXRole") as? String }

private func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, "AXPosition"), let s = attr(e, "AXSize") else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

// MARK: - Finder

struct FinderWindow {
    let element: AXUIElement
    let frame: CGRect          // AX coordinates (top-left origin)
    let sidebarWidth: CGFloat? // nil = sidebar hidden
}

enum Finder {
    static let bundleID = "com.apple.finder"

    static func app() -> AXUIElement? {
        guard let f = NSWorkspace.shared.frontmostApplication, f.bundleIdentifier == bundleID else { return nil }
        return AXUIElementCreateApplication(f.processIdentifier)
    }

    /// Focused standard Finder browser window (not the desktop, Get Info, or a sheet).
    static func focusedWindow(_ app: AXUIElement) -> FinderWindow? {
        guard let w = attr(app, "AXFocusedWindow") as! AXUIElement?,
              (attr(w, "AXSubrole") as? String) == "AXStandardWindow",
              let f = frame(w),
              let split = children(w).first(where: { role($0) == "AXSplitGroup" })
        else { return nil }
        var width: CGFloat?
        for c in children(split) where role(c) == "AXScrollArea" {
            if children(c).contains(where: { role($0) == "AXOutline" }), let cf = frame(c), cf.width > 0 {
                width = cf.width
                break
            }
        }
        return FinderWindow(element: w, frame: f, sidebarWidth: width)
    }

    /// Press View ▸ Show/Hide Sidebar. Found by its ⌃⌘S shortcut so it works in any language.
    static func toggleSidebar(_ app: AXUIElement) {
        guard let bar = attr(app, "AXMenuBar") as! AXUIElement? else { return }
        for top in children(bar) {
            for menu in children(top) {
                for item in children(menu)
                where (attr(item, "AXMenuItemCmdChar") as? String) == "S"
                    && (attr(item, "AXMenuItemCmdModifiers") as? Int) == 4 { // 4 = ⌃ (⌘ implied)
                    AXUIElementPerformAction(item, "AXPress" as CFString)
                    return
                }
            }
        }
    }
}

// MARK: - Controller

final class Peek {
    var enabled = true

    // Tuning
    let edgeWidth: CGFloat = 8        // px inside the window's left edge that reveals the sidebar
    let toolbarHeight: CGFloat = 52   // ignore the toolbar/traffic-light strip
    let hideMargin: CGFloat = 24      // extra px past the sidebar before it counts as "left"
    let hideDelay: TimeInterval = 0.08 // tiny grace so overshooting the edge doesn't flicker
    let settleTimeout: TimeInterval = 0.5

    private var awaySince: Date?
    // After a toggle, Finder takes a moment to update its window tree. Until it
    // reports the state we asked for, don't act again (prevents double toggles).
    private var expectVisible: Bool?
    private var expectUntil = Date.distantPast
    private var timer: Timer?
    private var monitor: Any?

    func start() {
        // React the moment the pointer moves…
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] _ in
            self?.tick()
        }
        // …and keep a light timer for the hide grace period and window switches.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.005
    }

    // Set PEEK_DEBUG=1 to log decisions to stderr.
    private let debug = ProcessInfo.processInfo.environment["PEEK_DEBUG"] != nil
    private var lastLog = ""
    private func log(_ m: @autoclosure () -> String) {
        guard debug else { return }
        let s = m()
        if s != lastLog { lastLog = s; FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
    }

    private func toggle(_ app: AXUIElement, toVisible v: Bool, _ now: Date) {
        log(v ? "show" : "hide")
        Finder.toggleSidebar(app)
        expectVisible = v
        expectUntil = now.addingTimeInterval(settleTimeout)
        awaySince = nil
    }

    private func tick() {
        guard enabled, AXIsProcessTrusted(), let app = Finder.app(), let win = Finder.focusedWindow(app) else {
            awaySince = nil; return
        }
        let now = Date()
        let visible = win.sidebarWidth != nil
        if let e = expectVisible {
            if e != visible && now < expectUntil { return }
            expectVisible = nil
        }

        // Mouse in AX coordinates (flip from Cocoa's bottom-left origin).
        let m = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: m.x, y: primaryHeight - m.y)
        let f = win.frame
        let inContentRows = p.y >= f.minY + toolbarHeight && p.y <= f.maxY

        if let sw = win.sidebarWidth {
            // Visible: hide as soon as the pointer leaves the sidebar.
            // Never while a mouse button is down — you may be dragging a file onto a sidebar favourite.
            let near = inContentRows && p.x >= f.minX - edgeWidth && p.x <= f.minX + sw + hideMargin
            if near || NSEvent.pressedMouseButtons != 0 { awaySince = nil; return }
            awaySince = awaySince ?? now
            if now.timeIntervalSince(awaySince!) >= hideDelay { toggle(app, toVisible: false, now) }
        } else {
            // Hidden: reveal instantly at the left edge.
            if inContentRows && p.x >= f.minX - 2 && p.x <= f.minX + edgeWidth { toggle(app, toVisible: true, now) }
        }
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    let peek = Peek()
    var item: NSStatusItem!
    let enabledItem = NSMenuItem(title: "Auto-hide Finder Sidebar", action: #selector(toggleEnabled), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    let permItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openPrivacy), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "FinderPeek")

        let menu = NSMenu()
        menu.delegate = self
        for i in [enabledItem, loginItem, permItem] { i.target = self; menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FinderPeek", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        item.menu = menu

        peek.enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        peek.start()
    }

    @objc func toggleEnabled() {
        peek.enabled.toggle()
        UserDefaults.standard.set(peek.enabled, forKey: "enabled")
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { if s.status == .enabled { try s.unregister() } else { try s.register() } }
        catch { NSSound.beep() }
    }

    @objc func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = peek.enabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permItem.isHidden = AXIsProcessTrusted()
        item.button?.appearsDisabled = !peek.enabled
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
