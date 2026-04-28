# PMET monorepo top-level Makefile
# Thin entry point — delegates to per-module scripts.

.PHONY: help build build-core demo demo-indexing demo-pairing baseline clean

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD := $(ROOT)/build

help:
	@echo "PMET monorepo targets:"
	@echo "  build        - build all C/C++ engines into ./build/"
	@echo "  demo         - run demo indexing + pairing against data/"
	@echo "  baseline     - capture fingerprints to tests/baseline/fingerprints.txt"
	@echo "  clean        - remove ./build/"

build: build-core

build-core:
	@bash core/scripts/build_all.sh all

demo: demo-indexing demo-pairing

demo-indexing:
	@bash core/scripts/run_indexing.sh -v c

demo-pairing:
	@bash core/scripts/run_pairing.sh

baseline:
	@bash tests/baseline/capture.sh > tests/baseline/fingerprints.txt
	@echo "wrote tests/baseline/fingerprints.txt"

clean:
	@rm -rf $(BUILD)
