# S-01 — "Nova conversa" entra no atendimento de outro time, manda a mensagem e trava em 403

**Responsavel:** Nicolas Silva
**Origem:** suporte de 22/09/2026 — relato da Leticia (conta do cliente, caixa de WhatsApp).
Prints: modal vermelho "Atencao / Voce nao tem permissao para acessar esta conversa." e o modal
"Nova conversa" (telefone + caixa + time + mensagem).
**Branch:** sair de `producao`, 1 PR. Conventional Commits. `bundle exec rubocop -a` / `pnpm eslint`.
Nao deployar.

---

## O relato, em uma frase

> "Ela coloca o numero para chamar, atribui a ela e o time, e quando vai iniciar a conversa aparece
> que ela nao e habilitada. Nao tem link para te mandar. O atendimento 12 esta enviando msg aos
> clientes e aparece essa mensagem."

Traduzindo: **a mensagem sai** (o cliente recebe, e ela sai dentro do atendimento de outra pessoa),
e logo em seguida a tela dela bate no 403 e nao abre nada.

---

## S-01 — O "Nova conversa" reusa a conversa de outro time e descarta o agente/time escolhidos

| | |
|---|---|
| Tipo | BUG + vazamento de escrita |
| Valor | O agente volta a conseguir iniciar atendimento pelo modal. Hoje, em toda caixa de WhatsApp, quando o contato ja tem uma conversa nao resolvida, o modal NAO cria conversa nova: escreve dentro da conversa de outro time/agente e depois joga o agente num 403 sem saida |
| Confianca | CONFIRMADO: li o codigo dos dois lados e o proprio comentario do `useAttendanceGate.js` descreve o mesmo mecanismo |
| Ja existe? | O guard de time existe (`ConversationTeamAccessConcern`, P11) e o isolamento por agente existe, mas nenhum dos dois roda no `create` — ele esta em `CONVERSATIONLESS_ACTIONS`. O aviso "contato ja em atendimento" (Fase 2) existe, mas so avisa: tem "Enviar mesmo assim" |
| Onde | `app/builders/conversation_builder.rb:27-29`, `:36-38`, `:45-47`, `:60-72` · `app/controllers/api/v1/accounts/conversations_controller.rb:8`, `:61-67` · `app/controllers/concerns/conversation_team_access_concern.rb:16-25` · `app/javascript/dashboard/store/modules/contactConversations.js` (`create`, `throw new Error(error)`) · `app/javascript/dashboard/components-next/NewConversation/ComposeConversation.vue:241-284` · `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue:188-217` |
| Esforco | pequeno/medio (backend pequeno; front e 1 catch) |
| Como validar | Ver "Como validar" no fim |

---

## Causa raiz (a cadeia inteira)

1. O modal monta o payload com `assigneeId: currentUser.id` e `teamId` escolhido
   (`composeConversationHelper.js`, `prepareNewMessagePayload`) e chama `POST /conversations`.

2. `ConversationsController#create` (`:61-67`) chama o `ConversationBuilder`. O builder, em
   `look_up_exising_conversation` (`conversation_builder.rb:27-29`), **nao cria conversa nova**:

   - linha 28 — caixa com `lock_to_single_conversation` → devolve a conversa mais recente nao
     resolvida do contato naquela caixa (e, se nao houver, ate a resolvida);
   - linha 29 — caixa **WAHA** (`Channel::Api` + `waha_session_name`) → devolve a ultima conversa
     nao resolvida. **Toda caixa de WhatsApp da frota cai aqui.**

3. Quando reusa, o `assignee_id` e o `team_id` do payload sao **descartados**: eles so sao lidos em
   `conversation_params` (`:69-70`), que roda apenas dentro de `create_new_conversation`. A conversa
   devolvida continua com o dono e o time de quem estava atendendo.

4. Ainda dentro da transacao, o `MessageBuilder` grava a mensagem nessa conversa alheia. `create`
   esta em `CONVERSATIONLESS_ACTIONS` (`:8`), entao **nem o guard de time nem o isolamento por
   agente rodam** — e a escrita passa. E o furo do P11 por outra porta: da para escrever numa
   conversa que voce nao consegue nem abrir.

5. O front redireciona para a conversa devolvida
   (`ComposeConversation.vue:272-276`, `router.push(.../conversations/${data.id})`).

6. O `GET /conversations/:display_id` bate no `authorize_team_access`
   (`conversation_team_access_concern.rb:24`) e responde **403** — ela nao e membro do time daquela
   conversa e nao e a assignee.

7. `ConversationView.vue:188-217` transforma qualquer 403 **sem** `error_code` no modal vermelho com
   o texto fixo "Voce nao tem permissao para acessar esta conversa." (`:211`).

### Por que sabemos que e o guard de TIME

- O isolamento por agente responde 403 **com** `error_code: 'conversation_access_blocked'`, e nesse
  caso a tela mostraria o painel "nao atribuida a voce" + botao **Solicitar** (`:196-206`), nao o
  modal vermelho.
- Erro de policy (Pundit) sai como **401** (`request_exception_handler.rb:26-28`), que cairia no
  texto "Erro ao carregar a conversa".
