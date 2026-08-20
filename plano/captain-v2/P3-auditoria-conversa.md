# P3 — Auditoria funcional da tela de conversa

**Data:** 28/07/2026 · **Ambiente:** homologação (VM 192.168.8.232), branch `homologacao`, app em `http://localhost:3000`
**Usuário de teste:** `playwright-test@simplex.local` (admin nas contas 1 e 3)
**Método:** inventário pelo código + exercício real via Playwright 1.59.1 (headless Chromium), com captura de console, `pageerror` e requests HTTP.

## Conversas usadas

| conversa | o que é | uso |
|---|---|---|
| **444** (`id=2405`) | grupo WhatsApp real — inbox `spx` (Channel::Api → webhook WAHA) | só leitura + prioridade (revertida). **Nenhuma mensagem enviada.** |
| **485** (`id=2446`) | grupo WhatsApp real — inbox `simplexteste` | só leitura (mídias, integrantes). **Nenhuma mensagem enviada.** |
| **710** (`id=2674`) | **conversa de teste que criei** via widget web (inbox 6 `Suporte CHAT - SPX`, contato `rough-dawn-436`) — inbox sem webhook externo | todos os testes de escrita, envio, status, IA e ações destrutivas-reversíveis |

> A inbox 6 é `Channel::WebWidget` e **não tem webhook**: nada do que enviei ali saiu para número real. Todas as inboxes `Channel::Api` da conta 3 apontam para `waha.simplexsolucoes.com.br` — por isso nenhuma delas foi usada para envio.

---

## Resumo executivo

Testei **47 ações**. O núcleo do atendimento (enviar, nota privada, resolver, atribuir, rotular, anexar, responder/citar, encaminhar) **funciona**. O que quebra são as camadas que foram empilhadas por cima: busca, IA, integrações externas e dois botões que nunca foram ligados.

| | qtd |
|---|---|
| ✅ FUNCIONA | 31 |
| ⚠️ FUNCIONA COM PROBLEMA | 5 |
| ❌ QUEBRADA | 6 |
| 🚫 NÃO TESTADO | 5 |

**As 6 quebradas:** busca na conversa (só enxerga 3 meses), favoritar mensagem (função inexistente), traduzir (integração ausente, falha em silêncio), Copilot/IA inteiro (chave OpenAI inválida), aba CRM (domínio morto), aba SPX Dashboard (404).

---

## 1. Cabeçalho da conversa

`app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`

| ação | onde | funciona? | evidência | observação |
|---|---|---|---|---|
| Resolver | `buttons/ResolveAction.vue:272-281` | ✅ | `POST /conversations/710/toggle_status` → `200 {"current_status":"resolved"}` | Abre gate **"Selecionar Time"** antes (`useResolveValidation`) — correto por design |
| Reabrir | `ResolveAction.vue:282-291` | ✅ | `200 {"current_status":"open"}`; pill alterna Resolvida ⇄ Não atribuída | — |
| Abrir (de pendente/adiada) | `ResolveAction.vue:292-301` | ✅ | botão troca conforme status | — |
| **Deixar pendente** | `ResolveAction.vue:338-349` | **❌** | `422 POST /toggle_status` → `{"message":"Status não pode ser Pendente — recurso desativado para esta caixa de entrada"}` | Ver **Achado 1** |
| Adiar (snooze) | `ResolveAction.vue:326-337` → `openSnoozeModal()` | **⚠️** | abre `ninja-keys` sem nenhuma opção listada; rodapé em inglês ("to select", "to navigate", "esc to close", "move to parent") | Ver **Achado 2** |
| Prioridade (inline no header) | `ConversationHeader.vue:474-511` | ⚠️ | setei "Baixa" → `priority="low"` no banco; revertido para `nil` | Funciona, mas **não emite toast** (`setPriority:388-396` não chama `useAlert`, ao contrário do mesmo controle na sidebar) |
| Buscar na conversa | `ConversationMessageSearch.vue` | **❌** | `GET /search/messages?q=aguardando&conversation_id=444` → `200 {"messages":[]}` com **325 mensagens** contendo o termo | Ver **Achado 3** |
| Bloquear contato | `MoreActions.vue:83-99` | ✅ | `POST /conversations/710/mute` → 200; `blocked:true`; item vira "Desbloquear" | Revertido |
| Desbloquear contato | `MoreActions.vue:92-98` | ✅ | `POST /unmute` → 200; `blocked:false` | — |
| Enviar transcrição | `MoreActions.vue:101-106` → `EmailTranscriptModal` | ✅ | modal abre: "Enviar transcrição… / para o agente designado / para outro endereço" | Não disparei o envio |
| Compartilhar no chat interno | `MoreActions.vue:74-81` | ✅ | modal "Compartilhar conversa no chat interno — conversa #710" + lista de pessoas | Flag `internal_chat` ON na conta 3 |
| Devolver para a IA (re-triagem) | `MoreActions.vue:65-72` | 🚫 | não apareceu no kebab | Só aparece se a conversa for minha **e** houver assistente com `agent_bot_id` na inbox. Caminho existe (`store.dispatch('retriage')`), com `window.confirm` antes |
| Selo de status (pill) | `components-next/Conversation/ConversationStatusActions.vue` | ✅ | reflete Em atendimento / Resolvida / Não atribuída | Read-only por design |
| Janela 24h WhatsApp | `ConversationHeader.vue:233-303` | ✅ | render condicional a canal WhatsApp; não apareceu nas inboxes Api | Lógica correta, canal não bate |
| Badge de grupo + contagem | `ConversationHeader.vue:430-437` | ✅ | 444 mostrou "Grupo · 8 participantes" | — |

