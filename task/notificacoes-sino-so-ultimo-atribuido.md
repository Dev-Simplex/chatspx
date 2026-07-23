# Sino: notificar SÓ o último atribuído (não todos os participantes)

> **Substitui o alvo de** `task/notificacoes-sino-vazando-times.md`. Aquele documento resolve
> **"não vazar conversa de outro time"**. Esta tarefa é outra: **"mensagem nova só notifica quem
> estava atribuído"**. Parte do trabalho de lá continua válida — ver §6.
>
> Branch `nicolas`. **Sem migration. Sem feature flag.** Fix de **~3 linhas** + limpeza de histórico.

---

## 1. A regra (definida pelo dono em 2026-07-15)

> "Quando o cliente manda mensagem nova, só deve notificar **quem estava atribuído no momento em que
> a conversa foi finalizada/resolvida** (o último atribuído). Hoje notifica **todos** que participaram."

**Regra canônica nova:** notificar U sobre mensagem nova em C ⟺ **`U == C.assignee`**. Ponto final.

Evidência do sintoma (print do dono): conversa *Em atendimento*, **atribuída à Misya Correa**, time
`pos-venda`; o dono é apenas participante ("Você está participando") e **mesmo assim levou sino**.

---

## 2. 🎯 Veredito técnico: `conversation.assignee` JÁ É "o último atribuído no resolve"

**Não precisa de migration. Não precisa consultar `conversation_assignment_histories`.** Verificado:

