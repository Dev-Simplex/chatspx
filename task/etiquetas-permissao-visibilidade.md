# Etiquetas para todos + Visibilidade (pública / privada / de time)

> **Prompt de implementação** — branch `nicolas`, sem feature flag. Modelado no precedente já
> existente do **Macro** (`app/models/macro.rb`), que resolve exatamente o mesmo problema
> (visibility + created_by + scope por autor). Antes de codar, leia o Macro e seus specs; grande
> parte disto é "aplicar o padrão do Macro às Labels, com um terceiro caso `team`".

---

## 1. Objetivo

Hoje só **administradores** criam/editam/excluem etiquetas (`LabelPolicy` exige `administrator?`).
Queremos:

1. **Usuários comuns (agentes) podem incluir, editar e excluir etiquetas.**
2. Ao cadastrar, o usuário escolhe a **visibilidade**:
   - **Pública** — todos da conta veem e usam.
   - **Privada** — só o criador vê/usa.
   - **De um time** — só os membros de um time específico veem/usam.

### Decisões de produto já travadas (confirmadas com o usuário)

| Tema | Decisão |
|------|---------|
| **Alcance da visibilidade** | Governa apenas o **catálogo**: quem vê a etiqueta no gerenciamento (settings), na sidebar e no **seletor ao aplicar** numa conversa. **Não** esconde chips já aplicados numa conversa (isso é v2 e muito mais invasivo). |
| **Editar/excluir PÚBLICA** | Só **autor + admin**. (Renomear cascateia para todas as conversas marcadas via `Labels::UpdateJob` — alto impacto; não deixar qualquer agente mexer numa etiqueta compartilhada.) |
| **Editar/excluir DE TIME** | Qualquer **membro do time** + admin. |
| **Editar/excluir PRIVADA** | Só o **autor** (+ admin). |
| **Visibilidade padrão ao criar** | **Pública** (mantém o comportamento atual; usuário restringe quando quiser). |
| **Unicidade de título** | **Mantida** global por conta (`index_labels_on_title_and_account_id` UNIQUE). Ver §3.1 — é intencional, não relaxar. |

---

## ⚠️ Armadilhas que QUEBRAM o build/feature (ler antes de codar)

Verificadas no código real. Ignorar qualquer uma trava a feature.

1. **Pundit autoriza a CLASSE, não a instância.** O `base_controller#check_authorization` (`app/controllers/api/base_controller.rb:14-18`) faz `authorize(controller_name.classify.constantize)` → `authorize(Label)` (a **classe**). Isso só funciona hoje porque `LabelPolicy` só checa `administrator?` e nunca toca `@record`. No instante em que a policy reescrita ler `@record.created_by_id` / `@record.visibility_team?`, um `authorize(Label)` chamará `Label.created_by_id` → **NoMethodError**. **Solução (padrão Macro):** sobrescrever `check_authorization` no controller para `authorize(@label)` e escopá-lo em `only: [:show, :update, :destroy]`. `index` e `create` **não** passam por `authorize` (qualquer membro logado) — exatamente como `macros_controller.rb:5,71-73`. Ver §4.2.

2. **Apagar `permissions` do route meta bloqueia TODO MUNDO.** `hasPermissions(required=[], avail)` (`helper/permissionsHelper.js:1-8`) faz `required.some(...)` → em array **vazio retorna `false`** → rota inacessível a todos e redireciona. **NÃO remover a chave.** Trocar `['administrator']` por `['agent', 'administrator']` (§5.1). E cuidado com **custom roles** (enterprise): esses usuários têm `permissions` = `['conversation_manage', ...]`, **sem** `'agent'` — se o fork usar custom roles, incluir também `...CONVERSATION_PERMISSIONS`.

3. **`enum` sem `_prefix` colide com Ruby.** `enum visibility: { public:, private:, team: }` geraria `Label.public`/`Label.private` (conflitam com visibilidade de métodos Ruby) e `Label.team` (conflita com `belongs_to :team`). **Usar `_prefix: :visibility`** (§3.2) → `visibility_everyone?`, `Label.visibility_team`, etc. Por isso os nomes internos são `everyone/personal/team`, não `public/private`.

