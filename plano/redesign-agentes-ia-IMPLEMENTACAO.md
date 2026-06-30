# Plano de Implementação — Redesign Agentes IA (Captain) · ChatSPX

> Mockup aprovado (visual iOS + motion big-tech): **https://hmlchat.simplexsolucoes.com.br/mockups/agentes-ia/**
> Decisões: genérico/multi-tenant · consolidar rotas `/captain`→`/agents` com redirects · fluxo data-driven com toggle Simples/Técnico · iOS-fiel + animado.
> Regra de QA (vault): **build verde ≠ UI OK** → validar cada tela com Playwright em **light + dark** antes de fechar.

---

## Fase 0 — Fundação (Design System iOS + Motion) · pré-requisito de tudo
Criar primitives reutilizáveis em `app/javascript/dashboard/components-next/ios/` (light+dark, tokens `n-`):

| Componente | Papel | Base de motion |
|---|---|---|
| `IosListGroup.vue` / `IosRow.vue` | grouped inset list + chevron discipline (chevron só em linha que navega) | `<Transition>` |
| `IosSegmented.vue` | segmented control com **thumb deslizante** (spring) | CSS spring + JS measure |
| `IosToggle.vue` | switch 51×31 verde (aplica na hora, sem Save) | CSS |
| `IosSheet.vue` | modal/drawer com grabber + scrim `backdrop-blur` + entrada com mola | `<Transition>` |
| `IosBadge.vue` | chip de estado **cor+label+aria** com stroke na cor da superfície | — |
| `IosSearchField.vue`, `IosStatCard.vue` | busca + card de métrica | `@number-flow/vue` (já no projeto) |

- **Motion tokens** em `assets/scss/_motion.scss`: durações (.16/.34/.5s) e easings (`cubic-bezier(.34,1.56,.64,1)` spring, `(.22,1,.36,1)` ease-out), guard global `@media (prefers-reduced-motion)`.
- Reaproveitar libs já presentes: **NumberFlow** (count-up — já usado nas abas), **Vue `<Transition>/<TransitionGroup>`**, **vue-flow** (grafo). Nada novo de dependência.

---

## Fase 0 — Quick wins (baixo risco, alto valor — fecham 2 das 4 reclamações)

### Q1. Sidebar — remover "Conexão LLM"
- `components-next/sidebar/Sidebar.vue` (item "AI Agents", ~linhas 401-419): deletar filho "LLM Settings" (~412-417). Como sobra 1 filho, colapsar "AI Agents" em **item único** → `agents_dashboard`.
- Config LLM passa pra **"Opções avançadas"** do agente (`SettingsTab`) — ver decisão #2.
- i18n: remover `SIDEBAR.CAPTAIN_OPENAI_CONNECTION` após.

### Q2. Viewer do Playbook (fix do "não acessa")
- **Novo** `components-next/captain/assistant/DocumentViewerModal.vue` (usa `IosSheet`): PDF via `<iframe :src="display_url">`/pdf.js; inline/URL via campo `content`; botão Baixar.
- `DocumentCard.vue` (~46-66): adicionar ação **"Ver documento"** (`i-lucide-eye`) → emite `viewDocument`; linha clicável.
- `routes/dashboard/captain/documents/Index.vue` (~56-68): tratar `viewDocument` → `dispatch('captainDocuments/show', id)` → abrir modal.
- Backend **já expõe** `display_url`/`content`/`content_type` (serializer `_document.json.jbuilder` + `DocumentsController#show`). Sem mudança de back pra ver via iframe.

### Q3. i18n pt_BR
- Completar `i18n/locale/pt_BR/settings.json`: `CAPTAIN.AGENT_TABS.*` e demais chaves que hoje caem em fallback EN.

---

## Fase 1 — Catálogo de Tools + cards padronizados (alto valor)

