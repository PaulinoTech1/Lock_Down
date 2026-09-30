#!/usr/bin/env python3
"""Read-only, fail-closed control-domain observation. Fixtures are synthetic."""

import argparse
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import xml.etree.ElementTree as ET

STATUSES = {"PASS", "FAIL", "WARN", "UNKNOWN", "NOT_APPLICABLE", "MANUAL_TEST_REQUIRED"}
APPROVED_USB = ("0x0e8d", "0x7961")


def get(data, path):
    value = data
    for key in path.split("."):
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def evaluate(data, expect, synthetic=False):
    if expect not in ("offline", "guest", "maintenance"):
        raise ValueError("invalid expectation")
    if not isinstance(data, dict) or data.get("schema") != 1:
        raise ValueError("unsupported observation schema")
    checks = []

    def check(name, value, predicate, reason):
        status = "UNKNOWN" if value is None else "PASS" if predicate(value) else "FAIL"
        checks.append({"check": name, "status": status, "reason": reason})

    maintenance = expect == "maintenance"
    guest = expect == "guest"
    allowed_if = "approved" if maintenance else "none"

    for family in ("ipv4", "ipv6"):
        routes = get(data, family + "_routes")
        check(family + "-routes", routes,
              lambda rows: isinstance(rows, list) and
              (all(isinstance(row, dict) and row.get("dev") == allowed_if for row in rows)
               if maintenance else len(rows) == 0),
              "external routes must match the expected owner")
        rules = get(data, family + "_rules")
        check(family + "-policy-rules", rules,
              lambda rows: isinstance(rows, list) and not rows,
              "non-default policy routing is not approved")
    if maintenance:
        check("maintenance-route-present", get(data, "ipv4_routes"),
              lambda rows: isinstance(rows, list) and bool(rows),
              "maintenance requires an observed approved route")

    for name, path in (("external-addresses", "external_addresses"),
                       ("wifi-association", "wifi_associations"),
                       ("external-dns", "dns_links")):
        check(name, get(data, path),
              lambda rows: isinstance(rows, list) and
              (all(row == "approved" for row in rows) if maintenance else not rows),
              "host external link state must match the expected owner")

    check("guard-installed", get(data, "nft.guard"), lambda x: x is True,
          "dedicated egress guard must be present")
    check("host-output", get(data, "nft.host_output"),
          lambda x: x == ("maintenance" if maintenance else "deny"),
          "host output policy must match the expected state")
    check("maintenance-interface", get(data, "nft.maintenance_if"),
          lambda x: x == allowed_if,
          "maintenance allowance must name only the approved interface")
    for name, path in (("ip-forward-guard", "nft.forward_deny"),
                       ("bridge-forward-guard", "nft.bridge_deny")):
        check(name, get(data, path), lambda x: x is True,
              "forwarding guard must deny")
    for name, path in (("nat", "nft.nat"), ("masquerade", "nft.masquerade"),
                       ("ipv4-forwarding", "forwarding.ipv4"),
                       ("ipv6-forwarding", "forwarding.ipv6")):
        check(name, get(data, path), lambda x: x is False,
              "NAT and kernel forwarding must be off")

    for name, path in (("bridges", "bridges"), ("unexpected-nics", "unexpected_nics"),
                       ("network-namespaces", "netns"),
                       ("active-libvirt-networks", "libvirt.active_networks"),
                       ("libvirt-network-autostart", "libvirt.autostart_networks")):
        check(name, get(data, path), lambda rows: isinstance(rows, list) and not rows,
              "no alternate forwarding or egress path is approved")
    check("external-listeners", get(data, "listeners"),
          lambda rows: isinstance(rows, list) and
          all(isinstance(row, dict) and row.get("scope") == "local" for row in rows),
          "external listeners, including USB/IP and management, are prohibited")

    domains = get(data, "libvirt.running_domains")
    check("running-domains", domains,
          lambda rows: isinstance(rows, list) and
          (rows == ["approved"] if guest else not rows),
          "only the approved guest may run in guest mode")
    qemu = get(data, "qemu")
    check("qemu-process-count", qemu,
          lambda rows: isinstance(rows, list) and (len(rows) == 1 if guest else not rows),
          "unexpected system, session, or raw QEMU process")

    usb = get(data, "usb")
    check("usb-identity", usb,
          lambda x: isinstance(x, dict) and (
              (x.get("count") == 1 and x.get("approved_path") is True) or
              (not guest and not maintenance and x.get("count") == 0)),
          "one approved physical adapter must be identified")
    check("usb-ownership", usb,
          lambda x: isinstance(x, dict) and (
              x.get("owner") == ("guest" if guest else "host" if maintenance else "quarantined") and
              (x.get("driver") == "mt7921u" if maintenance else x.get("driver") is None) and
              x.get("authorized") is (guest or maintenance) or
              not guest and not maintenance and x.get("count") == 0 and
              x.get("owner") == "absent" and x.get("authorized") is None),
          "USB and host network driver ownership must match the state")

    if guest:
        xml = get(data, "guest_xml")
        check("guest-xml", xml,
              lambda x: isinstance(x, dict) and
              all(x.get(field) == 0 for field in ("interfaces", "filesystems", "agents")) and
              x.get("hostdev_count") == 1 and x.get("hostdev_approved") is True and
              x.get("clipboard") is False and x.get("file_transfer") is False and
              x.get("remote_graphics") is False,
              "guest XML must contain only approved device and display paths")
        confinement = None
        if isinstance(qemu, list):
            if len(qemu) != 1 or not isinstance(qemu[0], dict):
                confinement = False
            else:
                row = qemu[0]
                needed = ("domain", "uid", "gid", "apparmor", "seccomp",
                          "no_new_privs", "caps_reviewed", "qmp_local",
                          "service_uid_verified", "qmp_permissions_verified")
                bad = (row.get("domain") not in (None, "approved") or
                       isinstance(row.get("uid"), int) and row["uid"] == 0 or
                       isinstance(row.get("gid"), int) and row["gid"] == 0 or
                       row.get("apparmor") not in (None, "enforce") or
                       row.get("seccomp") not in (None, 2) or
                       row.get("no_new_privs") not in (None, 1) or
                       any(row.get(key) is False for key in (
                           "caps_reviewed", "qmp_local", "service_uid_verified",
                           "qmp_permissions_verified")))
                confinement = False if bad else None if any(
                    row.get(key) is None for key in needed) else True
        check("qemu-confinement", confinement, lambda x: x is True,
              "QEMU must have a reviewed unprivileged confinement")
        for name, path, good in (("ksm", "ksm", False), ("iommu", "iommu", True),
                                 ("nested-virtualization", "nested", False)):
            check(name, get(data, path), lambda x, good=good: x is good,
                  "runtime hardening must match the approved profile")
        internet = get(data, "guest_internet_proven")
        checks.append({"check": "guest-internet", "status":
                       "MANUAL_TEST_REQUIRED" if internet is False or internet is None else "PASS",
                       "reason": "guest Internet requires owner or trusted guest-side evidence"})
    if maintenance:
        check("maintenance-authorization", get(data, "maintenance_authorized"),
              lambda x: x is True, "an unexpired authorization is required")

    statuses = {row["status"] for row in checks}
    code = 1 if "FAIL" in statuses else 2 if statuses & {
        "UNKNOWN", "WARN", "MANUAL_TEST_REQUIRED"} else 0
    return {"schema": 1, "source": "synthetic" if synthetic else "live",
            "expect": expect, "checks": checks, "exit_code": code}


