"""Phone verification.

Codes are hashed before storage and expire. Without Twilio credentials the
code is logged to the console instead of texted, and (in DEBUG only) returned
in the response so the signup flow is usable on a local machine.
"""

import hashlib
import hmac
import logging
import random
from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from .models import PhoneVerification

logger = logging.getLogger("api")


def normalize_phone(raw: str) -> str:
    """Digits only, so "(408) 555-0134" and "4085550134" are the same number."""
    digits = "".join(character for character in raw if character.isdigit())
    # Drop a US country code so formatting differences don't create two rows.
    if len(digits) == 11 and digits.startswith("1"):
        digits = digits[1:]
    return digits


def hash_code(phone: str, code: str) -> str:
    return hmac.new(
        settings.SECRET_KEY.encode(), f"{phone}:{code}".encode(), hashlib.sha256
    ).hexdigest()


def send_code(raw_phone: str) -> tuple[PhoneVerification, str | None]:
    """Issues a code. Returns the record and, in dev mode, the plain code."""

    phone = normalize_phone(raw_phone)
    code = f"{random.randint(0, 999999):06d}"

    verification = PhoneVerification.objects.create(
        phone=phone,
        code_hash=hash_code(phone, code),
        expires_at=timezone.now() + timedelta(minutes=settings.PHONE_CODE_TTL_MINUTES),
    )

    if settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN:
        _send_via_twilio(phone, code)
        return verification, None

    logger.warning("SMS not configured — verification code for %s is %s", phone, code)
    return verification, code if settings.DEBUG else None


def _send_via_twilio(phone: str, code: str) -> None:
    # Imported lazily so the dependency stays optional.
    from twilio.rest import Client

    client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
    client.messages.create(
        to=f"+1{phone}" if len(phone) == 10 else f"+{phone}",
        from_=settings.TWILIO_FROM_NUMBER,
        body=f"Your Tensora verification code is {code}.",
    )


def verify_code(raw_phone: str, code: str) -> bool:
    phone = normalize_phone(raw_phone)
    verification = (
        PhoneVerification.objects.filter(phone=phone, verified_at__isnull=True)
        .order_by("-created_at")
        .first()
    )
    if verification is None or verification.is_expired:
        return False
    if verification.attempts >= settings.PHONE_CODE_MAX_ATTEMPTS:
        return False

    verification.attempts += 1
    matched = hmac.compare_digest(verification.code_hash, hash_code(phone, code))
    if matched:
        verification.verified_at = timezone.now()
    verification.save(update_fields=["attempts", "verified_at"])
    return matched


def is_recently_verified(raw_phone: str) -> bool:
    """Used by account setup — the client's `phone_verified` flag is not trusted."""
    phone = normalize_phone(raw_phone)
    cutoff = timezone.now() - timedelta(hours=1)
    return PhoneVerification.objects.filter(
        phone=phone, verified_at__isnull=False, verified_at__gte=cutoff
    ).exists()
