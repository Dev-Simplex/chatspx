# Respostas prontas: visibilidade (pública / privada / de time)

> **Prompt de implementação** — branch `nicolas`, sem feature flag. Modelado no precedente já
> executado das **Etiquetas** (`task/etiquetas-permissao-visibilidade.md`), que por sua vez
> segue o **Macro** (`app/models/macro.rb`). Grande parte disto é "aplicar o padrão das Labels
> às Canned Responses" — MAS há diferenças reais que quebram uma cópia ingênua (ler §0 e as
> Armadilhas antes de codar). Antes de começar, leia: `app/models/label.rb`,
> `app/policies/label_policy.rb`, `app/controllers/api/v1/accounts/labels_controller.rb` e o
> commit da feature de etiquetas (`819bf3a84`, `0242c5f51`).

---

## 1. Objetivo

Hoje **qualquer membro logado** (agente ou admin) cria/edita/exclui **qualquer** resposta pronta —
o controller **não tem autorização nenhuma** (não existe `CannedResponsePolicy`, nem `authorize`).
Queremos, ao cadastrar/editar uma resposta pronta, escolher a **visibilidade**:

- **Pública** — todos da conta veem e usam (no gerenciamento e no seletor `/` do compositor).
- **Privada** — só o criador vê/usa.
- **De um time** — só os membros de um time específico veem/usam.

### Decisões de produto já travadas (confirmadas com o usuário)

| Tema | Decisão |
|------|---------|
| **Alcance da visibilidade** | Governa o **catálogo**: quem vê a resposta no gerenciamento (settings) **e no seletor do compositor** (o picker `/` e o modal). Como o `index` do controller é o MESMO endpoint que alimenta o compositor (via `?search=`), filtrar o `index` já escopa os dois — desejado (agente não deve inserir uma resposta privada que não é dele). Não há chip aplicado/histórico a esconder: resposta pronta vira **texto literal** no envio (sem referência viva). |
| **Editar/excluir PÚBLICA** | **Qualquer agente** (+ admin). **Modelo permissivo** — mantém o colaborativo de hoje; ninguém perde acesso que já tinha. Justificativa: editar resposta pronta **não cascateia** (diferente de renomear etiqueta, que dispara `Labels::UpdateJob`); o blast radius é zero, então não há motivo para restringir a edição de compartilhadas. |
| **Editar/excluir DE TIME** | Qualquer **membro do time** + admin. |
| **Editar/excluir PRIVADA** | Só o **autor** (+ admin). |
| **MUDAR a visibilidade de uma PÚBLICA** | Só **autor + admin** (guard §4.2 `validate_visibility_change`). Fecha o furo do modelo permissivo: sem isso, qualquer agente poderia converter uma pública compartilhada em privada/de-time e **sumir** com ela do catálogo de todos (pior ainda numa legada órfã, que ficaria `personal + created_by nil` = invisível a todos os agentes). **Editar o CONTEÚDO** de uma pública segue livre p/ qualquer agente; só a **troca de visibilidade** (sair de `everyone`) é restrita. Legadas órfãs (sem autor) → só admin re-escopa. |
| **Respostas legadas** (`created_by_id = NULL`) | São públicas (`visibility = 0`) → **conteúdo editável por qualquer agente** (consistente com pública). Só a troca de visibilidade exige admin (linha acima). Ninguém perde acesso às respostas compartilhadas atuais. |
| **Visibilidade padrão ao criar** | **Pública** (mantém o comportamento atual; usuário restringe quando quiser). |
| **Unicidade de `short_code`** | **Mantida** por conta (validação de model `uniqueness: { scope: :account_id }`). Ver §3.1 — não relaxar. |

> **Diferença central vs. Etiquetas:** lá, abrir para agentes foi *expansão* (era admin-only) e a
> edição de pública ficou restrita a autor+admin por causa da cascata de rename. Aqui é o
> oposto: a edição já é livre; a feature **adiciona autorização** só onde faz sentido (privada e
> de-time). O único "aperto" é que privada/de-time passam a ser respeitadas — pública segue livre.

---

## ⚠️ Armadilhas que QUEBRAM o build/feature (ler antes de codar)

Verificadas no código real. Ignorar qualquer uma trava a feature.

1. **NÃO existe `CannedResponsePolicy` e o controller NÃO chama `authorize` hoje.** Diferente de
   Labels/Macros (que já tinham policy + `check_authorization`), aqui você **cria a policy do
   zero** E **adiciona** `before_action :check_authorization, only: [:update, :destroy]` +
   `before_action :validate_team_membership, only: [:create, :update]` no controller, além de
   sobrescrever `check_authorization` para `authorize(@canned_response)` (a **instância**). Sem
   isso, ou não há gate (privada não é respeitada) ou — se usar o `check_authorization` genérico
   do `base_controller` (`api/base_controller.rb:14-18`) — ele autoriza a **classe**
   `CannedResponse`, e a policy quebra ao ler `@record.created_by_id` → **NoMethodError**.
   **Não há `:show`** nas rotas (`config/routes.rb:110` = `only: [:index, :create, :update, :destroy]`),
   então o `check_authorization` é só em `[:update, :destroy]` (Labels incluía `:show`; aqui não).

