#!/usr/bin/env python3
"""Offline ThinkPad evidence fixtures. No host hardware is read or changed."""

import importlib.util
import json
import pathlib
import tempfile
import unittest
from types import SimpleNamespace


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts" / "collect-validation-evidence.py"
RELEASE = "6.18.53-lockdown-t14g3-audit11"


def collector():
    spec = importlib.util.spec_from_file_location("lockdown_validation", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def put(root, name, value):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def fixture(root):
    put(root, "commands/uname-r", RELEASE + "\n")
    put(root, "commands/secure-boot-results.txt",
        "[PASS] secure-boot-state: enabled\n[PASS] kernel-lockdown: none [integrity] confidentiality\n"
        "[PASS] expected-kernel: " + RELEASE + "\n"
        "[NOT_APPLICABLE] module-signatures: monolithic kernel\n")
    put(root, f"boot/config-{RELEASE}",
        'CONFIG_LOCALVERSION="-lockdown-t14g3-audit11"\n'
        '# CONFIG_MODULES is not set\nCONFIG_INTEL_IOMMU=y\nCONFIG_KVM_INTEL=y\n')
    put(root, "proc/cmdline", "root=UUID=6dc6712f-ec48-4782-a37a-9cef06b82a0d "
        "intel_iommu=on secret=SECRET_SSID ip=192.0.2.1\n")
    put(root, "sys/devices/system/cpu/online", "0-11\n")
    put(root, "sys/devices/system/cpu/present", "0-11\n")
    put(root, "proc/cpuinfo", "model name\t: Intel Core i5-1245U\nmicrocode\t: 0x43b\n")
    put(root, "commands/findmnt.json", '{"filesystems":[{"target":"/","source":"/dev/mapper/ubuntu--vg-ubuntu--lv","fstype":"ext4"}]}')
    put(root, "commands/lsblk.json", '{"blockdevices":[{"name":"nvme0n1","type":"disk","children":[{"name":"nvme0n1p3","type":"part","fstype":"crypto_LUKS","children":[{"name":"dm-0","type":"crypt"}]}]}]}')
    (root / "sys/kernel/iommu_groups/0").mkdir(parents=True)
    put(root, "sys/bus/pci/drivers/i915/bound-devices.txt", "0000:00:02.0\n")
    put(root, "sys/class/drm/card0-eDP-1/status", "connected\n")
    put(root, "sys/class/drm/card0-HDMI-A-1/status", "disconnected\n")
    put(root, "sys/bus/pci/drivers/i915/0000-runtime-pm", "active\n")
    put(root, "sys/bus/usb/devices/1-1/idVendor", "0e8d\n")
    put(root, "sys/bus/usb/devices/1-1/idProduct", "7961\n")
    put(root, "sys/bus/usb/devices/1-1/driver_name", "mt7921u\n")
    put(root, "sys/bus/usb/devices/1-1/busnum", "4\n")
    put(root, "sys/bus/usb/devices/1-1/devpath", "1\n")
    put(root, "sys/class/net/wlan0/operstate", "up\n")
    for name in ("dev/kvm", "dev/vhost-net", "dev/net/tun"):
        put(root, name, "")
    put(root, "proc/asound/cards", " 0 [sofhdadsp ]: sof-hda-dsp - sof-hda-dsp\n")
    put(root, "proc/bus/input/devices", 'N: Name="AT Translated Set 2 keyboard"\n'
        'N: Name="Synaptics Touchpad"\nN: Name="Elan TrackPoint"\n')
    put(root, "sys/power/mem_sleep", "[s2idle]\n")
    put(root, "sys/kernel/debug/wakeup_sources", "name count\nusb 1\n")
    put(root, "commands/systemctl-failed.txt", "")
    put(root, "commands/virsh-guests.txt", "test-guest\n")
    put(root, "commands/kernel-log.txt", "DMAR: IOMMU enabled\nDMAR: IRQ remapping enabled\n")


class ValidationCollectorTests(unittest.TestCase):
    def setUp(self):
        self.tool = collector()

    def run_fixture(self, changes=None, missing=(), expected=RELEASE):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp) / "evidence"
            root.mkdir()
            fixture(root)
            for name, value in (changes or {}).items():
                put(root, name, value)
            for name in missing:
                path = root / name
                path.rmdir() if path.is_dir() else path.unlink()
            original_files = sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file())
            output = pathlib.Path(temp) / "bundle"
            args = SimpleNamespace(expected_kernel=expected, output=str(output),
                                   evidence_root=str(root), include_host_hash=False)
            code = self.tool.collect(args)
            report = json.loads((output / "validation.json").read_text())
            markdown = (output / "validation.md").read_text()
            self.assertEqual(original_files,
                             sorted(str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()))
            return code, report, markdown

    def test_healthy_offline_evidence_stays_offline_and_private(self):
        code, report, markdown = self.run_fixture()
        checks = {row["check"]: row["status"] for row in report["checks"]}
        self.assertEqual(code, 0)
        self.assertEqual(report["mode"], "OFFLINE_FIXTURE")
        for name in ("kernel-identity", "secure-boot-state", "kernel-lockdown",
                     "cpu-count", "root-storage", "iommu", "wifi-driver", "kvm", "s2idle"):
            self.assertEqual(checks[name], "PASS", name)
        self.assertEqual(checks["internal-display"], "MANUAL_TEST_REQUIRED")
        self.assertEqual(checks["libvirt-inventory"], "PASS")
        self.assertEqual(checks["wifi-interface"], "PASS")
        self.assertIn("[ ] Internal panel", markdown)
        serialized = json.dumps(report) + markdown
        for secret in ("SECRET_SSID", "192.0.2.1", "6dc6712f-ec48-4782-a37a-9cef06b82a0d",
                       "0e:11:22:33:44:55", "test-guest"):
            self.assertNotIn(secret, serialized)
        self.assertIsNone(report["manifest"]["hostname_sha256"])

    def test_failure_classification(self):
        cases = (
            ({}, (), "wrong-release", "kernel-identity"),
            ({"commands/secure-boot-results.txt": "[FAIL] secure-boot-state: disabled\n"}, (), None, "secure-boot-state"),
            ({"commands/secure-boot-results.txt": "[FAIL] kernel-lockdown: none\n"}, (), None, "kernel-lockdown"),
            ({"sys/devices/system/cpu/online": "0-1\n"}, (), None, "cpu-count"),
            ({}, ("dev/kvm",), None, "kvm"),
            ({}, (), None, "iommu"),
            ({"sys/bus/usb/devices/1-1/driver_name": "\n"}, (), None, "wifi-driver"),
            ({"sys/power/mem_sleep": "[deep] s2idle\n"}, (), None, "s2idle"),
            ({"commands/systemctl-failed.txt": "failed.service loaded failed failed\n"}, (), None, "system-health"),
            ({"commands/kernel-log.txt": "i915: firmware load failed\n"}, (), None, "graphics-firmware"),
        )
        for changes, missing, expected, check in cases:
            with self.subTest(check=check):
                if check == "iommu":
                    changes = {"commands/kernel-log.txt": "No DMAR evidence\n"}
                    missing = ("sys/kernel/iommu_groups/0",)
                code, report, _ = self.run_fixture(changes, missing,
                                                   expected=expected or RELEASE)
                statuses = {row["check"]: row["status"] for row in report["checks"]}
                self.assertEqual(statuses[check], "FAIL")
                self.assertEqual(code, 1)

    def test_unreadable_evidence_is_unknown(self):
        code, report, _ = self.run_fixture(missing=("sys/power/mem_sleep",))
        statuses = {row["check"]: row["status"] for row in report["checks"]}
        self.assertEqual(statuses["s2idle"], "UNKNOWN")
        self.assertEqual(code, 3)


if __name__ == "__main__":
    unittest.main()
