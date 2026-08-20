# Contrato de eventos de tracking — ChatSPX

**Bloco 5.03** do `PLANO-MESTRE` (origem: T-C3.1, T-C3.9, BK-31). Versão **2**, 19/08/2026
(v1 em 18/08; a v2 acrescenta a §2.1, a família da abordagem do bloco **4.21**).

Este documento é a **fonte da verdade do contrato**. Quem for emitir, consumir ou entregar um evento
lê daqui — não do código. Mudança de nome, tipo ou default de campo **muda este arquivo primeiro**.

Consumidores conhecidos, todos em outras trilhas: **5.04** (emissão dos eventos do widget), **5.05**
(`event_id` de volta ao widget), **5.16** (`track(name, properties)` do site do cliente), **5.10**
(ponte de tags client-side), **5.11** (fila server-side), **5.13** (deduplicação), **5.14**
(auditoria e diagnóstico), **5.15** (contrato público) — e **4.21**, a instrumentação dos três níveis
de abordagem, que é o primeiro consumidor a ter entrado (ver §2.1).

---

## 1. Dois vocabulários, uma emissão

Arbitragem **A9** do `PLANO-MESTRE`: são dois contratos com públicos distintos, e forçá-los ao mesmo
nome piora os dois. **A emissão é uma só.**

| Fato | Evento de `window` (o site escuta) | Evento de tracking (GA4/Meta/`dataLayer`) |
|---|---|---|
| conversa criada no servidor | `chatwoot:conversation-created` | `chatspx_conversation_started` |
| pré-chat concluído | `chatwoot:prechat-submitted` | `chatspx_prechat_submitted` |
| visitante enviou mensagem | `chatwoot:message-sent` | — (sinal interno) |
| CSAT respondido | `chatwoot:csat-submitted` | ⚠ ver §6, ponto aberto |
| teaser/campanha exibida | `chatwoot:campaign-shown` | — |
| contato passou a ter e-mail ou telefone | — (server-side) | `chatspx_lead` |
| conversa resolvida | — (server-side) | `chatspx_conversation_resolved` |

**Regras de nome, e as três são verificadas em código** (`TrackingEvent`):

1. prefixo fixo `chatspx_`;
2. `snake_case` (minúsculas, dígitos e `_`, começando por letra);
3. **≤ 40 caracteres** — é limite do GA4, não preferência nossa.

Nome fora dessas regras é **recusado na gravação** com erro que nomeia a regra violada. O registro
**não** valida contra a lista fechada da §2: o bloco 5.16 deixa o site do cliente emitir evento
próprio (`chatspx_orcamento_pedido`), e uma lista fechada mataria isso. O que o formato garante é
que nenhum nome inválido chegue ao GA4 do cliente.

---

## 2. Os doze eventos

Tabela mestre, herdada da §A.6 do `25-plano-tracking-integracao.md`. A coluna **`event_id`
propagado** responde *"este evento vai pelos dois caminhos com o mesmo id, para a Meta deduplicar?"*
— e **não** *"este evento tem `event_id`?"*. Ver §4.1: **todo** registro tem `event_id`.

| # | Evento | Quando dispara | Parâmetros | Server-side | `event_id` propagado | PII |
|---:|---|---|---|:---:|:---:|:---:|
| 1 | `chatspx_widget_loaded` | SDK pronto | `inbox_id` | não | não | não |
| 2 | `chatspx_widget_opened` | bolha aberta | `inbox_id`, `page_url` | opcional | não | não |
| 3 | `chatspx_conversation_started` | 1ª mensagem do visitante / conversa criada | `conversation_id`, `inbox_id`, `first_utm_*` | **sim** | **sim** | não |
| 4 | `chatspx_prechat_submitted` | pré-chat concluído | **nomes** dos campos, nunca valores | **sim** | **sim** | só server |
| 5 | `chatspx_lead` | contato passa a ter e-mail **ou** telefone | `value`, `currency`, `lead_source`, `conversation_id` | **sim** | **sim** | só server, hasheada |
| 6 | `chatspx_lead_qualified` | regra / agente / IA qualifica | `value`, `currency`, `qualification_reason` | **sim** | **sim** | só server |
| 7 | `chatspx_lead_disqualified` | descartado | `disqualified_lead_reason` | opcional | não | não |
| 8 | `chatspx_agent_engaged` | agente humano assume | `lead_status`, `agent_id` | opcional | não | não |
| 9 | `chatspx_meeting_scheduled` | agendamento confirmado | `scheduled_at` | **sim** | **sim** | só server |
| 10 | `chatspx_conversation_resolved` | conversa resolvida | `resolution`, `duration_s` | opcional | não | não |
| 11 | `chatspx_deal_won` | negócio ganho | `value`, `currency`, `gclid`, `deal_id` | **só server** | **sim** | só server |
| 12 | `chatspx_deal_lost` | negócio perdido | `unconvert_lead_reason` | opcional | não | não |

