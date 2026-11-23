// PageKey — 仅当指定 App 在前台时，把右侧修饰键临时改成翻页键
//
// 原理：不拦截按键事件，因此**不需要「辅助功能」授权**。
// 在目标 App 激活 / 失活时，用系统自带的 /usr/bin/hidutil 在 HID 层
// 应用或撤销键盘映射。切换瞬时生效，其他 App 里按键保持原样。
//
//   双击启动      → 弹窗说明（菜单栏出现 ⌨ 图标）
//   切到目标 App  → 应用映射 + 右上角提示条
//   切走          → 撤销映射，按键恢复原功能
//
// 构建：make build（或 swiftc -O Sources/PageKey/main.swift -o build/pagekey）
// 许可：MIT

let PageKeyVersion = "1.1.0"

import Cocoa

// ---------- 可配置项 ----------
// 右 Command(0x7000000E7) → Page Up(0x70000004B)
// 右 Option (0x7000000E6) → Page Down(0x70000004E)
let MAP_ON = """
{"UserKeyMapping":[\
{"HIDKeyboardModifierMappingSrc":0x7000000E7,"HIDKeyboardModifierMappingDst":0x70000004B},\
{"HIDKeyboardModifierMappingSrc":0x7000000E6,"HIDKeyboardModifierMappingDst":0x70000004E}\
]}
"""
let MAP_OFF = "{\"UserKeyMapping\":[]}"

// ---------- 提示条（HUD） ----------
final class HUD: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 92),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        alphaValue = 0

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 92))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]

        label.frame = NSRect(x: 18, y: 14, width: 344, height: 64)
        label.autoresizingMask = [.width, .height]
        label.alignment = .left
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byWordWrapping
        blur.addSubview(label)
        contentView = blur
    }

    func show(text: String) {
        label.attributedStringValue = HUD.render(text)
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            animator().alphaValue = 0
        }, completionHandler: { self.orderOut(nil) })
    }

    static func render(_ text: String) -> NSAttributedString {
        let lines = text.components(separatedBy: "\n")
        let out = NSMutableAttributedString()
        for (i, line) in lines.enumerated() {
            let font: NSFont = i == 0
                ? .systemFont(ofSize: 14, weight: .semibold)
                : .systemFont(ofSize: 12, weight: .regular)
            let color: NSColor = i == 0 ? .labelColor : .secondaryLabelColor
            out.append(NSAttributedString(string: i == lines.count - 1 ? line : line + "\n",
                attributes: [.font: font, .foregroundColor: color]))
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return out
    }
}

// ---------- App ----------
final class AppDelegate: NSObject, NSApplicationDelegate {
    var targetIDs: Set<String> = ["com.microsoft.rdc.macos"]
    var statusItem: NSStatusItem!
    var hud = HUD()
    var hudFade: DispatchWorkItem?
    // 菜单里的两个开关，持久化到 UserDefaults
    var hudEnabled: Bool = (UserDefaults.standard.object(forKey: "hudEnabled") as? Bool) ?? true
    var notifyOnLeave: Bool = UserDefaults.standard.bool(forKey: "notifyOnLeave")
    var targetFrontmost = false
    var applied = false
    let queue = DispatchQueue(label: "pagekey.hidutil", qos: .userInitiated)

