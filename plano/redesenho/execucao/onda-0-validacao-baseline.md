# Onda 0 — Validação do baseline (blocos 0.1 + 0.11)

**Alvo:** commit `f26db6ee81` — `test(widget): capture Playwright baseline`
**Worktree:** `/home/chatwoot/chatwoot-redesenho-base` · **Branch:** `redesenho-base`
**Data da validação:** 2026-08-17
**Escopo:** PROVAR ou REFUTAR o commit com saída real de comando. Não reescrever o harness.
**Proibido nesta task:** `--update-snapshots`, alterar os 16 PNG, matar o Puma da :3000.

> Documento escrito incrementalmente conforme a validação avança.

---

## Tabela de veredito

| # | Item de aceite | Veredito | Estado no commit `f26db6ee81` como entregue |
|---|----------------|----------|---------------------------------------------|
| 1 | 16/16 snapshots passam sem `--update-snapshots` | ✅ **PASS** | ❌ FALHAVA (13/16 na 1ª execução) — corrigido |
| 2 | Estabilidade: duas rodadas seguidas 16/16 | ✅ **PASS** | ❌ FALHAVA (2ª rodada nem subia) — corrigido |
| 3 | Não-regressão: `copilot/` e `resolve-gate/` ainda descobertas | ✅ **PASS** | ✅ já passava |
| 4 | Fixture anti-erro falha alto (console.error + HTTP 500) | ✅ **PASS** | ✅ já passava |
| 5 | `grep "from '@playwright/test'" spec/e2e/widget/` vazio | ✅ **PASS** | ✅ já passava |
| 6 | Lista IGNORAR do fixture toda justificada | ✅ **PASS** (por inexistência da lista) | ✅ já passava |
| 7 | Dado dinâmico mascarado/congelado | ✅ **PASS** | ✅ já passava |
| 8 | 16 PNG + baseline.json commitados em `f26db6ee81` | ✅ **PASS** | ✅ já passava |

**Resumo:** o **baseline** (os 16 PNG e o `baseline.json`) é válido e foi confirmado. O que
estava quebrado era o **harness que o executa** — dois defeitos de infraestrutura, ambos
corrigidos com o mínimo de mudança, ambos documentados abaixo com a medição que os
identificou. Nenhum PNG foi regravado; nenhum aceite foi afrouxado.

---

## Ambiente da execução

```
$ node -v
v24.13.0
$ pnpm -v
10.2.0
$ pnpm exec playwright --version
Version 1.59.1
```

Portas em uso na VM antes de começar (armadilha conhecida da tentativa anterior):

```
$ ss -lntp | grep -E ':(3000|3038|3040|3999|4001|8899)\b'
LISTEN 0      1024         0.0.0.0:3000       0.0.0.0:*    users:(("ruby",pid=2213976,fd=8))
```

Só a **:3000 está ocupada** (Puma do ChatSPX de homologação — **não foi tocado**).
As portas que o harness usa (3038 SDK, 3999 widget, 8899 host, 3040/4001 HMR) estavam **todas livres**.
**Nenhuma porta precisou ser trocada**: o harness deste commit não usa a :3000.

---

## Item 8 — Os 16 PNG e o baseline.json estão commitados

**PASS.** `git show --stat f26db6ee81` (working tree limpo, HEAD = f26db6ee81):

```
commit f26db6ee81cec6660eb3f21ea3417d2155878585
Author: simplex <dev@simplexsolucoes.com.br>
Date:   Fri Aug 14 23:18:06 2026 +0000

    test(widget): capture Playwright baseline

 package.json                                       |   6 +-
 playwright.config.js                               |  53 +++-
 pnpm-lock.yaml                                     |  53 +++-
 spec/e2e/fixtures.js                               |  33 +++
 spec/e2e/widget/baseline.json                      |  93 ++++++
 spec/e2e/widget/fixture.sabotage.js                |  29 ++
 spec/e2e/widget/harness/host-server.mjs            |  84 ++++++
 spec/e2e/widget/harness/sdk-server.mjs             |  39 +++
 spec/e2e/widget/harness/widget-server.mjs          | 274 +++++++++++++++++
 spec/e2e/widget/sabotage.playwright.config.js      |  20 ++
 spec/e2e/widget/snapshots/home-dark-desktop.png    | Bin 0 -> 22535 bytes
 spec/e2e/widget/snapshots/home-dark-mobile.png     | Bin 0 -> 23998 bytes
 spec/e2e/widget/snapshots/home-light-desktop.png   | Bin 0 -> 22266 bytes
 spec/e2e/widget/snapshots/home-light-mobile.png    | Bin 0 -> 23788 bytes
 .../e2e/widget/snapshots/messages-dark-desktop.png | Bin 0 -> 145930 bytes
 spec/e2e/widget/snapshots/messages-dark-mobile.png | Bin 0 -> 225376 bytes
 .../widget/snapshots/messages-light-desktop.png    | Bin 0 -> 132973 bytes
 .../e2e/widget/snapshots/messages-light-mobile.png | Bin 0 -> 205745 bytes
 .../widget/snapshots/prechat-form-dark-desktop.png | Bin 0 -> 28868 bytes
 .../widget/snapshots/prechat-form-dark-mobile.png  | Bin 0 -> 30037 bytes
 .../snapshots/prechat-form-light-desktop.png       | Bin 0 -> 23453 bytes
 .../widget/snapshots/prechat-form-light-mobile.png | Bin 0 -> 29725 bytes
 spec/e2e/widget/snapshots/unread-dark-desktop.png  | Bin 0 -> 19690 bytes
 spec/e2e/widget/snapshots/unread-dark-mobile.png   | Bin 0 -> 19517 bytes
 spec/e2e/widget/snapshots/unread-light-desktop.png | Bin 0 -> 18306 bytes
 spec/e2e/widget/snapshots/unread-light-mobile.png  | Bin 0 -> 18381 bytes
 spec/e2e/widget/widget.spec.js                     | 329 +++++++++++++++++++++
 27 files changed, 996 insertions(+), 17 deletions(-)
```

