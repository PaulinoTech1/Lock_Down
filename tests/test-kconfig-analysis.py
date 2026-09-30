#!/usr/bin/env python3
"""Behavioral classification fixtures; no Linux build or hardware access."""

import importlib.util
import pathlib
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import json


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts" / "analyze-kconfig-delta.py"


def analyzer():
    spec = importlib.util.spec_from_file_location("lockdown_kconfig_analysis", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class KconfigAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.tool = analyzer()

    def test_accepted_and_unchanged_requests(self):
        baseline = {"CONFIG_PARENT": "y", "CONFIG_CHILD": "n"}
        proposal = {"CONFIG_CHILD": "y", "CONFIG_PARENT": "y"}
        resolved = {"CONFIG_PARENT": "y", "CONFIG_CHILD": "y"}
        report = self.tool.classify_changes(baseline, proposal, resolved, {})
        statuses = {row["symbol"]: row["status"] for row in report["requested_changes"]}
        self.assertEqual(statuses, {"CONFIG_CHILD": "ACCEPTED", "CONFIG_PARENT": "UNCHANGED_REQUEST"})
        self.assertEqual([row["symbol"] for row in report["direct_resolved_changes"]], ["CONFIG_CHILD"])

    def test_dependency_rejection_is_visible(self):
        report = self.tool.classify_changes(
            {"CONFIG_DEP": "n", "CONFIG_EXAMPLE": "n"},
            {"CONFIG_EXAMPLE": "y"},
            {"CONFIG_DEP": "n", "CONFIG_EXAMPLE": "n"},
            {},
        )
        row = report["rejected_requests"][0]
        self.assertEqual((row["requested_value"], row["resolved_value"], row["status"]),
                         ("y", "n", "REJECTED_BY_KCONFIG"))

    def test_collateral_and_unexpected_resolved_delta(self):
        report = self.tool.classify_changes(
            {"CONFIG_PARENT": "y", "CONFIG_CHILD": "y", "CONFIG_SURPRISE": "n"},
            {"CONFIG_PARENT": "n"},
            {"CONFIG_PARENT": "n", "CONFIG_CHILD": "n", "CONFIG_SURPRISE": "y"},
            {},
        )
        self.assertEqual([r["symbol"] for r in report["collateral_changes"]],
                         ["CONFIG_CHILD", "CONFIG_SURPRISE"])

    def test_required_symbol_regression_fails(self):
        report = self.tool.classify_changes(
            {"CONFIG_PARENT": "y", "CONFIG_REQUIRED": "y"},
            {"CONFIG_PARENT": "n"},
            {"CONFIG_PARENT": "n", "CONFIG_REQUIRED": "n"},
            {"CONFIG_REQUIRED": "y"},
        )
        self.assertEqual(report["required_symbol_results"][0]["status"], "FAIL")
        self.assertTrue(report["failed"])

    def test_wrong_source_version_refused(self):
        with self.assertRaises(self.tool.AnalysisError):
            self.tool.require_version("6.18.52", "6.18.53")

    def test_baseline_preserved_when_proposal_is_applied(self):
        with tempfile.TemporaryDirectory() as temp:
            baseline = pathlib.Path(temp) / "baseline.config"
            candidate = pathlib.Path(temp) / "proposal.config"
            baseline.write_text("CONFIG_PARENT=y\n# CONFIG_CHILD is not set\n")
            original = baseline.read_bytes()
            self.tool.apply_proposal(baseline, candidate, {"CONFIG_CHILD": "y"})
            self.assertEqual(baseline.read_bytes(), original)
            self.assertIn("CONFIG_CHILD=y", candidate.read_text())

    def test_proposal_rejects_duplicates_and_shell_text(self):
        with tempfile.TemporaryDirectory() as temp:
            proposal = pathlib.Path(temp) / "proposal.txt"
            proposal.write_text("CONFIG_X=y\n# CONFIG_X is not set\n")
            with self.assertRaises(self.tool.AnalysisError):
                self.tool.parse_proposal(proposal)
            proposal.write_text("CONFIG_X=$(touch /tmp/nope)\n")
            with self.assertRaises(self.tool.AnalysisError):
                self.tool.parse_proposal(proposal)

    def test_report_keeps_baseline_and_surfaces_collateral_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            home = pathlib.Path(temp)
            baseline = home / "baseline.config"
            baseline.write_text('CONFIG_LOCALVERSION="-fixture"\n# CONFIG_LOCALVERSION_AUTO is not set\n'
                                'CONFIG_PARENT=y\nCONFIG_CHILD=y\nCONFIG_REQUIRED=y\n')
            original = baseline.read_bytes()
            proposal = home / "proposal.txt"
            proposal.write_text("CONFIG_PARENT=n\n")
            for name in ("linux-6.18.53.tar.xz", "archive.sign", "trusted.gpg"):
                (home / name).touch()
            args = SimpleNamespace(version="6.18.53", archive=str(home / "linux-6.18.53.tar.xz"),
                                   sha256="a" * 64, signature=str(home / "archive.sign"),
                                   keyring=str(home / "trusted.gpg"), fingerprint="A" * 40,
                                   baseline=str(baseline), proposal=str(proposal), output=str(home / "report"))

            def fake_run(command, env=None, limit=16000):
                if "--source-dir" in command:
                    source = pathlib.Path(command[command.index("--source-dir") + 1])
                    source.mkdir()
                    (source / "Kconfig").write_text(
                        'config PARENT\n\tbool "parent"\nconfig CHILD\n\tbool "child"\n'
                        '\tdepends on PARENT\nconfig REQUIRED\n\tbool "required"\n'
                        '\tdepends on PARENT\n')
                return {"exit_code": 0, "output": "", "output_truncated": False}

            def fake_make(source, output, target):
                if target == "olddefconfig" and output.name == "proposal":
                    self.tool.apply_proposal(output / ".config", output / ".config",
                                             {"CONFIG_CHILD": "n", "CONFIG_REQUIRED": "n"})
                return "6.18.53-fixture" if target == "kernelrelease" else ""

            with patch.object(self.tool, "run", side_effect=fake_run), \
                 patch.object(self.tool, "make", side_effect=fake_make), \
                 patch.object(self.tool, "required_symbols", return_value={"CONFIG_REQUIRED": "y"}):
                code = self.tool.analyze(args)
            report = json.loads((home / "report/report.json").read_text())
            self.assertEqual(code, 1)
            self.assertEqual(report["status"], "FAIL")
            self.assertEqual([row["symbol"] for row in report["collateral_changes"]],
                             ["CONFIG_CHILD", "CONFIG_REQUIRED"])
            self.assertIn("CONFIG_PARENT", report["full_diff"])
            self.assertEqual(baseline.read_bytes(), original)
            self.assertEqual(report["source_identity"]["status"], "AUTHENTICATED_FRESH_EXTRACTION")
            child = report["collateral_changes"][0]
            self.assertIn("PARENT", child["direct_dependencies"])


if __name__ == "__main__":
    unittest.main()
