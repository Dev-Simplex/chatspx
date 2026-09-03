# Estado dos blocos — auditoria de árvore, 24/08/2026

> **O que este documento é.** Uma auditoria de **estado real da árvore** de `homologacao`
> (HEAD `7b4ad0a371`, 24/08/2026 18:39 UTC), bloco a bloco, para as **Ondas 3, 4, 5 e 6** do
> `PLANO-MESTRE.md` §2.2. Não é relato de execução: é conferência independente, feita abrindo
> arquivo e rodando comando.
>
> **O que ele NÃO é.** Não substitui os relatórios de trilha (`o3-*.md`, `o4-*.md`, `o5-*.md`,
> `o6-ia.md`) — ele os **confere**. Onde o relatório de trilha e a árvore discordam, quem manda
> aqui é a árvore, e a divergência está nomeada.
>
> **Ele revoga o `ESTADO-18ago.md` para estas quatro ondas.** Aquele documento conta 6 blocos na
> Onda 3, 0 na Onda 4, 5 na Onda 5 e 0 na Onda 6 — **11 no total**. A árvore de hoje tem **51 blocos
> FEITOS** entre as quatro, e a Onda 4, que ele marca com **zero**, tem **13**. O `ESTADO-18ago.md`
> descrevia a branch `redesenho-integra` na data dele, antes de o recorte pousar em `homologacao`;
> usá-lo hoje como rastreio **reabre 40 blocos já entregues**. Comparação linha a linha na §6.

## 0. Método, e os seus limites

**As quatro regras que governaram cada linha desta tabela:**

1. **"O arquivo existe" não é "o bloco está feito".** Para cada bloco, os arquivos decisivos da
   coluna *Arquivos* foram **abertos e lidos**. `sdk/tracking/tags.js` tem 10.722 B de ponte de tags
   implementada; já `widget/state/loadingGate.js` existe, tem teste verde e **nenhum consumidor** —
   o primeiro é FEITO, o segundo é PARCIAL, e a diferença só aparece lendo.
2. **Onde o ACEITE é executável, ele foi executado**, e o resultado está na coluna *Evidência*.
   Rodaram nesta auditoria: **rspec — 547 exemplos, 0 falhas**, em banco dedicado
   (`chatwoot_test_7`); **vitest — 3 corridas, a maior com 1.681 testes em 148 arquivos, 0 falhas**;
   **14 verificadores de navegador** (`*.check.mjs`, Chromium real); **1 suíte Playwright**; e o
   **gate de peso** (`scripts/widget-size.mjs`). O detalhamento está no anexo §8.
3. **Nada é FEITO por inferência de nome.** Onde não abri ou não consegui medir, está escrito
   NAO-VERIFICAVEL com a razão.
4. **A contagem de blocos vem do `PLANO-MESTRE.md`**, não de memória: 20 blocos na Onda 3, 22 na
   Onda 4, 21 na Onda 5, 5 na Onda 6 — conferido somando as linhas de cada tabela e batendo os
   pontos (P=1, M=3, G=8, P/M=2, M–G=5, §0.5) contra o total declarado no cabeçalho de cada onda.
   As quatro somas fecham exatamente: 76, 78, 66 e 25.

**Blocos CORTADOS ou realocados que não entram na contagem** (regra 5 do briefing):

| Bloco | Onda nominal | O que o plano diz | Contado aqui? |
|---|---|---|---|
| ~~**5.07**~~ | Onda 4 (`5.xx`) | **realocado para a Onda 1** — nove blocos mexem no `sdk.js` antes da Onda 5, e o cache de 1 ano sem validador seguraria o teaser por até 12 meses | **Não.** A Onda 4 tem 22 blocos *sem* ele, e o cabeçalho do plano já conta 22 |
| ~~**1.21**~~ | Onda 1 | **CORTADO** pela decisão D6 (backfill de origem) | Fora do recorte desta auditoria (Onda 1) |
| **3.15**, **4.09**, **4.10** | numeração de outras ondas | **executam na Onda 5**, por dependência de 2.01/2.06 | **Sim**, dentro da Onda 5 — é onde o plano os coloca |

**O que esta auditoria NÃO mediu, declarado:**

- **As suítes Playwright de `spec/e2e/`** (`widget`, `triggers`, `tracking`, `appearance`,
  `dashboard`, `telemetry`, `fallback`). Duas razões: (a) o `playwright.config.js` raiz aponta para
  `http://localhost:3000`, e a porta 3000 desta VM roda o **servidor de homologação já deployado** —
  um E2E contra ele mede o *deploy* (bundle de 21/08, Ruby anterior aos consertos da triagem), não a
  árvore; (b) as suítes com harness próprio usam **portas fixas** (3038/3999/8899), cujo slot pode
  estar sendo usado por outra trilha, e tomar o slot de outro agente já custou três incidentes.
  A exceção é `spec/e2e/widget/capture/`, que sobe Vite em porta efêmera — essa rodou.
- **Qualquer coisa que exija credencial externa viva** (Test Events da Meta, GA4 DebugView,
  GlitchTip recebendo erro real). Está marcado NAO-VERIFICAVEL, com a razão na linha.
- **Nenhuma migration rodou**, nenhum banco de produção foi tocado, nada foi buildado. O rspec usou
  `POSTGRES_DATABASE=chatwoot_test_7`, que já estava na versão `20260819160000` do `schema.rb`.

---

