# Handoff — ChatSPX Phase 7 — Agentes IA & Copilot Power-Ups

> **Para a próxima sessão do Claude Code (Chat B — IA pesada):** este documento é autocontido. Você está executando a Phase 7 do redesign workspace-v2 do ChatSPX em paralelo com Chat A (que faz design + Phases 5/6/8/9 + ajustes §6 + Phase 7.4/7.5 leves).
>
> **Não toque em nada que não esteja aqui.** Se uma tarefa parecer ambígua, leia também `docs/plan-workspace-v2-whatsapp-redesign.md` para o contexto geral, mas seu escopo é APENAS Phase 7.1, 7.2, 7.3, 7.6.

---

## 1. Contexto Mínimo

- **Quem:** Walisson (dev Simplexia/ChatSPX). Fala pt-BR direto, sem rodeios. Não usa emojis.
- **O que:** Implementar **Agentes IA** (substituto do n8n), **tool calling avançado**, **multi-turn workflows** e **voice-to-Copilot**. Tudo OpenAI, modelo `gpt-4o`.
- **Onde:** VM `192.168.8.232` (homologação completa, `RAILS_ENV=production` é seguro)
- **URL:** `https://hmlchat.simplexsolucoes.com.br`
- **Branch ativa:** `homologacao` (working tree, sem commit ainda)
- **Repo:** `Dev-Simplex/chatspx`

---

## 2. Hard Rules (não negociáveis)

| # | Regra |
|---|---|
| 1 | **NÃO commitar nada** sem o Walisson dizer "TUDO TUDO pronto" |
| 2 | **i18n pt-BR é prioridade** — mexer em `en.json` E `pt_BR.json` sempre |
| 3 | **Tailwind only** — sem CSS customizado, sem `<style scoped>`, sem inline |
| 4 | **Verificar Enterprise overlay** antes de editar core: `rg -n "Symbol" app enterprise` |
| 5 | **Branding:** usar `replaceInstallationName` de `shared/composables/useBranding` |
| 6 | **Modelo IA:** `gpt-4o` (full) — NÃO mini. Mini falha em tool calling com 6+ tools e em raciocínio multi-step |
| 7 | **Whisper:** sempre `language: 'pt'` para 7.6 (voice-to-Copilot) |
| 8 | **Quando bloqueado, dizer.** Não invente, não corte escopo |
| 9 | **Working tree only** — Chat A está mexendo em paralelo, evite conflitos (ver §4) |
| 10 | **Validar via Playwright logado** depois de cada feature |

---

## 3. Coordenação com Chat A (paralelo)

Chat A está fazendo: ajustes §6 (chave OpenAI por conta, modelo selector, pin toggle, wallpaper upload, telemetria) + Phases 5/6/8/9 + Phase 7.4/7.5.

### Arquivos compartilhados — risco de merge conflict

| Arquivo | Chat A mexe | Você (Chat B) mexe |
|---|---|---|
| `app/models/inbox.rb` | `additional_attributes['pin_mode']` (§6.3) | `additional_attributes['ai_agent_config']` (Phase 7.1) |
| `app/models/account.rb` | `store_accessor :openai_api_key, :openai_model_*` | Apenas LER essas settings |
| `app/javascript/dashboard/components/widgets/conversation/CopilotPanel.vue` | Não vai mexer (você adiciona) | Estender com tool_call buttons + workflow steps |
| `app/javascript/dashboard/api/conversations.js` | Adiciona métodos novos | Adiciona `copilotAgentRun`, `copilotToolCall`, `copilotWorkflowStep` |
| `config/routes.rb` | Adiciona rotas novas | Adiciona suas rotas (ver §6) |
| i18n `conversation.json` | Adiciona chaves novas | Adiciona suas chaves sob namespace `COPILOT.AGENTS.*`, `COPILOT.TOOLS.*`, `COPILOT.WORKFLOWS.*` |

### Regra de ouro de paralelismo
1. **Espere Chat A terminar §6 inteiro antes de começar Phase 7.1.** §6.3 mexe em `Inbox` model. Phase 7.1 também mexe. Coordena via Walisson.
2. **Use chaves diferentes em `additional_attributes`** — nada de overlap.
3. **Em `api/conversations.js` e `routes.rb`**: você só ADICIONA linhas no final. Nunca edita o que está lá.
4. **Em `CopilotPanel.vue`**: você ESTENDE (adiciona slots, modos de exibição). Não reescreve a base.
5. **Sem rebase agressivo, sem reset.** Working tree puro. Walisson coordena merge.

