PREFIX ?= /usr/local
DESTDIR ?= /
BUILD_DIR ?= build

.PHONY: all build generate test vet race verify install uninstall package smoke clean

all: build

build:
	go run ./internal/cmd/package build --output $(BUILD_DIR)/mira

generate:
	go generate ./...

test:
	go test ./...

vet:
	go vet ./...

race:
	go test -race ./...

verify: clean
	mkdir -p $(BUILD_DIR)/.generated
	go run ./internal/cmd/gencombinators -input internal/protocol/combinators.json -output $(BUILD_DIR)/.generated/combinator_generated.go
	cmp internal/protocol/combinator_generated.go $(BUILD_DIR)/.generated/combinator_generated.go
	go vet ./...
	go test ./...
	go test -race ./...
	go run ./internal/cmd/checkdag
	go run ./internal/cmd/package build --output $(BUILD_DIR)/mira

install:
	go run ./internal/cmd/package install --prefix $(PREFIX) --destdir $(DESTDIR)

uninstall:
	go run ./internal/cmd/package uninstall --prefix $(PREFIX) --destdir $(DESTDIR)

package:
	go run ./internal/cmd/package archive --output $(BUILD_DIR)/miracula-darwin-arm64.tar.gz

smoke:
	go test ./...

clean:
	go run ./internal/cmd/package clean
