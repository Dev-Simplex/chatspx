# Onda 0 — Auditoria semântica do merge v4.16.2 · ÁREA A3: WIDGET + SHARED + SDK + BUILD

**Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **HEAD:** `93571c69db`
**SHAs:** BASE `899fce1c92` (v4.12.1) · NOSSO `f26db6ee81` · DELES `70e284a044` (v4.16.2) · MERGE `93571c69db`
**Área:** 53 arquivos (`dados/area-front-widget.tsv`) — 1 APAGADO, 1 PEGOU_DELES, 29 PEGOU_NOSSO, 22 MERGE_REAL
**Método:** para cada arquivo, extração das linhas `git diff BASE NOSSO | grep '^+'` e verificação uma-a-uma da presença no MERGE (script `verifica.sh`), mais leitura do diff `NOSSO→MERGE`.

---

## RESUMO EXECUTIVO

**A área sobreviveu bem.** Das 53 entradas, **49 são OK**, 2 são PERDA, 2 são RISCO, 0 é DADO.
Mas a auditoria encontrou **dois fatos que a lista de 53 arquivos não mostrava** e que mudam o
planejamento do redesenho mais do que qualquer PERDA da lista:

> ### ⚠ FATO 1 — o merge tocou **82 arquivos em `app/javascript/widget/`**, não 4.
> A lista de 53 só continha os arquivos que **nós** havíamos customizado. O upstream mudou
> `App.vue`, `ChatFooter.vue`, `UserMessage.vue`, `UserMessageBubble.vue`, `PreChat/Form.vue`,
> `PreChatForm.vue`, `GroupedAvatars.vue`, `ArticleBlock.vue`, `ArticleListItem.vue`,
> `store/modules/conversation/*`, `helpers/actionCable.js`, `api/endPoints.js` e 60+ locales
> — **667 inserções fora de i18n**.
>
> ### ⚠ FATO 2 — os 16 snapshots Playwright foram capturados **ANTES** dessas mudanças.
> Eles estão íntegros no repo (bit a bit), mas retratam o widget de `f26db6ee81`.
> `App.vue:380` do MERGE adiciona `bg-n-slate-2 dark:bg-n-solid-1` ao **container raiz do widget**,
> que antes não tinha background nenhum. Isso muda o pixel de fundo de **todas as 4 telas
> capturadas, em light e dark**.
>
> **Consequência para o bloco 0.1:** a régua existe, mas ainda não foi confrontada com o merge.
> Antes de usar os snapshots como baseline do redesenho é preciso rodá-los uma vez contra o
> MERGE, ler o diff, e **re-aprovar conscientemente** o novo baseline. Aprovar sem ler o diff
> viola o MUST NOT do §10.3 — e reprovar em bloco descartaria mudanças upstream legítimas.

Os focos pedidos, respondidos em uma linha cada:

| foco | resposta | número |
|---|---|---|
| 1. `shared/` — `n-brand` | sobreviveu; **subiu de 7 para 8** usos (o novo é `EmojiPicker.vue:59`) | 7 → 8 |
| 1. `shared/` — `getContrastingTextColor` | **inalterado** pelo merge | 6 em `shared/`, 20 em `app/javascript/` (antes e depois) |
| 2. `widget/assets/scss/woot.scss` | **íntegro** — 32/32 linhas nossas presentes; a remarcação verde de `iris`/`text-blue`/`border-blue` (light+dark) sobreviveu; o merge só ADICIONOU | 32/32 |
| 3. `vite.config.ts` | **PERDA** — 3 blocos nossos descartados de verdade + 1 que o bloco 0.3 já queria matar. SDK segue IIFE ✔ | 30 linhas nossas → 0 |
| 4. `@playwright/test` | **preservado**; `playwright.config.js`, `spec/e2e/**` e os 16 PNG **bit a bit idênticos** | 16/16 |
| 5. `public/` | **29 de 29 são NOSSOS** | 29/29 |
| 6. `theme/colors.js` / `tailwind.config.js` | **íntegros**; o merge só ADICIONA | 15/15 e 99/99 |

---

## TABELA DE VEREDITOS

