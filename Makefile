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

.PHONY: build push deploy migrate seed ship clean version apply roll check

version:
	@echo $(VERSION)

# ─── build ────────────────────────────────────────────────
build:
	$(MAKE) -C backend build
	$(MAKE) -C flutter_app build
	$(MAKE) -C website build VERSION=$(VERSION)

# ─── push ─────────────────────────────────────────────────
push:
	$(MAKE) -C backend push
	$(MAKE) -C flutter_app push
	$(MAKE) -C website push VERSION=$(VERSION)

# ─── deploy ───────────────────────────────────────────────
deploy:
	@echo "Updating image tags and APP_VERSION to $(VERSION)..."
	@sed -i 's|image: $(REPO)/sophistry-worker:.*|image: $(REPO)/sophistry-worker:$(VERSION)|' deploy/k8s/05-api.yaml deploy/k8s/06-worker.yaml deploy/k8s/07-migrate-job.yaml
	@sed -i 's|image: $(REPO)/sophistry-web:.*|image: $(REPO)/sophistry-web:$(VERSION)|' deploy/k8s/05-web.yaml
	@sed -i 's|image: $(REPO)/sophistry-com:.*|image: $(REPO)/sophistry-com:$(VERSION)|' deploy/k8s/09-sophistry-com.yaml
	@sed -i '/name: APP_VERSION/{n;s|value: ".*"|value: "$(VERSION)"|}' deploy/k8s/05-api.yaml deploy/k8s/06-worker.yaml
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

# ─── ship (the full monty, no migrate) ───────────────────
ship: build push deploy
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
	sed -i "s|image: $(REPO)/sophistry-com:.*|image: $(REPO)/sophistry-com:$$NEXT|" deploy/k8s/09-sophistry-com.yaml; \
	sed -i "/name: APP_VERSION/{n;s|value: \".*\"|value: \"$$NEXT\"|}" deploy/k8s/05-api.yaml deploy/k8s/06-worker.yaml; \
	git add -A; \
	git commit -m "$$NEXT"; \
	git tag "$$NEXT"; \
	git push && git push --tags; \
	echo "🏷️  Tagged $$NEXT"

# ─── release (tag + ship) ────────────────────────────────
release: tag ship
	@echo "🚀 Released $(VERSION)!"

# ─── check (show running images) ──────────────────────────
check:
	@echo "── Pods & images in $(NS) ──"
	@kubectl get pods -n $(NS) -o custom-columns=\
'POD:.metadata.name,STATUS:.status.phase,IMAGE:.status.containerStatuses[*].image' \
	--no-headers 2>/dev/null | column -t
	@echo ""
	@echo "── Unique images ──"
	@kubectl get pods -n $(NS) -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.image}{"\n"}{end}{end}' \
	2>/dev/null | sort -u

# ─── clean ────────────────────────────────────────────────
clean:
	$(MAKE) -C backend clean
	$(MAKE) -C anaflutter_app clean

# ─── secrets (never checked in, generated from env) ───────
secret:
	@[ -n "$$POSTGRES_PASSWORD" ] || (echo "ERROR: POSTGRES_PASSWORD not set" && exit 1)
	kubectl create secret generic sophistry-db-secret \
		--namespace $(NS) \
		--from-literal=username=sophistry \
		--from-literal=password="$$POSTGRES_PASSWORD" \
		--type=kubernetes.io/basic-auth \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl label secret sophistry-db-secret -n $(NS) cnpg.io/reload=true --overwrite

# ─── apply ────────────────────────────────────────────────
apply:
	kubectl apply -f deploy/k8s/05-api.yaml
	kubectl apply -f deploy/k8s/05-web.yaml
	kubectl apply -f deploy/k8s/06-worker.yaml
	kubectl apply -f deploy/k8s/08-ingress.yaml
	kubectl apply -f deploy/k8s/09-sophistry-com.yaml
	kubectl rollout restart deploy -n sophistry
# ─── roll ────────────────────────────────────────────────
roll: release apply 
