# Estado dos blocos — auditoria de árvore das Ondas 0, 1 e 2, 27/08/2026

> **O que este documento é.** A auditoria de **estado real da árvore** de `homologacao`
> (HEAD `20d8c8febe`, 27/08/2026), bloco a bloco, para as **Ondas 0, 1 e 2** do `PLANO-MESTRE.md`
> §2.2 — os **53 blocos** que a auditoria de 24/08 não cobriu. Mesmo método do
> `ESTADO-BLOCOS-24ago.md`: conferência independente, feita abrindo arquivo e rodando comando.
>
> **Ele é o par do `ESTADO-BLOCOS-24ago.md`.** Aquele cobre as Ondas 3–6 (68 blocos); este cobre as
> Ondas 0–2 (53 blocos). **Juntos, os dois cobrem os 121 blocos do plano** — pela primeira vez.
>
> **Ele revoga o `ESTADO-18ago.md` para estas três ondas.** Aquele documento conta *"Onda 0: todos,
> 0.4 e 0.10 pendentes · Onda 1: 22 de 23 · Onda 2: 19, com 3.19 PARCIAL"* — **52 blocos fechados**.
> A árvore de hoje tem **47 FEITOS, 6 PARCIAIS e 0 AUSENTES**. A diferença não é regressão: é que
> `ESTADO-18ago.md` conta bloco *com commit*, e esta auditoria conta bloco *com aceite satisfeito*.
> Os seis parciais estão nomeados um a um, com o número que os reprova.
>
> **A árvore andou 35 commits desde o `ESTADO-BLOCOS-24ago.md`** (`7b4ad0a371` → `20d8c8febe`).
> Dois desses commits mudam vereditos daquele documento e estão registrados na §5.4.

## 0. Método, e os seus limites

**As seis regras que governaram cada linha desta tabela:**

1. **"O arquivo existe" não é "o bloco está feito".** Os arquivos decisivos da coluna *Arquivos* de
   cada bloco foram **abertos e lidos**. `lib/sdk_cache_policy.rb` implementa o bloco 5.07 inteiro;
   já `LauncherField.vue` existe, tem 172 linhas e **não tem controle nenhum de `launcher_icon`** —
   o primeiro é FEITO, o segundo deixa o 3.19 PARCIAL, e a diferença só aparece lendo.
2. **Nada é FEITO por inferência de nome de caminho** — e este relatório **desfaz um erro desse tipo
   que já estava escrito**: o `o4-tracking-client.md` declara o 5.07 *"verificado NÃO feito"* porque
   olhou o arquivo que o plano nomeia (`production.rb:24-26`) e o achou intacto. O bloco foi feito
   em **outro arquivo** — um middleware — e está no ar. Detalhe na §5.2.
3. **Onde o ACEITE é executável, ele foi executado**, e o resultado está na coluna *Evidência*.
   Rodaram nesta auditoria: **rspec — 341 exemplos, 0 falhas**, em banco dedicado
   (`chatwoot_test_aud012`); **vitest — 93 arquivos / 1.418 testes, 0 falhas**; a **suíte Playwright
   do widget inteira — 68 testes, 62 verdes e 6 vermelhos**, com os 6 periciados um a um (§5.5);
   **3 verificadores de navegador** (Chromium real); o **verificador por sabotagem do 0.11**; o
   **gate de peso**; e **`curl` contra o nginx desta VM**. Detalhamento na §8.
4. **Onde não é executável, está escrito NAO-VERIFICAVEL com a razão.** Nunca inventei.
5. **Bloco cortado ou realocado está registrado e não entra na contagem** (tabela abaixo).
6. **A contagem vem do `PLANO-MESTRE.md`**, não de memória: 11 blocos na Onda 0, 23 na Onda 1, 19 na
   Onda 2 — conferido somando as linhas de cada tabela e batendo os pontos (P=1, M=3, G=8, P/M=2,
   §0.5) contra o total declarado em cada cabeçalho. **As três somas fecham exatamente: 24, 50 e 56.**

**Blocos CORTADOS ou realocados que não entram na contagem:**

| Bloco | Onda nominal | O que o plano diz | Contado aqui? |
|---|---|---|---|
| ~~**1.21**~~ | Onda 1 | **CORTADO** pela decisão **D6** (backfill de origem). A linha permanece riscada no plano para ninguém a reintroduzir achando que foi esquecimento | **Não.** A Onda 1 tem 23 blocos *sem* ele, e o cabeçalho já conta 23 |
| **5.07** | numeração da Onda 4 | **realocado para a Onda 1** (§3 item 11) | **Sim**, dentro da Onda 1 — é onde o plano o coloca |
| **3.15** | numeração da Onda 2 | **executa na Onda 5**, por dependência de 2.01/2.06 | **Não.** Auditado no `ESTADO-BLOCOS-24ago.md` §3 |

**O que esta auditoria NÃO mediu, declarado:**

- **A frota.** Os blocos **0.4** (compressão) e **0.10** (chaves de cifra) têm aceite que diz
  *"em todas as VMs"*. O briefing proíbe tocar VM remota, então medi **só esta VM** e li o
  inventário do `onda-0-infra-0.4-0.10-EXECUTADO.md` para o resto. Está marcado na linha.
- **Validação em navegador real de tela do dashboard** (o aceite do 1.17 pede *"light e dark"*).
  Exige dashboard servido e sessão autenticada; marcado NAO-VERIFICAVEL na linha.
- **Nada foi alterado fora deste arquivo.** Nenhuma migration rodou, nenhum banco de produção foi
  tocado, nenhum build foi disparado, nada foi pushado. O rspec usou `POSTGRES_DATABASE=chatwoot_test_aud012`.
- **O gate de peso e o CSS do widget foram medidos contra o build do checkout principal**
  (`/home/chatwoot/chatwoot/public/vite`), porque `public/vite*` é ignorado pelo git e não existe
  nesta worktree. **A medição é válida e isso foi verificado**: aquele checkout está no **mesmo
  HEAD** (`20d8c8febe`, só `public/version.json` modificado) e **nenhuma fonte de `app/javascript/`
  é mais nova que o manifest** (`find -newer` → vazio). É a mesma cautela da §5.3 do documento de 24/08.

---

