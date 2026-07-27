# Encerramento inteligente + fila "Aguardando encerramento" — desenho executável

> Feature multi-tenant, **tudo opt-in por conta** (behavior/config, zero hardcode de cliente).
> Commit direto na `homologacao`; validar na conta 3 (.232) via AgentRunnerService/E2E antes de promover.
> Escopo deste doc: **desenho + pontos de extensão escolhidos**. Implementação só após OK do Paulo.

## 1. Objetivo e critério de sucesso

A aba IA está lotada de conversas que já deviam ter encerrado, mas encerrar é delicado: o que um humano
poderia reverter (ligar, retomar) **não pode sumir da vista**. Critério verificável:
- **A) trivial** fecha sozinha, com private note do motivo;
- **B) substantiva** aparece numa **fila visível e reversível**, sem fechar;
- **C) campanha sem resposta** nunca fecha (espera o próximo template);
- **D) clique-e-silêncio** recebe cadência de 2 mensagens (config da conta) e então fecha.
Tudo provado na conta 3.

## 2. O que já existe (reuso — não reescrever)

| Peça | Arquivo | Papel no desenho |
|---|---|---|
| Cron por inbox | `enterprise/app/jobs/enterprise/account/conversations_resolution_scheduler_job.rb` | entry point (já dedupe por inbox, já pula `captain_auto_resolve_disabled?`) |
| **Job de varredura** | `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb` | **esqueleto da triagem** — `perform_with_evaluation` já ramifica resolve↔handoff; private note + `resolution_message` já existem; já pula OOO de campanha |
| Avaliador LLM | `enterprise/lib/captain/conversation_completion_service.rb` + `_schema.rb` | **hoje binário** (`complete` bool) — vira classificador A/B/C/D |
| Gate por conta | `app/models/concerns/account_captain_auto_resolve.rb` | modos `evaluated`/`legacy`/`disabled` via `settings['captain_auto_resolve_mode']` |
| Tool de encerrar | `enterprise/lib/captain/tools/resolve_conversation_tool.rb` | encerramento no fluxo da resposta (mesma trava de conta) |
| **Fila "aguardando atendimento"** | **versionada e LIVE** (commits `6eb393938`+`ba0f12492`, em homologacao/producao): `scope :awaiting_human`, finder `assignee_type='awaiting'`, `clear_awaiting_human_marker`, gate `reply_assignment_gate_enabled?` | **padrão gêmeo a espelhar** para a fila B |
| Cadência in-window | `programar_followup_tool.rb` + `enterprise/app/jobs/captain/conversation/followup_job.rb` | motor da cadência do caso D (poke agente-composto, quiet hours, MAX 4) |
| Funil visível | `app/services/spx/tozi/funnel_placement_service.rb` | materialização alternativa (kanban) — Tozi-namespaced |
| NPS no resolve | `app/listeners/nps_survey_listener.rb` | dispara só em `resolved?` → só A e D disparam NPS; B não |

## 3. Fluxo da triagem (roda no `perform_with_evaluation`, por conversa pending parada >cutoff)

```
conversa pending parada (last_activity_at < cutoff)
  │
  ├─ campaign.present? E sem incoming?  ──► C: SKIP total (nunca resolve, nunca fila)   [guardrail 4]
  │
  └─ classifica via ConversationCompletionService (LLM) ──►
        A trivial              ──► auto-resolve (private note + resolution_message)  [default: OFF]
        B substantiva          ──► marca aguardando_encerramento + private note; NÃO fecha, NÃO fala
        D campanha+clique+silêncio ──► agenda cadência de 2 msgs (config) → resolve no fim
```

Mapa **classe → ação** é **config da conta** (§6). **Default conservador: A e D também caem em B** (fila),
até medir; só então liga-se auto-close de A e cadência de D.

## 4. Pontos de extensão escolhidos (cirúrgico)

1. **Classificador** — `ConversationCompletionSchema`: trocar `boolean complete` por
   `string classe` (enum `trivial|substantiva|campanha_sem_resposta|campanha_clique_silencio`) + `reason`.
   `ConversationCompletionService#parse_response` devolve `{classe, reason}`. Prompt (`conversation_completion.liquid`)
   ganha a taxonomia — **agnóstico** (sem nome de cliente/vertical). Retrocompat: `complete` derivado (`classe == :trivial`).
