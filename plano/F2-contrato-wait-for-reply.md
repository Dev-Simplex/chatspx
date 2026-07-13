# F2 — Contrato do loop `wait_for_reply` (fonte de verdade única)

> Fecha o loop: `send_interactive` (F1) envia as opções → o contato escolhe → o Flow **retoma**, **ramifica pela escolha** e executa a ação (enviar msg, transferir time…). Ambiente `.232` homolog. NÃO tocar produção. NÃO commitar (orquestrador commita no fim). NÃO tocar WIP do Paulo (`captain/conversation_eval*`, migration `20260702180000`, `db/schema.rb`).

## Visão do loop (o encaixe)
```
[send_interactive]  →  [wait_for_reply]  →(branch = value da opção)→ [ação: assign_team / send_message / …]
   (F1, envia)          (F2, suspende e         →('timeout')→ [ação de timeout]
                         ramifica na resposta)   →(fallback, aresta sem rótulo)→ [ação default]
```
**Chave de tudo:** o `value` da opção do F1 é enviado como `id` do botão/linha → o WhatsApp devolve esse mesmo id em `interactive.button_reply.id`/`list_reply.id` → viramos isso no `branch` da aresta. `value` (F1) == reply id == `edge.branch` (F2). Zero duplicação: o canvas copia as opções do `send_interactive` anterior.

**Sem migration** — `FlowRun` já tem `status/current_node_id/wait_until(nullable)/context(jsonb)`. Reusa tudo.

---

## AGENTE A — Capturar o id da resposta (pipeline de entrada) — PEQUENO/ISOLADO

**Arquivo:** `app/services/whatsapp/incoming_message_service_helpers.rb` (+ onde `build_content_attributes` monta os content_attributes da mensagem inbound — provavelmente `app/services/whatsapp/incoming_message_base_service.rb`).

**Hoje** (`message_content`, linha 27-33) a resposta interativa só guarda o **título** como `content`; o **id é descartado** (tem `# TODO` na linha 28).

**Fazer:** quando a mensagem inbound for interativa (`message['interactive']` com `button_reply` ou `list_reply`), persistir em `content_attributes`:
```ruby
content_attributes['selected_option'] = {
  'id'    => reply['id'],     # button_reply.id OU list_reply.id  (== o value do F1)
  'title' => reply['title']
}
```
- É **aditivo**: `content_attributes` é JSON store; `selected_option` não precisa estar nos accessors do Message (persiste como chave livre). Não valida contra `ContentAttributeValidator` (mensagem inbound é content_type `text`).
- Mexer no ponto onde os content_attributes da mensagem já são montados (`build_content_attributes`), lendo o raw message. NÃO trocar o `content` (segue sendo o título — não-regressão).

**Teste:** spec de `IncomingMessageService` (WhatsApp Cloud) — webhook com `interactive.list_reply`/`button_reply` → mensagem inbound criada com `content_attributes['selected_option'] == {id, title}` e `content == title` (não-regressão). Rodar rspec, reportar.

---

## AGENTE B — Motor: suspender-por-resposta + retomar + ramificar + hook do listener — GRANDE/ACOPLADO

**Arquivos:** `app/models/flow.rb` (NODE_TYPES), `app/services/flows/runner_service.rb`, novo `app/services/flows/reply_resume_service.rb`, `app/listeners/automation_rule_listener.rb`. (FlowRun NÃO muda.)

### B1. `Flow::NODE_TYPES` (flow.rb:75) — somar `wait_for_reply`
```ruby
NODE_TYPES = %w[trigger action condition router wait wait_for_reply].freeze
```

### B2. `RunnerService` — suspender no 1º toque, ramificar na retomada
Regras (o runner atual: `suspend_on_wait` grava o SUCESSOR + wait_until; `next_node_id(node_id, branch)` casa `edge['branch']==branch`, com fallback pra aresta sem rótulo):

