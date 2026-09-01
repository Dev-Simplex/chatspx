# G2 — GlitchTip: o pelotão do meio (4 erros de código)

**Data:** 2026-07-28 · **Analista:** worker G2 · **Escopo:** somente investigação. Nenhuma linha de `app/`, `lib/`, `enterprise/`, `config/` ou `db/` foi alterada. Nenhum commit, deploy ou restart.
**Fontes:** GlitchTip (GET), código em `/home/chatwoot/chatwoot` (branch `homologacao`), `git log`/`git show`, SELECTs no Postgres de homologação.

---

## Sumário executivo

Os quatro erros foram investigados até a causa raiz. **Três são bugs reais de código; um é regressão nossa comprovada; um não tem impacto nenhum em produção hoje.** Nenhum é "job antigo na fila com assinatura velha" — a hipótese do enunciado para o issue 86 foi **descartada com evidência** (é callsite desatualizado, não payload velho).

| # | Erro | Onde | Impacto real | Custo |
|---|------|------|--------------|-------|
| 128 | `undefined method 'messages' for nil` | Tozi PROD | **Alto** — o eval da conta para de rodar por inteiro | Baixo |
| 65 | `undefined method 'truncate' for nil` | Tozi PROD | **Médio-alto** — HTTP 500 no botão "apagar mensagem"; o agente não consegue apagar | **Mínimo** (1 linha × 2) |
| 86 | `wrong number of arguments (given 2, expected 3)` | Tozi PROD | **Baixo** — favicon de empresa nunca é baixado (cosmético) | Baixo |
| 160 | `undefined method 'dig' for an instance of String` | Homologação (WIP local) | **Zero em produção** — código não commitado; já corrigido no working tree | Zero (fechar 1 lacuna) |

**Por onde começar:** #65 (5 minutos, risco zero, dor visível) → #128 (maior dano funcional) → #86 → #160 (só não deployar sem fechar a lacuna). Ranqueamento detalhado no final.

---

## Issue 128 — `NoMethodError: undefined method 'messages' for nil`

**996 eventos · projeto `tozi` (PROD .109) · 2026-07-21 14:07 → 2026-07-28 11:16 · release `2bd596be84`**

### Stack — frames do nosso código

```
enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:20  #perform
enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:24  block in #perform
enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:56  #enqueue_episodes_for_account
enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:99  #resegment_stale_open_episodes
enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:99  block in #resegment_stale_open_episodes
enterprise/lib/captain/episode_segmenter_service.rb:22             #perform
enterprise/lib/captain/episode_segmenter_service.rb:62             #build_segments
enterprise/lib/captain/episode_segmenter_service.rb:40             #rows   <-- estoura aqui
```

Culprit: `Captain::EpisodeSegmenterService#rows`, snippet do próprio GlitchTip:

```ruby
@rows ||= conversation.messages
                      ^^^^^^^^^
```

> Nota: a linha 99 é do release da Tozi (`2bd596be84`); na `homologacao` de hoje o mesmo trecho está em `enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:81`. **Verifiquei com `git show 2bd596be84:` que o código é idêntico** — só mudou a numeração. O bug existe igual nos dois.

### Causa raiz — FATO VERIFICADO

`enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb:75-81`:

```ruby
Captain::ConversationEpisode.open_ones
                            .for_account(account.id)
                            .where('last_message_at < ?', gap_hours.hours.ago)
                            .order(last_message_at: :asc)
                            .limit(MAX_STALE_RESEGMENTS)
                            .includes(:conversation)
                            .each { |ep| Captain::EpisodeSegmenterService.new(conversation: ep.conversation).perform }
```

`ep.conversation` é **nil porque o episódio ficou órfão**: a conversa foi apagada e o registro em `captain_conversation_episodes` sobreviveu. Três evidências independentes que provam que nada impede isso:

1. **Não existe foreign key no banco.** `db/schema.rb:439-457` cria `captain_conversation_episodes` com `conversation_id bigint NOT NULL` e quatro índices — e `grep add_foreign_key db/schema.rb` não devolve nenhuma FK para essa tabela (as únicas FKs `captain_*` são de `captain_assistant_logs`). Confirmado também na migration de origem `db/migrate/20260717120000_create_captain_conversation_episodes.rb`, que não chama `add_foreign_key`.
2. **Não existe `dependent:` no lado da Conversation.** `grep -rn "ConversationEpisode" app/ enterprise/` não encontra nenhum `has_many :captain_conversation_episodes` em `Conversation`. O modelo `enterprise/app/models/captain/conversation_episode.rb:11` declara só o lado filho (`belongs_to :conversation`), que valida na escrita e não protege contra deleção posterior.
3. **Conversas são deletadas por vários caminhos, todos assíncronos:**
   - `app/controllers/api/v1/accounts/conversations_controller.rb:157-160` → `DeleteObjectJob.perform_later('Conversation', id, ...)`
   - `app/models/contact.rb:60` → `has_many :conversations, dependent: :destroy_async` (agente apaga um contato duplicado → todas as conversas dele somem)
   - `app/models/inbox.rb:71` e `app/models/account.rb:125` → idem

Ou seja: apagar **um contato** na Tozi basta para deixar episódios órfãos permanentes.

**Por que 996 eventos.** O cron é horário (`config/schedule.yml:141` → `cron: '7 * * * *'`). `app/jobs/application_job.rb` só declara `discard_on ActiveJob::DeserializationError` — **não há `retry_on` nem `discard_on` para `NoMethodError`**, então vale o retry padrão do Sidekiq (25 tentativas com backoff), e cada retry reexplode no mesmo episódio órfão. 996 eventos / 7 dias ≈ 142/dia ≈ 6/h — consistente com 1 execução horária + a cauda de retries. *(Cálculo consistente com a evidência; a contagem exata de retries é HIPÓTESE, não medi a fila da Tozi.)*

### Regressão? — sempre existiu

Não é regressão de um commit específico: o defeito nasceu junto com a feature. A migration `20260717120000` (17/07) já criou a tabela sem FK, e `firstSeen` é 21/07 — quatro dias depois, o tempo de alguém apagar a primeira conversa/contato que já tinha episódio. É **um buraco de design da Eval 2.0 F1**, não algo que quebrou depois.

### Impacto real para o usuário final

**Alto, e silencioso.** A exceção não é resgatada em lugar nenhum: sobe de `#rows` até `#perform` e mata o job inteiro. Consequências, na ordem em que acontecem dentro de `#enqueue_episodes_for_account` (linhas 55-57):

- `segment_touched_conversations` (55) roda e completa;
- `resegment_stale_open_episodes` (56) **explode**;
- `enqueue_closed_episodes` (57) **nunca executa** → nenhum `Captain::EpisodeEvalJob` é enfileirado → **os atendimentos daquela conta deixam de ser avaliados**;
- pior: o `raise` sobe até o `Account.find_each` da linha 20, então **as contas com id maior que a afetada também nunca são processadas** naquela rodada.

Traduzindo para o cliente: o produto de eval/IA da Tozi está parado desde 21/07 e ninguém recebeu aviso — a tela não quebra, os relatórios simplesmente não enchem. Isso é bem pior que poluir log.

### Proposta de correção (diff conceitual — NÃO aplicado)

**Camada 1 — parar o sangramento (o que eu faria primeiro, backend puro, sem migration):**

```ruby
# enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb
- .includes(:conversation)
- .each { |ep| Captain::EpisodeSegmenterService.new(conversation: ep.conversation).perform }
+ .joins(:conversation)      # INNER JOIN elimina órfãos na própria query
+ .preload(:conversation)
+ .each { |ep| Captain::EpisodeSegmenterService.new(conversation: ep.conversation).perform }
```

`joins` filtra o órfão no SQL (sem N+1, sem guard espalhado). Alternativa mais conservadora, se preferir não mexer na query: `.each { |ep| next if ep.conversation.nil?; ... }`.

