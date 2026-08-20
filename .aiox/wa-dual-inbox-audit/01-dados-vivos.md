# 01 — Dados Vivos: WhatsApp Cloud API, duas inboxes no mesmo WABA

**Cliente:** Tozi Imóveis (`tozi.chatspx.app`, VM `3.82.215.109`, Account id=6 "Tozi imóveis")
**Data da coleta:** 30/07/2026, 17:45–17:58 (America/Manaus, -0400) — equivalente 21:45–21:58 UTC
**Escopo:** SOMENTE LEITURA. Nenhuma escrita no banco, nenhum POST/DELETE na Graph API, nenhum restart, nenhum clique em "Cadastrar Webhook".
**Versão em produção na VM:** `2bd596be8` (deployed_at 1785448136)

> Todos os tokens aparecem mascarados (8 primeiros + 4 últimos) ou como SHA-256. Nenhum segredo íntegro neste documento.

---

## 1. Veredito

### Os dois canais compartilham o mesmo WABA? **SIM.**

```
business_account_id inbox 91 = 905788818829319
business_account_id inbox 99 = 905788818829319
                               ^^^^^^^^^^^^^^^ IDÊNTICOS
```

A premissa da hipótese está **confirmada**: como `override_waba_callback` faz `POST /<WABA_ID>/subscribed_apps`, o `override_callback_uri` é **um único valor por WABA**. Com dois números no mesmo WABA, quem registra por último sobrescreve a URL do outro. Isso é real e foi observado ao vivo (§4).

### A consequência afirmada — "a inbox 91 PARA de receber" — **NÃO se confirmou.**

A inbox 91 **nunca parou de receber**, nem durante a janela em que 100% dos POSTs da Meta estavam sendo entregues na URL do número da inbox 99. Prova nas seções §4 e §5. A causa: o Chatwoot resolve o canal pelo **payload** (`metadata.display_phone_number` + validação de `phone_number_id`), não pela URL. Uma URL compartilhada atende os dois números.

O que o usuário vê como "a 91 parou" é o **alerta visual** "Incompatibilidade na URL do webhook" alternando entre as duas inboxes (gangorra), não perda de mensagens.

---

## 2. Tabela comparativa das duas inboxes

| Campo | Inbox 91 — "[TOZI] FIXO" | Inbox 99 — "Tozi Imoveis MKT 1" | Igual? |
|---|---|---|---|
| channel id | 6 | 7 | — |
| channel_type | `Channel::Whatsapp` | `Channel::Whatsapp` | ✅ |
| provider | `whatsapp_cloud` | `whatsapp_cloud` | ✅ |
| **business_account_id (WABA)** | **905788818829319** | **905788818829319** | 🔴 **IGUAIS** |
| phone_number | `+556635317222` | `+556632114876` | ❌ diferentes |
| phone_number_id | `915207101681633` | `1198595696676446` | ❌ diferentes |
| api_key (token) | `EAAQTdu0...ZDZD` | `EAAQTdu0...ZDZD` | 🔴 **IDÊNTICOS** |
| api_key SHA-256 | `1a3b3095803227d6…ac1f722a` | `1a3b3095803227d6…ac1f722a` | 🔴 **IDÊNTICOS** |
| webhook_verify_token | `3bd37363...2e2f` | `7902902a...03f4` | ❌ diferentes |
| verify_token SHA-256 | `d28d050430222713…ce0e248d` | `be36621384b8465d…70c6bfa3` | ❌ diferentes |
| chaves do provider_config | api_key, business_account_id, phone_number_id, webhook_verify_token | + `verification_pin` | ❌ |
| `source` / embedded_signup | ausente (`nil`) | ausente (`nil`) | ✅ (nenhum é embedded signup) |
| inbox criada em | 2026-01-15 11:35:57 | **2026-07-30 16:54:35** | — |
| channel.updated_at | 2026-07-30 17:30:10 | 2026-07-30 16:54:44 | — |
| total de mensagens | 318.379 | **0** | — |
| última msg incoming | **2026-07-30 17:34:55** (id=1579828) | nenhuma | — |
| conversas ativas 24h | 249 | 0 | — |
| contact_inboxes | 15.752 | 0 | — |
| membros (agentes) | — | 2 | — |

