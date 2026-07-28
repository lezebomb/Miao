import AppKit
import MiaomiaoCore

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onLeftDown: ((NSPoint) -> Void)?
    var onLeftDragged: ((NSPoint) -> Void)?
    var onLeftUp: ((NSPoint) -> Void)?
    var onQuit: (() -> Void)?
    let imageView = NSImageView()
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isEditable = false
        imageView.isEnabled = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
    override func mouseDown(with event: NSEvent) { onLeftDown?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onLeftDragged?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onLeftUp?(NSEvent.mouseLocation) }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: NSLocalizedString("退出妙妙", comment: "Quit Miaomiao"),
            action: #selector(quitSelected(_:)),
            keyEquivalent: ""
        )
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func quitSelected(_ sender: Any?) {
        onQuit?()
    }
}

@MainActor
final class PetWindowController {
    let window: NSWindow
    private let view: PetView
    private let animator: PetAnimationController
    private let configuration: MiaomiaoConfiguration
    private var hoverTimer: Timer?
    private var hoverArmed = true
    private var dragStart: NSPoint?
    private var lastDragPoint: NSPoint?
    private var dragMoved = false
    private(set) var followOffset = NSPoint.zero

    var isDragging: Bool { dragStart != nil }

    init(resources: RuntimeResources) {
        configuration = resources.configuration
        let size = NSSize(
            width: resources.behavior.cell.width * resources.configuration.windowScale,
            height: resources.behavior.cell.height * resources.configuration.windowScale
        )
        let panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "妙妙"
        window = panel

        view = PetView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
        animator = PetAnimationController(imageView: view.imageView, resources: resources)
        wireInteractions()
    }

    func start() {
        placeAtDefaultLocation()
        animator.start()
        show()
    }

    func stop() {
        hoverTimer?.invalidate()
        animator.stop()
    }

    func show() {
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func placeRelative(to target: NSRect) {
        guard !isDragging else { return }
        let options = configuration.codexWindow
        var origin: NSPoint
        if options.placement == "inside-bottom-right" {
            origin = NSPoint(
                x: target.maxX - window.frame.width - options.edgePadding + options.offsetX,
                y: target.minY + options.edgePadding + options.offsetY
            )
        } else {
            origin = NSPoint(
                x: target.maxX + options.offsetX,
                y: target.minY + options.offsetY
            )
            let screen = ScreenGeometry.screen(containing: target)
            if origin.x + window.frame.width > screen.visibleFrame.maxX {
                origin.x = target.maxX - window.frame.width - options.edgePadding + options.offsetX
            }
        }
        origin.x += followOffset.x
        origin.y += followOffset.y
        window.setFrameOrigin(ScreenGeometry.clampedOrigin(origin, size: window.frame.size, near: target))
    }

    private func wireInteractions() {
        view.onMouseEntered = { [weak self] in self?.mouseEntered() }
        view.onMouseExited = { [weak self] in self?.mouseExited() }
        view.onLeftDown = { [weak self] point in self?.leftDown(at: point) }
        view.onLeftDragged = { [weak self] point in self?.leftDragged(to: point) }
        view.onLeftUp = { [weak self] point in self?.leftUp(at: point) }
        view.onQuit = { NSApp.terminate(nil) }
    }

    private func mouseEntered() {
        guard hoverArmed, !isDragging else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.hoverDwellMs / 1_000,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.hoverArmed, !self.isDragging else { return }
                self.hoverArmed = false
                self.animator.triggerPetAction()
            }
        }
    }

    private func mouseExited() {
        hoverTimer?.invalidate()
        if !isDragging {
            hoverArmed = true
        }
    }

    private func leftDown(at point: NSPoint) {
        hoverTimer?.invalidate()
        dragStart = point
        lastDragPoint = point
        dragMoved = false
        animator.setDragging(true)
    }

    private func leftDragged(to point: NSPoint) {
        guard let start = dragStart, let previous = lastDragPoint else { return }
        let incremental = NSPoint(x: point.x - previous.x, y: point.y - previous.y)
        let total = NSPoint(x: point.x - start.x, y: point.y - start.y)
        guard abs(total.x) + abs(total.y) >= 2 else { return }
        dragMoved = true
        var origin = window.frame.origin
        origin.x += incremental.x
        origin.y += incremental.y
        origin = ScreenGeometry.clampedOrigin(
            origin,
            size: window.frame.size,
            near: NSRect(origin: point, size: .zero)
        )
        let appliedDelta = NSPoint(
            x: origin.x - window.frame.origin.x,
            y: origin.y - window.frame.origin.y
        )
        window.setFrameOrigin(origin)
        followOffset.x += appliedDelta.x
        followOffset.y += appliedDelta.y
        lastDragPoint = point

        let direction = InteractionLogic.dragDirection(
            deltaX: total.x,
            deltaY: total.y,
            threshold: configuration.drag.horizontalThresholdPx,
            dominanceRatio: configuration.drag.horizontalDominanceRatio
        )
        animator.startDragAction(direction: direction)
    }

    private func leftUp(at point: NSPoint) {
        guard dragStart != nil else { return }
        dragStart = nil
        lastDragPoint = nil
        animator.setDragging(false)
        animator.endDrag()
        if !dragMoved {
            animator.triggerPetAction()
        }
    }

    private func placeAtDefaultLocation() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.maxX - window.frame.width - 24,
            y: visible.minY + 24
        )
        window.setFrameOrigin(origin)
    }
}

enum ScreenGeometry {
    static func screen(containing rect: NSRect) -> NSScreen {
        NSScreen.screens.max {
            $0.frame.intersection(rect).width * $0.frame.intersection(rect).height <
            $1.frame.intersection(rect).width * $1.frame.intersection(rect).height
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func clampedOrigin(_ origin: NSPoint, size: NSSize, near rect: NSRect) -> NSPoint {
        let visible = screen(containing: rect).visibleFrame
        return NSPoint(
            x: min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
    }
}
