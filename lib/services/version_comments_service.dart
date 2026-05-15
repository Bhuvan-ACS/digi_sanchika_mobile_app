import 'package:digi_sanchika/models/version_comment.dart';
import 'package:digi_sanchika/services/versions_service.dart';

class VersionCommentsService {
  final VersionsService _versions = VersionsService();

  Future<List<VersionComment>> listComments(
    String documentId, {
    required String versionTo,
    String? versionFrom,
  }) async {
    final items = await _versions.listComments(
      documentId: documentId,
      versionTo: versionTo,
      versionFrom: versionFrom,
    );
    return items
        .whereType<dynamic>()
        .map((c) => c is Map
            ? VersionComment.fromJson(Map<String, dynamic>.from(c))
            : VersionComment.fromJson(<String, dynamic>{}))
        .toList();
  }

  Future<bool> addComment({
    required String documentId,
    required String version,
    required String comment,
  }) async {
    final resp = await _versions.addComment(
      documentId: documentId,
      version: version,
      comment: comment,
    );
    return resp != null;
  }

  Future<bool> resolveComment(String commentId) async {
    return _versions.resolveComment(commentId);
  }

  Future<bool> deleteComment(String commentId) async {
    return _versions.deleteComment(commentId);
  }
}
