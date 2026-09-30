#!/usr/bin/env python3
"""Validate the narrow work-domain libvirt XML template without side effects."""

import argparse
from collections import Counter
import pathlib
import sys
import xml.etree.ElementTree as ET

ALLOWED_ROOT = {"name", "memory", "vcpu", "os", "features", "cpu", "on_crash",
                "devices", "seclabel"}
ALLOWED_DEVICES = {"disk", "controller", "input", "graphics", "video", "hostdev"}


def validate(xml):
    errors = []
    if not isinstance(xml, str) or len(xml) > 1024 * 1024 or "<!" in xml or "<?" in xml:
        return ["DOCTYPE, entity, processing instruction, or oversized XML is forbidden"]
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return ["XML could not be parsed"]
    if root.tag != "domain" or root.get("type") != "kvm":
        errors.append("KVM domain required")
    if root.attrib != {"type": "kvm"} or Counter(child.tag for child in root) != {
            name: 1 for name in ALLOWED_ROOT}:
        errors.append("top-level elements must match the reviewed profile")
    if root.findtext("name") != "work-domain":
        errors.append("approved domain name required")
    memory = root.find("memory")
    if memory is None or memory.get("dumpCore") != "off":
        errors.append("guest memory must be excluded from host core dumps")
    if root.find("on_crash") is None or root.findtext("on_crash") != "destroy":
        errors.append("automatic crash restart forbidden")
    label = root.find("seclabel")
    if label is None or label.attrib != {"type": "dynamic", "model": "apparmor",
                                               "relabel": "yes"}:
        errors.append("dynamic AppArmor sVirt required")
    devices = root.find("devices")
    if devices is None:
        return errors + ["devices missing"]
    if Counter(child.tag for child in devices) != {name: 1 for name in ALLOWED_DEVICES}:
        errors.append("device elements must match the reviewed profile")
    if len(devices.findall("interface")) or len(devices.findall("filesystem")):
        errors.append("guest network and host filesystem forbidden")
    disks = devices.findall("disk")
    if len(disks) != 1 or disks[0].get("device") != "disk" or disks[0].get("type") != "file":
        errors.append("exactly one file-backed guest disk required")
    else:
        source = disks[0].find("source")
        driver = disks[0].find("driver")
        target = disks[0].find("target")
        if (source is None or source.attrib != {"file":
                "/var/lib/libvirt/images/work-domain.qcow2"} or
                driver is None or driver.attrib != {"name": "qemu", "type": "qcow2",
                                                   "cache": "none"} or
                target is None or target.attrib != {"dev": "vda", "bus": "virtio"} or
                len(disks[0]) != 3):
            errors.append("guest disk source must be reviewed")
    hostdevs = devices.findall("hostdev")
    if len(hostdevs) != 1:
        errors.append("exactly one approved USB hostdev required")
    else:
        dev = hostdevs[0]
        vendor = dev.find("source/vendor")
        product = dev.find("source/product")
        source = dev.find("source")
        if ((dev.get("mode"), dev.get("type"), dev.get("managed")) != (
                "subsystem", "usb", "yes") or source is None or
                source.get("startupPolicy") != "mandatory" or vendor is None or
                vendor.get("id") != "0x0e8d" or product is None or
                product.get("id") != "0x7961" or len(source) != 2 or
                len(dev) != 1):
            errors.append("hostdev is not the single mandatory MT7921U")
    graphics = devices.findall("graphics")
    if len(graphics) != 1:
        errors.append("exactly one local graphics device required")
    else:
        display = graphics[0]
        listen = display.findall("listen")
        clipboard = display.find("clipboard")
        transfer = display.find("filetransfer")
        if (display.get("type") != "spice" or display.get("autoport") != "no" or
                display.get("port") != "-1" or display.get("listen") is not None or
                display.get("websocket") is not None or len(listen) != 1 or
                listen[0].attrib != {"type": "none"} or
                Counter(child.tag for child in display) != {
                    "listen": 1, "clipboard": 1, "filetransfer": 1}):
            errors.append("SPICE must have no TCP or WebSocket listener")
        if clipboard is None or clipboard.get("copypaste") != "no":
            errors.append("SPICE clipboard must be explicitly disabled")
        if transfer is None or transfer.get("enable") != "no":
            errors.append("SPICE file transfer must be explicitly disabled")
    controller = devices.find("controller")
    if controller is None or controller.attrib != {"type": "usb", "model": "qemu-xhci"}:
        errors.append("only reviewed USB controller is allowed")
    input_device = devices.find("input")
    if input_device is None or input_device.attrib != {"type": "tablet", "bus": "usb"}:
        errors.append("only reviewed local input is allowed")
    video = devices.find("video")
    if (video is None or len(video) != 1 or video.find("model") is None or
            video.find("model").attrib != {"type": "virtio", "heads": "1"}):
        errors.append("only reviewed video device is allowed")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        errors = validate(args.xml.read_text(encoding="utf-8"))
    except OSError:
        print("UNKNOWN: XML could not be read", file=sys.stderr)
        return 2
    for error in errors:
        print("FAIL: " + error)
    if not errors:
        print("PASS: work-domain XML structural policy")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
