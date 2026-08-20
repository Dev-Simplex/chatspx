# 04 — Forense: "inbox desconectada" descartando mensagens em silêncio

**Alvo:** Account 6 (Tozi), VM `3.82.215.109`, inboxes 91 (`+556635317222`) e 99 (`+556632114876`), mesmo WABA `905788818829319`
**Investigação:** 31/07/2026, 11:32–12:15 UTC — SOMENTE LEITURA (nenhum update/save/restart/POST)
**Pergunta:** o flag `reauthorization_required` esteve ativo e descartou mensagens entrantes?

## Resposta curta

**Não há evidência de que o flag tenha sido marcado, nem de uma única mensagem descartada.** O "vale" de ~20 min de ontem à noite foi queda natural de fim de expediente, provada payload a payload. A premissa de que "alguém salvou a inbox 91 às 21:30 e limpou o flag" está **incorreta** — aquele `updated_at` foi um job automático de sync de templates.

---

## Limites da evidência (ler antes das conclusões)

| Fonte | Cobertura real |
|---|---|
| `journald` | **apenas 2026-07-27 18:39 UTC → agora** (1 único boot, 4.0 GB). Não existe log dos 26 dias anteriores. |
| `log/production.log` | **não existe** — a unit roda com `RAILS_LOG_TO_STDOUT=true`; só há `development.log`/`tidewave.log` antigos |
| Redis | guarda **estado atual**, não histórico. Reiniciado hoje 06:13 UTC (ver §5) |
| `audits` (tabela) | **cobre os 30 dias** — é a evidência persistente mais longa disponível |
| `messages` (banco) | cobre os 30 dias — usado como proxy para o período sem log |

Onde o log não alcança, uso o banco e digo explicitamente que é proxy. Onde não há evidência, digo que não há.

---

## Linha do tempo — 30/07/2026 (UTC; local = UTC-4)

| Hora UTC | Evento | Fonte |
|---|---|---|
| 20:54:33 | `POST /api/v1/accounts/6/inboxes` — inbox 99 criada por **User#1** | log + `audits` |
| 20:54:35 | audit `Inbox#99 create user=User#1` | `audits` |
| 20:55:07 | audits `InboxMember#286/#287 create user=User#1` (2 agentes na inbox 99) | `audits` |
| 21:01:23 | `POST /api/v1/accounts/6/inboxes/91/register_webhook` | log |
| 21:05:48 | `POST /…/inboxes/99/register_webhook` | log |
| 21:06:06 | `POST /…/inboxes/91/register_webhook` | log |
| **21:30:10** | audit `Inbox#91 update` **user vazio** — payload é `message_templates` | `audits` |
| 21:34:55 | última incoming da 91 antes do vale (id=1579828) | banco |
| 21:35–21:49 | **vale**: nenhum payload com mensagem real (só recibos) | log |
| 21:49:39 | incoming id=1579840 — fluxo volta | banco + log |
| 21:55–21:57 | rajada de 7 incoming | banco + log |

Cadência dos audits `Inbox#91 update` (todos sem autor): 00:00:23, 03:05:05, 06:05:26, 09:10:09, 12:15:33, 15:20:17, 18:25:26, **21:30:10** — de ~3 em ~3 horas, seguindo até hoje (31/07 00:30:16, 03:30:27, 06:35:21, 09:40:37). É o job de sync de templates, não um humano salvando a inbox.

---

## 1) Quando a inbox 91 (e a 99) foi marcada como `reauthorization_required`?

**Não encontrei nenhuma marcação, em nenhum momento coberto pela evidência.**

Estado atual (31/07 11:35 UTC), varredura em **toda a instância**, não só nesses canais:

```
AUTHORIZATION_ERROR_COUNT: 0 chave(s)
REAUTHORIZATION_REQUIRED: 0 chave(s)

channel id=6 inbox=91 "[TOZI] FIXO"          reauthorization_required? = false   count = 0
channel id=7 inbox=99 "Tozi Imoveis MKT 1"   reauthorization_required? = false   count = 0
AUTHORIZATION_ERROR_THRESHOLD = 2
```

Varredura de log em **todo o período disponível**, unidades `chatwoot-web.1` + `chatwoot-worker.1`, padrões `Inactive WhatsApp channel|Webhook setup failed|whatsapp_disconnect|ChannelNotificationsMailer`:

```
27/07 18:39 → 28/07 18:00   -- No entries --
28/07 18:00 → 29/07 18:00   -- No entries --
29/07 18:00 → 30/07 18:00   -- No entries --
30/07 18:00 → 31/07 11:55   -- No entries --
```

