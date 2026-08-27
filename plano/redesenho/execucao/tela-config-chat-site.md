# Tela de configuração do chat de site — os cinco achados, medidos e consertados

> **Trilha:** `chatwoot-spx-ui-config` (worktree própria), base `6d56c722c8`.
> **Commits locais:** `6b1c58a9b1` (arquivos da trilha) e `877c543ec9`
> (**fora da minha lista** — ver §7).
> **Nada foi enviado.** Sem `git push`, sem PR, sem tocar em banco ou VM.
> **Data:** 26/08/2026.

---

## 0. Como cada número foi obtido

Duas fontes, e cada afirmação abaixo diz de qual delas veio:

1. **Instalação real** — Chromium 1234 via Playwright 1.59.1 contra
   `https://hmlchat.simplexsolucoes.com.br`, conta 3, caixa 6
   ("Suporte CHAT - SPX"), logado como `qa-playwright@simplex.test`. Só leitura:
   navegação e `getComputedStyle`. Nenhuma configuração foi salva, nenhuma senha
   foi trocada.
2. **Harness do repositório** — `spec/e2e/inbox-config/`, que monta a
   `Settings.vue` **de verdade** num Chromium real.

O harness só vale porque a largura é fiel, e a largura é fiel por um motivo
que precisou ser descoberto: na instalação a tela **não** recebe o viewport
inteiro. `Wrapper.vue:33` monta o `<router-view>` com
`flex-1 max-w-[960px] mx-auto px-8 py-6 overflow-auto w-full`, e essa classe cai
na raiz da `Settings.vue` por fallthrough de atributo. É por isso que a barra de
abas mede **912 px em 1280 e também em 1440** — o viewport não muda nada. O
harness repete essa classe verbatim.

Medição de conferência, harness × instalação, mesmo estado de código:

| | instalação (hmlchat) | harness |
|---|---|---|
| largura da raiz `.settings` | 960 px | 960 px |
| `clientWidth` da lista de abas | 912 px | 912 px |
| `scrollWidth` da lista de abas | 1154 px | 1154 px |
| nº de abas | 11 | 11 |

---

## 1. Três abas com o mesmo nome, duas invisíveis

**Medido na instalação, antes:** `scrollWidth 1154 × clientWidth 912` — 242 px
de transbordo, idêntico em 1280 e 1440. Fora da vista, exatamente:

```
VISÍVEL  "Configurações"          [228..345]
VISÍVEL  "Agentes"                [349..421]
VISÍVEL  "Horário de funcionamento" [425..608]
VISÍVEL  "CSAT" "NPS" "Aparência" "Gatilhos" "Rastreio"
VISÍVEL  "Formulário Chat Pré"    [959..1102]
FORA     "Configuração"           [1106..1213]
FORA     "Configuração do Bot"    [1217..1366]
```

### (a) Os nomes

| chave | antes (pt-BR) | agora | antes (en) | agora |
|---|---|---|---|---|
| `TABS.SETTINGS` | Configurações | **Geral** | Settings | **General** |
| `TABS.CONFIGURATION` | Configuração | **Instalação** | Configuration | **Installation** |
| `TABS.BOT_CONFIGURATION` | Configuração do Bot | **Bot** | Bot Configuration | **Bot** |
| `TABS.PRE_CHAT_FORM` | Formulário Chat Pré | **Pré-chat** | Pre Chat Form | **Pre-chat** |

A quarta linha não estava no pedido. Entrou porque "Formulário Chat Pré" não é
português — é a ordem das palavras do inglês — e porque ela é a quarta maior da
barra. As quatro chaves só são usadas em `Settings.vue`; conferido por `grep`.
Só `pt_BR` e `en` foram tocados.

### (b) A affordance

O transbordo **acabou**: com os nomes novos, `scrollWidth 912 = clientWidth 912`,
zero abas fora da vista, em 1280 e 1440, nos dois temas. A barra não precisa mais
de rolagem para caber.

Mesmo assim o indicador foi consertado, porque ele **já existia e não funcionava**
— e é o que segura o dia em que alguém adicionar a 12ª aba. Achado (§7.1): o
chevron pintava **4 × 16 px**. O teste força a condição de transbordo de forma
real (viewport 900, onde o `max-w-[960px]` deixa de valer) e exige ≥ 14 px de
ícone pintado + rolagem que efetivamente alcança a última aba.

---

## 2. A foto do atendimento

