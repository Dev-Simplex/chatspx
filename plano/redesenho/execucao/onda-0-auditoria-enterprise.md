# TASK A2 — Auditoria semântica do merge v4.16.2 · ENTERPRISE / CAPTAIN / SPECS / CONFIG / DB

**Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **branch** `redesenho-merge` · **HEAD** `93571c69db`

| ref | SHA | o que é |
|---|---|---|
| BASE | `899fce1c9286b793d165c8ad6c0200ab676f185b` | tag v4.12.1 — ancestral comum |
| NOSSO | `f26db6ee81` | fork ChatSPX, 940 commits depois |
| DELES | `70e284a044f00326725f65f703162745371075ec` | tag v4.16.2 |
| MERGE | `93571c69db` | o resultado auditado (= HEAD) |

Estado do worktree ao iniciar: **limpo** (`git status --short` vazio). A task mencionava 8 arquivos com
edição de working tree inacabada em `config/llm.yml` / `lib/llm/*`; **não há nenhuma edição pendente
agora** — o outro executor que compartilha o worktree pode ter commitado ou a informação era de um
snapshot anterior. Auditei essas 8 vias `git diff NOSSO MERGE` como todos os demais.

> STATUS: **CONCLUÍDO**. 117 de 117 arquivos da área auditados, mais as 39 migrations novas,
> `db/schema.rb`, `lib/llm/*` e `enterprise/app/models/captain/assistant_response.rb`.
> Veredito consolidado: **3 DADO · 7 PERDA · 17 RISCO · 130 OK** (detalhe em CONTAGEM FINAL).
>
> **Leitura mínima, se o tempo for curto:** §2.2 e §2.3 (os dois DADO), §3.2 e §3.7 (as duas PERDA de
> maior impacto operacional), §1.3 (o achado nº 3 do coordenador, desescalado com prova), §4.1 (por que
> a suíte de testes passa verde com a regressão do handoff dentro), e C-1/C-2 (as correções urgentes).

---

## PARTE 1 — FEATURE FLAGS (config/features.yml + db/migrate/*repurpose*)

### 1.1 Mapa de bits nas 4 versões (fonte: parse YAML real, não leitura visual)

Contagens:

| ref | total | `feature_flags` | `feature_flags_ext_1` |
|---|---|---|---|
| BASE (v4.12.1) | 63 | 63 | — |
| NOSSO (ChatSPX) | 65 | **65** ← estourado | — |
| DELES (v4.16.2) | 68 | 63 | 5 |
| MERGE (HEAD) | 77 | 63 | 14 |

**Os 63 primeiros bits do MERGE são byte-a-byte, na mesma ordem, os 63 primeiros bits de NOSSO.**
Verificado por parse do YAML e `diff` das listas `coluna[bit] nome`:

```
=== NOSSO -> MERGE (único delta) ===
64,65c64,77
< feature_flags[64] conversation_required_attributes
< feature_flags[65] advanced_assignment
---
> feature_flags_ext_1[1..5]  whatsapp_manual_transfer, data_import, api_and_webhooks,
>                            whatsapp_reconfigure, whatsapp_embedded_signup_inbox_creation
> feature_flags_ext_1[6..12] conversation_unread_counts, custom_tools, message_reply_to,
>                            branded_email_templates, captain_v1_action_classifier,
>                            captain_document_auto_sync, unread_count_for_filters
> feature_flags_ext_1[13]    conversation_required_attributes
> feature_flags_ext_1[14]    advanced_assignment
```

**VEREDITO `config/features.yml`: OK (resolução correta).** Nenhum bit 1–63 da frota se moveu.
É o resultado que se queria. Os detalhes que sustentam isso estão em 1.2 e 1.3.

### 1.2 Os 6 `repurpose_*` do upstream — o dano que ELES fariam, e por que não fazem

O upstream v4.16.2 reaproveitou 6 bits da coluna `feature_flags` (todos ocupados por flags que ELE
marcou deprecated). Em 2 desses 6 bits, o ChatSPX **já havia colocado outra feature viva**:

| bit `ff` | BASE (v4.12.1) | upstream v4.16.2 põe aqui | **NOSSO fork tem aqui** | colisão? |
|---|---|---|---|---|
| 4 | `channel_twitter` | `conversation_unread_counts` | `channel_twitter` | não |
| **29** | `response_bot` | `custom_tools` | **`message_sequences`** | **SIM** |
| 31 | `insert_article_in_reply` | `branded_email_templates` | `insert_article_in_reply` | não |
| **39** | `report_v4` | `captain_v1_action_classifier` | **`ai_assistant_v2`** | **SIM** |
| 52 | `twilio_content_templates` | `captain_document_auto_sync` | `twilio_content_templates` | não |
| 57 | `quoted_email_reply` | `unread_count_for_filters` | `quoted_email_reply` | não |

(Os repurposes que o **ChatSPX** fez por conta própria, `git diff BASE NOSSO`: bit 29
`response_bot`→`message_sequences`, bit 30 `message_reply_to`→`internal_chat`, bit 39
`report_v4`→`ai_assistant_v2`, bits 61–63 reordenados para caber `kanban_cursor_loading` /
`kanban_ux_v2` / `captain_tasks`.)

Cada migration upstream tem a mesma forma, e é ela que seria destrutiva:

```ruby
Account.feature_<nova>.find_each(batch_size: 100) do |account|
  account.disable_features(:<nova>)
  account.save!(validate: false)
end
```

Como `feature_<nova>` resolve para o **bit ff[N]**, rodar isso no fork significaria
`UPDATE accounts SET feature_flags = feature_flags & ~(1<<(N-1))` — apagando o flag do ChatSPX que
mora em N, em **toda a frota**, silenciosamente (`validate: false`).

**O merge neutralizou todas as 6.** Verificado uma a uma contra `git show DELES:<arquivo>`:

| migration | upstream fazia | no MERGE está | veredito |
|---|---|---|---|
| `20260324102005_repurpose_response_bot_flag_for_custom_tools.rb` | `disable_features(:custom_tools)` em massa **+** limpa `response_bot` de `ACCOUNT_LEVEL_FEATURE_DEFAULTS` | só a limpeza do `InstallationConfig`; o loop de `disable_features` foi **removido** | **OK** |
| `20260426011444_repurpose_twilio_content_templates_flag_for_captain_document_auto_sync.rb` | idem (`twilio_content_templates`) | `def up; end` (no-op comentado) | **OK** |
| `20260430114500_repurpose_report_v4_flag_for_captain_v1_action_classifier.rb` | idem (`report_v4`) | só a limpeza do `InstallationConfig` | **OK** |
| `20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb` | idem (`channel_twitter`) | `def up; end` | **OK** |
| `20260629000000_repurpose_quoted_email_reply_flag_for_unread_count_for_filters.rb` | idem (`quoted_email_reply`) | `def up; end` | **OK** |
| `20260706000001_repurpose_insert_article_in_reply_for_branded_email_templates.rb` | idem (`insert_article_in_reply`) | `def up; end` | **OK** |

Por que o no-op é a resolução **certa** e não preguiça: no MERGE, cada feature nova do upstream ganhou
um bit em `feature_flags_ext_1`, coluna criada com `default: 0`. O objetivo da migration upstream era
"garantir que o flag repurposed comece desligado"; num bit virgem de coluna nova isso já é verdade por
construção. O loop era não só desnecessário como destrutivo.

As duas que **mantiveram** a limpeza do `InstallationConfig` também estão certas, e não são
decorativas: `Featurable#enable_default_features` (`app/models/concerns/featurable.rb:115-121`) faz
`enable_features(*names)` a partir de `ACCOUNT_LEVEL_FEATURE_DEFAULTS`, e `enable_features` chama
`send("feature_#{name}=")`. Uma entrada stale `response_bot` ou `report_v4` gravada no
`InstallationConfig` da frota levaria a `NoMethodError` em **criação de conta nova** — porque o
ChatSPX renomeou justamente esses dois bits. As migrations são idempotentes (`reject` que não acha
nada não faz mal).

**AÇÃO OPERACIONAL (não é bug do merge, é pré-deploy):** confirmar, por VM da frota, se
`InstallationConfig[ACCOUNT_LEVEL_FEATURE_DEFAULTS]` contém `response_bot` ou `report_v4`. Se contiver,
essas duas migrations vão salvá-lo de um `NoMethodError`; se não contiver, são no-op. Consulta
read-only proposta (não executada por mim):

```sql
SELECT value FROM installation_configs WHERE name = 'ACCOUNT_LEVEL_FEATURE_DEFAULTS';
```

### 1.3 Achado nº 3 do coordenador (`conversation_required_attributes` / `advanced_assignment`) — **DESESCALADO**

O coordenador classificou como RISCO: "mover de coluna muda onde o bit é lido; conta que já tivesse
esses flags ligados pode aparecer como desligada". **Investiguei e a premissa não se sustenta: não
existe estado a preservar, porque esses dois flags eram fisicamente ingravável em NOSSO.**

Cadeia de prova:

1. `FlagShihTzu` mapeia bit → máscara com `1 << (flag_key - 1)`
   (`flag_shih_tzu-0.3.23/lib/flag_shih_tzu.rb:80`).
2. Em NOSSO, `Featurable::FEATURES` punha **todas** as 65 features na coluna `feature_flags`
   (`git show f26db6ee81:app/models/concerns/featurable.rb`, sem noção de `column:`), logo:
   - `conversation_required_attributes` = bit 64 → máscara `1 << 63` = **9 223 372 036 854 775 808**
   - `advanced_assignment` = bit 65 → máscara `1 << 64` = **18 446 744 073 709 551 616**
3. `accounts.feature_flags` é `bigint` (`db/schema.rb:80`), cujo máximo é
   **9 223 372 036 854 775 807**. Ambas as máscaras **excedem** o tipo.
4. Portanto, em NOSSO, tanto o `UPDATE ... | máscara` (ligar) quanto o `WHERE feature_flags & máscara`
   (ler/consultar) estouram com `PG::NumericValueOutOfRange`. **Nenhuma conta da frota pode ter esses
   bits gravados** — a operação nunca completou.

Corolário: o merge não perdeu estado; ele **conserta um bug latente**. E o bug era alcançável em
produção — `enterprise/app/models/enterprise/account.rb:120` faz
`send('feature_advanced_assignment=', true) if business_or_enterprise_plan?`, ou seja, salvar uma conta
de plano Business/Enterprise em NOSSO dispararia o overflow.

**Veredito: OK.** Não é necessária migration de carregamento de estado, e escrever uma seria pior
(migraria um estado que não existe).

**Verificação de fechamento recomendada** (read-only, para o coordenador rodar na frota antes do
deploy — se qualquer linha voltar diferente de 0, meu raciocínio está errado e eu quero saber):

```sql
-- bits 1..63 são os únicos representáveis; qualquer conta com feature_flags < 0 ou
-- com os 2 flags "ligados" indicaria estado que eu afirmei impossível
SELECT count(*) AS contas_com_flags_negativo FROM accounts WHERE feature_flags < 0;
SELECT count(*) AS contas_ext1_nao_zero FROM accounts WHERE feature_flags_ext_1 <> 0;
```

### 1.4 Nota lateral: bug de nome na migration que cria `feature_flags_ext_1`

`db/migrate/20260706215758_add_feature_flags_ext_2_to_accounts.rb` — a classe se chama
`AddFeatureFlagsExt2ToAccounts` mas o corpo adiciona **`feature_flags_ext_1`**:

```ruby
class AddFeatureFlagsExt2ToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :feature_flags_ext_1, :bigint, default: 0, null: false
  end
end
```

Conferido contra `git show DELES:` — **é bug do upstream, idêntico**, o merge não introduziu nada.
Consequências reais: (a) é a **única** migration do repo que cria `ext_1`, e ela cria; o schema fecha;
(b) `Featurable::FEATURE_FLAG_COLUMNS` só conhece `feature_flags` e `feature_flags_ext_1` — **não
existe coluna `ext_2` nem no schema nem no código**; (c) a armadilha é futura: quem for adicionar
`ext_2` de verdade vai achar que já existe. Veredito: **RISCO (baixo, cosmético/manutenção)**, não
corrigir agora (renomear migration já aplicada na frota reintroduziria a migration).

---

## PARTE 2 — MIGRATIONS (db/migrate): as 39 novas, uma a uma

`comm` entre `git ls-tree NOSSO` e `git ls-tree MERGE` em `db/migrate/`: **39 migrations novas**
(a task dizia 40; são 39 — conferido duas vezes). **Zero migrations nossas apagadas.**
**Zero colisões de timestamp** (`cut -c1-14 | sort | uniq -d` → vazio).

### 2.0 `drop_channel_voice` — CONFIRMADO AUSENTE (o merge acertou)

8 migrations do upstream foram **descartadas** pelo merge:

```
db/migrate/20260326120000_add_voice_to_channel_twilio_sms.rb
db/migrate/20260326120001_drop_channel_voice.rb            ← a perigosa
db/migrate/20260408170902_create_calls.rb
db/migrate/20260604000000_add_provider_config_to_channel_twilio_sms.rb
db/migrate/20260616120000_add_icon_to_teams.rb             ← reentrou como 20260616120001 (fix de colisão)
db/migrate/20260618000000_backfill_rejected_call_status.rb
db/migrate/20260622000000_add_account_created_at_index_to_calls.rb
db/migrate/20260630000000_add_sender_created_index_to_messages.rb  ← reentrou como 20260630000001
```

Varredura por qualquer outra coisa que dropasse a tabela: `git grep -l "channel_voice\|Channel::Voice"`
no MERGE, em `db/` e `config/`, devolve **só** `db/migrate/20250620120000_create_channel_voice.rb`
(a nossa, que cria), `db/schema.rb` (que declara a tabela) e `config/features.yml` (o flag no bit 45).
**Nada dropa `channel_voice`. VEREDITO: OK.**

`add_icon_to_teams` e `add_sender_created_index_to_messages` foram renomeadas de `...000` para
`...001`: é o fix de colisão de timestamp, bem feito.

### 2.1 Tabela-veredito das 39

Critério: **DADO** = destrói/corrompe registro de cliente já gravado. **RISCO** = altera semântica
ou pode travar o `db:migrate` da frota. **OK** = DDL aditivo ou no-op.

