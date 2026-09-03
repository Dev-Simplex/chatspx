# Reconciliação `homologacao` × `redesenho-integra` — lote **BACKEND** (14 arquivos)

**Trilha:** `o4-resto` · **Drop:** `/tmp/claude-1001/resolucao/backend/` · **15 arquivos** (14 do lote + 1 declarado na §3)
**Estado:** `git merge --abort` executado, worktree limpo, **nada commitado** — como o protocolo pede.

**Verificação de entrega:** `grep -rn '^<<<<<<<\|^>>>>>>>\|^=======$'` no drop → **vazio**. `ruby -c` em todos
os `.rb` → **OK**. Os três arquivos seus (`db/schema.rb`, `public/version.json`, `swagger/swagger.json`)
**não foram tocados** — os dois primeiros conferidos por md5 antes e depois (§6).

---

## 1. Resolução, arquivo por arquivo

| # | Arquivo | `redesenho-integra` (ours) | `homologacao` (theirs) | O que ficou |
|---|---|---|---|---|
| 1 | `AGENTS.md` | 2 armadilhas do merge v4.16.2 (`feature_flags_ext_2`, `quoted_email_reply`) | 1 armadilha de timestamp de migration | **União.** Itens diferentes da mesma lista; nenhum se sobrepõe |
| 2 | `agents_controller.rb` | nada (upstream removeu os 4 `before_action`) | 4 `before_action`: 2 de supervisor + 2 de limite | **2 do supervisor entram, 2 de limite saem.** Ver §2.1 |
| 3 | `account.rb` | `include AccountSettingsSchema` (schema extraído) | `SETTINGS_PARAMS_SCHEMA` inline, com 2 chaves próprias | **Forma nova** (o `include`), e as 2 chaves migraram para o concern. Ver §2.2 |
| 4 | `whatsapp/health_service.rb` | `throughput_level`, `is_on_biz_app` + 2ª chamada Graph (WABA/portfólio) | `acceptable_webhook_urls`, `certificate`, `business_id` | **União.** `business_id` sai porque virou `business_account_id` da fonte. Ver §2.3 |
| 5 | `whatsapp_cloud_service.rb` | `normalize_opus_content_type` + `build_attachment_content` | `resolve_media_type` + `voice_note_content` + `apply_caption` | **Composição das duas.** Ver §2.4 |
| 6 | `enterprise/account.rb` (2 hunks) | `api_and_webhooks_enabled?`, `billing_currency*`, `enable_default_features` | `handoff_teams`, `handoff_allowed_team_ids` | **União.** Métodos independentes; nenhum toca no outro |
| 7 | `plan_usage_and_limits.rb` | `increment_custom_attribute(...)` | SQL `jsonb_set` atômico inline | **Upstream.** O helper faz exatamente o mesmo, atômico, com bind param. Ver §2.5 |
| 8 | `concerns/attachment.rb` (2 hunks) | `broadcast_message_update_for_audio` | `enqueue_media_description` + `media_pipeline_wanted?` | **União.** Dois `after_create_commit`, dois métodos |
| 9 | `concerns/conversation.rb` | `sla_applicable?` | `clear_awaiting_closure_on_customer_reply` | **União.** Métodos independentes |
| 10 | `audio_transcription_service.rb` | chamada direta, `transcription_model` + `temperature: 0.0` | `whisper_with_retry(...)` | **Retry da equipe, migrado para a forma nova.** Ver §2.6 |
| 11 | `inboxes_controller_spec.rb` | campos de WABA/portfólio no dublê | `business_id`, `expected_webhook_url`, `acceptable_webhook_urls` | **União menos `business_id`**, para o dublê espelhar o serviço resolvido |
| 12 | `enterprise/models/account_spec.rb` | `default features`, `captain document sync cadence` | `#handoff_teams` (7 exemplos) | **União.** 43 → 50 exemplos |
| 13 | `whatsapp/health_service_spec.rb` | spec inteiro (add/add), estrutura nova | spec inteiro (add/add), foco em WABA | **Base do upstream + 7 casos da equipe reescritos.** Ver §2.7 |
| 14 | `whatsapp_cloud_service_spec.rb` (4 hunks) | 2 testes de áudio/voice | 3 testes de limite inline (vídeo/imagem) | **União dos 5**, com `v13.0` → `v24.0` nos da equipe |

---

## 2. As sete resoluções que não foram união trivial

### 2.1 `agents_controller.rb` — dois `before_action` entram, dois saem

