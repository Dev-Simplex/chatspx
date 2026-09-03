# Onda 0 — Auditoria de `app/views/`: o contrato de API e de e-mail

**Task:** A7 — o último buraco declarado pelo auditor de backend upstream
**Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **Branch:** `redesenho-merge`
**Bases:** NOSSO = `f26db6ee81` · MERGE = `6ad7a9ec6e`
**Modo:** somente leitura. Nenhum arquivo do worktree foi alterado.
**Status:** EM PRODUÇÃO — escrito incrementalmente conforme a medição avança.

---

## 0. Método (e por que ele não é leitura)

O briefing pediu medição, não leitura. Foi o que se fez:

1. **Escopo real medido**, não estimado:
   `git diff --name-status f26db6ee81 6ad7a9ec6e -- app/views/` → **97 arquivos**
   (o auditor de backend estimou 67; o número real é 97)
   `... -- enterprise/app/views/` → **34 arquivos** (estimou 43; real 34)
   **Total: 131 arquivos**, dos quais **58 são `.jbuilder`** (o contrato JSON).

2. **Extrator de chaves** (`scratchpad/jbkeys.py`): para cada `.jbuilder` tocado, lê o blob
   nos dois lados via `git show <rev>:<path>` e extrai o conjunto de chaves emitidas,
   reconhecendo as formas do DSL (`json.foo`, `json.set!`, `json.extract!`) e **marcando
   explicitamente como OPACO** o que regex não resolve (`json.merge!`, `partial!` dinâmico,
   `set!` dinâmico) — para que o relatório nunca afirme cobertura que não tem.

   **Validação do extrator** (obrigatória antes de confiar no número): rodado em
   `app/views/api/v1/models/_contact.json.jbuilder`, devolveu 13 chaves no lado NOSSO.
   Leitura manual do mesmo arquivo confere exatamente 13 (`additional_attributes`,
   `availability_status`, `email`, `id`, `name`, `phone_number`, `blocked`, `identifier`,
   `thumbnail`, `custom_attributes`, `last_activity_at`, `created_at`, `contact_inboxes`). ✔

   **Resultado da varredura: 0 (zero) construções OPACAS nos 58 arquivos.** Não há `merge!`
   nem `partial!` dinâmico em nenhum jbuilder tocado — logo a diferença de conjuntos é
   completa, não amostral.

3. **Segunda camada — mudança de VALOR, não de chave.** A diferença de conjuntos só pega
   chave que *desapareceu do arquivo*. O defeito mais perigoso desta superfície é outro:
   **a chave continua sendo emitida, com valor diferente ou condicionada a uma guarda nova.**
   Para isso houve leitura integral do diff dos 24 jbuilder `M` (modificados) — e é aí que
   está tudo o que importa neste relatório.

4. **Consumidor vivo:** `git grep` no `app/javascript/` do MERGE para cada chave/valor sob
   suspeita. Perda sem consumidor é dívida; perda com consumidor é defeito.

### Achado estrutural de cobertura, antes de tudo

O briefing manda priorizar `views/api/v1/widget/**` como 1º. **O merge não tocou nenhum
arquivo desse diretório:**

```
$ git diff --name-only f26db6ee81 6ad7a9ec6e -- app/views/api/v1/widget/ | wc -l
0
```

Os 11 jbuilder do widget estão intactos. **Mas isso não fecha a pergunta** — eles renderizam
por `json.partial!` os partials de `api/v1/models/**`, e *esses* mudaram. O contrato do widget
muda por dentro, sem o arquivo do widget aparecer em nenhum diff. Rastreado abaixo.

---

## 1. Chaves de API perdidas **COM CONSUMIDOR VIVO**

### 1.1 🔴 P0 — `settings` do hook de integração passou a ser filtrado no servidor, e a nossa tela de "Editar hook" **apaga a credencial no banco ao salvar**

**Arquivo do contrato:** `app/views/api/v1/models/_hook.json.jbuilder`

```diff
-json.settings resource.settings if Current.account_user&.administrator?
-json.reference_id resource.reference_id if Current.account_user&.administrator?
+if Current.account_user&.administrator?
+  visible_properties = resource.app&.visible_properties || []
+  settings = (resource.settings || {}).select { |key, _| visible_properties.include?(key.to_s) }
+
+  json.settings settings
+  json.reference_id resource.reference_id
+end
```

A chave `settings` **continua sendo emitida** — por isso nenhuma diferença de conjunto de chaves
a pega, nenhum teste de contrato de nível de chave falha, e nenhum erro aparece em log. O que
mudou é o **conteúdo**: antes o servidor devolvia o hash inteiro, agora devolve só as chaves
listadas em `visible_properties` do app.

#### Por que isso é defeito NOSSO e não do upstream

