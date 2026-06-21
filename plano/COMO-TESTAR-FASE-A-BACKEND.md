# Como testar a IA como agente (Fase A) — pelo backend

> Estado: Fase A implementada (aceite final pode estar rodando ainda). App de homologação no ar.
> Ambiente: VM homologação (192.168.8.232). Conta de teste: **3 (SimplexIA)**, inbox **44**.
> ⚠️ Testar SÓ na conta 3 (sandbox). Não mexer em conta de cliente real.

## Espelhos da IA disponíveis (AgentBot, bot_type: captain)

| agent_bot_id | IA | conta | inbox ligada |
|---|---|---|---|
| **3** | **Clara** | 3 (SimplexIA) | **44 (SimplexIA)** ← usar esta |
| 4 | Clara | 1 | — |
| 5/6/7/8/9 | Júlia/Bruna/Letícia/Marina/Rafa | 1 | — |
| 10/11/12/13/14 | Júlia/Bruna/Letícia/Marina/Rafa | 3 | — |

A ideia central: a IA agora é um **AgentBot atribuível**. Atribuir a conversa ao espelho = a IA assume e responde. Atribuir um humano = a IA cala sozinha (callback de exclusividade).

---

## Opção A — Rails console (mais direto, sem token)

No servidor de homologação:

```bash
cd /home/chatwoot/chatwoot
RAILS_ENV=production bundle exec rails runner '
  inbox   = Inbox.find(44)                      # SimplexIA
  acc     = inbox.account                        # conta 3
  contact = acc.contacts.create!(name: "Teste Backend IA", phone_number: "+5599#{rand(10**8)}")
  ci      = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conv    = Conversation.create!(account: acc, inbox: inbox, contact: contact, contact_inbox: ci)

  # 1) ATRIBUI a conversa à IA (espelho Clara = agent_bot_id 3)
  Conversations::AssignmentService.new(conversation: conv, assignee_id: 3, assignee_type: "AgentBot").perform
  conv.reload
  puts "conversa #{conv.display_id}: assignee_agent_bot_id=#{conv.assignee_agent_bot_id} (esperado 3)"

  # 2) SIMULA mensagem do cliente -> dispara a IA (async, via Sidekiq)
  conv.messages.create!(account: acc, inbox: inbox, message_type: :incoming,
                        content: "Oi, quero informações", sender: contact)
  puts "mensagem de entrada criada. Aguarde alguns segundos e rode a verificação abaixo."
  puts "ID da conversa para conferir: #{conv.id}"
'
```

Depois de ~10-20s, ver a resposta da IA:

```bash
RAILS_ENV=production bundle exec rails runner '
  conv = Conversation.find(<ID_DA_CONVERSA>)
  conv.messages.order(:id).each { |m| puts "[#{m.message_type}] #{m.sender_type}: #{m.content&.truncate(80)}" }
'
```

**Esperado:** aparece uma mensagem `[outgoing] Captain::Assistant: ...` (a IA respondendo como agente).

### Teste do "IA cala" (o ponto-chave da Fase A)

```bash
RAILS_ENV=production bundle exec rails runner '
  conv = Conversation.find(<ID_DA_CONVERSA>)
  user = conv.account.users.first       # qualquer humano da conta
  Conversations::AssignmentService.new(conversation: conv, assignee_id: user.id).perform
  conv.reload
  puts "assignee_id=#{conv.assignee_id}  assignee_agent_bot_id=#{conv.assignee_agent_bot_id} (esperado: humano setado, bot = nil)"
'
```

**Esperado:** ao atribuir um humano, `assignee_agent_bot_id` volta a `nil` automaticamente → a IA para de responder.

---

## Opção B — via API HTTP (precisa de api_access_token de um admin da conta 3)

Atribuir a conversa à IA:

```bash
curl -X POST "http://localhost:3000/api/v1/accounts/3/conversations/<DISPLAY_ID>/assignments" \
  -H "api_access_token: <TOKEN_ADMIN_CONTA_3>" \
  -H "Content-Type: application/json" \
  -d '{"assignee_id": 3, "assignee_type": "AgentBot"}'
```

Resposta deve mostrar o AgentBot Clara como assignee. Depois mande uma mensagem de entrada na conversa (pelo canal/WhatsApp da inbox 44) e a IA responde.

Guard novo (admin-only): se usar um **token de agente comum** para atribuir a IA → retorna **403** (`conversations.captain.assignment_forbidden`).

---

## Ressalvas honestas (avisar quem for testar)

1. **A IA responder de verdade depende da chave LLM da conta estar configurada** na sandbox. Se a atribuição funciona (passos 1 e do "IA cala") mas não vem resposta, é a chave/credencial — não o trilho de atribuição.
2. **Sem a Fase B ainda**, a IA responde com o prompt/tools atuais — pode faltar `buscar_imovel` e o tom de atendente refinado. Pra testar "ela atende como agente atribuído" serve; o refinamento de comportamento é a fase seguinte.
3. **Não tem UI ainda** (Fase C): por enquanto a atribuição é por console/API, não pela tela.
4. É **working tree**, nada commitado. Se o servidor for reiniciado a partir do git limpo, as mudanças somem até voltar a branch/working tree.

5. **O front NÃO mostra a IA como responsável ainda.** Mesmo com a conversa atribuída à IA no backend (`assignee_agent_bot_id` setado), a tela não desenha "Clara" no campo de agente — isso é a **Fase C** (serializar assignee-IA + badge), ainda não feita. Por isso o nome que aparece no front pode ser o último humano (ex.: o usuário de teste). **Teste pelo backend** (console/API), conferindo `assignee_agent_bot_id` e a resposta — não pela tela.

---

## A IA JÁ está vinculada ao bot (não precisa criar)

Cada espelho nasce ligado ao seu assistant: **bot 3 = Clara (assistant 3)**, etc. Pra "usar" uma IA num teste, é só usar o **id do bot** da tabela acima como `assignee_id`. Não há passo de vínculo manual IA↔bot.

### Quer testar OUTRA IA (Júlia, Bruna...) numa inbox?

As outras IAs existem mas não têm inbox elegível. Pra tornar, por ex., a Júlia (bot 10 / assistant 10, conta 3) elegível numa inbox:

```bash
RAILS_ENV=production bundle exec rails runner '
  CaptainInbox.create!(captain_assistant_id: 10, inbox_id: 44)   # Júlia elegível na inbox 44
  puts "ok"
'
```

Depois é só atribuir a conversa ao **bot 10** (mesmo recipe da Opção A/B, trocando `assignee_id: 3` por `assignee_id: 10`). A elegibilidade (`CaptainInbox`) controla **quais IAs podem atuar** naquela inbox; a **atribuição** (assignee_agent_bot_id) controla **qual delas está atendendo** a conversa.
