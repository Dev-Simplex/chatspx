#!/usr/bin/env bash

# Description: Install and manage a ChatSPX (Chatwoot fork) installation.
# OS: Ubuntu 24.04 LTS
# Script Version: 4.0.0
# Run this script as root

set -eu -o errexit -o pipefail -o noclobber -o nounset

# -allow a command to fail with !'s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo '`getopt --test` failed in this environment.'
    exit 1
fi

# Global variables
LONGOPTS=console,debug,help,install,Install:,logs:,restart,ssl,upgrade,Upgrade:,webserver,version,web-only,worker-only,convert:
OPTIONS=cdhiI:l:rsuU:wvWK
CWCTL_VERSION="4.0.0"
pg_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 15 ; echo '')
CHATWOOT_HUB_URL="https://hub.2.chatwoot.com/events"
RUBY_VERSION="3.4.4"
NODE_MAJOR=24
REPO_URL="https://github.com/Dev-Simplex/chatspx.git"
DEFAULT_BRANCH="producao"
LOG_FILE="/var/log/chatwoot-setup.log"

# if user does not specify an option
if [ "$#" -eq 0 ]; then
  echo "No options specified. Use --help to learn more."
  exit 1
fi

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    exit 2
fi
eval set -- "$PARSED"

c=n d=n h=n i=n I=n l=n r=n s=n u=n U=n w=n v=n W=n K=n C=n BRANCH=$DEFAULT_BRANCH SERVICE=web DEPLOYMENT_TYPE=full CONVERT_TO=""
while true; do
    case "$1" in
        -c|--console) c=y; break ;;
        -d|--debug) d=y; shift ;;
        -h|--help) h=y; break ;;
        -i|--install) i=y; BRANCH="$DEFAULT_BRANCH"; break ;;
        -I|--Install) I=y; BRANCH="$2"; break ;;
        -l|--logs) l=y; SERVICE="$2"; break ;;
        -r|--restart) r=y; break ;;
        -s|--ssl) s=y; shift ;;
        -u|--upgrade) u=y; BRANCH="$DEFAULT_BRANCH"; break ;;
        -U|--Upgrade) U=y; BRANCH="$2"; break ;;
        -w|--webserver) w=y; shift ;;
        -v|--version) v=y; shift ;;
        -W|--web-only) W=y; DEPLOYMENT_TYPE=web; shift ;;
        -K|--worker-only) K=y; DEPLOYMENT_TYPE=worker; shift ;;
        --convert)
            C=y; CONVERT_TO="$2"
            case "$CONVERT_TO" in
                web) DEPLOYMENT_TYPE=web ;;
                worker) DEPLOYMENT_TYPE=worker ;;
                full) DEPLOYMENT_TYPE=full ;;
                *) echo "Invalid conversion type. Use: web, worker, or full"; exit 3 ;;
            esac
            shift 2 ;;
        --) shift; break ;;
        *) echo "Invalid option(s). Use --help."; exit 3 ;;
    esac
done

if [ "$d" == "y" ]; then
  echo "console: $c, debug: $d, help: $h, install: $i, Install: $I, BRANCH: $BRANCH, \
  logs: $l, SERVICE: $SERVICE, ssl: $s, upgrade: $u, Upgrade: $U, webserver: $w, web-only: $W, worker-only: $K, convert: $C, convert-to: $CONVERT_TO, deployment-type: $DEPLOYMENT_TYPE"
fi

if [ "$(id -u)" -ne 0 ]; then
  echo 'This needs to be run as root.' >&2
  exit 1
fi

trap exit_handler EXIT

function exit_handler() {
  if [ "$?" -ne 0 ] && [ "$u" == "n" ]; then
   echo -en "\nSome error has occured. Check '$LOG_FILE' for details.\n"
   exit 1
  fi
}

##############################################################################
# Ensure swap exists (needed for asset compilation on small VMs)
##############################################################################
function ensure_swap() {
  if [ "$(swapon --show | wc -l)" -eq 0 ]; then
    local mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_mb" -lt 4096 ]; then
      echo "Creating 2GB swap file for build stability..."
      fallocate -l 2G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  fi
}

##############################################################################
# Domain/SSL input
##############################################################################
function get_domain_info() {
  read -rp 'Informe o dominio/subdominio do ChatSPX (ex: chat.seudominio.com.br): ' domain_name
  read -rp 'Informe um e-mail para avisos de renovacao do certificado SSL (LetsEncrypt): ' le_email
  cat << EOF

Este script vai gerar certificados SSL via LetsEncrypt e
servir o ChatSPX em https://$domain_name.
Certifique-se de que o DNS ja esta apontando para o IP desta VM.

EOF
  read -rp 'Deseja continuar? (sim ou nao): ' exit_true
  if [ "$exit_true" == "nao" ]; then
    exit 1
  fi
}

