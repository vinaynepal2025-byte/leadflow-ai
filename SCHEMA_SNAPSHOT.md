# SCHEMA_SNAPSHOT.md — real production schema, as of 2026-08-17

Generated read-only via the Supabase MCP server against the live `leadflow-ai` project (`qovaakuithekhotkrrdi`) — no data modified, no live phone numbers contacted. This is the authoritative artifact `TECH_DEBT.md` §1 called for ("no single file you can read to see the real current schema").

**Live counts at snapshot time:** 4 tenants, 785 leads, 56 tables total. Real production data — treat accordingly.

**Note:** `dashboard_sections` and `lead_list_fields` (added earlier this session, migration files exist at `backend/migrations/2026-08-17-dashboard-sections.js` and `2026-08-17-lead-list-fields.js`) are **not present in this list** — confirms those two migrations still haven't been run against production. Customize Dashboard / Customize Leads List will continue 404ing until someone runs them.

## Tables (56)

| Table | Columns | RLS enabled | Rows |
|---|---|---|---|
| tenants | id, name, logo_url, theme_color, contact_email, contact_phone, created_at, status, verification_token, verification_token_expires_at, email_reply_to, own_brevo_api_key_encrypted, own_brevo_sender_email, default_country_code | ✅ | 4 |
| leads | id, tenant_id, full_name, phone, email, source, stage, assigned_to, notes, parent_name, parent_phone, parent_relation, custom_fields, referred_by_lead_id, referrer_name, referrer_type, created_at, updated_at, source_category, last_contacted_at, engagement_trend, phone_country_code, deleted_at, deleted_by | ✅ | 785 |
| custom_field_definitions | id, tenant_id, field_key, label, field_type, options, created_at | ✅ | 1 |
| communications | id, tenant_id, lead_id, channel, direction, body, created_by, created_at | ✅ | 30 |
| reminders | id, tenant_id, lead_id, title, due_at, assigned_to, status, created_at | ✅ | 10 |
| documents | id, tenant_id, lead_id, doc_type, file_name, stored_path, status, uploaded_by, created_at, expiry_date | ✅ | 9 |
| users | id, tenant_id, email, password_hash, full_name, role, created_at, active, invite_token, invite_token_expires_at | ✅ | 4 |
| campaigns | id, tenant_id, name, message_template, status, created_at | ✅ | 0 |
| campaign_targets | id, campaign_id, lead_id, status | ✅ | 0 |
| tasks | id, tenant_id, lead_id, title, due_at, status, assigned_to, priority, created_at | ✅ | 0 |
| admission_applications | id, tenant_id, lead_id, institution_name, course_name, intake, application_status, scholarship_amount, tuition_fee, notes, created_at, updated_at | ✅ | 1 |
| fee_payments | id, tenant_id, lead_id, fee_type, amount, due_date, paid_date, status, payment_method, notes, created_at, plan_id, installment_number, total_installments | ✅ | 4 |
| notifications | id, tenant_id, user_id, title, body, link_type, link_id, read, created_at | ✅ | 2 |
| automation_rules | id, tenant_id, name, trigger_event, condition_field, condition_value, action_type, action_config, enabled, created_at | ✅ | 1 |
| knowledge_articles | id, tenant_id, title, content, category, created_at, updated_at | ✅ | 0 |
| call_logs | id, tenant_id, lead_id, duration_seconds, outcome, notes, called_by, created_at, direction, phone_used, follow_up_at, channel, reminder_id, sentiment | ✅ | 2 |
| voice_notes | id, tenant_id, lead_id, file_name, stored_path, transcript, ai_summary, recorded_by, created_at | ✅ | 2 |
| colleges | id, tenant_id, name, country, contact_person, contact_email, commission_percent, notes, created_at, peer_review_enabled, peer_review_default_price | ✅ | 2 |
| pipeline_stages | id, tenant_id, name, position, color | ✅ | 5 |
| meetings | id, tenant_id, lead_id, meeting_type, title, scheduled_at, duration_minutes, mode, meeting_link, location, campus_name, host_name, attendees, status, outcome_notes, interest_level, follow_up_required, requested_by, created_at, updated_at, virtual_platform, areas_visited, photo_url, visitor_queries, caller_city, caller_state, first_time_visit, referred_by, admission_session, visits_to_nepal_count, visitor_relation, follow_up_date | ✅ | 4 |
| visa_applications | id, tenant_id, lead_id, country, visa_type, status, application_number, submitted_date, interview_date, decision_date, embassy_location, rejection_reason, notes, created_at, updated_at | ✅ | 2 |
| travel_plans | id, tenant_id, lead_id, departure_date, departure_city, arrival_date, arrival_city, airline, flight_number, accommodation, pickup_arranged, pickup_contact, status, notes, created_at | ✅ | 0 |
| capture_forms | id, tenant_id, public_key, name, channel, assign_to, default_stage, auto_reply_message, active, submission_count, created_at | ✅ | 1 |
| students | id, tenant_id, lead_id, student_code, institution_name, course_name, batch_year, current_semester, status, enrolled_date, expected_completion, local_contact, notes, created_at, updated_at, academic_phase, overall_academic_risk, last_risk_computed_at | ✅ | 0 |
| student_checkins | id, tenant_id, student_id, checkin_date, wellbeing, academic_status, issues_raised, action_taken, conducted_by | ✅ | 0 |
| scoring_config | tenant_id, weights, thresholds, updated_at | ✅ | 0 |
| tracked_links | id, tenant_id, short_code, title, destination, platform, campaign, capture_form_id, click_count, active, created_at | ✅ | 1 |
| link_clicks | id, link_id, tenant_id, clicked_at, referrer, user_agent | ✅ | 0 |
| alumni_connections | id, tenant_id, lead_id, student_id, requested_at, status, notes | ✅ | 0 |
| alumni_availability | student_id, available_for_contact, preferred_channel, bio, max_active_connections, updated_at | ✅ | 0 |
| payment_links | id, tenant_id, fee_payment_id, gateway, gateway_order_id, amount, status, payment_url, created_at, paid_at | ✅ | 0 |
| consent_records | id, tenant_id, lead_id, consent_type, granted, method, recorded_by, recorded_at, notes | ✅ | 8 |
| data_requests | id, tenant_id, lead_id, request_type, status, requested_at, completed_at, handled_by | ✅ | 0 |
| review_providers | id, tenant_id, college_id, full_name, role, phone, upi_id, price_per_review, bio, verified, active, rating_sum, rating_count, created_at, pricing_mode, rate_per_minute | ✅ | 3 |
| peer_review_bookings | id, tenant_id, lead_id, college_id, provider_id, meeting_id, price, commission_percent, payment_status, payment_confirmed_at, payment_note, rating, review_notes, status, created_at, duration_minutes | ✅ | 11 |
| offers | id, tenant_id, lead_id, offer_text, amount, currency, given_by, given_at, valid_until, status, notes, created_at | ✅ | 4 |
| content_library | id, tenant_id, title, content_type, file_url, link_url, body_text, tags, language, active, created_at | ✅ | 2 |
| content_sends | id, tenant_id, lead_id, content_id, channel, draft_text, sent_at, sent_by | ✅ | 5 |
| flyers | id, tenant_id, lead_id, template_id, fields, png_base64, ai_generated, created_at | ✅ | 8 |
| lead_detail_sections | id, tenant_id, section_key, is_custom, enabled, sort_order, custom_label, icon_override, color_override, size_override, shape_override, custom_action_type, custom_action_value, created_at, updated_at, gradient_override, style_variant | ✅ | 13 |
| lead_notes | id, tenant_id, lead_id, note_text, author_name, pinned, created_at, tags, sentiment | ✅ | 2 |
| tenant_logos | id, tenant_id, label, storage_path, is_default, created_at | ✅ | 1 |
| flyer_projects | id, tenant_id, lead_id, title, canvas_width, canvas_height, canvas_json, background_color, background_image_path, rendered_image_path, ai_generated, created_by, created_at, updated_at | ✅ | 8 |
| share_targets | id, tenant_id, target_key, is_custom, enabled, sort_order, custom_label, icon_override, color_override, custom_package_or_scheme, created_at, updated_at | ✅ | 6 |
| visa_checklist_items | id, tenant_id, country, visa_type, doc_type, display_order, created_at | ✅ | 25 |
| consent_form_templates | id, tenant_id, consent_type, title, body_text, updated_at | ✅ | 4 |
| whatsapp_templates | id, tenant_id, name, body_text, created_at | ✅ | 5 |
| scheduled_messages | id, tenant_id, lead_id, body_text, send_at, status, created_by, created_at, sent_at | ✅ | 0 |
| subjects | id, tenant_id, name, code, phase_or_semester, credit_hours, active, created_at, updated_at | ✅ | 0 |
| assessments | id, tenant_id, subject_id, name, assessment_type, max_marks, passing_marks, weight_percent, assessment_date, created_at, updated_at | ✅ | 0 |
| marks | id, tenant_id, student_id, assessment_id, marks_obtained, source, recorded_by, notes, created_at, updated_at | ✅ | 0 |
| attendance_records | id, tenant_id, student_id, subject_id, session_date, status, source, recorded_by, created_at | ✅ | 0 |
| academic_risk_config | tenant_id, weights, attendance_threshold_warning, attendance_threshold_critical, updated_at | ✅ | 0 |
| academic_risk_scores | id, tenant_id, student_id, computed_at, academic_risk, attendance_risk, overall_risk, confidence, evidence, created_at | ✅ | 0 |
| more_menu_items | id, tenant_id, item_key, is_custom, enabled, sort_order, custom_label, icon_override, color_override, custom_action_type, custom_action_value, created_at, updated_at, gradient_override, style_variant | ❌ | 17 |
| nav_tabs | id, tenant_id, tab_key, enabled, sort_order, custom_label, icon_override, color_override, created_at, updated_at, gradient_override, style_variant | ❌ | 0 |

