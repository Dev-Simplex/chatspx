# Onda 4 · Trilha COMPLEMENTAR (o4-resto) — relatório de execução

**Worktree:** `/home/chatwoot/chatwoot-o4-resto` · **Branch:** `o4-resto`
**Base:** `redesenho-integra` (`e0ae8e5759`) — o worktree **não existia**; foi criado com
`git worktree add … -b o4-resto redesenho-integra`, o que já contempla o merge pedido no briefing
(a branch nasce da integra, então `redesenho-integra` é ancestral, não um merge a fazer).
**Escopo realocado:** **5.01, 5.17 e 5.18**. Os demais do spec ficam bloqueados e não foram tocados:
5.05 e 5.16 (dependem de **5.03**), 5.19 e 5.20 (dependem de **4.15**), 5.21 (depende de **5.11**).
**Banco:** `chatwoot_test_o4resto` (`RAILS_ENV=test`). Nenhum push, PR, deploy ou restart.

---

## Bloco 5.01 — Config pública de tracking por inbox ✅ **FECHADO**

### O que a base já dava, e o que faltava

O 3.01 (já integrado) criou `widget_tracking` em `inbox.additional_attributes`, com lista negativa
`/(\A|_)(token|secret)\z/i` e `WidgetTrackingProjection` (lista branca na leitura). O aceite literal
do bloco — *gravar `access_token` → 422 apontando a tela de credenciais* — **já passava**.

O que faltava é o que o enunciado chama de *"schema JSON ⚪"* e *"qualquer chave que pareça segredo"*.
Medi o buraco antes de escrever qualquer linha, com 21 nomes e valores com cara de credencial:

| | resultado |
|---|---|
| **Aceitos pela base (o buraco)** | **17 de 21** |
| Recusados pela base | 4 (`access_token`, `client_secret`, `refresh_token`, `webhook_secret`) |

Os 17 que entravam: `api_key`, `apiKey`, `password`, `credential`, `credentials`, `private_key`,
`authorization`, `auth`, `access_token_v2`, `secretKey`, `signature`, `salt`, `passwd`, `pwd`, e
três valores de token sob **chave de nome inocente** (JWT, `sk_live_…`, `EAAG…`).

A causa estrutural: das três chaves de objeto, **`widget_tracking` era a única sem schema**.
`widget_triggers` e `widget_appearance` já tinham `additionalProperties: false`; o tracking aceitava
qualquer nome que não casasse a lista negativa.

### As três camadas, em ordem de força

| Camada | Onde | O que recusa |
|---|---|---|
| **1. Schema** (a principal) | `WidgetTrackingSchema` ⚪ | **tudo** que não foi declarado público — inclusive o nome de segredo que ninguém previu |
| 2. Nome | `WidgetSecretScanner::SECRET_KEY_PATTERN` | 16 termos, com `(\z\|_)` no fim (pega no **meio** do nome) e normalização camelCase (`apiKey` → `api_key`) |
| 3. Valor | `WidgetSecretScanner::SECRET_VALUE_PATTERNS` | JWT, Meta `EAA…`, Stripe `sk_live_…`, Google `AIza…`, GitHub, Slack, `Bearer …`, PEM |

A camada 3 existe porque, depois da lista de nomes, **o disfarce que sobra é chave inocente com
valor de token** — `{ event_map: { conversation_started: "sk_live_…" } }`.

**A mensagem nomeia a chave e nunca ecoa o valor.** Erro vai para a tela e para o log; repetir o
segredo ali seria publicá-lo num terceiro lugar. Tem asserção para isso.

### Duas decisões de recusa que são recusas de recusar

1. **`session` e `cookie` ficam fora da lista negativa.** São palavras de tracking legítimo
   (`session_timeout`), e barrá-las recusaria config de quem não fez nada errado.
2. **Os padrões checam a forma do identificador, nunca o comprimento exato.** Minha primeira versão
   exigia `[0-9]{5,20}` em `meta_pixel_id` — e **reprovou um teste desta base** que usa `'123'`.
   Comprimento exato é aposta sobre como a plataforma numera os clientes dela; forma errada é sinal
   de que entrou outra coisa (token tem letras, Pixel ID não). Corrigi a **minha** validação, não o
   teste alheio.

