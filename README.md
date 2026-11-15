# Connect

A tiny macOS menu bar app for sending notes between two laptops.
New notes slide in from the right edge of the screen; click one to open it, then
**Reply** (keeps it in the same note) or **Send as New Note**.

## 1. One-time server setup (about 3 minutes, free)

1. Create a free project at https://supabase.com.
2. Dashboard → **SQL Editor** → paste `supabase/schema.sql` → **Run**.
3. Dashboard → **Project Settings → API**: copy the **Project URL** and the
   **anon / publishable key**.

## 2. Install on your laptop

```bash
scripts/build-app.sh
cp -R build/Connect.app /Applications/
open /Applications/Connect.app
```

Enter your name, open **"Server URL and key instead"**, and paste the URL and key.
Then use the menu bar heart → **Copy Pairing Code** and send that code to her.

## 3. Install on her laptop (first time only)

Send her `Connect.app` (zip it, then AirDrop). On her Mac:

1. Drag it into **Applications**.
2. Open it. macOS will warn that it's from an unidentified developer, because the app isn't
   notarized. Go to **System Settings → Privacy & Security → Open Anyway**. You only need to do this once.
3. Enter her name and paste your pairing code.

From then on it starts at login and checks for notes every 5 seconds.

## Shipping an update (over the air)

```bash
scripts/release.sh "What changed"
```

This bumps the version, builds a universal app, signs the update with your Sparkle
key (kept in your login keychain under the account `connect`), and publishes a
GitHub release on `GITHUB_REPO` (see `version.env`). Her copy checks hourly and
installs updates silently. You can also use **Check for Updates…** in the menu.

For the very first release, publish the version she installed so update checks have a feed:

```bash
NO_BUMP=1 scripts/release.sh "First version"
```

## Notes

- No secrets are built into the app. Each laptop stores the server URL and key locally.
  Anyone who has the pairing code can read and write the notes, so only share it with her.
- **Back up the Sparkle private key.** If you lose it, you can't ship updates to her
  installed copy. Export it with:
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account connect -x connect-sparkle-key.txt`
- Each person's name identifies their notes, so use two different names.
