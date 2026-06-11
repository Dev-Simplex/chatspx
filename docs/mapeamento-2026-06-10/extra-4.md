# Extra 4 — Memória durável do lead: feature_memory, feature_contact_attributes, merge de contatos e PII no to_llm_text

> Mapeamento baseado 100% em leitura do código local (branch `paulao`), com referências file:linha.
> Data: 2026-06-10. Nenhum arquivo modificado; produção não foi tocada.

---

## 1. O que exatamente chega ao prompt do runner v2 — notas entram ou só atributos?

### 1.1 Pipeline de construção do contexto

O runner v2 é o `Captain::Assistant::AgentRunnerService` (`enterprise/app/services/captain/assistant/agent_runner_service.rb`). O estado injetado no contexto do agente é montado em `build_state`/`build_conversation_state`:

- `CONVERSATION_STATE_ATTRIBUTES = %i[id display_id inbox_id contact_id status priority label_list custom_attributes additional_attributes]` — `agent_runner_service.rb:9-12`
- `CONTACT_STATE_ATTRIBUTES = %i[id name email phone_number identifier contact_type custom_attributes additional_attributes]` — `agent_runner_service.rb:14-17`
- `CONTACT_INBOX_STATE_ATTRIBUTES = %i[id hmac_verified]` — `agent_runner_service.rb:19`
- `CAMPAIGN_STATE_ATTRIBUTES = %i[id title message campaign_type description]` — `agent_runner_service.rb:21`
- Montagem: `state[:contact] = slice_attrs(@conversation.contact, CONTACT_STATE_ATTRIBUTES)` — `agent_runner_service.rb:158`; `slice_attrs` é um `attributes.slice` puro (`:163-165`).

**Conclusão direta: as notas (`Note`) NÃO fazem parte do state.** O slice pega apenas colunas do registro `contacts`. Não há nenhum ponto no runner v2 que carregue `contact.notes`.

### 1.2 Gate do contato no prompt: `feature_contact_attributes`

`enterprise/app/models/concerns/agentable.rb:15-29` (`agent_instructions`):

```ruby
enhanced_context = enhanced_context.merge(
  conversation: state[:conversation] || {},
  contact: config['feature_contact_attributes'].present? ? state[:contact] : nil,   # agentable.rb:23
  campaign: state[:campaign] || {}
)
```

