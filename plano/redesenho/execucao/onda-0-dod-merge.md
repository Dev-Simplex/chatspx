# Onda 0 — Definition of Done NUMÉRICA do bloco 0.2 (merge da v4.16.2)

- **Worktree:** `/home/chatwoot/chatwoot-redesenho-merge`
- **Branch:** `redesenho-merge`
- **Baseline pré-merge (a régua):** `f26db6ee81`
- **Executor:** T2 (medição — NÃO corrige)
- **Aceite do bloco 0.2 (PLANO-MESTRE §2.2):** "`pnpm test` verde; widget abre; os 16 snapshots revisados um a um"

**Este documento foi medido em duas passagens, em HEADs diferentes:**

| Passagem | HEAD | O que foi medido |
|---|---|---|
| 1ª — 2026-08-17 | `93571c69db` (merge cru) | Itens **1 a 8**. O item 9 ficou **bloqueado** (§9.1) |
| 2ª — 2026-08-17, após o bloco 0.3 | `8684f07304` | Item **9**: os 16 snapshots, agora medíveis (§9) |

> Este documento é **medição**, não correção. Nenhum código de aplicação foi alterado, nada foi
> commitado, e **`--update-snapshots` não foi usado em nenhuma execução** — os 16 PNG do baseline
> seguem byte-idênticos a `f26db6ee81`, verificado no início e no fim.

**Estado do worktree ao final:** só `M public/version.json` (reescrito pelo `bin/vite build`, passou
a refletir o HEAD correto). `public/vite/`, `public/packs/` e `test-results/` são artefatos de
execução — os dois primeiros estão no `.gitignore` (`:87` e `:79`) e os PNGs de evidência foram
guardados no scratchpad. O worktree temporário do baseline foi removido (`git worktree remove`).

Ficaram no PostgreSQL dois bancos de teste que criei, prontos para reuso por quem for corrigir:
**`chatwoot_test_merge_t2`** (schema do merge) e **`chatwoot_test_base_t2`** (schema do baseline).
Nenhum banco de desenvolvimento ou produção foi tocado, e o Puma da :3000 nunca foi tocado.

> ⚠️ **O worktree não esteve exclusivo em nenhuma das duas passagens.** Outros executores
> commitaram aqui (`6ad7a9ec6e`, `8684f07304`) e, na 2ª passagem, um arquivo meu não rastreado foi
> apagado no meio de um run. Os resultados abaixo foram colhidos em execuções limpas; a evidência
> foi movida para fora do worktree por isso.

---

## Veredito do bloco 0.2 — **os 3 aceites passam; o rspec continua vermelho**

> **Atualizado em 2026-08-17, após o bloco 0.3.** A primeira versão deste documento recusou o
> bloco porque o item 9 não podia sequer ser medido. O 0.3 corrigiu o `vite.config.ts`, a régua
> rodou, e o veredito dos **três aceites literais** mudou. O que **não** mudou são as regressões
> do §5b, que ficam fora da letra do aceite mas continuam de pé.

| Parte do aceite (PLANO-MESTRE §2.2) | Resultado |
|---|---|
| "`pnpm test` verde" | ✅ **4586 testes, 0 falhas** |
| "widget abre" | ✅ **ABRE** — SDK responde 200, harness serve, widget renderiza (§9) |
| "os 16 snapshots revisados um a um" | ✅ **16/16 comparados e passando** contra o baseline pré-merge (§9) |

**O que destravou:** o merge havia tomado o `vite.config.ts` do upstream por inteiro e descartado o
branch `isTestMode` do fork; sem ele o `vite-plugin-ruby` reescrevia o `root` para `app/javascript`
e o SDK dava 404 (§9.1). O bloco 0.3 (`8684f07304`) devolveu o branch **dentro** da estrutura nova
de 4 arquivos do upstream, e de quebra recuperou o `optimizeDeps` do canvas (§3.1), o
`dedupe: ['html2pdf.js']` (§3.3) e o `lord-icon` (§3.2). **Os três defeitos que eu havia apontado
na §3 estão corrigidos.**

**O que continua aberto — e não é pequeno:** o item 5b. As 219 falhas de rspec incluem duas
regressões reais do merge que o aceite literal do 0.2 não cobre, mas que a Onda 1 herda:
o `.joins(:messages)` × `has_many` instance-dependent (41 falhas) e a validação do OpenAI fazendo
HTTP síncrono (51 falhas, baseline tinha 0). Detalhe na §5b.

**Leitura honesta:** o bloco 0.2 cumpre o aceite que foi escrito para ele. Isso não é o mesmo que
"o merge está são" — é que o aceite do 0.2 mede o front do widget, e o front do widget está
intacto.

### Dívida antiga × regressão nova: rodei tudo que dava também no baseline

Nenhum gate vermelho foi reportado sem antes checar se ele já era vermelho antes do merge. Rodei
`rubocop`, `eslint` e 5 arquivos de spec no `f26db6ee81`, no mesmo ambiente:

| Gate | Baseline | Merge | Delta do merge |
|---|---:|---:|---|
| `rubocop` | 659 offenses (exit 1) | 674 (exit 1) | **+15** — 1 defeito real: `test?` duplicado (§4) |
| `eslint` | 741 problems / 103 errors (exit 1) | 786 / 103 errors (exit 1) | **+45 warnings, ±0 errors** (§2) |
| 5 specs mais afetados (169 exemplos) | 50 falhas | 110 falhas | **+60** (§5b) |

Isso muda a leitura de dois gates: **`eslint` e `rubocop` já falhavam antes**, e o que o merge
acrescentou é pequeno e cirúrgico. Já o **rspec não**: as 219 falhas contêm regressões reais.

### Os três defeitos de código que o merge criou

| # | Defeito | Onde | Evidência |
|---|---|---|---|
| 1 | `root` do Vite reescrito sob `TEST=true` → SDK 404 → **os 16 snapshots inverificáveis** | `vite.config.ts` | §9, §9.1 |
| 2 | `.joins(:messages)` do upstream × `has_many` instance-dependent do fork → `ArgumentError` nos contadores de não lidas | `unread_counts/filtered_counter.rb:182` × `conversation.rb:168` | §5b — 41 falhas |
| 3 | Validação nova do upstream faz **HTTP síncrono para `api.openai.com` dentro de uma validação de ActiveRecord** | `integrations/openai/key_validator.rb` (arquivo novo) | §5b — 51 falhas, baseline tinha **0** |

Os três têm a mesma assinatura: **feature nova do upstream encostando em customização antiga do
fork, sem reconciliação**. É por isso que **o bloco 0.3 é pré-requisito do 0.2, não sucessor**.

Dois números que valem para as fases seguintes: o `pnpm size` passa medindo a casca do bundle
(real: **416 kB gzip** contra limite de 300 kB — §6) e a coluna `feature_flags` está **exatamente
no teto de 63 bits** (§8).

---

## Ambiente

| Item | Valor |
|---|---|
| node | v24.13.0 |
| pnpm | 10.2.0 |
| ruby | 3.4.4 (2025-05-14, +PRISM) |
| node_modules | presente (1123 pacotes no store `.pnpm`) |
| playwright browsers | chromium-1208/1217/1234, firefox-1509 (cache local OK) |
| harness widget (portas) | 3038 (sdk), 3999 (widget), 8899 (host) — **não usa a 3000** |
| banco de teste | **`chatwoot_test_merge_t2`** @ localhost — banco dedicado a esta medição (ver §5a) |

