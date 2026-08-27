# Triagem: telemetria (2.13) e gatilhos (4.04) — 27/08/2026

> **Escopo.** As falhas de `spec/e2e/telemetry/` e `spec/e2e/triggers/`, medidas em Chromium real
> nesta worktree (`chatwoot-spx-tela4-tracking`, base `7b4ad0a371`). Nenhum banco, nenhuma VM,
> nenhum `push`.

## 0. O placar

| Suíte | Antes | Depois | Como rodar |
|---|---|---|---|
| `spec/e2e/telemetry` | **4 passaram, 2 falharam** | **6 passaram, 0 falharam** | `npx playwright test --config=spec/e2e/telemetry/playwright.config.js` |
| `spec/e2e/triggers` | **0 passaram, 13 falharam** | **11 passaram, 2 falharam** | `TRIGGERS_PORT=3072 npx playwright test --config=spec/e2e/triggers/triggers.playwright.config.js` |
| `widget/helpers/specs/telemetry.spec.js` | 17 exemplos | **18 exemplos, todos verdes** | `npx vitest run app/javascript/widget/helpers/specs/telemetry.spec.js` |

**A contagem de gatilhos veio 13, não 12.** A lista da dispatch dizia 12; medido são **13 de 13** —
o arquivo tem 13 testes (4 × 2 temas + 3 do nível Agressivo + 2 do que já está gravado) e nenhum
passava.

As **2 que sobraram** em gatilhos são defeito real, diagnosticado e **não corrigido por decisão de
propriedade de arquivo** — §4.

---

## 1. Telemetria — o teste estava certo pela metade, e a metade certa era a que ninguém tinha lido

### 1.1 O que a dispatch suspeitava, e por que não era isso

A suspeita era vazamento: «se o teste está certo, o widget está VAZANDO erro para o `window.onerror`
do SITE DO CLIENTE». **Não está.** Medido, com o gate em modo relatório
(`E2E_ANTIERRO=report`), nos três cenários do describe:

```
2.13 — nada vaza … > o erro registrado não aparece no `window.onerror` do pai
  pageerror=0 console=0 http=0 rede=1
```

`pageerror=0` e o próprio `expect(vazamentos).toEqual([])` do corpo do teste **passavam**. A falha
acontecia **depois** do corpo, em `spec/e2e/fixtures.js:238`, e a mensagem dizia o que era:

```
Error: errosEsperados que NÃO aconteceram — o cenário mudou e o escape ficou para trás
+   "/Failed to load resource: net::ERR_FAILED/",
```

### 1.2 A primeira causa: escape no escopo errado

`telemetria.spec.js` declarava, **no describe inteiro** (3 testes), dois padrões de erro esperado.
Só **um** dos três cenários provoca esses dois — o que derruba o endpoint com `route.abort`. Os
outros dois não derrubam nada, então o padrão do `ERR_FAILED` nunca acontecia neles, e o fixture do
bloco 0.11 reprova, por regra escrita, escape declarado que não ocorre.

Isso é literalmente o que o cabeçalho do fixture chama de decoração: *«escape que sobrevive ao
cenário que o justificava»*. Corrigido movendo o escape para um `describe` aninhado com o cenário
que o justifica, sozinho.

### 1.3 A segunda causa, que só apareceu quando a primeira saiu do caminho — e essa é PRODUTO

Reescopar o escape **não deixa a suíte verde**. Ele estava escondendo um erro de verdade: os dois
outros cenários produzem `net::ERR_ABORTED` no **nosso próprio `POST`** de telemetria — 1 vez no
cenário do `window.onerror`, **10 vezes** no cenário do teto por sessão.

A tentação é declarar isso como artefato de teardown. **Não é**, e a sonda de tempo mostra:

```
844.7ms  response 204 /telemetry        <- servidor respondeu
845.1ms  reportWidgetError resolveu
857.2ms  servidor recebeu (confirmado)
886.1ms  requestfailed net::ERR_ABORTED  <- 41 ms DEPOIS do 204
2425.0ms page.close                      <- 1,5 s DEPOIS do abort
```

O `ERR_ABORTED` acontece com a página **viva**, 41 ms depois de uma resposta **bem-sucedida**.
Causa: `reportWidgetError` nunca lia o corpo da resposta, e o Chromium cancela o stream que ninguém
consome.

