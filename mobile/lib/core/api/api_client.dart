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
  static const _timeout = Duration(seconds: 12);

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

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fieldName,
    required String filePath,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers['Accept'] = 'application/json';
      if (accessToken != null) {
        request.headers['Authorization'] = 'Bearer $accessToken';
      }
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } on http.ClientException {
      throw ApiException('Не удалось подключиться к API: $baseUrl');
    } on Exception catch (error) {
      if (error.toString().contains('TimeoutException')) {
        throw ApiException(
          'Сервер отвечает слишком долго. Попробуйте ещё раз.',
        );
      }
      rethrow;
    }
  }

  String mediaUrl(String url) {
    if (url.isEmpty ||
        url.startsWith('http://') ||
        url.startsWith('https://')) {
      return url;
    }
    final api = Uri.parse(baseUrl);
    final origin = api.replace(path: '', query: '', fragment: '').toString();
    return '${origin.replaceFirst(RegExp(r'/$'), '')}$url';
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
        'GET' => http.get(uri, headers: headers).timeout(_timeout),
        'POST' =>
          http.post(uri, headers: headers, body: requestBody).timeout(_timeout),
        'PATCH' =>
          http
              .patch(uri, headers: headers, body: requestBody)
              .timeout(_timeout),
        _ => throw ApiException('Unsupported method: $method'),
      };
      return _handleResponse(response);
    } on http.ClientException {
      throw ApiException('Не удалось подключиться к API: $baseUrl');
    } on Exception catch (error) {
      if (error.toString().contains('TimeoutException')) {
        throw ApiException(
          'Сервер отвечает слишком долго. Попробуйте ещё раз.',
        );
      }
      rethrow;
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
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
  }

  Map<String, dynamic> _decodeObject(String text) {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }
}
