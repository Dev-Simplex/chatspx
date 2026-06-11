# Extra 3 — Subsistema de notificações: o loop "corretor fica sabendo"

> Mapeamento baseado em leitura do código local (branch `paulao`), árvores `app/` e `enterprise/`.
> Pergunta-guia: quando a IA/HandoffTool/automação/API atribui uma conversa, o que de fato sai (in-app, e-mail, push) e o que silencia?

---

## 1. Arquitetura geral do pipeline

### 1.1 Como um evento vira notificação

Todos os eventos de domínio passam pelo `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb:1-26`), que enfileira um `EventDispatcherJob` e publica para os listeners registrados — entre eles o `NotificationListener.instance` (linha 20). **Implicação importante: os gates dos listeners são avaliados quando o job roda, não no momento do dispatch** — se o status da conversa mudou entre o dispatch e a execução (ex.: `pending` → `open` milissegundos depois), o listener vê o estado novo.

O `NotificationListener` (`app/listeners/notification_listener.rb`) trata exatamente 4 eventos:

| Evento | Handler | O que faz |
|---|---|---|
| `conversation_bot_handoff` | linhas 2-7 | `notify_inbox_members` → notificação `conversation_creation` p/ TODOS os membros da inbox |
| `conversation_created` | linhas 9-14 | idem (`notify_inbox_members`, linhas 45-55) |
| `assignee_changed` | linhas 16-34 | notificação `conversation_assignment` SÓ para o novo assignee |
| `message_created` | linhas 36-41 | delega para `Messages::MentionService` + `Messages::NewMessageNotificationService` |

**Não existe handler para `conversation_opened`** — quem trata esse evento é só `ReportingEventListener` (`app/listeners/reporting_event_listener.rb:132`), `AutomationRuleListener` (`app/listeners/automation_rule_listener.rb:10-12`) e `AgentBotListener` (`app/listeners/agent_bot_listener.rb:10`).

### 1.2 NotificationBuilder → registro in-app

`app/builders/notification_builder.rb`:
- Linha 27: **só o tipo `conversation_creation` exige assinatura prévia** (`user_subscribed_to_notification?`, linhas 14-23: precisa de flag email OU push daquele tipo). Os demais tipos (assignment, new_message, mention, SLA) **sempre criam o registro in-app**.
- Linha 29: contato bloqueado silencia tudo, EXCETO `conversation_mention`.
- Linha 36: `secondary_actor: secondary_actor || Current.user` — em jobs de background (`Current.user` nil), fica nil; não há gate de "bot como performer" aqui.

### 1.3 Notification model → entrega (push/e-mail)

`app/models/notification.rb`:
- `after_create_commit :process_notification_delivery, :dispatch_create_event` (linha 52).
- `process_notification_delivery` (linhas 200-209): enfileira `Notification::PushNotificationJob` **se** `push_<tipo>` está ligado no `NotificationSetting` do usuário naquela conta, e `Notification::EmailNotificationJob` **se** `email_<tipo>` está ligado (`user_subscribed_to_notification?`, linhas 211-216). Sem flag → **só fica o registro in-app**.
- Também enfileira `Notification::RemoveDuplicateNotificationJob` (linha 208) — que **destrói as notificações antigas do mesmo user+conversa**, mantendo só a mais recente (`app/jobs/notification/remove_duplicate_notification_job.rb:12-16`). O sininho colapsa para 1 entrada por conversa.
- `dispatch_create_event` → `NOTIFICATION_CREATED` → `ActionCableListener#notification_created` (`app/listeners/action_cable_listener.rb:4-8`) faz broadcast em tempo real pro `pubsub_token` do usuário → badge do sininho no painel e no app móvel conectado.
- Os índices `uniq_primary_actor_per_account_notifications` / `uniq_secondary_actor...` (schema.rb:1177-1178) **não são unique** apesar do nome — são índices comuns.

### 1.4 Canais de entrega

**In-app (sininho):** sempre que o registro `Notification` é criado (ver gates acima). Visível só com o painel aberto (ActionCable) ou ao abrir a lista de notificações.

