# W2 — Migrations, schema e integridade de dados

**Escopo:** 45 migrations novas do upstream em `v4.12.1..v4.16.2` (+ 8 exclusivas de `upstream/develop`),
diff de `db/schema.rb`, e o choque com as nossas 105 migrations próprias.
**Base (merge-base):** `899fce1c9286b793d165c8ad6c0200ab676f185b` (= `v4.12.1`). **Nosso HEAD:** `ee87f5e799` (`homologacao`).
**Auditoria read-only** — nenhum arquivo fora desta pasta foi tocado, nenhum comando de escrita em git/DB foi executado.

---

## Sumário executivo

1. **Só 2 colisões exatas de timestamp** (`20260616120000` e `20260630000000`) — ambas fáceis de re-carimbar; nenhuma colisão de nome de classe.
2. **O risco real não é o timestamp: é o `features.yml`.** Nosso bitmask e o deles divergiram em **8 posições de bit**. Merge ingênuo do `features.yml` = corrupção silenciosa de feature flag em todas as contas da frota.
3. **Bug latente já existente no nosso fork:** temos **65 features numa única coluna bigint** (limite = 63). Os bits 64 (`conversation_required_attributes`) e 65 (`advanced_assignment`) **não podem ser ligados** — estouram `bigint`.
4. O upstream **resolveu exatamente esse problema** em `v4.16.0` (`feature_flags_ext_1` + `Featurable` multi-coluna). É o item de maior valor da auditoria: **TRAZER, obrigatório**.
5. **1 migration destrutiva com perda de dados de cliente:** `20260714123000_purge_pending_captain_assistant_responses` faz `DELETE FROM captain_assistant_responses WHERE status = 0`. No upstream `status 0` deixou de existir; **no nosso fork `0 = pending` e é estado ativo**. **DESCARTAR.**
6. **1 migration que quebra código nosso vivo:** `20260326120001_drop_channel_voice` — o upstream matou `Channel::Voice`, nós ainda usamos (10+ arquivos). **DESCARTAR** (ou trazer o refactor de voz inteiro).
7. **1 migration que enfileira job destrutivo em produção:** `20260515000000_enqueue_validate_openai_hooks_job` — destrói `Integrations::Hook` do OpenAI e e-mailala o admin. **TRAZER ADAPTADO** (rodar manual, por conta, com dry-run).
8. 2 backfills batendo em tabela grande (`messages`, `captain_documents`) e 3 índices `CONCURRENTLY` — exigem janela, não trava tabela.
9. Nosso schema divergiu do deles em **93 foreign keys** (eles têm 4) e **20 índices em `messages`** (eles 13). Isso muda o custo/risco de qualquer DDL deles.
10. `db/schema.rb` deles está em `2026_07_18_000000`, o nosso em `2026_07_22_120000` — **o schema.rb tem que ser regerado, nunca mergeado à mão.**

---

## 1) Tabela de colisão de timestamp

Timestamp duplicado ⇒ `ActiveRecord::DuplicateMigrationVersionError` no boot de **qualquer** comando `db:*`, travando a frota inteira. Cruzamento completo dos 45 prefixos deles × **todos** os prefixos do nosso `db/migrate` (não só os 105 novos):

| Timestamp | Migration UPSTREAM | Migration NOSSA | Já aplicada na frota? | Gravidade | Correção |
|---|---|---|---|---|---|
| `20260616120000` | `add_icon_to_teams.rb` (v4.16.0, `e8edc9ebf5`) | `add_agent_id_to_messages.rb` (isolamento por agente) | **Sim** (nossa está em `schema_migrations` de toda VM) | 🔴 Bloqueia `db:migrate` | Re-carimbar a **deles** para `20260616120001`. O código deles é idempotente (`unless column_exists?`), roda limpo. |
| `20260630000000` | `add_sender_created_index_to_messages.rb` (v4.16.0, `a5fcecb3f6`) | `extend_ai_config_changes.rb` (auditoria do receptor Almirante) | **Sim** | 🔴 Bloqueia `db:migrate` | Re-carimbar a **deles** para `20260630000001`. Código deles usa `if_not_exists`, roda limpo. |

**Colisões de nome de classe (`DuplicateMigrationNameError`): nenhuma.** Conferido em `db/migrate` inteiro.
**Colisões com `upstream/develop` (8 migrations extras): nenhuma** (timestamp nem nome).

> ⚠️ **Armadilha operacional:** re-carimbar é a correção certa, mas **jamais** o contrário (apagar a nossa e ficar com a deles no mesmo timestamp): o `schema_migrations` da frota já tem a linha `20260616120000`; a migration deles seria considerada "já rodada" e a coluna `teams.icon` **nunca** seria criada — falha silenciosa que só aparece em runtime.

> ℹ️ **Não existe `enterprise/db/migrate`** nem em `v4.16.2` nem no nosso HEAD (`git ls-tree -d v4.16.2:enterprise/` → `app config lib`). Todas as migrations vivem em `db/migrate`; o gating enterprise é feito **dentro** da migration com `return unless ChatwootApp.enterprise?` (ex.: `20260410092753`, `20260428120000`).

---

## 2) As 45 migrations do upstream — o que cada uma faz

Legenda **Tipo**: `A` = aditiva (coluna/índice/tabela nova) · `T` = transformadora (rename/change_column) · `D` = destrutiva (drop/delete) · `B` = backfill de dados.
Legenda **Nossa área**: tabela ou arquivo que **nós** já modificamos.