##############################################################################
# Install system dependencies
##############################################################################
function install_dependencies() {
  echo "  Updating system packages..."
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  echo "  Adding package repositories..."
  apt-get install -y curl wget gnupg2 lsb-release ca-certificates software-properties-common

  # Redis 7+ repo
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

  # Node.js repo
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

  # PostgreSQL 16 repo
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --yes -o /usr/share/keyrings/postgresql-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

  apt-get update

  echo "  Installing build tools and libraries..."
  apt-get install -y \
      git file g++ gcc autoconf build-essential \
      libssl-dev libyaml-dev libreadline-dev libncurses5-dev \
      libffi-dev libgdbm6 libgdbm-dev libpq-dev \
      libxml2-dev libxslt1-dev libvips \
      zlib1g-dev liblzma-dev libgmp-dev \
      imagemagick patch ruby-dev sudo \
      postgresql-client-16 redis-tools \
      nodejs python3-pip python3-packaging

  echo "  Installing pnpm..."
  npm install -g pnpm
}

##############################################################################
# Install PostgreSQL and Redis
##############################################################################
function install_databases() {
  apt-get install -y postgresql-16 postgresql-16-pgvector postgresql-contrib redis-server
}

##############################################################################
# Install Nginx + Certbot
##############################################################################
function install_webserver() {
  apt-get install -y nginx nginx-full certbot python3-certbot-nginx
}

##############################################################################
# Create chatwoot system user
##############################################################################
function create_cw_user() {
  if ! id -u "chatwoot" &>/dev/null; then
    adduser --disabled-password --gecos "" chatwoot
  fi
}

##############################################################################
# Install RVM + Ruby
##############################################################################
function configure_rvm() {
  create_cw_user

  gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  gpg2 --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  curl -sSL https://get.rvm.io | bash -s stable
  adduser chatwoot rvm

  # Install Ruby as chatwoot user
  sudo -i -u chatwoot bash -l <<RVMSCRIPT
    rvm autolibs disable
    rvm install ruby-${RUBY_VERSION}
    rvm use ${RUBY_VERSION} --default
    ruby --version
RVMSCRIPT
}

##############################################################################
# Postgres password persistence
##############################################################################
function save_pgpass() {
  mkdir -p /opt/chatwoot/config
  local file="/opt/chatwoot/config/.pg_pass"
  if ! test -f "$file"; then
    echo "$pg_pass" > "$file"
    chmod 600 "$file"
  fi
}

function get_pgpass() {
  local file="/opt/chatwoot/config/.pg_pass"
  if test -f "$file"; then
    pg_pass=$(cat "$file")
  fi
}

##############################################################################
# Configure PostgreSQL (user, pgvector, template encoding)
##############################################################################
function configure_db() {
  save_pgpass
  get_pgpass

  systemctl enable --now postgresql
  systemctl enable --now redis-server

  # Wait for PostgreSQL to be ready
  for i in $(seq 1 30); do
    if sudo -i -u postgres pg_isready -q 2>/dev/null; then break; fi
    sleep 1
  done

  sudo -i -u postgres psql <<EOF
    \set pass '${pg_pass}'
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'chatwoot') THEN
        CREATE USER chatwoot CREATEDB;
      END IF;
    END
    \$\$;
    ALTER USER chatwoot PASSWORD :'pass';
    ALTER ROLE chatwoot SUPERUSER;

    -- Fix template1 encoding for UTF-8
    UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';
    DROP DATABASE IF EXISTS template1;
    CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UNICODE';
    UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';
    \c template1
    VACUUM FREEZE;

    -- Enable pgvector extension on template1 so all new DBs inherit it
    CREATE EXTENSION IF NOT EXISTS vector;
EOF
}

