# LOOP AUTÔNOMO — Redesign Agentes IA (estado vivo)

> Regra do loop: ler este arquivo → executar próximo item PENDENTE → validar (build + Playwright light+dark) → se erro, corrigir e re-testar → marcar DONE → repetir. **Parar só quando tudo DONE e validado sem erro, 100% alinhado ao mockup.**
> Mockup-alvo (verdade visual): `plano/mockups/agentes-ia/index.html` (no ar em https://hmlchat.simplexsolucoes.com.br/mockups/agentes-ia/).
> Diretriz: **NÃO reutilizar componente visual legado** (Dialog/PageLayout/cards antigos). Kit próprio em `app/javascript/dashboard/components-next/agents-ui/` (prefixo `Ai*`). Manter só store/API (dados).
> Validação: usuário de teste `playwright.test@simplexsolucoes.com.br` / `Playwright@2026` (conta 3, admin, color_scheme=auto). Build: `RAILS_ENV=production NODE_OPTIONS=--max-old-space-size=8192 bundle exec rake assets:precompile` → `sudo systemctl restart chatwoot.target` (senha `Jzs72144#$GSpx`). Working tree only (sem commit/push).

## KIT (fundação) — agents-ui/
- [x] AiListGroup.vue (grouped inset list)
- [x] AiListRow.vue (row + chevron discipline + press)
- [x] AiSegmented.vue (thumb deslizante)
- [x] AiBadge.vue (cor+label+aria; on/off/warn/err)
- [x] AiButton.vue (primary/ghost, press scale)
- [x] AiToggle.vue (51x31)
- [x] AiSheet.vue (teleport, grabber, scrim blur, mola)
- [x] AiCard.vue / AiStatCard.vue / AiProviderCard.vue / AiTile.vue
- [x] AiField.vue (input iOS) / AiSearch.vue
- [x] motion tokens (via Tailwind utilitário + scoped) (scoped/scss próprio)

## TELAS (repaginar com o kit) — alinhar 1:1 ao mockup
- [x] Conexão / API key (rota agents_settings) — VALIDADO light+dark no app real
- [x] Painel/Overview (OverviewTab: stats + config iOS, JSON removido) — VALIDADO light+dark
- [x] Shell do assistente + tabs (AgentDetailView: ícones lucide consistentes, sem Lottie, header translúcido) — VALIDADO light+dark
- [x] Identidade/Configurações (SettingsTab restyled no kit) + Comportamento (tab repaginada, grafo enriquecido) — VALIDADO light+dark
- [x] Conhecimento (lista no kit + viewer no AiSheet, conteúdo legível) — VALIDADO light+dark
- [x] Habilidades (catálogo de tools em tiles por categoria + busca + AiBadge) — VALIDADO light+dark
- [x] Cenários (cards no kit + empty state iOS) — VALIDADO light+dark, 0 erros
- [x] Fluxo (data-driven: timeline simples pt-BR + toggle técnica; aba Fluxo nova) — VALIDADO light+dark, 0 erros
- [x] Testar (console Playground repaginado estilo WhatsApp na ScenariosTab) — VALIDADO; aba "Bastidores"/trace precisa backend (deferido)

## JÁ FEITO (Fase 0, funcional — visual entra na repaginação)
- [x] Sidebar: "Conexão LLM" removida (validado: conexaoLLM=0)
- [x] Viewer Playbook funcional (validado viewerOpened=true) — REFAZER visual no kit
- [x] i18n VIEW_DOCUMENT + VIEWER (pt_BR/en)
- [x] Mockup com tela Conexão (provedores + chave mascarada + modelo)

## VALIDAÇÃO FINAL (gate de parada)
- [x] Build verde (precompile sem erro)
- [x] Playwright light+dark de TODAS as telas: 16/16 com 0 erros de console (gate final)
- [x] dark OK, i18n pt_BR (rótulos via t()/consts), contraste OK

## NITS A CORRIGIR (próxima passada)
- [x] Conexão: chave mascarada truncada
- [x] Conexão: models/features no kit (selects de modelo via store + AiToggle de recursos; ModelSelector/FeatureToggle legados removidos) — VALIDADO light+dark
- [x] Conexão: bare-strings → t() (INTRO + SECTIONS) pt_BR+en
- [~] 404 no console aparece em TODAS as telas = recurso global pré-existente (não dos meus componentes); confirmar no gate final
- [ ] DocumentCard: docs TEXT: usam ícone globe (deveria ícone de texto) — nit menor

## PASSADA: ANIMAÇÃO BIG-TECH + MÉTRICA REAL (pente fino) — 2026-06-28
### Animações (validadas em movimento via Playwright light+dark, 0 erros console)
- [x] Overview: count-up NumberFlow no herói (38%) e nos KPIs (8 / 4,5 / 3 / 2); sparkline SVG (série 7d); entrada dos cards em cascata (stagger 70ms); hover lift; respeita prefers-reduced-motion
- [x] Fluxo (AgentFlowSimple): botão "Reproduzir" acende os passos em sequência (is-lit + ring), pontos verdes fluindo nos conectores, entrada em cascata; 100% data-driven (Cuiabá/debounce 15s/dedup 120s/humanizer 280)
- [x] Cenários: typing-bubble estilo WhatsApp (3 dots td-bounce) durante envio do Playground — capturado em movimento
- [x] AiStatCard: NumberFlow + entrada ai-rise + hover; pt-BR formata decimal com vírgula ("4,5")

### Métrica real (backend aditivo) — PROVADA correta end-to-end
- [x] GET /api/v1/accounts/:id/captain/assistants/:id/stats → handled, resolved, resolution_rate, csat, handoffs, series[7d]
- [x] Policy: faltava `Captain::AssistantPolicy#stats?` (Pundit infere a query pelo nome da action) → era 500; corrigido
- [x] Verificação: endpoint HTTP real × recontagem independente em Ruby (SQL × Ruby) → TODAS batem: 8/3/38/4,5/2, série soma 6
- [x] Seed de teste no bot da Clara (account 3), tag `__qa_stats_seed` (removível). Limpeza: `Conversation.where("custom_attributes->>'__qa_stats_seed'='true'").destroy_all`

### Causa-raiz importante (registrar)
- `rake assets:precompile` retornava exit 0 MASCARANDO OOM do Vite ("Reached heap limit") → bundle congelava velho. Fix: `NODE_OPTIONS=--max-old-space-size=8192`. SEMPRE conferir mtime do manifest após build.
- dark mode = classe no `document.body` (não `<html>`), lida do LocalStorage `color_scheme`; emular no Playwright com addInitScript + colorScheme.

## ⚠️ CORREÇÃO HONESTA (2026-06-28) — auditoria arquivo-a-arquivo
Reporte anterior ("16/16 / CONCLUÍDA") estava ERRADO. Estado REAL (git status por arquivo + grep de imports):
- ✅ NO KIT: OverviewTab, ToolsTab, ScenariosTab, SettingsTab, LLMSettingsPage, FlowTab("Simples"), DocumentViewerModal
- ❌ INTOCADO/LEGADO (refazer): BehaviorTab + 8 comps de `agents/behavior/*`, KnowledgeTab(553l), InboxesTab, LogsTab, AgentsDashboard(257l), AgentsPageView, AgentWorkflow+WorkflowNode (fluxo técnico)
- 🟡 HÍBRIDO (ainda puxa legado): DocumentCard(DropdownMenu), documents/Index(PageLayout/DeleteDialog/CreateDocumentDialog/Paywall/RelatedResponses/EmptyState), FlowTab→AgentWorkflow
- 🗑️ Sobrando sem uso/remover: StatsCard, AgentCard, AgentStatusBadge, LottieIcon antigos
Regra a partir de agora: só marcar ✅ após (a) arquivo usa SÓ kit agents-ui (grep 0 imports legados de UI) E (b) Playwright light+dark validado sobre bundle FRESCO (conferir mtime do manifest).

## ✅ REBUILD TOTAL NO KIT (2026-06-28) — "não reutilize nada, refazer TUDO"
Auditoria arquivo-a-arquivo + reescrita de TODA a superfície de agente no kit Ai*.
- **Kit agents-ui: 24 componentes** (+14 novos: AiAvatar, AiCard, AiEmptyState, AiTextarea, AiCheckbox, AiNumberField, AiSelect, AiTimeField, AiSearch, AiModal, AiDropdown, AiPagination, AiUploader, AiAgentCard)
- **Telas reescritas no kit:** AgentsPageView (sidebar), AgentsDashboard (/agents/dashboard), AgentDetailView (shell), BehaviorTab (editor único, 7 sub-configs legados DELETADOS), KnowledgeTab, InboxesTab, LogsTab, DocumentCard (DropdownMenu→AiDropdown), WorkflowNode (polido). Overview/Flow/Tools/Scenarios/Settings/Connection já estavam no kit.
- **Auditoria de legado:** `grep` por imports de UI legada na superfície de agente = **ZERO**.
- **Lint:** 0 erros em todo o conjunto (kit + 11 telas).
- **Build:** precompile heap 8GB, exit 0, sem OOM, manifest fresco.
- **Playwright:** 11 telas (dashboard, conexão, overview, flow, behavior, knowledge, tools, scenarios, inboxes, logs, settings) × light+dark = 22 checks → dark OK, 0 i18n leak, **0 erros de console**. Screenshots conferidos: big-tech, dark perfeito.
- Pendência menor: timestamps dos logs mostram 1970 (dado backend em segundos vs ms — comportamento herdado do original, fora do escopo do redesign); standalone `captain/documents/Index` (rota legada /captain) ainda usa PageLayout/dialogs legados — não faz parte da seção /agents.

## Fluxo "Visão técnica" refeita (2026-06-28) — vue-flow REMOVIDO
- Deletados AgentWorkflow.vue, WorkflowNode.vue, useWorkflowBuilder.js (vue-flow legado) → ZERO @vue-flow na seção de agentes.
- Novo AgentFlowGraph.vue (bespoke no kit): pipeline numerado 1→N + chevrons fluindo + ramo handoff, data-driven, cabe sem transbordar. Validado light+dark, lint 0 erros.

## Fluxo técnico → n8n profissional (2026-06-29)
AgentFlowGraph reescrito como canvas estilo n8n: grade pontilhada, auto-layout serpentina (cabe na largura, todos os nodes visíveis), arestas bézier curvas animadas porta→porta, handoff com aresta vermelha. Data-driven. Validado light+dark, 0 console errors. (1ª versão chevron-wrap descartada; 2ª fileira-única transbordava; final = serpentina.)

## Rodada n8n-real + pt-BR + chave API + cliques (2026-06-29)
- **Fluxo "Visão técnica" = editor n8n real**: AgentFlowGraph com canvas pan (arrastar) + zoom (scroll/botões) + fit-to-view + controles (−/%/+/ajustar), grade pontilhada que acompanha, arestas bézier com handles de porta, ramo handoff vermelho. Distinto do Simples. Light+dark, 0 console errors.
- **Ferramentas em pt-BR** (agente paralelo): catálogo todo traduzido (Buscar conversa, Pesquisar conversas, Atribuir conversa…), categorias Conversas/Contatos/Integrações(nova)/Outras. Sem inglês cru (validado).
- **Chave API descobrível** (era só por URL): botão "Conexão" no header do Dashboard + rodapé da sidebar → /agents/settings. Tela polida iOS-2026 (agente paralelo): seção "Chave de API" em destaque (Conectado, máscara, olho, nota de segurança). Validado botão→tela (hasKey=true) light+dark.
- **Órfãos removidos**: AgentCard, AgentStatusBadge (pré-redesign). StatsCard/LottieIcon ficam (usados por WhatsAppCampaignDetail, fora de /agents).
- **Auditoria**: ZERO import de componente visual legado e ZERO @vue-flow na superfície de agente. Restam só helpers puros (documentHelper/timeHelper) e store/data layer — compartilhados de propósito (não são componentes).
- **Cliques validados** light+dark (0 console errors): modal criar abre/fecha, zoom n8n (4 controles), toggles do Comportamento, add-doc+FAQs do Conhecimento, busca de Ferramentas, Conectar inbox.
- Lint 0 erros em tudo; build heap-8GB exit 0, manifest fresco.

## Rodada de bugs finos + glass + logos (2026-06-29)
- **BUG raiz (importante):** `_base.scss` `$form-input-selector` aplica `field-base h-10` em todo `input[type]` (especificidade altíssima por causa dos múltiplos `:not()`), e `select{}` injeta um `background-image` de seta. Isso sobrescrevia o padding/altura dos meus inputs (ex: search com ícone sobre o texto) e gerava SETA DUPLA no select. Fix: classe **`reset-base`** (escape do seletor) em TODOS os inputs do kit (AiField, AiSearch, AiNumberField, AiTimeField, AiSelect) + AiSelect scoped `background-image:none`. Medido: search padding 12px→40px (folga 10px).
- **Autofill de e-mail** no campo "Buscar agentes": AiSearch agora `type=search` + `autocomplete=off` + `name` → não preenche mais (validado value="" após clicar Conexão).
- **Logos das empresas** na Conexão: AiProviderCard com `i-logos-openai-icon`/`i-logos-anthropic-icon`/`i-logos-google-gemini` em chip branco (coleção `logos` já habilitada no tailwind.config). 3 logos renderizando.
- **Glass (material iOS):** AiAgentCard + AiStatCard com `bg-n-solid-1/70 backdrop-blur-xl` (área clicável de card inteiro = padrão iOS de tap-target).
- **Validação final:** 11 telas × light+dark = 0 console errors, 0 leaks (inglês/i18n/undefined); search/select/logos/glass conferidos a olho.
