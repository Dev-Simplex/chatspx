# Bloco 0.11 · O fixture anti-erro — relatório de execução

**Worktree:** `/home/chatwoot/chatwoot-o1-widget` · **Branch:** `o1-widget`
**Base:** `redesenho-integra` (`a7e37d2356` → merge sem conflito) · **Data:** 19/08/2026

---

## 0. Resumo

| | |
|---|---|
| Aceite do 0.11 | **11 de 11 verificações**, executadas por `spec/e2e/widget/fixture-antierro.check.mjs` |
| Sabotagens do próprio fixture | **4**, todas detectadas |
| Suítes convertidas ao fixture | **7** (2 dentro do escopo do aceite, 5 para medir) |
| `spec/e2e/widget/**` com `test` de `@playwright/test` | **0 de 29** |
| Defeito encontrado no desenho, medido e corrigido | **1** — a armadilha da tupla do Playwright (§4) |

---

## 1. O que já existia, e o que faltava

O bloco 0.1 (`f26db6ee81`) já havia deixado `spec/e2e/fixtures.js` capturando `pageerror`,
`console.error`, `requestfailed` e HTTP ≥ 400, e **6 specs do widget já o usavam**. O 0.11 não
começou do zero — e é honesto dizer isso.

O que faltava, e que é o que separa "existe um fixture" de "o fixture é confiável":

| Faltava | Por quê |
|---|---|
| lista `IGNORAR` com razão por linha | é o aceite, e sem ela **erro de ambiente derruba tudo** e alguém desliga o fixture |
| critério escrito de ambiente × produto | sem critério, a lista cresce por conveniência |
| escape **por cenário** | um teste que exercita o caminho de falha não tinha como declarar o que ele mesmo provoca |
| separação das quatro categorias | um número só esconde qual está acontecendo |
| observar janelas novas | o widget abre popout; erro na janela nova não era visto por ninguém |
| verificação do aceite | as sabotagens existiam, mas alguém tinha de rodar e **olhar** |
| 2 specs de `spec/e2e/widget/**` | `citacao` e `capture` pegavam `test` de `@playwright/test` |

---

## 2. As quatro categorias, separadas — e por quê

O despacho pediu contagem própria por categoria. São **quatro**, não três, e a quarta importa:

| Categoria | O que é | Quem costuma ser o dono |
|---|---|---|
| `pageerror` | exceção **não capturada** que subiu ao `window.onerror` | o mais grave: algo parou de executar |
| `console` | `console.error` — um **log**. O código seguiu | quem escolheu reclamar |
| `http` | resposta com status ≥ 400 | pode ser nossa (500) ou de contrato (404) |
| `rede` | `requestfailed` — **não houve resposta** (DNS, recusa, bloqueio) | **não é HTTP: não há status** |

A quarta não é preciosismo: as duas suítes que mais sujaram a medição (§3) sujaram **em `rede`**,
e as duas o fazem de propósito. Se `rede` estivesse dobrada em `http`, a leitura seria "duas suítes
com erro de servidor" em vez de "duas suítes que derrubam o servidor porque é isso que elas testam".

---

## 3. A LINHA DE BASE — o que já está sujo hoje

Medida com `E2E_ANTIERRO=report`, que **conta e imprime sem reprovar**. É o modo do primeiro
inventário, e ele existe só para isto: o padrão do fixture é bloquear.

### 3.1 O placar

**60 cenários medidos**, em 7 suítes.

| Suíte | Cenários | pageerror | console | http | rede | Veredito |
|---|---:|---:|---:|---:|---:|---|
| `widget/capture` | 3 | 0 | 0 | 0 | 0 | **limpa** |
| `widget/citacao` | 10 | 0 | 0 | 0 | 0 | **limpa** |
| `tracking` | 9 | 0 | 0 | 0 | 0 | **limpa** |
| `appearance` | 11 | 0 | 0 | 0 | 0 | **limpa** |
| `telemetry` | 6 | 0 | 1 | 0 | 12 | **cenário** — ver 3.2 |
| `fallback` | 8 | 0 | 6 | 0 | 6 | **cenário** — ver 3.2 |
| `triggers` | 13 | **13** | 0 | 0 | 0 | **DEFEITO REAL** — ver 3.3 |
| `widget` (principal, 20 snapshots + 6 specs) | — | — | — | — | — | **sob tranca — §7.1** |
| `copilot` (15) + `resolve-gate` (1) | — | — | — | — | — | **precisam do Rails na 3000 — §7.2** |

