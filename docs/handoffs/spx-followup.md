# HANDOFF — frente `spx/followup`

> Follow-up, encerramento, agendamento e notificações. Branch executora: **`spx/followup`**.
> Quem integra e deploya é a sessão da pasta `Workspaces/chatspx`.

---

## 🚨 AVISO DE DEPLOY — este merge muda VOLUME, não só comportamento

**Leia antes de aprovar o deploy.** Não é um conserto silencioso: quando entrar, coisas que
**nunca aconteceram** em produção passam a acontecer, e caem na fila de gente que hoje não as
recebe.

### Por quê

Três `event_type` emitidos pelo `ResponseBuilderJob` nunca estiveram em
`Captain::AssistantLog::EVENT_TYPES`. O `create!` levantava `RecordInvalid`, o `rescue` do
**chamador** engolia em silêncio, e tudo que vinha **depois da linha de log** deixava de
acontecer. Como o log é a primeira linha do método, três features estavam mortas:

| `event_type` | Feature | Estado real em produção |
|---|---|---|
| `handoff_auto_fired` | safety-net de handoff (P10) | **nunca disparou** |
| `dedup_regenerate` | backstop anti-repetição | morria antes de regenerar → a conversa silenciava |
| `unknown_marker` | retry de resposta inenviável | nunca re-rodava; ia direto pra humano |

### Consequência operacional no primeiro dia

- **Handoffs vão aumentar.** Toda conversa em que a IA escreve que uma pessoa assume — e que
  hoje morre ali, com o cliente esperando alguém que nunca vem — passa a acionar a passagem de
  verdade. Não há como estimar o volume pelo histórico: o evento nunca foi gravado (era
  justamente o `create!` que falhava), então **não existe série histórica desse caso**.
- **Esses handoffs entram no rodízio.** Os dois gatilhos (`ensure_handoff_if_promised` e
  `process_action('handoff')`) passaram a ir pelo `HumanHandoffService`, que chama o
  `Spx::Distribuicao::DistribuirService`. Antes chamavam `bot_handoff!` puro e pulavam
  dossiê, time e rodízio.
- **A detecção ficou mais larga**: passou a reconhecer `corretor/vendedor/gerente/especialista`
  (e feminino/plural), além da promessa no presente ("eu passo pro corretor"), que exigia
  auxiliar (`vou/vamos/irei`) e não casava.

### Combina com outra frente

A **`spx/rodizio`** está ligando designação, espelho no Vista e contagem por corretor em cima
**deste mesmo caminho**. O aumento de handoff chega lá também. Alinhar as duas antes de subir.

### Recomendação

Subir com alguém olhando a fila no primeiro dia, e ter à mão o kill-switch por conta
(`behavior`/config do agente) caso o volume surpreenda. Se preferir, dá pra medir antes:
com o merge em homologação, o `AssistantLog` passa a gravar `handoff_auto_fired` — em alguns
dias existe a série que hoje não existe.

---

## O que está na branch

| Commit | O quê |
|---|---|
| `fd5b810dd` | safety-net de handoff passa pelo `HumanHandoffService` (dossiê + time + rodízio); detecção alargada + veto de auto-apresentação |
| `a3b39a7ea` | `process_action('handoff')` idem — é o caminho do `error_response` **e** do `handle_error`, ou seja dispara quando a IA quebra |
| `52d85280a` | despedida educada não cancela cutucada com compromisso pendente (conv 20320) |
| `4208cf2c7` | declara os `event_type` que faltavam + `log_behavior_event` com `rescue` próprio |

**Decisão estrutural**: registrar nunca pode derrubar comportamento. O `log_behavior_event`
ganhou `rescue` — sem isso, o próximo rótulo que alguém esquecer de declarar mata em silêncio a
feature que ele deveria observar. Foi esse acoplamento que escondeu três features por meses.

### Verificação

Rodado na `.232`, worktree isolado (receita em `docs/WORKFLOW-GIT-SPX.md`):
**55 examples, 0 failures** · RuboCop **16 offenses** nos arquivos tocados = **baseline exato**.

Teste de mutação: revertendo o gate do compromisso, os 3 exemplos da 20320 ficam vermelhos —
eles detectam de verdade. (Antes do fix de fixture passavam **em vazio**: o `travel_to` do
`before` roda depois da mensagem outgoing, então tudo criado nos exemplos nascia com
`created_at` anterior e `lead_replied?` era falso de qualquer jeito.)

---

## Próximo: ligar o `auto_closure` na Tozi

Levantamento **read-only** na produção Tozi (conta 6, `3.82.215.109`) em 31/07/2026.

### Estado dos gates

| Gate | Valor em prod | Situação |
|---|---|---|
| `captain_auto_resolve_mode` | `"disabled"` | 🔴 **bloqueia tudo** — barra no scheduler e no `#perform` |
| `feature_enabled?('captain_tasks')` | `true` | ✅ |
| `settings['auto_closure']` | `nil` | 🔴 não configurado → `auto_closure_enabled?` é false |
| `route_with_closure_policy` | presente | ✅ o código-base da fila **já está em prod** |
| `evaluate_conversation_completion?` | `captain_tasks && evaluated?` | 🔴 **falta o `\|\| auto_closure_enabled?`** |

