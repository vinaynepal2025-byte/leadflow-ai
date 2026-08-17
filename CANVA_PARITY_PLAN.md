# CANVA_PARITY_PLAN.md

Full-scope roadmap for bringing Flyer Studio/Logo Studio up to Canva's feature breadth, per explicit instruction: *"Canva ke paas jo jo hai wo sab chahiye, please don't put limit... jo nahi bana sakte new codes likho but completely Canva jaisa chahiye."* This plan does not cap the vision — every major Canva capability is listed below, phased by what's buildable with code in this app's architecture versus what depends on infrastructure/cost decisions no amount of code alone resolves. Each phase gets the same treatment as `LOGO_STUDIO_ARCHITECTURE.md`: real, verified increments, committed one at a time, status kept current here.

## How to read this

- ✅ Shipped this pass
- 🔨 In progress / next up
- 📋 Planned, not started — genuinely buildable with more engineering time, no external blocker
- ⚠️ Buildable, but a *limited* version without a paid third-party service (flagged with what upgrading it would need)
- 🏗️ A separate infrastructure initiative, not an "add a feature" task — sized honestly so it isn't quietly dropped

## Phase A — Unified Elements panel

Today: icon picker, SVG import, and Asset Library are three separate entry points. Canva has one searchable "Elements" panel across everything.
**Status: 📋** — merge the three into one search-driven panel (tabs or filter chips for Icons/Shapes/SVG/My Uploads), reusing `buildCustomizeRegistry`-style unification already proven elsewhere in this app.

## Phase B — Text effects