**Quatro suítes já estão limpas** — 33 cenários sem um único erro de qualquer categoria. Elas passam
a bloquear a partir de agora sem nenhuma dívida.

### 3.2 As duas que sujam de propósito — e é o caso exato do ponto 1 do despacho

`telemetry` e `fallback` são as duas suítes que **exercitam justamente o caminho de falha**:

- **`telemetria.spec.js`** → describe *"2.13 — nada vaza para o site do cliente"*, com o teste
  *"o endpoint fora do ar não gera `unhandledrejection` no pai"*. Ele **derruba o endpoint de
  propósito**. Os `net::ERR_ABORTED`/`ERR_FAILED` **são o cenário**, e o que se prova é que eles
  **não** viram erro visível no site do cliente.
- **`launcherFallback.spec.js`** → describe *"2.14 — **o bundle falhou**"*. Ele **bloqueia o
  `sdk.js` de propósito** para provar que o link de contato alternativo aparece.
  `ERR_BLOCKED_BY_CLIENT` é o cenário sendo montado.

**Nenhuma das duas foi para `IGNORAR`.** Elas ganharam escape **por cenário e por mensagem**, no
`describe` que as justifica, com o motivo escrito ao lado. A diferença é grande:

> Pôr `net::ERR_FAILED` na lista global cegaria o fixture para uma falha real de telemetria em
> **qualquer** outro cenário do repositório. No describe, ele vale só ali. E o describe irmão de
> `fallback` — *"o bundle carregou normalmente"* — **não tem escape nenhum**: se o `sdk.js` passar
> a falhar no caminho feliz, reprova.

Depois do escape, as duas passam **em modo bloqueante**: `telemetry` 4 passed, `fallback` 8 passed.

### 3.3 `triggers` — o achado, e é exatamente o que o bloco existe para produzir

**Os 13 cenários da suíte produzem `pageerror`. O mesmo, um por cenário:**

```
pageerror: Cannot read properties of undefined (reading 'find')
    at ComputedRefImpl.fn (…/settings/inbox/widget/triggers/TeaserComposer.vue:46:19)
```

**Causa raiz, localizada:** `TeaserComposer.vue` (bloco **4.05+4.07**, commit `8aa34c79ec`) lê dois
getters de store —

```js
const campanhas = useMapGetter('campaigns/getLiveChatCampaigns');
const vinculada = computed(() => campanhas.value.find(…));   // linha 46
```

— e o harness E2E do bloco **4.04** (`spec/e2e/triggers/harness/entry.js`) monta um store falso com
exatamente **três** getters: `inboxes/getInbox`, `inboxes/getUIFlags` e `globalConfig/get`. Não há
`campaigns/*`. `campanhas.value` é `undefined`, e `.find` sobre `undefined` lança.

**É dívida de junção entre duas trilhas:** o 4.05/4.07 acrescentou um componente à `TriggersPage` e
não atualizou o harness que a monta. Ninguém errou sozinho.

#### Não fui eu — medido, não deduzido

Duas provas independentes:

1. A medição roda com `E2E_ANTIERRO=report`, e nesse modo **o fixture não reprova nada**. As 13
   falhas são dos `expect` dos próprios testes.
2. Revertido o import do spec para `@playwright/test` (sem o meu fixture), os mesmos testes falham:
   **2 failed**, os dois "Chamativo é o único destacado". A quebra é **pré-existente**.

#### E aqui está o argumento do bloco 0.11, inteiro, num caso só

O primeiro teste da suíte se chama **"renderiza sem erro de console e sem chave de i18n crua"**, e
ele **já coletava erros por conta própria**:

```js
const abrir = async (page, …) => {
  const erros = [];
  page.on('console', msg => { if (msg.type() === 'error') erros.push(msg.text()); });
  page.on('pageerror', erro => erros.push(erro.message));
  await page.goto(…);
  await page.waitForSelector('[data-testid="approach-bold"]');   // <-- morre AQUI
  return erros;
};
…
expect(erros).toEqual([]);        // <-- nunca chega a rodar
```

O componente quebra, o seletor nunca aparece, o `waitForSelector` estoura — e **a linha que
conferiria os erros nunca executa**. O coletor existia, estava correto, e ficou cego porque morava
**dentro do corpo do teste**.

O fixture confere **depois do `use(page)`**: ele roda mesmo quando o teste morre no meio, e por isso
a mensagem passa a nomear a causa (`TeaserComposer.vue:46:19`) em vez do sintoma (timeout de
seletor). Centralizar não é elegância — é a diferença entre um coletor que pode ser pulado e um que
não pode.