| # | Migration | Rel. | Tabela | Tipo | Toca área nossa? | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|---|---|
| 1 | `20260324070820_add_secret_to_agent_bots` | v4.13.0 | `agent_bots` | A | ✅ `agent_bots` (temos `captain_assistant_id`) | Baixo | TRAZER | P |
| 2 | `20260324070828_add_secret_to_channel_api` | v4.13.0 | `channel_api` | A | — | Baixo | TRAZER | P |
| 3 | `20260324070835_backfill_agent_bot_and_channel_api_secrets` | v4.13.0 | `agent_bots`,`channel_api` | B | ✅ **usa `update!` → nossas validações rodam** | **Alto** | TRAZER ADAPTADO (`update_column`) | P |
| 4 | `20260324102005_repurpose_response_bot_flag_for_custom_tools` | v4.13.0 | `accounts` (bit 29) | T | 🔴 **bit 29 = nosso `message_sequences`** | **Crítico** | TRAZER ADAPTADO | M |
| 5 | `20260326120000_add_voice_to_channel_twilio_sms` | v4.14.0 | `channel_twilio_sms` | A | — | Baixo | AVALIAR DEPOIS | P |
| 6 | `20260326120001_drop_channel_voice` | v4.14.0 | `channel_voice` | **D** | 🔴 **ainda usamos `Channel::Voice`** | **Crítico** | **DESCARTAR** | — |
| 7 | `20260327065119_create_platform_banners` | v4.14.0 | `platform_banners` (nova) | A | — | Baixo | AVALIAR DEPOIS | P |
| 8 | `20260408170902_create_calls` | v4.13.0 | `calls` (nova) | A | — | Baixo | AVALIAR DEPOIS | P |
| 9 | `20260409091202_enable_assignment_v2_for_new_accounts` | v4.13.0 | `installation_configs` | B | ⚠️ muda default de roteamento p/ conta nova | Médio | AVALIAR DEPOIS | P |
| 10 | `20260410092751_add_edited_to_captain_assistant_responses` | v4.13.0 | `captain_assistant_responses` | A | ✅ Captain | Baixo | TRAZER | P |
| 11 | `20260410092752_add_sync_columns_to_captain_documents` | v4.13.0 | `captain_documents` | A | ✅ Captain (temos `captain_document_chunks`) | Baixo | TRAZER | P |
| 12 | `20260410092753_backfill_edited_on_captain_assistant_responses` | v4.13.0 | `captain_assistant_responses` | B | ✅ Captain | Médio | TRAZER | P |
| 13 | `20260422133000_add_additional_attributes_to_companies` | v4.14.0 | `companies` | A | — | Baixo | TRAZER | P |
| 14 | `20260426011444_repurpose_twilio_content_templates_flag_for_captain_document_auto_sync` | v4.14.0 | `accounts` (bit 52) | T | ⚠️ ainda temos `twilio_content_templates` no bit 52 | Médio | TRAZER ADAPTADO | P |
| 15 | `20260427094500_rename_company_condition_key_in_automation_rules` | v4.14.0 | `automation_rules`, `custom_filters` | B/T | ✅ **`automation_rules`** | Médio | TRAZER | P |
| 16 | `20260428120000_backfill_captain_document_sync_metadata` | v4.14.0 | `captain_documents` | B | ✅ Captain | Médio | TRAZER | P |
| 17 | `20260429043000_add_sync_stats_index_to_captain_documents` | v4.14.0 | `captain_documents` | A | ✅ Captain | Baixo | TRAZER | P |
| 18 | `20260430114500_repurpose_report_v4_flag_for_captain_v1_action_classifier` | v4.14.0 | `accounts` (bit 39) | T | 🔴 **bit 39 = nosso `ai_assistant_v2`** | **Crítico** | TRAZER ADAPTADO | M |
| 19 | `20260507000000_add_imap_authentication_to_channel_email` | v4.14.0 | `channel_email` | A | — | Baixo | TRAZER | P |
| 20 | `20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts` | v4.14.1 | `accounts` (bit 4) | T | ⚠️ ainda temos `channel_twitter` no bit 4 | Médio | TRAZER ADAPTADO | P |
| 21 | `20260515000000_enqueue_validate_openai_hooks_job` | v4.14.0 | `integrations_hooks` | **D** (via job) | 🔴 destrói hook OpenAI + e-mail p/ admin | **Alto** | TRAZER ADAPTADO | M |
| 22 | `20260525093000_change_captain_document_external_link_to_text` | v4.14.1 | `captain_documents` | T | ✅ Captain | Médio (lock) | TRAZER | P |
| 23 | `20260604000000_add_provider_config_to_channel_twilio_sms` | v4.15.0 | `channel_twilio_sms` | A | — | Baixo | AVALIAR DEPOIS | P |
| 24 | `20260610000000_add_icon_color_to_categories` | v4.15.0 | `categories` | A | ⚠️ Central de Ajuda embutida | Baixo | TRAZER | P |
| 25 | `20260611184600_create_user_sessions` | v4.15.0 | `user_sessions` (nova) | A | — | Baixo | TRAZER | P |
| 26 | `20260616120000_add_icon_to_teams` | v4.16.0 | `teams` | A | 🔴 **colisão de timestamp** | **Alto** | TRAZER (re-carimbar) | P |
| 27 | `20260617000000_add_exclude_older_than_hours_to_assignment_policies` | v4.16.0 | `assignment_policies` | A | ⚠️ temos `distribuicao_policies` própria | Baixo | AVALIAR DEPOIS | P |
| 28 | `20260618000000_backfill_rejected_call_status` | v4.16.0 | `calls` | B | — (tabela inexistente p/ nós) | Baixo | segue #8 | P |
| 29 | `20260620000000_create_captain_message_reports` | v4.16.0 | `captain_message_reports` (nova) | A | ✅ Captain | Baixo | AVALIAR DEPOIS | P |
| 30 | `20260622000000_add_account_created_at_index_to_calls` | v4.16.0 | `calls` | A (CONCURRENTLY) | — | Baixo | segue #8 | P |
| 31 | `20260623000000_add_draft_columns_to_articles` | v4.16.0 | `articles` | A | ⚠️ Central de Ajuda | Baixo | TRAZER | P |
| 32 | `20260629000000_repurpose_quoted_email_reply_flag_for_unread_count_for_filters` | v4.16.0 | `accounts` (bit 57) | T | ⚠️ ainda temos `quoted_email_reply` no bit 57 | Médio | TRAZER ADAPTADO | P |
| 33 | `20260630000000_add_sender_created_index_to_messages` | v4.16.0 | **`messages`** | A (CONCURRENTLY) | 🔴 **colisão de timestamp + tabela gigante** | **Alto** | TRAZER (re-carimbar, janela) | P |
| 34 | `20260702000000_expand_data_imports_for_intercom_imports` | v4.16.0 | `data_imports` | A | — | Baixo | AVALIAR DEPOIS | P |
| 35 | `20260702000001_create_data_import_items` | v4.16.0 | nova | A | — | Baixo | AVALIAR DEPOIS | P |
| 36 | `20260702000002_create_data_import_mappings` | v4.16.0 | nova | A | — | Baixo | AVALIAR DEPOIS | P |
| 37 | `20260702000003_create_data_import_errors` | v4.16.0 | nova | A | — | Baixo | AVALIAR DEPOIS | P |
| 38 | `20260706000000_add_inbox_scope_to_email_templates` | v4.16.0 | `email_templates` | A/T | ⚠️ **pode abortar com `IrreversibleMigration`** | Médio | TRAZER (pré-check) | P |
| 39 | `20260706000001_repurpose_insert_article_in_reply_for_branded_email_templates` | v4.16.0 | `accounts` (bit 31) | T | ⚠️ ainda temos `insert_article_in_reply` no bit 31 | Médio | TRAZER ADAPTADO | P |
| 40 | **`20260706215758_add_feature_flags_ext_2_to_accounts`** | v4.16.0 | `accounts` | A | 🔴 **resolve nosso bitmask estourado** | Baixo (a DDL) | **TRAZER — obrigatório** | M |
| 41 | `20260709091147_create_agent_sessions` | v4.16.0 | `agent_sessions` (nova) | A | ✅ Captain (temos `captain_tool_calls`, `captain_conversation_evals`) | Baixo | AVALIAR DEPOIS | M |
| 42 | `20260710000000_change_captain_assistant_description_to_text` | v4.16.0 | `captain_assistants` | T | ✅ Captain (temos `behavior`) | Baixo | TRAZER | P |
| 43 | `20260713184351_create_captain_faq_suggestions` | v4.16.0 | 2 tabelas novas + índice ivfflat | A | ✅ Captain | Médio | AVALIAR DEPOIS | M |
| 44 | **`20260714123000_purge_pending_captain_assistant_responses`** | v4.16.2 | `captain_assistant_responses` | **D** | 🔴 **apaga FAQs pendentes de cliente** | **Crítico** | **DESCARTAR** | — |
| 45 | `20260718000000_add_phone_number_health_to_channel_whatsapp` | v4.16.2 | `channel_whatsapp` | A | ✅ **temos `Whatsapp::HealthService` próprio** | Baixo (DDL) | TRAZER ADAPTADO | M |

