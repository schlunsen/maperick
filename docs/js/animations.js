/**
 * animations.js — Scroll-based animations and interactive UI for Maperick.
 * Pure vanilla JS, no dependencies. Designed for 60fps smoothness.
 */

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function throttle(fn, ms) {
  let last = 0;
  let timer = null;
  return function (...args) {
    const now = performance.now();
    const remaining = ms - (now - last);
    if (remaining <= 0) {
      if (timer) {
        cancelAnimationFrame(timer);
        timer = null;
      }
      last = now;
      fn.apply(this, args);
    } else if (!timer) {
      timer = requestAnimationFrame(() => {
        last = performance.now();
        timer = null;
        fn.apply(this, args);
      });
    }
  };
}

// ---------------------------------------------------------------------------
// State shared across subsystems
// ---------------------------------------------------------------------------

let observers = [];
let scrollHandlers = [];
let rafId = null;
let lastScrollY = 0;
let ticking = false;

// ---------------------------------------------------------------------------
// 1. Scroll-triggered fade-ins
// ---------------------------------------------------------------------------

function initScrollFadeIns() {
  const targets = document.querySelectorAll('.animate-on-scroll');
  if (!targets.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;

        const el = entry.target;
        el.classList.add('visible');

        // Stagger children that opt in
        const children = el.querySelectorAll('.stagger');
        children.forEach((child, i) => {
          child.style.transitionDelay = `${i * 80}ms`;
          child.classList.add('visible');
        });

        observer.unobserve(el);
      });
    },
    { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
  );

  targets.forEach((t) => observer.observe(t));
  observers.push(observer);
}

// ---------------------------------------------------------------------------
// 2. Hero parallax
// ---------------------------------------------------------------------------

function initHeroParallax() {
  const hero = document.querySelector('.hero');
  const heroContent = document.querySelector('.hero-content');
  const globe = document.querySelector('.globe-container');
  if (!hero) return;

  const heroHeight = () => hero.offsetHeight;

  function onScroll(scrollY) {
    const h = heroHeight();
    if (scrollY > h * 1.5) return; // no work when far past hero

    const ratio = Math.min(scrollY / h, 1);

    if (heroContent) {
      heroContent.style.transform = `translateY(${scrollY * 0.35}px)`;
      heroContent.style.opacity = 1 - ratio * 1.1;
    }

    if (globe) {
      globe.style.transform = `translateY(${scrollY * 0.2}px)`;
    }
  }

  scrollHandlers.push(onScroll);
}

// ---------------------------------------------------------------------------
// 3. Sticky header
// ---------------------------------------------------------------------------

function initStickyHeader() {
  let header = document.querySelector('.sticky-header');

  // If no sticky header exists in the DOM, create one
  if (!header) {
    header = document.createElement('header');
    header.className = 'sticky-header';
    header.setAttribute('aria-hidden', 'true');
    header.innerHTML = `
      <a href="#" class="sticky-header__logo">Maperick</a>
      <a href="https://github.com/schlunsen/maperick"
         class="sticky-header__github"
         target="_blank"
         rel="noopener noreferrer">
        GitHub
      </a>
    `;
    document.body.prepend(header);
  }

  const hero = document.querySelector('.hero');
  const triggerOffset = hero ? hero.offsetHeight * 0.6 : 400;

  function onScroll(scrollY) {
    const show = scrollY > triggerOffset;
    header.classList.toggle('sticky-header--visible', show);
    header.setAttribute('aria-hidden', String(!show));
  }

  scrollHandlers.push(onScroll);
}

// ---------------------------------------------------------------------------
// 4. Terminal typing effect
// ---------------------------------------------------------------------------

function initTypingEffect() {
  const blocks = document.querySelectorAll('.typing-effect');
  if (!blocks.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;

        const el = entry.target;
        observer.unobserve(el);
        typeBlock(el);
      });
    },
    { threshold: 0.5 }
  );

  blocks.forEach((b) => observer.observe(b));
  observers.push(observer);
}

