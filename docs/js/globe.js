/**
 * Maperick — Realistic Earth Globe with NASA Textures & Custom Shaders
 *
 * Uses the same NASA Blue Marble day map and night city-lights texture
 * as the native Mac app, rendered with a custom GLSL shader that blends
 * day/night based on a sun direction and adds atmospheric fresnel glow.
 */

import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const GLOBE_RADIUS = 2;
const DOT_COUNT = 28;
const ARC_COUNT = 14;
const ARC_SEGMENTS = 64;
const PARTICLE_COUNT_PER_ARC = 3;
const AUTO_ROTATE_SPEED = 0.0006;

const PALETTE = {
  background: 0x0a0a1a,
  dot: 0x00ff88,
  arc: 0x00ccff,
  glow: 0x00ccff,
};

// ---------------------------------------------------------------------------
// Earth shader — day/night blend + atmosphere rim
// ---------------------------------------------------------------------------

const earthVertexShader = /* glsl */ `
  varying vec2 vUv;
  varying vec3 vNormal;
  varying vec3 vPosition;
  varying vec3 vWorldNormal;

  void main() {
    vUv = uv;
    vNormal = normalize(normalMatrix * normal);
    vWorldNormal = normalize((modelMatrix * vec4(normal, 0.0)).xyz);
    vPosition = (modelViewMatrix * vec4(position, 1.0)).xyz;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const earthFragmentShader = /* glsl */ `
  uniform sampler2D uDayMap;
  uniform sampler2D uNightMap;
  uniform vec3 uSunDirection;
  uniform float uTime;

  varying vec2 vUv;
  varying vec3 vNormal;
  varying vec3 vPosition;
  varying vec3 vWorldNormal;

  void main() {
    vec3 viewDir = normalize(-vPosition);

    // Sample textures
    vec3 dayColor = texture2D(uDayMap, vUv).rgb;
    vec3 nightColor = texture2D(uNightMap, vUv).rgb;

    // Sun illumination factor based on world-space normal vs sun direction
    float sunDot = dot(vWorldNormal, uSunDirection);

    // Smooth day/night transition (-0.15 to 0.2 = twilight zone)
    float dayFactor = smoothstep(-0.15, 0.2, sunDot);

    // Darken day side to fit dark theme, brighten slightly on sun-facing side
    vec3 dayLit = dayColor * mix(0.25, 0.65, dayFactor);

    // Night side: city lights with warm glow
    vec3 nightLit = nightColor * vec3(1.0, 0.85, 0.6) * 1.2;

    // Blend day and night
    vec3 color = mix(nightLit, dayLit, dayFactor);

    // Rim lighting — atmospheric edge glow
    float rimPower = 1.0 - max(dot(vNormal, viewDir), 0.0);

    // Blue atmosphere on the lit side rim
    vec3 atmosphereColor = vec3(0.2, 0.5, 1.0);
    float atmosRim = pow(rimPower, 2.5);
    color += atmosphereColor * atmosRim * dayFactor * 0.5;

    // Green/cyan accent on the dark side rim (hacker aesthetic)
    vec3 darkRimColor = vec3(0.0, 0.8, 0.5);
    color += darkRimColor * pow(rimPower, 3.5) * (1.0 - dayFactor) * 0.3;

    // General subtle rim glow (always visible)
    vec3 generalRim = vec3(0.1, 0.4, 0.7);
    color += generalRim * pow(rimPower, 3.0) * 0.25;

    // Very subtle pulsing brightness
    float pulse = 1.0 + sin(uTime * 0.5) * 0.02;
    color *= pulse;

    gl_FragColor = vec4(color, 1.0);
  }
