# CSS Deep Audit — ChatSPX WA Skin

**Auditor:** @ux-design-expert (Alex) • **Escopo:** `_next-colors.scss`, `_wa-skin.scss` (2002 linhas), `_woot.scss`
**Uso de `!important` em `_wa-skin.scss`:** **202 ocorrencias** em 2002 linhas (10% das linhas). Sinal de guerra de especificidade perdida.

---

## 1. Conflitos / regras redundantes DENTRO do skin

### ❌ `.conversations-list .conversation` definido em **3 blocos** diferentes
- L273-284: `border-bottom` + `transition` + hover
- L317-351: thumbnail, typography, cores (`--wa-text-primary`)
- L1183-1207: **re-define** `padding`, `.conversation--user` font-size **17px** (vs L324-327 que diz **15px**)
- L1755-1788: **re-re-define** cores com `!important` direto em hex (`#111b21`, `#667781`)

**Efeito:** `.conversation--user` tem 3 font-sizes possiveis (15px → 17px → nenhum), 3 cores (var token → var token → hex). O bloco de L1755+ com `!important` vence tudo, mas o L324 e L1186 viraram **CSS morto**. ⚠️ Bug-prone se alguem editar o bloco errado.

### ❌ `.conversation:not(.active):hover` vs `.conversations-list .conversation:hover`
- L281-284 (specificity 0,2,1): `bg: var(--wa-list-hover)` → `#f5f6f7`
- L1791-1794 (specificity 0,2,1 mas `!important`): `bg: #e9edef` + `inset box-shadow verde`

**Conflito:** dois valores diferentes pro mesmo estado. O de baixo (L1791) vence por cascade + `!important`. A regra de L281 e **redundante** e usa `var(--wa-list-hover)` = `#f5f6f7` que **nunca e aplicado**. Remover.

