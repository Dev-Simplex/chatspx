# G1 — GlitchTip issue 68: `OrphanRetriageJob` / `RecordInvalid: Contact can't be blank`

**Data:** 2026-07-28 · **Autor:** worker G1 · **Escopo:** investigação e proposta (nenhum código alterado, nenhuma escrita no banco)
**Issue:** [GlitchTip #68](https://glitchtip.chatspx.app/simplex/tozi/issues/68) · projeto `tozi` · 27.074 ocorrências · 12/07 → 28/07, **ainda ativo**

---

## 1. Resumo executivo

O `Conversations::OrphanRetriageJob` roda a cada 5 minutos e tenta re-triar conversas que ficaram
sem atendente. Ele encontra, na conta **6 da Tozi PROD**, ao menos uma conversa **sem contato**
(`contact_id IS NULL`) — um registro legado criado pela própria migration de FKs de 30/03/2026, que
optou por *nulificar* a referência em vez de apagar a linha. Quando o job tenta gravar o marcador de
dedupe (`conversation.update!`), o model reprova a conversa nas suas próprias validações e a exceção
**mata o job inteiro**.

O sangramento é um ciclo fechado e auto-sustentável: **o marcador que impediria a repetição é
justamente o que não consegue ser gravado**. Logo, a mesma conversa é reprocessada a cada 5 minutos,
para sempre. Com os 5 retries do Sidekiq, isso dá **1.728 eventos/dia** — número que bate na casa
decimal com os 27.074 eventos em 15,7 dias.

**O erro não é o pior sintoma.** Dois efeitos colaterais silenciosos são mais graves:

1. A feature de vigia de órfãs está **inoperante** na conta 6: como a exceção sobe pelo `.each`,
   nenhuma conversa depois da quebrada é re-triada nem alertada.
2. `notify_admins` roda **antes** do `update!` que falha — ou seja, todos os administradores recebem
   uma notificação `conversation_orphaned` (com push/e-mail) **a cada 5 minutos, indefinidamente**,
   sobre uma conversa fantasma que sequer abre na UI.

**Recomendação:** opção **(a) guard no job** — `.where.not(contact_id: nil)` na query — que é
exatamente o que o Chatwoot upstream já faz no `Conversations::ResolutionJob` para este mesmo
problema. É uma linha, tem precedente interno, e para 100% do sangramento. Não é "esconder dado
ruim": conversa sem contato é irrecuperável por definição — não há para quem responder. A limpeza dos
dados (opção b) é um trabalho separado e **não urgente**, e a opção (c) — desligar o job — é a única
que eu descarto, porque a premissa do job continua válida.

---

## 2. O que o job faz e de onde veio

**FATO VERIFICADO.**

| Item | Valor |
|---|---|
| Arquivo | `app/jobs/conversations/orphan_retriage_job.rb` |
| Introduzido em | commit `dfc42ac834`, **2026-06-21** ("consolida WIP de staging sobre origin/homologacao") |
| Agendador | `config/schedule.yml:120-124` → `Account::OrphanConversationsWatchJob`, cron `*/5 * * * *` |
| Fan-out | `app/jobs/account/orphan_conversations_watch_job.rb:9` — 1 job por conta com `reply_assignment_gate` |
| Fila | `low` · `BATCH_LIMIT = 100` |

**Premissa do job (continua válida):** em contas com o modo "Atribuição obrigatória"
(`reply_assignment_gate`), uma conversa aberta que fica sem humano **e** sem espelho Captain por mais
de 15 minutos é uma falha de atendimento. O job re-executa as regras de triagem (`conversation_created`)
sobre ela e, se ainda assim ninguém assumir, alerta os administradores — uma vez por *episódio* de
orfandade.

O dedupe por episódio é gravado em `additional_attributes['orphan_alerted_at']`
(`orphan_retriage_job.rb:37-38`). **Guarde esse detalhe — é o centro do problema.**

---

## 3. Causa raiz

### 3.1 O ponto exato da falha

**FATO VERIFICADO** — stacktrace do evento `2026-07-28T12:00:58Z`, issue 68:

```
app/jobs/conversations/orphan_retriage_job.rb : Conversations::OrphanRetriageJob#perform
   → .each { |conversation| process_orphan(conversation, account) }          # linha 18
app/jobs/conversations/orphan_retriage_job.rb : #process_orphan
   → conversation.update!(additional_attributes:                             # linha 37
activerecord (7.1.5.2) .../validations.rb : #raise_validation_error
```

Mensagem completa: `Validation failed: Contact can't be blank, Contact must exist, Contact inbox must exist`

`app/jobs/conversations/orphan_retriage_job.rb:29-39`:

```ruby
def process_orphan(conversation, account)
  alerted_at = conversation.additional_attributes['orphan_alerted_at']
  return if alerted_at.present? && Time.zone.parse(alerted_at) >= conversation.last_activity_at

  retriage(conversation, account)          # 33 — re-executa as automation rules
  return unless still_orphan?(conversation)

  notify_admins(conversation, account)     # 36 — ★ cria notificação p/ TODOS os admins
  conversation.update!(additional_attributes:                                  # 37 — ★ EXPLODE AQUI
    conversation.additional_attributes.merge('orphan_alerted_at' => Time.current.iso8601))
end
```

### 3.2 Por que o `update!` reprova

**FATO VERIFICADO.** O `update!` dispara as validações do model `Conversation`, e a conversa carregada
já está inválida em repouso:

| Origem da mensagem | `app/models/conversation.rb` |
|---|---|
| `Contact can't be blank` | `:77` — `validates :contact_id, presence: true` |
| `Contact must exist` | `:151` — `belongs_to :contact` (required por default no Rails ≥ 5) |
| `Contact inbox must exist` | `:152` — `belongs_to :contact_inbox` |

Ou seja: **o registro já estava inválido antes do job encostar nele.** O job não cria dado ruim — ele
tropeça em dado ruim preexistente. As três mensagens juntas indicam `contact_id IS NULL` **e**
`contact_inbox_id` não-resolvível.

### 3.3 De onde vêm as conversas sem contato

**FATO VERIFICADO — a nulificação está no código, explícita e intencional.**

`db/migrate/20260330120000_add_foreign_key_constraints.rb`, cabeçalho (linha 3):

```
# Orfao em coluna nullable -> NULA o campo (preserva a linha).
```

`:29` declara `contact_id` como coluna nulável, e `:67-73` executa a sanitização:

```ruby
if column_accepts_null?(from_table, column)
  # coluna aceita NULL -> NULA a referencia orfa (preserva a linha; protege conversas/contact_inboxes)
  safety_execute(<<~SQL.squish)
    UPDATE #{from_table} SET #{column} = NULL
    WHERE #{column} IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM #{to_table} WHERE #{to_table}.id = #{from_table}.#{column})
  SQL
```

Em **30/03/2026**, ao introduzir as FKs, toda conversa cujo contato já não existia teve
`contact_id` zerado — decisão deliberada de preservar a linha em vez de apagá-la (a migration trata
`conversations` e `messages` como `PRECIOUS_TABLES`, `:44`). Esses contatos tinham sido apagados antes
disso pelo `dependent: :destroy_async` do Chatwoot upstream (`app/models/contact.rb:60`), que apaga o
contato imediatamente e as conversas *depois*, de forma assíncrona — e, sem FK, nada garantia que o
"depois" acontecesse.

O schema permite esse estado: `db/schema.rb:943` → `t.bigint "contact_id"` (**sem** `null: false`),
enquanto o model exige presença. **A discrepância schema × model é o buraco por onde o dado entra.**

> **HIPÓTESE (bem fundamentada, não verificada):** o `contact_inbox_id` dessas mesmas conversas ficou
> *dangling* — não existe FK `conversations → contact_inboxes` na lista da migration, e
> `contact_inboxes → contacts` é `ON DELETE CASCADE` (`:37`), então o `contact_inbox` sumiu junto com
> o contato e ninguém nulificou a referência. Isso explica a terceira mensagem de erro. Confirmável
> com a query Q3 do anexo.

> **FATO VERIFICADO (por eliminação):** *não* existem conversas com `contact_id` apontando para
> contato inexistente. A migration `20260609120000` roda `validate_foreign_key :conversations, :contacts`
> e o banco reporta a constraint `fk_rails_0330c79025 ... ON DELETE CASCADE` **validada**. Uma FK
> validada não admite referência quebrada — mas ignora NULL. Logo o estado dessas linhas é
> necessariamente `contact_id IS NULL`, não "dangling".

### 3.4 Por que nunca para — o ciclo fechado

**FATO VERIFICADO.** Três mecanismos que deveriam conter isso falham em cadeia:

**(i) O dedupe é a própria vítima.** O marcador `orphan_alerted_at`, que na linha 31 abortaria o
reprocessamento, é gravado pelo `update!` da linha 37 — o que explode. Nunca é gravado ⇒ nunca deduplica
⇒ reprocessa em 5 minutos ⇒ explode de novo. **Circularidade perfeita.**

**(ii) A limpeza upstream não alcança esses registros.** `Internal::RemoveOrphanConversationsJob`
(cron `0 */12 * * *`, `config/schedule.yml:117-120`) existe exatamente para apagar conversas sem
contato — mas `app/services/internal/remove_orphan_conversations_service.rb:29` filtra:

```ruby
base = base.where('conversations.last_activity_at > ?', @days.days.ago)   # @days = 1
```

Só limpa órfãs com atividade **nas últimas 24 h**. Registros legados de março/junho têm
`last_activity_at` antigo e são **permanentemente invisíveis** para a limpeza. Enquanto isso o
`OrphanRetriageJob` filtra `last_activity_at < 15.minutes.ago` (`:16`) — o conjunto **complementar**.
Os dois jobs, juntos, cobrem tudo *menos* a interseção onde vive o problema: órfãs com mais de 1 dia
são pescadas pelo retriage e nunca limpas.

**(iii) Nada trata a exceção.** `process_orphan` não tem `rescue`; `perform` também não. O `rescue`
existente (`:63-65`) protege só o loop de regras dentro de `retriage`. A exceção sobe até o Sidekiq,
que retenta — `config/sidekiq.yml:9` → `:max_retries: 5`.

### 3.5 A aritmética do sangramento

**FATO VERIFICADO** — 100 eventos consecutivos da issue 68, campo `contexts.sidekiq.retry_count`:

```
None, 4, 3, 2, 1, 0, None, 4, 3, 2, 1, 0, None, 3, 4, 2, 1, 0, None, 4, 3, 2, 1, 0, None, ...
```

Blocos limpos de **6**: 1 execução original (`retry_count: None`) + 5 retries (`0..4`). Todos os 100
eventos carregam o **mesmo argumento**: `gid://chatwoot/Account/6`.

```
288 execuções/dia (cron */5)  ×  6 eventos por execução  =  1.728 eventos/dia
27.074 eventos ÷ 1.728        =  15,67 dias
firstSeen 2026-07-12T20:01 → lastSeen 2026-07-28T12:00 = 15,66 dias      ✅ bate
```

**Conclusão quantitativa: taxa perfeitamente constante ao longo de 16 dias.** Isso só é possível se o
conjunto de registros processados for **o mesmo todo dia** — nada entra, nada sai, nada é corrigido.
Confirma a suspeita do enunciado: são **os mesmos registros, para sempre**.

Timeline de um ciclo (evento de 28/07 12:00): `enqueued_at 12:00:03` → `failed_at 12:00:07` (4 s) →
`retried_at 12:00:32` → `enqueued_at 12:00:57`. Retry a cada ~25-30 s, dentro da janela de 5 min.

### 3.6 Quantas conversas quebradas existem?

**Cada execução gera exatamente 1 evento** — a primeira exceção mata o batch. Portanto o volume de
erros **não** mede a quantidade de registros ruins: 1 conversa quebrada produz os mesmos 27 mil erros
que 50 produziriam. **Não é possível determinar o número pelo GlitchTip.** Só com SELECT na .109
(queries Q1-Q4 no anexo) — fora do meu alcance nesta task.

Isso tem uma implicação prática que vale destacar: **o volume do erro é independente do tamanho do
problema de dados**. Não use os 27 mil como estimativa de quantas linhas precisam de limpeza.

---

## 4. O que mais está quebrado (além do ruído no GlitchTip)

**FATO VERIFICADO — por leitura do fluxo, confirmado pelo stacktrace.**

### 4.1 A vigia de órfãs está inoperante na conta 6

A exceção sobe pelo `.each` da linha 18 e derruba o `perform`. Toda conversa que venha **depois** da
quebrada na ordem do batch (limite 100) nunca é re-triada nem alertada. Como não há `ORDER BY` na
query (`:14-17`), a ordem é a do heap do Postgres — estável na prática, então **sempre as mesmas
conversas ficam de fora**, silenciosamente.

Ou seja: a conta que **mais** pediu a feature (é a única com o gate ligado que quebra) é a que **não
a tem funcionando**. O erro no GlitchTip é barulhento; esta falha é muda.

### 4.2 Spam de notificação para os administradores

`notify_admins` (`:36`) roda **antes** do `update!` que explode (`:37`). Ele executa por completo:

- `app/builders/notification_builder.rb:26-34` → `user.notifications.create!` — **sem dedupe próprio**
- `app/models/notification.rb:64` → `after_create_commit :process_notification_delivery, :dispatch_create_event`
- `:229-238` → enfileira `PushNotificationJob` e `EmailNotificationJob` (se o admin estiver inscrito)

Resultado: **~1.728 vezes por dia × nº de admins**, cada administrador recebe uma notificação
`conversation_orphaned` de uma conversa fantasma. `Notification::RemoveDuplicateNotificationJob`
(`:237`) mantém só a mais recente na tabela — então o banco não infla — mas **o push e o e-mail já
foram disparados**, e o sino do dashboard pisca de novo a cada 5 minutos.

> **HIPÓTESE:** o volume real de push/e-mail depende dos `notification_settings` dos admins da conta 6
> (`notification.rb:240`) — não tenho acesso para confirmar. O registro na tabela e o evento realtime
> (`dispatch_create_event`) acontecem **incondicionalmente**.

Vale a pena perguntar ao cliente se os admins vêm reclamando disso — provavelmente vêm, e ninguém
ligou uma coisa à outra.

### 4.3 Regras de automação re-executadas a cada 5 minutos

`retriage` (`:52-68`) roda **antes** de tudo isso, reexecutando todas as regras `conversation_created`
ativas contra a conversa fantasma. Se alguma regra tiver ação de envio de mensagem ou webhook, ela é
reavaliada 288×/dia. O `rescue` da `:63` captura as falhas e **manda cada uma para o GlitchTip** —
possível fonte de ruído adicional em outras issues.

---

## 5. Diagnóstico: dado corrompido ou código que não trata caso legítimo?

**São os dois, e por isso o conserto tem duas camadas independentes.**

| Camada | Natureza | Verdade |
|---|---|---|
| **Dado** | Conversas com `contact_id IS NULL` na conta 6 da Tozi | Estado **legado e intencionalmente preservado** pela migration de 30/03 (`:67-73`). Não é corrupção acidental — foi uma escolha de projeto: preservar a linha em vez de apagá-la. |
| **Código** | O job não filtra esse estado | **Defeito real.** Todo consumidor de conversas em lote precisa desse guard, e o resto do repo já tem. |

O que decide a questão é o **precedente interno**, `app/jobs/conversations/resolution_job.rb:28-29`
(código do Chatwoot upstream, presente no repo):

```ruby
# Exclude orphan conversations where contact was deleted but conversation cleanup is pending
base_scope.where.not(contact_id: nil)
```

O `ResolutionJob` — que é o job irmão, mesma família, mesma varredura em lote — **já resolve esse
problema exatamente assim, e o comentário nomeia a causa com precisão**. O `OrphanRetriageJob`, escrito
em 21/06 na Fase C, simplesmente não herdou o guard. A conclusão é confortável: não estamos inventando
um workaround, estamos aplicando a convenção que o próprio repositório já estabeleceu.

Se o dado fosse o único problema, limpá-lo resolveria — mas a próxima conversa órfã que aparecer
(contato deletado com cleanup assíncrono pendente, que é a janela normal do `destroy_async`) recria a
falha. **O guard é a correção definitiva; a limpeza é higiene.**

---

## 6. Propostas

### (a) Guard no job — **RECOMENDADA**

Filtrar na query o estado que o model rejeita, seguindo `resolution_job.rb:29`:

```ruby
account.conversations.open
       .where(assignee_id: nil).without_captain_assignee
       .where.not(contact_id: nil)                          # ← única linha nova
       .where('conversations.last_activity_at < ?', threshold)
       .limit(BATCH_LIMIT)
```

**Complemento recomendado (mesma entrega):** um `rescue` em volta do `process_orphan` na linha 18, para
que **nenhuma** conversa individual possa derrubar o batch inteiro no futuro — o mesmo padrão que o
`retriage` já usa na `:63-65`. Isso protege contra a próxima classe de dado inesperado, que virá.

| | |
|---|---|
| **Para o sangramento?** | Sim, 100% e imediatamente. 27.074 → 0. |
| **Restaura a feature?** | Sim — as demais órfãs da conta 6 voltam a ser re-triadas e alertadas. |
| **Para o spam de notificação?** | Sim. |
| **Esforço** | ~15 min de código + 2 specs (`spec/jobs/conversations/orphan_retriage_job_spec.rb`, 229 linhas, já tem toda a estrutura de fixtures). |
| **Risco** | **Muito baixo.** Restringe um scope de leitura. O único "efeito" é deixar de processar conversas que hoje já não são processadas — elas causam exceção. |
| **Reversível?** | Trivialmente (revert de 1 commit). |
| **Deixa dado ruim para trás?** | Sim — as linhas continuam no banco, invisíveis. Ver (b). |

**Sobre a crítica honesta a esta opção:** o enunciado a descreve como "esconde o dado ruim", e isso é
justo — mas com uma ressalva importante. Uma conversa sem contato **não tem valor operacional
recuperável**: não há para quem responder, ela não abre na UI, não pode ser atribuída, não pode ser
resolvida com sentido. Re-triá-la não é um objetivo que estamos abandonando; é uma operação sem
significado. O guard não esconde um problema que queríamos resolver — ele reconhece que aquele registro
está fora do domínio do job. Ainda assim, o dado ruim **existe** e merece tratamento próprio, o que nos
leva à (b).

### (b) Limpar os dados órfãos

Duas sub-variantes, muito diferentes em risco:

**(b1) Corrigir o alcance do job de limpeza que já existe.** `RemoveOrphanConversationsService` já faz
o trabalho certo — só está míope pela janela de 1 dia (`:29`). O service aceita `days:` no construtor
(`:2`), então uma execução pontual `Internal::RemoveOrphanConversationsService.new(days: 3650).perform`
limparia o legado usando **código já existente, testado e em produção há meses**, com `destroy_all`
(callbacks + cascades corretos). Nenhuma linha de código nova.

**(b2) `DELETE` manual.** Ver anexo Q5. Não recomendo — `destroy_all` via service faz o trabalho com os
callbacks certos.

| | |
|---|---|
| **Para o sangramento?** | Sim, **mas só até a próxima órfã aparecer** — e ela vai aparecer, pela janela normal do `destroy_async`. |
| **Esforço** | ~10 min de execução + tempo de contagem/backup prévios. |
| **Risco** | **Médio-alto.** É escrita em massa em PROD de cliente, com `ON DELETE CASCADE` apagando mensagens, `applied_slas`, `reporting_events`, `csat_survey_responses`. **Irreversível sem backup.** Some com histórico que pode aparecer em relatórios. |
| **Reversível?** | **Não**, exceto por restore de backup. |

**Trade-off honesto:** (b) resolve o dado, mas *não* resolve o defeito — sem o guard, o job volta a
quebrar na primeira conversa órfã nova. E é a única opção das três que pode destruir dado do cliente.
**Não faça (b) sem (a); (a) sozinha é segura.**

### (c) Desligar o job

**Descarto.** A premissa do job **se sustenta**: a conta 6 tem `reply_assignment_gate` ligado
deliberadamente, e a vigia de órfãs é a contrapartida operacional desse modo. O problema não é a
premissa — é uma linha de filtro que faltou. Desligar trocaria um erro barulhento por uma feature
ausente, que é pior: hoje pelo menos sabemos que está quebrado.

Mencionado apenas como **mitigação emergencial**: `reply_assignment_gate = false` na conta 6 (via
settings, sem deploy) zera o sangramento em 5 minutos, se por algum motivo o deploy de (a) não puder
sair hoje. Desliga a feature junto.

---

## 7. Recomendação

**Executar (a) agora. Avaliar (b1) depois, sem pressa, como higiene.**

1. **(a) Guard + rescue defensivo.** Uma linha de filtro, um `rescue`, dois specs. Para o sangramento,
   restaura a feature, para o spam de notificação, e alinha o job à convenção que o repo já segue no
   `ResolutionJob`. Risco muito baixo, reversível.
2. **Depois, com calma: (b1)**, rodando o service existente com `days:` amplo — **precedido de SELECT
   de contagem e backup**. Isso é higiene de dados, não contenção de incidente. A prioridade cai muito
   depois de (a).
3. **Não fazer (c).**

**Fora do escopo desta task, mas anotado para o roadmap** — a raiz estrutural é a discrepância
`db/schema.rb:943` (nullable) × `conversation.rb:77` (presence). Enquanto ela existir, todo consumidor
de conversas em lote precisa se lembrar do guard. Uma migration futura de `NOT NULL` (depois da
limpeza) fecharia a classe inteira de bugs. Não urgente; registro só para não se perder.

---

## 8. Risco de não fazer nada

| Consequência | Severidade |
|---|---|
| Vigia de órfãs **inoperante** na conta 6 — conversas sem atendente passam batido, sem alerta. É exatamente a falha que o `reply_assignment_gate` foi contratado para prevenir. | **Alta** — é falha de SLA de atendimento em cliente pagante |
| Admins recebendo notificação/push de conversa fantasma a cada 5 min, indefinidamente | **Alta** — desgaste direto com o cliente; treina o time a ignorar o sino |
| 27 mil erros/16 dias enterrando os outros sinais do GlitchTip (é 2× todo o resto somado) | **Média-alta** — a observabilidade da frota fica cega |
| Carga inútil: 1.728 jobs/dia na fila `low` + regras de automação reavaliadas 288×/dia | **Baixa** — desperdício, não risco |
| Nunca para sozinho — taxa constante comprovada em 16 dias, sem tendência de queda | **é o ponto**: não há cenário de auto-resolução |

---

## Anexo — queries de diagnóstico (SELECT, para rodar na Tozi PROD .109)

> Fora do meu alcance nesta task (SSH para .109 proibido). O banco de **homologação está limpo** —
> `contact_id_null = 0` em 2.521 conversas — o que confirma que o problema é dado específico da Tozi,
> não do código em si. Nenhuma dessas queries escreve.

```sql
-- Q1: quantas conversas sem contato existem, por conta e status
SELECT account_id, status, count(*)
FROM conversations WHERE contact_id IS NULL
GROUP BY 1,2 ORDER BY 3 DESC;

-- Q2: as que o job pesca hoje (o conjunto que causa os 27 mil erros)
SELECT c.id, c.display_id, c.account_id, c.inbox_id, c.contact_inbox_id,
       c.created_at, c.last_activity_at
FROM conversations c
WHERE c.account_id = 6 AND c.status = 0 AND c.assignee_id IS NULL
  AND c.contact_id IS NULL
  AND c.last_activity_at < now() - interval '15 minutes'
ORDER BY c.id LIMIT 100;

-- Q3: confirma a HIPÓTESE do contact_inbox dangling (secção 3.3)
SELECT count(*) AS contact_inbox_dangling
FROM conversations c
LEFT JOIN contact_inboxes ci ON ci.id = c.contact_inbox_id
WHERE c.contact_id IS NULL AND c.contact_inbox_id IS NOT NULL AND ci.id IS NULL;

-- Q4: raio de alcance de uma eventual limpeza — o que o CASCADE levaria junto
SELECT (SELECT count(*) FROM messages m
          JOIN conversations c ON c.id = m.conversation_id WHERE c.contact_id IS NULL) AS mensagens,
       (SELECT count(*) FROM conversations WHERE contact_id IS NULL)                   AS conversas;

-- Q5: alcance da limpeza HOJE vs. com janela ampla (mostra por que o cleanup nunca as pega)
SELECT count(*) FILTER (WHERE last_activity_at > now() - interval '1 day')  AS pega_hoje,
       count(*) FILTER (WHERE last_activity_at <= now() - interval '1 day') AS invisivel_p_limpeza
FROM conversations WHERE contact_id IS NULL;
```

**Escrita proposta em (b1) — NÃO EXECUTADA, decisão do coordenador:**

```ruby
# Requer backup prévio. Irreversível. Roda o service JÁ EXISTENTE com janela ampla.
# Faz destroy_all (callbacks + cascades) — apaga mensagens, SLAs, reporting_events
# das conversas atingidas. Rodar Q1/Q4 ANTES para saber o alcance exato.
Internal::RemoveOrphanConversationsService.new(account: Account.find(6), days: 3650).perform
```

---

## Nota de método

Tudo marcado **FATO VERIFICADO** foi confirmado por leitura de código no repo, consulta GET ao
GlitchTip, ou SELECT no banco de homologação — as fontes estão citadas em cada ponto. As duas
**HIPÓTESES** estão sinalizadas no texto (3.3 `contact_inbox` dangling; 4.2 volume real de push/e-mail)
e ambas são confirmáveis com as queries do anexo, na .109.

Nenhum arquivo de aplicação foi alterado, nenhuma escrita foi feita em banco algum, e nenhuma chamada
não-Get foi feita ao GlitchTip.