`;

// ---------------------------------------------------------------------------
// Atmosphere shader — outer glow halo
// ---------------------------------------------------------------------------

const atmosphereVertexShader = /* glsl */ `
  varying vec3 vNormal;
  varying vec3 vPosition;

  void main() {
    vNormal = normalize(normalMatrix * normal);
    vPosition = (modelViewMatrix * vec4(position, 1.0)).xyz;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const atmosphereFragmentShader = /* glsl */ `
  varying vec3 vNormal;
  varying vec3 vPosition;

  void main() {
    vec3 viewDir = normalize(-vPosition);
    float intensity = pow(0.7 - dot(vNormal, viewDir), 3.0);
    vec3 color = vec3(0.12, 0.45, 0.85);
    gl_FragColor = vec4(color, 1.0) * intensity * 0.6;
  }
`;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function latLonToVec3(lat, lon, radius) {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lon + 180) * (Math.PI / 180);
  return new THREE.Vector3(
    -radius * Math.sin(phi) * Math.cos(theta),
    radius * Math.cos(phi),
    radius * Math.sin(phi) * Math.sin(theta),
  );
}

function randomLatLon() {
  const lat = (Math.acos(2 * Math.random() - 1) / Math.PI) * 180 - 90;
  const lon = Math.random() * 360 - 180;
  return { lat, lon };
}

function createArcCurve(start, end, globeRadius) {
  const mid = new THREE.Vector3().addVectors(start, end).multiplyScalar(0.5);
  const dist = start.distanceTo(end);
  const altitude = globeRadius + dist * 0.45;
  mid.normalize().multiplyScalar(altitude);
  return new THREE.QuadraticBezierCurve3(start, mid, end);
}

function createGlowTexture(color, opacity) {
  const canvas = document.createElement('canvas');
  canvas.width = 64;
  canvas.height = 64;
  const ctx = canvas.getContext('2d');
  const gradient = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  const c = new THREE.Color(color);
  const r = (c.r * 255) | 0;
  const g = (c.g * 255) | 0;
  const b = (c.b * 255) | 0;
  gradient.addColorStop(0, `rgba(${r},${g},${b},${opacity})`);
  gradient.addColorStop(0.4, `rgba(${r},${g},${b},${opacity * 0.4})`);
  gradient.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(canvas);
}

// ---------------------------------------------------------------------------
// Location data for tooltip
// ---------------------------------------------------------------------------

const LOCATIONS = [
  { ip: '142.250.80.46', city: 'Mountain View', country: 'US' },
  { ip: '151.101.1.140', city: 'San Francisco', country: 'US' },
  { ip: '104.16.132.229', city: 'Toronto', country: 'CA' },
  { ip: '185.199.108.153', city: 'Amsterdam', country: 'NL' },
  { ip: '13.107.42.14', city: 'Redmond', country: 'US' },
  { ip: '93.184.216.34', city: 'London', country: 'GB' },
  { ip: '198.41.30.2', city: 'Paris', country: 'FR' },
  { ip: '216.58.214.206', city: 'Zurich', country: 'CH' },
  { ip: '172.217.14.110', city: 'Frankfurt', country: 'DE' },
  { ip: '31.13.70.36', city: 'Stockholm', country: 'SE' },
  { ip: '157.240.1.35', city: 'Singapore', country: 'SG' },
  { ip: '52.84.150.11', city: 'Tokyo', country: 'JP' },
  { ip: '103.235.46.39', city: 'Hong Kong', country: 'HK' },
  { ip: '203.208.41.37', city: 'Sydney', country: 'AU' },
  { ip: '200.174.9.12', city: 'Sao Paulo', country: 'BR' },
  { ip: '154.120.80.11', city: 'Cape Town', country: 'ZA' },
  { ip: '41.206.32.10', city: 'Nairobi', country: 'KE' },
  { ip: '178.238.11.6', city: 'Mumbai', country: 'IN' },
  { ip: '223.5.5.5', city: 'Beijing', country: 'CN' },
  { ip: '121.78.90.2', city: 'Seoul', country: 'KR' },
  { ip: '176.32.103.205', city: 'Dublin', country: 'IE' },
  { ip: '82.98.86.174', city: 'Helsinki', country: 'FI' },
  { ip: '190.93.240.10', city: 'Buenos Aires', country: 'AR' },
  { ip: '185.70.41.35', city: 'Moscow', country: 'RU' },
  { ip: '45.55.99.72', city: 'New York', country: 'US' },
  { ip: '103.21.244.0', city: 'Jakarta', country: 'ID' },
  { ip: '197.234.240.1', city: 'Lagos', country: 'NG' },
  { ip: '185.180.12.1', city: 'Warsaw', country: 'PL' },
];