**O que o 5.03 emite hoje:** apenas o **#10**, `chatspx_conversation_resolved`, que é o aceite deste
bloco e um fato que **só o servidor conhece**. Os #1 a #9 são do widget e do store — bloco **5.04**,
outra trilha. O #11 e o #12 dependem do funil (bloco 5.21). Acrescentar um fato server-side custa
**um método** em `TrackingEventListener`, no formato do `BaseListener`; a infraestrutura já aceita
todos.

### 2.1 A família da abordagem — bloco 4.21 (13→19/08/2026)

Quatro nomes, um por fato da abordagem em três níveis (decisão **D1**). Eles **não** estão na tabela
de doze porque não são fatos do funil: são a instrumentação da superfície que produz o funil, e é ela
que responde *"qual nível converte mais nesta conta"*. Entram por
`POST /api/v1/widget/approach_events`, com a mesma autenticação de sessão do resto do widget.

| Evento | Quando dispara | Server-side | `event_id` propagado | PII |
|---|---|:---:|:---:|:---:|
| `chatspx_approach_shown` | teaser apareceu, ou o painel abriu sozinho (`aggressive`) | **sim** | não | não |
| `chatspx_approach_dismissed` | o visitante fechou o teaser | **sim** | não | não |
| `chatspx_approach_opened` | o painel abriu a partir da abordagem | **sim** | não | não |
| `chatspx_approach_converted` | o visitante **enviou mensagem** depois de ter sido abordado | **sim** | não | não |

**Parâmetros, iguais nos quatro** — e são exatamente três, todos vocabulário fechado da configuração
(`WidgetTriggersSchema::APPROACHES`), nenhum vindo do cliente em texto livre:

| Campo | O que é |
|---|---|
| `approach` | o nível **efetivo** desta abordagem, depois da degradação por familiaridade (4.19) |
| `approach_configured` | o nível que o administrador escolheu |
| `degraded` | derivado — `approach != approach_configured`. Existe para separar *o efeito do nível* do *efeito da degradação* numa consulta só |

**A `dedup_key` desta família é `approach:<source_id>:<ordinal>`**, e o `ordinal` é a ordem da
abordagem na vida daquele navegador — vem do cookie do 4.19, que já contava. Ele é passado
**explicitamente** porque a derivação padrão da §4.2 erra nos dois sentidos aqui, e os dois foram
medidos removendo a linha e vendo o spec ficar vermelho:

- **conta demais** — a derivação usa `occurred_at.to_i`, e o reenvio cai noutro segundo: três
  mensagens seguidas do visitante viram três conversões;
- **conta de menos** — duas abordagens genuínas ao mesmo visitante dentro do mesmo segundo
  compartilham a chave derivada e viram uma linha só.

O que a derivação padrão **não** erra: ela não mistura visitantes diferentes, porque o assunto dela
cai para `contact_id`, que este endpoint passa.

**O `converted` não dispara sem `shown` na mesma página.** Quem abriu o painel pelo lançador não
converteu *por* uma abordagem, e contá-lo inflaria o numerador do nível que estava configurado sem
ter sido usado.

### 2.2 A família do teste A/B de fluxo — bloco 6.05 (19/08/2026)

Três nomes, um por fato do experimento. Como a família da abordagem, eles **não** estão na tabela de
doze: não são fatos do funil do cliente, são a instrumentação que responde *"qual variante deste
fluxo converte mais"*. Todos são **server-side** — quem os emite é o motor de fluxos
(`Flows::AbTracking`), nunca o navegador — e **nenhum propaga `event_id`**: não são fatos de
conversão do negócio, e mandá-los à Meta ou ao GA4 encheria a conta do cliente de evento interno.

