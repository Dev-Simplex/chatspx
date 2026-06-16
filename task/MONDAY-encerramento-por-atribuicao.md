# Encerramento de atendimento só por quem está atribuído

---

## 📌 Resumo executivo

Hoje qualquer atendente pode **encerrar** (resolver) qualquer conversa. A proposta: **só encerra quem está atribuído à conversa**. Quem tentar encerrar uma conversa que não é dele vê um **modal "Atribuir a você e encerrar?"** — num clique, a conversa é atribuída a ele e encerrada no mesmo gesto.

**Objetivo:** garantir responsabilidade clara pelo encerramento (quem fechou, assumiu) e evitar que conversas sejam encerradas "por engano" por quem não estava atendendo.

**Por que é rápido de fazer:** ~80% da fundação já existe — foi construída no gate de resposta (mesmo modal, mesma flag de modo, mesmo padrão de bloqueio no backend). Aqui é espelhar para a ação de "encerrar".

---

## 🎯 Escopo

**Inclui**
- Bloquear o encerramento quando a conversa não está atribuída a quem encerra.
- Modal para atribuir a si (com as variantes: sem dono / de um colega / da IA / fora do time → escolhe um time).
- Ao confirmar: atribui e encerra em sequência (o encerramento nunca se perde).
- Validação no backend (não dá pra burlar pela API), não só na tela.
- Cobrir todos os pontos onde se encerra: botão do cabeçalho, menu de contexto e ações em massa.

**Não inclui**
- Reabrir / soneca / pendente (só o "encerrar").
- Mudança quando o modo "Atribuição obrigatória" está **desligado** (aí continua tudo como hoje).

---

## ✅ Decisões a confirmar (3)

| # | Decisão | Recomendação |
|---|---|---|
| 1 | Usar a **mesma chave** do "modo Atribuição obrigatória" (liga resposta + encerramento juntos) ou uma chave separada só pro encerramento? | **Mesma** (coerência: se não responde sem ser dono, não encerra sem ser dono) |
| 2 | **Admin** também passa pelo modal? | **Sim, sem exceção** (igual ao gate de resposta) |
| 3 | **Encerrar em massa** conversas que não são suas → atribuir a você + encerrar todas (com 1 confirmação), pular as que não são suas, ou bloquear? | **Atribuir + encerrar com confirmação** |

---

## ⏱️ Esforço e entrega

- **Tamanho:** pequeno/médio (reaproveita o que já existe).
- **Estimativa:** ~1 a 1,5 dia de dev + validação.
- **Ambiente:** desenvolvido e testado em homologação (sandbox SimplexIA, conta de teste). Nada vai pra cliente sem validação.
- **Validação obrigatória:** testes automatizados + Playwright (tema claro e escuro) antes de considerar pronto.

---

## ⚠️ Riscos (controlados)

- **Não quebrar automações** que encerram sozinhas (SLA, mensagens agendadas, macros) → essas têm exceção, o bloqueio é só pra ação manual de pessoa.
- **Encerrar exige time** (regra que já existe) → o modal já cuida de pedir o time quando precisa.
- **Acoplar resposta + encerramento** na mesma chave → aceito por coerência; dá pra separar depois se incomodar.

---
---

# 🔧 Anexo técnico (para quem vai implementar)

> Fork Chatwoot (Rails + Vue 3). Working tree only — nada commitado até validar. Modo econômico (sem multi-agente).

## Decisões (detalhe)

| # | Decisão | Resolução |
|---|---|---|
| R-1 | Regra central | Encerrar (`status = resolved`) exige `conversation.assignee_id == current_user.id` |
| R-2 | UX ao bloquear | Modal "Atribuir a você e encerrar?" — 4 variantes (sem dono / de colega / da IA / fora do time) |
| R-3 | Flag/Modo | Reusar `reply_assignment_gate` (modo "Atribuição obrigatória"). Alt.: `resolve_assignment_gate` separada |
| R-4 | Escopo | Só `resolved`. Reopen já auto-atribui (`toggle_status_service.rb` `should_assign_conversation?`) |
| R-5 | Admin | Sem exceção (consistente com gate de resposta) |
| R-6 | Guard | Fonte da verdade no `ToggleStatusService` (espelha `validate_team_requirement!`) → 422 `resolve_assignment_required` |
| R-7 | Automação/macro/bot | Bypass — só ação direta de humano é barrada |
| R-8 | Bulk | Atribuir+encerrar com confirm (a decidir) |
| R-9 | Conversa da IA | Modal "Assumir da {IA} e encerrar?" → self-assign solta o espelho (callback de exclusividade) |
| R-10 | Modo Clássico | Flag desligada → comportamento atual intacto |

