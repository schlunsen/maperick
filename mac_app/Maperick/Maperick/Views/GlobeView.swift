import SwiftUI
import SceneKit

struct GlobeView: NSViewRepresentable {
    var scene: GlobeScene
    var allowsInteraction: Bool = false
    var autoRotates: Bool = true

    func makeNSView(context: Context) -> GlobeSceneView {
        let view = GlobeSceneView()
        view.scene = scene
        view.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1.0)
        view.antialiasingMode = .multisampling2X

        // Do NOT use allowsCameraControl — it fights with our custom scroll zoom.
        // Instead we handle drag rotation manually in GlobeSceneView.
        view.allowsCameraControl = false

        if allowsInteraction {
            view.isInteractionEnabled = true
            view.globeScene = scene
        }

        return view
    }

    func updateNSView(_ nsView: GlobeSceneView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {}
}

/// Custom SCNView that handles scroll-zoom and drag-rotate without SceneKit's camera controller
class GlobeSceneView: SCNView {
    private let minZoom: CGFloat = 7.0
    private let maxZoom: CGFloat = 20.0
    private var cachedCamera: SCNNode?
    private var targetZoom: CGFloat = 13.0
    private var isAnimatingZoom = false

    // Drag rotation state
    var isInteractionEnabled = false
    weak var globeScene: GlobeScene?
    private var lastDragPoint: NSPoint?
    private var isDragging = false
    private var dragInertiaX: CGFloat = 0
    private var dragInertiaY: CGFloat = 0
    private var inertiaTimer: Timer?

    private var globeNode: SCNNode? {
        scene?.rootNode.childNode(withName: "globe", recursively: false)
    }

    /// Finds and caches the camera node on first access
    private func cameraNode() -> SCNNode? {
        if let cached = cachedCamera { return cached }
        let node = scene?.rootNode.childNode(withName: "mainCamera", recursively: true)
        cachedCamera = node
        if let node = node {
            targetZoom = CGFloat(node.position.z)
        }
        return node
    }

    // MARK: - Scroll Zoom

    override func scrollWheel(with event: NSEvent) {
        guard cameraNode() != nil else { return }

        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            // Trackpad: smooth, use raw pixels
            delta = -event.scrollingDeltaY * 0.02
        } else {
            // Mouse wheel: discrete steps, bigger multiplier
            delta = -event.scrollingDeltaY * 1.0
        }

        guard abs(delta) > 0.001 else { return }

        targetZoom = max(minZoom, min(maxZoom, targetZoom + delta))
        startZoomAnimation()
    }

    override func magnify(with event: NSEvent) {
        guard cameraNode() != nil else { return }
        let delta = -event.magnification * 5.0
        targetZoom = max(minZoom, min(maxZoom, targetZoom + delta))
        startZoomAnimation()
    }

    private func startZoomAnimation() {
        guard !isAnimatingZoom else { return }
        isAnimatingZoom = true
        animateZoom()
    }

    private func animateZoom() {
        guard let camera = cachedCamera else {
            isAnimatingZoom = false
            return
        }

        let currentZ = CGFloat(camera.position.z)
        let diff = targetZoom - currentZ

        if abs(diff) < 0.005 {
            camera.position.z = targetZoom
            isAnimatingZoom = false
            return
        }

        // Smooth exponential lerp
        let newZ = currentZ + diff * 0.18
        camera.position.z = newZ

        DispatchQueue.main.async { [weak self] in
            self?.animateZoom()
        }
    }

    // MARK: - Drag Rotation

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { super.mouseDown(with: event); return }
        lastDragPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
        inertiaTimer?.invalidate()
        dragInertiaX = 0
        dragInertiaY = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled, isDragging, let lastPoint = lastDragPoint else {
            super.mouseDragged(with: event)
            return
        }
        guard let globe = globeNode else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let dx = currentPoint.x - lastPoint.x
        let dy = currentPoint.y - lastPoint.y

        // Rotate globe based on drag delta
        let sensitivity: CGFloat = 0.005
        globe.eulerAngles.y += dx * sensitivity
        globe.eulerAngles.x -= dy * sensitivity

        // Clamp vertical rotation to avoid flipping
        globe.eulerAngles.x = max(-CGFloat.pi / 2.5, min(CGFloat.pi / 2.5, globe.eulerAngles.x))

        // Track velocity for inertia
        dragInertiaX = dx * sensitivity
        dragInertiaY = -dy * sensitivity

        lastDragPoint = currentPoint
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractionEnabled, isDragging else { super.mouseUp(with: event); return }
        isDragging = false
        lastDragPoint = nil

        // Start inertia if there was velocity
        if abs(dragInertiaX) > 0.0005 || abs(dragInertiaY) > 0.0005 {
            startInertia()
        }
    }

    private func startInertia() {
        inertiaTimer?.invalidate()
        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let globe = self.globeNode else {
                timer.invalidate()
                return
            }

            globe.eulerAngles.y += self.dragInertiaX
            globe.eulerAngles.x += self.dragInertiaY
            globe.eulerAngles.x = max(-CGFloat.pi / 2.5, min(CGFloat.pi / 2.5, globe.eulerAngles.x))

            // Decay
            self.dragInertiaX *= 0.95
            self.dragInertiaY *= 0.95

            if abs(self.dragInertiaX) < 0.00005 && abs(self.dragInertiaY) < 0.00005 {
                timer.invalidate()
            }
        }
    }
}
