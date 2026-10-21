# Serving API contract

What the iOS client expects from the Django REST Framework service. Every route
here is called by `Serving/Core/Networking/LiveBackend.swift`; the paths are
listed in `Endpoint.swift` under `Routes`.

## Conventions

- Base URL includes the version prefix: `https://api.serving.app/v1/`
- JSON in, JSON out, **snake_case** keys. The Swift models declare their
  `CodingKeys` explicitly, so the keys below are exactly what goes on the wire.
- Timestamps are ISO-8601 with a timezone: `2026-08-12T18:30:00Z`. The client
  parses with and without fractional seconds and always sends milliseconds.
- Money is a JSON **number**, 2 decimal places, USD. Set
  `COERCE_DECIMAL_TO_STRING: False` in DRF — the client decodes `Decimal` from
  a number and will fail on `"24.00"`.
- Enum values are the exact camelCase strings listed here (`awaitingBusiness`,
  `syntheticGut`, `applePay`, …), not snake_case.
- Auth: `Authorization: Bearer <access_token>`
- Errors: `{"detail": "..."}` or DRF field errors `{"phone": ["..."]}`
- `402` means the payment was declined; `401` triggers one refresh attempt then
  a forced sign-out

## Auth

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `auth/login/` | `email`, `password` | `AuthSession` |
| POST | `auth/signup/` | `email` | `AuthSession` with `user: null` |
| POST | `auth/oauth/apple/` | `identity_token`, `full_name?`, `email?` | `AuthSession` |
| POST | `auth/oauth/google/` | `id_token` | `AuthSession` |
| POST | `auth/token/refresh/` | `refresh` | `{"access": "..."}` |
| POST | `auth/logout/` | — | 204 |
| GET | `auth/me/` | — | `User` |
| POST | `auth/phone/request-code/` | `phone` | 204 |
| POST | `auth/phone/verify/` | `phone`, `code` | `{"verified": true}` |
| POST | `auth/account-setup/` | `AccountSetupDraft` | `AuthSession` |
| POST | `notifications/device-tokens/` | `token`, `platform` | 204 |

`AuthSession`:

```json
{
  "access_token": "…",
  "refresh_token": "…",
  "email": "player@example.com",
  "user": null
}
```

`user` is `null` until account setup finishes — that is what puts the app on
`SetUpAccountView`. Afterwards:

```json
{
  "id": "uuid",
  "email": "player@example.com",
  "account_type": "player",          // or "business"
  "display_name": "Alex Rivera",
  "owner_name": null,                 // business accounts only
  "phone": "(408) 555-0134",
  "phone_verified": true,
  "business_id": null,                // set for business accounts
  "avatar_url": null,
  "created_at": "2026-08-01T12:00:00Z"
}
```

`AccountSetupDraft` posts `account_type`, `email`, `password`, `phone`,
`phone_verified`, plus `business_name` / `owner_name` / `address` for
businesses or `player_name` for players. The server should re-verify the phone
server-side rather than trusting `phone_verified`.

## Discovery

`GET businesses/search/?lat=&lng=&radius_m=&q=` → `[Business]`

Results mix two kinds of record and the client branches on `is_claimed`:

- `is_claimed: true` — a Serving storefront. Full object, orderable.
- `is_claimed: false` — a shop sourced from map data with no account. Only
  `name`, `address`, `coordinate` and `phone` are shown, and the app offers a
  phone call instead of checkout.

`GET businesses/{id}/` → `Business`

```json
{
  "id": "uuid",
  "name": "Baseline String Lab",
  "owner_name": "Jordan Kim",
  "phone": "(408) 555-0110",
  "address": {"line1": "…", "line2": "", "city": "Sunnyvale", "state": "CA", "postal_code": "94085"},
  "coordinate": {"latitude": 37.376, "longitude": -122.021},
  "location_kind": "storefront",      // storefront | residential | publicMeetingSpot
  "is_claimed": true,
  "about": "…",
  "rating": 4.9,
  "rating_count": 213,
  "typical_turnaround_hours": 24,
  "accepts_bring_your_own_string": true,
  "bring_your_own_string_fee": 22,
  "drop_off_instructions": "…",
  "services": [
    {"id": "uuid", "name": "Standard Stringing", "details": "…",
     "labor_price": 22, "turnaround_hours": 24, "is_active": true}
  ],
  "inventory": [
    {"id": "uuid", "brand": "Luxilon", "name": "ALU Power", "category": "polyester",
     "sport": "tennis", "gauge": "16L / 1.25mm", "price": 24, "stock_count": 14,
     "details": "…", "is_active": true}
  ],
  "open_hours": [
    {"weekday": 1, "opens_at_minutes": 600, "closes_at_minutes": 1140, "is_closed": true}
  ]
}
```

`weekday` follows `Calendar.component(.weekday:)` — 1 is Sunday.
`category` is one of `polyester`, `multifilament`, `syntheticGut`,
`naturalGut`, `hybrid`, `badminton`. `sport` is `tennis` or `badminton`.

## Orders

| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| POST | `orders/` | `OrderDraft` | Creates an order in `awaitingBusiness`. **No charge.** |
| GET | `orders/?role=player\|business` | — | Orders for the caller in that role |
| GET | `orders/{id}/` | — | One order |
| POST | `orders/{id}/acknowledge/` | `proposed_pick_up_date`, `note?` | Business only → `awaitingPlayerApproval` |
| POST | `orders/{id}/decline/` | `reason?` | Business only → `declined` |
| POST | `orders/{id}/accept-pickup/` | `payment_method` | Player only. **Captures payment**, → `confirmed` |
| PATCH | `orders/{id}/status/` | `status` | Business only: `inProgress`, `complete` |
| POST | `orders/{id}/cancel/` | — | Refunds if already captured |

`OrderDraft`:

```json
{
  "business_id": "uuid",
  "service_id": "uuid",
  "drop_off_date": "2026-08-12T17:00:00Z",
  "payment_method": "applePay",        // applePay | card | payPal
  "note_for_stringer": "",
  "racquets": [
    {
      "id": "uuid",
      "sport": "tennis",
      "model": "Babolat Pure Aero 98",
      "main_tension": 52,
      "cross_tension": 50,
      "notes": "Logo stencil please.",
      "string_selection": {
        "kind": "storefront",
        "product_id": "uuid",
        "product_name": "Luxilon ALU Power",
        "price": 24
      }
    }
  ]
}
```

`string_selection` is a tagged object with exactly two shapes — a string bought
from the storefront, or one the player brings themselves:

```json
{"kind": "storefront", "product_id": "uuid", "product_name": "…", "price": 24}
{"kind": "byos", "description": "Solinco Tour Bite 17"}
```

`Order` adds server-owned fields on top of the draft:

```json
{
  "id": "uuid",
  "order_number": "TN-4831",
  "business_id": "uuid", "business_name": "…", "business_phone": "…",
  "player_id": "uuid", "player_name": "…", "player_phone": "…",
  "racquets": [ … ],
  "service_id": "uuid", "service_name": "Standard Stringing",
  "drop_off_date": "2026-08-12T17:00:00Z",
  "drop_off_address": { … },
  "drop_off_instructions": "…",
  "proposed_pick_up_date": null,
  "confirmed_pick_up_date": null,
  "business_note": null,
  "pricing": {
    "strings_subtotal": 24,
    "labor_subtotal": 22,
    "bring_your_own_string_fee": 0,
    "service_fee": 2.99,
    "tax": 4.24
  },
  "payment": {
    "method": "applePay",
    "state": "requiresPaymentMethod",
    "payment_intent_id": null,
    "charged_at": null,
    "last4": null
  },
  "status": "awaitingBusiness",
  "created_at": "…",
  "updated_at": "…"
}
```

`status`: `awaitingBusiness`, `awaitingPlayerApproval`, `confirmed`,
`inProgress`, `complete`, `declined`, `cancelled`.

`payment.state`: `requiresPaymentMethod`, `requiresConfirmation`, `processing`,
`succeeded`, `failed`, `refunded`.

The server owns `pricing`. `PricingEngine.swift` mirrors the arithmetic for the
pre-submit estimate — keep the two in step:

```
strings_subtotal          = Σ price of storefront strings
labor_subtotal            = service.labor_price × racquet count
bring_your_own_string_fee = business fee × BYOS racquet count
service_fee               = max($1.49, 6% of the above)
tax                       = resolved from the drop-off address
```

The stringer's payout is `strings_subtotal + labor_subtotal +
bring_your_own_string_fee` — the service fee is Serving's.

## Storefront management

| Method | Path | Body |
| --- | --- | --- |
| PATCH | `businesses/{id}/` | Partial `Business` |
| PUT | `businesses/{id}/products/` | `StringProduct` (upsert by id) |
| DELETE | `businesses/{id}/products/{product_id}/` | — |
| PUT | `businesses/{id}/services/` | `StringingService` (upsert by id) |
| DELETE | `businesses/{id}/services/{service_id}/` | — |
| GET | `businesses/{id}/earnings/` | — |

`earnings`:

```json
{
  "pending_payout": 184.50,
  "paid_out_this_month": 1260.75,
  "gross_this_week": 412.00,
  "completed_orders_this_month": 38,
  "next_payout_date": "2026-08-13T00:00:00Z",
  "payout_status": "active"            // notConnected | pendingVerification | active | paused
}
```

## Push notifications

APNs payload the client understands:

```json
{
  "aps": {"alert": {"title": "Pick-up time proposed", "body": "…"}, "sound": "default"},
  "type": "order.acknowledged",
  "order_id": "uuid"
}
```

Any push with an `order_id` refreshes the order lists; tapping one opens the
Orders tab. Events worth sending:

| `type` | Sent to | When |
| --- | --- | --- |
| `order.created` | business | Player submits a request |
| `order.acknowledged` | player | Stringer proposes a pick-up time |
| `order.declined` | player | Stringer declines |
| `order.confirmed` | business | Player accepts and pays |
| `order.in_progress` | player | Stringer starts |
| `order.complete` | player | Ready for pick up |
| `order.cancelled` | both | Either side cancels |
