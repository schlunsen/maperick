// ========================================
// NAVIGATION
// ========================================
const slides = document.querySelectorAll('.slide');
const dots = document.querySelectorAll('.dot');
const counter = document.getElementById('slide-counter');
const prevBtn = document.getElementById('nav-prev');
const nextBtn = document.getElementById('nav-next');
let currentSlide = 0;
const totalSlides = slides.length;
let isTransitioning = false;

function goToSlide(index, direction) {
  direction = direction || 'next';
  if (index < 0 || index >= totalSlides || index === currentSlide || isTransitioning) return;
  isTransitioning = true;
  var current = slides[currentSlide];
  var next = slides[index];
  current.classList.remove('slide-active', 'slide-exit-left');
  next.classList.remove('slide-active', 'slide-exit-left');
  if (direction === 'next') {
    next.style.transform = 'translateX(60px)';
    next.style.opacity = '0';
    current.classList.add('slide-exit-left');
  } else {
    next.style.transform = 'translateX(-60px)';
    next.style.opacity = '0';
    current.style.transform = 'translateX(60px)';
    current.style.opacity = '0';
  }
  current.classList.remove('slide-active');
  void next.offsetWidth;
  next.style.transform = '';
  next.style.opacity = '';
  next.classList.add('slide-active');
  dots[currentSlide].classList.remove('active');
  dots[index].classList.add('active');
  counter.textContent = (index + 1) + ' / ' + totalSlides;
  currentSlide = index;
  triggerSlideAnimations(index);
  if (typeof window.__playSlideAudio === 'function') window.__playSlideAudio(index);
  setTimeout(function() {
    isTransitioning = false;
    current.classList.remove('slide-exit-left');
    current.style.transform = '';
    current.style.opacity = '';
  }, 650);
}

function nextSlide() { if (currentSlide < totalSlides - 1) goToSlide(currentSlide + 1, 'next'); }
function prevSlide() { if (currentSlide > 0) goToSlide(currentSlide - 1, 'prev'); }

document.addEventListener('keydown', function(e) {
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === ' ') { e.preventDefault(); nextSlide(); }
  if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') { e.preventDefault(); prevSlide(); }
});
nextBtn.addEventListener('click', nextSlide);
prevBtn.addEventListener('click', prevSlide);
dots.forEach(function(dot, i) {
  dot.addEventListener('click', function() { goToSlide(i, i > currentSlide ? 'next' : 'prev'); });
});

var touchStartX = 0, touchStartY = 0;
document.addEventListener('touchstart', function(e) { touchStartX = e.touches[0].clientX; touchStartY = e.touches[0].clientY; }, { passive: true });
document.addEventListener('touchend', function(e) {
  var dx = e.changedTouches[0].clientX - touchStartX, dy = e.changedTouches[0].clientY - touchStartY;
  if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 50) { if (dx < 0) nextSlide(); else prevSlide(); }
}, { passive: true });

// ========================================
// SLIDE ANIMATIONS
// ========================================
function animateCount(el, target, duration) {
  var startTime = performance.now();
  function update(now) {
    var progress = Math.min((now - startTime) / duration, 1);
    el.textContent = Math.round(target * (1 - Math.pow(1 - progress, 3)));
    if (progress < 1) requestAnimationFrame(update);
  }
  requestAnimationFrame(update);
}

