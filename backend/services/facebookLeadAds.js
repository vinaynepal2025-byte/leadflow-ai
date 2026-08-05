// backend/services/facebookLeadAds.js
// Same honest pattern as backend/services/whatsapp.js and services/payments.js:
// real Meta Graph API calls against the actual documented contract, but
// they only work once Vinay has his own Facebook Page + Developer App +
// Page Access Token — nobody can generate those for him.
//
// Setup (Vinay's side, not code):
//   1. Create a Facebook App at developers.facebook.com (Business type)
//   2. Add the "Webhooks" product, subscribe to the "leadgen" field on
//      his Facebook Page
//   3. Generate a long-lived Page Access Token (Graph API Explorer, or
//      via the standard OAuth token-exchange flow)
//   4. Set FACEBOOK_PAGE_ACCESS_TOKEN + LEAD_ADS_VERIFY_TOKEN in Render env vars
//   5. Register https://<render-url>/lead-ads/webhook as the webhook URL
//      in the Facebook App Dashboard, using the same LEAD_ADS_VERIFY_TOKEN

const GRAPH_API_VERSION = 'v21.0';

// When a lead-ad is submitted, Meta's webhook only sends a `leadgen_id` —
// the actual submitted field data has to be fetched separately via this call.
async function fetchLeadDetails(leadgenId) {
  const pageAccessToken = process.env.FACEBOOK_PAGE_ACCESS_TOKEN;
  if (!pageAccessToken) {
    throw new Error('Facebook Lead Ads not configured. Set FACEBOOK_PAGE_ACCESS_TOKEN in .env.');
  }

  const url = `https://graph.facebook.com/${GRAPH_API_VERSION}/${leadgenId}?access_token=${pageAccessToken}`;
  const res = await fetch(url);
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Facebook Graph API error: ${data.error?.message || JSON.stringify(data)}`);
  }

  // Meta returns field_data as [{name, values: [value]}, ...] — flatten
  // to a plain object. Field names depend entirely on how the lead form
  // was built in Meta Ads Manager (e.g. "full_name", "email",
  // "phone_number", or fully custom question keys).
  const fields = {};
  for (const f of data.field_data || []) {
    fields[f.name] = f.values?.[0] || null;
  }
  return fields;
}

module.exports = { fetchLeadDetails };
