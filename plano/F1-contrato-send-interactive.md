# F1 — Contrato do nó `send_interactive` (fonte de verdade única)

> Nó novo no canvas de automação que envia **lista/botões interativos** do WhatsApp. Backend e frontend implementam contra ESTE contrato. Ambiente `.232` homologação. NÃO tocar produção. NÃO commitar (o orquestrador commita no fim). NÃO tocar o WIP do Paulo (`enterprise/.../captain/conversation_eval*`, `db/migrate/20260702180000_*`).

## Escopo F1 (MVP shippável)
Enviar uma mensagem com **corpo (body)** + **1 a 10 opções**. O canal já decide: **≤3 opções → botões**, **>3 → lista** (comportamento existente em `base_service.rb`). Descrição por opção (só aparece em lista). **Sem** seções customizadas, **sem** header/footer, **sem** botão-label custom (usa i18n atual) — isso é F1.5/F3. **F1 NÃO fecha o loop** (esperar resposta + ramificar é F2) — F1 só ENVIA.

## Formato do nó (definition)
```js
{
  id: 'n3',
  type: 'action',
  action_name: 'send_interactive',
  action_params: [
    {
      content: 'Escolha uma opção:',            // body, obrigatório, máx 1024
      items: [                                   // 1..10 opções
        { title: 'Suporte', value: 'suporte', description: 'Falar com o time de suporte' },
        { title: 'Vendas',  value: 'vendas' }    // description opcional
      ]
    }
  ]
}
```

## Limites oficiais Meta (enforce nos DOIS lados)
- **items:** 1 a **10** (senão a lista estoura na Meta).
- **title:** obrigatório. Botão: máx **20**. Linha de lista: máx **24**.
- **value:** obrigatório (vira o `id` da reply — o que a Meta devolve em `button_reply.id`/`list_reply.id`; é o que F2 vai usar pra ramificar). Máx 200. Se vazio, backend cai pra slug do title.
- **description:** opcional, só em lista (>3). Máx **72**. Ignorado em botões.
- **content (body):** máx 1024.

---

## BACKEND — arquivos e mudanças

### 1. `app/models/flow.rb` — whitelist
Somar `send_interactive` em `BASE_ACTION_NAMES` (linha ~65-73), senão o Flow nem salva (validação `definition_action_names`).

### 2. `app/services/flows/action_service.rb` — nova ação `send_interactive`
Espelhar `send_message` (linha 90-100). Pontos:
- Guard `return if conversation_a_tweet?`.
- **Compliance idêntico ao send_message:** `enforce_compliance!(category: 'utility', free_form: true)` (respeita janela 24h — fora dela dá StepSkip, não envia texto livre que a Meta rejeitaria).
- Ler `config = action_params[0].to_h.with_indifferent_access`; `content = config['content']`; `items = Array(config['items'])`.
- **Validar/sanear:** rejeitar (StepSkip triável, ex. `'interactive_no_items'`) se items vazio; **cap 10** (truncar); cada item vira `{ 'title' => t[..24], 'value' => (value.presence || slug(title)), 'description' => d && d[..72] }`.
- Criar a Message com `content_type: 'input_select'` + `content_attributes: { items: [...] }` + o anti-loop `message_content_attributes` (flow_id).

### ⚠️ GOTCHA CRÍTICO (prove com teste): `Messages::MessageBuilder` perde os `items` com Hash puro
`MessageBuilder#initialize` só faz `@items = content_attributes.dig(:items)` **quando `params.instance_of?(ActionController::Parameters)`** (linha 17: `return unless ...`). E `message_params` (linha 178) sempre injeta `items: @items` — que com Hash puro é **nil** e **sobrescreve** o `content_attributes['items']` setado na linha 177. Resultado: a mensagem salva **sem items** → o provider manda texto puro, não lista/botão.

**Escolha a correção mais limpa e PROVE:**
- (a) **Recomendado:** tornar o `MessageBuilder` robusto — popular `@items`/`@in_reply_to` a partir de `content_attributes` **também** para Hash (mover as linhas 19-20 pra fora do `return unless ActionController::Parameters`, lendo via o método `content_attributes` já existente que normaliza). É aditivo (antes era nil pra callers de Hash) e conserta o service layer inteiro. **Precisa de teste de não-regressão** (send_message/send_template continuam iguais).
- (b) OU passar `ActionController::Parameters` de dentro do `send_interactive` — MAS cuidado: o método `content_attributes` (linha 76-84) só aceita `Hash`/`String`; `ActionController::Parameters` aninhado cairia no `{}` (linha 83). Se for por aqui, garanta a conversão.

