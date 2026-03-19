# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Processes**: backend (Rails on port 3000), worker (Sidekiq), vite (dev server on port 3036)
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
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
  - 58 languages supported; English has 44 JSON locale files organized by feature

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles
- Services follow `<Namespace>::<Action>Service` naming, expose a single `perform` method, raise `StandardError` with descriptive messages on failure
- Builders follow `<Resource>Builder` naming with `perform` as the main method
- Use `pattr_initialize` for service constructors with required (`!`) and optional params

## System Architecture

### Multi-tenancy
Every table with customer data has `account_id`. Unique indexes are always per-account (e.g., email unique per account, phone unique per account). Conversations get per-account `display_id` via a DB trigger and sequence `conv_dpid_seq_<account_id>`. Campaigns get `camp_dpid_seq_<account_id>`.

### Key model relationships
```
Account → Inbox (polymorphic channel) → ContactInbox ← Contact
                                      ↓
                                 Conversation → Message (has_many attachments)
                                      ↓
                                 ConversationParticipant, Mention, Label (taggable)
```

### Account model
- `settings` (JSONB store_accessor): auto_resolve_after, auto_resolve_message, auto_resolve_ignore_waiting, audio_transcriptions, auto_resolve_label, conversation_required_attributes, captain_models, captain_features
- `custom_attributes`, `internal_attributes`, `limits` (JSONB)
- `status` enum: active(0), suspended(1)
- Feature flags via FlagShihTzu bit flags
- After create: dispatches `ACCOUNT_CREATED`, creates default funnel, creates DB sequences

### Conversation model
- `status` enum: `open: 0`, `resolved: 1`, `pending: 2`, `snoozed: 3`
- `priority` enum: `low: 0`, `medium: 1`, `high: 2`, `urgent: 3`
- `custom_attributes` (JSONB) — CRM custom fields
- `additional_attributes` (JSONB) — referer, conversation_language, type (tweet), chat_id (Telegram)
- `cached_label_list` — denormalized labels
- `uuid` — unique, generated via DB trigger
- `display_id` — unique per account via DB trigger
- `can_reply?` — checks message window (MessageWindowService)
- `bot_handoff!` — opens conversation, dispatches CONVERSATION_BOT_HANDOFF
- Key callbacks: `before_create :determine_conversation_status`, `after_update_commit :execute_after_update_commit_callbacks`
- Concerns: Labelable, AssignmentHandler, AutoAssignmentHandler, ActivityMessageHandler, ConversationMuteHelpers, SortHandler

### Message model
- `message_type` enum: `incoming: 0`, `outgoing: 1`, `activity: 2`, `template: 3`
- `content_type` enum: `text: 0`, `input_text: 1`, `input_textarea: 2`, `input_email: 3`, `input_select: 4`, `cards: 5`, `form: 6`, `article: 7`, `incoming_email: 8`, `input_csat: 9`, `integrations: 10`, `sticker: 11`, `input_nps: 12`, `voice_call: 13`
- `status` enum: `sent: 0`, `delivered: 1`, `read: 2`, `failed: 3`
- `content_attributes` (JSON store_accessor): deleted, in_reply_to, email, submitted_values, previous_content, edited, edited_at, edited_by, translations, is_unsupported, external_error
- `additional_attributes` (JSONB): campaign_id, automation_rule_id
- `external_source_ids` (JSONB): slack
- `source_id` — channel-specific external message ID (nil for WAHA outgoing messages)
- `private: true` = internal note, not visible to contact
- `content` max 150,000 chars
- Flood protection: max 60 msgs/minute per conversation
- Attachment limit: 15 per message
- Default scope: `order(created_at: :asc)`
- Key callbacks: `after_create_commit` reopens snoozed/resolved conversations, dispatches events, triggers SendReplyJob
- `valid_first_reply?` — human response, not campaign/bot/automation
- `human_response?` — outgoing from User (not AgentBot)

