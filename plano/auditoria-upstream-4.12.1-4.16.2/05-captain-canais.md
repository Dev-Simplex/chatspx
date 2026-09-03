# W5 — Captain/IA e Canais de Mensagem

**Auditoria read-only** · merge-base `899fce1c92` (v4.12.1, 25/03/2026) → `v4.16.2` (27/07/2026) + `upstream/develop` (03/08/2026)
**Nosso HEAD:** `ee87f5e799` (branch `homologacao`)

---

## Sumário executivo

1. **O maior achado desta auditoria não é uma feature — é um bloqueador de merge.** Nós e o upstream reciclamos os **mesmos bits** de `feature_flags` para features **diferentes**: 12 posições divergem. Um merge ingênuo troca features entre si em todas as contas e as migrations `repurpose_*` do upstream **desligam** `ai_assistant_v2` (redesign do Copilot) e `message_sequences` na frota inteira. Ver §2.1.
2. **O upstream resolveu o bitmask cheio** (`feature_flags_ext_1`, PR #14947 / `873d16f54c`). Nós já estamos em 65 features num campo que só comporta 63 — dois bits nossos estão em terreno indefinido. **TRAZER, alta prioridade.**
3. **Canais:** o upstream corrigiu na raiz o problema dos 2 números no mesmo WABA (`7c7459b734`, override por *phone number*). Nosso patch local (`acceptable_webhook_urls`, working tree, não commitado) só mascara o alerta na UI. **Trocar o nosso pelo deles.**
4. **Segurança obrigatória:** validação HMAC dos webhooks WhatsApp/Instagram (`a9ac1c633d`) — nós **não temos**; assinatura de webhooks de API channel/agent bots (`95463230cb`); `SafeFetch` como guarda SSRF central (`3dfb5061e1`).
5. **Captain:** o upstream investiu em *observabilidade e guardrails* (agent_sessions, message reports, classificador de handoff, detector de falsa promessa) enquanto nós investimos em *capacidade de atendimento* (tools de negócio, eval por episódio, áudio, carrossel, auto-closure). Eixos **complementares** — e os dois passes de inspeção pós-resposta deles (A9, A10) atacam problemas que nós hoje tentamos resolver por prompt, com histórico de recaída.
6. **Copilot: intocado pelo upstream no período** (1 linha). Nosso redesign + streaming é ganho líquido, sem dívida.
7. **Depreciações que nos custam:** `Channel::Voice` foi **dropado** (migration `drop_channel_voice`) e virou capability do `Channel::TwilioSms`; `Pending.vue` e `RelatedResponses.vue` removidos; `conversation_faq_generator` (prompt) removido.
8. Duas colisões de timestamp de migration: `20260616120000` e `20260630000000`.

---

## 1. Grade de decisão — ESCOPO A: Captain / IA

| # | Item | Origem | Valor | Risco merge | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| A1 | **Extensão do bitmask de feature flags** (`feature_flags_ext_1`) | `873d16f54c` #14947 | **Alto** | Médio | **TRAZER** | P |
| A2 | **HMAC/assinatura de webhooks** (ver B1) | — | Alto | Baixo | TRAZER | P |
| A3 | `agent_sessions` — telemetria de sessão (modelo, créditos, docs/FAQs/cenários usados) | `df7f137657` #14970, `9749a3dc96` #14971, `ae49af354d` #15096 | **Alto** | Médio | **TRAZER ADAPTADO** | M |
| A4 | **Captain generation path** na bolha (UI: "de onde veio essa resposta") | `67cab7171d` #15078 | **Alto** | Médio | **TRAZER ADAPTADO** | M |
| A5 | **Message reports** — agente marca resposta ruim da IA | `6a262287d2` #14799 | **Alto** | Baixo | **TRAZER** | P |
| A6 | **FAQ suggestions** — pipeline conversa→observação→sugestão→revisão | `102f19fe41`, `e10b236871`, `7948ea09ac`, `7910eabefc` (#14977-#15017) | Médio | **Alto** | AVALIAR DEPOIS | G |
| A7 | **Document auto-sync** (recrawl agendado, `sync_status`, fingerprint, UI) | `5264de24b0`, `2182165201`, `568aae875b`, `f6be0d80ef`, `d20950c5b4` | **Alto** | Médio | **TRAZER** | M |
| A8 | **Roteamento de LLM por feature** (`config/llm.yml` + `Llm::FeatureRouter`) | `43e0f8a141` #14841, `4e26c5b4bb` #14843, `cf134deb37` #14858 | **Alto** | **Alto** | **TRAZER ADAPTADO** | M |
| A9 | **Guardrail de falsa promessa** (harness "vou verificar e te aviso") | `1c7e60880d` #14672, `84fda8a323` #14823, `0af9900be2` #14824 | **Alto** | Baixo | **TRAZER ADAPTADO** | M |
| A10 | **Classificador de handoff V1** (decide *se* transfere, 12 razões) | `70f799ab35` #14337 | **Alto** | Médio | **TRAZER ADAPTADO** | M |
| A11 | `max_turns` 100 → **10** no agent runner (freio de custo/loop) | `ce2e10e89e` #14883 | **Alto** | Baixo | **TRAZER** | P |
| A12 | **SafeFetch** nas custom tools (SSRF central) | `3dfb5061e1` #14620 | **Alto** | Baixo | **TRAZER** | P |
| A13 | Limite de 15 custom tools/conta + slug ≤64 chars com anti-colisão | `custom_tool.rb` @ v4.16.2 | Médio | Baixo | **TRAZER** | P |
| A14 | Custom tools: headers de API key corrigidos; custom tools no V2 | `9c68eed676` #15008, `fd625981e9` #15015 | Médio | Baixo | **TRAZER** | P |
| A15 | **Snippet `current_time`** no prompt (datas relativas) | `279dd1876c` #14069 | Médio | Médio | **JÁ TEMOS (mas ver §3.11)** | P |
| A16 | Prompt de `conversation_completion` — status + rótulo Captain/Bot/Assistant | `1b6a80d84d` #14967, `354c2cab6b` #14433 | Médio | **Alto** | **TRAZER ADAPTADO** | M |
| A17 | **Captain Overview** (dashboard de métricas + drilldown por assistente) | `7910eabefc` #15017 | Médio | **Alto** | AVALIAR DEPOIS | G |
| A18 | **Assistant migration V1→V2** (classificador+auditor de instruções) | `8fc5c7a5c8` #14909, `6d38b4d39c` #15002 | Baixo | Baixo | DESCARTAR | — |
| A19 | Firecrawl v2 + fallback `sourceUrl` + link longo | `cd9192f7d1`, `8e27ca4282`, `37c8e7e699` | Baixo | Baixo | AVALIAR DEPOIS | P |
| A20 | Help Center: geração/curadoria/tradução de artigo por LLM | `751c28d94d` #14136, `3d20a7b049` #14370 | Médio | Baixo | AVALIAR DEPOIS | M |
| A21 | Onboarding: `WidgetCreationService`, `widget_tagline`, website analyzer | `3489298726` #14314 | Baixo | Baixo | DESCARTAR | — |
| A22 | Uso/BYOK: `counts_toward_usage?` por serviço | `45f4b423ae` #14587, `f13f3ba446` #13968 | Médio | Médio | **TRAZER ADAPTADO** | P |
| A23 | `external_link` → `text` + índice md5 (URLs longas) | `20260525093000` | Médio | Baixo | **TRAZER** | P |
| A24 | Descrição do assistente `string`→`text` | `cc87429903` #14985 | Baixo | Baixo | TRAZER | P |
| A25 | **Copilot** — praticamente intocado upstream | `43e0f8a141` (1 linha) | Nenhum | — | **JÁ TEMOS (superior)** | — |
| A26 | Streaming de resposta | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** | — |
| A27 | Eval / LLM-as-a-Judge por episódio | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** | — |
| A28 | MCP (`mcp/chatspx-tools`) | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** | — |
| A29 | Rajada de mensagens → 1 resposta só | `38a317962b` #15133 (develop) | **Alto** | Médio | AVALIAR DEPOIS | P |
| A30 | Respeitar limite de caracteres do canal | `4ac2432b77` #14982 (develop) | Médio | Baixo | AVALIAR DEPOIS | P |
| A31 | Eventos de ciclo de vida normalizados do Captain | `7981e2cc75` #15213 (develop) | Médio | **Alto** | AVALIAR DEPOIS | M |

## 2. Grade de decisão — ESCOPO B: Canais

| # | Item | Origem | Valor | Risco merge | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| B1 | **HMAC nos webhooks WhatsApp/Instagram** | `a9ac1c633d` #14280 | **Alto (obrigatório)** | Baixo | **TRAZER** | P |
| B2 | **Override de webhook por phone number** (2 números / 1 WABA) | `7c7459b734` #13817 | **Alto** | Médio | **TRAZER — e descartar nosso patch** | P |
| B3 | Limpar override ao apagar inbox manual / desregistrar número | `9328f8739c` #15010, `b2716e15e1` #14940 | Médio | Baixo | **TRAZER** (junto com B2) | P |
| B4 | **Health de phone number persistido + sync agendado** | `d644c207f0` #15100 | **Alto** | **Alto** | **TRAZER ADAPTADO** | M |
| B5 | Assinatura (secret) de webhooks de API channel e agent bots | `95463230cb` #13892 | **Alto (obrigatório)** | Baixo | **TRAZER** | P |
| B6 | Contato bloqueado → descartar mensagem WhatsApp entrante | `3f9f054c43` #14061 | **Alto** | Baixo | **TRAZER** (1 linha) | P |
| B7 | Lookup de canal por telefone normalizado no webhook | `e65e18e9c5` #13709 | **Alto** | Médio | **TRAZER ADAPTADO** | P |
| B8 | Guarda de janela de 24h em envio por automação | `166a41c31c` #15113 | **Alto** | Baixo | **TRAZER** | P |
| B9 | `fallback_title` de localização truncado a 255 (msg sumia) | `7acbe8b3ff` #14517 | **Alto** | Baixo | **TRAZER** (1 linha) | P |
| B10 | Preservar nome original de anexo do Cloud | `c041fde3a2` #14168 | Médio | Baixo | **TRAZER** | P |
| B11 | Lock por (inbox, contato) contra conversas duplicadas | `05dd31389e` #14060 | — | — | **JÁ TEMOS (superior)** — `6516d06d5c` | — |
| B12 | Referral CTWA | `de137e8297` #14681 | Médio | Médio | **JÁ TEMOS (parcial)** — `58c98bf1f2` | P |
| B13 | **BSUID** (business-scoped user ids da coexistência) | `40deaef458` #14436, `a3a961919e` #15150 | Médio | Médio | AVALIAR DEPOIS | M |
| B14 | Coexistência: reabrir conversa entre identidades / msg indisponível | `2144de92f2` #15098, `56e30102eb` #14547 | Baixo | Médio | AVALIAR DEPOIS | M |
| B15 | Embedded signup: reconfigurar, migrar p/ manual, log de transferência | `2891a72cb9` #15038, `b560720e08` #14975, `0a25a0ef66` #15032 | Médio | Médio | AVALIAR DEPOIS | M |
| B16 | Derrubar checagem obsoleta de escopo WABA / desligar re-oauth manual | `f93f2067b6` #14697, `8a3b129292` #13599 | Médio | Baixo | **TRAZER** | P |
| B17 | Aviso quando sync de template Cloud falha | `3e03f8da1e` #15004 | Baixo | Baixo | TRAZER | P |
| B18 | Voice notes (áudio gravado no dashboard) via Cloud + conversão ogg | `37eed5de1e` #14606 | Médio | Médio | AVALIAR DEPOIS | M |
| B19 | **WhatsApp Cloud Calling** (chamadas de voz pelo WhatsApp) | `28ec1794f4`, `de696a55cb`, `c4a6a19e9b`, `8d5d02ea97`, `e055cead35` | Baixo | **Alto** | AVALIAR DEPOIS | G |
| B20 | **Voz vira capability do Twilio SMS — `Channel::Voice` dropado** | `0e122188e9` #13963 + `drop_channel_voice` | — | **Alto** | **DÍVIDA — ver §3.3** | M |
| B21 | Variáveis em campanhas WhatsApp | `f8f0caf443` #13649 | Médio | Médio | AVALIAR DEPOIS | M |
| B22 | Email: layouts com marca por inbox | `c420edce58` #14936 | Baixo | Médio | DESCARTAR | — |
| B23 | Email: strip de null bytes no inbound (mensagem sumia) | `d1c482cb64` #14546 | Médio | Baixo | **TRAZER** | P |
| B24 | Email: tipo de autenticação IMAP configurável | `202403873d` #12306 | Baixo | Baixo | AVALIAR DEPOIS | P |
| B25 | Email: imagens inline sem `Content-Disposition` | `42bba748cf` #11949 | Médio | Baixo | **TRAZER** | P |
| B26 | Instagram: processar eventos após esgotar retry de mutex | `73ba0b26e5` #14647 | **Alto** | Baixo | **TRAZER** | P |
| B27 | Facebook: parar de forçar `MESSAGE_TAG/ACCOUNT_UPDATE` | `d8656edc61` #14329 | Médio | Baixo | **TRAZER** | P |
| B28 | Line: URLs não expiráveis para imagem/vídeo | `4cce7f6ad8` #13949 | Baixo | Baixo | TRAZER | P |
| B29 | Agent bots: eventos `conversation_status_changed`, `changed_attributes`, atribuição | `50d6ebaaca`, `f4d66566d0`, `b815eb9ce0` | Médio | Médio | AVALIAR DEPOIS | P |
| B30 | Dados da conta no payload de webhook | `af1dfc21f6` #12445 | Baixo | Baixo | AVALIAR DEPOIS | P |
| B31 | Feature `api_and_webhooks` obrigatória p/ token API e webhooks | `522e3c4d3f` #14973 | Baixo | Médio | **AVALIAR — pode quebrar integração de cliente** | P |
| B32 | Slack: sincronizar respostas interativas do bot | `f7bbd40816` #14076 | Baixo | Baixo | DESCARTAR | — |
| B33 | **WAHA / Evolution API** (16 serviços) | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** | — |
| B34 | **Grupos WhatsApp com autor por mensagem + integrantes** | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** — `44b77d19c0` | — |
| B35 | Templates HSM criados/submetidos pela nossa API | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** — `de4014dd24` | — |
| B36 | Reconciliador do 9º dígito BR | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** — `d74fb42cbc` | — |
| B37 | Meta Lead Ads → conversa | *inexistente upstream* | — | — | **JÁ TEMOS (só nós)** — `0ca02a6b1a` | — |
| B38 | Token dedicado de template Cloud / header text params / reply por scoped id | `59eac9a7c5`, `9d769dfcdd`, `d04a717701` (develop) | Médio | Baixo | AVALIAR DEPOIS | P |

---

## 3. Detalhamento — o que importa

### 3.1 🚨 BLOQUEADOR: colisão de bits em `config/features.yml`

`Featurable` (`app/models/concerns/featurable.rb:9-13`) mapeia bit ↔ feature pela **posição da entrada no YAML**, 1-based. Nós e o upstream editamos as mesmas posições em direções diferentes:

| bit | NOSSO | UPSTREAM v4.16.2 |
|---|---|---|
| 4 | `channel_twitter` | `conversation_unread_counts` |
| 29 | `message_sequences` | `custom_tools` |
| 30 | `internal_chat` | `message_reply_to` |
| 31 | `insert_article_in_reply` | `branded_email_templates` |
| **39** | **`ai_assistant_v2`** | **`captain_v1_action_classifier`** |
| 52 | `twilio_content_templates` | `captain_document_auto_sync` |
| 57 | `quoted_email_reply` | `unread_count_for_filters` |
| 61 | `kanban_cursor_loading` | `captain_tasks` |
| 62 | `kanban_ux_v2` | `conversation_required_attributes` |
| 63 | `captain_tasks` | `advanced_assignment` |
| 64 | `conversation_required_attributes` | `whatsapp_manual_transfer` |
| 65 | `advanced_assignment` | `data_import` |

Consequências concretas de um merge sem tratamento:

- **`ai_assistant_v2` (bit 39) é o flag do redesign do Copilot.** O upstream reciclou esse bit e a migration `20260430114500_repurpose_report_v4_flag_for_captain_v1_action_classifier` roda `disable_features(:captain_v1_action_classifier)` em **todas** as contas — ou seja, apaga o bit 39 da frota inteira. O redesign do Copilot desapareceria para todos os clientes.
- Idem `20260324102005_repurpose_response_bot_flag_for_custom_tools` sobre o bit 29 (`message_sequences`).
- Idem `20260426011444` (bit 52) e `20260508000000` (bit 4).
- Os bits 61-65 estão **deslocados em +2** porque inserimos `kanban_cursor_loading` e `kanban_ux_v2` no meio da lista. Depois do merge, uma conta com `captain_tasks` ligado passaria a ler `advanced_assignment`, e assim por diante.

> **Nota crítica sobre `captain_tasks`:** o commit `d985beeafd` ("auto_closure exige captain_tasks") faz nosso auto-closure depender do bit 63. No upstream esse bit é `advanced_assignment`. O auto-closure ligaria/desligaria pelo flag errado.

**Ação recomendada antes de qualquer merge:** congelar o mapa bit→feature atual (dump de `accounts.feature_flags` por conta), reordenar nosso `features.yml` para **coincidir posicionalmente** com o do upstream, mover nossas features exclusivas para o fim / para `feature_flags_ext_1`, e escrever uma migration de remapeamento própria. Esforço: **M**, mas é pré-requisito de tudo.

### 3.2 A1 — `feature_flags_ext_1` (PR #14947 / `873d16f54c`)

`Featurable` upstream passa a suportar N colunas bitset, com `MAX_FEATURES_PER_COLUMN = 63` e validação que **explode no boot** se alguém passar do limite. Features novas declaram `column: feature_flags_ext_1` no YAML.

Isto nos interessa diretamente: **nós já temos 65 features** — os bits 64 e 65 (`conversation_required_attributes`, `advanced_assignment`) estão além do que um `bigint` com sinal comporta. Nossa memória de projeto registra "usar `internal_attributes` porque o bitmask estourou"; a solução do upstream é melhor e permanente. Vem com `app/models/concerns/featurable.rb`, `config/features.yml` e uma migration de 1 coluna. **TRAZER, P, prioridade máxima** (fazer junto com §3.1).

### 3.3 B20 — `Channel::Voice` foi DROPADO (depreciação que nos custa)

O upstream removeu `enterprise/app/models/channel/voice.rb` e transformou voz em capability do `Channel::TwilioSms` (`0e122188e9` #13963), com duas migrations:

- `20260326120000_add_voice_to_channel_twilio_sms.rb` (`voice_enabled`, `twiml_app_sid`, `api_key_secret`)
- `20260326120001_drop_channel_voice.rb` → **`drop_table :channel_voice`**

Nós **temos** `enterprise/app/models/channel/voice.rb` e todo o entorno (`contact_inbox_builder`, `contactable_inboxes_service`, `calls_controller`, `has_many :voice_channels`). Se alguma conta da frota tiver inbox de voz, essa migration **apaga a tabela e os dados**. Precisa de auditoria de dados antes (`SELECT count(*) FROM channel_voice` por VM) e de um plano de migração para `channel_twilio_sms`, ou de excluir essa migration do merge conscientemente (aí carregamos um modelo que o upstream não mantém mais — dívida crescente).

Além disso o upstream **reescreveu quase todo o subsistema de voz** (~640 linhas removidas, `call_session_sync_service.rb` e `conference/name.rb` deletados). Qualquer coisa que tenhamos encostado ali vai conflitar.

### 3.4 B2/B4 — WhatsApp: nosso patch × a correção deles

**O problema:** a Meta aceita um `override_callback_uri` por WABA, mas o Chatwoot registrava nele uma URL **por número**. Com 2 números no mesmo WABA, só uma URL fica registrada e a outra inbox acusa incompatibilidade (mesmo funcionando, porque o roteamento de entrada resolve a inbox pelo *payload*, não pela URL).

**Nossa solução** (working tree, não commitada, `app/services/whatsapp/health_service.rb`): `build_acceptable_webhook_urls` aceita a URL de qualquer canal irmão do mesmo WABA na mesma conta. É correto no diagnóstico, mas trata o **sintoma** (o alerta da UI).

**A solução deles** (`7c7459b734` #13817): trocam `override_waba_callback` por `override_phone_number_callback` — `POST /<PHONE_NUMBER_ID>` com `webhook_configuration.override_callback_uri`. O override de phone number tem precedência sobre o de WABA, então **cada número passa a ter callback próprio de verdade**. Vem acompanhado de teardown seletivo (`clear_phone_number_callback_override`) e de `9328f8739c`/`b2716e15e1` que limpam o override só do número apagado.

**Recomendação: TRAZER o deles e descartar o nosso.** Reduz divergência, resolve a causa, e nosso patch nem está commitado (custo de descarte ≈ zero). O comentário técnico que escrevemos no `health_service.rb` continua valioso como documentação — vale preservar no commit de adoção.

**B4 — health persistido:** o `#15100` (`d644c207f0`) guarda o resultado do health em colunas novas (`phone_number_health` jsonb, `phone_number_health_checked_at`, `phone_number_health_error`), com `HealthSyncSchedulerJob` horário, e expande a tela `AccountHealth.vue` (526 linhas alteradas). **Nós já modificamos essa mesma tela** (`AccountHealth.vue` está `M` no working tree) e o `health_service.rb`. Colisão frontal — daí "TRAZER ADAPTADO": pegar o backend (persistência + job agendado, que resolve o custo de bater na Graph API a cada page load) e reconciliar a tela com o nosso skin. Ver também `3479b1026e` (develop) que preserva o health quando o enriquecimento de business falha.

### 3.5 A8 — Roteamento de LLM por feature

O upstream fechou o ciclo iniciado antes de v4.12.1: agora **todo** serviço LLM declara `feature:` em vez de `model:`, e `Llm::FeatureRouter.resolve(feature:, account:)` decide modelo + credencial. Serviços de sistema (embedding, transcrição, tradução de query) passam a usar a chave da instalação e **não** contam para o uso do cliente (`counts_toward_usage?`).

Nosso `config/llm.yml` **já divergiu**: temos `claude-sonnet-4`, `claude-opus-4`, default `gpt-5-mini` para assistant/copilot; eles têm `gpt-5.1`, `gpt-5.2`, `coming_soon: true` nos Claude/Gemini e ~10 features a mais (`document_faq_generation`, `conversation_faq_generation`, `pdf_faq_generation`, `help_center_article_generation`, `onboarding_content_generation`, `help_center_query_translation`…). Também mexemos em `enterprise/app/services/llm/base_ai_service.rb` (+73 linhas) e `legacy_base_open_ai_service.rb`.

**TRAZER ADAPTADO:** vale muito a arquitetura (`FeatureRouter`, `counts_toward_usage?`, `captain_models` normalizado em `CaptainFeaturable`, campo de override de modelo no super admin). **Não** vale o `llm.yml` deles literal — nossos defaults são escolha de negócio (custo/qualidade por cliente) e os modelos Anthropic que usamos de verdade estão marcados `coming_soon` lá.

### 3.6 A9 — Guardrail de falsa promessa

Três PRs (`1c7e60880d`, `84fda8a323`, `0af9900be2`) criam `Captain::Llm::AssistantFalsePromiseService` + schema: um segundo passe que inspeciona a resposta e detecta "vou verificar e te aviso", "estou te transferindo", "vou escalar" — promessas de trabalho assíncrono que a IA não pode cumprir. Configurável por conta.

**Isto é diretamente aplicável a nós.** Nós resolvemos o mesmo problema *por prompt* (`334f0409e9` "garante handoff prometido", `b780eec93e` "handoff quase nunca disparava"). Um verificador determinístico pós-resposta é mais robusto que instrução no prompt. **TRAZER ADAPTADO** — nosso prompt é pt-BR e muito customizado; o detector deles é explicitamente language-independent, então dá para plugar sem reescrever nossa conduta. O prompt correspondente está em `system_prompts_service.rb:assistant_false_promise_detector`.

### 3.7 A3/A4/A5 — Observabilidade: onde o upstream ficou melhor que nós

Este é o ponto em que, honestamente, **a versão deles ficou melhor**:

- **`agent_sessions`** (`df7f137657`, `9749a3dc96`): uma linha por geração, polimórfica sobre Conversation/CopilotThread, guardando `llm_model`, `credits_consumed`, `document_ids`, `faq_ids`, `scenario_ids`, `run_context`. Nós temos `captain_assistant_logs` (eventos) e `captain_tool_calls` (traces de tool) — cobrimos o *que aconteceu*, mas não *com que material a resposta foi construída*.
- **Generation path na UI** (`67cab7171d`): o agente vê, na própria bolha, quais documentos/FAQs/cenários alimentaram a resposta. Isso resolve o "por que a IA disse isso?" sem ir ao banco. Front novo: `CaptainGenerationDetails.vue` (342 linhas) + `bubbles/Base.vue`.
- **Message reports** (`6a262287d2`): o agente marca a resposta ruim com motivo (`incorrect_information`, `inappropriate_response`, …). É o *feedback loop humano* que o nosso eval (LLM-as-a-judge) não tem — nosso juiz é automático, o deles é humano. **Complementares.**

**TRAZER ADAPTADO** para A3/A4 (o front colide com nosso redesign de bolha) e **TRAZER** direto para A5 (`MessageContextMenu.vue` + dialog isolado, colisão pequena).

### 3.8 A6/A17 — FAQ suggestions e Overview: valor real, custo alto

O pipeline de FAQ suggestions (4 PRs, ~1.500 linhas) transforma conversas resolvidas em sugestões de FAQ deduplicadas por embedding (`captain_faq_observations` → `captain_faq_suggestions` com `has_neighbors`), com tela de revisão. O Overview (`AssistantStatsBuilder` + `AssistantDrilldownBuilder`, ~440 linhas de builder + 8 componentes novos) é um dashboard de eficácia por assistente.

Ambos **substituem** telas que nós já redesenhamos: `responses/Pending.vue` foi **deletado** e virou `responses/FaqSuggestions.vue`; `documents/Index.vue` mudou 340 linhas. Dos 12 arquivos de front Captain em colisão, 5 são exatamente destas features.

**AVALIAR DEPOIS** para ambos: o valor é real mas o custo de reconciliar com o glass/aurora é G. Se forem trazidos, que seja como projeto próprio de front, não como parte de um merge.

### 3.9 A16 — `conversation_completion` × nosso auto-closure

O upstream melhorou o prompt de avaliação de encerramento: agora injeta `Conversation status:` no input e rotula o remetente como `Customer`/`Captain`/`Bot`/`Assistant` em vez de `Customer`/`Assistant` (`1b6a80d84d`), trata conversa já resolvida (`354c2cab6b`), e passa a usar sempre a chave da instalação (`counts_toward_usage? => false`).

Nós construímos **em cima** desse serviço: `conversation_eval_service.rb` (221 linhas), `conversation_eval_schema.rb`, `episode_gate_service.rb`, `episode_segmenter_service.rb`, prompts `conversation_eval.liquid` e `runtime_context.liquid`, mais a fila "aguardando encerramento" (`33eececf10`). O arquivo em si só tem 3 linhas nossas alteradas, mas o **ecossistema ao redor é nosso**.

**TRAZER ADAPTADO:** as melhorias de rotulagem e o `Conversation status:` são genuinamente melhores e baratos de portar isoladamente. O `counts_toward_usage?` precisa checar se bate com a nossa contabilidade de chaves por propósito (`b1c3c7812b`).

### 3.10 A11 — `max_turns: 100` → `10`

Uma linha (`agent_runner_service.rb`), efeito grande: hoje um assistente em loop de tool pode queimar até 100 turnos por resposta. Nós **modificamos esse arquivo** (+83 linhas), então não vem de graça no merge, mas a mudança em si é trivial de aplicar e é dinheiro direto. **TRAZER, P.**

### 3.11 A15 — hora atual no prompt: temos melhor, mas travado num cliente

O upstream criou `snippets/current_time.liquid` + `[Current Time]` no prompt do assistente, alimentado por `config['timezone']` da conta.

Nosso `runtime_context.liquid` já faz isso **e mais**: injeta data/hora, status de atendimento (aberto/fechado) e regras de conduta fora do horário — é claramente mais rico. Mas o texto é **`(horário de Sinop/MT)` hardcoded**, ou seja, só está correto para um cliente. Numa frota multi-cliente isso é um bug latente: qualquer conta em outro fuso recebe uma afirmação de fuso errada no prompt.

**Recomendação:** manter o nosso conteúdo, adotar do upstream apenas o *mecanismo* de resolver o timezone pela config da conta (`config['timezone']`, ver `system_prompts_service.rb:format_current_time`). Esforço P, e conserta um problema nosso independente do merge.

### 3.12 A10 — classificador de handoff: correção de avaliação

Numa primeira leitura classifiquei isto como "já temos". **Não temos.** Nosso `bd32c4118b` decide *para qual time* o handoff vai (roteamento de destino, 21 linhas em `handoff_tool.rb` + rake de config). O `70f799ab35` do upstream é outra coisa: um **segundo passe de LLM** (`AssistantActionClassifierService`, 148 linhas + schema) que, depois da resposta gerada, decide se a conversa **deve** ser transferida, com taxonomia fechada de 12 razões (`explicit_human_request`, `repeated_frustration_or_loop`, `account_or_transaction_verification`, …).

Nós tratamos essa decisão **por prompt**, e isso já nos custou caro: `b780eec93e` ("handoff quase nunca disparava — descrição negativa") e `334f0409e9` ("garante handoff prometido") são exatamente sintomas de decisão de transferência feita por descrição de tool. Um classificador dedicado é mais robusto. **TRAZER ADAPTADO** (valor Alto): o serviço é autocontido; o que precisa adaptar é o gancho no `response_builder_job.rb` (que nós modificamos) e a flag — que no upstream é justamente `captain_v1_action_classifier`, o bit 39 que colide com o nosso `ai_assistant_v2` (§3.1). Combina bem com A9 (falsa promessa): os dois são passes de inspeção pós-resposta e compartilham `assistant_response_inspection_helpers.rb`.

---

## 4. O que o upstream DEPRECOU ou REMOVEU (dívida técnica futura)

| Removido | Onde | Nosso impacto |
|---|---|---|
| **`Channel::Voice` (tabela `channel_voice`)** | `drop_channel_voice` + `0e122188e9` | **Alto** — temos o modelo e 8 pontos de código; migration apaga dados. Ver §3.3 |
| `Voice::CallSessionSyncService`, `Voice::Conference::Name` | `0e122188e9` | Baixo (não estendemos) |
| `captain/responses/Pending.vue` | `7910eabefc` | Médio — a tela existe no nosso front redesenhado |
| `captain/pageComponents/document/RelatedResponses.vue` | `7910eabefc` | Baixo |
| `SystemPromptsService.conversation_faq_generator` | `d57354c8b5` | Médio — método sumiu; virou `ConversationFaqPromptsService` |
| Flags `response_bot`, `message_reply_to`, `report_v4`, `channel_twitter`, `twilio_content_templates`, `quoted_email_reply`, `insert_article_in_reply` | migrations `repurpose_*` | **Alto** — ver §3.1 |
| Checagem de escopo WABA no embedded signup | `f93f2067b6` #14697 | Baixo (a checagem estava quebrada mesmo) |
| `AssistantSystemSettingsForm.vue` (-23 linhas de campos) | v4.16.2 | Baixo |
| `override_waba_callback` (assinatura antiga) | `7c7459b734` | Médio — é o método que nosso comentário de `health_service.rb` referencia |

---

## 5. Riscos e pegadinhas

1. **§3.1 é pré-condição.** Nenhum item desta auditoria deve ser mergeado antes de resolver o mapa de bits. Não é opcional e não é contornável por cherry-pick seletivo — basta uma das migrations `repurpose_*` rodar.
2. **Colisão de timestamp de migration** (quebra `db:migrate` com `DuplicateMigrationVersionError`):
   - `20260616120000` → nosso `add_agent_id_to_messages` × upstream `add_icon_to_teams`
   - `20260630000000` → nosso `extend_ai_config_changes` × upstream `add_sender_created_index_to_messages`
   Fix conhecido: `git mv` para timestamp único (ver `reference_migration_timestamp_colisao`).
3. **`enterprise/lib/captain/tools/` é 90% nosso.** Temos 26 arquivos ali; o upstream tem 8. As nossas tools de negócio (`buscar_imovel`, `enviar_fotos_imovel`, `programar_followup`, `responder_em_audio`, …) não têm contraparte. As 3 tools compartilhadas (`faq_lookup_tool`, `handoff_tool`, `http_tool`) mudaram no upstream — `http_tool` foi **reescrito** (-82 linhas) para usar SafeFetch, e o nosso tem guarda SSRF própria (`check_private_ip!`) + `perform_test`. Merge de `http_tool` = reescrever, não mergear.
4. **`B31` (`api_and_webhooks` obrigatório)** pode derrubar integração de cliente silenciosamente: contas sem o flag perdem token de API e webhooks. Se vier, precisa migration que liga o flag na frota inteira.
5. **`system_prompts_service.rb`**: upstream mudou 198 linhas; nós mudamos 4 no arquivo mas movemos a customização para `.liquid` (`assistant.liquid` +25, `runtime_context.liquid` novo). Merge textual vai "dar certo" e mudar o comportamento da IA em produção sem ninguém notar. Qualquer adoção aqui exige rodar o eval antes/depois.
6. **`AccountHealth.vue`** tem 526 linhas alteradas no upstream **e** está modificado no nosso working tree. Conflito garantido.
7. **Nosso patch `acceptable_webhook_urls` não está commitado.** Se alguém rodar `git checkout` no `health_service.rb` durante o merge, ele some sem rastro. (Este relatório é a única cópia da justificativa técnica dele fora do working tree.)
8. **Voz no WhatsApp (B19)** assume `channel_voice` como feature flag — que no nosso mapa está no bit 45, coincidentemente **igual** ao deles. Um dos poucos alinhamentos por acaso.

---

## 6. O que eu NÃO consegui apurar

- **Estado dos dados na frota.** Não consultei banco nenhum (auditoria read-only sobre git). Perguntas em aberto que mudam a decisão: quantas contas têm `ai_assistant_v2`/`message_sequences`/`captain_tasks` ligados? Existe alguma linha em `channel_voice`? Sem isso, o custo real de §3.1 e §3.3 é estimativa.
- **Se os bits 64/65 do nosso `feature_flags` funcionam hoje.** `FlagShihTzu` sobre `bigint` com sinal comporta 63 bits; temos 65 features. Não testei o comportamento de `feature_advanced_assignment?` em runtime — pode estar silenciosamente sempre falso.
- **Comparação visual do front.** Não abri o Playwright nem comparei as telas novas do upstream (Overview, FaqSuggestions, DocumentDetails) contra o nosso redesign. As estimativas de esforço G para A6/A17 são baseadas em contagem de linhas e sobreposição de arquivos, não em inspeção de UI.
- **`upstream/develop` além de v4.16.2** foi varrido só por título de commit nos paths das duas áreas (12 commits relevantes listados); não abri os diffs.
- **Twilio/SMS e Telegram** tiveram movimentação mínima no período e não foram aprofundados além do diffstat.
- **Efeito do merge sobre `mcp/chatspx-tools`**: o upstream não tem MCP, então não há colisão direta, mas não verifiquei se o MCP consome APIs de Captain que mudaram de forma (ex.: `custom_tools_controller` mudou 25 linhas).

---

*Relatório gerado por auditoria estática de git (log/diff/show/ls-tree). Nenhum arquivo fora desta pasta foi alterado, nenhum comando de escrita em git foi executado.*