## 1. Onda 0 — Terreno *(11 blocos · 24 pontos · 6,4% do esforço)*

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **0.1** | Harness Playwright do widget + baseline, axe e contraste | `package.json`, `playwright.config.js`, `spec/e2e/widget/` ⚪ | **sim** | **sim — o aceite literal, em três partes** | `npx playwright test --project=widget --list` → **68 testes em 8 arquivos**. As suítes antigas **não regrediram**: `--project=desktop-chromium --list` → **108 testes em 23 arquivos**, dos quais **30 são de `copilot/` e `resolve-gate/`** (os projetos de dashboard têm `testIgnore: /widget\//`, então os três convivem). Baseline: **20 PNG** em `spec/e2e/widget/snapshots/` + `baseline.json` declarando a matriz (5 vistas × 2 temas × 2 viewports). **axe e contraste medidos dentro do mesmo teste** (`widget.spec.js:340-389`, `AxeBuilder` + `computedContrast` com `toBeCloseTo(…, 2)`). **A suíte foi RODADA, não só listada: 62 de 68 verdes** (5,6 min) — o harness sobe, mede e reprova. Os 6 vermelhos estão periciados um a um na §5.5 e **nenhum é defeito de produto**; 4 deles são **PNG deste baseline que congelaram o contraste que o 1.02 consertou**, e por isso o bloco leva ⚠: o harness cumpre o aceite, os artefatos dele envelheceram | **FEITO** ⚠ |
| **0.2** | Merge da v4.16.2, sozinho | 113 arquivos do widget | **parcial** | **sim — e reprova por hash de blob** | `package.json` diz **4.16.2**, mas **`config/app.yml` ainda diz `4.12.1`** — e é ele que alimenta `Chatwoot.config[:version]`, ou seja **a instância se apresenta como 4.12.1** no super_admin, no `/api`, no `APP_VERSION` do dashboard e no `ChatwootHub`. O snapshot do merge (`93571c69db`) trazia `4.16.2` no `app.yml`; o recorte não o carregou. **`git merge-base --is-ancestor v4.16.2 HEAD` → falso**: a tag não é ancestral, o merge não existe no grafo. Por hash de blob, dos **82 arquivos** que o upstream tocou em `app/javascript/widget/` entre v4.12.1 e v4.16.2: **0 iguais a v4.16.2**, **59 ainda byte-a-byte em v4.12.1** (55 traduções + **7 de código**), 20 híbridos, 3 adicionados e ausentes. Detalhe e impacto na §5.1 | **PARCIAL** |
| **0.3** | Reconciliar o build: o upstream quebrou `vite.config.ts` em 4 | `vite.config.ts`, `vite.lib.config.ts`, `vite.shared.ts`, `vitest.config.ts` | **sim** | sim — leitura dos 4 arquivos | Os quatro existem (8.618 / 2.090 / 975 / 1.482 B), mais três nossos (`vite.sdk-css.ts`, `vite.stats.ts`, `vite.tracking.config.ts`). **SDK sai IIFE**: `vite.lib.config.ts:45,50-51` — `inlineDynamicImports: true`, `formats: ['iife']`, `name: 'sdk'`. **`manualChunks` do Leaflet deletado, não portado**: `grep -n -i leaflet vite*.ts` → **vazio**, e o gate do 0.5 confirma por duas vias que o Leaflet está fora do first-paint | **FEITO** |
| **0.4** | gzip/brotli para `text/css` e `application/javascript` nas **4 VMs** | fora do repo (nginx) | **n/a** | **parcial — só esta VM** | `curl -skI -H "Accept-Encoding: gzip, br"` contra o nginx local: `/packs/js/sdk.js` → `content-encoding: br` + `vary: Accept-Encoding` (`content-type: text/javascript`); `/vite/assets/widget-*.css` → idem (`content-type: text/css`). **Nesta VM o aceite PASSA.** O `onda-0-infra-0.4-0.10-EXECUTADO.md` só cobre os dois vhosts **deste mesmo nginx** (`hmlchat` e `chatspx.app`) — **as outras 3 VMs não aparecem nem no relatório nem foram medidas aqui** (briefing proíbe tocar VM remota). O aceite diz *"nas 4 VMs, não só homologação"* | **PARCIAL** |
| **0.5** | Gate que mede o **grafo** + trava do Leaflet + teto do `sdk.js` | `scripts/widget-size.mjs` ⚪ | **sim** | **sim — rodado** | `node scripts/widget-size.mjs` (28.777 B) contra o build vigente. **Reporta o grafo, não o chunk**: 289.488 B gzip de JS eager (vs. 39.699 B do chunk de entrada, *"o que o glob media"*). **Trava do Leaflet em DUAS deteções** — nominal (`leaflet-*.js` no fecho) e **por conteúdo** (assinatura do Leaflet em qualquer arquivo do fecho, porque o Rollup o inlina quando o import vira estático): **8 entradas / 38 arquivos varridos, nenhum**. **Os dois tetos do `sdk.js` existem e imprimem o delta** contra a linha de base §12 (29.014 B / 9.595 B). O gate **roda e sai VERMELHO** — que é o projeto dele, e o número está na §5.3 | **FEITO** |
| **0.6** | Teste de paridade entre os **dois montadores** de config | spec novo ⚪ | **sim** | sim — rspec | Quatro specs de paridade/varredura: `widget_configuration_builder_parity_spec.rb`, `widget_tokens_builder_parity_spec.rb`, `widget_public_config_secret_scan_spec.rb`, `widget_pre_chat_payload_parity_spec.rb` — **15 exemplos, 0 falhas**. O mecanismo é o que o aceite pede: acrescentar chave em um só dos dois arquivos faz a suíte falhar nomeando a chave (e foi o que segurou o 3.04, §3) | **FEITO** |
| **0.7** | Limpeza morta: `WidgetBuilder.vue`, 2 chaves órfãs, namespace `inboxWidget` | `settings/inbox/WidgetBuilder.vue`, `i18n/` | **sim** | **sim — o aceite literal do grep** | `grep -rn WidgetBuilder app/javascript` → **vazio**. `inboxWidget.json` existe em **`pt_BR` e `en`** — e hoje já é o namespace de toda a Onda 2 (a tela de aparência, gatilhos, rastreio e pré-chat leem dele) | **FEITO** |
| **0.8** | Dívidas de coerência: `NPS.*` em `en`, cor default unificada (D11), aviso de `allowed_domains` (D8), cortar `import 'widget/i18n'` (D10) | `i18n/en/inboxMgmt.json`, `Website.vue`, `ConfigurationPage.vue`, `helper/preChat.js` | **sim** | **sim — as 4, uma a uma** | (a) **`NPS.*`: 63 chaves em `en` e 63 em `pt_BR`** — contadas por travessia recursiva do JSON, não por grep de linha; painel em `en` não mostra chave crua. (b) **D11**: `Channel::WebWidget::DEFAULT_WIDGET_COLOR = '#2dc46f'` é `attribute … default:` no modelo, espelhado em `dashboard/constants/widget.js:13` e consumido por `Website.vue:24` e `Onboarding::WebWidgetCreationService` — **tela e API nascem da mesma cor**. (c) **D8**: `ConfigurationPage.vue:346` traz `<Banner v-if="hasNoAllowedDomains">` com `EMPTY_WARNING.{TITLE,BODY,ACTION_HINT}` presentes **nos dois idiomas** (*"Qualquer site pode embutir este widget"* / *"Any website can embed this widget"*). (d) **D10**: `grep 'widget/i18n'` em `dashboard/` → **vazio**; o único resto é um spec de `shared/`, que é legítimo | **FEITO** |
| **0.9** | `ColorPicker` para de mutar o store direto (D2) | `Settings.vue:231-233, 948, 538` | **sim** | sim — vitest | `<ColorPicker v-model="channelWidgetColor" />` (`Settings.vue:1142`) escreve numa `data` local, semeada de `this.inbox.widget_color` (`:546`) e só enviada em `updateInbox` (`:716,730`). **Nenhuma atribuição a `this.inbox.<campo>`** no arquivo. `Settings.colorPickerStore.spec.js`: **4 testes, verdes** | **FEITO** |
| **0.10** | Provisionar `ACTIVE_RECORD_ENCRYPTION_*` na frota e inventariar | `.env` de cada VM | **n/a** | **parcial — só esta VM** | **Nesta VM: as 3 chaves estão no `.env`** (`PRIMARY_KEY`, `DETERMINISTIC_KEY`, `KEY_DERIVATION_SALT`) e o `onda-0-infra-…-EXECUTADO.md` registra `configured? = true` no processo vivo desde o restart de 24/08. **Na frota o aceite continua REPROVADO, pelo próprio relatório**: 5 VMs foram provisionadas mas **NÃO reiniciadas** — enquanto não reiniciarem, o processo vivo segue com `configured? = false`; e **ALTERNATIVO `.169` e PAULAO `.100` ficaram sem rota**, não verificadas. O aceite diz *"→ `true` em todas"*. Não medido aqui por proibição de tocar VM remota | **PARCIAL** |
| **0.11** | O fixture anti-erro: todo E2E falha com `console.error`, `pageerror` ou HTTP 4xx/5xx | `spec/e2e/fixtures.js` ⚪, lista `IGNORAR` | **sim** | **sim — e o verificador SABOTA, que é o padrão-ouro** | `spec/e2e/fixtures.js` (11.801 B) com as 4 categorias (`pageerror`, `console`, `http`, `rede`) e **`IGNORAR = []`** — lista vazia, então *"toda entrada tem comentário"* não tem como falhar. `node spec/e2e/widget/fixture-antierro.check.mjs` → **11 de 11 verificações**, e **8 delas provam o vermelho injetando o defeito**: reprova `console.error`, reprova `pageerror`, reprova HTTP 500 **nomeando método e URL**, reprova falha de rede, reprova erro em **janela nova**, reprova `errosEsperados` obsoleto, recusa padrão catch-all. Duas provam o verde (página limpa; erro que o próprio cenário provoca). A 11ª é o aceite do grep: **nenhum dos 31 `*.spec.js` de `spec/e2e/widget/**` importa `test` de `@playwright/test`** — o único casamento textual é uma **citação do aceite dentro de um comentário** do próprio verificador | **FEITO** |

### Fecho da Onda 0

**11 de 11 blocos com código ou infraestrutura entregue; 8 FEITOS e 3 PARCIAIS.** Os três parciais
não são "quase pronto", são três coisas diferentes:

- **0.2** é o único parcial de **código**, e o achado é estrutural: o merge não está no grafo, a
  versão que a instância anuncia é a velha, e 7 arquivos de código do widget nunca receberam o
  delta do upstream. **Um deles (`ArticleViewer.vue`) é o que reprova o 3.17** (§3).
- **0.4 e 0.10 são de frota**, não de repositório. Os dois estão **FEITOS nesta VM e abertos fora
  dela** — e o 0.10 é o que segura o 5.02, que é o maior pedaço parado do plano inteiro.

---

## 2. Onda 1 — Nada mentindo *(23 blocos · 50 pontos · 13,3% do esforço)*