**Push** (`app/services/notification/push_notification_service.rb`):
- Itera as `notification_subscriptions` do usuário (linha 9) — tabela `notification_subscriptions`, tipos `browser_push: 1` e `fcm: 2` (`app/models/notification_subscription.rb:23-26`).
- Re-checa a flag `push_<tipo>` (linhas 22-27) — dupla verificação.
- **Browser push (webpush/VAPID):** `send_browser_push` (linhas 66-73), exige `VapidService.public_key` + subscription browser (linha 46). Auto-limpeza de subscription expirada (linhas 75-88).
- **FCM direto:** `send_fcm_push` (linhas 90-100), exige `FIREBASE_PROJECT_ID` + `FIREBASE_CREDENTIALS` em GlobalConfig (`firebase_credentials_present?`, linhas 110-112). Mensagem data-only v1 (linhas 126-149) consumida pelo app móvel oficial via Notifee.
- **Relay Chatwoot Hub:** `send_push_via_chatwoot_hub` (linhas 102-108) — fallback quando NÃO há credenciais Firebase próprias e `ENABLE_PUSH_RELAY_SERVER` ≠ false (default `true`, `.env.example:252`); POSTa o payload FCM para o hub do Chatwoot (`lib/chatwoot_hub.rb:108-115`), que entrega via o projeto Firebase DELES — isto é, **só funciona com o app móvel oficial do Chatwoot**.

**E-mail** (`app/services/notification/email_notification_service.rb`):
- Gates em cascata (linhas 5-12): `DISABLE_AGENT_EMAIL_NOTIFICATIONS=true` mata tudo; `read_at` presente (já leu o push) pula; usuário **não confirmado** pula; flag `email_<tipo>` desligada pula; **rate limit diário de e-mail da conta** (`within_email_rate_limit?`, `app/models/concerns/account_email_rate_limitable.rb:19-24` — limite por conta `limits['emails']`, global `ACCOUNT_EMAILS_LIMIT` ou `ChatwootApp.max_limit`).
- Mailer `AgentNotifications::ConversationNotificationsMailer` (`app/mailers/agent_notifications/conversation_notifications_mailer.rb`): para `assigned_conversation_new_message` e `participating_conversation_new_message` há um gate extra — **não envia e-mail se o agente está online** (linhas 41 e 54, via `OnlineStatusTracker.get_presence`). Para `conversation_assignment` NÃO há esse gate (envia mesmo online). Overlay Enterprise adiciona os 3 mailers de SLA com assunto em PT (`enterprise/app/mailers/enterprise/agent_notifications/conversation_notifications_mailer.rb:2-31`).

### 1.5 Defaults de notification_settings — o detalhe que explica o incidente

`app/models/account_user.rb:46-51` (`after_create_commit :create_notification_setting`):

```ruby
setting.selected_email_flags = [:email_conversation_assignment]
setting.selected_push_flags  = [:push_conversation_assignment]
```

**Por padrão, o único tipo com entrega ativa (e-mail + push) é `conversation_assignment`.** Todos os outros — `assigned_conversation_new_message` (lead respondeu na conversa do corretor!), `conversation_mention`, `participating_conversation_new_message`, `conversation_creation`, SLA — ficam **só no sininho in-app**, a menos que o usuário ligue as flags em Perfil → Notificações (`NotificationPreferences.vue`). `NotificationSetting` usa FlagShihTzu sobre `email_flags`/`push_flags` (`app/models/notification_setting.rb:30-34`).

---

## 2. Resposta direta: quem atribui → o que sai

### 2.1 Atribuição (qualquer origem que passe por callbacks)

Caminho único: `Conversation` salva com `assignee_id` mudado → `AssignmentHandler#notify_assignment_change` (`app/models/concerns/assignment_handler.rb:55-62`, `after_commit`) → dispatch `ASSIGNEE_CHANGED` com `notifiable_assignee_change?` calculado em `app/models/conversation.rb:228-234` e empacotado em `dispatcher_dispatch` (conversation.rb:392-396).

`NotificationListener#assignee_changed` (linhas 16-34) então aplica os gates, em ordem:
1. **`assignee.blank?` → silêncio total** (linha 24). Desatribuição não notifica ninguém — nem o ex-assignee.
2. **`notifiable_assignee_change` blank → silêncio** (linha 25). Vira `false` quando: não houve mudança real de assignee; assignee nil; ou **self-assign** (`self_assign?`: `Current.user&.id == assignee_id`, `assignment_handler.rb:83-85`). Em jobs/IA, `Current.user` é nil → nunca é self-assign → **atribuição por bot/job sempre é "notifiable"**.
3. **`conversation.pending?` → silêncio** (linha 26). Atribuir conversa pending não notifica. (Mas lembrar: gate avaliado async — se a conversa abriu antes do EventDispatcherJob rodar, passa.)

Passando os gates → `NotificationBuilder` tipo `conversation_assignment` → in-app sempre + **push e e-mail por default** (única combinação com flags ON de fábrica). E-mail sai mesmo com o agente online. Push sai **se** existir `NotificationSubscription` do corretor.