**Camada 2 — defesa no serviço** (`enterprise/lib/captain/episode_segmenter_service.rb`, `#perform`): `return [] if conversation.nil?`. `pattr_initialize [:conversation!]` só exige a *chave*, não rejeita nil — vale fechar.

**Camada 3 — causa raiz (migration, exige janela):** limpar os órfãos (`DELETE FROM captain_conversation_episodes e WHERE NOT EXISTS (SELECT 1 FROM conversations c WHERE c.id = e.conversation_id)`) e então `add_foreign_key :captain_conversation_episodes, :conversations, on_delete: :cascade` + `has_many :captain_conversation_episodes, dependent: :delete_all` na Conversation. ⚠️ A FK **falha** se sobrar um órfão — limpar antes, na mesma migration.

| | |
|---|---|
| **Esforço** | Camada 1+2: ~15 min. Camada 3: ~1h (migration + validar em homolog) |
| **Risco de regressão** | Camada 1+2: muito baixo (só deixa de processar registro que já explodia). Camada 3: médio — `on_delete: :cascade` muda comportamento de deleção; validar que a limpeza roda antes da FK |
| **Spec** | Sim, e é fácil: não existe **nenhum** spec para `EpisodeSegmenterService` nem para `ConversationEvalSchedulerJob` (`find spec -path "*captain*" -name "*episode*"` → vazio). Caso: criar episódio, `Conversation.delete` (sem callbacks) para forjar o órfão, rodar o job e esperar que não levante e que `enqueue_closed_episodes` ainda enfileire |

---

## Issue 65 — `NoMethodError: undefined method 'truncate' for nil`

**13 eventos · projeto `tozi` (PROD) · 2026-07-10 20:10 → 2026-07-27 20:42 · releases `1ffd7c49ed`, `ed05923b7b`, `2bd596be84`**

### Stack — frames do nosso código

```
app/controllers/api/v1/accounts/conversations/messages_controller.rb:79  #destroy
app/services/messages/delete_content_service.rb:23                       #perform
app/services/messages/delete_content_service.rb:42                       #resolve_waha_message_id_safely
app/services/messages/waha_message_resolvable.rb:42                      #resolve_waha_message_id
app/services/messages/waha_message_resolvable.rb:47                      #find_waha_message_id_from_api  <-- estoura aqui
```

Request: `DELETE https://tozi.chatspx.app/api/v1/accounts/6/conversations/10540/messages/1563060`

Snippet do GlitchTip:

```ruby
"session=#{inbox.waha_session_name}, content=#{@message.content.truncate(100).inspect}")
                                                              ^^^^^^^^^
```

### Causa raiz — FATO VERIFICADO

`app/services/messages/waha_message_resolvable.rb:46-47` chama `@message.content.truncate(100)` **numa linha de log**, sem tolerar `content` nil. Mensagem outgoing de **mídia sem legenda** (imagem/áudio/documento) tem `content` NULL — no banco de homologação há **2.174 mensagens outgoing com `content IS NULL`**, então o caso é comum, não exótico.

O mesmo bug se repete em `app/services/messages/waha_message_resolvable.rb:72` (`raise_no_match!`, também só log).

Condições necessárias, todas verificáveis no código:
- `propagate_to_waha?` verdadeiro (`delete_content_service.rb:35-37`): inbox WAHA + mensagem outgoing + enviada pelo próprio agente;
- `@message.source_id` em branco (`waha_message_resolvable.rb:40`), senão retorna antes de logar;
- `@message.content` nil.

**Por que vira 500 e não um toast.** `app/controllers/api/v1/accounts/conversations/messages_controller.rb:81` faz `rescue ActiveRecord::RecordInvalid, ArgumentError` — e `delete_content_service.rb:43` faz `rescue ArgumentError`. **`NoMethodError` não está em nenhum dos dois.** `RequestExceptionHandler#handle_with_exception` (linhas 10-23) só trata `RecordNotFound`, `Pundit::NotAuthorizedError` e `ParameterMissing`. A exceção sai limpa até o Rails → **HTTP 500**.

