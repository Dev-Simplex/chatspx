# Diagnóstico — DeadSet do Sidekiq (9.999 jobs mortos) · Tozi produção

- **Ambiente:** Tozi Imóveis · conta 6 · VM AWS `3.82.215.109` (tozi.chatspx.app)
- **Data da investigação:** 29/07/2026 (dados coletados às 16:30–16:37 UTC)
- **Natureza:** investigação **read-only**. Nenhum `retry`, `kill`, `delete` ou restart foi executado. O DeadSet foi preservado integralmente como evidência.
- **Escopo:** responder o que compõe os mortos, se ainda está acontecendo, e se houve perda com consequência para o cliente.

> ⚠️ **Leia a seção 7 antes de mexer no DeadSet.** Um `retry_all` neste estado dispara mensagem real, hoje, para cliente real, referente a conversas de semanas atrás.

---

## 0. Resumo executivo (TL;DR)

1. **Não houve um incidente.** O DeadSet é **sangria contínua de ~386 jobs/dia**, produzida por **três cron jobs quebrados** que falham 100% das vezes há semanas.
2. **Uma perda real, com consequência para o negócio:** **10 leads do Meta Lead Ads** preencheram formulário na página da Tozi e **nunca entraram no CRM**. Ninguém falou com eles. **O vazamento continua aberto** — o mais recente morreu em 29/07 00:36 UTC.
3. **O eval (LLM-as-a-Judge) está morto desde 22/07.** O scheduler quebra na primeira iteração todo hora. **1.066 episódios fechados** aguardam julgamento. Sem impacto no cliente final, mas a feature está parada há 7 dias — e o watchdog que deveria gritar está *depois* da linha que estoura.
4. **O resto (≈9.700 jobs) é lixo sem consequência**: notificação de órfã que já saiu, eval duplicado que já foi gravado, e 3 contatos de junho num loop de resolução que nunca vai resolver.
5. **Efeito colateral grave do ruído:** a 386/dia o DeadSet (teto 9.999) se recicla a cada ~26 dias. **Falha de verdade fica soterrada e é descartada automaticamente** — foi exatamente o que quase aconteceu com os 10 leads.

**Ordem de ataque sugerida:** BUG 4 (leads, perde dinheiro e está ativo) → BUG 1 (1 linha, destrava 1.066 episódios) → BUG 2 → BUG 3.

---

## 1. Composição do DeadSet

`Sidekiq::DeadSet.size = 9999` (teto default — os mais antigos já foram descartados; tratar como amostra).
**Janela coberta:** 09/07/2026 → 29/07/2026 (~20 dias).
`Sidekiq::Stats`: `processed=9.941.288 · failed=97.547 · dead=9.999 · retry=5 · enqueued=0`.

| Classe do job | Erro | Volume | Janela | Cadência | Veredito |
|---|---|---:|---|---|---|
| `Conversations::OrphanRetriageJob` | `ActiveRecord::RecordInvalid: Contact can't be blank, Contact must exist, Contact inbox must exist` | **4.854** | 12/07 → hoje | 288/dia (cron `*/5 * * * *`) | **BUG ATIVO** · lixo |
| `Conversations::OrphanRetriageJob` | `NoMethodError: undefined method 'blocked?' for nil` | 1.009 | 09/07 → 12/07 | idem | Sintoma já corrigido (mesma causa) |
| `Captain::ConversationEvalJob` | `ActiveRecord::RecordInvalid: Conversation has already been taken` | 2.493 | 17/07 → 21/07 | pico encerrado | **LIXO** |
| `Contacts::ResolveLidJob` | `Waha::ApiService::LidNotResolvable` (1.212) + `Waha::ApiService::Error` (217) | 1.429 | contínuo | 72/dia (cron `15 * * * *`) | **BUG ATIVO** · lixo |
| `Captain::ConversationEvalSchedulerJob` | `NoMethodError: undefined method 'messages' for nil` | 195 | 21/07 → hoje | 24/dia (cron `7 * * * *`) | **BUG ATIVO** · perda funcional |
| `Webhooks::MetaLeadAdsJob` | `RecordInvalid` (e164) ×8 + `RuntimeError` Graph 400 ×1 + `RecordInvalid` (source_id) ×1 | 10 | 15/07 → hoje | esporádico | 🔴 **PERDA REAL** |
| `Avatar::AvatarFromFaviconJob` | `ArgumentError: wrong number of arguments (given 2, expected 3)` | 9 | esporádico | — | LIXO |

