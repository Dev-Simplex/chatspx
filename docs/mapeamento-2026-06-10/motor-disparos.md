# Mapeamento — Motor de disparos em massa SPX (Tozi)

> Área: motor-disparos · Branch `paulao` · Levantado em 2026-06-10 por leitura direta do código local.
> Escopo: motor PRÓPRIO do SPX (não o blaster nativo do Chatwoot). Camada 100% OSS (`app/`, `lib/tasks/`, `scripts/`) — busca em `enterprise/` por `Spx|Tozi|Disparo` só retorna Captain tools (funil/copilot), nenhum override do motor.

---

## 1. Inventário de componentes

| Componente | Path | Papel |
|---|---|---|
| Job de disparo (1 lead) | `app/jobs/spx/tozi/disparo_lead_job.rb` (178 linhas) | Cria/reusa ficha+conversa, atribui corretor, envia HSM |
| Job de follow-up (1 conversa) | `app/jobs/spx/tozi/followup_hsm_job.rb` (41 linhas) | HSM `tozi_followup_lanc` NA conversa existente |
| Rake tasks | `lib/tasks/spx_tozi.rake` | `setup_funnel`, `create_templates`, `disparo`, `disparo_teste`, `backfill_funnel` |
| Scripts de operação | `scripts/spx/tozi/` (20 arquivos, ver `README.md`) | Ingestão (Python), motores de enfileiramento (Ruby `rails runner`), criação de templates (Graph API), relatório, consolidação |
| Consolidação one-shot | `scripts/spx/tozi/consolida_conversas_duplicadas.rb` | Fusão das 275 duplicatas (rodado em prod 08/06) |
| Catálogo de templates | `docs/TEMPLATES-DISPARO-TOZI.md` | 23 templates APPROVED/MARKETING/pt_BR, IDs Meta, botões |
| Relatório consolidado | `docs/RELATORIO-DISPAROS-TOZI-2026-06-08.md` | 7.249 HSM, 84,4% alcance, 24,2% resposta, ~US$382 |
| Backlog defensivo | `docs/backlog/reconciliador-incoming-9-digito.md` | Proposta: preferir ficha da conversa mais recente quando 2+ fichas casam |
| Stats por campanha | `app/controllers/api/v1/accounts/campaigns_controller.rb:43-86` | `GET .../campaigns/:id/stats` agrega por `campaign_id` |
| Blaster nativo DESATIVADO | `app/models/campaign.rb:66-74` | `execute_campaign` p/ `Whatsapp` só loga; campanha âncora (`completed`) serve apenas como agregador de stats |

Infra de apoio (Chatwoot core usada pelo motor):
- `app/services/whatsapp/phone_number_normalization_service.rb` — reconcilia variantes de wa_id por país.
- `app/services/whatsapp/phone_normalizers/brazil_phone_normalizer.rb:24-30` — `variants(waid)` = `[waid, com_9 (13d), sem_9 (12d)]`.
- `app/services/contacts/brazil_phone_normalizer.rb:53-61` — adiciona o 9º dígito em E.164 (+55 com 10 dígitos → 11).
- `app/builders/contact_inbox_with_contact_builder.rb` — find-or-create de Contact+ContactInbox (L17 reusa ficha por `source_id`; L108-118 fallback por telefone normalizado).
- `app/builders/messages/message_builder.rb:124-126,148` — grava `template_params` em `messages.additional_attributes`.
- `app/services/whatsapp/send_on_whatsapp_service.rb:8-15,17-38` — `template_params` presente → `send_template_message`.
- `app/services/whatsapp/template_processor_service.rb:21-27` — só envia se o template estiver SINCRONIZADO e `approved` no canal (gotcha: `sync_templates` + restart do worker p/ limpar cache).
- `app/services/whatsapp/template_processor_service.rb:59-77` — `build_header_params` espera `media_url`+`media_type` (formato usado pelo header de imagem dos inquilinos).
- Fila: `queue_as :low` existe em `config/sidekiq.yml:24`.

---

## 2. Fluxo completo de um disparo