> **É a onda mais fechada das três.** 22 de 23 blocos com aceite satisfeito, e o único parcial
> (1.08) reprova por um número que **outros blocos** empurraram para cima depois que ele fechou.

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **1.01** | Folha de tokens em arquivo próprio | `widget/assets/scss/_tokens.scss` ⚪ | **sim** | **sim — o aceite literal** | `_tokens.scss` (131 l.) nasceu do recorte integral do `@layer base` de `woot.scss`, com os mixins `widget-brand-light` / `widget-shape`. **`woot.scss` não define mais valor de token**: `grep '--w-.*:'` nele → vazio; só o `@import 'tokens'` na mesma posição, para o CSS sair byte a byte na mesma ordem | **FEITO** |
| **1.02** | Tokens de marca calculados no servidor (luminância WCAG, limiar 0,17913) | `app/services/widget_tokens.rb` ⚪, `show.html.erb` | **sim** | sim — rspec | `WidgetTokens` (229 l.): `LUMINANCE_THRESHOLD = 0.17913`, `on_color`, `contrast_ratio`, `readable_on`, `sanitize` (cor inválida **não** é interpolada). `widget_tokens_spec.rb` + `widget_tokens_builder_parity_spec.rb` **verdes**, e o `_tokens.scss` documenta o par medido: `L(#2dc46f)=0,411854 > 0,17913 → --w-on-brand: #000000`, contraste **9,2371:1** | **FEITO** |
| **1.03** | Os mesmos tokens atravessam a ponte e pintam o **launcher** | `IframeEventHelper.js`, `IFrameHelper.js` | **sim** | sim — Chromium | `applyWidgetTokens` (`IFrameHelper.js:70`) com alfabeto fechado por regex — hex de 3/6/8 dígitos ou `var(--w-…)`, nada mais. `onLoad` repassa `tokens` do servidor (`:607-624`) e o comentário registra por que repassar `widgetColor` cru **não** é calcular contraste. **Nenhuma fórmula de contraste em JS de runtime** — o `launcher-hover.check.mjs` mede o resultado em Chromium: repouso **e** hover em `rgb(0,156,224)`, ícone em `rgb(0,0,0)` por `currentColor` | **FEITO** |
| **1.04** | **Fim do `n-brand`**: 26 linhas, 18 arquivos, YIQ e `--widget-color` órfã | os 25 pontos da §A.1.1, `theme/colors.js` | **sim** | **sim — os 3 greps do aceite, `shared/` incluído** | `grep -rn` em `widget/`, `sdk/` **e `shared/`**: `n-brand` → **0** (o único casamento textual é a substring de `--w-on-brand`, que é o token novo, mais **uma citação em comentário** no `WAvatar.vue`); `getContrastingTextColor` → **0**; `--widget-color` → **0**. Os três vazios, que é o aceite palavra por palavra | **FEITO** |
| **1.05** | Literais do SDK → variáveis, **incluindo a armadilha do `:hover` verde** | `sdk.js`, `bubbleHelpers.js`, `IFrameHelper.js` | **sim** | **sim — Chromium, e o verificador do bloco dá 4/7** | **O aceite escrito PASSA**: `launcher-hover.check.mjs` mede em Chromium real que o launcher em `#009CE0` continua `rgb(0,156,224)` **em `:hover`**, e que a regra `:hover` usa `var(--w-brand)`. **Mas o verificador que o próprio bloco escreveu reprova 3 das 7**, e só **uma** delas é verificador desatualizado (§5.2). As outras duas são literais vivos: `sdk.js:414` (`var(--w-focus-ring-color, #2dc46f)`) e `sdk.js:351,396,406` (`color: #1f2d3d/#37546d/#6e6f73`) | **FEITO** ⚠ |
| **1.06** | A11y mínima: `lang`, `role="log"`, rótulos traduzidos, anel de foco | `show.html.erb:2`, `ConversationWrap.vue`, `HeaderActions.vue`, `_tokens.scss` | **sim** | sim — vitest + leitura | `show.html.erb:8` → `<html lang="<%= account.locale…tr('_','-') %>">`. **1 `[role="log"]`** em `ConversationWrap.vue:300`. `a11y.spec.js` (**verde**) assere os quatro: um só `role="log"` com nome em pt-BR, sem `aria-live` redundante, **todo `<button>` do cabeçalho com nome acessível não vazio e em pt-BR**, `title` e `aria-label` não divergem. **Anel de foco real e por token**: `WComposer.vue:98-100` (`outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color)`) — *não* transparente. Ressalva declarada: o `focus-ring.check.mjs` está órfão (§5.2). A dívida de a11y do widget inteiro é do bloco próprio §12.8a, **não** do aceite deste — e **medi quanto dela já caiu**: nos 16 cenários que rodaram o axe, `serious` foi de **28 para 6 (−79%)** e `critical` de **12 para 8**, com `messages-*` e `home-*-dark` zerando `serious`. O teto do `baseline.json` **não acompanhou** (§5.5) | **FEITO** ⚠ |
| **1.07** | Typing dots em CSS (mata o GIF de 19.296 B) + as 3 curvas | `AgentTypingBubble.vue`, `WTypingDots.vue` ⚪ | **sim** | sim — vitest | `WTypingDots.vue` em `widget/ui/`; `AgentTypingBubble.vue:15` documenta a troca. **`grep typing.gif` em `app/javascript/widget/` e `sdk/` → vazio** (o único resto vive em `superadmin_pages/`, outro produto). `typingDots.spec.js` **verde** | **FEITO** |
| **1.08** | Peso sem tocar componente: `content` próprio do Tailwind e assets órfãos | `tailwind.widget.config.js` ⚪, `public/brand-assets/`, fontes | **sim** | **sim, e reprova pelo número** | `tailwind.widget.config.js` existe (5.076 B) e o efeito é enorme: o CSS do widget saiu de **1.692.256 B** para **94.395 B** (−94,4%). **`grep -o "@font-face"` no CSS do widget → 0** (eram 7), e o gate confirma **0 arquivos `.woff2`, 0 B** no grafo; nenhuma referência a `brand-assets/` no CSS. **Mas o teto do aceite é 80.000 B crus e o medido é 94.395 B — +14.395 B, 18% acima.** O `onda-1-widget.md:1442` declara o bloco *"✅ FECHADO — 75.500 B"*, e estava certo **na data dele**: o que engordou os 18.895 B depois foram os blocos das Ondas 2 e 5 que acrescentaram CSS. A régua não se afrouxa (regra 4 do briefing) | **PARCIAL** |
| **1.09** | **O bridge**: 16 `else if` viram mapa, `e.origin` nos dois lados, fim do `targetOrigin: '*'` | `widget/bridge/` ⚪, `App.vue`, `helpers/utils.js` | **sim** | **sim — o aceite numérico** | **`App.vue` = 308 linhas < 310** (a margem de 3 que o plano calculou). `widget/bridge/` com `handlers.js` (**22 handlers no mapa**, de `config-set` a `toggle-open`), `origin.js`, `index.js`, `closeOnEscape.js`. **`targetOrigin` deixou de ser `'*'` incondicional**: `getParentTargetOrigin()` devolve a origem real e só cai em `'*'` quando não dá para sabê-la. Origem estranha é ignorada (`IFrameHelper.js:291`, `isTrustedFrameOrigin`). Specs por handler **sem montar o App** (`bridge/specs/`, 3 arquivos) — **verdes** | **FEITO** |
| **1.10** | Registry de `content_type` (`<component :is>`) | `widget/message-types/` ⚪ | **sim** | sim — vitest | `message-types/index.js`: `MESSAGE_TYPES` com **os 8 tipos**, `resolveMessageType` degradando para texto, e o comentário registra que os outros 6 do enum degradam de propósito. **Um 9º custa 1 arquivo + 1 linha**, e `AgentMessageBubble` não conhece `content_type` por nome. Suíte de `message-types/` **verde** | **FEITO** |
| **1.11** | HMAC, portas 1 e 2 | `contacts_controller.rb` | **sim** | sim — rspec | `IDENTITY_BINDING_PARAMS = [:identifier, :email, :phone_number]` + `before_action :validate_hmac, only: [:set_user]` **e** `validate_hmac_for_identified_update, only: [:update]` — as duas portas. E a não-regressão está no desenho: pré-chat anônimo e `setCustomAttributes` **continuam passando** em inbox com HMAC obrigatório, porque nenhum dos dois reamarra a sessão. `widget_identity_token_spec.rb` **verde** | **FEITO** |
| **1.12** | Corrigir o throttle que nunca casa (`contacts` → `contact`) | `rack_attack.rb` | **sim** | sim — rspec | `rack_attack.rb:212-214` traz a correção **com a causa escrita**: a rota é `resource :contact` (singular), o path real é `/api/v1/widget/contact`, e a comparação com o plural *"era sempre falsa e o limite nunca mordia"*. `rack_attack_widget_contact_spec.rb` **verde** — e ele roda com `Rack::Attack` ligado, que é o que a lição do `localhost esconde o Rack::Attack` exige | **FEITO** |
| **1.13** | **Retry de webhook (B3)**: exceção sobe, efeito no esgotamento, `X-Chatwoot-Delivery` estável | `lib/webhooks/trigger.rb`, `webhook_job.rb` | **sim** | sim — rspec | `WebhookJob`: `retry_on StandardError, wait: :polynomially_longer, attempts: 5` com `handle_exhaustion` **no bloco do retry** (roda uma vez, no fim, não a cada tentativa). `Webhooks::Trigger` deixa a exceção subir (`:64`, com o comentário do defeito B3). **Delivery id estável entre tentativas** por construção — usa `job_id`, que o `retry_job` preserva — e sai no header (`trigger.rb:91`). `webhook_job_spec.rb` **verde** | **FEITO** |
| **1.14** | Teto de tamanho **e de quantidade** de `custom_attributes` no contato | `contact.rb`, validador | **sim** | sim — rspec | `Contact::CUSTOM_ATTRIBUTES_MAX_KEYS = 50` + `validates :custom_attributes, jsonb_attributes_length: { max_keys: … }`. O validador **não** está no caminho que o plano supôs (`app/validators/`) — mora onde o Zeitwerk o acha. A regra *"morde no crescimento"* está no desenho da validação. Coberto no lote de `contact_spec.rb` | **FEITO** |
| **1.15** | Allowlist de nomes em `POST /widget/events` | `events_controller.rb` | **sim** | sim — rspec | `PERMITTED_EVENT_NAMES = [WEBWIDGET_TRIGGERED, CAMPAIGN_TRIGGERED]` + `422` com mensagem que **nomeia a lista** (`:133`). A allowlist ganhou depois um portão a mais (`SITE_EVENT_PREFIX`, do `track()` do 5.16) — ampliação declarada, não furo. `events_controller_spec.rb` **verde** | **FEITO** |
| **1.16** | **Auto-provisionar `CustomAttributeDefinition`** para chave nova vinda do site (B6) | serviço novo ⚪, `contact_identify_action.rb` | **sim** | sim — rspec | `CustomAttributes::AutoProvisionService`, chamado de `contact_identify_action.rb:146,152-155`. Traz as três guardas do aceite: **chave reservada não cria definição** (`STANDARD_ATTRIBUTES` por modelo, `:64`), **corrida cria uma só** (`already_exists?` + resgate que só loga, `:92`), e o `origin: ORIGIN_WEBSITE` já nasce com o selo do 4.17. `auto_provision_service_spec.rb` + `custom_attribute_definition_spec.rb`: **51 exemplos, 0 falhas** | **FEITO** |
| **1.17** | Seção **"Dados recebidos do site (N)"** no painel, com selo — e IP mascarado | `CustomAttributes.vue` | **sim** | **parcial — vitest sim, navegador não** | `CUSTOM_ATTRIBUTES.FROM_WEBSITE_SECTION = "Dados recebidos do site ({count})"` e `FROM_WEBSITE_BADGE = "Do site"`, com `data-testid="from-website-badge"` em `CustomAttributes.vue:386` — e um comentário registrando um defeito de empilhamento já corrigido. **IP mascarado por padrão** com as 4 chaves (`IP_ADDRESS_MASKED: "Oculto"`, `_REVEAL`, `_HIDE`) e o botão em `ConversationInfo.vue:74`. `CustomAttributes.spec.js`: **5 testes verdes**. A metade *"validado em navegador real, light e dark"* é **NAO-VERIFICAVEL** aqui: exige dashboard servido com sessão autenticada | **FEITO** |
| **1.18** | Seed idempotente das ~12 definições de origem | serviço/seed ⚪ | **sim** | sim — rspec | `Tracking::OriginDefinitionsSeeder` com `existing_keys` + `already_exists?` — **rodar duas vezes não duplica**, por consulta, não por `rescue`. `origin_definitions_seeder_spec.rb` **verde** | **FEITO** |
| **1.20** | **Parar de destruir o dado na escrita** | `lib/url_helper.rb` + 1 linha em `conversation.rb` | **sim** | sim — rspec | `url_helper.rb` com `REFERER_RAW_KEY`, `sanitize_referer_attribute!` e as **três saídas escritas no comentário**: URL recuperável → `referer` utilizável; não recuperável → **`additional_attributes['referer_raw']`, nunca `nil` silencioso**; vazia → nem cria a chave. `url_helper_spec.rb` + `conversations_referer_spec.rb` + `conversation_origin_spec.rb` **verdes**, e a 5ª asserção (`referer_raw` não vaza para o widget nem para prompt de IA) tem spec próprio no enterprise (`runner_state_helper_referer_raw_spec.rb`) | **FEITO** |
| **1.19** | **Parser de origem (C0)**, prospectivo (D6) | `app/services/tracking/` ⚪ | **sim** | sim — rspec | `Tracking::OriginParser`: `utm_*`, `gclid`/`gbraid`/`wbraid`, `fbclid`, `msclkid`, `ttclid`, host e path; **`last_*` na conversa, `first_*` write-once no contato** decidido fora do parser (`:6`). **A lista de IA generativa existe e é dupla** — por host (`chatgpt.com`, `chat.openai.com`, `perplexity.ai`, `gemini.google.com`, `bard.google.com`, `claude.ai`, `copilot.microsoft.com`) **e por token de `utm_source`** (`:20`), com a ordem certa: `ia_generativa` é testado **antes** de busca orgânica, senão `gemini.google.com` cairia em "google" (`:101,110`). `origin_parser_spec.rb` **verde** | **FEITO** |
| **1.22** | Relatório mínimo: conversas por `utm_source`/`medium`/`campaign` | serviço + tela | **sim** | sim — rspec + vitest | `Tracking::OriginReport` + `GET …/origin_report` (`api/reports.js:132`) + `ConversationOriginReports.vue` na rota de relatórios. **As duas armadilhas do aceite estão tratadas**: conversa sem origem sai `value: nil` e o front a rotula *"origem não disponível"* (nunca "direta"), e o período anterior à medição tem **rótulo próprio** — `ORIGIN_REPORTS.BEFORE_MEASUREMENT.{TITLE,WHOLE_RANGE,PARTIAL}` (`:111-119`), nunca vazio nem zerado. `origin_report_spec.rb`, `origin_reports_controller_spec.rb` e `ConversationOriginReports.spec.js` **verdes** | **FEITO** |
| **1.23** | **O contrato do SDK deixa de ser mudo**: `Promise` em tudo, fila pré-boot | `entrypoints/sdk.js`, `widget/bridge/` ⚪ | **sim** | sim — vitest | `entrypoints/sdk.js` documenta e implementa as três regras: nunca lança (chamada malformada vira `Promise.reject`, `:84-99`), **retorna `Promise` que resolve quando a mensagem saiu de fato — inclusive da fila pré-boot** (`:69-70`), e trata o visitante que sai antes do boot (`:286`). `preBootQueue.spec.js`, `track.spec.js`, `snippetConfig.spec.js`, `settingsHelpers.spec.js` **verdes** | **FEITO** |
| **5.07** | **Propagação do SDK** (realocado da Onda 5) | `production.rb:24-26` + carregador fino | **sim** | **sim — rspec + headers vivos** | **Feito por middleware, não pelo arquivo que o plano nomeia** — e é por isso que um relatório de trilha o declarou ausente (§5.2). `lib/sdk_cache_policy.rb`: `SDK_PATHS = ['/packs/js/sdk.js', '/packs/js/tracking.js']`, `MAX_AGE = 300`, `CACHE_CONTROL = "public, max-age=300, must-revalidate"`, plugado em `config/initializers/sdk_cache_policy.rb` com `insert_before 0`. **Medido no ar nesta VM**: `curl -skI …/packs/js/sdk.js` → `cache-control: public, max-age=300, must-revalidate` + `last-modified`. `sdk_cache_policy_spec.rb`: **10 exemplos, 0 falhas**. A metade *"conferido nas VMs da frota"* é NAO-VERIFICAVEL aqui | **FEITO** |

