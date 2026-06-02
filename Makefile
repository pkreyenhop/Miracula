.PHONY: all test test-mira check check-headers tools clean cleanup install \
        zig-build check-migration warning-audit

all:
	zig build

test:
	zig build test

test-mira:
	zig build test-mira

check:
	zig build check

check-headers:
	zig build check-headers

tools:
	zig build tools

install:
	zig build install

clean cleanup:
	zig build clean

zig-build check-migration:
	zig build check-migration

warning-audit:
	zig build check