1. **Construtor:** aceitar `resume_reply: nil` → `@resume_reply`. E em `resume_from(node_id)` gravar `@resume_start_id = node_id` (o nó de reentrada).
2. **`suspend_step`/`step_node`:** para `node['type'] == 'wait_for_reply'`:
   - Se `node_id == @resume_start_id` (estamos RETOMANDO neste nó) → **NÃO suspende**; cai no `visit` pra ramificar.
   - Senão (1º toque no walk pra frente) → **suspende gravando o PRÓPRIO nó** (não o sucessor) e `wait_until` = prazo do timeout (ou **nil** se sem timeout): `flow_run.suspend!(node_id: node_id, wait_until: timeout_or_nil)`. Retorna HALT.
   - `wait` (tempo) puro segue **inalterado** (sucessor + wait_until sempre).
3. **`visit`:** somar `when 'wait_for_reply' → instrument_branch(node) { evaluate_reply_branch(node) }`.
4. **`evaluate_reply_branch(node)`:**
   - reply = `@resume_reply` (setado na retomada por mensagem) — hash `{id, title}`.
   - **com reply** → `reply['id'].to_s` (vira o branch; `next_node_id` casa `edge.branch == value`, senão a aresta sem rótulo = fallback).
   - **sem reply** (retomada por TEMPO = timeout via ResumeJob) → `'timeout'`.
5. **Timeout config do nó:** `node['timeout'] = { enabled:, value:, unit: minutes|hours|days }`. Se `enabled` → `wait_until` = `value.unit.from_now` (reusar `wait_until_for`/`normalized_wait`); senão `nil` (espera indefinida pela resposta).

⚠️ **Não quebrar:** `SimulationWalk` (dry-run) deve ATRAVESSAR `wait_for_reply` sem suspender (igual faz com `wait`) — checar `Flows::SimulationWalk`/`simulate_visit` e tratar o novo type.

### B3. `Flows::ReplyResumeService` (NOVO) — retomada por MENSAGEM (não por tempo)
Espelha `Flows::ResumeService`, mas dispara pela resposta e injeta o reply:
```ruby
class Flows::ReplyResumeService
  def initialize(conversation:, reply:)  # reply = { id:, title: }
  def perform
    run = FlowRun.waiting.where(conversation: @conversation).order(updated_at: :desc)
              .detect { |r| wait_for_reply_node?(r) }   # current_node_id aponta um wait_for_reply
    return false unless run
    run.with_lock do
      next false unless run.waiting?
      Flows::RunnerService.new(
        flow: run.flow, conversation: run.conversation,
        trigger_payload: run.context, flow_run: run, resume_reply: @reply
      ).resume_from(run.current_node_id)
      true
    end
  end
end
```
- Best-effort (rescue → log + `run.fail!`), como o ResumeService.
- `wait_for_reply_node?`: acha o nó `current_node_id` na definition e confere `type == 'wait_for_reply'`.

### B4. `AutomationRuleListener` — hook no `message_created`
Em `run_flows` (listener), para `event_name == 'message_created'` com mensagem **incoming de contato**: ANTES do disparo por-evento/keyword, tentar retomar um wait_for_reply pendente. Se retomou, **RETURN** (a resposta pertence ao flow ativo — não dispara flow novo com a mesma mensagem; espelha o early-return do opt-out na linha 92):
```ruby
if event_name == 'message_created' && resume_pending_reply(conversation, payload)
  return
end
```
- `resume_pending_reply`: monta `reply = { id: msg.content_attributes['selected_option']&.dig('id') || msg.content, title: msg.content_attributes['selected_option']&.dig('title') || msg.content }` e chama `Flows::ReplyResumeService.new(conversation:, reply:).perform`. Só pra `msg.incoming? && !msg.private?`. (Anti-loop `flow_id` já filtrou msgs do motor em `ignore_message_created_event?`.)
- Assim funciona tanto pra **toque em botão/lista** (selected_option.id do Agente A) quanto pra **resposta digitada** (content).