No upstream, `visible_properties` é seguro porque **o upstream não tem tela de editar hook**:

```
$ git cat-file -e v4.16.0:app/javascript/dashboard/routes/dashboard/settings/integrations/EditHook.vue
v4.16.0: NAO TEM (arquivo e 100% nosso)

$ git show -s --format="%an | %s" e406daad26
Paulo Seze | feat(integrations): UI de editar hooks declarativos (apps.yml)
```

`EditHook.vue` é nosso, está montado na UI (`IntegrationHooks.vue:147,156` → botão *Editar* por
hook), e **o merge não o tocou** (`git diff` do arquivo é vazio). Ele foi escrito sob o
pressuposto — verdadeiro até este merge — de que `hook.settings` vem completo:

```js
// EditHook.vue:48 — parseInitialValues()
const settings = this.hook?.settings || {};
formSchema.forEach(item => {
  const raw = settings[item.name];
  if (raw === undefined || raw === null) {
    values[item.name] = '';        // <<< chave filtrada pelo servidor => string VAZIA
    return;
  }
  ...
});

// EditHook.vue:73 — buildHookPayload()
const settings = {};
Object.keys(this.values).forEach(key => { settings[key] = this.values[key]; });
return { settings };               // <<< reenvia TODAS as chaves, inclusive as vazias
```

E o servidor **substitui o jsonb inteiro**, não faz merge:

```ruby
# app/controllers/api/v1/accounts/integrations/hooks_controller.rb:10
def update
  @hook.update!(permitted_params.slice(:status, :settings))
end
```

**Cadeia completa:** servidor filtra `api_key` → form recebe `undefined` → grava `''` no campo →
submit envia `settings: {api_key: '', ...}` → `update!` sobrescreve a coluna → **a credencial é
destruída no banco**. Sem erro, sem log, sem teste vermelho.

#### Superfície medida (mecanismo, não estimativa)

Cruzamento de `settings_form_schema` × `visible_properties` de `config/integration/apps.yml` no
MERGE (script no scratchpad, saída literal):

| App | Campos que o form NOSSO edita e reenvia | Perdidas na resposta → **apagadas ao salvar** |
|---|---|---|
| `openai` | `api_key`, `label_suggestion` | **`api_key`** |
| `dialogflow` | `project_id`, `credentials`, `region`, `language_code` | **`credentials`** (JSON da service account) |
| `google_translate` | `project_id`, `credentials` | **`credentials`** |
| `meta_lead_ads` | 11 campos | **`verify_token`, `app_secret`, `page_access_token`, `initial_message_template`, `whatsapp_template_name`, `whatsapp_template_locale`, `whatsapp_template_body_fields`** |
| `leadsquared` | 6 campos | **`access_key`, `secret_key`** |
| `dyte` | `account_id`, `app_id`, `api_token` | **`api_token`** |

**6 integrações, 14 chaves de credencial/config.** `meta_lead_ads` é a pior: perde os 3 segredos
(`app_secret`, `page_access_token`, `verify_token`) **e** os 4 campos de template de WhatsApp —
uma edição de "trocar o inbox de destino" desconecta a integração inteira.

#### Agravante: o merge também *encurtou* a lista do openai

Não é só o filtro que é novo — a lista encolheu do nosso lado para o deles:

| App | NOSSO `visible_properties` | MERGE `visible_properties` |
|---|---|---|
| `openai` | `['api_key', 'label_suggestion']` | `['label_suggestion']` |
| `dialogflow` | `['project_id', 'region']` | `['project_id', 'region', 'language_code']` |
| `dyte` | `['organization_id']` | `['account_id', 'app_id']` |

No NOSSO lado `visible_properties` **não era filtro de servidor** — era só a lista de colunas da
tabela em `MultipleIntegrationHooks.vue`. O merge reaproveitou o mesmo campo para uma segunda
finalidade (filtro de resposta) sem que ninguém revisasse se as duas finalidades pedem a mesma
lista. Elas não pedem: "coluna que aparece na tabela" e "chave que o form precisa para não
apagar o segredo" são conjuntos diferentes.

#### Sintoma secundário (pode mascarar o primário)

`openai.settings_form_schema` marca `api_key` como `'validation': 'required'`. Dependendo de como
o FormKit trata o campo obrigatório vazio, o submit pode ser **bloqueado** em vez de salvar — o
usuário vê "campo obrigatório" num campo que ele já preencheu no passado e cuja chave ele não
tem mais em mãos. Ou apaga, ou tranca. As duas são regressão; a segunda é menos destrutiva e
mais fácil de confundir com "bug de UI".

#### Correção recomendada (uma das três, em ordem de preferência)