E como ela estoura *antes* de qualquer chamada à WAHA, o `persist_delete` (linha 25) nunca roda: **a mensagem não é apagada nem localmente**. O comentário do próprio serviço (linhas 10-12) diz que o soft-delete local deve acontecer sempre — este caminho viola o contrato que o código declara.

**Confirmação empírica de que o agente fica travado:** os 13 eventos são só 3 mensagens distintas — `messages/1528803` aparece **4×**, `messages/1548710` 2×, `messages/1563060` 2×. É o agente clicando em "apagar" de novo e de novo, recebendo erro, e a mensagem continuando lá.

### Regressão? — sempre existiu neste código

O `firstSeen` (10/07) é anterior às três releases que aparecem nos eventos, e o defeito está na primeira versão do concern (é um log escrito junto com a feature de delete-for-everyone da WAHA, que é código nosso). Não achei commit anterior em que a linha estivesse correta. **HIPÓTESE (não provada):** nasceu com a feature — não consegui datar o commit de origem porque o arquivo é recente e o `firstSeen` do GlitchTip só cobre a janela de retenção.

### Impacto real para o usuário final

**Médio-alto e visível.** O agente da Tozi seleciona "apagar mensagem" numa foto/áudio que ele mesmo mandou, e recebe erro. A mensagem permanece na tela do agente **e no WhatsApp do cliente**. Não há workaround na interface. É o erro desta lista com a dor mais direta e imediata — e o mais barato de consertar.

### Proposta de correção (diff conceitual — NÃO aplicado)

```ruby
# app/services/messages/waha_message_resolvable.rb:47
- "session=#{inbox.waha_session_name}, content=#{@message.content.truncate(100).inspect}")
+ "session=#{inbox.waha_session_name}, content=#{@message.content.to_s.truncate(100).inspect}")

# app/services/messages/waha_message_resolvable.rb:72
- Rails.logger.warn("... for content=#{@message.content.truncate(100).inspect}")
+ Rails.logger.warn("... for content=#{@message.content.to_s.truncate(100).inspect}")
```

`match_targets` (linha 128-133) já é seguro — o `.compact` remove o nil, então a lógica de match não precisa de mudança.

**Opcional, a critério do coordenador:** trocar `rescue ArgumentError` por `rescue StandardError` em `delete_content_service.rb:43`, para que o soft-delete local nunca mais seja bloqueado por um erro na resolução do id. Ganha robustez, perde visibilidade de bugs futuros — é um trade-off, não uma recomendação.

| | |
|---|---|
| **Esforço** | ~5 minutos |
| **Risco de regressão** | **Nulo.** `to_s` em string é identidade; só muda o texto do log quando content é nil |
| **Spec** | Sim, e o arquivo já existe: `spec/services/messages/delete_content_service_spec.rb`. Caso: mensagem outgoing em inbox WAHA, `content: nil`, `source_id: nil`, `Current.user` = sender → esperar soft-delete local em vez de exceção |

---

## Issue 86 — `ArgumentError: wrong number of arguments (given 2, expected 3)`

**54 eventos · projeto `tozi` (PROD) · 2026-07-15 20:23 → 2026-07-27 02:19 · release `2bd596be84` · fila `purgable`**

### Stack — frames do nosso código

```
app/jobs/avatar/avatar_from_favicon_job.rb:9   Avatar::AvatarFromFaviconJob#perform
app/jobs/avatar/avatar_from_url_job.rb:17      perform   <-- aridade não bate
```

Payload Sidekiq do evento (`contexts.sidekiq.args`):

```json
{"job_class": "Avatar::AvatarFromFaviconJob",
 "arguments": [{"globalid": "gid://chatwoot/Company/12"}],
 "queue_name": "purgable", "executions": 0}
```

### Causa raiz — FATO VERIFICADO, e a hipótese "job velho na fila" está DESCARTADA

