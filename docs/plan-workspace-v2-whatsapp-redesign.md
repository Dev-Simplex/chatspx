# Handoff — ChatSPX Workspace v2 (Redesign WhatsApp-Fiel)

> **Para a próxima sessão do Claude Code:** este documento é autocontido. Leia ele inteiro antes de tocar em qualquer coisa. Você está continuando o trabalho do Walisson na Simplex Soluções no fork ChatSPX (Chatwoot). Não pergunte coisas que já foram decididas aqui. Execute.

---

## 1. Contexto Mínimo

- **Quem:** Walisson (dev Simplexia/ChatSPX). Fala pt-BR direto, sem rodeios. Não usa emojis. Quer execução completa, não MVP.
- **O que:** Redesign do dashboard de conversas do ChatSPX para estética e ergonomia de WhatsApp Web/Desktop, mantendo features Chatwoot OSS+Enterprise e adicionando IA como cidadã de primeira classe.
- **Onde:** VM `192.168.8.232` (homologação completa, `RAILS_ENV=production` é seguro aqui).
- **URL:** `https://hmlchat.simplexsolucoes.com.br`
- **Branch ativa:** `homologacao` (working tree, sem commit ainda)
- **Repo:** `Dev-Simplex/chatspx`
- **Design reference:** [`whatsapp.md`](../whatsapp.md) na raiz + mocks em `public/dmock/workspace-v2/` (variante Z aprovada)

---

## 2. Hard Rules (não negociáveis)

| # | Regra | Razão |
|---|---|---|
| 1 | **NÃO commitar nada** sem o Walisson dizer "TUDO TUDO pronto". Working tree only. | Regra fixa do dono |
| 2 | **i18n pt-BR é prioridade** (sobrescreve a regra global Chatwoot que diz "só `en`"). Mexer em `en.json` E `pt_BR.json` sempre. | Cliente é Brasil |
| 3 | **Tailwind only.** Sem CSS customizado, sem `<style scoped>`, sem inline. | Convenção do repo |
| 4 | **Não tocar a left sidebar (Zone A).** Phase 1 já está finalizada. | Já entregue |
| 5 | **Edição incremental.** Nada de reescrita global de componentes. | Risco regressão |
| 6 | **Verificar Enterprise overlay** antes de editar core: `rg -n "Symbol" app enterprise`. Se Enterprise sobrescreve, espelhar. | Chatwoot tem `enterprise/` |
| 7 | **Branding:** usar `replaceInstallationName` de `shared/composables/useBranding`. Nunca hardcodar "Chatwoot". | White-label |
| 8 | **Sem defensive programming desnecessário.** Happy path primeiro, código mínimo. | Filosofia Walisson |
| 9 | **Modelo IA — estratégia 2-tier (tudo OpenAI):** Default `gpt-4o-mini` para Ghost, Copilot lateral, detecção idioma, tool calling simples, Phase 5-6-8-9, 7.4-7.6. **`gpt-4o` (full)** para Phase 7.1 Agentes IA, 7.2 Tool calling avançado, 7.3 Multi-turn workflows — onde raciocínio multi-step é crítico. NÃO usar Anthropic/Claude. | Walisson aprovou |
| 10 | **Whisper:** sempre `language: 'pt'`. Áudios são pt-BR. | Decisão feita |
| 11 | **Quando bloqueado, dizer.** Se algo não dá, fala. Não inventa solução nem corta escopo unilateralmente (já levou pushback antes). | Lição aprendida |
| 12 | **Workflow logado para QA:** SEMPRE testar Playwright logado com `cw_d_session_info` cookie injection. | Garantia de qualidade |

---

## 3. Decisões Já Tomadas (não rediscutir)

