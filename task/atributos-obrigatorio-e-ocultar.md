# Atributo personalizado: preenchimento obrigatório e ocultar

**Nível:** pleno · **Risco:** médio — tem migration, e o "obrigatório" pode travar o resolver
**Onde validar:** staging (`nicolas.chatspx.app`) antes da frota
**Executar por partes:** cada parte fecha sozinha e tem prova própria. **Leia a Parte 0 antes de escrever qualquer linha.**

---

## Por que esta task existe

O modal "Adicionar atributo personalizado" ganha dois checkboxes, abaixo do "Habilitar
validação do regex":

1. **Preenchimento obrigatório** — quando o agente for **resolver** a conversa e o atributo
   estiver vazio, abre um modal para ele preencher; sem preencher, não resolve.
2. **Ocultar** — quando ligado, o atributo **não aparece dentro da conversa**.

O caso real que motivou o "Ocultar": a conta 1 tem três atributos técnicos de contato —
`waha_whatsapp_chat_id`, `waha_whatsapp_jid`, `waha_whatsapp_lid` — que poluem o painel
"Atributos do contato" e não dizem nada para quem atende.

---

## Parte 0 — Ler antes de codar (10 minutos, sem código)

> **O fluxo de "preenchimento obrigatório" JÁ EXISTE no fork, inteiro.** Está dormente e
> configurado em outro lugar. Quem começar pelo teclado vai reimplementar o que está pronto.

O que já existe e **deve ser reaproveitado**:

| peça pronta | arquivo |
|---|---|
| checagem do que falta preencher | `app/javascript/dashboard/composables/useConversationRequiredAttributes.js` |
| **o modal de preencher ao resolver** | `components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue` |
| resolver individual | `components/buttons/ResolveAction.vue:185` e `:201` |
| resolver em massa | `composables/chatlist/useBulkActions.js` + `components/ChatList.vue:423` |
| onde a config mora hoje | `account.settings.conversation_required_attributes` (array de chaves) |
| tela de config atual | `components-next/ConversationWorkflow/ConversationRequiredAttributes.vue` (Fluxo de Conversa) |
| flag | `conversation_required_attributes`, `premium: true` (`config/features.yml:241`) — **DESLIGADA** |

O modal já valida `required`, `url` e **regex do próprio atributo**, e já trata `text`,
`number`, `link`, `date`, `list` e `checkbox`. **Não reescreva o modal.**

Duas limitações do que existe, e é aí que mora o trabalho novo:

- ele alcança **só atributos de conversa** — a task pede conversa **e contato**;
- ele está atrás de uma **flag premium desligada**, então hoje não responde a nada.

O **"Ocultar" não existe** — esse é do zero.

```bash
# confirme o estado antes de começar
cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner '
a = Account.find(1)
puts "flag ligada? #{a.feature_enabled?("conversation_required_attributes")}"
puts "obrigatorios hoje: #{a.settings["conversation_required_attributes"].inspect}"
a.custom_attribute_definitions.each { |d| puts "#{d.attribute_model} | #{d.attribute_key}" }'
```

---

## Parte 1 — Banco: duas colunas

Migration em `custom_attribute_definitions`:

```ruby
add_column :custom_attribute_definitions, :required, :boolean, default: false, null: false
add_column :custom_attribute_definitions, :hidden,   :boolean, default: false, null: false
```

**Por que coluna e não o array que já existe:** `account.settings.conversation_required_attributes`
é por CONTA e só de CONVERSA. A task pede por ATRIBUTO e inclui CONTATO. Manter o array e
somar um segundo para contato criaria duas fontes de verdade para a mesma pergunta.

**Backfill na mesma migration — não pule.** Conta da frota que já configurou obrigatórios
perde tudo em silêncio se você só criar a coluna:

```ruby
Account.find_each do |account|
  keys = account.settings['conversation_required_attributes']
  next if keys.blank?
  account.custom_attribute_definitions
         .where(attribute_model: :conversation_attribute, attribute_key: keys)
         .update_all(required: true)
end
```

⚠️ **Migration precisa de confirmação antes de rodar** — no staging e, depois, na frota.

**Prova:** `rails db:migrate` sobe; numa conta com `conversation_required_attributes`
preenchido, os atributos daquelas chaves ficam com `required = true`.

---

## Parte 2 — Backend: aceitar e devolver os campos

