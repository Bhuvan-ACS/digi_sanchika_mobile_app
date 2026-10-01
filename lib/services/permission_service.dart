import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Handles runtime permissions for Digi Sanchika.
///
/// Android uploads use system pickers (Photo Picker / Storage Access Framework)
/// so the app does not request broad media or storage permissions.
///
/// iOS keeps the existing photo-library permission behavior.
class PermissionService {
  static List<Permission> get _required =>
      Platform.isIOS ? const [Permission.photos] : const [];

  /// Returns a (granted, total) pair suitable for UI display.
  static Future<({int granted, int total})> permissionSummary() async {
    if (!Platform.isIOS) {
      return (granted: 0, total: 0);
    }

    final granted = (await Permission.photos.isGranted) ? 1 : 0;
    return (granted: granted, total: 1);
  }

  /// Returns `true` if the app is missing at least one required permission.
  static Future<bool> anyNotGranted() async {
    if (!Platform.isIOS) return false;
    return !(await Permission.photos.isGranted);
  }

  /// Returns the status of every required permission.
  static Future<Map<Permission, PermissionStatus>> checkAll() async {
    final Map<Permission, PermissionStatus> result = {};
    for (final p in _required) {
      result[p] = await p.status;
    }
    return result;
  }

  /// Requests required permissions and returns the result map.
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    if (_required.isEmpty) return <Permission, PermissionStatus>{};
    return _required.request();
  }

  /// How many required permissions are currently granted.
  static Future<int> grantedCount() async {
    final s = await permissionSummary();
    return s.granted;
  }

  /// Total number of permission slots shown in the UI.
  static int get totalCount => Platform.isIOS ? 1 : 0;

  /// Opens the OS app-settings page so the user can manually grant permissions.
  static Future<void> openSettings() => openAppSettings();
}