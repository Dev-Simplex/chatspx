# A4 — Painel + cliente de streaming: o chat que o agente usa

**Data:** 28/07/2026 · VM 192.168.8.232 (homologação) · branch `homologacao` · **nada commitado**
**Escopo:** ligar o painel V2 ao streaming SSE e entregar os controles que fazem um chat de IA ser
utilizável. Fonte da verdade do design: `public/mockups/copiloto-v2.html`. Contratos: C1 e C2 do
`plano/captain-v2/20-BRIEFING-EXECUCAO.md`.

---

## 1. O que mudou (arquivo por arquivo)

### Arquivos novos

| Arquivo | Linhas | Papel |
|---|---|---|
| `app/javascript/dashboard/api/captain/copilotStream.js` | 251 | **Ponto único de troca do transporte.** URL do endpoint (C1), headers de auth, `openHttpStream` (fetch + ReadableStream), `openFakeStream` (emissor falso local) e `CopilotStreamHttpError` |
| `…/ai-assistant/composables/sseParser.js` | 143 | Parser SSE incremental (WHATWG), tolerante a frame partido entre chunks de rede |
| `…/ai-assistant/composables/useCopilotStream.js` | 353 | Cliente do stream: ordem, reconexão, cancelamento real, watchdog de inatividade, classificação de erro |
| `…/ai-assistant/composables/useCopilotThread.js` | 261 | Thread + histórico por conversa (carrega, cria, cacheia, trunca) |
| `…/ai-assistant/composables/useCopilotAssistant.js` | 47 | Escolhe qual `Captain::Assistant` embasa a thread (mesma precedência do `CopilotContainer`) — **só leitura**, nunca escreve no assistente |
| `…/ai-assistant/composables/useComposerInsert.js` | 55 | "Usar como resposta": reaproveita os bus events que o Copilot V1 já usa |
| `…/ai-assistant/composables/useCopilotShortcuts.js` | 84 | Ctrl/Cmd+J invoca · Tab aceita · Esc descarta |

### Arquivos alterados

| Arquivo | O que mudou |
|---|---|
| `…/ai-assistant/AIAssistantPanel.vue` | **Reescrito.** Era uma chamada síncrona a `processEvent('reply_suggestion')` com o texto digitado virando *rótulo* de uma ação fixa; agora é um chat de verdade sobre SSE, com thread persistida, parar / refazer / editar / usar como resposta, composer em pill e os três atalhos. Saiu todo o `purple-600` literal (C2 §3) |
| `…/ai-assistant/composables/useTypewriter.js` | Ganhou **modo "seguir o stream"** (`useTypewriter.js:113-137`) e **catch-up** (`:76-94`). Antes, cada token novo chamava `start()` e **reanimava do zero** — com streaming real o texto piscaria e ficaria atrás do servidor. Agora, quando o texto cresce por acréscimo, ele continua de onde parou e acelera se a fila aumenta. Os 8 specs pré-existentes continuam verdes |

### Specs novos (63 testes)

`…/composables/spec/sseParser.spec.js` (11) · `…/composables/spec/useCopilotStream.spec.js` (10) ·
`…/composables/spec/useCopilotThread.spec.js` (12) · `…/composables/spec/useCopilotShortcuts.spec.js` (9) ·
`…/composables/spec/useComposerInsert.spec.js` (5) · `…/spec/AIAssistantPanel.spec.js` (10) ·
`app/javascript/dashboard/api/captain/specs/copilotStream.spec.js` (11 — a prova de streaming)

---

## 2. Cliente SSE (item 1 da missão)

### Rota — **precisa do aval do A1**

O briefing escreveu `POST /api/v1/accounts/:id/copilot_threads/:thread_id/stream`, mas o recurso real
no `config/routes.rb:77` é `captain/copilot_threads`. Assumi o caminho com o prefixo:

```
POST /api/v1/accounts/:account_id/captain/copilot_threads/:thread_id/stream
```

Se o A1 tiver usado outro, a troca é **uma constante**: `COPILOT_STREAM_PATH` /
`buildStreamUrl` em `api/captain/copilotStream.js:23,42`. Nada mais no front conhece a URL.

**Não uso `EventSource`**: ele é GET-only e não carrega os headers `access-token/client/uid` do
devise-token-auth. Uso `fetch` + `ReadableStream`, que é o mesmo desenho do cliente da OpenAI.

### Ordem preservada