### Fecho da Onda 1

**22 de 23 blocos com aceite satisfeito.** O único parcial, o **1.08**, é a lição mais útil desta
onda: **ele fechou correto e foi reaberto pelo peso que outros blocos acrescentaram depois**. Um
teto medido uma vez, na data do bloco, não protege ninguém; o que protege é o gate do 0.5 rodando no
CI — e ele hoje já cobra o `sdk.js`, mas **não cobra o CSS de 80 KB do 1.08** (o teto dele é o do
grafo, 300 kB, que passa). Essa é a folga que deixou os 18.895 B entrarem sem ninguém ver.

As duas marcas ⚠ (1.05 e 1.06) **não são aceite reprovado** — são verificadores que ficaram atrás do
código, e a §5.2 mostra por quê.

---

## 3. Onda 2 — Configuração *(19 blocos · 56 pontos · 14,9% do esforço · blocos `3.xx`)*

| Id | Título curto | Arquivos que o plano pede | EXISTEM? | ACEITE verificável agora? | Evidência | Veredito |
|---|---|---|:---:|---|---|:---:|
| **3.01** | **O lar da configuração**: as 4 chaves em `additional_attributes` | `inbox.rb`, `inboxes_controller.rb` | **sim** | sim — rspec | `WidgetConfigurable` com `store_accessor :additional_attributes, :widget_profile, :widget_triggers, :widget_tracking, :widget_appearance` e **uma validação por chave**. Strong params: **as quatro declaradas de uma vez** (`inboxes_controller.rb:268-270`), que é a arbitragem A1. `inbox_widget_config_spec.rb` e `inboxes_controller_widget_config_spec.rb` **verdes** — incluindo *"PATCH parcial de uma chave não apaga as outras três"*. A lista negativa de segredo entra já aqui e 5.01 a amplia | **FEITO** |
| **3.02** | Schema dos gatilhos validado por `json_schemer` | `inbox.rb`, schema novo ⚪ | **sim** | sim — rspec | `WidgetTriggersSchema` (`app/models/concerns/`), validado por `json_schemer`, com `WidgetSchemaErrorMessage` para o 422 **nomear o campo**. `inbox_widget_triggers_schema_spec.rb` **verde** | **FEITO** |
| **3.20** | **A abordagem em três níveis vira schema** | schema ⚪, `inbox.rb`, os 2 montadores | **sim** | sim — rspec | `APPROACHES = %w[discreet bold aggressive]`, `DEFAULT_APPROACH = 'bold'`, e — a asserção que só existe porque alguém pensou no celular — **`MOBILE_APPROACHES = %w[discreet bold]`**, com o comentário da razão (*"em celular o painel cobre a tela inteira, que é onde auto-open é mais hostil"*). `degrade_on_return` booleano. Os três campos saem na projeção pública (§3.04), que é o que a A5 exige. `inbox_widget_approach_spec.rb` **verde** | **FEITO** |
| **3.03** | `WidgetProfile.resolve` → **flags planas**; troca **propõe**, nunca reescreve | `app/services/widget_profile.rb` ⚪ | **sim** | sim — rspec | `WidgetProfile` (`:1` "o perfil resolvido em FLAGS PLANAS") lê as colunas já existentes — `csatOnResolve` sai de `inbox.csat_survey_enabled?` (`:82`) — e o comentário `:56-58` registra a regra A3 explicitamente: inbox com CSAT desligado e perfil `support` **continua desligada**. `widget_profile_spec.rb` **verde**. Sem migration e sem backfill | **FEITO** |
| **3.04** | Entregar as **quatro** chaves ao widget **nos dois montadores** | `show.html.erb`, `configs/create.json.jbuilder` | **sim** | **sim — e o 0.6 é quem cobra** | Os dois montadores trazem as quatro, na mesma ordem: ERB `:68-72` (`widgetProfile`, `profileConfig`, `widgetTriggers`, `widgetTracking`, `widgetAppearance`) e jbuilder `:52-56` (idem em snake_case). **`widget_tracking` sai pela projeção pública** (`public_widget_tracking`), não cru. Paridade + varredura por `token`/`secret`: **15 exemplos, 0 falhas** (§0.6) | **FEITO** |
| **3.05** | O widget consome **flags planas**, nunca o nome do perfil | `configMixin.js`, `store/modules/appConfig.js` | **sim** | **sim — e o aceite virou lint executável** | `widget/specs/profileFlagsLint.spec.js` **transforma o grep do aceite em teste**: varre os templates de `widget/` e falha se **qualquer `v-if`/`v-else-if`/`v-show` citar `widgetProfile`**, com uma allowlist explícita para o resolvedor e seus consumidores diretos. **Verde.** É a forma mais forte deste aceite — grep de auditoria envelhece, lint no CI não | **FEITO** |
| **3.06** | `useInboxWidgetConfig` (rascunho, `isDirty`, payload, salvar) + barra + confirmação | `inbox/widget/composables/` ⚪ | **sim** | sim — vitest | 9 módulos em `composables/` (`useInboxWidgetConfig`, `useUnsavedChangesGuard`, `useContrast`, `useProfileVisibility`, os 3 *contracts* e os 2 de campos/rótulos) + `WidgetSaveBar.vue` e `WidgetUnsavedChangesDialog.vue`. `useInboxWidgetConfig.spec.js` e `useUnsavedChangesGuard.spec.js` **verdes** | **FEITO** |
| **3.07** | Seletor de perfil (2 `RadioCard`) + `useProfileVisibility` + a pergunta no wizard | `inbox/widget/` ⚪, `channels/Website.vue` | **sim** | sim — vitest | `WidgetProfileSelector.vue` + `WidgetProfileSwitchDialog.vue` (o diálogo que **lista nominalmente o que muda e o que continua gravado**) + `useProfileVisibility.js`. No wizard: `Website.vue:110` traz `<WidgetProfileSelector v-model="widgetProfile" allow-empty />` — **`allow-empty` é o "sem default pré-selecionado"** do aceite, e o comentário `:30` registra a razão. Specs **verdes** | **FEITO** |
| **3.08** | **O medidor de contraste**: 4 pares com `color2k`, veredito, cor ajustada | `ContrastReadout.vue` ⚪, `useContrast.js` ⚪ | **sim** | sim — vitest | `useContrast.js` importa `getContrast`/`getLuminance`/`parseToRgba` de `color2k`, expõe `contrastPairs(hex)` e formata **duas casas em pt-BR** (`2,27`). O cabeçalho registra o número do aceite: *"verde com texto branco dá 2,27:1, reprova AA e reprova até o mínimo"*. `useContrast.spec.js` **verde** — e a comparação com o servidor (1.02) é feita com `toBeCloseTo`, que é a armadilha que o plano mandou evitar | **FEITO** |
| **3.09** | Tela 1 completa, ligada ao roteador de abas + i18n pt-BR **e** en | `appearance/` ⚪, `Settings.vue`, `i18n/*/inboxWidget.json` | **sim** | sim — vitest | 6 componentes / **743 linhas** (`AppearancePage` 310, `LauncherField` 172, `ContrastReadout` 127, `BrandColorField` 48, `AppearanceOverrideBanner` 46, `ThemeModeField` 40), plugados em `Settings.vue:45-47,87` e no roteador de abas (`:164,182`). **O aviso de override existe e é o que o aceite pede**: `AppearanceOverrideBanner.vue` com `data-testid="override-banner"` e `OVERRIDE.BODY` recebendo **a lista de campos sobrescritos**, em vez de mentir. `Settings.widgetAppearance.spec.js` **verde** | **FEITO** |
| **3.10** | Preview honesto: tokens reais (mata as ~74 custom properties, D4), 7 derivados, toggles | `modules/widget-preview/` | **sim** | **sim — com uma ressalva de letra, não de mérito** | Os toggles existem e são **independentes do tema do dashboard**: `isDarkPreview` e `isMobilePreview` (`Widget.vue:89,96,235,247`) trocam a classe do wrapper. E o mecanismo é o certo: `.wp-theme-light { @include widget-palette-light; }` / `.wp-theme-dark { … }` (`:381-387`) — **o preview declara as vars a partir dos mixins do widget**, que é exatamente o que D4 pede. **A letra do aceite (`grep --slate-/--solid-` → vazio) não passa mais**: há **5 ocorrências**, todas em `WidgetPreChatPreview.vue:131-149` — arquivo do bloco **3.16**, posterior. Não são as ~74 literais do D4: são leituras de vars que o wrapper declara, e o comentário do arquivo explica que o nome da classe mudou para escapar dos seletores `[class*='text-n-slate-*']` do skin do dashboard. **Mérito satisfeito, grep desatualizado** | **FEITO** ⚠ |
| **3.11** | Fim do snippet montado por corte de string no byte 13 (D3) | `widget-preview/Widget.vue`, backend | **sim** | sim — rspec + leitura | `Widget.vue:114-132`: o snippet chega **pronto do servidor** por `props.webWidgetScript` (`Channel::WebWidget#web_widget_script`), e o comentário nomeia o defeito morto (`script.substring(0, 13)`) e a consequência (*"mexer numa chave de tradução quebrava o snippet de todo mundo naquele idioma"*). **Tradutor não alcança mais o snippet.** `web_widget_fallback_snippet_spec.rb` **verde** | **FEITO** |
| **3.12** | Ampliar `EDITABLE_ATTRS` do pré-chat: 7 chaves novas | `web_widget.rb:34-40` | **sim** | sim — rspec | `EDITABLE_ATTRS` (`:53-60`) traz `:step, :position, :mask, :validator, :help_text, :error_message` e **`show_if` como hash aninhado** (`{ show_if: [:field, :operator, :value] }`) — que é o detalhe que faz `permit` funcionar. Forma inválida é rejeitada pelo `PreChatFormSchema` (`:277`). Verde no lote da Onda 2 | **FEITO** |
| **3.13** | Máscaras e validadores BR: CPF, CNPJ, CEP, UF, e-mail corporativo, anti-lixo | `helper/brMasks.js` ⚪ + espelho no widget | **sim** | sim — vitest | **Três cópias coerentes**: `shared/helpers/brMasks.js` (a fonte, com spec), `dashboard/helper/brMasks.js` e `widget/helpers/brMasks.js` — consumidas pelo editor de campo (3.14) e pelo `CaptureField.vue` (4.03). `MASKS = %w[cpf cnpj cpf_cnpj cep uf phone]` também no Ruby (`pre_chat_form_schema.rb:26`), então tela e servidor falam o mesmo alfabeto. `brMasks.spec.js` **verde** — e cobre a regra de dígitos repetidos, que é a asserção que separa um validador de DV de um validador de verdade | **FEITO** |
| **3.14** | Tela 3 (pré-chat): editor, etapas com teto de 8, condicional, 3 modos e i18n | `prechat/` ⚪ | **sim** | sim — vitest | 5 arquivos / **1.038 linhas**. **`MAX_ENABLED_FIELDS = 8` e `MAX_STEPS = 8`** com `canAddStep` cobrando o teto. **Os três modos existem nomeados**: `MODES = ['simple', 'builder', 'flow']`, com `toBuilder`/`toSimple` e o comentário do §B.4.1 — *"Construtor → Simples não apaga nada"*, que é o aceite de migrar sem perder campo. **Validação no blur**: `@blur="labelTouched = true"` / `previewTouched` (`PreChatFieldEditor.vue:136,215`). Suíte **verde** | **FEITO** |
| **3.16** | Prévia da etapa 1 do pré-chat dentro do preview | `widget-preview/` | **sim** | sim — vitest | `WidgetPreChatPreview.vue` montado por `Widget.vue:7`, com `data-testid` por elemento (`prechat-preview-submit`, `prechat-preview-steps`) e o rótulo *"etapa 1 de N"*. `WidgetPreChat.spec.js` **verde** | **FEITO** |
| **3.17** | Tela inicial por perfil e base de conhecimento por flag (+ o `bg-white` sem `dark:` do `ArticleViewer`) | `views/Home.vue`, `Article/*`, `ArticleViewer.vue:13` | **parcial** | **sim, e reprova a metade menor** | **A metade grande passa e é a que vale**: `Home.vue:49-57` traz `<ArticleContainer v-if="showKnowledgeBase" />` com o comentário registrando que o `v-if` (e não `v-show`) é o que impede o request; `HomeKnowledgeBase.spec.js` **verde**, e ele espiona `API.get` — mede **rede**, não aparência, que é o aceite literal (*"nenhum request a `/articles` sai"*). **A metade menor não foi feita**: `ArticleViewer.vue:13` continua `<div class="bg-white h-full">`, **sem `dark:`**. E não é descuido de leitura minha — o arquivo é **byte-a-byte idêntico a `v4.12.1`** (`git hash-object` = `git rev-parse v4.12.1:…` = `9289d054`), ou seja **nem o upstream nem nós o tocamos** (§5.1). O `onda-2-resto.md:245,396` **declara isso**: *"não foram tocados — coordenador rotear"* | **PARCIAL** |
| **3.18** | **A aparência sai do `localStorage` e vira configuração** | schema ⚪, `inbox.rb`, os 2 montadores, `Settings.vue`, `constants/localStorage.js` | **sim** | sim — rspec + vitest | `WidgetAppearanceSchema` com os **9 campos** (`theme`, `position`, `offset_x`, `offset_y`, `launcher_type`, `launcher_text`, `hide_bubble`, `panel_style`, `launcher_icon`), `enum`/`maximum` por campo e **DEFAULTS lidos sem migration** (regra A4). O mapa `:59-64` é a peça que faltava: traduz a chave nova para o nome que o `chatwootSettings` do site usa (`theme→darkMode`, `hide_bubble→hideMessageBubble`…), que é como a **regra de precedência** se sustenta. **A leitura por `localStorage` foi removida**: `grep position/offset/launcher` em `constants/localStorage.js` → **vazio**. `inbox_widget_appearance_spec.rb` **verde** | **FEITO** |
| **3.19** | **O ícone do lançador deixa de ser um `path` fixo** — 9 asserções | `sdk/bubbleHelpers.js`, `widget_appearance`, `appearance/`, ActiveStorage | **parcial** | **sim — 5 de 9 medidas em Chromium, 4 ausentes** | **A metade SDK está completa e medida**: `LAUNCHER_ICON_MODES = ['default','image','agent_photo']`, `resolveLauncherIcon` com a degradação escrita (`agent_photo` sem avatar → `default`), `onerror` voltando ao `bubbleSVG` (`:155`), `preloadLauncherImage`, e `setBubbleAccessibleName`. **`launcher-icon.check.mjs`: 13/13 asserções em Chromium real**, incluindo os três pares de contraste do anel (3,727 / 4,759 / 17,928 — todos ≥ 3:1, SC 1.4.11) e a não-regressão do balão. **A metade TELA não existe**: `LauncherField.vue` (172 l.) **não tem controle nenhum de `launcher_icon`** — o campo só aparece no *contract* (`widgetAppearanceContract.js:20`) e no default (`widgetConfigFields.js:45`). Sem upload, **sem o teto de 20 KB**, e **sem o aviso "rosto converte mais"** da decisão D5 (`grep rosto` no i18n → vazio). O próprio spec do bloco declara as 4 como bloqueadas (`bubbleHelpers.spec.js:11-14`) — a diferença é que **3.18 e 3.09, que as bloqueavam, já fecharam** | **PARCIAL** |

