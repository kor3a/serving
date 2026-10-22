"""API endpoints.

Route order and payloads follow docs/API_CONTRACT.md; the Swift side lists the
same paths in Core/Networking/Endpoint.swift.
"""

import logging
import math
import random
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import authenticate
from django.db import transaction
from django.db.models import F, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from . import oauth, payments, push, sms
from .exceptions import OrderTransitionError
from .models import (
    AccountType,
    Business,
    DeviceToken,
    OpenHours,
    Order,
    OrderRacquet,
    OrderStatus,
    PaymentState,
    PayoutStatus,
    StringingService,
    StringKind,
    StringProduct,
    User,
)
from .pricing import compute_breakdown, money
from .serializers import (
    AcceptPickUpSerializer,
    AccountSetupSerializer,
    AcknowledgeSerializer,
    AppleOAuthSerializer,
    BusinessProfileUpdateSerializer,
    BusinessSerializer,
    DeclineSerializer,
    DeviceTokenSerializer,
    EarningsSerializer,
    GoogleOAuthSerializer,
    LoginSerializer,
    OrderDraftSerializer,
    OrderSerializer,
    OrderStatusSerializer,
    PhoneRequestSerializer,
    PhoneVerifySerializer,
    SignupSerializer,
    StringingServiceSerializer,
    StringProductSerializer,
    UserSerializer,
)

logger = logging.getLogger("api")


# ---------------------------------------------------------------- helpers


def auth_session(user: User, *, email: str | None = None) -> dict:
    """The `AuthSession` the client expects from every auth endpoint.

    `user` is null until account setup finishes — that is what routes the app
    to SetUpAccountView.
    """
    refresh = RefreshToken.for_user(user)
    return {
        "access_token": str(refresh.access_token),
        "refresh_token": str(refresh),
        "email": email or user.email,
        "user": UserSerializer(user).data if user.setup_complete else None,
    }


def business_queryset():
    return Business.objects.prefetch_related("services", "inventory", "open_hours")


def order_queryset():
    return Order.objects.select_related("business", "player").prefetch_related("racquets")


def next_order_number() -> str:
    """Short, human-quotable id. Retries on the (unlikely) collision."""
    for _ in range(10):
        candidate = f"TN-{random.randint(1000, 99999)}"
        if not Order.objects.filter(order_number=candidate).exists():
            return candidate
    return f"TN-{timezone.now().timestamp():.0f}"


def haversine_meters(lat1, lon1, lat2, lon2) -> float:
    radius = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


# ---------------------------------------------------------------- auth


@api_view(["POST"])
@permission_classes([AllowAny])
def login(request):
    serializer = LoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data["email"].lower()

    user = authenticate(request, username=email, password=serializer.validated_data["password"])
    if user is None:
        return Response(
            {"detail": "That email and password combination didn't work."},
            status=status.HTTP_401_UNAUTHORIZED,
        )
    return Response(auth_session(user))


