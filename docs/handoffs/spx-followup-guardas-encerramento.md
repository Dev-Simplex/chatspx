# As duas guardas da fila de encerramento — frente `spx/followup`

> **Tarefa C.** Data: **11/08/2026** · Base medida: **`788ece5d89`** (= `origin/spx/followup`) ·
> CI: **`.232`**, worktree `/tmp/ci-followup-c`, banco `chatwoot_ci_fup_c`.
>
> Duas guardas: **(A)** quem espera humano não entra na varredura de encerramento;
> **(B)** quem volta a falar sai da fila.

---

## 0. Enquadramento — estado REAL da produção, conferido hoje

Levantamento **read-only** na conta 6 (`rails runner` via `scripts/ops/tozi-prod.sh`). Nada foi
ligado, nenhuma migration rodou, nenhum deploy foi feito.

| Gate | Valor em 11/08 | Handoff de 31/07 dizia |
|---|---|---|
| `captain_auto_resolve_mode` | `"disabled"` | igual |
| `feature_enabled?('captain_tasks')` | `true` | igual |
| `settings['auto_closure']` | `{"enabled" => false, "max_dias" => 0}` | `nil` — **mudou** |

A política segue **desligada** (o `disabled` barra na primeira linha do `#perform`), então nada
está sangrando agora. Mas o `auto_closure` deixou de ser `nil`: alguém escreveu a chave com
`enabled: false` e **`max_dias: 0`**. Isso importa para a guarda A, porque `max_dias = 0` é
exatamente o ramo em que o `scannable` filtra — e é o ramo que a produção usaria ao religar.

### Marcadores hoje (conta 6)

```
aguardando_encerramento_desde ... 355   (todas open)
encerramento_avisado_em ..........   0
aguardando_humano_desde ..........   8   (5 open + 2 snoozed, +1 criada durante a medição)
com os DOIS marcadores ...........   0
```

Da varredura de elegíveis da inbox 91 (`open` + espelho captain, paradas > 1h): **434**, das
quais **354 já carregam o marcador de encerramento** e **4 carregam o de humano**.

### ⚠️ Correção à premissa da tarefa: as 327 não estão presas *por causa da guarda B*

A spec parte de que a exigência de transição em `awaiting_closure_customer_returned?` "prende as
327". Medido, o quadro é outro — e vale registrar porque muda o que a entrega resolve:

| Recorte | Conversas |
|---|---:|
| Com marcador **e** `waiting_since` já preenchido (imunes ao clear atual) | **253** de 355 |
| Dessas, com **incoming novo depois** do marcador (presas de fato, hoje) | **1** (display 953) |

Ou seja: **71% da fila está armada para nunca ser solta quando o cliente voltar**, mas só uma
conversa já exerceu isso. As outras 354 continuam marcadas por um motivo mais simples — **não
acontece nada com elas**: ninguém assume, ninguém resolve, ninguém volta a falar. Marcador não
tem prazo de validade.

Consequência prática, e é o ponto que decide o próximo passo: **a correção conserta o fluxo, não
drena o passivo.** Sem mensagem nova não existe evento que dispare limpeza nenhuma. Por isso a
varredura da §4 existe.

---

## 1. Guarda A — quem espera humano não entra na varredura

`enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb`, método `scannable`.

O `HumanHandoffService` **não solta o espelho captain** (é o Modelo A: a IA segue dona até um
humano puxar a atribuição) e o `bot_handoff!` deixa a conversa `open`. Resultado: uma conversa
que está na fila do **humano** casa perfeitamente com `inbox.conversations.open.assigned_to_captain`
— o mesmo escopo que alimenta a fila do **encerramento**. Nada a excluía.

O que isso custa quando a política estiver ligada, em ordem de gravidade:

1. **O cliente que espera uma pessoa recebe "vou encerrar".** O ramo `queue` do
   `dispatch_closure_action` manda o `closing_notice` antes de enfileirar.