Contagem: **16 PNG** (4 views × 2 temas × 2 viewports), `baseline.json`, `fixtures.js`,
`widget.spec.js`, os 3 servidores `.mjs`, o `fixture.sabotage.js` e o
`sabotage.playwright.config.js` — todos presentes no commit, todos como adição (`Bin 0 ->`).

> **Refutação do relatório anterior:** o commit **não foi revertido**. Ele é o HEAD da branch
> `redesenho-base`, o working tree está limpo, e os 27 arquivos estão no índice.

---

## Item 1 — 16/16 sem `--update-snapshots`

Comando executado (o projeto `widget` tem **20 testes**: os 16 cenários de snapshot da matriz
+ 4 testes de contrato do próprio harness):

```
$ pnpm exec playwright test --project=widget
```

### Rodada 1 — cache do Vite FRIO → **FALHA (17/20; 13/16 snapshots)**

```
Running 20 tests using 1 worker

  ✘   1 [widget] › widget.spec.js:151:7 › home-light-desktop (20.7s)
  ✘   2 [widget] › widget.spec.js:151:7 › home-light-mobile (35.2s)
  ✘   3 [widget] › widget.spec.js:151:7 › home-dark-desktop (13.6s)
  ✓   4 [widget] › widget.spec.js:151:7 › home-dark-mobile (26.3s)
  ✓   5 [widget] › widget.spec.js:151:7 › messages-light-desktop (6.5s)
  ✓   6 [widget] › widget.spec.js:151:7 › messages-light-mobile (8.2s)
  ✓   7 [widget] › widget.spec.js:151:7 › messages-dark-desktop (6.6s)
  ✓   8 [widget] › widget.spec.js:151:7 › messages-dark-mobile (7.1s)
  ✓   9 [widget] › widget.spec.js:151:7 › prechat-form-light-desktop (13.4s)
  ✓  10 [widget] › widget.spec.js:151:7 › prechat-form-light-mobile (8.3s)
  ✓  11 [widget] › widget.spec.js:151:7 › prechat-form-dark-desktop (6.3s)
  ✓  12 [widget] › widget.spec.js:151:7 › prechat-form-dark-mobile (7.0s)
  ✓  13 [widget] › widget.spec.js:151:7 › unread-light-desktop (11.9s)
  ✓  14 [widget] › widget.spec.js:151:7 › unread-light-mobile (5.8s)
  ✓  15 [widget] › widget.spec.js:151:7 › unread-dark-desktop (7.1s)
  ✓  16 [widget] › widget.spec.js:151:7 › unread-dark-mobile (5.5s)
  ✓  17 [widget] › widget.spec.js:222:1 › carrega SDK, entrypoint e host reais nas portas contratadas (2.9s)

  3 failed
    [widget] › widget.spec.js:151:7 › home-light-desktop
    [widget] › widget.spec.js:151:7 › home-light-mobile
    [widget] › widget.spec.js:151:7 › home-dark-desktop
  17 passed (3.8m)
EXIT_CODE=1
```

Texto das 3 falhas (nenhuma é diff de pixel — **as três morrem antes de chegar ao
`toHaveScreenshot`**):

```
  1) home-light-desktop
    TimeoutError: page.goto: Timeout 15000ms exceeded.
    Call log:
      - navigating to "http://127.0.0.1:8899/?scenario=home&theme=light", waiting until "domcontentloaded"
    > 85 |   await page.goto(`${HOST_URL}/?scenario=${view}&theme=${theme}`, {

  2) home-light-mobile
    Error: expect(received).toBe(expected) // Object.is equality
    Expected: true
    Received: false
    Call Log: - Timeout 30000ms exceeded while waiting on the predicate
    > 88 |   await expect
      89 |     .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {

  3) home-dark-desktop
    Error: expect(locator).toBeVisible() failed
    Locator: locator('#chatwoot_live_chat_widget').contentFrame()
             .getByText('Estamos conectados.', { exact: true })
    Expected: visible
    Timeout: 5000ms
    Error: element(s) not found
    > 134 |   await expect(anchor).toBeVisible();
```

### Rodada 2 — mesmo comando, cache do Vite já aquecido pela rodada 1 → **20/20**

```
Running 20 tests using 1 worker

  ✓   1 [widget] › widget.spec.js:151:7 › home-light-desktop (46.0s)
  ✓   2 [widget] › widget.spec.js:151:7 › home-light-mobile (15.3s)
  ✓   3 [widget] › widget.spec.js:151:7 › home-dark-desktop (6.5s)
  ✓   4 [widget] › widget.spec.js:151:7 › home-dark-mobile (6.5s)
  ✓   5 [widget] › widget.spec.js:151:7 › messages-light-desktop (8.0s)
  ✓   6 [widget] › widget.spec.js:151:7 › messages-light-mobile (7.3s)
  ✓   7 [widget] › widget.spec.js:151:7 › messages-dark-desktop (6.8s)
  ✓   8 [widget] › widget.spec.js:151:7 › messages-dark-mobile (6.7s)
  ✓   9 [widget] › widget.spec.js:151:7 › prechat-form-light-desktop (6.8s)
  ✓  10 [widget] › widget.spec.js:151:7 › prechat-form-light-mobile (6.8s)
  ✓  11 [widget] › widget.spec.js:151:7 › prechat-form-dark-desktop (7.0s)
  ✓  12 [widget] › widget.spec.js:151:7 › prechat-form-dark-mobile (6.2s)
  ✓  13 [widget] › widget.spec.js:151:7 › unread-light-desktop (6.0s)
  ✓  14 [widget] › widget.spec.js:151:7 › unread-light-mobile (6.1s)
  ✓  15 [widget] › widget.spec.js:151:7 › unread-dark-desktop (5.9s)
  ✓  16 [widget] › widget.spec.js:151:7 › unread-dark-mobile (6.9s)
  ✓  17 [widget] › widget.spec.js:222:1 › carrega SDK, entrypoint e host reais nas portas contratadas (2.7s)
  ✓  18 [widget] › widget.spec.js:255:1 › congela o relógio e alimenta o store determinístico (3.9s)
  ✓  19 [widget] › widget.spec.js:269:1 › preserva a geometria original do unread no resize real (3.1s)
  ✓  20 [widget] › widget.spec.js:300:1 › baseline descreve exatamente a matriz de 16 cenários (51ms)

  20 passed (3.0m)
EXIT_CODE=0
```

