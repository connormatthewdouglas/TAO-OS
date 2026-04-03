const API = window.HUB_API_BASE || 'http://localhost:8787';
const installCmd = `git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "Local changes detected"; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh`;

document.getElementById('installCmd').textContent = installCmd;

let ACTIVE_ACCOUNT_ID = null;
let ACTIVE_SESSION_TOKEN = null;
let ACTIVE_WALLET_CHALLENGE = null;

function withScope(path) {
  return path;
}

function authHeaders() {
  return {
    ...(ACTIVE_SESSION_TOKEN ? { 'x-session-token': ACTIVE_SESSION_TOKEN } : {})
  };
}

function setResult(id, text, ok = true) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text;
  el.classList.remove('status-ok', 'status-err');
  el.classList.add(ok ? 'status-ok' : 'status-err');
}

function apiMessage(result, fallback = 'request_failed') {
  if (!result) return fallback;
  if (result.error) return result.error;
  if (result.message) return result.message;
  return fallback;
}

async function jget(path) {
  const res = await fetch(`${API}${withScope(path)}`, { headers: authHeaders() });
  return res.json();
}

async function jpost(path, body) {
  const payload = { ...(body || {}) };
  if (ACTIVE_ACCOUNT_ID && !payload.actor_account_id) payload.actor_account_id = ACTIVE_ACCOUNT_ID;
  const res = await fetch(`${API}${withScope(path)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...authHeaders() },
    body: JSON.stringify(payload)
  });
  return res.json();
}

function rows(id, data, render, colspan = 4) {
  document.getElementById(id).innerHTML = (data || []).map(render).join('') || `<tr><td colspan='${colspan}'>No data</td></tr>`;
}

function setScopedDefaults() {
  const contribInput = document.getElementById('contribAccount');
  const appealInput = document.getElementById('appealAccountId');
  if (contribInput && !contribInput.value) contribInput.value = ACTIVE_ACCOUNT_ID || '';
  if (appealInput && !appealInput.value) appealInput.value = ACTIVE_ACCOUNT_ID || '';
}

async function establishSession(accountId) {
  if (!accountId) {
    ACTIVE_SESSION_TOKEN = null;
    return;
  }
  const session = await fetch(`${API}/hub/session/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account_id: accountId })
  }).then(r => r.json());

  if (!session.ok || !session.session_token) {
    throw new Error(`session_create_failed:${apiMessage(session)}`);
  }
  ACTIVE_SESSION_TOKEN = session.session_token;
}

async function bootstrapAccount() {
  const boot = await fetch(`${API}/hub/session/bootstrap`).then(r => r.json());
  const sel = document.getElementById('accountSelect');
  sel.innerHTML = (boot.accounts || []).map(a => `<option value="${a.account_id}">${a.role} · ${a.account_id.slice(0, 8)}...</option>`).join('');
  ACTIVE_ACCOUNT_ID = boot.suggested_account_id || boot.accounts?.[0]?.account_id || null;
  if (ACTIVE_ACCOUNT_ID) sel.value = ACTIVE_ACCOUNT_ID;
  await establishSession(ACTIVE_ACCOUNT_ID);
  setScopedDefaults();
  sel.addEventListener('change', async () => {
    ACTIVE_ACCOUNT_ID = sel.value;
    await establishSession(ACTIVE_ACCOUNT_ID);
    setScopedDefaults();
    await load();
  });
}

