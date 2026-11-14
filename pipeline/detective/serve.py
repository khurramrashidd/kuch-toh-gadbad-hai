"""python -m detective serve  -  share the app and LIVE pipeline data on your network.

  http://<laptop-ip>:8090/        the built web app (app/build/web, from `flutter build web`)
  http://<laptop-ip>:8090/data/   app/web/data, read live: every pipeline run shows up after a refresh

Open the first link on the tablet / phone browser (same Wi-Fi, or the laptop's Mobile Hotspot).
A debug phone build can read the same live data:
  flutter run --dart-define=DATA_BASE_URL=http://<laptop-ip>:8090/data/
"""
from __future__ import annotations

import socket
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .util import PIPELINE_DIR

HELP_PAGE = """<!doctype html><meta charset="utf-8"><title>Kuch Toh Gadbad Hai - data server</title>
<body style="font-family:system-ui;max-width:640px;margin:40px auto;line-height:1.5">
<h2>Data server is running</h2>
<p>The web app is not built yet. In the <code>app</code> folder run:</p>
<pre>flutter build web</pre><p>then refresh this page. Live data: <a href="/data/catalog.json">/data/catalog.json</a></p>
</body>"""

TYPES = {
    ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm", ".json": "application/json",
    ".png": "image/png", ".svg": "image/svg+xml", ".html": "text/html", ".css": "text/css", ".ico": "image/x-icon",
    ".ttf": "font/ttf", ".otf": "font/otf", ".woff2": "font/woff2", ".frag": "text/plain", ".map": "application/json",
}


def lan_ips() -> list[str]:
    ips: set[str] = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))  # no packet is sent; just picks the outgoing interface
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    return sorted(ip for ip in ips if not ip.startswith("127.") and not ip.startswith("169.254."))


class _Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, **TYPES}
    data_dir: Path = Path(".")
    web_root: Path = Path(".")
    quiet = True

    def _clean(self) -> str:
        return self.path.split("?", 1)[0].split("#", 1)[0]

    def translate_path(self, path: str) -> str:
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if clean == "/data" or clean.startswith("/data/"):
            self.directory = str(self.data_dir)
            clean = clean[len("/data"):] or "/"
        else:
            self.directory = str(self.web_root)
        return super().translate_path(clean)

    def do_GET(self):  # noqa: N802
        p = self._clean()
        if not (p == "/data" or p.startswith("/data/")) and not (self.web_root / "index.html").exists():
            body = HELP_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def end_headers(self):
        p = self._clean()
        if p.startswith("/data/") or p in ("/", "/index.html") or p.endswith(("flutter_bootstrap.js", "flutter_service_worker.js", "version.json")):
            self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def log_request(self, code="-", size="-"):
        p = self._clean()
        try:
            c = int(code)
        except (TypeError, ValueError):
            c = 0
        if not self.quiet or c >= 400 or p.endswith("/data/catalog.json"):
            what = "loaded catalog" if p.endswith("catalog.json") and c == 200 else p
            print(f"  {time.strftime('%H:%M:%S')}  {self.client_address[0]:15s} {c}  {what}", flush=True)

    def log_message(self, format, *args):  # noqa: A002
        if not self.quiet:
            super().log_message(format, *args)


class _Server(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        import sys

        exc = sys.exc_info()[1]
        if isinstance(exc, (ConnectionResetError, BrokenPipeError, ConnectionAbortedError, TimeoutError)):
            return  # browsers drop connections all the time
        super().handle_error(request, client_address)


def serve(data_dir: Path, port: int = 8090, web_root: str | None = None, quiet: bool = True) -> int:
    data_dir = Path(data_dir).resolve()
    root = Path(web_root).resolve() if web_root else (PIPELINE_DIR.parent / "app" / "build" / "web").resolve()
    handler = type("Handler", (_Handler,), {"data_dir": data_dir, "web_root": root, "quiet": quiet})
    try:
        httpd = _Server(("0.0.0.0", port), partial(handler, directory=str(root)))
    except OSError as e:
        print(f"Port {port} is busy ({e}). Try:  python -m detective serve --port {port + 1}")
        return 2
    ips = lan_ips()
    print("=" * 76)
    print(" Kuch Toh Gadbad Hai - live server   (Ctrl+C to stop)")
    print("=" * 76)
    print(f"  data : {data_dir}   (live - refresh the page after each pipeline run)")
    print(f"  app  : {root}" + ("" if (root / 'index.html').exists() else "   NOT BUILT YET -> in app\\: flutter build web"))
    print(f"\n  this laptop : http://localhost:{port}/")
    for ip in ips:
        print(f"  tablet/phone: http://{ip}:{port}/          (same Wi-Fi or laptop hotspot)")
    if ips:
        print(f"\n  phone debug build with live data:\n    flutter run --dart-define=DATA_BASE_URL=http://{ips[0]}:{port}/data/")
    print("\n  Windows asks to allow Python on the network the first time: tick Private, click Allow.")
    print("  Venue Wi-Fi often blocks device-to-device traffic: then turn on the laptop's Mobile Hotspot")
    print("  and join it from the tablet (laptop address is usually 192.168.137.1).")
    print("=" * 76, flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nserver stopped")
    finally:
        httpd.server_close()
    return 0
