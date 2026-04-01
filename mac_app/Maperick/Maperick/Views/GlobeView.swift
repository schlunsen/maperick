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

        if allowsInteraction {
            view.allowsCameraControl = true
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.defaultCameraController.inertiaEnabled = true
            // Disable zoom so scroll doesn't move the globe
            view.defaultCameraController.minimumVerticalAngle = -90
            view.defaultCameraController.maximumVerticalAngle = 90
            view.defaultCameraController.delegate = context.coordinator
            context.coordinator.scene = scene
            context.coordinator.scnView = view
        }

        return view
    }

    func updateNSView(_ nsView: GlobeSceneView, context: Context) {
        // Don't force-restart auto-rotate — the GlobeScene manages its own rotation timing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func startAutoRotation(in scene: GlobeScene) {
        guard let globe = scene.rootNode.childNode(withName: "globe", recursively: false) else { return }
        globe.runAction(
            SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0.3, z: 0, duration: 10.0)),
            forKey: "autoRotate"
        )
    }

    class Coordinator: NSObject, SCNCameraControllerDelegate {
        var scene: GlobeScene?
        weak var scnView: GlobeSceneView?
        var userIsInteracting = false

        func cameraInertiaWillStart(for cameraController: SCNCameraController) {
            userIsInteracting = true
            scene?.rootNode.childNode(withName: "globe", recursively: false)?
                .removeAction(forKey: "autoRotate")
        }

        func cameraInertiaDidEnd(for cameraController: SCNCameraController) {
            userIsInteracting = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, !self.userIsInteracting else { return }
                self.scene?.rootNode.childNode(withName: "globe", recursively: false)?
                    .runAction(
                        SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0.3, z: 0, duration: 10.0)),
                        forKey: "autoRotate"
                    )
            }
        }
    }
}

/// Custom SCNView that uses scroll wheel for zoom and allows drag rotation
class GlobeSceneView: SCNView {
    private let minZoom: CGFloat = 7.0
    private let maxZoom: CGFloat = 20.0
    private var cachedCamera: SCNNode?

    /// Finds and caches the camera node on first access
    private func cameraNode() -> SCNNode? {
        if let cached = cachedCamera { return cached }
        let node = scene?.rootNode.childNode(withName: "mainCamera", recursively: true)
        cachedCamera = node
        return node
    }

    override func scrollWheel(with event: NSEvent) {
        guard let cameraNode = cameraNode() else { return }
        let delta = CGFloat(event.scrollingDeltaY) * 0.05
        let currentZ = cameraNode.position.z
        let newZ = max(minZoom, min(maxZoom, currentZ + delta))
        cameraNode.position.z = newZ
    }

    override func magnify(with event: NSEvent) {
        guard let cameraNode = cameraNode() else { return }
        let delta = -event.magnification * 3.0
        let currentZ = cameraNode.position.z
        let newZ = max(minZoom, min(maxZoom, currentZ + delta))
        cameraNode.position.z = newZ
    }
}
