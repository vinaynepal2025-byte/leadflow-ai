// LeadFlow AI — Database Layer
// Note: SQLite used here for local development/prototyping only.
// Production target per VertiCore TSE-08 baseline = PostgreSQL.
// Swapping this file's implementation is the only change needed later —
// the API layer above never touches SQL directly (seam discipline).

const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(path.join(__dirname, 'leadflow.db'));

db.exec(`
  CREATE TABLE IF NOT EXISTS tenants (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    logo_url TEXT,
    theme_color TEXT DEFAULT '#2D5BFF',
    contact_email TEXT,
    contact_phone TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS leads (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    source TEXT,              -- e.g. Website, Walk-in, Referral, Facebook Ad
    stage TEXT NOT NULL DEFAULT 'New',  -- New -> Contacted -> Counseling -> Admission -> Closed/Lost
    assigned_to TEXT,         -- counselor name/id
    notes TEXT,
    parent_name TEXT,         -- Parent CRM: guardian contact (education vertical)
    parent_phone TEXT,
    parent_relation TEXT,     -- e.g. Father, Mother, Guardian
    custom_fields TEXT,       -- JSON object of tenant-defined field values
    referred_by_lead_id TEXT, -- an existing lead/student who referred this one
    referrer_name TEXT,       -- or a free-text referrer (agent, alumni, teacher)
    referrer_type TEXT,       -- student | parent | alumni | agent | staff | other
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_leads_tenant ON leads(tenant_id);
  CREATE INDEX IF NOT EXISTS idx_leads_stage ON leads(tenant_id, stage);

  -- Custom Fields Builder: no-code, tenant-defined extra fields on a lead
  -- (e.g. "Passport Number", "IELTS Score") without touching the schema.
  CREATE TABLE IF NOT EXISTS custom_field_definitions (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    field_key TEXT NOT NULL,      -- machine key, e.g. "ielts_score"
    label TEXT NOT NULL,          -- display label, e.g. "IELTS Score"
    field_type TEXT NOT NULL DEFAULT 'text',  -- text | number | date | select
    options TEXT,                 -- JSON array of choices, only for 'select'
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_fields_key ON custom_field_definitions(tenant_id, field_key);

  -- Communication Hub: one row per interaction (call, whatsapp, email, note)
  CREATE TABLE IF NOT EXISTS communications (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    channel TEXT NOT NULL,       -- call | whatsapp | email | sms | note
    direction TEXT NOT NULL,     -- inbound | outbound
    body TEXT,                   -- message text / call summary / note text
    created_by TEXT,             -- counselor name/id who logged it
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_comms_lead ON communications(tenant_id, lead_id);

  -- Reminder Engine: scheduled follow-ups per lead
  CREATE TABLE IF NOT EXISTS reminders (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    title TEXT NOT NULL,          -- e.g. "Follow up on scholarship docs"
    due_at TEXT NOT NULL,         -- ISO datetime
    assigned_to TEXT,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | done | missed
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_reminders_due ON reminders(tenant_id, status, due_at);

  -- Document Vault: files attached to a lead (passport, marksheet, etc.)
  CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    doc_type TEXT NOT NULL,        -- e.g. Passport, Marksheet, Photo, Certificate
    file_name TEXT NOT NULL,
    stored_path TEXT NOT NULL,     -- where the actual file lives on disk (v1) / object storage (production)
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | verified | rejected
    uploaded_by TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_documents_lead ON documents(tenant_id, lead_id);

  -- Users: counselors/admins who log into the app
  -- Note: v1 uses email+password with JWTs, tested and working end to end.
  -- Production target per VertiCore TSE-08 baseline is Keycloak/Zitadel —
  -- that's an infrastructure swap behind the same /auth API shape, not
  -- something this sandbox can run (needs a real Keycloak server).
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'counselor',  -- owner | admin | counselor
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(tenant_id, email);

  -- Campaign Manager: bulk outreach to a set of leads
  CREATE TABLE IF NOT EXISTS campaigns (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    message_template TEXT NOT NULL,  -- e.g. "Hi {{name}}, ..."
    status TEXT NOT NULL DEFAULT 'draft',  -- draft | sent
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS campaign_targets (
    id TEXT PRIMARY KEY,
    campaign_id TEXT NOT NULL REFERENCES campaigns(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    status TEXT NOT NULL DEFAULT 'pending'  -- pending | sent
  );

  CREATE INDEX IF NOT EXISTS idx_campaign_targets_campaign ON campaign_targets(campaign_id);

  -- Task Manager: general team todos, optionally tied to a lead
  CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT REFERENCES leads(id),
    title TEXT NOT NULL,
    due_at TEXT,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | done
    assigned_to TEXT,
    priority TEXT NOT NULL DEFAULT 'normal', -- low | normal | high
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_tasks_tenant ON tasks(tenant_id, status, due_at);

  -- Admission Tracker: university/college applications per lead
  -- (a lead can apply to multiple universities — one row per application)
  CREATE TABLE IF NOT EXISTS admission_applications (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    institution_name TEXT NOT NULL,
    course_name TEXT,
    intake TEXT,                 -- e.g. "Sep 2026", "Jan 2027"
    application_status TEXT NOT NULL DEFAULT 'Preparing',
      -- Preparing -> Submitted -> Under Review -> Offer -> Accepted -> Rejected -> Withdrawn
    scholarship_amount REAL,
    tuition_fee REAL,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_admissions_lead ON admission_applications(tenant_id, lead_id);

  -- Fee Tracker: installments/payments per lead (consultancy fee, tuition, etc.)
  CREATE TABLE IF NOT EXISTS fee_payments (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    fee_type TEXT NOT NULL,       -- e.g. "Consultancy Fee", "Tuition Installment 1"
    amount REAL NOT NULL,
    due_date TEXT,
    paid_date TEXT,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | paid | overdue | waived
    payment_method TEXT,          -- cash | bank transfer | card | UPI
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_fees_lead ON fee_payments(tenant_id, lead_id);

  -- Notification Center: in-app alerts for a user (or unassigned/tenant-wide)
  CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    user_id TEXT,                 -- null = tenant-wide notification
    title TEXT NOT NULL,
    body TEXT,
    link_type TEXT,                -- lead | reminder | document | fee | admission
    link_id TEXT,
    read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(tenant_id, user_id, read);

  -- Automation Hub: simple trigger -> condition -> action rules
  CREATE TABLE IF NOT EXISTS automation_rules (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    trigger_event TEXT NOT NULL,      -- lead.created | lead.stage_changed | document.rejected
    condition_field TEXT,             -- e.g. "stage" (only relevant for lead.stage_changed)
    condition_value TEXT,             -- e.g. "Admission"
    action_type TEXT NOT NULL,        -- create_reminder | create_notification
    action_config TEXT NOT NULL,      -- JSON string, e.g. {"title":"Follow up","offset_days":1}
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_automation_trigger ON automation_rules(tenant_id, trigger_event, enabled);

  -- Knowledge Base: internal articles/FAQs (university info, visa process, etc.)
  CREATE TABLE IF NOT EXISTS knowledge_articles (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT,               -- e.g. "Visa Process", "University Info", "Scholarships"
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_knowledge_tenant ON knowledge_articles(tenant_id, category);

  -- Call Manager: structured call outcomes (duration, result) beyond the
  -- generic Communication Hub log
  CREATE TABLE IF NOT EXISTS call_logs (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    duration_seconds INTEGER,
    outcome TEXT NOT NULL,   -- connected | no-answer | busy | wrong-number | voicemail
    notes TEXT,
    called_by TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_call_logs_lead ON call_logs(tenant_id, lead_id);

  -- Voice Notes: recorded audio attached to a lead, with optional
  -- transcription/summary (filled in once a speech-to-text key is configured)
  CREATE TABLE IF NOT EXISTS voice_notes (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    file_name TEXT NOT NULL,
    stored_path TEXT NOT NULL,
    transcript TEXT,
    ai_summary TEXT,
    recorded_by TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_voice_notes_lead ON voice_notes(tenant_id, lead_id);

  -- College CRM: universities/colleges the consultancy partners with
  CREATE TABLE IF NOT EXISTS colleges (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    country TEXT,
    contact_person TEXT,
    contact_email TEXT,
    commission_percent REAL,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_colleges_tenant ON colleges(tenant_id);

  -- Pipeline Builder: no-code, tenant-defined pipeline stages (replacing
  -- a fixed New/Contacted/.../Lost list with something each tenant can
  -- actually customize, per the product's "no redevelopment" promise).
  CREATE TABLE IF NOT EXISTS pipeline_stages (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    position INTEGER NOT NULL,
    color TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_pipeline_stages_tenant ON pipeline_stages(tenant_id, position);

  -- Meetings: counseling sessions, virtual/physical campus tours, parent
  -- meetings, demo classes. Distinct from call_logs (a phone call that
  -- happened) and reminders (a nudge to do something) — a meeting is a
  -- scheduled event with attendees, a place/link, and an outcome.
  CREATE TABLE IF NOT EXISTS meetings (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    meeting_type TEXT NOT NULL,     -- Counseling | Virtual Campus Tour | Physical Campus Visit | Parent Meeting | Demo Class | Other
    title TEXT NOT NULL,
    scheduled_at TEXT NOT NULL,
    duration_minutes INTEGER DEFAULT 30,
    mode TEXT NOT NULL DEFAULT 'online',   -- online | in-person
    meeting_link TEXT,              -- Zoom/Meet/WhatsApp video link for online
    location TEXT,                  -- campus/office address for in-person
    campus_name TEXT,               -- which campus is being toured
    host_name TEXT,                 -- counselor/campus rep conducting it
    attendees TEXT,                 -- JSON array: [{"name","role","phone"}] — student, parent, consultant
    status TEXT NOT NULL DEFAULT 'scheduled',  -- scheduled | completed | no-show | cancelled | rescheduled
    outcome_notes TEXT,             -- what happened, filled in after
    interest_level TEXT,            -- hot | warm | cold — post-tour read
    follow_up_required INTEGER NOT NULL DEFAULT 1,
    requested_by TEXT,              -- student | parent | consultant | campus — who asked for it
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_meetings_lead ON meetings(tenant_id, lead_id);
  CREATE INDEX IF NOT EXISTS idx_meetings_scheduled ON meetings(tenant_id, scheduled_at, status);

  -- Visa tracking: for study-abroad, this is where deals are won or lost.
  -- Kept separate from admission_applications because a student can hold
  -- an offer letter and still be mid-visa, and the timelines differ.
  CREATE TABLE IF NOT EXISTS visa_applications (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    country TEXT NOT NULL,
    visa_type TEXT,                  -- Student, Dependent, etc.
    status TEXT NOT NULL DEFAULT 'Not Started',
      -- Not Started -> Documents Pending -> Submitted -> Biometrics Done
      -- -> Interview Scheduled -> Approved -> Rejected -> Appealing
    application_number TEXT,
    submitted_date TEXT,
    interview_date TEXT,
    decision_date TEXT,
    embassy_location TEXT,
    rejection_reason TEXT,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_visa_lead ON visa_applications(tenant_id, lead_id);

  -- Travel & arrival: the last mile most CRMs drop entirely, but it's
  -- exactly when anxious parents call the consultancy most.
  CREATE TABLE IF NOT EXISTS travel_plans (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    departure_date TEXT,
    departure_city TEXT,
    arrival_date TEXT,
    arrival_city TEXT,
    airline TEXT,
    flight_number TEXT,
    accommodation TEXT,              -- hostel/apartment name
    pickup_arranged INTEGER NOT NULL DEFAULT 0,
    pickup_contact TEXT,
    status TEXT NOT NULL DEFAULT 'planning',  -- planning | booked | travelled | arrived
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_travel_lead ON travel_plans(tenant_id, lead_id);

  -- Public Lead Capture: each tenant can publish forms (website embed,
  -- QR code, Facebook lead ads, WhatsApp link) that create leads directly,
  -- with no counselor typing anything. Each form has its own public key
  -- so submissions can be attributed to the exact channel.
  CREATE TABLE IF NOT EXISTS capture_forms (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    public_key TEXT NOT NULL,        -- goes in the public URL; not guessable
    name TEXT NOT NULL,              -- "Website Contact Form", "Campus QR Poster"
    channel TEXT NOT NULL,           -- website | qr | facebook | whatsapp | other
    assign_to TEXT,                  -- auto-assign incoming leads to this counselor
    default_stage TEXT DEFAULT 'New',
    auto_reply_message TEXT,         -- instant WhatsApp/email acknowledgement text
    active INTEGER NOT NULL DEFAULT 1,
    submission_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_capture_public_key ON capture_forms(public_key);

  -- Student Lifecycle: once a lead is admitted they stop being a lead and
  -- become a student the consultancy stays responsible for — which is
  -- where referrals, testimonials and repeat business actually come from.
  CREATE TABLE IF NOT EXISTS students (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    student_code TEXT,               -- university roll/registration number
    institution_name TEXT,
    course_name TEXT,
    batch_year TEXT,
    current_semester INTEGER DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'enrolled',
      -- enrolled | on-leave | graduated | discontinued | transferred
    enrolled_date TEXT,
    expected_completion TEXT,
    local_contact TEXT,              -- guardian/contact in the host country
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_students_lead ON students(tenant_id, lead_id);

  -- Periodic check-ins with enrolled students — the ongoing relationship
  -- that turns one admission into a referral pipeline.
  CREATE TABLE IF NOT EXISTS student_checkins (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    student_id TEXT NOT NULL REFERENCES students(id),
    checkin_date TEXT DEFAULT (datetime('now')),
    wellbeing TEXT,                  -- good | okay | struggling
    academic_status TEXT,
    issues_raised TEXT,
    action_taken TEXT,
    conducted_by TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_checkins_student ON student_checkins(tenant_id, student_id);

  -- Per-tenant lead scoring weights. Consultancies genuinely differ in
  -- what predicts a conversion for them — for a campus-owned counselling
  -- desk a tour visit is everything, for an agent network a paid booking
  -- is. Stored as one JSON blob rather than a column per signal so new
  -- signals can be added without a schema migration.
  CREATE TABLE IF NOT EXISTS scoring_config (
    tenant_id TEXT PRIMARY KEY REFERENCES tenants(id),
    weights TEXT NOT NULL,        -- JSON: { signalKey: points }
    thresholds TEXT NOT NULL,     -- JSON: { hot: 70, warm: 40 }
    updated_at TEXT DEFAULT (datetime('now'))
  );

  -- Trackable social links: every link posted anywhere gets its own short
  -- code, so a lead can be traced back to the exact Instagram story or
  -- Facebook post that produced it — the single most useful thing a
  -- consultancy can know about its marketing spend.
  CREATE TABLE IF NOT EXISTS tracked_links (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    short_code TEXT NOT NULL,
    title TEXT NOT NULL,           -- "Instagram bio link", "Sept intake FB post"
    destination TEXT NOT NULL,     -- where it forwards to (usually a capture form)
    platform TEXT NOT NULL,        -- instagram | facebook | whatsapp | telegram | youtube | linkedin | tiktok | offline_qr | other
    campaign TEXT,                 -- groups links belonging to one campaign
    capture_form_id TEXT REFERENCES capture_forms(id),
    click_count INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_tracked_links_code ON tracked_links(short_code);

  -- One row per click, so attribution survives even if the person fills
  -- the form days later from a different device.
  CREATE TABLE IF NOT EXISTS link_clicks (
    id TEXT PRIMARY KEY,
    link_id TEXT NOT NULL REFERENCES tracked_links(id),
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    clicked_at TEXT DEFAULT (datetime('now')),
    referrer TEXT,
    user_agent TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_link_clicks_link ON link_clicks(link_id, clicked_at);

  -- Alumni Network: connects a new lead with an existing/graduated
  -- student at the same institution — peer trust converts far better
  -- than a sales pitch. Students opt in to being contactable.
  CREATE TABLE IF NOT EXISTS alumni_connections (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),      -- the prospective student asking
    student_id TEXT NOT NULL REFERENCES students(id), -- the alumni/current student
    requested_at TEXT DEFAULT (datetime('now')),
    status TEXT NOT NULL DEFAULT 'requested',  -- requested | connected | declined
    notes TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_alumni_conn_lead ON alumni_connections(tenant_id, lead_id);

  -- A student's willingness to be contacted, and how — separate from
  -- their enrollment record since it can change over time.
  CREATE TABLE IF NOT EXISTS alumni_availability (
    student_id TEXT PRIMARY KEY REFERENCES students(id),
    available_for_contact INTEGER NOT NULL DEFAULT 0,
    preferred_channel TEXT DEFAULT 'whatsapp',  -- whatsapp | email | call
    bio TEXT,          -- "3rd year MBBS, happy to talk about hostel life and clinicals"
    max_active_connections INTEGER DEFAULT 3,
    updated_at TEXT DEFAULT (datetime('now'))
  );

  -- Payment gateway attempts, linked to a fee_payments row. Kept separate
  -- from fee_payments itself so a lead can retry a failed payment without
  -- corrupting the underlying fee record.
  CREATE TABLE IF NOT EXISTS payment_links (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    fee_payment_id TEXT NOT NULL REFERENCES fee_payments(id),
    gateway TEXT NOT NULL,          -- razorpay | esewa | khalti
    gateway_order_id TEXT,
    amount REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'created',  -- created | paid | failed | expired
    payment_url TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    paid_at TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_payment_links_fee ON payment_links(fee_payment_id);

  -- Consent & Compliance: what a lead has agreed to, and when. Handling
  -- passports, marksheets and financial details makes this a genuine
  -- obligation, not a nice-to-have — and export/delete requests are a
  -- real right under most data protection frameworks (GDPR-style).
  CREATE TABLE IF NOT EXISTS consent_records (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    consent_type TEXT NOT NULL,  -- data_processing | marketing_contact | document_sharing | third_party_sharing
    granted INTEGER NOT NULL,    -- 1 = granted, 0 = withdrawn
    method TEXT,                 -- verbal | whatsapp | form | email
    recorded_by TEXT,
    recorded_at TEXT DEFAULT (datetime('now')),
    notes TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_consent_lead ON consent_records(tenant_id, lead_id);

  -- A logged data-subject request (export or delete) — the request itself
  -- must be auditable even before/regardless of whether it's fulfilled.
  CREATE TABLE IF NOT EXISTS data_requests (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    request_type TEXT NOT NULL,  -- export | delete
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | completed
    requested_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    handled_by TEXT
  );
`);

