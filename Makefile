# Sophistry — top-level Makefile
# Usage:
#   make build          — build backend + frontend images
#   make push           — push both images
#   make deploy         — rollout restart in k8s
#   make ship           — build, push, migrate, deploy (the works)
#   make seed           — seed test cases

REPO     := briankmatheson
NS       := sophistry
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

export VERSION REPO NS

.PHONY: build push deploy migrate seed ship clean version

version:
	@echo $(VERSION)

# ─── build ────────────────────────────────────────────────
build:
	$(MAKE) -C backend build
	$(MAKE) -C flutter_app build

# ─── push ─────────────────────────────────────────────────
push:
	$(MAKE) -C backend push
	$(MAKE) -C flutter_app push

# ─── deploy ───────────────────────────────────────────────
deploy:
	@echo "Updating image tags to $(VERSION)..."
	@sed -i 's|image: $(REPO)/sophistry-worker:.*|image: $(REPO)/sophistry-worker:$(VERSION)|' deploy/k8s/05-api.yaml deploy/k8s/06-worker.yaml deploy/k8s/07-migrate-job.yaml
	@sed -i 's|image: $(REPO)/sophistry-web:.*|image: $(REPO)/sophistry-web:$(VERSION)|' deploy/k8s/05-web.yaml
	kubectl rollout restart -n $(NS) deploy

migrate:
	kubectl delete job -n $(NS) sophistry-migrate --ignore-not-found
	@sed -i 's|image: $(REPO)/sophistry-worker:.*|image: $(REPO)/sophistry-worker:$(VERSION)|' deploy/k8s/07-migrate-job.yaml
	kubectl create -f deploy/k8s/07-migrate-job.yaml
	@echo "Waiting for migration..."
	kubectl wait --for=condition=complete -n $(NS) job/sophistry-migrate --timeout=60s
	kubectl logs -n $(NS) job/sophistry-migrate

seed:
	bash deploy/k8s/seed.sh

# ─── ship (the full monty) ────────────────────────────────
ship: build push migrate deploy
	@echo "🚀 Sophistry $(VERSION) shipped!"

# ─── logs ─────────────────────────────────────────────────
logs-api:
	kubectl logs -n $(NS) deploy/sophistry-api --tail=50 -f

logs-worker:
	kubectl logs -n $(NS) deploy/sophistry-worker --tail=50 -f

status:
	kubectl get pods -n $(NS)

# ─── tag (auto-bump patch, update manifests, commit, push) ─
LATEST_TAG := $(shell git tag --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$$' | head -1)

tag:
	@if [ -z "$(LATEST_TAG)" ]; then \
		NEXT=0.1.0; \
	else \
		MAJOR=$$(echo $(LATEST_TAG) | cut -d. -f1); \
		MINOR=$$(echo $(LATEST_TAG) | cut -d. -f2); \
		PATCH=$$(echo $(LATEST_TAG) | cut -d. -f3); \
		NEXT=$$MAJOR.$$MINOR.$$((PATCH + 1)); \
	fi; \
	echo "$(LATEST_TAG) → $$NEXT"; \
	sed -i "s|image: $(REPO)/sophistry-worker:.*|image: $(REPO)/sophistry-worker:$$NEXT|" deploy/k8s/05-api.yaml deploy/k8s/06-worker.yaml deploy/k8s/07-migrate-job.yaml; \
	sed -i "s|image: $(REPO)/sophistry-web:.*|image: $(REPO)/sophistry-web:$$NEXT|" deploy/k8s/05-web.yaml; \
	git add -A; \
	git commit -m "$$NEXT"; \
	git tag "$$NEXT"; \
	git push && git push --tags; \
	echo "🏷️  Tagged $$NEXT"

# ─── release (tag + ship) ────────────────────────────────
release: tag ship
	@echo "🚀 Released $(VERSION)!"

# ─── clean ────────────────────────────────────────────────
clean:
	$(MAKE) -C backend clean
	$(MAKE) -C flutter_app clean