**Por fila:** `low` 8.356 · `scheduled_jobs` 1.624 · `default` 10 · `purgable` 9.
**Por conta:** 100% dos `OrphanRetriageJob` são da conta 6.

### É evento pontual ou sangria contínua?

Sangria contínua e perfeitamente regular. Os dias recentes marcam **384–386 mortos/dia**, que é exatamente a soma dos três crons quebrados:

```
288 (OrphanRetriage, a cada 5 min)  +  72 (ResolveLid, 3 LIDs × 24 h)  +  24 (EvalScheduler, 1×/h)  = 384/dia
```

O único evento com formato de "pico" é o `Captain::ConversationEvalJob` (17–21/07: 289 → 874 → 602 → 329 → 399), que **cessou** em 21/07 quando a conta migrou para eval por episódio.

---

## 2. Ainda está acontecendo?

**Sim, três dos quatro morrem hoje.** Mortos em 29/07 (dia parcial, até 16:30 UTC): 197 orphan + 48 lid + 17 scheduler + **1 lead Meta**.

- `RetrySet` = **5** (nada acumulando).
- Todas as filas em **0**, latência **0**.
- **O worker está saudável.** O que está quebrado são os jobs, não a infra.

A taxa está **estável** — nem subindo nem caindo.

---

## 3. Houve perda real?

### 3.1 🔴 SIM — 10 leads do Meta Lead Ads nunca entraram no CRM

**Única classe com consequência para o cliente.** Pessoas preencheram o formulário de anúncio da Tozi pedindo contato, o job morreu antes de criar contato/conversa, e **ninguém falou com elas**.

- Taxa de falha ≈ **1,4%** (10 perdidos contra 715 conversas `meta_lead_ads` criadas nos últimos 30 dias).
- Página: `539594042748152`.
- **Ainda vazando** — o mais recente morreu hoje, 29/07 00:36 UTC.

| leadgen_id | form_id | criado (UTC) | erro |
|---|---|---|---|
| `1228879640313685` | 2545551432555984 | 29/07 00:36 | e164 |
| `1563119535154237` | 2545551432555984 | 27/07 21:00 | e164 |
| `1348661217479007` | 2545551432555984 | 26/07 16:15 | e164 |
| `1623670439323331` | 1293052512205511 | 24/07 21:11 | e164 |
| `1603292504494302` | 2545551432555984 | 24/07 18:03 | e164 |
| `1022847793971424` | 2545551432555984 | 23/07 22:10 | e164 |
| `4413829438886679` | 2545551432555984 | 20/07 17:31 | e164 |
| `1754187419256821` | 1293052512205511 | 17/07 01:02 | e164 |
| `1023034720313121` | 903313219208924 | 15/07 00:31 | Graph API 400 (objeto não existe) |
| `2125863541294888` | 2420675818408605 | 15/07 00:28 | source_id inválido p/ inbox WhatsApp |

> **Recuperação:** pelo **Meta Lead Center** (não por retry — ver seção 7). Os leadgen_ids acima permitem localizar cada lead.

### 3.2 Orphan retriage — sem perda hoje, com risco latente

O trabalho útil **acontece**; o job estoura no fim do lote.

Evidências:
- Lote atual = 17 órfãs elegíveis. As **14 legítimas** ocupam as posições 0–13 e **todas já têm `orphan_alerted_at`**.
- As **3 envenenadas** (fevereiro/2026) caem nas posições **14, 15, 16** — a query sai ordenada por `last_activity_at` decrescente e elas são as mais antigas.
- Prova independente: **1.181 notificações `conversation_orphaned` nos últimos 7 dias**, **336 conversas** com `orphan_alerted_at`, a última gerada hoje.

