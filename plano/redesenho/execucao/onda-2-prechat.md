# Onda 2 — trilha PRÉ-CHAT (blocos 3.12, 3.13, 3.14, 3.16)

Worktree: `/home/chatwoot/chatwoot-o2-config-prechat` · branch `o2-config-prechat` · base `c06ba1824e`
Executor: terminal `term_c44cb45e` · task `task_ae72654bae0f` · 18/08/2026

Escrito conforme avanço. Cada bloco traz: o que a base tinha (medido), o que foi feito, o mecanismo
que executa o aceite, e o **resultado real** do mecanismo — inclusive quando ele é vermelho.

---

## 0. O terreno, medido antes da primeira linha

| O que | Estado medido |
|---|---|
| `app/models/channel/web_widget.rb` | `EDITABLE_ATTRS` nas linhas 47-53 (o plano cita 34-40; o bloco 0.8 empurrou 13 linhas). `pre_chat_fields` aceitava 13 chaves, nenhuma das sete do 3.12 |
| `pre_chat_form_options` | jsonb sem validação de forma alguma no modelo — só `before_validation :validate_pre_chat_options`, que **semeia** o default e não valida nada |
| `json_schemer` | `Gemfile:38`, `0.2.24` no lock. Padrão de uso: `app/models/concerns/json_schema_validator.rb` e `integrations/hook.rb:106` |
| `helper/preChat.js` | existe, foi tocado pelo bloco 0.8 (D10) — o lookup de i18n dos rótulos padrão |
| `shared/helpers/Validators.js` | é importado **pelo widget e pelo dashboard**; `libphonenumber-js` (`package.json:98`) e `company-email-validator` (`:80`) já instalados |
| `inbox/widget/` (a pasta nova do plano) | **não existe** nesta branch — nem `composables/`, nem `prechat/` |
| `i18n/*/inboxWidget.json` | existe nos dois idiomas (bloco 0.7), com `PRE_CHAT_FORM.FIELDS` e `CONFIGURATION` |
| Banco de teste da trilha | `chatwoot_test_o2_prechat`, criado só para esta trilha. **`POSTGRES_DATABASE` é cravado no env de teste** porque `config/database.yml` usa a mesma variável nos três ambientes — herdar o `.env` da máquina apontaria `RAILS_ENV=test` para o banco de produção |

### 0.1 Sete falhas pré-existentes em `inboxes_controller_spec.rb`

Medido **com o meu trabalho fora do caminho** (`git stash push -u`, rodar, `pop`):

```
$ bundle exec rspec spec/controllers/api/v1/accounts/inboxes_controller_spec.rb   # base limpa
100 examples, 7 failures
```

As sete são: `DELETE …/inboxes/:id` (deleta inbox), `PATCH` com branded email layout > 256 KiB, e as
cinco de `GET …/inboxes/:id/health` com inbox WhatsApp. **Nenhuma tem relação com pré-chat** e todas
já falhavam antes desta trilha. Registro aqui para que ninguém as atribua a esta branch.

> **Cicatriz nova, para as outras trilhas:** `git stash` é **por repositório, não por worktree**. O
> meu stash apareceu no topo da pilha compartilhada com as outras três trilhas da Onda 2, e o `pop`
> abortou na primeira tentativa porque o rspec havia reescrito `public/version.json`. Deu certo
> (arquivos conferidos por `diff` contra cópia de segurança), mas **não repitam**: para medir
> baseline, prefira rodar o teste antes de escrever o código.

---

## 1. Bloco 3.12 — as sete chaves novas do pré-chat ✅

**Aceite do plano:** *"Campo com `mask` e `show_if` persiste; forma inválida é rejeitada"*.

### 1.1 O que a base tinha, e por que só o `permit` não bastava

`EDITABLE_ATTRS` é lista fechada: chave não declarada **não levanta erro**, é descartada em silêncio.
Sem a ampliação, um `PATCH` com `mask: "cpf"` volta **200** e o banco não guarda máscara nenhuma — o
pior tipo de falha, porque a tela parece ter funcionado. E o `permit` decide *quais chaves entram*;
ele não olha *valor*: `mask: "banana"` e `step: 99` passariam direto para o jsonb e só quebrariam no
navegador do visitante.

Por isso o bloco tem **duas** metades, e as duas têm mecanismo próprio.

### 1.2 O que foi feito

| Arquivo | O quê |
|---|---|
| `app/models/channel/web_widget.rb` | `EDITABLE_ATTRS` ganha `:step, :position, :mask, :validator, :help_text, :error_message` e `{ show_if: [:field, :operator, :value] }` dentro de `pre_chat_fields`; nova `validate :pre_chat_form_options_shape` |
| `app/models/channel/web_widget/pre_chat_form_schema.rb` ⚪ | JSON Schema da forma de `pre_chat_form_options`, com o vocabulário de máscaras/validadores/operadores e o formatador de mensagem de erro |

**Três decisões de forma, cada uma com a razão:**

1. **`additionalProperties: true` no campo.** A tela antiga (`PreChatForm/Settings.vue:78`) regrava o
   array inteiro. Fechar a forma do campo transformaria qualquer chave legada de qualquer conta da
   frota num 422 no próximo save — o schema recusaria dado que ele mesmo nunca aceitou gravar.
2. **Sem `maxItems`.** O teto de 8 do plano é sobre campo **habilitado**. O array carrega também todo
   atributo personalizado da conta com `enabled: false` (`helper/preChat.js#getCustomFields`), então
   uma conta com 12 atributos tem 12 entradas há anos. `maxItems: 8` aqui seria 422 em massa na frota.
   O teto de 8 é regra da tela (3.14) e conta `enabled` — **e isso muda o mecanismo do aceite 21**.
3. **`show_if` com `additionalProperties: false`.** É chave que nasce agora, não há legado a proteger,
   e é o que barra `E`/`OU` aninhado — que a §B.4.4 deliberadamente não entrega nesta versão.

