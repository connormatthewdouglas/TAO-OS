const API = window.HUB_API_BASE || 'http://localhost:8787';
const installCmd = `git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "Local changes detected"; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh`;
document.getElementById('installCmd').textContent = installCmd;

let ACTIVE_ACCOUNT_ID = null;
let ACTIVE_SESSION_TOKEN = null;
let ACTIVE_WALLET_CHALLENGE = null;
let ACTIVE_ROLE = null;
let ALL_ACCOUNTS = [];
let CURRENT_OPEN_CYCLE_ID = null;

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

function setLoading(id, msg = 'Loading…') {
  const el = document.getElementById(id);
  if (el) { el.innerHTML = `<tr><td colspan="99"><span class="loading">${msg}</span></td></tr>`; }
}

function apiMsg(r, fallback = 'Something went wrong') {
  if (!r) return fallback;
  return r.error || r.message || fallback;
}

function rows(id, data, render, colspan = 4) {
  const el = document.getElementById(id);
  if (!el) return;
  el.innerHTML = (data || []).length
    ? data.map(render).join('')
    : `<tr><td colspan='${colspan}' style='color:var(--muted)'>Nothing here yet</td></tr>`;
}

function shortId(id) {
  return id ? id.slice(0, 8) + '…' : '--';
}

function friendlyRole(role) {
  return { mixed: 'Admin', validator: 'Validator', contributor: 'Contributor', consumer: 'Fast User' }[role] || role;
}

function friendlyState(state) {
  return {
    stake_locked: 'Pending Review',
    accepted: 'Accepted',
    rejected: 'Rejected',
    settled: 'Settled',
    pending: 'Pending',
  }[state] || state;
}

function accountLabel(a) {
  return `${a.username ? a.username : friendlyRole(a.role)} · ${shortId(a.account_id)}`;
}

// ── Bootstrap ────────────────────────────────────────────────────────────────

