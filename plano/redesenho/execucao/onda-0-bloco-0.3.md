# Onda 0 · Bloco 0.3 — Reconciliação do build do Vite

**Worktree:** `/home/chatwoot/chatwoot-redesenho-build` · **Branch:** `redesenho-build`
**Base:** `6ad7a9ec6e` (merge v4.16.2 + conserto do harness do 0.1) · **Pré-merge de referência:** `f26db6ee81`
**Executor:** W0.3 (redespacho) · **Data:** 2026-08-17

> Este relatório é escrito **conforme avança**. Cada seção só é marcada como fechada depois que o
> mecanismo de aceite dela foi executado e a saída real colada aqui.

> **Histórico:** o primeiro dispatch deste bloco foi cancelado pelo coordenador antes de qualquer
> edição, porque apontava para `chatwoot-redesenho-merge` — worktree onde a v4.16.2 existe isolada e
> onde os 16 snapshots do widget estão sendo medidos. O levantamento feito lá (causa raiz do 404,
> localização dos patches) está preservado na seção 6 e foi o ponto de partida. **A edição aconteceu
> aqui, em `chatwoot-redesenho-build`.** Nenhum arquivo de outro worktree foi tocado.

---

## Resumo do aceite

| # | aceite | resultado | seção |
|---|---|---|---|
| a | `bin/vite build` gera o MESMO conjunto de 8 entradas | ✅ 8/8, conjunto idêntico (2 hashes mudaram, causa rastreada em §8) | §3 |
| b | `public/packs/js/sdk.js` sai IIFE | ✅ IIFE, 29.014 B / 9.595 B gzip (= baseline) | §4 |
| c | `TEST=true` serve o SDK com 200 | ✅ 200 em `widget.js`, `sdk.js`, `/widget`, `/__ready` | §2 |
| d | `grep -rn "leaflet" vite*.ts` sem `manualChunks` | ✅ grep vazio (exit 1) | §5 |
| e | eslint e vitest não pioram | ✅ eslint 786 (103 err) → 786 (103 err); vitest 4586 passed → 4586 passed | §9 |

Itens 2 (§C1/§C2/§C3) em §7 · commit `301bbdfdf9` em §11 · débitos honestos em §12 (o item 5 é o mais
importante: nada impede o próximo merge do upstream de apagar o `isTestMode` outra vez).
**Arquivos alterados: 2** — `vite.config.ts`, `vite.shared.ts`. Os outros dois do escopo
(`vite.lib.config.ts`, `vitest.config.ts`) foram conferidos e não precisavam de mudança (§7, final).

---

## 0. Estado de partida (medido, não presumido)

Os quatro arquivos do upstream, como chegaram do merge:

| arquivo | linhas | o que tem |
|---|---|---|
| `vite.config.ts` | 17 | `plugins: [ruby(), vue(vueOptions), yaml()]`, `css.preprocessorOptions.scss`, `resolve: { alias }` |
| `vite.shared.ts` | 22 | `aliases` + `vueOptions` (só `['ninja-keys']`) |
| `vite.lib.config.ts` | 33 | build de biblioteca do SDK, `formats: ['iife']` |
| `vitest.config.ts` | 39 | vitest, importa `vueOptions` de `vite.shared` |

O nosso `vite.config.ts` pré-merge tinha **145 linhas** e concentrava tudo (`isLibraryMode`,
`isTestMode`, `optimizeDeps`, `manualChunks`, `dedupe`, bloco `test:` do vitest). O upstream quebrou
isso em 4 arquivos — **a refatoração é legítima e o bloco 0.3 a aceita**. O que se perdeu foram as
customizações SPX que moravam dentro do arquivo antigo.

Correspondência entre o modelo antigo e o novo, para o registro:

| nosso pré-merge | equivalente no upstream | veredito |
|---|---|---|
| `isLibraryMode` → `plugins = []` + `build.lib` + `dir: public/packs` | `vite.lib.config.ts` inteiro (sem plugin nenhum) | **coberto**, nada a fazer |
| bloco `test: { … }` dentro do `vite.config.ts` | `vitest.config.ts` | **coberto**, nada a fazer |
| `isTestMode` → `plugins = [vue(vueOptions)]` | **não existe em nenhum dos 4** | **devolvido** (§1) |
| `vueOptions` com `lord-icon` | `vite.shared.ts:19`, só `['ninja-keys']` | **devolvido** (§C1) |
| `optimizeDeps` do canvas | não existe | **devolvido** (§C2) |
| `resolve.dedupe` | não existe | **devolvido** (§C3) |
| `manualChunks: { leaflet }` | não existe | **fica morto** de propósito (§5) |