**Vocabulário fixado** (o mesmo nome vale no schema Ruby e no helper JS do 3.13; nome que exista de um
lado só é campo que a tela oferece e o widget ignora):

* `mask`: `cpf`, `cnpj`, `cpf_cnpj`, `cep`, `uf`, `phone`
* `validator`: `cpf`, `cnpj`, `cpf_cnpj`, `cep`, `uf`, `email`, `corporate_email`, `phone`,
  `junk_name`, `junk_phone`, `junk_email`
* `show_if.operator`: `is`, `is_not`, `contains`, `filled`
* `step`: 1–8 · `position`: 0–99 · `help_text`/`error_message`: ≤ 160 caracteres

As três regras anti-lixo da §B.4.3 entram como valores de `validator` (`junk_*`). A **severidade
suave** (avisa, não trava o envio) é declarada no helper de front — o schema só decide se o nome
existe. Consequência assumida: um campo tem **um** validador; quem quiser "corporativo + descartável"
usa `corporate_email`, que é o mais restritivo dos dois.

### 1.3 Mecanismo e resultado real

Dois arquivos de teste, um por metade:

* `spec/models/channel/web_widget_pre_chat_schema_spec.rb` — 12 exemplos (a forma)
* `spec/controllers/api/v1/accounts/inboxes_pre_chat_schema_spec.rb` — 3 exemplos (o `permit`, por
  `PATCH` HTTP de verdade)

**Vermelho antes** (com os arquivos de teste escritos e o código ainda não):

```
$ rspec spec/models/channel/web_widget_pre_chat_schema_spec.rb
12 examples, 8 failures          # as 8 de "forma inválida"; as de persistência passam
                                 # porque o jsonb aceita tudo quando ninguém valida

$ rspec spec/controllers/api/v1/accounts/inboxes_pre_chat_schema_spec.rb
3 examples, 3 failures           # a chave é DESCARTADA e a resposta é 200 — exatamente
                                 # o defeito silencioso que o bloco fecha
```

**Verde depois**, com a vizinhança junto:

```
$ rspec spec/models/channel/ spec/controllers/api/v1/accounts/inboxes_pre_chat_schema_spec.rb spec/jobs/inboxes/
108 examples, 0 failures

$ rubocop <os 4 arquivos>
4 files inspected, no offenses detected
```

O aceite literal, asserção por asserção: `mask: "cpf"` + `show_if: {field, operator}` sobem por
`PATCH`, **persistem** e voltam com o valor exato (`include('mask' => 'cpf', …)`, não `be_present`);
`mask: "banana"` → **422** e o banco continua sem máscara; `show_if` sem `operator` → **422**.

---

## 2. Bloco 3.13 — máscaras e validadores brasileiros ✅

**Aceite do plano:** *"`529.982.247-25` aceito, `…-26` rejeitado pelo DV, **e `111.111.111-11`
rejeitado pela regra de dígitos repetidos**"*.

### 2.1 Fonte única, não espelho — e por quê

O plano pedia `dashboard/helper/brMasks.js` "+ espelho no widget". **Duas cópias divergem no primeiro
conserto feito de um lado só** — e aí a tela promete uma regra e o formulário do visitante aplica
outra, que é o defeito mais caro possível num campo de captura. A implementação ficou em
`app/javascript/shared/helpers/brMasks.js` (pasta que os dois grafos já importam: o widget usa
`shared/helpers/Validators.js` hoje), e os dois caminhos que o plano nomeia existem como
reexportação de uma linha:

* `app/javascript/dashboard/helper/brMasks.js` → `export * from 'shared/helpers/brMasks'`
* `app/javascript/widget/helpers/brMasks.js` → idem

### 2.2 Duas dependências recusadas, com o número medido

O plano listava as duas como "já instalada", e as duas foram medidas antes de serem usadas:

| Dependência | Medição | Decisão |
|---|---|---|
| `company-email-validator` (`package.json:80`) | `free_email_provider_domains.js` = **222.995 bytes** | **Não importada.** O widget tem teto de 300 kB no grafo inteiro (gate do bloco 0.5); uma lista de domínios levaria dois terços dele. Ficou uma lista curta, explícita e auditável: 42 provedores gratuitos e 30 descartáveis |
| `libphonenumber-js` (`package.json:98`) | `metadata.full.json` = **156 kB**; e — medido — **não está no grafo do widget hoje**: só o dashboard o importa | **Não importada.** O widget valida telefone com `startsWithPlus` + `isPhoneNumberValidWithDialCode` de `shared/helpers/Validators.js`, registrados no FormKit em `entrypoints/widget.js:36-38`. É exatamente o que o item 25 da §C.3 pede |

> **Divergência declarada contra a §B.4.3 do plano 23:** a tabela de lá diz que o telefone é
> validado por `libphonenumber-js`, "já instalado **e já registrado no FormKit do widget
> (`entrypoints/widget.js:36-38`)**". As linhas 36-38 registram `startsWithPlus` e
> `isPhoneNumberValidWithDialCode`, que vêm de `shared/helpers/Validators.js` — **`libphonenumber-js`
> não aparece em nenhum arquivo de `app/javascript/widget/`**. A afirmação do plano confunde o pacote
> com as regras do FormKit.

### 2.3 O que o helper entrega

* **Máscaras** (`applyMask`): `cpf`, `cnpj`, `cpf_cnpj` (alterna pelo comprimento), `cep`, `uf`,
  `phone`. Máscara desconhecida devolve o valor **intacto** — máscara que não existe não pode comer o
  que o visitante escreveu.
* **Documentos**: `isValidCPF`, `isValidCNPJ`, `isValidCpfOrCnpj`, `isValidCEP`, `isValidUF` +
  `UF_LIST` com as 27 unidades.
