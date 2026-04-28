# PMET monorepo top-level Makefile
# Thin entry point — delegates to per-module scripts.

.PHONY: help build build-core demo demo-indexing demo-pairing baseline clean \
        up down logs ps rebuild

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD := $(ROOT)/build

help:
	@echo "PMET monorepo targets:"
	@echo ""
	@echo "  Local CLI / dev"
	@echo "    build        - build all C/C++ engines into ./build/"
	@echo "    demo         - run demo indexing + pairing against data/"
	@echo "    baseline     - capture fingerprints to tests/baseline/fingerprints.txt"
	@echo "    clean        - remove ./build/"
	@echo ""
	@echo "  Web app (docker-compose, exposes nginx on http://localhost:5960)"
	@echo "    up           - build + start the full stack (api + worker + frontend + nginx + redis)"
	@echo "    down         - stop the stack"
	@echo "    rebuild      - rebuild images and restart"
	@echo "    logs         - tail logs from all services"
	@echo "    ps           - show service status"
	@echo ""
	@echo "  More deploy targets: cd deploy && make help"

# ---- Local CLI / dev ----

build: build-core

build-core:
	@bash core/scripts/build_all.sh all

demo: demo-indexing demo-pairing

demo-indexing:
	@bash apps/cli/scripts/run_indexing.sh -v c

demo-pairing:
	@bash apps/cli/scripts/run_pairing.sh

baseline:
	@bash tests/baseline/capture.sh > tests/baseline/fingerprints.txt
	@echo "wrote tests/baseline/fingerprints.txt"

clean:
	@rm -rf $(BUILD)

# ---- Web app (proxies into deploy/) ----
# These shortcuts run docker-compose from deploy/ so you don't need to cd.
# All targets accept the same env vars as the underlying compose commands.

up:
	@$(MAKE) -C deploy build
	@$(MAKE) -C deploy start
	@echo ""
	@echo "PMET stack is up — http://localhost:5960"

down:
	@$(MAKE) -C deploy stop

rebuild:
	@$(MAKE) -C deploy rebuild

logs:
	@$(MAKE) -C deploy logs

ps:
	@cd deploy && docker-compose ps
