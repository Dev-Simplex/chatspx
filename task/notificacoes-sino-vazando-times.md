# Notificações: sino (Caixa de Entrada) mostrando conversas de outros times/usuários

> **Prompt de implementação** — branch `nicolas`, **sem migration**, **sem feature flag** (ver Decisão P8).
> Fix cirúrgico: **1 service novo (~30 linhas) + 3 call sites de audiência**. Todo o resto é teste,
> pré-checagem e limpeza de histórico.
>
> **Leia antes de codar:** `app/services/conversations/permission_filter_service.rb:18-25`,
> `app/services/messages/new_message_notification_service.rb:29-44` e a **§2 (Armadilhas)** — há 4
> armadilhas que **matam notificação legítima** se ignoradas.
>
> **Origem:** análise multi-agente (22 agentes, 4 lentes + verificação adversarial; 15 causas-raiz
> confirmadas). **Cuidado com a intuição:** o suspeito óbvio (`notify_inbox_members`, que notifica todo
> membro do inbox) está **INERTE hoje** — corrigir só ele **não muda nada** do que o dono vê. A causa
> real é a **participação eterna** (§1, vetor nº1).
>
> **Dados medidos no staging (conta #1, read-only, reconferidos pelo orquestrador em 2026-07-14):**
> | Medição | Valor |
> |---|---|
> | `participating_conversation_new_message` (tipo 5) | **47** ← 84% do volume |
> | `assigned_conversation_new_message` / `conversation_assignment` | 5 / 4 |
> | `conversation_creation` (tipo 1) | **0** |
> | `notification_settings` com opt-in de "Nova conversa" | **0 de 18** (todos `email_flags=2, push_flags=2`) |
> | Conversas com participante / com 2+ participantes | 54 / **5** (máx 2) → acúmulo real |
>
> Refaça a medição **na conta onde o bug foi reportado** antes de codar (**Fase 0**).

---

## 1. Objetivo e diagnóstico (o que realmente está quebrado)

O fork tem **duas superfícies de visibilidade que discordam**:

| Superfície | Regra real | Arquivo |
|---|---|---|
| **LISTA** de conversas | membro do inbox **E** (`team_id ∈ meus times` **OU** `team_id IS NULL`); agente **sem time** → sem filtro de time | `app/services/conversations/permission_filter_service.rb:19-24` |
| **GET conversations/:id** | 403 se `team_id` presente **E** não-admin **E** não-assignee **E** não-membro do time | `app/controllers/api/v1/accounts/conversations_controller.rb:246-260` |
| **SINO** | **nenhuma regra** — a audiência é escolhida sem consultar time, atribuição ou policy | `app/services/messages/new_message_notification_service.rb:30`, `app/listeners/notification_listener.rb:92-101` |

**O sino é a única superfície do produto sem equivalente do `PermissionFilterService`.** É exatamente isso que o dono está vendo: um índice de conversas que ele **não acha na lista** e que, ao clicar, dá **403**.

### Vetor nº1 confirmado (o que gera o volume) — participação eterna

1. `app/listeners/participation_listener.rb:8` — `find_or_create_by!(user_id: conversation.assignee_id)` a cada `assignee_changed`. **Nunca remove o assignee anterior.** O conjunto só cresce (grep confirmou: participante só sai por API manual em `participants_controller.rb:15,23` ou `app/jobs/agents/destroy_job.rb:51`).
2. `app/services/messages/new_message_notification_service.rb:29-44` — `notify_participating_users` itera **todos** os `conversation_participants`, sem olhar time, sem olhar se ainda é assignee. Únicas exclusões: o sender (`:31`) e dedup por mensagem (`:34`).
3. `app/builders/notification_builder.rb:27` — o gate de preferências é literalmente **só** `conversation_creation`. Logo a linha em `notifications` é **sempre** criada e o agente **não tem toggle nenhum** para desligar esse ruído.
4. Resultado: João (time Vendas) é atribuído → vira participante. Conversa é reatribuída ao time Suporte/Maria (`AssignmentHandler` troca assignee **e** time) → **João continua participante para sempre** e recebe sino de **toda mensagem nova** de uma conversa que sumiu da lista dele e retorna 403 se ele abrir.

**Dados do staging (medidos, read-only):** `notifications` por tipo → **`5` (participating_conversation_new_message) = 47, `3` = 5, `2` = 4, `1` (conversation_creation) = 0**. 84% do volume vem do caminho de participantes.

### Vetor nº2 — `notify_inbox_members` (o suspeito do scout): **INERTE hoje**

`app/listeners/notification_listener.rb:92-101` notifica **todo membro do inbox** sem olhar time — real, off-model. **Mas** `notification_builder.rb:27` exige opt-in em `conversation_creation`, e `app/models/account_user.rb:46-51` **não liga esse bit por padrão**. Medido no staging: **18/18 notification_settings com `email_flags=2, push_flags=2`; zero opt-in; zero notificação tipo 1 já criada.**
👉 **Consequência para a expectativa do dono:** corrigir só `notify_inbox_members` **não mudaria nada do que ele vê**. É bomba armada, não é a causa. Corrigimos junto (barato), mas na Fase 3, não na 2.

### Vetor nº3 — obsolescência (`team_changed`)
Não existe handler `team_changed` no `NotificationListener` (só `conversation_bot_handoff:2`, `conversation_created:9`, `assignee_changed:16`, `message_created:40`). Notificação nasce válida (`team_id` nil) e **nunca é reavaliada** quando a triagem move a conversa. `app/jobs/notification/delete_notification_job.rb` só sabe `all`/`read`. Isso é o **histórico sujo** → Fase 4.

---

## 2. ⚠️ Armadilhas que quebram a feature (verificadas no código real)

1. **NUNCA aplicar o escopo dentro do `NotificationBuilder`** (`app/builders/notification_builder.rb:25-38`). É o choke point tentador dos 8 call sites — e mataria a **menção cross-team**, que é **deliberada**: `app/services/messages/mention_service.rb:40-45` monta `administrators + inbox.members` **sem filtro de time**, de propósito (menção é consentimento explícito). **Pior:** os specs **não pegariam** essa regressão — `spec/services/messages/mention_service_spec.rb:22` faz `allow(NotificationBuilder).to receive(:new).and_return(builder)` (o builder é um double, o `build_notification` real nunca roda), e `spec/builders/notification_builder_spec.rb` usa conversa **sem time**. Regressão **silenciosa**. → **Escopar na SELEÇÃO DE AUDIÊNCIA**, nunca no builder.
2. **`OR team_id IS NULL` não é opcional** (`permission_filter_service.rb:21`, travado por `spec/services/conversations/permission_filter_service_spec.rb:60,68`). Escopar "só time" faria **conversa sem time não notificar ninguém** — o análogo do card órfão. A única rede é `app/jobs/conversations/orphan_retriage_job.rb:71-78`, que só alcança **admins**.
3. **Agente SEM time recebe tudo do inbox** (`permission_filter_service.rb:22-23`, travado por `spec/.../permission_filter_service_spec.rb:82-92`: *"returns all conversations from accessible inboxes"*). Escopar por `conversation.team.members` zeraria a notificação dele **enquanto a lista dele continua mostrando tudo**. Regressão total em conta que não usa Teams.
4. **No `conversation_created` o `team_id` é quase sempre nil** (`app/models/conversation.rb:174`, `after_create_commit`). Escopo por time ali cai no ramo permissivo → **no-op**. Nuance: `AutomationRuleListener` é o 1º e `NotificationListener` o 9º do **mesmo** `AsyncDispatcher#listeners` (`app/dispatchers/async_dispatcher.rb:12-24`), no mesmo `EventDispatcherJob` e **mesma instância** de `event.data[:conversation]` — então se houver regra de roteamento, o time **já** está lá. Os dois caminhos existem.
5. **`BaseListener#extract_conversation_and_account` não dá reload** (`app/listeners/base_listener.rb:4-7`). Time atribuído por **outro** processo (`Spx::Tozi::FunnelAutomationListener`, IA, retriagem) pode não estar refletido em memória. → **não** fazer reload cego (perde o efeito da automação in-memory? não perde — `ActionService#assign_team` faz `update!`, `app/services/action_service.rb:62-73), mas avaliar caso a caso; para o fix da Fase 2 (`message_created`) o objeto vem fresco do banco e isso não é problema.
6. **Não renumerar `NOTIFICATION_TYPES`** (`app/models/notification.rb:38-52` — há comentário explícito no fork: `NotificationSetting` deriva os bits FlagShihTzu do valor, `app/models/notification_setting.rb:30-34`). Este fix **não adiciona tipo novo**.
7. **`Conversations::PermissionFilterService` não é reusável como classe** — opera sobre um **relation** (dado usuário → conversas); precisamos do **inverso** (dada conversa → usuários). Além disso o EE faz `prepend` e **sobrescreve `perform`** para custom roles (`enterprise/app/services/enterprise/conversations/permission_filter_service.rb:2-6`). → **Reusar a REGRA, não a classe**, com comentário cruzado nos dois arquivos.
8. **`ConversationParticipant#ensure_inbox_access`** (`app/models/conversation_participant.rb:44-46`) só valida na criação. Participante que saiu do inbox continua na tabela. O guard de audiência precisa checar inbox **de novo**, não confiar na validação.
9. **A notificação é criada em job async** (`EventDispatcherJob`) → `Current.user` pode estar nil. A regra **não pode depender de `Current`** (o `NotificationBuilder` já sofre disso em `:36`).
10. **Barrar na entrega não resolve**: `app/models/notification.rb:214-223` (`process_notification_delivery`) roda **depois** da linha existir e só gateia push/email; `dispatch_create_event` (`:57`) já mandou o realtime. **Barrar na criação da audiência mata sino+push+email de uma vez.**

---

## 3. Decisões de produto para TRAVAR com o dono

| # | Pergunta | Recomendação | Por quê |
|---|---|---|---|
| **P1** | Qual é a **regra canônica** do sino? | **Notificar U sobre C ⟺** `U é admin` **OU** `U é assignee de C` **OU** (`U é membro do inbox de C` **E** (`C.team_id` nil **OU** `C.team_id ∈ times de U`)). | É literalmente a regra da **LISTA** (`permission_filter_service.rb:19-24`) + a cláusula de assignee do guard `authorize_team_access` (`conversations_controller.rb:251`). Reusar, não inventar. |
| **P2** | Conversa **SEM time** notifica quem? | **Todo membro do inbox.** | Armadilha 2. Precedente travado por spec. Senão conversa nova entra e passa batido. |
| **P3** | Agente **SEM time nenhum** recebe o quê? | **Tudo dos inboxes dele** (sem filtro de time). | Armadilha 3. Precedente travado por spec. Conta que não usa Teams não pode ficar muda. |
| **P4** | **Ex-assignee / participante** que perdeu visibilidade continua sendo notificado de novas mensagens? | **NÃO.** Para de notificar. **Mas continua participante** (não apagamos linha de `conversation_participants`). | É o vetor nº1, 84% do volume. Não apagar dados = reversível e não quebra a lista de participantes da UI. |
| **P5** | **Menção cross-team** (`@fulano` de outro time no inbox compartilhado) continua notificando? | **SIM, intocada.** Fica fora de qualquer escopo. | `mention_service.rb:40-45` é deliberado. Menção = consentimento explícito e nominal. |
| **P6** | E as **mensagens SEGUINTES** para esse mencionado cross-team (ele virou participante em `mention_service.rb:67-71`)? | **Para de notificar** (só a menção em si passa). | Consistente com P4. Hoje um @ = ruído vitalício. |
| **P7** | **Notificações já existentes** (stale) no sino: apagar, esconder ou deixar? | **Apagar via script one-shot** (`--dry-run` primeiro). Só as que **hoje** violam a regra. | Precedente de delete de notificação existe (`Notification::RemoveDuplicateNotificationJob`, `notification.rb:222`). Sem isso, o dono abre o sino no dia seguinte e diz que o fix não funcionou. |
| **P8** | Vale **flag por conta/inbox**? | **NÃO. Regra fixa.** | Mesmo precedente do funil "Geral" (`FunnelPolicy`, regra fixa por papel, sem toggle — decisão já tomada pelo dono). Notificar sobre o que o usuário não pode ver não é preferência, é bug. Flag = manter o bug ligado em algum lugar. |
| **P9** | **Admin** continua recebendo tudo (`conversation_orphaned`, SLA)? | **SIM, intocado.** | `orphan_retriage_job.rb:71-78`, `queue_escalation_job.rb:91-98` — coerente com "admin vê tudo" (inclusive o Geral). |
| **P10** | Corrigimos também `notify_inbox_members` (`conversation_creation`), sabendo que **hoje é inerte** (0 opt-in no staging)? | **SIM, na Fase 3** — é ~3 linhas e fecha a bomba. **Com expectativa clara: não muda nada visível.** | O toggle é self-service (`notification_settings_controller.rb:14-16`, label pt-BR "Nova conversa"). Qualquer agente pode armar a bomba amanhã. |
| **P11** | E o buraco adjacente: `GET conversations/:id/**messages**` serve conversa de outro time (o `authorize_team_access` **não** existe em `conversations/base_controller.rb:8`, que só faz `authorize :show?`)? | **FORA DE ESCOPO** deste fix — abrir tarefa separada. É bug de **autorização**, não de notificação. | Misturar os dois transforma um fix de 30 linhas num refactor de policy com blast radius em 10 controllers aninhados. |

---

## 4. Mapa do código atual (o que existe hoje)

**Criação de notificação — 9 call sites de `NotificationBuilder.new`:**

| Call site | Audiência | Veredito |
|---|---|---|
| `app/services/messages/new_message_notification_service.rb:36` | **todos os `conversation_participants`** | 🔴 **FIX (Fase 2)** — vetor nº1, 84% do volume |
| `app/listeners/notification_listener.rb:95` (`notify_inbox_members`) | **todo membro do inbox** | 🟠 **FIX (Fase 3)** — inerte hoje (opt-in), bomba armada |
| `enterprise/app/models/sla_event.rb:65` | participantes + admins + assignee | 🟠 **FIX parcial (Fase 3)** — só a parte de participantes |
| `app/listeners/notification_listener.rb:32` (`assignee_changed`) | só o assignee | ✅ não mexer |
| `app/listeners/notification_listener.rb:65` (`notify_previous_assignee`) | só o assignee anterior | ✅ não mexer |
| `app/services/messages/new_message_notification_service.rb:20` | só o assignee | ✅ não mexer |
| `app/services/messages/mention_service.rb:57` | só os @mencionados | ✅ **PROIBIDO mexer** (P5) |
| `app/jobs/conversations/orphan_retriage_job.rb:73` | só admins | ✅ não mexer (P9) |
| `app/jobs/conversations/queue_escalation_job.rb:93` | só admins | ✅ não mexer (P9) |

**Leitura — confirmada limpa, não mexer:** `app/finders/notification_finder.rb:40` (`current_user.notifications.where(account_id:)`), todas as ações de `app/controllers/api/v1/accounts/notifications_controller.rb`, e o realtime `app/listeners/action_cable_listener.rb:4-8` (broadcast só para `notification.user.pubsub_token`).

**Superfície de UI (corrigindo o scout):** o sino é o item `name: 'Inbox'` de `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:299-307` → rota `inbox_view` (`app/javascript/dashboard/routes/dashboard/inbox/routes.js:11-30`) → `InboxList.vue` / `InboxCard.vue`. **`components-next/sidebar/SidebarNotificationBell.vue` é CÓDIGO MORTO** e `routes/dashboard/notifications/routes.js` (`notifications_index`) está **sombreada** (`dashboard.routes.js:31` espalha `inboxRoutes` antes de `notificationRoutes` no mesmo path). **Não investir nesses dois arquivos — mexer neles não muda a tela.**

**Gravidade do payload (justifica a urgência):** a notificação não é só um badge — `app/views/api/v1/accounts/notifications/index.json.jbuilder:17` serializa `primary_actor.push_event_data` → `app/presenters/conversations/event_data_presenter.rb:26-37` entrega **última mensagem viva**, `sender` (nome/telefone do contato), `assignee` (nome do agente do outro time) e `team`. É uma **janela read-only e viva** que contorna o 403 do `authorize_team_access`.

---

## 5. Solução por fases (verde a cada passo)

### Fase 0 — Pré-checagem de dados (read-only, **antes de codar**)
Rodar **na conta onde foi reportado** (se for produção, pedir ao dono/orquestrador — este host é staging).
```ruby
Notification.where(user_id: X, account_id: A).group(:notification_type).count
NotificationSetting.find_by(user_id: X, account_id: A)&.slice(:email_flags, :push_flags)
User.find(X).teams.pluck(:id); User.find(X).inboxes.count
```
- Se dominar **tipo 5** → Fase 2 é o fix. (staging: 47/56 ✔)
- Se aparecer **tipo 1** → o agente ligou "Nova conversa"; Fase 3 sobe de prioridade.
- Se o reclamante for **admin** → pode ser `conversation_orphaned` (tipo 9), **by design** (P9) → nenhum código muda, é conversa de produto.
- Se o agente for membro de inbox largo **e não tiver time** → P3 diz que ele vê tudo mesmo; a alavanca é **higiene de membership**, não código.

**Saída:** confirmação escrita do vetor. Sem isso, não codar.

---

### Fase 1 — Service da regra canônica (sem call site, puro)
**Novo:** `app/services/conversations/visibility_service.rb`
```ruby
# Espelho INVERSO de Conversations::PermissionFilterService#accessible_conversations
# (app/services/conversations/permission_filter_service.rb:18-25) + a cláusula de assignee do
# guard authorize_team_access (app/controllers/api/v1/accounts/conversations_controller.rb:246-260).
#   LÁ:  dado 1 usuário -> quais conversas (relation).
#   AQUI: dada 1 conversa -> quais usuários (audiência de notificação).
# SE VOCÊ MUDAR UM, MUDE O OUTRO. (comentário cruzado obrigatório nos 2 arquivos)
class Conversations::VisibilityService
  pattr_initialize [:conversation!]

  def visible_to?(user)
    return false if user.blank?
    return true  if administrator_ids.include?(user.id)
    return true  if conversation.assignee_id == user.id      # atribuição implica acesso
    return false unless inbox_member_ids.include?(user.id)
    return true  if conversation.team_id.nil?                # ARMADILHA 2 — não remover
    return true  unless users_with_teams_ids.include?(user.id) # ARMADILHA 3 — agente sem time vê tudo do inbox

    team_member_ids.include?(user.id)
  end
end
```
- `administrator_ids`: `AccountUser.where(account_id:, role: :administrator).pluck(:user_id)` (1 query, memoizado).
- `inbox_member_ids`: `conversation.inbox.member_ids`.
- `team_member_ids`: `conversation.team&.team_members&.pluck(:user_id) || []`.
- `users_with_teams_ids`: `TeamMember.joins(:team).where(teams: { account_id: }).where(user_id: inbox_member_ids).distinct.pluck(:user_id)` — resolve "agente sem time" para o loop inteiro em 1 query.
- **NÃO** usar `Current.user` (armadilha 9). **NÃO** usar `Pundit`/`ConversationPolicy` (é mais permissiva que a lista e não tem contexto de request no job).

**Spec novo:** `spec/services/conversations/visibility_service_spec.rb` — matriz completa:
admin fora do inbox → true · assignee fora do time → true · membro do inbox + time igual → true · membro do inbox + **time diferente** → **false** · membro do inbox + conversa **sem time** → true · **agente sem time** + conversa com time → true · não-membro do inbox → false · user nil → false.

✅ **Verde:** `bundle exec rspec spec/services/conversations/visibility_service_spec.rb`. Nenhum comportamento mudou ainda.

---

### Fase 2 — O FIX (participantes) ⟵ resolve o bug reportado
**Alterar:** `app/services/messages/new_message_notification_service.rb:29-44`
```ruby
def notify_participating_users
  participating_users = conversation.conversation_participants.includes(:user).map(&:user)
  participating_users -= [sender] if sender.is_a?(User)

  participating_users.uniq.each do |participant|
    next if already_notified?(participant)
    next unless visibility.visible_to?(participant)   # <- ÚNICA linha nova
    ...
  end
end

def visibility
  @visibility ||= Conversations::VisibilityService.new(conversation: conversation)
end
```
- **Não** tocar `notify_conversation_assignee` (`:15-27`) — já direcionado, e o assignee passa pela regra de qualquer jeito.
- **Não** apagar participante (P4). A participação segue existindo para a UI de participantes e para `MentionService`.

**Specs:** `spec/services/messages/new_message_notification_service_spec.rb`
- 🆕 *"não notifica participante de outro time quando a conversa tem time"* (ex-assignee).
- 🆕 *"notifica participante quando a conversa não tem time"*.
- 🆕 *"notifica participante sem time nenhum"*.
- 🆕 *"notifica o assignee mesmo que ele não seja do time da conversa"*.
- 🆕 *"notifica admin participante de outro time"*.
- ⚠️ Revisar os existentes: se algum monta participante sem time e conversa sem time, continua verde.

✅ **Verde:** `bundle exec rspec spec/services/messages/ spec/listeners/ spec/builders/`
🎯 **Este passo, sozinho, mata 84% do que o dono está vendo.** Dá para parar aqui e validar no staging antes da Fase 3.

---

### Fase 3 — Fechar as bombas armadas (inerte hoje, ver P10)
1. `app/listeners/notification_listener.rb:92-101` — `notify_inbox_members`:
   ```ruby
   visibility = Conversations::VisibilityService.new(conversation: conversation)
   members.each do |agent|
     next unless visibility.visible_to?(agent)
     ...
   ```
   ⚠️ Armadilha 4: em `conversation_created` o `team_id` costuma ser nil → cai em `return true if conversation.team_id.nil?` → **mesmo comportamento de hoje**. Isso é **correto** (P2), não é bug.
2. `enterprise/app/models/sla_event.rb:64-66` — filtrar **só o ramo de participantes**:
   ```ruby
   visibility = Conversations::VisibilityService.new(conversation: conversation)
   notify_users = conversation.conversation_participants.map(&:user).select { |u| visibility.visible_to?(u) }
   notify_users += account.administrators                       # intocado (P9)
   notify_users += [conversation.assignee] if conversation.assignee.present?  # intocado
   ```

**Specs a ALTERAR (detector de regra — devem continuar VERDES sem edição se você implementou a regra certa):**
- `spec/listeners/notification_listener_spec.rb:15-28` — conversa **sem time** (a factory só põe time via trait `:with_team`, `spec/factories/conversations.rb:20-24`), `first_agent` é agente sem time → **passa** sob a regra da lista, **quebra** sob "só time/assignee". **Se quebrou, você implementou a regra errada — volte à §P1/P2/P3.**
- `spec/listeners/notification_listener_spec.rb:188-201` — idem para `conversation_bot_handoff`.
- Negativos `:30-43` e `:203-216` (flags off) → passam sempre.

**Specs NOVOS:** `spec/listeners/notification_listener_spec.rb` — 🆕 *"não notifica membro do inbox de outro time quando a conversa já tem time"* (usar `:with_team`), 🆕 *"notifica membro do inbox sem time"*, 🆕 *"notifica admin"*.

**Spec de REGRESSÃO obrigatório (armadilha 1):** `spec/services/messages/mention_service_spec.rb` — 🆕 caso com **builder REAL** (`unstub`/contexto sem o `allow(NotificationBuilder)` de `:22`), conversa **com time X**, mencionado do **time Y** membro do inbox → **deve criar `conversation_mention`**. Este é o único teste que impede alguém de "otimizar" o guard para dentro do `NotificationBuilder` no futuro.

✅ **Verde:** `bundle exec rspec spec/listeners spec/services/messages spec/builders spec/models/notification_spec.rb spec/enterprise`

---

### Fase 4 — Limpeza do histórico (P7)
Sem isso o dono abre o sino e o bug "continua".
1. **Script `task/notificacoes_vazadas_cleanup.rb`** com `--dry-run` **default**:
   - varre `Notification.where(account_id:, primary_actor_type: 'Conversation').includes(:user, :primary_actor)` em `find_each`;
   - para cada, `Conversations::VisibilityService.new(conversation: n.primary_actor).visible_to?(n.user)` (memoizar o service por conversa);
   - dry-run imprime: total, por `notification_type`, por usuário, 10 exemplos.
2. **Só depois de o dono aprovar os números**, rodar com `--apply` (`destroy_all` em lotes → dispara `dispatch_destroy_event` e o `unread_count` do sino se corrige sozinho via `action_cable_listener.rb:16-30`).
3. ⚠️ **Nunca** rodar em produção sem dry-run revisado. Nunca escopar por `read_at` — as lidas também sujam a aba "Lidas".

**Sem handler `team_changed` nesta fase.** O fluxo passa a nascer correto (Fases 2-3); a janela de obsolescência que resta é a conversa que **já foi notificada** e depois muda de time — cobrir isso exige ou um handler que **apaga** notificação (destrutivo, dispara em toda triagem) ou filtro no `NotificationFinder` (join polimórfico + quebra de paginação). **Deferido** → Fase 5.

---

### Fase 5 — Deferidos (abrir tarefas separadas, NÃO fazer agora)
- **Handler `team_changed`** que revoga notificações obsoletas (o evento já é despachado: `app/models/concerns/assignment_handler.rb:62`).
- **Filtro read-side** no `NotificationFinder` como defesa em profundidade (custo: join polimórfico + `unread_count` inconsistente com a paginação).
- **Poda de participantes** em `participation_listener.rb:8` — **recomendo NÃO fazer**: a tabela não tem coluna `source`, então é impossível distinguir "ex-assignee automático" de "participante adicionado à mão" (`participants_controller.rb:6-10`) ou "@mencionado" (`mention_service.rb:67-71`). O guard de audiência já resolve o sintoma sem destruir dado.
- **🔴 Buraco de autorização (P11, mais grave que este bug):** `app/controllers/api/v1/accounts/conversations/base_controller.rb:8` só faz `authorize @conversation, :show?`, **sem** `authorize_team_access` — e `ConversationPolicy#agent_can_view_conversation?` (`app/policies/conversation_policy.rb:17`) concede por `inbox_access?` sozinho. Reproduzido: `GET conversations/:id` → **403**, mas `GET conversations/:id/messages` → **200 com o conteúdo da conversa do outro time**. Herdam desse base: `messages`, `labels`, `assignments`, `participants`, `reactions`, `funnel_items`, `copilot_chats`. **Tarefa própria, prioridade alta.**
- **Dead code:** `ConversationPolicy#participant?` (`:51`) nunca é chamado pelo core (só pelo override EE de custom roles).
- **Higiene:** `notifications_controller.rb:62-67` — `set_primary_actor` faz `find_by(id:)` sem escopo de conta (no-op explorável = nenhum, mas escopar por `Current.account` na faxina).

---

## 6. O que NÃO mexer (explícito)

| Não tocar | Por quê |
|---|---|
| `app/builders/notification_builder.rb` | Armadilha 1 — mata menção cross-team, **sem spec pegando**. |
| `app/services/messages/mention_service.rb` | P5 — menção cross-team é deliberada. |
| `app/finders/notification_finder.rb` / `notifications_controller.rb` | Leitura já escopada por `user_id`. Não é a causa. |
| `app/listeners/action_cable_listener.rb` | Broadcast já é 1:1 com o dono (`:6`). |
| `app/listeners/notification_listener.rb:16-38` e `:52-73` | `assignee_changed` / `notify_previous_assignee` já direcionados. |
| `orphan_retriage_job.rb:73`, `queue_escalation_job.rb:93` | Admin vê tudo, by design (P9). |
| `app/models/notification.rb` `NOTIFICATION_TYPES` | Armadilha 6 — bits FlagShihTzu. Não renumerar, não adicionar tipo. |
| `app/policies/conversation_policy.rb` | P11 — fix de autorização é **outra** tarefa. Apertar a policy **não** corrige o sino (o listener nem consulta a policy). |
| `components-next/sidebar/SidebarNotificationBell.vue`, `routes/dashboard/notifications/` | Código morto / rota sombreada. |
| Front (`InboxList.vue`, `InboxCard.vue`, `getters.js`) | O fix é **não criar a linha**. Filtrar no front seria maquiagem. |
| `db/` | Sem migration. |
| Feature flags / `feature_flags` bitmask | P8 — regra fixa. E o bitmask já está no teto de 63 bits. |

---

## 7. Checklist

**Antes de codar**
- [ ] Fase 0 rodada na conta certa; vetor confirmado por escrito.
- [ ] P1–P11 respondidas pelo dono (mínimo: P1, P2, P3, P4, P7, P8).
- [ ] Confirmado com o dono que ele é **agente** (se for admin, ver P9 — pode não haver bug).

**Implementação**
- [ ] F1: `visibility_service.rb` + spec verde; comentário cruzado adicionado **em `permission_filter_service.rb:18`** também.
- [ ] F2: guard em `notify_participating_users`; specs novos verdes.
- [ ] F3: guard em `notify_inbox_members` + `sla_event.rb`; `notification_listener_spec.rb:15-28` e `:188-201` **verdes sem edição**; spec de regressão de menção com builder REAL.
- [ ] `bundle exec rubocop` nos arquivos tocados.
- [ ] Suíte: `bundle exec rspec spec/services/conversations spec/services/messages spec/listeners spec/builders spec/enterprise/app/models/sla_event_spec.rb`

**Validação (staging `nicolas.chatspx.app` — **nunca** em produção)**
- [ ] Seed: 2 times, 1 inbox compartilhado; conversa atribuída ao agente A (time X) → reatribuída ao agente B (time Y). Cliente manda mensagem.
- [ ] **A NÃO recebe sino.** B recebe. Admin recebe. Conferir `Notification.where(user_id: A).count` estável.
- [ ] Conversa **sem time** → todos do inbox recebem (P2).
- [ ] Agente sem time → recebe (P3).
- [ ] `@menção` cross-team → **mencionado recebe** (P5); mensagem seguinte → **não recebe** (P6).
- [ ] Restart: `sudo /bin/systemctl restart chatwoot.target` (código Ruby; sem `assets:precompile`, nada de front mudou).

**Limpeza**
- [ ] F4 dry-run revisado com o dono → `--apply` → sino do reclamante conferido ao vivo.

**Commit**
- [ ] 1 commit por fase (padrão `[[commit-at-end-of-each-phase]]`): `fix(notifications): escopa audiência do sino pela regra de visibilidade da lista`.
- [ ] Tarefas separadas abertas: P11 (autorização em controllers aninhados) e F5.
