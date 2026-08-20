# Onda 3 · Trilha `o3-flows-captura` — relatório de execução

Worktree: `/home/chatwoot/chatwoot-o3-flows-captura` · Branch: `o3-flows-captura`
Base: `redesenho-integra` @ `4954ed5837`.

> ## ⚠️ LEIA ISTO PRIMEIRO — a folga de bytes do `sdk.js` é ~metade do que foi passado
>
> Você passou "**11.710 B** gzip contra teto de **15.360**, sobram **3.650**".
> **Medi antes de gastar**, no worktree já mergeado, com o comando que o próprio gate
> declara para o SDK (`scripts/widget-size.mjs`: `gzip -c public/packs/js/sdk.js | wc -c`),
> depois de `pnpm build:sdk`:
>
> | | raw | gzip |
> |---|---:|---:|
> | **antes** (HEAD pós-merge, sem código meu) | 39.099 | **13.755** |
> | **depois** (5.07 + 5.08) | 40.470 | **14.332** |
> | **meu delta** | +1.371 | **+577** |
>
> **O teto do gate é `sdkGzip: 15_000`** (decimal, não 15.360 — `scripts/widget-size.mjs`).
> Portanto a folga **antes de mim já era 1.245 B, não 3.650**; depois de mim sobram **668 B**.
> Se a trilha do teaser (4.06) estiver dimensionando com 3.650 na cabeça, ela estoura o teto
> sozinha. **Não afrouxei nada** — o número está cru aqui e a decisão é sua.
>
> Meu primeiro corte dava **+728 B**; mover o `attach` para o lado sob demanda recuperou
> 151 B. O que sobrou eager é só capturar e buscar, e não vejo mais gordura sem trocar
> legibilidade por golfe.

> **RECADO AO COORDENADOR — o relay estava sem coordenador conectado quando terminei, então o
> `worker_done` não chegou por mensagem. Está aqui, que é onde você lê.**
>
> **Os quatro blocos estão entregues e commitados localmente.** Três coisas pedem a sua atenção,
> e nenhuma delas eu resolvi por conta própria além do que era meu:
>
> 1. **A conferência do contrato com a `o2-config-prechat` achou um buraco que não era de nenhum
>    dos dois lados.** Os contratos casam (o schema dela recusa `flow_id`, exatamente como o meu
>    publicava) — mas **nada gateava a entrega do fluxo pelo MODO da inbox**. Sem isso, uma inbox
>    no modo *Simples* rodaria o formulário clássico **e** o fluxo de captura: dois pré-chats para
>    o mesmo visitante. Fechei **no meu lado**, sem tocar arquivo dela, espelhando a tela do 3.14.
>    Detalhe em §4.02 — a guarda de modo. Se você preferir outro desenho, é uma linha.
> 2. **O aceite de 375 px reprovou na branch integrada, e a investigação achou DOIS defeitos meus —
>    nenhum no produto.** O `beforeAll` estourava os 120 s porque eu aquecia o grafo inteiro
>    (3.863 módulos, 235 s) — e a causa não era nem o `createViteServer` (7,9 s, medido) nem o
>    `App.vue` (removi: zero diferença): eram as **arestas de dependência do Tailwind**, que levam
>    ao dashboard inteiro. Aquecimento dirigido derrubou para **22,4 s**. E o terceiro teste **não
>    pegava o defeito que eu disse que pegava**: afiei o medidor duas vezes antes de descobrir que
>    a premissa é que estava errada (o texto cabia). Seção própria abaixo, com todos os números.
> 3. **A paridade 0.6 já não reprova mais**: no último merge a trilha do widget fechou a chave
>    `tokens`, e as **três** paridades passam aqui (11 exemplos, 0 falhas). Auditei os
>    meus cinco commits arquivo por arquivo **antes** de rodar: nenhum toca os dois montadores de
>    config. E encontrei uma armadilha de ambiente que vale para todas as trilhas — a falha do
>    `dyte_controller_spec` **não é defeito de código, é locale**: o fork nasce pt-BR e o spec do
>    upstream espera inglês; com `DEFAULT_LOCALE=en` ela passa. Detalhe em §Vermelho herdado.
>
> Sobre o `0 examples, 0 failures`: essa armadilha apareceu aqui **na primeira execução** e foi
> lida como o que é. Toda execução citada neste relatório tem **N > 0** conferido contra o esperado.

| Bloco | Situação | Commit |
|---|---|---|
| **4.01** | ✅ entregue | `5d52910d27` |
| **4.02** (BK-21/22/23) | ✅ entregue | `8a5a2f9f32` + `3c50b63758` |
| **4.03** | ✅ entregue | `ebf9b18768` + `1785d1dd6a` |
| **4.18** (BE-5) | ✅ entregue | `f9f46a2735` |
| **5.07** (T-C2.0) | ✅ entregue | `6e0011ea42` |
| **5.08** (T-C2.1–2.6, 2.8) | ✅ entregue | `6e0011ea42` |

**Os quatro blocos da trilha estão entregues.** O bloqueio de 4.03/4.18 era de **base**, não de
trabalho: 1.10, 3.13 e 3.14 já estavam na `redesenho-integra` e não na minha base. O coordenador
autorizou o merge; ele entrou limpo na primeira vez e com **um conflito** (aditivo, resolvido por
união) na segunda — as duas i18n do widget, onde o outro lado acrescentou chaves de A11Y e eu
acrescentei o bloco `CAPTURE`.

## Números

| Suíte | Resultado |
|---|---|
| Backend desta trilha + regressão do motor Flow + widget | **474 exemplos, 3 falhas — todas HERDADAS** (§Vermelho herdado) |
| Vitest do widget (captura, message-types, pré-chat, guarda do Tailwind) | **73 exemplos, 0 falhas** |
| Vitest do **SDK** (inclui os 39 do coletor de origem) | **122 exemplos, 0 falhas** |
| Middleware de cache do SDK (5.07) | **10 exemplos, 0 falhas** |
| Playwright — aceite dos 375 px, config próprio | **3 exemplos, 0 falhas** (43,8 s) |
| Playwright — aceite dos 375 px, **`--project=widget`** (o comando do coordenador) | **3 exemplos, 0 falhas** (4,1 min) |
| As três paridades de config do widget | **11 exemplos, 0 falhas** — a chave `tokens` foi fechada no último merge (§Paridade) |

Banco de teste dedicado: `chatwoot_test_o3flows`. Nunca dev, nunca homologação.

---

# 4.01 — A ponte que faltava: resposta a `input_select`/`form` vira mensagem `incoming`

## O diagnóstico, arquivo por arquivo

1. `Flows::InteractiveAction#send_interactive` (`app/services/flows/interactive_action.rb`) já criava
   uma mensagem **outgoing** `content_type: 'input_select'` com `content_attributes.items` — e o
   widget **já a renderizava** (`AgentMessageBubble.vue:53` → `ChatOptions.vue`).
2. O visitante clicava → `AgentMessageBubble#onOptionSelect` → `message/update` →
   `PATCH /api/v1/widget/messages/:id` com `message[submitted_values]`.
3. `Api::V1::Widget::MessagesController#update` **só gravava `submitted_values` na própria mensagem
   outgoing**. Nenhuma mensagem `incoming` nascia.