---

## 2. Composer

`app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` (3467 linhas)

| ação | onde | funciona? | evidência | observação |
|---|---|---|---|---|
| Enviar resposta pública | `ReplyBox.vue:3243-3257` | ✅ | msg `id=36067` `type=outgoing private=false status=sent` no banco | Testado só na conversa de teste 710 |
| Gate "Conversa sem responsável" | `useReplyAssignmentGate` | ✅ | modal "Atribua a conversa a você para enviar" → "Atribuir a mim e enviar" atribuiu e enviou | Excelente comportamento |
| Nota privada (cadeado) | `ReplyBox.vue:3190-3200` | ✅ | `aria-pressed` false→true, título muda, pill ganha `--private` | — |
| Enviar nota privada | idem | ✅ | msg `id=36065` `private=true` | Nota **não** passa pelo gate de atribuição — correto |
| Emoji | `ReplyBox.vue:3152-3160` | ✅ | picker abre (1857 botões), clique inseriu `😙` no editor | ⚠️ servidor sem fonte de emoji: vira tofu no screenshot (ambiente, não bug) |
| Anexar arquivo | `ReplyBox.vue:3093-3098` | ✅ | filechooser abre; preview fullscreen estilo WhatsApp com nome, tamanho (27 B) e "Adicionar uma legenda…" | — |
| Resposta pronta `/atalho` | `ReplyBox.vue:3119-3125` + editor | ✅ | digitei `/tes` → dropdown com `/teste`; clique inseriu `aaa` | Conta 3 tem 1 canned response |
| Resposta pronta (menu "+") | `ReplyBox.vue:3119-3125` | ✅ | item "Resposta pronta" presente | — |
| Agendar mensagem | `ReplyBox.vue:3099-3105` | ✅ | modal "Agendar envio" com atalhos: Em 1 hora / Hoje à noite (20h) / Amanhã às 9h / Próxima segunda às 9h + data-hora exata | Não agendei de fato |
| Compartilhar localização | `ReplyBox.vue:3127-3133` | ✅ | modal com mapa Leaflet/OpenStreetMap + fallback CEP+Número | "Permissão de GPS negada" é do headless; fallback funciona |
| Compartilhar contato | `ReplyBox.vue:3135-3141` | ✅ | modal lista contatos com telefones | — |
| Gravar áudio (mic) | `ReplyBox.vue:3258-3267` | 🚫 | `pageerror: Error accessing the microphone: Requested device not found` | Servidor sem microfone. **O erro escapa como exceção não tratada** — vale envolver em try/catch com toast |
| Botão enviar aparece/some | `ReplyBox.vue:3242-3277` | ✅ | com texto → ✈️; sem texto → 🎤 | Transição correta |
| Atalho `Alt+P` (nota privada) | `WootWriter/ReplyTopPanel.vue:133-142` | ✅ | `aria-pressed` → `true` | — |
| Atalho `Alt+L` (resposta) | idem | ✅ | `aria-pressed` → `false` | — |
| Atalho `Alt+M` (menu resolver) | `ResolveAction.vue:238-241` | ✅ | abriu dropdown com Resolver/Adiar/Deixar pendente | — |
| Atalhos `Alt+E` / `Ctrl+Alt+E` | `ResolveAction.vue:242-260` | 🚫 | não exercitados (evitar resolver em cascata) | Código presente |
| Assinatura | `ReplyBox.vue:634, 1227-1228, 1693-1700` | 🚫 | toggle só renderiza se `messageSignature` existir; `User#52.message_signature = nil` | Não alterei o perfil de teste |
| Templates WhatsApp | `ReplyBox.vue:3106-3111` | 🚫 | `showWhatsappTemplates` false nas inboxes testadas | Só canal WhatsApp nativo |
| Mensagem interativa (botões/lista) | `ReplyBox.vue:3143-3149` | 🚫 | `showInteractiveMessage` false | Depende de inbox WAHA — ver **Achado 6** |
| Sugestão fantasma (Tab p/ aceitar) | `ReplyBox.vue:2944-2951` | ❌ | `POST /ghost_suggestion` → `200 {"suggestion":null,"language":"pt-BR"}` | Consequência do **Achado 4** (chave OpenAI) |

