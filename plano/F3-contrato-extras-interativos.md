# F3 — Contrato dos extras interativos (fonte de verdade única)

> Completa o catálogo da API oficial no canvas: **botão de link (cta_url)**, **pedir localização (location_request)** e **formulário nativo (WhatsApp Flows)** — finalizando o stub já documentado. Ambiente `.232` homolog. NÃO tocar produção sem restart controlado. NÃO commitar (orquestrador). NÃO tocar WIP do Paulo (`captain/conversation_eval*`, migration `20260702180000`, `db/schema.rb`). Construir SOBRE F1+F2 (já no working tree).

## A sacada: passthrough genérico de interativo (1 método no provider serve todos)
Hoje o provider tem caminhos hardcoded (text/attachment/input_select). Em vez de um caminho por tipo novo, adicionamos **UM**: se a mensagem carrega `content_attributes['interactive_payload']` (um objeto `interactive` já montado), o provider faz o POST cru. Cada AÇÃO do Flow monta seu payload específico. Zero acoplamento entre os tipos.

Os 3 extras são todos `type: 'interactive'` na Meta:
- **cta_url:** `interactive: { type:'cta_url', body:{text}, action:{ name:'cta_url', parameters:{ display_text, url } } }` (+ header/footer opcionais)
- **location_request:** `interactive: { type:'location_request_message', body:{text}, action:{ name:'send_location' } }`
- **flow (nativo):** já montado por `Flows::WhatsappFlowAction#build_whatsapp_flow_payload` (type:'flow', action.parameters com flow_id/flow_token/flow_cta…)

**Sem migration.** Guarda de janela 24h (mensagens de sessão) via `enforce_compliance!(free_form: true)`, como o F1.

---

## AGENTE D — Backend (provider + 3 ações + whitelist)

### D1. `app/services/whatsapp/providers/whatsapp_cloud_service.rb` — passthrough
No TOPO de `send_message` (antes de attachment/input_select/text):
```ruby
def send_message(phone_number, message)
  @message = message
  return send_raw_interactive(phone_number, message) if message.content_attributes&.dig('interactive_payload').present?
  # ...resto inalterado...
end

def send_raw_interactive(phone_number, message)
  response = HTTParty.post("#{phone_id_path}/messages", headers: api_headers, body: {
    messaging_product: 'whatsapp', to: phone_number,
    interactive: message.content_attributes['interactive_payload'], type: 'interactive'
  }.to_json)
  process_response(response, message)
end
```
NÃO quebrar os caminhos existentes (F1 input_select, text, attachment). (360dialog fica fora do F3 — as ações guardam `whatsapp_cloud_inbox?`.)

### D2. `app/services/flows/rich_interactive_action.rb` (NOVO mixin, incluído no ActionService) — 2 ações novas
Espelham `send_interactive` (guard tweet, `whatsapp_cloud_inbox?` senão StepSkip `inbox_not_whatsapp`, `enforce_compliance!(category:'utility', free_form:true)`, textos via `render_liquid`, cria Message com `content: body` + `content_attributes: message_content_attributes.merge('interactive_payload' => payload)`).
- `send_cta_url(action_params)`: config `{ body, button_text, url, header?, footer? }` → payload cta_url. Guard: body+button_text+url presentes (senão StepSkip `cta_url_incomplete`). Validar url http(s).
- `send_location_request(action_params)`: config `{ body }` → payload location_request_message. Guard: body presente.

⚠️ `interactive_payload` é chave livre em content_attributes (persiste no JSON store; NÃO é o `items`, então não sofre o gotcha do F1). content_type fica `text` (default) — o provider roteia pelo `interactive_payload`, não pelo content_type.

### D3. `app/services/flows/whatsapp_flow_action.rb` — FINALIZAR o stub
Trocar o `raise Flows::StepSkip.new('whatsapp_flow_provider_missing', ...)` (linha 68-69) por: criar a Message com `content: config[:body]` + `content_attributes: message_content_attributes.merge('interactive_payload' => payload)` (mesmo wrapper das ações D2). O `build_whatsapp_flow_payload` já existe — só reusar. Manter as guardas (whatsapp_cloud_inbox?, whatsapp_flow_config_valid?, compliance).

