// svg_sanitizer.dart — validates and strips dangerous content from a
// user-imported SVG file before it's ever stored as a FlyerElement's
// svgData or rendered on-device.
//
// flutter_svg doesn't execute <script>, so the classic browser-XSS threat
// model doesn't fully apply here -- but two things still matter for a
// Flutter renderer: (1) SMIL/script content is dead weight that can still
// throw or misbehave in the SVG parser, and (2) an <image>/<use> pointing
// at an http(s) URL will genuinely make a network request from the
// device when rendered, which is an unwanted tracking/SSRF-adjacent
// vector for a file someone just picked off their phone. Both are worth
// stripping even though the risk profile differs from a browser.
//
// This does real XML parsing (via package:xml), not regex-on-a-string --
// the master prompt's requirement to "sanitize unsafe SVG input" only
// means something if malformed/adversarial markup can't just dodge a
// pattern match.

import 'package:xml/xml.dart';

class SvgSanitizeException implements Exception {
  final String message;
  SvgSanitizeException(this.message);
  @override
  String toString() => message;
}

/// 2 MB is generous for a logo/icon SVG (these are typically a few KB to
/// low hundreds of KB) and cheap to enforce before even attempting to
/// parse a potentially pathological file.
const int kMaxSvgBytes = 2 * 1024 * 1024;

const _kDisallowedElements = {
  'script',
  'foreignobject',
  'iframe',
  'embed',
  'object',
  'audio',
  'video',
};

bool _isSafeUriValue(String value) {
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return true;
  if (v.startsWith('#')) return true; // in-document fragment reference
  if (v.startsWith('data:')) return true; // inline, no network fetch
  return false; // http(s):, javascript:, ftp:, everything else -- reject
}

/// Throws [SvgSanitizeException] with a user-facing message if [raw] isn't
/// a usable SVG. Returns a sanitized, re-serialized SVG string otherwise.
String sanitizeSvg(String raw) {
  if (raw.trim().isEmpty) {
    throw SvgSanitizeException('The file is empty.');
  }
  if (raw.length > kMaxSvgBytes) {
    throw SvgSanitizeException('This SVG is too large (max 2 MB).');
  }

  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(raw);
  } on XmlException catch (e) {
    throw SvgSanitizeException('This isn\'t a valid SVG file (${e.message}).');
  }

  final root = doc.rootElement;
  if (root.name.local.toLowerCase() != 'svg') {
    throw SvgSanitizeException('The file\'s root element must be <svg>.');
  }

  void sanitizeElement(XmlElement el) {
    // Strip event-handler attributes (onload, onclick, ...) and any
    // href/xlink:href that would trigger a network fetch.
    final toRemove = <XmlAttribute>[];
    for (final attr in el.attributes) {
      final name = attr.name.local.toLowerCase();
      if (name.startsWith('on')) {
        toRemove.add(attr);
      } else if (name == 'href' || name == 'xlink:href') {
        if (!_isSafeUriValue(attr.value)) toRemove.add(attr);
      }
    }
    for (final attr in toRemove) {
      el.attributes.remove(attr);
    }

    // Recurse into children first (post-order) so removing a disallowed
    // child element doesn't disturb iteration over its siblings.
    final childElements = el.children.whereType<XmlElement>().toList();
    for (final child in childElements) {
      if (_kDisallowedElements.contains(child.name.local.toLowerCase())) {
        el.children.remove(child);
      } else {
        sanitizeElement(child);
      }
    }
  }

  sanitizeElement(root);

  return doc.toXmlString();
}
