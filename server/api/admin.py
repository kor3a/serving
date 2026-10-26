from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import (
    Business,
    DeviceToken,
    OpenHours,
    Order,
    OrderRacquet,
    Payout,
    PhoneVerification,
    PlayerRacquet,
    StringingService,
    StringProduct,
    User,
)


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ["-created_at"]
    list_display = ["email", "account_type", "display_name", "phone_verified", "setup_complete"]
    list_filter = ["account_type", "setup_complete", "phone_verified", "is_staff"]
    search_fields = ["email", "display_name", "phone"]
    readonly_fields = ["id", "created_at", "updated_at"]

    fieldsets = (
        (None, {"fields": ("id", "email", "password")}),
        ("Profile", {"fields": ("account_type", "display_name", "owner_name", "phone",
                                "phone_verified", "avatar_url", "business", "setup_complete")}),
        ("OAuth", {"fields": ("apple_subject", "google_subject")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups",
                                    "user_permissions")}),
        ("Dates", {"fields": ("last_login", "created_at", "updated_at")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("email", "password1", "password2")}),
    )


class OpenHoursInline(admin.TabularInline):
    model = OpenHours
    extra = 0


class ServiceInline(admin.TabularInline):
    model = StringingService
    extra = 0


class ProductInline(admin.TabularInline):
    model = StringProduct
    extra = 0


@admin.register(Business)
class BusinessAdmin(admin.ModelAdmin):
    list_display = ["name", "city", "is_claimed", "payout_status", "rating"]
    list_filter = ["is_claimed", "location_kind", "payout_status"]
    search_fields = ["name", "city", "phone"]
    inlines = [ServiceInline, ProductInline, OpenHoursInline]


class RacquetInline(admin.TabularInline):
    model = OrderRacquet
    extra = 0


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ["order_number", "business_name", "player_name", "status",
                    "payment_state", "drop_off_date", "confirmed_pick_up_date"]
    list_filter = ["status", "payment_state", "payment_method"]
    search_fields = ["order_number", "business_name", "player_name"]
    readonly_fields = ["id", "created_at", "updated_at"]
    inlines = [RacquetInline]


@admin.register(PlayerRacquet)
class PlayerRacquetAdmin(admin.ModelAdmin):
    list_display = ["__str__", "player", "sport", "color", "main_tension", "cross_tension"]
    list_filter = ["sport"]
    search_fields = ["manufacturer", "model", "player__email"]


admin.site.register([DeviceToken, PhoneVerification, Payout])
admin.site.site_header = "Serving"
admin.site.site_title = "Serving"
