// Duplicate Intelligence — fuzzy matching, entirely local (no paid API).
// Two signals, combined:
//  1. Phone: normalized to last 10 digits (handles +91/91/0-prefix variants
//     that exact-string matching would miss)
//  2. Name: Levenshtein edit-distance similarity (catches "Rahul Sharma" vs
//     "Rahul Sharrma" typos) — a real, useful heuristic, not a placeholder.

function normalizePhone(phone) {
  if (!phone) return null;
  const digits = phone.replace(/[^0-9]/g, '');
  return digits.slice(-10); // last 10 digits, ignoring country code variance
}

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]);
    }
  }
  return dp[m][n];
}

function nameSimilarity(a, b) {
  const an = a.toLowerCase().trim();
  const bn = b.toLowerCase().trim();
  const dist = levenshtein(an, bn);
  const maxLen = Math.max(an.length, bn.length) || 1;
  return 1 - dist / maxLen; // 1.0 = identical, 0.0 = completely different
}

/// Returns candidate duplicates for a new lead being created, sorted by
/// confidence. Doesn't auto-merge anything — a human decides (Merge action
/// stays a UI decision, not an automatic silent action).
async function findDuplicates(db, tenantId, { full_name, phone }) {
  const allLeads = await db.prepare('SELECT id, full_name, phone FROM leads WHERE tenant_id = ?').all(tenantId);
  const normalizedNewPhone = normalizePhone(phone);

  const candidates = [];
  for (const lead of allLeads) {
    let score = 0;
    let reasons = [];

    if (normalizedNewPhone && normalizePhone(lead.phone) === normalizedNewPhone) {
      score = 1.0;
      reasons.push('exact phone match');
    } else if (full_name) {
      const sim = nameSimilarity(full_name, lead.full_name);
      if (sim >= 0.8) {
        score = sim;
        reasons.push(`name ${Math.round(sim * 100)}% similar`);
      }
    }

    if (score >= 0.8) {
      candidates.push({ lead_id: lead.id, full_name: lead.full_name, phone: lead.phone, score, reasons });
    }
  }

  return candidates.sort((a, b) => b.score - a.score);
}

module.exports = { findDuplicates, normalizePhone, nameSimilarity };
