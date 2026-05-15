import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/document_comment.dart';
import 'package:digi_sanchika/services/api_client.dart';

class CommentsListResponse {
  final CollaborationStatus collaborationStatus;
  final List<DocumentComment> comments;

  const CommentsListResponse({
    required this.collaborationStatus,
    required this.comments,
  });
}

class CommentThreadResponse {
  final DocumentComment root;
  final List<DocumentComment> replies;

  const CommentThreadResponse({required this.root, required this.replies});
}

class CommentsService {
  Dio get _dio => ApiClient.instance.dio;

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) => v is List ? v : const [];

  Future<CommentsListResponse?> listRootComments(
    String documentId, {
    int? version,
  }) async {
    final resp = await _dio.get(
      '/documents/$documentId/comments',
      queryParameters: {if (version != null) 'version': version},
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final statusMap = _asMap(map['collaborationStatus']) ?? <String, dynamic>{'level': 'view_only', 'isLocked': false};
    final status = CollaborationStatus.fromJson(statusMap);
    final items = _asList(map['comments'] ?? map['items'] ?? map['data']);
    final comments = items
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(DocumentComment.fromJson)
        .toList();
    return CommentsListResponse(collaborationStatus: status, comments: comments);
  }

  Future<CommentThreadResponse?> getThread(String documentId, String commentId) async {
    final resp = await _dio.get(
      '/documents/$documentId/comments/$commentId/thread',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final thread = _asMap(map['thread']) ?? map;
    final root = _asMap(thread['root']);
    if (root == null) return null;
    final replies = _asList(thread['replies'])
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map((j) => DocumentComment.fromJson({...j, 'document_id': documentId, 'parent_id': commentId}))
        .toList();
    return CommentThreadResponse(root: DocumentComment.fromJson({...root, 'document_id': documentId}), replies: replies);
  }

  Future<DocumentComment?> createComment(
    String documentId, {
    required String content,
    String? parentId,
    int? pageNumber,
    double? x,
    double? y,
    String visibility = 'public',
    int? documentVersion,
  }) async {
    final resp = await _dio.post(
      '/documents/$documentId/comments',
      data: {
        'content': content,
        'parentId': parentId,
        if (pageNumber != null) 'pageNumber': pageNumber,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        'visibility': visibility,
        if (documentVersion != null) 'documentVersion': documentVersion,
      },
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final comment = _asMap(map['comment']) ?? map;
    if (comment['id'] == null) return null;
    return DocumentComment.fromJson(comment);
  }

  Future<DocumentComment?> updateComment(
    String documentId,
    String commentId, {
    required String content,
  }) async {
    final resp = await _dio.patch(
      '/documents/$documentId/comments/$commentId',
      data: {'content': content},
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final comment = _asMap(map['comment']) ?? map;
    if (comment['id'] == null) return null;
    return DocumentComment.fromJson(comment);
  }

  Future<bool> resolveThread(String documentId, String commentId) async {
    final resp = await _dio.post(
      '/documents/$documentId/comments/$commentId/resolve',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    return resp.statusCode == 200;
  }

  Future<bool> deleteComment(String documentId, String commentId) async {
    final resp = await _dio.delete(
      '/documents/$documentId/comments/$commentId',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    return resp.statusCode == 200;
  }
}

