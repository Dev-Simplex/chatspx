# Onda 4 · Trilha TRACKING CLIENT-SIDE — relatório de execução

**Worktree:** `/home/chatwoot/chatwoot-o4-tracking-client` · **Branch:** `o4-tracking-client`
**Base:** `redesenho-integra` (`eb31616f31`, 125 commits) · **Data:** 18/08/2026

---

## 0. Situação dos cinco blocos, antes de qualquer detalhe

| Bloco | Estado | Prova / bloqueio |
|---|---|---|
| **5.04** eventos que faltam | **ENTREGUE** | 2 commits; 45 exemplos em JS + 18 em RSpec + 6 em navegador real, todos com vermelho provado antes |
| **5.08** coletor de origem no SDK | **BLOQUEADO** | depende de **5.07** (verificado NÃO feito: `config/environments/production.rb:24-26` segue com `max-age=1.year` e sem `ETag`) e de **5.01** |
| **5.09** consentimento | **BLOQUEADO** | depende de **5.01** — a chave `consent_mode` já existe na projeção pública, mas o **formato** dela é o schema de 5.01, que não existe |
| **5.10** ponte de tags | **BLOQUEADO** | depende de 5.08 e 5.09 (5.04, a terceira dependência, está pronta) |
| **5.13** deduplicação | **BLOQUEADO** | depende de 5.10 e de **5.11**, que a trilha `o4-server-cred` declara "não iniciado" |

Os quatro bloqueios estão detalhados no §7, com a proposta que peço ao coordenador decidir.

---

## 1. Uma decisão de base que precisa estar declarada: o merge de `o4-server-cred`

O despacho diz que 5.03 entregou `Tracking::EventRecorder` e que eu o chamaria. Ele não estava na
minha base: `redesenho-integra` está em `eb31616f31` e o commit de 5.03 (`031cfa1ae6`) vive só na
branch `o4-server-cred`, ainda não integrada.

Sem ele eu não conseguiria escrever nem testar o `lead_identified` de T-C3.7, que é server-side por
natureza e está na coluna *Arquivos* do meu bloco ("listener novo"). Então:

```
git merge o4-server-cred          # 1 conflito, em db/schema.rb
```

O conflito era só a linha de versão do schema (`2026_08_18_150000` da minha base contra
`2026_08_18_140100` da deles). Resolvido mantendo a **maior**, que é a regra do arquivo. As duas
migrations de tracking e a de `widget_partial_leads` convivem: `20260818140000`, `20260818140100` e
`20260818150000` são timestamps distintos, **sem colisão** (verificado — é a cicatriz do
`DuplicateMigrationVersionError` que já travou `db:migrate` na frota).

**Consequência para quem integrar:** a branch `o4-tracking-client` contém o commit de 5.03. Mesclar
as duas ordens (5.03 antes ou depois) dá o mesmo resultado; não há trabalho duplicado.

---

## 2. Bloco 5.04 — o que foi entregue

### 2.1 A fonte única dos nomes

`app/javascript/widget/constants/sdkEvents.js` deixou de ser uma lista de sete linhas e passou a ser
o contrato do vocabulário de `window`:

- os **sete nomes antigos, intactos** (renomear qualquer um derruba integração de cliente em
  produção, em silêncio);
- os **sete novos**: `chatwoot:conversation-created`, `chatwoot:prechat-submitted`,
  `chatwoot:message-sent`, `chatwoot:csat-submitted`, `chatwoot:campaign-shown`,
  `chatwoot:lead-identified`, `chatwoot:reset-completed`;
- `SDK_EVENT_CONTRACT`: para cada evento novo, **o nome de tracking correspondente** (ou `null`
  declarado) e **as chaves de payload permitidas**. É o mapa 1:1 da arbitragem A9 e é o que o bloco
  **5.10** vai consumir para montar `dataLayer`/`fbq`/`gtag` sem reinventar vocabulário.

### 2.2 O emissor, com duas guardas que a cópia manual não tinha

