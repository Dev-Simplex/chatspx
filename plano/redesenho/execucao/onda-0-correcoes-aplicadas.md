# Onda 0 · bloco 0.2 — CORREÇÕES APLICADAS (executor C1)

**Worktree:** `/home/chatwoot/chatwoot-redesenho-correcoes` · **branch** `redesenho-correcoes`
**Parte de:** `93571c69db` (o merge da v4.16.2)

| ref | SHA |
|---|---|
| BASE (v4.12.1) | `899fce1c92` |
| NOSSO (fork) | `f26db6ee81` |
| DELES (v4.16.2) | `70e284a044` |
| MERGE | `93571c69db` |

Autoridade: `onda-0-correcoes-pendentes.md` (22 itens) + a lista fechada do despacho C1.
Escopo NÃO meu: `vite*.ts` / `swagger.json` (bloco 0.3, outro executor) e o `.env`
(`SAFE_FETCH_ALLOW_PRIVATE_NETWORK`, item de pré-deploy).

> STATUS: **EM EXECUÇÃO** — escrito incrementalmente conforme cada item fecha.

---

## GRUPO 1 — DADO (dado de cliente em risco)

### Item 1 · A2 §C-1 · `purge_pending_captain_assistant_responses` — **APLICADO**

**O que estava** (`db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb`):

```ruby
def up
  execute('DELETE FROM captain_assistant_responses WHERE status = 0')
end
def down; end
```

No upstream `status = 0` nunca foi estado válido (é lixo). No fork é **FAQ pendente de revisão
humana**, gravada pelo `ConversationFaqService` antes de o upstream trocar o fluxo por
`captain_faq_suggestions`. Combinado com o enum que perdeu o estado
(`enum status: { approved: 1 }`), a linha ficava órfã e depois era apagada, sem `down`.

**O que ficou** — duas edições:

1. `enterprise/app/models/captain/assistant_response.rb:47` → `enum status: { pending: 0, approved: 1 }`,
   com comentário explicando que é legado e que `status` **não** é permitido em `response_params`
   (conferido: `params.require(:assistant_response).permit(:question, :answer, :assistant_id)`),
   logo reintroduzir o estado **não** reabre a criação de pendentes pela API.
2. A migration virou **transferência + purge**, em SQL puro (usar os modelos dispararia
   `after_commit :update_embedding` do `Captain::FaqSuggestion` e gastaria crédito recalculando um
   vetor que já temos): `INSERT INTO captain_faq_suggestions` (question, answer, **embedding**,
   assistant_id, account_id, language, source_count 1, status 0 = `open`) → `INSERT INTO
   captain_faq_observations` (o vínculo com a conversa de origem, status 0 = `attached`) →
   `DELETE`.

**Divergências deliberadas do patch proposto em §C-1, e por quê:**

- O patch do auditor fazia `JOIN (SELECT id, 'pt' AS locale_name FROM accounts) a` e depois
  `split_part(replace(a.locale_name, ...))` — um rodeio que sempre resulta em `'pt'`. Troquei pelo
  literal `'pt'` direto. Confirmado que `'pt'` é o formato certo:
  `ConversationFaqService.normalize_language` faz `language.tr('-','_').split('_').first.downcase`,
  então `pt_BR` → `pt`. (`accounts.locale` é enum inteiro; resolver o nome em SQL puro exigiria
  replicar o mapa do enum — e a frota é pt-BR, `pt_BR = 16` é o default.)
- Troquei o `JOIN captain_faq_suggestions ON question/answer` por **`JOIN LATERAL ... LIMIT 1`**.
  Com o JOIN simples, duas pendentes de mesmo question/answer no mesmo assistant produziriam
  produto cartesiano (2×2 = 4 linhas de observation); o `ON CONFLICT DO NOTHING` mascararia parte
  disso. Com `LATERAL ... ORDER BY fs.id LIMIT 1` é **uma** observation por pendente,
  deterministicamente.
- Acrescentei `AND EXISTS (SELECT 1 FROM conversations c WHERE c.id = r.documentable_id)`:
  `captain_faq_observations` **não tem FK** para `conversations` (conferido em `db/schema.rb`), então
  uma pendente cuja conversa já foi apagada geraria observation apontando para um id inexistente.

**Não ressuscitei a tela velha** (`captain/responses/Pending.vue`), conforme o despacho: o front já
migrou inteiro para `FaqSuggestions.vue` e a rota `faqs/pending` já redireciona. A correção garante
que o DADO não morra órfão, não que a UI antiga volte.