### As 8 migrations extras de `upstream/develop` (pós-`v4.16.2`)

| Migration | Tabela | Tipo | Nossa área | Recomendação |
|---|---|---|---|---|
| `20260709060000_add_execution_delay_to_automation_rules` | `automation_rules` | A | ✅ **motor Flow / modo antigo** | AVALIAR DEPOIS |
| `20260709060100_add_status_changed_at_to_conversations` | `conversations` | A | ✅ conversations (nossa) | AVALIAR DEPOIS |
| `20260709060200_create_automation_rule_pending_executions` | nova | A | ✅ **coexiste/compete com `flow_runs`** | AVALIAR DEPOIS |
| `20260715000000_add_completed_at_to_applied_slas` | `applied_slas` | A | — | AVALIAR DEPOIS |
| `20260724000100_add_index_to_conversations_created_at` | `conversations` | A (CONCURRENTLY) | ⚠️ tabela grande + já temos 12 índices próprios | AVALIAR DEPOIS |
| `20260728000001_add_business_management_token_to_channel_whatsapp` | `channel_whatsapp` | A | ✅ WhatsApp | AVALIAR DEPOIS |
| `20260729051500_add_status_updated_at_index_to_automation_rule_pending_executions` | nova | A | — | segue a de cima |
| `20260731140853_create_conversation_outcomes` | nova | A | ✅ Captain (concorre com `captain_conversation_evals`) | AVALIAR DEPOIS |

> `develop` está com **69** features no `features.yml` (63 + 6 em `feature_flags_ext_1`) — a coluna de extensão **já está sendo usada de verdade** upstream, o que confirma que a solução do item #40 é a linha oficial e não um experimento.

---

## 3) Diff de `db/schema.rb`

- Versão deles: `2026_07_18_000000` · Versão nossa: `2026_07_22_120000`.
- Tabelas: base 86 → upstream **95** → nós **125**.

### 3.1 Tabelas que só eles têm (10)
`agent_sessions`, `calls`, `captain_faq_observations`, `captain_faq_suggestions`, `captain_message_reports`,
`data_import_errors`, `data_import_items`, `data_import_mappings`, `platform_banners`, `user_sessions`.