⚠️ **Risco latente:** essa garantia depende da ordenação observada. Se as envenenadas subirem no lote (mudança de plano de query, ou surgirem envenenadas mais recentes), órfãs legítimas passam a ser **puladas em silêncio** — o `each` aborta o lote inteiro na primeira exceção.

### 3.3 ConversationEvalJob — sem perda

92 conversas distintas geraram 2.493 jobs mortos. **Todas as 92 já possuem registro de eval no banco.** São enfileiramentos duplicados batendo no índice único (`Conversation has already been taken`). Lixo puro.

### 3.4 ResolveLidJob — sem perda de mensagem

3 `contact_inbox` travados, todos de junho:

| contact_inbox | contact | inbox | conversa | msgs | outgoing | última msg | status |
|---|---|---|---|---:|---:|---|---|
| 57038 | 87693 | 61 (Channel::Api) | 39041 | 9 | 2 | 10/06 | resolved |
| 57173 | 87797 | 62 (Channel::Api) | 39200 | 6 | 1 | 15/06 | resolved |
| 58206 | 88705 | 61 (Channel::Api) | — | 0 | 0 | — | sem conversa |

Os dois primeiros **foram atendidos normalmente** (têm resposta outgoing e estão resolvidos). Nenhuma mensagem deixou de sair. Perda = **3 cadastros sem telefone**, com `identifier` sujo (`<lid>@lid`). Qualidade de dado, não atendimento.

### 3.5 Eval scheduler — perda funcional interna (não do cliente)

- Último `avaliado_em` = **22/07/2026 11:23**. **Zero evals criados nos últimos 7 dias.**
- **1.066 episódios fechados aguardando julgamento** (represados).
- Nenhuma mensagem deixou de ser enviada; nenhum cliente foi afetado. É a feature de qualidade que está parada.

---

## 4. Causas-raiz

> **Atenção às referências de arquivo:** os trechos marcados **[deployado]** foram lidos direto da VM de produção, que **diverge do checkout local** (o scheduler em produção é bem mais novo — tem episódios e watchdog). Conferir contra a branch efetivamente em produção antes de aplicar.

### BUG 1 — Eval scheduler morre na primeira iteração 🔴 (mais barato de corrigir)

**[deployado]** `enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:99`

```ruby
Captain::ConversationEpisode.open_ones
                            .for_account(account.id)
                            .where('last_message_at < ?', gap_hours.hours.ago)
                            .order(last_message_at: :asc)
                            .limit(MAX_STALE_RESEGMENTS)
                            .includes(:conversation)
                            .each { |ep| Captain::EpisodeSegmenterService.new(conversation: ep.conversation).perform }
                            #                                                          ^^^^^^^^^^^^^^^^^^ pode ser nil
```

**[deployado]** `enterprise/lib/captain/episode_segmenter_service.rb:40` → `@rows ||= conversation.messages` → `NoMethodError`.

**Dado de produção:**
- 3 episódios **abertos e vencidos** apontam para conversas deletadas: episódios `1184, 1490, 8871` → conversas `22949, 40002, 32537`.
- **29 episódios órfãos** no total (qualquer status).
- **O órfão está na posição 0 do lote** → estoura na primeira iteração.

**Agravante — a ordem de chamada:**

```ruby
def enqueue_episodes_for_account(account)   # linha 51
  ...
  segment_touched_conversations(account, inbox_ids)  # 55
  resegment_stale_open_episodes(account)             # 56  ← estoura aqui
  enqueue_closed_episodes(account)                   # 57  ← nunca roda
  flow_watchdog(account)                             # 58  ← nunca roda
end
```

Ou seja: os 1.066 episódios fechados nunca são enfileirados, **e o dead man's switch criado justamente para gritar "funil seco" está depois da linha que quebra.** A pane é silenciosa por construção.

