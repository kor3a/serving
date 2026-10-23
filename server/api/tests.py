"""End-to-end tests for the order lifecycle and the JSON contract.

The key-set assertions are deliberate: they are the guard against the server
drifting from the `CodingKeys` in Serving/Core/Models. If you add a field to a
Swift model, these tests should fail until the server sends it.

    python manage.py test
"""

import json
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from .models import (
    AccountType,
    Business,
    LocationKind,
    Order,
    OrderStatus,
    PaymentState,
    StringCategory,
    StringingService,
    StringProduct,
    User,
)

# Exactly the keys each Swift model declares.
USER_KEYS = {
    "id", "email", "account_type", "display_name", "owner_name", "phone",
    "phone_verified", "business_id", "avatar_url", "created_at",
}
AUTH_SESSION_KEYS = {"access_token", "refresh_token", "user", "email"}
BUSINESS_KEYS = {
    "id", "name", "owner_name", "phone", "address", "coordinate", "location_kind",
    "is_claimed", "about", "rating", "rating_count", "typical_turnaround_hours",
    "accepts_bring_your_own_string", "bring_your_own_string_fee",
    "drop_off_instructions", "services", "inventory", "open_hours",
}
ADDRESS_KEYS = {"line1", "line2", "city", "state", "postal_code"}
ORDER_KEYS = {
    "id", "order_number", "business_id", "business_name", "business_phone",
    "player_id", "player_name", "player_phone", "racquets", "service_id",
    "service_name", "drop_off_date", "drop_off_address", "drop_off_instructions",
    "proposed_pick_up_date", "confirmed_pick_up_date", "business_note", "pricing",
    "payment", "status", "created_at", "updated_at",
}
RACQUET_KEYS = {"id", "sport", "model", "string_selection", "main_tension",
                "cross_tension", "notes"}
PRICING_KEYS = {"strings_subtotal", "labor_subtotal", "bring_your_own_string_fee",
                "service_fee", "tax"}
PAYMENT_KEYS = {"method", "state", "payment_intent_id", "charged_at", "last4"}
EARNINGS_KEYS = {"pending_payout", "paid_out_this_month", "gross_this_week",
                 "completed_orders_this_month", "next_payout_date", "payout_status"}


