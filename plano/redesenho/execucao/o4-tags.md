# Onda 4 · Ponte de tags — trilha `o4-resto`

**Worktree:** `/home/chatwoot/chatwoot-o4-resto` · **Data:** 19/08/2026 · commitado localmente, não pushado

> **Este relatório substitui um que eu apaguei.** Ver §0 antes de qualquer coisa.

| Commit | O que é |
|---|---|
| `0bd642f871` | a implementação desta trilha para 5.05/5.10/5.16 — **revertida** |
| `add255156c` | o revert, com a causa escrita |
| `f4f3257426` | merge de `redesenho-integra` (traz a implementação que fica, `0e11a04109`) |
| `36924a392e` | **o que sobrou de valor**: o check de navegador + 4 vermelhos que o merge deixou |

---

## 0. Duas perdas, e uma delas é minha

**A primeira, do coordenador, já está reconhecida por ele:** 5.05, 5.10 e 5.16 foram despachados a
duas trilhas. Esta escreveu **2.086 linhas em 33 arquivos** que agora estão revertidas. Não há
defeito nelas; há um erro de coordenação, e ele está registrado aqui com o número para que daqui a
seis meses ninguém leia "sumiu".

**A segunda é minha, e não estava no despacho.** O relatório de execução é **untracked por
convenção** e as duas trilhas escrevem no **mesmo caminho**
(`plano/redesenho/execucao/o4-tags.md`). A outra trilha commitou às **18:53** e escreveu o relatório
dela — com **7 escalações**, segundo a mensagem de `0e11a04109`. Eu escrevi o meu às **19:06, por
cima**. Procurei em todas as worktrees e no histórico: **o arquivo dela não existe em lugar nenhum**,
porque nunca foi commitado.

O que sobrou dele: a mensagem de `0e11a04109` (que é longa e detalhada) e os comentários no código.
Reconstruí na §5 as escalações que consegui **verificar contra o código** — as outras se perderam, e
quem as escreveu é quem pode dizer quais eram.

**Regra que deveria existir e não existe:** relatório de trilha untracked em caminho compartilhado é
uma sobrescrita esperando acontecer. Ou ele entra no git com o commit da trilha, ou o nome carrega a
trilha (`o4-tags-o1-widget.md`). Não decidi por conta própria — é do coordenador.

---

## 1. A decisão: a implementação da outra trilha fica

Li as duas. **Concordo com a decisão, e por mais razões do que as quatro do despacho.** O backend
dela é melhor que o meu em dois pontos que eu não tinha visto:

**(a) A chave de idempotência é por GESTO, não por segundo.** A minha derivava do `occurred_at`
para o `track()` do site — o que junta dois `track()` legítimos no mesmo segundo. A dela gera um
`eventKey` no navegador **por chamada** (`crypto.randomUUID()` com reserva para contexto inseguro) e
o transforma em `dedup_key`. Chamada nova é fato novo; reenvio da mesma chamada é o mesmo registro.
É estritamente melhor.

**(b) A sessão entra pela autenticação, nunca pelo corpo.** `dedup_key` é prefixada pelo
`@contact_inbox.source_id`, que vem do token. O comentário dela diz o porquê, e está certo: aceitar
a sessão do corpo deixaria um cliente adulterado **colidir com a chave de outro visitante e apagar o
evento dele**. Eu não tinha considerado esse vetor.

Some-se o teto de 4.096 bytes em `properties` (que eu não tinha) e o achado de que
`applyInboxConsentMode` **nunca era chamado em produção** — o gate do 5.09 existia e não gateava
nada. Isso é um defeito real que a trilha dela encontrou e corrigiu.

**Nada meu foi melhor a ponto de justificar reverter a decisão.** As diferenças que sobram são
trade-offs, não defeitos, e estão na §6 como observações — não como escalações.

---

## 2. O que foi enxertado (commit `36924a392e`)

### 2.1 O check de navegador — `tracking/specs/browser/ponte-de-tags.check.mjs`

