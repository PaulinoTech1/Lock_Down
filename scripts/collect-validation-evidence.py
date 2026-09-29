#!/usr/bin/env python3
"""Collect bounded Lock_Down host evidence without performing physical tests."""

import argparse
import datetime
import gzip
import hashlib
import json
import os
import pathlib
import re
import socket
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
STATUS = {"PASS", "FAIL", "WARN", "UNKNOWN", "NOT_APPLICABLE", "MANUAL_TEST_REQUIRED"}
RELEASE = re.compile(r"^[A-Za-z0-9._+-]+$")
DEVICE = re.compile(r"^[A-Za-z0-9_.:+-]{1,64}$")
PCI = re.compile(r"^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$")
VERIFIER = re.compile(r"^\[(PASS|FAIL|WARN|UNKNOWN|NOT_APPLICABLE)\] ([a-z-]+):")
MANUAL = (
    ("internal-display", "Internal panel visibly renders correctly"),
    ("brightness-keys", "Brightness keys work"),
    ("trackpoint", "TrackPoint works"),
    ("touchpad", "Touchpad works"),
    ("keyboard", "Keyboard works"),
    ("speakers", "Speakers work"),
    ("microphone", "Microphone works"),
    ("wifi-traffic", "MT7921U associates and passes traffic"),
    ("usb-storage", "USB storage read/write/eject and reinsert/read work"),
    ("hdmi-display", "HDMI display works"),
    ("usb-c-displayport", "Direct USB-C DisplayPort works"),
    ("s2idle-resume", "s2idle suspend/resume works"),
    ("post-resume-wifi", "Wi-Fi works after resume"),
    ("real-kvm-guest", "Real KVM guest boots under the intended policy"),
    ("custom-fallback", "Previous custom fallback kernel boots"),
    ("distro-rescue", "Distro rescue kernel boots"),
    ("power-comparison", "Matched power comparison supports any power claim"),
)
REQUIRED = {
    "kernel-identity", "secure-boot-state", "kernel-lockdown", "cpu-count",
    "root-storage", "iommu", "wifi-driver", "kvm", "s2idle", "system-health",
}


class CollectionError(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def safe_name(value, limit=64):
    value = value.strip()[:limit]
    return value if DEVICE.fullmatch(value) else "UNKNOWN"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def cpu_set(value):
    result = set()
    for part in value.strip().split(","):
        if not re.fullmatch(r"\d+(?:-\d+)?", part):
            return None
        ends = [int(item) for item in part.split("-")]
        low, high = (ends[0], ends[0]) if len(ends) == 1 else ends
        if high < low or high > 4095:
            return None
        result.update(range(low, high + 1))
    return result


class Evidence:
    def __init__(self, root=None):
        self.offline = root is not None
        self.root = pathlib.Path(root).resolve(strict=True) if root else pathlib.Path("/")
        if not self.root.is_dir():
            raise CollectionError("evidence root is not a directory", 2)

    def path(self, relative):
        candidate = self.root / relative
        try:
            resolved = candidate.resolve(strict=False)
            resolved.relative_to(self.root)
        except (OSError, ValueError):
            return None
        return candidate

    def read_bytes(self, relative, limit=1024 * 1024):
        path = self.path(relative)
        if path is None or not path.is_file():
            return None
        try:
            with path.open("rb") as stream:
                data = stream.read(limit + 1)
            return data if len(data) <= limit else None
        except OSError:
            return None

    def read(self, relative, limit=1024 * 1024):
        data = self.read_bytes(relative, limit)
        return data.decode("utf-8", errors="replace") if data is not None else None

    def command(self, fixture_name, command, env=None, limit=65536, returncodes=(0,)):
        if self.offline:
            return self.read("commands/" + fixture_name, limit)
        try:
            process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     check=False, timeout=15, env=env)
            if process.returncode not in returncodes or len(process.stdout) > limit:
                return None
            return process.stdout.decode("utf-8", errors="replace")
        except (OSError, subprocess.TimeoutExpired):
            return None

    def entries(self, relative):
        directory = self.path(relative)
        if directory is None or not directory.is_dir():
            return None
        try:
            return sorted(directory.iterdir(), key=lambda item: item.name)[:128]
        except OSError:
            return None

    def exists(self, relative):
        path = self.path(relative)
        return path is not None and path.exists()


