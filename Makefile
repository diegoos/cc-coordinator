# Builds the hook for every platform into scripts/bin.
# Run make install once. It needs rustup and zig.

BIN_DIR := scripts/bin
TARGET_DIR := hook/target

# name:target:extension
PLATFORMS := \
	macos-arm64:aarch64-apple-darwin: \
	macos-x64:x86_64-apple-darwin: \
	linux-arm64:aarch64-unknown-linux-musl: \
	linux-x64:x86_64-unknown-linux-musl: \
	windows-arm64:aarch64-pc-windows-gnullvm:.exe \
	windows-x64:x86_64-pc-windows-gnu:.exe

TARGETS := $(foreach p,$(PLATFORMS),$(word 2,$(subst :, ,$(p))))

.DEFAULT_GOAL := all

.PHONY: install all test clean

install:
	@command -v zig >/dev/null || { echo "zig not found: install it first (for example, brew install zig)" >&2; exit 1; }
	rustup target add $(TARGETS)
	cargo install --locked cargo-zigbuild

all:
	@set -e; for p in $(PLATFORMS); do \
		name=$${p%%:*}; rest=$${p#*:}; target=$${rest%%:*}; ext=$${rest#*:}; \
		(cd hook && cargo zigbuild --release --target $$target); \
		cp $(TARGET_DIR)/$$target/release/coordinator-hook$$ext $(BIN_DIR)/hook-$$name$$ext; \
	done
	$(MAKE) test

test:
	cd hook && cargo test && cargo build
	COORDINATOR_HOOK_BIN=$(CURDIR)/hook/target/debug/coordinator-hook bash tests/coordinator-hook.test.sh
	bash tests/coordinator-wrapper.test.sh

clean:
	cd hook && cargo clean
