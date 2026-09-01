# G3 — GlitchTip: a família WAHA/LID

> Investigação · 28/07/2026 · VM 192.168.8.232 (homologação), branch `homologacao`, HEAD `d985beeafd`
> **Somente investigação.** Nenhum arquivo de `app/`, `lib/`, `enterprise/`, `config/` ou `db/` foi alterado.
> Banco: só `SELECT`. WAHA e GlitchTip: só `GET`. Nenhum SSH para outra VM.

---

## 0. VEREDITO DA PERGUNTA 1(d) — o que você pediu primeiro

### **NÃO há incompatibilidade entre o cache de ontem e o job antigo. O contrato bate.**

Verificado no Redis vivo desta VM, não no comentário do código:

```
$ redis-cli --scan --pattern 'alfred:waha:lid_pn:*' | wc -l
726
$ redis-cli get alfred:waha:lid_pn:Simplex:201769107873931
559284152449
$ redis-cli ttl alfred:waha:lid_pn:Simplex:201769107873931
604290          # 7d - ~8min → escrito pelo cron das 12:00 de hoje
```

- chave = `waha:lid_pn:{session}:{lid só dígitos}` ✅
- valor = telefone só dígitos, E.164 sem `+` ✅
- `Whatsapp::LidPhoneCache.normalize_lid` aceita tanto `"229480102662169"` quanto `"229480102662169@lid"` (`lid_phone_cache.rb:101`) — e o `ResolveLidJob` carrega o JID cru (`resolve_lid_job.rb:58`). **Casa sem conversão.**

**Havia um risco real de namespace, e ele NÃO se concretizou.** `$alfred` é um
`Redis::Namespace.new('alfred', ...)` (`config/initializers/01_redis.rb:10`), então toda chave ganha o
prefixo `alfred:`. O `read` passa por `Redis::Alfred.get` (namespaced), mas o `write_many` acessa o pool
**cru** (`lid_phone_cache.rb:86`: `$alfred.with { |conn| conn.pipelined { ... } }`). Se `Redis::Namespace#pipelined`
não fosse namespaced, o lote gravaria em `waha:lid_pn:*` e a leitura procuraria em `alfred:waha:lid_pn:*` —
cache 100% miss, silencioso, indetectável por teste unitário com MockRedis.

Não acontece: `redis-namespace 1.10.0`, `lib/redis/namespace.rb:311` → `def pipelined(&block); namespaced_block(:pipelined, &block); end`.
E a prova empírica está acima: as 726 chaves existem **com** o prefixo `alfred:`. **FATO VERIFICADO.**

> ⚠️ Registre isso como invariante: `write_many` depende de um detalhe de implementação da gem
> `redis-namespace`. Um upgrade de major dessa gem pode quebrar o cache **sem quebrar nenhum teste**.
> Um spec que asserte a chave física (`redis.keys('alfred:waha:lid_pn:*')`) fecharia esse flanco.

### O que EXISTE de descasamento — e é material

**O cache nunca terá a chave que o `ResolveLidJob` procura, por causa da SESSÃO.**

| lado | sessão usada | de onde vem |
|---|---|---|
| escrita (`RefreshGroupsJob`) | só sessões **WORKING** descobertas em `GET /api/sessions` | `refresh_groups_job.rb:62-74` |
| leitura (`ResolveLidJob`, se ligado) | `inbox.waha_session_name` | `resolve_lid_job.rb:19` |

Nesta VM, hoje:

```
inboxes WAHA:   id 42 → sessão "spx"          (não existe mais na WAHA)
                id 43 → sessão "simplexteste" (status FAILED)
sessões WORKING na WAHA: apenas "Simplex"
chaves de cache: 726, TODAS em waha:lid_pn:Simplex:*
chaves waha:lid_pn:simplexteste:* → 0
chaves waha:lid_pn:spx:*          → 0
```

Ligar o `ResolveLidJob` ao cache, **hoje, nesta VM, reduziria exatamente 0 dos 2.812 erros.** Não por
defeito do cache — por descasamento de escopo. Detalhe abaixo em 1(a).

---

## 1. ISSUE 27 — 2.812× `Waha::ApiService::ConnectionError` (Net::ReadTimeout)

### 1.0 A causa raiz, em uma frase

**Um único `contact_inbox` preso, apontando para uma sessão WAHA em estado FAILED, martelado 7 vezes
por hora por um cron — 20 dias seguidos.** Não é volume de LIDs. É um loop.

