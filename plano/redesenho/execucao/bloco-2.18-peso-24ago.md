# Bloco 2.18 — peso, 2ª rodada · 24/08/2026

> **Uma frase.** O gate do grafo do widget saiu de **VERMELHO em +30,8%** para **VERDE com
> 10.386 B de folga** — 392.497 → 289.614 B gzip, **−102.883 B (−26,2%)** — sem afrouxar
> nenhum teto; o aceite literal do bloco (**≤ 150 KB gzip** e `window.__SENTRY__` undefined)
> **não** foi alcançado, e o que falta está medido byte a byte na §5.

---

## 1. Os números, antes e depois

Tudo medido em build real (`bin/vite build --force`, `pnpm build:sdk`), com
`node scripts/widget-size.mjs`.

| Medida | Antes | Depois | Teto | Situação |
|---|---:|---:|---:|---|
| **JS eager** do first-paint (grafo) | 392.497 B gzip | **289.614 B gzip** | 300.000 | ✅ **folga 10.386 B** |
| Grafo total (JS + CSS) | 407.705 B gzip | 304.822 B gzip | — | CSS é do bloco 1.08 |
| Chunk de entrada | 85.819 B gzip | 39.768 B gzip | — | (não é a régua) |
| **`sdk.js` cru** | 45.229 B | **42.982 B** | 40.000 | ❌ **+2.982** (era +5.229) |
| **`sdk.js` gzip** | 14.994 B | **14.340 B** | 15.000 | ✅ folga **660 B** (era **6 B**) |
| Leaflet fora do first-paint | OK | OK | — | ✅ |

O "antes" é a medição desta worktree (392.497), 81 B acima da do relatório de estado
(392.416) por conta dos commits da trilha em que a worktree está apoiada. Mesmo build,
mesma régua, os dois lados do A/B.

---

## 2. O que entrou — e o que cada frente valeu

### 2.1 i18n sob demanda — `widget/i18n/index.js`, `entrypoints/widget.js`

`index.js` importava os **40 idiomas** de forma estática: **193.227 B renderizados** que
todo visitante baixava para ler **um**. Agora só o `en` — o `fallbackLocale` — é eager; os
outros 39 são `import()`, um chunk por idioma.

O mapa é **explícito**, não `import.meta.glob`: o diretório tem **56** arquivos e este
índice sempre expôs **40**; um glob passaria a expor os 16 restantes, que é mudança de
comportamento escondida dentro de uma otimização.

Sem flash de idioma: o entrypoint resolve os candidatos de boot
(`chatwootWebChannel.locale`, a variação base e `?locale=` do popout) e **espera** as
mensagens **antes do `mount()`** — `App.vue#mounted` chama `setLocale` no tique seguinte.
A troca em tempo de execução (ponte `set-locale`, inbox multi-idioma) é coberta por um
`watch`, com o `en` segurando o intervalo.

### 2.2 FormKit só na rota do pré-chat — `widget/formkit.js`, `entrypoints/widget.js`

`app.use(plugin, defaultConfig(...))` era eager: **203.437 B renderizados** de
`@formkit/{core,inputs,rules,validation,i18n,observer,utils,vue}` no first-paint de **todo**
visitante — inclusive os dos widgets sem pré-chat ligado, que são a maioria.

`PreChat/Form.vue` é o **único** consumidor no widget e só a rota `prechat-form` o monta.
O plugin passou para o `beforeResolve` dessa rota. `app.use()` depois do `mount()` é
legítimo em Vue 3: `createAppAPI#use` não consulta `isMounted`.

**A lista `ROTAS_COM_FORMKIT` é o ponto frágil do desenho** — uma rota nova que monte o
formulário e não esteja nela não quebra build, lint nem teste de componente: quebra o
pré-chat em produção. `widget/specs/formKitSobDemanda.spec.js` carrega as rotas de verdade
e caminha a árvore de `components` procurando o `FormKit` **por identidade de objeto**
(um `grep` acharia a palavra em comentário e em classe CSS). Provado que acusa: com a
lista vazia o teste falha com `expected [ 'prechat-form' ] to deeply equal []`.

### 2.3 `vue` na build runtime-only — `vite.config.ts`

O alias apontava para `vue/dist/vue.esm-bundler.js`, a build **com compilador de template**:
`@vue/compiler-dom` + `@vue/compiler-core`, **168.582 B renderizados** no fecho de
first-paint de um widget que **não compila template nenhum** — todo `.vue` já sai compilado
do `@vitejs/plugin-vue`.

O único consumidor de compilação em runtime que entra em bundle de produção em todo o
`app/javascript` é `portal/portalHelpers.js:86,104`. Ele — e só ele — continua recebendo a
build completa, por `customResolver` do alias. Os dois arquivos são cascas sobre o mesmo
`@vue/runtime-dom`, então não há duas cópias do Vue na página.