### Fecho da Onda 2

**17 de 19 blocos com aceite satisfeito.** A onda inteira do backend de configuração (3.01–3.04,
3.12, 3.18, 3.20) está fechada e com spec, e é ela que sustenta metade da Onda 3 auditada em 24/08.

Os dois parciais têm a **mesma forma**, e é uma forma que vale registrar: **um bloco cujo aceite tem
duas metades, com a metade grande feita e a pequena roteada para outro lugar** — e ninguém voltou.
No 3.17 é uma classe CSS de uma linha; no 3.19 são quatro asserções de tela que **já estão
destravadas** desde que 3.18 e 3.09 fecharam. As duas são das correções mais baratas do plano inteiro.

---

## 4. Ondas 0, 1 e 2 — o que estas três ondas garantem hoje

Vale dizer em uma linha o que os 47 blocos FEITOS compram, porque é a base de tudo que as Ondas 3–6
apoiam em cima:

1. **Terreno medido** — harness de 20 snapshots com axe e contraste, fixture que **reprova erro de
   console**, gate de peso que mede o grafo, e paridade que impede os dois montadores de divergirem.
2. **Nada mentindo** — a cor da marca sai do servidor com contraste WCAG calculado, o `n-brand` e o
   YIQ morreram, o bridge tem origem validada, o webhook **tenta de verdade** 5 vezes, o throttle do
   contato **casa**, o HMAC fechou as duas portas, e a origem do visitante **para de ser apagada na
   escrita** — com parser prospectivo, seed idempotente e relatório que diz *"antes da medição"* em
   vez de zero.
