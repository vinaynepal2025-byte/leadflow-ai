// LeadFlow AI web — API client.
//
// Talks to the exact same Express backend the Flutter mobile app uses
// (see mobile/lib/services/api_service.dart for the reference contract) —
// no backend changes, no second API. Auth model mirrors the mobile app's:
// a JWT bearer token + x-tenant-id header on every request, both required
// since the backend's global enforceAuth gate (middleware/auth.js) went
// live. Token + tenantId are kept in localStorage (client-side only —
// this file must never run at build/server time with a real token).

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || "https://leadflow-ai-backend-e50r.onrender.com";

const TOKEN_KEY = "leadflow_web_token";
const TENANT_KEY = "leadflow_web_tenant_id";
const USER_KEY = "leadflow_web_user";

export interface AuthUser {
  id: string;
  email: string;
  full_name: string;
  role: string;
  tenant_id: string;
}

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TOKEN_KEY);
}

export function getTenantId(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TENANT_KEY);
}

export function getUser(): AuthUser | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(USER_KEY);
  return raw ? (JSON.parse(raw) as AuthUser) : null;
}

export function setSession(token: string, user: AuthUser) {
  window.localStorage.setItem(TOKEN_KEY, token);
  window.localStorage.setItem(TENANT_KEY, user.tenant_id);
  window.localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearSession() {
  window.localStorage.removeItem(TOKEN_KEY);
  window.localStorage.removeItem(TENANT_KEY);
  window.localStorage.removeItem(USER_KEY);
}

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function headers(): HeadersInit {
  const token = getToken();
  const tenantId = getTenantId();
  return {
    "Content-Type": "application/json",
    ...(tenantId ? { "x-tenant-id": tenantId } : {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

async function handle<T>(res: Response): Promise<T> {
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const body = await res.json();
      if (body?.error) message = body.error;
    } catch {
      // response wasn't JSON -- keep the generic message
    }
    throw new ApiError(res.status, message);
  }
  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

export async function apiGet<T>(path: string): Promise<T> {
  const res = await fetch(`${API_BASE_URL}${path}`, { headers: headers() });
  return handle<T>(res);
}

export async function apiPost<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${API_BASE_URL}${path}`, {
    method: "POST",
    headers: headers(),
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return handle<T>(res);
}

// ---------- Auth ----------

export interface LoginResponse {
  token: string;
  user: AuthUser;
}

export async function login(tenantId: string, email: string, password: string) {
  // Deliberately not using apiPost() -- login happens before a session
  // (and therefore a tenantId/token to put in headers()) exists.
  const res = await fetch(`${API_BASE_URL}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tenant_id: tenantId, email, password }),
  });
  return handle<LoginResponse>(res);
}

// ---------- CRM ----------

export interface Lead {
  id: string;
  tenant_id: string;
  full_name: string;
  phone?: string | null;
  email?: string | null;
  source?: string | null;
  stage: string;
  assigned_to?: string | null;
  notes?: string | null;
  created_at: string;
  updated_at: string;
}

export function getLeads(stage?: string) {
  const qs = stage ? `?stage=${encodeURIComponent(stage)}` : "";
  return apiGet<Lead[]>(`/leads${qs}`);
}

export function getLead(id: string) {
  return apiGet<Lead>(`/leads/${id}`);
}

export interface PipelineStage {
  id: string;
  tenant_id: string;
  name: string;
  position: number;
  color: string;
}

export function getPipelineStages() {
  return apiGet<PipelineStage[]>("/pipeline-stages");
}

// ---------- Dashboard / Analytics ----------

export interface AnalyticsSummary {
  total_leads: number;
  by_stage: { stage: string; count: number }[];
  by_source: { source: string; count: number }[];
  pending_reminders: number;
  overdue_reminders: number;
  communications_today: number;
  conversion_rate: number;
}

export function getAnalyticsSummary() {
  return apiGet<AnalyticsSummary>("/analytics/summary");
}
