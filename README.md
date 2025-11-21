A tiny CORS proxy written in Dart.

The library provides a `CorsProxy` that listens for requests and forwards them to the remote URL provided when instantiating a proxy instance.
The proxy will add permissive CORS headers so that browsers can access the proxied resources.

Usage
-----

Run from the project root:

```bash
dart run bin/cors.dart https://api.target.com/ 8080
```

Then request:

```
http://localhost:8080/path/to/resource
```

Notes
-----

- The proxy supports preflight OPTIONS requests and adds some CORS response headers such as `Access-Control-Allow-Origin`.
- Be warned! It is designed for demonstration and development use; it does not implement advanced security checks or access restrictions.

