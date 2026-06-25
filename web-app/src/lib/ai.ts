export async function sendChatCompletion(prompt: string): Promise<string> {
  const provider = localStorage.getItem('ai_provider') || 'google';
  const model = localStorage.getItem('ai_model') || (provider === 'google' ? 'models/gemini-1.5-flash' : 'google/gemma-3-27b-it:free');
  const googleKey = localStorage.getItem('ai_api_key_google') || '';
  const openrouterKey = localStorage.getItem('ai_api_key_openrouter') || '';

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
