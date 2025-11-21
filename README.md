A tiny CORS proxy written in Dart. The library provides a `CorsProxy` that
listens for requests and forwards them to a remote URL provided as a
`url` query parameter. The proxy will add permissive CORS headers so that
browsers can access the proxied resources.

Usage
-----

Run from the project root:

```bash
dart run bin/cors.dart 8080
```

Then request:

```
http://localhost:8080/proxy?url=https://example.com
```

Notes
-----

- The proxy supports preflight OPTIONS requests and adds the following CORS
	response header: `Access-Control-Allow-Origin: *`.
- The proxy is designed for demonstration and development use; it does not
	implement advanced security checks or access restrictions.
