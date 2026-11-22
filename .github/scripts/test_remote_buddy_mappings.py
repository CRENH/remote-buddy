import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remote_buddy_mappings as rbm  # noqa: E402

SCRIPT = Path(__file__).resolve().parent / 'remote_buddy_mappings.py'


def profile(profile_id, model, name, home='showDesktop', **extra):
    value = {
        'id': profile_id, 'model': model, 'customName': name,
        'bluetoothIdentifier': f'BT-{profile_id}', 'hidFingerprint': f'HID-{profile_id}', 'gainDB': 10.0,
        'mappings': {'buttonBindings': {'home': home}, 'buttonShortcuts': {}, 'secondaryButtonBindings': {}},
    }
    value.update(extra)
    return value


def domain(profiles, apps=(), **other):
    values = {rbm.PROFILES_KEY: json.dumps(profiles).encode(), rbm.APPS_KEY: json.dumps(list(apps)).encode()}
    values.update(other)
    return values


class MappingBackupTests(unittest.TestCase):
    def test_backup_keeps_only_mappings_and_apps(self):
        backup = rbm.make_backup(domain([profile('A', 'rc003', '客厅')], [{'id': 'X', 'bundleIdentifier': 'b'}]), 'now')
        self.assertEqual(backup['format'], rbm.FORMAT)
        self.assertEqual(backup['remotes'], [{'id': 'A', 'model': 'rc003', 'name': '客厅',
                                              'mappings': profile('A', 'rc003', '客厅')['mappings']}])
        self.assertNotIn('bluetoothIdentifier', json.dumps(backup))
        self.assertEqual(len(backup['customApplications']), 1)

    def test_restore_replaces_mappings_and_keeps_pairing_and_gain(self):
        backup = rbm.make_backup(domain([profile('A', 'rc003', '客厅', home='showDesktop')]), 'now')
        local = profile('A', 'rc003', '客厅', home='escape', gainDB=3.0)
        profiles, _, _, changed = rbm.plan_restore(domain([local]), backup)
        self.assertEqual(profiles[0]['mappings']['buttonBindings']['home'], 'showDesktop')
        self.assertEqual(profiles[0]['bluetoothIdentifier'], 'BT-A')
        self.assertEqual(profiles[0]['gainDB'], 3.0)
        self.assertEqual(changed, 1)

    def test_match_prefers_id_then_name_then_first_of_model(self):
        remotes = [{'id': 'A', 'model': 'rc003', 'name': 'A', 'mappings': {}},
                   {'id': 'B', 'model': 'rc003', 'name': 'B', 'mappings': {}}]
        self.assertEqual(rbm.match_remote(profile('B', 'rc003', 'A'), remotes)[0]['id'], 'B')
        self.assertEqual(rbm.match_remote(profile('N', 'rc003', 'B'), remotes)[0]['id'], 'B')
        self.assertEqual(rbm.match_remote(profile('N', 'rc003', 'C'), remotes)[0]['id'], 'A')
        self.assertIsNone(rbm.match_remote(profile('N', 't1_remote', 'A'), remotes)[0])

    def test_remote_model_missing_locally_is_reported_and_others_untouched(self):
        backup = rbm.make_backup(domain([profile('T', 't1_remote', 'T1')]), 'now')
        local = profile('A', 'rc003', '客厅', home='escape')
        profiles, _, lines, changed = rbm.plan_restore(domain([local]), backup)
        self.assertEqual(profiles[0]['mappings'], local['mappings'])
        self.assertEqual(changed, 0)
        self.assertTrue(any('本机没有对应的遥控器' in line for line in lines))

    def test_application_references_point_at_local_ids(self):
        source = profile('A', 'rc003', '客厅')
        source['mappings']['buttonApplicationProfileIDs'] = {'home': 'Y'}
        source['mappings']['secondaryButtonBindings'] = {'ok': {'longPress': {'action': 'customApplication',
                                                                              'applicationProfileID': 'Y'}}}
        backup = rbm.make_backup(domain([source], [{'id': 'Y', 'bundleIdentifier': 'com.example.app'}]), 'now')
        local_apps = [{'id': 'X', 'bundleIdentifier': 'com.example.app'}]
        profiles, apps, _, _ = rbm.plan_restore(domain([profile('A', 'rc003', '客厅')], local_apps), backup)
        mappings = profiles[0]['mappings']
        self.assertEqual(mappings['buttonApplicationProfileIDs'], {'home': 'X'})
        self.assertEqual(mappings['secondaryButtonBindings']['ok']['longPress']['applicationProfileID'], 'X')
        self.assertEqual([a['id'] for a in apps], ['X'])

    def test_missing_application_is_added_and_unknown_reference_reported(self):
        source = profile('A', 'rc003', '客厅')
        source['mappings']['buttonApplicationProfileIDs'] = {'home': 'Y', 'ok': 'GONE'}
        backup = rbm.make_backup(domain([source], [{'id': 'Y', 'displayName': '示例', 'bundleIdentifier': 'b'}]), 'now')
        _, apps, lines, _ = rbm.plan_restore(domain([profile('A', 'rc003', '客厅')]), backup)
        self.assertEqual([a['id'] for a in apps], ['Y'])
        self.assertTrue(any('新增自定义 App：示例' in line for line in lines))
        self.assertTrue(any('找不到' in line and 'ok' in line for line in lines))

    def test_wrong_file_is_rejected(self):
        with self.assertRaises(ValueError):
            rbm.plan_restore(domain([profile('A', 'rc003', '客厅')]), {'format': 'other', 'remotes': []})


