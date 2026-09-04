#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  Prepara uma máquina para usar o /promover-pr
#
#      bash scripts/ops/setup-promover-pr.sh
#
#  Não altera nada sem avisar: primeiro diagnostica os 4 requisitos, depois
#  oferece resolver o que dá para resolver sozinho. O que exige decisão humana
#  (autenticar no GitHub, receber a chave de produção) ele explica e para.
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

V='\033[32m'; A='\033[33m'; R='\033[31m'; C='\033[36m'; N='\033[0m'
ok=0; falta=0
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PEM="${TOZI_PEM:-$raiz/simplex.linux.pem}"

titulo() { printf "\n${C}━━━ %s${N}\n" "$1"; }
bom()    { printf "  ${V}✓${N} %s\n" "$1"; ok=$((ok+1)); }
ruim()   { printf "  ${R}✗${N} %s\n" "$1"; falta=$((falta+1)); }
dica()   { printf "      ${A}→ %s${N}\n" "$1"; }

printf "${C}Preparando esta máquina para o /promover-pr${N}\n"
printf "  repo: %s\n" "$raiz"

# ─── 1. git e o repositório ────────────────────────────────────────────────
titulo "1. Repositório"
if git -C "$raiz" rev-parse --git-dir >/dev/null 2>&1; then
  bom "repositório git encontrado"
  atual=$(git -C "$raiz" rev-parse --abbrev-ref HEAD)
  printf "      branch atual: %s\n" "$atual"
  if git -C "$raiz" fetch origin --prune -q 2>/dev/null; then
    bom "consegue falar com o origin (fetch funcionou)"
  else
    ruim "não consegue fazer fetch do origin"
    dica "confira a credencial do git para github.com/Dev-Simplex/chatspx"
  fi
else
  ruim "isto não é um repositório git"
  dica "rode o script de dentro do checkout do chatspx"
fi

# ─── 2. o gh, que é como o comando lê e mergeia PR ─────────────────────────
titulo "2. GitHub CLI (gh)"
if command -v gh >/dev/null 2>&1; then
  bom "gh instalado ($(gh --version 2>/dev/null | head -1))"
  if gh auth status >/dev/null 2>&1; then
    quem=$(gh api user --jq .login 2>/dev/null || echo "?")
    bom "autenticado como: $quem"
    # Ler um PR prova acesso de leitura; o merge só se prova mergeando, então
    # aqui checamos o papel do usuário no repositório.
    papel=$(gh api "repos/Dev-Simplex/chatspx" --jq .permissions 2>/dev/null || echo "")
    if echo "$papel" | grep -q '"push":true'; then
      bom "tem permissão de escrita no repositório (pode mergear)"
    else
      ruim "sem permissão de escrita no Dev-Simplex/chatspx"
      dica "peça ao dono do repo para te dar acesso de write"
    fi
  else
    ruim "gh instalado mas NÃO autenticado"
    dica "rode: gh auth login"
  fi
else
  ruim "gh não instalado"
  dica "Ubuntu/Debian: sudo apt install gh   ·   Mac: brew install gh"
  dica "depois: gh auth login"
fi

# ─── 3. acesso às VMs ──────────────────────────────────────────────────────
titulo "3. Acesso às VMs de produção"
if [ -f "$PEM" ]; then
  perm=$(stat -c "%a" "$PEM" 2>/dev/null || stat -f "%Lp" "$PEM" 2>/dev/null)
  bom "chave encontrada: $PEM"
  if [ "$perm" != "600" ] && [ "$perm" != "400" ]; then
    printf "      ${A}permissão $perm é frouxa; o ssh recusa. Corrigindo...${N}\n"
    chmod 600 "$PEM" && printf "      ${V}corrigido para 600${N}\n"
  fi
  # Uma VM basta para provar que a chave serve. CATATAU é a escolhida por não
  # ser cliente crítico; a Tozi fica de fora porque o IP dela muda no stop/start.
  if timeout 15 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       -i "$PEM" ubuntu@3.85.130.14 true 2>/dev/null; then
    bom "SSH funciona (testado na CATATAU)"
  else
    ruim "a chave existe mas o SSH não conectou"
    dica "confira se seu IP está liberado no security group da AWS"
  fi
else
  ruim "chave de produção não encontrada em $PEM"
  dica "ela NÃO vai no git de propósito (chave privada em repositório é vazamento)"
  dica "peça o simplex.linux.pem ao responsável e salve em $raiz/"
  dica "ou aponte outro caminho: export TOZI_PEM=/caminho/da/chave"
fi

# ─── 4. as peças do próprio comando ────────────────────────────────────────
titulo "4. O comando e o script"
[ -f "$raiz/.claude/commands/promover-pr.md" ] \
  && bom "comando /promover-pr presente" \
  || { ruim "falta .claude/commands/promover-pr.md"; dica "git pull na branch producao"; }

if [ -f "$raiz/scripts/ops/pr-raiox.py" ]; then
  bom "script de raio-X presente"
  if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)" 2>/dev/null; then
    bom "python3 compatível ($(python3 --version 2>&1))"
  else
    ruim "python3 ausente ou anterior ao 3.9"
    dica "o script usa anotações de tipo modernas"
  fi
else
  ruim "falta scripts/ops/pr-raiox.py"
  dica "git pull na branch producao"
fi

# ─── veredito ──────────────────────────────────────────────────────────────
titulo "RESULTADO"
if [ "$falta" -eq 0 ]; then
  printf "  ${V}Tudo pronto (%d verificações).${N}\n\n" "$ok"
  printf "  Experimente com um PR já resolvido, que é o mais didático:\n"
  printf "    ${C}python3 scripts/ops/pr-raiox.py 71${N}\n"
  printf "  E, no Claude Code, o fluxo completo:\n"
  printf "    ${C}/promover-pr <numero>${N}\n\n"
else
  printf "  ${R}%d item(ns) faltando${N} · %d ok\n\n" "$falta" "$ok"
  printf "  Resolva o que está marcado acima e rode este script de novo.\n"
  printf "  Sem o item 3 (SSH) dá para revisar e mergear, mas NÃO dá para\n"
  printf "  deployar — e merge sem deploy não muda nada para o cliente.\n\n"
fi
exit $(( falta > 0 ? 1 : 0 ))
