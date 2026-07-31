# LeadFlow AI
### Powered by VertiCore MetaOS

A Lead Intelligence & Consultancy Operating System — currently optimized
for education/career/medical-admission consultancies, architected to
generalize to any relationship-driven business.

## Folders
- **`backend/`** — Node.js API: Lead Management, Communication Hub,
  WhatsApp (paid + free + webhook), AI Analysis (Claude). Real, tested code.
- **`mobile/`** — Flutter app source: Leads List, Add Lead, Lead Detail
  (with AI Insight + WhatsApp). Needs `flutter create .` once (see
  `mobile/README.md`) to become a runnable project.

## Quick start
1. `cd backend && npm install && cp .env.example .env && node server.js`
2. `cd mobile && flutter create . && flutter pub get && flutter run`

## Status
Built module by module, each tested before moving to the next:
Lead Management -> Communication Hub -> WhatsApp (3 methods) -> AI Analysis
-> Mobile app (Leads/Add/Detail screens). Next modules continue the same way.

## Uploading this to your own GitHub
1. Create a new repository on github.com (no need to initialize with a README)
2. On the repo page, click "uploading an existing file"
3. Drag this entire folder's contents in and commit — no terminal needed
