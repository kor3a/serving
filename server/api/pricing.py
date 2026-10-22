"""Order pricing — the server-side source of truth.

Mirrors Serving/Core/Backend/PricingEngine.swift, which computes the same
numbers for the pre-submit estimate. If you change one, change the other.
"""

from decimal import Decimal, ROUND_HALF_EVEN

from django.conf import settings

from .models import Business, StringKind, StringingService

CENTS = Decimal("0.01")


def money(value) -> Decimal:
    return Decimal(value).quantize(CENTS, rounding=ROUND_HALF_EVEN)


def player_service_fee() -> Decimal:
    return Decimal(settings.PLAYER_SERVICE_FEE)


def stringer_commission_rate() -> Decimal:
    return Decimal(settings.STRINGER_COMMISSION_RATE)


def tax_rate_for(business: Business) -> Decimal:
    """Flat rate placeholder.

    Swap in a tax provider (Stripe Tax, Avalara) keyed on the drop-off
    address when you need real rates — this is the only place to change.
    """
    return Decimal(settings.DEFAULT_TAX_RATE)


def compute_breakdown(
    *,
    racquets: list[dict],
    service: StringingService | None,
    business: Business,
) -> dict[str, Decimal]:
    """`racquets` are dicts with `string_kind` and `string_price` resolved."""

    strings_subtotal = sum(
        (Decimal(item.get("string_price") or 0) for item in racquets), Decimal("0")
    )

    labor_price = service.labor_price if service else Decimal("0")
    labor_subtotal = labor_price * len(racquets)

    byos_count = sum(1 for item in racquets if item.get("string_kind") == StringKind.BYOS)
    byos_fee = business.bring_your_own_string_fee * byos_count

    merchandise = strings_subtotal + labor_subtotal + byos_fee
    service_fee = player_service_fee()
    # Taken out of the stringer's payout, so it is not part of what the
    # player pays.
    stringer_commission = merchandise * stringer_commission_rate()
    tax = (strings_subtotal + byos_fee) * tax_rate_for(business)

    return {
        "strings_subtotal": money(strings_subtotal),
        "labor_subtotal": money(labor_subtotal),
        "bring_your_own_string_fee": money(byos_fee),
        "service_fee": money(service_fee),
        "stringer_commission": money(stringer_commission),
        "tax": money(tax),
    }