function triggerSlideAnimations(index) {
  var slide = slides[index];
  if (index === 1) slide.querySelectorAll('.philosophy-point').forEach(function(p, i) { setTimeout(function() { p.classList.add('visible'); }, 400 + i * 300); });

  // Slide 3 (index 2): PROBLEM slide — dramatic staggered reveal
  if (index === 2) {
    var eyebrow = slide.querySelector('.problem-eyebrow');
    var heading = slide.querySelector('.problem-heading');
    var cards = slide.querySelectorAll('.problem-card');
    var mockup = slide.querySelector('.problem-mockup');
    var quote = slide.querySelector('.problem-quote');
    [eyebrow, heading, mockup, quote].forEach(function(el) { if (el) el.classList.remove('visible'); });
    cards.forEach(function(c) { c.classList.remove('visible'); });

    // Choreography: eyebrow → heading → cards stagger → mockup → quote
    setTimeout(function() { if (eyebrow) eyebrow.classList.add('visible'); }, 200);
    setTimeout(function() { if (heading) heading.classList.add('visible'); }, 600);
    cards.forEach(function(c, i) {
      setTimeout(function() { c.classList.add('visible'); }, 1200 + i * 400);
    });
    setTimeout(function() { if (mockup) mockup.classList.add('visible'); }, 2800);
    setTimeout(function() { if (quote) quote.classList.add('visible'); }, 3600);
  }

  if (index === 3) {
    slide.classList.remove('phase-intro', 'phase-settled');
    slide.querySelectorAll('.agent-orbital').forEach(function(n) { n.classList.remove('visible'); });
    slide.classList.add('phase-intro');
    setTimeout(function() {
      slide.classList.remove('phase-intro'); slide.classList.add('phase-settled');
      slide.querySelectorAll('.agent-orbital').forEach(function(n, i) { setTimeout(function() { n.classList.add('visible'); }, 1200 + i * 2000); });
    }, 4000);
  }
  if (index === 4) {
    // Zoom-Through Pipeline: badges zoom from dots, shockwaves fire, cards materialize
    var ztTitle = slide.querySelector('.zt-title');
    var badges = slide.querySelectorAll('.zt-badge');
    var shockwaves = slide.querySelectorAll('.zt-shockwave');
    var bodies = slide.querySelectorAll('.zt-card-body');
    var connectors = slide.querySelectorAll('.zt-connector-line');

    // Reset all state for re-entry
    if (ztTitle) ztTitle.classList.remove('visible');
    badges.forEach(function(b) { b.classList.remove('zoom-in'); });
    shockwaves.forEach(function(s) { s.classList.remove('fire'); });
    bodies.forEach(function(b) { b.classList.remove('materialize'); });
    connectors.forEach(function(c) { c.classList.remove('draw'); });
    void slide.offsetWidth; // force reflow

    // Card 1: dot → badge → shockwave → card materializes
    setTimeout(function() { badges[0].classList.add('zoom-in'); }, 400);
    setTimeout(function() { shockwaves[0].classList.add('fire'); }, 650);
    setTimeout(function() { bodies[0].classList.add('materialize'); }, 900);

    // Connector 1 draws
    setTimeout(function() { connectors[0].classList.add('draw'); }, 1400);

    // Card 2: same sequence
    setTimeout(function() { badges[1].classList.add('zoom-in'); }, 1800);
    setTimeout(function() { shockwaves[1].classList.add('fire'); }, 2050);
    setTimeout(function() { bodies[1].classList.add('materialize'); }, 2300);

    // Connector 2 draws
    setTimeout(function() { connectors[1].classList.add('draw'); }, 2800);

    // Card 3: same sequence
    setTimeout(function() { badges[2].classList.add('zoom-in'); }, 3200);
    setTimeout(function() { shockwaves[2].classList.add('fire'); }, 3450);
    setTimeout(function() { bodies[2].classList.add('materialize'); }, 3700);

    // Title fades in LAST — content first, label last
    setTimeout(function() { if (ztTitle) ztTitle.classList.add('visible'); }, 4500);
  }
  if (index === 5) {
    slide.querySelectorAll('.loop-node').forEach(function(n, i) { setTimeout(function() { n.classList.add('visible'); }, 200 + i * 200); });
    var r = slide.querySelector('.loop-repeat'); if (r) setTimeout(function() { r.classList.add('visible'); }, 1200);
    slide.querySelectorAll('.docker-container').forEach(function(c, i) { setTimeout(function() { c.classList.add('visible'); }, 400 + i * 150); });
  }
  // Slide 7 (index 6): LAYOUTS — stagger layout preview cards
  if (index === 6) {
    slide.querySelectorAll('.layout-preview').forEach(function(p) { p.classList.remove('visible'); });
    slide.querySelectorAll('.layout-preview').forEach(function(p, i) {
      setTimeout(function() { p.classList.add('visible'); }, 400 + i * 200);
    });
    // Legacy fallback
    slide.querySelectorAll('.timeline-event').forEach(function(e, i) { setTimeout(function() { e.classList.add('visible'); }, 300 + i * 200); });
  }
  if (index === 7) slide.querySelectorAll('.dash-row:not(.header)').forEach(function(r, i) { setTimeout(function() { r.classList.add('visible'); }, 300 + i * 200); });
  if (index === 8) slide.querySelectorAll('.severity-item').forEach(function(s, i) { setTimeout(function() { s.classList.add('visible'); }, 200 + i * 150); });
  // Slide 10 (index 9): IMPACT stagger + count + bars
  if (index === 9) {
    slide.querySelectorAll('.stagger-item').forEach(function(el) { el.classList.remove('visible'); });
    slide.querySelectorAll('.impact-bar-fill').forEach(function(el) { el.style.width = '0%'; });
    slide.querySelectorAll('.stagger-item').forEach(function(item) {
      var delay = parseInt(item.dataset.stagger || 0) * 600 + 300;
      setTimeout(function() {
        item.classList.add('visible');
        item.querySelectorAll('[data-count]').forEach(function(n) { animateCount(n, parseInt(n.dataset.count), 1500); });
        item.querySelectorAll('.impact-bar-fill').forEach(function(bar, bi) {
          setTimeout(function() { bar.style.width = bar.dataset.width + '%'; }, 200 + bi * 300);
        });
      }, delay);
    });
  }
  // Slide 11 (index 10): BUILD YOUR OWN — stagger build-step cards
  if (index === 10) {
    slide.querySelectorAll('.build-step').forEach(function(s) { s.classList.remove('visible'); });
    slide.querySelectorAll('.build-step').forEach(function(s, i) {
      setTimeout(function() { s.classList.add('visible'); }, 300 + i * 250);
    });
  }
}
triggerSlideAnimations(0);

// ========================================
// AUDIO NARRATION (overlap-safe)
// ========================================
var audioToggle = document.getElementById('audio-toggle');
var volumeSlider = document.getElementById('volume-slider');
var audioProgressBar = document.getElementById('audio-progress-bar');
var audioEnabled = true, audioVolume = 0.6, currentAudio = null, audioProgressInterval = null;
var slideAudioCache = {};
var activeFadeIntervals = [];  // track all fade intervals so we can kill them
var pendingTimer = null;
var audioGeneration = 0;  // increments on every playSlideAudio call; stale callbacks check this

function preloadAllAudio() {
  for (var i = 0; i < totalSlides; i++) {
    var audio = new Audio();
    audio.preload = 'auto';
    audio.src = 'presentation-audio/slide-' + String(i + 1).padStart(2, '0') + '.mp3';
    audio.volume = audioVolume;
    (function(idx, a) {
      a.addEventListener('error', function() { delete slideAudioCache[idx]; });
      a.addEventListener('canplaythrough', function() { slideAudioCache[idx] = a; }, { once: true });
      slideAudioCache[idx] = a;
    })(i, audio);
  }
}
preloadAllAudio();

function cancelAllFades() {
  for (var i = 0; i < activeFadeIntervals.length; i++) {
    clearInterval(activeFadeIntervals[i]);
  }
  activeFadeIntervals = [];
}

function fadeAudio(audio, to, dur, cb) {
  var from = audio.volume;
  if (from === to) { if (cb) cb(); return; }
  var steps = 25, stepVal = (to - from) / steps, iv = dur / steps;
  var t = setInterval(function() {
    audio.volume = Math.max(0, Math.min(1, audio.volume + stepVal));
    if ((stepVal > 0 && audio.volume >= to - 0.01) || (stepVal < 0 && audio.volume <= to + 0.01)) {
      audio.volume = Math.max(0, Math.min(1, to));
      clearInterval(t);
      var idx = activeFadeIntervals.indexOf(t);
      if (idx !== -1) activeFadeIntervals.splice(idx, 1);
      if (to === 0) audio.pause();
      if (cb) cb();
    }
  }, iv);
  activeFadeIntervals.push(t);
}