---

## 1. Baseline deste worktree (antes das minhas mudanças) — MEDIDO

Armadilha para quem quiser reproduzir: `bin/vite build` **sem** `--force` não rebuilda, responde
`Skipping vite build. Watched files have not changed since the last build`.

```
$ NODE_OPTIONS=--max-old-space-size=8192 bin/vite build --force     → BUILD_EXIT=0
$ pnpm run build:sdk                                               → SDK_EXIT=0
```

**8 entradas** em `public/vite/.vite/manifest.json` (`isEntry: true`) — conjunto idêntico ao que a
DoD do 0.2 mediu antes de mim, e os mesmos hashes que o levantamento no worktree de merge registrou:

```
entrypoints/dashboard.js        -> assets/dashboard-DyLvZxS2.js
entrypoints/portal.js           -> assets/portal-CrOnmi5l.js
entrypoints/sdk.js              -> assets/sdk-Dc_7YRjf.js
entrypoints/superadmin.js       -> assets/superadmin-viAhw5LG.js
entrypoints/superadmin_pages.js -> assets/superadmin_pages-Bhf_MI3d.js
entrypoints/survey.js           -> assets/survey-MHQ8svyg.js
entrypoints/v3app.js            -> assets/v3app-CupYlVPa.js
entrypoints/widget.js           -> assets/widget-B4nz3W4i.js
```

SDK baseline: **29.014 B crus / 9.595 B gzip**, IIFE — bate exatamente com o número que o
coordenador passou na task.

```
$ head -c 200 public/packs/js/sdk.js
(function(){"use strict";/*! js-cookie v3.0.5 | MIT */function B(e){…
```

eslint baseline: `✖ 786 problems (103 errors, 683 warnings)` — também bate com a task.

Avisos herdados do merge, registrados para não serem confundidos com regressão do 0.3:
`[css-syntax-error] Unexpected "button"` em `.conversations-list [role=button]button` (seletor
inválido, vem do CSS mergeado) e `AudioRecorder.vue` importado dinâmica **e** estaticamente.

---

## 2. Item 1 — o caminho de teste devolvido ✅ FECHADO

### A causa raiz do 404

- `widget-server.mjs:199-208` cria o servidor com `root: repositoryRoot` **e**
  `configFile: vite.config.ts`.
- Mas o `config()` do `vite-plugin-ruby` é mesclado **por cima** do config do usuário e reescreve
  `root` para o `sourceCodeDir` = `app/javascript` (`config/vite.json`). Com isso o pedido de
  `/app/javascript/entrypoints/widget.js` (`widget-server.mjs:137`) cai fora da raiz → **404**.
- No pré-merge (`f26db6ee81:vite.config.ts:27,41`) existia
  `const isTestMode = process.env.TEST === 'true'` → `plugins = [vue(vueOptions)]`, isto é **sem
  `ruby()`**. Sem `ruby()`, `root` fica o que o harness pediu e o entrypoint resolve.
- O harness já força `process.env.TEST = 'true'` na linha 6, antes do `import('vite')` — a ordem
  importa e está correta.

### A correção, dentro da estrutura nova (a refatoração do upstream NÃO foi desfeita)

`vite.config.ts` — o branch voltou como ternário no `plugins`, sem reintroduzir a variável `plugins`
mutável do arquivo antigo:

```ts
const isTestMode = process.env.TEST === 'true';

export default defineConfig({
  plugins: isTestMode
    ? [vue(vueOptions), yaml()]
    : [ruby(), vue(vueOptions), yaml()],
```

Diferença deliberada em relação ao pré-merge: o `yaml()` **fica** no caminho de teste. Ele não
existia no nosso arquivo antigo (o upstream o adicionou), não toca em `root` e é o que o
`vitest.config.ts` já faz — mantê-lo evita que um `import` de `.yml` no grafo do widget quebre o
harness no futuro. É estritamente aditivo.

### PROVA — servidor + curl, medido agora (sem playwright)

Portas conferidas livres antes de subir (`ss -ltnp | grep -E ':3999|:4001'` → vazio), para não
atropelar o executor que mede os 16 snapshots no outro worktree.

```
$ TEST=true node spec/e2e/widget/harness/widget-server.mjs &
READY apos 58s        (/__ready passou de 503 para 200 quando o aquecimento do grafo terminou)

=== CODIGOS HTTP ===
/app/javascript/entrypoints/widget.js         200
/app/javascript/entrypoints/sdk.js            200
/widget                                       200
/__ready                                      200
```

Os 200 não são página de erro — o conteúdo servido é ESM **transformado de verdade**, com as deps já
reescritas para o pré-bundle:

```
$ curl -s http://127.0.0.1:3999/app/javascript/entrypoints/widget.js | head -6
import { createApp } from "/node_modules/.vite/deps/vue_dist_vue__esm-bundler__js.js?v=cf031dc0";
import { createI18n } from "/node_modules/.vite/deps/vue-i18n.js?v=ccd69030";

import VueDOMPurifyHTML from "/node_modules/.vite/deps/vue-dompurify-html.js?v=14abd0d6";
import store from "/app/javascript/widget/store/index.js";
import App from "/app/javascript/widget/App.vue";
```

```
$ curl -s http://127.0.0.1:3999/app/javascript/entrypoints/sdk.js | head -4
import Cookies from "/node_modules/.vite/deps/js-cookie.js?v=78a00464";
import { IFrameHelper } from "/app/javascript/sdk/IFrameHelper.js";
```

Encerramento (o conserto do 0.1 funciona — não sobra processo nem porta presa):

```
$ kill -TERM <pid>
$ ss -ltnp | grep -E ':3999|:4001'   → PORTAS 3999/4001 LIVRES
```

**`pnpm exec playwright test` NÃO foi executado**, por instrução: a medição dos 16 snapshots é do
executor da DoD, no worktree dele, e o harness tem porta fixa.

> Nota sobre o enunciado do aceite (c): a task pede "serve o SDK com 200". O entrypoint que o harness
> de fato injeta no documento é **`widget.js`** (`widget-server.mjs:137`), não `sdk.js`. Medi **os
> dois** — ambos 200 — para que o aceite feche sem ambiguidade em nenhuma das duas leituras.

---

## 3. Aceite (a) — as 8 entradas depois da mudança ✅

```
$ NODE_OPTIONS=--max-old-space-size=8192 bin/vite build --force   → BUILD_EXIT=0
```

**8 entradas**, e o **conjunto de chaves é idêntico** ao baseline (`diff` das colunas de nome sai
vazio):

| entrada | baseline | depois do 0.3 |
|---|---|---|
| `entrypoints/dashboard.js` | `dashboard-DyLvZxS2.js` | `dashboard-DxhRaUCC.js` |
| `entrypoints/portal.js` | `portal-CrOnmi5l.js` | `portal-CrOnmi5l.js` |
| `entrypoints/sdk.js` | `sdk-Dc_7YRjf.js` | `sdk-Dc_7YRjf.js` |
| `entrypoints/superadmin.js` | `superadmin-viAhw5LG.js` | `superadmin-viAhw5LG.js` |
| `entrypoints/superadmin_pages.js` | `superadmin_pages-Bhf_MI3d.js` | `superadmin_pages-Bhf_MI3d.js` |
| `entrypoints/survey.js` | `survey-MHQ8svyg.js` | `survey-MHQ8svyg.js` |
| `entrypoints/v3app.js` | `v3app-CupYlVPa.js` | `v3app-CupYlVPa.js` |
| `entrypoints/widget.js` | `widget-B4nz3W4i.js` | `widget-DbM5h1sc.js` |

Total de assets emitidos: **739 antes, 739 depois**.

### Os dois hashes que mudaram — investigados, não presumidos

Não bastava ver "conjunto idêntico" e seguir. Diffei os dois logs de build inteiros normalizando o
hash do nome, e **um único asset mudou de tamanho**:

```
< assets/dashboard.js 6,805.88 kB
> assets/dashboard.js 6,805.87 kB
```

−10 bytes, e a causa é o §C1: com `lord-icon` declarado como custom element, o compilador Vue deixa
de emitir a resolução de componente. Provado no bundle:

```
$ grep -c 'resolveComponent("lord-icon")' public/vite/assets/dashboard-DxhRaUCC.js   → 0
$ grep -o '"lord-icon"' public/vite/assets/dashboard-DxhRaUCC.js | uniq -c           → 1 (a tag)
```

O `widget.js` mudou de hash com **tamanho, gzip e sourcemap byte-idênticos** (96,50 kB / 27,92 kB /
389,95 kB), e o bundle do widget **não contém** `lord-icon` nem `html2pdf` — logo nenhuma das minhas
três correções o alcança. Outros ~40 chunks estão na mesma situação (`EmojiPicker`, `pickerHelper`,
`Messages`, `PortalsArticles*`, `commandbar`…): hash novo, tamanho idêntico. Ver §8 para o teste de
determinismo que fecha essa questão.

---

## 4. Aceite (b) — SDK em IIFE ✅

```
$ pnpm run build:sdk                        → SDK_EXIT=0
$ stat -c '%s' public/packs/js/sdk.js       → 29014
$ gzip -c public/packs/js/sdk.js | wc -c    → 9595
```

