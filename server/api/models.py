"""Data model for Serving.

Field names and enum values line up with Serving/Core/Models in the iOS app —
the enum values are the exact camelCase strings the Swift client decodes, so
don't "tidy" them into snake_case.
"""

import uuid
from decimal import Decimal

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone


class AccountType(models.TextChoices):
    BUSINESS = "business", "Business"
    PLAYER = "player", "Player"


class LocationKind(models.TextChoices):
    STOREFRONT = "storefront", "Storefront"
    RESIDENTIAL = "residential", "Home-based"
    PUBLIC_MEETING_SPOT = "publicMeetingSpot", "Meeting spot"


class RacquetSport(models.TextChoices):
    TENNIS = "tennis", "Tennis"
    BADMINTON = "badminton", "Badminton"


class StringCategory(models.TextChoices):
    POLYESTER = "polyester", "Polyester"
    MULTIFILAMENT = "multifilament", "Multifilament"
    SYNTHETIC_GUT = "syntheticGut", "Synthetic Gut"
    NATURAL_GUT = "naturalGut", "Natural Gut"
    HYBRID = "hybrid", "Hybrid"
    BADMINTON = "badminton", "Badminton"


class OrderStatus(models.TextChoices):
    AWAITING_BUSINESS = "awaitingBusiness", "Awaiting stringer"
    AWAITING_PLAYER_APPROVAL = "awaitingPlayerApproval", "Pick-up time proposed"
    CONFIRMED = "confirmed", "Confirmed"
    IN_PROGRESS = "inProgress", "In progress"
    COMPLETE = "complete", "Complete"
    DECLINED = "declined", "Declined"
    CANCELLED = "cancelled", "Cancelled"


class PaymentMethod(models.TextChoices):
    APPLE_PAY = "applePay", "Apple Pay"
    CARD = "card", "Card"
    PAYPAL = "payPal", "PayPal"


class PaymentState(models.TextChoices):
    REQUIRES_PAYMENT_METHOD = "requiresPaymentMethod", "Not charged yet"
    REQUIRES_CONFIRMATION = "requiresConfirmation", "Awaiting confirmation"
    PROCESSING = "processing", "Processing"
    SUCCEEDED = "succeeded", "Paid"
    FAILED = "failed", "Failed"
    REFUNDED = "refunded", "Refunded"


class PayoutStatus(models.TextChoices):
    NOT_CONNECTED = "notConnected", "Not connected"
    PENDING_VERIFICATION = "pendingVerification", "Verifying"
    ACTIVE = "active", "Active"
    PAUSED = "paused", "Paused"


class StringKind(models.TextChoices):
    STOREFRONT = "storefront", "From storefront"
    BYOS = "byos", "Bring your own string"


# ---------------------------------------------------------------- users


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError("Users must have an email address.")
        user = self.model(email=self.normalize_email(email).lower(), **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("account_type", AccountType.PLAYER)
        extra.setdefault("display_name", email.split("@")[0])
        return self.create_user(email, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    """Email-as-username account, shared by players and stringers.

    `account_type` is only meaningful after account setup completes;
    `setup_complete` is what the app checks to decide whether to show
    SetUpAccountView.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    account_type = models.CharField(
        max_length=16, choices=AccountType.choices, default=AccountType.PLAYER
    )
    display_name = models.CharField(max_length=200, blank=True, default="")
    owner_name = models.CharField(max_length=200, blank=True, default="")
    phone = models.CharField(max_length=32, blank=True, default="")
    phone_verified = models.BooleanField(default=False)
    avatar_url = models.URLField(blank=True, default="")

    business = models.OneToOneField(
        "Business", null=True, blank=True, on_delete=models.SET_NULL, related_name="owner_account"
    )

    setup_complete = models.BooleanField(default=False)
    apple_subject = models.CharField(max_length=255, blank=True, default="", db_index=True)
    google_subject = models.CharField(max_length=255, blank=True, default="", db_index=True)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.email


class PhoneVerification(models.Model):
    """One issued SMS code. The code itself is never stored in the clear."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=32, db_index=True)
    code_hash = models.CharField(max_length=128)
    attempts = models.PositiveIntegerField(default=0)
    expires_at = models.DateTimeField()
    verified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    @property
    def is_expired(self):
        return timezone.now() > self.expires_at


class DeviceToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="device_tokens")
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=16, default="ios")
    created_at = models.DateTimeField(auto_now_add=True)


