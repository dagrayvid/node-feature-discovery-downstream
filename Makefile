.PHONY: all build verify verify-gofmt clean local-image local-image-push test-e2e yamls
.FORCE:

GO_CMD ?= go
GO_FMT ?= gofmt

IMAGE_BUILD_CMD ?= podman build
IMAGE_BUILD_EXTRA_OPTS ?=
IMAGE_PUSH_CMD ?= podman push
CONTAINER_RUN_CMD ?= podman run

MDL ?= mdl

VERSION := $(shell git describe --tags --dirty --always)

IMAGE_REGISTRY ?= quay.io/openshift-psap
IMAGE_TAG_NAME ?= $(VERSION)
IMAGE_EXTRA_TAG_NAMES ?=

IMAGE_NAME := node-feature-discovery
IMAGE_REPO := $(IMAGE_REGISTRY)/$(IMAGE_NAME)
IMAGE_TAG := $(IMAGE_REPO):$(IMAGE_TAG_NAME)
IMAGE_EXTRA_TAGS := $(foreach tag,$(IMAGE_EXTRA_TAG_NAMES),$(IMAGE_REPO):$(tag))

K8S_NAMESPACE ?= openshift-nfd

OPENSHIFT ?= yes

# We use different mount prefix for local and container builds.
# Take CONTAINER_HOSTMOUNT_PREFIX from HOSTMOUNT_PREFIX if only the latter is specified
ifdef HOSTMOUNT_PREFIX
    CONTAINER_HOSTMOUNT_PREFIX := $(HOSTMOUNT_PREFIX)
else
    CONTAINER_HOSTMOUNT_PREFIX := /host-
endif
HOSTMOUNT_PREFIX := /host-

KUBECONFIG ?=
E2E_TEST_CONFIG ?=

LDFLAGS = -ldflags "-s -w -X openshift/node-feature-discovery/pkg/version.version=$(VERSION) -X openshift/node-feature-discovery/source.pathPrefix=$(HOSTMOUNT_PREFIX)"

all: image

grpc-health-probe:
	@CGO_ENABLED=0 $(GO_CMD) install -v -tags netgo -ldflags=-w ./vendor/github.com/grpc-ecosystem/grpc-health-probe/...

build:
	@mkdir -p bin
	$(GO_CMD) build -v -o bin $(LDFLAGS) ./cmd/...

install: grpc-health-probe
	$(GO_CMD) install -v $(LDFLAGS) ./cmd/...

local-image: yamls
	$(IMAGE_BUILD_CMD) --build-arg VERSION=$(VERSION) \
		--build-arg HOSTMOUNT_PREFIX=$(CONTAINER_HOSTMOUNT_PREFIX) \
		-t $(IMAGE_TAG) \
		$(foreach tag,$(IMAGE_EXTRA_TAGS),-t $(tag)) \
		$(IMAGE_BUILD_EXTRA_OPTS) ./

local-image-push:
	$(IMAGE_PUSH_CMD) $(IMAGE_TAG)

yamls:
	@./scripts/kustomize.sh $(K8S_NAMESPACE) $(IMAGE_REPO) $(IMAGE_TAG_NAME)

templates:
	@# Need to prepend each line in the sample config with spaces in order to
	@# fit correctly in the configmap spec.
	@sed s'/^/    /' deployment/components/worker-config/nfd-worker.conf.example > nfd-worker.conf.tmp
	@# The sed magic below replaces the block of text between the lines with start and end markers
	@start=NFD-WORKER-CONF-START-DO-NOT-REMOVE; \
	end=NFD-WORKER-CONF-END-DO-NOT-REMOVE; \
	sed -e "/$$start/,/$$end/{ /$$start/{ p; r nfd-worker.conf.tmp" \
	    -e "}; /$$end/p; d }" -i deployment/helm/node-feature-discovery/values.yaml
	@rm nfd-worker.conf.tmp

mock:
	mockery --name=FeatureSource --dir=source --inpkg --note="Re-generate by running 'make mock'"
	mockery --name=APIHelpers --dir=pkg/apihelper --inpkg --note="Re-generate by running 'make mock'"
	mockery --name=LabelerClient --dir=pkg/labeler --inpkg --note="Re-generate by running 'make mock'"

verify:	verify-gofmt

verify-gofmt:
ifeq (, $(GOFMT_CHECK))
	@echo "verify-gofmt: OK"
else
	@echo "verify-gofmt: ERROR: gofmt failed on the following files:"
	@echo "$(GOFMT_CHECK)"
	@echo ""
	@echo "For details, run: gofmt -d -s $(GOFMT_CHECK)"
	@echo ""
	@exit 1
endif
apigen:
	protoc --go_opt=paths=source_relative --go_out=plugins=grpc:.  pkg/labeler/labeler.proto

gofmt:
	@$(GO_FMT) -w -l $$(find . -name '*.go')

ci-lint:
	golangci-lint run --timeout 7m0s

lint:
	golint -set_exit_status ./...

mdlint:
	find docs/ -path docs/vendor -prune -false -o -name '*.md' | xargs $(MDL) -s docs/mdl-style.rb

test:
	$(GO_CMD) test -x -v ./cmd/... ./pkg/...

e2e-test:
	@if [ -z ${KUBECONFIG} ]; then echo "[ERR] KUBECONFIG missing, must be defined"; exit 1; fi
	$(GO_CMD) test -v ./test/e2e/ -args -nfd.repo=$(IMAGE_REPO) -nfd.tag=$(IMAGE_TAG_NAME) \
	    -kubeconfig=$(KUBECONFIG) -nfd.e2e-config=$(E2E_TEST_CONFIG) -ginkgo.focus="\[kubernetes-sigs\]" \
	    $(if $(OPENSHIFT),-nfd.openshift,)
	$(GO_CMD) test -v ./test/e2e/ -args -nfd.repo=$(IMAGE_REPO) -nfd.tag=$(IMAGE_TAG_NAME)-minimal \
	    -kubeconfig=$(KUBECONFIG) -nfd.e2e-config=$(E2E_TEST_CONFIG) -ginkgo.focus="\[kubernetes-sigs\]" \
	    $(if $(OPENSHIFT),-nfd.openshift,)