**Comando que prova** (`db/migrate/...`): ver §DoD, run da migration no banco de teste dedicado.

**Veredito: APLICADO.**

### Item 2 · A2 §C-2 · `enqueue_validate_openai_hooks_job` — **APLICADO**

**O que estava:** `def up; Migration::ValidateOpenaiHooksJob.perform_later; end`, sem `down`. O job
faz `hook.destroy!` em `Integrations::Hook` de `openai` — **com a `api_key` e as settings dentro** —
para toda conta cuja chave devolva 401 em `GET {api_base}/models`. Assíncrono, fora da transação da
migration, irreversível. Numa VM cujo `CAPTAIN_OPEN_AI_ENDPOINT` aponte para um gateway que só
libere `/chat/completions` (401 em `/v1/models` com chave boa), apaga as integrações de IA da VM
inteira.

**O que ficou:**

1. A migration virou **no-op comentada**, dizendo por quê e como rodar o housekeeping à mão
   (`db/migrate/20260515000000_enqueue_validate_openai_hooks_job.rb`). Nada foi apagado do job — a
   capacidade continua existindo, só deixou de disparar sozinha no `db:migrate` da frota.
2. `app/jobs/migration/validate_openai_hooks_job.rb` ganhou `dry_run:` (default `false`, então a
   assinatura antiga e os 3 specs existentes seguem válidos): conta o que apagaria, loga
   `WOULD destroy hook_id=… account_id=…`, e **não** manda o e-mail de "desconectado".

**Mecanismo de aceite** (não é afirmação): spec novo em
`spec/jobs/migration/validate_openai_hooks_job_spec.rb`, com valor exato —
`expect(result).to eq(checked: 1, destroyed: 1)`, `expect(hook.reload).to be_enabled`,
`expect(hook.reload.settings['api_key']).to eq('sk-bad')` (a chave sobrevive) e
`expect(...IntegrationsNotificationMailer).not_to have_received(:with)`.

**Veredito: APLICADO.**

---

## GRUPO 2 — PERDA de comportamento de IA em produção

### Item 3 · A2 §C-16 · `response_builder_job` — **APLICADO**

**O que estava:** `fix_property_links` apagado (método e chamada), `outgoing_attachment_placeholder`
devolvendo `'[attachment sent]'` para toda foto, `quoted_description` devolvendo
`'a previously sent attachment'`, e o regex de limpeza cobrindo só o placeholder novo em inglês.

O que torna isto acidente e não decisão: **o produtor do dado continua vivo e o comentário dele
descreve o consumidor apagado** — `buscar_imovel_tool.rb:125-127` grava `urls_imoveis` e
`enviar_fotos_imovel_tool.rb:147,197` gravam `property_code`. `git grep fix_property_links` no merge
devolvia **só o comentário**.

**O que ficou:** as quatro edições de §C-16 —
(a) `fix_property_links` de volta, com o comentário, chamado no início de `sanitize_for_whatsapp`;
(b) `property_code` de volta no placeholder de anexo;
(c) `property_code` de volta em `quoted_description`, com o fallback pt-BR
    (`'uma foto enviada anteriormente'`, que é o texto que entra no prefixo pt-BR
    `[Respondendo a esta mensagem anterior: "…"]`);
(d) o comentário da rajada sem transação reinserido em `process_response`, para ninguém "otimizar"
    isso envolvendo os sends numa transação.

Mais uma linha que §C-16 pede e que é a parte fácil de esquecer: o regex agora remove **os dois**
placeholders — o novo (`[attachment sent]`) e o pt-BR legado
(`/\[\s*fotos?[^\]]*enviad[ao]s?\s*\]/i`), que **já está gravado no histórico da frota**. Sem ele, o
LLM ecoando `[foto do imóvel 3338 enviada]` mandaria isso literalmente ao cliente.

**Divergência registrada:** no fallback SEM `property_code`, §C-16(b) mantém o
`'[attachment sent]'` do upstream (o nosso era `'[foto do imóvel enviada]'`). Segui o patch do
auditor. Fica registrado que, para um cliente que não é imobiliária, "foto do imóvel" era a string
errada — adotar o texto neutro é melhoria, não perda, mas é uma diferença em relação a NOSSO e
está aqui à vista.

**Mecanismo de aceite** (5 casos novos em `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb`,
todos com valor exato):