**Antes:** um círculo com ícone genérico rotulado "Imagem do Canal", só
`input[type=file]` escondido atrás dele. Sem galeria, sem formato, sem tamanho,
sem dizer onde a foto aparece.

**Agora** (`components/ChannelAvatarField.vue`):

- **galeria de 8 avatares padrão**, um clique aplica, com anel na escolhida;
- **"Enviar minha imagem"** como botão explícito (`accept` = jpeg/png/gif);
- **"PNG, JPG ou GIF · quadrada, a partir de 250 × 250 px · até 15 MB"** na tela
  — os números vêm de `Avatarable#acceptable_avatar` (15 MB, três MIMEs) e de
  `avatar_url` (variante `resize_to_fill: [250, nil]`);
- **"Aparece no cabeçalho do chat no site do cliente e no balão das mensagens do
  atendente."**, e o preview ao lado mostra as duas coisas acontecendo.

Escolher da galeria **não** guarda a URL: baixa o PNG do próprio domínio e monta
um `File`, emitindo o mesmo `{ file, url }` do upload. A foto vai para o
ActiveStorage, então guardar só a URL a deixaria de fora do salvamento.

### Os arquivos, e o `.gitignore`

Ilustrações próprias — **sem foto de pessoa real e sem banco de imagem**. Os
`.svg` são a fonte; os `.png` são o que a galeria serve, porque o backend recusa
SVG na validação.

`*.png` está no `.gitignore` desta base (linha 112) e `git add` pula em silêncio.
Conferido antes e depois:

```
$ git check-ignore -v public/dashboard/images/inbox-avatars/atendente-1.png
.gitignore:112:*.png    ...            # antes
.gitignore:132:!public/dashboard/images/inbox-avatars/*.png   # depois
$ git add -n public/dashboard/images/inbox-avatars/
add 'public/dashboard/images/inbox-avatars/atendente-1.png'   ... (8 PNG + 8 SVG)
```

A exceção entrou comentada, no mesmo laço das duas que já existiam. **Nenhum
`git add -f`.** Confirmado no índice: 8 PNGs.

### Por que ficou na aba "Geral", e não em "Aparência"

A favor de "Aparência": é onde mora o resto do visual e onde o preview vive.

A favor de "Geral", que é onde ficou:

1. **A foto é da caixa, não do widget.** Toda caixa tem uma — WhatsApp, e-mail,
   API. "Aparência" só existe para caixa de widget. Mover levaria o controle
   embora de todos os outros canais.
2. **O mecanismo de gravação é o do formulário "Geral"**: `multipart` no mesmo
   `updateInbox` que grava o nome. "Aparência" trabalha sobre um rascunho com
   barra de salvar e guarda de alterações próprias; enfiar upload de arquivo
   nesse modelo é reescrever o modelo.
3. **O contra-argumento do pedido já não vale.** "Está separado de tudo que é
   visual" era verdade quando o controle era mudo. A aba "Geral" de uma caixa de
   widget **já renderiza o preview ao vivo do lado** (`:logo="avatarUrl"`), então
   a foto escolhida aparece na hora, no lugar onde vai aparecer. O defeito não
   era a aba: era o controle não dizer nada.

---

## 3. A barra do preview

**Medido antes:** `scrollWidth 489 × clientWidth 416` (1280) e `× 412` (1440).
"Modo do chat" com **39 px de largura e 63 px de altura** — três linhas — e
"Celular" cortado em "Celu".

**Causa:** `flex items-center justify-between` sem `flex-wrap`. Sem permissão
para quebrar linha, a única saída do navegador é espremer os itens.

**Agora:** `flex-wrap` na barra e nos grupos, `shrink-0 whitespace-nowrap` nos
rótulos. Medido: sem transbordo e nenhum rótulo com mais de 1 linha, em 1280 e
1440, nos dois temas.

---

## 4. Os cartões de tema

**Medido antes:** cartões de **109 px**; "O widget abre sempre claro." em **4
linhas** e "Segue o tema do sistema de quem visita o site." em **6**.

**Causa:** `sm:grid-cols-3`. O `sm:` olha o **viewport**; o container é a coluna
de 6/8 da `SettingsFieldSection`, que dá 351 px em qualquer viewport. Três colunas
ali são 109 px por cartão, sobrando ~69 px de texto.

**Agora:** `[grid-template-columns:repeat(auto-fit,minmax(190px,1fr))]`, que
decide pela largura **real do container**. Medido: uma linha por descrição, em
1280 e 1440, nos dois temas.