**Fix aplicado:** `.joins(:conversation)` (INNER JOIN descarta episódio órfão no próprio SQL) em `resegment_stale_open_episodes` **e** em `enqueue_closed_episodes` — o segundo porque, ao destravar o cron, ele passaria a enfileirar episódios fechados que também podem estar órfãos, trocando um job morto por outro.

Verificado em produção (read-only): lote de 100 episódios **sem** o join contém 2 órfãos, o primeiro na **posição 0**; **com** o join, zero. Os 1.051 episódios fechados não julgados **não** contêm órfãos — destravar não gera job morto novo.

**Sugestão não aplicada (fica de recomendação):** mover `flow_watchdog` para um `ensure`, ou dar rescue próprio a cada etapa — um watchdog que só roda no caminho feliz não é watchdog. Não fiz porque muda o contrato de erro do job; decisão do time.

**Higiene de dados:** os 29 episódios órfãos podem ficar — o guard-rail resolve o sintoma sem deletar nada.

---

### BUG 2 — Orphan retriage estoura em conversa sem contato

**[deployado, idêntico ao checkout]** `app/jobs/conversations/orphan_retriage_job.rb:37`

```ruby
def process_orphan(conversation, account)          # linha 29
  ...
  notify_admins(conversation, account)             # 36
  conversation.update!(additional_attributes:      # 37  ← RecordInvalid
    conversation.additional_attributes.merge('orphan_alerted_at' => Time.current.iso8601))
end
```

`update!` revalida o registro inteiro; conversa com `contact_id` NULL falha em `Contact can't be blank, Contact must exist, Contact inbox must exist`. Como o `each` de `perform` (linha 18) não tem rescue, **o lote inteiro aborta**.

**Histórico do sintoma:** até 12/07 estourava antes, em `app/builders/notification_builder.rb:29` (`primary_actor.contact.blocked?`). O deploy que trocou por `primary_actor.contact&.blocked?` **mudou o sintoma, não a causa** — daí a virada de `NoMethodError` para `RecordInvalid` exatamente em 12/07.

**As 3 conversas envenenadas** (todas conta 6, `status=open`, **zero mensagens incoming**, `contact_id` NULL e `contact_inbox_id` apontando para registro inexistente):

| conversation | display_id | inbox | criada | last_activity | msgs | contact_inbox_id (morto) |
|---|---|---|---|---|---:|---|
| 21454 | 4778 | 61 | 25/02 | 26/02 | 1.751 | 39041 |
| 20960 | 4516 | 91 | 21/02 | 23/02 | 1 | 38535 |
| 20844 | 4441 | 61 | 20/02 | 20/02 | 28 | 14102 |

Provável origem: as consolidações de fevereiro/junho feitas com `delete`/`update_columns` (sem callbacks), que removeram contatos e `contact_inboxes` sem levar as conversas junto.

**Por que a faxina automática nunca as pegou —** **[deployado]** `Internal::RemoveOrphanConversationsService#build_orphan_conversations_query`:

```ruby
base = base.where('conversations.last_activity_at > ?', @days.days.ago)   # @days = 1
```

O job roda de 12 em 12 horas mas **só enxerga órfã com atividade nas últimas 24 h**. Órfã que envelheceu fica invisível para sempre. Estas são de fevereiro.

**Fix aplicado:**
1. `.joins(:contact)` no scope de `perform` — exclui no SQL a conversa cujo contato não existe. É órfã de **dado**, não de atribuição: não há quem notificar nem o que triar.
2. `rescue StandardError` por conversa dentro do `each`, com `ChatwootExceptionTracker` (mesmo padrão já usado no loop de regras deste arquivo). **Uma** conversa problemática nunca mais aborta o lote — que é a lição sistêmica dos 288 jobs/dia.

Verificado em produção (read-only): lote cai de **17 → 14** conversas, exatamente as 3 envenenadas excluídas.

