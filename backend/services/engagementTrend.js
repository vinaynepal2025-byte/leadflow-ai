// backend/services/engagementTrend.js
// Rule-based engagement-trend detector — deliberately NOT an AI call.
// Same design philosophy as leadScoring.js: explainable, instant, zero
// per-lead cost. Detects "silent churn" — a lead still replying, but
// replies getting shorter/slower, which raw reply-COUNT (used elsewhere
// in scoring.js) doesn't catch on its own.

/// communications: array of { direction, channel, body, created_at },
/// same shape cockpit.js and aiAnalysis.js already read.
function computeEngagementTrend(communications) {
  const inbound = communications
    .filter((c) => c.direction === 'inbound' && c.channel !== 'note')
    .map((c) => ({ ...c, created_at: new Date(c.created_at), length: (c.body || '').trim().length }))
    .sort((a, b) => a.created_at - b.created_at);

  if (inbound.length === 0) {
    return { trend: 'unknown', reasoning: 'No replies from this lead yet.' };
  }

  const daysSinceLastReply = Math.floor((Date.now() - inbound[inbound.length - 1].created_at.getTime()) / 86400000);
  if (daysSinceLastReply > 21) {
    return { trend: 'cold', reasoning: `No reply in ${daysSinceLastReply} days.` };
  }

  if (inbound.length < 4) {
    // Not enough history for a before/after comparison — a single data
    // point isn't a trend, so this stays honest rather than guessing.
    return { trend: 'unknown', reasoning: 'Not enough reply history yet to detect a trend (need at least 4 replies).' };
  }

  const mid = Math.floor(inbound.length / 2);
  const earlier = inbound.slice(0, mid);
  const recent = inbound.slice(mid);

  const avg = (arr) => arr.reduce((sum, c) => sum + c.length, 0) / arr.length;
  const avgEarlierLen = avg(earlier);
  const avgRecentLen = avg(recent);

  // Average time between one of OUR outbound messages and the lead's next
  // inbound reply — a growing gap is as strong a churn signal as shorter replies.
  const replyGap = (subset) => {
    const gaps = [];
    for (const reply of subset) {
      const priorOutbound = communications
        .filter((c) => c.direction === 'outbound' && new Date(c.created_at) < reply.created_at)
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))[0];
      if (priorOutbound) {
        gaps.push((reply.created_at - new Date(priorOutbound.created_at)) / 3600000); // hours
      }
    }
    return gaps.length > 0 ? gaps.reduce((s, g) => s + g, 0) / gaps.length : null;
  };
  const earlierGap = replyGap(earlier);
  const recentGap = replyGap(recent);

  const lengthRatio = avgEarlierLen > 0 ? avgRecentLen / avgEarlierLen : 1;
  const gapRatio = earlierGap && recentGap && earlierGap > 0 ? recentGap / earlierGap : 1;

  const signals = [];
  if (lengthRatio < 0.6) signals.push(`replies got shorter (avg ${Math.round(avgEarlierLen)}→${Math.round(avgRecentLen)} chars)`);
  if (lengthRatio > 1.4) signals.push(`replies got longer (avg ${Math.round(avgEarlierLen)}→${Math.round(avgRecentLen)} chars) — more engaged`);
  if (gapRatio > 1.8) signals.push(`taking longer to reply (avg ${Math.round(earlierGap)}h→${Math.round(recentGap)}h)`);
  if (gapRatio < 0.55) signals.push(`replying faster (avg ${Math.round(earlierGap)}h→${Math.round(recentGap)}h) — more engaged`);

  const cooling = lengthRatio < 0.6 || gapRatio > 1.8;
  const rising = lengthRatio > 1.4 || gapRatio < 0.55;

  let trend = 'steady';
  if (cooling && !rising) trend = 'cooling';
  else if (rising && !cooling) trend = 'rising';

  return {
    trend,
    reasoning: signals.length > 0 ? signals.join('; ') : 'Reply pattern is stable — no significant change detected.',
  };
}

module.exports = { computeEngagementTrend };