### Evidência

**a) Todos os eventos são desta VM, e da fila do cron.** Amostra dos 100 eventos mais recentes
(`GET /api/0/issues/27/events/?limit=100`):

```
server_name : chatwoot                                  ×100   ← esta VM (homologação)
queue       : scheduled_jobs                            ×100
release     : d985beeafd909e608fba4563fe8503d52835d6ec  ×100   ← HEAD atual
janela      : 2026-07-27T19:27Z → 2026-07-28T11:35Z (16h, 100 eventos ≈ 6,3/h)
total       : 2.812 · firstSeen 2026-07-08T19:26Z · lastSeen 2026-07-28T11:35Z (ainda ativo)
```

`Contacts::ResolveLidJob` é `queue_as :high` (`resolve_lid_job.rb:4`). A fila `scheduled_jobs` identifica
sem ambiguidade quem enfileirou: `Contacts::ResolveLidSweepJob`, que faz
`.set(queue: :scheduled_jobs).perform_later` (`resolve_lid_sweep_job.rb:30`), agendado em
`config/schedule.yml:88` para rodar **de hora em hora aos :15**.

**b) Há exatamente UM contato preso na base inteira.** Rodei a mesma query do sweep
(`resolve_lid_sweep_job.rb:44-56`):

```
ci_id 4258 | inbox 43 (sessão "simplexteste") | source_id = UUID (não é @lid)
contact 2021 | identifier = 81820414494285957058@lid | phone_number = NULL
criado em 2026-05-06 · sem alteração desde 2026-05-06 01:24
```

Panorama de `@lid` na base toda: `contact_inboxes.source_id like '%@lid'` = **0**;
`contacts.identifier like '%@lid'` = **1**; `contacts.name like '%@lid'` = **0**.

**c) O timeout é reproduzível ao vivo, e a causa é a sessão FAILED.** `GET` puro contra a WAHA:

```
GET /api/sessions?all=true
  → simplexteste: FAILED · Simplex: WORKING · (+9 FAILED, 1 STOPPED). "spx" NÃO existe mais.

GET /api/simplexteste/lids/81820414494285957058@lid
  → HTTP 422 em 10,22 s
    {"error":"Session status is not as expected...","status":"FAILED","expected":["WORKING"]}

GET /api/Simplex/lids/81820414494285957058@lid          (sessão saudável, mesmo LID)
  → HTTP 200 em 0,21 s   {"lid":"81820414494285957058@lid","pn":null}
```

`Waha::ApiService::DEFAULT_TIMEOUT = 8` (`api_service.rb:12`). **A WAHA leva 10,2 s para dizer 422; o
socket morre aos 8 s.** O erro nunca chega a ser um 422 tratável — vira `Net::ReadTimeout` →
`ConnectionError` (`api_service.rb:5`) → GlitchTip. **FATO VERIFICADO, reproduzido hoje.**

**d) A aritmética fecha.** 1 job/hora × 7 tentativas (`retry_on ... attempts: 7`, `resolve_lid_job.rb:6`)
= 7 eventos/hora = 168/dia. Medido: 72 eventos entre 00:00 e 11:35 de hoje ≈ **6,3/h**. Em 19,7 dias de
issue: 2.812 ÷ 19,7 = **143/dia**. Bate.

**Os 2.812 erros são 1 contato × 7 retries × 24 h × 20 dias. Nada mais.**

---

### 1(a) — Ligar o `ResolveLidJob` ao `LidPhoneCache` reduz quanto, na prática?

**Resposta curta: hoje, zero. E a razão importa mais que o número.**

Três motivos, todos verificados:

1. **Descasamento de sessão.** O único LID preso pertence à sessão `simplexteste`. O cache só tem
   `Simplex`. Miss garantido → cai na WAHA → timeout. (ver §0)
2. **O LID não é resolvível nem pela sessão boa.** `GET /api/Simplex/lids/81820414494285957058@lid`
   → `pn: null`. E ele não aparece em nenhum dos 78 grupos. **Nenhuma quantidade de cache resolve
   um LID que a WAHA não conhece.**
3. **Não há repetição para amortizar.** O cache paga quando N chamadas viram 1. Aqui N = 1 contato.

Os números que você pediu, medidos hoje:

| medida | valor | como |
|---|---|---|
| contatos `@lid` distintos presos | **1** | query do sweep |
| repetição de LID entre tentativas | **100 % — sempre o mesmo LID** | idem |
| entradas que o cache já tem, vindas do `RefreshGroupsJob` | **726** | `redis-cli --scan` |
| pares LID→PN disponíveis em `GET /api/Simplex/groups` | **725** distintos / 931 participantes / 78 grupos / 240 KB / **0,30 s** | GET ao vivo |
| overlap entre as 726 chaves e o LID preso | **0** | — |
| mensagens já gravadas com `content_attributes.group_sender` | **0** | `SELECT` em `messages` |

O cache de ontem **está funcionando e está cheio** (726 entradas, TTL 7 d, repopulado a cada 30 min por
0,3 s de HTTP). Ele só não tem nada a ver com a issue 27.

> **Onde o cache SIM paga:** no caminho novo de ingestão de grupo
> (`messages_controller.rb:146` → `LidPhoneCache.phone`). Se as 90 conversas de grupo desta base
> passassem a receber mensagens pela sessão `Simplex`, seriam 725 LIDs resolvidos em RAM em vez de
> 725 round-trips de até 8 s. Esse ganho é real — só não é o ganho da issue 27.

---

### 1(b) — O cache resolve o timeout ou só reduz a frequência?

**Só reduz frequência, e no caso da issue 27 nem isso.** O miss continua caindo na WAHA.

Estado atual dos freios, verificado arquivo por arquivo:

| freio | `ResolveLidJob` (antigo) | `GroupSenderPhoneResolver` (ontem) |
|---|---|---|
| cache positivo | ❌ nenhum | ✅ `LidPhoneCache.read` (`:38`) |
| cache negativo | ❌ nenhum | ✅ `write_unresolved`, TTL 10 min (`:55`) |
| circuit breaker | ❌ **nenhum** | ✅ `waha:lid_pn:circuit:{session}`, 60 s (`:23-24, :57`) |
| pula sessão não-WORKING | ❌ nenhum | ❌ nenhum (mas o breaker cobre) |
| retry | 7×, 5 s→600 s (~18 min) | 3×, 15 s→300 s (`resolve_group_sender_phone_job.rb:16`) |
| re-enfileiramento eterno | ✅ **sim** — cron horário | ❌ não |

**Retry infinito? Tecnicamente não; na prática sim.** São 7 tentativas por execução, mas o
`ResolveLidSweepJob` reenfileira o mesmo `contact_inbox` **toda hora, para sempre**. O comentário do
sweep (`resolve_lid_sweep_job.rb:3-14`) descreve isso como rede de segurança contra LID preso — e é,
mas **sem estado**: ele não sabe distinguir "vai resolver logo" de "está preso há 83 dias apontando
para uma sessão FAILED".

Detalhe fino que amplifica: `LidNotResolvable < Error` (`api_service.rb:9`) — ou seja, **o `retry_on
Waha::ApiService::Error` também pega o caso "LID legítimo, mas ainda sem mapeamento"**, gastando as 7
tentativas. Esse caminho está silenciado no Sentry (`config/initializers/sentry.rb:11`), então **não
aparece no GlitchTip mas consome fila igual**. O que você vê é a ponta.

---

### 1(c) — Desenho proposto (conceitual — NÃO implementado)

O trabalho de ontem já construiu a peça certa. **A proposta é não escrever nada novo: fazer o job
antigo delegar ao resolver novo.**

**Diff conceitual, 3 movimentos:**

**① `ResolveLidJob#resolve_lid` delega ao `GroupSenderPhoneResolver`**
`resolve_lid_job.rb:66-77` reimplementa à mão exatamente o que o resolver faz melhor (get direto →
fallback de lista). Trocar por `Whatsapp::GroupSenderPhoneResolver.new(session_name).phone_for(lid)`
traz de graça: cache-first, cache negativo, circuit breaker de 60 s por sessão e lock do fallback caro.

> 🚨 **ARMADILHA DE TIPO — a mais importante desta proposta.** `phone_for` devolve **só dígitos**
> (`556699949191`); o `resolve_lid` atual devolve o **JID cru** (`556699949191@c.us`). E esse valor é
> usado como `source_id` de `contact_inbox` em três pontos: `find_by(source_id: pn)` (`:120`),
> `update!(source_id: pn)` (`:143`, `:156`). Trocar o tipo sem adaptar **muda a chave de identidade do
> contato**. Mitigação: manter o job convertendo de volta (`"#{phone}@c.us"`) antes de tocar em
> `source_id`, ou expor um `phone_for_jid`.
> Risco hoje é baixo — os 30 `contact_inboxes` das inboxes WAHA têm `source_id` **100 % UUID**
> (0 `@c.us`, 0 `@lid`, 0 `@g.us`), então nenhum desses branches dispara. Mas é uma bomba-relógio para
> quando o `source_id` passar a ser o JID.