* **E-mail**: `isValidEmail`, `isCorporateEmail`.
* **Telefone**: `isPhoneWithDialCode`.
* **As três regras anti-lixo**, cada uma com função própria e **severidade `warning`**:
  `looksLikeJunkName`, `looksLikeJunkPhone`, `looksLikeJunkEmail`. O bloqueio é suave por decisão da
  §B.4.3 — filtro rígido em formulário de captura descarta cliente real.
* **`validateFieldValue(value, { validator, required })`** → `{ valid, severity, code }`. O `code` é
  **sufixo de chave de i18n**, nunca texto pronto.

### 2.4 Duas armadilhas encontradas ao escrever, e como cada uma foi resolvida

1. **A do CPF, que o plano avisou.** O DV sozinho **aceita** `111.111.111-11`: a soma ponderada de
   `111111111` dá 54, `11 − 54 % 11 = 1`. A regra de dígitos repetidos entra **dentro** de
   `isValidCPF`/`isValidCNPJ`, não como heurística separada — não é desligável. Um teste varre as
   **dez** sequências de dígito único e exige lista vazia de aprovados.
2. **A do anti-lixo de telefone, encontrada aqui.** A regra "sequência trivial" aplicada a
   **substring** marca `+55 11 98765-4321` como lixo — ele termina em `987654321`, que é uma sequência
   decrescente, e é um celular plausível. A regra passou a exigir sequência **de ponta a ponta**, mais
   um caso explícito para os últimos oito dígitos todos iguais (`+55 11 11111-1111`, em que DDI e DDD
   escondem a repetição). O comentário no código registra por que o número de exemplo do teste mudou.

### 2.5 Mecanismo e resultado real

`app/javascript/shared/helpers/specs/brMasks.spec.js` — 32 exemplos.

**Vermelho antes:** `Failed to resolve import "shared/helpers/brMasks"` — 1 arquivo falhou, 0 testes
coletados. **Verde depois:**

```
$ npx vitest run app/javascript/shared/helpers/specs/brMasks.spec.js
Test Files  1 passed (1)
     Tests  32 passed (32)

$ npx eslint <os 4 arquivos>
(sem saída — 0 problemas)
```

O aceite literal: `isValidCPF('529.982.247-25') === true`; `isValidCPF('529.982.247-26') === false`;
`isValidCPF('111.111.111-11') === false`; `isValidCNPJ('11.111.111/1111-11') === false`;
`isCorporateEmail('fulano@gmail.com') === false` e `isCorporateEmail('fulano@empresa.com.br') === true`;
`isPhoneWithDialCode('11987654321') === false`.

---

## 3. O merge de `redesenho-integra`, e por que ele veio antes do 3.14

O 3.14 depende de **3.06** (`useInboxWidgetConfig`), que é da trilha TELAS. Escalei em vez de
improvisar, e a resposta foi para eu mesmo mergear a branch de integração:

```
$ git merge redesenho-integra
Merge branch 'redesenho-integra' into o2-config-prechat     # zero conflito
```

Veio junto: Onda 0 inteira, quase toda a Onda 1, e as três outras trilhas da Onda 2 —
`useInboxWidgetConfig`, `useUnsavedChangesGuard`, `WidgetSaveBar`, `WidgetUnsavedChangesDialog`,
`widgetConfigFields`, `widgetFieldLabels` e os specs deles.

**Nenhuma suíte quebrou:** `vitest app/javascript/shared app/javascript/dashboard` (regra R21, porque
o 3.13 acrescentou arquivo em `shared/`) fechou em **426 arquivos e 4358 exemplos, 0 falhas**.

---

## 4. Bloco 3.14 — a Tela 3 ✅

**Aceite do plano:** *"9º campo impossível com o motivo à vista; validação **no blur**; migrar
Simples↔Construtor não perde campo"* (+ itens 21, 26, 27 e 28 da §C.3).

### 4.1 O que foi escrito

| Arquivo | O quê |
|---|---|
| `prechat/preChatModel.js` ⚪ | As regras que os aceites cobram: teto, etapas, ordem, condicional, migração, modo |
| `prechat/PreChatFieldEditor.vue` ⚪ | Rótulo, ajuda, erro próprio, obrigatório, máscara, validador, condicional e **a prévia do campo** |
| `prechat/PreChatStepList.vue` ⚪ | Etapas, arrastar (`vuedraggable`), contador e o teto com o motivo à vista |
| `prechat/ConditionEditor.vue` ⚪ | Campo / operador / valor, só de etapa anterior |
| `prechat/PreChatPage.vue` ⚪ | Os três modos, a mensagem, a migração com confirmação, a barra de salvar |
| `i18n/{pt_BR,en}/inboxWidget.json` | **118 chaves, paridade exata** entre os dois idiomas |
| `composables/widgetConfigFields.js` | Os **dois descritores** do pré-chat (autorizados pelo coordenador) |
| `web_widget.rb` + `pre_chat_form_schema.rb` | A chave `mode` (ver o contrato na §4.5) |

**A regra mora fora do componente de propósito.** Teto de 8, condicional de etapa anterior e
migração sem perda são aceites — e regra escondida dentro de um `.vue` só é verificável montando a
tela inteira, o que torna o teste lento, frágil e vago sobre o que quebrou.

### 4.2 O teto de 8, e a medição que mudou o mecanismo do aceite 21

O aceite diz *"o contador mostra `8/8`"*. **Contando o quê?** Medido: a tela antiga
(`PreChatForm/Settings.vue:78`) regrava o array inteiro, e `helper/preChat.js#getCustomFields`
enfia **todo atributo personalizado da conta** nele com `enabled: false`. Uma conta com 12
atributos tem **12 entradas** em `pre_chat_fields` e **zero** formulário longo.

`[DECISÃO]` — o teto conta campo **habilitado**. Contar entradas do array travaria a tela de quem
nunca configurou nada, e é a mesma razão pela qual o schema do 3.12 não ganhou `maxItems`. Um teste
usa exatamente a forma da frota (3 ligados + 9 desligados) e exige `3 de 8 campos`.

