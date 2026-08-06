// backend/services/fontSetup.js
//
// Registers the bundled font files (backend/assets/fonts/*.ttf) so that
// sharp's SVG rendering (librsvg, via its bundled fontconfig) can find
// them by family name.
//
// IMPORTANT — this must be required BEFORE the first `require('sharp')`
// call anywhere in the app (server.js does this at the very top, ahead of
// every route mount). It sets process.env.FONTCONFIG_PATH, which
// fontconfig reads once at its own internal initialization — setting it
// after fontconfig has already initialized will not work.
//
// Deliberately does NOT shell out to the `fc-cache` CLI tool — that
// binary's presence can't be guaranteed on every deploy target. Instead
// this writes a minimal fonts.conf that fontconfig can read directly and
// scan on demand. Verified working end-to-end this session, in a
// from-scratch process with no pre-existing font cache and no FONTCONFIG_PATH
// previously set — see session notes / test screenshots.

const fs = require('fs');
const os = require('os');
const path = require('path');

const FONTS_DIR = path.join(__dirname, '..', 'assets', 'fonts');
const CONFIG_DIR = path.join(os.tmpdir(), 'leadflow-fontconfig');
const CACHE_DIR = path.join(CONFIG_DIR, 'cache');

// Keep this list in sync with the actual files in backend/assets/fonts/.
// Exposed so routes/flyers.js can validate a requested font_family
// against what's actually installed, instead of silently falling back.
const AVAILABLE_FONTS = [
  'Space Grotesk',
  'Playfair Display',
  'Poppins',
  'Lato',
  'Montserrat',
  'Open Sans',
];

function setupFonts() {
  if (!fs.existsSync(FONTS_DIR)) {
    console.warn(`fontSetup: ${FONTS_DIR} not found — flyer generation will use default fonts only.`);
    return;
  }

  fs.mkdirSync(CACHE_DIR, { recursive: true });

  const fontsConf = `<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>${FONTS_DIR}</dir>
  <cachedir>${CACHE_DIR}</cachedir>
</fontconfig>`;

  fs.writeFileSync(path.join(CONFIG_DIR, 'fonts.conf'), fontsConf, 'utf8');
  process.env.FONTCONFIG_PATH = CONFIG_DIR;

  console.log(`fontSetup: registered ${AVAILABLE_FONTS.length} custom fonts from ${FONTS_DIR}`);
}

setupFonts();

module.exports = { AVAILABLE_FONTS };
