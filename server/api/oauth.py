"""Verification of Apple and Google identity tokens.

Both providers sign their ID tokens with rotating RSA keys published as JWKS.
We fetch the key set, verify the signature, issuer and audience, and return the
claims we care about.

In DEBUG, `OAUTH_ALLOW_UNVERIFIED_TOKENS` lets an unsigned placeholder through
so the simulator can sign in before the client SDKs are wired up. Never enable
that in production.
"""

import logging
import time

import jwt
import requests
from jwt import PyJWKClient
from rest_framework import serializers

logger = logging.getLogger("api")

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}

_jwk_clients: dict[str, PyJWKClient] = {}


def _jwk_client(url: str) -> PyJWKClient:
    if url not in _jwk_clients:
        _jwk_clients[url] = PyJWKClient(url, cache_keys=True)
    return _jwk_clients[url]


class OAuthClaims:
    def __init__(self, subject: str, email: str | None, email_verified: bool = False):
        self.subject = subject
        self.email = (email or "").lower() or None
        self.email_verified = email_verified


def _unverified_claims(token: str) -> dict:
    return jwt.decode(token, options={"verify_signature": False})


def verify_apple_token(token: str, *, audience: str, allow_unverified: bool) -> OAuthClaims:
    try:
        signing_key = _jwk_client(APPLE_JWKS_URL).get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=audience,
            issuer=APPLE_ISSUER,
        )
    except Exception as error:  # noqa: BLE001 — any failure is a rejected token
        if not allow_unverified:
            logger.warning("Apple token verification failed: %s", error)
            raise serializers.ValidationError({"identity_token": ["Could not verify this token."]})
        logger.warning("Accepting UNVERIFIED Apple token (development mode): %s", error)
        claims = _claims_or_placeholder(token, "apple")

    return OAuthClaims(
        subject=claims.get("sub", ""),
        email=claims.get("email"),
        email_verified=str(claims.get("email_verified", "false")).lower() == "true",
    )


def verify_google_token(token: str, *, audiences: list[str], allow_unverified: bool) -> OAuthClaims:
    try:
        signing_key = _jwk_client(GOOGLE_JWKS_URL).get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=audiences or None,
            options={"verify_aud": bool(audiences)},
        )
        if claims.get("iss") not in GOOGLE_ISSUERS:
            raise ValueError(f"Unexpected issuer {claims.get('iss')}")
    except Exception as error:  # noqa: BLE001
        if not allow_unverified:
            logger.warning("Google token verification failed: %s", error)
            raise serializers.ValidationError({"id_token": ["Could not verify this token."]})
        logger.warning("Accepting UNVERIFIED Google token (development mode): %s", error)
        claims = _claims_or_placeholder(token, "google")

    return OAuthClaims(
        subject=claims.get("sub", ""),
        email=claims.get("email"),
        email_verified=bool(claims.get("email_verified", False)),
    )


def _claims_or_placeholder(token: str, provider: str) -> dict:
    """Development fallback: read the token if it parses, else invent an identity.

    The mock tokens the app sends before the SDKs are wired up ("mock-google-
    id-token") are not JWTs at all, so we key a stable dev account off the
    token string itself.
    """
    try:
        return _unverified_claims(token)
    except Exception:  # noqa: BLE001
        digest = abs(hash(token)) % 10_000_000
        return {
            "sub": f"dev-{provider}-{digest}",
            "email": f"dev-{provider}-{digest}@example.com",
            "email_verified": True,
            "iat": int(time.time()),
        }