### Build / dependências / SDK

| arquivo | classe triagem | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|
| `package.json` | MERGE_REAL (30) | **OK** | nada — **27/27** linhas nossas presentes | `"@playwright/test": "1.59.1"` em `package.json:143`; `"playwright": "^1.59.1"` em `:163`; `"@axe-core/playwright": "4.10.2"` em `:134` | — |
| `pnpm-lock.yaml` | MERGE_REAL (658) | **OK** | nada; a única linha nossa ausente é `dompurify: 3.3.2`, substituída pelo bump upstream para `3.4.11` no próprio `package.json:82` | **139/139** deps do `package.json` presentes no lock e **139/139 `specifier:` coerentes** — é exatamente o que `pnpm install --frozen-lockfile` valida | — |
| `vite.config.ts` | PEGOU_DELES (30) | **PERDA** | `optimizeDeps` do canvas de Automações; `lord-icon` em `isCustomElement`; `resolve.dedupe: ['html2pdf.js']` | NOSSO `vite.config.ts:32`, `:47-64`, `:114`; MERGE tem **17 linhas** e nenhuma delas | §C1 §C2 §C3 |
| `vite.shared.ts` | (novo, upstream) | **PERDA (mesma causa)** | é onde `lord-icon` deveria ter aterrissado | `vite.shared.ts:19` → `['ninja-keys']` só | §C1 |
| `vite.lib.config.ts` | (novo, upstream) | **OK** | — | `formats: ['iife']` em `:28`; saída `js/sdk.js` em `:22`; `inlineDynamicImports: true` em `:23` | — (o SDK **continua IIFE**, como o bloco 0.3 exige) |
| `vitest.config.ts` | (novo, upstream) | **OK** | bloco `test:` migrado íntegro do nosso `vite.config.ts:116-144` | `vitest.config.ts:10-38` | — |
| `app/javascript/entrypoints/sdk.js` | — | **OK** | nada; **byte-idêntico** ao NOSSO | `git diff f26db6ee81 93571c69db -- app/javascript/entrypoints/sdk.js` → vazio | — |
| `app/javascript/sdk/` (dir) | — | **OK** | nada; **byte-idêntico** ao NOSSO | `git diff --stat … -- app/javascript/sdk/` → vazio | — |

### Documentação de API

| arquivo | classe triagem | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|
| `swagger/swagger.json` | MERGE_REAL (69140) | **PERDA** | a **abrangência**: de **353 paths documentados** para **90** (o artefato do upstream). A marca ChatSPX sobreviveu | NOSSO 66.102 linhas / 353 paths → MERGE 16.259 linhas / 90 paths, e `set(paths_MERGE) == set(paths_DELES)` é `True` | §C4 |
| `swagger/index.yml` | — | **OK** | nada — 11/11 linhas nossas | `"title": "Chat SPX API"`, `contact.name: Simplex Solucoes`, `license: Proprietaria`, `servers: [/]` presentes até no `swagger.json` do MERGE (`:4-18`) | — |
| `swagger/index.html` | — | **OK** | nada — 28/28; **byte-idêntico** ao NOSSO | Scalar + `--scalar-color-accent: #2dc46f` | — |

### Tema / marca

| arquivo | classe triagem | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|
| `theme/colors.js` | MERGE_REAL (30) | **OK** | nada — **15/15** linhas nossas | `brand: '#2dc46f'` em `theme/colors.js:227`; escala `woot.25..900` verde em `:16-27`; `teal-text`/`teal-border` em `:266-267`. O merge só **adiciona** (`portal*` em `:228-230`, `call-widget*` em `:259-263`) | — |
| `tailwind.config.js` | MERGE_REAL (99) | **OK** | nada — **99/99** linhas nossas | paletas `wa-composer`/`wa` em `:41-67`; `boxShadow.overlay/dropdown`; keyframes `head-shake`/`glow-pulse`; plugin `tailwindcss-animated` | — (ver RISCO R3) |
| `app/javascript/widget/assets/scss/woot.scss` | MERGE_REAL (64) | **OK** | nada — **32/32** linhas nossas | `--iris-9: 45 196 111` em light `:190` e dark `:297`; `--text-blue: 24 166 88`; `--border-blue: 45, 196, 111, 0.5`; `select:not(.reset-base)` preservado em `:112` | — (ver RISCO R3) |
| `public/manifest.json` | PEGOU_NOSSO (84) | **OK** | nada; o descartado foi a cor de marca **deles** (`#2781F6`) | `"name": "SPX - CHAT"` em `public/manifest.json:2` | — |

