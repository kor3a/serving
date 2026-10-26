"""Serializers producing exactly the JSON documented in docs/API_CONTRACT.md.

Two rules matter more than anything else here:

1. Optional Swift values must be `null`, never `""`. `AppUser.avatarURL` is a
   `URL?` — an empty string fails to decode.
2. Non-optional Swift values must always be present, including empty arrays on
   unclaimed businesses.
"""

from decimal import Decimal

from rest_framework import serializers

from .models import (
    AccountType,
    Business,
    OpenHours,
    Order,
    OrderRacquet,
    PlayerRacquet,
    OrderStatus,
    PaymentMethod,
    StringingService,
    StringKind,
    StringProduct,
    User,
)


def none_if_blank(value):
    return value if value else None


# ---------------------------------------------------------------- shared


class AddressSerializer(serializers.Serializer):
    line1 = serializers.CharField(allow_blank=True, default="")
    line2 = serializers.CharField(allow_blank=True, default="")
    city = serializers.CharField(allow_blank=True, default="")
    state = serializers.CharField(allow_blank=True, default="")
    postal_code = serializers.CharField(allow_blank=True, default="")


class CoordinateSerializer(serializers.Serializer):
    latitude = serializers.FloatField()
    longitude = serializers.FloatField()


# ---------------------------------------------------------------- users


class UserSerializer(serializers.ModelSerializer):
    owner_name = serializers.SerializerMethodField()
    avatar_url = serializers.SerializerMethodField()
    business_id = serializers.UUIDField(source="business.id", allow_null=True, read_only=True)

    class Meta:
        model = User
        fields = [
            "id",
            "email",
            "account_type",
            "display_name",
            "owner_name",
            "phone",
            "phone_verified",
            "business_id",
            "avatar_url",
            "created_at",
        ]

    def get_owner_name(self, user):
        return none_if_blank(user.owner_name)

    def get_avatar_url(self, user):
        return none_if_blank(user.avatar_url)


class AccountSetupSerializer(serializers.Serializer):
    """Payload from SetUpAccountView."""

    account_type = serializers.ChoiceField(choices=AccountType.choices)
    email = serializers.EmailField(required=False, allow_blank=True)
    password = serializers.CharField(min_length=8, write_only=True)
    phone = serializers.CharField()
    phone_verified = serializers.BooleanField(required=False, default=False)

    business_name = serializers.CharField(required=False, allow_blank=True, default="")
    owner_name = serializers.CharField(required=False, allow_blank=True, default="")
    address = AddressSerializer(required=False)
    player_name = serializers.CharField(required=False, allow_blank=True, default="")

    def validate(self, attrs):
        if attrs["account_type"] == AccountType.BUSINESS:
            missing = [
                field
                for field in ("business_name", "owner_name")
                if not (attrs.get(field) or "").strip()
            ]
            if missing:
                raise serializers.ValidationError(
                    {field: ["This field is required for business accounts."] for field in missing}
                )
        elif not (attrs.get("player_name") or "").strip():
            raise serializers.ValidationError(
                {"player_name": ["This field is required for player accounts."]}
            )
        return attrs


# ---------------------------------------------------------------- storefront


class OpenHoursSerializer(serializers.ModelSerializer):
    class Meta:
        model = OpenHours
        fields = ["weekday", "opens_at_minutes", "closes_at_minutes", "is_closed"]


class StringingServiceSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)

    class Meta:
        model = StringingService
        fields = ["id", "name", "details", "labor_price", "turnaround_hours", "is_active"]


class StringProductSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)

    class Meta:
        model = StringProduct
        fields = [
            "id",
            "brand",
            "name",
            "category",
            "sport",
            "gauge",
            "price",
            "stock_count",
            "details",
            "is_active",
        ]