Uma resposta HTTP é um fluxo de bytes ordenado — a ordem vem do transporte, não de reordenação no
cliente. O que o parser garante é que **nunca renderizamos meio frame**: o evento só é emitido
quando a linha em branco fecha o registro (`sseParser.js:60-75`), mesmo que a rede tenha cortado no
meio do JSON. Testado com corte no meio do nome do campo (`sseParser.spec.js:23`).

### Reconexão

- **Só reconecta** falha de conexão (socket caído, stream fechado antes do `done`): 2 tentativas,
  backoff 800ms → 2000ms.
- **Nunca reconecta** erro HTTP: 401 continua 401. Reenviar não conserta credencial e só queima
  tempo do agente (`useCopilotStream.js:291-306`).
- **Sem duplicar texto:** se o servidor numera os frames (`id:`), mando `Last-Event-ID` e descarto
  os ids já vistos; se **não** numera, assumo replay integral e **zero o buffer** antes de reconectar.
  Os dois caminhos têm spec (`useCopilotStream.spec.js` — "does not duplicate", "drops frames already seen").

### Cancelamento de verdade

`stop()` chama `AbortController.abort()` no fetch → o socket fecha → por C1 o servidor detecta o
disconnect e mata o job. **Não é um "some da tela"**: o spec captura o `AbortSignal` que foi para o
transporte e afirma `signal.aborted === true` (`useCopilotStream.spec.js:104`).

### Nada de spinner infinito

Watchdog de inatividade de **30s** rearmado a cada frame (`useCopilotStream.js:123-131`): servidor
mudo vira erro `timeout` com botão de tentar de novo, não uma ampulheta eterna.

### Emissor falso (desenvolvimento sem backend)

`localStorage.chatspx_copilot_fake_stream = '1'` troca a rede pelo emissor local
(`copilotStream.js:88-177`). A decisão fica dentro do módulo de transporte — o painel e o composable
não sabem se estão falando com o servidor ou com o falso.

---

## 3. Os controles (item 2)

| Controle | Onde | Comportamento |
|---|---|---|
| **Parar** | `AIAssistantPanel.vue` — `[data-testid="ai-stop-streaming"]`, `v-if="isStreaming"` | Só aparece durante a geração. Aborta a conexão. O texto parcial fica, com a nota "Você parou aqui." Também escuto `@cancel-streaming` do `AIMessageBubble` (o A3 desenha um Parar próprio na régua da bolha) |
| **Refazer** | botão `REGENERATE` | Trunca a partir da última pergunta e re-envia a mesma pergunta |
| **Editar a pergunta** | botão `EDIT_QUESTION` | Devolve a pergunta ao composer, mostra "Editando a pergunta" + Cancelar; ao enviar, a pergunta antiga **e a resposta dela** somem e entra a nova |
| **Usar como resposta** | `[data-testid="ai-use-as-reply"]` + `@apply` da bolha + **Tab** | Ver abaixo |

### "Usar como resposta" — reaproveita o caminho existente

Descobri como o composer é alimentado hoje: `CopilotAssistantMessage.vue:52-59` emite
`BUS_EVENTS.INSERT_INTO_RICH_EDITOR` (web widget / e-mail) ou `INSERT_INTO_NORMAL_EDITOR` (o resto),
ouvidos por `ReplyBox.vue:948` e `Editor.vue:859`. **Reusei exatamente isso** em
`useComposerInsert.js` em vez de abrir caminho novo — mesma regra de canal, mesmo comportamento.

`useCopilotReply.js` (a pista do enunciado) é outro fluxo: ele serve as ações inline ✨ do composer
(`accept()` devolve o texto para o `ReplyBox` trocar o editor). Não serve para o painel, que é um
componente irmão sem acesso ao estado do `ReplyBox` — por isso fui pelo bus, que é o mesmo trilho
que o Copilot V1 usa e já está em produção.

**Decisão de UX que vale revisar na validação visual:** ao aplicar, o painel **fecha**. Ele é um
`Dialog` modal com backdrop; deixá-lo aberto esconderia justamente o composer onde o texto acabou de
cair. O histórico continua lá — Ctrl+J reabre e a conversa está intacta. Se o painel deixar de ser
modal (virar coluna lateral como no mockup), essa linha (`applyAnswer` → `closeFromUISettings`) sai.

---

## 4. Composer (item 3)

Pill `rounded-[26px]`, textarea que cresce até 160px, **Enter envia**, **Shift+Enter quebra linha**,
botão circular `size-8` em `--oa-send` / `--oa-send-ink` — preto no claro, branco no escuro, o par
exato do C2. Desabilitado (opacidade 30%) com o campo vazio ou durante a geração. Zero cor de
destaque no fio do chat.