4. `AutomationRuleListener#message_created` → `run_flows` → `incoming_message_consumed?` →
   `resume_pending_reply` exige `message&.incoming?`.

Conclusão: **o evento nunca acontecia**, e o `FlowRun` ficava `waiting` **para sempre** no canal web.
`wait_for_reply` funcionava no WhatsApp (onde `Whatsapp::IncomingMessageBaseService` cria a incoming
com `content_attributes.selected_option`, `:187`) e **não** funcionava no widget.

## O que foi feito

`Api::V1::Widget::MessagesController#update` passa a **materializar a resposta do visitante como
mensagem `incoming` de verdade**, no MESMO formato do WhatsApp. A leitura no listener **não precisou
mudar** — `reply_from_message` (`automation_rule_listener.rb:299-312`) já lê `selected_option` e já
cai no `content` quando não há opção. **O defeito era a ausência da mensagem, não o leitor dela.**

### Contrato desta ponta (nome da chave, tipo, default, ausência)

**Mensagem criada** (só quando o motor está ativo — ver guardas):

| Chave | Tipo | Valor | Na ausência |
|---|---|---|---|
| `message_type` | enum | `incoming` | — |
| `sender` | Contact | o visitante (`@contact`) | — |
| `content` | string | `input_select`: o **título** da opção (ou o `value`, se sem título). `form`: os pares `campo: valor`, **uma linha cada**, na ordem preenchida | conteúdo vazio ⇒ **nenhuma** mensagem é criada |
| `content_attributes.selected_option` | `{id, title}` | `id` = `value` da opção (o **branch** do `wait_for_reply`), `title` = rótulo | **só existe em `input_select`**. Em `form` é ausente, e o `wait_for_reply` casa pelo `content` (fallback que já existia) |
| `content_attributes.in_reply_to` | integer | id da mensagem estruturada | — |
| `content_attributes.flow_id` | — | **NUNCA presente** | se estivesse, o próprio listener a ignoraria como "gerada pela automação" (`automation_generated_message?`) — e o `wait_for_reply` nunca retomaria |

**Marca na mensagem estruturada** (a outgoing original):

| Chave | Tipo | Significado | Na ausência |
|---|---|---|---|
| `content_attributes.reply_message_id` | integer | id da `incoming` materializada | **ausente = comportamento de hoje**: o widget desenha o balão local. É exatamente o que acontece com o motor desligado |

### As duas guardas, que são as duas metades do aceite

- **Motor desligado ⇒ nada muda.** A guarda é `account.flows_engine_enabled? && account.flows.active.exists?`
  — o **mesmo** gate do `AutomationRuleListener#flows_engine_active?`. Usar só a flag seria pior do
  que não ter guarda: com a flag ligada **antes do backfill**, o listener cai no motor ANTIGO
  (`run_rules`), e a mensagem nova passaria a disparar `AutomationRule` que hoje não dispara.
- **2 cliques = 1 mensagem e 1 retomada.** Lido **antes** do `update!`: se `submitted_values` já
  existia, esta requisição não é a primeira resposta e não ecoa. Cobre double-click, retry de rede e
  aba duplicada — sem depender do `uiFlags.isUpdating` do front.

### A ponta do widget (o defeito de junção que eu teria criado)

`AgentMessage.vue` desenha um balão LOCAL a partir de `submitted_values` (`hasRecordedResponse` →
`<UserMessage>`; e `isASubmittedForm` → um `<UserMessage>` por campo). Com a mensagem real chegando
pela lista, a tela mostraria **a mesma resposta duas vezes**. Os dois computados passam a devolver
`false` quando `reply_message_id` está presente. Sem o motor a chave não existe, e a tela é
**pixel-idêntica** à de hoje.

`isASubmittedFormMessage` (em `app/javascript/shared/`) **não foi tocado** — a decisão ficou no
componente do widget, para não arrastar o dashboard (regra R21).

## Mecanismos

| Arquivo | Exemplos | Mede |
|---|---|---|
| `spec/controllers/api/v1/widget/messages_flow_reply_spec.rb` | 9 | 1 mensagem por clique; formato idêntico ao WhatsApp; retomada no branch certo; 2 cliques = 1 mensagem e 1 retomada; motor desligado não cria nada; `input_email` não ecoa; `submitted_values` continua gravado |
| `app/javascript/widget/components/specs/agentMessageVisitorReply.spec.js` | 4 | o balão local some com `reply_message_id` e permanece sem ele (opção e formulário) |

**Vermelho medido restaurando o código antigo no lugar** (não imaginado): **3 de 9** e **2 de 4**
falhavam. Os demais são as não-regressões, e passavam antes e depois.

Detalhe que o vermelho revelou e vale registrar: o `AutomationRuleListener` mora no
**AsyncDispatcher** (`EventDispatcherJob`). A retomada **não** acontece dentro da requisição do
visitante — acontece no worker. O spec performa o job explicitamente; em produção é o Sidekiq.

---

# 4.02 — `widget_prechat`, resolução no servidor, adaptador por canal, teto de 8

## ⇢ CONTRATO DE RESOLUÇÃO (é isto que a trilha `o2-config-prechat` está esperando)

> **Confirmo o desenho que o coordenador arbitrou: o alvo mora no `trigger_config` do FLUXO.**
> Nada de `flow_id` dentro de `pre_chat_form_options`. Um `flow_id` fixo por inbox responde
> "qual fluxo" com **um** fluxo — e o aceite deste bloco é **dois** fluxos ativos entregando coisas
> diferentes conforme a URL. Seriam duas fontes de verdade para a mesma pergunta, com uma delas
> destinada a morrer levando junto uma chave já gravada no banco de clientes.
>
> A consulta é exatamente a forma do índice existente
> `index_flows_on_account_id_and_trigger_type_and_active`: `account.flows.active.widget_prechat`.

### 1. O valor do enum

```ruby
enum trigger_type: { manual: 0, conversation_event: 1, schedule: 2,
                     keyword: 3, external_webhook: 4, widget_prechat: 5 }
```

**`widget_prechat` ocupa o inteiro 5** (`app/models/flow.rb:46`). A coluna já é `integer`: **não há
migration**. O valor está fixado por spec (`spec/models/flow_spec.rb` e `flow_widget_prechat_spec.rb`)
— quem inserir um valor no meio quebra a suíte, nomeando o problema.

### 2. O formato do `trigger_config` — chave a chave, tipo, default, ausência

Fonte da verdade em código: `app/models/flow/widget_prechat_schema.rb` (validado por **json_schemer**,
não Zod — §10.2 N3). `Flow::WidgetPrechatSchema::DEFAULTS` é o mesmo hash publicado abaixo.

| Chave | Tipo | Default | O que acontece **na ausência** |
|---|---|---|---|
| `inbox_ids` | `integer[]` | `[]` | vale para **qualquer** inbox Website da conta |
| `url_conditions` | `array` de `{operator, value}` | `[]` | **catch-all**: casa qualquer URL, **inclusive conversa sem `referer`** |
| `match` | `"all"` \| `"any"` | `"all"` | todas as condições de URL precisam casar |
| `utm` | `object` `{chave: valor}` | `{}` | não filtra por UTM |
| `devices` | `string[]` de `desktop`\|`mobile`\|`tablet` | `[]` | qualquer dispositivo |
| `business_hours_only` | `boolean` | `false` | não filtra por expediente |
| `priority` | `integer` (−1000..1000) | `0` | entra no desempate com 0 |

