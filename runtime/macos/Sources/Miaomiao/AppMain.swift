import AppKit
import Foundation
import MiaomiaoCore

private struct CommandLineOptions {
    let followChatGPT: Bool
    let checkOnly: Bool
    let resourceRoot: URL?
    let automaticExitMilliseconds: Double?

    init(arguments: [String]) throws {
        var followChatGPT = false
        var checkOnly = false
        var resourceRoot: URL?
        var automaticExitMilliseconds: Double?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--follow-chatgpt", "--follow-codex":
                followChatGPT = true
            case "--check-only":
                checkOnly = true
            case "--resource-root":
                index += 1
                guard index < arguments.count else {
                    throw MiaomiaoDataError.invalidValue("--resource-root requires a path")
                }
                resourceRoot = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--test-auto-exit-ms":
                index += 1
                guard index < arguments.count,
                      let value = Double(arguments[index]),
                      value > 0 else {
                    throw MiaomiaoDataError.invalidValue(
                        "--test-auto-exit-ms requires a positive number"
                    )
                }
                automaticExitMilliseconds = value
            default:
                throw MiaomiaoDataError.invalidValue(
                    "unknown command-line option \(arguments[index])"
                )
            }
            index += 1
        }
        self.followChatGPT = followChatGPT
        self.checkOnly = checkOnly
        self.resourceRoot = resourceRoot
        self.automaticExitMilliseconds = automaticExitMilliseconds
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let resources: RuntimeResources
    private let options: CommandLineOptions
    private var instanceLock: SingleInstanceLock?
    private var petController: PetWindowController?
    private var follower: ChatGPTFollower?

    init(resources: RuntimeResources, options: CommandLineOptions) {
        self.resources = resources
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            instanceLock = try SingleInstanceLock()
        } catch SingleInstanceError.alreadyRunning {
            fputs("Miaomiao is already running; duplicate launch ignored.\n", stderr)
            NSApp.terminate(nil)
            return
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        let pet = PetWindowController(resources: resources)
        petController = pet
        pet.start()
        if options.followChatGPT {
            let follower = ChatGPTFollower(
                pet: pet,
                configuration: resources.configuration.codexWindow
            )
            self.follower = follower
            follower.start()
        }
        if let delay = options.automaticExitMilliseconds {
            Timer.scheduledTimer(withTimeInterval: delay / 1_000, repeats: false) { _ in
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        follower?.stop()
        petController?.stop()
        instanceLock = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private func resolveResources(options: CommandLineOptions) throws -> RuntimeResources {
    if let root = options.resourceRoot {
        return try RuntimeResources(root: root)
    }
    guard let bundledRoot = Bundle.main.resourceURL else {
        throw MiaomiaoDataError.invalidValue("application resource directory is unavailable")
    }
    return try RuntimeResources(root: bundledRoot)
}

@main
private struct MiaomiaoApplication {
    @MainActor
    static func main() {
        do {
            let options = try CommandLineOptions(arguments: CommandLine.arguments)
            let resources = try resolveResources(options: options)
            if options.checkOnly {
                let actionCount = resources.behavior.actions.count
                let frameCount = resources.behavior.actions.values.reduce(0) {
                    $0 + $1.frames.count
                }
                print("Miaomiao macOS validation passed.")
                print("Behavior: \(resources.behaviorURL.path)")
                print("Config: \(resources.configurationURL.path)")
                print("Actions: \(actionCount); frames: \(frameCount)")
                print(
                    "globalDurationScale=\(resources.configuration.globalDurationScale); " +
                    "windowScale=\(resources.configuration.windowScale)"
                )
                exit(EXIT_SUCCESS)
            }

            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let delegate = AppDelegate(resources: resources, options: options)
            application.delegate = delegate
            application.run()
        } catch {
            fputs("Miaomiao failed to start: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
