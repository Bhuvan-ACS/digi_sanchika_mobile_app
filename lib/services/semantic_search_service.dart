import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/semantic_index_status.dart';

class SemanticSearchService {
  Dio get _dio => ApiClient.instance.dio;

  Future<Map<String, dynamic>> semanticSearch(Map<String, dynamic> payload) async {
    final response = await _dio.post('/search/semantic', data: payload);
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Search failed'};
  }

  Future<SemanticIndexStatus?> getIndexStatus(String documentId) async {
    final response = await _dio.get('/documents/$documentId/semantic-status');
    if (response.statusCode == 200) {
      return SemanticIndexStatus.fromJson(response.data);
    }
    return null;
  }

  Future<bool> rerunIndexing(String documentId) async {
    final response = await _dio.post('/documents/$documentId/semantic-rerun');
    return response.statusCode == 200;
  }
}
