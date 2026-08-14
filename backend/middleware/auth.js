const jwt = require('jsonwebtoken');

// Same secret auth.js signs tokens with. Duplicated here (not re-exported
// from auth.js) to avoid a circular require -- auth.js already imports
// nothing from middleware/, and this file must not import routes/auth.js.
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret-change-me';

// P0 SECURITY FIX -- PHASE 1 (foundation, non-breaking).
//
// The problem this closes: every route file trusts a client-supplied
// `x-tenant-id` header for which tenant's data to read/write. Nothing
// verifies the caller is actually a member of that tenant -- anyone who
// knows (or guesses) a tenant_id can read/write/delete that tenant's data
// by just setting the header. auth.js has working JWT infra (login/
// register issue real signed tokens) but nothing in the request pipeline
// ever checks for one.
//
// This middleware is deliberately ADDITIVE, not enforcing, so it ships
// with zero risk of breaking the current app (which sends no token at
// all yet -- see Phase 2, the Flutter-side rollout):
//   - No Authorization header, or an invalid/expired one -> request
//     proceeds exactly as before. req.user is left unset. Every route's
//     existing `req.header('x-tenant-id') || 'demo-consultancy'` pattern
//     is completely untouched.
//   - A VALID Bearer token -> req.user is set to the verified payload,
//     AND the x-tenant-id header on the request is overwritten with the
//     tenant_id from the token itself. This means the moment a caller
//     presents a real token, every one of the 55 route files that reads
//     `req.header('x-tenant-id')` automatically starts trusting the
//     verified identity instead of whatever the client claimed --
//     without a single one of those 55 files needing to change. A
//     client can no longer spoof a different tenant's data by lying in
//     the header once it's authenticated; the header is now a courier
//     for the server's own verified value, not client input.
//
// Phase 3 will flip this from optional to mandatory (reject requests
// with no/invalid token) once Phase 2's Flutter rollout means real users
// are actually sending tokens. Until then, this only helps callers who
// already have one (e.g. this can be curl-tested today with a token from
// POST /auth/login, without waiting for the app to be updated).
function attachUser(req, res, next) {
  const header = req.header('Authorization');
  if (header && header.startsWith('Bearer ')) {
    try {
      const payload = jwt.verify(header.slice(7), JWT_SECRET);
      req.user = { id: payload.userId, tenantId: payload.tenantId, role: payload.role };
      // Overwrite, never trust-and-merge -- this is what makes the header
      // un-spoofable for authenticated requests. req.headers is a plain
      // object in Express, safe to mutate before routing continues.
      req.headers['x-tenant-id'] = payload.tenantId;
    } catch (err) {
      // Invalid/expired token. Phase 1 stays additive: do NOT reject the
      // request here (that's Phase 3's job) -- fall through to the
      // legacy header-only behavior so today's real users (who send no
      // token) are never affected by a malformed one either.
    }
  }
  next();
}

// ---------------------------------------------------------------------
// PHASE 3 -- mandatory authentication.
//
// Everything not matched below requires a valid token. These exceptions
// are genuine public surfaces, each verified against the live route
// files rather than assumed -- breaking any one of them would fail
// silently in a way no error log would surface:
//
//  - /health                    uptime checks
//  - /auth/login|register|signup how you GET a token; gating these would
//                               make login impossible (chicken-and-egg)
//  - /auth/verify-email,        clicked from an email in a browser, which
//    /auth/resend-verification  cannot send an Authorization header
//  - /capture/submit/:key,      PUBLIC LEAD CAPTURE FORMS -- filled in by
//    /capture/form/:key         prospective students who have no account.
//                               Note /capture/forms (managing forms) is
//                               NOT public and is deliberately excluded
//                               by the trailing-slash-sensitive matching.
//  - /peer-reviews/pay/:id      the no-login UPI payment page built
//    + /pay/:id/confirm         specifically so a LEAD can pay from their
//                               own phone -- the whole point is no login
//  - /whatsapp/webhook,         inbound webhooks from Meta / lead ads;
//    /lead-ads/webhook          third parties cannot send our JWT
//  - /whatsapp/process-scheduled called by the GitHub Actions cron every
//                               15 min, which has no token. NOTE: the
//                               workflow swallows errors with `|| echo`,
//                               so gating this would have broken
//                               scheduled WhatsApp sends *silently*.
//                               Flagged as a real follow-up: this should
//                               get its own shared-secret header rather
//                               than staying fully open indefinitely.
//  - /s/:code                   public short links (Instagram bio etc.)
//
// Matched by prefix against req.path. Ordering doesn't matter since this
// is a pure "does any entry match" check.
const PUBLIC_PREFIXES = [
  '/health',
  '/auth/login',
  '/auth/register',
  '/auth/signup',
  '/auth/verify-email',
  '/auth/resend-verification',
  '/capture/submit/',
  '/capture/form/',
  '/peer-reviews/pay/',
  '/whatsapp/webhook',
  '/whatsapp/process-scheduled',
  '/lead-ads/webhook',
  '/s/',
];

function isPublicPath(path) {
  return PUBLIC_PREFIXES.some((p) =>
    // Exact-match entries (no trailing slash) must match the whole path
    // or a deeper segment; prefix entries (trailing slash) match anything
    // beneath them. This is what keeps /capture/form/:key public while
    // leaving /capture/forms (the admin list) gated -- a naive
    // startsWith('/capture/form') would have wrongly opened both.
    p.endsWith('/') ? path.startsWith(p) : path === p || path.startsWith(`${p}/`)
  );
}

// PHASE 3: the actual enforcement gate. Mounted globally in server.js
// immediately after attachUser, so a request with no valid token never
// reaches any domain route. Before this, a caller who simply omitted the
// Authorization header fell through to the legacy x-tenant-id path and
// was served whatever tenant they claimed -- which is exactly the P0
// this whole 4-phase effort exists to close.
function enforceAuth(req, res, next) {
  if (isPublicPath(req.path)) return next();
  if (!req.user) {
    return res.status(401).json({ error: 'Authentication required. Please log in again.' });
  }
  next();
}

// Kept for per-route use where a specific route needs its own gate; the
// global enforceAuth above now covers the general case.
function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Authentication required' });
  next();
}

// PHASE 4 -- role gating. Now genuinely enforceable, because req.user is
// reliably populated for every non-public request. Until Phase 1+2 this
// could not work at all: req.user was always undefined, which is why the
// admin/counselor/viewer roles shipped earlier were decorative.
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Authentication required' });
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: `Requires role: ${roles.join(' or ')}` });
    }
    next();
  };
}

module.exports = { attachUser, enforceAuth, requireAuth, requireRole, isPublicPath, JWT_SECRET };