---

## 3. Menu de contexto da mensagem

`app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` · gates em `components-next/message/Message.vue:558-596`

Itens que aparecem numa mensagem outgoing minha: **Responder mensagem · Encaminhar mensagem · Copiar · Traduzir · Copiar link para a mensagem · Adicionar às respostas prontas · Favoritar mensagem · Excluir**

| ação | onde | funciona? | evidência | observação |
|---|---|---|---|---|
| Responder / citar | `MessageContextMenu.vue:219-227` | ✅ | item presente e clicável; emite `replyTo` | — |
| Encaminhar mensagem | `MessageContextMenu.vue:228-236` | ✅ | entra em modo seleção: barra "1 selecionada(s)" + botão Encaminhar | — |
| Copiar | `MessageContextMenu.vue:237-245` | ✅ | `copyTextToClipboard` + toast | — |
| **Traduzir** | `MessageContextMenu.vue:246-254` | **❌** | `POST /messages/36062/translate` → `200` **corpo vazio**; nada muda na bolha; nenhum aviso | Ver **Achado 5** |
| Copiar link da mensagem | `MessageContextMenu.vue:256-264` | ✅ | monta permalink `?messageId=` | — |
| Adicionar às respostas prontas | `MessageContextMenu.vue:265-273` | ✅ | abre `AddCannedModal` | — |
| **Favoritar / Desfavoritar** | `MessageContextMenu.vue:283-300` → `Message.vue:697-725` | **❌** | console: `Error starring message: TypeError: MessageApi.starMessage is not a function`; **zero requests** | Ver **Achado 7** |
| Excluir mensagem | `MessageContextMenu.vue:328-336` | ✅ | item presente; abre `woot-delete-modal` | **Não executado por segurança** |
| Editar mensagem | `Message.vue:591-594` | 🚫 | gated por `props.isWahaInbox` | Ver **Achado 6** |
| **Reagir** | — | **não existe** | `MessageReactions` é sempre `readonly` (`Message.vue:989-995`, `MessageList.vue:491`) | Ver **Achado 8** |

---

## 4. Painel lateral (contato + conversa)

`app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`

