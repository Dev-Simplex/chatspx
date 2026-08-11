#!/usr/bin/env bash
# Cria uma frente de trabalho paralela, com a base certa.
#
# Por que existe: worktree criada à mão (ou pelo harness do Orca) costuma nascer
# de `master`, que é o UPSTREAM do Chatwoot — 1.300+ commits atrás, sem Captain V2
# e sem nada do SPX. Isso já queimou três sessões: a BigStore de julho parou no
# "1.175 commits atrás" e duas sessões de 02/08 nasceram na base errada.
#
# A worktree criada aqui aparece sozinha no painel do Orca — ele descobre
# worktrees que não criou. Então NÃO deixe a sessão criar outra: duas entradas
# para a mesma frente é como se apaga a worktree que está em uso.
#
# Uso:  bash scripts/ops/nova-frente.sh <nome>
#       bash scripts/ops/nova-frente.sh --lista
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="origin/homologacao"
DEST_DIR="$(dirname "$REPO")/chatspx-frentes"

if [ "${1:-}" = "--lista" ]; then
  git -C "$REPO" worktree list
  exit 0
fi

NOME="${1:-}"
if [ -z "$NOME" ]; then
  echo "uso: bash scripts/ops/nova-frente.sh <nome>   (ex: tozi-ig)" >&2
  exit 1
fi
case "$NOME" in
  */*|*' '*) echo "nome sem barra e sem espaço, por favor." >&2; exit 1 ;;
esac

BRANCH="spx/$NOME"
DEST="$DEST_DIR/$NOME"

git -C "$REPO" fetch origin --quiet

if git -C "$REPO" worktree list --porcelain | grep -qi "^worktree .*[/\\]$NOME\$"; then
  echo "⚠  Já existe worktree para '$NOME'. Use a que existe — duplicar é o que apaga trabalho." >&2
  git -C "$REPO" worktree list | grep -i "$NOME" >&2 || true
  exit 1
fi
if git -C "$REPO" rev-parse --verify --quiet "$BRANCH" >/dev/null; then
  echo "⚠  A branch '$BRANCH' já existe. Anexe a worktree nela em vez de criar outra:" >&2
  echo "   git -C '$REPO' worktree add '$DEST' '$BRANCH'" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
git -C "$REPO" worktree add "$DEST" -b "$BRANCH" "$BASE"

echo
echo "✅ frente '$NOME' criada"
echo "   pasta  : $DEST"
echo "   branch : $BRANCH"
echo "   base   : $BASE ($(git -C "$REPO" rev-parse --short "$BASE"))"
echo
echo "Abra a sessão do Orca APONTANDO para essa pasta — não deixe ele criar outra."
echo "E pushe assim que houver o primeiro commit: worktree deletada leva junto o que"
echo "não foi publicado."
