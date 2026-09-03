# Trilha `spx-tela4-tracking` — blocos 5.06 (Tela 4) e 5.14 (auditoria e diagnóstico)

Worktree `chatwoot-spx-tela4-tracking`, branch `spx-tela4-tracking`, commit local `9c975e257b`
sobre a base `7b4ad0a371`.

---

## 0. Duas correções ao enunciado da task

**A worktree nasceu no commit errado.** Ela estava em `6a7cbcf5ba` — ancestral estrito da base,
1.556 commits atrás, sem nenhum commit próprio. O `plano/` sequer existia nela. Corrigido com
`git reset --hard 7b4ad0a371` (fast-forward puro, nada perdido).

**Os arquivos NÃO estavam ausentes.** A task dizia `AUSENTE
app/javascript/.../settings/inbox/tracking/` e `AUSENTE DiagnosticsPanel.vue`. A verificação foi
feita num caminho que não existe: a pasta real é `settings/inbox/**widget**/tracking/`, e os cinco
componentes já estavam lá desde `daaa6b139e`. O coordenador enviou a mesma correção depois.

O que de fato faltava eram os **dois buracos que a própria tela declarava**: `SecretField` preso em
`is-defined="false"` com `BLOCKED_BY_502`, e `DiagnosticsPanel` recebendo `:deliveries="[]"`.

---

## 1. O defeito que trava os dois blocos — e ele é de terceiros

**O servidor recusa o que a Tela 4 grava. Ela dá 422 em todo salvamento, hoje, em produção.**

Rodando o payload real da tela contra `WidgetTrackingSchema::SCHEMA` com `json_schemer`:

```
ERROS: 3
  /event_map/chatspx_lead : string   (schema aceita só string; a tela grava {enabled,meta,ga4})
  /test_mode              : boolean  (schema aceita só boolean; a tela grava {enabled,started_at,code})
  /lead_value             : schema=false  (additionalProperties:false recusa a chave)
```

Reproduzível: `bundle exec ruby` sobre o payload de `TrackingPage.vue` + `WidgetTrackingSchema`.

**Quem está errado é o schema, não a tela.** O plano exige as três formas:
`T-C1.5` pede ligado/desligado **mais** o nome por destino (três informações, não cabem numa
string); `T-C1.8` pede `test_event_code` **e** desligamento automático (sem `started_at` gravado,
"7 dias" é frase na tela e nada no dado); `T-C1.6` pede o valor do lead.

### Por que ninguém tinha visto

O spec vitest da tela **mocka o `dispatch`** — o payload nunca encosta no schema. Cada trilha testou
o seu lado. É a lição `reference_schema_grava_tela_formato_divergente`.

### Duas confirmações independentes, achadas depois

1. **O guarda do próprio repo já concorda.** `composables/specs/widgetTrackingContract.spec.js`, teste
   *"o rascunho da tela não carrega chave que a projeção descartaria"*: ao declarar `lead_value` e
   `kill_switch` no `DEFAULT_TRACKING`, ele falha nomeando exatamente as duas.
2. **A trilha do SDK achou o mesmo e escalou.** `app/javascript/sdk/tracking/tags.js:104-116` diz,
   textualmente: *"As duas nao podem estar certas, e a divergencia esta ESCALADA no relatorio desta
   trilha — nao arbitrada aqui."* O SDK já tolera as duas formas, então **corrigir o schema para a
   forma objeto não quebra o lado do SDK**.

### O que falta decidir

Perguntei ao coordenador se posso editar os dois arquivos Ruby (fora da minha lista). O `ask`
esgotou 25 min sem resposta, então **não editei**. O patch está pronto e testado em
`scratchpad/patch_schema_5_01.py`: troca `event_map` para objeto `{enabled,meta,ga4}`, `test_mode`
para objeto, declara `lead_value` e `kill_switch`, e soma as duas chaves ao `PUBLIC_KEYS`. Nenhuma
toca segredo — `SECRET_KEY_PATTERN` segue recusando `token`/`secret`.

---

## 2. O que entrou

### 5.14 — auditoria e diagnóstico

| Item do plano | Estado |
|---|---|
| log por evento com **nomes**, nunca valores | ✅ e é o núcleo — ver §3 |
| painel por inbox | ✅ resumo + tabela + erros agrupados |
| botão de teste | ✅ com o status HTTP **real**, não "enviado com sucesso" |
| EMQ exibido | ✅ média, com a faixa 8+ escrita na tela |
| retenção | ✅ exibida (o expurgo automático é job de backend, fora da trilha) |
| kill switch por conta | ✅ já existia, somente leitura |
| kill switch por inbox | ⚠️ **superfície declarada, sem controle** — ver §4 |

`useTrackingDiagnostics.js` decide o denominador da taxa de entrega, e essa escolha vira resposta
de suporte: conta sobre o que foi **tentado**. `pending` fica fora (senão a taxa despenca toda vez
que a fila enche e o número deixa de significar algo); `skipped` fica fora dos dois lados
(consentimento negado não é defeito); `dead` conta como falha (a DLQ não pode sumir da conta).

### 5.06 — Tela 4

