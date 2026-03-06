#!/usr/bin/env bash

# Description: Install and manage an SPX Chat installation (forked from Chatwoot).
# OS: Ubuntu 24.04 LTS
# Script Version: 1.0.2
# Run this script as root

set -eu -o errexit -o pipefail -o noclobber -o nounset

! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
  echo '`getopt --test` failed in this environment.'
  exit 1
fi

LONGOPTS=console,debug,help,install,Install:,logs:,restart,ssl,upgrade,webserver,version
OPTIONS=cdhiI:l:rsuwv

CWCTL_VERSION="1.0.2"
APP_NAME="SPX Chat"
APP_USER="chatwoot"
APP_DIR="/home/${APP_USER}/chatwoot"
APP_REPO_URL="https://github.com/Dev-Simplex/chatspx.git"
DEFAULT_BRANCH="producao"
RUBY_VERSION="3.2.4"
NODE_MAJOR="23"
PNPM_VERSION="10"
pg_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 15 ; echo '')
CHATWOOT_HUB_URL=""

if [ "$#" -eq 0 ]; then
  echo "No options specified. Use --help to learn more."
  exit 1
fi

! PARSED=$(getopt --options="$OPTIONS" --longoptions="$LONGOPTS" --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  exit 2
fi

eval set -- "$PARSED"

c=n d=n h=n i=n I=n l=n r=n s=n u=n w=n v=n BRANCH="$DEFAULT_BRANCH" SERVICE=web
while true; do
  case "$1" in
    -c|--console)
      c=y
      break
      ;;
    -d|--debug)
      d=y
      shift
      ;;
    -h|--help)
      h=y
      break
      ;;
    -i|--install)
      i=y
      BRANCH="$DEFAULT_BRANCH"
      break
      ;;
    -I|--Install)
      I=y
      BRANCH="$2"
      break
      ;;
    -l|--logs)
      l=y
      SERVICE="$2"
      break
      ;;
    -r|--restart)
      r=y
      break
      ;;
    -s|--ssl)
      s=y
      shift
      ;;
    -u|--upgrade)
      u=y
      break
      ;;
    -w|--webserver)
      w=y
      shift
      ;;
    -v|--version)
      v=y
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option(s) specified. Use help(-h) to learn more."
      exit 3
      ;;
  esac
done

if [ "$d" == "y" ]; then
  echo "console: $c, debug: $d, help: $h, install: $i, Install: $I, BRANCH: $BRANCH, logs: $l, SERVICE: $SERVICE, ssl: $s, upgrade: $u, webserver: $w"
fi

if [ "$(id -u)" -ne 0 ]; then
  echo 'This needs to be run as root.' >&2
  exit 1
fi

trap exit_handler EXIT

function exit_handler() {
  if [ "$?" -ne 0 ] && [ "$u" == "n" ]; then
    echo -en "\nSome error has occured. Check '/var/log/chatwoot-setup.log' for details.\n"
    exit 1
  fi
}

function get_domain_info() {
  read -rp "Enter the domain/subdomain for ${APP_NAME} (e.g., app.domain.com): " domain_name
  read -rp 'Enter an email address for LetsEncrypt reminders: ' le_email
  cat << EOF

This script will generate SSL certificates via LetsEncrypt and
serve ${APP_NAME} at https://$domain_name.
Proceed further once you have pointed your DNS to the IP of the instance.

EOF
  read -rp 'Do you wish to proceed? (yes or no): ' exit_true
  if [ "$exit_true" == "no" ]; then
    exit 1
  fi
}

function install_dependencies() {
  apt-get update && apt-get upgrade -y

  apt-get install -y \
    curl wget git software-properties-common ca-certificates \
    imagemagick libpq-dev libxml2-dev libxslt1-dev file g++ gcc autoconf \
    build-essential libssl-dev libyaml-dev libreadline-dev gnupg2 \
    patch ruby-dev zlib1g-dev liblzma-dev libgmp-dev libncurses5-dev \
    libffi-dev libgdbm6 libgdbm-dev sudo libvips python3-pip

  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/redis.list > /dev/null

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list > /dev/null

  echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg 16" \
    > /etc/apt/sources.list.d/pgdg.list
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

  apt-get update

  apt-get install -y \
    postgresql-client-16 redis-tools nodejs

  npm install -g "pnpm@${PNPM_VERSION}"
}

function install_databases() {
  apt-get install -y postgresql-16 postgresql-16-pgvector postgresql-contrib redis-server
}

function install_webserver() {
  apt-get install -y nginx nginx-full certbot python3-certbot-nginx
}

function create_cw_user() {
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$APP_USER"
  fi
}