### Contact model
- `contact_type` enum: visitor(0), lead(1), customer(2)
- `email` — unique per account, case-insensitive
- `phone_number` — unique per account, E.164 format `/\+[1-9]\d{1,14}\z/`
- `identifier` — unique per account, custom external ID
- `custom_attributes` (JSONB) — WAHA fields (see WAHA section) + user-defined CRM fields
- `additional_attributes` (JSONB) — company_name, city, country, social profiles
- Auto-promotes visitors to leads if email/phone/social present (via `Contacts::SyncAttributes`)
- Brazil phone normalization: `Contacts::BrazilPhoneNormalizer.normalize(phone)` adds 9th digit for BR mobile

### ContactInbox model
- `source_id` — channel-specific contact identifier (required, unique per inbox)
- `hmac_verified` — boolean for secure widget identification
- `pubsub_token` — unique, for WebSocket authentication
- Validates source_id format per channel (E.164 for Twilio, WhatsApp JID for WhatsApp)

### User & AccountUser models
- User: Devise auth with 2FA, STI (SuperAdmin inherits from User)
- AccountUser: per-account membership with `role` enum: agent(0), administrator(1)
- `availability` enum: online(0), offline(1), busy(2) — on AccountUser
- `auto_offline` boolean — auto-set offline after inactivity
- Permissions: `administrator? ? ['administrator'] : ['agent']`
- Enterprise: `custom_role_id` extends permissions with granular controls

### Channel polymorphism
`Inbox#channel_type` + `Inbox#channel_id` → one of 12 channel types:
- `Channel::Api` (also base for WAHA), `Channel::WebWidget`, `Channel::Email`
- `Channel::Whatsapp` (providers: default/360Dialog, whatsapp_cloud/Meta)
- `Channel::FacebookPage`, `Channel::Instagram`, `Channel::Telegram`
- `Channel::TwilioSms` (medium: sms, whatsapp), `Channel::TwitterProfile`
- `Channel::Line`, `Channel::Sms` (Bandwidth), `Channel::Tiktok`
- Helper methods: `inbox.api?`, `inbox.email?`, `inbox.whatsapp?`, `inbox.facebook?`, `inbox.telegram?`, etc.

### Inbox model key fields
- `waha_session_name` — for WAHA integration identification
- `enable_auto_assignment`, `auto_assignment_config` (JSONB)
- `lock_to_single_conversation` — important for mobile/SMS
- `csat_survey_enabled`, `csat_config` (JSONB)
- `nps_survey_enabled`, `nps_config` (JSONB)
- `sender_name_type` enum: friendly(0), professional(1)
- `active_bot?` — agent_bot_inbox active OR dialogflow hooks enabled
- `assignable_agents` — members + administrators

## Event Dispatch System
```
Model callback → Rails.configuration.dispatcher.dispatch(EVENT_NAME, time, data)
  → SyncDispatcher  → ActionCableListener  → ActionCableBroadcastJob → WebSocket clients
                     → AgentBotListener
  → AsyncDispatcher → EventDispatcherJob   → WebhookListener (external webhooks)
                                           → AutomationRuleListener
                                           → NotificationListener
                                           → HookListener (Slack, Dialogflow, etc.)
                                           → CsatSurveyListener, NpsSurveyListener
                                           → ParticipationListener
                                           → ReportingEventListener
                                           → CampaignListener
```
Event constants in `lib/events/types.rb`: `MESSAGE_CREATED`, `MESSAGE_UPDATED`, `CONVERSATION_CREATED`, `CONVERSATION_STATUS_CHANGED`, `ASSIGNEE_CHANGED`, `TEAM_CHANGED`, `CONTACT_CREATED/UPDATED/MERGED/DELETED`, `NOTIFICATION_CREATED`, etc.

### ActionCable real-time
- `RoomChannel`: subscribes to user's `pubsub_token` + account channel; broadcasts presence
- `ActionCableBroadcastJob` (queue: critical): smart refresh for conversation updates — fetches fresh data from DB
- Messages and conversations broadcast automatically via `after_update_commit` callbacks

## Notification System