### `shared/`

| arquivo | classe triagem | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|
| `shared/helpers/FileHelper.js` | MERGE_REAL (270) | **OK** | nada — **243/243** | — | — |
| `shared/components/ui/MultiselectDropdownItems.vue` | MERGE_REAL (84) | **OK** | nada; as 3 linhas "ausentes" foram **estendidas**, não removidas | `isAIOption` (`:92-96`) virou `type==='agent_bot' \|\| assignee_type==='AgentBot'`; `grouped` (`:42-46`) e `showGroupHeader` (`:97-101`) intactos; consumidor `ConversationAction.vue:583` ainda passa `:grouped="showAssigneeGroups"` | — |
| `shared/components/ui/MultiselectDropdown.vue` | MERGE_REAL (7) | **OK** | nada — 6/6; `:grouped` repassado em `:165` | — | — |
| `shared/helpers/MessageFormatter.js` | MERGE_REAL (39) | **OK** | nada; `sanitizeLegacyGroupContent` **preservado e encadeado** | `:125` → `sanitizeLegacyGroupContent(message \|\| '').replace(COLWIDTHS_MARKER_REGEX,'')`; helper íntegro em `:57-100` | — (ver RISCO R4) |
| `shared/helpers/specs/MessageFormatter.spec.js` | MERGE_REAL (53) | **OK** | nada — 44/44 | — | — |
| `shared/helpers/timeHelper.js` | MERGE_REAL (22) | **OK** | nada; a única linha "ausente" é **comentário jsdoc** reescrito pelo upstream | `locale: ptBR` em `:63`; `shortTimeAgo` íntegro em `:74-89` | — |
| `shared/helpers/specs/timeHelper.spec.js` | MERGE_REAL (2) | **OK** | nada — 1/1 | — | — |
| `shared/components/charts/BarChart.vue` | MERGE_REAL (17) | **OK** | nada — 15/15 | — | — |
| `shared/store/globalConfig.js` | MERGE_REAL (5) | **OK** | nada — 5/5 | — | — |
| `shared/components/emoji/EmojiInput.vue` | **APAGADO** (4) | **RISCO** | o componente inteiro. A deleção é **do upstream** (não existe em `70e284a044`) e **nenhum arquivo o importa mais** | substituto `shared/components/emoji/EmojiPicker.vue`; `grep -rn "emoji/EmojiInput" app/javascript/` → vazio; `box-shadow-blue` não existe mais em lugar nenhum | §R1 |

### `widget/` · `v3/` · `entrypoints/`

| arquivo | classe triagem | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|
| `widget/components/ChatInputWrap.vue` | MERGE_REAL (15) | **OK** | nada — 5/5 linhas nossas | `border-n-brand shadow-focus` em `:161`; `border-n-weak` em `:162`; `bg-transparent` em `:190`. O merge trocou `EmojiInput` → `EmojiPicker` (`:11-13`, `:177-182`) | — (ver §R1) |
| `widget/components/PreChat/Form.vue` | MERGE_REAL (2) | **OK** | nada — 1/1 | — | — |
| `entrypoints/dashboard.js` | MERGE_REAL (24) | **OK** | nada — **24/24** | — | — |
| `entrypoints/portal.js` · `superadmin.js` · `survey.js` | fora dos 53 | **OK** | 0 linhas nossas nesses arquivos — só mudança upstream | — | — |
| `v3/views/login/Index.vue` | MERGE_REAL (28) | **OK** | nada de substantivo: nosso `mt-8` da seção MFA virou `mt-11` e `v-if`→`v-else-if` porque o upstream inseriu `SessionLimitOverlay` antes | MERGE `:332`; nossa identidade visual (`h-13`, `rounded-2xl`, `text-n-brand hover:text-[#1FB85A]`, `max-w-md w-full mx-auto`) intacta | §R2 (cosmético) |
| `v3/components/Form/Input.vue` | MERGE_REAL (11) | **OK** | nada — 6/6 | — | — |
| `v3/views/auth/signup/components/Signup/Form.vue` | MERGE_REAL (2) | **OK** | nada — 1/1 | — | — |
| `v3/App.vue` | MERGE_REAL (2) | **OK** | nada — 1/1 | — | — |

