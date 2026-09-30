# Chat SPX: guia curto de desenvolvimento

Leia este arquivo antes de alterar o projeto. Ele resume o que foi confirmado neste checkout. O `AGENTS.md` contém as regras detalhadas de trabalho.

## O produto e a base de código

O Chat SPX é um fork do Chatwoot mantido pela Simplex. A maior parte da base continua organizada como o upstream em `app/`, `config/`, `db/` e `spec/`. As extensões Enterprise ficam em `enterprise/`; o mecanismo que injeta módulos `Enterprise::*` por `prepend_mod_with` e `include_mod_with` está em `config/initializers/01_inject_enterprise_edition_module.rb`. Ao mudar lógica core ou API, procure a implementação nas duas árvores antes de editar.

As customizações próprias não ficam em um único diretório. Use este mapa para localizar os módulos confirmados:

| Área | Onde começar |
|---|---|
| Código SPX no backend | `app/controllers/spx/`, `app/models/spx/`, `app/services/spx/`, `app/jobs/spx/`, `app/listeners/spx/` e `lib/tasks/spx_*.rake` |
| Agentes IA e Captain v2 | Rotas em `app/javascript/dashboard/routes/dashboard/agents/`, UI em `app/javascript/dashboard/components-next/agents/`, modelo em `enterprise/app/models/captain/assistant.rb` e serviços em `enterprise/app/services/captain/` |
| Distribuição e rodízio por time | `app/models/spx/distribuicao/`, `app/services/spx/distribuicao/`, `app/jobs/spx/distribuicao/`, `app/listeners/spx/distribuicao/`, API em `app/controllers/api/v1/accounts/teams/distribuicao_controller.rb` e UI em `app/javascript/dashboard/routes/dashboard/settings/teams/` |
| Unidades | `app/models/unit.rb`, `app/controllers/api/v1/accounts/units_controller.rb`, `app/services/units/` e `app/javascript/dashboard/routes/dashboard/settings/units/` |
| Motor de flows | Modelo em `app/models/flow.rb`, execução em `app/services/flows/` e canvas em `app/javascript/dashboard/routes/dashboard/settings/automation/canvas/` |
| Isolamento por time e agente | `app/models/concerns/inbox_isolation_scope.rb`, `app/services/team_message_isolation.rb`, `app/services/agent_message_isolation.rb`, `app/services/agent_conversation_isolation.rb` e `app/finders/message_finder.rb` |
| NPS | `app/models/nps_response.rb`, `app/services/nps_survey_service.rb`, `app/builders/nps_surveys/`, `app/controllers/api/v1/accounts/nps_responses_controller.rb` e telas `NetPromoterScore*` em `app/javascript/dashboard/routes/dashboard/settings/` |
| WhatsApp oficial | `app/models/channel/whatsapp.rb` e `app/services/whatsapp/providers/whatsapp_cloud_service.rb` |
| WAHA | `app/services/waha/`, `app/jobs/waha/`, `app/controllers/webhooks/waha_controller.rb` e `app/javascript/dashboard/routes/dashboard/settings/wahaConnections/` |

O motor de flows persiste o grafo em `flows.definition` e o executa por `Flows::RunnerService`; o vocabulário de ações está em `app/models/flow.rb`. A distribuição SPX usa política, estado e logs próprios e pode ser acionada por flows por meio de `app/services/flows/distribuicao_action.rb`. As três regras de isolamento são configuradas por caixa de entrada, com escopo opcional por time, conforme `app/models/concerns/inbox_isolation_scope.rb`.

## Stack confirmada

| Camada | Versão ou evidência |
|---|---|
| Ruby | 3.4.4 em `.ruby-version` |
| Rails | 7.1.5.2 em `Gemfile.lock`; restrição `~> 7.1` em `Gemfile` |
| Vue | `^3.5.12` em `package.json` |
| Vite | `^5.4.21`, fixado em 5.4.21 pelo override de `package.json` |
| Tailwind CSS | `^3.4.19` em `package.json` |
| PostgreSQL | Adaptador `pg` 1.5.3 em `Gemfile.lock`; a versão do servidor não está fixada no repo |
| pgvector | Gem `pgvector` 0.1.1 e extensão `vector` habilitada em `db/schema.rb` |
| Redis | Cliente Ruby 5.0.6 em `Gemfile.lock`; a versão do servidor não está fixada no repo |
| Sidekiq | 7.3.1 em `Gemfile.lock`, configurado por `config/sidekiq.yml` |
| Node e pnpm | Node 24.x, pnpm 10.x e package manager pnpm 10.2.0 em `package.json` |