**Mantive `triggers` convertida.** Ela já está 13/13 vermelha por conta própria; o fixture não piora
nada e passa a apontar o arquivo e a linha. Não consertei — não é meu bloco, e o despacho pediu para
declarar a linha de base, não reescrever o passado. Escalado no §7.5.

### 3.4 `appearance` estava limpa — e a primeira medição mentiu

`appearance`: **11 cenários, zero erros de qualquer categoria.**

A primeira medição a acusou com dezenas de `ERR_CONNECTION_REFUSED` em arquivos de i18n. Era **ruído
do meu próprio método**: eu havia disparado quatro suítes com `webServer` ao mesmo tempo, e os
servidores Vite se atropelaram. Rodada isolada, zero.

**A lição vale para quem for repetir esta medição:** suíte com `webServer` medida em paralelo produz
erro de rede que **parece defeito de produto**. A distinção ambiente × produto do §5 não cobre isso,
porque não é nem um nem outro — é o instrumento sujando a amostra. Medir isolado, ou não medir.

### 3.5 A lista `IGNORAR` está **vazia**

Nada precisou entrar. O `503 /waha_connections` que o despacho citou **não apareceu em nenhuma das
suítes medidas** — ele é do ambiente de validação do dashboard, e as suítes que o alcançariam
(`copilot`, `resolve-gate`) dependem do Rails na 3000 e não foram medidas aqui.

O formato da entrada está escrito no arquivo, comentado, pronto para a primeira que for necessária —
com os três critérios do §5 que ela terá de satisfazer.

---

## 4. O DEFEITO QUE EU MESMO INTRODUZI, medi e corrigi

Este é o achado mais caro do bloco, e ele quase passou.

Escrevi o escape como `test.use({ errosEsperados: [/a/, /b/] })` — a forma intuitiva. As sabotagens
ficaram verdes, o aceite deu 9/9. Aí apliquei o escape em `telemetry` e `fallback`, e **os testes
reprovaram** com `errosEsperados.forEach is not a function`.

Reproduzi num spec de dez linhas:

```
test.use({ opt: [/aaa/, /bbb/] })   ->   opt === /aaa/     (não é array; /bbb/ sumiu)
```

**O Playwright confunde o array com a sintaxe de tupla `[valor, { option: true }]`.** A heurística é
"array de 2 posições cujo segundo item é objeto" — e `RegExp` **é** objeto. Consequência medida:

| padrões declarados | o que chega | resultado |
|---:|---|---|
| 1 | o array | funciona |
| **2** | **só o primeiro, como RegExp solto** | **quebra** |
| 3+ | o array | funciona |

Um escape que **funciona com 1 e com 3, e perde o segundo padrão em silêncio quando são 2**. É
precisamente a forma de este bloco virar praga: o teste fica vermelho por um erro que o autor achou
que tinha declarado, ninguém entende, e o fixture é desligado.

**Correção:** a forma canônica passou a ser `{ padroes: [...] }`, que nunca é lida como tupla. Array
cru continua aceito (1 ou 3+), e o caso quebrado é **detectado e nomeado**:

```
errosEsperados em "…" chegou como [object RegExp] em vez de lista.
Você provavelmente escreveu `test.use({ errosEsperados: [/a/, /b/] })` com DOIS padrões: o
Playwright leu isso como a tupla `[valor, options]` e descartou o segundo.
Use a forma canônica: `test.use({ errosEsperados: { padroes: [/a/, /b/] } })`.
```

E virou o **11º cenário de aceite**, com sabotagem própria: um describe que usa a forma quebrada e
tem de reprovar nomeando `tupla` e `padroes`.

---

## 5. O critério de ambiente × produto, escrito

Está no topo de `spec/e2e/fixtures.js`, porque é lá que quem for acrescentar uma entrada vai olhar.
Uma entrada só é **ambiente** se satisfizer os **três**:

1. o erro vem de dependência **externa** que este ambiente de validação não provisiona (WAHA,
   gateway de e-mail, storage de terceiro); **e**
2. a ausência dela **não é defeito do código sob teste** — o mesmo cenário passa onde o serviço
   existe; **e**
3. o padrão nomeia a URL/mensagem **específica**, nunca uma família inteira.

Falhou qualquer um? É **produto**, e produto **bloqueia** — 404 de asset nosso, 500 nosso,
`console.error` de código nosso, mesmo que "sempre esteve ali".

**Os dois escapes são diferentes de propósito:**

