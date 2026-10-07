# syntax=docker/dockerfile:1
# CI do fork do ChatSPX (app chatspx-ci no Coolify). O scripts/ci.mjs injeta este arquivo como
# .captador-ci/Dockerfile no commit de CI da branch ci/fork; ele nunca entra na branch da feature.
# Roda `bundle exec rspec` só nos arquivos listados em .captador-ci/specs.txt, com Postgres 16 +
# pgvector (a imagem do CI oficial do fork) e Redis subindo dentro do próprio build: o docker build
# não alcança o daemon para subir serviços. Spec vermelho = build falha = deploy "failed".
FROM ruby:3.4.4-bookworm AS teste
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-common redis-server \
 && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
 && apt-get install -y --no-install-recommends postgresql-16 postgresql-16-pgvector \
 && rm -rf /var/lib/apt/lists/*
ENV RAILS_ENV=test BUNDLE_WITHOUT=development BUNDLE_JOBS=4 \
    POSTGRES_HOST=127.0.0.1 REDIS_URL=redis://127.0.0.1:6379
WORKDIR /app
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install
# ExecJS (carregado pelo config/application.rb) exige um runtime de JS. Depois do bundle: mantém o cache.
COPY --from=node:24-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY . .
RUN set -e; \
    PG=/usr/lib/postgresql/16/bin; mkdir -p /tmp/pg && chown postgres /tmp/pg; \
    su postgres -c "$PG/initdb -D /tmp/pg/dados -A trust -E UTF8 --locale=C.UTF-8 >/dev/null"; \
    su postgres -c "$PG/pg_ctl -D /tmp/pg/dados -w -l /tmp/pg/log -o \"-c listen_addresses=127.0.0.1 -k /tmp/pg -c fsync=off -c full_page_writes=off -c synchronous_commit=off\" start >/dev/null"; \
    redis-server --daemonize yes --save '' --appendonly no >/dev/null; \
    bundle exec rake db:create db:schema:load >/dev/null; \
    echo "rspec: $(tr '\n' ' ' < .captador-ci/specs.txt)"; \
    bundle exec rspec --format progress $(cat .captador-ci/specs.txt); \
    touch /tmp/rspec-ok
# Vitest do front, opcional: só quando o ci.mjs manda .captador-ci/vitest.txt (VITEST="..."). Sem a
# lista o passo termina na hora e o build é o de antes. O pnpm (versão do packageManager) vem do
# corepack da imagem do node, montado só aqui; a store do pnpm e o corepack ficam em cache do
# BuildKit. --ignore-scripts: o "prepare" (husky install) falha sem .git; scripts de dependência o
# pnpm 10 já não roda.
RUN --mount=type=bind,from=node:24-bookworm-slim,source=/usr/local/lib/node_modules/corepack,target=/opt/corepack \
    --mount=type=cache,target=/root/.cache/pnpm-store \
    --mount=type=cache,target=/root/.cache/node/corepack \
    set -e; \
    if [ -s .captador-ci/vitest.txt ]; then \
      export COREPACK_ENABLE_DOWNLOAD_PROMPT=0; \
      node /opt/corepack/dist/pnpm.js install --frozen-lockfile --ignore-scripts --store-dir /root/.cache/pnpm-store; \
      echo "vitest: $(tr '\n' ' ' < .captador-ci/vitest.txt)"; \
      TZ=UTC node_modules/.bin/vitest --no-watch --no-cache --no-coverage $(cat .captador-ci/vitest.txt); \
    fi

# Imagem mínima só para o Coolify fechar o deploy como "finished"; o ci.mjs para o container.
FROM busybox:1.37
COPY --from=teste /tmp/rspec-ok /rspec-ok
CMD ["sleep", "3600"]
