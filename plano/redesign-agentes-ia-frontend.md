# Redesign Frontend — Agentes IA (Captain) · ChatSPX

> Pesquisa+diagnóstico via 14 subagentes (4 código + 9 web + 1 síntese). Data: 2026-06-27.
> Direção: **"Treine sua IA como um novo funcionário"** — linguagem de negócio em pt-BR, shell visual iOS-fiel sobre os tokens `n-` (dark mode obrigatório), leigo-primeiro, com transparência/confiança (console de teste).

---

## Diagnóstico de causa-raiz (os 4 pontos que você apontou)

### 1. Sidebar — "Conexão LLM"
- **Arquivo:** `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, item "AI Agents" (linhas ~401-419), filho "LLM Settings" (linhas ~412-417, label `SIDEBAR.CAPTAIN_OPENAI_CONNECTION` → `agents_settings`).
- **Fix:** deletar o objeto filho. Como sobra 1 filho só (Dashboard), simplificar "AI Agents" para item único → `agents_dashboard`. Roteamento intacto (`agents_settings` continua acessível). Config de LLM passa pra "Opções avançadas" do agente.

### 2. Fluxo (vue-flow) genérico
- **Arquivo:** `useWorkflowBuilder.js` — `PIPELINE_NODES` é **array constante** (linhas ~9-49); `getNodeSummary` (~172-199) lê só parte de `assistant.behavior` (timezone, max_chars, ttl) e **nunca** lê `assistant.config` (modelo, temperatura), não tem case pra `media_pipeline`, e ignora tools/cenários → **todo agente fica igual**.
- **Fix:** tornar `nodes` um `computed` a partir do `assistant` (config+behavior+tools+scenarios); enriquecer cada nó com dado real; + nós dinâmicos de Tools/Cenários. E uma **"Visão simples"** (timeline vertical pt-BR) como padrão.

### 3. Playbook de Vendas Tozi não abre
- **Causa:** backend **completo** (serializer expõe `display_url`/`content`/`content_type`, `DocumentsController#show` e `ApiClient.show` existem) — falta **a camada de UI**. `DocumentCard.vue` só tem "Ver respostas relacionadas" + "Excluir"; não existe viewer.
- **Fix:** criar `DocumentViewerModal.vue` (PDF via `<iframe :src="display_url">`/pdf.js; inline/URL via campo `content`; botão Baixar) + ação "Ver documento" no `DocumentCard.vue` + handler em `documents/Index.vue`.

### 4. Tools como lista crua
- **Arquivo:** `ToolsTab.vue` — ~51 built-in hardcoded (`COPILOT_TOOLS`, string list) + custom como cards soltos, **sem categoria**, account-scoped.
- **Fix:** campo `category` no `tools.yml` + migration em `captain_custom_tools`; mover `COPILOT_TOOLS` pra API; `ToolTile.vue` em grid agrupado por categoria, badge de estado (Ativa/Inativa/Requer config), busca, drawer de detalhe.

### Dívida visual transversal
Duas arquiteturas coexistindo (`/agents` moderno com tabs vs `/captain` legacy com PageLayout) → inconsistência; Lottie desordenado; cards antigos (border-only) vs cards novos (gradient); i18n pt_BR incompleto (`CAPTAIN.AGENT_TABS.*` caindo em fallback EN).

---

## Conceito por tela

