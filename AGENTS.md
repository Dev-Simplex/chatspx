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

## Ambientes por cliente (⚠️ leia ANTES de deployar)

O SPX serve **varios clientes** (contas/tenants) na mesma base. "Homologacao"/"producao" sao
**por cliente** — cada um tem sua VM. **A palavra "homologacao" sozinha e ambigua**: diga sempre
de qual cliente. Mapa canonico + helpers de deploy por cliente: **`scripts/ops/AMBIENTES.md`**.

- **Tozi** — HML: `192.168.8.232` (conta 3) → `scripts/ops/tozi-hml.sh` · 🔴 PROD: `3.82.215.109` (conta 6) → `scripts/ops/tozi-prod.sh`
- **Fabrica/Atacadao** — box unico `3.87.182.184` (fabrica.chatspx.app, contas 1/2) → `scripts/ops/fabrica.sh`

Cada helper imprime um banner CLIENTE · AMBIENTE · HOST — confira antes de rodar. Codigo por
cliente = namespace `Spx::Tozi::*` / `Spx::FabricaOculos::*` + config no banco da conta. Docs por
cliente em `docs/clientes/<cliente>/`; scripts operacionais em `scripts/spx/<cliente>/`.

## 🔒 Isolamento multi-cliente (nao-negociavel — evita o incidente Fabrica->Tozi)

> So o **CODIGO** (branch `producao`) replica pra todas as VMs. O **COMPORTAMENTO de cada IA**
> (prompt, persona, tom, conduta, modelo LLM) vive no **BANCO de cada conta** e **NAO** replica.

- **Conduta/persona especifica de um cliente -> SEMPRE no banco da conta** (`assistant.config['instructions']` / `behavior`, via o helper daquele cliente). **NUNCA** em codigo compartilhado — em especial `enterprise/lib/captain/prompts/assistant.liquid`, que e o **molde de TODOS os clientes**. Ja vazou 1x (conduta de oticas da Fabrica -> Tozi via a `.232`, revertida em `645b58ceb`).
- O `assistant.liquid` compartilhado so aceita conduta **agnostica** (nao narrar tool, `[IGNORAR]` no fechamento). Nada que nomeie cliente ou vertical (oticas/imoveis). Se precisar variar por cliente no template, gateie por conta lendo do banco — nao hardcode.
- **NAO existe auto-pull** (verificado 08/07 e 29/07 via Almirante `drift_check`): push na `homologacao` **nao desce ao vivo** pra `.232`. Codigo so entra numa VM por `propose_deploy_vm` + aprovacao humana. Mesmo assim, a `.232` tem clientes reais (contas 3/4/5) — pense "quem mais recebe isso?" antes de PROPOR o deploy. Fonte da verdade do fluxo: `docs/WORKFLOW-GIT-SPX.md`.
- **Antes de tocar IA de qualquer cliente: declare CLIENTE + CONTA + VM** e use o helper certo (confira o banner). Sessoes locais usam **worktree por cliente** em `chatspx-clientes/` (`tozi-prod` conta 6 · `tozi-hml` conta 3 · `fabrica` contas 1/2), cada um com `CLAUDE.local.md` fixando o alvo.
- Canal governado pra aplicar config-por-conta na VM certa, com aprovacao de dois: **ai-config-receptor + Almirante**.

## Almirante — control plane da frota (MCP)

> MCP `almirante` (`painel.chatspx.app/mcp`). Token na env de usuário `ALMIRANTE_TOKEN` — **sessão nova conecta sozinha**; se der `Failed to connect / Missing ALMIRANTE_TOKEN`, a sessão nasceu antes da variável (abra outra). Mapa completo das 50 tools: vault `Obsidian/aprendizados/almirante-mcp.md`.

**Use o Almirante no lugar de SSH** pra operar a frota SPX:
- **Saúde/ops:** `fleet_status`, `vm_health`, `service_status`/`service_logs`, `sidekiq_status`, `migration_status`, `drift_check`, `version_matrix`.
- **Git/entrega:** `git_diff` + GitHub (`gh_list_prs`/`gh_get_pr`/`gh_create_pr`/`gh_merge_pr`/`gh_comment`/issues/`gh_read_file`).
- **Deploy é SEMPRE propor→aprovar (nunca aplicar direto):** `dry_run` → `propose_deploy_vm/group/all` / `propose_merge` / `propose_migrate` / `propose_restart_*` / `propose_rollback` → `list_pending`/`request_status` → **aprovação humana** → `deploy_history`/`deploy_logs`. `freeze_deploys` congela a frota.
- **Config de IA por conta (jeito governado de aplicar a §Isolamento):** `ai_list_agents`/`ai_get_agent` → `ai_update_prompt`/`ai_update_behavior`/`ai_set_tool`/`ai_add_faq`/`ai_set_credential`, com `ai_history` + **`ai_rollback`**. Escreve no **banco da conta** (não no molde compartilhado). **Declare CLIENTE + CONTA + VM antes** e confira em `ai_get_agent`.

**⚠️ Limite:** o Almirante **NÃO lê conversas**. Análise comportamental (por que a IA não fez handoff, etc.) continua via **banco/eval nativo** do Chatwoot, não pelo Almirante.

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
- **Scrollbars**: TODAS as barras de rolagem seguem branding. Estilizadas globalmente em `app/javascript/dashboard/assets/scss/_wa-skin.scss` via vars `--wa-scrollbar-thumb*` (light + dark). Nao usar scrollbar default do browser; nao restilizar por componente — herda automaticamente. Para esconder em casos especificos, usar classe `.no-scrollbar`.

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

