import 'dart:convert';

import 'package:http/http.dart' as http;

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
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (accessToken != null) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
      final requestBody = body == null ? null : jsonEncode(body);
      final response = await switch (method) {
        'GET' => http.get(uri, headers: headers),
        'POST' => http.post(uri, headers: headers, body: requestBody),
        'PATCH' => http.patch(uri, headers: headers, body: requestBody),
        _ => throw ApiException('Unsupported method: $method'),
      };
      final text = response.body;
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
    } on http.ClientException {
      throw ApiException('Не удалось подключиться к API: $baseUrl');
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