### Schema e projeção descrevem o mesmo conjunto — e há spec que falha se divergirem

Se o schema aceitasse uma chave que a projeção descarta, o cliente salvaria, a tela confirmaria, e o
dado sumiria sem aviso. Medido: **6 chaves, idênticas nos dois lados.**

### Contrato da chave (exigência do briefing: bloco que é ponta de contrato escreve o contrato)

| Chave | Tipo | Formato | Default na ausência |
|---|---|---|---|
| `meta_pixel_id` | string | `^[0-9]{1,20}$` | ausente — nenhum pixel é emitido |
| `ga4_measurement_id` | string | `^G-[A-Za-z0-9]{1,20}$` | ausente |
| `google_ads_send_to` | string | `^AW-[0-9]{1,15}(/rótulo)?$` | ausente |
| `event_map` | object | ≤ 50 entradas, valores string de 1–100 chars | ausente — nenhum evento é mapeado |
| `consent_mode` | string | `disabled` \| `basic` \| `advanced` (nomes do Consent Mode v2) | `disabled`, que é o comportamento de hoje |
| `test_mode` | boolean | — | ausente = falso |

Chave fora desta lista → **422 na escrita**. Objeto inteiro ausente (`nil`) → o widget recebe `{}`
e nada muda; é a regra A4 (sem migration, sem backfill).

### Mecanismo, vermelho e verde

O vermelho é o concern **restaurado à versão da base** (`git checkout HEAD --`), com o schema no
disco mas não ligado — mede o produto ter passado a usar a defesa, não a defesa existir:

| | examples | failures |
|---|---|---|
| **Vermelho** (concern da base) | 28 | **18** |
| **Verde** | 28 | **0** |

Não-regressão do 3.01 (`inboxes_controller_widget_config_spec.rb`): **19 examples, 0 failures**, com
os três arquivos juntos dando **47 examples, 0 failures**. `rubocop`: **no offenses** — o
`Metrics/ModuleLength` que meu acréscimo estourou foi resolvido **extraindo** `WidgetSecretScanner`,
não afrouxando o gate.

### Os dois sentidos, como o briefing exigiu

| Sentido | Mecanismo | Medido |
|---|---|---|
| **1. a chave suspeita é recusada** | `inbox_tracking_config_spec.rb`, PATCH real | 422, `attributes` inclui `widget_tracking`, mensagem em **pt-BR** (locale da instalação) com `access_token` **e** "tela de credenciais" |
| **2. salvar sem ela não apaga nada** | 4 exemplos | a tentativa recusada deixa o tracking anterior **intacto**; reenviar a config boa mantém as outras três chaves; salvar `widget_profile` não mexe no tracking; atualizar um campo preserva os outros |

O sentido 2 não é detalhe: o pior defeito desta execução foi o upstream filtrar um campo na leitura
enquanto o formulário reenviava o objeto inteiro, e abrir "Editar" **apagava a credencial do
cliente**. Recusa que apaga o que já existia troca um vazamento por uma perda.

### Asserção negativa (pedido explícito do coordenador)

`widget_public_config_secret_scan_spec.rb` renderiza **as duas pontas** — o HTML de
`show.html.erb` e o JSON de `configs/create.json.jbuilder` — e falha se encontrar nome **ou** valor
com cara de credencial. Inclui:

- o caso do **segredo gravado por fora do modelo** (`update_column`, contornando a validação de
  propósito): é o cenário que a projeção por lista branca existe para cobrir — console, import,
  migration de terceiro, bug futuro;
- **sabotagem nas duas pontas**, porque teste que nunca viu vermelho não prova nada (lição do caso
  da paridade 0.6);
- a exigência de que a config **legítima esteja lá** (`1234567890`), senão a varredura passaria por
  vazio, que é o falso verde.

_Status desta suíte: aguardando o build do Vite deste worktree — ver a nota de execução abaixo._

### Nota de execução: o `autoBuild` do Vite

Renderizar `show.html.erb` em `RAILS_ENV=test` dispara `vite build` quando não há manifest
(`config/vite.json`, `autoBuild: true`). Num worktree recém-criado isso são **minutos** dentro do
primeiro exemplo, e o sintoma é o spec "travado" sem saída. Não é defeito do bloco: é o custo de
worktree novo. O build foi disparado uma vez, à parte.