**29.014 B crus / 9.595 B gzip — exatamente a linha de base da task, byte a byte.** Nenhuma
divergência a justificar: `vite.lib.config.ts` não foi tocado, e nenhuma das três correções entra no
grafo do SDK (o SDK não usa Vue SFC, nem `html2pdf.js`, nem Vue Flow).

IIFE confirmado pela primeira linha — o wrapper `(function(){…})()`, não `export`/`define`:

```
$ head -c 120 public/packs/js/sdk.js
(function(){"use strict";/*! js-cookie v3.0.5 | MIT */function B(e){for(var o=1;o<arguments.length;o++){var t=arguments[
```

---

## 5. Item 3 — `manualChunks` do Leaflet: DELETADO, confirmado ✅

```
$ grep -rn "leaflet" vite*.ts vitest.config.ts        → exit 1 (nenhuma linha)
$ grep -rn "manualChunks" vite*.ts vitest.config.ts   → exit 1 (nenhuma linha)
```

Morreu no merge, **não foi portado**, e não vai ser. Ao aplicar §C2 e §C3 no mesmo arquivo o risco
era restaurá-lo por engano junto — os greps acima existem exatamente para provar que isso não
aconteceu. `LocationPickerModal.vue` (único consumidor, `app/javascript/dashboard/components-next/location/`)
já importa Leaflet por `import()` dinâmico, que é a forma correta de isolar o peso.

---

## 6. Item 4 — `swagger/swagger.json`: registrado, NÃO corrigido

Fora de escopo por instrução explícita do coordenador (não é build, não tem conserto barato). O
débito é o §C4 da auditoria: 353 → 90 paths, e o pipeline que gerava os 353 (`assemble.rb` +
`specs.json`) nunca foi versionado, logo `rake swagger:build` não o reproduz.
**Nenhuma linha de `swagger/` foi tocada por este executor.**

---

## 7. Item 2 — as três customizações SPX devolvidas

### §C1 — `lord-icon` em `isCustomElement` ✅ PROVADO NO BUNDLE

Aplicado em `vite.shared.ts:16-25`. Uma edição só cobre os três consumidores (`vite.config.ts` e
`vitest.config.ts` importam `vueOptions` daqui) — é o ganho da refatoração do upstream.

Consumidor real: `LordIconIcon.vue:155` renderiza `<lord-icon …>`.

**Mecanismo executado** (asserção de valor no artefato de produção, não "não deu erro"):

```
$ grep -c 'resolveComponent("lord-icon")' public/vite/assets/dashboard-DxhRaUCC.js   → 0
$ grep -o '"lord-icon"' public/vite/assets/dashboard-DxhRaUCC.js | uniq -c           → 1
```

Zero resoluções de componente + a tag presente como string = o compilador tratou `lord-icon` como
elemento nativo. Antes da correção ele emitiria `resolveComponent("lord-icon")` e o runtime logaria
`Failed to resolve component: lord-icon`. Os −10 bytes do `dashboard.js` (§3) são exatamente esse
código que deixou de ser emitido — a mudança de tamanho é a evidência independente de que o patch
pegou.

### §C2 — `optimizeDeps` do canvas de Automações ✅ PROVADO EM DEV

Aplicado em `vite.config.ts`, dentro do `defineConfig`, com o comentário original preservado.

**Mecanismo executado:** script `prova-c2-optimizedeps.mjs` (no scratchpad) sobe o **mesmo
`vite.config.ts`** em `mode: 'development'`, em `middlewareMode` — **sem abrir porta nenhuma**, para
não competir com o Puma 3000 de homologação nem com o harness de outro executor. Saída real:

```
1) optimizeDeps.include resolvido = ["@vue-flow/core","@vue-flow/background","@vue-flow/controls","@vue-flow/minimap","vue-shepherd"]
   OK: as 5 deps do canvas estão no include
2) esbuildOptions.define["process.env.ES_BUILD"] = "false"   OK
3) pré-bundle materializado + `process.env` substituído:
   @vue-flow/core:       @vue-flow_core.js        (2650 B)  process.env.NODE_ENV cru=false  process.env.ES_BUILD cru=false  OK
   @vue-flow/background: @vue-flow_background.js  (5218 B)  process.env.NODE_ENV cru=false  process.env.ES_BUILD cru=false  OK
   @vue-flow/controls:   @vue-flow_controls.js    (8780 B)  process.env.NODE_ENV cru=false  process.env.ES_BUILD cru=false  OK
   @vue-flow/minimap:    @vue-flow_minimap.js    (99616 B)  process.env.NODE_ENV cru=false  process.env.ES_BUILD cru=false  OK
   vue-shepherd:         vue-shepherd.js         (59699 B)  process.env.NODE_ENV cru=false  process.env.ES_BUILD cru=false  OK

VEREDITO §C2: PASSOU   (exit 0)
```