// Hard-stop every audio element immediately — no fade, no delay
function killAllAudio() {
  cancelAllFades();
  if (pendingTimer) { clearTimeout(pendingTimer); pendingTimer = null; }
  if (audioProgressInterval) { clearInterval(audioProgressInterval); audioProgressInterval = null; }
  Object.values(slideAudioCache).forEach(function(a) {
    if (!a.paused) { a.pause(); }
    a.currentTime = 0;
    a.volume = audioVolume;
  });
  currentAudio = null;
  audioProgressBar.style.width = '0%';
}

function stopCurrentAudio() {
  killAllAudio();
}

function playSlideAudio(si) {
  // Immediately kill everything — no overlap possible
  killAllAudio();
  audioGeneration++;
  var gen = audioGeneration;

  if (!audioEnabled) return;
  var nextA = slideAudioCache[si];
  if (!nextA) return;

  // Small delay before starting new audio for a clean transition
  pendingTimer = setTimeout(function() {
    pendingTimer = null;
    if (gen !== audioGeneration) return;  // stale — user already navigated again
    startAudio(nextA, si, gen);
  }, 600);
}

function startAudio(audio, si, gen) {
  if (!audioEnabled || gen !== audioGeneration) return;

  // Safety: make sure nothing else is playing
  Object.values(slideAudioCache).forEach(function(a) {
    if (a !== audio && !a.paused) { a.pause(); a.currentTime = 0; }
  });

  audio.currentTime = 0;
  currentAudio = audio;
  audio.volume = 0;
  // Valentina (slides 1 & 12): slightly faster, slightly quieter
  var isValentina = (si === 0 || si === 11);
  audio.playbackRate = isValentina ? 1.1 : 1.0;
  audio.play().catch(function() {});
  fadeAudio(audio, isValentina ? audioVolume * 0.85 : audioVolume, 600);

  audioProgressInterval = setInterval(function() {
    if (gen !== audioGeneration) { clearInterval(audioProgressInterval); return; }
    if (audio.duration && !audio.paused) {
      audioProgressBar.style.width = ((audio.currentTime / audio.duration) * 100) + '%';
    }
  }, 200);

  audio.addEventListener('ended', function() {
    if (gen !== audioGeneration) return;
    audioProgressBar.style.width = '100%';
    setTimeout(function() {
      if (gen !== audioGeneration) return;
      audioProgressBar.style.width = '0%';
    }, 500);
    if (audioProgressInterval) { clearInterval(audioProgressInterval); audioProgressInterval = null; }
  }, { once: true });

  audio.addEventListener('ended', function() {
    if (gen !== audioGeneration) return;  // don't auto-advance if user already moved
    if (audioEnabled && si < totalSlides - 1) {
      setTimeout(function() {
        if (gen !== audioGeneration) return;
        goToSlide(si + 1, 'next');
      }, 1200);
    }
  }, { once: true });
}

audioToggle.addEventListener('click', function() {
  audioEnabled = !audioEnabled;
  audioToggle.classList.toggle('muted', !audioEnabled);
  if (!audioEnabled) stopCurrentAudio(); else playSlideAudio(currentSlide);
});
volumeSlider.addEventListener('input', function() {
  audioVolume = parseInt(volumeSlider.value) / 100;
  if (currentAudio && !currentAudio.paused) currentAudio.volume = audioVolume;
  if (audioVolume === 0) { audioToggle.classList.add('muted'); audioEnabled = false; }
  else if (!audioEnabled) { audioEnabled = true; audioToggle.classList.remove('muted'); }
});
document.addEventListener('keydown', function(e) { if (e.key === 'a' || e.key === 'A') audioToggle.click(); });
window.__playSlideAudio = playSlideAudio;

// ========================================
// BACKGROUND MUSIC
// ========================================
var bgMusic = new Audio('presentation-audio/background-music.mp3');
bgMusic.loop = true;
bgMusic.volume = 0;
bgMusic.preload = 'auto';
var bgMusicEnabled = true;
var bgMusicVolumeMultiplier = 0.30;  // slider value (0-1) — scales the base/ducked volumes
var bgMusicBaseVolume = 0.18;  // quiet background level (max)
var bgMusicDuckedVolume = 0.07;  // duck when narration plays (max)
var musicToggle = document.getElementById('music-toggle');
var musicVolumeSlider = document.getElementById('music-volume-slider');

function getMusicBase() { return bgMusicBaseVolume * bgMusicVolumeMultiplier; }
function getMusicDucked() { return bgMusicDuckedVolume * bgMusicVolumeMultiplier; }

function fadeBgMusic(to, dur) {
  var from = bgMusic.volume, steps = 20, stepVal = (to - from) / steps, iv = dur / steps;
  var t = setInterval(function() {
    bgMusic.volume = Math.max(0, Math.min(1, bgMusic.volume + stepVal));
    if ((stepVal > 0 && bgMusic.volume >= to - 0.005) || (stepVal < 0 && bgMusic.volume <= to + 0.005) || stepVal === 0) {
      bgMusic.volume = Math.max(0, Math.min(1, to));
      clearInterval(t);
    }
  }, iv);
}

function startBgMusic() {
  if (!bgMusicEnabled) return;
  bgMusic.volume = 0;
  bgMusic.play().catch(function() {});
  fadeBgMusic(getMusicBase(), 1500);
}

function duckBgMusic() {
  if (!bgMusic.paused) fadeBgMusic(getMusicDucked(), 400);
}

function unduckBgMusic() {
  if (!bgMusic.paused) fadeBgMusic(getMusicBase(), 800);
}

// Duck when narration plays, unduck when it ends
var _origStartAudio = startAudio;
startAudio = function(audio, si, gen) {
  duckBgMusic();
  audio.addEventListener('ended', function() { if (gen === audioGeneration) unduckBgMusic(); }, { once: true });
  _origStartAudio(audio, si, gen);
};

musicToggle.addEventListener('click', function() {
  bgMusicEnabled = !bgMusicEnabled;
  musicToggle.classList.toggle('muted', !bgMusicEnabled);
  if (!bgMusicEnabled) {
    fadeBgMusic(0, 400);
    setTimeout(function() { bgMusic.pause(); }, 500);
  } else {
    startBgMusic();
  }
});