## 1. Onda 3 — Captura *(blocos `4.xx` · 20 blocos · 76 pontos · 20,3% do esforço)*

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **4.01** | Ponte: resposta a `input_select`/`form` vira `incoming` | `widget/messages_controller.rb`, `automation_rule_listener.rb` | **sim** | sim — rspec | `FLOW_REPLY_CONTENT_TYPES = %w[input_select form]` + `echo_visitor_reply` (`messages_controller.rb:5,45`); `#resume_pending_reply → Flows::ReplyResumeService` (`automation_rule_listener.rb:341-348`). `messages_flow_reply_spec.rb` **verde** | **FEITO** |
| **4.02** | `trigger_type: widget_prechat`, resolução no servidor, adaptador, teto de 8 | `flow.rb:42`, `app/services/flows/` | **sim** | sim — rspec | enum `widget_prechat: 5` (`flow.rb:46`) + validações `widget_prechat_trigger_config_shape` / `_collected_fields_cap`; `Flows::WidgetPrechatResolver` (11.144 B), `Flows::StructuredMessageLimits` (META×WEB). 4 specs **verdes** | **FEITO** |
| **4.03** | Fluxo de captura conversacional (8 campos, e-mail **ou** WhatsApp, máscaras BR) | `widget/capture/` ⚪, `message-types/` ⚪ | **sim** | sim — Playwright | `CaptureForm.vue` (148 l.) + `CaptureField.vue` (231 l.); `MAX_CAPTURE_FIELDS = 8`, `CONTACT_TYPES = ['email','phone']`. `spec/e2e/widget/capture/` (porta efêmera): **3 passed** — inclusive *"conclui sem barra de rolagem horizontal em nenhum momento"* em 375 px | **FEITO** |
| **4.04** | Tela 2 — 7 gatilhos, 3 níveis de abordagem, degradação | `triggers/` ⚪ | **sim** | sim — vitest | 7 componentes, **1.219 linhas** (`TriggersPage` 368, `ApproachSelector` 130, `SegmentationField` 182, `TriggerRow` 200, `LegacyCampaigns` 138, `TeaserComposer` 131, `AutoOpenWarningDialog` 70). `degradeOnReturn` default **true**; celular recusa `aggressive`. Suíte da tela **verde** (34 arquivos / 664 testes no diretório `widget/`) | **FEITO** |
| **4.05** | Vínculo teaser ↔ campanha existente | `triggers/` + `campaigns` | **sim** | **sim, e reprova a ponta a ponta** | `TeaserComposer.vue` edita `title`/`message` da campanha de chat ao vivo da inbox (não cria campanha por gatilho) — metade do aceite OK. **Mas o teaser do 4.06 renderiza `canal.welcomeTagline \|\| canal.welcomeTitle` (`sdk/teaser.js:180`) e a campanha não viaja no payload de boot**: editar o texto no compositor **não muda o que o visitante vê**. Achado registrado pela própria trilha (`o3-coexistencia.md` §7.2) e **confirmado aqui no código** | **PARCIAL** |
| **4.06** | O teaser no host, em duas formas (Discreto/Chamativo) | `sdk/bubbleHelpers.js`, `sdk/sdk.js`, `cookieHelpers.js` | **sim** | sim — Chromium + gate | `sdk/teaser.js` + CSS `.woot-teaser` / `--discreet` (uma forma, foto e chips ocultos por CSS — o 10º aceite da D1). `sdk/specs/browser/teaser.check.mjs`: **10/10 asserções em Chromium**. 9º aceite (A13): gate publica o delta e o **gzip cabe** — 14.994 B ≤ 15.000 B. **Folga: 6 bytes** | **FEITO** ⚠ |
| **4.19** | Degradação por familiaridade | `sdk/tracking/approach.js` ⚪, `bubbleHelpers.js`, `cookieHelpers.js` | **sim** | sim — vitest | `approach.js`: cookie `"<abordagens>.<0\|1>"`, escada `aggressive→bold→discreet→nada`, 30 dias, `secure` sob HTTPS, sem `Date.now()`. `sdk/specs/approach.spec.js` **verde** | **FEITO** |
| **4.20** | Auto-open opt-in, desligado por padrão | `triggers/` (o aviso), `sdk/`, i18n | **sim** | **sim — o aceite literal do grep** | `AutoOpenWarningDialog.vue` + `sessionStorage 'cw_auto_open'`; celular fica em `bold` explicitamente. **Aceite `grep "Google"` nas strings desta tela → vazio: 0 ocorrências em 112 chaves de `TRIGGERS`/`APPROACH`/`AUTO_OPEN`, em `pt_BR` e em `en`** (varredura recursiva do JSON, não grep de linha) | **FEITO** |
| **4.21** | Instrumentação dos três níveis | `sdk/tracking/`, `sdkEvents.js`, listener de 5.03 | **sim** | sim — rspec + vitest | `widget/api/approachEvent.js` + `approach_events_controller.rb`; payload leva `approach` **e** `approach_configured`. `approach_events_spec.rb` **verde**; `sdk/specs/approach.spec.js` **verde** | **FEITO** |
| **4.22** | Coexistência com campanhas legadas, com precedência escrita | `widget/store/modules/campaign.js`, `sdk/`, `triggers/` | **sim** | sim — rspec + vitest | Precedência em **duas portas** (`campaign.js:29,133`); `LegacyCampaigns.vue` = a seção "modo antigo"; `Widget::CampaignImportService` importa e **desativa** a campanha. `campaign_import_to_trigger_spec.rb` e `campaign_import_service_spec.rb` **verdes** | **FEITO** |
| **4.07** | Teaser no preview, com gatilho simulado | `widget-preview/` | **sim** | sim — vitest | `widget-preview/components/WidgetTeaser.vue` (mesma regra de duas formas, cores por token). `WidgetTeaser.spec.js` **verde** | **FEITO** |
| **4.08** | Saída para WhatsApp no perfil marketing | `message-types/` ⚪, casca de `ChatFooter.vue` | **sim** | sim — vitest | `widget/components/WhatsAppExit.vue` + `helpers/profileConfigHelper.js` (`primaryExit`). `WhatsAppExit.spec.js` e `profileConfigHelper.spec.js` **verdes** | **FEITO** |
| **4.11** | Piscar do título 60 s; som **desligado** por default | `sdk/` ⚪, `IFrameHelper.js` | **sim** | sim — vitest | `sdk/specs/titleFlasher.spec.js` e `sdk/specs/notificationSound.spec.js` **verdes** | **FEITO** |
| **4.12** | `conversation_resolved` no webhook de conta | `webhook.rb:32-34`, `webhook_listener.rb` | **sim** | sim — rspec | `ALLOWED_WEBHOOK_EVENTS` inclui `conversation_resolved` (`webhook.rb:47`) + `WebhookListener#conversation_resolved` (`:29`). `webhook_listener_conversation_resolved_spec.rb` **verde** | **FEITO** |
| **4.13** | Assinar os 3 caminhos + filtro por inbox de verdade | `automation_rules/action_service.rb`, `macros/execution_service.rb`, `flows/action_service.rb`, `webhook_listener.rb` | **sim** | sim — rspec | `Webhook.signing_secret_for` nos **três** (e num quarto, `kanban/automation_engine_service.rb:123`); filtro por `inbox_id` real em `webhook_listener.rb:175-177` (*sem* `inbox_id` continua recebendo tudo). `webhook_listener_inbox_filter_spec.rb` **verde** | **FEITO** |
| **4.14** | Log de entregas + replay + rotação + parar de expor o segredo | tabela nova ⚪, `_webhook.json.jbuilder`, endpoints N4/N5 | **parcial** | sim — rspec (backend) | Backend **completo**: `20260819130000_create_webhook_deliveries`, modelo `WebhookDelivery`, ações `deliveries`/`replay`/`rotate_secret` (`webhooks_controller.rb:3,29,40`), jbuilder passa a expor só `has_secret`. `trigger_delivery_log_spec.rb` + `webhook_deliveries_and_secret_spec.rb` **verdes**. **Falta a metade do aceite que é tela**: nenhum componente do dashboard consome `webhook_deliveries` (`grep -rln` em `app/javascript/dashboard` → vazio), então *"a tela mostra a entrega falhada e o reenvio"* **não é observável** | **PARCIAL** |
| **4.15** | Três estados de enforcement de identidade | `inbox.rb`, `contacts_controller.rb`, `_inbox.json.jbuilder` | **sim** | sim — rspec | concern `IdentityEnforceable` (`identity_enforcement`, `..._observed_since`), `resolved_identity_enforcement` exposto no jbuilder (`:48`) e consumido em 3 controllers. `identity_enforcement_states_spec.rb` + `inbox_identity_enforcement_spec.rb` **verdes** | **FEITO** |
| **4.16** | Portas 3 e 4 do HMAC: pré-chat e `input_email` param de fundir | `contact_identify_action.rb`, `conversations_controller.rb`, `messages_controller.rb` | **sim** | sim — rspec | recusa de **merge** sob `STRICT` (`contact_identify_action.rb:77-84`), com o e-mail preservado em `submitted_email`. `identity_enforcement_prechat_spec.rb` **verde** | **FEITO** |
| **4.17** | Origem/confiança em `custom_attribute_definitions` + delimitar no prompt | migration ⚪, `custom_attribute_definition.rb`, `system_prompts_service.rb` | **sim** | sim — rspec | `20260818120000_add_origin_to_custom_attribute_definitions`; `ORIGINS`, `requires_verified_origin`, escopo por conta/modelo. `custom_attribute_origin_gate_spec.rb`, `custom_attribute_definition_spec.rb` e `system_prompts_service_contact_data_spec.rb` **verdes** | **FEITO** |
| **4.18** | Lead incompleto persistido antes de a conversa existir | tabela/serviço ⚪, `widget/capture/`, `PreChat/Form.vue`, painel | **sim** | sim — rspec | `20260818150000_create_widget_partial_leads` + `WidgetPartialLead` (ciclo de 4 fases, retenção declarada) + `Widget::PartialLeads::RecordService` + relatório (`api/v2/.../partial_lead_reports`). 4 specs **verdes** | **FEITO** |

### Fecho da Onda 3

**20 de 20 blocos com código na árvore.** As duas ressalvas não são "quase pronto": são **duas
metades de aceite que ninguém verificou até aqui** — o texto do teaser que não chega ao visitante
(4.05) e o log de entregas que não tem tela (4.14). As duas foram achadas abrindo o código, não
lendo relatório.

---

## 2. Onda 4 — Atribuição *(blocos `5.xx` · 22 blocos · 78 pontos · 20,8% do esforço)*

