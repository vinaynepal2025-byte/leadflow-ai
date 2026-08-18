"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getLeads, Lead, ApiError } from "@/lib/api";

export default function CrmPage() {
  const [leads, setLeads] = useState<Lead[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getLeads()
      .then(setLeads)
      .catch((err) => setError(err instanceof ApiError ? err.message : "Could not load leads"))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-slate-900">CRM</h1>
      <p className="mt-1 text-sm text-slate-500">{leads.length} lead{leads.length === 1 ? "" : "s"} — same GET /leads the mobile app uses.</p>

      {loading && <p className="mt-8 text-sm text-slate-400">Loading...</p>}
      {error && (
        <div className="mt-8 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Could not load: {error}
        </div>
      )}

      {!loading && !error && (
        <div className="mt-6 overflow-hidden rounded-xl border border-slate-200 bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-slate-200 bg-slate-50 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3">Stage</th>
                <th className="px-4 py-3">Source</th>
                <th className="px-4 py-3">Phone</th>
                <th className="px-4 py-3">Created</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {leads.map((lead) => (
                <tr key={lead.id} className="hover:bg-slate-50">
                  <td className="px-4 py-3">
                    <Link href={`/crm/${lead.id}`} className="font-medium text-slate-900 hover:underline">
                      {lead.full_name}
                    </Link>
                  </td>
                  <td className="px-4 py-3">
                    <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700">{lead.stage}</span>
                  </td>
                  <td className="px-4 py-3 text-slate-500">{lead.source ?? "—"}</td>
                  <td className="px-4 py-3 text-slate-500">{lead.phone ?? "—"}</td>
                  <td className="px-4 py-3 text-slate-500">{new Date(lead.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
              {leads.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-8 text-center text-slate-400">
                    No leads yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
