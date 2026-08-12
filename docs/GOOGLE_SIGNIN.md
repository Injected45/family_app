# Getting a Google web client ID

This is the last thing blocking sign-in. It takes about fifteen minutes and costs
nothing.

You are creating **one OAuth 2.0 Client ID of type "Web application"**. That
single ID is used in two places — the Flutter app sends it to Google, and the API
uses it to verify that the token it receives was issued for *this* application.

**You do not need the client secret.** The console will show you one; ignore it.
This server verifies Google's ID tokens against Google's public keys, which needs
only the ID. If you paste a secret into `GOOGLE_CLIENT_ID_WEB`, `npm run preflight`
will tell you so.

> The Cloud Console's menu wording shifts every few months. The labels below were
> current at the time of writing; if something has moved, search the console for
> the words in **bold** rather than following a path that no longer exists.

---

## 1. Create a project

Go to <https://console.cloud.google.com/>. In the project picker at the top,
choose **New project**.

- Name: `Family Association` (or anything — this is internal)
- Leave the organisation and location as they are

Wait for it to be created, then make sure it is the selected project. Everything
below applies to the selected project, and creating credentials in the wrong one
is a common half-hour lost.

---

## 2. Configure the consent screen

Google will not issue credentials until it knows what users are consenting to.
Look for **Google Auth Platform** (previously **OAuth consent screen**) — it is
under **APIs & Services**, or directly at
<https://console.cloud.google.com/auth/overview>.

Fill in **Branding**:

| Field | Value |
|---|---|
| App name | `جمعية العائلة` — this is what members see on the consent screen |
| User support email | your email |
| Developer contact email | your email |

Then **Audience**. You have a real choice here:

**Option A — Testing (recommended to start).** Add each member's Google address
under **Test users**. Only those addresses can sign in, up to 100. No Google
review, no waiting. For an extended family this may be all you ever need, and it
is a genuine second lock: even if someone learns the URL, Google refuses them
before your approval screen is reached.

**Option B — In production.** Anyone with a Google account can *reach* the sign-in
screen; your own approval step still decides who gets in. Because this app asks
only for name, email and profile picture — all "non-sensitive" scopes — **you do
not need Google's verification review** to publish. Choose this if the association
has more than 100 members, or if maintaining a test-user list is a chore.

You can switch from A to B later without changing any code.

Under **Data access**, confirm the scopes are only `openid`,
`.../auth/userinfo.email` and `.../auth/userinfo.profile`. Do not add others —
anything more triggers a verification review you do not need.

> **A note specific to this app.** In Testing mode, Google expires *its* refresh
> tokens after seven days, which breaks many apps every week. It does not affect
> this one: the Google ID token is used exactly once, at sign-in, and the API then
> issues its own session tokens. Nobody gets signed out on a seven-day cycle.

---

## 3. Create the client ID