> **É aqui que o `ESTADO-18ago.md` erra mais feio** — ele marca **0**. A árvore tem 13 blocos
> fechados e 4 parciais. E é aqui também que está o buraco de verdade: **a metade server-side do
> tracking (5.02 → 5.11 → 5.12/5.13/5.14 → 5.21) não existe**, 28 dos 78 pontos.

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **5.01** | Config **pública** de tracking por inbox, recusando segredo | `inbox.rb`, schema JSON ⚪ | **sim** | sim — rspec | `WidgetConfigurable` (`store_accessor :widget_tracking`) + `WidgetTrackingSchema` + `WidgetTrackingProjection`. `inbox_tracking_config_spec.rb` **verde** (gravar `access_token` → 422) | **FEITO** |
| **5.02** | Tabela própria de credenciais com `encrypts` + **OAuth de um clique** Meta/Google | migration ⚪, modelo, controller N1/N2, policy, fluxo OAuth ⚪ | **NÃO** | não há o que verificar | **Nenhuma tabela de credenciais no `schema.rb`** (só `tracking_events` e `tracking_deliveries`); nenhum modelo `TrackingCredential`; nenhum fluxo OAuth. A própria tela do 5.06 declara a ausência: os `SecretField` saem `disabled` com `INBOX_WIDGET.TRACKING.BLOCKED_BY_502` (`TrackingPage.vue:198,274`) | **AUSENTE** |
| **5.03** | Contrato de eventos + `tracking_events`/`tracking_deliveries` com `event_id` | documento ⚪, migrations ⚪, 2 modelos, listener | **sim** | sim — rspec | `20260818140000/140100`; `TrackingEvent` (`dedup_key`, índice único `(account_id,name,dedup_key)`) e `TrackingDelivery` (índice único `(tracking_event_id,destination)`, `field_names` só nomes); `docs/tracking/contrato-de-eventos.md` (305 l.). 3 specs **verdes** | **FEITO** |
| **5.04** | Os 6 eventos que faltam, emitidos **uma vez**, do store | `sdkEvents.js`, ações do store, listener | **sim** | parcial — vitest sim, navegador não | Emissores no store + `widget/api/events.js`; renomear evento quebra o CI (fonte única de nomes). Vitest do `widget/` + `sdk/` **verde (1.681 testes)**. A parte *"a ordem é observável por `addEventListener` em navegador real"* mora em `spec/e2e/widget/sdkEvents.spec.js`, **não rodada** (§0) | **FEITO** |
| **5.05** | `event_id` nasce no backend, `204` → `200 {event_id}` | `events_controller.rb` | **sim** | sim — rspec | `events_controller.rb` responde `200 { event_id, name }` e mantém `PERMITTED_EVENT_NAMES`. `events_controller_spec.rb` + `events_tracking_spec.rb` **verdes** | **FEITO** |
| **5.06** | Tela 4 (rastreio): 4 sub-abas, `SecretField`, mapa de eventos, modo teste | `tracking/` ⚪ | **parcial** | sim — vitest + código | 5 componentes / **834 linhas**; **4 sub-abas** (Meta, Google, Eventos, Diagnóstico); modo teste com desligamento automático em 7 dias; `AccountScopeCard` mostra o kill switch da conta; a projeção pública chega ao HTML servido (`show.html.erb:67`, `public_widget_tracking`). Suíte da tela **verde**. **Mas as duas sub-abas de credencial são casca**: `SecretField` entra `disabled` porque 5.02 não existe | **PARCIAL** |
| **5.08** | Coletor de origem no SDK, carregado **sob demanda** | `sdk/tracking/` ⚪ + 1 linha em `IFrameHelper.js` | **sim** | sim — vitest | 12 módulos em `sdk/tracking/` (`capture`, `clickIds`, `googleIds`, `cookies`, `keys`, `loader`, `attach`…); o carregador fino usa URL de runtime para escapar do `inlineDynamicImports`, e o coletor sai como artefato próprio — **`public/packs/js/tracking.js` existe, 9.236 B**. `capture.spec.js`, `safariSurvival.spec.js`, `loader.spec.js` **verdes** | **FEITO** |
| **5.09** | Consentimento (Consent Mode v2 / LGPD), padrão negado | `sdk/tracking/` ⚪, serviço de estado | **sim** | sim — vitest | `sdk/tracking/consent.js` (5.378 B) + `sdk/specs/consentApi.spec.js` + `tracking/specs/consent.spec.js` **verdes** (asserção negativa: com CMP negando, zero disparos) | **FEITO** |
| **5.10** | Ponte de tags: `trackSingle`, `send_to`, `dataLayer` sempre, `skipPageView`, detecção | `sdk/tracking/tags.js` ⚪ | **parcial** | **sim — Chromium** | `tags.js` (10.722 B): `paraDataLayer`/`paraMeta`/`paraGoogleAds` com `eventID`/`transaction_id`, guarda de exceção, "somente dataLayer" como padrão. **`ponte-de-tags.check.mjs`: 36 asserções em navegador real, todas passaram**; `gtm-datalayer.check.mjs`: 9. **Falta T-C4.3** — instalação condicional da tag faltante com `skipPageView`: `install_tags` não existe no `WidgetTrackingSchema` (recusado por `additionalProperties`), nem na projeção, nem na tela. Cliente que cola o Pixel ID sem ter o pixel na página **não recebe nada, e não é avisado** | **PARCIAL** |
| **5.11** | Fila server-side: CAPI, Measurement Protocol e Enhanced Conversions | `app/services/tracking/` ⚪, `app/jobs/tracking/` ⚪ | **NÃO** | não há o que verificar | **`app/jobs/tracking/` não existe.** `app/services/tracking/` tem 6 arquivos e **todos são da trilha de origem da Onda 1** (`origin_parser`, `origin_recorder`, `origin_report`, `origin_attributes`, `origin_definitions_seeder`) mais o `event_recorder` do 5.03. Nenhum cliente de `graph.facebook.com`, de Measurement Protocol ou de Enhanced Conversions em `app/`, `enterprise/` ou `lib/` | **AUSENTE** |
| **5.12** | Modo "sem PII" — o caminho que não depende do jurídico | idem 5.11 | **NÃO** | não há o que verificar | Só existe a **fundação** que o 5.03 deixou pronta: `TrackingDelivery#field_names` valida que é lista rasa de strings ("nunca valores"). O modo em si não existe porque a fila que ele modula não existe | **AUSENTE** |
| **5.13** | Deduplicação de verdade: mesmo `event_id` nos dois caminhos, janela de 48 h | serviços | **parcial** | parcial | O lado **client** está pronto e medido: `eventID` no Meta, `transaction_id` no Ads, `chatspx_event_id` no dataLayer (`tags.js:171,184,223`, verificados em Chromium). O lado **server** não existe (5.11). **A janela de 48 h não está em lugar nenhum** — `grep "48"` em `tracking_event.rb` e `event_recorder.rb` → vazio. O aceite ("os dois eventos com o mesmo `event_id` no Test Events da Meta") é **NAO-VERIFICAVEL**: exige conta e credencial da Meta | **PARCIAL** |
| **5.14** | Auditoria e diagnóstico: log por evento, retenção, painel, botão de teste, kill switch, EMQ | modelo ⚪, `DiagnosticsPanel.vue` ⚪ | **parcial** | sim — código | `DiagnosticsPanel.vue` existe e implementa a regra dura (mostra **nomes**, nunca valores, com defesa em profundidade). Kill switch aparece em `AccountScopeCard` / `TrackingPage.vue:166`. **Mas o painel não tem fonte**: a própria prop se chama `unavailableReason` — *"Enquanto a leitura do log não existir, a tela diz por que está vazia"*. **Sem botão de teste** (`grep TEST_BUTTON\|sendTest\|test_event` no diretório → vazio) e **sem EMQ** | **PARCIAL** |
| **5.15** | Contrato público de integração + guia de verificação | documentação ⚪ | **sim** | não por comando | `docs/tracking/contrato-de-eventos.md` (305 l.) + `docs/tracking/guia-de-integracao.md` (228 l.). Aceite (*"um integrador que nunca viu o produto instala e dispara um evento só com o documento"*) é **NAO-VERIFICAVEL** por comando: exige uma pessoa que nunca viu o produto | **FEITO** |
| **5.22** | Instalação em WordPress, Wix e GTM | documentação ⚪, snippet, i18n | **sim** | **sim — Chromium (a metade R9)** | `docs/tracking/instalacao-por-plataforma.md` (202 l.), uma armadilha por plataforma. A regra **R9** (*"o snippet do GTM não sobrescreve `window.dataLayer` do cliente"*) é medida: `sdk/specs/browser/gtm-datalayer.check.mjs` → **9 asserções em navegador real**. A outra metade (*"uma pessoa instala num WordPress limpo seguindo só o documento"*) é NAO-VERIFICAVEL por comando | **FEITO** |
| **5.23** | "Recebido do site" ao lado da conversa | `ContactPanel.vue`, componente novo ⚪, i18n | **NÃO** | não há o que verificar | **O bloco foi executado e NÃO foi integrado.** O commit `758f8d6111` (branch `o4-resto`) cria `SiteContext.vue`, `helper/originAttributes.js` e 4 specs — **nenhum dos 5 arquivos está na árvore de `homologacao`**, e `git merge-base --is-ancestor 758f8d6111 HEAD` → falso. Os arquivos *tocados* pelo commit (i18n, `ContactPanel.vue`, `useUISettings.js`) existem, o que torna o engano fácil: o bloco **parece** presente por tabela e não está. `ContactPanel.vue` não importa `SiteContext` | **AUSENTE** |
| **5.16** | `track(name, properties)` — uma implementação | `sdk/`, `sdkEvents.js` | **sim** | sim — vitest | `sdk/specs/track.spec.js`, `sdk/specs/tagsWiring.spec.js`, `widget/bridge/handlers.js` + `handlers.spec.js` — **verdes** | **FEITO** |
| **5.17** | `company`, `signed_up_at`, dedupe do `setUser`, telefone identifica, regra de verbo | `widget/store/modules/contacts.js`, `cookieHelpers.js`, `ContactIdentifyAction` | **sim** | sim — vitest + rspec | `widget/helpers/identityPayload.js` + `sdk/specs/identityDedupe.spec.js` + `contacts.js`. `identityPayload.spec.js` e `contact_identify_action_spec.rb` **verdes** (mudar só o telefone volta a sair do navegador) | **FEITO** |
| **5.18** | `data-*` de **configuração** no snippet (nunca identidade) | snippet, `inbox.additional_attributes` | **sim** | sim — vitest | `sdk/snippetConfig.js` + `entrypoints/sdk.js`; `snippetConfig.spec.js` **verde**, com asserção negativa nos dois eixos | **FEITO** |
| **5.19** | JWT como formato **adicional**, HMAC legado | serviço irmão de `token_service.rb`, `contacts_controller.rb` | **sim** | sim — rspec | `app/services/widget/identity_token_service.rb` (ao lado de `token_service.rb`, sobre `base_token_service.rb`). `widget_identity_token_spec.rb` + `identity_token_service_spec.rb` **verdes** | **FEITO** |
| **5.20** | Mensagem proativa em **uma** chamada; bot lê a própria conversa | rota nova ⚪, `BOT_ACCESSIBLE_ENDPOINTS` | **sim** | sim — rspec | `proactive_messages_controller.rb` (`only: [:create]`, rota em `routes.rb:60`) + `index` liberado em `BOT_ACCESSIBLE_ENDPOINTS`. `proactive_messages_spec.rb` e `bot_reads_own_conversation_spec.rb` **verdes** | **FEITO** |
| **5.21** | Ciclo fechado: `gclid` 90 dias, negócio ganho → Ads/Meta/GA4, `ctwa_clid` | clientes de API ⚪, jobs ⚪, migration ⚪ | **NÃO** | não há o que verificar | `grep -rn "ctwa_clid"` em `app/` e `enterprise/` → **vazio**. Nenhum job de janela de atribuição, nenhum cliente de conversão offline. Depende de 5.11, que não existe | **AUSENTE** |