---

## Bloco 5.17 — O telefone entra na identidade, e o verbo fica explícito ✅ **FECHADO**

### O defeito, medido antes de escrever

`getUserString` (`sdk/cookieHelpers.js`) só olhava `avatar_url`, `email`, `name` e
`identifier_hash`. Duas consequências, e as duas silenciosas:

| | |
|---|---|
| **Mudar só o telefone não saía do navegador** | o hash era **literalmente o mesmo** — medido: `be767ee006ffbc46ecad06184bcf8c30` antes e depois. O SDK comparava com o cookie e retornava cedo |
| **Telefone sozinho não identificava** | `hasUserKeys` exigia um dos três, e a chamada morria com *"should have one of the keys [avatar_url, email, name]"* |

**Vermelho: 9 falhas em 14. Verde: 14, 0.**

### A correção, e a regra por trás dela

`phone_number` entra em `REQUIRED_USER_KEYS`, e o hash passa a cobrir **tudo o que o widget
realmente envia**. A regra: *campo que o widget manda e o hash ignora é, por construção, campo que
nunca atualiza depois da primeira vez.* Objeto vira texto com **chaves ordenadas** — sem isso, o
mesmo conteúdo em outra ordem daria hash diferente e o dedupe reenviaria a cada chamada, que é o
defeito oposto e igualmente mudo.

**Efeito colateral declarado:** o hash mudou, então na primeira visita após o deploy cada visitante
já identificado dispara **um** `setUser` extra. É o preço de corrigir, e ele se paga uma vez.

### Superfície nova e a regra de verbo

`company` como **objeto** (`{name, id, plan}` → `company_name` + `company_*`) e `signed_up_at`, num
módulo próprio — `widget/helpers/identityPayload.js`. A tradução entre o vocabulário do **site** e o
da **API** é uma junção, e enquanto viveu inline no store cada campo novo virou linha copiada: foi
exatamente assim que `phone_number` acabou fora do dedupe.

| Verbo | Semântica | Estado |
|---|---|---|
| `setUser` | **substitui** | **legado**, marcado no código, comportamento intacto |
| `updateUser` | **mescla** — campo não enviado não viaja, então o servidor não o apaga | novo |

O site que só quer corrigir o telefone chamava `setUser` com o objeto inteiro e, se esquecesse um
campo, o apagava sem aviso — mesmo formato do defeito que apagava credencial ao abrir "Editar".

### Duas guardas da base me pararam, e as duas estavam certas

1. **Os specs do store** observam os dispatches de `setUser`. Minha primeira versão delegava para
   uma *action* nova e mudava essa lista. Troquei por **função compartilhada**: o contrato
   observável não muda neste bloco, e os 3 specs passaram **sem eu tocar em nenhum**.
2. **A spec-guarda do bridge (1.09)** exige a lista exata de eventos e reprovou o 17º. Atualizei a
   régua **declarando por que ele nasceu** — que é o que a guarda existe para forçar.

Mais um teste de comportamento: `set-user` e `update-user` despacham ações **diferentes**. Se ambos
caíssem em `contacts/setUser`, o update mesclaria nada — e nenhum teste de nome pegaria isso.

**72 tests, 0 failures** em 8 arquivos (SDK, bridge, store, helpers). `eslint` limpo.

---

## Bloco 5.09 — Consentimento, com padrão negado e a ordem como aceite ✅ **FECHADO**

### A asserção negativa é o aceite

Com a CMP negando, o contador de disparos fica em **zero** — chamando o gate dez vezes seguidas,
e com consentimento parcial (o propósito concedido dispara, o vizinho continua em zero). *Contar os
disparos permitidos provaria que o caminho feliz anda; só contar os **proibidos** prova que o gate
existe.*

O gate **não executa** a função. Executar e descartar o resultado seria a mesma coisa que não ter
gate — o disparo já teria acontecido.

### Não há fila, e a ausência é deliberada

Reproduzir depois o que o visitante negou na hora seria honrar a letra do consentimento e trair o
sentido. O aceite diz *"os **seguintes** disparam"* — os anteriores ficaram para trás porque naquele
momento a resposta era não.

### A ordem de execução, medida

