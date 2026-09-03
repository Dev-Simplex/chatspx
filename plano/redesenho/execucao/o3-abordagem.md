# Onda 3 · ABORDAGEM — degradação, auto-open e instrumentação

> **Worktree:** `/home/chatwoot/chatwoot-o1-widget` · **branch:** `o1-widget`
> **Blocos:** 4.19 (degradação por familiaridade) · 4.20 (auto-open opt-in) · 4.21 (instrumentação)
> **Base:** `c7a0c2641f` — o 4.06 fechado (relatório em `onda-4-teaser.md`)
> **Data:** 19/08/2026
>
> **Regra que rege este arquivo:** todo aceite tem um **mecanismo executado**, e onde havia risco de
> falso verde há **controle negativo** — a sabotagem, a saída vermelha dela, e o verde de volta.

---

## ⚠️ PRIMEIRO, O TETO: o número do briefing não é o número que o CI cobra, e não é ele que aperta

O briefing manda medir `sdk.js` contra **15.360 B gzip**. Medi contra o gate, que é quem reprova:

```
scripts/widget-size.mjs:82    sdkGzip: 15_000,   // A13 — protege o visitante
scripts/widget-size.mjs:83    sdkRaw:  40_000,   // A13 — protege o parse
```

**São dois desencontros, e o segundo é o que muda o projeto.**

1. **O teto gzip do gate é 15.000 B, não 15.360.** A diferença é a unidade: A13 diz "15 KB gzip", o
   gate usa KB decimal (`// KB decimal (1 KB = 1000 B), a mesma unidade do size-limit`), e 15.360 é
   15 KiB. São **360 B** — projetar contra o número folgado e entregar em 15.100 daria verde na minha
   planilha e **vermelho no CI**.

2. **Não é o gzip que aperta. É o CRU.** O gate cobra os dois, e a medição de `HEAD`, antes de eu
   escrever uma linha:

```
                cru        gzip
sdk.js @ HEAD   39.031 B   12.720 B
teto            40.000 B   15.000 B
FOLGA              969 B    2.280 B
```

**A folga real para os três blocos era 969 B crus.** Em gzip pareciam 2.280 B (ou 2.640, pelo número
do briefing) — mas o compressor deste arquivo roda a ~3,07:1, então gastar os 2.280 B de gzip exigiria
~7.000 B crus, quatro vezes mais do que existia. **Quem manda é o teto cru, e o briefing não o cita.**

Registro isto no topo pela mesma razão que o 4.06 registrou a folga: descobrir com o código escrito
que o orçamento era um terço do anunciado é a surpresa cara que estes relatórios existem para evitar.

**Escalado ao coordenador, com o número:** o gate e o briefing discordam em 360 B, e a A13 discorda de
si mesma na unidade ("15 KB gzip" no texto, `15_000` no código). Uma das duas está errada e a decisão
é dele. **Não mexi no gate** — mudar teto para caber é exatamente o que a §4 proíbe.

---

## O RESULTADO EM BYTES — os três blocos couberam, e sobrou

Medição: build do `sdk.js` a cada etapa (`vite build --config vite.lib.config.ts`), gzip pelo mesmo
comando do gate (`gzip -c <arquivo> | wc -c`).

| etapa | cru | Δ cru | gzip | Δ gzip |
|---|---:|---:|---:|---:|
| **base** — `HEAD`, 4.06 fechado | 39.031 | — | 12.720 | — |
| 4.19 — degradação por familiaridade | 39.521 | **+490** | 12.946 | **+226** |
| *achado: `date-fns` fora do SDK* | 38.644 | **−877** | 12.565 | **−381** |
| 4.20 — auto-open opt-in | 38.901 | **+257** | 12.668 | **+103** |
| 4.21 — instrumentação (lado do host) | 39.173 | **+272** | 12.741 | **+73** |
| **TOTAL** | **39.173** | **+142** | **12.741** | **+21** |