2. **Serialização é INLINE, não jbuilder.** Não existe `app/views/api/v1/accounts/canned_responses/`.
   O controller responde via `render json: serialize(cr)` e o método privado `serialize`
   (`canned_responses_controller.rb:36-47`) monta o JSON com `as_json(only: %i[...])` + bloco de
   attachments. **Os campos novos (`visibility`, `team_id`, `created_by`) entram ali**, no
   `only:` e num merge — não em jbuilder. `index`, `create` e `update` todos passam por `serialize`.

3. **`enum` sem `_prefix` colide.** `visibility: { ..., team: 2 }` geraria `CannedResponse.team`
   que colide com `belongs_to :team`, e `public`/`private` colidem com visibilidade de métodos
   Ruby. **Usar `_prefix: :visibility`** (§3.2) → `visibility_everyone?`, `CannedResponse.visibility_team`,
   `visibility_personal?`, etc. Por isso os nomes internos são `everyone/personal/team`.

4. **`with_visibility` vai no `index`, que É o endpoint do compositor.** Aplicar o scope dentro do
   método privado `canned_responses` (`controller:49-58`) para compor com a busca
   (`.where(search…).order_by_search`). Isso escopa **tanto** a lista de settings **quanto** o
   picker `/` e o modal do compositor (ambos batem no mesmo `index`). É o único ponto de leitura
   do catálogo (grep confirmou: não há widget/relatório/automação lendo canned responses). **Não
   aplicar em `Current.account.canned_responses` global** em outros lugares (não há outros, mas
   fica a regra).

5. **Specs existentes já estão VERMELHAS na branch (não é "vão quebrar" — já quebram).**
   `spec/controllers/api/v1/accounts/canned_responses_controller_spec.rb` (é `type: :request`)
   compara `response.parsed_body` com `account.canned_responses.as_json` (linha ~28) e ordena
   `[cr3, cr2, cr1].as_json` (linhas ~45-47). O `serialize` do fork **já** adiciona
   `"attachments" => []`, que o `as_json` cru não tem → rodar o spec hoje dá **2 falhas** (linhas
   ~22 e ~31). **Não introduza a ideia de que foi você que quebrou.** Reescreva essas 2 asserções
   para checar os campos do `serialize` (incluindo `visibility`/`created_by`/`team_id`), não
   `as_json` cru, e cubra visibilidade. **Não existe** `spec/models/canned_response_spec.rb` → criar.

6. **Tabela é `id: :serial` (integer PK) e o índice `[account_id, short_code]` NÃO é UNIQUE no DB**
   (`db/schema.rb:318-326`). A unicidade é **só** validação de model. Não precisa mudar isso; só
   não copie do doc de Labels a suposição de índice único no banco. As FKs novas (`created_by`,
   `team`) são bigint apontando para users/teams bigint — ok, independente do PK serial da tabela.

7. **`content` é rich text (ProseMirror `WootMessageEditor`) e há anexos (multipart).** O campo de
   visibilidade é um bloco **irmão**, fora do editor. A API já serializa via `buildPayload` que
   vira `FormData` quando há anexo e faz append genérico de todas as chaves — `visibility`/`team_id`
   passam sozinhos (JSON e multipart). Só confira que `team_id: null` no multipart não vira string
   problemática (append manda `'' `; o backend trata `team_id` vazio como nil no permit).

---

## 2. Como funciona hoje (mapa do código)

### Backend
- **Model** `app/models/canned_response.rb` (31 linhas) — colunas: `content, short_code, account_id`.
  Validações: `content`/`short_code`/`account` presença; `short_code uniqueness scope: :account_id`.
  `belongs_to :account`; `has_many_attached :attachments` (fork). Scope `order_by_search`. **Sem**
  `default_scope`, **sem** callbacks, **sem** `created_by`, **sem** visibilidade.
- **Schema** `db/schema.rb:318-326` — `id: :serial`; índices `idx_canned_responses_account_short_code`
  (`[account_id, short_code]`, **não** único) e `idx_canned_responses_account_id`.
- **Controller** `app/controllers/api/v1/accounts/canned_responses_controller.rb` (59 linhas) —
  `before_action :fetch_canned_response, only: [:update, :destroy]`. **Sem autorização.** `index`
  → `render json: canned_responses.map { serialize }`. Privado `canned_responses` (49-58) aplica
  busca quando `params[:search]`. `serialize` (36-47) = `as_json(only: %i[id short_code content
  account_id created_at updated_at])` + `attachments`. `permitted_params` (32-34) = `:short_code,
  :content, attachments: []`.
- **Policy** — **não existe** (`app/policies/canned_response_policy.rb` a criar).
- **BaseController** `app/controllers/api/base_controller.rb:14-18` — `check_authorization(model=nil)`
  autoriza a **classe** por padrão (a armadilha 1). O `Api::V1::Accounts::BaseController` não tem
  `check_authorization` global; cada controller opta por ação.
- **Rotas** `config/routes.rb:110` — `resources :canned_responses, only: [:index, :create, :update, :destroy]`.
- **Outros leitores** — só `Account#has_many :canned_responses` e o seeder (`lib/seeders/account_seeder.rb`).
  Sem widget/API pública/relatório. `Api::V1::CannedResponsesHelper` é módulo vazio.

### Frontend
- **Settings UI** `app/javascript/dashboard/routes/dashboard/settings/canned/` — `Index.vue`
  (`<script setup>`, tabela + hospeda modais), `AddCanned.vue` e `EditCanned.vue` (modais **Options
  API** com **validações Vuelidate inline** — **não há** `validations.js` compartilhado). Campos:
  `short_code` (input), `content` (`WootMessageEditor` ProseMirror), `attachments` (input file).
