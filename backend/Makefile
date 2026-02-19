# Sophistry Backend Makefile
REPO    ?= briankmatheson
IMAGE   := $(REPO)/sophistry-worker
VERSION ?= dev

.PHONY: build push run shell test migrate clean

build:
	docker build --no-cache -t $(IMAGE):$(VERSION) .

push:
	docker push $(IMAGE):$(VERSION)

# ─── local dev ────────────────────────────────────────────
run:
	docker run --rm -p 8000:8000 --env-file .env $(IMAGE):$(VERSION)

shell:
	docker run --rm -it --env-file .env $(IMAGE):$(VERSION) bash

# ─── verify image contents ────────────────────────────────
check:
	@echo "--- middleware import ---"
	@docker run --rm $(IMAGE):$(VERSION) grep "from eval" /app/sophistry/middleware.py
	@echo "--- views provider ---"
	@docker run --rm $(IMAGE):$(VERSION) grep "provider" /app/evals/views.py | head -5
	@echo "--- evals files ---"
	@docker run --rm $(IMAGE):$(VERSION) ls -la /app/evals/

# ─── migrations (local docker, needs DB) ──────────────────
makemigrations:
	docker run --rm --env-file .env $(IMAGE):$(VERSION) python manage.py makemigrations

showmigrations:
	docker run --rm --env-file .env $(IMAGE):$(VERSION) python manage.py showmigrations evals

# ─── clean ────────────────────────────────────────────────
clean:
	docker rmi $(IMAGE):$(VERSION) 2>/dev/null || true
	find . -name '*.pyc' -delete
	find . -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name '*~' -delete
