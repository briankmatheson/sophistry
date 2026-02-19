from django.contrib import admin
from django.urls import path, include
from evals.views import home
from sophistry.views_session import reset_session

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/session/reset/", reset_session, name="session-reset"),
    path("", home, name="home"),
    path("", include("evals.urls")),
]