class ServingFlowTests(APITestCase):
    """Drives the whole player ↔ business flow over HTTP."""

    def setUp(self):
        self.business = Business.objects.create(
            name="Baseline String Lab",
            owner_name="Jordan Kim",
            phone="(408) 555-0110",
            line1="845 E Duane Ave",
            city="Sunnyvale",
            state="CA",
            postal_code="94085",
            latitude=37.3760,
            longitude=-122.0210,
            location_kind=LocationKind.STOREFRONT,
            is_claimed=True,
            rating=Decimal("4.9"),
            rating_count=213,
            bring_your_own_string_fee=Decimal("22.00"),
            drop_off_instructions="Side entrance of Suite B.",
        )
        self.service = StringingService.objects.create(
            business=self.business, name="Standard Stringing", labor_price=Decimal("22.00")
        )
        self.product = StringProduct.objects.create(
            business=self.business,
            brand="Luxilon",
            name="ALU Power",
            category=StringCategory.POLYESTER,
            gauge="16L / 1.25mm",
            price=Decimal("24.00"),
            stock_count=5,
        )
        self.unclaimed = Business.objects.create(
            name="Courtside Racquet Sports",
            phone="(408) 555-0182",
            line1="1201 W El Camino Real",
            city="Mountain View",
            state="CA",
            postal_code="94040",
            latitude=37.3835,
            longitude=-122.0961,
            is_claimed=False,
        )

        self.player = User.objects.create_user(
            email="player@example.com",
            password="serving123",
            account_type=AccountType.PLAYER,
            display_name="Alex Rivera",
            phone="(408) 555-0134",
            phone_verified=True,
            setup_complete=True,
        )
        self.owner = User.objects.create_user(
            email="shop@example.com",
            password="serving123",
            account_type=AccountType.BUSINESS,
            display_name=self.business.name,
            owner_name="Jordan Kim",
            phone=self.business.phone,
            phone_verified=True,
            setup_complete=True,
        )
        self.owner.business = self.business
        self.owner.save()

    # ------------------------------------------------------------ helpers

    def authenticate(self, email, password="serving123"):
        response = self.client.post(
            "/v1/auth/login/", {"email": email, "password": password}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access_token']}")
        return response.data

    def as_player(self):
        return self.authenticate("player@example.com")

    def as_owner(self):
        return self.authenticate("shop@example.com")

    def make_order(self, *, byos=False):
        self.as_player()
        selection = (
            {"kind": "byos", "description": "Solinco Tour Bite 17"}
            if byos
            else {
                "kind": "storefront",
                "product_id": str(self.product.id),
                "product_name": self.product.name,
                "price": 999,  # ignored — the server prices from its own data
            }
        )
        payload = {
            "business_id": str(self.business.id),
            "service_id": str(self.service.id),
            "drop_off_date": (timezone.now() + timedelta(days=1)).isoformat(),
            "payment_method": "applePay",
            "note_for_stringer": "Logo stencil please.",
            "racquets": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "sport": "tennis",
                    "model": "Babolat Pure Aero 98",
                    "string_selection": selection,
                    "main_tension": 52,
                    "cross_tension": 50,
                    "notes": "",
                }
            ],
        }
        response = self.client.post("/v1/orders/", payload, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    # ------------------------------------------------------------ auth

    def test_signup_returns_null_user_until_setup(self):
        response = self.client.post(
            "/v1/auth/signup/", {"email": "new@example.com"}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(set(response.data), AUTH_SESSION_KEYS)
        # A null user is what sends the app to SetUpAccountView.
        self.assertIsNone(response.data["user"])
        self.assertEqual(response.data["email"], "new@example.com")

    def test_account_setup_requires_verified_phone(self):
        signup = self.client.post(
            "/v1/auth/signup/", {"email": "new@example.com"}, format="json"
        ).data
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {signup['access_token']}")

        unverified = self.client.post(
            "/v1/auth/account-setup/",
            {
                "account_type": "player",
                "email": "new@example.com",
                "password": "supersecret",
                "phone": "(408) 555-0199",
                "phone_verified": True,  # client claim, not trusted
                "player_name": "Sam Chen",
            },
            format="json",
        )
        self.assertEqual(unverified.status_code, 400)
        self.assertIn("phone", unverified.data)

    @override_settings(DEBUG=True)
    def test_full_signup_flow(self):
        signup = self.client.post(
            "/v1/auth/signup/", {"email": "new@example.com"}, format="json"
        ).data
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {signup['access_token']}")

        code_response = self.client.post(
            "/v1/auth/phone/request-code/", {"phone": "(408) 555-0199"}, format="json"
        )
        self.assertEqual(code_response.status_code, 200)
        code = code_response.data["dev_code"]

        verify = self.client.post(
            "/v1/auth/phone/verify/",
            {"phone": "(408) 555-0199", "code": code},
            format="json",
        )
        self.assertTrue(verify.data["verified"])

        setup = self.client.post(
            "/v1/auth/account-setup/",
            {
                "account_type": "business",
                "email": "new@example.com",
                "password": "supersecret",
                "phone": "(408) 555-0199",
                "phone_verified": True,
                "business_name": "Net Cord Stringing",
                "owner_name": "Sam Chen",
                "address": {
                    "line1": "Ortega Park",
                    "line2": "",
                    "city": "Sunnyvale",
                    "state": "CA",
                    "postal_code": "94087",
                },
            },
            format="json",
        )
        self.assertEqual(setup.status_code, 200, setup.data)
        self.assertEqual(set(setup.data), AUTH_SESSION_KEYS)
        self.assertEqual(set(setup.data["user"]), USER_KEYS)
        self.assertEqual(setup.data["user"]["account_type"], "business")
        self.assertIsNotNone(setup.data["user"]["business_id"])
        # A new shop is bookable immediately.
        self.assertTrue(
            StringingService.objects.filter(business_id=setup.data["user"]["business_id"]).exists()
        )

    def test_wrong_password_is_401(self):
        response = self.client.post(
            "/v1/auth/login/",
            {"email": "player@example.com", "password": "wrong-password"},
            format="json",
        )
        self.assertEqual(response.status_code, 401)
        self.assertIn("detail", response.data)

    def test_player_user_payload_shape(self):
        session = self.as_player()
        self.assertEqual(set(session["user"]), USER_KEYS)
        # Optional Swift values must be null, never "".
        self.assertIsNone(session["user"]["owner_name"])
        self.assertIsNone(session["user"]["avatar_url"])
        self.assertIsNone(session["user"]["business_id"])

    # ------------------------------------------------------------ discovery

    def test_search_returns_claimed_and_unclaimed(self):
        response = self.client.get(
            "/v1/businesses/search/", {"lat": 37.3688, "lng": -122.0363, "radius_m": 40000}
        )
        self.assertEqual(response.status_code, 200)
        names = [row["name"] for row in response.data]
        self.assertIn("Baseline String Lab", names)
        self.assertIn("Courtside Racquet Sports", names)

        for row in response.data:
            self.assertEqual(set(row), BUSINESS_KEYS)
            self.assertEqual(set(row["address"]), ADDRESS_KEYS)
            self.assertEqual(set(row["coordinate"]), {"latitude", "longitude"})
            # Non-optional arrays on the Swift side.
            self.assertIsInstance(row["services"], list)
            self.assertIsInstance(row["inventory"], list)
            self.assertIsInstance(row["open_hours"], list)

        # Closest first.
        self.assertEqual(response.data[0]["name"], "Baseline String Lab")

    def test_search_orders_by_distance_and_respects_radius(self):
        response = self.client.get(
            "/v1/businesses/search/", {"lat": 37.3760, "lng": -122.0210, "radius_m": 1000}
        )
        self.assertEqual([row["name"] for row in response.data], ["Baseline String Lab"])

    def test_unclaimed_business_cannot_take_orders(self):
        self.as_player()
        response = self.client.post(
            "/v1/orders/",
            {
                "business_id": str(self.unclaimed.id),
                "drop_off_date": (timezone.now() + timedelta(days=1)).isoformat(),
                "payment_method": "applePay",
                "racquets": [
                    {
                        "sport": "tennis",
                        "model": "",
                        "string_selection": {"kind": "byos", "description": "Own set"},
                        "main_tension": 52,
                        "cross_tension": 52,
                        "notes": "",
                    }
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    # ------------------------------------------------------------ orders

    def test_order_payload_shape(self):
        order = self.make_order()
        self.assertEqual(set(order), ORDER_KEYS)
        self.assertEqual(set(order["pricing"]), PRICING_KEYS)
        self.assertEqual(set(order["payment"]), PAYMENT_KEYS)
        self.assertEqual(set(order["drop_off_address"]), ADDRESS_KEYS)
        self.assertEqual(set(order["racquets"][0]), RACQUET_KEYS)
        self.assertEqual(
            set(order["racquets"][0]["string_selection"]),
            {"kind", "product_id", "product_name", "price"},
        )

    def test_money_is_a_number_not_a_string(self):
        """Swift decodes Decimal from a JSON number; "24.00" would throw.

        Checks the rendered bytes, not `response.data` — DRF only converts
        Decimal at render time, so `.data` would hide a string encoding.
        """
        order = self.make_order()
        self.as_player()
        response = self.client.get(f"/v1/orders/{order['id']}/")
        rendered = json.loads(response.content)

        for key, value in rendered["pricing"].items():
            self.assertNotIsInstance(value, str, f"pricing.{key} was serialized as a string")
            self.assertIsInstance(value, (int, float), f"pricing.{key}")

        for key in ("main_tension", "cross_tension"):
            self.assertIsInstance(rendered["racquets"][0][key], (int, float), key)

        price = rendered["racquets"][0]["string_selection"]["price"]
        self.assertIsInstance(price, (int, float))

        # And on the storefront, where prices originate.
        business = json.loads(
            self.client.get(f"/v1/businesses/{self.business.id}/").content
        )
        self.assertIsInstance(business["inventory"][0]["price"], (int, float))
        self.assertIsInstance(business["services"][0]["labor_price"], (int, float))
        self.assertIsInstance(business["bring_your_own_string_fee"], (int, float))
        self.assertIsInstance(business["rating"], (int, float))

    def test_timestamps_have_no_fractional_seconds(self):
        order = self.make_order()
        self.assertRegex(order["created_at"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

    def test_server_prices_the_order_itself(self):
        """The client's price field is ignored — inventory is the source."""
        order = self.make_order()
        pricing = order["pricing"]
        self.assertEqual(Decimal(str(pricing["strings_subtotal"])), Decimal("24.00"))
        self.assertEqual(Decimal(str(pricing["labor_subtotal"])), Decimal("22.00"))
        self.assertEqual(Decimal(str(pricing["bring_your_own_string_fee"])), Decimal("0.00"))
        # 6% of 46.00
        self.assertEqual(Decimal(str(pricing["service_fee"])), Decimal("2.76"))

    def test_byos_charges_the_install_fee_and_no_string(self):
        order = self.make_order(byos=True)
        pricing = order["pricing"]
        self.assertEqual(Decimal(str(pricing["strings_subtotal"])), Decimal("0.00"))
        self.assertEqual(Decimal(str(pricing["bring_your_own_string_fee"])), Decimal("22.00"))
        self.assertEqual(order["racquets"][0]["string_selection"]["kind"], "byos")

    def test_new_order_is_unpaid_and_awaiting_the_business(self):
        order = self.make_order()
        self.assertEqual(order["status"], "awaitingBusiness")
        self.assertEqual(order["payment"]["state"], "requiresPaymentMethod")
        self.assertIsNone(order["payment"]["charged_at"])
        self.assertIsNone(order["proposed_pick_up_date"])
        self.assertIsNone(order["confirmed_pick_up_date"])

    def test_full_order_lifecycle(self):
        order = self.make_order()
        order_id = order["id"]
        pick_up = timezone.now() + timedelta(days=2)

        # 1. Stringer acknowledges and proposes a pick-up time. Still no charge.
        self.as_owner()
        acknowledged = self.client.post(
            f"/v1/orders/{order_id}/acknowledge/",
            {"proposed_pick_up_date": pick_up.isoformat(), "note": "Ready the next evening."},
            format="json",
        )
        self.assertEqual(acknowledged.status_code, 200, acknowledged.data)
        self.assertEqual(acknowledged.data["status"], "awaitingPlayerApproval")
        self.assertIsNotNone(acknowledged.data["proposed_pick_up_date"])
        self.assertIsNone(acknowledged.data["confirmed_pick_up_date"])
        self.assertEqual(acknowledged.data["payment"]["state"], "requiresPaymentMethod")

        # 2. Player accepts — this is where payment is captured.
        self.as_player()
        accepted = self.client.post(
            f"/v1/orders/{order_id}/accept-pickup/", {"payment_method": "applePay"}, format="json"
        )
        self.assertEqual(accepted.status_code, 200, accepted.data)
        self.assertEqual(accepted.data["status"], "confirmed")
        self.assertEqual(accepted.data["payment"]["state"], "succeeded")
        self.assertIsNotNone(accepted.data["payment"]["charged_at"])
        self.assertIsNotNone(accepted.data["payment"]["payment_intent_id"])
        # The confirmed time is the one that was proposed.
        self.assertEqual(
            accepted.data["confirmed_pick_up_date"], accepted.data["proposed_pick_up_date"]
        )

        # Stock came down only after payment.
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_count, 4)

        # 3. Stringer works through it.
        self.as_owner()
        in_progress = self.client.patch(
            f"/v1/orders/{order_id}/status/", {"status": "inProgress"}, format="json"
        )
        self.assertEqual(in_progress.data["status"], "inProgress")

        complete = self.client.patch(
            f"/v1/orders/{order_id}/status/", {"status": "complete"}, format="json"
        )
        self.assertEqual(complete.data["status"], "complete")

        # 4. The racquet is handed back at the confirmed time and place.
        picked_up = self.client.patch(
            f"/v1/orders/{order_id}/status/", {"status": "pickedUp"}, format="json"
        )
        self.assertEqual(picked_up.status_code, 200, picked_up.data)
        self.assertEqual(picked_up.data["status"], "pickedUp")

    def make_ready_order(self):
        """An order that has been paid for, strung and marked ready for pick up."""

        order = self.make_order()
        self.as_owner()
        self.client.post(
            f"/v1/orders/{order['id']}/acknowledge/",
            {"proposed_pick_up_date": (timezone.now() + timedelta(days=2)).isoformat()},
            format="json",
        )
        self.as_player()
        self.client.post(
            f"/v1/orders/{order['id']}/accept-pickup/", {"payment_method": "card"}, format="json"
        )
        self.as_owner()
        for step in ("inProgress", "complete"):
            self.client.patch(f"/v1/orders/{order['id']}/status/", {"status": step}, format="json")
        return order

    def test_pick_up_confirmation_goes_to_both_sides(self):
        with mock.patch("api.push.notify_order") as notify:
            self.make_ready_order()

        ready = [c for c in notify.call_args_list if c.kwargs["event"] == "order.complete"]
        self.assertEqual({c.args[0] for c in ready}, {self.player, self.owner})
        # Both carry the same location and agreed time.
        bodies = [c.kwargs["body"] for c in ready]
        self.assertTrue(all(self.business.line1 in body for body in bodies), bodies)

    def test_only_the_stringer_can_mark_a_racquet_picked_up(self):
        order = self.make_ready_order()
        self.as_player()
        response = self.client.patch(
            f"/v1/orders/{order['id']}/status/", {"status": "pickedUp"}, format="json"
        )
        self.assertEqual(response.status_code, 403)

    def test_cannot_pick_up_before_the_racquet_is_ready(self):
        order = self.make_order()
        self.as_owner()
        response = self.client.patch(
            f"/v1/orders/{order['id']}/status/", {"status": "pickedUp"}, format="json"
        )
        self.assertEqual(response.status_code, 409)

    def test_ready_order_cannot_be_cancelled(self):
        order = self.make_ready_order()
        self.as_player()
        response = self.client.post(f"/v1/orders/{order['id']}/cancel/", {}, format="json")
        self.assertEqual(response.status_code, 409, response.data)

    def test_cannot_accept_before_a_time_is_proposed(self):
        order = self.make_order()
        self.as_player()
        response = self.client.post(
            f"/v1/orders/{order['id']}/accept-pickup/", {"payment_method": "card"}, format="json"
        )
        self.assertEqual(response.status_code, 409, response.data)

    def test_only_the_stringer_can_acknowledge(self):
        order = self.make_order()
        self.as_player()  # player trying to acknowledge their own order
        response = self.client.post(
            f"/v1/orders/{order['id']}/acknowledge/",
            {"proposed_pick_up_date": (timezone.now() + timedelta(days=2)).isoformat()},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_status_cannot_skip_ahead(self):
        order = self.make_order()
        self.as_owner()
        response = self.client.patch(
            f"/v1/orders/{order['id']}/status/", {"status": "complete"}, format="json"
        )
        self.assertEqual(response.status_code, 409)

    def test_declining_leaves_the_player_uncharged(self):
        order = self.make_order()
        self.as_owner()
        response = self.client.post(
            f"/v1/orders/{order['id']}/decline/", {"reason": "Machine is down."}, format="json"
        )
        self.assertEqual(response.data["status"], "declined")
        self.assertEqual(response.data["payment"]["state"], "requiresPaymentMethod")
        self.assertEqual(response.data["business_note"], "Machine is down.")

    def test_cancelling_a_paid_order_refunds_it(self):
        order = self.make_order()
        pick_up = timezone.now() + timedelta(days=2)

        self.as_owner()
        self.client.post(
            f"/v1/orders/{order['id']}/acknowledge/",
            {"proposed_pick_up_date": pick_up.isoformat()},
            format="json",
        )
        self.as_player()
        self.client.post(
            f"/v1/orders/{order['id']}/accept-pickup/", {"payment_method": "card"}, format="json"
        )

        cancelled = self.client.post(f"/v1/orders/{order['id']}/cancel/", {}, format="json")
        self.assertEqual(cancelled.data["status"], "cancelled")
        self.assertEqual(cancelled.data["payment"]["state"], "refunded")

    def test_orders_are_scoped_to_the_caller(self):
        self.make_order()

        self.as_player()
        player_orders = self.client.get("/v1/orders/", {"role": "player"})
        self.assertEqual(len(player_orders.data), 1)

        self.as_owner()
        business_orders = self.client.get("/v1/orders/", {"role": "business"})
        self.assertEqual(len(business_orders.data), 1)

        # A third party sees nothing and cannot fetch the order directly.
        stranger = User.objects.create_user(
            email="stranger@example.com", password="serving123", setup_complete=True
        )
        self.authenticate("stranger@example.com")
        self.assertEqual(len(self.client.get("/v1/orders/").data), 0)
        order_id = Order.objects.first().id
        self.assertEqual(self.client.get(f"/v1/orders/{order_id}/").status_code, 404)

    def test_out_of_stock_string_is_rejected(self):
        self.product.stock_count = 0
        self.product.save()
        self.as_player()
        response = self.client.post(
            "/v1/orders/",
            {
                "business_id": str(self.business.id),
                "drop_off_date": (timezone.now() + timedelta(days=1)).isoformat(),
                "payment_method": "applePay",
                "racquets": [
                    {
                        "sport": "tennis",
                        "model": "",
                        "string_selection": {
                            "kind": "storefront",
                            "product_id": str(self.product.id),
                            "product_name": "Luxilon ALU Power",
                            "price": 24,
                        },
                        "main_tension": 52,
                        "cross_tension": 52,
                        "notes": "",
                    }
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    # ------------------------------------------------------------ storefront

    def test_storefront_management_round_trip(self):
        self.as_owner()

        product_id = "22222222-2222-2222-2222-222222222222"
        created = self.client.put(
            f"/v1/businesses/{self.business.id}/products/",
            {
                "id": product_id,
                "brand": "Solinco",
                "name": "Hyper-G",
                "category": "polyester",
                "sport": "tennis",
                "gauge": "17 / 1.20mm",
                "price": "20.00",
                "stock_count": 11,
                "details": "Big spin.",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(created.status_code, 200, created.data)

        # Same id again updates rather than duplicating.
        updated = self.client.put(
            f"/v1/businesses/{self.business.id}/products/",
            {
                "id": product_id,
                "brand": "Solinco",
                "name": "Hyper-G Soft",
                "category": "polyester",
                "sport": "tennis",
                "gauge": "17 / 1.20mm",
                "price": "21.50",
                "stock_count": 8,
                "details": "Softer version.",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(updated.data["name"], "Hyper-G Soft")
        self.assertEqual(StringProduct.objects.filter(id=product_id).count(), 1)

        deleted = self.client.delete(
            f"/v1/businesses/{self.business.id}/products/{product_id}/"
        )
        self.assertEqual(deleted.status_code, 204)
        self.assertFalse(StringProduct.objects.filter(id=product_id).exists())

    def test_cannot_edit_another_shops_storefront(self):
        self.as_player()
        response = self.client.put(
            f"/v1/businesses/{self.business.id}/products/",
            {"brand": "X", "name": "Y", "category": "polyester", "price": "1.00"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_profile_patch_updates_drop_off_address(self):
        self.as_owner()
        response = self.client.patch(
            f"/v1/businesses/{self.business.id}/",
            {
                "about": "Now open Sundays.",
                "location_kind": "publicMeetingSpot",
                "address": {
                    "line1": "Las Palmas Park",
                    "line2": "",
                    "city": "Sunnyvale",
                    "state": "CA",
                    "postal_code": "94086",
                },
                "coordinate": {"latitude": 37.3542, "longitude": -122.0198},
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["address"]["line1"], "Las Palmas Park")
        self.assertEqual(response.data["location_kind"], "publicMeetingSpot")
        self.assertAlmostEqual(response.data["coordinate"]["latitude"], 37.3542)

    def test_earnings_shape_and_totals(self):
        order = self.make_order()
        pick_up = timezone.now() + timedelta(days=2)

        self.as_owner()
        self.client.post(
            f"/v1/orders/{order['id']}/acknowledge/",
            {"proposed_pick_up_date": pick_up.isoformat()},
            format="json",
        )
        self.as_player()
        self.client.post(
            f"/v1/orders/{order['id']}/accept-pickup/", {"payment_method": "applePay"}, format="json"
        )

        self.as_owner()
        response = self.client.get(f"/v1/businesses/{self.business.id}/earnings/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(set(response.data), EARNINGS_KEYS)
        # Payout excludes the platform fee: 24.00 string + 22.00 labor.
        self.assertEqual(Decimal(str(response.data["pending_payout"])), Decimal("46.00"))

    def test_device_token_registration(self):
        self.as_player()
        response = self.client.post(
            "/v1/notifications/device-tokens/",
            {"token": "abc123", "platform": "ios"},
            format="json",
        )
        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.player.device_tokens.count(), 1)


class PhoneVerificationTests(APITestCase):
    def test_wrong_code_is_rejected(self):
        self.client.post("/v1/auth/phone/request-code/", {"phone": "4085550100"}, format="json")
        response = self.client.post(
            "/v1/auth/phone/verify/", {"phone": "4085550100", "code": "000000"}, format="json"
        )
        self.assertFalse(response.data["verified"])

    @override_settings(DEBUG=True)
    def test_phone_formatting_does_not_matter(self):
        code = self.client.post(
            "/v1/auth/phone/request-code/", {"phone": "(408) 555-0100"}, format="json"
        ).data["dev_code"]
        response = self.client.post(
            "/v1/auth/phone/verify/", {"phone": "4085550100", "code": code}, format="json"
        )
        self.assertTrue(response.data["verified"])