Shadow and background-highlight already exist. Canva's other headline text effects: **outline/stroke**, **curved text** (on the live canvas, not just server-rendered logo templates), lift (soft drop shadow, a shadow-preset variant), hollow (stroke-only, no fill).
**Status: ✅ shipped this pass** — outline via a stroked `Paint` copy of the text layered behind the filled copy (works standalone and combined with curve); curved text via a new `CurvedTextPainter` (`flyer_canvas_element_widget.dart`) that places each glyph along a real circular arc derived from a chord/sagitta relationship (arc always spans the element's width; `curveAmount` -100..100 controls how much it bulges, positive up / negative down) — same per-character trig as the server-side `archText()` in `logoTemplates.js`, now live and editable on-canvas instead of only baked into logo template SVGs. "Hollow" (stroke-only, transparent fill) and "Lift" (a shadow-preset variant of the existing `textShadow` toggle) were not built as separate controls this pass — the colour picker only stores opaque RGB today (`flyerColorToHex` drops alpha), so hollow specifically needs that widened before it's real, not just wired up. Tracked here rather than silently dropped.

## Phase C — Photo adjustments/filters

Brightness, contrast, saturation, and a duotone effect. Today an image element only has `cornerRadius`/`fit` — zero photo-editing controls.
**Status: ✅ shipped** — brightness/contrast/saturation achieved client-side via `ColorFilter`/`ColorFiltered` matrices, no new dependency, no server round-trip. Duotone (2-colour gradient map effect) not yet built — tracked here rather than silently dropped.

## Phase D — Frames & photo grids

Frames: an image masked into a shape (circle/star/blob). Grids: multiple photos auto-arranged into a layout (2-up, 3-up, collage).
**Status: 📋** — frames via `ClipPath` with the existing shape-path definitions (`FlyerShapePainter` already has several); grids via a layout helper that places N images into preset slot arrangements, each slot still an independently editable/replaceable element.

## Phase E — Draw tool

Freehand drawing directly on the canvas.
**Status: 📋** — `GestureDetector` recording `Offset` points into a `Path`, rendered as a new element type (`FlyerElementType.drawing`), same persistence pattern as every other element (serializes as a list of points in `canvas_json`).

## Phase F — Charts

Bar/line/pie chart elements built from a small data table the user types in.
**Status: 📋** — a new element type rendering via `CustomPainter` from a `{labels, values}` structure stored in the element; no charting package needed for the 3 basic types.

## Phase G — QR code element

A QR code as a placeable, resizable canvas element (encoding a URL/lead-capture-form link, brand social link, etc.).
**Status: 📋** — the backend's `qrcode` npm package is already a dependency (used elsewhere in the app for lead capture); exposing it as a Flyer Studio element is mostly wiring, not new capability.

## Phase H — Multi-page designs

One project, several pages/canvases (e.g., a 2-page flyer or a mini-brochure).
**Status: 📋** — extends the document model (`flyer_projects.canvas_json` becomes an array-of-pages instead of an array-of-elements at the top level) — a real schema-shape change, needs a migration path for existing single-page projects (treat a legacy array as "page 1").

## Phase I — Magic Resize (smarter)

Today: `kFlyerCanvasPresets` + `_exportAllSizes()` already does "one design → every standard size," scaling every element proportionally.
**Status: ✅ baseline exists.** Canva's version is smarter about reflow (e.g., a headline might wrap differently at a very different aspect ratio) — a content-aware version is a real algorithmic project on its own; proportional scaling is the correct, honest baseline to keep for now.

## Phase J — Background remover ⚠️

Canva's is ML-based (a trained segmentation model), typically served via a hosted API.
**Status: ⚠️** — a **classical computer-vision version is buildable now** (chroma-key style: works well for a photo shot against a plain/solid background, much worse on a busy background) — real and functional, not fake, but genuinely lower quality than Canva's AI version on typical phone photos. **To match Canva's actual quality would need a paid third-party background-removal API** (e.g. remove.bg-style service) — that's a cost/vendor decision, not a coding gap; flagging it here rather than silently shipping something that looks AI-powered but isn't.

## Phase K — Bigger template/stock library

Canva licenses millions of templates/photos/graphics from stock providers.
**Status: ⚠️ ongoing, not a one-time task** — this app's Asset Library (built this session) is the right mechanism to keep growing a library, and AI logo/graphic generation adds original content over time, but there is no way to legally replicate Canva's licensed catalog without either paying for a stock-content API/license (cost decision) or growing the library manually/via AI generation over time. Both are real paths; neither is "write more code" alone.

## Phase L — Animation / video export 🏗️

Canva supports animated designs and full video editing (timeline, trim, transitions, audio).
**Status: 🏗️** — this is a different engineering domain from a static-design editor: needs a frame-timeline data model, a rendering pipeline that composites frames over time, and server-side video encoding (FFmpeg or similar). `FEATURE_STATUS.md` #11 already tracks this exact gap ("Creative/Video engine... no video, no FFmpeg"). Sized honestly as its own multi-week initiative, not folded into this plan's smaller phases so it doesn't get silently dropped.

## Phase M — Real-time multi-user collaboration 🏗️

Canva supports multiple people co-editing one design live.
**Status: 🏗️** — needs WebSocket infrastructure, presence, and either operational-transform or CRDT-based conflict resolution — a distributed-systems project, not an editor feature. Also worth naming plainly: LeadFlow is a single-org internal CRM tool where one counsellor typically owns one design, so this is the lowest-value-per-effort item on this whole list for this specific product — included because "don't limit the plan," not because it's recommended next.

## Phase N — AI Magic Design / Magic Write / Text-to-Image ⚠️

Canva's AI suite: generate a whole design from a prompt, AI copywriting, text-to-image graphics.
**Status: ⚠️ partially exists** — Logo Studio's AI generator (this session) already does "brief → editable design" for logos specifically; AI Quick Restyle already does natural-language section restyling. A general **text-to-image element generator** needs an image-generation model API (no such provider is wired into `aiProvider.js` today) — a new cost/vendor integration, same category of decision as Phase J.

---

## What's actually shipped vs. planned, kept current

| Phase | Status |
|---|---|
| A — Unified Elements panel | 📋 |
| B — Text effects (outline/curved) | ✅ outline + curve shipped; hollow/lift not yet |
| C — Photo adjustments/filters | ✅ brightness/contrast/saturation shipped; duotone not yet |
| D — Frames & grids | 📋 |
| E — Draw tool | 📋 |
| F — Charts | 📋 |
| G — QR code element | 📋 |
| H — Multi-page designs | 📋 |
| I — Magic Resize | ✅ baseline |
| J — Background remover | ⚠️ classical-CV version buildable; AI-quality needs a paid API |
| K — Bigger library | ⚠️ ongoing content growth, not one task |
| L — Animation/video | 🏗️ separate initiative |
| M — Collaboration | 🏗️ separate initiative, low value for this product |
| N — AI Magic Design suite | ⚠️ partially exists; text-to-image needs a new paid API |

This is a genuinely large program — comparable in size to the 12-phase Logo Studio build earlier in this session, likely larger. It will continue phase-by-phase in the same way: real code, real verification, one commit per phase, this table kept honest about what's actually done.
