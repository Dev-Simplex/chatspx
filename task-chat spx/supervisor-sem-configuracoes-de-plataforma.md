# Supervisor sem as configurações de plataforma

**Nível:** pleno · **Risco:** médio — mexe em permissão, e permissão erra para o lado de liberar
**Onde validar:** staging (`nicolas.chatspx.app`) antes da frota
**Executar por partes:** cada parte abaixo fecha sozinha e tem prova própria. Não pule a Parte 2.

---

## Por que esta task existe

Hoje quem supervisiona time no ChatSPX enxerga **mais do que precisa**. Medido na conta #1:

| usuário | papel na conta | tipo na instalação | supervisiona |
|---|---|---|---|
| Walisson `sup@simplexsolucoes.com.br` (id 14) | **administrator** | **SuperAdmin** | sim |
| NICOLAS `nicolasnatha8@gmail.com` (id 17) | agent | — | sim |
| Agente Teste B `supervisor.teste@chatspx.app` (id 11) | agent | — | sim |

Sendo administrador **e** super admin da instalação, o Walisson vê o **Console de Super Admin** e
todas as telas de configuração. O pedido é tirar dele seis coisas — e só essas seis:

1. **Console de Super Admin** (menu do perfil)
2. **Atributos personalizados**
3. **Robôs**
4. **Macros**
5. **Integrações**
6. **Fluxo de conversa**

Todo o resto que ele já acessa continua igual: caixas de entrada, agentes, times, etiquetas,
respostas prontas, automações, relatórios, campanhas, SLA, auditoria, conexões WAHA, e por aí.

## A decisão de modelagem

> **"Supervisor" = quem tem linha em `team_supervisors`.** É o conceito que já existe no fork
> (`TeamSupervision`), usado hoje em isolamento de mensagens e em conversas.

Consequências que precisam estar claras antes de começar:

- Para supervisor **agente** (ids 11 e 17) nada muda: agente já não vê tela de configuração.
  A regra só morde **administrador que supervisiona time** — hoje, uma pessoa.
- **Se o dono da conta virar supervisor de um time, ele também perde esses seis itens.** Se isso
  não for aceitável, a alternativa é uma marca explícita (coluna `settings_restricted` em
  `account_users`, ou papel personalizado) em vez de derivar da supervisão. Decida na Parte 0 e
  siga com uma só; não implemente as duas.

## Parte 0 — Confirmar o alvo (5 minutos, sem código)

```bash
cd /home/chatwoot && RAILS_ENV=production bundle exec rails runner '
sup = TeamSupervisor.joins(:team).where(teams: { account_id: 1 }).map(&:user_id).uniq
AccountUser.where(account_id: 1, user_id: sup).each do |au|
  u = User.find(au.user_id)
  puts "#{u.name} | papel=#{au.role} | tipo=#{u.type.inspect}"
end'
```

Se aparecer algum administrador que **deve** manter tudo, pare e troque a regra pela marca
explícita antes de escrever qualquer linha.

## Parte 1 — Console de Super Admin

O item aparece em `components-next/sidebar/SidebarProfileMenu.vue:128`, com a condição
`currentUser.type === 'SuperAdmin'`.

**Esconder o menu não tira o acesso.** `/super_admin` é um escopo Devise próprio
(`config/routes.rb:833`, `devise_for :super_admins`) com `SuperAdmin < User` por STI: quem tem
`users.type = 'SuperAdmin'` entra pela URL mesmo sem menu nenhum.

O que realmente resolve é **deixar de ser super admin**:

```ruby
# Rebaixa o supervisor a usuário comum da instalação (o menu some sozinho).
User.where(id: 14).update_all(type: nil)
```

⚠️ **Só existem dois super admins** — `dev@simplexsolucoes.com.br` (id 1) e o id 14. Não toque no
id 1: sem ele ninguém administra a instalação.

Se quiser que a regra sobreviva a alguém recriar o acesso, adicione a guarda no login do console
(`super_admin/devise/sessions`): recusar quem tem linha em `team_supervisors`. Opcional — a
mudança de tipo já entrega o pedido.

**Prova:** o menu do perfil não mostra mais o item; abrir `/super_admin` numa aba anônima cai na
tela de login e o e-mail do supervisor é recusado.

## Parte 2 — Backend: negar de verdade

Esta é a parte que vale. Sem ela, a Parte 3 é maquiagem: as telas somem e as APIs continuam
abertas por URL.

Crie **uma fonte única** — por exemplo `app/services/supervisor_settings_scope.rb`, espelhando o
formato de `AgentMessageIsolation`/`TeamSupervision`:

```ruby
module SupervisorSettingsScope
  module_function

  # true quando o usuário é supervisor de time nesta conta e, por isso, perde as
  # configurações de plataforma. Sem User (job/API pública) nunca restringe.
  def blocked?(user, account) = TeamSupervision.supervisor?(user, account)
end
```

E aplique nos cinco pontos. Repare que **cada um tem uma amarração diferente** — e dois deles hoje
não têm autorização nenhuma:

| item | onde autorizar | situação hoje |
|---|---|---|
| Atributos personalizados | `api/v1/accounts/custom_attribute_definitions_controller.rb` | **sem nenhuma autorização** — qualquer usuário da conta cria e apaga |
| Robôs | `agent_bots_controller.rb` + `agent_bot_policy.rb` | já tem `check_authorization` |
| Macros | `macros_controller.rb` (+ `macro_policy.rb`) | `check_authorization` só em show/update/destroy/execute |
| Integrações | `api/v1/accounts/integrations/apps_controller.rb` | `check_admin_authorization?` (não passa por policy) |
| Fluxo de conversa | `flows_controller.rb` + `flow_policy.rb` | `index` e `create` **sem** `check_authorization` |