document.addEventListener('keydown', function(e) { if (e.key === 'm' || e.key === 'M') musicToggle.click(); });

musicVolumeSlider.addEventListener('input', function() {
  bgMusicVolumeMultiplier = parseInt(musicVolumeSlider.value) / 100;
  if (!bgMusic.paused) {
    // If narration is playing, stay ducked at new level; otherwise go to base
    if (currentAudio && !currentAudio.paused) fadeBgMusic(getMusicDucked(), 200);
    else fadeBgMusic(getMusicBase(), 200);
  }
});

// ========================================
// PRESENTER AVATAR (audio-reactive)
// ========================================
var presenterBubble = document.getElementById('presenter-bubble');
var presenterA = document.getElementById('presenter-a');
var presenterB = document.getElementById('presenter-b');
var presenterC = document.getElementById('presenter-c');
var presenterName = document.getElementById('presenter-name');
var audioCtx = null, analyser = null, analyserData = null;
var mouthAnimFrame = null;
var connectedSources = new WeakMap();

// Slide-to-presenter mapping: slide 1 & 12 = C (Valentina), slides 2 & 11 = A (Alex), slides 3-10 = B (Sam)
function getPresenter(slideIndex) {
  if (slideIndex === 0 || slideIndex === 11) return 'c'; // slides 1 & 12
  if (slideIndex === 1 || slideIndex === 10) return 'a'; // slides 2 & 11 (Alex)
  return 'b';
}

var currentPresenterWho = null;
var swapBurst = document.getElementById('presenter-swap-burst');
var EXIT_ANIMS = ['exit-spin', 'exit-drop', 'exit-zoom'];
var ENTER_ANIMS = ['enter-bounce', 'enter-slide', 'enter-flip'];
var ALL_ANIMS = EXIT_ANIMS.concat(ENTER_ANIMS);
var PRESENTER_NAMES = { a: 'Alex', b: 'Sam', c: 'Valentina' };
var presenterEls = { a: presenterA, b: presenterB, c: presenterC };
var swapInProgress = false;

function clearAnimClasses(el) {
  ALL_ANIMS.forEach(function(c) { el.classList.remove(c); });
}

function randomFrom(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

function showPresenter(slideIndex) {
  var who = getPresenter(slideIndex);

  // Same presenter, just make sure visible
  if (who === currentPresenterWho) {
    presenterBubble.classList.add('visible');
    return;
  }

  var prevWho = currentPresenterWho;
  currentPresenterWho = who;

  var ringStroke = document.getElementById('presenter-ring-stroke');

  function animateStrokeDraw(duration, cb) {
    if (!ringStroke) { if (cb) cb(); return; }
    var start = performance.now();
    function step(now) {
      var t = Math.min((now - start) / duration, 1);
      // ease-out cubic
      var e = 1 - Math.pow(1 - t, 3);
      ringStroke.style.strokeDashoffset = (283 - e * 283).toFixed(0);
      if (t < 1) requestAnimationFrame(step); else { if (cb) cb(); }
    }
    ringStroke.style.strokeDashoffset = '283';
    requestAnimationFrame(step);
  }

  function animateStrokeErase(duration, cb) {
    if (!ringStroke) { if (cb) cb(); return; }
    var start = performance.now();
    function step(now) {
      var t = Math.min((now - start) / duration, 1);
      var e = Math.pow(t, 2); // ease-in
      ringStroke.style.strokeDashoffset = (e * 283).toFixed(0);
      if (t < 1) requestAnimationFrame(step); else { if (cb) cb(); }
    }
    ringStroke.style.strokeDashoffset = '0';
    requestAnimationFrame(step);
  }

  // First appearance — stroke draws in with enter animation
  if (!prevWho || !presenterBubble.classList.contains('visible')) {
    presenterA.style.display = 'none';
    presenterB.style.display = 'none';
    presenterC.style.display = 'none';
    var newEl = presenterEls[who];
    clearAnimClasses(newEl);
    newEl.style.display = '';
    newEl.classList.add(randomFrom(ENTER_ANIMS));
    presenterName.textContent = PRESENTER_NAMES[who];
    presenterName.classList.remove('anim-in');
    void presenterName.offsetWidth;
    presenterName.classList.add('anim-in');
    presenterBubble.classList.remove('presenter-active-a', 'presenter-active-b', 'presenter-active-c');
    presenterBubble.classList.add('presenter-active-' + who);
    presenterBubble.classList.add('visible');
    animateStrokeDraw(600);
    return;
  }

  // Swap animation: stroke erases → old exits → burst → stroke draws → new enters
  if (swapInProgress) return;
  swapInProgress = true;

  var oldEl = presenterEls[prevWho];
  var newEl = presenterEls[who];
  var exitAnim = randomFrom(EXIT_ANIMS);
  var enterAnim = randomFrom(ENTER_ANIMS);

  // Phase 0: Stroke erases while old exits
  animateStrokeErase(400);
  clearAnimClasses(oldEl);
  void oldEl.offsetWidth;
  oldEl.classList.add(exitAnim);

  setTimeout(function() {
    // Phase 1: Old is gone, fire burst glow
    oldEl.style.display = 'none';
    clearAnimClasses(oldEl);

    swapBurst.classList.remove('fire');
    void swapBurst.offsetWidth;
    swapBurst.classList.add('fire');

    // Update ring color
    presenterBubble.classList.remove('presenter-active-a', 'presenter-active-b', 'presenter-active-c');
    presenterBubble.classList.add('presenter-active-' + who);

    setTimeout(function() {
      // Phase 2: New presenter enters + stroke draws in
      newEl.style.display = '';
      clearAnimClasses(newEl);
      void newEl.offsetWidth;
      newEl.classList.add(enterAnim);
      animateStrokeDraw(500);

      // Name tag slides in
      presenterName.textContent = PRESENTER_NAMES[who];
      presenterName.classList.remove('anim-in');
      void presenterName.offsetWidth;
      presenterName.classList.add('anim-in');

      setTimeout(function() {
        swapInProgress = false;
        swapBurst.classList.remove('fire');
      }, 700);
    }, 250); // slight delay after burst starts before new enters
  }, 500); // wait for exit animation to finish
}

function hidePresenter() {
  presenterBubble.classList.remove('visible', 'speaking');
  stopMouthAnimation();
}

function ensureAudioContext() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    analyser = audioCtx.createAnalyser();
    analyser.fftSize = 256;
    analyser.smoothingTimeConstant = 0.6;
    analyserData = new Uint8Array(analyser.frequencyBinCount);
  }
  if (audioCtx.state === 'suspended') audioCtx.resume();
}