### Leitura das duas rodadas

Os **16 PNG commitados são válidos**: na rodada 2 os 16 `toHaveScreenshot` bateram contra os
arquivos do commit, sem `--update-snapshots`, com `maxDiffPixelRatio: 0.01`. Nenhuma falha em
nenhuma das duas rodadas foi diff de imagem.

O que quebra é o **cold-start do harness**: os `webServer` do `playwright.config.js` declaram
prontidão via `/__ready`, que responde 200 assim que a porta abre — **antes** de o Vite em
`middlewareMode` ter transformado qualquer módulo. O primeiro teste então paga sozinho a
otimização de deps (esbuild) + a transformação sob demanda de todo o grafo de SFCs do widget,
e estoura os limites do próprio teste (`navigationTimeout` 15s, poll de 30s, expect de 5s).
A partir do 4º teste o custo já foi pago e cada cenário cai para ~6s.

Isto é **defeito real do harness, não do baseline**: o gate `/__ready` mente sobre a
prontidão do servidor. Correção aplicada e reprovada na seção "Correção".

---

## Correção aplicada (defeito real do harness, não do baseline)

### Diagnóstico, medido

O `webServer` do Playwright considerava os servidores prontos assim que `/__ready`
respondia 200 — e ele respondia 200 no instante em que a porta abria. Só que os dois
servidores Vite rodam em `middlewareMode`, transformam SFC **sob demanda** e **não
persistem** esse cache em disco. Resultado: o primeiro teste da suíte pagava sozinho a
compilação do grafo inteiro do widget.

Medição do custo real que estava escondido dentro do primeiro teste:

| Rodada | cache `node_modules/.vite` | duração do 1º teste | duração dos demais |
|--------|---------------------------|---------------------|--------------------|
| 1 | frio | 20.7s → **falhou** (goto 15s) | ~6s |
| 2 | quente | 46.0s (passou raspando) | ~6s |
| controle (`-g home-light-desktop`) | frio (apagado à mão) | 43.8s (passou) | — |

O primeiro teste operava em ~45s contra um orçamento de ~45s (`navigationTimeout` 15s +
poll de 30s). Sob carga, estoura. É flakiness estrutural, não ruído.

Medição direta do warmup, subindo os dois servidores à mão com `node_modules/.vite` apagado:

```
$ rm -rf node_modules/.vite
$ node spec/e2e/widget/harness/sdk-server.mjs &
$ node spec/e2e/widget/harness/widget-server.mjs &
$ # polling de 1s em /__ready até HTTP 200
SDK pronto em 24s
WIDGET pronto em 214s
=== SDK=24s WIDGET=214s ===
```

### O que mudou (3 arquivos, nenhum deles de aplicação)

1. `spec/e2e/widget/harness/sdk-server.mjs` e `spec/e2e/widget/harness/widget-server.mjs`:
   `/__ready` passa a responder **503 `*-warming`** até o grafo de módulos do entrypoint
   ter sido transformado, e só então 200. O aquecimento é uma travessia recursiva do
   `moduleGraph` a partir de `/app/javascript/entrypoints/{sdk,widget}.js`.
   *(503 é deliberado: o Playwright trata 2xx/3xx/400/401/402/403 como "pronto" e segue
   esperando em 503 — o gate fica honesto.)*
2. `playwright.config.js`: `timeout` dos dois `webServer` com Vite de `120000` → `600000`.
   É **teto**, não custo: o boot termina quando o warmup termina (214s medidos). Os 120s
   originais estouravam o warmup e derrubavam a suíte com
   `Error: Timed out waiting 120000ms from config.webServer.`

**Nada foi afrouxado no teste.** Os limites de asserção (`navigationTimeout` 15s, polls de
30s, expect de 5s, `maxDiffPixelRatio` 0.01) estão **intocados** — o custo apenas saiu de
dentro do teste e foi para o boot do servidor, que é onde ele pertence.

### Prova de que a correção elimina a fragilidade em vez de mascará-la

O primeiro teste deixou de ser outlier — a assinatura do cold-start desapareceu:

| | 1º teste | faixa dos demais |
|---|---|---|
| antes (cache quente) | 46.0s | 5.5s – 15.3s |
| antes (cache frio) | 43.8s / falha | 5.5s – 35.2s |
| **depois (cache frio)** | **9.0s** | **5.1s – 6.9s** |

---

## Itens 1 e 2 — resultado após a correção

### Rodada green 1 — `node_modules/.vite` apagado (cache TOTALMENTE frio) → **20/20**

```
$ rm -rf node_modules/.vite
$ pnpm exec playwright test --project=widget

Running 20 tests using 1 worker

  ✓   1 [widget] › widget.spec.js:151:7 › home-light-desktop (9.0s)
  ✓   2 [widget] › widget.spec.js:151:7 › home-light-mobile (5.7s)
  ✓   3 [widget] › widget.spec.js:151:7 › home-dark-desktop (6.5s)
  ✓   4 [widget] › widget.spec.js:151:7 › home-dark-mobile (5.8s)
  ✓   5 [widget] › widget.spec.js:151:7 › messages-light-desktop (6.6s)
  ✓   6 [widget] › widget.spec.js:151:7 › messages-light-mobile (6.5s)
  ✓   7 [widget] › widget.spec.js:151:7 › messages-dark-desktop (6.7s)
  ✓   8 [widget] › widget.spec.js:151:7 › messages-dark-mobile (6.9s)
  ✓   9 [widget] › widget.spec.js:151:7 › prechat-form-light-desktop (6.2s)
  ✓  10 [widget] › widget.spec.js:151:7 › prechat-form-light-mobile (5.7s)
  ✓  11 [widget] › widget.spec.js:151:7 › prechat-form-dark-desktop (6.0s)
  ✓  12 [widget] › widget.spec.js:151:7 › prechat-form-dark-mobile (6.1s)
  ✓  13 [widget] › widget.spec.js:151:7 › unread-light-desktop (5.4s)
  ✓  14 [widget] › widget.spec.js:151:7 › unread-light-mobile (5.2s)
  ✓  15 [widget] › widget.spec.js:151:7 › unread-dark-desktop (5.1s)
  ✓  16 [widget] › widget.spec.js:151:7 › unread-dark-mobile (5.1s)
  ✓  17 [widget] › widget.spec.js:222:1 › carrega SDK, entrypoint e host reais nas portas contratadas (2.9s)
  ✓  18 [widget] › widget.spec.js:255:1 › congela o relógio e alimenta o store determinístico (3.8s)
  ✓  19 [widget] › widget.spec.js:269:1 › preserva a geometria original do unread no resize real (3.0s)
  ✓  20 [widget] › widget.spec.js:300:1 › baseline descreve exatamente a matriz de 16 cenários (43ms)

  20 passed (5.8m)
EXIT_CODE=0
```