**Escopo do problema:** a instância tem exatamente **2 canais WhatsApp**, ambos na Account 6, ambos no **mesmo WABA `905788818829319`**. Não há terceiro canal afetado.

---

## 3. Ambiente da VM

| Item | Valor | Confere? |
|---|---|---|
| `ENV['FRONTEND_URL']` | `https://tozi.chatspx.app` | ✅ sem barra final, sem `www` |
| `GlobalConfigService.load('FRONTEND_URL')` | `https://tozi.chatspx.app` | ✅ idêntico ao ENV |
| `WHATSAPP_API_VERSION` | **`v24.0`** | ⚠️ o default no código é `v22.0`; a VM tem `v24.0` no GlobalConfig |
| `INACTIVE_WHATSAPP_NUMBERS` | `""` (vazio, no banco; ausente no `.env`) | ✅ guard inofensivo hoje |
| Rails.env / Time.zone | `production` / `America/Manaus` (-0400) | — |

URLs que o código monta (`FRONTEND_URL + /webhooks/whatsapp/ + phone_number`):

- inbox 91 → `https://tozi.chatspx.app/webhooks/whatsapp/+556635317222`
- inbox 99 → `https://tozi.chatspx.app/webhooks/whatsapp/+556632114876`

---

## 4. Estado real no lado da Meta (somente GET, v24.0)

### `GET /v24.0/905788818829319/subscribed_apps` → HTTP 200

```json
{"data":[{"whatsapp_business_api_data":{
   "link":"https://www.facebook.com/games/?app_id=1147301410628990",
   "name":"WABA TOZI","id":"1147301410628990"},
 "override_callback_uri":"https://tozi.chatspx.app/webhooks/whatsapp/+556635317222"}]}
```

**URL ativa AGORA no WABA:** `https://tozi.chatspx.app/webhooks/whatsapp/+556635317222` — ou seja, **a URL do número da inbox 91**. Há **um único app inscrito** ("WABA TOZI", id `1147301410628990`) e **um único** `override_callback_uri` para o WABA inteiro — a confirmação direta de que não existe override por número nesse endpoint.

### `webhook_configuration` de cada número

`GET /v24.0/<PHONE_NUMBER_ID>?fields=…` → HTTP 200 nos dois:

| | Inbox 91 (`915207101681633`) | Inbox 99 (`1198595696676446`) |
|---|---|---|
| display_phone_number | +55 66 3531-7222 | +55 66 3211-4876 |
| `webhook_configuration.whatsapp_business_account` | `https://tozi.chatspx.app/webhooks/whatsapp/+556635317222` | `https://tozi.chatspx.app/webhooks/whatsapp/+556635317222` |
| `webhook_configuration.application` | `https://chat.simplexsolucoes.com.br/webhooks/whatsapp/+556635317222` | `https://chat.simplexsolucoes.com.br/webhooks/whatsapp/+556635317222` |
| platform_type | CLOUD_API | CLOUD_API |
| code_verification_status | **EXPIRED** | VERIFIED |
| quality_rating | GREEN | UNKNOWN |
| throughput | STANDARD | STANDARD |

**Os dois números devolvem `webhook_configuration` IDÊNTICO** — inclusive o número novo (99) reporta a URL do número antigo (91). Não existe webhook por número configurado; ambos herdam o do WABA. Essa é a prova, vinda do próprio lado da Meta, de que o override é por WABA.

⚠️ **Achado colateral relevante:** o webhook de **nível `application`** aponta para `https://chat.simplexsolucoes.com.br/…` — **outro ambiente, não o da Tozi**. Enquanto o override do WABA existir, ele prevalece. Se o override for removido (ver risco R1), os eventos passam a cair no endpoint da instância da Simplex e **aí sim a Tozi para de receber de verdade**.

---

## 5. Evidência de tráfego: o que aconteceu hoje

### Timeline reconstruída (logs `chatwoot-web.1` + banco), horário local -0400