| Tópico | Decisão |
|---|---|
| Limite OpenAI/mês | $50 inicial, monitorar via logs por endpoint |
| Chave OpenAI | **Cada conta tem a sua** (`account.settings.openai_api_key`), fallback `ENV['OPENAI_API_KEY']` |
| Modelo padrão | `gpt-4o-mini` (Ghost, Copilot lateral, detecção idioma, tool calling simples) |
| Modelo avançado | `gpt-4o` full (Phase 7.1 Agentes IA, 7.2 Tool calling complexo, 7.3 Multi-turn workflows) |
| Whisper language | `pt` forçado |
| Copilot histórico ao trocar conversa | Salvar (Phase 7.4 — persistir em `conversation.additional_attributes`) |
| Onboarding em contas existentes | **Aparece para todas**, sem auto-dismiss SQL |
| Replicar para produção interna/SaaS | **Não tocar.** Walisson avisa quando |
| Pin de conversa | Toggle por inbox: `inbox.additional_attributes['pin_mode']` ∈ `per_agent` (default) \| `per_inbox`. UI no Settings → Inboxes → [inbox] → Comportamento |
| Wallpaper | Aceita **URL externa** E **upload via ActiveStorage** (`account.chat_wallpaper_image`, max 5MB, image/jpeg/png/webp) |
| Escopo | **Phases 2/3/4 já feitas + ajustes §6 + Phases 5, 6, 8, 9 + Phase 7.4/7.5** = 22 features. Phase 7.1/7.2/7.3/7.6 (IA pesada) está em chat paralelo (`docs/plan-phase7-ai-agents.md`). |
| Coordenação Chat B | Esperar Chat B começar só DEPOIS de você terminar §6 (especialmente §6.2 chave OpenAI por conta + §6.5 modelo selector — Chat B depende). Walisson coordena. |

---

## 3.1 Estratégia de Modelos OpenAI (importante)

**Tudo OpenAI. Sem Anthropic, sem Claude.** Walisson decidiu manter um único provedor.

| Onde | Modelo | Por quê |
|---|---|---|
| Ghost suggestion (composer preview) | `gpt-4o-mini` | Curto, rápido, barato, qualidade ótima |
| Copilot lateral (chat conversacional simples) | `gpt-4o-mini` | Custo/benefício imbatível |
| Whisper transcrição áudio | `whisper-1` | Único modelo de áudio OpenAI |
| Detecção de idioma (Phase 7.5) | `gpt-4o-mini` | Tarefa trivial, classificação |
| Copilot histórico (Phase 7.4) | `gpt-4o-mini` | Mesma do default |
| Voice-to-Copilot (Phase 7.6) | `whisper-1` + `gpt-4o-mini` | Reusa pipeline |
| **Agentes IA (Phase 7.1)** | **`gpt-4o`** (full) | Raciocínio multi-step, tool calling robusto |
| **Tool calling complexo (Phase 7.2)** | **`gpt-4o`** | mini falha em function calling com 6+ tools |
| **Multi-turn workflows (Phase 7.3)** | **`gpt-4o`** | Manter contexto através de state machine |

**Como implementar:** modelos vêm de `account.settings.openai_model_default` e `account.settings.openai_model_advanced` (configuráveis via UI — ver §6.5). Services usam default ou advanced conforme o caso. Sem fallback hardcoded em tempo de run, mas constante de default em cada service para o caso de conta sem setting.

**Custo comparado** (1M tokens):
- `gpt-4o-mini`: $0.15 input / $0.60 output
- `gpt-4o`: $2.50 input / $10 output (16x mais caro)
- `whisper-1`: $0.006/minuto

**Mitigação de custo do `gpt-4o`** nas Phase 7.1-7.3:
- Limitar histórico de contexto (max 10 mensagens)
- Truncar transcrição de conversa a 4000 chars no prompt
- Cache agressivo de respostas idênticas (5min)
- Logar cada chamada com tokens consumidos para Walisson monitorar

---

## 4. Estado Atual (Phases 2/3/4 — DONE no working tree)

Não refaça. Já implementado e validado via Playwright logado:

### Phase 2 — Composer + IA
- 2.1 Composer dobrável (já existia, validado)
- 2.2 Ghost suggestion (`Copilot::GhostSuggestionService`, gpt-4o-mini, cache 5min)
- 2.3 Transcrição áudio (Whisper, `AudioTranscriptionService` + Job, persiste em `attachment.meta['transcribed_text']`)
- 2.4 Reply preview 3 linhas (já existia)

### Phase 3 — Layout + Context
- 3.1 Bubble tail SVG (já existia, `_wa-skin.scss`)
- 3.2 Card tipografia (`text-[14.2px] leading-[19px] font-medium`)
- 3.3 Chat wallpaper (URL — falta adicionar upload, ver §6.4)
- 3.4 Notes threaded (removida restrição `!isPrivate` em `shouldShowReplyToMessage`)
- 3.5 Priority pill com dropdown 5 opções
- 3.6 Dashboard KPI strip toggle

