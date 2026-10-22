"""Stripe capture.

Payment happens in exactly one place: when the player accepts the stringer's
proposed pick-up time. Nothing is authorized at checkout, so there is no
separate authorize/capture pair — a single PaymentIntent is created and
confirmed here.

Without STRIPE_SECRET_KEY the capture is simulated so the whole order flow
still works locally.
"""

import logging
from decimal import Decimal

from django.conf import settings

from .exceptions import PaymentDeclined

logger = logging.getLogger("api")


class PaymentResult:
    def __init__(self, intent_id: str, last4: str = "", simulated: bool = False):
        self.intent_id = intent_id
        self.last4 = last4
        self.simulated = simulated


def stripe_enabled() -> bool:
    return bool(settings.STRIPE_SECRET_KEY)


def capture_order_payment(order, *, payment_method_id: str = "") -> PaymentResult:
    """Charges `order.total`. Raises ValidationError (→ HTTP 402) if declined."""

    amount_cents = int((order.total * Decimal("100")).to_integral_value())

    if not stripe_enabled():
        logger.warning(
            "STRIPE_SECRET_KEY not set — simulating a %s capture for order %s",
            order.total,
            order.order_number,
        )
        return PaymentResult(intent_id=f"pi_simulated_{order.order_number}", last4="4242", simulated=True)

    import stripe

    stripe.api_key = settings.STRIPE_SECRET_KEY

    try:
        intent = stripe.PaymentIntent.create(
            amount=amount_cents,
            currency="usd",
            payment_method=payment_method_id or None,
            # The player already chose to pay by accepting the pick-up time,
            # so confirm in the same call rather than round-tripping.
            confirm=bool(payment_method_id),
            automatic_payment_methods={"enabled": True, "allow_redirects": "never"}
            if not payment_method_id
            else None,
            metadata={
                "order_id": str(order.id),
                "order_number": order.order_number,
                "business_id": str(order.business_id),
                "player_id": str(order.player_id),
            },
            # Route the stringer's share to their connected account and keep
            # the platform fee. Requires Stripe Connect onboarding.
            **_connect_kwargs(order),
        )
    except Exception as error:  # noqa: BLE001 — stripe raises many types
        logger.exception("Stripe capture failed for %s", order.order_number)
        raise PaymentDeclined(str(error))

    if intent.status not in {"succeeded", "requires_capture", "processing"}:
        raise PaymentDeclined(f"Payment was not completed (status: {intent.status}).")

    last4 = ""
    charges = getattr(intent, "charges", None)
    if charges and charges.data:
        details = charges.data[0].payment_method_details
        card = getattr(details, "card", None)
        last4 = getattr(card, "last4", "") or ""

    return PaymentResult(intent_id=intent.id, last4=last4)


def _connect_kwargs(order) -> dict:
    account_id = order.business.stripe_account_id
    if not account_id:
        return {}
    # Serving keeps the player's service fee and the stringer commission;
    # Stripe sends the rest (the stringer's prices less commission, plus tax)
    # to the stringer's connected account.
    fee_cents = int((order.platform_revenue * Decimal("100")).to_integral_value())
    return {
        "application_fee_amount": fee_cents,
        "transfer_data": {"destination": account_id},
    }


def refund_order(order) -> bool:
    if not stripe_enabled() or not order.stripe_payment_intent:
        return True
    if order.stripe_payment_intent.startswith("pi_simulated_"):
        return True

    import stripe

    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        stripe.Refund.create(payment_intent=order.stripe_payment_intent)
        return True
    except Exception:  # noqa: BLE001
        logger.exception("Refund failed for %s", order.order_number)
        return False
