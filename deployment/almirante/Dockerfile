# ===== build =====
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# o painel (web/) e embutido via go:embed no binario do control
RUN CGO_ENABLED=0 go build -ldflags "-s -w -X main.version=docker" -o /out/almirante-control ./cmd/almirante-control

# ===== runtime =====
FROM alpine:3.20
# git+ssh: o control faz merge (git push) e fala SSH com as VMs
RUN apk add --no-cache git openssh-client ca-certificates tzdata && \
    adduser -D -u 1001 almirante
WORKDIR /app
COPY --from=build /out/almirante-control /usr/local/bin/almirante-control
COPY fleet.json /app/fleet.json
# /app/state (estado/known_hosts) e /app/secrets (creds montadas) graváveis pelo user nao-root
RUN mkdir -p /app/state /app/secrets && chown -R almirante:almirante /app
USER almirante
EXPOSE 4100
# Coolify: defina as ENV abaixo (secrets). Monte um volume em /app/state (estado/known_hosts).
ENV ALMIRANTE_FLEET_FILE=/app/fleet.json \
    ALMIRANTE_CONTROL_PORT=4100 \
    ALMIRANTE_STATE_DIR=/app/state \
    ALMIRANTE_MOCK=1
# ENV a configurar no Coolify (NAO commitar):
#   ALMIRANTE_MOCK=0
#   ALMIRANTE_DEV_TOKENS="tokendev1:joao:operator,tokenadmin:ederson:admin"
#   ALMIRANTE_TRANSPORT_KEY_PATH=/app/secrets/transport_key   (AWS)  -> monte como secret
#   ALMIRANTE_TRANSPORT_PASSWORD=...                          (Proxmox)
#   ALMIRANTE_KNOWN_HOSTS=/app/state/known_hosts             (popular com os 3 tipos: rsa,ecdsa,ed25519)
#   ALMIRANTE_REPO_URL=https://github.com/Dev-Simplex/chatspx.git
#   GIT push: monte ~/.git-credentials (PAT) ou use a deploy key
CMD ["almirante-control"]