// ---------------------------------------------------------------------------
// Build Earth
// ---------------------------------------------------------------------------

function buildEarth(scene) {
  const group = new THREE.Group();
  const loader = new THREE.TextureLoader();

  // Load both textures
  const dayMap = loader.load('textures/earth_daymap.jpg');
  const nightMap = loader.load('textures/earth_night.jpg');

  // Improve texture quality
  for (const tex of [dayMap, nightMap]) {
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    tex.minFilter = THREE.LinearMipmapLinearFilter;
    tex.magFilter = THREE.LinearFilter;
  }

  // Sun direction — angled so roughly half the globe is lit
  const sunDir = new THREE.Vector3(1.0, 0.3, 0.8).normalize();

  // Earth sphere with day/night shader
  const earthGeo = new THREE.SphereGeometry(GLOBE_RADIUS, 96, 96);
  const earthMat = new THREE.ShaderMaterial({
    uniforms: {
      uDayMap: { value: dayMap },
      uNightMap: { value: nightMap },
      uSunDirection: { value: sunDir },
      uTime: { value: 0 },
    },
    vertexShader: earthVertexShader,
    fragmentShader: earthFragmentShader,
    transparent: false,
  });
  const earthMesh = new THREE.Mesh(earthGeo, earthMat);
  group.add(earthMesh);

  // Inner atmosphere rim (additive, front-face)
  const innerAtmoGeo = new THREE.SphereGeometry(GLOBE_RADIUS * 1.004, 64, 64);
  const innerAtmoMat = new THREE.ShaderMaterial({
    vertexShader: atmosphereVertexShader,
    fragmentShader: /* glsl */ `
      varying vec3 vNormal;
      varying vec3 vPosition;
      void main() {
        vec3 viewDir = normalize(-vPosition);
        float rim = 1.0 - max(dot(vNormal, viewDir), 0.0);
        float intensity = pow(rim, 3.5);
        vec3 color = mix(vec3(0.0, 0.7, 0.4), vec3(0.15, 0.45, 0.9), rim);
        gl_FragColor = vec4(color, intensity * 0.3);
      }
    `,
    blending: THREE.AdditiveBlending,
    side: THREE.FrontSide,
    transparent: true,
    depthWrite: false,
  });
  group.add(new THREE.Mesh(innerAtmoGeo, innerAtmoMat));

  // Outer atmosphere halo (back-side, larger sphere)
  const outerAtmoGeo = new THREE.SphereGeometry(GLOBE_RADIUS * 1.18, 64, 64);
  const outerAtmoMat = new THREE.ShaderMaterial({
    vertexShader: atmosphereVertexShader,
    fragmentShader: atmosphereFragmentShader,
    blending: THREE.AdditiveBlending,
    side: THREE.BackSide,
    transparent: true,
    depthWrite: false,
  });
  group.add(new THREE.Mesh(outerAtmoGeo, outerAtmoMat));

  scene.add(group);
  return { group, earthMat };
}

// ---------------------------------------------------------------------------
// Connection dots
// ---------------------------------------------------------------------------

function buildDots(group) {
  const positions = [];
  const dotData = [];

  for (let i = 0; i < DOT_COUNT; i++) {
    const { lat, lon } = randomLatLon();
    const pos = latLonToVec3(lat, lon, GLOBE_RADIUS * 1.008);
    positions.push(pos.x, pos.y, pos.z);
    dotData.push({
      position: pos,
      location: LOCATIONS[i % LOCATIONS.length],
    });
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));

  const texture = createGlowTexture(PALETTE.dot, 1.0);
  const mat = new THREE.PointsMaterial({
    color: PALETTE.dot,
    size: 0.08,
    map: texture,
    transparent: true,
    opacity: 0.9,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    sizeAttenuation: true,
  });

  const points = new THREE.Points(geo, mat);
  group.add(points);

  return { points, dotData };
}

