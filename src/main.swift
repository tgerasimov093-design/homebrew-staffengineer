import AppKit

final class Connector: NSObject, NSApplicationDelegate {
    private var worker: Process?
    private var pipe: Pipe?
    private var item: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "StaffEngineer")
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть доску StaffEngineer", action: #selector(openBoard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Отключиться и выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        item = status
    }

    private var origin = "https://staffengineer.ru"
    @objc private func openBoard() {
        if let url = URL(string: origin + "/systemdesign/mcp") { NSWorkspace.shared.open(url) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.scheme == "staffengineer-interview", parts.host == "connect",
                  parts.user == nil, parts.password == nil, parts.port == nil,
                  parts.fragment == nil, parts.path.isEmpty else { continue }
            let query = parts.queryItems ?? []
            func get(_ key: String) -> String? { query.first { $0.name == key }?.value }
            guard query.count == 3, let nonce = get("nonce"), nonce.utf8.count == 64,
                  nonce.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let agent = get("agent"), ["codex", "claude-code"].contains(agent),
                  let site = get("site"), ["local", "production"].contains(site) else { continue }
            origin = site == "local" ? "http://localhost:5173" : "https://staffengineer.ru"
            do {
                try ensureWorker()
                var data = try JSONSerialization.data(withJSONObject: ["origin": origin, "nonce": nonce, "agent": agent])
                data.append(10)
                try pipe?.fileHandleForWriting.write(contentsOf: data)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Не удалось запустить коннектор"
                alert.informativeText = "Переустановите StaffEngineer для macOS и повторите подключение на доске."
                alert.runModal()
            }
        }
    }

    private func ensureWorker() throws {
        if worker?.isRunning == true { return }
        let resources = Bundle.main.resourceURL!
        let node = resources.appendingPathComponent("node")
        let process = Process()
        process.executableURL = node
        process.arguments = [resources.appendingPathComponent("desktop.mjs").path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [node.resolvingSymlinksInPath().deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].joined(separator: ":")
        process.environment = env
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        pipe = input
        worker = process
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? pipe?.fileHandleForWriting.close()
    }
}
let app = NSApplication.shared
let delegate = Connector()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