@unittest.skipUnless(sys.platform == 'darwin', 'needs macOS defaults')
class DefaultsRoundTripTests(unittest.TestCase):
    def setUp(self):
        self.domain = f'com.example.remote-buddy-mappings-test.{uuid.uuid4().hex}'
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name)
        seed = self.path / 'seed.plist'
        seed.write_bytes(plistlib.dumps(domain([profile('A', 'rc003', '客厅', home='showDesktop')], showDockIcon=True)))
        subprocess.run(['defaults', 'import', self.domain, str(seed)], check=True)

    def tearDown(self):
        subprocess.run(['defaults', 'delete', self.domain], capture_output=True)
        # defaults delete leaves an empty plist behind.
        (Path.home() / 'Library/Preferences' / f'{self.domain}.plist').unlink(missing_ok=True)
        self.folder.cleanup()

    def run_script(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), '--domain', self.domain, *args],
                              capture_output=True, text=True)

    def stored_profiles(self):
        return rbm.decode_list(rbm.read_domain(self.domain), rbm.PROFILES_KEY)

    def test_backup_change_and_restore(self):
        if rbm.app_is_running():
            self.skipTest('Remote Buddy is running')
        backup = self.path / 'mappings.json'
        self.assertEqual(self.run_script('backup', '--output', str(backup)).returncode, 0)
        changed = self.stored_profiles()
        changed[0]['mappings']['buttonBindings']['home'] = 'escape'
        rbm.write_list(self.domain, rbm.PROFILES_KEY, changed)

        dry_run = self.run_script('restore', str(backup), '--safety-dir', str(self.path))
        self.assertEqual(dry_run.returncode, 0, dry_run.stderr)
        self.assertIn('试运行', dry_run.stdout)
        self.assertEqual(self.stored_profiles()[0]['mappings']['buttonBindings']['home'], 'escape')

        applied = self.run_script('restore', str(backup), '--apply', '--safety-dir', str(self.path))
        self.assertEqual(applied.returncode, 0, applied.stderr)
        restored = self.stored_profiles()[0]
        self.assertEqual(restored['mappings']['buttonBindings']['home'], 'showDesktop')
        self.assertEqual(restored['bluetoothIdentifier'], 'BT-A')
        self.assertTrue(rbm.read_domain(self.domain)['showDockIcon'])
        self.assertEqual(len(list(self.path.glob('before-restore-*.plist'))), 1)


if __name__ == '__main__':
    unittest.main()