---

## 4. Estado Atual Relevante (já existe)

Você está construindo EM CIMA do que já existe:

### Backend já existente
- **`app/services/copilot/chat_service.rb`** — Copilot lateral (gpt-4o-mini, conversa simples). NÃO substituir, ESTENDER.
- **`app/services/copilot/ghost_suggestion_service.rb`** — Composer ghost. Não tocar.
- **`app/services/audio_transcription_service.rb`** — Whisper transcrição de áudio incoming. Reusar para 7.6.
- **`app/controllers/api/v1/accounts/conversations/copilot_chats_controller.rb`** — Endpoint atual. Adicionar siblings.
- **`config/routes.rb`** — `resource :copilot_chat, only: [:create]` dentro de `scope module: :conversations`.

### Frontend já existente
- **`CopilotPanel.vue`** (380px drawer direita) — quick prompts, histórico mensagens user/assistant, textarea com Enter envia. Você vai estender isso.

### Settings da conta (Chat A vai criar — você LÊ)
```ruby
account.settings['openai_api_key']        # chave da conta
account.settings['openai_model_default']  # 'gpt-4o-mini'
account.settings['openai_model_advanced'] # 'gpt-4o' — VOCÊ USA ESTE
```

Helper para todos seus services:
```ruby
def api_key
  @api_key ||= account.settings['openai_api_key'].presence || ENV['OPENAI_API_KEY']
end

def model
  account.settings['openai_model_advanced'].presence || 'gpt-4o'
end
```

---

## 5. Stack & Convenções

| Camada | Stack |
|---|---|
| Backend | Rails 7.1.5.2, Ruby 3.4.4 (RVM, NÃO rbenv) |
| Frontend | Vue 3 Composition API `<script setup>`, Vite, Tailwind |
| LLM | `ruby-openai 7.3.1` |
| State machine | adicionar gem `aasm` no Gemfile (Phase 7.3) |
| Auth | Devise Token Auth (cookie `cw_d_session_info`) |
| Settings persist | `account.settings` jsonb via `store_accessor` |
| Cache | `Rails.cache` |
| Jobs | Sidekiq, queue `low` |

### Build + restart
```bash
rm -f tmp/cache/vite/last-build-production.json && \
  touch <arquivos-modificados> && \
  RAILS_ENV=production bundle exec rails assets:precompile && \
  sudo systemctl restart chatwoot.target
```

### Login Playwright (smoke logado)
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

Conta de teste: `account_id=5` (Realizare, 1908 conversas). Conversa estável: `1884`.

---

## 6. Phase 7.1 — Agentes IA (substituto do n8n)

**Objetivo:** Cada inbox pode ter um Agente IA configurado que responde clientes automaticamente, com personalidade, base de conhecimento e ferramentas próprias. Substitui workflows n8n simples.

### Modelo de dados
```ruby
# app/models/inbox.rb (campos em additional_attributes — sem migration)
inbox.additional_attributes['ai_agent_config'] = {
  enabled: false,                          # toggle on/off
  name: 'Agente Realizare',                # nome do agente
  persona: 'Atendente de imobiliária...',  # system prompt curto
  knowledge_base: '...',                    # texto livre, max 8000 chars
  tools_allowed: ['search_listings'],       # tools que pode usar
  fallback_action: 'assign_to_human',       # quando desistir
  trigger_on_first_message: true,           # autoresponde primeira msg
  trigger_after_inactivity_minutes: nil,    # ou só após N min sem agente
  language: 'pt-BR',
  max_turns: 10,                            # antes de escalar pra humano
}
```

### Arquivos a criar

#### Backend
1. **`app/services/copilot/agent_runner_service.rb`** — orquestra a chamada do agente
   - `initialize(conversation:, message:)`
   - `run` retorna `{ reply:, tool_calls: [], should_escalate: false }`
   - Usa `gpt-4o` com `tools` populadas conforme `tools_allowed`
   - System prompt monta: persona + knowledge_base + instruções gerais + idioma
   - Limite: `max_turns` no contexto

2. **`app/services/copilot/agent_tools/`** (diretório com 1 arquivo por tool)
   - `search_listings.rb` — exemplo: busca em base de imóveis (mock para Realizare)
   - `check_availability.rb`
   - `create_lead.rb`
   - `transfer_to_human.rb` — força fallback
   - **Padrão:** cada tool tem `self.schema` (JSON schema OpenAI) e `self.execute(args, conversation:)`

