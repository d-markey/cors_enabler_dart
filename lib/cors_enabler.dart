import 'dart:async';
import 'dart:io';

/// A tiny CORS proxy that listens on [host]:[port] and proxies requests to the
/// [target] URL.
///
/// Example: http://localhost:8080/some/url
class CorsProxy {
  final Uri target;
  final String host;
  final int port;
  final bool allowCredentials;

  HttpServer? _server;
  final HttpClient _client = HttpClient();
  final Set<String> _extraAllowedHeaders = {};

  /// Create a CORS proxy that forwards requests to [target].
  ///
  /// Example: `CorsProxy(target: Uri.parse('https://example.com/api'))` will
  /// forward requests from `http://cors-proxy/some/resource` to
  /// `https://example.com/api/some/resource`.
  CorsProxy({
    required this.target,
    this.host = '0.0.0.0',
    this.port = 8080,
    this.allowCredentials = false,
    Set<String>? extraAllowedHeaders,
  }) {
    if (extraAllowedHeaders != null) {
      _extraAllowedHeaders.addAll(extraAllowedHeaders);
    }
  }

  CorsProxy.mcp({
    required this.target,
    this.host = '0.0.0.0',
    this.port = 8080,
    this.allowCredentials = false,
    Set<String>? extraAllowedHeaders,
  }) {
    _extraAllowedHeaders.addAll({
      'Mcp-Session-Id',
      'Mcp-Protocol-Version',
      'Last-Event-Id',
    });
    if (extraAllowedHeaders != null) {
      _extraAllowedHeaders.addAll(extraAllowedHeaders);
    }
  }

  /// The actual port the server is bound to; only available after [start]
  /// has returned.
  int? get boundPort => _server?.port;

  /// Starts the proxy server and returns when it's ready to accept requests.
  Future<void> start() async {
    _server = await HttpServer.bind(host, port);
    _server!.listen(_handleRequest);
  }

  Uri _buildTargetUri(Uri reqUri) {
    // Merge path segments from target and the incoming request.
    final List<String> segments = [];
    for (final s in target.pathSegments) {
      if (s.isNotEmpty) segments.add(s);
    }
    for (final s in reqUri.pathSegments) {
      if (s.isNotEmpty) segments.add(s);
    }

    final path = segments.isEmpty ? '/' : '/${segments.join('/')}';

    // Merge query parameters: target's params first, then request's params
    final combinedQuery = <String, String>{};
    combinedQuery.addAll(target.queryParameters);
    combinedQuery.addAll(reqUri.queryParameters);

    return Uri(
      scheme: target.scheme,
      userInfo: target.userInfo,
      host: target.host,
      port:
          target.hasPort ? target.port : (target.scheme == 'https' ? 443 : 80),
      path: path,
      queryParameters: combinedQuery.isEmpty ? null : combinedQuery,
    );
  }

  /// Stop the server if running.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest req) async {
    // Always respond to preflight with CORS headers
    if (req.method.toUpperCase() == 'OPTIONS') {
      _setCorsHeaders(req.response, req);
      req.response.statusCode = HttpStatus.noContent;
      return req.response.close();
    }

    // Build the target URI by combining the configured `target` with the
    // incoming request path and query parameters.
    final targetUri = _buildTargetUri(req.uri);

    try {
      // Create request to remote
      final proxiedReq = await _client.openUrl(req.method, targetUri);

      // Copy headers from incoming request (but don't forward host)
      req.headers.forEach((name, values) {
        if (name.toLowerCase() == 'host') return;
        for (final v in values) {
          try {
            proxiedReq.headers.add(name, v);
          } catch (_) {}
        }
      });

      // Stream body
      await req.cast<List<int>>().pipe(proxiedReq);

      final proxiedResp = await proxiedReq.close();

      // Forward status
      req.response.statusCode = proxiedResp.statusCode;

      // Copy headers, excluding transfer-encoding hop-by-hop headers
      proxiedResp.headers.forEach((name, values) {
        if (name.toLowerCase() == 'transfer-encoding') return;
        for (final v in values) {
          try {
            req.response.headers.add(name, v);
          } catch (_) {}
        }
      });

      // Always allow CORS
      _setCorsHeaders(req.response, req);

      // Pipe body
      await proxiedResp.pipe(req.response);
    } catch (err) {
      req.response.statusCode = HttpStatus.internalServerError;
      _setCorsHeaders(req.response, req);
      req.response.write('Proxy error: $err');
      req.response.close().ignore();
    }
  }

  /// Set CORS headers, merging any requested preflight headers so clients
  /// can use custom authentication/authorization headers.
  void _setCorsHeaders(HttpResponse response, [HttpRequest? request]) {
    // Defaults we always allow
    final defaults = <String>{
      'Origin',
      'Content-Type',
      'Accept',
      'Authorization',
      'Authentication',
    };

    // Add MCP-specific headers configured on this proxy
    defaults.addAll(_extraAllowedHeaders);

    // Add any headers requested by the client in the preflight
    final requested = request?.headers.value('access-control-request-headers');
    if (requested != null && requested.isNotEmpty) {
      for (final part in requested.split(',')) {
        final h = part.trim();
        if (h.isNotEmpty) defaults.add(h);
      }
    }

    // Origin handling: if credentials are allowed, we must echo the Origin
    // (cannot use '*'). Otherwise '*' is acceptable.
    final origin = request?.headers.value('origin');
    if (allowCredentials && origin != null && origin.isNotEmpty) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Access-Control-Allow-Credentials', 'true');
    } else {
      response.headers.set('Access-Control-Allow-Origin', '*');
    }

    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, DELETE, OPTIONS, PATCH',
    );
    response.headers.set('Access-Control-Allow-Headers', defaults.join(', '));

    // Expose auth-related headers so client-side code can read them if set
    final expose = <String>{'authorization', 'www-authenticate'};
    expose.addAll(_extraAllowedHeaders.map((h) => h.toLowerCase()));
    response.headers.set('Access-Control-Expose-Headers', expose.join(', '));
  }
}
