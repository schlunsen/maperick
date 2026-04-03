// ========================================
// LLM CLIENT — Multi-provider support
// Anthropic (Claude) + OpenAI-compatible (OpenAI, DeepSeek, GLM, Ollama)
// ========================================

const LLM_PROVIDERS = {
  anthropic: {
    name: 'Claude (Anthropic)',
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-sonnet-4-20250514',
    models: ['claude-sonnet-4-20250514', 'claude-opus-4-20250514', 'claude-haiku-4-20250514'],
    format: 'anthropic'
  },
  openai: {
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com',
    defaultModel: 'gpt-4o',
    models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo'],
    format: 'openai'
  },
  deepseek: {
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    format: 'openai'
  },
  glm: {
    name: 'GLM (Zhipu)',
    baseUrl: 'https://open.bigmodel.cn/api/paas',
    defaultModel: 'glm-4-plus',
    models: ['glm-4-plus', 'glm-4'],
    format: 'openai'
  },
  ollama: {
    name: 'Ollama (Local)',
    baseUrl: 'http://localhost:11434',
    defaultModel: 'llama3',
    models: ['llama3', 'mistral', 'codellama', 'gemma2'],
    format: 'openai',
    noAuth: true
  },
  custom: {
    name: 'Custom (OpenAI-compatible)',
    baseUrl: '',
    defaultModel: '',
    models: [],
    format: 'openai'
  }
};

class LLMClient {
  constructor() {
    this.loadSettings();
  }

  loadSettings() {
    try {
      const saved = JSON.parse(localStorage.getItem('wp_llm_settings') || '{}');
      this.provider = saved.provider || 'anthropic';
      this.apiKey = saved.apiKey || '';
      this.model = saved.model || '';
      this.customBaseUrl = saved.customBaseUrl || '';
      this.customModel = saved.customModel || '';
    } catch {
      this.provider = 'anthropic';
      this.apiKey = '';
      this.model = '';
      this.customBaseUrl = '';
      this.customModel = '';
    }
  }

  saveSettings() {
    localStorage.setItem('wp_llm_settings', JSON.stringify({
      provider: this.provider,
      apiKey: this.apiKey,
      model: this.model,
      customBaseUrl: this.customBaseUrl,
      customModel: this.customModel
    }));
  }

  getProviderConfig() {
    const config = { ...LLM_PROVIDERS[this.provider] };
    if (this.provider === 'custom') {
      config.baseUrl = this.customBaseUrl;
      config.defaultModel = this.customModel;
    }
    return config;
  }

  getModel() {
    return this.model || this.getProviderConfig().defaultModel;
  }

  isConfigured() {
    const config = this.getProviderConfig();
    if (config.noAuth) return true;
    return !!this.apiKey;
  }

  // Stream or non-stream call to LLM
  async chat(messages, { system = '', onChunk = null, temperature = 0.7 } = {}) {
    const config = this.getProviderConfig();
    const model = this.getModel();

    if (config.format === 'anthropic') {
      return this._callAnthropic(messages, { system, onChunk, temperature, model, config });
    } else {
      return this._callOpenAI(messages, { system, onChunk, temperature, model, config });
    }
  }

  async _callAnthropic(messages, { system, onChunk, temperature, model, config }) {
    const body = {
      model,
      max_tokens: 8192,
      temperature,
      messages: messages.map(m => ({ role: m.role, content: m.content }))
    };
    if (system) body.system = system;
    if (onChunk) body.stream = true;

    const resp = await fetch(`${config.baseUrl}/v1/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': this.apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true'
      },
      body: JSON.stringify(body)
    });

    if (!resp.ok) {
      const err = await resp.text();
      throw new Error(`Anthropic API error ${resp.status}: ${err}`);
    }

    if (onChunk) {
      return this._streamAnthropic(resp, onChunk);
    } else {
      const data = await resp.json();
      return data.content[0].text;
    }
  }

  async _streamAnthropic(resp, onChunk) {
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let full = '';
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop();

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          try {
            const data = JSON.parse(line.slice(6));
            if (data.type === 'content_block_delta' && data.delta?.text) {
              full += data.delta.text;
              onChunk(data.delta.text, full);
            }
          } catch {}
        }
      }
    }
    return full;
  }

  async _callOpenAI(messages, { system, onChunk, temperature, model, config }) {
    const msgs = [];
    if (system) msgs.push({ role: 'system', content: system });
    msgs.push(...messages.map(m => ({ role: m.role, content: m.content })));

    const body = {
      model,
      temperature,
      messages: msgs,
      max_tokens: 8192
    };
    if (onChunk) body.stream = true;

    const headers = { 'Content-Type': 'application/json' };
    if (!config.noAuth) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    const baseUrl = config.baseUrl.replace(/\/+$/, '');
    const endpoint = config.format === 'openai' && this.provider === 'ollama'
      ? `${baseUrl}/v1/chat/completions`
      : `${baseUrl}/v1/chat/completions`;

    const resp = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(body)
    });

    if (!resp.ok) {
      const err = await resp.text();
      throw new Error(`API error ${resp.status}: ${err}`);
    }

    if (onChunk) {
      return this._streamOpenAI(resp, onChunk);
    } else {
      const data = await resp.json();
      return data.choices[0].message.content;
    }
  }

  async _streamOpenAI(resp, onChunk) {
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let full = '';
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop();

      for (const line of lines) {
        if (line.startsWith('data: ') && line !== 'data: [DONE]') {
          try {
            const data = JSON.parse(line.slice(6));
            const delta = data.choices?.[0]?.delta?.content;
            if (delta) {
              full += delta;
              onChunk(delta, full);
            }
          } catch {}
        }
      }
    }
    return full;
  }

  // Test connection
  async testConnection() {
    try {
      const result = await this.chat(
        [{ role: 'user', content: 'Say "connected" and nothing else.' }],
        { temperature: 0 }
      );
      return { ok: true, message: result.trim() };
    } catch (e) {
      return { ok: false, message: e.message };
    }
  }
}

// Export as global
window.LLMClient = LLMClient;
window.LLM_PROVIDERS = LLM_PROVIDERS;