3. **`app/services/copilot/agent_dispatcher.rb`** — decide quando rodar o agente
   - Hook em `Conversations::MessageBuilder` (after_create_commit)
   - Se `inbox.additional_attributes['ai_agent_config']['enabled']` && (primeira mensagem || inatividade)
   - Enfileira `RunAgentJob`

4. **`app/jobs/run_agent_job.rb`** — Sidekiq job
   - Chama `AgentRunnerService`, persiste resposta como mensagem outgoing
   - Logger detalhado (telemetria de tokens conforme §6.1 do plano principal)

5. **`app/controllers/api/v1/accounts/inboxes/ai_agent_controller.rb`**
   - `GET /api/v1/accounts/:account_id/inboxes/:inbox_id/ai_agent` — config atual
   - `PATCH ...` — atualiza config
   - `POST .../test` — testa o agente com 1 mensagem mock, retorna response

6. **`config/routes.rb`** — adicionar dentro do scope da inbox:
   ```ruby
   resource :ai_agent, only: [:show, :update] do
     post :test, on: :collection
   end
   ```

#### Frontend
1. **`app/javascript/dashboard/routes/dashboard/settings/inbox/AiAgentSettings.vue`** — tela completa de config
   - Tab "Agente IA" dentro do Settings → Inbox → [inbox]
   - Toggle Enable
   - Inputs: nome, persona (textarea), knowledge_base (textarea), idioma (select)
   - Multi-select de tools
   - Configuração de trigger (radio: primeira_msg / após_inatividade)
   - Slider max_turns
   - Botão "Testar agente" — abre modal com chat de teste

2. **`app/javascript/dashboard/components-next/AiAgent/AgentTestChat.vue`** — modal de teste
   - Mini chat usando endpoint `POST .../ai_agent/test`
   - Mostra também tool_calls que o agente tentou usar

3. **`app/javascript/dashboard/api/inboxes.js`** — adicionar:
   - `getAiAgentConfig(inboxId)`
   - `updateAiAgentConfig(inboxId, config)`
   - `testAiAgent(inboxId, message)`

#### i18n
- `INBOX.AI_AGENT.{TITLE,ENABLE,NAME,PERSONA,KNOWLEDGE_BASE,TOOLS,TRIGGER,MAX_TURNS,TEST,SAVE,...}`

### Validação
- [ ] Habilitar agente em inbox de teste
- [ ] Configurar persona simples ("Você é um atendente de imobiliária")
- [ ] Mandar mensagem incoming via WAHA simulator → agente responde
- [ ] Logs mostram tokens consumidos
- [ ] Modal de teste funciona

---

## 7. Phase 7.2 — Tool Calling Avançado (Copilot lateral)

**Objetivo:** Habilitar `tools` na chamada do Copilot lateral (drawer) para que o assistente possa executar ações reais via botões. 6 ferramentas:
1. `mark_resolved` — fecha conversa
2. `assign_to_agent(agent_id)` — atribui
3. `add_label(label_name)` — adiciona etiqueta
4. `set_priority(level)` — altera prioridade
5. `send_canned_response(short_code)` — envia resposta padrão
6. `create_task(title, description)` — cria task interna (additional_attributes)

### Arquivos
1. **Refatorar `app/services/copilot/chat_service.rb`** para aceitar `tools` opcionais e modelo configurável
   - Adicionar param `enable_tools: true` no construtor
   - Quando true, usar `model: account.settings['openai_model_advanced'] || 'gpt-4o'`
   - Passar `tools` no payload OpenAI

2. **`app/services/copilot/tools/`** — diretório com 6 arquivos
   - Cada um tem `self.schema` (function definition OpenAI) e `self.execute(args, conversation:, agent:)`

3. **`app/controllers/api/v1/accounts/conversations/copilot_chats_controller.rb`** — adicionar action
   - `POST .../copilot_chat/execute_tool` — recebe `{ tool_name, tool_args }`, executa server-side, retorna resultado

4. **Refatorar `CopilotPanel.vue`**:
   - Quando model retorna `tool_calls` na response, renderizar bubble especial com botão "Aplicar [nome_tool]"
   - Click → `POST .../execute_tool` → mostra resultado inline ("✓ Conversa marcada como resolvida")
   - Múltiplos tool_calls = múltiplos botões