### Nota de segurança sobre o banco (verificado antes de tocar em qualquer coisa)

`config/database.yml` resolve o banco de **teste** por `ENV.fetch('POSTGRES_DATABASE', 'chatwoot_test')`.
Se este worktree tivesse um `.env` apontando para o banco de homologação, `db:test:prepare` teria
apagado o banco em uso. **Não tem** — só existe `.env.example`. Confirmado em runtime:

```
$ RAILS_ENV=test bin/rails runner "...connection_db_config..."
env=test db=chatwoot_test host=localhost user=postgres
```

*(essa foi a checagem inicial. O banco efetivamente usado passou a ser `chatwoot_test_merge_t2`
depois que a falta de credencial forçou um ajuste de ambiente — e aproveitei para isolar a
medição de outros executores. Ver §5a.)*

---

## Tabela-resumo (§10.4)

| # | Comando | Exit | Números | Veredito |
|---|---|---|---|---|
| 1 | `pnpm exec vitest --no-watch --no-cache` | **0** | **463 arquivos / 4586 testes — 4586 passed, 0 failed, 0 errors** (594s) | ✅ **PASSA** |
| 2 | `pnpm eslint` | **1** | **786 = 103 errors + 683 warnings**; baseline tinha **741 = 103 + 638** → **delta = +45 warnings, ±0 errors** | ❌ **FALHA, mas já falhava antes** — 0 errors novos (§2) |
| 3 | `bin/vite build` | **0** | **8 entradas, conjunto IDÊNTICO ao baseline**; 6591 módulos; 4m23s | ✅ **PASSA** (mas ver §3: 3 customizações SPX perdidas) |
| 3b | `pnpm run build:sdk` | **0** | `public/packs/js/sdk.js` 29.01 kB, **IIFE confirmado** | ✅ **PASSA** |
| 4a | `bundle install` | **0** | — | ✅ **PASSA** |
| 4b | `bundle exec rubocop` | **1** | 3531 arquivos, **674 offenses**; baseline tinha **659** → **delta do merge = +15** | ❌ **FALHA, mas já falhava antes** — 1 defeito real: método duplicado (§4) |
| 5a | `bin/rails db:test:prepare` (RAILS_ENV=test) | **1** → **0** | falha de ambiente (senha do PG); passa após prover credencial | ⚠️ **PASSA com ajuste de ambiente** (ver §5a) |
| 5b | `bundle exec rspec` (62 tocados + models + services) | **1** | **4774 examples, 219 failures, 41 pending** (49min15s — dentro do cap) | ❌ **FALHA** — 41 delas são incompatibilidade fork×upstream (§5b) |
| 6 | `pnpm size` | **0** | widget **27.89 kB**/300 kB; sdk **9.64 kB**/40 kB | ⚠️ **VERDE FALSO** — ver §6 |
| 7 | `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` | **0** | saída **vazia**, 257 migrations | ✅ **PASSA** |
| 8 | BOOT `RAILS_ENV=test` + flags | **0** | imprime `4.16.2`; **63 default + 14 ext_1 = 77** | ✅ **PASSA** |
| 9 | `pnpm exec playwright test --project=widget` | **0** | **20 passed / 0 failed** (6.7m) — **os 16 comparados contra o baseline pré-merge** | ✅ **PASSA** (§9). *Antes do bloco 0.3: **NÃO MEDIDO por bloqueio de build** — 404 no SDK impedia o harness de servir; nunca foi falha de snapshot (§9.1)* |

---

## §1 — Vitest ✅

```
$ pnpm exec vitest --no-watch --no-cache
 Test Files  463 passed (463)
      Tests  4586 passed (4586)
   Duration  594.38s
EXIT=0
```

Zero falhas, zero erros não tratados. **É o `pnpm test` do aceite do bloco 0.2, e ele está verde.**

---

## §2 — ESLint: 786 problemas, e **zero errors novos**

```
$ pnpm eslint                     # merge, 93571c69db
✖ 786 problems (103 errors, 683 warnings)
  62 errors and 11 warnings potentially fixable with the `--fix` option.
EXIT=1
```

Mesmo método da §4: rodei o **mesmo comando no baseline** `f26db6ee81` (worktree descartável no
scratchpad, com o `node_modules` deste worktree via symlink — legítimo porque `git diff … --
package.json` não mostra mudança de versão em eslint/prettier entre os dois commits).

| | Problems | Errors | Warnings | Exit |
|---|---:|---:|---:|---:|
| Baseline `f26db6ee81` | 741 | **103** | 638 | **1** |
| Merge `93571c69db` | 786 | **103** | 683 | **1** |
| **Delta do merge** | **+45** | **±0** | **+45** | — |

**A leitura que importa: o eslint também já falhava antes, e o merge não introduziu um único error
novo.** O total de errors é exatamente o mesmo, e não por coincidência de número — a composição
por regra quase não mexeu, e o saldo é zero:

| Regra (errors) | Base → Merge | |
|---|---|---|
| `prettier/prettier` | 59 → 62 | **+3** |
| `vue/no-undef-components` | 4 → 2 | −2 |
| `vue/no-unused-properties` | 5 → 4 | −1 |
| **saldo** | | **0** |

Os **+3 errors de `prettier/prettier`** são os únicos errors realmente atribuíveis ao merge, e são
puramente cosméticos — `--fix` resolve os três:

| Arquivo | Mensagem |
|---|---|
| `dashboard/components/widgets/ChannelItem.vue:85` | quebra de linha desnecessária em `props.channel.key === 'voice' && !!props.enabledFeatures.channel_voice` |
| `dashboard/helper/actionCable.js:426` | `Delete ⏎` (linha em branco sobrando no fim) |
| `…/reports/components/specs/ReportDrilldownCard.spec.js:48` | ternário precisa de parênteses e cabe em uma linha |

*(nota lateral: o `ChannelItem.vue` ainda referencia `enabledFeatures.channel_voice`, o que é
coerente com a decisão do merge de descartar a migration `drop_channel_voice` — o suporte a voice
continua de pé nos dois lados.)*

Os **+45 warnings** são dívida de i18n e template, não defeito: `@intlify/vue-i18n/no-dynamic-keys`
400 → 442 (+42) e `vue/no-root-v-if` 25 → 27 (+2), acompanhando os 758 arquivos `.js`/`.vue` que o
merge tocou.

> A decomposição por regra dos *warnings* é aproximada — mensagens de várias linhas escapam do
> parser. Os totais (741 / 786) vêm do sumário do próprio eslint e são exatos.

Onde a dívida se concentra (e o merge não tocou): as três piores telas somam 43 dos 103 errors —
`MessageTemplatesPage.vue` 17, `TemplateBuilder.vue` 15, `MigrationBanner.vue` 11.
## §3 — Build Vite: o bloco 0.3 apareceu (análise estática, pré-build)

O diff `f26db6ee81..93571c69db` mostra que o merge **tomou o `vite.config.ts` do upstream por
inteiro** (145 linhas → 17). O upstream 4.16.2 legitimamente refatorou a config em três arquivos
novos — e isso está OK:

| Arquivo | Status | Conteúdo |
|---|---|---|
| `vite.shared.ts` | **A** (novo, upstream) | `aliases` + `vueOptions` |
| `vite.lib.config.ts` | **A** (novo, upstream) | build do SDK |
| `vitest.config.ts` | **A** (novo, upstream) | config do vitest |

**Verificações que PASSARAM:**