### 2.1 Ingestão (Python, local)
`scripts/spx/tozi/ingestao_tozi_v4.py` (venda) e `ingestao_inquilinos.py` (inquilinos):
- Normalização canônica = **DDD + últimos 8 dígitos** (colapsa DDI 55 e 9º dígito) — `ingestao_inquilinos.py:51-53`.
- Recuperações: trunk-0 (tira o 0), 9 dígitos sem DDD → assume 66, 8 dígitos → 66+9 (`norm_local`, L31-49). Valida DDD contra lista (L17-21).
- Dedup em camadas (`ingestao_inquilinos.py:93-115`): (1) blacklist corretores (`TODOS CORRETORES DE SINOP.csv`), (2) já-enviados (`sent_phones.txt`, extraído do DB), (3) **conversa ABERTA na inbox 91** (`open_phones.txt`) — **só na ingestão de inquilinos**, (4) dup interno. Saída: CSV `nome,telefone_e164,canonical`.

### 2.2 Enfileiramento (Ruby, `rails runner` na AWS)
Motores em `scripts/spx/tozi/disparo_*.rb` (ex.: `disparo_venda.rb`, `disparo_inq.rb`, `disparo_ab.rb`). Padrão comum:
- Relê o CSV (`/home/chatwoot/tozi_*.csv`) e re-deduplica AO VIVO contra o DB: `Conversation.where(inbox_id: 91).where("additional_attributes->>'source' = 'disparo_lancamento'")` → canonical do `contact.phone_number` (`disparo_venda.rb:49-53`). + filtro fake `(\d)\1{6,}` (L25-27) + dup interno.
- Round-robin de corretor: `assignee = BROKERS[j % BROKERS.size]` (`disparo_venda.rb:74`).
- **Decorrelação** template×corretor: `TEMPLATES[(j + j / BROKERS.size) % TEMPLATES.size]` (`disparo_venda.rb:75`, `disparo_inq.rb:59`) — cada corretor manda todos os templates. A/B usa `j % TEMPLATES.size` (split 50/50 por lead, `disparo_ab.rb:59` — a fórmula decorrelacionada quebrava com 1 corretor).
- Pacing: `Spx::Tozi::DisparoLeadJob.set(wait: (STEP * j).seconds).perform_later(...)` com `STEP=5` (`disparo_venda.rb:79-82`) → jobs caem no **Sidekiq ScheduledSet**.
- Campanha âncora: `Campaign` criada com `campaign_status: :completed` e `save!(validate: false)` (`disparo_venda.rb:31-45`) — nunca dispara o blaster nativo (guard em `app/models/campaign.rb:58-62`: `return if completed?`); só serve pra `campaign_id` agregar stats.
- `DRY=1` simula (imprime cruzamento corretor×template) sem enfileirar.
- A rake genérica `spx:tozi:disparo[csv,limit,dry_run,spread_min,template]` (`lib/tasks/spx_tozi.rake:142-212`) faz o mesmo com `spread_min` default 120 min e `dry_run` default TRUE — porém está **desatualizada** vs os scripts: não passa `campaign_id`, não tem dedup live, e usa `DISPARO_BROKERS=[128,126,127,131,125]` (L131) e só os 3 templates `tozi_lancamento_*` (L134-138). Os lotes reais de jun/2026 rodaram pelos scripts.

### 2.3 O job — `Spx::Tozi::DisparoLeadJob`
`app/jobs/spx/tozi/disparo_lead_job.rb`, `queue_as :low`, `INBOX_ID = 91` hardcoded (L12).