| Evento | Quando dispara | Onde, no código |
|---|---|---|
| `chatspx_flow_variant_assigned` | o motor **começa** a rodar a variante para este visitante — é o **denominador** | `Flows::RunnerService#perform` |
| `chatspx_flow_variant_step` | um nó do fluxo foi executado **com sucesso** | `Flows::StepInstrumentation#record_step` |
| `chatspx_flow_variant_converted` | o walk **chegou ao fim** | `Flows::RunnerService#finish_run` |

**Parâmetros, iguais nos três** — vocabulário fechado, tudo vindo da configuração e do próprio fluxo,
nada de texto livre do visitante:

| Campo | O que é |
|---|---|
| `experiment` | a chave declarada em `trigger_config.experiment.key`; flows que a compartilham são variantes |
| `variant` | o `flows.id` da variante — **a variante é o próprio fluxo**, então quem roda já sabe qual é |
| `variant_version` | `flows.version` [M20]. É o que faz publicar uma variante nova **não** invalidar o histórico da anterior: a linha antiga guarda a versão sob a qual aquele número foi obtido |
| `node_id` | **só no `_step`** — qual nó foi alcançado. A **ordem** das etapas não viaja no evento: quem ordena é o relatório, pela posição do nó em `flow.definition` |

**A `dedup_key` desta família é `flow_ab:<flow_id>:<conversation_id>:<sufixo>`**, com sufixo
`assigned`, `converted` ou `step:<node_id>`. Ela é passada **explicitamente** pela razão da §4.2, e
aqui o dano tem nome: num A/B, conversão contada duas vezes **é a variante errada ganhando**, porque
quem retenta mais é quem falhou mais. Medido removendo a linha e vendo o spec ficar vermelho nos dois
sentidos — retry 30 s depois vira duas conversões, e duas etapas genuínas no mesmo segundo viram uma.

**Consequência que é aceite, não efeito colateral:** o mesmo visitante que passa duas vezes pelo mesmo
nó (uma retomada depois de um `wait`, um retry do job) conta **uma** vez. O denominador é
*"visitantes que viram a variante"*, não *"vezes que o motor rodou"*.

**Fluxo fora de experimento não emite nada** — que é o estado de toda a frota hoje. `experiment`
ausente em `trigger_config` significa exatamente "nada muda".

---

## 3. Onde o evento é gravado

Duas tabelas. A primeira é **o fato**; a segunda é **cada tentativa de contar o fato a um destino**.

### 3.1 `tracking_events` — o fato, uma linha por ação do usuário

| Campo | Tipo | Nulo | Default | O que acontece se chegar ausente |
|---|---|:---:|---|---|
| `event_id` | string(36) | não | — | **gerado** (`SecureRandom.uuid`). É a chave de negócio, única na tabela |
| `name` | string | não | — | erro de validação nomeando o campo |
| `account_id` | bigint | não | — | erro (a conta é obrigatória; sem ela o dado não tem dono) |
| `inbox_id` | bigint | **sim** | `nil` | fica `nil`; evento de conta (ex.: negócio ganho no funil) não tem inbox |
| `conversation_id` | bigint | **sim** | `nil` | fica `nil` |
| `contact_id` | bigint | **sim** | `nil` | fica `nil` |
| `occurred_at` | datetime | não | — | **`Time.current`**. É o instante do FATO, não o da gravação (a Meta usa como `event_time`) |
| `properties` | jsonb | não | `{}` | vira `{}` |
| `source` | enum int | não | `server` | `server` (0), `widget` (1), `site` (2) |
| `dedup_key` | string | não | — | **derivada**: `"<name>:<conversation_id ou contact_id ou 'account'>:<occurred_at.to_i>"` |

**Índices:**

- único em `event_id` — dois registros nunca compartilham id;
- único em **(`account_id`, `name`, `dedup_key`)** — é a trava de idempotência do FATO (§4.2);
- `(account_id, name, occurred_at)`, `conversation_id`, `contact_id`, `inbox_id`, `occurred_at` (BRIN
  para varredura por período, como `reporting_events` já faz).

