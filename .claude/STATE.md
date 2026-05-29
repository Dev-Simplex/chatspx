# Estado ChatSPX — atualizado 2026-05-27

> Single source of truth do que está **in-flight** no projeto.
> Coisas estáveis vão pro [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/MEMORY.md) (per-projeto) ou pro vault Obsidian.
> Decisões com mais de 30 dias devem ser movidas pra `clientes/tozi-conversation-log.md` no vault.

> 🔴 **HANDOFF DE FECHAMENTO 29/05 → ler [`docs/HANDOFF-2026-05-29.md`](../docs/HANDOFF-2026-05-29.md) PRIMEIRO.**
> Próxima sessão foca em: reconciliar conflito de templates (2 sessões divergiram), corrigir deploy AWS (não-git + credencial), subir código paulao→prod Tozi, re-aplicar dados (funil/prompt Júlia #5/knowledge/hook), verificar quebras, implementar Bloco 3+4 cadência, e generalizar multi-cliente. Múltiplas sessões trabalharam no branch paulao em paralelo (5 commits de outras sessões — ver handoff §3).

---

## 🚧 Em andamento

### [2026-05-29] Vendas Tozi — Júlia repaginada + templates HSM + knowledge

**Base:** análise de 400+ áudios de atendimentos reais (corretor Henrique, alta conversão) em `C:/Users/paulo/Workspaces/tozi/analise-atendimentos/` (ANALISE-COMPORTAMENTAL.md, PLAYBOOK-VENDAS-TOZI.md, FAQ-TOZI.md, julia-vendas-PROPOSTA.md). Método: consultivo, tom "de Sinop", descobre a pessoa antes dos números (direção do gerente Guilherme: "não quero SDR que pergunta 'qual sua renda bruta'").

**Feito (PAULAO + WABA prod):**
1. ✅ **Prompt da Júlia (Scenario Vendas #1, account 1)** atualizado da proposta: 4458→6273 chars, agora com consciência de nicho (5 nichos), qualificação humanizada, represamento de lançamentos, handoff por nicho, consulta à knowledge. Backup: `/tmp/julia_backup_1780092115.txt` na VM PAULAO. **A proposta NÃO estava aplicada antes — só era documento.**
2. ✅ **Knowledge anexada à Clara** (assistant 1, knowledge_mode=chunks): doc#3 Playbook (19 chunks) + doc#4 FAQ (13 chunks), embeddings OK. Júlia consulta via search_documentation (RAG).
3. ✅ **4 templates HSM submetidos** no WABA Tozi (905788818829319) — PENDING aprovação Meta. IDs em `Obsidian/credenciais/tozi.md`.

**Acesso produção descoberto:** VM AWS `3.82.215.109` (tozi.chatspx.app), chave `Downloads/handoff-tozi/simplex.linux.pem`, Account 6. **Não é git** (deploy via script). Detalhes em `credenciais/tozi.md`.

**Falta:**
- Aplicar o mesmo (prompt Júlia + knowledge) em **produção AWS Account 6** quando subir — lá o Scenario Vendas é #5, assistant Clara #7, ainda com prompt antigo (4458).
- Aprovar/ajustar templates com o time (Paulo confirmando).
- Subir o código da branch paulao pra AWS (processo não-git a definir).
- Bloco 3+4 da cadência (state machine + ScheduledMessages) — ainda pendente.


### [2026-05-27] Meta Lead Ads → Clara (Tozi) — 🟢 EM PRODUÇÃO, aguardando lead orgânico

**Status:** Pipeline completo funcionando E2E. App em modo Live no Meta. Subscription ativa. Hook configurado. Testado via Lead Ads Testing Tool — webhook real chegou no SPX, conversa criada (id=146). Aguarda primeiro lead orgânico real (de campanha rodando) pra fechar ciclo com WAHA+Clara.

**Configuração final (27/05):**
- App Meta: **SPX Lead Ads Tozi** id=`1658426868710322`, criado dentro do BM Tozi, modo **Ao Vivo**
- Page Tozi: `539594042748152`, subscribed em field `leadgen` ✅
- Lead Access Manager: SPX Lead Ads Tozi listado como CRM ✅
- SU Token: nunca expira, salvo em `Obsidian/credenciais/tozi.md` seção "Meta Lead Ads"
- App Secret: `4c27cd1eb604a196f6ed1d74c05abacf` (vault)
- Verify Token: `228d3c9f0065ab7fa859255dce9b24795a60ff0bbd9988f2` (vault)
- Hook no SPX (Account 1): id=3, `skip_initial_message=true` (modo teste — não dispara 1ª msg ao lead até validar com lead real)
- Inbox alvo: 1 (WAHA Tozi, paulo.chatspx.app)
- Último commit: `005661347` (fix substring match + dummy filter na extração de campos)

**Validação E2E (27/05):**
- ✅ GET challenge respondido (Meta verificou webhook)
- ✅ POST de Meta IP real (`2a03:2880:2ff:4d::`) chegou em 13:23
- ✅ Job processou em 611ms, criou Conversation 146 (sem phone — form de teste tinha dummy data)
- ✅ Conversations criadas: 144, 145, 146 (todas testes, podem ser deletadas)

**Bugs identificados e corrigidos hoje:**
1. `Lead has no phone_number` raise → agora aceita lead sem phone (cria conv mesmo assim, não envia 1ª msg) — commit `09958905a`
2. Form com nomes custom PT-BR (`qual_seu_telefone?`) não casavam com lista exata de chaves → substring match + normalização de acentos/caracteres especiais — commit `005661347`
3. Test Tool injeta `<test lead: dummy data>` como valor → agora filtra via TEST_DUMMY_REGEX

**Bloqueios resolvidos hoje:**
- "App is not installed by any of the admins" → resolvido adicionando app ao Lead Access Manager
- "App em desenvolvimento, leads reais não disparam webhook" → resolvido ativando modo Live (URL política privacidade + categoria já configurados)
- Webhook ficava Pending no Tool → resolvido com DELETE+POST subscribed_apps (reset)

**Pesquisa-base:** [`Obsidian/pesquisas/meta-lead-ads-webhook-api.md`](C:/Users/paulo/Workspaces/Obsidian/pesquisas/meta-lead-ads-webhook-api.md)

**Antes do primeiro lead orgânico responder:**
- ⚠ Remover/ampliar whitelist `only_contact_phones` da Clara (hoje só responde +5566996247866)
- ⚠ Quando confiante, desligar flag `skip_initial_message` no hook (Settings → Integrations → Meta Lead Ads → Editar)

### [2026-05-27] Templates HSM WhatsApp via API do SPX — 🟢 mecanismo pronto, falta criar os templates Tozi

**Objetivo:** criar/submeter message templates (HSM) pra aprovação Meta sem abrir WhatsApp Manager — tudo via API do SPX. Base pra cadência em produção (Cloud API).

**Implementado (commits `de4014dd2` + `2991b61e7`):**
- `Whatsapp::TemplateManagementService` — generaliza `CsatTemplateService`. create/list/status/delete via Graph API v22.0. Aceita MARKETING/UTILITY/AUTHENTICATION + components livres. Usa `provider_config` business_account_id + api_key. Normaliza nome (lowercase+underscore).
- `Api::V1::Accounts::InboxMessageTemplatesController` — index/create/destroy scoped por inbox. Valida Cloud API (WAHA rejeitado). Rota: `resources :message_templates` dentro de inboxes.
- `rake spx:tozi:create_templates[account_id,inbox_id]` — cria os 4 templates da cadência: tozi_lead_inicial (MKT), tozi_lead_followup_dia (MKT), tozi_lead_reativacao (MKT), tozi_followup_horario_combinado (UTILITY).

**Status sync de aprovação:** já existe `Channel::Whatsapp#sync_templates` + `templates_sync_job`.

**Falta:** rodar `create_templates` numa inbox Cloud API. PAULAO é WAHA (sem WABA). Prod inbox 91 (número fixo Tozi Cloud API) serve. Precisa WABA id + api_key do provider_config da inbox 91, OU rodar a rake em prod.

### [2026-05-27] Kanban de Pré-Venda Tozi + Cadência de Follow-up — 🟡 EM CONSTRUÇÃO

**Descoberta chave:** o fork chatspx JÁ TEM sistema Kanban completo e robusto — não precisa construir. Componentes existentes a reusar:
- `Funnel` / `FunnelStage` / `FunnelItem` (models) — Kanban com colunas/cards/drag-and-drop
- `KanbanBoard.vue` + `ListView` + `CalendarView` (3 visualizações prontas em `routes/dashboard/kanban/`)
- `FunnelStage.automation_type` — move card automático (hoje só open/resolved)
- **`ScheduledMessage` + `ScheduledMessages::SendJob`/`CreateService`** — base PRONTA da cadência de follow-up (envio agendado, status pending/sent/failed/cancelled)
- `Kanban::FunnelItemsBackfillService`, `MoveConversationToAutomatedStageService`

**Diagramas de design (v3):** `docs/tozi-followup-{kanban,flow}.excalidraw` + `.png`. Renderer offline: `docs/render_excalidraw_offline.py` (PIL, sem CDN — porque esm.sh está bloqueado no ambiente). Cadência definida: A (frio, 2h/24h/3d, Marketing), B (silêncio, trigger=pergunta pendente, 15min/1h/6h/24h, Service→Marketing), AGENDADO só com horário definido, 24/7 (sem horário comercial), QUALIFICADO = saída.

**Implementado hoje (PAULAO, Account 1, Inbox 1):**
- Bloco 1 ✅ — `rake spx:tozi:setup_funnel[1,1]` cria funil "Pré-Venda Tozi" (id=6) com 7 stages (automation_type: novo_lead, aguardando_1a, em_conversa, em_silencio, agendado, qualificado, frio). Idempotente, parametrizável pra prod (6,91).
- Bloco 2 ✅ — `Spx::Tozi::FunnelPlacementService` + hook no `CreateConversationService` → lead Meta entra em "Novo Lead". `rake spx:tozi:backfill_funnel[1]` colocou 45 leads existentes.

**Falta (próxima sessão):**
- Bloco 3 — `Spx::Tozi::FunnelAutomationService` (state machine): move cards por evento (incoming→em_conversa, pergunta+15min→em_silencio, cap→frio, handoff→qualificado). Hook em message_created.
- Bloco 4 — cadência via ScheduledMessages: cria mensagens agendadas (A/B) quando lead em espera, cancela pending quando responde. Reusa SendJob existente.

**Produção:** trabalho feito no PAULAO (WAHA). Em prod (Account 6, Inbox 91 = número fixo Tozi com Cloud API oficial), cadência usa templates HSM (janela 24h + categorias Marketing/Utility/Service valem). ScheduledMessage envia pelo canal da inbox → mesmo código, transparente.

### [2026-05-25] Meta Lead Ads — histórico de implementação
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

- **[2026-05-27]** Criado app **SPX Lead Ads Tozi** (id `1658426868710322`) dentro do BM Tozi (não cross-BM via Business MW). Caminho cross-BM exigia Partnership e era overhead — app no BM dono da página é mais limpo.
- **[2026-05-27]** Implementada UI de editar hook (`EditHook.vue`) — não é mais limitação do Chatwoot core, fork nosso. Vale pra todas integrações declarativas.
- **[2026-05-27]** Adicionada flag `skip_initial_message` no hook pra modo teste sem enviar msg ao lead.
- **[2026-05-25]** Adotado modelo STATE.md + hook SessionEnd como solução pra perda de contexto multi-sessão. MCP de memória semântica (Supermemory/Mem0) fica como opcional.
- **[2026-05-19]** SPX institucional (SimplexIA) usa **Meta WhatsApp Cloud API direta** (Account 3, Inbox 89, `provider=whatsapp_cloud`) — NÃO WAHA. Corrige assumption anterior.
- **[2026-05-17]** Stack escolhida pra agente IA Tozi: **Captain V2 nativo + camada fina futura** em `app/services/spx/tozi/`. Descartado tozi-agent/ Python e AIOX (meta-framework dev, não runtime).

---

## ⏳ Aguardando externos

- **Lead orgânico real** de campanha Tozi rodando → vai disparar webhook automático e criar conversa (Clara não responderá enquanto flag `skip_initial_message=true` e whitelist `only_contact_phones` estiverem ativos).
- **Paulo:** quando quiser, ampliar `only_contact_phones` da Clara + desligar `skip_initial_message` no hook.
- **(Opcional, limpeza):** deletar conversas de teste 144, 145, 146 (mesmo lead replay, source=meta_lead_ads).

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
