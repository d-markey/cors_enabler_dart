import 'dart:io';

import '_utils.dart';

/// Standard MCP headers.
const defaultMcpHeaders = {
  'Mcp-Session-Id',
  'Mcp-Protocol-Version',
  'Last-Event-Id',
};

/// Default headers allowed for CORS.
const defaultAllowedHeaders = {
  'Origin',
  'Content-Type',
  'Accept',
  'Authorization',
  'Authentication',
};

/// Extension accessors for headers
extension HeadersExt on HttpHeaders {
  /// Get the `Origin` header.
  String get origin => value('origin') ?? '';

  /// Get the `Access-Control-Request-Headers` header.
  String get accessControlRequestHeaders =>
      value('access-control-request-headers') ?? '';

  /// Get the `Access-Control-Allow-Origin` header.
  String get accessControlAllowOrigin =>
      value('Access-Control-Allow-Origin') ?? '';

  /// Set the `Access-Control-Allow-Origin` header.
  set accessControlAllowOrigin(String value) =>
      set('Access-Control-Allow-Origin', value);

  /// Set/unset the `Access-Control-Allow-Credentials` header.
  set accessControlAllowCredentials(bool value) {
    if (value) {
      set('Access-Control-Allow-Credentials', 'true');
    } else {
      removeAll('Access-Control-Allow-Credentials');
    }
  }

  /// Set the `Access-Control-Allow-Methods` header.
  set accessControlAllowMethods(Iterable<String> value) =>
      set('Access-Control-Allow-Methods', value.join(', '));

  /// Get the `Access-Control-Allow-Headers` header.
  List<String> get accessControlAllowHeaders =>
      value(
        'Access-Control-Allow-Headers',
      )?.split(',').map(toLowerCase).map(trim).toList() ??
      const [];

  /// Set the `Access-Control-Allow-Headers` header.
  set accessControlAllowHeaders(Iterable<String> value) =>
      set('Access-Control-Allow-Headers', value.join(', '));

  /// Set the `Access-Control-Expose-Headers` header.
  set accessControlExposeHeaders(Iterable<String> value) =>
      set('Access-Control-Expose-Headers', value.join(', '));
}
