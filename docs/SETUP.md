# Running Serving against a real backend

The iOS app ships with an in-memory backend so it runs with no server at all.
This guide switches it over to the Django + Postgres service in `server/`.

Work through it in order — each part stands on its own, and you can stop after
Part 2 and have a fully working app on SQLite.

---

## Part 0 — Python

**You need Python 3.10 or newer.** macOS still ships 3.9 as `python3`, and
Django 5.2 will not install on it. Check first:

```sh
python3 --version
```

If that prints 3.9.x (or pip only offers you `Django 4.2` and older), install a
current Python:

```sh
brew install python@3.13
```

or use the installer from https://www.python.org/downloads/macos/. You don't
need to replace the system Python — `setup.sh` below finds the newest one
installed and uses that.

---

## Part 1 — Run the server locally (10 minutes)

No database setup needed yet; without `DATABASE_URL` the server uses a local
SQLite file.

```sh
cd server
./setup.sh
```

That picks a suitable Python, creates `.venv`, installs dependencies, copies
`.env.example` to `.env`, migrates and seeds demo data. Then:

```sh
source .venv/bin/activate
python manage.py runserver
```

<details>
<summary>Doing it by hand instead</summary>

```sh
cd server
python3.13 -m venv .venv           # an explicit 3.10+ interpreter
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env               # defaults are fine to start
python manage.py migrate
python manage.py seed_demo         # demo shops + two sign-in-able accounts
python manage.py runserver
```

</details>

If you already made a `.venv` with the wrong Python, rebuild it with
`./setup.sh --recreate`.

Check it's alive:

```sh
curl http://localhost:8000/v1/health/
# {"status":"ok","time":"2026-08-11T18:30:00Z"}
```

`seed_demo` creates:

| Account | Password | What it is |
| --- | --- | --- |
| `player@serving.app` | `serving123` | Player account |
| `shop@serving.app` | `serving123` | Business account managing Baseline String Lab |

plus five Sunnyvale-area shops — three Serving storefronts and two unclaimed
ones, so the map shows both kinds of pin.

Want an admin UI? `python manage.py createsuperuser`, then
http://localhost:8000/admin/ — you can inspect and edit every order there.

---

## Part 2 — Point the app at it

In `Serving/App/AppEnvironment.swift`:

```swift
static let useMockBackend = false
```

That's the only change. `apiBaseURL` already defaults to
`http://localhost:8000/v1/` in DEBUG builds.

Run the app in the **simulator** and sign in as `player@serving.app` /
`serving123`.

### On a physical device

The phone can't see your Mac's `localhost`. Find your Mac's LAN address
(System Settings → Wi-Fi → Details, or `ipconfig getifaddr en0`), then:

```sh
python manage.py runserver 0.0.0.0:8000
```

and set the DEBUG branch of `apiBaseURL` to `http://192.168.1.20:8000/v1/`
(your address). Both devices must be on the same Wi-Fi.

Plain HTTP works because `Serving/Resources/Info.plist` carries an App
Transport Security exception for local networking. **Delete that
`NSAppTransportSecurity` dictionary before shipping** — production runs on
HTTPS, which needs no exception.

### Signing up a fresh account

There's no SMS provider yet, so the verification code is printed in the server
console:

```
WARNING SMS not configured — verification code for 4085550199 is 442278
```

In DEBUG the same code also comes back as `dev_code` in the API response.

---

## Part 3 — Move to Neon Postgres

SQLite is fine for one developer. Switch to Postgres when you want the data to
outlive your laptop, or before you invite anyone else in.

Neon only provides the database here. Sign-in stays in Django (Part 4), so
there is no Neon Auth or other auth provider to set up.

### 3.1 Link the project

`server/neon.ts` declares Postgres as the only service. The link to the Neon
project lives in `server/.neon`, which is gitignored, so a fresh clone links
it once. You need Node.js for the CLI:

```sh
npm i -g neon@latest
cd server
npm install            # @neon/config, which neon.ts imports
neon login             # opens a browser sign-in
neon init -y --no-config --org-id org-fancy-night-32625238 \
    --project-id silent-river-47185799 --branch production
neon deploy            # applies neon.ts and pulls env vars into .env
```