- **Gate de rota** `canned.routes.js:22-30` → `meta: { featureFlag: FEATURE_FLAGS.CANNED_RESPONSES,
  permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] }`. **Já aberto a agentes** (igual Labels) —
  nada a mudar aqui (a rota-pai de redirect não tem `meta`; opcional adicionar, não bloqueante).
- **Store** `store/modules/cannedResponse.js` — `getCannedResponse({searchKey})`, `createCannedResponse`,
  `updateCannedResponse`, `deleteCannedResponse`. **Passthrough**: create manda o objeto inteiro;
  update destrutura `{id, ...updateObj}` e encaminha tudo → campos novos passam sozinhos.
- **API** `api/cannedResponse.js` — estende `ApiClient` (NÃO `CacheEnabledApiClient`; sem cache).
  `get({searchKey})` → `GET canned_responses?search=`. `buildPayload` (27-39) faz FormData com
  anexo e append genérico de todas as chaves.
- **Compositor (integração-chave)** — **dois** consumidores, ambos via `getCannedResponse`/`getCannedResponses`
  → **mesmo `index`**:
  - `/` inline: `components/widgets/conversation/CannedResponse.vue` (getter `getCannedResponses`,
    dispatch `getCannedResponse {searchKey}`), montado no `Editor.vue` (876-879).
  - Modal: `components-next/canned-response/CannedResponseModal.vue`, aberto pelo `ReplyBox.vue`.
  → Como o backend filtra o `index` por `with_visibility`, **os dois já respeitam a visibilidade
  automaticamente**. Nada a filtrar no front. ✅
- **Times/role** `store/modules/teams/getters.js` (`getTeams`, `getMyTeams`, `getTeam`);
  `composables/useAdmin.js` (`isAdmin`); `store/modules/auth.js` (`getCurrentUser`, `getCurrentRole`).
- **i18n** `i18n/locale/{en,pt_BR}/cannedMgmt.json` — namespace `CANNED_MGMT`, com blocos **separados**
  `ADD.FORM` e `EDIT.FORM` (não há bloco `FORM` único como em Labels).

### Precedente Etiquetas (COPIAR)
- `app/models/label.rb`: `enum visibility { everyone:0, personal:1, team:2 }, _prefix: :visibility`;
  validações de `team_id`; `self.with_visibility(user)`; `self.account_admin?`; `team_belongs_to_account`.
- `app/policies/label_policy.rb`: `visible?`/`manage?` com `author?`/`team_member?`/`administrator?`/`orphan?`.
- `app/controllers/api/v1/accounts/labels_controller.rb`: `authorize(@label)` (instância),
  `validate_team_membership`, `with_visibility` no index, `create` seta `created_by`.
- `app/models/team.rb`: declaração `before_destroy :rebase_team_labels` na **linha 43**, método `rebase_team_labels` em **94-96**.
- Front: `LabelVisibilityField.vue`, `Index.vue` (badge lucide + `canManage`), `AddLabel.vue`/`EditLabel.vue`.

### Mapa de cópia (alvo canned ⇐ fonte label) — e onde DIVERGE
Copiar da esquerda (Label, já pronto) para a direita (Canned), atento às divergências marcadas ⚠.

| Alvo (Canned) | Fonte (Label, copiar) | Divergência ⚠ |
|---|---|---|
| migration `add_visibility_to_canned_responses` | `20260709120000_add_visibility_to_labels` | tabela é `id: :serial`; índice `short_code` **não-único** no DB |
| `CannedResponse` enum/validações/`with_visibility` | `label.rb` | `with_visibility(user, base)` recebe **base** (compõe com busca); sem `default_scope`/downcase |
| `CannedResponsePolicy` (CRIAR) | `label_policy.rb` | pública = **qualquer agente** (permissivo); **sem** `show?` (não há rota); + guard de transição no controller |
| controller: `authorize`/guards/serialize | `labels_controller.rb` | serializa **inline** (`serialize`), não jbuilder; `check_authorization` só `[:update,:destroy]`; `+validate_visibility_change` |
| `CannedVisibilityField.vue` (CRIAR) | `LabelVisibilityField.vue` | i18n em `CANNED_MGMT.VISIBILITY.*` (bloco novo compartilhado) |
| `EditCanned.vue` seletor+gating | `EditLabel.vue` | ⚠ **props individuais** (`edvisibility`/`edteamId`/`edcreatedBy`), **não** `selectedResponse`; wire no `Index.vue` |
| `AddCanned.vue` seletor | `AddLabel.vue` | validações **inline** (não há `validations.js`) |
| `Index.vue` badge+coluna+`canManage` | `labels/Index.vue` | precisa **adicionar** imports (`useAdmin`, teams getters, currentUser) que o canned Index não tem |
| i18n `cannedMgmt.json` | `labelsMgmt.json:40-63` | bloco **compartilhado** `VISIBILITY` no topo (Add/Edit são separados); **não** duplicar |
| Team `rebase_team_canned_responses` | `team.rb` `rebase_team_labels` (43, 94-96) | idêntico; testar com funil removido |
| specs model+request | labels specs | request spec **já vermelho** (attachments); criar model spec do zero |

---

## 3. Modelo de dados

