from rest_framework import serializers
from .models import TestCase, Run, Result

class TestCaseSerializer(serializers.ModelSerializer):
    class Meta:
        model = TestCase
        fields = ["id","slug","title","prompt","expected","tags","is_active","created_at"]

class RunSerializer(serializers.ModelSerializer):
    class Meta:
        model = Run
        fields = ["run_uuid","name","notes","models_requested","filters","status","created_at","total","completed","failed"]

class ResultSerializer(serializers.ModelSerializer):
    testcase_slug = serializers.CharField(source="testcase.slug", read_only=True)
    class Meta:
        model = Result
        fields = ["id","run_uuid","provider","model","testcase_slug","status","score","latency_ms","output_text","error","created_at"]