async function load() {
  const [cycle, machines, ledger, contrib, appeals, balances, identity, audit] = await Promise.all([
    jget('/hub/cycle/latest'),
    jget('/hub/machines'),
    jget('/hub/rewards/ledger?limit=20'),
    jget('/hub/contributions'),
    jget('/hub/governance/appeals'),
    jget('/hub/rewards/balances'),
    jget('/hub/identity'),
    jget('/hub/audit/actions?limit=5')
  ]);

  const c = cycle.data;
  document.getElementById('cycleCard').textContent = c
    ? `Cycle: ${c.cycle_id} · Status: ${c.status} · Pool: ${c.pool_close ?? c.pool_open}`
    : 'Cycle: -- · Status: -- · Pool: --';

  const wi = identity.wallet_identity;
  const verifyClass = wi?.verification_status === 'verified' ? 'badge-verified' : 'badge-unverified';
  const verifyLabel = wi?.verification_status || 'unverified';
  document.getElementById('identityCard').innerHTML = identity.ok
    ? `Identity: ${ACTIVE_ACCOUNT_ID?.slice(0, 8) || '--'}... · Rail: internal_credits · <span class="badge ${verifyClass}">${verifyLabel}</span>${wi?.wallet_address ? ` · Wallet: ${wi.wallet_address}` : ' · Wallet: not bound'}`
    : `Identity: unavailable (${identity.error || 'unknown_error'})`;
  if (wi?.verification_status === 'verified') {
    ACTIVE_WALLET_CHALLENGE = null;
    document.getElementById('walletChallengeMessage').textContent = 'Wallet verified. No pending challenge.';
  }

  const auditItems = (audit?.data || []).map(a => `${a.action}@${a.created_at?.slice(11, 19) || '--:--:--'}`);
  document.getElementById('actionTrailSummary').textContent = audit?.ok
    ? `Recent actions: ${auditItems.length ? auditItems.join(' · ') : 'none yet'}`
    : `Recent actions unavailable (${apiMessage(audit)})`;

  rows('machinesBody', machines.data, m => `<tr><td>${m.machine_id}</td><td>${m.plan}</td><td>${m.fast_cycle_fee}</td><td>${m.last_burn_cycle_id ?? '-'}</td></tr>`);
  rows('ledgerBody', ledger.data, e => `<tr><td>${e.event_type}</td><td>${e.bucket}</td><td>${e.amount}</td><td>${e.cycle_id}</td></tr>`);
  rows('contribBody', contrib.data, s => `<tr><td>${s.submission_hash}</td><td>${s.class}</td><td>${s.state}</td><td>${s.verdict ?? '-'}</td></tr>`);
  rows('appealsBody', appeals.data, a => `<tr><td>${a.appeal_id}</td><td>${a.submission_id}</td><td>${a.state}</td><td>${a.deadline_at ?? '-'}</td></tr>`);

  const pool = balances.pool?.incentive_pool_balance ?? '--';
  const burn = balances.pool?.burn_sink_total ?? '--';
  document.getElementById('rewardsSummary').innerHTML = `
    <div class='card'><b>Rail</b><div>internal_credits</div></div>
    <div class='card'><b>Incentive Pool</b><div>${pool}</div></div>
    <div class='card'><b>Burn Sink Total</b><div>${burn}</div></div>
    <div class='card'><b>Cycle Status</b><div>${c?.status ?? '--'}</div></div>
  `;
}

// Actions

document.getElementById('bindWalletBtn').addEventListener('click', async () => {
  try {
    const wallet_address = document.getElementById('walletAddressInput').value.trim();
    const chain_id = document.getElementById('walletChainInput').value.trim() || 'evm:1';
    if (!wallet_address) {
      setResult('bindWalletResult', 'Enter a wallet address first.', false);
      return;
    }
    const result = await jpost('/hub/identity/wallet/bind', { account_id: ACTIVE_ACCOUNT_ID, wallet_address, chain_id });
    if (result.ok) {
      setResult('bindWalletResult', `Wallet bound in rail mode (${result.wallet_identity?.verification_status || 'unverified'}). Signature verification comes next.`, true);
    } else {
      setResult('bindWalletResult', `Bind failed: ${apiMessage(result)}`, false);
    }
    await load();
  } catch (err) {
    setResult('bindWalletResult', `Bind failed: ${err.message}`, false);
  }
});

document.getElementById('walletChallengeBtn').addEventListener('click', async () => {
  try {
    const result = await jpost('/hub/identity/wallet/challenge', { account_id: ACTIVE_ACCOUNT_ID });
    if (result.ok) {
      ACTIVE_WALLET_CHALLENGE = result;
      document.getElementById('walletChallengeMessage').textContent = result.message;
      setResult('walletVerifyResult', 'Challenge generated. Sign this exact message with your bound wallet.', true);
    } else {
      setResult('walletVerifyResult', `Challenge failed: ${apiMessage(result)}`, false);
    }
  } catch (err) {
    setResult('walletVerifyResult', `Challenge failed: ${err.message}`, false);
  }
});