##############################################################################
# Collect SPX-specific configuration from user
##############################################################################
function collect_spx_config() {
  echo ""
  echo "=== Configuracao do ChatSPX ==="
  echo ""

  # Timezone
  echo "Fuso horario:"
  echo "  1) America/Manaus (UTC-4)"
  echo "  2) America/Sao_Paulo (UTC-3)"
  echo "  3) America/Fortaleza (UTC-3)"
  echo "  4) America/Cuiaba (UTC-4)"
  echo "  5) Outro"
  read -rp "Escolha [1]: " tz_choice
  tz_choice=${tz_choice:-1}
  case "$tz_choice" in
    1) cfg_timezone="America/Manaus" ;;
    2) cfg_timezone="America/Sao_Paulo" ;;
    3) cfg_timezone="America/Fortaleza" ;;
    4) cfg_timezone="America/Cuiaba" ;;
    5) read -rp "  Informe o fuso horario (ex: America/Recife): " cfg_timezone ;;
    *) cfg_timezone="America/Manaus" ;;
  esac

  # Performance (auto-detect: extract maximum from VM)
  local mem_mb=$(free -m | awk '/^Mem:/{print $2}')
  local mem_gb=$((mem_mb / 1024))
  local cpu_count=$(nproc)

  # Puma workers = CPU cores (leave 1 for OS if > 2 cores)
  local suggested_concurrency=$cpu_count
  [ "$cpu_count" -gt 2 ] && suggested_concurrency=$((cpu_count - 1))

  # Threads per worker: scale with RAM per worker
  local ram_per_worker=$((mem_mb / (suggested_concurrency + 1)))
  local suggested_threads=5
  [ "$ram_per_worker" -ge 1024 ] && suggested_threads=8
  [ "$ram_per_worker" -ge 2048 ] && suggested_threads=12
  [ "$ram_per_worker" -lt 512 ] && suggested_threads=3

  # Sidekiq: aggressive — 1 worker per ~60MB RAM, cap at 50
  local suggested_sidekiq=$((mem_mb / 60))
  [ "$suggested_sidekiq" -gt 50 ] && suggested_sidekiq=50
  [ "$suggested_sidekiq" -lt 5 ] && suggested_sidekiq=5

  echo ""
  echo "Detectado: ${mem_gb}GB RAM, ${cpu_count} CPUs"
  echo "Configuracao de performance (otimizada para extrair o maximo da VM):"
  echo "  RAILS_MAX_THREADS=${suggested_threads} (threads por processo Puma)"
  echo "  WEB_CONCURRENCY=${suggested_concurrency} (workers Puma = CPUs)"
  echo "  SIDEKIQ_CONCURRENCY=${suggested_sidekiq} (workers Sidekiq)"
  read -rp "Aceitar esses valores? (sim ou nao) [sim]: " accept_perf
  accept_perf=${accept_perf:-sim}
  if [ "$accept_perf" != "sim" ]; then
    read -rp "  RAILS_MAX_THREADS [$suggested_threads]: " cfg_threads
    read -rp "  WEB_CONCURRENCY [$suggested_concurrency]: " cfg_web_concurrency
    read -rp "  SIDEKIQ_CONCURRENCY [$suggested_sidekiq]: " cfg_sidekiq
  fi
  cfg_threads=${cfg_threads:-$suggested_threads}
  cfg_web_concurrency=${cfg_web_concurrency:-$suggested_concurrency}
  cfg_sidekiq=${cfg_sidekiq:-$suggested_sidekiq}

  # SMTP (valores padrao SPX)
  configure_smtp="sim"
  cfg_mailer_sender="SPX - CHAT <sup@simplexsolucoes.com.br>"
  cfg_smtp_domain="simplexsolucoes.com.br"
  cfg_smtp_address="cloud55.mailgrid.net.br"
  cfg_smtp_port="587"
  cfg_smtp_user="chatspx@simplexsolucoes.com.br"
  cfg_smtp_pass="Master@1239*"
  cfg_smtp_auth="login"
  echo ""
  echo "SMTP configurado com valores padrao SPX (cloud55.mailgrid.net.br)"

  # WAHA
  echo ""
  read -rp "Configurar WAHA (integracao WhatsApp)? (sim ou nao) [nao]: " configure_waha
  configure_waha=${configure_waha:-nao}
  if [ "$configure_waha" == "sim" ]; then
    read -rp "  URL da API WAHA (ex: https://waha.seudominio.com.br): " cfg_waha_url
    read -rp "  Chave da API WAHA: " cfg_waha_key
    read -rp "  Sessao padrao WAHA (nome da sessao para validacao de numeros): " cfg_waha_session
  fi

  # First account + Super Admin
  echo ""
  echo "--- Primeira Conta e Super Admin ---"
  read -rp "Nome da conta (ex: Simplex Solucoes): " cfg_account_name
  read -rp "Nome do administrador: " cfg_admin_name
  read -rp "E-mail do administrador: " cfg_admin_email
  read -rsp "Senha do administrador (minimo 6 caracteres): " cfg_admin_password
  echo ""

  echo ""
  echo "Configuracao coletada. Iniciando instalacao..."
  echo ""
}

##############################################################################
# Helper: set or add a key=value in the .env file safely
##############################################################################
function set_env() {
  local env_file="/home/chatwoot/chatwoot/.env"
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$env_file"; then
    sudo -u chatwoot perl -pi -e "s|^\Q${key}\E=.*|${key}=${value}|" "$env_file"
  else
    echo "${key}=${value}" | sudo -u chatwoot tee -a "$env_file" > /dev/null
  fi
}

##############################################################################
# Clone repo, install deps, configure .env, compile assets
##############################################################################
function setup_chatwoot() {
  local secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 63 ; echo '')
  get_pgpass

  # Step 1: Clone and install deps
  sudo -i -u chatwoot bash -l <<CLONESCRIPT
    set -e
    if [ ! -d ~/chatwoot ]; then
      git clone ${REPO_URL} ~/chatwoot
    fi
    cd ~/chatwoot
    git fetch --all
    git checkout ${BRANCH}
    git pull origin ${BRANCH} || true
    gem install bundler --no-document
    bundle install --jobs \$(nproc) --retry 3
    pnpm install --frozen-lockfile || pnpm install
