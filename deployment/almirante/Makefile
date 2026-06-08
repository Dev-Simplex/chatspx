GO ?= go
BIN := bin

.PHONY: build test race vet lint demo agent-linux clean

build:
	CGO_ENABLED=0 $(GO) build -o $(BIN)/ ./cmd/...

test:
	$(GO) test ./...

race:
	$(GO) test -race ./...

vet:
	$(GO) vet ./...

# Sobe o MCP em modo mock (sem SSH, sem rede) — para demo/dev.
demo: build
	ALMIRANTE_MOCK=1 $(BIN)/almirante-mcp

# Cross-compile do agente para as VMs (binario unico estatico).
agent-linux:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -o $(BIN)/almiranted-linux-amd64 ./cmd/almiranted

clean:
	rm -rf $(BIN)
