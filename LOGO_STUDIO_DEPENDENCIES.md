# LOGO_STUDIO_DEPENDENCIES.md

What Logo Studio depends on, and why. License clearance for each is tracked separately in `LOGO_STUDIO_LICENSES.md` — this file is about function, that one is about legal status.

## New dependencies added this pass

| Package | Where | Why |
|---|---|---|
| `flutter_svg` (2.3.0) | `mobile/pubspec.yaml` | Renders SVG markup on-canvas (`SvgPicture.string`) — the entire reason `FlyerElementType.svg` can stay vector instead of flattening to a bitmap on import. |
| `xml` (6.6.1, Dart) | `mobile/pubspec.yaml` | Real XML parsing for `svg_sanitizer.dart` — needed to walk an imported SVG's element tree and strip `<script>`/event handlers/external hrefs/`foreignObject` by structure, not by regex. |

Both are pure-Dart/Flutter packages with zero native platform code — no Android/iOS permission or build-config changes were needed to add them.

## Existing dependencies Logo Studio now leans on more heavily

| Package | Role in Logo Studio |
|---|---|
| `sharp` (0.35.3, backend) | Already used for the 7 template SVG→PNG renders; now also does the real JPG/WebP conversion in the export pipeline (Phase 7). Lazy-loaded (`getSharp()`) in both `tenantLogos.js` and `flyerProjects.js` so a load failure only disables image features, never crashes the server. |
| `file_picker` (mobile) | Already in the app (documents, Excel import); reused as-is for SVG import (`_importSvgElement`) — no new package needed for "pick a file from device." |
| `image_picker` (mobile) | Already in the app; reused for Asset Library image uploads. |
| `provider` (mobile) | State management pattern every new screen/sheet follows (`context.watch<AppearanceSettings>()` etc.) — no new state-management dependency introduced. |

## Deliberately not added

| Considered | Verdict | Reasoning |
|---|---|---|
| `path_drawing` (Dart) | Not added | Evaluated for SVG path-data parsing; not needed for the Phase 4 slice actually shipped (element-level SVG transform, not node-level path editing). Re-evaluate if/when full path editing is built. |
| An `.ico`-encoding npm package | Not added | A correct single-image ICO container (Vista+ PNG-in-ICO format) is ~20 lines of buffer-writing — see `pngToIco()` in `backend/routes/flyerProjects.js`. Didn't clear the Dependency Policy bar (master spec §36: check whether existing tools already solve it before adding a package). Verified against real ICO header bytes — see `LOGO_STUDIO_TESTING.md`. |
| A dedicated icon library package (beyond Material) | Not added | Section 11's "categorized icon library" gap is real but unaddressed this pass (`LOGO_STUDIO_FEATURES.md` #7) — SVG import is the practical workaround today. Any future icon-pack addition must be logged in `LOGO_STUDIO_LICENSES.md` before use. |
