import http.client
import json
import sqlite3
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app
from mac_applications import validate_application, save_application, list_applications, BUDGET_RANGES


class ApplicationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.data_patch = patch.object(app, 'DATA', self.directory)
        self.data_patch.start()
        app.APPLICATION_ATTEMPTS.clear()
        self.server = app.ThreadingHTTPServer(('127.0.0.1', 0), app.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.payload = dict(creatorType='travel', need='Find spoken moments in my travel footage.', email='qa@example.com', monthlyUsd=20, contactConsent=True)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.data_patch.stop()
        self.tmp.cleanup()

    def request(self, payload=None, route='/api/mac-applications', method='POST', origin=None, extra_headers=None):
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        headers = {'Content-Type': 'application/json'}
        if origin:
            headers['Origin'] = origin
        headers.update(extra_headers or {})
        conn.request(method, route, body=json.dumps(self.payload if payload is None else payload) if method=='POST' else None, headers=headers)
        res = conn.getresponse()
        result = res.status, res.read()
        conn.close()
        return result

    def test_save_retry_and_private_storage(self):
        self.assertEqual(self.request()[0], 201)
        self.assertEqual(self.request({**self.payload, 'need':'Do not replace another application.'})[0], 201)
        db = self.directory/'mac-applications.sqlite3'
        self.assertEqual(db.stat().st_mode & 0o777, 0o600)
        with sqlite3.connect(db) as conn:
            rows=conn.execute('select email, need, monthly_usd from applications').fetchall()
        self.assertEqual(rows, [('qa@example.com', self.payload['need'], 20)])
        for route in ['/api/mac-applications', '/data/mac-applications.sqlite3', '/assets/../data/mac-applications.sqlite3']:
            self.assertEqual(self.request(route=route, method='GET')[0], 404)

    def test_validation_and_price_choices(self):
        for value in [0, 20, None]:
            self.assertEqual(validate_application({**self.payload, 'monthlyUsd':value})[3], value)
        for change in [{'monthlyUsd':True}, {'monthlyUsd':-1}, {'monthlyUsd':1.5}, {'email':'bad'}, {'need':'short'}, {'contactConsent':False}, {'creatorType':[]}]:
            self.assertEqual(self.request({**self.payload, **change})[0], 400)
        self.assertEqual(self.request([])[0], 400)
        self.assertFalse((self.directory/'mac-applications.sqlite3').exists())

    def test_origin_rate_limit_and_page(self):
        self.assertEqual(self.request(origin='https://external.invalid')[0], 403)
        self.assertEqual(self.request({**self.payload,'website':'spam'})[0], 400)
        for _ in range(5):
            self.assertEqual(self.request()[0],201)
        self.assertEqual(self.request()[0],429)
        status, body=self.request(route='/mac-early-access',method='GET')
        self.assertEqual(status,200)
        self.assertEqual(body.count(b'<fieldset>'), 4)
        self.assertEqual(self.request({'need':'x'*9000})[0],413)

    def test_background_budget_and_legacy_migration(self):
        db = self.directory/'mac-applications.sqlite3'
        # Exact v1 schema, not the new writer, verifies a real upgrade path.
        with sqlite3.connect(db) as conn:
            conn.execute('CREATE TABLE applications (id INTEGER PRIMARY KEY,email TEXT NOT NULL UNIQUE,creator_type TEXT NOT NULL,need TEXT NOT NULL,monthly_usd INTEGER,contact_consent INTEGER NOT NULL,consent_version TEXT NOT NULL,created_at TEXT NOT NULL)')
            conn.execute("INSERT INTO applications VALUES (1,'old@example.com','travel','Keep the old need',25,1,'mac-early-access-v1','2026-09-01T00:00:00+00:00')")
        self.assertEqual(list_applications(db)[0]['monthly_usd'], 25)
        modern = dict(background='creator', platforms=['youtube','tiktok'], need='A story from my hiking trip.', email='new@example.com', budgetRange='20-39', contactConsent=True)
        self.assertEqual(self.request(modern)[0],201)
        saved=list_applications(db)
        self.assertEqual(len(saved),2)
        new=next(r for r in saved if r['email']=='new@example.com')
        old=next(r for r in saved if r['email']=='old@example.com')
        self.assertEqual((new['background'],new['budget_range'],new['monthly_usd']),('creator','20-39',None))
        self.assertEqual(set(new['platforms'].split(',')),{'youtube','tiktok'})
        self.assertEqual((old['background'],old['monthly_usd']),(None,25))
        for value in BUDGET_RANGES:
            validate_application({**modern,'budgetRange':value})
        for change in [{'budgetRange':'100'}, {'budgetRange':[]}, {'background':'fake'}, {'platforms':'youtube'}, {'platforms':['fake']}]:
            self.assertEqual(self.request({**modern,**change})[0],400)

    def test_local_admin_and_restricted_access(self):
        route='/api/admin/mac-applications'
        status,body=self.request(route=route,method='GET')
        self.assertEqual(status,200)
        self.assertEqual(json.loads(body)['applications'],[])
        self.assertFalse((self.directory/'mac-applications.sqlite3').exists())
        self.assertEqual(self.request()[0],201)
        status,body=self.request(route=route,method='GET')
        self.assertEqual(json.loads(body)['applications'][0]['email'],'qa@example.com')
        for headers in [{'Host':'public.example.com'}, {'Sec-Fetch-Site':'cross-site'}, {'Sec-Fetch-Site':'same-site'}, {'X-Forwarded-For':'127.0.0.1'}, {'Forwarded':'for=127.0.0.1'}, {'Origin':'https://outside.invalid'}]:
            for target in [route,'/admin/mac-applications']:
                self.assertEqual(self.request(route=target,method='GET',extra_headers=headers)[0],403)
        self.assertEqual(self.request(route='/admin/mac-applications',method='GET')[0],200)
        fake=object.__new__(app.Handler)
        fake.client_address=('192.168.1.2',42)
        fake.headers={'Host':f'127.0.0.1:{self.server.server_address[1]}'}
        fake.server=self.server
        self.assertFalse(fake.allow_local_application_admin())


if __name__=='__main__':
    unittest.main()
