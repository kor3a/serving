"""APNs notifications for order events.

Payload shape matches what PushService.swift reads:

    {"aps": {...}, "type": "order.acknowledged", "order_id": "<uuid>"}

Without APNs credentials the notification is logged instead of sent, so the
order flow is fully exercisable in development.
"""

import json
import logging
import time

from django.conf import settings

logger = logging.getLogger("api")

APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com"
APNS_HOST_PRODUCTION = "https://api.push.apple.com"


def apns_configured() -> bool:
    return bool(settings.APNS_KEY_ID and settings.APNS_TEAM_ID and settings.APNS_KEY_PATH)


def notify_order(user, *, event: str, title: str, body: str, order) -> None:
    """Sends `event` to every device the user has registered."""

    tokens = list(user.device_tokens.values_list("token", flat=True))
    payload = {
        "aps": {"alert": {"title": title, "body": body}, "sound": "default"},
        "type": event,
        "order_id": str(order.id),
    }

    if not tokens:
        logger.info("No devices registered for %s — skipping %s", user.email, event)
        return

    if not apns_configured():
        logger.info("APNs not configured — would send %s to %s: %s", event, user.email, body)
        return

    token_jwt = _provider_token()
    host = APNS_HOST_SANDBOX if settings.APNS_USE_SANDBOX else APNS_HOST_PRODUCTION

    # httpx speaks HTTP/2, which APNs requires.
    try:
        import httpx
    except ImportError:
        logger.warning("Install httpx[http2] to deliver push notifications.")
        return

    with httpx.Client(http2=True, timeout=10) as client:
        for device_token in tokens:
            response = client.post(
                f"{host}/3/device/{device_token}",
                headers={
                    "authorization": f"bearer {token_jwt}",
                    "apns-topic": settings.APNS_TOPIC,
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                },
                content=json.dumps(payload),
            )
            if response.status_code == 410:
                user.device_tokens.filter(token=device_token).delete()
            elif response.status_code >= 400:
                logger.warning("APNs rejected %s: %s", device_token[:8], response.text)


def _provider_token() -> str:
    import jwt

    with open(settings.APNS_KEY_PATH, "rb") as key_file:
        signing_key = key_file.read()

    return jwt.encode(
        {"iss": settings.APNS_TEAM_ID, "iat": int(time.time())},
        signing_key,
        algorithm="ES256",
        headers={"kid": settings.APNS_KEY_ID},
    )


# ---------------------------------------------------------------- events


def order_created(order):
    owner = getattr(order.business, "owner_account", None)
    if owner:
        notify_order(
            owner,
            event="order.created",
            title="New stringing request",
            body=f"{order.player_name} · {order.racquets.count()} racquet(s)",
            order=order,
        )


def order_acknowledged(order):
    when = order.proposed_pick_up_date
    notify_order(
        order.player,
        event="order.acknowledged",
        title="Pick-up time proposed",
        # %-d / %-I aren't supported by Windows' strftime, so unpad by hand.
        body=f"{order.business_name} can have it ready "
        f"{when:%a, %b} {when.day} at {when.hour % 12 or 12}:{when:%M %p}."
        if when
        else f"{order.business_name} responded to your request.",
        order=order,
    )


def order_declined(order):
    notify_order(
        order.player,
        event="order.declined",
        title="Request declined",
        body=f"{order.business_name} can't take this job. You were not charged.",
        order=order,
    )


def order_confirmed(order):
    owner = getattr(order.business, "owner_account", None)
    if owner:
        notify_order(
            owner,
            event="order.confirmed",
            title="Order confirmed",
            body=f"{order.player_name} accepted your pick-up time and paid.",
            order=order,
        )


def order_status_changed(order):
    event = "order.in_progress" if order.status == "inProgress" else "order.complete"
    body = (
        "Your racquet is on the stringing machine."
        if order.status == "inProgress"
        else "Ready for pick up."
    )
    notify_order(order.player, event=event, title=order.business_name, body=body, order=order)


def order_cancelled(order, *, notify_player: bool):
    recipient = order.player if notify_player else getattr(order.business, "owner_account", None)
    if recipient:
        notify_order(
            recipient,
            event="order.cancelled",
            title="Order cancelled",
            body=f"Order {order.order_number} was cancelled.",
            order=order,
        )