### `public/` — os 29 arquivos, um por linha (foco 5)

Método: comparação de **blob SHA** do MERGE contra NOSSO e contra DELES.
`==NOSSO? = SIM` significa que o binário no merge é bit a bit o nosso.

| arquivo | ==NOSSO? | ==DELES? | blob no MERGE |
|---|---|---|---|
| `public/manifest.json` | SIM | NAO | `1877b9c454` |
| `public/ms-icon-70x70.png` | SIM | NAO | `a84ffc9e6b` |
| `public/ms-icon-310x310.png` | SIM | NAO | `df5683a441` |
| `public/ms-icon-150x150.png` | SIM | NAO | `57d5803d7b` |
| `public/ms-icon-144x144.png` | SIM | NAO | `3d55d0eb83` |
| `public/favicon-badge-96x96.png` | SIM | NAO | `e45584fbdc` |
| `public/favicon-badge-32x32.png` | SIM | NAO | `9b001881e1` |
| `public/favicon-badge-16x16.png` | SIM | NAO | `7f7983b63d` |
| `public/favicon-96x96.png` | SIM | NAO | `e45584fbdc` |
| `public/favicon-512x512.png` | SIM | NAO | `07029c4bfb` |
| `public/favicon-32x32.png` | SIM | NAO | `7b77569d9d` |
| `public/favicon-16x16.png` | SIM | NAO | `bf0df0c0c6` |
| `public/apple-icon-precomposed.png` | SIM | NAO | `98fba5d9ca` |
| `public/apple-icon.png` | SIM | NAO | `98fba5d9ca` |
| `public/apple-icon-76x76.png` | SIM | NAO | `550caf23a3` |
| `public/apple-icon-72x72.png` | SIM | NAO | `89599f3fd0` |
| `public/apple-icon-60x60.png` | SIM | NAO | `d8d695f73b` |
| `public/apple-icon-57x57.png` | SIM | NAO | `e64e393d13` |
| `public/apple-icon-180x180.png` | SIM | NAO | `07280afd6e` |
| `public/apple-icon-152x152.png` | SIM | NAO | `c02de5646e` |
| `public/apple-icon-144x144.png` | SIM | NAO | `60e99fc0dd` |
| `public/apple-icon-120x120.png` | SIM | NAO | `0f2d575897` |
| `public/apple-icon-114x114.png` | SIM | NAO | `250edc37f1` |
| `public/android-icon-96x96.png` | SIM | NAO | `e45584fbdc` |
| `public/android-icon-72x72.png` | SIM | NAO | `87877054f5` |
| `public/android-icon-48x48.png` | SIM | NAO | `91563d416b` |
| `public/android-icon-36x36.png` | SIM | NAO | `f418f205c4` |
| `public/android-icon-192x192.png` | SIM | NAO | `0004efea21` |
| `public/android-icon-144x144.png` | SIM | NAO | `3d55d0eb83` |

**29 SIM / 0 NAO. Nenhuma perda de marca. Nada a corrigir.**

Nota de contexto (fora dos 53): o merge apagou `public/assets/images/dashboard/priority/{high,low,medium,none,urgent}.svg`.
Verificado: o upstream também os apagou (`git ls-tree 70e284a044` → vazio) e **nenhum arquivo em `app/` os referencia**. Deleção legítima.

---

## CORREÇÕES PROPOSTAS, EM ORDEM DE GRAVIDADE

### §C1 — PERDA · `lord-icon` deixou de ser custom element (quebra ícone animado em runtime)

