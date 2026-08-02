# AI Design Engine — Portable Module

Built for LeadFlow AI, but written with zero LeadFlow-specific coupling
so it can be dropped into any other Flutter + Node/Express project.

## What it is
A "describe the look you want, AI builds it" theming system. A person
types a plain-language prompt ("premium and trustworthy for a medical
consultancy"); an LLM (via the existing multi-provider aiProvider.js)
returns a structured theme (colors, font pairing, corner radius, dark
mode, UI style mode, glow/floating/texture flags); the app applies it
instantly.

## Files that make up the whole engine

### Backend (copy as-is into any Express project)
- `backend/services/aiProvider.js` — provider-agnostic AI caller
  (Claude / Gemini / OpenRouter, switchable via `AI_PROVIDER` env var).
  Exposes `generateText()` and `generateJson()`.
- `backend/routes/ai.js` — the `POST /ai/generate-theme` route.
  No db, no tenant/auth coupling. Takes `{ prompt, brandColors? }`,
  returns a validated theme JSON object. Mount it under any path.

### Flutter (copy as a unit — these 4 files are the whole client side)
- `mobile/lib/theme/appearance_settings.dart` — the `ChangeNotifier`
  holding every visual setting (colors, font, radius, style mode, etc.),
  persisted via `shared_preferences`. The engine adds one method here:
  `applyGeneratedTheme(Map<String, dynamic> theme, GlassSetter setGlassEnabled)`.
- `mobile/lib/theme/app_theme.dart` — turns `AppearanceSettings` into a
  real Flutter `ThemeData` (this is what every screen actually renders
  with). Untouched by the engine, but required for it to have any effect.
- `mobile/lib/services/api_service.dart` — add one method,
  `generateAiTheme(String prompt, {List<String>? brandColors})`,
  calling the backend route above.
- `mobile/lib/widgets/ai_theme_generator_card.dart` — the actual UI:
  a prompt box + Generate button. Self-contained `StatefulWidget`, only
  needs `AppearanceSettings`/`GlassSettings` available via `provider`
  above it in the widget tree, and drops into any screen with
  `const AiThemeGeneratorCard()`.

## To port into a new project
1. Copy `aiProvider.js` + the `generate-theme` route from `ai.js` into
   the new backend. Set `AI_PROVIDER` + the matching API key in `.env`.
2. Copy the 4 Flutter files above (or the equivalent methods, if the new
   project already has its own `AppearanceSettings`-shaped class —
   the engine only needs: primaryColor, accentColor, a font-pairing
   enum, cornerRadius, darkMode, a style-mode enum, glow/floating/texture
   flags, and a way to persist + notifyListeners()).
3. Update the `VALID_FONTS` / `VALID_MODES` whitelists in `ai.js` to
   match the new project's actual enum values (they don't have to be
   named the same as LeadFlow's, just consistent between backend and
   Flutter).
4. Drop `<AiThemeGeneratorCard />` into any screen with access to those
   providers.

## Design choices worth keeping when porting
- The backend clamps/validates every AI-returned field (hex regex,
  enum whitelist, numeric range) before sending it to the client --
  never trust the LLM's JSON directly against a live app's theme system.
- `generateJson()` already strips \`\`\`json fences models add --
  reuse it rather than re-parsing JSON ad hoc per feature.
- The Flutter side degrades safely: any missing/invalid field in the
  response falls back to the current setting rather than crashing.