As três asserções são de **valor**: a lista resolvida é comparada elemento a elemento com as 5 deps
esperadas; o `define` é comparado com a string `'false'`; e cada pré-bundle é lido do disco e
verificado por **ausência de `process.env.NODE_ENV` / `process.env.ES_BUILD` crus** — que é
literalmente o sintoma do bug (`process is not defined`).

**Por que sem o `include` isso quebrava** — esta parte está provada por leitura de código, não por
medição, e registro a diferença: `@vue-flow/*` só aparece nos componentes do canvas
(`routes/dashboard/settings/automation/canvas/{FlowCanvasView,FlowNode,FlowEdge}.vue`), alcançados
por `import()` dinâmico em `agents.routes.js:13` → `FlowTab.vue`. O scan do optimizer no boot só
segue imports estáticos a partir dos entrypoints, então essas deps ficavam fora do pré-bundle e
chegavam ao browser como ESM cru de `node_modules`, com `process.env.*` literal.

**O que este mecanismo NÃO cobre, e fica honesto:** eu não abri a tela do canvas num browser real
para ler o console. Isso exigiria Rails + login, e o Puma da porta 3000 é o ChatSPX de homologação em
uso — proibido nesta onda. O que medi é a camada exata onde o bug vivia (o pré-bundle do dev server);
a confirmação visual na tela pertence a quem tiver ambiente logado disponível.

### §C3 — `resolve.dedupe: ['html2pdf.js']` ✅ APLICADO, com ressalva declarada

Aplicado em `vite.config.ts` (`resolve: { alias: aliases, dedupe: ['html2pdf.js'] }`).
Consumidor real: `ConversationPDFExporter.js:2` (`import html2pdf from 'html2pdf.js'`, usado na
linha 1097).

**Estado medido do grafo hoje** — o store pnpm tem **uma única versão de cada** peça:

```
html2pdf.js  0.10.3      html2canvas 1.4.1      jspdf 3.0.4
```

Ou seja: **hoje não há duplicata para o `dedupe` colapsar**, e por isso ele não produz diferença
observável no bundle (nenhum asset relacionado mudou de tamanho no build). A diretiva é uma **trava
preventiva**: ela volta a valer no instante em que um transitivo puxar uma segunda cópia de
`html2pdf.js`, cenário que já produziu PDF em branco antes e motivou a linha no nosso config.
Reportando o que é: **o patch está no lugar e é correto, mas o teste de PDF ponta a ponta não foi
executado** — depende de conta logada e exportação real de conversa, fora do que esta task pode fazer
sem tocar em ambiente de homologação.

---

### Os outros dois arquivos do escopo — conferidos, nada a corrigir

A task lista 4 arquivos. Dois deles eu **não** editei, e isso é uma conclusão medida, não uma
omissão:

**`vitest.config.ts`** — o upstream levou para cá o nosso bloco `test:` inteiro. Comparei as chaves
do bloco pré-merge com as do arquivo novo:

```
$ diff <(chaves do bloco test: em f26db6ee81:vite.config.ts) <(chaves de vitest.config.ts)
IDENTICO: nenhuma chave do nosso bloco test: foi perdida
```

E os valores que importam, conferidos um a um (`pre` = ocorrências no nosso pré-merge, `pos` = no
arquivo novo):

```
'fake-indexeddb/auto'   pre=1 pos=1      tinykeys            pre=1 pos=1
vitest.setup.js         pre=1 pos=1      @material/mwc-icon  pre=1 pos=1
singleThread            pre=1 pos=1      sonar-report.xml    pre=1 pos=1
```

**`vite.lib.config.ts`** — cobre integralmente o nosso `isLibraryMode`:

```
js/sdk.js  pre=2 lib=2      'iife'  pre=1 lib=1
name:'sdk' pre=1 lib=1      entrypoints/sdk.js  pre=1 lib=1
```

Não portei §C1/§C2/§C3 para ele, e a razão é verificada, não suposta: o grafo do SDK
(`app/javascript/sdk/**` + `entrypoints/sdk.js`) **não importa nenhum `.vue`, nem `html2pdf`, nem
`vue-flow`** (grep sem resultado). `lord-icon` precisa do compilador Vue, `dedupe` precisa de
`html2pdf.js` e `optimizeDeps` só age em dev — nenhum dos três tem efeito no SDK. Foi também por isso
que o `sdk.js` saiu byte-idêntico ao baseline (§4).