**Os três blocos custaram 1.019 B crus de código novo e devolveram 877 B**, fechando em **+142 B
crus / +21 B gzip**. Folga que sobra: **827 B crus**, **2.259 B gzip**. Gate:

```
[3] sdk.js — a vantagem nº 1 (100% dos visitantes de todos os sites)
    cru ...............    39.173 B   teto 40.000 B   OK (folga 827 B)
    gzip ..............    12.741 B   teto 15.000 B   OK (folga 2.259 B)
```

**Sobre o método de medição.** O briefing pede a medição "com o trabalho no `stash`". Não usei
`git stash`: a pilha de stash é **do repositório**, compartilhada pelos 27 worktrees desta base, e
outro agente que dê `pop` leva o meu trabalho junto — é lição registrada. O equivalente exato foi
medir `HEAD` **antes de tocar em qualquer arquivo** e, no fim, reconstruir a base num
`git worktree add --detach HEAD` descartável. Os dois deram o mesmo número, **39.031 / 12.720**, e o
worktree foi removido.

---

## O ACHADO: o `date-fns` estava dentro do `sdk.js`, por uma soma de uma hora

Foi caçado, não tropeçado: com 479 B crus de folga depois do 4.19, fui procurar gordura no artefato
como o 4.06 fez com os comentários do `SDK_CSS`. Dentro do bundle, isto:

```
"Starting with v2.0.0-beta.1 date-fns doesn't accept strings as date arguments.
 Please use `parseISO` to parse strings. See: https://git.io/fjule"
```

Uma string de deprecação **em inglês, de 180 caracteres**, baixada por 100% dos visitantes de todos os
sites de todos os clientes, que nenhum deles jamais lê. Ela vinha junto de `toDate`, `toInteger` e
`requiredArgs` — o fecho de `date-fns/addHours` — e a única chamada era:

```js
IFrameHelper.js:82   const expireBy = addHours(new Date(), 1);   // cookie de soneca de campanha
```

Virou `new Date(Date.now() + 36e5)`. Semântica idêntica (`addHours` sobre um `Date` recém-criado é
soma de milissegundos), e **−877 B crus / −381 B gzip**.

**Por que isto vale além deste bloco.** É o mesmo padrão do achado do 4.06: o custo não estava no que
o bloco escreveu, estava no que o arquivo já carregava por descuido. `sdk.js` tem teto e **oito
blocos do plano acrescentam código eager a ele** (A13). Vale varrer o resto dos imports do grafo do
SDK antes que a Onda 5 chegue — não é o meu bloco e não fui além do que precisei.

---

## 4.19 — a degradação por familiaridade

**Arquivos:** `sdk/tracking/approach.js` (novo, 62 l.) · `sdk/IFrameHelper.js` · `sdk/cookieHelpers.js`

### O cookie guarda duas coisas, e o aceite cobra isso nominalmente

`cw_approach`, primeira parte, formato **`"<abordagens>.<0|1>"`** — quantas vezes abordamos e se
converteu. Nada mais. Sem timestamp (o prazo do cookie é o único relógio: 30 dias sem abordagem e o
estado some), sem identificador novo, sem perfil de navegação. É o que a arbitragem **A15** exige, e
o teste cobra o formato com expressão regular, não com um `toBeDefined()`.

A escada é um array e a degradação é uma soma de índice:

```js
const NIVEIS = ['aggressive', 'bold', 'discreet'];
export const degradar = (nivel, degraus) => NIVEIS[NIVEIS.indexOf(nivel) + degraus] || null;
```

Cair da escada é `undefined`, que vira `null` — "não aborde". Um `switch` de três casos custaria mais
bytes e diria a mesma coisa pior, e o arquivo tem teto.

### `lerAbordagem` devolve array, e isso é decisão de bytes

Nome de propriedade **sobrevive à minificação**; nome de variável local não. `{ abordagens, converteu }`
teria posto duas palavras longas no artefato quatro vezes. `[n, c]` desestruturado no chamador custa
zero. É o tipo de escolha que só faz sentido neste arquivo, e está comentada lá para que ninguém a
"melhore" em outro.