**Por quê importa:** `LordIconIcon.vue:155` renderiza `<lord-icon …>`. Sem a declaração, o compilador
Vue trata `lord-icon` como componente, não acha, emite
`Failed to resolve component: lord-icon` e **não renderiza o ícone**.

**Patch** — `vite.shared.ts:19`:

```diff
 export const vueOptions = {
   template: {
     compilerOptions: {
-      isCustomElement: (tag: string) => ['ninja-keys'].includes(tag),
+      isCustomElement: (tag: string) => ['ninja-keys', 'lord-icon'].includes(tag),
     },
   },
 };
```

Uma edição só cobre os três consumidores (`vite.config.ts`, `vitest.config.ts` importam `vueOptions` daqui).

---

### §C2 — PERDA · `optimizeDeps` do canvas de Automações (quebra o `vite dev`)

**Por quê importa:** sem isso, o chunk lazy do canvas quebra com `process is not defined`
no servidor de dev (Vue Flow lê `NODE_ENV`, `vue-shepherd` lê `ES_BUILD`). Afeta **só o DEV** —
o build de produção substitui `process` sozinho. Este bloco foi escrito exatamente para
resolver aquele bug, e o merge o desfez.

**Patch** — `vite.config.ts`, dentro de `defineConfig({ … })`:

```diff
 export default defineConfig({
   plugins: [ruby(), vue(vueOptions), yaml()],
+  optimizeDeps: {
+    // Deps do canvas de Automações que leem `process.env.*`. Como o canvas é lazy-loaded,
+    // sem incluí-las o vite dev não substitui `process` no pré-bundle e o chunk quebra com
+    // "process is not defined" (Vue Flow via NODE_ENV; vue-shepherd via ES_BUILD). Só afeta
+    // o DEV — o build de produção já substitui.
+    include: [
+      '@vue-flow/core',
+      '@vue-flow/background',
+      '@vue-flow/controls',
+      '@vue-flow/minimap',
+      'vue-shepherd',
+    ],
+    esbuildOptions: {
+      define: {
+        'process.env.ES_BUILD': 'false',
+      },
+    },
+  },
   css: {
```

**Mecanismo de aceite** (obrigatório, §10.3): subir `bin/vite dev` **em porta ≠ 3000**, abrir a rota
do canvas de Automações e afirmar que o console **não** contém `process is not defined`.
Sem esse passo executado, a correção é afirmação, não fato.

---

### §C3 — PERDA · `resolve.dedupe: ['html2pdf.js']`

**Por quê importa:** `dashboard/helper/ConversationPDFExporter.js:2` importa `html2pdf.js`.
O `dedupe` existia para impedir duas cópias da lib no grafo (jsPDF/html2canvas transitivos),
que produzem PDF em branco ou erro de instância.

**Patch** — `vite.config.ts:16`:

```diff
-  resolve: { alias: aliases },
+  resolve: { alias: aliases, dedupe: ['html2pdf.js'] },
```

**Mecanismo de aceite:** exportar uma conversa em PDF e verificar que o arquivo tem páginas.

**NÃO portar:** `manualChunks: { leaflet: ['leaflet'] }` (NOSSO `vite.config.ts:82-90`). O merge já
o eliminou e o bloco 0.3 quer que ele morra. `LocationPickerModal.vue:90` já importa Leaflet por
`import()` dinâmico, que é a forma correta de isolar o peso. Registrado aqui só para que ninguém
o "restaure por engano" ao aplicar §C2/§C3 no mesmo arquivo.

---

### §C4 — PERDA · `swagger/swagger.json` caiu de 353 para 90 paths

**O que sobreviveu:** a **marca** (`"title": "Chat SPX API"`, contato Simplex, licença proprietária,
`servers: [/]`) e o `swagger/index.html` com o Scalar verde. **O que se perdeu:** 283 dos 353 paths
documentados. Os 90 restantes são exatamente o conjunto do upstream.

**Diagnóstico honesto — a correção não é trivial.** O próprio comentário que nós escrevemos em
`swagger/index.yml:1-4` explica por quê:

