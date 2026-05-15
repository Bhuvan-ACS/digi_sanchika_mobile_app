import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Handles all runtime permission checks and requests for Digi Sanchika.
///
/// Android strategy:
///   - Android 13+ (API 33+): request READ_MEDIA_IMAGES / VIDEO / AUDIO
///   - Android < 13          : request READ_EXTERNAL_STORAGE (Permission.storage)
///   - "Fully permitted" means EITHER storage is granted  OR all three
///     granular permissions are granted — whichever applies to the device.
///
/// iOS strategy:
///   - Only Permission.photos is required.
class PermissionService {
  // ── Required permissions by platform ────────────────────────────────────────

  static List<Permission> get _androidAll => [
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ];

  static List<Permission> get _iosAll => [Permission.photos];

  static List<Permission> get _required =>
      Platform.isIOS ? _iosAll : _androidAll;

  /// Returns a (granted, total) pair suitable for UI display.
  ///
  /// Android notes:
  /// - Android 13+ uses granular media permissions; `storage` isn't applicable.
  /// - Android < 13 uses `storage` as umbrella permission.
  static Future<({int granted, int total})> permissionSummary() async {
    if (Platform.isIOS) {
      final granted = (await Permission.photos.isGranted) ? 1 : 0;
      return (granted: granted, total: 1);
    }

    final storageGranted = await Permission.storage.isGranted;
    if (storageGranted) return (granted: 4, total: 4);

    // If granular permissions are granted, treat this as Android 13+ and show total=3.
    final photos = await Permission.photos.isGranted;
    final videos = await Permission.videos.isGranted;
    final audio = await Permission.audio.isGranted;

    if (photos || videos || audio) {
      final granted = (photos ? 1 : 0) + (videos ? 1 : 0) + (audio ? 1 : 0);
      return (granted: granted, total: 3);
    }

    // Unknown state (likely old Android with storage denied): keep previous UX.
    return (granted: 0, total: 4);
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns `true` if the app is missing at least one required permission.
  static Future<bool> anyNotGranted() async {
    if (Platform.isIOS) {
      return !(await Permission.photos.isGranted);
    }
    // Android: accept EITHER legacy storage OR all modern granular permissions.
    if (await Permission.storage.isGranted) return false;
    final photos = await Permission.photos.isGranted;
    final videos = await Permission.videos.isGranted;
    final audio = await Permission.audio.isGranted;
    return !(photos && videos && audio);
  }

  /// Returns the status of every required permission.
  static Future<Map<Permission, PermissionStatus>> checkAll() async {
    final Map<Permission, PermissionStatus> result = {};
    for (final p in _required) {
      result[p] = await p.status;
    }
    return result;
  }

  /// Requests all required permissions and returns the result map.
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    return await _required.request();
  }

  /// How many required permissions are currently granted.
  /// On Android, if legacy `storage` is granted we count everything as granted.
  static Future<int> grantedCount() async {
    final s = await permissionSummary();
    return s.granted;
  }

  /// Total number of permission slots shown in the UI.
  static int get totalCount => Platform.isIOS ? 1 : 4;

  /// Opens the OS app-settings page so the user can manually grant permissions.
  static Future<void> openSettings() => openAppSettings();
}