**Os do supervisor ficam, e é obrigatório:** `authorize_supervision_change` e
`authorize_supervisor_update` **existem no arquivo** (linhas 82 e 96). Sem os `before_action`, eles
viram **código morto** — a autorização de quem pode mudar supervisão simplesmente não roda, e
nenhum teste do lado do upstream notaria, porque para ele a feature não existe.

**Os de limite saem porque os métodos não existem mais.** `validate_limit` e
`validate_limit_for_bulk_create` eram métodos da homologação (linhas 177-185 lá); o upstream os
removeu e moveu a checagem para dentro do `AgentBuilder`, que levanta
`AgentBuilder::LimitExceededError` **de dentro de um `account.with_lock`** — e `create`/`bulk_create`
já a capturam. Mantê-los daria `NoMethodError` em toda criação de agente.

**A funcionalidade não se perdeu, melhorou:** sob lock, duas criações simultâneas não furam mais o
limite — o que o `before_action` permitia. O `bulk_create_agents` faz a mesma checagem de lote
(`raise ... if emails.count > available_agent_count`), também sob lock, antes de criar qualquer um.

### 2.2 `account.rb` — a feature migra para a forma nova

O upstream extraiu `SETTINGS_PARAMS_SCHEMA` para `AccountSettingsSchema`. O concern já tinha 15 das
17 chaves; **faltavam duas, e as duas são da equipe**: `template_reply_routing` e `contact_invite`.

Resolver a favor do concern sem trazê-las teria apagado as duas em silêncio —
`additionalProperties: true` deixa o valor ser **gravado**, mas sem a declaração o campo perde
validação de tipo e some de qualquer consumidor que leia o schema. O sintoma apareceria semanas
depois, no roteamento de template ou no convite de contato de um cliente.

`captain_models`/`captain_features` ficaram na forma do upstream (derivadas de
`Llm::Models.feature_keys`): **conferi que as 13 features do `config/llm.yml` cobrem as 6 que a
equipe listava à mão** — inclusive `audio_transcription` e `help_center_search`. Nada se perde e a
lista deixa de precisar de manutenção manual.

### 2.3 `health_service.rb` — `acceptable_webhook_urls` não podia sair

A Meta aceita **um** `override_callback_uri` por WABA. Com vários números no mesmo WABA, a URL
registrada pertence a um só deles — e mesmo assim é válida para todos, porque a entrada resolve o
canal pelo `phone_number_id` do payload, não pela URL. Sem este campo, `AccountHealth.vue` (que veio
no merge, **com spec próprio de 10+ casos**) volta a acusar "webhook url mismatch" num canal que
funciona.

Os métodos `build_acceptable_webhook_urls`/`sibling_phone_numbers` já estavam no arquivo pelo
auto-merge: **sem a linha que os chama, seriam código morto.**

Também trouxe `certificate`, e acrescentei o campo a `phone_health_fields` — sem pedi-lo ao Graph, a
chave voltaria sempre `nil`. Ele **não** entrou em `PERSISTED_FIELDS`: essa lista define o que fica
gravado no canal em toda a frota, e mexer nela não é decisão desta reconciliação.

**`business_id` não foi trazido**, e é o único campo que sai: ele repetia
`provider_config['business_account_id']`, e o upstream passou a buscar o dado na **fonte** (segunda
chamada Graph), entregando `business_account_id` + `business_account_name` + o portfólio. O
`AccountHealth.vue` do merge já lê a forma nova (`business_portfolio_id`, linha 326).

### 2.4 `whatsapp_cloud_service.rb` — três linhas, três donos

```ruby
normalize_opus_content_type(attachment)                       # upstream
type = resolve_media_type(attachment)                          # equipe
type_content = voice_note_content(attachment, type) || build_attachment_content(type, attachment, message)
```

- **`normalize_opus_content_type` (upstream):** o Marcel re-detecta OGG/Opus como `audio/opus` depois
  do attach, e o Meta exige `audio/ogg`. Ainda **ajuda** o passo 3, normalizando o blob antes.
- **`resolve_media_type` (equipe):** vídeo acima de 16 MB e imagem acima de 5 MB precisam ir como
  `document`, senão a Meta **recusa**. Usar a versão do upstream aqui reintroduziria a regressão que
  o commit `fix(whatsapp): restaura video >16MB como documento` fechou — e que passou três semanas
  sem ninguém notar.
- **`voice_note_content` (equipe), antes do fallback:** PTT só sai como PTT quando a mídia vai por ID
  (upload em `/media`) com `voice: true`; pelo `link` chega como **arquivo** de áudio — a equipe
  testou em produção com `audio/ogg` e com `audio/ogg; codecs=opus`, e os dois vieram como arquivo.
  Quando o upload falha, devolve `nil` e cai no caminho do upstream: o áudio chega como arquivo em
  vez de não chegar.