function configure_rvm() {
  create_cw_user

  gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys \
    409B6B1796C275462A1703113804BB82D39DC0E3 \
    7D2BAF1CF37B13E2069D6956105BD0E739499BDB

  gpg2 --keyserver hkp://keyserver.ubuntu.com --recv-keys \
    409B6B1796C275462A1703113804BB82D39DC0E3 \
    7D2BAF1CF37B13E2069D6956105BD0E739499BDB

  curl -sSL https://get.rvm.io | bash -s stable
  adduser "$APP_USER" rvm
}

function save_pgpass() {
  mkdir -p /opt/chatwoot/config
  file="/opt/chatwoot/config/.pg_pass"
  if ! test -f "$file"; then
    echo "$pg_pass" > /opt/chatwoot/config/.pg_pass
  fi
}

function get_pgpass() {
  file="/opt/chatwoot/config/.pg_pass"
  if test -f "$file"; then
    pg_pass=$(cat "$file")
  fi
}

function configure_db() {
  save_pgpass
  get_pgpass

  sudo -i -u postgres psql << EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'chatwoot') THEN
    CREATE USER chatwoot CREATEDB;
  END IF;
END
\$\$;
ALTER USER chatwoot PASSWORD '${pg_pass}';
ALTER ROLE chatwoot SUPERUSER;
UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';
DROP DATABASE IF EXISTS template1;
CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UNICODE';
UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';
EOF

  sudo -i -u postgres psql -d template1 << EOF
VACUUM FREEZE;
EOF

  systemctl enable redis-server.service
  systemctl enable postgresql
  systemctl restart redis-server
  systemctl restart postgresql
}

function setup_chatwoot() {
  local secret
  local RAILS_ENV=production

  secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 63 ; echo '')
  get_pgpass

  sudo -i -u "$APP_USER" bash << EOF
source /etc/profile.d/rvm.sh || true

rvm --version
rvm autolibs disable
rvm install "ruby-${RUBY_VERSION}"
rvm use "${RUBY_VERSION}" --default

if [ -d "${APP_DIR}" ]; then
  rm -rf "${APP_DIR}"
fi

git clone "${APP_REPO_URL}" "${APP_DIR}"
cd "${APP_DIR}"
git checkout "${BRANCH}"

gem install bundler
bundle config set without 'development test' || true
bundle install

pnpm install

cp .env.example .env

sed -i -e "/SECRET_KEY_BASE/ s/=.*/=${secret}/" .env || echo "SECRET_KEY_BASE=${secret}" >> .env
sed -i -e '/REDIS_URL/ s#=.*#=redis://localhost:6379#' .env || echo "REDIS_URL=redis://localhost:6379" >> .env
sed -i -e '/POSTGRES_HOST/ s/=.*/=localhost/' .env || echo "POSTGRES_HOST=localhost" >> .env
sed -i -e '/POSTGRES_USERNAME/ s/=.*/=chatwoot/' .env || echo "POSTGRES_USERNAME=chatwoot" >> .env
sed -i -e "/POSTGRES_PASSWORD/ s/=.*/=${pg_pass}/" .env || echo "POSTGRES_PASSWORD=${pg_pass}" >> .env
sed -i -e "/RAILS_ENV/ s/=.*/=${RAILS_ENV}/" .env || echo "RAILS_ENV=${RAILS_ENV}" >> .env
grep -q '^INSTALLATION_ENV=' .env || echo "INSTALLATION_ENV=linux_script" >> .env

RAILS_ENV=production bundle exec rails assets:precompile NODE_OPTIONS="--max-old-space-size=4096"
EOF
}

function run_db_migrations() {
  sudo -i -u "$APP_USER" bash << EOF
source /etc/profile.d/rvm.sh || true
cd "${APP_DIR}"
rvm use "${RUBY_VERSION}" --default
RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare
EOF
}

function configure_systemd_services() {
  cp "${APP_DIR}/deployment/chatwoot-web.1.service" /etc/systemd/system/chatwoot-web.1.service
  cp "${APP_DIR}/deployment/chatwoot-worker.1.service" /etc/systemd/system/chatwoot-worker.1.service
  cp "${APP_DIR}/deployment/chatwoot.target" /etc/systemd/system/chatwoot.target

  if [ -f "${APP_DIR}/deployment/chatwoot" ]; then
    cp "${APP_DIR}/deployment/chatwoot" /etc/sudoers.d/chatwoot
  fi

  cp "$0" /usr/local/bin/cwctl
  chmod +x /usr/local/bin/cwctl

  systemctl daemon-reload
  systemctl enable chatwoot.target
  systemctl start chatwoot.target
}