**Operadores de URL** (`url_conditions[].operator`): `contains`, `not_contains`, `equals`,
`starts_with`, `ends_with`. **Não há regex**, de propósito: `trigger_config` é escrito pelo admin e
avaliado a cada conversa nova — uma expressão patológica viraria ReDoS no caminho quente.

**Como a URL é comparada:** a URL **inteira, com querystring**, `downcase` dos dois lados.
A URL é o `conversation.additional_attributes['referer']` **já saneado pelo bloco 1.20**.

**URL ausente** (visitante sem `referer` registrado): só casa `not_contains` — não há texto onde
procurar, então "não contém" é verdade e o resto é falso. Um fluxo **sem** `url_conditions` continua
casando (é catch-all).

**UTM:** **todas** as chaves declaradas precisam bater (E), por igualdade case-insensitive, contra os
parâmetros da querystring. URL que nem o saneamento do 1.20 recuperou ⇒ sem UTM legível ⇒ o filtro
não casa (nunca levanta).

**Dispositivo:** classificado a partir do que o widget **já grava** em
`additional_attributes['browser']` (`device_name` + `platform_name`). `tablet` é testado **antes** de
`mobile` (um iPad casa os dois; a categoria mais específica vence). **Browser não gravado ⇒ nunca
casa um filtro de dispositivo declarado** — preferimos não entregar um fluxo segmentado a entregar o
errado.

**Expediente:** `business_hours_only: true` usa o **mesmo** expediente do resto do produto
(`Inbox#working_now?`, concern `OutOfOffisable`). Inbox sem expediente configurado responde `true`.

**Chaves de outros gatilhos que sobram no objeto** (`keywords`, `webhook_token`, `conditions`, …):
**aceitas e ignoradas**. `additionalProperties` fica **aberto no topo** de propósito — `trigger_config`
é a mesma coluna dos cinco gatilhos, e um fluxo que MUDA de `keyword` para `widget_prechat` chega
carregando as chaves antigas. Fechar o topo transformaria a troca de gatilho num 422 sobre dado que
o próprio produto gravou. **Dentro de `url_conditions` a forma é fechada** (`additionalProperties:
false`), porque a estrutura nasce neste bloco e não há legado a proteger — `{operator, value, flags}`
é 422 com o endereço do erro (`url_conditions/0`).

### 3. A regra de desempate — quando dois fluxos ativos casam a mesma requisição

Aplicada em ordem; o **primeiro critério que separa** decide (`Flows::WidgetPrechatResolver#rank`):

1. **`priority` DESC.** É a única alavanca explícita do admin, e por isso vem primeiro: se ele
   declarou, ele mandou.
2. **Especificidade DESC** = **nº de critérios declarados que casaram**
   (`url_conditions.size + utm.size + (devices? 1 : 0) + (business_hours_only? 1 : 0)`).
   Um catch-all (0) **sempre** perde para um fluxo que fala daquela URL.
3. **`id` ASC — o MAIS ANTIGO vence.** Empate total não muda de fluxo quando alguém cria um novo:
   um fluxo recém-criado **não rouba, em silêncio, o tráfego** de um que já estava no ar.

Sem nenhum fluxo casando: **nenhum fluxo é entregue** e o widget se comporta como hoje.

Os três degraus têm spec própria em `spec/services/flows/widget_prechat_resolver_spec.rb`.

### 4. O que o widget recebe — e o que ele NUNCA recebe

**Recebe:** apenas as **MENSAGENS da conversa**, um passo por vez, nos `content_type` que ele já
renderiza (`text`, `input_select`, `form`, `input_email`, `cards`) com os `content_attributes` de
desenho (`items`, `submitted_values`, `reply_message_id`, `in_reply_to`, `selected_option`).

**Nunca recebe:**

- `flows.definition` — nem `nodes`, nem `edges`, nem `action_name`;
- `trigger_config` — nem `url_conditions`, nem `utm`, nem `priority`: **os critérios de segmentação
  do cliente não vão para o navegador**;
- a **lista** de fluxos, nem o **nome** dos fluxos que não foram escolhidos.

Isso é medido lendo o **corpo inteiro** de `GET /api/v1/widget/messages` e procurando cada um desses
termos (`prechat_flow_delivery_spec.rb`, exemplo "never ships the flow definition…").

**Exposição conhecida e declarada:** `content_attributes.flow_id` (um inteiro) **continua** indo ao
widget nas mensagens que o motor envia — é o anti-loop que já existia (`json.content_attributes
message.content_attributes`, `index.json.jbuilder`). Não é a definição nem critério: revela apenas
que existe um fluxo com aquele id. **Não filtrei de propósito** — filtrar campo na leitura é
exatamente a forma do pior defeito desta execução, e aqui não há ganho que pague o risco. Fica
registrado como candidato a endurecimento, não como pendência silenciosa.

### 5. Onde a resolução acontece (para a tela saber o que prometer ao admin)

`AutomationRuleListener#run_widget_prechat_flow`, no evento **`conversation_created`** de inbox
**Website**, com o motor Flow ativo. Fica **fora** do laço por-evento porque `widget_prechat` não casa
por `event_name` — quem escolhe é o servidor.

**O que a tela 3.14 pode dizer ao admin, sem mentir:**

- o modo **Fluxo** não tem (e não deve ter) um seletor "qual fluxo": **o motor resolve pelo gatilho**;
- quem decide é o `trigger_config` do fluxo, editado na tela de **Automações**;
- a inbox pode ser restringida pelo lado do fluxo (`inbox_ids`), não pelo lado da inbox;
- se **nenhum** fluxo `widget_prechat` ativo casar, **nada** é entregue — vale desenhar o estado
  "nenhum fluxo atende este site ainda".

## BK-22 — o adaptador de mensagem estruturada por canal

**O defeito real que isso corrige:** `Flows::InteractiveAction` truncava **todo** título em 24
caracteres — o limite da **Meta** — inclusive no chat de site, onde nenhuma regra da Meta vale.
"Falar com o time financeiro sobre a fatura" chegava ao visitante como "Falar com o time financ".

`Flows::StructuredMessageLimits.for(conversation)`:

| Limite | WhatsApp (`META`) | Chat de site (`WEB`) | Procedência do número do lado web |
|---|---|---|---|
| `items` | 10 | 20 | **não** é limite do canal (o widget desenha um `<ul>`): é guarda contra lista patológica, com folga de 2× sobre a Meta |
| `title` | 24 | 160 | o mesmo teto de rótulo curto que o pré-chat já usa (`PreChatFormSchema::MAX_TEXT_LENGTH`) |
| `description` | 72 | 160 | idem |
| `body` | 1024 | 10 000 | o limite que o **próprio produto** declara para canal genérico (`MESSAGE_MAX_LENGTH.GENERAL`) |
| `value` | 200 | **200** | **IGUAL de propósito** — ver abaixo |

**`value` não diverge entre canais, e isso é a parte importante.** Ele é o id da resposta e o
`edge.branch` que o `wait_for_reply` casa. Se o corte divergisse por canal, o **mesmo** fluxo
ramificaria diferente no WhatsApp e no site — o pior tipo de defeito, porque só aparece num dos dois.