- **Esta regra e do upstream, NAO vale pra este fork.** No Chatwoot original so `en` e editado
  porque os outros idiomas vem de traducao comunitaria. Aqui a base de usuarios e brasileira e o
  produto e entregue em PT-BR: **feature nova edita `en` E `pt_BR`**, senao o time do cliente ve
  metade da tela em ingles. Os commits recentes fazem isso rotineiramente.
- Demais idiomas (es, fr, ...) continuam sendo da comunidade — nao traduzir.

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
- **CRITICO — Nunca `systemctl restart` em producao sem antes rodar `rails db:migrate:status`.** Migration pendente + restart = 500 em cadeia (PG::UndefinedColumn em queries que usam a coluna nova). Bomba latente pode ficar 7+ dias oculta porque codigo antigo em memoria nao a referencia. Ver vault: `01-Permanentes/Incidente - Pending Migration 24-abr-2026.md`. Para aplicar migration especifica pulando outras pendentes (ex: uma com orphan data), usar `db:migrate:up VERSION=YYYYMMDDHHMMSS` (nao `db:migrate VERSION=X` que aplica TODAS ate X).

### Armadilhas herdadas do merge da v4.16.2 (nao consertar — consertar piora)

- **Nao existe coluna `feature_flags_ext_2`.** A migration `20260706215758_add_feature_flags_ext_2_to_accounts.rb`
  se chama `ext_2` mas o corpo adiciona **`feature_flags_ext_1`** — bug do upstream, identico em
  `v4.16.2`. Ela e a UNICA migration que cria `ext_1`, e o schema fecha. `Featurable::FEATURE_FLAG_COLUMNS`
  conhece so `feature_flags` e `feature_flags_ext_1`. **Nao renomear a migration**: ela ja esta aplicada
  na frota, e renomear faz o Rails reexecuta-la e tentar criar `ext_1` de novo. Quem for adicionar
  `ext_2` de verdade: crie uma migration nova, nao confie no nome desta. (auditoria-enterprise §1.4 / C-22)
- **`quoted_email_reply` e flag MORTO e ainda ocupa um bit.** O upstream promoveu o recurso a GA e tirou
  o gate do `ReplyBox.vue`; o merge acompanhou. Mas a entrada continua em `config/features.yml`, o que
  faz o super admin exibir "desligado" enquanto o recurso esta ligado para todo canal de e-mail.
  **Nao remover a entrada**: tirar um flag do meio da lista remapeia o bit de todos os que vem depois,
  em toda a frota. Slot queimado e mais barato que remapear. (auditoria-dashboard A4-9)
- **CRÍTICO — timestamp de migration com SEGUNDOS REAIS, nunca hora redonda.** O timestamp **é** a
  versão da migration. Duplicado, o Rails levanta `DuplicateMigrationVersionError` e **nenhuma
  migration roda** — não só a duplicada. O deploy inteiro para.
  - **Como aconteceu (30/07/2026):** três frentes trabalhando em paralelo escolheram, cada uma por
    conta, horas redondas — `120000`, `120100`, `130000`, `130100`, `120200`. Três colidiram. Não
    foi azar: hora redonda é o número que todo mundo escolhe.
  - **Regra:** gere o timestamp de verdade — `date +%Y%m%d%H%M%S` — e **não arredonde**. Dois
    segundos reais não colidem.
  - **Antes de escolher, olhe a branch de integração, não a sua worktree:**
    `git ls-tree origin/homologacao db/migrate/ --name-only | sort | tail`. Worktree de frente
    costuma estar atrás e **não enxerga** as migrations das outras frentes.
  - Coluna que outra frente pode ter tocado em banco de teste: `add_column ... if_not_exists: true`
    transforma um aborto de lote num no-op.

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

## Trocar entre branches (feature <-> homologacao)

Script pronto em `~/switch-branch.sh` para trocar de branch e recompilar assets automaticamente:

```bash
~/switch-branch.sh feature/agentes-ia   # trabalhar na feature
~/switch-branch.sh homologacao          # voltar para homologacao
```

O script faz:
- Stasha alteracoes locais nao commitadas (seguro, nada e perdido)
- `git checkout` da branch alvo
- `git pull --ff-only` se tiver upstream
- `RAILS_ENV=production bundle exec rails assets:precompile`
- Mostra comando de restart ao final

Depois do script, **reiniciar os servicos** para servir os novos assets:
```bash
sudo systemctl restart chatwoot-web.1 chatwoot-worker.1
```

**Branches feature parqueadas (nao em homologacao/producao):**
- `feature/agentes-ia` — redesign completo Agentes IA (Captain -> AI Agents)

Para mergear uma feature de volta em homologacao quando estiver pronta:
```bash
~/switch-branch.sh homologacao
git merge feature/agentes-ia
git push origin homologacao
# recompilar + restart
```

# Ao compactar, preservar:
# - Plano de implementacao atual
# - Lista de arquivos modificados
# - Resultado dos testes e erros nao resolvidos
# - Estado do Enterprise overlay

## Timezone: America/Cuiaba
## Linguagem: Portugues (Brasil)