| Hora | Evento | Fonte |
|---|---|---|
| **16:54:33** | `POST /api/v1/accounts/6/inboxes` → **criação da inbox 99**. O callback `after_commit :setup_webhooks, on: :create` dispara e o override do WABA vira a URL do +556632114876 | log |
| 16:54–17:01 | POSTs da Meta migram para `/webhooks/whatsapp/+556632114876` | log |
| **17:01:23** | `POST /api/v1/accounts/6/inboxes/91/register_webhook` → clique em "Cadastrar Webhook" na **91**; override volta para a URL do 91 | log |
| **17:05:48** | `POST /…/inboxes/99/register_webhook` → clique na **99**; override vai para o 99 de novo | log |
| **17:06:06** | `POST /…/inboxes/91/register_webhook` → clique na **91**; override volta para o 91 | log |
| 17:30:09 | `message_templates_last_updated` da 91 (sync de templates — **não** é o webhook) | banco |
| 17:34:55 | última mensagem **incoming** da inbox 91 (operação normal) | banco |

A gangorra dos cliques está registrada nos logs: **91 → 99 → 91**, exatamente o comportamento previsto para um override único por WABA.

### Hits `POST /webhooks/whatsapp/<numero>` por hora (hoje, local)

| Hora | `+556635317222` (91) | `+556632114876` (99) |
|---|---|---|
| 07h–15h | 202, 265, 745, 590, 382, 198, 513, 378, 459 | 0 |
| **16h** | **562** | **58** |
| **17h** | **276** | **23** |

### Minuto a minuto na janela crítica

```
16:53  11 →  +556635317222
16:54   5 →  +556635317222     3 → +556632114876   ← inbox 99 criada (16:54:33)
16:55   0                     14 → +556632114876
16:56   0                      7 → +556632114876
16:57   0                     10 → +556632114876
16:58   0                     11 → +556632114876
16:59   0                     13 → +556632114876
17:00   0                     17 → +556632114876
17:01   9 →  +556635317222     3 → +556632114876   ← clique "Cadastrar Webhook" na 91 (17:01:23)
17:02+  só +556635317222
```

**De 16:55 a 17:00 (≈6 minutos) a URL do número 91 não recebeu um único POST** — 100% do tráfego do WABA foi entregue na URL do número 99. É o desvio real, ao vivo.

### O que provou que a 91 continuou funcionando

Correlação URL-de-entrega × conteúdo do payload, janela 16:52–17:12:

```
81 POSTs chegaram em  /webhooks/whatsapp/+556632114876   (URL do número 99)
… e 100% deles traziam no corpo:  "display_phone_number" => "556635317222"
                                                             ^^^^^^^^^^^^ número da inbox 91
```

Nenhum payload do número 99 chegou (número novo, sem conversas). E no banco, **durante exatamente essa janela**, a inbox 91 gravou tráfego sem interrupção:

```
31 mensagens incoming na inbox 91 entre 16:52:01 e 17:07:20
  … incluindo 16:59:59, 17:00:10, 17:00:56, 17:00:59, 17:01:06
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ dentro do período em que SÓ a URL do 99 recebia POSTs
```

Gaps de recebimento da 91 nas últimas 12h: 14 gaps > 5 min, **nenhum deles na janela do desvio** — o maior foi 27,6 min às 06:28 (madrugada, tráfego naturalmente baixo). A distribuição das últimas 24h é normal: 1.309 incoming e 1.657 outgoing na 91.

### Erros: nenhum

| Padrão procurado (logs de hoje, `chatwoot-web.1`) | Ocorrências |
|---|---|
| `Webhook setup failed` | 0 |
| `Webhook callback override failed` | 0 |
| `App subscription to WABA failed` | 0 |
| `Inactive WhatsApp channel` | 0 |
| `Rejected webhook for inactive` | 0 |
| respostas não-200 em `/webhooks/whatsapp` | 0 |

Todos os `register_webhook` retornaram sucesso. Nenhuma mensagem foi descartada.

---

## 6. Achados que contrariam ou qualificam a hipótese