---

## 8. §3 continuado — por que 31 chunks trocaram de hash sem trocar de conteúdo

Isto não era parte do aceite, mas eu não podia registrar "conjunto idêntico ✅" deixando 31 hashes
mudados sem explicação — seria exatamente o tipo de relatório otimista que a regra proíbe. A
investigação deu uma causa única e verificada.

### Passo 1 — o build é determinístico (então a mudança é minha, não do Rollup)

Rodei um **terceiro** build, idêntico ao segundo, sem alterar nada:

```
$ NODE_OPTIONS=--max-old-space-size=8192 bin/vite build --force   → BUILD_EXIT=0
$ diff <entradas do build 2> <entradas do build 3>                → vazio
$ diff <todos os 739 assets do build 2> <do build 3>              → vazio
```

Dois builds idênticos produzem os **739 assets com hashes idênticos**. Logo os 31 hashes não são
instabilidade do bundler: minha mudança os causou, e havia o que explicar.

### Passo 2 — a topologia, tirada do manifest

Comparei `base-manifest.json` com o manifest novo e, para cada chunk que mudou de hash, contei
quantas das suas dependências declaradas também mudaram:

```
26 deps mudadas | entrypoints/dashboard.js
 5 deps mudadas | entrypoints/widget.js
 2 deps mudadas | widget/views/Messages.vue   <- entrypoints/widget.js, shared/components/emoji/EmojiPicker.vue
 1 dep  mudada  | shared/components/emoji/EmojiPicker.vue          <- entrypoints/dashboard.js
 1 dep  mudada  | widget/views/{Home,Campaigns,PreChatForm,UnreadMessages}.vue  <- entrypoints/widget.js
 1 dep  mudada  | + 23 chunks lazy do dashboard (agents/tabs/*, helpcenter/pages/*, commandbar…)
                                                                    <- entrypoints/dashboard.js
```

**31 chunks no total, e nenhum deles é folha** — todos têm ao menos uma dependência que também mudou.
A raiz é uma só: `entrypoints/dashboard.js`, o único asset do build inteiro que mudou de **tamanho**
(−10 bytes, o `resolveComponent("lord-icon")` do §C1).

### Passo 3 — o mecanismo, confirmado no byte

O nome do chunk aparece **dentro** do código de quem o importa, e o hash do Vite tem **sempre 8
caracteres**:

```
$ grep -o "dashboard-[A-Za-z0-9_-]\{8\}\.js" public/vite/assets/EmojiPicker-BKQbYu4E.js
dashboard-DxhRaUCC.js

sTAEyjbD → 8 caracteres     BKQbYu4E → 8 caracteres
```

Trocar `dashboard-DyLvZxS2.js` por `dashboard-DxhRaUCC.js` dentro de um chunk muda o **conteúdo** sem
mudar **um único byte de tamanho** — e conteúdo diferente significa hash diferente. Daí a cascata.

E o caminho até o widget, que era o ponto que mais precisava de explicação (o bundle do widget não
contém `lord-icon` nem `html2pdf`): `EmojiPicker.vue` é um chunk **compartilhado** — o manifest mostra
`entrypoints/dashboard.js` entre os seus `imports` — e `widget/views/Messages.vue` importa esse mesmo
chunk. Então:

```
lord-icon (§C1) → dashboard.js encolhe 10 B → seu nome muda
                → EmojiPicker.vue (compartilhado) muda de nome
                → Messages.vue muda → widget.js muda
                → Home / Campaigns / PreChatForm / UnreadMessages mudam
```

**Conclusão:** as 8 entradas são o mesmo conjunto, os 739 assets são os mesmos assets, e as 31
mudanças de hash têm origem única, rastreada e desejada — o §C1 fazendo exatamente o que devia. O
aceite (a) pede o mesmo **conjunto**, não os mesmos hashes; hashes idênticos seriam impossíveis para
qualquer correção que altere a compilação de um template, que é justamente o que o §C1 é.

> Consequência operacional para quem deployar: `dashboard.js`, `widget.js` e mais 29 chunks trocam de
> nome, então **`assets:precompile` é obrigatório** — servir o manifest velho com os arquivos novos (ou
> o contrário) dá 404 de chunk. É o mesmo modo de falha já registrado em
> `reference_deploy_incompleto_front_desatualizado`.

---

## 9. Aceite (e) — eslint e vitest não pioraram

