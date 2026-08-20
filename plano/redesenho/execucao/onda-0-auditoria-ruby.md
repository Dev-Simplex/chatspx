# Onda 0 — Auditoria semântica do merge v4.16.2 · ÁREA A1: RUBY DE APLICAÇÃO (`app/` + `lib/`)

- **Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **branch** `redesenho-merge` · **HEAD** `93571c69db`
- **SHAs:** BASE `899fce1c92` (v4.12.1) · NOSSO `f26db6ee81` · DELES `70e284a044` (v4.16.2) · MERGE `93571c69db`
- **Pais do merge confirmados:** `f26db6ee81cec6660eb3f21ea3417d2155878585` + `70e284a044f00326725f65f703162745371075ec` — o merge é de fato NOSSO×DELES, sem pai intermediário.
- **Escopo:** 121 arquivos de `app/{models,services,controllers,jobs,builders,finders,mailers,listeners,views,presenters,policies,helpers,dispatchers}`, `lib/`, `Gemfile`, `Gemfile.lock`, `.env.example`.

## Método executado

Para os 121 arquivos rodou-se uma varredura léxica programática: extrai **todas** as linhas
que NÓS adicionamos em `git diff BASE NOSSO -- <f>` e verifica, uma a uma (normalizando whitespace,
descartando linhas triviais tipo `end`/`}`), se a linha ainda existe no blob do MERGE. Linha nossa
ausente no MERGE vira candidata a PERDA e é julgada à mão. Além disso os arquivos quentes e os
focos nomeados na task foram lidos por inteiro para caçar **RISCO semântico** (assinatura, enum,
default, ordem, contrato), que a varredura léxica não detecta.

Resultado bruto: **98 dos 121** arquivos não perderam nenhuma linha nossa; **23** tiveram ao menos
uma linha ausente e foram investigados individualmente.

---

## 1. Veredito dos FOCOS nomeados na task

### 1.1 WhatsApp (WAHA/Evolution, grupos, 9º dígito, Meta Lead Ads) — **SOBREVIVEU**

| Item | Estado no MERGE | Evidência |
|---|---|---|
| **Grupos com autor por mensagem** (commit `44b77d19c0`) | **INTACTO**. Os **19 arquivos Ruby** do commit foram comparados um a um contra `f26db6ee81`: 18 são **byte-idênticos ao nosso**; só `app/models/conversation.rb` mudou (por outras razões, ver 1.5). | `waha/*`, `whatsapp/group_sender_extractor.rb`, `whatsapp/group_sender_phone_resolver.rb`, `whatsapp/lid_phone_cache.rb`, `csat_survey_service.rb`, `nps_survey_listener.rb`, `message_templates/*`, `llm_formatter/conversation_llm_formatter.rb`, `captain/behavior/router_service.rb` — todos idênticos |
| **`Conversation#group?`** (ponto único de verdade) | **INTACTO**, com os comentários pt-BR e o `jsonb_hash` tolerante a tipo | `app/models/conversation.rb:235-243` |
| **9º dígito BR** (`processed_waid`) | **INTACTO**, e o upstream ainda ACRESCENTOU normalizers dedicados | `app/services/whatsapp/incoming_message_service_helpers.rb:57` chama `Whatsapp::PhoneNumberNormalizationService`; upstream trouxe `whatsapp/phone_normalizers/brazil_phone_normalizer.rb` (`strip_ninth_digit`) |
| **Meta Lead Ads (`referral`)** | **PRESERVADO com contrato equivalente**. Nosso `attrs[:referral] = message[:referral].to_h if present?` virou `referral_attributes(message)` do upstream, que faz `message[:referral]&.to_h&.deep_stringify_keys \|\| {}` e passa a **pular echo**. | `incoming_message_service_helpers.rb:81-85` |
| **Interativo WhatsApp (`selected_option`, F1/F2 Automações)** | **INTACTO**, comentários pt-BR inclusive | `incoming_message_base_service.rb`, método renomeado `build_content_attributes` → `message_content_attributes` |
| **Mutex/fila do inbound** (`MutexApplicationJob`, `queue_as :high`, `retry_on LockAcquisitionError` 20×2s, lock 30s) | **INTACTO** — o upstream convergiu para a mesma solução | `app/jobs/webhooks/whatsapp_events_job.rb` |
| **Override de webhook por número** | **GANHO**: entrou `Whatsapp::WebhookChannelFinderService`, que resolve exatamente o caso BR (display_phone_number sem o 9) tentando dígitos crus + normalizado, exigindo match de `phone_number_id`. Substitui nosso `find_by(phone_number:)` direto. | `app/services/whatsapp/webhook_channel_finder_service.rb` (novo, não existia em `f26db6ee81`) |

### 1.2 Contadores — `compute_all_counts` **SOBREVIVEU INTEIRO**

O `app/finders/conversation_finder.rb` é o **2º arquivo mais customizado da área** (304 linhas nossas)
e o diff `NOSSO → MERGE` tem **uma única linha**:

```diff
+    'unread' => %w[sort_on_unread desc],
```

`compute_all_counts` permanece nas 4 ocorrências (`:53/:80/:102` e a definição em `:316`, agora
`:54/:81/:103/:317`). A saga de unread counts do upstream **entrou inteira** (17 services em
`app/services/conversations/unread_counts/*` + `unread_counts_controller.rb` + 2 migrations), mas
entrou **ao lado**, não por cima: ela alimenta um contador de badge por conversa, não substitui
os 9 contadores agregados do finder. O scope que a linha nova referencia existe
(`conversation.rb:125 scope :sort_on_unread`). **Veredito: OK.**

> ⚠️ Nota cruzada para a área de `db/` (não é minha área, mas é consequência direta desta):
> as 2 migrations que vieram junto — `20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb`
> e `20260629000000_repurpose_quoted_email_reply_flag_for_unread_count_for_filters.rb` — **reaproveitam
> bits já usados** do bitmask `feature_flags`. Conta da frota que tenha `channel_twitter` ou
> `quoted_email_reply` ligados passa a ter `conversation_unread_counts` / `unread_count_for_filters`
> ligados sem ninguém ter pedido. Isso casa com o achado 3 do coordenador sobre `features.yml` e
> deve ser verificado pelo executor de `db/` + `config/`.

### 1.3 `lib/webhooks/trigger.rb` (bloco 1.13) — **OK, com dois RISCOS operacionais**

Estado final: a classe **NÃO** foi reescrita no construtor — `initialize(url, payload, webhook_type,
secret: nil, delivery_id: nil)` **já existia em BASE (v4.12.1)** e é idêntico em NOSSO, DELES e MERGE.
O bloco 1.13 pode contar com essa assinatura.

Nossa única customização no arquivo (`ActivityMessageJob.perform_later(conversation.id, …)` em vez de
passar o objeto AR) **sobreviveu** — `lib/webhooks/trigger.rb:85`.

O que o upstream trocou, e o que isso custa:

1. **`RestClient` → `SafeFetch` (SSRF filter).** `perform_request` agora passa por `SsrfFilter`.
   O default é bloquear rede privada: `SafeFetch.allow_private_network?` lê
   `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` com **default `false`** (`lib/safe_fetch.rb:38`).
   → **RISCO OPERACIONAL ALTO NA FROTA**: todo webhook de conta, webhook de API inbox e agent bot
   apontando para IP/host privado (WAHA interna, n8n interno, receptor local, `192.168.x`) passa a
   falhar silenciosamente em `handle_failure` — vira log `warn`, não erro visível.
2. **Detecção de status por regex.** O retry de agent bot (429/500) agora depende de
   `error.message.to_s[/\A(\d{3})\b/, 1]` (`trigger.rb:132`). **Verifiquei o contrato**: o fetcher
   levanta `raise SafeFetch::HttpError, "#{response.code} #{response.message}"`
   (`lib/safe_fetch/fetcher.rb:9`), então a mensagem de fato começa pelo código e o regex casa.
   Frágil, mas **hoje coerente** — vira RISCO só se alguém mudar o texto da exceção.

### 1.4 `lib/url_helper.rb` + `validate_referer_url` (bloco 1.20) — **MEDIÇÃO DO PLANO CONFIRMADA**

Conferi por hash, não por leitura:

| arquivo | BASE | NOSSO | DELES | MERGE |
|---|---|---|---|---|
| `lib/url_helper.rb` (md5 do blob) | `b8d78def…` | `b8d78def…` | `b8d78def…` | `b8d78def…` |
| `Conversation#validate_referer_url` (md5 do trecho) | `6ce2e40d…` | `5013805a…` | `6ce2e40d…` | `5013805a…` |

`lib/url_helper.rb` é **byte-idêntico nos quatro**. `validate_referer_url` foi customizado por nós, o
upstream **não tocou** (BASE == DELES) e o **MERGE ficou com a nossa versão** (`conversation.rb:617-621`).
A base do bloco 1.20 está de pé.

### 1.5 `app/models/conversation.rb` e `app/models/account.rb` (os mais quentes) — **OK**

**`account.rb`**: o `SETTINGS_PARAMS_SCHEMA` inline foi extraído pelo upstream para o concern
`AccountSettingsSchema`. Verifiquei **um a um** os 9 settings nossos no concern do MERGE —
todos **PRESENTES**: `auto_resolve_ignore_waiting`, `audio_transcriptions`, `keep_pending_on_bot_failure`,
`resolve_assignment_gate`, `takeover_request_gate`, `captain_auto_resolve_mode`, `reply_assignment_gate`,
`orphan_retriage_after`, `conversation_required_attributes`. Os 4 que o scan léxico acusou como
ausentes (`resolve_assignment_gate`, `takeover_request_gate`, `reply_assignment_gate`,
`orphan_retriage_after`) **não existem no concern do upstream** (`70e284a044:app/models/concerns/account_settings_schema.rb`)
e **foram reenxertados** no concern do MERGE. Resolução correta. Os `store_accessor` correspondentes
seguem em `account.rb`.

**`conversation.rb`**: as 2 linhas nossas ausentes são só a refatoração upstream de
`handle_bot_status`/`handle_campaign_status` para `set_active_bot_conversation` (que preserva
`inbox.pending_status_enabled?` e ainda seta `assignee_agent_bot`). Nosso `skip_auto_assignment` e
o `reply_assignment_gate` foram **integrados** ao novo `release_agent_bot_for_handoff` do upstream,
não descartados. `allowed_keys?` virou `additional_attributes_changed?` — semântica **ampliada** de
forma segura (passa a olhar o valor antigo além do novo; dispara mais eventos, nunca menos).

---

---

## 2. Verificação independente dos três ACHADOS DE PARTIDA do coordenador

Foram reconferidos por conta própria, sem repetir a afirmação. **Dois confirmam; o terceiro precisa
de correção factual.**

### 2.1 Achado 1 (DADO, `captain/assistant_response.rb`) — **CONFIRMADO, e é o mais grave do merge**

```
NOSSO  f26db6ee81:enterprise/app/models/captain/assistant_response.rb:45   enum status: { pending: 0, approved: 1 }
DELES  70e284a044:…:47                                                     enum status: { approved: 1 }
MERGE  93571c69db:…:47                                                     enum status: { approved: 1 }
```

E a migration existe no MERGE, com o `DELETE` literal:

```ruby
# db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb
class PurgePendingCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def up
    execute('DELETE FROM captain_assistant_responses WHERE status = 0')
  end
  def down; end
end
```

`down` é vazio: **não há rollback**. Rodar `db:migrate` na frota apaga irreversivelmente toda FAQ
pendente de cliente. (Fora da minha área de arquivos, mas confirmado e repetido aqui porque é o único
achado que destrói dado gravado.)

### 2.2 Achado 2 (PERDA, `captain/responses/Pending.vue`) — **CONFIRMADO**

```
f26db6ee81  EXISTE   70e284a044  AUSENTE   93571c69db  AUSENTE
```

Casa com 2.1: a tela do fluxo de FAQ pendente foi apagada junto com o estado `pending`.

### 2.3 Achado 3 (`config/features.yml`) — **CONFIRMADO NO FATO, MAS O RISCO É MENOR DO QUE PARECE**

Reconstruí as duas colunas do bitmask a partir do YAML dos três SHAs e comparei **posição por posição**:

| coluna | NOSSO | DELES | MERGE | ordem dos bits comuns |
|---|---|---|---|---|
| `feature_flags` | 65 | 63 | 63 | **IDÊNTICA** — nenhum bit remapeado |
| `feature_flags_ext_1` | 0 | 5 | 14 | **IDÊNTICA** (prefixo preservado) |

Os dois flags que saíram de `feature_flags` são exatamente `conversation_required_attributes` e
`advanced_assignment` — e eles ocupavam as posições **64 e 65** de uma coluna `bigint`, que comporta
**63** flags (o próprio cabeçalho do arquivo diz, em `features.yml:13`, que a coluna está cheia em
63/63). Ou seja: **esses dois bits nunca couberam na coluna**; não havia estado válido gravado na
frota para eles. Mover para `feature_flags_ext_1` **não corrompe dado de cliente** — corrige um
overflow que já existia no nosso fork.

**O que ainda precisa ser checado pelo executor de `config/` + `db/`:** se alguma conta da frota tem
esses flags marcados como ligados na UI do Super Admin, esse estado se perde na virada (porque
passa a ser lido de outra coluna, que está zerada). É reconfiguração manual, não perda de dado.
Nenhuma migration de carregamento de estado foi encontrada para esses dois flags.

