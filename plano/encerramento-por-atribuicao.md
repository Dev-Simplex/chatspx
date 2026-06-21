# Plano — Encerramento (resolver) só por quem está atribuído

> **Status: PLANEJADO, não iniciado** (2026-06-12).
> Feature irmã do **gate universal de resposta** (Fase D do `ia-consolidado.md`): assim como
> "só o assignee responde", aqui **só o assignee encerra**. Ao tentar encerrar uma conversa
> que não é sua, aparece um **modal para atribuir a você** — e, ao confirmar, atribui e encerra
> no mesmo gesto. Reaproveita o trilho já construído (flag, dialog, guard 422).
> **Working tree only — nenhum commit até validado.**

---

## 1. Decisões (com recomendação; itens "❓" precisam do Walisson)

| # | Decisão | Resolução proposta |
|---|---|---|
| R-1 | Regra central | **Encerrar (status `resolved`) exige que `conversation.assignee_id == current_user.id`.** Se não estiver atribuída a quem encerra → bloqueia e oferece atribuir |
| R-2 | UX ao bloquear | **Modal "Atribuir a você e encerrar?"** — 1 clique atribui (self) e encerra em sequência. Mesma mecânica de 4 variantes do `AssignToReplyDialog` (sem dono / de colega / da IA / fora do time → escolhe um time seu) |
| R-3 | Flag/Modo | **Reusar o mesmo modo "Atribuição obrigatória"** (`reply_assignment_gate`) — quem liga o gate de resposta liga o de encerramento junto. Coerência: se não pode responder sem ser dono, não encerra sem ser dono. ❓ Alternativa: flag separada `resolve_assignment_gate` se quiser ligar um sem o outro |
| R-4 | Escopo de status | **Só `resolved` (encerrar).** `reopen`/`snooze`/`pending` fora do escopo (reopen, aliás, já auto-atribui — `toggle_status_service.rb:30 should_assign_conversation?`) |
| R-5 | Admin | **Sem exceção** — admin também passa pelo modal (consistente com o gate de resposta, decisão D-4 do plano principal). ❓ confirmar |
| R-6 | Guard no backend | **Fonte da verdade no `ToggleStatusService`** (não só na UI) — espelha o `validate_team_requirement!` que já existe ali. Erro 422 `resolve_assignment_required` |
| R-7 | Automação/macro/sistema | **Bypass**: resolve disparado por macro, automation rule, scheduled message ou bot **não** passa pelo guard (igual o reply gate ignora automações). Só ação direta de humano é barrada |
| R-8 | Bulk resolve | ❓ Decisão: ao encerrar em massa conversas que não são suas → (a) **atribuir a você + encerrar todas** com um confirm único ("X não são suas — atribuir a você e encerrar?"); (b) encerrar só as suas e pular o resto com aviso; (c) bloquear o lote. **Recomendo (a)** |
| R-9 | Conversa da IA | Encerrar conversa atribuída à IA → modal "Assumir da {IA} e encerrar?" → self-assign solta o espelho (callback de exclusividade) → encerra. Consistente com R-2 |
| R-10 | Modo Clássico | Flag desligada → **comportamento atual intacto** (qualquer um encerra, sem modal) |

## 2. O modelo-alvo em uma narrativa

Atendente clica **Resolver** numa conversa que **é dele** → encerra normal, como hoje.
Clica em **Resolver** numa conversa que **não é dele** → em vez de encerrar, sobe um **modal**:
- conversa **sem dono** e ele é do time (ou conversa sem time) → *"Atribuir a você e encerrar?"* (1 clique)
- conversa **de um colega** → *"Assumir de {nome} e encerrar?"* (colega notificado — reusa D4 do gate)
- conversa **da IA** → *"Assumir da {IA} e encerrar?"* (espelho é solto)
- ele **não é do time** (admin/agente de outro time) → o modal mostra **os times dele** pra escolher + *"Atribuir e encerrar"*

Ao confirmar: atribui o time (se preciso) → atribui a si → **encerra**. Tudo num gesto, o
encerramento nunca se perde. No modo Clássico, nada muda.

