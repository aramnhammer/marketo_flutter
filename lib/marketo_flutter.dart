import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/src/mock_client.dart';

class MarketoException implements Exception {
  final String message;
  final int? statusCode;

  MarketoException(this.message, {this.statusCode});

  @override
  String toString() => 'MarketoException: $message';
}

class MarketoAuthResponse {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String scope;

  MarketoAuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.scope,
  });

  factory MarketoAuthResponse.fromJson(Map<String, dynamic> json) {
    return MarketoAuthResponse(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
      expiresIn: json['expires_in'],
      scope: json['scope'],
    );
  }
}

class MarketoConfig {
  final String identityUrl;
  final String clientId;
  final String clientSecret;

  MarketoConfig({
    required this.identityUrl,
    required this.clientId,
    required this.clientSecret,
  });
}

class MarketoClient {
  final MarketoConfig _config;
  http.Client httpClient;

  String? _accessToken;
  int? _tokenExpiry;  // this is in seconds

  factory MarketoClient(MarketoConfig config, {http.Client? httpClient}) {
    return MarketoClient._(config, httpClient ?? http.Client());
  }

  MarketoClient._(this._config, this.httpClient);

  Future<MarketoAuthResponse> authenticate() async {
    final uri = Uri.parse('${_config.identityUrl}/oauth/token').replace(
      queryParameters: {
        'grant_type': 'client_credentials',
        'client_id': _config.clientId,
        'client_secret': _config.clientSecret,
      },
    );
    try {

      final response = await httpClient.get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        _accessToken = jsonResponse['access_token'];
        _tokenExpiry = (DateTime.now().millisecondsSinceEpoch + (jsonResponse['expires_in'] * 1000)) as int?;

        return MarketoAuthResponse.fromJson(jsonResponse);

      } else {

        throw MarketoException('Failed to authenticate: ${response.body}', statusCode: response.statusCode);

      }
    } catch (e) {

      if (e is MarketoException) {
        rethrow;
      }

      throw MarketoException('Failed to authenticate: $e');
    }
  }

  Future<String> getAccessToken() async {
    if (_accessToken == null || _tokenExpiry == null || DateTime.now().millisecondsSinceEpoch > _tokenExpiry!) {
      final authResponse = await authenticate();
      _accessToken = authResponse.accessToken;
      _tokenExpiry = (DateTime.now().millisecondsSinceEpoch + (authResponse.expiresIn * 1000)) as int?;
    }

    return _accessToken!;
  }

  Future<Map<String, dynamic>> makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final accessToken = await getAccessToken();

    final uri = Uri.parse('${_config.identityUrl}/rest/$endpoint').replace(
      queryParameters: queryParameters,
    );

    final headers = {
      'Authorization' : 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };

    try {
      late http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await httpClient.get(uri, headers: headers);
          break;
        case 'POST':
          response = await httpClient.post(uri, headers: headers, body: json.encode(body));
          break;
        case 'PUT':
          response = await httpClient.put(uri, headers: headers, body: json.encode(body));
          break;
        case 'DELETE':
          response = await httpClient.delete(uri, headers: headers);
          break;
        default:
          throw MarketoException('Unsupported HTTP method: $method');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MarketoException('Request failed with status: ${response.statusCode}', statusCode: response.statusCode);
      }

      return json.decode(response.body);
    } catch (e) {
      if (e is MarketoException) {
        rethrow;
      }
      throw MarketoException('Request failed: $e');
    }
  }
  void dispose() {
    httpClient.close();
  }
}