Uma varredura anterior, focada na noite do incidente (30/07 18:00→23:59) com padrão ampliado (`+ OAuthException|reauthoriz|prompt_reauth|Phone registration failed`), também devolveu `-- No entries --` nas duas units.

**Fora da janela de log (01–27/07): sem evidência direta.** Ver §3 para o proxy.

---

## 2) Quantas mensagens entrantes foram descartadas?

**Zero — com prova direta na janela pedida.**

Método: separar, no log, os POSTs que carregam **mensagem real** (`"messages" =>` no payload) dos que carregam apenas **recibos** (`"statuses" =>`), e cruzar 1:1 com o que o banco gravou.

Janela 21:28–22:02 UTC (12.692 linhas de log):

```
linhas Enqueued Webhooks::WhatsappEventsJob : 67
  contendo "messages" =>  : 17     <- mensagens reais
  contendo "statuses" =>  : 50     <- recibos (read/delivered)
```

Timestamps dos 17 payloads com mensagem real (horário local nas linhas do Rails) × mensagens gravadas na inbox 91 (UTC no banco):

| payload no log | mensagem no banco | id |
|---|---|---|
| 17:29:52 | *(fora do recorte 21:30–22:00)* | — |
| 17:30:38 | 21:30:38 | 1579800 |
| 17:31:20 | 21:31:20 | 1579807 |
| 17:31:36 | 21:31:36 | 1579811 |
| 17:32:01 | 21:32:02 | 1579814 |
| 17:32:18 | 21:32:18 | 1579816 |
| 17:32:21 | 21:32:22 | 1579817 |
| 17:34:54 | 21:34:54 | 1579827 |
| 17:34:55 | 21:34:55 | 1579828 |
| **17:49:39** | **21:49:39** | 1579840 |
| 17:55:22 | 21:55:22 | 1579841 |
| 17:55:44 | 21:55:44 | 1579842 |
| 17:56:02 | 21:56:04 | 1579843 |
| 17:56:07 | 21:56:07 | 1579844 |
| 17:56:11 | 21:56:11 | 1579845 |
| 17:56:18 | 21:56:18 | 1579846 |
| 17:57:35 | 21:57:35 | 1579848 |

**16 de 16 dentro do recorte foram gravadas. Correspondência 1:1, nenhuma perda.**

### O vale de 21:35–21:49 explicado

Os POSTs que chegaram nesse intervalo (17:38, 17:39, 17:40, 17:43, 17:44, 17:47 local) **eram todos recibos de status** — nenhum payload com `"messages"`. A Meta não entregou mensagem nova porque não havia mensagem nova. Além disso houve um **outgoing às 21:39:07** (id=1579838): o canal estava operante, enviando.

Confirmação independente — as outras inboxes da conta, que são `Channel::Api` e **não passam pelo job do WhatsApp nem pelo flag**, caíram no mesmo intervalo:

```
inbox=61 "[Tozi] Financeiro" (Channel::Api):  21:00-21:30 -> 30 | 21:30-22:00 -> 4
inbox=62 "[TOZI] prestacao"  (Channel::Api):  21:00-21:30 -> 29 | 21:30-22:00 -> 8
inbox=91 "[TOZI] FIXO"       (Channel::Whatsapp): 21:00-21:30 -> 46 | 21:30-22:00 -> 16
```

Uma causa específica do WhatsApp não derruba canais de API. Baseline da própria inbox 91 no mesmo horário nos 14 dias anteriores: 29, 28, 81, 0, 3, 10, 14, 28, 21, 23, 2, 6, 19, 31 — os 16 de ontem estão dentro da faixa.

**Veredito: fim de expediente, não descarte.**

---

## 3) É recorrente?

**Não há evidência de recorrência nos últimos 30 dias.** Como o log não cobre o período, usei o fluxo de mensagens como proxy: um flag ativo bloqueia *todo* o incoming até alguém salvar a inbox, então deixaria um buraco visível.

22.966 mensagens incoming analisadas (30 dias). Os 15 maiores gaps são todos de madrugada (343–589 min, entre ~01h e ~11h UTC = 21h–07h local). Gaps > 45 min em horário comercial (12:00–21:00 UTC = 08:00–17:00 local):

```
72.8 min  2026-07-04 16:44Z   (sábado)
45.1 min  2026-07-04 19:07Z   (sábado)
80.4 min  2026-07-04 20:59Z   (sábado)
170.9 min 2026-07-05 16:04Z   (domingo)
150.6 min 2026-07-05 19:05Z   (domingo)
66.2 min  2026-07-11 17:42Z   (sábado)
68.3 min  2026-07-11 19:31Z   (sábado)
62.7 min  2026-07-12 12:04Z   (domingo)
53.8 min  2026-07-12 13:19Z   (domingo)
47.9 min  2026-07-12 14:15Z   (domingo)
257.2 min 2026-07-12 17:01Z   (domingo)
55.3 min  2026-07-18 20:41Z   (sábado)
54.9 min  2026-07-19 17:51Z   (domingo)
175.9 min 2026-07-26 12:09Z   (domingo)
55.2 min  2026-07-26 18:28Z   (domingo)
```