No limite, três coisas acontecem juntas, e as três são asseridas: o contador vira `8 de 8 campos`,
o seletor de adicionar **some** e dá lugar a um botão desabilitado, e **o motivo aparece escrito na
tela** — não em `title`, não em tooltip. Botão cinza sem explicação é a forma mais rápida de fazer
alguém achar que a tela quebrou.

### 4.3 Validação no blur (aceite 26)

O aceite pede algo *"verificável contando renders de mensagem de erro durante a digitação"*. O teste
digita **sete teclas** de um CPF que vai dar inválido e exige `message.exists() === false` **em cada
uma delas**; depois dispara o `blur` e cobra o **texto exato** (`'Confira o CPF: os números não
fecham.'`). Há o par em `en`, e há o caso do `error_message` próprio do cliente ganhando do texto
padrão.

Um quarto teste cobra o que o §B.4.3 decidiu e que é fácil perder no caminho: **anti-lixo é aviso,
não barreira** — a mensagem de `junk_name` não pode sair na cor de erro.

### 4.4 Migrar sem perder campo (aceite 28)

`toBuilder` não move nada: só torna explícito o que já era implícito (etapa 1, posição pela ordem do
array). `toSimple` **não apaga campo nenhum** — traz todos para a etapa 1 e devolve, junto, o que a
volta custa: as etapas que somem e as condicionais que deixam de valer. A tela mostra isso **antes**
de aplicar, com os números no texto, e só migra depois do "sim".

Testado nos dois níveis: ida e volta no modelo puro devolvendo a mesma lista de campos, e na tela
com o diálogo — inclusive que **o modo ainda não mudou** enquanto a pergunta está aberta.

### 4.5 O contrato de `mode` — leia antes de "completar" o schema

Escalei duas vezes nesta trilha, e a segunda foi aqui. **Medido:** a tabela `flows`
(`db/schema.rb:1362-1380`) **não tem `inbox_id`**, e `trigger_config` não carrega `inbox_ids` em
lugar nenhum (`grep` em `app/services/flows/`, `app/models/flow.rb` e no front de automações: zero
ocorrência). Ou seja, *"a tela mostra qual fluxo está vinculado"* (§B.4.5) é uma promessa que a base
não sustenta. A decisão do coordenador: **`mode` entra, `flow_id` não.**

| Chave | Onde | Tipo | Valores | Default | Ausente | Fora do enum |
|---|---|---|---|---|---|---|
| `mode` | `pre_chat_form_options.mode` | string | `simple`, `builder`, `flow` | **não há** — a chave nasce vazia e **não houve backfill** | O front lê o **derivado do conteúdo** (`resolveMode` → `deriveMode`): uma etapa, sem condicional/máscara/validador/ajuda = `simple`; qualquer recurso avançado = `builder`. É o estado de **toda a frota hoje** | **422** no servidor, nomeando `mode`; no front cai no derivado, para a tela nunca ficar num modo que o servidor recusa gravar |

**Por que gravar em vez de derivar sempre:** derivar infere **intenção** a partir de **sintoma**. Um
formulário montado no Construtor que por acaso ficasse com uma etapa e nenhum recurso avançado
voltaria sozinho para "Simples", e o administrador veria a tela trocar de modo sem ter pedido.

**E o que NÃO mora aqui:** no modo `flow`, **qual** fluxo atende o pré-chat **não** se decide nesta
tela e **não** se grava neste jsonb. O motor resolve pelo gatilho do próprio fluxo — `trigger_type` +
`trigger_config`, com o índice `(account_id, trigger_type, active)` que existe exatamente para essa
consulta — e é isso que permite **dois fluxos ativos atenderem URLs diferentes** (aceite do bloco
4.02, da trilha `o3-flows-captura`). Um `flow_id` gravado do lado do formulário seria uma **segunda
fonte de verdade para a mesma pergunta**, e mataria aquele aceite. Por isso o JSON Schema traz
`'flow_id' => false` — recusa explícita, com o comentário do porquê no código e um teste que cobra o
422. **Se você veio aqui para "completar" o schema com o id do fluxo: não é lacuna, é desenho.**

### 4.6 Os dois descritores do mapa canônico

Território da trilha TELAS, acrescentados por esta trilha com aval do coordenador e o contrato
confirmado por eles:

| Chave lógica | `scope` | `path` | `group` | Lê | Ausente |
|---|---|---|:---:|---|---|
| `preChatEnabled` | `channel` | `pre_chat_form_enabled` | não | `Boolean(inbox.pre_chat_form_enabled)` | `false` |
| `preChat` | `channel` | `pre_chat_form_options` | **não** | o objeto inteiro, sobre `{pre_chat_message: '', pre_chat_fields: []}` | o rascunho nasce com a forma vazia, e a tela não quebra no primeiro `.pre_chat_fields` |

**Nenhum dos dois é `group: true`**, e a razão é do contrato deles: `group` existe para as quatro
chaves de `additional_attributes`, onde o update faz merge de primeiro nível e a contagem por
subcampo importa. `pre_chat_form_options` é coluna jsonb do **canal** e viaja **inteira** no PATCH.
**Consequência declarada:** mexer em cinco campos do pré-chat conta **uma** alteração não salva, não
cinco. Contagem por subcampo exigiria mudar a estrutura do mapa, que é território deles.

Os rótulos `INBOX_WIDGET.FIELDS.PRE_CHAT_ENABLED` e `…PRE_CHAT` entraram nos dois idiomas — o teste
de i18n deles percorre `KNOWN_FIELD_PATHS` e teria falhado nomeando a chave que faltasse.

### 4.7 Mecanismo e resultado real

