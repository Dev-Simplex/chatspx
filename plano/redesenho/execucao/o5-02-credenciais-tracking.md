# Bloco 5.02 (metade (a): CÓDIGO) — cofre de credenciais de rastreio

**Worktree:** `/home/chatwoot/chatwoot-spx-cred-tracking` · **Branch:** `spx-cred-tracking`
**Base:** `homologacao` (`7b4ad0a371`) · **Data:** 24/08/2026

**ACEITE da tabela mestra:** *"Segredo nunca volta em claro; `verify` testa em modo teste sem
gravar evento real"* — **atendido**, e cada metade provada por um teste que fica VERMELHO sem a
proteção correspondente (§4).

---

## 0. Duas coisas achadas antes da primeira linha de código

### 0.1 A worktree estava 1.556 commits atrás da base que a task nomeia

A task diz *"Repo base: `/home/chatwoot/chatwoot`, branch `homologacao`, HEAD `7b4ad0a371`"*. A
worktree estava em `6a7cbcf5ba` — **ancestral** de `homologacao`, 1.556 commits atrás, e **sem o
bloco 0.10**: `config/application.rb` tinha só o `encryption_configured?` do upstream, sem o bloco
`config.active_record.encryption.*` que o 0.10 acrescentou.

Escrever o 5.02 ali teria produzido código que passa no teste local e **grava segredo em claro na
frota**, porque a configuração de cifra não existiria. Como a branch não tinha nenhum commit
próprio (`git rev-list --count 7b4ad0a371..6a7cbcf5ba` = 0) e a árvore estava limpa, alinhei com
`git reset --hard homologacao`. Nada foi perdido.

Reportei ao coordenador; ele conferiu e as três worktrees já estão em `7b4ad0a371`.

### 0.2 O pré-requisito 0.10, conferido e não presumido

```
RAILS_ENV=test bundle exec rails runner 'puts Chatwoot.encryption_configured?'  # => true
```

---

## 1. O que foi entregue

| Arquivo | Papel |
|---|---|
| `db/migrate/20260824120000_create_tracking_credentials.rb` | tabela, UNIQUE por inbox, FKs `on_delete: :cascade` |
| `app/models/tracking_credential.rb` | `encrypts` por segredo, `SECRET_ATTRIBUTES`, `secret_summary`, validações |
| `enterprise/app/models/enterprise/audit/tracking_credential.rb` | `audited ... except:` os 4 segredos |
| `app/services/tracking_credentials/verifier.rb` | `verify` em modo teste, cliente HTTP injetável |
| `app/controllers/.../inboxes/tracking_credentials_controller.rb` | `show`, `update` (upsert), `verify` |
| `app/policies/tracking_credential_policy.rb` | só administrador |
| `app/views/.../tracking_credentials/*.jbuilder` | serialização mascarada |
| `config/routes.rb` | `resource :tracking_credential` + `post :verify` (só linhas novas) |
| `config/locales/{en,pt_BR}.yml` | 15 chaves novas em `errors.tracking_credential` (só chaves novas) |

### 1.1 Por que tabela própria, e não o jsonb da inbox

A configuração pública do 5.01 mora em `inbox.additional_attributes['widget_tracking']`, que é
**servida ao navegador** em dois lugares. Segredo que morasse junto vazaria no dia em que alguém
serializasse o hash inteiro — que é o antipadrão que esta base já tem em
`webhooks/_webhook.json.jbuilder:6`. Separar torna o vazamento **impossível por construção**, em
vez de depender de cada serializador lembrar de filtrar.

### 1.2 A serialização

O jbuilder **não sabe** devolver segredo: ele varre `SECRET_ATTRIBUTES` e chama `secret_summary`,
que devolve `{ configured:, last_four: }`. Campo de segredo novo no modelo já nasce mascarado, e
não há como acrescentar um e esquecer de mascará-lo.

`last_four` devolve os **4 últimos caracteres puros** (`"9876"`), não `"…9876"` — o `…` é
apresentação e fica com a Tela 4 (bloco 5.06). Abaixo de `MIN_SECRET_LENGTH` (8) devolve `nil`, e
não um pedaço: sem esse piso um segredo de 5 caracteres voltaria quase inteiro.

