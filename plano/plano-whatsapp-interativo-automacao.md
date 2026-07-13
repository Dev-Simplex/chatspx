# Plano — WhatsApp interativo (lista/botões) nas Automações (Flow)

> Objetivo do Walisson (13/07/2026): hoje a automação **só envia template**. Trazer o leque da **API oficial do WhatsApp** pra dentro do canvas — em especial **lista/botões interativos** — e fechar o **loop**: enviar lista → pessoa escolhe → **ramifica na escolha** → executa ações (enviar mensagem, transferir pra time).
> Base: 2 agentes mapearam código (envio WhatsApp oficial + motor Flow) + doc oficial Meta. Ambiente `.232` (homologação).

---

## 0. TL;DR — o que já existe vs o que falta

**Já existe (infra pronta, não precisa construir):**
- ✅ **Canal oficial já ENVIA botões/lista interativos.** `WhatsappCloudService#send_interactive_text_message` + `base_service.rb#create_payload_based_on_items`: uma mensagem com `content_type: 'input_select'` + `content_attributes.items = [{title, value}]` vira **botões (≤3 itens)** ou **lista (>3 itens)** automaticamente. Vale também pra 360dialog. **Zero código de canal.**
- ✅ **FlowRun já sabe PAUSAR e RETOMAR.** `flow_run.rb`: enum `status: active/waiting/completed/failed`, colunas `current_node_id` (onde retomar) + `wait_until` (quando) + `context` (jsonb, variáveis acumuladas). O `RunnerService` tem semântica `HALT`, e o nó `wait` já suspende. Índice único parcial garante **≤1 run in-flight por (flow, conversa)**.
- ✅ **Ramificação já existe.** Nós `condition` (true/false) e `router` (first-match + fallback) — `runner_service.rb#evaluate_router`. Arestas com `branch`.
- ✅ **Ações reutilizáveis já no catálogo:** `send_message`, `assign_team` (transferir time), `assign_agent`, `add_label`, `change_status`, etc.

**Os 3 gaps (o que falta de fato):**
1. **A automação não consegue EMITIR interativo.** `Flows::ActionService#send_message` (e o clássico) hardcodam **texto puro** — nunca setam `input_select`/`items`. → precisa **nó novo `send_interactive`**.
2. **A resposta é capturada pela METADE.** `incoming_message_service_helpers.rb#message_content` guarda só o **título** da opção escolhida; **descarta o `id`** (`button_reply.id`/`list_reply.id` = o `value` da opção). Tem `# TODO` no código. → ramificar por texto é frágil; precisa **persistir o `id`**. (O lado WAHA já faz isso via `poll_vote`.)
3. **Não há retomada por MENSAGEM.** O `wait` só tem `wait_until` (tempo); `ResumeJob` só pega `FlowRun.due` (venceu o tempo). Não existe "esperar a resposta do usuário". → precisa **nó `wait_for_reply`** + hook no `message_created` que ache o run in-flight e retome + **ramificar pelo `context`**.

---

## 1. Catálogo COMPLETO — todas as opções de envio da API oficial → status no nosso código

| Tipo oficial (Meta) | O que é | Canal já envia? | Nó na automação hoje | Recomendação |
|---|---|---|---|---|
| `text` | Texto livre | ✅ `send_text_message` | ✅ `send_message` | pronto |
| `image`/`video`/`audio`/`document`/`sticker` | Mídia | ✅ `send_attachment_message` | ✅ `send_attachment` | pronto |
| `location` | Enviar localização | ✅ `send_location_message` | ⚠️ via attachment, sem nó dedicado | nó F3 |
| `contacts` | Cartão de contato | ✅ `send_contacts_message` | ❌ | nó F3 (nicho) |
| `reaction` | Reagir com emoji | ❌ | ❌ | baixa prio |
| **`interactive.button`** (≤3) | **Botões de resposta** | ✅ via `input_select` | ❌ | **F1 — nó `send_interactive`** |
| **`interactive.list`** (até 10 linhas/10 seções) | **Lista** | ✅ via `input_select` | ❌ | **F1 — mesmo nó** |
| `interactive.cta_url` | Botão que abre link | ❌ não montado | ❌ | F3 (nice-to-have) |
| `interactive.location_request_message` | Pedir a localização do cliente | ❌ não montado | ❌ | F3 (útil) |
| `interactive.address_message` | Formulário de endereço | ❌ (regional) | ❌ | baixa prio |
| `interactive.flow` (**WhatsApp Flows**) | Formulário multi-etapa nativo | 🟡 payload montado, **sem envio** (StepSkip `whatsapp_flow_provider_missing`) | ❌ (stub `whatsapp_flow_action.rb`) | F3 — mais caro |
| `interactive.product`/`product_list` | Catálogo/loja | ❌ (precisa catálogo Meta) | ❌ | fora de escopo |
| `template` | Template aprovado (único fora da janela 24h) | ✅ `send_template` | ✅ `send_template` | pronto |

**Limites oficiais (pra montar o nó certo):** botões = **máx 3** (título 20 chars) · lista = **máx 10 seções / 10 linhas no total** (título da linha 24, descrição 72, título da seção 24, label do botão da lista 20) · body 1024 · header/footer 60. ⚠️ O builder atual (`base_service.rb`) usa **1 seção fixa, sem descrição/header/footer e SEM cap de 10** → >10 itens estoura na Meta. F1 precisa endurecer isso.

---

## 2. ⚠️ Restrição de negócio que muda o design: janela de 24h

Interativo (lista/botões) **só é entregue dentro da janela de 24h** — quando o cliente mandou mensagem nas últimas 24h (`can_reply? == true`). Fora dela, a Meta **exige template** (`send_on_whatsapp_service.rb#perform_reply` força template quando `can_reply? == false`).

