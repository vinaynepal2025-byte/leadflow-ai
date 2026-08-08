// backend/services/supabaseStorage.js
//
// Uploads a file buffer to Supabase Storage (bucket: leadflow-uploads).
//
// WHY THIS EXISTS: documents.js and voiceNotes.js previously used
// multer's diskStorage, writing to Render's local filesystem. Render's
// free tier disk is EPHEMERAL — every redeploy wipes it — so every
// previously "verified" document and voice note became permanently
// inaccessible (404) the next time the service redeployed. This was
// discovered live this session (confirmed via a real 404 on production
// for a voice note recorded earlier the same session). Supabase Storage
// is already free (1GB) and persists independently of the backend's own
// deploys, since it's a separate managed service.
//
// UPDATE (2026-08-08): bucket flipped to PRIVATE (was public-read).
// uploadFile() still returns a public-style URL string for backward
// compatibility with rows written before this change (documents.js
// download route branches on this). New reads should use getSignedUrl().
//
// Requires two env vars (Render + local .env):
//   SUPABASE_STORAGE_URL  — e.g. https://qovaakuithekhotkrrdi.supabase.co
//   SUPABASE_STORAGE_KEY  — the project's anon/publishable key (NOT the
//                           service_role key — deliberately scoped to
//                           least-privilege via a bucket-specific policy,
//                           so a leaked key only risks this one bucket,
//                           not full database access)

async function uploadFile(buffer, storagePath, contentType) {
  const baseUrl = process.env.SUPABASE_STORAGE_URL;
  const key = process.env.SUPABASE_STORAGE_KEY;
  if (!baseUrl || !key) {
    throw new Error('Supabase Storage not configured — set SUPABASE_STORAGE_URL and SUPABASE_STORAGE_KEY');
  }

  const uploadUrl = `${baseUrl}/storage/v1/object/leadflow-uploads/${storagePath}`;
  const res = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': contentType || 'application/octet-stream',
      'x-upsert': 'true',
    },
    body: buffer,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase Storage upload failed (${res.status}): ${text}`);
  }

  return `${baseUrl}/storage/v1/object/public/leadflow-uploads/${storagePath}`;
}

async function getSignedUrl(storagePath, expirySeconds) {
  const expiry = expirySeconds || 300;
  const baseUrl = process.env.SUPABASE_STORAGE_URL;
  const key = process.env.SUPABASE_STORAGE_KEY;
  if (!baseUrl || !key) {
    throw new Error('Supabase Storage not configured — set SUPABASE_STORAGE_URL and SUPABASE_STORAGE_KEY');
  }

  const signUrl = `${baseUrl}/storage/v1/object/sign/leadflow-uploads/${storagePath}`;
  const res = await fetch(signUrl, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ expiresIn: expiry }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase signed URL failed (${res.status}): ${text}`);
  }

  const data = await res.json();
  return `${baseUrl}/storage/v1${data.signedURL}`;
}

module.exports = { uploadFile, getSignedUrl };