### Notification model
- `notification_type` enum: conversation_creation(1), conversation_assignment(2), assigned_conversation_new_message(3), participating_conversation_new_message(5), conversation_mention(4), sla_missed_*(6-8)
- Polymorphic: `primary_actor` (Conversation), `secondary_actor` (Message)
- After create: queues push + email notification jobs, dispatches to ActionCable

### Notification delivery
- **Push**: Browser WebPush (VAPID), FCM (Firebase), Chatwoot Hub relay (fallback)
- **Email**: `AgentNotifications::ConversationNotificationsMailer` (skips if agent is online or `DISABLE_AGENT_EMAIL_NOTIFICATIONS=true`)
- **Real-time**: ActionCable broadcast to user's pubsub_token with unread_count

### NotificationSetting
- Per-user per-account bit flags for email and push preferences per notification type
- `NotificationSubscription` stores device tokens (browser_push or fcm)

### Who creates notifications
1. `NotificationListener` on conversation_created/assignee_changed/message_created
2. `Messages::NewMessageNotificationService` for assignee and participants
3. `Messages::MentionService` for @mentions: `(mention://user/ID/name)` and `(mention://team/ID/name)`

## Authentication & Authorization

### Authentication paths
1. **DeviseTokenAuth**: Headers `access-token`, `client`, `expiry`, `uid` — 2-month token lifespan, max 25 devices
2. **Access Token**: Header `api_access_token` — for Users and AgentBots, validates via `AccessTokenAuthHelper`
3. **Widget Token**: Header `X-Auth-Token` — decoded via `Widget::TokenService`, extracts contact/inbox
4. **Platform App**: Header `api_access_token` pointing to PlatformApp owner — separate namespace `/platform/api/v1/`
5. **MFA/2FA**: Encrypted OTP + backup codes, 3-step verification via `Mfa::AuthenticationService`
6. **SSO**: Redis-backed 5-min tokens, Google OAuth2, SAML (enterprise)

### Bot access restrictions
AgentBots can only access whitelisted endpoints:
- `conversations` → toggle_status, toggle_priority, create, update, custom_attributes
- `conversations/messages` → create
- `conversations/assignments` → create

### Pundit authorization
- Context: `{ user: Current.user, account: Current.account, account_user: Current.account_user }`
- **Admin-only**: Account, User, Team, Inbox (CRUD), AutomationRule, Campaign, Webhook, WahaConnection, Report
- **All agents**: Conversation (index), Contact (index/show/create/update), Inbox (index/show)
- **Admin or author**: Macro (personal vs global access)
- **Enterprise custom roles**: conversation_manage, conversation_unassigned_manage, conversation_participating_manage, contact_manage, report_manage, knowledge_base_manage

### Current context (`lib/current.rb`)
Thread-safe accessors: `Current.user`, `Current.account`, `Current.account_user`, `Current.executed_by`, `Current.contact`

## API Surface

### Main namespaces
- `/api/v1/accounts/:account_id/*` — Primary authenticated API
- `/api/v2/accounts/:account_id/*` — Reporting/analytics
- `/platform/api/v1/*` — Third-party integration API
- `/public/api/v1/*` — Public widget/contact-facing API
- `/webhooks/*` — Inbound webhook handlers

### Key endpoints
- **Conversations**: CRUD + toggle_status, toggle_priority, mute/unmute, transcript, custom_attributes, attachments
- **Messages**: CRUD + translate, retry; create triggers SendReplyJob
- **Contacts**: CRUD + search, filter, import/export, contactable_inboxes
- **Inboxes**: CRUD + health check, sync_templates, set_agent_bot
- **WAHA Connections**: CRUD + qr_code, connect, disconnect, restart
- **Notifications**: CRUD + read_all, destroy_all

### Webhook controllers
| Route | Controller | Queue |
|---|---|---|
| `POST /webhooks/whatsapp/:phone_number` | WhatsappController | low |
| `POST /webhooks/telegram/:bot_token` | TelegramController | default |
| `POST /webhooks/line/:line_channel_id` | LineController | default |
| `POST /webhooks/sms/:phone_number` | SmsController | default |
| `POST /webhooks/instagram` | InstagramController | default (mutex) |
| `POST /webhooks/tiktok` | TiktokController | default (mutex) |

