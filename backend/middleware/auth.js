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

// Phase 3 will use this to actually block unauthenticated requests on
// routes that should require login. Exported now so it exists in one
// place ahead of time; not wired into server.js until Phase 3.
function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Authentication required' });
  next();
}

// Phase 4 helper -- role-gate a route to specific roles once req.user is
// reliably populated (i.e. after Phase 2 client rollout is live). Safe to
// export now; unused until then.
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Authentication required' });
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: `Requires role: ${roles.join(' or ')}` });
    }
    next();
  };
}

module.exports = { attachUser, requireAuth, requireRole, JWT_SECRET };