CLONESCRIPT

  # Step 2: Configure .env
  sudo -u chatwoot cp /home/chatwoot/chatwoot/.env.example /home/chatwoot/chatwoot/.env

  # Core
  set_env "SECRET_KEY_BASE" "$secret"
  set_env "REDIS_URL" "redis://localhost:6379"
  set_env "POSTGRES_HOST" "localhost"
  set_env "POSTGRES_USERNAME" "chatwoot"
  set_env "POSTGRES_PASSWORD" "$pg_pass"
  set_env "RAILS_ENV" "production"
  set_env "ENABLE_ACCOUNT_SIGNUP" "false"
  set_env "INSTALLATION_ENV" "linux_script"

  # Timezone
  set_env "TZ" "$cfg_timezone"

  # Performance
  set_env "RAILS_MAX_THREADS" "$cfg_threads"
  set_env "WEB_CONCURRENCY" "$cfg_web_concurrency"
  set_env "SIDEKIQ_CONCURRENCY" "$cfg_sidekiq"

  # SMTP
  if [ "${configure_smtp:-nao}" == "sim" ]; then
    set_env "MAILER_SENDER_EMAIL" "$cfg_mailer_sender"
    set_env "SMTP_DOMAIN" "$cfg_smtp_domain"
    set_env "SMTP_ADDRESS" "$cfg_smtp_address"
    set_env "SMTP_PORT" "$cfg_smtp_port"
    set_env "SMTP_USERNAME" "$cfg_smtp_user"
    set_env "SMTP_PASSWORD" "$cfg_smtp_pass"
    set_env "SMTP_AUTHENTICATION" "$cfg_smtp_auth"
    set_env "SMTP_ENABLE_STARTTLS_AUTO" "true"
    set_env "SMTP_OPENSSL_VERIFY_MODE" "peer"
    set_env "SMTP_SSL" "false"
    set_env "MAILER_INBOUND_EMAIL_DOMAIN" "$cfg_smtp_domain"
  fi

  # WAHA
  if [ "${configure_waha:-nao}" == "sim" ]; then
    set_env "WAHA_API_URL" "$cfg_waha_url"
    set_env "WAHA_API_KEY" "$cfg_waha_key"
    set_env "WAHA_DEFAULT_SESSION" "$cfg_waha_session"
  fi

  # Ativar X-Accel-Redirect no Rails (Nginx serve arquivos do disco)
  local prod_rb="/home/chatwoot/chatwoot/config/environments/production.rb"
  if grep -q '# config.action_dispatch.x_sendfile_header.*X-Accel-Redirect' "$prod_rb"; then
    sed -i "s|# config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'|config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'|" "$prod_rb"
  fi

  # Compile assets
  sudo -i -u chatwoot bash -l <<'BUILDSCRIPT'
    set -e
    cd ~/chatwoot
    RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=4096' bundle exec rake assets:precompile
BUILDSCRIPT
}

##############################################################################
# Run database migrations
##############################################################################
function run_db_migrations() {
  sudo -i -u chatwoot bash -l <<'MIGRATESCRIPT'
    set -e
    cd ~/chatwoot
    RAILS_ENV=production bundle exec rails db:create 2>/dev/null || true
    RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:schema:load
    RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:migrate
    RAILS_ENV=production bundle exec rails db:seed
MIGRATESCRIPT
}

##############################################################################
# Create first account and super admin user
##############################################################################
function create_first_account() {
  if [ -z "${cfg_admin_email:-}" ] || [ -z "${cfg_admin_password:-}" ]; then
    echo "Pulando criacao de conta (credenciais nao informadas)."
    return
  fi

  # Write a Ruby script to a temp file to avoid shell escaping issues
  local script_file="/tmp/chatwoot_create_account.rb"
  cat > "$script_file" <<RUBY
return if User.exists?(email: '$cfg_admin_email')

account = Account.create!(name: '$cfg_account_name')

user = User.new(
  name: '$cfg_admin_name',
  email: '$cfg_admin_email',
  password: '$cfg_admin_password',
  type: 'SuperAdmin'
)
user.skip_confirmation!
user.save!

AccountUser.create!(
  account_id: account.id,
  user_id: user.id,
  role: :administrator
)

Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
puts "Conta '#{account.name}' criada com admin #{user.email}"
RUBY

  chmod 644 "$script_file"
  sudo -i -u chatwoot bash -l -c 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails runner /tmp/chatwoot_create_account.rb'
  rm -f "$script_file"
}

