import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'security.dart';

/// One deadline, bounded streaming body, and explicit redirect policy. Closing
/// the per-request client also cancels the socket when the deadline expires.
class MobileHttp {
  MobileHttp({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;

  static Uri validateUri(Uri uri, {bool allowDevelopmentHttp = kDebugMode}) {
    final raw = uri.toString();
    final local = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '10.0.2.2',
    }.contains(uri.host);
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        raw.length > 8192 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(raw) ||
        !(uri.scheme == 'https' ||
            (allowDevelopmentHttp && uri.scheme == 'http' && local))) {
      throw const MobileSecurityException('msg.httpsRequired');
    }
    return uri;
  }

  static bool redirectAllowed(Uri initial, Uri next) {
    if (initial.scheme == 'https') return next.scheme == 'https';
    return initial.origin == next.origin;
  }

  Future<http.Response> request(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
    bool subscription = false,
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = maxSubscriptionBytes,
  }) async {
    validateUri(uri);
    final client = _clientFactory();
    Future<http.Response> perform() async {
      var current = uri;
      for (var redirects = 0; ; redirects++) {
        final req = http.Request(method, current)..followRedirects = false;
        req.headers.addAll(headers);
        if (body != null) req.body = body;
        final response = await client.send(req);
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          // Account API calls never forward bearer tokens or login bodies.
          if (!subscription || method != 'GET' || redirects >= 3) {
            throw const MobileSecurityException('msg.redirectRejected');
          }
          final location = response.headers['location'];
          if (location == null) {
            throw const MobileSecurityException('msg.redirectRejected');
          }
          final next = validateUri(current.resolve(location));
          if (!redirectAllowed(uri, next)) {
            throw const MobileSecurityException('msg.redirectRejected');
          }
          // Cancel rather than drain an untrusted, potentially endless body.
          await response.stream.listen((_) {}).cancel();
          current = next;
          continue;
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw const MobileSecurityException('msg.subscriptionTooLarge');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const MobileSecurityException('msg.subscriptionTooLarge');
          }
          bytes.add(chunk);
        }
        return http.Response.bytes(
          bytes.takeBytes(),
          response.statusCode,
          headers: response.headers,
          request: req,
        );
      }
    }

    try {
      return await perform().timeout(timeout);
    } on MobileSecurityException {
      rethrow;
    } catch (_) {
      // ClientException / SocketException often include the full token URL.
      throw const MobileSecurityException('msg.networkFailed');
    } finally {
      client.close();
    }
  }
}
