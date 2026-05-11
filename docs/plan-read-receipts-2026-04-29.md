# Plano — Read Receipts WhatsApp (delivered + read)

> **Data:** 2026-04-29
> **Reportado por:** Walisson
> **Sintoma:** No ChatSPX as mensagens WhatsApp pulam direto de **1 cinza** (sent) para **2 azuis** (read), sem passar pelos **2 cinzas** (delivered). Walisson confirma que **antes funcionava** — nas inboxes WAHA atuais (#43 simplexteste, #42 spx) e nas Evolution API antigas.

## Diagnóstico final

### Os números no banco confirmam (inbox #43, 6 meses)

| Status | Qtd | % |
|---|---|---|
| sent (1✓) | 3.784 | 60% |
| **delivered (2✓ cinza)** | **2** | **0,03%** |
| read (2✓ azul) | 2.376 | 38% |
| failed | 155 | 2% |

**Apenas 2 mensagens em 6 meses ficaram em `delivered`** — confirma que a transição está quebrada.

### Causa raiz (git blame)

Em **2026-03-31** dois commits no mesmo dia:

| Commit | Hora | Mudança |
|---|---|---|
| `54c36da2e` | 01:56 UTC | **ADICIONOU** `handle_waha_ack_status_update` em `update_last_seen` — quando WAHA enviava `{payload: {id, ack}}`, atualizava status direto |
| `0db46b0dd` | poucas horas depois | **REMOVEU** essa lógica e trocou por `Waha::MessageStatusSyncJob` (polling) |

A intenção do segundo commit foi "centralizar" mas resultou em perda da granularidade. O polling:
- Só roda 1× por chamada de `update_last_seen` (cooldown 30s)
- Quando WAHA notifica `read`, o polling dispara mas pega `ack=3` direto e marca `read` — **pula `delivered`**
- Não roda automaticamente no momento em que WAHA marca `delivered` (ack=2)

### Por que "antes funcionava com WAHA"

Entre `54c36da2e` (01:56) e `0db46b0dd` (idem dia, ~hora depois) — **algumas horas em 31/03** — funcionou. Walisson testou nesse período e viu os 2 cinzas. Depois quebrou.

### O que a WAHA realmente envia

Pelos logs reais de hoje (`12:06:38`):

```
POST /public/api/v1/inboxes/{ident}/contacts/{uuid}/conversations/484/update_last_seen
Parameters: {inbox_id, contact_id, id, conversation: {}}
```

Atualmente o payload **não traz `payload.ack`** — só notifica que o cliente leu. Mas a versão do WAHA Chatwoot App de 31/03 enviava — e pode voltar a enviar (depende de versão/config). Logo, restaurar o handler é defensivo.

## Solução — estratégia dupla

### A) Caminho rápido (granular) — restaurar `handle_waha_ack_status_update`

**Arquivo:** `app/controllers/public/api/v1/inboxes/conversations_controller.rb`

```ruby
def update_last_seen
  # Caminho rápido: WAHA envia payload.ack → atualiza status direto
  if waha_ack_params_present?
    handle_waha_ack_status_update
    return head :ok
  end

  @conversation.contact_last_seen_at = DateTime.now.utc
  @conversation.save!

  if waha_inbox?
    ::Waha::MessageStatusSyncJob.perform_later(@conversation.id)
  else
    ::Conversations::UpdateMessageStatusJob.perform_later(@conversation.id, @conversation.contact_last_seen_at)
  end

  head :ok
end

private

def waha_ack_params_present?
  params.dig(:payload, :ack).present?
end

def handle_waha_ack_status_update
  waha_message_id = params.dig(:payload, :id)
  ack = params.dig(:payload, :ack).to_i
  status = waha_ack_to_chatwoot_status(ack)
  return if waha_message_id.blank? || status.blank?

  message = @conversation.messages.find_by(source_id: waha_message_id)
  Messages::StatusUpdateService.new(message, status).perform if message
end

def waha_ack_to_chatwoot_status(ack)
  { 1 => 'sent', 2 => 'delivered', 3 => 'read', 4 => 'read' }[ack]
end
```

### B) Caminho fallback — polling escalonado pós-envio

Cobre o caso atual onde WAHA não envia `payload.ack`. Garante que `delivered` seja captado dentro de segundos.

**Onde:** após criar msg outgoing em inbox WAHA. Ponto certo é `app/builders/messages/message_builder.rb#perform` ou um after_commit no Message — escolher o mais simples.

```ruby
# Em message_builder.rb (ou after_commit no model Message):
def schedule_waha_ack_polling
  return unless @message.outgoing? && waha_inbox?(@message.inbox)

  [5.seconds, 30.seconds, 2.minutes, 10.minutes].each do |delay|
    Waha::MessageStatusSyncJob.set(wait: delay).perform_later(@message.conversation_id)
  end
end
```

**`app/jobs/waha/message_status_sync_job.rb`** — reduzir cooldown:

```ruby
COOLDOWN = 3.seconds  # era 30s; com cooldown menor o polling escalonado funciona
```

### C) Otimização secundária — polling em `messages#index` condicional

**`app/controllers/api/v1/accounts/conversations/messages_controller.rb`** — `enqueue_waha_status_sync` só dispara se conv tem msgs em `sent` há mais de 30s:

```ruby
def enqueue_waha_status_sync
  inbox = @conversation.inbox
  return unless inbox&.channel_type == 'Channel::Api' && inbox.waha_session_name.present?
  return unless @conversation.messages
                              .where(message_type: :outgoing, status: :sent)
                              .where('created_at > ?', 30.seconds.ago)
                              .where('created_at < ?', 1.hour.ago)
                              .exists?

  Waha::MessageStatusSyncJob.perform_later(@conversation.id)
end
```

Evita carga desnecessária a cada navegação no dashboard.

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Polling 4× por msg → carga +400% no `get_messages` da WAHA | Cooldown 3s + fila default (não critical) + condição em messages#index |
| Mensagem fica horas em `delivered` (cliente não leu) | Polling agendado em 10min é suficiente; quando cliente abrir, WAHA chama `update_last_seen` |
| WAHA volta a enviar `payload.ack` em update futuro | Caminho A trata. É defensivo. |
| `Messages::StatusUpdateService` rejeita transição read→delivered | Já tem guard: `return false if message.read? && status == 'delivered'` |

## Validação

### Teste happy path
1. Agente envia msg → ver **1✓** (sent) imediato
2. Aguardar ~5s → ver **2✓ cinzas** (delivered)
3. Cliente abrir mensagem → ver **2✓ azuis** (read)

### Teste em produção (banco)
```ruby
# Antes: 2 delivered em 6 meses
Message.where(inbox_id: 43, status: :delivered).where('created_at > ?', 1.day.ago).count
# Depois: deve crescer (esperado: 30-50% das outgoing passam por delivered)
```

### Logs Sidekiq
- Cada msg outgoing nova → 4 `Waha::MessageStatusSyncJob` enfileirados
- Service deve fazer GET na WAHA `/api/sessions/.../messages` e atualizar conforme `ack`

## Plano de execução

| # | Ação | Arquivos | Tempo |
|---|------|----------|-------|
| 1 | Restaurar `handle_waha_ack_status_update` | `public/api/v1/inboxes/conversations_controller.rb` | 5min |
| 2 | Adicionar `schedule_waha_ack_polling` em criação de msg outgoing | `messages/message_builder.rb` (ou model `Message`) | 10min |
| 3 | Reduzir COOLDOWN do job para 3s | `waha/message_status_sync_job.rb` | 1min |
| 4 | Tornar polling em `messages#index` condicional | `api/v1/accounts/conversations/messages_controller.rb` | 5min |
| 5 | Build + restart `chatwoot.target` | — | 4min |
| 6 | Smoke test manual: enviar msg, validar 3 estados visuais | — | 10min |
| 7 | Validação banco: query `Message.where(status: :delivered)` cresce | — | 2min |

**Total:** ~40min.

## Plano de rollback

Working tree atual tem ~109 arquivos. Se P1 quebrar produção:

```bash
git restore app/controllers/public/api/v1/inboxes/conversations_controller.rb
git restore app/builders/messages/message_builder.rb
git restore app/jobs/waha/message_status_sync_job.rb
git restore app/controllers/api/v1/accounts/conversations/messages_controller.rb
sudo systemctl restart chatwoot.target
```

Sem migration, sem mudança de schema — rollback é puro código.

## Outras melhorias da sessão (já no working tree)

| Item | Status | Pendência |
|---|---|---|
| B1-B9 do `plan-ui-fixes-2026-04-28.md` | ✓ feito | Validar |
| Avatar contato em bubbles incoming 1:1 | ✓ feito | Validar |
| Remoção total de reactions | ✓ feito | Validar |
| Star → context menu (Favoritar/Desfavoritar) | ✓ feito | Validar |
| Hover consistência cores | ✓ feito | Validar |
| Avatar TOP-aligned + size 28 LEFT/24 RIGHT + gap-x-1.5 | ✓ feito | Validar |
| **6.4 delivered receipt** | ❌ **PENDENTE** | **Este plano** |

Os itens 6.2/6.3 mencionados anteriormente como "depende de WAHA" — descartados deste ciclo após pesquisa confirmar que a WAHA Chatwoot App não tem flag pública para forwardar todos os tipos de evento.

## Commit final (após aprovação)

```
feat(messages+ui): delivered receipt + avatar incoming + favoritar context-menu + ui-fixes B1-B9

- public/messages: restaurar handle_waha_ack_status_update para captar
  payload.ack direto da WAHA (commit 54c36da2e regredido em 0db46b0dd)
- waha/job: polling escalonado 5s/30s/2min/10min após msg outgoing,
  cooldown reduzido 30s→3s
- messages_controller: polling em #index só se conv tem sent recente
- ui: avatar contato em bubbles incoming, top-aligned, size 28/24, gap 1.5
- ui: Favoritar/Desfavoritar via menu de contexto (botão direito)
- ui: remoção total de reactions (estudo WAHA pendente)
- ui: B1-B9 do plan-ui-fixes-2026-04-28
```

## Referências

- [WAHA Events Docs](https://waha.devlike.pro/docs/how-to/events/)
- [WAHA Chatwoot App Overview](https://waha.devlike.pro/docs/apps/chatwoot/)
- Commit `54c36da2e` — `feat: per-message status tracking (sent/delivered/read) for WAHA`
- Commit `0db46b0dd` — `feat: WAHA per-message status sync` (regressão)
