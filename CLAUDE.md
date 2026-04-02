# Chatwoot Development Guidelines


## Linguagem: Portugues (Brasil)
## Timezone: America/Cuiaba

## Base de Conhecimento Obsidian (CONSULTAR AUTOMATICAMENTE)

Existe um vault Obsidian com TODA a documentacao da empresa Simplex Solucoes.

**Vault:** `vault/`
**Entry point:** `vault/02-MOCs/MOC - Home.md`

### Quando consultar (SEM o usuario pedir):

- Credencial, senha, SSH, URL, API key, token -> `vault/02-MOCs/MOC - Credenciais e Acessos.md`
- Algo quebrado ou com erro -> `vault/02-MOCs/ROUTER - Resolucao de Problemas.md`
- Executar procedimento (deploy, sync, etc.) -> `vault/02-MOCs/ROUTER - Operacoes.md`
- Trabalho para cliente especifico -> `vault/02-MOCs/ROUTER - Clientes.md`
- Infraestrutura, servidores, Docker -> `vault/02-MOCs/MOC - Infraestrutura.md`
- Workflows n8n -> `vault/02-MOCs/MOC - n8n Automacoes.md`
- Monday.com -> `vault/02-MOCs/MOC - Monday.md`

### Como acessar:

1. Ler direto do filesystem: `vault/`
2. Seguir wikilinks `[[]]` para navegar ate a informacao

MUST: Consultar o vault ANTES de pedir informacoes ao usuario.
MUST: Seguir os wikilinks das notas para chegar na informacao.
MUST NOT: Adivinhar credenciais ou URLs -- sempre buscar no vault.

---

## Escrita Automatica no Vault (WRITE-BACK)

O vault e uma rede neural que CRESCE organicamente. Sempre que aprender algo novo durante o trabalho, registre no vault seguindo as regras abaixo.

### Principios Zettelkasten (seguir SEMPRE)

1. **Atomicidade** -- Uma nota = uma ideia/fix/procedimento. Se precisa de "e tambem..." -> dividir em notas separadas. Tamanho ideal: 5-20 linhas de conteudo (sem frontmatter). Se o titulo nao descreve 100% do conteudo, a nota nao e atomica.
2. **Conectividade** -- Links sao o esqueleto da rede. Toda nota DEVE ter no minimo 1 link para MOC + 1 link para nota relacionada. Links bidirecional: se A linka para B, verificar se B deveria linkar para A.
3. **Estrutura emergente** -- MOCs sao indices, nao hierarquias. Crescem por append. Tags sao para busca; links sao para navegacao.
4. **Densidade > Volume** -- Uma nota com 3 links corretos vale mais que 10 notas sem links. Nao criar notas so por criar.

### Melhores praticas para rede neural do Claude

1. **Busca obrigatoria antes de criar** -- Grep por titulo E por palavras-chave do conteudo. Duplicata e o pior erro possivel.
2. **Frontmatter como metadata** -- `source: claude-code` permite auditoria. `atualizado:` permite rastrear frescor da informacao.
3. **Append com atribuicao** -- Ao editar nota existente, marcar com `**[claude-code YYYY-MM-DD]**` para distinguir de conteudo humano.
4. **Limite por sessao** -- Maximo 3 notas novas por conversa. Mais que isso indica falta de atomicidade ou flood.
5. **Links semanticos** -- Nao usar "veja tambem". Usar contexto: "resolve [[Bug X]]", "depende de [[Servidor Y]]", "usado por [[CLI - Z]]".

### Estrutura de pastas do vault (referencia)

```
00-Inbox/          -- Buffer temporario para notas que nao se encaixam
01-Permanentes/    -- Notas permanentes (Fix, Config, Padrao, servidores, produtos)
02-MOCs/           -- MOCs e Routers (indices -- nao criar novos)
03-Projetos/       -- Projetos por cliente (subpastas por cliente: Alternativo/, ChatSPX/, etc.)
04-Runbooks/       -- Procedimentos operacionais (RB - ...)
05-Clientes/       -- Fichas de clientes (CLI - ...)
06-Daily/          -- Notas diarias (opcional)
07-Templates/      -- Templates Obsidian (nao editar)
08-Arquivos/       -- Anexos e arquivos estaticos (PDFs, imagens)
99-Arquivo/        -- Notas arquivadas/inativas
```

### Criacao de pastas

A IA PODE criar subpastas dentro de `vault/03-Projetos/NomeCliente/` para projetos de clientes novos.
A IA NAO deve criar pastas na raiz do vault nem subpastas em `vault/01-Permanentes/`.

### Quando escrever (gatilhos automaticos)

| Gatilho | Acao | Destino |
|---------|------|---------|
| Bug resolvido com causa nao obvia | Criar nota permanente com causa raiz e solucao | `vault/01-Permanentes/` |
| Credencial nova ou alterada | Atualizar nota existente | Nota da credencial |
| Procedimento novo descoberto | Criar runbook | `vault/04-Runbooks/` |
| Integracao nova configurada | Criar nota permanente | `vault/01-Permanentes/` |
| Informacao de cliente atualizada | Atualizar nota do cliente | `vault/05-Clientes/` |
| Servidor/porta/IP novo | Atualizar nota do servidor | `vault/01-Permanentes/` |
| Workflow n8n criado/modificado | Atualizar MOC n8n ou nota do cliente | Nota existente |
| Padrao tecnico recorrente | Criar nota permanente | `vault/01-Permanentes/` |

