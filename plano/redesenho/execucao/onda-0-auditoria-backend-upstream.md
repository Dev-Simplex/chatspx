# Onda 0 — TASK A6: o buraco da triagem no BACKEND (arquivos **upstream-only**)

- **Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **branch** `redesenho-merge` · **HEAD** `93571c69db`
- **SHAs:** BASE `899fce1c92` (v4.12.1) · NOSSO `f26db6ee81` · DELES `70e284a044` (v4.16.2) · MERGE `93571c69db`
- **Escopo:** os arquivos de backend que **só o upstream** mudou — invisíveis para a triagem de colisão.
- **Continuação de:** `onda-0-auditoria-ruby.md` (A1). Cruza com `onda-0-auditoria-enterprise.md` (A2).
- **Fora de escopo por decisão da task:** `db/migrate` (coberto por A2 §2, citado onde relevante).

---

## 0. Método, e a primeira coisa que o método revelou

`/tmp/claude-1001/so-deles.txt` tem 3.047 entradas. Filtrando backend (`app/` Ruby+views, `lib/`,
`config/`, `enterprise/`, sem `app/javascript`) restam **645**. Classifiquei cada uma perguntando ao
git se o arquivo existia em `899fce1c92`:

| classe | qtde | por que importa |
|---|---:|---|
| **NOVO** (não existia na BASE) | **311** | é o padrão SafeFetch — código novo que passa a ser chamado |
| **MODIFICADO** (existia; só o upstream mexeu) | **334** | o merge pegou a versão DELES **inteira, sem conflito**. Mudança de comportamento em arquivo que já usávamos passa 100% silenciosa |

Dos 334 modificados, **62 são `config/locales/*.yml`** de idiomas que a frota não usa (`am`, `az`,
`bn`, `hy`, `ka`, `ml`, `ne`, `sh`, `ur_IN`…) → descartados em bloco, sem leitura. Restam **272
modificados** + **311 novos** = **583 candidatos reais**.

> A task pediu para caçar o vetor "arquivo novo chamado por código nosso". O método mostrou que
> existe um **quarto vetor**, mais numeroso e igualmente cego: os 272 **modificados**. Nenhum deles
> gerou conflito, então nenhum humano os leu — e é neles que estão dois dos três achados mais graves
> deste relatório (§1.1 e §1.2).

**Cruzamento mecânico do vetor 1** (reproduzível):
1. `git diff --name-only BASE NOSSO` → 4.760 arquivos que **nós** tocamos (686 `.rb` sobreviventes);
2. para cada um dos 220 `.rb` **novos** do upstream, extraiu-se a constante top-level (`class`/`module`) — 198 delas;
3. `grep -l "\bConstante\b"` sobre os 686 arquivos nossos → **62 acertos**: arquivos novos do
   upstream efetivamente invocados de dentro de código que nós customizamos. Esses 62 foram lidos.

**Vetor 2 (ENV):** extração léxica de todo `ENV.fetch(...)`/`ENV[...]` nas três árvores (BASE, NOSSO,
MERGE) e diferença de conjuntos, para separar ENV nova-do-upstream de ENV nossa. Seção 2.

**Vetor 3 (agir sozinho):** `config/initializers/*` lido integralmente (7 arquivos), `config/schedule.yml`
diffado, os 27 jobs novos listados e rastreados até quem os enfileira. Seção 3.

**Varredura dos 272 modificados:** grep dirigido nas linhas **adicionadas** do diff `BASE→MERGE` por
`def perform(`, `after_commit`, `after_create`, `before_validation`, `validates`, `ENV`, `default:`,
`perform_later` → 38 arquivos com sinal, todos os 38 lidos. Os 234 restantes entraram na amostragem
declarada da §4.

---

## 1. O que muda o comportamento de um caminho que o ChatSPX JÁ USA

Ordenado por gravidade. `DADO` = corrompe/perde dado · `PERDA` = funcionalidade morre · `RISCO` = pode quebrar sob condição da frota.

| # | gravidade | o que quebra | onde | classe |
|---|---|---|---|---|
| 1.1 | **PERDA + DADO** | **Excluir conversa não exclui nada, e responde `200 OK`** | `app/services/conversations/delete_service.rb` (NOVO) | vetor 1 |
| 1.2 | **PERDA** | **Webhook do Instagram passa a exigir HMAC — sempre.** Sem `FB_APP_SECRET`/`INSTAGRAM_APP_SECRET` no GlobalConfig → 401 em 100% dos eventos | `app/controllers/webhooks/instagram_controller.rb` + `concerns/meta_token_verify_concern.rb` (MOD) | vetor 4 |
| 1.3 | **PERDA** | **WhatsApp Cloud: 401 quando o canal não é resolvido pelo payload** — a mensagem é descartada pela Meta e não chega a lugar nenhum | `app/controllers/webhooks/whatsapp_controller.rb` (MOD) | vetor 4 |
| 1.4 | **RISCO alto** | Tools HTTP do Captain e avatar-por-URL passam pelo `SafeFetch`, que **bloqueia rede privada por default** | `enterprise/lib/captain/tools/http_tool.rb`, `app/jobs/avatar/avatar_from_url_job.rb` | vetor 1 |
| 1.5 | **DADO** | **Criar conta renomeia a conta sozinha** com o `<title>` do site do domínio do e-mail do admin | `app/jobs/account/branding_enrichment_job.rb` (NOVO) | vetor 1+3 |
| 1.6 | **RISCO** | O modelo default do Captain resolve por `Llm::FeatureRouter` e vira `gpt-5.2` fixo — alcance **maior** do que o A2 §3.2 declarou | `lib/llm/feature_router.rb` (NOVO) | vetor 1 |
| 1.7 | **RISCO** | FAQ de conversa deixa de entrar na base e vira **sugestão pendente de aprovação** | `enterprise/app/services/captain/llm/conversation_faq_service.rb` | vetor 1 |
| 1.8 | **RISCO** | Auto-atribuição periódica só cobre inbox com `assignment_policy`; o catch-up de inbox sem policy sumiu | `config/schedule.yml` + `AutoAssignment::PeriodicAssignmentJob` | vetor 3 |
| 1.9 | **RISCO médio** | Login com 25 sessões ativas passa a devolver **409 + picker** em vez de evictar em silêncio | `app/controllers/devise_overrides/sessions_controller.rb` (MOD) | vetor 4 |
| 1.10 | **RISCO baixo** | `content` do payload de webhook muda: `\`+newline vira newline, newline final é removido | `app/services/messages/webhook_content_normalizer.rb` (NOVO) | vetor 1 |
| 1.11 | **RISCO baixo** | `UpdateSlackMessageJob` volta a receber **objetos AR** por GlobalID, contra o hardening do commit `87095e111b` | `app/jobs/update_slack_message_job.rb` (NOVO) | vetor 1 |

---

### 1.1 — PERDA + DADO · **excluir conversa não exclui, e a API mente `200 OK`**

Este é o achado que a task previu no abstrato e que existe no concreto.

O upstream extraiu o `destroy` do controller para um service novo:

```ruby
# app/services/conversations/delete_service.rb  — NOVO, upstream-only, nunca revisado
::DeleteObjectJob.perform_later(conversation, user, ip)          # 3 args, OBJETOS
```

Mas `app/jobs/delete_object_job.rb` **não é upstream-only** — é nosso. O upstream não tocou nele
(`git diff BASE DELES -- app/jobs/delete_object_job.rb` → vazio) e o merge ficou com a nossa versão
(`git diff NOSSO MERGE` → vazio). E a nossa versão é o hardening do commit `87095e111b`:

```ruby
# app/jobs/delete_object_job.rb — NOSSO, sobreviveu ao merge
ALLOWED_OBJECT_TYPES = %w[Account Inbox Conversation Contact User AgentBot Label SlaPolicy CustomAttributeDefinition].freeze

