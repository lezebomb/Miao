import Foundation

public enum WeightedChoice {
    public static func choose(
        names: [String],
        weights: [Double],
        unitRandom: Double
    ) -> String? {
        guard names.count == weights.count, !names.isEmpty else { return nil }
        let positiveWeights = weights.map { max(0, $0) }
        let total = positiveWeights.reduce(0, +)
        guard total > 0 else { return nil }
        let target = min(max(unitRandom, 0), 0.999_999_999) * total
        var cumulative = 0.0
        for (index, weight) in positiveWeights.enumerated() {
            cumulative += weight
            if target < cumulative {
                return names[index]
            }
        }
        return names.last
    }

    public static func choose(
        entries: [PetBehavior.WeightedAction],
        unitRandom: Double,
        allowsNoSelection: Bool
    ) -> String? {
        let total = entries.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else { return nil }
        let unit = min(max(unitRandom, 0), 0.999_999_999)
        if allowsNoSelection, unit >= total {
            return nil
        }
        let target = allowsNoSelection ? unit : unit * total
        var cumulative = 0.0
        for entry in entries {
            cumulative += max(0, entry.weight)
            if target < cumulative {
                return entry.action
            }
        }
        return entries.last?.action
    }
}

public enum DragDirection: Equatable {
    case none
    case left
    case right
}

public enum InteractionLogic {
    public static func dragDirection(
        deltaX: Double,
        deltaY: Double,
        threshold: Double,
        dominanceRatio: Double
    ) -> DragDirection {
        guard abs(deltaX) >= threshold,
              abs(deltaX) >= abs(deltaY) * dominanceRatio else {
            return .none
        }
        return deltaX < 0 ? .left : .right
    }
}

public struct PlaybackCursor: Equatable {
    public private(set) var frameIndex = 0
    public private(set) var completedCycles = 0

    public init() {}

    public mutating func advance(frameCount: Int, repeatCount: Int, loops: Bool) -> Bool {
        frameIndex += 1
        if frameIndex < frameCount {
            return true
        }
        if loops {
            frameIndex = 0
            return true
        }
        completedCycles += 1
        if completedCycles < repeatCount {
            frameIndex = 0
            return true
        }
        return false
    }
}
