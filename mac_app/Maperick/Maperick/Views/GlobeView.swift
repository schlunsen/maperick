import SwiftUI
import SceneKit

struct GlobeView: NSViewRepresentable {
    var scene: GlobeScene
    var allowsInteraction: Bool = false

    func makeNSView(context: Context) -> GlobeSceneView {
        // Force Metal rendering API for GPU-driven pipeline
        let view = GlobeSceneView(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
            SCNView.Option.preferLowPowerDevice.rawValue: false
        ])
        view.scene = scene
        view.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1.0)
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = true

        view.isJitteringEnabled = false
        view.isTemporalAntialiasingEnabled = false

        // Do NOT use allowsCameraControl — it fights with our custom scroll zoom.
        view.allowsCameraControl = false

        if allowsInteraction {
            view.isInteractionEnabled = true
            view.globeScene = scene
        }

        // Use SceneKit's own render loop for inertia (zero-latency, vsync'd)
        view.delegate = view

        view.setupVisibilityObservers()
        return view
    }

    func updateNSView(_ nsView: GlobeSceneView, context: Context) {}
}

/// Custom SCNView that handles scroll-zoom and drag-rotate without SceneKit's camera controller.
/// Inertia runs inside SceneKit's render loop via SCNSceneRendererDelegate for zero-latency updates.
class GlobeSceneView: SCNView, SCNSceneRendererDelegate {
    private let minZoom: CGFloat = 7.0
    private let maxZoom: CGFloat = 20.0
    private var cachedCamera: SCNNode?
    private var targetZoom: CGFloat = 13.0
    private var isAnimatingZoom = false

    // Drag rotation state
    var isInteractionEnabled = false
    weak var globeScene: GlobeScene?
    private var lastDragPoint: NSPoint?
    private var lastDragTime: CFTimeInterval = 0
    private var isDragging = false
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0
    private var isCoasting = false
    private var lastRenderTime: CFTimeInterval = 0
    private var idleFpsTimer: Timer?
    private var visibilityObservers: [Any] = []

    private var cachedGlobe: SCNNode?
    private func globeNode() -> SCNNode? {
        if let cached = cachedGlobe { return cached }
        let node = scene?.rootNode.childNode(withName: "globe", recursively: false)
        cachedGlobe = node
        return node
    }

    private func cameraNode() -> SCNNode? {
        if let cached = cachedCamera { return cached }
        let node = scene?.rootNode.childNode(withName: "mainCamera", recursively: true)
        cachedCamera = node
        if let node = node {
            targetZoom = CGFloat(node.position.z)
        }
        return node
    }

    // MARK: - Frame Rate Management

    /// Boost to 60fps for interaction, drop back to 30fps when idle
    private func boostFrameRate() {
        preferredFramesPerSecond = 60
        idleFpsTimer?.invalidate()
    }