**② Pular sessão que não está WORKING — antes de gastar a chamada**
É o que mata os 2.812. O `RefreshGroupsJob` já resolveu isso do lado dele (`refresh_groups_job.rb:62-74`,
`working_sessions`). O `ResolveLidJob` (e o resolver) não têm esse guarda. Formas, da mais barata à mais
correta:
- **(barata)** cachear `GET /api/sessions` por ~60 s numa chave `waha:sessions:working` e abortar cedo
  quando a sessão do inbox não estiver lá — 1 chamada de 0,1 s protege todas as outras;
- **(correta)** o próprio breaker do resolver já cobriria: o primeiro timeout abre o circuito por 60 s.
  Mas com **uma execução por hora**, o TTL de 60 s expira sempre entre execuções → **o breaker de 60 s
  não protege um job de cadência horária**. Para esse caso o TTL precisa ser da ordem do intervalo do
  sweep (ex.: 30–60 min) ou o breaker precisa ser por `contact_inbox`, não por sessão.

**③ Dar memória ao sweep (dead-letter de verdade)**
Hoje ele é sem estado. Sugestão: contador de falhas em `custom_attributes` do contato (ou chave Redis);
depois de N ciclos sem sucesso, marcar como `lid_unresolvable` e parar de reenfileirar, com um log
periódico e um caminho explícito de "tentar de novo" (ex.: quando a sessão voltar a WORKING). Sem isso,
qualquer LID que a WAHA nunca vai conhecer volta a martelar para sempre.

**Ordem de impacto (o que eu executaria primeiro):**

| # | ação | esforço | reduz |
|---|---|---|---|
| 1 | ② guarda de sessão WORKING no caminho do `ResolveLidJob` | baixo | **~100 % dos 2.812** |
| 2 | ③ memória no sweep | médio | protege contra a próxima recorrência |
| 3 | ① delegar ao resolver (+ conversão de JID) | médio | ganho estrutural, não desta issue |

> **Alternativa operacional, custo zero de código:** aquele `contact_inbox` 4258 aponta para uma sessão
> morta desde 06/05. Limpar/normalizar esse único registro **zera a issue 27 hoje**. É um `UPDATE` — fora
> do meu escopo, e é decisão sua. Registro porque o custo/benefício é gritante: 1 linha × 2.812 erros.
> Mas trata o sintoma: sem ② e ③, a próxima sessão que morrer recria o loop.

**Riscos do pacote todo:** (i) a troca de tipo do `pn` descrita em ①; (ii) um breaker por sessão com TTL
longo atrasa a recuperação legítima quando a WAHA volta — mitigável com `close_circuit` no primeiro
sucesso, que o resolver já faz (`:50`); (iii) mexer no `ResolveLidJob` mexe no `merge_or_update`, que faz
**merge de contatos** — o caminho mais destrutivo desse arquivo. Qualquer alteração ali pede spec de
regressão dos três casos (A/B/C, `:118-131`).

---

## 2. ISSUE 104 — 42× `Phone number deve estar no formato e164`

### **Isto não é WAHA, não é LID, e não é esta VM.**

O enunciado supunha LID gravado como telefone. **É outra coisa: Meta Lead Ads (formulário do Facebook).**

```
culprit     : Sidekiq/Webhooks::MetaLeadAdsJob
server_name : ip-172-31-86-119        ← host AWS, NÃO é a .232
release     : 2bd596be844e358ab541943fb7ce7046f8453d91   (≠ HEAD daqui)
42 eventos · 2026-07-17 → 2026-07-27 · retry_count 4 no evento capturado
```

Stack (frames in-app):
```
app/jobs/webhooks/meta_lead_ads_job.rb#perform
  → app/services/meta/lead_ads/create_conversation_service.rb#perform
    → #build_contact_inbox
      → app/builders/contact_inbox_with_contact_builder.rb#create_contact  ← RecordInvalid
```