### Phase 4 — Power Features
- 4.1 Multi-view Kanban (já existia em Chatwoot OSS)
- 4.2 Pin de conversa per-user via UISettings (falta toggle por inbox, ver §6.3)
- 4.3 Copilot lateral drawer 380px (gpt-4o-mini, conversation-aware, quick prompts)
- 4.4 Onboarding checklist 4 steps fixed bottom-right

### Arquivos já criados/modificados (Phases 2/3/4)
**Novos backend (6):** `app/services/copilot/ghost_suggestion_service.rb`, `app/services/copilot/chat_service.rb`, `app/services/audio_transcription_service.rb`, `app/jobs/audio_transcription_job.rb`, `app/controllers/api/v1/accounts/conversations/ghost_suggestions_controller.rb`, `app/controllers/api/v1/accounts/conversations/copilot_chats_controller.rb`

**Novos frontend (5):** `app/javascript/dashboard/components/widgets/conversation/CopilotPanel.vue`, `app/javascript/dashboard/components-next/Onboarding/OnboardingChecklist.vue`, `app/javascript/dashboard/composables/usePinnedConversations.js`, `app/javascript/dashboard/routes/dashboard/settings/account/components/ChatWallpaper.vue`, `app/javascript/dashboard/routes/dashboard/settings/account/components/DashboardKpiStrip.vue`

**Modificados backend:** `app/models/account.rb` (store_accessors), `app/models/attachment.rb` (after_create_commit), `app/controllers/api/v1/accounts_controller.rb` (permitted_settings), `config/routes.rb` (`ghost_suggestion`, `copilot_chat`)

**Modificados frontend:** `app/javascript/dashboard/App.vue`, `ConversationBox.vue`, `ConversationHeader.vue`, `ReplyBox.vue` (1879 linhas), `ConversationCard.vue`, `api/conversations.js`

**i18n (6):** `en` + `pt_BR` para `conversation.json`, `general.json`, `generalSettings.json`

---

## 5. Stack & Convenções do Repo

| Camada | Stack |
|---|---|
| Backend | Rails 7.1.5.2, Ruby 3.4.4 (RVM, NÃO rbenv — `rbenv` não existe nesta máquina) |
| Frontend | Vue 3 Composition API `<script setup>`, Vite via `vite_ruby` |
| Styling | Tailwind tokens: `n-slate-*`, `n-solid-*`, `n-alpha-*`, `n-weak`, `n-strong`, `n-brand`, `n-chat-bg` |
| Icons | `lucide-vue-next` via `Icon.vue` (renderiza SVG inline com `data-v-3db653ac`, NÃO classe `.i-lucide-*`) |
| Auth | Devise Token Auth (cookie `cw_d_session_info`) |
| Store | Vuex + composables (`useAccount`, `useUISettings`) |
| Settings persist | `account.settings` jsonb via `store_accessor` (sem migrations novas) |
| LLM | `ruby-openai 7.3.1` (gem `OpenAI::Client`) |
| Cache | `Rails.cache` |
| Jobs | Sidekiq, queue `low` |

### Rotinas operacionais
```bash
# Build com cache bust (vite cache não invalida sozinho)
rm -f tmp/cache/vite/last-build-production.json && touch <arquivos-modificados>
RAILS_ENV=production bundle exec rails assets:precompile

# Restart
sudo systemctl restart chatwoot.target
# (sudo NOPASSWD configurado APENAS para restart chatwoot.target — qualquer outro sudo pede senha)

# Smoke HTTP
curl -k -s -o /dev/null -w "%{http_code}\n" https://hmlchat.simplexsolucoes.com.br/

# Rails runner (sem rbenv, RVM auto-loads)
RAILS_ENV=production bundle exec rails runner "..."
```

### Login para Playwright logado
```ruby
RAILS_ENV=production bundle exec rails runner "
u = User.find_by(email: 'sup@simplexsolucoes.com.br')
client_id = SecureRandom.urlsafe_base64(nil, false)
token = SecureRandom.urlsafe_base64(nil, false)
expiry = (Time.now + 1.day).to_i
u.tokens[client_id] = { token: BCrypt::Password.create(token), expiry: expiry }
u.save!
puts JSON.dump({uid: u.uid, client: client_id, token: token, expiry: expiry, user_id: u.id})
"
```
Cookie `cw_d_session_info` injetado via Playwright `addCookies` com encodeURIComponent JSON.

