# Grupo A, itens #6 e #7 — instalação condicional de tag (5.10 / T-C4.3) e o 422 da Tela 4 (5.01)

> Trilha `spx-tela4-tracking`, 24/08/2026. Commit local `17bf7f8f09` sobre `homologacao` (`6d56c722c8`).
> Nada foi empurrado, nenhum PR foi aberto, nenhuma VM foi tocada.

## O que foi entregue

| Item | Bloco | Estado | Onde |
|---|---|---|---|
| **#7** | 5.10 · T-C4.3 | **FEITO** | `sdk/tracking/tags.js`, `widget_tracking_schema.rb`, `widget_tracking_projection.rb`, `TrackingPage.vue`, i18n |
| — | 5.01 (prioridade do coordenador) | **FEITO** | `widget_tracking_schema.rb`, `widget_tracking_projection.rb`, `TrackingPage.vue` |
| **#6** | 4.14 · tela de entregas | **NÃO INICIADO** — travado por propriedade de arquivo, não por código. Diagnóstico completo na §4 |

---

## 1. Item #7 — T-C4.3, instalar a tag que falta

### O buraco que ele fecha

A ponte de tags só falava com a tag que **já existia** na página (`typeof window.fbq !== 'function'`
→ retorna). Consequência: **o cliente que colava o Pixel ID na nossa tela e não tinha o pixel no
site não recebia nada na Meta — e nada avisava.**

Agora existe o caminho 2 da precedência do plano (§A.7):

1. Pixel configurado **e** `fbq` na página → `trackSingle` naquele id. Nada é instalado.
2. Pixel configurado e `fbq` **ausente** → instalar, sem `PageView`, **e só com opt-in**.
3. Sempre, independente de 1 e 2 → `dataLayer.push`.

### O que foi decidido, e por quê

**`install_tags` é objeto (`meta` / `google`), não booleano.** O plano (§C1) diz "booleano"; o
briefing desta trilha diz "o objeto novo leva `additionalProperties: false` no nível dele também".
Segui o briefing, e a razão de produto é a mesma: instalar o pixel da Meta e instalar o gtag do
Google são **autorizações diferentes**. O cliente com GTM no site quer o Google vindo do container
dele, e ainda assim pode querer o pixel da Meta vindo de nós. Um booleano único o obrigaria a
escolher entre não medir na Meta e deixar um segundo gtag numa página que já tem governança de tags.

**A decisão Q5 está escrita como ausência de chave.** Não há valor de fábrica em lugar nenhum: quem
nunca marcou o interruptor não tem `install_tags` no banco, e `undefined` cai no `!` da ponte. É a
forma da decisão que não pode ser desfeita por engano.

**O `send_to` do Ads entra junto na instalação do Google.** Instalar só o GA4 deixaria a conversão do
Ads sem transporte — o mesmo silêncio que o T-C4.3 existe para acabar. A conta é a parte do
`AW-XXXX/rótulo` antes da barra (`contaDoAds`); o rótulo pertence à conversão.

**O consentimento vem ANTES da instalação.** Injetar `fbevents.js` ou `gtag.js` é uma requisição a um
terceiro que lê cookie. Nenhum `isAllowed` posterior desfaz um script já carregado. A ordem dos
guardas em `paraMeta` foi invertida por isso.

**`arguments` e `_fbq` ficaram como estão, com `eslint-disable` e a razão escrita.** São contrato do
`fbevents.js`/`gtag.js`, que leem a fila que fica no `window`. "Modernizar" para rest args é uma
mudança cujo único lugar de descobrir o erro é a conta de anúncio do cliente.

### Peso

`tracking.js`: **9.236 → 10.637 B cru; 3.436 → 4.010 B gzip (+574 B)**. É o artefato **sob demanda**
(T-C4.9), buscado só quando a inbox tem tracking configurado.

**O `sdk.js` não foi tocado.** `loadCollector` faz `import(/* @vite-ignore */ url)` — import por URL
de runtime — então o bundler nunca puxa `tags.js` para o `sdk.js`. O teto A13 (15.000 B gzip, com os
6 bytes de folga que o `ESTADO-BLOCOS-24ago.md` §5.3 registra) continua exatamente onde estava.

---

## 2. A prioridade do coordenador — o 422 da Tela 4 (bloco 5.01)

### O defeito

O schema declarava `event_map` como `nome → string`, `test_mode` como booleano, e **não declarava
`lead_value`**. A Tela 4 grava objeto nos três. Reproduzido campo a campo com o payload real da tela
contra o modelo real:

```
== o payload INTEIRO da Tela 4 ==
  RECUSA  tudo junto, como a tela salva
== campo a campo ==
  OK      meta_pixel_id / ga4_measurement_id / google_ads_send_to / consent_mode
  RECUSA  event_map    tem valor inválido em "event_map/chatspx_widget_loaded": deve ser do tipo string
  RECUSA  test_mode    tem valor inválido em "test_mode": deve ser do tipo boolean
  RECUSA  lead_value   tem valor inválido em "lead_value": campo desconhecido
```

Depois da correção, as oito linhas são `OK`.

### Por que nenhum teste pegava

**Cada lado testava o SEU formato.** O spec do schema gravava `{ 'conversation_started' => 'Lead' }` e
ficava verde. O spec da tela montava o objeto e ficava verde. Ninguém rodava o payload da **tela**
contra o **validador** — e o vão entre dois testes verdes é onde o defeito morava.

O bloco novo `'a Tela 4 salva: o payload REAL da tela contra o validador REAL'` fecha esse vão, e
**lê o contrato do front**: extrai os doze eventos e as subchaves de `DEFAULT_EVENT_MAP` do
`widgetTrackingContract.js`. Se alguém acrescentar um evento lá, o payload daqui cresce junto.

### Qual formato venceu, e por que não foi moeda ao ar

**O objeto**, porque ele diz o que a string não consegue. `{ enabled: false, meta: nil, ga4:
"widget_open" }` é "manda só ao GA4, com este nome, desligado por padrão" — três decisões que uma
string única apaga. Onze das doze entradas de fábrica usam `nil` em pelo menos um destino. O mesmo
vale para `test_mode`: um booleano não guarda o `test_event_code` da Meta nem o `started_at`, e sem
`started_at` o desligamento automático de 7 dias vira uma frase na tela e nada no dado.

**As formas antigas continuam aceitas**, e não por indecisão:

- a **string** em `event_map` já era lida por `entradaDoMapa` ("renomeie assim nos dois destinos"), e
  uma inbox pode tê-la gravada por API;
- o **booleano** em `test_mode` idem — e a tela agora o **normaliza** (`typeof === 'boolean'` →
  `{ enabled: bruto }`). Sem essa linha, `true.enabled` é `undefined` e a tela mostraria DESLIGADO
  para quem está com o modo teste ligado: o cliente seguiria mandando evento de teste para a Meta
  achando que não estava.

Os três sub-objetos novos levam `additionalProperties: false`. `lead_value` ficou **sem teto e sem
mínimo** de propósito: a tela não valida faixa nenhuma, e um limite que ela não conhece devolveria de
novo um 422 que o administrador não consegue explicar — que é o defeito sendo consertado.

---

## 3. Provas

Banco dedicado `chatwoot_test_tela4tracking`. `.env` copiado do repo base (sem ele o rspec sai
"0 examples", que lê-se como verde e não testou nada).

| Comando | Antes | Depois |
|---|---|---|
| `rspec spec/models/concerns/widget_tracking_schema_spec.rb` | **20 exemplos, 0 falhas** | **37 exemplos, 0 falhas** |
| `rspec` nos 5 specs de `widget_tracking` | — | **77 exemplos, 0 falhas** |
| `rspec` incluindo controller/requests/serviços relacionados | — | **121 exemplos, 0 falhas** |
| `vitest run app/javascript/sdk/` | — | **320 testes / 24 arquivos, 0 falhas** |
| `vitest run .../inbox/widget/` | 643 testes | **653 testes / 29 arquivos, 0 falhas** |
| `vitest` dos dois juntos | — | **779 testes / 36 arquivos, 0 falhas** |
| `node .../browser/ponte-de-tags.check.mjs` (Chromium real) | **36 asserções** | **56 asserções, todas passaram** |
| `rubocop` + `eslint` nos arquivos tocados | — | **limpos** (1 warning pré-existente) |

### Os testes ACUSAM — quatro sabotagens, com o vermelho medido

| Sabotagem | Resultado |
|---|---|
| Tirar `additionalProperties: false` de dentro de `install_tags` | o exemplo da subchave desconhecida (`install_now`) fica **vermelho** |
| Voltar o schema para o de `HEAD` | **7 de 37** exemplos falham |
| Voltar `garantirMeta` para o comportamento de ontem (nunca instala) | **3 de 60** testes falham |
| Instalar **com** `PageView` e sem `send_page_view: false` | **2 de 60** falham |
| Voltar `TrackingPage.vue` para o de `HEAD` (sem o interruptor) | **8 de 29** falham |

Nenhuma afirmação de ausência ficou sozinha: cada "não instalou" tem, ao lado, o exemplo que **liga**
o interruptor e exige o efeito. Sem o par, "não mandou `install_tags` ligado" passaria também numa
tela que não tem interruptor nenhum — que era exatamente o estado de ontem.