| ação | onde | funciona? | evidência | observação |
|---|---|---|---|---|
| Abrir/fechar painel | `ConversationHeader.vue:52-57` | ✅ | clique no nome do contato alterna | Estado persiste em `uiSettings` — **fecha e não volta sozinho** ao usar Copilot/abas; confunde |
| Editar contato | `contact/ContactInfo.vue` | ✅ | modal "Editar contato — rough-dawn-436" com nome, e-mail, telefone, empresa, país | Não salvei |
| **Mesclar contato** | idem | ✅ | modal "Mesclar contatos" com principal / a ser excluído | **Não executado por segurança** |
| **Excluir contato** | idem | ✅ | modal "Confirmar Exclusão — Não, Mantenha / Sim, Excluir" | **Não executado por segurança** |
| Atribuir agente | `ConversationAction.vue:578-591` | ✅ | "Atribuir a mim" atribuiu; atividade registrada na timeline | — |
| Atribuir time | `ConversationAction.vue:599-611` | ✅ | time `teste-flow-team` aplicado no gate de resolução | — |
| Prioridade (sidebar) | `ConversationAction.vue:619-633` | ✅ | dropdown com Nenhuma/Urgente/Alta/Média/Baixa | Este **emite toast**, ao contrário do do header |
| Rótulos | `conversation/labels/LabelBox.vue` | ✅ | adicionei `triagem` → persistiu (`label_list=["triagem"]`) + atividade na timeline | Só na conversa de teste |
| Participantes da conversa | `ConversationParticipant.vue` | ✅ | "1 pessoa está participando — Você está participando" | — |
| **Integrantes do grupo** | `GroupParticipants.vue` | ⚠️ | 444: 8 integrantes com badges ADMIN ✅ · 485: "Sincronizar agora" → `GET /waha_group` → `200 {"ok":false,"status":"failed","reason":"circuit_open"}` | Ver **Achado 9** |
| Mídias e Arquivos | `ConversationMedia.vue` | ✅ | "Baixar todas (3) · Selecionar · Imagens (3)" | — |
| Situação no Kanban | `KanbanStatus.vue` | ✅ | mostra quadros "Geral / Resolvidos / há 25 dias" com "Abrir no Kanban" | — |
| Informação da conversa | `ConversationInfo.vue` | ✅ | acordeão abre | — |
| Atributos do contato | `customAttributes/CustomAttributes.vue` | ✅ | acordeão abre | — |
| Notas do contato | `contact/ContactNotes.vue` | ✅ | acordeão abre | — |
| Conversas anteriores | `ContactConversations.vue` | ✅ | acordeão abre | — |
| Reordenar seções (drag) | `ContactPanel.vue:181-190` (`vuedraggable`) | 🚫 | não exercitei drag-and-drop | — |
| **Macros** | `Macros/List.vue` | ⚠️ | flag `macros` ON na conta 3, mas **`Macro.where(account_id:3)` = 0 registros** → seção não renderiza (`hasMacros`) | Não é bug: não há macro cadastrada. Vale saber que ninguém usa |
| Sequências de Follow-up | `MessageSequenceWidget.vue` | ✅ | "Nenhuma sequência ativa. Crie uma em Configurações." | — |
| Shopify / Linear | `ShopifyOrdersList.vue`, `linear/IssuesList.vue` | 🚫 | integrações não configuradas na conta 3 | Só `openai` está em `Integrations::Hook` |

### Abas do painel central

| ação | onde | funciona? | evidência | observação |
|---|---|---|---|---|
| Mensagens | tab padrão | ✅ | — | — |
| **CRM** | `dashboard_apps` (conta 3) → `https://crmspx.simplexsolucoes.com.br/` | **❌** | `curl` → **000** (conexão falha); iframe cai em `chrome-error://chromewebdata/`; console: `Failed to execute 'postMessage'… recipient window's origin ('null')` | Ver **Achado 10** |
| **SPX Dashboard** | `dashboard_apps` → `https://marketplace.simplexsolucoes.com.br` | **❌** | `curl` → **404**; iframe renderiza literalmente **"404 page not found"** | Ver **Achado 10**. Título cadastrado com espaço à esquerda: `" SPX Dashboard"` |

---

## 5. IA / Copilot

