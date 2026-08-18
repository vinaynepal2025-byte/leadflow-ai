// Lead Lifecycle state machine -- Leads Ecosystem redesign, Phase 2
// (Domain Model). See LEADS_AUTOMATION_AUDIT.md section 2 for why this is
// a *new*, separate column (`leads.lifecycle_status`) rather than a
// rewrite of the existing free-text `leads.stage` column: 785 live leads
// already hold stage values, and the mobile Leads List screen's filter
// chips are generated from the tenant-customizable `pipeline_stages`
// table, which this does not touch or replace.
//
// Pure functions only (no DB/network) so this can be unit-tested in
// isolation, same reasoning as flyer_element.dart's
// parsePagesFromCanvasJson/canvasJsonForPages from the Canva-parity work.

// The primary forward path a lead is expected to move through.
const MAIN_SEQUENCE = [
  'NEW',
  'CONTACT_PENDING',
  'CONTACTED',
  'ENGAGED',
  'QUALIFIED',
  'COUNSELLING',
  'APPLICATION',
  'DOCUMENT_PENDING',
  'OFFER',
  'COMMITMENT',
  'PAYMENT_PENDING',
  'ADMISSION_CONFIRMED',
];

// Side-states a lead can branch into from (most of) the main sequence.
const SIDE_STATES = ['NOT_INTERESTED', 'LOST', 'DORMANT', 'REACTIVATION', 'ON_HOLD'];

// Migration-only bucket for legacy `stage` values that don't map cleanly
// onto any state below (see the backfill migration). Never a valid
// transition *target* -- a lead can only ever leave this bucket, not
// re-enter it -- so its presence always means "not yet classified since
// the new state machine was introduced," never "sent back here."
const NEEDS_REVIEW = 'NEEDS_REVIEW';

const ALL_STATUSES = [...MAIN_SEQUENCE, ...SIDE_STATES, NEEDS_REVIEW];

const TERMINAL_STATUSES = new Set(['ADMISSION_CONFIRMED']);
const EXIT_STATES = new Set(['NOT_INTERESTED', 'LOST', 'DORMANT']);

function isKnownStatus(status) {
  return ALL_STATUSES.includes(status);
}

// What a lead currently in `current` may legally move to next. Returns []
// for an unknown/invalid `current` (nothing is legal from a status that
// doesn't exist) and for the terminal status (ADMISSION_CONFIRMED is the
// end of the funnel -- a new intake, not a transition, is how you'd
// handle a returning past-admission lead).
function computeAllowedNextStates(current) {
  if (!isKnownStatus(current)) return [];
  if (TERMINAL_STATUSES.has(current)) return [];

  if (current === NEEDS_REVIEW) {
    // First real classification after migration -- anything except back
    // into NEEDS_REVIEW itself, and REACTIVATION doesn't make sense as a
    // *first* classification (there's nothing to "reactivate" yet).
    return ALL_STATUSES.filter((s) => s !== NEEDS_REVIEW && s !== 'REACTIVATION');
  }

  if (current === 'REACTIVATION') {
    // A win-back attempt in progress: it either resumes the funnel from
    // CONTACT_PENDING onward, or confirms the lead really is gone.
    const resumeFrom = MAIN_SEQUENCE.indexOf('CONTACT_PENDING');
    return [...MAIN_SEQUENCE.slice(resumeFrom), 'NOT_INTERESTED', 'LOST'];
  }

  if (current === 'ON_HOLD') {
    // Resume anywhere in the funnel, or confirm the pause turned into an exit.
    return [...MAIN_SEQUENCE, 'NOT_INTERESTED', 'LOST', 'DORMANT'];
  }

  if (EXIT_STATES.has(current)) {
    // NOT_INTERESTED / LOST / DORMANT: lateral re-tagging between exit
    // reasons, or an explicit win-back attempt via REACTIVATION. No
    // direct jump back into the main sequence -- that must go through
    // REACTIVATION so a recovery attempt is always an explicit, visible
    // step (this is exactly the trigger condition the Lead Recovery
    // Agent needs, per the audit's automation-opportunities section).
    return [...[...EXIT_STATES].filter((s) => s !== current), 'REACTIVATION'];
  }

  // An active main-sequence state: forward to any later main-sequence
  // state (skip-ahead allowed -- e.g. a lead already qualified via an ad
  // landing page can enter straight past CONTACT_PENDING), back one step
  // to the immediately preceding state (manual correction of a
  // fat-fingered move), or out to any side-state except REACTIVATION
  // (nothing to reactivate while still active).
  const idx = MAIN_SEQUENCE.indexOf(current);
  const forward = MAIN_SEQUENCE.slice(idx + 1);
  const backOneStep = idx > 0 ? [MAIN_SEQUENCE[idx - 1]] : [];
  const sideExits = SIDE_STATES.filter((s) => s !== 'REACTIVATION');
  return [...forward, ...backOneStep, ...sideExits];
}

function isValidTransition(from, to) {
  if (!isKnownStatus(to)) return false;
  return computeAllowedNextStates(from).includes(to);
}

// Backfill mapping for the one-time migration -- the only literal `stage`
// values actually referenced anywhere in the backend (per
// LEADS_AUTOMATION_AUDIT.md section 2's grep across every route/service
// file). Anything else (a tenant's custom pipeline_stages name, NULL,
// empty string) falls into NEEDS_REVIEW rather than a guessed mapping.
const STAGE_BACKFILL_MAP = {
  New: 'NEW',
  Contacted: 'CONTACTED',
  Counseling: 'COUNSELLING',
  Admission: 'ADMISSION_CONFIRMED',
  // students.js sets stage='Closed' on enrollment -- i.e. a successful
  // conversion, not an exit -- so this maps to the funnel's success
  // terminus, not to LOST/NOT_INTERESTED.
  Closed: 'ADMISSION_CONFIRMED',
  Lost: 'LOST',
};

function mapLegacyStageToLifecycleStatus(stage) {
  return STAGE_BACKFILL_MAP[stage] || NEEDS_REVIEW;
}

module.exports = {
  MAIN_SEQUENCE,
  SIDE_STATES,
  NEEDS_REVIEW,
  ALL_STATUSES,
  TERMINAL_STATUSES,
  EXIT_STATES,
  isKnownStatus,
  computeAllowedNextStates,
  isValidTransition,
  STAGE_BACKFILL_MAP,
  mapLegacyStageToLifecycleStatus,
};