def perform(object_type, object_id, user_id = nil, ip = nil)   # 4 args, STRINGS/IDs
  return unless ALLOWED_OBJECT_TYPES.include?(object_type)
  ...
```

O casamento é este:

| o service passa | o job recebe em | valor real |
|---|---|---|
| `conversation` | `object_type` | `#<Conversation id: 123>` |
| `user` | `object_id` | `#<User id: 4>` |
| `ip` | `user_id` | `"192.168.8.1"` |
| — | `ip` | `nil` |

`ALLOWED_OBJECT_TYPES.include?(#<Conversation>)` compara `String == Conversation` → **false** →
`return` na primeira linha. **O job termina com sucesso, sem exceção, sem log, sem nada.**

Efeito observável na frota:
- `DELETE /api/v1/accounts/:id/conversations/:id` responde `head :ok`;
- o front remove a conversa da lista;
- no próximo reload **ela volta**;
- não há erro no GlitchTip, porque não há erro — o job retorna `nil` normalmente;
- o `Enterprise::AuditLog` da exclusão (`process_post_deletion_tasks`) **também nunca é criado** →
  buraco de auditoria além do buraco funcional.

Os outros **7** chamadores do job em todo o merge usam a assinatura correta
(`agents_controller:116`, `inboxes_controller:94`, `super_admin/accounts_controller:78`,
`platform/.../users_controller:33`, `platform/.../accounts_controller:25`,
`account_deletion_service:16`, `enterprise/.../sla_policies_controller:20`). O service novo é o
**único** ponto divergente do merge inteiro.

**Correção proposta** — uma linha, em `app/services/conversations/delete_service.rb:6`:

```ruby
- ::DeleteObjectJob.perform_later(conversation, user, ip)
+ ::DeleteObjectJob.perform_later(conversation.class.name, conversation.id, user&.id, ip)
```

**Como provar antes e depois** (o aceite tem mecanismo, não é afirmação): num console de **teste**,
`Conversations::DeleteService.new(conversation: c, user: u, ip: '1.1.1.1').perform` seguido de
`perform_enqueued_jobs` e `expect(Conversation.exists?(c.id)).to be false`. Hoje esse expect falha.

> **Cruzamento obrigatório com a memória `reference_flows_fk_bloqueia_delete_conversa`:** depois de
> corrigida a assinatura, o `conversation.destroy!` volta a ser executado — e aí ele bate na FK sem
> cascade de `flow_runs`/`flow_step_logs`, levantando `ActiveRecord::InvalidForeignKey`. Antes o erro
> era síncrono e visível (500 na UI); agora será um job falhando com retry no Sidekiq. **Corrigir
> §1.1 sem corrigir a FK troca "some em silêncio" por "falha em loop no GlitchTip".** As duas
> correções têm de ir juntas.

---

### 1.2 — PERDA · **Instagram passa a exigir assinatura HMAC em todo webhook**

`app/controllers/webhooks/instagram_controller.rb` está em `so-deles.txt:71`. Upstream-only. Ganhou:

```ruby
before_action :verify_meta_signature!, only: :events
```

E **não sobrescreve** `meta_signature_verification_required?` — confirmado listando todos os `def` do
arquivo (`valid_token?`, `meta_app_secrets`, `instagram_channel_meta_app_secrets`,
`instagram_channels_from_payload`, `instagram_ids_from_entry`, `instagram_id_from_messaging`,
`contains_echo_event?`, `events`). Logo vale o default do concern:

```ruby
# app/controllers/concerns/meta_token_verify_concern.rb
def meta_signature_verification_required?
  true          # ← sempre
end

def verify_meta_signature!
  return unless meta_signature_verification_required?
  return if valid_meta_signature?
  head :unauthorized
end
```

`valid_meta_signature?` exige o header `X-Hub-Signature-256` **e** ao menos um secret não-branco em
`meta_app_secrets` = `[secrets do provider_config do canal, INSTAGRAM_APP_SECRET, FB_APP_SECRET]`.
Se nenhum estiver preenchido, `any?` sobre um array de brancos é `false` → **401**.

Na frota isso significa: **qualquer VM cujo GlobalConfig não tenha `FB_APP_SECRET` ou
`INSTAGRAM_APP_SECRET` preenchido para de receber DM do Instagram no instante do deploy.** A Meta
recebe 401, não reenvia indefinidamente, e **nada aparece no GlitchTip** — não é exceção, é um
`head :unauthorized` deliberado. O sintoma que o cliente reporta é "o Instagram parou", sem rastro.

**Correção proposta:** não relaxar o código (a verificação é correta e é uma melhoria de segurança
real). Isto vira **item de checklist de pré-deploy** — §2, linha `FB_APP_SECRET`. Para cada VM com
canal Instagram/Messenger ativo, confirmar antes do deploy:

```ruby
# console RAILS_ENV=production da VM, somente leitura
Channel::Instagram.count + Channel::FacebookPage.count
InstallationConfig.find_by(name: 'FB_APP_SECRET')&.value.present?
InstallationConfig.find_by(name: 'INSTAGRAM_APP_SECRET')&.value.present?
```

Se houver canal e nenhum secret → **preencher antes**, não depois.

---

### 1.3 — PERDA · **WhatsApp Cloud: 401 quando o canal não é resolvido**

Mesmo mecanismo, com uma guarda a mais. `app/controllers/webhooks/whatsapp_controller.rb`
(`so-deles.txt:72`) sobrescreve:

```ruby
def meta_signature_verification_required?
  return true if whatsapp_channel.blank?                              # ← (A)
  return false unless whatsapp_channel.provider == 'whatsapp_cloud'   # ← (B)
  return true if channel_meta_app_secrets(whatsapp_channel).present?  # ← (C)
  whatsapp_channel.provider_config['source'] == 'embedded_signup'     # ← (D)
end
```

Matriz para a frota:

| situação do canal | exige HMAC? | veredito |
|---|---|---|
| (B) provider `default` — 360dialog, e o caminho por onde WAHA/Evolution entram | não | **OK** |
| (D) `whatsapp_cloud` manual, sem app_secret no `provider_config` | não | **OK** |
| (C) `whatsapp_cloud` com `app_secret`/`client_secret`/`api_secret` no `provider_config` | sim | OK **se** o secret for o do app que a Meta usa para assinar |
| (D) `whatsapp_cloud` com `source: 'embedded_signup'` | sim | **RISCO**: se `WHATSAPP_APP_SECRET` estiver vazio no GlobalConfig → 401 permanente |
| **(A) canal não resolvido** | **sim** | **PERDA silenciosa** |

O caso (A) é o perigoso e é específico do nosso parque. `whatsapp_channel` resolve por
`whatsapp_business_payload_channel || Channel::Whatsapp.find_by(phone_number: params[:phone_number])`,
e o primeiro depende de `Whatsapp::WebhookChannelFinderService` casar `display_phone_number` **e**
`phone_number_id`. Isso cruza direto com a memória
`reference_wa_cloud_override_waba_vs_numero` (dois números no mesmo WABA, URL única, entrega
resolvida pelo payload) e com o 9º dígito brasileiro: **qualquer divergência de `phone_number_id`
entre o que a Meta manda e o que está salvo no `provider_config` faz o canal ficar `blank`** — e aí,
em vez do comportamento antigo (enfileira o job, que resolvia o canal por conta própria), o
controller devolve **401 e joga a mensagem fora**.