## Mapa de pastas para o dia a dia

- `app/controllers/`, `app/models/`, `app/services/`, `app/jobs/`, `app/listeners/`: backend Rails.
- `app/javascript/dashboard/routes/`: páginas e rotas do dashboard.
- `app/javascript/dashboard/components-next/`: componentes atuais de UI, inclusive as bolhas de mensagem.
- `app/javascript/dashboard/api/`, `store/` e `composables/`: acesso à API, estado e lógica reutilizável do front.
- `app/javascript/dashboard/i18n/locale/`: traduções do dashboard.
- `config/routes.rb`, `config/schedule.yml` e `config/sidekiq.yml`: rotas, tarefas recorrentes e filas.
- `db/migrate/` e `db/schema.rb`: evolução e estado do banco.
- `enterprise/`: implementação e overlays Enterprise. Sempre verificar junto com `app/`.
- `spec/` e arquivos `*.spec.js`: testes Ruby e front.
- `deployment/`: units do systemd e scripts de instalação. Não trate isso como autorização para operar outra VM.
- `docs/`: especificações, tarefas, decisões e runbooks versionados.

## Convenções de implementação

### Frontend e visual

Para UI nova, reutilize o design system e os componentes de `app/javascript/dashboard/components-next/`. Para message bubbles, `components-next/` é obrigatório. Os tokens mais usados estão nas classes `bg-n-solid-*`, `text-n-slate-*`, `border-n-weak` e `bg-n-brand`; confira `tailwind.config.js` e os componentes existentes. Toda tela deve funcionar nos temas claro e escuro.

Use somente utilitários Tailwind no componente. Não acrescente CSS customizado, `<style scoped>` nem estilo inline. As barras de rolagem recebem o branding global em `app/javascript/dashboard/assets/scss/_wa-skin.scss`; não crie uma aparência local para elas. Não use `hover:scale`.

Não deixe texto visível hardcoded no template. Adicione a chave em inglês e em português do Brasil, normalmente sob `app/javascript/dashboard/i18n/locale/en/` e `app/javascript/dashboard/i18n/locale/pt_BR/`. Não altere os demais idiomas. Ao exibir o nome do produto, use `replaceInstallationName` de `shared/composables/useBranding` em vez de hardcodar a marca base.

### Rails, Enterprise e banco

Ruby segue RuboCop, com limite de 150 caracteres por linha. Use `bundle exec` em toda CLI Ruby. Antes de uma mudança core ou de API, procure os símbolos relacionados em `app` e `enterprise`. Preserve contratos entre as duas árvores; comportamento somente Enterprise deve usar os pontos de extensão do overlay.

Migration nova deve usar segundos reais:

```bash
date +%Y%m%d%H%M%S
git ls-tree -r --name-only origin/producao -- db/migrate | sort | tail
```

Não arredonde o horário. Timestamp duplicado gera `DuplicateMigrationVersionError` e bloqueia todas as migrations. Quando outra frente puder já ter criado a coluna no banco de desenvolvimento, avalie `if_not_exists: true` conforme a mudança concreta, sem usá-lo por padrão.

### Commits e pull requests

Use Conventional Commits, por exemplo `fix(teams): corrige layout do assistente`. Não mencione ferramentas de IA na mensagem.

A descrição do PR começa com um parágrafo curto voltado ao usuário, inclui `Closes` com os links das issues e usa `How to test` para feature ou `How to reproduce` para bugfix. `What changed` é opcional. Não crie uma seção `How this was tested` listando comandos.

## Executar um teste isolado

Na VM de desenvolvimento, o Ruby do projeto (3.4.4) vem do RVM e já carrega em qualquer terminal. Se `ruby -v` responder 3.2.3, é o Ruby do sistema: rode `source /etc/profile.d/rvm.sh` antes.

```bash
bundle exec rspec spec/services/spx/distribuicao/distribuir_service_fila_spec.rb
```

Para um arquivo de front, o script `test` de `package.json` chama o Vitest sem watch:

```bash
pnpm test app/javascript/dashboard/routes/dashboard/settings/teams/specs/TeamForm.spec.js
```

Também existem `pnpm test:watch`, `pnpm eslint` e `bundle exec rubocop -a`. Rode apenas o alvo proporcional à mudança.

