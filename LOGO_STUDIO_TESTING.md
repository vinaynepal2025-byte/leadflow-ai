# LOGO_STUDIO_TESTING.md

What was actually checked for this pass, and how. No claim here is asserted without the command/result that backs it — see `LOGO_STUDIO_ARCHITECTURE.md` for what each phase does and why.

## Static analysis (every phase)

`flutter analyze` was run after every phase, scoped to the touched files first, then a full-project sweep at the end:

- **Final full-project result: 126 issues, 0 errors.** Confirmed via `flutter analyze 2>&1 | grep -c "^   error"` → `0`.
- Every one of the 126 is a pre-existing `info`/`warning`-level style lint (deprecated `.value` color accessors, missing `const`, `BuildContext`-across-async-gap warnings already present before this session) — none introduced by this pass. Verified by diffing scoped per-file analyze output against each file's issue count immediately after each edit, every time: zero new issues at every checkpoint.
- Backend: `node -c` run on every touched/new file after every edit (`flyerProjects.js`, `tenantLogos.js`, `tenantAssets.js`, `brandKit.js`, `leadDetailSections.js`, `server.js`, all three migration files) — all pass.

## Functional verification (not just "does it compile")

### SVG sanitizer (`svg_sanitizer.dart`, Phase 4)
Standalone Dart script, 10 cases, run via `dart run` from within the `mobile/` package so `package:xml` resolved correctly:
1. Valid SVG with a `<path>` — kept intact. ✅
2. `<script>alert(1)</script>` — stripped. ✅
3. `onload`/`onclick` event attributes — stripped. ✅
4. External `https://` href on `<image>` — stripped. ✅
5. `data:image/png;base64,...` href — kept (no network fetch risk). ✅
6. `#fragment` href — kept (in-document reference). ✅
7. Non-`<svg>` root element (`<html>...`) — throws `SvgSanitizeException`. ✅
8. Empty input — throws. ✅
9. Malformed XML (`<svg><rect></svg>`) — throws with the parser's own error. ✅
10. `<foreignObject>` — stripped. ✅

Result: 10/10 pass.

### Export format conversion + ICO encoder (Phase 7)
Standalone Node script using the real `sharp` package (installed via `npm install` for this check, `package-lock.json` reverted afterward to avoid an unintended dependency-pin change):
- Generated a real 100×100 semi-transparent PNG via `sharp`, confirmed PNG magic bytes.
- Converted to JPEG via the same code path the export route uses — confirmed real `FFD8FF` JPEG magic bytes (not just "didn't throw").
- Converted to WebP — confirmed `RIFF`...`WEBP` container header.
- Ran the hand-rolled `pngToIco()` — confirmed: reserved/type/count header fields correct, width/height/color-count/planes/bits-per-pixel/data-size/offset fields all correct, and the embedded PNG bytes are byte-identical to the source (`embedded.equals(faviconPng)` → true) with intact PNG magic bytes.

Result: every conversion verified against the actual file format's binary signature, not assumed from "no error thrown."

### Database schema (Phases 6, 5, 9)
Every new/documented table verified against the **live** production schema via direct `information_schema.columns` / `pg_policies`-style queries (Supabase MCP `execute_sql`), not assumed from the migration file alone:
- `flyer_projects`/`tenant_logos`: exact column/type/default set pulled from production before writing the baseline migration, so the migration matches reality exactly (verified: `id UUID DEFAULT gen_random_uuid()`, `canvas_json JSONB NOT NULL DEFAULT '[]'::jsonb`, etc.)
- `tenant_assets`: applied live via `apply_migration`, confirmed present with a follow-up `information_schema` check before building the route.
- `tenant_brand_kits`: first `apply_migration` attempt correctly failed (`text and uuid` type mismatch on the FK columns) — this is a real error caught by testing, not glossed over. Fixed by changing the six role columns from `TEXT` to `UUID` to match `tenant_logos.id`'s actual type, then reapplied successfully.

## Security / multi-tenancy review (Phase 12)

