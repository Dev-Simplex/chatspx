# Runbook — Promover a branch `nicolas` para PRODUÇÃO / FROTA

> Passo a passo para levar tudo que foi construído no staging (`nicolas.chatspx.app`) para a **produção/frota** (`chat.simplexsolucoes.com.br`). Escrito do host de dev `nicolas` (que é **pull-only**: não pusha nem deploya). O deploy real roda **do orquestrador `192.168.8.229`** via `deploy.sh` (padrão da frota). Este documento é o checklist para quem executa o deploy.

**Regra de ouro:** produção é a frota (nunca foi local de teste). Faça **backup do banco antes de qualquer migration** e valide numa **conta piloto** antes de habilitar features para todos.

---

## 0. Pré-requisitos / contexto

- **Branch a deployar:** `nicolas` (HEAD atual com todo o trabalho recente: Follow-up/drip, Chat Interno v2, SLA por etapa, etc.).
- **Onde rodar:** orquestrador `192.168.8.229` → `deploy.sh` (este host `nicolas` **não** tem chave de deploy/PEM; é só staging).
- **Produção:** `chat.simplexsolucoes.com.br` (`45.189.168.51`) — servidor separado.
- **Topologia de produção (confirmar):** se igual ao staging → Cloudflare → nginx → puma (ActionCable in-process, sem anycable). Implica **piscar de ~2s no WebSocket a cada restart** (esperado; clientes reconectam sozinhos).

---

## 1. Ordem do deploy (padrão Chatwoot)

1. **Backup do banco de produção** (obrigatório, antes das migrations):
   ```bash
   pg_dump -Fc -f /backups/chatwoot_pre_deploy_$(date +%F_%H%M).dump <DATABASE_URL_ou_flags>
   ```
2. **Pré-checagem de flags** (ver §3.1 — rodar ANTES do code pull, enquanto os nomes antigos existem).
3. **Pull do código** da branch `nicolas` na frota (via deploy.sh).
4. **Dependências** (só se `Gemfile.lock`/`package.json` mudaram): `bundle install` / `pnpm install` (ou yarn).
5. **Migrations** (idempotente — só roda as pendentes):
   ```bash
   RAILS_ENV=production bundle exec rails db:migrate
   ```
6. **Assets** (⚠️ heap — ver §4):
   ```bash
   NODE_OPTIONS=--max-old-space-size=8192 RAILS_ENV=production bundle exec rails assets:precompile
   ```
7. **Restart** dos serviços: **web** (puma — pega features.yml + listeners) e **worker/sidekiq** (pega `schedule.yml` novo). Na frota normalmente via systemd/deploy.sh.
8. **Pós-deploy**: §3.2 (habilitar features por conta) + §6 (smoke).

> `db:migrate` aplica só o que falta em `schema_migrations` — não precisa enumerar as 80+ migrations da branch. As **deste ciclo** estão em §5 para ciência.

---

## 2. O que muda além de código/migrations

| Item | Onde | Pega efeito em |
|---|---|---|
| Crons novos | `config/schedule.yml`: `message_sequences_advance_job` (*/1), `kanban_sla_monitor_job` (*/15), `kanban_daily_snapshot_job` (diário) | restart do **sidekiq** (sidekiq-cron recarrega) |
| Listeners de evento | `app/dispatchers/async_dispatcher.rb`: `MessageSequences::ExitListener`, `Spx::Tozi::FunnelAutomationListener` | restart do **web** |
| Feature flags | `config/features.yml` (bitmask) | restart do **web** + **habilitação por conta** (§3) |

---

## 3. Feature flags — a parte MAIS sensível (manual, fora de migration)

`feature_flags` é um **bitmask `bigint`** na tabela `accounts`; cada flag é um **bit posicionado pela ORDEM** em `config/features.yml`. **Limite: 63 bits.** Por isso, flags novos que ultrapassariam 63 foram criados **reclamando slots de flags deprecadas in-place** (mesma posição → não desloca os outros bits).

### Reclamações in-place feitas nesta branch (vs versão antiga)
| Slot antigo (deprecated) | Virou | Observação |
|---|---|---|
| `response_bot` | **`message_sequences`** | Follow-up/drip |
| `message_reply_to` | **`internal_chat`** | Chat interno |
| `report_v4` | **`ai_assistant_v2`** | (ciclo anterior) |
| `mobile_v2` | **`report_rollup`** | (ciclo anterior) |

### Flags novos appendados ao FIM (bits novos, seguros)
`kanban_cursor_loading`, `kanban_ux_v2`, `captain_tasks`, `conversation_required_attributes`, `advanced_assignment` — todos default `enabled: false`.

### 3.1 ⚠️ Pré-checagem OBRIGATÓRIA (rodar ANTES do code pull)
Como o reclaim reusa o bit, **se alguma conta de produção tiver o flag deprecado ANTIGO ligado, o flag NOVO liga sozinho** após o deploy. Rode no console de produção **com o código ANTIGO ainda** (nomes antigos existem):
```ruby
RAILS_ENV=production bundle exec rails runner '
%w[response_bot message_reply_to report_v4 mobile_v2].each do |f|
  ids = Account.all.select { |a| a.feature_enabled?(f) rescue false }.map(&:id)
  puts "#{f}: #{ids.empty? ? "nenhuma conta (SEGURO)" : "CONTAS #{ids.inspect} — REVISAR"}"
end'
```
- Tudo "nenhuma conta (SEGURO)" → pode deployar sem risco de ligar feature à toa.
- Alguma conta listada → **desligar o flag antigo nessas contas antes do deploy** (`acc.disable_features!('response_bot')` etc.), senão a feature nova entra ligada para elas.