### O ACEITE do 5.10, medido em navegador real

> *"Página com 3 pixels: o evento NÃO vaza; sem pixel: nenhum PageView duplicado; gtag/dataLayer do
> cliente continuam funcionais; console limpo."*

- **3 pixels, não vaza** — cenário 1: toda chamada é `trackSingle` no pixel `222`, nenhuma escapa.
- **sem pixel, nenhum PageView duplicado** — cenário 2 (opt-in desligado: nada instalado, nenhum
  script, nenhuma requisição externa) **e** cenário 4 (opt-in ligado: `init` sai, `PageView` **não**).
- **gtag/dataLayer continuam funcionais** — cenário 1 verifica por **identidade** (`===`), e a fila
  que o cliente já tinha sobrevive.
- **console limpo** — asserido nos cinco cenários, com o console do Chromium de verdade.
- **cenário 5 (novo)** — consentimento negado + opt-in ligado: nada instalado, e nenhuma tentativa
  de requisição a terceiro (nem servida, nem abortada).

O cenário 4 serve os scripts de terceiro por **dublê local** (`route.fulfill` com corpo vazio): o que
se mede é a **nossa** sequência de comandos, não o comportamento da Meta. Sair para a internet
tornaria o verificador dependente de rede e do humor de dois terceiros.

---

## 4. Item #6 (bloco 4.14) — por que não foi feito

**Não é falta de código, é propriedade de arquivo.** Pedi autorização três vezes e não houve
resposta: `ask` (900 s, expirou), `escalation`, `ask` (420 s, expirou). O briefing é explícito —
*"Se precisar de algo fora dela, NÃO edite"* — e a regra existe para não colidir com as trilhas
rodando em paralelo. Editar assim mesmo trocaria uma entrega atrasada por um conflito.

### O que eu confirmei, para quem pegar

**O backend está completo e funcional** (conferido abrindo arquivo, não por inferência de nome):

| Peça | Onde | Estado |
|---|---|---|
| `POST .../webhooks/:id/rotate_secret` | `config/routes.rb:567-574` + `webhooks_controller.rb:29-32` | existe; devolve o segredo novo **uma vez**, via `create.json.jbuilder` |
| `GET .../webhooks/:id/deliveries` | idem + `webhooks_controller.rb:35-37` | existe; 100 mais recentes, view `deliveries.json.jbuilder` pronta com `delivery_id`, `event`, `status`, `http_status`, `attempts`, `error_message`, `delivered_at`, `created_at` |
| `POST .../webhooks/:id/replay` | idem + `webhooks_controller.rb:40-44` | existe; **não regenera** o `delivery_id` — é ele que permite ao destino deduplicar |
| parar de expor o segredo no `index` | `_webhook.json.jbuilder` | **já feito**: expõe `has_secret`, e `secret` só quando `expose_secret` |
| ping de validação no cadastro | `webhooks_controller.rb:15` | `@webhook.send_validation_ping!`, e a falha dele não derruba a criação |

**O que falta é só front**, e são estes arquivos — nenhum deles na minha lista:

- `app/javascript/dashboard/api/webhooks.js` — hoje é um `ApiClient` pelado, sem os três métodos;
- `app/javascript/dashboard/routes/dashboard/settings/integrations/Webhooks/` — `Index.vue`,
  `WebhookRow.vue`, `EditWebHook.vue`, `NewWebHook.vue`;
- `app/javascript/dashboard/i18n/locale/{en,pt_BR}/integrations.json`.

O aceite do 4.14 é *"a tela mostra a entrega falhada e o reenvio chega com o **mesmo**
`X-Chatwoot-Delivery`; o `index` não expõe segredo"*. A segunda metade **já passa**; a primeira
precisa de um consumidor de `deliveries` + um botão que chame `replay` e mostre o `delivery_id` que
volta na resposta.

---

## 5. O que ficou anotado e não foi enxertado

- **`lead_value` entrou na projeção pública** (`PUBLIC_KEYS` e `PUBLIC_TRACKING_KEYS`), porque o plano
  §C1 o marca como público ("valor calculado"). Ele agora viaja no HTML de toda página do site do
  cliente, como os outros identificadores públicos. Se isso for indesejado, o lugar de mudar é a
  projeção — mas aí a tela volta a receber 422 nesse campo, e a decisão precisa ser tomada junto.
- **`instalacaoAutorizada()`** foi exposto na ponte como leitura (não efeito). Serve ao diagnóstico do
  5.14 e ao verificador; nenhum consumidor de produção o usa ainda.
- O **modo "somente dataLayer"** continua sendo o padrão de fábrica (T-C4.10) e não foi tocado.
