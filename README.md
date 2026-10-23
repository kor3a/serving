# Serving

iOS app for tennis and badminton players and racquet stringers. Players find
stringers on a map, order string (or bring their own), and book a drop-off.
Stringers run a storefront, take orders and get paid.

Open `Serving.xcodeproj` in Xcode and hit Run — it builds and runs against an
in-memory backend, so the whole flow works with no server.

## Requirements

- Xcode 15.2 or newer
- iOS 17.0+ simulator or device
- No third-party dependencies (nothing to install, no SPM resolution step)
- Python 3.10+ only if you're running the backend in `server/`

## Running it

The app starts on the mock backend (`AppConfig.useMockBackend = true`), which
implements every server call in memory:

| Step | What to do |
| --- | --- |
| Sign in as a **player** | Any email + any 8-character password |
| Sign in as a **business** | An email containing `shop` or `string`, e.g. `shop@serving.app` |
| Phone verification | Any 6-digit code (`424242` is the demo code) |
| Sign in with Apple | Works on device; returns a mock session in the simulator |

To exercise the full order lifecycle, run two simulators (or sign out and back
in) — place an order as a player, acknowledge it as the business and propose a
pick-up time, then accept it as the player.

## The order flow

This is the part of the product with real rules, so it is worth stating
plainly. **The player is never charged at checkout.**

```
Player submits request         → status: awaitingBusiness       (no charge)
Stringer acknowledges,
  proposes a pick-up date/time → status: awaitingPlayerApproval (no charge)
Player accepts the time        → Stripe PaymentIntent captured
                               → status: confirmed
Stringer starts the job        → status: inProgress
Stringer marks it ready,
  confirming location & time   → status: complete   (pick-up confirmation
                                                      pushed to both sides)
Stringer hands racquet back    → status: pickedUp
```

After the player accepts, they land on the **Order Confirmation** screen
(`Features/Player/OrderConfirmationView.swift`):

1. the horizontal order tracker — Order Confirmed → Order In Progress → Order
   Complete — in its own section at the top,
2. directly beneath it, `Drop Off Date & Time:` and `Pick Up Date & Time:` as
   agreed between the two sides,
3. then the receipt and order details.

`OrderStatus.trackerStep` is the single mapping from status to tracker
position, so the tracker cannot drift out of sync with the order.

When the stringer marks a racquet ready they first confirm the pick-up location
and the agreed time; both sides then get the **Pick-up confirmation**
(`Features/Shared/PickUpConfirmationView.swift`) with those details. The
stringer closes the order from there with **Hand over racquet** (`pickedUp`).

## Project layout

```
Serving/                     iOS app (SwiftUI)
├── App/                     App entry point, routing, composition root
│   ├── ServingApp.swift     @main, store wiring
│   ├── AppEnvironment.swift AppConfig + which Backend is used
│   ├── AppDelegate.swift    APNs registration
│   └── RootView.swift       Landing → auth → setup → business/player
├── Core/
│   ├── Models/              User, Business, Order, Payment
│   ├── Backend/             Backend protocol, MockBackend, seed data, pricing
│   ├── Networking/          APIClient, Endpoint/Routes, LiveBackend, TokenStore
│   ├── Services/            Location, Face ID, push notifications
│   └── DesignSystem/        Theme + shared components
└── Features/
    ├── Onboarding/          Landing, login, signup, account setup, phone verify
    ├── Stores/              SessionStore, OrderStore, DiscoverStore, BusinessStore
    ├── Shared/              OrderTrackerView, PickUpConfirmationView
    ├── Player/              Discover map, storefront, checkout, orders, profile
    └── Business/            Dashboard, orders, calendar, storefront management

server/                      Django + DRF API
├── serving/settings.py      Env-driven config (DB, JWT, Stripe, APNs)
└── api/
    ├── models.py            Users, businesses, storefront, orders
    ├── serializers.py       The wire format, matching the Swift CodingKeys
    ├── views.py             Every route in docs/API_CONTRACT.md
    ├── pricing.py           Mirrors PricingEngine.swift
    ├── payments.py          Stripe capture on accept-pickup
    ├── oauth.py sms.py push.py
    └── tests.py             Full lifecycle + payload-shape assertions
```

### Screens, mapped to the UI plan

**Onboarding** — Landing (brand logo) → Login (Apple, Google, Face ID, email +
password) → Signup (email) → Set Up Account (Business / Player tabs, prefilled
uneditable email, verified phone, 8-character password; businesses also give a
drop-off address, which can be a park if they work out of their home).

**Player** — Discover (map behind a results sheet, search by area, filters),
Orders, Profile.

**Business** — Home (active orders, pending orders, earnings snapshot, payout
status, Settings in the trailing nav position), Orders, Calendar (drop-offs and
pick-ups by day), Storefront (merchandise, service pricing, public profile).

## The backend

The Django + DRF service that the app talks to lives in `server/`. It runs on
SQLite out of the box and on Neon Postgres once `neon deploy` fills in its
connection strings.

Needs **Python 3.10+** (macOS ships 3.9, which can't install Django 5.2 —
`brew install python@3.13`).

```sh
cd server
./setup.sh                 # venv, deps, .env, migrate, seed
source .venv/bin/activate
python manage.py runserver
```

Then set `AppConfig.useMockBackend = false` in
`Serving/App/AppEnvironment.swift` and run the app in the simulator — sign in
as `player@serving.app` / `serving123`.

**docs/SETUP.md** is the full walkthrough: Neon provisioning, Django Auth,
Apple/Google sign-in, Stripe, Twilio, APNs and deployment.
**docs/API_CONTRACT.md** specifies every route and payload.
**docs/postgres_schema.sql** documents the Postgres schema (reference —
Django's migrations are what actually create the tables).

Two commands keep the halves in step:

```sh
python manage.py test            # order lifecycle + payload shapes
python manage.py check_contract  # diffs the API's JSON keys against Swift CodingKeys
```

### Payments

Nothing is charged from the device. `POST /orders/{id}/accept-pickup/` is where
the server creates and confirms the Stripe PaymentIntent, then returns the
confirmed order. Only the publishable key would ever live in the app
(`AppConfig.stripePublishableKey`); add the Stripe iOS SDK when you want the
native Apple Pay sheet, and pass the resulting payment method id along with
that request.

### Capabilities to switch on before shipping

The project builds without any signing capabilities so it runs out of the box.
Before a real build, add these in **Signing & Capabilities** and set
`CODE_SIGN_ENTITLEMENTS` to `Serving/Serving.entitlements`:

- Push Notifications (APNs)
- Sign in with Apple
- Apple Pay (merchant id `merchant.app.serving`)

Google sign-in needs the GoogleSignIn SDK; `LoginView.googleButton` marks the
one place to call it, and the ID token it returns goes to
`auth/oauth/google/`.

## Regenerating the Xcode project

The project file is generated from the files on disk. After adding, renaming or
deleting a source file:

```sh
python3 Scripts/generate_xcodeproj.py
```

Identifiers are derived from file paths, so the regenerated project is stable
and diffable rather than a wall of churn.
