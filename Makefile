PREFIX ?= /usr/local
DESTDIR ?= /
BUILD_DIR ?= build

.PHONY: all build generate test race verify install uninstall package smoke clean

all: build

build:
	python3 tools/package.py build --output $(BUILD_DIR)/mira

generate:
	go generate ./...

test:
	go test ./...

race:
	go test -race ./...

verify: clean
	mkdir -p $(BUILD_DIR)/.generated
	go run ./internal/cmd/gencombinators -input internal/protocol/combinators.json -output $(BUILD_DIR)/.generated/combinator_generated.go
	cmp internal/protocol/combinator_generated.go $(BUILD_DIR)/.generated/combinator_generated.go
	go test ./...
	go test -race ./...
	go run ./internal/cmd/checkdag
	python3 test/integration/test_go_command.py
	python3 test/integration/test_go_repl.py
	python3 test/integration/test_go_install.py
	python3 tools/package.py build --output $(BUILD_DIR)/mira
	python3 test/integration/startup_from_source.py $(BUILD_DIR)/mira

install:
	python3 tools/package.py install --prefix $(PREFIX) --destdir $(DESTDIR)

uninstall:
	python3 tools/package.py uninstall --prefix $(PREFIX) --destdir $(DESTDIR)

package:
	python3 tools/package.py archive --output $(BUILD_DIR)/miracula-darwin-arm64.tar.gz

smoke:
	python3 test/integration/test_go_install.py

clean:
	python3 tools/package.py clean
