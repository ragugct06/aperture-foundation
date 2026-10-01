"""Offline orchestration tests; real PostgreSQL checks run in the database CI step."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                    "GIT_AUTHOR_NAME": "Test", "GIT_COMMITTER_NAME": "Test",
                    "GIT_AUTHOR_EMAIL": "test@example.test", "GIT_COMMITTER_EMAIL": "test@example.test",
                    "DB_SECRET_ID": "test/database", "AWS_REGION": "us-east-1",
                    "MOCK_SECRET": json.dumps({"host": "db.example.test", "dbname": "test",
                                               "username": "migrator", "password": "test-secret"}),
                    "MOCK_AWS_FAILURE": "", "DB_SSLMODE": "require",
                    "MOCK_EXPECTED_URL": "jdbc:postgresql://db.example.test:5432/test?sslmode=require",
                    "MOCK_DOCKER_LOG": str(self.work / "calls.jsonl"), "MOCK_FAILURE": ""}
        for key in list(self.env):
            if key.startswith("DB_SECRET_") and key.endswith("_KEY"):
                del self.env[key]
        # These fixtures use dbname; the loader also supports deployment key mappings.
        self.env["DB_SECRET_DATABASE_KEY"] = "dbname"
        subprocess.run(["git", "init", str(self.work)], check=True, capture_output=True, env=self.env)
        (self.work / "marker").write_text("old release")
        self.git("add", ".")
        self.git("commit", "-m", "pre-Liquibase release")
        self.old_revision = self.git("rev-parse", "HEAD")
        shutil.copytree(ROOT / "database", self.work / "database")
        self.git("add", "database")
        self.git("commit", "-m", "release with migrations")
        self.revision = self.git("rev-parse", "HEAD")
        # The current worktree can contain newer schema files. They must not ship
        # when deploying an older image/release's migration revision.
        (self.work / "database/changes/not-in-release.sql").write_text("UNRELEASED")
        (self.work / "bin").mkdir()
        aws = self.work / "bin/aws"
        aws.write_text(f"#!{sys.executable}\n" + '''
import os, sys
assert sys.argv[1:] == ["secretsmanager", "get-secret-value", "--secret-id",
    os.environ["DB_SECRET_ID"], "--region", os.environ["AWS_REGION"],
    "--query", "SecretString", "--output", "text"]
if os.environ["MOCK_AWS_FAILURE"]:
    print(os.environ["MOCK_AWS_FAILURE"] + " test-secret", file=sys.stderr)
    sys.exit(1)
print(os.environ["MOCK_SECRET"])
''')
        aws.chmod(0o755)
        docker = self.work / "bin/docker"
        docker.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
assert args[0] == "run" and "--rm" in args
assert "liquibase/liquibase:4.33.0" in args
assert "test-secret" not in args
assert "LIQUIBASE_COMMAND_PASSWORD" in args
secret = json.loads(os.environ["MOCK_SECRET"])
assert os.environ["LIQUIBASE_COMMAND_URL"] == os.environ["MOCK_EXPECTED_URL"]
assert os.environ["LIQUIBASE_COMMAND_USERNAME"] == secret[os.environ.get("DB_SECRET_USERNAME_KEY", "username")]
assert os.environ["LIQUIBASE_COMMAND_PASSWORD"] == secret[os.environ.get("DB_SECRET_PASSWORD_KEY", "password")]
volume = args[args.index("--volume") + 1].split(":")[0]
assert Path(volume, "changelog.yaml").is_file()
assert not Path(volume, "changes/not-in-release.sql").exists()
with Path(os.environ["MOCK_DOCKER_LOG"]).open("a") as log:
    log.write(json.dumps({"action": args[-1], "volume": volume}) + "\\n")
if args[-1] == os.environ["MOCK_FAILURE"]:
    sys.exit(2)
''')
        docker.chmod(0o755)
        self.env["PATH"] = str(self.work / "bin") + os.pathsep + self.env["PATH"]

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.work), *args],
                                       env=self.env, stderr=subprocess.DEVNULL, text=True).strip()

    def run_migration(self, action="update", revision=None):
        result = subprocess.run(["bash", str(ROOT / "ci/database/migrate.sh"),
                                 action, revision or self.revision], cwd=self.work,
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertNotIn("test-secret", result.stdout + result.stderr)
        self.assertEqual(list(self.work.glob(".liquibase-work.*")), [])
        log = self.work / "calls.jsonl"
        actions = [json.loads(line)["action"] for line in log.read_text().splitlines()] if log.exists() else []
        return result, actions

    def test_update_uses_release_snapshot_and_validates_first(self):
        result, actions = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(actions, ["validate", "update"])

    def test_failed_validation_prevents_update(self):
        self.env["MOCK_FAILURE"] = "validate"
        result, actions = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, ["validate"])

    def test_failed_update_propagates_to_caller(self):
        self.env["MOCK_FAILURE"] = "update"
        result, actions = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, ["validate", "update"])

    def test_sql_preview_does_not_apply_update(self):
        result, actions = self.run_migration(action="update-sql")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, ["validate", "update-sql"])

    def test_release_without_changelogs_fails_closed(self):
        result, actions = self.run_migration(revision=self.old_revision)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("has no Liquibase changelog", result.stdout)
        self.assertEqual(actions, [])

    def test_missing_secret_id_prevents_database_access(self):
        del self.env["DB_SECRET_ID"]
        result, actions = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, [])

    def test_secret_fetch_failure_prevents_database_access(self):
        self.env["MOCK_AWS_FAILURE"] = "1"
        result, actions = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, [])

    def test_secret_failure_reports_safe_diagnostics(self):
        for error, hint in [
            ("AccessDeniedException", "AWS AccessDenied"),
            ("ResourceNotFoundException", "AWS ResourceNotFound"),
            ("ExpiredTokenException", "AWS authentication failed"),
            ("DecryptionFailure", "AWS DecryptionFailure"),
            ("InvalidRequestException", "AWS InvalidRequest"),
            ("Could not connect to the endpoint URL", "AWS connection failed"),
        ]:
            with self.subTest(error=error):
                self.env["MOCK_AWS_FAILURE"] = error
                result, actions = self.run_migration()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(hint, result.stderr)
                self.assertEqual(actions, [])

    def test_invalid_secret_prevents_database_access(self):
        for secret in ["not json test-secret", "null", "{}",
                       json.dumps({"host": "db", "dbname": "test", "username": "u",
                                   "password": "test-secret", "port": 70000}),
                       json.dumps({"host": "db/injected", "dbname": "test", "username": "u",
                                   "password": "test-secret"})]:
            with self.subTest(secret=secret):
                self.env["MOCK_SECRET"] = secret
                result, actions = self.run_migration()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(actions, [])

    def test_custom_keys_port_and_special_characters(self):
        self.env.update({"DB_SECRET_HOST_KEY": "hostname", "DB_SECRET_DATABASE_KEY": "database",
                         "DB_SECRET_USERNAME_KEY": "user", "DB_SECRET_PASSWORD_KEY": "pass",
                         "DB_SECRET_PORT_KEY": "dbport", "DB_SSLMODE": "verify-full",
                         "MOCK_SECRET": json.dumps({"hostname": "db.example.test", "database": "test/name",
                             "user": "migration user", "pass": "test-secret '$`\\\"" + chr(10), "dbport": "5433"}),
                         "MOCK_EXPECTED_URL": "jdbc:postgresql://db.example.test:5433/test%2Fname?sslmode=verify-full"})
        result, actions = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(actions, ["validate", "update"])

    def test_runtime_secret_overrides_stale_connection_environment(self):
        self.env.update({"LIQUIBASE_COMMAND_URL": "stale", "LIQUIBASE_COMMAND_USERNAME": "stale",
                         "LIQUIBASE_COMMAND_PASSWORD": "stale"})
        result, actions = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(actions, ["validate", "update"])

    def test_cannot_automatically_mark_existing_schema_as_executed(self):
        result, actions = self.run_migration(action="changelog-sync")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, [])