1. **Normalização do telefone** (`normalize_phone`, L100-107): só dígitos → prefixa `55` se 10-11 dígitos → `+` → `Contacts::BrazilPhoneNormalizer.normalize` adiciona o 9º dígito (sempre formato 13d "nosso").
2. **`resolved_source_id`** (L112-116, **fix 11b913531**): `Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)` — percorre as variantes `[waid, com_9, sem_9]` (`brazil_phone_normalizer.rb:24-30`) e devolve o `source_id` da **primeira ficha existente** (`phone_number_normalization_service.rb:24-28`); se nenhuma existe, devolve o waid 13d (contato novo). É o MESMO serviço que o incoming usa (`incoming_message_service_helpers.rb:50-52`) → disparo e reply convergem na mesma ficha.
3. **Ficha**: `ContactInboxWithContactBuilder` (L75-85) — reusa por `source_id` (builder L17); senão acha Contact por telefone (com fallback normalizado, builder L108-118) e cria a ficha. Marca `additional_attributes.source = 'disparo_lancamento'` no contato.
4. **`find_or_create_conversation`** (L121-143, **fix 11b913531**): busca POR CONTATO (`Conversation.where(inbox_id:, contact_id:)`) a conversa não-resolvida mais recente, senão a mais recente qualquer; se achou → `update!(assignee_id:)` (se diferente), `update!(campaign_id:)` (só se nil), `open!` (se não-aberta) e retorna. Cria nova **só se o contato nunca teve conversa**: `status: 'open'`, `assignee_id`, `campaign_id`, `additional_attributes: { source: 'disparo_lancamento', template: <nome> }` (L133-142). Honra o `lock_to_single_conversation=true` da inbox 91.
5. **`send_hsm`** (L149-164): monta o payload pro `Messages::MessageBuilder`:
   - `content` = espelho humano da transcrição, formatado do hash **`PREVIEWS`** (L17-54, 17 templates) com `%<n>s`=primeiro nome do lead e `%<a>s`=primeiro nome do corretor (`agent_first_name`, L145-147, fallback `'Guilherme'`). Template ausente do hash → fallback `'Oi %<n>s!'` (L155) — causa do incidente "mensagens estranhas" de 03/06 (era só o rótulo; o lead recebia o HSM completo).
   - `template_params` = `{name, language: 'pt_BR', processed_params: {body: {'1' => nome, '2' => corretor}}}` — `format` ignora chaves não usadas, então serve pra templates de 1 ou 2 variáveis (comentário L153).
   - **`NO_BODY_VAR`** (L58-62): templates de inquilinos têm corpo SEM variável; `tozi_inq_lancamento`/`tozi_inq_invest` = `:image` → `no_var_params` (L167-175) monta `processed_params.header = {media_url: INQ_IMAGE_URL, media_type: 'image'}` (formato exigido por `TemplateProcessorService#build_header_params`, `template_processor_service.rb:59-77`). `INQ_IMAGE_URL = 'https://tozi.chatspx.app/inq-mapa.jpeg'` (L56) — **asset off-git, hoje 404 em prod** (dropado num redeploy).
6. **Envio real**: `MessageBuilder` grava `template_params` em `messages.additional_attributes` (`message_builder.rb:124-126`) → `Whatsapp::SendOnWhatsappService#perform_reply` vê `template_params` → `send_template_message` (`send_on_whatsapp_service.rb:8-38`) → `TemplateProcessorService` localiza o template aprovado/sincronizado no canal (`template_processor_service.rb:21-27`) → `channel.send_template`. Status de entrega da Meta atualiza `messages.status` (sent/delivered/read/failed) + `external_error` (códigos 131026 sem-WhatsApp, 130472/131049 pacing).
7. **Erro**: rescue geral L90-91 — loga `[Disparo] falha tel=...` e não derruba a fila (best-effort).

### 2.4 Follow-up — `Spx::Tozi::FollowupHsmJob`
`app/jobs/spx/tozi/followup_hsm_job.rb`: recebe `conversation_id` (não telefone) → manda o HSM **dentro da conversa que já existe** (não cria ficha/conversa — por isso não duplica), `open!` se resolvida (L21), **mantém o assignee**, template fixo `tozi_followup_lanc` 1 variável (L11-14, 23-34).