function setup_ssl() {
  curl https://ssl-config.mozilla.org/ffdhe4096.txt >> /etc/ssl/dhparam
  wget https://raw.githubusercontent.com/Dev-Simplex/chatspx/master/deployment/nginx_chatwoot.conf -O /etc/nginx/sites-available/nginx_chatwoot.conf

  certbot certonly --non-interactive --agree-tos --nginx -m "$le_email" -d "$domain_name"

  sed -i "s/chatwoot.domain.com/$domain_name/g" /etc/nginx/sites-available/nginx_chatwoot.conf

  ln -sf /etc/nginx/sites-available/nginx_chatwoot.conf /etc/nginx/sites-enabled/nginx_chatwoot.conf
  systemctl restart nginx

  sudo -i -u "$APP_USER" bash << EOF
cd "${APP_DIR}"
sed -i "s#http://0.0.0.0:3000#https://${domain_name}#g" .env
EOF

  systemctl restart chatwoot.target
}

function setup_logging() {
  touch /var/log/chatwoot-setup.log
  LOG_FILE="/var/log/chatwoot-setup.log"
}

function ssl_success_message() {
  cat << EOF

***************************************************************************
${APP_NAME} installation is complete.
The server will be accessible at https://$domain_name
***************************************************************************

EOF
}

function cwctl_message() {
  echo "SPX CLI installed."
  echo 'Type "cwctl --help" to learn more.'
}

function get_cw_version() {
  CW_VERSION="$BRANCH"
}

