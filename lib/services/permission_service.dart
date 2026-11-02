import 'package:permission_handler/permission_handler.dart';

/// Handles all runtime permission checks and requests for Digi Sanchika.
///
/// Document/photo/video uploads go through `file_picker`, which opens the
/// OS's own document/photo picker (Storage Access Framework on Android,
/// PHPickerViewController on iOS) — neither platform requires a storage or
/// media-library permission grant for that, so none is requested here.
///
/// What Digi Sanchika actually needs permission for:
///   - Camera   — scanning documents.
///   - Microphone — voice search.
///   - Notifications — push alerts.
class PermissionService {
  static const List<Permission> _required = [
    Permission.camera,
    Permission.microphone,
    Permission.notification,
  ];

  /// Returns a (granted, total) pair suitable for UI display.
  static Future<({int granted, int total})> permissionSummary() async {
    var granted = 0;
    for (final p in _required) {
      if (await p.isGranted) granted++;
    }
    return (granted: granted, total: _required.length);
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns `true` if the app is missing at least one required permission.
  static Future<bool> anyNotGranted() async {
    for (final p in _required) {
      if (!await p.isGranted) return true;
    }
    return false;
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
  static Future<int> grantedCount() async {
    final s = await permissionSummary();
    return s.granted;
  }

  /// Total number of permission slots shown in the UI.
  static int get totalCount => _required.length;

  /// Opens the OS app-settings page so the user can manually grant permissions.
  static Future<void> openSettings() => openAppSettings();
}