### 3.2 The two connection strings

`neon deploy` (and `neon env pull`) writes both into `server/.env`:

| Variable | Host | Used for |
| --- | --- | --- |
| `DATABASE_URL` | `ep-…-pooler…neon.tech` | Everything the running app does |
| `DATABASE_URL_UNPOOLED` | `ep-…neon.tech` | `migrate`, `test`, `dbshell` — picked automatically |

The pooled host runs PgBouncer in transaction mode, so `settings.py` turns off
server-side cursors whenever it's in use. Schema changes go over the direct
host. Neon computes suspend after five idle minutes, so persistent connections
are health-checked before reuse; the first request after a pause takes a few
hundred milliseconds longer.

### 3.3 Migrate

```sh
python manage.py migrate
python manage.py seed_demo
python manage.py createsuperuser
```

Then check **Tables** in the Neon console — you should see `api_user`,
`api_business`, `api_order` and friends.

### Branches

`neon checkout dev --create` makes a copy-on-write branch of the database
(it expires after 7 days, per `neon.ts`) and points `.env` at it — handy for
trying a migration against real data before running it on `production`.

### About `docs/postgres_schema.sql`

That file documents the target schema and is useful for reading the data model
or hand-provisioning. **Don't run it against the same database Django
manages** — Django's migrations own these tables, and running both leaves you
with two conflicting definitions. Use `manage.py migrate`; treat the SQL file
as reference.

### Row Level Security