function install() {
  get_cw_version
  cat << EOF

***************************************************************************
              ${APP_NAME} Installation (${CW_VERSION})
***************************************************************************

For more verbose logs, open up a second terminal and follow along using,
'tail -f /var/log/chatwoot-setup.log'.

EOF

  sleep 3
  read -rp "Would you like to configure a domain and SSL for ${APP_NAME}? (yes or no): " configure_webserver

  if [ "$configure_webserver" == "yes" ]; then
    get_domain_info
  fi

  echo -en "\n"
  read -rp 'Would you like to install Postgres and Redis? (Answer no if you plan to use external services) (yes or no): ' install_pg_redis

  echo -en "\n➥ 1/9 Installing dependencies. This takes a while.\n"
  install_dependencies &>> "${LOG_FILE}"

  if [ "$install_pg_redis" != "no" ]; then
    echo "➥ 2/9 Installing databases."
    install_databases &>> "${LOG_FILE}"
  else
    echo "➥ 2/9 Skipping Postgres and Redis installation."
  fi

  if [ "$configure_webserver" == "yes" ]; then
    echo "➥ 3/9 Installing webserver."
    install_webserver &>> "${LOG_FILE}"
  else
    echo "➥ 3/9 Skipping webserver installation."
  fi

  echo "➥ 4/9 Setting up Ruby"
  configure_rvm &>> "${LOG_FILE}"

  if [ "$install_pg_redis" != "no" ]; then
    echo "➥ 5/9 Setting up the database."
    configure_db &>> "${LOG_FILE}"
  else
    echo "➥ 5/9 Skipping database setup."
  fi

  echo "➥ 6/9 Installing ${APP_NAME}. This takes a long while."
  setup_chatwoot &>> "${LOG_FILE}"

  if [ "$install_pg_redis" != "no" ]; then
    echo "➥ 7/9 Running database migrations."
    run_db_migrations &>> "${LOG_FILE}"
  else
    echo "➥ 7/9 Skipping database migrations."
  fi

  echo "➥ 8/9 Setting up systemd services."
  configure_systemd_services &>> "${LOG_FILE}"

  public_ip=$(curl -s http://checkip.amazonaws.com || true)

  if [ "$configure_webserver" != "yes" ]; then
    cat << EOF
➥ 9/9 Skipping SSL/TLS setup.

***************************************************************************
${APP_NAME} installation is complete.
The server will be accessible at http://${public_ip}:3000
***************************************************************************

EOF
    cwctl_message
  else
    echo "➥ 9/9 Setting up SSL/TLS."
    setup_ssl &>> "${LOG_FILE}"
    ssl_success_message
    cwctl_message
  fi

  exit 0
}

function get_console() {
  sudo -i -u "$APP_USER" bash -c "source /etc/profile.d/rvm.sh || true; cd ${APP_DIR} && rvm use ${RUBY_VERSION} --default && RAILS_ENV=production bundle exec rails c"
}

function help() {
  cat <<EOF
Usage: cwctl [OPTION]...
Install and manage your ${APP_NAME} installation.

Example: cwctl -i
Example: cwctl -I develop
Example: cwctl -l web
Example: cwctl --logs worker
Example: cwctl --upgrade
Example: cwctl -c

Installation/Upgrade:
  -i, --install             Install ${APP_NAME} from the default branch (${DEFAULT_BRANCH})
  -I, --Install <branch>    Install ${APP_NAME} from a git branch
  -u, --upgrade             Upgrade ${APP_NAME} from the configured repository
  -s, --ssl                 Fetch and install SSL certificates using LetsEncrypt
  -w, --webserver           Install and configure Nginx webserver with SSL

Management:
  -c, --console             Open ruby console
  -l, --logs                View logs from ${APP_NAME}. Supported values: web / worker
  -r, --restart             Restart ${APP_NAME}

Miscellaneous:
  -d, --debug               Show debug messages
  -v, --version             Display version information
  -h, --help                Display this help text

Exit status:
Returns 0 if successful; non-zero otherwise.
EOF
}

function get_logs() {
  if [ "$SERVICE" == "worker" ]; then
    journalctl -u chatwoot-worker.1.service -f
  fi
  if [ "$SERVICE" == "web" ]; then
    journalctl -u chatwoot-web.1.service -f
  fi
}

function ssl() {
  get_domain_info
  if ! systemctl -q is-active nginx; then
    install_webserver
  fi
  setup_ssl
  ssl_success_message
}

function upgrade_prereq() {
  sudo -i -u "$APP_USER" bash << EOF
cd "${APP_DIR}"
git update-index --refresh
if ! git diff-index --quiet HEAD --; then
  echo "Custom code changes detected. Aborting update."
  echo "Please proceed to update manually."
  exit 1
fi
EOF
}

function upgrade_redis() {
  if ! command -v redis-server &> /dev/null; then
    return
  fi

  current_version=$(redis-server --version | awk -F 'v=' '{print $2}' | awk '{print $1}')
  major_version=$(echo "$current_version" | cut -d. -f1)

  if [ "$major_version" -ge 7 ]; then
    return
  fi

  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/redis.list > /dev/null
  apt-get update -y
  apt-get upgrade redis-server -y
  apt-get install -y libvips
}

function upgrade_node() {
  current_version=$(node --version | cut -c 2-)
  major_version=$(echo "$current_version" | cut -d. -f1)

  if [ "$major_version" -ge "$NODE_MAJOR" ]; then
    return
  fi

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list > /dev/null

  apt-get update
  apt-get install -y nodejs
}

function get_pnpm() {
  npm install -g "pnpm@${PNPM_VERSION}"

  sudo -i -u "$APP_USER" bash << EOF
cd "${APP_DIR}" || exit 0
rm -rf node_modules
EOF
}

function upgrade() {
  echo "Upgrading ${APP_NAME}"
  sleep 2

  upgrade_prereq
  upgrade_redis
  upgrade_node
  get_pnpm

  sudo -i -u "$APP_USER" bash << EOF
source /etc/profile.d/rvm.sh || true
cd "${APP_DIR}"

git fetch origin
git checkout "${DEFAULT_BRANCH}"
git pull origin "${DEFAULT_BRANCH}"

rvm install "ruby-${RUBY_VERSION}"
rvm use "${RUBY_VERSION}" --default

gem install bundler
bundle config set without 'development test' || true
bundle install
pnpm install

RAILS_ENV=production bundle exec rails assets:precompile NODE_OPTIONS="--max-old-space-size=4096"
RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare
EOF

  cp "${APP_DIR}/deployment/chatwoot-web.1.service" /etc/systemd/system/chatwoot-web.1.service
  cp "${APP_DIR}/deployment/chatwoot-worker.1.service" /etc/systemd/system/chatwoot-worker.1.service
  cp "${APP_DIR}/deployment/chatwoot.target" /etc/systemd/system/chatwoot.target

  if [ -f "${APP_DIR}/deployment/chatwoot" ]; then
    cp "${APP_DIR}/deployment/chatwoot" /etc/sudoers.d/chatwoot
  fi

  systemctl daemon-reload
  systemctl restart chatwoot.target
}

function restart() {
  systemctl restart chatwoot.target
  systemctl status chatwoot.target
}

function webserver() {
  ssl
}

function report_event() {
  return 0
}

function version() {
  echo "cwctl v$CWCTL_VERSION (${APP_NAME})"
}

function main() {
  setup_logging

  if [ "$c" == "y" ]; then
    get_console
  fi

  if [ "$h" == "y" ]; then
    help
  fi

  if [ "$i" == "y" ] || [ "$I" == "y" ]; then
    install
  fi

  if [ "$l" == "y" ]; then
    get_logs
  fi

  if [ "$r" == "y" ]; then
    restart
  fi

  if [ "$s" == "y" ]; then
    ssl
  fi

  if [ "$u" == "y" ]; then
    upgrade
  fi

  if [ "$w" == "y" ]; then
    webserver
  fi

  if [ "$v" == "y" ]; then
    version
  fi
}

main "$@"