| | `IGNORAR` (global) | `errosEsperados` (por cenário) |
|---|---|---|
| para quê | só ambiente | o erro que o próprio teste provoca |
| exige que ocorra? | **não** (o serviço pode existir na máquina de alguém) | **sim** — declarado que não ocorre **reprova** |
| catch-all | recusado | recusado |

A exigência de ocorrência no escape por cenário é o que impede a lista de apodrecer: escape que
sobrevive ao cenário que o justificava é exatamente como uma lista destas vira decoração.

**Nenhum dos dois aceita padrão amplo.** `recusarPadraoAmplo` rejeita `''`, `.*`, `.+`, `^.*$`,
`[\s\S]*` e qualquer fonte com menos de 4 caracteres, com a mensagem *"um catch-all desliga o
fixture sem que ninguém veja"*.

---

## 6. Como o aceite foi verificado — e por que não dava para "rodar e olhar"

O aceite do 0.11 afirma que **certos testes FALHAM**. Um aceite assim não pode ser verificado por um
teste que passa: seria preciso alguém rodar e conferir a olho.

`spec/e2e/widget/fixture-antierro.check.mjs` roda `fixture.sabotage.js` num subprocesso e confere,
cenário por cenário, **quem reprovou** e **se a mensagem nomeia o que o aceite manda nomear**. É o
mesmo padrão dos outros `.check.mjs` desta base, e é verde quando o fixture está trabalhando:

```
OK    REPROVA: console.error — reprovou nomeando "console", "sabotagem-console-marcador"
OK    REPROVA: pageerror — reprovou nomeando "pageerror", "sabotagem-pageerror-marcador"
OK    REPROVA: HTTP 500 nomeando método e URL — reprovou nomeando "http", "500", "GET", "/api/sabotagem-500"
OK    REPROVA: falha de rede — reprovou nomeando "rede", "sabotagem-rede"
OK    REPROVA: console.error em janela NOVA — reprovou nomeando "console", "sabotagem-popup-marcador"
OK    REPROVA: errosEsperados obsoleto — reprovou nomeando "NÃO aconteceram", "sabotagem-que-nunca-ocorre"
OK    REPROVA: padrão catch-all é recusado — reprovou nomeando "amplo demais"
OK    REPROVA: array cru com dois padroes e detectado — reprovou nomeando "tupla", "padroes"
OK    PASSA: página limpa — passou
OK    PASSA: o erro que o próprio cenário provoca — passou
OK    nenhum dos 29 *.spec.js de spec/e2e/widget/** importa `test` de @playwright/test

11 de 11 verificações do aceite 0.11
```

### 6.1 A armadilha do `grep` do aceite

O aceite diz: `grep -rn "from '@playwright/test'" spec/e2e/widget/` → vazio.

**Esse grep dá vazio HOJE, antes de qualquer trabalho** — porque esta base usa `require(...)`, não
`import … from`. Um aceite que passa sozinho não mede nada.

O que o aceite **quer** é que nenhum teste pegue `test` fora do fixture. Então o verificador cobra a
regra de verdade, nas duas sintaxes, distinguindo teste de config: **config precisa** de
`defineConfig`/`devices` de `@playwright/test` e não tem `page` para observar. Os 3 configs que
restam em `spec/e2e/widget/` são legítimos por isso.

### 6.2 Sabotagens do próprio fixture — cicatriz nº 1 aplicada a mim

Não chamei de verde sem tirar a coisa e ver se o mecanismo percebe:

| Sabotagem no fixture | O que o verificador acusou |
|---|---|
| desligar a captura de `console.error` | **3 falhas** — as 2 sabotagens de console passaram a passar, e o escape legítimo virou falso positivo |
| remover `context.on('page')` | **1 falha** — a janela nova deixou de ser observada |
| não cobrar escape obsoleto | **1 falha** — o escape podre passou a passar |
| (a armadilha da tupla, §4) | **1 falha** — coberta pelo 11º cenário |

A primeira revelou uma propriedade que eu não tinha desenhado: desligar a captura de console
**também** derruba o cenário de escape legítimo, porque o erro declarado deixa de acontecer. A trava
anti-apodrecimento funciona como rede secundária contra o fixture ser esvaziado.

### 6.3 A sabotagem saiu da tranca

O `sabotage.playwright.config.js` espalhava `...baseConfig` e subia os **três `webServer` das portas
3038/3999/8899** só para verificar um fixture. Agora não herda nada e não tem `webServer`: as
sabotagens usam `page.route` e `setContent`. **O mecanismo que prova a rede de segurança não pode ser
o que mais briga por porta.**