Note que `Channel::Whatsapp` **não tem** `app_secret` (não é coluna no `db/schema.rb` nem método no
modelo) — `respond_to?(:app_secret)` é `false`, então só o `provider_config` conta. Isso é o que
salva os casos (B)/(D) manuais.

**Correção proposta** — inverter a guarda (A), que hoje falha para o lado inseguro-para-o-negócio:

```ruby
- return true if whatsapp_channel.blank?
+ # Canal não resolvido: deixar o job resolver (ele tenta dígitos crus + normalizado, 9º dígito BR).
+ # Rejeitar aqui descarta a mensagem sem rastro — pior que aceitar e falhar visivelmente adiante.
+ return false if whatsapp_channel.blank?
```

E, independente disso, o item de checklist §2 para `WHATSAPP_APP_SECRET` nas VMs com embedded signup.

---

### 1.4 — RISCO alto · **`SafeFetch` bloqueia rede privada por default, e o alcance é maior que o de A1 §1.3**

A A1 achou o `SafeFetch` porque `lib/webhooks/trigger.rb` era colisão. Os arquivos que **definem** o
comportamento são upstream-only e nunca foram lidos: `lib/safe_fetch.rb`, `lib/safe_fetch/fetcher.rb`,
`lib/safe_fetch/private_network_request.rb`, `lib/safe_fetch/request_options.rb`.

```ruby
# lib/safe_fetch.rb
def self.allow_private_network?
  ActiveModel::Type::Boolean.new.cast(ENV.fetch('SAFE_FETCH_ALLOW_PRIVATE_NETWORK', false))
end
```

O cruzamento mecânico mostra **três** chamadores dentro de código nosso, não um:

| chamador | o que deixa de funcionar em rede privada |
|---|---|
| `lib/webhooks/trigger.rb` | webhook para host interno (já reportado em A1 §1.3) |
| **`enterprise/lib/captain/tools/http_tool.rb`** | **toda tool HTTP customizada do Captain que aponte para IP/host privado** — ERP do cliente na LAN, n8n interno, receptor SPX, MCP `chatspx-tools` |
| `app/jobs/avatar/avatar_from_url_job.rb` | avatar por URL servido de storage interno (MinIO/local) |

O `http_tool.rb` é o que dói: é a porta pela qual os agentes IA da frota falam com os sistemas do
cliente. O erro chega como `SafeFetch::UnsafeUrlError`, que o `http_tool` não distingue de um 500 do
outro lado — a IA responde "não consegui consultar" e ninguém sabe por quê.

**Correção proposta:** `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` no `.env` de **toda VM da frota**, como
item de pré-deploy (§2). É restauração de comportamento, não afrouxamento: era assim antes do merge.
Onde se quiser manter o hardening, a alternativa é uma allowlist explícita de hosts — mas isso é
trabalho de produto, não de merge, e não deve bloquear a onda.

---

### 1.5 — DADO · **criar conta renomeia a conta sozinha**

`app/jobs/account/branding_enrichment_job.rb` é NOVO e é enfileirado incondicionalmente no
`create` do controller de contas — **inclusive no "adicionar conta" do dashboard**:

```ruby
# app/controllers/api/v1/accounts_controller.rb:37-46
def create
  @user, @account = AccountBuilder.new(...).perform
  enqueue_branding_enrichment          # ← sem guarda de ambiente, plano ou flag
```

```ruby
# app/jobs/account/branding_enrichment_job.rb
result = WebsiteBrandingService.new(email).perform
account.name = result[:title] if result[:title].present?     # ← sobrescreve o nome digitado
account.custom_attributes['brand_info'] = result if ...blank?
account.save! if account.changed?
```

E `WebsiteBrandingService` faz `SafeFetch.fetch("https://#{domínio do e-mail do admin}")` e faz scrape
do `<title>`. Ou seja: criar a conta "Cliente Fulano" com o e-mail do admin em `@gmail.com` **dispara
um request para `https://gmail.com`** e pode renomear a conta para o que estiver no `<title>` da
página. Não há guarda de "só se o nome estiver em branco".

Ainda mexe em `custom_attributes['onboarding_step']` (`'enrichment'` → `'account_details'`) e faz
broadcast ActionCable `account.enrichment_completed` — um fluxo de onboarding do Chatwoot Cloud que a
frota não usa.

**Correção proposta:** remover a chamada `enqueue_branding_enrichment` do `create` (é um comportamento
de SaaS público, não de instalação self-hosted white-label), **ou** — se quiser manter para o SaaS
Hostinger — condicioná-la a `ChatwootApp.chatwoot_cloud?` e proteger o nome:

```ruby
- account.name = result[:title] if result[:title].present?
+ account.name = result[:title] if result[:title].present? && account.name.blank?
```

Escolha do dono do produto; recomendo remover a chamada, que é o menor delta.

---

### 1.6 — RISCO · **`Llm::FeatureRouter` alcança mais superfície do que o A2 §3.2 declarou**

O A2 §3.2 já reportou que `enterprise/app/models/concerns/agentable.rb` resolve o modelo do agente por
`Llm::FeatureRouter` e que, com `captain_integration_v2` ligada, cai em
`CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'` sem fallback. **Não repito o achado.** O que acrescento é o
alcance, que o cruzamento mecânico revelou: o router (arquivo NOVO, upstream-only) é chamado de
**11 pontos**, e um deles é `app/models/concerns/captain_featurable.rb` — que o A2 não cobriu por ser
`app/`, não `enterprise/`:

```ruby
# NOSSO (f26db6ee81)                          # MERGE
def captain_models_with_defaults              def captain_models_with_defaults
  ...                                           Llm::Models.feature_keys.index_with do |k|
  Llm::Models.default_model_for(feature_key)      Llm::FeatureRouter.resolve(feature: k, account: self)[:model]
end                                           end
```

`captain_models_with_defaults` alimenta `captain_preferences`, que é **o que a tela de Preferências do
Captain mostra ao usuário**, e os métodos `captain_<feature>_model` usados por
`lib/captain/base_task_service.rb`. Consequência: com `captain_integration_v2: enabled: true` no nosso
`config/features.yml` (nós ligamos; na BASE era `false`), **toda conta sem override explícito vê e usa
`gpt-5.2` como modelo do assistente**, e não o `gpt-4.1` do `llm.yml` nem o `gpt-5-mini` que nós
tínhamos escolhido (A2 §3.4).

Um risco secundário que investiguei e **descarto**: `validate_captain_models` deixou de fazer
`next if model_name.blank?`, o que faria conta com `captain_models: {"assistant" => ""}` parar de
salvar. Mas o upstream adicionou `before_validation :normalize_captain_models`, que remove os brancos
antes da validação. **Não é problema.**

**Correção proposta:** casada com a de A2 §C-13. O ponto mínimo é fazer o hardcode respeitar a
disponibilidade real, em `lib/llm/feature_router.rb`:

```ruby
- CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'.freeze
+ # Só usa o modelo v2 se a chave da instalação realmente tem acesso a ele.
+ def captain_v2_assistant_model(account, feature_key)
+   ...
+   Llm::Models.first_runtime_supported(CAPTAIN_V2_ASSISTANT_MODEL, Llm::Models.default_model_for(feature_key))
```