1. **Servidor faz merge em vez de substituir** — `@hook.update!(settings: @hook.settings.merge(permitted_params[:settings]))`.
   Resolve na raiz e protege qualquer cliente futuro, não só a nossa tela.
2. **`EditHook.vue` não reenvia chave que não recebeu** — pular do payload as chaves cujo valor
   inicial veio `undefined` (o `ToolsView.vue` do Walisson já faz exatamente isso com
   `isMasked()`; é o padrão da casa, só não foi aplicado aqui).
3. Devolver `api_key`/`credentials` a `visible_properties` — **não recomendado**: reexpõe segredo
   na resposta da API, que é justamente o que o upstream foi corrigir.

**Recomendo (1) + (2)**: (1) fecha o buraco de dados, (2) evita a UI mostrar campo vazio onde há
valor gravado. Fora do escopo desta task (somente leitura) — vai para a lista de correções.


### 1.2 Candidatos investigados e **descartados** (por que não são defeito)

Registro explícito porque cada um destes *parece* defeito à leitura, e três deles chegaram a
entrar na lista antes de a verificação derrubá-los. Descartar com prova também é entrega.

| Mudança | Por que parecia perda | Por que **não** é |
|---|---|---|
| `_user.json.jbuilder`: `access_token` → `''` se `!accounts.any?(&:api_and_webhooks_enabled?)` | O Kanban do Nicolas usa `currentUser.access_token` como header `api_access_token` no DirectUpload (`ScheduledMessageForm.vue:291`). Token vazio = upload de anexo do agendamento quebrado | `Account#api_and_webhooks_enabled?` retorna `true` incondicional no CE (`account.rb:194`) e, no EE, `return true unless ChatwootApp.chatwoot_cloud?` (`enterprise/account.rb:76`). Nossa frota é self-hosted (`DEPLOYMENT_ENV != 'cloud'`) → **sempre true**. Token preservado |
| `_user.json.jbuilder`: nova chave `api_and_webhooks` por conta | O front esconde a seção Access Token com base nela; contas antigas não têm o bit ligado (`api_and_webhooks` vive em `feature_flags_ext_1`) | `profile/Index.vue:107` abre com `if (!this.isOnChatwootCloud) return true;` — em self-hosted a seção fica habilitada sem consultar a flag. Backend e front usam a mesma guarda de cloud. Coerente |
| `captain/_custom_tool.json.jbuilder`: `auth_config` só para `Current.user&.administrator?` | Padrão idêntico ao 1.1 — `CustomToolForm.vue:62` faz `state.auth_config = newTool.auth_config \|\| {}` e o `update!` aceita `auth_config: {}`. Um agente salvando apagaria a credencial da tool | `Captain::CustomToolPolicy#update?` exige `@account_user.administrator?` — **a mesma condição** da guarda de leitura no jbuilder. Quem não vê o `auth_config` também recebe 403 no update. Não existe janela. **É exatamente o contraste que torna o 1.1 um defeito:** lá a guarda de leitura (`visible_properties`) e a de escrita (`settings: {}` liberado) são condições *diferentes* |
| `_account.json.jbuilder`: `Enterprise::Billing::Currencies.enabled?` | `Account#billing_currency` existe no EE, logo o `respond_to?` não curto-circuita e a constante é avaliada em todo bootstrap do dashboard — `NameError` seria 500 no login | A constante existe: `enterprise/app/services/enterprise/billing/currencies.rb:2` (`module Enterprise::Billing::Currencies`). Meu primeiro grep procurou `module Currencies` e não casou com a forma compacta — **falso positivo meu**, corrigido antes de entrar no relatório |
| `captain/_custom_tool`: `Current.user&.administrator?` | `administrator?` é papel de `AccountUser`, não de `User` — `NoMethodError` derrubaria a lista de tools do Captain | Existe: `app/models/concerns/user_attribute_helpers.rb:34` → `current_account_user&.administrator?`. Também falso positivo do meu grep inicial |
| `assignable_agents/index.json.jbuilder`: `@agent_bots.map` e `json.assignee_type 'User' if @include_agent_bots` | `nil.map` → 500; e `assignee_type` não emitido no caso default deixaria o front sem discriminar tipo | Controller define ambos (`assignable_agents_controller.rb:6,16`): `@agent_bots = @include_agent_bots ? AgentBot.accessible_to(...) : []`. E `inboxAssignableAgents.js:27` só lê `record.assignee_type` sob `includeAgentBots && ...` — mesma condição do emissor |
| `_account.json.jbuilder`: `onboarding_step` saiu de `custom_attributes['onboarding_step']` para `resource.onboarding_step` | O método derivado pode devolver `'enrichment'`, valor que o front antigo não conhece | O jbuilder emite **dentro** do bloco `json.custom_attributes`, e `useAccountEnrichment.js:24` lê exatamente `custom_attributes?.onboarding_step === 'enrichment'`. As duas pontas vieram no mesmo merge. Coerente |
| `attachments.json.jbuilder`: 11 chaves removidas do arquivo | Maior perda de chaves da varredura inteira | Extraídas para o partial novo `api/v1/models/_attachment.json.jbuilder`, conferidas **uma a uma**: as 11 estão lá. A única troca é `json.id attachment.id` → `attachment_data[:id]`, e `Attachment#base_data` (`attachment.rb:170`) inclui `id: id` — mesmo valor |