### 3.1 Migration
`db/migrate/<timestamp>_add_visibility_to_canned_responses.rb` — timestamp **posterior** a
`20260709120000` (a migration de Labels). Padrão do fork: `ActiveRecord::Migration[7.1]`, cabeçalho
comentado com o "porquê", idempotente.

```ruby
class AddVisibilityToCannedResponses < ActiveRecord::Migration[7.1]
  def up
    add_column :canned_responses, :visibility, :integer, default: 0, null: false   # 0 = everyone (pública)
    add_reference :canned_responses, :created_by, null: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :canned_responses, :team, null: true,
                  foreign_key: { to_table: :teams, on_delete: :nullify }
    add_index :canned_responses, %i[account_id visibility],
              name: 'index_canned_responses_on_account_and_visibility'
  end

  def down
    remove_index  :canned_responses, name: 'index_canned_responses_on_account_and_visibility', if_exists: true
    remove_reference :canned_responses, :team, if_exists: true
    remove_reference :canned_responses, :created_by, if_exists: true
    remove_column :canned_responses, :visibility, if_exists: true
  end
end
```

- Respostas existentes ficam `visibility = 0` (pública) e `created_by_id = NULL` → públicas órfãs
  (qualquer agente edita, por decisão travada). Sem backfill (não dá pra inferir o autor histórico).
- `team` FK `on_delete: :nullify`: se o time some, a resposta de-time viraria órfã com
  `visibility=team, team_id=NULL` (inválida). Por isso o cleanup no Team (§3.3).

### 3.2 Model `app/models/canned_response.rb`
Adicionar:

```ruby
enum visibility: { everyone: 0, personal: 1, team: 2 }, _prefix: :visibility
# _prefix evita CannedResponse.team (colide com belongs_to :team) e public/private.

belongs_to :created_by, class_name: 'User', optional: true
belongs_to :team, optional: true

validates :team_id, presence: true, if: :visibility_team?
validate  :team_belongs_to_account, if: :visibility_team?
validates :team_id, absence: true, unless: :visibility_team?

# Catálogo visível a um usuário — espelha Label.with_visibility. Usar SÓ no controller#index
# (que também alimenta o compositor). Recebe a relação BASE já filtrada por busca, para compor.
def self.with_visibility(user, base = nil)
  account = Current.account
  base ||= account.canned_responses
  return base if account_admin?(user, account)

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
- `with_visibility` recebe `base` para **compor com a busca** do `index` (`.where(short_code ILIKE …)
  .order_by_search`). As três relações do `.or` derivam da MESMA base → compatíveis.
- **Não** copiar `before_validation` de downcase nem `default_scope order(:title)` de Labels — canned
  responses não têm isso; a ordenação natural do `index` é `order_by_search` (quando há busca) ou a
  ordem padrão. O `.or` preserva a ordenação aplicada na base.
- Mensagem de unicidade: como `short_code` é único por conta e privadas de outros são invisíveis, um
  agente pode receber "short_code já existe" sem ver o conflito. Usar mensagem genérica no i18n e
  documentar no PR (mesmo caveat das Labels).

### 3.3 Limpeza ao apagar um Team
Em `app/models/team.rb` já existe `before_destroy :rebase_team_labels` (declaração na linha 43,
método em 94-96). **Estender** para também rebaixar canned responses de-time (adicionar callback +
método irmão):

```ruby
before_destroy :rebase_team_labels
before_destroy :rebase_team_canned_responses

# ...
def rebase_team_canned_responses
  CannedResponse.where(team_id: id, visibility: :team)
                .update_all(visibility: :everyone, team_id: nil) # rubocop:disable Rails/SkipsModelValidations
end
```
(A FK já faz `nullify`; isto garante que `visibility` acompanhe, senão a validação
`team_id presence if visibility_team?` quebraria em updates futuros.)

> **Atenção ao testar (mesmo caso das Labels):** um `team.destroy!` real é barrado por uma FK
> **não relacionada** — `funnels → teams` sem `on_delete` (`schema.rb:1785`), e todo Team cria um
> funil no `after_create :create_default_funnel`. Logo `team.destroy!` levanta
> `ActiveRecord::InvalidForeignKey` **antes** de qualquer `before_destroy` rodar. No spec, remova o
> funil primeiro (`team.funnels.destroy_all`) ou stube `Kanban::CreateFunnelForTeamService`. Como
> nas Labels, este callback só é alcançado quando o destroy de fato conclui — em produção o cenário
> "apagar time" hoje nem é alcançável, mas o callback fica pronto para quando for.

---

## 4. Backend — policy, controller, serializer

### 4.1 Policy `app/policies/canned_response_policy.rb` (CRIAR — não existe)
Modelo permissivo (decisão travada): **pública = qualquer membro**; privada = autor+admin;
de-time = membro+admin.

```ruby
class CannedResponsePolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
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

  def team_member?
    @record.visibility_team? && @account_user.user.teams.exists?(id: @record.team_id)
  end

  # Quem edita/exclui — modelo PERMISSIVO (decisões §1).
  def manage?
    return true if administrator?
    return true if @record.visibility_everyone?   # pública: qualquer agente (inclui legadas órfãs)
    return author? if @record.visibility_personal? # privada: só autor
    return team_member? if @record.visibility_team? # de-time: qualquer membro
    false
  end
