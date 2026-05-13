#!/usr/bin/env bash
# ==========================================================================
# Cleanup de chunks Vite antigos em public/vite/assets/
#
# Mantem:
#   - Arquivos referenciados pelo manifest atual (build vigente)
#   - Arquivos modificados nas ultimas 24h (margem para deploys seguidos)
#
# Remove:
#   - Todo o resto (chunks orfaos de builds anteriores)
#
# Safe-by-default: se manifest.json nao existir ou jq falhar, NAO apaga nada.
#
# Uso:
#   bash scripts/cleanup-vite-assets.sh [ASSETS_DIR]
#
# ASSETS_DIR default: /home/chatwoot/chatwoot/public/vite/assets
# ==========================================================================

set -euo pipefail

ASSETS_DIR="${1:-/home/chatwoot/chatwoot/public/vite/assets}"
MANIFEST="$(dirname "$ASSETS_DIR")/.vite/manifest.json"

log() { echo "[cleanup-vite] $1"; }
warn() { echo "[cleanup-vite] WARN: $1"; }

# Safety 1: diretorio de assets precisa existir
if [[ ! -d "$ASSETS_DIR" ]]; then
  warn "ASSETS_DIR nao encontrado: $ASSETS_DIR — skip"
  exit 0
fi

# Safety 2: manifest precisa existir
if [[ ! -f "$MANIFEST" ]]; then
  warn "manifest.json nao encontrado em $MANIFEST — skip (nao apaga nada)"
  exit 0
fi

# Safety 3: jq precisa estar disponivel
if ! command -v jq >/dev/null 2>&1; then
  warn "jq nao instalado — skip"
  exit 0
fi

# 1. Coletar arquivos referenciados pelo manifest atual.
#    Estrutura tipica: { "src/entry.js": { "file": "assets/x.js", "css": ["assets/y.css"] } }
#    Query recursiva pega .file e .css de qualquer nivel.
KEEP_LIST=$(mktemp)
trap 'rm -f "$KEEP_LIST"' EXIT

if ! jq -r '.. | .file? // empty, .css? // empty | if type == "array" then .[] else . end' \
       "$MANIFEST" 2>/dev/null | sort -u > "$KEEP_LIST"; then
  warn "jq falhou ao parsear manifest — skip (nao apaga nada)"
  exit 0
fi

# Safety 4: keep_list vazia significa manifest mal formado — abortar
if [[ ! -s "$KEEP_LIST" ]]; then
  warn "keep_list vazia (manifest sem .file/.css?) — skip"
  exit 0
fi

# Reduz "assets/foo.js" -> "foo.js" para comparacao por basename
KEEP_BASENAMES=$(mktemp)
trap 'rm -f "$KEEP_LIST" "$KEEP_BASENAMES"' EXIT
awk -F/ '{print $NF}' "$KEEP_LIST" | sort -u > "$KEEP_BASENAMES"

KEPT=0
REMOVED=0
FREED_BYTES=0

# 2. Varrer assets/ — manter se: (a) basename no manifest OU (b) mtime < 24h
while IFS= read -r -d '' f; do
  bn=$(basename "$f")

  if grep -qFx "$bn" "$KEEP_BASENAMES"; then
    KEPT=$((KEPT + 1))
    continue
  fi

  # find -mmin -1440 retorna o proprio arquivo se modificado nas ultimas 24h
  if [[ -n "$(find "$f" -maxdepth 0 -mmin -1440 -print 2>/dev/null)" ]]; then
    KEPT=$((KEPT + 1))
    continue
  fi

  size=$(stat -c %s "$f" 2>/dev/null || echo 0)
  if rm -f "$f"; then
    REMOVED=$((REMOVED + 1))
    FREED_BYTES=$((FREED_BYTES + size))
  fi
done < <(find "$ASSETS_DIR" -maxdepth 1 -type f -print0)

FREED_MB=$((FREED_BYTES / 1024 / 1024))
log "public/vite/assets: kept $KEPT files, removed $REMOVED files (~${FREED_MB} MB freed)"