**16/16 snapshots** batendo contra os PNG do commit `f26db6ee81`, sem `--update-snapshots`.

---

## Item 3 — Não-regressão: `copilot/` e `resolve-gate/` continuam descobertas

**PASS.** Os três projetos existem e nenhuma suíte foi excluída do config para o widget passar.

```
$ pnpm exec playwright test --list
Total: 80 tests in 17 files

$ pnpm exec playwright test --list --project=desktop-chromium
Total: 30 tests in 16 files
$ pnpm exec playwright test --list --project=mobile-chromium
Total: 30 tests in 16 files
$ pnpm exec playwright test --list --project=widget
Total: 20 tests in 1 file
```

Distribuição por suíte, somando todos os projetos:

```
$ pnpm exec playwright test --list | grep -oE "› (copilot|resolve-gate|widget)/" | sort | uniq -c
     52 › copilot/
      8 › resolve-gate/
     20 › widget/
```

Os 17 arquivos descobertos:

```
copilot/banner-dismiss-persist.spec.js      copilot/panel-mutex.spec.js
copilot/banner-long-conv.spec.js            copilot/panel-open-close.spec.js
copilot/dropdown-categories.spec.js         copilot/preview-chip-aceitar.spec.js
copilot/dropdown-disabled.spec.js           copilot/preview-chip-discard.spec.js
copilot/dropdown-keyboard.spec.js           copilot/quick-prompt-flow.spec.js
copilot/error-matrix.spec.js                copilot/streaming-cancel-on-switch.spec.js
copilot/feature-flag-granular.spec.js       resolve-gate/assign-and-resolve.spec.js
copilot/onboarding-esc-skip.spec.js         widget/widget.spec.js
copilot/onboarding-first-time.spec.js
```

O isolamento entre suítes é feito por `testIgnore: /widget\//` nos projetos
`desktop-chromium`/`mobile-chromium` e `testDir: 'spec/e2e/widget'` no projeto `widget` —
ou seja, **por inclusão do widget num projeto próprio, não por exclusão das outras suítes**.
A correção que apliquei mexeu só no bloco `webServer` do config; a descoberta é idêntica à
do commit original.

---

## Item 5 — Nenhum spec do widget importa do `@playwright/test`

**PASS.** O grep exato pedido devolve saída vazia:

```
$ grep -rn "from '@playwright/test'" spec/e2e/widget/
$ echo $?
1
```

Checagem mais forte (a forma CommonJS, que é a usada neste repo):

```
$ grep -rn "@playwright/test" spec/e2e/
spec/e2e/fixtures.js:1:const { test: base, expect } = require('@playwright/test');
spec/e2e/widget/sabotage.playwright.config.js:1:const { defineConfig, devices } = require('@playwright/test');
spec/e2e/copilot/*.spec.js  ... (15 arquivos, suíte antiga)
spec/e2e/resolve-gate/assign-and-resolve.spec.js:19: ...
```

Em `spec/e2e/widget/` a única ocorrência é o **config de sabotagem**, que importa
`defineConfig`/`devices` — não `test`/`expect`. Os dois arquivos de teste do diretório
importam do fixture anti-erro:

```
spec/e2e/widget/widget.spec.js:3:      const { test, expect } = require('../fixtures');
spec/e2e/widget/fixture.sabotage.js:1: const { test } = require('../fixtures');
```

> Nota factual, não é falha deste bloco: as suítes **antigas** (`copilot/`, `resolve-gate/`)
> ainda importam direto do `@playwright/test` e portanto **não** têm a proteção anti-erro.
> O bloco 0.11 cobre o widget, que é o escopo pedido.

---

## Item 6 — Toda entrada da lista IGNORAR tem justificativa

**PASS — por inexistência da lista.** O fixture não tem lista de ignorar: ele coleta **todos**
os erros dos quatro canais e assere igualdade com array vazio.

`spec/e2e/fixtures.js` na íntegra (33 linhas, é o arquivo inteiro):

```js
const { test: base, expect } = require('@playwright/test');

const test = base.extend({
  page: async ({ page }, use) => {
    const errors = [];

    page.on('pageerror', error => { errors.push(`pageerror: ${error.message}`); });
    page.on('console', message => {
      if (message.type() === 'error') { errors.push(`console.error: ${message.text()}`); }
    });
    page.on('requestfailed', request => {
      errors.push(`requestfailed: ${request.method()} ${request.url()} (${request.failure()?.errorText || 'unknown error'})`);
    });
    page.on('response', response => {
      if (response.status() >= 400) {
        errors.push(`HTTP ${response.status()}: ${response.request().method()} ${response.url()}`);
      }
    });

    await use(page);
    expect(errors, 'Erros capturados durante o teste').toEqual([]);
  },
});
```

Entradas da lista IGNORAR: **zero**. Portanto zero entradas sem justificativa — a regra MUST NOT
do §10.3 ("silenciar erro de console sem justificar em comentário") não é violada porque
**nada é silenciado**.

Verificação de que não existe silenciamento escondido em outro lugar:

```
$ grep -rniE "ignor|allowlist|allowed|whitelist|skip|silenc|expected.?error" spec/e2e/fixtures.js spec/e2e/widget/*.js
(nenhuma ocorrência)
```