4. **`with_visibility` é SÓ para o `labels_controller#index`.** Não aplicar o scope em `Current.account.labels` global nem em models/reports/automations — eles continuam usando o conjunto completo. Aplicar globalmente sub-contaria relatórios e esconderia labels de automações. Ver §6.

---

## 2. Como funciona hoje (mapa do código)

### Backend
- **Model** `app/models/label.rb` — colunas: `title, description, color, show_on_sidebar, account_id`. Sem visibilidade, sem dono. `default_scope { order(:title) }`. `after_update_commit :update_associated_models` dispara `Labels::UpdateJob` quando `title` muda.
- **Tabela** `labels` (`db/schema.rb`): índice UNIQUE `(title, account_id)`.
- **Controller** `app/controllers/api/v1/accounts/labels_controller.rb` — `before_action :check_authorization` (Pundit). `index` usa `policy_scope(Current.account.labels)`. `permitted_params` = `:title, :description, :color, :show_on_sidebar`.
- **Policy** `app/policies/label_policy.rb` — `index?` → admin **ou** agent; `create?/update?/destroy?/show?` → **só admin**. Sem `Scope` custom (retorna tudo).
- **Views** `app/views/api/v1/accounts/labels/{index,show,create,update}.json.jbuilder` — expõem `id, title, description, color, show_on_sidebar`.
- **Aplicação em conversas** é por **string** (gem `acts-as-taggable-on`, concern `app/models/concerns/labelable.rb`, `label_list`). Não há FK Label↔Conversation. Passa por `LabelConcern`, **não** pela `LabelPolicy`. → Agente já aplica/remove labels; só não gerencia o catálogo.

### Frontend
- **Settings UI** `app/javascript/dashboard/routes/dashboard/settings/labels/` — `Index.vue`, `AddLabel.vue`, `EditLabel.vue`, `validations.js`. (Não há `LabelForm.vue`; o form é duplicado em Add/Edit.) Campos: `title`, `description`, `color` (`woot-color-picker`), `showOnSidebar` (checkbox).
- **Gate de acesso (o que bloqueia o agente):** `labels.routes.js:17` e `:28` → `meta: { permissions: ['administrator'] }`. O guard `dashboard/routes/index.js` → `helper/routeHelpers.js` → `helper/permissionsHelper.js#hasPermissions` redireciona o agente.
- **Store** `store/modules/labels.js` (actions `get/create/update/delete`), **API** `api/labels.js` (`CacheEnabledApiClient`, endpoint `labels`).
- **Sidebar** `components-next/sidebar/Sidebar.vue:848` — item "Settings Labels" **sem** gate próprio (o bloqueio real é a route meta).
- **Aplicar label na conversa** `routes/dashboard/conversation/labels/LabelBox.vue` — `:allow-creation="isAdmin"` (`LabelBox.vue:117`); dropdown `shared/components/ui/label/LabelDropdown.vue`.
- **Role no front:** `composables/useAdmin.js` (`isAdmin`), `composables/usePolicy.js`, `helper/permissionsHelper.js`.
- **Times no front:** `store/modules/teams/` — getter `getMyTeams` (filtra `team.is_member`).

### Precedente Macro (COPIAR)
- `app/models/macro.rb`: `enum visibility: { personal: 0, global: 1 }`, `created_by_id`, `set_visibility(user, params)` (força personal se `user.agent?`), `self.with_visibility(user, _params)` (`global.or(personal.where(created_by_id: user.id))`).
- `app/policies/macro_policy.rb`: `author?` = `@record.created_by == @account_user.user`; `update?` = `author? || (administrator? && global?)`.
- `app/controllers/api/v1/accounts/macros_controller.rb`: `index` usa `Macro.with_visibility(current_user, params)`; `create/update` setam `created_by_id` e chamam `set_visibility`; permite `:visibility`.
- Serializer `app/views/api/v1/models/_macro.json.jbuilder` expõe `visibility` + bloco `created_by`.
- Specs: `spec/controllers/api/v1/accounts/macros_controller_spec.rb`, `spec/models/macro_spec.rb` (`#set_visibility`).