---

### 1.7 — RISCO · **FAQ de conversa vira sugestão pendente em vez de entrar na base**

`enterprise/app/listeners/captain_listener.rb` (colisão bem resolvida: manteve nosso comentário pt-BR
do `assistant_for`) trocou a chamada síncrona por um job novo:

```diff
- Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate
+ Captain::Llm::ConversationFaqJob.perform_later(conversation, assistant)
```

E o job chama `generate_suggestions`. O método `generate_and_deduplicate` **não existe mais em lugar
nenhum do merge** (grep em `app lib enterprise` → zero). O fluxo novo grava em
`captain_faq_suggestions` (`status: open`) e espera aprovação humana.

Efeito na frota: **a base de conhecimento dos agentes IA para de crescer sozinha.** Para a Clara Tozi,
que é o piloto, isso é mudança de produto, não de código.

Verifiquei que a UI existe e veio no merge — `app/javascript/dashboard/api/captain/faqSuggestions.js`,
`components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue`, `KnowledgeCard.vue`,
`CoverageBanner.vue`. Então não é PERDA, é RISCO de produto: **alguém precisa saber que agora tem uma
fila de aprovação, senão ela acumula sem ninguém olhar.** Registrar como item de release notes e
confirmar com a área do dashboard que a tela está acessível no redesenho.

A2 §4.6 tratou do contrato do spec desse listener; este é o efeito de produto do mesmo commit.

---

### 1.8 — RISCO · **catch-up de auto-atribuição encolheu**

O upstream removeu `bulk_auto_assignment_job` do `config/schedule.yml` e ainda o **destrói do Redis**
explicitamente (§3.2). A2 §4.7 concluiu, corretamente, que a garantia "auto-assignment não rouba
conversa do mirror bot" migrou para o motor novo. O que acrescento é a diferença de **cobertura** dos
dois jobs, que não é equivalente:

| | `Inboxes::BulkAutoAssignmentJob` (removido) | `AutoAssignment::PeriodicAssignmentJob` (fica) |
|---|---|---|
| cadência | 15 min | **30 min** |
| escopo de conta | `Account.feature_assignment_v2` | `account.feature_enabled?('assignment_v2')` (igual) |
| **escopo de inbox** | `inboxes.where(enable_auto_assignment: true)` | **`inboxes.joins(:assignment_policy)`** + `auto_assignment_v2_enabled?` |

**Inbox com `enable_auto_assignment: true` mas sem `assignment_policy` deixa de ter catch-up.** A
atribuição no momento da criação da conversa continua funcionando; o que some é a varredura que pegava
conversa que ficou órfã (agente saiu, capacidade liberou depois).

**Correção proposta:** nenhuma no código. É item de verificação de dados, por VM, antes do deploy:

```ruby
# leitura, console RAILS_ENV=production da VM
Account.all.select { |a| a.feature_enabled?('assignment_v2') }.flat_map { |a|
  a.inboxes.where(enable_auto_assignment: true).left_joins(:assignment_policy)
   .where(assignment_policies: { id: nil }).pluck(:id, :name)
}
```

Lista não-vazia = inboxes que perdem o catch-up. Ou se cria `assignment_policy` para elas, ou se
aceita a perda conscientemente.

---

### 1.9 a 1.11 — riscos menores, uma leitura cada

**1.9 · 409 no login.** `sessions_controller.rb` (MOD, 129 linhas de diff) introduziu
`MAX_SESSIONS = ENV.fetch('MAX_USER_SESSIONS', 25)` — o mesmo valor de
`config.max_number_of_devices = 25` já existente. Quando o limite é atingido **e** é requisição de
browser **e** `user.user_sessions.count >= user.tokens.size`, o login devolve **409 com um picker de
sessões a revogar** em vez de evictar a mais antiga em silêncio. O efeito é diferido: `user_sessions`
é tabela nova, começa vazia, então nas primeiras semanas a condição `>= tokens.size` é falsa e o
comportamento antigo (evicção silenciosa) prevalece. Depois disso, agente com 25 tokens ativos vê o
409. **Se o front do redesenho não tratar 409 nesse endpoint, ele não loga.** → verificar com a área
do dashboard; não é correção de backend.

**1.10 · payload de webhook.** `Messages::WebhookContentNormalizer.normalize` passa a ser aplicado em
`Message#webhook_push_event_data` (campos `content` e `processed_message_content`) e em
`MessageContentPresenter#webhook_content`. Faz `gsub(/\\\r?\n/, "\n")` e `sub(/(\r?\n)+\z/, '')`.
É melhoria (tira a contrabarra do CommonMark que vazava para gateways de WhatsApp), mas **muda o
payload que n8n/Automações/WAHA recebem**: mensagens perdem o(s) newline(s) finais. Qualquer
comparação exata de string do lado consumidor precisa saber disso. Sem correção; é nota de contrato.

**1.11 · GlobalID de volta no Slack.** `UpdateSlackMessageJob.perform_later(message, hook)` passa
objetos AR, enquanto o `SendOnSlackJob` ao lado, no mesmo método, passa `message.id, hook.id`. Não
quebra (ambos são GlobalID-serializáveis), mas é uma regressão pontual do hardening do commit
`87095e111b`, e só se manifesta se a integração Slack estiver ativa. Correção de uma linha, baixa
prioridade.

---

## 2. Variáveis de ambiente novas — **checklist de pré-deploy da frota**

Método: extração léxica de `ENV.fetch(...)` / `ENV[...]` nas três árvores (BASE, NOSSO, MERGE) e
diferença de conjuntos, para separar ENV nova-do-upstream de ENV nossa. A primeira passada usou grep
por linha e **perdeu** um caso — `ENV.fetch(` com o nome da variável na linha seguinte. Refiz com
`tr '\n' ' '` por arquivo antes do grep; a segunda passada achou
`RATE_LIMIT_REPORTS_DRILLDOWN_API_USER_LEVEL`, que a primeira não via. **Os números da tabela abaixo
são os da segunda passada** (merge 158 · BASE 111 · NOSSO 142 nomes distintos).

As novas do merge foram separadas em **nossas** (`WAHA_*`, `FLOW_*`, `CHATSPX_*`, `TOZI_*`, `SPX_*`,
`CHROMIUM_PATH`… — já provisionadas) e **do upstream** (16). Dessas 16, oito são argumentos de rake
task (`CSV_INPUT`, `IDS`, `LIMIT`, `INPUT`, `OUTPUT`, `STATUS`, `FROM`, `TO`), uma é de rake de
storage (`UPDATE_BLOB_SERVICE_NAME`) e uma é de ambiente de desenvolvimento
(`ANNOTATERB_SKIP_ON_DB_TASKS`) — nenhuma delas decide comportamento em produção.

Sobram **6 que decidem comportamento em runtime**, e **nenhuma das 6 está no `.env.example`**
(verificado uma a uma com `grep -c` no arquivo). Esta é a tabela que vira checklist:

| variável | default no código | efeito na frota **com ela ausente** | ação | prioridade |
|---|---|---|---|---|
| **`SAFE_FETCH_ALLOW_PRIVATE_NETWORK`** | `false` (`lib/safe_fetch.rb:39`) | **Quebra**: webhook para host interno, **tool HTTP do Captain para IP privado** e avatar de storage interno passam a levantar `SafeFetch::UnsafeUrlError`. Era permitido antes do merge | **`=true` em toda VM** (§1.4) | **P0** |
| **`MAX_USER_SESSIONS`** | `25` (`sessions_controller.rb:2`) | Login de usuário com 25 sessões ativas pode devolver **409 + picker** em vez de evictar (§1.9). Ausente = 25, igual a `max_number_of_devices` | não setar; **validar o front** | P2 |
| **`RATE_LIMIT_CONVERSATION_DELETE`** | `'60'` / 1 min (`rack_attack.rb:225`) | Limpeza em massa de conversas (>60/min por conta) passa a tomar **429**. Fica atrás de §1.1 na fila: hoje o delete nem funciona | setar só se houver rotina de limpeza | P3 |
| **`RATE_LIMIT_AGENT_CREATE`** | `'100'` / 1 dia (`rack_attack.rb:234`) | Onboarding em massa / import de agentes acima de 100/dia toma **429** | setar em VM com import grande | P3 |
| **`RATE_LIMIT_AGENT_DELETE`** | `'50'` / 1 dia (`rack_attack.rb:243`) | Idem, para remoção | idem | P3 |
| **`RATE_LIMIT_REPORTS_DRILLDOWN_API_USER_LEVEL`** | **`max(RATE_LIMIT_REPORTS_API_USER_LEVEL / 10, 1)` = `10`** / 1 min (`rack_attack.rb:263`) | Endpoint novo `/api/v2/.../reports/drilldown`. **10 req/min por usuário é apertado** para quem explora relatórios clicando métrica a métrica → **429** | subir para `50` se a tela de relatórios usar drilldown | **P2** |

> `RATE_LIMIT_REPORTS_API_USER_LEVEL` **não** entra nesta tabela: verifiquei que ela já existia na
> BASE (`base-tree/config/initializers/rack_attack.rb:207`, mesmo default `'100'`). O que é novo é a
> variável **derivada** dela, acima — e é a derivação (`/10`) que produz um limite baixo sem ninguém
> ter escolhido o número.

**Não são ENV, mas são o mesmo tipo de item — configuração ausente que quebra caminho vivo.** Estas
vêm do `InstallationConfig` (GlobalConfig), não do `.env`, e por isso escapam de qualquer grep de
`.env.example`. **Pertencem ao mesmo checklist:**

| chave (GlobalConfig) | efeito com ela ausente | prioridade |
|---|---|---|
| **`FB_APP_SECRET`** / **`INSTAGRAM_APP_SECRET`** | **401 em 100% dos webhooks do Instagram** (§1.2). Silencioso: não gera exceção | **P0**, em toda VM com canal IG/Messenger |
| **`WHATSAPP_APP_SECRET`** | **401 nos webhooks** de canal `whatsapp_cloud` com `source: embedded_signup` (§1.3) | **P0**, em toda VM com embedded signup |

E uma que **já existia** mas cujo significado mudou:

| variável | mudança | efeito |
|---|---|---|
| `FORCE_SSL` | passou a decidir também o flag `secure:` do cookie de sessão (`config/initializers/session_store.rb`) | Só afeta o dashboard `super_admin` (sessão não é usada para auth de API). Com `FORCE_SSL` ausente numa VM servida por HTTPS via nginx, o cookie do super_admin fica sem `secure` — endurecimento perdido, nada quebra. **P3** |

> **Formato sugerido para o `.env` da frota** (bloco a colar, P0 apenas):
> ```
> # v4.16.2 — restaura o comportamento de rede interna que o SafeFetch passou a bloquear
> SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true
> ```
> As duas linhas de GlobalConfig não vão no `.env`: são registro em `installation_configs`, feito
> pela tela de super_admin ou por `InstallationConfig.create!`.

---

## 3. O que age sozinho: initializers, crons e jobs sem chamador humano

Os 7 `config/initializers/*` upstream-only foram lidos por inteiro. `config/schedule.yml` foi diffado
NOSSO→MERGE. Os 27 jobs novos foram rastreados até quem os enfileira.

### 3.1 Initializers — veredito de cada um

| arquivo | classe | o que faz sozinho | veredito |
|---|---|---|---|
| `active_storage.rb` | NOVO | libera `Content-Disposition: inline` para 7 MIMEs de áudio (player in-app de gravação/voice note) e limita range-request de proxy a **1 range < 100MB** (`head :range_not_satisfiable` acima disso) | **OK / ganho.** O limite só rejeita multi-range, que nenhum player usa |
| `acts_as_taggable_on.rb` | NOVO | `ActsAsTaggableOn.tags_counter = false` — desliga o counter cache de `tags.taggings_count` para evitar deadlock em escrita paralela de label (INF-68) | **OK.** Verifiquei: `taggings_count` não é lido em lugar nenhum de `app/ lib/ enterprise/ app/javascript/` — só existe como coluna em `db/schema.rb:2107`. A coluna passa a ficar desatualizada, e ninguém a consulta |
| `i18n_pluralization.rb` | NOVO | regra de plural `:other` para `zh_CN`/`zh_TW` | **dormente** (frota é pt-BR) |
| `sidekiq.rb` | MOD | **ver §3.2** | **RISCO — o único que age destrutivamente** |
| `session_store.rb` | MOD | `secure:` do cookie passa a seguir `FORCE_SSL`; `httponly: true` | OK, §2 |
| `facebook_messenger.rb` | MOD | `app_secret_for(page_id)` passa a procurar o secret **no canal** antes do `FB_APP_SECRET` global | **ganho** — e é a mesma família do §1.2 |
| `languages.rb` | MOD | acrescenta `41 => et`, `42 => uz` ao `LANGUAGES_CONFIG` | OK — **não desloca** `pt_BR = 16`, os índices existentes ficam intocados |

### 3.2 `config/initializers/sidekiq.rb` — o cron loader passou a **apagar** jobs do Redis

```diff
- Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file) if ...
+ %w[bulk_auto_assignment_job].each { |name| Sidekiq::Cron::Job.destroy(name) }
+ Sidekiq::Cron::Job.load_from_hash!(schedule, source: 'schedule')
```

Duas mudanças, uma benigna e uma que exige verificação:

- **`Sidekiq::Cron::Job.destroy('bulk_auto_assignment_job')`** roda **em todo boot do Sidekiq server**.
  É deliberado do upstream (par do §1.8). Não afeta nenhum cron nosso.
- **`load_from_hash!` com `source: 'schedule'`** passa a **remover do Redis** todo cron com esse
  mesmo source tag que não esteja mais no YAML. Investiguei o risco de isso apagar cron nosso e
  **descarto**: `grep -rn 'Sidekiq::Cron' app lib config enterprise` retorna **apenas as duas linhas
  do próprio initializer** — o ChatSPX não registra nenhum cron dinamicamente fora do `schedule.yml`.
  E os nossos continuam no YAML, verificado no diff NOSSO→MERGE: `conversations_orphan_watch_job`
  (vigia de órfãs D-12), o refresh de grupos WAHA de 30 em 30 min e o purge de bulk media
  **sobreviveram**. O único delta do arquivo é `-bulk_auto_assignment_job` e
  `+trigger_hourly_scheduled_items_job`.

**Veredito: OK, com uma verificação de uma linha no primeiro deploy** — depois de subir, conferir no
Sidekiq Web (`/sidekiq/cron`) que os três crons SPX seguem listados. É o tipo de coisa que só se vê
uma vez.