As quatro ocorrências de `.filter(` em `widget.spec.js` são de animações em execução
(linhas 165, 173) e de contagem de violações axe por impacto (linhas 185, 188) — nenhuma
filtra erro de console.

---

## Item 7 — Dado dinâmico mascarado ou congelado

**PASS.** Leitura do código, mecanismo por mecanismo:

**1. Relógio congelado antes de qualquer script da página.** `freezeTime` usa
`page.addInitScript`, que roda antes de todo script do documento, e substitui a classe
`Date` inteira — construtor sem argumentos **e** `Date.now()`:

```js
const FROZEN_TIME = '2025-01-15T12:00:00.000Z';

const freezeTime = async page => {
  await page.addInitScript(frozenTime => {
    const NativeDate = Date;
    const timestamp = NativeDate.parse(frozenTime);
    class FrozenDate extends NativeDate {
      constructor(...args) { super(...(args.length ? args : [timestamp])); }
      static now() { return timestamp; }
    }
    window.Date = FrozenDate;
  }, FROZEN_TIME);
};
```

`prepareScenario` chama `freezeTime(page)` como **primeira** instrução (linha 83), antes do
`setViewportSize` e do `goto`. Nenhum cenário escapa.

**2. O relógio do browser e os timestamps do servidor são o MESMO instante** — verificado, não
presumido:

```
$ node -e "..."
FROZEN_EPOCH 1736942400 => 2025-01-15T12:00:00.000Z
FROZEN_TIME              => 2025-01-15T12:00:00.000Z
batem? true
```

Isso é o que torna estável o texto relativo das mensagens ("há 4 minutos", "há 1 minuto"):
`created_at` é `FROZEN_EPOCH - 240/-180/-120/-60`, e o "agora" do browser é exatamente
`FROZEN_EPOCH`. A diferença renderizada é constante entre execuções.

**3. O congelamento é asserido, não presumido.** Existe um teste dedicado que prova as duas
coisas ao mesmo tempo — identidade das mensagens e relógio:

```js
test('congela o relógio e alimenta o store determinístico', async ({ page }) => {
  const { frame } = await prepareScenario(page, 'messages', 'light', 'desktop');
  const state = await frame.locator('body').evaluate(() => ({
    ids: Object.keys(window.WOOT_WIDGET.$store.state.conversation.conversations),
    now: new Date().toISOString(),
  }));
  expect(state.ids).toEqual(['101', '102', '103', '104']);
  expect(state.now).toBe(FROZEN_TIME);
});
```

**4. Nada é gerado — tudo é literal fixo no `widget-server.mjs`.** Não há faker, uuid,
`Math.random` nem `Date.now()` em lugar nenhum do harness:

```
$ grep -rnE "Math\.random|Date\.now\(\)|new Date\(\)|faker|uuid" spec/e2e/widget/
spec/e2e/widget/widget.spec.js:263:    now: new Date().toISOString(),   ← dentro do evaluate,
                                                     com o Date JÁ congelado; é a própria
                                                     asserção do item 3 acima
```

Os dados servidos são constantes literais: mensagens de id `101–104` com conteúdo fixo,
remetente fixo (`id: 7, name: 'Marina Lima'`), contato fixo (`id: 19, 'Visitante E2E'`),
conversa fixa (`id: 31`), `contact_last_seen_at: FROZEN_EPOCH - 210`, `websiteToken`
e `chatwootPubsubToken` fixos.

**5. Avatares não são gerados.** `avatarUrl: ''` no `chatwootWebChannel` e nenhum
`avatar_url` nos senders — não há URL remota nem imagem aleatória entrando no screenshot.
O que o widget desenha são iniciais derivadas de um nome constante.

**6. Formatação de data/hora é determinística por config**, não pelo relógio da máquina:
`locale: 'pt-BR'` e `timezoneId: 'America/Cuiaba'` no `use` global do `playwright.config.js`,
mais `locale: 'pt_BR'` nas settings do host e do canal.

**7. Renderização estabilizada antes do clique do obturador:**
- `await frame.locator('body').evaluate(() => document.fonts.ready)` — sem FOUT no snapshot;
- `--disable-font-subpixel-positioning --disable-lcd-text` nas `launchOptions` do projeto
  `widget` — mata a variação de antialiasing entre execuções;
- `animations: 'disabled'` no `expect.toHaveScreenshot` **e**, além disso, um poll explícito
  que só libera o screenshot quando há **zero** animações rodando, contando host e iframe:

```js
await expect.poll(async () => {
  const hostAnimations = await holder.evaluate(el =>
    el.getAnimations({ subtree: true }).filter(a => a.playState === 'running').length);
  const widgetAnimations = await frame.locator('body').evaluate(() =>
    document.getAnimations().filter(a => a.playState === 'running').length);
  return hostAnimations + widgetAnimations;
}).toBe(0);
```

**8. Âncora de conteúdo forte, nunca `networkidle`** (regra MUST do §10.3):

```
$ grep -rn "networkidle" spec/e2e/widget/ spec/e2e/fixtures.js
(nenhuma ocorrência)
```

Cada cenário espera um texto específico e exato antes de fotografar
(`'Estamos conectados.'`, `'Mensagem determinística para o cenário.'`,
`'Conte um pouco sobre você.'`, `'Resposta pendente número três.'`), além de asserir o nome
da rota atual do router e, no tema escuro, a presença de `#app > .dark`.

**Conformidade com as demais regras MUST do §10.3**, verificada no mesmo arquivo:
- asserção verifica **valor**, nunca truthy: `toBe(400)`, `toBe(4)`, `toBe(316)`, `toBe(300)`,
  `toEqual(['101','102','103','104'])`, `toEqual({gap:4, holder:316, iframe:300, iframeHeight:278})`,
  `toEqual(baseline.measurements[scenario].axe)`;
- decimal com tolerância declarada: `expect(ratio).toBeCloseTo(baseline.measurements[scenario].contrast, 2)`;
- não é tautológico: o contraste é recalculado do zero no spec (fórmula WCAG a partir do
  `getComputedStyle` renderizado) e comparado contra um número gravado no `baseline.json` —
  o spec não lê a implementação para se autoconfirmar.

---