### B5. Testes (rspec, RAILS_ENV=test, SEM HTTP real)
Spec de integração do loop: flow `send_interactive → wait_for_reply(2 opções + timeout) → [branch A: assign_team] / [branch B: send_message] / [timeout: add_label]`. Cobrir:
- 1º disparo suspende em `waiting`, `current_node_id` = o wait_for_reply, `wait_until` nil (sem timeout).
- `ReplyResumeService` com reply id = value A → retoma, segue aresta branch A, executa assign_team, run `completed`.
- reply id sem aresta → aresta fallback (sem rótulo).
- timeout: com `timeout.enabled`, `wait_until` setado; `ResumeService` (tempo) → branch 'timeout'.
- listener: incoming reply retoma o run e dá `return` (não dispara flow novo).
- não-regressão: `wait` (tempo) puro inalterado; dry-run atravessa wait_for_reply.
Rodar `bundle exec rspec <arquivos>`, reportar VERDE real.

---

## AGENTE C — Frontend: nó `wait_for_reply` + ramificação por porta — MÉDIO

**Dir base:** `app/javascript/dashboard/routes/dashboard/settings/automation/canvas/`

### C1. `nodeCatalog.js` — novo item (família `logic`, perto de `wait`/`router`)
```js
{ key:'wait_for_reply', type:'wait_for_reply', family:'logic',
  labelKey:'AUTOMATION.CANVAS.NODES.WAIT_FOR_REPLY', icon:'i-lucide-messages-square' },
```

### C2. `FlowCanvasView.vue#addNode` — nascer com portas + **copiar opções do bloco anterior**
Ao adicionar `wait_for_reply`:
- `node.replies = []`; se o `prev` (auto-conectado) for `send_interactive`, **pré-preencher**: `node.replies = prev.action_params[0].items.map(i => ({ key: i.value, label: i.title }))`.
- `node.timeout = { enabled: false, value: 1, unit: 'hours' }`.
- `node.fallback_key = 'fallback'`.
- As **portas de saída** = uma por `reply.key` + `'timeout'` (se enabled) + `'fallback'` (igual o `router` expõe portas por `routes[].key` + fallback). Ver como o router monta ports/handles (RouterConfig + FlowNode) e espelhar.

### C3. `config/WaitForReplyConfig.vue` (NOVO) + registrar em `NodeConfigPanel.vue`
- Lista editável de respostas esperadas (`key` = value da opção, `label`), add/remove — pré-preenchida do bloco anterior (C2) mas editável.
- Toggle **timeout** { enabled, value, unit } (reusar o padrão do `WaitConfig.vue`).
- Escreve em `node.replies` / `node.timeout` / `node.fallback_key`. Two-way binding no padrão dos outros configs.
- Aviso: "cada opção vira uma saída; conecte cada uma à ação desejada. 'Sem correspondência' e 'Tempo esgotado' têm saídas próprias."

### C4. Portas no `FlowNode.vue`
`wait_for_reply` expõe uma porta de saída por `reply.key` + timeout + fallback (mesmo mecanismo do `router`). Conferir no Playwright que as portas aparecem rotuladas.

### C5. i18n en+pt (`AUTOMATION.CANVAS.NODES.WAIT_FOR_REPLY` + `CONFIG.WAIT_FOR_REPLY.*`)
pt: "Aguardar resposta"; en: "Wait for reply". + labels do config (respostas, timeout, avisos, portas timeout/fallback).

### C6. Specs
Estender `specs/nodeCatalog.spec.js` pro novo item; se houver spec de addNode/canvas, cobrir o pré-preenchimento das replies a partir do send_interactive anterior. Rodar vitest, reportar.

---

## Contrato de acoplamento (os 3 têm que casar)
- **selected_option** (A→B): `content_attributes['selected_option'] = { 'id', 'title' }` na msg inbound interativa.
- **branch** (B↔C): `edge.branch` = `reply.key` (= value da opção = reply id) | `'timeout'` | ausente (fallback). `evaluate_reply_branch` devolve o reply id (com reply) ou `'timeout'` (sem).
- **node wait_for_reply** (C→B): `{ type:'wait_for_reply', replies:[{key,label}], timeout:{enabled,value,unit}, fallback_key:'fallback' }`.
- **suspensão**: `current_node_id` = o PRÓPRIO nó wait_for_reply; `wait_until` = prazo timeout ou **nil**.

## Convenções (todos)
- Editar in-place; NÃO commitar/push. NÃO tocar WIP do Paulo. Nada de produção/HTTP real/credencial.
- Reportar: arquivos+file:line, o que os testes cobrem, saída REAL dos testes, desvios justificados.
