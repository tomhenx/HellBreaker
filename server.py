#!/usr/bin/env python3
"""
HellBreaker local dev server.
Serves the dist/ folder with the COOP/COEP headers Godot 4 WebAssembly requires.
"""
import http.server
import os
import threading
import webbrowser

PORTS    = [7777, 8888, 9000, 3000, 5000, 8080]
DIST_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist")
ENTRY    = "HellBreaker.html"

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js":   "application/javascript; charset=utf-8",
    ".mjs":  "application/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck":  "application/octet-stream",
    ".png":  "image/png",
    ".svg":  "image/svg+xml",
    ".ico":  "image/x-icon",
}


class GodotHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIST_DIR, **kwargs)

    # Required headers for SharedArrayBuffer (Godot 4 threading)
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy",   "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def guess_type(self, path):
        _, ext = os.path.splitext(path)
        return MIME.get(ext.lower(), super().guess_type(path))

    def log_message(self, fmt, *args):
        status = args[1] if len(args) > 1 else "???"
        color  = "\033[92m" if str(status).startswith("2") else "\033[93m"
        reset  = "\033[0m"
        print(f"  {color}{args[0]}{reset}  {status}")


def _open_browser(port):
    import time
    time.sleep(0.6)
    url = f"http://localhost:{port}/{ENTRY}"
    print(f"  Opening {url}\n")
    webbrowser.open(url)


if __name__ == "__main__":
    if not os.path.isdir(DIST_DIR):
        print(f"[ERROR] dist/ folder not found at: {DIST_DIR}")
        input("Press Enter to exit...")
        raise SystemExit(1)

    if not os.path.isfile(os.path.join(DIST_DIR, ENTRY)):
        print(f"[ERROR] {ENTRY} not found in dist/. Re-export the project first.")
        input("Press Enter to exit...")
        raise SystemExit(1)

    port = None
    for candidate in PORTS:
        import socket
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("0.0.0.0", candidate))
                port = candidate
                break
            except OSError:
                continue

    if port is None:
        print(f"[ERROR] Could not bind to any of {PORTS}. Close whatever is using those ports.")
        input("Press Enter to exit...")
        raise SystemExit(1)

    url = f"http://localhost:{port}/{ENTRY}"
    print()
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║        HellBreaker  —  Dev Server            ║")
    print("  ╠══════════════════════════════════════════════╣")
    print(f"  ║  URL  →  {url:<36}║")
    print("  ║  Stop →  Ctrl+C                              ║")
    print("  ╚══════════════════════════════════════════════╝")
    print()

    threading.Thread(target=_open_browser, args=(port,), daemon=True).start()

    with http.server.HTTPServer(("0.0.0.0", port), GodotHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n  Server stopped.")
