// ========================================
// CREATOR — Questionnaire + Generation Pipeline
// ========================================

(function () {
  const llm = new LLMClient();
  const assets = new AssetGenerator();

  // --- Settings Panel ---
  const settingsBtn = document.getElementById('settings-btn');
  const settingsPanel = document.getElementById('settings-panel');
  const providerSelect = document.getElementById('provider-select');
  const modelSelect = document.getElementById('model-select');
  const apiKeyInput = document.getElementById('api-key');
  const customUrlGroup = document.getElementById('custom-url-group');
  const customUrlInput = document.getElementById('custom-url');
  const testBtn = document.getElementById('test-connection');
  const testResult = document.getElementById('test-result');
  const saveSettingsBtn = document.getElementById('save-settings');

  settingsBtn.addEventListener('click', () => {
    settingsPanel.classList.toggle('open');
  });

  // Populate provider dropdown
  Object.entries(LLM_PROVIDERS).forEach(([key, config]) => {
    const opt = document.createElement('option');
    opt.value = key;
    opt.textContent = config.name;
    providerSelect.appendChild(opt);
  });

  function updateModels() {
    const config = LLM_PROVIDERS[providerSelect.value];
    modelSelect.innerHTML = '';
    const models = config.models.length ? config.models : [config.defaultModel || 'custom'];
    models.forEach(m => {
      const opt = document.createElement('option');
      opt.value = m;
      opt.textContent = m;
      modelSelect.appendChild(opt);
    });
    customUrlGroup.style.display = providerSelect.value === 'custom' ? 'block' : 'none';
    apiKeyInput.closest('.field').style.display = config.noAuth ? 'none' : '';
  }

  providerSelect.addEventListener('change', updateModels);

  // Load saved settings
  providerSelect.value = llm.provider;
  updateModels();
  if (llm.model) modelSelect.value = llm.model;
  apiKeyInput.value = llm.apiKey;
  if (llm.customBaseUrl) customUrlInput.value = llm.customBaseUrl;

  saveSettingsBtn.addEventListener('click', () => {
    llm.provider = providerSelect.value;
    llm.apiKey = apiKeyInput.value;
    llm.model = modelSelect.value;
    llm.customBaseUrl = customUrlInput.value;
    llm.customModel = modelSelect.value;
    llm.saveSettings();
    settingsPanel.classList.remove('open');
  });

  testBtn.addEventListener('click', async () => {
    llm.provider = providerSelect.value;
    llm.apiKey = apiKeyInput.value;
    llm.model = modelSelect.value;
    llm.customBaseUrl = customUrlInput.value;
    testResult.textContent = 'Testing...';
    testResult.className = 'test-result';
    const result = await llm.testConnection();
    testResult.textContent = result.ok ? 'Connected!' : `Failed: ${result.message}`;
    testResult.className = 'test-result ' + (result.ok ? 'success' : 'error');
  });

  // --- HF Token ---
  const hfTokenInput = document.getElementById('hf-token');
  const hfSaved = localStorage.getItem('wp_hf_token') || '';
  hfTokenInput.value = hfSaved;

  // --- Photo uploads ---
  const photoInput = document.getElementById('photo-upload');
  const photoPreview = document.getElementById('photo-preview');
  let uploadedPhotos = []; // { name, dataUrl }

  photoInput.addEventListener('change', (e) => {
    const files = Array.from(e.target.files);
    files.forEach(file => {
      const reader = new FileReader();
      reader.onload = (ev) => {
        uploadedPhotos.push({ name: file.name, dataUrl: ev.target.result });
        renderPhotoPreviews();
      };
      reader.readAsDataURL(file);
    });
  });

  function renderPhotoPreviews() {
    photoPreview.innerHTML = uploadedPhotos.map((p, i) => `
      <div class="photo-thumb">
        <img src="${p.dataUrl}" alt="${p.name}" />
        <button class="photo-remove" data-index="${i}">&times;</button>
        <span class="photo-name">${p.name}</span>
      </div>
    `).join('');
    photoPreview.querySelectorAll('.photo-remove').forEach(btn => {
      btn.addEventListener('click', () => {
        uploadedPhotos.splice(parseInt(btn.dataset.index), 1);
        renderPhotoPreviews();
      });
    });
  }

  // --- Generation ---
  const generateBtn = document.getElementById('generate-btn');
  const progressSection = document.getElementById('progress-section');
  const progressLog = document.getElementById('progress-log');
  const progressBar = document.getElementById('progress-bar-fill');

  function log(msg) {
    const line = document.createElement('div');
    line.className = 'log-line';
    line.textContent = msg;
    progressLog.appendChild(line);
    progressLog.scrollTop = progressLog.scrollHeight;
  }

  function setProgress(pct) {
    progressBar.style.width = pct + '%';
  }

  generateBtn.addEventListener('click', async () => {
    const topic = document.getElementById('topic').value.trim();
    const description = document.getElementById('description').value.trim();
    const audience = document.getElementById('audience').value.trim();
    const tone = document.getElementById('tone').value;
    const slideCount = document.getElementById('slide-count').value;

    if (!topic) { alert('Please enter a topic'); return; }
    if (!llm.isConfigured()) { alert('Please configure your LLM provider in settings'); return; }

    // Save HF token
    const hfToken = hfTokenInput.value.trim();
    if (hfToken) {
      localStorage.setItem('wp_hf_token', hfToken);
      assets.setToken(hfToken);
    }

    // Show progress
    progressSection.classList.add('active');
    progressLog.innerHTML = '';
    generateBtn.disabled = true;

    try {
      // Step 1: Plan slides
      log('Planning slide structure...');
      setProgress(10);

      const planPrompt = `Create a presentation about: "${topic}"

Description: ${description || 'No additional description provided.'}
Target audience: ${audience || 'General audience'}
Tone: ${tone}
Number of slides: ${slideCount}
${uploadedPhotos.length ? `Available photos: ${uploadedPhotos.map(p => p.name).join(', ')}` : 'No photos provided.'}

Generate the slide plan as JSON.`;

      const planRaw = await llm.chat(
        [{ role: 'user', content: planPrompt }],
        { system: CREATOR_SYSTEM_PROMPT, temperature: 0.7 }
      );

      let plan;
      try {
        // Extract JSON from response (handle markdown code blocks)
        const jsonMatch = planRaw.match(/```(?:json)?\s*([\s\S]*?)```/) || [null, planRaw];
        plan = JSON.parse(jsonMatch[1].trim());
      } catch (e) {
        // Try to find JSON object in response
        const braceMatch = planRaw.match(/\{[\s\S]*\}/);
        if (braceMatch) {
          plan = JSON.parse(braceMatch[0]);
        } else {
          throw new Error('Could not parse slide plan from LLM response');
        }
      }

      log(`Planned ${plan.slides.length} slides: "${plan.title}"`);
      setProgress(20);

      // Step 2: Generate HTML for each slide
      const slideHtmls = [];
      const narrations = [];

      for (let i = 0; i < plan.slides.length; i++) {
        const slide = plan.slides[i];
        log(`Building slide ${i + 1}/${plan.slides.length}: ${slide.title}...`);
        setProgress(20 + (i / plan.slides.length) * 50);

        const slidePrompt = `Create slide ${i + 1} of ${plan.slides.length} for a presentation titled "${plan.title}".

Slide title: ${slide.title}
Layout: ${slide.layout}
Purpose: ${slide.purpose}
Suggested components: ${(slide.components || []).join(', ')}
${uploadedPhotos.length && i === 0 ? 'Use the title-icon SVG pattern for the first slide.' : ''}

Return ONLY the inner HTML of the <section> element. Start with <div class="slide-content ${slide.layout}"> and end with </div>.`;

        const html = await llm.chat(
          [{ role: 'user', content: slidePrompt }],
          { system: SLIDE_SYSTEM_PROMPT, temperature: 0.6 }
        );

        // Clean up response — strip markdown code blocks if present
        let cleanHtml = html.replace(/```html?\s*/g, '').replace(/```\s*/g, '').trim();
        slideHtmls.push(cleanHtml);
        narrations.push(slide.narration || '');
      }

      log('All slides generated!');
      setProgress(75);

      // Step 3: Generate audio (if HF token provided)
      let audioUrls = [];
      if (hfToken && narrations.some(n => n)) {
        log('Generating narration audio...');
        audioUrls = await assets.generateAllAudio(
          narrations,
          (current, total) => {
            setProgress(75 + (current / total) * 20);
            if (current < total) log(`Audio ${current + 1}/${total}...`);
          }
        );
        log('Audio generation complete!');
      }

      setProgress(95);

      // Step 4: Save project and redirect to editor
      const project = {
        title: plan.title,
        createdAt: new Date().toISOString(),
        slides: slideHtmls.map((html, i) => ({
          html,
          narration: narrations[i] || '',
          audioUrl: audioUrls[i] || null
        })),
        photos: uploadedPhotos,
        plan: plan
      };

      localStorage.setItem('wp_current_project', JSON.stringify(project));
      log('Saved! Opening editor...');
      setProgress(100);

      setTimeout(() => {
        window.location.href = 'editor.html';
      }, 800);

    } catch (e) {
      log(`Error: ${e.message}`);
      console.error(e);
      generateBtn.disabled = false;
    }
  });
})();
