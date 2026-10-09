import http.client
import json
import threading
import unittest
from server import DEFAULTS, Server


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = Server(('127.0.0.1', 0))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        with self.server.lock:
            self.server.settings = dict(DEFAULTS)

    def request(self, method='GET', path='/api/settings', value=None, headers=None, raw=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        body = raw if raw is not None else json.dumps(value) if value is not None else None
        connection.request(method, path, body, headers or {'Content-Type': 'application/json'})
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_defaults_and_update(self):
        code, headers, body = self.request()
        self.assertEqual(code, 200)
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertEqual(json.loads(body), DEFAULTS)
        changed = dict(DEFAULTS, size=8, color='#aabbcc')
        self.assertEqual(self.request('PUT', value=changed)[0], 200)
        self.assertEqual(json.loads(self.request()[2]), changed)

    def test_invalid_settings_do_not_change_state(self):
        for key, invalids in {'size': [0, 65, True, '4', None], 'speed': [0, 1001],
                              'pressure': [-1, 1.1], 'pool': [-1, 1.6], 'color': ['red', '#123', 12],
                              'response': [0, 101], 'power': [0, 5]}.items():
            for invalid in invalids:
                with self.subTest(key=key, value=invalid):
                    self.assertEqual(self.request('PUT', value=dict(DEFAULTS, **{key: invalid}))[0], 400)
                    self.assertEqual(json.loads(self.request()[2]), DEFAULTS)
        for value in [{}, [], dict(DEFAULTS, extra=1), dict(DEFAULTS, size=float('nan')),
                      dict(DEFAULTS, size=float('inf'))]:
            self.assertEqual(self.request('PUT', value=value)[0], 400)

    def test_origin(self):
        for origin in ['http://evil.example', 'null', 'http://127.0.0.1:1']:
            self.assertEqual(self.request('PUT', value=DEFAULTS, headers={
                'Content-Type': 'application/json', 'Origin': origin})[0], 403)
        self.assertEqual(self.request('PUT', value=DEFAULTS, headers={
            'Content-Type': 'application/json', 'Origin': f'http://127.0.0.1:{self.port}'})[0], 200)

    def test_bad_bodies(self):
        self.assertEqual(self.request('PUT', raw='{bad')[0], 400)
        self.assertEqual(self.request('PUT', raw='x' * 4097)[0], 413)
        self.assertEqual(self.request('PUT', value=DEFAULTS, headers={'Content-Type': 'text/plain'})[0], 415)

    def test_static_allowlist(self):
        for path in ['/', '/brush.js', '/remote.js']:
            self.assertEqual(self.request(path=path)[0], 200)
        for path in ['/server.py', '/../README.md', '/%2e%2e/README.md']:
            self.assertEqual(self.request(path=path)[0], 404)


if __name__ == '__main__':
    unittest.main()