Django connects as the Postgres owner and enforces access in the API layer, so
RLS is not required. If you later let clients read these tables directly
(Neon's Data API, for instance), turn RLS on then.

---

## Part 4 — Auth, in more detail

Django Auth is already wired up; there is nothing to configure for
email/password. What's worth knowing:

- **Custom user model** (`api.User`): email is the username, and it carries
  `account_type`, `phone`, `phone_verified` and the `business` link.
- **`setup_complete`** is the flag that drives onboarding. `POST /auth/signup/`
  returns `"user": null`, which is what routes the app to `SetUpAccountView`;
  `POST /auth/account-setup/` sets the password, creates the business (for
  stringers), flips the flag, and returns the full user.
- **Phone verification is enforced server-side.** The client's
  `phone_verified: true` is treated as a UI hint — `account-setup` re-checks
  that the number was actually verified in the last hour and rejects it
  otherwise.
- **JWTs** come from SimpleJWT: a 60-minute access token and a 30-day refresh
  token, both stored in the iOS keychain. `APIClient` refreshes automatically
  on a 401 and signs the user out if that fails.

### Sign in with Apple

1. Enable the capability in Xcode (Signing & Capabilities) and on the App ID in
   the Apple Developer portal.
2. Set `APPLE_BUNDLE_ID` in `.env` to your bundle identifier — it's the
   audience the identity token is verified against.
3. Set `OAUTH_ALLOW_UNVERIFIED_TOKENS=false`.

The app already sends a real identity token from `SignInWithAppleButton`; the
server verifies its signature against Apple's JWKS.

### Google sign-in

The app has the button and the endpoint, but not the SDK — it currently sends a
placeholder token that only the dev-mode fallback accepts. To finish it:

1. Add the GoogleSignIn SDK via Swift Package Manager.
2. Create an **iOS OAuth client** in Google Cloud Console; put its client id in
   `GOOGLE_CLIENT_IDS` and its reversed form in the app's URL schemes.
3. In `LoginView.googleButton`, present the SDK and pass the returned ID token
   to `session.signInWithGoogle(idToken:)`.

Then set `OAUTH_ALLOW_UNVERIFIED_TOKENS=false`.

---

## Part 5 — Payments, SMS and push

All three degrade gracefully: leave the credentials blank and the flows still
work locally, with the real call replaced by a log line.

### Stripe

```sh
STRIPE_SECRET_KEY=sk_test_...
```

Payment is captured in exactly one place — `POST /orders/{id}/accept-pickup/`,
when the player accepts the proposed pick-up time. Nothing is charged at
checkout, so there's no authorize/capture pair to manage.

For the money to reach stringers rather than your own balance, set up **Stripe
Connect**: onboard each business, store the connected account id on
`Business.stripe_account_id`, and `payments.py` will route the charge with
`application_fee_amount` set to Serving's service fee.

Apple Pay needs the Stripe iOS SDK on the client to produce a payment method
id; pass it as `payment_method_id` in the accept-pickup call.

### Twilio (SMS codes)

```sh
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=+14085550000
```

Also `pip install twilio` — it's imported lazily so it stays optional.

### APNs (push notifications)

1. Apple Developer → **Keys** → new key with APNs enabled. Download the `.p8`
   once.
2. ```sh
   APNS_KEY_ID=ABC123DEFG
   APNS_TEAM_ID=YOURTEAMID
   APNS_KEY_PATH=/absolute/path/to/AuthKey_ABC123DEFG.p8
   APNS_TOPIC=app.serving.Serving
   APNS_USE_SANDBOX=true
   ```
3. `pip install "httpx[http2]"` — APNs requires HTTP/2.
4. Enable Push Notifications in Xcode's Signing & Capabilities and set
   `CODE_SIGN_ENTITLEMENTS` to `Serving/Serving.entitlements`.

Push is best-effort: the app also refreshes on pull-to-refresh and on
appearance, so a missing notification never strands an order.

---

## Part 6 — Deploying

Any host that runs Django works. Minimum checklist:

```sh
DJANGO_DEBUG=false
DJANGO_SECRET_KEY=<50+ random characters>
DJANGO_ALLOWED_HOSTS=api.yourdomain.com
DATABASE_URL=<Neon pooled URI>
DATABASE_URL_UNPOOLED=<Neon direct URI>
OAUTH_ALLOW_UNVERIFIED_TOKENS=false
```

Then:

- run `python manage.py migrate` on deploy,
- serve with gunicorn or uvicorn (`serving.wsgi:application`),
- terminate TLS at the load balancer,
- remove the `NSAppTransportSecurity` block from `Info.plist`,
- point the release branch of `apiBaseURL` at your domain.

`DJANGO_DEBUG=false` turns off two development conveniences on purpose: the
`dev_code` field disappears from phone verification responses, and the
browsable API renderer is disabled.

---

## Checking that the two halves agree

Two commands, both worth running after any model change:

```sh
python manage.py test            # 29 tests: full order lifecycle + payload shapes
python manage.py check_contract  # diffs the API's JSON keys against the Swift CodingKeys
```

`check_contract` parses `CodingKeys` out of `Serving/Core/Models/*.swift`,
renders each serializer, and fails if a key is missing, renamed or unexpected.
It's the guard against a change on one side quietly breaking decoding on the
other — which is otherwise invisible until the app throws at runtime.

---

## Troubleshooting

**`Could not find a version that satisfies the requirement Django==5.2.x`**,
with the offered list stopping around 4.2 — you're on Python 3.9 (the macOS
system one). See Part 0, then `./setup.sh --recreate`.

**`connection to server ... failed: SSL required`** — set `DB_SSL_REQUIRE=true`.

**`Failed building wheel for psycopg` / `pg_config not found`** — pip fell back
to a source build because no wheel matched your platform. `pip install
"psycopg[binary]"` should use a prebuilt wheel; if it still fails, install
libpq (`brew install libpq`) and retry.

**`could not translate host name`** — you copied the URI without replacing
`[YOUR-PASSWORD]`, or the password has an unescaped `@`. Percent-encode it.

**App shows "Please sign in again" immediately** — the access token was
rejected. Check the server console; usually the JWT was signed with a
different `DJANGO_SECRET_KEY` than the one now running.

**`The request timed out` in the simulator** — the server is bound to
`127.0.0.1` only. That's fine for the simulator but check it's actually
running; for a device use `runserver 0.0.0.0:8000`.

**`A server with the specified hostname could not be found` on device** — the
phone is on cellular or a different Wi-Fi than the Mac.

**Decoding errors after adding a field** — run `check_contract`. A Swift model
with a new non-optional property fails to decode until the server sends it.

**Orders show up empty for a business account** — the signed-in user has no
`business_id`. That link is created during account setup; for a hand-made user,
set it in the admin.
