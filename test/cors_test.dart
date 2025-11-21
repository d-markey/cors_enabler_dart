import 'dart:convert';
import 'dart:io';

import 'package:cors_enabler/cors_enabler.dart';
import 'package:test/test.dart';

void main() {
  HttpServer? $upstream;

  HttpServer upstreamServer() => $upstream!;

  setUpAll(() async {
    // Start a simple upstream test server
    $upstream ??= (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
      ..listen((HttpRequest request) async {
        request.response.headers.set('x-upstream', 'yes');
        request.response.statusCode = HttpStatus.ok;
        request.response.write('upstream:${request.method} ${request.uri}');
        await request.response.close();
      });
  });

  tearDownAll(() async {
    final upstream = $upstream;
    $upstream = null;
    return upstream?.close(force: true);
  });

  Future<(CorsProxy, Uri)> startProxy({
    bool mcp = false,
    bool allowCredentials = false,
  }) async {
    // Start the CORS proxy; bind to ephemeral port and point it at the
    // upstream test server.
    final upstream = upstreamServer();
    final upstreamUri = Uri.parse(
      'http://${upstream.address.address}:${upstream.port}/',
    );

    final proxyCtor = mcp ? CorsProxy.mcp : CorsProxy.new;
    final proxy = proxyCtor(
      target: upstreamUri,
      host: InternetAddress.loopbackIPv4.address,
      allowCredentials: allowCredentials,
      port: 0,
    );
    await proxy.start();

    final proxyPort = proxy.boundPort!;
    return (proxy, Uri.parse('http://${proxy.host}:$proxyPort/'));
  }

  test('CORS proxy forwards request', () async {
    final (proxy, proxyUri) = await startProxy();

    final client = HttpClient();
    final req = await client.getUrl(proxyUri);
    final resp = await req.close();
    final body = await utf8.decoder.bind(resp).join();

    expect(resp.statusCode, HttpStatus.ok);
    expect(resp.accessControlAllowOrigin, '*');
    expect(body, 'upstream:GET /');

    client.close();
    await proxy.stop();
  });

  test('CORS proxy sets CORS headers', () async {
    final (proxy, proxyUri) = await startProxy();

    final client = HttpClient();
    final req = await client.openUrl('OPTIONS', proxyUri);
    final resp = await req.close();
    expect(resp.statusCode, equals(HttpStatus.noContent));
    expect(resp.accessControlAllowOrigin, '*');

    client.close();
    await proxy.stop();
  });

  test('CORS proxy sets CORS headers - allowCredentials = true', () async {
    final (proxy, proxyUri) = await startProxy(allowCredentials: true);

    final client = HttpClient();
    final req = await client.openUrl('OPTIONS', proxyUri);
    req.headers.add('origin', 'http://caller.com');
    final resp = await req.close();
    expect(resp.statusCode, equals(HttpStatus.noContent));
    expect(resp.accessControlAllowOrigin, 'http://caller.com');

    client.close();
    await proxy.stop();
  });

  test('MCP CORS proxy sets CORS headers', () async {
    final (proxy, proxyUri) = await startProxy(mcp: true);

    final client = HttpClient();
    final req = await client.openUrl('OPTIONS', proxyUri);
    final resp = await req.close();
    expect(resp.statusCode, equals(HttpStatus.noContent));
    expect(resp.accessControlAllowOrigin, '*');
    expect(resp.accessControlAllowHeaders, contains('mcp-session-id'));
    expect(resp.accessControlAllowHeaders, contains('mcp-protocol-version'));

    client.close();
    await proxy.stop();
  });
}

extension on HttpClientResponse {
  String get accessControlAllowOrigin =>
      headers.value('access-control-allow-origin')?.toLowerCase() ?? '';

  String get accessControlAllowHeaders =>
      headers.value('access-control-allow-headers')?.toLowerCase() ?? '';
}