Seleção de audiência nos scripts `followup_schedule.rb` / `followup_venda_schedule.rb`:
- Universo: `Conversation.where(inbox_id: 91, campaign_id: N, assignee_id: BROKERS)`.
- `reached` = convs com outgoing `delivered|read` (L17-18); `replied` = convs com incoming (L15-16); alvo = `reached - replied`.
- `already_fu` = convs que já receberam o follow-up, detectado por `messages.additional_attributes->'template_params'->>'name' = 'tozi_followup_lanc'` (L22-25) — idempotência entre rodadas.
- Interleave por corretor + cap (`TOTAL=600/400`), pacing 5s via `FollowupHsmJob.set(wait:)`.
- Limitação atual: **só corpo de texto** — não suporta header de imagem (por isso o follow-up com template de imagem ficou travado; Paulo mandou segurar).

### 2.5 Pausar / retomar
- Jobs futuros vivem no **`Sidekiq::ScheduledSet`** (efeito do `.set(wait:)`). Pausar = deletar do ScheduledSet por classe (`DisparoLeadJob` ou `FollowupHsmJob`) — `scripts/spx/tozi/README.md:33-34`. Não há comando versionado; é console.
- Retomar = rodar o motor de novo; o dedup live (já-enviados via `source='disparo_lancamento'` ou `already_fu`) exclui quem já recebeu.
- **Não há estado persistente de campanha** (nada de "pausada/em curso" em banco) — o controle é 100% manual.

---

## 3. O bug das duplicatas (9º dígito) e o fix

### Mecanismo do bug (job ANTIGO, pré-11b913531)
1. O job criava a ficha com `source_id` no formato PRÓPRIO: 13 dígitos com o 9 (`BrazilPhoneNormalizer`). E criava **sempre** uma `Conversation.create!` nova.
2. Pros números antigos, **a Meta entrega o wa_id na variante 12d** (sem o 9). O incoming (`incoming_message_base_service.rb:112-129`) resolve a ficha via `processed_waid` → `PhoneNumberNormalizationService`, que devolve a **primeira** ficha que casar na ordem `[waid, com_9, sem_9]` (`phone_number_normalization_service.rb:24-28`). Se já existia ficha 12d (histórico anterior de WhatsApp), o reply caía NELA — não na ficha 13d criada pelo disparo.
3. `set_conversation` com `lock_to_single_conversation` opera **por ficha**, não por contato: `@contact_inbox.conversations.last` (`incoming_message_base_service.rb:131-142`) → não achando conversa naquela ficha, criava conversa NOVA, sem assignee, sem histórico.
4. A `AutomationRule #53 'iniciar zerado'` (dado de prod: event `conversation_opened`, inboxes 61/62/91, zera assignee+team) desatribuía ao (re)abrir → o sintoma final: lead respondendo dias depois aparecia **"Não atribuída", sem corretor, sem histórico** — e a secretária não via a conversa do corretor por causa da custom role.
5. Saldo medido em prod: **275 contatos** com >1 conversa (203 com 2 fichas + 72 com 2 conversas na mesma ficha — estas pelo `Conversation.create!` incondicional).

### O fix (commit `11b913531`, 08/06, 40+/11-)
- **`resolved_source_id`** (job L112-116): o disparo passa a usar o MESMO algoritmo de reconciliação do incoming → se o contato já existe em qualquer variante, reusa aquela ficha; replies e disparos convergem.
- **`find_or_create_conversation`** (job L121-143): busca por `contact_id` (atravessa fichas) e reusa a conversa única, reabrindo+atribuindo; cria só se nunca existiu. Fecha a fonte dos "2 convs na mesma ficha".
- **Consolidação one-shot** (`scripts/spx/tozi/consolida_conversas_duplicadas.rb`): por contato com >1 conversa na inbox 91 (universo = contatos com `source='disparo_lancamento'`, L25-28): survivor = conversa com mais incoming, empate → mais recente (L38); move mensagens via `update_all` (L52); assignee = corretor do disparo mais recente (L40-41); status `open` + `last_activity_at` recalculado via `update_columns` (L58-62, **sem callbacks** — não dispara automation rules nem eventos); migra `campaign_id`/`source`/`template`; apaga notificações + `captain_assistant_logs` órfãos e as convs/fichas duplicadas com `delete` (L64-70); transação por contato; `MODE=validate` roda 1 contato com rollback (L79-88). Resultado em prod: 275 ok / 0 falhas / 810 msgs movidas / 298 convs + 203 fichas apagadas; bônus: corretor passou a ver o histórico inteiro no fio único.
- **Residual documentado** (`docs/backlog/reconciliador-incoming-9-digito.md`): o `PhoneNumberNormalizationService` ainda devolve a PRIMEIRA ficha que casar — se uma duplicata nascer por OUTRO caminho (import, outra integração), o reply pode cair na ficha "morta". Proposta: com 2+ matches, preferir a ficha da conversa mais recente. Prioridade baixa (fonte de novas duplicatas foi fechada).