**Todos caem em sábado ou domingo. Nenhum buraco em dia útil.** Nenhum dia com zero mensagens; volume diário entre 78 (hoje, em curso) e 1.355.

Reforço: o flag só é limpo quando alguém salva a inbox, e os **únicos** dois saves humanos da inbox 91 em 30 dias foram **03/07 12:27:11** e **08/07 21:49:49** (User#1) — nenhum deles precedido de buraco de tráfego, ou seja, não foram reconexões de canal derrubado.

---

## 4) Qual foi o gatilho concreto?

**Nenhum gatilho encontrado.** Verifiquei os três candidatos:

**a) 401 ao baixar mídia** (`incoming_message_whatsapp_cloud_service.rb:17`) — sem sinal. Se o token falhasse no download, a mensagem seria criada sem anexo. Nos últimos 7 dias, das mensagens incoming sem texto:

```
total sem content: 1002
com anexo        : 1002
sem anexo        : 0      <- candidatos a mídia perdida
```

Anexos por dia (27→31/07): 240, 210, 183, 188, 9(hoje, em curso). Sem degradação.

**b) Falha no `setup_webhooks`** (`whatsapp.rb:68`) — sem sinal. Os três `register_webhook` de ontem (21:01:23, 21:05:48, 21:06:06) não produziram `[WHATSAPP] Webhook setup failed`, que é logado como `error` no rescue. Zero ocorrências em todo o log disponível.

**c) Token compartilhado expirado** — descartado. O `api_key` é o mesmo nas duas inboxes (SHA-256 idêntico, verificado na auditoria 01), então uma expiração derrubaria as duas e quebraria também o envio. Houve outgoing às 21:39:07 UTC de ontem e o fluxo segue normal hoje (78 incoming até 11:35 UTC).

**d) `code_verification_status = EXPIRED` na inbox 91** — é real, mas **não é gatilho deste flag**. Refere-se à verificação em duas etapas do número na Meta; o número opera com `quality_rating: GREEN` e tráfego normal. O efeito prático é outro: faz `WebhookSetupService#perform` tentar `register_phone_number` a cada clique em "Cadastrar Webhook" (falha engolida por `rescue` + `warn`).

---

## 5) O flag deixa rastro além do Redis?

**Praticamente não.** O estado vive em duas chaves Redis sem TTL (`REAUTHORIZATION_REQUIRED:channel_whatsapp:<id>` e `AUTHORIZATION_ERROR_COUNT:…`). Não há coluna, tabela de histórico nem audit para ele — a tabela `audits` existe (gem `audited`) mas cobre apenas atributos de models ActiveRecord.

O que **existe** como rastro indireto:

1. **Um WARN por descarte** — corrigindo a premissa do briefing, o descarte **não é totalmente silencioso**:
   ```ruby
   # app/jobs/webhooks/whatsapp_events_job.rb:14-18
   if channel_is_inactive?(channel)
     Rails.logger.warn("Inactive WhatsApp channel: #{channel&.phone_number || "unknown - #{params[:phone_number]}"}")
     return
   end
   ```
   Não há log de *erro* e a Meta recebe 200 — mas há um WARN. Ele é o detector direto, e foi justamente ele que devolveu `-- No entries --`.
2. `Rails.logger.error("[WHATSAPP] Webhook setup failed: …")` (`whatsapp.rb:66`).
3. **E-mail de desconexão**: `prompt_reauthorization!` chama `send_channel_reauthorization_email(:whatsapp_disconnect)` → `AdministratorNotifications::ChannelNotificationsMailer` → `deliver_later`. Deixa rastro no worker e na caixa dos admins. Também zero ocorrências.

Caminhos de escrita do flag (mapeados no código em produção):

| Ação | Onde |
|---|---|
| marca (direto) | `channel/whatsapp.rb:68` (rescue do `setup_webhooks`), `embedded_signup_service.rb:65` |
| marca (via contador ≥ 2) | `incoming_message_whatsapp_cloud_service.rb:17` |
| **limpa** | `inboxes_controller.rb:146` (`reauthorize_and_update_channel`) — **único caminho aplicável a estes canais** |
| limpa (não aplicável) | `whatsapp/reauthorization_service.rb:21` — só roda no fluxo *embedded signup*; ambos os canais têm `source = nil` (setup manual) |