| gate | baseline (task e medido por mim) | depois do 0.3 | veredito |
|---|---|---|---|
| `pnpm eslint` | 786 problems (103 errors, 683 warnings) | **786 problems (103 errors, 683 warnings)** | ✅ idêntico |
| `pnpm exec vitest --no-watch` | 4586 passed, 0 failed | **4586 passed (4586), 463 arquivos, exit 0** | ✅ idêntico |

```
$ pnpm exec vitest --no-watch
 Test Files  463 passed (463)
      Tests  4586 passed (4586)
VITEST_EXIT=0
```

O eslint saiu **igual ao baseline nos três números** (786 / 103 / 683), não apenas "não pior". Isso era
esperado: as duas edições são de config, e `vite.config.ts` / `vite.shared.ts` já passavam limpos
antes. A quebra de linha que o Prettier impôs no `isCustomElement` (arrow multi-linha) está no formato
que o próprio eslint exige — nenhum problema novo, nenhum a menos.

---

## 10. O que eu NÃO toquei (verificado, não prometido)

```
$ git status --porcelain
 M vite.config.ts
 M vite.shared.ts
```

Dois arquivos, os dois meus. Nada em `app/`, `enterprise/`, `db/`, `config/`, `spec/e2e/**`,
`scripts/widget-size.mjs`, `package.json` ou `swagger/`.

Um detalhe que vale registrar porque confunde quem for reproduzir: durante os builds apareceu um
terceiro arquivo modificado, `public/version.json`. **Não é meu.**
`config/initializers/app_version.rb:5` o reescreve a cada boot do Rails (`File.write(version_file, {
version:, deployed_at: Time.now.to_i })`), e `bin/vite build` carrega o Rails. O conteúdo só passou de
`f26db6ee81` para `6ad7a9ec6e` — o HEAD deste worktree. Restaurei com `git checkout -- ` para não
sujar o commit; qualquer build futuro o reescreve de novo.

`public/vite/` e `public/packs/` foram reescritos pelos três builds, mas são gitignored
(`.gitignore:87`) e não entram no commit.

**Sobre a medição dos 16 snapshots em `chatwoot-redesenho-merge`:** não a toquei. Não editei arquivo
nenhum naquele worktree, não rodei `playwright test`, e o harness que subi aqui usou as portas 3999/4001
**depois de conferir que estavam livres** e as devolveu ao encerrar.

---

## 11. Commit

Feito **depois** de todos os números fecharem, nunca antes.

```
$ git commit -m "build(0.3): reconcilia o vite do upstream e devolve o caminho de teste"
[check_vue_template_refs] mode=staged checked=224 files problems=0
301bbdfdf9 build(0.3): reconcilia o vite do upstream e devolve o caminho de teste
 vite.config.ts | 35 +++++++++++++++++++++++++++++++++--
 vite.shared.ts |  6 +++++-
 2 files changed, 38 insertions(+), 3 deletions(-)
```

Os hooks de pre-commit rodaram normalmente (`check_vue_template_refs`: 224 arquivos, 0 problemas).
**`--no-verify` não foi usado.** Local, na branch `redesenho-build`. **Nenhum push, nenhum PR, nenhum
deploy, nenhum restart de serviço.**

O `pnpm exec prettier --check` nos dois arquivos passa (`All matched files use Prettier code style!`).

---

## 12. Débitos que este bloco deixa registrados (não são falhas do 0.3)

1. **§C4 `swagger/swagger.json`** — 353 → 90 paths. Fora de escopo por instrução; o pipeline que
   gerava os 353 (`assemble.rb` + `specs.json`) nunca foi versionado, então `rake swagger:build` não o
   reproduz. Não tocado.
2. **§C2 na tela** — o `optimizeDeps` está provado na camada onde o bug vivia (o pré-bundle do dev
   server), mas ninguém abriu o canvas de Automações num browser logado para ler o console. Exigiria
   Rails + login e o Puma da 3000 é homologação em uso.
3. **§C3 ponta a ponta** — o `dedupe` está no lugar e é correto, mas hoje o store pnpm tem uma única
   cópia de `html2pdf.js` (0.10.3), então a diretiva não tem duplicata para colapsar e não produz
   diferença observável. A exportação real de PDF de uma conversa não foi testada.
4. **Avisos herdados do merge**, que aparecem no build e **não** são regressão do 0.3:
   `[css-syntax-error] Unexpected "button"` em `.conversations-list [role=button]button`, e
   `AudioRecorder.vue` importado dinâmica e estaticamente.

### Acrescentados no fechamento (a pedido do coordenador, 2026-08-17)