3. **Configuração** — as quatro chaves têm lar, schema, strong param, projeção pública e **as duas
   telas** (aparência e pré-chat), com preview honesto, medidor de contraste que bate com o servidor
   e snippet que o tradutor não quebra mais.

---

## 5. Cinco achados de método que mudariam vereditos se ninguém olhasse

### 5.1 O merge da v4.16.2 não está no grafo, e a instância se anuncia como 4.12.1

Três medições independentes dizem a mesma coisa:

| Medição | Resultado |
|---|---|
| `git merge-base --is-ancestor v4.16.2 HEAD` | **falso** — a tag não é ancestral |
| `package.json` × `config/app.yml` | **4.16.2** × **4.12.1** |
| Hash de blob dos 82 arquivos que o upstream tocou em `app/javascript/widget/` | **0** iguais a v4.16.2 · **59** ainda em v4.12.1 · **20** híbridos · **3** ausentes |

A explicação está no próprio log: `47c30dd41a` — *"commit de MERGE nao e trabalho nosso — recorte
cai de 1.643 para 1.004"*. O recorte **reescreveu a história** e o upstream entrou como conjunto
escolhido de mudanças, não como merge. Isso foi deliberado e tem mérito (o recorte é o que torna a
árvore auditável). **As três consequências não foram deliberadas:**

1. **A versão que a instância anuncia é a velha.** `Chatwoot.config[:version]` alimenta
   `api_controller.rb:5`, `dashboard_controller.rb:71` (`APP_VERSION`), a barra do super_admin e o
   `ChatwootHub`. O snapshot do merge trazia `4.16.2` no `app.yml`; a resolução manteve o nosso lado.
   **É uma linha de YAML** e nenhum aceite a cobre.
2. **Um `git merge upstream/v4.x` futuro vai reapresentar conflito** no que já foi decidido, porque
   o grafo não registra que a v4.16.2 passou por aqui.
3. **Sete arquivos de código do widget nunca receberam o delta do upstream** — e um deles reprova o
   3.17 hoje:

   | Arquivo | O que o upstream mudou e não entrou |
   |---|---|
   | `widget/views/ArticleViewer.vue` | 1 linha — **é o `bg-white` sem `dark:` do aceite do 3.17** |
   | `widget/views/PreChatForm.vue` | 13 linhas |
   | `widget/store/modules/conversation/getters.js` | `getPendingCustomAttributes`, `getPendingLabels` |
   | `widget/api/specs/endPoints.spec.js` | +88 linhas de teste |
   | `Home/Article/ArticleBlock.vue` · `ArticleListItem.vue` | 3 linhas |
   | `store/modules/specs/conversation/mutations.spec.js` | teste |

   **Conferi o único que poderia ser caminho morto** e não é: o estado `pendingCustomAttributes` /
   `pendingLabels` **existe** em `mutations.js:118-131`, e `actions.js:96` o lê **direto do state**,
   sem getter. Os getters ausentes são cosméticos. Os outros 55 arquivos em v4.12.1 são traduções.

*Nada disto foi corrigido — esta auditoria é somente leitura.*

### 5.2 O 5.07 foi declarado ausente por um relatório que olhou o arquivo que o plano nomeia

`o4-tracking-client.md:13` diz, sobre o 5.08:

> **BLOQUEADO** — depende de **5.07** (verificado NÃO feito: `config/environments/production.rb:24-26`
> segue com `max-age=1.year` e sem `ETag`)

**A observação está certa e a conclusão está errada.** O `production.rb:24-26` de fato segue com
`public, max-age=31556952` — e continua assim de propósito, porque essa regra vale para **todo**
`public/`. O bloco 5.07 foi feito **noutro lugar**: um middleware inserido antes de tudo
(`insert_before 0`) que trata **só os dois caminhos do SDK**.

| Fonte | Diz |
|---|---|
| `lib/sdk_cache_policy.rb:36,42,47` | `SDK_PATHS = ['/packs/js/sdk.js','/packs/js/tracking.js']` · `MAX_AGE = 300` · `must-revalidate` |
| `spec/lib/middleware/sdk_cache_policy_spec.rb` | **10 exemplos, 0 falhas** |
| `curl -skI` no nginx desta VM | `cache-control: public, max-age=300, must-revalidate` + `last-modified` |

O erro é o mesmo que o briefing desta auditoria manda evitar — **ler o caminho em vez do conteúdo** —
e ele custou caro, porque marcou como bloqueado um bloco (5.08) cujo bloqueio não existia. Note que a
divergência aqui é **oposta** à do 5.23 de 24/08: lá o relatório dizia *feito* e a árvore não tinha;
aqui o relatório diz *não feito* e a árvore tem. **As duas direções acontecem, e só a árvore decide.**

### 5.3 Dois verificadores estão vermelhos e nenhum dos dois é aceite reprovado

| Verificador | Bloco | Estado | Por quê |
|---|---|---|---|
| `launcher-hover.check.mjs` | **1.05** | **4/7** | 1 das 3 falhas é o verificador: ele procura `setAttributeNS(null, 'fill', 'currentColor')` **literal**, e o 3.19 refatorou `bubbleHelpers.js` para passar a cor por parâmetro — `iconFill = 'currentColor'` como default (`:208`), aplicado em `:133,218,222`. **O comportamento está certo e o regex não alcança mais.** As outras 2 falhas são reais: `#2dc46f` em `sdk.js:414` e `#1f2d3d/#37546d/#6e6f73` em `:351,396,406` |
| `focus-ring.check.mjs` | **1.06** | **falha na largada** | *"não localizei as classes do composer em `ChatInputWrap.vue`"*. O bloco **2.05 fez o que devia**: `ChatInputWrap.vue` virou casca de **36 linhas** e as classes foram para `WComposer.vue`. Já registrado na §5.2 do `ESTADO-BLOCOS-24ago.md`; **três dias depois continua vermelho** |

O anel de foco **existe e é real** — `WComposer.vue:98-100` traz `outline: var(--w-focus-ring-width)
solid var(--w-focus-ring-color)`, que satisfaz *"`outline-color` não transparente"* por token.

Vermelho permanente treina gente a ignorar vermelho, que é o risco **R17** do próprio plano. **São
dois arquivos e três regex.**

### 5.4 O gate de peso mudou de veredito desde 24/08 — para melhor num eixo, pior no outro

O `ESTADO-BLOCOS-24ago.md` §5.3 media o gate contra o build de 21/08. Rodei contra o build de 27/08
(mesmo HEAD, nenhuma fonte mais nova — verificado por `find -newer`):

| Medida | 24/08 | **27/08** | Teto | Situação |
|---|---:|---:|---:|---|
| grafo do widget (JS eager, gzip) | 392.416 B | **289.488 B** | 300.000 B | **passou a caber** — folga de 10.512 B. É o bloco **2.18**, que entrou depois |
| `sdk.js` **cru** | 45.229 B | **42.969 B** | 40.000 B | **FALHA (+2.969 B)** — melhorou 2.260 B e continua estourado |
| `sdk.js` **gzip** | 14.994 B | **14.339 B** | 15.000 B | OK — a folga subiu de **6 B** para **661 B** |
| linha de base §12 | — | 29.014 B / 9.595 B | — | delta: **+48,10% cru / +49,44% gzip** |
| CSS do widget (cru) | — | **94.395 B** | **80.000 B** (aceite do 1.08) | **FALHA (+14.395 B)** |

Duas leituras práticas, e a segunda é a que ninguém tinha:

- **O grafo entrou no teto.** O item 9 da "ordem de ataque" de 24/08 (bloco 2.18, 8 pontos) **está
  feito**, e com ele o item 10 (6.04) perdeu metade do bloqueio: sobra o 1.08.
