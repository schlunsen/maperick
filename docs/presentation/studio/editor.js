// ========================================
// EDITOR — Per-slide editing with LLM chat
// ========================================

(function () {
  const llm = new LLMClient();

  // Load project
  let project;
  try {
    project = JSON.parse(localStorage.getItem('wp_current_project'));
  } catch {}

  if (!project || !project.slides || !project.slides.length) {
    document.getElementById('editor-app').innerHTML = `
      <div style="display:flex;align-items:center;justify-content:center;height:100vh;flex-direction:column;gap:1rem;">
        <h2 style="color:var(--text);">No presentation loaded</h2>
        <p style="color:var(--text-muted);">Create one first or load an existing project.</p>
        <a href="creator.html" style="color:var(--rose);">Go to Creator</a>
      </div>`;
    return;
  }

  let currentSlide = 0;
  const chatHistories = project.slides.map(() => []);
  let isGenerating = false;

  // --- DOM refs ---
  const preview = document.getElementById('slide-preview');
  const slideNav = document.getElementById('slide-nav');
  const slideCounter = document.getElementById('ed-slide-counter');
  const htmlEditor = document.getElementById('html-editor');
  const chatMessages = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  const chatSend = document.getElementById('chat-send');
  const applyBtn = document.getElementById('apply-html');
  const undoBtn = document.getElementById('undo-btn');
  const addSlideBtn = document.getElementById('add-slide-btn');
  const deleteSlideBtn = document.getElementById('delete-slide-btn');
  const exportBtn = document.getElementById('export-btn');
  const presentBtn = document.getElementById('present-btn');

  // --- Slide thumbnails ---
  function renderSlideNav() {
    slideNav.innerHTML = project.slides.map((s, i) => `
      <button class="slide-thumb ${i === currentSlide ? 'active' : ''}" data-index="${i}">
        <span class="thumb-num">${i + 1}</span>
      </button>
    `).join('');
    slideNav.querySelectorAll('.slide-thumb').forEach(btn => {
      btn.addEventListener('click', () => {
        goToSlide(parseInt(btn.dataset.index));
      });
    });
  }

  function goToSlide(index) {
    currentSlide = index;
    renderSlideNav();
    renderPreview();
    renderHtmlEditor();
    renderChat();
    slideCounter.textContent = `Slide ${index + 1} / ${project.slides.length}`;
  }

  // --- Preview ---
  function renderPreview() {
    const slide = project.slides[currentSlide];
    preview.innerHTML = `
      <section class="slide slide-active" data-index="${currentSlide}">
        ${slide.html}
      </section>
    `;
    // Trigger any animations
    const section = preview.querySelector('.slide');
    if (section) {
      section.querySelectorAll('[data-delay]').forEach((el, i) => {
        setTimeout(() => el.classList.add('visible'), 200 + i * 150);
      });
      section.querySelectorAll('.stagger-item').forEach(item => {
        const delay = parseInt(item.dataset.stagger || 0) * 400 + 200;
        setTimeout(() => item.classList.add('visible'), delay);
      });
    }
  }

  // --- HTML Editor ---
  function renderHtmlEditor() {
    htmlEditor.value = project.slides[currentSlide].html;
  }

  // --- Apply manual edits ---
  applyBtn.addEventListener('click', () => {
    project.slides[currentSlide].html = htmlEditor.value;
    saveProject();
    renderPreview();
  });

  // --- Undo ---
  const undoStack = project.slides.map(s => [s.html]);

  undoBtn.addEventListener('click', () => {
    const stack = undoStack[currentSlide];
    if (stack.length > 1) {
      stack.pop();
      project.slides[currentSlide].html = stack[stack.length - 1];
      saveProject();
      renderPreview();
      renderHtmlEditor();
    }
  });

  function pushUndo() {
    undoStack[currentSlide].push(project.slides[currentSlide].html);
    if (undoStack[currentSlide].length > 20) undoStack[currentSlide].shift();
  }

  // --- Chat ---
  function renderChat() {
    const history = chatHistories[currentSlide];
    chatMessages.innerHTML = history.length ? history.map(m => `
      <div class="chat-msg chat-${m.role}">
        <span class="chat-role">${m.role === 'user' ? 'You' : 'AI'}</span>
        <div class="chat-content">${escapeHtml(m.content)}</div>
      </div>
    `).join('') : `
      <div class="chat-placeholder">
        Ask the AI to modify this slide. Try:<br/>
        "Make the title bigger"<br/>
        "Add a 3-column stats section"<br/>
        "Change to a two-column layout"
      </div>
    `;
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  async function sendChat() {
    const msg = chatInput.value.trim();
    if (!msg || isGenerating) return;
    if (!llm.isConfigured()) { alert('Configure LLM settings first'); return; }

    isGenerating = true;
    chatSend.disabled = true;
    chatInput.value = '';

    // Add user message
    chatHistories[currentSlide].push({ role: 'user', content: msg });
    renderChat();

    // Build messages for LLM
    const currentHtml = project.slides[currentSlide].html;
    const messages = [
      {
        role: 'user',
        content: `Here is the current HTML for slide ${currentSlide + 1}:\n\n\`\`\`html\n${currentHtml}\n\`\`\`\n\nModification request: ${msg}\n\nReturn ONLY the complete modified HTML for this slide (starting with <div class="slide-content ...">). No explanation, no markdown code blocks — just the raw HTML.`
      }
    ];

    // Add streaming response
    const aiMsgDiv = document.createElement('div');
    aiMsgDiv.className = 'chat-msg chat-assistant';
    aiMsgDiv.innerHTML = '<span class="chat-role">AI</span><div class="chat-content streaming">Thinking...</div>';
    chatMessages.appendChild(aiMsgDiv);
    chatMessages.scrollTop = chatMessages.scrollHeight;
    const contentDiv = aiMsgDiv.querySelector('.chat-content');

    try {
      const result = await llm.chat(messages, {
        system: SLIDE_SYSTEM_PROMPT + '\n\nIMPORTANT: Return ONLY raw HTML. No markdown, no code blocks, no explanation.',
        temperature: 0.5,
        onChunk: (chunk, full) => {
          contentDiv.textContent = full;
          chatMessages.scrollTop = chatMessages.scrollHeight;
        }
      });

      // Clean result
      let cleanHtml = result.replace(/```html?\s*/g, '').replace(/```\s*/g, '').trim();

      // Save undo state and apply
      pushUndo();
      project.slides[currentSlide].html = cleanHtml;
      saveProject();

      chatHistories[currentSlide].push({ role: 'assistant', content: 'Slide updated! (Applied to preview)' });
      renderChat();
      renderPreview();
      renderHtmlEditor();

    } catch (e) {
      chatHistories[currentSlide].push({ role: 'assistant', content: `Error: ${e.message}` });
      renderChat();
    }

    isGenerating = false;
    chatSend.disabled = false;
    contentDiv.classList.remove('streaming');
  }

  chatSend.addEventListener('click', sendChat);
  chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendChat(); }
  });

  // --- Slide management ---
  addSlideBtn.addEventListener('click', () => {
    project.slides.push({
      html: '<div class="slide-content slide-center-layout">\n  <h2 class="slide-heading">New Slide</h2>\n  <p class="slide-body">Add your content here.</p>\n</div>',
      narration: '',
      audioUrl: null
    });
    undoStack.push(['']);
    chatHistories.push([]);
    saveProject();
    goToSlide(project.slides.length - 1);
  });

  deleteSlideBtn.addEventListener('click', () => {
    if (project.slides.length <= 1) { alert('Cannot delete the last slide'); return; }
    if (!confirm(`Delete slide ${currentSlide + 1}?`)) return;
    project.slides.splice(currentSlide, 1);
    undoStack.splice(currentSlide, 1);
    chatHistories.splice(currentSlide, 1);
    saveProject();
    goToSlide(Math.min(currentSlide, project.slides.length - 1));
  });

  // --- Export ---
  exportBtn.addEventListener('click', () => {
    const slideSections = project.slides.map((s, i) => `
    <!-- Slide ${i + 1} -->
    <section class="slide${i === 0 ? ' slide-active' : ''}" data-index="${i}">
      ${s.html}
    </section>`).join('\n');

    const dots = project.slides.map((_, i) => `      <button class="dot${i === 0 ? ' active' : ''}" data-slide="${i}"></button>`).join('\n');

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${project.title || 'Presentation'}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet" />
    <link rel="stylesheet" href="engine/presentation-styles.css" />
    <script src="engine/three.min.js"><\/script>
</head>
<body>
  <canvas id="bg-canvas"></canvas>
  <div class="presentation" id="presentation">
    <div class="slide-counter" id="slide-counter">1 / ${project.slides.length}</div>
    <div class="progress-dots" id="progress-dots">
${dots}
    </div>
    <button class="nav-arrow nav-prev" id="nav-prev"><svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 18l-6-6 6-6"/></svg></button>
    <button class="nav-arrow nav-next" id="nav-next"><svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg></button>
${slideSections}
  </div>
<script src="engine/presentation-script.js"><\/script>
<script src="engine/presentation-bg.js"><\/script>
</body>
</html>`;

    const blob = new Blob([html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = (project.title || 'presentation').toLowerCase().replace(/\s+/g, '-') + '.html';
    a.click();
    URL.revokeObjectURL(url);
  });

  // --- Present ---
  presentBtn.addEventListener('click', () => {
    // Build a temporary preview
    localStorage.setItem('wp_preview_mode', 'true');
    exportBtn.click(); // For now, just download
  });

  // --- Save ---
  function saveProject() {
    localStorage.setItem('wp_current_project', JSON.stringify(project));
  }

  // --- Keyboard shortcuts ---
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT') return;
    if (e.key === 'ArrowLeft' && currentSlide > 0) goToSlide(currentSlide - 1);
    if (e.key === 'ArrowRight' && currentSlide < project.slides.length - 1) goToSlide(currentSlide + 1);
    if (e.key === 'z' && (e.ctrlKey || e.metaKey)) undoBtn.click();
  });

  // --- Init ---
  renderSlideNav();
  goToSlide(0);
})();