### O contador sobe quando ABORDAMOS, não quando a página carrega

O incremento está no `aoExibir`, que só dispara quando o teaser de fato apareceu. Visitante que abriu a
aba e foi embora antes dos 8 s, ou que pegou banner de cookie na tela, **não gasta um degrau da escada
por uma abordagem que não aconteceu**. Tem teste próprio.

### Uma decisão declarada: "já converteu" não sobrevive a uma abordagem nova

O par `(n, c)` descreve o **ciclo corrente**, não a vida inteira. Converter grava `0.1`; a abordagem
seguinte grava `1.0`. Consequência: `c = 1` só existe com `n = 0`, e o par distingue exatamente três
estados — visitante novo (`0.0`), visitante que converteu e teve o contador zerado (`0.1`), visitante
sendo abordado (`n.0`). A alternativa (preservar `c` para sempre) exigiria uma terceira informação
para não mentir, e o aceite diz **duas**.

### Os aceites, e o mecanismo de cada um

| Aceite | Mecanismo | ✓ |
|---|---|---|
| 1ª visita em `bold` mostra o grande | `woot-teaser--bold` no DOM, 3 visitas remontando o host | ✓ |
| **2ª sem conversão mostra o pequeno** | mesma sequência: `woot-teaser--discreet` | ✓ |
| 3ª não mostra nada | `holder.querySelector('.woot-teaser') === null` | ✓ |
| **Converter zera o contador** | `chatwoot:message-sent` pela ponte → cookie vai a `0.1`; a visita seguinte volta ao nível cheio | ✓ |
| Com `degrade_on_return: false` o nível não cai nunca | 3 visitas, `bold` nas três — **e o contador continua contando**, que é o que mantém o ordinal único na dedup do 4.21 | ✓ |
| Cookie com `secure` em HTTPS | par de asserções no `cookieHelpers.spec.js`: `true` em `https:` **e `false` em `http:`** | ✓ |
| 30 dias, pela helper de domínio | espião em `setCookieWithDomain`, com controle negativo (30→31 reprova) | ✓ |

**Controle negativo do bloco.** Sabotando `degradar` para ignorar o contador:

```
× bold: 1ª visita mostra o grande, 2ª o pequeno, 3ª não mostra nada
× a exibição vira dado, com o nível e o configurado separados
  Tests  2 failed | 13 passed (15)
```

Revertido: **15 passed**.

### O item 46 do gap analysis (P0) foi fechado para TODOS os cookies do SDK, não só para o novo

O `PLANO-MESTRE` registra o item 46 — *"cookie do SDK com `secure` quando a página é HTTPS"*,
classificado **P0** — como **absorvido pelo 4.19**. Pus a linha **dentro de `setCookieWithDomain`**, e
não como parâmetro do meu cookie:

```js
secure: window.location.protocol === 'https:',
```

Uma linha, e ela cobre os três cookies que o SDK grava (`cw_conversation`, `cw_teaser_dismissed`,
`cw_approach`). Tratar como parâmetro teria fechado o P0 só para o cookie que nasceu hoje e deixado os
dois antigos abertos — que é o defeito original intacto.

**A condição não é decoração.** `secure: true` fixo faria o navegador **descartar em silêncio** o
cookie em todo site que ainda serve HTTP, e o widget perderia a sessão do visitante sem um erro no
console. Por isso o teste afirma as duas metades: liga em HTTPS **e fica desligado em HTTP**.

Cinco testes existentes de `cookieHelpers.spec.js` ficaram vermelhos com a mudança (afirmavam o objeto
de opções inteiro) e foram atualizados — é o comportamento novo, não uma regressão.

---

## 4.20 — o auto-open opt-in

**Arquivos:** `sdk/teaser.js` (refatorado) · `sdk/tracking/approach.js` · nada no dashboard

### O gatilho composto saiu de dentro do teaser, e o Agressivo consome o mesmo