```
$ npx vitest run app/javascript/dashboard/routes/dashboard/settings/inbox/widget
Test Files  9 passed (9)
     Tests  173 passed (173)          # 68 novos desta trilha + os da trilha TELAS

$ rspec spec/models/channel/web_widget_pre_chat_schema_spec.rb spec/controllers/.../inboxes_pre_chat_schema_spec.rb
21 examples, 0 failures               # 4 deles são o contrato do `mode`, vermelhos antes

$ npx eslint <prechat/ + widgetConfigFields.js>     → 0 problemas
$ rubocop <os 4 arquivos ruby>                      → no offenses detected
```

Duas correções que os testes cobraram e que valem registro:

1. **Ordem de campo sem `position`.** A primeira versão tratava ausência como zero, e um teste
   mostrou o formulário embaralhando: campo sem ordem explícita ia para a **frente**. Como a tela
   antiga não grava `position`, isso reordenaria o formulário de toda a frota na primeira
   reordenação. Passou a ir para o **fim**, com teste para o legado inteiro sem `position` nenhum.
2. **O `<dialog>` do jsdom não tem `showModal`.** Montar o `Dialog` real derrubava o teste por
   limitação do ambiente, não por defeito. O stub expõe `open`/`close` como espiões — continua
   verificável **que** a tela pediu confirmação, que é o que o aceite cobra.

---

## 5. Bloco 3.16 — a etapa 1 do pré-chat dentro do preview ✅

**Aceite do plano:** *"O que a tela configura é o que o preview mostra"*.

Este bloco dependia de **3.10** (a trilha TELAS), que ficou pronto em `ce5b47aa6e` e entrou na
`redesenho-integra` em `3ec1d81a5b`. Segundo `git merge redesenho-integra`, limpo.

### 5.1 O que foi feito

| Arquivo | O quê |
|---|---|
| `widget-preview/components/WidgetPreChatPreview.vue` ⚪ | A etapa 1 renderizada: mensagem, campos habilitados na ordem, obrigatório, ajuda, botão e o aviso de "etapa 1 de N" |
| `widget-preview/components/Widget.vue` | Duas props novas (`preChatEnabled`, `preChatOptions`) e o `v-if` que troca as bolhas pelo formulário |
| `Settings.vue` | **duas linhas**, e só: as duas props ligadas ao `inbox` |

**A garantia do aceite não é visual, é estrutural:** quem decide *quais campos entram e em que
ordem* é `fieldsOfStep`, do `preChatModel` — **a mesma função** que o construtor usa. Uma cópia da
regra de ordenação aqui divergiria da de lá sem ninguém notar, que é exatamente a dívida **D4** que
o 3.10 acabou de pagar com a paleta.

Os rótulos passam por `getLabel`/`getPlaceHolder` (`helper/preChat.js`), o mesmo caminho da tela e
do widget: campo padrão sem rótulo gravado cai no **texto traduzido**, e o nome interno
(`emailAddress`) nunca chega ao visitante. Um teste cobra isso literalmente.

**A cor vem por token** (`bg-w-brand` / `text-w-on-brand`), nunca por prop: o aviso do coordenador
sobre o 3.10 foi seguido — `WidgetBody` deixou de receber `:config` de propósito, e reintroduzir a
prop recriaria a segunda fonte de verdade que eles eliminaram. Um teste assere que o botão **não
tem `style` inline**.

### 5.2 A decisão sobre `Settings.vue`, declarada

`Settings.vue` é 🔴 e o plano reserva a ele uma edição mínima, do bloco **3.09** (trilha TELAS, ainda
não entregue). Sem ninguém passando as props, porém, o 3.16 seria **código morto** — o preview teria
a capacidade e nada a acionaria.

`[DECISÃO]` — entrei com **duas linhas**, no mesmo elemento `<Widget>` que já existe
(`Settings.vue:1389-1390`), sem tocar em mais nada do arquivo. É aditivo e fica na mesma região que o
3.09 vai reescrever quando ligar a tela nova ao roteador de abas; se conflitar, a resolução é união.
**Está declarado aqui e foi comunicado ao coordenador** — não é uma edição silenciosa em território
alheio.

### 5.3 Mecanismo e resultado real

`widget-preview/specs/WidgetPreChat.spec.js` — 12 exemplos. Vermelho antes (o componente não existia:
`Failed to resolve import`), verde depois:

```
$ npx vitest run app/javascript/dashboard/modules/widget-preview
Test Files  3 passed (3)        # os 2 do 3.10 + o meu
     Tests  25 passed (25)
```

O aceite, asserção por asserção: campo desabilitado **não** aparece; a ordem é a de `position`; com
3 etapas, o preview mostra **só a 1** e diz "Etapa 1 de 3"; `required` marca `*` e o opcional não;
`help_text` aparece; sem campo habilitado, o preview diz que o visitante vai direto para a conversa;
e com `preChatEnabled: false` o preview continua exatamente como era — inclusive quando as props não
são passadas, que é o estado de qualquer outra tela que monte o preview.

Um detalhe que o teste do 3.10 me cobrou e vale registrar: o `previewTokens.spec.js` deles varre
**todos** os arquivos de `widget-preview/` procurando custom property de cor literal
(`--slate-`, `--solid-`…). O componente novo passa porque usa **classe** de token, não valor — o
gate deles funcionou como rede para a minha entrega também.

---

## 6. Fechamento da trilha

### 6.1 Os quatro blocos

| Bloco | Estado | Mecanismo do aceite | Resultado real |
|---|:---:|---|---|
| **3.12** — `EDITABLE_ATTRS` + schema | ✅ | 15 rspec (12 modelo + 3 request) | verde; vermelho antes em 8 e 3 |
| **3.13** — máscaras e validadores BR | ✅ | 32 vitest | verde; vermelho antes (import não resolvia) |
| **3.14** — a Tela 3 | ✅ | 70 vitest + 6 rspec do `mode` | verde; vermelho antes nos 4 do `mode` |
| **3.16** — etapa 1 no preview | ✅ | 12 vitest | verde; vermelho antes (componente não existia) |