### 1.3 `encrypts`: uma declaração por campo, e NÃO determinístico

Li o achado de `onda-0-infra-0.4-0.10-EXECUTADO.md` antes de declarar. **Não preciso de
determinismo** — nenhuma consulta busca inbox por valor de segredo, o acesso é sempre pela inbox —
então usei cifra não determinística, que é a mais forte: com IV aleatório, duas inboxes que usem o
mesmo token produzem ciphertext diferente, e ninguém descobre que compartilham credencial olhando
o banco. Dois testes travam a escolha (§4, itens do `describe 'criptografia em repouso'`).

Como não uso `deterministic: true`, a prova de estabilidade de `to_sql` **não se aplica** a este
bloco. O que provo no lugar é o oposto, e está medido: `scheme.deterministic?` é `false` nos
quatro campos, e o mesmo valor em duas linhas gera ciphertext diferente.

### 1.4 Sem a guarda `if Chatwoot.encryption_configured?`

`Integrations::Hook` declara `encrypts ... if Chatwoot.encryption_configured?`. Faz sentido lá — é
campo legado com linhas em claro no banco. Aqui a tabela **nasce vazia**, e a mesma guarda faria um
ambiente sem chaves gravar o access token da Meta **em claro, em silêncio**. Troquei por uma
validação que **recusa** a gravação nesse caso: falhar alto é a saída certa quando a alternativa é
vazar.

### 1.5 `verify` sem gravar evento real

Cada provedor usa o caminho de teste **oficial**, e o serviço se recusa a rodar quando ele não está
disponível:

- **Meta** — `test_event_code` no payload manda o evento para o Test Events e o mantém fora da
  produção. **Sem o código, `verify` recusa** em vez de mandar assim mesmo. É a diferença entre
  testar e sujar o relatório de campanha do cliente com uma conversão que nunca aconteceu.
- **GA4** — `POST /debug/mp/collect`, que valida e **não grava**. Cuidado necessário: esse endpoint
  responde `200` mesmo para payload inválido; quem diz se passou é `validationMessages`. Tratar o
  200 como sucesso aprovaria credencial errada — há teste para isso.

O cliente HTTP é injetável (`client:`), então **nenhum spec toca a rede**.

### 1.6 O vazio que apagava credencial

Apliquei no `update` a mesma defesa que `Integrations::Hook` precisou: segredo que chega `''` **não
apaga** o valor gravado. A tela nunca recebe o valor (só `last_four`), então um vazio vindo dela é
resíduo de formulário, jamais intenção de apagar. Sem essa guarda o teste fica vermelho e a
credencial some com `200 OK` (§4, prova 2).

---

## 2. O que ficou de fora, e por quê

### 2.1 A metade (b) — OAuth de um clique — NÃO foi feita, como a task determina

Exige app registrado na Meta (Facebook Login for Business) e no Google, que é **cadastro do dono**.
A interface está pronta para recebê-la sem nova migration:

- colunas cifradas `google_ads_refresh_token` e `google_ads_developer_token` já existem;
- `oauth_metadata` (jsonb) existe para escopo concedido, expiração e id da conta de anúncios —
  metadado **não sensível**; o token vai nas colunas cifradas;
- `SECRET_ATTRIBUTES` já cobre os dois campos do Google, então eles já saem mascarados na API e já
  estão fora da auditoria.

**Falta, e é externo ao código:** app registrado na Meta com a permissão `ads_management` revisada;
projeto no Google Cloud com OAuth consent screen publicado e Google Ads **developer token**
aprovado; as URLs de callback registradas nos dois. Enquanto isso não existir, não há o que
implementar sem inventar credencial.

### 2.2 `has_one :tracking_credential` em `app/models/inbox.rb`

Seria uma linha, mas o arquivo é de outra trilha agora. O controller usa
`TrackingCredential.find_or_initialize_by(inbox:)`, com **o mesmo comportamento**: a cardinalidade
é garantida pelo UNIQUE em `inbox_id` e a limpeza pela FK `on_delete: :cascade`, ambos no banco.
Recomendo acrescentar a associação quando a trilha dona do arquivo puder — é conveniência, não
correção.

