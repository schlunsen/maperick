import SceneKit
import simd

class GlobeScene: SCNScene {
    // MARK: - Cached Color Constants
    private static let lowColor = NSColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
    private static let medColor = NSColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0)
    private static let highColor = NSColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)

    private var globeNode: SCNNode!
    private var connectionPins: [String: SCNNode] = [:]
    private var arcBeams: [String: SCNNode] = [:]
    private var previousIPs: Set<String> = []
    private var homeMarkerNode: SCNNode?
    private var userLatitude: Double = 0
    private var userLongitude: Double = 0
    private var hasUserLocation = false

    // Follow mode state
    private(set) var isFollowMode = false
    private var followTimer: Timer?
    private var activityBuffer: [(latitude: Double, longitude: Double, weight: Double, timestamp: Date)] = []
    private var currentFollowTarget: (latitude: Double, longitude: Double)?
    private var isAnimatingFollow = false

    let globeRadius: CGFloat = 5.0

    override init() {
        super.init()
        setupScene()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        followTimer?.invalidate()
    }

    // MARK: - Scene Setup

    private func setupScene() {
        background.contents = NSColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1.0)

        globeNode = createGlobeNode()
        rootNode.addChildNode(globeNode)

        let atmosphere = createAtmosphereNode()
        rootNode.addChildNode(atmosphere)

        let stars = createStarField()
        rootNode.addChildNode(stars)

        setupLighting()
        setupCamera()

    }

    // MARK: - Globe Node

    private func createGlobeNode() -> SCNNode {
        let sphere = SCNSphere(radius: globeRadius)
        sphere.segmentCount = 64

        let material = SCNMaterial()

        // Use real NASA Blue Marble texture from app bundle
        if let dayTexture = loadBundleImage("earth_daymap") {
            material.diffuse.contents = dayTexture
        } else {
            // Fallback: solid blue
            material.diffuse.contents = NSColor(red: 0.05, green: 0.12, blue: 0.25, alpha: 1.0)
        }

        // Use NASA night lights as emission map (city lights glow)
        if let nightTexture = loadBundleImage("earth_night") {
            material.emission.contents = nightTexture
            material.emission.intensity = 0.6
        }

        // Glossy specular highlights — ocean reflections
        material.specular.contents = NSColor(white: 0.6, alpha: 1.0)
        material.shininess = 40
        material.fresnelExponent = 3.0
        material.reflective.contents = NSColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 1.0)
        material.reflective.intensity = 0.3
        material.locksAmbientWithDiffuse = false

        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.name = "globe"
        return node
    }

    /// Load an image from the app bundle (tries jpg then png)
    private func loadBundleImage(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    // MARK: - Atmosphere

    private func createAtmosphereNode() -> SCNNode {
        let sphere = SCNSphere(radius: globeRadius * 1.025)
        sphere.segmentCount = 48
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.clear
        material.emission.contents = NSColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.15)
        material.transparent.contents = NSColor(white: 1.0, alpha: 0.08)
        material.blendMode = .add
        material.isDoubleSided = true
        material.lightingModel = .constant
        material.fresnelExponent = 3.0
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.name = "atmosphere"
        return node
    }

    // MARK: - Stars

    private func createStarField() -> SCNNode {
        let count = 1200
        var positions: [Float] = []
        var colors: [Float] = []
        for _ in 0..<count {
            let theta = Float.random(in: 0...(.pi * 2))
            let phi = Float.random(in: 0...(.pi))
            let r: Float = 50
            positions.append(r * Foundation.sin(phi) * Foundation.cos(theta))
            positions.append(r * Foundation.sin(phi) * Foundation.sin(theta))
            positions.append(r * Foundation.cos(phi))
            let brightness = Float.random(in: 0.3...1.0)
            colors.append(brightness)
            colors.append(brightness)
            colors.append(brightness * 1.1)
            colors.append(1.0)
        }
        let source = SCNGeometrySource(data: Data(bytes: positions, count: positions.count * 4),
                                       semantic: .vertex, vectorCount: count, usesFloatComponents: true,
                                       componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let colorSource = SCNGeometrySource(data: Data(bytes: colors, count: colors.count * 4),
                                            semantic: .color, vectorCount: count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        var indices = Array<UInt16>((0..<count).map { UInt16($0) })
        let indexData = Data(bytes: &indices, count: count * MemoryLayout<UInt16>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .point, primitiveCount: count, bytesPerIndex: MemoryLayout<UInt16>.size)
        let geo = SCNGeometry(sources: [source, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geo.materials = [material]
        return SCNNode(geometry: geo)
    }

    // MARK: - Lighting

    private func setupLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.35, alpha: 1.0)
        rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = NSColor(white: 1.0, alpha: 1.0)
        sun.light?.intensity = 1200
        sun.position = SCNVector3(10, 8, 12)
        sun.look(at: SCNVector3(0, 0, 0))
        rootNode.addChildNode(sun)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = NSColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0)
        fill.light?.intensity = 400
        fill.position = SCNVector3(-10, -5, -10)
        fill.look(at: SCNVector3(0, 0, 0))
        rootNode.addChildNode(fill)
    }

    // MARK: - Camera

    private func setupCamera() {
        let cameraNode = SCNNode()
        cameraNode.name = "mainCamera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 45
        cameraNode.camera?.zFar = 200

        // Start zoomed out, then drift in very close
        let startZ: CGFloat = 14
        let endZ: CGFloat = 8.5
        let startY: CGFloat = 1.5
        let endY: CGFloat = 0.8

        cameraNode.position = SCNVector3(0, startY, startZ)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        rootNode.addChildNode(cameraNode)

        // Slow cinematic zoom-in over 3 seconds
        let zoomDuration: TimeInterval = 3.0
        let zoomIn = SCNAction.customAction(duration: zoomDuration) { node, elapsed in
            let t = Float(elapsed / CGFloat(zoomDuration))
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            let z = Float(startZ) + (Float(endZ) - Float(startZ)) * eased
            let y = Float(startY) + (Float(endY) - Float(startY)) * eased
            node.position = SCNVector3(0, CGFloat(y), CGFloat(z))
            node.look(at: SCNVector3(0, 0, 0))
        }
        cameraNode.runAction(zoomIn)
    }

    /// Smoothly zoom the camera to a given distance (for big window vs popover)
    func zoomCamera(toZ z: CGFloat, duration: TimeInterval = 1.5) {
        guard let cameraNode = rootNode.childNode(withName: "mainCamera", recursively: true) else { return }
        let startZ = Float(cameraNode.position.z)
        let startY = Float(cameraNode.position.y)
        let endZ = Float(z)
        let endY = Float(z * 0.1) // slight Y adjustment
        let action = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = Float(elapsed / CGFloat(duration))
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            node.position.z = CGFloat(startZ + (endZ - startZ) * eased)
            node.position.y = CGFloat(startY + (endY - startY) * eased)
            node.look(at: SCNVector3(0, 0, 0))
        }
        cameraNode.runAction(action, forKey: "zoomCamera")
    }

    // MARK: - User Location

    /// Set the user's home location on the globe
    func setUserLocation(latitude: Double, longitude: Double) {
        userLatitude = latitude
        userLongitude = longitude
        hasUserLocation = true
        createHomeMarker()

        // Rotate globe so user's location faces the camera on startup
        rotateToFaceUser()
    }

    /// Rotate the globe so the user's location faces the camera (+Z direction)
    private func rotateToFaceUser() {
        guard hasUserLocation else { return }

        // Stop ALL actions to prevent interference
        globeNode.removeAllActions()

        // Match the same math as smoothRotateToFace (follow mode)
        let targetY = CGFloat(-userLongitude * .pi / 180.0)
        let targetX = CGFloat(userLatitude * .pi / 180.0) * 0.6

        // Reset all euler angles at once
        globeNode.eulerAngles = SCNVector3(x: targetX, y: targetY, z: 0)

        print("[Maperick] Rotating globe to face user: lat=\(userLatitude) lon=\(userLongitude) → eulerY=\(targetY) eulerX=\(targetX)")

    }

    /// Creates a distinct pulsing beacon at the user's location — hollow rings on the surface
    private func createHomeMarker() {
        homeMarkerNode?.removeFromParentNode()

        let position = latLonToPosition(latitude: userLatitude, longitude: userLongitude)
        let homeColor = NSColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        let direction = position.normalized()
        let surfaceNormal = simd_float3(Float(direction.x), Float(direction.y), Float(direction.z))

        let node = SCNNode()
        node.position = position
        node.name = "homeMarker"

        // Small solid center dot (tiny cylinder flush on surface)
        let dot = SCNCylinder(radius: 0.05, height: 0.002)
        dot.radialSegmentCount = 16
        let dotMat = SCNMaterial()
        dotMat.diffuse.contents = NSColor.white
        dotMat.emission.contents = homeColor
        dotMat.emission.intensity = 1.0
        dotMat.lightingModel = .constant
        dotMat.isDoubleSided = true
        dot.materials = [dotMat]
        let dotNode = SCNNode(geometry: dot)
        dotNode.simdOrientation = orientToSurface(normal: surfaceNormal)
        node.addChildNode(dotNode)

        // Expanding ripple rings for home marker (staggered)
        addHomeRing(to: node, color: homeColor, direction: direction, delay: 0)
        addHomeRing(to: node, color: homeColor, direction: direction, delay: 1.2)
        addHomeRing(to: node, color: homeColor, direction: direction, delay: 2.4)

        globeNode.addChildNode(node)
        homeMarkerNode = node
    }

    // MARK: - Follow Mode

    /// Toggle follow mode on/off
    func setFollowMode(_ enabled: Bool) {
        isFollowMode = enabled

        if enabled {
            // Stop idle auto-rotation
            globeNode.removeAction(forKey: "autoRotate")

            // Start the 30-second batch timer
            followTimer?.invalidate()
            followTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.evaluateFollowTarget()
            }
            // Also do an immediate evaluation
            evaluateFollowTarget()
        } else {
            // Stop follow timer
            followTimer?.invalidate()
            followTimer = nil
            activityBuffer.removeAll()
            currentFollowTarget = nil

            // Stopped follow mode
        }
    }

    /// Record activity for follow mode (called from updateConnections)
    private func recordActivity(servers: [ServerInfo]) {
        guard isFollowMode else { return }
        let now = Date()
        for server in servers {
            guard server.latitude != 0 || server.longitude != 0 else { continue }
            activityBuffer.append((
                latitude: server.latitude,
                longitude: server.longitude,
                weight: Double(server.connectionCount),
                timestamp: now
            ))
        }
        // Trim old entries (keep last 60 seconds for smoothing)
        let cutoff = now.addingTimeInterval(-60)
        activityBuffer.removeAll { $0.timestamp < cutoff }
    }

    /// Every 30s, compute weighted centroid of recent traffic and smoothly rotate to it
    private func evaluateFollowTarget() {
        guard isFollowMode, !activityBuffer.isEmpty else { return }

        // Compute weighted centroid in 3D (avoids lat/lon wraparound issues)
        var wx: Double = 0, wy: Double = 0, wz: Double = 0
        var totalWeight: Double = 0

        // Include user's own location with moderate weight if available
        if hasUserLocation {
            let userW = 2.0
            let latRad = userLatitude * .pi / 180.0
            let lonRad = userLongitude * .pi / 180.0
            wx += userW * cos(latRad) * cos(lonRad)
            wy += userW * sin(latRad)
            wz += userW * cos(latRad) * sin(lonRad)
            totalWeight += userW
        }

        for entry in activityBuffer {
            let latRad = entry.latitude * .pi / 180.0
            let lonRad = entry.longitude * .pi / 180.0
            let w = entry.weight
            wx += w * cos(latRad) * cos(lonRad)
            wy += w * sin(latRad)
            wz += w * cos(latRad) * sin(lonRad)
            totalWeight += w
        }

        guard totalWeight > 0 else { return }
        wx /= totalWeight
        wy /= totalWeight
        wz /= totalWeight

        // Convert back to lat/lon
        let targetLat = atan2(wy, sqrt(wx * wx + wz * wz)) * 180.0 / .pi
        let targetLon = atan2(wz, wx) * 180.0 / .pi

        // Check if the target has moved significantly (> 5 degrees) to avoid micro-jitter
        if let current = currentFollowTarget {
            let dLat = abs(targetLat - current.latitude)
            let dLon = abs(targetLon - current.longitude)
            if dLat < 5.0 && dLon < 5.0 {
                return // Not enough change, skip rotation
            }
        }

        currentFollowTarget = (latitude: targetLat, longitude: targetLon)
        smoothRotateToFace(latitude: targetLat, longitude: targetLon)
    }

    /// Smoothly rotate the globe so the given lat/lon faces the camera
    private func smoothRotateToFace(latitude: Double, longitude: Double) {
        guard !isAnimatingFollow else { return }
        isAnimatingFollow = true

        // The camera is at (0, ~1, ~8.5) looking at the origin.
        // A point at longitude L is at angle +L from +Z.
        // To rotate it to face the camera (+Z), set globe Y rotation = -L.

        let targetYRotation = CGFloat(-longitude * .pi / 180.0)
        // Slight X tilt to bring latitude into view (camera is slightly above center)
        let targetXRotation = CGFloat(latitude * .pi / 180.0) * 0.3

        let currentY = globeNode.eulerAngles.y
        let currentX = globeNode.eulerAngles.x

        // Compute shortest rotation path for Y (handle wraparound)
        var deltaY = targetYRotation - CGFloat(currentY)
        while deltaY > .pi { deltaY -= 2 * .pi }
        while deltaY < -.pi { deltaY += 2 * .pi }

        let finalY = CGFloat(currentY) + deltaY
        let finalX = targetXRotation

        // Pre-compute as Float to avoid type-checker issues
        let startY = Float(currentY)
        let startX = Float(currentX)
        let dY = Float(deltaY)
        let endX = Float(finalX)
        let dX = endX - startX

        // Animate over 2 seconds with ease-in-out
        let duration: TimeInterval = 2.0
        let animateAction = SCNAction.customAction(duration: duration) { [weak self] node, elapsed in
            let t = Float(elapsed / CGFloat(duration))
            // Smooth ease-in-out curve
            let eased: Float
            if t < 0.5 {
                eased = 4.0 * t * t * t
            } else {
                let p = -2.0 * t + 2.0
                eased = 1.0 - (p * p * p) / 2.0
            }

            node.eulerAngles.y = CGFloat(startY + dY * eased)
            node.eulerAngles.x = CGFloat(startX + dX * eased)

            if t >= 1.0 {
                self?.isAnimatingFollow = false
            }
        }

        globeNode.runAction(animateAction, forKey: "followRotation")
    }

    // MARK: - Connection Pin Updates

    func updateConnections(servers: [ServerInfo]) {
        // Record activity for follow mode
        recordActivity(servers: servers)
        let currentIPs = Set(servers.map { $0.ip })
        let newIPs = currentIPs.subtracting(previousIPs)

        // Remove old pins; fade out arcs gracefully
        for ip in previousIPs.subtracting(currentIPs) {
            if let pinNode = connectionPins[ip] {
                pinNode.removeFromParentNode()
                connectionPins.removeValue(forKey: ip)
            }
            if let arcNode = arcBeams[ip] {
                arcBeams.removeValue(forKey: ip)
                // Fade out over 1.5s then remove
                let fadeOut = SCNAction.fadeOut(duration: 1.5)
                let remove = SCNAction.removeFromParentNode()
                arcNode.runAction(SCNAction.sequence([fadeOut, remove]))
            }
        }

        for server in servers {
            guard server.latitude != 0 || server.longitude != 0 else { continue }

            if let existingPin = connectionPins[server.ip] {
                updatePinSize(existingPin, count: server.connectionCount)
            } else {
                let pin = createPinNode(for: server)
                globeNode.addChildNode(pin)
                connectionPins[server.ip] = pin

                // Add arc beam from user location to this server
                if hasUserLocation {
                    let arc = createArcBeam(
                        fromLat: userLatitude, fromLon: userLongitude,
                        toLat: server.latitude, toLon: server.longitude,
                        color: colorForIntensity(server.intensityColor)
                    )
                    globeNode.addChildNode(arc)
                    arcBeams[server.ip] = arc
                }
            }

            if newIPs.contains(server.ip) {
                addRipple(at: server.latitude, longitude: server.longitude, color: server.intensityColor)
            }
        }
        previousIPs = currentIPs
    }

    private func createPinNode(for server: ServerInfo) -> SCNNode {
        let color = colorForIntensity(server.intensityColor)
        let position = latLonToPosition(latitude: server.latitude, longitude: server.longitude)
        let direction = position.normalized()
        let surfaceNormal = simd_float3(Float(direction.x), Float(direction.y), Float(direction.z))

        let node = SCNNode()
        node.position = position

        // Tiny solid center dot flush on surface
        let dot = SCNCylinder(radius: 0.02, height: 0.001)
        dot.radialSegmentCount = 12
        let dotMat = SCNMaterial()
        dotMat.diffuse.contents = color
        dotMat.emission.contents = color
        dotMat.emission.intensity = 0.8
        dotMat.lightingModel = .constant
        dotMat.isDoubleSided = true
        dot.materials = [dotMat]
        let dotNode = SCNNode(geometry: dot)
        dotNode.simdOrientation = orientToSurface(normal: surfaceNormal)
        node.addChildNode(dotNode)

        // Two staggered expanding ripple rings instead of a static ring
        addWaterRing(to: node, color: color, direction: direction, delay: 0)
        addWaterRing(to: node, color: color, direction: direction, delay: 1.5)

        return node
    }

    /// Creates a thin torus ring that expands outward like a water ripple
    /// Uses scale transforms instead of geometry mutation to avoid per-frame vertex buffer rebuilds
    private func addWaterRing(to parent: SCNNode, color: NSColor, direction: SCNVector3, delay: TimeInterval) {
        // Create torus at its MAXIMUM target size from the start
        let maxRingRadius: CGFloat = 0.37  // 0.02 + 0.35
        let maxPipeRadius: CGFloat = 0.004
        let torus = SCNTorus(ringRadius: maxRingRadius, pipeRadius: maxPipeRadius)
        torus.ringSegmentCount = 48
        torus.pipeSegmentCount = 6

        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.15)
        mat.emission.contents = color.withAlphaComponent(0.35)
        mat.transparent.contents = NSColor(white: 1.0, alpha: 0.3)
        mat.blendMode = .add
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        torus.materials = [mat]

        let ringNode = SCNNode(geometry: torus)

        // Orient ring flat against globe surface using quaternion
        ringNode.simdOrientation = orientToSurface(normal: simd_float3(Float(direction.x), Float(direction.y), Float(direction.z)))

        ringNode.opacity = 0
        ringNode.scale = SCNVector3(0.05, 0.05, 0.05)
        parent.addChildNode(ringNode)

        let expandDuration: TimeInterval = 3.0

        let wait = SCNAction.wait(duration: delay)
        let expand = SCNAction.customAction(duration: expandDuration) { node, elapsed in
            let t = elapsed / CGFloat(expandDuration)
            let eased = 1.0 - (1.0 - t) * (1.0 - t) // ease-out
            // Scale from small to full size
            let s = 0.05 + eased * 0.95
            node.scale = SCNVector3(s, s, s)
            // Fade: ramp up then fade out gently
            let fadeIn = min(t * 4.0, 1.0)
            let fadeOut = max(0, 1.0 - (t - 0.25) / 0.75)
            node.opacity = fadeIn * fadeOut * 0.45
        }
        let reset = SCNAction.customAction(duration: 0.01) { node, _ in
            node.scale = SCNVector3(0.05, 0.05, 0.05)
            node.opacity = 0
        }
        let pause = SCNAction.wait(duration: Double.random(in: 0.2...0.8))
        ringNode.runAction(SCNAction.sequence([wait, SCNAction.repeatForever(SCNAction.sequence([expand, reset, pause]))]))
    }

    /// Expanding ring for the home marker — larger and slower than connection rings
    /// Uses scale transforms instead of geometry mutation to avoid per-frame vertex buffer rebuilds
    private func addHomeRing(to parent: SCNNode, color: NSColor, direction: SCNVector3, delay: TimeInterval) {
        // Create torus at its MAXIMUM target size from the start
        let maxRingRadius: CGFloat = 0.53  // 0.03 + 0.5
        let maxPipeRadius: CGFloat = 0.006
        let torus = SCNTorus(ringRadius: maxRingRadius, pipeRadius: maxPipeRadius)
        torus.ringSegmentCount = 48
        torus.pipeSegmentCount = 6

        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.2)
        mat.emission.contents = color.withAlphaComponent(0.5)
        mat.transparent.contents = NSColor(white: 1.0, alpha: 0.4)
        mat.blendMode = .add
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        torus.materials = [mat]

        let ringNode = SCNNode(geometry: torus)
        ringNode.simdOrientation = orientToSurface(normal: simd_float3(Float(direction.x), Float(direction.y), Float(direction.z)))
        ringNode.opacity = 0
        ringNode.scale = SCNVector3(0.05, 0.05, 0.05)
        parent.addChildNode(ringNode)

        let expandDuration: TimeInterval = 3.5

        let wait = SCNAction.wait(duration: delay)
        let expand = SCNAction.customAction(duration: expandDuration) { node, elapsed in
            let t = elapsed / CGFloat(expandDuration)
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            // Scale from small to full size
            let s = 0.05 + eased * 0.95
            node.scale = SCNVector3(s, s, s)
            let fadeIn = min(t * 4.0, 1.0)
            let fadeOut = max(0, 1.0 - (t - 0.25) / 0.75)
            node.opacity = fadeIn * fadeOut * 0.55
        }
        let reset = SCNAction.customAction(duration: 0.01) { node, _ in
            node.scale = SCNVector3(0.05, 0.05, 0.05)
            node.opacity = 0
        }
        let pause = SCNAction.wait(duration: Double.random(in: 0.3...0.8))
        ringNode.runAction(SCNAction.sequence([wait, SCNAction.repeatForever(SCNAction.sequence([expand, reset, pause]))]))
    }

    private func updatePinSize(_ node: SCNNode, count: Int) {
        // Dots are uniform size
    }

    // MARK: - Ripple Effect (for new connections)

    private func addRipple(at latitude: Double, longitude: Double, color: String) {
        let position = latLonToPosition(latitude: latitude, longitude: longitude)
        let direction = position.normalized()
        let intensityColor = colorForIntensity(color)

        // Two concentric water rings for a subtle splash effect
        addSplashRing(at: position, direction: direction, color: intensityColor, delay: 0, maxRadius: 0.4)
        addSplashRing(at: position, direction: direction, color: intensityColor, delay: 0.3, maxRadius: 0.7)
    }

    /// Uses scale transforms instead of geometry mutation to avoid per-frame vertex buffer rebuilds
    private func addSplashRing(at position: SCNVector3, direction: SCNVector3, color: NSColor, delay: TimeInterval, maxRadius: CGFloat) {
        // Create torus at its MAXIMUM target size from the start
        let fullRingRadius: CGFloat = 0.02 + maxRadius
        let torus = SCNTorus(ringRadius: fullRingRadius, pipeRadius: 0.008)
        torus.ringSegmentCount = 48
        torus.pipeSegmentCount = 6

        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.1)
        mat.emission.contents = color.withAlphaComponent(0.3)
        mat.transparent.contents = NSColor(white: 1.0, alpha: 0.25)
        mat.blendMode = .add
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        torus.materials = [mat]

        let ringNode = SCNNode(geometry: torus)
        ringNode.position = position
        // Orient ring flat against globe surface using quaternion
        ringNode.simdOrientation = orientToSurface(normal: simd_float3(Float(direction.x), Float(direction.y), Float(direction.z)))
        ringNode.opacity = 0
        ringNode.scale = SCNVector3(0.01, 0.01, 0.01)

        globeNode.addChildNode(ringNode)

        let wait = SCNAction.wait(duration: delay)
        let duration: TimeInterval = 2.0
        let expand = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = elapsed / CGFloat(duration)
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            // Scale from tiny to full size
            let s = 0.01 + eased * 0.99
            node.scale = SCNVector3(s, s, s)
            let fadeIn = min(t * 8.0, 1.0)
            let fadeOut = max(0, 1.0 - (t - 0.2) / 0.8)
            node.opacity = fadeIn * fadeOut * 0.7
        }

        ringNode.runAction(SCNAction.sequence([wait, expand, SCNAction.removeFromParentNode()]))
    }

    // MARK: - Arc Beams

    /// Smoothly interpolates between arc points using cubic Catmull-Rom style interpolation
    private func interpolateArcPoint(_ points: [simd_float3], at t: Float) -> simd_float3 {
        let count = points.count
        guard count > 1 else { return points.first ?? simd_float3(0, 0, 0) }

        let clampedT = max(0, min(1, t))
        let scaledT = clampedT * Float(count - 1)
        let index = min(Int(scaledT), count - 2)
        let frac = scaledT - Float(index)

        // Smooth hermite interpolation for buttery motion
        let smoothFrac = frac * frac * (3.0 - 2.0 * frac)

        let p0 = points[index]
        let p1 = points[min(index + 1, count - 1)]

        return p0 + (p1 - p0) * smoothFrac
    }

    /// Creates a curved arc beam from one lat/lon to another, with animated traveling particles and glow
    private func createArcBeam(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double, color: NSColor) -> SCNNode {
        let containerNode = SCNNode()
        containerNode.name = "arcBeam"

        let startPos = latLonToPosition(latitude: fromLat, longitude: fromLon)
        let endPos = latLonToPosition(latitude: toLat, longitude: toLon)

        // Compute arc points via great-circle slerp with elevation — high segment count for smoothness
        let segments = 96
        let s = simd_float3(Float(startPos.x), Float(startPos.y), Float(startPos.z))
        let e = simd_float3(Float(endPos.x), Float(endPos.y), Float(endPos.z))
        let arcDistance = simd_length(e - s)

        // Height of the arc proportional to distance (farther = higher arc) — elegant curves
        let maxArcHeight = Float(globeRadius) * 0.04 + arcDistance * 0.08

        var arcPoints: [simd_float3] = []

        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let point = slerpOnSphere(s, e, t: t)
            // Smooth sine elevation — peaked at midpoint
            let elevation = maxArcHeight * sin(t * .pi)
            let elevated = simd_normalize(point) * (simd_length(point) + elevation)
            arcPoints.append(elevated)
        }

        // --- Layer 1: Soft wide glow ribbon (background haze) ---
        let glowNode = buildRibbonNode(
            arcPoints: arcPoints, segments: segments, color: color,
            ribbonWidth: 0.022, baseAlpha: 0.06, emissionAlpha: 0.04
        )
        glowNode.opacity = 0.5
        containerNode.addChildNode(glowNode)

        // --- Layer 2: Core beam ribbon (sharp, bright center) ---
        let coreNode = buildRibbonNode(
            arcPoints: arcPoints, segments: segments, color: color,
            ribbonWidth: 0.005, baseAlpha: 0.35, emissionAlpha: 0.25
        )
        coreNode.opacity = 0.8
        containerNode.addChildNode(coreNode)

        // --- Animated beam entrance: draw-on effect ---
        containerNode.opacity = 0
        let fadeIn = SCNAction.fadeIn(duration: 0.6)
        fadeIn.timingMode = .easeOut
        containerNode.runAction(fadeIn)

        // --- Animated pulse along the beam (subtle brightness wave) ---
        addBeamPulse(to: coreNode, duration: 3.0 + Double.random(in: 0...1.0))

        // --- Traveling particles (multiple, staggered, smoothly interpolated) ---
        let particleCount = arcDistance > 3.0 ? 3 : 2
        for i in 0..<particleCount {
            let delay = Double(i) * (1.2 + Double.random(in: 0...0.5))
            addTravelingParticle(to: containerNode, arcPoints: arcPoints, color: color, initialDelay: delay)
        }

        return containerNode
    }

    /// Builds a ribbon geometry node from arc points — reusable for glow and core layers
    private func buildRibbonNode(arcPoints: [simd_float3], segments: Int, color: NSColor,
                                  ribbonWidth: Float, baseAlpha: Float, emissionAlpha: Float) -> SCNNode {
        var ribbonVerts: [Float] = []
        var ribbonColors: [Float] = []

        for i in 0...segments {
            let pos = arcPoints[i]
            let radial = simd_normalize(pos)

            let prev = i > 0 ? arcPoints[i - 1] : pos
            let next = i < segments ? arcPoints[i + 1] : pos
            let tangent = simd_normalize(next - prev)

            var perp = simd_cross(tangent, radial)
            let perpLen = simd_length(perp)
            if perpLen > 0.0001 {
                perp = perp / perpLen * ribbonWidth
            } else {
                perp = simd_float3(ribbonWidth, 0, 0)
            }

            ribbonVerts.append(pos.x + perp.x)
            ribbonVerts.append(pos.y + perp.y)
            ribbonVerts.append(pos.z + perp.z)

            ribbonVerts.append(pos.x - perp.x)
            ribbonVerts.append(pos.y - perp.y)
            ribbonVerts.append(pos.z - perp.z)

            // Smooth fade at endpoints using smoothstep-like curve
            let t = Float(i) / Float(segments)
            let edgeFade = sin(t * .pi)
            let smoothEdge = edgeFade * edgeFade  // Squared sine for softer fade
            let alpha = smoothEdge * baseAlpha

            let r = Float(color.redComponent)
            let g = Float(color.greenComponent)
            let b = Float(color.blueComponent)
            ribbonColors.append(contentsOf: [r, g, b, alpha])
            ribbonColors.append(contentsOf: [r, g, b, alpha])
        }

        var indices: [UInt16] = []
        for i in 0..<segments {
            let base = UInt16(i * 2)
            indices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
        }

        let vertexCount = (segments + 1) * 2
        let vertexData = Data(bytes: ribbonVerts, count: ribbonVerts.count * MemoryLayout<Float>.size)
        let vertexSource = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: vertexCount,
                                              usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                              dataOffset: 0, dataStride: 12)

        let colorData = Data(bytes: ribbonColors, count: ribbonColors.count * MemoryLayout<Float>.size)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: vertexCount,
                                             usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                             dataOffset: 0, dataStride: 16)

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt16>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles, primitiveCount: segments * 2, bytesPerIndex: 2)

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.white.withAlphaComponent(CGFloat(baseAlpha))
        mat.emission.contents = color.withAlphaComponent(CGFloat(emissionAlpha))
        mat.blendMode = .add
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        geometry.materials = [mat]

        return SCNNode(geometry: geometry)
    }

    /// Adds a subtle pulsing brightness animation to a beam node
    private func addBeamPulse(to node: SCNNode, duration: TimeInterval) {
        let pulse = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = elapsed / CGFloat(duration)
            // Gentle sine-wave opacity oscillation
            let wave = 0.7 + 0.3 * sin(t * CGFloat.pi * 2.0)
            node.opacity = CGFloat(wave) * 0.8
        }
        node.runAction(SCNAction.repeatForever(pulse))
    }

    /// Adds a smoothly interpolated glowing particle that travels along the arc path with a comet tail
    private func addTravelingParticle(to parent: SCNNode, arcPoints: [simd_float3], color: NSColor, initialDelay: TimeInterval) {
        // Main bright particle
        let sphere = SCNSphere(radius: 0.022)
        sphere.segmentCount = 12
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.white.withAlphaComponent(0.9)
        mat.emission.contents = color.withAlphaComponent(0.8)
        mat.emission.intensity = 1.5
        mat.blendMode = .add
        mat.lightingModel = .constant
        sphere.materials = [mat]

        let particleNode = SCNNode(geometry: sphere)
        particleNode.opacity = 0

        // Soft glow halo around the particle
        let halo = SCNSphere(radius: 0.06)
        halo.segmentCount = 8
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = color.withAlphaComponent(0.15)
        haloMat.emission.contents = color.withAlphaComponent(0.2)
        haloMat.emission.intensity = 1.0
        haloMat.blendMode = .add
        haloMat.lightingModel = .constant
        haloMat.writesToDepthBuffer = false
        halo.materials = [haloMat]

        let haloNode = SCNNode(geometry: halo)
        particleNode.addChildNode(haloNode)

        // Small trailing particles (comet tail effect)
        let tailCount = 4
        var tailNodes: [SCNNode] = []
        for j in 0..<tailCount {
            let tailSphere = SCNSphere(radius: CGFloat(0.012 - Double(j) * 0.002))
            tailSphere.segmentCount = 6
            let tailMat = SCNMaterial()
            tailMat.diffuse.contents = color.withAlphaComponent(CGFloat(0.4 - Double(j) * 0.08))
            tailMat.emission.contents = color.withAlphaComponent(CGFloat(0.3 - Double(j) * 0.06))
            tailMat.emission.intensity = 0.8
            tailMat.blendMode = .add
            tailMat.lightingModel = .constant
            tailMat.writesToDepthBuffer = false
            tailSphere.materials = [tailMat]

            let tailNode = SCNNode(geometry: tailSphere)
            tailNode.opacity = 0
            parent.addChildNode(tailNode)
            tailNodes.append(tailNode)
        }

        parent.addChildNode(particleNode)

        let travelDuration: TimeInterval = 2.0 + Double.random(in: 0...1.0)
        let pauseDuration: TimeInterval = Double.random(in: 0.8...2.5)
        let points = arcPoints

        let travel = SCNAction.customAction(duration: travelDuration) { [weak self] node, elapsed in
            let t = Float(elapsed / CGFloat(travelDuration))

            // Ease-in-out cubic for natural acceleration/deceleration
            let eased: Float
            if t < 0.5 {
                eased = 4.0 * t * t * t
            } else {
                let f = (2.0 * t - 2.0)
                eased = 0.5 * f * f * f + 1.0
            }

            // Smooth position interpolation
            let pos = self?.interpolateArcPoint(points, at: eased) ?? points[0]
            node.position = SCNVector3(CGFloat(pos.x), CGFloat(pos.y), CGFloat(pos.z))

            // Smooth fade in/out with sine curve — no hard edges
            let fadeEnvelope = sin(Float(t) * .pi)
            let smoothFade = fadeEnvelope * fadeEnvelope // Squared for softer transitions
            node.opacity = CGFloat(smoothFade) * 0.85

            // Update trailing particles with position history (delayed positions)
            for (j, tailNode) in tailNodes.enumerated() {
                let tailT = max(0, eased - Float(j + 1) * 0.035)
                let tailPos = self?.interpolateArcPoint(points, at: tailT) ?? points[0]
                tailNode.position = SCNVector3(CGFloat(tailPos.x), CGFloat(tailPos.y), CGFloat(tailPos.z))
                let tailFade = max(0, fadeEnvelope - Float(j + 1) * 0.15)
                tailNode.opacity = CGFloat(tailFade * tailFade) * CGFloat(0.5 - Double(j) * 0.1)
            }
        }

        let hide = SCNAction.customAction(duration: 0.01) { node, _ in
            node.opacity = 0
            for tailNode in tailNodes {
                tailNode.opacity = 0
            }
        }
        let pause = SCNAction.wait(duration: pauseDuration)
        let initialWait = SCNAction.wait(duration: initialDelay)

        particleNode.runAction(SCNAction.sequence([initialWait, SCNAction.repeatForever(SCNAction.sequence([travel, hide, pause]))]))
    }

    /// Spherical linear interpolation between two points on the globe surface
    private func slerpOnSphere(_ a: simd_float3, _ b: simd_float3, t: Float) -> simd_float3 {
        let aN = simd_normalize(a)
        let bN = simd_normalize(b)
        let radius = (simd_length(a) + simd_length(b)) * 0.5

        var dot = simd_dot(aN, bN)
        dot = max(-1.0, min(1.0, dot)) // clamp

        if dot > 0.9999 {
            // Nearly identical points — linear interpolation
            return a + (b - a) * t
        }

        let omega = acos(dot)
        let sinOmega = sin(omega)
        let factorA = sin((1.0 - t) * omega) / sinOmega
        let factorB = sin(t * omega) / sinOmega

        return (aN * factorA + bN * factorB) * radius
    }

    // MARK: - Coordinate Conversion

    func latLonToPosition(latitude: Double, longitude: Double) -> SCNVector3 {
        let latRad = Float(latitude * .pi / 180.0)
        let lonRad = Float(longitude * .pi / 180.0)
        let r = Float(globeRadius) * 1.01
        let x = r * Foundation.cos(latRad) * Foundation.sin(lonRad)
        let y = r * Foundation.sin(latRad)
        let z = r * Foundation.cos(latRad) * Foundation.cos(lonRad)
        return SCNVector3(x, y, z)
    }

    // MARK: - Surface Orientation

    /// Computes a quaternion that rotates the default Y-up axis to align with the given surface normal.
    /// SCNTorus and SCNCylinder both have their flat plane in XZ (Y is up), so we rotate Y → normal.
    private func orientToSurface(normal: simd_float3) -> simd_quatf {
        let up = simd_float3(0, 1, 0)
        let n = simd_normalize(normal)
        let dot = simd_dot(up, n)

        if dot > 0.9999 {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // identity
        } else if dot < -0.9999 {
            // 180° rotation around any perpendicular axis
            return simd_quatf(angle: .pi, axis: simd_float3(1, 0, 0))
        }

        let axis = simd_normalize(simd_cross(up, n))
        let angle = acos(dot)
        return simd_quatf(angle: angle, axis: axis)
    }

    // MARK: - Focus on Filtered Servers

    /// Stop rotation and smoothly rotate the globe to center on the given servers.
    /// Also adjusts zoom to fit the spread of connections.
    func focusOnServers(_ servers: [ServerInfo]) {
        guard !servers.isEmpty else { return }

        // Compute weighted centroid in 3D (avoids lat/lon wraparound issues)
        var wx: Double = 0, wy: Double = 0, wz: Double = 0
        var totalWeight: Double = 0

        // Include user location with moderate weight
        if hasUserLocation {
            let userW = 2.0
            let latRad = userLatitude * .pi / 180.0
            let lonRad = userLongitude * .pi / 180.0
            wx += userW * cos(latRad) * cos(lonRad)
            wy += userW * sin(latRad)
            wz += userW * cos(latRad) * sin(lonRad)
            totalWeight += userW
        }

        for server in servers {
            guard server.latitude != 0 || server.longitude != 0 else { continue }
            let w = Double(server.connectionCount)
            let latRad = server.latitude * .pi / 180.0
            let lonRad = server.longitude * .pi / 180.0
            wx += w * cos(latRad) * cos(lonRad)
            wy += w * sin(latRad)
            wz += w * cos(latRad) * sin(lonRad)
            totalWeight += w
        }

        guard totalWeight > 0 else { return }
        wx /= totalWeight
        wy /= totalWeight
        wz /= totalWeight

        // Convert centroid back to lat/lon
        let centroidLat = atan2(wy, sqrt(wx * wx + wz * wz)) * 180.0 / .pi
        let centroidLon = atan2(wz, wx) * 180.0 / .pi

        // Compute the angular spread to determine zoom level
        var maxAngle: Double = 0
        let centroid3D = simd_normalize(simd_float3(Float(wx), Float(wy), Float(wz)))

        // Check angle from centroid to user location
        if hasUserLocation {
            let uLatRad = userLatitude * .pi / 180.0
            let uLonRad = userLongitude * .pi / 180.0
            let uDir = simd_normalize(simd_float3(Float(cos(uLatRad) * cos(uLonRad)), Float(sin(uLatRad)), Float(cos(uLatRad) * sin(uLonRad))))
            let angle = Double(acos(max(-1, min(1, simd_dot(centroid3D, uDir))))) * 180.0 / .pi
            maxAngle = max(maxAngle, angle)
        }

        for server in servers {
            guard server.latitude != 0 || server.longitude != 0 else { continue }
            let latRad = server.latitude * .pi / 180.0
            let lonRad = server.longitude * .pi / 180.0
            let dir = simd_normalize(simd_float3(Float(cos(latRad) * cos(lonRad)), Float(sin(latRad)), Float(cos(latRad) * sin(lonRad))))
            let angle = Double(acos(max(-1, min(1, simd_dot(centroid3D, dir))))) * 180.0 / .pi
            maxAngle = max(maxAngle, angle)
        }

        // Choose zoom based on spread: tight cluster = zoom in, wide spread = zoom out
        let targetZ: CGFloat
        if maxAngle < 15 {
            targetZ = 9.0   // Very tight cluster — zoom in close
        } else if maxAngle < 40 {
            targetZ = 11.0  // Medium spread
        } else if maxAngle < 80 {
            targetZ = 13.0  // Wide spread
        } else {
            targetZ = 15.0  // Global spread — zoom out
        }

        // Smoothly rotate to the centroid
        smoothRotateToFace(latitude: centroidLat, longitude: centroidLon)

        // Adjust zoom
        zoomCamera(toZ: targetZ, duration: 1.5)
    }

    /// Resume auto-rotation (called when process filter is cleared)
    func resumeAutoRotation() {
        // Rotate back to face user if we know their location
        if hasUserLocation {
            smoothRotateToFace(latitude: userLatitude, longitude: userLongitude)
        }

    }

    // MARK: - Color Helpers

    private func colorForIntensity(_ intensity: String) -> NSColor {
        switch intensity {
        case "green":  return GlobeScene.lowColor
        case "yellow": return GlobeScene.medColor
        case "red":    return GlobeScene.highColor
        default:       return GlobeScene.lowColor
        }
    }

}

// MARK: - SCNVector3 Helpers

extension SCNVector3 {
    func normalized() -> SCNVector3 {
        let length = sqrt(x * x + y * y + z * z)
        guard length > 0 else { return self }
        return SCNVector3(x / length, y / length, z / length)
    }
}