O aceite manda o `aggressive` respeitar o gatilho composto do 4.06 (8 s **E** 30 % de rolagem). Um
segundo relógio, um segundo listener de rolagem e uma segunda detecção de banner de cookie seriam
**três chances de os dois níveis divergirem**, e o dobro de bytes. Então o gatilho virou
`armarGatilho(quandoDisparar)`, e os três níveis o consomem.

`montarTeaser` continua sendo a **porta única** — é lá que moram as duas recusas que valem para os
três níveis (`teaserEnabled: false` e dispensa persistida), e uma porta só é o que impede o Agressivo
de escapar delas.

### O Agressivo sai antes de qualquer `createElement`, e isso não é estilo

Construir o cartão para descartá-lo faria `foto.src = canal.avatarUrl` numa `<img>` que nunca entra na
página — e **o navegador baixa a imagem assim mesmo**. Seria uma requisição de rede por carregamento de
página, em todo visitante do site, para um elemento invisível. O `if (agressivo)` está acima da
construção inteira.

### "Uma vez por sessão" é `sessionStorage`, e a razão de não ser cookie

Dois motivos, e o segundo decide: `sessionStorage` é literalmente um armazenamento de sessão (não há
data de expiração para calcular nem para errar); e **cookie viaja em toda requisição ao domínio do
cliente** — um marcador que o servidor nunca lê não tem por que ser anexado a cada imagem e a cada
folha de estilo do site que nos hospeda.

**Consequência declarada:** `sessionStorage` é por **aba**, não por navegador. Três abas abertas
receberiam três auto-opens **se não houvesse o freio do 4.19** — que há: a primeira aba grava a
abordagem, a segunda lê o contador e cai para `bold`. Com `degrade_on_return: false` o administrador
desligou esse freio de propósito, e aí abre em cada aba. Está escrito no código.

O `try/catch` também não é decoração: `sessionStorage` **levanta** (não devolve `null`) quando o site
nos hospeda em iframe sem `allow-same-origin` ou com cookies de terceiros bloqueados. Sem ele, o boot
do SDK morre no site do cliente. Na dúvida, `false` — não abrir é o erro barato.

### "Em celular não liga por padrão, e o caminho está fechado nas duas pontas" — CONFERIDO, e virou três

O briefing manda conferir. Confiro, com o mecanismo de cada ponta:

| Ponta | O que fecha | Verificação |
|---|---|---|
| **Schema (3.20)** | `MOBILE_APPROACHES = %w[discreet bold]` — `aggressive` não está no enum | `spec/models/inbox_widget_approach_spec.rb` + `inboxes_controller_widget_config_spec.rb`: **422** com mensagem que nomeia o campo. **45 exemplos, 0 falhas**, rodados nesta task |
| **Resolução (3.20)** | `resolved_widget_approach` derruba mobile para `bold` mesmo com desktop `aggressive` | mesma suíte |
| **SDK (4.20, novo)** | no celular lê-se **`approach_mobile` e só ele** | teste com payload adulterado (`approach: aggressive` sem `approach_mobile`) em 375 px: **o painel não abre** |

A terceira ponta veio **de graça, e com bytes negativos**: o 4.06 tinha
`gatilhos.approach_mobile || gatilhos.approach`, e esse `||` era a brecha — bastaria um payload de
versão anterior, sem `approach_mobile`, para o celular herdar o `aggressive` do desktop. Removê-lo
encurtou a linha e fechou o caminho.

### `grep -rn "Google"` nas strings de i18n desta tela → **vazio**

```
$ grep -rn "Google" app/javascript/dashboard/i18n/locale/pt_BR/inboxWidget.json \
                    app/javascript/dashboard/i18n/locale/en/inboxWidget.json
grep-exit=1        (nada encontrado)
$ grep -rn "Google" app/javascript/dashboard/routes/dashboard/settings/inbox/widget/
grep-exit=1        (nada encontrado)
```

E há teste permanente disso, escrito pelo **4.04** — não por mim —, que varre as seções `TRIGGERS` e
`APPROACH` dos dois idiomas contra `/google|seo|ranking/i` e exige que a varredura tenha visto mais de
50 strings (senão um `grep` vazio por engano passaria por verde).