**Nó novo `send_form`** (`app/services/flows/form_action.rb`): emite `content_type: 'form'` no canal
web. Fecha o par que o 4.01 deixou aberto — o motor já sabia **ler** a submissão de um formulário que
**nenhum nó sabia pedir**. Campos saneados para as chaves que `ContentAttributeValidator::ALLOWED_FORM_ITEM_KEYS`
aceita (qualquer chave fora invalida a Message inteira); tipo desconhecido vira `text` (um campo que
aparece como texto é recuperável; um que não renderiza trava o visitante); teto de **8** campos, o
mesmo do BK-23. **Fora do canal web levanta um `Flows::StepSkip` triável** (`form_unsupported_channel`)
— o passo aparece no `FlowStepLog` com o motivo, em vez de mandar um texto improvisado. No WhatsApp
quem faz esse papel é o `send_whatsapp_flow`, que já existe.

**Escopo do BK-22 declarado e NÃO entregue, com o motivo:** `cards` no canal web. O `content_type`
existe e o widget o renderiza, mas **nenhum consumidor desta onda pede** — adicionar um `send_cards`
ao whitelist do motor sem consumidor é código morto num arquivo que a frota inteira carrega. Se o
coordenador quiser, é um arquivo novo de ~60 linhas no mesmo formato do `send_form`.

## BK-23 — teto de 8 campos

`Flow#collected_fields_count` = **nº de nós `wait_for_reply`** + **soma dos `items` dos nós
`send_form`**. Um `wait_for_reply` é exatamente uma pergunta respondida pelo visitante (o
`send_message`/`send_interactive` que o precede apenas **desenha** a pergunta); um `send_form` de 12
campos coleta 12 — sem essa segunda metade, um fluxo com um único nó de formulário passaria pelo teto
contando **zero**.

Fluxo `widget_prechat` com **9 campos não salva**, e o erro diz o número encontrado e o teto:
`"fluxo de captura coleta 9 campos; o teto e 8"`. **Recusa em vez de truncar**: truncar apagaria
etapa que o admin desenhou, e ele só descobriria pelo lead que não chega. O teto **não** se aplica
aos outros gatilhos — é regra do fluxo de captura, não do motor.

## Mecanismos do 4.02

| Arquivo | Exemplos | Mede |
|---|---|---|
| `spec/controllers/api/v1/widget/prechat_flow_delivery_spec.rb` | 7 | **o aceite**: dois fluxos ativos, duas URLs, dois fluxos entregues; catch-all vs específico; motor desligado; e o corpo inteiro da resposta sem definição/critério/lista |
| `spec/services/flows/widget_prechat_resolver_spec.rb` | 14 | o contrato chave a chave (operadores, `match`, UTM, dispositivo, `inbox_ids`, ausência) e os **três degraus** do desempate |
| `spec/models/flow_widget_prechat_spec.rb` | 11 | enum = 5; schema aceita/recusa com endereço do erro; troca de gatilho não vira 422; teto de 8 e a mensagem exata |
| `spec/services/flows/action_service_web_structured_spec.rb` | 9 | título inteiro no site vs cortado em 24 no WhatsApp; `value` idêntico nos dois; 20 vs 10 opções; `send_form` (saneamento, teto, skip fora do canal) |

**Vermelho medido restaurando o código antigo no lugar:** 7/7, 9/11 e 7/9 falhavam, e o
`widget_prechat_resolver_spec` nem carregava (`Flows::WidgetPrechatResolver` não existia).

---

# 4.02 — a guarda de modo, descoberta ao conferir o contrato com a outra ponta

O coordenador pediu: *"confira o contrato dela contra o seu depois do merge, chave por chave"*.
Conferido. **Os dois casam** — o `pre_chat_form_schema.rb` da `o2-config-prechat` traz
`'flow_id' => false`, que **recusa a chave sempre que ela aparecer**, com comentário explicando que
o alvo mora no `trigger_config` do fluxo. É exatamente o contrato que publiquei, escrito do outro
lado sem nos falarmos.

**Mas a conferência achou um buraco que não era de nenhum dos dois lados:** nada gateava a entrega
do fluxo pelo **modo** da inbox. Uma inbox no modo **Simples** rodaria o formulário clássico **e** o
fluxo de captura — dois pré-chats para o mesmo visitante, que é captura em duplicidade, não
redundância inofensiva.

Fechei no meu lado (`3c50b63758`), sem tocar arquivo da outra trilha. A guarda espelha a tela dela:
em `PreChatPage.vue` o seletor de modos só aparece **dentro** do interruptor mestre do pré-chat,
então a condição é `pre_chat_form_enabled?` **E** `pre_chat_form_options['mode'] == 'flow'`.
`mode` ausente é o estado de **toda a frota hoje** ⇒ nada muda. Três exemplos novos, vermelhos sem
a linha da guarda (medido removendo-a).

> **Adendo ao contrato publicado acima**, para quem for escrever a tela: um fluxo `widget_prechat`
> ativo e casando a URL **só é entregue** se a inbox estiver com o pré-chat **ligado** e no modo
> **Fluxo**. É mais uma coisa verdadeira que a tela pode dizer ao admin.

---

# 4.03 — Fluxo de captura conversacional

## O que foi feito

`app/javascript/widget/capture/` — dois componentes **do widget**, não de `shared/`:

- **`CaptureField.vue`** — um campo: rótulo, entrada, **máscara no blur**, validação, mensagem e
  a11y (`aria-invalid`, `aria-describedby`, `role="alert"`).
- **`CaptureForm.vue`** — n campos com teto de 8, a regra "e-mail **ou** WhatsApp" e o botão.

`message-types/FormContent.vue` (o registry do 1.10) escolhe entre os dois formulários **pelo
conteúdo do passo**: declarou `mask`, `validator` ou um campo `phone` → `CaptureForm`; qualquer
outro → o `ChatForm` de sempre. **Zero regressão**: um `form` gravado antes deste bloco não tem
nenhuma dessas chaves.

**`ChatForm` não foi ensinado a falar brasileiro de propósito.** Ele mora em `shared/` e o dashboard
também o renderiza — mexer nele arrastaria a outra superfície junto (regra R21).

### Três decisões, com a razão escrita

1. **Máscara no blur, não a cada tecla.** Numa caixa de 375 px, mascarar enquanto se digita empurra
   o cursor a cada separador inserido: a pessoa digita 11 dígitos e vê o cursor pular três vezes.
   No blur o valor é normalizado uma vez, quando ela já terminou. É o que o aceite pede.
2. **"E-mail OU WhatsApp"** — campos de contato (`email`/`phone`) formam **um grupo**: se algum é
   obrigatório, basta **um** preenchido **e válido** para satisfazer o grupo. Pedir os dois e
   aceitar qualquer um. Sem isso, um passo que pede ambos obriga a dar ambos — que é exatamente o
   atrito que o fluxo de captura existe para remover.
3. **Nenhuma classe de estilo nos campos.** `woot.scss` já estiliza `input:not(.reset-base)`,
   `textarea` e `select` com o visual do widget. Competir com ele por utilitária **perde na
   especificidade** (0,1,1 contra 0,1,0) e ainda criaria um segundo visual de campo dentro do mesmo
   widget. Só o estado de erro é acrescentado, por um seletor mais específico que o global.