def command(argv, timeout=8):
    """Only fixed, read-only argv; failure is unknown, never empty success."""
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=timeout, check=False)
        if result.returncode or len(result.stdout) > 1024 * 1024:
            return None
        return result.stdout.decode("utf-8", errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return None


def json_command(argv):
    raw = command(argv)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def read(path):
    try:
        return pathlib.Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def routes(family):
    rows = json_command(["ip", "-j", "-" + family, "route", "show", "table", "all"])
    if not isinstance(rows, list):
        return None
    return [{"dst": row.get("dst", "default"), "dev": row.get("dev", "UNKNOWN")}
            for row in rows if isinstance(row, dict) and row.get("dev") != "lo" and
            row.get("type") not in ("local", "broadcast", "multicast", "blackhole")]


def rules(family):
    rows = json_command(["ip", "-j", "-" + family, "rule", "show"])
    if not isinstance(rows, list):
        return None
    defaults = {(0, "local"), (32766, "main"), (32767, "default"),
                (0, "255"), (32766, "254"), (32767, "253")}
    return [{"table": str(row.get("table", "UNKNOWN"))} for row in rows
            if isinstance(row, dict) and (row.get("priority"), str(row.get("table"))) not in defaults]


def addresses(approved_if):
    rows = json_command(["ip", "-j", "address", "show"])
    if not isinstance(rows, list):
        return None
    result = []
    for row in rows:
        if not isinstance(row, dict):
            return None
        name = row.get("ifname")
        if name == "lo":
            continue
        for addr in row.get("addr_info", []):
            if addr.get("scope") == "global":
                result.append("approved" if name == approved_if else "other")
    return result


def associations(approved_if):
    listing = command(["iw", "dev"])
    if listing is None:
        return None
    interfaces = re.findall(r"^\s*Interface\s+(\S+)", listing, re.M)
    result = []
    for name in interfaces:
        status = command(["iw", "dev", name, "link"])
        if status is None:
            return None
        if "Not connected." not in status:
            if "Connected to " not in status:
                return None
            result.append("approved" if name == approved_if else "other")
    return result


def dns_links(approved_if):
    output = command(["resolvectl", "dns"])
    if output is None:
        return None
    result = []
    for line in output.splitlines():
        if ":" not in line or not line.split(":", 1)[1].strip():
            continue
        if line.startswith("Global:"):
            result.append("other")
        else:
            match = re.match(r"Link\s+\d+\s+\(([^)]+)\):", line)
            if not match:
                return None
            result.append("approved" if match.group(1) == approved_if else "other")
    return result


def nft_state(approved_if):
    data = json_command(["nft", "-j", "list", "ruleset"])
    if not isinstance(data, dict) or not isinstance(data.get("nftables"), list):
        return None
    objects = data["nftables"]
    guard = any(item.get("table", {}).get("family") == "inet" and
                item.get("table", {}).get("name") == "lockdown_guard" for item in objects)
    chains = {item["chain"]["name"]: item["chain"] for item in objects
              if "chain" in item and item["chain"].get("family") == "inet" and
              item["chain"].get("table") == "lockdown_guard"}
    bridge = {item["chain"]["name"]: item["chain"] for item in objects
              if "chain" in item and item["chain"].get("family") == "bridge" and
              item["chain"].get("table") == "lockdown_guard"}
    def closed(chains_by_name, name):
        chain = chains_by_name.get(name, {})
        if chain.get("hook") != name or chain.get("type") != "filter" or chain.get("policy") != "drop":
            return False
        # An accept inside a drop-policy chain can still open the path.
        for item in objects:
            rule = item.get("rule", {})
            if rule.get("family") == chain.get("family") and rule.get("table") == "lockdown_guard" and rule.get("chain") == name:
                expr = rule.get("expr", [])
                if not isinstance(expr, list):
                    return False
                if any(isinstance(term, dict) and "accept" in term for term in expr):
                    loopback_key = "iifname" if name == "input" else "oifname"
                    loopback_only = (name in ("input", "output") and len(expr) == 2 and
                        expr[0] == {"match": {"op": "==", "left": {"meta": {"key": loopback_key}},
                                             "right": "lo"}} and "accept" in expr[1])
                    if not loopback_only:
                        return False
        return True
    rules_json = json.dumps(objects, separators=(",", ":"))
    nat = any("nat" in item.get("chain", {}).get("type", "") for item in objects) or any(
        "snat" in json.dumps(item.get("rule", {}).get("expr", [])) for item in objects)
    masq = '"masquerade"' in rules_json
    # Until a reviewed template exists, every output accept is UNKNOWN.
    host_output = "deny" if closed(chains, "output") else None
    return {"guard": guard and closed(chains, "output") and closed(chains, "input") and
            closed(chains, "forward") and closed(bridge, "output") and
            closed(bridge, "forward"), "host_output": host_output,
            "maintenance_if": "none" if host_output == "deny" else None,
            "forward_deny": closed(chains, "forward"),
            "bridge_deny": closed(bridge, "forward"),
            "nat": nat, "masquerade": masq}


def libvirt_state(approved_domain):
    domains = command(["virsh", "-c", "qemu:///system", "list", "--name"])
    networks = command(["virsh", "-c", "qemu:///system", "net-list", "--name"])
    all_networks = command(["virsh", "-c", "qemu:///system", "net-list", "--all", "--name"])
    if None in (domains, networks, all_networks):
        return None
    autostart = []
    for name in all_networks.splitlines():
        if not name:
            continue
        info = command(["virsh", "-c", "qemu:///system", "net-info", name])
        if info is None:
            return None
        if re.search(r"^Autostart:\s+yes\s*$", info, re.M | re.I):
            autostart.append(name)
    return {"running_domains": ["approved" if name == approved_domain else "other"
                                for name in domains.splitlines() if name],
            "active_networks": ["other" for name in networks.splitlines() if name],
            "autostart_networks": ["other" for name in autostart]}


def link_inventory(approved_if):
    rows = json_command(["ip", "-j", "link", "show"])
    if not isinstance(rows, list):
        return None
    unexpected = []
    for row in rows:
        if not isinstance(row, dict):
            return None
        name = row.get("ifname")
        if name in ("lo", approved_if):
            continue
        flags = row.get("flags", [])
        if row.get("operstate") == "UP" or "UP" in flags:
            unexpected.append("other")
    return unexpected


def namespace_inventory():
    try:
        host = os.readlink("/proc/self/ns/net")
        seen = set()
        for entry in pathlib.Path("/proc").iterdir():
            if entry.name.isdigit():
                seen.add(os.readlink(str(entry / "ns/net")))
        return [] if seen == {host} else ["other"]
    except OSError:
        return None


def listener_inventory():
    # No raw addresses or process names leave this function.
    output = command(["ss", "-H", "-lntup"])
    if output is None:
        return None
    result = []
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 5:
            return None
        local = parts[4]
        if local.startswith(("127.", "[::1]:", "::1:", "localhost:")):
            scope = "local"
        elif local.startswith(("0.0.0.0:", "[::]:", "*:", ":::")):
            scope = "external"
        else:
            scope = "external"  # Non-loopback bind, including link-local.
        result.append({"scope": scope})
    return result


def process_inventory(approved_domain, expected_qemu_user):
    result = []
    pids = []
    try:
        import pwd
        expected_uid = pwd.getpwnam(expected_qemu_user).pw_uid if expected_qemu_user else None
    except (ImportError, KeyError):
        expected_uid = None
    try:
        entries = list(pathlib.Path("/proc").iterdir())
    except OSError:
        return None
    for entry in entries:
        if not entry.name.isdigit():
            continue
        cmdline = None
        try:
            cmdline = (entry / "cmdline").read_bytes()[:131072].decode(
                "utf-8", errors="replace").replace("\0", " ")
        except OSError:
            return None  # An incomplete process inventory cannot prove absence.
        if not re.search(r"(?:^|/|\s)qemu-(?:system|kvm)", cmdline):
            continue
        status = read(entry / "status")
        label = read(entry / "attr/current")
        if status is None or label is None:
            return None
        def number(name):
            match = re.search(r"^" + re.escape(name) + r":\s+(\d+)", status, re.M)
            return int(match.group(1)) if match else None
        cap_match = re.search(r"^CapEff:\s+([0-9a-fA-F]+)", status, re.M)
        caps_reviewed = int(cap_match.group(1), 16) == 0 if cap_match else None
        domain = ("approved" if approved_domain and
                  ("guest=" + approved_domain) in cmdline else "other")
        uid = number("Uid")
        monitor = re.search(r"(?:^|\s)-chardev\s+socket,[^ ]*id=charmonitor,[^ ]*path=([^, ]+)",
                            cmdline)
        monitor_path = monitor.group(1) if monitor else None
        qmp_permissions = None
        if monitor_path and monitor_path.startswith(("/run/libvirt/", "/var/lib/libvirt/qemu/")):
            try:
                info = os.stat(monitor_path)
                qmp_permissions = (stat.S_ISSOCK(info.st_mode) and
                                   info.st_mode & 0o077 == 0 and
                                   info.st_uid in (0, expected_uid))
            except OSError:
                pass
        pids.append(int(entry.name))
        result.append({"domain": domain, "uid": uid, "gid": number("Gid"),
                       "apparmor": "enforce" if "(enforce)" in label and
                       "libvirt-" in label else "other",
                       "seccomp": number("Seccomp"), "no_new_privs": number("NoNewPrivs"),
                       "caps_reviewed": caps_reviewed,
                       "qmp_local": monitor_path is not None,
                       "qmp_permissions_verified": qmp_permissions,
                       "service_uid_verified": uid == expected_uid if
                       expected_uid is not None and uid is not None else None})
    return result, pids


def usb_inventory(approved_path, qemu_pids):
    try:
        matches = []
        for entry in pathlib.Path("/sys/bus/usb/devices").iterdir():
            vendor = read(entry / "idVendor")
            product = read(entry / "idProduct")
            if (vendor, product) == ("0e8d", "7961"):
                matches.append(entry)
        if len(matches) != 1:
            return {"count": len(matches), "owner": "absent" if not matches else "unknown",
                    "driver": None,
                    "approved_path": False, "authorized": None}
        entry = matches[0]
        bound = []
        for interface in entry.parent.glob(entry.name + ":*"):
            driver = interface / "driver"
            if driver.is_symlink():
                bound.append(driver.resolve().name)
        driver_name = "mt7921u" if "mt7921u" in bound else (bound[0] if bound else None)
        authorized = read(entry / "authorized")
        authorized = authorized == "1" if authorized in ("0", "1") else None
        bus = read(entry / "busnum")
        dev = read(entry / "devnum")
        device_node = None if not bus or not dev else "/dev/bus/usb/{:03d}/{:03d}".format(
            int(bus), int(dev))
        qemu_owner = False
        if device_node:
            for pid in qemu_pids:
                for fd in pathlib.Path("/proc").joinpath(str(pid), "fd").iterdir():
                    try:
                        if os.readlink(fd) == device_node:
                            qemu_owner = True
                    except OSError:
                        return None
        owner = ("guest" if qemu_owner and driver_name is None and authorized is True else
                 "host" if driver_name == "mt7921u" and not qemu_owner and authorized is True else
                 "quarantined" if driver_name is None and not qemu_owner and authorized is False
                 else "unknown")
        return {"count": 1, "owner": owner, "driver": driver_name,
                "approved_path": entry.name == approved_path if approved_path else None,
                "authorized": authorized}
    except (OSError, ValueError):
        return None


def guest_xml_summary(approved_domain):
    if not approved_domain:
        return None
    live = command(["virsh", "-c", "qemu:///system", "dumpxml", approved_domain])
    inactive = command(["virsh", "-c", "qemu:///system", "dumpxml", "--inactive", approved_domain])
    if live is None or inactive is None:
        return None
    try:
        roots = [ET.fromstring(x) for x in (live, inactive)]
    except ET.ParseError:
        return None
    summaries = []
    for root in roots:
        if root.tag != "domain" or any(child.tag not in {
                "name", "uuid", "memory", "currentMemory", "vcpu", "os", "features",
                "cpu", "on_crash", "on_poweroff", "on_reboot", "clock", "pm",
                "devices", "seclabel", "resource", "cputune", "numatune"} for child in root):
            return None
        devices = root.find("devices")
        if devices is None:
            return None
        if any(child.tag not in {"emulator", "disk", "controller", "input", "graphics",
                                  "video", "hostdev", "memballoon", "watchdog"}
               for child in devices):
            return None
        hostdevs = devices.findall("hostdev")
        graphics = devices.findall("graphics")
        summaries.append({
            "interfaces": len(devices.findall("interface")),
            "filesystems": len(devices.findall("filesystem")),
            "agents": len(devices.findall("channel")) + len(devices.findall("redirdev")),
            "hostdev_count": len(hostdevs),
            "hostdev_approved": len(hostdevs) == 1 and
            hostdevs[0].get("type") == "usb" and
            hostdevs[0].find("source/vendor").get("id") == APPROVED_USB[0] and
            hostdevs[0].find("source/product").get("id") == APPROVED_USB[1] if hostdevs and
            hostdevs[0].find("source/vendor") is not None and
            hostdevs[0].find("source/product") is not None else False,
            "clipboard": not graphics or any(g.find("clipboard") is None or
                g.find("clipboard").get("copypaste") != "no" for g in graphics),
            "file_transfer": not graphics or any(g.find("filetransfer") is None or
                g.find("filetransfer").get("enable") != "no" for g in graphics),
            "remote_graphics": not graphics or any(g.get("type") != "spice" or
                g.get("listen") or g.get("port") not in (None, "-1") or
                g.get("autoport") == "yes" for g in graphics),
        })
    return summaries[0] if summaries[0] == summaries[1] else None


def collect_live(approved_if=None, approved_domain=None, adapter_path=None,
                 expected_qemu_user=None):
    if sys.platform != "linux":
        raise RuntimeError("live verification requires Linux")
    data = {"schema": 1, "ipv4_routes": routes("4"), "ipv6_routes": routes("6"),
            "ipv4_rules": rules("4"), "ipv6_rules": rules("6"),
            "external_addresses": addresses(approved_if),
            "wifi_associations": associations(approved_if), "dns_links": dns_links(approved_if),
            "nft": nft_state(approved_if), "libvirt": libvirt_state(approved_domain)}
    ipv4 = read("/proc/sys/net/ipv4/ip_forward")
    ipv6 = read("/proc/sys/net/ipv6/conf/all/forwarding")
    data["forwarding"] = {"ipv4": ipv4 == "1" if ipv4 in ("0", "1") else None,
                          "ipv6": ipv6 == "1" if ipv6 in ("0", "1") else None}
    bridges = json_command(["bridge", "-j", "link"])
    data["bridges"] = bridges if isinstance(bridges, list) else None
    data["unexpected_nics"] = link_inventory(approved_if)
    data["netns"] = namespace_inventory()
    processes = process_inventory(approved_domain, expected_qemu_user)
    data["qemu"] = processes[0] if processes is not None else None
    data["usb"] = usb_inventory(adapter_path, processes[1]) if processes is not None else None
    data["listeners"] = listener_inventory()
    ksm = read("/sys/kernel/mm/ksm/run")
    data["ksm"] = ksm == "1" if ksm in ("0", "1") else None
    iommu_groups = pathlib.Path("/sys/kernel/iommu_groups")
    dmesg = command(["dmesg"])
    data["iommu"] = (bool(list(iommu_groups.iterdir())) and bool(re.search(
        r"DMAR.*IOMMU.*enabled|IOMMU.*enabled", dmesg, re.I))
        if iommu_groups.is_dir() and dmesg is not None else None)
    nested = read("/sys/module/kvm_intel/parameters/nested")
    data["nested"] = nested.upper() in ("Y", "1") if nested and nested.upper() in (
        "Y", "N", "1", "0") else None
    data["guest_xml"] = guest_xml_summary(approved_domain)
    data["maintenance_authorized"] = None
    data["guest_internet_proven"] = False
    return data


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect", choices=("offline", "guest", "maintenance"), required=True)
    parser.add_argument("--fixture", type=pathlib.Path, help="synthetic observation JSON")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--approved-if", help="observed host MT7921U interface name")
    parser.add_argument("--approved-domain", help="approved work-domain libvirt name")
    parser.add_argument("--adapter-path", help="approved USB sysfs path, e.g. 4-1")
    parser.add_argument("--expected-qemu-user", help="distribution libvirt QEMU service account")
    args = parser.parse_args(argv)
    try:
        if args.fixture:
            data = json.loads(args.fixture.read_text(encoding="utf-8"))
        else:
            data = collect_live(args.approved_if, args.approved_domain, args.adapter_path,
                                args.expected_qemu_user)
        report = evaluate(data, args.expect, synthetic=bool(args.fixture))
    except (OSError, json.JSONDecodeError, ValueError, RuntimeError) as exc:
        print("verifier invocation/runtime error: " + str(exc), file=sys.stderr)
        return 3
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print("CONTROL DOMAIN ISOLATION: " + report["source"].upper() +
              " / " + args.expect.upper())
        for row in report["checks"]:
            print("[{}] {}: {}".format(row["status"], row["check"], row["reason"]))
        print("EXIT " + str(report["exit_code"]))
    return report["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