---

## 7. Escalações

### 7.1 🟠 A suíte principal do widget não foi medida — **peço o slot**

`playwright.config.js` (projeto `widget`: 20 snapshots + `widget`, `darkMode`, `sdkEvents`, `scroll`,
`movimento`, `superficie`) usa as portas fixas **3038/3999/8899**, slot único sob sua tranca.

Essas 6 specs **já usavam** o fixture antes deste bloco, então não há dívida de adoção — mas elas
agora rodam com as quatro categorias separadas, o escape por cenário e a observação de janelas novas.
**A linha de base delas está por medir**, e é justamente a suíte que o despacho aponta como a de
maior alavancagem. Peço o slot para rodar `E2E_ANTIERRO=report` nela e completar o §3.1.

### 7.2 🟡 `copilot` (15 specs) e `resolve-gate` (1) seguem fora do fixture

Elas dependem do Rails na 3000 e do ambiente de validação — que é exatamente onde vive o
`503 /waha_connections` que o despacho citou. **Não as converti**: sem poder medi-las, converter
seria ligar um gate às cegas em 16 arquivos, e é assim que um fixture vira praga.

O verificador as **lista como aviso** a cada execução, com o caminho de cada uma, para que a dívida
seja visível sem ser bloqueante. É a decisão de escopo que devolvo a você.

### 7.5 🔴 `spec/e2e/triggers` está 13/13 vermelha na base — junção 4.05/4.07 × 4.04

Detalhado no §3.3. O `TeaserComposer.vue` (4.05+4.07) pede `campaigns/getLiveChatCampaigns` e
`campaigns/getUIFlags`; o harness do 4.04 (`spec/e2e/triggers/harness/entry.js`) monta um store falso
com três getters e nenhum deles é de `campaigns`. Resultado: `pageerror` em **todos** os 13 cenários.

**Provado pré-existente** por duas vias (§3.3). **Não consertei** — é junção de duas trilhas que não
são a minha, e o conserto (acrescentar os dois getters ao harness, ou dar default `[]` ao
`computed`) é decisão de quem é dono do componente. O reparo aparenta ser de poucas linhas.

Registro que este é o **primeiro defeito real que o fixture produziu**, e ele estava invisível: a
suíte falhava por timeout de seletor, e a mensagem não dizia por quê.

### 7.6 🟡 Medir suítes com `webServer` em paralelo suja a amostra

Ver §3.4. Quatro suítes simultâneas produziram `ERR_CONNECTION_REFUSED` em massa que parecia defeito
de produto e não era. Quem for repetir a medição: **uma de cada vez**.

### 7.3 🟡 O aceite do bloco cita um `grep` que já passava sozinho

Ver §6.1. Registro porque o mesmo padrão pode estar em outros aceites: um comando de verificação que
casa com uma sintaxe que a base não usa dá vazio e parece verde.

### 7.4 ⚪ Modo `report` existe e é opt-in

`E2E_ANTIERRO=report` conta e imprime sem reprovar. Ele foi criado para levantar esta linha de base.
**O padrão é bloquear** — quem rodar sem a variável tem o comportamento do aceite. Registro
explicitamente porque uma variável que desliga o gate é a coisa que mais merece ser conhecida por
quem for revisar: se ela aparecer num CI, é para reprovar a mudança que a colocou lá.

---

## 8. Arquivos

**Novo:** `spec/e2e/widget/fixture-antierro.check.mjs` — o aceite executado

**Reescritos:** `spec/e2e/fixtures.js` · `spec/e2e/widget/fixture.sabotage.js` ·
`spec/e2e/widget/sabotage.playwright.config.js`

**Convertidos ao fixture (1 linha cada):** `spec/e2e/widget/capture/captureWidth.spec.js` ·
`spec/e2e/widget/citacao/citacao.spec.js` *(escopo do aceite)* · `spec/e2e/tracking/tracking.spec.js` ·
`spec/e2e/triggers/triggers.spec.js` · `spec/e2e/appearance/appearance.spec.js` ·
`spec/e2e/telemetry/telemetria.spec.js` · `spec/e2e/fallback/launcherFallback.spec.js` *(para medir)*

**Com escape por cenário:** `telemetria.spec.js` · `launcherFallback.spec.js`

**Não tocado:** `spec/e2e/widget/baseline.json` — o ESLint reclama de formatação dele, e é de outra
trilha. Regra MUST NOT do §10.3: não reformatar arquivo em massa.

ESLint limpo em tudo o que este bloco tocou.