### Tools (a tela "muito feia")
- **Backend:** campo `category` em `config/agents/tools.yml`; migration `add_category_to_captain_custom_tools`; expor os built-in (`COPILOT_TOOLS`, hoje hardcoded no `.vue`) via **API** (estender endpoint de tools com `type`/`category`) — fonte única.
- **Frontend:** refatorar `components-next/agents/tabs/ToolsTab.vue` →
  - `ToolTile.vue` (ícone colorido por categoria, nome legível — nunca snake_case, descrição, `IosBadge` Ativa/Inativa/**Requer config**).
  - Grid agrupado por categoria + `IosSegmented` (Mais usadas/Todas/Personalizadas) + `IosSearchField`.
  - Drawer `ToolDetail` (`IosSheet`): o que faz, parâmetros (builder em linhas → gera JSON-schema), exemplos, toggle Ativar; marcar tools que **escrevem** vs só leem.
  - **Multi-tenant:** tool com credencial não configurada (Vista/Google por conta) → badge "Requer config", não some (casa com commit `b45f3f578`).
- Padronizar `ResponseCard.vue`/`DocumentCard.vue`/`InboxCard.vue` na linguagem visual nova; unificar empty states (`components-next/captain/pageComponents/emptyStates`).

---

## Fase 2 — Fluxo data-driven + Visão Simples (resolve o "genérico")
- `composables/.../useWorkflowBuilder.js`:
  - `PIPELINE_NODES` (array const ~9-49) → **`computed(assistant)`** (config+behavior+tools+scenarios).
  - `getNodeSummary` (~172-199): ler `assistant.config` (modelo/temperatura), **adicionar case `media_pipeline`**, Handoff com time/destino real, Router com todos `skip_*`, Business Hours com timezone+janela, Debounce/Dedup/Humanizer reais; **nós dinâmicos** de Tools ativas e Cenários.
- **Novo** `AgentFlowSimple.vue`: timeline vertical pt-BR (labels por resultado, handoff destacado, ponto de energia no trilho, **▶ Reproduzir**).
- `AgentWorkflow.vue` (grafo vue-flow): enriquecer com summaries reais + **arestas animadas** + replay.
- Toggle `IosSegmented` "Simples/Técnico" (Simples padrão; mobile só simples).

### Overview analítico (junto)
- `AgentsDashboard.vue` + `OverviewTab.vue`: **KPI-herói** traduzido + cards com NumberFlow + sparkline + bloco "Lacunas de conhecimento" + **galeria de templates** como empty state. Tirar JSON cru de config do overview (→ avançado).

---

## Fase 3 — Editar Assistant como onboarding + Console de Teste (transformacional)
- **Editar Assistant:** consolidar `SettingsTab`/`BehaviorTab` num **stepper "treine como funcionário"** (descrição do negócio em texto livre; presets de tom; avançado colapsado: modelo/temp/debounce/dedup/humanizer). Mensagens editáveis (saudação, **fora-do-horário hoje hardcoded**, handoff, fallback) com `{{contato.nome}}`. **Checklist de prontidão** que bloqueia "Ativar" listando o que falta. **Rascunho vs Publicado** com rollback.
- **Console de Teste** (novo `TestConsole.vue`, split-pane / `IosSheet` no mobile): aba Conversa (bolhas WhatsApp reutilizando componentes de mensagem) + **Bastidores** (regra/fonte/tool, args/retorno/latência, "por que respondeu isso"). Backend: endpoint **dry-run** do assistant (sem tocar conversa real); marcar conversas-teste como excluídas de relatórios/CSAT.

---

## Fase 4 — Conhecimento avançado + Cenários + Replay (incremental)
- **Base de conhecimento:** migration adicionar status `failed` ao enum (hoje só `in_progress/available`); barra de chunks (`captain_document_chunks`); ação **Reprocessar** (re-enfileira `CrawlJob`/`ChunkBuilderJob`); ícone por tipo de origem; agrupar por saúde; preview com `contextual_content`. (Opcional) extração de texto de PDF (`pdf-parse`) p/ preencher `content`.
- **Cenários:** procedimentos em linguagem natural (cards), "Testar cenário", importar SOP, linter de contradição; refletir como nós no Fluxo.
- **Replay de conversa real** no Fluxo/Console (definir política de privacidade — ver decisão).

---

## Cross-cutting — Consolidação de rotas
- Unificar `/captain/:id/*` (responses, documents, tools, scenarios, playground…) sob `/agents/:assistantId` com tabs; adicionar **redirects** (rotas `redirect:` no router) dos paths antigos. Aposentar `PageLayout` legacy gradualmente.

---

## Testes, rollout e autoridade
- **Playwright light+dark** por tela (DOM walker: vazamentos i18n, contraste, ícones) — obrigatório antes de marcar fase done.
- **Feature flag por conta** (settings jsonb) p/ ligar o novo Agentes IA gradual; **piloto Clara/Tozi** primeiro, depois geral.
- 1 PR por fase; **push/deploy = @devops** (regra de autoridade); nada de deploy automático.

## Ordem & dependências
Fundação(0) → Quick wins(0) → Fase 1 → Fase 2 → Fase 3 → Fase 4. Rotas consolidadas em paralelo a partir da Fase 2.

## Decisões abertas (recap)
LLM config: "Opções avançadas" por agente vs conta · Tools por agente (join `captain_assistant_tools`) agora vs depois · Replay com conversas reais vs sandbox · Migration `failed` ok? · PDF text-extraction agora vs depois.
