# Chat SPX — Simplex Solucoes

Fork do Chatwoot mantido pela Simplex. Produto SaaS proprio com branding e modulos customizados.

## Cerebro

Voce tem um cerebro persistente com TUDO sobre este projeto.
**Vault:** `/home/chatwoot/vault`
**Nota do projeto:** `01-Permanentes/Chat SPX.md` — ambientes, credenciais, deploy, .env
**Engineering:** `02-MOCs/ROUTER - Engineering.md` — padroes e workflows
**Consultar ANTES de agir.** Credenciais, servidores, procedures — tudo esta no vault.

## Contexto

- Cliente: Simplex Solucoes (produto proprio)
- Tipo: **Build-to-Earn** (producao, clientes reais — NÃO experimentar libs/arquiteturas novas aqui)
- Repo: Dev-Simplex/chatspx (branch `producao`)
- Producao: https://chat.simplexsolucoes.com.br (192.168.8.229)
- Homologacao: https://hmlchat.simplexsolucoes.com.br (192.168.8.232)
- SaaS: https://chatspx.app (Proxmox)

## Stack Tecnica

| Camada | Tecnologia | Versao |
|--------|-----------|--------|
| Backend | Ruby on Rails | ver .ruby-version |
| Frontend | Vue 3 (Composition API) | Vite |
| Banco | PostgreSQL | chatwoot_production |
| Cache | Redis | localhost:6379 |
| Styling | Tailwind CSS | ver tailwind.config.js |
| WhatsApp | WAHA API | waha.simplexsolucoes.com.br |

## Comandos do Projeto

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f Procfile.dev`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Test Ruby (linha)**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Seed Local**: `bundle exec rails db:seed`
- **Seed Search Data**: `bundle exec rails search:setup_test_data`
- **Seed Account (rico)**: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"`
- **Ruby Version**: `rbenv install $(cat .ruby-version)` — sempre `eval "$(rbenv init -)"` antes de bundle/rspec
- Sempre usar `bundle exec` para Ruby CLI tasks

## Code Style

- **Ruby**: RuboCop (150 char max line length), compact `module/class` definitions (nao nested)
- **Vue/JS**: ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: PascalCase, Composition API com `<script setup>` no topo
- **Events**: camelCase
- **I18n**: Sem strings hardcoded em templates — usar i18n
- **Error Handling**: Custom exceptions em `lib/custom_exceptions/`
- **Models**: Validate presence/uniqueness, indexes adequados
- **Type Safety**: PropTypes em Vue, strong params em Rails

## Styling

- **Tailwind Only** — SEM excecoes:
  - Nao escrever CSS customizado
  - Nao usar scoped CSS
  - Nao usar inline styles
  - Sempre usar Tailwind utility classes
- **Colors**: ver `tailwind.config.js`

## Regras de Arquitetura

- MVP focus: menor mudanca de codigo, happy-path first
- Sem defensive programming desnecessario — so o que producao provou ser necessario
- Codigo minimal e legivel > abstracoes elaboradas
- Remover codigo morto/inalcancavel/nao-usado
- Nao escrever multiplas versoes da mesma logica — escolher a melhor e implementar
- Nao escrever specs a menos que explicitamente pedido
- Iterar apos confirmacao

## Enterprise Edition

Chatwoot tem overlay Enterprise em `enterprise/` que extende/sobrescreve codigo OSS.

**IMPORTANTE — checklist para qualquer mudanca em logica core ou APIs:**
- Buscar arquivos relacionados em AMBAS as arvores antes de editar: `rg -n "FooService|ControllerName" app enterprise`
- Novos endpoints/services/models: considerar se Enterprise precisa override ou extension point
- Nao hardcodar comportamento de instancia/plano no OSS — preferir config, feature flags, extension points
- Manter contratos request/response estaveis entre OSS e Enterprise
- Ao renomear/mover codigo compartilhado, espelhar a mudanca em `enterprise/`
- Specs Enterprise em `spec/enterprise`, espelhando layout OSS
- Para comportamento Enterprise-only em features OSS existentes: usar `prepend_mod_with`/`include_mod_with` — NAO editar OSS direto
- Features exclusivas Enterprise: colocar direto em `enterprise/`
- Docs: https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

## Branding / White-labeling

- Strings user-facing com "Chatwoot": usar `replaceInstallationName` de `shared/composables/useBranding`
- Nunca hardcodar nome de marca

## Translations

- Apenas editar `en.yml` (backend) e `en.json` (frontend)
- Outros idiomas sao mantidos pela comunidade

## Frontend

- Usar `components-next/` para message bubbles (o resto esta sendo deprecated)

## Codex Worktree Workflow

- Worktree + branch separado por task para isolar mudancas
- Setup Codex-specific em `.codex/`, processo via `Procfile.worktree`
- `.codex/environments/environment.toml` gera DB/port/Redis DB index dinamicos por worktree
- Cada worktree com seu proprio Overmind socket/title

## Specs (testes)

- Preferir `with_modified_env` (spec helpers) ao inves de stub em `ENV`
- Em specs com parallel/reloading: comparar `error.class.name` ao inves de igualdade de constante

## Hurdles Conhecidos

- Enterprise overlay em `enterprise/` — SEMPRE verificar ambas as arvores antes de editar
- Branding: usar `replaceInstallationName`, nunca hardcodar "Chatwoot"
- Branch `producao` (nao `main`) — deploy script aponta para esta branch
- .env de producao tem TZ=America/Manaus (nao Cuiaba)
- Seeds: `db:seed` para dev rapido, `AccountSeeder` para dados ricos
- rbenv: sempre inicializar antes de qualquer comando Ruby

## Commit Messages

- Conventional Commits: `tipo(escopo): descricao`
- Exemplo: `feat(auth): add user authentication`
- Nao referenciar Claude em commits