| ação | onde | funciona? | evidência | observação |
|---|---|---|---|---|
| Botão ✨ no composer | `ReplyBox.vue:3206-3222` (`data-testid="ai-button"`) | ✅ (abre) | menu abre com **15 ações** | Abrir funciona; executar não |
| Painel Copilot (lateral) | `CopilotMenuBar.vue` | ✅ (abre) | "Copiloto IA · Lia" + atalhos: Resumir esta conversa / Sugerir uma resposta / Quem deve atender? / Histórico do contato | — |
| **Executar qualquer ação de IA** | `enterprise/app/jobs/captain/copilot/response_job.rb:57-72` | **❌** | thread criada (`POST /captain/copilot_threads` → 200, thread 41), resposta: **"O Capitão não conseguiu gerar uma resposta agora. Tente novamente."** | Ver **Achado 4** |
| Resumo da IA (sidebar) | `ConversationSummary.vue` | ❌ | "A IA ainda não resumiu este atendimento." | Mesma causa |
| Assuntos e Tarefas | `ConversationChecklist.vue` | ❌ | "Nenhum assunto identificado ainda." | Mesma causa |

Ações oferecidas pelo menu ✨ (todas bloqueadas pela mesma causa): Resumir o que rolou · Sugerir uma resposta · Melhorar · Encurtar · Analisar tom do cliente · Corrigir só ortografia · Deixar mais formal / amigável / informal / firme / direto ao ponto · Expandir · Perguntar ao Copilot.

> Cumpri a regra: **não disparei IA contra conversa de cliente**. Todo teste de IA foi na conversa de teste 710.

---

# Achados detalhados

## Achado 1 — ❌ "Deixar pendente" aparece mesmo desativado e falha com erro genérico

**Onde:** `app/javascript/dashboard/components/buttons/ResolveAction.vue:338-349`

`pending_status_enabled = false` em **todas as 9 inboxes da conta 3**. O menu de contexto da *lista* de conversas checa a flag corretamente (`components/widgets/conversation/contextMenu/Index.vue:214`), mas o dropdown do botão **Resolver dentro da conversa não checa**.

```
POST /api/v1/accounts/3/conversations/710/toggle_status
→ 422 {"message":"Status não pode ser Pendente — recurso desativado para esta caixa de entrada","attributes":["status"]}
```

O front descarta a mensagem do backend e mostra o genérico `CONVERSATION.CHANGE_STATUS_FAILED` (`ResolveAction.vue:178`). O agente vê "Falha ao mudar o status" sem saber por quê.

**Correção:** replicar a checagem de `currentInbox.pending_status_enabled` no `v-if` do item, e propagar `error.response.data.message` no toast.

## Achado 2 — ⚠️ "Adiar" abre uma command bar vazia com texto em inglês

**Onde:** `ResolveAction.vue:142-145` → `document.querySelector('ninja-keys').open({parent:'snooze_conversation'})`

Abre o `ninja-keys` no meio da tela com o placeholder *"Digite um horário, por exemplo: amanhã, 2 horas, próxima sexta-…"* e **nenhuma opção pré-listada**. O rodapé de ajuda vem em inglês: `to select · to navigate · esc to close · move to parent`.

Comparação direta: "Agendar mensagem" (no composer) tem atalhos prontos — *Em 1 hora, Hoje à noite (20h), Amanhã às 9h, Próxima segunda às 9h*. "Adiar" faz o agente adivinhar a sintaxe.

## Achado 3 — ❌ "Pesquisar na conversa" só enxerga os últimos 3 meses (sem avisar)

**Onde:** `app/services/search_service.rb:100`

```ruby
query = current_account.messages.where(inbox_id: accessable_inbox_ids)
                       .where('created_at >= ?', 3.months.ago)   # <-- aqui
```

`message_base_query` aplica o corte de 3 meses **antes** de filtrar por `conversation_id`. Resultado medido na conversa 444:

| termo | mensagens que contêm | dentro de 3 meses | resultado da busca |
|---|---|---|---|
| `aguardando` | **325** | 0 | `200 {"messages":[]}` |
| `Responsável` | muitas | 0 | `200 {"messages":[]}` |
| `Conversa` | — | 2 | 2 resultados (ambos de atividade) |

Mensagem mais recente com "aguardando": `2025-12-04`. Corte: `2026-04-28`. O agente pesquisa algo que ele mesmo está vendo na tela e não acha nada — e a UI mostra o texto neutro de "sem resultados", como se o termo não existisse.

**Correção:** quando `params[:conversation_id]` está presente, o escopo já é uma conversa só — o corte temporal não protege índice nenhum e deveria ser dispensado (ou virar um aviso explícito na UI).

