# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: 3.4.4 — manage via `rbenv` (install with `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)
- **Production build**: `RAILS_ENV=production bundle exec rake assets:precompile` then send `kill -USR2 <puma-pid>` to reload

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:
  - Do not write custom CSS
  - Do not use scoped CSS
  - Do not use inline styles
  - Always use Tailwind utility classes
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- MVP focus: Least code change, happy-path only
- No unnecessary defensive programming
- Ship the happy path first: limit guards/fallbacks to what production has proven necessary, then iterate
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code
- Don't write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## Project-Specific

- **Translations**:
  - Only update `en.yml` (backend) and `en.json` (frontend) as the source of truth
  - Also update `pt_BR/conversation.json` and `pt/conversation.json` for pt-BR keys (this project uses pt-BR in production)
  - Other languages are handled by the community
  - Frontend locale files live under `app/javascript/dashboard/i18n/locale/<lang>/`
- **Frontend**:
  - Use `components-next/` for new components (especially message bubbles); the old `components/` tree is being deprecated
  - Frontend architecture: Vuex (migrating gradually to Pinia), Vue 3 Composition API, `<script setup>` everywhere in `components-next/`
  - API clients extend `ApiClient` (`app/javascript/dashboard/api/`); each module exports a singleton instance
  - Composables live in `app/javascript/dashboard/composables/`; use `useStore()`, `useI18n()`, `useAlert()`, `useTrack()`
  - Global events use `mitt` emitter: `import { emitter } from 'shared/helpers/mitt'` with constants from `BUS_EVENTS`

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles
- Services follow `<Namespace>::<Action>Service` naming, expose a single `perform` method, raise `StandardError` with descriptive messages on failure
- Builders follow `<Resource>Builder` naming with `perform` as the main method

## System Architecture

### Multi-tenancy
Every table with customer data has `account_id`. Unique indexes are always per-account (e.g., email unique per account, phone unique per account). Conversations get per-account `display_id` via a DB trigger and sequence `conv_dpid_seq_<account_id>`.

### Key model relationships
```
Account → Inbox (polymorphic channel) → ContactInbox ← Contact
                                      ↓
                                 Conversation → Message (has_many attachments)
```

### Message key fields
- `message_type` enum: `incoming: 0`, `outgoing: 1`, `activity: 2`, `template: 3`
- `content_type` enum: `text: 0`, `input_csat: 9`, `form: 6`, `incoming_email: 8`, `voice_call: 13`
- `status` enum: `sent: 0`, `delivered: 1`, `read: 2`, `failed: 3`
- `content_attributes` (JSONB) stores: `deleted`, `in_reply_to`, `email`, `submitted_values`, `previous_content`, `edited`, `edited_at`, `edited_by`, `translations`, `is_unsupported`
- `source_id` — channel-specific external message ID (nil for WAHA outgoing messages)
- `private: true` = internal note, not visible to contact

### Conversation key fields
- `status` enum: `open`, `resolved`, `pending`, `snoozed`
- `custom_attributes` (JSONB) — CRM custom fields
- `additional_attributes` (JSONB) — referer, conversation_language, type (tweet), chat_id (Telegram)

### Contact custom_attributes (JSONB) — WAHA fields
- `waha_whatsapp_chat_id` — primary WhatsApp JID (e.g., `"5511999999999@c.us"`)
- `waha_whatsapp_jid` — alternative JID field (checked first, then falls back to chat_id)
- `whatsapp_number_exists` — boolean from validation job
- `whatsapp_last_checked_at`, `whatsapp_validation_source`

### Channel polymorphism
`Inbox#channel_type` + `Inbox#channel_id` → one of: `Channel::Api`, `Channel::WebWidget`, `Channel::Email`, `Channel::Whatsapp`, `Channel::FacebookPage`, `Channel::Telegram`, `Channel::TwilioSms`, etc.
Helper methods: `inbox.api?`, `inbox.email?`, `inbox.whatsapp?`, etc.

### Event dispatch system
```
Model callback → Rails.configuration.dispatcher.dispatch(EVENT_NAME, time, data)
  → SyncDispatcher  → ActionCableListener  → ActionCableBroadcastJob → WebSocket clients
  → AsyncDispatcher → EventDispatcherJob   → WebhookListener (sends webhooks)
                                           → AutomationRuleListener
```
Event constants live in `lib/events/types.rb` (e.g., `MESSAGE_CREATED`, `MESSAGE_UPDATED`, `CONVERSATION_STATUS_CHANGED`).

