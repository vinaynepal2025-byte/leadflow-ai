# LeadFlow AI — Backend

Real, tested backend code for LeadFlow AI (VertiCore MetaOS's first Product
Instance). Every endpoint below was verified working before packaging.

## Modules
1. **Lead Management** — create/list/update/delete, pipeline stages
2. **Communication Hub** — full history of every interaction per lead
3. **WhatsApp — paid method** — sends via Meta Cloud API (needs Meta Business token)
4. **WhatsApp — free method** — generates a wa.me click-to-chat link with the
   message pre-filled; counselor taps Send manually (no Meta approval needed)
5. **WhatsApp — webhook** — automatically captures replies from leads and
   logs them, once this backend is deployed with a public URL
6. **AI Analysis** — Claude reads a lead's history, returns summary,
   sentiment, buying intent, risk flags, next action, draft reply

## Setup
1. `npm install`
2. `cp .env.example .env`, fill in what you have (leave blank = that feature
   waits, everything else still works)
3. `node server.js` — runs at http://localhost:3000

## Endpoints
- `GET  /health`
- `POST /leads`, `GET /leads`, `GET /leads/:id`, `PATCH /leads/:id`, `DELETE /leads/:id`
- `POST /communications`, `GET /communications?lead_id=xxx`
- `POST /whatsapp/send` — paid, real send via Meta API
- `GET  /whatsapp/chat-link/:leadId?message=...` — free wa.me link
- `POST /whatsapp/chat-link/:leadId/confirm-sent` — log after tapping Send
- `GET/POST /whatsapp/webhook` — Meta's inbound-message webhook
- `POST /ai/analyze-lead/:id`

## Continuing in Claude Code
Open this folder in Claude Code and say: "continue LeadFlow AI." Nothing is
lost — this is the real, tested starting point.