- **SDK sai IIFE:** ✅ preservado. `vite.lib.config.ts` tem `formats: ['iife']`,
  `inlineDynamicImports: true`, `dir: 'public/packs'`, `entryFileNames → js/sdk.js`.
  E o pipeline continua ligado: `lib/tasks/build.rake:7` chama `pnpm run build:sdk`.
- **Aliases:** ✅ os 10 sobreviveram integralmente em `vite.shared.ts`
  (`vue, components, next, v3, dashboard, helpers, shared, survey, widget, assets`).

**Customizações SPX que o merge DESCARTOU** (nenhuma reapareceu em `vite.shared.ts` /
`vite.lib.config.ts` / `vitest.config.ts` — grep por padrão retornou vazio):

| # | Perdido | Ainda usado no código? | Impacto | Veredito |
|---|---|---|---|---|
| 3.1 | `optimizeDeps.include` de `@vue-flow/*` + `vue-shepherd` e `esbuildOptions.define ES_BUILD=false` | **SIM** — `.../automation/canvas/FlowCanvasView.vue`, `FlowNode.vue`, `FlowEdge.vue` | **dev-only**: sem isso o `vite dev` não substitui `process` no pré-bundle e o canvas lazy-loaded quebra com `process is not defined` (era exatamente o bug que o comentário no código documentava) | ❌ **REGRESSÃO NOSSA** |
| 3.2 | `isCustomElement` perdeu `lord-icon` (ficou só `ninja-keys`) | **SIM** — `components-next/icon/LordIconIcon.vue` | Vue passa a tratar `<lord-icon>` como componente não resolvido (warning no console + elemento não renderiza como custom element) | ❌ **REGRESSÃO NOSSA** |
| 3.3 | `resolve.dedupe: ['html2pdf.js']` | **SIM** — `dashboard/helper/ConversationPDFExporter.js` | risco de dupla instância de `html2pdf.js` no bundle | ⚠️ **REGRESSÃO NOSSA** (impacto a confirmar no build) |
| 3.4 | `build.rollupOptions.output.manualChunks: { leaflet: ['leaflet'] }` | **NÃO** — nenhum `import 'leaflet'` em `app/javascript` | chunk manual já apontava para dep morta; a perda é **inócua** | ✅ **perda aceitável** |

> Registrado, **não corrigido** — é escopo do bloco 0.3 (reconciliação do build).

### 3.5 — O build rodou: conjunto de entradas ✅

```
$ NODE_OPTIONS=--max-old-space-size=8192 bin/vite build
✓ 6591 modules transformed.
✓ built in 4m 23s
EXIT=0
```

Comparação do conjunto de entradas (`isEntry: true` no `.vite/manifest.json`) entre o manifest
recém-gerado e o manifest do baseline `f26db6ee81`
(`/home/chatwoot/chatwoot-redesenho-base/public/vite/.vite/manifest.json`):

```
$ diff entries-base.txt entries-merge.txt
>>> CONJUNTO IDENTICO <<<
```

As 8 entradas, iguais dos dois lados:
`dashboard.js`, `portal.js`, `sdk.js`, `superadmin.js`, `superadmin_pages.js`, `survey.js`,
`v3app.js`, `widget.js`.

**O conjunto de entradas NÃO mudou.** O que mudou foi a *organização* da config (§3.1–3.4).

**Observação — 8 warnings `css-syntax-error` no build:**
`.conversations-list [role=button]p a` (seletor inválido gerado a partir de
`_wa-skin.scss:345`, `[role='button'].cursor-pointer`). **Não é regressão do merge:** o mesmo
seletor quebrado já está no CSS do baseline
(`redesenho-base/public/vite/assets/dashboard-BZ5EcUHU.css`), e `_wa-skin.scss` não foi tocado
pelo merge (diff vazio). Dívida pré-existente do fork.

---

## §3b — SDK sai IIFE ✅ (verificado no artefato, não na config)

```
$ pnpm run build:sdk
public/packs/js/sdk.js  29.01 kB │ gzip: 9.66 kB
✓ built in 6.75s
EXIT=0

$ head -c 120 public/packs/js/sdk.js
(function(){"use strict";/*! js-cookie v3.0.5 | MIT */function B(e){for(var o=1;o<arguments.length;o++){var t=arguments[

$ grep -c '^import \|^export ' public/packs/js/sdk.js
0
```

Arquivo único, abre com `(function(){`, zero `import`/`export` ESM. **É IIFE.**

---

## §4 — Rubocop: 674 offenses, das quais **+15 são do merge**

```
$ bundle exec rubocop            # merge, 93571c69db
3531 files inspected, 674 offenses detected, 318 offenses autocorrectable
EXIT=1
```

Para saber o que é do merge e o que é dívida do fork, rodei o **mesmo comando no baseline**. Criei
um worktree descartável do `f26db6ee81` dentro do meu scratchpad (`git worktree add --detach`) —
não toquei no worktree de nenhum outro executor. As versões de lint são idênticas nos dois commits
(`git diff … -- package.json` não mostra mudança em eslint/prettier), então a comparação é justa.

| | Arquivos | Offenses | Autocorrigíveis | Exit |
|---|---:|---:|---:|---:|
| Baseline `f26db6ee81` | 3152 | **659** | 310 | **1** |
| Merge `93571c69db` | 3531 | **674** | 318 | **1** |
| **Delta do merge** | +379 | **+15** | +8 | — |

**A leitura que importa: o rubocop JÁ FALHAVA antes do merge.** Exit 1 dos dois lados, 659
offenses de dívida pré-existente do fork (concentrada em `scripts/spx/**` e `task/**`, scripts
operacionais nunca lintados). O merge não quebrou o lint Ruby; acrescentou 15 offenses a um gate
que já estava vermelho.

Delta por cop (o que subiu e o que caiu):

| Cop | Base → Merge | |
|---|---|---|
| `Metrics/CyclomaticComplexity` | 54 → 58 | +4 |
| `Metrics/ClassLength` | 8 → 11 | +3 |
| `Metrics/ModuleLength` | 1 → 3 | +2 |
| `Lint/DuplicateMethods` | 0 → 1 | **+1** 🔴 |
| `Layout/*` (5 cops distintos) | — | +5 |
| `Lint/RedundantCopDisableDirective`, `Rails/ActiveRecordCallbacksOrder`, `Style/GuardClause`, `Layout/LineLength` | — | +1 cada |
| `RSpec/AnyInstance` | 9 → 6 | −3 |
| `RSpec/VerifiedDoubles` | 3 → 2 | −1 |

A maioria é ruído de métrica (código do upstream é maior que o do fork nos mesmos arquivos). Mas
uma delas é um **defeito real de resolução de merge**:

### 🔴 `Lint/DuplicateMethods` — método duplicado em `custom_tool_policy.rb`

```
enterprise/app/policies/captain/custom_tool_policy.rb:26:3: W: Lint/DuplicateMethods:
  Method Captain::CustomToolPolicy#test? is defined at both
  enterprise/app/policies/captain/custom_tool_policy.rb:14 and :26.
```

Os dois lados adicionaram `test?` de forma independente, **em posições diferentes do arquivo**:

| Versão | Onde está `test?` |
|---|---|
| Baseline do fork `f26db6ee81` | linha 22, depois de `destroy?` |
| Upstream `v4.16.2` | linha 14, entre `create?` e `update?` |
| **Merge `93571c69db`** | **linhas 14 *e* 26 — os dois** |

