// Read-only introspection for the Tool Registry (Phase 3). Lets the
// (future) Automation Center screen and this deploy's verification both
// see what's actually registered without importing server internals.
// Deliberately does NOT expose a generic "invoke any tool" HTTP
// endpoint -- invokeTool() is called from server-side orchestrator/agent
// code only (later phases), never directly from a client request, so a
// tool's risk tier can't be bypassed by hitting an HTTP route with the
// right shape.

const express = require('express');
const { listTools } = require('../services/toolRegistry');

const router = express.Router();

// GET /tools — list every registered tool with its risk tier and schema.
router.get('/', (req, res) => {
  res.json(listTools());
});

module.exports = router;
