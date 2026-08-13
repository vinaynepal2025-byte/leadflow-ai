// Lead 360 — Unified Lead Intelligence Core (Phase 1 of the Meta-OS
// interconnection layer).
//
// Every other module (Documents, Fees, Admissions, Visa, Travel, Consent,
// Meetings, Reminders, Offers, Communications, Scoring) already exists and
// works, but each one only knows about itself. This service is the first
// layer that reads across ALL of them for one lead, turns that into a
// single prioritized alert list ("what needs attention right now, and in
// which module"), and hands the whole picture to the AI for one synthesized
// narrative + one recommended next action — instead of each module having
// its own disconnected "AI Insight" button.
//
// Deliberately read-only and additive: this does not change any existing
// table or route. leads.js / documents.js / fees.js / etc. are all
// untouched. Composition over addition — this is a new aggregation layer,
// not a new source of truth.

const db = require('../db');
const { scoreLead, loadConfig } = require('./leadScoring');
const { generateJson } = require('./aiProvider');

function daysBetween(a, b) {
  return Math.round((new Date(b).getTime() - new Date(a).getTime()) / 86400000);
}

const REQUIRED_CONSENT_TYPES = ['data_processing'];

async function buildLead360(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) return null;

  const [
    scoreConfig,
    fees,
    documents,
    applications,
    offers,
    visaApps,
    travelPlans,
    consentRows,
    meetings,
    reminders,
    communications,
  ] = await Promise.all([
    loadConfig(db, tenantId),
    db.prepare('SELECT * FROM fee_payments WHERE tenant_id = ? AND lead_id = ?').all(tenantId, leadId),
    db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND lead_id = ?').all(tenantId, leadId),
    db.prepare('SELECT * FROM admission_applications WHERE tenant_id = ? AND lead_id = ?').all(tenantId, leadId),
    db.prepare('SELECT * FROM offers WHERE tenant_id = ? AND lead_id = ? ORDER BY given_at DESC').all(tenantId, leadId),
    db.prepare('SELECT * FROM visa_applications WHERE tenant_id = ? AND lead_id = ?').all(tenantId, leadId),
    db.prepare('SELECT * FROM travel_plans WHERE tenant_id = ? AND lead_id = ?').all(tenantId, leadId),
    db.prepare('SELECT * FROM consent_records WHERE tenant_id = ? AND lead_id = ? ORDER BY recorded_at DESC').all(tenantId, leadId),
    db.prepare('SELECT * FROM meetings WHERE tenant_id = ? AND lead_id = ?').all(tenantId, leadId),
    db.prepare("SELECT * FROM reminders WHERE tenant_id = ? AND lead_id = ? AND status = 'pending'").all(tenantId, leadId),
    db.prepare('SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tenantId, leadId),
  ]);

  const score = await scoreLead(db, tenantId, lead, scoreConfig);

  const now = Date.now();
  const alerts = [];

  // ---------- Fees ----------
  const pendingFees = fees.filter((f) => f.status === 'pending');
  const overdueFees = pendingFees.filter((f) => f.due_date && new Date(f.due_date).getTime() < now);
  const pendingTotal = pendingFees.reduce((s, f) => s + Number(f.amount || 0), 0);
  if (overdueFees.length > 0) {
    alerts.push({
      severity: 'critical',
      module: 'admissions_fees',
      message: `${overdueFees.length} fee installment(s) overdue, totalling ₹${overdueFees.reduce((s, f) => s + Number(f.amount || 0), 0)}`,
    });
  } else if (pendingFees.length > 0) {
    const soonest = pendingFees.slice().sort((a, b) => new Date(a.due_date) - new Date(b.due_date))[0];
    if (soonest?.due_date && daysBetween(now, soonest.due_date) <= 7) {
      alerts.push({
        severity: 'warning',
        module: 'admissions_fees',
        message: `₹${soonest.amount} due in ${Math.max(0, daysBetween(now, soonest.due_date))} day(s)`,
      });
    }
  }

  // ---------- Documents ----------
  const rejectedDocs = documents.filter((d) => d.status === 'rejected');
  const pendingDocs = documents.filter((d) => d.status === 'pending');
  if (rejectedDocs.length > 0) {
    alerts.push({
      severity: 'critical',
      module: 'documents',
      message: `${rejectedDocs.length} document(s) rejected — needs re-upload`,
    });
  }
  if (pendingDocs.length > 0) {
    alerts.push({
      severity: 'info',
      module: 'documents',
      message: `${pendingDocs.length} document(s) awaiting verification`,
    });
  }

  // ---------- Visa ----------
  for (const v of visaApps) {
    if (v.status === 'Rejected') {
      alerts.push({ severity: 'critical', module: 'visa_travel_student', message: `${v.country} visa rejected` });
    } else if (v.interview_date && daysBetween(now, v.interview_date) >= 0 && daysBetween(now, v.interview_date) <= 7) {
      alerts.push({
        severity: 'warning',
        module: 'visa_travel_student',
        message: `${v.country} visa interview in ${daysBetween(now, v.interview_date)} day(s)`,
      });
    }

    // Cross-check this visa's required-document checklist (Phase 3)
    // against what's actually in Documents — closes the loop so a
    // missing document surfaces here even before the counselor thinks
    // to check the Visa tab.
    if (v.status !== 'Approved' && v.status !== 'Rejected') {
      const required = await db.prepare(
        'SELECT doc_type FROM visa_checklist_items WHERE tenant_id = ? AND country = ? AND visa_type = ?'
      ).all(tenantId, v.country, v.visa_type);
      if (required.length > 0) {
        const docsByType = new Set(documents.filter((d) => d.status !== 'rejected').map((d) => d.doc_type.trim().toLowerCase()));
        const missing = required.filter((r) => !docsByType.has(r.doc_type.trim().toLowerCase()));
        if (missing.length > 0) {
          alerts.push({
            severity: missing.length === required.length ? 'warning' : 'info',
            module: 'visa_travel_student',
            message: `${v.country} visa checklist: ${missing.length}/${required.length} document(s) still missing`,
          });
        }
      }
    }
  }

  // ---------- Travel ----------
  for (const t of travelPlans) {
    if (t.departure_date && daysBetween(now, t.departure_date) >= 0 && daysBetween(now, t.departure_date) <= 14
        && !t.pickup_arranged) {
      alerts.push({
        severity: 'warning',
        module: 'visa_travel_student',
        message: `Departure in ${daysBetween(now, t.departure_date)} day(s) — airport pickup not arranged yet`,
      });
    }
  }

  // ---------- Consent / Compliance ----------
  const grantedTypes = new Set(
    consentRows.filter((c) => c.granted).map((c) => c.consent_type)
  );
  const missingRequired = REQUIRED_CONSENT_TYPES.filter((t) => !grantedTypes.has(t));
  if (missingRequired.length > 0) {
    alerts.push({
      severity: 'warning',
      module: 'consent_compliance',
      message: `Missing required consent: ${missingRequired.join(', ')}`,
    });
  }

  // ---------- Meetings ----------
  const noShows = meetings.filter((m) => m.status === 'no-show').length;
  if (noShows >= 2) {
    alerts.push({
      severity: 'warning',
      module: 'meetings',
      message: `${noShows} no-shows on record — consider a different channel/time`,
    });
  }

  // ---------- Reminders ----------
  const overdueReminders = reminders.filter((r) => r.due_at && new Date(r.due_at).getTime() < now);
  if (overdueReminders.length > 0) {
    alerts.push({
      severity: 'critical',
      module: 'activity_timeline',
      message: `${overdueReminders.length} overdue follow-up reminder(s) — we're the bottleneck`,
    });
  }

  // ---------- Offers ----------
  const activeOffers = offers.filter((o) => o.status === 'active');

  // ---------- Communication staleness ----------
  if (communications.length > 0) {
    const lastContact = communications[0].created_at;
    const gap = daysBetween(lastContact, now);
    if (gap > 14) {
      alerts.push({ severity: 'warning', module: 'calling_cockpit', message: `No contact in ${gap} days` });
    }
  } else {
    alerts.push({ severity: 'info', module: 'calling_cockpit', message: 'Never contacted' });
  }

  const severityRank = { critical: 0, warning: 1, info: 2 };
  alerts.sort((a, b) => severityRank[a.severity] - severityRank[b.severity]);

  const snapshot = {
    lead: { full_name: lead.full_name, stage: lead.stage },
    score: { value: score.score, temperature: score.temperature },
    fees: { pending_count: pendingFees.length, overdue_count: overdueFees.length, pending_total: pendingTotal },
    documents: { total: documents.length, pending: pendingDocs.length, rejected: rejectedDocs.length },
    applications: applications.map((a) => ({ institution: a.institution_name, status: a.application_status })),
    offers: activeOffers.map((o) => ({ text: o.offer_text, amount: o.amount })),
    visa: visaApps.map((v) => ({ country: v.country, status: v.status })),
    travel: travelPlans.map((t) => ({ departure_date: t.departure_date, pickup_arranged: !!t.pickup_arranged })),
    consent_missing: missingRequired,
    meetings_no_show: noShows,
    overdue_reminders: overdueReminders.length,
    days_since_contact: communications.length ? daysBetween(communications[0].created_at, now) : null,
  };

  let ai = null;
  try {
    const prompt = `You are the senior counselor's assistant for an education admissions consultancy, looking at ONE lead's complete cross-department picture in a single glance (engagement, fees, documents, applications, visa, travel, compliance, meetings).

Lead snapshot (JSON): ${JSON.stringify(snapshot)}

Alerts already computed by the system (do not repeat these verbatim, synthesize around them): ${JSON.stringify(alerts)}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "headline": "one sentence, the single most important thing about this lead right now, referencing a specific fact from the snapshot",
  "narrative": "2-3 sentences connecting signals ACROSS modules (e.g. fees + visa timeline + engagement) into one coherent read of where this admission stands",
  "top_action": "the ONE highest-leverage next step, specific to this lead",
  "risk_level": "low | medium | high"
}`;
    ai = await generateJson(prompt, { maxTokens: 1200 });
  } catch (err) {
    ai = { error: err.message };
  }

  return {
    lead_id: leadId,
    score: score.score,
    temperature: score.temperature,
    alerts,
    active_offers: activeOffers,
    snapshot,
    ai,
  };
}

module.exports = { buildLead360 };