### Conta com dados ricos para QA
- `account_id=5` — Realizare Imobiliária (1908 conversas) — conversa 1884 funciona como bookmark estável

---

## 6. Trabalho Pendente (executar tudo)

### 6.1 Logs de telemetria OpenAI (decisão #1 — limite $50/mês)
- Adicionar log estruturado em `Copilot::ChatService`, `Copilot::GhostSuggestionService`, `AudioTranscriptionService`:
  ```
  [OpenAI::Telemetry] service=ghost account_id=5 tokens_in=N tokens_out=M cost_usd=X
  ```
- Calcular custo a partir dos tokens da response da OpenAI (`response.dig('usage', ...)`)
- Custos atuais: gpt-4o-mini = $0.15/1M input + $0.60/1M output. Whisper = $0.006/min.
- Não bloqueante (limite hard só na OpenAI dashboard) — só observability

### 6.2 Chave OpenAI por conta (decisão #2)
- Adicionar `store_accessor :settings, :openai_api_key` em `app/models/account.rb`
- Permitir em `app/controllers/api/v1/accounts_controller.rb` `permitted_settings`
- Encrypted at rest: usar `attr_encrypted` ou `Rails.application.credentials` — mas o jsonb de settings já é o padrão. Aceitável guardar como string normal por enquanto, marcar como TODO de hardening
- Refatorar os 3 services para usar `account.settings['openai_api_key'].presence || ENV['OPENAI_API_KEY']`
- Criar UI: nova tela `Settings → Integrações → OpenAI`
  - Input password masked
  - Botão "Testar chave" → faz 1 chamada barata (`models.list`) e mostra ✓ ou ✗
  - Salvar
- i18n: `INTEGRATIONS.OPENAI.{TITLE,LABEL,PLACEHOLDER,TEST,SAVE,SUCCESS,INVALID}`

### 6.3 Pin com toggle por inbox (decisão #9)
- Campo: `inbox.additional_attributes['pin_mode']` (default `'per_agent'`)
- Permitir em `Inbox` controller params
- UI nova aba: `Settings → Inboxes → [inbox] → Comportamento` (ou adicionar à aba existente "Configuration")
  - Radio group: "Por agente (cada agente fixa as suas)" | "Por caixa de entrada (todos compartilham)"
- Refatorar `usePinnedConversations.js`:
  - Quando `pin_mode === 'per_agent'`: lê/escreve em `user_uisettings.pinned_conversation_ids` (atual)
  - Quando `pin_mode === 'per_inbox'`: lê/escreve em `inbox.additional_attributes['pinned_conversation_ids']`
- Criar endpoint `PATCH /api/v1/inboxes/:id` se não permitir editar `additional_attributes` ainda (verificar)

### 6.4 Wallpaper com upload (decisão #10)
- `app/models/account.rb`: `has_one_attached :chat_wallpaper_image`
- Criar endpoint `POST /api/v1/accounts/:id/chat_wallpaper` que recebe multipart, valida (max 5MB, content_type ∈ image/jpeg|png|webp), attacha
- Resposta: `{ url: rails_blob_url(account.chat_wallpaper_image) }`
- Atualizar `ChatWallpaper.vue`:
  - Tabs/toggle: "URL externa" | "Upload"
  - Upload: input file + preview + botão upload → ao concluir, persiste URL em `account.settings.chat_wallpaper_url`
  - Remover image: botão "Remover" → `account.chat_wallpaper_image.purge`
- ActiveStorage já está configurado no projeto (verifica `config/storage.yml`)

### 6.5 UI para escolher modelo OpenAI por conta (Walisson pediu)
- Adicionar 2 store_accessors em `app/models/account.rb`:
  ```ruby
  store_accessor :settings, :openai_model_default     # default 'gpt-4o-mini'
  store_accessor :settings, :openai_model_advanced    # default 'gpt-4o'
  ```