### Fecho da Onda 4

A **metade client-side está pronta e medida em navegador real**: coletor, consentimento, ponte de
tags, contrato de eventos, identidade, snippet, proativa, documentação. A **metade server-side não
começou** — e ela é onde moram os 8 pontos de 5.02, os 8 de 5.11 e os 8 de 5.21.

**Uma correção ao `ESTADO-21ago.md` §5.1**, que diz que **0.4 e 0.10** seguem travando
`5.02 → 5.11 → 5.14` e `5.21`. O commit `7b4ad0a371` (HEAD de hoje) executou os dois, mas o estado
é mais fino do que "resolvido", e a diferença muda o que dá para atacar:

- **Para escrever e testar o 5.02 aqui, o caminho está aberto.** Homologação foi reiniciada em
  24/08 17:34 e `Chatwoot.encryption_configured?` responde `true` no processo vivo.
- **Para o 5.02 chegar à frota, não está.** As chaves foram provisionadas nas 5 VMs alcançáveis
  mas **nenhuma foi reiniciada** — o processo vivo delas segue com `configured? = false` —, e
  ALTERNATIVO (`.169`) e PAULAO (`.100`) estavam **sem rota** e não foram tocadas. O aceite do
  0.10 (*"`true` em todas"*) continua **reprovado fora da homologação**
  (`onda-0-infra-0.4-0.10-EXECUTADO.md`).

O que trava 5.11 e 5.21 é outra coisa, e não é infraestrutura nossa: **verificação externa** (§7).

---

