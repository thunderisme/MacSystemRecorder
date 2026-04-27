import AppKit

@MainActor
final class CropSelectionSession {
    private var window: NSWindow?
    private var selection: CGRect?

    static func selectArea(on screen: NSScreen) -> CGRect? {
        let session = CropSelectionSession()
        return session.run(on: screen)
    }

    private func run(on screen: NSScreen) -> CGRect? {
        let selectionView = CropSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        selectionView.onComplete = { [weak self] rect in
            self?.selection = rect
            NSApp.stopModal()
        }
        selectionView.onCancel = { [weak self] in
            self?.selection = nil
            NSApp.stopModal()
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = selectionView
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSCursor.crosshair.set()
        NSApp.runModal(for: window)
        NSCursor.arrow.set()

        window.orderOut(nil)
        self.window = nil
        return selection
    }
}

final class CropSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        if let rect = selectionRect {
            NSColor.clear.setFill()
            rect.fill(using: .clear)

            NSColor.systemBlue.withAlphaComponent(0.22).setFill()
            rect.fill()

            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            NSColor.systemBlue.setStroke()
            path.stroke()

            drawSizeLabel(for: rect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 32, rect.height >= 32 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).intersection(bounds)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let label = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        let size = label.size(withAttributes: attributes)
        let origin = CGPoint(x: rect.minX + 8, y: max(rect.minY + 8, rect.maxY - size.height - 8))
        label.draw(at: origin, withAttributes: attributes)
    }
}