## RLS finding (verified, not just inferred)

54 of 56 tables show `rls_enabled = true`, which looked like a real protection layer at first glance. Verified against `pg_policies`: **zero RLS policies exist on any table.** Postgres's own behavior for RLS-enabled-with-no-policies is "deny all" — *except* for roles with `BYPASSRLS`. Verified: the `postgres` role (which `backend/db.js` connects as by default — `PGUSER || 'postgres'`) has `rolbypassrls = true`. **Net effect: RLS is fully bypassed by every request the backend makes today.** It provides zero actual protection — tenant isolation is 100% the `WHERE tenant_id = ?` discipline in each route file, exactly as `TECH_DEBT.md` §2 already flagged, now confirmed by direct inspection rather than inference. Enabling RLS was likely a one-click Supabase security-advisor suggestion applied without the matching policies — worth either finishing properly (real per-tenant policies, useful defense-in-depth once a non-bypassing role exists) or removing to avoid the false impression of protection it currently gives anyone reading the dashboard.

`nav_tabs` — a table not referenced anywhere in `backend/routes/` or `backend/server.js` per this session's route inventory — exists in production with 0 rows and no RLS. Likely an abandoned/superseded predecessor to `more_menu_items`. Flagged for cleanup, not touched (out of scope for a read-only audit).