### A metade de dashboard do 4.20 JÁ ESTAVA PRONTA — entregue pelo 4.04

Auditei antes de escrever qualquer coisa, e não havia o que construir:

| O que o 4.20 pede da tela | Onde já está |
|---|---|
| Aviso antes de salvar | `ApproachSelector.vue:59-63` — escolher Agressivo **abre o diálogo e não emite nada**; só `confirmAggressive` grava |
| Três consequências, todas do visitante | `AutoOpenWarningDialog.vue` + `AUTO_OPEN_DIALOG.POINT_*` |
| Celular explicitamente em `bold` | `confirmAggressive` grava `approach_mobile: DEFAULT_APPROACH` |
| Sem menção a buscador | verificado acima |

**Então o 4.20 aqui é só a metade do SDK**, e é onde ele estava faltando: a política existia na tela e
**nada abria o painel**.

### `Esc` fecha o painel aberto por auto-open e devolve o foco ao lançador — VERIFICADO, com ressalva

O briefing diz "(2.11, já fechado)". **Está fechado — em `o5-composer`, que ainda não entrou em
`redesenho-integra`.** Confirmado:

```
$ git merge-base --is-ancestor 14822b4cd6 HEAD              → NÃO
$ git merge-base --is-ancestor 14822b4cd6 redesenho-integra → NÃO
$ git branch --all --contains 14822b4cd6                    → o5-composer
```

Podia ter deduzido que funciona (o auto-open entra pelo mesmíssimo `IFrameHelper.events.toggleBubble`
do clique, e o listener do 2.11 é do **documento**). Preferi executar. Coloquei o `closeOnEscape.js` do
2.11 ao lado deste código, só para a execução, e rodei o caminho inteiro — auto-open → `Esc` no iframe
→ `closeWindow` no host → foco:

```
✓ 4.20 × 2.11 — o painel aberto SOZINHO fecha no Esc
  ✓ auto-open → Esc → painel fechado e foco no lançador
```

**Controle negativo** (trocando o nível para `bold`, que não pode abrir sozinho):

```
× auto-open → Esc → painel fechado e foco no lançador
  → expected false to be true
```

O arquivo **não foi commitado neste branch** — ele importa um módulo que não existe aqui, e teste que
não roda é indistinguível de teste que passa. Ficou arquivado em
`execucao/dados/o3-abordagem-autoOpenEscape.check.spec.js`; **ele deve entrar em
`app/javascript/sdk/specs/` no merge que juntar `o5-composer` e `o1-widget`**, e é o único item de
handoff deste relatório.

Registro de passagem, porque o 2.11 tinha razão e vale para o meu bloco: o retorno de foco já
funcionava antes dele (`bubbleHelpers.js:264`, `chatBubble.focus()` em `handleBubbleToggle`). O que o
2.11 consertou foi o `Esc`, que estava num `<div>` e não recebia a tecla.

---

## 4.21 — a instrumentação dos três níveis

**Arquivos:** `sdk/IFrameHelper.js` (a ponte) · `widget/api/approachEvent.js` (novo) ·
`widget/bridge/handlers.js` · `widget/components/ChatFooter.vue` ·
`app/controllers/api/v1/widget/approach_events_controller.rb` (novo) · `config/routes.rb` ·
`docs/tracking/contrato-de-eventos.md`

### A decisão de arquitetura, e ela é decisão de bytes

O fato acontece no **host**: é lá que o teaser aparece, que o visitante dispensa e que o painel abre
sozinho. Mas o `sdk.js` tem teto e o iframe **não tem** — e dentro do iframe já existem `axios`, o
`X-Auth-Token` da sessão e o tratamento de erro.

Então o host paga só o `postMessage` (**+272 B crus**, a única parte que entra no orçamento) e o iframe
faz o resto de graça. O `X-Auth-Token`, aliás, **mora no iframe, que é onde ele deve morar** — replicar
a chamada no host exigiria expor o token à página do cliente.

