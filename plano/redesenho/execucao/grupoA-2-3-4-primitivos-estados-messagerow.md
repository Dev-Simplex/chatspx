# Grupo A #2, #3 e #4 — a cadeia dos primitivos do widget

> Blocos **2.01** (primitivos), **2.07** (estados de verdade) e **2.02** (`MessageRow`),
> na ordem em que se destravam. Commit local `322f8c0d4b`, branch `spx-fila-tracking`.
> Nada foi enviado para remoto e nenhum banco foi tocado.

## 1. O que mudou, bloco a bloco

### 2.01 — os primitivos (esforço G)

`WAvatar.vue` e `WTypingDots.vue` saíram de `widget/components/` para `widget/ui/`.

Mover não era o trabalho. Em `widget/ui/` o `specs/primitivosLint.spec.js` passa a
varrê-los — e reprovou, como o plano previa:

```
Tests  1 failed | 56 passed (57)
literais: 26 hexadecimais + 2 rgb()  →  #4B143D … #3A5BC7, rgb(0…, rgb(2…
```

Os 28 viraram token. `WTypingDots` já estava limpo e passou sem tocar.

**Onde os tokens foram parar, e a decisão que tive de tomar sozinha.** A paleta de
iniciais não tinha equivalente na paleta do widget — ela só tem `slate/iris/ruby/
amber/teal/gray`, e quatro dos seis tons (rosa, laranja, íris real, azul) não existem
lá. Perguntei ao coordenador se podia acrescentar dois mixins em
`_tokens_values.scss` (arquivo do bloco 1.01, FEITO) ou se devia criar folha própria
em `widget/ui/`. **O `ask` expirou em 900 s sem resposta** (`msg_e5a7124850c8`).
Segui pela folha única, porque a alternativa reintroduz exatamente a divergência que o
1.01 existe para impedir, e porque a mudança é **aditiva**: `widget-avatar-light` e
`widget-avatar-dark` são novos, nenhum valor existente foi tocado, e a saída CSS
anterior está intacta. **Se o coordenador preferir o outro caminho, é uma troca de
dois blocos de mixin — o componente não muda.**

Some junto um mecanismo: o par escuro viajava por `--dark-bg`/`--dark-text` escritos
em `:style` e aplicados por `dark:!bg-[var(…)]` com `!important`. Agora o tema escuro
redeclara o token e a cascata resolve.

### 2.07 — estados de verdade (esforço M)

`connectionMonitor.js` e `loadingGate.js` existiam, tinham teste verde e **nenhum
leitor**. Entram os dois consumidores:

| Arquivo novo | O que lê | Onde é montado |
|---|---|---|
| `components/ConnectionBanner.vue` | `widgetConnectionMonitor` → `WBanner` | `views/Messages.vue`, **acima da lista, fora do composer** |
| `components/ConversationSkeleton.vue` | `widgetLoadingGate` → `WSkeleton` + `WSpinner` | `ConversationWrap.vue`, no lugar do `Spinner` imediato |

As duas instâncias mudaram de `widget/helpers/actionCable.js` para
`widget/state/index.js` — a tela precisa LER o estado, e o `actionCable` arrasta o
connector, o áudio e a ponte de iframe atrás de um booleano. O `actionCable` reexporta
`widgetConnectionMonitor` para quem já o importava de lá.

Chaves novas em `pt_BR.json` **e** `en.json` (`CONNECTION.RECONNECTING`, `.OFFLINE`,
`.LOADING`), como a regra da onda exige.

### 2.02 — `MessageRow` (esforço M)

`AgentMessage.vue` (335 linhas) + `UserMessage.vue` (179) = **514**. Viraram
`MessageRow.vue`, uma linha só com `variant`, e as duas continuam existindo como
**cascas** — é por elas que `ChatMessage.vue` escolhe o lado, e é o nome delas que
aparece na árvore de componentes.

```
AgentMessage.vue   31
UserMessage.vue    26
                   --
soma               57   (teto: 150)
MessageRow.vue    447
```

A marcação foi copiada à risca dos dois originais — inclusive o encadeamento de anexos
em que `ImageBubble` abre uma cadeia própria e `FileBubble` fecha a outra. Não é
elegante e **não foi corrigido de propósito**: cinco telas do widget são cobertas por
20 snapshots de pixel, e mexer nisso é decisão de outro bloco.