> `# NOTA (Chat SPX): o swagger.json servido em /swagger e gerado de forma ABRANGENTE`
> `# pelo pipeline SPX (cobre os 141 controllers da API). Este index.yml (fonte upstream`
> `# fragmentada) cobre apenas um subconjunto; `rake swagger:build` sozinho NAO reproduz o`
> `# spec completo. Ver scratchpad/assemble.rb + specs.json para regenerar.`

Verificado: **`assemble.rb` e `specs.json` não estão versionados e não existem mais na VM**
(`git ls-tree` e `find /home/chatwoot` → vazio). Portanto `rake swagger:build` **não** restaura os 353 paths.

**Duas opções, em ordem de custo — decisão do executor de correção, não minha:**

1. **Barata, reversível, recomendada como primeiro passo:** restaurar o artefato anterior e
   registrar o débito.
   ```bash
   git checkout f26db6ee81 -- swagger/swagger.json
   ```
   Custo: perde a documentação dos endpoints novos do upstream (`branded_email_layout`,
   payloads de canal por tipo). Ganho: `/swagger` volta a documentar 353 endpoints.

2. **Correta, cara:** reconstruir o pipeline de assemble sobre as fontes **novas** (o merge trouxe
   291 fontes `.yml`, 16 a mais que as nossas 275 — **nenhuma fonte nossa foi perdida**) e regerar.
   Isso resolve os dois lados de uma vez e elimina o débito permanentemente.

Os 4 `swagger/tag_groups/*_swagger.json` são gerados pelo mesmo pipeline e estão **praticamente
intactos** (87 → 88 paths), o que confirma que a perda está isolada no `swagger.json` principal.

---

### §R1 — RISCO · o emoji picker do widget trocou de componente

`EmojiInput.vue` (apagado pelo upstream) → `EmojiPicker.vue`. No widget, `ChatInputWrap.vue:177-182`
trocou a API do componente:

```diff
-      <EmojiInput
+      <EmojiPicker
         v-if="shouldShowEmojiPicker && showEmojiPicker"
         v-on-clickaway="hideEmojiPicker"
-        :on-click="emojiOnClick"
+        class="!bottom-full end-0 mb-2 max-w-[calc(100vw-3rem)]"
+        @select="onSelectEmoji"
```

e removeu o `.emoji-dialog` scoped que posicionava o painel.

**Nossa perda direta é pequena:** era só a cor do foco (`#2dc46f` no lugar do `#1f93ff`),
e `EmojiPicker.vue:59` já usa `focus:outline-n-brand` — **token, não hex** — portanto herda o verde
automaticamente. **Nada a corrigir em código.**

**O risco é de plano, não de código:** qualquer bloco do redesenho que descreva o emoji picker do
widget descreve um componente que não existe mais. Ação: revisar as referências a `EmojiInput`
nos blocos das ondas 1–6 antes de executá-los.

---

### §R2 — RISCO (cosmético) · espaçamento da seção MFA no login

`v3/views/login/Index.vue:332`: nosso `mt-8` virou `mt-11` e o `v-if` virou `v-else-if` porque o
upstream inseriu `SessionLimitOverlay` como irmão anterior. As classes de layout que **eram nossas**
(`max-w-md w-full mx-auto`) foram preservadas.

**Correção, se alguém quiser o espaçamento original:**
```diff
-    <section v-else-if="mfaRequired" class="mt-11 max-w-md w-full mx-auto">
+    <section v-else-if="mfaRequired" class="mt-8 max-w-md w-full mx-auto">
```
Não recomendo aplicar sem ver a tela: `mt-11` é o valor do upstream para os dois irmãos, e trocar
só um cria assimetria entre o overlay de sessão e o de MFA.

---

### §R3 — RISCO · a renderização de listas dentro da bolha mudou (afeta o pixel do widget)

Duas mudanças upstream coordenadas alteram como `<ul>`/`<ol>` aparecem **dentro da mensagem**:

`widget/assets/scss/woot.scss:34-56` (`.message-content`):
```diff
   ul {
-    list-style: disc;
-    @apply ltr:pl-3 rtl:pr-3;
+    @apply list-disc list-inside;
   }
+  li {
+    padding-inline-start: 1.5em;
+    text-indent: -1.5em;
+    > p:first-child { @apply inline; }
+    > * { text-indent: 0; }
+  }
```