| # | migration | veredito | por quê |
|---|---|---|---|
| 1 | `20260714123000_purge_pending_captain_assistant_responses` | **DADO — crítico** | `DELETE FROM captain_assistant_responses WHERE status = 0`. No fork, status 0 = FAQ **pendente viva**. Detalhes em 2.2. |
| 2 | `20260515000000_enqueue_validate_openai_hooks_job` | **DADO** | enfileira job que faz `hook.destroy!` de integrações OpenAI. Detalhes em 2.3. |
| 3 | `20260410092753_backfill_edited_on_captain_assistant_responses` | **RISCO** | marca `edited = true` por heurística `updated_at - created_at > 15 dias`. Detalhes em 2.4. |
| 4 | `20260427094500_rename_company_condition_key_in_automation_rules` | **RISCO** | reescreve `automation_rules.conditions` e `custom_filters.query` (`attribute_key 'company' → 'company_name'`) com `update_column`. Detalhes em 2.5. |
| 5 | `20260706000000_add_inbox_scope_to_email_templates` | **RISCO — trava de deploy** | `raise ActiveRecord::IrreversibleMigration` se houver `email_templates` duplicados com `account_id IS NULL`. Detalhes em 2.6. |
| 6 | `20260409091202_enable_assignment_v2_for_new_accounts` | **RISCO** | liga `assignment_v2` no `ACCOUNT_LEVEL_FEATURE_DEFAULTS`. Detalhes em 2.7. |
| 7 | `20260525093000_change_captain_document_external_link_to_text` | **RISCO — trava de deploy** | `change_column ... null: false` + índice unique novo `md5(external_link)`. Falha se algum `captain_documents.external_link` for NULL, ou se dois documentos do mesmo assistant colidirem por md5. Detalhes em 2.8. |
| 8 | `20260324070835_backfill_agent_bot_and_channel_api_secrets` | **RISCO** | gera `secret` para todo `AgentBot` e `Channel::Api` existente. É aditivo (não sobrescreve — filtra `where(secret: nil)`), mas passa a existir um segredo que consumidores de webhook podem começar a exigir. Detalhes em 2.9. |
| 9 | `20260428120000_backfill_captain_document_sync_metadata` | **OK** | `update_all('sync_status = 1, last_synced_at = updated_at')` só onde `sync_status IS NULL AND last_synced_at IS NULL AND status = available`. Baseline aditivo em colunas criadas na migration irmã; não sobrescreve nada preexistente. |
| 10 | `20260324102005_repurpose_response_bot_flag_for_custom_tools` | **OK** | neutralizada (ver 1.2) |
| 11 | `20260426011444_repurpose_twilio_content_templates_flag_...` | **OK** | no-op (ver 1.2) |
| 12 | `20260430114500_repurpose_report_v4_flag_for_captain_v1_action_classifier` | **OK** | neutralizada (ver 1.2) |
| 13 | `20260508000000_repurpose_channel_twitter_flag_...` | **OK** | no-op (ver 1.2) |
| 14 | `20260629000000_repurpose_quoted_email_reply_flag_...` | **OK** | no-op (ver 1.2) |
| 15 | `20260706000001_repurpose_insert_article_in_reply_...` | **OK** | no-op (ver 1.2) |
| 16 | `20260706215758_add_feature_flags_ext_2_to_accounts` | **RISCO (baixo)** | nome/classe dizem `ext_2`, corpo cria `ext_1`. Bug do upstream (ver 1.4). |
| 17 | `20260324070820_add_secret_to_agent_bots` | OK | `add_column` |
| 18 | `20260324070828_add_secret_to_channel_api` | OK | `add_column` |
| 19 | `20260327065119_create_platform_banners` | OK | `create_table` novo |
| 20 | `20260410092751_add_edited_to_captain_assistant_responses` | OK | `add_column` com default |
| 21 | `20260410092752_add_sync_columns_to_captain_documents` | OK | `add_column` |
| 22 | `20260422133000_add_additional_attributes_to_companies` | OK | `add_column` |
| 23 | `20260429043000_add_sync_stats_index_to_captain_documents` | OK | `add_index` |
| 24 | `20260507000000_add_imap_authentication_to_channel_email` | OK | `add_column` |
| 25 | `20260610000000_add_icon_color_to_categories` | OK | `add_column` |
| 26 | `20260611184600_create_user_sessions` | OK | `create_table` novo |
| 27 | `20260616120001_add_icon_to_teams` | OK | `add_column` (timestamp corrigido) |
| 28 | `20260617000000_add_exclude_older_than_hours_to_assignment_policies` | OK | `add_column` |
| 29 | `20260620000000_create_captain_message_reports` | OK | `create_table` novo |
| 30 | `20260623000000_add_draft_columns_to_articles` | OK | `add_column` |
| 31 | `20260630000001_add_sender_created_index_to_messages` | OK | `add_index` (timestamp corrigido) |
| 32 | `20260702000000_expand_data_imports_for_intercom_imports` | OK | `change_table bulk` só aditivo |
| 33 | `20260702000001_create_data_import_items` | OK | `create_table` novo |
| 34 | `20260702000002_create_data_import_mappings` | OK | `create_table` novo |
| 35 | `20260702000003_create_data_import_errors` | OK | `create_table` novo |
| 36 | `20260709091147_create_agent_sessions` | OK | `create_table` novo |
| 37 | `20260710000000_change_captain_assistant_description_to_text` | OK | `string → text` alarga, não trunca |
| 38 | `20260713184351_create_captain_faq_suggestions` | OK | `create_table` novo (é o destino da migração que falta — ver 2.2) |
| 39 | `20260718000000_add_phone_number_health_to_channel_whatsapp` | OK | `add_column` |

### 2.2 DADO nº 1 — `purge_pending_captain_assistant_responses`: CONFIRMADO e AMPLIADO

O achado do coordenador está correto, e é **maior** do que a migration sozinha. O fluxo inteiro de FAQ
pendente do ChatSPX foi desmontado em quatro pontos, e é a **combinação** que apaga dado sem substituto:

**(a) O enum perdeu o estado.** `enterprise/app/models/captain/assistant_response.rb:47`:

```diff
- enum status: { pending: 0, approved: 1 }     # NOSSO
+ enum status: { approved: 1 }                 # MERGE (= upstream)
```

**(b) O produtor do dado sumiu.** `enterprise/app/services/captain/llm/conversation_faq_service.rb`
(triagem: **PEGOU_DELES**). Em NOSSO, linha 66, `save_new_faqs` gravava a FAQ como pendente:

```ruby
assistant.responses.create!(
  question: faq['question'],
  answer: faq['answer'],
  status: 'pending',          # ← revisão humana antes de aprovar
  documentable: conversation
)
```

No MERGE esse método não existe mais: o upstream reescreveu o serviço inteiro para gravar em
`captain_faq_suggestions` + `captain_faq_observations` (tabelas novas, migration nº 38 acima).
`git grep "status: 'pending'"` em `enterprise/` no MERGE → **nenhuma ocorrência**.

**(c) A tela sumiu.** `app/javascript/dashboard/routes/dashboard/captain/responses/Pending.vue` foi
apagada (achado nº 2 do coordenador — arquivo fora da minha área, mas é a mesma cadeia). Em NOSSO ela
buscava `{ page, status: 'pending' }` (`Pending.vue:125`) e havia rota
`captain_assistants_responses_pending` (`captain.routes.js:69-71`) e badge de contagem
(`responses/Index.vue:42,271`).

**(d) A migration deleta.** `DELETE FROM captain_assistant_responses WHERE status = 0`, com `def down; end`
— **irreversível**.

Resultado líquido: a FAQ pendente que a frota tem gravada hoje fica **órfã** (nenhum código a lê,
nenhuma UI a mostra, o enum não a reconhece) e depois é **apagada**. O upstream não precisou de
migração porque no upstream `status = 0` nunca foi um estado válido — é lixo. No fork é dado de cliente.

**VEREDITO: DADO — máxima prioridade.** Correção proposta em §C-1: substituir o purge por uma
**migração** para `captain_faq_suggestions`, e só então limpar.

### 2.3 DADO nº 2 (novo) — `enqueue_validate_openai_hooks_job` destrói integrações de IA da frota

`db/migrate/20260515000000_enqueue_validate_openai_hooks_job.rb`:

```ruby
def up
  Migration::ValidateOpenaiHooksJob.perform_later
end
```

`app/jobs/migration/validate_openai_hooks_job.rb:10-18`:

```ruby
scope.find_each do |hook|              # Integrations::Hook.where(app_id: 'openai', status: 'enabled')
  next if Integrations::Openai::KeyValidator.valid?(hook.settings&.dig('api_key'))
  AdministratorNotifications::IntegrationsNotificationMailer.with(account: hook.account).openai_disconnect.deliver_later
  hook.destroy!                        # ← APAGA a integração da conta, com as settings dentro
end
```

`Integrations::Openai::KeyValidator.valid?` (`app/.../key_validator.rb`) faz `GET {api_base}/models` com
`Bearer <api_key>` e considera inválido **qualquer resposta 401**; `api_base` vem de
`InstallationConfig['CAPTAIN_OPEN_AI_ENDPOINT']` ou, na ausência, `https://api.openai.com/v1`.

Por que isso é DADO e não housekeeping, na frota ChatSPX especificamente:

1. `Integrations::Hook` de `openai` guarda a chave e as configurações da conta em `settings`.
   `destroy!` apaga o registro — **não há `down`, não há backup, e o job roda assíncrono**, fora da
   transação da migration.
2. Toda conta cuja chave OpenAI tenha sido rotacionada/revogada (situação normal em frota de cliente,
   e a razão de o upstream ter escrito isso) perde a integração inteira em vez de só ficar com uma
   chave inválida — e o admin recebe um e-mail de "desconectado" que ninguém pediu.
3. O risco é maior no fork por causa do endpoint: se alguma VM aponta `CAPTAIN_OPEN_AI_ENDPOINT` para
   um gateway/proxy que responde 401 a `GET /v1/models` (comum em gateways que só liberam
   `/chat/completions`), **as chaves válidas são classificadas como inválidas e todas as integrações
   da VM são apagadas de uma vez**.

Mitigação parcial que existe no código: `rescue Faraday::Error` → `true` (erro de rede não destrói).
Isso cobre timeout e DNS, **não** cobre 401.

**VEREDITO: DADO.** Correção proposta em §C-2 (neutralizar a migration e rodar o job em modo relatório
antes de deixá-lo destruir).

### 2.4 RISCO — `backfill_edited_on_captain_assistant_responses`

```ruby
Captain::AssistantResponse
  .where('updated_at - created_at > make_interval(days := ?)', 15)
  .in_batches(of: 1000) { |batch| batch.update_all(edited: true) }
```

A heurística ("se passaram >15 dias entre criação e última atualização, então um humano editou") é
declaradamente arbitrária — o próprio comentário do upstream diz isso. No fork ela é **mais** frágil,
porque `Captain::AssistantResponse` tem `after_commit :update_response_embedding`
(`assistant_response.rb:39`): qualquer reprocessamento de embedding toca `updated_at` sem que humano
nenhum tenha editado. Toda FAQ criada há mais de 15 dias e reindexada depois é marcada `edited = true`.

Não destrói conteúdo (só um booleano novo), e o campo hoje só alimenta rotulagem na UI do upstream.
Por isso **RISCO**, não DADO. Correção proposta em §C-4 (transformar em no-op: `edited` fica `false`
para o legado, que é a verdade conhecida, em vez de um palpite).

### 2.5 RISCO — `rename_company_condition_key_in_automation_rules`

Reescreve, com `update_column` (sem validação, sem callback, sem `updated_at`):

- `automation_rules.conditions`, trocando `attribute_key: 'company'` → `'company_name'` em toda condição
  cujo `custom_attribute_type` seja blank e `attribute_model ∈ [nil, '', 'standard']`;
- `custom_filters.query['payload']`, idem, para filtros de contato.

Por que merece atenção no fork: `companies` é flag **nossa** (bit 58 de `feature_flags`, adicionada por
nós — não existe no BASE) e o ChatSPX tem motor de automação próprio (Flows) convivendo com
`automation_rules` em "modo antigo". A migration é **conservadora** (a guarda
`standard_company_condition?` exclui custom attributes) e **idempotente** (rodar duas vezes não muda
nada, porque a segunda passada não encontra mais `'company'`). O que ela não tem é `down`.

O ponto de atenção real: se alguma regra da frota usa `attribute_key: 'company'` com semântica de
**custom attribute** mas gravada sem `custom_attribute_type` preenchido, ela será renomeada para um
atributo que não existe e a regra **para de casar silenciosamente**. É verificável antes do deploy
(§C-5) e barato de checar.

**VEREDITO: RISCO.**

### 2.6 RISCO / trava de deploy — `add_inbox_scope_to_email_templates`

```ruby
def ensure_no_duplicate_installation_templates!
  duplicates = select_values(<<~SQL) # name, template_type, locale com account_id IS NULL e COUNT(*) > 1
  ...
  raise ActiveRecord::IrreversibleMigration, "Duplicate installation email templates must be resolved..."
end
```

A migration **aborta o `db:migrate`** se a instalação tiver templates de e-mail de escopo global
duplicados por `(name, template_type, locale)`. O ChatSPX tem locale pt_BR próprio e templates
customizados; duplicata é plausível. Se acontecer, o deploy para **no meio da fila de migrations** —
com as anteriores já aplicadas. É trava, não corrupção. Verificação prévia em §C-6.

### 2.7 RISCO — `enable_assignment_v2_for_new_accounts` + `assignment_v2: enabled false → true`

Duas mudanças que só fazem sentido juntas:

- `config/features.yml`: `assignment_v2` mudou de `enabled: false` (NOSSO) para `enabled: true` (MERGE);
- a migration liga `assignment_v2` no `ACCOUNT_LEVEL_FEATURE_DEFAULTS` do `InstallationConfig`.

Efeito: **toda conta criada depois do deploy nasce com o motor de atribuição v2 ligado.** Contas
existentes não são tocadas (a migration só mexe no default). O ChatSPX tinha esse flag em `false`
deliberadamente — é a diferença entre o round-robin clássico e o motor v2 com assignment policies.

Agrava: `enterprise/app/models/enterprise/account.rb:119-123` mantém `advanced_assignment` em
auto-sync com `assignment_v2` (liga se plano Business/Enterprise, desliga se `assignment_v2` cai). Ou
seja, ligar `assignment_v2` por default também passa a ligar `advanced_assignment` em contas de plano
pago novas — e `advanced_assignment` é justamente o flag que **só agora** passou a ser gravável
(era o bit 65, ver §1.3).

**VEREDITO: RISCO** — decisão de produto, não bug de merge. Precisa de escolha explícita (§C-7).

### 2.8 RISCO / trava de deploy — `change_captain_document_external_link_to_text`

```ruby
remove_index :captain_documents, name: 'index_captain_documents_on_assistant_id_and_external_link', if_exists: true
change_column :captain_documents, :external_link, :text, null: false
add_index :captain_documents, 'assistant_id, md5(external_link)', unique: true, name: '...md5', if_not_exists: true
```

Dois modos de falha na frota:

1. `null: false` — se existir `captain_documents.external_link IS NULL` (documento criado por upload de
   PDF, por exemplo, em vez de crawl de URL), o `change_column` falha e o `db:migrate` para.
2. O índice unique novo é sobre `md5(external_link)`. O índice antigo era sobre o texto e, sendo
   `string`, estava limitado a 255 caracteres; o novo cobre o link **inteiro**. Dois documentos do mesmo
   assistant cujas URLs só diferiam **depois** do byte 255 passavam pelo índice antigo e **colidem** no
   novo → `PG::UniqueViolation`, `db:migrate` para.

Verificações prévias em §C-8. Ambos são trava, não perda de dado.

### 2.9 RISCO — `backfill_agent_bot_and_channel_api_secrets`