function connectAudioToAnalyser(audio) {
  ensureAudioContext();
  if (!connectedSources.has(audio)) {
    var source = audioCtx.createMediaElementSource(audio);
    source.connect(analyser);
    analyser.connect(audioCtx.destination);
    connectedSources.set(audio, source);
  }
}

var blinkTimer = null;
var pupilTimer = null;
var browTimer = null;
var squintTimer = null;

// Viseme shapes: each defines lip paths, mouth hole, jaw, tongue, teeth, cheeks
// Shapes are interpolated for smooth transitions
var VISEMES = {
  // 0: closed / rest
  rest:       { holeRx: 1, holeRy: 0.5, holeCy: 76, jawDy: 0, upperLip: 'M52,76 Q56,75.5 60,75.5 Q64,75.5 68,76', lowerLip: 'M52,76 Q56,76.5 60,76.5 Q64,76.5 68,76', tongueRy: 0, tongueCy: 80, teethUpperH: 0, teethLowerH: 0, cheekScale: 1 },
  // 1: slight open "uh/schwa"
  uh:         { holeRx: 7, holeRy: 4, holeCy: 77, jawDy: 2, upperLip: 'M51,75 Q56,73 60,73 Q64,73 69,75', lowerLip: 'M51,79 Q56,81 60,81 Q64,81 69,79', tongueRy: 1, tongueCy: 80, teethUpperH: 1.5, teethLowerH: 0, cheekScale: 1 },
  // 2: "ah" wide open
  ah:         { holeRx: 9, holeRy: 7, holeCy: 78, jawDy: 5, upperLip: 'M49,75 Q55,72 60,71.5 Q65,72 71,75', lowerLip: 'M49,81 Q55,86 60,87 Q65,86 71,81', tongueRy: 3, tongueCy: 83, teethUpperH: 2.5, teethLowerH: 1.5, cheekScale: 0.9 },
  // 3: "ee" wide grin
  ee:         { holeRx: 11, holeRy: 2.5, holeCy: 76, jawDy: 1, upperLip: 'M48,76 Q54,74 60,73.5 Q66,74 72,76', lowerLip: 'M48,76 Q54,78 60,78.5 Q66,78 72,76', tongueRy: 0, tongueCy: 78, teethUpperH: 2, teethLowerH: 1, cheekScale: 1.15 },
  // 4: "oo" small round
  oo:         { holeRx: 4, holeRy: 5, holeCy: 77, jawDy: 3, upperLip: 'M54,75 Q57,73 60,72.5 Q63,73 66,75', lowerLip: 'M54,79 Q57,82 60,83 Q63,82 66,79', tongueRy: 1.5, tongueCy: 81, teethUpperH: 0, teethLowerH: 0, cheekScale: 0.85 },
  // 5: "F/V" - teeth on lower lip
  fv:         { holeRx: 8, holeRy: 1.5, holeCy: 76, jawDy: 0.5, upperLip: 'M50,76 Q55,75 60,75 Q65,75 70,76', lowerLip: 'M50,76 Q55,76.5 60,76.8 Q65,76.5 70,76', tongueRy: 0, tongueCy: 78, teethUpperH: 3.5, teethLowerH: 0, cheekScale: 1 },
  // 6: "M/B/P" - lips pressed
  mbp:        { holeRx: 7, holeRy: 0.3, holeCy: 76, jawDy: 0, upperLip: 'M50,76 Q55,75.8 60,75.8 Q65,75.8 70,76', lowerLip: 'M50,76 Q55,76.2 60,76.2 Q65,76.2 70,76', tongueRy: 0, tongueCy: 78, teethUpperH: 0, teethLowerH: 0, cheekScale: 1.1 },
  // 7: "TH/L" - tongue tip visible
  th:         { holeRx: 8, holeRy: 3, holeCy: 76.5, jawDy: 1.5, upperLip: 'M50,75 Q55,73.5 60,73 Q65,73.5 70,75', lowerLip: 'M50,78 Q55,79.5 60,80 Q65,79.5 70,78', tongueRy: 3.5, tongueCy: 77, teethUpperH: 2, teethLowerH: 0, cheekScale: 1 },
  // 8: "W/R" - pursed
  wr:         { holeRx: 5, holeRy: 3.5, holeCy: 77, jawDy: 2, upperLip: 'M53,76 Q56,74 60,73.5 Q64,74 67,76', lowerLip: 'M53,78 Q56,80 60,81 Q64,80 67,78', tongueRy: 0.5, tongueCy: 79, teethUpperH: 0, teethLowerH: 0, cheekScale: 0.9 },
  // 9: asymmetric smirk (funny!)
  smirk:      { holeRx: 8, holeRy: 2.5, holeCy: 76, jawDy: 1, upperLip: 'M50,77 Q55,74 60,73 Q65,74 70,74', lowerLip: 'M50,77 Q55,79 60,78.5 Q65,78 70,77', tongueRy: 0, tongueCy: 78, teethUpperH: 1.5, teethLowerH: 0, cheekScale: 1.05 },
};

var VISEME_KEYS = Object.keys(VISEMES);