    private func scheduleIdleFrameRate() {
        idleFpsTimer?.invalidate()
        idleFpsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.preferredFramesPerSecond = 30
        }
    }

    // MARK: - Scroll Zoom

    override func scrollWheel(with event: NSEvent) {
        guard cameraNode() != nil else { return }

        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = -event.scrollingDeltaY * 0.02
        } else {
            delta = -event.scrollingDeltaY * 1.0
        }
        guard abs(delta) > 0.001 else { return }

        targetZoom = max(minZoom, min(maxZoom, targetZoom + delta))
        isAnimatingZoom = true
        boostFrameRate()
    }

    override func magnify(with event: NSEvent) {
        guard cameraNode() != nil else { return }
        let delta = -event.magnification * 5.0
        targetZoom = max(minZoom, min(maxZoom, targetZoom + delta))
        isAnimatingZoom = true
        boostFrameRate()
    }

    // MARK: - Visibility & Power Management

    private func setRenderingActive(_ active: Bool) {
        scene?.isPaused = !active
        rendersContinuously = active
        preferredFramesPerSecond = active ? 30 : 0
    }

    func setupVisibilityObservers() {
        let nc = NotificationCenter.default

        let resign = nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setRenderingActive(false)
        }
        let activate = nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setRenderingActive(true)
        }
        let hide = nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setRenderingActive(false)
        }
        let unhide = nc.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setRenderingActive(true)
        }
        let occlude = nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] notification in
            guard let view = self, let window = notification.object as? NSWindow, window == view.window else { return }
            view.setRenderingActive(window.occlusionState.contains(.visible))
        }

        visibilityObservers = [resign, activate, hide, unhide, occlude]
    }

    deinit {
        idleFpsTimer?.invalidate()
        for observer in visibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Drag Rotation

    /// Sensitivity scales with zoom level for natural feel
    private var dragSensitivity: CGFloat {
        let zoom = cachedCamera?.position.z ?? 13.0
        return CGFloat(zoom) * 0.0004
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { super.mouseDown(with: event); return }
        lastDragPoint = convert(event.locationInWindow, from: nil)
        lastDragTime = CACurrentMediaTime()
        isDragging = true
        isCoasting = false
        velocityX = 0
        velocityY = 0
        boostFrameRate()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled, isDragging, let lastPoint = lastDragPoint else {
            super.mouseDragged(with: event)
            return
        }
        guard let globe = globeNode() else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let now = CACurrentMediaTime()
        let dt = max(now - lastDragTime, 0.001)

        let dx = currentPoint.x - lastPoint.x
        let dy = currentPoint.y - lastPoint.y
        let sens = dragSensitivity

        // Apply rotation immediately — this is the 1:1 tracking part
        globe.eulerAngles.y += dx * sens
        globe.eulerAngles.x -= dy * sens
        globe.eulerAngles.x = max(-CGFloat.pi / 2.5, min(CGFloat.pi / 2.5, globe.eulerAngles.x))

        // Build smoothed velocity for inertia (exponential moving average)
        let instantVX = dx * sens / CGFloat(dt)
        let instantVY = -dy * sens / CGFloat(dt)
        let smoothing: CGFloat = 0.25
        velocityX = velocityX * (1.0 - smoothing) + instantVX * smoothing
        velocityY = velocityY * (1.0 - smoothing) + instantVY * smoothing

        lastDragPoint = currentPoint
        lastDragTime = now
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractionEnabled, isDragging else { super.mouseUp(with: event); return }
        isDragging = false
        lastDragPoint = nil

        // If the finger paused before releasing, don't throw
        let timeSinceLastMove = CACurrentMediaTime() - lastDragTime
        if timeSinceLastMove > 0.08 {
            velocityX = 0
            velocityY = 0
            scheduleIdleFrameRate()
            return
        }

        // Start coasting if there's meaningful velocity
        if abs(velocityX) > 0.05 || abs(velocityY) > 0.05 {
            isCoasting = true
            lastRenderTime = CACurrentMediaTime()
        } else {
            scheduleIdleFrameRate()
        }
    }

    // MARK: - SCNSceneRendererDelegate (inertia + zoom inside the render loop)

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // --- Smooth zoom ---
        if isAnimatingZoom, let camera = cachedCamera {
            let currentZ = CGFloat(camera.position.z)
            let diff = targetZoom - currentZ
            if abs(diff) < 0.005 {
                camera.position.z = targetZoom
                isAnimatingZoom = false
                if !isDragging && !isCoasting { scheduleIdleFrameRate() }
            } else {
                camera.position.z = currentZ + diff * 0.18
            }
        }

        // --- Inertia coasting ---
        guard isCoasting, let globe = globeNode() else { return }

        let now = CACurrentMediaTime()
        let dt = lastRenderTime > 0 ? min(now - lastRenderTime, 1.0 / 15.0) : 1.0 / 60.0
        lastRenderTime = now

        // Apply velocity (rad/s × seconds = radians)
        globe.eulerAngles.y += velocityX * CGFloat(dt)
        globe.eulerAngles.x += velocityY * CGFloat(dt)
        globe.eulerAngles.x = max(-CGFloat.pi / 2.5, min(CGFloat.pi / 2.5, globe.eulerAngles.x))

        // Smooth exponential decay: loses ~95% over 2 seconds
        let decay: CGFloat = pow(0.05, CGFloat(dt) / 2.0)
        velocityX *= decay
        velocityY *= decay

        if abs(velocityX) < 0.01 && abs(velocityY) < 0.01 {
            velocityX = 0
            velocityY = 0
            isCoasting = false
            scheduleIdleFrameRate()
        }
    }
}
