# LOGO_STUDIO_ARCHITECTURE.md

Phase 1 deliverable for the LeadFlow AI Logo Studio master-prompt build. Grounded in a direct read of the current codebase (not aspirational) — see citations throughout. Companion to `LOGO_STUDIO_LICENSES.md` (dependency/license decisions).

## 1. Current state (what already exists, reuse it)

One editor powers both Flyer Studio and Logo Studio today: `FlyerStudioScreen(isLogoMode: bool)` (`mobile/lib/screens/flyer_studio/flyer_studio_screen.dart`, ~2,836 lines). `isLogoMode` only changes the canvas default (512×512, transparent background) and the terminal save action (`_saveAsLogo()` → `tenant_logos` instead of a share flow).

Already built and production-tested — **do not rewrite these**:
- **Object model**: `FlyerElement` (`flyer_element.dart`) — flat class, `FlyerElementType {text, image, logo, shape, icon}`, with `x/y/width/height/rotation/zIndex/locked/opacity/aspectLocked` + per-type fields. Round-trips through the backend's `canvas_json` JSONB column with zero server transformation.
- **Transforms**: drag/resize/rotate (15° snap) with corner handles, smart snapping (canvas edges/center + sibling edges/center, 18px threshold).
- **Ephemeral grouping**: multi-select mode with shared drag/resize/rotate/align/duplicate/delete (not persisted grouping).
- **Undo/redo**: whole-canvas JSON snapshot stack, max 40 entries.
- **Autosave**: 2.5s debounce → `PATCH /flyer-projects/:id`, full `canvas_json` replace. Manual save also available.
- **Layers panel**: bottom sheet with thumbnails, reorder, lock, delete, multi-select bulk ops.
- **Color picker**: `ColorPickerDialog` widget — curated swatches + free RGB. Reusable as-is.
- **Icon finder**: `POST /ai/find-icon` — LLM maps free-text to the closest icon key + color. Reusable pattern, needs a bigger icon set behind it.
- **Template fill-in**: `backend/services/logoTemplates.js` — 7 hardcoded SVG-string generators (monogram_badge, wordmark, icon_text, crest_seal, shield_emblem, arch_badge, geometric_mark), rendered to PNG via `sharp`/librsvg.
- **Storage**: `backend/services/supabaseStorage.js` (Supabase Storage, signed URLs), multer memory-storage uploads. Tenant-scoped path conventions already in place.
- **Auth/tenancy**: global `enforceAuth` + JWT-derived `tenant_id` (client can't spoof it), every query scoped `WHERE tenant_id = ?`. Caveat: no DB-level RLS backstop (see `SCHEMA_SNAPSHOT.md`) — tenant isolation is 100% app-layer today.

## 2. Real gaps vs. the master spec

| Spec requirement | Current state | Verdict |
|---|---|---|
| Vector/SVG document model, editable SVG paths, SVG import/export | **None.** Zero SVG packages installed (no `flutter_svg`, `path_drawing`, `xml`). Shapes are `CustomPainter` `Path`s; export is `RepaintBoundary→toImage()→PNG`, i.e. flatten-to-bitmap. Icons are Material `IconData`, not SVG. | **Biggest real gap.** Needs new foundation. |
| Typography system | Two hardcoded, unsynced font lists (`kFlyerFontFamilies`, 8 fonts; `kLogoFontOptions`, 6 fonts) plus `backend/services/fontSetup.js`. No font-picker widget, no letter-spacing/line-height UI beyond raw fields. | Needs consolidation + a real picker widget. |
| Icon/symbol library with categories | 50 Material icons, flat list, no categories. | Needs a real, categorized, larger library (or a vetted OSS SVG icon set). |
| Brand Kit, logo variations, asset library | **None of these three concepts exist anywhere.** `tenant_logos` is one-row-per-finished-logo, not a raw asset repo. | Net-new, from scratch. |
| True AI-generative logo creation | Today's "AI generation" is parametric fill-in of the 7 fixed templates — no LLM/diffusion-driven layout. `flyer_projects` has an `ai-generate` route but only for flyer text/image layout, not logos. | Net-new AI pipeline (Section 13/14 of spec), provider-agnostic per existing `aiProvider.js` pattern. |
| Template *engine* (data-driven, user-savable) | 7 hardcoded JS functions, not data-driven, no user-created templates. | Needs a real data model. |
| Migration file for `flyer_projects`/`tenant_logos` | **Neither table has a migration file in-repo** — both were applied directly to Supabase historically. | Any new columns need a fresh migration; nothing to extend from. |
| Export presets (social sizes, ICO, WebP) | Only PNG via client-side `toImage()`. | Needs a real multi-format export pipeline (client raster is fine for PNG/JPG; SVG-native export needs the new vector layer). |

## 3. Phased plan (gap-based — skips what's already solid)

Numbering matches the master prompt's Section 38 phases; phases already substantially satisfied by the existing Flyer/Logo canvas are marked accordingly rather than rebuilt.

- **Phase 1 — Audit + licenses.** ✅ This document + `LOGO_STUDIO_LICENSES.md`.
- **Phase 2 — Core document model + canvas.** Mostly done (`FlyerElement` + `FlyerStudioScreen`). Extend, don't replace: add an `svg` element type and a `groups` concept that persists (today's grouping is ephemeral).
- **Phase 3 — Objects + layers + transforms.** Mostly done. Add: persisted groups/ungroup, layer rename, nested-group display in the Layers panel.
- **Phase 4 — Typography + shapes + SVG.** ✅ Shipped: `FlyerElementType.svg` + `svg_sanitizer.dart` (real XML-parsed sanitization: strips `<script>`/event handlers/`foreignObject`/external hrefs, 2MB cap, 10/10 cases verified) + `flutter_svg`-based rendering with optional single-colour recolor, wired into the shared toolbar/layers/properties panel. `flyer_fonts.dart` unifies the two font lists into one `FlyerFontOption` (flutterFamily + backendFamily pairing, since canvas and server-rendered templates genuinely use different family-name dialects — see file header). **Deferred, not done:** full node-level SVG path editing (dragging individual bezier control points) — today's SVG element is transform-editable (move/resize/rotate/recolor/opacity) but not point-editable. No mature Flutter package does two-way SVG path editing; building it correctly (hit-testing curve handles, bezier math) is a substantial standalone effort, tracked as a follow-up increment rather than blocking the rest of the plan.
- **Phase 5 — Templates + asset library.** Move `logoTemplates.js`'s 7 templates into a data-driven `logo_templates` table (name/category/thumbnail/canvas config/objects/tags) so users can save their own customized templates. Build a generic asset library (new `tenant_assets` table: icons/images/logos/exports/templates in one browsable, searchable place) — the biggest net-new backend piece.
- **Phase 6 — Save/load + backend + storage.** Write the missing migration for `flyer_projects`/`tenant_logos` (idempotent, matches the established `CREATE TABLE IF NOT EXISTS` pattern used for `dashboard_sections`/`lead_list_fields`). Add a `duplicate` endpoint (currently missing). Extend `flyer_projects` with `groups_json`, `is_logo_project` flag rather than forking a parallel `logos` table — keeps one canvas contract.
- **Phase 7 — Export pipeline.** Add real SVG export (serialize the vector document model directly — no rasterization needed once Phase 4 lands), WebP/ICO via `sharp` (already a dependency, supports both), and the social/favicon size presets as a config list, not new code paths.
- **Phase 8 — AI generation + variants.** Reuse `backend/services/aiProvider.js`'s existing `generateJson()` abstraction (already provider-agnostic across Claude/Gemini/OpenRouter) to have the LLM choose/compose from the Phase 5 template *primitives* (shapes + icon + typography choices) rather than attempting freeform image generation — keeps output genuinely editable per Section 14's requirement ("do not treat a raster AI image as an editable vector logo"). Variant generation (horizontal/vertical/icon-only/mono/dark/light) is mechanical transforms over the same document model, not new AI calls.
- **Phase 9 — Brand Kit.** New `tenant_brand_kits` table referencing a primary logo project + palette + typography choices + generated variant set.
- **Phase 10 — LeadFlow integrations.** Wire "Attach Logo" into Lead Detail and Communication Hub/WhatsApp share (both already have generic attachment/share plumbing per `ARCHITECTURE_MAP.md`) and "Insert Logo" into Flyer Studio (trivial — it's the same canvas, just insert a `logo`-type element referencing a saved project).
- **Phase 11 — Mobile optimization.** Verify the existing touch/pinch/drag/resize/rotate handling (already implemented) still performs once the object model grows; no architecture change expected here.
- **Phase 12 — Security, performance, testing, regression.** SVG-upload sanitization (Phase 4's sanitizer), confirm every new table/route follows the existing `WHERE tenant_id = ?` discipline, add unit tests for the new document-model serialization and the SVG path editor, `flutter analyze` + backend `node -c` + a full regression pass on existing Flyer Studio (since it shares the same screen/model).

## 4. Key architectural decision

**Extend `FlyerElement`/`FlyerStudioScreen`, do not fork a parallel Logo Studio engine.** The spec's Section 27 ("Reusable Design Engine") and Section 39 ("Existing App Protection") both point the same direction: one canvas contract already serves Flyer Studio in production with live tenant data (8 `flyer_projects` rows, 8 legacy `flyers` rows). Forking would double the maintenance surface and violate "do not unnecessarily... alter database structures without migration planning." All new element types (`svg`), persisted groups, and typography upgrades are additive fields on the existing model, versioned so old `canvas_json` blobs keep loading unchanged.