| arquivo | o que muda |
|---|---|
| `api/v1/accounts/custom_attribute_definitions_controller.rb` | `permitted_payload` ganha `:required, :hidden` |
| `app/views/api/v1/models/_custom_attribute_definition.json.jbuilder` | expor `required` e `hidden` |
| `enterprise/app/models/enterprise/concerns/custom_attribute_definition.rb` | o `cleanup_conversation_required_attributes` fica órfão depois do backfill — remover ou deixar inerte |

⚠️ **Este controller foi tocado na task do supervisor** e já tem
`check_platform_settings_authorization?` em `create/update/destroy`. Não remova.

**Sem o jbuilder o front nunca vê os campos** — é o erro mais fácil de cometer aqui, porque
o `PATCH` responde 200 e parece que salvou.

**Prova:**
```bash
curl -s -X POST -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  http://127.0.0.1:3000/api/v1/accounts/1/custom_attribute_definitions \
  -d '{"custom_attribute_definition":{"attribute_display_name":"Motivo","attribute_key":"motivo","attribute_model":0,"required":true}}'
# a resposta precisa trazer "required": true
curl -s -H "api_access_token: $TOKEN" \
  http://127.0.0.1:3000/api/v1/accounts/1/custom_attribute_definitions | grep required
```

---

## Parte 3 — O formulário: dois checkboxes

`settings/attributes/AddAttribute.vue` e `settings/attributes/EditAttribute.vue`.

Espelhe o padrão que já está no arquivo — o checkbox do regex em `AddAttribute.vue:263` é
`<input type="checkbox" v-model>` puro, sem componente. Os dois novos vão logo abaixo dele.

Diferente do regex, os dois **valem para qualquer tipo** de atributo (o bloco do regex tem
`v-if="isAttributeTypeText"`).

I18n: chaves novas em `ATTRIBUTES_MGMT` no **`en.json` apenas** — os outros idiomas são da
comunidade.

No `EditAttribute.vue`, os checkboxes precisam **carregar o estado atual** do atributo, como o
`regexEnabled` faz em `:129`.

**Prova:** criar atributo com os dois marcados, reabrir em Editar e ver os dois marcados.

---

## Parte 4 — "Ocultar" (faça esta antes da 5: é menor e independente)

Um filtro, **num ponto só**:
`routes/dashboard/conversation/customAttributes/CustomAttributes.vue:48` — o computed
`attributes`, que hoje devolve `attributes/getAttributesByModel` cru.

Esse componente serve **os dois painéis** dentro da conversa ("Atributos da conversa" e
"Atributos do contato") pela prop `attributeType`, então um filtro cobre os dois.

> ⚠️ **NÃO filtre no getter da store** (`store/modules/attributes.js`). Os mesmos getters
> alimentam `settings/attributes/Index.vue:77` — onde o atributo precisa aparecer para ser
> editado —, `components-next/filter/provider.js:54`, `contactProvider.js:52`,
> `useAutomation.js:142` e `shared/composables/useFilter.js:53`. Esconder na origem torna o
> atributo inadministrável e o some dos filtros e automações, que é mais do que foi pedido.

**Prova:** marcar Ocultar em `waha_whatsapp_jid` → some do painel do contato **dentro da
conversa**, e **continua** aparecendo em Configurações → Atributos Personalizados e no
construtor de filtros.

---

## Parte 5 — "Preenchimento obrigatório"

### 5.1 — A fonte muda

`useConversationRequiredAttributes.js` passa a:

1. ler `required === true` das **definições de atributo**, não de `account.settings`;
2. **perder a checagem de flag** — decisão desta task: sempre ativo, sem gate;
3. devolver os obrigatórios **dos dois modelos**, cada um carregando o seu `attributeModel` —
   o consumidor precisa saber **onde gravar**.

O `checkMissingAttributes` já trata direito o caso do checkbox (chave ausente ≠ valor falso) e
não considera `0` ou `false` como vazio. **Mantenha essa lógica**, só troque a origem da lista.

### 5.2 — Gravar em dois lugares

É aqui que mora o trabalho novo. `ResolveAction.vue:185` hoje faz uma coisa só:

```js
const mergedAttributes = { ...currentCustomAttributes, ...attributes };
toggleStatus(RESOLVED, context.snoozedUntil, mergedAttributes);
```

Passa a separar por `attributeModel`:

- **conversa** → caminho atual (`toggleStatus` com os atributos mesclados);
- **contato** → `contacts/update` com `custom_attributes`
  (`store/modules/contacts/actions.js:124` já aceita), no contato de
  `currentChat.meta.sender.id`, **antes** de resolver.

### 5.3 — Resolver em massa

`useBulkActions.js` enforça a mesma regra e precisa acompanhar a nova fonte, senão o agente
contorna tudo selecionando conversas na lista.

**Prova:** com um atributo de conversa obrigatório e outro de contato obrigatório, abrir uma
conversa vazia e resolver → o modal pede os dois; preencher e resolver → a conversa resolve, e
os valores aparecem **cada um no seu painel**. Repetir pelo resolver em massa.

---

## Parte 6 — Uma tela some

Depois do backfill, o multi-select em
`components-next/ConversationWorkflow/ConversationRequiredAttributes.vue` vira uma segunda
fonte de verdade e sai da tela "Fluxo de Conversa".

⚠️ Essa é **uma das seis telas que o supervisor perdeu** na task anterior
(`supervisor-sem-configuracoes-de-plataforma.md`). Mexer nela não muda o recorte do supervisor,
mas confira que a tela continua abrindo para o administrador comum depois da remoção.

---

## Pegadinhas conhecidas

- **A flag está desligada.** Testar sem lembrar disso leva à conclusão errada de que "não
  funciona". Depois da Parte 5.1 o gate some, mas antes dela nada responde.
- **Contato pode não existir.** Conversa sem contato identificado não tem onde gravar atributo
  de contato obrigatório. **Decida e escreva no código:** pular esses, ou barrar o resolver com
  mensagem clara. Não deixe estourar.
- **Duas gravações, um botão.** Contato e conversa são chamadas distintas. Se a do contato
  falhar, a conversa **não pode** resolver em silêncio.
- **Oculto + obrigatório na mesma definição** é combinação coerente — o agente nunca vê o campo
  no painel e só o preenche no modal de resolver. Está certo; documente para não parecer bug.
- **`hidden` some do painel, não do dado.** API, automações, filtros e webhooks continuam
  enxergando o atributo. É ocultar, não apagar.
- **Não filtre no getter da store** (Parte 4).
- **O jbuilder é obrigatório** (Parte 2) — sem ele o PATCH responde 200 e nada muda na tela.
- **Overlay Enterprise:** procure os mesmos arquivos em `enterprise/` antes de editar
  (`rg -n "custom_attribute_definition" app enterprise`).

---

## Fora de escopo

- Obrigatório em outros estados (snooze, pending) — **só resolver**.
- Ocultar na página de Contatos, nos filtros ou nas automações — **só dentro da conversa**.
- Obrigatoriedade no widget / pré-chat.
- Mexer no que a task do supervisor entregou.

---

## Verificação

| | |
|---|---|
| `bundle exec rspec spec/models/custom_attribute_definition_spec.rb` | modelo |
| `bundle exec rspec spec/controllers/api/v1/accounts/custom_attribute_definitions_controller_spec.rb` | API |
| `npx vitest run app/javascript/dashboard/composables/spec/useConversationRequiredAttributes.spec.js` | **já existe e VAI quebrar** quando a fonte mudar — atualizar faz parte da tarefa |
| `bundle exec rubocop -a` nos arquivos Ruby | lint |
| `npx eslint <arquivo>` (não `pnpm eslint`, que varre o projeto todo) | lint |

Manual, na ordem:

1. Atributo de **conversa** obrigatório → resolver conversa vazia → modal abre → preenche → resolve.
2. Atributo de **contato** obrigatório → mesmo teste → o valor cai no **contato**.
3. Os dois juntos → o modal pede os dois de uma vez.
4. **Resolver em massa** → bloqueia igual.
5. **Ocultar** num `waha_*` → some do painel do contato na conversa; **continua** em
   Configurações e no construtor de filtros.
6. **Regressão:** atributo sem nenhum dos dois checkboxes se comporta exatamente como hoje.

**Deploy:** commit **antes** do restart (senão o `version.json` carimba o SHA antigo). Como
mexe em Vue, precisa de precompile — e o heap padrão do Node estoura neste bundle:

```bash
cd /home/chatwoot/chatwoot
RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=8192' \
  bundle exec rake assets:precompile > build.log 2>&1; echo $?   # nunca canalize para tail
sudo /bin/systemctl restart chatwoot.target
```