    // --- hidutil 应用/撤销 ---
    func apply(_ on: Bool) {
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
            p.arguments = ["property", "--set", on ? MAP_ON : MAP_OFF]
            do { try p.run(); p.waitUntilExit() } catch {
                DispatchQueue.main.async {
                    self.showHUD("hidutil 调用失败：\(error.localizedDescription)")
                }
            }
        }
        applied = on
    }

    // --- 生命周期 ---
    func applicationDidFinishLaunching(_ n: Notification) {
        setupStatusItem()
        setupAppObserver()
        setupSignalHandlers()
        // 先清掉上次异常退出可能残留的全局映射
        apply(false)
        // 稍后同步一次真实前台状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.syncWithFrontmost() }
        refreshMenu()

        // 调试用：打印菜单结构后退出（CI 冒烟测试也用它）
        if cliArgs.contains("--dump-menu") {
            for item in statusItem.menu?.items ?? [] {
                if item.isSeparatorItem { print("---"); continue }
                let mark = item.state == .on ? "[x]" : "[ ]"
                print("\(mark) \(item.title)\(item.isEnabled ? "" : "   (置灰)")")
            }
            exit(0)
        }

        if !quietMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showInfoAlert(first: true) }
        }
    }

    func syncWithFrontmost() {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        let hit = targetIDs.contains(id)
        guard hit != targetFrontmost else { return }
        targetFrontmost = hit
        apply(hit)
        refreshMenu()
    }

    var signalSources: [DispatchSourceSignal] = []

    @objc func setupSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { self.hardExit() }
            src.resume()
            signalSources.append(src)
        }
    }

    func hardExit() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", MAP_OFF]
        try? p.run()
        p.waitUntilExit()
        exit(0)
    }

    func applicationWillTerminate(_ n: Notification) {
        // 退出前务必撤销，避免全局残留
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", MAP_OFF]
        try? p.run()
        p.waitUntilExit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showInfoAlert(first: false)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // --- 说明弹窗 ---
    func showInfoAlert(first: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = first ? "PageKey 已启动（无需任何权限）" : "PageKey 已在后台运行"
        a.informativeText = """
        生效范围：\(targetIDs.sorted().joined(separator: "、"))
        该 App 在前台时：
            右 Command  →  Page Up
            右 Option   →  Page Down
        切走即自动恢复原功能，其他 App 完全不受影响。

        切到目标 App 时会弹出提示条；菜单栏 ⌨ 图标可查看状态或退出。
        """
        a.addButton(withTitle: "知道了")
        a.addButton(withTitle: "退出 PageKey")
        if a.runModal() == .alertSecondButtonReturn { NSApp.terminate(nil) }
    }

    // --- 菜单栏 ---
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = NSMenu()
    }

    func setupAppObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            let hit = self.targetIDs.contains(id)
            guard hit != self.targetFrontmost else { return }
            self.targetFrontmost = hit
            self.apply(hit)
            self.refreshMenu()
            if hit {
                self.showHUD("PageKey 已启用 · \(app.localizedName ?? id)\n右 ⌘ = Page Up     右 ⌥ = Page Down")
            } else if self.notifyOnLeave {
                self.showHUD("PageKey 已挂起 · 按键已恢复原功能\n切回目标 App 即自动启用")
            }
        }
    }

    func refreshMenu() {
        if let btn = statusItem.button {
            let name = targetFrontmost ? "keyboard.fill" : "keyboard"
            let img = NSImage(systemSymbolName: name, accessibilityDescription: "PageKey")
            img?.isTemplate = true
            btn.image = img
            btn.toolTip = targetFrontmost ? "PageKey：已启用" : "PageKey：待命"
        }
        statusItem.menu?.removeAllItems()
        let state = NSMenuItem(title: targetFrontmost ? "状态：已启用" : "状态：待命（当前 App 不在范围）",
                               action: nil, keyEquivalent: "")
        state.isEnabled = false
        statusItem.menu?.addItem(state)
        let scope = NSMenuItem(title: "生效范围：\(targetIDs.sorted().joined(separator: ", "))",
                               action: nil, keyEquivalent: "")
        scope.isEnabled = false
        statusItem.menu?.addItem(scope)
        statusItem.menu?.addItem(.separator())
        let hudToggle = NSMenuItem(title: "显示切换提示条",
                                   action: #selector(toggleHUD), keyEquivalent: "h")
        hudToggle.state = hudEnabled ? .on : .off
        statusItem.menu?.addItem(hudToggle)

        let toggle = NSMenuItem(title: "切走时也提示",
                                action: #selector(toggleLeaveNotice), keyEquivalent: "")
        toggle.state = (hudEnabled && notifyOnLeave) ? .on : .off
        toggle.isEnabled = hudEnabled          // 总开关关掉时，子选项置灰
        statusItem.menu?.addItem(toggle)

        statusItem.menu?.addItem(NSMenuItem(title: "预览提示条", action: #selector(testHUD), keyEquivalent: "t"))
        statusItem.menu?.addItem(NSMenuItem(title: "使用说明", action: #selector(showHelp), keyEquivalent: ""))
        statusItem.menu?.addItem(.separator())
        statusItem.menu?.addItem(NSMenuItem(title: "退出 PageKey", action: #selector(quit), keyEquivalent: "q"))
        for item in statusItem.menu?.items ?? [] { item.target = self }
    }

    @objc func toggleHUD() {
        hudEnabled.toggle()
        UserDefaults.standard.set(hudEnabled, forKey: "hudEnabled")
        if !hudEnabled { hud.hide() }
        refreshMenu()
    }

    @objc func toggleLeaveNotice() {
        notifyOnLeave.toggle()
        UserDefaults.standard.set(notifyOnLeave, forKey: "notifyOnLeave")
        refreshMenu()
    }

    @objc func testHUD() {
        let note = hudEnabled ? "" : "\n（总开关当前为关闭状态）"
        showHUD("PageKey 提示条测试\n右 ⌘ = Page Up     右 ⌥ = Page Down" + note, force: true)
    }
    @objc func showHelp() { showInfoAlert(first: false) }
    @objc func quit() { NSApp.terminate(nil) }

    func showHUD(_ text: String, force: Bool = false) {
        guard hudEnabled || force else { return }
        hudFade?.cancel()
        hud.show(text: text)
        let work = DispatchWorkItem { self.hud.hide() }
        hudFade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }
}

// ---------- 入口 ----------
var cliArgs = Array(CommandLine.arguments.dropFirst())

let usage = """
PageKey \(PageKeyVersion) — 只在指定 App 前台时把右侧修饰键变成翻页键

用法:
  PageKey [bundle-id ...] [选项]

选项:
  --quiet     静默启动（不弹说明框，适合加登录项）
  --no-hud    不显示切换提示条（等价于菜单里关掉「显示切换提示条」）
  --no-hud    不显示切换提示条（等价于菜单里关掉「显示切换提示条」）
  --reset     清除全局键位映射，恢复正常
  --list      打印当前前台 App 的 bundle id（用来查目标 id）
  --version   版本号
  -h, --help  本帮助

示例:
  PageKey com.microsoft.rdc.macos
  PageKey com.apple.Terminal com.microsoft.rdc.macos --quiet
"""

if cliArgs.contains("--version") { print("PageKey \(PageKeyVersion)"); exit(0) }
if cliArgs.contains("-h") || cliArgs.contains("--help") { print(usage); exit(0) }

if cliArgs.contains("--list") {
    if let app = NSWorkspace.shared.frontmostApplication {
        print("前台 App: \(app.localizedName ?? "?")  bundle id: \(app.bundleIdentifier ?? "?")")
    }
    exit(0)
}

let app = NSApplication.shared

// 单实例保护
if let bid = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        .filter { $0.processIdentifier != getpid() }
    if !others.isEmpty {
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "PageKey 已经在运行"
        a.informativeText = "它正静默待命，请在菜单栏找到 ⌨ 图标查看状态或退出。"
        a.addButton(withTitle: "好")
        a.runModal()
        exit(0)
    }
}

if cliArgs.contains("--reset") {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = ["property", "--set", MAP_OFF]
    try? p.run(); p.waitUntilExit()
    print("已清除全局键位映射（恢复正常）")
    exit(0)
}

let quietMode = cliArgs.contains("--quiet")
let delegate = AppDelegate()
let ids = cliArgs.filter { !$0.hasPrefix("--") }
if !ids.isEmpty { delegate.targetIDs = Set(ids) }
if cliArgs.contains("--no-hud") { delegate.hudEnabled = false }
if cliArgs.contains("--no-hud") { delegate.hudEnabled = false }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