- Permitir em `permitted_settings`
- UI: na MESMA tela de §6.2 (`Settings → Integrações → OpenAI`), abaixo da chave, adicionar 2 selects:

  **Modelo padrão (uso geral):**
  - `gpt-4o-mini` (recomendado — barato e rápido) ← default
  - `gpt-4o` (mais caro, qualidade superior)
  - `gpt-4-turbo` (legado)

  **Modelo avançado (Agentes IA, workflows complexos):**
  - `gpt-4o` (recomendado) ← default
  - `gpt-4o-mini` (mais barato, mas pode falhar em tool calling complexo)
  - `o1-mini` (reasoning, lento)
  - `o1-preview` (reasoning forte, caro)

- Cada select tem:
  - Help text explicando trade-off
  - Tooltip com custo por 1M tokens
  - Botão "Restaurar padrão"

- Refatorar services para usar a setting da conta:
  ```ruby
  # Copilot::ChatService, Copilot::GhostSuggestionService
  MODEL = -> (account) { account.settings['openai_model_default'].presence || 'gpt-4o-mini' }

  # Phase 7.1, 7.2, 7.3 services
  MODEL_ADVANCED = -> (account) { account.settings['openai_model_advanced'].presence || 'gpt-4o' }
  ```

- i18n: `INTEGRATIONS.OPENAI.{MODEL_DEFAULT,MODEL_ADVANCED,MODEL_HELP_DEFAULT,MODEL_HELP_ADVANCED,MODEL_RESTORE}`

- **Tela final fica assim:**
  ```
  ┌─────────────────────────────────────────────────┐
  │ Integrações → OpenAI                            │
  ├─────────────────────────────────────────────────┤
  │ Chave da API                                    │
  │ [sk-proj-•••••••••••••]  [Testar] [Salvar]     │
  │                                                  │
  │ Modelo padrão (uso geral)                       │
  │ [▼ gpt-4o-mini  ($0.15/$0.60 por 1M)]          │
  │ Usado em: composer ghost, copilot lateral,      │
  │ detecção de idioma, transcrição preview         │
  │                                                  │
  │ Modelo avançado (raciocínio complexo)           │
  │ [▼ gpt-4o  ($2.50/$10 por 1M)]                 │
  │ Usado em: Agentes IA, tool calling, workflows   │
  │ multi-turn                                      │
  │                                                  │
  │ [Restaurar padrões]  [Salvar]                  │
  └─────────────────────────────────────────────────┘
  ```

---

## 7. Roadmap Phase 5-9 (escopo reduzido — Phase 7 IA pesada está em outro chat)

> **Divisão entre os 2 chats:**
> - **Você (Chat A — este documento):** ajustes §6, Phases 5, 6, 8, 9 + Phase 7.4/7.5 leves = **22 features**
> - **Chat B (`docs/plan-phase7-ai-agents.md`):** Phase 7.1, 7.2, 7.3, 7.6 = **4 features de IA pesada**
>
> Você implementa 22 features. Ordem sugerida (dependências no topo):

### Phase 5 — Mensagens & Mídia (7 features)
1. **5.1 Reactions** (👍 ❤️ 😂 😮 😢 🙏): backend `message.additional_attributes['reactions'] = { user_id: emoji }`. Endpoint `POST /messages/:id/reactions`. Frontend: picker no hover do balão (8 emojis padrão), exibir contadores abaixo. Suporte multi-reaction por user.
2. **5.2 Forward**: Modal "Encaminhar para..." com search de conversa, ação criar nova mensagem na conversa destino com prefixo `[Encaminhada]`. Backend usa `Messages::MessageBuilder`.
3. **5.3 Star messages**: `message.additional_attributes['starred'] = true`. Filtro lateral "Mensagens favoritas" na sidebar de conversa. Botão star no hover.
4. **5.4 Voice notes inline**: MediaRecorder API → blob webm/opus → upload como Attachment file_type:audio → trigger AudioTranscriptionJob automaticamente. UI: botão mic no composer, gravando mostra waveform + cancel/send.
5. **5.5 Document preview embed**: PDF.js no chip de attachment file_type:file. Preview inline no chat (primeira página) + botão "Abrir completo".
6. **5.6 Image multi-select + bulk download**: Modo seleção na galeria de mensagens, checkbox em imagens, action "Baixar tudo" (zip via JSZip OU ActionController download).
7. **5.7 Media gallery por conversa**: Aba lateral nova "Mídia" no painel direito com timeline visual de imagens/vídeos/docs/áudios da conversa. Reaproveitar componente Gallery existente (`docs/plan-gallery-polish-v3.md` referência).

