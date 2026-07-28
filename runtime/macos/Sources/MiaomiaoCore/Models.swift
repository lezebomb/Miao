import Foundation

public struct PetBehavior: Codable, Sendable {
    public let formatVersion: Int
    public let cell: Cell
    public let actions: [String: Action]
    public let events: Events

    public struct Cell: Codable, Sendable {
        public let width: Double
        public let height: Double
    }

    public struct Action: Codable, Sendable {
        public let frames: [String]
        public let frameDurationMs: Double
        public let frameDurationsMs: [Double]?
        public let repeatCount: Int?
        public let loop: Bool
        public let outroAction: String?

        public func duration(at index: Int) -> Double {
            frameDurationsMs?[index] ?? frameDurationMs
        }
    }

    public struct Events: Codable, Sendable {
        public let petOrHover: PetOrHover
        public let dragLeft: String
        public let dragRight: String
        public let idle: Idle
    }

    public struct PetOrHover: Codable, Sendable {
        public let random: [String]
        public let weights: [Double]
        public let ignoreWhilePlaying: Bool
    }

    public struct Idle: Codable, Sendable {
        public let `default`: String
        public let microActions: [WeightedAction]
        public let random: [WeightedAction]
        public let specialCheckIntervalMs: [Double]
    }

    public struct WeightedAction: Codable, Sendable {
        public let action: String
        public let weight: Double
    }
}

public struct MiaomiaoConfiguration: Codable, Sendable {
    public let formatVersion: Int
    public let globalDurationScale: Double
    public let windowScale: Double
    public let idlePauseRangeMs: [Double]
    public let hoverDwellMs: Double
    public let triggerCooldownMs: Double
    public let drag: Drag
    public let codexWindow: FollowWindow

    public struct Drag: Codable, Sendable {
        public let horizontalThresholdPx: Double
        public let horizontalDominanceRatio: Double
    }

    public struct FollowWindow: Codable, Sendable {
        public let placement: String
        public let offsetX: Double
        public let offsetY: Double
        public let edgePadding: Double
        public let followIntervalMs: Double
        public let waitTimeoutMs: Double
    }
}

public enum MiaomiaoDataError: LocalizedError {
    case missingFile(URL)
    case invalidValue(String)
    case unsafeFramePath(String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let url):
            return "Missing required file: \(url.path)"
        case .invalidValue(let message):
            return "Invalid Miaomiao configuration: \(message)"
        case .unsafeFramePath(let path):
            return "Frame path escapes the pet resource directory: \(path)"
        }
    }
}

public struct RuntimeResources: Sendable {
    public let root: URL
    public let petRoot: URL
    public let behaviorURL: URL
    public let configurationURL: URL
    public let behavior: PetBehavior
    public let configuration: MiaomiaoConfiguration

    public init(root: URL) throws {
        let normalizedRoot = root.standardizedFileURL
        let petRoot = normalizedRoot
            .appendingPathComponent("pet", isDirectory: true)
            .appendingPathComponent("miaomiao", isDirectory: true)
        let behaviorURL = petRoot.appendingPathComponent("behavior.json")
        let configurationURL = normalizedRoot.appendingPathComponent("miaomiao.config.json")

        for url in [behaviorURL, configurationURL] where !FileManager.default.fileExists(atPath: url.path) {
            throw MiaomiaoDataError.missingFile(url)
        }

        let decoder = JSONDecoder()
        let behavior = try decoder.decode(PetBehavior.self, from: Data(contentsOf: behaviorURL))
        let configuration = try decoder.decode(
            MiaomiaoConfiguration.self,
            from: Data(contentsOf: configurationURL)
        )

        self.root = normalizedRoot
        self.petRoot = petRoot
        self.behaviorURL = behaviorURL
        self.configurationURL = configurationURL
        self.behavior = behavior
        self.configuration = configuration
        try validate()
    }

    public func frameURL(relativePath: String) throws -> URL {
        let candidate = petRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = petRoot.path.hasSuffix("/") ? petRoot.path : petRoot.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw MiaomiaoDataError.unsafeFramePath(relativePath)
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw MiaomiaoDataError.missingFile(candidate)
        }
        return candidate
    }

    private func validate() throws {
        guard behavior.formatVersion >= 1 else {
            throw MiaomiaoDataError.invalidValue("behavior formatVersion must be positive")
        }
        guard configuration.formatVersion >= 1 else {
            throw MiaomiaoDataError.invalidValue("config formatVersion must be positive")
        }
        guard behavior.cell.width > 0, behavior.cell.height > 0 else {
            throw MiaomiaoDataError.invalidValue("cell dimensions must be positive")
        }
        guard configuration.globalDurationScale > 0 else {
            throw MiaomiaoDataError.invalidValue("globalDurationScale must be greater than zero")
        }
        guard configuration.windowScale > 0 else {
            throw MiaomiaoDataError.invalidValue("windowScale must be greater than zero")
        }
        try validateRange(configuration.idlePauseRangeMs, name: "idlePauseRangeMs")
        try validateRange(
            behavior.events.idle.specialCheckIntervalMs,
            name: "idle.specialCheckIntervalMs"
        )
        guard configuration.hoverDwellMs >= 0, configuration.triggerCooldownMs >= 0 else {
            throw MiaomiaoDataError.invalidValue("interaction delays cannot be negative")
        }
        guard configuration.drag.horizontalThresholdPx >= 0,
              configuration.drag.horizontalDominanceRatio > 0 else {
            throw MiaomiaoDataError.invalidValue("drag thresholds must be valid")
        }
        guard configuration.codexWindow.followIntervalMs > 0,
              configuration.codexWindow.waitTimeoutMs >= 0 else {
            throw MiaomiaoDataError.invalidValue("follow intervals must be valid")
        }

        for (name, action) in behavior.actions {
            guard !action.frames.isEmpty else {
                throw MiaomiaoDataError.invalidValue("action \(name) has no frames")
            }
            if let durations = action.frameDurationsMs, durations.count != action.frames.count {
                throw MiaomiaoDataError.invalidValue(
                    "action \(name) has \(action.frames.count) frames but \(durations.count) durations"
                )
            }
            guard action.frames.indices.allSatisfy({ action.duration(at: $0) > 0 }) else {
                throw MiaomiaoDataError.invalidValue("action \(name) has a non-positive duration")
            }
            guard (action.repeatCount ?? 1) > 0 else {
                throw MiaomiaoDataError.invalidValue("action \(name) repeatCount must be positive")
            }
            if let outro = action.outroAction, behavior.actions[outro] == nil {
                throw MiaomiaoDataError.invalidValue("action \(name) references unknown outro \(outro)")
            }
            for frame in action.frames {
                _ = try frameURL(relativePath: frame)
            }
        }

        var referencedActions = [
            behavior.events.dragLeft,
            behavior.events.dragRight,
            behavior.events.idle.default
        ]
        referencedActions += behavior.events.petOrHover.random
        referencedActions += behavior.events.idle.microActions.map(\.action)
        referencedActions += behavior.events.idle.random.map(\.action)
        for name in referencedActions where behavior.actions[name] == nil {
            throw MiaomiaoDataError.invalidValue("event references unknown action \(name)")
        }
        guard behavior.events.petOrHover.random.count == behavior.events.petOrHover.weights.count else {
            throw MiaomiaoDataError.invalidValue("petOrHover choices and weights must have equal lengths")
        }
    }

    private func validateRange(_ values: [Double], name: String) throws {
        guard values.count == 2, values[0] >= 0, values[0] <= values[1] else {
            throw MiaomiaoDataError.invalidValue("\(name) must contain an ordered non-negative pair")
        }
    }
}
