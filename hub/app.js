const API = window.HUB_API_BASE || 'http://localhost:8787';
const installCmd = `git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "Local changes detected"; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh`;

document.getElementById('installCmd').textContent = installCmd;

let ACTIVE_ACCOUNT_ID = null;
let ACTIVE_SESSION_TOKEN = null;
let ACTIVE_WALLET_CHALLENGE = null;
let ALL_ACCOUNTS = [];

// ── API helpers ──────────────────────────────────────────────────────────────

function authHeaders() {
  return ACTIVE_SESSION_TOKEN ? { 'x-session-token': ACTIVE_SESSION_TOKEN } : {};
}

async function jget(path) {
  const res = await fetch(`${API}${path}`, { headers: authHeaders() });
  return res.json();
}

async function jpost(path, body) {
  const payload = { ...(body || {}) };
  if (ACTIVE_ACCOUNT_ID && !payload.actor_account_id) payload.actor_account_id = ACTIVE_ACCOUNT_ID;
  const res = await fetch(`${API}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...authHeaders() },
    body: JSON.stringify(payload)
  });
  return res.json();
}

function setResult(id, text, ok = true) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text;
  el.className = ok ? 'muted status-ok' : 'muted status-err';
}

function apiMsg(r, fallback = 'request_failed') {
  if (!r) return fallback;
  return r.error || r.message || fallback;
}

function rows(id, data, render, colspan = 4) {
  document.getElementById(id).innerHTML =
    (data || []).length ? data.map(render).join('') : `<tr><td colspan='${colspan}'>No data</td></tr>`;
}

function btcUsd(btc, btcPrice) {
  const usd = Number(btc) * Number(btcPrice || 85000);
  return `${Number(btc).toFixed(8)} BTC (~$${usd.toFixed(2)})`;
}

// ── Bootstrap ────────────────────────────────────────────────────────────────

async function establishSession(accountId) {
  if (!accountId) { ACTIVE_SESSION_TOKEN = null; return; }
  const s = await fetch(`${API}/hub/session/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account_id: accountId })
  }).then(r => r.json());
  if (!s.ok || !s.session_token) throw new Error(`session_create_failed:${apiMsg(s)}`);
  ACTIVE_SESSION_TOKEN = s.session_token;
}

async function bootstrapAccount() {
  const boot = await fetch(`${API}/hub/session/bootstrap`).then(r => r.json());
  ALL_ACCOUNTS = boot.accounts || [];
  const sel = document.getElementById('accountSelect');
  sel.innerHTML = ALL_ACCOUNTS.map(a => `<option value="${a.account_id}">${a.role} · ${a.account_id.slice(0, 8)}…</option>`).join('');
  ACTIVE_ACCOUNT_ID = boot.suggested_account_id || ALL_ACCOUNTS[0]?.account_id || null;
  if (ACTIVE_ACCOUNT_ID) sel.value = ACTIVE_ACCOUNT_ID;
  await establishSession(ACTIVE_ACCOUNT_ID);
  populateAccountSelects();

  sel.addEventListener('change', async () => {
    ACTIVE_ACCOUNT_ID = sel.value;
    await establishSession(ACTIVE_ACCOUNT_ID);
    await load();
  });
}

function populateAccountSelects() {
  ['dispenseAccountSelect', 'controlAccountSelect'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = ALL_ACCOUNTS.map(a => `<option value="${a.account_id}">${a.role} · ${a.account_id.slice(0, 8)}…</option>`).join('');
  });
}

// ── Load all panels ──────────────────────────────────────────────────────────

async function load() {
  await Promise.all([
    loadPoolState(),
    loadIdentity(),
    loadMachines(),
    loadLedger(),
    loadContributions(),
    loadLifetimeVotes(),
  ]);
}