function startMouthAnimation(slideIndex) {
  stopMouthAnimation();
  var who = getPresenter(slideIndex);
  var svgEl = who === 'a' ? presenterA : (who === 'b' ? presenterB : presenterC);
  var els = {
    mouthHole: svgEl.querySelector('.presenter-mouth-hole'),
    lipUpper: svgEl.querySelector('.presenter-lip-upper'),
    lipLower: svgEl.querySelector('.presenter-lip-lower'),
    tongue: svgEl.querySelector('.presenter-tongue'),
    teethUpper: svgEl.querySelector('.presenter-teeth-upper'),
    teethLower: svgEl.querySelector('.presenter-teeth-lower'),
    jaw: svgEl.querySelector('.presenter-jaw'),
    cheekL: svgEl.querySelector('.presenter-cheek-l'),
    cheekR: svgEl.querySelector('.presenter-cheek-r'),
    head: svgEl.querySelector('.presenter-head'),
    browL: svgEl.querySelector('.presenter-brow-l'),
    browR: svgEl.querySelector('.presenter-brow-r'),
    pupilL: svgEl.querySelector('.presenter-pupil-l'),
    pupilR: svgEl.querySelector('.presenter-pupil-r'),
    glintL: svgEl.querySelector('.presenter-glint-l'),
    glintR: svgEl.querySelector('.presenter-glint-r'),
    lidL: svgEl.querySelector('.presenter-lid-l'),
    lidR: svgEl.querySelector('.presenter-lid-r'),
  };
  if (!els.mouthHole) return;

  presenterBubble.classList.add('speaking');

  var smoothLevel = 0, smoothLow = 0, smoothMid = 0, smoothHigh = 0;
  var prevLevel = 0, rawLevel = 0;
  var frameCount = 0;
  var currentViseme = 'rest';
  var targetViseme = 'rest';
  var visemeBlend = 1; // 0=current, 1=target (start fully at target)
  var visemeHoldFrames = 0;
  var silenceFrames = 0;
  var prevWasSilent = true;

  // Blinks: random 2-5s, occasional double-blink
  function scheduleBlink() {
    blinkTimer = setTimeout(function() {
      if (!mouthAnimFrame) return;
      function doBlink() {
        els.lidL.setAttribute('ry', '12'); els.lidR.setAttribute('ry', '12');
        els.lidL.setAttribute('cy', '56'); els.lidR.setAttribute('cy', '56');
        setTimeout(function() {
          els.lidL.setAttribute('ry', '0'); els.lidR.setAttribute('ry', '0');
          els.lidL.setAttribute('cy', '46'); els.lidR.setAttribute('cy', '46');
        }, 100 + Math.random() * 60);
      }
      doBlink();
      // 20% chance of double-blink
      if (Math.random() < 0.2) { setTimeout(doBlink, 250); }
      scheduleBlink();
    }, 1800 + Math.random() * 3500);
  }
  scheduleBlink();

  // Pupils: drift, sometimes look at "audience" (down-center)
  function schedulePupilMove() {
    pupilTimer = setTimeout(function() {
      if (!mouthAnimFrame) return;
      var dx, dy;
      if (Math.random() < 0.25) {
        // Look down at audience
        dx = (Math.random() - 0.5) * 2; dy = 2.5 + Math.random();
      } else if (Math.random() < 0.15) {
        // Look up (thinking)
        dx = (Math.random() - 0.5) * 2; dy = -2.5;
      } else {
        dx = (Math.random() - 0.5) * 5; dy = (Math.random() - 0.5) * 3;
      }
      els.pupilL.setAttribute('cx', (49 + dx).toFixed(1));
      els.pupilR.setAttribute('cx', (75 + dx).toFixed(1));
      els.pupilL.setAttribute('cy', (57 + dy).toFixed(1));
      els.pupilR.setAttribute('cy', (57 + dy).toFixed(1));
      els.glintL.setAttribute('cx', (50.5 + dx).toFixed(1));
      els.glintR.setAttribute('cx', (76.5 + dx).toFixed(1));
      els.glintL.setAttribute('cy', (55 + dy).toFixed(1));
      els.glintR.setAttribute('cy', (55 + dy).toFixed(1));
      setTimeout(function() {
        els.pupilL.setAttribute('cx', '49'); els.pupilR.setAttribute('cx', '75');
        els.pupilL.setAttribute('cy', '57'); els.pupilR.setAttribute('cy', '57');
        els.glintL.setAttribute('cx', '50.5'); els.glintR.setAttribute('cx', '76.5');
        els.glintL.setAttribute('cy', '55'); els.glintR.setAttribute('cy', '55');
      }, 500 + Math.random() * 600);
      schedulePupilMove();
    }, 1200 + Math.random() * 2500);
  }
  schedulePupilMove();

  // Eyebrows: raise on emphasis, occasional asymmetric quirk
  function scheduleBrowRaise() {
    browTimer = setTimeout(function() {
      if (!mouthAnimFrame) return;
      if (smoothLevel > 0.35) {
        if (Math.random() < 0.3) {
          // Asymmetric — one brow up (funny/skeptical)
          els.browL.setAttribute('y1', '42'); els.browL.setAttribute('y2', '41');
          // right stays or goes down
          els.browR.setAttribute('y1', '46'); els.browR.setAttribute('y2', '47');
        } else {
          els.browL.setAttribute('y1', '43'); els.browL.setAttribute('y2', '42');
          els.browR.setAttribute('y1', '42'); els.browR.setAttribute('y2', '43');
        }
        setTimeout(function() {
          els.browL.setAttribute('y1', '46'); els.browL.setAttribute('y2', '45');
          els.browR.setAttribute('y1', '45'); els.browR.setAttribute('y2', '46');
        }, 350 + Math.random() * 400);
      }
      scheduleBrowRaise();
    }, 600 + Math.random() * 1800);
  }
  scheduleBrowRaise();

  // Occasional squint when concentrating
  function scheduleSquint() {
    squintTimer = setTimeout(function() {
      if (!mouthAnimFrame) return;
      if (smoothLevel > 0.2 && Math.random() < 0.3) {
        els.lidL.setAttribute('ry', '4'); els.lidR.setAttribute('ry', '4');
        els.lidL.setAttribute('cy', '52'); els.lidR.setAttribute('cy', '52');
        setTimeout(function() {
          els.lidL.setAttribute('ry', '0'); els.lidR.setAttribute('ry', '0');
          els.lidL.setAttribute('cy', '46'); els.lidR.setAttribute('cy', '46');
        }, 300 + Math.random() * 300);
      }
      scheduleSquint();
    }, 3000 + Math.random() * 4000);
  }
  scheduleSquint();

  // Pick viseme based on audio analysis
  function pickViseme(level, low, mid, high) {
    if (level < 0.06) return 'rest';
    if (level < 0.12) return 'mbp'; // barely speaking, lips together

    var ratio_hl = high / (low + 1);
    var ratio_lm = low / (mid + 1);
    var r = Math.random();

    // Sibilants / "s", "sh", "z" → ee/fv
    if (ratio_hl > 0.9 && level > 0.15) {
      return r < 0.6 ? 'ee' : 'fv';
    }
    // Heavy low → ah/oo
    if (ratio_lm > 1.2 && level > 0.3) {
      return r < 0.5 ? 'ah' : (r < 0.8 ? 'oo' : 'wr');
    }
    // Medium level → cycle through shapes
    if (level > 0.5) {
      // Loud — big shapes
      var loud = ['ah', 'ee', 'oo', 'th', 'uh'];
      return loud[Math.floor(r * loud.length)];
    }
    if (level > 0.25) {
      var med = ['uh', 'ee', 'fv', 'wr', 'mbp', 'smirk'];
      return med[Math.floor(r * med.length)];
    }
    // Quiet
    var quiet = ['uh', 'mbp', 'rest', 'wr'];
    return quiet[Math.floor(r * quiet.length)];
  }

  function applyViseme(v, level) {
    var s = VISEMES[v];
    if (!s) return;

    // Mouth hole (dark interior)
    els.mouthHole.setAttribute('rx', s.holeRx.toFixed(1));
    els.mouthHole.setAttribute('ry', (s.holeRy * Math.max(level * 1.3, 0.3)).toFixed(1));
    els.mouthHole.setAttribute('cy', s.holeCy.toFixed(1));

    // Lips
    els.lipUpper.setAttribute('d', s.upperLip);
    els.lipLower.setAttribute('d', s.lowerLip);

    // Jaw drop
    var jawY = 80 + s.jawDy * Math.min(level * 1.5, 1);
    els.jaw.setAttribute('cy', jawY.toFixed(1));

    // Tongue
    var tRy = s.tongueRy * Math.min(level * 1.5, 1);
    els.tongue.setAttribute('ry', tRy.toFixed(1));
    els.tongue.setAttribute('cy', s.tongueCy.toFixed(1));
    els.tongue.setAttribute('rx', (3 + tRy * 0.5).toFixed(1));

    // Teeth
    var tuh = s.teethUpperH * Math.min(level * 1.8, 1);
    var tlh = s.teethLowerH * Math.min(level * 1.5, 1);
    els.teethUpper.setAttribute('height', tuh.toFixed(1));
    els.teethUpper.setAttribute('y', (s.holeCy - s.holeRy * 0.6).toFixed(1));
    els.teethUpper.setAttribute('x', (60 - s.holeRx * 0.45).toFixed(1));
    els.teethUpper.setAttribute('width', (s.holeRx * 0.9).toFixed(1));
    els.teethLower.setAttribute('height', tlh.toFixed(1));
    els.teethLower.setAttribute('y', (s.holeCy + s.holeRy * 0.3).toFixed(1));
    els.teethLower.setAttribute('x', (60 - s.holeRx * 0.4).toFixed(1));
    els.teethLower.setAttribute('width', (s.holeRx * 0.8).toFixed(1));

    // Cheek puff/squish
    var cs = s.cheekScale;
    els.cheekL.setAttribute('r', (5 * cs).toFixed(1));
    els.cheekR.setAttribute('r', (5 * cs).toFixed(1));
    var cheekOp = 0.25 + (cs > 1 ? 0.2 : 0);
    els.cheekL.setAttribute('opacity', cheekOp.toFixed(2));
    els.cheekR.setAttribute('opacity', cheekOp.toFixed(2));
  }

  function animate() {
    analyser.getByteFrequencyData(analyserData);
    frameCount++;

    // Frequency bands
    var lowSum = 0, midSum = 0, highSum = 0;
    for (var i = 2; i < 8; i++) lowSum += analyserData[i];
    for (var i = 8; i < 22; i++) midSum += analyserData[i];
    for (var i = 22; i < 45; i++) highSum += analyserData[i];
    var lowAvg = lowSum / 6, midAvg = midSum / 14, highAvg = highSum / 23;

    // Energy detection with fast attack, slow release
    var rawLevel = Math.min((lowAvg * 0.35 + midAvg * 0.4 + highAvg * 0.25) / 120, 1);
    if (rawLevel > smoothLevel) {
      smoothLevel = smoothLevel * 0.3 + rawLevel * 0.7; // fast attack
    } else {
      smoothLevel = smoothLevel * 0.85 + rawLevel * 0.15; // slow release
    }
    smoothLow = smoothLow * 0.6 + lowAvg * 0.4;
    smoothMid = smoothMid * 0.6 + midAvg * 0.4;
    smoothHigh = smoothHigh * 0.6 + highAvg * 0.4;
    var level = smoothLevel;

    // Track silence for lip smack on restart
    if (level < 0.06) {
      silenceFrames++;
      prevWasSilent = true;
    } else {
      if (prevWasSilent && silenceFrames > 8) {
        // Coming out of silence → quick lip smack (mbp → chosen)
        targetViseme = 'mbp';
        visemeHoldFrames = 3;
      }
      silenceFrames = 0;
      prevWasSilent = false;
    }

    // Pick new viseme when hold expires
    visemeHoldFrames--;
    if (visemeHoldFrames <= 0) {
      currentViseme = targetViseme;
      targetViseme = pickViseme(level, smoothLow, smoothMid, smoothHigh);
      visemeHoldFrames = 3 + Math.floor(Math.random() * 5);
      visemeBlend = 0;
    }

    // Blend towards target
    visemeBlend = Math.min(1, visemeBlend + 0.2);

    // Apply the target viseme (blending handled by frame-rate smoothing)
    applyViseme(targetViseme, level);

    // Head movement: bob + tilt + slight forward lean when loud
    if (els.head) {
      var bob = Math.sin(frameCount * 0.07) * level * 2;
      var tilt = Math.sin(frameCount * 0.025) * (0.5 + level * 1.5);
      var lean = level > 0.4 ? (level - 0.4) * 3 : 0;
      els.head.setAttribute('transform',
        'translate(0,' + (bob - lean * 0.5).toFixed(2) + ') rotate(' + tilt.toFixed(2) + ',60,60)');
    }

    // Shockwave + ring pulse on audio spikes
    var spike = rawLevel - prevLevel;
    if (spike > 0.25 && frameCount > 10) {
      var ring = document.getElementById('presenter-ring');
      if (ring) {
        ring.classList.remove('pulse');
        void ring.offsetWidth;
        ring.classList.add('pulse');
        setTimeout(function() { ring.classList.remove('pulse'); }, 300);
      }
      var sw = document.getElementById('presenter-shockwave-' + (frameCount % 2 === 0 ? '1' : '2'));
      if (sw) {
        sw.classList.remove('fire');
        void sw.offsetWidth;
        sw.classList.add('fire');
        setTimeout(function() { sw.classList.remove('fire'); }, 550);
      }
    }

    prevLevel = rawLevel;
    mouthAnimFrame = requestAnimationFrame(animate);
  }
  mouthAnimFrame = requestAnimationFrame(animate);
}