**Commits** (locais, um por bloco, com o id na mensagem — nenhum `push`, nenhum PR, nenhum deploy):

```
194c1a42ef  feat(3.12): pre-chat aceita step, show_if, mask, validator, help_text, error_message e position
de579c5cc6  feat(3.13): mascaras e validadores BR do pre-chat, com a armadilha do CPF fechada
4127767b64  feat(3.14): tela 3 do pre-chat — editor, etapas com teto de 8, condicional e os 3 modos
1775b2f277  fix(3.14): "Sempre mostrar" gravava show_if: null, e o servidor devolve 422
2d3b7551c0  feat(3.16): a etapa 1 do pre-chat aparece dentro do preview
```

### 6.2 Os números finais, medidos depois do último commit

```
$ npx vitest run app/javascript/shared app/javascript/dashboard
Test Files  441 passed (441)
     Tests  4647 passed (4647)

$ rspec spec/models/channel/ spec/controllers/api/v1/accounts/inboxes_pre_chat_schema_spec.rb
96 examples, 0 failures

$ npx eslint <tudo que esta trilha tocou>      → 0 problemas
$ rubocop  <os 4 arquivos ruby>                → no offenses detected
```

As **sete falhas pré-existentes** de `inboxes_controller_spec.rb` (§0.1) continuam sendo as mesmas
sete, e nenhuma tem relação com pré-chat.

### 6.3 O defeito que a revisão pegou, e por que ele importa

Depois de tudo verde, reli o editor de condicional e achei uma incompatibilidade **produtor ×
consumidor**: clicar em "Sempre mostrar" emitia `{ show_if: null }`, e o JSON Schema declara
`show_if` como `type: object`. Os dois lados estavam certos **isolados** — o front limpando o campo,
o servidor recusando forma inválida — e a junção devolveria **422 na operação mais banal do editor**.
Nenhum dos 70 testes do bloco pegava, porque nenhum atravessava a junção.

Corrigido em `updateField` (chave com `null` é apagada, string vazia continua sendo gravada) e
**amarrado dos dois lados**: um teste JS exige que a chave suma, um teste Ruby exige que
`show_if: nil` seja recusado.

### 6.4 O que fica para outras trilhas — e o que NÃO se deve "completar"

1. **`flow_id` não é lacuna, é desenho** (§4.5). Quem mexer no schema do pré-chat vai ver `mode` sem
   um id de fluxo ao lado. O alvo mora no `trigger_config` do **fluxo**, resolvido pelo servidor
   (bloco 4.02, trilha `o3-flows-captura`). Gravar um id aqui mata o aceite *"dois fluxos ativos
   entregam fluxos diferentes conforme a URL"*.
2. **`Settings.vue` levou duas linhas desta trilha** (§5.2), na mesma região que o **3.09** vai
   reescrever. Se conflitar, a resolução é união.
3. **Os dois descritores do pré-chat** em `widgetConfigFields.js` (§4.6) foram escritos por esta
   trilha com aval do coordenador. Nenhum é `group`, e a consequência (uma alteração pendente, não
   N) está declarada.
4. **O bloco 3.15** (o widget honrar `mask`/`validator`/`step`/`show_if`) consome o vocabulário
   fixado aqui: os mesmos nomes valem em `PreChatFormSchema` (Ruby) e em `shared/helpers/brMasks.js`
   (JS), e `widget/helpers/brMasks.js` já existe como caminho de import. **Nome que exista de um
   lado só é campo que a tela oferece e o widget ignora.**
5. **Peso do widget:** `brMasks.js` não traz dependência nova, de propósito (§2.2). Se alguém
   importar `company-email-validator` (222.995 B) ou `libphonenumber-js` (156 kB) no grafo do widget
   para "melhorar" a validação, o gate de 300 kB do bloco 0.5 cai — e a melhoria não é necessária,
   porque as regras já estão aqui.

### 6.5 Divergências declaradas contra o plano 23

1. **Telefone não usa `libphonenumber-js`** (§2.2). A §B.4.3 afirma que ele está "já registrado no
   FormKit do widget (`entrypoints/widget.js:36-38`)" — as linhas 36-38 registram `startsWithPlus` e
   `isPhoneNumberValidWithDialCode`, de `shared/helpers/Validators.js`, e **`libphonenumber-js` não
   aparece em nenhum arquivo de `app/javascript/widget/`**.
2. **`company-email-validator` não foi importado** (§2.2), apesar de instalado: 222.995 bytes de
   domínios contra um teto de 300 kB no grafo inteiro do widget.
3. **"A tela mostra qual fluxo está vinculado" (§B.4.5) não era realizável** (§4.5): não existe
   vínculo inbox↔fluxo na base. O modo Fluxo entrega o que é verdade — que o motor resolve pelo
   gatilho — em vez de um seletor que não teria onde gravar.
4. **O teto de 8 conta campo habilitado, não entrada do array** (§4.2), porque a tela antiga grava
   todo atributo personalizado da conta com `enabled: false`.
5. **Fonte única em `shared/`, não espelho** (§2.1): o plano pedia um helper no dashboard "+ espelho
   no widget"; duas cópias divergem no primeiro conserto feito de um lado só.

---

## 7. Verificação em navegador — o aceite de aparência que estava afirmado, não verificado

Aviso do coordenador depois da entrega: **aceite de aparência conferido só em jsdom não está
verificado**. A trilha TELAS mediu por CDP um catch-all do skin que passa verde no vitest e erra na
tela. Revisei os meus e **dois estavam nesse estado** — mais um terceiro que a medição revelou.

### 7.1 O que estava afirmado

| Aceite | Como estava provado | O problema |
|---|---|---|
| 3.14 — *"anti-lixo é aviso, não erro: a mensagem não vem em vermelho"* | `classes()` **não** contém `ruby` | lê a classe e conclui; não sabe se a classe pinta |
| 3.14 — *"validação dura vem em vermelho"* | `classes()` contém `ruby` | idem — e Tailwind descarta classe desconhecida **em silêncio** |
| 3.16 — *"o botão usa os tokens da marca"* | `classes()` contém `bg-w-brand`; sem `style` inline | idem |