async function loadPoolState() {
  try {
    const s = await jget('/hub/pool/state');
    const cur = s.current_cycle;
    const cfg = s.config || {};

    // Header card
    if (cur) {
      document.getElementById('cycleCard').textContent =
        `Cycle ${cur.cycle_id} · ${cur.status} · Pool $${(Number(cur.pool_principal_btc) * 85000).toFixed(0)}`;
    } else {
      document.getElementById('cycleCard').textContent = 'No cycles yet';
    }

    // Pool cards
    const bp = cur?.btc_price_usd || 85000;
    document.getElementById('poolPrincipal').textContent = cur
      ? `${Number(cur.pool_principal_btc).toFixed(8)} BTC\n~$${(Number(cur.pool_principal_btc) * bp).toFixed(2)}`
      : '--';
    document.getElementById('payoutPot').textContent = cur
      ? `${Number(cur.payout_pot_btc).toFixed(8)} BTC\n~$${(Number(cur.payout_pot_btc) * bp).toFixed(2)}`
      : '--';
    document.getElementById('cycleYield').textContent = cur
      ? `${Number(cur.cycle_yield_btc).toFixed(8)} BTC\n~$${(Number(cur.cycle_yield_btc) * bp).toFixed(4)}`
      : '--';
    document.getElementById('fastRevenue').textContent = cur
      ? `$${Number(cur.fast_revenue_usd).toFixed(2)} → ${Number(cur.fast_revenue_btc).toFixed(8)} BTC`
      : '--';
    document.getElementById('effectiveYield').textContent = cfg.effective_per_cycle_yield
      ? `${(cfg.effective_per_cycle_yield * 100).toFixed(3)}%/cycle\n(${(cfg.effective_per_cycle_yield * 12 * 100).toFixed(2)}% annual effective)`
      : '--';
    document.getElementById('cycleStatus').textContent = cur?.status || '--';

    // Fetch all cycles
    // We don't have a /hub/pool/all endpoint yet — load from SQL via a workaround
    // For now just show current if exists
    const allRows = cur ? [cur] : [];
    document.getElementById('allCyclesBody').innerHTML = allRows.length
      ? allRows.map(r => `<tr>
          <td>${r.cycle_id}</td>
          <td>${r.fast_user_count}</td>
          <td>$${Number(r.fast_revenue_usd).toFixed(2)}</td>
          <td>${Number(r.payout_pot_btc).toFixed(8)}</td>
          <td>${Number(r.pool_principal_btc).toFixed(8)}</td>
          <td>${Number(r.cycle_yield_btc).toFixed(8)}</td>
          <td>${r.status}</td>
        </tr>`).join('')
      : `<tr><td colspan="7">No cycles run yet. Go to Cycle tab.</td></tr>`;
  } catch (e) {
    document.getElementById('cycleCard').textContent = `Pool load error: ${e.message}`;
  }
}

async function loadIdentity() {
  try {
    const [identity, audit] = await Promise.all([
      jget('/hub/identity'),
      jget('/hub/audit/actions?limit=5')
    ]);
    const wi = identity.wallet_identity;
    const ctrl = identity?.account_control?.control_mode || 'normal';
    const verifyBadge = wi?.verification_status === 'verified'
      ? '<span class="badge badge-verified">verified</span>'
      : '<span class="badge badge-unverified">unverified</span>';
    const ctrlBadge = ctrl === 'blocked'
      ? '<span class="badge badge-blocked">blocked</span>'
      : ctrl === 'slow'
        ? '<span class="badge badge-slow">slow</span>'
        : '<span class="badge">normal</span>';
    document.getElementById('identityCard').innerHTML = identity.ok
      ? `${ACTIVE_ACCOUNT_ID?.slice(0, 8) || '--'}… · ${ctrlBadge} · ${verifyBadge}${wi?.wallet_address ? ` · ${wi.wallet_address.slice(0, 10)}…` : ''}`
      : `Identity unavailable`;

    if (wi?.verification_status === 'verified') {
      ACTIVE_WALLET_CHALLENGE = null;
      document.getElementById('walletChallengeMessage').textContent = 'Wallet verified.';
    }

    const auditItems = (audit?.data || []).map(a => `${a.action}@${a.created_at?.slice(11, 19) || '--'}`);
    document.getElementById('actionTrailSummary').textContent = `Recent actions: ${auditItems.join(' · ') || 'none'}`;
  } catch (_e) {}
}

async function loadMachines() {
  try {
    const m = await jget('/hub/machines');
    rows('machinesBody', m.data, r =>
      `<tr><td title="${r.machine_id}">${r.machine_id.slice(0, 12)}…</td><td>${r.plan}</td><td>${r.fast_cycle_fee ?? '--'}</td><td>${r.last_burn_cycle_id ?? '-'}</td></tr>`);
  } catch (_e) {}
}

async function loadLedger() {
  try {
    const l = await jget('/hub/rewards/ledger?limit=30');
    rows('ledgerBody', l.data, e =>
      `<tr><td>${e.event_type}</td><td>${e.bucket}</td><td>${e.amount}</td><td>${e.cycle_id}</td></tr>`);
  } catch (_e) {}
}