- **Fluxo de resposta** (cliente falou, bot responde com lista) → janela **aberta**, funciona liso. É o caso do Walisson.
- **Fluxo frio** (disparo ativo) → o **primeiro toque tem que ser template**; a lista só depois que o cliente responder.
- O nó `send_interactive` deve tratar "janela fechada" com elegância: `StepSkip` claro (ou fallback pra template). O `enforce_compliance!(free_form: true)` já existe pra isso.

---

## 3. Plano em fases

### F1 — Enviar lista/botões a partir do canvas (CAMINHO CURTO)
**Entregável:** um nó novo no canvas que dispara uma lista/botões interativos. Infra de canal já pronta.
1. `nodeCatalog.js`: item `{ key:'send_interactive', type:'action', actionName:'send_interactive', family:'msg', icon, label }`.
2. `Flow::BASE_ACTION_NAMES` (+ enterprise): somar `send_interactive` (senão o Flow nem salva).
3. `Flows::ActionService#send_interactive`: cria outgoing com `content_type: 'input_select'` + `content_attributes: { items: [{title, value}] }` via `Messages::MessageBuilder` (espelha `send_message`). Respeita janela 24h.
4. **Endurecer o builder** (`base_service.rb`): cap de 10 linhas, suporte a seções, `description` na linha, header/footer opcional. (senão risco de erro Meta com >10.)
5. Config panel no front (espelha `SendTemplateConfig.vue`): campos body + lista de itens (título/valor/descrição) + seções + label do botão. Verbo em `ActionDescriber::VERBS`.
6. Specs (espelha os do canvas) + validação Playwright light/dark na homolog.

### F2 — Fechar o loop: esperar a escolha e ramificar (O CORAÇÃO DA FEATURE)
**Entregável:** "pessoa escolhe uma opção → ramifica → ação (enviar msg / transferir time)".
1. **Capturar o `id` da resposta:** em `incoming_message_service_helpers.rb#message_content` + `build_content_attributes`, persistir `interactive.button_reply.id`/`list_reply.id` em `content_attributes` (ex.: `content_attributes.submitted_values` ou `selected_option`). Precedente: `waha/poll_vote_service.rb`.
2. **Nó `wait_for_reply`:** suspende **sem** `wait_until` (ou com timeout opcional) — variante do `wait`. Grava `current_node_id` = sucessor.
3. **Retomada por mensagem:** hook em `AutomationRuleListener#message_created` que, se houver `FlowRun` in-flight (`waiting`) pra aquela conversa (o índice único garante ≤1), injeta a resposta em `flow_run.context` e chama `RunnerService#resume_from`. Hoje o listener **só cria run novo, nunca retoma** — é o ponto a estender.
4. **Ramificar pela resposta:** variante de `condition`/`router` que lê `flow_run.context` (a escolha) em vez de só atributos da conversa. Precedente: `ai_classify` ("classifica → alimenta um router").
5. Timeout/fallback do `wait_for_reply` (cliente não responde) → aresta de timeout.
6. Specs + Playwright end-to-end (enviar lista → simular escolha → conferir ramo + ações).

### F3 — Resto do catálogo + WhatsApp Flows nativo (OPCIONAL / DEPOIS)
- Nós dedicados: `location`, `cta_url`, `location_request`.
- Fechar o **WhatsApp Flows nativo**: implementar o caminho de envio de `interactive.type=flow` no provider (o payload já está montado em `whatsapp_flow_action.rb`, só falta o POST) e tirar da whitelist o `send_whatsapp_flow`.

---

## 4. Decisão pendente (do Walisson): qual CANAL?

O plano acima é pro **canal oficial** (`whatsapp_cloud` / 360dialog) — que foi o que você pediu ("api oficial").

**Mas ⚠️:** boa parte da frota roda em **WAHA** (não-oficial, `Channel::Api`). O WAHA faz interativo de outro jeito — **poll nativo** (`/api/sendPoll`) + `/api/sendList` — e **já captura o voto com id** (`waha/poll_vote_service.rb`). Se os clientes que você quer atender estão em WAHA, a feature precisa de um **caminho paralelo** (o nó `send_interactive` detecta o tipo de inbox e escolhe o payload).

→ **Decidir:** (a) **oficial só** (mais simples, atende quem usa Cloud API/360dialog), ou (b) **oficial + WAHA** (cobre a frota toda, +trabalho no F1/F2 pro lado WAHA).

---

## 5. Arquivos-âncora
- **Canal interativo:** `app/services/whatsapp/providers/whatsapp_cloud_service.rb`, `.../base_service.rb`, `app/models/concerns/content_attribute_validator.rb`, `app/services/whatsapp/incoming_message_service_helpers.rb`
- **Janela 24h:** `app/services/whatsapp/send_on_whatsapp_service.rb`, `app/services/conversations/message_window_service.rb`
- **Motor Flow:** `app/models/flow.rb`, `app/models/flow_run.rb`, `app/services/flows/runner_service.rb`, `.../resume_service.rb`, `.../action_service.rb`, `app/jobs/flows/{resume_job,execution_job}.rb`
- **Dispatch por evento:** `app/listeners/automation_rule_listener.rb`
- **Front canvas:** `app/javascript/dashboard/routes/dashboard/settings/automation/canvas/{nodeCatalog.js,flatToDefinition.js,FlowCanvasView.vue,config/RouterConfig.vue}`
- **WAHA (referência lado não-oficial):** `app/services/waha/{api_service.rb,outbound_special_message_service.rb,poll_vote_service.rb}`
- **WhatsApp Flows nativo (stub):** `app/services/flows/whatsapp_flow_action.rb`