### D4. `app/models/flow.rb` — whitelist
`BASE_ACTION_NAMES` += `send_cta_url send_location_request send_whatsapp_flow`.

### D5. `app/services/flows/action_describer.rb` — verbos
`'send_cta_url' => 'Enviaria o botão de link'`, `'send_location_request' => 'Pediria a localização'`, `'send_whatsapp_flow' => 'Enviaria o formulário (Flow)'`.

### D6. Testes (rspec, RAILS_ENV=test, SEM HTTP real)
- Ação `send_cta_url`/`send_location_request`: cria Message com `content_attributes['interactive_payload']` no formato Meta certo (type cta_url / location_request_message); StepSkip nos guards (config incompleta, inbox não-cloud).
- `send_whatsapp_flow`: NÃO levanta mais `whatsapp_flow_provider_missing`; cria Message com interactive_payload type flow.
- Provider `send_raw_interactive`: com um Message double carregando `interactive_payload`, monta o POST `{type:'interactive', interactive: <payload>}` (stub HTTParty, sem rede). E `send_message` roteia pro raw quando há interactive_payload (não quebra input_select/text).
- Rodar `bundle exec rspec <arquivos>`, reportar VERDE real.

---

## AGENTE E — Frontend (3 nós + configs)

Dir base `app/javascript/dashboard/routes/dashboard/settings/automation/canvas/`.

### E1. `nodeCatalog.js` — 3 itens (family `msg`, perto de send_interactive)
```js
{ key:'send_cta_url', type:'action', actionName:'send_cta_url', family:'msg', labelKey:'AUTOMATION.CANVAS.NODES.SEND_CTA_URL', icon:'i-lucide-external-link' },
{ key:'send_location_request', type:'action', actionName:'send_location_request', family:'msg', labelKey:'AUTOMATION.CANVAS.NODES.SEND_LOCATION_REQUEST', icon:'i-lucide-map-pin' },
{ key:'send_whatsapp_flow', type:'action', actionName:'send_whatsapp_flow', family:'msg', labelKey:'AUTOMATION.CANVAS.NODES.SEND_WHATSAPP_FLOW', icon:'i-lucide-clipboard-list' },
```

### E2. Configs (NOVOS) + registrar no `NodeConfigPanel.vue`
Espelhar `SendInteractiveConfig.vue`/`MessageConfig.vue` (padrão controlado, two-way em `node.action_params[0]`):
- `config/CtaUrlConfig.vue`: body (textarea), button_text, url (+ header/footer opcionais). Escreve `{ body, button_text, url, header, footer }`.
- `config/LocationRequestConfig.vue`: body. Escreve `{ body }`.
- `config/WhatsappFlowConfig.vue`: flow_id, cta, body (+ header, footer, screen opcionais, flow_action select navigate/data_exchange). Escreve `{ flow_id, cta, body, header, footer, screen, flow_action }`.

### E3. i18n en+pt (os DOIS)
`AUTOMATION.CANVAS.NODES.{SEND_CTA_URL,SEND_LOCATION_REQUEST,SEND_WHATSAPP_FLOW}` + `CONFIG.{CTA_URL,LOCATION_REQUEST,WHATSAPP_FLOW}.*`. pt: "Enviar botão de link" / "Pedir localização" / "Enviar formulário (Flow)". Sem vazar chave crua.

### E4. Testes
Estender `specs/nodeCatalog.spec.js` pros 3 itens (catalogEntryForNode/familyForNode/labelForNode). Rodar `npx vitest run <arquivos>`, reportar. (Build/Playwright = orquestrador.)

---

## Contrato de acoplamento
- **interactive_payload** (D↔provider): `content_attributes['interactive_payload']` = objeto `interactive` Meta pronto; o provider faz POST `{type:'interactive', interactive: payload}`.
- **action_params** (E→D): cta_url `[{body,button_text,url,header?,footer?}]`; location_request `[{body}]`; whatsapp_flow `[{flow_id,cta,body,header?,footer?,screen?,flow_action?}]`.

## Convenções (todos)
Editar in-place; NÃO commitar/push; NÃO tocar WIP do Paulo; nada de produção/HTTP real/credencial. Reportar arquivos+file:line, cobertura dos testes, saída REAL, desvios.