1. **A perda de mensagens não acontece.** O roteamento é por payload — verificado no código que roda na VM: `Webhooks::WhatsappEventsJob#find_channel_from_whatsapp_business_payload` → `get_channel_from_wb_payload` casa `metadata.display_phone_number` com `Channel::Whatsapp.phone_number` e ainda **valida** `provider_config['phone_number_id']`. A URL só é usada como fallback (`find_channel_by_url_param`) quando `object != 'whatsapp_business_account'`.
2. **O alerta da UI é um falso positivo estrutural.** `HealthService` compara a URL esperada (sempre a do próprio número) com o `webhook_configuration` (sempre o do WABA, comum aos dois). Com dois números no mesmo WABA, **um dos dois sempre exibirá "Incompatibilidade na URL do webhook"** — e clicar em "Cadastrar Webhook" apenas transfere o alerta para o outro. Loop infinito por construção.
3. **Os tokens `api_key` das duas inboxes são idênticos** — o mesmo token do WABA foi reaproveitado nas duas. Não causa o problema, mas significa que revogar/expirar esse token derruba as duas inboxes de uma vez.
4. **`INACTIVE_WHATSAPP_NUMBERS` está vazio.** Esse é o único mecanismo pelo qual a URL compartilhada mataria os dois números (o guard rejeita pelo número **da URL**, não do payload). Hoje inofensivo — mas se alguém preencher esse config com o número de uma das inboxes, derruba **as duas**.
5. **O número da inbox 91 está com `code_verification_status = EXPIRED`** e não possui `verification_pin` em `provider_config` (a 99 possui). Como `WebhookSetupService#perform` chama `register_phone_number` quando o número não está `VERIFIED`, clicar em "Cadastrar Webhook" na inbox 91 **não é uma ação inócua**: dispara `POST /<phone_number_id>/register` na Meta. Falhas ali são engolidas (`rescue` + `Rails.logger.warn`), e de fato não houve registro bem-sucedido hoje — o número segue EXPIRED, com `quality_rating` GREEN e operação normal.

---

## 7. Riscos remanescentes (não são o sintoma relatado, mas são reais)

**R1 — Apagar qualquer uma das duas inboxes derruba as DUAS.** Confirmado no código da VM: `Channel::Whatsapp` tem `before_destroy :teardown_webhooks` → `Whatsapp::WebhookTeardownService` → `unsubscribe_waba_webhook` → `DELETE /<WABA_ID>/subscribed_apps`. O DELETE é no WABA inteiro: remove a inscrição do app e, com ela, o override compartilhado. Aí os eventos passam a seguir o webhook de nível `application`, que aponta para `chat.simplexsolucoes.com.br` — **outro ambiente**. Este é o cenário em que a Tozi realmente perde mensagens.

**R2 — Gangorra permanente na UI.** Enquanto os dois números estiverem no mesmo WABA com o código atual, o aviso de incompatibilidade continuará alternando. É cosmético, mas gera exatamente o clique que provoca o desvio de ~6 minutos observado hoje.

**R3 — Janela de desvio a cada clique.** Cada "Cadastrar Webhook" desvia o endpoint por alguns minutos. Hoje isso foi absorvido pelo roteamento por payload; se o guard `INACTIVE_WHATSAPP_NUMBERS` for populado (R4) ou se a URL alvo ficar indisponível, deixa de ser absorvido.

---

## 8. Como os dados foram coletados (reprodutibilidade)

- Acesso: `ssh ubuntu@3.82.215.109` com a chave RSA da frota (extraída de `deployment/panel/server.js`, gravada fora do repo com `chmod 600` e **removida ao fim**).
- Banco: `rails runner` como usuário `chatwoot`, `RAILS_ENV=production`, scripts em `/tmp` na VM (somente leitura).
  - ⚠️ Pegadinha encontrada: `Message` tem `default_scope { order(created_at: :asc, id: :asc) }`. Um `.order(id: :desc).first` devolve a mensagem **mais antiga**, não a mais recente. Toda consulta usou `Message.unscoped` + `reorder(...)`. A primeira rodada desta auditoria caiu nessa armadilha e reportou "última incoming = 15/01" — era a primeira.
  - `groupdate` sobrescreve `.count` em queries agrupadas e conflita com o `default_scope` (`PG::GroupingError`); resolvido com `reorder(nil)`.
- Graph API: apenas **GET**, executados de dentro da VM via HTTParty no próprio `rails runner` — assim o token nunca transitou por linha de comando (`ps`/histórico). Respostas passaram por função de redação antes de qualquer impressão.
- Logs: `journalctl -u chatwoot-web.1` (a unit roda com `RAILS_LOG_TO_STDOUT=true`; journal cobre desde 27/07/2026 18:38 UTC). Filtros por número, por minuto e por padrão de erro.
- Timezones: `journalctl --since/--until` usa **UTC**; os timestamps dentro das linhas do Rails e do banco estão em **-0400**. Todas as tabelas deste relatório foram normalizadas para o horário local (-0400).
