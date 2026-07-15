# Sino: notificar SÓ o último atribuído (não todos os participantes)

> **Documento único desta tarefa.** Branch `nicolas`. **Sem migration. Sem feature flag.**
> O fix é de **~3 linhas**; o resto é teste e limpeza de histórico.
> Substitui `task/notificacoes-sino-vazando-times.md` (removido — vive no histórico do git,
> commits `f735723e5` e `adbb115e5`; o resumo do que ele resolvia está no **§8**).

---

## 1. A regra

> "Quando o cliente manda mensagem nova, só deve notificar **quem estava atribuído no momento em que
> a conversa foi finalizada/resolvida** (o último atribuído). Hoje notifica **todos** que participaram."

**Regra canônica:** notificar U sobre mensagem nova em C ⟺ **`U == C.assignee`**. Ponto final.

**Sintoma (print do dono):** conversa *Em atendimento*, **atribuída à Misya Correa**, time `pos-venda`.
O dono é apenas participante ("Você está participando") e **mesmo assim levou sino**.

---

## 2. 🎯 Veredito: `conversation.assignee` JÁ É "o último atribuído no resolve"

**Não precisa de migration. Não precisa consultar `conversation_assignment_histories`.** Verificado no código:

| Pergunta | Resposta | Evidência |
|---|---|---|
| Resolver limpa o assignee? | **Não**, persiste. Só zera `waiting_since`. | `conversation.rb:202-207`, `:312-319`. Não existe coluna `resolved_at`. |
| Mensagem nova reabre a conversa resolvida? | **Sim**, só p/ `incoming?`; não reabre se mutada, contato bloqueado ou resposta a NPS ativo. | `message.rb:449-458` |
| A reabertura pode **trocar** o assignee? | **Não, no caso normal.** O round-robin só roda se `assignee.blank?` **ou** o assignee perdeu acesso ao inbox. | `auto_assignment_handler.rb:14,49-50` |
| Assignment **V2** rouba conversa já atribuída? | **Não** — só `unassigned_conversations`. | `auto_assignment/assignment_service.rb:4-15,30-32` |
| O sino lê o assignee **depois** da reabertura? | **Sim.** Ordem explícita: `reopen_conversation` roda **antes** de `dispatch_create_events`. | `message.rb:346-352` (comentário cita rails/rails#20911) |

➡️ **Notificar `conversation.assignee` == notificar "quem estava atribuído quando resolveu".**
O caminho `notify_conversation_assignee` (`new_message_notification_service.rb:15-28`) **já faz isso hoje**.
**O trabalho é só parar de notificar o resto.**

> ⚠️ **NÃO troque `conversation.assignee` por consulta ao histórico.** Além de desnecessário, o
> `VisibilityService` **reprovaria** o destinatário lido do histórico (ele exige inbox+time) e a regra
> nasceria quebrada.

---

## 3. Decisões travadas com o dono

| # | Pergunta | **Decisão** | Consequência aceita |
|---|---|---|---|
| **D1** | Participante adicionado **à mão** (aba "Participantes da conversa") recebe sino de msg nova? | **NÃO. Mata os 3 caminhos.** Só o atribuído recebe. | A aba "Participantes" vira **informativa**. Sem migration. |
| **D2** | Conversa **sem assignee** + msg nova → quem recebe? | **Ninguém. Silêncio aceito.** | Cobrem a **lista de "Não atribuídas"** + `orphan_retriage_job` / `queue_escalation_job` (já alertam admin). |
| **D3** | **@menção** continua notificando? | **SIM, a menção em si** (tipo 4, intocada). | As **mensagens seguintes** ao mencionado **param** — consequência de D1. |
| **D4** | **Admin** é exceção? | **NÃO.** Só recebe se for o assignee. | É o pedido: o dono é admin e quer **menos** ruído. |
| **D5** | Paramos de **criar** participante automático? | **NÃO.** `ParticipationListener` segue gravando. | Preserva a aba e o histórico. **Reversível**: se um dia quiserem notificar participantes, o dado está lá. |

**Por que D1 mata os 3 de uma vez:** existem 3 criadores de participante — automático
(`participation_listener.rb:8`), @menção (`mention_service.rb:69`) e manual
(`participants_controller.rb:8,14`) — e a tabela **não tem coluna que os distinga**. Separar exigiria
migration; o dono optou por não fazer.

---

## 4. O FIX (F1) — ~3 linhas

`app/services/messages/new_message_notification_service.rb`: **remover a chamada
`notify_participating_users`** de `perform`, junto com o método e o guard de visibilidade que fica
órfão. Manter `notify_conversation_assignee` **intocado**.

```ruby
def perform
  return unless message.notifiable?

  notify_conversation_assignee   # único caminho: o último atribuído
end
```
- `already_notified?` / `mark_notified` **continuam** (a correção do sino duplicado, commit `967cad55d`).
- **Não** apagar `conversation_participants` (D5).

**Specs** (`spec/services/messages/new_message_notification_service_spec.rb`):
🆕 *"não notifica participante que não é o assignee"* · 🆕 *"não notifica admin participante"* ·
🆕 *"notifica só o assignee"* · 🆕 *"conversa sem assignee não notifica ninguém"* (D2) ·
🆕 *"após reabrir conversa resolvida, notifica quem estava atribuído"* (trava a ordem, armadilha 5).

⚠️ Os exemplos atuais que esperam tipo 5 **vão quebrar — é o objetivo**. Reescrever, não remendar.

✅ `bundle exec rspec spec/services/messages spec/listeners spec/mailers/agent_notifications`

---

## 5. ⚠️ Armadilhas (verificadas no código real)

1. **NUNCA mover o guard para dentro do `NotificationBuilder`.** Mata a **menção cross-team**
   (`mention_service.rb:40-45` monta audiência sem filtro **de propósito**). Os specs **não pegariam**:
   `mention_service_spec.rb:22` troca o builder por um double. A **única** trava é o spec com builder
   REAL (commit `6f2d7183a`) — **não apagar**.
2. **Não remover o guard do `sla_event.rb`** "por simetria". Depois deste fix, o SLA passa a ser o
   **único** lugar que ainda itera a participação eterna (tipos 6/7/8).
3. **Não renumerar `NOTIFICATION_TYPES`** (`notification.rb:38-52`) — bits FlagShihTzu. O tipo 5 fica
   **aposentado**, não sai do enum.
4. **Há um e-mail amarrado ao tipo 5** (`spec/mailers/agent_notifications/conversation_notifications_mailer_spec.rb`).
   Parar de criar o tipo 5 **também mata esse e-mail** — é desejado, mas confira os specs do mailer.
5. **Ordem de callbacks é aliada, mas frágil** (`message.rb:346-352`). Se alguém reordenar, o sino passa
   a ler o assignee **pré-reabertura**. → **spec que trava a ordem**.
6. **Borda NÃO resolvida por este fix:** assignee que **saiu do inbox** continua sendo o único
   notificado (o round-robin só o substitui se houver agente **online**; `agent_assignment_service.rb:15,19-31`).
   O `VisibilityService` não pega (retorna `true` por `assignee_id`). → §7.

---

## 6. Mapa: quem cria notificação hoje

| Call site | Audiência | Depois deste fix |
|---|---|---|
| `new_message_notification_service.rb:15-28` (assignee) | só o assignee | ✅ **vira o único caminho** — não mexer |
| `new_message_notification_service.rb:30+` (participantes) | todos os participantes | 🔴 **REMOVER (F1)** |
| `notification_listener.rb` (`notify_inbox_members`) | membros do inbox, tipo 1 | ✅ já escopado por time — não mexer |
| `enterprise/app/models/sla_event.rb` | participantes + admins + assignee | ✅ já escopado (só participantes) — **não remover** (armadilha 2) |
| `mention_service.rb:57` | só os @mencionados | ✅ **PROIBIDO mexer** (D3) |
| `notification_listener.rb` (`assignee_changed`, `notify_previous_assignee`) | assignee / ex-assignee | ✅ não mexer |
| `orphan_retriage_job.rb:73`, `queue_escalation_job.rb:93` | só admins | ✅ não mexer (D2 depende deles) |

**Não mexer:** `notification_builder.rb` (armadilha 1) · `notification_finder.rb` /
`notifications_controller.rb` (leitura já escopada por `user_id`) · `action_cable_listener.rb`
(broadcast já é 1:1) · front (`InboxList.vue`/`InboxCard.vue` — o fix é **não criar a linha**;
filtrar no front seria maquiagem) · `db/` (sem migration) · feature flags (bitmask no teto de 63 bits).

---

## 7. Fases restantes

### F2 — Limpeza do histórico
O sino do dono tem **42 tipo-5 antigos**; sem limpar, ele abre e diz que não funcionou.
Atualizar `task/notificacoes_vazadas_cleanup.rb`:
- **tipo 5** → apagar **todos** (tipo aposentado; nenhum é mais legítimo);
- **tipos 1, 6, 7, 8** → manter a regra `visible_to?` atual (seguem governados pelo time);
- **tipos 2, 3, 4, 9, 10** → **continuam de fora** (assignee / menção / órfã / unassignment).

`--dry-run` é default. Rodar **na conta do dono** e revisar antes do `--apply`.

### F3 — Deferidos (tarefa própria)
- Assignee que saiu do inbox segue notificado (armadilha 6).
- Automação em `conversation_opened` roda **async, depois** da notificação: se o cliente usa automação
  que reatribui na reabertura, o sino vai pro assignee antigo (`automation_rule_listener.rb:10-12`).
- **🔴 P11 (mais grave que este bug):** `conversations/base_controller.rb:8` só faz `authorize :show?`,
  **sem** `authorize_team_access` → `GET conversations/:id` dá **403** mas `GET .../messages` devolve
  **200 com o conteúdo do outro time**. Herdam: messages, labels, assignments, participants, reactions,
  funnel_items, copilot_chats.

---

## 8. Estado atual: o que já está commitado (e por que continua valendo)

6 commits em `nicolas` (`967cad55d..adbb115e5`), specs verdes, staging LIVE, E2E ALL GREEN.
Eles resolvem um problema **real e diferente**: agente de **outro time** recebendo sino de conversa
que não acha na lista e que dá 403 ao abrir.

**Franqueza:** esse fix **não resolve a queixa do dono** — ele é **admin**, e a regra isenta admin de
propósito. Medido na conta #1: **42 das 47** notificações tipo-5 são do admin e **todas passam
legitimamente** → a limpeza acha **0 vazadas**. Para admin não existe a incoerência 403/lista (ele vê
tudo): a queixa dele é **ruído** de participação eterna — o que a F1 acima resolve.

| Commit | O quê | Destino nesta tarefa |
|---|---|---|
| `967cad55d` | sino **duplicado** (`mark_notified`) — bug pré-existente | **MANTER** |
| `43d32f603` | `Conversations::VisibilityService` + spec | **MANTER** (governa tipos 1 e 6/7/8) |
| `71039a6d0` | guard em `notify_participating_users` | 🔴 **morre na F1** junto com o método |
| `6f2d7183a` | guards `notify_inbox_members` + `sla_event`; spec de menção com builder REAL | **MANTER** (armadilhas 1 e 2) |
| `9d5e11236` | scripts: `sino_fase0_diagnostico.rb`, `sino_e2e.rb`, `notificacoes_vazadas_cleanup.rb` | **ADAPTAR** (E2E: trocar asserts p/ "só o assignee"; cleanup: ver F2) |
| `adbb115e5` | docs | este arquivo |

**Dados medidos (conta #1 do staging, read-only):** 47 tipo-5 (84% do volume) · 5 tipo-3 · 4 tipo-2 ·
**0** tipo-1 (`notify_inbox_members` está inerte: 0 de 18 com opt-in) · 0 custom roles ·
52/58 conversas com time · o admin é participante de **49** conversas.

---

## 9. Checklist

- [x] Regra definida; decisões D1–D5 travadas.
- [x] Verificado que `conversation.assignee` sobrevive ao resolve→reabrir (§2).
- [x] **F1:** remover `notify_participating_users`; specs reescritos verdes. → commit `6d741efec`
- [x] Spec que trava a ordem `reopen_conversation` → `dispatch_create_events` (armadilha 5).
- [x] `bundle exec rubocop` nos arquivos tocados. (0 offenses)
- [x] **F2:** script atualizado; dry-run rodado na conta #1. → **falta o `--apply` (decisão do dono)**
- [x] Validar no staging (`task/sino_e2e.rb` adaptado): **E2E ALL GREEN** — admin participante não
      recebe · assignee recebe · conversa sem assignee → ninguém · @menção ainda notifica cross-team.
- [x] Restart do staging.
- [ ] **Pendente do dono:** revisar o dry-run (abaixo) e autorizar o `--apply`.
- [ ] **Pendente do dono:** QA visual no sino do staging.

### Baseline de specs (medido, não presumido)

`bundle exec rspec spec/services/messages spec/listeners spec/mailers/agent_notifications`
→ **25 falhas idênticas ANTES e DEPOIS** deste fix (diff vazio contra um worktree em HEAD limpo).
Nenhuma é deste trabalho — são de ambiente/fork: `SMTP From address may not be blank` (mailers),
assinatura do `HookJob` (`hook_listener_spec`) e expectativas estritas de dispatcher
(`pin_service_spec`, `action_cable_listener_spec`, `reporting_event_listener_spec`).
Os specs do escopo (`new_message_notification_service`, `mention_service`, `visibility_service`,
`notification_listener`) estão **74 exemplos, 0 falhas**.

### Dry-run da F2 na conta #1 (staging, read-only) — para o dono revisar

    (A) APOSENTADO participating_conversation_new_message: 47  -> apaga todas
    (B) governados pelo time (creation/sla_*):              0  -> nada a avaliar
    A APAGAR: 47   | user #1 (admin): 42 · user #5 (Cibely Oliveira): 4 · user #10 (Agente Teste A): 1

Confirma o §8: as 42 do admin **passam** em `visible_to?` (ele está no time da conversa — ex.:
`conv.team=5`, `user.teams=[2,5]`), por isso a regra antiga achava **0**. Agora o critério é o
**tipo aposentado**, não a visibilidade. Rodar quando o dono aprovar:

    RAILS_ENV=production bundle exec rails runner task/notificacoes_vazadas_cleanup.rb -- --account=1 --apply
