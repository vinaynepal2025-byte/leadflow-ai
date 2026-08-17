"use client";

import { useEffect, useState } from "react";
import { getAnalyticsSummary, AnalyticsSummary, ApiError } from "@/lib/api";

function StatCard({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white p-5">
      <p className="text-xs font-medium text-slate-500">{label}</p>
      <p className="mt-1 text-2xl font-bold text-slate-900">{value}</p>
    </div>
  );
}

export default function DashboardPage() {
  const [data, setData] = useState<AnalyticsSummary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getAnalyticsSummary()
      .then(setData)
      .catch((err) => setError(err instanceof ApiError ? err.message : "Could not load dashboard data"))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-slate-900">Dashboard</h1>
      <p className="mt-1 text-sm text-slate-500">Real data from your LeadFlow AI backend — the same GET /analytics/summary the mobile app uses.</p>

      {loading && <p className="mt-8 text-sm text-slate-400">Loading...</p>}
      {error && (
        <div className="mt-8 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Could not load: {error}
        </div>
      )}

      {data && (
        <>
          <div className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
            <StatCard label="Total Leads" value={data.total_leads} />
            <StatCard label="Conversion Rate" value={`${data.conversion_rate}%`} />
            <StatCard label="Pending Follow-ups" value={data.pending_reminders} />
            <StatCard label="Overdue" value={data.overdue_reminders} />
          </div>

          <div className="mt-6 rounded-xl border border-slate-200 bg-white p-5">
            <h2 className="text-sm font-semibold text-slate-700">Pipeline by stage</h2>
            <div className="mt-4 space-y-2">
              {data.by_stage.map((s) => (
                <div key={s.stage} className="flex items-center justify-between text-sm">
                  <span className="text-slate-600">{s.stage}</span>
                  <span className="font-semibold text-slate-900">{s.count}</span>
                </div>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
