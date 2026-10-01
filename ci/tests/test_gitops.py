"""Offline regression tests: python3 -m unittest discover -s ci/tests -v."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
API = "https://api.bitbucket.org/2.0/repositories/workspace/gitops/pullrequests"
COMMIT = "a" * 40
BRANCH = "deploy/dev/service/aaaaaaaaaaaa"


def pr(state="OPEN", commit=COMMIT):
    return {"id": 7, "state": state,
            "source": {"branch": {"name": BRANCH}, "commit": {"hash": commit}},
            "destination": {"branch": {"name": "main"}}}


def call(method, path, code, body):
    return {"method": method, "url": API + path, "code": code, "body": body}


READ = call("GET", "/7", 200, pr())
APPROVE = call("POST", "/7/approve", 200, {"approved": True})
CHECKS = call("GET", "/7/mergeability/checks", 200, {"values": []})
MERGE = call("POST", "/7/merge", 200, pr("MERGED"))
MERGED = call("GET", "/7", 200, pr("MERGED"))
EXISTING = call("GET", "", 200, {"values": [pr()]})


class PullRequestTests(unittest.TestCase):
    def run_flow(self, calls, success=True, timeout=20):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            sequence = work / "calls.json"
            sequence.write_text(json.dumps(calls))
            curl = work / "curl"
            curl.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
headers = [args[i + 1] for i, arg in enumerate(args) if arg == "--header"]
if "--data" in args:
    assert "Content-Type: application/json" in headers, args
    json.loads(args[args.index("--data") + 1])
else:
    # Approval is a bodyless POST. Declaring JSON without a JSON body can cause
    # the server to reject it before the approval handler runs.
    assert not any(header.lower().startswith("content-type:") for header in headers), args
sequence = Path(os.environ["MOCK_CALLS"])
calls = json.loads(sequence.read_text())
assert calls, "Unexpected HTTP request"
expected = calls.pop(0)
assert args[args.index("--request")+1] == expected["method"], args
assert args[-1] == expected["url"], args
if expected["method"] == "GET" and expected["url"].endswith("/pullrequests"):
    query = args[args.index("--data-urlencode")+1]
    assert 'source.repository.full_name = "workspace/gitops"' in query, query
if expected["method"] == "POST" and expected["url"].endswith("/pullrequests"):
    payload = json.loads(args[args.index("--data")+1])
    assert payload["title"] == 'deploy: "release"'
    assert payload["destination"]["branch"]["name"] == "main"
if expected["url"].endswith(("/approve", "/merge")):
    assert args[args.index("--user")+1] == "approver@example.test:api-token"
sequence.write_text(json.dumps(calls))
Path(args[args.index("--output")+1]).write_text(json.dumps(expected["body"]))
print(expected["code"], end="")
''')
            curl.chmod(0o755)
            # Avoid real waits except in the timeout test.
            if timeout > 1:
                sleeper = work / "sleep"
                sleeper.write_text("#!/bin/sh\nexit 0\n")
                sleeper.chmod(0o755)
            env = {**os.environ, "PATH": str(work) + os.pathsep + os.environ["PATH"],
                   "MOCK_CALLS": str(sequence), "GITOPS_ACCESS_TOKEN": "repo-token",
                   "GITOPS_APPROVER_EMAIL": "approver@example.test",
                   "GITOPS_APPROVER_TOKEN": "api-token",
                   "GITOPS_MERGE_TIMEOUT_SECONDS": str(timeout),
                   "GITOPS_POLL_INTERVAL_SECONDS": "1"}
            result = subprocess.run([
                "bash", str(ROOT / "ci/gitops/complete-pull-request.sh"),
                "workspace", "gitops", BRANCH, "main", COMMIT, 'deploy: "release"'],
                env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode == 0, success, output)
            self.assertEqual(json.loads(sequence.read_text()), [], output)
            return output

    def test_create_approve_merge(self):
        self.run_flow([call("GET", "", 200, {"values": []}),
                       call("POST", "", 201, pr()), READ, APPROVE, READ,
                       CHECKS, MERGE, MERGED])

    def test_resume_existing_pr_without_creating_duplicate(self):
        self.run_flow([EXISTING, READ, APPROVE, READ, CHECKS, MERGE, MERGED])

    def test_reconcile_concurrent_creation(self):
        self.run_flow([call("GET", "", 200, {"values": []}),
                       call("POST", "", 400, {"error": "already exists"}),
                       EXISTING, READ, APPROVE, READ, CHECKS, MERGE, MERGED])

    def test_wait_for_checks_then_async_merge(self):
        self.run_flow([EXISTING, READ, APPROVE, READ,
                       call("GET", "/7/mergeability/checks", 200,
                            {"values": [{"blocking": True, "status": "PENDING"}]}),
                       READ, CHECKS, call("POST", "/7/merge", 202, {"task_id": "task-1"}),
                       READ, call("GET", "/7/merge/task-status/task-1", 200,
                                  {"task_status": "PENDING"}),
                       READ, call("GET", "/7/merge/task-status/task-1", 200,
                                  {"task_status": "SUCCESS", "merge_result": pr("MERGED")}),
                       MERGED])

    def test_async_task_failure_is_not_success(self):
        self.run_flow([EXISTING, READ, APPROVE, READ, CHECKS,
                       call("POST", "/7/merge", 202, {"task_id": "task-1"}), READ,
                       call("GET", "/7/merge/task-status/task-1", 200,
                            {"error": {"message": "Merge failed"}})], success=False)

    def test_merge_permission_failure_is_terminal(self):
        self.run_flow([EXISTING, READ, APPROVE, READ, CHECKS,
                       call("POST", "/7/merge", 403, {"error": "Forbidden"})], success=False)

    def test_approval_failure_never_merges(self):
        self.run_flow([EXISTING, READ,
                       call("POST", "/7/approve", 401, {"error": "Unauthorized"})], success=False)

    def test_changed_branch_never_approved(self):
        self.run_flow([EXISTING, call("GET", "/7", 200, pr(commit="b" * 40))], success=False)

    def test_abbreviated_commit_is_resolved_before_approval_and_merge(self):
        short_read = call("GET", "/7", 200, pr(commit=COMMIT[:12]))
        resolved = {"method": "GET", "url": API.removesuffix("/pullrequests") + "/commit/" + COMMIT[:12],
                    "code": 200, "body": {"hash": COMMIT}}
        short_merged = call("GET", "/7", 200, pr("MERGED", commit=COMMIT[:12]))
        self.run_flow([EXISTING, short_read, resolved, APPROVE, short_read, resolved,
                       CHECKS, MERGE, short_merged, resolved])

    def test_matching_prefix_does_not_allow_a_different_full_commit(self):
        resolved = {"method": "GET", "url": API.removesuffix("/pullrequests") + "/commit/" + COMMIT[:12],
                    "code": 200, "body": {"hash": COMMIT[:12] + "b" * 28}}
        output = self.run_flow([EXISTING, call("GET", "/7", 200, pr(commit=COMMIT[:12])),
                               resolved], success=False)
        self.assertIn("PR source commit mismatch", output)

    def test_unresolved_abbreviated_commit_never_approved(self):
        unresolved = {"method": "GET", "url": API.removesuffix("/pullrequests") + "/commit/" + COMMIT[:12],
                      "code": 404, "body": {"error": "Commit not found"}}
        self.run_flow([EXISTING, call("GET", "/7", 200, pr(commit=COMMIT[:12])),
                       unresolved], success=False)

    def test_missing_commit_never_approved(self):
        self.run_flow([EXISTING, call("GET", "/7", 200, pr(commit=None))], success=False)

    def test_changed_destination_never_approved(self):
        changed = pr()
        changed["destination"]["branch"]["name"] = "unexpected"
        self.run_flow([EXISTING, call("GET", "/7", 200, changed)], success=False)

    def test_already_merged_does_not_post(self):
        self.run_flow([EXISTING, MERGED])

    def test_conflict_is_rechecked(self):
        self.run_flow([EXISTING, READ, APPROVE, READ, CHECKS,
                       call("POST", "/7/merge", 409, {"error": "Pending check"}),
                       READ, CHECKS, MERGE, MERGED])

    def test_timeout_does_not_report_success(self):
        output = self.run_flow([EXISTING, READ, APPROVE, READ,
                               call("GET", "/7/mergeability/checks", 200,
                                    {"values": [{"blocking": True}]})], success=False, timeout=1)
        self.assertIn("Timed out", output)


class ScanTests(unittest.TestCase):
    def run_scan(self, configured_exit_code=None, scanner_failure=False):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            docker = work / "docker"
            docker.write_text("#!/bin/sh\nexit 0\n")
            docker.chmod(0o755)
            scanner = work / "trivy"
            scanner.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
Path("calls").open("a").write("scan\\n")
exit_code = args[args.index("--exit-code")+1]
assert exit_code == os.environ["EXPECTED_SCAN_EXIT_CODE"], args
assert args[args.index("--severity")+1] == "HIGH,CRITICAL", args
assert args[args.index("--format")+1] == "json", args
assert "--ignore-unfixed" in args, args
if os.environ["MOCK_SCAN_FAILURE"] == "1":
    print("Mock scanner execution failed", file=sys.stderr)
    sys.exit(2)
Path(args[args.index("--output")+1]).write_text(json.dumps({"Results": ["CRITICAL"]}))
sys.exit(int(exit_code))
''')
            scanner.chmod(0o755)
            env = {**os.environ, "PATH": str(work) + os.pathsep + os.environ["PATH"],
                   "EXPECTED_SCAN_EXIT_CODE": configured_exit_code or "0",
                   "MOCK_SCAN_FAILURE": "1" if scanner_failure else "0"}
            # Exercise the script's default independently of the CI job's setting.
            env.pop("IMAGE_SCAN_EXIT_CODE", None)
            if configured_exit_code is not None:
                env["IMAGE_SCAN_EXIT_CODE"] = configured_exit_code
            result = subprocess.run(["bash", str(ROOT / "ci/common/image-scan.sh")],
                                    cwd=work, capture_output=True, text=True,
                                    env=env, timeout=30)
            output = result.stdout + result.stderr
            expected = 2 if scanner_failure else int(configured_exit_code or "0")
            self.assertEqual(result.returncode, expected, output)
            self.assertTrue((work / "calls").is_file(), output)
            self.assertEqual((work / "calls").read_text(), "scan\n", output)
            if scanner_failure:
                self.assertIn("Mock scanner execution failed", result.stderr)
            else:
                self.assertTrue((work / "reports/trivy-image-scan.json").is_file(), output)

    def test_scan_once_and_preserve_failure_report(self):
        self.run_scan(configured_exit_code="1")

    def test_scan_defaults_to_report_only(self):
        self.run_scan()

    def test_scanner_errors_fail_even_in_report_only_mode(self):
        self.run_scan(scanner_failure=True)


class DeploymentBranchTests(unittest.TestCase):
    def test_retry_preserves_commit_and_merged_values_are_noop(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            remote = work / "remote.git"
            seed = work / "seed"
            bin_dir = work / "bin"
            bin_dir.mkdir()
            real_git = shutil.which("git")
            env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1",
                   "GIT_CONFIG_GLOBAL": os.devnull,
                   "GIT_AUTHOR_NAME": "Test", "GIT_COMMITTER_NAME": "Test",
                   "GIT_AUTHOR_EMAIL": "test@example.test", "GIT_COMMITTER_EMAIL": "test@example.test"}

            def git(*args):
                return subprocess.check_output([real_git, *map(str, args)], env=env,
                                               stderr=subprocess.DEVNULL, text=True).strip()

            git("init", "--bare", remote)
            git("init", seed)
            git("-C", seed, "checkout", "-b", "main")
            values = seed / "environments/dev/service/values.yaml"
            values.parent.mkdir(parents=True)
            values.write_text("release: {}\nimage: {}\n")
            git("-C", seed, "add", ".")
            git("-C", seed, "commit", "-m", "initial")
            git("-C", seed, "push", remote, "main")
            # Redirect only the clone URL; all branch/tree/push logic uses real Git.
            wrapper = bin_dir / "git"
            wrapper.write_text(f"#!{sys.executable}\n" + '''
import os, sys
args = [os.environ["TEST_REMOTE"] if arg.startswith("https://x-token-auth:") else arg
        for arg in sys.argv[1:]]
os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"], *args])
''')
            wrapper.chmod(0o755)
            yq = bin_dir / "yq"
            yq.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
Path(sys.argv[-1]).write_text(json.dumps({key: os.environ[key] for key in
    ["RELEASE_TAG", "SOURCE_COMMIT", "IMAGE_REPOSITORY", "IMAGE_DIGEST"]}) + "\\n")
''')
            yq.chmod(0o755)
            curl = bin_dir / "curl"
            curl.write_text(f"#!{sys.executable}\n" + '''
import json, os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
branch = "deploy/dev/service/aaaaaaaaaaaa"
commit = subprocess.check_output([os.environ["REAL_GIT"], "--git-dir", os.environ["TEST_REMOTE"],
                                  "rev-parse", branch], text=True).strip()
pr = {"id": 7, "state": "OPEN", "source": {"branch": {"name": branch}, "commit": {"hash": commit}},
      "destination": {"branch": {"name": "main"}}}
if args[-1].endswith("/pullrequests"):
    body, code = {"values": [pr]}, 200
elif args[-1].endswith("/7"):
    body, code = pr, 200
else:
    assert args[-1].endswith("/approve"), args
    body, code = {"error": "Temporary approval failure"}, 403
Path(args[args.index("--output")+1]).write_text(json.dumps(body))
print(code, end="")
''')
            curl.chmod(0o755)
            metadata = work / "metadata.env"
            metadata.write_text(f"RELEASE_TAG=dev\nSOURCE_COMMIT={COMMIT}\n"
                                "IMAGE_REPOSITORY=registry/service\nIMAGE_DIGEST=sha256:1234\n")
            env.update({"PATH": str(bin_dir) + os.pathsep + env["PATH"],
                        "REAL_GIT": real_git, "TEST_REMOTE": str(remote),
                        "GITOPS_ACCESS_TOKEN": "test", "GITOPS_APPROVER_EMAIL": "test@example.test",
                        "GITOPS_APPROVER_TOKEN": "test"})

            def deploy():
                return subprocess.run(["bash", str(ROOT / "ci/gitops/update-environment.sh"),
                                       "dev", "service", str(metadata)],
                                      env=env, capture_output=True, text=True, timeout=30)

            first = deploy()
            self.assertNotEqual(first.returncode, 0)
            self.assertIn("Cannot approve PR", first.stderr)
            first_commit = git("--git-dir", remote, "rev-parse", BRANCH)
            second = deploy()
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("Reusing unchanged deployment branch", second.stdout)
            self.assertEqual(git("--git-dir", remote, "rev-parse", BRANCH), first_commit)
            self.assertNotIn("[skip ci]", git("--git-dir", remote, "log", "-1", "--format=%s", BRANCH))
            git("--git-dir", remote, "update-ref", "refs/heads/main", first_commit)
            third = deploy()
            self.assertEqual(third.returncode, 0, third.stdout + third.stderr)
            self.assertIn("already references this release", third.stdout)


if __name__ == "__main__":
    unittest.main()