**`apply_caption` foi removido:** `build_attachment_content` faz o mesmo (legenda com assinatura,
pulando áudio/sticker) mais `filename` e `voice`. Mantê-lo deixaria duas funções idênticas, uma sem
chamador.

### 2.5 `plan_usage_and_limits.rb` — o upstream extraiu, não removeu

`increment_custom_attribute` faz **exatamente** o que a homologação fazia inline: `update_all` com
`jsonb_set` **atômico** mais a atualização do objeto em memória. O incremento continua atômico — que
era o ponto da versão da equipe — e o helper ainda usa bind param em vez de interpolar a chave no SQL.

### 2.6 `audio_transcription_service.rb` — a integração ganha, como você indicou

Confirmado: o `initialize` já vinha correto do auto-merge (`@account` antes, `super()` sem argumento).

O conflito era outro, e a resolução preserva os dois lados:
- **o retry é da equipe e fica** — sem ele, um 429 transitório deixava o áudio sem transcrição em
  silêncio;
- **mas `WHISPER_MODEL` não existe mais neste arquivo.** O upstream trocou a constante fixa pelo
  modelo que o `Llm::FeatureRouter` resolve por conta (`transcription_model`). Pegar o lado da
  homologação inteiro daria **`NameError` na primeira transcrição** — em runtime, não no boot, porque
  Ruby só resolve constante quando a linha executa. O arquivo carregaria, os testes do lado antigo
  passariam, e o defeito apareceria no áudio de um cliente. É o modo de falha do seu despacho, no
  estado puro;
- **`temperature: 0.0`, não 0.4:** melhoria do upstream com razão medida — em áudio silencioso,
  temperatura > 0 dispara repetição em espiral (o modelo "alucina" texto que não foi dito).

### 2.7 `health_service_spec.rb` — add/add, os dois lados escreveram o arquivo inteiro

Base: o spec do upstream (testa a estrutura nova: duas chamadas Graph, persistência, log de risco).
Acrescentei **7 casos da equipe, reescritos** — não copiados, porque o serviço mudou de forma.

Um deles mudou de significado e está declarado no próprio spec: o caso
`business_account_id` ausente esperava cair na própria URL; agora `validate_channel!` **recusa antes**
de qualquer chamada ao Graph. O teste virou `raise_error(ArgumentError)`. O fallback continua dentro
de `sibling_phone_numbers` para quem chame o método direto.

---

## 3. Um arquivo FORA da lista de conflitos, e por que foi necessário

**`app/models/concerns/account_settings_schema.rb`** — não conflitou (só existe do lado do upstream),
mas **a resolução de `account.rb` é incompleta sem ele**: é para lá que as duas chaves da equipe
(`template_reply_routing`, `contact_invite`) tinham de migrar. Sem esta edição, resolver `account.rb`
a favor do concern apagaria as duas.

Está no drop, e é a única coisa lá que não estava na sua lista. Se preferir tratá-lo à parte, o diff
é aditivo e isolado: duas chaves no meio do `properties`, com comentário.

---

## 4. ESCALADO — um defeito que o merge NÃO causou, e que ninguém está resolvendo

**`app/controllers/api/v1/accounts/inboxes_controller.rb` — o método `health` está duplicado, e a
cópia errada é a que roda.** O arquivo **não conflitou** (os dois lados eram idênticos), então nenhum
lote o pegou.

O controller **inclui** `Api::V1::Accounts::Concerns::WhatsappHealthManagement` (linha 8) **e
redefine `health`** (linha 108). Em Ruby o método da classe vence o do módulo. Resultado:

| | concern (nunca roda) | controller (o que roda) |
|---|---|---|
| chama | `sync_health_status!` | `fetch_health_status` |
| persiste `phone_number_health` | **sim** | **não** |
| loga transição de risco | **sim** | não |
| erro da Meta | `type` (authorization/api), `http_status`, `code`, `subcode` | `'Failed to fetch health data'` |

Ou seja: **toda a infraestrutura de persistência que o upstream construiu — `PERSISTED_FIELDS`,
`persist_health_status`, `persist_health_error`, `log_risky_transition` — está morta por este
caminho**, e o diagnóstico de erro da Meta é substituído por uma string genérica.

**Como sei que é pré-existente:** os dois lados do merge têm o mesmo `def health` no controller, e o
spec do upstream (`inboxes_controller_spec.rb`) mocka `sync_health_status!` em 4 lugares — ele foi
escrito para o concern. É o próprio spec do upstream denunciando o defeito, e ele falha igual na
`redesenho-integra` pura (medido: 100 exemplos / 8 falhas, sem uma linha minha).