// ---------------------------------------------------------------------------
// Arcs & travelling particles
// ---------------------------------------------------------------------------

function buildArcs(group, dotData) {
  const arcs = [];
  const usedPairs = new Set();

  const arcMaterial = new THREE.LineBasicMaterial({
    color: PALETTE.arc,
    transparent: true,
    opacity: 0.2,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  });

  let attempts = 0;
  while (arcs.length < ARC_COUNT && attempts < 300) {
    attempts++;
    const a = (Math.random() * dotData.length) | 0;
    const b = (Math.random() * dotData.length) | 0;
    if (a === b) continue;
    const key = a < b ? `${a}-${b}` : `${b}-${a}`;
    if (usedPairs.has(key)) continue;
    usedPairs.add(key);

    const curve = createArcCurve(dotData[a].position, dotData[b].position, GLOBE_RADIUS);
    const pts = curve.getPoints(ARC_SEGMENTS);
    const geo = new THREE.BufferGeometry().setFromPoints(pts);
    const line = new THREE.Line(geo, arcMaterial.clone());
    group.add(line);
    arcs.push({ curve, line });
  }

  // Travelling particles
  const particlePositions = [];
  const particleMeta = [];

  for (let ai = 0; ai < arcs.length; ai++) {
    for (let p = 0; p < PARTICLE_COUNT_PER_ARC; p++) {
      const t = Math.random();
      const speed = 0.0008 + Math.random() * 0.0018;
      const pt = arcs[ai].curve.getPoint(t);
      particlePositions.push(pt.x, pt.y, pt.z);
      particleMeta.push({ arcIndex: ai, t, speed });
    }
  }

  const particleGeo = new THREE.BufferGeometry();
  particleGeo.setAttribute('position', new THREE.Float32BufferAttribute(particlePositions, 3));

  const particleTex = createGlowTexture(PALETTE.glow, 1.0);
  const particleMat = new THREE.PointsMaterial({
    color: PALETTE.glow,
    size: 0.055,
    map: particleTex,
    transparent: true,
    opacity: 0.9,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    sizeAttenuation: true,
  });

  const particlePoints = new THREE.Points(particleGeo, particleMat);
  group.add(particlePoints);

  return { arcs, particlePoints, particleMeta };
}

// ---------------------------------------------------------------------------
// Star field
// ---------------------------------------------------------------------------

function buildStars(scene) {
  const count = 2000;
  const positions = new Float32Array(count * 3);

  for (let i = 0; i < count; i++) {
    const r = 30 + Math.random() * 50;
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.acos(2 * Math.random() - 1);
    positions[i * 3] = r * Math.sin(phi) * Math.cos(theta);
    positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
    positions[i * 3 + 2] = r * Math.cos(phi);
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));

  const mat = new THREE.PointsMaterial({
    color: 0x9999cc,
    size: 0.06,
    transparent: true,
    opacity: 0.5,
    sizeAttenuation: true,
    depthWrite: false,
  });

  scene.add(new THREE.Points(geo, mat));
}

// ---------------------------------------------------------------------------
// Tooltip
// ---------------------------------------------------------------------------

