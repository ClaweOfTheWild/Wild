"""Validate the privileged workflow boundary and GitHub's newer queue syntax."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class ReleaseWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.release = yaml.safe_load(
            (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        )
        cls.checks = yaml.safe_load(
            (ROOT / ".github/workflows/release-checks.yml").read_text(encoding="utf-8")
        )

    def test_only_closed_pull_requests_to_main_can_trigger_publication(self):
        self.assertEqual(
            self.release["on"],
            {"pull_request_target": {"types": ["closed"], "branches": ["main"]}},
        )
        guard = " ".join(self.release["jobs"]["release"]["if"].split())
        self.assertEqual(
            guard,
            "github.repository == 'ClaweOfTheWild/Wild' && "
            "github.event.pull_request.merged == true && "
            "github.event.pull_request.base.ref == 'main' && "
            "github.event.pull_request.base.repo.full_name == 'ClaweOfTheWild/Wild'",
        )

    def test_queue_preserves_multiple_pending_merges_without_cancellation(self):
        self.assertEqual(
            self.release["concurrency"],
            {
                "group": "wild-github-release",
                "queue": "max",
                "cancel-in-progress": False,
            },
        )

    def test_publisher_runs_only_trusted_base_code_with_step_scoped_token(self):
        self.assertEqual(self.release["permissions"], {})
        job = self.release["jobs"]["release"]
        self.assertEqual(job["permissions"], {"contents": "write"})
        self.assertNotIn("env", job)
        checkout, publish = job["steps"]
        self.assertRegex(checkout["uses"], r"^actions/checkout@[0-9a-f]{40}$")
        self.assertEqual(checkout["with"]["ref"], "${{ github.sha }}")
        self.assertIs(checkout["with"]["persist-credentials"], False)
        self.assertEqual(publish["uses"], "./.github/actions/publish-release")
        self.assertEqual(publish["env"], {"GH_TOKEN": "${{ github.token }}"})
        self.assertNotIn("run", publish)

    def test_checks_are_unprivileged_and_cannot_call_the_publisher(self):
        self.assertEqual(self.checks["permissions"], {})
        self.assertEqual(
            self.checks["on"],
            {"pull_request": {"branches": ["main"]}, "push": {"branches": ["main"]}},
        )
        for job in self.checks["jobs"].values():
            self.assertEqual(job["permissions"], {"contents": "read"})
            for step in job["steps"]:
                self.assertNotIn("publish-release", step.get("uses", ""))
                self.assertNotIn("GH_TOKEN", step.get("env", {}))


if __name__ == "__main__":
    unittest.main()
