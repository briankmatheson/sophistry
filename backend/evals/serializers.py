from rest_framework import serializers
from .models import TestSet, TestCase, Run, Result

class TestSetSerializer(serializers.ModelSerializer):
    class Meta:
        model = TestSet
        fields = ["id", "name", "description", "is_active", "created_at"]

class TestCaseSerializer(serializers.ModelSerializer):
    test_set_name = serializers.CharField(source="test_set.name", read_only=True, default=None)
    class Meta:
        model = TestCase
        fields = ["id","slug","title","prompt","expected","tags","is_active","test_set","test_set_name","created_at"]

class RunSerializer(serializers.ModelSerializer):
    class Meta:
        model = Run
        fields = ["run_uuid","name","notes","models_requested","filters","status","created_at","total","completed","failed"]

class ResultSerializer(serializers.ModelSerializer):
    testcase_slug = serializers.CharField(source="testcase.slug", read_only=True)
    class Meta:
        model = Result
        fields = ["id","run_uuid","provider","model","testcase_slug","status","score","latency_ms","output_text","error","created_at"]