### Backend do 4.03

`send_form` passa a preservar `mask` e `validator` — **descartando nome fora do vocabulário** de
`Channel::WebWidget::PreChatFormSchema` (mandar `mask: "banana"` ao widget não mascara nada e ainda
arrisca invalidar a Message) — e o tipo `phone`. `ContentAttributeValidator::ALLOWED_FORM_ITEM_KEYS`
ganhou as duas chaves: **sem elas a Message inteira era invalidada na persistência** e o passo
simplesmente não chegava ao visitante.

## O aceite de 375 px — e o teste que a sabotagem exigiu

Medido em **navegador real** (`spec/e2e/widget/capture/`): Vue real, `woot.scss` real, Tailwind
gerado pelo config do widget. Nenhum CSS de teste.

**Não encosta no harness de porta fixa** (3038/3999/8899, que o coordenador trancou): sobe o Vite em
`middlewareMode` numa **porta efêmera** (porta 0) dentro do próprio teste, com config Playwright
própria que **não herda** a raiz — herdar subiria os três servidores travados só para medir largura.

Três momentos medidos: recém-desenhado, com a mensagem de erro mais longa visível, e preenchido.
Mais a **conclusão**: os quatro valores chegam ao `submit`.

> **O terceiro teste do arquivo nasceu de uma sabotagem que NÃO falhou.** A primeira versão media só
> `scrollWidth` do documento e a caixa de cada campo. Devolvi o `whitespace-nowrap` que o `.button`
> do widget traz — um defeito real, que eu tinha desfeito de propósito — e **o aceite passou mesmo
> assim**: o botão é `block`, então a CAIXA continua com 100% da largura; quem estoura é o **texto**
> dentro dela, e nem `scrollWidth` do documento nem `getBoundingClientRect` enxergam isso.
>
> A medição certa é por elemento: `scrollWidth > clientWidth`. **Aceite que não falha quando o
> defeito está presente não é aceite, é decoração.**

Dois achados medidos, que valem registro:

- a máscara `phone` do 3.13 devolve o valor **intacto** quando começa com `+` (quem digita DDI está
  dando um número internacional, e reformatá-lo quebraria quem cola do exterior). Como o validador
  `phone` **exige** o DDI, o par `mask: phone` + `validator: phone` **nunca reformata**. Não é
  defeito — é uma combinação que a tela de configuração pode querer explicar ao admin.
- o `TEST=true` é obrigatório antes de o `vite.config.ts` ser lido: sem ele o RubyPlugin reescreve o
  `root` para `app/javascript` e todo caminho de `spec/` devolve 404.

---

# 4.18 — Lead incompleto (BE-5)

## O desenho, e o que ele muda

O aceite fala do **momento em que a conversa nasce**. Hoje, quem preenche nome e e-mail e fecha a
aba no terceiro campo **some sem deixar rastro**: a conversa só nasce no envio do pré-chat, e sem
conversa não existe lugar onde o lead possa estar.

Tabela nova **`widget_partial_leads`** — e não jsonb num contato — porque o registro parcial é de
quem **não** concluiu, tem retenção própria (LGPD) e precisa ser **contado por etapa**. Cardinalidade
alta, expurgo por data e agregação por coluna são exatamente o que jsonb não faz bem.

### O ciclo

| Momento | O que acontece |
|---|---|
| cada campo respondido | o rascunho vai ao servidor (debounce de 1,2 s; **a sessão vem do TOKEN**, nunca do corpo) |
| conclui o pré-chat | `completed_at` — e **a linha fica**: o relatório precisa do denominador |
| some | o varredor confirma o abandono e **materializa o CONTATO** marcado como incompleto, com a etapa em que parou e a etiqueta configurável |
| a retenção vence | o registro parcial é **apagado** |

### O contrato de configuração (`account.internal_attributes`)

| Chave | Tipo | Default | Na ausência |
|---|---|---|---|
| `partial_lead_capture_enabled` | boolean | **`false`** | **nada é gravado — o comportamento de hoje** |
| `partial_lead_abandon_after_minutes` | integer (1..1440) | **5** | 5 (o default do mockup 22 §3) |
| `partial_lead_retention_days` | integer (1..365) | **30** | 30 |
| `partial_lead_label` | string | **`lead-incompleto`** | a etiqueta é aplicada; `""` desliga a etiqueta sem desligar a captura |

**Valor torto** (String, negativo, absurdo) **cai no default declarado** — nunca em retenção
infinita nem em varredura por segundo.

**O default de `enabled` é `false`, e isso é leitura de LGPD, não timidez:** o registro parcial é
dado pessoal de quem **não concluiu nada** e, portanto, **não consentiu com nada**. Guardar por
padrão seria decidir pelo cliente uma coisa que é dele decidir. A tela por inbox do mockup 22 §3 é
do bloco de configuração — ela **consome** estes nomes, não os redefine.

### As garantias, e como cada uma é provada

| Aceite | Como é garantido | Onde se mede |
|---|---|---|
| o lead existe no painel **marcado como incompleto, com a etapa** | `Contact` com `custom_attributes['widget_lead_incomplete']`, `widget_lead_step`, `widget_lead_step_name` + etiqueta | `partial_leads_spec.rb`, `lifecycle_spec.rb` |
| **retomar na mesma sessão não duplica** | **índice ÚNICO** em `(inbox_id, session_id)` — garantia do banco, não do serviço | `widget_partial_lead_spec.rb` |
| **não dispara automação, campanha nem webhook de conversa** | **não cria conversa** — não é regra escrita, é consequência. O spec monta uma `AutomationRule` ativa em `conversation_created` e um webhook inscrito, e prova que nada rodou | `partial_leads_spec.rb` |
| o relatório responde **"quantos e onde"** | contagem por etapa agregada **no banco**; o endpoint devolve **só contagens** | `lifecycle_spec.rb`, `partial_lead_reports_controller_spec.rb` |
| retenção configurável com padrão declarado | tabela acima + varredor que expurga **mesmo com a captura desligada** | `lifecycle_spec.rb` |

O endpoint do relatório **nunca devolve as respostas do visitante** — um spec procura o e-mail no
corpo da resposta para provar. O dado pessoal de quem não concluiu não precisa sair da base para o
relatório existir.

### A cicatriz da FK, tratada de frente

`widget_partial_leads` tem FK para `accounts`, `inboxes` e `contacts`. **As três em `on_delete:
cascade`**, e o spec **apaga de verdade pelas três pontas**.

Não é zelo abstrato: uma FK sem cascade já travou `conversation.destroy!` com `InvalidForeignKey`
nesta base, e o agente descobria pelo 500 na tela. E cascade por **múltiplos caminhos até a mesma
linha filha** é justamente o caso em que a suíte fica verde por `schema.rb` e a frota quebra por
migration — por isso o teste exclui de verdade, em vez de conferir o schema.

No contato, `cascade` (e não `nullify`) também é a leitura de LGPD certa: apagar a pessoa apaga as
respostas que ela deu pela metade. Órfão anônimo seria pior.

**Migration:** `20260818150000`. `ls db/migrate | cut -d_ -f1 | sort | uniq -d` sai **vazio** (R5).