Como as posições eram diferentes, o git não viu conflito e manteve ambos. Os corpos são idênticos
(`@account_user.administrator?`), então o **impacto funcional é nulo** — o segundo `def` apenas
redefine o primeiro com o mesmo código. Mas é a assinatura exata de merge aceito sem releitura, e é
o único defeito de código que a régua do Ruby revelou.

> Registrado, **não corrigido** (minha entrega é medição). Correção é de uma linha: apagar o
> `def test?` das linhas 26-28.
## §5 — Ruby specs

### 5a — `db:test:prepare` ⚠️ falhou por ambiente, resolvido

**Primeira execução — FALHOU:**

```
$ RAILS_ENV=test bin/rails db:test:prepare
ActiveRecord::ConnectionNotEstablished: connection to server at "127.0.0.1", port 5432
  failed: fe_sendauth: no password supplied
Tasks: TOP => db:test:load_schema => db:test:purge => db:check_protected_environments
EXIT=1
```

Causa: este worktree **não tem `.env`**, então caía no default `POSTGRES_USERNAME=postgres` /
senha vazia, e o PostgreSQL desta VM exige senha.

**Resolução de ambiente (permitida pela exceção da task; registrada aqui):**
peguei do `.env` do worktree principal **somente** `POSTGRES_PASSWORD` e `POSTGRES_USERNAME`
(`chatwoot`) — **não** o arquivo inteiro — e fixei o banco explicitamente.

Duas salvaguardas aplicadas:

1. O `.env` de homologação **não define `POSTGRES_DATABASE`** (homologação resolve pelo default do
   `RAILS_ENV`, isto é, `chatwoot_production`). Herdar o arquivo inteiro teria feito `db:test:purge`
   apontar para um banco real. Por isso `POSTGRES_DATABASE` foi **fixado à mão**, nunca herdado.
2. Como há outros executores nesta onda no mesmo PostgreSQL (existem `chatwoot_test_2..5`,
   `chatwoot_ci_followup`, `chatwoot_ci_fup_b`), **não** usei o `chatwoot_test` compartilhado.
   Criei um banco dedicado: **`chatwoot_test_merge_t2`**.

```
$ POSTGRES_DATABASE=chatwoot_test_merge_t2 RAILS_ENV=test bin/rails db:test:prepare
EXIT=0
```

Bancos no servidor (confirmando que o alvo é distinto dos reais): `chatwoot_production`,
`chatwoot_dev`, `chatwoot_test`, `chatwoot_test_2..5`, `chatwoot_ci_*`, `automacoes_f1_test`,
**`chatwoot_test_merge_t2`** ← o nosso. Nenhum banco de dev/produção foi tocado.

> **Nota de método:** a primeira execução foi registrada como ✅ por engano — a notificação de
> "exit 0" vinha do subshell que envolvia o comando, não do comando. O exit real está no `EXIT=`
> gravado no fim de cada log. Daqui em diante todos os exits desta tabela vêm do log, não da
> notificação.

### 5b — `bundle exec rspec`: 219 falhas em 4774 exemplos

```
$ bundle exec rspec <62 specs tocados> spec/models spec/services
Finished in 49 minutes 15 seconds (files took 24.4 seconds to load)
4774 examples, 219 failures, 41 pending
EXIT=1
```

Terminou **dentro** do cap de 60 min — nada foi cortado. As 219 falhas caem em 37 arquivos e cinco
padrões:

| # | Padrão | Falhas | Natureza |
|---|---|---:|---|
| 1 | `WebMock::NetConnectNotAllowedError` → `https://api.openai.com` | **51** | 🔴 **regressão do merge** (baseline: **0**) |
| 2 | `ArgumentError: association scope 'messages' is instance dependent` | **41** | 🔴 **incompatibilidade fork × upstream criada pelo merge** |
| 3 | `RecordInvalid: Status cannot be Pending — feature disabled for this inbox` | 33 | validação do fork vs. specs |
| 4 | `ArgumentError: wrong number of arguments (given 2, expected 3)` | 4 | assinatura |
| 5 | `InvalidForeignKey` / `PG::ForeignKeyViolation` | 3 | FK sem cascade |
| — | demais | 87 | variado |

#### Delta certificado: 5 specs rodados também no baseline

Para não classificar por palpite, rodei os 5 arquivos que concentram mais falhas **também no
`f26db6ee81`** (worktree descartável, banco próprio `chatwoot_test_base_t2`, mesmo ambiente e
mesma ausência de `.env`):

| Spec | Baseline | Merge | Delta |
|---|---:|---:|---:|
| `enterprise/…/captain/documents_controller_spec.rb` | 1 | 33 | **+32** 🔴 |
| `enterprise/services/captain/copilot/chat_service_spec.rb` | 0 | 18 | **+18** 🔴 |
| `controllers/…/conversations_controller_spec.rb` | 10 | 16 | **+6** |
| `services/conversations/filter_service_spec.rb` | 25 | 29 | **+4** |
| `services/spx/ai_config/change_set_applier_spec.rb` | **14** | **14** | **0** — dívida nossa, pré-existente |
| **Total (169 exemplos)** | **50** | **110** | **+60** |

> Isso cobre 110 das 219 falhas. Não extrapolo para as outras 109 — não as medi no baseline.

#### 🔴 Padrão 1 — 51 × OpenAI: era ambiente? **Não.** O baseline prova que não

Minha primeira hipótese foi ambiente (worktree sem `.env`, sem chave). **O run no baseline
derrubou essa hipótese**: mesmo ambiente, mesma ausência de `.env`, e o baseline teve **0**
`NetConnectNotAllowedError`. As 51 são do merge.

A origem é código novo do upstream. `lib/integrations/openai/key_validator.rb` **não existe** em
`f26db6ee81`, e `app/models/integrations/hook.rb` ganhou +70 linhas, entre elas:

```ruby
validate :validate_openai_api_key, if: :validate_openai_api_key?
```

O validador faz uma requisição HTTP **de dentro de uma validação de ActiveRecord**:

```ruby
def self.valid?(api_key)
  connection = Faraday.new { |f| f.options.timeout = TIMEOUT_SECONDS }   # 5s
  response = connection.get("#{api_base}/models") do |req|
    req.headers['Authorization'] = "Bearer #{api_key}"
  end
  response.status != 401
end
```

Nos testes, o WebMock bloqueia e 51 exemplos morrem. **Fora dos testes o efeito é outro e pior:**
salvar um `Integrations::Hook` do OpenAI passa a fazer uma chamada síncrona de até 5s para
`api.openai.com` dentro do ciclo de validação. Vale conferir esse comportamento antes de levar
para a frota — sobretudo porque o fallback do `rescue` é `true` (erro de rede ⇒ chave considerada
válida).

#### 🔴 Padrão 2 — `.joins(:messages)` do upstream × `has_many` instance-dependent do fork

41 falhas com a mesma exceção. Os dois lados:

**Fork** — `app/models/conversation.rb:168` declara a associação com scope *instance-dependent*
(o lambda recebe a conversa), para o `team_message_isolation`:

```ruby
has_many :messages, lambda { |conversation|
  if conversation.team_id.nil? || !conversation.inbox&.team_message_isolation
    all
  else
    where('messages.team_id IS NULL OR messages.team_id = ?', conversation.team_id)
  end
}, dependent: :destroy_async, autosave: true
```

**Já existia no baseline** — `git show f26db6ee81:app/models/conversation.rb` traz o mesmo lambda,
comentários inclusive.

**Upstream** — `app/services/conversations/unread_counts/filtered_counter.rb` é **arquivo novo**:

```
$ git log --oneline -1 --diff-filter=A -- app/services/conversations/unread_counts/filtered_counter.rb
66cfb26c77 feat: Add unread count filters feature flag (1/6) (#14885)
```

e na linha 182 faz exatamente o que o scope instance-dependent proíbe:

```ruby
.joins(:messages)
.where(messages: { account_id: account.id })
```

O Rails não monta JOIN de associação cujo scope depende da instância → `ArgumentError` em runtime.

**Nenhum dos dois lados está errado isoladamente — o defeito nasceu do merge**, que juntou a
feature nova do upstream com a customização antiga do fork sem reconciliá-las. Onde bate:

| Spec | Falhas |
|---|---:|
| `unread_counts/filtered_counter_spec.rb` | 21 |
| `unread_counts/refresher_spec.rb` | 9 |
| `unread_counts/counter_spec.rb` | 6 |
| `unread_counts/builder_spec.rb` | 3 |
| outros | 2 |

**Não é só teste vermelho:** o caminho quebrado é o dos contadores de não lidas. A feature está
atrás da flag `unread_count_filters` — com a flag ligada, o `ArgumentError` sobe do serviço em
produção, não do spec.

#### Padrão 3 — 33 × `Status cannot be Pending — feature disabled for this inbox`

A validação é do fork e **já existia no baseline** (a mensagem está em
`f26db6ee81:app/models/conversation.rb` e em `config/locales/en.yml`). 29 das 33 estão em
`filter_service_spec.rb` — que no baseline já tinha 25 falhas. Ou seja: majoritariamente
pré-existente, com **+4** atribuíveis ao merge.

#### Padrão 4 — 4 × aridade, todos ancorados em `spec/rails_helper.rb:47`

```ruby
allow_any_instance_of(Conversation).to receive(:team_required_for_resolution).and_return(nil)
```

Stub global do fork sobre um método cuja assinatura passou a esperar 3 argumentos.

#### Padrão 5 — 3 × FK sem cascade

`ActiveRecord::InvalidForeignKey` / `PG::ForeignKeyViolation` ao destruir registros — mesmo formato
do problema conhecido de `flow_runs`/`flow_step_logs` bloqueando `conversation.destroy!`.

#### Dívida que **não** é do merge

`spec/services/spx/ai_config/change_set_applier_spec.rb` falha **14 vezes nos dois commits**. É
código SPX nosso, quebrado antes do merge — deve ser tratado, mas não conta contra o bloco 0.2.

---

## §6 — `pnpm size`: passa, e é falso verde — com o número que prova

```
$ pnpm size
  public/vite/assets/widget-B4nz3W4i.js   Size limit: 300 kB   Size: 27.89 kB gzipped
  public/packs/js/sdk.js                  Size limit:  40 kB   Size:  9.64 kB gzipped
EXIT=0
```

**Linha de base do bloco 0.5 — por que o verde não vale nada.** A config
(`.size-limit.json`) aponta para o glob `public/vite/assets/widget-*.js`, que casa com **um único
chunk**: o de entrada. Percorrendo o grafo de imports do `entrypoints/widget.js` no
`.vite/manifest.json`:

| O que se mede | Chunks | Bruto | Gzip |
|---|---:|---:|---:|
| **O que o `size-limit` mede hoje** | 1 | 94.2 kB | **27.89 kB** |
| **First-paint real** (entry + imports estáticos) | 15 | 1265.3 kB | **416.28 kB** |
| Alcançável incl. `dynamicImports` (lazy) | 320 | 23218.8 kB | — |

O limite declarado é **300 kB gzip**. O first-paint real é **416.28 kB gzip** — **38,8% acima do
limite**. O gate passa porque mede a casca (o chunk de entrada), não o payload. O número honesto
para o bloco 0.5 partir é **416.28 kB**, não 27.89 kB.

O `sdk.js` é medido corretamente (arquivo único, IIFE, sem code-splitting): **9.64 kB / 40 kB** é
um verde real.

## §7 — Colisão de timestamp de migration ✅

```
$ ls db/migrate | cut -d_ -f1 | sort | uniq -d
(vazio)
EXIT=0
```
257 migrations, **zero timestamps duplicados**. Não trava `db:migrate` na frota.

## §8 — Boot em `RAILS_ENV=test` ✅

```
$ RAILS_ENV=test bin/rails runner "puts Chatwoot.config[:version] rescue puts 'BOOT FAIL'"
4.16.2
EXIT=0
```

O app **sobe** — nenhum `ArgumentError` do `Featurable`. Contagem de flags confirmada em runtime
(não por grep), lendo `config/features.yml` dentro do Rails:

```
feature_flags:       63
feature_flags_ext_1: 14
TOTAL:               77
FEATURE_FLAG_COLUMNS: ["feature_flags", "feature_flags_ext_1"]
Account.flag_mapping keys: ["feature_flags", "feature_flags_ext_1"]
```

**Confirma a triagem do coordenador: 63/63 na coluna default (no limite, 0 slots livres) + 14 em
`ext_1`.** A coluna default está *exatamente* no teto de 63 bits — qualquer flag nova que não
declare `column: feature_flags_ext_1` estoura o boot.

## §9 — Os 16 snapshots, revisados um a um ✅

> **Medido em `8684f07304`** (`build(0.3): reconcilia o vite do upstream e devolve o caminho de
> teste`), depois que o bloco 0.3 corrigiu o bloqueio diagnosticado na §9.1. Antes disso o item 9
> não era "falha de snapshot" — era **NÃO MEDIDO por bloqueio de build**. São coisas diferentes, e
> a distinção importa: um baseline nunca foi contestado.

### O bloqueio morreu — verificado antes de rodar

O fix devolveu o branch `isTestMode` **dentro** da estrutura de 4 arquivos do upstream (a
refatoração dele ficou intacta), e de quebra recuperou duas das customizações que eu havia
apontado na §3: o `optimizeDeps` do canvas (§3.1) e o `dedupe: ['html2pdf.js']` (§3.3). O
`lord-icon` (§3.2) voltou em `vite.shared.ts`.

Confirmei o efeito antes de gastar um run — e a prova é a **inversão** das duas URLs:

| URL | Antes (§9.1) | Agora |
|---|---|---|
| `/app/javascript/entrypoints/sdk.js` (o que o harness pede) | 404 🔴 | **200** ✅ |
| `/entrypoints/sdk.js` | 200 | **404** ✅ |

```
$ TEST=true node --input-type=module -e "…resolveConfig…"
ROOT (TEST=true) = /home/chatwoot/chatwoot-redesenho-merge      ← era .../app/javascript
plugin ruby      = (nenhum)                                     ← era vite-plugin-ruby
```

E a régua estava íntegra na largada: os **16 PNG byte-idênticos ao `f26db6ee81`** (comparados um a
um contra o objeto do git, não contra outro worktree).

### O resultado

```
$ pnpm exec playwright test --project=widget
  20 passed (6.7m)
EXIT=0
```

**16/16 cenários passaram, mais os 4 testes de contrato.** E cada cenário não valida só o pixel —
valida quatro coisas, todas contra o baseline pré-merge:

1. `toHaveScreenshot` contra o PNG de `f26db6ee81`;
2. contagem axe `critical`/`serious` **exata**;
3. contraste do texto âncora com `toBeCloseTo(baseline, 2)` — 2 casas decimais;
4. geometria em valores exatos (`holderWidth` 400 no desktop; no unread `gap` 4 e 316/300 no mobile).

### Os 16, um a um