- **O teto do CSS do 1.08 não é cobrado por gate nenhum.** O gate do 0.5 mede o CSS *dentro do
  grafo* contra o teto de 300 kB (que passa), não contra os 80 kB do 1.08. Por isso os 18.895 B
  entraram desde que o bloco fechou em 75.500 B sem nenhum vermelho acender.


### 5.5 A suíte do widget está vermelha em 6 de 68 — e **nenhum dos 6 é defeito de produto**

Rodei a suíte inteira do bloco 0.1 (`npx playwright test --project=widget`, portas 8899/3999/3038
conferidas livres antes de começar). **62 passaram, 6 falharam, em 5,6 min.** Periciei as seis, e
elas se dividem em três causas — nenhuma delas é o produto:

**(a) Quatro snapshots do pré-chat: o baseline congelou o defeito de contraste que o 1.02 consertou.**

`prechat-form-{light,dark}-{desktop,mobile}` falham com **17.175 px (8%)** no desktop e **28.470 px
(9%)** no mobile — muito acima do `maxDiffPixelRatio: 0.01`, e espalhados por toda a largura
(`x[0..399]`, `y[15..460]`), o que já descarta antialiasing. Abri as imagens e medi as cores:

| | fundo do cabeçalho | texto e ícones do cabeçalho | rótulo do botão | contraste |
|---|---|---|---|---|
| **baseline** (PNG commitado) | `rgb(45,196,111)` = `#2dc46f` | **branco** `(255,255,255)` | **branco** | **2,2734:1** — reprova AA |
| **árvore de hoje** | `rgb(45,196,111)` = `#2dc46f` | **preto** `(0,0,0)` | **preto** | **9,2371:1** — passa |

**A árvore está certa e o baseline está errado.** Preto sobre `#2dc46f` é exatamente o que o bloco
**1.02** decide (`L(#2dc46f) = 0,411854 > 0,17913 → --w-on-brand: #000000`), e os dois números —
2,2734 e 9,2371 — são os que o `_tokens.scss` e o aceite do 3.08 já traziam escritos. Os 4 PNG do
pré-chat foram capturados **antes** de o token alcançar essa superfície e nunca foram revistos; os
outros 16 cenários passam porque já foram.

**É a armadilha que o próprio plano nomeia**, na nota de rodapé do 0.11: *"um baseline de snapshots
capturado por um harness que engole erro é um baseline que fotografa o defeito e o aprova"*. Aqui é
a versão espelhada e mais sorrateira: **o baseline fotografou o defeito, e agora reprova o conserto.**

**NÃO regravei os snapshots** — auditoria é somente leitura, e `--update-snapshots` regrava *tudo*
que a corrida tocou, não só o que se pretendia. A correção é revisar os 4 PNG **um a um**, olhando
cada um, que é o que o aceite do 0.1 sempre pediu.

**(b) `sdkEvents.spec.js:318` — seletor órfão, terceiro caso do mesmo tipo da §5.3.**

Falha com `TimeoutError: locator.fill` esperando por **`#chat-input`** (`:329`). **Esse id não existe
em lugar nenhum de `app/javascript/`**: o bloco **2.05** virou o `ChatInputWrap.vue` numa casca de 36
linhas e o campo foi para o primitivo `WComposer.vue`, cujo `<textarea>` tem
**`id="w-composer-campo"`** (`:69-70`). É uma linha de spec, e ela vale: este arquivo é *o* mecanismo
do aceite do **5.04** (*"a ordem é observável por `addEventListener` em navegador real"*), que o
`ESTADO-BLOCOS-24ago.md` marcou FEITO registrando que a suíte **não fora rodada**. Rodou agora: os
outros três eventos do contrato (`csat-submitted`, `campaign-shown`, `conversation-started`) passam;
só `message-sent` cai, e cai no seletor, não no contrato.

**(c) `citacao.spec.js:95` (tema claro) — o fixture do 0.11 pegou o WebSocket do Vite.**

O erro é literal: `WebSocket connection to 'ws://127.0.0.1:24678/' failed` mais dois `console` do
`@vite/client`. **É ambiente, não produto** — e o mesmo teste **passa no tema escuro**, que é a
assinatura de flaky de infraestrutura. O fixture está funcionando exatamente como projetado; o que
falta é que `IGNORAR` está **vazio** (`fixtures.js:70`), e o HMR do harness é justamente o caso de
AMBIENTE para o qual essa lista existe. **Uma entrada com comentário** fecha, e a regra MUST NOT do
§10.3 (toda entrada com a razão escrita) continua honrada.

**E um ganho que ninguém tinha visto: a a11y do widget melhorou em TODOS os 16 cenários medidos.**

O teste imprime `[axe] <cenário> MELHOROU` quando fica abaixo do teto, e imprimiu **16 vezes — em
todos os cenários que chegaram a rodar o axe**:

| | teto no `baseline.json` | **medido hoje** | queda |
|---|---:|---:|---:|
| `critical` (16 cenários) | 12 | **8** | −33% |
| `serious` (16 cenários) | 28 | **6** | **−79%** |

`messages-*` e `home-*-dark` foram a **zero** `serious`. O teto não desce sozinho — por decisão
deliberada do próprio teste (`widget.spec.js:352-362`: *"o número só desce por ATO DELIBERADO"*) —
então **hoje a régua de a11y do widget está frouxa em 22 violações `serious`**. Baixar as 16 linhas
do `baseline.json` é o que trava o ganho; enquanto não baixar, uma regressão de até 22 `serious`
passa verde.

---

## 6. Resumo

### 6.1 Por onda, em blocos e em pontos de esforço

Escala do plano §0.5: **P = 1 · M = 3 · G = 8 · P/M = 2**. As três somas batem com o total declarado
no cabeçalho de cada onda (24, 50, 56), o que é a conferência de que nenhuma linha foi perdida nem
contada duas vezes.

| Onda | Blocos | FEITO | PARCIAL | AUSENTE | Pontos | FEITO (pts) | PARCIAL (pts) | AUSENTE (pts) | **% FEITO por esforço** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **0** — Terreno | 11 | **8** | 3 | 0 | 24 | 14 | 10 | 0 | **58,3%** |
| **1** — Nada mentindo | 23 | **22** | 1 | 0 | 50 | 47 | 3 | 0 | **94,0%** |
| **2** — Configuração (`3.xx`) | 19 | **17** | 2 | 0 | 56 | 50 | 6 | 0 | **89,3%** |
| **Total das 3 ondas** | **53** | **47** | **6** | **0** | **130** | **111** | **19** | **0** | **85,4%** |

**Nenhum bloco AUSENTE nas três ondas.** Os 19 pontos parciais estão em 6 blocos, e **10 desses 19
pontos são um só: o 0.2**, cujo "parcial" é de forma (grafo, versão, 7 arquivos), não de função.

### 6.2 O plano inteiro, pela primeira vez

Somando com o `ESTADO-BLOCOS-24ago.md` (Ondas 3–6):

| Recorte | Blocos | FEITO | PARCIAL | AUSENTE | Pontos | FEITO (pts) | **% por esforço** |
|---|---:|---:|---:|---:|---:|---:|---:|
| Ondas 0, 1, 2 *(este documento)* | 53 | 47 | 6 | 0 | 130 | 111 | 85,4% |
| Ondas 3, 4, 5, 6 *(24/08)* | 68 | 51 | 10 | 7 | 245 | 163 | 66,5% |
| **O PLANO INTEIRO** | **121** | **98** | **16** | **7** | **375** | **274** | **73,1%** |

**274 dos 375 pontos do plano estão FEITOS (73,1%).** Dos 101 pontos restantes, **19 estão nestas
três ondas** e 82 nas quatro seguintes. E o número que mais muda a leitura: **as Ondas 0–2 sozinhas
valem 130 pontos e estão 85,4% fechadas** — o terreno e a configuração, que sustentam todo o resto,
não são o gargalo.

*Duas ressalvas de honestidade sobre esta soma.* (a) As linhas das Ondas 3–6 são de **24/08** e a
árvore andou 35 commits — a §5.4 já mostra dois vereditos que mudaram (2.18 fechou, 5.23 foi
integrado no commit `24f54ab552`), então o número real das Ondas 3–6 é **melhor** que 66,5%; não o
recalculei porque está fora do recorte desta task. (b) "% por esforço" é % de *pontos de plano*, não
de valor entregue ao cliente.

### 6.3 O que mudou de veredito em relação ao `ESTADO-18ago.md`

| Onda | `ESTADO-18ago.md` diz | Esta auditoria mede | Delta |
|---|---|---|---|
| **0** | "todos"; **0.4 e 0.10 pendentes** — "exigem sudo, não pedidos" | **8 FEITO + 3 PARCIAL** de 11 | **0.4 e 0.10 saíram do pendente**: o sudo foi concedido em 24/08 e os dois foram executados **nesta VM** (medi o brotli por `curl`, as chaves no `.env`). Continuam parciais **por frota**, não por sudo. E aparece um parcial que aquele documento não via: o **0.2** |
| **1** | "**22** de 23"; falta 1.21 | **22 FEITO + 1 PARCIAL** de 23 | **Mesmo número, contas diferentes.** 1.21 está **cortado** (D6) e não conta, então o denominador é 23, não 24. O parcial é o **1.08**, que aquele documento dava por fechado — e estava certo na data: o CSS **regrediu depois**, de 75.500 B para 94.395 B |
| **2** | "**19**"; falta 3.15 (em curso); **3.19 PARCIAL** | **17 FEITO + 2 PARCIAL** de 19 | **3.15 não pertence a esta onda** — o plano o executa na Onda 5, e ele foi auditado em 24/08. **3.19 continua PARCIAL e pelo mesmo motivo** (a metade de tela), mas com uma diferença que muda a prioridade: **as dependências que o bloqueavam — 3.18 e 3.09 — fecharam**. E entra um parcial novo: o **3.17**, cuja metade menor o próprio `onda-2-resto.md` roteou ao coordenador e ninguém pegou |

