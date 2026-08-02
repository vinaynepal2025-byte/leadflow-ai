// AI Analysis service — reads a lead's conversation history and produces
// counseling-useful insight. Provider-agnostic: works with Claude, Gemini,
// or OpenRouter depending on AI_PROVIDER in .env (see aiProvider.js).

const { generateJson } = require('./aiProvider');

async function analyzeLead(lead, communications) {
  const history = communications
    .map((c) => `[${c.created_at}] ${c.direction} ${c.channel}: ${c.body || '(no text)'}`)
    .join('\n');

  const prompt = `You are a counseling-quality analyst for an education/career consultancy.
Given a lead's profile and their full interaction history, analyze it.

Lead: ${lead.full_name}, source: ${lead.source || 'unknown'}, current stage: ${lead.stage}
Notes on file: ${lead.notes || 'none'}

Interaction history (oldest first is not guaranteed; check timestamps):
${history || '(no interactions logged yet)'}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "summary": "2-3 sentence summary of where this relationship stands",
  "sentiment": "positive | neutral | negative | mixed",
  "buying_intent": "high | medium | low",
  "risk_flags": ["short phrases naming any concerns, e.g. 'no contact in 10 days'"],
  "suggested_next_action": "one concrete next step the counselor should take",
  "suggested_whatsapp_reply": "a ready-to-send WhatsApp message draft, warm and professional"
}`;

  return generateJson(prompt, { maxTokens: 2000 });
}

module.exports = { analyzeLead };