A segunda metade do aceite ("nenhum seletor de irmão adjacente para agrupar") **já
estava paga** pelos blocos 2.02/2.03 anteriores (`useMessageGrouping.js`); aqui ela
virou asserção executável em vez de afirmação.

## 2. O que provou cada aceite

| Bloco | Aceite (§2.2) | Comando | Resultado |
|---|---|---|---|
| 2.01 | «nenhum importa de `dashboard/`, nenhum tem cor literal» | `npx vitest run app/javascript/widget/ui/specs/primitivosLint.spec.js` | **57 testes**, 14 primitivos × 4 + a guarda de glob vazio |
| 2.01 | o valor não pode mudar junto com o lugar | `npx vitest run app/javascript/widget/ui/specs/WAvatar.spec.js` | **22 testes** — cada token comparado contra a tabela original |
| 2.01 | e a **cascata** tem de resolver, não só a string | `node app/javascript/widget/ui/specs/browser/avatar-tokens.check.mjs` | **37/37 em Chromium real** — desenho antigo × novo lado a lado, `getComputedStyle` idêntico nos 2 temas |
| 2.07 | «nada nos primeiros 3 s, faixa depois, composer utilizável; micro-queda de 1,5 s não mostra nada» + «skeleton só acima de 600 ms» | `npx vitest run app/javascript/widget/components/specs/estadosDeVerdade.spec.js` | **13 testes** |
| 2.02 | «`AgentMessage`+`UserMessage` < 150 linhas somados; nenhum seletor de irmão adjacente» | `npx vitest run app/javascript/widget/components/specs/messageRow.spec.js` | **8 testes**, soma **57** |
| — | regressão | `npx vitest run app/javascript/widget app/javascript/dashboard/modules/widget-preview app/javascript/shared` | **131 arquivos / 1.464 testes**, 0 falhas |
| — | lint | `npx eslint app/javascript/widget` | **0 erros** (9 avisos, todos o `$t` de dublê que os specs já existentes têm) |

## 3. A prova de que os testes ACUSAM

A armadilha nomeada no briefing é real: os dois módulos do 2.07 passaram uma onda
inteira **mortos com teste verde**, porque um exame de "o módulo existe" ou "a função
foi chamada" não distingue ligado de existente. Então cada mecanismo foi quebrado de
propósito e o vermelho medido:

| Quebra deliberada | Vermelho |
|---|---|
| tirar `<ConnectionBanner />` de `Messages.vue`, `<ConversationSkeleton>` de `ConversationWrap.vue` e a inscrição no monitor | **7 de 13** falham |
| tirar só os dois consumidores da árvore (o resto intacto) | **3 de 13** falham |
| tirar a guarda `reply_message_id` do `MessageRow` | 4.01 falha (`agentMessageVisitorReply`) |
| engordar `AgentMessage.vue` em 130 linhas | o teto do 2.02 falha |
| trocar **um dígito** de `--w-avatar-4-fg` (`#0bd8b6` → `#0bd8b7`) | falha no vitest **e** no Chromium (36/37) |

Os testes que continuam verdes com o consumidor desligado são, todos, os de asserção
NEGATIVA ("micro-queda não mostra nada", "sem busca nada aparece") — que é o
comportamento correto deles, e a razão de nenhum aceite depender só de asserção
negativa.

## 4. O que ficou de fora, e por quê

- **As suítes Playwright de `spec/e2e/widget/`** (os 20 snapshots). Elas usam portas
  fixas (3038/3999/8899) e o slot do harness está sob tranca do coordenador. Em vez de
  tomar o slot, a identidade de pixel do 2.01 foi provada por um verificador de
  Chromium com `chromium.launch()` direto, porta nenhuma — ele compara os dois
  desenhos no mesmo documento e é mais específico que um diff de imagem. **A matriz
  continua com 20 cenários; nada foi reduzido.**
- **A faixa de conexão só aparece na tela de mensagens.** Em `Home` e na lista de não
  lidas não há composer nem conversa para proteger, e o aceite do bloco fala da
  conversa. Se a decisão de produto for outra, é uma linha por view.
- **`build`/`vite.config` e `sdk/`** não foram tocados — são de outras trilhas.
- **Nenhum `rspec`.** Os três blocos são inteiramente de front; não há Ruby no
  caminho deles.
