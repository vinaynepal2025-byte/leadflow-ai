"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { getLead, Lead, ApiError } from "@/lib/api";

function Field({ label, value }: { label: string; value?: string | null }) {
  if (!value) return null;
  return (
    <div>
      <p className="text-xs font-medium text-slate-400">{label}</p>
      <p className="text-sm text-slate-800">{value}</p>
    </div>
  );
}

export default function LeadDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [lead, setLead] = useState<Lead | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getLead(id)
      .then(setLead)
      .catch((err) => setError(err instanceof ApiError ? err.message : "Could not load this lead"))
      .finally(() => setLoading(false));
  }, [id]);

  return (
    <div className="p-8">
      <button onClick={() => router.push("/crm")} className="text-sm text-slate-500 hover:text-slate-800">
        ← Back to CRM
      </button>

      {loading && <p className="mt-6 text-sm text-slate-400">Loading...</p>}
      {error && (
        <div className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Could not load: {error}
        </div>
      )}

      {lead && (
        <div className="mt-4 max-w-xl rounded-xl border border-slate-200 bg-white p-6">
          <div className="flex items-center justify-between">
            <h1 className="text-xl font-bold text-slate-900">{lead.full_name}</h1>
            <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700">{lead.stage}</span>
          </div>
          <div className="mt-6 grid grid-cols-2 gap-4">
            <Field label="Phone" value={lead.phone} />
            <Field label="Email" value={lead.email} />
            <Field label="Source" value={lead.source} />
            <Field label="Assigned to" value={lead.assigned_to} />
          </div>
          {lead.notes && (
            <div className="mt-6">
              <p className="text-xs font-medium text-slate-400">Notes</p>
              <p className="mt-1 text-sm text-slate-700">{lead.notes}</p>
            </div>
          )}
          <p className="mt-6 text-xs text-slate-400">
            Communications, documents, and the rest of the mobile app's Lead 360 view arrive in a later web pass — this page proves the core read path works end-to-end first.
          </p>
        </div>
      )}
    </div>
  );
}