## 3. A base que JÁ existe (verificada 2026-06-12)

| Peça | Onde | Como reusar |
|---|---|---|
| Serviço de encerrar (toggle status) | `app/services/conversations/toggle_status_service.rb` (`perform`, `validate_team_requirement!:21`, `should_assign_conversation?:30`) | Adicionar `validate_assignment!` espelhando o `validate_team_requirement!` |
| Endpoint | `app/controllers/api/v1/accounts/conversations_controller.rb` (`toggle_status`) | Capturar o novo erro → 422 |
| Padrão de guard 422 do reply gate (D1) | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:222-229` (`render_assignment_required`, `error_code: 'assignment_required'`) | Copiar pra `error_code: 'resolve_assignment_required'` |
| Flag/modo "Atribuição obrigatória" | `useReplyAssignmentGate.js` (lê `account.settings.reply_assignment_gate`) + toggle `AttendanceModeToggle.vue` | Ler a mesma flag (R-3) |
| **Dialog de assunção (D2) — reaproveitar** | `app/javascript/dashboard/components-next/Conversation/AssignToReplyDialog.vue` (+ spec) | Generalizar com prop `action: 'reply' | 'resolve'` (muda só o texto/CTA e o callback final) |
| Botão Resolver (header) | `app/javascript/dashboard/components/buttons/ResolveAction.vue` (`toggleStatus:94`, `onCmdResolveConversation:128`) — **já tem precedente de modal antes de resolver** (`resolveAttributesModalRef`, `assignTeamAndResolve`) | Interceptar antes do `store.dispatch('toggleStatus', resolved)` |
| Outras superfícies de resolve | context menu `contextMenu/Index.vue`; bulk `conversationBulkActions/UpdateActions.vue` + `Index.vue`; atalho de teclado; macros | Frontend: cobrir as visíveis; backend pega todas |
| Self-assign helpers | store actions `assignAgent`/`assignTeam`; `assignTeamAndResolve` (ResolveAction) | Reusar |
| Notificar dono anterior | NotificationService `conversation_assignment` (D4 do gate) | Reusar |

## 4. Fases e tarefas

### Fase 1 — Backend (guard, fonte da verdade) — P-M
| ID | Tarefa | Onde |
|---|---|---|
| 1.1 | `validate_assignment!` no `ToggleStatusService`: se `params[:status]=='resolved'` E flag ligada E `@user.is_a?(User)` E `@conversation.assignee_id != @user.id` → `raise ResolveAssignmentRequiredError`. Bypass automação/macro/bot (R-7: `@user` não-humano ou contexto de automação) | `toggle_status_service.rb` |
| 1.2 | Capturar o erro no controller → **422** com `error_code: 'resolve_assignment_required'` + metadados (dono atual, time) | `conversations_controller.rb#toggle_status` |
| 1.3 | i18n da mensagem (`conversations.resolve_assignment_gate.assignment_required`) pt_BR + en | `config/locales/*.yml` |
| 1.4 | Bulk: aplicar o guard no caminho de bulk resolve conforme R-8 | `bulk_actions` service/controller |

### Fase 2 — Frontend (modal + interceptação) — M
| ID | Tarefa | Onde |
|---|---|---|
| 2.1 | Generalizar `AssignToReplyDialog.vue` com `action: 'reply' | 'resolve'` (texto/CTA "...e encerrar" + callback que atribui→encerra) | `components-next/Conversation/AssignToReplyDialog.vue` |
| 2.2 | Interceptar o **Resolver** no `ResolveAction.vue`: se flag ligada E não é o dono → abre o dialog em vez de `toggleStatus(resolved)`; ao confirmar, atribui (time+self) e encerra | `buttons/ResolveAction.vue` |
| 2.3 | Cobrir as outras superfícies: context menu e bulk actions (mesma checagem antes de resolver) | `contextMenu/Index.vue`, `conversationBulkActions/*` |
| 2.4 | Tratar 422 `resolve_assignment_required` como fallback (corrida: alguém mudou o dono → reabre o dialog atualizado) | store conversations / ResolveAction |
| 2.5 | Notificar dono anterior quando colega assume p/ encerrar (reusar D4) | — |
| 2.6 | i18n pt_BR + en das strings novas do dialog (variante resolve), zero hardcode | `i18n/locale/*` |