async function establishSession(accountId) {
  if (!accountId) { ACTIVE_SESSION_TOKEN = null; return; }
  const s = await fetch(`${API}/hub/session/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account_id: accountId })
  }).then(r => r.json());
  if (!s.ok || !s.session_token) throw new Error(`Session failed: ${apiMsg(s)}`);
  ACTIVE_SESSION_TOKEN = s.session_token;
}

async function bootstrapAccount() {
  const boot = await fetch(`${API}/hub/session/bootstrap`).then(r => r.json());
  ALL_ACCOUNTS = boot.accounts || [];
  const sel = document.getElementById('accountSelect');
  sel.innerHTML = ALL_ACCOUNTS.map(a => `<option value="${a.account_id}">${accountLabel(a)}</option>`).join('');
  ACTIVE_ACCOUNT_ID = boot.suggested_account_id || ALL_ACCOUNTS[0]?.account_id || null;
  ACTIVE_ROLE = ALL_ACCOUNTS.find(a => a.account_id === ACTIVE_ACCOUNT_ID)?.role || null;
  if (ACTIVE_ACCOUNT_ID) sel.value = ACTIVE_ACCOUNT_ID;
  await establishSession(ACTIVE_ACCOUNT_ID);
  populateAccountSelects();

  sel.addEventListener('change', async () => {
    ACTIVE_ACCOUNT_ID = sel.value;
    ACTIVE_ROLE = ALL_ACCOUNTS.find(a => a.account_id === ACTIVE_ACCOUNT_ID)?.role || null;
    await establishSession(ACTIVE_ACCOUNT_ID);
    await load();
  });
}

function populateAccountSelects() {
  ['dispenseAccountSelect', 'controlAccountSelect', 'deleteAccountSelect'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.innerHTML = ALL_ACCOUNTS.map(a =>
      `<option value="${a.account_id}">${accountLabel(a)}</option>`
    ).join('');
  });
}

// ── Load all panels ──────────────────────────────────────────────────────────

async function load() {
  await Promise.all([
    loadPoolState(),
    loadIdentity(),
    loadBalance(),
    loadMachines(),
    loadLedger(),
    loadContributions(),
    loadLifetimeVotes(),
  ]);
}

// ── Balance bar ──────────────────────────────────────────────────────────────

async function loadBalance() {
  try {
    const b = await jget('/hub/rewards/my-balance');
    const bar = document.getElementById('balanceBar');
    if (!bar) return;
    if (b.ok) {
      bar.innerHTML = `
        <span class="bal-label">Your balance</span>
        <span class="bal-value">${Number(b.balance_btc).toFixed(8)} BTC</span>
        <span class="bal-label">~$${b.balance_usd}</span>
        <span style="margin-left:16px;border-left:1px solid var(--line);padding-left:16px" class="bal-label">Total earned (payouts + royalties)</span>
        <span class="bal-value">${Number(b.total_earned_btc).toFixed(8)} BTC</span>
        <span class="bal-label">~$${b.total_earned_usd}</span>`;
    } else {
      bar.innerHTML = `<span class="bal-label">Balance unavailable</span>`;
    }
  } catch (_e) {}
}

// ── Pool state ───────────────────────────────────────────────────────────────

async function loadPoolState() {
  try {
    const [s, hist] = await Promise.all([
      jget('/hub/pool/state'),
      jget('/hub/pool/cycles'),
    ]);
    const cur = s.current_cycle;
    const cfg = s.config || {};
    if (cur?.status === 'open') CURRENT_OPEN_CYCLE_ID = cur.cycle_id;
    const bp = cur?.btc_price_usd || cfg.btc_price_usd || 85000;

    document.getElementById('cycleCard').textContent = cur
      ? `Cycle ${cur.cycle_id} · ${cur.status} · Pool $${(Number(cur.pool_principal_btc) * bp).toFixed(0)}`
      : 'No cycles yet';

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
      ? `$${Number(cur.fast_revenue_usd).toFixed(2)} USD → ${Number(cur.fast_revenue_btc).toFixed(8)} BTC`
      : '--';
    document.getElementById('effectiveYield').textContent = cfg.effective_per_cycle_yield
      ? `${(cfg.effective_per_cycle_yield * 100).toFixed(3)}%/cycle\n(${(cfg.effective_per_cycle_yield * 12 * 100).toFixed(2)}% annually)`
      : '--';
    document.getElementById('cycleStatus').textContent = cur ? (cur.status === 'open' ? 'Open — accepting votes' : 'Closed') : '--';

    const allCycles = hist.data || (cur ? [cur] : []);
    rows('allCyclesBody', allCycles, r => `<tr>
      <td>${r.cycle_id}</td>
      <td>${r.fast_user_count}</td>
      <td>$${Number(r.fast_revenue_usd).toFixed(2)}</td>
      <td>${Number(r.payout_pot_btc).toFixed(8)}</td>
      <td>${Number(r.pool_principal_btc).toFixed(8)}</td>
      <td>${Number(r.cycle_yield_btc).toFixed(8)}</td>
      <td><span class="badge ${r.status === 'open' ? 'badge-verified' : ''}">${r.status}</span></td>
    </tr>`, 7);
  } catch (e) {
    document.getElementById('cycleCard').textContent = `Error loading pool: ${e.message}`;
  }
}

// ── Identity ──────────────────────────────────────────────────────────────────

async function loadIdentity() {
  try {
    const [identity, audit] = await Promise.all([
      jget('/hub/identity'),
      jget('/hub/audit/actions?limit=5')
    ]);
    const wi = identity.wallet_identity;
    const ctrl = identity?.account_control?.control_mode || 'normal';
    const verifyBadge = wi?.verification_status === 'verified'
      ? '<span class="badge badge-verified">Wallet Verified</span>'
      : '<span class="badge badge-unverified">Wallet Not Verified</span>';
    const ctrlBadge = ctrl === 'blocked'
      ? '<span class="badge badge-blocked">Blocked</span>'
      : ctrl === 'slow' ? '<span class="badge badge-slow">Slow Mode</span>' : '';

    document.getElementById('identityCard').innerHTML = identity.ok
      ? `${friendlyRole(ACTIVE_ROLE)} · ${shortId(ACTIVE_ACCOUNT_ID)} ${ctrlBadge} ${verifyBadge}${wi?.wallet_address ? ` · ${wi.wallet_address.slice(0, 12)}…` : ''}`
      : 'Identity unavailable';

    if (wi?.verification_status === 'verified') {
      ACTIVE_WALLET_CHALLENGE = null;
      document.getElementById('walletChallengeMessage').textContent = 'Wallet verified.';
    }

    const auditItems = (audit?.data || []).map(a => `${a.action} at ${a.created_at?.slice(11, 19) || '--'}`);
    document.getElementById('actionTrailSummary').textContent =
      `Recent actions: ${auditItems.join(' · ') || 'none yet'}`;
  } catch (_e) {}
}

// ── Machines ──────────────────────────────────────────────────────────────────

async function loadMachines() {
  try {
    const m = await jget('/hub/machines');
    rows('machinesBody', m.data, r => `<tr>
      <td title="${r.machine_id}">${shortId(r.machine_id)}</td>
      <td>${r.plan === 'fast' ? '⚡ Fast' : '🔵 Stable'}</td>
      <td>${r.fast_cycle_fee ?? '--'}</td>
      <td>${r.last_burn_cycle_id ?? 'Never'}</td>
    </tr>`);
  } catch (_e) {}
}

// ── Ledger ────────────────────────────────────────────────────────────────────

async function loadLedger() {
  try {
    const l = await jget('/hub/rewards/ledger?limit=30');
    const friendlyType = t => ({
      test_dispense: 'Test funds added',
      fast_burn: 'Fast plan fee',
      contributor_payout: 'Contribution payout',
      contributor_royalty: 'Yield royalty',
    }[t] || t);
    rows('ledgerBody', l.data, e => `<tr>
      <td>${friendlyType(e.event_type)}</td>
      <td>${e.bucket}</td>
      <td>${Number(e.amount).toFixed(8)}</td>
      <td>${e.cycle_id || '--'}</td>
    </tr>`);
  } catch (_e) {}
}

// ── Contributions ─────────────────────────────────────────────────────────────

async function loadContributions() {
  try {
    const c = await jget('/hub/contributions');
    const isValidator = ACTIVE_ROLE === 'validator' || ACTIVE_ROLE === 'mixed';
    rows('contribBody', c.data, s => {
      const verdictBtns = isValidator
        ? `<button class="btn-sm btn-accept" onclick="setVerdict('${s.submission_id}','accepted')">Accept</button>
           <button class="btn-sm btn-reject" onclick="setVerdict('${s.submission_id}','rejected')">Reject</button>`
        : '';
      return `<tr>
        <td title="${s.submission_id}">${shortId(s.submission_id)}</td>
        <td>${s.title}</td>
        <td>${s.class}</td>
        <td><span class="badge">${friendlyState(s.state)}</span></td>
        <td>${verdictBtns}</td>
      </tr>`;
    }, 5);
  } catch (_e) {}
}

// ── Lifetime votes ────────────────────────────────────────────────────────────

async function loadLifetimeVotes() {
  try {
    const lv = await jget('/hub/contributors/lifetime-votes');
    document.getElementById('allLifetimeVotesDisplay').textContent =
      `Total lifetime votes across all contributors: ${Number(lv.all_lifetime_votes || 0).toFixed(2)}`;
    const acctMap = Object.fromEntries(ALL_ACCOUNTS.map(a => [a.account_id, a.username || friendlyRole(a.role)]));
    rows('lifetimeVotesBody', lv.data, r => `<tr>
      <td title="${r.account_id}">${acctMap[r.account_id] || shortId(r.account_id)}</td>
      <td>${Number(r.lifetime_votes).toFixed(2)}</td>
      <td>${r.lifetime_share_pct}%</td>
      <td>${Number(r.total_payout_btc || 0).toFixed(8)}</td>
      <td>${Number(r.total_royalty_btc || 0).toFixed(8)}</td>
      <td>${r.cooldown_remaining > 0 ? `${r.cooldown_remaining} cycles` : '—'}</td>
    </tr>`, 6);
  } catch (_e) {}
}

// ── Verdict (accept / reject submission) ─────────────────────────────────────

window.setVerdict = async function(submissionId, verdict) {
  try {
    const r = await jpost(`/hub/contributions/${submissionId}/verdict`, { verdict });
    if (r.ok) await loadContributions();
    else alert(`Could not set verdict: ${apiMsg(r)}`);
  } catch (e) {
    alert(`Error: ${e.message}`);
  }
};

// ── Cycle runner ─────────────────────────────────────────────────────────────

document.getElementById('runCycleV31Btn').addEventListener('click', async () => {
  try {
    const cycle_id = Number(document.getElementById('cycleIdInput').value);
    const fast_user_count = Number(document.getElementById('fastUserCountInput').value || 5);
    const btcPrice = document.getElementById('btcPriceInput').value;
    if (!Number.isFinite(cycle_id) || cycle_id <= 0) {
      setResult('runCycleResult', 'Enter a valid cycle number.', false); return;
    }
    const body = { cycle_id, fast_user_count };
    if (btcPrice) body.btc_price_usd = Number(btcPrice);
    const r = await jpost('/hub/cycle/run-v31', body);
    setResult('runCycleResult',
      r.ok
        ? `Cycle ${r.cycle_id} is now open.\n\nRevenue: $${r.fast_revenue_usd}\n60% payout pot: ${r.payout_pot_btc} BTC (~$${r.payout_pot_usd})\n40% locked in pool: ${r.pool_inflow_btc} BTC\nPool total: ${r.pool_principal_btc} BTC (~$${r.pool_principal_usd})\nBabylon yield this cycle: ${r.cycle_yield_btc} BTC (~$${r.cycle_yield_usd})`
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
    if (!Number.isFinite(cycle_id) || cycle_id <= 0) {
      setResult('closeCycleResult', 'Enter a valid cycle number.', false); return;
    }
    const r = await jpost('/hub/cycle/close-v31', { cycle_id });
    if (r.ok) {
      const lines = (r.payouts || []).map(p =>
        `  ${shortId(p.account_id)} — vote share: ${p.vote_share_pct}% — payout: ${p.payout_btc} BTC${Number(p.royalty_btc) > 0 ? ` + ${p.royalty_btc} BTC yield royalty` : ''}`
      ).join('\n');
      setResult('closeCycleResult',
        `Cycle ${r.cycle_id} closed and settled.\nTotal votes cast: ${r.total_cycle_votes}\nQualifying submissions: ${r.qualifying_submissions}\n\nPayouts:\n${lines || '  (no qualifying submissions this cycle)'}`,
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

document.getElementById('loadSubmissionsForVoteBtn').addEventListener('click', async () => {
  try {
    const cid = Number(document.getElementById('voteCycleIdInput').value);
    if (!Number.isFinite(cid)) return;
    currentVoteCycleId = cid;

    const c = await jget('/hub/contributions');
    // Show accepted submissions for voting
    const accepted = (c.data || []).filter(s => s.state === 'accepted' || s.state === 'stake_locked');

    const allocDiv = document.getElementById('voteAllocatorRows');
    if (accepted.length === 0) {
      allocDiv.innerHTML = '<p class="muted">No accepted submissions found. Accept submissions in the Submissions tab first.</p>';
      document.getElementById('voteAllocator').style.display = 'block';
      return;
    }

    allocDiv.innerHTML = accepted.map(s => `
      <div class="inline-form" style="margin:4px 0;align-items:center">
        <span style="width:300px;display:inline-block;font-size:13px" title="${s.submission_id}">
          <b>${s.title}</b> <span style="color:var(--muted)">(${s.class})</span>
        </span>
        <input type="number" min="0" max="100" step="1" value="0"
          id="votePoints_${s.submission_id}" data-subid="${s.submission_id}"
          style="width:70px" class="vote-points-input" />
        <span style="color:var(--muted);font-size:12px">pts</span>
      </div>`).join('');

    document.getElementById('voteAllocator').style.display = 'block';
    document.querySelectorAll('.vote-points-input').forEach(inp => {
      inp.addEventListener('input', updatePointsRemaining);
    });
    updatePointsRemaining();
  } catch (e) {
    alert(`Error loading submissions: ${e.message}`);
  }
});

function updatePointsRemaining() {
  const inputs = document.querySelectorAll('.vote-points-input');
  const used = Array.from(inputs).reduce((s, i) => s + Number(i.value || 0), 0);
  const el = document.getElementById('votePointsRemaining');
  el.textContent = `Points used: ${used} / 100${used > 100 ? ' — too many! Reduce before submitting.' : ''}`;
  el.className = used > 100 ? 'muted status-err' : 'muted';
}

document.getElementById('submitVotesBtn').addEventListener('click', async () => {
  try {
    if (!currentVoteCycleId) { setResult('voteSubmitResult', 'Load submissions first.', false); return; }
    const inputs = document.querySelectorAll('.vote-points-input');
    const allocations = Array.from(inputs)
      .map(i => ({ submission_id: i.dataset.subid, points: Number(i.value || 0) }))
      .filter(a => a.points > 0);
    const total = allocations.reduce((s, a) => s + a.points, 0);
    if (total > 100.001) { setResult('voteSubmitResult', `Total points (${total}) exceeds 100.`, false); return; }
    if (!allocations.length) { setResult('voteSubmitResult', 'Allocate at least some points first.', false); return; }
    const r = await jpost('/hub/contributions/votes', { cycle_id: currentVoteCycleId, allocations });
    setResult('voteSubmitResult',
      r.ok ? `Vote submitted. You used ${r.total_points_used.toFixed(1)} out of 100 points.` : `Error: ${apiMsg(r)}`,
      r.ok);
  } catch (e) { setResult('voteSubmitResult', `Error: ${e.message}`, false); }
});

document.getElementById('loadVoteTotalsBtn').addEventListener('click', async () => {
  try {
    const cid = Number(document.getElementById('voteViewCycleId').value);
    if (!Number.isFinite(cid)) return;
    const r = await jget(`/hub/contributions/votes?cycle_id=${cid}`);
    rows('voteTotalsBody', r.data, row => `<tr>
      <td title="${row.submission_id}">${shortId(row.submission_id)}</td>
      <td>${Number(row.total_points).toFixed(1)}</td>
      <td>${row.vote_share_pct}%</td>
      <td>${row.voter_count}</td>
    </tr>`, 4);
  } catch (_e) { rows('voteTotalsBody', [], _ => '', 4); }
});

// ── Lifetime votes ────────────────────────────────────────────────────────────

document.getElementById('refreshLifetimeBtn').addEventListener('click', loadLifetimeVotes);

// ── Submissions ───────────────────────────────────────────────────────────────

document.getElementById('createContribBtn').addEventListener('click', async () => {
  try {
    const hash = document.getElementById('contribHash').value.trim();
    const title = document.getElementById('contribTitle').value.trim();
    if (!hash || !title) { setResult('createContribResult', 'Fill in both the submission ID and title.', false); return; }
    const r = await jpost('/hub/contributions', {
      account_id: ACTIVE_ACCOUNT_ID,
      submission_hash: hash,
      title,
      class_name: document.getElementById('contribClass').value,
    });
    setResult('createContribResult', r.ok ? 'Submission received. A validator will review it.' : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) { document.getElementById('contribHash').value = ''; document.getElementById('contribTitle').value = ''; await loadContributions(); }
  } catch (e) { setResult('createContribResult', `Error: ${e.message}`, false); }
});

// ── Identity ──────────────────────────────────────────────────────────────────

document.getElementById('setUsernameBtn').addEventListener('click', async () => {
  try {
    const username = document.getElementById('usernameInput').value.trim();
    if (!username) { setResult('setUsernameResult', 'Enter a name first.', false); return; }
    const r = await jpost('/hub/accounts/username', { username });
    if (r.ok) {
      setResult('setUsernameResult', `Name set to "${r.username}". Reload to see it in the account switcher.`, true);
      // Update local account list so selector reflects it immediately
      const a = ALL_ACCOUNTS.find(x => x.account_id === ACTIVE_ACCOUNT_ID);
      if (a) a.username = r.username;
      const sel = document.getElementById('accountSelect');
      sel.innerHTML = ALL_ACCOUNTS.map(a => `<option value="${a.account_id}">${accountLabel(a)}</option>`).join('');
      sel.value = ACTIVE_ACCOUNT_ID;
      populateAccountSelects();
    } else {
      setResult('setUsernameResult', `Error: ${apiMsg(r)}`, false);
    }
  } catch (e) { setResult('setUsernameResult', `Error: ${e.message}`, false); }
});

document.getElementById('bindWalletBtn').addEventListener('click', async () => {
  try {
    const wallet_address = document.getElementById('walletAddressInput').value.trim();
    const chain_id = document.getElementById('walletChainInput').value.trim() || 'evm:1';
    if (!wallet_address) { setResult('bindWalletResult', 'Enter your wallet address first.', false); return; }
    const r = await jpost('/hub/identity/wallet/bind', { account_id: ACTIVE_ACCOUNT_ID, wallet_address, chain_id });
    setResult('bindWalletResult',
      r.ok ? 'Wallet saved. Now click "Generate Challenge" and sign the message to verify you own it.' : `Error: ${apiMsg(r)}`,
      r.ok);
    if (r.ok) await loadIdentity();
  } catch (e) { setResult('bindWalletResult', `Error: ${e.message}`, false); }
});

document.getElementById('walletChallengeBtn').addEventListener('click', async () => {
  try {
    const r = await jpost('/hub/identity/wallet/challenge', { account_id: ACTIVE_ACCOUNT_ID });
    if (r.ok) {
      ACTIVE_WALLET_CHALLENGE = r;
      document.getElementById('walletChallengeMessage').textContent = r.message;
      setResult('walletVerifyResult', 'Sign this exact message with your wallet app, then paste the result below and click Verify.', true);
    } else {
      setResult('walletVerifyResult', `Error: ${apiMsg(r)}`, false);
    }
  } catch (e) { setResult('walletVerifyResult', `Error: ${e.message}`, false); }
});

document.getElementById('walletVerifyBtn').addEventListener('click', async () => {
  try {
    const signature = document.getElementById('walletSignatureInput').value.trim();
    if (!signature) { setResult('walletVerifyResult', 'Paste your signed message first.', false); return; }
    if (!ACTIVE_WALLET_CHALLENGE?.nonce) { setResult('walletVerifyResult', 'Generate a challenge first.', false); return; }
    const r = await jpost('/hub/identity/wallet/verify', { account_id: ACTIVE_ACCOUNT_ID, signature });
    setResult('walletVerifyResult', r.ok ? 'Wallet verified! You\'re good to receive payouts.' : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) { document.getElementById('walletSignatureInput').value = ''; await loadIdentity(); }
  } catch (e) { setResult('walletVerifyResult', `Error: ${e.message}`, false); }
});

// ── Account creation ──────────────────────────────────────────────────────────

document.getElementById('createAccountBtn').addEventListener('click', async () => {
  try {
    const role = document.getElementById('newAccountRole').value;
    const label = document.getElementById('newAccountLabel').value.trim();
    const r = await fetch(`${API}/hub/accounts/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeaders() },
      body: JSON.stringify({ role, label })
    }).then(res => res.json());
    if (r.ok) {
      const name = r.username ? `"${r.username}" (${friendlyRole(r.role)})` : friendlyRole(r.role);
      setResult('createAccountResult',
        `Account created! You're now ${name}.\nAccount ID: ${r.account_id}\n\nYou're now selected in the top bar. Share your account ID with the admin if needed.`,
        true);
      // Refresh account list and switch to new account
      const boot = await fetch(`${API}/hub/session/bootstrap`).then(res => res.json());
      ALL_ACCOUNTS = boot.accounts || [];
      const sel = document.getElementById('accountSelect');
      sel.innerHTML = ALL_ACCOUNTS.map(a => `<option value="${a.account_id}">${accountLabel(a)}</option>`).join('');
      sel.value = r.account_id;
      ACTIVE_ACCOUNT_ID = r.account_id;
      ACTIVE_ROLE = r.role;
      await establishSession(r.account_id);
      populateAccountSelects();
    } else {
      setResult('createAccountResult', `Could not create account: ${apiMsg(r)}`, false);
    }
  } catch (e) { setResult('createAccountResult', `Error: ${e.message}`, false); }
});