| # | Cenário | Resultado | Tempo | Diff | Veredito |
|---|---|---|---|---|---|
| 1 | `home-light-desktop` | ✅ passou | 12.2s | nenhum | idêntico ao baseline |
| 2 | `home-light-mobile` | ✅ passou | 6.7s | nenhum | idêntico ao baseline |
| 3 | `home-dark-desktop` | ✅ passou | 7.6s | nenhum | idêntico ao baseline |
| 4 | `home-dark-mobile` | ✅ passou | 6.3s | nenhum | idêntico ao baseline |
| 5 | `messages-light-desktop` | ✅ passou | 6.6s | nenhum | idêntico ao baseline |
| 6 | `messages-light-mobile` | ✅ passou | 7.2s | nenhum | idêntico ao baseline |
| 7 | `messages-dark-desktop` | ✅ passou | 6.9s | nenhum | idêntico ao baseline |
| 8 | `messages-dark-mobile` | ✅ passou | 8.0s | nenhum | idêntico ao baseline |
| 9 | `prechat-form-light-desktop` | ✅ passou | 6.7s | nenhum | idêntico ao baseline |
| 10 | `prechat-form-light-mobile` | ✅ passou | 6.5s | nenhum | idêntico ao baseline |
| 11 | `prechat-form-dark-desktop` | ✅ passou | 6.4s | nenhum | idêntico ao baseline |
| 12 | `prechat-form-dark-mobile` | ✅ passou | 6.6s | nenhum | idêntico ao baseline |
| 13 | `unread-light-desktop` | ✅ passou | 5.9s | nenhum | idêntico ao baseline |
| 14 | `unread-light-mobile` | ✅ passou | 5.8s | nenhum | idêntico ao baseline |
| 15 | `unread-dark-desktop` | ✅ passou | 5.8s | nenhum | idêntico ao baseline |
| 16 | `unread-dark-mobile` | ✅ passou | 5.8s | nenhum | idêntico ao baseline |

Nenhum falhou, então **não há uma única imagem `-diff` para abrir**. Isso não me deixa satisfeito
como resposta, pelo motivo da próxima seção.

### Verificação extra: o "passou" é zero diferença, ou é a folga absorvendo?

Os 16 passarem não me bastou como resposta, por um motivo concreto: o aceite oficial usa
`maxDiffPixelRatio: 0.01` e `threshold` padrão (0.2). Num quadro de 390×844 isso são **~3.300
pixels** que podem mudar sem que nada acuse — e o merge **mexeu no `App.vue`** de verdade:

```
$ git diff f26db6ee81..HEAD -- app/javascript/widget/App.vue
+    isUnreadOrCampaignView() {
+      return ['unread-messages', 'campaigns'].includes(this.$route.name);
+    },
...
+      'bg-n-slate-2 dark:bg-n-solid-1': !isUnreadOrCampaignView,
```

E a classe **pinta de verdade** neste contexto: `theme/colors.js:105` define
`n.slate.2 = rgb(var(--slate-2))`, e `--slate-2` está declarada no próprio
`widget/assets/scss/woot.scss` (light `249 249 251` = `#F9F9FB`; dark `--solid-1: 23 23 26` =
`#17171A`). Não é uma classe morta.

Então rodei de novo com a tolerância **zerada** (`maxDiffPixels: 0`, `threshold: 0`) — isso
**endurece** o aceite, não afrouxa; o aceite oficial continua sendo o `playwright.config.js` do
repositório, que já passou 20/20.

```
$ pnpm exec playwright test --config=<scratchpad>/strict.config.js --project=widget
  14 passed / 6 failed (6.3m)
```

| Cenário | Tolerância zero | Pixels diferentes |
|---|---|---:|
| `messages-*` (4 cenários) | ✅ **idêntico** | **0** |
| `unread-*` (4 cenários) | ✅ **idêntico** | **0** |
| `home-light-desktop`, `home-dark-desktop` | ✅ **idêntico** | **0** |
| `home-light-mobile` | difere | 5257 (2%) |
| `home-dark-mobile` | difere | 5001 (2%) |
| `prechat-form-light-desktop` | difere | 6495 (3%) |
| `prechat-form-light-mobile` | difere | 7161 (3%) |
| `prechat-form-dark-desktop` | difere | 6106 (3%) |
| `prechat-form-dark-mobile` | difere | 6469 (2%) |

**10 dos 16 são pixel-a-pixel idênticos ao baseline pré-merge.** Os outros 6 divergem — e é
justamente por causa deles que valeu a pena não parar no verde.

> Nota metodológica: os ratios de 2-3% são **maiores** que o `maxDiffPixelRatio: 0.01` oficial e
> mesmo assim o run oficial passou. Não é contradição: no run oficial o `threshold` é 0.2, então
> pixels com diferença sutil não entram na conta; no meu run estrito o `threshold` é 0, e **toda**
> diferença conta, inclusive a de anti-aliasing. O que decide o veredito é a **magnitude** dessas
> diferenças — medida abaixo.

### O que os 6 diffs mostram — abertos e lidos, um a um

Rodei os 6 divergentes de novo, salvando os PNGs fora do worktree. Primeiro fato, e ele já
decide muita coisa:

**A divergência é flaky.** Entre a primeira e a segunda execução com tolerância zero, três
cenários **trocaram de lado**:

| Cenário | 1ª execução | 2ª execução |
|---|---|---|
| `home-light-mobile` | ✘ 5257 px | ✅ **0 px** |
| `prechat-form-light-desktop` | ✘ 6495 px | ✅ **0 px** |
| `prechat-form-dark-desktop` | ✘ 6106 px | ✅ **0 px** |
| `home-dark-mobile` | ✘ 5001 px | ✘ 5001 px (idêntico) |
| `prechat-form-light-mobile` | ✘ 7161 px | ✘ 7161 px (idêntico) |
| `prechat-form-dark-mobile` | ✘ 6469 px | ✘ 6469 px (idêntico) |

Uma mudança introduzida pelo merge **não alterna** entre execuções: ou está lá ou não está. O que
alterna é ruído de rasterização.

**Segundo fato: o fundo — o suspeito número um — é idêntico.** O `App.vue` passou a pintar o
container raiz com `dark:bg-n-solid-1`. Amostrei o fundo do `home-dark-mobile` em cinco pontos,
nas duas imagens:

| Ponto | Baseline (`expected`) | Pós-merge (`actual`) | Delta |
|---|---|---|---|
| (195,300) | `#17171A` | `#17171A` | (0,0,0) |
| (195,450) | `#17171A` | `#17171A` | (0,0,0) |
| (50,600) | `#17171A` | `#17171A` | (0,0,0) |
| (340,250) | `#17171A` | `#17171A` | (0,0,0) |
| (195,200) | `#17171A` | `#17171A` | (0,0,0) |

**O fundo já era `#17171A` antes do merge.** A classe nova pinta o container com exatamente a cor
que ele já herdava — efeito visual zero. É por isso que a mudança do `App.vue`, que é real no
código, não aparece no pixel.

**Terceiro fato: onde as diferenças estão.** Mapeando os pixels com delta > 32 por faixa vertical:

| Cenário | Faixas Y | O que existe nessas faixas |
|---|---|---|
| `home-dark-mobile` | 68-92, 106-124, 133-147, 680-692, 706-723, 732-747, 768-782 | título "Como podemos ajudar?", subtítulo, e os textos do card "Estamos conectados / Normalmente responde / Continuar conversa" |
| `prechat-form-light-mobile` | 20-61, 109-125, 158-169, 242-253, 327-340, 431-456 | header "Equipe Simplex", "Conte um pouco sobre você.", labels `Full Name` / `Email` / `Mensagem`, botão "Iniciar Conversa" |