`app/javascript/widget/helpers/sdkEventEmitter.js` (novo). Antes havia três emissores espalhados
montando o envelope `{event:'onEvent', eventIdentifier, data}` na mão (`ChatFooter.vue`,
`TeamAvailability.vue`, `actionCable.js`). Agora o envelope é um só e passa por:

1. **Filtro de contrato.** Só as chaves declaradas atravessam. O `window` do site do cliente é
   legível por qualquer script de terceiro da página; a regra dura de `24-plano-backend-dados.md`
   §17.1 é *nome de campo sim, valor de PII nunca*. Uma chave `email` que escape por descuido é
   descartada — e o descarte é **contado** pela telemetria de 2.13, porque chave perdida em silêncio
   é defeito invisível. Evento sem entrada no contrato (os sete antigos) passa **intacto**: este
   bloco não pode estreitar payload que ele não definiu.
2. **Nunca lança.** O emissor roda no meio do caminho do visitante. `postMessage` que falhe não pode
   impedir a conversa de ser criada — é a mesma doutrina do `TrackingEventListener` de 5.03.

O "uma vez" do aceite mora aqui, em `emitSdkEventOnce(evento, dados, chave)`. A marcação é feita
**depois** do envio bem-sucedido: envio que falhou não aconteceu, e marcar antes perderia o evento
para sempre.

### 2.3 Emitido do STORE, e por quê

| Evento | De onde sai | Chave do "uma vez" |
|---|---|---|
| `chatwoot:conversation-created` | `conversation/actions.js` — `createConversation` (pré-chat) **e** `sendMessageWithData` (1ª mensagem sem pré-chat) | o nome do evento (uma conversa por documento) |
| `chatwoot:prechat-submitted` | `conversation/actions.js` — `createConversation` | — (um pré-chat por conversa) |
| `chatwoot:message-sent` | `conversation/actions.js` — `sendMessageWithData` | — (por mensagem, de propósito) |
| `chatwoot:csat-submitted` | `message.js` — `update` | `csat:{messageId}` |
| `chatwoot:campaign-shown` | `campaign.js` — `startCampaign` | `campanha:{id}` |
| `chatwoot:lead-identified` | `contacts.js#update`, `message.js#update`, `conversation/actions.js#createConversation` | o nome do evento |
| `chatwoot:reset-completed` | `sdk/IFrameHelper.js` — `events.loaded` | — (um por `reset()`) |

**Nenhum componente foi editado por dentro.** `PreChat/Form.vue`, `ChatFooter.vue` e
`ChatInputWrap.vue` são campo minado (R15 §B12.3) e, pior, são componentes: montam e desmontam a
cada troca de rota, então um evento emitido de `mounted` dispara duas vezes num re-render e zero
numa navegação que reusa a instância. O store não monta nem desmonta.

`CustomerSatisfaction.vue` tem um segundo motivo para não ser tocado: ele mora em `shared/` e é
renderizado também pelo dashboard e pela pesquisa avulsa — emitir de lá mandaria evento de widget de
dentro de telas que não têm SDK do outro lado. (E, por não ter sido tocado, a regra **R21** não se
aplica: **nenhum arquivo de `app/javascript/shared/` foi alterado neste bloco**.)

### 2.4 T-I4.4 — `on-start-conversation` corrigido sem quebrar ninguém

`chatwoot:on-start-conversation` é **intenção**: dispara no clique, antes de existir conversa. Ele
**continua exatamente onde estava**, emitido pelos mesmos dois componentes, porque é contrato
público em uso. O que faltava era a **conclusão** — e ela agora existe, com id:
`chatwoot:conversation-created` só sai quando o servidor respondeu.

### 2.5 T-I4.5 — o `reset()` deixou de ser mudo

O que existia era só supressão: `resetTriggered` impedia o segundo `chatwoot:ready`, e o site que
chamou `reset()` não recebia sinal nenhum. Agora o reset **anuncia** `chatwoot:reset-completed`.

**Um defeito achado de lambuja e corrigido:** a flag nunca era limpa. Depois do primeiro `reset()`
ela ficava `true` para sempre, e **qualquer recarga posterior do iframe deixava de emitir
`chatwoot:ready`** — a supressão valia uma vez e durava a vida da página. Agora cada `reset()`
suprime exatamente um `ready` e anuncia exatamente uma conclusão.

