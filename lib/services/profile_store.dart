import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:digi_sanchika/models/profile.dart';
import 'package:digi_sanchika/services/profile_service.dart';

/// App-wide profile state shared by Home, Profile and Edit Profile Details.
///
/// The server profile is loaded from `/auth/me`. The backend has no update
/// endpoint yet, so edits (and the chosen avatar) are kept on the device as
/// overrides layered on top of the server profile, keyed by the server's
/// employee ID so another account on the same device never inherits them.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();
  static final ProfileStore instance = ProfileStore._();

  static const _overridesPrefix = 'profile_overrides_';

  UserProfile? _serverProfile;
  Map<String, dynamic> _overrides = {};

  /// The profile with local edits applied, or null before the first load.
  UserProfile? get profile {
    final base = _serverProfile;
    if (base == null) return null;
    return base.copyWith(
      employeeName: _overrides['employeeName'] as String?,
      email: _overrides['email'] as String?,
      designation: _overrides['designation'] as String?,
      employeeId: _overrides['employeeId'] as String?,
      department: _overrides['department'] as String?,
      sinceYear: _overrides['sinceYear'] as String?,
    );
  }

  /// Encoded avatar choice (see `AvatarChoice`), or null for initials.
  String? get avatar => _overrides['avatar'] as String?;

  /// Fetches the server profile. Returns the raw service response so callers
  /// can handle errors (e.g. 401) the same way they did before.
  Future<Map<String, dynamic>> load() async {
    final response = await ProfileService.getUserProfile();
    if (response['success'] == true && response['data'] != null) {
      _serverProfile = UserProfile.fromJson(
        response['data'] as Map<String, dynamic>,
      );
      _overrides = await _readOverrides(_serverProfile!.employeeId);
      notifyListeners();
    }
    return response;
  }

  /// Persists the edited fields and avatar, then notifies every listener.
  Future<void> save({
    required String employeeName,
    required String email,
    required String designation,
    required String employeeId,
    required String department,
    required String sinceYear,
    required String? avatar,
  }) async {
    final base = _serverProfile;
    if (base == null) throw StateError('Profile not loaded');

    _overrides = {
      'employeeName': employeeName,
      'email': email,
      'designation': designation,
      'employeeId': employeeId,
      'department': department,
      'sinceYear': sinceYear,
      'avatar': avatar,
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_overridesPrefix${base.employeeId}',
      jsonEncode(_overrides),
    );
    notifyListeners();
  }

  Future<Map<String, dynamic>> _readOverrides(String serverEmployeeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_overridesPrefix$serverEmployeeId');
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      if (kDebugMode) print('Failed to read profile overrides: $e');
      return {};
    }
  }
}
