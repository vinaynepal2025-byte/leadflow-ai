// Multi-provider AI layer — Claude (Anthropic), Gemini (Google), or
// OpenRouter (which itself proxies many models). Which one runs is chosen
// by AI_PROVIDER in .env, so switching providers needs no code change.
//
// Each provider needs its own API key from its own console:
//   claude     -> ANTHROPIC_API_KEY   (console.anthropic.com)
//   gemini     -> GEMINI_API_KEY      (aistudio.google.com/apikey)
//   openrouter -> OPENROUTER_API_KEY  (openrouter.ai/keys)

const Anthropic = require('@anthropic-ai/sdk');

const DEFAULT_MODELS = {
  claude: 'claude-sonnet-4-5',
  gemini: 'gemini-2.0-flash',
  openrouter: 'anthropic/claude-3.5-sonnet',
};

function activeProvider() {
  return (process.env.AI_PROVIDER || 'claude').toLowerCase();
}

function activeModel() {
  return process.env.AI_MODEL || DEFAULT_MODELS[activeProvider()] || DEFAULT_MODELS.claude;
}

/// Sends a single prompt and returns plain text. Every caller in the app
/// goes through this one function, so adding/swapping providers never
/// touches feature code.
async function generateText(prompt, { maxTokens = 600 } = {}) {
  const provider = activeProvider();

  if (provider === 'claude') {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error('Claude not configured. Set ANTHROPIC_API_KEY in .env (or switch AI_PROVIDER).');
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model: activeModel(),
      max_tokens: maxTokens,
      messages: [{ role: 'user', content: prompt }],
    });
    return response.content.find((b) => b.type === 'text')?.text || '';
  }

  if (provider === 'gemini') {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new Error('Gemini not configured. Set GEMINI_API_KEY in .env (get one at aistudio.google.com/apikey).');
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${activeModel()}:generateContent?key=${apiKey}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: maxTokens },
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(`Gemini request failed: ${JSON.stringify(data)}`);
    return data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  }

  if (provider === 'openrouter') {
    const apiKey = process.env.OPENROUTER_API_KEY;
    if (!apiKey) throw new Error('OpenRouter not configured. Set OPENROUTER_API_KEY in .env (get one at openrouter.ai/keys).');
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: activeModel(),
        max_tokens: maxTokens,
        messages: [{ role: 'user', content: prompt }],
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(`OpenRouter request failed: ${JSON.stringify(data)}`);
    return data.choices?.[0]?.message?.content || '';
  }

  throw new Error(`Unknown AI_PROVIDER "${provider}". Use: claude, gemini, or openrouter.`);
}

/// Same as generateText but parses a JSON response, tolerating the
/// ```json fences models often add.
async function generateJson(prompt, options) {
  const text = await generateText(prompt, options);
  let clean = text.replace(/```json|```/g, '').trim();
  try {
    return JSON.parse(clean);
  } catch (err) {
    const match = clean.match(/(\[[\s\S]*\]|\{[\s\S]*\})/);
    if (match) {
      try {
        return JSON.parse(match[1]);
      } catch (_) {
        // fall through to the descriptive error below
      }
    }
    throw new Error(`AI response was not valid JSON (${err.message}). Raw response started with: "${clean.slice(0, 120)}"`);
  }
}

module.exports = { generateText, generateJson, activeProvider, activeModel, DEFAULT_MODELS };
