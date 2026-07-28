import AppKit
import ApplicationServices
import MiaomiaoCore

@MainActor
final class ChatGPTFollower {
    private static let bundleIdentifiers = [
        "com.openai.chat",
        "com.openai.codex"
    ]
    private static let applicationNames = ["ChatGPT", "Codex"]

    private let pet: PetWindowController
    private let configuration: MiaomiaoConfiguration.FollowWindow
    private var timer: Timer?
    private var targetApplication: NSRunningApplication?
    private var launchDeadline = Date.distantFuture
    private var didTryLaunch = false
    private var didRequestAccessibility = false
    private var hasAttachedToTarget = false
    private var terminationObserver: NSObjectProtocol?

    init(pet: PetWindowController, configuration: MiaomiaoConfiguration.FollowWindow) {
        self.pet = pet
        self.configuration = configuration
    }

    func start() {
        launchDeadline = Date().addingTimeInterval(configuration.waitTimeoutMs / 1_000)
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let terminated = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                      ] as? NSRunningApplication,
                      terminated.processIdentifier == self.targetApplication?.processIdentifier,
                      self.hasAttachedToTarget else {
                    return
                }
                NSApp.terminate(nil)
            }
        }
        poll()
        timer = Timer.scheduledTimer(
            withTimeInterval: configuration.followIntervalMs / 1_000,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    private func poll() {
        if targetApplication?.isTerminated == true {
            if hasAttachedToTarget {
                NSApp.terminate(nil)
            } else {
                fallBackToDesktopMode()
            }
            return
        }

        if targetApplication == nil {
            targetApplication = findRunningApplication()
        }
        if targetApplication == nil, !didTryLaunch {
            didTryLaunch = true
            launchTargetApplication()
        }
        guard let application = targetApplication else {
            if Date() >= launchDeadline {
                fallBackToDesktopMode()
            }
            return
        }

        guard accessibilityIsTrusted() else {
            requestAccessibilityIfNeeded()
            if Date() >= launchDeadline {
                fallBackToDesktopMode()
            }
            return
        }

        guard let targetWindow = readMainWindow(of: application) else {
            pet.show()
            return
        }
        hasAttachedToTarget = true
        if targetWindow.minimized {
            pet.hide()
            return
        }
        pet.show()
        pet.placeRelative(to: targetWindow.frame)
    }

    private func findRunningApplication() -> NSRunningApplication? {
        let applications = NSWorkspace.shared.runningApplications
        for bundleIdentifier in Self.bundleIdentifiers {
            if let application = applications.first(where: {
                $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
            }) {
                return application
            }
        }
        return applications.first {
            guard !$0.isTerminated, let name = $0.localizedName?.lowercased() else { return false }
            return Self.applicationNames.contains { name == $0.lowercased() }
        }
    }

    private func launchTargetApplication() {
        for bundleIdentifier in Self.bundleIdentifiers {
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                continue
            }
            let launchConfiguration = NSWorkspace.OpenConfiguration()
            launchConfiguration.activates = true
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: launchConfiguration
            ) { [weak self] application, _ in
                DispatchQueue.main.async { [weak self, application] in
                    if let application {
                        self?.targetApplication = application
                    }
                }
            }
            return
        }
        showInformationalAlert(
            message: "未找到 ChatGPT 或 Codex",
            details: "妙妙会继续以普通桌宠模式运行。安装并启动 macOS 版 ChatGPT/Codex 后，可重新用跟随模式启动。"
        )
        fallBackToDesktopMode()
    }

    private func accessibilityIsTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    private func requestAccessibilityIfNeeded() {
        guard !didRequestAccessibility else { return }
        didRequestAccessibility = true
        showInformationalAlert(
            message: "需要辅助功能权限",
            details: "跟随 ChatGPT/Codex 窗口需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Miaomiao。未授权时妙妙仍可作为普通桌宠运行。"
        )
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    private func readMainWindow(of application: NSRunningApplication) -> TargetWindow? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let mainWindow: AXUIElement? = copyAttribute(
            appElement,
            kAXMainWindowAttribute as CFString
        )
        if let mainWindow, let window = targetWindow(from: mainWindow) {
            return window
        }
        let windows: [AXUIElement]? = copyAttribute(
            appElement,
            kAXWindowsAttribute as CFString
        )
        guard let windows else {
            return nil
        }
        return windows.lazy.compactMap { self.targetWindow(from: $0) }.first
    }

    private func targetWindow(from element: AXUIElement) -> TargetWindow? {
        let minimizedValue: Bool? = copyAttribute(
            element,
            kAXMinimizedAttribute as CFString
        )
        let positionValue: AXValue? = copyAttribute(
            element,
            kAXPositionAttribute as CFString
        )
        let sizeValue: AXValue? = copyAttribute(
            element,
            kAXSizeAttribute as CFString
        )
        guard let positionValue, let sizeValue else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        let mainScreenTop = NSScreen.screens.first?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        let appKitFrame = NSRect(
            x: position.x,
            y: mainScreenTop - position.y - size.height,
            width: size.width,
            height: size.height
        )
        return TargetWindow(frame: appKitFrame, minimized: minimizedValue ?? false)
    }

    private func copyAttribute<T>(
        _ element: AXUIElement,
        _ name: CFString
    ) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func fallBackToDesktopMode() {
        timer?.invalidate()
        timer = nil
        pet.show()
    }

    private func showInformationalAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = details
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private struct TargetWindow {
    let frame: NSRect
    let minimized: Bool
}