O enunciado pedia para distinguir **payload antigo na fila** de **callsite desatualizado**. É o segundo, e a prova está no próprio payload: o job enfileirado é o `AvatarFromFaviconJob` com **1 argumento** (`Company/12`) — que é exatamente a assinatura atual dele (`app/jobs/avatar/avatar_from_favicon_job.rb:4`, `def perform(company)`). O payload está **correto**. O erro acontece *dentro* do perform, na chamada síncrona da linha 9:

```ruby
# app/jobs/avatar/avatar_from_favicon_job.rb:9
Avatar::AvatarFromUrlJob.perform_now(company, favicon_url)   # 2 argumentos

# app/jobs/avatar/avatar_from_url_job.rb:17
def perform(avatarable_type, avatarable_id, avatar_url)      # 3 parâmetros
```

**Não drenar nem versionar fila resolve nada** — só corrigir o callsite.

### Regressão? — SIM, e é nossa. Commit identificado.

`git log -S "def perform(avatarable_type, avatarable_id, avatar_url)"` devolve um único commit:

```
2026-03-30 20:29:09 +0000  87095e111b  feat: auditoria completa best practices 2026 + ~120 fixes
```

`git show 87095e111b -- app/jobs/avatar/avatar_from_url_job.rb`:

```diff
-  def perform(avatarable, avatar_url)
+  ALLOWED_AVATARABLE_TYPES = %w[Contact User Inbox AgentBot].freeze
+
+  def perform(avatarable_type, avatarable_id, avatar_url)
+    return unless ALLOWED_AVATARABLE_TYPES.include?(avatarable_type)
+
+    avatarable = avatarable_type.constantize.find_by(id: avatarable_id)
```

A própria mensagem do commit anuncia a mudança: *"Sidekiq: 29 jobs convertidos AR objects → IDs + callers + specs"*. Mas o `--stat` do commit mostra que ele tocou **apenas dois arquivos** em `app/jobs/avatar/`: `avatar_from_gravatar_job.rb` e `avatar_from_url_job.rb`. **O `avatar_from_favicon_job.rb` ficou para trás.**

Cronologia completa:
- **2026-03-05** — `059506b1db feat: Add automatic favicon fetching for companies (#13013)` (upstream Chatwoot) introduz o favicon job já chamando `perform_now(company, favicon_url)` — **correto na época**, a assinatura era de 2 args.
- **2026-03-30** — `87095e111b` (nosso) muda a assinatura para 3 args e atualiza 17 callsites, **menos** esse. Confirmei que os outros 17 estão corretos (`grep -rn AvatarFromUrlJob`: todos usam `(class.name, id, url)`).
- **2026-07-15** — primeiro evento no GlitchTip (quando a Tozi cadastrou uma empresa com domínio).

**Armadilha importante:** só corrigir a aridade **não resolve** o problema de negócio. `ALLOWED_AVATARABLE_TYPES = %w[Contact User Inbox AgentBot]` **não inclui `Company`**, então `avatar_from_url_job.rb:18` daria `return` imediato e o favicon nunca seria anexado — o erro sumiria do GlitchTip e a feature continuaria quebrada, agora em silêncio. O fix precisa ser duplo.

### Impacto real para o usuário final

**Baixo — honestamente, é quase só ruído.** O que quebra: a empresa cadastrada no CRM da Tozi fica sem o ícone do site (`Company#fetch_favicon`, `enterprise/app/models/company.rb:51`, roda em `after_create_commit`). Nada de mensagem perdida, nada de tela travada — o avatar simplesmente não aparece. O job vive na fila `purgable`, a de menor prioridade, e falha isolado.

O único custo colateral é os retries do Sidekiq ocupando a fila (54 eventos para uma quantidade bem menor de empresas — `Companies::FetchAvatarsJob` também enfileira em lote, `app/jobs/companies/fetch_avatars_job.rb:12`).

### Proposta de correção (diff conceitual — NÃO aplicado)

