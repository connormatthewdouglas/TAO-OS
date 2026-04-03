import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import fetch from 'node-fetch';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 8787;
const REF = process.env.SUPABASE_PROJECT_REF;
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN;

function esc(v) {
  return String(v ?? '').replace(/'/g, "''");
}

function scopeAccount(req) {
  return (req.query.account_id || req.headers['x-account-id'] || '').toString().trim() || null;
}

async function getAccountRole(accountId) {
  if (!accountId) return null;
  const rows = await sql(`select role from l5_accounts where account_id='${esc(accountId)}' limit 1;`);
  return rows[0]?.role || null;
}

function canAdmin(role) {
  return role === 'mixed';
}

function canVote(role) {
  return role === 'validator' || role === 'mixed';
}

function isLikelyWalletAddress(value) {
  const v = String(value || '').trim();
  if (!v) return false;
  // MVP rail-mode: keep this broad enough for non-EVM future support,
  // but still reject obvious junk.
  return v.length >= 6 && v.length <= 128 && /^[a-zA-Z0-9:_-]+$/.test(v);
}

async function ensureWalletTable() {
  await sql(`create table if not exists l5_wallet_identities (
    account_id uuid primary key references l5_accounts(account_id) on delete cascade,
    wallet_address text not null,
    chain_id text not null default 'evm:1',
    verification_status text not null default 'unverified',
    verification_method text,
    verification_nonce text,
    signature text,
    bound_at timestamptz not null default now(),
    verified_at timestamptz,
    updated_at timestamptz not null default now()
  );`);

  await sql(`create unique index if not exists l5_wallet_identities_address_unique
    on l5_wallet_identities ((lower(wallet_address)));`);
}

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ query })
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Supabase ${res.status}: ${text}`);
  return JSON.parse(text || '[]');
}

app.get('/health', async (_req, res) => {
  try {
    await sql('select 1 as ok;');
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/cycle/latest', async (_req, res) => {
  try {
    const data = await sql(`select cycle_id,status,pool_open,pool_close,cycle_started_at,cycle_closed_at
      from l5_pool_cycles order by cycle_id desc limit 1;`);
    res.json({ ok: true, data: data[0] || null });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/hub/cycle/run', async (req, res) => {
  try {
    const actorId = scopeAccount(req) || req.body?.actor_account_id;
    const role = await getAccountRole(actorId);
    if (!canAdmin(role)) return res.status(403).json({ ok: false, error: 'forbidden_admin_only' });

    const cycleId = Number(req.body?.cycle_id);
    const poolOpen = Number(req.body?.pool_open ?? 1000);
    if (!Number.isFinite(cycleId)) return res.status(400).json({ ok: false, error: 'invalid_cycle_id' });

    const data = await sql(`select l5_run_cycle(${cycleId}, ${poolOpen}) as result;`);
    res.json({ ok: true, data: data[0]?.result || null });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/machines', async (req, res) => {
  try {
    const accountId = scopeAccount(req);
    const where = accountId ? `where account_id='${esc(accountId)}'` : '';
    const data = await sql(`select machine_id,account_id,plan,fast_cycle_fee,last_burn_cycle_id,plan_updated_at
      from l5_machine_entitlements ${where} order by plan_updated_at desc limit 200;`);
    res.json({ ok: true, data });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/hub/machines/:machineId/plan', async (req, res) => {
  try {
    const actorId = scopeAccount(req) || req.body?.actor_account_id;
    const actorRole = await getAccountRole(actorId);
    const { machineId } = req.params;
    const { plan } = req.body;
    if (!['stable', 'fast'].includes(plan)) return res.status(400).json({ ok: false, error: 'invalid_plan' });

    const owner = await sql(`select account_id from l5_machine_entitlements where machine_id='${esc(machineId)}' limit 1;`);
    const ownerId = owner[0]?.account_id;
    if (!ownerId) return res.status(404).json({ ok: false, error: 'machine_not_found' });

    if (!(canAdmin(actorRole) || actorId === ownerId)) {
      return res.status(403).json({ ok: false, error: 'forbidden_not_owner' });
    }

    await sql(`update l5_machine_entitlements set plan='${esc(plan)}', plan_updated_at=now() where machine_id='${esc(machineId)}';`);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/rewards/ledger', async (req, res) => {
  try {
    const limit = Math.min(Number(req.query.limit || 50), 200);
    const accountId = scopeAccount(req);
    const where = accountId
      ? `where source_account_id='${esc(accountId)}' or target_account_id='${esc(accountId)}'`
      : '';
    const data = await sql(`select event_time,cycle_id,event_type,bucket,amount,idempotency_key,source_account_id,target_account_id
      from l5_credit_ledger ${where} order by event_time desc limit ${limit};`);
    res.json({ ok: true, data });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/rewards/balances', async (req, res) => {
  try {
    const accountId = scopeAccount(req);
    const [pool, accounts] = await Promise.all([
      sql(`select * from v_l5_pool_balance;`),
      sql(accountId
        ? `select * from v_l5_account_balances where account_id='${esc(accountId)}' limit 1;`
        : `select * from v_l5_account_balances order by balance desc limit 200;`)
    ]);
    res.json({ ok: true, pool: pool[0] || null, accounts });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/contributions', async (req, res) => {
  try {
    const accountId = scopeAccount(req);
    const where = accountId ? `where account_id='${esc(accountId)}'` : '';
    const data = await sql(`select submission_id,account_id,submission_hash,title,class,state,verdict,measured_score,appeal_deadline,updated_at
      from l5_contributor_submissions ${where} order by updated_at desc limit 200;`);
    res.json({ ok: true, data });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/hub/contributions', async (req, res) => {
  try {
    let { account_id, submission_hash, title, class_name = 'preset', stake_amount = 5 } = req.body || {};
    if (!submission_hash || !title) return res.status(400).json({ ok: false, error: 'missing_fields' });

    if (!account_id) {
      const acct = await sql(`select account_id from l5_accounts where role in ('contributor','mixed') order by created_at asc limit 1;`);
      account_id = acct[0]?.account_id;
      if (!account_id) {
        await sql(`insert into l5_accounts (role, status) values ('contributor','active');`);
        const acct2 = await sql(`select account_id from l5_accounts where role='contributor' order by created_at asc limit 1;`);
        account_id = acct2[0]?.account_id;
      }
    }

    await sql(`insert into l5_contributor_submissions (account_id, submission_hash, title, class, stake_amount, state)
      values ('${esc(account_id)}', '${esc(submission_hash)}', '${esc(title)}', '${esc(class_name)}', ${Number(stake_amount)}, 'stake_locked')
      on conflict (submission_hash) do update set updated_at = now();`);

    res.json({ ok: true, account_id });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/governance/appeals', async (req, res) => {
  try {
    const accountId = scopeAccount(req);
    const where = accountId
      ? `where opened_by_account_id='${esc(accountId)}' or submission_id in (select submission_id from l5_contributor_submissions where account_id='${esc(accountId)}')`
      : '';
    const data = await sql(`select appeal_id,submission_id,opened_by_account_id,state,reason,evidence_uri,deadline_at,opened_at,resolved_at
      from l5_appeals ${where} order by opened_at desc limit 200;`);
    res.json({ ok: true, data });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/hub/governance/appeals', async (req, res) => {
  try {
    const actorId = scopeAccount(req) || req.body?.opened_by_account_id;
    const { submission_id, opened_by_account_id, reason, evidence_uri = null, fee_amount = 0.10 } = req.body || {};
    if (!submission_id || !opened_by_account_id || !reason) return res.status(400).json({ ok: false, error: 'missing_fields' });
    if (actorId !== opened_by_account_id) return res.status(403).json({ ok: false, error: 'forbidden_actor_mismatch' });

    const data = await sql(`select l5_open_appeal('${esc(submission_id)}', '${esc(opened_by_account_id)}', '${esc(reason)}', ${evidence_uri ? `'${esc(evidence_uri)}'` : 'null'}, ${Number(fee_amount)}) as result;`);
    res.json({ ok: true, data: data[0]?.result || null });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/governance/votes', async (req, res) => {
  try {
    const accountId = scopeAccount(req);
    const where = accountId ? `where voter_account_id='${esc(accountId)}'` : '';
    const data = await sql(`select vote_id,appeal_id,voter_account_id,vote,weight,voted_at
      from l5_governance_votes ${where} order by voted_at desc limit 200;`);
    res.json({ ok: true, data });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/hub/governance/votes', async (req, res) => {
  try {
    const actorId = scopeAccount(req) || req.body?.voter_account_id;
    const actorRole = await getAccountRole(actorId);
    const { appeal_id, voter_account_id, vote, weight = 1 } = req.body || {};
    if (!appeal_id || !voter_account_id || !['yes', 'no', 'abstain'].includes(vote)) {
      return res.status(400).json({ ok: false, error: 'missing_or_invalid_fields' });
    }
    if (actorId !== voter_account_id) return res.status(403).json({ ok: false, error: 'forbidden_actor_mismatch' });
    if (!canVote(actorRole)) return res.status(403).json({ ok: false, error: 'forbidden_vote_role' });

    await sql(`insert into l5_governance_votes (appeal_id, voter_account_id, vote, weight)
      values ('${esc(appeal_id)}', '${esc(voter_account_id)}', '${esc(vote)}', ${Number(weight)})
      on conflict (appeal_id, voter_account_id) do update set vote='${esc(vote)}', weight=${Number(weight)}, voted_at=now();`);

    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/identity', async (req, res) => {
  try {
    const accountId = scopeAccount(req);
    if (!accountId) return res.status(400).json({ ok: false, error: 'missing_account_scope' });

    await ensureWalletTable();

    const [accountRows, walletRows] = await Promise.all([
      sql(`select account_id, role, status from l5_accounts where account_id='${esc(accountId)}' limit 1;`),
      sql(`select account_id, wallet_address, chain_id, verification_status, verification_method, bound_at, verified_at, updated_at
           from l5_wallet_identities where account_id='${esc(accountId)}' limit 1;`)
    ]);

    if (!accountRows[0]) return res.status(404).json({ ok: false, error: 'account_not_found' });
    res.json({
      ok: true,
      account: accountRows[0],
      wallet_identity: walletRows[0] || null,
      rail_mode: 'internal_credits'
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.post('/hub/identity/wallet/bind', async (req, res) => {
  try {
    const actorId = scopeAccount(req) || req.body?.actor_account_id;
    const { account_id, wallet_address, chain_id = 'evm:1' } = req.body || {};

    if (!actorId || !account_id || !wallet_address) {
      return res.status(400).json({ ok: false, error: 'missing_fields' });
    }
    if (actorId !== account_id) {
      return res.status(403).json({ ok: false, error: 'forbidden_actor_mismatch' });
    }
    if (!isLikelyWalletAddress(wallet_address)) {
      return res.status(400).json({ ok: false, error: 'invalid_wallet_address' });
    }

    await ensureWalletTable();

    const accountRows = await sql(`select account_id from l5_accounts where account_id='${esc(account_id)}' limit 1;`);
    if (!accountRows[0]) return res.status(404).json({ ok: false, error: 'account_not_found' });

    const clashes = await sql(`select account_id from l5_wallet_identities
      where lower(wallet_address)=lower('${esc(wallet_address)}') and account_id <> '${esc(account_id)}' limit 1;`);
    if (clashes[0]) return res.status(409).json({ ok: false, error: 'wallet_already_bound_elsewhere' });

    await sql(`insert into l5_wallet_identities
      (account_id, wallet_address, chain_id, verification_status, verification_method, signature, verified_at, updated_at)
      values
      ('${esc(account_id)}', '${esc(wallet_address)}', '${esc(chain_id)}', 'unverified', 'pending_signature', null, null, now())
      on conflict (account_id) do update
      set wallet_address='${esc(wallet_address)}',
          chain_id='${esc(chain_id)}',
          verification_status='unverified',
          verification_method='pending_signature',
          signature=null,
          verified_at=null,
          updated_at=now();`);

    const walletRows = await sql(`select account_id, wallet_address, chain_id, verification_status, verification_method, bound_at, verified_at, updated_at
      from l5_wallet_identities where account_id='${esc(account_id)}' limit 1;`);

    res.json({
      ok: true,
      message: 'wallet_bound_unverified',
      wallet_identity: walletRows[0] || null,
      next_step: 'signature_verification_pending_implementation'
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.get('/hub/session/bootstrap', async (_req, res) => {
  try {
    const accounts = await sql(`select account_id, role, status, created_at from l5_accounts order by created_at asc limit 20;`);
    const suggestedAdmin = accounts.find(a => a.role === 'mixed') || null;
    const suggestedOperator = accounts.find(a => ['contributor','validator','consumer'].includes(a.role)) || accounts[0] || null;
    res.json({
      ok: true,
      suggested_account_id: (suggestedAdmin || suggestedOperator)?.account_id || null,
      suggested_admin_account_id: suggestedAdmin?.account_id || null,
      suggested_operator_account_id: suggestedOperator?.account_id || null,
      accounts
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e.message || e) });
  }
});

app.listen(PORT, () => {
  console.log(`hub-api listening on :${PORT}`);
});
