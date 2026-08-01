PREFIX ?= /usr/local
DESTDIR ?= /
BUILD_DIR ?= build

.PHONY: all build test race verify install uninstall package smoke clean

all: build

build:
	python3 scripts/package_go.py build --output $(BUILD_DIR)/mira

test:
	go test ./...

race:
	go test -race ./...

verify: clean
	go generate ./...
	git diff --exit-code -- internal/protocol/combinator_generated.go
	go test ./...
	go test -race ./...
	go run ./cmd/checkdag
	python3 tests/test_go_command.py
	python3 tests/test_go_repl.py
	python3 tests/test_go_install.py
	python3 scripts/package_go.py build --output $(BUILD_DIR)/mira
	python3 tests/startup_from_source.py $(BUILD_DIR)/mira

install:
	python3 scripts/package_go.py install --prefix $(PREFIX) --destdir $(DESTDIR)

uninstall:
	python3 scripts/package_go.py uninstall --prefix $(PREFIX) --destdir $(DESTDIR)

package:
	python3 scripts/package_go.py archive --output $(BUILD_DIR)/miracula-darwin-arm64.tar.gz

smoke:
	python3 tests/test_go_install.py

clean:
	python3 scripts/package_go.py clean