2. **A conversa fica nas duas filas ao mesmo tempo** — o `conversation_finder` conta
   `awaiting_count` e `awaiting_closure_count` em colunas separadas e a mesma conversa apareceria
   nas duas, sumindo do filtro "IA" por dois motivos independentes.
3. **Uma classificação de LLM por ciclo de cron**, para uma conversa que não é assunto do
   encerramento. Com `BULK_ACTIONS_LIMIT = 100` por ciclo, é vaga tirada de quem precisa.

### O fix

```ruby
def scannable(scope, account)
  scope = scope.where("conversations.custom_attributes->>'aguardando_humano_desde' IS NULL")
  return scope if closure_max_days(account).positive?

  scope.where("conversations.custom_attributes->>'aguardando_encerramento_desde' IS NULL")
end
```

**A exclusão é incondicional, e isso é escolha, não descuido.** A exclusão que já existia depende
da válvula (`max_dias`) porque uma conversa na fila de encerramento **precisa** voltar ao scan
para que a válvula possa fechá-la. A da fila do humano não: o encerramento não tem o que fazer
ali em nenhum cenário. O teto do "esperando humano" — regra 6 do contrato do eixo — é outra
decisão, e o próprio contrato manda combiná-la com a **`spx/rodizio`** (que já tem
`sla_assumir_minutos` como *medida*, não ação). Um teto que nascesse como efeito colateral da
válvula do encerramento seria um segundo relógio divergindo do dela.

### Adjacência observada, NÃO corrigida

O caminho **legado** (`resolvable_pending_conversations` com `closure_on = false`, que serve o
`perform_time_based` e o `route_legacy`) não passa pelo `scannable` — logo uma conversa `pending`
com `aguardando_humano_desde` continuaria alcançável por ele. Hoje é inalcançável na prática: o
handoff deixa a conversa `open`, e a inbox 91 tem `pending_status_enabled = false`. Fica anotado
por ser outro caminho, fora do recorte nomeado na tarefa.

---

## 2. Guarda B — quem volta a falar sai da fila

`enterprise/app/models/enterprise/concerns/conversation.rb`, `awaiting_closure_customer_returned?`.

### A decisão que a tarefa pede: o sinal certo é **o incoming**, não a transição de `waiting_since`

Duas razões, e a segunda é decisiva.

**(1) `waiting_since` satura.** O campo só é populado quando está vazio
(`set_waiting_since_on_incoming_message`: `return unless incoming? && conversation.waiting_since.blank?`),
e toda conversa **nasce** com ele preenchido (`before_create :ensure_waiting_since`). Então a
transição `nil -> presente` só existe num recorte: o cliente falando **depois** de a IA ter
respondido. Conversa que entra na fila com o cliente tendo falado por último — 253 das 355 em
produção — não produz transição nenhuma no próximo incoming.

**(2) Nesse caso o `after_commit` da conversa nem roda.** Quando o incoming chega numa conversa
`open` cujo `waiting_since` já está preenchido, **a conversa não é salva**: o
`set_waiting_since_on_incoming_message` sai antes do `update`, e o único toque no registro é o
`set_conversation_activity`, que usa `update_columns` — sem callbacks, sem `after_commit`.
Os outros passos do `execute_after_create_commit_callbacks` também não salvam (`reopen_conversation`
só age em `resolved`/`snoozed`; `mark_pending_conversation_as_open_for_human_response` só em
`pending`; `release_captain_mirror_after_human_reply` só em outgoing de humano).

Ou seja: **do lado da conversa, esse evento é invisível.** A guarda B não é apenas estreita —
para a população que ela precisaria servir, ela é **inalcançável**. Nenhuma reescrita do predicado
dentro do `after_commit` resolveria, porque o callback não chega a ser chamado.

### Custo — a pergunta que a tarefa manda pesar

Fazer a checagem no `after_commit` da conversa (`awaiting_closure_clearable?` roda em **toda**
conversa que salva) exigiria algo como `messages.incoming.where('created_at > ?', desde).exists?`:
**uma query por commit de conversa**, para uma condição falsa em praticamente todas — e ainda
assim errada, pelo motivo (2).