// Seed sensible default stages for a brand-new tenant so the app is usable
// immediately — a starting point the tenant can freely edit/reorder/delete
// via the Pipeline Builder, not a hardcoded system list.
function seedDefaultStages(tid) {
  const existing = db.prepare('SELECT COUNT(*) AS c FROM pipeline_stages WHERE tenant_id = ?').get(tid).c;
  if (existing > 0) return;
  const defaults = [
    ['New', '#607D8B'], ['Contacted', '#2196F3'], ['Counseling', '#FF9800'],
    ['Admission', '#4CAF50'], ['Closed', '#009688'], ['Lost', '#F44336'],
  ];
  const insert = db.prepare('INSERT INTO pipeline_stages (id, tenant_id, name, position, color) VALUES (?, ?, ?, ?, ?)');
  defaults.forEach(([name, color], i) => insert.run(require('crypto').randomUUID(), tid, name, i, color));
}

// Seed a default demo tenant so the API is usable immediately
const existing = db.prepare('SELECT id FROM tenants WHERE id = ?').get('demo-consultancy');
if (!existing) {
  db.prepare('INSERT INTO tenants (id, name) VALUES (?, ?)').run('demo-consultancy', 'Demo Consultancy');
}
seedDefaultStages('demo-consultancy');

module.exports = db;
