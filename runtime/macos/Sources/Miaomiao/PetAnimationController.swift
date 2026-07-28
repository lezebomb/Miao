import AppKit
import MiaomiaoCore

@MainActor
final class PetAnimationController {
    private let imageView: NSImageView
    private let resources: RuntimeResources
    private let behavior: PetBehavior
    private let configuration: MiaomiaoConfiguration
    private var imageCache: [URL: NSImage] = [:]
    private var frameTimer: Timer?
    private var idleTimer: Timer?
    private var specialTimer: Timer?
    private(set) var currentActionName: String
    private var cursor = PlaybackCursor()
    private var lastPetTrigger = Date.distantPast
    private var dragging = false

    init(imageView: NSImageView, resources: RuntimeResources) {
        self.imageView = imageView
        self.resources = resources
        behavior = resources.behavior
        configuration = resources.configuration
        currentActionName = resources.behavior.events.idle.default
    }

    func start() {
        startIdle()
        scheduleSpecialCheck()
    }

    func setDragging(_ value: Bool) {
        dragging = value
    }

    func startDragAction(direction: DragDirection) {
        let actionName: String?
        switch direction {
        case .left:
            actionName = behavior.events.dragLeft
        case .right:
            actionName = behavior.events.dragRight
        case .none:
            actionName = nil
        }
        if let actionName, currentActionName != actionName {
            startAction(actionName)
        }
    }

    func endDrag() {
        startIdle()
    }

    func triggerPetAction() {
        let event = behavior.events.petOrHover
        if event.ignoreWhilePlaying, currentActionName != behavior.events.idle.default {
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastPetTrigger) * 1_000 >= configuration.triggerCooldownMs else {
            return
        }
        guard let choice = WeightedChoice.choose(
            names: event.random,
            weights: event.weights,
            unitRandom: Double.random(in: 0..<1)
        ) else {
            return
        }
        lastPetTrigger = now
        startAction(choice)
    }

    func stop() {
        frameTimer?.invalidate()
        idleTimer?.invalidate()
        specialTimer?.invalidate()
    }

    private func startIdle() {
        frameTimer?.invalidate()
        idleTimer?.invalidate()
        currentActionName = behavior.events.idle.default
        cursor = PlaybackCursor()
        showFrame(index: 0)
        let range = configuration.idlePauseRangeMs
        let delay = Double.random(in: range[0]...range[1]) * configuration.globalDurationScale
        idleTimer = scheduledTimer(milliseconds: delay) { [weak self] in
            self?.startMicroAction()
        }
    }

    private func startMicroAction() {
        guard !dragging else {
            startIdle()
            return
        }
        let entries = behavior.events.idle.microActions
        guard let name = WeightedChoice.choose(
            entries: entries,
            unitRandom: Double.random(in: 0..<1),
            allowsNoSelection: false
        ) else {
            startIdle()
            return
        }
        startAction(name)
    }

    private func startAction(_ name: String) {
        guard behavior.actions[name] != nil else { return }
        frameTimer?.invalidate()
        idleTimer?.invalidate()
        currentActionName = name
        cursor = PlaybackCursor()
        showFrame(index: 0)
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        guard let action = behavior.actions[currentActionName] else {
            startIdle()
            return
        }
        let milliseconds = max(
            16,
            action.duration(at: cursor.frameIndex) * configuration.globalDurationScale
        )
        frameTimer = scheduledTimer(milliseconds: milliseconds) { [weak self] in
            self?.advanceFrame()
        }
    }

    private func advanceFrame() {
        guard let action = behavior.actions[currentActionName] else {
            startIdle()
            return
        }
        if cursor.advance(
            frameCount: action.frames.count,
            repeatCount: action.repeatCount ?? 1,
            loops: action.loop
        ) {
            showFrame(index: cursor.frameIndex)
            scheduleNextFrame()
        } else if let outro = action.outroAction {
            startAction(outro)
        } else {
            startIdle()
        }
    }

    private func showFrame(index: Int) {
        guard let action = behavior.actions[currentActionName],
              action.frames.indices.contains(index) else {
            return
        }
        do {
            let url = try resources.frameURL(relativePath: action.frames[index])
            if let cached = imageCache[url] {
                imageView.image = cached
                return
            }
            guard let image = NSImage(contentsOf: url) else {
                throw MiaomiaoDataError.invalidValue("cannot decode image \(url.path)")
            }
            imageCache[url] = image
            imageView.image = image
        } catch {
            NSApp.presentError(error)
        }
    }

    private func scheduleSpecialCheck() {
        specialTimer?.invalidate()
        let range = behavior.events.idle.specialCheckIntervalMs
        let delay = Double.random(in: range[0]...range[1]) * configuration.globalDurationScale
        specialTimer = scheduledTimer(milliseconds: delay) { [weak self] in
            self?.performSpecialCheck()
        }
    }

    private func performSpecialCheck() {
        defer { scheduleSpecialCheck() }
        guard !dragging, currentActionName == behavior.events.idle.default else { return }
        if let name = WeightedChoice.choose(
            entries: behavior.events.idle.random,
            unitRandom: Double.random(in: 0..<1),
            allowsNoSelection: true
        ) {
            startAction(name)
        }
    }

    private func scheduledTimer(
        milliseconds: Double,
        block: @MainActor @escaping () -> Void
    ) -> Timer {
        let timer = Timer.scheduledTimer(
            withTimeInterval: milliseconds / 1_000,
            repeats: false
        ) { _ in
            MainActor.assumeIsolated {
                block()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
