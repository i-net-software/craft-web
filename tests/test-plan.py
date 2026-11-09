"""Exercise publication limits without GitHub or Maven writes."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlanTest(unittest.TestCase):
    def plan(self, mode, override=False):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for command, source in {
                'gh': '''#!/usr/bin/env python3
import json, os, sys, datetime
mode = os.environ['CASE']
args = ' '.join(sys.argv)
if mode == 'github_error': sys.exit(1)
if '/tags?' in args:
    if mode == 'tag': print('gridcraft-web-0.12.0\\nwordcraft-web-0.12.0')
elif '/i-net-software/craft-web/releases?' in args:
    if mode in ('recent', 'reserved'):
        for app in ('gridcraft', 'wordcraft'):
            print(json.dumps({'tag': app + '-web-0.12.0', 'at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}))
else:
    app = 'gridcraft' if '/gridcraft/' in args else 'wordcraft'
    for version in ('0.11.1', '0.12.0', '0.10.0'):
        print(json.dumps({'tag': 'v'+version, 'assets': [app+'-web-'+version+'.zip']}))
''',
                'curl': '''#!/usr/bin/env python3
import os, sys, datetime
mode = os.environ['CASE']
updated = '20200101000000'
if mode == 'central_recent': updated = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
version = '0.12.0' if mode == 'central_duplicate' else '0.10.0'
open(sys.argv[sys.argv.index('--output')+1], 'w').write('<metadata><versioning><versions><version>'+version+'</version></versions><lastUpdated>'+updated+'</lastUpdated></versioning></metadata>')
print('503' if mode == 'central_error' else '404' if mode == 'first' else '200', end='')
''',
            }.items():
                file = path / command
                file.write_text(source)
                file.chmod(0o755)
            return subprocess.run(['bash', 'scripts/plan.sh'], cwd=ROOT, env={
                **os.environ, 'PATH': directory + os.pathsep + os.environ['PATH'],
                'GITHUB_REPOSITORY': 'i-net-software/craft-web', 'CASE': mode,
                'OVERRIDE_COOLDOWN': 'true' if override else 'false',
            }, capture_output=True, text=True)

    def test_only_latest_per_app(self):
        for mode in ('new', 'first'):
            result = self.plan(mode)
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = json.loads(result.stdout)['include']
            self.assertEqual(len(entries), 2)
            self.assertEqual([v['version'] for v in entries], ['0.12.0', '0.12.0'])

    def test_cooldown_and_duplicate_guards(self):
        for mode in ('recent', 'reserved', 'tag', 'central_duplicate', 'central_recent'):
            with self.subTest(mode=mode):
                result = self.plan(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {'include': []})

    def test_override_allows_publication_during_cooldown(self):
        result = self.plan('central_recent', override=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)['include']), 2)

    def test_override_keeps_duplicate_and_reservation_guards(self):
        for mode in ('reserved', 'tag', 'central_duplicate'):
            with self.subTest(mode=mode):
                result = self.plan(mode, override=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {'include': []})

    def test_remote_errors_stop_publication(self):
        for mode in ('github_error', 'central_error'):
            self.assertNotEqual(self.plan(mode).returncode, 0)


if __name__ == '__main__':
    unittest.main()
