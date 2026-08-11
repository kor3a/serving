# Running Tensora against a real backend

The iOS app ships with an in-memory backend so it runs with no server at all.
This guide switches it over to the Django + Postgres service in `server/`.

Work through it in order — each part stands on its own, and you can stop after
Part 2 and have a fully working app on SQLite.

---

## Part 1 — Run the server locally (10 minutes)

No database setup needed yet; without `DATABASE_URL` the server uses a local
SQLite file.

```sh
cd server
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env               # defaults are fine to start
python manage.py migrate
python manage.py seed_demo         # demo shops + two sign-in-able accounts
python manage.py runserver
```

Check it's alive:

```sh
curl http://localhost:8000/v1/health/
# {"status":"ok","time":"2026-08-11T18:30:00Z"}
```

`seed_demo` creates:

| Account | Password | What it is |
| --- | --- | --- |
| `player@tensora.app` | `tensora123` | Player account |
| `shop@tensora.app` | `tensora123` | Business account managing Baseline String Lab |

plus five Sunnyvale-area shops — three Tensora storefronts and two unclaimed
ones, so the map shows both kinds of pin.

Want an admin UI? `python manage.py createsuperuser`, then
http://localhost:8000/admin/ — you can inspect and edit every order there.

---

## Part 2 — Point the app at it

In `Tensora/App/AppEnvironment.swift`:

```swift
static let useMockBackend = false
```

That's the only change. `apiBaseURL` already defaults to
`http://localhost:8000/v1/` in DEBUG builds.

Run the app in the **simulator** and sign in as `player@tensora.app` /
`tensora123`.

### On a physical device

The phone can't see your Mac's `localhost`. Find your Mac's LAN address
(System Settings → Wi-Fi → Details, or `ipconfig getifaddr en0`), then:

```sh
python manage.py runserver 0.0.0.0:8000
```

and set the DEBUG branch of `apiBaseURL` to `http://192.168.1.20:8000/v1/`
(your address). Both devices must be on the same Wi-Fi.

Plain HTTP works because `Tensora/Resources/Info.plist` carries an App
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

## Part 3 — Move to Supabase Postgres

SQLite is fine for one developer. Switch to Postgres when you want the data to
outlive your laptop, or before you invite anyone else in.

### 3.1 Create the project

1. https://supabase.com/dashboard → **New project**.
2. Pick a region near your users, and save the database password — the
   dashboard shows it exactly once.
3. Wait for provisioning (~2 minutes).

### 3.2 Get the connection string

**Project Settings → Database → Connection string → URI.**

Supabase gives you three; use the one that matches how you run Django:

| Mode | Port | Use it when |
| --- | --- | --- |
| Direct connection | 5432 | Long-lived server (a VM, Fly.io, Render) |
| Session pooler | 5432 | Same, behind IPv4. The safe default. |
| Transaction pooler | 6543 | Serverless / autoscaling with many short-lived processes |

Django holds connections open, so **session pooler** is the right default.
Don't use the transaction pooler with `DB_CONN_MAX_AGE` — set it to `0` if
you must.

Put it in `server/.env`, replacing `[YOUR-PASSWORD]`:

```sh
DATABASE_URL=postgresql://postgres.abcdefghijkl:YOUR-PASSWORD@aws-0-us-west-1.pooler.supabase.com:5432/postgres
DB_SSL_REQUIRE=true
```

If your password contains `@`, `/`, `#` or `?`, percent-encode it
(`@` → `%40`), or the URL won't parse.

### 3.3 Migrate

```sh
python manage.py migrate
python manage.py seed_demo
python manage.py createsuperuser
```

Then check **Table Editor** in Supabase — you should see `api_user`,
`api_business`, `api_order` and friends.

### About `docs/supabase_schema.sql`

That file documents the target schema and is useful for reading the data model
or hand-provisioning. **Don't run it against the same database Django
manages** — Django's migrations own these tables, and running both leaves you
with two conflicting definitions. Use `manage.py migrate`; treat the SQL file
as reference.

### Row Level Security

Django connects as the Postgres owner and enforces access in the API layer, so
RLS is not required. If you later add Supabase client libraries reading these
tables directly, turn RLS on then — the API keys Supabase issues are meant to
be paired with it.

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
`application_fee_amount` set to Tensora's service fee.

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
   APNS_TOPIC=app.tensora.Tensora
   APNS_USE_SANDBOX=true
   ```
3. `pip install "httpx[http2]"` — APNs requires HTTP/2.
4. Enable Push Notifications in Xcode's Signing & Capabilities and set
   `CODE_SIGN_ENTITLEMENTS` to `Tensora/Tensora.entitlements`.

Push is best-effort: the app also refreshes on pull-to-refresh and on
appearance, so a missing notification never strands an order.

---

## Part 6 — Deploying

Any host that runs Django works. Minimum checklist:

```sh
DJANGO_DEBUG=false
DJANGO_SECRET_KEY=<50+ random characters>
DJANGO_ALLOWED_HOSTS=api.yourdomain.com
DATABASE_URL=<Supabase session pooler URI>
OAUTH_ALLOW_UNVERIFIED_TOKENS=false
```

Then:

- run `python manage.py migrate` on deploy,
- serve with gunicorn or uvicorn (`tensora.wsgi:application`),
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

`check_contract` parses `CodingKeys` out of `Tensora/Core/Models/*.swift`,
renders each serializer, and fails if a key is missing, renamed or unexpected.
It's the guard against a change on one side quietly breaking decoding on the
other — which is otherwise invisible until the app throws at runtime.

---

## Troubleshooting

**`connection to server ... failed: SSL required`** — set `DB_SSL_REQUIRE=true`.

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