`tailwind.config.js` (`typography.bubble`): `'ul li'` → `'ul > li'`, `paddingInlineStart` `0.625em` → `0`,
mais `listStylePosition: 'inside'` e o mesmo par `paddingInlineStart: 1.5em` / `textIndent: -1.5em`.
Junto vieram a **remoção dos overrides RTL** (`'[dir="rtl"] &': { margin: … }`).

**Isto não é perda nossa** — nós não tínhamos customizado nada disso. Mas:
- muda o pixel do snapshot `messages-*.png` sempre que a mensagem tiver lista;
- `typography.bubble` também alcança o widget por `shared/components/CustomerSatisfaction.vue:136`
  (`class="… prose prose-bubble"`), que é a superfície de CSAT dentro do widget;
- a remoção dos overrides RTL é uma mudança de comportamento em árabe/hebraico que ninguém pediu.

**Ação:** nada a reverter. Registrar como causa conhecida de diff visual quando os snapshots forem
reconfrontados (ver FATO 2), para que o diff seja aprovado com justificativa e não às cegas.

---

### §R4 — RISCO · `useBranding` ficou case-insensitive

`shared/composables/useBranding.js:21`:
```diff
-    return text.replace(/Chatwoot/g, installationName);
+    return text.replace(/chatwoot/gi, installationName);
```

Melhora a cobertura do rebranding, mas agora **qualquer** ocorrência casa — inclusive dentro de
strings técnicas. Se algum texto traduzido contiver `chatwoot.com`, `www.chatwoot.com` ou
`@chatwoot/utils`, o resultado vira `SPX - CHAT.com`. Não encontrei ocorrência ativa,
mas é uma armadilha para quem escrever i18n novo.

**Ação:** nenhuma correção de código. Anotar na convenção de i18n: nunca colocar URL literal
`chatwoot.com` em string traduzível.

---

## CONFIRMAÇÃO INDEPENDENTE DOS 3 ACHADOS DE PARTIDA

Verifiquei os três por conta própria, sem reaproveitar a afirmação do coordenador.

**1. DADO — `enterprise/app/models/captain/assistant_response.rb` — ✅ CONFIRMADO, e é grave.**
```
NOSSO  f26db6ee81:45  enum status: { pending: 0, approved: 1 }
MERGE  93571c69db:47  enum status: { approved: 1 }
```
A migration existe: `db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb`.
Confirmo a leitura do coordenador: no upstream `status = 0` é lixo, no nosso fork é **FAQ pendente
viva**. A migration apaga dado de cliente da frota. Prioridade máxima — mas é da área Ruby/Captain,
não da minha; deixo a correção com aquele executor.

**2. PERDA — `dashboard/routes/dashboard/captain/responses/Pending.vue` — ✅ CONFIRMADO.**
`git cat-file -e f26db6ee81:…` → existe. `git cat-file -e 93571c69db:…` → **ausente**. Casa com o achado 1.

**3. RISCO — `config/features.yml` — ⚠️ CONFIRMADO O FATO, mas o RISCO **NÃO SE MATERIALIZA**.**

O fato é verdadeiro: `conversation_required_attributes` (`:302`) e `advanced_assignment` (`:307`)
ganharam `column: feature_flags_ext_1` no MERGE, e **não existe migration de carregamento de estado**
(as únicas migrations de flag são `…_change_feature_flags_to_bigint`, `…_flip_chatwoot_v4_default…`
e `…_add_feature_flags_ext_2_to_accounts` — nenhuma migra valores de `feature_flags` para `ext_1`).

Mas a preocupação — "conta da frota que já tivesse esses flags ligados pode aparecer como desligada" —
**não pode acontecer**, e o número mostra por quê. Comparei a coluna default **bit a bit**:

```
NOSSO  default: 65 flags   (índices 0..64)
MERGE  default: 63 flags   (índices 0..62)  + 14 em feature_flags_ext_1

Posições que mudaram para algum flag presente nos dois:
  bit 63  conversation_required_attributes  -> movido para ext_1
  bit 64  advanced_assignment               -> movido para ext_1
  (nenhuma outra)
```

