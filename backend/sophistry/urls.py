from django.contrib import admin
from django.urls import path, include
from evals.views import home
from sophistry.views_session import reset_session
from evals.views_review import review

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/session/reset/", reset_session, name="session-reset"),
    path("api/mobile/review/", review, name="mobile-review"),
    path("", home, name="home"),
    path("", include("evals.urls")),
]