---

## 4. Fragilidades e riscos

1. **Divergência repo↔prod (a mais grave).** Deploy AWS é não-git (branch `rollout`); o job em prod tinha 124 linhas (sem `NO_BODY_VAR`/inquilinos), o `followup_hsm_job.rb` SUMIU de prod num redeploy (`uninitialized constant`, restaurado via scp) e o commit `11b913531` **não está deployado** — cada redeploy da `rollout` re-dropa o código off-git e reabre a fábrica de duplicatas. O asset `public/inq-mapa.jpeg` (header dos `tozi_inq_*`) também sumiu (404) → envio de template de imagem falharia hoje.
2. **Filtro "conversa em atendimento" incompleto.** Só a ingestão de inquilinos exclui contatos com conversa ABERTA (camada 3, `ingestao_inquilinos.py:108-110`); os lotes de venda/locação não tinham essa camada → disparo podia atropelar atendimento humano vivo. Mesmo nos inquilinos: (a) cobre só `open` — `resolved`/`pending`/`snoozed` recente passam; (b) é snapshot (`open_phones.txt`) gerado na ingestão, stale na hora do disparo (que pode ser dias depois).
3. **Dedup ancorado em `source='disparo_lancamento'` hardcoded** (job L80/L141 e scripts) — qualquer envio fora do orquestrador (ex.: os ~11 HSM manuais de Adrian/Gelson) e conversas orgânicas ficam fora do dedup de "já-enviados".
4. **Sem idempotência por mensagem.** O job é idempotente por ficha/conversa, mas re-enfileirar o mesmo lead manda um 2º HSM no mesmo fio. O controle anti-duplo-envio é todo nos scripts (dedup live).
5. **`open!`/`update!` disparam automation rules de prod.** `find_or_create_conversation` atribui (CONVERSATION_UPDATED) e depois `open!` (CONVERSATION_OPENED, `conversation.rb:380-392`) — a mesma rule #53 que zera assignee ao abrir pode, em tese, desfazer a atribuição do disparo. As condições exatas da rule são dado de prod (não verificável no repo) — precisa conferir antes de confiar no reopen+assign.
6. **Conteúdo dos templates triplicado sem fonte única**: corpo aprovado na Meta, hash `PREVIEWS` do job, e scripts `create_*_templates.rb`. Template novo sem entrada no `PREVIEWS` → painel mostra o fallback `'Oi %<n>s!'` (incidente de 03/06). O doc `TEMPLATES-DISPARO-TOZI.md` é snapshot manual.
7. **Scripts e dados soltos**: motores foram rodados de `Downloads/` e `/tmp` na AWS (`fu_schedule.rb`), CSVs em `/home/chatwoot/`; `scripts/spx/tozi/` é arquivo-histórico com IDs/paths hardcoded, não um pipeline reproduzível.
8. **Hardcodes single-tenant**: `INBOX_ID=91`, IDs de corretor, nomes de template, `campaign_id` por título — generalização multi-cliente pendente (handoff 29/05).
9. **Rake `spx:tozi:disparo` desatualizada** vs scripts (sem `campaign_id`, sem dedup live, lista de brokers antiga incluindo Guilherme/Marcus) — risco de alguém usá-la achando que é o motor atual.
10. **Observabilidade fraca**: rescue engole erros com log de texto; falha só aparece em `messages.status/external_error`; cliques de botão contados por match exato de string (`report_data.rb:8-9,27-31`); a métrica do A/B (resposta qualificada) nunca foi medida.
11. **`PhoneNumberNormalizationService` primeira-ficha-que-casar** (residual, ver §3) — hot-path de TODO incoming WhatsApp.
12. **Follow-up sem suporte a header de imagem** (`FollowupHsmJob` só texto) — bloqueou a 2ª leva com template de imagem.