def add(checks, name, status, reason, evidence=None):
    if status not in STATUS:
        raise CollectionError("invalid internal status")
    item = {"check": name, "status": status, "reason": reason}
    if evidence is not None:
        item["evidence"] = evidence
    checks.append(item)


def private_output(path):
    path = pathlib.Path(path).absolute()
    if path.exists() or path.is_symlink():
        raise CollectionError("output already exists", 2)
    parent = path.parent
    if not parent.is_dir() or any(item.is_symlink() for item in (parent, *parent.parents)):
        raise CollectionError("unsafe output parent", 2)
    if os.name == "posix":
        stat = parent.stat()
        if stat.st_uid not in (os.geteuid(), 0) or (stat.st_mode & 0o022 and not
                (stat.st_uid == 0 and stat.st_mode & 0o1000)):
            raise CollectionError("unsafe output parent permissions", 2)
    path.mkdir(mode=0o700)
    return path


def write_private(path, text):
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        stream.write(text)


def cmdline_parameters(raw):
    allowed = {
        "intel_iommu": {"on", "off"}, "iommu": {"pt", "off", "force"},
        "lockdown": {"integrity", "confidentiality", "none"},
        "mem_sleep_default": {"s2idle", "deep"},
    }
    result = {}
    for word in raw.split():
        key, sep, value = word.partition("=")
        if sep and key in allowed:
            result[key] = value if value in allowed[key] else "PRESENT_REDACTED"
    return result


def read_json(text):
    if text is None:
        return None
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        return None


def nested_blocks(devices):
    for item in devices:
        if isinstance(item, dict):
            yield item
            yield from nested_blocks(item.get("children") or [])


def log_counts(raw):
    if raw is None:
        return None
    lines = raw.splitlines()[-500:]
    return {
        "dmar": sum(bool(re.search(r"\b(?:DMAR|IOMMU)\b", line, re.I)) for line in lines),
        "irq_remapping": sum(bool(re.search(r"IRQ remapping.*(?:enabled|on)", line, re.I)) for line in lines),
        "i915_firmware_errors": sum(bool(re.search(r"i915.*firmware.*(?:fail|error)|i915.*(?:fail|error).*firmware", line, re.I)) for line in lines),
        "wifi_firmware_errors": sum(bool(re.search(r"(?:mt7921|mt76|wifi).*firmware.*(?:fail|error)", line, re.I)) for line in lines),
        "kernel_errors": sum(bool(re.search(r"\b(?:failed|failure|error)\b", line, re.I)) for line in lines),
        "bounded_lines": len(lines),
    }