## 5. Plano de testes (inegociável)

### Specs (Rails + Vitest)
- **Backend:** `ToggleStatusService` — dono encerra (ok); não-dono encerra com flag ligada (raise/422); admin não-dono (raise — R-5); automação/macro/bot encerra sem barrar (bypass R-7); flag desligada (comportamento atual); resolve sem time ainda exige time (não regredir `validate_team_requirement!`); bulk conforme R-8.
- **Frontend:** `AssignToReplyDialog` variante `resolve` (4 variantes de texto/CTA); `ResolveAction` abre o dialog quando não-dono + flag ligada e encerra direto quando dono; paridade i18n en↔pt_BR.

### Playwright (OBRIGATÓRIO, light + dark, conta 3, usuário de teste dedicado — NUNCA senha real)
| # | Cenário | Esperado |
|---|---|---|
| PR1 | Dono clica Resolver | encerra direto, sem modal |
| PR2 | Não-dono (do time) clica Resolver | modal "Atribuir a você e encerrar?" → confirma → conversa encerrada e atribuída |
| PR3 | Conversa de colega | modal "Assumir de {nome} e encerrar?" → encerra; colega notificado |
| PR4 | Conversa da IA | modal "Assumir da {IA} e encerrar?" → espelho solto → encerrada |
| PR5 | Admin/agente fora do time | modal mostra os times do usuário → escolhe → atribui+encerra |
| PR6 | Flag desligada (modo Clássico) | Resolver encerra direto, sem modal (nada muda) |
| PR7 | DOM walker | sem i18n key vazada, ícones ok, contraste ok, 0 console errors, nos 2 temas |

### E2E (sandbox conta 3)
- Criar conversa atribuída a outro → tentar encerrar → modal → assumir → encerrar → confirmar status `resolved` e `assignee_id` = usuário.
- Corrida: dois agentes tentam encerrar a mesma → o segundo recebe 422 e o dialog atualizado.
- Bulk resolve com mix (suas + de outros) → comportamento conforme R-8.

## 6. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Guard só na UI → bypass por API | Fonte da verdade no `ToggleStatusService` (1.1), UI é só UX |
| Quebrar automações que resolvem (SLA, scheduled, macro) | Bypass explícito p/ não-humano/automação (R-7) + specs |
| Conflito com `validate_team_requirement!` (resolve já exige time) | O fluxo assume time no dialog (variante "fora do time"); manter as duas validações compondo |
| Bulk resolve travar operação | R-8 decidido antes de implementar; default "atribuir+encerrar com confirm" |
| Macro "resolver" deixar de funcionar p/ agente comum | Macro roda via ActionService/Current.user = executor → tratar como automação (bypass) ou validar caso a caso |
| Flag única acopla reply+resolve | Aceito por coerência (R-3); se incomodar, split em `resolve_assignment_gate` |
| Reabertura/snooze fora do escopo gerar inconsistência | Escopo travado em `resolved` (R-4); reopen já auto-atribui |

## 7. Decisões abertas para o Walisson confirmar

1. **R-3:** mesma flag do gate de resposta, ou flag separada só pro encerramento?
2. **R-5:** admin também passa pelo modal (sem exceção)?
3. **R-8:** bulk resolve de conversas não-suas → atribuir+encerrar (recomendado), pular, ou bloquear?

## 8. Encaixe

Feature irmã da Fase D do `ia-consolidado.md` (gate universal de resposta). Reusa flag, dialog,
guard 422 e notificação já construídos. Pode ser implementada como **"Fase D-bis"** logo após a
revisão humana da Fase D, ou como item isolado. Mesmo modo econômico (Opus + xhigh, sem ultracode),
working tree only, Playwright light+dark antes do aceite.