| Verificação | Resultado |
|---|---|
| `default` vai **antes** do `update`, sempre | `['default', 'update']` |
| `update` sem default publicado **publica o default antes** | idem — em vez de mandar update solto, que a plataforma lê como desconhecido |
| publicar o default **duas vezes** não empurra dois | o segundo apagaria um `update` já recebido; o teste aceita, republica o default e exige que a concessão sobreviva |

### Estado por conta/inbox — consumindo o 5.01

`consent_mode` (`disabled` \| `basic` \| `advanced`) vem de `widget_tracking`, **já validado pelo
schema do 5.01**. `disabled` é o padrão e mantém o comportamento de **hoje**: ligar o gate sozinho
mudaria o produto de quem não configurou nada. `advanced` publica a linha de base na hora. Modo
desconhecido cai em `disabled`, **nunca** em "liga tudo".

Entrada torta não vira concessão: `true`, `'sim'`, `1` e `null` não concedem; propósito inventado
nem entra no estado.

### Mecanismo, vermelho e verde

Vermelho = gate removido **e** default nascendo concedido — que é o Consent Mode mal configurado
típico: **14 falhas em 17**. Verde: **22 examples, 0** (119 tests no SDK inteiro). `eslint` limpo.

**Nada foi disparado para serviço externo**: o sink é injetável e o teste observa por ele.

**Pendência declarada:** o `consent` no payload **server-side** depende do canal do **5.05**, que
está escalado (seção abaixo) e não foi tocado.

---

## Bloco 5.18 — `data-*` de configuração no snippet ✅ **FECHADO**

**A regra, que é o aceite:** configuração viaja por qualquer via; **identidade e credencial, só
pela API JS**.

### Por que a distinção é dura

O snippet é HTML: aparece no view-source, entra em cache de CDN, fica no histórico do navegador e é
copiado entre páginas por quem cuida do **site**, não por quem cuida de dados. Configuração ali é
inofensiva — a posição da bolha é pública de qualquer jeito. Identidade não: um `data-email` num
template de e-commerce vaza o cliente para qualquer um que veja a fonte da página, e
`data-identifier-hash` publica justamente a credencial que existe para provar que aquele visitante
é ele mesmo.

### Asserção negativa nos dois eixos

| Eixo | Mecanismo |
|---|---|
| **Identidade** | um exemplo **por chave** da lista; a prova de que a interseção com as chaves de configuração é **vazia**; e o caso misturado — config passa, identidade não, e o valor do e-mail não aparece em lugar nenhum do resultado |
| **Credencial** | `accessToken`, `apiKey`, `clientSecret`, `password`, `privateKey`, `authorization`, `bearerToken`, `webhookSecret` — mais a prova **inversa**: nenhuma das 16 chaves de configuração é confundida com credencial |

A prova inversa importa tanto quanto a direta: falso positivo aqui quebraria o integrador que não
fez nada errado.

### O teste pegou um defeito meu

`canonical('apiKey')` produz `api_key`, e meu padrão só listava `apikey` — **`apiKey` e
`privateKey` passavam batido**. As duas grafias entraram, e o comentário no código registra que foi
o teste que achou.

### Recusa alta e visível, e precedência declarada

`readSnippetConfig` devolve `{ config, rejected }`, e o `run()` emite `console.warn` nomeando cada
chave recusada **e dizendo por onde ela deve ir**. Recusa silenciosa faria o integrador achar que
configurou; o sintoma apareceria semanas depois como *"o widget ignora o que eu mando"*.

**`window.chatwootSettings` vence o `data-*`.** A via em JavaScript é a que o dono da integração
controla; o snippet costuma ser colado por outra pessoa, às vezes por gerenciador de tags. A
inversa produziria *"mudei no código e não mudou no site"*, sem nada no console.

**32 examples no bloco, 151 tests no SDK inteiro, 0 falhas.** `eslint` limpo.

---

## Estado da trilha