```ruby
expect(out).to eq('Olha: https://www.toziimoveis.com.br/imovel/x,3338')  # URL inventada -> a real
expect(out).to eq('Veja ')                                              # código que não bate -> removida
expect(out).to eq('Segue  pra você ver')                                # placeholder pt-BR legado limpo
expect(...outgoing_attachment_placeholder...).to eq('[foto do imóvel 3338 enviada]')
expect(...outgoing_attachment_placeholder...).to eq('[attachment sent]')
```

**Veredito: APLICADO.**

### Item 4 · A2 §C-15 · `handoff_tool` — **APLICADO**

**O que estava:** a `description` do tool — o texto que o LLM lê para decidir transferir — era a do
upstream, consent-first: *"only when the customer requests human assistance, accepts an offer…"*.
Três linhas acima, **o nosso comentário que condena exatamente esse tipo de descrição sobreviveu**
(`handoff_tool.rb:1-6`: *"A descrição antiga ('when unable to assist further') fazia a IA quase nunca
chamar o tool… então nenhum lead chegava ao humano"*). O arquivo se autocontradizia.

**O que ficou:** a descrição pt-BR proativa restaurada. `#description` de instância continua fazendo
`base = self.class.description`, então o modo "IA decide" (que enumera os times) recebe o texto novo.

**E o spec, que é a parte que importa:** `handoff_tool_spec.rb` tinha sido **reescrito para assertar
o texto do upstream** em DOIS lugares (`:15-16` e `:30`) — é por isso que a regressão passava verde.
Os dois asserts agora travam a nossa descrição. Rodado: 30 examples, 0 failures.

**Decisão aberta registrada (não é minha nem do coordenador):** adotar o consent-first do upstream é
mudança de política de atendimento com efeito comercial direto (chegada de lead ao humano). Se o dono
do produto escolher adotá-la, os três pontos andam juntos — `assistant.liquid` §Human Handoff
Protocol, `snippets/core_rules.liquid` (a regra de transferência) e esta `description` — e o
comentário de `handoff_tool.rb:1-6` tem de ser **apagado**, senão o arquivo volta a se contradizer.

**Veredito: APLICADO.**

### Itens 5 e 6 · A2 §C-3 e §C-14 · prompts — **APLICADOS**

Dois snippets novos, para preservar a refatoração do upstream em vez de reverter os templates:

- `enterprise/lib/captain/prompts/snippets/spx_conduct.liquid` — as **7 regras de conduta** que o
  merge reduziu a 3 bullets em inglês. Conferidas uma a uma contra o que o merge oferecia: 4 não
  tinham cobertura nenhuma (pessoa pelo nome; não se passar por atendente específico; não pedir nota
  de avaliação; ping de presença) e 2 tinham cobertura pela metade (o limite de 1 repergunta no
  fechamento; o `[IGNORAR]` de cobrança PURA de espera).
- `enterprise/lib/captain/prompts/snippets/availability.liquid` — `business_status` e
  `business_hours_text`. Este é o item que §3.5 elevou: `runtime_context.liquid` só é renderizado
  dentro de `split_instructions_for_cache`, isto é **somente com `prompt_cache_system_enabled?`
  ligado**, e ele é opt-in com default **OFF**. No caminho que a frota roda hoje, `time_awareness`
  calculava os dois valores e eles eram **descartados** — a IA voltou a não saber se está dentro do
  horário.

Chamados nos DOIS templates (`assistant.liquid` e `scenario.liquid` — os agentes de cenário são os
que atendem no modo multi-agente, §3.8). Seguro nos dois modos: no modo caching,
`split_instructions_for_cache` passa `ctx.except(*VOLATILE_PROMPT_KEYS)` ao template estável, então
`business_status` chega vazio, os `{% if %}` não imprimem nada, e o valor vem no bloco volátil por
`runtime_context.liquid` como hoje. Sem duplicação em nenhum dos dois.

**NÃO** devolvi `current_datetime`/`business_status`/`business_hours_text` ao corpo de
`assistant.liquid`: eles migraram de propósito para `runtime_context.liquid` (design de prompt
caching, correto).

**Mecanismo de aceite:** `spec/enterprise/lib/captain/lib/captain/prompts/spx_prompt_snippets_spec.rb`
(arquivo novo) renderiza os templates **reais** — sem stub de `File` — e assevera valor:

```
render('assistant', business_status: 'fechado agora, os atendentes voltam às 8h', ...)
  → contém '# Disponibilidade' e 'O atendimento está fechado agora, os atendentes voltam às 8h.'
render('assistant', {})   → NÃO contém '# Disponibilidade' nem '# Horário de funcionamento'
render('scenario', …)     → idem, os 4 casos
render('assistant', {})   → contém '# Conduta no atendimento (ChatSPX)' + as 6 regras nomeadas acima
```

**Veredito: APLICADOS.**

### Item 7 · A2 §C-9 · `agentable.rb#agent_model` — **APLICADO**

**O que estava:** `agent_model` devolvia `route[:model]` cru. Perdeu duas salvaguardas nossas:
`Llm::Models.runtime_id_for` (o `llm.yml` guarda `claude-sonnet-4.5` com ponto; o RubyLLM só conhece
`claude-sonnet-4-5` com hífen — e a gem `ai-agents` passa o valor direto para `RubyLLM.chat` com
`assume_model_exists: false`, então toda conta com assistant Claude derrubava o Captain com
`ModelNotFoundError`) e o fallback por suporte de runtime.

**O que ficou:** o patch de §C-9, com o comentário explicando as duas razões.

**Mecanismo de aceite** — 2 casos novos em `agentable_spec.rb`, e a lacuna que eles fecham é
nomeada: a cobertura que o merge trouxe exercita `gpt-5`, `gpt-4.1-nano` e o default, **nenhum
Claude**, então a suíte passava verde com o defeito dentro.

```ruby
account.update!(captain_models: { 'assistant' => 'claude-sonnet-4.5' })
expect(agent_model).to eq('claude-sonnet-4-5')        # tradução ponto -> hífen

create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'modelo-que-nao-existe')
expect(agent_model).to eq(Llm::Models.default_model_for('assistant'))  # fallback por runtime
```

Os 5 casos que já existiam continuam passando — medido, não suposto: rodei
`Llm::Models.runtime_supported_model?` nesta VM para os 9 modelos do `llm.yml` que os specs usam e
**todos devolvem `true`**, então `first_runtime_supported(preferred, default)` devolve `preferred`.

**Veredito: APLICADO.**

### Item 8 · A2 §C-13 · `config/llm.yml` + o conjunto de LLM — **APLICADO (parcial, por medição)**

**Defaults do fork restaurados:**

| chave | MERGE | agora | por quê |
|---|---|---|---|
| `features.assistant.default` | `gpt-4.1` | **`gpt-5-mini`** | default nosso, deliberado |
| `features.copilot.default` | `gpt-4.1` | **`gpt-5-mini`** | idem |
| `features.audio_transcription.default` | `gpt-4o-mini-transcribe` | **`whisper-1`** | trocava o modelo de transcrição de áudio de toda a frota |

`gpt-5.1`/`gpt-5.2` **ficam disponíveis** nas listas (saída 1 de §C-13: "disponíveis mas não
default").

**O que NÃO fiz, e a medição que decidiu:** §C-13 também sugeria trocar os defaults de
`conversation_faq_generation` e `help_center_article_generation` de `gpt-5.2` para `gpt-4.1-mini`,
mas **condicionado**: *"Se der `false` em qualquer uma, a saída 1 é obrigatória"*, referindo-se a
`Llm::Models.runtime_supported_model?('gpt-5.2')`. Medi nesta VM: **`true`**. E as duas features são
**novas do upstream** — não existiam em NOSSO, logo não há default nosso a restaurar; mudá-las seria
tomar uma decisão nova, não desfazer uma reversão. Cheguei a aplicar e reverti quando o
`spec/lib/llm/models_spec.rb:29` (spec do upstream) acusou. **Registrado como decisão aberta**:
`gpt-5.2` tem `credit_multiplier: 3` contra 1 do `gpt-5-mini` — as duas features nascem 3× mais
caras por chamada. O dono do produto decide o default.

**Specs que travam a decisão** (§4.2 mostrou que o merge os havia removido/reescrito):

- `preferences_controller_spec.rb:63-64` → volta a assertar `gpt-5-mini` para assistant e copilot;
- `audio_transcription_service_spec.rb:128` → volta a assertar `model: 'whisper-1'`.

**O que NÃO restaurei, e por quê:** os asserts de `spec/lib/llm/models_spec.rb` que garantiam
`runtime_supported_model?('gpt-5.1') == false` e
`first_runtime_supported('gpt-5.1','gpt-5.2','unknown') == 'gpt-5-mini'`. Eles só valem se
`gpt-5.1`/`gpt-5.2` **não** estiverem no `llm.yml`, e a decisão foi mantê-los disponíveis. Restaurar
os asserts contradiria o `llm.yml` que ficou. É o que "reconcilie o CONJUNTO, não arquivo por
arquivo" significa aqui.

**`public/version.json`:** estava na lista dos 8 arquivos em edição inacabada, mas é artefato de
deploy (`{"version":"f26db6ee81","deployed_at":…}`), regenerado no deploy. Nenhum relatório propõe
mexer nele. **Não tocado.**

**ESCALAÇÃO (item que o `llm.yml` sozinho NÃO desfaz — precisa do dono do produto):**
`Llm::FeatureRouter::CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'` força `gpt-5.2` em **toda conta com
`captain_integration_v2` que não tenha escolha explícita de modelo**. E esse flag está
`enabled: true` e é ligado em `enable_default_features` para toda conta self-hosted enterprise
(`enterprise/app/models/enterprise/account.rb:111`) — ou seja, **a frota inteira**. Nosso fork nunca
forçou modelo por flag: valia `account.captain_models['assistant']` ou o default do `llm.yml`.
Efeito medido: o default que acabei de restaurar (`gpt-5-mini`, `credit_multiplier 1`) **não chega**
a essas contas; elas rodam `gpt-5.2` (`credit_multiplier 3`).
**Não apliquei** porque (a) não está na lista fechada, (b) o auditor deliberadamente escopou C-13 ao
`llm.yml` dizendo "C-9 resolve o fallback; o default continua sendo escolha nossa", e (c) neutralizar
o forçamento exige reescrever asserts em **3 arquivos de spec**
(`agentable_spec.rb:185`, `preferences_controller_spec.rb:128,144`,
`super_admin/accounts_controller_spec.rb:77`), o que é mudança deliberada de produto e não conserto
de merge. Uma linha resolve quando houver decisão.

### Item 9 · A2 §C-11 · fuso horário — **APLICADO**

`agentable.rb`: `bh['timezone'].presence || account&.reporting_timezone.presence || 'America/Cuiaba'`.
Usar `reporting_timezone` é melhor (multi-tenant) e fica; o que faltava era o fallback final — sem
ele, conta sem nenhum dos dois cai em `TimeZone[nil]` → nil → **UTC**, e a IA informa horário 3–4 h
adiantado ao cliente.

### Item 10 · A1 patch 1 · `openai_prompts/summary.liquid` — **APLICADO**

O bloco pt-BR de volta byte a byte de `f26db6ee81`: a regra `**IMPORTANT — LANGUAGE**` e os 4
cabeçalhos (`Intenção do cliente`, `Resumo da conversa`, `Itens de ação`, `Pendências`).
O que prova que foi acidente e não decisão: os quatro prompts irmãos (`reply`, `improve`,
`tone_rewrite`, `fix_spelling_grammar`) **mantiveram** a instrução pt-BR no merge; só o `summary`
perdeu (MERGE == DELES byte a byte).

### Item 11 · A1 patch 3 · `swagger_controller.rb` — **APLICADO**

**O que estava:** o gate `if Rails.env.development? || Rails.env.test?` com `else head :not_found`
respondia 404 em produção **antes** de a Basic Auth servir para nada, deixando nosso
`authenticate_docs!` (`:20-37`) como código morto — a doc da API deixava de existir em produção.

**O que ficou:** gate removido, **hardening de path traversal do upstream preservado**
(`Rack::Utils.clean_path_info` + `delete_prefix('/')` + o `start_with?("#{swagger_root}/")`).
Quem fecha a porta é o `authenticate_docs!`, que já é o padrão seguro: sem `SWAGGER_DOCS_PASSWORD`
ele devolve 404 por conta própria.

**Mecanismo de aceite** — 4 casos novos em `spec/controllers/swagger_controller_spec.rb` que
exercitam o caminho de produção sem depender do ambiente do runner
(`allow(Rails.env).to receive(:development?/:test?).and_return(false)`):

| cenário | esperado | resultado |
|---|---|---|
| sem `SWAGGER_DOCS_PASSWORD` | 404 | ✅ |
| com senha, sem credencial | 401 | ✅ |
| com senha e credencial correta | 200 + página | ✅ |
| `GET /swagger/swagger.json` sem credencial | 200 | ✅ |

O caso de path traversal (`/swagger/%2Fetc%2Fpasswd` → 404) continua passando.

---

## Bloco C3 — os dois P0 de DESTRUIÇÃO SILENCIOSA que fecharam a Onda 0

Executor C3. Worktree `chatwoot-redesenho-correcoes`, branch `redesenho-correcoes`.
Banco de teste **dedicado**: `chatwoot_test_c3` (criado para esta task; nenhum banco de dev ou de
produção foi tocado, nenhuma migration rodou fora de `RAILS_ENV=test`).

### Item 23 · A6 §1.1 · `excluir conversa` volta a excluir — **APLICADO** (o WIP foi validado, e **corrigido**)

O commit `a9eeef3105` era `WIP` de propósito: código no disco, nada provado. Validei as três
peças. **Duas estavam certas. A terceira não fechava o defeito** — e o motivo é o achado mais
importante deste bloco.

#### (a) A assinatura — estava certa

`Conversations::DeleteService` é novo do upstream e chamava o **nosso** `DeleteObjectJob` com
`(conversation, user, ip)` — 3 objetos — quando o job espera `(object_type, object_id, user_id, ip)`.
A primeira linha do job é `return unless ALLOWED_OBJECT_TYPES.include?(object_type)`, e comparar
uma String com uma instância de `Conversation` dá `false`: o job **retornava na primeira linha**,
sem exceção, sem log, sem GlitchTip. A API respondia **200 OK** e a conversa continuava lá.

**Vermelho-antes**, com a linha 14 revertida para a forma antiga (produzido, não afirmado):

```
$ bundle exec rspec spec/controllers/api/v1/accounts/conversations_controller_spec.rb \
    -e 'when the conversation has records that used to block its deletion'
Failure/Error: expect(Conversation.exists?(conversation.id)).to be(false)
  expected false
       got true
2 examples, 2 failures
```

`got true` **é o defeito**: a conversa sobreviveu ao "sucesso".

#### (b) A migration de FK — a escolha por coluna estava certa, e cada CASCADE justificado

Medido em `pg_constraint` no banco de teste, **quatro** FKs apontavam para `conversations` com
`NO ACTION` (`confdeltype='a'`) — o executor anterior estava certo, são quatro e não duas:

```
captain_assistant_logs | conversation_id | a
flow_runs              | conversation_id | a
flow_step_logs         | conversation_id | a
message_sequence_enrollments | conversation_id | a
```

Conferi a nullability de cada coluna no schema antes de assinar a escolha. **As duas frases que o
coordenador pediu, uma por CASCADE:**

- **`flow_runs.conversation_id` → CASCADE.** A coluna é `null: false` (`schema.rb:1323`): *um
  `FlowRun` é a execução de um flow **dentro de uma conversa**, e o próprio banco proíbe que ele
  exista sem uma — não há estado válido de `FlowRun` órfão, então preservá-lo é impossível, não
  apenas indesejável.*
- **`message_sequence_enrollments.conversation_id` → CASCADE.** A coluna é `null: false`
  (`schema.rb:1737`): *uma inscrição em sequência é o vínculo entre uma sequência e **aquela**
  conversa; sem a conversa não há a quem entregar o próximo passo, e o índice único parcial
  `index_active_enrollment_per_sequence_conversation` é definido sobre `(message_sequence_id,
  conversation_id)`, isto é, a identidade do registro inclui a conversa.*

As três nullable ficaram **SET NULL**, preservando o log de diagnóstico:
`captain_assistant_logs.conversation_id`, `flow_step_logs.conversation_id` e
`flow_step_logs.flow_run_id`.

Rodei a migration **nos dois sentidos** no banco de teste. Com ela revertida:

```
$ bin/rails db:migrate:down VERSION=20260723000000 && bin/rails runner probe_fk.rb
FKs NO ACTION agora: captain_assistant_logs.conversation_id, flow_step_logs.conversation_id,
                     flow_runs.conversation_id, message_sequence_enrollments.conversation_id
RESULTADO: InvalidForeignKey -> PG::ForeignKeyViolation: ERROR: update or delete on table
"conversations" violates foreign key constraint "fk_rails_deb91f3c1b" on table
"captain_assistant_logs"
```

#### (c) 🔴 O que o WIP **não** fechava: a FK sozinha depende da ORDEM DOS TRIGGERS

Com a migration aplicada, `conversation.destroy!` **continuava** levantando `InvalidForeignKey`:

```
PG::ForeignKeyViolation: ERROR: insert or update on table "flow_step_logs"
  violates foreign key constraint "fk_rails_d47afdca87"
DETAIL:  Key (flow_run_id)=(6) is not present in table "flow_runs".
```

Isolei a condição — só falha quando o **mesmo** `flow_step_log` tem `conversation_id` **e**
`flow_run_id` preenchidos, que é o caso normal de qualquer flow que rodou numa conversa:

| cenário | resultado |
|---|---|
| step_log com `conversation_id` **e** `flow_run_id` | ❌ FALHA |
| step_log só com `flow_run_id` | ✅ OK |
| step_log só com `conversation_id` | ✅ OK |
| nenhum step_log | ✅ OK |

**Mecanismo:** apagar a conversa dispara duas ações sobre a mesma linha de `flow_step_logs` — o
CASCADE de `flow_runs.conversation_id` (que remove a run) e o SET NULL de
`flow_step_logs.conversation_id` (que faz `UPDATE` na linha). Se o `UPDATE` corre **depois** do
delete da run, o Postgres revalida `flow_run_id` contra uma linha que ele mesmo apagou na
transação. Trocar essa FK por CASCADE **não resolve** (testado: falha igual).

**E aqui está a parte que faz disto um falso verde estrutural** — o resultado depende da ordem de
criação das constraints, e ela **diverge entre os dois caminhos**:

```
ESTADO 1: db:schema:load do schema.rb  (o que a SUÍTE DE TESTE faz)   -> destroy! OK
ESTADO 2: migration aplicada por cima  (o que a FROTA vai fazer)      -> InvalidForeignKey
```

Mesmo schema lógico, mesma migration, veredito oposto. Com a migration só, a suíte ficaria verde e
**a frota quebraria** — e quebraria do jeito que o próprio WIP queria evitar: dentro de um job com
retry, isto é, trocando "some em silêncio" por "falha em loop no GlitchTip". No request spec, sem
a correção, o `DELETE` devolve **500**.

**Correção (minha, não estava no WIP):** `app/models/conversation.rb` ganhou
`has_many :flow_step_logs, dependent: :nullify`. Nullificar pelo Rails acontece **antes** do
`DELETE` e é determinístico — não depende de ordem de trigger. Medido no ESTADO 2 (o da frota),
isolando só essa linha:

```
sem  dependent: :nullify -> PG::ForeignKeyViolation ... Key (flow_run_id)=(6) is not present
com  dependent: :nullify -> destroy! OK
```

#### Aceite — request spec, e o aceite **não** é "a API devolveu 200"

`spec/controllers/api/v1/accounts/conversations_controller_spec.rb`. Os dois exemplos que já
existiam asseveram a *chamada* (`have_enqueued_job … .with(...)`) — foi exatamente por isso que o
P0 passou verde. Os dois que adicionei asseveram o **efeito no banco**, com `flow_run` e
`message_sequence_enrollment` associados:

| exemplo | o que prova | vermelho-antes |
|---|---|---|
| `removes the conversation from the database, not just returns 200` | `Conversation.exists?` é **false**; `FlowRun` e `MessageSequenceEnrollment` sumiram por CASCADE | `expected false / got true` |
| `removes the conversation under the FK ordering the fleet will have` | recria as FKs na ordem da migration (o ESTADO 2) e o delete ainda funciona; `FlowStepLog` **sobrevive** com `conversation_id: nil, flow_run_id: nil` | `500 Internal Server Error` |

O segundo exemplo é a rede que faltava: sem ele, esta regressão volta e a suíte não vê.

### Item 26 · A7 P0 · editar integração para de apagar a credencial — **APLICADO**

Defeito de **composição**: nenhum dos três lados está errado sozinho, e por isso passava por 100%
dos testes verdes.

1. o upstream passou a filtrar `settings` por `app.visible_properties` no
   `_hook.json.jbuilder` — a chave `settings` **continua sendo emitida**, muda só o conteúdo, então
   nenhum teste de contrato de nível de chave falha;
2. `EditHook.vue` (100% do fork — o upstream não tem tela de editar hook) lê o hash já filtrado,
   grava `''` no campo que chegou `undefined` e reenvia tudo;
3. `HooksController#update` **sobrescrevia** o jsonb inteiro.

Resultado: abrir "Editar" e salvar **destruía a credencial no banco**, com 200 OK e sem log.
6 integrações, 14 chaves. Exposição medida nesta VM: **1 hook `openai` habilitado**.

**O filtro do jbuilder NÃO foi desfeito** — não devolver segredo no JSON é a parte certa do que o
upstream fez, e há um exemplo que guarda essa regressão (`does not return the api_key in the
payload`, que assere `settings == {'label_suggestion' => false}`).

#### Corrigido dos dois lados, porque cada um fecha um caminho diferente

- **Servidor** (`hooks_controller.rb`): `update` passou a **mesclar** `settings` em vez de
  substituir. Protege qualquer cliente, inclusive script que chame a API direto.
- **Front** (`EditHook.vue`): não reenvia chave que não recebeu. `settingKeysMissingFromServer()`
  olha só o que o servidor mandou — não presume quais chaves são secretas, porque
  `visible_properties` varia por app e **já mudou uma vez neste merge**.

**Uma decisão que preciso registrar** (é minha, e o coordenador pode reverter): o merge sozinho
resolve "o cliente não mandou a chave", mas **não** resolve "o cliente mandou a chave vazia" — que
é exatamente o que a nossa tela fazia e o que qualquer script escrito contra ela ainda faria. Meu
terceiro exemplo falhou nisso, e a falha estava certa. Fechei com a mesma regra do front, do outro
lado do fio: **valor vazio para chave que não está em `visible_properties` é ignorado**, porque o
cliente nunca recebeu aquele valor e portanto não pode ter tido intenção de apagá-lo. Chave visível
continua podendo ser esvaziada, e trocar a credencial por um valor novo funciona sempre.
**Custo aceito:** a API deixa de conseguir *remover* uma chave invisível de `settings` (só
sobrescrevê-la). Nenhuma tela nossa faz isso.

#### Aceite

`spec/controllers/api/v1/accounts/integrations/hooks_controller_spec.rb` — 4 exemplos novos:

| exemplo | asserção |
|---|---|
| `does not return the api_key in the payload` | `settings == {'label_suggestion' => false}` (o filtro do upstream **continua** valendo) |
| `keeps the stored api_key when the update does not mention it` | `settings == {'api_key' => 'sk-original', 'label_suggestion' => true}` |
| `keeps the stored api_key even when a client blanks it out` | `settings['api_key'] == 'sk-original'` |
| `still lets an administrator replace the credential on purpose` | `settings['api_key'] == 'sk-nova'` |

**Vermelho-antes** (só o controller revertido, spec novo rodando) — os dois sintomas que a
auditoria previu, "ou apaga, ou tranca", nos dois exemplos:

```
Failure/Error: expect(openai_hook.reload.settings['api_key']).to eq('sk-original')
  expected: "sk-original"
       got: ""                      <-- a credencial foi APAGADA no banco

Failure/Error: expect(response).to have_http_status(:success)
  expected 2xx but it was 422       <-- settings_json_schema exige api_key: a edição TRANCA
4 examples, 2 failures
```

O lado do front tem prova própria, sem navegador e sem Playwright:
`app/javascript/dashboard/routes/dashboard/settings/integrations/specs/EditHook.spec.js`,
5 exemplos sobre `buildHookPayload` — **5 passed depois, 5 failed antes**. Cobre também o campo
JSON do `dialogflow`, onde o `JSON.parse('')` de um campo omitido levantaria `SyntaxError`.

### A cadeia entre os dois defeitos — registrada para que ninguém reintroduza uma metade

`Integrations::Hook#validate_openai_api_key?` dispara quando `openai_api_key_changed?`. Sem a
correção do item 26, salvar a tela mudava a chave para `''` — e é **essa mudança** que arma o job
do **item 8** (`Migration::ValidateOpenaiHooksJob`), que **destrói o hook inteiro** quando a chave
não valida. Encadeado: o admin edita qualquer campo da integração → a chave é apagada → o job
seguinte apaga a integração inteira. Os dois itens estão corrigidos separadamente; **nenhuma das
duas metades protege sozinha**, e quem reverter uma achando que a outra cobre reabre a cadeia.

### Verificações de gate

| gate | resultado |
|---|---|
| `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` | **vazio** (258 migrations) — conferido no fim, depois de todo o trabalho |
| `rubocop` nos 7 arquivos tocados | **0 offenses** |
| `eslint` em `EditHook.vue` | **limpo** |
| `conversations_controller_spec` | baseline **9 falhas** / depois **9 falhas** + 2 exemplos novos verdes → **delta 0** |
| `hooks_controller_spec` | 16 exemplos, **1 falha**, e ela é **pré-existente** (`validates Cloudflare RealtimeKit credentials`, falha idêntica no HEAD limpo) |
| migration rodada fora do banco de teste | **não** — só `chatwoot_test_c3` |