`vitest.config.ts` fica com o alias antigo de propósito: dezenas de specs montam dublês com
`template: '<div />'` e precisam do compilador.

### 2.4 `sdk.js` — `vite.sdk-css.ts`, `vite.lib.config.ts`

`SDK_CSS` é template string, e **template string é DADO**: nenhum minificador de JS a toca.
As 409 linhas de CSS indentado viajavam inteiras no único arquivo que 100% dos visitantes de
todos os sites baixam. `vite.sdk-css.ts` as minifica em tempo de build (**−1.622 B**) e
**ABORTA o build** se o literal for renomeado, movido ou ganhar interpolação — um plugin que
não acha o alvo e segue calado devolveria os bytes sem ninguém ver.

Mais terser em 3 passes e sem comentário legal (**−625 B**). O `target` **não** foi mexido:
`esnext` economizaria mais 425 B, mas o SDK roda no navegador do visitante do **cliente**.

---

## 3. A frente que foi MEDIDA E REJEITADA: chunk de vendor próprio

O plano nomeia três frentes; a terceira **custa bytes**. Agrupamento conservador
(`vendor-vue`, `vendor-i18n`, `vendor-markdown`, `vendor-sanitize`, `vendor-http`,
`vendor-routing`, deixando `date-fns` e `@sentry/*` fora):

```
sem manualChunks .... 289.629 B gzip de JS eager   (12 chunks)
com manualChunks .... 316.365 B gzip de JS eager   (19 chunks)
custo ...............  +26.736 B gzip  (+9,2%)
```

Duas causas, as duas estruturais: **gzip não é aditivo** (cada chunk comprime sozinho, e o
gate cobra a soma, que é o que a rede entrega), e **agrupar por PACOTE desfaz o agrupamento
por ALCANÇABILIDADE** que o Rollup já faz — um pacote usado por caminho eager *e* lazy vira
um chunk só, e o first-paint passa a baixar a parte que era só da rota lazy.

O problema real que a frente queria resolver — **nome de chunk que mente**
(`Validators-*.js` continha `@sentry/core`, `vue-router` e `date-fns` e nenhum validador) —
está resolvido por diagnóstico, sem custo de rede: `scripts/widget-eager.check.mjs`.

Também foi testada e rejeitada a flag `__VUE_I18N_LEGACY_API__: false` (vale 3.447 B gzip):
ela remove a API legada do `vue-i18n` do bundle inteiro, e a suíte provou que ainda há
consumidor dela — o teste caiu com «expected 2 to be greater than 2», que é um render que
deixou de acontecer. As duas rejeições estão registradas em `vite.config.ts`.

---

## 4. Como isso foi verificado

**`scripts/widget-eager.check.mjs`** (novo) lê `chunk.modules` **do Rollup** — nunca `grep`
no bundle, que nesta base já achou "amplitude" em atributo de SVG — e cobra o que **não pode**
estar no first-paint. Tem **controles positivos**: se `vue-i18n`, `vue-router`, `App.vue` ou
`en.json` sumirem do fecho, ele falha dizendo que quem quebrou foi a **medição** — sem isso,
um verificador que só afirma ausência passaria medindo nada.

A/B sobre os dois builds reais, com `--stats-only`:

```
ANTES   VERMELHO · 3 problemas   @sentry (39 módulos) · @formkit (10) · 39 idiomas
DEPOIS  VERMELHO · 1 problema    @sentry (39 módulos)
```

**Suíte**: `npx vitest run` — **571 arquivos, 6.350 testes**. Especificamente do bloco:
`widget/i18n/specs/cargaSobDemanda.spec.js` (5), `cargaSobDemandaFalha.spec.js` (1, com o
`import()` do idioma derrubado de propósito — se o dublê não pegasse, o teste falharia),
`widget/specs/formKitSobDemanda.spec.js` (3) e `sdk/specs/sdkCssMinify.spec.js` (4).

---

## 5. O que NÃO foi alcançado, e quanto vale cada coisa que falta

O aceite do bloco é **JS eager ≤ 150 KB gzip** e **`window.__SENTRY__` / `window.amplitude`
undefined dentro do iframe**.

- `window.amplitude` — ✅ **provado**: zero módulos `@amplitude/*` no fecho estático.
- `window.__SENTRY__` — ❌ **39 módulos de `@sentry/core`** continuam no first-paint.
- ≤ 150 KB — ❌ **289.614 B**.

**Por que parou aqui:** as duas pendências exigem arquivos fora do escopo declarado desta
trilha. A pergunta foi mandada ao coordenador (`orca orchestration ask`, duas vezes,
25 min + 15 min) e **não foi respondida** até o fecho.