## PR Description Format

- Paragrafo curto user-facing descrevendo a mudanca
- `Closes` com links de issues
- Feature PRs: `How to test` (product/UX)
- Bugfix PRs: `How to reproduce`
- Opcional: `What changed` para highlights de implementacao
- NAO adicionar `How this was tested` listando specs/comandos

## Checklist Pos-Implementacao

- [ ] `bundle exec rspec` passando nos specs afetados
- [ ] `pnpm eslint` sem erros
- [ ] `bundle exec rubocop -a` sem offenses
- [ ] Verificou `enterprise/` para arquivos relacionados
- [ ] Apenas `en.yml`/`en.json` editados (outros idiomas = comunidade)
- [ ] CLAUDE.md atualizado se descobriu novo pitfall

## Modulo Agentes IA (Captain v2)

Modulo de agentes IA que substitui o n8n. Configuracao code-first (Claude Code configura via API, frontend e viewer).

### Mapa de Arquivos

| Area | Path | Descricao |
|------|------|-----------|
| **Frontend Pages** | `app/javascript/dashboard/routes/dashboard/agents/` | Pages: AgentsPageView, AgentsDashboard, AgentDetailView, LLMSettingsPage |
| **Frontend Tabs** | `app/javascript/dashboard/components-next/agents/tabs/` | 8 tabs: Overview, Behavior, Knowledge, Tools, Scenarios, Inboxes, Logs, Settings |
| **Frontend Shared** | `app/javascript/dashboard/components-next/agents/` | AgentCard, StatsCard, LottieIcon, AgentStatusBadge |
| **Behavior Configs** | `app/javascript/dashboard/components-next/agents/behavior/` | RouterConfig, DebounceConfig, BusinessHoursConfig, etc. |
| **Workflow Visual** | `app/javascript/dashboard/components-next/agents/workflow/` | AgentWorkflow (vue-flow), WorkflowNode, useWorkflowBuilder |
| **Copilot** | `app/javascript/dashboard/components-next/copilot/` | CopilotPanel, CopilotToolCard, CopilotAvatar |
| **Routes** | `app/javascript/dashboard/routes/dashboard/agents/agents.routes.js` | Todas as rotas do modulo |
| **Backend Tools** | `enterprise/app/services/captain/tools/copilot/` | 30 copilot tools (send_message, resolve_conversation, etc.) |
| **Behavior Services** | `enterprise/app/services/captain/behavior/` | router, debounce, business_hours, humanizer, dedup, copilot_trigger |
| **Assistant Model** | `enterprise/app/models/captain/assistant.rb` | Model com behavior JSONB + config |
| **Lottie Icons** | `app/javascript/dashboard/assets/lottie/useanimations/` | 27 animacoes JSON do useAnimations.com |
| **i18n** | `locale/en/settings.json` e `integrations.json` | Keys: AGENTS_PAGE, AGENTS_DASHBOARD, AGENT_DETAIL, CAPTAIN.AGENT_TABS |
| **Spec Clara Tozi** | `TOZI-AGENT-SPEC.md` (raiz) | Especificacao completa do agente Clara para Tozi Imobiliaria |

### Design System

- Design guide completo no vault: `vault/01-Permanentes/Padrao Design System SaaS Completo.md`
- Inspirado em n8n, Linear, Cal.com, PostHog, Vercel (14 pesquisas, 200+ fontes)
- Tokens: `bg-n-solid-1/2/3`, `text-n-slate-10/11/12`, `border-n-weak`, `bg-n-brand`
- Dark mode obrigatorio em TUDO: `bg-white dark:bg-n-solid-2`
- Icones animados: `lottie-web` + useAnimations, hover-only, `dark:invert`
- NUNCA `hover:scale` — usar `transition-shadow hover:shadow-md`

### Filosofia Code-First

- O Claude Code configura agentes via API (PUT /captain/assistants/:id)
- O frontend e um VIEWER (mostra estado, JSON viewers com copy-to-clipboard)
- SettingsTab e read-only — nao tem formularios de edicao
- ToolsTab mostra 32 copilot tools (sistema) + custom tools + MCP config template
- Workflow visual mostra APENAS nodes habilitados no behavior (nao fakes)

### Backend: Behavior JSONB

O campo `behavior` no assistant e um JSONB livre. Estrutura:
```json
{
  "debounce_seconds": 15,
  "router": { "enabled": true, "skip_labels": [], "skip_agent_bot": true },
  "business_hours": { "enabled": false },
  "humanizer": { "enabled": false, "max_chars": 300 },
  "dedup": { "enabled": false, "ttl_seconds": 60 },
  "copilot_trigger": { "enabled": false, "hashtag": "#copilot" },
  "media_pipeline": { "enabled": false }
}
```

### Pre-commit Hook

O projeto tem lint-staged no pre-commit. Se falhar por erros PRE-EXISTENTES em arquivos que voce nao tocou (ex: Sidebar.vue, Copilot.vue), usar `--no-verify` e anotar.

## Historico de Decisoes

- 2026-04-07: Modulo Agentes IA criado (141 arquivos, 8596 linhas)
- 2026-04-07: Design system compilado de 14 pesquisas paralelas (n8n, Linear, Cal.com, etc.)
- 2026-04-07: Filosofia code-first adotada (frontend = viewer, Claude Code = configurador)
- 2026-04-07: 30 copilot tools backend implementadas
- 2026-04-07: Lottie icons (useAnimations) integrados com lottie-web

# Ao compactar, preservar:
# - Plano de implementacao atual
# - Lista de arquivos modificados
# - Resultado dos testes e erros nao resolvidos
# - Estado do Enterprise overlay

## Timezone: America/Cuiaba
## Linguagem: Portugues (Brasil)