- **Painel/Overview:** large title iOS colapsável; lista de agentes como grouped inset list (avatar + chip de estado "Em teste/Ativo em 1 canal/Ativo" + chevron); 1 **KPI-herói** traduzido ("a IA resolveu 7 de cada 10 conversas") + cards com sparkline; bloco "Lacunas de conhecimento" acionável; empty state = **galeria de templates clonáveis** (não um "+").
- **Lista de Assistants:** mesma inset list; swipe/long-press (Duplicar/Pausar/Testar/Excluir); "Novo agente" = wizard (linguagem natural ou clonar template); segmented control Todos/Ativos/Em teste.
- **Editar Assistant:** onboarding em passos "treine como funcionário" (quem é → sobre o negócio → o que sabe → o que pode fazer → quando passar pra humano → mensagens → testar/ativar); avançado (modelo/temp/debounce/dedup/humanizer) **colapsado**; mensagens editáveis (saudação, fora-do-horário hoje hardcoded, handoff, fallback) com `{{contato.nome}}`; checklist de prontidão que **bloqueia "Ativar"** listando o que falta; Rascunho vs Publicado.
- **Fluxo:** **data-driven**, 2 visões — Simples (timeline vertical pt-BR estilo Apple Shortcuts, labels por resultado, handoff destacado) como padrão; Técnica (grafo enriquecido) atrás de segmented control; mobile só simples. **Replay de conversa real** anotada (prova que é o fluxo daquele agente).
- **Tools:** catálogo visual de tiles agrupados (Imóveis&CRM, Agendamento, Atendimento humano, Busca&Conhecimento, Conversa, Personalizadas); badge de estado com stroke (cor+label+aria); "Requer config" multi-tenant (casa com credenciais Vista/Google por conta); drawer de detalhe; marcar tools que **escrevem** vs só leem.
- **Base de Conhecimento:** **fix do viewer** (item 3) + status trio (Processando/Treinado/Falhou — precisa migration p/ enum `failed`) + barra de chunks + "Reprocessar" + ícone por tipo de origem + cabeçalho agregado ("48 docs · 44 treinados · 1 falhou · 6.210 chunks") + preview com `contextual_content`.
- **Respostas prontas:** padronizar `ResponseCard` na linguagem visual nova; busca + grupos; create/edit em sheet; micro-stat ("usada em 42 conversas"); templates pt-BR.
- **Cenários:** procedimentos em linguagem natural (SOP/playbook) como cards; "Testar este cenário" no console; importar/colar SOP → estrutura; refletir no Fluxo.
- **Console de Teste (novo, persistente):** WhatsApp fake split-pane (sheet "Testar" no mobile); abas Conversa + **Bastidores** (regra/fonte/tool que disparou, args/retorno/latência); atribuição de fonte ("por que respondeu isso"); "testar como contato" (dados de exemplo vs reais); forçar branch (fora-do-horário/handoff); conversas-teste fora de relatórios.

---

## Plano por fases

**Fase 0 — Quick wins (1-2 dias, baixo risco):**
1. Remover submenu "Conexão LLM" + simplificar "AI Agents" → item único.
2. Fix Playbook: `DocumentViewerModal.vue` + ação "Ver documento" + handler (PDF via iframe do `display_url`).
3. Completar i18n pt_BR de `CAPTAIN.AGENT_TABS.*`.

**Fase 1 — Fundação iOS + Catálogo de Tools:** primitives iOS reutilizáveis (inset list, row+chevron, toggle 51x31, segmented, sheet c/ grabber) light+dark; catálogo de Tools (category no yml + migration + `ToolTile.vue` + busca + "Requer config" + drawer); padronizar cards + empty states.

**Fase 2 — Fluxo data-driven + Visão simples:** refatorar `useWorkflowBuilder` p/ computed do assistant; Visão Simples padrão; grafo técnico atrás de toggle; progressive disclosure.

**Fase 3 — Editar Assistant como onboarding + Console de Teste:** passos "treine como funcionário"; console persistente (Conversa+Bastidores); checklist de prontidão; Rascunho/Publicado; ativação em estágios.

**Fase 4 — Conhecimento avançado + Cenários + Overview analítico:** status/reprocessar/lacunas; cenários como procedimentos; KPI-herói + funil + CSAT; per-assistant tool scoping (`captain_assistant_tools`); extração de texto de PDF.

---

## Decisões abertas (gating)
1. **Consolidar rotas** `/captain` legacy → `/agents/:id` com tabs (com redirects)? Define o tamanho da refatoração.
2. **Onde mora a config LLM** após sair do sidebar: "Opções avançadas" por agente ou Configurações da conta?
3. **Tools por agente** (join `captain_assistant_tools`) agora ou manter account-scoped?
4. **Taxonomia de categorias** de tools — validar a proposta.
5. **Visão técnica** do fluxo fica pro leigo (atrás de toggle) ou só admin?
6. **Replay** usa conversas reais (privacidade) ou sandbox?
7. **PDF**: extrair texto agora (preview/chunks/busca) ou só viewer via iframe na Fase 0?
8. **Migration** status `failed` em `captain_documents` — ok adicionar?
9. **Escopo**: piloto Clara Tozi primeiro (viés imobiliário) ou genérico desde a Fase 1?
10. **Lottie**: padronizar ou migrar p/ ícones estáticos (iOS-like)?
