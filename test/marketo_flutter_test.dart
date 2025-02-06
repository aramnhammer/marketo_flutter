import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:marketo_flutter/marketo_flutter.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MarketoClient client;
  final config = MarketoConfig(
    identityUrl: 'https://test.marketo.com',
    clientId: 'test_client_id',
    clientSecret: 'test_client_secret',
  );

  group('MarketoClient Authentication Tests', () {
    test('successful authentication returns valid token', () async {

      // confusing syntax: here we create our handler function that actually does the testing of the request we generate later in the
      // test when we call client.authenticate()
      final mockClient = MockClient((request) async {
        
        expect(request.method, equals('GET'));
        expect(
          request.url.toString(),
          equals(
            'https://test.marketo.com/oauth/token'
            '?grant_type=client_credentials'
            '&client_id=test_client_id'
            '&client_secret=test_client_secret'
          ),
        );

        return http.Response(
          json.encode({
            'access_token': 'test_token',
            'token_type': 'bearer',
      'expires_in': 3599,
            'scope': 'test@example.com'
          }),
          200,
        );
      });

      client = MarketoClient(config, httpClient: mockClient);

      final authResponse = await client.authenticate();
      
      expect(authResponse.accessToken, equals('test_token'));
      expect(authResponse.tokenType, equals('bearer'));
      expect(authResponse.expiresIn, equals(3599));
      expect(authResponse.scope, equals('test@example.com'));
    });

    test('authentication failure throws MarketoException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error": "Invalid client credentials"}', 401);
      });

      client = MarketoClient(config);
      client.httpClient = mockClient;

      expect(
        () => client.authenticate(),
        throwsA(isA<MarketoException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('network error during authentication throws MarketoException', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      client = MarketoClient(config);
      client.httpClient = mockClient;

      expect(
        () => client.authenticate(),
        throwsA(isA<MarketoException>()),
      );
    });
  });

  group('MarketoClient API Request Tests', () {
    test('makeRequest includes valid authentication token', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('oauth/token')) {
          return http.Response(
            json.encode({
              'access_token': 'test_token',
              'token_type': 'bearer',
              'expires_in': 3599,
              'scope': 'test@example.com'
            }),
            200,
          );
        }

        expect(request.headers['Authorization'], equals('Bearer test_token'));
        expect(request.headers['Content-Type'], equals('application/json'));

        return http.Response(
          json.encode({'success': true, 'data': []}),
          200,
        );
      });

      client = MarketoClient(config);
      client.httpClient = mockClient;

      final response = await client.makeRequest(
        'GET',
        'https://test.marketo.com/rest/v1/leads.json',
        queryParameters: {'filterType': 'email'},
      );

      expect(response['success'], isTrue);
      expect(response['data'], isEmpty);
    });

    test('expired token triggers re-authentication', () async {
      var authCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('oauth/token')) {
          authCount++;
          return http.Response(
            json.encode({
              'access_token': 'test_token_$authCount',
              'token_type': 'bearer',
              'expires_in': 0, // Immediately expired token
              'scope': 'test@example.com'
            }),
            200,
          );
        }

        // Verify we're using the new token
        expect(
          request.headers['Authorization'],
          equals('Bearer test_token_2'),
        );

        return http.Response(
          json.encode({'success': true}),
          200,
        );
      });

      client = MarketoClient(config);
      client.httpClient = mockClient;

      // Initial authentication
      await client.authenticate();
      
      // Wait a moment to ensure token expires
      await Future.delayed(Duration(milliseconds: 100));
      
      // Make request with expired token
      final response = await client.makeRequest(
        'GET',
        'https://test.marketo.com/rest/v1/leads.json',
      );

      expect(authCount, equals(2));
      expect(response['success'], isTrue);
    });

    test('API error response throws MarketoException', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('oauth/token')) {
          return http.Response(
            json.encode({
              'access_token': 'test_token',
              'token_type': 'bearer',
              'expires_in': 3599,
              'scope': 'test@example.com'
            }),
            200,
          );
        }

        return http.Response(
          json.encode({
            'error': 'Invalid parameter',
            'error_description': 'Parameter x is required'
          }),
          400,
        );
      });

      client = MarketoClient(config);
      client.httpClient = mockClient;

      expect(
        () => client.makeRequest(
          'GET',
          'https://test.marketo.com/rest/v1/leads.json',
        ),
        throwsA(isA<MarketoException>()
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  test('dispose closes HTTP client', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{}', 200);
    });

    client = MarketoClient(config);
    client.httpClient = mockClient;
    
    client.dispose();
    
    expect(
      () => client.makeRequest('GET', 'https://test.marketo.com/test'),
      throwsA(isA<MarketoException>()),
    );
  });
}