### O que falta, em ordem

1. **Código** — o que importa é o `782cf28f2`. Sem ele, `auto_closure.enabled = true` numa conta
   em modo `legacy` fica **ligado porém dormente**: o roteador de encerramento vive em
   `perform_with_evaluation`, que só rodava no modo `evaluated`. Os outros três: `d985beeaf`
   (prod já tem o gate `captain_tasks`, mas o diff difere), `e0c858dbb` (só rubocop, não exige
   restart), `55d42db54` (frontend "Devolver para a IA" — **exige precompile**).

2. **Tirar o `captain_auto_resolve_mode` de `disabled`** — e aqui mora uma armadilha. Esse
   `disabled` foi posto de propósito em 01/06, depois do incidente em que o auto-resolve fechou
   conversas de clientes reais. Se alguém mudar para `legacy` **sem** configurar o
   `auto_closure`, o `evaluate_conversation_completion?` dá false e cai no
   **`perform_time_based`** — que é exatamente o comportamento do incidente. A ordem importa:
   configurar o `auto_closure` **antes** de destravar o modo.

3. **Configurar `settings['auto_closure']`** na conta 6: `enabled`, `actions` por classe
   (default é `queue`) e `closing_notice`.

### Volume esperado quando ligar

`resolvable_pending_conversations` com `closure_on` alcança **também as abertas da IA** (não só
`pending` — o que faz sentido no Modelo A, onde a inbox 91 tem `pending_status_enabled=false` e
só 2 pending).

Abertas da IA paradas na inbox 91, hoje: **496 (>1h)** · 483 (>24h) · **300 (>7d)** ·
**0 já aguardando humano**.

`Limits::BULK_ACTIONS_LIMIT = 100` por ciclo de cron → a represa drena em ~5 ciclos, **cada
conversa passando por uma chamada de classificação (LLM)**. Ou seja: ligar o `auto_closure`
tem custo de inferência e mexe em 496 conversas reais. Considerar drenar o passivo de forma
controlada antes de deixar o cron solto.

---

## Próximo item: a promessa que o HUMANO esquece — desenho travado

Escolhido antes da cadência configurável porque reusa o motor de compromisso já consertado
(`followup_motivo` consumido no disparo) e é o caso descrito com nome: atendente promete
retorno e some. A cadência configurável depende de tela, então vem depois.

**Decisões batidas (Paulo, 31/07):**

1. **Detecção automática, exigindo prazo explícito.** Listener na mensagem `outgoing` de `User`
   (não de `Captain::Assistant`), no padrão do `Spx::TemplateReplyRouterListener`. Só registra
   quando há **expressão de tempo** — é ela que discrimina promessa de intenção vaga: "vou ver
   isso" não conta, "te mando amanhã" conta. Sem prazo não há o que cobrar.
   Motivo de não usar só o botão adiar/resolver: quem esquece a promessa também esquece o botão.

2. **Escalada só interna, terminando na fila do time.** Prazo vence → nota privada + notificação
   pro autor. Continuou parada → devolve à fila do time. **A IA não fala com o cliente numa
   conversa de humano**: contradiz o Modelo A e ela não sabe o que foi combinado fora do sistema
   (ligação, WhatsApp pessoal) — poderia prometer o que já foi entregue.

**Decidido por regra de projeto, não precisa perguntar:** opt-in **por conta** (default off),
como todo comportamento novo — nunca hardcode de cliente.

**Cuidado conhecido na entrega:** as notificações desta conta vêm **OFF de fábrica**
(`assigned_conversation_new_message` sem push/email), então lembrete que dependa só do
`Notification` pode nunca ser visto. Por isso a nota privada na conversa é o canal primário, e a
notificação é reforço — e por isso a escalada pro time existe.

**Peças a reusar, não reinventar:** `snoozed_until` + `Conversations::ReopenSnoozedConversationsJob`
(o "adiar" já existe e reabre sozinho) · o motor de compromisso do `FollowupJob` · o padrão de
listener SPX.

## Aberto nesta frente

- **Cadência personalizável no front** (hoje é código: `MAX_FOLLOWUPS`, `QUIET_START/END`,
  `followup_auto_minutes` no behavior).
- **Notificações** — subexploradas.
- **Promessa do humano** que ele esquece (a da IA já é coberta pelo compromisso).
- **Repescagem por reenvio de template.**
- **NPS no fechamento**: uma conversa ≠ um atendimento; fechar/reabrir dispara pesquisa.
- **Aresta aceita**: se o compromisso morre sem cumprir porque um humano assumiu, o
  `followup_motivo` fica armado e a cutucada preventiva fica suspensa até o agente programar um
  novo follow-up (que rearma os dois). Auto-curável pela tool; está comentado no código.