Duas hipóteses foram testadas e uma delas caiu:

| Experimento | Resultado |
|---|---|
| tirar `keepalive: true` | `ERR_ABORTED` **continua** — não é o keepalive |
| consumir a resposta (`await resposta.text()`) | **nenhum `requestfailed`**, some por completo |

**Por que isso é defeito de produto e não ruído de teste:** o aceite do bloco 2.13 é *«nada vaza
para o site do cliente»*. Nada chega ao `window.onerror` dele — mas a aba **Network** do devtools
dele passa a mostrar a nossa telemetria em vermelho, como requisição falhada, **dez vezes seguidas**
no cenário do laço. É a nossa observabilidade parecendo quebrada dentro do site de outra empresa.

**Correção:** `app/javascript/widget/helpers/telemetry.js` drena a resposta com
`await resposta?.text?.()`. Encadeamento opcional porque o dublê de `fetch` do jsdom não é um
`Response` de verdade — o que se quer é *«se veio corpo, drene»*, não *«assuma que veio»*.

### 1.4 Prova de que o teste ACUSA

Com a correção do escape **já aplicada** e **só** a linha da drenagem removida:

```
✘  4 … › o erro registrado não aparece no `window.onerror` do pai
     Error: A página produziu 1 rede.  ← "rede: POST …/telemetry — net::ERR_ABORTED"
✘  6 … › o teto por sessão impede o widget de virar amplificador
     Error: A página produziu 10 rede. ← dez vezes o mesmo
  2 failed, 4 passed
```

Devolvendo a linha: **6 passed**. E em jsdom, o teste novo
`drena a resposta — corpo não lido vira ERR_ABORTED no site do cliente` dá
**1 failed | 17 passed** sem a correção e **18 passed** com ela.

Os dois cenários de navegador agora rodam **sem escape nenhum** — qualquer erro que volte a
aparecer neles reprova.

---

## 2. Gatilhos — uma causa, treze falhas

### 2.1 A causa

`spec/e2e/triggers/harness/entry.js` monta a `TriggersPage` com um store falso que registra
`inboxes/*` e `globalConfig/get`. **Não registra `campaigns/*`.** Dois filhos da tela leem dali:
`TeaserComposer` (4.05) e `LegacyCampaigns` (4.22). `useMapGetter` devolve `undefined`, e:

```
PAGEERROR: Cannot read properties of undefined (reading 'find')
   at ComputedRefImpl.fn (…/triggers/TeaserComposer.vue:46:19)
```

A tela morre no mount, nenhum `data-testid` chega ao DOM, e os 13 testes reprovam no
`waitForSelector('[data-testid="approach-bold"]')`.

**Isso não é sabotagem deliberada** (o padrão de `spec/e2e/widget/fixture.sabotage.js`, onde a falha
é o resultado correto): `spec/e2e/triggers/` tem só `entry.js` e `triggers-server.mjs`, e nenhum dos
dois declara sabotagem.

### 2.2 De que lado estava o erro

**Do harness.** O módulo `campaigns` do painel real está **sempre** registrado
(`dashboard/store/index.js:17,89`) e `getLiveChatCampaigns` sempre devolve array. Em produção o
`undefined` não acontece. Endurecer os componentes com `?? []` mascararia um módulo ausente sem
consertar nada — o defeito era o dublê incompleto.

Registrados: `campaigns/getLiveChatCampaigns` (lista **vazia** — o estado de uma inbox que ainda não
tem campanha de chat ao vivo, que é estado real do painel), `campaigns/getUIFlags`, e as actions
`campaigns/update` e `campaigns/get`. O que depende de campanha vinculada já é coberto em jsdom por
`triggers/specs/TeaserComposer.spec.js` e `triggers/specs/LegacyCampaigns.spec.js`.

### 2.3 Um perigo achado no caminho: a porta 3062 servindo OUTRA árvore

`triggers-server.mjs` calcula `repositoryRoot` a partir do próprio caminho, e a config tinha
`reuseExistingServer: true` numa porta fixa. Durante esta task havia um servidor vivo na 3062 com
`cwd = /home/chatwoot/chatwoot` — **outra árvore**. A suíte teria medido o código de outra worktree
sem uma linha de aviso.