## Services Layer (191 services)

### Key service patterns
- `Base::SendOnChannelService` — abstract base for all channel senders (template pattern: `perform` → `perform_reply`)
- `ActionService` — handles conversation mutations: assign, label, resolve, snooze, mute, priority
- `FilterService` — base for advanced filtering (Conversations, Contacts)

### Message services (`app/services/messages/`)
- `UpdateContentService` — edit WAHA messages (PUT via WAHA API, ±900s window match)
- `MarkdownRendererService` — per-channel markdown normalization
- `StatusUpdateService` — update message status (prevents read→delivered regression)
- `MentionService` — parse @mentions, create notifications
- `ForwardService` — forward messages with attachments
- `NewMessageNotificationService` — notify assignee + participants

### Channel send services (all extend `Base::SendOnChannelService`)
- `Whatsapp::SendOnWhatsappService` — template or session message via provider
- `Telegram::SendOnTelegramService` — text + attachments, Markdown→HTML, reply-to support
- `Email::SendOnEmailService` — via ConversationReplyMailer
- `Facebook::SendOnFacebookService`, `Instagram::BaseSendService`
- `Twilio::SendOnTwilioService` — template (content_sid) or session
- `Line::SendOnLineService`, `Sms::SendOnSmsService`, `Tiktok::SendOnTiktokService`, `Twitter::SendOnTwitterService`

### Auto-assignment services (`app/services/auto_assignment/`)
- `AssignmentService` — bulk assignment for unassigned conversations
- `AgentAssignmentService` — single conversation assignment with online agent filtering
- `InboxRoundRobinService` — Redis-backed round-robin per inbox
- `RateLimiter` — prevent agent overload

### Other key services
- `Conversations::FilterService` — advanced filtering with counts (mine/assigned/unassigned/all)
- `Contacts::BrazilPhoneNormalizer` — BR phone E.164 normalization
- `MessageTemplates::HookExecutionService` — triggers out-of-office, greeting, email collect templates
- `CsatSurveyService` / `NpsSurveyService` — survey triggers with cooldown, blocklist, business rules
- `Mailbox::ConversationFinder` — strategy pattern for email thread matching (UUID → In-Reply-To → References → New)
- `Crm::Leadsquared::ProcessorService` — LeadSquared CRM sync

## Background Jobs (77 jobs)

### Sidekiq configuration
- **Concurrency**: 15 (production), configurable via `SIDEKIQ_CONCURRENCY`
- **Timeout**: 35 seconds
- **Max retries**: 5
- **Queues** (priority order): critical, high, medium, default, mailers, action_mailbox_routing, low, scheduled_jobs, deferred, purgable, housekeeping, async_database_migration, bulk_reindex_low, active_storage_analysis/purge, action_mailbox_incineration

### Scheduled jobs (Sidekiq-Cron via `config/schedule.yml`)
| Job | Interval | Purpose |
|---|---|---|
| `TriggerScheduledItemsJob` | 5 min | Master scheduler: enqueues resolution, campaigns, snooze reopen, template sync |
| `Inboxes::FetchImapEmailInboxesJob` | 1 min | Trigger IMAP email sync |
| `Inboxes::BulkAutoAssignmentJob` | 15 min | v1 auto-assignment |
| `AutoAssignment::PeriodicAssignmentJob` | 30 min | v2 auto-assignment |
| `Internal::RemoveStaleContactInboxesJob` | Daily 22:30 | Clean orphaned contact_inboxes (>3 months) |
| `Internal::RemoveStaleRedisKeysJob` | Daily 22:30 | Clean stale Redis keys |
| `Internal::ProcessStaleContactsJob` | Daily 04:30 | Remove unidentified contacts (>30 days, no conversations) |
| `Internal::DeleteAccountsJob` | Daily 01:00 | Delete accounts marked for deletion |
| `Internal::CheckNewVersionsJob` | Daily 12:00 | Check for new Chatwoot versions |