class BusinessSerializer(serializers.ModelSerializer):
    address = serializers.SerializerMethodField()
    coordinate = serializers.SerializerMethodField()
    services = StringingServiceSerializer(many=True, read_only=True)
    inventory = StringProductSerializer(many=True, read_only=True)
    open_hours = OpenHoursSerializer(many=True, read_only=True)
    rating = serializers.SerializerMethodField()

    class Meta:
        model = Business
        fields = [
            "id",
            "name",
            "owner_name",
            "phone",
            "address",
            "coordinate",
            "location_kind",
            "is_claimed",
            "about",
            "rating",
            "rating_count",
            "typical_turnaround_hours",
            "accepts_bring_your_own_string",
            "bring_your_own_string_fee",
            "drop_off_instructions",
            "services",
            "inventory",
            "open_hours",
        ]

    def get_address(self, business):
        return {
            "line1": business.line1,
            "line2": business.line2,
            "city": business.city,
            "state": business.state,
            "postal_code": business.postal_code,
        }

    def get_coordinate(self, business):
        # Non-optional on the client, so always emit a pair.
        return {
            "latitude": business.latitude or 0.0,
            "longitude": business.longitude or 0.0,
        }

    def get_rating(self, business):
        return float(business.rating) if business.rating is not None else None


class BusinessProfileUpdateSerializer(serializers.Serializer):
    """PATCH body for the storefront editor. Every field is optional."""

    name = serializers.CharField(required=False)
    owner_name = serializers.CharField(required=False, allow_blank=True)
    phone = serializers.CharField(required=False, allow_blank=True)
    about = serializers.CharField(required=False, allow_blank=True)
    address = AddressSerializer(required=False)
    coordinate = CoordinateSerializer(required=False)
    location_kind = serializers.CharField(required=False)
    typical_turnaround_hours = serializers.IntegerField(required=False, min_value=1)
    accepts_bring_your_own_string = serializers.BooleanField(required=False)
    bring_your_own_string_fee = serializers.DecimalField(
        required=False, max_digits=10, decimal_places=2
    )
    drop_off_instructions = serializers.CharField(required=False, allow_blank=True)
    open_hours = OpenHoursSerializer(many=True, required=False)


# ---------------------------------------------------------------- player racquets


class PlayerRacquetSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    main_tension = serializers.FloatField(min_value=10, max_value=90)
    cross_tension = serializers.FloatField(min_value=10, max_value=90)

    class Meta:
        model = PlayerRacquet
        fields = [
            "id",
            "sport",
            "manufacturer",
            "model",
            "color",
            "main_tension",
            "cross_tension",
        ]

    def validate_manufacturer(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Enter the racquet's manufacturer.")
        return value


# ---------------------------------------------------------------- orders


class StringSelectionField(serializers.Field):
    """Maps the tagged `string_selection` object onto the flat racquet row.

        {"kind": "storefront", "product_id": …, "product_name": …, "price": …}
        {"kind": "byos", "description": "Solinco Tour Bite 17"}
    """

    def to_representation(self, racquet):
        if racquet.string_kind == StringKind.STOREFRONT:
            return {
                "kind": "storefront",
                "product_id": str(racquet.product_id) if racquet.product_id else None,
                "product_name": racquet.product_name,
                "price": racquet.string_price,
            }
        return {"kind": "byos", "description": racquet.byos_description}

    def to_internal_value(self, data):
        if not isinstance(data, dict):
            raise serializers.ValidationError("Expected an object.")
        kind = data.get("kind")
        if kind == "storefront":
            product_id = data.get("product_id")
            if not product_id:
                raise serializers.ValidationError({"product_id": ["Required for storefront strings."]})
            return {
                "string_kind": StringKind.STOREFRONT,
                "product_id": product_id,
                "product_name": data.get("product_name", ""),
            }
        if kind == "byos":
            return {
                "string_kind": StringKind.BYOS,
                "byos_description": (data.get("description") or "").strip(),
            }
        raise serializers.ValidationError({"kind": ['Must be "storefront" or "byos".']})


class OrderRacquetSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    string_selection = StringSelectionField(source="*")
    main_tension = serializers.FloatField()
    cross_tension = serializers.FloatField()

    class Meta:
        model = OrderRacquet
        fields = [
            "id",
            "sport",
            "model",
            "color",
            "string_selection",
            "main_tension",
            "cross_tension",
            "notes",
        ]


class OrderSerializer(serializers.ModelSerializer):
    business_id = serializers.UUIDField(read_only=True)
    player_id = serializers.UUIDField(read_only=True)
    service_id = serializers.UUIDField(read_only=True, allow_null=True)
    racquets = OrderRacquetSerializer(many=True, read_only=True)
    drop_off_address = serializers.SerializerMethodField()
    business_note = serializers.SerializerMethodField()
    pricing = serializers.SerializerMethodField()
    payment = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = [
            "id",
            "order_number",
            "business_id",
            "business_name",
            "business_phone",
            "player_id",
            "player_name",
            "player_phone",
            "racquets",
            "service_id",
            "service_name",
            "drop_off_date",
            "drop_off_address",
            "drop_off_instructions",
            "proposed_pick_up_date",
            "confirmed_pick_up_date",
            "business_note",
            "pricing",
            "payment",
            "status",
            "created_at",
            "updated_at",
        ]

    def get_drop_off_address(self, order):
        return {
            "line1": order.drop_off_line1,
            "line2": order.drop_off_line2,
            "city": order.drop_off_city,
            "state": order.drop_off_state,
            "postal_code": order.drop_off_postal_code,
        }

    def get_business_note(self, order):
        return none_if_blank(order.business_note)

    def get_pricing(self, order):
        return {
            "strings_subtotal": order.strings_subtotal,
            "labor_subtotal": order.labor_subtotal,
            "bring_your_own_string_fee": order.bring_your_own_string_fee,
            "service_fee": order.service_fee,
            "tax": order.tax,
        }

    def get_payment(self, order):
        charged_at = order.charged_at
        return {
            "method": order.payment_method,
            "state": order.payment_state,
            "payment_intent_id": none_if_blank(order.stripe_payment_intent),
            "charged_at": serializers.DateTimeField().to_representation(charged_at)
            if charged_at
            else None,
            "last4": none_if_blank(order.card_last4),
        }


class OrderDraftSerializer(serializers.Serializer):
    """POST /orders/ — what CheckoutView submits."""

    business_id = serializers.UUIDField()
    service_id = serializers.UUIDField(required=False, allow_null=True)
    drop_off_date = serializers.DateTimeField()
    payment_method = serializers.ChoiceField(
        choices=PaymentMethod.choices, default=PaymentMethod.APPLE_PAY
    )
    note_for_stringer = serializers.CharField(required=False, allow_blank=True, default="")
    racquets = OrderRacquetSerializer(many=True)

    def validate_racquets(self, racquets):
        if not racquets:
            raise serializers.ValidationError("An order needs at least one racquet.")
        return racquets


class AcknowledgeSerializer(serializers.Serializer):
    proposed_pick_up_date = serializers.DateTimeField()
    note = serializers.CharField(required=False, allow_blank=True, allow_null=True, default="")


class DeclineSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, allow_null=True, default="")


