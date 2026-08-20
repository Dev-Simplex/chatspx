# A3 — VISUAL: os componentes do chat no padrão OpenAI

> Worker A3 · 2026-07-28 · VM 192.168.8.232 (homologação) · branch `homologacao`
> Fonte da verdade: `public/mockups/copiloto-v2.html` · contrato C2 do briefing.
> **Nada foi commitado.** Working tree only, como manda a regra 2.

---

## 1. O que mudou

| Arquivo | O que é |
|---|---|
| `app/javascript/dashboard/assets/scss/_copilot-oa.scss` | **novo** — os 13 tokens `--oa-*` (claro + escuro), a tipografia do markdown (`.oa-prose`), o wrapper do bloco de código e as animações (pontinhos, cursor) |
| `app/javascript/dashboard/assets/scss/_woot.scss:25-26` | **+2 linhas** — comentário + `@import 'copilot-oa'` |
| `.../ai-assistant/AIMessageBubble.vue` | reescrito — a decisão estrutural mora aqui |
| `.../ai-assistant/AILoadingShimmer.vue` | reescrito — três pontinhos no lugar das barras roxas |
| `.../ai-assistant/AIErrorBanner.vue` | reescrito — monocromático + variante `unauthorized` (o 401) |
| `.../ai-assistant/AIQuickPromptCard.vue` | reestilizado — cartão `.qp` do mockup |
| `.../ai-assistant/AISmartBanner.vue` | reestilizado — severidade virou peso, não matiz |
| `.../ai-assistant/AISuggestionChip.vue` | reestilizado — mesmo vocabulário, API intacta |
| `.../ai-assistant/spec/AIMessageBubble.spec.js` | **novo** — 19 testes |
| `.../ai-assistant/spec/AIMessageBubble.tables.spec.js` | **novo** — 2 testes (rolagem da tabela) |
| `.../ai-assistant/spec/AIErrorBanner.spec.js` | **novo** — 12 testes |
| `.../ai-assistant/spec/AIQuickPromptCard.spec.js` | **novo** — 7 testes |
| `.../ai-assistant/spec/AILoadingShimmer.spec.js` | reescrito — 7 testes |
| `.../ai-assistant/spec/AISmartBanner.spec.js` | 3 testes de cor viraram testes de token + 1 novo |

---

## 2. A decisão estrutural

**A resposta da IA não tem bolha.** Em `AIMessageBubble.vue` os três papéis são
ramos irmãos do template, não variações de um mesmo contêiner:

- `role=user` (`AIMessageBubble.vue:252-260`) — a **única** bolha da tela:
  `bg-[var(--oa-user-bub)]`, `rounded-[18px]`, `max-w-[75%]`, à direita.
- `role=assistant` (`AIMessageBubble.vue:278-391`) — `w-full`, texto solto na
  coluna, **sem avatar, sem etiqueta "Copiloto", sem fundo**. O `sparkles` roxo
  e a palavra "Copilot" que existiam antes foram removidos — há teste travando
  isso (`AIMessageBubble.spec.js:81`).
- `role=thinking` (`AIMessageBubble.vue:262-276`) — três pontinhos.

Nenhum `purple-600` sobrou em nenhum dos seis componentes. A varredura de DOM
no navegador (item 6) não achou **nenhum** pixel cromático no fio do chat.

---

## 3. Onde os tokens moram, e por quê

Escolha: **variáveis CSS num arquivo de estilo global**, consumidas nos
templates por valor arbitrário do Tailwind (`bg-[var(--oa-bg)]`).

O argumento, em três pontos:

1. **A paleta `n-*` não serve.** `_next-colors.scss` foi retonada para o
   verde/cinza do WhatsApp (`--slate-11: #667781`, `--iris-9: #00a884`). Não
   existe combinação de `n-*` que produza `#0d0d0d`/`#f4f4f4`/`#ececec`. Cravar
   os hex direto no template seria pior: 13 valores × 2 temas espalhados por
   6 arquivos.
2. **Cada token é um par claro/escuro.** Um bloco `.dark` troca os 13 de uma
   vez. A alternativa Tailwind seria `dark:` em cada utilitário — o dobro de
   classes e duas oportunidades de esquecer uma.