##############################################################################
# Configure systemd services
##############################################################################
function configure_systemd_services() {
  local existing_full_deployment=false
  [ -f "/etc/systemd/system/chatwoot.target" ] && existing_full_deployment=true

  local CW_HOME="/home/chatwoot/chatwoot/deployment"

  if [ "$DEPLOYMENT_TYPE" == "web" ]; then
    echo "Setting up web-only deployment"
    if [ "$existing_full_deployment" = true ]; then
      systemctl stop chatwoot.target 2>/dev/null || true
      systemctl disable chatwoot.target 2>/dev/null || true
    fi
    [ -f "/etc/systemd/system/chatwoot-worker.target" ] && {
      systemctl stop chatwoot-worker.target 2>/dev/null || true
      systemctl disable chatwoot-worker.target 2>/dev/null || true
    }
    cp "$CW_HOME/chatwoot-web.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot-web.target" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now chatwoot-web.target

  elif [ "$DEPLOYMENT_TYPE" == "worker" ]; then
    echo "Setting up worker-only deployment"
    if [ "$existing_full_deployment" = true ]; then
      systemctl stop chatwoot.target 2>/dev/null || true
      systemctl disable chatwoot.target 2>/dev/null || true
    fi
    [ -f "/etc/systemd/system/chatwoot-web.target" ] && {
      systemctl stop chatwoot-web.target 2>/dev/null || true
      systemctl disable chatwoot-web.target 2>/dev/null || true
    }
    cp "$CW_HOME/chatwoot-worker.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot-worker.target" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now chatwoot-worker.target

  else
    echo "Setting up full deployment (web + worker)"
    [ -f "/etc/systemd/system/chatwoot-web.target" ] && {
      systemctl stop chatwoot-web.target 2>/dev/null || true
      systemctl disable chatwoot-web.target 2>/dev/null || true
    }
    [ -f "/etc/systemd/system/chatwoot-worker.target" ] && {
      systemctl stop chatwoot-worker.target 2>/dev/null || true
      systemctl disable chatwoot-worker.target 2>/dev/null || true
    }
    cp "$CW_HOME/chatwoot-web.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot-worker.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot.target" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now chatwoot.target
  fi

  # Sudoers and cwctl
  cp "$CW_HOME/chatwoot" /etc/sudoers.d/chatwoot
  chmod 440 /etc/sudoers.d/chatwoot
  cp "$CW_HOME/setup_spx_24.04.sh" /usr/local/bin/cwctl
  chmod +x /usr/local/bin/cwctl
}

##############################################################################
# Detectar se a VM tem IP publico (pode usar LetsEncrypt)
##############################################################################
function has_public_ip() {
  local public_ip=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null)
  local local_ip=$(hostname -I | awk '{print $1}')
  # Se o IP publico bate com algum IP local, tem IP publico direto
  if ip addr show | grep -q "$public_ip"; then
    return 0
  fi
  # Tenta acessar a porta 80 de fora
  if curl -s --max-time 5 -o /dev/null -w "%{http_code}" "http://${public_ip}" 2>/dev/null | grep -q "200\|301\|302\|404"; then
    return 0
  fi
  return 1
}

##############################################################################
# Gerar certificado auto-assinado (para VMs internas sem IP publico)
##############################################################################
function setup_selfsigned_ssl() {
  echo "VM interna detectada. Gerando certificado auto-assinado..."
  mkdir -p /etc/nginx/ssl
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/selfsigned.key \
    -out /etc/nginx/ssl/selfsigned.crt \
    -subj "/CN=${domain_name}" 2>/dev/null

  cp /home/chatwoot/chatwoot/deployment/nginx_chatwoot.conf /etc/nginx/sites-available/nginx_chatwoot.conf
  sed -i "s/chatwoot.domain.com/$domain_name/g" /etc/nginx/sites-available/nginx_chatwoot.conf
  # Trocar caminhos do LetsEncrypt pro auto-assinado
  sed -i "s|/etc/letsencrypt/live/$domain_name/fullchain.pem|/etc/nginx/ssl/selfsigned.crt|g" /etc/nginx/sites-available/nginx_chatwoot.conf
  sed -i "s|/etc/letsencrypt/live/$domain_name/privkey.pem|/etc/nginx/ssl/selfsigned.key|g" /etc/nginx/sites-available/nginx_chatwoot.conf
  # Remover dhparam se nao existir
  if [ ! -f /etc/ssl/dhparam ]; then
    sed -i '/ssl_dhparam/d' /etc/nginx/sites-available/nginx_chatwoot.conf
  fi
  ln -sf /etc/nginx/sites-available/nginx_chatwoot.conf /etc/nginx/sites-enabled/nginx_chatwoot.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl restart nginx
}

##############################################################################
# SSL setup com LetsEncrypt (para VMs com IP publico)
##############################################################################
function setup_letsencrypt_ssl() {
  echo "IP publico detectado. Gerando certificado LetsEncrypt..."
  curl -s https://ssl-config.mozilla.org/ffdhe4096.txt >> /etc/ssl/dhparam
  cp /home/chatwoot/chatwoot/deployment/nginx_chatwoot.conf /etc/nginx/sites-available/nginx_chatwoot.conf
  certbot certonly --non-interactive --agree-tos --nginx -m "$le_email" -d "$domain_name"
  sed -i "s/chatwoot.domain.com/$domain_name/g" /etc/nginx/sites-available/nginx_chatwoot.conf
  ln -sf /etc/nginx/sites-available/nginx_chatwoot.conf /etc/nginx/sites-enabled/nginx_chatwoot.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl restart nginx
}