**Teste obrigatório:** criar via `Flows::ActionService#send_interactive` e **assertar** que a Message persistida tem `content_type == 'input_select'` e `content_attributes['items']` == os items saneados. Esse teste pega o gotcha.

### 3. `app/services/whatsapp/providers/base_service.rb` — endurecer o builder
- `create_rows`: incluir `'description' => item['description']` quando presente (linha da lista suporta description; botão não tem).
- `create_payload_based_on_items`: **cap defensivo de 10** rows (a validação primária é no action, mas o canal é a última linha de defesa contra erro Meta).
- NÃO quebrar 360dialog (`whatsapp_360_dialog_service.rb` usa os mesmos helpers).

### 4. `app/models/concerns/content_attribute_validator.rb`
Somar `:description` em `ALLOWED_SELECT_ITEM_KEYS` (hoje `[:title, :value]`) — senão a Message com description em input_select fica **inválida** e não salva. Additivo, seguro.

### 5. `app/services/flows/action_describer.rb`
Somar `'send_interactive' => 'Enviaria a lista de opções'` no `VERBS` (linha ~16).

### 6. TESTES (rodar em RAILS_ENV=test, NUNCA production, SEM HTTP real)
- Spec do `Flows::ActionService#send_interactive`: cria a Message certa (o teste do gotcha acima). Stub/no-op de envio real.
- Spec do `base_service`: com um Message double, `create_payload_based_on_items` gera **button** (≤3) e **list** (>3), description na row, cap 10. Sem HTTP.
- Spec de não-regressão do `MessageBuilder` se escolher a opção (a).
- Rodar `bundle exec rspec <arquivos>` e reportar VERDE.

---

## FRONTEND — arquivos e mudanças

### 1. `.../canvas/nodeCatalog.js`
Somar item (perto de `send_template`, família `msg`):
```js
{ key: 'send_interactive', type: 'action', actionName: 'send_interactive', family: 'msg',
  labelKey: 'AUTOMATION.CANVAS.NODES.SEND_INTERACTIVE', icon: 'i-lucide-list' },
```

### 2. `.../canvas/config/SendInteractiveConfig.vue` (NOVO)
- Espelhar o padrão de `MessageConfig.vue` (body) + um **editor de lista repetível** de itens (mirar `RouterConfig.vue`/`ConditionConfig.vue` p/ o padrão de array add/remove, e `ConfigField.vue` p/ os campos).
- Campos por item: **title** (obrigatório, maxlength dinâmico: 20 se ≤3 itens/botões, 24 se lista), **value** (obrigatório), **description** (opcional, maxlength 72, só faz sentido em lista).
- Body: textarea, maxlength 1024.
- Regras UI: mínimo 1, **máximo 10** itens (desabilita "adicionar" em 10); aviso sutil "≤3 vira botões, >3 vira lista".
- Two-way binding com `node.action_params[0]` **exatamente** no formato `{ content, items:[{title,value,description}] }` (ler MessageConfig/SetAttributeConfig p/ o padrão de emit/update do canvas).

### 3. `.../canvas/NodeConfigPanel.vue`
Importar + registrar no dispatcher: `send_interactive: markRaw(SendInteractiveConfig)`.

### 4. i18n (en + pt_BR, os DOIS)
- `AUTOMATION.CANVAS.NODES.SEND_INTERACTIVE` — pt: "Enviar opções (lista/botões)", en: "Send options (list/buttons)".
- Chaves do config (`AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.*`): label do body, "Opções", "Adicionar opção", title/valor/descrição, aviso do ≤3/>3, erros de validação. Achar o namespace certo lendo como `SendTemplateConfig.vue`/`MessageConfig.vue` resolvem `t(...)`.
- Conferir que NÃO vaza chave crua (padrão do projeto: validar no Playwright depois).

### 5. TESTES
- Se existir `nodeCatalog.spec.js`/specs do canvas, estender p/ cobrir o novo item (catalogEntryForNode/familyForNode/labelForNode com `send_interactive`).
- Rodar o vitest dos specs tocados e reportar VERDE. (Build/precompile e Playwright ficam com o orquestrador.)

---

## Convenções (ambos)
- Editar **direto no working tree** de `/home/chatwoot/chatwoot` (a sessão trabalha in-place). **NÃO commitar, NÃO push.**
- **NÃO tocar** arquivos do WIP do Paulo (captain conversation_eval*, migration 20260702180000).
- Nada de produção, nada de HTTP real pro WhatsApp, nada de credencial real.
- Reportar: arquivos tocados (file:line), o que os testes cobrem, saída dos testes (verde/vermelho), e qualquer desvio do contrato com justificativa.