## 3. Onda 5 — A conversa *(blocos `2.xx`, mais 3.15, 4.09 e 4.10 · 21 blocos · 66 pontos · 17,6%)*

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **2.01** | Os **13** primitivos de `widget/ui/` (`aria-label` por prop) | `widget/ui/` ⚪ | **parcial** | sim — vitest | `widget/ui/` tem **12** `.vue` + `rotulos.js`, e o lint do bloco (`primitivosLint.spec.js`, que varre o diretório em vez de uma lista) está **verde**: nenhum importa de `dashboard/`, nenhum tem cor literal. **Mas 2 dos 13 da lista do plano 22 não estão lá**: `WAvatar.vue` e `WTypingDots.vue` moram em `widget/components/`, **fora do alcance do lint** — e `WAvatar.vue` tem **26 literais hex** no mapa de cores de avatar (`:43-52` e seguintes), exatamente o que a régua existe para pegar. (`WDateSeparator.vue` é um 12º que o plano não previu, e está sob a régua.) | **PARCIAL** |
| **2.02** | `MessageRow` unifica agente/visitante; agrupamento vira **dados** | `MessageRow.vue` ⚪, `useMessageGrouping.js` ⚪, `_conversation.scss` | **metade** | sim, **e reprova** | A metade dos **dados** está feita: `widget/composables/useMessageGrouping.js` existe, é consumido por `ConversationWrap.vue` (`:9`, `calcularAgrupamento`), e os seletores de irmão adjacente saíram do SCSS (comentário em `_conversation.scss:68`). A metade do **componente** não: **`MessageRow.vue` não existe**, e o aceite *"`AgentMessage`+`UserMessage` < 150 linhas somados"* mede **514 linhas** (335 + 179). A própria trilha registrou a pendência (`o5-baloes.md` §0.1, onde eram 471) | **PARCIAL** |
| **2.03** | Balões: raio 20/6, `max-width` 82%, sem sombra, corpo 15/22 | `AgentMessageBubble.vue`, `UserMessageBubble.vue`, `_conversation.scss` | **sim** | **sim — Chromium, 64/64** | `bubble-geometry.check.mjs` → **64/64 asserções**, nos dois temas, nas duas cores de teste, mais RTL. ⚠ **Só depois de corrigir o próprio verificador**: ver §5.1 — rodado como está no repositório ele dá **19/64**, medindo um CSS de julho | **FEITO** |
| **2.04** | Lista e scroll: fundo tokenizado, textura, auto-scroll condicional, botão "descer" | `ConversationWrap.vue`, `Messages.vue`, `WScrollToBottom.vue` ⚪ | **sim** | sim — vitest + arquivo | `ConversationWrap.vue` traz os três números do scroll e a textura como **máscara** (não `background-image`); `WScrollToBottom.vue` existe. Aceite *"textura < 30 KB"*: `public/assets/images/chat-spx-texture.webp` = **24.354 B** ✅. Suíte do `widget/` verde | **FEITO** |
| **2.05** | Composer: enviar **e** anexo, foco visível, `keydown`, cascas < 60 linhas | cascas em `ChatInputWrap.vue`/`ChatFooter.vue` → `WComposer.vue` ⚪ | **sim** | **sim — Chromium, 7/7** | `WComposer.vue` (108 l.); **cascas: `ChatInputWrap.vue` 36 linhas e `ChatFooter.vue` 55 — as duas abaixo de 60** ✅. `composer-geometry.check.mjs` → **7/7**, inclusive `font-size = 16px` no campo (que é o que devolve o zoom do 2.09) | **FEITO** |
| **2.06** | Header: 56/96, `<h1>` real, `<main>`, ações 40/44 | `ChatHeader.vue`, `ChatHeaderExpanded.vue`, `HeaderActions.vue`, `ViewWithHeader.vue` | **sim** | **sim — Chromium, 10/10** | `header-geometry.check.mjs` → **10/10** (inclusive alvos 40×40 com área de toque). `<h1>` real nos dois cabeçalhos, que são mutuamente exclusivos | **FEITO** |
| **2.07** | Estados de verdade: vazio, skeleton só acima de 600 ms, reconectando, offline, erro | `WBanner.vue` ⚪, `WSkeleton.vue` ⚪, `Banner.vue`, `BaseActionCableConnector.js` | **parcial** | sim, **e o aceite não é observável** | A **máquina de estados** existe, é alimentada e é testada com relógio falso: `widget/state/connectionMonitor.js` + `loadingGate.js`, `widgetConnectionMonitor.reportConnected/reportDisconnected` em `helpers/actionCable.js:47,63`; `connectionState.spec.js` **verde** (carência de 3.000 ms exata). O watchdog de 15 s passou a fazer trabalho (`BaseActionCableConnector.js:137`). **Mas ninguém LÊ o estado**: `grep -rn "widgetConnectionMonitor\|widgetLoadingGate"` fora de `specs/` devolve **só as 3 linhas que escrevem**, e `WBanner.vue`/`WSkeleton.vue` **não são importados por nenhum componente**. O aceite (*"rede cortada 10 s: nada nos 3 s, faixa depois"*) mede um módulo, não a tela | **PARCIAL** |
| **2.08** | Movimento + `prefers-reduced-motion` / `prefers-contrast` / `forced-colors` | `_tokens.scss`, `sdk.js`, componentes | **sim** | **sim — Chromium, 5/5** | `@media (prefers-reduced-motion: reduce)` em `sdk.js:421` (inclusive desligando a transição do teaser) e blocos `prefers-contrast: more` / `forced-colors` em `_tokens_values.scss`. `open-animation.check.mjs` → **5/5** | **FEITO** |
| **2.09** | Mobile: breakpoint único 768, `dvw/dvh`, safe-area, alvos 44×44, **devolver o zoom** | `sdk.js`, `IFrameHelper.js`, **`show.html.erb:6`** | **sim** | **sim — o aceite literal** | `show.html.erb:18` → `content="width=device-width, initial-scale=1"`: **sem `user-scalable=0` e sem `maximum-scale`** ✅ (era violação direta de SC 1.4.4 AA). Breakpoint 768 único (`sdk.js:306,529`, `IFrameHelper.js:225,703` documentando a volta do 667 pelo 4.06 e o conserto). `mobile-breakpoint.check.mjs` → **6/6**; `font-size ≥ 16px` fechado pelo 2.05 | **FEITO** |
| **2.10** | Dark mode completo: default `auto`, reativo, sem remount | `sdk.js`, `App.vue`, `useDarkMode.js`, `_tokens.scss` | **sim** | sim — vitest | `useDarkMode.js` com `DARK_QUERY` reativo (o valor congelava na 1ª avaliação); `App.vue:40` liga `color-scheme` no `:root`. Suíte do `widget/` verde | **FEITO** |
| **2.11** | `Esc` fecha e devolve o foco; `inert` no fundo em mobile | `widget/bridge/` ⚪, `IFrameHelper.js`, `bubbleHelpers.js` | **sim** | sim — vitest, **5/5** | `widget/bridge/closeOnEscape.js` + `closeOnEscape.spec.js` → **5 testes verdes**, inclusive o cleanup sem listener órfão. *(Na primeira corrida em lote 1 falhou por timeout de 5 s sob carga; isolado, o mesmo teste leva 309 ms e passa — era a máquina, não o código.)* | **FEITO** |
| **2.12** | Uma instância de MarkdownIt por valor de `linkify` + `v-memo` | `useMessageFormatter.js`, `MessageFormatter.js` | **sim** | sim — vitest | Cache por valor de `linkify` em `useMessageFormatter.js`; `v-memo` no `v-for` do template de `ConversationWrap.vue`. Suíte do `widget/`+`shared/` verde | **FEITO** |
| **2.13** | Telemetria de erro do widget, com PII removida | `widget/bridge/` ⚪, GlitchTip | **sim** | parcial — rspec sim, GlitchTip não | `widget/helpers/telemetry.js` + `Widget::ErrorReport` + `telemetry_controller`. `telemetry_controller_spec.rb` e `error_report_spec.rb` **verdes**. *"o erro aparece no GlitchTip"* é **NAO-VERIFICAVEL** aqui: exige o serviço externo recebendo evento | **FEITO** |
| **2.14** | Degradação do launcher: bundle falhou → canal alternativo | `sdk.js`, snippet | **sim** | parcial — rspec sim, E2E não | `Channel::WebWidget#fallback_label_json` / `#fallback_style_json` / `fallback_bootstrap_js` (`web_widget.rb:94-143`) + i18n nos dois idiomas; `web_widget_fallback_snippet_spec.rb` **verde**. O E2E que bloqueia o bundle no devtools (`spec/e2e/fallback/`) **não foi rodado** (§0) | **FEITO** |
| **2.15** | Idempotência de envio (chave por mensagem) | `widget/api/conversation.js`, backend | **sim** | sim — rspec | `echo_id` deixou de ser virtual e é gravado em `source_id` (coluna e índice que já existiam); `existing_message_for_retry` em `messages_controller.rb:24`. `messages_idempotency_spec.rb` **verde** | **FEITO** |
| **2.16** | Fila offline de **intenções** (nunca de estados transitórios) | `widget/offline/` ⚪ | **sim** | sim — vitest | `widget/offline/queue.js` (87 l.) + `queue.spec.js` **verde** | **FEITO** |
| **2.17** | i18n: `"mandatório"` → **"obrigatório"**, erro por campo | `widget/i18n/locale/pt_BR.json` | **sim** | **sim — o aceite literal** | `grep -rn "mandatório" app/javascript/widget/i18n/` → **vazio** ✅ | **FEITO** |
| **2.18** | Peso, 2ª rodada: chunk de vendor, FormKit lazy, i18n sob demanda | `vite.shared.ts`, `entrypoints/widget.js`, `widget/i18n/index.js` | **NÃO** | não há o que verificar | `grep "manualChunks\|amplitude\|Sentry"` em `vite.shared.ts` e `vite.config.ts` → **vazio**. A própria trilha o registrou como **BLOQUEADO por 2.\*** (`o5-movimento.md`, "Estado dos blocos"). O gate confirma o efeito: o grafo do widget está em **392.416 B gzip** contra teto de 300.000 | **AUSENTE** |
| **3.15** | O widget honra `mask`/`validator`/`step`/`show_if` — por delegação | casca em `PreChat/Form.vue` → `widget/ui/WField.vue` ⚪ | **sim** | sim — vitest | `widget/helpers/preChatFieldRules.js` (reexporta `shared/helpers/brMasks`, sem segundo dicionário) + `PreChat/specs/Form.conditional.spec.js` **verde**; os 4 operadores de `show_if` testados um a um. **Duas ressalvas declaradas**: a chave `position` é aceita pelo schema e **não é consumida** (`o5-migrados.md` §1.4), e `Form.vue` **não virou casca** — segue com 559 linhas | **FEITO** ⚠ |
| **4.09** | Identidade de IA: rótulo no header e na bolha, `aria-busy`, 3 marcações | `ChatHeader.vue`, `message-types/`, `ConversationWrap.vue` | **sim** | **sim — Chromium, 9/9** | `handoff-mark-color.check.mjs` → **9/9 asserções em Chromium**, incluindo *"nunca roxo como marcador"*. `avatar-aria.check.mjs` → 4/4 | **FEITO** |
| **4.10** | CSAT redesenhado (nunca antes do encerramento; polegar para IA) e cards | `CustomerSatisfaction.vue`, `StarRating.vue`, `ChatCard.vue` | **parcial** | **sim — Chromium, 6/6 do que existe** | `role="radiogroup"` + `role="radio"` com rótulo textual (`CustomerSatisfaction.vue:187,199`); `csat-target-size.check.mjs` → **6/6** (alvos 44×44); teto de 3 botões por card. **Dois itens do título estão abertos, e os dois exigem backend**: *"nunca antes do encerramento"* (quem cria a mensagem de CSAT é o servidor; o componente não recebe sinal de encerramento) e *"polegar para IA"* — `CSAT_DISPLAY_TYPES` em `shared/constants/messages.js:87` tem **só `emoji` e `star`**, e criar o valor só no consumidor é a assimetria que a paridade do 0.6 existe para pegar | **PARCIAL** |