#### i18n
- `COPILOT.TOOLS.{MARK_RESOLVED,ASSIGN,LABEL,PRIORITY,CANNED,TASK,APPLY,APPLIED,FAILED}`

### Validação
- [ ] Pedir no Copilot: "marca essa conversa como resolvida"
- [ ] Botão "Aplicar mark_resolved" aparece
- [ ] Click → conversa muda status para resolved
- [ ] Pedir: "atribui pro João" → botão "Aplicar assign_to_agent" → atribui

---

## 8. Phase 7.3 — Multi-Turn Workflows (state machine)

**Objetivo:** Workflows pré-definidos que o Copilot guia o agente através de etapas. 3 workflows iniciais:
1. **`refund_flow`** — coleta motivo → valor → método → confirma → executa
2. **`escalation_flow`** — coleta urgência → motivo → contexto → escala
3. **`feedback_flow`** — pergunta NPS → comentário → motivos → finaliza

### Arquivos

#### Backend
1. **Adicionar gem `aasm` no Gemfile** (~> 5.5)
   - `bundle install`

2. **`app/services/copilot/workflow/base_workflow.rb`** — classe base com AASM
   - States: `idle, gathering, confirming, executing, completed, aborted`
   - Persistência em `conversation.additional_attributes['copilot_workflow']`

3. **`app/services/copilot/workflow/refund_workflow.rb`** — herda da base
   - Define os steps específicos
   - Cada step tem prompt para o LLM extrair info, validações, transições

4. **`app/services/copilot/workflow/escalation_workflow.rb`**
5. **`app/services/copilot/workflow/feedback_workflow.rb`**

6. **`app/services/copilot/workflow_runner.rb`** — orquestrador
   - `start(workflow_name, conversation:)`
   - `step(input)` — recebe input do agente, avança state, retorna próximo prompt ou `done`
   - Usa `gpt-4o` para extrair intent e validar respostas

7. **`app/controllers/api/v1/accounts/conversations/copilot_workflows_controller.rb`**
   - `POST .../copilot_workflow/start { workflow }`
   - `POST .../copilot_workflow/step { input }`
   - `DELETE .../copilot_workflow` — aborta

8. **`config/routes.rb`** — adicionar `resource :copilot_workflow`

#### Frontend
1. **Estender `CopilotPanel.vue`** com modo "workflow"
   - Botão "Iniciar fluxo" abre menu com 3 workflows
   - Quando workflow ativo: header muda ("Fluxo de Reembolso — passo 2/5"), barra de progresso
   - Mensagens guiadas pelo state machine
   - Botão "Cancelar fluxo" sempre visível

2. **`api/conversations.js`** — adicionar:
   - `startCopilotWorkflow(conversationId, workflowName)`
   - `stepCopilotWorkflow(conversationId, input)`
   - `cancelCopilotWorkflow(conversationId)`

#### i18n
- `COPILOT.WORKFLOWS.{TITLE,START,REFUND,ESCALATION,FEEDBACK,STEP,OF,CANCEL,COMPLETED}`

### Validação
- [ ] Iniciar `refund_flow`
- [ ] Sistema pergunta motivo → responder → avança step
- [ ] Pular step / dar resposta inválida → LLM pede novamente
- [ ] Concluir fluxo → ação final executa (ex: cria mensagem privada com resumo)

---

## 9. Phase 7.6 — Voice-to-Copilot

**Objetivo:** Botão mic no composer do CopilotPanel — agente fala, áudio vai para Whisper, texto entra no chat e envia.

### Arquivos
1. **Estender `CopilotPanel.vue`**:
   - Botão mic ao lado do textarea
   - Click → `MediaRecorder` start, ícone vira "stop" pulsando
   - Click stop → blob webm → POST `/api/v1/accounts/:id/copilot_voice` (multipart)
   - Backend transcreve via Whisper (`language: 'pt'`)
   - Texto retorna → preenche o textarea → envia automaticamente OU agente confirma com Enter

2. **`app/controllers/api/v1/accounts/copilot_voice_controller.rb`**:
   - `POST .../copilot_voice` recebe multipart audio
   - Tempfile + `OpenAI::Client.audio.transcribe(parameters: { model: 'whisper-1', file:, language: 'pt' })`
   - Retorna `{ text: '...' }`

3. **`config/routes.rb`** — `post :copilot_voice` no scope da account

4. **`api/conversations.js`** — `transcribeCopilotVoice(audioBlob)`