Payload do webhook (mascarado): `{"entry":[{"id":"5395*****8152", "changes":[{"field":"leadgen",
"value":{"ad_id":"1202*****0544","form_id":"2545*****5984","leadgen_id":"1563*****4237"}}]}]}` — **o
telefone não vem no webhook**; é buscado depois na Graph API pelo `leadgen_id`. Por isso o número real
não aparece no evento do GlitchTip. **Não tenho como mostrar exemplos reais mascarados: o número não
está no payload capturado, e a base onde ele existe está na VM AWS, fora do meu escopo de acesso.**
Nesta base local, `contacts` com `phone_number` malformado = **0** (os 16 que a contagem inicial pegou
são string vazia, não formato inválido).

### A mecânica, essa sim verificada em código

`create_conversation_service.rb:261-273`:

```ruby
def normalize_phone(phone)
  digits = phone.to_s.gsub(/\D/, '')
  return nil if digits.blank?
  ddd = default_ddd
  digits = "#{ddd}#{digits}" if ddd.present? && digits.length.between?(8, 9)
  digits = "55#{digits}"     if digits.length.between?(10, 11)
  formatted = "+#{digits}"
  Contacts::BrazilPhoneNormalizer.normalize(formatted) || formatted
end
```

Validação em `contact.rb:54-57`: `format: { with: /\+[1-9]\d{1,14}\z/ }` — 2 a 15 dígitos, **primeiro
dígito ≠ 0**.

**Causa raiz: `normalize_phone` nunca valida o próprio resultado.** Dois detalhes:

1. **O `|| formatted` é código morto.** `BrazilPhoneNormalizer.normalize` **nunca devolve nil** — em
   todos os early-returns devolve `@phone_number` (`brazil_phone_normalizer.rb:29-35`). Ou seja, tudo o
   que entra sai, válido ou não. Não há porta de saída.
2. **Nenhuma faixa de comprimento é rejeitada.** Só 8–9 e 10–11 recebem tratamento; qualquer outra
   passa direto para o `Contact`.

Entradas que produzem `RecordInvalid` (**HIPÓTESE**, derivada do código — não pude confirmar contra os
dados reais da VM AWS):

| o que o lead digita | digits | resultado | por quê falha |
|---|---|---|---|
| `0055 66 99999-9999` | `00556699999999` (14) | `+00556699999999` | começa com **0** — regex exige `[1-9]` |
| `0 66 99999-9999` (DDD com zero antigo) | `0669999999` (10) → `550669999999` | `+550669...` | passa na regex, vira **contato errado** (não gera erro, gera lixo) |
| `099999999` sem DDD no hook | `099999999` (9) | `+099999999` | começa com **0** |
| dois números colados no campo | 20–26 dígitos | `+2299…` | > 15 dígitos |
| `9999` (lixo / teste) | `9999` (4) | `+9999` | passa na regex ✅ — vira contato falso, silencioso |

Os dois primeiros (zero à esquerda) são de longe os mais prováveis em formulário aberto do Facebook.
**Não é o nono dígito brasileiro** — o `BrazilPhoneNormalizer` trata isso corretamente, inclusive o caso
de fixo (`LANDLINE_FIRST_DIGITS`, `:16`). **Não é número estrangeiro** — 12 a 15 dígitos passam na regex.

**Conserto conceitual (1 linha):** validar o resultado antes de devolver —
`result.match?(/\A\+[1-9]\d{1,14}\z/) ? result : nil`. Com `nil`, o serviço já tem caminho tratado:
`create_conversation_service.rb:28-37` loga "lead sem phone_number" e segue (ou pula limpo em inbox
Cloud API). **Erro vira log; o lead deixa de ser perdido em retry.** Hoje o job estoura e retenta —
`retry_count: 4` no evento, sem chance de sucesso, porque o dado de entrada não muda.

### O trabalho de ontem piora ou melhora isto?

**Nem um nem outro — os caminhos não se tocam.** Verificado por varredura: `group_sender` só é lido e
escrito em `messages_controller.rb`, `resolve_group_sender_phone_job.rb`,
`conversation_llm_formatter.rb`, `group_participants_parser.rb`, `group_sender_extractor.rb`,
`group_sender_phone_resolver.rb`. **Nenhuma ocorrência de `group_sender` toca `Contact#phone_number`.**
`Whatsapp::ResolveGroupSenderPhoneJob#persist_phone` (`:44-53`) grava **exclusivamente** em
`message.content_attributes` — jsonb, sem validação de formato, sem `Contact`.