### 3.3 Jobs novos que rodam sem ninguém pedir

| job | quem dispara | efeito autônomo | veredito |
|---|---|---|---|
| **`Internal::TriggerHourlyScheduledItemsJob`** | **cron novo `0 * * * *`** | único conteúdo: `Channels::Whatsapp::HealthSyncSchedulerJob.perform_later` | ver linha abaixo |
| `Channels::Whatsapp::HealthSyncSchedulerJob` | o job acima, **de hora em hora** | seleciona até `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT = 25` canais **`provider: 'whatsapp_cloud'`** de conta ativa, não checados há 6h, e enfileira um `HealthSyncJob` por canal → **chamada à Graph API da Meta** | **RISCO baixo.** Filtra por `whatsapp_cloud`, então **não toca canais WAHA/Evolution** (que entram como `provider: 'default'` — `PROVIDERS = %w[default whatsapp_cloud]`, idêntico em NOSSO e MERGE). `HealthSyncJob` faz `rescue ApiError, ArgumentError → nil`, então token expirado não vira ruído no GlitchTip. **Tráfego externo novo, silencioso, aceitável** |
| `Enterprise::Internal::TriggerDailyScheduledItemsJob` | cron diário existente | acrescenta `Captain::Documents::ScheduleSyncsJob` para `enterprise` (diário), `business` (domingos) e `startups` (dia 1º) | **dormente** na frota: são planos de Cloud; instalação self-hosted não tem esses `plan_name` |
| **`Migration::ValidateOpenaiHooksJob`** | `db/migrate/20260515000000_enqueue_validate_openai_hooks_job.rb` | percorre `Integrations::Hook` com `app_id: 'openai'`, valida a chave contra a OpenAI e **`hook.destroy!`** os inválidos, mandando e-mail ao admin | **DADO — já reportado por A2 §2.3.** Confirmo pelo meu lado: o job existe no merge e o único chamador é a migration. Correção é responsabilidade de A2; não duplico |
| `UserSessionIpLookupJob` | `UserSessionTrackingService`, **a cada login** | geolocaliza o IP da sessão | **OK.** `IpLookupService` usa `Geocoder.search` com base **local** e faz `return if !ip_database_available?` (`File.exist?(GeocoderConfiguration::LOOK_UP_DB)`). Sem a base MaxMind na VM, não faz nada e não chama ninguém |
| **`Account::BrandingEnrichmentJob`** | `accounts_controller#create` | **§1.5** | **DADO** |
| `Labels::RemoveAssociationsJob` | `labels_controller#destroy` | passa a limpar as associações da label em background depois do `destroy!` | **OK / ganho** — o `destroy` já era síncrono; o fan-out saiu do request |
| `Captain::Llm::ConversationFaqJob` | `CaptainListener#conversation_resolved` | **§1.7** | RISCO de produto |
| `Captain::Documents::PerformSyncJob` | `documents_controller` + o scheduler acima | sync de documento do Captain | dormente/OK |
| `Companies::SyncContactNamesJob`, `Companies::DeleteJob` | callbacks de `Company` (EE) | feature Companies, nova | dormente — a frota não usa Companies |
| `Onboarding::HelpCenterArticle{Generation,Writer}Job` | fluxo de onboarding Cloud | dormente |
| `Voice::Provider::Twilio::RecordingAttachmentJob` | canal Voice | dormente — não temos canal Voice |
| `DataImports::Intercom::*` (4 jobs) | import manual de Intercom | dormente |
| `Captain::Articles::TranslateJob` | ação manual na UI | dormente |
| ~~`Enterprise::Webhooks::WhatsappEventsJob`~~ | — | **não existe no merge** — ver §3.4 |
| `Captain::Conversation::{MessageBuilder,V1ActionClassifier,V1FalsePromiseHandler}` | `response_builder_job.rb` | decomposição interna do responder do Captain | A2 §3.7 tratou o `response_builder_job`; nada a acrescentar |
| `Conversations::UnreadCounts::Listener` | **registrado no NOSSO `app/dispatchers/async_dispatcher.rb`** — roda em `message_created`, `conversation_updated`, `assignee_changed`, `team_changed`, `conversation_status_changed`, `conversation_contact_changed`, `conversation_mentioned`, `conversation_deleted` | mantém contadores de não-lidas em Redis | **RISCO condicionado — ver abaixo** |

**`Conversations::UnreadCounts::Listener`** merece parágrafo porque está no nosso dispatcher e é o
listener de maior fan-out do merge: oito eventos, todos no caminho quente. Li-o inteiro. Todo caminho
de trabalho é gated por `account.feature_enabled?('conversation_unread_counts')` ou pelo flag do
`FilteredCountInvalidator`, com `return unless` na primeira linha — **com as duas flags desligadas ele
é praticamente inerte** (sobra o `filtered_count_invalidator(...).conversation_changed!` de
`conversation_deleted`, um `DEL` no Redis).

O risco não está no listener, está em **quem liga a flag**: A1 §1.2 já avisou que as migrations
`repurpose_channel_twitter_flag_for_conversation_unread_counts` e
`repurpose_quoted_email_reply_flag_for_unread_count_for_filters` **reaproveitam bits já usados** — conta
da frota com `channel_twitter` ou `quoted_email_reply` ligados acorda com
`conversation_unread_counts` ligada sem ninguém ter pedido, e este listener passa a rodar em cada
mensagem. **É a mesma verificação que A2 PARTE 1 já colocou na fila**; registro aqui apenas o
consumidor, que é novo e é nosso ponto de entrada.

### 3.4 Teste de integridade: os **29 arquivos que o upstream tem e o merge não trouxe**

Não estava no roteiro da task, mas sai de graça do mesmo cruzamento e é o complemento exato dele: se
a pergunta é "o que entrou sem ninguém ver", a irmã dela é "o que **não** entrou sem ninguém ver".
Para cada um dos 645 upstream-only, perguntei se o arquivo existe no MERGE; para os que não existem,
se existem em `70e284a044`.

**34 ausentes do merge · 29 deles existem em DELES · e os 29 são a mesma feature:**
`WhatsApp Calls` + `Call` model (`calls_controller`, `whatsapp_calls_controller`, `call_finder`,
`models/call.rb`, `whatsapp/{call_service,incoming_call_service,call_conversation_builder,
call_permission_request_service,call_permission_reply_service,inbound_call_identity_builder}.rb`,
`voice/{recording_status_service,provider/twilio/recording_attachment_*}`,
`twilio/voice_teardown_service.rb`, `lib/voice/call_errors.rb`,
`lib/custom_exceptions/call_already_accepted.rb`, os 9 jbuilders de `calls`/`whatsapp_calls`,
`enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb`,
`enterprise/app/jobs/enterprise/webhooks/whatsapp_events_job.rb`,
`enterprise/app/models/enterprise/channel/twilio_sms.rb`, `enterprise/app/finders/enterprise/message_finder.rb`).

