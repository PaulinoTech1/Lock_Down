#!/usr/bin/env python3
"""Ensure legacy profile labels cannot be mistaken for the daily profile."""

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED = {
    "work-domain": "CURRENT",
    "trusted-workstation": "INCOMPATIBLE_WITH_TWO_DOMAIN_MODE",
    "untrusted-analysis": "LEGACY",
    "network-lab": "LAB_ONLY",
}


class ProfileStatusTests(unittest.TestCase):
    def test_single_authoritative_profile_and_banners(self):
        manifest = json.loads((ROOT / "vm-profiles/status.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema"], 1)
        self.assertEqual(manifest["profiles"], EXPECTED)
        self.assertEqual([name for name, state in manifest["profiles"].items()
                          if state == "CURRENT"], ["work-domain"])
        for name, state in EXPECTED.items():
            with self.subTest(name=name):
                text = (ROOT / "vm-profiles" / name / "profile.md").read_text(encoding="utf-8")
                self.assertIn(state, "\n".join(text.splitlines()[:8]))
                if state != "CURRENT":
                    self.assertIn("NON-PRODUCTION", "\n".join(text.splitlines()[:8]))


if __name__ == "__main__":
    unittest.main()
