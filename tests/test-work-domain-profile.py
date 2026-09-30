#!/usr/bin/env python3
"""Structured policy checks for the proposed production work guest."""

import importlib.util
import pathlib
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate-work-domain.py"
PROFILE = ROOT / "vm-profiles" / "work-domain" / "domain.xml"


def module():
    spec = importlib.util.spec_from_file_location("work_domain_validator", VALIDATOR)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class WorkDomainTests(unittest.TestCase):
    def setUp(self):
        self.tool = module()
        self.xml = PROFILE.read_text(encoding="utf-8")

    def validate(self, xml):
        return self.tool.validate(xml)

    def mutate(self, fn):
        root = ET.fromstring(self.xml)
        fn(root)
        return ET.tostring(root, encoding="unicode")

    def test_authoritative_profile_passes(self):
        self.assertEqual(self.validate(self.xml), [])

    def test_network_and_host_integration_are_rejected(self):
        additions = (
            "<interface type='network'><source network='default'/></interface>",
            "<interface type='bridge'><source bridge='br0'/></interface>",
            "<interface type='direct'><source dev='wlan0' mode='bridge'/></interface>",
            "<filesystem type='mount'><driver type='virtiofs'/></filesystem>",
            "<channel type='unix'><target name='org.qemu.guest_agent.0'/></channel>",
            "<redirdev bus='usb' type='spicevmc'/>",
            "<hostdev mode='subsystem' type='pci'/>",
            "<hostdev mode='subsystem' type='usb'><source><vendor id='0x1234'/>"
            "<product id='0xabcd'/></source></hostdev>",
        )
        for element in additions:
            with self.subTest(element=element):
                xml = self.mutate(lambda root: root.find("devices").append(ET.fromstring(element)))
                self.assertTrue(self.validate(xml))

    def test_display_escape_paths_are_rejected(self):
        def change_attribute(root, path, key, value):
            root.find(path).set(key, value)
        for path, key, value in (("devices/graphics/clipboard", "copypaste", "yes"),
                                 ("devices/graphics/filetransfer", "enable", "yes"),
                                 ("devices/graphics", "type", "vnc"),
                                 ("devices/graphics", "port", "5900"),
                                 ("devices/graphics", "autoport", "yes"),
                                 ("devices/graphics/listen", "type", "address")):
            with self.subTest(path=path, key=key):
                self.assertTrue(self.validate(self.mutate(
                    lambda root: change_attribute(root, path, key, value))))

    def test_doctype_and_unknown_elements_are_rejected(self):
        self.assertTrue(self.validate("<!DOCTYPE domain [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + self.xml))
        xml = self.mutate(lambda root: root.find("devices").append(ET.Element("mystery")))
        self.assertTrue(self.validate(xml))
        xml = self.mutate(lambda root: root.append(ET.fromstring("<devices><interface/></devices>")))
        self.assertTrue(self.validate(xml))
        xml = self.mutate(lambda root: root.find("devices/graphics").append(
            ET.fromstring("<gl enable='yes'/>")))
        self.assertTrue(self.validate(xml))

    def test_disk_and_hostdev_mutations_are_rejected(self):
        for path, key, value in (("devices/disk/source", "file", "/home/user/private.qcow2"),
                                 ("devices/disk/target", "bus", "sata"),
                                 ("devices/hostdev/source/vendor", "id", "0x1234")):
            with self.subTest(path=path):
                def alter(root):
                    root.find(path).set(key, value)
                self.assertTrue(self.validate(self.mutate(alter)))

    def test_required_confinement_cannot_be_omitted(self):
        for path in ("devices/hostdev", "seclabel", "devices/graphics/clipboard",
                     "devices/graphics/filetransfer", "devices/graphics/listen"):
            with self.subTest(path=path):
                def remove(root):
                    parent_path, child = path.rsplit("/", 1) if "/" in path else ("", path)
                    parent = root.find(parent_path) if parent_path else root
                    parent.remove(parent.find(child))
                self.assertTrue(self.validate(self.mutate(remove)))


if __name__ == "__main__":
    unittest.main()