class AcceptPickUpSerializer(serializers.Serializer):
    payment_method = serializers.ChoiceField(
        choices=PaymentMethod.choices, default=PaymentMethod.APPLE_PAY
    )
    # Set by the Stripe SDK once Apple Pay / card details are collected.
    payment_method_id = serializers.CharField(required=False, allow_blank=True, default="")


class OrderStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=OrderStatus.choices)

    def validate_status(self, value):
        allowed = {OrderStatus.IN_PROGRESS, OrderStatus.COMPLETE, OrderStatus.PICKED_UP}
        if value not in allowed:
            raise serializers.ValidationError(
                "Only inProgress, complete and pickedUp can be set directly."
            )
        return value


class EarningsSerializer(serializers.Serializer):
    pending_payout = serializers.DecimalField(max_digits=10, decimal_places=2)
    paid_out_this_month = serializers.DecimalField(max_digits=10, decimal_places=2)
    gross_this_week = serializers.DecimalField(max_digits=10, decimal_places=2)
    completed_orders_this_month = serializers.IntegerField()
    next_payout_date = serializers.DateTimeField(allow_null=True)
    payout_status = serializers.CharField()


class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField()
    platform = serializers.CharField(required=False, default="ios")


# ---------------------------------------------------------------- auth I/O


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField()


class SignupSerializer(serializers.Serializer):
    email = serializers.EmailField()


class AppleOAuthSerializer(serializers.Serializer):
    identity_token = serializers.CharField()
    full_name = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    email = serializers.EmailField(required=False, allow_blank=True, allow_null=True)


class GoogleOAuthSerializer(serializers.Serializer):
    id_token = serializers.CharField()


class PhoneRequestSerializer(serializers.Serializer):
    phone = serializers.CharField()


class PhoneVerifySerializer(serializers.Serializer):
    phone = serializers.CharField()
    code = serializers.CharField(min_length=4, max_length=8)


def zero_money() -> Decimal:
    return Decimal("0.00")
