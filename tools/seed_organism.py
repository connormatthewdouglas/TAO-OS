#!/usr/bin/env python3
"""
CursiveOS seed organism CLI.

Phase 0 intentionally runs as a local, append-only organism loop:
variant -> sensor result -> regression gate -> ledger entry -> fake payout.
The schemas are production-shaped so bundles can later be submitted to
CursiveRoot/Hub without redesigning the local machinery.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STATE_DIR = ROOT / ".cursiveos" / "seed"
DEFAULT_CONFIG = {
    "schema_version": "seed-organism.config.v0.1",
    "current_cycle_share": 0.20,
    "lifetime_share": 0.80,
    "minimum_confidence": 0.65,
    "minimum_accept_fitness": 0.01,
    "weights": {
        "network": 0.40,
        "coldstart": 0.30,
        "sustained": 0.20,
        "idle_power": 0.10,
    },
    "caps_pct": {
        "network": 50.0,
        "coldstart": 50.0,
        "sustained": 50.0,
        "idle_power": 50.0,
    },
    "severe_regression_pct": {
        "network": -5.0,
        "coldstart": -5.0,
        "sustained": -3.0,
        "idle_power_cost": 15.0,
    },
}


class SeedError(RuntimeError):
    pass


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def read_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError as exc:
        raise SeedError(f"file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SeedError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SeedError(f"expected JSON object in {path}")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def append_jsonl(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(data, sort_keys=True) + "\n")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SeedError(f"invalid JSONL in {path}:{line_no}: {exc}") from exc
            if isinstance(row, dict):
                rows.append(row)
    return rows


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_json(data: dict[str, Any]) -> str:
    encoded = json.dumps(data, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(encoded)


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def state_path(args: argparse.Namespace) -> Path:
    return Path(args.state_dir).expanduser().resolve() if args.state_dir else DEFAULT_STATE_DIR


def ensure_state(state: Path) -> None:
    for name in ["runs", "ledger", "cycles", "exports", "variants"]:
        (state / name).mkdir(parents=True, exist_ok=True)
    config = state / "config.json"
    if not config.exists():
        write_json(config, DEFAULT_CONFIG)
    for name in ["variants.jsonl", "sensor-results.jsonl", "regression-results.jsonl", "ledger.jsonl", "payouts.jsonl"]:
        path = state / "ledger" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch(exist_ok=True)


def load_config(state: Path) -> dict[str, Any]:
    ensure_state(state)
    config = DEFAULT_CONFIG | read_json(state / "config.json")
    config["weights"] = DEFAULT_CONFIG["weights"] | config.get("weights", {})
    config["caps_pct"] = DEFAULT_CONFIG["caps_pct"] | config.get("caps_pct", {})
    config["severe_regression_pct"] = DEFAULT_CONFIG["severe_regression_pct"] | config.get("severe_regression_pct", {})
    return config


def git_commit_ref() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        return "unknown"


def machine_id_from_metrics(metrics: dict[str, Any]) -> str:
    explicit = metrics.get("machine_id") or metrics.get("hardware_fingerprint_hash")
    if explicit:
        return str(explicit)
    host = {
        "system": platform.system(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "node": platform.node(),
    }
    return "local-" + sha256_json(host)[:16]


def num(obj: dict[str, Any], key: str) -> float | None:
    value = obj.get(key)
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def pct_higher_is_better(baseline: float | None, variant: float | None) -> float | None:
    if baseline is None or variant is None or baseline == 0:
        return None
    return ((variant - baseline) / baseline) * 100.0


def pct_lower_is_better(baseline: float | None, variant: float | None) -> float | None:
    if baseline is None or variant is None or baseline == 0:
        return None
    return ((baseline - variant) / baseline) * 100.0


def pct_cost(baseline: float | None, variant: float | None) -> float | None:
    if baseline is None or variant is None or baseline == 0:
        return None
    return ((variant - baseline) / baseline) * 100.0


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def normalize_pct(value: float | None, cap: float) -> float:
    if value is None:
        return 0.0
    if cap <= 0:
        return 0.0
    return clamp(value / cap, -1.0, 1.0)


def present_core_metrics(metrics: dict[str, Any]) -> list[str]:
    baseline = metrics.get("baseline", {})
    variant = metrics.get("variant", {})
    required = {
        "network_mbps": (baseline, variant),
        "coldstart_ms": (baseline, variant),
        "sustained_tokps": (baseline, variant),
    }
    missing = []
    for key, (left, right) in required.items():
        if num(left, key) is None or num(right, key) is None:
            missing.append(key)
    return missing


def derive_confidence(metrics: dict[str, Any], missing_core: list[str]) -> float:
    if "confidence" in metrics:
        try:
            return clamp(float(metrics["confidence"]), 0.0, 1.0)
        except (TypeError, ValueError):
            pass
    if missing_core:
        return 0.0
    repeats = metrics.get("sample_counts", {})
    if not isinstance(repeats, dict):
        repeats = {}
    core_counts = [
        int(repeats.get("network", 1) or 1),
        int(repeats.get("coldstart", 1) or 1),
        int(repeats.get("sustained", 1) or 1),
    ]
    min_repeat = min(core_counts)
    return clamp(0.50 + (0.10 * (min_repeat - 1)), 0.50, 0.90)


def score_performance(
    *,
    variant: dict[str, Any],
    metrics: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    baseline = metrics.get("baseline", {})
    candidate = metrics.get("variant", {})
    if not isinstance(baseline, dict) or not isinstance(candidate, dict):
        raise SeedError("metrics must contain baseline and variant objects")

    missing_core = present_core_metrics(metrics)
    deltas = {
        "network_pct": pct_higher_is_better(num(baseline, "network_mbps"), num(candidate, "network_mbps")),
        "coldstart_pct": pct_lower_is_better(num(baseline, "coldstart_ms"), num(candidate, "coldstart_ms")),
        "sustained_pct": pct_higher_is_better(num(baseline, "sustained_tokps"), num(candidate, "sustained_tokps")),
        "idle_power_pct": pct_cost(num(baseline, "idle_watts"), num(candidate, "idle_watts")),
    }

    weights = config["weights"]
    caps = config["caps_pct"]
    fitness = (
        weights["network"] * normalize_pct(deltas["network_pct"], caps["network"])
        + weights["coldstart"] * normalize_pct(deltas["coldstart_pct"], caps["coldstart"])
        + weights["sustained"] * normalize_pct(deltas["sustained_pct"], caps["sustained"])
        - weights["idle_power"] * normalize_pct(deltas["idle_power_pct"], caps["idle_power"])
    )

    severe = []
    thresholds = config["severe_regression_pct"]
    if deltas["network_pct"] is not None and deltas["network_pct"] < thresholds["network"]:
        severe.append(f"network regression {deltas['network_pct']:.2f}%")
    if deltas["coldstart_pct"] is not None and deltas["coldstart_pct"] < thresholds["coldstart"]:
        severe.append(f"cold-start regression {deltas['coldstart_pct']:.2f}%")
    if deltas["sustained_pct"] is not None and deltas["sustained_pct"] < thresholds["sustained"]:
        severe.append(f"sustained regression {deltas['sustained_pct']:.2f}%")
    if deltas["idle_power_pct"] is not None and deltas["idle_power_pct"] > thresholds["idle_power_cost"]:
        severe.append(f"idle power cost {deltas['idle_power_pct']:.2f}%")

    result = {
        "schema_version": "seed-organism.sensor-result.v0.1",
        "variant_id": variant["variant_id"],
        "sensor_id": "perf.genesis.v1",
        "machine_id": machine_id_from_metrics(metrics),
        "preset_version": variant.get("preset_version") or metrics.get("preset_version") or "unknown",
        "baseline": {
            "network_mbps": num(baseline, "network_mbps"),
            "coldstart_ms": num(baseline, "coldstart_ms"),
            "sustained_tokps": num(baseline, "sustained_tokps"),
            "idle_watts": num(baseline, "idle_watts"),
        },
        "variant": {
            "network_mbps": num(candidate, "network_mbps"),
            "coldstart_ms": num(candidate, "coldstart_ms"),
            "sustained_tokps": num(candidate, "sustained_tokps"),
            "idle_watts": num(candidate, "idle_watts"),
        },
        "delta": deltas,
        "confidence": derive_confidence(metrics, missing_core),
        "fitness_score": round(fitness, 8),
        "missing_core_metrics": missing_core,
        "severe_regressions": severe,
        "timestamp": now_iso(),
    }
    result["sensor_result_hash"] = sha256_json(result)
    return result


def evaluate_regression(variant: dict[str, Any], metrics: dict[str, Any]) -> dict[str, Any]:
    regression = metrics.get("regression", {})
    if not isinstance(regression, dict):
        regression = {}

    failures = list(regression.get("failures", []) or [])
    full_test_passed = bool(regression.get("full_test_passed", True))
    reverted_cleanly = bool(regression.get("reverted_cleanly", True))
    host_safety_passed = bool(regression.get("host_safety_passed", True))

    if not full_test_passed:
        failures.append("full-test gate failed")
    if not reverted_cleanly:
        failures.append("reversibility gate failed")
    if not host_safety_passed:
        failures.append("host-safety gate failed")

    result = {
        "schema_version": "seed-organism.regression-result.v0.1",
        "variant_id": variant["variant_id"],
        "sensor_id": "regression.genesis.v1",
        "machine_id": machine_id_from_metrics(metrics),
        "passed": not failures,
        "failures": failures,
        "reverted_cleanly": reverted_cleanly,
        "full_test_passed": full_test_passed,
        "host_safety_passed": host_safety_passed,
        "timestamp": now_iso(),
    }
    result["regression_result_hash"] = sha256_json(result)
    return result


def verdict(sensor: dict[str, Any], regression: dict[str, Any], config: dict[str, Any]) -> tuple[str, str]:
    if sensor["missing_core_metrics"]:
        return "invalid", "missing core metrics: " + ", ".join(sensor["missing_core_metrics"])
    if not regression["passed"]:
        return "rejected_regression", "; ".join(regression["failures"])
    if sensor["severe_regressions"]:
        return "rejected_negative_fitness", "; ".join(sensor["severe_regressions"])
    if sensor["confidence"] < float(config["minimum_confidence"]):
        return "inconclusive", f"confidence {sensor['confidence']:.2f} below minimum {config['minimum_confidence']:.2f}"
    if sensor["fitness_score"] <= float(config["minimum_accept_fitness"]):
        return "rejected_negative_fitness", f"fitness {sensor['fitness_score']:.4f} below acceptance threshold"
    return "accepted", "fitness positive and gates passed"


def validate_variant(data: dict[str, Any]) -> dict[str, Any]:
    if "variant_id" not in data:
        raise SeedError("variant is missing variant_id")
    data = dict(data)
    data.setdefault("schema_version", "seed-organism.variant.v0.1")
    data.setdefault("contributor_id", "local-founder")
    data.setdefault("commit_ref", git_commit_ref())
    data.setdefault("declared_scope", "local seed organism evaluation")
    data.setdefault("rollback_method", "preset --undo or benchmark harness cleanup")
    return data


def ledger_entry(
    *,
    cycle_id: int,
    variant: dict[str, Any],
    sensor: dict[str, Any],
    bundle_hash: str,
) -> dict[str, Any]:
    return {
        "schema_version": "seed-organism.ledger-entry.v0.1",
        "ledger_entry_id": "ledger-" + uuid.uuid4().hex,
        "cycle_id": str(cycle_id),
        "variant_id": variant["variant_id"],
        "contributor_id": variant["contributor_id"],
        "commit_ref": variant["commit_ref"],
        "sensor_result_refs": [bundle_hash, sensor["sensor_result_hash"]],
        "fitness_score": sensor["fitness_score"],
        "current_cycle_eligible": True,
        "lifetime_fitness_delta": sensor["fitness_score"],
        "created_at": now_iso(),
    }


def write_bundle(
    *,
    state: Path,
    cycle_id: int,
    variant: dict[str, Any],
    metrics: dict[str, Any],
    sensor: dict[str, Any],
    regression: dict[str, Any],
    decision: str,
    reason: str,
) -> tuple[Path, str]:
    ts = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_id = uuid.uuid4().hex[:8]
    run_dir = state / "runs" / f"cycle-{cycle_id}" / f"{variant['variant_id']}-{ts}-{run_id}"
    write_json(run_dir / "variant.json", variant)
    write_json(run_dir / "metrics.json", metrics)
    write_json(run_dir / "sensor-result.json", sensor)
    write_json(run_dir / "regression-result.json", regression)
    manifest = {
        "schema_version": "seed-organism.bundle-manifest.v0.1",
        "variant_id": variant["variant_id"],
        "run_id": run_id,
        "cycle_id": str(cycle_id),
        "decision": decision,
        "reason": reason,
        "created_at": now_iso(),
        "files": {},
    }
    for path in sorted(run_dir.glob("*.json")):
        manifest["files"][path.name] = sha256_bytes(path.read_bytes())
    manifest["bundle_hash"] = sha256_json(manifest)
    write_json(run_dir / "bundle-manifest.json", manifest)
    return run_dir, manifest["bundle_hash"]


def cmd_init(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    print(f"seed organism state initialized: {rel(state)}")
    print(f"config: {rel(state / 'config.json')}")


def cmd_run_variant(args: argparse.Namespace) -> None:
    state = state_path(args)
    config = load_config(state)
    variant = validate_variant(read_json(Path(args.variant)))
    metrics = collect_metrics(args, variant)

    sensor = score_performance(variant=variant, metrics=metrics, config=config)
    regression = evaluate_regression(variant, metrics)
    decision, reason = verdict(sensor, regression, config)
    run_dir, bundle_hash = write_bundle(
        state=state,
        cycle_id=args.cycle_id,
        variant=variant,
        metrics=metrics,
        sensor=sensor,
        regression=regression,
        decision=decision,
        reason=reason,
    )

    variant_record = dict(variant)
    variant_record.update({"cycle_id": str(args.cycle_id), "recorded_at": now_iso()})
    append_jsonl(state / "ledger" / "variants.jsonl", variant_record)
    append_jsonl(state / "ledger" / "sensor-results.jsonl", sensor | {"bundle_hash": bundle_hash, "decision": decision})
    append_jsonl(state / "ledger" / "regression-results.jsonl", regression | {"bundle_hash": bundle_hash, "decision": decision})

    if decision == "accepted":
        entry = ledger_entry(cycle_id=args.cycle_id, variant=variant, sensor=sensor, bundle_hash=bundle_hash)
        append_jsonl(state / "ledger" / "ledger.jsonl", entry)

    print(f"variant: {variant['variant_id']}")
    print(f"decision: {decision}")
    print(f"reason: {reason}")
    print(f"fitness_score: {sensor['fitness_score']:.6f}")
    print(f"confidence: {sensor['confidence']:.2f}")
    print(f"bundle_hash: {bundle_hash}")
    print(f"bundle: {rel(run_dir)}")


def collect_metrics(args: argparse.Namespace, variant: dict[str, Any]) -> dict[str, Any]:
    if args.metrics:
        return read_json(Path(args.metrics))
    if args.execute:
        return execute_linux_harness(variant)
    raise SeedError("provide --metrics for deterministic scoring, or --execute on a Linux test host")


def execute_linux_harness(variant: dict[str, Any]) -> dict[str, Any]:
    if platform.system() != "Linux":
        raise SeedError("--execute is only supported on Linux test hosts")
    preset = variant.get("preset_path")
    if not preset:
        raise SeedError("variant must include preset_path for --execute")
    preset_path = (ROOT / preset).resolve() if not Path(preset).is_absolute() else Path(preset)
    if not preset_path.exists():
        raise SeedError(f"preset_path not found: {preset_path}")
    harness = ROOT / "cursiveos-full-test-v1.4.sh"
    if not harness.exists():
        raise SeedError(f"full-test harness not found: {harness}")

    logs_dir = ROOT / "logs"
    before_logs = set(logs_dir.glob("cursiveos-full-test-*.log"))
    before_json = set(logs_dir.glob("cursiveos-full-test-*.json"))
    subprocess.run([str(harness), str(preset_path)], cwd=ROOT, check=True)
    after_json = set(logs_dir.glob("cursiveos-full-test-*.json"))
    new_json = sorted(after_json - before_json, key=lambda p: p.stat().st_mtime)
    if new_json:
        return load_full_test_metrics_json(new_json[-1])
    after_logs = set(logs_dir.glob("cursiveos-full-test-*.log"))
    new_logs = sorted(after_logs - before_logs, key=lambda p: p.stat().st_mtime)
    if not new_logs:
        raise SeedError("harness completed but no new result JSON or summary log was found")
    return parse_full_test_log(new_logs[-1])


def load_full_test_metrics_json(path: Path) -> dict[str, Any]:
    data = read_json(path)
    baseline = data.get("baseline", {})
    candidate = data.get("variant", {})
    regression = data.get("regression", {})
    if not isinstance(baseline, dict) or not isinstance(candidate, dict):
        raise SeedError(f"full-test result JSON missing baseline/variant objects: {path}")
    if not isinstance(regression, dict):
        regression = {}
    return {
        "schema_version": "seed-organism.metrics.from-full-test-json.v0.1",
        "source_result_json": str(path),
        "source_log": data.get("summary_log"),
        "machine_id": data.get("machine_id") or data.get("hardware_fingerprint_hash"),
        "hardware_fingerprint_hash": data.get("hardware_fingerprint_hash"),
        "preset_version": data.get("preset_version", "v0.8"),
        "baseline": {
            "network_mbps": num(baseline, "network_mbps"),
            "coldstart_ms": num(baseline, "coldstart_ms"),
            "sustained_tokps": num(baseline, "sustained_tokps"),
            "idle_watts": num(baseline, "idle_watts"),
        },
        "variant": {
            "network_mbps": num(candidate, "network_mbps"),
            "coldstart_ms": num(candidate, "coldstart_ms"),
            "sustained_tokps": num(candidate, "sustained_tokps"),
            "idle_watts": num(candidate, "idle_watts"),
        },
        "sample_counts": data.get("sample_counts", {"network": 1, "coldstart": 1, "sustained": 1}),
        "regression": {
            "full_test_passed": bool(regression.get("full_test_passed", True)),
            "reverted_cleanly": bool(regression.get("reverted_cleanly", True)),
            "host_safety_passed": bool(regression.get("host_safety_passed", True)),
            "failures": list(regression.get("failures", []) or []),
        },
    }


def parse_full_test_log(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    rows = {}
    fingerprint = None
    stability_passed = True
    stability_failures = []
    for line in text.splitlines():
        parts = line.split()
        if line.startswith("Fingerprint:"):
            fingerprint = line.split(":", 1)[1].strip()
        elif line.startswith("Stability"):
            stability_passed = " true " in f" {line.lower()} "
            if not stability_passed:
                stability_failures.append("stability flag false in full-test summary")
        if line.startswith("Network throughput") and len(parts) >= 7:
            rows["network"] = (parts[2], parts[4])
        elif line.startswith("Cold-start latency") and len(parts) >= 5:
            rows["coldstart"] = (parts[2].replace("ms", ""), parts[3].replace("ms", ""))
        elif line.startswith("Sustained inference") and len(parts) >= 4:
            rows["sustained"] = (parts[2], parts[3])
        elif line.startswith("Idle power draw") and len(parts) >= 5:
            rows["power"] = (parts[3].replace("W", ""), parts[4].replace("W", ""))
    try_float = lambda v: None if v in (None, "N/A") else float(str(v).replace("+", "").replace("%", ""))
    return {
        "schema_version": "seed-organism.metrics.from-full-test.v0.1",
        "source_log": str(path),
        "machine_id": fingerprint or "linux-" + sha256_bytes(text.encode("utf-8"))[:16],
        "preset_version": "v0.8",
        "baseline": {
            "network_mbps": try_float(rows.get("network", [None, None])[0]),
            "coldstart_ms": try_float(rows.get("coldstart", [None, None])[0]),
            "sustained_tokps": try_float(rows.get("sustained", [None, None])[0]),
            "idle_watts": try_float(rows.get("power", [None, None])[0]),
        },
        "variant": {
            "network_mbps": try_float(rows.get("network", [None, None])[1]),
            "coldstart_ms": try_float(rows.get("coldstart", [None, None])[1]),
            "sustained_tokps": try_float(rows.get("sustained", [None, None])[1]),
            "idle_watts": try_float(rows.get("power", [None, None])[1]),
        },
        "sample_counts": {"network": 1, "coldstart": 1, "sustained": 1},
        "regression": {
            "full_test_passed": stability_passed,
            "reverted_cleanly": "Presets reverted" in text,
            "host_safety_passed": True,
            "failures": stability_failures,
        },
    }


def cmd_close_cycle(args: argparse.Namespace) -> None:
    state = state_path(args)
    config = load_config(state)
    ledger = read_jsonl(state / "ledger" / "ledger.jsonl")
    cycle_id = str(args.cycle_id)
    revenue = int(args.revenue_sats)
    contributors: dict[str, dict[str, float]] = {}

    for entry in ledger:
        cid = str(entry["contributor_id"])
        contributors.setdefault(cid, {"cycle_fitness": 0.0, "lifetime_fitness": 0.0})
        contributors[cid]["lifetime_fitness"] += float(entry.get("lifetime_fitness_delta", 0.0))
        if str(entry.get("cycle_id")) == cycle_id and entry.get("current_cycle_eligible", True):
            contributors[cid]["cycle_fitness"] += float(entry.get("fitness_score", 0.0))

    current_share = float(config["current_cycle_share"])
    lifetime_share = float(config["lifetime_share"])
    current_pot = int(round(revenue * current_share))
    lifetime_pot = revenue - current_pot
    cycle_total = sum(v["cycle_fitness"] for v in contributors.values())
    lifetime_total = sum(v["lifetime_fitness"] for v in contributors.values())

    rows = []
    for cid, values in sorted(contributors.items()):
        cycle_fit = values["cycle_fitness"]
        lifetime_fit = values["lifetime_fitness"]
        current_payout = int(round(current_pot * (cycle_fit / cycle_total))) if cycle_total > 0 else 0
        lifetime_payout = int(round(lifetime_pot * (lifetime_fit / lifetime_total))) if lifetime_total > 0 else 0
        rows.append({
            "contributor_id": cid,
            "cycle_fitness": round(cycle_fit, 8),
            "lifetime_fitness": round(lifetime_fit, 8),
            "current_cycle_payout_sats": current_payout,
            "lifetime_payout_sats": lifetime_payout,
            "total_payout_sats": current_payout + lifetime_payout,
        })

    report = {
        "schema_version": "seed-organism.payout-report.v0.1",
        "cycle_id": cycle_id,
        "simulated_revenue_sats": revenue,
        "current_cycle_share": current_share,
        "lifetime_share": lifetime_share,
        "contributors": rows,
        "created_at": now_iso(),
    }
    report["payout_report_hash"] = sha256_json(report)
    out = state / "cycles" / f"cycle-{cycle_id}-payout.json"
    write_json(out, report)
    append_jsonl(state / "ledger" / "payouts.jsonl", report)
    print(f"cycle: {cycle_id}")
    print(f"contributors: {len(rows)}")
    print(f"report_hash: {report['payout_report_hash']}")
    print(f"report: {rel(out)}")


def cmd_status(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    variants = read_jsonl(state / "ledger" / "variants.jsonl")
    sensors = read_jsonl(state / "ledger" / "sensor-results.jsonl")
    ledger = read_jsonl(state / "ledger" / "ledger.jsonl")
    payouts = read_jsonl(state / "ledger" / "payouts.jsonl")
    accepted = [r for r in sensors if r.get("decision") == "accepted"]
    print(f"state: {rel(state)}")
    print(f"variants_evaluated: {len(variants)}")
    print(f"accepted_variants: {len(accepted)}")
    print(f"ledger_entries: {len(ledger)}")
    print(f"payout_reports: {len(payouts)}")
    if sensors:
        last = sensors[-1]
        print(f"last_decision: {last.get('variant_id')} -> {last.get('decision')} fitness={last.get('fitness_score')}")


def cmd_export(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    out = state / "exports" / f"seed-export-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    shutil.copytree(state / "ledger", out / "ledger")
    if (state / "cycles").exists():
        shutil.copytree(state / "cycles", out / "cycles")
    manifest = {
        "schema_version": "seed-organism.export-manifest.v0.1",
        "created_at": now_iso(),
        "source_state": str(state),
        "files": {},
    }
    for path in sorted(out.rglob("*")):
        if path.is_file():
            manifest["files"][str(path.relative_to(out))] = sha256_bytes(path.read_bytes())
    manifest["export_hash"] = sha256_json(manifest)
    write_json(out / "export-manifest.json", manifest)
    print(f"export_hash: {manifest['export_hash']}")
    print(f"export: {rel(out)}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Run the CursiveOS Phase 0 seed organism loop")
    p.add_argument("--state-dir", default=None, help="local seed state directory (default: .cursiveos/seed)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="initialize local seed organism state")

    run = sub.add_parser("run-variant", help="score a variant and write an audit bundle")
    run.add_argument("--variant", required=True, help="variant metadata JSON")
    run.add_argument("--metrics", help="deterministic metrics JSON")
    run.add_argument("--execute", action="store_true", help="run the Linux full-test harness for the variant preset")
    run.add_argument("--cycle-id", type=int, default=1)

    close = sub.add_parser("close-cycle", help="compute fake-BTC payout report for a cycle")
    close.add_argument("--cycle-id", type=int, required=True)
    close.add_argument("--revenue-sats", type=int, required=True)

    sub.add_parser("status", help="show local organism state")
    sub.add_parser("export", help="export ledger and cycle reports for CursiveRoot/Hub ingestion")
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        {
            "init": cmd_init,
            "run-variant": cmd_run_variant,
            "close-cycle": cmd_close_cycle,
            "status": cmd_status,
            "export": cmd_export,
        }[args.cmd](args)
    except SeedError as exc:
        print(f"seed-organism error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