No caminho da mensagem o custo é: `incoming?`, `private?` e **uma checagem de chave em memória**
no `custom_attributes` da conversa já carregada. **Zero query nova**, e só em mensagem incoming.

### O fix

Segue o padrão que o próprio fork já usa para o A2c (`release_captain_mirror_after_human_reply`):
hook **no-op no OSS**, implementado no `Enterprise::Message` (que é `prepend`ado).

- `app/models/message.rb` — chama `clear_awaiting_closure_after_customer_reply` no
  `execute_after_create_commit_callbacks` e declara o no-op.
- `enterprise/app/models/enterprise/message.rb` — implementa: incoming não-privado chama a
  conversa.
- `enterprise/app/models/enterprise/concerns/conversation.rb` — ganha
  `clear_awaiting_closure_on_customer_reply` **público**, que reusa o
  `clear_awaiting_closure_marker` já existente (uma única implementação da limpeza).

`awaiting_closure_customer_returned?` **foi mantido de propósito** (o comentário no código diz
por quê): além do incoming pós-resposta da IA, ele pega o `bot_handoff!`, que repopula
`waiting_since` ao mandar a conversa para a fila do humano. Sem ele, uma conversa que sai do
encerramento para o handoff ficaria marcada nas duas filas — exatamente o que a guarda A evita do
outro lado. Remover teria sido uma troca de um bug por outro.

---

## 3. O gêmeo `awaiting_human_clearable?` — verificado, e **não** tem o mesmo vício

A tarefa manda olhar e apenas relatar. Olhado:

```ruby
awaiting_human_assumed?  # saved_change_to_assignee_id? && assignee_id.present?
awaiting_human_replied?  # saved_change_to_assignee_agent_bot_id? && blank? && reason == 'human_reply'
```

São transições também — mas aqui a transição **é** o evento: "um humano assumiu" e "um humano
respondeu soltando o espelho" acontecem *sendo* mudanças de coluna, e essas mudanças salvam a
conversa. Não há saturação equivalente à do `waiting_since`. O caso que seria imune — marcador
caindo numa conversa que **já** tem assignee humano — é barrado pelo
`reset_agent_bot_when_assignee_present` (conversa não tem dono humano e espelho ao mesmo tempo) e
pelo fato de o handoff sempre partir de conversa do espelho.

Medido em produção (8 conversas com o marcador): **0 já com assignee**, **0 sem espelho** — ou
seja, nenhuma imune hoje. **Nada a corrigir.**

O que continua aberto ali é outra coisa, já registrada no contrato: **não existe teto**. Se o
humano nunca assume e nunca responde, o marcador fica — é a regra 6, e é decisão a combinar com a
`spx/rodizio`. Fora do escopo desta tarefa.

---

## 4. Resíduo: a correção **não** destrava as 355 sozinha

Confirmado pelo mecanismo, não por suposição: as três saídas do marcador (humano assume, cliente
volta a falar, conversa resolve) são todas **eventos**. Conversa parada não gera evento — logo o
marcador fica, e a fila do time segue com 355 conversas que não deveriam estar lá (a política
está **desligada**: nenhuma delas é fila legítima).

Escrito, **em dry-run**, e **não executado**:

**`scripts/spx/tozi/limpa_marcadores_encerramento.rb`**

- `DRY=1` por padrão. Só conta e mostra amostra. `DRY=0` é decisão do Paulo.
- Remove **apenas** as três chaves do encerramento (`aguardando_encerramento_desde`,
  `encerramento_avisado_em`, `encerramento_classe`). Não muda status, não atribui, não manda
  mensagem, **não toca em `aguardando_humano_desde`**.
- `update_columns` de propósito, igual ao concern: apagar marcador não é movimentar conversa — um
  `update!` em 355 conversas dispararia a cadeia de `after_commit` (funil, ActionCable, webhooks)
  e a limpeza viraria evento.
- Corte por idade (`DIAS`, default 3) para que, com a política já ligada, fila legítima recente
  não seja varrida junto.

