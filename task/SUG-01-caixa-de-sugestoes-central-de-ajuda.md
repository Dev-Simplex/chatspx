# SUG-01: Caixa de sugestões na Central de Ajuda + painel no Super Admin

**Responsável:** Nicolas Silva
**Origem:** pedido do dono em 28/09/2026. Mockup aprovado: https://nicolas.chatspx.app/caixa-de-sugestoes.html (abas **A** e **C**; cópia em `task-chat spx/SUG-01-mockup-caixa-de-sugestoes.html`).
**Parte 1 de 2.** O link público é a **SUG-02**, que só começa depois que esta estiver mergeada na `producao`.
**Branch:** sair de `producao`, 1 PR, Conventional Commits. Rodar `bundle exec rubocop -a` e `pnpm eslint`.
**Fluxo:** staging nicolas → validar → PR. Não deployar na frota.

---

| | |
|---|---|
| Tipo | FEATURE |
| Valor | O usuário logado manda ideias de melhoria à Simplex pela Central de Ajuda, e a Simplex lê tudo no Super Admin. |
| Já existe? | Não. Não há nada de sugestão ou feedback além do CSAT. |
| Esforço | médio: 1 tabela, 2 controllers, 1 tela Vue, 1 tela Administrate |
| Obrigatório | **Tudo responsivo, no celular (~375px) e no notebook (1366px).** |
| Base para a SUG-02 | A tabela já nasce com a origem `public_link`, para que a SUG-02 **não precise de migration**. |

---

## Requisitos aprovados

1. **Dentro do sistema (A):** um item novo, **"Sugerir melhoria"**, no grupo **Central de Ajuda** do menu lateral.
   - Tem um campo de sugestão (obrigatório) e um anexo opcional (foto ou vídeo, até 100 MB).
   - Nome e empresa vêm do login: `current_user.name` e `Current.account.name`.
   - Embaixo fica a lista **"Minhas sugestões"**, com data, texto, anexo e status.
   - O item aparece **mesmo com a flag `help_center` desligada**. Só o item novo; os filhos de Portais continuam como estão.
2. **Painel Simplex (C):** a tela **Sugestões** no **Super Admin** mostra as sugestões de todas as contas.
   - Colunas: data, origem, nome, empresa, conta, texto, anexo (link para abrir/baixar) e status.
   - Filtros: todas, novas, do sistema e do link. O filtro do link fica vazio até a SUG-02 entrar.
   - O status (Nova / Lida / Planejada / Feita) é editável e aparece para o usuário em "Minhas sugestões".
3. **Fora da v1:** votos, resposta ao usuário pelo painel e aviso por e-mail.

---

## Implementação

### 1. Modelo e migration
Arquivo `db/migrate/<ts>_create_suggestions.rb`:
```ruby
create_table :suggestions do |t|
  t.references :account, null: true, foreign_key: { on_delete: :nullify }
  t.references :user, null: true, foreign_key: { on_delete: :nullify }
  t.string :name, null: false
  t.string :company, null: false
  t.text :content, null: false
  t.integer :source, null: false, default: 0   # in_app | public_link (a SUG-02 usa)
  t.integer :status, null: false, default: 0   # nova | lida | planejada | feita
  t.timestamps
end
add_index :suggestions, :created_at
add_index :suggestions, :status
```
- `account_id` e `user_id` são nullable **de propósito**:
  - o link público da SUG-02 não tem conta;
  - sugestão de conta apagada continua valendo, e isso não pode travar a exclusão da conta (lição do T07).
- **Confira o `schema.rb`**: a versão tem de ser a timestamp mais alta. Prove com `db:schema:dump`.

Arquivo `app/models/suggestion.rb`:
- `belongs_to :account, optional: true`, `belongs_to :user, optional: true`.
- `enum source: { in_app: 0, public_link: 1 }` e `enum status: { nova: 0, lida: 1, planejada: 2, feita: 3 }`.
- `has_one_attached :media`.
- Validações:
  - `content`, `name` e `company` com presence; `content` com `length: { maximum: 5000 }`.
  - O anexo aceita só `image/*` ou `video/*` e ≤ 100 MB. Use uma validação simples no modelo, no molde de `Attachment#validate_file_size` (`app/models/attachment.rb`). A SUG-02 reaproveita essa mesma validação.
- No `Account` e no `User`, acrescente `has_many :suggestions, dependent: :nullify`.

### 2. API da conta
**Rota** (`config/routes.rb`, dentro de `namespace :accounts`): `resources :suggestions, only: [:index, :create]`.

**Controller** `app/controllers/api/v1/accounts/suggestions_controller.rb` (`< Api::V1::Accounts::BaseController`):
- `index`: `Current.account.suggestions.where(user: Current.user).order(created_at: :desc).limit(50)`.
- `create`: `source: :in_app`, `name: Current.user.name`, `company: Current.account.name`, `content` e `media` vindos do params (multipart).
- Qualquer membro da conta pode enviar. **Não** crie policy de admin.
- JSON em jbuilder (`app/views/api/v1/accounts/suggestions/`): `id, content, status, created_at, media_url, media_filename`.

