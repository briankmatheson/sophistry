REPO    ?= briankmatheson
IMAGE   := $(REPO)/sophistry-com
VERSION ?= latest

build:
	docker build -t $(IMAGE):$(VERSION) .

push:
	docker push $(IMAGE):$(VERSION)

run:
	docker run --rm -p 8080:80 $(IMAGE):$(VERSION)

.PHONY: build push run
