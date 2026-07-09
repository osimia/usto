import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  String? accessToken;
  String? refreshToken;

  Future<Map<String, dynamic>> getJson(String path) {
    return _request('GET', path);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _request('POST', path, body: body);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _request('PATCH', path, body: body);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (accessToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final data = text.isEmpty ? <String, dynamic>{} : _decodeObject(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = data['error'];
        if (error is Map && error['message'] is String) {
          throw ApiException(
            error['message'] as String,
            statusCode: response.statusCode,
          );
        }
        throw ApiException(
          'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      return data;
    } on SocketException {
      throw ApiException('Не удалось подключиться к API: $baseUrl');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeObject(String text) {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }
}
