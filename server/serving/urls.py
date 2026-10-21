from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    # The iOS client's AppConfig.apiBaseURL includes this version prefix.
    path("v1/", include("api.urls")),
]