Isso é **coerente e deliberado** — casa com A2 §2.0 (`drop_channel_voice` confirmado ausente, "o merge
acertou"). O que eu fiz foi verificar se o descarte foi **limpo**, porque descarte parcial é como se
quebra um boot. Resultado:

| verificação | resultado |
|---|---|
| referências remanescentes a `CallFinder`, `Voice::CallErrors`, `CustomExceptions::CallAlreadyAccepted`, `Whatsapp::CallService`, `Whatsapp::IncomingCallService`, `RecordingStatusService`, `VoiceTeardownService` em `app lib enterprise config` | **0 arquivos, para todas as 7** |
| referências ao model `Call` em `app/models` + `enterprise/app/models` | **0** |
| rotas órfãs em `config/routes.rb` | **0** — a única rota de chamada (`:363`, `post :call ... to: 'calls#create'`) resolve para `enterprise/app/controllers/api/v1/accounts/contacts/calls_controller.rb`, que **existe**, e cujas dependências (`Voice::OutboundCallBuilder`, `Channel::Voice`) também existem |
| o override EE perdido do WhatsApp Cloud continha caminho de **mensagem**? | **não** — li a versão de DELES: são só `pre_accept_call`, `accept_call`, `reject_call`, `terminate_call`, `initiate_call`, `send_call_permission_request`. Nada do envio/recebimento de mensagem |
| o `Enterprise::Webhooks::WhatsappEventsJob` perdido interceptava o inbound? | **só o de chamada** — `handle_message_events` faz `return handle_call_events(...) if call_event?` e cai em `super` para tudo o mais. E o job base do merge **não tem** `prepend_mod_with`, então nem seria carregado |

**Os outros 5 ausentes** não existem nem em DELES — foram **deletados pelo upstream**, e verifiquei
os dois que podiam doer:
- `app/controllers/api/v1/accounts/working_hours_controller.rb`: sem rota no merge, e horário de
  atendimento segue gerenciado por `inboxes_controller` + `app/models/working_hour.rb` +
  `out_of_offisable.rb`, todos presentes. **Sem perda.**
- `app/services/whatsapp/token_validation_service.rb`: **existia em NOSSO** e tinha exatamente **um**
  chamador (`whatsapp/embedded_signup_service.rb:43`). No merge esse mesmo ponto chama
  `Whatsapp::HealthService.new(channel).fetch_health_status`. Migração completa, zero órfão. **Sem perda.**
- Os 3 restantes (`v2/reports/timeseries/count_report_builder.rb`,
  `enterprise/.../companies/_company.json.jbuilder`, `lib/tasks/auto_annotate_models.rake`) são
  refactor de relatório, feature dormente e rake de desenvolvimento.

**Veredito da §3.4: o merge descartou a feature de chamadas por inteiro e sem deixar resíduo.** É o
único bloco grande deste relatório em que a resposta é "está certo".

### 3.5 `Featurable` — o que eu ia reportar e por que não reporto

`app/models/concerns/featurable.rb` (MOD) foi reescrito: `FEATURES` (índice global sequencial) virou
`FEATURES_BY_COLUMN`, com `FEATURE_FLAG_COLUMNS = ['feature_flags', 'feature_flags_ext_1']`,
agrupamento por `column:` do `features.yml`, reindexação **dentro de cada coluna** e
`MAX_FEATURES_PER_COLUMN = 63` com `raise ArgumentError` no load da classe.

Dado o que a memória `reference_feature_flags_bit_64_ingravavel` registra (65 entradas em 63 bits),
persegui isso como **trava de boot**. Verifiquei por parse real do YAML do merge:

```
total features no MERGE: 77   →   feature_flags: 63   ·   feature_flags_ext_1: 14
```

63 ≤ 63 e 14 ≤ 63 → **não levanta**. A coluna `feature_flags_ext_1` existe em `db/schema.rb:87`.
Também confirmei que a constante removida `Featurable::FEATURES` **não é referenciada** em nenhum
lugar de `app/ lib/ enterprise/ spec/` (nenhum `NameError` latente). **Sem achado meu.**

O remapeamento de bits que essa reindexação implica é exatamente o objeto da **PARTE 1 do A2**
(§1.1 mapa de bits nas 4 versões, §1.2 os seis `repurpose_*`, §1.4 o bug de nome na migration do
`feature_flags_ext_1`). Fica lá, não aqui.

---

## 4. COBERTURA — o que foi julgado e o que ficou de fora, nominalmente

### 4.1 Julgado

| conjunto | qtde | como |
|---|---:|---|
| `config/initializers/*` upstream-only | **7 / 7** | lidos integralmente (§3.1) |
| `config/` não-locale, não-initializer | **3 / 3** | `app.yml` (só `version: 4.12.1→4.16.2`), `markdown_embeds.yml` (só `+guidejar`), `llm_models.json` (1.253 modelos; NOVO, consumido por `Llm::Models`/`ruby_llm` — não é lido pelo `llm.yml`, que é a fonte de verdade dos defaults; ver A2 §3.4) |
| `config/schedule.yml` | 1 | diffado NOSSO→MERGE, linha a linha (§3.2) |
| `lib/` upstream-only | **49 / 49** classificados; **19** lidos | os 4 do `SafeFetch`, `llm/feature_router.rb`, `llm/models.rb`, `llm/exception_trackable.rb`, `captain/overview_summary_service.rb`, `integrations/slack/{emoji_formatter,update_slack_message_service}.rb`, `integrations/linear/auto_link_service.rb`, `integrations/openai/key_validator.rb`, `custom_exceptions/*` (3), `active_storage/migrator.rb`, e as 5 rake tasks novas |
| `.rb` novos do upstream cruzados com código nosso | **62 / 62** | todos os acertos do cruzamento mecânico foram abertos |
| Modificados com sinal de risco | **38 / 38** | grep dirigido no diff `BASE→MERGE`, todos lidos |
| Jobs novos (`app/` + `enterprise/`) | **27 / 27** | rastreados até o enfileirador (§3.3) |
| ENV novas | **46 / 46** | classificadas nossas × upstream em duas passadas (a 2ª robusta a quebra de linha); as 6 de runtime detalhadas (§2) |
| Chaves de GlobalConfig recém-exigidas | 3 | `FB_APP_SECRET`, `INSTAGRAM_APP_SECRET`, `WHATSAPP_APP_SECRET` (§2) |
| **Integridade referencial dos ausentes** | **34 / 34** | §3.4 — 29 existem em DELES e não no merge (feature de chamadas, descarte limpo verificado); 5 foram deletados pelo próprio upstream, os 2 que podiam doer verificados um a um |
| **Amostragem dirigida** dos novos de `app/services` + `app/jobs` **não cruzados** | 43 no pool; **9 já julgados** em §1/§3, **6 amostrados**, 28 declarados dormentes por família | ver §4.2 |

**Total julgado com rigor: ~210 arquivos** dos 645.

**Resultado da amostragem dirigida (§4.1, última linha) — vale mais que a contagem:**

Amostrei 6 do pool de 43 escolhendo pelo critério "pode tocar caminho quente", não por sorteio. Dois
deles mudaram a conclusão da amostra, e para melhor:

- **`app/services/whatsapp/identifier_sync_service.rb`** e **`app/services/contact_inbox_source_id_resolver.rb`**
  são NOVOS e não apareceram no cruzamento — mas são chamados por
  `whatsapp/incoming_message_identifier_helper.rb`, que **é** um dos 62 cruzados. Ou seja: estão no
  caminho de **inbound de WhatsApp**, o mais quente da frota, a dois saltos do nosso código.
  Persegui a regressão brasileira mais óbvia — o `ContactInboxSourceIdResolver` cria o contact_inbox
  com `normalized_source_ids.first`, então **qual é o primeiro?** Resposta:
  `incoming_message_source_ids` monta `[whatsapp_phone_source_id(...), whatsapp_source_id(user_id),
  whatsapp_source_id(parent_user_id)]`, e `whatsapp_phone_source_id` faz `processed_waid(phone_number)`.
  **O 9º dígito BR é aplicado antes de virar `source_id`, e o waid processado é o primeiro da lista.**
  Confere com A1 §1.1: **sem regressão.**
- `app/services/onboarding/web_widget_creation_service.rb`: chamado só por
  `onboardings_controller:68` (fluxo de onboarding do Cloud). Dormente.
- `app/services/twilio/{referral_params_helper,whatsapp_identifier_helper}.rb`: canal Twilio, dormente.
- `app/services/imap/deleted_message_tracker.rb`: já entrou pela porta do §1.1 (é a primeira linha do
  `Conversations::DeleteService`); note que **ele roda antes** do enfileiramento quebrado, então o
  tracking de e-mail apagado funciona mesmo hoje — só a exclusão não.

### 4.2 Ficou de fora — nominalmente, e por quê

| conjunto | qtde | por que ficou | risco de ter ficado |
|---|---:|---|---|
| `config/locales/*.yml` (`am ar az bg bn ca cs da de el es et fa fi fr he hi hr hu hy id is it ja ka ko lt lv ml ms ne nl no pl pt ro ru sh sk sl sq sr sv ta th tl tr uk ur ur_IN uz vi zh zh_CN zh_TW` + 9 `devise.*`) | **62** | idiomas que a frota não usa. `pt_BR` **não** está nessa lista (é colisão, coberta por A1) | **nulo** — exceto `config/locales/pt.yml` (Portugal), que não é o nosso `pt_BR` |
| Features que a frota não tem, fora de `views/`: `voice/**` (Twilio Voice), `billing`/`stripe`, `compan*` (Companies), `intercom`, `linear`, `dyte`/`realtime_kit` | **59** (conjunto único, `grep -E` no `backend-so-deles.txt` menos `views/`) | canal Voice, billing Stripe, Companies, Intercom, Linear e videochamada não existem na frota. **Amostragem executada** nos dois maiores diffs: `enterprise/app/models/channel/voice.rb` (122 linhas de diff — só `include Channelable` + `EDITABLE_ATTRS`, **nenhum `prepend_mod`** em modelo nosso) e `enterprise/app/services/voice/inbound_call_builder.rb` (124 linhas — cria Contact/Conversation próprios, chamado só pelo controller de voz). Confirmados autocontidos | **baixo** — dormentes por ausência de canal/plano |
| `app/views/**` (jbuilder de API e ERB de portal público) | **67** | mudam serialização de endpoints; a superfície de contrato JSON pertence à área do dashboard/front, que a consome | **médio** — declarado, não coberto. Um jbuilder que mude nome de campo quebra o front sem quebrar o Ruby |
| `enterprise/app/views/**` (mailers e views EE, incl. `devise/mailer/confirmation_instructions.html.erb`, 134 linhas de diff — o maior diff de view do merge) | **43** | templates de e-mail; o de `confirmation_instructions` foi rebrandado pelo upstream e **provavelmente reverte customização visual nossa** | **médio** — declarado. Vale um olhar da área de front/branding |
| Modificados **sem** sinal no grep dirigido | **234** | o grep cobre `def perform(`, callbacks, `validates`, `ENV`, `default:`, `perform_later`. Mudança de risco que não passe por nenhum desses padrões escapa | **baixo-médio** — é o limite honesto do método |
| Novos de `app/services`+`app/jobs` não cruzados e não amostrados, por família: `data_imports/intercom/**` (12), `conversations/unread_counts/**` infra (12: `builder`, `counter`, `filtered_counter`, `filtered_count_{instrumentation,snapshot_resolver,store,store_keys,version_cache}`, `filter_query_counter`, `refresher`, `store_keys`), + `contacts/bulk_remove_labels_service`, `notification/push_test_service`, `reports/raw_data_source`, `social_link_parser` | **28** | Intercom é dormente (não importamos de Intercom). A infra de `unread_counts` foi julgada **pelo consumidor** — o `Listener` no nosso dispatcher (§3.3), que é o único ponto de entrada e é gated por feature flag | **baixo** |
| `db/**` | 45 | fora de escopo por decisão da task | coberto por A2 §2 |

### 4.3 O que este relatório **não** faz

Não editei uma linha de código (auditoria), não rodei build, teste, migration nem install, e não
toquei o Puma da porta 3000. As correções propostas em §1 são diffs sugeridos, não aplicados. Os dois
mecanismos de verificação que proponho (o `expect` do §1.1 e as duas consultas de console do §1.2/§1.8)
**não foram executados** — a task proíbe rodar teste neste worktree, que está em uso por outro
executor. Estão escritos de forma a poderem ser executados por quem tiver o gate.

---

## 5. Resumo para o coordenador

Três coisas passariam para produção sem este relatório, e nenhuma delas gera exceção:

1. **Excluir conversa não exclui** e a API responde `200 OK` (§1.1). Causa: um arquivo novo do
   upstream (`conversations/delete_service.rb`) chama um job nosso com a assinatura antiga. Correção
   de uma linha — **mas tem de ir junto com a FK de `flow_runs`**, senão troca-se "some em silêncio"
   por "falha em loop".
2. **Instagram para de receber webhook** em qualquer VM sem `FB_APP_SECRET`/`INSTAGRAM_APP_SECRET`
   (§1.2), e **WhatsApp Cloud descarta mensagem** quando o canal não é resolvido pelo payload (§1.3).
   Ambos respondem `401`: nada no GlitchTip, nada no log de aplicação.
3. **`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=false`** é o default e derruba não só webhook interno, mas as
   **tools HTTP do Captain** — a porta pela qual os agentes IA falam com os sistemas do cliente (§1.4).

E uma quarta, de outra natureza: **criar conta renomeia a conta sozinha** com o `<title>` scrapeado do
domínio do e-mail do admin (§1.5) — comportamento de SaaS público que não deveria existir num
self-hosted white-label.

A §2 é o checklist de pré-deploy: **1 variável de `.env` (P0)** e **2 chaves de GlobalConfig (P0)**,
mais 4 itens P2/P3 de observação.

**O que este relatório desarma** (para o coordenador não gastar executor com isso):
- `Featurable` **não** trava o boot com o `MAX_FEATURES_PER_COLUMN = 63` — o `features.yml` do merge já
  vem particionado 63 + 14, e a constante removida `Featurable::FEATURES` não é referenciada em
  lugar nenhum (§3.5).
- O `load_from_hash!` do Sidekiq **não** apaga cron nosso — o ChatSPX não registra cron fora do
  `schedule.yml`, e os três crons SPX estão lá (§3.2).
- O descarte da feature de chamadas foi **limpo**: 29 arquivos ausentes, **zero** referência órfã,
  **zero** rota órfã (§3.4).
- O 9º dígito BR **sobreviveu** também no caminho novo de resolução de contact_inbox do WhatsApp
  (§4.2), que passa por dois services novos que o cruzamento inicial não pegou.

**O maior buraco que fica declarado:** os **110 arquivos de `views/`** (67 em `app/`, 43 em
`enterprise/`) que mudam serialização de API e templates de e-mail. São contrato com o front, não com
o Ruby — quebram sem levantar exceção, exatamente como os achados desta auditoria. Recomendo uma task
irmã da área de dashboard sobre esse conjunto, com atenção especial a
`enterprise/app/views/devise/mailer/confirmation_instructions.html.erb` (134 linhas de diff, o maior
do merge em views, e candidato a ter revertido branding nosso).
