#!/usr/bin/env python3
"""
Layer 5 tokenomics simulation — v3.1 (BTC + Babylon yield, 60/40 split).

Architecture:
  - Fast users pay F_fast_usd per cycle per machine (converted to BTC at settlement)
  - Each payment: 60% → payout_pot (distributed by validator vote, resets each cycle)
                  40% → pool_principal (locked forever, earns Babylon yield)
  - Validators: pay F_fast, receive F_fast refund (net zero), get 100 vote points
  - Contributors: earn from TWO streams:
      1. payout_pot share  = (cycle_votes / total_cycle_votes) × payout_pot
      2. yield_royalty      = (lifetime_votes / all_lifetime_votes) × cycle_yield
  - Babylon yield: babylon_gross_yield × staking_fraction × pool_principal / cycles_per_year
  - 1% minimum vote threshold for any payout or lifetime vote accrual
  - Reputation cooldown: 3 consecutive cycles with < min_vote_threshold → 5-cycle cooldown

Usage:
  python3 tools/layer5_tokenomics_playground.py \\
    --scenario references/layer5-sim-scenario.json \\
    --out reports/layer5-sim-report.json
"""

from __future__ import annotations
import argparse
import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Any, Optional


DEFAULT_PARAMS = {
    # Pricing
    "F_fast_usd": 2.0,          # Fast user fee per machine per cycle, USD
    "btc_price_usd": 85000.0,   # BTC/USD at settlement (can be overridden per scenario)

    # Split
    "payout_pot_fraction": 0.60,  # fraction of fast revenue to payout pot
    "pool_fraction": 0.40,        # fraction of fast revenue to pool principal (locked)

    # Babylon yield
    "babylon_gross_yield": 0.065,  # ~6.5% gross annual
    "staking_fraction": 0.50,      # 50% of pool actively staked; 50% cold storage
    "cycles_per_year": 12,         # monthly cycles

    # Governance
    "validator_vote_points": 100,       # points each eligible validator distributes per cycle
    "min_vote_threshold": 0.01,         # 1% of total votes for any payout/royalty
    "low_vote_cooldown_trigger": 3,     # consecutive low-vote cycles → cooldown
    "cooldown_cycles": 5,               # cycles contributor is locked out after trigger
}


@dataclass
class Contributor:
    account_id: str
    lifetime_votes: float = 0.0
    cycle_low_vote_streak: int = 0
    cooldown_remaining: int = 0

    # Cumulative earnings
    total_payout_earned_btc: float = 0.0
    total_royalty_earned_btc: float = 0.0


@dataclass
class CycleResult:
    cycle_id: int
    fast_user_count: int
    fast_revenue_usd: float
    fast_revenue_btc: float
    payout_pot_btc: float
    pool_inflow_btc: float
    pool_principal_btc: float           # cumulative, locked
    cycle_yield_btc: float              # Babylon yield this cycle
    total_cycle_votes: float
    accepted_submissions: int
    contributor_payouts: List[Dict]     # [{account_id, cycle_votes, payout_btc, royalty_btc}]
    validator_net_cost_btc: float       # should be 0.0 (pay F_fast, get refunded F_fast)
    all_lifetime_votes_total: float     # global lifetime votes after this cycle


