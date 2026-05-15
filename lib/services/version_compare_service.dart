import 'package:digi_sanchika/models/version_compare.dart';
import 'package:digi_sanchika/services/versions_service.dart';

class VersionCompareService {
  final VersionsService _versions = VersionsService();

  Future<VersionCompare?> compareText({
    required String documentId,
    required String fromVersion,
    required String toVersion,
  }) async {
    final data = await _versions.compareText(
      documentId: documentId,
      versionFrom: fromVersion,
      versionTo: toVersion,
    );
    if (data == null) return null;
    final diff = data['diff'] ?? data;
    return VersionCompare.fromJson({
      'document_id': documentId,
      'versionFrom': fromVersion,
      'versionTo': toVersion,
      'diff': diff,
    });
  }

  Future<VersionCompare?> comparePdf({
    required String documentId,
    required String fromVersion,
    required String toVersion,
  }) async {
    final data = await _versions.comparePdf(
      documentId: documentId,
      versionFrom: fromVersion,
      versionTo: toVersion,
    );
    if (data == null) return null;
    final url = data['url'] ?? data['compareUrl'] ?? data['viewUrl'];
    return VersionCompare(
      documentId: documentId,
      fromVersion: fromVersion,
      toVersion: toVersion,
      compareUrl: url?.toString(),
    );
  }

  Future<bool> createSnapshot(String documentId) async {
    final snapshot = await _versions.snapshot(documentId);
    return snapshot != null;
  }
}
