import 'package:dio/dio.dart';
import 'package:digi_sanchika/services/api_client.dart';

class CollaborationLockService {
  Dio get _dio => ApiClient.instance.dio;

  Future<bool> lock(String documentId) async {
    final resp = await _dio.post(
      '/documents/$documentId/collaboration/lock',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    return resp.statusCode == 200;
  }

  Future<bool> unlock(String documentId) async {
    final resp = await _dio.delete(
      '/documents/$documentId/collaboration/lock',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    return resp.statusCode == 200;
  }
}

