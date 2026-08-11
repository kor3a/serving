# Tensora

iOS app for tennis and badminton players and racquet stringers. Players find
stringers on a map, order string (or bring their own), and book a drop-off.
Stringers run a storefront, take orders and get paid.

Open `Tensora.xcodeproj` in Xcode and hit Run — it builds and runs against an
in-memory backend, so the whole flow works with no server.

## Requirements

- Xcode 15.2 or newer
- iOS 17.0+ simulator or device
- No third-party dependencies (nothing to install, no SPM resolution step)

## Running it

The app starts on the mock backend (`AppConfig.useMockBackend = true`), which
implements every server call in memory:

| Step | What to do |
| --- | --- |
| Sign in as a **player** | Any email + any 8-character password |
| Sign in as a **business** | An email containing `shop` or `string`, e.g. `shop@tensora.app` |
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
Stringer marks it done         → status: complete
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

## Project layout

```
Tensora/
├── App/                     App entry point, routing, composition root
│   ├── TensoraApp.swift     @main, store wiring
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
    ├── Shared/              OrderTrackerView
    ├── Player/              Discover map, storefront, checkout, orders, profile
    └── Business/            Dashboard, orders, calendar, storefront management
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

## Connecting the Django backend

1. Set `AppConfig.useMockBackend = false` and point `AppConfig.apiBaseURL` at
   your service.
2. Implement the routes in `docs/API_CONTRACT.md`. `LiveBackend` already calls
   all of them; `Core/Networking/Endpoint.swift` lists every path in one place.
3. The client sends and receives snake_case JSON with ISO-8601 timestamps, and
   expects a `{access_token, refresh_token, user, email}` payload from the auth
   endpoints. Tokens are stored in the keychain and refreshed automatically on
   a 401.

`docs/supabase_schema.sql` has a starting Postgres schema matching the models.

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
`CODE_SIGN_ENTITLEMENTS` to `Tensora/Tensora.entitlements`:

- Push Notifications (APNs)
- Sign in with Apple
- Apple Pay (merchant id `merchant.app.tensora`)

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