| Bloco | Estado | Commit |
|---|---|---|
| **5.01** | ✅ fechado | `cc0aa06e05` |
| **5.17** | ✅ fechado | `829d98a32c` |
| **5.09** | ✅ fechado | `c6964e5345` |
| **5.18** | ✅ fechado | (este) |
| **5.05** | ⚠️ **escalado** — diverge do contrato, ver seção abaixo | — |
| **5.16** | ⏸ não iniciado nesta rodada | — |
| 5.19 · 5.20 | ⛔ bloqueados por **4.15** | — |
| 5.21 | ⛔ bloqueado por **5.11** | — |
| 5.02 · 5.11 | ⛔ bloqueados por **0.10** (infra, exige sudo — fora da alçada, não pedido) | — |

---

# ⚠️ ESCALAÇÃO AO COORDENADOR — bloco 5.05 diverge do contrato

> Tentei mandar isto por `orca orchestration send --type escalation` e o relay respondeu
> *"No recipient or active Dispatch Run could be resolved"* — o Run da dispatch anterior fechou.
> O briefing cobre o caso: **"se o relay estiver sem coordenador, escreva tudo no relatório,
> inclusive o que você diria por mensagem"**. É o que está abaixo. **Não escolhi por conta própria
> e não acertei com a outra ponta.**

## O que o 5.05 pede

> *`event_id` nasce no backend e volta ao widget (`204` → `200 {event_id}`)* ·
> aceite: *resposta traz UUID; o `pushEvent` atual continua funcionando sem alteração*

## Os quatro fatos, lidos do código contra o contrato

| # | Fato | Onde eu li |
|---|---|---|
| 1 | O endpoint aceita **só dois nomes**, por causa do **1.15** já mergeado | `events_controller.rb:12` — `PERMITTED_EVENT_NAMES` |
| 2 | `webwidget.triggered` dispara em `onBubbleToggle` quando `isOpen` — é o evento **#2 `chatspx_widget_opened`**, que a §2 do contrato marca **"`event_id` propagado: não"** | `IFrameHelper.js:374-378` + contrato §2 |
| 3 | `campaign.triggered` **não tem evento de tracking nenhum**: a §1 mapeia "teaser/campanha exibida" para `chatwoot:campaign-shown` e **`—`** na coluna de tracking | contrato §1 |
| 4 | Os eventos que **realmente** propagam `event_id` são **3, 4, 5, 6, 9 e 11** — e **nenhum deles passa por este endpoint** | contrato §4.1 |

## Por que isso trava o bloco

Implementar o 5.05 como *"registra o fato e devolve o `event_id`"* entregaria um id que **o próprio
contrato diz não propagar**, para um evento que não propaga, mais um segundo nome que não existe no
vocabulário de tracking.

E há um impedimento mais duro: se eu **registrar** o fato aqui, viro o **segundo emissor** do evento
#2 — o que o `TrackingEventListener` proíbe nominalmente:

> *"Os eventos #1 a #9 nascem no widget e no store (**bloco 5.04, outra trilha**) e **não devem ser
> emitidos daqui também**: a regra RG4 do plano 25 é 'uma emissão por fato', e dois emissores para o
> mesmo fato é o defeito de junção que este plano já pagou caro uma vez."*

A **5.04 não está na base** (conferido em `git log redesenho-integra`: existem 5.03 e 1.15, não 5.04).

## Três saídas — a escolha é sua

| | O que muda | Custo |
|---|---|---|
| **A** | 5.05 vira **só o canal**: `200 {event_id}` com UUID gerado no servidor e **não gravado**, pronto para a 5.04 usar na dedupe da Meta | contrato ganha uma linha dizendo que **este** id não é chave de registro |
| **B** | 5.05 **registra** `chatspx_widget_opened` aqui, e a 5.04 passa a **consumir** o id em vez de emitir de novo | move a fronteira 5.04/5.05 e obriga a atualizar a §2 do contrato — o #2 passaria a propagar |
| **C** | 5.05 **espera** a 5.04 | bloco fica bloqueado, como 5.19/5.20/5.21 |

**Minha recomendação: (A)**, porque é a única que fecha o aceite literal do bloco (*"resposta traz
UUID; o `pushEvent` atual continua funcionando sem alteração"*) sem mexer na fronteira de outra
trilha nem contradizer a §2 do contrato. Mas é uma decisão de contrato, e o contrato é seu.

**Enquanto isso não volta, não toquei em `events_controller.rb`.** Segui para 5.17 e 5.09, que
estão destravados e sem ambiguidade.