Isso torna a conclusão mais forte: **se o flag tivesse sido marcado em 30/07, ele ainda estaria lá hoje**, porque ninguém salvou a inbox 91 desde 08/07. E o Redis não o teria perdido:

```
maxmemory 0 | maxmemory-policy noeviction | evicted_keys: 0
save 3600 1 300 100 60 10000   (persistência RDB ativa)
restart de hoje: 06:13:04 Stopping → 06:13:05 Deactivated successfully → 06:13:06 Started (shutdown limpo, salva RDB)
```

### O que falta para detectar isso proativamente

1. **Elevar o WARN a evento monitorado** — mandar `Inactive WhatsApp channel` para o GlitchTip (já usado na frota). Hoje o sinal existe mas morre no journald.
2. **Persistir o evento**: gravar timestamp + motivo quando `prompt_reauthorization!`/`reauthorized!` são chamados (coluna ou tabela própria). Hoje é impossível responder "quando ficou desconectado" depois que o estado muda.
3. **Watchdog de fluxo por inbox**: alertar se uma inbox WhatsApp ativa fica N minutos sem incoming em horário comercial. Pega qualquer causa, não só este flag — e teria respondido esta investigação em segundos.
4. **Varredura periódica** de `REAUTHORIZATION_REQUIRED:*` no Redis com alerta.
5. **Retenção de log**: 4 GB / ~4 dias é curto para forense. Aumentar `SystemMaxUse`/`MaxRetentionSec` ou exportar.

---

## Conclusão

### FATO COMPROVADO

1. Nenhuma chave de reauthorization existe hoje em **toda** a instância; ambos os canais estão `false`/`0`.
2. Zero ocorrências de `Inactive WhatsApp channel`, `Webhook setup failed`, `whatsapp_disconnect` e `ChannelNotificationsMailer` em **todo** o log disponível (27/07 18:39 → 31/07 11:55 UTC).
3. Na janela 21:28–22:02 de 30/07, os 17 payloads com mensagem real viraram 17 mensagens no banco — **zero descarte**.
4. O vale 21:35–21:49 não recebeu nenhum payload com mensagem; só recibos de status. Houve outgoing no meio dele.
5. Inboxes 61 e 62 (`Channel::Api`, fora do caminho do flag) caíram no mesmo intervalo.
6. O `updated_at` da inbox 91 às 21:30:10 foi **sync automático de templates** (audit sem autor, cadência de 3h) — **não** foi alguém salvando a inbox.
7. O último save humano da inbox 91 foi **08/07 21:49:49 UTC**; portanto o único caminho de limpeza do flag não foi acionado em 30/07.
8. Nenhum buraco de tráfego em dia útil nos últimos 30 dias; todos os gaps longos diurnos caem em sábados e domingos.
9. Download de mídia saudável: 1002 de 1002 mensagens sem texto têm anexo.
10. Redis sem eviction, com persistência e reiniciado de forma limpa — uma chave marcada teria sobrevivido.
11. O descarte **loga** um WARN (a premissa "sem log" vale só para log de *erro*).

### HIPÓTESE (não comprovada)

- **H1 — o aviso que o usuário viu foi o de webhook, não o de desconexão.** A UI tem dois avisos distintos: `RECONNECTION_REQUIRED` ("Sua caixa de entrada está desconectada. Você não receberá novas mensagens até reautorizar.", ligado ao flag) e `URL_MISMATCH` ("Incompatibilidade na URL do webhook", ligado ao `HealthService`). O segundo é o falso positivo estrutural documentado na auditoria 01: com dois números no mesmo WABA, um dos dois **sempre** o exibe. *A favor:* os três cliques em `register_webhook` às 21:01/21:05/21:06 são exatamente o comportamento de quem reage a esse banner, e não há rastro algum do flag. *Contra:* o usuário descreveu o aviso com a palavra "desconectou". Para fechar isso bastaria perguntar a ele qual das duas frases apareceu.
- **H2 — se o flag esteve ativo alguma vez, foi antes de 27/07** (fora do alcance do log) **e não deixou buraco de tráfego**. Considero improvável, porque a limpeza exige salvar a inbox e o único save é de 08/07, sem queda de fluxo antes dele.

### NÃO ENCONTRADO (dito explicitamente)

- Nenhuma evidência de 401 no download de mídia.
- Nenhuma evidência de falha em `setup_webhooks`.
- Nenhuma evidência de token expirado ou revogado.
- Nenhuma evidência de e-mail `whatsapp_disconnect` disparado.
- Nenhuma evidência de mensagem entrante perdida — em nenhuma janela analisada.