Go to **APIs & Services → Credentials**
(<https://console.cloud.google.com/apis/credentials>), then
**+ Create credentials → OAuth client ID**.

- **Application type: Web application** — this matters. Pick this even if you
  only ever ship the Android app, because the Android client sends the *web*
  client ID as its `serverClientId` so the server can verify the audience.
- Name: `Family Association web`

Now the important part.

---

## 4. Register the exact origins you will browse to

Under **Authorised JavaScript origins**, add every origin the app is served from.
Google matches these **exactly**:

- no trailing slash — `http://localhost:3000`, not `http://localhost:3000/`
- no path — the origin only
- no wildcards
- **`localhost` and `127.0.0.1` are different origins.** Register the one you
  actually type into the browser. This wastes more time than any other single
  detail here.

Which to add depends on how you run it:

**Development, single origin** (the API serves the built web app — the recommended
setup):

```
http://localhost:3000
```

**Development with hot reload** (Flutter's own dev server). Its port is random by
default, and a new port every run means a new origin Google rejects — so pin it:

```bash
flutter run -d chrome --web-port=5000
```

```
http://localhost:5000
```

**Production**, once you have a hostname:

```
https://jamiya.example.ly
```

HTTPS is required in production; `localhost` is the one exception Google allows
over plain HTTP.

**Authorised redirect URIs** can be left empty. The sign-in flow this app uses
returns an ID token to the page rather than redirecting, so no redirect URI is
involved. Adding one does no harm if the console insists.

Press **Create**. Copy the **Client ID** — it looks like:

```
123456789012-a1b2c3d4e5f6g7h8i9j0.apps.googleusercontent.com
```

Ignore the client secret.

---

## 5. Put it in both places

It goes in **two** places, and they must be the **same value**.

**The API** — `api/.env`:

```
GOOGLE_CLIENT_ID_WEB=123456789012-a1b2c3d4e5f6g7h8i9j0.apps.googleusercontent.com
```

**The app** — at build or run time:

```bash
cd app
flutter run -d chrome --web-port=5000 \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=123456789012-a1b2....apps.googleusercontent.com \
  --dart-define=GOOGLE_CLIENT_ID=123456789012-a1b2....apps.googleusercontent.com
```

For a release build served from the API itself:

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<the same id> \
  --dart-define=GOOGLE_CLIENT_ID=<the same id>
```

`API_BASE_URL=/api/v1` is a relative path, so the app talks to whatever host
served it and nothing needs changing when the hostname does.

---

## 6. Check it

```bash
cd api
npm run preflight
```

The `GOOGLE_CLIENT_ID_WEB` line should read `ok`. It catches a mistyped ID, and
specifically catches pasting the secret instead.

Then start the API, open the app, and press **الدخول بحساب Google**.

**The first account to sign in becomes the administrator.** Make sure that is
you. Everyone afterwards lands on "بانتظار الموافقة" until you approve them from
the **إدارة المستخدمين** screen.

If a placeholder seed user is still in the database, that bootstrap will not fire
— `npm run preflight` reports it, and the fix is
`npm run db:reset && npm run migrate` before importing real data.

---

## When it does not work

| What you see | What it means |
|---|---|
| `Error 400: redirect_uri_mismatch` or `origin_mismatch` | The origin you are browsing is not in **Authorised JavaScript origins**. Check for a trailing slash, and check `localhost` vs `127.0.0.1` |
| The button does nothing, console shows an origin error | Same cause. Flutter's dev server changed port — pin it with `--web-port` |
| `403: access_denied` right after choosing an account | You are in **Testing** mode and that address is not a **Test user** |
| `503 GOOGLE_NOT_CONFIGURED` from the API | `GOOGLE_CLIENT_ID_WEB` is not set in `api/.env`, or the API was not restarted after setting it |
| `401 INVALID_GOOGLE_TOKEN` | The app and the API are using **different** client IDs, or `GOOGLE_SERVER_CLIENT_ID` was not passed to the build. They must match exactly |
| `403 ACCOUNT_PENDING` | Sign-in worked. This is the approval gate — an administrator must approve the account |
| Works in development, fails in the installed Android app | The release signing certificate's SHA-1 is not registered. See `app/README.md` |
| Changes to origins seem ignored | Google can take a few minutes to propagate. Wait, then try a private window |

Two failures worth telling apart: **`INVALID_GOOGLE_TOKEN` means the IDs do not
match**, while **`ACCOUNT_PENDING` means everything worked** and you simply need
to approve the account.

---

## Later: Android and iOS

Only needed if you ship native apps; the web app is complete on its own.

Create additional client IDs of type **Android** / **iOS** in the same project.
For Android you register the package name `ly.rhalla.family_app` together with a
signing certificate SHA-1 — and you must register **both** the debug and the
release fingerprints, or sign-in works on your machine and fails in the store
build. Keep passing the **web** client ID as `GOOGLE_SERVER_CLIENT_ID`; the
platform ID goes in `GOOGLE_CLIENT_ID`.

```bash
# debug fingerprint
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android -keypass android

# release fingerprint
keytool -list -v -keystore upload-keystore.jks -alias upload
```