# ---------------------------------------------------------------- businesses


class Business(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    owner_name = models.CharField(max_length=200, blank=True, default="")
    phone = models.CharField(max_length=32, blank=True, default="")

    line1 = models.CharField(max_length=255, blank=True, default="")
    line2 = models.CharField(max_length=255, blank=True, default="")
    city = models.CharField(max_length=120, blank=True, default="")
    state = models.CharField(max_length=40, blank=True, default="")
    postal_code = models.CharField(max_length=20, blank=True, default="")

    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    location_kind = models.CharField(
        max_length=32, choices=LocationKind.choices, default=LocationKind.STOREFRONT
    )

    # False for shops imported from map data that never signed up. The app
    # shows those as name / address / phone with a call button.
    is_claimed = models.BooleanField(default=False, db_index=True)

    about = models.TextField(blank=True, default="")
    rating = models.DecimalField(max_digits=2, decimal_places=1, null=True, blank=True)
    rating_count = models.PositiveIntegerField(default=0)
    typical_turnaround_hours = models.PositiveIntegerField(default=48)
    accepts_bring_your_own_string = models.BooleanField(default=True)
    bring_your_own_string_fee = models.DecimalField(
        max_digits=10, decimal_places=2, default=Decimal("0.00")
    )
    drop_off_instructions = models.TextField(blank=True, default="")

    stripe_account_id = models.CharField(max_length=64, blank=True, default="")
    payout_status = models.CharField(
        max_length=32, choices=PayoutStatus.choices, default=PayoutStatus.NOT_CONNECTED
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]
        verbose_name_plural = "businesses"

    def __str__(self):
        return self.name


class OpenHours(models.Model):
    """Weekday follows Calendar.component(.weekday:) — 1 is Sunday."""

    business = models.ForeignKey(Business, on_delete=models.CASCADE, related_name="open_hours")
    weekday = models.PositiveSmallIntegerField()
    opens_at_minutes = models.PositiveIntegerField(default=600)
    closes_at_minutes = models.PositiveIntegerField(default=1140)
    is_closed = models.BooleanField(default=False)

    class Meta:
        ordering = ["weekday"]
        unique_together = [("business", "weekday")]
        verbose_name_plural = "open hours"


class StringingService(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    business = models.ForeignKey(Business, on_delete=models.CASCADE, related_name="services")
    name = models.CharField(max_length=120)
    details = models.TextField(blank=True, default="")
    labor_price = models.DecimalField(max_digits=10, decimal_places=2)
    turnaround_hours = models.PositiveIntegerField(default=48)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["labor_price"]

    def __str__(self):
        return f"{self.name} ({self.business.name})"


class StringProduct(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    business = models.ForeignKey(Business, on_delete=models.CASCADE, related_name="inventory")
    brand = models.CharField(max_length=120)
    name = models.CharField(max_length=120)
    category = models.CharField(max_length=32, choices=StringCategory.choices)
    sport = models.CharField(
        max_length=16, choices=RacquetSport.choices, default=RacquetSport.TENNIS
    )
    gauge = models.CharField(max_length=64, blank=True, default="")
    price = models.DecimalField(max_digits=10, decimal_places=2)
    stock_count = models.PositiveIntegerField(default=0)
    details = models.TextField(blank=True, default="")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["brand", "name"]

    def __str__(self):
        return f"{self.brand} {self.name}"


# ---------------------------------------------------------------- orders


class Order(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    order_number = models.CharField(max_length=24, unique=True)

    business = models.ForeignKey(Business, on_delete=models.PROTECT, related_name="orders")
    player = models.ForeignKey(User, on_delete=models.PROTECT, related_name="orders")
    service = models.ForeignKey(
        StringingService, null=True, blank=True, on_delete=models.SET_NULL, related_name="orders"
    )

    # Snapshotted so a past receipt never changes when a shop edits its
    # profile, pricing or address.
    service_name = models.CharField(max_length=120, default="Stringing")
    business_name = models.CharField(max_length=200)
    business_phone = models.CharField(max_length=32, blank=True, default="")
    player_name = models.CharField(max_length=200)
    player_phone = models.CharField(max_length=32, blank=True, default="")
    drop_off_line1 = models.CharField(max_length=255, blank=True, default="")
    drop_off_line2 = models.CharField(max_length=255, blank=True, default="")
    drop_off_city = models.CharField(max_length=120, blank=True, default="")
    drop_off_state = models.CharField(max_length=40, blank=True, default="")
    drop_off_postal_code = models.CharField(max_length=20, blank=True, default="")
    drop_off_instructions = models.TextField(blank=True, default="")

    drop_off_date = models.DateTimeField()
    proposed_pick_up_date = models.DateTimeField(null=True, blank=True)
    confirmed_pick_up_date = models.DateTimeField(null=True, blank=True)
    business_note = models.TextField(blank=True, default="")

    strings_subtotal = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    labor_subtotal = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    bring_your_own_string_fee = models.DecimalField(
        max_digits=10, decimal_places=2, default=Decimal("0.00")
    )
    service_fee = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    tax = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))

    payment_method = models.CharField(
        max_length=16, choices=PaymentMethod.choices, default=PaymentMethod.APPLE_PAY
    )
    payment_state = models.CharField(
        max_length=32,
        choices=PaymentState.choices,
        default=PaymentState.REQUIRES_PAYMENT_METHOD,
    )
    stripe_payment_intent = models.CharField(max_length=120, blank=True, default="")
    charged_at = models.DateTimeField(null=True, blank=True)
    card_last4 = models.CharField(max_length=4, blank=True, default="")

    status = models.CharField(
        max_length=32, choices=OrderStatus.choices, default=OrderStatus.AWAITING_BUSINESS
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["business", "status", "-created_at"]),
            models.Index(fields=["player", "-created_at"]),
        ]

    def __str__(self):
        return f"{self.order_number} · {self.business_name}"

    @property
    def total(self) -> Decimal:
        return (
            self.strings_subtotal
            + self.labor_subtotal
            + self.bring_your_own_string_fee
            + self.service_fee
            + self.tax
        )

    @property
    def payout_amount(self) -> Decimal:
        """What the stringer receives — everything except the platform fee."""
        return self.strings_subtotal + self.labor_subtotal + self.bring_your_own_string_fee


class OrderRacquet(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="racquets")
    sport = models.CharField(
        max_length=16, choices=RacquetSport.choices, default=RacquetSport.TENNIS
    )
    model = models.CharField(max_length=200, blank=True, default="")
    main_tension = models.DecimalField(max_digits=4, decimal_places=1)
    cross_tension = models.DecimalField(max_digits=4, decimal_places=1)
    notes = models.TextField(blank=True, default="")

    string_kind = models.CharField(max_length=16, choices=StringKind.choices)
    product = models.ForeignKey(
        StringProduct, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    product_name = models.CharField(max_length=255, blank=True, default="")
    string_price = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    byos_description = models.CharField(max_length=255, blank=True, default="")

    class Meta:
        ordering = ["id"]


class Payout(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    business = models.ForeignKey(Business, on_delete=models.CASCADE, related_name="payouts")
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    stripe_payout = models.CharField(max_length=120, blank=True, default="")
    status = models.CharField(max_length=32, default="pending")
    paid_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