Os **63 primeiros bits mantêm ordem idêntica** — nenhum flag da frota foi remapeado. E os dois flags
movidos ocupavam os índices **63 e 64** de uma coluna `bigint` que comporta **63 bits (0..62)**:
eram justamente os dois que **estouravam o bitmask** e que, portanto, **nunca puderam ser gravados
em conta nenhuma**. Não há estado a preservar porque nunca houve estado.

**Veredito revisado: OK.** A resolução do merge é correta *e* segura, e **não precisa** de migration
de carregamento. O `features.yml:13-16` do MERGE agora documenta a regra
(`The feature_flags column is FULL (63/63 slots used)`), que é exatamente o que a nossa nota
`reference_chatspx_feature_flags_bitmask_cheio` antecipava. Ganhamos do upstream aqui.

---

## CONTAGEM POR VEREDITO

| veredito | nº | quais |
|---|---|---|
| **OK** | **49** | `package.json`, `pnpm-lock.yaml`, `theme/colors.js`, `tailwind.config.js`, `woot.scss`, `manifest.json` + 28 favicons, `FileHelper.js`, `MultiselectDropdownItems.vue`, `MultiselectDropdown.vue`, `MessageFormatter.js`, `MessageFormatter.spec.js`, `timeHelper.js`, `timeHelper.spec.js`, `BarChart.vue`, `globalConfig.js`, `ChatInputWrap.vue`, `PreChat/Form.vue`, `entrypoints/dashboard.js`, `v3/views/login/Index.vue`, `v3/components/Form/Input.vue`, `Signup/Form.vue`, `v3/App.vue` |
| **PERDA** | **2** | `vite.config.ts` (§C1 §C2 §C3), `swagger/swagger.json` (§C4) |
| **RISCO** | **2** | `shared/components/emoji/EmojiInput.vue` (§R1), `v3/views/login/Index.vue` — cosmético (§R2) |
| **DADO** | **0** | — |

Fora dos 53, mas registrados por afetarem o redesenho: §R3 (listas na bolha) e §R4 (`useBranding`).
`v3/views/login/Index.vue` aparece em duas linhas porque tem veredito OK e um resíduo cosmético; conta **uma vez**, como OK.

**COBERTURA: 53 de 53 arquivos da área auditados.**

Checagem da cobertura: 22 MERGE_REAL + 1 PEGOU_DELES + 1 APAGADO + 29 PEGOU_NOSSO = 53.
Auditados adicionalmente, fora da lista: `vite.shared.ts`, `vite.lib.config.ts`, `vitest.config.ts`,
`entrypoints/{sdk,portal,superadmin,survey}.js`, `app/javascript/sdk/`, `swagger/index.yml`,
`swagger/index.html`, `shared/composables/useBranding.js`, `widget/App.vue`, `widget/components/{ChatFooter,UserMessage,UserMessageBubble}.vue`,
`playwright.config.js`, `spec/e2e/widget/**` (16 snapshots), `public/assets/images/dashboard/priority/*`.

---

## O QUE O PRÓXIMO EXECUTOR PRECISA FAZER (ordem sugerida)

1. **§C1** — uma linha em `vite.shared.ts`. Barato, corrige quebra visível.
2. **§C2** — restaurar `optimizeDeps`. **Com** o mecanismo de aceite executado (vite dev em porta ≠ 3000).
3. **§C3** — restaurar `dedupe`. **Com** aceite (exportar um PDF).
4. **FATO 2 / bloco 0.1** — rodar os 16 snapshots contra o MERGE, **ler o diff**, decidir
   arquivo por arquivo o que é mudança upstream legítima (§R3, `App.vue:380`) e re-aprovar
   o baseline conscientemente. **Não** aprovar em bloco.
5. **§C4** — decidir entre restaurar o `swagger.json` antigo (barato) ou reconstruir o pipeline (correto).

**Nada foi editado neste worktree.** Esta auditoria é somente-leitura; o único arquivo escrito é
este relatório, fora do repositório.