Se um dia o `group_sender.phone` for promovido a `Contact#phone_number` (é a evolução natural, e o PR
upstream `chatwoot#13361` aponta nessa direção), aí sim a validação e164 passa a valer para ele —
e o formato de ontem está **certo**: dígitos puros normalizados por `LidPhoneCache.normalize_phone`,
bastando prefixar `+`. **A precaução, quando isso acontecer, é a mesma da issue 104: validar antes de
salvar, nunca confiar no normalizer como filtro.**

---

## 3. ISSUE 155 — 10× `PG::GroupingError: messages.created_at must appear in GROUP BY`

### **Não há bug em código versionado. Foi um `rails runner` ad-hoc — provavelmente da pesquisa de ontem.**

```
culprit     : bin/rails in <main>
tags        : source=runner · server_name=chatwoot (esta VM) · release=d985beeafd (HEAD)
10 eventos  : 2026-07-27 14:35:43 → 15:04:52   (janela de ~29 min)
SQL         : ... GROUP BY "messages"."conversation_id" ORDER BY "messages"."created_at" ...
```

`source=runner` + `culprit: bin/rails in <main>` = comando executado à mão, não job nem request. A
janela (27/07, 14:35–15:04) cai dentro da sessão de pesquisa de ontem — os relatórios de
`plano/pesquisa-grupos-waha/` têm mtime entre 13:10 e 16:45 do mesmo dia. **Não há stack frame de
`app/` porque o código não estava em arquivo nenhum.**

### O mecanismo (é o que você suspeitou)

`app/models/message.rb:136` → `default_scope { order(created_at: :asc, id: :asc) }`.
Todo `Message.where(...).group(:conversation_id).count` carrega esse `ORDER BY messages.created_at`
para dentro do SQL agregado, e o Postgres recusa: a coluna ordenada não está no `GROUP BY` nem é
agregada. **Message é o único modelo de domínio com `default_scope` ordenado** (os outros são
`installation_config` e `label`, que ninguém agrupa).

### Varredura do código versionado — está limpo

- `.group(:conversation_id)` em `app/`, `lib/`, `enterprise/`: **nenhuma ocorrência.**
- Único agregado sobre `Message` em produção: `app/builders/v2/reports/outgoing_messages_count_builder.rb:17`
  → `base_messages` já faz **`.unscope(:order)`** antes de qualquer `.group(...)`. ✅
- `scripts/spx/tozi/consolida_conversas_duplicadas.rb:39` já usa `.reorder(nil).group(:conversation_id)`
  — e usa **desde 08/06/2026** (commit `e22c2eae39`), portanto **não é a origem** dos erros de ontem.

### Conserto (para o próximo runner, não para o repositório)

```ruby
Message.where(...).reorder(nil).group(:conversation_id).count   # ou .unscope(:order)
```

`reorder(nil)` é a forma idiomática do repo (aparece em `campaigns_controller.rb:82,92` e no script
acima). Explicitar o `GROUP BY` com `created_at` também funcionaria, mas muda a semântica da contagem —
não é o que se quer.

**Ação recomendada: nenhuma alteração de código.** Vale marcar a issue como resolvida no GlitchTip
(não parou mais desde 27/07 15:04) e, se quiser blindar, adicionar a regra ao checklist de runner:
*"todo `.group` sobre `Message` leva `.reorder(nil)`"*.

---

## 4. ISSUES 163 e 164 — Redis

### São duas VMs diferentes. Uma delas é esta.

| issue | erro | ×  | janela | servidor |
|---|---|---|---|---|
| 163 | `LOADING Redis is loading the dataset in memory` | 42 | 28/07 **06:42:55 → 06:42:56** (1,1 s) | `ip-172-31-86-119` — **host AWS, não é a .232** |
| 164 | `CannotConnectError: Connection refused 127.0.0.1:6379` | 7 | 28/07 **06:48:18.806 → .908** (0,1 s) | `chatwoot` — **esta VM, homologação** |

**Confirmação independente da 164, no `journalctl` desta máquina:**

```
jul 28 06:48:15 chatwoot systemd[1]: Stopping redis-server.service...
jul 28 06:48:18 chatwoot systemd[1]: Deactivated successfully / Started redis-server.service
jul 28 06:48:17.850Z chatwoot-worker.1 {"lvl":"WARN","msg":"RedisClient::CannotConnectError: Connection refused ..."}
```