### 7.2 O defeito que a medição achou — e ele era real

`_wa-skin.scss:1840-1853` tem, **sob `.dark`**:

```scss
.bg-n-solid-1                  { background-color: #111b21 !important; }
[class*='text-n-slate-12']     { color: #e9edef !important; }
[class*='text-n-slate-11']     { color: #aebac1 !important; }
[class*='text-n-slate-10']     { color: #8696a0 !important; }
```

O preview ganhou **tema próprio** no bloco 3.10. Com **o painel escuro e o preview claro** — a
combinação que aquele bloco tornou possível —, medido no Chromium **antes** da correção:

```
 FAIL  rótulo do campo        esperado=rgb(28, 32, 36)     recebido=rgb(233, 237, 239)
 FAIL  texto de exemplo       esperado=rgb(128, 131, 141)  recebido=rgb(134, 150, 160)
  ok   botão (bg-w-brand)     esperado=rgb(45, 196, 111)   recebido=rgb(45, 196, 111)
```

Rótulo quase **branco** sobre um painel que o tema claro pede **branco**. Os 12 exemplos de jsdom do
3.16 continuavam verdes — eles verificam estrutura, e estrutura estava certa.

**Por que o botão passou e o texto não:** `bg-w-brand` / `text-w-on-brand` são tokens do **widget**,
que nenhum catch-all persegue. Classe `n-*` é do dashboard, e é a que o skin captura.

### 7.3 A correção

O preview do pré-chat **não usa mais nenhuma classe de cor `n-*`**. As mesmas variáveis
(`--slate-12`, `--slate-11`, `--slate-10`, `--slate-6`, `--ruby-11`), que o preview já declara no
wrapper a partir dos mixins do widget, passam a ser consumidas por classes próprias no `<style
scoped>`. Herdar o token certo não bastava: `!important` vence a variável, então é preciso **não
casar com o seletor**.

Depois: **7/7**, incluindo o tema inverso (painel claro + preview escuro), que prova que a correção
segue o tema do preview e não trocou um acoplamento por outro.

### 7.4 Os mecanismos novos

`chromium.launch()` direto — sem porta, sem servidor, sem tocar em 3038/3999/8899:

| Arquivo | Asserções |
|---|---|
| `widget-preview/specs/browser/prechat-preview-colors.check.mjs` | **7** — as 5 cores nos dois temas, o tema inverso e a trava textual |
| `prechat/specs/browser/field-message-colors.check.mjs` | **4** — erro × aviso nos dois temas do painel |

Três decisões de desenho desses arquivos:

1. **As classes saem do componente real**, por `data-testid`, não de uma fixture: se alguém trocar as
   classes, o teste mede as novas em vez de continuar medindo uma cópia interna.
2. **Trava textual junto da medição:** *"nenhuma classe de cor `n-*` no template"*. A medição só
   segue verde enquanto ninguém as traz de volta, e a asserção olha o `<template>`, não os
   comentários — que citam os nomes justamente ao explicar o porquê.
3. **Diagnóstico que mede sem reprovar.** O fundo do painel do preview
   (`.widget-wrapper.bg-n-solid-1`) sai `rgb(17, 27, 33)` onde o tema claro pede branco. **Essa
   superfície é do bloco 3.10.** Reprovar ali sequestraria o gate de outra trilha; apagar a medição
   esconderia que o par texto/fundo depende das duas. O número fica impresso, com o dono nomeado.

Um detalhe que quase produziu um vermelho falso: na primeira rodada, erro e aviso saíram **os dois**
`rgb(0, 0, 0)`. Faltava injetar `_next-colors.scss` — sem as custom properties do dashboard,
`color: rgb(var(--ruby-9))` é declaração inválida e o texto herda preto. **O harness estava errado,
não o código.** Com os tokens injetados, o erro sai `rgb(229, 70, 102)` nos dois temas.

### 7.5 O gate D4 precisou distinguir declarar de consumir

O teste do 3.10 reprovava qualquer arquivo do preview que **mencionasse** `--slate-`, e a minha
correção passou a **consumir** `var(--slate-12)` — que é o oposto da cópia de paleta que ele existe
para matar. O padrão passou a exigir os **dois-pontos da declaração**, e ganhou uma
auto-verificação: `--slate-1: 252 252 253;` reprova, `color: rgb(var(--slate-12));` não. O gate
continua pegando o defeito para o qual foi escrito.

### 7.6 Resultado

```
$ node .../prechat-preview-colors.check.mjs      7/7 asserções passaram
$ node .../field-message-colors.check.mjs        4/4 asserções passaram
$ npx vitest run <widget-preview + inbox/widget> 15 arquivos, 292 exemplos, 0 falhas
$ npx eslint <o que foi tocado>                  0 problemas
```

**Nenhum aceite desta trilha continua fechado só por jsdom.** Os blocos 3.12 e 3.13 nunca estiveram
nesse estado: são backend em banco real e helpers puros, sem uma asserção de cor entre eles.

---

## 8. A paridade 0.6, depois que ela passou a existir

O coordenador avisou que o teste de paridade entre os dois montadores — dado como existente no
preâmbulo de todas as trilhas — **nunca esteve na base**. Foi restaurado em `5184a6f209`.

Esta trilha **acrescentou chave de configuração**: `mode`, dentro de `pre_chat_form_options`
(§4.5). Então o pedido se aplica. O que foi feito, na ordem pedida:

### 8.1 As duas pontas, conferidas com os olhos

```
app/views/widgets/show.html.erb:45          preChatFormEnabled: <%= @web_widget.pre_chat_form_enabled %>,
app/views/widgets/show.html.erb:46          preChatFormOptions: <%= @web_widget.pre_chat_form_options.to_json.html_safe %>,
app/views/api/v1/widget/configs/…:13        json.pre_chat_form_enabled @web_widget.pre_chat_form_enabled
app/views/api/v1/widget/configs/…:14        json.pre_chat_form_options @web_widget.pre_chat_form_options
```

