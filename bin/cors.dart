import 'dart:io';

import 'package:cors_enabler/cors_enabler.dart';

void main(List<String> arguments) async {
  // Simple runner for the CORS proxy.
  // Usage: dart run bin/cors.dart <target-url> [port]
  if (arguments.isEmpty) {
    print('Usage: dart run bin/cors.dart <target-url> [port]');
    exit(2);
  }

  final targetArg = arguments[0];
  final targetUri = Uri.tryParse(targetArg);
  if (targetUri == null ||
      !(targetUri.scheme == 'http' || targetUri.scheme == 'https')) {
    print('Error: target must be a valid http or https URL.');
    exit(2);
  }

  final port = arguments.length > 1 ? int.tryParse(arguments[1]) ?? 8080 : 8080;
  final proxy = CorsProxy.mcp(target: targetUri, host: '0.0.0.0', port: port);

  await proxy.start();
  final boundPort = proxy.boundPort!;
  print('CORS proxy listening on http://localhost:$boundPort');

  // Keep running until the user terminates (Ctrl-C)
  ProcessSignal.sigint.watch().listen((_) async {
    print('Shutting down...');
    await proxy.stop();
    exit(0);
  });
}
