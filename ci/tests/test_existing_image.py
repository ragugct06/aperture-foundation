"""Verify GitOps retries select the existing image, never publish a new one."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMMIT = "a" * 40
DIGEST = "sha256:" + "b" * 64


class ExistingImageTests(unittest.TestCase):
    def run_lookup(self, digest=DIGEST, aws_failure=False):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            aws = work / "aws"
            aws.write_text(f"#!{sys.executable}\n" + '''
import os, sys
from pathlib import Path
args = sys.argv[1:]
assert args[:2] == ["ecr", "describe-images"], args
assert args[args.index("--image-ids") + 1] == "imageTag=" + "a" * 40, args
assert args[args.index("--repository-name") + 1] == "service", args
Path("aws-calls").open("a").write("describe-images\\n")
if os.environ["MOCK_AWS_FAILURE"] == "1":
    sys.exit(254)
print(os.environ["MOCK_DIGEST"])
''')
            aws.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "ci/ecr/read-existing-image.sh")],
                                    cwd=work, capture_output=True, text=True, timeout=10,
                                    env={**os.environ, "PATH": str(work) + os.pathsep + os.environ["PATH"],
                                         "IMAGE_COMMIT": COMMIT, "BITBUCKET_COMMIT": "c" * 40,
                                         "AWS_ACCOUNT_ID": "123456789012", "AWS_REGION": "us-east-1",
                                         "ECR_REPOSITORY": "service", "MOCK_DIGEST": digest,
                                         "MOCK_AWS_FAILURE": "1" if aws_failure else "0"})
            output = result.stdout + result.stderr
            self.assertEqual((work / "aws-calls").read_text(), "describe-images\n", output)
            metadata = work / "reports/image-metadata.env"
            if aws_failure or digest != DIGEST:
                self.assertNotEqual(result.returncode, 0, output)
                self.assertFalse(metadata.exists())
            else:
                self.assertEqual(result.returncode, 0, output)
                self.assertIn(f"SOURCE_COMMIT={COMMIT}\n", metadata.read_text())
                self.assertIn(f"IMAGE_DIGEST={DIGEST}\n", metadata.read_text())
                self.assertIn("IMAGE_REPOSITORY=123456789012.dkr.ecr.us-east-1.amazonaws.com/service\n",
                              metadata.read_text())

    def test_uses_original_image_commit_not_pipeline_commit(self):
        self.run_lookup()

    def test_missing_digest_does_not_write_deployment_metadata(self):
        self.run_lookup(digest="None")

    def test_aws_failure_stops_deployment(self):
        self.run_lookup(aws_failure=True)
