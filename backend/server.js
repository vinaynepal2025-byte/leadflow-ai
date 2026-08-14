require('dotenv').config({ quiet: true });
require('./services/fontSetup');
const express = require('express');
const cors = require('cors');
const leadsRouter = require('./routes/leads');
const communicationsRouter = require('./routes/communications');
const whatsappRouter = require('./routes/whatsapp');
const whatsappLinkRouter = require('./routes/whatsappLink');
const whatsappWebhookRouter = require('./routes/whatsappWebhook');
const aiRouter = require('./routes/ai');
const { router: remindersRouter } = require('./routes/reminders');
const analyticsRouter = require('./routes/analytics');
const documentsRouter = require('./routes/documents');
const { router: authRouter } = require('./routes/auth');
const campaignsRouter = require('./routes/campaigns');
const tasksRouter = require('./routes/tasks');
const admissionsRouter = require('./routes/admissions');
const feesRouter = require('./routes/fees');
const { router: notificationsRouter } = require('./routes/notifications');
const leadsImportRouter = require('./routes/leadsImport');
const automationsRouter = require('./routes/automations');
const performanceRouter = require('./routes/performance');
const settingsRouter = require('./routes/settings');
const auditRouter = require('./routes/audit');
const knowledgeRouter = require('./routes/knowledge');
const emailRouter = require('./routes/email');
const callsRouter = require('./routes/calls');
const voiceNotesRouter = require('./routes/voiceNotes');
const calendarRouter = require('./routes/calendar');
const collegesRouter = require('./routes/colleges');
const leadsImportExcelRouter = require('./routes/leadsImportExcel');
const customFieldsRouter = require('./routes/customFields');
const pipelineStagesRouter = require('./routes/pipelineStages');
const meetingsRouter = require('./routes/meetings');
const journeyRouter = require('./routes/journey');
const captureRouter = require('./routes/capture');
const studentsRouter = require('./routes/students');
const scoringRouter = require('./routes/scoring');
const { router: socialRouter } = require('./routes/social');
const { randomUUID: shortLinkUuid } = require('crypto');
const alumniRouter = require('./routes/alumni');
const triageRouter = require('./routes/triage');
const paymentsRouter = require('./routes/payments');
const predictionsRouter = require('./routes/predictions');
const inboxRouter = require('./routes/inbox');
const complianceRouter = require('./routes/compliance');
const leadDetailSectionsRouter = require('./routes/leadDetailSections');
const leadNotesRouter = require('./routes/leadNotes');
const db = require('./db');

const app = express();
// Render terminates TLS in front of this app and forwards plain HTTP, so
// without this, req.protocol always reports 'http' -- every generated
// share link (/s/:code, /peer-reviews/pay/:id) would come out as
// http://... instead of https://... . Trusting the first proxy hop lets
// Express read X-Forwarded-Proto and report the real scheme.
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json());

// P0 SECURITY FIX -- Phase 1 (foundation, non-breaking). See
// middleware/auth.js for the full rationale. Additive only: requests
// with no/invalid token behave exactly as before; a valid token makes
// x-tenant-id trustworthy for every route below without touching them.
app.use(require('./middleware/auth').attachUser);

app.get('/health', (req, res) => res.json({ status: 'ok', product: 'LeadFlow AI' }));
app.use('/auth', authRouter);
app.use('/campaigns', campaignsRouter);
app.use('/tasks', tasksRouter);
app.use('/admissions', admissionsRouter);
app.use('/fees', feesRouter);
app.use('/notifications', notificationsRouter);
app.use('/automations', automationsRouter);
app.use('/performance', performanceRouter);
app.use('/settings', settingsRouter);
app.use('/audit', auditRouter);
app.use('/knowledge', knowledgeRouter);
app.use('/email', emailRouter);
app.use('/calls', callsRouter);
app.use('/voice-notes', voiceNotesRouter);
app.use('/calendar', calendarRouter);
app.use('/colleges', collegesRouter);
app.use('/custom-fields', customFieldsRouter);
app.use('/pipeline-stages', pipelineStagesRouter);
app.use('/meetings', meetingsRouter);
app.use('/journey', journeyRouter);
app.use('/capture', captureRouter);
app.use('/students', studentsRouter);
app.use('/scoring', scoringRouter);
app.use('/social', socialRouter);
app.use('/alumni', alumniRouter);
app.use('/triage', triageRouter);
app.use('/payments', paymentsRouter);
app.use('/review-providers', require('./routes/reviewProviders'));
app.use('/peer-reviews', require('./routes/peerReviews'));
app.use('/predictions', predictionsRouter);
app.use('/inbox', inboxRouter);
app.use('/compliance', complianceRouter);

// GET /s/:code — the public short link. Deliberately mounted at the root
// so shared URLs stay short enough for an Instagram bio. Records the click
// then forwards; a tracking failure must never block the redirect, since
// a broken link costs a real lead.
app.get('/s/:code', async (req, res) => {
  const link = await db.prepare('SELECT * FROM tracked_links WHERE short_code = ? AND active = 1').get(req.params.code);
  if (!link) return res.status(404).send('This link is no longer active.');

  try {
    await db.prepare('INSERT INTO link_clicks (id, link_id, tenant_id, referrer, user_agent) VALUES (?, ?, ?, ?, ?)')
      .run(shortLinkUuid(), link.id, link.tenant_id, req.get('referer') || null, req.get('user-agent') || null);
    await db.prepare('UPDATE tracked_links SET click_count = click_count + 1 WHERE id = ?').run(link.id);
  } catch (err) {
    console.error('Click tracking failed (redirect continues):', err.message);
  }

  res.redirect(link.destination);
});
app.use('/leads/import-excel', leadsImportExcelRouter);
app.use('/leads/import', leadsImportRouter);
app.use('/leads', leadsRouter);
app.use('/cockpit', require('./routes/cockpit'));
app.use('/leads-excel', require('./routes/leadsExcelV2'));
app.use('/flyers', require('./routes/flyers'));
app.use('/leads-folders', require('./routes/leadFolders'));
app.use('/lead-ads', require('./routes/leadAdsWebhook'));
app.use('/communications', communicationsRouter);
app.use('/whatsapp', whatsappRouter);
app.use('/whatsapp', whatsappLinkRouter);
app.use('/whatsapp', whatsappWebhookRouter);
app.use('/ai', aiRouter);
app.use('/reminders', remindersRouter);
app.use('/analytics', analyticsRouter);
app.use('/documents', documentsRouter);
app.use('/lead-detail-sections', leadDetailSectionsRouter);
app.use('/lead-notes', leadNotesRouter);
app.use('/tenant-logos', require('./routes/tenantLogos'));
app.use('/flyer-projects', require('./routes/flyerProjects'));
app.use('/share-targets', require('./routes/shareTargets'));
app.use('/call-prep', require('./routes/callPrep'));
app.use('/leads', require('./routes/leadTimeline'));
app.use('/lead360', require('./routes/lead360'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`LeadFlow AI backend running on port ${PORT}`));