### 2.3 A leitura do id público tolera o 5.01 não existir

`verify` lê Pixel ID e Measurement ID de `inbox.additional_attributes['widget_tracking']`, que é do
bloco **5.01 (não executado)**. Lido com `dig`, o campo volta `nil` e o operador recebe *"configure
o Pixel ID antes de testar"* em vez de um `NoMethodError`. Quando o 5.01 chegar, liga sozinho.

---

## 3. Como rodei

```
cp /home/chatwoot/chatwoot/.env .                       # worktree não tem .env
export POSTGRES_DATABASE=chatwoot_test_spx_cred          # banco dedicado, não o compartilhado
RAILS_ENV=test bundle exec rails db:create db:schema:load
RAILS_ENV=test bundle exec rails db:migrate
```

| Comando | Resultado |
|---|---|
| `rspec spec/models/tracking_credential_spec.rb spec/services/tracking_credentials/verifier_spec.rb spec/controllers/api/v1/accounts/inboxes/tracking_credentials_controller_spec.rb` | **36 examples, 0 failures** |
| `rspec spec/controllers/api/v1/accounts/inboxes_controller_spec.rb spec/controllers/api/v1/accounts/inboxes/assignment_policies_controller_spec.rb` (regressão das rotas) | **98 examples, 0 failures** |
| `rubocop` nos 11 arquivos tocados | **no offenses detected** |
| `RAILS_ENV=test bundle exec rails runner 'puts 1'` (boot, pedido pelo coordenador) | **1** |

`N > 0` em todos: a contagem está acima, não é "sem falhas" com zero exemplos.

---

## 4. As quatro provas de vermelho

Um teste que afirma ausência (*"não contém o segredo"*, *"não chamou"*) passa também quando o
sujeito nunca existiu. Quebrei cada proteção e registrei a falha:

| # | Proteção removida | Falha observada |
|---|---|---|
| 1 | jbuilder passa a devolver `resource[attribute]` | `expected "...\"meta_access_token\":\"EAAmeta-access-token-que-nao-pode-vazar-9876\"..." not to include "EAAmeta-access-token-que-nao-pode-vazar-9876"` |
| 2 | `update_params` deixa de descartar o segredo vazio | `expected: "EAAmeta-...-9876"` / `got: ""` — a credencial foi **apagada** com `200 OK` |
| 3 | `except:` sai do `audited` | `expected ["meta_access_token", "meta_test_event_code"] not to include "meta_access_token"` — o segredo ia para `audits` |
| 4 | some a guarda do `test_event_code` | `expected: 0 times with any arguments` / `received: 1 time` — o serviço **chamou a Meta**, gravando evento real |

Além disso, cada asserção de ausência tem um **controle** ao lado que prova que o sujeito existe:
`expect(credential.reload.meta_access_token).to eq(secret)` antes do `not_to include`, e
`expect(changes).to have_key('meta_test_event_code')` antes do `not_to include` da auditoria. Sem
esses controles, os testes mediriam zero.

**Uma correção que os controles pegaram:** a prova 4, na primeira tentativa, ficou vermelha pelo
motivo errado (`undefined method 'code' for nil`, porque o dublê devolvia `nil`) — o que esconderia
a regressão real. Reordenei a asserção para que `expect(client).not_to have_received(:post)` venha
**primeiro**, e a falha passou a apontar o fato que importa.

---

## 5. Detalhe do ambiente que outra trilha vai encontrar

Nesta base, **Pundit negado responde `401`, não `403`** — e o corpo é a única coisa que distingue
"não entrou" de "entrou e a policy negou":

- não autenticado → `{"errors":["Você precisa entrar ou se cadastrar antes de continuar."]}`
- policy negou → `{"error":"You are not authorized to do this action"}`

Um spec que só olhasse o status passaria mesmo se a policy nunca fosse consultada. Os meus asseram
a **chave do corpo**.