def collect(args):
    if not RELEASE.fullmatch(args.expected_kernel):
        raise CollectionError("invalid expected kernel release", 2)
    if args.evidence_root is None and not sys.platform.startswith("linux"):
        raise CollectionError("live collection requires Linux; use --evidence-root for offline fixtures", 2)
    evidence = Evidence(args.evidence_root)
    output = private_output(args.output)
    checks = []
    mode = "OFFLINE_FIXTURE" if evidence.offline else "LIVE_LINUX"

    observed_raw = (evidence.command("uname-r", ["uname", "-r"]) or "").strip()
    observed = observed_raw if RELEASE.fullmatch(observed_raw) else None
    add(checks, "kernel-identity", "UNKNOWN" if observed is None else
        "PASS" if observed == args.expected_kernel else "FAIL",
        "running release unavailable" if observed is None else
        "running release matches expected" if observed == args.expected_kernel else
        "running release differs from expected",
        {"observed_release": observed})

    config_data = None
    config_source = None
    if observed:
        compressed = evidence.read_bytes("proc/config.gz", limit=2 * 1024 * 1024)
        if compressed is not None:
            try:
                config_data = gzip.decompress(compressed)
                if len(config_data) > 4 * 1024 * 1024:
                    config_data = None
                else:
                    config_source = "proc/config.gz"
            except (OSError, ValueError):
                config_data = None
        if config_data is None:
            config_data = evidence.read_bytes("boot/config-" + observed, limit=4 * 1024 * 1024)
            config_source = "boot/config" if config_data is not None else None
    config_hash = sha256(config_data) if config_data is not None else None
    add(checks, "config-identity", "UNKNOWN" if config_data is None else
        "PASS" if config_source == "proc/config.gz" else "WARN",
        "running embedded config unavailable" if config_data is None else
        "running embedded config hashed" if config_source == "proc/config.gz" else
        "boot config hashed; running config not independently proven",
        {"sha256": config_hash, "source": config_source})
    config_text = config_data.decode("utf-8", errors="replace") if config_data is not None else ""

    cmdline = evidence.read("proc/cmdline", limit=16384)
    add(checks, "kernel-parameters", "PASS" if cmdline is not None else "UNKNOWN",
        "allowlisted parameters recorded" if cmdline is not None else "command line unreadable",
        {"parameters": cmdline_parameters(cmdline or "")})

    verifier_env = os.environ.copy()
    verifier_env["EXPECTED_KERNEL"] = args.expected_kernel
    verifier_output = evidence.command("secure-boot-results.txt",
        ["bash", str(ROOT / "scripts/verify-secure-boot.sh")], env=verifier_env,
        returncodes=(0, 1, 3))
    verifier_results = {}
    if verifier_output is not None:
        for line in verifier_output.splitlines():
            match = VERIFIER.match(line)
            if match and match.group(2) not in verifier_results:
                verifier_results[match.group(2)] = match.group(1)
    for name, key in (("secure-boot-state", "secure-boot-state"),
                      ("kernel-lockdown", "kernel-lockdown"),
                      ("verifier-kernel", "expected-kernel")):
        state = verifier_results.get(key, "UNKNOWN")
        add(checks, name, state, "existing Secure Boot verifier result" if state != "UNKNOWN"
            else "Secure Boot verifier evidence unavailable")
    module_state = verifier_results.get("module-policy", verifier_results.get("module-signatures", "UNKNOWN"))
    add(checks, "module-policy", module_state, "existing verifier module result" if module_state != "UNKNOWN"
        else "module policy evidence unavailable")

    online = evidence.read("sys/devices/system/cpu/online")
    present = evidence.read("sys/devices/system/cpu/present")
    online_set = cpu_set(online) if online is not None else None
    present_set = cpu_set(present) if present is not None else None
    count = len(online_set) if online_set is not None else None
    add(checks, "cpu-count", "UNKNOWN" if count is None else "PASS" if count == 12 else "FAIL",
        "online CPU list unavailable" if count is None else
        "12 logical CPUs online" if count == 12 else "online logical CPU count differs from target",
        {"online": count, "present": len(present_set) if present_set is not None else None})
    cpuinfo = evidence.read("proc/cpuinfo")
    model_match = re.search(r"^model name\s*:\s*([^\n]+)", cpuinfo or "", re.M)
    microcode_match = re.search(r"^microcode\s*:\s*(0x[0-9a-fA-F]+)", cpuinfo or "", re.M)
    model = re.sub(r"[^A-Za-z0-9 ._()+-]", "", model_match.group(1))[:120] if model_match else None
    add(checks, "cpu-details", "PASS" if model else "UNKNOWN",
        "CPU model and microcode inventory" if model else "CPU model unavailable",
        {"model": model, "microcode": microcode_match.group(1) if microcode_match else None})

    findmnt = read_json(evidence.command("findmnt.json", ["findmnt", "-J", "-o", "SOURCE,FSTYPE,TARGET", "/"]))
    lsblk = read_json(evidence.command("lsblk.json", ["lsblk", "-J", "-o", "NAME,TYPE,FSTYPE,PKNAME"]))
    filesystems = findmnt.get("filesystems", []) if isinstance(findmnt, dict) else []
    root = next((item for item in filesystems if item.get("target") == "/"), None)
    blocks = list(nested_blocks(lsblk.get("blockdevices", []))) if isinstance(lsblk, dict) else []
    mapper = bool(root and str(root.get("source", "")).startswith("/dev/mapper/"))
    luks = any(item.get("fstype") == "crypto_LUKS" or item.get("type") == "crypt" for item in blocks)
    nvme = any(str(item.get("name", "")).startswith("nvme") and item.get("type") == "disk" for item in blocks)
    storage_known = root is not None and lsblk is not None
    storage_ok = mapper and luks and nvme
    add(checks, "root-storage", "UNKNOWN" if not storage_known else "PASS" if storage_ok else "FAIL",
        "root or block topology unavailable" if not storage_known else
        "mapper-backed root, LUKS and NVMe topology observed" if storage_ok else
        "expected root mapper, LUKS or NVMe topology missing",
        {"fstype": safe_name(str(root.get("fstype", ""))) if root else None,
         "mapper_root": mapper, "luks_present": luks, "nvme_present": nvme})

    log_text = evidence.command("kernel-log.txt",
        ["journalctl", "-k", "-b", "-n", "500", "--no-pager", "--output=cat"], limit=512 * 1024)
    logs = log_counts(log_text)
    groups = evidence.entries("sys/kernel/iommu_groups")
    group_count = len([item for item in groups if item.is_dir()]) if groups is not None else None
    iommu_evidence = bool(logs and logs["dmar"] and logs["irq_remapping"])
    add(checks, "iommu", "UNKNOWN" if groups is None or logs is None else
        "FAIL" if group_count == 0 else "PASS" if iommu_evidence else "WARN",
        "IOMMU groups or bounded kernel log unavailable" if groups is None or logs is None else
        "IOMMU groups absent" if group_count == 0 else
        "groups, DMAR and IRQ remapping evidence present" if iommu_evidence else
        "groups present; bounded log lacks DMAR or IRQ remapping evidence",
        {"group_count": group_count, "dmar_lines": logs["dmar"] if logs else None,
         "irq_remapping_lines": logs["irq_remapping"] if logs else None})

    i915_entries = evidence.entries("sys/bus/pci/drivers/i915")
    if evidence.offline:
        binding_fixture = evidence.read("sys/bus/pci/drivers/i915/bound-devices.txt", limit=4096)
        bound = (sum(bool(PCI.fullmatch(line.strip())) for line in binding_fixture.splitlines())
                 if binding_fixture is not None else None)
    else:
        bound = sum(bool(PCI.fullmatch(item.name)) for item in i915_entries) if i915_entries is not None else None
    add(checks, "graphics-driver", "UNKNOWN" if bound is None else "PASS" if bound else "FAIL",
        "i915 binding unreadable" if bound is None else "i915 PCI binding observed" if bound else "i915 PCI binding absent",
        {"bound_devices": bound})
    drm_entries = evidence.entries("sys/class/drm") or []
    connectors = []
    for item in drm_entries:
        if len(connectors) >= 32:
            break
        if re.fullmatch(r"card\d+-.+", item.name):
            status = evidence.read(f"sys/class/drm/{item.name}/status", limit=64)
            if status and status.strip() in {"connected", "disconnected", "unknown"}:
                connectors.append({"connector": safe_name(item.name), "state": status.strip()})
    add(checks, "drm-connectors", "PASS" if connectors else "UNKNOWN",
        "connector enumeration only; physical output needs a manual test" if connectors else "DRM connectors unavailable",
        {"connectors": connectors})
    add(checks, "graphics-firmware", "UNKNOWN" if logs is None else
        "FAIL" if logs["i915_firmware_errors"] else "PASS",
        "bounded kernel log unavailable" if logs is None else
        "i915 firmware error detected" if logs["i915_firmware_errors"] else
        "no i915 firmware error in bounded log window",
        {"error_count": logs["i915_firmware_errors"] if logs else None})
    runtime_pm = evidence.read("sys/bus/pci/drivers/i915/0000-runtime-pm", limit=64) if evidence.offline else None
    if not evidence.offline and i915_entries:
        for item in i915_entries:
            if PCI.fullmatch(item.name):
                runtime_pm = evidence.read(f"sys/bus/pci/drivers/i915/{item.name}/power/runtime_status", limit=64)
                break
    runtime_state = runtime_pm.strip() if runtime_pm else None
    add(checks, "graphics-runtime-pm", "UNKNOWN" if runtime_state is None else "PASS",
        "i915 runtime power state unavailable" if runtime_state is None else "i915 runtime power state recorded; no power claim",
        {"state": runtime_state if runtime_state in {"active", "suspended", "suspending", "resuming", "unsupported"} else "UNKNOWN"})

    usb_entries = evidence.entries("sys/bus/usb/devices")
    usb = []
    for item in usb_entries or []:
        if len(usb) >= 64:
            break
        relative = f"sys/bus/usb/devices/{item.name}"
        vid = (evidence.read(relative + "/idVendor", limit=16) or "").strip().lower()
        pid = (evidence.read(relative + "/idProduct", limit=16) or "").strip().lower()
        if not re.fullmatch(r"[0-9a-f]{4}", vid) or not re.fullmatch(r"[0-9a-f]{4}", pid):
            continue
        driver_text = (evidence.read(relative + "/driver_name", limit=64) or "").strip()
        driver_path = evidence.path(relative + "/driver")
        driver = safe_name(driver_text or (driver_path.resolve().name if driver_path and driver_path.is_symlink() else ""))
        if not evidence.offline and driver == "UNKNOWN":
            # USB drivers commonly bind an interface (1-1:1.0), not its parent device (1-1).
            for interface in usb_entries:
                if interface.name.startswith(item.name + ":"):
                    link = evidence.path(f"sys/bus/usb/devices/{interface.name}/driver")
                    if link and link.is_symlink():
                        driver = safe_name(link.resolve().name)
                        break
        bus = (evidence.read(relative + "/busnum", limit=16) or "").strip()
        port = (evidence.read(relative + "/devpath", limit=32) or "").strip()
        usb.append({"vid_pid": f"{vid}:{pid}", "driver": driver,
                    "bus": bus if re.fullmatch(r"\d{1,3}", bus) else None,
                    "port": port if re.fullmatch(r"[0-9.]{1,16}", port) else None})
    wifi = [item for item in usb if item["vid_pid"] == "0e8d:7961"]
    wifi_bound = any(item["driver"] == "mt7921u" for item in wifi)
    add(checks, "wifi-driver", "UNKNOWN" if usb_entries is None else "PASS" if wifi_bound else "FAIL",
        "USB inventory unavailable" if usb_entries is None else
        "MT7921U USB adapter bound" if wifi_bound else "MT7921U adapter or driver binding absent",
        {"adapter_count": len(wifi), "bound": wifi_bound})
    add(checks, "usb-topology", "PASS" if usb else "UNKNOWN",
        "VID:PID, bus/port and driver inventory only" if usb else "USB topology unreadable",
        {"devices": usb})
    add(checks, "wifi-firmware", "UNKNOWN" if logs is None else
        "FAIL" if logs["wifi_firmware_errors"] else "PASS",
        "bounded kernel log unavailable" if logs is None else
        "Wi-Fi firmware error detected" if logs["wifi_firmware_errors"] else
        "no Wi-Fi firmware error in bounded log window",
        {"error_count": logs["wifi_firmware_errors"] if logs else None})
    net_entries = evidence.entries("sys/class/net")
    wifi_states = []
    if net_entries is not None:
        for item in net_entries:
            if len(wifi_states) >= 16:
                break
            if re.fullmatch(r"(?:wl\w{1,30}|wlan\d{1,3})", item.name):
                state = evidence.read(f"sys/class/net/{item.name}/operstate", limit=64)
                wifi_states.append(state.strip() if state and state.strip() in {"up", "down", "dormant", "unknown"} else "UNKNOWN")
    add(checks, "wifi-interface", "UNKNOWN" if net_entries is None else "PASS" if wifi_states else "WARN",
        "network interface inventory unavailable" if net_entries is None else
        "wireless interface state recorded; no connectivity claim" if wifi_states else "no wireless interface enumerated",
        {"interface_count": len(wifi_states), "states": wifi_states})

    kvm = evidence.exists("dev/kvm")
    kvm_config = "CONFIG_KVM_INTEL=y" in config_text.splitlines()
    vhost = evidence.exists("dev/vhost-net")
    tun = evidence.exists("dev/net/tun")
    add(checks, "kvm", "UNKNOWN" if config_data is None else "PASS" if kvm and kvm_config else "FAIL",
        "kernel config unavailable" if config_data is None else
        "KVM device and config present; no VM was launched" if kvm and kvm_config else
        "KVM device or config missing",
        {"dev_kvm": kvm, "config_kvm_intel": kvm_config, "vhost_net": vhost, "tun": tun})
    add(checks, "kvm-network-prerequisites", "PASS" if vhost and tun else "WARN",
        "vhost-net and TUN present" if vhost and tun else "vhost-net or TUN absent; guest workflow untested")
    guests = evidence.command("virsh-guests.txt", ["virsh", "list", "--all", "--name"], limit=32768)
    guest_count = len([line for line in guests.splitlines() if line.strip()]) if guests is not None else None
    add(checks, "libvirt-inventory", "UNKNOWN" if guest_count is None else "PASS",
        "libvirt inventory unavailable" if guest_count is None else "defined guests counted; none launched",
        {"defined_guest_count": guest_count})

    cards = evidence.read("proc/asound/cards")
    audio_count = len(re.findall(r"^\s*\d+\s+\[", cards or "", re.M)) if cards is not None else None
    add(checks, "audio-enumeration", "UNKNOWN" if cards is None else "PASS" if audio_count else "WARN",
        "ALSA card data unavailable" if cards is None else
        "ALSA card enumerated; playback and capture need manual tests" if audio_count else
        "no ALSA card enumerated", {"card_count": audio_count})
    inputs = evidence.read("proc/bus/input/devices")
    input_classes = {
        "keyboard": bool(re.search(r"Name=.*keyboard", inputs or "", re.I)),
        "touchpad": bool(re.search(r"Name=.*touchpad", inputs or "", re.I)),
        "trackpoint": bool(re.search(r"Name=.*trackpoint", inputs or "", re.I)),
    }
    add(checks, "input-enumeration", "UNKNOWN" if inputs is None else
        "PASS" if all(input_classes.values()) else "WARN",
        "input inventory unavailable" if inputs is None else
        "input classes enumerated; function needs manual tests" if all(input_classes.values()) else
        "one or more input classes not enumerated", {"classes": input_classes})

    modes = evidence.read("sys/power/mem_sleep", limit=128)
    selected = re.search(r"\[([^]]+)\]", modes or "")
    selected_mode = selected.group(1) if selected else None
    supported = re.findall(r"\b(?:s2idle|deep|shallow)\b", modes or "")
    add(checks, "s2idle", "UNKNOWN" if selected_mode is None else
        "PASS" if selected_mode == "s2idle" else "FAIL",
        "mem_sleep unreadable or unparseable" if selected_mode is None else
        "s2idle selected; no suspend was triggered" if selected_mode == "s2idle" else
        "selected suspend mode is not s2idle",
        {"selected": selected_mode, "supported": sorted(set(supported))})
    wakeups = evidence.read("sys/kernel/debug/wakeup_sources", limit=256 * 1024)
    add(checks, "wakeup-sources", "UNKNOWN" if wakeups is None else "PASS",
        "wakeup source inventory unavailable" if wakeups is None else
        "wakeup source count recorded; no suspend inference",
        {"count": max(0, len(wakeups.splitlines()) - 1) if wakeups is not None else None})

    failed_units = evidence.command("systemctl-failed.txt",
        ["systemctl", "--failed", "--no-legend", "--no-pager", "--plain"], limit=32768)
    unit_count = len([line for line in failed_units.splitlines() if line.strip()]) if failed_units is not None else None
    add(checks, "system-health", "UNKNOWN" if unit_count is None else
        "PASS" if unit_count == 0 else "FAIL",
        "failed unit list unavailable" if unit_count is None else
        "zero failed units" if unit_count == 0 else "failed system units present",
        {"failed_unit_count": unit_count})
    add(checks, "kernel-errors", "UNKNOWN" if logs is None else
        "WARN" if logs["kernel_errors"] else "PASS",
        "bounded kernel log unavailable" if logs is None else
        "kernel error keywords in bounded log window; review on host" if logs["kernel_errors"] else
        "no error keywords in bounded log window",
        {"error_count": logs["kernel_errors"] if logs else None,
         "bounded_lines": logs["bounded_lines"] if logs else None})

    for name, label in MANUAL:
        add(checks, name, "MANUAL_TEST_REQUIRED", label)

    try:
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=False, timeout=5).stdout.decode().strip()
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            commit = "UNKNOWN"
    except (OSError, subprocess.TimeoutExpired):
        commit = "UNKNOWN"
    hostname = (evidence.read("commands/hostname", limit=256) if evidence.offline
                else socket.gethostname()) if args.include_host_hash else None
    manifest = {
        "git_commit": commit, "kernel_release": observed, "kernel_config_sha256": config_hash,
        "collector_sha256": sha256(pathlib.Path(__file__).read_bytes()),
        "collected_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "hostname_sha256": sha256(hostname.strip().encode()) if hostname else None,
        "evidence_mode": mode,
    }
    counts = {status: sum(row["status"] == status for row in checks) for status in sorted(STATUS)}
    report = {
        "schema": "lockdown.validation.v1", "mode": mode,
        "expected_kernel": args.expected_kernel, "observed_kernel": observed,
        "checks": checks, "manual_checklist": [label for _, label in MANUAL],
        "manifest": manifest, "summary": {"counts": counts, "validated": False},
    }
    markdown = ["# ThinkPad validation evidence", "",
                f"Mode: **{mode}**. Expected release: `{args.expected_kernel}`.",
                "This bundle does not declare the kernel validated.", "",
                "## Collected checks", "", "| Check | Status | Meaning |", "| --- | --- | --- |"]
    for row in checks:
        if row["status"] != "MANUAL_TEST_REQUIRED":
            markdown.append(f"| {row['check']} | {row['status']} | {row['reason']} |")
    markdown += ["", "## Physical owner checklist", ""]
    markdown += [f"- [ ] {label}" for _, label in MANUAL]
    markdown += ["", "Record dates, kernel release, observations and recovery outcome separately. Do not check boxes based on device enumeration.", ""]
    write_private(output / "validation.json", json.dumps(report, indent=2, sort_keys=True) + "\n")
    write_private(output / "validation.md", "\n".join(markdown))
    print(f"{mode} evidence: {output / 'validation.json'}")
    if any(row["status"] == "FAIL" for row in checks):
        return 1
    if any(row["check"] in REQUIRED and row["status"] == "UNKNOWN" for row in checks):
        return 3
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-kernel", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--evidence-root")
    parser.add_argument("--include-host-hash", action="store_true")
    args = parser.parse_args()
    try:
        return collect(args)
    except (CollectionError, OSError, ValueError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return error.code if isinstance(error, CollectionError) else 1


if __name__ == "__main__":
    sys.exit(main())
