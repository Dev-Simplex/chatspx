# Onda 0 — O buraco da triagem: o que o upstream mudou no WIDGET sem colidir conosco

**Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **HEAD:** `93571c69db`
**Comparação:** NOSSO `f26db6ee81` → MERGE `93571c69db` — o que o merge da v4.16.2 trouxe do upstream
**Continuação da A3** (`onda-0-auditoria-widget.md`). Os arquivos já auditados lá são **citados, não repetidos**.

**Delimitação primeiro, porque encolhe a área de 3 diretórios para 1:**

| diretório do brief | veredito |
|---|---|
| `app/javascript/sdk/**` | **o merge não tocou em nada** — `git diff --name-only f26db6ee81 93571c69db -- app/javascript/sdk/` → **vazio** |
| `app/views/widgets/show.html.erb` | **intacto** — `git diff --stat … -- app/views/widgets/` → **vazio** |
| `app/javascript/widget/**` | **82 arquivos**: 25 de código + 57 de i18n |

---

## 1. O QUE MUDOU PARA O VISITANTE DO SITE DO CLIENTE

Sete mudanças que o visitante vê ou sente. O resto dos 25 arquivos é ruído mecânico
(despachado no fim da seção em uma linha).

### 1.1 — 🎨 O widget inteiro ganhou cor de fundo *(o achado que veio da A3, agora com a cor)*

`App.vue:380` — o container raiz passou a receber uma classe condicional que **antes não existia**:

```diff
       'is-flat-design': isWidgetStyleFlat,
+      'bg-n-slate-2 dark:bg-n-solid-1': !isUnreadOrCampaignView,
       dark: prefersDarkMode,
```

Resolvendo os tokens em `woot.scss`: light `--slate-2: 249 249 251` (`:192`) → **#F9F9FB**;
dark `--solid-1: 23 23 26` (`:390`) → **#17171A**. Antes o painel **não pintava fundo nenhum** e
herdava o que estivesse embaixo.

Exceção deliberada: as views `unread-messages` e `campaigns` continuam sem fundo (`App.vue:69-71`),
porque são os balões flutuantes sobre a página do cliente — se ganhassem fundo, apareceria um
retângulo cinza no site do visitante.

**Impacto:** afeta o pixel de **todas as 4 telas capturadas** nos 16 snapshots, em light e dark.
É a causa nº 1 de divergência quando o baseline for reconfrontado.

### 1.2 — 🎨 O leitor de artigos deixou de ser branco fixo