Grepped every new route's SQL statements to confirm the tenant-isolation discipline `TECH_DEBT.md`/`SCHEMA_SNAPSHOT.md` already documented as the app's *only* isolation layer (Postgres RLS is enabled but policy-less; the backend connects as `postgres`, which bypasses RLS) was followed everywhere new:
- Every `SELECT`/`UPDATE`/`DELETE` in `tenantAssets.js` and `brandKit.js` filters by `tenant_id = ?`, **except** three `SELECT ... WHERE id = ?` calls that read back a row immediately after an insert (a fresh `randomUUID()` this same request just created) or immediately after an `UPDATE ... WHERE tenant_id = ? AND id = ?` already succeeded — the id isn't attacker-controlled at that point, so this isn't a cross-tenant read. Same pattern already used throughout the pre-existing codebase (`dashboardSections.js`, `tenantLogos.js`).
- `/tenant-assets` and `/brand-kit` confirmed **not** in `middleware/auth.js`'s `PUBLIC_PREFIXES` — both auth-gated by default, same as every other business route.
- SVG upload has two layers: real client-side sanitization (`svg_sanitizer.dart`, XML-structural) before an SVG ever becomes an element, plus a server-side size cap + shape check on `POST /tenant-assets/svg` as defense-in-depth against a client that skips the first layer — documented in-file why a full server-side sanitizer wasn't built (the asset is never handed to a server-side renderer, and is only ever served back to the tenant that stored it).

## Not tested (stated plainly, not hidden)

- **No live-device or CI screenshot** of any new UI. This repo has no platform scaffolding checked in (`android/`/`ios/`/`web/` under `mobile/` are generated at CI build time), and CI (`build-and-release.yml`) only triggers on push to `main`, not this feature branch. Verification for UI changes is `flutter analyze` (structural correctness) + code-level review against the app's established small-screen-safe patterns (Phase 11) — not a rendered screenshot.
- **No automated unit/widget test suite added.** The existing codebase has no Flutter widget-test or backend Jest/Mocha suite to extend (confirmed absent in the Phase 1 audit) — verification throughout this pass was `flutter analyze` + standalone functional scripts + live schema checks, consistently, at every phase, rather than a test framework this repo doesn't otherwise use.
- **No regression pass against a running backend server.** Route logic was verified by direct code review + syntax check + (for the two riskiest pieces of new logic — the SVG sanitizer and the export/ICO conversion) real standalone execution against the actual libraries (`xml`, `sharp`) involved. The routes were not exercised end-to-end against a live Express server + real HTTP requests in this pass.

## Acceptance criteria (master spec §40), scored against this pass

| Criterion | Status |
|---|---|
| Logo Studio opens from LeadFlow | ✅ (pre-existing) |
| Blank logo creation works | ✅ (pre-existing) |
| Template creation works | ✅ (pre-existing) |
| AI-assisted generation works when configured | ✅ (new, Phase 8) |
| Text is editable | ✅ (pre-existing) |
| SVG is editable | 🟡 transform-level (new, Phase 4); not node/path-level |
| Shapes are editable | ✅ (pre-existing) |
| Layers work | ✅ (pre-existing) |
| Undo/redo works | ✅ (pre-existing) |
| Projects save | ✅ (pre-existing) |
| Projects reopen | ✅ (pre-existing) |
| Projects duplicate | ✅ (fixed a real bug this pass, Phase 6) |
| Assets can be managed | ✅ (new, Phase 5) |
| Variants work | ✅ (new, Phase 8) |
| Brand Kit works | ✅ (new, Phase 9) |
| Exports work | ✅ (pre-existing PNG; JPG/WebP/favicon new, Phase 7) |
| Transparent export works | ✅ (pre-existing) |
| Sharing integrates with existing LeadFlow mechanisms | ✅ (new, Phase 10) |
| Authentication is respected | ✅ (verified, see Security review above) |
| Tenant isolation is enforced | ✅ (verified, see Security review above) |
| Existing LeadFlow features remain functional | ✅ (0 new `flutter analyze` errors across the whole project) |
| Tests/checks pass | ✅ (see Static analysis + Functional verification above) |
| No known critical licensing/security issue remains | ✅ (`LOGO_STUDIO_LICENSES.md` — zero third-party code reused, two new packages both permissive-licensed) |