## Achado 4 — ❌ Todo o Copilot / IA da conversa está morto (chave OpenAI inválida)

Reproduzido diretamente (na conversa de teste):

```
RubyLLM::UnauthorizedError: Incorrect API key provided: sk-proj-****uiAA.
  ruby_llm-1.9.2/lib/ruby_llm/error.rb:54 parse_error
```

`Captain::Copilot::ResponseJob` captura como `StandardError` genérico (`response_job.rb:57`) e grava o fallback `captain.copilot.failure` = *"O Capitão não conseguiu gerar uma resposta agora."* — mensagem que **não distingue chave inválida de timeout ou bug**.

A chave vem de `ENV['OPENAI_API_KEY']` (164 chars) e também está em `InstallationConfig CAPTAIN_OPEN_AI_API_KEY`. Efeito colateral: `POST /ghost_suggestion` sempre devolve `{"suggestion":null}`, "Resumo da IA" e "Assuntos e Tarefas" ficam vazios para sempre.

**Correção:** trocar a chave na homologação. Além disso, `Llm::Config::MissingAccountApiKeyError` já tem tratamento próprio (`response_job.rb:25`) — vale capturar `RubyLLM::UnauthorizedError` no mesmo bloco, para o agente ver "credencial inválida" em vez de "tente novamente" (que ele vai tentar, indefinidamente).

## Achado 5 — ❌ "Traduzir" não faz nada e não avisa

**Onde:** `app/controllers/api/v1/accounts/conversations/messages_controller.rb:104-113` + `app/services/messages/translate_service.rb`

A integração `google_translate` **não existe** na conta 3 (`Integrations::Hook.where(account_id:3)` = apenas `[["openai","enabled"]]`). O processador devolve `nil`, o controller responde `head :ok` (200 sem corpo), o front não trata e **não mostra nada**.

```
POST /api/v1/accounts/3/conversations/710/messages/36062/translate → 200 (corpo vazio)
message.content_attributes depois: {"in_reply_to" => nil}   # nada persistido
```

O item fica visível no menu de contexto de toda mensagem com texto (`Message.vue:584`), sem depender da integração existir. Clicar = silêncio absoluto.

**Correção:** esconder "Traduzir" quando a integração não estiver ativa, **ou** devolver 422 com mensagem e exibir toast.

## Achado 6 — 🚫 Família WAHA inteira invisível: nenhuma inbox tem `waha_session_name`

`waha_session_name` é **`nil` nas 9 inboxes da conta 3** — inclusive nas que de fato são WAHA (`spx`, `simplexteste`, com webhook `waha.simplexsolucoes.com.br`).

Tudo que depende disso fica inacessível na homologação:

- **Editar mensagem** — `Message.vue:567-572` (`canEditBase` exige `props.isWahaInbox`, derivado de `!!inbox?.waha_session_name` em `MessagesView.vue:139-141`)
- **Mensagem interativa (botões/lista)** — `ReplyBox.vue:3143-3149`
- Roteamento de grupos em `message_builder.rb:218`, `conversation_builder.rb:42`, `contact_inbox_builder.rb:25`, `webhook_listener.rb:150`

Combinado com o banner permanente **"Uma conexão WhatsApp está com falha"** no topo de toda a aplicação, a leitura é: as conexões WAHA desta VM estão desvinculadas. Não consegui testar essas ações — não é possível afirmar se o código funciona.

## Achado 7 — ❌ "Favoritar mensagem" chama uma função que não existe

**Onde:** `app/javascript/dashboard/components-next/message/Message.vue:700` e `:715`

```js
await MessageAPI.starMessage({ accountId, conversationId, messageId });    // linha 700
await MessageAPI.unstarMessage({ accountId, conversationId, messageId });  // linha 715
```

A API client **não tem** esses métodos. O que existe é (`app/javascript/dashboard/api/inbox/message.js:170`):

```js
toggleStar(conversationId, messageId, currentlyStarred = false) { ... }
```

Assinatura diferente (posicional, não objeto) e nome diferente. Console no clique:

```
Error starring message: TypeError: MessageApi.starMessage is not a function
```