end
```
> `ApplicationPolicy` (`app/policies/application_policy.rb`) expõe `@account_user`, `@user`, `@account`.
> `@account_user.user_id` e `@account_user.user` existem. Como `index`/`create` não passam por
> `authorize` (padrão Macro/Label), `index?`/`create?` ficam por completude; o gate efetivo é
> `update?`/`destroy?` sobre a instância + `validate_team_membership` no controller (caso de-time).
> **Não há `visible?`/`show?`** porque não há rota `:show`; o escopo de leitura é o `with_visibility`
> no `index`.

### 4.2 Controller `canned_responses_controller.rb` (adicionar autorização + visibilidade)

```ruby
class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]
  before_action :check_authorization, only: [:update, :destroy]
  before_action :validate_team_membership, only: [:create, :update]
  before_action :validate_visibility_change, only: [:update]

  def index
    render json: canned_responses.map { |cr| serialize(cr) }
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params.merge(created_by: current_user))
    @canned_response.save!
    render json: serialize(@canned_response)
  end

  def update
    @canned_response.attachments.purge if params.dig(:canned_response, :attachments).present?
    @canned_response.update!(canned_response_params)
    render json: serialize(@canned_response)
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  private

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  # Instância, NÃO a classe (Armadilha 1).
  def check_authorization
    authorize(@canned_response)
  end

  # Só membros do time (ou admin) criam/editam resposta de-time.
  def validate_team_membership
    return unless effective_visibility.to_s == 'team'
    return if Current.account_user.administrator?

    head :forbidden unless Current.user.teams.exists?(id: effective_team_id)
  end

  def effective_visibility
    params.dig(:canned_response, :visibility) || @canned_response&.visibility
  end

  # Modelo permissivo deixa QUALQUER agente editar o CONTEÚDO de uma pública; mas TROCAR a
  # visibilidade dela (tirar do everyone) só autor/admin pode — senão um agente "sequestraria" a
  # resposta compartilhada, sumindo com ela do catálogo dos outros. Legada órfã (sem autor) → só admin.
  def validate_visibility_change
    return unless @canned_response.visibility_everyone?
    new_visibility = params.dig(:canned_response, :visibility)
    return if new_visibility.blank? || new_visibility.to_s == 'everyone'
    return if Current.account_user.administrator?

    head :forbidden unless @canned_response.created_by_id == Current.user.id
  end

  def effective_team_id
    params.dig(:canned_response, :team_id) || @canned_response&.team_id
  end

  def canned_responses
    scope = if params[:search]
              Current.account.canned_responses
                     .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
                     .order_by_search(params[:search])
            else
              Current.account.canned_responses
            end
    CannedResponse.with_visibility(current_user, scope)
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content, :visibility, :team_id, attachments: [])
  end

  def serialize(canned)
    canned.as_json(only: %i[id short_code content account_id visibility team_id created_at updated_at]).merge(
      'created_by' => (canned.created_by && { 'id' => canned.created_by.id, 'name' => canned.created_by.name }),
      'attachments' => canned.attachments.map do |att|
        { 'id' => att.id, 'filename' => att.filename.to_s, 'file_type' => att.content_type, 'file_url' => url_for(att) }
      end
    )
  end