**Todas as faixas são linhas de texto. Nenhuma é área de fundo.** O delta máximo por canal é
**87 de 255**, e **nenhum** pixel passa de 96 — o perfil de uma borda de glifo re-rasterizada, não
de uma superfície repintada.

E é o que se vê nas imagens: o `-diff.png` desenha o contorno das letras e das bordas dos campos, e
deixa o miolo das áreas grandes em branco (sem diferença). Comparando `expected` e `actual` lado a
lado, o `prechat-form-light-mobile` é indistinguível a olho: mesmo layout, mesmas cores, mesmas
posições, mesmo texto.

### Os 16, um a um — o veredito de cada

Formato: resultado no aceite oficial · diferença sob tolerância zero · o que mudou visualmente.

| # | Cenário | Aceite oficial | Tolerância zero | O que mudou visualmente | Veredito |
|---|---|---|---|---|---|
| 1 | `home-light-desktop` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 2 | `home-light-mobile` | ✅ passou | 0 px / 5257 px (**flaky**) | contornos do título e do card de status; fundo idêntico | ✅ ruído de rasterização |
| 3 | `home-dark-desktop` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 4 | `home-dark-mobile` | ✅ passou | 5001 px (estável) | contornos de texto do título/subtítulo e do card; fundo `#17171A` **igual** nos dois | ✅ ruído de rasterização |
| 5 | `messages-light-desktop` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 6 | `messages-light-mobile` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 7 | `messages-dark-desktop` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 8 | `messages-dark-mobile` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 9 | `prechat-form-light-desktop` | ✅ passou | 0 px / 6495 px (**flaky**) | contornos de labels e do botão | ✅ ruído de rasterização |
| 10 | `prechat-form-light-mobile` | ✅ passou | 7161 px (estável) | contornos do header, labels e botão; fundo e layout idênticos | ✅ ruído de rasterização |
| 11 | `prechat-form-dark-desktop` | ✅ passou | 0 px / 6106 px (**flaky**) | contornos de labels e do botão | ✅ ruído de rasterização |
| 12 | `prechat-form-dark-mobile` | ✅ passou | 6469 px (estável) | contornos de texto do formulário | ✅ ruído de rasterização |
| 13 | `unread-light-desktop` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 14 | `unread-light-mobile` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 15 | `unread-dark-desktop` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |
| 16 | `unread-dark-mobile` | ✅ passou | **0 px** | nada — pixel a pixel idêntico | ✅ sem mudança |

**10 dos 16 são idênticos ao baseline até o último pixel.** Os 6 restantes divergem só em contorno
de glifo, metade deles de forma não reprodutível. **Nenhum é regressão nossa, e nenhum é sequer
mudança do upstream que tenha chegado à tela.**

Os `unread-*` merecem uma nota: eles são os 4 que o upstream **excluiu de propósito** da mudança
(`App.vue:69-71`, `isUnreadOrCampaignView`), porque são os balões flutuantes sobre a página do
cliente. Deram **0 px** nos quatro — o que é exatamente o esperado e confirma que a exclusão
funciona.

### As duas mudanças do upstream que eu fui conferir no pixel

| Mudança | Existe no código? | Chegou ao pixel? |
|---|---|---|
| `App.vue` — container raiz ganha `bg-n-slate-2 dark:bg-n-solid-1` | **Sim**, confirmado no diff (+4 linhas). E a classe é viva: `theme/colors.js:105` mapeia `n.slate.2 → rgb(var(--slate-2))`, e `--slate-2` está declarada em `widget/assets/scss/woot.scss` | **Não.** A cor pintada é a mesma que o elemento já herdava (`#17171A` no dark, medido nos dois lados). Torna explícito o que era implícito |
| `ArticleViewer.vue` — `bg-white` → `bg-n-solid-1` | **Sim**, confirmado (`-  <div class="bg-white h-full">` / `+  <div class="bg-n-solid-1 h-full">`) | **Fora da matriz.** As 4 views testadas são `home`, `messages`, `prechat-form`, `unread`; o visor do help center não é uma delas. **Não foi medido — e não posso afirmar nada sobre ele** |

A segunda linha é uma lacuna de cobertura, não um resultado: se essa tela importa para as Ondas 1-6,
ela precisa de um 17º cenário. Registro como pendência, não como aprovação.

### As duas perguntas, uma frase cada

**1. Os 16 rodaram?**
**Sim** — o harness serviu, o widget renderizou e houve comparação de pixel de verdade contra o
baseline pré-merge nos 16 cenários (`20 passed`, `EXIT=0`, 6.7 min), com os PNGs de `f26db6ee81`
verificados byte-a-byte antes e depois do run e `--update-snapshots` jamais usado.

**2. O merge muda o widget de forma aceitável?**
**O merge não muda o widget** — 10 dos 16 são idênticos até o último pixel e os outros 6 divergem
apenas em contorno de glifo (delta máximo 87/255, metade não reprodutível entre execuções), com
fundo, layout, cores e texto medidos como iguais; **portanto nenhum dos 16 precisa de baseline
re-aprovado, e o baseline do bloco 0.1 continua válido como régua das Ondas 1 a 6, exatamente como
está.**

### O que eu NÃO posso afirmar

- **`ArticleViewer` (help center) não foi medido.** A mudança `bg-white → bg-n-solid-1` é real no
  código, mas a matriz cobre `home`, `messages`, `prechat-form` e `unread` — o visor de artigo não
  é nenhuma delas. Se essa tela importa para as ondas seguintes, ela precisa de um cenário próprio.
- **A tolerância oficial tem folga real.** `maxDiffPixelRatio: 0.01` com `threshold: 0.2` deixou
  passar sem acusar nada as diferenças de 2-3% que eu só enxerguei zerando a tolerância. Neste
  merge isso não escondeu nada — eu fui olhar e não havia nada. Mas a folga existe, e uma mudança
  visual pequena e localizada (um ícone, um badge) caberia dentro dela. Vale saber disso antes de
  confiar no verde das Ondas 1-6.
- **Os 6 divergentes são um sinal de instabilidade do harness**, não do merge: metade deles alterna
  entre 0 e ~6000 pixels de execução para execução, sempre em texto. Se as ondas seguintes forem
  medir mudanças visuais finas, esse ruído vira falso positivo.

### Higiene

- `--update-snapshots` **não foi usado em nenhuma das três execuções**; os 16 PNG do baseline
  seguem byte-idênticos a `f26db6ee81`, verificado no fim.
- O Puma da porta 3000 não foi tocado.
- Nenhum código de aplicação foi alterado. O único instrumento que criei (um config do Playwright
  com a tolerância **zerada** — que endurece o aceite, não afrouxa) vive no scratchpad, fora do
  worktree, e não altera a suíte.
- **Escrita concorrente no worktree:** durante esta medição apareceu `scripts/widget-size.mjs`
  (não é meu) e um arquivo meu não rastreado na raiz foi apagado no meio de um run — que morreu com
  `Cannot find module playwright.strict.config.js`. Por isso movi o instrumento e os artefatos para
  o scratchpad. O run oficial (o que vale) rodou antes disso, limpo. Fica o registro: **o worktree
  não estava exclusivo**, ao contrário do que a dispatch assumia.

---