function typeBlock(el) {
  const fullText = el.getAttribute('data-text') || el.textContent;
  el.textContent = '';
  el.classList.add('typing-active');

  // Create a blinking cursor element
  const cursor = document.createElement('span');
  cursor.className = 'typing-cursor';
  cursor.textContent = '\u2588'; // full block character
  el.after(cursor);

  let i = 0;
  const speed = 30; // ms per character

  function step() {
    if (i < fullText.length) {
      el.textContent += fullText[i];
      i++;
      setTimeout(step, fullText[i - 1] === '\n' ? speed * 6 : speed);
    } else {
      el.classList.remove('typing-active');
      el.classList.add('typing-done');
      // Keep cursor blinking for a moment, then remove
      setTimeout(() => cursor.remove(), 2000);
    }
  }

  step();
}

// ---------------------------------------------------------------------------
// 5. Smooth scroll for anchor links
// ---------------------------------------------------------------------------

function initSmoothScroll() {
  document.addEventListener('click', (e) => {
    const link = e.target.closest('a[href^="#"]');
    if (!link) return;

    const id = link.getAttribute('href');
    if (id === '#') return;

    const target = document.querySelector(id);
    if (!target) return;

    e.preventDefault();
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });

    // Update URL without jumping
    if (history.pushState) {
      history.pushState(null, '', id);
    }
  });
}

// ---------------------------------------------------------------------------
// 6. Globe integration helper
// ---------------------------------------------------------------------------

/**
 * Returns a scroll-handler function that adjusts globe visuals based on
 * scroll position. The caller (e.g. main.js or globe.js) can hook this
 * into the animation loop or pass a globe API object.
 *
 * @param {Object} options
 * @param {HTMLElement} options.globeElement - The globe canvas / container
 * @param {Function}    [options.setRotationSpeed] - Callback to adjust rotation speed (0-1)
 * @returns {Function} scrollHandler(scrollY) — call on each scroll tick
 */
export function createGlobeScrollHandler({
  globeElement,
  setRotationSpeed = null,
} = {}) {
  const hero = document.querySelector('.hero');
  const heroHeight = hero ? hero.offsetHeight : 600;

  return function globeScrollHandler(scrollY) {
    const ratio = Math.min(Math.max(scrollY / heroHeight, 0), 1);

    // Fade globe as user scrolls past hero (min opacity 0.25)
    if (globeElement) {
      globeElement.style.opacity = 1 - ratio * 0.75;
    }

    // Slow rotation: full speed at top, 20% speed once past hero
    if (typeof setRotationSpeed === 'function') {
      setRotationSpeed(1 - ratio * 0.8);
    }
  };
}

// ---------------------------------------------------------------------------
// Central scroll dispatcher (one listener, one rAF)
// ---------------------------------------------------------------------------

function onRawScroll() {
  lastScrollY = window.scrollY;
  if (!ticking) {
    rafId = requestAnimationFrame(() => {
      const y = lastScrollY;
      for (let i = 0; i < scrollHandlers.length; i++) {
        scrollHandlers[i](y);
      }
      ticking = false;
    });
    ticking = true;
  }
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

function cleanup() {
  observers.forEach((o) => o.disconnect());
  observers = [];
  scrollHandlers = [];

  window.removeEventListener('scroll', onRawScroll, { passive: true });
  window.removeEventListener('beforeunload', cleanup);

  if (rafId) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
}

/**
 * Initialise all animation subsystems.
 * Call once after DOM is ready.
 */
export function initAnimations() {
  // Reset in case of hot-reload
  cleanup();

  initScrollFadeIns();
  initHeroParallax();
  initStickyHeader();
  initTypingEffect();
  initSmoothScroll();

  window.addEventListener('scroll', onRawScroll, { passive: true });
  window.addEventListener('beforeunload', cleanup);

  // Trigger once for elements already in view on load
  onRawScroll();
}