### Os quatro eventos, e por que quatro

| Evento | Fato |
|---|---|
| `chatspx_approach_shown` | teaser apareceu, ou o painel abriu sozinho — **é o denominador** |
| `chatspx_approach_dismissed` | o visitante fechou |
| `chatspx_approach_opened` | o painel abriu a partir da abordagem |
| `chatspx_approach_converted` | o visitante **enviou mensagem** depois de ter sido abordado |

Os três parâmetros são `approach` (o nível **efetivo**), `approach_configured` (o que o administrador
escolheu) e `degraded` (derivado dos dois). O aceite pede os dois primeiros *"para separar o efeito da
degradação do efeito do nível"*; o terceiro é derivado no servidor e não recebido, porque **quem
calcula uma coisa a partir das outras duas não pode discordar delas**.

**O nome é composto pelo SERVIDOR.** O cliente manda a etapa (`shown`), nunca o nome. É a lição que o
`EventsController` desta base já carrega escrita — nome vindo do site do cliente ia direto para o
barramento —, e aqui um nome livre entraria no GA4 e no Meta **do cliente**.

**"Sem vocabulário novo" (A9), conferido:** a família usa o prefixo `chatspx_`, `snake_case`, ≤ 40
caracteres, e o sinal de conversão é `chatwoot:message-sent` — nome que **o contrato do 5.03 já
declarava** na §2 como sinal interno e que ainda não existia no código. Nasceu aqui, e o site do
cliente passa a recebê-lo de graça.

### O aceite em uma frase: "qual nível converte mais nesta conta", sem abrir console de ninguém

```sql
SELECT properties->>'approach' AS nivel, name, count(*)
  FROM tracking_events WHERE account_id = ? GROUP BY 1, 2;
```

Tem exemplo executando exatamente essa consulta e conferindo os quatro cruzamentos — inclusive o
`nil` de "`discreet` não converteu nenhuma vez", que é o que uma consulta honesta precisa devolver.

**"Exibição sem abertura também é registrada"** tem exemplo próprio: `shown` gravado, `opened` vazio.
Sem denominador não há medição.

### A ARMADILHA HERDADA — consumida, não contornada, e o vermelho está aqui

O briefing avisa: *"o job do dispatcher é retentado, e o 5.03 travou a idempotência do fato com índice
único em `(account_id, name, dedup_key)`. Consuma essa trava."*

**Aqui a retentativa não vem de um job — vem da rede e do próprio visitante.** Reenvio do POST;
`handleSendMessage` disparado três vezes porque a pessoa mandou três mensagens seguidas. A trava é a
mesma, e o jeito de consumi-la é passar `dedup_key` **explicitamente**:

```ruby
dedup_key: "approach:#{@contact_inbox.source_id}:#{ordinal}"
```

O `ordinal` é a ordem da abordagem na vida daquele navegador. **Não é identificador novo** — é o
contador que o cookie do 4.19 já mantinha, atravessando a ponte. O `source_id` vem do **token**, nunca
do corpo: aceitá-lo do corpo deixaria um cliente adulterado colidir com a chave de outro visitante e
**apagar o evento dele** — a dedup viraria ferramenta de suprimir dado alheio.

**Sabotagem — removendo a linha `dedup_key:`, com a derivação padrão assumindo:**

```
16 examples, 3 failures

× tres mensagens seguidas do visitante sao UMA conversao
× a chave deriva do FATO, nao do relogio: o mesmo ordinal colide mesmo em segundos diferentes
× ordinais diferentes sao fatos diferentes — a abordagem seguinte NAO e engolida
```

Restaurada: **16 examples, 0 failures**.

Os três vermelhos mostram que o dano tem **dois sentidos opostos**, e é isso que a derivação padrão
esconde:

- **conta demais** — a derivação usa `occurred_at.to_i`, e o reenvio cai noutro segundo: uma conversão
  vira três;
- **conta de menos** — duas abordagens **genuínas** ao mesmo visitante dentro do mesmo segundo
  compartilham a chave derivada e viram uma linha só.

