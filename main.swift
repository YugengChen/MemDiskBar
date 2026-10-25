import AppKit
import ServiceManagement

// MARK: - 数据采集

struct MemoryInfo {
    let used: UInt64   // 与「活动监视器」的“已使用内存”一致：App 内存 + 联动 + 已压缩
    let total: UInt64
    var ratio: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct DiskInfo {
    let used: UInt64
    let total: UInt64
    var ratio: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

func readMemory() -> MemoryInfo {
    let total = ProcessInfo.processInfo.physicalMemory
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return MemoryInfo(used: 0, total: total) }

    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let page = UInt64(pageSize)

    let appMemory = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
    let wired = UInt64(stats.wire_count)
    let compressed = UInt64(stats.compressor_page_count)
    let used = min((appMemory + wired + compressed) * page, total)
    return MemoryInfo(used: used, total: total)
}

func readDisk() -> DiskInfo {
    let url = URL(fileURLWithPath: "/")
    let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
    guard let values = try? url.resourceValues(forKeys: keys),
          let total = values.volumeTotalCapacity,
          let free = values.volumeAvailableCapacityForImportantUsage else {
        return DiskInfo(used: 0, total: 0)
    }
    let t = UInt64(total)
    let f = UInt64(max(free, 0))
    return DiskInfo(used: t > f ? t - f : 0, total: t)
}

// MARK: - 格式化

func gb(_ bytes: UInt64, decimal: Bool) -> String {
    // 内存用 1024 进制，磁盘用 1000 进制（与 Finder/系统设置一致）
    let unit: Double = decimal ? 1_000_000_000 : 1_073_741_824
    let v = Double(bytes) / unit
    return v >= 100 ? String(format: "%.0fG", v) : String(format: "%.1fG", v)
}

func pct(_ r: Double) -> String { String(format: "%.0f%%", r * 100) }

/// 已用/总量，例如 6.8/8GB、162/245GB
func usedOfTotal(_ used: UInt64, _ total: UInt64, decimal: Bool) -> String {
    let unit: Double = decimal ? 1_000_000_000 : 1_073_741_824
    func num(_ v: Double) -> String {
        let s = v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    return "\(num(Double(used) / unit))/\(num(Double(total) / unit))GB"
}

enum DisplayMode: Int {
    case size = 0, percent = 1
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private let memDetail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let diskDetail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let percentItem = NSMenuItem(title: "显示百分比", action: #selector(setPercent), keyEquivalent: "")
    private let sizeItem = NSMenuItem(title: "显示 已用/总量", action: #selector(setSize), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLogin), keyEquivalent: "")

    private var mode: DisplayMode {
        get { DisplayMode(rawValue: UserDefaults.standard.integer(forKey: "displayMode2")) ?? .size }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode2"); refresh() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(memDetail)
        menu.addItem(diskDetail)
        menu.addItem(.separator())
        for item in [percentItem, sizeItem, loginItem] { item.target = self }
        menu.addItem(percentItem)
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开活动监视器", action: #selector(openActivityMonitor), keyEquivalent: "").target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        refresh()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh() {
        let mem = readMemory()
        let disk = readDisk()

        let memText: String
        let diskText: String
        switch mode {
        case .percent:
            memText = pct(mem.ratio)
            diskText = pct(disk.ratio)
        case .size:
            memText = usedOfTotal(mem.used, mem.total, decimal: false)
            diskText = usedOfTotal(disk.used, disk.total, decimal: true)
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let title = NSMutableAttributedString()
        title.append(symbol("memorychip", fallback: "内存"))
        title.append(gauge(mem.ratio))
        title.append(NSAttributedString(string: " \(memText)", attributes: [.font: font, .foregroundColor: color(mem.ratio)]))
        title.append(NSAttributedString(string: "   ", attributes: [.font: font]))
        title.append(symbol("internaldrive", fallback: "储存"))
        title.append(gauge(disk.ratio))
        title.append(NSAttributedString(string: " \(diskText)", attributes: [.font: font, .foregroundColor: color(disk.ratio)]))
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = "内存 \(pct(mem.ratio)) · 储存 \(pct(disk.ratio))"

        memDetail.title = "内存：\(gb(mem.used, decimal: false)) / \(gb(mem.total, decimal: false))（\(pct(mem.ratio))）"
        diskDetail.title = "储存：\(gb(disk.used, decimal: true)) / \(gb(disk.total, decimal: true))（\(pct(disk.ratio))），剩余 \(gb(disk.total - disk.used, decimal: true))"
        percentItem.state = mode == .percent ? .on : .off
        sizeItem.state = mode == .size ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    /// 占用超过 90% 标红，超过 75% 标橙，其余跟随菜单栏文字颜色
    private func color(_ r: Double) -> NSColor {
        if r >= 0.9 { return .systemRed }
        if r >= 0.75 { return .systemOrange }
        return .labelColor
    }

    /// 竖向小胶囊进度条，绘制时才取颜色，能自动跟随浅色/深色菜单栏
    private func gauge(_ r: Double) -> NSAttributedString {
        let size = NSSize(width: 9, height: 14)
        let fillColor = r >= 0.75 ? color(r) : NSColor.labelColor
        let image = NSImage(size: size, flipped: false) { rect in
            let track = NSBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 0.5), xRadius: 2, yRadius: 2)
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            track.fill()
            var fill = rect.insetBy(dx: 2.5, dy: 0.5)
            fill.size.height *= CGFloat(min(max(r, 0), 1))
            fillColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2.5, width: size.width, height: size.height)
        return NSAttributedString(attachment: attachment)
    }

    private func symbol(_ name: String, fallback: String) -> NSAttributedString {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: fallback) else {
            return NSAttributedString(string: fallback, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let attachment = NSTextAttachment()
        let configured = img.withSymbolConfiguration(config) ?? img
        configured.isTemplate = true
        attachment.image = configured
        attachment.bounds = CGRect(x: 0, y: -2, width: configured.size.width, height: configured.size.height)
        return NSAttributedString(attachment: attachment)
    }

    @objc private func setPercent() { mode = .percent }
    @objc private func setSize() { mode = .size }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动设置"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }
}

// 命令行：MemDiskBar --login on|off，用于在不点菜单的情况下设置开机启动
if let i = CommandLine.arguments.firstIndex(of: "--login"), i + 1 < CommandLine.arguments.count {
    do {
        if CommandLine.arguments[i + 1] == "on" {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        print("login item status: \(SMAppService.mainApp.status.rawValue)") // 1 = enabled
        exit(0)
    } catch {
        print("failed: \(error.localizedDescription)")
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