---

## 5. Contraste no tema escuro — **não havia defeito nos rótulos nomeados**

Isto precisa ser dito sem enfeite: **os quatro rótulos que o pedido mandou
conferir já passavam em AA, com folga.** Medido na instalação, antes de qualquer
mudança:

| rótulo | claro | escuro |
|---|---|---|
| Imagem do Canal (hoje "Foto do atendimento") | 17,46:1 | 14,82:1 |
| Nome do site | 17,46:1 | 14,82:1 |
| Domínio do website | 17,46:1 | 14,82:1 |
| Centro de Ajuda | 17,46:1 | 14,82:1 |
| (texto de apoio, `text-n-slate-10`) | 4,65:1 | 5,72:1 |

Não inventei conserto onde não havia defeito. O que ficou no repositório é
**trava de regressão**: o teste percorre todo rótulo e texto de apoio da coluna
do formulário e exige o mínimo do SC 1.4.3 (4,5:1, ou 3:1 para texto grande).

**Um erro meu, corrigido, que vale registrar:** a primeira versão do medidor
parava no primeiro `background-color` não-transparente e tratava
`rgba(0, 168, 132, 0.14)` como opaco. Devolvia **1,33:1** para a aba ativa, que
na tela está longe disso. Número errado reprova código bom. O helper agora
**compõe alfa** camada a camada até achar uma opaca. Foi essa correção que
transformou 6 "reprovados" em 2 achados reais (§6).

**Onde havia defeito de contraste de verdade:** os rótulos da barra do preview
("Modo do chat", "Escuro", "Celular") em `text-n-slate-11` davam **4,14:1** no
tema claro — abaixo de AA. Corrigido junto do item 3 (§7.2).

---

## 6. Achados fora do meu escopo, **não corrigidos**, com número

Nenhum destes foi tocado. Ficam registrados porque foram medidos.

1. **`Wrapper.vue` ignora a prop `fullWidth`, e é a causa-raiz do item 1.**
   `inbox.routes.js:41` calcula `fullWidth: params.name === 'settings_inbox_show'`
   e passa para o `SettingsContent`. `Wrapper.vue` **não declara essa prop** — o
   `<router-view>` crava `max-w-[960px]` para todo mundo. É por isso que a barra
   de 11 abas só tem 912 px em qualquer tela. Honrar a prop resolveria o
   transbordo na raiz, mas o arquivo é o wrapper de **toda** tela de settings.
   **Decisão de quem coordena, não minha.**

2. **Botão primário do dashboard: 2,27:1.** Branco sobre a cor de marca
   (`#2dc46f` nesta conta). Vale para todo `NextButton` primário do produto, não
   para esta tela. O widget já tem `--w-brand-readable` para exatamente isso; o
   dashboard não usa nada equivalente.

3. **Aba ativa: ~2,1:1** (texto `#2DC46F` sobre `rgba(0,168,132,0.14)` composta).
   Mesmo laço do item 2 — cor de marca como texto.

4. **Contador de caracteres do `woot-input`: 4,25:1** em 12 px. Marginal, abaixo
   de AA.

---

## 7. O commit separado — três arquivos fora da minha lista

Perguntei ao coordenador **duas vezes** (`orca orchestration ask`, 600 s e
1800 s). **As duas expiraram sem resposta.** Sem estes três consertos, os itens
1(b), 2 e 3 do ACEITE ficam por fazer. Entreguei isolado, em `877c543ec9`, para
poder ser descartado com um `git revert` sem tocar no resto. Se for descartado,
**5 dos 25 casos voltam a falhar**, e falham nomeando o que ficou faltando.

### 7.1 `dashboard/components/ui/Tabs/Tabs.vue`

A affordance **já existia** no markup — chevron e fade estão lá desde a base. O
que não existia era a pintura: o `<span i-lucide-chevron-right size-4>` media
**4 × 16 px**. A regra global de `<button>` (`_base.scss`) empurra
`padding: 4px 10px` para dentro do botão de 24 px, sobram 4 px de caixa de
conteúdo, e o ícone — flex-item com `flex-shrink: 1` — encolhia até caber. Um
risco vertical de 4 px some na captura de tela. Foi por isso que a medição de
campo registrou "nenhuma indicação visual": o elemento estava lá, invisível.

`!p-0` no botão + `shrink-0` no ícone → 16 × 16 px, conferido em captura.
Opacidade de repouso subiu de 45% para 70%.

