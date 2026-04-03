// ========================================
// THREE.JS ORGANIC FLOWING BACKGROUND
// Soft particles, petal patterns, gentle bloom
// ========================================

(function () {
  const canvas = document.getElementById('bg-canvas');
  if (!canvas || typeof THREE === 'undefined') return;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 1000);
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x1a1520, 1);

  camera.position.set(0, 0, 30);

  // --- Configuration ---
  const NODE_COUNT = 80;
  const CONNECTION_DISTANCE = 10;
  const ROSE = new THREE.Color(0xf0a6ca);
  const LAVENDER = new THREE.Color(0xc4b5fd);
  const BLUSH = new THREE.Color(0xfbc4ab);
  const SAGE = new THREE.Color(0xa8d5ba);

  // --- Floating particles ---
  const nodePositions = [];
  const nodeVelocities = [];
  const nodeSizes = [];

  for (let i = 0; i < NODE_COUNT; i++) {
    nodePositions.push(
      (Math.random() - 0.5) * 50,
      (Math.random() - 0.5) * 30,
      (Math.random() - 0.5) * 15 - 5
    );
    nodeVelocities.push(
      (Math.random() - 0.5) * 0.008,
      (Math.random() - 0.5) * 0.008,
      (Math.random() - 0.5) * 0.004
    );
    nodeSizes.push(0.18 + Math.random() * 0.35);
  }

  const nodeGeometry = new THREE.BufferGeometry();
  nodeGeometry.setAttribute('position', new THREE.Float32BufferAttribute(nodePositions, 3));
  nodeGeometry.setAttribute('size', new THREE.Float32BufferAttribute(nodeSizes, 1));

  const nodeShaderMaterial = new THREE.ShaderMaterial({
    uniforms: {
      uColor1: { value: ROSE },
      uColor2: { value: LAVENDER },
      uTime: { value: 0 }
    },
    vertexShader: `
      attribute float size;
      uniform float uTime;
      varying float vAlpha;
      varying float vMix;
      void main() {
        vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
        gl_PointSize = size * (280.0 / -mvPosition.z);
        gl_Position = projectionMatrix * mvPosition;
        vAlpha = 0.3 + 0.25 * sin(uTime * 0.4 + position.x * 0.3 + position.y * 0.2);
        vMix = 0.5 + 0.5 * sin(position.x * 0.2 + uTime * 0.15);
      }
    `,
    fragmentShader: `
      uniform vec3 uColor1;
      uniform vec3 uColor2;
      varying float vAlpha;
      varying float vMix;
      void main() {
        float d = length(gl_PointCoord - vec2(0.5));
        if (d > 0.5) discard;
        float glow = smoothstep(0.5, 0.0, d);
        vec3 color = mix(uColor1, uColor2, vMix);
        gl_FragColor = vec4(color, vAlpha * glow * glow);
      }
    `,
    transparent: true,
    depthWrite: false
  });

  const nodesMesh = new THREE.Points(nodeGeometry, nodeShaderMaterial);
  scene.add(nodesMesh);

  // --- Soft connection lines ---
  const maxLines = NODE_COUNT * 3;
  const linePositions = new Float32Array(maxLines * 6);
  const lineColors = new Float32Array(maxLines * 6);
  const lineGeometry = new THREE.BufferGeometry();
  lineGeometry.setAttribute('position', new THREE.Float32BufferAttribute(linePositions, 3));
  lineGeometry.setAttribute('color', new THREE.Float32BufferAttribute(lineColors, 3));

  const lineMaterial = new THREE.LineBasicMaterial({
    vertexColors: true,
    transparent: true,
    opacity: 0.35,
    depthWrite: false
  });

  const linesMesh = new THREE.LineSegments(lineGeometry, lineMaterial);
  scene.add(linesMesh);

  // --- Organic petal shapes (background pattern) ---
  const petalGroup = new THREE.Group();
  const petalMaterial = new THREE.LineBasicMaterial({
    color: ROSE,
    transparent: true,
    opacity: 0.05
  });

  for (let row = -4; row <= 4; row++) {
    for (let col = -6; col <= 6; col++) {
      const x = col * 5 + (row % 2) * 2.5;
      const y = row * 4.5;
      const petalShape = new THREE.BufferGeometry();
      const verts = [];
      for (let i = 0; i <= 60; i++) {
        const angle = (Math.PI * 2 / 60) * i;
        const r = 1.6 + 0.5 * Math.sin(angle * 3);
        verts.push(x + r * Math.cos(angle), y + r * Math.sin(angle), -18);
      }
      petalShape.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
      petalGroup.add(new THREE.Line(petalShape, petalMaterial));
    }
  }
  scene.add(petalGroup);

  // --- Gentle bloom ripples ---
  const RIPPLE_COLORS = [
    new THREE.Color(0xf0a6ca),
    new THREE.Color(0xc4b5fd),
    new THREE.Color(0xa8d5ba),
    new THREE.Color(0xfbc4ab),
  ];

  const pulseRings = [];
  const RING_INTERVAL = 3500;
  let lastRingTime = 0;

  function createRipple() {
    const x = (Math.random() - 0.5) * 35;
    const y = (Math.random() - 0.5) * 20;
    const color = RIPPLE_COLORS[Math.floor(Math.random() * RIPPLE_COLORS.length)];
    for (let r = 0; r < 3; r++) {
      const curve = new THREE.EllipseCurve(0, 0, 1, 1, 0, Math.PI * 2, false, 0);
      const points = curve.getPoints(64);
      const geom = new THREE.BufferGeometry().setFromPoints(points);
      const mat = new THREE.LineBasicMaterial({
        color: color,
        transparent: true,
        opacity: 0.25
      });
      const ring = new THREE.LineLoop(geom, mat);
      ring.position.set(x, y, -1);
      ring.scale.set(0.1, 0.1, 1);
      ring.userData = { age: -r * 0.5, maxAge: 5.0 };
      scene.add(ring);
      pulseRings.push(ring);
    }
  }

  // --- Rising petal particles ---
  const STREAM_COUNT = 40;
  const streamPositions = [];
  const streamVelocities = [];
  for (let i = 0; i < STREAM_COUNT; i++) {
    streamPositions.push(
      (Math.random() - 0.5) * 55,
      -20 - Math.random() * 15,
      (Math.random() - 0.5) * 10 - 3
    );
    streamVelocities.push(
      (Math.random() - 0.5) * 0.01,
      0.02 + Math.random() * 0.03,
      0
    );
  }

  const streamGeometry = new THREE.BufferGeometry();
  streamGeometry.setAttribute('position', new THREE.Float32BufferAttribute(streamPositions, 3));

  const streamMaterial = new THREE.ShaderMaterial({
    uniforms: {
      uColor: { value: BLUSH },
      uTime: { value: 0 }
    },
    vertexShader: `
      uniform float uTime;
      varying float vAlpha;
      void main() {
        vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
        gl_PointSize = 3.0 * (200.0 / -mvPosition.z);
        gl_Position = projectionMatrix * mvPosition;
        vAlpha = 0.2 + 0.15 * sin(uTime * 1.5 + position.x * 0.5);
      }
    `,
    fragmentShader: `
      uniform vec3 uColor;
      varying float vAlpha;
      void main() {
        float d = length(gl_PointCoord - vec2(0.5));
        if (d > 0.5) discard;
        float glow = smoothstep(0.5, 0.0, d);
        gl_FragColor = vec4(uColor, vAlpha * glow);
      }
    `,
    transparent: true,
    depthWrite: false
  });

  const streamMesh = new THREE.Points(streamGeometry, streamMaterial);
  scene.add(streamMesh);

  // --- Animation loop ---
  const clock = new THREE.Clock();

  function animate() {
    requestAnimationFrame(animate);
    const elapsed = clock.getElapsedTime();

    // Update node positions
    const pos = nodeGeometry.attributes.position.array;
    for (let i = 0; i < NODE_COUNT; i++) {
      const i3 = i * 3;
      pos[i3] += nodeVelocities[i3];
      pos[i3 + 1] += nodeVelocities[i3 + 1];
      pos[i3 + 2] += nodeVelocities[i3 + 2];
      if (Math.abs(pos[i3]) > 25) nodeVelocities[i3] *= -1;
      if (Math.abs(pos[i3 + 1]) > 15) nodeVelocities[i3 + 1] *= -1;
      if (Math.abs(pos[i3 + 2] + 5) > 8) nodeVelocities[i3 + 2] *= -1;
    }
    nodeGeometry.attributes.position.needsUpdate = true;
    nodeShaderMaterial.uniforms.uTime.value = elapsed;

    // Update connections (soft rose threads)
    let lineIdx = 0;
    const lp = lineGeometry.attributes.position.array;
    const lc = lineGeometry.attributes.color.array;
    for (let i = 0; i < NODE_COUNT && lineIdx < maxLines; i++) {
      for (let j = i + 1; j < NODE_COUNT && lineIdx < maxLines; j++) {
        const i3 = i * 3, j3 = j * 3;
        const dx = pos[i3] - pos[j3];
        const dy = pos[i3 + 1] - pos[j3 + 1];
        const dz = pos[i3 + 2] - pos[j3 + 2];
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (dist < CONNECTION_DISTANCE) {
          const idx = lineIdx * 6;
          lp[idx] = pos[i3]; lp[idx+1] = pos[i3+1]; lp[idx+2] = pos[i3+2];
          lp[idx+3] = pos[j3]; lp[idx+4] = pos[j3+1]; lp[idx+5] = pos[j3+2];
          const alpha = 1 - dist / CONNECTION_DISTANCE;
          const mix = 0.5 + 0.5 * Math.sin(elapsed * 0.2 + i * 0.1);
          lc[idx]   = (0.94*(1-mix) + 0.77*mix) * alpha;
          lc[idx+1] = (0.65*(1-mix) + 0.71*mix) * alpha;
          lc[idx+2] = (0.79*(1-mix) + 0.99*mix) * alpha;
          lc[idx+3] = lc[idx]; lc[idx+4] = lc[idx+1]; lc[idx+5] = lc[idx+2];
          lineIdx++;
        }
      }
    }
    for (let i = lineIdx; i < maxLines; i++) {
      const idx = i * 6;
      lp[idx]=lp[idx+1]=lp[idx+2]=0; lp[idx+3]=lp[idx+4]=lp[idx+5]=0;
    }
    lineGeometry.attributes.position.needsUpdate = true;
    lineGeometry.attributes.color.needsUpdate = true;
    lineGeometry.setDrawRange(0, lineIdx * 2);

    // Bloom ripples
    const now = performance.now();
    if (now - lastRingTime > RING_INTERVAL) { createRipple(); lastRingTime = now; }
    for (let i = pulseRings.length - 1; i >= 0; i--) {
      const ring = pulseRings[i];
      ring.userData.age += 0.016;
      const age = ring.userData.age;
      if (age < 0) continue;
      const t = age / ring.userData.maxAge;
      if (t >= 1) {
        scene.remove(ring); ring.geometry.dispose(); ring.material.dispose();
        pulseRings.splice(i, 1); continue;
      }
      const ease = 1 - Math.pow(1 - t, 2);
      const scale = 0.2 + ease * 12;
      ring.scale.set(scale, scale, 1);
      ring.material.opacity = 0.2 * (1 - t);
    }

    // Rising petal particles
    const sp = streamGeometry.attributes.position.array;
    for (let i = 0; i < STREAM_COUNT; i++) {
      const i3 = i * 3;
      sp[i3] += streamVelocities[i3] + Math.sin(elapsed * 0.5 + i) * 0.005;
      sp[i3 + 1] += streamVelocities[i3 + 1];
      if (sp[i3 + 1] > 25) {
        sp[i3] = (Math.random() - 0.5) * 55;
        sp[i3 + 1] = -20 - Math.random() * 15;
      }
    }
    streamGeometry.attributes.position.needsUpdate = true;
    streamMaterial.uniforms.uTime.value = elapsed;

    // Gentle petal rotation
    petalGroup.rotation.z = Math.sin(elapsed * 0.04) * 0.02;

    // Subtle camera sway
    camera.position.x = Math.sin(elapsed * 0.08) * 0.6;
    camera.position.y = Math.cos(elapsed * 0.06) * 0.4;

    renderer.render(scene, camera);
  }

  animate();

  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });
})();
