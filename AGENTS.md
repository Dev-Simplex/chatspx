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
- SaaS: https://chat.chatspx.com.br (VPS Hostinger)

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

## Historico de Decisoes

[Preencher durante desenvolvimento]

# Ao compactar, preservar:
# - Plano de implementacao atual
# - Lista de arquivos modificados
# - Resultado dos testes e erros nao resolvidos
# - Estado do Enterprise overlay

## Timezone: America/Cuiaba
## Linguagem: Portugues (Brasil)