```ruby
# app/jobs/avatar/avatar_from_favicon_job.rb:9
- Avatar::AvatarFromUrlJob.perform_now(company, favicon_url)
+ Avatar::AvatarFromUrlJob.perform_now(company.class.name, company.id, favicon_url)

# app/jobs/avatar/avatar_from_url_job.rb:15
- ALLOWED_AVATARABLE_TYPES = %w[Contact User Inbox AgentBot].freeze
+ ALLOWED_AVATARABLE_TYPES = %w[Contact User Inbox AgentBot Company].freeze
```

⚠️ `Company` é modelo **enterprise-only** (`enterprise/app/models/company.rb`). Numa instalação CE, `'Company'.constantize` (linha 20) levantaria `NameError`. Como o único caminho que enfileira com `'Company'` é o próprio `Company#fetch_favicon`, que só existe em EE, o risco é teórico — mas se quiser blindar, trocar `.constantize` por `.safe_constantize` (o `return unless avatarable` da linha 21 já cobre o nil).

`should_sync_avatar?` (linha 46-56) e `update_avatar_sync_attributes` (linha 74-85) só se aplicam a `Contact`, então `Company` passa direto — sem efeito colateral.

| | |
|---|---|
| **Esforço** | ~10 minutos |
| **Risco de regressão** | Baixo. A allowlist só *amplia*; o callsite corrigido usa o mesmo padrão dos outros 17 |
| **Spec** | Sim. `spec/jobs/avatar/` tem `avatar_from_url_job_spec.rb` e `avatar_from_gravatar_job_spec.rb`, mas **não tem** `avatar_from_favicon_job_spec.rb` — criar um cobrindo `perform_now` com os 3 args e o anexo efetivamente gravado (o teste precisa verificar o **anexo**, não só a chamada, senão o esquecimento da allowlist passa batido) |

---

## Issue 160 — `NoMethodError: undefined method 'dig' for an instance of String`

**4 eventos · projeto `homologacao` (VM .232) · 2026-07-27 19:23 → 19:26 · release `d985beeafd` · `source: runner`, `server_name: chatwoot`**

### Stack — frames do nosso código

```
app/services/waha/group_locator.rb:28   Waha::GroupLocator.group_id
app/models/conversation.rb:219          Conversation#group?   <-- estoura aqui
```

Snippet do GlitchTip:

```ruby
return true if additional_attributes&.dig('type') == 'group'
                                    ^^^^^
```

### Causa raiz — FATO VERIFICADO (parcialmente), e o diagnóstico do enunciado está certo

A intuição do enunciado — *"campo jsonb que às vezes vem string serializada e às vezes hash"* — está **correta**. `Conversation#additional_attributes` é `jsonb`; o `&.` protege contra nil, mas **não contra tipo errado**. Quando a coluna guarda uma String JSON em vez de um objeto, `String#dig` não existe → `NoMethodError`.

**Este erro já foi diagnosticado e corrigido — o fix está no working tree da .232, não commitado.** `git diff HEAD -- app/models/conversation.rb` mostra a versão atual:

```ruby
def group?
  return true if jsonb_hash(additional_attributes)['type'] == 'group'
  ...
end

# Coluna jsonb lida com tolerancia: devolve sempre Hash, mesmo quando o registro
# guarda uma String JSON (dado gravado torto) ou nil.
def jsonb_hash(value)
  return value if value.is_a?(Hash)
  return {} if value.blank?
  parsed = JSON.parse(value.to_s)
  parsed.is_a?(Hash) ? parsed : {}
rescue JSON::ParserError
  {}
end
```

Estado dos arquivos envolvidos (`git status --porcelain`):
- `M app/models/conversation.rb` — modificado, **não commitado** (o `group?` nem existe em `HEAD`)
- `?? app/services/waha/group_locator.rb` — **untracked**, arquivo novo

### O que **NÃO** consegui provar

