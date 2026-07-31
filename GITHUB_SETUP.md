# LeadFlow AI — GitHub Upload & Install Guide

Follow this once. After that, every time you push a code change, GitHub
automatically rebuilds the app and updates both install links — you never
run a build command yourself.

---

## Step 1 — Create the GitHub repository

1. Go to [github.com/new](https://github.com/new)
2. Repository name: `leadflow-ai` (or anything you like)
3. Leave it **Public** (Private also works, but GitHub Pages needs a paid
   plan for private repos — Public is simplest and free)
4. Do **NOT** check "Add a README" — leave it completely empty
5. Click **Create repository**

---

## Step 2 — Upload the code (no command line needed)

**Recommended: GitHub Desktop** (a free app with buttons, not commands)

1. Download & install [desktop.github.com](https://desktop.github.com)
2. Sign in with your GitHub account
3. Unzip the project file I gave you, into any folder on your computer
4. In GitHub Desktop: **File → Add local repository** → pick that unzipped folder
5. If it says "this isn't a Git repository," click **create a repository here**
6. Bottom-left: type a commit message like "Initial upload" → **Commit to main**
7. Top bar: **Publish repository** → pick the `leadflow-ai` repo you made in Step 1 → **Publish**

That's it — every file (backend + mobile + the auto-build robot) is now on GitHub.

---

## Step 3 — Turn on GitHub Pages (one-time toggle)

1. On your repo's GitHub page: **Settings** tab → **Pages** (left sidebar)
2. Under "Build and deployment" → **Source**: choose **Deploy from a branch**
3. **Branch**: select `gh-pages` → `/ (root)` → **Save**

*(If `gh-pages` doesn't appear yet, that's fine — it's created automatically
the first time the build finishes. Come back here after Step 4 and select it then.)*

---

## Step 4 — Watch it build (takes about 5-8 minutes)

1. Click the **Actions** tab on your repo
2. You'll see "Build and Release LeadFlow AI" running (a yellow dot -> green check when done)
3. This is GitHub's own computer installing Flutter and building your app —
   nothing runs on your machine

---

## Step 5 — Install the app

**Option A — Web install (any phone, easiest)**
1. Go to `https://<your-github-username>.github.io/leadflow-ai/`
   (replace with your actual username and repo name)
2. On Android (Chrome): tap the menu (three dots) -> **Install app** / **Add to Home screen**
3. On iPhone (Safari): tap Share -> **Add to Home Screen**
4. It now behaves like a real installed app, with its own icon

**Option B — Android APK (direct install)**
1. On your repo page, click **Releases** (right sidebar)
2. Download `app-release.apk` from the latest build
3. Open the downloaded file on your Android phone -> allow "install unknown apps" if asked -> Install

---

## Step 6 — Point the app at your backend

The app itself only handles the screens — it still needs your **backend**
(the `backend/` folder) running somewhere reachable, exactly like before.
GitHub Pages/Releases only host the **app**, not the backend.

1. Deploy `backend/` to any Node.js host (Render, Railway, a VPS, etc.) —
   ask me for help with this when you're ready to pick one
2. Open the installed app -> on the Login screen, tap **Server Setup**
   (small link near the bottom)
3. Enter your backend's real address (e.g. `https://leadflow-api.onrender.com`)
4. Tap **Save & Test Connection** — it confirms it can reach it
5. Go back and log in normally

Until Step 6 is done, the app installs and opens fine, but can't load leads
yet — it's still pointed at "localhost," same as it always was in this chat.

---

## Making changes later

Edit files in the unzipped folder -> GitHub Desktop will show what changed ->
commit -> **Push origin**. The Actions robot rebuilds automatically within
a few minutes, and both the web link and the APK update themselves.
