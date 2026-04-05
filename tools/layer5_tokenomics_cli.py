#!/usr/bin/env python3
"""
Layer 5 tokenomics CLI — v3.1

Wraps layer5_tokenomics_playground.py for interactive scenario editing and sim runs.

Usage examples:
  python3 tools/layer5_tokenomics_cli.py show-params
  python3 tools/layer5_tokenomics_cli.py set-param --key F_fast_usd --value 2.00
  python3 tools/layer5_tokenomics_cli.py set-fast-users --value 10
  python3 tools/layer5_tokenomics_cli.py run --verbose
  python3 tools/layer5_tokenomics_cli.py status
"""
import argparse
import json
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
ACTIVE_SCENARIO = ROOT / 'references' / 'layer5-sim-scenario.active.json'
BASELINE_SCENARIO = ROOT / 'references' / 'layer5-sim-scenario.json'
DEFAULT_OUT = ROOT / 'reports' / 'layer5-sim-report-active.json'
SIM_MODULE_PATH = ROOT / 'tools' / 'layer5_tokenomics_playground.py'


def load_sim_module():
    spec = importlib.util.spec_from_file_location('layer5_sim', SIM_MODULE_PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def ensure_active():
    if not ACTIVE_SCENARIO.exists():
        ACTIVE_SCENARIO.write_text(BASELINE_SCENARIO.read_text())


def load_active():
    ensure_active()
    return json.loads(ACTIVE_SCENARIO.read_text())


def save_active(data):
    ACTIVE_SCENARIO.write_text(json.dumps(data, indent=2))


# ── commands ──────────────────────────────────────────────────────────────────

def cmd_help(_):
    print('''Commands:
  help
    Show this command list.

  reset [--source baseline]
    Reset active scenario from the baseline template.

  show-params
    Show current tokenomics params from active scenario.

  show-scenario
    Show full active scenario JSON.

  set-param --key PARAM --value N
    Update a scenario parameter (e.g. F_fast_usd, btc_price_usd, babylon_gross_yield).

  set-fast-users --value N
    Set default fast_user_count for the scenario.

  set-validators --value N
    Set default validator_count for the scenario.

  set-cycles --value N
    Set number of cycles.

  set-acceptance-rate --value N
    Set acceptance_rate (0.0-1.0) for submissions.

  run [--out PATH] [--verbose] [--tail N]
    Run simulation using active scenario and write report JSON.

  status [--report PATH] [--tail N]
    Show summary and per-cycle table from latest report.
''')


def cmd_reset(args):
    ACTIVE_SCENARIO.write_text(BASELINE_SCENARIO.read_text())
    print(f'active scenario reset from baseline: {ACTIVE_SCENARIO}')


def cmd_show_params(_):
    data = load_active()
    params = data.get('params', {})
    print('--- scenario params ---')
    for k in sorted(params.keys()):
        print(f'  {k} = {params[k]}')
    print(f'  fast_user_count = {data.get("fast_user_count", "--")}')
    print(f'  validator_count = {data.get("validator_count", "--")}')
    print(f'  cycles          = {data.get("cycles", "--")}')
    print(f'  acceptance_rate = {data.get("acceptance_rate", "--")}')


def cmd_show_scenario(_):
    data = load_active()
    print(json.dumps(data, indent=2))


def cmd_set_param(args):
    data = load_active()
    data.setdefault('params', {})[args.key] = float(args.value)
    save_active(data)
    print(f'param {args.key} = {data["params"][args.key]}')


def cmd_set_fast_users(args):
    data = load_active()
    data['fast_user_count'] = int(args.value)
    save_active(data)
    print(f'fast_user_count = {data["fast_user_count"]}')


def cmd_set_validators(args):
    data = load_active()
    data['validator_count'] = int(args.value)
    save_active(data)
    print(f'validator_count = {data["validator_count"]}')


def cmd_set_cycles(args):
    data = load_active()
    data['cycles'] = int(args.value)
    save_active(data)
    print(f'cycles = {data["cycles"]}')


def cmd_set_acceptance_rate(args):
    data = load_active()
    data['acceptance_rate'] = float(args.value)
    save_active(data)
    print(f'acceptance_rate = {data["acceptance_rate"]}')


def _print_cycle_rows(report, tail=10):
    rows = report.get('cycles', [])[-tail:]
    if not rows:
        print('no cycle rows')
        return
    btc_price = report.get('params', {}).get('btc_price_usd', 85000)
    header = f"{'cycle':>5}  {'fast_users':>10}  {'revenue_usd':>11}  {'payout_pot_btc':>14}  {'pool_principal_btc':>18}  {'yield_btc':>9}  {'submissions':>11}"
    print(header)
    for r in rows:
        print(
            f"{r['cycle_id']:>5}  {r['fast_user_count']:>10}  "
            f"${r['fast_revenue_usd']:>10.2f}  {r['payout_pot_btc']:>14.8f}  "
            f"{r['pool_principal_btc']:>18.8f}  {r['cycle_yield_btc']:>9.8f}  "
            f"{r['accepted_submissions']:>11}"
        )


def _print_contributor_totals(report, btc_price=85000):
    contribs = report.get('contributors_final', {})
    if not contribs:
        print('no contributors')
        return
    print('\ncontributor totals (final):')
    for cid, meta in sorted(contribs.items(), key=lambda kv: kv[1].get('lifetime_votes', 0), reverse=True):
        total_btc = meta.get('total_payout_btc', 0) + meta.get('total_royalty_btc', 0)
        print(
            f"  {cid}: lifetime_votes={meta.get('lifetime_votes', 0):.1f}  "
            f"payout={meta.get('total_payout_btc', 0):.8f} BTC  "
            f"royalty={meta.get('total_royalty_btc', 0):.8f} BTC  "
            f"total~${total_btc * btc_price:.4f}"
        )


def cmd_run(args):
    data = load_active()
    sim_mod = load_sim_module()
    sim = sim_mod.Sim(params=data.get('params', {}), seed=int(data.get('seed', 42)))
    result = sim.run(data)
    out = Path(args.out) if args.out else DEFAULT_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2))
    print(json.dumps(result['summary'], indent=2))
    if args.verbose:
        _print_cycle_rows(result, tail=int(args.tail))
        _print_contributor_totals(result, btc_price=result['params'].get('btc_price_usd', 85000))
    print(f'report: {out}')


