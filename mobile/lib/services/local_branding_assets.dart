import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Local-first branding assets (custom background wallpaper + logo).
///
/// Design: images are copied into the app's own persistent documents
/// directory under a FIXED filename per asset type (not the picker's
/// original filename), so there is always at most one saved background
/// and one saved logo on-device -- picking a new one simply overwrites
/// the old file at the same path. This keeps AppearanceSettings' stored
/// value a stable, predictable path string that survives app restarts
/// (unlike the raw path ImagePicker returns, which points into a cache
/// directory that the OS can clear at any time).
///
/// This is the "local" half of the local-vs-backend choice Vinay asked
/// for. The backend/synced half (reusing tenantLogos.js's existing
/// Supabase Storage infra) is a separate, later chunk -- deliberately
/// not mixed into this one, since it needs the live backend route file
/// reviewed first rather than guessed at.
class LocalBrandingAssets {
  LocalBrandingAssets._();

  static const _backgroundFileName = 'custom_background_wallpaper.jpg';
  static const _logoFileName = 'custom_branding_logo.png';

  static Future<String> _appDocsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<String?> pickAndSaveBackground() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return null;
    final docsPath = await _appDocsPath();
    final savedPath = '$docsPath/$_backgroundFileName';
    await File(picked.path).copy(savedPath);
    return savedPath;
  }

  static Future<String?> pickAndSaveLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) return null;
    final docsPath = await _appDocsPath();
    final savedPath = '$docsPath/$_logoFileName';
    await File(picked.path).copy(savedPath);
    return savedPath;
  }

  static Future<void> deleteBackground() async {
    final docsPath = await _appDocsPath();
    final f = File('$docsPath/$_backgroundFileName');
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteLogo() async {
    final docsPath = await _appDocsPath();
    final f = File('$docsPath/$_logoFileName');
    if (await f.exists()) await f.delete();
  }
}
