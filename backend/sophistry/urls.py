from django.urls import path, include
from rest_framework.routers import DefaultRouter
from evals.views import TestCaseViewSet, RunViewSet, ResultViewSet
from evals import views

router = DefaultRouter()
router.register(r"api/testcases", TestCaseViewSet)
router.register(r"api/runs", RunViewSet)
router.register(r"api/results", ResultViewSet)

urlpatterns = [
    path("", include(router.urls)),
    path("api/mobile/run/", views.mobile_create_run),
    path("api/mobile/question", views.mobile_question),
    path("api/mobile/answer/", views.mobile_answer),
    path("api/mobile/testcase/", views.mobile_create_testcase),
]