**36 asserções em Chromium real**, contra o **artefato construído** (`public/packs/js/tracking.js`,
minificado, importado como módulo ES por http). Adaptado ao contrato que ficou: `createTagsBridge`,
que devolve `{ onTrackingEvent, onWindowEvent, metaPixelInicializado, ga4Configurado }`;
`chatspx_event_id` no `dataLayer`; Google Ads só com `value` numérico.

Três páginas:

| Página | O que ela prova |
|---|---|
| site com GTM e **três pixels** | toda chamada é `trackSingle` no pixel `222` — nenhuma escapa para os outros dois; `eventID` presente; `window.gtag` e `window.dataLayer` sobrevivem **por identidade** (`===`); a fila que o cliente já tinha continua lá; evento desligado e evento fora do mapa vão **só** ao `dataLayer`; `onWindowEvent` traduz pelo contrato e `tracking: null` não vira nada; PII some **inclusive aninhada**, e o irmão dela fica |
| site cru, sem tag nenhuma | o `dataLayer` é criado e recebe; **nenhum** `fbq`, **nenhum** `gtag`, **nenhum** script injetado — e portanto nenhum `PageView` duplicado |
| consentimento negado | nenhuma tag dispara, mas o `dataLayer` recebe; `analytics_storage` concedido libera o GA4 **sem** liberar Meta e Ads |

Em todas: **zero requisição externa** (as rotas para fora são abortadas e contadas) e **console
vazio** — que é aceite do bloco e não existe em jsdom.

**O check foi verificado por sabotagem.** Cinco defeitos plantados no `tags.js`, cinco vermelhos:

| Sabotagem | Falhas |
|---|---:|
| `trackSingle` → `track` (o evento vaza para os 3 pixels) | 4 |
| `gtag` sem `send_to` | 1 |
| sem o filtro de PII | 5 |
| reatribuir `window.dataLayer` (viola RC2) | 6 |
| gate de consentimento desligado | 2 |

Sem isso o check seria decoração: um verificador que nunca reprova não distingue código bom de
código ausente.

### 2.2 Quatro vermelhos que o merge deixou na base

Todos **medidos antes** de corrigir, todos alheios aos blocos duplicados:

1. **`667` de volta no `sdk.js` e no `IFrameHelper`** (2 specs vermelhos). O 4.06 o reintroduziu
   depois de o 2.09 ter fixado 768 como número único; na faixa 668–767 px o teaser decidia
   "desktop" enquanto o CSS já tratava como celular. E **o dublê de `approach.spec.js` tinha o 667
   cravado** — um mock que repete o número errado *concorda* com o defeito em vez de denunciá-lo.
   Agora ele importa `MOBILE_BREAKPOINT`.
2. **Dois comentários dentro do `SDK_CSS`** — 599 B crus baixados por 100% dos visitantes.
   Comentário em template string é **dado**; o minificador não o toca. Movidos para o cabeçalho.
3. **Dois specs do 5.06 lendo `widget_configurable.rb`**, de onde o 5.01 tirou o
   `SECRET_KEY_PATTERN` (2 vermelhos). O `noSecretLeak` passou a cobrar as **duas** pontas.
4. **O guia do 5.15 dizia que `track()` "ainda não está disponível"** — e o 5.16 o entregou. O teste
   do 5.15 existia exatamente para avisar isso, avisou, e **o vermelho ficou aberto**: a documentação
   pública passou a mentir para o integrador. Guia reescrito com a API que ficou (a expressão de nome
   dela, a recusa de PII pelo servidor), e a asserção **invertida** — agora cobra que o guia ensine o
   que o SDK tem, e que a expressão do guia seja a **mesma** do SDK.

### 2.3 Bytes (A13), medido nos dois estados com o comando do gate

| Estado | cru | gzip |
|---|---:|---:|
| `redesenho-integra` | 45.852 B | **15.335 B** ← acima do teto |
| com `36924a392e` | 45.142 B | **14.972 B** ← dentro |
| teto | 40.000 B | 15.000 B |

