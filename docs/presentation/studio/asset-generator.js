// ========================================
// ASSET GENERATOR — HuggingFace API
// TTS audio + image generation
// ========================================

class AssetGenerator {
  constructor(hfToken) {
    this.hfToken = hfToken || '';
  }

  setToken(token) {
    this.hfToken = token;
  }

  isConfigured() {
    return !!this.hfToken;
  }

  // Generate narration audio using Edge TTS via HF
  async generateAudio(text, { voice = 'en-US-GuyNeural', rate = '-10%', pitch = '-5Hz' } = {}) {
    if (!this.hfToken) throw new Error('HuggingFace token required for audio generation');

    // Use the edge-tts space or a TTS model on HF
    // We'll use the microsoft/speecht5_tts model as fallback
    try {
      const resp = await fetch('https://api-inference.huggingface.co/models/facebook/mms-tts-eng', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.hfToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ inputs: text })
      });

      if (!resp.ok) {
        const err = await resp.text();
        throw new Error(`TTS API error: ${err}`);
      }

      const blob = await resp.blob();
      return URL.createObjectURL(blob);
    } catch (e) {
      console.warn('TTS generation failed:', e.message);
      return null;
    }
  }

  // Generate image using FLUX.1-schnell on HF
  async generateImage(prompt) {
    if (!this.hfToken) throw new Error('HuggingFace token required for image generation');

    try {
      const resp = await fetch('https://api-inference.huggingface.co/models/black-forest-labs/FLUX.1-schnell', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.hfToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          inputs: prompt,
          parameters: { width: 1024, height: 576 }
        })
      });

      if (!resp.ok) {
        const err = await resp.text();
        throw new Error(`Image API error: ${err}`);
      }

      const blob = await resp.blob();
      return URL.createObjectURL(blob);
    } catch (e) {
      console.warn('Image generation failed:', e.message);
      return null;
    }
  }

  // Generate all audio for a presentation
  async generateAllAudio(narrations, onProgress) {
    const results = [];
    for (let i = 0; i < narrations.length; i++) {
      if (onProgress) onProgress(i, narrations.length);
      const url = await this.generateAudio(narrations[i]);
      results.push(url);
    }
    if (onProgress) onProgress(narrations.length, narrations.length);
    return results;
  }
}

window.AssetGenerator = AssetGenerator;