**Chaves estrangeiras, e a razão de cada `ON DELETE`** — a doutrina já escrita nesta base
(`20260723000000_cascade_conversation_deletion_for_orphan_blockers.rb`): coluna **NOT NULL** cujo
registro não existe sem o pai → `CASCADE`; coluna **nullable** de histórico de diagnóstico →
`SET NULL`, para que o histórico sobreviva **e para não bloquear a exclusão do pai**.

| FK | ON DELETE | Por quê |
|---|---|---|
| `account_id` → `accounts` | `CASCADE` | o evento não existe sem a conta |
| `inbox_id` → `inboxes` | `SET NULL` | apagar uma inbox não pode apagar o histórico de atribuição — nem falhar por causa dele |
| `conversation_id` → `conversations` | `SET NULL` | idem. É a cicatriz de `flow_runs`/`flow_step_logs`, que travavam `conversation.destroy!` |
| `contact_id` → `contacts` | `SET NULL` | idem |

### 3.2 `tracking_deliveries` — uma linha por (evento, destino)

| Campo | Tipo | Nulo | Default | O que acontece se chegar ausente |
|---|---|:---:|---|---|
| `tracking_event_id` | bigint | não | — | erro. FK `CASCADE`: apagar o evento apaga as entregas |
| `destination` | enum int | não | — | erro. `data_layer` (0), `meta_pixel` (1), `ga4_gtag` (2), `meta_capi` (3), `ga4_mp` (4), `google_ads` (5) |
| `status` | enum int | não | `pending` | `pending` (0), `sent` (1), `failed` (2), `skipped` (3), `dead` (4) |
| `attempts` | integer | não | `0` | `0`. O teto de 5 tentativas é política de 5.11, não da tabela |
| `http_status` | integer | sim | `nil` | fica `nil` |
| `error_code` | string | sim | `nil` | fica `nil` |
| `error_message` | text | sim | `nil` | fica `nil` |
| `field_names` | jsonb | não | `[]` | vira `[]`. Guarda **NOMES** dos campos enviados, **nunca valores** (T-C8.1, e é o que 5.12 verifica) |
| `emq` | decimal(3,1) | sim | `nil` | fica `nil`. Event Match Quality, quando o destino informa |
| `last_attempted_at` | datetime | sim | `nil` | fica `nil` |
| `delivered_at` | datetime | sim | `nil` | preenchido só quando o destino confirma |

**Índice único em (`tracking_event_id`, `destination`)** — é o aceite deste bloco, e o §4.3 explica
o que ele impede na prática.

---

## 4. As três regras que fazem o registro valer

### 4.1 Todo registro tem `event_id`; só alguns o propagam

`event_id` é UUID v4 gerado **no servidor** (regra RC7), uma vez por ação do usuário. Ele existe em
**todo** registro porque é a chave de negócio: é por ele que o painel de 5.14 encontra o evento, que
5.05 responde ao widget e que a fila de 5.11 é idempotente.

A coluna *"`event_id` propagado"* da §2 é outra coisa: diz quais eventos levam esse id **também**
ao navegador, para a Meta deduplicar o par (`event_id`, `event_name`) na janela de 48 h. Os eventos
que propagam são **3, 4, 5, 6, 9 e 11**.

> Esta distinção existe porque o aceite do bloco 5.03 no `PLANO-MESTRE` diz *"resolver uma conversa
> gera o evento com `event_id`"*, enquanto a tabela §A.6 marca o evento #10 com *"`event_id`: não"*.
> Não é contradição: o registro tem id sempre; a propagação é seletiva. Sem isto escrito, a próxima
> trilha resolveria o conflito por conta própria — e as duas pontas divergiriam em silêncio.

### 4.2 O mesmo fato, registrado duas vezes, é um registro só

O `AsyncDispatcher` entrega o evento por `EventDispatcherJob.perform_later`. Job que falha é
**retentado**, e o listener roda de novo. Sem trava, o mesmo fato viraria dois registros com dois
`event_id` — e aí a dedup por (evento, destino) da §4.3 não protegeria nada, porque seriam eventos
diferentes aos olhos do banco.