**Não aplicado (decisão do Paulo):** dar a `RemoveOrphanConversationsService` uma passada sem janela de tempo. ⚠️ Ele usa `destroy_all` — é write em produção, e as 3 conversas guardam mensagens (uma delas 1.751). O guard-rail já resolve o job; deletar é outra conversa.

---

### BUG 3 — ResolveLid em loop eterno (72 mortos/dia)

`app/jobs/contacts/resolve_lid_job.rb` (checkout local, linha ~28) — quando o LID não resolve:

```ruby
raise Waha::ApiService::Error, "LID not yet resolvable: #{lid}"
```

Com `retry_on ... attempts: 7`, cada job morre após ~18 min de backoff. E `config/schedule.yml:103-105`:

```yaml
waha_resolve_lid_sweep_job:
  cron: '15 * * * *'
  class: 'Contacts::ResolveLidSweepJob'
```

o sweep **re-enfileira os mesmos 3 contatos toda hora, para sempre**. Não existe nenhum mecanismo de desistência (nenhum `lid_resolution_failed_at` / contador de tentativas persistido).

Os 3 LIDs (`7675274387630@lid`, `277098505723986@lid`, `155800005799987@lid`) são de junho — o WAHA já não tem o mapeamento. **Nunca vão resolver.**

**Fix aplicado:** `ABANDON_AFTER = 30.days` no `ResolveLidSweepJob` — só reenfileira `contact_inbox` criado nos últimos 30 dias. Sem schema novo, sem estado persistido. O log passa a informar quantos foram abandonados (o arquivo já tinha a política de "nunca truncar em silêncio").

Escolhi janela por idade em vez de contador de tentativas porque o sweep existe para o caso do WAHA **reaprender** o mapeamento, e isso acontece em dias — não em meses.

Verificado em produção (read-only): dos 3 presos, **2 são abandonados de imediato** (48 mortos/dia a menos) e 1 ainda é recente; ele sai sozinho da varredura ao completar 30 dias.

---

### BUG 4 — Meta Lead Ads perde o lead quando o telefone não normaliza 🔴 (custa dinheiro)

**[deployado]** `app/services/meta/lead_ads/create_conversation_service.rb:258-269`

```ruby
def normalize_phone(phone)
  digits = phone.to_s.gsub(/\D/, '')
  return nil if digits.blank?

  ddd = default_ddd
  digits = "#{ddd}#{digits}" if ddd.present? && digits.length.between?(8, 9)
  digits = "55#{digits}"     if digits.length.between?(10, 11)
  formatted = "+#{digits}"
  Contacts::BrazilPhoneNormalizer.normalize(formatted) || formatted   # linha 269  ← BUG
end
```

**Ninguém valida o telefone antes de entregá-lo ao `Contact`.**

Ponto crítico, verificado no código: **`Contacts::BrazilPhoneNormalizer` NÃO é um validador.** Ele só acrescenta o 9º dígito e, quando não reconhece o padrão, **devolve a entrada intacta** (`return @phone_number unless brazilian_number?`). Ou seja, `"+066999636866"` entra e sai igual — o `|| formatted` nem chega a ser exercido nesses casos.

Do outro lado, `Contact` valida `format: /\+[1-9]\d{1,14}\z/` (`app/models/contact.rb:54-57`) e **não se auto-corrige**: o método que sanearia (`discard_invalid_attrs` → `phone_number_format`, linha 189) **não é callback** — é método público que só roda se alguém chamar, e o `ContactInboxWithContactBuilder` não chama.

Resultado: lixo digitado no formulário chega cru ao `Contact` → `RecordInvalid` → job morre → **o lead evapora**.

**Telefones reais dos 10 leads perdidos** (obtidos via GET read-only no Graph):