2. **Roteador** — `InboxPendingConversationsResolutionJob`: `perform_with_evaluation` passa a ler `classe`,
   consultar o mapa da conta e despachar. `resolve_conversation`/private note reusados como estão.
   `resolvable_pending_conversations` ganha o **guard de campanha-sem-resposta** (guardrail 4).
3. **Fila B** — novo marcador `custom_attributes['aguardando_encerramento_desde']` + `scope :awaiting_closure`
   + case de finder `assignee_type='pending_closure'` + tab + contagem (espelhando `awaiting_human` — §7).
   Marcador limpo quando humano assume/responde/resolve (mesma família do `clear_awaiting_human_marker`).
4. **Cadência D** — job dedicado (irmão do `FollowupJob`) que manda penúltima ("vou encerrar") e última
   ("encerrei, pode chamar à vontade") dentro da janela 24h, textos de `config`, e resolve. Reusa quiet-hours/idempotência.

## 4b. Motivo de fechamento (IA + humano) — reuso do workflow de atributos obrigatórios

O fluxo de resolver JÁ tem os dois modais imaginados (`app/javascript/dashboard/components/buttons/ResolveAction.vue`):
- **Time ao resolver** — `useResolveValidation`: sem time, bloqueia o resolve e abre `TeamSelectionModal`.
- **Atributos obrigatórios ao resolver** — `useConversationRequiredAttributes` + `ConversationResolveAttributesModal`:
  se faltar custom attribute marcado obrigatório, o modal força preencher antes de fechar. Config **por conta**:
  `account.settings.conversation_required_attributes` (lista de chaves) + feature flag `CONVERSATION_REQUIRED_ATTRIBUTES`.

**Humano dá o motivo = ~zero código (config, multi-tenant nativo):** criar conversation custom attribute
`motivo_encerramento` (tipo **lista** com categorias, ou texto) → incluí-lo em `conversation_required_attributes`
→ todo resolve humano com o campo vazio abre o modal exigindo o motivo. Só ligar a flag nas contas SPX.

**IA dá o motivo = escrita estruturada (pequena):** o modal é frontend — NÃO intercepta o `resolved!` do backend,
então a IA popula o mesmo campo. Em `resolve_conversation`/`ResolveConversationTool`, além do private note (auditoria),
gravar `custom_attributes['motivo_encerramento']` = categoria derivada da `classe` A/B/C/D + o `reason` do classificador.
IA-fechada e humano-fechada passam a carregar o **mesmo campo estruturado** (consultável, visível na sidebar, alimenta
eval/relatórios) — não uma nota solta.

**Unifica com a fila B:** quando o humano puxa da fila "Aguardando encerramento" e fecha, o modal já pede o motivo;
dá pra **pré-preencher** (`initialValues` do modal) com a sugestão da IA — humano confirma ou edita. IA propõe, humano decide.

## 4c. Regras de fechamento janela-aware (governadas por `can_reply?`)

Sinal-mestre: `conversation.can_reply?` (`Conversations::MessageWindowService`) — **já multi-canal**
(Cloud 24h · WAHA janela config/nenhuma · IG 24h/7d) e retorna **`false` quando nunca houve incoming**
(template não respondido). Governa (a) se dá pra mandar free-form (nota de encerramento / NPS) e
(b) o relógio do fechamento. **Nada free-form sai com a janela fechada.** Multi-canal sai de graça:
sem `if canal ==` — tudo lê `can_reply?`.

Combina 3 sinais determinísticos (`can_reply?`, `campaign?`, tem incoming) + `classe` (LLM):