end
```

Pontos de atenção:
- `index`/`create` **não** rodam `authorize` (qualquer membro), igual Macro/Label. Pertença à conta
  garantida por `BaseController`/`current_account`.
- `canned_responses` aplica busca **e depois** `with_visibility(scope)` → compositor e settings
  ficam ambos escopados.
- `create` seta `created_by: current_user` (necessário para `author?`).
- `serialize` ganha `visibility`, `team_id` no `only:` + bloco `created_by` (nil quando órfã).
  `as_json(only:)` com `visibility` (enum) retorna a **string** do enum (`"everyone"/"personal"/"team"`)
  — é o que o front consome.
- `validate_team_membership` roda antes do save; não-membro → `403` sem persistir.

### 4.3 Contrato de resposta (o que o front consome)
Cada resposta pronta passa a carregar: `visibility` (string `everyone|personal|team`),
`team_id` (int|null), `created_by` (`{id,name}`|null), além dos campos atuais + `attachments`.

---

## 5. Frontend

### 5.1 Gate de rota
**Nada a mudar** — `canned.routes.js:27` já usa `permissions: [...ROLES, ...CONVERSATION_PERMISSIONS]`
(agentes já entram). Opcional: adicionar `meta.permissions` na rota-pai de redirect (`:16-21`) por
paridade com Labels; não é bloqueante.

### 5.2 Campo de visibilidade — `CannedVisibilityField.vue` (CRIAR)
`LabelVisibilityField.vue` está **hardcoded** no namespace `LABEL_MGMT.FORM.VISIBILITY.*`, então
**não** é reutilizável direto. Criar `settings/canned/CannedVisibilityField.vue` como cópia
quase-verbatim, trocando o prefixo i18n para `CANNED_MGMT.VISIBILITY.*` (bloco **compartilhado** —
ver §5.7; NÃO usar `ADD.FORM`/`EDIT.FORM`, que são separados e um componente único não resolveria os
dois). Reaproveitar toda a
lógica: `VISIBILITY_OPTIONS = ['everyone','personal','team']`; props `visibility`/`teamId`/`teamError`;
emits `update:visibility`/`update:teamId`; `availableTeams = isAdmin ? teams/getTeams : teams/getMyTeams`;
`mounted` faz `teams/get` se vazio; limpar `teamId` ao sair de `team`; `<select class="reset-base">`
(a classe `reset-base` é obrigatória — padding global sobrepõe senão).

### 5.3 Modais Add/Edit (`AddCanned.vue` / `EditCanned.vue`)
Ambos Options API com **validações Vuelidate inline** (não há `validations.js`). **ATENÇÃO — a
estrutura do canned NÃO é a das Labels:** `EditCanned.vue` **não** recebe um objeto `selectedResponse`;
recebe **props individuais** (`id`, `edcontent`, `edshortCode`, `onClose`, props 16-21) e semeia o
`data()` a partir delas (`shortCode: this.edshortCode`, `content: this.edcontent`). NÃO copie o
padrão `selectedResponse` do `EditLabel` — dá `ReferenceError`. O registro completo mora no
`activeResponse` do `Index.vue` (setado em `openEditPopup`, ~99-102).

Em **cada** modal:
- Importar e renderizar `<CannedVisibilityField v-model:visibility="visibility" v-model:team-id="teamId" :team-error="teamError" />`
  como bloco **irmão**, após o `WootMessageEditor` de `content` (fora do editor) e perto do bloco de anexos.
- `data()`: `visibility` e `teamId` (ver semeadura abaixo). No **AddCanned**: `visibility: 'everyone'`, `teamId: null`.
- Validações inline: adicionar ao objeto `validations` de cada modal (importar `requiredIf` de `@vuelidate/validators`):
  `visibility: {}` e `teamId: { requiredIf: requiredIf(function () { return this.visibility === 'team'; }) }`.

**AddCanned** — payload de submit (dispatch `createCannedResponse`, objeto ~68-70): incluir
`visibility: this.visibility` e `team_id: this.visibility === 'team' ? this.teamId : null`.

**EditCanned — encanamento de props (o passo que o implementador esquece):**
1. Em `Index.vue`, no `<EditCanned>` (~253-260), passar 3 props novas a partir de `activeResponse`:
   `:edvisibility="activeResponse.visibility"`, `:edteam-id="activeResponse.team_id"`,
   `:edcreated-by="activeResponse.created_by"`.
2. Em `EditCanned.vue`, declarar as props: `edvisibility: { type: String, default: 'everyone' }`,
   `edteamId: { type: Number, default: null }`, `edcreatedBy: { type: Object, default: null }`.
3. Semear o `data()` delas: `visibility: this.edvisibility || 'everyone'`, `teamId: this.edteamId || null`.
4. Payload de submit (dispatch `updateCannedResponse`, objeto ~72-75): incluir `visibility: this.visibility`
   e `team_id: this.visibility === 'team' ? this.teamId : null`.
- **Gating (`canManage`)**: computar com admin OR (`everyone` → sempre true, pois pública é editável por
  qualquer agente) OR (`team` → membro via `teams/getMyTeams`) OR (autor: `currentUser.id === this.edcreatedBy?.id`).
  Quando `!canManage`: banner `CANNED_MGMT.VISIBILITY.NO_MANAGE_PERMISSION` + submit desabilitado.
  > **Nota (LOW):** como o `index` já vem escopado por `with_visibility`, toda linha que um não-admin
  > consegue ver é gerenciável por ele (pública→true, própria privada→autor→true, de-time de time
  > dele→membro→true). Logo, na prática, `canManage` é quase sempre `true` e o banner raramente
  > aparece — o gate REAL é o 403 do backend. Manter o `canManage` é **defensivo/redundante** (ou
  > simplificar). O caso em que ele agrega é o **submit de troca de visibilidade** de uma pública por
  > não-autor (o guard `validate_visibility_change` dá 403) — vale desabilitar o seletor de
  > visibilidade quando `edvisibility === 'everyone'` e o usuário não é autor/admin, pra refletir isso.

### 5.4 Lista `Index.vue`
- Adicionar imports que hoje não existem no canned Index: `useAdmin`, getters de `teams`,
  `getCurrentUser`. (O Index de Labels já faz isso — copiar.)
- Nova coluna **Visibilidade** (badge com ícone lucide + texto): `everyone` → `i-lucide-globe`
  «Pública»; `personal` → `i-lucide-lock` «Privada»; `team` → `i-lucide-users` «Time «nome»»
  (nome via `teams/getTeam`). Copiar `visibilityBadge()` e a célula de `labels/Index.vue:39-60,206-216`.
  Adicionar o header em `tableHeaders`.
- Botões Editar/Excluir condicionados a `canManage(cr)` (mesma regra do §5.3; pública → sempre true).
- `onBeforeMount`/`mounted`: garantir `teams/get` (para resolver nomes de time e membership).

### 5.5 Compositor — nada a fazer ✅
`CannedResponse.vue` (picker `/`) e `CannedResponseModal.vue` consomem `getCannedResponses` via
`getCannedResponse` → o `index` já filtrado por `with_visibility`. A visibilidade é respeitada
automaticamente. Não filtrar no front.

### 5.6 Store / API — nada estrutural
`store/modules/cannedResponse.js` e `api/cannedResponse.js` são genéricos: create manda o objeto
inteiro; update encaminha `updateObj`; `buildPayload` faz append genérico (inclui multipart). Só
conferir que `visibility`/`team_id` chegam no payload (vêm do submit dos modais). Sem cache a
invalidar.

### 5.7 i18n (`cannedMgmt.json` — en E pt_BR)
`cannedMgmt.json` tem blocos **separados** `ADD.FORM` e `EDIT.FORM` e **não** tem um `FORM`
compartilhado (diferente de Labels, que tem um `FORM` único). Como o `CannedVisibilityField` é **um**
componente usado nos dois modais, ele precisa de **um único caminho i18n** — então **NÃO duplicar** em
`ADD.FORM`/`EDIT.FORM`. Em vez disso, **criar um bloco novo, compartilhado, no topo** do `CANNED_MGMT`
(irmão de `LIST`/`ADD`/`EDIT`/`DELETE`):

```
CANNED_MGMT.VISIBILITY {
  LABEL,
  EVERYONE { LABEL, DESCRIPTION },
  PERSONAL { LABEL, DESCRIPTION },
  TEAM     { LABEL, DESCRIPTION },
  TEAM_SELECT { LABEL, PLACEHOLDER, REQUIRED_ERROR },
  NO_MANAGE_PERMISSION
}
```
Mais `CANNED_MGMT.LIST.TABLE_HEADER.VISIBILITY` (esse vai sob `LIST.TABLE_HEADER`, que já existe).
Conteúdo espelha o bloco de Labels (`labelsMgmt.json:40-63`). Display: "Pública/Privada/De um time"
(pt_BR), "Public/Private/Team" (en). Tooltip curto por opção. Adicionar em **ambos** os locales
(en + pt_BR) mantendo as duas árvores idênticas em estrutura.

---

## 6. Casos de borda / atenção

1. **Compositor escopado** — um agente **não** verá/inserirá respostas privadas de outro nem de-time
   de time que não participa (decisão travada). Pública e as próprias sempre aparecem.
2. **Respostas legadas** (`created_by_id = NULL`, públicas) — **conteúdo** editável por qualquer agente
   (modelo permissivo) → **ninguém perde acesso** ao migrar. Este é o ganho do modelo permissivo.
2b. **Sequestro de pública (fechado)** — sem guard, qualquer agente poderia mudar uma pública
   compartilhada para privada/de-time e sumir com ela do catálogo dos outros (numa legada órfã,
   viraria `personal + created_by nil` = invisível a todos). O `validate_visibility_change` (§4.2)
   restringe a **troca de visibilidade** de uma `everyone` a autor+admin. Editar conteúdo segue livre.
3. **Time apagado** — §3.3 rebaixa canned de-time para pública. Sem respostas fantasma.
4. **Membership perdida** — sai do time → deixa de ver as canned de-time daquele time (esperado).
5. **Anexos + multipart** — `visibility`/`team_id` passam pelo `buildPayload` genérico; confirmar
   `team_id` vazio → nil no permit (não persistir string vazia como team_id).
6. **Unicidade `short_code`** — mensagem genérica no i18n (privada de outro é invisível → conflito
   "fantasma"). Documentar no PR.
7. **Sem `:show`** — não criar rota nem `show?`; o `check_authorization` é só `[:update, :destroy]`.

---

## 7. Testes

### Model `spec/models/canned_response_spec.rb` (CRIAR)
- `enum visibility` + `_prefix`.
- validação `team_id` presente sse `visibility_team?`; ausente caso contrário; team da mesma conta.
- `CannedResponse.with_visibility(user, base)`:
  - admin vê tudo;
  - agente vê `everyone` + suas `personal` + `team` dos seus times;
  - agente **não** vê `personal` de outro nem `team` de time que não participa;
  - compõe com uma `base` já filtrada por busca (passar um scope e checar interseção).
- `rebase_team_canned_responses` (cleanup do Team): resposta de-time vira `everyone`/`team_id: nil`
  ao apagar o time. **Removê-lo do funil antes** (`team.funnels.destroy_all`) ou stubar
  `Kanban::CreateFunnelForTeamService`, senão `team.destroy!` estoura a FK `funnels→teams` antes do
  callback (ver §3.3).

### Request `spec/controllers/api/v1/accounts/canned_responses_controller_spec.rb` (ATUALIZAR — JÁ VERMELHO)
- **Este spec já falha 2 exemplos na branch** (o `serialize` do fork adiciona `attachments`, que o
  `as_json` cru comparado nas linhas ~28 e ~45-47 não tem). Reescrever essas asserções para checar os
  campos do `serialize` (incluindo `visibility`/`created_by`/`team_id`) — não `as_json` cru. Deixar
  esses 2 verdes já faz parte da F2 (não é regressão sua).
- `index` filtrado por visibilidade (admin vs 2 agentes em times diferentes; com e sem `?search=`).
- `create` por agente: pública (default), privada, de-time (membro) → 200; de-time de time não-membro
  → 403 (a menos que admin). `created_by` setado.
- `update`/`destroy`:
  - **pública** com CONTEÚDO editado por **qualquer agente** (não-autor) → 200 (modelo permissivo!);
  - autor edita a própria privada → 200; **não-autor** edita **privada de outro** → 403;
  - membro do time edita de-time → 200; não-membro → 403;
  - legada (órfã, pública) com conteúdo editado por agente → 200.
- **Guard de transição de visibilidade** (`validate_visibility_change`):
  - não-autor tenta mudar uma **pública** para `personal`/`team` → **403** (não "sequestra" a compartilhada);
  - autor muda a própria pública para privada → 200; admin muda qualquer uma → 200;
  - órfã pública → só admin re-escopa (agente não-autor → 403).
- Regressão: agente segue criando/listando (não perdeu acesso ao conteúdo).

### Factory `spec/factories/canned_responses.rb` (ESTENDER)
- default `visibility :everyone`; traits `:personal`, `:team_visible` (com `team`), `:created_by`.

### Frontend
- Se houver specs de componente para os modais/Index: seletor renderiza; `team_id` obrigatório quando
  "De um time"; botões de gestão condicionados a `canManage` (pública sempre gerenciável).

---

## 8. Ordem de execução sugerida (fases pequenas, verde a cada passo)

- **F1 — Dados/Model**: migration + `CannedResponse` (enum `_prefix`, associações, validações,
  `with_visibility(base)`) + `rebase_team_canned_responses` no Team + `spec/models/canned_response_spec.rb`.
  Rodar `rspec spec/models/canned_response_spec.rb`.
- **F2 — API**: criar `CannedResponsePolicy` + wiring no controller (`check_authorization` instância,
  `validate_team_membership`, `validate_visibility_change`, `with_visibility` no `canned_responses`,
  `created_by` no create, `serialize` com campos novos, permit) + **atualizar** o request spec (2
  exemplos **já vermelhos** + cobrir visibilidade e guard de transição). Rodar specs de controller + `rubocop`.
- **F3 — Front settings**: `CannedVisibilityField.vue` + seletor nos dois modais (Add/Edit, validações
  inline) + coluna/insígnia + gating `canManage` no `Index.vue` + i18n (ADD.FORM e EDIT.FORM, en+pt_BR).
  Rodar `eslint`.
- **F4 — Compositor**: confirmar (sem código) que o picker `/` e o modal já respeitam a visibilidade
  (index filtrado). QA manual.
- **F5 — Validação staging** (nicolas.chatspx.app): `assets:precompile` +
  `sudo /bin/systemctl restart chatwoot.target`. Testar com um **agente** e um **admin**, em 2 times
  distintos, incluindo o picker `/` no compositor. Nunca testar em produção/frota.

Commit ao fim de **cada** fase (padrão do fork). Sem feature flag → vai a todos no deploy.

---

## 9. Checklist de "pronto"

- [ ] Agente cria/edita/exclui suas respostas prontas (mantido) + escolhe visibilidade.
- [ ] Seletor Pública/Privada/De-time no cadastro, com seleção de time.
- [ ] Privada só aparece para o autor; de-time só para membros; pública para todos — no settings
      **e no seletor `/` do compositor**.
- [ ] Pública (conteúdo) editável por qualquer agente (modelo permissivo); privada só autor/admin; de-time membro/admin.
- [ ] Trocar a visibilidade de uma pública restrito a autor/admin (`validate_visibility_change` → 403 p/ não-autor).
- [ ] Respostas legadas continuam editáveis por agentes (públicas órfãs) — ninguém perdeu acesso.
- [ ] Time apagado não deixa resposta fantasma.
- [ ] `CannedResponsePolicy` criada; controller autoriza a **instância**; guard de time dá 403.
- [ ] Request spec corrigido (não quebra por `as_json`) + model spec novo; build/lint verdes.
- [ ] Copy PT-BR + EN (em ADD.FORM e EDIT.FORM).
- [ ] Validado no staging com agente + admin, incluindo o compositor.

---

### Referências rápidas de arquivos
```
Backend
  app/models/canned_response.rb
  app/models/label.rb / macro.rb                 # PRECEDENTES
  app/policies/canned_response_policy.rb          # CRIAR
  app/policies/label_policy.rb / macro_policy.rb  # PRECEDENTES
  app/controllers/api/v1/accounts/canned_responses_controller.rb
  app/controllers/api/v1/accounts/labels_controller.rb   # PRECEDENTE (authorize instância, guard)
  app/controllers/api/base_controller.rb          # check_authorization autoriza a CLASSE
  app/models/team.rb                              # before_destroy :rebase_team_labels (estender)
  config/routes.rb:110                            # sem :show
  db/migrate/<novo>.rb ; db/schema.rb:318-326
Frontend
  app/javascript/dashboard/routes/dashboard/settings/canned/{canned.routes.js,Index.vue,AddCanned.vue,EditCanned.vue}
  app/javascript/dashboard/routes/dashboard/settings/canned/CannedVisibilityField.vue   # CRIAR
  app/javascript/dashboard/routes/dashboard/settings/labels/{LabelVisibilityField.vue,Index.vue,AddLabel.vue,EditLabel.vue}  # PRECEDENTE
  app/javascript/dashboard/store/modules/cannedResponse.js ; api/cannedResponse.js
  app/javascript/dashboard/store/modules/teams/getters.js (getMyTeams/getTeam)
  app/javascript/dashboard/components/widgets/conversation/CannedResponse.vue           # picker /
  app/javascript/dashboard/components-next/canned-response/CannedResponseModal.vue      # modal
  app/javascript/dashboard/composables/useAdmin.js
  app/javascript/dashboard/i18n/locale/{en,pt_BR}/cannedMgmt.json
Specs
  spec/models/canned_response_spec.rb             # CRIAR
  spec/controllers/api/v1/accounts/canned_responses_controller_spec.rb   # ATUALIZAR (frágil)
  spec/factories/canned_responses.rb              # ESTENDER
```
