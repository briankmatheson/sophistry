# Sophistry Flutter App Makefile
REPO    ?= briankmatheson
IMAGE   := $(REPO)/sophistry-web
VERSION ?= dev

BACKEND_URL ?= https://app.sophistry.online

.PHONY: build push run-web apk clean

# ─── docker (web) ─────────────────────────────────────────
build:
	docker build --no-cache -t $(IMAGE):$(VERSION) .

push:
	docker push $(IMAGE):$(VERSION)

# ─── local flutter dev ────────────────────────────────────
run-web:
	flutter run -d chrome --dart-define=BACKEND_BASE_URL=$(BACKEND_URL)

run-android:
	flutter run --dart-define=BACKEND_BASE_URL=$(BACKEND_URL)

# ─── APK build ────────────────────────────────────────────
apk:
	flutter build apk --split-per-abi --dart-define=BACKEND_BASE_URL=$(BACKEND_URL)
	@echo "APKs in build/app/outputs/flutter-apk/"
	@ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true

apk-install:
	adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# ─── web build (no docker) ────────────────────────────────
web:
	flutter build web --dart-define=BACKEND_BASE_URL=$(BACKEND_URL)

# ─── deps ─────────────────────────────────────────────────
deps:
	flutter pub get

analyze:
	flutter analyze

test:
	flutter test

# ─── clean ────────────────────────────────────────────────
clean:
	flutter clean
	docker rmi $(IMAGE):$(VERSION) 2>/dev/null || true