### O que bloquear × o que não pode quebrar

Ler não é o mesmo que administrar, e é aqui que essa task quebra a tela do supervisor se for feita
no braço:

- **Atributos personalizados:** as definições alimentam o painel do contato e da conversa. Bloqueie
  `create/update/destroy`; **mantenha o `index`/`show`**, senão o supervisor abre uma conversa e os
  campos personalizados somem.
- **Macros:** agente executa macro dentro da conversa — é uso legítimo e continua valendo. Bloqueie
  a **gestão** (create/update/destroy); **preserve `index` e `execute`**.
- **Robôs:** a tela de caixa de entrada mostra o bot ligado. Bloqueie a gestão; confira se algum
  ponto de leitura depende do `index` antes de fechá-lo.
- **Integrações:** aqui pode fechar inteiro (index/show inclusive) — nenhuma tela de atendimento
  depende dessa listagem. Confirme o Dyte/webhooks antes de concluir.
- **Fluxo de conversa:** feche gestão e listagem; a execução do fluxo roda por job/webhook, sem
  `Current.user`, então não é afetada.

**Prova:** com o token do supervisor, `POST/PATCH/DELETE` nos cinco recursos devolve **403**, e
`GET` dos que precisam continuar (atributos, macros) devolve **200**:

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/auth/sign_in -H "Content-Type: application/json" \
  -d '{"email":"sup@simplexsolucoes.com.br","password":"SENHA"}' | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['access_token'])")
curl -s -o /dev/null -w "%{http_code} atributos(POST)\n" -X POST -H "api_access_token: $TOKEN" \
  http://127.0.0.1:3000/api/v1/accounts/1/custom_attribute_definitions -d "attribute_display_name=x"
curl -s -o /dev/null -w "%{http_code} atributos(GET)\n" -H "api_access_token: $TOKEN" \
  http://127.0.0.1:3000/api/v1/accounts/1/custom_attribute_definitions
```

## Parte 3 — Front: sumir da barra lateral e barrar a rota

A barra lateral não decide sozinha: cada folha resolve a permissão da rota de destino
(`SidebarGroupLeaf.vue:30`, `SidebarGroup.vue:295` → `resolvePermissions(to)`), e a lista do usuário
vem do backend em `currentAccount.permissions` (`helper/permissionsHelper.js`). O mesmo helper
alimenta a guarda de rota (`helper/routeHelpers.js`) — por isso mexer **no helper** cobre menu e URL
de uma vez, e mexer só no `Sidebar.vue` deixa a URL viva.

Sugestão de recorte, uma constante e um ponto de decisão:

```js
// nomes de rota que o supervisor não alcança, mesmo sendo administrador
export const ROTAS_FORA_DO_SUPERVISOR = [
  'attributes_list',
  'agent_bots',
  'macros_wrapper',
  'settings_applications',
  'conversation_workflow_index',
];
```

O front precisa saber que a pessoa é supervisora. Já existe `teams/getSupervisedTeams`
(`store/modules/teams/getters.js:14`) — use-o, ou exponha a marca no payload do usuário se preferir
não depender da store de times ter carregado.

**Prova:** logado como o supervisor, os cinco itens não aparecem em Configurações, e digitar a URL
`/app/accounts/1/settings/custom-attributes` (e as outras quatro) cai no bloqueio de rota, não na
tela.

## Parte 4 — Não quebrar quem já usava

- Com um **administrador comum** (não supervisor), os seis itens continuam visíveis e funcionando.
- Com um **agente**, nada muda.
- Com o **supervisor**, abra uma conversa e confira: campos personalizados aparecem, macro executa,
  atribuição e times seguem normais.
- Rode `bundle exec rubocop -a` nos arquivos tocados e `npx eslint <arquivo>` (não `pnpm eslint`,
  que varre o projeto inteiro e demora).
- Specs: `spec/policies/` dos recursos tocados e `spec/controllers/api/v1/accounts/` dos cinco.

## Pegadinhas conhecidas

- **Front sozinho não protege.** Some com o menu e a API segue aberta — a Parte 2 é a que vale.
- **Dois controllers hoje não autorizam nada** (atributos e `flows#index/#create`). Ao fechar, você
  está corrigindo um furo que já existia para qualquer agente, não só para o supervisor — teste com
  um agente comum antes de concluir que "quebrou".
- **`check_admin_authorization?` não passa por policy** (integrações): a negação tem que entrar ali,
  não numa policy que ninguém consulta.
- **Overlay Enterprise:** procure os mesmos arquivos em `enterprise/` antes de editar
  (`rg -n "AgentBotPolicy|MacroPolicy|apps_controller" app enterprise`) e mantenha o comportamento
  compatível.
- **Ordem do deploy:** commit antes do restart, senão o `version.json` carimba o SHA antigo e os
  navegadores abertos seguem com o bundle velho.
- **A aba aberta mente.** Depois do deploy, recarregue a aba do supervisor antes de julgar se sumiu.

## Fora de escopo

- Mudar o que o **administrador comum** enxerga.
- Criar papel personalizado / custom role.
- Tirar o super admin do `dev@simplexsolucoes.com.br`.
- Mexer no isolamento de mensagens, de conversas ou na supervisão de time em si — aqui só se usa a
  marca de supervisor, não se altera o que ela já faz.