- Sobra o `ConversationTeamAccessConcern`: 403, sem `error_code`.

### Por que o aviso "contato ja em atendimento" nao segurou

O gate existe (`useAttendanceGate.js` — o comentario no topo do arquivo descreve exatamente este
bug), mas ele **avisa** e oferece "Enviar mesmo assim". O bloqueio duro so acontece com
`takeover_request_gate` ligado **e** dono humano. Se a conversa alheia estiver com a IA ou na fila
sem dono, o botao fica liberado — e a mensagem vaza.

---

## Fix minimo

### Backend — `Api::V1::Accounts::ConversationsController#create`

Depois do builder, decidir o que fazer quando a conversa **ja existia** (Rails 7.1:
`@conversation.previously_new_record?` distingue criada de reusada):

```ruby
def create
  ActiveRecord::Base.transaction do
    @conversation = ConversationBuilder.new(params: params, contact_inbox: @contact_inbox).perform
    adopt_or_block_reused_conversation
    self_assign_creator_for_reply_gate if params[:message].present?
    Messages::MessageBuilder.new(Current.user, @conversation, params[:message]).perform if params[:message].present?
  end
end
```

Regra do `adopt_or_block_reused_conversation`:

1. conversa **nova** (`previously_new_record?`) → segue como hoje;
2. conversa reusada **sem dono e sem time** → aplica o `assignee_id`/`team_id` que vieram do modal.
   E o caso comum (fila/IA): a conversa passa a ser dela, ela abre normal e o comportamento vira o
   que o agente espera;
3. conversa reusada **com dono ou time de outro** e que o usuario **nao pode abrir** (mesma regra do
   `ConversationTeamAccessConcern#team_access_exempt?` + `AgentConversationIsolation.hidden_from?`)
   → **nao grava a mensagem**: `render` 403 com `error_code: 'conversation_access_blocked'` e o
   mesmo `meta` do `AgentConversationAccessConcern` (dono, time, pedido pendente), abortando a
   transacao;
4. conversa reusada que ele **pode** abrir → segue como hoje.

O ponto inegociavel e o 3: hoje a mensagem sai antes de qualquer checagem.

### Frontend — dois pontos pequenos

- `store/modules/contactConversations.js`, action `create`: o `catch` faz `throw new Error(error)`,
  o que **destroi** o objeto do axios — `error.response` some e o compose nunca consegue ler o
  `error_code`. Trocar por `throw error`.
- `ComposeConversation.vue#performCreateConversation` (`:241-284`): no `catch`, se
  `error.response?.data?.error_code === 'conversation_access_blocked'`, reaproveitar o
  `AttendanceWarningDialog` (ja montado no arquivo) com o `meta` da resposta — "este contato ja esta
  em atendimento com o time X" + Solicitar — em vez do alerta generico. Minimo aceitavel: um
  `useAlert` com essa frase.

### Fora de escopo (nao fazer agora)

- Mexer na regra de reuso do WAHA (`waha_api_inbox?`) ou no `lock_to_single_conversation` — a
  deduplicacao existe por um motivo e mudar isso e decisao de produto.
- Trocar o texto fixo do `ConversationView.vue:211` pela mensagem que o backend manda
  (`conversations.team_access.forbidden`, que em pt-BR ja diz "Esta conversa e de outro time"). Vale
  a pena, mas e outro PR.

---

## Como validar

**Specs (request):**

1. Agente do time A, caixa WAHA, contato com conversa `open` do time B → `POST /conversations` com
   `team_id` do time A responde **403** e **nenhuma** `Message` e criada (hoje responde 200 e cria).
2. Mesmo cenario, conversa existente **sem** assignee e **sem** team → responde 200, a conversa fica
   com `assignee_id` do criador e `team_id` do modal, e o `GET /conversations/:display_id` do mesmo
   agente responde 200.
3. Conversa existente ja atribuida ao proprio agente → 200 e a mensagem entra (nao regredir).

**Em campo (staging nicolas, conta 1):** com dois agentes de times diferentes, mandar pelo modal
"Nova conversa" para um contato que ja tem conversa aberta do outro time. Antes: mensagem entregue +
modal vermelho. Depois: aviso explicando de quem e o atendimento, sem mensagem enviada.

**Leitura para confirmar na VM do cliente (sem alterar nada), com o telefone do contato em maos:**

```ruby
c = Contact.find_by(phone_number: '+55...')
c.conversations.order(created_at: :desc).limit(5).map { |x|
  { id: x.display_id, inbox: x.inbox_id, status: x.status, team: x.team_id, assignee: x.assignee_id }
}
```

O esperado pelo diagnostico: a conversa para onde ela foi jogada tem `team_id` de um time do qual a
Leticia nao e membro (`User#teams`), e `assignee_id` de outra pessoa ou `nil`.

---

## Contexto

Mesma familia do P11 (`ConversationTeamAccessConcern`, commit d9046246b) e do isolamento por agente:
as travas cobrem a conversa e os sub-recursos, mas `POST /conversations` continua sendo porta
lateral. O aviso da Fase 2 (`useAttendanceGate`) foi feito para avisar o agente; falta a trava no
servidor.