### Onde escrever (IA faz tudo -- zero intervencao humana)

| Tipo de nota | Pasta destino | Quando |
|-------------|---------------|--------|
| Fix de bug | `vault/01-Permanentes/` | Prefixo `Fix - ` |
| Configuracao de infra | `vault/01-Permanentes/` | Prefixo `Config - ` |
| Padrao tecnico | `vault/01-Permanentes/` | Prefixo `Padrao ` |
| Runbook/procedimento | `vault/04-Runbooks/` | Prefixo `RB - ` |
| Informacao de cliente | `vault/05-Clientes/` | Prefixo `CLI - ` |
| Projeto novo | `vault/03-Projetos/` | Prefixo `PROJ - ` |
| Nota EXISTENTE | Editar in-place | Append ao final da secao relevante |
| MOCs | Editar in-place | Apenas ADICIONAR links, NUNCA remover |

### Como escrever -- Regras de Seguranca

```
MUST: Grep no vault antes de criar (titulo + palavras-chave do conteudo)
MUST: Usar frontmatter com source: claude-code em notas novas
MUST: Seguir templates de `vault/07-Templates/` para o tipo de nota
MUST: Manter atomicidade -- UMA ideia por nota
MUST: Minimo 2 wikilinks [[]] por nota (1 MOC + 1 relacionada)
MUST: Atualizar campo `atualizado:` com data atual ao editar nota existente
MUST: Adicionar link na MOC relevante ao criar nota nova
MUST: Links bidirecionais -- se A linka B, verificar se B deveria linkar A
MUST: Marcar appends com **[claude-code YYYY-MM-DD]** para atribuicao

MUST NOT: Deletar ou reescrever conteudo escrito por humanos
MUST NOT: Editar frontmatter criado por humanos (exceto `atualizado:`)
MUST NOT: Remover links de MOCs
MUST NOT: Criar nota sem antes verificar se ja existe uma sobre o mesmo tema
MUST NOT: Criar mais que 3 notas novas por conversa
MUST NOT: Criar arquivos de template ou MOC novos
MUST NOT: Criar notas sem links (nota sem links = arquivo morto)
```

### Frontmatter para notas novas

```yaml
---
tipo: permanente | runbook | cliente | projeto
tags: [area/subtema]
criado: YYYY-MM-DD
atualizado: YYYY-MM-DD
quando_usar: Descricao curta de quando esta nota e relevante
source: claude-code
---
```

### Padrao de nomes de arquivo

- Fix de bug: `Fix - Nome Descritivo.md`
- Configuracao: `Config - Nome Descritivo.md`
- Padrao tecnico: `Padrao Nome.md`
- Runbook: `RB - Nome do Procedimento.md`
- Cliente: `CLI - Nome do Cliente.md`
- Projeto: `PROJ - Nome do Projeto.md`

### Exemplo de nota de bug fix

```markdown
---
tipo: permanente
tags: [infra/coolify, fix/database]
criado: 2026-04-01
atualizado: 2026-04-01
quando_usar: Servico no Coolify nao conecta ao banco pelo IP externo
source: claude-code
---

# Fix - DATABASE_URL Coolify Hostname Interno

## Problema
Backend retornava 500 em todas as rotas. PostgreSQL inacessivel pelo IP externo.

## Causa Raiz
DATABASE_URL apontava para `192.168.8.129:5432` (IP da rede local).
Dentro do Coolify, servicos se comunicam pelo hostname interno do container.

## Solucao
Alterar DATABASE_URL para usar o hostname interno do Coolify:
`postgresql://postgres:SENHA@bkkcsso8s4s8w4o8kcw4gggs:5432/postgres`

## Notas Relacionadas
- [[MOC - Infraestrutura]]
- [[MOC - Credenciais e Acessos]]
```

### Exemplo de append em nota existente

```markdown
## Secao Existente
- item existente 1
- item existente 2
- **[claude-code 2026-04-01]** Novo item descoberto durante trabalho
```

### Fluxo de decisao antes de escrever

```
1. Descobri algo novo durante o trabalho?
   NAO -> nao escrever
   SIM -> continuar

2. Ja existe nota sobre isso no vault?
   SIM -> append na nota existente (manter conteudo humano)
   NAO -> continuar

3. E atomico? (uma unica ideia/procedimento/fix)
   NAO -> dividir em multiplas notas
   SIM -> continuar

4. Ja criei 3+ notas nesta conversa?
   SIM -> parar (limite de qualidade)
   NAO -> criar na pasta correta conforme tabela

5. Adicionar links:
   Minimo 1 MOC + 1 nota relacionada
   Verificar se notas linkadas deveriam linkar de volta
   Adicionar link na MOC relevante
```

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

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
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - Only update `en.yml` and `en.json`
  - Other languages are handled by the community
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.
