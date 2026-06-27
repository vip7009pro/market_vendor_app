import api from './api';

export interface AiModelInfo {
  id: string;
  name: string;
}

export function presetModels(provider: 'google' | 'openrouter'): AiModelInfo[] {
  if (provider === 'google') {
    return [
      { id: 'models/gemini-2.0-flash', name: 'Gemini 2.0 Flash' },
      { id: 'models/gemini-2.0-flash-lite', name: 'Gemini 2.0 Flash Lite' },
      { id: 'models/gemini-1.5-flash', name: 'Gemini 1.5 Flash' },
      { id: 'models/gemma-4-31b-it', name: 'Gemma 4 31B IT' },
    ];
  } else {
    return [
      { id: 'google/gemma-3-27b-it:free', name: 'Google Gemma 3 27B IT (free)' },
      { id: 'nvidia/nemotron-3-nano-30b-a3b:free', name: 'NVIDIA Nemotron 3 (free)' },
      { id: 'deepseek/deepseek-chat-v3-0324:free', name: 'DeepSeek Chat V3 (free)' },
      { id: 'meta-llama/llama-4-maverick:free', name: 'Meta Llama 4 Maverick (free)' },
    ];
  }
}

export async function fetchAvailableModels(provider: 'google' | 'openrouter', apiKey: string): Promise<AiModelInfo[]> {
  if (!apiKey) {
    return presetModels(provider);
  }

  try {
    if (provider === 'openrouter') {
      const res = await fetch('https://openrouter.ai/api/v1/models', {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`
        }
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = await res.json();
      const data = body.data || [];
      const models = data.map((m: any) => ({
        id: m.id || '',
        name: m.name || m.id || '',
      })).filter((m: any) => m.id);
      
      // Sort alphabetically by name
      models.sort((a: any, b: any) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
      return models;
    } else {
      const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}&pageSize=100`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = await res.json();
      const data = body.models || [];
      const models = data
        .filter((m: any) => m.supportedGenerationMethods?.includes('generateContent'))
        .map((m: any) => ({
          id: m.name || '',
          name: m.displayName || m.name || '',
        }));
      
      // Sort alphabetically by name
      models.sort((a: any, b: any) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
      return models;
    }
  } catch (err) {
    console.warn(`Failed to fetch models from ${provider} API, using presets`, err);
    return presetModels(provider);
  }
}

export async function sendChatCompletion(prompt: string): Promise<string> {
  let provider = 'google';
  let googleKey = '';
  let openrouterKey = '';

  try {
    const dbSettings = await api.getAiSettings();
    if (dbSettings) {
      provider = dbSettings.provider || 'google';
      googleKey = dbSettings.googleKey || '';
      openrouterKey = dbSettings.openrouterKey || '';
    }
  } catch (err) {
    console.warn('Failed to load AI settings from DB, falling back to localStorage', err);
    if (typeof window !== 'undefined') {
      provider = localStorage.getItem('ai_provider') || 'google';
      googleKey = localStorage.getItem('ai_api_key_google') || '';
      openrouterKey = localStorage.getItem('ai_api_key_openrouter') || '';
    }
  }

  const model = (typeof window !== 'undefined' && localStorage.getItem('ai_model')) || (provider === 'google' ? 'models/gemini-1.5-flash' : 'google/gemma-3-27b-it:free');

  if (provider === 'google') {
    if (!googleKey) {
      throw new Error('Thiếu API key Google Gemini. Vui lòng vào Cấu hình hệ thống > Cấu hình AI để nhập key.');
    }
    
    const url = `https://generativelanguage.googleapis.com/v1beta/${model}:generateContent?key=${googleKey}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: prompt }
            ]
          }
        ],
        generationConfig: {
          responseMimeType: 'application/json'
        }
      })
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Google Gemini API Error (${res.status}): ${errText}`);
    }

    const data = await res.json();
    const candidates = data.candidates;
    if (!candidates || candidates.length === 0) {
      throw new Error('Gemini API không trả về kết quả nào.');
    }

    const parts = candidates[0].content?.parts || [];
    let resultText = '';
    // Gemma-4 thinking models support: skip thought parts and pick the last text part
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if (part.thought === true) continue;
      if (part.text && part.text.trim()) {
        resultText = part.text;
        break;
      }
    }

    if (!resultText) {
      throw new Error('Không tìm thấy nội dung văn bản trong kết quả Gemini.');
    }

    return resultText;
  } else {
    if (!openrouterKey) {
      throw new Error('Thiếu API key OpenRouter. Vui lòng vào Cấu hình hệ thống > Cấu hình AI để nhập key.');
    }

    const url = 'https://openrouter.ai/api/v1/chat/completions';
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${openrouterKey}`
      },
      body: JSON.stringify({
        model: model,
        messages: [
          { role: 'user', content: prompt }
        ]
      })
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`OpenRouter API Error (${res.status}): ${errText}`);
    }

    const data = await res.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error('OpenRouter không trả về nội dung chat completion.');
    }

    return content;
  }
}
