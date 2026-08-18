"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import Link from "next/link";
import { getToken, getUser, clearSession, AuthUser } from "@/lib/api";

// Nav structure per the Master Spec §25. Only Dashboard and CRM are real
// pages this phase (Phase 1's own Definition of Done: prove the web app
// can do what the mobile app already does for core CRM before adding
// anything net-new). The rest are honestly marked "Coming soon" with
// which phase they arrive in (see IMPLEMENTATION_PLAN.md) rather than
// being fake pages that look finished but do nothing -- the Master
// Spec's own §32 rule ("no fake functionality... dead buttons... mark
// NOT CONNECTED with a clear path") applied to unfinished nav, not just
// unfinished providers.
const NAV_ITEMS: { label: string; href: string; phase?: string }[] = [
  { label: "Dashboard", href: "/dashboard" },
  { label: "CRM", href: "/crm" },
  { label: "AI Workforce", href: "/ai-workforce", phase: "Phase 2" },
  { label: "Opportunities", href: "/opportunities", phase: "Phase 3" },
  { label: "Campaigns", href: "/campaigns", phase: "Phase 3" },
  { label: "Creative Studio", href: "/creative-studio", phase: "Phase 6" },
  { label: "Automations", href: "/automations", phase: "Phase 5" },
  { label: "Knowledge", href: "/knowledge", phase: "Phase 4" },
  { label: "Analytics", href: "/analytics", phase: "Phase 8" },
  { label: "Integrations", href: "/integrations", phase: "Phase 6" },
  { label: "Credits & Billing", href: "/billing", phase: "Phase 7" },
  { label: "Settings", href: "/settings", phase: "Phase 1" },
];

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<AuthUser | null>(null);
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      router.replace("/login");
      return;
    }
    setUser(getUser());
    setChecked(true);
  }, [router]);

  if (!checked) return null;

  function handleLogout() {
    clearSession();
    router.replace("/login");
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <aside className="flex w-60 shrink-0 flex-col border-r border-slate-200 bg-white">
        <div className="border-b border-slate-200 px-5 py-4">
          <span className="text-sm font-bold text-slate-900">LeadFlow AI</span>
        </div>
        <nav className="flex-1 space-y-0.5 p-3">
          {NAV_ITEMS.map((item) => {
            const active = pathname?.startsWith(item.href);
            const disabled = Boolean(item.phase);
            return (
              <Link
                key={item.href}
                href={disabled ? "#" : item.href}
                aria-disabled={disabled}
                className={`flex items-center justify-between rounded-lg px-3 py-2 text-sm transition ${
                  disabled
                    ? "cursor-not-allowed text-slate-300"
                    : active
                    ? "bg-slate-900 text-white"
                    : "text-slate-700 hover:bg-slate-100"
                }`}
                onClick={(e) => disabled && e.preventDefault()}
              >
                <span>{item.label}</span>
                {item.phase && <span className="text-[10px] text-slate-300">{item.phase}</span>}
              </Link>
            );
          })}
        </nav>
        <div className="border-t border-slate-200 p-3">
          <p className="truncate px-2 text-xs font-medium text-slate-700">{user?.full_name}</p>
          <p className="truncate px-2 text-xs text-slate-400">{user?.email}</p>
          <button
            onClick={handleLogout}
            className="mt-2 w-full rounded-lg px-2 py-1.5 text-left text-xs font-semibold text-slate-500 hover:bg-slate-100"
          >
            Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 overflow-y-auto">{children}</main>
    </div>
  );
}