### Fecho da Onda 5

O acabamento visual **está entregue e medido em navegador de verdade** — balões, header, composer,
movimento, mobile, dark mode, `Esc`. As quatro parciais têm a mesma assinatura: **o mecanismo
existe, o consumidor não**. Primitivo fora do diretório que o lint varre (2.01), composable sem o
componente que ele deveria alimentar (2.02), máquina de estados que ninguém lê (2.07), CSAT à
espera de duas decisões do servidor (4.10).

---

## 4. Onda 6 — IA e otimização *(blocos `6.xx` · 5 blocos · 25 pontos · 6,7% do esforço)*

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **6.01** | Guardrail de **pré-envio**: retém antes, em vez de anotar depois | `episode_gate_service.rb` (extração), serviço novo ⚪, caminho de envio | **sim** | sim — rspec | `enterprise/app/services/captain/response_guardrail_service.rb` + `enterprise/lib/captain/gate_asserts.rb` (asserts extraídos) + `tool_trace_window.rb`, ligados em `response_builder_job.rb`. `response_guardrail_service_spec.rb`, `response_builder_job_guardrail_spec.rb` e `gate_asserts_spec.rb` **verdes**. Custo zero de LLM é asserção sobre contagem de chamadas | **FEITO** |
| **6.02** | **Eval como produto**: casos por assistente, execução, veredito, comparação | modelos/serviços existentes + tela nova ⚪ | **sim** | sim — rspec | Modelos `Captain::EvalCase` / `EvalRun` / `EvalCaseResult`; serviços `Eval::RunService`, `CaseRunnerService`, `ComparisonService`, `AssistantResponder`; controllers `eval_cases`/`eval_runs`; **tela**: `agents/pages/EvaluationPage.vue` + `components-next/agents/tabs/EvalTab.vue` + `api/captain/eval.js`. Os 2 controller specs **verdes** | **FEITO** |
| **6.03** | Citação de fonte vira **metadado da mensagem** | `search_knowledge_tool.rb`, `content_attributes`, `widget/message-types/` ⚪ | **sim** | sim — rspec + vitest | `enterprise/lib/captain/citation_window.rb` + `search_knowledge_tool.rb` + persistência em `content_attributes.citations`; consumidor `widget/message-types/CitationList.vue`, registrado no registry do 1.10. `citation_window_spec.rb`, `response_builder_job_citation_spec.rb` e `citationList.spec.js` **verdes** | **FEITO** |
| **6.04** | **Facade**: o app carrega no primeiro clique, não no primeiro paint | `sdk/`, `IFrameHelper.js`, `entrypoints/` | **NÃO** | não há o que verificar | `grep -rn "querySelectorAll('iframe')\|facade\|onFirstClick"` em `app/javascript/sdk/` → **vazio**. `IFrameHelper.createFrame` (`:104`) segue sendo chamado na carga. Depende de **1.08** (Onda 1) e **2.18**, e o plano é explícito: facade sobre bundle gordo troca "pesado sempre" por "lento quando abre" | **AUSENTE** |
| **6.05** | **Teste A/B de fluxo, versionado** | `flow.rb`, serviço de designação ⚪, relatório | **sim** | sim — rspec | `Flows::AbTracking` (designação estável por `contact_inbox.source_id`, exposição como denominador, `variant_version`), `Flows::AbReportService`, `Flow::AbExperiment`, `widget_prechat_resolver` com `visitor_key`. 5 specs **verdes** (`ab_end_to_end`, `ab_report_service`, `ab_tracking`, `ab_experiment`, `flows_experiment`) | **FEITO** |

### Fecho da Onda 6

Quatro de cinco entregues — e o que falta é o único **G** da onda, o facade, que o próprio plano
manda deixar por último. **A condição escrita na §4 do plano vale hoje:** com 6.01 existindo, o
widget de marketing **pode** sair com IA ligada — era isso que a exceção da Onda 3 travava.

---

## 5. Dois achados de método que mudariam vereditos se ninguém olhasse

### 5.1 O verificador do 2.03 mede um CSS de julho — e reprova o bloco por isso

`bubble-geometry.check.mjs:68` e `unread-bubble-contrast.check.mjs:48` escolhem o CSS assim:

```js
const arquivo = readdirSync(dir).find(f => /^widget-.*\.css$/.test(f));
```

`readdirSync().find()` pega o **primeiro em ordem de diretório**, não o do build. E `public/vite/assets/`
guarda **7** `widget-*.css`, sendo o primeiro `widget-B98UQrMr.css`, de **27/07**, 1.103.138 B — um
artefato anterior ao redesenho. O do manifest é `widget-DkkDNx07.css`, de 21/08, 93.726 B.

| Corrida | Resultado |
|---|---|
| como está no repositório (CSS de 27/07) | **19/64** — raio 4px em vez de 6, corpo 14/21 em vez de 15/22, largura 88% em vez de 82% |
| com o CSS do manifest | **64/64** |

Não é detalhe de encanamento: **lido como está, o verificador reprova um bloco que está correto**, e
os números que ele imprime são plausíveis o bastante para virar um relatório de regressão. A correção
é ler `.vite/manifest.json` (chave `entrypoints/widget.js` → `css[0]`) em vez de varrer o diretório.
**Não corrigi** — está fora do recorte desta auditoria, que é somente leitura.

### 5.2 `focus-ring.check.mjs` ficou órfão do próprio sujeito

Ele falha com `FALHA: não localizei as classes do composer em ChatInputWrap.vue`. A razão é que o
bloco **2.05 fez exatamente o que devia**: transformou `ChatInputWrap.vue` numa casca de 36 linhas e
mudou as classes para `WComposer.vue`. O verificador é do bloco **1.06** (Onda 1), procura
`'…shadow-focus…': isFocused` dentro de `ChatInputWrap.vue` (`:33,48`) e continua apontando para o
arquivo antigo.

**Conferido antes de chamar de falso vermelho:** o anel existe e é real —
`WComposer.vue:98-100` traz `&:focus-visible { outline: var(--w-focus-ring-width) solid
var(--w-focus-ring-color); outline-offset: … }`, que é a asserção *"`outline-color` não
transparente"* do 1.06 satisfeita por token, não por sombra. **Não é aceite reprovado; é verificador
desatualizado** — mas hoje é um vermelho permanente, e vermelho permanente treina gente a ignorar
vermelho, que é o risco **R17** do próprio plano.

