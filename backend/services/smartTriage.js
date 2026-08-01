// Smart Triage — when a lead messages, this decides: answer instantly
// from the Knowledge Base, or escalate to a human. It never invents an
// answer — if nothing in the Knowledge Base is a confident match, it
// escalates rather than guessing, because a wrong answer about visas or
// fees does more damage than a short delay.

const db = require('../db');
const { generateJson } = require('./aiProvider');
const { createNotification } = require('../routes/notifications');
const { sendWhatsAppMessage } = require('./whatsapp');

/// Simple, dependency-free keyword overlap as a first pass — works with
/// zero configuration. If an AI provider is configured, its judgment
/// refines the decision; if not, the app still functions on this alone.
function keywordScore(message, article) {
  const words = (text) => new Set(text.toLowerCase().match(/[a-z0-9]{3,}/g) || []);
  const msgWords = words(message);
  const articleWords = words(`${article.title} ${article.content}`);
  let overlap = 0;
  for (const w of msgWords) if (articleWords.has(w)) overlap++;
  return msgWords.size > 0 ? overlap / msgWords.size : 0;
}

async function triageMessage(tenantId, leadId, message) {
  const articles = await db.prepare('SELECT * FROM knowledge_articles WHERE tenant_id = ?').all(tenantId);
  if (articles.length === 0) {
    return { action: 'escalate', reason: 'No Knowledge Base articles configured yet' };
  }

  const ranked = articles
    .map((a) => ({ article: a, score: keywordScore(message, a) }))
    .sort((a, b) => b.score - a.score);

  const best = ranked[0];
  // A low keyword-overlap match is likely a coincidence, not a real answer —
  // e.g. "fee" appearing in an unrelated article shouldn't trigger a reply.
  if (!best || best.score < 0.15) {
    return { action: 'escalate', reason: 'No confident Knowledge Base match', best_guess_article: best?.article.title };
  }

  // If an AI provider is configured, ask it to actually draft the reply
  // grounded in that specific article — much better than pasting the raw
  // article text at someone. If no key is set, we still send something
  // useful: the article's own content, verbatim, clearly attributed.
  try {
    const drafted = await generateJson(
      `A prospective student asked: "${message}"\n\n` +
      `Here is the ONLY source you may use to answer — our official article "${best.article.title}":\n${best.article.content}\n\n` +
      `If this article genuinely answers the question, write a warm, brief WhatsApp reply (2-4 sentences) using ONLY facts from it. ` +
      `If it does NOT actually answer the question, say so.\n\n` +
      `Respond ONLY with JSON: {"can_answer": true|false, "reply": "..."}`,
      { maxTokens: 300 },
    );
    if (drafted.can_answer && drafted.reply) {
      return { action: 'auto_reply', reply: drafted.reply, source_article: best.article.title, confidence: best.score };
    }
    return { action: 'escalate', reason: 'AI determined the matched article does not answer the question', best_guess_article: best.article.title };
  } catch {
    // No AI configured, or it failed — fall back to a safe, honest reply:
    // the article content itself, not a guess.
    return {
      action: 'auto_reply',
      reply: `${best.article.content}\n\n(If this doesn't fully answer your question, a counselor will follow up shortly.)`,
      source_article: best.article.title,
      confidence: best.score,
    };
  }
}

/// Called from the WhatsApp webhook after an inbound message is logged.
/// Runs the triage, and either sends the auto-reply (if WhatsApp is
/// configured) or raises an escalation notification for a counselor.
async function handleInboundForTriage(tenantId, lead, message) {
  if (!lead.phone) return;

  const result = await triageMessage(tenantId, lead.id, message);

  if (result.action === 'auto_reply') {
    try {
      await sendWhatsAppMessage(lead.phone, result.reply);
      await db.prepare(`
        INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
        VALUES (?, ?, ?, 'whatsapp', 'outbound', ?, 'AI Auto-Reply')
      `).run(require('crypto').randomUUID(), tenantId, lead.id, `[Auto-reply, source: ${result.source_article}] ${result.reply}`);
    } catch (err) {
      // WhatsApp not configured or send failed — escalate instead of
      // silently losing the reply.
      await createNotification(tenantId, {
        title: `Reply ready but couldn't send: ${lead.full_name}`,
        body: `Drafted: "${result.reply}" — WhatsApp not configured (${err.message})`,
        linkType: 'lead', linkId: lead.id,
      });
    }
  } else {
    await createNotification(tenantId, {
      title: `Needs a human: ${lead.full_name}`,
      body: `"${message}" — ${result.reason}`,
      linkType: 'lead', linkId: lead.id,
    });
  }

  return result;
}

module.exports = { triageMessage, handleInboundForTriage };