class Sim:
    def __init__(self, params: Dict[str, Any], seed: int = 42):
        self.p = {**DEFAULT_PARAMS, **params}
        self.rng = random.Random(seed)
        self.contributors: Dict[str, Contributor] = {}

    def _usd_to_btc(self, usd: float) -> float:
        return usd / self.p["btc_price_usd"]

    def _effective_yield_rate(self) -> float:
        """Effective per-cycle yield rate on pool principal."""
        gross = float(self.p["babylon_gross_yield"])
        staking = float(self.p["staking_fraction"])
        cycles = max(1, int(self.p["cycles_per_year"]))
        return (gross * staking) / cycles

    def _ensure_contributor(self, account_id: str) -> Contributor:
        if account_id not in self.contributors:
            self.contributors[account_id] = Contributor(account_id=account_id)
        return self.contributors[account_id]

    def run(self, scenario: Dict[str, Any]) -> Dict[str, Any]:
        p = self.p
        cycles = int(scenario.get("cycles", 12))
        pool_principal = float(scenario.get("pool_principal_open", 0.0))

        # Scenario: list of cycles, each can specify fast_user_count, submitted contributions
        # If a flat fast_user_count is given at top level, use it for all cycles
        default_fast_users = int(scenario.get("fast_user_count", 5))
        default_validator_count = int(scenario.get("validator_count", 3))
        default_submissions_per_cycle = int(scenario.get("submissions_per_cycle", 2))
        default_acceptance_rate = float(scenario.get("acceptance_rate", 0.70))

        # Per-cycle overrides can be provided in scenario["cycle_overrides"][cycle_id]
        cycle_overrides: Dict[int, Dict] = {}
        for ov in scenario.get("cycle_overrides", []):
            cycle_overrides[int(ov["cycle_id"])] = ov

        cycle_rows: List[CycleResult] = []
        total_cumulative_yield_btc = 0.0

        for c in range(1, cycles + 1):
            ov = cycle_overrides.get(c, {})
            fast_user_count = int(ov.get("fast_user_count", default_fast_users))
            validator_count = int(ov.get("validator_count", default_validator_count))
            submissions_this_cycle = int(ov.get("submissions_per_cycle", default_submissions_per_cycle))
            acceptance_rate = float(ov.get("acceptance_rate", default_acceptance_rate))

            # --- Revenue ---
            fast_revenue_usd = fast_user_count * float(p["F_fast_usd"])
            fast_revenue_btc = self._usd_to_btc(fast_revenue_usd)

            payout_pot_btc = fast_revenue_btc * float(p["payout_pot_fraction"])
            pool_inflow_btc = fast_revenue_btc * float(p["pool_fraction"])
            pool_principal += pool_inflow_btc

            # --- Babylon yield ---
            cycle_yield_btc = pool_principal * self._effective_yield_rate()
            total_cumulative_yield_btc += cycle_yield_btc

            # --- Validator net cost ---
            # Validators pay F_fast_usd and receive a full refund → net zero
            # Their voting rights are granted by their eligibility, not payment
            f_fast_btc = self._usd_to_btc(float(p["F_fast_usd"]))
            validator_net_cost_btc = 0.0  # pay - refund = 0

            # --- Contribution voting ---
            # Generate submissions for this cycle
            # Each submission is accepted or rejected based on acceptance_rate
            # Accepted submissions receive validator votes (100 pts × validator_count distributed)

            accepted_ids: List[str] = []
            for i in range(submissions_this_cycle):
                # Assign to a contributor account (scripted or auto-generated)
                if ov.get("contributor_accounts"):
                    acct_pool = ov["contributor_accounts"]
                    account_id = acct_pool[i % len(acct_pool)]
                elif scenario.get("contributor_accounts"):
                    acct_pool = scenario["contributor_accounts"]
                    account_id = acct_pool[i % len(acct_pool)]
                else:
                    account_id = f"contributor_{(c * 100 + i) % max(1, int(scenario.get('contributor_pool_size', 3))) + 1}"

                contrib = self._ensure_contributor(account_id)
                if contrib.cooldown_remaining > 0:
                    continue  # contributor is in cooldown, submission silently skipped

                accepted = self.rng.random() < acceptance_rate
                if accepted:
                    accepted_ids.append(account_id)

            # Distribute 100 × validator_count vote points across accepted submissions
            total_vote_points = float(p["validator_vote_points"]) * validator_count
            vote_alloc: Dict[str, float] = {}

            if accepted_ids:
                # Validators distribute votes randomly (uniform for sim; real system uses democratic vote)
                # Each validator distributes 100 points across accepted submissions
                for _ in range(validator_count):
                    remaining = float(p["validator_vote_points"])
                    pts = sorted([self.rng.random() for _ in range(len(accepted_ids) - 1)])
                    cuts = [0.0] + pts + [1.0]
                    shares = [cuts[j+1] - cuts[j] for j in range(len(accepted_ids))]
                    for idx, aid in enumerate(accepted_ids):
                        alloc = shares[idx] * remaining
                        vote_alloc[aid] = vote_alloc.get(aid, 0.0) + alloc

            total_cycle_votes = sum(vote_alloc.values())
            min_threshold = float(p["min_vote_threshold"])

            # --- Contributor payouts ---
            # Global lifetime votes (before this cycle's additions — royalty uses post-cycle totals)
            # We compute in two passes: first add this cycle's votes to lifetime, then compute royalties

            # Pass 1: add cycle votes to lifetime ledger
            qualifying_votes: Dict[str, float] = {}
            for aid, cv in vote_alloc.items():
                frac = cv / total_cycle_votes if total_cycle_votes > 0 else 0.0
                if frac >= min_threshold:
                    qualifying_votes[aid] = cv
                    contrib = self._ensure_contributor(aid)
                    contrib.lifetime_votes += cv
                    contrib.cycle_low_vote_streak = 0
                else:
                    contrib = self._ensure_contributor(aid)
                    contrib.cycle_low_vote_streak += 1
                    if contrib.cycle_low_vote_streak >= int(p["low_vote_cooldown_trigger"]):
                        contrib.cooldown_remaining = int(p["cooldown_cycles"])
                        contrib.cycle_low_vote_streak = 0

            # Tick cooldowns for all contributors
            for contrib in self.contributors.values():
                if contrib.cooldown_remaining > 0:
                    contrib.cooldown_remaining -= 1

            # Global lifetime votes total (after this cycle)
            all_lifetime_votes = sum(c.lifetime_votes for c in self.contributors.values())

            # Pass 2: compute payouts
            contributor_payouts = []
            for aid, cv in qualifying_votes.items():
                contrib = self.contributors[aid]
                vote_share = cv / total_cycle_votes if total_cycle_votes > 0 else 0.0

                # Stream 1: payout pot share
                payout_btc = vote_share * payout_pot_btc

                # Stream 2: yield royalty (lifetime_votes / all_lifetime after this cycle)
                royalty_share = contrib.lifetime_votes / all_lifetime_votes if all_lifetime_votes > 0 else 0.0
                royalty_btc = royalty_share * cycle_yield_btc

                contrib.total_payout_earned_btc += payout_btc
                contrib.total_royalty_earned_btc += royalty_btc

                contributor_payouts.append({
                    "account_id": aid,
                    "cycle_votes": round(cv, 4),
                    "vote_share_pct": round(vote_share * 100, 2),
                    "payout_btc": round(payout_btc, 8),
                    "payout_usd": round(payout_btc * float(p["btc_price_usd"]), 4),
                    "royalty_btc": round(royalty_btc, 8),
                    "royalty_usd": round(royalty_btc * float(p["btc_price_usd"]), 4),
                    "lifetime_votes_after": round(contrib.lifetime_votes, 4),
                })

            cycle_rows.append(CycleResult(
                cycle_id=c,
                fast_user_count=fast_user_count,
                fast_revenue_usd=round(fast_revenue_usd, 4),
                fast_revenue_btc=round(fast_revenue_btc, 8),
                payout_pot_btc=round(payout_pot_btc, 8),
                pool_inflow_btc=round(pool_inflow_btc, 8),
                pool_principal_btc=round(pool_principal, 8),
                cycle_yield_btc=round(cycle_yield_btc, 8),
                total_cycle_votes=round(total_cycle_votes, 4),
                accepted_submissions=len(accepted_ids),
                contributor_payouts=contributor_payouts,
                validator_net_cost_btc=validator_net_cost_btc,
                all_lifetime_votes_total=round(all_lifetime_votes, 4),
            ))

        # --- Summary ---
        total_payout_btc = sum(r.payout_pot_btc for r in cycle_rows)
        total_yield_btc = sum(r.cycle_yield_btc for r in cycle_rows)
        total_revenue_usd = sum(r.fast_revenue_usd for r in cycle_rows)

        return {
            "params": p,
            "summary": {
                "cycles": cycles,
                "pool_principal_final_btc": round(pool_principal, 8),
                "pool_principal_final_usd": round(pool_principal * float(p["btc_price_usd"]), 2),
                "total_fast_revenue_usd": round(total_revenue_usd, 2),
                "total_payout_pot_distributed_btc": round(total_payout_btc, 8),
                "total_babylon_yield_btc": round(total_yield_btc, 8),
                "total_babylon_yield_usd": round(total_yield_btc * float(p["btc_price_usd"]), 4),
                "effective_yield_rate_per_cycle": round(self._effective_yield_rate(), 6),
                "btc_price_used": float(p["btc_price_usd"]),
            },
            "contributors_final": {
                cid: {
                    "lifetime_votes": round(c.lifetime_votes, 4),
                    "total_payout_btc": round(c.total_payout_earned_btc, 8),
                    "total_payout_usd": round(c.total_payout_earned_btc * float(p["btc_price_usd"]), 4),
                    "total_royalty_btc": round(c.total_royalty_earned_btc, 8),
                    "total_royalty_usd": round(c.total_royalty_earned_btc * float(p["btc_price_usd"]), 4),
                    "cooldown_remaining": c.cooldown_remaining,
                }
                for cid, c in self.contributors.items()
            },
            "cycles": [
                {
                    "cycle_id": r.cycle_id,
                    "fast_user_count": r.fast_user_count,
                    "fast_revenue_usd": r.fast_revenue_usd,
                    "fast_revenue_btc": r.fast_revenue_btc,
                    "payout_pot_btc": r.payout_pot_btc,
                    "pool_inflow_btc": r.pool_inflow_btc,
                    "pool_principal_btc": r.pool_principal_btc,
                    "cycle_yield_btc": r.cycle_yield_btc,
                    "accepted_submissions": r.accepted_submissions,
                    "total_cycle_votes": r.total_cycle_votes,
                    "all_lifetime_votes": r.all_lifetime_votes_total,
                    "contributor_payouts": r.contributor_payouts,
                }
                for r in cycle_rows
            ],
        }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    scenario = json.loads(Path(args.scenario).read_text())
    sim = Sim(params=scenario.get("params", {}), seed=int(scenario.get("seed", 42)))
    result = sim.run(scenario)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2))

    print(json.dumps(result["summary"], indent=2))


if __name__ == "__main__":
    main()
