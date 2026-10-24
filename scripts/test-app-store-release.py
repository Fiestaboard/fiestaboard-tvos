#!/usr/bin/env python3
"""Release policy tests: no network, Apple writes, or signing credentials."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("app-store-release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

GOOD = [{"name": "build-and-test", "conclusion": "success"},
        {"name": "Release archive", "conclusion": "success"}]


def version(number, state, build=None):
    return {"id": number, "attributes": {"versionString": number, "platform": "TV_OS",
            "appStoreState": state}, "relationships": {"build": {"data": build}}}


class ReleasePolicyTests(unittest.TestCase):
    def plan(self, versions=(), changed=True, jobs=None):
        return release.plan_release(list(versions), changed, GOOD if jobs is None else jobs)

    def test_first_release_reuses_existing_unbuilt_draft(self):
        result = self.plan([version("1.0", "PREPARE_FOR_SUBMISSION")])
        self.assertTrue(result["publish"])
        self.assertEqual(result["version"], "1.0")

    def test_approved_release_increments_patch_numerically(self):
        result = self.plan([version("1.0.9", "READY_FOR_SALE"), version("1.0.10", "READY_FOR_DISTRIBUTION")])
        self.assertEqual(result["version"], "1.0.11")

    def test_two_component_version_gets_patch_component(self):
        self.assertEqual(self.plan([version("1.0", "READY_FOR_SALE")])["version"], "1.0.1")

    def test_optional_job_failure_does_not_block(self):
        jobs = GOOD + [{"name": "Home Top Shelf screenshot (informational, not required)", "conclusion": "failure"}]
        self.assertTrue(self.plan(jobs=jobs)["publish"])

    def test_failed_required_test_blocks_release(self):
        with self.assertRaisesRegex(release.ReleaseError, "build-and-test"):
            self.plan(jobs=[{"name": "build-and-test", "conclusion": "failure"}, GOOD[1]])

    def test_missing_required_job_blocks_release(self):
        with self.assertRaisesRegex(release.ReleaseError, "Release archive"):
            self.plan(jobs=GOOD[:1])

    def test_unchanged_sources_skip_version_creation(self):
        result = self.plan([version("1.0", "READY_FOR_SALE")], changed=False)
        self.assertFalse(result["publish"])
        self.assertNotIn("version", result)

    def test_active_review_or_pending_release_skips(self):
        for state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_APP_STORE"):
            with self.subTest(state=state):
                self.assertFalse(self.plan([version("1.0", state)])["publish"])

    def test_rejected_version_requires_attention(self):
        for state in ("REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY"):
            with self.subTest(state=state), self.assertRaisesRegex(release.ReleaseError, "attention"):
                self.plan([version("1.0", state)])

    def test_uploaded_draft_is_not_overwritten(self):
        with self.assertRaisesRegex(release.ReleaseError, "already has a build"):
            self.plan([version("1.0", "PREPARE_FOR_SUBMISSION", {"type": "builds", "id": "123"})])

    def test_other_platform_versions_do_not_affect_tv_release(self):
        ios = version("9.0", "IN_REVIEW")
        ios["attributes"]["platform"] = "IOS"
        self.assertEqual(self.plan([ios, version("1.0", "READY_FOR_SALE")])["version"], "1.0.1")

    def test_unknown_apple_state_fails_closed(self):
        with self.assertRaisesRegex(release.ReleaseError, "Unsupported"):
            self.plan([version("1.0", "NEW_APPLE_STATE")])


if __name__ == "__main__":
    unittest.main()