async function loadContributions() {
  try {
    const c = await jget('/hub/contributions');
    rows('contribBody', c.data, s =>
      `<tr><td title="${s.submission_id}">${s.submission_id?.slice(0, 8) || '--'}…</td><td>${s.title}</td><td>${s.class}</td><td>${s.state}</td><td>${s.verdict ?? '-'}</td></tr>`, 5);
  } catch (_e) {}
}

async function loadLifetimeVotes() {
  try {
    const lv = await jget('/hub/contributors/lifetime-votes');
    document.getElementById('allLifetimeVotesDisplay').textContent =
      `Global lifetime votes: ${Number(lv.all_lifetime_votes || 0).toFixed(2)}`;
    rows('lifetimeVotesBody', lv.data, r =>
      `<tr>
        <td title="${r.account_id}">${r.account_id?.slice(0, 8) || '--'}…</td>
        <td>${Number(r.lifetime_votes).toFixed(2)}</td>
        <td>${r.lifetime_share_pct}%</td>
        <td>${Number(r.total_payout_btc || 0).toFixed(8)}</td>
        <td>${Number(r.total_royalty_btc || 0).toFixed(8)}</td>
        <td>${r.cooldown_remaining > 0 ? `${r.cooldown_remaining} cycles` : '—'}</td>
      </tr>`, 6);
  } catch (_e) {}
}

// ── Cycle runner ─────────────────────────────────────────────────────────────

document.getElementById('runCycleV31Btn').addEventListener('click', async () => {
  try {
    const cycle_id = Number(document.getElementById('cycleIdInput').value);
    const fast_user_count = Number(document.getElementById('fastUserCountInput').value || 5);
    const btcPrice = document.getElementById('btcPriceInput').value;
    const body = { cycle_id, fast_user_count };
    if (btcPrice) body.btc_price_usd = Number(btcPrice);
    if (!Number.isFinite(cycle_id)) {
      setResult('runCycleResult', 'Enter a valid cycle id.', false); return;
    }
    const r = await jpost('/hub/cycle/run-v31', body);
    setResult('runCycleResult',
      r.ok
        ? `Cycle ${r.cycle_id} opened.\nFast revenue: $${r.fast_revenue_usd} → ${r.fast_revenue_btc} BTC\nPayout pot: ${r.payout_pot_btc} BTC ($${r.payout_pot_usd})\nPool inflow: ${r.pool_inflow_btc} BTC\nPool principal: ${r.pool_principal_btc} BTC ($${r.pool_principal_usd})\nBabylon yield: ${r.cycle_yield_btc} BTC ($${r.cycle_yield_usd})`
        : `Error: ${apiMsg(r)}`,
      r.ok);
    if (r.ok) await load();
  } catch (e) {
    setResult('runCycleResult', `Error: ${e.message}`, false);
  }
});

document.getElementById('closeCycleBtn').addEventListener('click', async () => {
  try {
    const cycle_id = Number(document.getElementById('closeCycleIdInput').value);
    if (!Number.isFinite(cycle_id)) {
      setResult('closeCycleResult', 'Enter a valid cycle id.', false); return;
    }
    const r = await jpost('/hub/cycle/close-v31', { cycle_id });
    if (r.ok) {
      const payoutLines = (r.payouts || []).map(p =>
        `  ${p.account_id?.slice(0, 8)}… vote_share=${p.vote_share_pct}% payout=${p.payout_btc} BTC royalty=${p.royalty_btc} BTC`
      ).join('\n');
      setResult('closeCycleResult',
        `Cycle ${r.cycle_id} settled.\nTotal votes: ${r.total_cycle_votes}\nQualifying submissions: ${r.qualifying_submissions}\n\nPayouts:\n${payoutLines || '  (none)'}`,
        true);
      await load();
    } else {
      setResult('closeCycleResult', `Error: ${apiMsg(r)}`, false);
    }
  } catch (e) {
    setResult('closeCycleResult', `Error: ${e.message}`, false);
  }
});

// ── Contribution voting ───────────────────────────────────────────────────────

let currentVoteCycleId = null;
let currentSubmissionsForVote = [];