| Caso | can_reply? | Ação |
|---|---|---|
| trivial (saudação morta) | aberta | 1 nota gentil de encerramento (enquanto aberta) → resolve **silencioso** na expiração |
| substantiva (progrediu, sumiu) | aberta | cutucada firme + nota "vou encerrar" (lever) → re-engajou → volta pra aba IA; senão → **Aguardando encerramento** |
| template sem resposta | fechada | **fecha calado** (config: cadência multi-HSM mantém aberta pro próximo template) |
| clique-e-silêncio (botão→apresentação→sumiu) | aberta | cadência normal (janela aberta) → nota → fecha |
| parada há dias (cliente sumiu) | fechada | **fecha calado**; se substantiva → Aguardando encerramento (humano reabre via HSM) |

> Revisa o brief original: caso **C não é "nunca fecha"** — é **fecha calado** (salvo cadência multi-HSM configurada).

**Timing (porém do Paulo, 21/07):** a nota de encerramento é a **ÚNICA** despedida e sai **enquanto a janela
está aberta**; o `resolved!` na/após a expiração é **SILENCIOSO** — implica **suprimir `create_resolution_message`**
nesses fechos (a nota já foi a despedida; nada entrega pós-expiração). NPS, quando cabível, dispara **antes/junto
da nota, com a janela aberta**; em fecho de trivial/template-sem-resposta, **pula NPS** (lead morto — não repetir
o vazamento de junho, mesma causa: >24h bloqueia captura).

**Decisão (delegada, Paulo 21/07):** substantiva que esgota a cadência e segue muda → **não auto-fecha**;
nota + vai pra Aguardando encerramento (worklist real do humano). Válvula anti-pilha: auto-fecha após
`aguardando_encerramento_max_dias` ocioso (default 3, config; `hold_indefinido` opcional). Trivial → auto-fecha
na expiração. Cliente volta a falar em qualquer ponto → limpa marcador, volta pra aba IA.

**Horário comercial / pico de engajamento (nota do Paulo):** relevante, mas vive na **CADÊNCIA** (QUANDO disparar
cutucada/nota dentro da janela — ex.: lead das 7h que só volta às 18h), não na decisão de fechar (a janela de 24h
já cobre o dia inteiro). Reusa o seam de quiet-hours do `FollowupJob` (hoje 21h–8h). Opt-in por conta (padrões de
pico variam por cliente/canal). Fase posterior.

## 5. Guardrails (mapeados)

1. **NPS** — só A e D chegam a `resolved!` → NPS dispara só nesses (esperado). B não fecha ⇒ zero NPS.
   Sweep one-time do backlog = **tarefa separada**, NPS-safe (janela >24h já bloqueia captura).
2. **Episódio (F1)** — resolve = fronteira; B não resolve ⇒ sem fronteira prematura. ⚠️ `EpisodeSegmenterService`
   está na `producao`, **não nesta branch** — coerência a validar no merge, não bloqueia o desenho.
3. **Auditabilidade** — toda decisão (fecha/fila/espera) grava private note com motivo (padrão `create_private_note` já existe).
4. **Campanha nunca expira por tempo** — guard no job antes do LLM (item 4.2).
5. **Config por conta** — §6; default = tudo pra fila B.

## 6. Config por conta (behavior JSONB, opt-in)

```json
"auto_closure": {
  "enabled": false,
  "actions": { "trivial": "queue", "substantiva": "queue", "campanha_clique_silencio": "queue" },
  "closing_cadence": { "penultima_wait_min": 60, "ultima_wait_min": 60 }
}
```
Textos da cadência e `resolution_message` vêm de `assistant.config` (**REGRA #1: zero exemplos copiáveis** no
prompt/tool — descrever origem do valor, nunca um exemplo). `enabled:false` ⇒ comportamento atual intacto.
**Motivo de fechamento (§4b) tem config própria** (não no behavior): custom attribute `motivo_encerramento` +
`account.settings.conversation_required_attributes` + flag `CONVERSATION_REQUIRED_ATTRIBUTES` — por conta.

## 7. Materialização da fila B — DECIDIDO: espelhar o subsistema `awaiting`

Novo marcador `aguardando_encerramento_desde` + `scope :awaiting_closure` + case de finder + tab + count,
espelhando 1:1 os commits `6eb393938`/`ba0f12492` (que estão **versionados em homologacao/producao e LIVE**).
UX consistente com o "Aguardando atendimento" que a operação já usa; reversível; gateado por conta.