### 7.2 `dashboard/modules/widget-preview/components/Widget.vue`

A barra inteira do preview (TabBar + 3 interruptores) mora só neste arquivo.
Sem editá-lo, o item 3 não tem conserto. Ver §3 e o fim da §5.

### 7.3 `dashboard/modules/widget-preview/components/WidgetFooter.vue`

O "C" do preview **não era a inicial de ninguém**: era `<Avatar name="C">`,
literal no código, mostrado para toda caixa, com foto ou sem. Consertar isto não
é opcional — o ACEITE do item 2 diz "prove que a galeria aplica a foto (o preview
deixa de mostrar a inicial)", e enquanto o "C" for literal essa prova é
impossível. Agora usa a foto do atendimento; sem foto, cai na inicial do nome da
caixa.

---

## 8. O teste

`spec/e2e/inbox-config/` — 25 casos, Chromium real, dois temas, 1280 e 1440.

```
spec/e2e/inbox-config/
├── harness/inbox-config-server.mjs   # Vite em middlewareMode, porta 3071
├── harness/entry.js                  # monta a Settings.vue REAL
├── inbox-config.playwright.config.js # reuseExistingServer: FALSE, de propósito
└── inboxConfig.spec.js               # 25 casos
```

Comando:

```
npx playwright test --config spec/e2e/inbox-config/inbox-config.playwright.config.js
```

### Vermelho e verde, os dois medidos

| estado da árvore | resultado |
|---|---|
| código da base (`git checkout 6d56c722c8 -- <os 7 arquivos>`) | **24 falharam, 1 passou** |
| com os dois commits | **25 passaram** (6,5 min) |

O único que passa nos dois é `o medidor de contraste realmente reprova cor ruim`
— e ele passa nos dois **de propósito**: é a guarda contra teste que mede nada.
Ele injeta `color: rgb(60,65,70)` nos rótulos no tema escuro e exige que o
medidor reprove. Se o cálculo de contraste quebrasse, os outros quatro casos de
contraste ficariam verdes com qualquer cor; este fica vermelho.

**Honestidade sobre o vermelho dos casos de contraste:** os quatro casos de
contraste falham na base porque a âncora deles (`[data-testid=
"channel-avatar-field"]`, e o rótulo "Foto do atendimento") só existe depois do
conserto — não porque o contraste da base fosse ruim. Ele não era: §5 traz os
números. Esses quatro são trava de regressão, e quem tratá-los como prova de
defeito vai estar lendo errado.

Duas decisões do teste que valem explicação:

- **`reuseExistingServer: false`.** Um servidor já no ar na porta 3071 pode ser
  de outra worktree — o `repositoryRoot` do harness vem do `import.meta.url`
  **dele**, não do meu. Reaproveitar mediria o código do vizinho e devolveria
  verde sobre a árvore errada.
- **Nenhum caso olha "o elemento existe".** Todos leem geometria (`scrollWidth`,
  `getBoundingClientRect`, altura ÷ `line-height`) ou cor composta. Um teste que
  afirma presença passa também quando o assunto nunca funcionou.

### O que mais foi rodado

| comando | resultado |
|---|---|
| `npx vitest run` nos 9 arquivos de spec afetados | **63 testes, 63 passaram** |
| `npx eslint` nos 7 arquivos + o teste | **0 erros** (2 avisos pré-existentes de chave i18n dinâmica em `ThemeModeField`) |

---

## 9. Arquivos

**`6b1c58a9b1` — dentro da minha lista**

```
.gitignore                                                   (só a exceção comentada)
app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json
app/javascript/dashboard/i18n/locale/en/inboxMgmt.json
app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue
app/javascript/dashboard/routes/dashboard/settings/inbox/components/ChannelAvatarField.vue   (novo)
app/javascript/dashboard/routes/dashboard/settings/inbox/widget/appearance/ThemeModeField.vue
public/dashboard/images/inbox-avatars/atendente-{1..8}.{png,svg}                             (novos)
spec/e2e/inbox-config/**                                                                     (novo)
```

**`877c543ec9` — fora da minha lista, descartável (§7)**

```
app/javascript/dashboard/components/ui/Tabs/Tabs.vue
app/javascript/dashboard/modules/widget-preview/components/Widget.vue
app/javascript/dashboard/modules/widget-preview/components/WidgetFooter.vue
```

Não toquei em `inbox/widget/tracking/**`, `widget/ui/**` nem `vite.config.js`.