### Phase 6 — Status & Presença (4 features)
1. **6.1 Typing indicator**: ActionCable já tem `typing_on`/`typing_off` parcial — completar. Mostrar "Fulano está digitando..." abaixo do contact name no header. Throttle 3s.
2. **6.2 Online presence**: Presence channel via Redis (Devise+ActionCable). Badge verde no avatar do contato quando online (last_seen_at < 30s). Para contato externo (cliente WhatsApp), usar `contact.last_activity_at`.
3. **6.3 Last seen**: Já existe `contact.last_seen_at`. Exibir "Visto por último há Xh" abaixo do contact name no header (i18n com `dayjs.fromNow`).
4. **6.4 Read receipts**: Mensagens outgoing com double-check. `message.read_at` já existe no schema (verificar). Update via webhook WAHA / API channel. UI: 1 check (sent), 2 checks gray (delivered), 2 checks blue (read).

### Phase 7 — Copilot Power-Ups (apenas 7.4 e 7.5 aqui — resto é Chat B)

> **IMPORTANTE:** Phase 7.1 (Agentes IA), 7.2 (Tool calling), 7.3 (Workflows) e 7.6 (Voice-to-Copilot) **NÃO são seu escopo**. Estão em outro chat paralelo (`docs/plan-phase7-ai-agents.md` — Chat B). NÃO toque nessas features.
>
> Coordenação com Chat B: você pode mexer em `app/services/copilot/chat_service.rb` (já existe) para adicionar histórico (7.4) e multi-idioma (7.5). Chat B vai ESTENDER esse mesmo service depois para tool calling — então mantenha sua refatoração simples e aditiva, sem reescrever a estrutura.

1. **7.4 Copilot histórico salvo** — `gpt-4o-mini`. Persistir `messages` do CopilotPanel em `conversation.additional_attributes['copilot_history']` (limite 50 mensagens, FIFO). Carregar ao abrir drawer. Botão "Limpar histórico".
2. **7.5 Copilot multi-idioma automático** — `gpt-4o-mini`. Detectar idioma da conversa (1 chamada classificação OpenAI) → ajustar `system_prompt` em `Copilot::ChatService` para responder no idioma detectado. Cachear detecção por conversa por 1h.

### Phase 8 — Workspace Polish (5 features)
1. **8.1 Theme switch fluido**: View transitions API (`document.startViewTransition`). Já existe toggle dark/light, melhorar a transição.
2. **8.2 Density toggle**: User setting `ui_settings.conversation_density` ∈ `compact|comfortable|spacious`. Aplicar via classes Tailwind no `ConversationCard`, `MessagesView`. Toggle no menu do user (avatar bottom-left).
3. **8.3 Sidebar customizável (drag to reorder)**: Library `vuedraggable` (já no `package.json`). Reordenar abas Inbox/Teams/Labels/Custom Views. Persistir em `user_ui_settings.sidebar_order`.
4. **8.4 Quick reply templates per inbox**: Canned responses já existem. Melhorar UI: shortcut `/` no composer abre dropdown filtrável. Aceitar variáveis `{{contact.name}}`, `{{agent.name}}`, `{{conversation.id}}` interpoladas.
5. **8.5 Keyboard shortcuts globais**: Library `mousetrap-vue` (verificar — pode usar nativo). Atalhos: `j/k` navegar conversas, `r` reply, `n` nota privada, `Esc` fechar, `?` modal de ajuda. Configurável em Settings → Profile.

### Phase 9 — Mobile-First / PWA (4 features)
1. **9.1 PWA install prompt**: Service worker já existe (`public/service-worker.js`). Capturar evento `beforeinstallprompt`, exibir banner customizado "Instalar ChatSPX" com botão. Esconder após instalado ou dispensa.
2. **9.2 Push notifications**: Web Push API. VAPID keys em ENV. Backend `app/services/web_push_service.rb` já existe (verificar). Frontend: solicitar permission no primeiro login pós-1min, salvar subscription em `user.push_subscription`.
3. **9.3 Mobile <640px refinado**: Auditar todos os breakpoints `sm:`, ajustar paddings, tipografia, layouts em screens estreitas (< 640px). Testar com Playwright viewport `{ width: 375, height: 812 }`.
4. **9.4 Swipe gestures**: Library `hammer.js` ou `vue3-touch-events`. Em ConversationCard mobile: swipe-left = arquivar (resolved), swipe-right = marcar como não lida. Animar com `translateX`.