| leadgen_id | telefone digitado | e-mail | diagnóstico |
|---|---|---|---|
| 1603292504494302 | `066999636866` | leandro_hsilva@hotmail.com | 🟢 **trunk-0 — recuperável** |
| 1022847793971424 | `066996693068` | reginazilch93@gmail.com | 🟢 **trunk-0 — recuperável** |
| 4413829438886679 | `066996563471` | pablo.b.3471@gmail.com | 🟢 **trunk-0 — recuperável** |
| 1228879640313685 | `"2 mil de entrada"` | adryannaassuncao4@gmail.com.br | lead respondeu a pergunta errada |
| 1563119535154237 | `"5 mil"` | oliveiraysa427@gmail.com | idem |
| 1348661217479007 | `"4"` | thyjk@gmail.com | idem |
| 1623670439323331 | `"6........"` | jucaquiteria@gmail.com | idem |
| 1754187419256821 | 44 dígitos concatenados | thaizabrito.adv@gmail.com | provável `+5566999204990` no início |
| 2125863541294888 | (vazio) | matheusgazziero@hotmail.com | form sem telefone |
| 1023034720313121 | — | — | Graph 400: objeto não existe |

> **Achado de produto, não de código:** 4 dos 10 responderam **o valor da entrada** no campo de telefone. Isso é problema do **formulário no Meta** (campo mal rotulado ou pergunta anterior "grudando"). Vale revisar os forms `2545551432555984` e `1293052512205511` — nenhum código conserta isso.

**Fix aplicado** (ver seção 9):
1. **Tira o zero de tronco** (`digits.sub(/\A0+/, '')`) — recupera 3 dos 10.
2. **Valida e164 no fim**; o que não passar vira `nil` e cai no caminho já existente de "lead sem telefone", **em vez de matar o job**.
3. O log de "sem telefone" passa a carregar **telefone cru + e-mail**, porque é o único rastro de um lead pago que não virou conversa.

**Ainda em aberto (decisão do Paulo, fora do escopo do bugfix):** a inbox alvo é a **91 `[TOZI] FIXO` (Cloud API)**, e nela lead sem telefone faz `return nil` (linha 33-36) — ou seja, continua **não** entrando no CRM, só que agora com log em vez de job morto. Se quiser que esses leads (que **têm e-mail válido**) entrem para follow-up manual, é preciso um caminho de contato sem `source_id` de WhatsApp. Recomendo tratar como item separado.

---

## 5. Veredito consolidado por classe

| Classe | Volume | Veredito | Justificativa |
|---|---:|---|---|
| `Webhooks::MetaLeadAdsJob` | 10 | 🔴 **PERDA + BUG ATIVO** | 10 leads reais nunca entraram; ainda vazando |
| `Captain::ConversationEvalSchedulerJob` | 195 | 🟠 **BUG ATIVO** (perda funcional interna) | Eval parado desde 22/07; 1.066 episódios represados |
| `Conversations::OrphanRetriageJob` | 5.863 | 🟡 **BUG ATIVO** (lixo, risco latente) | Notificações saem normalmente; estoura no fim do lote |
| `Contacts::ResolveLidJob` | 1.429 | 🟡 **BUG ATIVO** (lixo) | Loop infinito em 3 contatos; nenhuma mensagem perdida |
| `Captain::ConversationEvalJob` | 2.493 | ⚪ **LIXO** | Duplicatas; as 92 conversas já têm eval gravado |
| `Avatar::AvatarFromFaviconJob` | 9 | ⚪ **LIXO** | Cosmético (avatar por favicon) |

---

## 6. Lista concreta de afetados

**Perda de negócio — 10 leads:** ver tabela da seção 3.1.

**Higiene de dados (sem impacto de atendimento):**
- Conversas envenenadas: **21454, 20960, 20844** (display 4778, 4516, 4441).
- Episódios órfãos abertos: **1184, 1490, 8871** (+ 29 órfãos no total).
- Contatos travados em LID: **87693, 87797, 88705** (contact_inbox 57038, 57173, 58206).

---

## 7. ⛔ Recomendação de descarte — leia antes de tocar no DeadSet

