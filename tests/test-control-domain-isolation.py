#!/usr/bin/env python3
"""Synthetic observations only; these tests never inspect or alter the host."""

import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts" / "verify-control-domain-isolation.py"


def verifier():
    spec = importlib.util.spec_from_file_location("control_domain_isolation", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def healthy():
    return {
        "schema": 1,
        "ipv4_routes": [], "ipv6_routes": [],
        "ipv4_rules": [], "ipv6_rules": [],
        "external_addresses": [], "wifi_associations": [], "dns_links": [],
        "nft": {"guard": True, "host_output": "deny", "maintenance_if": "none",
                "forward_deny": True, "bridge_deny": True, "nat": False,
                "masquerade": False},
        "forwarding": {"ipv4": False, "ipv6": False},
        "bridges": [], "unexpected_nics": [], "netns": [],
        "libvirt": {"running_domains": [], "active_networks": [],
                    "autostart_networks": []},
        "qemu": [],
        "usb": {"count": 1, "owner": "quarantined", "driver": None,
                "approved_path": True},
        "listeners": [], "ksm": False, "iommu": True, "nested": False,
        "guest_xml": None, "maintenance_authorized": False,
        "guest_internet_proven": False,
    }


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.tool = verifier()

    def report(self, expect, change=None):
        data = healthy()
        if change:
            change(data)
        return self.tool.evaluate(data, expect, synthetic=True)

    def test_safe_offline(self):
        report = self.report("offline")
        self.assertEqual(report["exit_code"], 0)
        self.assertEqual(report["source"], "synthetic")

    def test_unsafe_host_paths_fail_offline(self):
        changes = {
            "ipv4-default": ("ipv4_routes", [{"dst": "default", "dev": "wlan0"}]),
            "ipv6-default": ("ipv6_routes", [{"dst": "default", "dev": "wlan0"}]),
            "ipv4-nondefault": ("ipv4_routes", [{"dst": "198.51.100.0/24", "dev": "wlan0"}]),
            "policy-route": ("ipv4_rules", [{"table": "100"}]),
            "association-without-route": ("wifi_associations", ["wlan0"]),
            "external-dns": ("dns_links", ["wlan0"]),
            "nat": ("nft.nat", True),
            "masquerade": ("nft.masquerade", True),
            "ipv4-forward": ("forwarding.ipv4", True),
            "ipv6-forward": ("forwarding.ipv6", True),
            "bridge-forward": ("nft.bridge_deny", False),
            "unexpected-nic": ("unexpected_nics", ["ethernet"]),
            "unexpected-usb-nic": ("unexpected_nics", ["usb-nic"]),
            "usbip-v4": ("listeners", [{"kind": "usbip", "scope": "external"}]),
            "usbip-v6": ("listeners", [{"kind": "usbip", "scope": "external"}]),
            "libvirt-listener": ("listeners", [{"kind": "libvirt", "scope": "external"}]),
            "spice-listener": ("listeners", [{"kind": "spice", "scope": "external"}]),
            "vnc-listener": ("listeners", [{"kind": "vnc", "scope": "external"}]),
            "guard-absent": ("nft.guard", False),
            "namespace": ("netns", ["external"]),
        }
        for name, (path, value) in changes.items():
            with self.subTest(name=name):
                def change(data):
                    target = data
                    parts = path.split(".")
                    for part in parts[:-1]:
                        target = target[part]
                    target[parts[-1]] = value
                self.assertEqual(self.report("offline", change)["exit_code"], 1)

    def test_failed_collection_is_unknown_not_pass(self):
        for field in ("ipv4_routes", "ipv6_routes", "ipv4_rules", "wifi_associations",
                      "dns_links", "nft", "forwarding", "libvirt", "listeners", "usb"):
            with self.subTest(field=field):
                report = self.report("offline", lambda data: data.__setitem__(field, None))
                self.assertEqual(report["exit_code"], 2)
                self.assertIn("UNKNOWN", {row["status"] for row in report["checks"]})

    def test_guest_confinement_failures(self):
        base = healthy()
        base["libvirt"]["running_domains"] = ["approved"]
        base["usb"].update(owner="guest", driver=None)
        base["qemu"] = [{"domain": "approved", "uid": 64055, "gid": 64055,
                          "apparmor": "enforce", "seccomp": 2, "no_new_privs": 1,
                          "caps_reviewed": True, "qmp_local": True,
                          "service_uid_verified": True, "qmp_permissions_verified": True}]
        base["guest_xml"] = {"interfaces": 0, "filesystems": 0, "agents": 0,
                             "clipboard": False, "file_transfer": False,
                             "remote_graphics": False, "hostdev_count": 1,
                             "hostdev_approved": True}
        report = self.tool.evaluate(base, "guest", synthetic=True)
        self.assertEqual(report["exit_code"], 2)  # Internet needs a manual test.
        for field, value in (("interfaces", 1), ("agents", 1), ("hostdev_count", 2),
                             ("clipboard", True), ("remote_graphics", True)):
            with self.subTest(field=field):
                bad = copy.deepcopy(base)
                bad["guest_xml"][field] = value
                self.assertEqual(self.tool.evaluate(bad, "guest", synthetic=True)["exit_code"], 1)
        for field, value in (("uid", 0), ("gid", 0), ("apparmor", "complain"),
                             ("apparmor", "unconfined"), ("seccomp", 0),
                             ("qmp_local", False), ("service_uid_verified", False),
                             ("qmp_permissions_verified", False)):
            with self.subTest(field=field, value=value):
                bad = copy.deepcopy(base)
                bad["qemu"][0][field] = value
                self.assertEqual(self.tool.evaluate(bad, "guest", synthetic=True)["exit_code"], 1)
        for field, value in (("ksm", True), ("iommu", False), ("nested", True)):
            with self.subTest(field=field):
                bad = copy.deepcopy(base)
                bad[field] = value
                self.assertEqual(self.tool.evaluate(bad, "guest", synthetic=True)["exit_code"], 1)

    def test_maintenance_exclusivity(self):
        data = healthy()
        data["nft"].update(host_output="maintenance", maintenance_if="approved")
        data["usb"].update(owner="host", driver="mt7921u")
        data["maintenance_authorized"] = True
        data["ipv4_routes"] = [{"dst": "default", "dev": "approved"}]
        data["dns_links"] = ["approved"]
        self.assertEqual(self.tool.evaluate(data, "maintenance", synthetic=True)["exit_code"], 0)
        bad = copy.deepcopy(data)
        bad["ipv6_routes"] = [{"dst": "default", "dev": "second"}]
        self.assertEqual(self.tool.evaluate(bad, "maintenance", synthetic=True)["exit_code"], 1)
        bad = copy.deepcopy(data)
        bad["libvirt"]["running_domains"] = ["approved"]
        self.assertEqual(self.tool.evaluate(bad, "maintenance", synthetic=True)["exit_code"], 1)

    def test_nft_accept_cannot_hide_inside_drop_policy(self):
        base = [
            {"table": {"family": "inet", "name": "lockdown_guard"}},
            {"chain": {"family": "inet", "table": "lockdown_guard", "name": "output",
                       "type": "filter", "hook": "output", "policy": "drop"}},
            {"chain": {"family": "inet", "table": "lockdown_guard", "name": "input",
                       "type": "filter", "hook": "input", "policy": "drop"}},
            {"chain": {"family": "inet", "table": "lockdown_guard", "name": "forward",
                       "type": "filter", "hook": "forward", "policy": "drop"}},
            {"chain": {"family": "bridge", "table": "lockdown_guard", "name": "output",
                       "type": "filter", "hook": "output", "policy": "drop"}},
            {"chain": {"family": "bridge", "table": "lockdown_guard", "name": "forward",
                       "type": "filter", "hook": "forward", "policy": "drop"}},
        ]
        original = self.tool.json_command
        try:
            self.tool.json_command = lambda argv: {"nftables": base}
            self.assertEqual(self.tool.nft_state(None)["host_output"], "deny")
            accepted = copy.deepcopy(base)
            accepted.append({"rule": {"family": "inet", "table": "lockdown_guard",
                                      "chain": "output", "expr": [{"accept": None}]}})
            self.tool.json_command = lambda argv: {"nftables": accepted}
            self.assertIsNone(self.tool.nft_state(None)["host_output"])
            self.assertFalse(self.tool.nft_state(None)["guard"])
        finally:
            self.tool.json_command = original

    def test_fixture_cli_never_collects_live_or_prints_private_values(self):
        data = healthy()
        data["untrusted_private_input"] = "SECRET_SSID 192.0.2.1 private-host"
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "observation.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            original = self.tool.collect_live
            try:
                self.tool.collect_live = lambda *args: self.fail("fixture invoked live collector")
                import contextlib
                import io
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    code = self.tool.main(["--expect", "offline", "--fixture", str(path),
                                           "--format", "json"])
            finally:
                self.tool.collect_live = original
        report = json.loads(output.getvalue())
        self.assertEqual(code, 0)
        self.assertEqual(report["source"], "synthetic")
        for secret in ("SECRET_SSID", "192.0.2.1", "private-host"):
            self.assertNotIn(secret, output.getvalue())


if __name__ == "__main__":
    unittest.main()