## Segundo defeito, achado exatamente pelo item 2 (duas rodadas seguidas)

A asserção de estabilidade acrescentada pelo coordenador **pegou um bug que a rodada única
nunca pegaria**: a segunda execução consecutiva da suíte não subia.

```
=== rodada encadeada, sem limpeza manual entre elas ===
Error: http://127.0.0.1:3038/__ready is already used, make sure that nothing is
running on the port/url or set reuseExistingServer:true in config.webServer.
EXIT_CODE=1
```

Causa, verificada nos processos vivos depois da suíte terminar:

```
$ ps -eo pid,etime,stat,cmd | grep harness/
 874939  01:11 Ss  /bin/sh -c node spec/e2e/widget/harness/sdk-server.mjs
 874940  01:11 Sl  node spec/e2e/widget/harness/sdk-server.mjs
 876400  01:08 Ss  /bin/sh -c node spec/e2e/widget/harness/widget-server.mjs
 876402  01:08 Sl  node spec/e2e/widget/harness/widget-server.mjs
 877766  01:06 Ss  /bin/sh -c node spec/e2e/widget/harness/host-server.mjs
 877769  01:06 Sl  node spec/e2e/widget/harness/host-server.mjs

$ ss -lntp | grep -E ':(3038|3999|8899)'
LISTEN 127.0.0.1:3999  users:(("MainThread",pid=876402,fd=25))
LISTEN 127.0.0.1:3038  users:(("MainThread",pid=874940,fd=25))
LISTEN 127.0.0.1:8899  users:(("MainThread",pid=877769,fd=21))
```

Os três servidores **sobreviviam** ao fim da suíte, segurando as portas. Dois motivos somados,
ambos no código original do commit:

1. registrar `process.once('SIGTERM', close)` **cancela** o encerramento default do Node — a
   partir dali o processo só sai quando o event loop esvazia;
2. `server.close()` apenas para de aceitar **novas** conexões; as conexões keep-alive que o
   Chromium deixou abertas (e o WebSocket do `/cable`, no widget-server) mantêm o loop vivo
   indefinidamente.

Correção nos três `harness/*.mjs`: `server.closeAllConnections()` antes do `close()` e
`process.exit(0)` ao final do handler.

> Este defeito é **independente** do cold-start e não teria aparecido no aceite original de
> uma execução só. É o caso de a asserção extra do coordenador ter pago por si.

### Rodada A + Rodada B — encadeadas, sem nenhuma limpeza manual entre elas

Este é o teste do item 2 na forma dura: o mesmo comando duas vezes seguidas, no mesmo shell,
sem apagar porta nem cache no meio, com uma inspeção de processos entre as duas.

```
=== RODADA A 12:50:55 ===
  ✓   1 [widget] › widget.spec.js:151:7 › home-light-desktop (5.9s)
  ✓   2 [widget] › widget.spec.js:151:7 › home-light-mobile (6.1s)
  ✓   3 [widget] › widget.spec.js:151:7 › home-dark-desktop (5.6s)
  ✓   4 [widget] › widget.spec.js:151:7 › home-dark-mobile (5.5s)
  ✓   5 [widget] › widget.spec.js:151:7 › messages-light-desktop (8.4s)
  ✓   6 [widget] › widget.spec.js:151:7 › messages-light-mobile (8.8s)
  ✓   7 [widget] › widget.spec.js:151:7 › messages-dark-desktop (6.6s)
  ✓   8 [widget] › widget.spec.js:151:7 › messages-dark-mobile (6.3s)
  ✓   9 [widget] › widget.spec.js:151:7 › prechat-form-light-desktop (6.2s)
  ✓  10 [widget] › widget.spec.js:151:7 › prechat-form-light-mobile (6.0s)
  ✓  11 [widget] › widget.spec.js:151:7 › prechat-form-dark-desktop (6.2s)
  ✓  12 [widget] › widget.spec.js:151:7 › prechat-form-dark-mobile (6.3s)
  ✓  13 [widget] › widget.spec.js:151:7 › unread-light-desktop (6.0s)
  ✓  14 [widget] › widget.spec.js:151:7 › unread-light-mobile (5.1s)
  ✓  15 [widget] › widget.spec.js:151:7 › unread-dark-desktop (5.0s)
  ✓  16 [widget] › widget.spec.js:151:7 › unread-dark-mobile (5.0s)
  (+ os 4 testes de contrato)

  20 passed (5.5m)
EXIT_A=0

=== processos remanescentes entre A e B ===
NENHUM processo remanescente

=== RODADA B 12:56:29 ===
```

A linha **`NENHUM processo remanescente`** é a prova direta da correção do segundo defeito:
antes dela, os três servidores ficavam vivos segurando 3038/3999/8899 e a rodada B morria
na largada.

### Rodada B — imediatamente depois da A, mesmo shell, sem limpeza → **20/20**

```
=== RODADA B 12:56:29 ===

Running 20 tests using 1 worker

  ✓   1 [widget] › widget.spec.js:151:7 › home-light-desktop (6.3s)
  ✓   2 [widget] › widget.spec.js:151:7 › home-light-mobile (5.8s)
  ✓   3 [widget] › widget.spec.js:151:7 › home-dark-desktop (5.5s)
  ✓   4 [widget] › widget.spec.js:151:7 › home-dark-mobile (5.5s)
  ✓   5 [widget] › widget.spec.js:151:7 › messages-light-desktop (6.7s)
  ✓   6 [widget] › widget.spec.js:151:7 › messages-light-mobile (6.8s)
  ✓   7 [widget] › widget.spec.js:151:7 › messages-dark-desktop (6.3s)
  ✓   8 [widget] › widget.spec.js:151:7 › messages-dark-mobile (5.8s)
  ✓   9 [widget] › widget.spec.js:151:7 › prechat-form-light-desktop (6.2s)
  ✓  10 [widget] › widget.spec.js:151:7 › prechat-form-light-mobile (6.1s)
  ✓  11 [widget] › widget.spec.js:151:7 › prechat-form-dark-desktop (6.1s)
  ✓  12 [widget] › widget.spec.js:151:7 › prechat-form-dark-mobile (5.8s)
  ✓  13 [widget] › widget.spec.js:151:7 › unread-light-desktop (5.0s)
  ✓  14 [widget] › widget.spec.js:151:7 › unread-light-mobile (4.8s)
  ✓  15 [widget] › widget.spec.js:151:7 › unread-dark-desktop (5.0s)
  ✓  16 [widget] › widget.spec.js:151:7 › unread-dark-mobile (4.8s)
  ✓  17 [widget] › widget.spec.js:222:1 › carrega SDK, entrypoint e host reais nas portas contratadas (2.7s)
  ✓  18 [widget] › widget.spec.js:255:1 › congela o relógio e alimenta o store determinístico (3.4s)
  ✓  19 [widget] › widget.spec.js:269:1 › preserva a geometria original do unread no resize real (3.1s)
  ✓  20 [widget] › widget.spec.js:300:1 › baseline descreve exatamente a matriz de 16 cenários (48ms)

  20 passed (5.7m)
EXIT_B=0
=== fim B 13:02:16 ===
```