### 2.6 T-C3.7 — `chatspx_lead` nasce no servidor, e a razão é aritmética

O fato é *"o contato **passou a ter** e-mail ou telefone"*. A palavra que importa é **passou**: é
transição, não estado. O widget vê estado ("este contato tem e-mail") e **não distingue** o
visitante que acabou de digitar do visitante que já era identificado e recarregou a página. Emitir o
evento de tracking do cliente contaria um Lead **por carregamento de página** — conversão inflada,
decisão de mídia tomada sobre número mentiroso.

No servidor a transição é verificável, porque `contact.updated` traz `previous_changes`.
`TrackingEventListener` ganhou `contact_created` e `contact_updated`:

- **transição** = campo estava vazio **e** passou a ter valor. Trocar de e-mail **não** vira lead de
  novo — ele já era;
- **`dedup_key: "chatspx_lead:contact:<id>"`**, explícita. Sem ela a derivação padrão usa
  `occurred_at.to_i`, e um contato que ganha e-mail às 09:00:01 e telefone às 09:00:09 produziria
  **dois** `chatspx_lead` — dois `event_id`, duas conversões na Meta, e o índice único de
  (evento, destino) não tocaria em nenhuma, porque para o banco são eventos diferentes. **Há teste
  para exatamente este caso.**

---

## 3. O CONTRATO, campo por campo — porque este bloco é ponta de junção

O despacho pede: *"escreva o contrato no relatório: nome da chave, tipo, default, e o que acontece
na ausência."* Segue.

### 3.1 `chatwoot:conversation-created`

| Chave | Tipo | Obrigatória | Na ausência |
|---|---|:---:|---|
| `conversation_id` | número | **sim** | o evento não é emitido |
| `inbox_id` | número | **não** | **a chave não vem** — ver o aviso abaixo |

> **AVISO DE JUNÇÃO, e é o campo que um consumidor descuidado quebraria.** `inbox_id` só existe no
> caminho do **pré-chat**, porque é o `POST /widget/conversations` que o devolve
> (`create.json.jbuilder`). No caminho **sem pré-chat** — em que a conversa nasce junto com a
> primeira mensagem — o servidor não devolve `inbox_id` ao widget: o payload de mensagem
> (`_widget_message.json.jbuilder`) traz só `conversation_id`. Fazer a chave existir nos dois
> caminhos exigiria publicar o id da inbox no `chatwootWebChannel`, o que toca os **dois** montadores
> de config (bloco BK-16 / 3.04, outra trilha) e o teste de paridade de 0.6. Não fiz. **Quem
> consumir precisa tratar `inbox_id` como opcional.**

`conversation_id` é o **`display_id`** — o mesmo id que a API pública usa em
`/conversations/{id}/messages`, e portanto o único que serve a quem escuta de fora.

### 3.2 `chatwoot:prechat-submitted`

| Chave | Tipo | Obrigatória | Na ausência |
|---|---|:---:|---|
| `fields` | lista de strings | **sim** | lista vazia (`[]`), nunca chave ausente |

São os **nomes** dos campos preenchidos (`fullName`, `emailAddress`, `phoneNumber` e as chaves dos
atributos customizados), **nunca os valores**. Campo vazio ou só com espaços não entra.

### 3.3 `chatwoot:message-sent`

| Chave | Tipo | Obrigatória | Na ausência |
|---|---|:---:|---|
| `conversation_id` | número | não | a chave não vem |

### 3.4 `chatwoot:csat-submitted`

| Chave | Tipo | Obrigatória | Na ausência |
|---|---|:---:|---|
| `rating` | número 1–5 | **sim** | o evento não é emitido |

Emitido **uma vez por pesquisa** (chave `csat:{messageId}`): o visitante responde a nota e depois
escreve o comentário, e as duas submissões passam pela mesma ação — o fato é um só.

### 3.5 `chatwoot:campaign-shown`

| Chave | Tipo | Obrigatória | Na ausência |
|---|---|:---:|---|
| `campaign_id` | número | **sim** | o evento não é emitido |

