#!/usr/bin/env bash
#
# install-almiranted.sh — instalador idempotente do agente Almirante (Fase 0).
#
# O QUE FAZ (idempotente, seguro de re-rodar):
#   1. Copia o binario `almiranted` para /usr/local/bin (com backup do anterior).
#   2. Cria o state dir /var/lib/almirante com os subdiretorios pending/ e approved/.
#   3. IMPRIME (nao aplica) o snippet de authorized_keys com forced-command e a
#      linha de sudoers que o transport_user precisa.
#
# O QUE *NAO* FAZ:
#   - NAO edita ~/.ssh/authorized_keys de ninguem.
#   - NAO edita /etc/sudoers nem /etc/sudoers.d/*.
#   - NAO faz restart de servico, deploy, nem qualquer operacao destrutiva.
#   A aplicacao desses dois snippets e um passo HUMANO consciente (Fase 0).
#
# Uso:
#   sudo ./install-almiranted.sh [caminho-do-binario]
#     caminho-do-binario  (opcional) default: ./bin/almiranted ou ./almiranted
#
# Variaveis de ambiente (com defaults sensatos):
#   APP_USER        usuario da app que executa o pipeline   (default: chatwoot)
#   TRANSPORT_USER  usuario SSH do transporte (forced-cmd)  (default: deploybot)
#   STATE_DIR       state dir do gate pending/approved      (default: /var/lib/almirante)
#   INSTALL_DIR     destino do binario                      (default: /usr/local/bin)
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config (override por env var)
# ---------------------------------------------------------------------------
APP_USER="${APP_USER:-chatwoot}"
TRANSPORT_USER="${TRANSPORT_USER:-deploybot}"
STATE_DIR="${STATE_DIR:-/var/lib/almirante}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="almiranted"
INSTALLED_BIN="${INSTALL_DIR}/${BIN_NAME}"

# Unidades systemd que o agente tem permissao de reiniciar (espelha
# deploy.AllowedUnits no codigo Go). Mantido em sync manualmente.
RESTART_UNITS=(
  "chatwoot.target"
  "chatwoot-web.1.service"
  "chatwoot-worker.1.service"
)

# ---------------------------------------------------------------------------
# Helpers de log (sem cor pra nao sujar log de CI/SSH)
# ---------------------------------------------------------------------------
log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "rode como root (sudo). Precisa escrever em ${INSTALL_DIR} e ${STATE_DIR}."

# Localiza o binario de origem: argumento explicito, senao tenta caminhos comuns.
SRC_BIN="${1:-}"
if [ -z "${SRC_BIN}" ]; then
  for cand in "./bin/${BIN_NAME}" "./${BIN_NAME}" "$(dirname "$0")/../bin/${BIN_NAME}"; do
    if [ -f "${cand}" ]; then
      SRC_BIN="${cand}"
      break
    fi
  done
fi
[ -n "${SRC_BIN}" ] || die "binario ${BIN_NAME} nao encontrado. Passe o caminho: $0 /caminho/almiranted"
[ -f "${SRC_BIN}" ] || die "binario nao existe: ${SRC_BIN}"

# Garante que o APP_USER existe (o agente roda como ele via sudo -u).
id "${APP_USER}" >/dev/null 2>&1 || warn "usuario APP_USER='${APP_USER}' nao existe ainda; o agente nao vai conseguir 'sudo -u ${APP_USER}' ate cria-lo."

# ---------------------------------------------------------------------------
# 1. Instala o binario (idempotente: backup so se o conteudo mudou)
# ---------------------------------------------------------------------------
if [ -f "${INSTALLED_BIN}" ] && cmp -s "${SRC_BIN}" "${INSTALLED_BIN}"; then
  log "binario ja instalado e identico em ${INSTALLED_BIN} (nada a fazer)."
else
  if [ -f "${INSTALLED_BIN}" ]; then
    BACKUP="${INSTALLED_BIN}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "${INSTALLED_BIN}" "${BACKUP}"
    log "backup do binario anterior: ${BACKUP}"
  fi
  # install(1) faz copia atomica + permissoes numa tacada.
  install -m 0755 -o root -g root "${SRC_BIN}" "${INSTALLED_BIN}"
  log "instalado: ${INSTALLED_BIN}"
fi