### Key job patterns
- `MutexApplicationJob` — distributed Redis locking (used for: IMAP fetch, Facebook/Instagram/TikTok webhooks, Slack, LeadSquared)
- `EventDispatcherJob` (queue: critical, retries: 3) — routes events to async listeners
- `ActionCableBroadcastJob` (queue: critical) — real-time WebSocket broadcasts with smart refresh
- `SendReplyJob` (queue: high, retries: 5) — routes outgoing messages to channel services
- `WebhookJob` (queue: medium, retries: 5) — delivers external webhooks
- `HookJob` (queue: medium) — routes to Slack, Dialogflow, Google Translate, LeadSquared

## Frontend Architecture

### Directory structure
```
app/javascript/
├── dashboard/           # Main dashboard application
│   ├── components-next/ # New Vue 3 Composition API components (USE THIS)
│   ├── components/      # Legacy components (being deprecated)
│   ├── api/             # API clients extending ApiClient
│   ├── store/           # Vuex modules (46+ namespaced, primary state management)
│   ├── stores/          # Pinia stores (2 so far: calls, companies — migration ongoing)
│   ├── composables/     # Vue 3 composables
│   ├── routes/          # Vue Router route definitions
│   ├── helper/          # Utility helpers
│   ├── constants/       # Application constants
│   ├── i18n/            # 58 languages, 44 locale files per language
│   └── modules/         # Feature modules
├── shared/              # Shared code across apps
├── v3/                  # Auth/onboarding views
├── portal/              # Help center portal
└── survey/              # Survey pages
```

### Frontend patterns
- **State**: Vuex (primary, migrating to Pinia). Access via `useStore()`, `useMapGetter()`, `useStoreGetters()`
- **API clients**: Extend `ApiClient` (`app/javascript/dashboard/api/`); each exports singleton instance; account-scoped routes built as `/api/v1/accounts/{accountId}`
- **Composables**: `useStore()`, `useI18n()`, `useAlert()`, `useTrack()`, `useAccount()`, `useAdmin()`, `useInbox()`, `usePolicy()`, `useConfig()`
- **Events**: mitt emitter: `import { emitter } from 'shared/helpers/mitt'` with constants from `BUS_EVENTS`
- **Message bubbles**: `components-next/message/bubbles/` — 30+ bubble types (Text, Image, Audio, Video, File, Email, Location, Contact, CSAT, NPS, Form, VoiceCall, etc.)
- **Feature flags**: `FEATURE_FLAGS` in `dashboard/featureFlags.js`

### WAHA frontend
- API client: `dashboard/api/wahaConnections.js` — getAll, get, create, delete, getQRCode, connect, disconnect, restart
- Settings page: `routes/dashboard/settings/wahaConnections/` — Index.vue (status polling 5s), QRCodeModal.vue, AddConnectionModal.vue
- Inbox detection: `!!inbox.wahaSessionName` (camelCase from API jbuilder)

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

### WAHA API Service methods
- Session: `list_sessions`, `create_session`, `start_session`, `stop_session`, `restart_session`, `delete_session`
- Messages: `edit_message(session, chat_id, msg_id, content)`, `get_messages(session, chat_id, limit:)`
- QR: `get_qr_code(name, format: 'image'|'json')`
- Contacts: `check_contact_exists(session_name:, phone:)`, `get_lid_phone_number(session, lid)`, `get_lids_list(session, limit:, offset:)`
- App: `create_chatwoot_app(session_name:, config:)`

### WAHA Connection creation flow
1. Create WAHA session via API
2. Create `Channel::Api` in transaction
3. Create Inbox with `waha_session_name` and `lock_to_single_conversation: true`
4. Ensure user has access token
5. Create Chatwoot app in WAHA with config (url, accountId, accountToken, inboxId, inboxIdentifier, locale: 'pt-BR')
6. Update channel webhook_url: `{WAHA_API_URL}/webhooks/chatwoot/{session_name}/{app_id}`
7. Start session