Origens concretas:
- **HandoffTool da Clara** (`enterprise/lib/captain/tools/handoff_tool.rb`): posta a razão como **nota privada sem markup de menção** (linhas 26-37 — não dispara MentionService), `conversation.bot_handoff!` (linha 40 → `conversation.rb:199-203`: `open!` + dispatch `CONVERSATION_BOT_HANDOFF`), depois `assign_to_available_agent` (linhas 52-64) → `AutoAssignment::AgentAssignmentService#perform` → `conversation.update(assignee:)` com callbacks completos. **Porém o serviço só sorteia entre agentes ONLINE** (`app/services/auto_assignment/agent_assignment_service.rb:18-28`, interseção com `OnlineStatusTracker`). **Se nenhum corretor está online, a conversa fica aberta e SEM DONO, silenciosamente** (nem log de aviso). O evento `CONVERSATION_BOT_HANDOFF` aciona `notify_inbox_members` (notification_listener.rb:2-7) com tipo `conversation_creation` — que exige assinatura prévia (notification_builder.rb:27) — **morto por default** (flags de creation OFF).
- **Copilot tool `assign_conversation`** (`enterprise/app/services/captain/tools/copilot/assign_conversation_service.rb:25-29`): `conversation.save!` → callbacks completos → mesmo pipeline. Hook pronto pra IA orquestradora (aceita `agent_id` e `team_id`).
- **API REST** (`/toggle_assignee` etc.): `Current.user` = quem chamou; secretária atribuindo ao corretor → notifica o corretor; corretor pegando pra si → self-assign → silêncio (correto).
- **DisparoLeadJob** (`app/jobs/spx/tozi/disparo_lead_job.rb`): conversa nova é criada já `open` com `assignee_id` (linhas 133-142) → `saved_change_to_assignee_id?` true no create → `ASSIGNEE_CHANGED` dispara → **corretor recebe conversation_assignment (in-app + e-mail + push default) POR DISPARO** — num lote de 600, são centenas de e-mails por corretor, contidos só pelo rate limit diário da conta e pelo `RemoveDuplicateNotificationJob` (que colapsa o sininho mas NÃO impede e-mails de conversas distintas). No caminho de reuso (linhas 126-130), o `update!(assignee_id:)` acontece ANTES do `open!` — se a conversa estava pending, o gate da linha 26 pode silenciar (racy: depende de o EventDispatcherJob rodar antes ou depois do `open!`).
- **AutomationRule "iniciar zerado" (#53 em prod)**: zera assignee+team → assignee nil → gate da linha 24 → **desatribuição 100% silenciosa**. Esse é o mecanismo que tornou o incidente invisível: lead respondeu, regra zerou o dono, ninguém foi notificado de nada.

### 2.2 Lead responde na conversa do corretor (o cerne do incidente)

`Messages::NewMessageNotificationService` (`app/services/messages/new_message_notification_service.rb`):
- Gate de entrada: `message.notifiable?` = `(incoming? || outgoing?) && !private?` (`app/models/concerns/message_filter_helpers.rb:16-18`). **Não há gate de status da conversa** — funciona até em pending.
- `notify_conversation_assignee` (linhas 15-27): silencia se assignee nil, se já notificado pela mesma mensagem (mention/participante), ou se `assignee == sender`.
- Resultado: reply do lead → notificação `assigned_conversation_new_message` **in-app criada SEMPRE** (mesmo no limbo pending). **Mas push e e-mail são default OFF para esse tipo** → o corretor só fica sabendo se estiver com o painel aberto. No celular, nada. Esse é o elo quebrado do loop "corretor fica sabendo": **não é que a notificação não existe — é que a entrega ativa (push/e-mail) do tipo certo está desligada de fábrica**, e o e-mail, mesmo ligado, é suprimido com o agente online (mailer linha 41).
- Bônus inesperado: mensagens **outgoing da Clara** (sender `Captain::Assistant`) também são `notifiable?` → cada resposta da IA cria notificação in-app pro corretor assignee (sender ≠ assignee). Ruído de sininho em escala; colapsado por conversa pelo RemoveDuplicateNotificationJob.

### 2.3 A promoção pending→open do commit f96ae7740 notifica alguém?

**Não — diretamente, ninguém.** `ensure_conversation_open` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:59-71`) chama `conversation.open!` com `Current.executed_by = assistant`. Isso dispara `CONVERSATION_OPENED` + `CONVERSATION_STATUS_CHANGED` (`conversation.rb:380-390`) — **nenhum dos dois tem handler no NotificationListener**. O `executed_by` só muda a autoria da atividade e o `performed_by` do evento.

Efeitos indiretos relevantes:
1. **`AutomationRuleListener#conversation_opened` RODA** (`automation_rule_listener.rb:10-12`). O skip `performed_by_automation?` (linhas 73-75) só ignora eventos performados por `AutomationRule` — Clara (`Captain::Assistant`) não é. Logo a **regra #53 "iniciar zerado" (event conversation_opened, inboxes 61/62/91, zera assignee+team) dispara quando a Clara promove a conversa** — risco real de desatribuir a conversa que a IA acabou de assumir, de novo sem notificar ninguém (gate assignee nil).
2. A mensagem incoming que originou o hook gera `MESSAGE_CREATED` separadamente (`app/models/message.rb:401-409`) → se a conversa tem assignee, sai `assigned_conversation_new_message` in-app (entrega OFF por default). Como tudo é async, na hora em que o listener roda a conversa provavelmente já está open.
3. Broadcast ActionCable de status p/ a UI (listas atualizam), sem notificação pessoal.

### 2.4 FCM/VAPID está configurado nesta instalação?

O que o código garante (sem acesso a prod, avaliando o repo):
- **VAPID (browser push): auto-bootstrap.** `VapidService.vapid_keys` (`lib/vapid_service.rb:10-22`) gera o par de chaves e persiste em `InstallationConfig('VAPID_KEYS')` na primeira chamada se não existir (com fallback a `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY` do env — comentadas no `.env.example:195-196`). O `DashboardController` expõe a pública ao front (`app/controllers/dashboard_controller.rb:72`), e `pushHelper.js` registra a subscription quando o usuário concede permissão (`app/javascript/dashboard/helper/pushHelper.js:63-83`, via `NotificationPreferences.vue:91-109` e `App.vue:161`). **Conclusão: webpush está sempre disponível server-side**; o gargalo é comportamental — cada corretor precisa conceder permissão no navegador (HTTPS ok em prod). iPhone só com PWA instalada na home screen.
- **FCM direto: quase certamente NÃO configurado.** Exige `FIREBASE_PROJECT_ID` + `FIREBASE_CREDENTIALS` em InstallationConfig, defaults vazios (`config/installation_config.yml:319-330`); nada no repo/STATE indica projeto Firebase próprio.
- **Relay via Chatwoot Hub: ligado por default** (`ENABLE_PUSH_RELAY_SERVER=true`, `.env.example:252`; código em `push_notification_service.rb:102-116` + `chatwoot_hub.rb:108-115`). Serve **exclusivamente** tokens FCM do **app móvel oficial do Chatwoot** (o token pertence ao projeto Firebase do Chatwoot). Corretor no celular tem duas rotas: (a) instalar o app oficial Chatwoot apontando pra `tozi.chatspx.app` — o app registra `NotificationSubscription` tipo `fcm` via `POST /api/v1/notification_subscriptions` (`app/controllers/api/v1/notification_subscriptions_controller.rb:4-8`) e o push sai pelo relay (conflita com white-label, mas funciona); ou (b) navegador móvel com webpush. Não existe app móvel próprio do chatspx no repo.
- **Não verificável daqui:** se os corretores TÊM subscriptions registradas em prod (tabela `notification_subscriptions`, Account 6). Checagem sugerida em prod (read-only): `NotificationSubscription.where(user_id: [126,127,128,131,125]).pluck(:user_id, :subscription_type)`.

### 2.5 Menção em nota privada serve de canal IA→humano com push garantido?

**Serve como canal, mas o push NÃO é garantido com os defaults.** Mecânica (`app/services/messages/mention_service.rb`):
- Exige mensagem **privada** com markup exato `[Nome](mention://user/<id>/<nome>)` (regex linha 22; também `mention://team/<id>` que expande pros membros do time, linhas 30-38). A nota privada que a HandoffTool cria hoje (handoff_tool.rb:28-37) é texto puro — **não menciona ninguém**.
- Mencionado precisa ser admin da conta ou membro da inbox (linhas 40-49).
- Efeitos: `Conversations::UserMentionJob` (pasta "Menções" da sidebar), notificação `conversation_mention` (linhas 51-65) e **inclusão como participante** (linhas 67-71) — o que liga o usuário a TODAS as mensagens futuras via `participating_conversation_new_message`.
- Pontos fortes do tipo `conversation_mention`: é criado in-app **sem exigir assinatura** (notification_builder.rb:27 só restringe creation) e fura até o gate de contato bloqueado (linha 29). E-mail de mention NÃO tem o gate "agente online" (mailer linhas 25-35).
- Ponto fraco fatal: **`push_conversation_mention` e `email_conversation_mention` são default OFF** (account_user.rb:48-49). Sem script ligando essas flags para os corretores + subscription registrada, a menção vira só sininho.
- Receita para virar canal IA→humano confiável: (1) one-time script ligando `push_conversation_mention` + `email_conversation_mention` (e idealmente `push/email_assigned_conversation_new_message`) nos `notification_settings` dos corretores; (2) garantir webpush (permissão no navegador) ou app móvel; (3) IA escrever a nota privada com o markup `mention://user/...` — via `send_message`-like tool ou `Messages::MessageBuilder` com `private: true`.

---

## 3. Tabela-resumo dos gates

| Gate | Onde | O que silencia |
|---|---|---|
| Conversa `pending` | notification_listener.rb:4, 11, 26 | creation, bot_handoff e assignment (NÃO silencia new_message/mention). Avaliado async → racy |
| Assignee nil | notification_listener.rb:24; new_message_notification_service.rb:16 | assignment e new_message. Desatribuição é sempre silenciosa |
| Self-assign (`Current.user == assignee`) | assignment_handler.rb:83-85 → conversation.rb:228-234 | assignment. Job/IA: Current.user nil → nunca self-assign |
| Flags do usuário (default só `conversation_assignment`) | account_user.rb:46-51; notification.rb:200-216; notification_builder.rb:14-27 | entrega push/e-mail de TODOS os outros tipos; creation nem vira in-app |
| `sender == assignee` / já notificado | new_message_notification_service.rb:17-18, 48-56 | new_message |
| Mensagem privada / activity | message_filter_helpers.rb:16-18 | new_message (nota privada não notifica assignee — só via mention) |
| Agente online | conversation_notifications_mailer.rb:41, 54 | e-mail de new_message types (assignment e mention passam) |
| Usuário não confirmado / notificação lida / `DISABLE_AGENT_EMAIL_NOTIFICATIONS` / rate limit | email_notification_service.rb:5-12 | e-mail |
| Sem `NotificationSubscription` | push_notification_service.rb:9, 46, 91-92 | push (webpush exige VAPID + permissão; fcm exige app oficial ou Firebase próprio) |
| Contato bloqueado | notification_builder.rb:29 | tudo exceto mention |
| Bot como performer | — | **não existe gate específico**; outgoing da Clara até GERA notificação in-app pro assignee |
| Dedup | remove_duplicate_notification_job.rb:12-16 | colapsa sininho a 1 por user+conversa (não afeta e-mails já disparados) |

## 4. SLA como canal alternativo de follow-up vencido

`SlaEvent` (`enterprise/app/models/sla_event.rb:34, 60-86`): ao estourar FRT/NRT/RT, notifica **admins da conta + assignee** com tipos `sla_missed_*` (mailers PT no overlay Enterprise). Mesma ressalva: push/e-mail desses tipos são default OFF. Mas é um mecanismo nativo de "conversa esquecida" que a orquestração pode aproveitar (aplicar SLA policy nas conversas de disparo em vez de criar watchdog próprio).

## 5. Implicações para a IA orquestradora

1. **Atribuir com callbacks (update!/save!) é o único caminho que notifica** — e é o canal mais confiável do sistema (push+e-mail default ON). Nunca `update_columns` para assignee.
2. **Atribuir só depois de `open`** (ou aceitar a raciness do gate pending). Sequência segura: `open!` → `update!(assignee_id:)`.
3. **Verificar pós-atribuição**: HandoffTool pode terminar sem dono (ninguém online) sem erro. Orquestrador precisa de fallback (fila da secretária, time, ou menção a admin).
4. **Regra #53 vs promoção f96ae7740**: o `conversation_opened` da promoção aciona automation rules — a regra "iniciar zerado" pode desatribuir o que a IA fez. Conciliar (condição na regra, ou desativá-la quando a IA orquestrar).
5. **Ligar flags por script** (`NotificationSetting#selected_push_flags/selected_email_flags`) para `assigned_conversation_new_message` e `conversation_mention` dos corretores é pré-requisito de qualquer loop IA→humano por push.
6. **Menção em nota privada** é o melhor canal dirigido IA→humano (escolhe a pessoa, vira participante, fura gates) — desde que as flags estejam ligadas e haja subscription.
7. **Cuidado com volume**: disparos em massa com assignee geram 1 `conversation_assignment` (e-mail+push) por conversa criada; só o rate limit diário da conta segura.