## Ver a mudança na VM de desenvolvimento

Estes comandos são somente para a VM de desenvolvimento do Thalysson. Nunca os execute em produção ou em VM de cliente.

O systemd inicia Rails e Sidekiq com `RAILS_ENV=production` e `WorkingDirectory=/home/chatwoot/chatwoot`, conforme `deployment/chatwoot-web.1.service` e `deployment/chatwoot-worker.1.service`. Portanto, antes de validar, a revisão a testar precisa estar nesse checkout, na branch `thalysson`. Um restart feito enquanto a alteração existe apenas em outra worktree do Orca não muda o código servido.

Traga o trabalho da worktree para o checkout principal e confira o alvo antes de qualquer comando:

```bash
cd /home/chatwoot/chatwoot
git branch --show-current          # tem que ser thalysson
git merge <branch-da-worktree>
git status --short
```

Para mudança de frontend, gere os assets com 12288 MB de memória, confira migrations e reinicie somente o target da VM de desenvolvimento. Com 4096, valor que ainda aparece em `deployment/setup_spx_24.04.sh`, o build do front estoura memória. Se o build falhar no meio, o app continua servindo o front anterior; confira a saída do comando, não só o fim do log.

```bash
NODE_OPTIONS=--max-old-space-size=12288 RAILS_ENV=production bundle exec rake assets:precompile
RAILS_ENV=production bundle exec rails db:migrate:status
sudo systemctl restart chatwoot.target
systemctl status chatwoot-web.1 chatwoot-worker.1 --no-pager
```

Para mudança apenas de backend, não há build de frontend. Se a tarefa inclui migration, aplique-a primeiro no banco da VM de desenvolvimento. Em todos os casos, confirme que não há migration pendente antes do restart:

```bash
RAILS_ENV=production bundle exec rails db:migrate
RAILS_ENV=production bundle exec rails db:migrate:status
sudo systemctl restart chatwoot.target
systemctl status chatwoot-web.1 chatwoot-worker.1 --no-pager
```

Se não houve migration, pule somente `db:migrate`, nunca a conferência `db:migrate:status`. O `Procfile.dev` também define Rails, Sidekiq e Vite, e `pnpm dev` o inicia; porém ele usa Rails na porta 3000 e pressupõe que o ambiente de desenvolvimento esteja preparado. Este checkout não contém `Procfile.worktree` nem `.codex/environments/environment.toml`, apesar da referência no `AGENTS.md`, então o caminho confirmado para esta VM é o build de produção servido pelo systemd.

## Fluxo Git do Thalysson

Trabalhe em worktree separada por tarefa, criada pelo Orca, e confirme o caminho e a branch antes de editar. A linha de trabalho do Thalysson é `thalysson`; a entrega segue por PR de `thalysson` para `producao`. Não commite diretamente em `producao`, não use `main` ou `master` como destino e não faça deploy. O processo geral de worktrees está documentado em `docs/ORQUESTRACAO-ORCA.md`; o fluxo compartilhado do repo está em `docs/WORKFLOW-GIT-SPX.md`.

## Armadilhas que evitam retrabalho

- Uma implementação pode existir em `app/` e ter extensão ou override em `enterprise/`. Pesquise as duas árvores.
- O produto é white-label. Não hardcode “Chatwoot” nem outro nome em texto visível.
- Para este fork, feature nova traduz `en` e `pt_BR`. A regra upstream de editar somente inglês não vale aqui.
- Use `components-next/` para bolhas de mensagem e preserve tema escuro em toda UI nova.
- Use Tailwind. Não resolva um problema local criando CSS ou scrollbar por componente.
- A branch de integração e produção é `producao`, não `main` nem `master`.
- Sempre use `bundle exec`. Na VM de desenvolvimento o Ruby vem do RVM (`/usr/local/rvm`); o `AGENTS.md` também fala de rbenv, que vale para outras máquinas. Se `ruby -v` mostrar 3.2.3, carregue o RVM com `source /etc/profile.d/rvm.sh`.
- Nunca reinicie uma instância com migration pendente. Na VM de desenvolvimento, rode `RAILS_ENV=production bundle exec rails db:migrate:status` antes de reiniciar o target.
- Em migration, use timestamp real com segundos e confira as migrations já existentes na branch alvo.
- Alteração de frontend no app servido pelo systemd só aparece depois de `assets:precompile` e restart na VM de desenvolvimento.