**Nada no DeadSet deve ser reprocessado.** Pode ser limpo **depois** de corrigir os bugs — senão enche de novo em ~26 dias.

### Reprocessamentos que disparariam mensagem real hoje

| Classe | Risco ao reprocessar |
|---|---|
| `Conversations::OrphanRetriageJob` (4.854) | 🔴 **O mais perigoso.** Re-executa `AutomationRules::ActionService` das regras de `conversation_created` → atribuições em massa e potencialmente `send_message` em conversas antigas. Um `retry_all` aqui é uma tempestade em cima de conversa real. |
| `Webhooks::MetaLeadAdsJob` (10) | 🔴 Dispara a 1ª mensagem ao lead. Além disso os leadgen_ids de 15/07 provavelmente já expiraram no Graph, e abordar alguém 14 dias depois queima o lead. **Recuperar pelo Meta Lead Center, na mão.** |
| `Captain::ConversationEvalJob` / `SchedulerJob` | ⚪ Sem risco (LLM-judge interno, idempotente) — mas inútil: já avaliados. |
| `Contacts::ResolveLidJob` | ⚪ Sem risco — mas morreria de novo em minutos. |
| `Avatar::AvatarFromFaviconJob` | ⚪ Inócuo. |

### O que fazer à mão

1. **Os 10 leads** — baixar pelo Meta Lead Center (página `539594042748152`, forms `2545551432555984`, `1293052512205511`, `903313219208924`, `2420675818408605`) e repassar aos corretores. **Única recuperação de receita aqui.**
2. Corrigir BUG 4 — o vazamento está aberto.
3. Corrigir BUG 1 (1 linha) — destrava os 1.066 episódios.
4. Corrigir BUG 2 e BUG 3.
5. **Só então** limpar o DeadSet.
6. Considerar um alerta simples de "DeadSet crescendo acima de X/dia" — hoje 386 mortos/dia é o normal, e é isso que faz falha de verdade passar despercebida.

> Sobre as 3 conversas de fevereiro: **prefiro a guarda no código a deletá-las.** Deletar é write em produção e é decisão do Paulo, não do fix.

---

## 8. Como reproduzir (read-only)

Acesso via helper (imprime banner CLIENTE·AMBIENTE·HOST):

```bash
scripts/ops/tozi-prod.sh put <script_local.rb> /tmp/script.rb
scripts/ops/tozi-prod.sh run "bundle exec rails runner /tmp/script.rb"
```

> ⚠️ Gotcha do helper: rodar o `rails runner` **sozinho**. Encadear com `;` faz o `RAILS_ENV=production` valer só no primeiro comando.

Esqueleto da agregação (não imprimir payload inteiro — contém PII):

```ruby
require 'sidekiq/api'

def real_class(item)
  w = item['wrapped']
  return w if w.present?
  k = item['class'].to_s
  return item['args'][0]['job_class'].to_s if k.include?('JobWrapper') && item['args'][0].is_a?(Hash)
  k
end

by_class = Hash.new(0)
Sidekiq::DeadSet.new.each do |j|
  it = j.item
  by_class["#{real_class(it)} || #{it['error_class']} || #{it['error_message'].to_s[0, 90]}"] += 1
end
by_class.sort_by { |_, v| -v }.each { |k, v| puts format('%-6d %s', v, k) }
```

Consultas de apoio usadas:

```ruby
# episódios órfãos (BUG 1)
Captain::ConversationEpisode.for_account(6)
  .where('NOT EXISTS (SELECT 1 FROM conversations WHERE conversations.id = captain_conversation_episodes.conversation_id)').count

# lote real do orphan retriage (BUG 2)
Account.find(6).conversations.open.where(assignee_id: nil).without_captain_assignee
  .where('conversations.last_activity_at < ?', 15.minutes.ago).limit(100)
  .each_with_index { |c, i| puts "#{i} #{c.id} #{c.contact.nil? ? 'POISON' : 'ok'}" }

# saúde do eval (BUG 1)
Captain::ConversationEval.maximum(:avaliado_em)
Captain::ConversationEpisode.closed.for_account(6).where('ended_at >= ?', 7.days.ago).count
```