**Dry-run rodado em produção (leitura pura, nada escrito):**

```
conta 6 · auto_closure = {"enabled" => false, "max_dias" => 0}
marcadores no total: 355
com mais de 3 dia(s): 355   <== conversas que este script tocaria
modo: DRY-RUN (nada será escrito)
```

**355 conversas.** Todas com mais de 3 dias — o que confirma a origem: resíduo de 03/08, não fila
viva.

---

## 5. Verificação

### Isolamento duplo (a `.232` é compartilhada por todas as frentes)

- Path próprio: **`/tmp/ci-followup-c`** — conferido antes (`ps aux | grep ci-`: nenhum processo;
  `/tmp` tinha `/tmp/ci-camp` e `/tmp/ci-camp-files` de outra frente, intocados).
- Banco próprio: **`chatwoot_ci_fup_c`** no `db:migrate` **e** no `rspec`.
- Conferido antes de rodar que o `.env` symlinkado **não define `POSTGRES_DATABASE`** (sem isso,
  `RAILS_ENV=test` apontaria para o banco vivo da `.232`).

### Suíte

Baseline = **meu ramo sem o meu commit** (`788ece5d89` limpo, no mesmo banco e mesma máquina):

| Momento | Examples | Falhas |
|---|---:|---:|
| Baseline dos 2 arquivos que toquei | 42 | **3** |
| Depois do fix (mesmos 2 arquivos) | 51 | **3** |
| **Conjunto completo do baseline (5 arquivos)** | **211** | **12** |

**12 falhas = as 12 documentadas** em `spx-followup-baseline.md` (9 da guarda de `pending` na
`spec/models/conversation_spec.rb` + 3 do contrato do `ActivityMessageJob`/locale). Nenhuma nova.
**9 exemplos novos, todos verdes.**

Dois arquivos vizinhos, fora do baseline, rodados por eu ter tocado o `Message` do OSS:
`spec/models/message_spec.rb` + `spec/enterprise/models/conversation_spec.rb` → **140 examples, 1
falha** (`conversation_spec.rb:17`, SLA + activity message). **Preexistente**: com as minhas
mudanças em `stash`, a mesma falha aparece igual (26 examples, 1 failure).

### Teste de mutação (revertendo o fix, confirmando vermelho)

| Mutação | Resultado |
|---|---|
| Guarda A removida do `scannable` | **3 de 4** exemplos vermelhos (o 4º é o controle positivo — a conversa da IA *sem* marcador **tem** que continuar sendo varrida, e continua) |
| Guarda B revertida (`Enterprise::Message` original) | **2 de 5** exemplos vermelhos — exatamente os dois que dependem do sinal novo; os 3 restantes (transição, e os dois "não pode limpar") seguem verdes |

Os testes detectam de verdade, e detectam a coisa certa.

### Lint

`rubocop` nos 6 arquivos tocados + no script novo: **0 offenses**. (Baseline dos dois arquivos de
código que vieram do baseline: 0 e 0 — mantido.)

### Banco de teste sujo?

**Não.** Banco dedicado `chatwoot_ci_fup_c` criado e **dropado** ao final; worktree removida;
`/tmp/xfer-c` apagado. Lista de bancos antes e depois **idêntica**. O `chatwoot_test`
compartilhado **não foi tocado**.

---

## 6. O que fica para quem for religar o `auto_closure`

1. **Drenar o passivo antes** (`DRY=0` no script da §4) — senão o time abre a fila e vê 355
   conversas velhas misturadas com as novas, e a primeira impressão da feature é uma fila
   entupida.
2. A ordem das duas chaves continua valendo e continua sendo o risco maior: **ligar** =
   `auto_closure` primeiro, kill-switch depois. **Desligar** = kill-switch primeiro.
3. Com `max_dias: 0` (valor atual) a válvula não fecha nada — a fila é hold indefinido esperando
   humano. Decisão de produto, não bug; só não confundir com "a fila não funciona".