---

## 8. Plano de Execução Sugerido (mas você decide a ordem)

**Princípio:** Cada item = pequeno ciclo `code → build → restart → smoke → próximo`. Tudo no working tree, sem commit.

1. **Setup ambiente** — confirmar HTTP 200, Sidekiq up, OpenAI key setada
2. **Ajustes 6.1-6.4** (~1h cada) — fechar a base que já está rodando
3. **Phase 5** sequencial (5.1 → 5.7), cada uma é 1-3h
4. **Phase 6** (6.3 last seen é o mais simples, fazer primeiro; 6.1 e 6.2 dependem de Redis pub/sub bem testado)
5. **Phase 7** (7.4 e 7.5 primeiro como warm-up; depois 7.2 tool calling; depois 7.6 voice; deixar 7.1 e 7.3 por último — são complexos)
6. **Phase 8** (rápidas e isoladas, podem entrar em paralelo)
7. **Phase 9** (testar muito em mobile real / Chrome DevTools device mode)

**Após cada feature:**
- Build + restart
- Playwright smoke logado da feature
- Reportar pro Walisson com screenshot

**Não esquecer:**
- i18n `en` + `pt_BR` em CADA feature
- Verificar Enterprise overlay (`rg "X" app enterprise`)
- Tailwind only (zero CSS custom)
- `Icon.vue` para ícones, NÃO `<svg>` direto
- Memorizar lições novas no vault `vault/01-Permanentes/Licao - ...md` quando descobrir pitfall

---

## 9. Pitfalls Conhecidos (já paguei o pedágio)

1. **`.env` com chaves vazias** (`OPENAI_API_KEY=` aparenta setada mas length=0): `wc -c <<< "$OPENAI_API_KEY"` para confirmar.
2. **Login API com senha quebra**: gerar `tokens` direto no model + cookie inject (ver §5).
3. **Account 1 não tem conversas**: usar account 5 (Realizare).
4. **Selector `.i-lucide-X` em Playwright NÃO funciona**: `Icon.vue` renderiza SVG inline. Usar `.wa-header-icon-btn` + ordem de DOM, ou `data-v-3db653ac` attr.
5. **Vite cache não invalida**: `rm tmp/cache/vite/last-build-production.json && touch <arquivos>` antes de `assets:precompile`.
6. **Rubocop `Rails/SkipsModelValidations`**: inline disable comment `# rubocop:disable Rails/SkipsModelValidations` quando `update_column` é apropriado em jsonb meta.
7. **`update_account` aceita só keys whitelisted**: TODA nova setting precisa entrar em `permitted_settings` ou some silenciosamente.
8. **`rbenv` não existe nesta VM**: `bundle exec` direto (RVM auto-loads via /etc/profile.d).
9. **sudo é NOPASSWD apenas para `systemctl restart chatwoot.target`**: qualquer outro sudo pede senha → não tente.
10. **NÃO cortar escopo MVP unilateralmente**: Walisson quer execução completa. Se algo não der, fala explicitamente — não defere silenciosamente.

---

## 10. Comunicação com o Walisson

- pt-BR direto, frases curtas
- Sem emojis, sem trailing summaries longos ("✅ Done!" — não)
- Quando bloqueado, dizer "estou bloqueado em X porque Y, preciso de Z"
- Quando completar feature, reportar:
  - O que foi feito (1 linha)
  - HTTP status / smoke result
  - Screenshot (path /tmp/...)
  - "Próxima feature: X" se for continuar autonomamente
- "faz o que achar melhor" / "não me pergunte" = executar end-to-end sem pausar
- Vault para memória persistente: `vault/01-Permanentes/`, `vault/02-MOCs/`

---

## 11. Comandos Úteis Quick Reference

