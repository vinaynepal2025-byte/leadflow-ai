// LeadFlow AI — Database Layer (Postgres / Supabase)
//
// Route files were originally written against node:sqlite's synchronous
// `db.prepare(sql).get/.all/.run(...)` API using `?` placeholders. Rather
// than rewriting every SQL string across 41 route files, this shim
// preserves that exact call shape — `?` placeholders and `datetime('now')`
// calls are translated to Postgres syntax automatically, and .get/.all/.run
// are now async (must be awaited at every call site).

const { Pool } = require('pg');

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

module.exports = { prepare, pool };
