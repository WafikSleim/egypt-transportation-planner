import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_failure.dart';

/// Thin JSON client over the project's own API. The app never talks to
/// OpenTripPlanner directly.
///
/// ### Why `lang` is injected here and nowhere else
///
/// Stop names, route display names and the origin/destination labels are all
/// localised **server-side** — the client's own translations cover chrome
/// only. So a screen can be fully Arabic and still show Latin stop names if
/// one call forgets `lang`, and that failure is silent and plausible: it
/// looks like an app that works.
///
/// Rather than trust every call site, this class adds `lang` to every request
/// from [languageCode]. There is no way to make the request without it.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required String Function() languageCode,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _languageCode = languageCode,
       _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final String Function() _languageCode;
  final http.Client _client;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: {...query, 'lang': _languageCode()});

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const ApiFailure(FailureKind.offline, detail: 'timeout');
    } on SocketException catch (e) {
      throw ApiFailure(FailureKind.offline, detail: e.message);
    } on http.ClientException catch (e) {
      throw ApiFailure(FailureKind.offline, detail: e.message);
    }

    if (response.statusCode >= 500) {
      throw ApiFailure(FailureKind.serverDown, status: response.statusCode);
    }
    if (response.statusCode >= 400) {
      throw ApiFailure(
        FailureKind.badRequest,
        status: response.statusCode,
        detail: _detail(response),
      );
    }

    try {
      // Decoded from bytes, not from `response.body`: the payload is Arabic
      // and `body` guesses latin-1 when the server omits a charset.
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw ApiFailure(FailureKind.unexpected, detail: e.message);
    }
  }

  String? _detail(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] != null) {
        return body['detail'].toString();
      }
    } catch (_) {
      // A non-JSON error body is not worth a second failure mode.
    }
    return null;
  }

  void close() => _client.close();
}
