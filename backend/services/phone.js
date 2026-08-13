// Phone number assembly.
//
// Why this exists: leads store the national number and the country code in
// two separate columns (`leads.phone` = "8618350225", `leads.phone_country_code`
// = "+91"). Several call sites were building wa.me links from `leads.phone`
// alone, which produces https://wa.me/8618350225 — not a valid international
// number, so WhatsApp either refuses it or resolves it against whatever
// country the *counsellor's* own SIM is in. Every WhatsApp link in the app
// was affected.
//
// Everything that needs a dialable or wa.me-able number should come through
// here, so the rule lives in exactly one place.

/// Strips everything except digits.
function digitsOnly(value) {
  return String(value || '').replace(/[^0-9]/g, '');
}

/// Builds the full international number in the digits-only form wa.me wants
/// (no plus, no spaces, no dashes): "918618350225".
///
/// Handles the cases that actually occur in this data:
/// - national number + separate country code (the normal case)
/// - a number already stored with its country code (don't double-prefix)
/// - a number stored with a leading 0 trunk prefix (drop it before prefixing)
function toWhatsAppNumber(phone, countryCode, fallbackCountryCode) {
  let national = digitsOnly(phone);
  if (!national) return null;

  const cc = digitsOnly(countryCode || fallbackCountryCode || '+91');
  if (!cc) return national;

  // Many countries write local numbers with a leading 0 that must be
  // dropped when dialling internationally.
  if (national.length > 10 && national.startsWith('0')) {
    national = national.replace(/^0+/, '');
  } else if (national.startsWith('0')) {
    national = national.replace(/^0+/, '');
  }

  // Already carries the country code — don't prefix it twice. Guarded on
  // length as well as prefix, since some national numbers legitimately
  // begin with the same digits as their country code.
  if (national.startsWith(cc) && national.length > cc.length + 6) {
    return national;
  }

  return cc + national;
}

/// Builds an E.164 string for display and for tel: links: "+918618350225".
function toE164(phone, countryCode, fallbackCountryCode) {
  const num = toWhatsAppNumber(phone, countryCode, fallbackCountryCode);
  return num ? `+${num}` : null;
}

/// Builds a wa.me click-to-chat link with an optional pre-filled message.
function buildWhatsAppLink(phone, countryCode, message, fallbackCountryCode) {
  const num = toWhatsAppNumber(phone, countryCode, fallbackCountryCode);
  if (!num) return null;
  return message
    ? `https://wa.me/${num}?text=${encodeURIComponent(message)}`
    : `https://wa.me/${num}`;
}

module.exports = { digitsOnly, toWhatsAppNumber, toE164, buildWhatsAppLink };