# Mostra a versao (campo -X main.version do ldflags), se o binario suportar.
if "${INSTALLED_BIN}" --version >/dev/null 2>&1; then
  log "versao: $("${INSTALLED_BIN}" --version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
# 2. Cria o state dir do gate (pending/approved). Idempotente.
#    Dono = APP_USER (o agente roda como ele e precisa escrever os tokens).
#    0750: dono+grupo leem; resto do mundo nao enxerga os tokens de aprovacao.
# ---------------------------------------------------------------------------
install -d -m 0750 -o "${APP_USER}" -g "${APP_USER}" "${STATE_DIR}"          2>/dev/null \
  || install -d -m 0750 "${STATE_DIR}"
install -d -m 0750 -o "${APP_USER}" -g "${APP_USER}" "${STATE_DIR}/pending"  2>/dev/null \
  || install -d -m 0750 "${STATE_DIR}/pending"
install -d -m 0750 -o "${APP_USER}" -g "${APP_USER}" "${STATE_DIR}/approved" 2>/dev/null \
  || install -d -m 0750 "${STATE_DIR}/approved"
log "state dir pronto: ${STATE_DIR} (pending/ approved/)"

# ---------------------------------------------------------------------------
# 3. Imprime os snippets que precisam de aplicacao HUMANA (Fase 0).
#    Nada abaixo MODIFICA o sistema — e tudo informativo.
# ---------------------------------------------------------------------------

# (a) Forced-command para ~${TRANSPORT_USER}/.ssh/authorized_keys
#     A chave do transporte SO consegue rodar o almiranted (via sudo -u APP_USER),
#     e o forced-command ignora qualquer comando que o cliente SSH peca.
#     Os subcomandos approve/deploy continuam fora do alcance da chave: o gate
#     (approve) so e criado por sessao humana, nunca pela chave de transporte.
AUTHORIZED_KEYS_CMD="command=\"sudo -u ${APP_USER} ${INSTALLED_BIN}\",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc"

cat <<EOF

----------------------------------------------------------------------
PASSO HUMANO 1/2 — authorized_keys (forced-command)
----------------------------------------------------------------------
Em ~${TRANSPORT_USER}/.ssh/authorized_keys, prefixe a CHAVE PUBLICA do
transporte com este forced-command (a chave fica DEPOIS, na mesma linha):

  ${AUTHORIZED_KEYS_CMD} ssh-ed25519 AAAA...<chave-publica-do-transporte>

Isso restringe a chave a invocar SOMENTE o almiranted como ${APP_USER}.
EOF

# (b) sudoers para o TRANSPORT_USER:
#     - rodar o almiranted como APP_USER, sem senha
#     - reiniciar APENAS as units permitidas, sem senha
SUDOERS_FILE="/etc/sudoers.d/almirante-${TRANSPORT_USER}"
# Monta a lista de comandos systemctl restart (uma entrada por unit permitida).
RESTART_CMDS=""
for unit in "${RESTART_UNITS[@]}"; do
  [ -n "${RESTART_CMDS}" ] && RESTART_CMDS+=", "
  RESTART_CMDS+="/usr/bin/systemctl restart ${unit}"
done

cat <<EOF

----------------------------------------------------------------------
PASSO HUMANO 2/2 — sudoers (NOPASSWD minimo)
----------------------------------------------------------------------
Crie ${SUDOERS_FILE} com EXATAMENTE estas linhas e valide com 'visudo -c':

  # Almirante: transporte roda o agente como ${APP_USER} (sem senha).
  ${TRANSPORT_USER} ALL=(${APP_USER}) NOPASSWD: ${INSTALLED_BIN}

  # Almirante: restart so das units permitidas (espelha deploy.AllowedUnits).
  ${TRANSPORT_USER} ALL=(root) NOPASSWD: ${RESTART_CMDS}

Aplicar (HUMANO, fora deste script):
  visudo -cf - <<'SUDO'   # valida a sintaxe antes
  ${TRANSPORT_USER} ALL=(${APP_USER}) NOPASSWD: ${INSTALLED_BIN}
  ${TRANSPORT_USER} ALL=(root) NOPASSWD: ${RESTART_CMDS}
  SUDO
  # se OK, escreva o arquivo com permissao 0440 e dono root:root.
----------------------------------------------------------------------

EOF

log "instalacao concluida. Os 2 passos HUMANOS acima NAO foram aplicados (por design)."