3. **É o mecanismo que o repo já usa.** `_wa-skin.scss` e `_next-colors.scss`
   fazem exatamente isso, importados por `_woot.scss`. Segui a trilha existente
   em vez de inventar uma terceira.

O markup segue Tailwind-first como o resto de `components-next`. A única
estilização por descendência é a do markdown renderizado (`.oa-prose`), porque
o HTML vem do `markdown-it` via `v-html` e não tem classe nossa para receber
utilitário.

**⚠️ Toquei um arquivo compartilhado:** `_woot.scss` ganhou duas linhas (o
`@import`). Sem isso os tokens não existem em lugar nenhum. Nenhum outro worker
mexe em SCSS nesta rodada, então o risco de conflito é nulo — mas está aqui
declarado.

---

## 4. Contraste — medido, não estimado

Rodei o cálculo WCAG sobre os pares reais do mockup **e** depois uma varredura
no navegador nó a nó. Achado que muda o desenho:

| Par | Claro | Escuro |
|---|---|---|
| `--oa-ink` no fundo | 19,44:1 ✅ | 13,63:1 ✅ |
| `--oa-ink` na bolha do usuário | 17,67:1 ✅ | **11,17:1 ✅** |
| `--oa-ink-2` no fundo | 6,58:1 ✅ | 7,77:1 ✅ |
| **`--oa-ink-3` no fundo** | **3,23:1 ❌** | 4,98:1 ✅ |
| **`--oa-ink-3` no hover** | **2,84:1 ❌** | 4,14:1 (⚠️ só UI) |

O contraste baixo de propósito do tema escuro (`#ececec` sobre `#303030`)
**passa folgado**: 11,17:1. Era a preocupação levantada e ela não se confirmou.