Gera `SecureRandom.urlsafe_base64(24)` para todo `AgentBot` e `Channel::Api` com `secret` nulo. Não
sobrescreve segredo existente. Não destrói dado. O que muda é o **contrato de webhook**: passa a existir
um segredo por bot/canal que o upstream usa para assinar payload. Na frota ChatSPX há consumidores
externos de webhook de Channel::Api e AgentBot (WAHA, n8n). Se algum ponto do código passar a **exigir**
assinatura válida, esses consumidores quebram — não por causa da migration, mas do código que vem com
ela. Isso é verificação para o auditor da área `app/` (`HookJob`, `AgentBotListener`,
`WebhookListener`); registro aqui como pendência cruzada, com o veredito **RISCO**.

---

## PARTE 3 — CAPTAIN e LLM

Método aplicado a todos: extração das linhas que NÓS adicionamos (`git diff BASE NOSSO | grep '^+'`,
normalizadas por whitespace) e verificação de presença uma a uma no MERGE. A taxa de sobrevivência
mecânica está na coluna "surv" da tabela final (§PARTE 6).

### 3.1 PERDA — `enterprise/lib/captain/prompts/assistant.liquid` (prompt em produção na frota)

Sobrevivência mecânica: **23%** (16 de 21 linhas nossas sumiram). O merge tomou a estrutura do upstream.
Nem toda perda é real — parte migrou para outro arquivo nosso, e é preciso separar:

**Perdas que NÃO são perdas** (a informação foi para `runtime_context.liquid`, que é NOSSO — commits
`1f59794f7a feat(captain): injeta o horário de funcionamento do config no prompt` e
`e785949cea feat(captain): prompt caching Anthropic pra cortar custo de input`, e sobreviveu ao merge
intacto, renderizado por `agentable.rb:174` via `Captain::PromptRenderer.render('runtime_context', ...)`):

- bloco `# Data e hora atual` (`current_datetime`, `business_status`) → `runtime_context.liquid:1-8`
- bloco `# Horário de funcionamento` (`business_hours_text`) → `runtime_context.liquid:9-11`

Isso é o design de **prompt caching**: prefixo estável em `assistant.liquid`, parte volátil em
`runtime_context.liquid`. Correto. **Não corrigir.**

**Perda REAL — 7 das 13 regras de `# Conduta no atendimento (sempre)`.** O MERGE as reduziu a três
bullets em inglês (`# Shared Response Conduct`, `assistant.liquid:24-27`) e a um snippet novo do
upstream `snippets/core_rules.liquid` (arquivo que **não existe em NOSSO**; conferido:
`git cat-file -e NOSSO:...snippets/core_rules.liquid` → NÃO). Cruzando as 13 regras nossas contra o
que o MERGE oferece:

| regra nossa (pt-BR, produção) | coberta no MERGE? | onde |
|---|---|---|
| nunca inventar fatos/nomes/endereços/valores/links | **sim** | `assistant.liquid:25` + `core_rules.liquid:2` |
| não narrar tools / não dizer que vai consultar e volta | **sim** | `assistant.liquid:26` + `core_rules.liquid:3,10` |
| ser concisa, uma ou duas frases | **sim** | `core_rules.liquid:5` |
| responder no idioma do cliente | **sim** | `core_rules.liquid:6` |
| desambiguar perguntando, sem expor a busca | **parcial** | `core_rules.liquid:7` (pede a pergunta, não a discrição) |
| **pessoa pelo nome: não confirmar nem negar que existe/trabalha aqui** | **NÃO** | — |
| **nunca se passar por um atendente humano específico** | **NÃO** | — |
| **`[IGNORAR]` só em cobrança/desabafo puro; nunca silenciar reclamação com pergunta dentro** | **parcial/pior** | `assistant.liquid:27` cobre "closing or thanks" e "never ignore a complaint", mas perde a regra de que cobrança de espera **sem** pergunta deve ser silenciada |
| **não devolver ao cliente dados que ele mesmo enviou; não reproduzir anúncio/foto** | **NÃO** | — |
| **não pedir nota de avaliação; ignorar CSAT no histórico** | **NÃO** | — |
| **fechamento: "ok/obrigado/valeu" → `[IGNORAR]`; reperguntar no máximo 1×** | **parcial** | `assistant.liquid:27` tem o `[IGNORAR]` de fechamento, perde o limite de 1 repergunta |
| **ping de presença na espera: responder 1× curto, do 2º em diante `[IGNORAR]`** | **NÃO** | — |
| tom direto, não anunciar o que entendeu | **NÃO** | — |

**VEREDITO: PERDA.** São regras que existem porque a IA errou em produção sem elas. Nenhum teste
acusa — é exatamente o cenário que a task antecipou. Correção em §C-3 (reinjetar as 7 regras como
snippet próprio, preservando a refatoração do upstream).

**RISCO acoplado, e grave: o merge inverteu a política de handoff.** NOSSO (e o BASE):

```
### For Questions and Information Requests
3. **If unable to answer**: Use `captain--tools--handoff` tool to transfer to a human expert
```

MERGE (`assistant.liquid:66-71` e `core_rules.liquid:11`): handoff passa a ser **consent-first** — a IA
deve *perguntar* se o cliente quer falar com um atendente e só chamar `captain--tools--handoff` depois
que ele **pedir ou aceitar**. Na frota isso significa que a IA deixa de escalar sozinha quando não sabe
responder, e passa a devolver uma pergunta. É mudança de comportamento de atendimento em toda a frota,
sem nenhum teste que a detecte. Decisão de produto — registrada em §C-3b, não corrijo por conta própria.

Ainda: `core_rules.liquid:9` traz `Do not use lists, markdown, bullet points, numbered steps, or other
formatting that is not typically spoken` — regra escrita para o canal de **voz** do upstream, agora
aplicada a **todo** assistant, inclusive WhatsApp/web. RISCO de formatação (§C-3c).

### 3.2 PERDA — `enterprise/app/models/concerns/agentable.rb`: `agent_model` perdeu as duas salvaguardas

Sobrevivência 95%, mas as linhas que sumiram são as que importam. Em NOSSO:

```ruby
def agent_model
  raw = account&.captain_assistant_model.presence || LlmConstants::DEFAULT_MODEL
  Llm::Models.runtime_id_for(raw)          # ← tradução alias → id de runtime
end
```

No MERGE (`agentable.rb:36-41`):

```ruby
def agent_model
  route = Llm::FeatureRouter.resolve(feature: 'assistant', account: account)
  return route[:model] if route[:source] == :account_override || account&.feature_enabled?('captain_integration_v2')
  installation_model.presence || route[:model]
end
```

Duas coisas se perderam no caminho, e as duas têm consequência funcional:

**(a) `Llm::Models.runtime_id_for` desapareceu deste caminho.** O método existe e é NOSSO — o comentário
que o documenta (`lib/llm/models.rb:36-42`, em pt-BR) explica exatamente por quê: o `llm.yml` guarda o
modelo com **ponto** (`claude-sonnet-4.5`, branding comercial e o que o usuário vê na UI) enquanto o
RubyLLM só conhece a forma com **hífen** (`claude-sonnet-4-5`). `agent_model` alimenta
`Agents::Agent.new(model:)`, e a gem `ai-agents 0.12.0` passa esse valor direto para
`RubyLLM.chat(model:)` (`ai-agents-0.12.0/lib/agents/runner.rb:107`) com `assume_model_exists: false`
(default, `agent.rb:69`) — isto é, **com validação no registry**. Resultado: qualquer conta cujo modelo
de assistant seja um Claude do nosso `llm.yml` faz o Captain levantar `RubyLLM::ModelNotFoundError`.
O `llm.yml` do MERGE oferece `claude-haiku-4.5` e `claude-sonnet-4.5` na lista de `assistant`, então é
alcançável pela UI de preferências.

**(b) O fallback por suporte de runtime desapareceu.** `Llm::BaseAiService#model_for_feature` (que o
merge preservou e até melhorou) protege o caminho dos services com
`Llm::Models.first_runtime_supported(*candidates)` — se o modelo preferido não existir no runtime, cai
para o próximo. `agent_model` **não tem** esse guarda-chuva. E o modelo que ele escolhe para toda conta
com `captain_integration_v2` é `Llm::FeatureRouter::CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'`
(`lib/llm/feature_router.rb:4,32-36`) — um modelo que **nós havíamos deliberadamente removido do
`llm.yml`** (o `git diff BASE NOSSO` de `config/llm.yml` apaga `gpt-5.1` e `gpt-5.2`) e que o merge
reintroduziu. `captain_integration_v2` é ligado em `enterprise/app/models/enterprise/account.rb:111`
e em `reconcile_plan_features_service.rb:41`, ou seja está ligado na frota.

Consequência combinada: **toda conta da frota com `captain_integration_v2` passa a rodar o Captain em
`gpt-5.2`, sem fallback.** Se a chave OpenAI da VM não tem acesso a esse modelo, o Captain para de
responder — e o caminho dos services (que tem fallback) continua funcionando, o que torna o sintoma
confuso de diagnosticar. **VEREDITO: PERDA + RISCO alto.** Correção em §C-9.

**RISCO — temperatura default mudou.** `agentable.rb:11`:

```diff
- temperature: temperature.to_f || 0.7,                        # NOSSO
+ temperature: temperature.presence&.to_f || DEFAULT_TEMPERATURE,   # MERGE, DEFAULT_TEMPERATURE = 0.5
```

O merge conserta um bug real (em Ruby `nil.to_f` é `0.0`, e `0.0 || 0.7` é `0.0` — o `|| 0.7` nunca
executava), mas **muda o comportamento em produção**: onde `temperature` estiver nulo/vazio, a IA sai de
`0.0` (determinística, que é o que a frota roda hoje) para `0.5`. Isso é perceptível na fala do
assistente. **RISCO** — precisa decisão, não conserto silencioso (§C-10).

**PERDA (pequena, concreta) — fuso horário default.** `agentable.rb:63-65`:

```diff
- tz = ActiveSupport::TimeZone[bh['timezone'].presence || 'America/Cuiaba'] || ActiveSupport::TimeZone['UTC']
+ timezone = bh['timezone'].presence || account&.reporting_timezone.presence
+ tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone['UTC']
```

Usar `account.reporting_timezone` é conceitualmente melhor (multi-tenant). O que se perdeu é o
**fallback**: conta sem `business_hours.timezone` **e** sem `reporting_timezone` cai em `TimeZone[nil]`
→ nil → **UTC**, e a IA passa a informar horário 3–4 h adiantado. Antes caía em `America/Cuiaba`.
Correção de uma linha em §C-11.

**RISCO — hora duplicada e em dois idiomas no prompt.** O merge acrescentou
`current_time: format_current_time(state[:timezone])` (`agentable.rb:24`) e
`{% render 'current_time', current_time: current_time %}` em `assistant.liquid:20`; nosso
`runtime_context.liquid` continua injetando `current_datetime`. `format_current_time` usa
`strftime('%A, %B %d, %Y %I:%M %p %Z')` → **inglês** ("Monday, August 17, 2026 12:00 PM"), enquanto
`current_datetime` é pt-BR ("segunda-feira, 17/08/2026 às 12:00"). A IA recebe a hora **duas vezes, em
dois idiomas e dois formatos**. Não quebra, mas é ruído no prompt e contraria a diretriz pt-BR.
Correção em §C-12.

Do lado positivo, o merge acertou em `VOLATILE_PROMPT_KEYS`, que **expandiu** corretamente para
incluir as chaves novas — sem isso o prompt caching cacheria a hora:

```diff
- VOLATILE_PROMPT_KEYS = %w[current_datetime business_status conversation contact campaign]
+ VOLATILE_PROMPT_KEYS = %w[current_time current_datetime business_status business_hours_text conversation contact campaign]
```

E tornou defensivos os dois `is_a?(Captain::Assistant) ? self : assistant` (agora
`(assistant if respond_to?(:assistant))` + `return {} unless asst`). **OK.**

### 3.3 OK — `enterprise/app/services/llm/base_ai_service.rb` (91%)

As 4 linhas "sumidas" foram **substituídas por versões melhores**, não perdidas:
`initialize(account:)` → `initialize(feature:, account:, fallback_model:)`; `model_for_feature` ganhou
cadeia de candidatos explícita `[override_de_conta, fallback, installation_model, route, *candidatos]`
e continua terminando em `Llm::Models.first_runtime_supported(*candidates)` — nosso guarda-chuva de
runtime **preservado**. `chat` manteve `Llm::Models.runtime_id_for(selected_model)`.
Uma melhoria nossa foi mantida e outra ganhou reforço (`runtime_supported_model?` agora também exige
`models.key?(model_id)`, `lib/llm/models.rb:27`). **VEREDITO: OK.**

### 3.4 `config/llm.yml` — RISCO (defaults de IA da frota trocados)

Sobrevivência 91%. O que o ChatSPX havia decidido e o merge reverteu:

| chave | NOSSO | MERGE | veredito |
|---|---|---|---|
| `features.assistant.default` | `gpt-5-mini` | **`gpt-4.1`** | **PERDA** (default nosso revertido para o do upstream) |
| `features.copilot.default` | `gpt-5-mini` | **`gpt-4.1`** | **PERDA** |
| `features.audio_transcription` | `models: [whisper-1]`, `default: whisper-1` | `[gpt-4o-mini-transcribe, whisper-1]`, default **`gpt-4o-mini-transcribe`** | **RISCO** — troca o modelo de transcrição de áudio de toda a frota |
| `models.gpt-5.1`, `models.gpt-5.2` | **removidos por nós** | reintroduzidos | **RISCO** |
| `features.conversation_faq_generation.default` | (não existia) | `gpt-5.2` | **RISCO** |
| `features.help_center_article_generation.default` | (não existia) | `gpt-5.2` | **RISCO** |
| `models.claude-sonnet-4`, `models.claude-opus-4` | adicionados por nós | **mantidos** | OK |
| `providers:` (NOSSO consertou o typo `aproviders:` do upstream) | `providers` | `providers` | OK |

O `git diff BASE NOSSO` mostra que nós **renomeamos** `gpt-5.1` → `gpt-5` e **apagamos** `gpt-5.2`, e
tiramos o `coming_soon` dos Claude — o padrão de quem alinhou o `llm.yml` ao que a chave da frota
realmente tem acesso. O merge desfez isso e ainda promoveu `gpt-5.2` a **default** de duas features
novas. Como `Llm::Models.first_runtime_supported` protege o caminho dos services, o efeito prático é
degradação silenciosa (cai para o próximo candidato) — exceto em `agent_model`, que não tem fallback
(§3.2). Correção em §C-13.

### 3.5 CORREÇÃO À §3.1 — `business_status` e `business_hours_text` NÃO chegam ao prompt no caminho default

Ao verificar como `runtime_context.liquid` entra no prompt, encontrei uma condição que muda o veredito
da §3.1 para pior. `agentable.rb:17-34`:

```ruby
def agent_instructions(context = nil)
  ...
  return split_instructions_for_cache(enhanced_context) if prompt_cache_system_enabled?   # ← linha 31
  Captain::PromptRenderer.render(template_name, enhanced_context.with_indifferent_access)  # ← linha 33
end
```

`runtime_context.liquid` só é renderizado dentro de `split_instructions_for_cache`
(`agentable.rb:174`), isto é **somente quando o prompt caching está ligado**. E
`prompt_cache_system_enabled?` é **opt-in**, com default **OFF** — exige
`account.custom_attributes['prompt_cache_system'] = true` ou `ENV['SPX_PROMPT_CACHE_SYSTEM']`
(o comentário do próprio método diz "Default (nenhum dos dois) = OFF").