function stopMouthAnimation() {
  if (mouthAnimFrame) { cancelAnimationFrame(mouthAnimFrame); mouthAnimFrame = null; }
  if (blinkTimer) { clearTimeout(blinkTimer); blinkTimer = null; }
  if (pupilTimer) { clearTimeout(pupilTimer); pupilTimer = null; }
  if (browTimer) { clearTimeout(browTimer); browTimer = null; }
  if (squintTimer) { clearTimeout(squintTimer); squintTimer = null; }
  presenterBubble.classList.remove('speaking');
  var ring = document.getElementById('presenter-ring');
  if (ring) ring.classList.remove('pulse');
  // Reset to rest viseme
  var rest = VISEMES.rest;
  document.querySelectorAll('.presenter-mouth-hole').forEach(function(m) { m.setAttribute('rx', '1'); m.setAttribute('ry', '0.5'); m.setAttribute('cy', '76'); });
  document.querySelectorAll('.presenter-lip-upper').forEach(function(l) { l.setAttribute('d', rest.upperLip); });
  document.querySelectorAll('.presenter-lip-lower').forEach(function(l) { l.setAttribute('d', rest.lowerLip); });
  document.querySelectorAll('.presenter-tongue').forEach(function(t) { t.setAttribute('ry', '0'); });
  document.querySelectorAll('.presenter-teeth-upper, .presenter-teeth-lower').forEach(function(t) { t.setAttribute('height', '0'); });
  document.querySelectorAll('.presenter-jaw').forEach(function(j) { j.setAttribute('cy', '80'); });
  document.querySelectorAll('.presenter-cheek-l, .presenter-cheek-r').forEach(function(c) { c.setAttribute('r', '5'); c.setAttribute('opacity', '0.35'); });
  document.querySelectorAll('.presenter-lid-l, .presenter-lid-r').forEach(function(l) { l.setAttribute('ry', '0'); });
  document.querySelectorAll('.presenter-head').forEach(function(h) { h.setAttribute('transform', ''); });
  document.querySelectorAll('.presenter-brow-l').forEach(function(b) { b.setAttribute('y1', '46'); b.setAttribute('y2', '45'); });
  document.querySelectorAll('.presenter-brow-r').forEach(function(b) { b.setAttribute('y1', '45'); b.setAttribute('y2', '46'); });
  document.querySelectorAll('.presenter-pupil-l').forEach(function(p) { p.setAttribute('cx', '49'); p.setAttribute('cy', '57'); });
  document.querySelectorAll('.presenter-pupil-r').forEach(function(p) { p.setAttribute('cx', '75'); p.setAttribute('cy', '57'); });
  document.querySelectorAll('.presenter-glint-l').forEach(function(g) { g.setAttribute('cx', '50.5'); g.setAttribute('cy', '55'); });
  document.querySelectorAll('.presenter-glint-r').forEach(function(g) { g.setAttribute('cx', '76.5'); g.setAttribute('cy', '55'); });
}