// ── Admin ──────────────────────────────────────────────────────────────────────

document.getElementById('dispenseBtn').addEventListener('click', async () => {
  try {
    const account_id = document.getElementById('dispenseAccountSelect').value;
    const amount_usd = Number(document.getElementById('dispenseAmountUsd').value);
    if (!account_id || !amount_usd) { setResult('dispenseResult', 'Select an account and enter an amount.', false); return; }
    const r = await jpost('/hub/admin/dispense', { account_id, amount_usd });
    setResult('dispenseResult',
      r.ok ? `Done. Added $${r.dispensed_usd} → ${r.dispensed_btc} BTC to that account.` : `Error: ${apiMsg(r)}`,
      r.ok);
    if (r.ok) { await loadLedger(); await loadBalance(); }
  } catch (e) { setResult('dispenseResult', `Error: ${e.message}`, false); }
});

document.getElementById('setPlanBtn').addEventListener('click', async () => {
  try {
    const machineId = document.getElementById('planMachineId').value.trim();
    const plan = document.getElementById('planValue').value;
    const r = await jpost(`/hub/machines/${encodeURIComponent(machineId)}/plan`, { plan });
    setResult('setPlanResult', r.ok ? 'Plan updated.' : `Error: ${apiMsg(r)}`, r.ok);
    if (r.ok) await loadMachines();
  } catch (e) { setResult('setPlanResult', `Error: ${e.message}`, false); }
});