O problema é outro: **`--oa-ink-3` (#8f8f8f) reprova em AA no tema claro** —
3,23:1 no fundo e 2,84:1 sobre o hover, que falha até o piso de 3:1 de
componente de UI. O mockup usa esse token para a fonte citada, o subtítulo do
estado vazio e a barra de dicas.

**Decisão:** mantive o token no arquivo (o mockup o define e ele serve para
placeholder), mas **nenhum texto ou ícone meu o usa** — todos foram para
`--oa-ink-2`. Diferença visual: um cinza um passo mais escuro no tema claro; o
desenho continua discreto e monocromático. Está documentado no cabeçalho do
`_copilot-oa.scss`.

---

## 5. i18n — zero texto hardcoded

Uso 40 chaves. **Todas as 40 já existem em `pt_BR` e em `en`** — o worker A2
criou as novas enquanto eu trabalhava; conferi uma a uma por script. As que eu
precisei e não existiam antes:

| Chave | pt-BR (como o A2 gravou) |
|---|---|
| `…AI_ASSISTANT_PANEL.ACTIONS.USE_AS_REPLY` | Usar como resposta |
| `…AI_ASSISTANT_PANEL.ACTIONS.STOP` | Parar |
| `…AI_ASSISTANT_PANEL.CODE.COPY` / `.COPIED` | Copiar / Copiado |
| `…AI_ASSISTANT_PANEL.SOURCE.ARIA` | Abrir a fonte citada: {source} |
| `…COPILOT_ERRORS.UNAUTHORIZED.TITLE` / `.BODY` | Credencial recusada / "…recusou a credencial. Isso não é problema da sua conexão…" |

Nada mais é pedido ao A2.

---

## 6. Como testei

**Lint** — `npx eslint` nos 6 componentes + 5 specs: **0 erros**. Sobram 5
warnings (`no-dynamic-keys`, `no-root-v-if`), todos padrões pré-existentes da
base. O baseline desses mesmos arquivos em `HEAD` tinha **7 erros** (inline
styles, strings cruas 👍/👎, `__uid`); zerei todos.

**Vitest** — `npx vitest run .../ai-assistant/spec/`: **78/78 verdes**, 9
arquivos (inclui os 10 testes novos do painel do A4, que passam contra os meus
componentes). Inclui os 9 testes pré-existentes do `AISuggestionChip`, que passam
sem alteração — prova de que a API pública (props, eventos, `data-testid`) não
mudou, e por isso o `ReplyBox.vue` (fora do meu escopo) continua de pé.

Na suíte inteira do diretório (202 testes) há **1 falha**:
`composables/spec/useAIAssistantFlag.spec.js:36`. **Pré-existente e fora do meu
escopo** — nem o composable nem o spec estão modificados no `git status`,
território do worker A4.

**Prova visual** — o Histoire do repo aponta para um `histoire.setup.ts` que
não existe, e sem ele o `useI18n` dos componentes quebra. Em vez de mexer em
config compartilhada, montei um harness Vite temporário que importa os
componentes **reais** com um `vue-i18n` de verdade, buildei com o Tailwind e o
SCSS do repo, servi estático e fotografei com Playwright em `light` e `dark`.
O harness foi removido do repo; as fontes estão preservadas em
`/tmp/claude-1001/-home-chatwoot-chatwoot/5b716bee-444e-4544-8662-57663df2ea07/scratchpad/harness/`
(rebuild: `npx vite build --config .../vite.config.mjs`).

Screenshots (2× DPI) em
`/tmp/claude-1001/-home-chatwoot-chatwoot/5b716bee-444e-4544-8662-57663df2ea07/scratchpad/shots/`:
`copiloto-{light,dark}.png` (página inteira) e
`{vazio,fio,carregando,erro,previa}-{light,dark}.png`.

Junto com as fotos, uma auditoria de DOM rodada no navegador nos dois temas:

| Verificação | claro | escuro |
|---|---|---|
| chave i18n vazando na tela | 0 | 0 |
| nós de texto reprovando AA (medido contra o fundo pintado de verdade) | **0** | **0** |
| ícones que não pintaram nada | 0 | 0 |
| cor cromática no fio do chat / na prévia | **0** | **0** |
| `pre` com scroll próprio | `overflow-x: auto`, 841px de conteúdo em 398px de caixa → **rola dentro dele** | idem |
| a página rola de lado por causa do código | **não** | **não** |
| tokens resolvidos | `#ffffff / #0d0d0d / #f4f4f4` | `#212121 / #ececec / #303030` |

---

## 6-B. Adendo — validação com IA real (chave renovada, 28/07)

Assim que o coordenador avisou que a chave é válida, fiz **uma** chamada a
`gpt-4.1-mini` (529 tokens, sem loop) pedindo uma resposta de copiloto com
markdown variado, e renderizei a saída **literal** do modelo nos meus
componentes. Foi a validação mais útil da tarefa: markdown que eu escrevo é
markdown que eu já sei que funciona.

Renderizaram perfeitamente: título (rebaixado para `h3`/`h5` — nunca `h1` no
fio), lista ordenada com sub-itens, régua, bloco de código com linguagem
(rolagem própria + botão de copiar), link com `target=_blank rel=noopener
noreferrer`, chip de fonte e as ações.

**Um defeito real apareceu — e é grave.** O modelo produziu uma **tabela**
comparativa. `useMarkdown.js` (arquivo do worker A4) não tem as tags de tabela
no `ALLOWED_TAGS` do DOMPurify, então:

- a **linha de cabeçalho sumiu inteira** (`Ação | Vantagens | Desvantagens`);
- as células viraram **texto corrido, sem separação nenhuma**:
  > "Aguardar atualização Evita custos adicionais Cliente pode ficar
  > insatisfeito Contatar transportadora Pode acelerar resolução…"

Isso é pior do que perder a informação: é **enganoso**. Uma vantagem e uma
desvantagem de ações diferentes ficam coladas na mesma frase, e o agente está
sob pressão com um cliente esperando. Modelos GPT produzem tabela comparativa o
tempo todo — não é um caso de borda.

**A minha metade está entregue:** tipografia monocromática da tabela em
`_copilot-oa.scss` (cabeçalho em `--oa-code`, bordas `--oa-line`) e a caixa
`.oa-tablewrap` com `overflow-x` própria, injetada pela mesma passada de
decoração do bloco de código (`AIMessageBubble.vue:147-170`) — o painel tem
400px e três colunas empurrariam a conversa. Coberta por
`spec/AIMessageBubble.tables.spec.js` (2 testes), que mocka o `useMarkdown`
justamente para testar a decoração sem depender do allowlist do A4.

**A metade do A4 é uma linha** — em `composables/useMarkdown.js`,
`PURIFY_CONFIG.ALLOWED_TAGS` precisa ganhar
`'table','thead','tbody','tr','th','td'`. Simulei exatamente esse patch numa
cópia dentro do harness (o arquivo do repo não foi tocado) e fotografei o
resultado: `shots/real-{light,dark}.png` mostram a tabela renderizada certa,
monocromática e dentro da coluna. É só ligar.

---

## 7. Decisões que quero registradas

**Não renomeei o arquivo.** `AIMessageBubble.vue` é um nome errado para um
componente cuja tese é "a IA não tem bolha" — concordo. Mas `AIAssistantPanel`
(A4, sendo editado agora), a suíte E2E e o `ReplyBox` importam por esse
caminho; renomear no meio da execução paralela quebraria o painel do A4 num
momento imprevisível, e o ganho é cosmético. Deixei o motivo no docblock do
componente. **Sugestão: renomear para `AIChatMessage.vue` numa passada única
depois que A3 e A4 pousarem.**

**👍/👎 viraram ícones lucide.** O mockup usa emoji; emoji é colorido e a regra
C2 pede vocabulário monocromático — além de gerar erro de lint
(`no-bare-strings-in-template`, que era um dos 7 erros do baseline).
`i-lucide-thumbs-up/down` resolve os dois.

**A severidade do `AISmartBanner` virou peso, não matiz.** Vermelho/âmbar/roxo
saíram; a régua da esquerda escurece conforme a urgência (`--oa-line` →
`--oa-ink-2` → `--oa-ink`). Quem não enxerga cor nunca dependeu do vermelho: a
urgência real está no `role="alert"` + `aria-live="assertive"`, preservados.

**Adicionei a variante `unauthorized` ao banner de erro** — hoje é o estado
mais provável (chave revogada) e o mockup mostra exatamente essa tela.

---

## 8. Pendências e riscos — o que o próximo precisa fazer

0. **@A4 — ⚠️ PRIORIDADE: libere as tags de tabela no `useMarkdown`.** Uma
   linha em `PURIFY_CONFIG.ALLOWED_TAGS`
   (`'table','thead','tbody','tr','th','td'`). Sem isso, toda tabela que o
   modelo gerar chega ao agente como texto corrido enganoso — ver seção 6-B,
   com print do antes e do depois. A estilização e a rolagem já estão prontas
   do meu lado.
1. **@A4 — o fundo do painel precisa ser `--oa-bg`.** Meus componentes assumem
   que a superfície atrás deles é `var(--oa-bg)`. O `AIAssistantPanel` ainda usa
   `bg-n-solid-1`. Enquanto não trocar, o chip de fonte (que tem
   `bg-[var(--oa-bg)]`) vai destoar por alguns tons do fundo do painel. Os
   tokens já estão disponíveis globalmente — é só usar.
2. **@A4 — o 401 não chega ao banner.** `useAIErrorState.classify()` devolve
   `null` para HTTP 401; a variante `unauthorized` que entreguei só aparece
   quando o composable passar a devolver `'unauthorized'`. Uma linha, no arquivo
   de vocês.
3. **@A4 — `sources`.** `AIMessageBubble` e `AISuggestionChip` aceitam uma prop
   `sources` (string ou `{id,label,url}`) e emitem `source-click`. Hoje ninguém
   passa nada — o chip simplesmente não renderiza. É o gancho pronto para
   quando o backend (A1) devolver a citação.
4. **E2E precisa de um ajuste de regex.**
   `spec/e2e/copilot/quick-prompt-flow.spec.js:47` procura o botão por
   `/Usar no composer|Aplicar/i`; o texto aprovado agora é **"Usar como
   resposta"**. O arquivo não é meu — não toquei. O `data-testid` estável é
   `ai-message-apply`.
5. **O botão de copiar do bloco de código aparece quando a resposta fecha**, não
   durante o streaming: o `v-html` é reescrito a cada token e redecorar o DOM a
   cada quadro seria caro. Se o produto quiser o botão já durante o streaming,
   é uma mudança pequena, mas com custo por token.
6. `bundle exec rubocop` não se aplica — não encostei em Ruby.
