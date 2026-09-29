#!/usr/bin/env python3
"""Resolve a human-proposed Kconfig delta against authenticated Linux source.

This produces review evidence, never a build or an approved candidate config.
"""

import argparse
import difflib
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SYMBOL = re.compile(r"^CONFIG_[A-Z0-9_]+$")
ASSIGNMENT = re.compile(r"^(CONFIG_[A-Z0-9_]+)=(.*)$")
DISABLED = re.compile(r"^# (CONFIG_[A-Z0-9_]+) is not set$")
VALUE = re.compile(r'^(?:[ymn]|[0-9]+|0x[0-9a-fA-F]+|"[A-Za-z0-9_ ./,+:@-]*")$')
MAKE_ENV_REMOVE = (
    "MAKEFLAGS", "MFLAGS", "GNUMAKEFLAGS", "MAKEFILES", "KBUILD_OUTPUT",
    "KBUILD_SRC", "KBUILD_KCONFIG", "KCONFIG_CONFIG", "KCONFIG_ALLCONFIG",
    "KERNELRELEASE", "LOCALVERSION", "ARCH", "CROSS_COMPILE", "CC", "HOSTCC",
    "LD", "AR", "NM", "OBJCOPY", "STRIP",
)


class AnalysisError(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def config_value(line):
    match = ASSIGNMENT.fullmatch(line)
    if match:
        return match.group(1), match.group(2)
    match = DISABLED.fullmatch(line)
    if match:
        return match.group(1), "n"
    return None


def parse_config(path):
    values = {}
    for number, line in enumerate(pathlib.Path(path).read_text(encoding="utf-8").splitlines(), 1):
        item = config_value(line)
        if item:
            if item[0] in values:
                raise AnalysisError(f"duplicate config symbol {item[0]} at line {number}")
            values[item[0]] = item[1]
    return values


def parse_proposal(path):
    values = {}
    for number, line in enumerate(pathlib.Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("##"):
            continue
        item = config_value(line)
        if not item or not SYMBOL.fullmatch(item[0]) or not VALUE.fullmatch(item[1]):
            raise AnalysisError(f"invalid proposal line {number}")
        if item[0] in values:
            raise AnalysisError(f"duplicate proposal symbol {item[0]} at line {number}")
        values[item[0]] = item[1]
    if not values:
        raise AnalysisError("proposal has no assignments")
    return values


def canonical(symbol, value):
    return f"# {symbol} is not set" if value == "n" else f"{symbol}={value}"


def apply_proposal(baseline, destination, proposal):
    lines = pathlib.Path(baseline).read_text(encoding="utf-8").splitlines()
    seen = set()
    output = []
    for line in lines:
        item = config_value(line)
        if item and item[0] in proposal:
            output.append(canonical(item[0], proposal[item[0]]))
            seen.add(item[0])
        else:
            output.append(line)
    output.extend(canonical(symbol, proposal[symbol]) for symbol in proposal if symbol not in seen)
    pathlib.Path(destination).write_text("\n".join(output) + "\n", encoding="utf-8", newline="\n")


def require_version(actual, expected):
    if actual != expected:
        raise AnalysisError(f"kernel version mismatch: source={actual!r}, expected={expected!r}")


def required_symbols(path):
    required = {}
    tier = "required"
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line == "[required]":
            tier = "required"
        elif line == "[warn]":
            tier = "warn"
        elif tier == "required" and line.startswith("CONFIG_") and "=" in line:
            symbol, value = line.split("=", 1)
            required[symbol] = value
    return required


def source_index(source, symbols):
    """Collect direct source clauses; never interpret them as resolved semantics."""
    definitions = {}
    for path in pathlib.Path(source).rglob("Kconfig*"):
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 1024 * 1024:
            continue
        relative = path.relative_to(source).as_posix()
        current = None
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            declaration = re.match(r"^\s*(?:menuconfig|config)\s+([A-Z0-9_]+)\s*$", line)
            if declaration:
                current = "CONFIG_" + declaration.group(1)
                definitions.setdefault(current, []).append({
                    "file": relative, "line": number, "direct_dependencies": [],
                    "select": [], "imply": [], "type": "UNKNOWN", "has_prompt": False,
                })
                continue
            if not current or not line[:1].isspace():
                if line and not line[:1].isspace():
                    current = None
                continue
            entry = definitions[current][-1]
            clause = line.strip()
            if clause.startswith("depends on "):
                entry["direct_dependencies"].append(clause[11:])
            elif clause.startswith("select "):
                entry["select"].append(clause[7:])
            elif clause.startswith("imply "):
                entry["imply"].append(clause[6:])
            elif re.match(r"^(?:bool|tristate|string|int|hex)(?:\s|$)", clause):
                entry["type"] = clause.split()[0]
                entry["has_prompt"] = '"' in clause
            elif clause.startswith("prompt "):
                entry["has_prompt"] = True
    result = {}
    for symbol in symbols:
        own = definitions.get(symbol, [])
        raw = [dep for item in own for dep in item["direct_dependencies"]]
        selected_by = sorted(name for name, items in definitions.items()
                             if any(re.match(rf"^{re.escape(symbol[7:])}(?:\s|$)", clause)
                                    for item in items for clause in item["select"]))
        implied_by = sorted(name for name, items in definitions.items()
                            if any(re.match(rf"^{re.escape(symbol[7:])}(?:\s|$)", clause)
                                   for item in items for clause in item["imply"]))
        reverse = sorted(name for name, items in definitions.items() if name != symbol
                         and any(re.search(rf"\b{re.escape(symbol[7:])}\b", clause)
                                 for item in items for clause in item["direct_dependencies"]))
        result[symbol] = {
            "definitions": own, "direct_dependencies": raw,
            "reverse_dependencies": reverse, "selected_by": selected_by,
            "implied_by": implied_by, "hidden_symbol": (
                all(not item["has_prompt"] for item in own) if own else "UNKNOWN"),
            "menu_nesting": "UNKNOWN", "architecture_restriction": "UNKNOWN",
            "dependency_metadata_confidence": "CONFIRMED_SOURCE_TEXT_NOT_RESOLVED_CONTEXT" if own else "UNKNOWN",
        }
    return result


def classify_changes(baseline, proposal, resolved, required, metadata=None):
    metadata = metadata or {}
    requested = []
    direct = []
    rejected = []
    collateral = []
    for symbol in sorted(set(baseline) | set(proposal) | set(resolved)):
        old = baseline.get(symbol, "absent")
        new = resolved.get(symbol, "absent")
        requested_value = proposal.get(symbol)
        if requested_value is None and old == new:
            continue
        if requested_value is not None:
            status = ("REJECTED_BY_KCONFIG" if requested_value != new else
                      "UNCHANGED_REQUEST" if old == new else "ACCEPTED")
        else:
            status = "COLLATERAL_CHANGE"
        meta = metadata.get(symbol, {})
        row = {
            "symbol": symbol, "baseline_value": old, "requested_value": requested_value,
            "resolved_value": new, "status": status,
            "subsystem": (meta.get("definitions") or [{}])[0].get("file", "UNKNOWN"),
            "direct_dependencies": meta.get("direct_dependencies", []),
            "reverse_dependencies": meta.get("reverse_dependencies", []),
            "selected_by": meta.get("selected_by", []),
            "implied_by": meta.get("implied_by", []),
            "kconfig_metadata": meta,
            "required_symbol": symbol in required,
            "hardware_relevance": "UNKNOWN", "security_relevance": "UNKNOWN",
            "validation_requirement": "HUMAN_REVIEW",
        }
        if requested_value is not None:
            requested.append(row)
            if old != new:
                direct.append(row)
            if status == "REJECTED_BY_KCONFIG":
                rejected.append(row)
        else:
            collateral.append(row)
    required_results = [{
        "symbol": symbol, "expected": expected, "resolved": resolved.get(symbol, "absent"),
        "status": "PASS" if resolved.get(symbol, "absent") == expected else "FAIL",
    } for symbol, expected in sorted(required.items())]
    return {
        "requested_changes": requested, "direct_resolved_changes": direct,
        "collateral_changes": collateral, "rejected_requests": rejected,
        "required_symbol_results": required_results,
        "failed": bool(rejected or any(row["status"] == "FAIL" for row in required_results)),
    }


def safe_output(path):
    path = pathlib.Path(path).absolute()
    if path.exists() or path.is_symlink():
        raise AnalysisError("output already exists")
    parent = path.parent
    if not parent.is_dir() or any(part.is_symlink() for part in (parent, *parent.parents)):
        raise AnalysisError("output parent missing or contains a symlink")
    if os.name == "posix":
        stat = parent.stat()
        if stat.st_uid not in (os.geteuid(), 0) or (stat.st_mode & 0o022 and not
                (stat.st_uid == 0 and stat.st_mode & 0o1000)):
            raise AnalysisError("unsafe output parent")
    path.mkdir(mode=0o700)
    return path


def run(command, env=None, limit=16000):
    try:
        result = subprocess.run(command, check=False, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, env=env, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AnalysisError(f"required tool unavailable or timed out: {command[0]}", 3) from error
    return {"command": [str(part) for part in command], "exit_code": result.returncode,
            "output": result.stdout[:limit], "output_truncated": len(result.stdout) > limit}


def make(source, output, target):
    env = os.environ.copy()
    for name in MAKE_ENV_REMOVE:
        env.pop(name, None)
    env["LC_ALL"] = "C"
    result = run(["make", "-s", "--no-print-directory", "-C", str(source),
                  f"O={output}", target], env=env)
    if result["exit_code"]:
        raise AnalysisError(f"make {target} failed: {result['output'][-1000:]}")
    return result["output"].strip()


def report_markdown(report):
    lines = ["# Kconfig delta evidence", "", f"Status: **{report['status']}**.",
             "Human review is required before any build or promotion.", "",
             f"Kernel source: `{report['kernel_version']}`; resolved release: `{report['kernel_release']}`.",
             f"Requested: {len(report['requested_changes'])}; collateral: {len(report['collateral_changes'])}; "
             f"rejected: {len(report['rejected_requests'])}.", "",
             "| Symbol | Baseline | Requested | Resolved | Classification |", "| --- | --- | --- | --- | --- |"]
    for row in report["requested_changes"] + report["collateral_changes"]:
        lines.append(f"| {row['symbol']} | {row['baseline_value']} | {row['requested_value'] or '-'} | "
                     f"{row['resolved_value']} | {row['status']} |")
    lines += ["", "## Policy gates", ""]
    for gate in report["policy_gate_results"]:
        lines.append(f"- {gate['name']}: exit {gate['exit_code']}")
    lines += ["", "## Confidence and limits", ""]
    lines += [f"- {note}" for note in report["confidence_notes"]]
    lines += ["", "## Complete resolved config diff", "", "```diff", report["full_diff"], "```", ""]
    if report["errors"]:
        lines += ["## Errors", ""] + [f"- {error}" for error in report["errors"]]
    return "\n".join(lines)


def write_report(output, report):
    for name, content in (("report.json", json.dumps(report, indent=2, sort_keys=True) + "\n"),
                          ("report.md", report_markdown(report))):
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(output / name, flags, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)


def analyze(args):
    baseline_path = pathlib.Path(args.baseline).resolve(strict=True)
    proposal_path = pathlib.Path(args.proposal).resolve(strict=True)
    if not baseline_path.is_file() or not proposal_path.is_file():
        raise AnalysisError("baseline and proposal must be regular files")
    before_hash = sha256(baseline_path)
    baseline = parse_config(baseline_path)
    proposal = parse_proposal(proposal_path)
    localversion = baseline.get("CONFIG_LOCALVERSION", "").strip('"')
    if not re.fullmatch(r"-[A-Za-z0-9._+-]+", localversion):
        raise AnalysisError("baseline LOCALVERSION is absent or invalid")
    output = safe_output(args.output)
    report = {
        "schema": "lockdown.kconfig-analysis.v1", "status": "UNKNOWN", "review_required": True,
        "baseline": {"filename": baseline_path.name, "sha256": before_hash},
        "proposal": {"sha256": sha256(proposal_path), "assignments": proposal},
        "resolved": {}, "requested_changes": [], "direct_resolved_changes": [],
        "collateral_changes": [], "rejected_requests": [], "required_symbol_results": [],
        "policy_gate_results": [], "kernel_version": args.version, "kernel_release": "UNKNOWN",
        "source_identity": {"archive_sha256": args.sha256.lower(), "signer_fingerprint": args.fingerprint.upper(),
                            "status": "UNKNOWN"},
        "confidence_notes": [
            "Kbuild resolves effective values; Kconfig source-clause indexing is context-incomplete.",
            "Hardware and security relevance require human evidence; no automatic recommendation is made.",
            "No build, boot, physical validation, or candidate promotion occurred.",
        ],
        "full_diff": "", "errors": [],
    }
    exit_code = 3
    try:
        with tempfile.TemporaryDirectory(prefix="lockdown-kconfig-", dir=output.parent) as scratch_name:
            scratch = pathlib.Path(scratch_name)
            source = scratch / f"linux-{args.version}"
            verifier = run([
                os.environ.get("BASH", "bash"), str(ROOT / "scripts/verify-kernel-source.sh"),
                "--version", args.version, "--localversion", localversion,
                "--archive", str(pathlib.Path(args.archive).resolve(strict=True)),
                "--sha256", args.sha256, "--signature", str(pathlib.Path(args.signature).resolve(strict=True)),
                "--keyring", str(pathlib.Path(args.keyring).resolve(strict=True)),
                "--fingerprint", args.fingerprint, "--source-dir", str(source),
                "--config", str(baseline_path),
            ])
            if verifier["exit_code"]:
                raise AnalysisError(f"source authentication failed: {verifier['output'][-1000:]}",
                                    3 if verifier["exit_code"] == 3 else 1)
            report["source_identity"]["status"] = "AUTHENTICATED_FRESH_EXTRACTION"
            original = scratch / "baseline"
            candidate = scratch / "proposal"
            original.mkdir()
            candidate.mkdir()
            shutil.copyfile(baseline_path, original / ".config")
            apply_proposal(baseline_path, candidate / ".config", proposal)
            make(source, original, "olddefconfig")
            resolved_baseline = parse_config(original / ".config")
            if resolved_baseline != baseline:
                raise AnalysisError("BASELINE_DRIFT: supplied config is not effective in this source")
            baseline_release = make(source, original, "kernelrelease")
            require_version(baseline_release, args.version + localversion)
            make(source, candidate, "olddefconfig")
            resolved = parse_config(candidate / ".config")
            release = make(source, candidate, "kernelrelease")
            if not release.startswith(args.version + "-"):
                raise AnalysisError("resolved kernelrelease does not match source version")
            if sha256(baseline_path) != before_hash:
                raise AnalysisError("baseline changed during analysis")
            report["kernel_release"] = release
            report["baseline"]["resolved_sha256"] = sha256(original / ".config")
            report["resolved"] = {"config_sha256": sha256(candidate / ".config"),
                                  "symbol_count": len(resolved)}
            requirements = required_symbols(ROOT / "config/required-symbols.txt")
            affected = set(baseline) ^ set(resolved)
            affected.update(name for name in set(baseline) & set(resolved)
                            if baseline[name] != resolved[name])
            affected.update(proposal)
            metadata = source_index(source, affected)
            changes = classify_changes(baseline, proposal, resolved, requirements, metadata)
            for key in ("requested_changes", "direct_resolved_changes", "collateral_changes",
                        "rejected_requests", "required_symbol_results"):
                report[key] = changes[key]
            report["full_diff"] = "\n".join(difflib.unified_diff(
                (original / ".config").read_text(encoding="utf-8").splitlines(),
                (candidate / ".config").read_text(encoding="utf-8").splitlines(),
                fromfile="baseline-resolved", tofile="proposal-resolved", lineterm=""))
            gates = [
                ("preflight-check", ["bash", str(ROOT / "scripts/preflight-check.sh"), str(candidate / ".config")]),
                ("preflight-security", ["bash", str(ROOT / "scripts/preflight-security.sh"), str(candidate / ".config")]),
                ("validate-boot-critical", ["bash", str(ROOT / "lock-down-kernel/scripts/validate-boot-critical.sh"), str(candidate / ".config")]),
                ("audit-config", ["bash", str(ROOT / "lock-down-kernel/scripts/audit-config.sh"),
                                  "--project-root", str(ROOT), "--config", str(candidate / ".config")]),
            ]
            gates += [(name, ["bash", str(ROOT / f"tests/test-{name}-config.sh"), str(candidate / ".config")])
                      for name in ("audit8-media", "audit9-device", "audit10-usb")]
            for name, command in gates:
                gate = run(command, limit=4000)
                report["policy_gate_results"].append({"name": name, "exit_code": gate["exit_code"],
                                                      "output": gate["output"],
                                                      "output_truncated": gate["output_truncated"]})
            report["status"] = ("FAIL" if changes["failed"] or
                                any(item["exit_code"] for item in report["policy_gate_results"])
                                else "COMPLETE")
            exit_code = 1 if report["status"] == "FAIL" else 0
    except (AnalysisError, OSError, UnicodeError, ValueError) as error:
        report["status"] = "UNKNOWN" if isinstance(error, AnalysisError) and error.code == 3 else "FAIL"
        report["errors"].append(str(error))
        exit_code = error.code if isinstance(error, AnalysisError) else 1
    write_report(output, report)
    print(f"{report['status']} Kconfig analysis: {output / 'report.json'}")
    return exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("version", "archive", "sha256", "signature", "keyring", "fingerprint",
                 "baseline", "proposal", "output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("--version must be an exact numeric point release")
    if not re.fullmatch(r"[a-fA-F0-9]{64}", args.sha256):
        parser.error("--sha256 must contain 64 hex characters")
    try:
        return analyze(args)
    except (AnalysisError, OSError, UnicodeError, ValueError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return error.code if isinstance(error, AnalysisError) else 1


if __name__ == "__main__":
    sys.exit(main())