document.getElementById('deleteAccountBtn').addEventListener('click', async () => {
  try {
    const account_id = document.getElementById('deleteAccountSelect').value;
    if (!account_id) return;
    const label = ALL_ACCOUNTS.find(a => a.account_id === account_id);
    if (!confirm(`Delete account ${accountLabel(label || { account_id })}? This cannot be undone.`)) return;
    const r = await jpost('/hub/admin/accounts/delete', { account_id });
    if (r.ok) {
      setResult('deleteAccountResult', `Deleted.`, true);
      ALL_ACCOUNTS = ALL_ACCOUNTS.filter(a => a.account_id !== account_id);
      const sel = document.getElementById('accountSelect');
      sel.innerHTML = ALL_ACCOUNTS.map(a => `<option value="${a.account_id}">${accountLabel(a)}</option>`).join('');
      populateAccountSelects();
    } else {
      setResult('deleteAccountResult', `Error: ${apiMsg(r)}`, false);
    }
  } catch (e) { setResult('deleteAccountResult', `Error: ${e.message}`, false); }
});

document.getElementById('setControlBtn').addEventListener('click', async () => {
  try {
    const account_id = document.getElementById('controlAccountSelect').value;
    const control_mode = document.getElementById('controlMode').value;
    const reason = document.getElementById('controlReason').value.trim() || null;
    const r = await jpost('/hub/admin/account-controls/set', { account_id, control_mode, reason });
    setResult('setControlResult',
      r.ok ? `Set to: ${control_mode}` : `Error: ${apiMsg(r)}`,
      r.ok);
  } catch (e) { setResult('setControlResult', `Error: ${e.message}`, false); }
});