```bash
# Estado git
git status -s
git diff --stat

# Build + restart full
rm -f tmp/cache/vite/last-build-production.json && \
  touch <arquivos> && \
  RAILS_ENV=production bundle exec rails assets:precompile && \
  sudo systemctl restart chatwoot.target

# Smoke HTTP
for path in / /app /api/v1/accounts/5/conversations; do
  echo -n "$path: "
  curl -k -s -o /dev/null -w "%{http_code}\n" "https://hmlchat.simplexsolucoes.com.br$path"
done

# Lint
pnpm eslint app/javascript --fix
bundle exec rubocop -a

# Playwright (logado)
CW_TOKEN=... CW_CLIENT=... CW_UID=... CW_EXPIRY=... CW_USER_ID=1 CW_ACCOUNT_ID=5 \
  node scripts/playwright_<feature>_logged.mjs

# Rails console produção
RAILS_ENV=production bundle exec rails c

# Ver logs
sudo journalctl -u chatwoot-web.1 -f
sudo journalctl -u chatwoot-worker.1 -f
```

---

## 12. Onde Estão as Coisas

| Tipo | Path |
|---|---|
| Models | `app/models/` |
| Controllers API | `app/controllers/api/v1/` |
| Services | `app/services/` |
| Jobs | `app/jobs/` |
| Vue componentes legacy | `app/javascript/dashboard/components/` |
| Vue componentes novos | `app/javascript/dashboard/components-next/` (preferir aqui para coisas novas) |
| Composables | `app/javascript/dashboard/composables/` |
| Vuex store | `app/javascript/dashboard/store/` |
| API client | `app/javascript/dashboard/api/` |
| Rotas frontend | `app/javascript/dashboard/routes/` |
| i18n | `app/javascript/dashboard/i18n/locale/{en,pt_BR}/*.json` |
| Tailwind config | `tailwind.config.js` |
| Enterprise overlay | `enterprise/` (espelha estrutura de `app/`) |
| Playwright scripts | `scripts/playwright_*.mjs` |
| Mocks design | `public/dmock/workspace-v2/` |
| Vault (memória) | `vault/` |
| Reference design | `whatsapp.md` (raiz) |

---

## 13. Vault — Notas Relevantes

Antes de começar, leia:
- `vault/CLAUDE.md` (entry point)
- `vault/01-Permanentes/Chat SPX.md` (ambientes, credenciais, deploy, .env)
- `vault/02-MOCs/ROUTER - Engineering.md` (padrões e workflows)
- `vault/02-MOCs/MOC - Credenciais e Acessos.md`
- `vault/02-MOCs/Projeto - Agentes IA.md` (Phase 7.1 — Chat B executa, você ignora)
- **`docs/plan-phase7-ai-agents.md`** — plano paralelo do Chat B. Leia para entender coordenação, NÃO execute features dele.

**Após completar trabalho não trivial, registrar no vault:**
- Erro inesperado → `Licao - ...md`
- Padrão reutilizável → `Padrao ...md`
- Boa prática → `BP - ...md`
- Procedimento → `RB - ...md`

---

## 14. Critérios de "Pronto"

Cada feature está pronta quando:
- [ ] Backend implementado + testado manual via Rails console
- [ ] Frontend implementado, build passa sem erro
- [ ] i18n `en` + `pt_BR` adicionado
- [ ] ESLint sem erros novos (`pnpm eslint`)
- [ ] Rubocop sem offenses novos (`bundle exec rubocop`)
- [ ] Enterprise overlay verificado (sem conflito)
- [ ] HTTP smoke 200
- [ ] Playwright logado com screenshot mostrando feature funcionando
- [ ] Walisson notificado com 1-2 frases + screenshot path

**Pronto-pronto (commit-ready):**
- [ ] TODAS as 26 features Phase 5-9 entregues
- [ ] Os 4 ajustes (§6.1-6.4) aplicados
- [ ] Smoke consolidado verde
- [ ] Walisson aprova explicitamente

Só então: branch `feature/workspace-v2-completo`, commits Conventional, PR contra `homologacao`. **Antes disso, NADA de commit.**

---

## 15. Em Caso de Dúvida

1. **Decisão técnica não-óbvia** → consultar vault primeiro, se não tiver resposta, perguntar Walisson
2. **Bloqueio externo** (chave API faltando, lib quebrada) → reportar e aguardar
3. **Conflito Enterprise** → ler `https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38` e resolver com `prepend_mod_with`/`include_mod_with`
4. **Não sei como mexer em X** → leia código existente similar primeiro (90% das respostas estão no repo)

---

*Documento de handoff gerado em 2026-04-28 por Orion (aiox-master) — sessão anterior atingiu limite de contexto. Próxima sessão: começar pelo §6 e seguir até §7.9.4 entregar tudo.*
