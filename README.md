# Connect

A tiny macOS menu bar app for sending notes between two laptops.
New notes slide in from the right edge of the screen; click one to open it, then
**Reply** (keeps it in the same note) or **Send as New Note**.

## 1. One-time setup (about 10 minutes, free)

You both sign in with Google. The database only shows each person the notes they sent or received.

**Supabase (stores the notes)**
1. Create a free project at https://supabase.com.
2. **SQL Editor** → paste `supabase/schema.sql` → **Run**.
3. **Project Settings → API**: copy the **Project URL** and the **publishable (anon) key**.
4. Put them in `version.env` as `SUPABASE_URL=` and `SUPABASE_KEY=`. They get built into the
   app, so neither of you has to type them. The key is safe to ship because the database only
   answers people who are signed in.

**Google (the sign-in)**
1. Go to https://console.cloud.google.com and create a project (any name).
2. **Google Auth Platform → Branding / Audience**: set it up as **External** and leave it in
   **Testing**. Under **Test users**, add **both of your Gmail addresses**. Only those two
   accounts will be able to sign in.
3. **Clients → Create client → Web application**. Under **Authorized redirect URIs**, add
   `https://<your-project>.supabase.co/auth/v1/callback`.
   Copy the **Client ID** and **Client secret**.

**Connect the two**
1. Supabase → **Authentication → Sign In / Providers → Google**: turn it on and paste the
   Client ID and secret.
2. Supabase → **Authentication → URL Configuration → Redirect URLs**: add
   `connectnotes://auth-callback`.

## 2. Install on your laptop

```bash
scripts/build-app.sh
cp -R build/Connect.app /Applications/
open /Applications/Connect.app
```

Click **Sign in with Google**, then enter her Gmail address and click **Done**.

## 3. Install on her laptop (first time only)

Send her `Connect.app` (zip it, then AirDrop), or the zip from the latest GitHub release. On her Mac:

1. Drag it into **Applications**.
2. Open it. macOS will warn that it's from an unidentified developer, because the app isn't
   notarized. Go to **System Settings → Privacy & Security → Open Anyway**. You only need to do this once.
3. She signs in with Google and enters your Gmail address.

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

- Sign-in stays active: the app refreshes its Google session in the background. You can sign out
  or change who you're writing to under the menu bar heart → **Account…**.
- The sign-in session is stored in `~/Library/Application Support/Connect/session.json`
  (readable only by you). It isn't in the Keychain, because the app isn't signed with an Apple
  developer certificate, and the Keychain would otherwise ask for permission after every update.
- **Back up the Sparkle private key.** If you lose it, you can't ship updates to her
  installed copy. Export it with:
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account connect -x connect-sparkle-key.txt`