### 3.6 `chatwoot:lead-identified`

| Chave | Tipo | Obrigatória | Na ausência |
|---|---|:---:|---|
| `identifiers` | lista de strings, subconjunto de `["email","phone_number"]` | **sim** | sem identificador, o evento **não** é emitido |
| `conversation_id` | número | não | a chave não vem (ex.: identificação fora de conversa) |

**Nunca leva o e-mail nem o telefone.** Quem precisa do valor é o servidor, que hasheia antes de
mandar à Meta.

### 3.7 `chatwoot:reset-completed`

Payload vazio (`{}`), por contrato (`24-plano-backend-dados.md` §17.1).

---

## 4. A conferência do contrato de 5.03 — o que casa e o que diverge

Li `docs/tracking/contrato-de-eventos.md` campo por campo antes de escrever. **Conferência:**

| Ponto do contrato | Casa? |
|---|---|
| Os cinco nomes `chatwoot:*` da §1 | **sim**, string por string — e há teste que lê do documento |
| O mapa `conversation-created → chatspx_conversation_started` | **sim** |
| O mapa `prechat-submitted → chatspx_prechat_submitted` | **sim** |
| `message-sent` e `campaign-shown` sem contrapartida de tracking | **sim**, `null` declarado no mapa |
| `chatspx_csat_submitted` **não existe** (§6 ponto 1: não implementar antes de decidir) | **sim** — o evento de `window` sai, o de tracking **não** |
| API `Tracking::EventRecorder.record!` (§5) | **sim**, chamada com os nomes declarados |
| `dedup_key` explícita quando há chave natural (§4.2) | **sim** — é o que impede o lead duplo |
| `properties` recusa PII crua (§6 ponto 3) | **sim**, e há teste que verifica que o e-mail não entra |
| Nomes de tracking: prefixo, snake_case, ≤ 40 (§1) | **sim**, verificado também em JS, porque o mapa daqui é o que 5.10 usará |

### 4.1 A DIVERGÊNCIA — escalada, não negociada

**O contrato de 5.03 (§1) registra o fato "contato passou a ter e-mail ou telefone" como
server-side puro:** a coluna do evento de `window` traz *"— (server-side)"*.

**O aceite do bloco 5.04 exige** a ordem `widget_opened → conversation_created → prechat_submitted →
**lead_identified**` **observável por `addEventListener` em navegador real** — o que só é possível
se o fato também chegar ao `window`.

Não combinei nada com a outra trilha. O que fiz, para não entregar zero e não fechar decisão que não
é minha:

- o evento de **tracking** `chatspx_lead` continua nascendo **só no servidor**, onde a transição é
  verificável — exatamente como o contrato manda;
- acrescentei o evento de **`window`** `chatwoot:lead-identified`, que é o **outro vocabulário do
  mesmo fato** (arbitragem A9), sem nenhum valor de PII;
- **não editei `docs/tracking/contrato-de-eventos.md`.** Ele é artefato de 5.03.
- congelei a divergência em teste: `sdkEventContract.spec.js` afirma que a linha do lead **segue sem
  evento de `window` no documento**. No dia em que o contrato passar a nomear um, o teste reprova e
  obriga a reconciliação.

**Decisão que peço ao coordenador:** ou (a) o contrato de 5.03 ganha a linha
`chatwoot:lead-identified` para o fato do lead, e o teste é atualizado junto; ou (b) o aceite de 5.04
troca `lead_identified` por outro quarto evento observável, e eu removo a emissão de `window`. Até a
decisão, o comportamento entregue é o (a) implementado.

### 4.2 Um ponto do comentário de 5.03 que ficou desatualizado — corrigido no cabeçalho, não no contrato

O cabeçalho de `TrackingEventListener` dizia *"os eventos #1 a #9 nascem no widget e no store (bloco
5.04) e não devem ser emitidos daqui também"*. Com T-C3.7, o **#5** passa a nascer aqui. Ajustei o
comentário do arquivo explicando por que isso **não** viola a RG4 ("uma emissão por fato"): o widget
emite o evento de `window`, que é vocabulário, não um segundo evento de tracking. O documento de
contrato **não** foi tocado.

