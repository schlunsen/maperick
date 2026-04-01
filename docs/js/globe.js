/**
 * Maperick — Interactive Three.js Globe Visualization
 *
 * Renders a wireframe earth globe with animated network-connection arcs,
 * glowing endpoint dots, and travelling particles.  Designed as an ambient,
 * dark-themed "hacker map" aesthetic background for the GitHub Pages site.
 *
 * Usage:
 *   import { initGlobe } from './globe.js';
 *   initGlobe(document.getElementById('globe-canvas'));
 */

import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js';
import { OrbitControls } from 'https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/controls/OrbitControls.js';

// ---------------------------------------------------------------------------
// Constants & palette
// ---------------------------------------------------------------------------

const PALETTE = {
  background: 0x0a0a1a,
  wireframe: 0x1a3a4a,
  dot: 0x00ff88,
  arc: 0x00ccff,
  glow: 0x00ccff,
  atmosphereInner: 0x0a2a3a,
};

const GLOBE_RADIUS = 2;
const DOT_COUNT = 22;
const ARC_COUNT = 12;
const ARC_SEGMENTS = 64;
const PARTICLE_COUNT_PER_ARC = 3;
const AUTO_ROTATE_SPEED = 0.0008;

// ---------------------------------------------------------------------------
// Fake location data for tooltips
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
  { ip: '200.174.9.12', city: 'São Paulo', country: 'BR' },
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
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Convert latitude / longitude (degrees) to a Vec3 on the sphere. */
function latLonToVec3(lat, lon, radius) {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lon + 180) * (Math.PI / 180);
  return new THREE.Vector3(
    -radius * Math.sin(phi) * Math.cos(theta),
    radius * Math.cos(phi),
    radius * Math.sin(phi) * Math.sin(theta),
  );
}

/** Generate a random latitude / longitude pair with uniform sphere distribution. */
function randomLatLon() {
  const lat = (Math.acos(2 * Math.random() - 1) / Math.PI) * 180 - 90;
  const lon = Math.random() * 360 - 180;
  return { lat, lon };
}

/** Quadratic bezier arc between two surface points, lifted above the globe. */
function createArcCurve(start, end, globeRadius) {
  const mid = new THREE.Vector3().addVectors(start, end).multiplyScalar(0.5);
  const dist = start.distanceTo(end);
  const altitude = globeRadius + dist * 0.45;
  mid.normalize().multiplyScalar(altitude);
  return new THREE.QuadraticBezierCurve3(start, mid, end);
}

/** Create a radial-gradient canvas texture for glow sprites. */
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
  gradient.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(canvas);
}

// ---------------------------------------------------------------------------
// Globe wireframe grid
// ---------------------------------------------------------------------------

function buildGlobe(scene) {
  const group = new THREE.Group();

  const gridMaterial = new THREE.LineBasicMaterial({
    color: PALETTE.wireframe,
    transparent: true,
    opacity: 0.35,
  });

  // Latitude rings
  for (let lat = -80; lat <= 80; lat += 20) {
    const pts = [];
    for (let lon = 0; lon <= 360; lon += 2) {
      pts.push(latLonToVec3(lat, lon, GLOBE_RADIUS));
    }
    const geo = new THREE.BufferGeometry().setFromPoints(pts);
    group.add(new THREE.Line(geo, gridMaterial));
  }

  // Longitude lines
  for (let lon = 0; lon < 360; lon += 20) {
    const pts = [];
    for (let lat = -90; lat <= 90; lat += 2) {
      pts.push(latLonToVec3(lat, lon, GLOBE_RADIUS));
    }
    const geo = new THREE.BufferGeometry().setFromPoints(pts);
    group.add(new THREE.Line(geo, gridMaterial));
  }

  // Subtle inner atmosphere shell
  const atmosphereGeo = new THREE.SphereGeometry(GLOBE_RADIUS * 1.015, 48, 48);
  const atmosphereMat = new THREE.MeshBasicMaterial({
    color: PALETTE.atmosphereInner,
    transparent: true,
    opacity: 0.08,
    side: THREE.FrontSide,
  });
  group.add(new THREE.Mesh(atmosphereGeo, atmosphereMat));

  // Outer glow shell (fresnel-style shader)
  const outerGeo = new THREE.SphereGeometry(GLOBE_RADIUS * 1.06, 48, 48);
  const outerMat = new THREE.ShaderMaterial({
    vertexShader: `
      varying vec3 vNormal;
      void main() {
        vNormal = normalize(normalMatrix * normal);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      varying vec3 vNormal;
      void main() {
        float intensity = pow(0.65 - dot(vNormal, vec3(0.0, 0.0, 1.0)), 3.0);
        gl_FragColor = vec4(0.1, 0.5, 0.7, 1.0) * intensity * 0.4;
      }
    `,
    blending: THREE.AdditiveBlending,
    side: THREE.BackSide,
    transparent: true,
    depthWrite: false,
  });
  group.add(new THREE.Mesh(outerGeo, outerMat));

  scene.add(group);
  return group;
}

// ---------------------------------------------------------------------------
// Connection dots
// ---------------------------------------------------------------------------

function buildDots(scene) {
  const positions = [];
  const dotData = [];

  for (let i = 0; i < DOT_COUNT; i++) {
    const { lat, lon } = randomLatLon();
    const pos = latLonToVec3(lat, lon, GLOBE_RADIUS * 1.005);
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
    size: 0.07,
    map: texture,
    transparent: true,
    opacity: 0.9,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    sizeAttenuation: true,
  });

  const points = new THREE.Points(geo, mat);
  scene.add(points);

  return { points, dotData };
}