5. 🔴 **Nada protege o `isTestMode` contra o próximo merge do upstream — e é o débito mais caro
   daqui.** É exatamente esta a falha que a Onda 0 acabou de pagar: o upstream refatorou
   `vite.config.ts`, o nosso branch de teste foi embora silenciosamente, e o custo só apareceu duas
   tentativas de medição depois, na forma de um 404 que travou o aceite do 0.2 inteiro. Nada mudou
   nessa exposição: se um merge futuro reescrever `vite.config.ts` de novo, o branch some outra vez, e
   de novo ninguém vai descobrir por um erro de build — o build fica **verde**, porque `ruby()` é
   correto em produção. O sintoma só aparece no harness.

   A trava é barata e não depende de subir servidor. Em `vitest`, resolver o próprio config e afirmar
   o valor:

   ```js
   // sob TEST=true, o plugin ruby NÃO pode estar na lista — senão ele reescreve `root`
   // para app/javascript e o harness do widget devolve 404.
   process.env.TEST = 'true';
   const config = await resolveConfig({ configFile: 'vite.config.ts' }, 'serve');
   expect(config.plugins.map(p => p.name)).not.toContain('vite-plugin-ruby');
   ```

   **Não implementei**, e o motivo é escopo, não esquecimento: o arquivo natural para isso é um novo
   spec, e a task 0.3 delimita os arquivos que eu podia tocar. Fica como recomendação explícita para
   quem definir a política de merge com o upstream — vale mais do que qualquer uma das três
   correções §C1/§C2/§C3, porque protege todas elas e mais o caminho de teste.

6. 🟡 **`public/version.json` é rastreado pelo git e reescrito a cada boot do Rails.** Armadilha para
   **todo** executor desta onda, não só para mim: `config/initializers/app_version.rb:5` faz
   `File.write` com `Time.now.to_i`, e qualquer comando que carregue o Rails (`bin/vite build`,
   `rails`, `rake`) deixa o arquivo modificado no working tree. Consequências práticas: um `git add -A`
   distraído o carrega para dentro de um commit de outra coisa; e um `git status` sujo pode ser lido
   como "o executor anterior deixou trabalho pendente" quando não deixou nada. Eu restaurei o meu com
   `git checkout --` (§10). O conserto de verdade seria `git rm --cached` + `.gitignore`, mas isso é
   `config/`+ raiz do repo — **fora do escopo do 0.3** e do escopo de qualquer bloco de build.

7. 🟢 **O mecanismo de aceite do §C2 foi preservado** — ele nasceu no scratchpad da sessão, que é
   efêmero, e um aceite cujo mecanismo desaparece volta a ser afirmação. Copiado para o lado deste
   relatório, junto com as duas listas de entradas que sustentam o aceite (a):

   ```
   plano/redesenho/execucao/dados/bloco-0.3-prova-c2-optimizedeps.mjs   (rodar com cwd = worktree)
   plano/redesenho/execucao/dados/bloco-0.3-entradas-baseline.txt
   plano/redesenho/execucao/dados/bloco-0.3-entradas-pos.txt
   ```

8. ℹ️ **Corroboração independente da linha de base do `sdk.js`, para o bloco 0.5.** Medi o SDK
   **antes** de tocar em qualquer arquivo, e deu **29.014 B crus / 9.595 B gzip** — o mesmo número que
   o coordenador remediu no PLANO-MESTRE §12, e não os 28.834 / 9.508 que o plano trazia. Como
   `vite.lib.config.ts` não foi tocado e o `sdk.js` saiu byte-idêntico depois das correções, os
   29.014 / 9.595 valem tanto antes quanto depois do 0.3: **o gate do 0.5 pode ancorar nesse par com
   segurança**, e um "+180 B de regressão" contra o número antigo seria artefato do plano, não do
   código.

---

## 13. O que isto destrava

O aceite do bloco 0.2 ("os 16 snapshots revisados um a um") estava **inverificável** porque o harness
devolvia 404 e o widget nunca renderizava. Com o caminho de teste de volta, `TEST=true` serve o
entrypoint do widget com **200** e o executor da DoD pode medir os 16 quando o coordenador liberar.

Duas coisas que quem for medir precisa saber:

1. **O aquecimento leva ~58s** antes de `/__ready` virar 200. É custo de boot do `webServer`, não do
   primeiro teste — o `timeout` do `playwright.config.js` tem de acomodá-lo.
2. **Os 16 snapshots vão ser medidos sobre um `dashboard.js`/`widget.js` de hash novo** (§8). O
   conteúdo funcional do widget não mudou — o `widget.js` saiu byte-idêntico em tamanho, gzip e
   sourcemap, e a única diferença é a string do nome de um chunk importado. Ainda assim, quem comparar
   pixels deve saber que a mudança existe e de onde vem, para não atribuir a ela um diff de imagem que
   venha de outro lugar.