### ❌ `.reply-box` definido em 4 lugares
- L434-443 (radius 12px, box-shadow, bg `var(--wa-composer-bg)` = branco)
- L817-819 (transition)
- L1397-1403 (padding + bg `var(--wa-header-bg)` = **#f0f2f5**)
- L1990-1995 (bg **#f0f2f5** + border-top `#d1d7db`, `!important`)

**Conflito real:** L434 pinta reply-box de **branco**, L1990 pinta de **cinza #f0f2f5**. Ambas com `!important`. A ultima ganha no compilado (ordem no arquivo), mas so por sorte — trocar a ordem dos blocos quebra.

### ❌ `.conversation-panel` / `.conversation-details-wrap` duplicados
- L76-94: `conversation-panel-light` e `-dark` com background-image + `!important`
- L97-102: `conversation-details-wrap` cor base
- L1974-1985: **sobrescreve tudo** com `background-color: #efeae2 !important` SEM a background-image. Resultado: o wallpaper PNG pode nao aparecer porque `background-color !important` dessa regra vence o `background-color !important` da L83, mas o `background-image` da L76 ainda aplica. Ou seja: wallpaper desenhando em cima de cor chapada — **concorrendo**, nao complementando.

### ⚠️ 12 definicoes de `:root { --wa-* }` espalhadas
- L13-73 (tokens base)
- L726-731 (redeclara `--wa-primary` — redundante, idem valor)
- L1011-1015 (rail width/bg — OK)
- L782-785 (redeclara `--wa-primary` em `.dark` mas com mesmo valor `#00a884`)

**Nao e bug visual,** mas e caos — qualquer refatoracao vai sangrar.

---

## 2. Analise visual dos screenshots

### ❌ `RT-02-dark.png` (lista + hover/active)
- Card com hover tem **borda verde inset-2px** esquerda — **OK WA-fiel**.
- Card active tem inset-3px verde — **OK**.
- **PROBLEMA 1:** O segundo card ("Simplex - Uptim...") mostra **cadeado com fundo escuro** e o texto "Enviado do WhatsApp" parece cortado com **elipses dupla** (`Siste...`). Nao e bug de CSS — e layout squeeze. Mas o `font-size: 14px` no `.conversation--message` (L1196) + padding `10px 13px` (L1184) deixa **pouco espaco util**. WA Web usa ~12.5px aqui.
- **PROBLEMA 2:** A largura da lista esta **cortando** o card da direita (aparece "sim... / Mar"). Isso nao e CSS do skin — provavel `InboxList.vue` width setting, mas combinado com o padding de 13px fica apertado.

### ❌ `tour-04-conv-open-dark.png` / `final-03-conv-dark.png`
- Contatos panel direita: **fundo cinza claro #efeae2 (claro!)** em dark mode numa tira do grid de "Imagens" — isso e **a wallpaper light "vazando"** porque a regra L1974 pinta `conversation-details-wrap` de `#efeae2` SEM `.dark` prefix, e o `.dark` override da L1980 so re-pinta `background-color` mas o elemento pode nao matchar o seletor exato.
- ⚠️ O bubble outgoing (verde escuro `#005c4b`) esta OK.
- ⚠️ Fundo do painel central mostra "Janeiro" como separador — **cor do texto parece OK** em dark.

### ⚠️ `x-hover-vs-active-dark.png`
- Hover: fundo `#202c33` + barra verde esquerda sutil. **OK**.
- Active: fundo `#2a3942` + barra 3px verde. **OK**.
- Contraste da barra hover (inset 2px, alpha 0.5) esta **muito sutil** em dark — pode parecer que so mudou o fundo. Usuario pode perceber como "active esta igual ao hover".

### ✅ `dark-03-toast.png`
- Toast top-right com fundo `#233138` — **OK**.
- Sidebar rail icones cinzas, **toast bem separado**. Sem issues.

---

## 3. Regras globais vs especificas

### ❌ `_woot.scss` — sem conflito direto, MAS:
- L44: `.tooltip { @apply bg-n-solid-2 text-n-slate-12 ... }` usa tokens `bg-n-solid-2`. Em light = branco (`--solid-2: 255 255 255`). Tooltip **branco no WA e errado** — deveria ser `#233138` em TODOS os modos (como o skin faz em L1859 para `.v-popper--theme-tooltip`). Ha dois sistemas de tooltip coexistindo.

### ⚠️ `_next-colors.scss`
- `--solid-blue: 217 253 211` em light (L146) — bubble out OK.
- `--solid-purple: 217 253 211` — **reaproveitou a cor do brand pro purple**. Qualquer componente legado que use purple vai virar verde. Tecnicamente OK pro redesign, mas se algo existir que dependa de diferenciar purple de blue, quebra.
- `--text-blue: 0 168 132` em light E dark (L130 e L286) — **mesmo verde em ambos os modos**. WA Web usa `#53bdeb` (azul claro) pro link/check read em dark. Aqui links ficam **sempre verde** mesmo em dark.
- ✅ Tokens RGB sem virgula (formato Tailwind v3 `rgb(var(--x) / <alpha>)`) — **corretos**.

### ❌ `var(--wa-list-border)` sendo usado SEM `rgb()` wrapper em alguns lugares
- L256-257: `border-bottom-color: var(--wa-list-border)` — `--wa-list-border: #e9edef` (hex puro em `_wa-skin.scss` L29). **OK** porque e hex direto.
- Mas o `--border-container` em `_next-colors.scss` L291 vira `42, 57, 66, 1` (formato rgb/a com virgulas) enquanto L135 e `233 237 239` (formato RGB sem virgula). **Inconsistencia de formato** entre light e dark do mesmo token. Qualquer `rgb(var(--border-container) / 0.5)` vai quebrar em dark.

---

## 4. Especificidade — onde a guerra acontece

### ❌ `.conversation:not(.active):hover` (L1791) tem specificity **(0,2,1)** + `!important`
Bate com `.conversations-list .conversation:hover` (L281) que e **(0,2,1)** sem `!important`. A regra mais generica (sem `.conversations-list` scope) vence em dark porque vem DEPOIS no arquivo. Isso e **fragil** — qualquer reorder quebra.

### ⚠️ `aside [class*='router-link-active']` e outros seletores em `aside`
6 variantes do seletor pra matchar router-link-active (L1912-1927). Todas com `!important`. Funciona, mas **bloqueia qualquer override futuro** sem um `!important` mais especifico. Divida-tecnica acumulando.

### ❌ `[class*='bg-n-solid-1'] { background-color: #111b21 !important; }` (L1056)
Seletor **atributo-contains** super amplo — pega qualquer classe com a substring "bg-n-solid-1" (incluindo compostas como `hover:bg-n-solid-1`). Isso pinta **hover states** que deveriam ser transparentes no estado base.

---

## 5. Top 5 problemas REAIS (priorizados por impacto visual)

### 1. ❌ **CRITICO — Wallpaper do chat vs background-color brigando**
- **Arquivo:** `_wa-skin.scss` L1974-1985 vs L76-94
- **Erro:** L1974 re-pinta `conversation-panel` / `conversation-details-wrap` com `background-color: #efeae2 !important` SEM `background-image`. Mata a imagem do wallpaper em cenarios onde o elemento bate esse seletor antes do de L76.
- **Usuario ve:** Fundo do chat sem a textura WA, ou textura "piscando" em F5.
- **Patch:**
  ```scss
  /* L1974 — remover, manter apenas o fallback em .conversation-panel light/dark */
  ```
  Consolidar em L76-94 apenas.

### 2. ❌ **CRITICO — `.conversation--user` font-size conflitante (15px vs 17px)**
- **Arquivo:** `_wa-skin.scss` L324-328 vs L1186-1191
- **Erro:** Duas regras com mesma specificity definem tamanho diferente. A ultima vence (17px), tornando L324 codigo morto. Se alguem editar L324 achando que e THE lugar, nao muda nada.
- **Usuario ve:** nao percebe — mas o code smell gera futuros bugs.
- **Patch:** Deletar L324-328 (o bloco inteiro de `.conversation--user` / `--message` / `--timestamp` em L324-350 esta duplicado e redundado pelos blocos L1186+ e L1755+).

### 3. ❌ **ALTO — Toast e tooltip usando DOIS sistemas**
- **Arquivo:** `_woot.scss` L44 vs `_wa-skin.scss` L1859
- **Erro:** `.tooltip` no `_woot.scss` aplica `bg-n-solid-2 text-n-slate-12` (token-based, branco em light). Skin em L1859 aplica `.v-popper--theme-tooltip` com `#233138` hardcoded. Se um componente usa `.tooltip` simples (sem FloatingVue), fica **branco sobre branco** em light.
- **Usuario ve:** Tooltips invisiveis em alguns componentes light.
- **Patch:**
  ```scss
  /* _woot.scss L44 */
  .tooltip { @apply bg-n-solid-2 text-n-slate-12 ...; background-color: #233138; color: #e9edef; }
  ```

### 4. ⚠️ **ALTO — `--text-blue` igual em light e dark**
- **Arquivo:** `_next-colors.scss` L130 e L286
- **Erro:** `--text-blue: 0 168 132` (verde WA) nos dois modos. Links renderizam **sempre verde** mesmo em dark — diferente de WA Web que usa `#53bdeb` pra links/timestamps lidos em dark.
- **Usuario ve:** Links em dark tem contraste ruim (#00a884 sobre #0b141a = 3.2:1, **falha WCAG AA**).
- **Patch:**
  ```scss
  .dark { --text-blue: 83 189 235; }  /* #53bdeb - WA dark link blue */
  ```

### 5. ⚠️ **MEDIO — `[class*='bg-n-solid-1']` pegando hover states**
- **Arquivo:** `_wa-skin.scss` L1056-1059
- **Erro:** Seletor `[class*='...']` captura classes compostas como `hover:bg-n-solid-1`. Aplica background escuro fora do estado hover.
- **Usuario ve:** Botoes com `hover:bg-n-solid-1` ficam pintados de `#111b21` o tempo todo em dark.
- **Patch:** Trocar `[class*='bg-n-solid-1']` por `.bg-n-solid-1` (match exato).

---

## 6. Diagnostico honesto — nao estou defendendo

- **O skin esta funcional mas fragil.** 202 `!important` em 2000 linhas nao e arquitetura — e **dividida tecnica pura**. Cada nova regra exige vencer a anterior com mais `!important` ou seletor mais especifico.
- **3 "waves" de edicao sobrepostas:** (1) tokens iniciais + WA basico L1-500, (2) expansao sidebar/scrollbars L500-1250, (3) polish final WA-fiel L1250-2000. Cada wave redefine o que a anterior ja definira, sem limpar o passado.
- **O usuario esta certo em suspeitar:** mesmo que Playwright confirme "a regra esta no DOM", a regra que **vence** pode nao ser a que o dev pensa que vence. Isso gera sensacao de "editei X e nada mudou" — classico sintoma de cascade-hell.
- **Recomendacao estrategica:** antes de adicionar regra nova, **consolidar os 3 blocos de `.conversation*` em UM** e remover os duplicados. Sem isso, qualquer nova edicao vira loteria.

---

**Arquivos de referencia:**
- `/home/chatwoot/chatwoot/app/javascript/dashboard/assets/scss/_wa-skin.scss`
- `/home/chatwoot/chatwoot/app/javascript/dashboard/assets/scss/_next-colors.scss`
- `/home/chatwoot/chatwoot/app/javascript/dashboard/assets/scss/_woot.scss`
