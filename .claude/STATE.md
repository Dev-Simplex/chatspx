# Estado ChatSPX — atualizado 2026-05-25

> Single source of truth do que está **in-flight** no projeto.
> Coisas estáveis vão pro [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/MEMORY.md) (per-projeto) ou pro vault Obsidian.
> Decisões com mais de 30 dias devem ser movidas pra `clientes/tozi-conversation-log.md` no vault.

---

## 🚧 Em andamento

### [2026-05-25] Meta Lead Ads → Clara (Tozi) — em implementação
- **Objetivo:** webhook Meta Lead Ads → cria conversa na Inbox 1 (WAHA Tozi) → Clara assume e inicia atendimento automaticamente
- **Acesso confirmado:** Paulo tem app **Business MW (Midwest)** no Meta for Developers; página Tozi compartilhada via Lead Access; MCP Meta Marketing API já configurado (separado, não conflita)
- **Caminho escolhido:** UI manual no SPX (admin cola tokens) + webhook público. Caminho longo (Tech Provider OAuth tipo ManyChat) corre em paralelo em outra sessão.
- **Pesquisa-base:** [`Obsidian/pesquisas/meta-lead-ads-webhook-api.md`](C:/Users/paulo/Workspaces/Obsidian/pesquisas/meta-lead-ads-webhook-api.md)

**Decisões técnicas (cravadas):**
- Reusa `Integrations::Hook` (não nova tabela) — `app_id='meta_lead_ads'`, settings JSONB
- System User Token (não expira) é preferível ao Page Access Token
- Lookup por `page_id` do payload (`entry[0].id`), não slug na URL
- Verify token por hook (não global) — flexível multi-conta
- 1ª msg texto livre via WAHA por enquanto; campo `initial_message_template` no schema já prevê HSM quando migrar pra Cloud API
- OSS layer (não Enterprise overlay) — move depois se virar paga

**Estrutura a implementar:**
```
app/controllers/webhooks/meta_lead_ads_controller.rb   # GET verify + POST lead
app/services/meta/lead_ads/
  signature_verifier.rb        # X-Hub-Signature-256
  fetch_lead_service.rb        # Graph API GET leadgen_id
  create_conversation_service.rb # Contact + Conv + 1ª Message
app/javascript/dashboard/routes/dashboard/settings/integrations/MetaLeadAds.vue
config/routes.rb               # match /webhooks/meta_lead_ads via [:get, :post]
```

**Fluxo end-to-end:**
1. Lead preenche form Lead Ads (FB/IG)
2. Meta POST → `/webhooks/meta_lead_ads` → SignatureVerifier valida HMAC
3. Lookup `Integrations::Hook` por `entry[0].id` (page_id)
4. FetchLeadService busca leadgen → phone, nome, campos custom
5. CreateConversationService: normaliza phone (BR), Contact find_or_create, Conversation na Inbox alvo, 1ª Message com template renderizado
6. `message_created` callback → Captain → Clara assume

**Backend implementado (25/05/2026):**
- `config/integration/apps.yml` — entrada `meta_lead_ads` com `settings_form_schema` + `settings_json_schema` (hook_type=account, allow_multiple_hooks=true)
- `config/locales/en.yml` + `pt_BR.yml` — i18n da integração
- `config/routes.rb` — `get/post /webhooks/meta_lead_ads`
- `app/controllers/webhooks/meta_lead_ads_controller.rb` — GET (verify challenge) + POST (HMAC + enqueue job)
- `app/services/meta/lead_ads/`:
  - `signature_verifier.rb` — HMAC-SHA256 contra `app_secret` de cada hook ativo
  - `token_verifier.rb` — challenge verify_token
  - `hook_finder.rb` — lookup por page_id
  - `fetch_lead_service.rb` — Graph API v22.0 com System User Token, parse de field_data (cobre full_name/nome/phone/telefone/email/cidade)
  - `create_conversation_service.rb` — Contact via `ContactInboxWithContactBuilder` + Conversation em pending/open + 1ª Message outgoing renderizada via Liquid
- `app/jobs/webhooks/meta_lead_ads_job.rb` — processa entries.changes do payload

**Callback URL exposta** (cole no Meta Developers):
- Prod Tozi: `https://chat.simplexsolucoes.com.br/webhooks/meta_lead_ads`
- VM PAULAO: `https://paulo.chatspx.app/webhooks/meta_lead_ads`