@api_view(["POST"])
@permission_classes([AllowAny])
def signup(request):
    """Email-only signup. The account exists but is not usable until setup."""
    serializer = SignupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data["email"].lower()

    user = User.objects.filter(email=email).first()
    if user and user.setup_complete:
        return Response(
            {"email": ["An account with this email already exists. Log in instead."]},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if user is None:
        user = User.objects.create_user(email=email)

    return Response(auth_session(user, email=email), status=status.HTTP_201_CREATED)


@api_view(["POST"])
@permission_classes([AllowAny])
def apple_oauth(request):
    serializer = AppleOAuthSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    claims = oauth.verify_apple_token(
        data["identity_token"],
        audience=settings.APPLE_BUNDLE_ID,
        allow_unverified=settings.OAUTH_ALLOW_UNVERIFIED_TOKENS,
    )
    # Apple only returns the email on the very first authorization, so fall
    # back to whatever the client captured then.
    email = claims.email or (data.get("email") or "").lower()
    user = _user_for_oauth(
        subject_field="apple_subject",
        subject=claims.subject,
        email=email,
        full_name=data.get("full_name"),
    )
    return Response(auth_session(user, email=email or user.email))


@api_view(["POST"])
@permission_classes([AllowAny])
def google_oauth(request):
    serializer = GoogleOAuthSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    claims = oauth.verify_google_token(
        serializer.validated_data["id_token"],
        audiences=settings.GOOGLE_CLIENT_IDS,
        allow_unverified=settings.OAUTH_ALLOW_UNVERIFIED_TOKENS,
    )
    user = _user_for_oauth(
        subject_field="google_subject", subject=claims.subject, email=claims.email
    )
    return Response(auth_session(user, email=claims.email or user.email))


def _user_for_oauth(*, subject_field: str, subject: str, email: str | None, full_name=None) -> User:
    user = None
    if subject:
        user = User.objects.filter(**{subject_field: subject}).first()
    if user is None and email:
        user = User.objects.filter(email=email).first()
    if user is None:
        user = User.objects.create_user(
            email=email or f"{subject}@privaterelay.appleid.com",
            display_name=(full_name or "").strip(),
        )
    if subject and getattr(user, subject_field) != subject:
        setattr(user, subject_field, subject)
        user.save(update_fields=[subject_field])
    return user


@api_view(["GET"])
def me(request):
    return Response(UserSerializer(request.user).data)


@api_view(["POST"])
def logout(request):
    """Drops this device's push token; JWTs expire on their own."""
    DeviceToken.objects.filter(user=request.user).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@permission_classes([AllowAny])
def phone_request_code(request):
    serializer = PhoneRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    _, dev_code = sms.send_code(serializer.validated_data["phone"])
    body = {}
    if dev_code:
        # DEBUG only — lets you complete signup without an SMS provider.
        body["dev_code"] = dev_code
    return Response(body, status=status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([AllowAny])
def phone_verify(request):
    serializer = PhoneVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    verified = sms.verify_code(
        serializer.validated_data["phone"], serializer.validated_data["code"]
    )
    return Response({"verified": verified})


@api_view(["POST"])
@transaction.atomic
def account_setup(request):
    serializer = AccountSetupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    user = request.user
    phone = data["phone"]

    # The client's phone_verified flag is a UI hint, not proof.
    if not sms.is_recently_verified(phone):
        return Response(
            {"phone": ["Verify this phone number before finishing setup."]},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user.account_type = data["account_type"]
    user.phone = phone
    user.phone_verified = True
    user.set_password(data["password"])

    if data["account_type"] == AccountType.BUSINESS:
        address = data.get("address") or {}
        business = Business.objects.create(
            name=data["business_name"].strip(),
            owner_name=data["owner_name"].strip(),
            phone=phone,
            line1=address.get("line1", ""),
            line2=address.get("line2", ""),
            city=address.get("city", ""),
            state=address.get("state", ""),
            postal_code=address.get("postal_code", ""),
            is_claimed=True,
        )
        # A shop with no services can't be booked, so seed the obvious one.
        StringingService.objects.create(
            business=business, name="Standard Stringing", labor_price=Decimal("20.00")
        )
        OpenHours.objects.bulk_create(
            [
                OpenHours(business=business, weekday=weekday, is_closed=weekday == 1)
                for weekday in range(1, 8)
            ]
        )
        user.business = business
        user.display_name = business.name
        user.owner_name = business.owner_name
    else:
        user.display_name = data["player_name"].strip()
        user.owner_name = ""

    user.setup_complete = True
    user.save()

    return Response(auth_session(user), status=status.HTTP_200_OK)


@api_view(["POST"])
def register_device_token(request):
    serializer = DeviceTokenSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    DeviceToken.objects.update_or_create(
        token=serializer.validated_data["token"],
        defaults={"user": request.user, "platform": serializer.validated_data["platform"]},
    )
    return Response(status=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- discovery


@api_view(["GET"])
@permission_classes([AllowAny])
def business_search(request):
    """Nearby stringers, closest first.

    Returns claimed storefronts alongside unclaimed shops imported from map
    data — the client renders the two differently.
    """
    try:
        latitude = float(request.query_params.get("lat", ""))
        longitude = float(request.query_params.get("lng", ""))
    except ValueError:
        return Response(
            {"detail": "lat and lng are required."}, status=status.HTTP_400_BAD_REQUEST
        )

    radius_m = float(request.query_params.get("radius_m", 25_000))
    query = (request.query_params.get("q") or "").strip()

    businesses = business_queryset()
    if query:
        businesses = businesses.filter(
            Q(name__icontains=query) | Q(city__icontains=query) | Q(line1__icontains=query)
        )

    # Cheap bounding box first, exact distance second. Swap in PostGIS
    # (see docs/supabase_schema.sql) once the table gets large.
    degrees = radius_m / 111_000
    businesses = businesses.filter(
        latitude__isnull=False,
        longitude__isnull=False,
        latitude__gte=latitude - degrees,
        latitude__lte=latitude + degrees,
        longitude__gte=longitude - degrees,
        longitude__lte=longitude + degrees,
    )

    with_distance = []
    for business in businesses:
        distance = haversine_meters(latitude, longitude, business.latitude, business.longitude)
        if distance <= radius_m:
            with_distance.append((distance, business))
    with_distance.sort(key=lambda pair: pair[0])

    return Response(
        BusinessSerializer([business for _, business in with_distance], many=True).data
    )


@api_view(["GET", "PATCH"])
@permission_classes([AllowAny])
def business_detail(request, business_id):
    business = get_object_or_404(business_queryset(), pk=business_id)

    if request.method == "GET":
        return Response(BusinessSerializer(business).data)

    # PATCH — storefront editor
    if not request.user.is_authenticated or request.user.business_id != business.id:
        return Response(
            {"detail": "You can only edit your own storefront."},
            status=status.HTTP_403_FORBIDDEN,
        )

    serializer = BusinessProfileUpdateSerializer(data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    address = data.pop("address", None)
    coordinate = data.pop("coordinate", None)
    open_hours = data.pop("open_hours", None)

    for field, value in data.items():
        setattr(business, field, value)
    if address:
        business.line1 = address.get("line1", business.line1)
        business.line2 = address.get("line2", business.line2)
        business.city = address.get("city", business.city)
        business.state = address.get("state", business.state)
        business.postal_code = address.get("postal_code", business.postal_code)
    if coordinate:
        business.latitude = coordinate["latitude"]
        business.longitude = coordinate["longitude"]
    business.save()

    if open_hours is not None:
        for row in open_hours:
            OpenHours.objects.update_or_create(
                business=business,
                weekday=row["weekday"],
                defaults={
                    "opens_at_minutes": row["opens_at_minutes"],
                    "closes_at_minutes": row["closes_at_minutes"],
                    "is_closed": row["is_closed"],
                },
            )

    business.refresh_from_db()
    return Response(BusinessSerializer(business).data)


# ---------------------------------------------------------------- storefront


@api_view(["PUT"])
def upsert_product(request, business_id):
    business = _own_business_or_403(request, business_id)
    if isinstance(business, Response):
        return business

    serializer = StringProductSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    product_id = data.pop("id", None)

    # The client generates the id, so an upsert keyed on (id, business) is
    # idempotent. Scoping by business stops one shop overwriting another's row.
    product = StringProduct.objects.filter(id=product_id, business=business).first()
    if product is None:
        product = StringProduct.objects.create(business=business, **({"id": product_id} if product_id else {}), **data)
    else:
        for field, value in data.items():
            setattr(product, field, value)
        product.save()

    return Response(StringProductSerializer(product).data)


@api_view(["DELETE"])
def delete_product(request, business_id, product_id):
    business = _own_business_or_403(request, business_id)
    if isinstance(business, Response):
        return business

    StringProduct.objects.filter(id=product_id, business=business).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["PUT"])
def upsert_service(request, business_id):
    business = _own_business_or_403(request, business_id)
    if isinstance(business, Response):
        return business

    serializer = StringingServiceSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    service_id = data.pop("id", None)

    service = StringingService.objects.filter(id=service_id, business=business).first()
    if service is None:
        service = StringingService.objects.create(business=business, **({"id": service_id} if service_id else {}), **data)
    else:
        for field, value in data.items():
            setattr(service, field, value)
        service.save()

    return Response(StringingServiceSerializer(service).data)


@api_view(["DELETE"])
def delete_service(request, business_id, service_id):
    business = _own_business_or_403(request, business_id)
    if isinstance(business, Response):
        return business

    StringingService.objects.filter(id=service_id, business=business).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["GET"])
def business_earnings(request, business_id):
    business = _own_business_or_403(request, business_id)
    if isinstance(business, Response):
        return business

    now = timezone.now()
    week_ago = now - timedelta(days=7)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    paid = Order.objects.filter(business=business, payment_state=PaymentState.SUCCEEDED)

    def payout_sum(queryset) -> Decimal:
        totals = queryset.aggregate(
            strings=Sum("strings_subtotal"),
            labor=Sum("labor_subtotal"),
            byos=Sum("bring_your_own_string_fee"),
            commission=Sum("stringer_commission"),
        )
        return money(
            (totals["strings"] or 0)
            + (totals["labor"] or 0)
            + (totals["byos"] or 0)
            - (totals["commission"] or 0)
        )

    # Money earned but not yet paid out: work that is paid for and underway.
    # Once you record real Stripe payouts, subtract the settled ones here.
    pending = payout_sum(
        paid.filter(status__in=[OrderStatus.CONFIRMED, OrderStatus.IN_PROGRESS])
    )

    completed_this_month = paid.filter(
        status__in=[OrderStatus.COMPLETE, OrderStatus.PICKED_UP], updated_at__gte=month_start
    )

    snapshot = {
        "pending_payout": pending,
        "paid_out_this_month": payout_sum(completed_this_month),
        "gross_this_week": payout_sum(paid.filter(charged_at__gte=week_ago)),
        "completed_orders_this_month": completed_this_month.count(),
        "next_payout_date": now + timedelta(days=2) if pending > 0 else None,
        "payout_status": business.payout_status or PayoutStatus.NOT_CONNECTED,
    }
    return Response(EarningsSerializer(snapshot).data)


def _own_business_or_403(request, business_id):
    business = get_object_or_404(Business, pk=business_id)
    if request.user.business_id != business.id:
        return Response(
            {"detail": "You can only manage your own storefront."},
            status=status.HTTP_403_FORBIDDEN,
        )
    return business


# ---------------------------------------------------------------- orders


@api_view(["GET", "POST"])
def orders_collection(request):
    if request.method == "GET":
        role = request.query_params.get("role", request.user.account_type)
        if role == AccountType.BUSINESS:
            if request.user.business_id is None:
                return Response([])
            queryset = order_queryset().filter(business_id=request.user.business_id)
        else:
            queryset = order_queryset().filter(player=request.user)
        return Response(OrderSerializer(queryset, many=True).data)

    return _create_order(request)


@transaction.atomic
def _create_order(request):
    serializer = OrderDraftSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    draft = serializer.validated_data

    business = get_object_or_404(business_queryset(), pk=draft["business_id"])
    if not business.is_claimed:
        return Response(
            {"detail": "This shop isn't on Serving yet — call them to book."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    service = None
    if draft.get("service_id"):
        service = business.services.filter(id=draft["service_id"], is_active=True).first()
    if service is None:
        service = business.services.filter(is_active=True).order_by("labor_price").first()
    if service is None:
        return Response(
            {"detail": "This shop hasn't published any services yet."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # Resolve each racquet's string against live inventory — prices come from
    # the database, never from the client.
    resolved = []
    for racquet in draft["racquets"]:
        row = {
            "sport": racquet.get("sport", "tennis"),
            "model": racquet.get("model", ""),
            "notes": racquet.get("notes", ""),
            "main_tension": racquet["main_tension"],
            "cross_tension": racquet["cross_tension"],
            "string_kind": racquet["string_kind"],
            "byos_description": racquet.get("byos_description", ""),
            "product_id": None,
            "product_name": "",
            "string_price": Decimal("0.00"),
        }

        if racquet["string_kind"] == StringKind.STOREFRONT:
            product = business.inventory.filter(id=racquet["product_id"], is_active=True).first()
            if product is None:
                return Response(
                    {"detail": "That string is no longer available from this shop."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if product.stock_count <= 0:
                return Response(
                    {"detail": f"{product.brand} {product.name} is out of stock."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            row["product_id"] = product.id
            row["product_name"] = f"{product.brand} {product.name}"
            row["string_price"] = product.price

        resolved.append(row)

    breakdown = compute_breakdown(racquets=resolved, service=service, business=business)

    order = Order.objects.create(
        order_number=next_order_number(),
        business=business,
        player=request.user,
        service=service,
        service_name=service.name,
        business_name=business.name,
        business_phone=business.phone,
        player_name=request.user.display_name or request.user.email,
        player_phone=request.user.phone,
        drop_off_line1=business.line1,
        drop_off_line2=business.line2,
        drop_off_city=business.city,
        drop_off_state=business.state,
        drop_off_postal_code=business.postal_code,
        drop_off_instructions=business.drop_off_instructions,
        drop_off_date=draft["drop_off_date"],
        business_note=(draft.get("note_for_stringer") or "").strip(),
        payment_method=draft["payment_method"],
        status=OrderStatus.AWAITING_BUSINESS,
        **breakdown,
    )

    OrderRacquet.objects.bulk_create([OrderRacquet(order=order, **row) for row in resolved])

    order = order_queryset().get(pk=order.pk)
    push.order_created(order)
    return Response(OrderSerializer(order).data, status=status.HTTP_201_CREATED)


@api_view(["GET"])
def order_detail(request, order_id):
    order = _visible_order_or_404(request, order_id)
    return Response(OrderSerializer(order).data)


@api_view(["POST"])
def acknowledge_order(request, order_id):
    """Business proposes when the racquet will be ready. Still no charge."""
    order = _visible_order_or_404(request, order_id)
    if request.user.business_id != order.business_id:
        return Response({"detail": "Only the stringer can do this."}, status=status.HTTP_403_FORBIDDEN)
    if order.status not in {OrderStatus.AWAITING_BUSINESS, OrderStatus.AWAITING_PLAYER_APPROVAL}:
        raise OrderTransitionError("This order has already moved past acknowledgement.")

    serializer = AcknowledgeSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    order.proposed_pick_up_date = serializer.validated_data["proposed_pick_up_date"]
    note = (serializer.validated_data.get("note") or "").strip()
    if note:
        order.business_note = note
    order.status = OrderStatus.AWAITING_PLAYER_APPROVAL
    order.save()

    push.order_acknowledged(order)
    return Response(OrderSerializer(order).data)


@api_view(["POST"])
def decline_order(request, order_id):
    order = _visible_order_or_404(request, order_id)
    if request.user.business_id != order.business_id:
        return Response({"detail": "Only the stringer can do this."}, status=status.HTTP_403_FORBIDDEN)
    if order.status not in {OrderStatus.AWAITING_BUSINESS, OrderStatus.AWAITING_PLAYER_APPROVAL}:
        raise OrderTransitionError("This order can no longer be declined.")

    serializer = DeclineSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    reason = (serializer.validated_data.get("reason") or "").strip()
    if reason:
        order.business_note = reason
    order.status = OrderStatus.DECLINED
    order.save()

    push.order_declined(order)
    return Response(OrderSerializer(order).data)


@api_view(["POST"])
@transaction.atomic
def accept_pick_up(request, order_id):
    """Player accepts the proposed time — the single point where money moves.

    Payment is captured first; the order is only marked confirmed if that
    succeeds, so a declined card can never leave a confirmed unpaid order.
    """
    order = _visible_order_or_404(request, order_id)
    if order.player_id != request.user.id:
        return Response({"detail": "Only the player can accept."}, status=status.HTTP_403_FORBIDDEN)
    if order.status != OrderStatus.AWAITING_PLAYER_APPROVAL:
        raise OrderTransitionError("There's no pick-up time waiting for approval on this order.")
    if order.proposed_pick_up_date is None:
        raise OrderTransitionError("The stringer hasn't proposed a pick-up time yet.")

    serializer = AcceptPickUpSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    order.payment_method = serializer.validated_data["payment_method"]
    order.payment_state = PaymentState.PROCESSING
    order.save(update_fields=["payment_method", "payment_state"])

    result = payments.capture_order_payment(
        order, payment_method_id=serializer.validated_data.get("payment_method_id", "")
    )

    order.stripe_payment_intent = result.intent_id
    order.card_last4 = result.last4
    order.charged_at = timezone.now()
    order.payment_state = PaymentState.SUCCEEDED
    order.confirmed_pick_up_date = order.proposed_pick_up_date
    order.status = OrderStatus.CONFIRMED
    order.save()

    # Stock only comes down once the order is actually paid for.
    for racquet in order.racquets.filter(string_kind=StringKind.STOREFRONT):
        StringProduct.objects.filter(id=racquet.product_id, stock_count__gt=0).update(
            stock_count=F("stock_count") - 1
        )

    push.order_confirmed(order)
    return Response(OrderSerializer(order).data)


@api_view(["PATCH"])
def update_order_status(request, order_id):
    order = _visible_order_or_404(request, order_id)
    if request.user.business_id != order.business_id:
        return Response({"detail": "Only the stringer can do this."}, status=status.HTTP_403_FORBIDDEN)

    serializer = OrderStatusSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    new_status = serializer.validated_data["status"]

    allowed = {
        OrderStatus.CONFIRMED: {OrderStatus.IN_PROGRESS},
        OrderStatus.IN_PROGRESS: {OrderStatus.COMPLETE},
        OrderStatus.COMPLETE: {OrderStatus.PICKED_UP},
    }
    if new_status not in allowed.get(order.status, set()):
        raise OrderTransitionError(f"Can't move an order from {order.status} to {new_status}.")

    order.status = new_status
    order.save(update_fields=["status", "updated_at"])

    push.order_status_changed(order)
    return Response(OrderSerializer(order).data)


@api_view(["POST"])
@transaction.atomic
def cancel_order(request, order_id):
    order = _visible_order_or_404(request, order_id)
    is_player = order.player_id == request.user.id
    is_business = request.user.business_id == order.business_id
    if not (is_player or is_business):
        return Response({"detail": "Not your order."}, status=status.HTTP_403_FORBIDDEN)
    # Once the racquet is strung there is nothing left to cancel: it is
    # waiting to be collected, or already has been.
    if order.status in {
        OrderStatus.COMPLETE,
        OrderStatus.PICKED_UP,
        OrderStatus.CANCELLED,
        OrderStatus.DECLINED,
    }:
        raise OrderTransitionError("This order can no longer be cancelled.")

    if order.payment_state == PaymentState.SUCCEEDED:
        if payments.refund_order(order):
            order.payment_state = PaymentState.REFUNDED
        else:
            return Response(
                {"detail": "We couldn't refund this order. Contact support."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

    order.status = OrderStatus.CANCELLED
    order.save()

    push.order_cancelled(order, notify_player=is_business)
    return Response(OrderSerializer(order).data)


def _visible_order_or_404(request, order_id) -> Order:
    order = get_object_or_404(order_queryset(), pk=order_id)
    if order.player_id != request.user.id and request.user.business_id != order.business_id:
        # Don't confirm the order exists to someone unrelated to it.
        from django.http import Http404

        raise Http404
    return order


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    # Formatted through a serializer field so it matches every other timestamp
    # the API emits — whole seconds, no microseconds.
    return Response(
        {
            "status": "ok",
            "time": serializers.DateTimeField().to_representation(timezone.now()),
        }
    )