def cmd_status(args):
    report_path = Path(args.report) if args.report else DEFAULT_OUT
    if not report_path.exists():
        raise SystemExit(f'report not found: {report_path}  — run `run` first.')
    report = json.loads(report_path.read_text())
    print(json.dumps(report.get('summary', {}), indent=2))
    _print_cycle_rows(report, tail=int(args.tail))
    _print_contributor_totals(report, btc_price=report['params'].get('btc_price_usd', 85000))
    print(f'\nloaded report: {report_path}')


# ── parser ────────────────────────────────────────────────────────────────────

def build_parser():
    p = argparse.ArgumentParser(description='Layer 5 tokenomics CLI (v3.1)')
    sub = p.add_subparsers(dest='cmd', required=True)

    sub.add_parser('help')
    r = sub.add_parser('reset')
    r.add_argument('--source', default='baseline')

    sub.add_parser('show-params')
    sub.add_parser('show-scenario')

    sp = sub.add_parser('set-param')
    sp.add_argument('--key', required=True)
    sp.add_argument('--value', required=True, type=float)

    sfu = sub.add_parser('set-fast-users')
    sfu.add_argument('--value', required=True, type=int)

    sv = sub.add_parser('set-validators')
    sv.add_argument('--value', required=True, type=int)

    sc = sub.add_parser('set-cycles')
    sc.add_argument('--value', required=True, type=int)

    sar = sub.add_parser('set-acceptance-rate')
    sar.add_argument('--value', required=True, type=float)

    rr = sub.add_parser('run')
    rr.add_argument('--out', required=False)
    rr.add_argument('--verbose', action='store_true')
    rr.add_argument('--tail', required=False, type=int, default=10)

    st = sub.add_parser('status')
    st.add_argument('--report', required=False)
    st.add_argument('--tail', required=False, type=int, default=10)

    return p


def main():
    p = build_parser()
    args = p.parse_args()
    cmds = {
        'help': cmd_help,
        'reset': cmd_reset,
        'show-params': cmd_show_params,
        'show-scenario': cmd_show_scenario,
        'set-param': cmd_set_param,
        'set-fast-users': cmd_set_fast_users,
        'set-validators': cmd_set_validators,
        'set-cycles': cmd_set_cycles,
        'set-acceptance-rate': cmd_set_acceptance_rate,
        'run': cmd_run,
        'status': cmd_status,
    }
    cmds[args.cmd](args)


if __name__ == '__main__':
    main()