### 3. Tela na Central de Ajuda
- API: `app/javascript/dashboard/api/suggestions.js`, com `ApiClient` e `create` via `FormData`.
- Rota: em `routes/dashboard/helpcenter/helpcenter.routes.js`, crie a rota `suggestions_new` em `/accounts/:accountId/suggestions`, **sem `meta.featureFlag`** e com permissões `['administrator', 'agent', 'custom_role']`. Fica fora do grupo que exige `HELP_CENTER`.
- Página: `routes/dashboard/helpcenter/pages/SuggestionsPage.vue`, em `<script setup>`, só com Tailwind e usando os componentes de `components-next` (Button, TextArea, arquivo).
  - **Notebook:** conteúdo em `max-w-2xl`, com o botão Enviar à direita.
  - **Celular:** largura total, com o botão ocupando a linha toda (`w-full sm:w-auto`). A lista "Minhas sugestões" quebra o texto sem rolagem lateral.
- Menu: em `components-next/sidebar/Sidebar.vue`, grupo `Portals` (~l.430), acrescente o filho `{ name: 'Suggestions', label: t('SIDEBAR.HELP_CENTER.SUGGESTIONS'), to: accountScopedRoute('suggestions_new') }`.
  - **Atenção:** o `components-next/sidebar/provider.js` esconde o item pela `featureFlag` da rota. Confira que o grupo Central de Ajuda aparece mesmo com `help_center` desligado e que ali só o filho novo fica visível.
  - Se o grupo sumir inteiro, a saída mínima é deixar os filhos de Portais com `featureFlag` e o grupo sem.
- Upload: reaproveite `checkFileSizeLimit` (`dashboard/mixins/fileUploadMixin.js`) ou a mesma regra num composable, com 100 MB.

### 4. Painel no Super Admin
- **Rota:** em `namespace :super_admin`, depois de `platform_apps`, acrescente `resources :suggestions, only: [:index, :show, :edit, :update]`. A ordem define a posição no menu lateral.
- **Controller** `app/controllers/super_admin/suggestions_controller.rb` (`< SuperAdmin::ApplicationController`).
- **Dashboard** `app/dashboards/suggestion_dashboard.rb`, no molde de `platform_app_dashboard.rb`:
  - Campos: `created_at`, `source`, `name`, `company`, `account`, `content`, `media`, `status`.
  - Só `status` entra em `FORM_ATTRIBUTES`.
  - Ordenação padrão: `created_at desc`.
  - Filtros via `COLLECTION_FILTERS`: `nova`, `in_app` e `public_link`.
- **Anexo:** um campo simples que renderize um link para `rails_blob_url(media)`. Se o Administrate não tiver campo pronto, crie um field mínimo em `app/fields/`.
- **Ícone** em `app/views/super_admin/application/_navigation.html.erb`: `suggestions: 'icon-lightbulb-line'` ou o que existir no sprite.

### 5. i18n
- Crie as chaves `SIDEBAR.HELP_CENTER.SUGGESTIONS` e `SUGGESTIONS.*` em `en.json`, e as mensagens do modelo em `en.yml`.
- O fork mostra pt_BR, então replique também em `pt_BR`. **Nenhuma string solta.**
- Cuidado com as armadilhas conhecidas: namespace de topo ≠ sub-chave, e `t('X') || 'reserva'` nunca funciona.

---

## Como validar (staging nicolas)

1. **Notebook (1366px)**, conta cobaia (id 11): Central de Ajuda → Sugerir melhoria. Envie só com texto, depois com um print. As duas aparecem em "Minhas sugestões" como **Nova**.
2. Tente enviar com a sugestão vazia: aparece o erro e nada é gravado. Um arquivo `.pdf` é recusado.
3. Repita numa conta **com `help_center` desligado**: o item tem de aparecer.
4. **Celular (375px, DevTools e um aparelho de verdade):** a mesma tela, sem rolagem lateral e com o botão Enviar ocupando a linha toda.
5. **Super Admin → Sugestões:** as sugestões acima aparecem com a origem **Sistema** e a conta. Os filtros funcionam e o anexo abre.
6. Mude uma sugestão para **Planejada** e confira que o status aparece em "Minhas sugestões" da conta.
7. Apagar uma conta criada **só para o teste** não apaga as sugestões dela: a coluna conta fica vazia. *Nunca faça isso na conta 1 nem na 11.*
8. Rode `bundle exec rspec` nos specs novos e confira `rubocop` e `eslint` limpos.

## Specs (mínimos)
- `spec/models/suggestion_spec.rb`: validações e o tipo do anexo.
- `spec/controllers/api/v1/accounts/suggestions_controller_spec.rb`: `create` e o `index` só com as minhas.
- Use `POSTGRES_DATABASE=chatwoot_test_promover`, porque o banco de teste é compartilhado com outras sessões.

## Cuidados
- Migration nova: **o restart na frota só às 20:00**. Isso não é para esta task (o ciclo para no PR).
- Enterprise: não há override de Portais nem de Super Admin que conflite. Mesmo assim, rode `rg -n "suggestion" enterprise` antes do PR.