- **De onde veio a String no jsonb.** O comentário no código atribui a *"um `update_all` mal escrito"*, mas `grep -rn "update_all\|update_columns" | grep additional_attributes` devolve só três ocorrências, todas escrevendo Hash corretamente (`avatar_from_url_job.rb:84`, `enterprise/app/models/enterprise/concerns/conversation.rb:57,77`). **Não achei o culpado no código.**
- **O dado torto não está mais no banco.** SELECT em homologação: `conversations` com `jsonb_typeof(additional_attributes) <> 'object'` = **0**; `contacts` com `custom_attributes` não-objeto = **0**.
- **HIPÓTESE (não provada):** os 4 eventos vieram de um `rails runner` de diagnóstico dos grupos WAHA (`source: runner`, os 4 num intervalo de 3 minutos), que atribuiu a String em memória ou gravou e reverteu. Não tenho como confirmar.

### Regressão? — não. É código WIP que nunca chegou a produção.

O `release` reportado (`d985beeafd`) é o HEAD atual da `homologacao`, mas o `group?` **não existe nesse commit** — o Rails carrega do disco, então o processo rodava o working tree. Como `group_locator.rb` é untracked e `conversation.rb` está modificado sem commit, **nada disso está em nenhuma VM da frota**.

### Impacto real para o usuário final

**Zero hoje.** Nenhum cliente roda esse código.

**Mas o impacto *potencial* é o maior dos quatro,** e por isso vale tratar antes do commit. `Conversation#group?` já é consultado em 10 caminhos, vários deles críticos:

```
app/controllers/public/api/v1/inboxes/messages_controller.rb:127  <-- RECEBIMENTO de mensagem
app/services/csat_survey_service.rb:32
app/listeners/nps_survey_listener.rb:49
app/services/message_templates/hook_execution_service.rb:70
app/services/message_templates/template/out_of_office.rb:12
enterprise/app/services/captain/behavior/router_service.rb:54     <-- roteamento da IA
app/services/llm_formatter/conversation_llm_formatter.rb:145
app/jobs/waha/refresh_groups_job.rb:110
app/controllers/concerns/waha_group_syncable.rb:22
app/services/waha/group_locator.rb:28
```

Um único registro torto derrubaria o recebimento de mensagem e o roteamento da IA. O `jsonb_hash` do working tree já resolve isso — é a decisão certa.

### Proposta de correção (diff conceitual — NÃO aplicado)

O fix principal **já está escrito**. O que falta é fechar a lacuna gêmea, no mesmo WIP:

```ruby
# app/services/waha/group_locator.rb:33 — mesmo bug, não corrigido:
candidates = [contact.identifier, *(contact.custom_attributes || {}).values_at('waha_whatsapp_chat_id', 'waha_whatsapp_jid')]
#                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ String#values_at não existe → NoMethodError
```

Se `custom_attributes` for String, `|| {}` não ajuda (String é truthy) e `values_at` estoura. Reaproveitar a mesma tolerância — o mais limpo seria extrair `jsonb_hash` para um concern/helper compartilhado em vez de ser um método privado de `Conversation`.

**Observação de escopo (não é bug ativo, mas é a mesma classe):** `app/models/conversation.rb:308` (`additional_attributes['type'] == 'tweet'`) e `:537-539` (`additional_attributes['referer']`) acessam a coluna sem tolerância. São código upstream, nunca apareceram no GlitchTip — registro aqui só para o coordenador decidir se quer padronizar.

| | |
|---|---|
| **Esforço** | ~10 minutos (só a lacuna do `group_locator.rb`) |
| **Risco de regressão** | Muito baixo — código ainda não deployado, dá para validar em homologação antes de sair |
| **Spec** | Sim, e é barato: spec de `Conversation#group?` com `additional_attributes` = Hash, String JSON válida, String lixo e nil. Não existe spec para `group?` nem para `Waha::GroupLocator` hoje |

---

## Ranqueamento — por onde começar

Ordenado por **(impacto no usuário) ÷ (custo de corrigir)**.