---

## 5. Ganchos para a IA orquestradora

- **Enfileiramento programático**: `Spx::Tozi::DisparoLeadJob.perform_later(nome:, telefone:, assignee_id:, template:, campaign_id:)` — a decisão de audiência/corretor/template/pacing já é externa ao job; uma IA pode assumir o papel dos scripts (decidir QUEM, QUANDO, COM QUAL template e PRA QUAL corretor) sem tocar no job.
- **Re-engajamento na conversa existente**: `Spx::Tozi::FollowupHsmJob.perform_later(conversation_id:, first:)` — primitiva pronta pra "follow-up de lead que parou de responder" fora da janela 24h (HSM), mantendo o corretor.
- **Telemetria consultável**: `conversations.campaign_id` + `additional_attributes.source/template`; `messages.additional_attributes.template_params.name` + `messages.status` (sent/delivered/read/failed) + `external_error` — é exatamente o que os scripts de follow-up usam pra calcular `reached - replied - already_fu`; uma IA pode usar a mesma álgebra como política de cadência.
- **Endpoint agregado**: `GET /api/v1/accounts/:id/campaigns/:id/stats` (`campaigns_controller.rb:12-14,43-86`) — total/alcance/lidas/falhas/replies/distribuição por corretor/códigos de falha/conversas recentes. Policy: admin (`campaign_policy.rb:22-24`).
- **Eventos Rails**: `CONVERSATION_OPENED/RESOLVED/STATUS_CHANGED` (`conversation.rb:380-392`) e `message_created` — pontos de escuta pra IA reagir a reply de disparo (já existe o precedente `Spx::Tozi::FunnelAutomationListener` do Bloco 3 movendo cards do funil por evento).
- **Criação programática de HSM**: `Whatsapp::TemplateManagementService` + rake `spx:tozi:create_templates` (`spx_tozi.rake:100-125`, idempotente list-then-skip) — IA pode propor/submeter templates novos; aprovação continua na Meta.
- **Cadência persistente alternativa**: `ScheduledMessages` já aceita `template_params` (Bloco 4) — candidato natural pra substituir o ScheduledSet do Sidekiq como agenda de disparo/cadência com estado em banco (pausável/cancelável por linha, cancel-on-reply).
- **Reconciliação de identidade**: `Whatsapp::PhoneNumberNormalizationService` é o ponto único de verdade pra "mesmo humano, variantes de número" — qualquer módulo de IA que crie conversa outbound DEVE passar por `resolved_source_id` + `find_or_create_conversation` (ou por uma extração desses helpers pra um service reutilizável, ex. `app/services/spx/` genérico).

## 6. Questões em aberto

1. Condições exatas da AutomationRule #53 em prod e sua interação com o `open!`+assign do job (risco de desatribuição do disparo no reopen).
2. O patch cirúrgico da frente 1 (`11b913531`) foi aplicado em prod? (STATE diz pendente de aval; cada redeploy da `rollout` re-dropa o código off-git.)
3. Recuperação do `inq-mapa.jpeg` (o anexo 411283 da resposta rápida `/interesse` é o mesmo mapa?) e inclusão de assets no fluxo de reconciliação `rollout`↔`paulao`.
4. Migrar a agenda de disparo de `Sidekiq::ScheduledSet` (volátil, console-only) para `ScheduledMessages`/tabela própria com estado persistente?
5. Generalizar o motor (tirar `INBOX_ID=91`, brokers e templates hardcoded) pra multi-cliente — pré-requisito pra IA orquestradora operar mais de uma conta.
6. Unificar a fonte de verdade dos corpos de template (Meta ↔ `PREVIEWS` ↔ docs) — hoje é sincronização manual em 3 lugares.
