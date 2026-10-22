"""Compare the server's JSON keys against the iOS app's CodingKeys.

    python manage.py check_contract

Parses the `CodingKeys` enums out of Serving/Core/Models/*.swift, renders each
serializer with throwaway data, and diffs the key sets. This is the guard that
the two halves of the app still agree — a missing or renamed key is a decode
failure on the device that no Python test would otherwise catch.

Everything it writes is rolled back.
"""

import re
from datetime import timedelta
from decimal import Decimal
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from api.models import (
    AccountType,
    Business,
    LocationKind,
    Order,
    OrderRacquet,
    StringCategory,
    StringingService,
    StringKind,
    StringProduct,
    User,
)
from api.serializers import (
    BusinessSerializer,
    EarningsSerializer,
    OrderSerializer,
    UserSerializer,
)

SWIFT_MODEL_DIR = Path(__file__).resolve().parents[4] / "Serving" / "Core" / "Models"

CASE_RE = re.compile(r"^\s*case\s+(\w+)(?:\s*=\s*\"([^\"]+)\")?\s*$", re.MULTILINE)


class Command(BaseCommand):
    help = "Diff the API's JSON keys against the iOS app's CodingKeys."

    def handle(self, *args, **options):
        if not SWIFT_MODEL_DIR.exists():
            self.stdout.write(
                self.style.WARNING(f"No Swift models at {SWIFT_MODEL_DIR} — skipping.")
            )
            return

        swift_keys = self.parse_swift_coding_keys()
        actual = self.render_payloads()

        failures = []
        checked = 0

        # StringSelection is a tagged union: each variant carries a subset of
        # the declared keys, so it is checked for containment, not equality.
        selection_keys = swift_keys.get("StringSelection", set())
        for variant, variant_keys in actual.pop("StringSelection", {}).items():
            checked += 1
            unknown = variant_keys - selection_keys
            if unknown:
                failures.append(f"StringSelection.{variant}: server sends unknown {sorted(unknown)}")
            else:
                self.stdout.write(f"  ✓ StringSelection.{variant} ({len(variant_keys)} keys)")

        for swift_type, json_keys in actual.items():
            expected = swift_keys.get(swift_type)
            if expected is None:
                failures.append(f"{swift_type}: no CodingKeys found in the Swift models")
                continue

            checked += 1
            missing = expected - json_keys
            extra = json_keys - expected
            if missing or extra:
                detail = []
                if missing:
                    detail.append(f"server is missing {sorted(missing)}")
                if extra:
                    detail.append(f"server sends unknown {sorted(extra)}")
                failures.append(f"{swift_type}: " + "; ".join(detail))
            else:
                self.stdout.write(f"  ✓ {swift_type} ({len(json_keys)} keys)")

        if failures:
            self.stdout.write("")
            for failure in failures:
                self.stdout.write(self.style.ERROR(f"  ✗ {failure}"))
            raise CommandError(f"{len(failures)} payload(s) drifted from the iOS models.")

        self.stdout.write(
            self.style.SUCCESS(f"\n{checked} payloads match the iOS CodingKeys.")
        )

    # ------------------------------------------------------------ Swift side

    def parse_swift_coding_keys(self) -> dict[str, set[str]]:
        """Maps Swift type name -> the wire keys its CodingKeys declares."""
        keys: dict[str, set[str]] = {}

        for path in sorted(SWIFT_MODEL_DIR.glob("*.swift")):
            source = path.read_text()
            # Walk declarations, tracking the innermost type that owns each
            # CodingKeys enum.
            for match in re.finditer(
                r"(?:struct|extension)\s+(\w+)[^{]*\{", source
            ):
                type_name = match.group(1)
                body = self._balanced_body(source, match.end() - 1)
                coding_keys = re.search(
                    r"enum\s+CodingKeys\s*:\s*String\s*,\s*CodingKey\s*\{", body
                )
                if coding_keys:
                    enum_body = self._balanced_body(body, coding_keys.end() - 1)
                    declared = {raw or name for name, raw in CASE_RE.findall(enum_body)}
                else:
                    # No CodingKeys enum means Swift synthesizes them from the
                    # stored property names, which are then the wire keys.
                    declared = self._stored_properties(body)
                    if not declared:
                        continue
                keys.setdefault(type_name, set()).update(declared)

        return keys

    @staticmethod
    def _stored_properties(body: str) -> set[str]:
        """Stored `var`/`let` declarations — skips computed properties."""
        found = set()
        for line in body.splitlines():
            stripped = line.strip()
            if stripped.startswith(("static", "private", "func", "//")):
                continue
            match = re.match(r"^(?:var|let)\s+(\w+)\s*:\s*[^{=]+$", stripped)
            if match:
                found.add(match.group(1))
        return found

    @staticmethod
    def _balanced_body(source: str, open_brace_index: int) -> str:
        depth = 0
        for index in range(open_brace_index, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    return source[open_brace_index + 1 : index]
        return ""

    # ------------------------------------------------------------ server side

    def render_payloads(self) -> dict[str, set[str]]:
        """Renders one of each payload inside a rolled-back transaction."""
        payloads: dict[str, set[str]] = {}

        try:
            with transaction.atomic():
                business = Business.objects.create(
                    name="Contract Check Stringing",
                    owner_name="Sam Chen",
                    phone="(408) 555-0000",
                    line1="1 Test St",
                    city="Sunnyvale",
                    state="CA",
                    postal_code="94085",
                    latitude=37.37,
                    longitude=-122.02,
                    location_kind=LocationKind.STOREFRONT,
                    is_claimed=True,
                    rating=Decimal("4.5"),
                    bring_your_own_string_fee=Decimal("20.00"),
                )
                service = StringingService.objects.create(
                    business=business, name="Standard", labor_price=Decimal("22.00")
                )
                product = StringProduct.objects.create(
                    business=business,
                    brand="Luxilon",
                    name="ALU Power",
                    category=StringCategory.POLYESTER,
                    gauge="16L",
                    price=Decimal("24.00"),
                    stock_count=3,
                )
                from api.models import OpenHours

                OpenHours.objects.create(business=business, weekday=1)

                player = User.objects.create_user(
                    email="contract-check@example.com",
                    password="serving123",
                    account_type=AccountType.PLAYER,
                    display_name="Alex Rivera",
                    phone="(408) 555-0134",
                    setup_complete=True,
                )

                order = Order.objects.create(
                    order_number="TN-CONTRACT",
                    business=business,
                    player=player,
                    service=service,
                    service_name=service.name,
                    business_name=business.name,
                    business_phone=business.phone,
                    player_name=player.display_name,
                    player_phone=player.phone,
                    drop_off_date=timezone.now() + timedelta(days=1),
                    proposed_pick_up_date=timezone.now() + timedelta(days=2),
                    confirmed_pick_up_date=timezone.now() + timedelta(days=2),
                    business_note="Note",
                    strings_subtotal=Decimal("24.00"),
                    labor_subtotal=Decimal("22.00"),
                    service_fee=Decimal("1.99"),
                    stringer_commission=Decimal("3.68"),
                    tax=Decimal("2.19"),
                )
                OrderRacquet.objects.create(
                    order=order,
                    model="Pure Aero",
                    main_tension=Decimal("52.0"),
                    cross_tension=Decimal("50.0"),
                    string_kind=StringKind.STOREFRONT,
                    product=product,
                    product_name="Luxilon ALU Power",
                    string_price=Decimal("24.00"),
                )
                OrderRacquet.objects.create(
                    order=order,
                    model="EZONE 100",
                    main_tension=Decimal("48.0"),
                    cross_tension=Decimal("48.0"),
                    string_kind=StringKind.BYOS,
                    byos_description="Solinco Tour Bite 17",
                )

                business.refresh_from_db()
                order.refresh_from_db()

                user_json = UserSerializer(player).data
                business_json = BusinessSerializer(business).data
                order_json = OrderSerializer(order).data
                earnings_json = EarningsSerializer(
                    {
                        "pending_payout": Decimal("0.00"),
                        "paid_out_this_month": Decimal("0.00"),
                        "gross_this_week": Decimal("0.00"),
                        "completed_orders_this_month": 0,
                        "next_payout_date": None,
                        "payout_status": "active",
                    }
                ).data

                payloads = {
                    "AppUser": set(user_json),
                    "StringerBusiness": set(business_json),
                    "PostalAddress": set(business_json["address"]),
                    "Coordinate": set(business_json["coordinate"]),
                    "StringingService": set(business_json["services"][0]),
                    "StringProduct": set(business_json["inventory"][0]),
                    "OpenHours": set(business_json["open_hours"][0]),
                    "Order": set(order_json),
                    "RacquetItem": set(order_json["racquets"][0]),
                    "PriceBreakdown": set(order_json["pricing"]),
                    "PaymentRecord": set(order_json["payment"]),
                    "EarningsSnapshot": set(earnings_json),
                    "StringSelection": {
                        variant["string_selection"]["kind"]: set(variant["string_selection"])
                        for variant in order_json["racquets"]
                    },
                }

                # AuthSession is assembled by the view, not a serializer.
                from api.views import auth_session

                payloads["AuthSession"] = set(auth_session(player))

                raise _Rollback
        except _Rollback:
            pass

        return payloads


class _Rollback(Exception):
    """Sentinel that unwinds the atomic block once payloads are captured."""