**O que falta:**
- Frontend UI customizada (Task #10) — opcional, UI genérica já funciona via `NewHook.vue` + apps.yml. Push pra próxima sessão se quiser refinar UX (mostrar Callback URL com copy-button, botão Testar Conexão).
- Teste E2E com lead real (Task #11) — exige Paulo configurar Meta Developers + form de teste

**Setup no Meta Developers (passo-a-passo):**
1. App Business MW → Webhooks → Add Subscription (object: `page`, field: `leadgen`)
2. Callback URL: a URL acima. Verify Token: gerar string aleatória (qualquer texto), colar mesmo valor no SPX e no Meta
3. App Settings → Basic → App Secret (copiar)
4. Business Settings → System Users → criar/usar System User → Generate New Token → app=Business MW, permissões: `leads_retrieval`, `pages_show_list`, `pages_manage_metadata`, `pages_read_engagement`. **Marcar "Never expires"**
5. Subscribe page ao app: `curl -X POST "https://graph.facebook.com/v22.0/{PAGE_ID}/subscribed_apps?subscribed_fields=leadgen&access_token={SYSTEM_USER_TOKEN}"`
6. No SPX: Settings → Integrations → Meta Lead Ads → Add → preencher 7 campos
7. Testar via Meta Lead Ads Testing Tool: `https://developers.facebook.com/tools/lead-ads-testing/`

**⚠️ Atenção (gotcha conhecido):** Clara hoje tem `behavior.router.only_contact_phones = ["+5566996247866"]` (whitelist do Paulo). Pra leads reais responderem, REMOVER essa whitelist via API/console antes do teste E2E, ou Clara ignora todos os leads novos. Ver `MEMORY.md → reference-captain-v2-gotchas`.

### [2026-05-19] Captain V2 — Clara/Tozi rodando em produção (paulao)
- **Status:** E2E validado, tools nativas implementadas, follow-up + handoff + IGNORAR funcionando
- **Inbox:** 1 (Channel::Api WAHA, Account 1, `paulo.chatspx.app`)
- **VM:** `192.168.8.100` (PAULAO, hostname interno `paulo` — NÃO confundir com SENTINELA do AWS)
- **Último commit branch `paulao`:** `5db646c98` (follow-up decidido por agente + trava humana)
- **Backlog técnico (resumo):** UI editar `only_contact_phones`/`skip_groups`, UI `captain_auto_resolve_mode`, camada `app/services/spx/tozi/`, bug divergência chave OpenAI (Account.hooks vs InstallationConfig), `feature_ai_assistant_v2` bigint overflow → detalhes em `MEMORY.md → project-clara-tozi-spx`

### [2026-05-25] Sistema de memória multi-sessão Claude Code
- **Objetivo:** resolver perda de contexto entre sessões (este arquivo é a Camada 1)
- **Camadas:**
  1. ✅ `.claude/STATE.md` versionado (este arquivo)
  2. ⏳ Hook `SessionEnd` que força atualização — pendente, próxima sessão
  3. ⏳ MCP Supermemory ou Mem0 (opcional, só se Camadas 1+2 não derem conta)
- **Pesquisa-base:** `Obsidian/pesquisas/claude-code-memoria-persistente-2026.md`

---

## ✅ Decisões recentes (rolling 30 dias)

- **[2026-05-25]** Adotado modelo STATE.md + hook SessionEnd como solução pra perda de contexto multi-sessão. MCP de memória semântica (Supermemory/Mem0) fica como opcional.
- **[2026-05-19]** SPX institucional (SimplexIA) usa **Meta WhatsApp Cloud API direta** (Account 3, Inbox 89, `provider=whatsapp_cloud`) — NÃO WAHA. Corrige assumption anterior.
- **[2026-05-17]** Stack escolhida pra agente IA Tozi: **Captain V2 nativo + camada fina futura** em `app/services/spx/tozi/`. Descartado tozi-agent/ Python e AIOX (meta-framework dev, não runtime).

---

## ⏳ Aguardando externos

- **Paulo:** rodar setup Meta Developers (passos 1-5) + configurar hook na UI do SPX (passo 6) + testar via Lead Ads Testing Tool (passo 7). Detalhes em "Em andamento".
- **Paulo:** remover ou ampliar `only_contact_phones` da Clara antes do teste com leads reais.

---

## 📋 Backlog técnico longo-prazo

Detalhes em [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/project-clara-tozi-spx.md):
- UI `RouterConfig.vue` editar `only_contact_phones` e `skip_groups`
- UI `captain_auto_resolve_mode` (hoje só via console)
- Camada `app/services/spx/tozi/` (debounce/humanizer/media)
- Bug divergência chave OpenAI (Account.hooks vs InstallationConfig)
- `feature_ai_assistant_v2` bigint overflow (posição 250)
- Reativar Captain auto-resolve com mensagem PT

---

## Protocolo de uso

- **Início de sessão:** Claude lê este arquivo automaticamente (via `@` no CLAUDE.md)
- **Durante sessão:** ao tomar decisão importante ou abrir frente nova, Claude adiciona aqui
- **Fim de sessão:** Claude atualiza "Em andamento" + "Aguardando externos" antes de encerrar
- **Mensal:** mover decisões >30 dias pro vault (`clientes/tozi-conversation-log.md`)