**Tokens visuais:** o shell inteiro do painel (moldura, cabeçalho, corpo, rodapé, composer, botões,
bloco de erro) usa os tokens `--oa-*` de `assets/scss/_copilot-oa.scss`, o arquivo que o A3 criou a
partir do mockup. Não sobrou nenhuma classe `n-slate`/`n-solid`/`n-weak`/`n-alpha` no arquivo
(`grep -c` = 0), então a moldura e as bolhas falam a mesma língua em claro e escuro. O `purple-600`
literal do painel antigo saiu inteiro.

---

## 5. Atalhos (item 4) — auditoria de conflito feita ANTES

| Atalho | Conflito? | Evidência |
|---|---|---|
| **Ctrl/Cmd+J** | **Não.** | `useChatListKeyboardEvents` usa `Alt+KeyJ`; o modal de ajuda usa `$mod+Slash`; o command bar usa `$mod+K`. Grep por `ctrlKey…j` / `metaKey…j` no dashboard inteiro só encontra o do próprio painel |
| **Tab** | **Sim, mas não colidem.** | O `ReplyBox` usa Tab para aceitar o ghost suggestion — só que esse handler vive no keymap do ProseMirror (`ReplyBox.vue:1250`), e o composer **não pode ter foco** com o dialog aberto (o Headless UI prende o foco no painel). Ainda assim, blindei: só aceito se o evento nasceu **dentro** de `[data-ai-panel]` **e** houver resposta pronta; Shift+Tab nunca é sequestrado; se não há nada a aceitar, o Tab segue navegando o foco |
| **Esc** | **Sim — resolvido por precedência.** | O `Dialog` fecha no Esc. Registro em **capture** e faço um descarte escalonado: gerando → para; erro na tela → limpa; editando → cancela; rascunho no composer → limpa; **só então** o painel fecha. Se nada há para descartar, deixo o evento passar |

Tudo em `useCopilotShortcuts.js`, com 9 specs cobrindo inclusive "Tab dentro × fora do painel" e
"Esc passa quando não há nada para descartar".

---

## 6. Thread e histórico (item 5) — e uma restrição que precisa de decisão

`copilot_threads` **não tem `conversation_id`** (`db/schema.rb`) e migration está proibida nesta
rodada. Sem coluna, o vínculo conversa → thread não tem onde morar no servidor. Resolvi no cliente:

- mapa `conversationId → threadId` em `localStorage.chatspx_copilot_thread_map`, **escopado por
  conta** (`useCopilotThread.js:24-70`);
- ao abrir o painel, carrego as mensagens daquela thread via `CopilotMessagesAPI.get(threadId)`;
- cache em memória por conversa: sair e voltar não refaz request (spec cobre);
- thread apagada no servidor (404) → esqueço o id e volto ao estado vazio, **sem travar em
  carregando**.

**Limitação honesta:** o vínculo vive no navegador. Trocar de máquina ou limpar o storage perde a
*associação* (as mensagens continuam no banco, só não são reencontradas por aquela conversa). Isso
se resolve com uma coluna ou com o backend devolvendo a thread da conversa — **decisão do
coordenador + A1**, não minha, porque exige migration.

**Estado de carregando ≠ estado vazio:** são dois `<section>` distintos (`isLoadingThread` →
shimmer + "Carregando a conversa"; vazio → saudação + quick prompts). Tem spec.

### Pendência de contrato com o A1

`CopilotThreadsController#create` **enfileira o job de resposta legado** (`build_copilot_response`).
Com streaming isso geraria resposta dobrada. Mando `skip_response: true` no create
(`useCopilotThread.js:187`) — o `params.permit` atual ignora o extra, então é inofensivo hoje e
**forward-compatible**. **Peço ao A1 que honre esse parâmetro** (ou que o `/stream` crie a thread).

---

## 7. O caminho de erro (item 6)

O `AIErrorBanner` (dono: A3) só conhece 5 tipos: `rate_limit`, `captain_unstable`, `timeout`,
`empty_response`, `network`. Tipo desconhecido cai em `variant = null` e o banner **não renderiza
nada** — ou seja, mandar `unauthorized` para ele produziria exatamente o pior resultado: erro
invisível.