## O que NÃO foi entregue no 4.18, e por quê

A refatoração de **`PreChat/Form.vue` para "só delegação"** aos componentes de captura do 4.03.
O aceite do bloco não a exige (ele fala de painel, não-duplicação, não-disparo, relatório e
retenção); o arquivo é 🔴 de risco de merge; e o que fiz nele é **aditivo** — um `watch` e três
métodos. Os componentes do 4.03 já existem para quem for fazer. **Fica declarado, não escondido.**

---

# 5.07 — Propagação do SDK (T-C2.0)

## O defeito, e por que ele é grande

`config/environments/production.rb:24-26` manda `Cache-Control: public, max-age=31556952` —
**um ano** — para tudo que sai de `public/`. O `sdk.js` mora num caminho **fixo**
(`/packs/js/sdk.js`, ver o snippet em `Channel::WebWidget`), **sem fingerprint** e **sem
cache-buster no snippet**.

A combinação é a pior possível: um navegador que baixou o `sdk.js` **não volta a pedir por um
ano**. Nove blocos desta onda mexem no SDK. Um visitante recorrente pode ficar até 12 meses
sem receber o teaser, o coletor de origem, ou uma correção de segurança.

## O conserto

`SdkCachePolicy` (Rack, `lib/middleware/`): troca o ano por `public, max-age=300,
must-revalidate` **apenas** nos caminhos do SDK (`/packs/js/sdk.js` e, pelo mesmo motivo,
`/packs/js/tracking.js` do bloco 5.08). Preserva o validador — a revalidação vira **304 sem
corpo**, não os 39 kB.

Três decisões, com a razão:

- **Middleware, não config.** `public_file_server.headers` é um hash **único** para todos os
  arquivos: ele não sabe distinguir caminho. E, nesta frota, o header sai do **Rails** e não do
  nginx (medição do plano §A.4.1) — então a correção chega a todas as VMs pelo deploy, sem
  mexer em nginx máquina a máquina.
- **Lista de caminhos exatos, não prefixo `/packs/js/`.** Prefixo tiraria do cache longo
  qualquer arquivo futuro que alguém coloque ali, sem ninguém ter decidido isso.
- **O resto de `public/` fica com o ano**, que está certo para caminho com fingerprint. Mexer
  nisso seria trocar um defeito por uma conta de banda.

## O mecanismo, e a metade dele que quase ficou de fora

`spec/lib/middleware/sdk_cache_policy_spec.rb` (10 exemplos) mede a reescrita, a preservação do
validador, o HEAD, e a **não**-reescrita de asset com hash, de outro arquivo em `/packs/js/` e
de método que não seja de leitura.

E mede a **instalação na pilha** — que é a metade que quase escapou: um middleware correto
**fora** da pilha não muda nada e ficaria **verde** no spec de unidade. Dois exemplos conferem
que ele está lá e que **embrulha o `ActionDispatch::Static`** (a pilha executa de fora para
dentro; quem está antes vê a resposta pronta na volta). **Vermelho medido** comentando o
`insert_before`: exatamente esses dois reprovam.

---

# 5.08 — Coletor de origem no SDK (T-C2.1 a T-C2.6, T-C2.8)

## A divisão eager × sob demanda é de CUSTO, e é o coração do bloco

| | onde roda | por quê |
|---|---|---|
| **captura** | eager, em toda página | o aceite é "chega por anúncio, **navega 5 páginas** e só então abre o chat". Quando o chat abre, o `gclid` já saiu da URL há cinco páginas e o referrer já é interno. Se a captura esperasse a abertura, **a origem já estaria perdida** — não há como recuperá-la depois |
| **enriquecimento** | sob demanda, ao abrir o chat | ler cookies, derivar `_fbc`/`_gcl_aw` e perguntar `client_id` ao gtag só é útil no momento em que a conversa vai nascer — e só quando a inbox tem tracking configurado (T-C2.8) |

### O achado que mudou o desenho do "sob demanda"

`vite.lib.config.ts` constrói o SDK como IIFE único com **`inlineDynamicImports: true`**. Sob
essa regra, um `import()` que o Rollup **consiga resolver em build é INLINADO** dentro do
`sdk.js`. Ou seja: "carregar sob demanda" com import comum entregaria **zero economia**, e cada
byte do coletor cairia sobre o orçamento do arquivo que 100% dos visitantes de todos os sites
baixam — que é justamente o orçamento que estava quase esgotado.

O que funciona é a **opção (c) do próprio T-C2.0**: import com **URL de runtime** (o Rollup não
a resolve, então a deixa passar), com o coletor como artefato próprio —
`vite.tracking.config.ts` → `public/packs/js/tracking.js`, **4.037 B raw / 1,64 kB gzip, fora do
`sdk.js`**. Por isso 5.07 e 5.08 são o mesmo mecanismo, e não dois.

O build entrou em `lib/tasks/build.rake`: sem ele o artefato não existe em produção e o
`import()` cai no `catch` — falha silenciosa, do tipo que aparece como "a atribuição parou de
funcionar" semanas depois.

## As regras, uma a uma

| Regra | O que fizemos |
|---|---|
| `first_*` **write-once** | a primeira origem da pessoa nunca é reescrita, nem por campanha nova |
| `last_*` sem zerar por navegação interna | só é sobrescrito quando a página traz parâmetro de campanha **ou** referrer externo. É o erro clássico de mercado: cada página nova grava "referrer = o próprio site" e a campanha some na segunda |
| `_fbc` / `_gcl_aw` no formato oficial | `fb.{subdomainIndex}.{timestamp}.{fbclid}` e `GCL.{unix}.{gclid}`, TTL 90 dias |
| **nunca fabricar sem clique real** | sem `fbclid`, não há `_fbc`. E o **cookie real tem precedência** sobre a derivação: quem escreveu conhece o domínio |
| allowlist de cookies | só `_fbp`, `_fbc`, `_ga`, `_gcl_aw` e `_ga_<ID>` ancorado. Varrer `document.cookie` seria exfiltrar sessão e carrinho do site do cliente |
| `client_id`/`session_id` com **1 s** | `gtag('get', …)` responde por callback e **pode nunca chamar** (gtag ainda carregando, id errado, bloqueador). Sem prazo, a promessa fica pendente para sempre e leva junto a abertura da conversa |

**Limitação declarada, e ela é minha:** o `subdomainIndex` é contado por rótulos do host, o que
**erra em ccSLD** (`loja.com.br` dá 2, o correto seria 1). Acertar exigiria a Public Suffix List
— ~40 kB, que não cabem no SDK. É por isso que o cookie real tem precedência: quando o Pixel
existe, esse cálculo nem é usado. Off-by-one conhecido, não silencioso.

## Não reintroduzi a mentira que a Onda 1 tirou

A trilha de origem mediu que o SDK manda `document.location.href`, **não** `document.referrer`, e
renomeou `referrer_host` → `page_host` porque *"batizar de origem um dado que é destino seria a
mentira que a onda proíbe"*.

Este bloco **traz o dado que faltava, com nome próprio**: `entry_referrer` é o `document.referrer`
de verdade, lido **na landing page**, que é o único lugar onde ele existe; `landing_page` é essa
primeira página. `page_host`/`page_path` continuam sendo o destino, e nada aqui os renomeia.