Corrigido sem tomar o slot de ninguém:
- `TRIGGERS_PORT` configura a porta (default **3062**, então nada muda para quem roda de um checkout
  só); a porta do HMR acompanha (`PORT + 1000`);
- `/__ready` passa a responder **qual árvore serve** — `triggers-ready /home/chatwoot/chatwoot-spx-tela4-tracking` —
  que é a única forma de conferir isso de fora.

---

## 3. Vermelho e verde, lado a lado

```
# gatilhos, ANTES
13 failed
  … todos por: page.waitForSelector: Test timeout of 60000ms exceeded
  … e o fixture acusando: pageerror: Cannot read properties of undefined (reading 'find')
                          at …/TeaserComposer.vue:46:19

# gatilhos, DEPOIS
11 passed (5.1m)
 2 failed  ← axe-core, tema light e dark; §4
```

```
# telemetria, ANTES              # telemetria, DEPOIS
4 passed, 2 failed               6 passed (7.5s)
```

---

## 4. O que FICOU DE FORA, e por quê

As 2 falhas restantes de gatilhos são o mesmo teste (`axe-core não acusa violação crítica ou
séria`) nos dois temas. São **defeito real**, e estavam escondidos atrás do erro do harness. Nenhum
está na tela de gatilhos: os três apontam para componentes **compartilhados** de `components-next`,
fora da lista "ARQUIVOS QUE SÃO SEUS" desta trilha.

| Componente | Regra | Impacto | O que o axe mede |
|---|---|---|---|
| `components-next/radioCard/RadioCard.vue` | `label` | **critical** | 5 nós. O `<input type="radio">` não tem nome acessível nenhum — sem `<label>`, sem `aria-label`, sem `aria-labelledby`, sem `title`. Para leitor de tela o cartão é um radio anônimo |
| `components-next/tabbar/TabBar.vue` | `color-contrast` | serious | 2 nós, **só no tema claro**: `text-n-blue-11` = `#2dc46f` (verde da marca) sobre `#f0f2f5` → **2,02:1**, contra 4,5:1 exigido |
| `components-next/avatar/Avatar.vue` | `color-contrast` | serious | 1 nó, só no claro: iniciais `#008573` sobre `#ccf3ea` → **3,81:1** |

Os três são renderizados pelo preview do widget, que a trilha de *appearance* também usa;
`RadioCard` tem **10 consumidores**, entre eles `appearance/ThemeModeField.vue` e
`appearance/LauncherField.vue`, que são de outra trilha.

Os dois de contraste são decisão de **paleta do design system**, não desta tela — e a base já sabe
disso: `LegacyCampaigns.vue` traz, em comentário, a medição dos pares `amber` (4,25:1) e `slate`
(4,14:1) com a nota de que *«a medição está roteada ao dono do design system»*.

O `label` do `RadioCard` é o único dos três que é puro cabeamento de acessibilidade: dar `id` ao
`<h3>` que já é o rótulo visível e apontar o `<input>` para ele com `aria-labelledby`. Zero pixel de
diferença, conserta os 10 consumidores de uma vez.

**A autorização foi pedida e não veio:** o `orca orchestration ask` com as três opções expirou sem
resposta (1.080 s). Sem ela, editar um componente com 10 consumidores enquanto outras trilhas rodam
em paralelo é o caminho conhecido para uma trilha apagar a outra — então os três ficaram **de fora,
diagnosticados e com o patch do `RadioCard` pronto para aplicar**. Nada foi afrouxado no teste para
fechar o item: as 2 falhas continuam vermelhas e nomeadas.

### 4.1 O que aplicar, quando houver autorização

```vue
<!-- components-next/radioCard/RadioCard.vue -->
<h3 :id="`${id}-label`" class="text-heading-3 text-n-slate-12">{{ label }}</h3>
...
<input :id="`${id}`" :aria-labelledby="`${id}-label`" ... />
```

Os dois de contraste **não** têm patch proposto de propósito: mexer em `text-n-blue-11` ou nas cores
do avatar é decidir a paleta do produto inteiro, e essa decisão não é desta trilha.