*(No mesmo espírito, e também fora do recorte: `launcher-hover.check.mjs`, do bloco 1.05, roda e dá
**4/7**. Não investiguei se é aceite ou verificador — só registro que não está verde.)*

### 5.3 O gate de peso está VERMELHO, e o `sdk.js` tem 6 bytes de folga

Não é bloco destas quatro ondas — é o **0.5**, da Onda 0 —, mas governa dez blocos que já entraram e
todos os que ainda vão engordar o `sdk.js`, então entra aqui. `node scripts/widget-size.mjs`, contra
o build vigente (`public/packs/js/sdk.js`, 21/08 06:24; **nenhuma fonte de `sdk/` ou `entrypoints/`
é mais nova que ele**, então a medição é válida):

| Medida | Valor | Teto | Situação |
|---|---:|---:|---|
| `sdk.js` **cru** | **45.229 B** | 40.000 B | **FALHA (+5.229 B)** — classificada pelo próprio gate como *regressão nova* |
| `sdk.js` **gzip** | **14.994 B** | 15.000 B | OK — **folga de 6 bytes** |
| grafo do widget (gzip) | 392.416 B | 300.000 B | dívida conhecida, dono nomeado: bloco **1.08** |
| linha de base §12 | 29.014 B crus / 9.595 B gzip | — | delta: **+55,89% cru / +56,27% gzip** |

A leitura prática: **o aceite literal do 4.06 ("cabe no teto de 15 KB gzip") passa, e passa por
6 bytes.** Qualquer bloco que ainda acrescente byte *eager* ao `sdk.js` — e 6.04 é exatamente isso —
estoura o gzip também. **O teto cru já está estourado hoje.**

---

## 6. Resumo

### 6.1 Por onda, em blocos e em pontos de esforço

Escala do plano §0.5: **P = 1 · M = 3 · G = 8 · P/M = 2 · M–G = 5**. As quatro somas batem com o
total declarado no cabeçalho de cada onda (76, 78, 66, 25), o que é a conferência de que nenhuma
linha foi perdida nem contada duas vezes.

| Onda | Blocos | FEITO | PARCIAL | AUSENTE | Pontos | FEITO (pts) | PARCIAL (pts) | AUSENTE (pts) | **% FEITO por esforço** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **3** — Captura (`4.xx`) | 20 | **18** | 2 | 0 | 76 | 70 | 6 | 0 | **92,1%** |
| **4** — Atribuição (`5.xx`) | 22 | **13** | 4 | 5 | 78 | 35 | 15 | 28 | **44,9%** |
| **5** — A conversa (`2.xx`+3) | 21 | **16** | 4 | 1 | 66 | 41 | 17 | 8 | **62,1%** |
| **6** — IA e otimização (`6.xx`) | 5 | **4** | 0 | 1 | 25 | 17 | 0 | 8 | **68,0%** |
| **Total das 4 ondas** | **68** | **51** | **10** | **7** | **245** | **163** | **38** | **44** | **66,5%** |

As quatro ondas somam **245 dos 375 pontos do plano inteiro (65,3%)**. Os 163 pontos FEITOS aqui são
**43,5% do plano inteiro** — sem contar nada das Ondas 0, 1 e 2, que este documento não auditou.

### 6.2 O que mudou de veredito em relação ao `ESTADO-18ago.md`

| Onda | `ESTADO-18ago.md` diz | Esta auditoria mede | Delta |
|---|---|---|---|
| **3** (`4.xx`) | "**6** fechados"; faltam identidade, gatilhos, webhooks, teaser | **18 FEITO + 2 PARCIAL** de 20 | **+12 blocos**. Identidade (4.15–4.17), gatilhos (4.04–4.11), webhooks (4.12–4.14) e teaser (4.06/4.19/4.20) estão **todos na árvore e com spec verde** — exatamente os quatro grupos que aquele documento lista como faltantes. Ele também **não conhece o 4.22** |
| **4** (`5.xx`) | "**0**"; "5.01 e 5.03 em curso"; tudo *gated* pelo 0.10 | **13 FEITO + 4 PARCIAL + 5 AUSENTE** de 22 | **+13 blocos.** Toda a metade client-side existe: coletor (5.08), consentimento (5.09), ponte de tags (5.10, medida em Chromium), eventos (5.04/5.05/5.16), identidade (5.17/5.19), snippet (5.18), proativa (5.20), tela (5.06) e 735 linhas de documentação (5.15/5.22). O *gate* do 0.10 **não vale mais para escrever aqui** |
| **5** (`2.xx`) | "**5**"; 2.02–2.04 e 2.12 em curso | **16 FEITO + 4 PARCIAL + 1 AUSENTE** de 21 | **+11 blocos.** 2.03, 2.04 e 2.12 fecharam; 2.02 continua **meio feito**, e aquele documento estava certo em não contá-lo |
| **6** (`6.xx`) | "**0**"; "tudo *gated* por 4.09 e 2.18" | **4 FEITO + 1 AUSENTE** de 5 | **+4 blocos.** 4.09 fechou, então 6.01/6.03 destravaram; 6.02 e 6.05 nunca dependeram de 2.18. Só **6.04** segue *gated*, e por 1.08+2.18 — não por 4.09 |

**A razão da divergência não é que alguém errou.** O `ESTADO-18ago.md` descreve a branch
`redesenho-integra` em 18/08. O recorte pousou em `homologacao` depois disso, com 74 commits
locais (`ESTADO-21ago.md`), e ninguém reescreveu o rastreio por onda. Usar o documento de 18/08 hoje
não é ler um número velho: é **reabrir 40 blocos já entregues**.

**E há a divergência no outro sentido, que é a mais perigosa das duas:** o `o4-instalacao.md` declara
o **5.23** entregue no commit `758f8d6111`, e ele **não está na árvore** (§2). Relatório de trilha
diz o que a trilha fez no worktree dela; só a árvore diz o que foi integrado. **As duas fontes têm de
ser lidas juntas, e quem decide é a árvore.**

---

## 7. Ordem sugerida de ataque

**Como esta ordem foi montada.** A coluna *Depende* da tabela mestra §2.2 de cada bloco, cruzada com
o veredito de quem ele depende. Um bloco só entra num grupo depois de todos os seus antecedentes
estarem FEITOS ou no mesmo grupo, acima dele. A coluna **Externo** separa o que **não se resolve com
código**: verificação jurídica (DPA), acesso de leitura à produção, cadastro de aplicativo em Meta e
Google.

### Grupo A — só código, sem nenhuma porta externa aberta *(37 pontos)*