Solução sem tocar no arquivo do A3: o painel roteia os 5 conhecidos para o banner e desenha um
**bloco próprio** (`[data-testid="ai-fallback-error"]`, `role="alert"`) para o resto — hoje
`unauthorized` (chave recusada), `no_assistant` e o genérico. Com título, corpo honesto ("não é
problema da sua conexão") e **Tentar de novo**, como no mockup. Se o A3 adicionar a variante
`unauthorized` ao banner, basta incluí-la em `BANNER_ERROR_TYPES` (uma linha) que o bloco próprio
sai de cena.

Garantias contra travar carregando: watchdog de 30s; `isStreaming` volta a `false` em **todos** os
desfechos (`finally`); bolha vazia é removida quando a geração falha sem produzir texto; retry não
existe onde não faz sentido (sem assistente configurado, não ofereço "tentar de novo").

---

## 8. i18n (item 7)

**Zero texto hardcoded.** 47 chaves `CONVERSATION.AI_ASSISTANT_PANEL.*` — e **45 já existem** nos
dois locales, porque o A2 acompanhou a reescrita (obrigado). Verifiquei chave a chave contra
`pt_BR/conversation.json` e `en/conversation.json`.

### Faltam 2 (criadas por mim depois do trabalho do A2)

| Chave | pt-BR sugerido | en sugerido |
|---|---|---|
| `…ERRORS.NO_ASSISTANT.TITLE` | "Nenhum agente de IA configurado" | "No AI agent configured" |
| `…ERRORS.NO_ASSISTANT.BODY` | "O copiloto precisa de um agente de IA para responder. Peça a quem administra a conta para criar um." | "The copilot needs an AI agent to answer. Ask an account admin to create one." |

### Uma sugestão de texto para o A2 (não alterei o JSON — i18n é dele)

`SHORTCUTS_HINT` hoje é *"Enter envia · Shift+Enter quebra linha · Esc fecha"*. Agora que os três
atalhos existem, o mockup pede a dica deles: **"Tab aceita · Esc descarta · Ctrl+J abre"**. As duas
informações são úteis; a decisão de qual mostrar na barra estreita é do A2.

---

## 9. Como testei

**`npx eslint`** nos 9 arquivos meus: **0 erros**. Resta 1 warning `no-dynamic-keys` em
`AIAssistantPanel.vue:523`, que é **pré-existente** (`t(suggestion.textKey)` do smart banner).

**Vitest — 63 testes novos, todos verdes.** Suíte inteira de `components-next/ai-assistant/` +
`api/captain/specs/`: **248 passando, 1 falhando**.

> A falha é **pré-existente e não é minha**: `useAIAssistantFlag.spec.js` → "returns false when
> server flag is disabled (kill-switch)". Nem o composable nem o spec aparecem em `git status`
> (ambos vêm do commit `7213b620b8`), e a falha se reproduz com o arquivo rodando isolado. O spec
> espera que o kill-switch do servidor vença os overrides de storage; a implementação documenta e faz
> o contrário (overrides têm precedência, `useAIAssistantFlag.js:23-36`). É spec desatualizado em
> relação à implementação — **não corrigi porque não é meu escopo e mexer nisso muda o gate de
> rollout**.

### A prova de streaming (o que foi pedido explicitamente)

Três provas independentes, todas automatizadas:

1. **Ponta a ponta com o emissor falso** — `api/captain/specs/copilotStream.spec.js`, teste
   *"delivers the answer in growing pieces, not in one shot"*: liga a flag do falso, roda
   `useCopilotStream.start()` real e captura o texto a **cada** token. Afirma (a) mais de 10
   renderizações parciais; (b) cada uma é **prefixo estrito** da seguinte — nunca reescreve, nunca
   reordena; (c) o primeiro render tem **menos da metade** do texto final; (d) o tempo total é
   > 50ms. Um painel que recebesse tudo de uma vez falharia em (a), (c) e (d).
2. **No composable, contra o transporte HTTP** — `useCopilotStream.spec.js`, *"exposes the text as
   it grows"*: snapshots do texto entre chunks dão exatamente `['um ', 'um dois ', 'um dois tres']`.
3. **Na tela** — `AIAssistantPanel.spec.js`, *"renders the text progressively as tokens arrive"*:
   lê o texto **renderizado na bolha** após cada token e afirma o crescimento
   `'Olhando'` → `'Olhando o histórico'` → `'Olhando o histórico do pedido.'`, e que a bolha volta a
   `data-streaming="false"` no `done`.

### Regressão fora do copiloto

Não toquei em nenhum arquivo da tela de conversa — `git status` confirma que meus arquivos são só os
listados no §1. `useTypewriter` (que alterei) só é importado por `AIMessageBubble.vue` e
`AISuggestionChip.vue`, ambos dentro do painel; o modo novo só liga quando o texto cresce por
acréscimo, então o chip (que recebe texto completo) não muda. Rodei por garantia os specs vizinhos —
`components-next/copilot/` e `Conversation/specs/SidepanelSwitch.spec.js`: **12 passando**. A
conversa 1:1 não foi tocada.

### O que **não** testei

- **Não validei no navegador.** O bundle em `public/vite` é de 14:02, anterior às minhas mudanças, e
  build/precompile é do coordenador (regra 3 do briefing). A validação visual em claro+escuro é dele.
- **Não bati no endpoint real**, porque o `/stream` do A1 ainda não estava no repo quando terminei
  (`plano/captain-v2/relatos/` tinha só A2 e A3). O contrato C1 está implementado como especificado;
  a primeira execução ponta a ponta vai precisar de um olho no console.
- **Não gastei chave da OpenAI.** Recebi o aviso de que ela voltou a ser válida; como não há endpoint
  de streaming ainda, não havia o que exercitar sem queimar dinheiro do cliente.

---

## 10. Como o coordenador chega no painel (para a validação visual)

```
1. Build (você): npm run build ou o vite dev — o bundle atual é anterior a este trabalho.
2. https://hmlchat.simplexsolucoes.com.br → conta 3 (Simplex Tecnologia)
3. Abrir uma conversa, ex.: /app/accounts/3/conversations/681
4. Ligar o painel V2 (o override exige RELOAD — não funciona em navegação SPA):
     sessionStorage.setItem('chatspx_ai_panel_v2_session','on'); location.reload()
   (ou entrar com ?aiv2=1 na URL e recarregar)
5. Abrir o painel:  Ctrl+J   (ou ✨ no composer → "Perguntar ao Copilot")
6. Ver o streaming SEM depender do backend do A1:
     localStorage.setItem('chatspx_copilot_fake_stream','1')
   → qualquer pergunta (ou um dos 4 quick prompts) escreve token a token.
     Para voltar ao endpoint real: localStorage.removeItem('chatspx_copilot_fake_stream')
7. Roteiro sugerido, em claro e escuro:
   a. quick prompt → texto crescendo + botão Parar visível
   b. Parar no meio → texto parcial fica + "Você parou aqui."
   c. Refazer → resposta nova substitui a anterior
   d. Editar pergunta → volta ao composer, edita, envia; a resposta velha some
   e. Usar como resposta (ou Tab) → texto cai no composer da conversa e o painel fecha
   f. Esc com nada acontecendo → fecha; Esc gerando → só para
   g. Erro: com o falso desligado e o endpoint ainda inexistente, o painel deve mostrar o bloco de
      erro com "Tentar de novo" — nunca ampulheta eterna
```

---

## 11. Riscos e pontos de integração

| # | Ponto | Gravidade | O que fazer |
|---|---|---|---|
| 1 | **Rota do `/stream`** assumida com prefixo `captain/` | Alta se divergir | Conferir com o A1; troca em `COPILOT_STREAM_PATH` |
| 2 | **`skip_response: true`** no create da thread | Alta | Se o A1 não honrar, cada pergunta nova gera **duas** respostas (o job legado + o stream) |
| 3 | **Props do `AIMessageBubble`** (A3) | Média | Consumo `type` / `text` / `isStreaming` e escuto `copy`, `apply`, `retry`, `feedback`, `cancel-streaming`. Se o A3 renomear props, o painel quebra. Verifiquei o arquivo dele durante a execução: o contrato está mantido |
| 4 | **Parar em dose dupla** | Baixa | O A3 desenha um "Parar" na régua da bolha e eu desenho um no painel (como no mockup). Se na tela ficarem dois, remover o meu é 6 linhas |
| 5 | **Vínculo thread↔conversa no localStorage** | Média | Some ao trocar de máquina/limpar storage. Resolver de verdade exige coluna → decisão do Walisson |
| 6 | **Painel fecha ao aplicar** | Baixa | Escolha de UX (é modal). Reversível em 1 linha |
| 7 | **`Retry-After` do 429** | Baixa | O `useAIErrorState` lê o header via objeto de erro do axios; meu transporte é `fetch`, então o contador do banner vai começar do padrão (60s). Cosmético |

---

## 12. Fronteira respeitada

Nenhuma escrita em tabela de agente de IA. `useCopilotAssistant` **lê** `captainAssistants/getRecords`
para descobrir qual assistente embasa a thread — é o mesmo `assistant_id` que o `CopilotContainer` já
usava, e continua sendo só um ponteiro de configuração. Zero migration, zero commit, zero deploy,
zero restart, zero SSH, nenhuma chave nova, nenhum segredo em arquivo.