## O transporte não inventou contrato nenhum

Os dois eventos já existem no bridge do widget, e o que está do outro lado deles também:

- `set-custom-attributes` → `contacts/setCustomAttributes` → **`first_*`**, no contato;
- `set-conversation-custom-attributes` → `conversation/setCustomAttributes` → o resto. E quando
  **ainda não há conversa**, essa action já guarda como `pendingCustomAttributes` e envia junto
  com a primeira mensagem — que é literalmente *"a conversa **nasce** com o `first_utm_source` e o
  `gclid` certos"*.

A divisão de escopo espelha o backend: `Tracking::OriginRecorder` grava `first_*` no contato
(write-once) e `last_*` na conversa. Mandar tudo para os dois lados duplicaria dado no painel.

**Nada dispara para serviço externo.** O coletor só **lê** cookies e **pergunta** ao `gtag` da
própria página. Zero requisição a Meta, Google ou GlitchTip — não há dublê a declarar porque não
há chamada a dublar.

## O aceite do Safari, e o que ele realmente prova

O ITP do Safari **limita a 7 dias** a validade de cookie escrito por JavaScript. Um coletor que
guarde a origem em cookie perde a campanha de quem volta na segunda semana — e é assim que boa
parte do mercado guarda.

**A origem aqui não depende de cookie nenhum**: mora em `localStorage`, e cookie só serve para
enriquecer. O spec modela o ITP do jeito que ele se manifesta — **os cookies somem** — e cobra
que, oito dias depois e sem cookie algum, a conversa ainda nasça com `first_utm_source`,
`first_gclid` e `first_landing_page` certos, e que o `_gcl_aw` ainda derive (a janela do Google é
de 90 dias, não 7).

**Limitação declarada:** o ITP também pode apagar `localStorage` após 7 dias sem interação quando
classifica o site como rastreador. Isso é avaliado sobre o site **do cliente** e não está sob
nosso controle; quando acontecer, a origem se perde. A única defesa real seria persistir no
servidor antes de a conversa existir — que é o mecanismo do bloco 4.18, e fica registrado como
caminho, não entregue aqui.

## Mecanismos

| Arquivo | Exemplos | Mede |
|---|---|---|
| `sdk/tracking/specs/capture.spec.js` | 10 | a jornada do aceite (anúncio → 5 páginas), write-once, navegação interna que não zera, truncagem, storage bloqueado/corrompido, parâmetro fora do vocabulário |
| `sdk/tracking/specs/payload.spec.js` | 17 | formato oficial de `_fbc`/`_gcl_aw`, proibição de fabricar, TTL de 90 dias, precedência do cookie, allowlist, timeout de 1 s e fallback por cookie |
| `sdk/tracking/specs/safariSurvival.spec.js` | 4 | 8 dias sem cookie nenhum |
| `sdk/tracking/specs/loader.spec.js` | 8 | sob demanda de verdade (sem config, nem requisição), e a entrega pelos dois eventos existentes |

**Vermelho por sabotagem dirigida:** tirar o write-once reprova 2; tirar a guarda de navegação
interna reprova 3 — entre elas **a do aceite das cinco páginas**.

Suíte do SDK inteira depois das mudanças: **122 exemplos, 0 falhas**.

---

# O aceite de 375 px reprovou na branch integrada — a investigação inteira

O coordenador rodou `--project=widget` na branch integrada: **29 passaram, 1 falhou, 2 não
rodaram**, e o vermelho era meu — `"beforeAll" hook timeout of 120000ms exceeded`, derrubando os
**três** testes do arquivo. Na branch integrada, o aceite do 4.03 **não estava sendo verificado por
nenhum deles**. Reproduzido aqui depois de mergear a `redesenho-integra`.

## O que era, medido — e o que NÃO era

Três hipóteses caíram, e vale registrar as três porque cada uma custaria trabalho a quem a
perseguisse:

| Hipótese | Veredito | Como se mediu |
|---|---|---|
| contenção de porta / carga (duas trilhas ao mesmo tempo) | **refutada** (pelo coordenador) | falha igual rodando o arquivo sozinho |
| `iniciar()` trava / erro engolido | **refutada** | retorna; o coordenador cronometrou **192,4 s** |
| custo do `createViteServer` com a `vite.config.ts` da raiz | **refutada aqui** | instrumentei passo a passo: **7,9 s** dos 235 |
| import de `App.vue` arrastando o app inteiro | **refutada aqui** | removi o import: **3.863 → 3.863 módulos**. Zero diferença |

**A causa real era o meu aquecimento recursivo.** Andar por `importedModules` a partir do módulo de
CSS não percorre imports de JS: percorre as **arestas de dependência do Tailwind** — o Vite registra
como dependência do módulo de estilo todo arquivo que o `content` varre. A quebra por diretório:

```
[ '/app/javascript/dashboard', 2621 ]   ← o dashboard inteiro
[ '/@fs//home',                 430 ]
[ '/app/javascript/widget',     267 ]
[ '/app/javascript/shared',     125 ]
[ '/app/views/public',           60 ]   ← .erb
[ '/app/views/reports',          29 ]   … e mais dez diretórios de views
                          total: 3.863 módulos, 235 s
```

Eu percorria o projeto inteiro para medir a largura de um formulário.

## O conserto, e os números

**Aquecimento dirigido**: só o módulo de entrada e o CSS; o resto o Vite transforma sob demanda,
que é barato porque o grafo JS desta página tem dezenas de módulos, não milhares.

| | antes | depois |
|---|---:|---:|
| `iniciar()` | 192–235 s | **22,4 s** |
| fluxo inteiro (subir + `goto` + âncora) | — | **33,2 s** |
| teto do meu config | 600 s | **120 s**, o mesmo do projeto `widget` |

O teto **baixou** de propósito: um config próprio mais generoso que o da corrida integrada é
exatamente o que deixa um arquivo passar no meu e falhar no dele. A folga é de ~3,5× sobre o medido,
e o número, a data e a máquina estão escritos ao lado da constante — teto sem procedência vira
número mágico que ninguém ousa mexer.

O CSS deixou de entrar por `App.vue` e passa por um shim (`widget/wootStyles.harness.scss`), que
existe por um motivo estrito: o `@config` do `woot.scss` é resolvido **relativo ao arquivo que o
PostCSS recebe**, então só um arquivo em `app/javascript/widget/` reproduz a base de produção.

**A decisão da porta efêmera ficou como estava** — este teste continua sem disputar 3038/3999/8899
com ninguém.

## O segundo defeito: o teste não pegava o que eu disse que ele pegava

Ao revalidar, sabotei a proteção de quebra de linha do botão. **O teste passou.** Afiei o medidor
(`scrollWidth` por elemento) — passou. Afiei de novo (`Range` sobre o texto) — **passou pela
terceira vez**.

Só então fui medir a **premissa**, em vez do medidor:

```
rotulo: "Quero falar com um especialista agora"
caixa: 343 px   texto: 272 px   whiteSpace: "nowrap"
```

**O texto cabia.** Não havia defeito algum a detectar — o teste estava certo e eu errado, e a minha
afirmação anterior (*"o teste que a sabotagem exigiu"*) estava sem lastro.