function createTooltip() {
  const el = document.createElement('div');
  el.style.cssText = [
    'position: fixed',
    'pointer-events: none',
    'background: rgba(10, 10, 26, 0.92)',
    'border: 1px solid rgba(0, 204, 255, 0.35)',
    'border-radius: 6px',
    'padding: 8px 12px',
    "font-family: 'JetBrains Mono', 'Fira Code', monospace",
    'font-size: 11px',
    'color: #00ff88',
    'line-height: 1.5',
    'display: none',
    'z-index: 1000',
    'backdrop-filter: blur(8px)',
    'box-shadow: 0 0 16px rgba(0, 204, 255, 0.15), 0 4px 12px rgba(0,0,0,0.4)',
  ].join(';');
  document.body.appendChild(el);
  return el;
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

export function initGlobe(canvas) {
  if (!canvas) {
    console.error('[Maperick] Canvas element not found.');
    return null;
  }

  // Renderer
  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    alpha: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(PALETTE.background, 1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  const scene = new THREE.Scene();

  // Camera — slightly above center for a nice angle
  const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 200);
  camera.position.set(0, 0.8, 5.2);

  // Stars
  buildStars(scene);

  // Earth
  const { group: globeGroup, earthMat } = buildEarth(scene);
  const { points: dotPoints, dotData } = buildDots(globeGroup);
  const { arcs, particlePoints, particleMeta } = buildArcs(globeGroup, dotData);

  // Tilt globe slightly
  globeGroup.rotation.x = 0.15;
  globeGroup.rotation.z = -0.05;

  // Tooltip & raycasting
  const tooltip = createTooltip();
  const raycaster = new THREE.Raycaster();
  raycaster.params.Points.threshold = 0.12;
  const mouse = new THREE.Vector2(9999, 9999);
  let hoveredIndex = -1;

  canvas.addEventListener('mousemove', (e) => {
    const rect = canvas.getBoundingClientRect();
    mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
    tooltip.style.left = `${e.clientX + 14}px`;
    tooltip.style.top = `${e.clientY + 14}px`;
  });

  canvas.addEventListener('mouseleave', () => {
    mouse.set(9999, 9999);
    tooltip.style.display = 'none';
    hoveredIndex = -1;
  });

  // Resize
  function resize() {
    const parent = canvas.parentElement || document.body;
    const w = parent.clientWidth;
    const h = parent.clientHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', resize);
  resize();

  // Animation
  let dotPulse = 0;
  const clock = new THREE.Clock();

  function animate() {
    requestAnimationFrame(animate);

    const elapsed = clock.getElapsedTime();
    const rotationFactor = globeGroup.userData.rotationFactor ?? 1;

    // Auto-rotate
    globeGroup.rotation.y += AUTO_ROTATE_SPEED * rotationFactor;

    // Update shader uniforms
    earthMat.uniforms.uTime.value = elapsed;

    // Dot pulse
    dotPulse += 0.02;
    dotPoints.material.opacity = 0.7 + Math.sin(dotPulse) * 0.2;

    // Move particles along arcs
    const posAttr = particlePoints.geometry.getAttribute('position');
    for (let i = 0; i < particleMeta.length; i++) {
      const meta = particleMeta[i];
      meta.t += meta.speed;
      if (meta.t > 1) meta.t -= 1;
      const pt = arcs[meta.arcIndex].curve.getPoint(meta.t);
      posAttr.setXYZ(i, pt.x, pt.y, pt.z);
    }
    posAttr.needsUpdate = true;

    // Arc opacity pulse
    for (let i = 0; i < arcs.length; i++) {
      const phase = elapsed * 0.8 + i * 0.5;
      arcs[i].line.material.opacity = 0.12 + Math.sin(phase) * 0.08;
    }

    // Tooltip raycasting
    raycaster.setFromCamera(mouse, camera);
    const intersects = raycaster.intersectObject(dotPoints);
    if (intersects.length > 0) {
      const idx = intersects[0].index;
      if (idx !== hoveredIndex && idx < dotData.length) {
        hoveredIndex = idx;
        const loc = dotData[idx].location;
        tooltip.innerHTML =
          `<span style="color:#00ccff">&#9679;</span> ${loc.ip}<br>` +
          `<span style="opacity:0.6">${loc.city}, ${loc.country}</span>`;
        tooltip.style.display = 'block';
      }
    } else if (hoveredIndex !== -1) {
      tooltip.style.display = 'none';
      hoveredIndex = -1;
    }

    renderer.render(scene, camera);
  }

  animate();

  return {
    scene,
    camera,
    renderer,
    globeGroup,
    dispose() {
      window.removeEventListener('resize', resize);
      renderer.dispose();
      tooltip.remove();
    },
  };
}