// ── Tabs ──────────────────────────────────────────────────────────────────────

document.querySelectorAll('#tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    document.getElementById(btn.dataset.tab).classList.add('active');
    // Auto-fill cycle ID inputs with current open cycle when switching to Cycle or Vote tabs
    if (CURRENT_OPEN_CYCLE_ID) {
      if (btn.dataset.tab === 'cycle') {
        const inp = document.getElementById('cycleIdInput');
        if (inp && !inp.value) inp.value = CURRENT_OPEN_CYCLE_ID;
        const closeInp = document.getElementById('closeCycleIdInput');
        if (closeInp && !closeInp.value) closeInp.value = CURRENT_OPEN_CYCLE_ID;
      }
      if (btn.dataset.tab === 'vote') {
        const inp = document.getElementById('voteCycleIdInput');
        if (inp && !inp.value) inp.value = CURRENT_OPEN_CYCLE_ID;
        const totInp = document.getElementById('voteViewCycleId');
        if (totInp && !totInp.value) totInp.value = CURRENT_OPEN_CYCLE_ID;
      }
    }
  });
});

// ── Init ──────────────────────────────────────────────────────────────────────

bootstrapAccount()
  .then(load)
  .catch(err => {
    document.getElementById('cycleCard').textContent = `Connection error: ${err.message}`;
  });
