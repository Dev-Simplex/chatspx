# Bloco 2.18 (frente `sdk.js`) fechado · e a fronteira real do 6.04 · 27/08/2026

> **Uma frase.** O `sdk.js` entrou no teto **cru** — 42.969 → **37.879 B**, com **2.121 B de
> folga** — e com isso `node scripts/widget-size.mjs` sai **VERDE nos quatro eixos** pela
> primeira vez; o **6.04 não foi implementado**, e não por falta de folga: o lançador e o teaser
> **nascem dentro do `onLoad`**, que só existe depois que o iframe carregou, então "adiar o
> iframe até o primeiro clique" hoje é adiar o próprio botão que deveria receber o clique.

---

## 1. Os números

Medido em build real, com os **dois** bundles reconstruídos — o `bin/vite build` principal
**não** refaz `public/packs/js/`, e é aí que mora o `sdk.js`:

```
npx vite build --config vite.lib.config.ts       # sdk.js
npx vite build --config vite.tracking.config.ts  # tracking.js
bin/vite build                                   # manifest do grafo
node scripts/widget-size.mjs
```

| Medida | Entrada desta trilha | Saída | Teto | Situação |
|---|---:|---:|---:|---|
| **`sdk.js` cru** | 42.969 B | **37.879 B** | 40.000 | ❌ → ✅ **folga 2.121 B** |
| **`sdk.js` gzip** | 14.339 B | **12.368 B** | 15.000 | ✅ folga **2.632 B** |
| JS eager do first-paint (grafo) | 289.564 B gzip | 289.564 B gzip | 300.000 | ✅ folga 10.436 B |
| Leaflet fora do first-paint | OK | OK | — | ✅ |
| `npx size-limit` | falhava no cru | **passa** | — | ✅ |

**Veredito do gate: `VERDE — teto do grafo, trava do Leaflet e os dois tetos do sdk.js passam.`**
com `exit 0`.

**Nenhum teto foi tocado.** `LIMITS` está idêntico ao que estava. **`GRAPH_BASELINE` também não
foi tocado**, e isso é deliberado: o grafo mediu 50 B abaixo da base de 24/08, e 50 B está dentro
da tolerância de ruído de 256 B que o próprio arquivo declara — nada nesta trilha toca o grafo do
widget, então baixar a régua aqui seria me creditar uma melhoria que não fiz.

---

## 2. Onde estavam os 5.090 B

Medido com **`chunk.modules` do Rollup** (`VITE_CHUNK_STATS=tmp/stats-sdk.json`), nunca com
`grep` no bundle — procurar o nome de um pacote no arquivo gerado acha atributo de SVG, string de
licença e comentário, e o rótulo do chunk não prova o conteúdo.

O `sdk.js` tinha **37 módulos, 141.846 B renderizados**. Cinco deles eram um pacote só:

| Módulo | B renderizados |
|---|---:|
| `md5/md5.js` | 6.299 |
| `crypt/crypt.js` | 3.202 |
| `charenc/charenc.js` | 1.031 |
| `is-buffer/index.js` | 871 |
| wrappers de CommonJS (`?commonjs-module`, `?commonjs-es-import`, `commonjsHelpers`) | 284 |
| **total** | **11.687** |

E ele tinha **um único consumidor no repositório inteiro**:

```
app/javascript/sdk/cookieHelpers.js:57
export const computeHashForUserData = (...args) => md5(getUserString(...args));
```

chamado de um lugar só, `entrypoints/sdk.js:289`, dentro de `setUser`.

### 2.1 Por que esse hash não precisava ser MD5

Ele responde **uma pergunta só, dentro do navegador do próprio visitante**: *"os dados que o site
está me passando agora são iguais aos da última vez?"*. O valor vai para o cookie
`cw_user_<websiteToken>` e nunca sai dali — não autentica nada, não viaja para o servidor, não é
comparado com nada produzido em outro lugar. Confirmado por varredura: **nenhum arquivo `.rb` ou
`.erb` menciona `cw_user_`**. O `identifier_hash` que de fato autentica é HMAC-SHA256 feito no
backend do cliente e não passa por aqui.

Ou seja: resistência a colisão **adversária** não é requisito; resistência a colisão **acidental**
é — e 128 bits dão isso de sobra.

### 2.2 Por que não um "MD5 em ESM com digest idêntico"

O relatório de 24/08 (§5) recomendou trocar por um MD5 em ESM preservando o digest, para não
invalidar os cookies em circulação. Medi as duas saídas e fui pelo outro caminho:

| Opção | custo no `sdk.js` cru | folga contra o teto |
|---|---:|---:|
| stub vazio (só para medir o piso) | — | 37.407 B → 2.593 |
| **`dedupeHash` de 128 bits (o que entrou)** | **+472 B** | **37.879 B → 2.121** |
| MD5 em ESM (implementação típica minificada ~1,5–2 kB) | +1.500 a +2.000 B | ~38.9–39.4 kB → ~600–1.100 |