A trava é o índice único **(`account_id`, `name`, `dedup_key`)**, e a `dedup_key` é **determinística**:
ela deriva do fato (`occurred_at` do evento do dispatcher, não `Time.current`), então o retry produz
a mesma chave. `Tracking::EventRecorder.record!` devolve o registro **existente** nesse caso, sem
criar nada e sem levantar erro.

Consequência para quem chama: **se você tem uma chave natural do fato, passe `dedup_key`.** Sem ela,
a derivação usa `occurred_at.to_i` — o que resolve o retry, mas não distingue dois fatos genuínos
ocorridos no mesmo segundo para a mesma conversa.

E há um segundo caminho de retentativa, que o 4.21 encontrou e que esta seção não previa: **o
cliente**. Uma requisição HTTP do navegador pode ser reenviada por falha de rede, e o mesmo gesto do
visitante pode virar três chamadas (mandar três mensagens seguidas dispara `converted` três vezes). A
regra é a mesma e a trava é a mesma — quem tem chave natural, passa `dedup_key`. A §2.1 é o exemplo
de como fica.

### 4.3 O índice único é o que impede entrega dupla

`TrackingEvent#claim_delivery(destination)` devolve:

- a `TrackingDelivery` **recém-criada**, quando o chamador ganhou a corrida — e só então ele deve
  entregar ao destino;
- **`nil`**, quando já existia uma entrega para aquele par — outro worker já assumiu.

A garantia é do **banco**, não da aplicação: o `create` colide no índice único, o
`ActiveRecord::RecordNotUnique` é capturado e vira `nil`. Dois workers concorrentes lendo antes de
escrever produziriam duas entregas se a checagem fosse só em Ruby; com o índice, um dos dois perde.

---

## 5. A API que as outras trilhas chamam

```ruby
# Registrar um fato. Idempotente pela dedup_key.
event = Tracking::EventRecorder.record!(
  name: 'chatspx_conversation_resolved',   # obrigatório, formato validado
  account: account,                        # obrigatório
  inbox: inbox,                            # opcional
  conversation: conversation,              # opcional
  contact: contact,                        # opcional
  occurred_at: event.timestamp,            # opcional -> Time.current
  properties: { resolution: 'agent', duration_s: 428 },  # opcional -> {}
  source: :server,                         # opcional -> :server
  dedup_key: "conversation:#{id}:resolved:#{ts}"         # opcional -> derivada
)

event.event_id       # => "0b9f...-..." (UUID v4, gerado no servidor)
event.persisted?     # => true, sempre

# Reservar a entrega a um destino. nil significa "já reservada por outro".
delivery = event.claim_delivery(:meta_capi)
return if delivery.nil?      # outro worker assumiu — NÃO entregue
```

`record!` levanta `ActiveRecord::RecordInvalid` quando o nome viola o formato ou a conta falta. Não
levanta por corrida: colisão de `dedup_key` devolve o registro existente.

---

## 6. Pontos abertos, declarados

1. **`chatspx_csat_submitted` não existe.** O mapa da A9 o prevê; a tabela §A.6 não o define. O plano
   25 é explícito: *"não implementar antes de decidir"*, para não nascer evento sem contrato. Fica
   para **5.15**, e o registro **aceitaria** o nome hoje (o formato é válido) — a decisão que falta é
   de produto: parâmetros, canais e política de PII.
2. **Retenção.** A12 do `PLANO-MESTRE`: 90 dias para o log de tracking, **configurável**. O job de
   limpeza é do bloco **5.14**; este bloco entrega o índice BRIN em `occurred_at` que o torna viável,
   e nada mais — apagar dado do cliente sem o painel que o mostra seria apagar às cegas.
3. **PII em `properties`.** O registro **recusa** chave de PII crua (`em`, `ph`, `fn`, `ln`, `email`,
   `phone`, `phone_number`, `first_name`, `last_name`) em `properties`, com erro que nomeia a chave.
   A regra RC5 do plano 25 diz que nenhum evento leva PII crua ao `dataLayer` nem aos params do
   `fbq`/`gtag`, e `properties` é exatamente o que alimenta os dois. O caminho da PII é outro: 5.11
   lê do contato, normaliza e **hasheia no servidor** na hora de montar o payload de cada destino.