Nenhum request sai. O `catch` mostra "Erro ao favoritar mensagem" — então o agente vê um erro, mas **o recurso nunca funcionou nem por acaso**. Há um `Message.vue.backup` com o mesmo defeito nas linhas 456/471, o que sugere que veio de um refactor incompleto.

**Correção (1 linha cada):** `MessageAPI.toggleStar(props.conversationId, props.id, false)` / `(…, true)`.

## Achado 8 — ⚠️ O agente não pode reagir a mensagens

`MessageReactions.vue` **suporta** modo interativo (`picker`/`all` com `MessageApi.toggleReaction`, que existe em `message.js:159`), mas ambos os pontos de uso passam `readonly`:

- `Message.vue:989-995` — chips de reação recebidas do WhatsApp
- `MessageList.vue:491` — reações soltas

O próprio comentário do componente explica: *"não existe API para reagir de volta no WhatsApp"*. Ou seja, é decisão consciente — mas o resultado prático é que **"reagir" não está entre as opções do agente**, e o backend já tem o endpoint pronto.

**Bônus (poluição de console):** `Message.vue:162` declara `reactions: { type: Array }`, mas o serializer entrega um Object. Como `MessageList.vue:497` faz `v-bind="item.message"`, **toda mensagem renderizada** dispara:

```
[Vue warn]: Invalid prop: type check failed for prop "reactions". Expected Array, got Object
```

Numa conversa de 300+ mensagens são centenas de warnings — o console fica inutilizável para depurar qualquer outra coisa. E a prop `reactions` **nunca é lida** em `Message.vue` (única ocorrência é a declaração). Pode ser removida.

## Achado 9 — ⚠️ "Sincronizar integrantes" falha com circuit breaker aberto

Na conversa 485:

```
GET /api/v1/accounts/3/conversations/485/waha_group
→ 200 {"ok":false,"status":"failed","reason":"circuit_open","waha_group":null}
```

UI mostra *"Não foi possível carregar os integrantes / Tentar novamente"* — **mensagem honesta**, sem inventar "0 participantes". Bem feito. Mas a função não entrega: na 485 continua "Integrantes ainda não sincronizados". Na 444, onde havia snapshot salvo, os 8 integrantes aparecem certinho com badges ADMIN. Mesma raiz do Achado 6 (WAHA fora do ar nesta VM).

## Achado 10 — ❌ As duas abas de integração da conta 3 estão mortas

Cadastradas em `dashboard_apps` (conta 3):

| aba | URL | `curl` | o que o agente vê |
|---|---|---|---|
| `CRM` | `https://crmspx.simplexsolucoes.com.br/` | **000** (não conecta) | tela em branco (`chrome-error://chromewebdata/`) |
| `" SPX Dashboard"` | `https://marketplace.simplexsolucoes.com.br` | **404** | literalmente **"404 page not found"** |

Console: `Failed to execute 'postMessage' on 'DOMWindow': The target origin provided ('https://crmspx.simplexsolucoes.com.br') does not match the recipient window's origin ('null')`.

Detalhe extra: ao trocar de aba o iframe anterior **não é desmontado** (fica `0x0`) — dois iframes de domínio externo carregados por conversa aberta.

Duas abas ocupando espaço permanente no topo do painel central, ambas entregando erro. O título `" SPX Dashboard"` tem um espaço à esquerda no cadastro.

---

# Ranqueamento por impacto no dia a dia

### 🔴 Quebrado e dói muito

1. **Busca na conversa cega para tudo além de 3 meses** (Achado 3) — é a ferramenta que o agente usa quando o cliente diz "mas eu já te falei isso". Falha em silêncio, o que é pior que falhar com erro: o agente conclui que a informação não existe. Numa conversa de grupo com 1845 mensagens (a 416), a busca é a única forma de navegar. `search_service.rb:100`, correção de uma linha.

2. **Copilot/IA inteiro morto** (Achado 4) — 15 ações no menu ✨ + painel lateral + resumo automático + sugestão fantasma, tudo devolvendo "tente novamente". É o recurso mais vendido da tela e o que menos entrega hoje. Correção é operacional (trocar a chave), mas o tratamento de erro precisa distinguir credencial inválida de falha transitória — senão o agente tenta de novo para sempre.