`ArticleViewer.vue:13`: `bg-white` → `bg-n-solid-1`. Uma linha, efeito real: no **dark mode** o
visor do help center dentro do widget passa de branco (#FFF) para **#17171A**. Antes era um
retângulo branco cegante no tema escuro; agora acompanha o tema.

### 1.3 — 🔧 O emoji picker do widget trocou de componente

`ChatInputWrap.vue:11-13,177-182` — `EmojiInput.vue` (apagado pelo upstream) → `EmojiPicker.vue`,
com API diferente (`:on-click` → `@select`) e o posicionamento saindo do SCSS scoped
(`.emoji-dialog`, removido) para classes utilitárias no template
(`!bottom-full end-0 mb-2 max-w-[calc(100vw-3rem)]`). Detalhado na A3 §R1; repito aqui só porque é
uma superfície que o visitante toca.

### 1.4 — ⏱️ O botão "enviar transcrição por e-mail" ganhou trava de 15 segundos

`ChatFooter.vue:14,100-129,171` — o upstream corrigiu um defeito real: o botão podia ser clicado
repetidamente e disparava um e-mail por clique. Agora há `isSendingTranscript` + `transcriptCooldown`
com `TRANSCRIPT_COOLDOWN_MS = 15000`, e o botão fica `:disabled` durante a janela.

**O visitante sente:** clicar duas vezes não manda dois e-mails; o botão fica visivelmente
desabilitado por 15 s. Junto veio a correção de um bug de verdade: o `catch` chamava
`emitter.$emit` (método que **não existe** no mitt) — ou seja, **o alerta de erro nunca aparecia**
e a falha virava exceção silenciosa. Agora é `emitter.emit` e o visitante vê o erro.

### 1.5 — 📝 O erro de campo no pré-chat mudou de mecanismo (e o rótulo vermelho mudou de gatilho)

`PreChat/Form.vue` — o estilo de erro saiu da classe `.error` aplicada ao input por JS
(`inputClass`/`labelClass`) e passou para `&[data-invalid]` no wrapper do FormKit (`:335-347`):

```diff
-    input.error, textarea.error, select.error {
-      @apply outline-n-ruby-8 …;
-    }
+  &[data-invalid] {
+    .formkit-label { @apply text-n-ruby-10; }
+    .formkit-inner input, … { @apply outline-n-ruby-8 …; }
+  }
```

Visualmente equivalente **quando funciona**, mas o gatilho passou a ser o estado do FormKit em vez
de uma string montada por nós. **Consequência para o plano:** qualquer bloco que estilize `.error`
no pré-chat estará estilizando um seletor morto — o seletor vivo agora é `[data-invalid]`.

### 1.6 — ✅ Validação por regex do pré-chat parou de falhar de forma intermitente

`PreChat/Form.vue:170-173` — bug real, corrigido:

```js
// FormKit caches the RegExp and calls .test() across keystrokes, so
// drop stateful g/y flags to stop lastIndex mutation flipping validity.
const matchRegex = regex
  ? new RegExp(regex.source, regex.flags.replace(/[gy]/g, ''))
  : null;
```

Um `regex_pattern` configurado com flag `g` mantinha `lastIndex` entre chamadas de `.test()`, e o
mesmo valor alternava entre válido e inválido a cada tecla. Junto, `getValidation` deixou de
devolver **string** (`'required|email'`) e passou a devolver **array de arrays**
(`[['required'], ['matches', regex]]`), porque o formato string estava serializando o objeto
`RegExp` e destruindo a validação.

**O visitante sente:** campos com máscara/regex param de recusar valores corretos.

### 1.7 — 🔌 Reconectar agora ressincroniza o estado da conversa

`actionCable.js:39` — o `onReconnect` passou a despachar
`conversationAttributes/getAttributes` além de `syncLatestMessages()`.

**O visitante sente:** se a conversa foi resolvida (ou auto-resolvida) enquanto ele estava
desconectado, o composer reflete isso ao voltar, em vez de deixá-lo digitar numa conversa fechada.
Isto conversa diretamente com o nosso F0 "sempre conectado" — é upstream chegando na mesma
conclusão por outro caminho, sem colidir com o nosso código.

### 1.8 — O resto: ruído mecânico, sem efeito no visitante

`GroupedAvatars.vue`, `ArticleBlock.vue`, `ArticleListItem.vue` só perderam
`import { defineProps, defineEmits }` (macros auto-importadas desde o Vue 3.3);
`UserMessageBubble.vue` trocou `::v-deep` por `:deep()` (sintaxe deprecada → atual);
`UserMessage.vue:88` acompanhou a nova assinatura de `sendMessageWithData`.
Os 5 arquivos `*.spec.js` são **testes novos** (+386 linhas) que cobrem justamente o que mudou.

### 1.9 — i18n (57 arquivos), em uma passada

- **55 dos 57** locales receberam exatamente o mesmo delta: o namespace novo `EMOJI_ICON_PICKER`
  (3 chaves), **+5/−0**.
- **`pt_BR.json`: 85 → 88 chaves, `0` chaves ausentes e `0` chaves com texto alterado.** Verificado
  por comparação de dicionário achatado, não por leitura do diff. **Nada nosso foi tocado.**
- Duas exceções: `et.json` (+90/−85 — o upstream traduziu strings que estavam em inglês) e
  `it.json` (+8/−3 — melhoria de tradução). Nenhuma toca pt-BR nem en.
- `i18n/index.js`: +1 locale (`uz`, uzbeque).
- Vazamento upstream registrado, fora do nosso escopo: `it.json` recebeu 2 das 3 chaves novas
  **em inglês** (`"SEARCH_EMOJI": "Search emoji…"`).

---

## 2. BLOCO DO PLANO × PREMISSA × AINDA VALE? × NÚMERO NOVO

**Esta é a seção que decide se a Onda 1 começa como está escrita.** Cada linha foi medida no
worktree, não inferida. Confirmei **e refutei** itens da lista do coordenador — a lista dele
estava certa em 5 de 8.

### 2.1 Veredito curto

| | blocos |
|---|---|
| **VALE INTEGRALMENTE — nada a mexer** | 1.06 · 1.07 · 1.10 · 2.02 · 2.03 · 2.04 · 2.06 · 2.07 · 2.09 · 2.11 · 2.12 · 2.13 · 2.16 · 2.17 |
| **VALE, mas um NÚMERO do aceite está errado e precisa ser corrigido antes da Onda 1** | **1.04** · **1.08** · **1.09** · **0.5** |
| **MUDOU DE ESCOPO — o upstream fez parte do trabalho** | **1.23** · **1.16 / 1.17** (a favor) |
| **VALE, mas ganhou uma armadilha nova** | **1.01** · **2.05** · **2.10** |

### 2.2 A tabela

| Bloco | Premissa escrita no §2.2 | Ainda vale? | Número real medido no MERGE | O que fazer |
|---|---|---|---|---|
| **1.01** | folha de tokens própria; aceite: "`woot.scss` não define mais valor de token" | **VALE — com 3 tokens novos para levar junto** | `woot.scss` **32/32 linhas nossas intactas** (A3). O upstream **acrescentou 3 tokens** ao arquivo: `--surface-1`, `--surface-2`, `--surface-active`, em light (`:275-277`) e dark (`:385-387`) | A extração passa a mover **6 declarações a mais**. Sem elas em `_tokens.scss` o aceite fica verde com 3 tokens órfãos |
| **1.04** | "**25 linhas**, 16 arquivos"; "**7 dos 25** `n-brand` e **6 dos 18** `getContrastingTextColor` em `shared/`" [M14] | **VALE — mas o `n-brand` cresceu** | `n-brand`: **25 → 26 linhas**, **17 → 18 arquivos**. Por diretório: `widget/` 22 ocorr. (inalterado), `sdk/` 0, `shared/` **7 → 8**. `getContrastingTextColor`: **18 → 18**, dos quais **6 em `shared/`** — o número do plano é **exato e inalterado**. `--widget-color`: **1 → 1** | Trocar "25 linhas" por **26** e "7 dos 25" por **8 dos 26**. O ponto novo é `shared/components/emoji/EmojiPicker.vue:59` (`focus:outline-n-brand`) — o componente que o upstream criou ao apagar o `EmojiInput.vue` |
| **1.06** | `show.html.erb:2` (`lang`), `ConversationWrap.vue` (`role="log"`), `bubbleHelpers.js:60`, `HeaderActions.vue` | **VALE INTEGRALMENTE** | os **quatro** arquivos **intactos** (diff vazio). `<html>` em `show.html.erb:2` continua **sem `lang`**; `git grep 'role="log"'` em `widget/` → **vazio** | nada |
| **1.07** | typing dots em CSS "mata o GIF de **19.296 B**" | **VALE INTEGRALMENTE** | `AgentTypingBubble.vue` **intacto**; referência viva em `AgentTypingBubble.vue:14`; `git cat-file -s` do blob = **19296 B exatos** | nada |
| **1.08** | CSS do widget ≤ 80 KB crus (**"hoje 1.103.132"**); **7 `@font-face`** [M16] | **VALE — mas o ponto de partida piorou 55%** | `@font-face` = **7** ✅ (confirma [M16] e prova que estou medindo o artefato certo). CSS medido no build do MERGE: `widget-*.css` = **1.692.256 B** crus / 155.908 gzip; somando os 3 CSS do widget = **1.709.123 B** | Trocar "hoje 1.103.132" por **1.709.123**. O teto de 80 KB continua certo — a redução exigida deixou de ser −92,7% e virou **−95,3%** |
| **1.09** | "**`App.vue` < 310 linhas** (hoje **386**; 386 − 88 + 5 = **303**)"; "16 ramos de `else if`" | **VALE — mas a conta do aceite está errada** | `App.vue`: **386 → 390** linhas. Ramos `message.event ===`: **16 → 16**, e os **16 nomes de evento são idênticos** — o contrato de `postMessage` não mudou em nada | **Corrigir o aceite**: `390 − 88 + 5 = **307**`, não 303. A margem cai de 7 para **3 linhas**. As 4 linhas novas ficam **fora** da região extraída (`:69-71` e `:380`), então o bloco não as remove — deixá-las na conta antiga reprovaria uma execução correta |
| **1.10** | "os **8 tipos**", `!isCards` duplicado e "os **dois ausentes**", `AgentMessageBubble.vue:42-67,92-152` | **VALE INTEGRALMENTE** | `AgentMessageBubble.vue` **intacto**. 7 `contentType ===` + o texto simples = **8 tipos**. O defeito segue vivo em `:96`: `!isCards && !isOptions && !isForm && !isArticle && !isCards && !isCSAT` — `isCards` **duas vezes**, faltando **`isEmail` e `isIntegrations`** = os "dois ausentes" | nada |
| **1.16 / 1.17** | auto-provisionar `CustomAttributeDefinition` (B6 backend) e a seção "Dados recebidos do site (N)" no painel | **VALE — e ficou mais fácil** | o upstream corrigiu a **corrida** que fazia o dado sumir: os `contactCustomAttributes` do pré-chat iam numa chamada separada **depois** da criação da conversa e eram gravados no contato já destruído pelo merge por e-mail/telefone. Agora vão no **mesmo request** (`PreChatForm.vue:44-47,58,70` + `endPoints.js:14`) | Nada a corrigir. Vale registrar: parte do "dado que não chegava" tinha esta causa, não só a do bloco 1.20 |
| **1.23** | "`setConversationCustomAttributes` antes da conversa **enfileira em vez de 404**"; "fila pré-boot drenada"; "`Promise` em todos os métodos" | **MUDOU DE ESCOPO — o upstream fez a metade da conversa** | **feito pelo upstream:** fila **pré-conversa** completa — `conversation/actions.js:215-236` enfileira quando não há conversa; `mutations.js:119-144` (`setPendingCustomAttributes`, `setPendingLabels`, `removePending*`, `clearPendingConversationMetadata`); `index.js:17-18` (estado); `getters.js:36-37`; `conversationLabels.js:8-25` (labels também); drenagem em `sendMessage`/`sendAttachment` com `clearPendingConversationMetadata`. **NÃO feito:** `widget/store/modules/contacts.js` está **intacto** — `setCustomAttributes` de **contato** (`:90`) continua batendo na API na hora, sem fila; e `app/javascript/sdk/` não mudou, logo a fila **pré-boot** e as `Promise` continuam inteiramente nossas | **Reescrever o escopo de 1.23**: o aceite "os 7 métodos chamados antes do boot" continua válido, mas 2 dos comportamentos já existem. Não implementar de novo — **testar** o que veio e implementar só o que falta. Perigo real: reimplementar a fila por cima cria duas filas e o atributo é enviado duas vezes |
| **2.02 / 2.03 / 2.04 / 2.06 / 2.07 / 2.11 / 2.12 / 2.13 / 2.16** | vários | **VALEM INTEGRALMENTE** | todos os arquivos citados estão **intactos**: `ConversationWrap.vue`, `Messages.vue`, `_conversation.scss`, `AgentMessageBubble.vue`, `ChatHeader.vue`, `HeaderActions.vue`, `useMessageFormatter.js`, `AgentMessage.vue` | nada |
| **2.05** | "cascas em `ChatInputWrap.vue`/`ChatFooter.vue` → `WComposer.vue`"; "as duas cascas < 60 linhas cada" | **VALE — com estado novo para preservar** | `ChatFooter.vue`: **152 → 177** linhas (+25). `ChatInputWrap.vue`: **190 → 193** | O aceite (<60 linhas *pós*-refatoração) não muda. Mas a refatoração agora precisa **preservar** o cooldown de transcrição (`isSendingTranscript`, `transcriptCooldown`, `transcriptCooldownTimer`, `beforeUnmount` que limpa o timer) e a troca `EmojiInput`→`EmojiPicker`. Extrair o composer sem levar isso reintroduz o duplo-envio de e-mail |
| **2.09** | "`show.html.erb:6` traz hoje `maximum-scale=1, user-scalable=0` [M17]" | **VALE INTEGRALMENTE — linha exata confirmada** | `show.html.erb:6` → `<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0" />`. Arquivo **intacto** | nada |
| **2.10** | dark mode completo; `App.vue:369-381` | **VALE — mas o intervalo de linhas envelheceu** | a região agora é **`App.vue:372-385`**, e a classe nova de fundo (`:380`) caiu **dentro dela** | Atualizar a citação de linha. Mais importante: 2.10 e a mudança 1.1 mexem **na mesma lista de classes** — quem executar 2.10 tem de decidir o que fazer com `bg-n-slate-2 dark:bg-n-solid-1`, não removê-la por acidente |
| **2.12** | "uma instância de MarkdownIt por valor de `linkify`"; `MessageFormatter.js:109` | **VALE — citação de linha envelheceu** | `useMessageFormatter.js` **intacto**. `shared/helpers/MessageFormatter.js` mudou (A3): o construtor agora está em **`:122`**, não `:109` | Atualizar a citação. O defeito (uma instância por bolha por render) continua |
| **2.17** | `"mandatório"` → `"obrigatório"`; `pt_BR.json:70,96` | **VALE INTEGRALMENTE — as duas linhas ainda são as certas** | `pt_BR.json:70` = `"REQUIRED_ERROR": "Nome Completo é mandatório"` (única ocorrência de "mandatório" em todo `widget/i18n/`); `:96` = `"REGEX_ERROR": "Forneça uma entrada válida"`, idêntico ao nosso. As 3 chaves novas entraram em `~:109`, **depois** das duas | nada |
| **2.18** | "chunk de vendor próprio"; `vite.shared.ts`, `entrypoints/widget.js:32-40`, `widget/i18n/index.js` | **VALE — e o arquivo que ele cita já existe** | `vite.shared.ts` **agora existe de verdade** (o plano o citava antecipando a quebra do bloco 0.3). `widget/i18n/index.js` ganhou **+1 locale** (`uz`) → o "i18n sob demanda" passa a carregar **58** locales, não 57 | Nada a corrigir. Registrar o 58 |
| **0.5** | teto do `sdk.js`, "linha de base de **28.834 B / 9.508 B gzip**" [M15] | **VALE — mas a linha de base mudou** | build do MERGE (`public/packs/js/sdk.js`, 17/ago 12:38): **29.014 B crus / 9.595 B gzip**. Tetos (40.960 / 15.360) folgados | Atualizar a linha de base para **29.014 / 9.595**, senão o gate imprime delta contra um número que não existe mais. Causa: `sdk/` **não** mudou — quem mudou foi o **build** (vite 5→6 + `vite.lib.config.ts`). É efeito colateral medível do bloco 0.3 |

### 2.3 Uma nota sobre a medição do CSS de 1.08

O `1.709.123 B` foi medido nos artefatos de `public/packs/vite/` produzidos pelo build de **outro
executor neste mesmo worktree** (`public/version.json` = `93571c69db`, `manifest.json` de 17/ago
12:38) — eu não rodei build, conforme o brief. O `1.103.132` do plano vem de um build diferente,
feito em outra máquina e em outro momento, então a comparação **não é perfeitamente controlada**.

O que a sustenta: a contagem de `@font-face` deu **exatamente 7**, o mesmo número de [M16], o que
prova que os dois estão medindo o mesmo artefato. Um crescimento de 55% no CSS de um Tailwind sem
`content` próprio (que é justamente o que o bloco 1.08 vai criar) é o resultado esperado de um
upstream que adicionou classes por 4 versões menores.

---

## 3. PERDAS NOSSAS DISFARÇADAS

A pergunta era: um arquivo sem colisão pode apagar comportamento nosso se o nosso comportamento
morava em outro arquivo que dependia dele. Investiguei os quatro vetores nomeados no brief.

| vetor | resultado | evidência |
|---|---|---|
| **contrato de `postMessage`** | **NENHUMA PERDA** | os **16** nomes de evento são **idênticos** entre NOSSO e MERGE, verificado por comparação de conjunto: `change-url`, `config-set`, `delete-conversation-custom-attribute`, `delete-custom-attribute`, `push-event`, `remove-label`, `SDK_SET_BUBBLE_VISIBILITY`, `set-color-scheme`, `set-conversation-custom-attributes`, `set-custom-attributes`, `set-label`, `set-locale`, `set-user`, `toggle-close-button`, `toggle-open`, `widget-visible` |
| **`content_type`** | **NENHUMA PERDA** | `AgentMessageBubble.vue` **intacto**; os 8 tipos idênticos |
| **chaves de config lidas pelo widget** | **NENHUMA PERDA** | `show.html.erb` **intacto**, portanto `window.chatwootWebChannel`, `chatwootPubsubToken`, `authToken` e `globalConfig` são os mesmos. As referências a `chatwootWebChannel` em `widget/` foram de **45 para 46**, e a diferença é **uma única linha, dentro de um spec novo** (`views/specs/PreChatForm.spec.js`) — nenhum consumo novo em código de produção |
| **nomes de evento / contrato HTTP** | **MUDOU, mas sem perda — e é coerente ponta a ponta** | `POST /api/v1/widget/messages` passou a aceitar `custom_attributes` e `labels` na **raiz** do corpo (`endPoints.js:36-42`), e `POST /widget/conversations` aceita `contact.custom_attributes` (`endPoints.js:14`). **Verifiquei o outro lado:** `api/v1/widget/messages_controller.rb:76-80` faz `params.permit(… custom_attributes: {} …)` e `:49-54` aplica os labels. O contrato fecha; nada é descartado por strong params |

**Uma mudança de assinatura que merece registro** (não é perda, mas quebraria código que a ignorasse):
`sendAttachmentAPI(attachment, replyTo)` virou `sendAttachmentAPI(attachment, { customAttributes, labels })`
— o **segundo parâmetro mudou de significado**. Rastreei todos os chamadores
(`git grep sendAttachmentAPI app/javascript/`): há **exatamente um**,
`conversation/actions.js:103`, e ele já usa a forma nova. Nenhum código nosso chamava com dois
argumentos. Sem impacto.

**Conclusão da seção 3: nenhuma PERDA nossa disfarçada nesta área.** Os 79 arquivos que entraram sem
revisão trouxeram correções de bug e uma feature (fila pré-conversa), não remoções.

---

## 4. COBERTURA

**COBERTURA: 82 de 82 arquivos da área auditados** — 25 de código, um a um, e 57 de i18n por
comparação de dicionário achatado (`pt_BR` chave a chave; os demais pelo `numstat`, com as 2
exceções ao padrão abertas e lidas).

Auditados adicionalmente porque um bloco do plano os cita e eu precisava saber se o merge os tocou:
`ConversationWrap.vue`, `Messages.vue`, `_conversation.scss`, `AgentMessageBubble.vue`,
`AgentTypingBubble.vue`, `ChatHeader.vue`, `HeaderActions.vue`, `AgentMessage.vue`,
`useMessageFormatter.js`, `widget/store/modules/contacts.js`, `app/views/widgets/show.html.erb`,
`app/javascript/sdk/**`, `app/controllers/api/v1/widget/messages_controller.rb` — **todos intactos**,
exceto onde a tabela §2.2 diz o contrário.

Fora da área por construção e já cobertos na A3 (citados, não repetidos): `woot.scss`,
`ChatInputWrap.vue`, `PreChat/Form.vue`, `App.vue`, `UserMessage*.vue`, `ChatFooter.vue`.

---

## O QUE O COORDENADOR PRECISA DECIDIR

**Quatro correções no PLANO-MESTRE, todas de uma linha, todas antes da Onda 1:**

1. **1.09** — `App.vue` "hoje 386" → **390**; a conta do aceite `303` → **307**. *Sem isso, uma
   execução correta do bloco é reprovada por 4 linhas que ele não tem como remover.*
2. **1.04** — "25 linhas" → **26**; "7 dos 25 em `shared/`" → **8 dos 26**. *`getContrastingTextColor`
   continua 18 e 6 — esses dois números do plano estão certos.*
3. **1.08** — "hoje 1.103.132" → **1.709.123**. *Os 7 `@font-face` continuam 7.*
4. **0.5** — linha de base do `sdk.js` `28.834 / 9.508` → **29.014 / 9.595**.

**Uma reescrita de escopo, que é a decisão de verdade:**

5. **1.23** — o upstream entregou a fila **pré-conversa** inteira (atributos e labels, com drenagem
   na 1ª mensagem). Continua nosso: a fila **pré-boot**, as `Promise` e a fila do
   `setCustomAttributes` de **contato**. Reimplementar por cima do que veio cria **duas filas** e
   envia o atributo duas vezes.

**E o que já estava dito na A3, que esta auditoria só reforça com a cor exata:** os 16 snapshots
retratam um widget sem fundo; o MERGE pinta `#F9F9FB` / `#17171A`. Reconfrontar e re-aprovar lendo
o diff, antes de usar como baseline.

**Nada foi editado neste worktree.** Esta auditoria é somente-leitura; o único arquivo escrito é
este relatório, fora do repositório.