> A regra do próprio arquivo (`features.yml:15-16`: _"never change an existing feature's `column`
> after release"_) foi tecnicamente violada — mas violada para **consertar** um estado inválido.

---

## 3. Tabela completa — 121 arquivos, um por linha

| # | arquivo | classe triagem | linhas nossas | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|---|---|
| 1 | `app/controllers/api/v1/accounts/conversations/messages_controller.rb` | MERGE_REAL | 350 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/conversations/messages_controller.rb` = só adição upstream | — |
| 2 | `app/finders/conversation_finder.rb` | MERGE_REAL | 304 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/finders/conversation_finder.rb` = só adição upstream | — |
| 3 | `app/models/conversation.rb` | MERGE_REAL | 267 | **OK** | nada — as 2 linhas ausentes são a refatoração upstream `handle_bot_status` → `set_active_bot_conversation`, que preserva `pending_status_enabled?`. Nosso `skip_auto_assignment` e `reply_assignment_gate` foram INTEGRADOS ao novo `release_agent_bot_for_handoff` | `conversation.rb:277-283, 466-476`; `group?` intacto em `:235-243`; `validate_referer_url` idêntico ao nosso em `:617-621` | — |
| 4 | `app/controllers/public/api/v1/inboxes_controller.rb` | MERGE_REAL | 170 | **RISCO** | nada nosso (`normalize_waha_contact_params` intacto); o upstream restringiu a busca de conversa a `@contact_inbox.conversations` quando o contato NÃO é hmac_verified | `public/api/v1/inboxes_controller.rb:32-36` | Validar com WAHA: um contato com múltiplos contact_inboxes (telefone + BSUID) pode passar a receber 404 em `conversation_id` |
| 5 | `app/listeners/action_cable_listener.rb` | MERGE_REAL | 143 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/listeners/action_cable_listener.rb` = só adição upstream | — |
| 6 | `app/controllers/api/v1/accounts/contacts_controller.rb` | MERGE_REAL | 134 | **RISCO** | nada nosso; `sort_on :company` virou `sort_on :company_name` — contrato do parâmetro `sort` mudou | `contacts_controller.rb:12` | Sem ação: o front do merge já usa `company_name` (`contactFilterItems/index.js:57`) |
| 7 | `app/services/whatsapp/providers/whatsapp_cloud_service.rb` | MERGE_REAL | 121 | **RISCO** | nada nosso (passthrough/carrossel, `with_agent_prefix`, `whatsapp_reply_context`, CSAT template intactos); o upstream trocou a Graph API de anexos de v13.0 para v24.0 e adicionou BSUID/voice | `whatsapp_cloud_service.rb:246` — `phone_id_path('v24.0')` | Validar envio de anexo em canal Cloud oficial após o merge (WAHA não é afetado) |
| 8 | `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` | MERGE_REAL | 119 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/views/api/v1/conversations/partials/_conversation.json.jbuilder` = só adição upstream | — |
| 9 | `app/controllers/api/v1/accounts/conversations_controller.rb` | MERGE_REAL | 119 | **OK** | nada — `DeleteObjectJob` virou `Conversations::DeleteService` (upstream) e o `includes` ganhou `:inbox` | `conversations_controller.rb:49, 161` | — |
| 10 | `app/models/message.rb` | MERGE_REAL | 113 | **OK** | nada — `webhook_push_event_data` é adição do upstream; a mudança de índice é só annotation | `message.rb:190-195` | — |
| 11 | `app/models/attachment.rb` | MERGE_REAL | 106 | **RISCO** | nada nosso (guarda de áudio sem arquivo, WAHA_MAX_SIZE_BY_CATEGORY_MB e HARD_MAXIMUM_FILE_UPLOAD_SIZE_MB intactos); o upstream mudou `data_url` de áudio para `rails_storage_redirect_url(disposition: inline)` | `attachment.rb:117, 126-130` | Validar que o envio de áudio por WAHA (que consome `download_url`, não `data_url`) segue intacto |
| 12 | `app/views/layouts/mailer/base.liquid` | MERGE_REAL | 95 | **OK** | nada de comportamento — o merge adotou o layout novo do upstream e REAPLICOU o branding ChatSPX por cima | `base.liquid:30/49/67` (#2DC46F em vez de #2781F6), `:95` ('SPX - CHAT'), `:123` ("Este email foi enviado por"). As 73 linhas ausentes são o layout antigo + reformatação prettier | — |
| 13 | `app/controllers/api/v1/accounts/inboxes_controller.rb` | MERGE_REAL | 93 | **RISCO** | nada nosso (o merge de `additional_attributes` sobreviveu; só o comentário pt-BR virou inglês); mas o upstream REMOVEU `before_action :validate_limit, only: [:create]` | `inboxes_controller.rb:5` (linha some); contagem de `validate_limit`: BASE=1 NOSSO=1 DELES=0 MERGE=0 | Remoção é do upstream, não do merge. Confirmar se a frota depende do limite de inboxes por conta |
| 14 | `app/builders/messages/message_builder.rb` | MERGE_REAL | 93 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/messages/message_builder.rb` = só adição upstream | — |
| 15 | `app/finders/message_finder.rb` | PEGOU_NOSSO | 78 | **RISCO** | nada nosso; o merge DESCARTOU `MessageFinder.prepend_mod_with` que o upstream adicionou (o módulo enterprise correspondente também não entrou, então hoje não quebra) | contagem de `prepend_mod_with`: BASE=0 NOSSO=0 DELES=1 MERGE=0 | Nenhuma ação obrigatória; anotar divergência para o próximo merge (patch 6) |
| 16 | `app/jobs/bulk_actions_job.rb` | MERGE_REAL | 77 | **OK** | nada — `User.find_by(id: user_id)` (nosso padrão AR→ID) sobreviveu; o `includes` só mudou porque o upstream inseriu `Conversations::PermissionFilterService` | `bulk_actions_job.rb:15-16, 136-139` | — |
| 17 | `app/models/account.rb` | MERGE_REAL | 69 | **OK** | nada — o schema inline virou o concern `AccountSettingsSchema`, e os 9 settings nossos foram reenxertados nele (verificados um a um) | `app/models/concerns/account_settings_schema.rb:18-27` contém resolve_assignment_gate, takeover_request_gate, reply_assignment_gate e orphan_retriage_after, que NÃO existem no concern do upstream | — |
| 18 | `app/builders/contact_inbox_with_contact_builder.rb` | MERGE_REAL | 69 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/contact_inbox_with_contact_builder.rb` = só adição upstream | — |
| 19 | `app/controllers/api/v1/accounts/captain/preferences_controller.rb` | MERGE_REAL | 58 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/captain/preferences_controller.rb` = só adição upstream | — |
| 20 | `app/controllers/api/v1/accounts_controller.rb` | MERGE_REAL | 50 | **RISCO** | nada nosso; contrato de signup mudou — cadastro web NÃO autenticado passa a responder `{email: ...}` em vez de enviar auth headers | `accounts_controller.rb:47-59` | Validar com o executor de front que o fluxo de cadastro do ChatSPX espera o novo contrato |
| 21 | `app/models/team.rb` | MERGE_REAL | 41 | **RISCO** | nada nosso; `push_event_data` passou a expor `icon`/`icon_color`, colunas novas | `team.rb:83-88` | Confirmar com o executor de db/ que a migration das colunas `icon`/`icon_color` entrou |
| 22 | `app/models/agent_bot.rb` | MERGE_REAL | 41 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/agent_bot.rb` = só adição upstream | — |
| 23 | `app/listeners/webhook_listener.rb` | MERGE_REAL | 38 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/listeners/webhook_listener.rb` = só adição upstream | — |
| 24 | `lib/captain/rewrite_service.rb` | MERGE_REAL | 36 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/captain/rewrite_service.rb` = só adição upstream | — |
| 25 | `app/services/whatsapp/providers/base_service.rb` | MERGE_REAL | 36 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/whatsapp/providers/base_service.rb` = só adição upstream | — |
| 26 | `app/jobs/webhooks/whatsapp_events_job.rb` | MERGE_REAL | 36 | **OK** | nada de comportamento — MutexApplicationJob, `queue_as :high`, `retry_on LockAcquisitionError` (20×2s) e o lock de 30s por (inbox, contato) sobreviveram; os 2 comentários pt-BR foram traduzidos e `contact_sender_id` foi ampliado para BSUID | `whatsapp_events_job.rb:1-14, 94-124` | — |
| 27 | `app/jobs/agents/destroy_job.rb` | MERGE_REAL | 36 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/agents/destroy_job.rb` = só adição upstream | — |
| 28 | `app/controllers/super_admin/accounts_controller.rb` | MERGE_REAL | 36 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/super_admin/accounts_controller.rb` = só adição upstream | — |
| 29 | `lib/llm/models.rb` | MERGE_REAL | 32 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/llm/models.rb` = só adição upstream | — |
| 30 | `app/controllers/api/v1/accounts/labels_controller.rb` | MERGE_REAL | 31 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/labels_controller.rb` = só adição upstream | — |
| 31 | `app/controllers/swagger_controller.rb` | MERGE_REAL | 29 | **PERDA** | Doc da API acessível em PRODUÇÃO sob HTTP Basic Auth: o merge repôs o gate `if Rails.env.development? || Rails.env.test?` e deixou nosso `authenticate_docs!` como código morto | `swagger_controller.rb:5-14` — `else head :not_found`; `authenticate_docs!` (linhas 20-37) nunca chega a proteger nada em prod | Remover o gate de ambiente mantendo o hardening de path traversal do upstream (patch 3) |
| 32 | `lib/current.rb` | MERGE_REAL | 26 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/current.rb` = só adição upstream | — |
| 33 | `app/services/whatsapp/incoming_message_base_service.rb` | MERGE_REAL | 24 | **OK** | nada — `build_content_attributes` virou `message_content_attributes` (mesmo conteúdo, `selected_option` do F1/F2 intacto); `referral` virou `referral_attributes` (equivalente + deep_stringify + skip em echo); `set_contact_from_echo/message` mudaram para `whatsapp/incoming_message_identifier_helper.rb` mantendo `processed_waid` (9º dígito) | `incoming_message_service_helpers.rb:57, 81-85`; `incoming_message_identifier_helper.rb:61` | — |
| 34 | `app/models/team_member.rb` | MERGE_REAL | 24 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/team_member.rb` = só adição upstream | — |
| 35 | `lib/llm/config.rb` | MERGE_REAL | 23 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/llm/config.rb` = só adição upstream | — |
| 36 | `app/views/api/v1/accounts/conversations/attachments.json.jbuilder` | MERGE_REAL | 22 | **OK** | nada — os 9 campos inline viraram `json.partial! api/v1/models/attachment`, que produz o MESMO payload. `json.id` continua valendo porque `Attachment#base_data` inclui `id:`; nosso `json.filename` e a paginação (`current_page`/`total_pages`) sobreviveram | `attachment.rb:168-175` (base_data com id); `_attachment.json.jbuilder:3` | — |
| 37 | `app/controllers/api/v2/accounts/summary_reports_controller.rb` | MERGE_REAL | 22 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v2/accounts/summary_reports_controller.rb` = só adição upstream | — |
| 38 | `app/jobs/hook_job.rb` | MERGE_REAL | 21 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/hook_job.rb` = só adição upstream | — |
| 39 | `app/models/campaign.rb` | MERGE_REAL | 20 | **RISCO** | nada nosso (comentário e `dispatch_status` preservados); `campaign_status` ganhou `processing: 2` e `trigger!` passou a exigir a flag `whatsapp_campaign` para inbox WhatsApp | `campaign.rb:52, 65-70, 82-84`; a flag tem `enabled: false` em features.yml:189 | Sem ação para a frota: nosso `execute_campaign` já desativa o blaster nativo de WhatsApp (campaign.rb:101-107) e a engine real é `Campaigns::Whatsapp::DispatchSchedulerJob`. Só validar que o front conhece o status `processing` |
| 40 | `app/controllers/public/api/v1/inboxes/contacts_controller.rb` | MERGE_REAL | 20 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/public/api/v1/inboxes/contacts_controller.rb` = só adição upstream | — |
| 41 | `app/views/devise/mailer/confirmation_instructions.html.erb` | MERGE_REAL | 18 | **OK** | nada — o merge adotou o template novo do upstream JÁ TRADUZIDO para pt-BR e com 'SPX - CHAT' | `confirmation_instructions.html.erb:2-56` (eyebrow/heading/intro em pt-BR); partial `_confirmation_body.html.erb` presente | — |
| 42 | `app/models/account_user.rb` | MERGE_REAL | 18 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/account_user.rb` = só adição upstream | — |
| 43 | `app/controllers/api/v1/accounts/agent_bots_controller.rb` | MERGE_REAL | 18 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/agent_bots_controller.rb` = só adição upstream | — |
| 44 | `app/presenters/message_content_presenter.rb` | MERGE_REAL | 15 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/presenters/message_content_presenter.rb` = só adição upstream | — |
| 45 | `app/views/api/v1/models/_message.json.jbuilder` | PEGOU_NOSSO | 14 | **RISCO** | nada nosso; descartou o campo `call` do upstream (voice_call). `Message` não tem `has_one :call` e `enterprise/app/models/call.rb` não entrou no merge — feature veio pela metade | enum `voice_call: 13` existe em `message.rb:108`, mas o model `Call` está ausente do MERGE | Nenhuma ação; consistente com a feature de chamadas não ter sido mergeada |
| 46 | `Gemfile.lock` | MERGE_REAL | 14 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- Gemfile.lock` = só adição upstream | — |
| 47 | `app/models/contact.rb` | MERGE_REAL | 14 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/contact.rb` = só adição upstream | — |
| 48 | `app/models/inbox.rb` | MERGE_REAL | 13 | **RISCO** | nada nosso (`pin_mode`/`pinned_conversation_ids` intactos); entrou `include InboxBrandedEmailLayoutable` + `has_many :email_templates` | `inbox.rb:49, 74` | Confirmar com o executor de db/ que a tabela `email_templates` e o concern entraram |
| 49 | `app/listeners/hook_listener.rb` | MERGE_REAL | 13 | **OK** | nada — `HookJob.perform_later(hook.id, …, message_id:)` e nosso `serialize_event_data` sobreviveram; a linha só ganhou `previous_changes:` | `hook_listener.rb:46`, `:52-58` | — |
| 50 | `app/helpers/api/v1/inboxes_helper.rb` | MERGE_REAL | 13 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/helpers/api/v1/inboxes_helper.rb` = só adição upstream | — |
| 51 | `app/builders/v2/reports/bot_metrics_builder.rb` | MERGE_REAL | 13 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/v2/reports/bot_metrics_builder.rb` = só adição upstream | — |
| 52 | `lib/integrations/openai/openai_prompts/summary.liquid` | PEGOU_DELES | 12 | **PERDA** | Instrução que força o resumo de conversa em pt-BR (4 cabeçalhos traduzidos + regra IMPORTANT — LANGUAGE) | MERGE == DELES byte a byte; `summary.liquid:20-28` voltou a "Customer Intent / Conversation Summary / Action Items / Follow-up Items" | Reaplicar o bloco pt-BR (patch 1) |
| 53 | `lib/captain/follow_up_service.rb` | MERGE_REAL | 12 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/captain/follow_up_service.rb` = só adição upstream | — |
| 54 | `app/jobs/inboxes/fetch_imap_emails_job.rb` | MERGE_REAL | 12 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/inboxes/fetch_imap_emails_job.rb` = só adição upstream | — |
| 55 | `lib/events/types.rb` | MERGE_REAL | 11 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/events/types.rb` = só adição upstream | — |
| 56 | `app/views/layouts/vueapp.html.erb` | MERGE_REAL | 11 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/views/layouts/vueapp.html.erb` = só adição upstream | — |
| 57 | `app/models/custom_attribute_definition.rb` | MERGE_REAL | 11 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/custom_attribute_definition.rb` = só adição upstream | — |
| 58 | `app/helpers/file_type_helper.rb` | MERGE_REAL | 11 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/helpers/file_type_helper.rb` = só adição upstream | — |
| 59 | `app/models/user.rb` | MERGE_REAL | 10 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/user.rb` = só adição upstream | — |
| 60 | `app/jobs/avatar/avatar_from_url_job.rb` | MERGE_REAL | 10 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/avatar/avatar_from_url_job.rb` = só adição upstream | — |
| 61 | `app/jobs/notification/delete_notification_job.rb` | PEGOU_DELES | 9 | **RISCO** | Assinatura voltou a receber o objeto AR (`perform(user, account, …)`); nossa versão passava `user_id` para evitar ActiveJob::DeserializationError quando o user é apagado antes do job rodar (commit 87095e111b, "29 jobs AR→IDs") | `delete_notification_job.rb:4`; caller coerente em `notifications_controller.rb:44-46` | Reconverter para IDs preservando o escopo por conta que o upstream trouxe (patch 4) |
| 62 | `app/services/notification/push_notification_service.rb` | MERGE_REAL | 9 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/notification/push_notification_service.rb` = só adição upstream | — |
| 63 | `lib/regex_helper.rb` | MERGE_REAL | 8 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/regex_helper.rb` = só adição upstream | — |
| 64 | `app/policies/contact_policy.rb` | MERGE_REAL | 8 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/policies/contact_policy.rb` = só adição upstream | — |
| 65 | `app/controllers/public/api/v1/portals/base_controller.rb` | MERGE_REAL | 8 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/public/api/v1/portals/base_controller.rb` = só adição upstream | — |
| 66 | `app/builders/v2/reports/conversations/base_report_builder.rb` | PEGOU_DELES | 7 | **OK** | nada — AVG_METRICS/COUNT_METRICS foram substituídos pelo `Reports::ReportMetricRegistry`, que contém nossa métrica | `report_metric_registry.rb:58-63` | — |
| 67 | `lib/captain/summary_service.rb` | MERGE_REAL | 7 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/captain/summary_service.rb` = só adição upstream | — |
| 68 | `Gemfile` | MERGE_REAL | 7 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- Gemfile` = só adição upstream | — |
| 69 | `app/views/api/v1/models/_inbox.json.jbuilder` | MERGE_REAL | 7 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/views/api/v1/models/_inbox.json.jbuilder` = só adição upstream | — |
| 70 | `app/services/whatsapp/incoming_message_service_helpers.rb` | MERGE_REAL | 7 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/whatsapp/incoming_message_service_helpers.rb` = só adição upstream | — |
| 71 | `app/views/layouts/portal.html.erb` | PEGOU_DELES | 6 | **PERDA** | `<title>SPX - CHAT</title>` fixo do portal. (O favicon fallback `/brand-assets/logo_thumbnail.svg` FOI reaplicado no partial novo) | MERGE == DELES; o título voltou a `@portal.display_title(@locale)` em `app/views/layouts/_portal_head.html.erb:19` | Decidir: manter display_title (recomendado) ou reaplicar o hardcode no partial (patch 2) |
| 72 | `app/services/messages/mention_service.rb` | MERGE_REAL | 6 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/messages/mention_service.rb` = só adição upstream | — |
| 73 | `app/presenters/conversations/event_data_presenter.rb` | MERGE_REAL | 6 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/presenters/conversations/event_data_presenter.rb` = só adição upstream | — |
| 74 | `app/models/concerns/activity_message_handler.rb` | MERGE_REAL | 6 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/concerns/activity_message_handler.rb` = só adição upstream | — |
| 75 | `lib/redis/redis_keys.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/redis/redis_keys.rb` = só adição upstream | — |
| 76 | `.env.example` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- .env.example` = só adição upstream | — |
| 77 | `app/services/automation_rules/conditions_filter_service.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/automation_rules/conditions_filter_service.rb` = só adição upstream | — |
| 78 | `app/services/auto_assignment/assignment_service.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/auto_assignment/assignment_service.rb` = só adição upstream | — |
| 79 | `app/models/inbox_member.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/inbox_member.rb` = só adição upstream | — |
| 80 | `app/models/conversation_participant.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/conversation_participant.rb` = só adição upstream | — |
| 81 | `app/models/concerns/auto_assignment_handler.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/concerns/auto_assignment_handler.rb` = só adição upstream | — |
| 82 | `app/jobs/data_import_job.rb` | MERGE_REAL | 5 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/data_import_job.rb` = só adição upstream | — |
| 83 | `app/controllers/api/v1/accounts/notifications_controller.rb` | PEGOU_DELES | 4 | **OK** | nada — o caller acompanhou a nova assinatura; ganhou escopo por conta em `fetch_notification` | `notifications_controller.rb:44-46, 72` | — |
| 84 | `lib/captain/base_task_service.rb` | MERGE_REAL | 4 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/captain/base_task_service.rb` = só adição upstream | — |
| 85 | `app/services/whatsapp/oneoff_campaign_service.rb` | MERGE_REAL | 4 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/whatsapp/oneoff_campaign_service.rb` = só adição upstream | — |
| 86 | `app/models/macro.rb` | MERGE_REAL | 4 | **OK** | nada — `assign_ai_agent` sobreviveu; a linha só foi requebrada para caber `remove_assigned_agent` do upstream | `macro.rb:33-35` | — |
| 87 | `app/controllers/api/v2/accounts/reports_controller.rb` | MERGE_REAL | 4 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v2/accounts/reports_controller.rb` = só adição upstream | — |
| 88 | `app/controllers/api/v1/accounts/assignable_agents_controller.rb` | MERGE_REAL | 4 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/assignable_agents_controller.rb` = só adição upstream | — |
| 89 | `app/controllers/api/v1/accounts/agents_controller.rb` | MERGE_REAL | 4 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/agents_controller.rb` = só adição upstream | — |
| 90 | `app/builders/notification_builder.rb` | MERGE_REAL | 4 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/notification_builder.rb` = só adição upstream | — |
| 91 | `app/jobs/inboxes/bulk_auto_assignment_job.rb` | APAGADO | 4 | **OK** | nada — o upstream apagou o job legado e o substituiu por `AutoAssignment::PeriodicAssignmentJob`, que NÓS já tínhamos. O filtro `assignee_agent_bot_id: nil` que era nossa customização está preservado no substituto | `auto_assignment/assignment_service.rb:38, 47`; `config/initializers/sidekiq.rb:47` destrói o cron órfão | Nenhuma; só notar que o cron caiu de 15min para 30min e o novo job exige `joins(:assignment_policy)` |
| 92 | `lib/captain/reply_suggestion_service.rb` | MERGE_REAL | 3 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- lib/captain/reply_suggestion_service.rb` = só adição upstream | — |
| 93 | `app/dispatchers/async_dispatcher.rb` | MERGE_REAL | 3 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/dispatchers/async_dispatcher.rb` = só adição upstream | — |
| 94 | `app/builders/v2/reports/team_summary_builder.rb` | MERGE_REAL | 3 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/v2/reports/team_summary_builder.rb` = só adição upstream | — |
| 95 | `app/builders/v2/reports/inbox_summary_builder.rb` | MERGE_REAL | 3 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/v2/reports/inbox_summary_builder.rb` = só adição upstream | — |
| 96 | `app/builders/v2/reports/agent_summary_builder.rb` | MERGE_REAL | 3 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/builders/v2/reports/agent_summary_builder.rb` = só adição upstream | — |
| 97 | `lib/webhooks/trigger.rb` | MERGE_REAL | 2 | **RISCO** | nada nosso (`ActivityMessageJob.perform_later(conversation.id, …)` sobreviveu); o upstream trocou RestClient por SafeFetch (SSRF filter, default bloqueia rede privada) | `trigger.rb:44-53`; `SafeFetch.allow_private_network?` default false em `lib/safe_fetch.rb:38` | Setar `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` no .env de cada VM da frota que tenha webhook/agent bot em rede interna (patch 5) |
| 98 | `app/views/api/v1/models/_team.json.jbuilder` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/views/api/v1/models/_team.json.jbuilder` = só adição upstream | — |
| 99 | `app/services/twilio/oneoff_sms_campaign_service.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/twilio/oneoff_sms_campaign_service.rb` = só adição upstream | — |
| 100 | `app/services/sms/oneoff_sms_campaign_service.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/sms/oneoff_sms_campaign_service.rb` = só adição upstream | — |
| 101 | `app/services/action_service.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/services/action_service.rb` = só adição upstream | — |
| 102 | `app/policies/inbox_policy.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/policies/inbox_policy.rb` = só adição upstream | — |
| 103 | `app/models/data_import.rb` | MERGE_REAL | 2 | **RISCO** | nada nosso; o model ganhou 11 colunas novas e 3 associações (`DataImportItem`/`Mapping`/`Error`) | `data_import.rb:6-24, 34-38` | Confirmar com o executor de db/ que as migrations do import Intercom entraram — sem elas o model quebra em uso |
| 104 | `app/models/concerns/avatarable.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/concerns/avatarable.rb` = só adição upstream | — |
| 105 | `app/mailers/conversation_reply_mailer.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/mailers/conversation_reply_mailer.rb` = só adição upstream | — |
| 106 | `app/mailers/conversation_reply_mailer_helper.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/mailers/conversation_reply_mailer_helper.rb` = só adição upstream | — |
| 107 | `app/mailers/administrator_notifications/integrations_notification_mailer.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/mailers/administrator_notifications/integrations_notification_mailer.rb` = só adição upstream | — |
| 108 | `app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb` = só adição upstream | — |
| 109 | `app/jobs/account/contacts_export_job.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/jobs/account/contacts_export_job.rb` = só adição upstream | — |
| 110 | `app/controllers/tiktok/callbacks_controller.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/tiktok/callbacks_controller.rb` = só adição upstream | — |
| 111 | `app/controllers/platform/api/v1/agent_bots_controller.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/platform/api/v1/agent_bots_controller.rb` = só adição upstream | — |
| 112 | `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/devise_overrides/omniauth_callbacks_controller.rb` = só adição upstream | — |
| 113 | `app/controllers/api/v1/accounts/portals_controller.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/portals_controller.rb` = só adição upstream | — |
| 114 | `app/controllers/api/v1/accounts/callbacks_controller.rb` | MERGE_REAL | 2 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/callbacks_controller.rb` = só adição upstream | — |
| 115 | `app/builders/v2/reports/base_summary_builder.rb` | MERGE_REAL | 2 | **OK** | nada — a query SQL manual virou `Reports::DataSource`, e `@avg_first_response_time_after_assignment` continua sendo exposto | `base_summary_builder.rb:12-20` | — |
| 116 | `app/builders/account_builder.rb` | MERGE_REAL | 2 | **OK** | nada — `locale: @locale.presence || I18n.locale.to_s` (nossa conta nova em pt-BR) sobreviveu; a linha só ganhou `custom_attributes` do upstream | `account_builder.rb:47-51` | — |
| 117 | `app/models/channel/whatsapp.rb` | MERGE_REAL | 1 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/models/channel/whatsapp.rb` = só adição upstream | — |
| 118 | `app/listeners/agent_bot_listener.rb` | MERGE_REAL | 1 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/listeners/agent_bot_listener.rb` = só adição upstream | — |
| 119 | `app/controllers/dashboard_controller.rb` | MERGE_REAL | 1 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/dashboard_controller.rb` = só adição upstream | — |
| 120 | `app/controllers/api/v1/accounts/teams_controller.rb` | MERGE_REAL | 1 | **OK** | nada — 0 linhas nossas ausentes no MERGE (varredura léxica) e nenhuma mudança de contrato detectada | `git diff f26db6ee81 93571c69db -- app/controllers/api/v1/accounts/teams_controller.rb` = só adição upstream | — |
| 121 | `app/builders/v2/reports/timeseries/average_report_builder.rb` | APAGADO | 1 | **OK** | nada — o upstream unificou Average/Count em `V2::Reports::Timeseries::ReportBuilder`; nossa métrica `avg_first_response_time_after_assignment` foi migrada para o registry novo | `app/services/reports/report_metric_registry.rb:58-63` (raw_event_name: :first_response_after_assignment) | Nenhuma. Nota: a métrica não tem `rollup_metric`; hoje inofensivo porque `Reports::DataSource.for` sempre devolve `RawDataSource` (TODO no upstream) |


_(o único item marcado `N/A` na tabela, `app/services/search_service.rb`, não faz parte dos 121 —
é um achado adjacente encontrado durante a auditoria e está descrito no patch 7.)_

---

## 4. CORREÇÕES PROPOSTAS, EM ORDEM DE GRAVIDADE

Nenhum patch abaixo foi aplicado. Esta auditoria foi somente-leitura sobre o repositório.

### Patch 0 — DADO (fora da minha área, mas bloqueia o merge inteiro)

`db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb` **não pode rodar na frota**.
Antes de qualquer `db:migrate`, a migration precisa ser neutralizada e o estado `pending` reposto no
enum de `enterprise/app/models/captain/assistant_response.rb`, junto com a tela `Pending.vue`.
Encaminhar para os executores de `db/`, `enterprise/` e front — os três precisam casar.

---

### Patch 1 — PERDA · `lib/integrations/openai/openai_prompts/summary.liquid`

**Por que importa:** os outros quatro prompts irmãos (`reply.liquid`, `improve.liquid`,
`tone_rewrite.liquid`, `fix_spelling_grammar.liquid`) **mantiveram** nossa instrução pt-BR no merge.
Só o `summary` perdeu — o que indica acidente de merge, não decisão. Sem ela, o resumo de conversa
volta a sair em inglês para cliente brasileiro.

Substituir as linhas **20 a 28** do arquivo no MERGE por:

```diff
--- a/lib/integrations/openai/openai_prompts/summary.liquid
+++ b/lib/integrations/openai/openai_prompts/summary.liquid
@@ -17,12 +17,14 @@
 13. Do not insert your own opinions about the conversation.
 
 
-Use markdown with the following format. Translate all section headings to match the reply language:
+**IMPORTANT — LANGUAGE**: Reply in Brazilian Portuguese (pt-BR). All section headers and content MUST be in Portuguese. Translate everything — never use English.
 
-**Customer Intent**
+Reply as a markdown using the following format with Portuguese headers:
 
-**Conversation Summary**
+**Intenção do cliente**
 
-**Action Items**
+**Resumo da conversa**
 
-**Follow-up Items**
+**Itens de ação**
+
+**Pendências**
```

---

### Patch 2 — PERDA · `app/views/layouts/_portal_head.html.erb` (título do portal)

O merge pegou `portal.html.erb` byte-idêntico ao upstream. O favicon fallback ChatSPX **foi**
reaplicado no partial novo (`_portal_head.html.erb:25`), mas o título voltou a `@portal.display_title`.

**Recomendação: NÃO reverter.** Nosso hardcode fazia *todo* portal de *todo* cliente da frota se
chamar "SPX - CHAT" na aba do navegador — `display_title` é o comportamento correto para um produto
multi-cliente. Registrar como decisão consciente, não como pendência.

Se ainda assim quiserem o hardcode de volta, é uma linha em `app/views/layouts/_portal_head.html.erb:19`:

```diff
-  <title><%= @portal.display_title(@locale) %></title>
+  <title>SPX - CHAT</title>
```

---

### Patch 3 — PERDA · `app/controllers/swagger_controller.rb`

O merge repôs o gate de ambiente do upstream **e manteve** nosso `authenticate_docs!`, que virou
código morto: em produção o `respond` responde 404 antes de a Basic Auth servir para qualquer coisa.
O hardening de path traversal que o upstream trouxe (linhas 6-9 e o `delete_prefix('/')` no
`derived_path`) é bom e deve ser preservado.

```diff
--- a/app/controllers/swagger_controller.rb
+++ b/app/controllers/swagger_controller.rb
@@ -2,15 +2,12 @@ class SwaggerController < ApplicationController
   before_action :authenticate_docs!
 
   def respond
-    if Rails.env.development? || Rails.env.test?
-      swagger_root = Rails.root.join('swagger')
-      file_path = swagger_root.join(derived_path).cleanpath
+    swagger_root = Rails.root.join('swagger')
+    file_path = swagger_root.join(derived_path).cleanpath
 
-      return head :not_found unless file_path.to_s.start_with?("#{swagger_root}/") && file_path.file?
+    return head :not_found unless file_path.to_s.start_with?("#{swagger_root}/") && file_path.file?
 
-      render inline: file_path.read
-    else
-      head :not_found
-    end
+    render inline: file_path.read
   end
```

`authenticate_docs!` já é o padrão seguro: sem `SWAGGER_DOCS_PASSWORD` definida, ele devolve 404 em
produção por conta própria (linha 25). Remover o gate não abre a doc por acidente.

**Aceite:** com `SWAGGER_DOCS_PASSWORD` **ausente**, `GET /swagger` em `RAILS_ENV=production` deve
responder **404**; com ela definida, deve responder **401** sem credencial e **200** com a credencial
correta; e `GET /swagger/*.json` deve responder **200 sem credencial** nos dois casos.

---

### Patch 4 — RISCO · `app/jobs/notification/delete_notification_job.rb`

O merge reverteu nossa conversão AR→ID (commit `87095e111b`, "Sidekiq: 29 jobs convertidos AR objects
→ IDs"). Varri **todos os jobs da área**: este é o **único** revertido — os outros 10 mantiveram a
assinatura por ID. O escopo por conta que o upstream trouxe é uma melhoria e deve ser mantido.

```diff
--- a/app/jobs/notification/delete_notification_job.rb
+++ b/app/jobs/notification/delete_notification_job.rb
@@ -1,14 +1,18 @@
 class Notification::DeleteNotificationJob < ApplicationJob
   queue_as :low
 
-  def perform(user, account, type: :all)
-    notifications = user.notifications.where(account_id: account.id)
+  def perform(user_id, account_id, type: :all)
+    user = User.find_by(id: user_id)
+    return unless user
+
+    notifications = user.notifications.where(account_id: account_id)
 
     ActiveRecord::Base.transaction do
       if type == :all
         notifications.destroy_all
       elsif type == :read
         notifications.where.not(read_at: nil).destroy_all
       end
     end
   end
 end
```

E o caller, em `app/controllers/api/v1/accounts/notifications_controller.rb:44-46`:

```diff
-      ::Notification::DeleteNotificationJob.perform_later(Current.user, Current.account, type: :read)
+      ::Notification::DeleteNotificationJob.perform_later(Current.user.id, Current.account.id, type: :read)
     else
-      ::Notification::DeleteNotificationJob.perform_later(Current.user, Current.account, type: :all)
+      ::Notification::DeleteNotificationJob.perform_later(Current.user.id, Current.account.id, type: :all)
```

**Aceite:** enfileirar o job, apagar o `User` antes de ele rodar, e o job deve terminar sem levantar
`ActiveJob::DeserializationError` (com a versão do merge, levanta).

---

### Patch 5 — RISCO OPERACIONAL · SSRF filter nos webhooks (nenhuma linha de código)

`lib/webhooks/trigger.rb` deixou de usar `RestClient` e passou a usar `SafeFetch`, que roda o
`SsrfFilter`. O default bloqueia rede privada (`lib/safe_fetch.rb:38`), e a falha é **silenciosa**:
cai em `handle_failure`, que só escreve `Rails.logger.warn`.

Isso atinge, em cada VM da frota: webhooks de conta, webhooks de API inbox e **agent bots** que
apontem para host/IP privado — WAHA interna, n8n interno, receptor local, qualquer `192.168.x`.

**Correção:** antes de subir o merge, adicionar ao `.env` de cada VM que tenha esse caso:

```
SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true
```

**Aceite:** com a variável ausente, um webhook para `http://192.168.8.232/...` deve falhar com
`SafeFetch::UnsafeUrlError`; com ela em `true`, deve entregar (HTTP 2xx no destino). Sem executar
esse teste, o item continua sendo afirmação, não verificação.

Levantamento a fazer antes do deploy (é o mecanismo que fecha o aceite):

```sql
SELECT id, account_id, url FROM webhooks
 WHERE url ~ '(^https?://(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.|localhost))';
SELECT id, account_id, name, outgoing_url FROM agent_bots WHERE outgoing_url IS NOT NULL;
```

---

### Patch 6 — RISCO · 4 hooks `prepend_mod_with` do upstream descartados pelo merge

| arquivo (CE) | módulo enterprise em v4.16.2 | módulo entrou no MERGE? |
|---|---|---|
| `app/finders/message_finder.rb` | `enterprise/app/finders/enterprise/message_finder.rb` | não |
| `app/jobs/webhooks/whatsapp_events_job.rb` | `enterprise/app/jobs/enterprise/webhooks/whatsapp_events_job.rb` | não |
| `app/models/channel/twilio_sms.rb` | `enterprise/app/models/enterprise/channel/twilio_sms.rb` | não |
| `app/services/whatsapp/providers/whatsapp_cloud_service.rb` | `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb` | não |

A resolução foi **coerente** (hook e módulo caíram juntos), então **nada quebra hoje** — nenhum
`prepend_mod_with` ficou apontando para módulo inexistente e nenhum módulo ficou órfão. O custo é
que quatro features enterprise da v4.16.2 não entraram e que, no próximo merge de upstream, esses
quatro arquivos conflitam de novo.

**Ação:** nenhuma alteração de código obrigatória. Registrar a divergência deliberada para o próximo
merge. Se em algum momento um desses módulos enterprise for trazido, o hook precisa vir junto — sem
ele o módulo é código morto (é exatamente o que aconteceu no patch 7).

---

### Patch 7 — Achado adjacente (não é regressão do merge) · `Enterprise::SearchService` órfão

Contagem de `prepend_mod_with` em `app/services/search_service.rb`: **BASE=1, NOSSO=0, DELES=1, MERGE=0**.
Foi o **nosso lado** que removeu o hook (não o merge; o merge só preservou nossa versão). Mas
`enterprise/app/services/enterprise/search_service.rb` continua no repositório, com customização
nossa em pt-BR (filtro de busca por conversa específica), e **nunca é carregado** — o único caller é
`app/controllers/api/v1/accounts/search_controller.rb:25`, que instancia `SearchService` puro.

Duas saídas, ambas de uma linha; a escolha é de produto, não de merge:

```ruby
# (a) reativar o módulo enterprise — reintroduzir no fim de app/services/search_service.rb:
SearchService.prepend_mod_with('SearchService')
```

ou apagar `enterprise/app/services/enterprise/search_service.rb`, se a busca avançada foi mesmo
descontinuada quando reescrevemos `message_base_query` no CE.

**Aceite:** buscar dentro de uma conversa específica (`params[:conversation_id]`) e conferir se o
resultado vem restrito àquela conversa (comportamento do CE atual) ou passa pelo caminho enterprise.

---

## 5. Notas cruzadas para outros executores

Achados fora da minha área que caíram no caminho e têm consequência direta:

| para | achado | evidência |
|---|---|---|
| `db/` + `config/` | as 2 migrations de unread counts **reaproveitam bits já usados** do bitmask: `20260508000000_repurpose_channel_twitter_flag_…` e `20260629000000_repurpose_quoted_email_reply_flag_…`. Conta que tenha `channel_twitter` ou `quoted_email_reply` ligados passa a ter as flags novas ligadas sem pedir | nomes das migrations no MERGE |
| `db/` | `app/models/data_import.rb` ganhou 11 colunas e 3 associações (`DataImportItem`/`Mapping`/`Error`); `app/models/team.rb` expõe `icon`/`icon_color`; `app/models/inbox.rb` referencia `email_templates` e `InboxBrandedEmailLayoutable` — sem as migrations correspondentes, esses models quebram em uso | `data_import.rb:6-38`, `team.rb:83-88`, `inbox.rb:49,74` |
| `config/` | `Gemfile` subiu `sidekiq-cron` de `>= 1.12.0` para `>= 2.4.0` (**major**) e `puma` para `~> 7.2` (**major**). Ambos afetam boot/deploy da frota e precisam de validação antes do rollout | `Gemfile:78, 139` |
| front | contrato de signup mudou: cadastro web não autenticado responde `{email: ...}` sem auth headers | `accounts_controller.rb:47-59` |
| front | `campaign_status` ganhou o valor `processing`; conferir se a listagem de campanhas o reconhece | `campaign.rb:52` |

---

## 6. Contagem final

| veredito | arquivos |
|---|---|
| **OK** | 104 |
| **RISCO** | 14 |
| **PERDA** | 3 |
| **DADO** | 0 *(na minha área; o único DADO do merge, `assistant_response.rb`, é de `enterprise/` — confirmado em 2.1)* |
| **total** | **121** |

Por classe da triagem, todos os obrigatórios foram cobertos individualmente:
**APAGADO 2/2** · **PEGOU_DELES 5/5** · **PEGOU_NOSSO 2/2** · **MERGE_REAL 112/112**.

**COBERTURA: 121 de 121 arquivos da área auditados.**

### Leitura de uma linha

O merge do Ruby de aplicação está **substancialmente bem resolvido**: os dois focos mais caros deste
fork — os 9 contadores em uma query do `conversation_finder.rb` (304 linhas nossas, mexeu 1) e todo o
WhatsApp de grupos (18 de 19 arquivos Ruby byte-idênticos ao nosso) — **saíram intactos**, e quem
resolveu o merge reenxertou à mão nossos gates de conta, nossa métrica de relatório e o branding dos
e-mails dentro das estruturas novas do upstream. As 3 perdas são pequenas e pontuais (um prompt de
IA em pt-BR, o título do portal, a doc da API em produção). O que realmente ameaça a frota **não
está nesta área**: é a migration que apaga FAQ pendente (2.1) e o SSRF filter dos webhooks (patch 5).