**A razão da divergência não é que alguém errou.** O `ESTADO-18ago.md` conta bloco **com commit**;
esta auditoria conta bloco **com aceite satisfeito**. Para as Ondas 0–2 os dois números quase batem
(52 × 47), o que é o oposto do que aconteceu nas Ondas 3–6, onde aquele documento **subestimava em
40 blocos**. **A lição não é "o 18ago é ruim": é que ele descreve a branch `redesenho-integra` em
18/08, e usá-lo como rastreio de hoje erra nas duas direções.**

---

## 7. Ordem sugerida de ataque

**Como esta ordem foi montada.** A coluna *Depende* da tabela mestra §2.2 de cada bloco, cruzada com
o veredito de quem ele depende. A coluna **Externo** separa o que **não se resolve com código**.

### Grupo A — só código, sem nenhuma porta externa, e todos podem começar hoje *(9 pontos)*

| # | Bloco | Esf. | Depende (estado) | O que exatamente falta | Externo? |
|---:|---|:---:|---|---|:---:|
| 1 | **3.17** `ArticleViewer` | — *(fração de M)* | 3.05 ✅ | **Uma classe.** `app/javascript/widget/views/ArticleViewer.vue:13` → acrescentar o par `dark:` ao `bg-white`. O arquivo está byte-a-byte em `v4.12.1` e o `onda-2-resto.md` já o roteou ao coordenador. **É o item mais barato do plano inteiro** | não |
| 2 | **0.2** versão e grafo | — *(fração de G)* | — | Duas linhas e uma decisão. (a) `config/app.yml` → `4.16.2`, senão a instância continua se anunciando como 4.12.1 em 5 lugares; (b) decidir e **escrever** como o próximo merge de upstream vai saber que a v4.16.2 passou (tag local, nota em `git notes`, ou linha no plano) — hoje o grafo não sabe. Os 7 arquivos de delta perdido: triar um a um, **`ArticleViewer` é o #1 acima** | não |
| 3 | **§5.3 + §5.5** pôr a régua no verde | — | — | **Quatro seletores e uma linha de lista.** (a) `launcher-hover.check.mjs:117` — aceitar o `fill` por parâmetro do 3.19; (b) `focus-ring.check.mjs` — apontar para `WComposer.vue`, não `ChatInputWrap.vue`; (c) `sdkEvents.spec.js:329` — `#chat-input` **não existe**, é `#w-composer-campo`; (d) uma entrada em `IGNORAR` (`fixtures.js:70`), **com o comentário da razão**, para o WebSocket do HMR do Vite. Não é bloco do plano; é a manutenção que impede o **R17** de virar realidade — e sem ela o vermelho de qualquer item abaixo se perde no meio dos vermelhos velhos | não |
| 3b | **§5.5** os 4 PNG do pré-chat | — | 1.02 ✅ | **Revisar um a um**, que é o que o aceite do 0.1 pede — nunca `--update-snapshots`, que regrava tudo que a corrida tocou. O baseline tem **branco sobre `#2dc46f` (2,27:1)** e a árvore tem **preto (9,24:1)**: quem está certo é a árvore | não |
| 3c | **§5.5** travar o ganho de a11y | — | — | **16 linhas do `baseline.json`.** Os tetos de `serious` estão frouxos em **22 violações** (28 → 6 medidas). Enquanto não descerem, uma regressão de a11y de até 22 `serious` passa verde. O próprio teste imprime o número e manda baixar | não |
| 4 | **1.05** os 2 literais reais | — *(fração de P)* | — | Depois do #3, o `launcher-hover` passa de 4/7 para 6/7 sozinho. Sobram `sdk.js:414` (`#2dc46f` no fallback do `var()`) e `:351,396,406` (`color:` cravado) — **e cada byte que sai daqui é byte no `sdk.js`, que está 2.969 B acima do teto cru** | não |
| 5 | **3.19** a metade de tela | **M (3)** | 3.18 ✅, 3.09 ✅, 1.05 ✅, 3.10 ✅ | **Nada mais o bloqueia** — as 4 asserções que o próprio bloco declarou bloqueadas em `bubbleHelpers.spec.js:11-14` esperavam 3.18 e 3.09, que fecharam. Falta: o seletor de `launcher_icon` em `LauncherField.vue` (o *contract* já o conhece), o upload com **teto de 20 KB**, o byte servido do nosso domínio, e o **aviso "rosto converte mais"** da D5. A metade SDK já está 13/13 em Chromium | não |
| 6 | **1.08** o CSS de volta ao teto | **M (3)** | 0.5 ✅ | **94.395 B contra teto de 80.000 B** (+18%). O bloco fechou em 75.500 B; quem engordou foram as Ondas 2 e 5. **Faça junto a trava**: acrescentar o teto do CSS ao `widget-size.mjs`, senão ele regride de novo sem vermelho — foi exatamente o que aconteceu | não |
| 7 | **0.4 / 0.10** a frota | **P (1) + P (1)** | — | **Código: zero.** É operação: reiniciar as 5 VMs provisionadas (as chaves estão inertes até lá), aplicar brotli+`gzip_vary` nas outras 3 VMs, e **abrir rota para ALTERNATIVO `.169` e PAULAO `.100`**, que ficaram sem SSH. **Enquanto 0.10 não fecha na frota, o 5.02 não fecha** — e ele é o topo da cadeia de 28 pontos da Onda 4 | **operação, não engenharia** |

### O que isso quer dizer em uma frase

**Dos 19 pontos ainda abertos nestas três ondas, 17 são só código e nenhum depende de porta
externa** — não há DPA, não há cadastro de app, não há acesso de produção nesta lista. Os outros 2
(0.4/0.10) são **operação de frota**, e são os que destravam os 28 pontos da Onda 4 que o documento
de 24/08 aponta como o maior buraco do plano. **E os seis primeiros itens da lista são de manutenção, não de
construção**: uma classe CSS, uma string de versão, quatro seletores, uma entrada de `IGNORAR`, 4 PNG
para olhar e 16 linhas de JSON para baixar. Nenhum deles escreve funcionalidade nova, e os três do
item 3 são o que separa uma régua confiável de uma régua que o time aprende a ignorar.

---

## 8. Anexo — o que rodou nesta auditoria

| Ferramenta | Escopo | Resultado |
|---|---|---|
| **rspec** (`POSTGRES_DATABASE=chatwoot_test_aud012`, banco criado por `db:schema:load`) | 5 lotes, 30 arquivos de spec dos blocos das Ondas 0, 1 e 2 | **341 exemplos, 0 falhas** (15 + 126 + 138 + 51 + 11) |
| **vitest** | 2 corridas: (a) `widget/{bridge,message-types,ui}` + `sdk/specs` + a11y/typingDots + relatório de origem → **36 arquivos / 464 testes**; (b) `settings/inbox/widget` + `settings/inbox/specs` + `widget-preview` + `widget/{views,mixins,specs,helpers}/specs` + `brMasks` → **57 arquivos / 954 testes** | **93 arquivos / 1.418 testes, 0 falhas** |
| **`*.check.mjs`** (Chromium real) | 3 verificadores rodados | `launcher-icon` **13/13** (bloco 3.19) · `launcher-hover` **4/7** (bloco 1.05 — §5.3) · `focus-ring` **falha na largada** (bloco 1.06 — §5.3) |
| **verificador por sabotagem** | `fixture-antierro.check.mjs` (bloco 0.11) | **11/11**, das quais **8 provam o vermelho injetando o defeito** |
| **Playwright — `--list`** | `--project=widget` e `--project=desktop-chromium` | **68 testes / 8 arquivos** e **108 testes / 23 arquivos** (30 de `copilot` + `resolve-gate`) — a primeira metade do aceite do 0.1 |
| **Playwright — suíte EXECUTADA** | `--project=widget` inteiro (portas 8899/3999/3038 conferidas livres antes) | **62 passaram, 6 falharam, 5,6 min.** Os 6 periciados na §5.5: 4 são PNG de baseline envelhecido (medi as cores: branco 2,27:1 no baseline × preto 9,24:1 na árvore), 1 é seletor órfão (`#chat-input` → `#w-composer-campo`), 1 é o WebSocket do HMR do Vite. **Nenhum é defeito de produto.** De quebra: **`[axe] MELHOROU` em 16 de 16 cenários** |
| **Pillow** (perícia de imagem) | os 4 diffs de snapshot | bbox, contagem de pixels por faixa e amostragem de cor — para separar antialiasing (que não era) de mudança de cor (que era) |
| **`scripts/widget-size.mjs`** | gate de peso do bloco 0.5, contra o build de 27/08 do checkout principal | **VERMELHO**, 1 regressão nova (`sdk.js` cru, +2.969 B). Grafo **dentro** do teto pela primeira vez — §5.4 |
| **`curl -skI`** (nginx local, `Host:` forçado) | blocos 0.4 e 5.07 | brotli + `Vary` em `text/css` **e** `text/javascript`; `sdk.js` com `max-age=300, must-revalidate` + `last-modified` |
| **`git hash-object` × `git rev-parse <tag>:<path>`** | bloco 0.2 — 82 arquivos do widget e 927 do repo | Auditoria de escopo por hash de blob — §5.1 |

**Nada foi alterado fora deste arquivo.** Nenhuma migration rodou, nenhum banco de produção foi
tocado, nenhuma VM remota foi acessada, nenhum build foi disparado, **nenhum snapshot foi regravado**
(`--update-snapshots` nunca foi usado, e a matriz continua com os 20 PNG), nada foi pushado. Os arquivos
auxiliares da varredura de blob vivem no diretório temporário da sessão, fora do repositório.