Os itens 2.2.1 e 2.2.2 devolvem **710 B crus / 363 B gzip** e trazem o gzip de volta para dentro do
teto, com 28 B de folga. O **cru segue estourado** (dívida herdada de 5.142 B, de antes desta onda).

---

## 3. O que NÃO foi enxertado, e por quê

O despacho pediu para dizer antes de enxertar. Os dois ficam de fora:

**`trackContract.js` (61 linhas) — não enxertar.** Ele fazia duas coisas, e a base já faz as duas
por outro caminho:
- *validação do nome no navegador*: o `entrypoints/sdk.js` que ficou já valida, com
  `/^chatspx_[a-z0-9_]{0,32}$/` numa expressão só. A minha versão dizia qual das três regras foi
  violada em vez de mostrar a expressão — é diferença de ergonomia, não de cobertura, e não paga uma
  segunda fonte de verdade.
- *lista de PII no cliente*: já existe em `tags.js`, **e com uma guarda melhor que a minha**: o
  `tags.spec.js` dela lê `app/models/tracking_event.rb` e reprova se as duas listas divergirem. A
  minha tinha a mesma guarda, mas duplicar a lista num terceiro arquivo criaria justamente a
  divergência que a guarda existe para pegar.

**`widget_event_recorder.rb` (146 linhas) — não enxertar.** A lógica equivalente está no controller
dela e é melhor (§1, pontos a e b). O único comportamento meu que não tem correspondente é a
sanitização de `page_url` (eu gravava sem query string, porque `TrackingEvent` recusa *chave* de PII
mas não um e-mail escondido dentro de uma URL). Na base isso não é um risco hoje: o controller dela
**não grava `page_url`** — `properties` do `widget_opened` fica vazio. Se alguém for acrescentar esse
parâmetro do contrato (§2, evento #2), a sanitização precisa vir junto. Fica anotado aqui, não
enxertado.

---

## 4. Gap do aceite na implementação que ficou: **T-C4.3 não está implementado**

Este é o único ponto em que peço decisão, e não é "a minha era melhor" — é aceite não coberto.

A ponte que ficou dispara **somente nas tags que já existem na página** (`typeof window.fbq !==
'function'` → retorna). Não há instalação condicional. Verificado: `grep -c
'installMetaPixel|installGoogleTag|skipPageView|install_tags'` em `tags.js` → **0**.

Consequência: **um cliente que cola o Pixel ID na nossa tela mas não tem o pixel na página não
recebe nada na Meta** — e não há sinal de que não recebeu.

O plano é explícito nas duas pontas:
- **T-C4.3**: *"Instalação condicional da tag faltante com `skipPageView`, atrás do toggle de
  opt-in"*;
- **Campos da tela (§C1)**: *"Instalar tag faltante | booleano | **público** | default desligado
  (decisão **Q5**: opt-in explícito, nunca por padrão)"*.

Hoje a chave `install_tags` **não existe** em `WidgetTrackingSchema` (verificado: o schema a recusa
por `additionalProperties`), nem na projeção pública, nem na tela.

**Pode ser que a trilha dela tenha escalado exatamente isto — era uma das 7 escalações do relatório
que eu apaguei.** Não tenho como saber. Se ainda não foi decidido, tenho o código pronto e testado
para enxertar (`installMetaPixel` / `installGoogleTag` com `send_page_view: false`, a chave nas três
listas e um `Switch` na aba Eventos, com i18n `en`/`pt_BR`) — mas **não enxerto sem sua palavra**,
porque instalar tag de terceiro no site do cliente é decisão de produto, não de código.

---

## 5. Divergências reconstruídas (schema 5.01 × tela 5.06)

O comentário do `tags.js` que ficou diz *"a divergência está ESCALADA no relatório desta trilha"* —
o relatório que eu apaguei. Reconstruo aqui a parte que **verifiquei executando o schema real contra
os payloads reais da tela**, para que a informação não dependa do arquivo perdido:

| Chave | O que a tela grava | O que o schema declara | Veredito |
|---|---|---|---|
| `event_map` | `{ chatspx_lead: { enabled, meta, ga4 } }` | `nome → string` | **RECUSA** em `/properties/event_map/additionalProperties` |
| `test_mode` | `{ enabled, code, started_at }` | `boolean` | **RECUSA** em `/properties/test_mode` |
| `lead_value` | `{ mode, amount }` | *chave inexistente* | **RECUSA** em `/additionalProperties` |

**A tela de rastreio não salva.** O administrador mexe no mapa de eventos, no modo teste ou no valor
do lead, clica em salvar e recebe **422** — só os três IDs e o `consent_mode` passam. Nenhum teste
pega porque cada lado testa o **seu** formato e ninguém roda o payload da tela contra o validador.

A ponte que ficou já tolera as duas formas de `event_map` (`entradaDoMapa` lê string e objeto), o que
é a decisão certa para não arbitrar sozinha. Falta arbitrar: **qual formato vence**. As outras duas
chaves não têm sequer tolerância — elas simplesmente não gravam.

---

## 6. Observações sobre a implementação que ficou — não são escalações

Sem medição que sustente "a minha era melhor". Registro para quem for tocar em 5.11/5.13:

1. **`trackSingle` sempre, mesmo para nome não-padrão da Meta.** Se o cliente mapear um evento para
   um nome que não está na lista de eventos padrão, o `fbevents.js` avisa no console do site dele —
   e "console limpo" é aceite. A chamada publicada pela Meta para evento próprio é
   `trackSingleCustom`. **Não medi**: precisaria do `fbevents.js` real, e o check não faz chamada
   externa de propósito. Fica como hipótese a confirmar, não como defeito.
2. **`track()` com falha de rede não publica no `dataLayer`.** O store dela só encaminha ao host
   depois do POST bem-sucedido. É defensável (sem `event_id`, o `dataLayer` teria um evento que o
   registro não tem). O contrário também é (o fato aconteceu; o GTM do cliente perde um evento real
   por uma falha que não é dele). É trade-off, e a escolha dela está coerente com o resto.
3. **O build do SDK apaga `public/packs`.** `vite.lib.config.ts` não tem `emptyOutDir: false`, então
   rodá-lo **depois** do build de tracking apaga o `tracking.js`. Em produção está certo —
   `lib/tasks/build.rake` chama `build:sdk` (linha 7) antes de `build:tracking` (linha 14). Vale
   saber ao rodar à mão: o check de navegador falha com "artefato ausente" se a ordem inverter.

---

## 7. Verificação

| Suíte | Resultado |
|---|---|
| vitest (`sdk`, `widget`, `settings/inbox/widget`) | **1.803 testes, 0 falhas** |
| rspec (backend de tracking: `events_tracking`, `events_controller`, `widget_tracking_schema`, `tracking_event`) | **68 exemplos, 0 falhas** |
| Chromium real (`ponte-de-tags.check.mjs`) | **36 asserções, 0 falhas** |
| sabotagem do check | **5 de 5 pegas** |
| eslint | limpo nos arquivos tocados |

Antes do commit, os mesmos alvos tinham **4 falhas** (§2.2). O `rspec` foi rodado com banco dedicado
`chatwoot_test_o4resto`; conferi a contagem de exemplos, e não só a de falhas — `0 examples` se lê
como verde e aconteceu uma vez nesta sessão, por caminho de arquivo errado meu.

---

## 8. Blocos bloqueados — registrados e não tocados

**5.02, 5.11, 5.12, 5.13, 5.14 e 5.21** dependem do **0.10** (infraestrutura, exige `sudo`, não foi
pedido). É o maior pedaço do plano parado por uma dependência só.

A ponte já está pronta para o 5.13: o `event_id` sai como `eventID` no `fbq` e como
`transaction_id` no Ads — **verificado em navegador real**. Falta o outro lado (CAPI), que é o 5.11.
