"""Django settings for the Serving API.

Configuration comes from environment variables (see server/.env.example).
Nothing here needs editing to run locally — copy .env.example to .env and go.
"""

from datetime import timedelta
from pathlib import Path

import dj_database_url
from dotenv import load_dotenv
import os

BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / ".env")


def env_bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.getenv(name, default).split(",") if item.strip()]


# ---------------------------------------------------------------- core

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-only-insecure-key-change-me")
DEBUG = env_bool("DJANGO_DEBUG", True)

# In DEBUG we accept any host so the iOS simulator and a phone on the same
# Wi-Fi can both reach the dev server.
ALLOWED_HOSTS = ["*"] if DEBUG else env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "api",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "serving.urls"
WSGI_APPLICATION = "serving.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

# ---------------------------------------------------------------- database

# DATABASE_URL points at Supabase in any real environment. Without it we fall
# back to SQLite so `manage.py runserver` works on a fresh clone.
DATABASE_URL = os.getenv("DATABASE_URL", "")

if DATABASE_URL:
    DATABASES = {
        "default": dj_database_url.parse(
            DATABASE_URL,
            conn_max_age=int(os.getenv("DB_CONN_MAX_AGE", "600")),
            # Supabase requires TLS.
            ssl_require=env_bool("DB_SSL_REQUIRE", True),
        )
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "api.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
     "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

# ---------------------------------------------------------------- DRF

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_RENDERER_CLASSES": ("rest_framework.renderers.JSONRenderer",)
    if not DEBUG
    else (
        "rest_framework.renderers.JSONRenderer",
        "rest_framework.renderers.BrowsableAPIRenderer",
    ),
    # The Swift client decodes Decimal from a JSON number; a string would fail.
    "COERCE_DECIMAL_TO_STRING": False,
    # ISO-8601 without fractional seconds. Foundation's ISO8601DateFormatter
    # is fussy about microsecond precision, so we emit whole seconds.
    "DATETIME_FORMAT": "%Y-%m-%dT%H:%M:%SZ",
    "DATETIME_INPUT_FORMATS": ["iso-8601"],
    "EXCEPTION_HANDLER": "api.exceptions.serving_exception_handler",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.getenv("JWT_ACCESS_MINUTES", "60"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=int(os.getenv("JWT_REFRESH_DAYS", "30"))),
    "ROTATE_REFRESH_TOKENS": False,
    "AUTH_HEADER_TYPES": ("Bearer",),
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "user_id",
}

CORS_ALLOW_ALL_ORIGINS = DEBUG
CORS_ALLOWED_ORIGINS = env_list("CORS_ALLOWED_ORIGINS")

# ---------------------------------------------------------------- Serving

# Serving's revenue, mirrored by PricingEngine.swift on the client: a flat
# service fee the player pays on top of the order, and a commission taken out
# of the stringer's payout.
PLAYER_SERVICE_FEE = os.getenv("PLAYER_SERVICE_FEE", "1.99")
STRINGER_COMMISSION_RATE = os.getenv("STRINGER_COMMISSION_RATE", "0.08")
DEFAULT_TAX_RATE = os.getenv("DEFAULT_TAX_RATE", "0.0913")

# Stripe. Leave the secret key unset in development: payments are then
# simulated so the accept-pickup step still confirms the order.
STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")

# SMS. Without Twilio credentials, verification codes are written to the
# console and logged on the response in DEBUG so you can sign up locally.
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM_NUMBER = os.getenv("TWILIO_FROM_NUMBER", "")
PHONE_CODE_TTL_MINUTES = int(os.getenv("PHONE_CODE_TTL_MINUTES", "10"))
PHONE_CODE_MAX_ATTEMPTS = int(os.getenv("PHONE_CODE_MAX_ATTEMPTS", "5"))

# OAuth
APPLE_BUNDLE_ID = os.getenv("APPLE_BUNDLE_ID", "app.serving.Serving")
GOOGLE_CLIENT_IDS = env_list("GOOGLE_CLIENT_IDS")
# Skips cryptographic verification of OAuth identity tokens. Development only.
OAUTH_ALLOW_UNVERIFIED_TOKENS = env_bool("OAUTH_ALLOW_UNVERIFIED_TOKENS", DEBUG)

# APNs
APNS_KEY_ID = os.getenv("APNS_KEY_ID", "")
APNS_TEAM_ID = os.getenv("APNS_TEAM_ID", "")
APNS_KEY_PATH = os.getenv("APNS_KEY_PATH", "")
APNS_TOPIC = os.getenv("APNS_TOPIC", APPLE_BUNDLE_ID)
APNS_USE_SANDBOX = env_bool("APNS_USE_SANDBOX", True)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "api": {"handlers": ["console"], "level": "DEBUG" if DEBUG else "INFO", "propagate": False},
    },
}