| Pergunta | Resposta | Evidência |
|---|---|---|
| Resolver limpa o assignee? | **Não**, persiste. Só zera `waiting_since`. | `conversation.rb:202-207`, `:312-319`. Não existe coluna `resolved_at`. |
| Mensagem nova reabre a conversa resolvida? | **Sim**, só p/ `incoming?`; não reabre se mutada, contato bloqueado ou resposta a NPS ativo. | `message.rb:449-458` |
| A reabertura pode **trocar** o assignee? | **Não, no caso normal.** O round-robin só roda se `assignee.blank?` **ou** o assignee perdeu acesso ao inbox. | `auto_assignment_handler.rb:14,49-50` |
| Assignment **V2** rouba conversa já atribuída? | **Não** — só `unassigned_conversations`. | `auto_assignment/assignment_service.rb:4-15,30-32` |
| O sino lê o assignee **depois** da reabertura? | **Sim.** A ordem é explícita: `reopen_conversation` roda **antes** de `dispatch_create_events`. | `message.rb:346-352` (comentário cita rails/rails#20911) |

➡️ **Logo: notificar `conversation.assignee` == notificar "quem estava atribuído quando resolveu".**
O caminho `notify_conversation_assignee` (`new_message_notification_service.rb:15-28`) **já faz isso hoje**.
**O trabalho é só parar de notificar o resto.**

⚠️ **NÃO troque `conversation.assignee` por consulta ao histórico.** Além de desnecessário, o
`VisibilityService` (se mantido no caminho) **reprovaria** o destinatário lido do histórico, e a
regra nasceria quebrada. (Risco levantado e confirmado pelo squad.)

---

## 3. Decisões de produto — TRAVADAS pelo dono

| # | Pergunta | **Decisão** | Consequência aceita |
|---|---|---|---|
| **D1** | Participante adicionado **à mão** (aba "Participantes da conversa") recebe sino de msg nova? | **NÃO. Mata os 3 caminhos.** Só o atribuído recebe. | A aba "Participantes" vira **informativa**: mostra quem passou pela conversa, mas não notifica. Sem migration. |
| **D2** | Conversa **sem assignee** + msg nova → quem recebe? | **Ninguém. Silêncio aceito.** | Quem cobre é a **lista de "Não atribuídas"** + `orphan_retriage_job` / `queue_escalation_job` (que já alertam admin hoje). |
| **D3** | **@menção** continua notificando? | **SIM, a menção em si** (tipo 4, intocada). | As **mensagens seguintes** ao mencionado **param** — consequência direta de D1. |
| **D4** | **Admin** é exceção? | **NÃO.** Admin só recebe se for o assignee. | É exatamente o pedido: o dono é admin e quer **menos** ruído. O `VisibilityService` isenta admin — por isso ele **não serve** para este fix. |
| **D5** | Paramos de **criar** participante automático? | **NÃO** (não escolhido). `ParticipationListener` segue gravando. | Preserva a aba de participantes e o histórico. **Reversível**: se um dia quiserem notificar participantes de novo, o dado está lá. |

---

## 4. ⚠️ Armadilhas (verificadas no código real)

1. **NUNCA mover o guard para dentro do `NotificationBuilder`.** Mata a **menção cross-team**
   (`mention_service.rb:40-45` monta audiência sem filtro **de propósito**). E os specs **não pegariam**:
   `mention_service_spec.rb:22` troca o builder por um double. A **única** trava é o spec novo com
   builder REAL (já escrito) — **não apagar**.
2. **Não remover o guard do `sla_event.rb`** "por simetria". Depois deste fix, o SLA passa a ser o
   **único** lugar que ainda itera a participação eterna (tipos 6/7/8). Remover reabre o vazamento
   por outra porta.
3. **Não renumerar `NOTIFICATION_TYPES`** (`notification.rb:38-52`) — bits FlagShihTzu. O tipo 5
   fica **aposentado**, não deletado do enum.
4. **Há um e-mail amarrado ao tipo 5** (`spec/mailers/agent_notifications/conversation_notifications_mailer_spec.rb`).
   Parar de criar o tipo 5 **também apaga esse e-mail** — é desejado, mas confira os specs do mailer.
5. **Ordem de callbacks é aliada, mas frágil** (`message.rb:346-352`). Se alguém reordenar, o sino
   passa a ler o assignee **pré-reabertura**. → **spec que trava a ordem**.
6. **Borda conhecida, NÃO resolvida por este fix:** assignee que **saiu do inbox** continua sendo o
   único notificado (o round-robin só o substitui se houver agente **online**;
   `agent_assignment_service.rb:15,19-31`). O `VisibilityService` **não pega** isso (`visible_to?`
   devolve `true` por `assignee_id`). → Fase 5.

---

## 5. Fases

### F1 — O FIX (~3 linhas) ⟵ resolve o que o dono vê
`app/services/messages/new_message_notification_service.rb`: **remover a chamada
`notify_participating_users`** de `perform` (e o método + o guard de visibilidade que ficou órfão).
Manter `notify_conversation_assignee` **intocado**.

```ruby
def perform
  return unless message.notifiable?

  notify_conversation_assignee   # único caminho: o último atribuído
end
```
- `already_notified?` / `mark_notified` **continuam** (a correção do sino duplicado segue valendo).
- **Não** apagar `conversation_participants` (D5).

**Specs:** reescrever `spec/services/messages/new_message_notification_service_spec.rb` —
🆕 *"não notifica participante que não é o assignee"* · 🆕 *"não notifica admin participante"* ·
🆕 *"notifica só o assignee"* · 🆕 *"conversa sem assignee não notifica ninguém"* (D2) ·
🆕 *"após reabrir conversa resolvida, notifica quem estava atribuído"* (trava a ordem, armadilha 5).
⚠️ Os exemplos atuais que esperam tipo 5 **vão quebrar — é o objetivo**; reescrever, não remendar.

✅ `bundle exec rspec spec/services/messages spec/listeners spec/mailers/agent_notifications`

### F2 — Limpeza do histórico
O sino do dono tem **42 tipo-5 antigos**; sem limpar, ele abre e diz que não funcionou.
Atualizar `task/notificacoes_vazadas_cleanup.rb`:
- **tipo 5** → apagar **todos** (o tipo está aposentado; nenhum é mais legítimo);
- **tipos 1, 6, 7, 8** → manter a regra `visible_to?` atual (continuam governados pelo time);
- **tipos 2, 3, 4, 9, 10** → **continuam de fora** (assignee/menção/órfã/unassignment).
`--dry-run` é default. Rodar na conta do dono e revisar antes do `--apply`.

### F3 — Manter o que já está feito (não jogar fora)
Ver §6. Sem código novo.

### F4 — Deferidos (tarefa própria)
- Assignee que saiu do inbox segue notificado (armadilha 6).
- Automação em `conversation_opened` roda **async, depois** da notificação: se o cliente usa
  automação que reatribui na reabertura, o sino vai pro assignee antigo (`automation_rule_listener.rb:10-12`).
- **🔴 P11 (mais grave que este bug):** `conversations/base_controller.rb:8` só faz `authorize :show?`,
  sem `authorize_team_access` → `GET conversations/:id` dá **403** mas `GET .../messages` devolve
  **200 com o conteúdo do outro time**. Herdam: messages, labels, participants, funnel_items…

---

## 6. O que fazer com o trabalho já implementado (não commitado)

| Peça | Destino | Porquê |
|---|---|---|
| `app/services/conversations/visibility_service.rb` + spec | **MANTER** | Ainda governa `notify_inbox_members` (tipo 1) e `sla_event` (6/7/8), que esta tarefa **não toca**. |
| Guard em `notify_inbox_members` (`notification_listener.rb`) | **MANTER** | Tipo 1 continua existindo. |
| Guard em `sla_event.rb` | **MANTER** | Vira o **único** ponto que ainda itera participação eterna (armadilha 2). |
| Spec de regressão de menção (builder REAL) | **MANTER** | Única trava contra matar a menção cross-team. |
| Guard em `notify_participating_users` | **REMOVER junto com o método** | Vira **órfão** — o loop inteiro morre. |
| `mark_notified` (sino duplicado) | **MANTER** | Bug real, pré-existente, já corrigido. |
| Comentário cruzado em `permission_filter_service.rb` | **MANTER** | Continua verdade para os tipos 1/6/7/8. |
| `task/sino_e2e.rb` | **ADAPTAR** | Trocar os asserts: hoje valida a regra de time; passa a validar "só o assignee". |

**Franqueza:** o fix de time **não resolvia a queixa do dono** (ele é admin, e o `VisibilityService`
isenta admin). Ele fecha um vazamento **real e diferente** — vale manter, mas não é o que estava sendo pedido.

---

## 7. Checklist

- [x] Regra definida e decisões D1–D5 travadas com o dono.
- [x] Verificado que `conversation.assignee` sobrevive ao resolve→reabrir (§2).
- [ ] F1: remover `notify_participating_users`; specs reescritos verdes.
- [ ] Spec que trava a ordem `reopen_conversation` → `dispatch_create_events`.
- [ ] `bundle exec rubocop` nos arquivos tocados.
- [ ] F2: script atualizado; **dry-run revisado com o dono** → `--apply`.
- [ ] Validar no staging (`task/sino_e2e.rb` adaptado): admin participante **não** recebe; assignee recebe;
      conversa sem assignee → ninguém; @menção ainda notifica.
- [ ] Restart: `sudo /bin/systemctl restart chatwoot.target` (unidades reais: `chatwoot-web.1`, `chatwoot-worker.1`).
- [ ] Commit (só quando o dono pedir).