### 1.3 🟡 P2 — `reauthorization_required` do WhatsApp deixa de avisar em canal criado à mão

`app/views/api/v1/models/_inbox.json.jbuilder`:

```diff
-  json.reauthorization_required resource.channel.try(:reauthorization_required?)
+  # Only show reauthorization for embedded signup; manual flow uses API keys, not OAuth
+  json.reauthorization_required(
+    (resource.channel.try(:provider_config) || {}).to_h['source'] == 'embedded_signup' &&
+    resource.channel.try(:reauthorization_required?)
+  )
```

Consumidores vivos: `ChannelLeaf.vue:32` (alerta na sidebar por canal) e `Settings.vue:355,370` (banner).

`source == 'embedded_signup'` só é gravado pelo fluxo de autorização OAuth
(`whatsapp/authorizations_controller.rb:56`). Os canais WhatsApp da frota criados manualmente
(Cloud API por token, 360dialog, WAHA/Evolution) **não têm esse `source`** → a expressão vira
`false` fixo. Quando o token expirar, o alerta na sidebar e o banner **não aparecem mais**.

Não é perda de contrato (a chave continua lá, com tipo `false` em vez de `nil`) e a intenção do
upstream é legítima — o fluxo manual não se reautoriza por OAuth, então o antigo banner mandava o
usuário para um lugar que não resolvia. Mas o efeito líquido na frota é **um diagnóstico a menos
no canal mais usado**. Registro como P2 para decisão de produto, não como correção obrigatória:
se quisermos o aviso de volta, ele precisa de um destino próprio para o fluxo manual ("seu token
expirou, gere outro no Meta Business"), não do banner de OAuth.

### 1.4 🟢 Mudança de comportamento sem perda: `sla_policy_id` de contato bloqueado

`app/views/api/v1/conversations/partials/_conversation.json.jbuilder` e o par enterprise passam a
zerar SLA quando `!conversation.sla_applicable?` — que é `!contact&.blocked?`
(`enterprise/app/models/enterprise/concerns/conversation.rb:41`). Consumidor:
`ConversationHeader.vue:196` (`applied_sla?.id || sla_policy_id`) deixa de mostrar o indicador em
conversa de contato bloqueado. Intencional e correto. O par CE usa
`!conversation.respond_to?(:sla_applicable?) || ...`, então não quebra em CE puro.

Sobre `contact.blocked` ser `nil` em registros antigos (pendência conhecida da triagem GlitchTip):
`!nil` → `true` → SLA aplicável, comportamento idêntico ao anterior. Sem risco.

---

## 2. Chaves perdidas **SEM consumidor** (dívida, não defeito)

### 2.1 `Company`: `created_at`/`updated_at` mudaram de tipo e ficaram condicionais

`enterprise/app/views/api/v1/accounts/companies/_company.json.jbuilder` foi **removido** e o
partial passou a viver em `enterprise/app/views/api/v1/models/_company.json.jbuilder`, com os 5
callers reapontados (`create`, `index`, `search`, `show`, `update`) de `'company'` para
`'api/v1/models/company'`. Nenhuma chave desapareceu; ganharam-se `custom_attributes` e
`last_activity_at`. Mas o **tipo** de duas mudou:

```diff
-json.created_at company.created_at          # Time -> string ISO-8601 no JSON
-json.updated_at company.updated_at
+json.created_at resource.created_at.to_i if resource[:created_at].present?   # -> epoch Integer, e condicional
+json.updated_at resource.updated_at.to_i if resource[:updated_at].present?
```

Um cliente que fizesse `new Date(company.created_at)` passa a receber um inteiro. **Não há tal
cliente:** `git grep created_at\|updated_at -- app/javascript/dashboard/routes/dashboard/companies/`
não retorna nada, e a feature está `enabled: false` + `premium: true` em `config/features.yml:225`
— dormente na frota. Fica registrado como dívida para quando Companies for ligada.

Nota de consistência: o novo formato (`.to_i`, condicional em `resource[:x].present?`) é o mesmo
padrão de `_contact.json.jbuilder`, então a mudança é uniformização, não capricho.

### 2.2 Nada mais perdeu chave

A varredura dos 58 `.jbuilder` não encontrou **nenhuma outra** chave presente em `f26db6ee81` e
ausente em `6ad7a9ec6e`. O saldo é fortemente aditivo — 30+ chaves novas (`draft_title`,
`draft_content`, `icon_color`, `exclude_older_than_hours`, `imap_authentication`, `secret`,
`sync_status`, `sla_frt_due_at`, `pdf_document`, `responses_count`, `edited`, `layout`,
`social_profiles`, `locale_translations`, `popular_content`, …). Todas as colunas e métodos que
elas referenciam foram verificados como existentes (tabela de verificação na seção 4).

---

## 3. E-mails alterados

O merge tocou **5** templates de e-mail (4 em `app/views/` + 1 em `enterprise/app/views/`).
Nenhum deles reverteu pt-BR para inglês — o padrão que
mordeu em `summary.liquid` e `assistant.liquid` **não se repete aqui**. Mas a medição achou uma
coisa pior, que nenhum diff mostra: o template pt-BR de confirmação **nunca foi o que roda**.

### 3.1 🔴 P1 — o e-mail de confirmação/convite da frota sai em INGLÊS, e o merge triplicou o texto errado

Existem dois `confirmation_instructions.html.erb`:

| Arquivo | Idioma (marcadores pt/en) | Fallback de marca |
|---|---|---|
| `app/views/devise/mailer/confirmation_instructions.html.erb` | **37 pt / 1 en** | `'SPX - CHAT'` |
| `enterprise/app/views/devise/mailer/confirmation_instructions.html.erb` | **0 pt / 16 en** | `'Chatwoot'` |

E o enterprise **ganha**, incondicionalmente:

```ruby
# config/application.rb:62 — dentro de class Application, SEM guarda de ChatwootApp.enterprise?
config.paths['app/views'].unshift('enterprise/app/views')
```

`unshift` põe `enterprise/app/views` na frente do view path. O diretório existe no repo, logo o
template EE resolve primeiro **sempre**. Consequência, para o e-mail que **o cliente do nosso
cliente recebe** ao ser convidado ou ao confirmar a conta:

- o corpo sai em **inglês** ("Hi …", "You're invited to join …", "Confirm my account");
- se `BRAND_NAME` não estiver setado naquela VM, o e-mail se assina **"Chatwoot"** — vazamento de
  marca do upstream, não a nossa. (Em `config/installation_config.yml:42` o default é
  `'SPX - CHAT'`, então o risco só aparece em VM cujo `InstallationConfig` foi editado para vazio.)

**Isto não é regressão do merge** — o lado NOSSO (`f26db6ee81`) já tinha o EE em inglês ("Hi
<%= @resource.name %>"). O que o merge fez foi **ampliar a superfície**: o EE saltou de 45 para 99
linhas (eyebrow, `detail_rows`, ramo SSO completo), e o CE em pt-BR cresceu em paralelo — os dois
foram reescritos, e o esforço de tradução continua investido no arquivo que não roda.

Correção (pequena, fora do escopo desta task): traduzir o EE para pt-BR e trocar o fallback
`'Chatwoot'` por `'SPX - CHAT'`. O `_confirmation_body.html.erb` novo **não** precisa de nada — só
existe no CE (não há duplicata EE), é compartilhado pelos dois, e não tem uma única string fixa de
idioma: recebe tudo por `locals`. Esse é o desenho certo; só o arquivo que preenche os locals está
no idioma errado.

**Mecanismo desta conclusão** (não leitura): varredura de todos os 38 templates de e-mail do CE
contra os do EE. Duplicatas: **exatamente 1**, a de cima. Nenhum template de e-mail existe só no
EE. Portanto este é o único ponto onde a precedência de view path troca o idioma de um e-mail.

### 3.2 🟠 P2 — e-mail NOVO em inglês, com assunto em inglês hardcoded

`app/views/mailers/administrator_notifications/integrations_notification_mailer/openai_disconnect.liquid`
(novo, 100% do upstream):

> Hello,
> Your OpenAI integration was disconnected because the configured API key is invalid or revoked. …

Assunto, também novo e hardcoded fora de locale
(`app/mailers/administrator_notifications/integrations_notification_mailer.rb:14`):

```ruby
subject = 'Your OpenAI integration was disconnected'
```

Vai para o **administrador da conta do cliente**. pt-BR é prioridade da casa, então isto entra
como perda de i18n — superfície nova, não regressão. Os dois vizinhos (`slack_disconnect`,
`dialogflow_disconnect`) já estavam em inglês hardcoded antes do merge; a dívida é do trio, e
traduzi-los é uma correção de 6 linhas.

**Conexão com o defeito 1.1 — vale registrar:** este é justamente o e-mail que dispara quando a
`api_key` do OpenAI fica inválida. O defeito 1.1 **apaga** essa chave ao salvar o hook. Ou seja:
o sintoma observável do 1.1 em produção é o administrador do cliente receber, em inglês, um aviso
de que a integração caiu — minutos depois de alguém ter apenas aberto "Editar" e clicado em salvar.
Se esse e-mail começar a aparecer na frota depois do deploy, a causa mais provável é o 1.1.

### 3.3 🟢 `layouts/mailer/base.liquid` — ganho, e a customização nossa sobreviveu

216 linhas de diff, o maior de `app/views/` — e **não** é o upstream sobrescrevendo o layout. O
resultado é uma versão nossa, mais nova: cartão com `border-radius: 24px`, `accent-bar` verde
`#2DC46F` (era o azul `#0080f8` do Chatwoot), footer em português. Trocas relevantes:

| | NOSSO (`f26db6ee81`) | MERGE (`6ad7a9ec6e`) |
|---|---|---|
| Texto do footer | "Desenvolvido por …" | "Este email foi enviado por …" |
| Cor de destaque | `#0080f8` (azul Chatwoot) | `#2DC46F` (verde) |
| Fundo | `#F8FAFC` | `#F4F7FB` |
| Largura máxima | 600px | 640px |
| `BRAND_NAME` ausente | `{% if global_config.BRAND_NAME != '' %}` → em Liquid `nil != ''` é **true**, renderizava footer com nome e link vazios | `{% assign %}` com fallback `'SPX - CHAT'` → footer coerente |

Os dois lados estão em pt-BR; o merge melhora o caso de `BRAND_NAME` nulo. Único ponto a ter em
mente: o fallback `'SPX - CHAT'` agora está **hardcoded no template**, então uma VM white-label que
zere `BRAND_NAME` passa a assinar os e-mails como "SPX - CHAT" em vez de não assinar. Dado que o
default de `installation_config.yml` já é `'SPX - CHAT'`, o comportamento observável só muda para
quem editou a config para vazio de propósito — improvável, mas é a única forma de este item virar
incidente de branding.

### 3.4 Fora do escopo, declarado: remetente e assunto

A pergunta 2 inclui "remetente" e "assunto". Nenhum dos dois vive em `app/views/`: remetente vem
de `app/mailers/**` + `MAILER_SENDER_EMAIL`, e assuntos vêm de `config/locales/**` (ou, no caso
acima, hardcoded no mailer). `app/mailers/` é território do auditor de Ruby. O que **este** relatório
verificou de assunto foi só o do 3.2, porque o template era novo e o assunto veio no mesmo commit.


---

## 3.5 Bloco 4 — o resto, nominalmente

66 dos 131 arquivos são o **Help Center público** (portal). É a maior fatia em contagem e a menor
em risco de contrato: são templates ERB renderizados no servidor, sem consumidor JS que possa
receber `undefined`. Verificados por mecanismo, não por leitura:

**(a) Nenhum partial órfão.** Extraí todas as referências `render '…'` dos 131 arquivos e resolvi
cada uma contra a árvore do MERGE: **102 referências, 102 resolvem** (101 no repo + `render "form"`
de `super_admin/accounts/edit.html.erb`, que vem de `administrate-0.20.1`). Um partial faltante
aqui seria 500 no Help Center público — não há nenhum.

**(b) Nenhum vazamento de i18n.** Os 54 usos de `t('public_portal.*')` nos views tocados foram
extraídos e conferidos contra `config/locales/pt_BR.yml`: **54/54 presentes**, e **0** com valor
idêntico ao `en.yml` (ou seja, nenhuma "tradução" que é cópia do inglês). Amostra:
`popular_articles` = `'Artigos populares'`, `no_results` = `"Nenhum resultado encontrado para '%{query}'"`,
`last_updated_on` = `'Última atualização em %{last_updated_on}'`. O tema novo do Help Center chega
**inteiramente traduzido** — o que, dado o histórico desta casa, era o resultado menos provável.

**(c) A Central de Ajuda embutida sobreviveu.** `layouts/portal.html.erb` encolheu de 162 para 14
linhas (7+/155-), o que à primeira vista parece exatamente o formato de uma customização atropelada.
Não é: o conteúdo foi extraído para `_portal_head.html.erb` e `_portal_scripts.html.erb` (ambos
novos). As duas metades da nossa customização de embed estão intactas:

- o `embed=true` que libera o framing vive no **controller**, não no layout, e está lá com o
  comentário em pt-BR original: `public/api/v1/portals/base_controller.rb:68-71`;
- o widget "pedir ajuda" foi para `_portal_scripts.html.erb:96-101`, com a **mesma** condição
  `@portal.channel_web_widget.present? && !@is_plain_layout_enabled`.

**(d) Demais categorias, uma linha cada** — todas aditivas, nenhuma com contrato:

| Categoria | n | Veredito |
|---|---|---|
| `portals/documentation_layout/**` (sidebar, topbar, breadcrumb, cards, footer, hero…) | 16 | Tema `documentation` novo do Help Center, todo aditivo, i18n completo (item b) |
| `portals/**` restante, incl. variantes `+plain` / `+documentation` | 37 | Multi-layout do portal (3 layouts: default, plain, documentation). Aditivo |
| `layouts/portal*` | 3 | Extração descrita em (c) |
| `layouts/vueapp.html.erb` | 1 | **1 linha**: `inboxEventsEnabled: '<%= ENV['ENABLE_INBOX_EVENTS'].present? %>'`. Consumidor coerente — `useConfig.js:43` compara `=== 'true'`, e o ERB emite `'true'`/`'false'` |
| `super_admin/push_diagnostics/show.html.erb` | 1 | Nova tela de diagnóstico de push (190 linhas, 0 removidas). Aditivo |
| `super_admin/{accounts/edit,application/_icons,_navigation}` | 3 | Suporte à nova tela + ícones; `_navigation` 5 linhas |
| `fields/account_status_field/_form`, `fields/suspension_history_field/_show` | 2 | Campos Administrate para suspensão de conta. Novos |
| `enterprise/fields/captain_model_overrides_field/{_form,_show}` | 2 | Override de modelo por conta no super admin. Novo |
| `enterprise/fields/manually_managed_features_field/_form` | 1 | 5 linhas. **Vale um olhar do responsável por feature flags** — é a tela que liga/desliga features à mão, e este merge remapeia slots de bitmask (dívida já conhecida). Não é defeito de view; é adjacência |
| `public/api/v1/models/_search_article.json.jbuilder` | 1 | Snippet da busca passou de `article.content.to_s.squish` para `ChatwootMarkdownRenderer#render_markdown_to_plain_text` (método verificado, existe). Melhora: o snippet deixa de mostrar sintaxe Markdown crua |

---

## 4. COBERTURA — julgados × declarados fora

### 4.1 O escopo real é maior do que o declarado

O auditor de backend declarou fora **~110 arquivos** (67 em `app/`, 43 em `enterprise/`). Medido:

| | Declarado por ele | Medido aqui | Delta |
|---|---|---|---|
| `app/views/` | 67 | **97** | +30 |
| `enterprise/app/views/` | 43 | **34** | −9 |
| **Total** | ~110 | **131** | **+21** |

Os 21 arquivos a mais foram julgados junto — nenhum ficou de fora por causa da divergência.

### 4.2 Julgados

**131/131 arquivos julgados.** Nada de `app/views/` ou `enterprise/app/views/` ficou sem veredito.

Profundidade por camada, honestamente:

| Camada | n | Profundidade |
|---|---|---|
| `.jbuilder` (contrato de API) | **58** | **Máxima.** Diferença de conjuntos de chaves nos dois lados por extrator validado + leitura integral do diff dos 24 modificados + `git grep` de consumidor no `app/javascript/` para cada mudança de valor |
| E-mail (5 templates) | **5** | **Máxima.** Diff integral + varredura de duplicatas CE×EE em todos os 38 templates de e-mail + prova de precedência de view path + conferência de idioma por contagem de marcadores |
| Portal / Help Center | **66** | **Média-alta.** Mecanismos (a) e (b): resolução de 102 partials + 54 chaves de i18n. Não li os 66 diffs linha a linha — são ERB aditivos sem consumidor JS. Declarado |
| `super_admin` + `fields` | **9** | **Baixa, deliberada.** Aditivos, superfície de super admin interno. Uma linha cada, acima |
| `layouts` (não-e-mail) | **4** | Alta (são 4 arquivos, 2 deles de 1–14 linhas) |

### 4.3 Verificações executadas (mecanismo, não afirmação)

| Verificação | Resultado |
|---|---|
| Extrator de chaves validado contra leitura manual | 13/13 em `_contact.json.jbuilder` ✔ |
| Construções opacas ao extrator (`merge!`, `partial!` dinâmico) nos 58 jbuilder | **0** — a diferença de conjuntos é completa, não amostral |
| Colunas novas referenciadas por jbuilder, contra `db/schema.rb` | 21 checadas: 17 são coluna, 4 são método (`Portal#default_locale`, `Account#onboarding_step`, `Inbox#branded_email_layout`, `Captain::Document#last_sync_error_code` via `store_accessor`). **0 ausentes** |
| Métodos/constantes novos referenciados | 10 checados, **0 ausentes**. 2 falsos positivos meus (`Enterprise::Billing::Currencies`, `User#administrator?`) derrubados antes de entrarem no relatório |
| Partials referenciados por jbuilder | 5 checados, todos resolvem (`_company` mudou de `accounts/companies/` para `models/`) |
| `render '…'` nos 131 arquivos | 102 referências, **102 resolvem** |
| Chaves `t('public_portal.*')` em `pt_BR.yml` | **54/54**, e **0** cópias do inglês |
| Duplicatas de template de e-mail CE×EE | **1** (`devise/mailer/confirmation_instructions.html.erb`) — o achado 3.1 |

### 4.4 Declarado fora — o que **não** foi coberto

1. **`app/views/api/v1/widget/**` — o 1º da lista de prioridades — não foi tocado pelo merge.**
   `git diff --name-only … -- app/views/api/v1/widget/` = **0**. Os 11 jbuilder do widget estão
   idênticos. O contrato do widget mudou apenas **por herança** dos partials de `api/v1/models/**`
   que ele renderiza; essas mudanças estão todas julgadas nas seções 1 e 2 (nenhuma é perda para o
   widget — o saldo dele é `_contact.company_id` e `_attachment` refatorado).

2. **Assunto e remetente de e-mail** — não moram em `app/views/`. Só o assunto do 3.2 foi
   verificado, porque veio no mesmo commit do template novo. `app/mailers/**` e
   `config/locales/**` (assuntos) são território do auditor de Ruby. Ver 3.4.

3. **Execução em runtime.** Esta auditoria é estática: leitura de blobs via `git show`, `git grep`
   e cruzamento de YAML. **Nenhum endpoint foi chamado, nenhum e-mail foi renderizado, nenhum
   teste rodou.** O worktree é compartilhado com executores que estão medindo, e a task é
   somente-leitura. Consequência honesta: o defeito 1.1 está provado por leitura das duas pontas
   (servidor filtra; front reenvia; `update!` sobrescreve), **não** por um request que apagou uma
   `api_key` de verdade. Se a Onda 1 quiser fechar isso com número, o teste é curto — request
   spec: cria hook openai com `api_key`, `PATCH` com o payload que `EditHook.vue` produz, e
   `expect(hook.reload.settings['api_key']).to eq('sk-original')`.

4. **`ChatwootMarkdownRenderer#render_markdown_to_plain_text`** — confirmado que existe, mas o
   *conteúdo* do snippet de busca que ele produz não foi comparado com o antigo em nenhum artigo
   real. Baixo risco (é melhora conhecida), mas não medido.

5. **Quais hooks de integração existem hoje em cada VM da frota.** Não consultei banco (proibido
   nesta task). O impacto do 1.1 por cliente depende de quais das 6 integrações estão realmente
   configuradas em cada VM — isso precisa de um `SELECT app_id, count(*) FROM integrations_hooks
   GROUP BY 1` por VM antes do deploy, para saber quem está exposto.

---

## 5. Veredito

**O último buraco declarado foi fechado com medição.** 131 arquivos julgados, 0 fora.

O que sai daqui para a lista de correções, em ordem:

| # | Sev | Achado | Correção |
|---|---|---|---|
| 1.1 | 🔴 **P0** | `_hook.json.jbuilder` filtra `settings` por `visible_properties`; nossa `EditHook.vue` reenvia tudo e o `update!` sobrescreve o jsonb → **apaga credencial de 6 integrações (14 chaves) ao salvar** | `HooksController#update` faz `settings.merge(...)` **+** `EditHook.vue` não reenvia chave que não recebeu |
| 3.1 | 🔴 **P1** | E-mail de confirmação/convite da frota sai em **inglês** com fallback de marca `'Chatwoot'` — o EE vence o CE por `unshift` no view path, e o merge triplicou o texto inglês | Traduzir `enterprise/…/confirmation_instructions.html.erb` e trocar o fallback por `'SPX - CHAT'` |
| 3.2 | 🟠 P2 | `openai_disconnect` (e-mail + assunto) novo em inglês, hardcoded fora de locale | Traduzir o trio `openai_/slack_/dialogflow_disconnect` (~6 linhas) |
| 1.3 | 🟡 P2 | `reauthorization_required` do WhatsApp fixo em `false` para canal criado à mão → perde o aviso de token expirado | Decisão de produto; se voltar, precisa de destino próprio para o fluxo manual |
| 2.1 | ⚪ dívida | `Company#created_at/updated_at` viraram epoch e condicionais | Nada agora (feature dormente, sem consumidor) |

**Nenhuma chave de API foi perdida sem substituto.** O saldo do contrato JSON é aditivo (30+ chaves
novas, todas com coluna/método existente). O defeito P0 não é uma chave que sumiu do JSON — é uma
chave que o servidor parou de *devolver* enquanto o nosso cliente continuou a *reescrevê-la*. Foi
por isso que passou por todo teste verde: nenhum dos dois lados está errado sozinho.