E o estado da máquina depois de tudo:

```
$ ps -eo pid,etime,cmd | grep harness/
NENHUM processo remanescente
$ ss -lntp | grep -E ':(3038|3999|8899)'
portas 3038/3999/8899 livres
$ ss -lntp | grep ':3000'
LISTEN 0  1024  0.0.0.0:3000  users:(("ruby",pid=2213976,fd=8))    ← Puma da homologação, intacto
```

### Veredito dos itens 1 e 2

**Item 1 — PASS.** 16/16 snapshots batendo contra os PNG do commit, sem `--update-snapshots`,
em três execuções independentes (green1 em cache frio, A e B encadeadas).

**Item 2 — PASS.** Duas rodadas consecutivas, `20/20` e `20/20`, EXIT 0 em ambas, sem
intervenção manual entre elas. Variação por teste entre 4.8s e 8.8s — sem outlier, sem retry
(o projeto `widget` roda com `retries: 0`).

Prova adicional de que os PNG do commit foram **lidos**, não regravados:

```
$ git status --porcelain spec/e2e/widget/snapshots/
(vazio)
$ git diff --numstat HEAD -- spec/e2e/widget/snapshots/ | wc -l
0
```

Os 16 arquivos estão byte-a-byte idênticos ao commit `f26db6ee81` depois de todas as
execuções. `--update-snapshots` nunca foi usado.

---

## Item 4 — Fixture anti-erro: a prova de que ele falha alto

**PASS.** Os quatro sabotadores falharam, cada um nomeando o erro que o fixture capturou.

```
$ pnpm exec playwright test --config=spec/e2e/widget/sabotage.playwright.config.js

Running 4 tests using 1 worker

  ✘  1 [widget-sabotage] › fixture.sabotage.js:3:1 › sabotagem: console.error é capturado (807ms)
  ✘  2 [widget-sabotage] › fixture.sabotage.js:11:1 › sabotagem: pageerror é capturado (831ms)
  ✘  3 [widget-sabotage] › fixture.sabotage.js:19:1 › sabotagem: requestfailed é capturado (1.3s)
  ✘  4 [widget-sabotage] › fixture.sabotage.js:27:1 › sabotagem: HTTP 500 é capturado (803ms)

  4 failed
EXIT_CODE=1
```

### 4a) `console.error` injetado faz o teste FALHAR e a falha NOMEIA o texto

```
  1) sabotagem: console.error é capturado

    Error: Erros capturados durante o teste
    expect(received).toEqual(expected) // deep equality

    - Array []
    + Array [
    +   "console.error: fixture-console-sabotage",
    + ]

       at ../fixtures.js:29
      > 29 |     expect(errors, 'Erros capturados durante o teste').toEqual([]);
```

O texto exato injetado pelo sabotador (`console.error('fixture-console-sabotage')`) aparece
literalmente na mensagem de falha. **Nomeia.**

### 4b) resposta 500 faz o teste FALHAR e a falha NOMEIA método e URL

```
  4) sabotagem: HTTP 500 é capturado

    Error: Erros capturados durante o teste
    expect(received).toEqual(expected) // deep equality

    - Array []
    + Array [
    +   "HTTP 500: GET http://127.0.0.1:8899/__sabotage__/500",
    +   "console.error: Failed to load resource: the server responded with a status of 500 (Internal Server Error)",
    + ]
```

Método (`GET`) e URL completa (`http://127.0.0.1:8899/__sabotage__/500`) estão na mensagem.
**Nomeia.**

> **Nuance registrada com honestidade:** o sabotador do commit dispara o 500 por *navegação*
> (`page.goto`), não por `fetch()`. O aceite fala em `fetch`. Como o handler do fixture é
> `page.on('response')`, ele cobre as duas coisas — mas em vez de presumir, **executei**.
> Spec temporário escrito no scratchpad (fora do repositório, nada foi alterado em
> `spec/e2e/`), usando o fixture real do repo e um `fetch()` de verdade:
>
> ```js
> const { test } = require('.../spec/e2e/fixtures');
> test('sabotagem extra: fetch() que devolve 500 é capturado', async ({ page }) => {
>   await page.goto('http://127.0.0.1:8899/?scenario=home&theme=light');
>   await page.evaluate(async () => { await fetch('/__sabotage__/500', { method: 'GET' }); });
> });
> ```
>
> ```
>   ✘  1 [fetch500] › sabotagem extra: fetch() que devolve 500 é capturado (443ms)
>
>     Error: Erros capturados durante o teste
>     - Array []
>     + Array [
>     +   "requestfailed: GET http://127.0.0.1:3038/app/javascript/entrypoints/sdk.js (net::ERR_CONNECTION_REFUSED)",
>     +   "console.error: Failed to load resource: net::ERR_CONNECTION_REFUSED",
>     +   "HTTP 500: GET http://127.0.0.1:8899/__sabotage__/500",
>     +   "console.error: Failed to load resource: the server responded with a status of 500 (Internal Server Error)",
>     + ]
>   1 failed
> ```
>
> O `fetch()` é capturado com método e URL. De quebra, como nessa execução isolada subi só o
> host-server, o fixture também flagrou o SDK ausente na 3038 — exatamente o comportamento
> que se espera dele.