| Item | Estado |
|---|---|
| 4 sub-abas, 12 eventos, valor do lead, cartão da conta, modo teste com desligamento | já existiam |
| `SecretField` nunca re-exibe + **4 últimos caracteres** | ✅ máscara de tamanho **fixo** |
| consumir a API do 5.02 por contrato `{configured, last_four}` | ✅ `useTrackingCredentials.js` |
| i18n pt-BR e en | ✅ 436 chaves, paridade exata |
| OAuth de um clique | ⚠️ lugar na tela + texto; exige cadastro externo (T-C1.7) |

O segredo **não viaja no PATCH da inbox** — vai por `PUT` próprio, disparado só quando há valor
novo. É o que impede o defeito conhecido de "salvar sem re-exibir apaga a credencial"
(`reference_read_filter_write_replace`). Coberto por teste.

---

## 3. O aceite do 5.14, e por que o teste óbvio não valeria

> "busca por `@` no painel RENDERIZADO → vazio"

Montar o painel com uma entrega sem e-mail passa nesse aceite **e não prova nada**: o `@` não
aparece porque nunca entrou. Pior, `field_names` já é uma lista de nomes por validação do modelo
(`TrackingDelivery#ensure_field_names_are_names`) — testar só ela é medir o vácuo.

**O vazamento real é `error_message`**, que é texto livre e que os destinos ecoam com o payload
ofensivo dentro. A Graph API da Meta responde `Invalid parameter: em (fulano@x.com.br) is not a
valid hash`, e isso cai inteiro na coluna. **O painel anterior renderizava esse campo cru.**

Por isso a limpeza mora em `trackingRedaction.js`, na fronteira de leitura, e é refeita **dentro do
componente** — quem montar o painel por outro caminho continua sem conseguir vazar.

### A prova do vermelho

Neutralizando **só** a tesoura e rodando `DiagnosticsPanel.spec.js`:

```
Tests  5 failed | 5 passed (10)
Received: "…Erros agrupados em (ana.souza@empresa.com.br) is not a valid hash 12×…"
```

Os 5 que caem são os que forçam a condição ruim: e-mail em `error_message`, telefone, e-mail na
**posição da chave** de `field_names` (o caso que `Object.keys(...)[0]` sozinho não pega, porque ali
a chave *é* o vazamento), erro agrupado e retorno do botão de teste. Os 5 que continuam verdes são
justamente os que passariam no vácuo.

---

## 4. O que ficou de fora, e por quê

**Kill switch por inbox — sem controle, de propósito.** A tela diz o que ele faz, diz que ainda não
está disponível e nomeia o bloco 5.01. `kill_switch` só vale se chegar ao widget, e o que chega é a
lista branca `WidgetTrackingProjection::PUBLIC_KEYS`; a chave não está lá e a gravação daria 422.
Um botão que muda de estado e não desliga nada faria o administrador acreditar que parou o rastreio
no meio de um incidente. Destrava com o patch do §1.

**Nada honra o kill switch hoje — nem o da conta.** `grep` por `kill_switch|tracking_kill_switch`
em `app/`, `enterprise/`, `lib/` e `config/` só encontra a própria tela. O da conta já era exibido
pelo `AccountScopeCard` antes desta trilha e também não tem ponto de aplicação. A aplicação é do SDK
(client-side) e dos jobs/services (server-side) — as duas fora da minha lista. **Um interruptor que
não interrompe é pior que nenhum**, então isto precisa de dono.

**As duas rotas de backend do 5.14 não existem.** Declarei o contrato em
`trackingDiagnosticsApi.js` para quem for escrever o controller:

```
GET  /api/v1/accounts/:id/inboxes/:inbox_id/tracking_deliveries?limit=N
     -> { deliveries: [...], retention_days: 90 }
POST /api/v1/accounts/:id/inboxes/:inbox_id/tracking_deliveries/test
     -> { delivery: {...} }
```

`config/routes.rb` e os controllers não são meus. Sem a rota, o painel **não diz "vazio"** — diz qual
caminho não respondeu, porque "não saiu evento" e "ninguém consegue ver" são respostas opostas.

**Expurgo automático da retenção (T-C8.2)** é job de backend. A tela exibe o prazo.

**OAuth de um clique (T-C1.7)** exige cadastro do app na Meta e no Google. Lugar reservado na tela.

**Consentimento não virou sub-aba.** O mockup `23-config-tracking.html` tem **cinco** abas
(`meta, google, eventos, consent, diag`); o plano e a task pedem **quatro**. Mantive quatro, com o
consentimento no cartão somente-leitura da conta. Se a intenção era cinco, é uma linha.

---

## 5. Como foi verificado

```
npx vitest run app/javascript/dashboard/routes/dashboard/settings/inbox/
  → Test Files 36 passed (36) · Tests 679 passed (679)

npx eslint app/javascript/.../widget/          → 0 errors (1 warning pré-existente)

paridade i18n pt_BR × en                       → 436 chaves, divergência vazia
```

Nenhum spec rspec: a entrega é front-end. O banco dedicado `chatwoot_test_tela4` foi criado e a
prova do §1 rodou com `bundle exec ruby` direto sobre o schema, sem banco.
