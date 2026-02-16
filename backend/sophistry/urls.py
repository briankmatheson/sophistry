from django.contrib import admin
from django.urls import path, include
from evals.views import home

urlpatterns = [
    path("admin/", admin.site.urls),
    path("", home, name="home"),
    path("", include("evals.urls")),
]