### Os outros dois canais, também verificados

```
  2) sabotagem: pageerror é capturado
    + Array [
    +   "pageerror: fixture-pageerror-sabotage",
    + ]

  3) sabotagem: requestfailed é capturado
    + Array [
    +   "requestfailed: GET http://127.0.0.1:1/fixture-request-sabotage (net::ERR_UNSAFE_PORT)",
    + ]
```

Os quatro canais do fixture (`pageerror`, `console.error`, `requestfailed`, `HTTP >= 400`)
estão vivos e cada um derruba o teste nomeando a causa.

> Detalhe de higiene: `fixture.sabotage.js` **não** entra na suíte normal — o `testMatch` do
> projeto `widget` é `/.*\.spec\.js/` e o arquivo não termina em `.spec.js`. Confirmado pelo
> `--list --project=widget`: `Total: 20 tests in 1 file` (só `widget.spec.js`).

---

## O que foi alterado, e o que NÃO foi

### Commit local (não pushado)

```
$ git log --oneline -2
d21794862b fix(e2e): aquece o Vite antes do /__ready e encerra o harness de verdade
f26db6ee81 test(widget): capture Playwright baseline
```

4 arquivos, +101/−12, todos de infraestrutura de teste:

| arquivo | mudança |
|---------|---------|
| `spec/e2e/widget/harness/sdk-server.mjs` | warmup do moduleGraph antes do `/__ready`; encerramento com `closeAllConnections()` + `exit(0)` |
| `spec/e2e/widget/harness/widget-server.mjs` | idem |
| `spec/e2e/widget/harness/host-server.mjs` | encerramento com `closeAllConnections()` + `exit(0)` |
| `playwright.config.js` | `timeout` de boot dos dois `webServer` com Vite: 120000 → 600000 |

`pnpm exec eslint` e `pnpm exec prettier --check` limpos nos quatro. Hook de pre-commit
(`check_vue_template_refs`, 197 arquivos) passou sem `--no-verify`.

### Restrições da task, honradas

- **Nenhum PNG tocado.** `git diff --numstat HEAD -- spec/e2e/widget/snapshots/` → `0`.
- **`--update-snapshots` nunca foi executado.** Os 16 PNG do commit foram lidos, não escritos.
- **Nada em `app/`, `enterprise/`, `lib/`, `config/`, `db/`.** O diff inteiro está em
  `spec/e2e/widget/harness/` e `playwright.config.js`.
- **Puma da :3000 intocado** durante toda a validação (`pid=2213976` vivo do começo ao fim).
  Nenhuma porta precisou ser trocada — o harness usa 3038/3999/8899 e 3040/4001, todas livres.
- **Nenhuma migration, nenhum banco, nenhum push, nenhum deploy, nenhum restart.**
- Worktree `/home/chatwoot/chatwoot-redesenho-merge` não foi acessado.
- O spec temporário do `fetch()` foi escrito no scratchpad, **fora** do repositório, e não
  deixou rastro em `spec/e2e/`.

### Achado menor, não corrigido (fora do escopo)

`test-results/` (o `outputDir` default do Playwright, que recebe vídeo e screenshot das
falhas) **não está no `.gitignore`** — aparece como untracked após qualquer execução com
falha. Removi o diretório antes de commitar. Vale uma linha no `.gitignore` num bloco futuro;
não mexi porque o escopo desta task é validar, não arrumar o repositório.

### Sobre a armadilha da tentativa anterior

O relatório anterior descrevia HTTP 504 "Outdated Optimize Dep" em `js-cookie.js` por
disputar a :3000 com o Puma. **Isso não aconteceu aqui em nenhuma das 6 execuções.** O harness
deste commit não usa a :3000: ele sobe instâncias próprias do Vite em `middlewareMode` nas
portas 3038 e 3999. A afirmação anterior de que o commit teria sido revertido também é falsa —
`f26db6ee81` está no HEAD com os 27 arquivos.

Uma observação factual para o coordenador, já que a task pedia atenção a isso: o harness **usa
Vite**, mas o seu próprio, embutido no processo `.mjs` — **não** depende de `bin/vite dev` nem
de nenhum servidor compartilhado. Ele compila do código-fonte a cada execução, o que é a
propriedade desejável aqui (o baseline mede o código da branch, não um bundle pré-construído
que poderia estar velho). O custo disso é o warmup, que agora é explícito e medido em vez de
escondido dentro do primeiro teste.

---

## VEREDITO

### 0.1 — **VALIDADO**

Os 16 PNG e o `baseline.json` do commit `f26db6ee81` são uma régua legítima: 16/16 batem
contra os arquivos commitados, sem `--update-snapshots`, em três execuções independentes, e
duas rodadas consecutivas fecham 20/20 cada. Os cenários cobrem a matriz declarada
(4 views × 2 temas × 2 viewports), os dados são congelados e as medições de acessibilidade e
contraste são asseridas contra valores gravados, com tolerância declarada. As suítes
`copilot/` e `resolve-gate/` continuam descobertas.

Ressalva registrada, não silenciada: **o commit não passava como entregue** — falhava 13/16 na
primeira execução e não subia na segunda. Os dois defeitos eram do harness (gate de prontidão
mentiroso e processos que não morriam), não do baseline, e estão corrigidos em `d21794862b`
sem regravar um único pixel.

### 0.11 — **VALIDADO**

O fixture anti-erro falha alto e nomeia a causa nos quatro canais que monitora — verificado
por execução, não por leitura: `console.error: fixture-console-sabotage`,
`pageerror: fixture-pageerror-sabotage`,
`requestfailed: GET http://127.0.0.1:1/fixture-request-sabotage (net::ERR_UNSAFE_PORT)` e
`HTTP 500: GET http://127.0.0.1:8899/__sabotage__/500` (este último confirmado tanto por
navegação quanto por `fetch()` real). Todo spec do widget importa do fixture, nunca do
`@playwright/test`. A lista IGNORAR tem zero entradas: nada é silenciado, portanto não há o
que justificar. Este bloco passou **sem precisar de nenhuma correção**.
