"""Exercise the real HTTP download route against an isolated release directory."""
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app


class MacDownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "package.json").write_text(json.dumps({"version": "0.1.4"}))
        (self.root / "dist-desktop").mkdir()
        self.installer = self.root / "dist-desktop/Pixfun-0.1.4-arm64.dmg"
        self.payload = bytes(range(256)) * 4096
        self.installer.write_bytes(self.payload)
        self.root_patch = patch.object(app, "ROOT", self.root)
        self.root_patch.start()
        self.server = app.ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.root_patch.stop()
        self.temp.cleanup()

    def request(self, method="GET", path="/downloads/pixfun-mac.dmg", headers=None):
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        conn.request(method, path, headers=headers or {})
        response = conn.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        conn.close()
        return result

    def test_full_download_and_head(self):
        status, headers, body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(body, self.payload)
        self.assertEqual(headers["Content-Type"], "application/x-apple-diskimage")
        self.assertEqual(headers["Content-Disposition"], 'attachment; filename="Pixfun-0.1.4-arm64.dmg"')
        self.assertEqual(headers["Cache-Control"], "no-store")
        status, headers, body = self.request("HEAD")
        self.assertEqual(status, 200)
        self.assertEqual(int(headers["Content-Length"]), len(self.payload))
        self.assertEqual(body, b"")

    def test_partial_download_resume(self):
        for byte_range, start, end in [("bytes=15-100", 15, 101), ("bytes=-512", len(self.payload)-512, len(self.payload))]:
            status, headers, body = self.request(headers={"Range": byte_range})
            self.assertEqual(status, 206)
            self.assertEqual(body, self.payload[start:end])
            self.assertEqual(headers["Content-Range"], f"bytes {start}-{end-1}/{len(self.payload)}")
            self.assertIn("attachment", headers["Content-Disposition"])
        self.assertEqual(self.request(headers={"Range": "bytes=99999999-"})[0], 416)

    def test_missing_release_does_not_serve_old_version(self):
        self.installer.rename(self.installer.with_name("Pixfun-0.1.3-arm64.dmg"))
        self.assertEqual(self.request()[0], 404)
        self.assertEqual(self.request("HEAD")[2], b"")

    def test_only_explicit_release_is_public(self):
        for path in ["/downloads/", "/downloads/Pixfun-0.1.4-arm64.dmg", "/downloads/../package.json", "/downloads/%2e%2e/package.json"]:
            self.assertEqual(self.request(path=path)[0], 404)
        (self.root / "package.json").write_text('{"version":"../../private"}')
        self.assertEqual(self.request()[0], 404)

    def test_link_stays_inside_release_directory(self):
        outside = self.root / "private.dmg"
        self.installer.rename(outside)
        self.installer.symlink_to(outside)
        self.assertEqual(self.request()[0], 404)


if __name__ == "__main__":
    unittest.main()
