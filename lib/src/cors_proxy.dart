import 'dart:async';
import 'dart:io';

import '_utils.dart';
import 'cors_headers.dart';

/// A tiny CORS proxy that listens on [host]:[port] and proxies requests to the
/// [target] URL.
///
/// Example: http://localhost:8080/some/resource --> [target]/some/resource
class CorsProxy {
  final Uri target;
  final String host;
  final int port;
  final bool allowCredentials;

  HttpServer? _server;
  final String _targetSegments;
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
    Iterable<String>? extraAllowedHeaders,
  }) : _targetSegments =
           target.pathSegments.where(isNotEmpty).map((s) => '/$s').join() {
    if (extraAllowedHeaders != null) {
      _extraAllowedHeaders.addAll(extraAllowedHeaders.map(toLowerCase));
    }
  }

  /// Create a CORS proxy that forwards requests to [target]. Same as the
  /// default constructor, only this constructor already takes into account
  /// MCP protocol headers (see [defaultMcpHeaders]).
  CorsProxy.mcp({
    required Uri target,
    String host = '0.0.0.0',
    int port = 8080,
    bool allowCredentials = false,
    Iterable<String>? extraAllowedHeaders,
  }) : this(
         target: target,
         host: host,
         port: port,
         allowCredentials: allowCredentials,
         extraAllowedHeaders:
             (extraAllowedHeaders == null)
                 ? defaultMcpHeaders
                 : defaultMcpHeaders.followedBy(extraAllowedHeaders),
       );

  /// Whether the proxy is running or not. `false` by default or after calling
  /// [stop], `true` after a successful call to [start].
  bool get isRunning => (_server != null);

  /// The actual port the proxy is bound to; will throw when [isRunning] is
  /// `false`.
  int get boundPort => _server!.port;

  /// Starts the proxy server and returns when it's ready to accept requests.
  Future<void> start() async {
    _server ??= (await HttpServer.bind(host, port))..listen(_handleRequest);
  }

  Uri _buildTargetUri(Uri reqUri) {
    // merge path segments from target and the incoming request
    final path =
        '$_targetSegments/${reqUri.pathSegments.where(isNotEmpty).join('/')}';

    // merge query parameters: target's params first, then request's params
    final queryParameters = {
      ...target.queryParameters,
      ...reqUri.queryParameters,
    };

    return Uri(
      scheme: target.scheme,
      userInfo: target.userInfo,
      host: target.host,
      port: target.hasPort ? target.port : target.defaultHttpPort,
      path: path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  /// Stop the server if running.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final resp = req.response;

    // always respond to preflight with CORS headers
    if (req.method.toUpperCase() == 'OPTIONS') {
      _setCorsHeaders(resp.headers, req);
      resp.statusCode = HttpStatus.noContent;
      return resp.close();
    }

    // build the target URI from the requested URI
    final targetUri = _buildTargetUri(req.uri);

    try {
      // forward incoming request (except "host" header) to [targetUri]
      final proxiedReq = await _client.openUrl(req.method, targetUri);
      proxiedReq.headers.copy(req.headers, except: const ['host']);
      await req.cast<List<int>>().pipe(proxiedReq);

      // wait for response...
      final proxiedResp = await proxiedReq.close();

      // forward response (excluding "transfer-encoding" headers), always
      // including CORS headers
      resp.statusCode = proxiedResp.statusCode;
      resp.headers.copy(
        proxiedResp.headers,
        except: const ['transfer-encoding'],
      );
      _setCorsHeaders(resp.headers, req);
      await proxiedResp.pipe(resp);
    } catch (err) {
      resp.statusCode = HttpStatus.internalServerError;
      _setCorsHeaders(resp.headers, req);
      resp.write('Proxy error: $err');
      await resp.close();
    }
  }

  void _setCorsHeaders(HttpHeaders headers, HttpRequest req) {
    // set CORS headers and headers configured on this proxy
    final allowedHeaders = {...defaultAllowedHeaders, ..._extraAllowedHeaders};

    // add any headers requested by the client in the preflight
    allowedHeaders.addAll(
      req.headers.accessControlRequestHeaders
          .split(',')
          .map(trim)
          .where(isNotEmpty),
    );

    final origin = allowCredentials ? req.headers.origin : '';
    if (origin.isNotEmpty) {
      // if credentials are allowed, we must echo the Origin (cannot use '*')
      headers.accessControlAllowOrigin = origin;
      headers.accessControlAllowCredentials = true;
    } else {
      // otherwise '*' is acceptable
      headers.accessControlAllowOrigin = '*';
    }

    headers.accessControlAllowHeaders = allowedHeaders;
    headers.accessControlAllowMethods = const {
      'GET, POST, PUT, DELETE, OPTIONS, PATCH',
    };

    // Expose auth-related headers so client-side code can read them if set
    headers.accessControlExposeHeaders = {
      'authorization',
      'www-authenticate',
      ..._extraAllowedHeaders,
    };
  }
}

extension on Uri {
  int get defaultHttpPort {
    switch (scheme.toLowerCase()) {
      case 'https':
        return 443;
      case 'http':
        return 80;
      default:
        return 0;
    }
  }
}

extension on HttpHeaders {
  /// Copy all headers from [source] into this instance apart from [except].
  void copy(HttpHeaders source, {Iterable<String>? except}) {
    final blackList = except?.map(toLowerCase).toSet() ?? const {};

    source.forEach((name, values) {
      if (blackList.contains(name.toLowerCase())) return;
      for (final v in values) {
        try {
          add(name, v);
        } catch (_) {}
      }
    });
  }
}
