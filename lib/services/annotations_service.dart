import 'package:dio/dio.dart';
import 'package:digi_sanchika/models/document_annotation.dart';
import 'package:digi_sanchika/services/api_client.dart';

class AnnotationsResponse {
  final String collaborationLevel;
  final List<DocumentAnnotation> annotations;

  const AnnotationsResponse({
    required this.collaborationLevel,
    required this.annotations,
  });
}

class AnnotationsService {
  Dio get _dio => ApiClient.instance.dio;

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> _asList(dynamic v) => v is List ? v : const [];

  Future<AnnotationsResponse?> listAnnotations(
    String documentId, {
    int? version,
  }) async {
    final resp = await _dio.get(
      '/documents/$documentId/annotations',
      queryParameters: {if (version != null) 'version': version},
    );
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final level = (map['collaborationLevel'] ?? map['level'] ?? 'view_only').toString();
    final items = _asList(map['annotations'] ?? map['items'] ?? map['data']);
    final annotations = items
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .map(DocumentAnnotation.fromJson)
        .toList();
    return AnnotationsResponse(collaborationLevel: level, annotations: annotations);
  }

  Future<DocumentAnnotation?> createAnnotation(
    String documentId, {
    required String type,
    int? pageNumber,
    required double x,
    required double y,
    required double width,
    required double height,
    String? content,
    String? colorHex,
    double? opacity,
    double? strokeWidth,
    String visibility = 'public',
    int? documentVersion,
  }) async {
    final resp = await _dio.post(
      '/documents/$documentId/annotations',
      data: {
        'type': type,
        if (pageNumber != null) 'pageNumber': pageNumber,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        if (content != null) 'content': content,
        if (colorHex != null) 'color': colorHex,
        if (opacity != null) 'opacity': opacity,
        if (strokeWidth != null) 'strokeWidth': strokeWidth,
        'visibility': visibility,
        if (documentVersion != null) 'documentVersion': documentVersion,
      },
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final ann = _asMap(map['annotation']) ?? map;
    if (ann['id'] == null) return null;
    return DocumentAnnotation.fromJson(ann);
  }

  Future<DocumentAnnotation?> updateAnnotation(
    String documentId,
    String annotationId, {
    String? content,
    String? colorHex,
    double? opacity,
    double? x,
    double? y,
    double? width,
    double? height,
  }) async {
    final resp = await _dio.patch(
      '/documents/$documentId/annotations/$annotationId',
      data: {
        if (content != null) 'content': content,
        if (colorHex != null) 'color': colorHex,
        if (opacity != null) 'opacity': opacity,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      },
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 200) return null;
    final map = _asMap(resp.data);
    if (map == null) return null;
    final ann = _asMap(map['annotation']) ?? map;
    if (ann['id'] == null) return null;
    return DocumentAnnotation.fromJson(ann);
  }

  Future<bool> deleteAnnotation(String documentId, String annotationId) async {
    final resp = await _dio.delete(
      '/documents/$documentId/annotations/$annotationId',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    return resp.statusCode == 200;
  }

  Future<Map<String, dynamic>?> applyRedactions(String documentId) async {
    final resp = await _dio.post(
      '/documents/$documentId/annotations/apply-redactions',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 200) return null;
    if (resp.data is Map) return Map<String, dynamic>.from(resp.data as Map);
    return null;
  }
}

