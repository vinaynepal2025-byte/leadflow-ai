// LeadFlow AI — Database Layer (Postgres / Supabase)
//
// Route files were originally written against node:sqlite's synchronous
// `db.prepare(sql).get/.all/.run(...)` API using `?` placeholders. Rather
// than rewriting every SQL string across 41 route files, this shim
// preserves that exact call shape — `?` placeholders and `datetime('now')`
// calls are translated to Postgres syntax automatically, and .get/.all/.run
// are now async (must be awaited at every call site).

const { Pool, types } = require('pg');

// Postgres returns BIGINT (used by COUNT star) as a string by default to
// avoid precision loss. Our counts are always small and Flutter expects
// real ints, so parse BIGINT (OID 20) as a JS number app-wide.
types.setTypeParser(20, (val) => parseInt(val, 10));

const pool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT || 5432,
  user: process.env.PGUSER || 'postgres',
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE || 'postgres',
  ssl: { rejectUnauthorized: false },
});

// Translates a SQLite-style query (using `?` placeholders and
// `datetime('now')`) into Postgres syntax (`$1, $2, ...` and `now()`).
function translate(sql) {
  let i = 0;
  let out = sql.replace(/\?/g, () => `$${++i}`);
  out = out.replace(/datetime\('now'\)/g, "to_char(now(), 'YYYY-MM-DD HH24:MI:SS')");
  return out;
}

// Builds a .get/.all/.run object bound to whatever can run a query --
// the shared pool (auto-managed connection per call, the original
// behaviour) or a single checked-out client (so every prepare() inside
// one transaction runs on the same connection, same session, same
// BEGIN/COMMIT). Same shape either way, so existing route code doesn't
// need to know or care which one it's using.
function makePreparer(queryable) {
  return function prepare(sql) {
    const translated = translate(sql);
    return {
      async get(...params) {
        const result = await queryable.query(translated, params);
        return result.rows[0];
      },
      async all(...params) {
        const result = await queryable.query(translated, params);
        return result.rows;
      },
      async run(...params) {
        const result = await queryable.query(translated, params);
        return { changes: result.rowCount, lastInsertRowid: undefined };
      },
    };
  };
}

const prepare = makePreparer(pool);

// Real transactions -- TECH_DEBT.md's #2 finding ("no BEGIN/COMMIT
// wrapper, multi-step writes aren't atomic") fixed. Usage:
//   await db.transaction(async (tx) => {
//     await tx.prepare('INSERT INTO leads (...) VALUES (...)').run(...);
//     await tx.prepare('INSERT INTO automation_log (...) VALUES (...)').run(...);
//   });
// Every tx.prepare(...) call inside the callback runs on the same
// checked-out client, so they all commit or all roll back together.
// Returns the callback's return value; rolls back and rethrows on any
// error, including one thrown intentionally by the caller to abort.
async function transaction(callback) {
  const client = await pool.connect();
  const tx = { prepare: makePreparer(client) };
  try {
    await client.query('BEGIN');
    const result = await callback(tx);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackErr) {
      console.error('Rollback itself failed (connection likely already dead):', rollbackErr.message);
    }
    throw err;
  } finally {
    client.release();
  }
}

// Prevent idle connection drops (network blips, pooler timeouts) from
// crashing the entire Node process — pg emits an unhandled 'error' event
// on the pool for these, which is fatal unless we listen for it.
pool.on('error', (err) => {
  console.error('Unexpected Postgres pool error (recovered, not fatal):', err.message);
});

module.exports = { prepare, transaction, pool };