| # | Bloco | Esf. | Depende (estado) | O que exatamente falta | Externo? |
|---:|---|:---:|---|---|:---:|
| 1 | **5.23** "Recebido do site" | M (3) | 1.17 ✅, 1.19 ✅, 4.15 ✅ | **Nada de projeto: integrar.** O código existe no commit `758f8d6111` (branch `o4-resto`) e são 5 arquivos que não pousaram — `SiteContext.vue`, `helper/originAttributes.js` e 3 specs. É o maior retorno por hora desta lista | não |
| 2 | **2.01** os primitivos | G (8) | 1.01 ✅ | Trazer `WAvatar.vue` e `WTypingDots.vue` para `widget/ui/` — e então o lint passa a cobri-los, o que fará os **26 literais hex** do `WAvatar` falharem, que é o ponto. **É o desbloqueador de 3 e 4 abaixo** | não |
| 3 | **2.07** estados de verdade | M (3) | 2.01 (grupo A #2) | Ligar o consumidor: nada lê `widgetConnectionMonitor`/`widgetLoadingGate` hoje, e `WBanner`/`WSkeleton` não são importados por componente nenhum | não |
| 4 | **2.02** `MessageRow` | M (3) | 2.01 (grupo A #2) | O componente unificado. `AgentMessage`+`UserMessage` = **514 linhas** contra teto de 150 | não |
| 5 | **4.05** teaser ↔ campanha | M (3) | 4.04 ✅ | A junção 4.05↔4.06: fazer a campanha vinculada viajar no payload de boot, ou o teaser ler dela. Hoje editar o texto **não muda o que o visitante vê**. **Urgente antes de o 4.22 chegar a cliente**: com o gatilho novo ligado, a campanha legada para de disparar e o texto escrito no compositor não aparece em lugar nenhum | não |
| 6 | **4.14** tela de entregas de webhook | M (3) | 1.13 ✅ | Só a metade de front: os endpoints `deliveries`/`replay`/`rotate_secret` já existem e têm spec verde | não |
| 7 | **5.10** T-C4.3 | M (3) | 5.08 ✅, 5.09 ✅, 5.04 ✅ | `install_tags` no `WidgetTrackingSchema` + projeção pública + interruptor na tela (opt-in, default desligado — decisão **Q5**, já tomada) + instalação condicional com `skipPageView` no `tags.js` | não |
| 8 | **4.10** CSAT: os 2 itens abertos | M (3) | 2.01 (grupo A #2), 1.10 ✅ | `CSAT_DISPLAY_TYPES` ganhar o valor de polegar **nas três pontas** (backend que grava, dashboard, widget — senão a paridade do 0.6 pega) e o sinal de encerramento que decide *quando* a mensagem de CSAT nasce. **Exige decisão de produto**, não credencial externa | não |
| 9 | **2.18** peso, 2ª rodada | G (8) | 0.5 ⚠ (gate **vermelho**), 2.\* ✅ | Chunk de vendor próprio, FormKit só na rota do pré-chat, i18n sob demanda. O grafo está em **392.416 B gzip** contra teto de 300.000 | não |

### Grupo B — depende do Grupo A, ainda sem porta externa *(8 pontos)*

| # | Bloco | Esf. | Depende (estado) | Observação | Externo? |
|---:|---|:---:|---|---|:---:|
| 10 | **6.04** facade | G (8) | **1.08** (Onda 1, não auditada aqui — mas o gate mostra o grafo 30,8% acima do teto, então **não** está fechada), 2.18 (grupo A #9), 4.06 ✅ | O plano é explícito: facade sobre bundle gordo troca *"pesado sempre"* por *"lento quando abre"*, que é pior para quem abre. **Não antecipar** | não |

### Grupo C — travado por porta EXTERNA, não por código *(37 pontos)*

| # | Bloco | Esf. | Depende | **O que é a porta externa** | Dá para começar algo? |
|---:|---|:---:|---|---|---|
| 11 | **5.02** credenciais + OAuth | G (8) | 0.10 ⚠, 5.01 ✅ | **Cadastro de aplicativo em Meta e em Google**: App ID/secret, revisão de app, escopos de Ads. Sem isso não existe "um clique" — e o plano trata o OAuth como **requisito de produto**, não enfeite. **Segunda porta:** o 0.10 está PASS só em homologação; a frota foi provisionada e **não reiniciada**, e 2 VMs estavam sem rota | **Sim, metade.** A tabela cifrada, o `encrypts` por segredo, o `audited` com `except:`, a serialização `configured` + 4 últimos caracteres e o `verify` em modo teste são **só código**, e destravam o 5.06 |
| 12 | **5.06** tela de rastreio (o resto) | G (8) | 5.02 (#11) | herdada do #11 | não antes do #11 |
| 13 | **5.11** fila server-side | G (8) | 5.02 (#11), 5.03 ✅, **V2** | **DPA — jurídico/comercial.** Três perguntas objetivas (§7 do plano): o contrato vigente prevê tratamento por conta do cliente com subcontratação declarada? Existe aditivo? Quem assina, e o que fazer com quem recusar? **Não é verificável por código** | o esqueleto da fila (job, retry com backoff, DLQ) não depende do DPA — só o *conteúdo* PII depende |
| 14 | **5.12** modo "sem PII" | P (1) | 5.11 (#13) | **NENHUMA.** Este bloco existe **exatamente** para ser o caminho que não espera o jurídico — o plano diz que sem DPA ele *"vai ao ar assim mesmo e recupera parte dos 20–40% perdidos por bloqueador"* | **Sim** — assim que a fila do #13 existir, mesmo sem resposta do DPA |
| 15 | **5.14** auditoria e diagnóstico | M (3) | 5.11 (#13) | parcial: a **leitura do log** não precisa de externo (a tabela `tracking_deliveries` já existe desde o 5.03), mas o EMQ vem da Meta | **Sim, parte.** Endpoint de leitura + botão de teste podem sair antes do #13 |
| 16 | **5.13** dedup de verdade | P (1) | 5.10 ✅(parcial), 5.11 (#13) | O **aceite** exige o *Test Events* da Meta — conta e credencial de cliente | a janela de 48 h e a guarda são código |
| 17 | **5.21** ciclo fechado | G (8) | 5.11 (#13), **V1** | **V1** — *"o webhook do WhatsApp Cloud entrega hoje o objeto `referral` com `ctwa_clid`?"*. Precisa de **acesso de leitura à produção** (homologação tem **zero** mensagens com `referral`, então não serve de amostra). Conforme a resposta, o bloco cai de **G** para **M**, porque a ingestão já existe | a consulta está pronta e testada no §7 do plano — é uma pergunta de minutos para quem tem o acesso |

### O que isso quer dizer em uma frase

**Dos 82 pontos ainda em aberto nestas quatro ondas, 45 (55%) são só código** — os grupos A e B, e
o grupo A inteiro pode começar hoje. **Os outros 37 (45%) esperam três respostas que não são de
engenharia**: o DPA (V2), o acesso de leitura à produção (V1) e o cadastro de aplicativo em
Meta/Google. Dentro desses 37 ainda há trabalho de código adiantável, nomeado na última coluna do
grupo C. **E o item mais barato da lista inteira é o #1:** o 5.23 já está escrito e só não foi
integrado.

---

## 8. Anexo — o que rodou nesta auditoria

| Ferramenta | Escopo | Resultado |
|---|---|---|
| **rspec** (`POSTGRES_DATABASE=chatwoot_test_7`) | 4 lotes, 39 arquivos de spec dos blocos das Ondas 3, 4 e 6 | **547 exemplos, 0 falhas** (214 + 237 + 57 + 39) |
| **vitest** | 3 corridas, com sobreposição: (a) `widget/{ui,bridge,capture,offline}` + `sdk/tracking` → **316 testes**; (b) `dashboard/.../inbox/widget/` + `widget-preview/` + `widget/message-types/` → **664 testes, 34 arquivos**; (c) `widget/` + `sdk/` + `shared/` → **1.681 testes, 148 arquivos** | **0 falhas** nas três. Na corrida (a), 1 teste caiu por *timeout* de 5 s sob carga; isolado leva 309 ms e passa — era a máquina |
| **`*.check.mjs`** (Chromium real) | **14** verificadores rodados | **12 verdes.** 2 vermelhos, e **nenhum dos dois é aceite reprovado**: `bubble-geometry` (verde 64/64 com o CSS do manifest — §5.1) e `focus-ring` (verificador desatualizado — §5.2). Fora do recorte: `launcher-hover` **4/7** (bloco 1.05) |
| **Playwright** | `spec/e2e/widget/capture/` (porta efêmera) | **3 passed** — o aceite de 375 px do 4.03 |
| **`scripts/widget-size.mjs`** | gate de peso do bloco 0.5 | **VERMELHO**: 1 regressão nova (`sdk.js` cru) + 1 dívida conhecida (grafo) — §5.3 |

**Nada foi alterado fora deste arquivo.** Nenhuma migration rodou, nenhum banco de produção foi
tocado, nenhum build foi disparado, nada foi pushado. O único arquivo auxiliar criado
(`bubble-check-manifest.mjs`, a cópia corrigida do verificador da §5.1) vive no diretório temporário
da sessão, fora do repositório.