### 3.2 Tabelas que só nós temos (40)
`account_integrations`, `ai_config_changes`, `attachment_bulk_downloads`, `campaign_recipients`,
`captain_assistant_logs`, `captain_conversation_episodes`, `captain_conversation_evals`,
`captain_document_chunks`, `captain_tool_calls`, **`channel_voice`** (eles dropparam),
`contact_flow_suppressions`, `conversation_assignment_histories`, `conversation_pdf_exports`,
`conversation_takeover_requests`, `distribuicao_logs/policies/states`, **`flow_node_stats`, `flow_runs`,
`flows`, `flow_step_logs`**, `funnel_*` (9 tabelas), `internal_channel*`/`internal_messages`,
`message_reactions`, `message_sequence*` (3), `nps_responses`, `report_pdf_exports`, `scheduled_messages`.

> ✅ **`flow_runs` / `flow_step_logs` / `flows` / `flow_node_stats` são 100% invisíveis para o upstream.** Nenhuma das 53 migrations toca neles. O único ponto de atrito é *conceitual*: `develop` cria `automation_rule_pending_executions`, que é o motor de agendamento **deles** para `automation_rules` — funcionalmente concorrente com o nosso `flow_runs`.

### 3.3 Colunas divergentes em tabelas comuns

| Tabela | Só deles | Só nosso |
|---|---|---|
| `accounts` | **`feature_flags_ext_1`** | — |
| `agent_bots` | `secret` | `captain_assistant_id` |
| `articles` | `draft_title`, `draft_content` | — |
| `assignment_policies` | `exclude_older_than_hours` | — |
| `campaigns` | — | `template_name`, `template_language`, `target_team_id`, `pacing_seconds`, `dispatch_status`, `dispatch_config` |
| `canned_responses` | — | `visibility`, `created_by_id`, `team_id` |
| `captain_assistant_responses` | `edited` | — |
| `captain_assistants` | — | `behavior` |
| `captain_custom_tools` | — | `copilot_only` |
| `captain_documents` | `sync_status`, `last_synced_at`, `last_sync_attempted_at` | — |
| `categories` | `icon_color` | — |
| `channel_api` | `secret` | — |
| `channel_email` | `imap_authentication` | — |
| `channel_twilio_sms` | `voice_enabled`, `twiml_app_sid`, `api_key_secret`, `provider_config` | — |
| `channel_whatsapp` | `phone_number_health`, `..._checked_at`, `..._error` | — |
| `companies` | `additional_attributes`, `custom_attributes`, `last_activity_at` | — |
| `conversations` | — | `assignee_last_changed_at` |
| `data_imports` | 13 colunas novas (Intercom) | — |
| `email_templates` | `inbox_id` | — |
| `inboxes` | — | `waha_session_name`, `nps_survey_enabled`, `nps_config`, `team_message_isolation`, `pending_status_enabled`, `additional_attributes`, `agent_message_isolation`, `agent_conversation_isolation` |
| `labels` | — | `visibility`, `created_by_id`, `team_id` |
| `messages` | — | `team_id`, `forwarded`, `forwarded_from_message_id`, `starred`, `agent_id` |
| `teams` | `icon`, `icon_color` | — |

**Nenhuma coluna com o mesmo nome e tipo diferente.** Não há sobreposição direta de coluna — todas as adições deles caem em nomes livres no nosso schema.

### 3.4 Onde o nosso schema divergiu a ponto de a migration deles falhar / virar redundante

| Situação | Detalhe | Efeito na migration deles |
|---|---|---|
| **Índices removidos por nós** | `20260328150309_remove_redundant_indexes_and_convert_to_brin` dropou `index_conversations_on_account_id`, `index_conversations_on_status_and_account_id`, `index_messages_on_created_at`, `index_reporting_events_on_created_at` e criou versões **BRIN** | O `db/schema.rb` deles ainda lista os B-tree. **Merge de `schema.rb` à mão reintroduz os índices que a gente apagou de propósito.** Sempre regerar. |
| `contacts.blocked` | Nós trocamos `index_contacts_on_blocked` por parcial `idx_contacts_blocked WHERE blocked = true` | Idem: divergência só de `schema.rb`, nenhuma migration deles depende. |
| `messages` | Nós temos **20 índices**, eles 13 (3 GIN trigram + 1 BRIN + 5 compostos nossos) | `add_index :messages, [:sender_type, :sender_id, :created_at]` **é válido** e não redundante, mas encarece writes (21º índice). |
| `email_templates` | Nosso schema ainda tem só `index_email_templates_on_name_and_account_id` | `20260706000000` **aborta com `ActiveRecord::IrreversibleMigration`** se existir template de instalação duplicado por `(name, template_type, locale)`. Precisa pré-check. |
| `captain_documents.external_link` | Nosso: `string NOT NULL` + `index_captain_documents_on_assistant_id_and_external_link` (nome idêntico ao deles) | `20260525093000` roda limpo — o índice que ele remove existe com o mesmo nome. |
| `data_imports` | Nosso ainda é o original (`data_type`, `processing_errors`, …) | `20260702000000` é puramente aditivo → roda limpo. |
| **Foreign keys** | Nós: **93** `add_foreign_key`. Eles: **4**. | Nenhuma FK nossa aponta para `captain_assistant_responses`, `captain_documents`, `channel_voice` ou `channel_api` — então nenhum `DELETE`/`DROP` deles esbarra em FK. Verificado linha a linha em `db/schema.rb`. |
| `channel_voice` | Tabela ainda existe no nosso schema **e é usada** | `drop_channel_voice` derruba o `Channel::Voice`. Ver §5.2. |

---

## 4) 🔴 O problema central: `config/features.yml` e o bitmask

Isto não aparece na lista de migrations, mas é **o maior risco de dado** de todo o merge — porque 8 das
45 migrations deles são exatamente `Repurpose*Flag*` e **dependem da ordem dos bits**.

### 4.1 Como está hoje