---

---

## 9. Correções aplicadas (29/07/2026)

Branch **`producao`** — os bugs estão vivos lá e é dela que sai o deploy. Os 5 arquivos-alvo são idênticos em `producao` e `homologacao` (exceto o `flow_watchdog`, que só `producao` tem e que os patches não tocam), então os commits aplicam limpo nas duas.

| # | Commit | Arquivo | Mudança |
|---|---|---|---|
| 1 | `fix(eval)` | `enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb` | `joins(:conversation)` em `resegment_stale_open_episodes` e `enqueue_closed_episodes` |
| 2 | `fix(orfas)` | `app/jobs/conversations/orphan_retriage_job.rb` | `joins(:contact)` no scope + rescue por conversa |
| 3 | `fix(waha)` | `app/jobs/contacts/resolve_lid_sweep_job.rb` | `ABANDON_AFTER = 30.days` + log de abandonados |
| 4 | `fix(lead-ads)` | `app/services/meta/lead_ads/create_conversation_service.rb` | trunk-0 + validação e164 + log com telefone cru e e-mail |

### Verificação executada

Tudo **read-only contra produção**; nada foi deployado, nenhum job reprocessado, nenhum serviço reiniciado.

- **Sintaxe:** `ruby -c` nos 4 arquivos → `Syntax OK` (rodado na VM, arquivos em `/tmp`, fora da árvore da aplicação).
- **Lint:** `rubocop -c .rubocop.yml` → **22 offenses antes, 22 depois**. Zero introduzidas; todas pré-existentes, em métodos não tocados.
- **FIX 1:** lote de 100 episódios — sem join: 2 órfãos, primeiro na posição 0. Com join: 0. Os 1.051 fechados não julgados não contêm órfãos.
- **FIX 2:** lote de órfãs 17 → 14 (as 3 envenenadas fora).
- **FIX 3:** 3 presos → 2 abandonados na hora, 1 ainda recuperável.
- **FIX 4:** rodado contra **os 10 leads reais** buscados no Graph, comparando `normalize_phone` antigo vs novo:
  - **3 leads RECUPERADOS** (viram conversa de verdade);
  - 6 tratados sem matar o job;
  - 1 irrecuperável (não existe mais no Graph);
  - **não-regressão:** 6 formatos que já funcionavam (`66999636866`, `+5566996350491`, `996926393`, `5566999999999`, `6632110000`, `(66) 99963-6866`) produzem resultado **idêntico** ao de antes.

### O que NÃO foi feito (de propósito)

- **Nada foi deployado.** Os commits estão locais, sem `push`.
- **DeadSet intacto** — segue como evidência; descartar é decisão do Paulo.
- **Nenhum job reprocessado** — ver seção 7.
- **Testes automatizados não escritos** (o AGENTS.md pede não escrever specs sem pedido explícito). Existem specs para 3 destes jobs em `spec/jobs/` — vale rodá-los antes do deploy.

### Próximos passos

1. Rodar os specs afetados: `bundle exec rspec spec/jobs/conversations/orphan_retriage_job_spec.rb spec/jobs/contacts/resolve_lid_sweep_job_spec.rb`.
2. Deploy pelo caminho governado (Almirante: `dry_run` → `propose_deploy_vm` → aprovação humana).
3. **Recuperar os 3 leads trunk-0 na mão** — o fix só vale para leads futuros; esses 3 já morreram. Telefones na tabela do BUG 4.
4. Propagar para `homologacao` (cherry-pick dos 4 commits).
5. Revisar os formulários do Meta (`2545551432555984`, `1293052512205511`) — 4 dos 10 leads responderam o valor da entrada no campo telefone.
6. Só depois de tudo no ar: limpar o DeadSet.

---

*Investigação read-only executada em 29/07/2026. DeadSet preservado. Correções aplicadas na branch `producao`, sem deploy.*