Portanto, no caminho que a frota roda hoje (caching desligado), só `assistant.liquid` /
`scenario.liquid` são renderizados. E o MERGE tirou de lá os blocos de disponibilidade:

- **`business_status`** ("O atendimento está aberto/fechado") — **não chega mais ao prompt**;
- **`business_hours_text`** ("O horário de atendimento é: …") — **não chega mais ao prompt**;
- `current_time` chega, mas via `snippets/current_time.liquid`, em inglês.

Isso desfaz exatamente o que o commit `1f59794f7a feat(captain): injeta o horário de funcionamento do
config no prompt` entregou. A IA volta a não saber se está dentro ou fora do horário — o problema que
o comentário do `time_awareness` documenta ("pra o agente não adivinhar/alucinar horário (ex: dizer
'volta segunda' numa quarta)"). `time_awareness` continua **calculando** os dois valores
(`agentable.rb:85-87`), e `VOLATILE_PROMPT_KEYS` continua listando-os: são produzidos e descartados.

**VEREDITO: PERDA** (eleva a §3.1 de "perda de regras de conduta" para "perda de regras de conduta +
perda da consciência de horário"). Correção em §C-14.

### 3.6 PERDA — `enterprise/lib/captain/tools/handoff_tool.rb`: o merge reintroduziu o bug que o comentário nosso descreve

Sobrevivência 77%. A `description` do tool — que é o texto que o LLM lê para decidir se chama o
handoff — foi substituída pela do upstream:

```diff
-  description 'Passa a conversa para um ATENDENTE HUMANO do time assumir. Use quando já ' \
-              'qualificou o cliente e é hora de uma pessoa continuar: ele quer visitar, ' \
-              'agendar ou fechar; pediu falar com um humano; o assunto exige uma pessoa ' \
-              '(jurídico, uma ação que você não executa); ou você não conseguiu resolver. ' \
-              'A IA continua respondendo normalmente até um humano assumir.'
+  description 'Hand off the conversation to a human agent only when the customer requests human assistance, ' \
+              'accepts an offer to speak with a human, an account-specific guideline requires transfer, or the ' \
+              'request requires an action the assistant cannot perform. Continue assisting until a human takes over.'
```

O que torna isto inequívoco é que **o comentário que explica por que a descrição antiga era ruim
sobreviveu, três linhas acima da descrição nova** (`handoff_tool.rb:1-6`):

```ruby
  # ... A descrição antiga ("when unable to
  # assist further") fazia a IA quase nunca chamar o tool (uma IA que está atendendo bem nunca
  # se considera "unable to assist"), então nenhum lead chegava ao humano.
```

A descrição que o merge instalou é do mesmo tipo que o comentário condena, e mais restritiva ainda
("**only when** the customer requests… accepts…"). O arquivo agora se autocontradiz: o comentário
documenta a correção, o código abaixo dele é a regressão. Efeito de negócio: **lead qualificado deixa
de chegar ao humano** (era o motivo declarado da mudança) e o handoff passa a depender de o cliente
pedir. Casa com a inversão de política do prompt (§3.1) — os dois pontos precisam ser corrigidos juntos.

O resto do arquivo está **OK**: `trigger_handoff` ganhou `tool_context` e captura de `handoff_note_id`
(upstream legítimo), e a chamada a `Captain::Conversation::HumanHandoffService` — nossa fonte única,
reusada pelo `FollowupJob` — sobreviveu. O comentário sobre modo "time fixo" perdeu apenas a menção
"(ex.: Tozi → recepção)", que é cosmético.

**VEREDITO: PERDA.** Correção em §C-15.

### 3.7 PERDA — `response_builder_job.rb`: produtor vivo, consumidor apagado

Sobrevivência 87% — 35 de 271 linhas nossas sumiram, e são as do bloco de saneamento da resposta. O
merge integrou bem a evolução do upstream (`V1ActionClassifier`, `V1FalsePromiseHandler`,
`MessageBuilder`, `SessionCaptureService`, `v2_handoff_tool_fired?`, `preserve_waiting_since`,
`report_v1_handoff_not_executed`) e preservou o nosso núcleo (`conversation_pending?`,
`captain_can_respond?`, `ensure_handoff_if_promised`, `auto_schedule_followup`,
`send_humanized_response`, `wait_for_dispatch`). O que ele levou embora foi o anti-alucinação:

**(a) `fix_property_links` foi apagado inteiro** — método e chamada:

```diff
   def sanitize_for_whatsapp(content)
     return content if content.blank?
-    content = fix_property_links(content)
     content.gsub(/\[\s*(ignorar|sem[\s_-]?resposta|no[\s_-]?reply)\s*\]/i, '')
```

```diff
-  def fix_property_links(content)
-    return content unless content.match?(/toziimoveis/i)
-    mapa = @conversation.reload.custom_attributes&.dig('urls_imoveis') || {}
-    content.gsub(%r{https?://[^\s)\]]*toziimoveis\.com\.br[^\s)\]]*}i) do |url|
-      match = url.scan(/\d+/).find { |n| mapa.key?(n) }
-      match ? mapa[match] : ''
-    end
-  end
```

A prova de que isto é acidente e não decisão: **o produtor do dado continua no repositório e o
comentário dele descreve o consumidor que foi apagado.** `enterprise/lib/captain/tools/buscar_imovel_tool.rb:125-127`:

```ruby
  # Guarda o mapa codigo/ImoCodigo -> URL canônica (build_url) na conversa (urls_imoveis),
  # pra o sanitizador de saída (fix_property_links) manter os links que a IA manda e remover
  # só os inventados. Sem isso, urls_imoveis fica vazio e TODO link da Tozi é apagado.
```

`git grep fix_property_links` no MERGE devolve **só esse comentário** — a implementação não existe mais.
Consequência direta em produção: a IA da Tozi volta a enviar ao cliente final **URL de imóvel
inventada** (o LLM monta `/imovel/...-3338` em vez do formato `...,ImoCodigo`), que era exatamente o
bug que o método corrigia.

**(b) `property_code` deixou de identificar a foto no histórico:**

```diff
   def outgoing_attachment_placeholder(message)
     return '' unless message.attachments.any?
-    code = message.additional_attributes&.dig('property_code')
-    code.present? ? "[foto do imóvel #{code} enviada]" : '[foto do imóvel enviada]'
+    '[attachment sent]'
   end
```

```diff
   def quoted_description(quoted)
     ...
-    code = quoted.additional_attributes&.dig('property_code')
-    return "foto do imóvel #{code}" if code.present?
-    quoted.attachments.any? ? 'uma foto enviada anteriormente' : ''
+    quoted.attachments.any? ? 'a previously sent attachment' : ''
   end
```

Mesmo padrão: o produtor sobreviveu — `enterprise/lib/captain/tools/enviar_fotos_imovel_tool.rb:147` e
`:197` continuam gravando `additional_attributes: { 'property_code' => codigo }`, e o comentário da
linha 190 explica por quê ("sem isso a foto e um outgoing…"). O consumidor virou `[attachment sent]`,
igual para todas as fotos, e o efeito é o que o nosso comentário apagado descrevia: *"todas viram o
MESMO placeholder no historico e o modelo nao sabe qual imovel e qual ('esse e qual?')"*.

**(c) O regex de limpeza trocou de idioma e deixou o histórico legado passar.** Coerente com (b) — o
placeholder novo é em inglês — mas as mensagens **já gravadas** na frota contêm
`[foto do imóvel 3338 enviada]`:

```diff
-  .gsub(/\[\s*fotos?[^\]]*enviad[ao]s?\s*\]/i, '')   # remove o placeholder pt-BR
+  .gsub(/\[\s*attachments?\s+sent\s*\]/i, '')        # remove só o placeholder novo
```

Se o LLM ecoar o placeholder antigo (o motivo pelo qual o filtro existe), ele **vai literalmente para o
cliente**. A correção precisa manter os dois padrões.

**(d) Comentário técnico perdido, comportamento intacto.** O bloco que explicava por que cada bolha
commita sozinha ("Sem transacao envolvendo a rajada: cada bolha precisa COMMITAR pra disparar o
SendReplyJob… o wait_for_dispatch serializa o envio") foi removido, mas `create_messages` e
`wait_for_dispatch` continuam lá. É perda de conhecimento, não de comportamento — vale reinserir para
que ninguém "otimize" isso envolvendo em transação depois.

**VEREDITO: PERDA.** Correção em §C-16.

### 3.8 PERDA — `enterprise/lib/captain/prompts/scenario.liquid`

Mesmo padrão do `assistant.liquid`, e pela §3.5 é perda **efetiva** (não migrou para lugar nenhum no
caminho default):

```diff
-{% if current_datetime %}Agora é {{ current_datetime }} (horário de Sinop/MT). O atendimento está {{ business_status }}. Nunca invente o dia da semana nem se está aberto.
-{% endif %}
+{% render 'current_time', current_time: current_time %}
+{% render 'core_rules' %}
```

Os agentes de cenário — que são os que efetivamente atendem no modo multi-agente — perdem
`business_status`. Ganharam `core_rules` do upstream, o que é bom, mas com a inversão de handoff
embutida (§3.1). **VEREDITO: PERDA.** Correção junto com §C-14.

### 3.9 OK — `config/initializers/sentry.rb` (falso positivo da varredura mecânica)

A varredura acusou 1 linha nossa ausente; é reformatação. O merge converteu a lista para multi-linha e
**acrescentou** uma exceção:

```diff
-    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'Waha::ApiService::LidNotResolvable']
+    config.excluded_exceptions += [
+      'Rack::Timeout::RequestTimeoutException',
+      'Waha::ApiService::LidNotResolvable',
+      'MutexApplicationJob::LockAcquisitionError'
+    ]
```

Nossos dois silenciamentos (o que estanca o GlitchTip da frota) estão de pé, e o comentário pt-BR sobre
`LidNotResolvable` também. **VEREDITO: OK.**

### 3.10 OK — `db/schema.rb`

Sobrevivência 99%: das 575 linhas que nós adicionamos, **1** não está no MERGE:

```
t.index ["name", "account_id"], name: "index_email_templates_on_name_and_account_id", unique: true
```

É exatamente o índice que `db/migrate/20260706000000_add_inbox_scope_to_email_templates.rb:6` remove de
propósito (`remove_index :email_templates, name: 'index_email_templates_on_name_and_account_id'`),
substituído pelos três índices parciais de escopo installation/account/inbox. **O schema bate com as
migrations e nenhuma coluna nossa desapareceu.** Confirmei também que `feature_flags_ext_1` está
declarado (`db/schema.rb:87`) e que **não** existe `feature_flags_ext_2` — coerente com
`Featurable::FEATURE_FLAG_COLUMNS` (§1.4). **VEREDITO: OK.**

---

## PARTE 4 — SPECS: qual contrato mudou (não conserto spec)

Os specs desta área que perderam linhas nossas são **sintoma**. Em cada caso, o contrato que mudou:

### 4.1 `spec/enterprise/lib/captain/tools/handoff_tool_spec.rb` — o teste foi trocado junto com a regressão

O assert que nós tínhamos desapareceu **e foi substituído por um que valida a descrição do upstream**
(`handoff_tool_spec.rb:15-16`):

```ruby
expect(tool.description).to include('only when the customer requests human assistance')
expect(tool.description).to include('accepts an offer to speak with a human')
```

Isto é o que torna a PERDA de §3.6 **silenciosa por construção**: a suíte não vai ficar vermelha, porque
o teste passou a afirmar o comportamento novo. Contrato mudado: **a descrição do handoff tool deixou de
ser a nossa (pt-BR, proativa) e virou a do upstream (inglês, consent-first)**. É o caso mais importante
desta parte, porque um executor que rodar a suíte e vê-la verde vai concluir, erradamente, que nada se
perdeu no handoff.

### 4.2 `preferences_controller_spec.rb` e `spec/lib/llm/models_spec.rb` — contrato: os defaults do `llm.yml`

Os asserts removidos eram os que **travavam** as nossas decisões de modelo:

```ruby
# preferences_controller_spec.rb (NOSSO)
it 'returns gpt-5-mini as default for assistant and copilot' do
  expect(json_response.dig(:features, :assistant, :default)).to eq('gpt-5-mini')
  expect(json_response.dig(:features, :copilot, :default)).to eq('gpt-5-mini')

# spec/lib/llm/models_spec.rb (NOSSO)
expect(described_class.runtime_supported_model?('gpt-5.1')).to be(false)
selected = described_class.first_runtime_supported('gpt-5.1', 'gpt-5.2', 'unknown-model')
expect(selected).to eq('gpt-5-mini')
```

Contrato mudado: `config/llm.yml` (§3.4) — `assistant.default`/`copilot.default` viraram `gpt-4.1` e
`gpt-5.1`/`gpt-5.2` voltaram a existir. Os specs não "quebraram": foram removidos porque a decisão que
eles protegiam foi revertida. **Consertar o spec sem consertar o `llm.yml` seria consagrar a reversão.**

### 4.3 `spec/enterprise/models/concerns/agentable_spec.rb` — contrato: resolução do modelo do agente

Perdemos os três casos que testavam `agent_model` via `account.captain_assistant_model`
(`double('Account', captain_assistant_model: 'gpt-4-turbo')`, "returns default model when account is
nil", etc.). Contrato mudado: `agent_model` não lê mais `captain_assistant_model`; passou a
`Llm::FeatureRouter.resolve` (§3.2).

O merge **trouxe** cobertura nova (`agentable_spec.rb:163-192`), inclusive do caminho
`CAPTAIN_V2_ASSISTANT_MODEL`. Mas os modelos exercitados são `gpt-5`, `gpt-4.1-nano` e o default —
**nenhum Claude**. Como a perda de §3.2(a) só se manifesta com modelo `claude-*` (o alias com ponto), a
suíte passa verde com o bug dentro. Registrado como lacuna de cobertura, não como spec a consertar.

### 4.4 `reconcile_plan_config_service_spec.rb` — contrato: quem gerencia `captain_integration`

Asserts removidos:

```ruby
expect(account.reload.enabled_features.keys).to include('captain_integration')
expect(account_with_captain.reload.enabled_features.keys).to include('captain_integration')
```

Contrato mudado, e é um achado de código, não de teste. A nossa customização em
`enterprise/app/services/enterprise/billing/handle_stripe_event_service.rb` era exatamente **remover
`captain_integration` da lista de features geridas pelo plano** (`git diff BASE NOSSO` daquele arquivo é
uma única linha: `-    captain_integration`). O merge reescreveu o serviço (53 inserções, 83 remoções),
extraiu as listas para `Enterprise::Billing::ReconcilePlanFeaturesService` — arquivo **novo do upstream**,
que não existia em NOSSO — e lá `captain_integration` está de volta
(`reconcile_plan_features_service.rb:15`, em `STARTUP_PLAN_FEATURES`).

O `perform` desse serviço começa com `account.disable_features(*PREMIUM_PLAN_FEATURES)`
(`:38`) e só religa conforme o plano. Efeito: em qualquer `customer.subscription.updated`, uma conta
que não esteja em plano Startups+ **tem `captain_integration` desligado**. Existe um escape
(`manually_managed_features`, `:42`, via `Internal::Accounts::InternalAttributesService`), mas ele exige
que cada conta esteja marcada — não é equivalente a ter tirado o flag da lista.

Alcance: só ambientes que recebem webhook do Stripe (o SaaS), não as VMs self-hosted da frota.
**VEREDITO: RISCO.** Os dois asserts removidos são a prova de que a customização existia e do que ela
protegia.

### 4.5 `incoming_message_whatsapp_cloud_service_spec.rb` — perda de cobertura, código intacto

Sumiu o bloco `context 'when message has a click-to-whatsapp referral'` inteiro (lead de anúncio
Meta: `referral.headline`, `source_url`, `image_url` em `content_attributes`) e o contraponto
`context 'when message has no referral (regression)'`.

**Verifiquei o código antes de classificar**: ele sobreviveu — `app/services/whatsapp/incoming_message_base_service.rb:180-181`
(`attrs[:referral] = referral_content_attrs if referral_content_attrs.present?`),
`app/services/whatsapp/incoming_message_service_helpers.rb:81-84` e o consumo no prompt em
`enterprise/app/services/captain/open_ai_message_builder_service.rb:100-105`. Logo é **RISCO (perda de
cobertura)**, não PERDA de comportamento: a feature CTWA funciona, mas nada mais a protege de uma
próxima regressão.

### 4.6 `spec/enterprise/listeners/captain_listener_spec.rb` — contrato: FAQ de conversa

Perdeu `instance_double(Captain::Llm::ConversationFaqService, generate_and_deduplicate: false)` e o
`it 'generates and deduplicates FAQs'`. Contrato mudado: o método público do serviço passou de
`generate_and_deduplicate` para `generate_suggestions`, junto com a reescrita do fluxo (§2.2). O spec
novo do upstream cobre o método novo. **OK** — é sintoma direto de §2.2, que já está tratado em C-1.

### 4.7 `bulk_auto_assignment_job_spec.rb` (APAGADO) e `spec/enterprise/models/conversation_spec.rb`

`Inboxes::BulkAutoAssignmentJob` **não existe mais** — nem no upstream (`git cat-file -e DELES:` do spec
→ NÃO), nem no MERGE (`app/jobs/inboxes/` só tem os jobs de IMAP e de widget). Foi substituído por
`AutoAssignment::PeriodicAssignmentJob` + `AutoAssignment::AssignmentJob`.

O que o nosso spec apagado protegia era a garantia "auto-assignment não rouba conversa do mirror bot do
Captain". **Essa garantia está implementada no motor novo**, em dois pontos, e um deles ainda tem o
nosso comentário:

```ruby
# app/services/auto_assignment/agent_assignment_service.rb:12
return if conversation.assignee_agent_bot_id.present? # nunca rouba conversa da IA (A2b)

# app/services/auto_assignment/assignment_service.rb:37
scope = inbox.conversations.unassigned.open.where(assignee_agent_bot_id: nil)
```

E **está coberta por spec** no caminho novo: `spec/services/auto_assignment/agent_assignment_service_spec.rb:34,41`
e `spec/services/auto_assignment/assignment_service_spec.rb:99,105,111` usam
`assistant.mirror_agent_bot`. **VEREDITO: OK** — o spec apagado ficou obsoleto junto com o job, e a
cobertura migrou. Mesma razão vale para a linha `Inboxes::BulkAutoAssignmentJob.perform_now` que sumiu
de `spec/enterprise/models/conversation_spec.rb`.

### 4.8 `response_builder_job_spec.rb` — cobertura estreitada

Nosso `it 'does not send a response when the conversation is no longer pending/open'` (caso genérico:
qualquer status fora de pending/open) foi substituído por
`it 'does not send a response when the conversation is snoozed'` (`:354`) — um único status. A lógica
(`captain_can_respond?`, com o `Conversation.uncached { ... pick(:status) }` que é nosso) sobreviveu
intacta no job. **RISCO (cobertura).**

### 4.9 `delete_notification_job_spec.rb` — contrato: assinatura do job

| | assinatura |
|---|---|
| NOSSO | `perform(user_id, type: 'all')` — sem escopo de conta, com `return unless user` |
| DELES / MERGE | `perform(user, account, type: :all)` — escopa por `account_id` |

O merge é **coerente ponta a ponta**: o job (`app/jobs/notification/delete_notification_job.rb:4`), o
chamador (`app/controllers/api/v1/accounts/notifications_controller.rb:44,46`) e o spec
(`:32,39`) usam a mesma forma. E o upstream corrige um bug nosso: a nossa versão apagava as notificações
do usuário em **todas as contas**, não só na conta corrente.

O que se perdeu é a defensividade: passar o objeto `User` em vez do id significa serialização por
GlobalID e `ActiveJob::DeserializationError` se o usuário for apagado antes do job rodar — nossa versão
fazia `User.find_by(id:)` + `return unless user`. **RISCO (baixo).**

---

## PARTE 5 — CONFIG restante

Auditados por varredura automática, todos com **100% das nossas linhas presentes** no MERGE:

| arquivo | linhas nossas | veredito |
|---|---|---|
| `config/routes.rb` | 145/145 | **OK** |
| `config/integration/apps.yml` | 69/69 | **OK** |
| `config/locales/pt_BR.yml` | 65/65 | **OK** |
| `config/locales/en.yml` | 61/61 | **OK** |
| `config/schedule.yml` | 51/51 | **OK** |
| `config/application.rb` | 9/9 | **OK** (inclui o `Rails.autoloaders.main.collapse` dos concerns em `enterprise/lib`) |
| `config/initializers/rack_attack.rb` | 8/8 | **OK** |
| `config/initializers/sentry.rb` | 2/2 (reformatado) | **OK** — §3.9 |
| `config/installation_config.yml` | 3/3 | **OK** |
| `config/features.yml` | 14/14 | **OK** — §1.1 |
| `config/llm.yml` | 11/12 | **PERDA** — §3.4 |

`AGENTS.md` (PEGOU_NOSSO, 212 linhas nossas) e `enterprise/app/models/enterprise/message.rb`
(PEGOU_NOSSO, 15 linhas) ficaram idênticos ao nosso lado: **OK**. No caso do `message.rb`, conferi que
descartar o lado do upstream é inócuo — o `git diff BASE DELES` daquele arquivo não traz mudança
funcional que nos falte.

### 5.1 Arquivo fora do TSV que precisa constar

`enterprise/app/models/captain/assistant_response.rb` **não está** em `area-ent.tsv` (a triagem não o
pegou), mas é onde mora o achado nº 1. Registro aqui:

| arquivo | classe triagem | veredito | o que se perdeu | evidência | correção |
|---|---|---|---|---|---|
| `enterprise/app/models/captain/assistant_response.rb` | (fora do TSV) | **DADO** | o estado `pending: 0` do enum, junto com a migration que apaga as linhas com esse status | `assistant_response.rb:47` (`enum status: { approved: 1 }`), era `{ pending: 0, approved: 1 }`; §2.2 | C-1 |

---

## CORREÇÕES PROPOSTAS, EM ORDEM DE GRAVIDADE

Nada abaixo foi aplicado. Não editei uma linha de código do worktree — a única escrita desta task é
este arquivo. Cada item traz o patch ou a instrução exata.

### C-1 · DADO · Migrar a FAQ pendente antes de apagá-la

**Substituir** `db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb` por uma
migração de dados. O purge do upstream só é correto onde `status = 0` é lixo; no fork é FAQ viva.

Passo 1 — reintroduzir o estado no enum, para que o legado continue legível durante a transição
(`enterprise/app/models/captain/assistant_response.rb:47`):

```diff
-  enum status: { approved: 1 }
+  # `pending` é legado do fork: FAQ gerada de conversa que aguardava revisão humana. O fluxo novo
+  # do upstream usa Captain::FaqSuggestion; mantido só até a migração 20260714123000 rodar.
+  enum status: { pending: 0, approved: 1 }
```

Passo 2 — trocar o corpo da migration por migração + purge, em SQL puro (não usar os modelos: o
`after_commit :update_embedding` do `Captain::FaqSuggestion` enfileiraria um job de embedding por
linha e gastaria crédito recalculando um vetor que já temos):

```ruby
class PurgePendingCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  # ChatSPX: status 0 NÃO é lixo — é FAQ pendente de revisão humana, gerada pelo
  # ConversationFaqService antes de o upstream trocar o fluxo por captain_faq_suggestions.
  # Migra para o fluxo novo (status open) preservando question/answer/embedding e o vínculo
  # com a conversa de origem, e só então apaga.
  def up
    execute(<<~SQL.squish)
      INSERT INTO captain_faq_suggestions
        (question, answer, embedding, assistant_id, account_id, language, source_count, status, created_at, updated_at)
      SELECT r.question,
             r.answer,
             r.embedding,
             r.assistant_id,
             r.account_id,
             COALESCE(NULLIF(split_part(replace(a.locale_name, '-', '_'), '_', 1), ''), 'pt'),
             1,
             0,
             r.created_at,
             r.updated_at
      FROM captain_assistant_responses r
      JOIN (SELECT id, 'pt' AS locale_name FROM accounts) a ON a.id = r.account_id
      WHERE r.status = 0
    SQL

    execute(<<~SQL.squish)
      INSERT INTO captain_faq_observations
        (account_id, conversation_id, faq_suggestion_id, generated_question, generated_answer,
         language, status, created_at, updated_at)
      SELECT r.account_id, r.documentable_id, s.id, r.question, r.answer, s.language, 0, r.created_at, r.updated_at
      FROM captain_assistant_responses r
      JOIN captain_faq_suggestions s
        ON s.assistant_id = r.assistant_id AND s.question = r.question AND s.answer = r.answer
      WHERE r.status = 0
        AND r.documentable_type = 'Conversation'
        AND r.documentable_id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL

    execute('DELETE FROM captain_assistant_responses WHERE status = 0')
  end

  def down; end
end
```

Notas de execução, porque isto mexe em dado de cliente:

- O `language` acima está fixado em `'pt'` de propósito. `accounts.locale` é um **enum inteiro**, não
  string — resolver o nome do locale em SQL puro exigiria replicar o mapa do enum. Como a frota é
  pt-BR (`reference_account_locale_ptbr`: `pt_BR = 16` é o default), `'pt'` é a resposta certa para
  todas as contas. Se alguma VM tiver conta em outro locale, trocar por um `Account.find_each` que
  chame `Captain::Llm::ConversationFaqService.language_for` — **mas então rodar em job, não na
  migration**.
- Não usar `dry_run` fictício: o modo de validar isto é rodar `up` **no banco de teste** e conferir a
  contagem antes/depois:
  `SELECT count(*) FROM captain_assistant_responses WHERE status = 0` deve virar `0`, e
  `SELECT count(*) FROM captain_faq_suggestions WHERE status = 0` deve ter aumentado **exatamente** por
  esse número.
- **Antes de rodar em qualquer VM da frota**, dump da tabela:
  `pg_dump -t captain_assistant_responses -a` — é o único rollback possível (`down` é vazio por
  construção, porque o `DELETE` é irreversível).

Passo 3 — a tela. `app/javascript/dashboard/routes/dashboard/captain/responses/Pending.vue` foi apagada
(achado nº 2, área `app/`). O fluxo novo do upstream tem UI própria para `faq_suggestions`; a decisão
é **usar a do upstream** e não restaurar a nossa, desde que a migração acima rode primeiro. Se a UI do
upstream não estiver completa, restaurar `Pending.vue` **não resolve** — ela consulta
`{ status: 'pending' }` em `captain_assistant_responses`, tabela que a migration esvazia. Este ponto
precisa ficar com o executor da área `app/`; registro aqui a dependência.

**Ordem obrigatória:** passo 1 → passo 2 → deploy. Rodar o purge antes de reintroduzir o enum não
quebra (é SQL puro), mas rodar o purge original apaga sem migrar.

### C-2 · DADO · Neutralizar o `ValidateOpenaiHooksJob` e rodá-lo primeiro em modo relatório

Substituir o corpo de `db/migrate/20260515000000_enqueue_validate_openai_hooks_job.rb`:

```diff
 class EnqueueValidateOpenaiHooksJob < ActiveRecord::Migration[7.1]
   def up
-    Migration::ValidateOpenaiHooksJob.perform_later
+    # ChatSPX: NÃO enfileirar automaticamente. O job faz `hook.destroy!` em Integrations::Hook
+    # de openai cuja chave devolva 401 em GET {CAPTAIN_OPEN_AI_ENDPOINT}/models — apagando a
+    # integração de IA da conta, com as settings dentro, sem rollback. Rodar manualmente por VM,
+    # depois de auditar o resultado em modo relatório. Ver onda-0-auditoria-enterprise.md §2.3.
   end
 
   def down; end
 end
```

E, para poder auditar antes de destruir, adicionar um modo relatório ao job
(`app/jobs/migration/validate_openai_hooks_job.rb`):

```diff
-  def perform(account: nil)
+  def perform(account: nil, dry_run: false)
     scope = Integrations::Hook.where(app_id: 'openai', status: 'enabled')
     scope = scope.where(account_id: account.id) if account
 
     stats = { checked: 0, destroyed: 0 }
 
     scope.find_each do |hook|
       stats[:checked] += 1
       next if Integrations::Openai::KeyValidator.valid?(hook.settings&.dig('api_key'))
 
+      if dry_run
+        Rails.logger.warn("[openai-backfill][dry-run] WOULD destroy hook_id=#{hook.id} account_id=#{hook.account_id}")
+        stats[:destroyed] += 1
+        next
+      end
+
       AdministratorNotifications::IntegrationsNotificationMailer.with(account: hook.account).openai_disconnect.deliver_later
```

Procedimento por VM, na ordem: (1) `Migration::ValidateOpenaiHooksJob.new.perform(dry_run: true)`;
(2) ler o log e conferir se os hooks listados são de fato chaves mortas — em especial se
`CAPTAIN_OPEN_AI_ENDPOINT` aponta para um gateway que possa devolver 401 em `/v1/models` mesmo com
chave boa; (3) só então rodar sem `dry_run`, ou corrigir as chaves e não rodar.

### C-3 · PERDA · Devolver as 7 regras de conduta que o `assistant.liquid` perdeu

Criar `enterprise/lib/captain/prompts/snippets/spx_conduct.liquid` (arquivo novo — preserva a
refatoração do upstream em vez de reverter o template):

```liquid
# Conduta no atendimento (ChatSPX)
- Se o cliente pedir por uma pessoa pelo nome, não confirme nem negue que ela existe ou trabalha aqui: acolha e encaminhe pelo assunto, sem prometer um nome específico.
- Nunca se passe por um atendente humano específico. Se o cliente perguntar se você é uma pessoa pelo nome (em geral o atendente que falou com ele antes), não confirme ser essa pessoa nem assuma a identidade dela; deixe claro com naturalidade que é outro atendente da equipe dando sequência, e siga ajudando.
- Use [IGNORAR] SOMENTE quando a mensagem for PURAMENTE cobrança ou desabafo da espera de um atendente humano, sem NENHUMA pergunta respondível. Se no meio da impaciência houver qualquer pergunta ou pedido que você consiga responder (horário, endereço, dúvida sobre um imóvel, etc.), responda essa pergunta normalmente — não silencie. Reclamação ou crítica ao atendimento NUNCA deve ser ignorada — responda e corrija, ou faça handoff.
- Seja direto e natural. Não abra a resposta anunciando o que entendeu nem o que vai fazer — vá ao ponto e conduza pro próximo passo. Não devolva ao cliente dados que ele mesmo enviou, nem reproduza o anúncio ou a foto que ele mandou.
- Ao desambiguar uma referência que tem mais de uma opção, pergunte de forma direta e local, nomeando as opções, sem expor que a informação veio de uma busca.
- Não peça nota de avaliação nem reproduza a pesquisa de satisfação do atendimento — ela é automática do sistema, não é sua fala. Ignore qualquer pesquisa desse tipo que apareça no histórico.
- Fechamento: quando o cliente só encerra ou agradece (ok, obrigado, valeu, blz, tá bom, tranquilo, show, perfeito, isso e afins) sem trazer nenhuma pergunta ou pedido novo, não responda de novo — responda apenas [IGNORAR] e fique em silêncio. Se ainda faltava a resposta dele a algo que você perguntou, você pode reperguntar no máximo uma vez; se ele só encerrar de novo, deixe quieto e responda [IGNORAR].
- Ping de presença na espera: depois que você já acionou o handoff ou avisou que um atendente vai assumir, se o cliente mandar só um cumprimento solto ou uma cobrança de presença (sem trazer pergunta nem pedido novo), responda UMA única vez, curto — reforçando que você está por aqui e quando o atendente ou o time retorna. Do segundo ping igual em diante (só cobrando presença, sem nada novo), responda [IGNORAR]. Se ele trouxer pergunta ou pedido novo, atenda normalmente.
```

E chamá-lo logo depois de `{% render 'core_rules' %}` em **`assistant.liquid`** e em
**`scenario.liquid`**:

```diff
 {% render 'core_rules' %}
+
+{% render 'spx_conduct' %}
```

O bloco `# Shared Response Conduct` que o merge trouxe pode ficar — ele não conflita, só é mais raso.

### C-3b · RISCO · Decidir sobre a inversão da política de handoff (**decisão de produto, não conserto**)

O merge trocado "escale quando não souber" por "pergunte e só escale se o cliente aceitar", em três
lugares que precisam andar juntos: `assistant.liquid:66-71`, `snippets/core_rules.liquid:11` e a
`description` do `HandoffTool` (C-15). Se a frota quer o comportamento antigo, os três voltam; se quer
o novo, C-15 não se aplica e o comentário de `handoff_tool.rb:1-6` deve ser **apagado** para o arquivo
parar de se contradizer. **Não decidi por conta própria** — é comportamento de atendimento com efeito
comercial direto (chegada de lead ao humano).

### C-3c · RISCO · `core_rules.liquid:9` proíbe formatação em todos os canais

```
- Do not use lists, markdown, bullet points, numbered steps, or other formatting that is not typically spoken.
```

É regra de canal de **voz**, aplicada agora a todo assistant, WhatsApp e web inclusive. Se não se quer
isso, condicionar o snippet ou remover a linha. Baixa gravidade, mas muda o formato de toda resposta.

### C-14 · PERDA · Fazer `business_status` e `business_hours_text` voltarem ao prompt

É o item que o §3.5 elevou: com `prompt_cache_system_enabled?` em **OFF** (o default), nada renderiza
`runtime_context.liquid`, e os dois valores são calculados e descartados.

Criar `enterprise/lib/captain/prompts/snippets/availability.liquid`:

```liquid
{% if business_status -%}
# Disponibilidade
O atendimento está {{ business_status }}. Use exatamente essa informação pra falar de quando o time retorna; nunca contrarie o que o status diz sobre quando reabre — se ele disser que os atendentes voltam ainda hoje, é hoje, não amanhã. Fora do horário, não diga que está chamando alguém agora nem prometa atendimento imediato; avise curto que o time assume quando reabrir. Só diga que já vai chamar alguém quando estiver DENTRO do horário.
{% endif -%}
{% if business_hours_text -%}
# Horário de funcionamento
O horário de atendimento é: {{ business_hours_text }}. Se perguntarem até que horas atende ou quando abre, use isso; nunca invente nem arredonde outro horário.
{% endif -%}
```

Chamar em `assistant.liquid` e `scenario.liquid`, junto do `current_time`:

```diff
 {% render 'current_time', current_time: current_time %}
+{% render 'availability', business_status: business_status, business_hours_text: business_hours_text %}
```

Isso é seguro nos dois modos: no modo caching, `split_instructions_for_cache` passa
`ctx.except(*VOLATILE_PROMPT_KEYS)` ao template estável, então `business_status` chega vazio ali (os
`{% if %}` não imprimem nada) e vem no bloco volátil via `runtime_context.liquid`, como hoje. No modo
default, chega pelo snippet. Sem duplicação em nenhum dos dois.

**Como verificar** (e este aceite tem mecanismo, não é afirmação): em `RAILS_ENV=test`, renderizar
`Captain::PromptRenderer.render('assistant', ctx)` com `business_status: 'fechado'` e
`business_hours_text: 'seg a sex, 8h às 18h'` e asseverar que a string de saída **contém** `'fechado'`
e `'seg a sex, 8h às 18h'`; e um segundo caso sem essas chaves, asseverando que a saída **não contém**
`'# Disponibilidade'`. Valor esperado explícito nos dois casos, não `be_present`.

### C-9 · PERDA · `agent_model`: devolver `runtime_id_for` e o fallback por runtime

`enterprise/app/models/concerns/agentable.rb:36-41`:

```diff
   def agent_model
     route = Llm::FeatureRouter.resolve(feature: 'assistant', account: account)
-    return route[:model] if route[:source] == :account_override || account&.feature_enabled?('captain_integration_v2')
-
-    installation_model.presence || route[:model]
+    preferred = if route[:source] == :account_override || account&.feature_enabled?('captain_integration_v2')
+                  route[:model]
+                else
+                  installation_model.presence || route[:model]
+                end
+
+    # `runtime_id_for`: o llm.yml guarda o modelo com ponto (claude-sonnet-4.5, branding/UI) e o
+    # RubyLLM só conhece a forma com hífen — sem isso, Agents::Agent quebra com ModelNotFoundError
+    # (ai-agents passa o valor direto pra RubyLLM.chat com assume_model_exists: false).
+    # `first_runtime_supported`: mesmo guarda-chuva que Llm::BaseAiService#model_for_feature já usa,
+    # pra um default novo do upstream (ex.: gpt-5.2) não derrubar o Captain onde a chave não o tem.
+    selected = Llm::Models.first_runtime_supported(preferred, Llm::Models.default_model_for('assistant'))
+    Llm::Models.runtime_id_for(selected.presence || preferred)
   end
```

**Aceite com mecanismo** — o spec que falta (`spec/enterprise/models/concerns/agentable_spec.rb`), com
valor esperado explícito:

```ruby
it 'translates dotted Claude aliases to the RubyLLM runtime id' do
  allow(mock_account).to receive(:captain_models).and_return({ 'assistant' => 'claude-sonnet-4.5' })
  expect(dummy_instance.send(:agent_model)).to eq('claude-sonnet-4-5')
end
```

### C-16 · PERDA · Restaurar o anti-alucinação de link e o `property_code`

Três edições em `enterprise/app/jobs/captain/conversation/response_builder_job.rb`. Elas fecham o
circuito que hoje está aberto: `buscar_imovel_tool.rb:139-140` grava `urls_imoveis` e
`enviar_fotos_imovel_tool.rb:147,197` gravam `property_code`, e ninguém lê.

(a) reintroduzir o método e a chamada:

```diff
   def sanitize_for_whatsapp(content)
     return content if content.blank?
 
+    content = fix_property_links(content)
     content.gsub(/\[\s*(ignorar|sem[\s_-]?resposta|no[\s_-]?reply)\s*\]/i, '')
-           .gsub(/\[\s*attachments?\s+sent\s*\]/i, '')
+           .gsub(/\[\s*attachments?\s+sent\s*\]/i, '')      # placeholder novo (upstream)
+           .gsub(/\[\s*fotos?[^\]]*enviad[ao]s?\s*\]/i, '') # placeholder pt-BR legado, já gravado no histórico da frota
```

```diff
+  # A URL de um imóvel só vem da buscar_imovel (build_url). O LLM às vezes monta uma URL do site
+  # na mão, com formato e número inventados (ex: caminho /imovel/...-3338 em vez de ...,ImoCodigo).
+  # Aqui, toda URL da Tozi na resposta é trocada pela que a busca realmente retornou (casando o
+  # código no fim da URL); se nenhum código bater, é inventada -> remove. Sem busca na conversa,
+  # nenhuma URL da Tozi é legítima. Só toca a saída da IA (não a de humano).
+  def fix_property_links(content)
+    return content unless content.match?(/toziimoveis/i)
+
+    mapa = @conversation.reload.custom_attributes&.dig('urls_imoveis') || {}
+    content.gsub(%r{https?://[^\s)\]]*toziimoveis\.com\.br[^\s)\]]*}i) do |url|
+      match = url.scan(/\d+/).find { |n| mapa.key?(n) }
+      match ? mapa[match] : ''
+    end
+  end
```

(b) devolver o código do imóvel ao placeholder:

```diff
+  # Foto sai como outgoing de conteudo vazio; sem o codigo, todas viram o MESMO placeholder no
+  # historico e o modelo nao sabe qual imovel e qual ("esse e qual?"). Carimbado pela
+  # EnviarFotosImovelTool em additional_attributes['property_code'].
   def outgoing_attachment_placeholder(message)
     return '' unless message.attachments.any?
 
-    '[attachment sent]'
+    code = message.additional_attributes&.dig('property_code')
+    code.present? ? "[foto do imóvel #{code} enviada]" : '[attachment sent]'
   end
```

(c) idem em `quoted_description`:

```diff
   def quoted_description(quoted)
     text = quoted.content.to_s.gsub(/\s+/, ' ').strip
     return text[0, 180] if text.present?
 
-    quoted.attachments.any? ? 'a previously sent attachment' : ''
+    code = quoted.additional_attributes&.dig('property_code')
+    return "foto do imóvel #{code}" if code.present?
+
+    quoted.attachments.any? ? 'uma foto enviada anteriormente' : ''
   end
```

(d) reinserir o comentário apagado em `process_response`, para ninguém "otimizar" a rajada envolvendo-a
numa transação:

```diff
     else
+      # Sem transacao envolvendo a rajada: cada bolha precisa COMMITAR pra disparar o
+      # SendReplyJob (after_create_commit). Dentro de uma transacao os sends so disparariam
+      # no commit final, TODOS juntos -> corriam soltos e chegavam fora de ordem. Commitando
+      # uma a uma, o wait_for_dispatch (espera o source_id) serializa o envio.
       message = create_messages
```

**Aceite com mecanismo** — spec com valor esperado, não `be_present`:

```ruby
it 'replaces an invented property URL with the one the search returned' do
  conversation.update!(custom_attributes: { 'urls_imoveis' => { '3338' => 'https://www.toziimoveis.com.br/imovel/x,3338' } })
  out = described_class.new.send(:sanitize_for_whatsapp, 'Olha: https://www.toziimoveis.com.br/imovel/apto-3338')
  expect(out).to eq('Olha: https://www.toziimoveis.com.br/imovel/x,3338')
end

it 'drops a Tozi URL whose code matches nothing' do
  conversation.update!(custom_attributes: { 'urls_imoveis' => {} })
  expect(described_class.new.send(:sanitize_for_whatsapp, 'Veja https://www.toziimoveis.com.br/imovel/apto-9999')).to eq('Veja')
end
```

### C-15 · PERDA · `HandoffTool`: restaurar a descrição pt-BR (condicionado a C-3b)

`enterprise/lib/captain/tools/handoff_tool.rb:6-8` — se a decisão de C-3b for manter o comportamento
proativo (o que o comentário `:1-6` do próprio arquivo defende):

```diff
-  description 'Hand off the conversation to a human agent only when the customer requests human assistance, ' \
-              'accepts an offer to speak with a human, an account-specific guideline requires transfer, or the ' \
-              'request requires an action the assistant cannot perform. Continue assisting until a human takes over.'
+  description 'Passa a conversa para um ATENDENTE HUMANO do time assumir. Use quando já ' \
+              'qualificou o cliente e é hora de uma pessoa continuar: ele quer visitar, ' \
+              'agendar ou fechar; pediu falar com um humano; o assunto exige uma pessoa ' \
+              '(jurídico, uma ação que você não executa); ou você não conseguiu resolver. ' \
+              'A IA continua respondendo normalmente até um humano assumir.'
```

E **reverter o spec junto** (`spec/enterprise/lib/captain/tools/handoff_tool_spec.rb:15-16`) — ele foi
reescrito para assertar o texto do upstream, e é por isso que a regressão não aparece na suíte:

```diff
-      expect(tool.description).to include('only when the customer requests human assistance')
-      expect(tool.description).to include('accepts an offer to speak with a human')
+      expect(tool.description).to include('Passa a conversa para um ATENDENTE HUMANO')
+      expect(tool.description).to include('A IA continua respondendo normalmente até um humano assumir')
```

Se a decisão de C-3b for **adotar** o consent-first do upstream, então não mexer no código e **apagar**
o comentário `handoff_tool.rb:1-6`, que passa a descrever o oposto do que o arquivo faz.

### C-13 · PERDA/RISCO · `config/llm.yml`: devolver os defaults do fork

```diff
   assistant:
-    default: gpt-4.1
+    default: gpt-5-mini
   copilot:
-    default: gpt-4.1
+    default: gpt-5-mini
   audio_transcription:
     models: [gpt-4o-mini-transcribe, whisper-1]
-    default: gpt-4o-mini-transcribe
+    default: whisper-1
```

E decidir sobre `gpt-5.1` / `gpt-5.2`: o `git diff BASE NOSSO` mostra que nós os removemos
deliberadamente (renomeando `gpt-5.1` → `gpt-5`), e o merge não só os reintroduziu como os pôs como
`default` de `conversation_faq_generation` e `help_center_article_generation`. Duas saídas:

1. **conservadora** — trocar esses dois defaults para `gpt-4.1-mini` (que já está nas duas listas), e
   deixar `gpt-5.1`/`gpt-5.2` disponíveis mas não default;
2. **verificar antes** — confirmar que a chave da frota tem acesso, com
   `Llm::Models.runtime_supported_model?('gpt-5.2')` em cada VM. Se der `false` em qualquer uma, a saída 1
   é obrigatória, porque `Llm::FeatureRouter::CAPTAIN_V2_ASSISTANT_MODEL` é `gpt-5.2` e `agent_model`
   hoje não tem fallback (C-9 resolve o fallback; o default continua sendo escolha nossa).

Restaurar os asserts que o merge removeu, para travar a decisão
(`spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb`,
`spec/lib/llm/models_spec.rb`) — com o valor que se decidir, não com `be_present`.

### C-10 · RISCO · Temperatura default: 0.0 → 0.5 (**decisão, não conserto**)

`enterprise/app/models/concerns/agentable.rb:11` — o merge corrigiu um bug nosso real
(`temperature.to_f || 0.7` nunca caía no `0.7`, porque `nil.to_f` é `0.0` e `0.0` é truthy). Só que o
efeito prático é que a frota sai de **0.0** para **0.5** onde `temperature` estiver nulo. Verificar
quantas assistants isso alcança, antes de decidir:

```sql
SELECT count(*) FILTER (WHERE temperature IS NULL OR temperature::text = '') AS sem_temperatura,
       count(*) AS total
FROM captain_assistants;
```

Se o número for alto, considerar `DEFAULT_TEMPERATURE = 0.0` para preservar o comportamento atual e
mudar depois, de propósito, com validação.

### C-11 · PERDA · Fuso horário: devolver o fallback

`enterprise/app/models/concerns/agentable.rb:63-65` — usar `account.reporting_timezone` é melhor; o que
falta é não cair em UTC quando ele também está vazio:

```diff
-    timezone = bh['timezone'].presence || account&.reporting_timezone.presence
+    timezone = bh['timezone'].presence || account&.reporting_timezone.presence || 'America/Cuiaba'
     tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone['UTC']
```

Sem isso, conta sem nenhum dos dois recebe horário em **UTC** (3–4 h adiantado) no prompt.

### C-12 · RISCO · Hora duplicada e em dois idiomas

`format_current_time` (`agentable.rb`) usa `strftime('%A, %B %d, %Y %I:%M %p %Z')` → inglês, enquanto
`current_datetime` (nosso) é pt-BR. Com C-14 aplicado, os dois convivem no prompt. Alinhar:

```diff
   def format_current_time(timezone)
     tz = ActiveSupport::TimeZone[timezone] if timezone.present?
     time = tz ? Time.current.in_time_zone(tz) : Time.current
-    time.strftime('%A, %B %d, %Y %I:%M %p %Z')
+    dias = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado]
+    "#{dias[time.wday]}, #{time.strftime('%d/%m/%Y às %H:%M %Z')}"
   end
```

Alternativa mais limpa (mais invasiva): parar de injetar `current_time` e deixar só `current_datetime`,
removendo `{% render 'current_time' %}` dos dois templates. Prefiro a primeira — mantém o template
igual ao upstream e só troca o formato.

### C-17 · RISCO · `captain_integration` volta a ser gerido pelo plano Stripe

`enterprise/app/services/enterprise/billing/reconcile_plan_features_service.rb:15` — restaurar a nossa
decisão, removendo o flag da lista:

```diff
     channel_tiktok
-    captain_integration
     captain_document_auto_sync
```

Só aplicar se o ChatSPX continua querendo o Captain fora da gestão por plano. **Verificação antes**: se
nenhum ambiente nosso recebe webhook do Stripe, isto é inerte e pode ficar como está — mas então
restaurar os asserts de `spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb` para
documentar a intenção.

### C-18 · RISCO (baixo) · `assistant_logs` voltou a `dependent: :destroy`

`enterprise/app/models/captain/assistant.rb:42` — nossa escolha era `:destroy_async` (o merge manteve
`:destroy_async` nas associações novas do upstream, `faq_suggestions` e `agent_sessions`, e trocou só a
nossa):

```diff
-  has_many :assistant_logs, class_name: 'Captain::AssistantLog', foreign_key: :captain_assistant_id, dependent: :destroy
+  has_many :assistant_logs, class_name: 'Captain::AssistantLog', foreign_key: :captain_assistant_id, dependent: :destroy_async
```

`captain_assistant_logs` cresce por evento de IA (`response_builder_job.rb:514`,
`debounced_response_job.rb:18`, `hook_execution_service.rb:102`), então apagar um assistant com
histórico longo passa a bloquear a request.

### C-4 · RISCO · `backfill_edited_on_captain_assistant_responses`: virar no-op

A heurística "≥15 dias entre `created_at` e `updated_at` ⇒ humano editou" é falsa no fork, porque
`Captain::AssistantResponse` tem `after_commit :update_response_embedding` — reindexar embedding toca
`updated_at`. Marcar `edited = true` em massa por isso é gravar um palpite:

```diff
 class BackfillEditedOnCaptainAssistantResponses < ActiveRecord::Migration[7.0]
   def up
-    return unless ChatwootApp.enterprise?
-    Captain::AssistantResponse
-      .where('updated_at - created_at > make_interval(days := ?)', 15)
-      .in_batches(of: 1000) { |batch| batch.update_all(edited: true) }
+    # ChatSPX: no-op. A heurística do upstream (>15 dias entre created_at e updated_at ⇒ editado por
+    # humano) é falsa aqui: `after_commit :update_response_embedding` toca updated_at em toda
+    # reindexação. `edited` fica false para o legado — que é a única coisa que sabemos ser verdade.
   end
 
   def down; end
 end
```

### C-5 a C-8 · RISCO · Verificações obrigatórias antes do `db:migrate` da frota

Nenhuma é conserto de código: são consultas read-only que precisam rodar **por VM**, antes do deploy.
Se qualquer uma voltar linha, a migration correspondente **trava o `db:migrate` no meio da fila** (as
anteriores já aplicadas) ou reescreve dado silenciosamente.

**C-5 — `rename_company_condition_key_in_automation_rules` (§2.5):** achar regra/filtro que use
`attribute_key: 'company'` com semântica de custom attribute mas sem `custom_attribute_type`:

```sql
SELECT id, account_id, conditions FROM automation_rules
WHERE conditions::text LIKE '%"attribute_key":"company"%';

SELECT id, account_id, query FROM custom_filters
WHERE filter_type = 0 AND query::text LIKE '%"attribute_key":"company"%';
```

Para cada linha, conferir se existe `custom_attribute_definitions` com `attribute_key = 'company'`. Se
existir, a regra vai ser renomeada para `company_name` e **para de casar** — nesse caso, excluir aquela
regra do escopo da migration antes de rodar.

**C-6 — `add_inbox_scope_to_email_templates` (§2.6):** a própria migration levanta
`IrreversibleMigration` nesse caso; rodar a consulta antes evita descobrir no deploy:

```sql
SELECT name, template_type, locale, count(*)
FROM email_templates WHERE account_id IS NULL
GROUP BY name, template_type, locale HAVING count(*) > 1;
```

**C-7 — `enable_assignment_v2_for_new_accounts` + `assignment_v2: enabled: true` (§2.7):** decisão de
produto. Se a frota **não** quer contas novas nascendo em assignment v2, reverter as duas coisas juntas:

```diff
 - name: assignment_v2
   display_name: Assignment V2
-  enabled: true
+  enabled: false
```

e transformar a migration em no-op. Lembrando que `assignment_v2` puxa `advanced_assignment` por
auto-sync (`enterprise/app/models/enterprise/account.rb:119-123`), agora que este último é gravável.

**C-8 — `change_captain_document_external_link_to_text` (§2.8):**

```sql
-- 1) external_link NULL faria o change_column null: false falhar
SELECT count(*) FROM captain_documents WHERE external_link IS NULL;

-- 2) colisão no índice unique novo por md5 do link inteiro (o antigo só via os 255 primeiros bytes)
SELECT assistant_id, md5(external_link), count(*)
FROM captain_documents GROUP BY 1, 2 HAVING count(*) > 1;
```

### C-19 · RISCO · Restaurar a cobertura de CTWA referral

O código sobreviveu (§4.5); o teste não. Restaurar de
`git show f26db6ee81:spec/services/whatsapp/incoming_message_whatsapp_cloud_service_spec.rb` os dois
contextos `'when message has a click-to-whatsapp referral'` e `'when message has no referral (regression)'`,
adaptando o que o upstream mudou na montagem do payload. Os asserts originais já checam valor
(`eq('Apartamento 2 quartos')`, `eq('https://fb.me/test')`), o que atende o critério.

### C-20 · RISCO · Devolver o caso genérico do `response_builder_job_spec`

Manter o `'when the conversation is snoozed'` do upstream e **acrescentar** o nosso caso genérico
(qualquer status fora de pending/open), que é o que exercita o
`Conversation.uncached { ... pick(:status) }` de `captain_can_respond?`.

### C-21 · RISCO (baixo) · `DeleteNotificationJob`: recuperar a defensividade

O escopo por conta do upstream é correto e deve ficar. O que vale reintroduzir é o guarda contra o
usuário apagado antes de o job rodar:

```diff
-  def perform(user, account, type: :all)
-    notifications = user.notifications.where(account_id: account.id)
+  def perform(user, account, type: :all)
+    return if user.blank? || account.blank?
+
+    notifications = user.notifications.where(account_id: account.id)
```

(Passar `user_id`/`account_id` em vez dos objetos seria mais robusto ainda, mas mudaria a assinatura em
três arquivos — não vale o atrito de merge.)

### C-22 · Nota · `add_feature_flags_ext_2_to_accounts` cria `ext_1` (§1.4)

**Não corrigir agora.** A migration já está aplicada na frota; renomeá-la faria o Rails reexecutá-la e
tentar criar `feature_flags_ext_1` de novo. Registrar em `AGENTS.md` para que quem for adicionar
`ext_2` de verdade saiba que a coluna não existe, apesar do nome.

---

## PARTE 6 — TABELA COMPLETA DOS 117 ARQUIVOS DA ÁREA

Ordenada como a lista de entrada (`area-ent.tsv`: MERGE_REAL por nº de linhas nossas decrescente,
depois os APAGADO/PEGOU_DELES/PEGOU_NOSSO). Onde a coluna "evidência" diz **varredura automática**, o
veredito vem da técnica obrigatória — extração das linhas que NÓS adicionamos (`git diff BASE NOSSO |
grep '^+'`, normalizadas por whitespace) e verificação de presença de cada uma no MERGE, com contagem
explícita. Os arquivos com julgamento estão referenciados à seção que os discute.

| arquivo | classe triagem | veredito | o que se perdeu | evidência (linha) | correção proposta |
|---|---|---|---|---|---|
| `db/schema.rb` | MERGE_REAL | **OK** | 1 linha: índice index_email_templates_on_name_and_account_id, removido de propósito pela migration | db/schema.rb; §3.10 | — |
| `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` | MERGE_REAL | OK | — (auto: 216/216 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/jobs/captain/conversation/response_builder_job.rb` | MERGE_REAL | **PERDA** | fix_property_links (anti-URL-inventada), property_code no placeholder de foto e em quoted_description; regex pt-BR do placeholder | response_builder_job.rb:374-387 e :164-170; §3.7 | C-16 |
| `spec/finders/conversation_finder_spec.rb` | MERGE_REAL | OK | — (auto: 126/126 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/models/attachment_spec.rb` | MERGE_REAL | OK | — (auto: 112/112 linhas nossas presentes, 100%) | varredura automática | — |
| `config/routes.rb` | MERGE_REAL | OK | — (auto: 145/145 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/models/conversation_spec.rb` | MERGE_REAL | **OK** | Inboxes::BulkAutoAssignmentJob deixou de existir no upstream | §4.7 | — |
| `spec/controllers/api/v1/accounts/conversations_controller_spec.rb` | MERGE_REAL | OK | — (auto: 103/103 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/services/whatsapp/incoming_message_whatsapp_cloud_service_spec.rb` | MERGE_REAL | **RISCO** | perdeu a cobertura de CTWA referral (o CÓDIGO sobreviveu: incoming_message_base_service.rb:180-181) | §4.5 | C-19 |
| `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb` | MERGE_REAL | **RISCO** | nosso teste genérico (qualquer status != pending/open) virou só 'when the conversation is snoozed' | response_builder_job_spec.rb:354; §4.8 | C-20 |
| `spec/controllers/api/v1/accounts/labels_controller_spec.rb` | MERGE_REAL | OK | — (auto: 86/86 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/listeners/action_cable_listener_spec.rb` | MERGE_REAL | OK | — (auto: 86/86 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb` | MERGE_REAL | OK | — (auto: 90/90 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/lib/captain/tools/handoff_tool_spec.rb` | MERGE_REAL | **RISCO** | o spec foi reescrito para ASSERTAR a description do upstream — nenhum teste acusa a regressão de §3.6 | handoff_tool_spec.rb:15-16; §4.1 | C-15 |
| `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` | MERGE_REAL | OK | — (auto: 68/68 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/concerns/agentable.rb` | MERGE_REAL | **PERDA** | agent_model perdeu runtime_id_for e o fallback por suporte de runtime; fallback de fuso America/Cuiaba | agentable.rb:36-41 e :63-65; §3.2 | C-9, C-11, C-10, C-12 |
| `spec/models/conversation_spec.rb` | MERGE_REAL | **OK** | falso positivo: as strings existem com outra formatação | conversation_spec.rb:342,362,366 | — |
| `spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb` | MERGE_REAL | **RISCO** | asserts que travavam o default gpt-5-mini de assistant/copilot foram removidos | §4.2 | C-13 |
| `spec/listeners/webhook_listener_spec.rb` | MERGE_REAL | OK | — (auto: 42/42 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/enterprise/concerns/conversation.rb` | MERGE_REAL | OK | — (auto: 76/76 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/jobs/bulk_actions_job_spec.rb` | MERGE_REAL | OK | — (auto: 50/50 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/enterprise/action_service.rb` | MERGE_REAL | OK | — (auto: 84/84 linhas nossas presentes, 100%) | varredura automática | — |
| `config/integration/apps.yml` | MERGE_REAL | OK | — (auto: 69/69 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/services/enterprise/action_service_spec.rb` | MERGE_REAL | OK | — (auto: 54/54 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/models/account_spec.rb` | MERGE_REAL | OK | — (auto: 43/43 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/captain/tools/handoff_tool.rb` | MERGE_REAL | **PERDA** | description pt-BR trocada pela do upstream, reintroduzindo o bug que o comentário :1-6 documenta ter corrigido | handoff_tool.rb:6-8; §3.6 | C-15 |
| `spec/enterprise/models/inbox_spec.rb` | MERGE_REAL | OK | — (auto: 41/41 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/listeners/captain_listener_spec.rb` | MERGE_REAL | **OK** | contrato do upstream: generate_and_deduplicate -> generate_suggestions (§2.2). Sintoma da reescrita do FAQ, não perda | §4.6 | — |
| `enterprise/app/services/captain/assistant/agent_runner_service.rb` | MERGE_REAL | **OK** | a exclusão de aguardando_humano_desde do contexto migrou para runner_state_helper.rb:36 | runner_state_helper.rb:36 | — |
| `spec/controllers/api/v1/accounts/agent_bots_controller_spec.rb` | MERGE_REAL | OK | — (auto: 32/32 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/captain/assistant.rb` | MERGE_REAL | **RISCO** | assistant_logs mudou de dependent: :destroy_async para :destroy (apagar assistant com muitos logs passa a bloquear) | enterprise/app/models/captain/assistant.rb:42 | C-18 |
| `enterprise/app/services/llm/base_ai_service.rb` | MERGE_REAL | **OK** | nossas 4 linhas viraram versões melhores; runtime_id_for e first_runtime_supported preservados | base_ai_service.rb:24,68 | — |
| `config/locales/pt_BR.yml` | MERGE_REAL | OK | — (auto: 65/65 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb` | MERGE_REAL | OK | — (auto: 38/38 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/models/captain/assistant_spec.rb` | MERGE_REAL | OK | — (auto: 37/37 linhas nossas presentes, 100%) | varredura automática | — |
| `config/locales/en.yml` | MERGE_REAL | OK | — (auto: 61/61 linhas nossas presentes, 100%) | varredura automática | — |
| `config/schedule.yml` | MERGE_REAL | OK | — (auto: 51/51 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/controllers/api/v1/profiles_controller_spec.rb` | MERGE_REAL | OK | — (auto: 33/33 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` | MERGE_REAL | **OK** | stats preservado; before_action reformatado multi-linha | assistants_controller.rb:7,51 | — |
| `spec/builders/messages/message_builder_spec.rb` | MERGE_REAL | OK | — (auto: 38/38 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/captain/copilot/chat_service.rb` | MERGE_REAL | **OK** | super(account:) virou super(feature: 'copilot', account:) | — | — |
| `spec/jobs/hook_job_spec.rb` | MERGE_REAL | OK | — (auto: 19/19 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/services/captain/copilot/chat_service_spec.rb` | MERGE_REAL | OK | — (auto: 31/31 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/services/messages/mention_service_spec.rb` | MERGE_REAL | OK | — (auto: 31/31 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/lib/captain/reply_suggestion_service_spec.rb` | MERGE_REAL | OK | — (auto: 28/28 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/lib/captain/rewrite_service_spec.rb` | MERGE_REAL | OK | — (auto: 21/21 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/lib/captain/follow_up_service_spec.rb` | MERGE_REAL | OK | — (auto: 26/26 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/listeners/automation_rule_listener_spec.rb` | MERGE_REAL | OK | — (auto: 17/17 linhas nossas presentes, 100%) | varredura automática | — |
| `config/llm.yml` | MERGE_REAL | **PERDA** | defaults nossos de assistant/copilot (gpt-5-mini) e audio_transcription (whisper-1); gpt-5.1/5.2 reintroduzidos | config/llm.yml:110,126,203; §3.4 | C-13 |
| `spec/models/agent_bot_spec.rb` | MERGE_REAL | OK | — (auto: 17/17 linhas nossas presentes, 100%) | varredura automática | — |
| `config/features.yml` | MERGE_REAL | **OK** | nada; os 63 bits da frota preservados na ordem | §1.1 diff das listas coluna[bit] | — |
| `spec/jobs/data_import_job_spec.rb` | MERGE_REAL | OK | — (auto: 10/10 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/captain/document.rb` | MERGE_REAL | OK | — (auto: 22/22 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/controllers/enterprise/api/v1/accounts/conversations_controller_spec.rb` | MERGE_REAL | OK | — (auto: 18/18 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/concerns/toolable.rb` | MERGE_REAL | OK | — (auto: 22/22 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/lib/llm/models_spec.rb` | MERGE_REAL | **RISCO** | asserts que garantiam que gpt-5.1/5.2 NÃO eram suportados foram removidos | §4.2 | C-13 |
| `spec/services/whatsapp/incoming_message_service_spec.rb` | MERGE_REAL | OK | — (auto: 22/22 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/controllers/api/v1/accounts_controller_spec.rb` | MERGE_REAL | OK | — (auto: 23/23 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb` | MERGE_REAL | **OK** | endpoint test e perform_test preservados; before_action refinado | custom_tools_controller.rb:5,32,36 | — |
| `spec/controllers/public/api/v1/inbox/messages_controller_spec.rb` | MERGE_REAL | OK | — (auto: 15/15 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/captain/prompts/assistant.liquid` | MERGE_REAL | **PERDA** | 7 das 13 regras de Conduta pt-BR + bloco de disponibilidade (business_status/business_hours_text) + política de handoff invertida | assistant.liquid:1-30 vs NOSSO:9-33; §3.1 e §3.5 | C-3, C-14 |
| `spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb` | MERGE_REAL | **RISCO** | perdeu os asserts que garantiam captain_integration ligado — triangula com §4.4 | §4.4 | C-17 |
| `spec/services/auto_assignment/assignment_service_spec.rb` | MERGE_REAL | OK | — (auto: 11/11 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/controllers/api/v1/accounts/captain/documents_controller_spec.rb` | MERGE_REAL | OK | — (auto: 14/14 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/jobs/avatar/avatar_from_url_job_spec.rb` | MERGE_REAL | OK | — (auto: 7/7 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb` | MERGE_REAL | OK | — (auto: 13/13 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/builders/contact_inbox_with_contact_builder_spec.rb` | MERGE_REAL | OK | — (auto: 16/16 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/messages/audio_transcription_service.rb` | MERGE_REAL | OK | — (auto: 16/16 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/enterprise/message.rb` | PEGOU_NOSSO | OK | — (auto: 15/15 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/models/inbox_spec.rb` | MERGE_REAL | OK | — (auto: 13/13 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/jobs/inboxes/fetch_imap_emails_job_spec.rb` | MERGE_REAL | OK | — (auto: 5/5 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/captain/tools/http_tool.rb` | MERGE_REAL | OK | — (auto: 14/14 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/captain/llm/embedding_service.rb` | MERGE_REAL | **OK** | captain_help_center_search_model preservado; fallback virou self.class.embedding_model | embedding_service.rb:10 | — |
| `spec/jobs/inboxes/bulk_auto_assignment_job_spec.rb` | APAGADO | **OK** | job removido pelo upstream; a garantia do mirror bot está no motor novo e coberta por spec/services/auto_assignment/* | agent_assignment_service.rb:12; §4.7 | — |
| `spec/listeners/agent_bot_listener_spec.rb` | MERGE_REAL | OK | — (auto: 11/11 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/models/concerns/agentable_spec.rb` | MERGE_REAL | **RISCO** | specs de agent_model por captain_assistant_model removidos; a cobertura nova não exercita nenhum modelo Claude, logo não pega a perda de runtime_id_for | agentable_spec.rb:163-192; §4.3 | C-9 |
| `enterprise/app/jobs/captain/documents/response_builder_job.rb` | MERGE_REAL | OK | — (auto: 13/13 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/lib/captain/summary_service_spec.rb` | MERGE_REAL | OK | — (auto: 10/10 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/listeners/captain_listener.rb` | MERGE_REAL | OK | — (auto: 9/9 linhas nossas presentes, 100%) | varredura automática | — |
| `config/application.rb` | MERGE_REAL | OK | — (auto: 9/9 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/services/conversations/filter_service_spec.rb` | MERGE_REAL | OK | — (auto: 4/4 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/jobs/channels/whatsapp/templates_sync_scheduler_job_spec.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `config/initializers/rack_attack.rb` | MERGE_REAL | OK | — (auto: 8/8 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/rails_helper.rb` | MERGE_REAL | OK | — (auto: 7/7 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/services/enterprise/billing/handle_stripe_event_service_spec.rb` | MERGE_REAL | OK | — (auto: 7/7 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/enterprise/concerns/inbox.rb` | MERGE_REAL | OK | — (auto: 6/6 linhas nossas presentes, 100%) | varredura automática | — |
| `config/installation_config.yml` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/captain/prompts/conversation_completion.liquid` | MERGE_REAL | OK | — (auto: 6/6 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/controllers/api/v1/accounts/applied_slas_controller.rb` | MERGE_REAL | OK | — (auto: 7/7 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb` | MERGE_REAL | OK | — (auto: 5/5 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/services/whatsapp/oneoff_campaign_service_spec.rb` | MERGE_REAL | OK | — (auto: 4/4 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/models/concerns/captain_featurable_spec.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/jobs/agents/destroy_job_spec.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/enterprise/inbox.rb` | MERGE_REAL | OK | — (auto: 5/5 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/helpers/captain/chat_response_helper.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/enterprise/jobs/captain/inbox_pending_conversations_resolution_job_spec.rb` | MERGE_REAL | OK | — (auto: 4/4 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/controllers/api/v1/accounts/captain/documents_controller.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `spec/jobs/notification/delete_notification_job_spec.rb` | PEGOU_DELES | **RISCO** | contrato do job mudou para (user, account, type:) — coerente ponta a ponta, mas perde nossa defensividade (user_id + return unless user) | delete_notification_job.rb:4; §4.9 | C-21 |
| `spec/enterprise/controllers/api/v1/accounts/applied_slas_controller_spec.rb` | MERGE_REAL | OK | — (auto: 4/4 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/captain/prompts/scenario.liquid` | MERGE_REAL | **PERDA** | bloco pt-BR de data/hora + business_status dos agentes de cenário | scenario.liquid:11 (era :11-12 em NOSSO); §3.8 | C-14 |
| `enterprise/app/services/captain/llm/system_prompts_service.rb` | MERGE_REAL | OK | — (auto: 2/2 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/policies/captain/custom_tool_policy.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/policies/captain/assistant_policy.rb` | MERGE_REAL | OK | — (auto: 3/3 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/captain/conversation_completion_service.rb` | MERGE_REAL | OK | — (auto: 2/2 linhas nossas presentes, 100%) | varredura automática | — |
| `config/initializers/sentry.rb` | MERGE_REAL | **OK** | nossos 2 excluded_exceptions de pé; o merge ADICIONOU um terceiro | sentry.rb:11-15; §3.9 | — |
| `enterprise/app/services/captain/llm/faq_generator_service.rb` | PEGOU_DELES | **OK** | assinatura virou (document:); nossa super(account:) absorvida; chamador e spec consistentes | response_builder_job.rb:32 | — |
| `enterprise/app/services/captain/llm/conversation_faq_service.rb` | PEGOU_DELES | **PERDA** | o produtor de FAQ pendente (status: 'pending') foi substituído pelo fluxo faq_suggestions; nossa linha super(account:) foi absorvida corretamente | §2.2 | C-1 |
| `enterprise/app/services/captain/llm/contact_notes_service.rb` | PEGOU_DELES | **OK** | super(account:) preservada e melhorada para super(feature:, account:) | contact_notes_service.rb:5 | — |
| `enterprise/app/services/captain/llm/contact_attributes_service.rb` | PEGOU_DELES | **OK** | idem | contact_attributes_service.rb:5 | — |
| `spec/models/data_import_spec.rb` | MERGE_REAL | OK | — (auto: 1/1 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/lib/enterprise/captain/reply_suggestion_service.rb` | MERGE_REAL | OK | — (auto: 1/1 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb` | MERGE_REAL | OK | — (auto: 1/1 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/captain/llm/paginated_faq_generator_service.rb` | MERGE_REAL | OK | — (auto: 1/1 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/models/enterprise/concerns/account.rb` | MERGE_REAL | OK | — (auto: 1/1 linhas nossas presentes, 100%) | varredura automática | — |
| `enterprise/app/services/enterprise/billing/handle_stripe_event_service.rb` | PEGOU_DELES | **RISCO** | nossa remoção de captain_integration da gestão por plano foi descartada na reescrita (voltou em ReconcilePlanFeaturesService::STARTUP_PLAN_FEATURES:15) | reconcile_plan_features_service.rb:15,38; §4.4 | C-17 |
| `enterprise/app/models/captain/custom_tool.rb` | MERGE_REAL | OK | — (auto: 1/1 linhas nossas presentes, 100%) | varredura automática | — |
| `AGENTS.md` | PEGOU_NOSSO | OK | — (auto: 212/212 linhas nossas presentes, 100%) | varredura automática | — |

### Migrations (não constam do `area-ent.tsv` porque são arquivos novos do upstream)

As 39 estão auditadas uma a uma em §2.1. Resumo de vereditos: **2 DADO** (`purge_pending_captain_assistant_responses`,
`enqueue_validate_openai_hooks_job`), **7 RISCO** (`backfill_edited_on_captain_assistant_responses`,
`rename_company_condition_key_in_automation_rules`, `add_inbox_scope_to_email_templates`,
`enable_assignment_v2_for_new_accounts`, `change_captain_document_external_link_to_text`,
`backfill_agent_bot_and_channel_api_secrets`, `add_feature_flags_ext_2_to_accounts`), **30 OK**.
Mais: **8 migrations do upstream corretamente descartadas** pelo merge (incluindo `drop_channel_voice`)
e **zero migrations nossas apagadas**, **zero colisões de timestamp**.

---

## CONTAGEM FINAL

**Arquivos da área (`area-ent.tsv`, 117):**

| veredito | nº |
|---|---|
| **DADO** | 0 |
| **PERDA** | 7 |
| **RISCO** | 10 |
| **OK** | 100 |
| total | **117** |

**Fora do TSV, auditados porque a task os exige (§2 e §5.1):**

| item | veredito | nº |
|---|---|---|
| `enterprise/app/models/captain/assistant_response.rb` | DADO | 1 |
| 39 migrations novas do upstream | DADO 2 · RISCO 7 · OK 30 | 39 |

**Total consolidado: 3 DADO · 7 PERDA · 17 RISCO · 130 OK.**

Os três DADO são a mesma cadeia em dois casos e um caso independente:
1. **`purge_pending_captain_assistant_responses` + `assistant_response.rb`** — apaga FAQ pendente de
   cliente sem migrar para o fluxo novo (achado nº 1 do coordenador, **confirmado e ampliado**: o
   produtor, a tela e o enum também caíram). Correção: **C-1**.
2. **`enqueue_validate_openai_hooks_job`** — `hook.destroy!` apaga a integração de IA da conta, com as
   settings dentro, quando a chave devolve 401. **Achado novo desta auditoria.** Correção: **C-2**.

O achado nº 2 do coordenador (`Pending.vue` apagada) é da área `app/`, mas é a mesma cadeia — registrado
como dependência em C-1, passo 3.

O achado nº 3 do coordenador (`features.yml`, flags movidos para `feature_flags_ext_1`) foi
**desescalado para OK** com prova aritmética em §1.3: os bits 64 e 65 exigiam máscaras `1 << 63` e
`1 << 64`, ambas maiores que o máximo de um `bigint`, logo nenhuma conta da frota podia tê-los gravados.
Não há estado a migrar, e o merge conserta um bug latente que derrubava o salvamento de conta em plano
Business/Enterprise.

**COBERTURA: 117 de 117 arquivos da área auditados.** Cobertura obrigatória cumprida: 100% dos APAGADO
(1/1), PEGOU_DELES (6/6) e PEGOU_NOSSO (2/2) individualmente; os 108 MERGE_REAL percorridos na ordem
decrescente de linhas nossas, com julgamento escrito para todos os que perderam qualquer linha e
verificação automática com contagem para os demais. Somando o que a task exige fora do TSV
(39 migrations + `assistant_response.rb` + `db/schema.rb` + `lib/llm/*`), **157 itens auditados**.

### O que esta auditoria NÃO cobre (para não passar por completo)

- `app/javascript/**` (inclusive `Pending.vue`) e o restante de `app/` — outra área.
- Não rodei build, suíte de testes, migration nem servidor: a task é somente-leitura, e outro executor
  usa este mesmo worktree. Todo aceite numérico proposto acima (C-9, C-14, C-16) vem com o mecanismo
  que o executa, mas **nenhum foi executado por mim** — está declarado como tal, não como verificado.
- As consultas SQL de §1.2, §1.3, C-5 a C-8 e C-10 são propostas: **não toquei em nenhum banco**.