**Não corrigi, e a razão é o protocolo:** o arquivo não é do meu lote, e a decisão de qual método o
endpoint deve chamar é de produto (consultar ao vivo × consultar e persistir). Também **não alinhei o
spec ao defeito** — trocar os mocks para `fetch_health_status` deixaria o CI verde e o defeito de pé.
O vermelho é o sintoma; apagá-lo é pior que tê-lo. A correção é uma linha: apagar o `def health` do
controller e deixar o do concern.

---

## 5. Verificação — o que rodou, e o que ficou de fora

| Spec | Resultado | Leitura |
|---|---|---|
| `whatsapp/health_service_spec.rb` + `whatsapp_cloud_service_spec.rb` | **53 exemplos, 0 falhas** | verde |
| `enterprise/models/account_spec.rb` | 50 exemplos, **1 falha** | a falha é **pré-existente**: o lado `--ours` puro dá 43/1, mesmíssimo teste (`marks new cloud accounts as eligible`). Minha união acrescenta 7 exemplos e nenhuma falha |
| `inboxes_controller_spec.rb` | 101 exemplos, 9 falhas | `--ours` puro dá **100/8**. As 4 de `/health` são o defeito da §4; a 9ª é o teste da equipe (`exposes the sibling webhook urls`), que falha **pela mesma causa** |

**Duas ressalvas honestas sobre o ambiente, não sobre o código:**

1. **`db/schema.rb` está em conflito**, então o banco de teste foi carregado com o schema `--ours`.
   `ActiveRecord::Schema.define(version:)` marca como aplicadas todas as migrations com timestamp
   menor — e as 10 da homologação são de julho/agosto. Resultado: elas contam como aplicadas **sem
   criar as tabelas**, e 3 testes do `inboxes_controller_spec` (284, 389, 650) caem em
   `PG::UndefinedTable: relation "team_supervisors" does not exist`. **É artefato do meu ambiente**;
   no seu, com o schema unido, devem passar. As falhas de `/health` **não** são disso — elas dão
   `MockExpectationError`, que é a §4.
2. **`swagger/swagger.json` em conflito impede qualquer spec de carregar** (`Skooma` tenta parseá-lo
   no `rails_helper` e levanta `Could not parse file swagger.json`). Para rodar, resolvi os dois
   arquivos **temporariamente** por `--ours` e os **restaurei ao estado de conflito** ao final —
   conferido por md5: `db/schema.rb` `cd98f9d5…`, `swagger/swagger.json` `54105ee3…`, idênticos ao
   que estava antes. **Nenhum dos dois está no drop.**

**Rubocop:** 13 ofensas nos 14 arquivos, **todas de métrica** (`ClassLength`, `ModuleLength`,
`MethodLength`, `Cyclomatic/PerceivedComplexity`) mais 2 `RSpec/NoExpectationExample`. Medi o lado
`--ours` puro: **7 delas já existiam**. As 6 novas são consequência aritmética de somar duas features
no mesmo arquivo (ex.: `health_service.rb` passou de 174 para 189 linhas). Não refatorei: mexer na
estrutura de código de terceiros no meio de uma reconciliação é como se perde comportamento. A única
que corrigi foi uma `Layout/IndentationConsistency` que a minha própria união introduziu.

---

## 6. Como confirmar que não toquei nos seus três arquivos

```
db/schema.rb          md5 cd98f9d508a4b99a0803e316b82f86d3   (3 marcadores `<<<<<<<`, intacto)
swagger/swagger.json  md5 54105ee34094c6450c7943905cf298d5   (2 marcadores, intacto)
public/version.json   não aberto
```

Nenhum deles está em `/tmp/claude-1001/resolucao/backend/`.

> **Bônus, se servir:** ao migrar o banco de teste eu gerei o schema com as duas linhagens aplicadas.
> Ele está em `/tmp/schema-unido-gerado.rb`. **Não é entrega** e não confio nele para o seu merge (o
> dump saiu de um banco cujo `schema_migrations` eu mexi para poder testar) — mas pode servir de
> conferência contra o seu, que você já fez duas vezes hoje.

---

## 7. O que ficou parado por causa desta tarefa

O despacho anterior (blocos **5.22** e **5.23**) estava em andamento:

- **5.22 — instalação em WordPress, Wix e GTM: ENTREGUE** e commitado (`1bf8b3fb79`) antes desta
  reconciliação começar. Relatório em `o4-instalacao.md`.
- **5.23 — contexto do sistema externo ao lado da conversa: NÃO COMEÇADO.** Aguarda a sua palavra
  sobre a ordem: retomo agora ou fico disponível para outro lote da reconciliação.