Os dois emitem o jsonb **inteiro**, e nenhuma chave de topo foi criada por esta trilha — `mode` viaja
dentro do objeto que já viajava. Por isso o 3.12 e o 3.14 não tocaram nos montadores.

### 8.2 A paridade rodada de verdade — e o resultado real

```
$ bundle exec rspec spec/requests/widget_configuration_builder_parity_spec.rb
1 example, 1 failure

  "app/views/api/v1/widget/configs/create.json.jbuilder" => ["api_host"],
- "app/views/widgets/show.html.erb" => ["hasAConnectedAgentBot"],
+ "app/views/widgets/show.html.erb" => ["hasAConnectedAgentBot", "tokens"],
```

**Vermelho — e a única divergência é `tokens`**, do bloco 1.02, já reportada pelo coordenador e de
dona conhecida. **Nenhuma chave desta trilha aparece na diferença**, conforme esperado pela §8.1.
Não toquei nisso.

### 8.3 O buraco que a 0.6 não cobre, e que é exatamente onde eu mexi

A 0.6 compara **chaves de TOPO**: ela extrai os nomes de primeiro nível de cada montador
(`keys_by_canonical_name`) e cruza. **`mode` é aninhada.** Dizer "a paridade cobre o meu `mode`"
seria repetir, em escala menor, o erro que custou caro aqui: confiar numa proteção que não alcança o
que se acrescentou.

E os dois montadores chegam ao mesmo objeto por **caminhos diferentes** — o ERB serializa com
`.to_json.html_safe`, o jbuilder entrega o Hash para o jbuilder serializar. Coincidirem hoje não é
garantia; é coincidência sem mecanismo.

Por isso entrou `spec/requests/widget_pre_chat_payload_parity_spec.rb` — 6 exemplos: o objeto
inteiro idêntico nos dois lados, o `mode`, as **sete** chaves por campo do 3.12, a condicional
intacta, a ausência de `flow_id` e uma auto-verificação.

### 8.4 O gate foi conferido nos dois sentidos, não rodado até ficar verde

```
# sabotando o montador de VERDADE: json.pre_chat_form_options …except('mode')
6 examples, 3 failures     ← acusa, nomeando `mode`
# revertido (git diff do jbuilder: vazio)
6 examples, 0 failures

# e a sabotagem embutida da própria 0.6, para confirmar que ELA está armada:
$ WIDGET_CONFIG_PARITY_SABOTAGE=erb bundle exec rspec …parity_spec.rb
Missing from …create.json.jbuilder: ["paritySabotageKey", "tokens"]
```

**Teste que nunca foi visto falhando é indistinguível de teste que não existe** — que é a lição do
caso, e ela vale para a rede que eu mesmo escrevi.

### 8.5 Estado da suíte Ruby desta trilha, depois do merge

```
$ rspec spec/models/channel/ spec/controllers/…/inboxes_pre_chat_schema_spec.rb spec/requests/widget_pre_chat_payload_parity_spec.rb
102 examples, 0 failures
$ rubocop spec/requests/widget_pre_chat_payload_parity_spec.rb   → no offenses
```

### 8.6 "0 examples, 0 failures" — a armadilha, conferida nesta trilha

Aviso do coordenador: worktree sem `.env` faz o rspec rodar sem banco e imprimir
`0 examples, 0 failures, 1 error occurred outside of examples` — que todo grep ingênuo lê como
verde. **Teste que não roda é indistinguível de teste que passa.**

Esta trilha não caiu nela, e a razão está registrada desde a §0: o env de teste é montado por
`grep`+`export` explícito (`scratchpad/testenv.sh`), **nunca** por `set -a; . .env` — que é o que
quebra na linha 70 do `.env` pelo `<` sem aspas de `MAILER_SENDER_EMAIL`. O banco é dedicado
(`chatwoot_test_o2_prechat`), e `POSTGRES_DATABASE` é cravado ali de propósito, porque
`config/database.yml` usa a mesma variável nos três ambientes.

Mas o aviso pede mais do que não cair na armadilha: pede **conferir se N é o número esperado**.
Contado contra os arquivos, um a um:

| Arquivo | `it` no arquivo | Executados |
|---|:---:|:---:|
| `spec/models/channel/web_widget_pre_chat_schema_spec.rb` | 17 | **17**, 0 falhas |
| `spec/controllers/api/v1/accounts/inboxes_pre_chat_schema_spec.rb` | 5 | **5**, 0 falhas |
| `spec/requests/widget_pre_chat_payload_parity_spec.rb` | 6 | **6**, 0 falhas |
| os 7 specs JS da trilha | 114 | **114**, 0 falhas |

Nenhum `0 examples`, e nenhum número menor que o esperado.

### 8.7 A paridade 0.6, saída crua

```
Widget configuration key parity drifted.
Missing from app/views/api/v1/widget/configs/create.json.jbuilder: ["tokens"]
Missing from app/views/widgets/show.html.erb: []
Expected: {"…show.html.erb" => ["hasAConnectedAgentBot"], "…create.json.jbuilder" => ["api_host"]}
Actual:   {"…show.html.erb" => ["hasAConnectedAgentBot", "tokens"], "…create.json.jbuilder" => ["api_host"]}

1 example, 1 failure
```

**Uma única chave fora do esperado: `tokens`**, do bloco 1.02, roteada à trilha do widget. Do outro
lado, `Missing from …show.html.erb: []` — nada do jbuilder falta no ERB. **Nenhuma chave desta
trilha aparece**, o que era o previsto pela §8.1: o `mode` viaja dentro de `pre_chat_form_options`,
que os dois montadores já emitiam inteiro. Não conserto chave alheia.
