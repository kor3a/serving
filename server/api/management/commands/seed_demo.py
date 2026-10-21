"""Seed the database with the same demo data the iOS mock backend uses.

    python manage.py seed_demo

Creates two sign-in-able accounts and a handful of Sunnyvale-area shops,
including two unclaimed ones so the map shows both kinds of pin.

    player@serving.app / serving123
    shop@serving.app   / serving123
"""

from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.utils import timezone

from api.models import (
    AccountType,
    Business,
    LocationKind,
    OpenHours,
    PayoutStatus,
    RacquetSport,
    StringCategory,
    StringingService,
    StringProduct,
    User,
)

DEMO_PASSWORD = "serving123"


class Command(BaseCommand):
    help = "Create demo accounts, storefronts and inventory."

    def add_arguments(self, parser):
        parser.add_argument(
            "--reset",
            action="store_true",
            help="Delete existing demo rows before seeding.",
        )

    def handle(self, *args, **options):
        if options["reset"]:
            Business.objects.filter(name__in=DEMO_BUSINESS_NAMES).delete()
            User.objects.filter(email__in=["player@serving.app", "shop@serving.app"]).delete()
            self.stdout.write("Cleared previous demo data.")

        baseline = self._baseline_string_lab()
        self._cross_and_main()
        self._smash_badminton()
        self._unclaimed_shops()

        player, created = User.objects.get_or_create(
            email="player@serving.app",
            defaults={
                "account_type": AccountType.PLAYER,
                "display_name": "Alex Rivera",
                "phone": "(408) 555-0134",
                "phone_verified": True,
                "setup_complete": True,
            },
        )
        player.set_password(DEMO_PASSWORD)
        player.save()

        owner, _ = User.objects.get_or_create(
            email="shop@serving.app",
            defaults={
                "account_type": AccountType.BUSINESS,
                "display_name": baseline.name,
                "owner_name": baseline.owner_name,
                "phone": baseline.phone,
                "phone_verified": True,
                "setup_complete": True,
            },
        )
        owner.business = baseline
        owner.account_type = AccountType.BUSINESS
        owner.setup_complete = True
        owner.set_password(DEMO_PASSWORD)
        owner.save()

        self.stdout.write(self.style.SUCCESS("Demo data ready."))
        self.stdout.write(f"  player@serving.app / {DEMO_PASSWORD}")
        self.stdout.write(f"  shop@serving.app   / {DEMO_PASSWORD}  (manages {baseline.name})")

    # ------------------------------------------------------------ shops

    def _hours(self, business, opens=600, closes=1140, closed_days=(1,)):
        for weekday in range(1, 8):
            OpenHours.objects.update_or_create(
                business=business,
                weekday=weekday,
                defaults={
                    "opens_at_minutes": opens,
                    "closes_at_minutes": closes,
                    "is_closed": weekday in closed_days,
                },
            )

    def _baseline_string_lab(self) -> Business:
        business, _ = Business.objects.update_or_create(
            name="Baseline String Lab",
            defaults={
                "owner_name": "Jordan Kim",
                "phone": "(408) 555-0110",
                "line1": "845 E Duane Ave",
                "line2": "Suite B",
                "city": "Sunnyvale",
                "state": "CA",
                "postal_code": "94085",
                "latitude": 37.3760,
                "longitude": -122.0210,
                "location_kind": LocationKind.STOREFRONT,
                "is_claimed": True,
                "about": "USRSA certified stringer. Wilson Baiardo machine, two-piece jobs on "
                         "request. Same-day service if dropped off before noon.",
                "rating": Decimal("4.9"),
                "rating_count": 213,
                "typical_turnaround_hours": 24,
                "accepts_bring_your_own_string": True,
                "bring_your_own_string_fee": Decimal("22.00"),
                "drop_off_instructions": "Ring the bell at the side entrance of Suite B. "
                                         "Racquet bin is inside the door.",
                "payout_status": PayoutStatus.ACTIVE,
            },
        )
        self._hours(business)

        services = [
            ("Standard Stringing", "One-piece install, logo stencil on request.", "22.00", 24),
            ("Rush (Same Day)", "Dropped off before noon, ready by 6 PM.", "35.00", 8),
            ("Hybrid Setup", "Two-piece, different string in mains and crosses.", "28.00", 24),
        ]
        for name, details, price, hours in services:
            StringingService.objects.update_or_create(
                business=business,
                name=name,
                defaults={
                    "details": details,
                    "labor_price": Decimal(price),
                    "turnaround_hours": hours,
                },
            )

        products = [
            ("Luxilon", "ALU Power", StringCategory.POLYESTER, "16L / 1.25mm", "24.00", 14,
             "The control benchmark. Crisp, low powered, holds tension well."),
            ("Babolat", "RPM Blast", StringCategory.POLYESTER, "17 / 1.25mm", "21.00", 9,
             "Octagonal shape for extra bite and spin."),
            ("Wilson", "NXT Comfort", StringCategory.MULTIFILAMENT, "16 / 1.30mm", "19.00", 22,
             "Soft multifilament, easy on the arm."),
            ("Wilson", "Natural Gut 16", StringCategory.NATURAL_GUT, "16 / 1.30mm", "48.00", 4,
             "Premium feel and tension maintenance."),
            ("Prince", "Synthetic Gut Duraflex", StringCategory.SYNTHETIC_GUT, "16 / 1.30mm",
             "12.00", 30, "Reliable all-round string at a friendly price."),
        ]
        for brand, name, category, gauge, price, stock, details in products:
            StringProduct.objects.update_or_create(
                business=business,
                brand=brand,
                name=name,
                defaults={
                    "category": category,
                    "gauge": gauge,
                    "price": Decimal(price),
                    "stock_count": stock,
                    "details": details,
                },
            )
        return business

    def _cross_and_main(self) -> Business:
        business, _ = Business.objects.update_or_create(
            name="Cross & Main Stringing",
            defaults={
                "owner_name": "Priya Nair",
                "phone": "(408) 555-0166",
                "line1": "Las Palmas Park — Parking Lot A",
                "city": "Sunnyvale",
                "state": "CA",
                "postal_code": "94086",
                "latitude": 37.3542,
                "longitude": -122.0198,
                "location_kind": LocationKind.PUBLIC_MEETING_SPOT,
                "is_claimed": True,
                "about": "Home-based stringer, 10 years on tour vans. Meet-ups at Las Palmas "
                         "Park courts most evenings.",
                "rating": Decimal("4.8"),
                "rating_count": 87,
                "typical_turnaround_hours": 48,
                "bring_your_own_string_fee": Decimal("18.00"),
                "drop_off_instructions": "Meet at the bench by court 3. Text when you're "
                                         "5 minutes out.",
                "payout_status": PayoutStatus.ACTIVE,
            },
        )
        self._hours(business, opens=1020, closes=1260, closed_days=(1, 7))

        StringingService.objects.update_or_create(
            business=business, name="Standard Stringing",
            defaults={"details": "One-piece install.", "labor_price": Decimal("18.00"),
                      "turnaround_hours": 48},
        )
        StringingService.objects.update_or_create(
            business=business, name="Badminton Restring",
            defaults={"details": "Up to 30 lbs, four-knot method.",
                      "labor_price": Decimal("16.00"), "turnaround_hours": 48},
        )
        StringProduct.objects.update_or_create(
            business=business, brand="Solinco", name="Hyper-G",
            defaults={"category": StringCategory.POLYESTER, "gauge": "17 / 1.20mm",
                      "price": Decimal("20.00"), "stock_count": 11,
                      "details": "Square profile, big spin, popular with juniors."},
        )
        StringProduct.objects.update_or_create(
            business=business, brand="Yonex", name="BG-65",
            defaults={"category": StringCategory.BADMINTON, "sport": RacquetSport.BADMINTON,
                      "gauge": "0.70mm", "price": Decimal("14.00"), "stock_count": 25,
                      "details": "Durable badminton string, the club standard."},
        )
        return business

    def _smash_badminton(self) -> Business:
        business, _ = Business.objects.update_or_create(
            name="Smash Badminton Works",
            defaults={
                "owner_name": "Wei Chen",
                "phone": "(408) 555-0193",
                "line1": "2190 S Bascom Ave",
                "city": "Campbell",
                "state": "CA",
                "postal_code": "95008",
                "latitude": 37.2872,
                "longitude": -121.9320,
                "location_kind": LocationKind.STOREFRONT,
                "is_claimed": True,
                "about": "Badminton specialists. Constant-pull machine, tensions up to 35 lbs.",
                "rating": Decimal("4.7"),
                "rating_count": 141,
                "typical_turnaround_hours": 36,
                "bring_your_own_string_fee": Decimal("15.00"),
                "drop_off_instructions": "Front counter, ask for the stringing desk.",
                "payout_status": PayoutStatus.PENDING_VERIFICATION,
            },
        )
        self._hours(business)
        StringingService.objects.update_or_create(
            business=business, name="Badminton Restring",
            defaults={"details": "Four-knot, pre-stretch included.",
                      "labor_price": Decimal("15.00"), "turnaround_hours": 36},
        )
        StringProduct.objects.update_or_create(
            business=business, brand="Yonex", name="Aerobite",
            defaults={"category": StringCategory.BADMINTON, "sport": RacquetSport.BADMINTON,
                      "gauge": "0.67mm", "price": Decimal("22.00"), "stock_count": 18,
                      "details": "Hybrid feel, extra shuttle grip for spin."},
        )
        return business

    def _unclaimed_shops(self):
        """Shops that exist on the map but have no Serving account."""
        Business.objects.update_or_create(
            name="Courtside Racquet Sports",
            defaults={
                "phone": "(408) 555-0182",
                "line1": "1201 W El Camino Real",
                "city": "Mountain View",
                "state": "CA",
                "postal_code": "94040",
                "latitude": 37.3835,
                "longitude": -122.0961,
                "is_claimed": False,
            },
        )
        Business.objects.update_or_create(
            name="Peninsula Tennis Shop",
            defaults={
                "phone": "(650) 555-0117",
                "line1": "455 Ramona St",
                "city": "Palo Alto",
                "state": "CA",
                "postal_code": "94301",
                "latitude": 37.4443,
                "longitude": -122.1610,
                "is_claimed": False,
            },
        )


DEMO_BUSINESS_NAMES = [
    "Baseline String Lab",
    "Cross & Main Stringing",
    "Smash Badminton Works",
    "Courtside Racquet Sports",
    "Peninsula Tennis Shop",
]