`redis-cli info server` → `uptime_in_seconds: 19218` ≈ restart às **06:48 UTC de hoje**. **Fecha ao
segundo.** Restart de serviço, **3 segundos de downtime**, provavelmente atualização de pacote
(o journal registra o `Stopping` sem crash, sem OOM, sem sinal).

A 163 é o mesmo fenômeno num host AWS: Redis subindo e recarregando o RDB (`LOADING`) — 42 erros em 1,1 s
é a assinatura de vários workers batendo na janela de carga. **Não é código; é o ciclo de restart.**

> Observação de triagem: as duas VMs reportam para o **mesmo projeto** do GlitchTip
> (`SENTRY_DSN=.../1`). Erros de homologação e de produção AWS chegam misturados no mesmo balde —
> a única forma de separar é a tag `server_name`. Vale considerar projetos separados (ou pelo menos um
> filtro salvo por `server_name`), senão toda triagem futura vai começar por esta desambiguação.

### O código degrada com elegância? **Sim — e eu confirmei lendo, não pelo comentário.**

**`Whatsapp::LidPhoneCache` — protegido em todas as 4 operações de I/O:**

| método | linha | proteção |
|---|---|---|
| `read` | `lid_phone_cache.rb:44-46` | `rescue StandardError → log + nil` |
| `write` | `:66-68` | `rescue StandardError → log + false` |
| `write_unresolved` | `:76-78` | `rescue StandardError → log + false` |
| `write_many` | `:93-95` | `rescue StandardError → log + 0` |

`phone` e `unresolved?` são wrappers de `read`, herdam a proteção. **`RedisClient::CannotConnectError` e
`RedisClient::CommandError` descendem de `RedisClient::Error < StandardError`** — pegos. `ConnectionPool::TimeoutError`
(`< Timeout::Error < RuntimeError`) também. **Nenhum caminho levanta.** ✅

**O caminho de ingestão de mensagem de grupo também está coberto**, ponta a ponta:

```ruby
# messages_controller.rb:143-148
phone = Whatsapp::LidPhoneCache.phone(group_waha_session_name, sender['lid'])
phone.present? ? sender.merge('phone' => phone) : sender     # nil → segue sem telefone
# :156-163  schedule_group_sender_phone_resolution  → rescue StandardError => log
```

Com o Redis fora: `phone` devolve `nil` → a mensagem **entra normalmente**, sem o telefone do autor →
o job de enriquecimento é enfileirado (ou o `rescue` da linha 161 engole a falha de enfileiramento) →
o front cai no nome do participante. **A ingestão não quebra. FATO VERIFICADO por leitura de código.**

`GroupSenderPhoneResolver` idem: `circuit_open?` (`:117-121`), `open_circuit` (`:123-127`),
`close_circuit` (`:129-133`), `acquire_list_lock` (`:135-140`) — todos com `rescue`. O caso
mais perigoso seria `circuit_open?` levantando e derrubando a resolução; ele devolve `false` (fail-open:
com Redis fora, tenta a WAHA — o comportamento certo).

### O que realmente acontece quando o Redis cai

O ponto frágil **não é o cache novo** — é o Sidekiq. Os 7 erros da issue 164 vêm do processo
`chatwoot-worker.1`, nível `WARN`, das threads internas do Sidekiq (heartbeat/fetch), não de um job.
O Sidekiq reconecta sozinho; nenhum job foi perdido. **Nenhuma requisição de usuário aparece nos
eventos** (`culprit: Sidekiq` nas duas issues; zero frames de controller).

**Custo real de um restart de Redis para o cache de ontem:** `aof_enabled: 0`, `maxmemory_policy:
noeviction`, `dbsize: 4169`, `used_memory: 4,27 MB`. Sem AOF, o que passou do último snapshot RDB
some. Para o mapa LID→PN isso é **irrelevante**: o `RefreshGroupsJob` repopula as 726 entradas a cada
30 min, ao custo de **0,30 s de HTTP**. Perda máxima: até 30 min de cache frio, degradando para o
comportamento antigo (round-trip por LID) — que é exatamente o que o desenho previu.

**Veredito do item 4: infraestrutura, não código. Nenhuma ação necessária.** Se o restart do
`redis-server` da .232 foi manual/apt e vai se repetir, a única melhoria que faz sentido é operacional
(janela de manutenção com o Sidekiq parado antes), não uma mudança de aplicação.