---

## 5. Os mecanismos que executam o aceite, e o vermelho de cada um

O aceite tem duas metades. Cada uma tem mecanismo, e cada mecanismo foi medido **vermelho antes**,
com o código anterior **restaurado no lugar** — não imaginado.

### 5.1 "renomear um evento quebra o CI"

`app/javascript/widget/specs/sdkEventContract.spec.js` — **16 exemplos**.

Ele **não repete os nomes**: lê a tabela da §1 de `docs/tracking/contrato-de-eventos.md` (documento
de outra trilha, declarado no próprio texto como fonte da verdade) e exige que batam, string por
string, com `constants/sdkEvents.js`, de onde todo emissor importa. São duas fontes independentes.

Tem uma asserção contra **verde vazio**: se a §1 sumir ou for renomeada, `expect(linhas.length)
.toBe(7)` reprova — sem ela, todos os `it.each` passariam por vacuidade.

> **Vermelho medido.** Renomeando `chatwoot:conversation-created` para
> `chatwoot:conversation-criada` em `sdkEvents.js`: **2 exemplos vermelhos**, ambos nomeando o
> evento (`expected [...] to include 'chatwoot:conversation-created'`). Revertido em seguida.

### 5.2 "a ordem é observável por `addEventListener` em navegador real"

`spec/e2e/widget/sdkEvents.spec.js` — **6 testes**, Chromium real, no harness de widget do projeto:
SDK real no documento do host (`:8899`), painel real no iframe (`:3999`), `postMessage` real com
verificação de origem. O que o teste escuta é o que o GTM do cliente escutaria.

Os nomes também vêm da fonte única — lidos do arquivo, não digitados no teste.

| Teste | Mede |
|---|---|
| 1 | a ordem `opened → conversation-created → prechat-submitted → lead-identified`, do clique real no lançador ao submit real do formulário |
| 2 | cada evento **uma vez** e com o payload exato; **e que o e-mail e o nome digitados NÃO aparecem** em nenhum `detail` |
| 3 | `reset()` anuncia `chatwoot:reset-completed` (T-I4.5) |
| 4 | `chatwoot:message-sent` pelo composer real, provando que `conversation-created` o precede no caminho sem pré-chat |
| 5 | `chatwoot:csat-submitted` por clique na carinha de nota 5 |
| 6 | `chatwoot:campaign-shown` com o widget **fechado**, que é a única condição em que o teaser aparece |

Os testes 4, 5 e 6 existem porque o **BK-17** — a outra origem deste bloco — pede os **seis** eventos
recebidos por uma página de teste, não os quatro do aceite do mestre.

> **Vermelho medido.** Com os cinco arquivos de produção restaurados na versão de
> `redesenho-integra`: **6 de 6 vermelhos**. Com o código do bloco: **6 de 6 verdes**.

### 5.3 As emissões, do store, uma vez

`app/javascript/widget/store/modules/specs/sdkEventsFromStore.spec.js` — **16 exemplos**, cobrindo os
quatro módulos juntos, porque a ordem não é propriedade de nenhum deles isolado.