### chat_id derivation (for WAHA API calls)
3-tier fallback in order:
1. `contact.custom_attributes['waha_whatsapp_chat_id']`
2. `contact_inbox.source_id` (if contains `@`)
3. `"+#{phone_number}@c.us"` constructed from phone

### Contact custom_attributes (JSONB) — WAHA fields
- `waha_whatsapp_chat_id` — primary WhatsApp JID (e.g., `"5511999999999@c.us"`)
- `waha_whatsapp_jid` — alternative JID field (checked first, then falls back to chat_id)
- `whatsapp_number_exists` — boolean from validation job
- `whatsapp_last_checked_at`, `whatsapp_validation_source`

### WAHA outgoing message source_id
WAHA **never** writes back the WhatsApp message ID to Chatwoot's `source_id`. When editing, the service fetches recent messages from WAHA API and matches by content + timestamp (±900s window).

### LID to Phone Number normalization
WhatsApp LIDs (`@lid` suffix) are resolved to phone numbers via `GET /api/{session}/contacts/{lid}`. If resolution fails, the LID is used as-is. See `normalize_waha_contact_params` in `app/controllers/public/api/v1/inboxes_controller.rb`.

### WAHA edit echo suppression
When a message is edited, WAHA sends a webhook back as a new incoming message with format: `{content}\n\n✏️ {locale_text}`. Detected and suppressed in `Public::Api::V1::Inboxes::MessagesController#create` via pattern `/\n✏️/`.

### Brazil phone normalization
`Contacts::BrazilPhoneNormalizer.normalize(phone)` — adds the 9th digit for BR mobile numbers, validates E.164 format.

## Infrastructure

### Rack timeout
**15 seconds** — any service calling an external API (WAHA, WhatsApp, etc.) must complete within this limit. Set all external HTTP client timeouts to ≤10s.

### Redis usage
- **Alfred pool** (size: 10-15): Round-robin, conversation emails, online presence (namespace: `alfred`, timeout: 2s)
- **Velma pool** (size: 10): Rack Attack rate limiting (namespace: `velma`, timeout: 2s)
- **ActionCable**: Redis pub/sub adapter for WebSocket broadcasts
- Supports Sentinel HA via `REDIS_SENTINELS` env var

### Rate limiting (Rack Attack)
- Global: 3000 req/min per IP (configurable via `RACK_ATTACK_LIMIT`)
- Auth: 5-10 attempts per period per IP/email for login, reset, MFA
- API: conversation transcript (30/hr), attachment upload (60/hr), contact search (100/min), reports (100/min user, 1000/min account)
- Widget: create conversation (6/12hr), update contact (60/hr)

### Key environment variables
| Variable | Default | Purpose |
|---|---|---|
| `WAHA_API_URL` | `http://localhost:3000` | WAHA API base URL |
| `WAHA_API_KEY` | — | Optional WAHA API key |
| `FRONTEND_URL` | — | Public app URL (webhooks, surveys) |
| `REDIS_URL` | `redis://127.0.0.1:6379` | Redis connection |
| `REDIS_SENTINELS` | — | Sentinel HA (format: `host1:port1,host2:port2`) |
| `RAILS_MAX_THREADS` | `5` | Puma threads + DB pool size |
| `POSTGRES_STATEMENT_TIMEOUT` | `30s` | DB query timeout |
| `SIDEKIQ_CONCURRENCY` | `15` | Sidekiq worker count |
| `ENABLE_RACK_ATTACK` | `true` (prod) | Rate limiting toggle |
| `MAILER_SENDER_EMAIL` | — | SMTP from address |
| `ACTIVE_STORAGE_SERVICE` | `local` | File storage: local, amazon, google, microsoft, s3_compatible |
| `ENABLE_ACCOUNT_SIGNUP` | — | `true`, `false`, `api_only` |
| `FORCE_SSL` | `false` | Force HTTPS |
| `LOG_LEVEL` | `info` | Rails log level |
| `SENTRY_DSN` | — | Sentry error monitoring |

