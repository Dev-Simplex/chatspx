# Onda 4 · Trilha WEBHOOKS — relatório de execução

- Worktree: `/home/chatwoot/chatwoot-o1-backend` · branch `o1-backend`
- Base: merge de `redesenho-integra` (`8d3859bc6a`), sem conflito
- Banco de teste dedicado: `chatwoot_test_wh`
- Blocos: **4.12 · 4.13 · 4.14** — todos fechados

| Bloco | Commit | Vermelho → verde |
|---|---|---|
| 4.12 | `bb804438f9` | **5 examples / 5 failures → 5 / 0** |
| 4.13 | `498c9bb7ee` | **14 / 12 → 14 / 0** |
| 4.14 | `987e24b1f4` | **11 / 8 → 18 / 0** (+ log de entregas **7 / 0**) |

**Portão final: 194 examples, 4 failures** — as 4 são pré-existentes e confirmadas no HEAD
limpo (2 WAHA, 2 de locale: specs que esperam mensagem em inglês numa conta que nasce
`pt_BR`).

---

## Correção ao recorte do pedido, medida

O pedido dizia "assinar os três caminhos hoje não assinados (**inbox API, agent bot**,
automação/macro/flow)". Medi caminho a caminho:

| Caminho | Estado real |
|---|---|
| inbox API (`webhook_listener.rb:146`) | **já assinado** (`secret: inbox.channel.secret`) |
| agent bot (`agent_bot_listener.rb:89`) | **já assinado** (`secret: agent_bot.secret`) |
| automation_rules, macros, flows, kanban, **webhook de instalação** | **nus** |

São **cinco** caminhos sem assinatura, e dois deles não estavam na lista (kanban e o de
instalação).

---

## 4.12 — `conversation_resolved` no webhook de conta

O evento existia só para agent bot. Webhook de conta não podia nem **se inscrever**: o nome
não estava em `ALLOWED_WEBHOOK_EVENTS` e a validação recusava com "Invalid events".

`conversation_status_changed` não resolvia: obriga o destino a inspecionar o payload para
descobrir **se** virou resolvida, e a inscrição nele traz junto todo o resto das mudanças de
status.

Assinatura e delivery id afirmados **por valor** — `secret` igual ao do webhook e presente,
`delivery_id` casando o formato uuid. `nil` passaria num teste de presença frouxo.

---

## 4.13 — Filtro por inbox e assinatura

### O filtro falhava nos DOIS sentidos

| Configuração | O que acontecia |
|---|---|
| `inbox_id` + `webhook_type: account_type` (**o que a tela cria**) | recebia eventos de **todas** as inboxes — ninguém lia o `inbox_id` |
| `webhook_type: inbox_type` | ficava fora do escopo `account_type` e **não recebia nada**, em silêncio |

Agora o que decide a entrega é ter ou não `inbox_id`, e não o `webhook_type`.

### Dois defeitos que só apareceram ao ligar o filtro

**1. O modelo aceitava webhook apontando para inbox de outra conta.** Medido: `valid? =>
true`. Inofensivo enquanto o campo era ignorado; com o filtro valendo vira armadilha
silenciosa de "não recebe nada", sem erro em lugar nenhum. Validado — e **só quando o
`inbox_id` muda**, senão o cliente ficaria trancado para fora de um registro antigo que
precisa justamente consertar.

**2. A factory tinha `inbox_id { 1 }` fixo** — um id solto, quase sempre de outra conta ou
inexistente. **Oito** specs de webhook estavam escopados por acidente a uma inbox que não
existe, e só não quebravam porque a entrega ignorava o campo.

### Assinatura

`Webhook.signing_secret_for` assina com o segredo do webhook que a conta **registrou** para
aquela URL. Sem registro não há segredo combinado com o destino — e inventar um não
assinaria nada, só daria a impressão de que assinou.

### Unicidade de URL

O índice `(account_id, url)` proibia apontar a mesma URL para duas inboxes, que passa a ser
configuração legítima. A migration **relaxa** a restrição — direção segura sobre dado
existente. `NULLS NOT DISTINCT` para não abrir brecha: sem isso, `NULL <> NULL` deixaria
passar N registros idênticos sem inbox.

---

## 4.14 — Log, replay, rotação e o segredo

### O log não herda a mentira

Você avisou, e o aviso valeu. Quem grava é o **próprio `Trigger`**, nos dois pontos em que
ele sabe o resultado — não uma camada acima.

**O caso que prova a diferença, e que virou teste:** num erro **permanente** (404) o
`Trigger` **não levanta** — chama `handle_failure` e retorna normalmente, então **o job
termina com sucesso**. Quem lesse o resultado do job gravaria "entregue" para uma entrega
que o destino recusou. O registro diz `failed`, `http_status: 404`.

### Replay

Reusa o **mesmo** `delivery_id`, e o índice **não é único** justamente por isso. Id novo no
reenvio transformaria "a mesma entrega, de novo" em "uma entrega diferente", e o destino
processaria duas vezes em vez de deduplicar. As 5 tentativas do 1.13 também são a mesma
entrega: **uma linha por `delivery_id`, atualizada**.

### O segredo, nos dois sentidos

O `index` listava o segredo em texto claro de **todos** os webhooks da conta. Agora devolve
`has_secret`; o valor só aparece na criação e na rotação, uma vez.

E a armadilha que te custou caro **foi medida e não existe aqui**: `webhook_params` nunca
permitiu `:secret`. Há teste dos dois lados — inclusive mandando `secret: nil` e
`secret: "forjado"` de propósito, e verificando que o segredo sobrevive.

### Duas decisões de engenharia que registro

**1. `WebhookPolicy` não tinha os métodos das ações novas.** Sem eles o Pundit levanta
`NotDefinedError` e a rota devolve **500**. Foi o teste que pegou.

**2. `webhook_id` entrou como sexto parâmetro de `WebhookJob#perform`, contra o
`Metrics/ParameterLists`,** com `disable` inline e justificativa escrita. Agrupar os kwargs
num objeto mudaria a assinatura de um job que tem instâncias **já enfileiradas**: no deploy,
todo webhook em fila falharia na desserialização. Parâmetro novo com default `nil` é
compatível com o que já está na fila.

> É uma exceção deliberada a um gate de estilo, e a decisão é sua se quiser outra. Escolhi
> compatibilidade de fila sobre contagem de parâmetros. No `Trigger`, que não tem fila, a
> redução foi feita de verdade: `delivery_id` + `webhook_id` viraram um `Delivery` struct.

---

## O que NÃO fiz, e por quê

- **Front do 4.14.** O `WebhookForm.vue` lê `value.secret` da **lista** para o botão de
  revelar. Com o `index` filtrando, esse botão passa a mostrar vazio. O backend expõe
  `has_secret` e a rota `rotate_secret` para a tela virar "girar segredo" em vez de
  "revelar", mas **a tela em si não foi alterada** — está fora do aceite dos três blocos e
  merece um bloco próprio, com validação em navegador.
- **Log para os caminhos sem registro `Webhook`** (automação, agent bot, inbox API). Eles
  não têm um `Webhook` a que pertencer, e inventar um registro sintético poluiria a tela do
  cliente com entregas que ele não cadastrou.