> ⚠️ **Correção de premissa:** não há dívida de off-git aqui — o subsistema base está na `homologacao`.
> A confusão inicial foi checkout local velho (457 commits atrás; `Temp/offgit-232/` é só dump do deployado).
> **Único pré-requisito:** trabalhar sobre a `homologacao` atual (§8 passo 0).
>
> Descartados: **funil** (`FunnelPlacementService` é `Spx::Tozi::*`, exigiria generalizar + nem toda conta usa)
> e **label+custom view** (menos integrado à aba IA). A gêmea `awaiting` ganha em consistência e reuso.

## Status de implementação (22/07 — worktree `chatspx-homolog`, NÃO commitado/pushado)

**Construído (núcleo, opt-in por conta, default OFF → zero efeito até uma conta ligar):**
- **Classificador** — `classe` (trivial/substantive) aditivo no schema+service+prompt (`complete` intacto).
- **Fila backend** — `scope :awaiting_closure` + finder `assignee_type='pending_closure'` + `awaiting_closure_count` +
  aba IA passa a excluir o marcador + limpeza no concern (humano assume · cliente volta · resolve).
- **Frontend abas** — `PENDING_CLOSURE` + `QUEUE_KEYS=[AWAITING, PENDING_CLOSURE]` (IA sobe pra linha 1 entre
  Minhas/Todas; linha 2 = as duas filas) + ícone `check-check` + variante **neutra** (não vermelho) + store + i18n en/pt.
- **Serviço** `Captain::Conversation::PendingClosureService` (gêmeo do `HumanHandoffService`: marca, abre p/ visível,
  IA segue dona, private note; não fecha).
- **Roteador** no `InboxPendingConversationsResolutionJob`: gate `account.settings['auto_closure']`; guard campanha-sem-resposta;
  classe → `close`/`queue` (default `queue`); `close` janela-aware (suprime `resolution_message` se `!can_reply?`) + grava
  `motivo_encerramento`; targeting expande p/ OPEN-da-IA quando ligado.

- **Cadência (inc. 5)** — stateful via marcadores no cron (sem job novo): nota "vou encerrar" enquanto a janela abre
  (`encerramento_avisado_em`+classe) → espera expirar → fecho SILENCIOSO; substantiva manda a nota e vai pra fila;
  **válvula** `max_dias` (default 3; `0`=hold). Concern limpa os marcadores da cadência junto. Texto por classe da config.
- **Combobox creatable (inc. 6)** — prop `creatable` opt-in no `ComboBox` (default off) + modal de resolver opta: humano
  digita categoria nova → vira opção selecionável → salva no `motivo_encerramento` da conversa.

**Config da conta (`account.settings['auto_closure']`):** `{ enabled, actions:{trivial,substantive:'close'|'queue'|'off'},
closing_notice:{trivial,substantive,default}, max_dias }`. Default: enabled=false (inerte); action ausente=`queue`; max_dias=3.

**Falta só:** **ops** (flag `CONVERSATION_REQUIRED_ATTRIBUTES` + custom attribute `motivo_encerramento` +
`account.settings['auto_closure']` na conta 3) · **verificação na `.232`** · nice-to-have: persistir categoria criada de volta
na definição do atributo (reuso cross-conversa sem editar em Settings).

## 8. Ordem de implementação + verificação

0. **Atualizar checkout local pra `homologacao` atual** (estou 457 commits atrás, merge-base 08/07) — a base
   `awaiting` a espelhar já está lá. Sem isso, qualquer edição nasce sobre código de 12 dias atrás.
1. Classificador (schema+service+prompt) → verifica: `AgentRunnerService` classifica 4 convs-amostra corretamente.
2. Guard campanha-sem-resposta no job → verifica: conversa de campanha sem incoming não é tocada (rails runner).
3. Fila B (marcador+finder+tab) → verifica: conversa marcada aparece na fila, some da aba IA, humano assume limpa o marcador.
4. Roteador liga tudo, **default = tudo pra fila B** → verifica E2E conta 3: trivial→fila, substantiva→fila, campanha→intacta.
5. Só então: cadência D + flip de A pra auto-close, medindo pelo eval.