// Hook into startAudio to drive the avatar
var _origStartAudioForPresenter = startAudio;
startAudio = function(audio, si, gen) {
  showPresenter(si);
  connectAudioToAnalyser(audio);
  // Start mouth animation once audio is actually playing
  var onPlay = function() {
    if (gen === audioGeneration) startMouthAnimation(si);
  };
  audio.addEventListener('playing', onPlay, { once: true });
  audio.addEventListener('ended', function() {
    if (gen === audioGeneration) {
      stopMouthAnimation();
      // Hide after a delay (unless next slide starts)
      setTimeout(function() {
        if (gen === audioGeneration) hidePresenter();
      }, 2000);
    }
  }, { once: true });
  _origStartAudioForPresenter(audio, si, gen);
};

// Hide presenter when audio is toggled off
var _origStopForPresenter = killAllAudio;
killAllAudio = function() {
  stopMouthAnimation();
  _origStopForPresenter();
};

// ========================================
// PLAY OVERLAY
// ========================================
var playOverlay = document.getElementById('play-overlay');
var playOverlayBtn = document.getElementById('play-overlay-btn');
function beginPresentation() { playOverlay.classList.add('hidden'); startBgMusic(); playSlideAudio(0); }

(function() {
  var t = new Audio('presentation-audio/slide-01.mp3'); t.volume = 0;
  var p = t.play();
  if (p) p.then(function() { t.pause(); t.src = ''; beginPresentation(); }).catch(function() { t.src = ''; playOverlay.classList.remove('hidden'); });
})();

playOverlayBtn.addEventListener('click', beginPresentation);
document.addEventListener('keydown', function sk(e) {
  if (!playOverlay.classList.contains('hidden') && (e.key === 'Enter' || e.key === ' ')) {
    e.preventDefault(); beginPresentation(); document.removeEventListener('keydown', sk);
  }
});