---

## 5. Resumo executivo

| issue | × | onde | veredito | ação sugerida |
|---|---|---|---|---|
| **27** | 2.812 | **.232 homolog** | **1 contact_inbox preso (id 4258) apontando p/ sessão `simplexteste` = FAILED, martelado 7×/h pelo cron horário. WAHA leva 10,2 s p/ dizer 422; timeout é 8 s.** | guarda de sessão WORKING + memória no sweep. (Normalizar o registro 4258 zera hoje — decisão sua) |
| **104** | 42 | **host AWS** `ip-172-31-86-119` | **Meta Lead Ads, não WAHA/LID.** `normalize_phone` não valida o próprio resultado; `\|\| formatted` é código morto | validar E.164 antes de devolver → cai no caminho "lead sem telefone" já existente |
| **155** | 10 | **.232 homolog** | **`rails runner` ad-hoc de ontem.** `default_scope` ordenado de `Message` vazando p/ o `GROUP BY`. Código versionado limpo | nenhuma alteração; marcar resolvida |
| **163** | 42 | **host AWS** | Redis recarregando dataset, burst de 1,1 s | nenhuma |
| **164** | 7 | **.232 homolog** | `systemctl restart redis-server` às 06:48:15, 3 s de downtime | nenhuma |

**Sobre o trabalho de ontem:** o contrato do `LidPhoneCache` está **íntegro e em produção nesta VM** —
726 entradas vivas, chave e valor no formato documentado, `pipelined` corretamente namespaced. O cache
degrada para `nil` com Redis fora, em todas as operações, e a ingestão de mensagem não quebra junto.
**Não há armadilha entre o novo e o antigo.** O que existe é um descasamento de **escopo de sessão** —
o cache cobre `Simplex` (a única WORKING), e as duas inboxes WAHA desta base apontam para sessões
mortas. Isso não é defeito do cache; é o estado da WAHA de homologação.

---

## Anexo — comandos usados (todos read-only)

```bash
# GlitchTip (GET)
curl -H "Authorization: Bearer $TOKEN" https://glitchtip.chatspx.app/api/0/issues/<ID>/
curl -H "Authorization: Bearer $TOKEN" https://glitchtip.chatspx.app/api/0/issues/<ID>/events/latest/
curl -H "Authorization: Bearer $TOKEN" "https://glitchtip.chatspx.app/api/0/issues/27/events/?limit=100"

# WAHA (GET)
GET /api/sessions?all=true
GET /api/simplexteste/lids/81820414494285957058@lid    → 422 em 10,22 s
GET /api/Simplex/lids/81820414494285957058@lid         → 200 em 0,21 s, pn:null
GET /api/Simplex/groups                                → 200 em 0,30 s, 78 grupos / 725 pares

# Postgres (SELECT)
inboxes WAHA · contact_inboxes presos (query do sweep) · formato de source_id
messages com content_attributes ? 'group_sender' · contacts fora do E.164

# Redis (leitura)
redis-cli --scan --pattern 'alfred:waha:lid_pn:*' | wc -l   → 726
redis-cli get/ttl · info server/memory/persistence

# Sistema
journalctl -u redis-server --since "2026-07-28 06:00"
git log / git log -S (histórico do sweep e do script do GROUP BY)
```

**Arquivos lidos** (nenhum modificado): `app/jobs/contacts/resolve_lid_job.rb`,
`app/jobs/contacts/resolve_lid_sweep_job.rb`, `app/jobs/waha/refresh_groups_job.rb`,
`app/jobs/whatsapp/resolve_group_sender_phone_job.rb`, `app/services/whatsapp/lid_phone_cache.rb`,
`app/services/whatsapp/group_sender_phone_resolver.rb`, `app/services/waha/group_participants_parser.rb`,
`app/services/waha/api_service.rb`, `app/services/meta/lead_ads/create_conversation_service.rb`,
`app/services/contacts/brazil_phone_normalizer.rb`, `app/controllers/public/api/v1/inboxes/messages_controller.rb`,
`app/models/message.rb`, `app/models/contact.rb`, `app/builders/v2/reports/outgoing_messages_count_builder.rb`,
`config/initializers/01_redis.rb`, `config/initializers/sentry.rb`, `config/schedule.yml`,
`lib/redis/alfred.rb`, `redis-namespace-1.10.0/lib/redis/namespace.rb`.