| Ordem | Issue | Vol. | Impacto no usuário | Esforço | Risco | Migration? | Justificativa |
|:---:|---|---:|---|---|---|---|---|
| **1º** | **#65** truncate for nil | 13 | **Médio-alto** — agente clica "apagar", toma 500, mensagem fica no WhatsApp do cliente | ~5 min | **Nulo** | Não | Melhor razão valor/linha da lista inteira. Uma linha × 2 ocorrências, `to_s` puro, spec já tem arquivo. Não há motivo para adiar |
| **2º** | **#128** messages for nil | 996 | **Alto** — o eval da conta para inteiro, sem aviso; contas seguintes no `find_each` também ficam sem processar | ~15 min (camada 1+2) | Muito baixo | Não (camada 3 sim) | Maior dano funcional e maior volume. A camada 1 (`joins`) resolve o sangramento **hoje** sem migration; a FK pode ir depois, com janela |
| **3º** | **#86** wrong nr of args | 54 | **Baixo** — favicon de empresa não aparece; puro cosmético | ~10 min | Baixo | Não | Regressão nossa comprovada (`87095e111b`), conserto óbvio. Fica em 3º porque ninguém perde mensagem por causa dele. **Corrigir a aridade E a allowlist** — só a aridade transforma o erro em falha silenciosa |
| **4º** | **#160** dig for String | 4 | **Zero em produção** (código WIP local) — mas potencial alto se for deployado como está | ~10 min | Muito baixo | Não | Não é urgência de produção, é **gate de qualidade antes do commit** do WIP de grupos WAHA. Fechar `group_locator.rb:33` junto |

### Sugestão de lotes

- **Lote A (hoje, backend puro, sem migration, deploy leve):** #65 + #128 camadas 1 e 2 + #86. Três arquivos de aplicação, nenhuma migration, nenhum asset de front — não precisa de `assets:precompile`, só `git pull` + restart. Fecha ~1.063 dos 1.067 eventos.
- **Lote B (janela agendada):** #128 camada 3 (limpeza dos órfãos + FK `on_delete: :cascade` + `dependent:`). Exige migration e validação em homologação primeiro.
- **Lote C (antes de commitar o WIP de grupos WAHA):** #160 — fechar `group_locator.rb:33` e escrever o spec de `group?`.

### Especificações de teste sugeridas (nenhuma existe hoje)

| Issue | Arquivo | Status |
|---|---|---|
| #65 | `spec/services/messages/delete_content_service_spec.rb` | Existe — só adicionar o caso `content: nil` |
| #128 | `spec/enterprise/lib/captain/episode_segmenter_service_spec.rb` + `..._eval_scheduler_job_spec.rb` | **Nenhum dos dois existe** |
| #86 | `spec/jobs/avatar/avatar_from_favicon_job_spec.rb` | **Não existe** (os irmãos `url` e `gravatar` existem) |
| #160 | spec de `Conversation#group?` e `Waha::GroupLocator` | **Nenhum existe** |

---

## Anexo — método e limites

**Fontes de evidência usadas:** GlitchTip via GET (`/api/0/issues/<id>/` e `/events/`, `/events/latest/`); leitura direta do código na branch `homologacao`; `git log -S`, `git show`, `git show <sha>:<path>` para comparar com o release da Tozi; `git status --porcelain` para separar código commitado de WIP; SELECTs read-only no Postgres de homologação.

**Restrições respeitadas:** nenhuma alteração em `app/`, `lib/`, `enterprise/`, `config/`, `db/`. Somente `SELECT` no banco. Somente `GET` no GlitchTip (nenhum issue marcado como resolvido). Nenhum SSH para .109/.229/fábrica. Nenhum commit, deploy ou restart.

**O que ficou fora do alcance:**
- Não pude inspecionar o banco da Tozi (.109) — proibido por escopo. Logo, para o **#128** provei o *mecanismo* que produz o órfão (ausência de FK + ausência de `dependent:` + caminhos de deleção assíncrona), mas **não** contei quantos episódios órfãos existem lá nem qual conta é a afetada. Em homologação a tabela está vazia (0 episódios), então não há como reproduzir localmente sem forjar os dados.
- A contagem de retries do Sidekiq que explica os 996 eventos do #128 é cálculo consistente, não medição — não abri a fila da Tozi.
- Para o **#160**, não identifiquei o código que gravou String no jsonb; o banco de homologação está limpo hoje.