### Validação
- [ ] Click mic → grava
- [ ] Click stop → áudio vai pro backend → Whisper retorna texto
- [ ] Texto preenche o textarea do Copilot

---

## 10. Pitfalls Conhecidos

1. **gpt-4o-mini falha em tool calling com 6+ tools** — sempre `gpt-4o` aqui. Não cair na tentação de "economizar".
2. **OpenAI tools schema é JSON** — definir `{ type: 'function', function: { name, description, parameters } }` corretamente.
3. **Conversation context muito longo estoura tokens** — truncar histórico em max 10 mensagens.
4. **Workflow state pode ficar inconsistente** — sempre validar `aasm_state` antes de aplicar input.
5. **MediaRecorder em Safari quebra com webm** — usar `audio/mp4` no fallback.
6. **`Inbox` model é muito tocado por Chat A** — coordenar com Walisson antes de editar.
7. **Vite cache não invalida** — sempre `rm tmp/cache/vite/last-build-production.json && touch <arquivos>`.
8. **`rbenv` não existe nesta VM** — `bundle exec` direto (RVM auto-loads).
9. **sudo NOPASSWD apenas para `systemctl restart chatwoot.target`** — qualquer outro sudo pede senha.
10. **`update_account` aceita só keys whitelisted** — settings novas precisam estar em `permitted_settings`.

---

## 11. Vault — Notas Relevantes

Antes de começar, leia:
- `vault/CLAUDE.md` (entry point)
- `vault/01-Permanentes/Chat SPX.md` (ambientes, credenciais, .env)
- `vault/02-MOCs/ROUTER - Engineering.md` (padrões e workflows)
- **`vault/02-MOCs/Projeto - Agentes IA.md`** ⭐ — escopo detalhado do projeto Agentes IA, ler INTEIRO
- `vault/02-MOCs/MOC - Credenciais e Acessos.md`

**Após completar trabalho não trivial:**
- Erro inesperado → `vault/01-Permanentes/Licao - ...md`
- Padrão reutilizável → `vault/01-Permanentes/Padrao ...md`
- Boa prática → `vault/01-Permanentes/BP - ...md`

---

## 12. Comunicação com o Walisson

- pt-BR direto, frases curtas
- Sem emojis, sem trailing summaries longos
- Quando bloqueado, dizer explicitamente
- Após cada feature: 1 frase descrevendo + screenshot path + smoke result
- "faz o que achar melhor" / "não me pergunte" = executar end-to-end sem pausar

---

## 13. Critérios de "Pronto"

Cada feature está pronta quando:
- [ ] Backend implementado + testado via Rails console
- [ ] Frontend implementado, build passa
- [ ] i18n `en` + `pt_BR` adicionado
- [ ] ESLint sem erros novos
- [ ] Rubocop sem offenses novos
- [ ] Enterprise overlay verificado
- [ ] HTTP smoke 200
- [ ] Playwright logado com screenshot mostrando feature
- [ ] Walisson notificado

**Pronto-pronto (commit-ready):**
- [ ] Phase 7.1, 7.2, 7.3, 7.6 entregues
- [ ] Smoke consolidado verde
- [ ] Walisson aprova explicitamente

Só então: branch `feature/phase7-ai-agents`, commits Conventional, PR contra `homologacao`.

---

## 14. Ordem de Execução Sugerida

1. **Aguardar Chat A terminar §6** (especialmente §6.2 chave OpenAI por conta + §6.5 modelo selector — você depende disso)
2. **Phase 7.2 Tool Calling primeiro** — é o building block de 7.1 e 7.3, e é mais simples
3. **Phase 7.6 Voice** — independente, rápido, dá vitória cedo
4. **Phase 7.3 Workflows** — usa tool calling como base
5. **Phase 7.1 Agentes IA** — o mais complexo, deixa por último

---

## 15. Em Caso de Dúvida

1. Decisão técnica → consultar vault primeiro
2. Bloqueio (chave faltando, lib quebrada) → reportar e aguardar
3. Conflito Enterprise → `prepend_mod_with`/`include_mod_with`
4. Conflito com Chat A → reportar Walisson antes de editar arquivo compartilhado

---

*Documento gerado em 2026-04-28 por Orion (aiox-master) — handoff para Chat B (Phase 7 IA pesada). Doc principal (Chat A): `docs/plan-workspace-v2-whatsapp-redesign.md`*