O digest idêntico compraria "nenhum cookie invalidado" por **três a quatro vezes mais bytes**, e o
que ele evita custa pouco: na primeira carga depois do deploy, cada visitante já identificado emite
**um** `set-user` a mais. Isso é o **lado seguro do erro** — identificar de novo é idempotente no
servidor, deixar de identificar não seria — e acontece uma vez só, porque o cookie é regravado no
formato novo em seguida. Com o 6.04 pendurado neste bloco e precisando de folga, os ~1,5 kB de
diferença valem mais que a re-identificação única.

### 2.3 O que entrou

`app/javascript/sdk/dedupeHash.js` — cyrb128: quatro acumuladores de 32 bits com constantes ímpares
distintas, misturados a cada caractere e de novo no fim, devolvidos como 32 hex (o mesmo formato e
o mesmo tamanho que o MD5 devolvia). Sem dependência, sem `BigInt`, e **sem mexer no `target` do
build** — a nota do `vite.lib.config.ts` sobre não trocar compatibilidade do navegador do visitante
por bytes continua valendo. `Math.imul` é ES6 e roda em tudo que o `target` atual já assume.

---

## 3. O teste acusa — provado com o vermelho na mão

`app/javascript/sdk/specs/dedupeHash.spec.js`, **24 casos**. Um hash de dedupe errado não quebra
nada visível: ele silenciosamente para de emitir `set-user` (colisão) ou passa a emitir sempre
(instabilidade), e nos dois casos a suíte fica verde. Por isso cada bloco do spec **nomeia o hash
errado que ele reprova**, e cada um foi rodado contra a mutação correspondente:

| Mutação aplicada ao `dedupeHash.js` | Vermelhos de 24 |
|---|---:|
| hash pelo **comprimento** da entrada (`hex8(len).repeat(4)`) | **16** |
| **32 bits disfarçados de 128** (`hex8(h1).repeat(4)`) | **9** |
| **`Math.imul` trocado por `*`** (perde os bits altos) | **7** |

O teste de colisão usa **200.000 entradas distintas**: com 128 bits a probabilidade de colisão é
~5e-29; com 32 bits o esperado são ~4,6 colisões, e foi ele que pegou a segunda mutação.

Os **vetores congelados** existem porque o valor viaja no cookie do visitante: trocar o algoritmo de
novo invalida todos os cookies em circulação, e isso tem de ser **decisão**, não descuido — uma
constante trocada ou um `>>>` virando `>>` passa despercebido sem eles.

**Suíte do SDK inteira: 27 arquivos, 352 testes, verde.** (Os `ReferenceError: document is not
defined` no log são ruído de teardown do jsdom em `DOMHelpers.js:64`, preexistentes e não tocados
por esta trilha.)

---

## 4. O que continua fora do aceite literal do 2.18 — e por quê

O aceite escrito na tabela mestra §2.2 é **"JS eager ≤ 150 KB gzip; `window.__SENTRY__` e
`window.amplitude` undefined dentro do iframe"**. Ele **continua não alcançado**, e o que falta
**não está mais no `sdk.js`**:

| Item do aceite | Situação | Onde mora o que falta |
|---|---|---|
| `window.amplitude` undefined | ✅ desde 24/08 | — |
| `window.__SENTRY__` undefined | ❌ 39 módulos de `@sentry/core` no first-paint | `widget/composables/useAvailability.js` → `dashboard/composables/useTransformKeys` |
| JS eager ≤ 150 KB gzip | ❌ 289.564 B | `widget/App.vue`, `widget/helpers/axios.js`, `shared/composables/useMessageFormatter.js`, `shared/store/globalConfig.js`, `widget/helpers/campaignHelper.js` |

Todos em `app/javascript/widget/**`, `app/javascript/shared/**` e `app/javascript/dashboard/**` —
fora da propriedade de arquivo desta trilha (`sdk/**` e a configuração de build). A §5 do relatório
de 24/08 já tinha medido item a item e concluído que **as três frentes nomeadas no plano não
alcançam os 150 KB**: somadas dão ≈161,7 KB.

**O que esta trilha fechou é o gate**, nos quatro eixos que ele cobra. É a régua que roda no CI e a
que protege 100% dos visitantes; o aceite dos 150 KB é mais apertado que ela e depende de outra
trilha.

---

## 5. O 6.04 (facade) — não implementado, e a razão não é a que o plano supõe

O plano prende o 6.04 a `1.08 + 2.18` porque *"facade sobre bundle gordo troca 'pesado sempre' por
'lento quando abre', que é pior para quem abre"*. Essa condição **está satisfeita agora**. Mas há
uma segunda dependência, que nenhum documento registra, e ela é dura.

### 5.1 O lançador e o teaser não existem antes do iframe

Medido na árvore, sem ambiguidade:

```
IFrameHelper.js:634   createBubbleHolder(...)          <- cria o LANÇADOR
IFrameHelper.js:715   montarTeaserSeConfigurado(...)   <- cria o TEASER
IFrameHelper.js:607   ...os dois estão DENTRO de onLoad
IFrameHelper.js:394   onLoad só é chamado por events.loaded
                      = o postMessage que o app Vue manda DE DENTRO do iframe
IFrameHelper.js:104   createFrame — chamado uma vez, em entrypoints/sdk.js:504
```

O plano descreve o estado desejado — *"o lançador e o teaser continuam no host, leves, **como já
estão**"* — mas hoje eles **não** estão assim: eles nascem depois que o iframe carregou e mandou
`tokens`, `widgetAppearance`, `widgetTriggers` e `teaserText` pela ponte, tudo serializado em
`app/views/widgets/show.html.erb`.

**Consequência direta:** adiar o `createFrame` até o primeiro clique não adia nada — **não existe
lançador para clicar**. E o aceite pede literalmente *"o teaser continua aparecendo **sem** carregar
o app"*, que pelo mesmo motivo é impossível hoje.

### 5.2 Não há endpoint leve para substituir a ponte

- `POST /api/v1/widget/config` (`Api::V1::Widget::ConfigsController#create`) **cria `contact_inbox`**
  — criar contato antes do clique é o oposto exato do que o facade quer.
- `GET /widget` (`WidgetsController`) **é** o documento do iframe.

O facade precisa de um **GET público, leve e cacheável** que devolva só o subconjunto do lançador
(tokens, `widgetAppearance`, `widgetTriggers`, `teaserText`, `hideMessageBubble`) **sem efeito
colateral**. Isso é `config/routes.rb` + `app/controllers/**` + um serializer — **fora da
propriedade de arquivo desta trilha**.

### 5.3 E há um custo funcional, que é decisão de produto

Com o app só carregando no clique, ficam **mortas até lá** superfícies que hoje são empurradas do
iframe pela ponte:

| O que morre até o primeiro clique | Onde |
|---|---|
| campanhas proativas (é o produto abordando quem não clicou) | `widget/store/modules/campaign`, `App.vue:206` |
| badge de não lidas no lançador | `IFrameHelper.events.handleNotificationDot` (`:574`) |
| som de notificação e o piscar do título | `IFrameHelper.events.playAudio` (`:594`) |
| rótulo configurado do lançador | `IFrameHelper.events.setBubbleLabel` (`:491`) |

Ou seja: o facade não é só "carregar mais tarde" — ele **desliga a proatividade do produto** até o
visitante clicar. Isso pode ser exatamente o que se quer (é o custo padrão de um facade), mas é
**decisão de produto**, não escolha de implementação, e não está registrada em lugar nenhum.

### 5.4 O que não foi feito, e por quê

Nada do 6.04 foi escrito. As três saídas possíveis foram levadas ao coordenador
(`orca orchestration ask`, com o diagnóstico acima) e **não houve resposta** dentro da janela desta
trilha:

1. **Liberar o backend** — o GET leve de config do lançador mais todo o lado do host. É a única que
   atende o aceite escrito, e precisa de arquivos declarados como não-meus.
2. **Só o lado do host**, atrás de flag desligada, consumindo uma interface sem produtor. Seria
   código morto: pior que não escrever.
3. **Não fazer agora** e registrar o bloqueio — foi o que aconteceu.

**A dependência real do 6.04, para o planejamento, é: `1.08` + `2.18` + um endpoint de config do
lançador + a decisão sobre a proatividade.** As duas últimas não estão na coluna "Depende" da
tabela mestra, e é isso que faz o bloco parecer menor do que é.

Uma parte do aceite, aliás, **já está satisfeita** e não custa nada: *"o visitante que clica duas
vezes rápido não instancia dois iframes"* — `createFrame` abre com `if (IFrameHelper.getAppFrame())
return;` (`IFrameHelper.js:105`).

---

## 6. Arquivos

**Novos:** `app/javascript/sdk/dedupeHash.js`, `app/javascript/sdk/specs/dedupeHash.spec.js`.

**Alterados:** `app/javascript/sdk/cookieHelpers.js` (o import e a linha 57),
`vite.lib.config.ts` (só o comentário do teto, com a trajetória medida).

**Deliberadamente NÃO alterados:**

- `package.json` / `pnpm-lock.yaml` — o `md5` continua declarado. Removê-lo exigiria o lockfile,
  que é arquivo compartilhado com as trilhas em paralelo. A trava contra ele voltar não é uma
  declaração e sim uma **medição**: com o `md5` de volta o cru vai a 42.969 e o gate fecha a porta.
- `scripts/widget-size.mjs` — `LIMITS` e `GRAPH_BASELINE` intocados (§1).
- `public/version.json` — regravado pelo build, restaurado antes do commit.

**Nada foi pushado, nenhum PR foi aberto, nenhuma VM e nenhum banco de produção foram tocados.**
Commit local: `c18740b9ff`.
