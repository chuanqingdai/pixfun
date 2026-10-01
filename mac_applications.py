"""Private early-access applications; no public read endpoint or email delivery."""
import re
import sqlite3
from datetime import datetime, timezone

CREATOR_TYPES = {'travel', 'outdoor', 'family', 'commercial', 'other'}
BACKGROUNDS = {'enthusiast', 'creator', 'editor', 'studio', 'brand', 'other'}
PLATFORMS = {'youtube', 'tiktok', 'instagram', 'bilibili', 'xiaohongshu', 'other'}
BUDGET_RANGES = ('free', '1-9', '10-19', '20-39', '40-69', '70+', 'unsure')


def validate_application(data):
    if not isinstance(data, dict):
        raise ValueError('Please complete the application form.')
    modern = 'background' in data
    creator = data.get('background') if modern else data.get('creatorType')
    need = data.get('need')
    email = data.get('email')
    price = data.get('monthlyUsd')
    if not isinstance(creator, str) or creator not in (BACKGROUNDS if modern else CREATOR_TYPES):
        raise ValueError('Choose your background.')
    if modern:
        budget = data.get('budgetRange')
        platforms = data.get('platforms', [])
        if not isinstance(budget, str) or budget not in BUDGET_RANGES:
            raise ValueError('Choose a monthly budget range.')
        if not isinstance(platforms, list) or len(platforms) > len(PLATFORMS) or any(not isinstance(p, str) or p not in PLATFORMS for p in platforms):
            raise ValueError('Choose valid platforms.')
        price = None
    if not isinstance(need, str) or not 10 <= len(need.strip()) <= 1200:
        raise ValueError('Describe your editing needs in 10–1,200 characters.')
    if not isinstance(email, str) or len(email) > 254 or not re.fullmatch(r'[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+', email.strip()):
        raise ValueError('Enter a valid email address.')
    if price is not None and (type(price) is not int or not 0 <= price <= 1000):
        raise ValueError('Enter a whole-dollar monthly amount from 0 to 1,000, or choose Not sure yet.')
    if (not modern and 'monthlyUsd' not in data) or data.get('contactConsent') is not True:
        raise ValueError('Complete the price question and agree to be contacted about your application.')
    return creator, need.strip(), email.strip().lower(), price


def save_application(path, data):
    creator, need, email, price = validate_application(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Permission is restricted before any personal information is written.
    path.touch(mode=0o600, exist_ok=True)
    path.chmod(0o600)
    with sqlite3.connect(str(path), timeout=10) as conn:
        conn.execute('''CREATE TABLE IF NOT EXISTS applications (
            id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE,
            creator_type TEXT NOT NULL, need TEXT NOT NULL, monthly_usd INTEGER,
            contact_consent INTEGER NOT NULL, consent_version TEXT NOT NULL,
            created_at TEXT NOT NULL)''')
        # Additive migration: retain original answers and exact historical prices.
        columns = {row[1] for row in conn.execute('PRAGMA table_info(applications)')}
        for name in ('background', 'platforms', 'budget_range'):
            if name not in columns:
                conn.execute(f'ALTER TABLE applications ADD COLUMN {name} TEXT')
        # Retries do not duplicate requests or overwrite another person's answers.
        conn.execute('''INSERT INTO applications
            (email, creator_type, need, monthly_usd, contact_consent, consent_version, created_at, background, platforms, budget_range)
            VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
            ON CONFLICT(email) DO NOTHING''',
            (email, creator, need, price, 'mac-early-access-v2' if 'background' in data else 'mac-early-access-v1',
             datetime.now(timezone.utc).isoformat(), data.get('background'),
             ','.join(sorted(set(data.get('platforms', [])))) if 'background' in data else None, data.get('budgetRange') if 'background' in data else None))


def list_applications(path):
    """Read without creating or migrating a database; supports the original schema."""
    if not path.exists():
        return []
    with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as conn:
        conn.row_factory = sqlite3.Row
        return [dict(row) for row in conn.execute('SELECT * FROM applications ORDER BY created_at DESC, id DESC')]
