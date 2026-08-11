"""URL map.

These paths must match `Routes` in Tensora/Core/Networking/Endpoint.swift.
Django's APPEND_SLASH is on, and the client sends trailing slashes, so keep
them here too.
"""

from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

urlpatterns = [
    path("health/", views.health),

    # Auth
    path("auth/login/", views.login),
    path("auth/signup/", views.signup),
    path("auth/oauth/apple/", views.apple_oauth),
    path("auth/oauth/google/", views.google_oauth),
    path("auth/token/refresh/", TokenRefreshView.as_view()),
    path("auth/logout/", views.logout),
    path("auth/me/", views.me),
    path("auth/phone/request-code/", views.phone_request_code),
    path("auth/phone/verify/", views.phone_verify),
    path("auth/account-setup/", views.account_setup),
    path("notifications/device-tokens/", views.register_device_token),

    # Discovery
    path("businesses/search/", views.business_search),
    path("businesses/<uuid:business_id>/", views.business_detail),

    # Storefront management
    path("businesses/<uuid:business_id>/products/", views.upsert_product),
    path("businesses/<uuid:business_id>/products/<uuid:product_id>/", views.delete_product),
    path("businesses/<uuid:business_id>/services/", views.upsert_service),
    path("businesses/<uuid:business_id>/services/<uuid:service_id>/", views.delete_service),
    path("businesses/<uuid:business_id>/earnings/", views.business_earnings),

    # Orders
    path("orders/", views.orders_collection),
    path("orders/<uuid:order_id>/", views.order_detail),
    path("orders/<uuid:order_id>/acknowledge/", views.acknowledge_order),
    path("orders/<uuid:order_id>/decline/", views.decline_order),
    path("orders/<uuid:order_id>/accept-pickup/", views.accept_pick_up),
    path("orders/<uuid:order_id>/status/", views.update_order_status),
    path("orders/<uuid:order_id>/cancel/", views.cancel_order),
]