### Uma afirmação minha que o controle negativo derrubou, e que eu corrigi

O comentário que escrevi primeiro no controller dizia que, sem a chave explícita, a derivação padrão
**misturaria visitantes diferentes** ("o assunto cairia para `'account'`, porque abordagem não tem
conversa"). A sabotagem provou que **não**: o exemplo "dois visitantes no mesmo segundo" continuou
verde sem a chave, porque este endpoint passa `contact:` e a derivação usa `contact_id`.

História boa, e falsa. O comentário do controller e a §2.1 do contrato foram corrigidos para dizer o
que a sabotagem mostra, e o exemplo "dois visitantes" foi rebatizado como **propriedade do endpoint,
não prova da chave** — com a razão escrita no próprio spec, para que ninguém o cite como evidência do
que ele não mede.

### PII: nenhuma, e não por sorte

`properties` tem exatamente três chaves, todas do vocabulário fechado de `WidgetTriggersSchema::APPROACHES`,
nenhuma vinda do cliente em texto livre. Tem exemplo que afirma **o conjunto exato de chaves** — não um
"não contém e-mail", que passaria verde com uma chave nova qualquer amanhã.

---

## O CONTRATO DO 5.03, LIDO CONTRA O CÓDIGO — **CASA**, com três divergências pequenas

O briefing manda ler e dizer. Li `docs/tracking/contrato-de-eventos.md` inteiro contra o código:

| O que o contrato diz | O que o código faz | ✓ |
|---|---|---|
| §1 — nome: prefixo `chatspx_`, `snake_case`, ≤ 40, recusado na gravação | `TrackingEvent:121-124`, três `errors.add` que nomeiam a regra | ✓ |
| §1 — o registro **não** valida contra a lista fechada da §2 | não há tal validação | ✓ |
| §3.1 — 11 campos, tipos, nulos e defaults | `schema.rb:2156-2176`, um a um | ✓ |
| §3.1 — único em `event_id`; único em `(account_id, name, dedup_key)`; BRIN em `occurred_at` | `index_tracking_events_on_event_id` (unique), `..._on_dedup` (unique), `..._on_occurred_at_brin` (brin) | ✓ |
| §3.1 — FKs: conta `CASCADE`, inbox/conversa/contato `SET NULL` | `schema.rb:2379-2382`, exatamente | ✓ |
| §3.2 — 13 campos de `tracking_deliveries` + único em `(tracking_event_id, destination)` | `schema.rb:2138-2154` | ✓ |
| §4.1 — `event_id` UUID v4 do servidor, em todo registro | `ensure_event_id` → `SecureRandom.uuid` | ✓ |
| §4.2 — `dedup_key` determinística; `record!` devolve o existente sem erro | `derive_dedup_key` + `rescue RecordNotUnique → find_by!`; **exercitado pelos meus exemplos** | ✓ |
| §4.3 — `claim_delivery` devolve `nil` na corrida, com savepoint | `TrackingEvent:89-95` | ✓ |
| §5 — assinatura de `record!` | `Tracking::EventRecorder:17-18`, nome por nome | ✓ |
| §6.3 — nove chaves de PII recusadas, varredura em profundidade | `PII_KEYS` + `find_pii_key` recursivo | ✓ |

**As três divergências, todas documentais e nenhuma bloqueante:**

1. **§2 dizia "acrescentar um evento ao listener custa *uma linha* no mapa de `TrackingEventListener`".**
   **Não há mapa.** O listener segue a convenção do `BaseListener` — **um método por fato**
   (`conversation_resolved`), e o comentário do próprio arquivo diz "custa um método com o mesmo
   formato", contradizendo o documento. Um doc que promete "uma linha num mapa" manda a próxima trilha
   procurar uma estrutura que não existe. **Corrigido no contrato.**
2. **§3.1 declara `event_id` como `string(36)`; a coluna não tem limite** (`t.string "event_id"`).
   Inofensivo hoje (UUID tem sempre 36), mas o contrato afirma uma garantia que o banco não dá.
   **Registro; não mexi na migration** — mudar coluna por causa de documentação é decisão do 5.03.
3. **§3.2 não lista o índice `index_tracking_deliveries_on_status`, que existe.** Sobra no código, não
   no documento — a lista de índices do contrato é incompleta, não errada.

**O contrato foi atualizado para a versão 2**, com a §2.1 nova (a família da abordagem: os quatro
nomes, os três parâmetros, a `dedup_key` e sua razão medida). É o que a regra do próprio documento
manda: *"mudança de nome, tipo ou default de campo muda este arquivo primeiro"*.

---

## Um defeito meu, pego por teste antes de sair daqui

A validação de nível do controller nasceu assim:

```ruby
(WidgetTriggersSchema::APPROACHES & [approach, approach_configured]).size == 2
```

Parece certo e recusa **o caso normal**: quando o nível não foi degradado, os dois são iguais, e
`%w[discreet bold aggressive] & %w[bold bold]` devolve **um** elemento. Toda abordagem não degradada
seria recusada com 422 — quer dizer, a maioria dos eventos, e justamente o baseline contra o qual a
degradação seria comparada.

Quem pegou foi o exemplo `degraded: false`, escrito porque o aceite fala em **separar** os dois
efeitos. Virou `all? { |nivel| APPROACHES.include?(nivel) }`, com a razão escrita no código.

---

## Suítes

| Suíte | Resultado |
|---|---|
| `vitest` — `sdk/` + `widget/` | **77 arquivos, 749 testes, 0 falhas** |
| `rspec` — abordagem, 3.20, tracking (5.03) | **112 exemplos, 0 falhas** |
| `eslint` — arquivos tocados | **0** |
| `rubocop` — Ruby novo + `routes.rb` | **0 ofensas** |
| `scripts/widget-size.mjs` | `sdk.js` **OK** nos dois tetos; grafo vermelho por **dívida conhecida**, sem regressão nova |

O rspec rodou em banco dedicado (`chatwoot_test_o1widget`) — este worktree não tem `.env`, e sem
credencial o rspec sai `0 examples` com cara de verde. **Os números acima são de execução com N > 0.**

**Dois testes já vermelhos que NÃO são meus, e a verificação disso.**
`dashboard/.../specs/inboxWidgetI18n.spec.js` reprova em `triggers.enabled` e `triggers.triggers`
("expected undefined to be type of 'string'"). Não toquei em nada de dashboard —
`git diff --stat HEAD -- app/javascript/dashboard/` sai **vazio**, e o `inboxWidget.json` é
**byte a byte idêntico** ao de `HEAD`. É dívida herdada, de quem entregou aquele arquivo de i18n, e
está registrada aqui para não virar surpresa no merge.

---

## O que fica para o coordenador

1. **Decidir o teto.** O gate cobra **15.000 B** gzip; o briefing e o relatório do 4.06 usam **15.360 B**;
   a A13 diz "15 KB gzip" no texto e `15_000` no código. **E o teto que realmente aperta é o cru
   (40.000 B), que o briefing não cita** — era ele que tinha 969 B de folga, não os 2.640 que o número
   de gzip sugeria. Não mexi em nada disso.
2. **Levar o `autoOpenEscape.check.spec.js`** de `execucao/dados/` para `app/javascript/sdk/specs/`
   quando `o5-composer` (2.11) entrar em `redesenho-integra`. É o único handoff deste relatório.
3. **Varrer os imports do grafo do SDK.** O `date-fns` devolveu 877 B crus por uma soma de uma hora. É
   o segundo achado desse tipo em dois blocos (o primeiro foram os comentários dentro do `SDK_CSS`), e
   os dois vieram de procurar, não de tropeçar. Com oito blocos ainda por acrescentar código eager,
   uma varredura dirigida agora é mais barata que um estouro na Onda 5.
4. **Os dois testes de i18n do dashboard já estão vermelhos em `HEAD`** — têm dono, e não é este bloco.