### 3.2 Habilitar os features novos (pós-deploy, por conta)
Todos entram **OFF por padrão**. Habilite na(s) conta(s) desejada(s) — recomendo **piloto primeiro**:
```ruby
RAILS_ENV=production bundle exec rails runner '
acc = Account.find(<ID_PILOTO>)
acc.enable_features!("message_sequences", "internal_chat")  # + outros que queira
puts acc.reload.feature_enabled?("internal_chat")'
```
> No staging, ambos estão ligados na conta #1.

### 3.3 Verificar o orçamento de bits (sanidade)
Confirme que nenhum flag passou do bit 63 (senão `RangeError` ao habilitar):
```ruby
RAILS_ENV=production bundle exec rails runner 'puts Account::FEATURES.keys.size'  # deve ser <= 63
```

---

## 4. Assets — nota do OOM

O `vite build` estourou o heap default do Node (~4GB) algumas vezes no staging (host tem RAM de sobra; é limite do Node). **Sempre** rodar o precompile com heap maior:
```bash
NODE_OPTIONS=--max-old-space-size=8192 RAILS_ENV=production bundle exec rails assets:precompile
```
Se a frota usa `deploy.sh`, garantir que esse `NODE_OPTIONS` esteja exportado no passo de assets.

---

## 5. Migrations deste ciclo (ciência; `db:migrate` cuida)

Aditivas e reversíveis (novas tabelas/colunas). Ordem por timestamp:
- **Follow-up/drip:** `20260625140000/140100/140200` (message_sequences, _steps, _enrollments).
- **Chat Interno:** `20260625150000/150100/150200` (internal_channels, _members, _messages), `160000` (mentions), `20260626120000` (actions: edited_at/deleted_at/reactions), `130000` (reply_to_id), `140000` (shared_conversation_id).
- **Kanban (ciclo):** `20260624120000..20260625130000` (settings, custom_fields, views, item_notes, automations, metric_snapshots, templates).
- **SLA por etapa / config no modal:** sem migration (usa `funnel_stages.settings`).

Nenhuma é destrutiva; rollback raramente necessário (ver §7).

---

## 6. Smoke-test pós-deploy (produção)

1. **Real-time:** no navegador logado, console:
   ```js
   new WebSocket('wss://chat.simplexsolucoes.com.br/cable').onopen = () => console.log('WS OK')
   ```
   (deve logar "WS OK" — handshake 101).
2. **Flags:** `Account.find(<piloto>).feature_enabled?('internal_chat')` → true.
3. **Crons:** sidekiq → checar `message_sequences_advance_job`, `kanban_sla_monitor_job` no schedule (sidekiq-cron / Sidekiq::Cron::Job.all).
4. **Chat Interno:** abrir `/app/accounts/<piloto>/internal-chat` (item na sidebar), criar DM, enviar mensagem, ver chegar ao vivo (2 navegadores).
5. **Follow-up:** Configurações → Sequências de Follow-up; inscrever numa conversa; ver o `AdvanceJob` rodar.
6. **Kanban SLA:** Editar Etapa → checkbox "Definir SLA"; card fica âmbar/vermelho conforme prazo.

---

## 7. Rollback

- **Código:** redeploy do commit anterior (a frota deploya por commit/branch).
- **features.yml:** ao voltar o código, os nomes antigos voltam — **não** habilitar os flags novos antes de validar.
- **Migrations:** aditivas; normalmente não precisa reverter. Se necessário, `RAILS_ENV=production bundle exec rails db:rollback STEP=<n>` (na ordem inversa; cuidado com FKs). As novas tabelas/colunas não afetam o fluxo antigo se a feature ficar OFF.
- **Banco:** pior caso, restaurar o dump do §1.

---

## 8. Decisões deixadas em aberto (confirmar antes/depois)

- **DIRECT_UPLOADS_ENABLED:** ligado só no banco do **staging**; no código o default segue `false`. Ligar na frota é **decisão à parte** (não vem por este deploy).
- **AnyCable / cable server separado:** opcional — elimina o piscar de ~2s do WebSocket a cada restart (hoje o cable roda in-process no puma). Mudança de infra (root/orquestrador), puramente hardening; **não** é bloqueante.
- **Quais contas** recebem `message_sequences` / `internal_chat` / demais flags — definir com o usuário (piloto → geral).
- **Canal "Geral"/Anúncios** do chat interno: item opcional deferido (não está nesta entrega).

---

## TL;DR (sequência mínima)
1. Backup do banco. 2. **Pré-checagem de flags (§3.1)** com código antigo. 3. Pull `nicolas`. 4. `db:migrate`. 5. `assets:precompile` com `NODE_OPTIONS=--max-old-space-size=8192`. 6. Restart web+sidekiq. 7. `enable_features!` na conta piloto. 8. Smoke (§6).
