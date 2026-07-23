# Prompt para "meter marcha" na produção interna (.229)

Cole isto num Claude Code rodando **na máquina de produção interna** (`192.168.8.229`, `chat.simplexsolucoes.com.br`). Ela tem credencial GitHub, então faz `git pull` direto (diferente das VMs AWS).

---

Você está na VM de **produção interna** do ChatSPX (192.168.8.229). Preciso **nivelar o código com `origin/producao`** (deve estar em `56a48c85e` — traz as features consolidadas de 07/07 já gated por flag + o **eval nativo LLM-as-a-Judge** do Captain). Faça um deploy **seguro e defensivo**, nesta ordem, e me reporte cada etapa:

1. **Diagnóstico (read-only primeiro):**
   - `cd` no repo do chatwoot (provável `/home/chatwoot/chatwoot`; o serviço roda como usuário `chatwoot`).
   - Mostre `git rev-parse --abbrev-ref HEAD`, `git rev-parse --short HEAD`, `git status --short` e `free -h`.
   - `git fetch origin` e mostre `git log --oneline HEAD..origin/producao` (o que falta) e se o front muda: `git diff --name-only HEAD..origin/producao -- app/javascript | wc -l`.
   - Se houver **commits locais próprios** (não vindos de origin) ou **WIP de código não commitada**, **PARE e me avise** — não sobrescreva sem confirmar.

2. **Atualizar código:** como usuário `chatwoot`, na branch `producao`:
   - `git checkout -- public/version.json` (limpa o marcador auto-gerado)
   - `git checkout producao && git pull --ff-only origin producao`
   - Confirme `git rev-parse --short HEAD` == `56a48c85e`.

3. **Anti-OOM (se o front mudou / máquina ≤ 8 GB):** ligue swap temporário ANTES de compilar assets:
   - `sudo swapon --show | grep -q swapfile_build || (sudo fallocate -l 4G /swapfile_build && sudo chmod 600 /swapfile_build && sudo mkswap /swapfile_build && sudo swapon /swapfile_build)`

4. **Dependências (só se mudaram):**
   - Se `Gemfile.lock` mudou no diff: `bundle install --jobs $(nproc) --retry 3`
   - Se `package.json`/`pnpm-lock.yaml` mudaram: `pnpm install --frozen-lockfile || pnpm install`

5. **Assets (só se o front mudou):** guarde o mtime do manifest ANTES (`stat -c %y public/vite/.vite/manifest.json`), então:
   - `RAILS_ENV=production NODE_OPTIONS=--max-old-space-size=6144 bundle exec rake assets:precompile`
   - **Confirme que o mtime do manifest MUDOU.** Se não mudou (exit 0 falso por OOM), o build falhou — rode de novo e me avise.

6. **Banco:** `RAILS_ENV=production bundle exec rails db:migrate` — reporte as migrations aplicadas (deve incluir `CreateCaptainConversationEvals`).

7. **Restart + validação:**
   - `sudo systemctl restart chatwoot.target`
   - Aguarde e valide: `curl -s -o /dev/null -w "%{http_code}" localhost:3000/` (espera 200/302).
   - Boot limpo? `sudo journalctl -u chatwoot-web.1.service --since "3 min ago" | grep -iE "NameError|Zeitwerk|LoadError|FATAL"` (deve vir vazio).
   - Confirme a tabela do eval: `RAILS_ENV=production bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?(:captain_conversation_evals)"`.

8. **Limpeza:** desligue o swap temporário — `sudo swapoff /swapfile_build && sudo rm -f /swapfile_build`.

**Importante:** o eval é **opt-in por conta** (`custom_attributes['eval_enabled']`), então subir o código **não ativa nada** automaticamente — as contas desta VM seguem intocadas até você ligar com `rake spx:eval:enable[<account_id>]`. Não ative sem me confirmar quais contas.

Se qualquer etapa falhar (OOM, migration, boot), **PARE e me mostre o erro** antes de prosseguir.