##############################################################################
# SSL setup (detecta automaticamente o tipo)
##############################################################################
function setup_ssl() {
  if has_public_ip; then
    setup_letsencrypt_ssl
  else
    setup_selfsigned_ssl
  fi

  set_env "FRONTEND_URL" "https://${domain_name}"

  # Restart appropriate chatwoot target
  if [ -f "/etc/systemd/system/chatwoot-web.target" ]; then
    systemctl restart chatwoot-web.target
  elif [ -f "/etc/systemd/system/chatwoot-worker.target" ]; then
    systemctl restart chatwoot-worker.target
  else
    systemctl restart chatwoot.target
  fi
}

##############################################################################
# Setup logging
##############################################################################
function setup_logging() {
  touch "$LOG_FILE"
}

function ssl_success_message() {
  cat << EOF

***************************************************************************
Instalacao do ChatSPX concluida com sucesso!
O servidor esta acessivel em https://$domain_name

Acesso:
  E-mail: ${cfg_admin_email:-"(criado via onboarding)"}
  Senha: (a que voce definiu durante o setup)

Proximos passos:
  1. Acesse https://$domain_name e faca login
  2. Ajuste o .env em /home/chatwoot/chatwoot/.env se necessario
  3. Use 'cwctl --help' para gerenciar a instalacao
***************************************************************************

EOF
}

function cwctl_message() {
  echo ""
  echo "Use 'cwctl --help' para gerenciar sua instalacao ChatSPX."
  echo ""
}