// ---------------------------------------------------------------------------
// Arcs & travelling particles
// ---------------------------------------------------------------------------

function buildArcs(scene, dotData) {
  const arcs = [];
  const usedPairs = new Set();

  const arcMaterial = new THREE.LineBasicMaterial({
    color: PALETTE.arc,
    transparent: true,
    opacity: 0.18,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  });

  // Pick random unique pairs of dots
  let attempts = 0;
  while (arcs.length < ARC_COUNT && attempts < 200) {
    attempts++;
    const a = (Math.random() * dotData.length) | 0;
    const b = (Math.random() * dotData.length) | 0;
    if (a === b) continue;
    const key = a < b ? `${a}-${b}` : `${b}-${a}`;
    if (usedPairs.has(key)) continue;
    usedPairs.add(key);

    const curve = createArcCurve(
      dotData[a].position,
      dotData[b].position,
      GLOBE_RADIUS,
    );
    const pts = curve.getPoints(ARC_SEGMENTS);
    const geo = new THREE.BufferGeometry().setFromPoints(pts);
    const line = new THREE.Line(geo, arcMaterial);
    scene.add(line);

    arcs.push({ curve, line });
  }

  // Particles travelling along each arc
  const particlePositions = [];
  const particleMeta = [];

  for (let ai = 0; ai < arcs.length; ai++) {
    for (let p = 0; p < PARTICLE_COUNT_PER_ARC; p++) {
      const t = Math.random();
      const speed = 0.001 + Math.random() * 0.002;
      const pt = arcs[ai].curve.getPoint(t);
      particlePositions.push(pt.x, pt.y, pt.z);
      particleMeta.push({ arcIndex: ai, t, speed });
    }
  }

  const particleGeo = new THREE.BufferGeometry();
  particleGeo.setAttribute(
    'position',
    new THREE.Float32BufferAttribute(particlePositions, 3),
  );

  const particleTex = createGlowTexture(PALETTE.glow, 1.0);
  const particleMat = new THREE.PointsMaterial({
    color: PALETTE.glow,
    size: 0.045,
    map: particleTex,
    transparent: true,
    opacity: 0.85,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    sizeAttenuation: true,
  });

  const particlePoints = new THREE.Points(particleGeo, particleMat);
  scene.add(particlePoints);

  return { arcs, particlePoints, particleMeta };
}

// ---------------------------------------------------------------------------
// Tooltip
// ---------------------------------------------------------------------------

function createTooltip() {
  const el = document.createElement('div');
  el.style.cssText = [
    'position: fixed',
    'pointer-events: none',
    'background: rgba(10, 10, 26, 0.88)',
    'border: 1px solid rgba(0, 204, 255, 0.35)',
    'border-radius: 4px',
    'padding: 6px 10px',
    "font-family: 'JetBrains Mono', 'Fira Code', monospace",
    'font-size: 11px',
    'color: #00ff88',
    'line-height: 1.45',
    'display: none',
    'z-index: 1000',
    'backdrop-filter: blur(4px)',
    'box-shadow: 0 0 12px rgba(0, 204, 255, 0.15)',
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

  // -- Renderer -------------------------------------------------------------
  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    alpha: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(PALETTE.background, 1);

  const scene = new THREE.Scene();

  // -- Camera ---------------------------------------------------------------
  const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
  camera.position.set(0, 0, 5.5);

  // -- Controls -------------------------------------------------------------
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.dampingFactor = 0.06;
  controls.rotateSpeed = 0.4;
  controls.enablePan = false;
  controls.minDistance = 3.2;
  controls.maxDistance = 9;
  controls.enableZoom = true;

  // -- Build scene ----------------------------------------------------------
  const globeGroup = buildGlobe(scene);
  const { points: dotPoints, dotData } = buildDots(scene);
  const { arcs, particlePoints, particleMeta } = buildArcs(scene, dotData);

  // Attach everything to the globe group so auto-rotation moves them together
  globeGroup.add(dotPoints);
  for (const arc of arcs) {
    globeGroup.add(arc.line);
  }
  globeGroup.add(particlePoints);

  // -- Tooltip & raycasting -------------------------------------------------
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

  // -- Resize handler -------------------------------------------------------
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

  // -- Interaction state ----------------------------------------------------
  let isUserInteracting = false;
  controls.addEventListener('start', () => { isUserInteracting = true; });
  controls.addEventListener('end', () => { isUserInteracting = false; });

  let dotPulse = 0;

  // -- Animation loop -------------------------------------------------------
  function animate() {
    requestAnimationFrame(animate);

    // Auto-rotate when idle
    if (!isUserInteracting) {
      globeGroup.rotation.y += AUTO_ROTATE_SPEED;
    }

    // Subtle dot brightness pulse
    dotPulse += 0.02;
    dotPoints.material.opacity = 0.7 + Math.sin(dotPulse) * 0.2;

    // Move particles along their arcs
    const posAttr = particlePoints.geometry.getAttribute('position');
    for (let i = 0; i < particleMeta.length; i++) {
      const meta = particleMeta[i];
      meta.t += meta.speed;
      if (meta.t > 1) meta.t -= 1;
      const pt = arcs[meta.arcIndex].curve.getPoint(meta.t);
      posAttr.setXYZ(i, pt.x, pt.y, pt.z);
    }
    posAttr.needsUpdate = true;

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

    controls.update();
    renderer.render(scene, camera);
  }

  animate();

  // -- Return public handle -------------------------------------------------
  return {
    scene,
    camera,
    renderer,
    controls,
    globeGroup,
    dispose() {
      window.removeEventListener('resize', resize);
      controls.dispose();
      renderer.dispose();
      tooltip.remove();
    },
  };
}
