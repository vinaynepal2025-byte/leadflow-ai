# LOGO_STUDIO_LICENSES.md

Tracks third-party code/asset reuse decisions for the Logo Studio build, per the master prompt's Section 3 requirement ("never copy proprietary code... a public GitHub repository is not automatically commercially reusable").

## External repositories evaluated

| Source | Verdict | Reason |
|---|---|---|
| `github.com/JeFcorp/LogoMaker` | **Not evaluated — access denied.** GitHub App has no access to this repo (private, renamed, deleted, or org access not granted — could not determine which). No code has been read or copied. | If access is granted later, re-run this audit before any reuse. Until then, treated as unavailable. |
| `logomakr.com` | **Not eligible for code reuse — closed-source commercial SaaS**, no public repository exists. Only its live product is visible in a browser; there is no source to license-check. Scraping/reverse-engineering its templates, fonts, icons, or UI would be copyright infringement and a ToS violation regardless of any license question. | Feature/UX ideas observable from public use are not copyrightable and may inform *original* design decisions; no code, assets, or specific expression may be copied. |

**Net effect: zero third-party application code is being reused.** All Logo Studio functionality is built natively, extending the existing `FlyerElement`/`FlyerStudioScreen` engine already in this repository (see `LOGO_STUDIO_ARCHITECTURE.md` §1) plus vetted open-source *packages* (below) — not copied application source.

## New package dependencies

| Package | Version installed | Purpose | License | Commercial SaaS OK? |
|---|---|---|---|---|
| `flutter_svg` | 2.3.0 | Renders SVG within Flutter — true vector element type in Flyer/Logo Studio (`FlyerElementType.svg`), replacing the flatten-to-PNG-only approach | BSD-3-Clause | Yes — permissive, no copyleft, attribution via standard OSS notices only |
| `xml` (Dart) | 6.6.1 | Real XML parsing for `svg_sanitizer.dart` (strips `<script>`/event handlers/external hrefs from imported SVGs) | MIT | Yes |

`path_drawing` was evaluated but not added — not needed for the Phase 4 slice shipped (element-level SVG import/render/transform/recolor). Full per-node SVG path editing is deferred to a later Phase 4 increment; re-evaluate then.

All three are permissive (BSD-3/MIT): no source-disclosure obligation, no "SaaS/network use = distribution" clause (unlike AGPL), only a standard copyright/license-notice preservation requirement, which is satisfied by keeping the package's own LICENSE file intact in the dependency tree (Flutter/npm tooling does this automatically — no manual action needed beyond not deleting `pub-cache`/`node_modules` license files).

## Existing dependencies already covering Logo Studio needs (no new license exposure)

Per the Phase 1 audit (`LOGO_STUDIO_ARCHITECTURE.md` §1), these already-installed packages are reused as-is, already cleared for this commercial codebase:

- `sharp` (backend, Apache-2.0) — SVG-string→PNG/WebP/ICO rasterization via librsvg.
- `image_picker`, `share_plus`, `file_picker` (mobile) — existing, unrelated license questions, already in production use.
- Bundled fonts (SpaceGrotesk, Inter, PlayfairDisplay, Lato, Poppins, Roboto, Montserrat, Open Sans) — all Google Fonts / SIL Open Font License, already vetted for this app prior to this session; no new fonts are being added without repeating this check.

## Icon library

The spec (Section 11) asks for a categorized icon system (business/education/medical/technology/etc.). Current library is 50 Material Design icons (Apache-2.0, via Flutter's bundled `Icons` class — already commercially clear). Expanding this to a categorized set should draw from **Material Symbols** (Apache-2.0) first before considering any third-party icon pack, to avoid introducing a new license to check. Any additional icon pack (e.g. a dedicated SVG icon library) must be added to this file's package table, with its license verified, before use.

## Standing rule

No file, template, font, icon, or code snippet from any external source (repository, website, or package) may be added to this codebase without first adding a row to the relevant table above documenting its license and commercial-use status. If a license is missing, unclear, restrictive (GPL/AGPL/BSL/non-commercial/etc.), or the source is inaccessible for review (as with `JeFcorp/LogoMaker` above), the required functionality is implemented natively instead.