| | base `v4.12.1` | upstream `v4.16.2` | **nós (HEAD)** |
|---|---|---|---|
| Total de features | 63 | **68** (63 + 5 em `feature_flags_ext_1`) | **65 — todas numa coluna só** |
| `Featurable` | 1 coluna | multi-coluna, `MAX_FEATURES_PER_COLUMN = 63` | **idêntico ao base** (`git diff base..HEAD -- app/models/concerns/featurable.rb` = vazio) |

`config/features.yml:245` — nossa 65ª feature. `FlagShihTzu` mapeia a n-ésima feature para `2^(n-1)`:

- bit 64 = `conversation_required_attributes` → `2^63` = 9223372036854775808
- bit 65 = `advanced_assignment` → `2^64`

O máximo de um `bigint` do Postgres é 9223372036854775807. Ou seja:

> **`conversation_required_attributes` e `advanced_assignment` não podem ser ligados em nenhuma conta hoje.**
> A leitura (`account.feature_advanced_assignment?`) devolve `false` silenciosamente para sempre; a escrita e o
> scope (`Account.feature_advanced_assignment`) geram literal SQL fora do range do `bigint`.
> As duas estão com `enabled: false` no `features.yml`, então **a criação de conta não quebra** — o bug é latente.
> `advanced_assignment` tem 8 referências no código; `conversation_required_attributes`, 2.

**Confirmação pendente em runtime** (não executei nada contra o banco): ver §7.

### 4.2 As 8 divergências de bit — merge ingênuo = corrupção de flag

Comparação posicional dos três `features.yml`:

| Bit | `v4.12.1` (base) | upstream `v4.16.2` | **nós** | Consequência do merge cru |
|---|---|---|---|---|
| 4 | `channel_twitter` | `conversation_unread_counts` | `channel_twitter` | Contas com Twitter ligado passam a ter `conversation_unread_counts` ligado |
| **29** | `response_bot` | `custom_tools` | **`message_sequences`** | 🔴 quem tem `message_sequences` vira `custom_tools`; a migration #4 então **desliga** o bit → **perdemos `message_sequences` de todas as contas** |
| **30** | `message_reply_to` | `message_reply_to` | **`internal_chat`** | 🔴 nós **sobrescrevemos** `message_reply_to` (sumiu do nosso yml). Merge devolve `message_reply_to` no bit do `internal_chat` |
| 31 | `insert_article_in_reply` | `branded_email_templates` | `insert_article_in_reply` | migration #39 desliga o bit |
| **39** | `report_v4` | `captain_v1_action_classifier` | **`ai_assistant_v2`** | 🔴 quem tem `ai_assistant_v2` vira `captain_v1_action_classifier`; migration #18 **desliga** → perdemos `ai_assistant_v2` |
| 52 | `twilio_content_templates` | `captain_document_auto_sync` | `twilio_content_templates` | migration #14 desliga o bit |
| 57 | `quoted_email_reply` | `unread_count_for_filters` | `quoted_email_reply` | migration #32 desliga o bit |
| **61–65** | 61 `captain_tasks`, 62 `conversation_required_attributes`, 63 `advanced_assignment` | idem base | **61 `kanban_cursor_loading`, 62 `kanban_ux_v2`, 63 `captain_tasks`, 64/65 estourados** | 🔴 **deslocamento de 2 bits**: `captain_tasks` (6 refs no código) muda de posição; contas com Kanban ligado passariam a ler `captain_tasks`/`conversation_required_attributes` |

### 4.3 Procedimento seguro (obrigatório antes de qualquer merge de `features.yml`)

