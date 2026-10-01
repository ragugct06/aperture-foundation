"""Tag resolution and promotion tests using local Git and mocked external actions."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DIGEST = 'sha256:' + 'b' * 64


class TagPromotionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name) / 'work'
        self.remote = Path(self.temp.name) / 'remote.git'
        self.env = {**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
                    'GIT_AUTHOR_NAME': 'Test', 'GIT_COMMITTER_NAME': 'Test',
                    'GIT_AUTHOR_EMAIL': 'test@example.test', 'GIT_COMMITTER_EMAIL': 'test@example.test',
                    'RELEASE_TAG': '1.0.0-beta.1', 'AWS_ACCOUNT_ID': '123456789012',
                    'AWS_REGION': 'us-east-1', 'ECR_REPOSITORY': 'service',
                    'MOCK_DIGEST': DIGEST, 'MOCK_FAILURE': '', 'SERVICE_NAME': 'aperture-foundation'}
        self.run_cmd('git', 'init', '--bare', str(self.remote))
        self.run_cmd('git', 'init', '-b', 'main', str(self.work))
        shutil.copytree(ROOT / 'ci/release', self.work / 'ci/release')
        shutil.copytree(ROOT / 'ci/ecr', self.work / 'ci/ecr')
        (self.work / 'database').mkdir()
        (self.work / 'database/changelog.yaml').write_text('databaseChangeLog: []\n')
        self.git('add', '.')
        self.git('commit', '-m', 'release')
        self.release = self.git('rev-parse', 'HEAD')
        self.env['EXPECTED_COMMIT'] = self.release
        for tag in ['1.0.0-beta.1', '1.0.0', 'v1.0.0-beta.1']:
            self.git('tag', tag)
        self.git('tag', '-a', '1.0.0-rc.1', '-m', 'annotated RC')
        (self.work / 'newer').write_text('pipeline checkout differs from tagged release')
        self.git('add', '.')
        self.git('commit', '-m', 'newer main')
        self.env['BITBUCKET_COMMIT'] = self.git('rev-parse', 'HEAD')
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', 'origin', 'main', '--tags')
        for directory in ['ci/database', 'ci/gitops', 'bin']:
            (self.work / directory).mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / 'ci/database/migrate-tag.sh', self.work / 'ci/database/migrate-tag.sh')
        (self.work / 'ci/database/migrate.sh').write_text('''#!/usr/bin/env bash
set -eu
[[ "$1" == update && "$2" == "$EXPECTED_COMMIT" ]]
printf 'migrate %s\n' "$2" >> calls
[[ "$MOCK_FAILURE" != migration ]]
''')
        (self.work / 'ci/gitops/update-environment.sh').write_text('''#!/usr/bin/env bash
set -eu
source "$3"
[[ "$SOURCE_COMMIT" == "$EXPECTED_COMMIT" ]]
[[ "$RELEASE_TAG" != dev ]]
[[ "$IMAGE_DIGEST" == "$MOCK_DIGEST" ]]
printf 'gitops %s %s\n' "$1" "$SOURCE_COMMIT" >> calls
[[ "$MOCK_FAILURE" != gitops ]]
''')
        aws = self.work / 'bin/aws'
        aws.write_text(f'#!{sys.executable}\n' + '''
import os, sys
from pathlib import Path
assert sys.argv[1:3] == ['ecr', 'describe-images']
assert sys.argv[sys.argv.index('--image-ids') + 1] == 'imageTag=' + os.environ['EXPECTED_COMMIT']
with Path('calls').open('a') as f:
    f.write('image ' + os.environ['EXPECTED_COMMIT'] + '\\n')
if os.environ['MOCK_FAILURE'] == 'image':
    sys.exit(1)
print(os.environ['MOCK_DIGEST'])
''')
        aws.chmod(0o755)
        self.env['PATH'] = str(self.work / 'bin') + os.pathsep + os.environ['PATH']

    def run_cmd(self, *args, cwd=None):
        return subprocess.check_output(args, cwd=cwd, env=self.env, stderr=subprocess.PIPE,
                                       text=True).strip()

    def git(self, *args):
        return self.run_cmd('git', *args, cwd=self.work)

    def promote(self, target='qe', database_only=False):
        script = 'ci/database/migrate-tag.sh' if database_only else 'ci/release/promote.sh'
        result = subprocess.run(['bash', script, target], cwd=self.work, env=self.env,
                                capture_output=True, text=True, timeout=15)
        log = self.work / 'calls'
        return result, log.read_text().splitlines() if log.exists() else []

    def test_tagged_commit_drives_image_migration_and_gitops_in_order(self):
        result, calls = self.promote()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [f'image {self.release}', f'migrate {self.release}',
                                 f'gitops qa {self.release}'])
        metadata = (self.work / 'reports/promoted-image.env').read_text()
        self.assertIn('RELEASE_TAG=1.0.0-beta.1\n', metadata)
        self.assertIn(f'IMAGE_DIGEST={DIGEST}\n', metadata)
        self.assertIn('TARGET_ENV=qa\n', metadata)

    def test_annotated_tag_is_fetched_and_peeled_to_commit(self):
        self.env['RELEASE_TAG'] = '1.0.0-rc.1'
        self.git('tag', '-d', '1.0.0-rc.1')
        result, calls = self.promote('uat')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls[-1], f'gitops uat {self.release}')

    def test_production_tag(self):
        self.env['RELEASE_TAG'] = '1.0.0'
        result, calls = self.promote('prod')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls[-1], f'gitops prod {self.release}')

    def test_wrong_environment_or_malformed_tag_stops_before_external_actions(self):
        for tag in ['1.0.0', '1.0.0-rc.1', '01.0.0-beta.1', 'main', '1.0.0-beta.1;false']:
            with self.subTest(tag=tag):
                self.env['RELEASE_TAG'] = tag
                result, calls = self.promote()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_missing_remote_tag_fails_even_if_it_exists_locally(self):
        self.env['RELEASE_TAG'] = '1.0.0-beta.2'
        self.git('tag', self.env['RELEASE_TAG'])
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_tag_outside_main_is_rejected(self):
        self.git('checkout', '-b', 'feature')
        (self.work / 'feature').write_text('not on main')
        self.git('add', 'feature')
        self.git('commit', '-m', 'feature only')
        self.env['RELEASE_TAG'] = '1.0.0-beta.2'
        self.git('tag', self.env['RELEASE_TAG'])
        self.git('push', 'origin', self.env['RELEASE_TAG'])
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('contained in origin/main', result.stderr)
        self.assertEqual(calls, [])

    def test_moved_tag_is_not_force_updated(self):
        self.git('tag', '-f', '1.0.0-beta.1', 'HEAD')
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_tag_without_changelog_stops_before_image_lookup(self):
        self.git('rm', 'database/changelog.yaml')
        self.git('commit', '-m', 'no changelog')
        self.env['RELEASE_TAG'] = '1.0.0-beta.2'
        self.git('tag', self.env['RELEASE_TAG'])
        self.git('push', 'origin', 'main', self.env['RELEASE_TAG'])
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no Liquibase changelog', result.stderr)
        self.assertEqual(calls, [])

    def test_missing_image_stops_before_migration(self):
        self.env['MOCK_FAILURE'] = 'image'
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [f'image {self.release}'])

    def test_invalid_digest_stops_before_migration(self):
        self.env['MOCK_DIGEST'] = 'None'
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [f'image {self.release}'])

    def test_migration_failure_prevents_gitops(self):
        self.env['MOCK_FAILURE'] = 'migration'
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [f'image {self.release}', f'migrate {self.release}'])

    def test_database_only_uses_tag_without_image_or_gitops(self):
        result, calls = self.promote(database_only=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [f'migrate {self.release}'])

    def test_gitops_failure_is_not_reported_as_success(self):
        self.env['MOCK_FAILURE'] = 'gitops'
        result, calls = self.promote()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls[-1], f'gitops qa {self.release}')
        self.assertNotIn('Promotion completed', result.stdout)

    def test_qa_alias_and_legacy_v_prefix(self):
        self.env['RELEASE_TAG'] = 'v1.0.0-beta.1'
        result, calls = self.promote('qa')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls[-1], f'gitops qa {self.release}')

    def create_tag(self, target='qe', tag='1.0.0-beta.2', source=None):
        self.env.update({'RELEASE_TAG': tag, 'SOURCE_REF': source or self.release,
                         'APP_REPO_ACCESS_TOKEN': 'test-tag-token-never-log',
                         'BITBUCKET_GIT_HTTP_ORIGIN': str(self.remote)})
        result = subprocess.run(['bash', 'ci/release/create-tag.sh', target],
                                cwd=self.work, env=self.env, capture_output=True,
                                text=True, timeout=15)
        self.assertNotIn(self.env['APP_REPO_ACCESS_TOKEN'], result.stdout + result.stderr)
        calls = self.work / 'calls'
        if calls.exists():
            self.assertTrue(all(line.startswith('image ') for line in calls.read_text().splitlines()))
        return result

    def remote_tag_commit(self, tag):
        return self.run_cmd('git', '--git-dir', str(self.remote), 'rev-parse',
                            f'refs/tags/{tag}^{{commit}}')

    def test_create_beta_on_explicit_commit_as_annotated_tag(self):
        result = self.create_tag()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.remote_tag_commit('1.0.0-beta.2'), self.release)
        self.assertEqual(self.run_cmd('git', '--git-dir', str(self.remote), 'cat-file',
                                      '-t', 'refs/tags/1.0.0-beta.2'), 'tag')
        metadata = (self.work / 'reports/created-tag.env').read_text()
        self.assertIn('RELEASE_TAG=1.0.0-beta.2\n', metadata)
        self.assertIn(f'IMAGE_DIGEST={DIGEST}\n', metadata)

    def test_create_rc_and_final_from_candidate_tags(self):
        result = self.create_tag('uat', '1.0.0-rc.2', '1.0.0-beta.1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Remove the fixture's final tag to exercise creation instead of reuse.
        self.git('push', 'origin', ':refs/tags/1.0.0')
        self.git('tag', '-d', '1.0.0')
        result = self.create_tag('prod', '1.0.0', '1.0.0-rc.2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.remote_tag_commit('1.0.0'), self.release)

    def test_create_retry_keeps_existing_tag_object(self):
        result = self.create_tag()
        self.assertEqual(result.returncode, 0, result.stderr)
        before = self.git('rev-parse', 'refs/tags/1.0.0-beta.2')
        result = self.create_tag()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git('rev-parse', 'refs/tags/1.0.0-beta.2'), before)

    def test_create_conflicting_tag_does_not_move_remote(self):
        self.env['EXPECTED_COMMIT'] = self.env['BITBUCKET_COMMIT']
        result = self.create_tag(tag='1.0.0-beta.1', source=self.env['BITBUCKET_COMMIT'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('will not be moved', result.stderr)
        self.assertEqual(self.remote_tag_commit('1.0.0-beta.1'), self.release)

    def test_create_enforces_source_type_and_version(self):
        for target, tag, source in [('qe', '1.0.0-beta.2', 'main'),
                                    ('uat', '1.0.0-rc.2', self.release),
                                    ('prod', '1.0.0', '1.0.0-beta.1'),
                                    ('uat', '2.0.0-rc.1', '1.0.0-beta.1')]:
            with self.subTest(target=target, source=source):
                result = self.create_tag(target, tag, source)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.work / 'calls').exists())

    def test_create_missing_image_does_not_create_tag(self):
        self.env['MOCK_FAILURE'] = 'image'
        result = self.create_tag()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git('ls-remote', '--tags', 'origin', 'refs/tags/1.0.0-beta.2'), '')
        self.assertFalse((self.work / 'reports/created-tag.env').exists())

    def test_create_failed_push_does_not_report_success(self):
        hook = self.remote / 'hooks/pre-receive'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        result = self.create_tag()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / 'reports/created-tag.env').exists())
        self.assertEqual(self.git('ls-remote', '--tags', 'origin', 'refs/tags/1.0.0-beta.2'), '')