- O **contato** só entra no prompt se `config['feature_contact_attributes']` estiver truthy no assistant.
- A **conversa** e a **campanha** entram SEMPRE (sem flag) — `agentable.rb:22` e `:24`.
- O mesmo gate vale pra scenarios (Júlia/Vendas #5), porque `Concerns::Agentable` é incluído em `Captain::Assistant` (`enterprise/app/models/captain/assistant.rb:22`) e `Captain::Scenario` (`enterprise/app/models/captain/scenario.rb:25`) — e o `config` dos scenarios delega pro assistant? Não: o scenario usa `config` herdado de... atenção: `Scenario` delega `temperature, feature_faq, feature_memory, product_name, response_guidelines, guardrails` ao assistant (`scenario.rb:54`) mas **não delega `config`**; em `agentable.rb:23` o `config` lido é `state[:assistant_config]` vindo do contexto do runner (`agent_runner_service.rb:147` — `assistant_config: @assistant.config`), portanto o flag avaliado é sempre o do **assistant** (Clara), tanto no agente orquestrador quanto nos scenario agents.

### 1.3 O que o template Liquid renderiza

Renderização: `Captain::PromptRenderer.render(template_name, context)` (`agentable.rb:28`; `enterprise/lib/captain/prompt_renderer.rb:5-9`), templates em `enterprise/lib/captain/prompts/`.

**`snippets/contact.liquid:1-17`** — o que de fato aparece no system prompt quando o flag está ligado:
- Contact ID, Name, Email, Phone, Identifier, Type
- TODOS os pares de `contact.custom_attributes` (loop linhas 8-12)
- TODOS os pares de `contact.additional_attributes` (loop linhas 13-17) — inclui `source: disparo_lancamento` gravado pelo `DisparoLeadJob` (`app/jobs/spx/tozi/disparo_lead_job.rb:80`)

**`snippets/conversation.liquid:1-18`** — entra SEMPRE (sem flag):
- display_id, contact_id, status, priority, labels
- TODOS os `conversation.custom_attributes` (linhas 9-13) — é AQUI que a memória escrita pela tool `salvar_info_lead` chega de volta ao agente: `tozi_status_lead` e `sobre_cliente` (`enterprise/lib/captain/tools/salvar_info_lead_tool.rb:17-20`), além de `followup_token/followup_count/followup_status` da cadência.
- TODOS os `conversation.additional_attributes` (linhas 14-18) — inclui `source: 'disparo_lancamento'` e `template: <nome do HSM>` gravados pelo disparo (`app/jobs/spx/tozi/disparo_lead_job.rb:141`). Ou seja, uma Clara conectada SABE que a conversa nasceu de disparo e qual template recebeu — hook de orquestração já pronto.

Os templates `assistant.liquid:22-38` e `scenario.liquid:15-31` renderizam os snippets sob "# Current Context" com `{% render 'contact' %}` apenas `{% if contact %}` — coerente com o gate do agentable.

### 1.4 Histórico de mensagens (a outra "memória")

`Captain::Conversation::ResponseBuilderJob#collect_previous_messages` (`enterprise/app/jobs/captain/conversation/response_builder_job.rb:64-83`): coleta **todas** as mensagens `incoming/outgoing` **não-privadas** da conversa atual (sem limite de quantidade — a constante `MAX_MESSAGE_LENGTH = 10_000` na linha 2 está **morta**, nenhum uso no arquivo nem no enterprise/). Notas privadas da conversa não entram (filtro `private: false`, linha 68). Notas do CONTATO também não.

Como a inbox 91 tem `lock_to_single_conversation=true`, a conversa única vira de fato a memória de longo prazo do lead — todo o histórico (incluindo HSMs de disparo e atendimento humano antigo) é reenviado ao LLM a cada turno. Pós-consolidação (810 mensagens movidas pra conversas únicas), threads longas = prompt grande + custo + risco de poluição de contexto (mesmo problema da conv 2159 de teste).

### 1.5 E o caminho v1 (`AssistantChatService`)?

`enterprise/app/services/captain/llm/assistant_chat_service.rb:46-53`: também injeta só atributos (`slice(:id, :name, :email, :phone_number, :identifier, :custom_attributes)`), gated por `@assistant&.feature_contact_attributes` (linha 48). Sem notas. Irrelevante em prod Tozi (Account 6 tem `captain_integration_v2`, `response_builder_job.rb:271-273` roteia pro v2).

### 1.6 Alguma tool do agente lê notas?

Não. As tools de agente vêm de `config/agents/tools.yml` (resolvidas em `enterprise/app/models/concerns/captain_tools_helpers.rb:45-55`): `add_contact_note`, `add_private_note`, `update_priority`, `add_label_to_conversation`, `faq_lookup`, `search_knowledge`, `resolve_conversation`, `handoff`, `buscar_imovel`, `enviar_fotos_imovel`, `salvar_info_lead`, `programar_followup`. A `AddContactNoteTool` só **escreve** (`enterprise/lib/captain/tools/add_contact_note_tool.rb:19-21` — `contact.notes.create!`). Nenhuma tool de agente lê `contact.notes` ou chama `contact.to_llm_text`.

Quem lê notas e entrega a um LLM são apenas:
- **Copilot** (assistente do atendente humano, não a Clara): `enterprise/app/services/captain/tools/copilot/get_contact_service.rb:12` e `search_contacts_service.rb:22` — ambos via `contact.to_llm_text`.
- **O próprio gerador de notas** (`contact_notes_service.rb:9`) — manda as notas existentes como contexto pro LLM não duplicar ("if its not already present in contact notes", `system_prompts_service.rb:64`).

### 1.7 Veredito da pergunta 1

**Só atributos entram no prompt do runner v2; notas NÃO entram em nenhum caminho.** O `feature_memory` produz uma memória **write-only do ponto de vista da Clara**: o CaptainListener grava notas no resolved, mas o agente nunca as lê de volta. As notas são consumíveis apenas pelo Copilot (humano) e pela UI de contato. A memória durável que a Clara de fato enxerga hoje é: (a) `conversation.custom_attributes` escritos pela `salvar_info_lead`, (b) `contact.custom_attributes`/`additional_attributes` (se `feature_contact_attributes` on), (c) o histórico integral da conversa única.

---

## 2. O gatilho do feature_memory: CaptainListener → ContactNotesService

`enterprise/app/listeners/captain_listener.rb:4-12`:

```ruby
def conversation_resolved(event)
  conversation = extract_conversation_and_account(event)[0]
  assistant = conversation.inbox.captain_assistant          # :6
  return unless conversation.inbox.captain_active?          # :8
  Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes if assistant.config['feature_memory'].present?  # :10
  Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate if assistant.config['feature_faq'].present?   # :11
end
```

- Registrado no `Enterprise::AsyncDispatcher` (`enterprise/app/dispatchers/enterprise/async_dispatcher.rb:2-6`) — roda async no evento `conversation.resolved`.
- **Duplo gate:** `captain_active?` (`enterprise/app/models/enterprise/inbox.rb:14-16` = `captain_assistant.present? && more_responses?`) **e** `feature_memory` no config.
- **Estado atual Tozi: o listener é no-op.** Clara está desconectada da inbox 91 (CaptainInbox destruído em 02/06) → `captain_active?` = false → nem nota nem FAQ são geradas em NENHUM resolve, independente do flag. Religar a Clara reativa este listener junto — efeito colateral do go-live que ninguém mapeou: cada resolve de conversa da inbox 91 passa a disparar 1-2 chamadas LLM extras (notas + FAQ) se os flags estiverem ligados.

`Captain::Llm::ContactNotesService` (`enterprise/app/services/captain/llm/contact_notes_service.rb`):
- Input: `"#Contact\n\n#{@contact.to_llm_text} \n\n#Conversation\n\n#{@conversation.to_llm_text}"` (linha 9) — contato completo (com notas existentes, PII e histórico) + transcrição da conversa.
- Output: JSON `{ notes: [...] }` parseado (linhas 56-63) → `@contact.notes.create!(content: note)` por nota (linhas 12-16). Notas criadas **sem user** (autor nil; compare com o copilot `add_note_to_contact_service.rb:14` que seta `user: @user`).
- Prompt do gerador: `system_prompts_service.rb:61-73` — "note taker… actionable notes for the CRM", no idioma da conta (`locale_english_name`, `contact_notes_service.rb:52`).

**Achado — serviço órfão:** `Captain::Llm::ContactAttributesService` (`enterprise/app/services/captain/llm/contact_attributes_service.rb`) existe, monta o mesmo input (linha 9) e tem prompt pronto (`system_prompts_service.rb:75-87`, "slot the attributes available in the conversation into the attributes available in the contact"), mas:
- `generate_and_update_attributes` é stub: `# to implement the update attributes` (linhas 12-15) — gera e joga fora.
- **Nenhum call-site no repo inteiro** (grep `ContactAttributesService` só encontra a própria definição).
Ou seja: a extração automática de atributos do contato a partir da conversa (a "memória estruturada" ideal pra orquestração — renda, bairro de interesse, nicho) está 80% pronta e desligada. É o candidato natural a virar a memória que ALIMENTA o prompt (porque custom_attributes do contato entram via contact.liquid, diferente das notas).

---

## 3. Os flags estão ligados na Clara #7?

**Não verificável sem acesso à produção** (regra desta investigação: sem SSH). O que o código permite afirmar:

- Flags vivem em `config` JSONB: `store_accessor :config, :temperature, :feature_faq, :feature_memory, :feature_contact_attributes, :product_name` (`enterprise/app/models/captain/assistant.rb:41`).
- **`feature_contact_attributes`: provavelmente TRUE.** A migração `db/migrate/20260320074636_backfill_feature_contact_attributes_for_assistants.rb:4-14` backfilla `feature_contact_attributes: true` pra **todo assistant de conta com `captain_integration_v2`** (Account 6 tem o flag de feature, conforme `response_builder_job.rb:272` exige e o STATE confirma). O STATE de 08/06 registra `migrate:status = 0 down` em prod — a migração foi aplicada. Se a Clara #7 já existia quando rodou, ficou true; se foi criada depois pela UI, o default do form é false (`app/javascript/dashboard/components-next/captain/pageComponents/assistant/settings/AssistantBasicSettingsForm.vue:63` — `contactAttributes: config.feature_contact_attributes || false`).
- **`feature_memory`: provavelmente FALSE/ausente.** Não há backfill; default da UI é false (`AssistantBasicSettingsForm.vue:61`, `AssistantForm.vue:97`); nenhum script do STATE menciona tê-lo ligado.
- **Verificação read-only sugerida** (console prod, sem efeito colateral): `Captain::Assistant.find(7).config.slice('feature_memory', 'feature_faq', 'feature_contact_attributes', 'knowledge_mode')`.
- Os flags são editáveis via API: `assistants_controller.rb` permite `:feature_faq, :feature_memory, :feature_citation, :feature_contact_attributes` (`enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb:62-63`) — alinhado à filosofia code-first (PUT /captain/assistants/7).

---

## 4. ContactMergeAction — o que a fusão preserva e o que perde

`app/actions/contact_merge_action.rb` (OSS puro — **não há override em `enterprise/`**; grep confirma). Transação única (linha 10), `update_all` em tudo (sem callbacks/validations — anotado pelo rubocop disable).

### 4.1 Preservado (movido pro base_contact)

| Dado | Mecanismo | Linhas |
|---|---|---|
| **Conversations** | `update_all(contact_id: base)` | 35-39 |
| **Contact inboxes** | move com dedup por `(inbox_id, source_id)`; em colisão, conversas re-apontadas pra CI do base e CI do mergee `destroy!` | 54-74 |
| **Notes** | `update_all(contact_id: base)` — a memória do feature_memory SOBREVIVE ao merge | 41-46 |
| **Messages (sender=Contact)** | `update_all(sender_id: base)` | 48-52 |
| **NPS / CSAT** | `update_all` | 76-86 |
| **Atributos escalares** | só `identifier, name, email, phone_number, additional_attributes, custom_attributes`; `mergee.deep_merge(base)` = **base vence em conflito**, mergee preenche buracos (inclusive chaves de custom_attributes que só o mergee tinha) | 88-99 |
| **Funnel items (Kanban)** | indiretamente: `FunnelItem belongs_to :conversation` (`app/models/funnel_item.rb:11,19`) — como as conversas são movidas (não destruídas), os cards seguem junto | — |
| **Scheduled messages (cadência HSM)** | idem: `belongs_to :conversation` (`app/models/scheduled_message.rb:34`) — seguem a conversa | — |

### 4.2 PERDIDO na fusão (dados do mergee descartados no `destroy!`, linha 96)

- **Labels do contato** — `Contact include Labelable` (`app/models/contact.rb:47`) = `acts_as_taggable_on :labels` (`app/models/concerns/labelable.rb:5`). O merge **não migra taggings**; as labels do mergee morrem com ele. (Labels de CONVERSA sobrevivem, pois pertencem à conversa.)
- **Avatar** (Avatarable, `contact.rb:45`).
- **Colunas não-listadas:** `contact_type` (lead/customer!), `location`, `country_code`, `company_id`, `blocked`, `last_activity_at`, `middle_name/last_name` — base mantém os seus; os do mergee somem (`mergable_attribute_keys`, linha 89).
- Evento: dispatcha `CONTACT_MERGED` (linhas 97-98; tipo em `lib/events/types.rb:45`); hoje o único consumidor é o ActionCableListener (`app/listeners/action_cable_listener.rb:160-162`) — **slot livre pra um listener de orquestração**.

### 4.3 Implicações pro reconciliador do 9º dígito / pós-consolidação

1. **ContactMergeAction NÃO funde conversas.** Se cada ficha duplicada tem conversa na inbox 91, o merge deixa o base com 2+ conversas na mesma inbox — viola o requisito `lock_to_single` da Tozi e recria o cenário "reply órfão visual". Foi exatamente por isso que o script `consolida_conversas_duplicadas.rb` precisou de lógica própria (mover mensagens com `update_all`, apagar conversas vazias). Um reconciliador definitivo = `ContactMergeAction` (dados do contato) **+ etapa de fusão de conversas** (inexistente no core).
2. **Cuidado com funnel_items na fusão de conversas:** unique index `(conversation_id, funnel_id)` (`funnel_item.rb:16,27`) — se as duas conversas têm card no mesmo funil, mover/duplicar estoura a unique; apagar conversa com `delete` (sem callbacks, como fez o script de consolidação) deixa funnel_items órfãos (FK existe? a landmine `20260330120000` de FKs estava down — verificar). Em prod o funil teve backfill 0, então exposição real é baixa, mas o reconciliador precisa tratar.
3. **Precedente pronto no código:** `Contacts::ResolveLidJob#merge_or_update` (`app/jobs/contacts/resolve_lid_job.rb:89-106`) já faz "quando uma identidade (LID) resolve pra um telefone que já tem ficha → `ContactMergeAction` + destrói a contact_inbox redundante". É o molde do reconciliador do 9º dígito: detectar variante 12d/13d via `Whatsapp::PhoneNumberNormalizationService`, eleger base (a ficha que o wa_id da Meta usa), fundir.
4. **Uniqueness de telefone:** `Contact validates phone_number uniqueness` (`contact.rb:54-57`). O merge contorna destruindo o mergee ANTES do `base.update!(merged_attributes)` (linhas 96-99). O reconciliador que tentar "consertar" o phone do base pra variante certa deve seguir a mesma ordem.
5. As **notas geradas pelo feature_memory sobrevivem** ao merge — bom: a memória durável do lead consolida em vez de se perder. Mas notas duplicadas (geradas em fichas paralelas antes da fusão) não são deduplicadas por ninguém.

### 4.4 Nota sobre a consolidação já executada (08/06)

O script de consolidação usou `delete`/`update_columns` (sem callbacks) e **não** o ContactMergeAction. Consequência: o que o merge preservaria via update_all foi tratado manualmente (mensagens movidas), mas **notas, NPS/CSAT, labels e custom_attributes das 203 fichas apagadas não foram migrados** (fichas de disparo recém-criadas dificilmente tinham esses dados — risco baixo, porém não-zero; ex.: nota criada por corretor na ficha "errada" durante a semana do bug).

---

## 5. `to_llm_text` vaza PII?

### 5.1 O que o formatter expõe

`to_llm_text` = `LlmFormatter::LlmTextFormatterService` (`app/models/concerns/llm_formattable.rb:4-6`). Para Contact, `LlmFormatter::ContactLlmFormatter` (`app/services/llm_formatter/contact_llm_formatter.rb`):
- **Name, Email, Phone, Location, Country Code** — linhas 37-41, **sem máscara nem redaction**
- **Todos os custom attributes de contato** definidos na conta (CPF, renda, etc., se existirem como custom attribute) — linhas 42-44
- **TODAS as notas do contato, na íntegra** — linhas 7-12 e 21-23 (`@record.notes.all`)
- Histórico resumido das últimas 10 conversas (status/data/contagem) — linhas 25-33

Para Conversation, `ConversationLlmFormatter` (`app/services/llm_formatter/conversation_llm_formatter.rb`): transcrição completa (mensagens privadas só com `include_private_messages: true`, linhas 58 e 71; contato embutido só com `include_contact_details: true`, linha 23).

**Resposta curta: sim — `to_llm_text` de Contact é PII integral por design** (nome+e-mail+telefone+notas+atributos), sem nenhuma camada de anonimização no fork.

### 5.2 Por onde essa PII sai

| Caminho | Destino | Referência |
|---|---|---|
| `ContactNotesService` (feature_memory, no resolve) | Provider LLM (OpenAI/Anthropic via RubyLLM) | `contact_notes_service.rb:9,22-28` |
| `ContactAttributesService` | (órfão — não roda) | `contact_attributes_service.rb:9` |
| Copilot `get_contact` / `search_contacts` | Provider LLM, sob comando do atendente | `copilot/get_contact_service.rb:12`, `search_contacts_service.rb:22` |
| Copilot `get_conversation*` / `search_conversations` | Provider LLM, **incluindo notas privadas da conversa** (`include_private_messages: true`) | `copilot/get_conversation_service.rb:13`, `get_conversation_full_service.rb:16`, `search_conversations_service.rb:22` |
| `Captain::RewriteService` | Provider LLM com `include_contact_details: true` | `lib/captain/rewrite_service.rb:30` |
| `Captain::SummaryService` | Provider LLM **sem** detalhes de contato (`include_contact_details: false`) — único caminho conservador | `lib/captain/summary_service.rb:17` |
| Prompt do runner v2 (contact.liquid) | Provider LLM: nome/e-mail/telefone do lead em todo turno (se `feature_contact_attributes`) | `snippets/contact.liquid:3-5` |
| **Tracing/observabilidade** | `instrumentation_params` inclui as `messages` COMPLETAS (system+user com a PII toda) → exportadas ao backend OTel/Langfuse quando `ChatwootApp.otel_enabled?` | `contact_notes_service.rb:43-46`; `lib/integrations/llm_instrumentation.rb:10-25` |

O vazamento mais sensível não é o provider (inerente a ter IA lendo CRM), e sim o **espelhamento integral de PII no backend de traces** quando OTel/Langfuse está ligado — telefone, e-mail e notas do lead ficam retidos num terceiro sistema sem política de retenção própria do SPX.

Mitigação natural (não implementada): camada de redaction no formatter (mascarar e-mail/telefone fora do necessário) ou no exporter de traces; e um `include_notes:` config no `ContactLlmFormatter` (hoje notas vão sempre).

---

## 6. Síntese pro desenho da IA orquestradora

1. **Memória durável que a IA realmente lê hoje:** `conversation.custom_attributes` (escritos por `salvar_info_lead`) + `conversation.additional_attributes` (source/template do disparo!) + `contact.custom/additional_attributes` (gated por `feature_contact_attributes`) + histórico integral da conversa única. **Notas estão fora do loop do agente.**
2. **Dois encanamentos prontos e subutilizados:** `ContactAttributesService` (extração de atributos → contato; órfão, stub) e a dupla `add_contact_note`/`feature_memory` (escrita de notas que ninguém lê de volta). Pra orquestração, o caminho de maior alavancagem é completar o `ContactAttributesService` e gravar em `contact.custom_attributes` — que JÁ entram no prompt — em vez de notas.
3. **Reconciliador do 9º dígito:** usar `ContactMergeAction` como núcleo (preserva notas/conversas/NPS/CSAT, deduplica contact_inboxes) seguindo o molde do `ResolveLidJob`, MAS adicionar: fusão de conversas (core não faz), migração de labels do contato (core perde), tratamento de funnel_items/unique e ordem destroy-antes-de-update pro phone uniqueness.
4. **Evento `CONTACT_MERGED`** (`contact_merge_action.rb:97`) está livre pra um listener de orquestração (ex.: re-sincronizar CRM externo, re-avaliar estágio de funil pós-fusão).
5. **Go-live da Clara religa o CaptainListener:** se `feature_memory`/`feature_faq` estiverem true, cada resolve da inbox 91 gera chamadas LLM extras com PII completa — decidir conscientemente (custo + privacidade) antes de reconectar.