1. **Trazer `Featurable` multi-coluna + migration #40** (`feature_flags_ext_1`) primeiro, isolado.
2. **Congelar os bits 1–63 no nosso layout atual.** Nada de reordenar. As features deles que hoje ocupam bits divergentes (`custom_tools`, `message_reply_to`, `captain_v1_action_classifier`, `conversation_unread_counts`, `branded_email_templates`, `unread_count_for_filters`, `captain_document_auto_sync`) entram **no fim de `feature_flags_ext_1`**, não nos bits originais deles.
3. **Mover `conversation_required_attributes` e `advanced_assignment` (bits 64/65) para `feature_flags_ext_1`** — corrige o bug latente. Como hoje eles são sempre `false`, **não há dado a migrar**.
4. **Não trazer as migrations `Repurpose*` como estão** (#4, #14, #18, #20, #32, #39): elas assumem o layout de bits do upstream. Reescrever como no-op ou adaptar ao nosso layout.
5. Rodar um `rake feature_defaults:toggle` (novo em v4.16.0, `lib/tasks/feature_defaults.rake`) ou script próprio para reconciliar `ACCOUNT_LEVEL_FEATURE_DEFAULTS` depois.

---

## 5) Data migrations / backfills — os mais perigosos

Não existe `db/data_migrate` nem `db/data` em nenhum dos dois lados. Os backfills vivem **dentro** de `db/migrate`, mais 1 job dedicado e 4 rake tasks novas.

### 5.1 🔴 `20260714123000_purge_pending_captain_assistant_responses` (v4.16.2, `7910eabefc`) — **DESCARTAR**

```ruby
def up
  execute('DELETE FROM captain_assistant_responses WHERE status = 0')
end
def down; end
```

- Upstream **removeu `pending` do enum**: `git show v4.16.2:enterprise/app/models/captain/assistant_response.rb` → `enum status: { approved: 1 }`. Para eles, `status = 0` é lixo órfão. Eles migraram o conceito de "sugestão pendente" para as novas tabelas `captain_faq_suggestions` / `captain_faq_observations` (#43).
- **No nosso fork `status 0` é `pending` e é um estado vivo:**
  - `enterprise/app/models/captain/assistant_response.rb:45` → `enum status: { pending: 0, approved: 1 }`
  - `enterprise/app/controllers/api/v1/accounts/captain/bulk_actions_controller.rb:40` → `responses.pending.update(status: 'approved')`
- Efeito: **apaga todas as FAQs pendentes de aprovação de todos os clientes**, sem batch, sem `down`, sem backup. Um único `DELETE` — lock longo e WAL pesado se a tabela for grande.
- **Não há FK apontando para `captain_assistant_responses` no nosso schema**, então o `DELETE` não seria barrado — ele simplesmente executa.
- Só faz sentido trazer **junto** com o pacote FAQ Suggestions (#43) e depois de migrar nossos `pending` para lá.

### 5.2 🔴 `20260326120001_drop_channel_voice` (v4.14.0, `0e122188e9`) — **DESCARTAR**

`drop_table :channel_voice, if_exists: true`. O upstream **apagou** `enterprise/app/models/channel/voice.rb` no mesmo intervalo (`git diff --name-status base..v4.16.2 -- enterprise/app/models/channel/` → `D enterprise/app/models/channel/voice.rb`) e moveu voz para `channel_twilio_sms` (#5, #23). Nós ainda temos o modelo **e** os consumidores:

`enterprise/app/models/channel/voice.rb`, `enterprise/app/controllers/twilio/voice_controller.rb`,
`enterprise/app/controllers/api/v1/accounts/contacts/calls_controller.rb`,
`enterprise/app/builders/enterprise/contact_inbox_builder.rb`,
`enterprise/app/builders/enterprise/messages/message_builder.rb`,
`enterprise/app/services/enterprise/contacts/contactable_inboxes_service.rb`,
`app/javascript/dashboard/components/widgets/ChannelItem.vue`, `.../ChannelName.vue` (+ `VoiceCall.vue`, `VoiceCallStatus.vue` que **nós** modificamos).

Trazer o drop sem trazer o refactor inteiro = `PG::UndefinedTable` em runtime. Se um dia for trazer, é o pacote todo (#5 + #6 + #8 + #23 + #28 + #30) e é **G**.

### 5.3 🔴 `20260515000000_enqueue_validate_openai_hooks_job` (v4.14.0, `3253e863ed`) — **TRAZER ADAPTADO**

A migration é uma linha (`Migration::ValidateOpenaiHooksJob.perform_later`), mas o job (`app/jobs/migration/validate_openai_hooks_job.rb`, novo) **destrói dados de integração de cliente**:

```ruby
scope = Integrations::Hook.where(app_id: 'openai', status: 'enabled')
... next if Integrations::Openai::KeyValidator.valid?(hook.settings&.dig('api_key'))
AdministratorNotifications::IntegrationsNotificationMailer...openai_disconnect.deliver_later
hook.destroy!
```

- O `KeyValidator` bate em `#{CAPTAIN_OPEN_AI_ENDPOINT}/v1/models` e só considera inválido em **HTTP 401**; erro de rede devolve `true` (fail-safe correto).
- **O risco para nós é o endpoint custom.** Se `CAPTAIN_OPEN_AI_ENDPOINT` da VM apontar para proxy/gateway que responde 401 em `/v1/models` (rota que ele pode não expor), o job **destrói hooks válidos de todas as contas** e dispara e-mail de "OpenAI desconectado" para os admins dos clientes.
- Recomendação: trazer o job, **não** trazer a migration que o enfileira. Rodar manualmente por conta (`perform_now(account: acc)`) depois de conferir o endpoint.

### 5.4 ⚠️ `20260324070835_backfill_agent_bot_and_channel_api_secrets` (v4.13.0) — **TRAZER ADAPTADO**

Usa `agent_bot.update!(secret: ...)` — **roda as validações do modelo**. O nosso `AgentBot` ganhou regras que o do upstream não tem (`app/models/agent_bot.rb:47-49`):

```ruby
validates :captain_assistant_id, presence: true, if: :captain?
validates :captain_assistant_id, absence: true, if: :webhook?
validates :outgoing_url, absence: true, if: :captain?
```

Qualquer linha legada inconsistente (bot `captain?` sem `captain_assistant_id`, ou com `outgoing_url` preenchido) faz o `update!` levantar `RecordInvalid` e **abortar a migration no meio** — parte da frota fica com `secret` preenchido e parte não. Trocar por `update_column(:secret, ...)` ou `update_all` em batch.

### 5.5 Demais backfills (risco médio/baixo)

| Migration | O que faz | Tabela | Observação |
|---|---|---|---|
| `20260410092753_backfill_edited_on_captain_assistant_responses` | `update_all(edited: true)` em batches de 1000 onde `updated_at - created_at > 15 dias` | `captain_assistant_responses` | heurística; batched; `ChatwootApp.enterprise?` guard; reversível na prática |
| `20260428120000_backfill_captain_document_sync_metadata` | `update_all('sync_status = 1, last_synced_at = updated_at')` em batches | `captain_documents` | batched; guard enterprise; idempotente (`sync_status: nil`) |
| `20260427094500_rename_company_condition_key_in_automation_rules` | reescreve JSON de `conditions` (`company` → `company_name`) em `automation_rules` **e** `custom_filters` | `automation_rules`, `custom_filters` | usa `update_column` (sem validação) — seguro; `down` vazio (**irreversível**); ⚠️ é a **única** migration deles que mexe em `automation_rules` |
| `20260618000000_backfill_rejected_call_status` | `UPDATE calls SET status='rejected' …` | `calls` | inócua para nós (tabela não existe até trazermos #8) |
| `20260409091202_enable_assignment_v2_for_new_accounts` | liga `assignment_v2` no `ACCOUNT_LEVEL_FEATURE_DEFAULTS` | `installation_configs` | muda comportamento de **conta nova**; conflita com a nossa política (`20260226130000_set_captain_default_features_disabled`, `20260703170000_change_default_account_locale_to_pt_br`) |
| `20260324102005` / `20260426011444` / `20260430114500` / `20260508000000` / `20260629000000` / `20260706000001` | 6× `Repurpose*Flag*`: `account.disable_features(:x); account.save!(validate: false)` + remove a entrada velha do `ACCOUNT_LEVEL_FEATURE_DEFAULTS` | `accounts`, `installation_configs` | `save!(validate: false)` é seguro; **o perigo é o layout de bit** (§4.2), não a mecânica |

### 5.6 Rake tasks novas (não rodam sozinhas, mas mexem em dado)

| Task | O que faz | Risco |
|---|---|---|
| `lib/tasks/captain_assistant_migration.rake` | `generate` (LLM classifica instruções do assistente → JSONL), `apply` (**escreve** no assistente, `DRY_RUN=true` por padrão), `restore_messages` | ⚠️ Chama LLM sobre config de cliente. Se um dia usarmos, **só com `DRY_RUN=true`** primeiro (regra da casa). |
| `lib/tasks/feature_defaults.rake` | toggle interativo de `ACCOUNT_LEVEL_FEATURE_DEFAULTS` | Útil — vale trazer junto com §4.3 passo 5 |
| `lib/tasks/ruby_llm.rake` | regenera `config/llm_models.json` | Baixo |
| `lib/tasks/storage_migrations.rake` | move blobs entre ActiveStorage services | Baixo (manual) |

---

## 6) Ordem segura de aplicação e janela de manutenção

### 6.1 Pré-flight (antes de qualquer `db:migrate`)

```bash
# 1. Nenhum timestamp duplicado (o que trava a frota)
ls db/migrate | sed -E 's/^([0-9]+)_.*/\1/' | sort | uniq -d      # tem que sair VAZIO
# 2. Nenhum nome de classe duplicado
ls db/migrate | sed -E 's/^[0-9]+_(.*)\.rb/\1/' | sort | uniq -d  # tem que sair VAZIO
# 3. Pré-check do #38 (email_templates) — se voltar linha, a migration ABORTA
SELECT name, template_type, locale, COUNT(*) FROM email_templates
 WHERE account_id IS NULL GROUP BY 1,2,3 HAVING COUNT(*) > 1;
# 4. Quanto o #44 apagaria (se alguém insistir em trazê-la)
SELECT count(*) FROM captain_assistant_responses WHERE status = 0;
# 5. Bots que fariam o #3 abortar
-- bot_type: { webhook: 0, captain: 1 }  (app/models/agent_bot.rb:44)
SELECT id FROM agent_bots WHERE bot_type = 1 AND (captain_assistant_id IS NULL OR outgoing_url IS NOT NULL);
```

### 6.2 Ordem sugerida — 4 ondas

**Onda 0 — corrigir o que já está quebrado (independe do merge).**
`Featurable` multi-coluna + `20260706215758` (`feature_flags_ext_1`) + mover bits 64/65 do nosso `features.yml` para a coluna nova. Zero migração de dado (as duas features estão sempre `false`). **Sem janela.**

**Onda 1 — aditivas puras, sem lock relevante.** Podem ir juntas, online:
`#1 #2 #5 #7 #8 #10 #11 #13 #17 #19 #23 #24 #25 #26(re-carimbada) #27 #29 #31 #34 #35 #36 #37 #41 #45`
Todas são `add_column` nullable / `create_table` / índice em tabela pequena. **Sem janela.**

**Onda 2 — índices `CONCURRENTLY` em tabela grande.** Um de cada vez, fora de pico, com `disable_ddl_transaction!` (já vem):
- `#33 20260630000000` → `messages (sender_type, sender_id, created_at)` — **a mais cara**. `messages` é a maior tabela e já carrega **20 índices** nossos (3 GIN trigram + 1 BRIN). Estimar por VM antes. **Janela recomendada** (não bloqueia escrita, mas consome I/O e pode falhar deixando índice `INVALID` — conferir `pg_index.indisvalid` depois).
- `#30 20260622000000` → `calls` (vazia para nós).
- `develop 20260724000100` → `conversations (created_at)` — tabela grande, já temos 12 índices próprios; avaliar se é redundante com `idx_conv_list_keyset`.

**Onda 3 — transformadoras e backfills.** Uma a uma, com contagem antes/depois:
- `#22 20260525093000` (`captain_documents.external_link` → `text`): `varchar` sem limite → `text` é **metadata-only** no PG (sem rewrite), mas o `add_index ... md5(external_link)` **não é `CONCURRENTLY`** → **trava escrita em `captain_documents`** enquanto constrói. Janela se a tabela for grande.
- `#42 20260710000000` (`captain_assistants.description` → `text`): idem, tabela pequena. Sem janela.
- `#12`, `#16` (backfills batched) — sem janela, monitorar.
- `#3` (adaptado para `update_column`) — sem janela.
- `#15 20260427094500` (rename de condition key) — tabela pequena; **irreversível**, fazer dump de `automation_rules.conditions` antes.
- `#38 20260706000000` (email_templates) — depois do pré-flight #3.
- `#9` — decisão de produto, não técnica.

**Nunca aplicar:** `#6` (drop_channel_voice), `#44` (purge pending), `#21` como migration (só o job, manual).
**Reescrever antes de aplicar:** `#4 #14 #18 #20 #32 #39` (os `Repurpose*`) — ver §4.3.

### 6.3 Resumo do que exige janela

| Migration | Tabela | Por quê |
|---|---|---|
| `#33` `add_sender_created_index_to_messages` | `messages` | índice novo em tabela gigante; I/O; 21º índice |
| `develop 20260724000100` | `conversations` | idem |
| `#22` `change_captain_document_external_link_to_text` | `captain_documents` | `add_index` **não-concurrent** → lock de escrita |
| `#44` (se insistirem) | `captain_assistant_responses` | `DELETE` único, sem batch → lock + WAL |
| `#38` | `email_templates` | remove/cria 4 índices únicos não-concurrent (tabela pequena — janela curta) |

`reporting_events`: **nenhuma** migration do upstream toca. Nossa única divergência ali é o BRIN (`index_reporting_events_on_created_at_brin`), que sobrevive ao merge desde que o `schema.rb` seja regerado.

---

## 7) Riscos e pegadinhas

1. **`db/schema.rb` não se merga — se regera.** Nossa versão (`2026_07_22_120000`) é mais nova que a deles (`2026_07_18_000000`) e nós **removemos índices de propósito** (BRIN). Resolver conflito de `schema.rb` à mão reintroduz `index_messages_on_created_at`, `index_conversations_on_account_id`, `index_conversations_on_status_and_account_id` e `index_reporting_events_on_created_at`, desfazendo `20260328150309` na próxima carga de schema. Procedimento: aceitar qualquer lado no conflito, rodar `db:migrate` num banco atualizado, commitar o `schema.rb` gerado.
2. **Re-carimbar migration ≠ apagar migration.** Ver o aviso da §1: a frota já tem `20260616120000` e `20260630000000` em `schema_migrations`.
3. **`add_feature_flags_ext_2_to_accounts` cria a coluna `feature_flags_ext_1`.** Nome de arquivo/classe diz "ext_2", a coluna é "ext_1". Não é bug, é confuso — não renomear achando que é typo.
4. **`ChatwootApp.enterprise?` gateia 2 backfills** (`#12`, `#16`). Se alguma VM da frota rodar sem enterprise, esses dados não são preenchidos e a `sync_status` fica `NULL` — o código deles trata, mas vale saber.
5. **93 FKs nossas vs 4 deles.** Nenhuma bate nas tabelas que eles alteram (verificado), mas qualquer migration futura do upstream que faça `DELETE`/`DROP` tem chance muito maior de esbarrar em constraint no nosso banco do que no deles. Somado ao já conhecido `flow_runs`/`flow_step_logs` bloqueando `conversation.destroy!`.
6. **`develop` traz o motor de agendamento deles para `automation_rules`** (`execution_delay` + `automation_rule_pending_executions` + índice). Isso é funcionalmente o que o nosso `flow_runs` faz. Trazer os dois cria dois agendadores no mesmo banco — decisão de arquitetura, não de migration.
7. **`agent_sessions` (#41) e `conversation_outcomes` (develop) competem com `captain_conversation_evals`/`captain_tool_calls`/`captain_conversation_episodes`.** Não colidem no schema (nomes diferentes), mas trazer os dois duplica telemetria de Captain.
8. **`20260427094500` tem `def down; end`** — irreversível de fato. Idem `#4`, `#14`, `#18`, `#20`, `#21`, `#32`, `#39`, `#44` (todos sem `down` funcional).
9. **`Whatsapp::HealthService` (nosso) não persiste nada** — lê `provider_config` e consulta a Graph API on-demand (`app/services/whatsapp/health_service.rb:23-40`). A migration `#45` cria as colunas de cache que o upstream usa. A DDL é inofensiva; o conflito real é no **código** do serviço (nós divergimos dele desde a base) — território do worker de código, não deste relatório.

---

## 8) O que eu NÃO consegui apurar

1. **Confirmação em runtime do overflow do bitmask.** A aritmética é determinística (`2^63 > bigint max`), mas não executei `Account.first.update!(feature_advanced_assignment: true)` para ver a exceção exata (`ActiveRecord::RangeError` vs `PG::NumericValueOutOfRange`) — auditoria read-only, e o banco local pede senha (`psql -U chatwoot -h localhost` → `fe_sendauth: no password supplied`).
2. **Volumes reais.** Não consultei nenhum banco de cliente, então não sei: quantas linhas `captain_assistant_responses.status = 0` seriam apagadas por `#44`; quantos `agent_bots` fariam `#3` abortar; se há `email_templates` de instalação duplicados (que abortam `#38`); nem o tamanho de `messages`/`conversations` por VM para dimensionar a janela da Onda 2. As queries estão prontas em §6.1.
3. **Se algum cliente hoje usa `Channel::Voice` de fato** (existe código, não sei se existe linha em `channel_voice`).
4. **Se `CAPTAIN_OPEN_AI_ENDPOINT` de alguma VM aponta para proxy** — é o que decide se o job do `#21` é inofensivo ou destrutivo.
5. **Migrations do upstream posteriores a `03/08/2026`** (o `upstream/develop` local está no HEAD daquele dia).

---

### Anexo — comandos usados

```bash
BASE=899fce1c9286b793d165c8ad6c0200ab676f185b
git diff --name-only --diff-filter=A $BASE..v4.16.2 -- db/migrate enterprise/db/migrate   # 45
git diff --name-only --diff-filter=A $BASE..HEAD     -- db/migrate enterprise/db/migrate   # 105
git diff --name-only --diff-filter=A v4.16.2..upstream/develop -- db/migrate               # 8
# colisão de timestamp
comm -12 <(...theirs | sed -E 's#.*/([0-9]+)_.*#\1#' | sort) \
         <(git ls-tree -r --name-only HEAD -- db/migrate | sed -E 's#.*/([0-9]+)_.*#\1#' | sort)
# schema
git show v4.16.2:db/schema.rb ; git show HEAD:db/schema.rb
# features
git show v4.16.2:config/features.yml | grep -oP '^- name: \K.*' | nl
```