## Base que já existe (reaproveitar)

| Peça | Onde |
|---|---|
| Serviço de encerrar | `app/services/conversations/toggle_status_service.rb` (`perform`, `validate_team_requirement!`, `should_assign_conversation?`) |
| Endpoint | `app/controllers/api/v1/accounts/conversations_controller.rb#toggle_status` |
| Padrão do guard 422 (gate de resposta) | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:222-229` (`render_assignment_required`, `error_code: 'assignment_required'`) |
| Flag/modo | `app/javascript/dashboard/composables/useReplyAssignmentGate.js` + toggle `.../settings/account/components/AttendanceModeToggle.vue` (`account.settings.reply_assignment_gate`) |
| **Modal a reaproveitar** | `app/javascript/dashboard/components-next/Conversation/AssignToReplyDialog.vue` — generalizar com `action: 'reply' | 'resolve'` |
| Botão Resolver | `app/javascript/dashboard/components/buttons/ResolveAction.vue` (`toggleStatus`, `onCmdResolveConversation`; já tem precedente de modal antes de resolver) |
| Outras superfícies | `contextMenu/Index.vue`, `conversationBulkActions/UpdateActions.vue` + `Index.vue`, atalho de teclado, macros |
| Notificar dono anterior | NotificationService `conversation_assignment` |

## Fases

### Fase 1 — Backend (guard, fonte da verdade)
- **1.1** `validate_assignment!` no `ToggleStatusService`: se `params[:status]=='resolved'` E flag ligada E `@user.is_a?(User)` E `@conversation.assignee_id != @user.id` → `raise ResolveAssignmentRequiredError`. Bypass automação/macro/bot.
- **1.2** Capturar no controller → **422** `resolve_assignment_required` + metadados (dono atual, time).
- **1.3** i18n pt_BR + en (`conversations.resolve_assignment_gate.assignment_required`).
- **1.4** Aplicar no caminho de bulk resolve (R-8).

### Fase 2 — Frontend (modal + interceptação)
- **2.1** Generalizar `AssignToReplyDialog.vue` com `action: 'reply' | 'resolve'` (texto/CTA "…e encerrar" + callback atribui→encerra).
- **2.2** Interceptar o Resolver no `ResolveAction.vue`: flag ligada + não-dono → abre o modal; ao confirmar, atribui (time+self) e encerra.
- **2.3** Cobrir context menu e ações em massa.
- **2.4** Tratar 422 como fallback (corrida: dono mudou → reabre o modal atualizado).
- **2.5** Notificar dono anterior quando colega assume.
- **2.6** i18n pt_BR + en das strings novas (zero hardcode).

## Testes (obrigatório antes do aceite)

**Specs (Rails + Vitest)**
- Backend: dono encerra (ok); não-dono com flag (422); admin não-dono (422); automação/macro/bot (bypass); flag desligada (atual); resolve sem time ainda exige time; bulk (R-8).
- Frontend: dialog variante `resolve` (4 variantes); `ResolveAction` abre modal quando não-dono / encerra direto quando dono; paridade i18n.

**Playwright (claro + escuro, conta 3, usuário de teste dedicado — nunca senha real)**
| # | Cenário | Esperado |
|---|---|---|
| PR1 | Dono resolve | encerra direto, sem modal |
| PR2 | Não-dono (do time) resolve | modal "Atribuir a você e encerrar?" → confirma → encerrada e atribuída |
| PR3 | Conversa de colega | modal "Assumir de {nome} e encerrar?" → encerra; colega notificado |
| PR4 | Conversa da IA | modal "Assumir da {IA} e encerrar?" → espelho solto → encerrada |
| PR5 | Admin/fora do time | modal mostra os times do usuário → escolhe → atribui+encerra |
| PR6 | Modo Clássico (flag off) | encerra direto, sem modal |
| PR7 | DOM walker | sem i18n vazada, ícones ok, contraste ok, 0 erros de console, 2 temas |

**E2E (sandbox conta 3)**
- Conversa de outro → resolver → modal → assumir → encerrar → status `resolved` + `assignee_id` = usuário.
- Corrida: 2 agentes resolvem a mesma → o segundo recebe 422 + modal atualizado.
- Bulk com mix (suas + de outros) → conforme R-8.

## Encaixe
Feature irmã da Fase D do plano "IA como atendente + gate universal" (`plano/ia-consolidado.md`). Reusa flag, modal, guard 422 e notificação. Pode entrar como "Fase D-bis", logo após a revisão humana da Fase D.