### ActionCable real-time
Messages and conversations are broadcast over ActionCable automatically after `message.update!` via `after_update_commit :dispatch_update_event`. No manual broadcast needed.

## WAHA Integration (Custom WhatsApp via Channel::Api)

WAHA (WhatsApp HTTP API) is a custom WhatsApp integration built on top of `Channel::Api`.

### Identifying a WAHA inbox
```ruby
inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?
```
`waha_session_name` is a string column on the `inboxes` table (migration: `20251202210211`).

### Key files
- `app/services/waha/api_service.rb` — HTTP client (GET, POST, PUT). Env vars: `WAHA_API_URL` (default `http://localhost:3000`), `WAHA_API_KEY`. Timeout: 10s (below rack-timeout of 15s).
- `app/controllers/api/v1/accounts/waha_connections_controller.rb` — CRUD + QR code + connect/disconnect/restart
- `app/policies/waha_connection_policy.rb` — admin-only
- `app/javascript/dashboard/api/wahaConnections.js` — frontend API client
- `app/services/messages/update_content_service.rb` — edits WAHA messages (via PUT on WAHA API)
- `docs/waha-lid-normalizacao.md` — documentation on LID→PN normalization

### chat_id derivation (for WAHA API calls)
3-tier fallback in order:
1. `contact.custom_attributes['waha_whatsapp_chat_id']`
2. `contact_inbox.source_id` (if contains `@`)
3. `"+#{phone_number}@c.us"` constructed from phone

### WAHA outgoing message source_id
WAHA **never** writes back the WhatsApp message ID to Chatwoot's `source_id`. When editing, the service fetches recent messages from WAHA API and matches by content + timestamp (±900s window).

### LID to Phone Number normalization
WhatsApp LIDs (`@lid` suffix) are resolved to phone numbers via `GET /api/{session}/contacts/{lid}`. If resolution fails, the LID is used as-is. See `normalize_waha_contact_params` in `app/controllers/public/api/v1/inboxes_controller.rb`.

### WAHA edit echo suppression
When a message is edited, WAHA sends a webhook back to Chatwoot as a new incoming message with format: `{content}\n\n✏️ {locale_text}`. This is detected and suppressed in `Public::Api::V1::Inboxes::MessagesController#create` via the pattern `/\n✏️/`.

### Frontend WAHA inbox detection
The inbox jbuilder exposes `waha_session_name` in the API response (`app/views/api/v1/models/_inbox.json.jbuilder`). In Vue: `inbox.waha_session_name.present?` (or `!!inbox.waha_session_name` in JS).

### Brazil phone normalization
`Contacts::BrazilPhoneNormalizer.normalize(phone)` — adds the 9th digit for BR mobile numbers, validates E.164 format.

## Infrastructure

### Rack timeout
**15 seconds** — any service calling an external API (WAHA, WhatsApp, etc.) must complete within this limit. Set all external HTTP client timeouts to ≤10s.

### Background jobs (Sidekiq)
Config: `config/sidekiq.yml`. Queues from highest to lowest priority: `critical`, `high`, `medium`, `default`, `mailers`, `low`, `scheduled_jobs`, `deferred`, `purgable`, `housekeeping`. Concurrency: 15 (production), configurable via `SIDEKIQ_CONCURRENCY`.

### Key environment variables
| Variable | Default | Purpose |
|---|---|---|
| `WAHA_API_URL` | `http://localhost:3000` | WAHA API base URL |
| `WAHA_API_KEY` | — | Optional WAHA API key |
| `FRONTEND_URL` | — | Public app URL (used in webhooks) |
| `REDIS_URL` | `redis://127.0.0.1:6379` | Redis connection |
| `RAILS_MAX_THREADS` | `5` | Puma threads + DB pool size |
| `POSTGRES_STATEMENT_TIMEOUT` | `14s` | DB query timeout |
| `SIDEKIQ_CONCURRENCY` | `15` | Sidekiq worker count |

### Asset pipeline
Vite (`vite.config.ts`). Source: `app/javascript`. Dev server on port 3036. Production: `RAILS_ENV=production bundle exec rake assets:precompile`.

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs:
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.
- Enterprise module injection: `prepend_mod_with('Foo')` looks for `Enterprise::Foo` in `enterprise/app/`. Use `prepend_mod_with` to override methods; `include_mod_with` to extend.
