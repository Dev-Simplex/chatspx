#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  git-preso.sh — o que existe SÓ neste notebook e some se ele morrer
# ═══════════════════════════════════════════════════════════════════════
# A regra "toda branch no origin no fim do dia" já está no WORKFLOW-GIT-SPX.md
# desde julho, e mesmo assim trabalho ficou preso: 34 arquivos do FactGuard em
# branch local-only, o STATE.md numa branch de conciliação 732 commits atrás,
# e uma worktree em %TEMP% varrida pelo Windows. Regra que depende de alguém
# lembrar não é o conserto — a pergunta "o que está preso?" precisava de uma
# varredura manual em cinco comandos. Este script é essa varredura.
#
# Uso:  scripts/ops/git-preso.sh
# Roda de qualquer worktree. Só lê — não commita, não empurra, não apaga.
set -uo pipefail
export MSYS_NO_PATHCONV=1

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "fora de um repo git"; exit 1; }
git fetch origin --quiet 2>/dev/null || echo "⚠  fetch falhou — o resultado pode estar velho"

achou=0

echo "══ 1. COMMITS QUE NÃO ESTÃO EM NENHUM REMOTO ══"
for b in $(git for-each-ref --format="%(refname:short)" refs/heads/); do
  n=$(git log --oneline "$b" --not --remotes 2>/dev/null | wc -l)
  if [ "$n" -gt 0 ]; then
    achou=1
    echo "  🔴 $b — $n commit(s)"
    git log --oneline "$b" --not --remotes 2>/dev/null | head -3 | sed "s/^/        /"
    echo "     conserto: git push -u origin $b"
  fi
done
[ "$achou" -eq 0 ] && echo "  ✅ nada preso"

echo
echo "══ 2. STASHES (somem num 'git stash clear') ══"
if [ -n "$(git stash list)" ]; then
  git stash list | sed "s/^/  📦 /"
  echo "     conserto: git branch backup/<nome> stash@{N} && git push origin backup/<nome>"
else
  echo "  ✅ nenhum"
fi

echo
echo "══ 3. WORKTREES ══"
git worktree list --porcelain | grep "^worktree " | sed "s/^worktree //" | while read -r p; do
  nome=$(basename "$p")
  if [ ! -d "$p" ]; then
    echo "  👻 $nome — FANTASMA, o diretório sumiu ($p)"
    echo "     conserto: git worktree remove --force \"$p\" (confira antes se a branch está no origin)"
    continue
  fi
  # Só o %TEMP% do Windows, que o SO varre sozinho. Não vale casar "temp" solto:
  # "templates-oficiais" contém "temp" e virava alarme falso.
  case "$p" in
    */AppData/Local/Temp/*|/tmp/*) echo "  ⚠  $nome — vive no temporário do sistema; o Windows apaga sem avisar" ;;
  esac
  sujo=$(git -C "$p" status --porcelain 2>/dev/null | wc -l)
  [ "$sujo" -gt 0 ] && echo "  📝 $nome — $sujo arquivo(s) sem commit"
  # Mede contra o upstream da PRÓPRIA branch. Comparar tudo com a homologação
  # acusaria worktree de cliente, que vive em branch de produção de propósito.
  br=$(git -C "$p" branch --show-current 2>/dev/null)
  if [ -n "$br" ]; then
    up=$(git -C "$p" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    if [ -n "$up" ]; then
      atras=$(git -C "$p" rev-list --count "HEAD..$up" 2>/dev/null || echo 0)
      [ "$atras" -gt 50 ] && echo "  🕰  $nome [$br] — $atras commits atrás de $up; o checkout está lendo código velho"
    else
      echo "  ❓ $nome [$br] — sem upstream; ninguém sabe se está em dia"
    fi
  fi
done

echo
echo "── o que este script NÃO vê ──"
echo "   arquivo que nunca entrou no git e está fora do repo (Downloads, /tmp das VMs),"
echo "   e trabalho que só existe no disco de uma VM. Para VM: git -C <repo> status."