---

## 3. Modelo de dados

### 3.1 Migration
`db/migrate/<timestamp>_add_visibility_to_labels.rb` (padrão do fork: `ActiveRecord::Migration[7.1]`, cabeçalho comentado com o "porquê", idempotente).

```ruby
class AddVisibilityToLabels < ActiveRecord::Migration[7.1]
  def up
    add_column :labels, :visibility, :integer, default: 0, null: false   # 0 = everyone (público)
    add_reference :labels, :created_by, null: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :labels, :team, null: true,
                  foreign_key: { to_table: :teams, on_delete: :nullify }
    add_index :labels, %i[account_id visibility], name: 'index_labels_on_account_and_visibility'
  end

  def down
    remove_index  :labels, name: 'index_labels_on_account_and_visibility', if_exists: true
    remove_reference :labels, :team, if_exists: true
    remove_reference :labels, :created_by, if_exists: true
    remove_column :labels, :visibility, if_exists: true
  end
end
```

- **Etiquetas existentes** ficam `visibility = 0` (público) e `created_by_id = NULL` → tratadas como públicas órfãs (qualquer admin gerencia; ver policy `orphan?`). Backfill de `created_by_id` **não** é necessário (não temos como saber o autor histórico).
- **`team` FK `on_delete: :nullify`**: se o time for apagado, a etiqueta de-time vira órfã → precisamos re-normalizar (ver §3.2 validação/`before_save`): quando `team_id` fica NULL mas `visibility = team`, rebaixar para `everyone` OU deixar inacessível. Recomendação: **um `after_*`/validação que impede `visibility=team` sem `team_id`**, e um cleanup no `Team` destroy que rebaixa labels do time para `everyone` (menos surpresa que sumir). Ver §3.3.

> **Não relaxar a unicidade `(title, account_id)`.** Como a aplicação em conversas é por **string**, dois `Label` distintos com o mesmo título produziriam a **mesma** tag — indistinguíveis na conversa e no relatório. Manter título único por conta é o que mantém o modelo de tags coerente. Se dois usuários quiserem "urgente" privada cada um, isso **não** é suportado nesta versão (documentar no PR).

### 3.2 Model `app/models/label.rb`
Adicionar:

```ruby
enum visibility: { everyone: 0, personal: 1, team: 2 }, _prefix: :visibility
# _prefix evita colisão de Label.public/Label.private com a visibilidade de métodos Ruby,
# e de Label.team com a associação belongs_to :team. Gera: visibility_everyone?,
# Label.visibility_team, etc.

belongs_to :created_by, class_name: 'User', optional: true
belongs_to :team, optional: true

validates :team_id, presence: true, if: :visibility_team?
validate  :team_belongs_to_account, if: :visibility_team?
validates :team_id, absence: true, unless: :visibility_team?   # limpa team_id se não for de-time

# Catálogo visível a um usuário (o coração da feature) — espelha Macro.with_visibility.
# ATENÇÃO: usar SÓ no labels_controller#index. Não aplicar globalmente (ver Armadilha 4).
def self.with_visibility(user)
  account = Current.account
  base = account.labels                         # respeita o scoping por conta da associação
  return base if account_admin?(user, account)  # admin vê tudo

  team_ids = user.teams.where(account_id: account.id).select(:id)
  base.where(visibility: :everyone)
      .or(base.where(visibility: :personal, created_by_id: user.id))
      .or(base.where(visibility: :team, team_id: team_ids))
end

def self.account_admin?(user, account)
  account.account_users.find_by(user_id: user.id)&.administrator? || false
end

private

def team_belongs_to_account
  return if team&.account_id == account_id
  errors.add(:team, 'must belong to the same account')
end
```

