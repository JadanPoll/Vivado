#!/usr/bin/env python3
"""One human entry point for Frontier Grade evidence and next experiments.

The JSON ledger is deliberately small and declarative. This program supplies
the repetitive machine view; stdout supplies the resumable human view.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEDGER_PATH = Path(__file__).with_name("knowledge.json")


def load_ledger():
    data = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
    if data.get("schema") != 1:
        raise ValueError(f"UNSUPPORTED_SCHEMA:{data.get('schema')!r}")
    required = ("mission", "goals", "specimens", "claims", "experiments")
    missing = [key for key in required if key not in data]
    if missing:
        raise ValueError("LEDGER_MISSING:" + ",".join(missing))
    return data


def select_specimens(ledger, where):
    selected = []
    for name, specimen in ledger["specimens"].items():
        params = specimen.get("params", {})
        if all(params.get(key) == value for key, value in where.items()):
            selected.append((name, specimen))
    return selected


def specimen_dir(ledger, name):
    return ROOT / ledger["specimen_root"] / name


def archive_path(ledger):
    value = ledger.get("evidence_archive")
    return ROOT / value if value else None


def archived_member(ledger, name, filename):
    path = archive_path(ledger)
    if path is None or not path.is_file():
        return None
    member = f"output/{name}/{filename}"
    with zipfile.ZipFile(path) as archive:
        try:
            return archive.read(member)
        except KeyError:
            return None


def evidence_exists(ledger, name, filename):
    if (specimen_dir(ledger, name) / filename).is_file():
        return True
    if archived_member(ledger, name, filename) is not None:
        return True
    snapshot = ledger["specimens"][name].get("snapshot", {})
    return filename in snapshot.get("files", [])


def evidence_text(ledger, name, filename):
    path = specimen_dir(ledger, name) / filename
    if path.is_file():
        return path.read_text(encoding="utf-8", errors="replace")
    archived = archived_member(ledger, name, filename)
    if archived is not None:
        return archived.decode("utf-8", errors="replace")
    snapshot = ledger["specimens"][name].get("snapshot", {})
    if filename == "drc.txt" and "drc_markers" in snapshot:
        return "\n".join(snapshot["drc_markers"])
    if filename == "cells.tsv" and "cell_ref_counts" in snapshot:
        rows = ["cell\tref\tloc\tbel"]
        for ref, count in snapshot["cell_ref_counts"].items():
            rows.extend(f"snapshot_{ref}_{index}\t{ref}\tSNAPSHOT\tSNAPSHOT" for index in range(count))
        return "\n".join(rows)
    return None


def summary_statuses(ledger):
    root = ROOT / ledger["specimen_root"]
    paths = sorted(root.glob("summary*.tsv"))
    statuses = {
        name: specimen.get("snapshot", {}).get("status")
        for name, specimen in ledger["specimens"].items()
        if specimen.get("snapshot", {}).get("status")
    }
    for path in paths:
        with path.open(encoding="utf-8", newline="") as handle:
            rows = csv.DictReader(handle, delimiter="\t")
            statuses.update({row["case"]: row["status"] for row in rows})
    archive_file = archive_path(ledger)
    if archive_file is not None and archive_file.is_file():
        with zipfile.ZipFile(archive_file) as archive:
            for member in archive.namelist():
                if re.fullmatch(r"output/summary[^/]*\.tsv", member):
                    text = archive.read(member).decode("utf-8", errors="replace")
                    rows = csv.DictReader(io.StringIO(text), delimiter="\t")
                    statuses.update({row["case"]: row["status"] for row in rows})
    error = None if statuses else f"MISSING:{(root / 'summary*.tsv').relative_to(ROOT)}"
    return statuses, error


def cell_rows(ledger, name):
    text = evidence_text(ledger, name, "cells.tsv")
    if text is None:
        return None
    return list(csv.DictReader(io.StringIO(text), delimiter="\t"))


def evaluate_check(ledger, check):
    selected = select_specimens(ledger, check.get("where", {}))
    if not selected:
        return "COVERAGE_GAP", ["NO_SPECIMENS_MATCH:" + json.dumps(check.get("where", {}), sort_keys=True)]

    failures = []
    coverage_missing = False
    kind = check["kind"]
    statuses, summary_error = summary_statuses(ledger)

    for name, _ in selected:
        base = specimen_dir(ledger, name)
        if kind == "summary_pass":
            if summary_error:
                failures.append(summary_error)
            elif statuses.get(name) != "PASS":
                failures.append(f"{name}:SUMMARY_STATUS={statuses.get(name, 'MISSING')}")
                coverage_missing = coverage_missing or name not in statuses
        elif kind == "artifacts_exist":
            for filename in check["files"]:
                if not evidence_exists(ledger, name, filename):
                    failures.append(f"{name}:MISSING_ARTIFACT={filename}")
                    coverage_missing = True
        elif kind in ("cell_refs_present", "cell_ref_count"):
            rows = cell_rows(ledger, name)
            if rows is None:
                failures.append(f"{name}:MISSING_ARTIFACT=cells.tsv")
                coverage_missing = True
                continue
            refs = [row.get("ref", "") for row in rows]
            if kind == "cell_refs_present":
                for ref in check["refs"]:
                    if ref not in refs:
                        failures.append(f"{name}:MISSING_CELL_REF={ref}")
            else:
                count = refs.count(check["ref"])
                if count != check["equals"]:
                    failures.append(
                        f"{name}:CELL_REF_COUNT={check['ref']}:{count}:EXPECTED={check['equals']}"
                    )
        elif kind in ("file_regex_absent", "file_regex_present"):
            text = evidence_text(ledger, name, check["file"])
            if text is None:
                failures.append(f"{name}:MISSING_ARTIFACT={check['file']}")
                coverage_missing = True
                continue
            matched = re.search(check["regex"], text) is not None
            if kind == "file_regex_absent" and matched:
                failures.append(f"{name}:FORBIDDEN_PATTERN={check['regex']}")
            if kind == "file_regex_present" and not matched:
                failures.append(f"{name}:REQUIRED_PATTERN_MISSING={check['regex']}")
        else:
            return "INVALID", [f"UNKNOWN_CHECK_KIND:{kind}"]

    if not failures:
        return "SUPPORTED", []
    if coverage_missing:
        return "COVERAGE_GAP", failures
    return "CONTRADICTED", failures


def evaluate_claim(ledger, claim):
    details = []
    states = []
    for check in claim["checks"]:
        state, failures = evaluate_check(ledger, check)
        states.append(state)
        details.extend(failures)
    if "INVALID" in states:
        state = "INVALID"
    elif "COVERAGE_GAP" in states:
        state = "COVERAGE_GAP"
    elif "CONTRADICTED" in states:
        state = "CONTRADICTED"
    else:
        state = "SUPPORTED"
    details = list(dict.fromkeys(details))
    return {"id": claim["id"], "state": state, "details": details, "claim": claim}


def evaluate(ledger):
    claims = [evaluate_claim(ledger, claim) for claim in ledger["claims"]]
    claim_states = {item["id"]: item["state"] for item in claims}
    experiments = sorted(
        (
            item for item in ledger["experiments"]
            if item.get("state") == "READY"
            and claim_states.get(item.get("completion_claim")) in (None, "COVERAGE_GAP")
        ),
        key=lambda item: item.get("priority", 0),
        reverse=True,
    )
    return {"mission": ledger["mission"], "claims": claims, "experiments": experiments}


def print_status(ledger, result):
    print("FRONTIER EVIDENCE STATUS")
    print("Mission:", result["mission"])
    print("Evidence:", ledger.get("snapshot_provenance", "live artifacts only"))
    print()
    counts = {}
    for item in result["claims"]:
        counts[item["state"]] = counts.get(item["state"], 0) + 1
        print(f"[{item['state']:<12}] {item['id']}")
        for detail in item["details"][:3]:
            print("  ", detail)
        if len(item["details"]) > 3:
            print(f"   ... {len(item['details']) - 3} more; use explain for full evidence")
    print()
    print("Summary:", " ".join(f"{key}={value}" for key, value in sorted(counts.items())))
    if result["experiments"]:
        next_item = result["experiments"][0]
        print("NEXT:", next_item["id"])
        print("Why:", next_item["expected_information"])
        print("Cost:", next_item["cost"])
        print("Stop:", next_item["stop_after"])
    else:
        print("NEXT: NONE - no experiment has earned READY status")
    print()
    print("Human:  python frontier/investigate.py explain CLAIM_ID")
    print("Machine: python frontier/investigate.py status --json")


def explain(ledger, claim_id):
    claim = next((item for item in ledger["claims"] if item["id"] == claim_id), None)
    if claim is None:
        raise ValueError(f"UNKNOWN_CLAIM:{claim_id}")
    result = evaluate_claim(ledger, claim)
    print(f"{claim['id']} [{result['state']}]")
    print("Question:", claim["question"])
    print("Claim:", claim["statement"])
    print("Scope:", claim["scope"])
    print("Evidence check:")
    if result["details"]:
        for detail in result["details"]:
            print(" -", detail)
    else:
        print(" - All declared checks passed.")
    print("Limitations:")
    for limitation in claim.get("limitations", []):
        print(" -", limitation)
    print("Stop when:", claim["stop_when"])
    print("Reopen when:", claim["reopen_when"])


def print_next(result):
    if not result["experiments"]:
        print("NO_READY_EXPERIMENT")
        return
    item = result["experiments"][0]
    print(item["id"])
    print("Parent goal:", item["parent_goal"])
    print("Change:", item["change"])
    print("Control:", item["control"])
    print("Information:", item["expected_information"])
    print("Cost:", item["cost"])
    print("Outcome tree:")
    for outcome, consequence in item["outcomes"].items():
        print(f" - {outcome}: {consequence}")
    print("Stopping rule:", item["stop_after"])


def main():
    parser = argparse.ArgumentParser(
        description="Human-readable and machine-readable Frontier evidence status."
    )
    sub = parser.add_subparsers(dest="command")
    status = sub.add_parser("status", help="Show claims, stopping boundaries, and next work")
    status.add_argument("--json", action="store_true", help="Emit the same state for a machine")
    explain_parser = sub.add_parser("explain", help="Explain one claim and its stopping boundary")
    explain_parser.add_argument("claim_id")
    sub.add_parser("next", help="Show only the highest-value ready experiment")
    args = parser.parse_args()

    try:
        ledger = load_ledger()
        result = evaluate(ledger)
        command = args.command or "status"
        if command == "status":
            if getattr(args, "json", False):
                serializable = {
                    "mission": result["mission"],
                    "claims": [
                        {"id": item["id"], "state": item["state"], "details": item["details"]}
                        for item in result["claims"]
                    ],
                    "next_experiment": result["experiments"][0] if result["experiments"] else None,
                }
                print(json.dumps(serializable, indent=2))
            else:
                print_status(ledger, result)
        elif command == "explain":
            explain(ledger, args.claim_id)
        elif command == "next":
            print_next(result)
        return 0
    except Exception as exc:
        print(f"INVESTIGATION_ERROR:{type(exc).__name__}:{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
