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

function prepare(sql) {
  const translated = translate(sql);
  return {
    async get(...params) {
      const result = await pool.query(translated, params);
      return result.rows[0];
    },
    async all(...params) {
      const result = await pool.query(translated, params);
      return result.rows;
    },
    async run(...params) {
      const result = await pool.query(translated, params);
      return { changes: result.rowCount, lastInsertRowid: undefined };
    },
  };
}

// Prevent idle connection drops (network blips, pooler timeouts) from
// crashing the entire Node process — pg emits an unhandled 'error' event
// on the pool for these, which is fatal unless we listen for it.
pool.on('error', (err) => {
  console.error('Unexpected Postgres pool error (recovered, not fatal):', err.message);
});

module.exports = { prepare, pool };