document.getElementById('loadSubmissionsForVoteBtn').addEventListener('click', async () => {
  try {
    const cid = Number(document.getElementById('voteCycleIdInput').value);
    if (!Number.isFinite(cid)) return;
    currentVoteCycleId = cid;
    const c = await jget('/hub/contributions');
    const subs = (c.data || []).filter(s => ['stake_locked', 'accepted', 'pending'].includes(s.state));
    currentSubmissionsForVote = subs;

    const allocDiv = document.getElementById('voteAllocatorRows');
    if (subs.length === 0) {
      allocDiv.innerHTML = '<p class="muted">No submissions available for this cycle.</p>';
      document.getElementById('voteAllocator').style.display = 'block';
      return;
    }

    allocDiv.innerHTML = subs.map(s => `
      <div class="inline-form" style="margin:4px 0">
        <span style="width:280px;display:inline-block" title="${s.submission_id}">${s.title} (${s.class}) · ${s.submission_id?.slice(0,8)}…</span>
        <input type="number" min="0" max="100" step="1" value="0"
          id="votePoints_${s.submission_id}" data-subid="${s.submission_id}"
          style="width:70px" class="vote-points-input" />
        <span>pts</span>
      </div>`).join('');

    document.getElementById('voteAllocator').style.display = 'block';

    // Live points counter
    document.querySelectorAll('.vote-points-input').forEach(inp => {
      inp.addEventListener('input', updatePointsRemaining);
    });
    updatePointsRemaining();
  } catch (e) {
    alert(`Load submissions error: ${e.message}`);
  }
});

function updatePointsRemaining() {
  const inputs = document.querySelectorAll('.vote-points-input');
  const used = Array.from(inputs).reduce((s, i) => s + Number(i.value || 0), 0);
  const el = document.getElementById('votePointsRemaining');
  el.textContent = `Points used: ${used} / 100`;
  el.className = used > 100 ? 'muted status-err' : 'muted';
}

document.getElementById('submitVotesBtn').addEventListener('click', async () => {
  try {
    if (!currentVoteCycleId) {
      setResult('voteSubmitResult', 'Load submissions first.', false); return;
    }
    const inputs = document.querySelectorAll('.vote-points-input');
    const allocations = Array.from(inputs)
      .map(i => ({ submission_id: i.dataset.subid, points: Number(i.value || 0) }))
      .filter(a => a.points > 0);

    const total = allocations.reduce((s, a) => s + a.points, 0);
    if (total > 100.001) {
      setResult('voteSubmitResult', `Total points (${total}) exceeds 100. Reduce your allocation.`, false); return;
    }
    if (allocations.length === 0) {
      setResult('voteSubmitResult', 'Allocate at least some points.', false); return;
    }

    const r = await jpost('/hub/contributions/votes', { cycle_id: currentVoteCycleId, allocations });
    setResult('voteSubmitResult',
      r.ok ? `Vote submitted. ${r.total_points_used.toFixed(1)} / 100 points used.` : `Error: ${apiMsg(r)}`,
      r.ok);
  } catch (e) {
    setResult('voteSubmitResult', `Error: ${e.message}`, false);
  }
});

document.getElementById('loadVoteTotalsBtn').addEventListener('click', async () => {
  try {
    const cid = Number(document.getElementById('voteViewCycleId').value);
    if (!Number.isFinite(cid)) return;
    const r = await jget(`/hub/contributions/votes?cycle_id=${cid}`);
    rows('voteTotalsBody', r.data, row =>
      `<tr>
        <td title="${row.submission_id}">${row.submission_id?.slice(0, 12)}…</td>
        <td>${Number(row.total_points).toFixed(1)}</td>
        <td>${row.vote_share_pct}%</td>
        <td>${row.voter_count}</td>
      </tr>`, 4);
  } catch (e) {
    rows('voteTotalsBody', [], _ => '', 4);
  }
});

// ── Lifetime votes ────────────────────────────────────────────────────────────

document.getElementById('refreshLifetimeBtn').addEventListener('click', loadLifetimeVotes);

// ── Submissions ───────────────────────────────────────────────────────────────

document.getElementById('createContribBtn').addEventListener('click', async () => {
  try {
    const r = await jpost('/hub/contributions', {
      account_id: ACTIVE_ACCOUNT_ID,
      submission_hash: document.getElementById('contribHash').value.trim(),
      title: document.getElementById('contribTitle').value.trim(),
      class_name: document.getElementById('contribClass').value,
    });
    setResult('createContribResult', r.ok ? 'Submission created.' : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) await loadContributions();
  } catch (e) {
    setResult('createContribResult', `Error: ${e.message}`, false);
  }
});

// ── Identity ──────────────────────────────────────────────────────────────────