Notas:
- `default_scope { order(:title) }` continua ordenando `with_visibility` por title — ok. As três relações do `.or` derivam da MESMA base (`account.labels`), então são estruturalmente compatíveis (requisito do `.or`).
- **Não** replicar o `set_visibility` de "downgrade" do Macro: aqui agentes PODEM criar pública/de-time. O único guard é membership de time (validado no controller, §4.2) — não rebaixar silenciosamente.
- **Erro de unicidade confuso:** como o título é único por conta e labels privadas de outros são invisíveis, um agente pode tentar criar `"vip"` e receber "título já existe" sem ver o conflito (uma privada de outro autor). Usar uma mensagem genérica ("Já existe uma etiqueta com esse nome nesta conta") no i18n e documentar no PR.
- Não replicar o `set_visibility` de "downgrade" do Macro tal-qual: aqui **agente PODE** criar pública/de-time. O único guard é: **etiqueta de-time exige que o usuário seja membro do time** (a menos que admin) — validar no controller/policy, não silenciosamente rebaixar.

### 3.3 Limpeza ao apagar um Team
Em `app/models/team.rb` (ou um callback/service): antes/depois de destruir o time, rebaixar suas etiquetas:
```ruby
# Ex.: before_destroy — evita labels "de-time" órfãs inacessíveis
Label.where(team_id: id, visibility: :team).update_all(visibility: :everyone, team_id: nil)
```
(A FK já faz `nullify`; este passo garante que `visibility` acompanhe, senão a validação `team_id presence if visibility_team?` quebraria em updates futuros.)

---

## 4. Backend — controller, policy, views

### 4.1 Policy `app/policies/label_policy.rb` (reescrever)
```ruby
class LabelPolicy < ApplicationPolicy
  def index?
    true   # qualquer membro logado lista (o scoping é feito por Label.with_visibility no controller)
  end

  def show?
    visible?
  end

  def create?
    true   # agentes e admins podem criar
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def author?
    @record.created_by_id.present? && @record.created_by_id == @account_user.user_id
  end

  def administrator?
    @account_user.administrator?
  end

  def orphan?
    @record.created_by_id.nil?
  end

  def team_member?
    @record.visibility_team? && @account_user.user.teams.exists?(id: @record.team_id)
  end

  # Quem enxerga a etiqueta no catálogo / seletor
  def visible?
    return true if administrator?
    return true if @record.visibility_everyone?
    return author? if @record.visibility_personal?
    return team_member? if @record.visibility_team?
    false
  end

  # Quem edita/exclui — decisões travadas em §1
  def manage?
    return true if administrator?
    return author? if @record.visibility_everyone?   # pública: só autor (ou admin)
    return author? if @record.visibility_personal?   # privada: só autor
    return team_member? if @record.visibility_team?  # de-time: qualquer membro
    orphan?  # etiquetas legadas sem dono → admin já cobre; agente não
  end
end
```
> **Confirmado:** `ApplicationPolicy` (`app/policies/application_policy.rb:1-10`) expõe `@account_user` (o `AccountUser`), `@user` e `@account` a partir do `pundit_user` (`application_controller.rb#pundit_user`). `@account_user.user_id` e `@account_user.user` existem (colunas/associação de `AccountUser`).
>
> **Nota:** com o controller no padrão Macro (§4.2), `index?` e `create?` **não são chamados** (index/create não passam por `authorize`). Ficam aqui só por completude; a autorização efetiva é `show?`/`update?`/`destroy?` sobre a instância `@label`, mais o `validate_team_membership` do controller para o caso de-time.

### 4.2 Controller `labels_controller.rb` (reescrever no padrão Macro)

O ponto crítico é **não** manter o `before_action :check_authorization` genérico (que autoriza a classe). Espelhar `macros_controller.rb`:

```ruby
class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization, only: [:show, :update, :destroy]
  before_action :validate_team_membership, only: [:create, :update]

  def index
    @labels = Label.with_visibility(current_user)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params.merge(created_by: current_user))
  end

  def update
    @label.update!(permitted_params)
  end

  def destroy
    @label.destroy!
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  # Instância, NÃO a classe — senão a policy quebra ao ler @record.created_by_id (Armadilha 1)
  def check_authorization
    authorize(@label)
  end

  # Só membros do time (ou admin) podem criar/editar etiqueta de-time.
  # Lê o valor EFETIVO (params têm prioridade; update parcial cai no valor atual do @label).
  def validate_team_membership
    effective_visibility = params.dig(:label, :visibility) || @label&.visibility
    return unless effective_visibility.to_s == 'team'
    return if Current.account_user.administrator?

    team_id = params.dig(:label, :team_id) || @label&.team_id
    head :forbidden unless Current.user.teams.exists?(id: team_id)
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar, :visibility, :team_id)
  end
end
```

Pontos de atenção:
- `index` e `create` **não** rodam `authorize` (qualquer membro logado da conta) — igual ao Macro. A pertença à conta já é garantida por `BaseController`/`current_account`.
- Removido o `policy_scope` do `index` — a filtragem agora é `Label.with_visibility`.
- `create` seta `created_by: current_user` (necessário para `author?` na policy).
- `validate_team_membership` roda **antes** do save; se não for membro → `403` sem persistir.

### 4.3 Views jbuilder (as 4: index/show/create/update)
Adicionar em cada:
```ruby
json.visibility label.visibility
json.team_id    label.team_id
if label.created_by
  json.created_by do
    json.id   label.created_by.id
    json.name label.created_by.name
  end
end
```
(Seguir o formato de `_macro.json.jbuilder`.)

---

## 5. Frontend

### 5.1 Liberar o acesso (o gate)
`app/javascript/dashboard/routes/dashboard/settings/labels/labels.routes.js`:
- **NÃO remover** a chave `permissions` (Armadilha 2: array vazio → `[].some()` → `false` → rota inacessível a todos).
- Trocar `permissions: ['administrator']` por **`permissions: ['agent', 'administrator']`** nas rotas `labels_wrapper` (`:17`) e `labels_list` (`:28`). Manter o `featureFlag: FEATURE_FLAGS.LABELS` em `:27`.
- **Custom roles (enterprise):** se o fork usar custom roles, esses usuários têm `permissions = ['conversation_manage', ...]` sem `'agent'`. Para incluí-los, usar `permissions: ['agent', 'administrator', ...CONVERSATION_PERMISSIONS]` (importar de `dashboard/constants/permissions.js`). Se o fork só usa agent/administrator padrão, `['agent', 'administrator']` basta.

### 5.2 Formulário criar/editar — seletor de visibilidade
`AddLabel.vue` e `EditLabel.vue` (form duplicado — replicar nos dois; considerar extrair um `LabelVisibilityField.vue` para não divergir):

- Novo campo **Visibilidade** (radio ou `<select>`): **Pública** / **Privada** / **De um time**.
  - Default no `AddLabel` = **Pública** (`everyone`).
  - Quando "De um time" → mostrar `<select>` de **times do usuário** (`store getters['teams/getMyTeams']`; admin pode ver `getTeams` completos). Carregar via `store.dispatch('teams/get')` no `mounted` se ainda não carregado.
  - Validação: se visibilidade = time, `team_id` obrigatório.
- `EditLabel.setFormValues()` deve preencher `visibility` e `team_id` a partir de `selectedResponse`.
- **Desabilitar/ocultar** o form de edição quando o usuário não pode gerenciar (a policy backend já barra com 403; o front deve refletir para não frustrar). Regra espelhando `manage?`: mostrar botão Editar/Excluir na linha da tabela (`Index.vue`) só se `canManage(label)` — computar no front com `useAdmin().isAdmin`, `currentUser.id === label.created_by?.id`, e membership de time (`getMyTeams`).
- Submits: incluir `visibility` e `team_id` no payload de `labels/create` e `labels/update`.
- Copy PT-BR (i18n `SETTINGS.LABELS.*`): rótulos "Visibilidade", "Pública", "Privada", "De um time", "Time", e tooltip curto explicando cada uma. Traduzir nos locales usados (pelo menos `pt_BR` e `en`).

