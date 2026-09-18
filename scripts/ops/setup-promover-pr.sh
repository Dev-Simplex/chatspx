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
# Preferencia: $TOZI_PEM, depois a copia PRIVADA em ~/.ssh, depois o arquivo do
# repo. O OpenSSH recusa chave com bit de grupo quando o dono e quem roda, e a do
# repo e 640 compartilhada por grupo — serve para quem NAO e dono dela, e falha
# para quem e. Cada usuario com a sua copia 600 resolve os dois casos sem que
# apertar o arquivo compartilhado tire o acesso do outro.
if [ -n "${TOZI_PEM:-}" ]; then
  PEM="$TOZI_PEM"
elif [ -f "$HOME/.ssh/simplex.linux.pem" ]; then
  PEM="$HOME/.ssh/simplex.linux.pem"
else
  PEM="$raiz/simplex.linux.pem"
fi

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
  dono=$(stat -c "%U" "$PEM" 2>/dev/null || stat -f "%Su" "$PEM" 2>/dev/null)
  bom "chave encontrada: $PEM (modo $perm, dono $dono)"

  # Quem decide se a chave presta é o TESTE DE SSH, não o número da permissão.
  # Mas a permissão é a causa mais comum de falha, e o erro do OpenSSH some no
  # 2>/dev/null — então quando o teste falha nós olhamos a permissão para
  # explicar, em vez de mandar a pessoa caçar security group à toa.
  #
  # A regra do OpenSSH: ele recusa chave privada com bit de grupo ou de outros
  # QUANDO o dono do arquivo é o usuário que está rodando ("bad permissions" e
  # "This private key will be ignored"). Se o arquivo é de OUTRO usuário, ele
  # não aplica essa checagem — foi por isso que um 640 passou no teste numa
  # máquina com dois usuários e derrubou o SSH em outra, onde o dono era o
  # próprio. Medido em 04/09/2026.
  if timeout 15 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       -i "$PEM" ubuntu@3.85.130.14 true 2>/dev/null; then
    bom "SSH funciona (testado na CATATAU)"
    case "$perm" in
      600|400) ;;
      *) printf "      ${A}modo $perm funciona hoje porque o dono é outro usuário,\n"
         printf "      mas quebra se você virar dono do arquivo. O seguro é 600.${N}\n" ;;
    esac
  else
    ruim "a chave existe mas o SSH não conectou"
    case "$perm" in
      600|400) dica "a permissão está correta; confira se seu IP está liberado no security group da AWS" ;;
      *) dica "modo $perm: o OpenSSH RECUSA chave privada com bit de grupo/outros"
         dica "corrija com: chmod 600 $PEM"
         if [ "$dono" != "$(id -un)" ]; then
           dica "o arquivo é de $dono, então talvez precise de sudo — ou faça uma cópia sua"
         fi ;;
    esac
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

# ─── 5. homologação e VMs dos devs (fase 6) ────────────────────────────────
# Opcional de propósito: sem esse acesso o /promover-pr revisa, mergeia e
# deploya do mesmo jeito, só a fase 6 fica sem enxergar a VM. Por isso a falha
# aqui não entra em `falta`. É a chave padrão do usuário (sem -i), a mesma que
# o raio-X usa, e nunca senha. A VM do Walisson (.46) fica fora, a pedido dele.
titulo "5. Acesso à homologação e VMs dos devs (fase 6, opcional)"
aqui=" $(hostname -I 2>/dev/null) "
for par in HOMOLOGACAO:192.168.8.232 THALYSSON:192.168.8.167 NICOLAS:192.168.8.98; do
  nome=${par%%:*}; ip=${par#*:}
  case "$aqui" in *" $ip "*) printf "      %s (%s) é esta máquina, pulei\n" "$nome" "$ip"; continue ;; esac
  if timeout 15 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       chatwoot@"$ip" true 2>/dev/null; then
    bom "SSH funciona na $nome ($ip)"
  else
    printf "  ${A}!${N} %s (%s) não respondeu por SSH\n" "$nome" "$ip"
    dica "sem isso a fase 6 mostra 'nao medida daqui' para essa VM"
    dica "peça para autorizarem sua chave pública (~/.ssh/id_ed25519.pub; se não tiver, ssh-keygen -t ed25519) no usuário chatwoot dela"
  fi
done

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
