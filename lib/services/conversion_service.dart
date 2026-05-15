import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';
import 'package:digi_sanchika/models/conversion_status.dart';

class ConversionService {
  Dio get _dio => ApiClient.instance.dio;

  Future<ConversionStatus?> getStatus(String documentId) async {
    final response = await _dio.get('/conversion/$documentId/status');
    if (response.statusCode == 200) {
      return ConversionStatus.fromJson(response.data);
    }
    return null;
  }

  Future<bool> requestConversion(String documentId) async {
    final response = await _dio.post('/conversion/$documentId/convert');
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> downloadConverted(
    String documentId,
    String format,
  ) async {
    final response = await _dio.get(
      '/conversion/$documentId/download/$format',
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': response.data};
    }
    return {'success': false, 'message': 'Download failed'};
  }

  Future<bool> retryConversion(String documentId) async {
    final response = await _dio.post('/documents/$documentId/retry-conversion');
    return response.statusCode == 200;
  }
}