##############################################################################
# INSTALL
##############################################################################
function install() {
  cat << EOF

***************************************************************************
              Instalacao ChatSPX (branch: $BRANCH)
***************************************************************************

Para logs detalhados, abra outro terminal e execute:
  tail -f $LOG_FILE

EOF

  sleep 2
  read -rp 'Deseja configurar dominio e SSL para o ChatSPX? (sim ou nao): ' configure_webserver
  if [ "$configure_webserver" == "sim" ]; then
    get_domain_info
  fi

  echo -en "\n"
  read -rp 'Deseja instalar Postgres e Redis localmente? (nao se usar servicos externos) (sim ou nao): ' install_pg_redis

  # Collect all SPX-specific configuration upfront
  collect_spx_config

  echo -en "\n=> 1/10 Verificando recursos do sistema...\n"
  ensure_swap &>> "$LOG_FILE"

  echo "=> 2/10 Instalando dependencias. Isso leva um tempo..."
  install_dependencies &>> "$LOG_FILE"

  if [ "$install_pg_redis" != "nao" ]; then
    echo "=> 3/10 Instalando bancos de dados (PostgreSQL 16 + pgvector + Redis 7)..."
    install_databases &>> "$LOG_FILE"
  else
    echo "=> 3/10 Pulando instalacao de bancos de dados."
  fi

  if [ "$configure_webserver" == "sim" ]; then
    echo "=> 4/10 Instalando servidor web (Nginx + Certbot)..."
    install_webserver &>> "$LOG_FILE"
  else
    echo "=> 4/10 Pulando instalacao do servidor web."
  fi

  echo "=> 5/10 Instalando Ruby ${RUBY_VERSION} via RVM..."
  configure_rvm &>> "$LOG_FILE"

  if [ "$install_pg_redis" != "nao" ]; then
    echo "=> 6/10 Configurando banco de dados..."
    configure_db &>> "$LOG_FILE"
  else
    echo "=> 6/10 Pulando configuracao do banco de dados."
  fi

  echo "=> 7/10 Instalando ChatSPX (clone, deps, assets). Isso leva bastante tempo..."
  setup_chatwoot &>> "$LOG_FILE"

  if [ "$install_pg_redis" != "nao" ]; then
    echo "=> 8/10 Executando migracoes do banco..."
    run_db_migrations &>> "$LOG_FILE"

    echo "=> 9/10 Criando primeira conta e super admin..."
    create_first_account &>> "$LOG_FILE"
  else
    echo "=> 8/10 Pulando migracoes do banco."
    echo "=> 9/10 Pulando criacao de conta (sem banco local)."
  fi

  echo "=> 10/10 Configurando servicos systemd..."
  configure_systemd_services &>> "$LOG_FILE"

  public_ip=$(curl -s http://checkip.amazonaws.com)

  if [ "$configure_webserver" != "sim" ]; then
    cat << EOF

***************************************************************************
Instalacao do ChatSPX concluida com sucesso!
O servidor esta acessivel em http://$public_ip:3000

Acesso:
  E-mail: ${cfg_admin_email:-"(criado via onboarding)"}
  Senha: (a que voce definiu durante o setup)

Para configurar dominio e SSL, execute: cwctl --ssl
***************************************************************************

EOF
    cwctl_message
  else
    echo "   Configurando SSL/TLS..."
    setup_ssl &>> "$LOG_FILE"
    ssl_success_message
    cwctl_message
  fi

  if [ "$install_pg_redis" == "nao" ]; then
    cat <<EOF

***************************************************************************
As migracoes do banco foram puladas. Apos configurar seu banco externo
no arquivo /home/chatwoot/chatwoot/.env, execute:

  sudo -i -u chatwoot bash -lc 'cd ~/chatwoot && RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare'
***************************************************************************

EOF
  fi

  exit 0
}

##############################################################################
# Console
##############################################################################
function get_console() {
  sudo -i -u chatwoot bash -l <<'CONSOLESCRIPT'
    cd ~/chatwoot && RAILS_ENV=production bundle exec rails c
CONSOLESCRIPT
}

##############################################################################
# Help
##############################################################################
function help() {
  cat <<EOF
Uso: cwctl [OPCAO]...
Instalar e gerenciar sua instalacao ChatSPX.

Exemplos:
  cwctl -i                    Instalar da branch $DEFAULT_BRANCH
  cwctl -I nome-da-branch     Instalar de uma branch especifica
  cwctl -u                    Atualizar para a ultima versao ($DEFAULT_BRANCH)
  cwctl -U nome-da-branch     Atualizar de uma branch especifica
  cwctl --web-only -i         Instalar apenas o servidor web
  cwctl --worker-only -i      Instalar apenas o worker
  cwctl --convert web         Converter para web-only
  cwctl --convert full        Converter para full (web + worker)
  cwctl -r                    Reiniciar servicos
  cwctl -l web                Ver logs do servidor web
  cwctl -l worker             Ver logs do worker
  cwctl -c                    Console Rails

Instalacao/Atualizacao:
  -i, --install             Instalar versao estavel (branch: $DEFAULT_BRANCH)
  -I BRANCH                 Instalar de uma branch especifica
  -u, --upgrade             Atualizar para a ultima versao estavel
  -U BRANCH                 Atualizar de uma branch especifica
  -s, --ssl                 Gerar certificados SSL (LetsEncrypt)
  -w, --webserver           Instalar e configurar Nginx com SSL
  -W, --web-only            Instalar apenas o servidor web
  -K, --worker-only         Instalar apenas o worker de background
      --convert TIPO        Converter deployment (TIPO: web, worker, full)

Gerenciamento:
  -c, --console             Abrir console Rails
  -l, --logs                Ver logs (web/worker)
  -r, --restart             Reiniciar servicos ChatSPX

Outros:
  -d, --debug               Mostrar mensagens de debug
  -v, --version             Mostrar versao
  -h, --help                Mostrar esta ajuda

Reportar bugs em https://github.com/Dev-Simplex/chatspx/issues

EOF
}

##############################################################################
# Logs
##############################################################################
function get_logs() {
  if [ "$SERVICE" == "worker" ]; then
    journalctl -u chatwoot-worker.1.service -f
  elif [ "$SERVICE" == "web" ]; then
    journalctl -u chatwoot-web.1.service -f
  else
    echo "Invalid service. Use: web or worker"
  fi
}

##############################################################################
# SSL standalone
##############################################################################
function ssl() {
  get_domain_info
  if ! systemctl -q is-active nginx; then
    install_webserver
  fi
  setup_ssl
  ssl_success_message
}

##############################################################################
# Upgrade prerequisites
##############################################################################
function upgrade_prereq() {
  sudo -i -u chatwoot bash -l <<'PREREQSCRIPT'
    cd ~/chatwoot
    git update-index --refresh
    if ! git diff-index --quiet HEAD --; then
      echo 'WARNING: Custom code changes detected.'
      echo 'Stashing changes before upgrade...'
      git stash
    fi
PREREQSCRIPT
}

function upgrade_redis() {
  if ! command -v redis-server &>/dev/null; then
    echo "Redis not installed. Skipping."
    return
  fi
  local current_version=$(redis-server --version | awk -F 'v=' '{print $2}' | awk '{print $1}')
  local major_version=$(echo "$current_version" | cut -d. -f1)
  if [ "$major_version" -ge 7 ]; then
    echo "Redis $current_version already >= 7. Skipping."
    return
  fi
  echo "Upgrading Redis to v7+..."
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
  apt-get update -y
  apt-get upgrade redis-server -y
}

function upgrade_node() {
  local current_version=$(node --version | cut -c 2-)
  local major_version=$(echo "$current_version" | cut -d. -f1)
  if [ "$major_version" -ge "$NODE_MAJOR" ]; then
    echo "Node.js $current_version already >= ${NODE_MAJOR}.x. Skipping."
    return
  fi
  echo "Upgrading Node.js to v${NODE_MAJOR}.x..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install nodejs -y
}

function get_pnpm() {
  if command -v pnpm &>/dev/null; then
    echo "pnpm already installed. Skipping."
    return
  fi
  echo "Installing pnpm..."
  npm install -g pnpm
  sudo -i -u chatwoot bash -l -c 'cd ~/chatwoot && rm -rf node_modules'
}

##############################################################################
# Upgrade
##############################################################################
function upgrade() {
  echo "Atualizando ChatSPX (branch: $BRANCH)..."

  if [ "$BRANCH" != "$DEFAULT_BRANCH" ]; then
    cat << EOF

AVISO: Atualizacao de branch nao-padrao e EXPERIMENTAL.
Sempre faca backup do banco de dados antes de continuar.

EOF
    read -rp "Deseja continuar? [s/N]: " user_input
    user_input=${user_input:-N}
    if [[ ! "$user_input" =~ ^([sS][iI][mM]|[sS])$ ]]; then
      echo "Atualizacao cancelada."
      exit 1
    fi
  fi

  ensure_swap
  upgrade_prereq
  upgrade_redis
  upgrade_node
  get_pnpm

  sudo -i -u chatwoot bash -l <<UPGRADESCRIPT
    set -e
    cd ~/chatwoot

    git fetch --all
    git checkout ${BRANCH}
    git pull origin ${BRANCH}

    latest_ruby_version=\$(cat .ruby-version)
    rvm install "ruby-\${latest_ruby_version}"
    rvm use "\${latest_ruby_version}" --default

    bundle install --jobs \$(nproc) --retry 3
    pnpm install --frozen-lockfile || pnpm install

    RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=4096' bundle exec rake assets:precompile
    RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:migrate
UPGRADESCRIPT

  # Update systemd services
  local CW_HOME="/home/chatwoot/chatwoot/deployment"
  if [ -f "/etc/systemd/system/chatwoot-web.target" ] && [ ! -f "/etc/systemd/system/chatwoot.target" ]; then
    cp "$CW_HOME/chatwoot-web.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot-web.target" /etc/systemd/system/
  elif [ -f "/etc/systemd/system/chatwoot-worker.target" ] && [ ! -f "/etc/systemd/system/chatwoot.target" ]; then
    cp "$CW_HOME/chatwoot-worker.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot-worker.target" /etc/systemd/system/
  else
    cp "$CW_HOME/chatwoot-web.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot-worker.1.service" /etc/systemd/system/
    cp "$CW_HOME/chatwoot.target" /etc/systemd/system/
  fi

  cp "$CW_HOME/chatwoot" /etc/sudoers.d/chatwoot
  chmod 440 /etc/sudoers.d/chatwoot
  cp "$CW_HOME/setup_spx_24.04.sh" /usr/local/bin/cwctl
  chmod +x /usr/local/bin/cwctl

  systemctl daemon-reload

  # Restart
  if [ -f "/etc/systemd/system/chatwoot-web.target" ] && [ ! -f "/etc/systemd/system/chatwoot.target" ]; then
    systemctl restart chatwoot-web.target
  elif [ -f "/etc/systemd/system/chatwoot-worker.target" ] && [ ! -f "/etc/systemd/system/chatwoot.target" ]; then
    systemctl restart chatwoot-worker.target
  else
    systemctl restart chatwoot.target
  fi

  echo ""
  echo "ChatSPX atualizado com sucesso para a branch: $BRANCH"
  echo ""
}

##############################################################################
# Restart
##############################################################################
function restart() {
  if [ -f "/etc/systemd/system/chatwoot-web.target" ] && [ ! -f "/etc/systemd/system/chatwoot.target" ]; then
    systemctl restart chatwoot-web.target
    systemctl status chatwoot-web.target --no-pager
  elif [ -f "/etc/systemd/system/chatwoot-worker.target" ] && [ ! -f "/etc/systemd/system/chatwoot.target" ]; then
    systemctl restart chatwoot-worker.target
    systemctl status chatwoot-worker.target --no-pager
  else
    systemctl restart chatwoot.target
    systemctl status chatwoot.target --no-pager
  fi
}

##############################################################################
# Convert deployment type
##############################################################################
function convert_deployment() {
  echo "Convertendo deployment ChatSPX para: $DEPLOYMENT_TYPE"
  if [ ! -d "/home/chatwoot/chatwoot" ]; then
    echo "Instalacao ChatSPX nao encontrada. Use --install primeiro."
    exit 1
  fi
  configure_systemd_services
  echo "Deployment convertido com sucesso para: $DEPLOYMENT_TYPE"
}

##############################################################################
# Webserver standalone
##############################################################################
function webserver() {
  ssl
}

##############################################################################
# Version
##############################################################################
function version() {
  echo "cwctl v$CWCTL_VERSION (ChatSPX)"
}

##############################################################################
# Main
##############################################################################
function main() {
  setup_logging

  if [ "$c" == "y" ]; then get_console; fi
  if [ "$h" == "y" ]; then help; fi
  if [ "$i" == "y" ] || [ "$I" == "y" ]; then install; fi
  if [ "$l" == "y" ]; then get_logs; fi
  if [ "$r" == "y" ]; then restart; fi
  if [ "$s" == "y" ]; then ssl; fi
  if [ "$u" == "y" ] || [ "$U" == "y" ]; then upgrade; fi
  if [ "$w" == "y" ]; then webserver; fi
  if [ "$v" == "y" ]; then version; fi
  if [ "$C" == "y" ]; then convert_deployment; fi
}

main "$@"