A correção foi no **cenário**, não no medidor: o rótulo virou um CTA longo de administrador (452 px
na mesma caixa de 343 px), que é o pior caso realista. Agora, **tirar a proteção reprova dois dos
três testes; com ela, os três passam** — verificado nos dois sentidos.

Fica também um cego útil, medido: **num elemento com `overflow: visible` — que é o caso de todo
botão — `scrollWidth` devolve a largura da CAIXA, nunca a do conteúdo que transborda.** Quem for
medir transbordo de texto em outro bloco não deve usá-lo.

> **A lição, que vale além deste arquivo:** quando um mecanismo não pega o defeito, a suspeita
> seguinte não é *"meço com mais precisão"* — é **"o defeito existe mesmo?"**. Eu afiei o medidor
> duas vezes antes de conferir a premissa, e era a premissa que estava errada.

---

# Paridade 0.6 — o resultado cru, e ele MUDOU

**Primeira medição** (merge de `5184a6f209`, 18/08): reprovava, com a divergência que o coordenador
já tinha nomeado — e **só** ela:

```
Missing from app/views/api/v1/widget/configs/create.json.jbuilder: ["tokens"]
Missing from app/views/widgets/show.html.erb: []
1 example, 1 failure
```

**Medição atual**, depois do último merge da `redesenho-integra`: **a chave `tokens` foi fechada
pela trilha do widget e as três paridades passam.**

```
spec/requests/widget_configuration_builder_parity_spec.rb
spec/requests/widget_tokens_builder_parity_spec.rb
spec/requests/widget_pre_chat_payload_parity_spec.rb
  11 examples, 0 failures
```

**Auditoria da minha parte, feita com os olhos antes de rodar:** listei os arquivos dos meus
commits e **nenhum** toca `show.html.erb`, `create.json.jbuilder`, `Channel::WebWidget::EDITABLE_ATTRS`
ou o controller de config do widget. As chaves que criei são de outra natureza:
`content_attributes` de mensagem (`selected_option`, `reply_message_id`, `in_reply_to`),
`trigger_config` de fluxo e `internal_attributes` de conta — nenhuma delas atravessa os dois
montadores de config do widget.

---

# Vermelho herdado — e uma armadilha de ambiente que vale para todas as trilhas

`spec/controllers/api/v1/widget` tem **3 falhas herdadas** — duas provadas revertendo os meus
arquivos para `4954ed5837` e vendo-as continuarem falhando, e uma terceira que **entrou com o
último merge** da `redesenho-integra`.

**Uma delas não é defeito de código, é de AMBIENTE — e isso vale para todo mundo:**

| Spec | Diagnóstico |
|---|---|
| `integrations/dyte_controller_spec.rb:37` | **artefato de locale.** O spec (upstream) espera `"Invalid message type. Action not permitted"` e recebe `"Tipo de mensagem inválido. Ação não permitida"`. O fork nasce **pt-BR** (`config/application.rb:48`: `ENV.fetch('DEFAULT_LOCALE', 'pt_BR')`) e **nenhum worktree tem `.env`**. Com `DEFAULT_LOCALE=en` ela **passa**. Ou seja: essa suíte só fica verde em quem tem a variável no ambiente — e ninguém tem, nos worktrees |
| `conversations_controller_spec.rb:272` | **falha real e independente de locale**: espera `Conversations::ActivityMessageJob` enfileirado com a activity de resolução e **enfileira 0**. Falha também com `DEFAULT_LOCALE=en`. Não toquei esse caminho; registro para não ser creditada a esta trilha nem descoberta no merge |
| `telemetry_controller_spec.rb:102` (**nova, veio no merge**) | do commit `a7badd02d5` (bloco **2.13**, outra trilha). "deixa passar as 20 primeiras e bloqueia a 21ª do mesmo IP": a 21ª devolve **204**, não 429. Falha **isolada** (8 exemplos, 1 falha), então não é ordenação. O exemplo IRMÃO, que faz 21 requisições e espera 429, **passa** — o que aponta para a contagem/janela do primeiro exemplo, não para o throttle estar ausente. Pista para quem for consertar, de uma cicatriz nossa: `rack_attack.rb:49` tem `safelist('trusted IPs')`, e **request spec roda como 127.0.0.1** — já houve aqui um defeito que dava 500 em todo cliente real e passou por 4.619 testes verdes exatamente por isso. Vale conferir se o IP simulado do spec escapa da safelist |

Sobre o aviso do coordenador: a armadilha do `0 examples, 0 failures` **apareceu aqui na primeira
execução** (sem credencial de banco) e foi lida como o que é — erro, não sucesso. Todas as
execuções desta trilha citam **N > 0** e o N conferido contra o esperado. O runner exporta
`POSTGRES_*` explicitamente e fixa `POSTGRES_DATABASE=chatwoot_test_o3flows`; **`.env` nunca foi
carregado por `source`** (a linha 70 do arquivo quebraria o `bash`).

---

# Arquivos desta trilha

**4.01** (`5d52910d27`) — `messages_controller.rb`, `AgentMessage.vue` + 2 specs.

**4.02** (`8a5a2f9f32`, `3c50b63758`) — `flow.rb`, `flow/widget_prechat_schema.rb`,
`automation_rule_listener.rb`, `flows/widget_prechat_resolver.rb`,
`flows/structured_message_limits.rb`, `flows/form_action.rb`, `flows/interactive_action.rb`,
`flows/action_service.rb` + 4 specs (`flow_spec.rb` teve o matcher do enum atualizado).

**4.03** (`ebf9b18768`) — `widget/capture/{CaptureField,CaptureForm}.vue`,
`message-types/FormContent.vue`, `widget/i18n/locale/{pt_BR,en}.json`,
`content_attribute_validator.rb`, `flows/form_action.rb` + 3 specs Vitest e o harness
`spec/e2e/widget/capture/`.

**4.18** (`f9f46a2735`) — migration `20260818150000`, `widget_partial_lead.rb`,
`services/widget/partial_leads/{settings,record_service,materialize_service,report}.rb`,
`jobs/widget/partial_leads/sweep_job.rb`, `api/v1/widget/partial_leads_controller.rb`,
`api/v2/accounts/partial_lead_reports_controller.rb`, `base_controller.rb` (+6 linhas),
`routes.rb`, `widget/api/partialLead.js`, `PreChat/Form.vue` + 5 specs.

**5.07 + 5.08** (`6e0011ea42`) — `lib/middleware/sdk_cache_policy.rb`,
`config/initializers/sdk_cache_policy.rb`, `app/javascript/sdk/tracking/` (keys, capture,
clickIds, cookies, googleIds, loader, attach, index), `vite.tracking.config.ts`,
`lib/tasks/build.rake`, `package.json` (script `build:tracking`),
`app/javascript/entrypoints/sdk.js` (+1 import, +1 chamada),
`app/javascript/sdk/IFrameHelper.js` (+1 import, o bloco de uma chamada)
+ `spec/lib/middleware/sdk_cache_policy_spec.rb` e 4 specs em `sdk/tracking/specs/`.

Nenhum `git push`, PR, deploy, restart, migration em banco de desenvolvimento/produção,
`--no-verify` ou aceite afrouxado. **Nenhuma chamada a serviço externo real** em nenhum
bloco — o coletor não faz requisição a Meta nem a Google; ele lê cookie e pergunta ao `gtag`
da própria página.
