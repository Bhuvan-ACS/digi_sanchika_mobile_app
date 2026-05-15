import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/ocr_status.dart';

class OcrService {
  Dio get _dio => ApiClient.instance.dio;

  Future<OcrStatus?> getStatus(String documentId) async {
    final response = await _dio.get('/ocr/$documentId/status');
    if (response.statusCode == 200) {
      return OcrStatus.fromJson(response.data);
    }
    return null;
  }

  Future<String?> getText(String documentId) async {
    final response = await _dio.get('/ocr/$documentId/text');
    if (response.statusCode == 200) {
      final data = response.data;
      return data is Map<String, dynamic> ? data['text']?.toString() : data.toString();
    }
    return null;
  }

  Future<bool> retry(String documentId) async {
    final response = await _dio.post('/ocr/$documentId/retry');
    return response.statusCode == 200;
  }

  Future<bool> queue(String documentId) async {
    final response = await _dio.post('/ocr/$documentId/queue');
    return response.statusCode == 200;
  }
}
