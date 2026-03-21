#!/usr/bin/env python3
"""Dev server with COOP/COEP headers for multi-threaded WASM (SharedArrayBuffer)."""
import http.server
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

class CORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        super().end_headers()

print(f"Serving at http://localhost:{PORT} (with COOP/COEP for multi-threaded WASM)")
http.server.HTTPServer(("", PORT), CORSHandler).serve_forever()