document.getElementById('bindWalletBtn').addEventListener('click', async () => {
  try {
    const wallet_address = document.getElementById('walletAddressInput').value.trim();
    const chain_id = document.getElementById('walletChainInput').value.trim() || 'evm:1';
    if (!wallet_address) { setResult('bindWalletResult', 'Enter a wallet address.', false); return; }
    const r = await jpost('/hub/identity/wallet/bind', { account_id: ACTIVE_ACCOUNT_ID, wallet_address, chain_id });
    setResult('bindWalletResult', r.ok ? `Bound (unverified). Sign to verify.` : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) await loadIdentity();
  } catch (e) {
    setResult('bindWalletResult', `Error: ${e.message}`, false);
  }
});

document.getElementById('walletChallengeBtn').addEventListener('click', async () => {
  try {
    const r = await jpost('/hub/identity/wallet/challenge', { account_id: ACTIVE_ACCOUNT_ID });
    if (r.ok) {
      ACTIVE_WALLET_CHALLENGE = r;
      document.getElementById('walletChallengeMessage').textContent = r.message;
      setResult('walletVerifyResult', 'Challenge generated. Sign with your wallet.', true);
    } else {
      setResult('walletVerifyResult', `Error: ${apiMsg(r)}`, false);
    }
  } catch (e) {
    setResult('walletVerifyResult', `Error: ${e.message}`, false);
  }
});

document.getElementById('walletVerifyBtn').addEventListener('click', async () => {
  try {
    const signature = document.getElementById('walletSignatureInput').value.trim();
    if (!signature) { setResult('walletVerifyResult', 'Paste signature first.', false); return; }
    if (!ACTIVE_WALLET_CHALLENGE?.nonce) { setResult('walletVerifyResult', 'Generate a challenge first.', false); return; }
    const r = await jpost('/hub/identity/wallet/verify', { account_id: ACTIVE_ACCOUNT_ID, signature });
    setResult('walletVerifyResult', r.ok ? 'Wallet verified.' : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) { document.getElementById('walletSignatureInput').value = ''; await loadIdentity(); }
  } catch (e) {
    setResult('walletVerifyResult', `Error: ${e.message}`, false);
  }
});

// ── Admin ──────────────────────────────────────────────────────────────────────

document.getElementById('dispenseBtn').addEventListener('click', async () => {
  try {
    const account_id = document.getElementById('dispenseAccountSelect').value;
    const amount_usd = Number(document.getElementById('dispenseAmountUsd').value);
    if (!account_id || !amount_usd) { setResult('dispenseResult', 'Select account and amount.', false); return; }
    const r = await jpost('/hub/admin/dispense', { account_id, amount_usd });
    setResult('dispenseResult',
      r.ok ? `Dispensed $${r.dispensed_usd} → ${r.dispensed_btc} BTC (at $${r.btc_price_used}/BTC)` : `Error: ${apiMsg(r)}`,
      r.ok);
    if (r.ok) await loadLedger();
  } catch (e) {
    setResult('dispenseResult', `Error: ${e.message}`, false);
  }
});

document.getElementById('setPlanBtn').addEventListener('click', async () => {
  try {
    const machineId = document.getElementById('planMachineId').value.trim();
    const plan = document.getElementById('planValue').value;
    const r = await jpost(`/hub/machines/${encodeURIComponent(machineId)}/plan`, { plan });
    setResult('setPlanResult', r.ok ? 'Plan updated.' : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) await loadMachines();
  } catch (e) {
    setResult('setPlanResult', `Error: ${e.message}`, false);
  }
});

document.getElementById('setControlBtn').addEventListener('click', async () => {
  try {
    const account_id = document.getElementById('controlAccountSelect').value;
    const control_mode = document.getElementById('controlMode').value;
    const reason = document.getElementById('controlReason').value.trim() || null;
    const r = await jpost('/hub/admin/account-controls/set', { account_id, control_mode, reason });
    setResult('setControlResult', r.ok ? `Control set: ${control_mode}` : `Error: ${apiMsg(r)}`, r.ok);
  } catch (e) {
    setResult('setControlResult', `Error: ${e.message}`, false);
  }
});

// ── Tabs ──────────────────────────────────────────────────────────────────────

document.querySelectorAll('#tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    document.getElementById(btn.dataset.tab).classList.add('active');
  });
});

// ── Init ──────────────────────────────────────────────────────────────────────

bootstrapAccount()
  .then(load)
  .catch(err => {
    document.getElementById('cycleCard').textContent = `API error: ${err.message}`;
  });