Valor em gzip de cada item que sobrou (gzip real de cada chunk, rateado entre os pacotes
daquele chunk pela fração de bytes renderizados — **estimativa ancorada em medida**):

| O que | ~gzip | Por onde entra no first-paint | Arquivo a mexer |
|---|---:|---|---|
| `date-fns` + `date-fns-tz` | **40.210 B** | `App.vue` (`addHours`) e `availabilityHelpers` (o `-tz` é CJS: não faz tree-shaking) | `widget/App.vue`, `widget/helpers/availabilityHelpers.js` |
| `markdown-it` + `entities` + `linkify-it` + `mdurl` + `punycode.js` + `uc.micro` | **40.895 B** | `router` → `ViewWithHeader` → `ChatHeaderExpanded` → `useMessageFormatter` | `shared/composables/useMessageFormatter.js` |
| `axios` | **17.668 B** | `App.vue` → `widget/helpers/axios.js` | `widget/helpers/axios.js` |
| `dompurify` | **15.295 B** | plugin `VueDOMPurifyHTML` no entrypoint — **não dá para adiar**: a diretiva é usada no primeiro render | — |
| `@sentry/core` | **15.168 B** | `App.vue` → `useAvailability` → `dashboard/composables/useTransformKeys` (importa `@sentry/vue` só para reportar erro de camelCase) | `widget/composables/useAvailability.js` |
| `@chatwoot/utils` | **11.767 B** | `widget/store` → `shared/store/globalConfig.js` | `shared/store/globalConfig.js` |
| `@intlify/message-compiler` | **8.229 B** | mensagens JSON compiladas em runtime | precisaria de `@intlify/unplugin-vue-i18n` (não instalado) |
| `urlpattern-polyfill` | **2.182 B** | `store/modules/campaign` → `campaignHelper` | `widget/helpers/campaignHelper.js` |

**A conclusão que importa para o planejamento:** somando os seis itens que dependem só de
arquivo de aplicação (Sentry + date-fns + markdown + axios + `@chatwoot/utils` + urlpattern)
dá **≈ 127,9 KB gzip**, o que levaria o grafo a **≈ 161,7 KB** — **ainda acima dos 150 KB**.
As três frentes nomeadas no plano **não alcançam o aceite do próprio bloco**: para fechar
150 KB é preciso, além delas, ou o `dompurify` sair do first-paint, ou a pré-compilação das
mensagens do `vue-i18n`, ou o **facade do bloco 6.04** — que o plano corretamente prende a
este bloco, mas que agora se vê ser **necessário**, não opcional, para o número.

**`sdk.js` cru:** faltam **2.982 B** e há um item que sozinho resolve — o pacote `md5` é
CommonJS e arrasta `crypt` + `charenc` + `is-buffer`; medido com alias de stub em build real,
vale **5.753 B crus** (45.229 → 39.476, ou seja, **abaixo do teto**). Trocar por um MD5 em
ESM com digest **idêntico** (o cookie de dedupe não muda) exige editar
`app/javascript/sdk/cookieHelpers.js`, vizinho de `sdk/tracking/` e portanto de outra trilha.

---

## 6. Arquivos

**Alterados:** `vite.config.ts`, `vite.lib.config.ts`, `vitest.config.ts`,
`scripts/widget-size.mjs` (só a `GRAPH_BASELINE`, **para baixo**: 422.599 → 289.614, que é o
que a própria mensagem de sucesso do gate manda fazer — sem isso o emagrecimento poderia ser
devolvido em silêncio; **os `LIMITS` não foram tocados**), `app/javascript/entrypoints/widget.js`,
`app/javascript/widget/i18n/index.js`.

**Novos:** `vite.sdk-css.ts`, `vite.stats.ts`, `scripts/widget-eager.check.mjs`,
`app/javascript/widget/formkit.js`, e 4 arquivos de spec.

**Nada foi pushado, nenhum PR foi aberto, nenhuma VM e nenhum banco de produção foram
tocados.**

---

## 7. Duas armadilhas que custaram tempo, para o próximo não pagar de novo

1. **`bin/vite build` PULA o build em silêncio.** «Skipping vite build. Watched files have
   not changed since the last build» — sai com exit 0 e o manifest fica o do build anterior.
   Toda medição deste relatório usou `--force`. Sem ele, um "antes" e um "depois" podem ser
   o mesmo arquivo.
2. **`vite_ruby` varre `app/javascript/entrypoints/` RECURSIVAMENTE.** Um spec posto em
   `entrypoints/specs/` vira **entrypoint do build**; como ele importava `vite.sdk-css.ts`
   (que importa `vite`), o Rollup passou a puxar o próprio Rollup para o bundle da aplicação
   e o build morreu em `failed to resolve import "fsevents"`. Spec de configuração de build
   não mora em `entrypoints/`.