### 5.3 Tabela de listagem `Index.vue`
- Nova coluna/insígnia **Visibilidade** (ícone + texto: 🌐 Pública / 🔒 Privada / 👥 Time «nome»). Buscar nome do time via store teams.
- Botões Editar/Excluir condicionados a `canManage(label)` (§5.2).

### 5.4 Seletor ao aplicar em conversa
- Como o `index` agora é server-filtrado por `with_visibility`, o store `labels/get` já traz **só** as etiquetas que o usuário pode ver → o `LabelDropdown` (`shared/components/ui/label/LabelDropdown.vue`) e a sidebar (`getLabelsOnSidebar`) **automaticamente** respeitam a visibilidade. Nada extra a filtrar no front. ✅
- `LabelBox.vue:117` — `:allow-creation="isAdmin"`: como agora agentes podem criar etiquetas, mudar para `:allow-creation="true"` (ou `canCreateLabels`, sempre true para membros logados). O modal de criação inline (`AddLabelModal` = `settings/labels/AddLabel.vue`) precisa suportar o campo visibilidade (default pública) — herda de §5.2.

### 5.5 Store / API
- `store/modules/labels.js` e `api/labels.js`: os payloads passam `visibility`/`team_id` sem mudança estrutural (é REST genérico). Garantir que o cache (`CacheEnabledApiClient`) não sirva catálogo de outro usuário indevidamente — o cache é por conta/usuário no client, ok, mas conferir invalidção após create/update/delete (já existe `revalidate`).

---

## 6. Casos de borda / atenção

1. **Chips já aplicados** de etiqueta privada/de-time continuam visíveis na conversa a quem a abrir (decisão travada: escopo é catálogo). Documentar no PR e no tooltip ("Privada controla quem vê a etiqueta na lista; se você marcá-la numa conversa, o rótulo aparece para quem abrir a conversa").
2. **Rename cascata**: `Labels::UpdateJob` propaga por título. Como título é único por conta, sem mudança. Só o **autor/admin** renomeia pública (decisão travada) → blast radius controlado.
3. **Etiquetas legadas** (`created_by_id = NULL`, públicas): admin gerencia; agente **não** (não é autor). Aceitável. Opcional: um agente promover-se a dono? Não nesta versão.
4. **Time apagado**: §3.3 rebaixa para pública. Sem etiquetas fantasma.
5. **Membership perdida**: se o usuário sai do time, deixa de ver as etiquetas de-time daquele time no catálogo (esperado). Etiquetas que ele mesmo aplicou continuam nas conversas.
6. **Widget/API pública de labels** (`widget/labels_controller`, contacts labels): continuam operando por string; não filtrar por visibilidade lá (fora de escopo — são listas aplicadas, não o catálogo de gestão).
7. **`show_on_sidebar`** é ortogonal à visibilidade (é só flag de UI). A sidebar mostra `getLabelsOnSidebar` ∩ catálogo-visível.

---

## 7. Testes

Copiar a estrutura de `spec/controllers/api/v1/accounts/macros_controller_spec.rb` e `spec/models/macro_spec.rb`.

### Model `spec/models/label_spec.rb`
- `enum visibility`.
- validação `team_id` presente sse `visibility_team?`; ausente caso contrário; team da mesma conta.
- `Label.with_visibility(user)`:
  - admin vê tudo;
  - agente vê `everyone` + suas `personal` + `team` dos seus times;
  - agente **não** vê `personal` de outro nem `team` de time que não participa.

### Request/Controller `spec/controllers/api/v1/accounts/labels_controller_spec.rb`
- `index` retorna catálogo filtrado por visibilidade (admin vs 2 agentes em times diferentes).
- `create` por **agente**: público (default), privado, e de-time (membro) → 200; de-time de time que não é membro → 403 (a menos que admin).
- `update`/`destroy`:
  - autor edita a própria (qualquer visibilidade) → 200;
  - membro do time edita etiqueta de-time → 200;
  - **não-autor** tenta editar **pública** → 403;
  - agente tenta editar **privada de outro** → 403/404.