> **Vermelho medido.** Com os quatro módulos restaurados: **12 vermelhos, 4 verdes**. Os 4 que
> passam são as asserções **negativas** ("não emite quando o servidor recusou", "não repete
> `conversation-created` para quem já tinha conversa", "não sai de `contacts/get`", "não emite com o
> widget aberto") — elas passam por vacuidade sem código nenhum, e existem como guarda contra
> regressão futura, não como prova desta entrega. Está dito aqui para não inflar o número.

### 5.4 O emissor e o servidor

- `app/javascript/widget/helpers/specs/sdkEventEmitter.spec.js` — **13 exemplos** (filtro de PII,
  guarda de exceção, "uma vez" por chave, e o caso de não gastar a marca quando o envio falhou).
- `spec/listeners/tracking_event_listener_lead_spec.rb` — **18 exemplos**. Vermelho medido: com o
  listener anterior, **18 `NoMethodError`**.

---

## 6. Números medidos

| Medida | Antes | Depois | Teto |
|---|---|---|---|
| `sdk.js` cru | 38,13 kB | **38,21 kB** | 40 kB |
| `sdk.js` gzip | 13,54 kB | **13,56 kB** | 15 kB |

O `SDK_EVENT_CONTRACT` **não** entra no bundle do SDK — tree-shaking o remove, porque só o widget o
importa. Os +80 B crus são o código do `reset-completed` e a constante nova.

| Suíte | Resultado |
|---|---|
| `vitest` widget + sdk | **74 arquivos, 742 exemplos, 0 falhas** |
| 16 snapshots + matriz do widget (`widget.spec.js`) | **24 de 24 verdes, nenhum pixel movido** |
| `sdkEvents.spec.js` (navegador real) | **6 de 6 verdes** |
| `rspec` listeners + contato + tracking | **461 exemplos, 16 falhas** — todas **pré-existentes** |
| `eslint` nos 11 arquivos tocados | limpo |
| `rubocop` no listener | limpo |

**As 16 falhas de rspec são da base, não deste bloco** — verificado restaurando o listener anterior:
com ele, o mesmo conjunto dá 34 falhas (16 da base + 18 minhas, que são o vermelho esperado). Ficam
em `hook_listener_spec.rb` (8), `notification_listener_spec.rb` (3), `webhook_listener_spec.rb` (2),
`reporting_event_listener_spec.rb` (1), `automation_rule_listener_reply_resume_spec.rb` (1),
`action_cable_listener_spec.rb` (1). Nenhuma toca tracking.

Banco: **`chatwoot_test_o4track`**, dedicado, `RAILS_ENV=test`. Nenhuma migration rodou contra
desenvolvimento ou homologação. Nenhum disparo saiu para Meta, Google ou GlitchTip: o E2E intercepta
100% das rotas que usa e o harness é Node local; o server-side só **grava** em `tracking_events` —
quem entrega a destino externo é 5.11, que não existe.

---

## 7. Os quatro blocos bloqueados, com o número do bloco que falta

### 7.1 **5.08** — bloqueado por **5.07** e por **5.01**

`5.07` está verificadamente **não feito**: `config/environments/production.rb` ainda serve
`Cache-Control: public, max-age=31556952` **sem `ETag` e sem `Last-Modified`**. Ele é dependência
declarada de 5.08 na §2.2 e entrega o "carregador fino" de que o *"carregado sob demanda"* do meu
aceite depende.

### 7.2 **5.09** — bloqueado por **5.01**

`1.23`, a outra dependência, está na base. O que falta é o **formato** de `consent_mode`.

Achado que vale registrar: **a projeção pública já existe na minha base**. O bloco 3.04 entregou
`WidgetTrackingProjection::PUBLIC_KEYS` = `meta_pixel_id`, `ga4_measurement_id`,
`google_ads_send_to`, `event_map`, `consent_mode`, `test_mode`, publicada nos **dois** montadores
(`show.html.erb` como `widgetTracking`, `create.json.jbuilder` como `widget_tracking`). E a recusa de
segredo do aceite de 5.01 (*gravar `access_token` → 422*) **já é atendida** pelo
`SECRET_KEY_PATTERN` de 3.01 — medido, não suposto:

```ruby
inbox.widget_tracking = { 'meta_pixel_id' => '123', 'access_token' => 'SEGREDO' }
inbox.valid?   # => false
# ["não aceita segredo: a chave \"access_token\" deve ficar na tela de credenciais, nunca aqui"]
```

O que 5.01 ainda deve é o **schema JSON** de `widget_tracking`: não há `WidgetTrackingSchema` ao lado
de `WidgetTriggersSchema` e `WidgetAppearanceSchema`, e por isso

```ruby
inbox.widget_tracking = { 'consent_mode' => { 'qualquer' => 'coisa' } }
inbox.valid?   # => true, sem erro nenhum
```

Ou seja: a **chave** `consent_mode` existe; os **valores** que ela aceita, não. Ler a chave é
consumir contrato; inventar os valores é inventar a config — e o despacho me proibiu isso,
corretamente.

### 7.3 **5.10** — bloqueado por 5.08 e 5.09 (5.04 pronto)

### 7.4 **5.13** — bloqueado por 5.10 e por **5.11**, declarado "não iniciado" no relatório de
`o4-server-cred` (§ Escopo realocado)

### 7.5 A proposta que peço ao coordenador decidir

Com todos os quatro bloqueados, o que dá para fazer **sem tocar arquivo de outra trilha e sem
inventar config** é a **ponta consumidora**, com defaults que degradam para o comportamento de hoje:

> `sdk/tracking/config.js` — leitor de `chatwootWebChannel.widgetTracking` usando **exatamente** as
> seis chaves de `WidgetTrackingProjection::PUBLIC_KEYS`, que **já são um fato do repositório**, com
> um teste de contrato que lê `PUBLIC_KEYS` do arquivo Ruby e exige que o leitor JS conheça as mesmas
> seis (a mesma técnica não-tautológica do §5.1). Defaults: **tudo desligado**; sem configuração,
> nada dispara — que é literalmente o comportamento de hoje, e é também o *"somente dataLayer como
> padrão de fábrica"* que 5.10 vai querer.

Isso destrava a metade client-side de 5.10 sem depender do schema de 5.01. **Não executei**: a
decisão é sua. Se autorizar, é meia jornada.

---

## 8. Três coisas que o próximo executor precisa saber

### 8.1 `git stash` é ARMADILHA neste repositório — a pilha é compartilhada entre as 24 worktrees

Usei `git stash push` / `git stash pop` para medir o vermelho do E2E. **Entre o push e o pop, outra
worktree mexeu na pilha**: o meu stash sumiu e o meu `pop` trouxe o `stash@{0}` **de outra pessoa**
("On homologacao: pre-deploy 15/08: 27 modificados da box"), com conflitos em 6 arquivos do
dashboard. A execução do E2E naquele momento saiu **verde pelo motivo errado** — o código de
produção já tinha voltado.

Estado depois de arrumar, **verificado**:

- meu worktree voltou a `HEAD` limpo; **nada do meu trabalho se perdeu** (estava commitado);
- o `stash@{0}` alheio **continua intacto na pilha** (o pop conflitou, e conflito preserva a
  entrada);
- varri **as 24 worktrees** (as 20 de `/home/chatwoot/chatwoot*` e as 4 de `/tmp/ci-*`) por
  marcadores do meu código (`emitSdkEventOnce`, `CHATWOOT_RESET_COMPLETED`,
  `CAMPOS_PADRAO_DO_PRECHAT`): **zero ocorrências fora daqui** — nenhum arquivo meu vazou para
  worktree alheia.

Refiz o vermelho **sem `git stash`**, com a receita segura:

```bash
cp <arquivo> $SCRATCH/         # guarda o novo
git show redesenho-integra:<arquivo> > <arquivo>   # escreve o antigo, sem tocar em index nem stash
<roda o teste>
cp $SCRATCH/<arquivo> <arquivo>                    # devolve
```

**Regra para as próximas trilhas: não use `git stash` enquanto houver agentes concorrentes em outras
worktrees deste repositório.** A pilha é do repositório, não da worktree, e `pop` é por índice.

### 8.2 O glob do Playwright não atravessa `/`

`page.route('**/api/v1/widget/messages*')` **não** casa `/api/v1/widget/messages/207` nem
`/widget/conversations/toggle_typing`. As duas caíam no harness, que responde **500** ao que não
conhece, e a fixture de `spec/e2e/fixtures.js` reprova por erro de console — com uma mensagem que
parece problema de rede e não é. Use expressão regular.

### 8.3 A sabotagem do `emitSdkEvent` que NÃO existe, e por que isso importa para 5.10

O emissor engole exceção de propósito e **conta** o erro pela telemetria de 2.13. Quando 5.10 puser
`fbq`/`gtag` no caminho, a guarda de exceção dele precisa ser **a mesma** — código de terceiro na
página do cliente lança por motivos que não controlamos, e um `throw` ali pararia a conversa. O
gancho já está pronto: basta 5.10 emitir por este módulo em vez de chamar `window.fbq` direto de
dentro de uma ação.

---

## 9. Commits (locais; nada pushado, nenhum PR, nenhum deploy)

| Commit | Conteúdo |
|---|---|
| `b4b31ad74f` | merge de `o4-server-cred` (5.03), conflito de `db/schema.rb` resolvido pela versão maior |
| `20a7d937a3` | **feat(5.04)** — os sete eventos, o emissor, as emissões do store, o `reset-completed` e o `chatspx_lead` server-side |
| `16a8450472` | **test(5.04)** — os seis eventos do BK-17 medidos em navegador real (message-sent, csat-submitted, campaign-shown) |

Arquivos novos: `widget/helpers/sdkEventEmitter.js`, três specs de unidade, uma spec E2E, uma spec
RSpec. Arquivos tocados: `widget/constants/sdkEvents.js`, quatro módulos do store,
`sdk/IFrameHelper.js`, `app/listeners/tracking_event_listener.rb`.

**Nenhuma string nova de interface** foi criada por este bloco — nada a traduzir em `pt_BR`/`en`.

---

## 10. O relay estava sem coordenador — a mensagem que eu teria mandado está aqui

`orca orchestration run-show --run run_26dd5a774ba8` e o `send` do `worker_done` responderam
**"No owning Orca client is connected to the relay"**. Não há coordenador conectado, então o
`worker_done` **não foi entregue**. Conforme a instrução ("se o relay estiver sem coordenador,
escreva tudo no relatório, inclusive o que você diria por mensagem"), segue o texto:

> **Onda 4 · trilha tracking client-side — 5.04 ENTREGUE; 5.08 / 5.09 / 5.10 / 5.13 bloqueados.**
>
> 5.04 entregue e provado: **45 exemplos de unidade em JS, 18 em RSpec e 6 em Chromium real**, todos
> com **vermelho medido antes**, restaurando o código anterior no lugar. Commits locais `20a7d937a3` e `16a8450472`, mais
> o merge `b4b31ad74f` de `o4-server-cred` — precisei dele para chamar `Tracking::EventRecorder`;
> conflito só na linha de versão do `db/schema.rb`, resolvido pela maior.
>
> **DIVERGÊNCIA DE CONTRATO, escalada e não negociada.** O contrato de 5.03 registra o fato do lead
> como server-side puro (a coluna do evento de `window` traz um travessão), mas o meu aceite exige
> `lead_identified` **observável por `addEventListener` em navegador**. Implementei os dois
> vocabulários — `chatspx_lead` só no servidor, onde a transição é verificável;
> `chatwoot:lead-identified` no `window`, sem PII — e **congelei a divergência em teste**. Decida:
> (a) o contrato ganha a linha do evento de `window` para esse fato, ou (b) o aceite troca o quarto
> evento. Detalhe no §4.1.
>
> **Bloqueios, com o número do bloco que falta:** 5.08 por **5.07** (verificado não feito:
> `production.rb` ainda sem `ETag`) e por **5.01**; 5.09 por **5.01** (a chave `consent_mode` já
> existe na projeção pública de 3.04, mas o **formato** dela é o schema de 5.01, que não existe —
> medido: hoje a inbox aceita qualquer coisa em `consent_mode` sem erro); 5.10 por 5.08 e 5.09;
> 5.13 por **5.11**, não iniciado.
>
> **Proposta (§7.5):** posso escrever a ponta consumidora — leitor de `widgetTracking` com as seis
> chaves de `WidgetTrackingProjection::PUBLIC_KEYS`, que **já são fato do repositório**, tudo
> desligado por default (= comportamento de hoje) — sem tocar arquivo de outra trilha e sem
> inventar config. Meia jornada. **Não executei: a decisão é sua**, e o despacho foi explícito em
> não inventar a config de tracking por conta própria.
>
> **Aviso para todas as trilhas:** a pilha do `git stash` é **do repositório**, compartilhada pelas
> 24 worktrees, e `pop` é por índice. Perdi um stash para outra worktree e recebi o dela, com
> conflitos. Nada vazou (varri as 24), mas **nenhum executor deve usar `git stash`** enquanto houver
> agentes concorrentes. Receita segura no §8.1.
