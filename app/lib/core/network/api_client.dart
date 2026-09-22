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
///
/// ### Every request has a ceiling
///
/// The target phone is on patchy data in Cairo, where a request that is going
/// to fail often fails by never finishing. A request with no ceiling is a
/// spinner with no ceiling, so [timeout] applies to every call and a call may
/// shorten or lengthen it for itself — see [defaultTimeout] and [planTimeout]
/// for why the two numbers differ.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required String Function() languageCode,
    http.Client? client,
    this.timeout = defaultTimeout,
  }) : _languageCode = languageCode,
       _client = client ?? http.Client();

  /// For the small, repeatable calls — `/stops`, `/attribution`.
  ///
  /// Eight seconds. A healthy one of these answers in well under a second, so
  /// this is already generous; and a stop search that takes longer than this
  /// has been overtaken by the letters the user typed while waiting.
  static const defaultTimeout = Duration(seconds: 8);

  /// For `/plan`, which is the expensive call and the one with no
  /// alternative.
  ///
  /// Twelve seconds. Routing plus the Arabic stop-name round trip is roughly
  /// a second on a good connection, and a bad connection multiplies that
  /// rather than adding to it. The old ceiling was twenty seconds for
  /// everything, which on a weak signal is twenty seconds of staring before
  /// being told something the first four made likely.
  static const planTimeout = Duration(seconds: 12);

  final String baseUrl;
  final Duration timeout;
  final String Function() _languageCode;
  final http.Client _client;

  /// The language every request is being made in. Exposed so a cached
  /// response can record which language it was fetched in — names are
  /// localised server-side, so an Arabic body is not an English one.
  String get languageCode => _languageCode();

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> query = const {},
    Duration? timeout,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: {...query, 'lang': _languageCode()});

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw ApiFailure(
        FailureKind.timedOut,
        detail: '${(timeout ?? this.timeout).inSeconds}s',
      );
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