- Regressão: garantir que rotas antes admin-only agora aceitam agente onde previsto.

### Factory `spec/factories/labels.rb`
- traits `:personal`, `:team_visible` (com `team`), default público, `created_by`.

### Frontend
- Se houver specs de componente para `AddLabel/EditLabel/Index`, cobrir: render do seletor, `team_id` obrigatório quando "De um time", botões de gestão condicionados a `canManage`.

---

## 8. Ordem de execução sugerida (fases pequenas, verde a cada passo)

- **F1 — Dados/Model**: migration + `Label` (enum, associações, validações, `with_visibility`) + limpeza no Team + specs de model. Rodar `rspec spec/models/label_spec.rb`.
- **F2 — API**: policy reescrita + controller (index scope, permit, `authorize(@label)`, guard de time) + jbuilders + request specs. Rodar specs de controller.
- **F3 — Front settings**: liberar route meta + seletor de visibilidade em Add/Edit (+ `LabelVisibilityField` compartilhado) + coluna/insígnia + gating de botões no `Index.vue` + i18n.
- **F4 — Aplicar em conversa**: `LabelBox.vue allow-creation` + confirmar que catálogo filtrado já cobre dropdown/sidebar. QA manual.
- **F5 — Validação staging** (nicolas.chatspx.app): build assets + `sudo /bin/systemctl restart chatwoot.target`. Testar com um usuário **agente** e um **admin**, em 2 times distintos. Nunca testar em produção/frota.

Commit ao fim de **cada** fase (padrão do fork). Sem feature flag → cuidado: vai a todos no deploy.

---

## 9. Checklist de "pronto"

- [ ] Agente cria/edita/exclui suas etiquetas.
- [ ] Seletor Pública/Privada/De-time no cadastro, com seleção de time.
- [ ] Privada só aparece para o autor; de-time só para membros; pública para todos — no settings, na sidebar e no seletor da conversa.
- [ ] Agente **não** edita pública de outro (só autor/admin); membro do time edita de-time.
- [ ] Etiquetas legadas continuam funcionando (públicas, geridas por admin).
- [ ] Time apagado não deixa etiqueta fantasma.
- [ ] Specs de model + request verdes; build/lint verdes.
- [ ] Copy PT-BR + EN.
- [ ] Validado no staging com agente + admin.

---

### Referências rápidas de arquivos
```
Backend
  app/models/label.rb
  app/models/macro.rb                          # PRECEDENTE
  app/policies/label_policy.rb
  app/policies/macro_policy.rb                 # PRECEDENTE
  app/controllers/api/v1/accounts/labels_controller.rb
  app/controllers/api/v1/accounts/macros_controller.rb   # PRECEDENTE
  app/views/api/v1/accounts/labels/*.json.jbuilder
  app/views/api/v1/models/_macro.json.jbuilder # PRECEDENTE (created_by/visibility)
  app/models/team.rb / team_member.rb / user.rb (has_many :teams)
  db/migrate/<novo>.rb
Frontend
  app/javascript/dashboard/routes/dashboard/settings/labels/{labels.routes.js,Index.vue,AddLabel.vue,EditLabel.vue,validations.js}
  app/javascript/dashboard/store/modules/labels.js ; api/labels.js
  app/javascript/dashboard/store/modules/teams/getters.js (getMyTeams)
  app/javascript/dashboard/routes/dashboard/conversation/labels/LabelBox.vue (allow-creation)
  app/javascript/shared/components/ui/label/LabelDropdown.vue
  app/javascript/dashboard/composables/{useAdmin.js,usePolicy.js}
Specs
  spec/models/{label_spec.rb,macro_spec.rb}
  spec/controllers/api/v1/accounts/{labels_controller_spec.rb,macros_controller_spec.rb}
  spec/factories/labels.rb
```