document.getElementById('walletVerifyBtn').addEventListener('click', async () => {
  try {
    const signature = document.getElementById('walletSignatureInput').value.trim();
    if (!signature) {
      setResult('walletVerifyResult', 'Paste wallet signature first.', false);
      return;
    }
    if (!ACTIVE_WALLET_CHALLENGE?.nonce) {
      setResult('walletVerifyResult', 'Generate a challenge first.', false);
      return;
    }

    const result = await jpost('/hub/identity/wallet/verify', { account_id: ACTIVE_ACCOUNT_ID, signature });
    if (result.ok) {
      setResult('walletVerifyResult', 'Wallet signature verified.', true);
      document.getElementById('walletSignatureInput').value = '';
      ACTIVE_WALLET_CHALLENGE = null;
    } else {
      setResult('walletVerifyResult', `Verify failed: ${apiMessage(result)}`, false);
    }
    await load();
  } catch (err) {
    setResult('walletVerifyResult', `Verify failed: ${err.message}`, false);
  }
});

document.getElementById('runCycleBtn').addEventListener('click', async () => {
  try {
    const cycle_id = Number(document.getElementById('cycleIdInput').value);
    const pool_open = Number(document.getElementById('poolOpenInput').value || 1000);
    const result = await jpost('/hub/cycle/run', { cycle_id, pool_open });
    if (result.ok) {
      setResult('runCycleResult', 'Cycle run complete.', true);
    } else {
      setResult('runCycleResult', `Run failed: ${apiMessage(result)}`, false);
    }
    await load();
  } catch (err) {
    setResult('runCycleResult', `Run failed: ${err.message}`, false);
  }
});

document.getElementById('setPlanBtn').addEventListener('click', async () => {
  try {
    const machineId = document.getElementById('planMachineId').value.trim();
    const plan = document.getElementById('planValue').value;
    const result = await jpost(`/hub/machines/${encodeURIComponent(machineId)}/plan`, { plan });
    setResult('setPlanResult', result.ok ? 'Plan updated.' : `Set plan failed: ${apiMessage(result)}`, result.ok);
    await load();
  } catch (err) {
    setResult('setPlanResult', `Set plan failed: ${err.message}`, false);
  }
});

document.getElementById('createContribBtn').addEventListener('click', async () => {
  try {
    const payload = {
      account_id: document.getElementById('contribAccount').value.trim(),
      submission_hash: document.getElementById('contribHash').value.trim(),
      title: document.getElementById('contribTitle').value.trim(),
      class_name: document.getElementById('contribClass').value
    };
    const result = await jpost('/hub/contributions', payload);
    setResult('createContribResult', result.ok ? 'Submission created/updated.' : `Create failed: ${apiMessage(result)}`, result.ok);
    await load();
  } catch (err) {
    setResult('createContribResult', `Create failed: ${err.message}`, false);
  }
});

document.getElementById('openAppealBtn').addEventListener('click', async () => {
  try {
    const payload = {
      submission_id: document.getElementById('appealSubmissionId').value.trim(),
      opened_by_account_id: document.getElementById('appealAccountId').value.trim(),
      reason: document.getElementById('appealReason').value.trim()
    };
    const result = await jpost('/hub/governance/appeals', payload);
    setResult('openAppealResult', result.ok ? 'Appeal opened.' : `Open appeal failed: ${apiMessage(result)}`, result.ok);
    await load();
  } catch (err) {
    setResult('openAppealResult', `Open appeal failed: ${err.message}`, false);
  }
});

bootstrapAccount()
  .then(load)
  .catch(err => {
    document.getElementById('cycleCard').textContent = `API error: ${err.message}`;
    setResult('bindWalletResult', `API error: ${err.message}`, false);
  });

document.querySelectorAll('#tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const tab = btn.dataset.tab;
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    document.getElementById(tab).classList.add('active');
  });
});
