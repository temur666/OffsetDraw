#!/usr/bin/env python3
"""Dependency-free LAN parameter server for the native Rollerball experiment."""
import argparse
import json
import math
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
DEFAULTS = dict(size=8, pressure=0.45, speed=240, power=2.6, response=25, pool=0.65, color='#203656')
RANGES = dict(size=(1, 64), pressure=(0.1, 1), speed=(60, 1000), power=(1, 4), response=(5, 100), pool=(0, 1.5))
STATIC = {'/': ('index.html', 'text/html; charset=utf-8'),
          '/brush.js': ('brush.js', 'text/javascript; charset=utf-8'),
          '/remote.js': ('remote.js', 'text/javascript; charset=utf-8')}


def validate(value):
    if not isinstance(value, dict) or set(value) != set(DEFAULTS):
        raise ValueError('Expected the complete parameter object')
    for key, (low, high) in RANGES.items():
        number = value[key]
        if type(number) not in (int, float) or not math.isfinite(number) or not low <= number <= high:
            raise ValueError(f'Invalid {key}; expected {low}..{high}')
    if not isinstance(value['color'], str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value['color']):
        raise ValueError('Invalid color; expected #RRGGBB')
    return dict(value)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address):
        self.settings = dict(DEFAULTS)
        self.lock = threading.Lock()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def respond(self, status, body, content_type='application/json; charset=utf-8'):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False, allow_nan=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' blob:; frame-ancestors 'none'")
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/api/settings':
            with self.server.lock:
                value = dict(self.server.settings)
            self.respond(200, value)
        elif path in STATIC:
            filename, content_type = STATIC[path]
            self.respond(200, (ROOT / filename).read_bytes(), content_type)
        else:
            self.respond(404, {'error': 'Not found'})

    def do_PUT(self):
        if urlsplit(self.path).path != '/api/settings':
            return self.respond(404, {'error': 'Not found'})
        origin = self.headers.get('Origin')
        if origin is not None and origin != 'http://' + self.headers.get('Host', ''):
            return self.respond(403, {'error': 'Cross-origin writes are not allowed'})
        if self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
            return self.respond(415, {'error': 'Expected application/json'})
        if self.headers.get('Transfer-Encoding'):
            return self.respond(400, {'error': 'Transfer-Encoding is not supported'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            return self.respond(400, {'error': 'Invalid Content-Length'})
        if not 0 < length <= 4096:
            return self.respond(413, {'error': 'Body must be 1..4096 bytes'})
        try:
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValueError('Incomplete body')
            value = validate(json.loads(raw))
        except (ValueError, UnicodeDecodeError, OverflowError):
            return self.respond(400, {'error': 'Invalid parameters'})
        with self.server.lock:
            self.server.settings = value
        self.respond(200, value)

    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=18765)
    args = parser.parse_args()
    server = Server((args.host, args.port))
    print(f'走珠笔调参：http://192.168.0.101:{args.port}（请替换为电脑实际 Wi-Fi IP）', flush=True)
    print(f'本机预览：http://127.0.0.1:{args.port} · Ctrl+C 停止', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
