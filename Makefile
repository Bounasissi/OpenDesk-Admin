# OpenDesk-Admin — canonical development gate
# Plan 01 (Repository Baseline): make verify is the single local pre-merge gate.
SWIFT ?= swift
SCRATCH_LINT := .build-lint

.PHONY: bootstrap build test lint secret-scan license-check verify clean

bootstrap: ## Resolve packages and prepare the environment (no external dependencies).
	$(SWIFT) package resolve >/dev/null 2>&1 || true
	@echo "bootstrap: ok (zero external SwiftPM dependencies)"

build:
	$(SWIFT) build --build-tests

test:
	$(SWIFT) test

lint: ## Full compile treating warnings as errors (isolated scratch dir).
	@rm -rf $(SCRATCH_LINT)
	$(SWIFT) build --build-tests --scratch-path $(SCRATCH_LINT) -Xswiftc -warnings-as-errors
	@rm -rf $(SCRATCH_LINT)

secret-scan:
	./scripts/secret-scan.sh

license-check:
	./scripts/license-check.sh

verify: build lint test secret-scan license-check ## Single local pre-merge gate.

clean:
	rm -rf .build .build-lint