### Asset pipeline
Vite (`vite.config.ts`). Source: `app/javascript`. Dev server on port 3036. Dual build: app mode (dashboard/widget) and library mode (SDK, 40KB limit). Production: `RAILS_ENV=production bundle exec rake assets:precompile`.

### Database
- PostgreSQL with pgvector extension
- Connection pool: `SIDEKIQ_CONCURRENCY` (Sidekiq) or `RAILS_MAX_THREADS` (Puma)
- Reaping frequency: 30s
- DB triggers for display_id (conversations, campaigns) and UUID generation

### Docker
- Production: `ruby:3.4.4-alpine3.21` with Node 24, imagemagick, vips
- Dev container: PostgreSQL 16 + pgvector, Redis, Mailhog
- Exposed port: 3000

## Enterprise Edition Notes

Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code via module injection.

### Module injection mechanism
- `prepend_mod_with('Foo')` → looks for `Enterprise::Foo`, overrides methods (Ruby `prepend`)
- `include_mod_with('Foo')` → extends with enterprise concerns (Ruby `include`)
- `extend_mod_with('Foo')` → adds class-level methods
- Iterates through `ChatwootApp.extensions` (default: `['enterprise']`)
- Detection: `ChatwootApp.enterprise?` checks if `enterprise/` directory exists

### Enterprise-only features
- **SLA**: SlaPolicy, AppliedSla, SlaEvent — conversation lifecycle tracking with time thresholds
- **Custom Roles**: Per-account roles with granular permissions (conversation_manage, contact_manage, report_manage, knowledge_base_manage)
- **Captain/AI**: Assistants, Scenarios, CustomTools, Documents, Copilot — full LLM platform with RAG, custom HTTP tools, copilot chat
- **Voice**: Channel::Voice — Twilio voice calls with IVR, conferencing
- **Billing**: Stripe integration with plan limits, topups
- **SAML SSO**: Enterprise SSO via OmniAuth SAML
- **Audit Logs**: Full change logging on key models via Audited gem
- **Companies**: CRM company records with domain-based deduplication
- **Agent Capacity**: Workload management with per-inbox limits
- **Balanced Assignment**: Workload-balanced agent assignment (vs OSS round-robin)
- **Advanced Search**: OpenSearch/Elasticsearch integration via Searchkick

### Enterprise structure
```
enterprise/
├── app/models/      # 58 files: SLA, CustomRole, Captain::*, Company, Channel::Voice, etc.
├── app/controllers/ # 44 files: SLA, audit, Captain, billing, SAML, voice
├── app/services/    # 71+ files: Captain/LLM, SLA processing, billing, permissions
├── app/policies/    # 14 files: SLA, custom role, Captain, + overlay modules
├── app/jobs/        # 23+ files: Captain, SLA, billing, audio transcription
├── app/listeners/   # Captain listener, ActionCable overlay
├── app/builders/    # Message, Agent, ContactInbox overlays
├── lib/captain/     # Tools (HTTP, FAQ lookup, handoff, labels, notes, priority)
└── config/          # SAML initializer
```

### Practical checklist for changes
- Search for related files in both trees before editing: `rg -n "FooService|ModelName" app enterprise`
- If adding new endpoints/services/models, consider whether Enterprise needs an override or extension point
- Avoid hardcoding plan-specific behavior in OSS; prefer feature flags or extension points
- Keep request/response contracts stable across OSS and Enterprise
- When renaming/moving shared code, mirror the change in `enterprise/`
- Tests: Add Enterprise-specific specs under `spec/enterprise`
- Use `prepend_mod_with` to override methods; `include_mod_with` to extend
- Enterprise module injection: `prepend_mod_with('Foo')` looks for `Enterprise::Foo` in `enterprise/app/`

## MCP Integrations

### Monday.com
- **Package**: `@mondaydotcomorg/monday-api-mcp`
- **Config**: `.mcp.json` (na raiz do projeto, contém token — não commitar)
- **Ferramentas disponíveis**: criar items, atualizar colunas, atribuir owners, postar updates, resumir boards, consultar insights
- **Docs**: https://github.com/mondaycom/mcp
