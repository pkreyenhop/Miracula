BUILD_DIR ?= build

.PHONY: all build run generate test vet race verify smoke clean

all: build

build:
	go build -o $(BUILD_DIR)/mira ./cmd/mira

run: build
	./$(BUILD_DIR)/mira

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
	go build -o $(BUILD_DIR)/mira ./cmd/mira

smoke:
	go test ./...

clean:
	rm -rf $(BUILD_DIR)