3. **"Deixar pendente" oferecido e rejeitado** (Achado 1) — status é fluxo de trabalho. O agente clica, leva "Falha ao mudar o status" e não descobre que o recurso está desligado na inbox. A checagem já existe no menu da lista; falta replicar no botão da conversa.

### 🟠 Quebrado, e o estrago é de confiança

4. **Aba CRM em branco + aba SPX Dashboard mostrando "404 page not found"** (Achado 10) — não atrapalha o atendimento, mas são duas abas fixas no topo entregando erro. É o tipo de coisa que faz o agente parar de confiar no resto da tela.

5. **"Traduzir" que não faz nada** (Achado 5) — clique → silêncio total, sem sequer um erro. Baixo uso provável (público pt-BR), mas o padrão "opção visível sem integração ativa" é o mesmo do Achado 1 e vale corrigir junto.

### 🟡 Quebrado e ninguém sente falta

6. **"Favoritar mensagem"** (Achado 7) — nunca funcionou; `starMessage` não existe. Como não há tela de "mensagens favoritas" em uso, a ausência não é sentida. Correção é trivial (2 linhas) — mas antes vale decidir se o recurso deve existir.

7. **Prioridade do header sem toast** — muda de verdade, só não confirma. Inconsistente com o mesmo controle na sidebar, que confirma.

### 🔵 Existe mas é confuso demais para servir

8. **"Adiar"** (Achado 2) — abre uma command bar vazia com instruções em inglês e exige que o agente adivinhe a sintaxe. O "Agendar mensagem" do composer resolveu o mesmo problema com atalhos prontos; "Adiar" ficou para trás.

9. **Painel lateral que fecha e não volta** — usar o Copilot ou trocar de aba fecha o painel de contato, e ele só volta clicando no nome do contato no cabeçalho — que não parece um botão. O agente perde acesso a rótulos, atribuição, prioridade e mídias sem entender o que fez.

10. **Menu "+" com 5 a 8 itens de peso muito diferente** — "Anexar arquivos" (uso diário) divide espaço com "Compartilhar localização" e "Compartilhar contato" (uso raro). Nada quebrado, só mal hierarquizado.

11. **Reagir não existe** (Achado 8) — em canal WhatsApp o cliente reage e o agente vê o chip, mas não pode responder na mesma moeda. O endpoint `toggleReaction` já existe no backend. É lacuna de produto, não bug.

12. **Macros: recurso ligado, zero cadastros** — flag `macros` ON na conta 3, nenhuma macro criada, seção não renderiza. Ou alguém cadastra, ou é peso morto na configuração.

### ⚫ Ruído que atrapalha diagnosticar tudo acima

13. **Centenas de `[Vue warn] reactions Expected Array, got Object` por conversa** (Achado 8, bônus) — uma prop declarada com tipo errado e **nunca usada** enche o console e esconde qualquer erro real. Remover `Message.vue:162` limpa tudo.

---

# Estado deixado no ambiente

| item | estado |
|---|---|
| Conversa **444** — prioridade | alterada para "Baixa" durante o teste, **revertida para "Sem prioridade"** ✅ (banco: `priority=nil`) |
| Conversa **444** — rótulos, status | intactos (`labels=[]`, `status=open`) ✅ |
| Conversa **485** | somente leitura, nada alterado ✅ |
| Contato `rough-dawn-436` | bloqueado durante o teste, **desbloqueado** ✅ (`blocked=false`) |
| **Conversa 710** (criada por mim, inbox de teste) | deixada **resolvida** — 2 mensagens minhas, rótulo `triagem`, time `teste-flow-team`. Fora da fila; pode ser apagada quando quiser |
| Thread Copilot 41 | criada durante teste da IA na conversa 710 |
| Código da aplicação | **nenhuma alteração** ✅ · nenhum commit, deploy, restart ou build ✅ |
| Banco | **somente SELECT** ✅ (escritas foram todas via UI) |
| Processos | nenhum puma isolado subido; serviço principal não reiniciado ✅ |

Scripts e screenshots da auditoria ficaram em
`/tmp/claude-1001/-home-chatwoot-chatwoot/fa5033d8-dd6c-41ba-ac83-487dd2fe97f5/scratchpad/` (fora do repositório).