## §9.1 — Histórico: o bloqueio que impedia a medição (RESOLVIDO no bloco 0.3)

> Esta seção é o registro de como o item 9 ficou bloqueado, e por quê. **O diagnóstico abaixo
> foi confirmado e o defeito foi corrigido** por `8684f07304` — ver §9. Fica aqui porque o
> mecanismo (plugin do upstream reescrevendo o `root` sob `TEST=true`) é a mesma classe de
> problema que a §3 descreve, e vai reaparecer no próximo merge de upstream.


Às 13:20:50, no meio desta medição, outro executor commitou neste worktree:

```
6ad7a9ec6e  fix(e2e): aquece o Vite antes do /__ready e encerra o harness de verdade
```

O commit é bom e ataca um defeito real do harness: o `/__ready` respondia 200 assim que a porta
abria, mas o Vite em `middlewareMode` compila SFC sob demanda sem persistir cache, então o primeiro
teste pagava sozinho ~44s de compilação contra um orçamento de ~45s e estourava de forma
intermitente. O fix aquece o grafo de módulos antes de anunciar prontidão e encerra o harness de
verdade (`closeAllConnections`). **Ele não toca em nenhum dos 16 PNG.**

**Mas ele não resolve o problema do bloco 0.2**, porque não toca a causa raiz:

```
$ git show --name-only 6ad7a9ec6e | grep -c 'vite.config.ts'
0
```

Re-medi as mesmas URLs contra o harness **já com o fix aplicado**, no HEAD `6ad7a9ec6e`:

| URL | Resposta |
|---|---|
| `/__ready` | **200** (agora um 200 honesto, depois do warmup) |
| `/app/javascript/entrypoints/sdk.js` | **404** 🔴 — igual a antes |
| `/entrypoints/sdk.js` | **200** |

E a prova direta, resolvendo a config do Vite exatamente como o harness a carrega
(`TEST=true`, `configFile: vite.config.ts`):

```
$ TEST=true node --input-type=module -e "…resolveConfig…"
ROOT resolvido = /home/chatwoot/chatwoot-redesenho-merge/app/javascript
BASE           = /vite-dev/
plugin ruby    = vite-plugin-ruby
```

O `root` **é** `app/javascript` e o `vite-plugin-ruby` **está** carregado, mesmo com `TEST=true` —
que era precisamente o que o branch `isTestMode` do fork evitava. Por isso
`/app/javascript/entrypoints/sdk.js` resolve para
`app/javascript/app/javascript/entrypoints/sdk.js`, que não existe → 404; e o caminho sem o prefixo
responde 200.

**Leitura para o coordenador:** são **dois** defeitos distintos no mesmo harness, e só um foi
corrigido.

| Defeito | Onde aparece | Status |
|---|---|---|
| Cold-start com `/__ready` mentiroso | `redesenho-base` **e** `redesenho-merge` | ✅ corrigido por `6ad7a9ec6e` |
| `root` do Vite reescrito sob `TEST=true` → 404 no SDK | **só** em `redesenho-merge` (o baseline ainda tem o `isTestMode`) | 🔴 **aberto** — depende do bloco 0.3 |

Faz sentido que o executor do 0.1 só tenha visto o primeiro: no worktree dele o `vite.config.ts`
ainda é o do fork, então lá o 404 não acontece. **O bloco 0.2 continua bloqueado.**
> intacto — é a prova que o bloco 0.1 produziu e que só ele pode substituir.

## §10 — Método, e o que eu NÃO fiz

### Como cada número foi obtido

Todo exit code desta tabela vem do `EXIT=$?` gravado no fim do log do próprio comando, **não** da
notificação do orquestrador. Isso não é preciosismo: no `db:test:prepare` a notificação reportou
exit 0 enquanto o comando havia falhado com exit 1 — o 0 era do subshell que envolvia o comando.
Registrei ✅ por engano e corrigi ao ler o log (§5a).

Para separar **dívida pré-existente** de **regressão do merge** nos dois gates de lint, rodei o
mesmo comando no baseline. Como o worktree `redesenho-base` é de outro executor e está fora do meu
alcance, criei um worktree descartável do `f26db6ee81` dentro do meu scratchpad:

```
git worktree add --detach <scratchpad>/base-probe f26db6ee81
ln -s <este-worktree>/node_modules <scratchpad>/base-probe/node_modules
```

O symlink de `node_modules` é legítimo aqui porque `git diff f26db6ee81..93571c69db -- package.json`
não mostra mudança de versão em eslint/prettier — as duas execuções usam exatamente o mesmo linter.
O worktree temporário é removido ao final.

### Restrições respeitadas

| Regra | Como foi cumprida |
|---|---|
| Não commitar | Nenhum commit. `git status` ao final: só `public/version.json` (reescrito pelo build) e `test-results/` (não rastreado) |
| Não corrigir código | Nenhuma linha de aplicação alterada, incluindo as regressões que encontrei (§3, §4) |
| Nunca tocar banco de dev/produção | Banco dedicado `chatwoot_test_merge_t2`; `POSTGRES_DATABASE` **fixado à mão**, nunca herdado do `.env` (que não define essa variável e resolveria para `chatwoot_production`) |
| Nunca matar o Puma da :3000 | Verificado durante e depois: pid 2213976 seguiu LISTEN o tempo todo |
| Não tocar no worktree `redesenho-base` | Nenhum processo dele foi encerrado, mesmo quando bloqueava minhas portas — esperei liberar |
| Nunca `--update-snapshots` | Não usado. Os 16 PNG seguem byte-idênticos ao `f26db6ee81` |
| Nunca afrouxar aceite | O harness tem portas fixas que o teste 17 valida como contrato; **não** as parametrizei para "fazer passar" |
| Protocolo de falha (2 tentativas) | `db:test:prepare` (2ª tentativa resolveu, §5a) e Playwright (run 1 contaminado → run 2 limpo → run 3 no HEAD novo, §9). Onde não resolvi, escalei em vez de improvisar |
| Não classificar por palpite | Todo gate vermelho foi rodado **também no baseline** antes de ser chamado de regressão. Foi isso que derrubou minha própria hipótese sobre as 51 falhas de OpenAI (§5b) |

### Ambiente que precisei resolver (única exceção permitida)

Uma só: a credencial do PostgreSQL. Este worktree não tem `.env`, então o default
(`postgres` / senha vazia) não conecta. Peguei **apenas** `POSTGRES_USERNAME` e `POSTGRES_PASSWORD`
do `.env` do worktree principal — nunca o arquivo inteiro — e fixei `POSTGRES_DATABASE` à mão.
Detalhe e justificativa na §5a.

### Como reproduzir

```bash
cd /home/chatwoot/chatwoot-redesenho-merge
export POSTGRES_USERNAME=chatwoot POSTGRES_PASSWORD=<do .env> \
       POSTGRES_DATABASE=chatwoot_test_merge_t2 RAILS_ENV=test

pnpm exec vitest --no-watch --no-cache          # §1
pnpm eslint                                     # §2
NODE_OPTIONS=--max-old-space-size=8192 bin/vite build   # §3
pnpm run build:sdk                              # §3b
bundle install && bundle exec rubocop           # §4
bin/rails db:test:prepare && bundle exec rspec <specs>  # §5
pnpm size                                       # §6
ls db/migrate | cut -d_ -f1 | sort | uniq -d    # §7
bin/rails runner "puts Chatwoot.config[:version]"       # §8
pnpm exec playwright test --project=widget      # §9  (exige as portas 3038/3999/8899 livres)
```
