# Onda 2 · Trilha BACKEND DA CONFIG — relatório de execução

**Worktree:** `/home/chatwoot/chatwoot-o2-config-backend` · **Branch:** `o2-config-backend`
**Blocos:** 3.01, 3.02, 3.18, 3.20, 3.03, 3.04 (nesta ordem, respeitando a coluna *Depende*)
**Início:** 18/08/2026

---

## 0. Terreno medido antes de escrever a primeira linha

| O que | Estado medido |
|---|---|
| `app/models/inbox.rb:50` | `store_accessor :additional_attributes, :pin_mode, :pinned_conversation_ids` — duas chaves |
| `inboxes_controller.rb:255-270` (`inbox_attributes`) | o `:217` do plano moveu-se para **`:260`** nesta base; `additional_attributes` permite `pin_mode`, `agent_signature_enabled`, `pinned_conversation_ids: []`, `allowed_template_names: []` |
| merge raso do `#update` | confirmado em `inboxes_controller.rb:52-56` — `.merge`, primeiro nível |
| `json_schemer` | `Gemfile:38`, `0.2.24` no lock; padrão de uso em `integrations/hook.rb:102` |
| Montador ERB | `app/views/widgets/show.html.erb` |
| Montador jbuilder | `app/views/api/v1/widget/configs/create.json.jbuilder` |
| **Spec de paridade 0.6** | **AUSENTE nesta base** — ver §0.1 |
| Banco de teste da trilha | `chatwoot_test_o2config`, criado só para esta trilha (não toca dev/produção) |
| Baseline da suíte | `spec/models/inbox_spec.rb` → **61 verdes, 1 falha pré-existente** (`:45`, `PG::ForeignKeyViolation` em `funnels` no `account.delete`) — falha da base, não desta trilha |

### 0.1 Achado que precede o trabalho: a suíte de paridade da 0.6 não está na base

O aceite do bloco **3.04** diz *"0.6 passa"*. O commit que criou esse teste existe no repositório
(`1a45399b2a`, `spec/requests/widget_configuration_builder_parity_spec.rb`, 97 linhas) **mas não é
ancestral do HEAD desta branch** — `git merge-base --is-ancestor 1a45399b2a HEAD` → falso, e
`git ls-tree -r HEAD | grep parity` não encontra o arquivo.

Sem o arquivo, o aceite de 3.04 não teria mecanismo — seria afirmação. O arquivo foi restaurado a
partir do próprio commit (é spec novo, risco de merge nenhum) e está registrado no commit de 3.04.

---

## Andamento — todos os blocos entregues

| Bloco | Estado | Commit |
|---|---|---|
| 3.01 O lar da configuração | ✅ | `09bbc30faa` |
| 3.02 Schema dos gatilhos | ✅ | `548ab87547` |
| 3.18 Aparência fora do `localStorage` | ✅ (uma parte do aceite depende do SDK — §2 item 1) | `b1e7cc6f23` |
| §B.4 `home_intents` (roteado pelo coordenador) | ✅ | `36c50d46b2` |
| 3.20 Abordagem em três níveis | ✅ | `817ff0fb53` |
| 3.03 `WidgetProfile.resolve` + seed | ✅ | `a4827afb92` |
| 3.04 As quatro chaves nos dois montadores | ✅ | `ad5c637f26` + `da252044a0` |
| 3.18c Teto tolerante à inbox legada | ✅ | `bd78983e13` |

---

## 1. Blocos entregues

### 3.01 — O lar da configuração · commit `09bbc30faa`

As quatro chaves de topo de `inbox.additional_attributes`, declaradas **numa única edição** do strong
params (`inbox_attributes`, `:255-265` nesta base — o `:217` do plano moveu-se com os merges):

```ruby
{ additional_attributes: [:pin_mode, :agent_signature_enabled, :widget_profile,
                          { pinned_conversation_ids: [], allowed_template_names: [],
                            widget_triggers: {}, widget_tracking: {}, widget_appearance: {} }] }
```

**Decisão de desenho registrada:** a lógica não foi escrita dentro de `inbox.rb` (arquivo 🟡 do
upstream), e sim numa concern nova, `WidgetConfigurable`. `inbox.rb` recebe **uma linha** (`include`)
mais a constante do teto. É a alternativa que menos texto acrescenta ao arquivo que o próximo merge
de upstream vai tocar. O `store_accessor` da concern e o que já existia em `inbox.rb:50` convivem —
`store_accessor` acumula no mesmo jsonb, e há um exemplo que prova que `pin_mode` continua íntegro.

**A lista negativa de segredos entra já aqui**, como o bloco exige, e é varrida **em profundidade**:
`*_token`, `*_secret`, `api_secret` e as chaves nuas `token`/`secret`, em objeto aninhado e em array
de objetos. `tokenizer_mode` passa (a palavra no meio não é segredo). Chave de `additional_attributes`
fora das quatro do widget **não** é policiada — o bloco 5.01 amplia, não substitui.

| Aceite do bloco | Mecanismo |
|---|---|
| `PATCH widget_profile: "marketing"` persiste e volta no `GET` | `inboxes_controller_widget_config_spec.rb:25` |
| `PATCH widget_appearance: {position: "left"}` idem | `:33` |
| valor inválido → 422 | `:52` — 422 com `attributes: ["widget_profile"]` |
| `PATCH` parcial não apaga as outras três | `:81` — grava as quatro, patcheia uma, lê as quatro |
| inbox sem as chaves continua funcionando | `:135` |
| nenhum segredo aceito | `:61` + 6 exemplos de modelo |

### 3.02 — Schema dos gatilhos · commit `548ab87547`

`WidgetTriggersSchema` (arquivo novo) com os sete gatilhos por `id`, `desktop`/`mobile`
(`enabled`/`value`/`selector`), cooldown, `defaults` e `audience` (url/utm/device).
`additionalProperties: false` em todo nível — um typo (`tirggers`) é recusado em vez de virar dado
morto no jsonb.

O tradutor de erro é `WidgetSchemaErrorMessage`: `data_pointer` vira o **caminho do campo**
(`triggers/0/desktop/value`) e o tipo do erro vira frase útil. Nos dois idiomas.

| Aceite | Mecanismo |
|---|---|
| objeto válido persiste | `inbox_widget_triggers_schema_spec.rb:27` |
| `value` negativo → 422 nomeando o campo | `:39` e o request spec |
| `id` desconhecido → 422 | `:46` — nomeia o campo **e** lista os sete aceitos |
| seletor vazio → 422 | `:56` |

**Vermelho medido antes do verde:** com a linha `validate :ensure_widget_triggers_match_schema`
desligada, 8 dos 10 exemplos falham; os 2 que sobrevivem são os que provam que objeto válido continua
passando (se falhassem, o teste estaria medindo outra coisa).

### 3.18 — A aparência sai do `localStorage` · commit `b1e7cc6f23`

`WidgetAppearanceSchema` com os nove campos. Os valores **casam com o vocabulário que o SDK já
entende** (`sdk/constants.js`), para que a precedência seja comparável campo a campo:

| Campo | Valores | Nome no `chatwootSettings` (site) |
|---|---|---|
| `theme` | `light` \| `auto` \| `dark` | `darkMode` |
| `position` | `left` \| `right` | `position` |
| `offset_x`, `offset_y` | inteiro 0–200 | — |
| `launcher_type` | `standard` \| `expanded_bubble` | `type` |
| `launcher_text` | string ≤ 64 | `launcherTitle` |
| `hide_bubble` | booleano | `hideMessageBubble` |
| `panel_style` | `standard` \| `flat` | `widgetStyle` |
| `launcher_icon` | `default` \| `image` \| `agent_photo` | — |

O mapa acima está **no código**, em `WidgetAppearanceSchema::OVERRIDABLE_BY_SITE` — é o vocabulário
comum entre backend, SDK e tela, para que ninguém invente um terceiro nome para a mesma coisa.

**Teto do jsonb: 16.384 bytes**, calibrado por medição e não por chute — nesta VM são 17 inboxes e o
maior `additional_attributes` tem **56 bytes** (0,34% do teto). O 422 diz o limite **e a razão** ("é
servido em toda página do site do cliente").

**Front:** `Settings.vue` lê e grava no servidor; `constants/localStorage.js` perde a chave
`WIDGET_BUILDER`. O PATCH envia o objeto de aparência **inteiro**, com o que já estava gravado por
baixo — o merge do servidor é raso, e mandar só os três campos desta tela apagaria tema, offsets,
estilo e ícone. É a classe de defeito "o formulário reenvia e o servidor sobrescreve".

| Aceite | Mecanismo |
|---|---|
| objeto válido persiste | `inbox_widget_appearance_spec.rb:17` |
| `position: "center"` → 422 nomeando o campo | `:23` + request spec |
| offset 500 → 422 | `:31` |
| texto de 200 caracteres → 422 | `:39` (e 64 exatos passa, `:47`) |
| **admin A grava, admin B lê em outra sessão** | request spec — dois administradores, dois tokens |
| jsonb acima do teto → 422 | `:74` + request spec |
| a tela não usa mais `localStorage` | `Settings.widgetAppearance.spec.js` — 5 exemplos |

**Vermelho medido:** sem as duas validações novas, 6 dos 12 exemplos de modelo falham; com o
`Settings.vue` anterior, 4 dos 5 exemplos de vitest falham.

**O que este bloco NÃO entrega, e por quê.** O aceite pede que "a tela declare que há override
ativo". A tela declara a **regra** (banner novo, pt-BR e en), mas não pode afirmar override **ativo**
por campo: o dashboard não lê o HTML do site do cliente. Detectar override em runtime exige que o
SDK reporte quais chaves de `chatwootSettings` estão presentes — e `sdk.js`/`IFrameHelper.js` não
estão na lista de arquivos deste bloco. **Registrado como junção pendente com a trilha da tela
(3.09) e com a frente W.** O vocabulário para isso já existe: `OVERRIDABLE_BY_SITE`.

### 3.20 — A abordagem em três níveis · commit `817ff0fb53`

`approach` (`discreet` | `bold` | `aggressive`), `approach_mobile` e `degrade_on_return`, **dentro de
`widget_triggers`** (A15): zero chaves novas de topo, zero edições novas no controller.

`approach_mobile` nunca herda `aggressive` — **nas duas pontas**: o schema recusa a escrita (422) e a
leitura derivada rebaixa para `bold`. Fechar só uma ponta deixaria o valor entrar por outro caminho.

A recusa vem com a razão junto: *"abertura automática não é oferecida em celular — lá o painel cobre
a tela inteira; use discreet ou bold"*. Um enum que só diz "valor não permitido" faz uma decisão de
produto parecer erro de digitação.

| Aceite | Mecanismo |
|---|---|
| `approach: "bold"` persiste e volta no `GET` | `inbox_widget_approach_spec.rb:11` + request spec |
| `approach: "agressivo"` → 422 | `:26` |
| `approach_mobile: "aggressive"` → 422 nomeando o campo, com a razão | `:56` (e `:70` em pt-BR) |
| inbox sem a chave → `bold` + `degrade_on_return: true` | `:83`, e `:106` prova que resolver **não escreve** |

### 3.18b — `home_intents`: a lacuna da §B.4, roteada pelo coordenador · commit `36c50d46b2`

**Decisão: caminho (a) — o campo é declarado agora.** O contrato, chave por chave:

| Item | Contrato |
|---|---|
| **Onde mora** | `inbox.additional_attributes['widget_appearance']['home_intents']` |
| **Por que ali** | as quatro chaves de topo são fechadas (A1/A15 — uma quinta custaria a segunda edição no `inboxes_controller.rb` 🔴). Entre as quatro, `widget_appearance` já é o lar do que o visitante **vê**, texto incluso (`launcher_text` é precedente direto). `widget_triggers` é *quando/intensidade*; `widget_tracking` é identificador público; `widget_profile` é escalar |
| **Tipo** | array de objetos |
| **Item** | `{ "id": string, "label": string }`, ambos obrigatórios, `additionalProperties: false` |
| **`id`** | inglês `snake_case` (A2), `^[a-z][a-z0-9_]{0,31}$`. Invisível ao visitante; é a chave que a telemetria por intenção (4.21) agrupa. **Estável** — renomear `id` perde a série histórica |
| **`label`** | texto que o visitante lê, 1 a 48 caracteres. É **conteúdo do cliente**, na língua dele — **nunca** i18n do produto. O i18n traz apenas *sugestões* que a tela oferece ao configurar |
| **Cardinalidade** | 2 a 4 quando presente. `[]` é válido e significa "a tela inicial de hoje". **1 item → 422** ("uma opção sozinha não é escolha") |
| **`id` duplicado** | 422 nomeando os ids repetidos — dois ids iguais quebram a telemetria sem que o visitante veja erro nenhum |
| **Chave ausente** | **não é erro.** `resolved_widget_appearance` devolve `[]`, e a inbox existente se comporta exatamente como hoje. Sem migration e sem backfill (A4) |
| **Fora do contrato** | 422 nomeando o campo com o caminho: `home_intents/0/label`, `home_intents/0/id`, `home_intents/0/action` (campo desconhecido) |
| **Nos montadores** | sai dentro de `widget_appearance` resolvido, nos **dois** — logo a paridade 0.6 cobre |
| **i18n (pt-BR e en)** | `INBOX_WIDGET.HOME_INTENTS`: `LABEL`, `DESCRIPTION`, `HELP`, `SUGGESTIONS.{PRICING,SUPPORT,PRODUCT}`, `ERRORS.{NEED_TWO,DUPLICATED_ID}` |

11 exemplos cobrem cada linha dessa tabela (`spec/models/inbox_widget_home_intents_spec.rb`).

### 3.03 — `WidgetProfile.resolve` → flags planas · commit `a4827afb92`

As onze flags da §B.3, todas escalares, com o conjunto de chaves verificado por **igualdade** (não
por amostragem — um teste que só checa três chaves não percebe a quarta faltando).

**Precedência, implementada onde ela importa:** `csatOnResolve` espelha `csat_survey_enabled`,
`emailContinuity` espelha `continuity_via_email`, e `captureFlow` só vira `conversational` quando o
pre-chat está de fato ligado. O valor gravado vence o perfil, sempre.

**O seed semeia só `widget_triggers`, e só na criação.** Coluna que já existe **não** é semeada — e
isso não é omissão, é o aceite do próprio bloco: *"inbox com `csat_survey_enabled: false` e perfil
`support` continua com CSAT desligado"*. Semear coluna na criação sobrescreveria o que o
administrador mandou no mesmo `POST`, e não há como o modelo distinguir "o admin mandou `false`" de
"o default da coluna é `false`". O perfil **propõe** mudança de coluna na tela (regime 2 de A3), que
é da trilha das telas.

### 3.04 — As quatro chaves nos dois montadores · commits `ad5c637f26` e `da252044a0`

| Chave | `show.html.erb` | `create.json.jbuilder` | Conteúdo |
|---|---|---|---|
| perfil | `widgetProfile` | `widget_profile` | `resolved_widget_profile` (`nil` → `support`) |
| flags | `profileConfig` | `profile_config` | `WidgetProfile.resolve` — 11 chaves camelCase **nos dois** |
| gatilhos | `widgetTriggers` | `widget_triggers` | gravado + abordagem **resolvida por dentro** |
| tracking | `widgetTracking` | `widget_tracking` | **projeção por lista branca** |
| aparência | `widgetAppearance` | `widget_appearance` | sempre completa (banco sobre o padrão) |

As chaves de **topo** seguem a convenção de cada arquivo; o **conteúdo** é idêntico, e há um exemplo
que compara os dois payloads campo a campo — porque quem consome os dois é o mesmo código do widget.

**A abordagem não ganhou chave própria no payload, de propósito.** Uma primeira versão emitia
`widgetApproach` ao lado; foi desfeita antes do commit. Dois lugares para o mesmo fato obrigariam o
SDK a ler dois caminhos para tomar uma decisão só, que é exatamente o que a A15 evita ao pôr os três
campos dentro de `widget_triggers`.

**Casamento com o consumidor** (exigência do coordenador): conferido chave por chave contra
`widget/helpers/profileConfigHelper.js` (commit `208d878e63`, trilha complementar, escrita
contract-first). **Batem integralmente** — mesmos 11 nomes camelCase, mesmos tipos, mesmos defaults
(`teaserDelayMs` 8000, `teaserScrollPercent` 30, enums de `captureFlow`/`primaryExit`/`homeLayout`).
Nenhum ajuste foi necessário em nenhuma das duas pontas, e nada foi mudado em silêncio.

**A suíte de paridade da 0.6 foi restaurada** (§0.1) e verificada nos **dois sentidos** com a
sabotagem que ela própria traz: `WIDGET_CONFIG_PARITY_SABOTAGE=erb` acusa a chave faltando no
jbuilder, `=jbuilder` acusa a que falta no ERB. Depois das cinco chaves novas, ela passa.

**Segredo:** um `access_token` gravado **por baixo** da validação (`update_column`, para simular o
caminho que não passa pela lista negativa) **não sai por nenhum dos dois montadores**, e a varredura
por `/token|secret/` nas quatro chaves dos dois payloads volta vazia. Trocando a projeção pelo hash
cru, 5 dos 13 exemplos falham — a rede prende.

---

### 3.18c — O teto do jsonb não pode travar quem já estava acima dele · commit `bd78983e13`

Achado durante a revisão do próprio trabalho, não por um teste que falhou. Uma inbox de WhatsApp com
centenas de `allowed_template_names` passa de 16 KB sem esforço — e, com a validação como estava
escrita, ela ficaria **inatualizável**: o administrador abriria a tela, salvaria qualquer campo e
receberia 422 sobre uma coisa em que não tocou.

É a cicatriz nº 1 desta execução em outro lugar: validação que nasce vermelha em cliente real e passa
despercebida porque o banco de teste está limpo. A regra passou a ser sobre **crescimento**: acima do
teto, o update só é recusado se o objeto aumentar. Encolher pode, ficar igual pode; inbox nova
continua com o teto duro. Quatro exemplos, e o primeiro deles verifica que a fixture está mesmo acima
do teto — sem ele, os outros três passariam medindo um cenário que não existe.

## 2. O que ficou fora, e por quê

1. **"A tela declara que há override *ativo*" (aceite de 3.18).** Entregue: a tela declara a **regra**
   de precedência, nos dois idiomas. Não entregue: dizer, campo a campo, que o site está
   sobrescrevendo **agora** — o dashboard não lê o HTML do site do cliente, e detectar isso exige que
   o SDK reporte quais chaves de `chatwootSettings` estão presentes. `sdk.js` e `IFrameHelper.js` não
   estão na lista de arquivos deste bloco. **Junção pendente com 3.09 e com a frente W**; o
   vocabulário para fazê-lo já existe e está no código (`WidgetAppearanceSchema::OVERRIDABLE_BY_SITE`).
2. **O diálogo de troca de perfil** (regime 2 de A3 — "propõe, listando nominalmente o que muda"). É
   tela; o backend entrega o que ela precisa (`WidgetProfile.resolve` e as colunas intactas).

## 3. Riscos e observações para a integração

- **Conflito previsto com `redesenho-integra`:** medido com `git merge-tree` (sem tocar em nada), são
  **dois** arquivos: `i18n/locale/{pt_BR,en}/inboxWidget.json`. É conflito **textual e aditivo**, não
  semântico: a trilha complementar usa `INBOX_WIDGET.APPEARANCE.BRAND_COLOR`, esta trilha usa
  `APPEARANCE.SITE_OVERRIDE`, mais `APPROACH` e `HOME_INTENTS`. A união das duas resolve. `show.html.erb`,
  `config/locales/*.yml` e o resto fazem auto-merge.
- **`inbox.rb` cresceu uma linha** e o `Metrics/ClassLength` do rubocop foi de `182/175` para
  `183/175`. A ofensa **já existia** na base; a concern é a alternativa que menos texto acrescenta ao
  arquivo do upstream. Nenhuma ofensa nova de rubocop foi introduzida em nenhum arquivo.
- **Falhas pré-existentes da base**, medidas com as mudanças revertidas (`git stash`) e idênticas
  depois: 8 em `inbox_spec` + `inboxes_controller_spec` (FK de `funnels` no `account.delete`, health
  do WhatsApp, branded email layout). **Nenhuma delas é desta trilha.**
- **Banco de teste próprio da trilha:** `chatwoot_test_o2config`. Nenhum comando tocou o banco de
  desenvolvimento/produção desta VM; a única leitura ali foi um `SELECT` de contagem para calibrar o
  teto do jsonb.

---

## 4. Verificação — o que foi executado, e o número real

Banco de teste da trilha: `chatwoot_test_o2config`. Comandos: `bundle exec rspec`,
`bundle exec rubocop`, `pnpm exec vitest`, `pnpm exec eslint`.

### 4.1 Os mecanismos desta trilha

| Suíte | Exemplos | Falhas |
|---|---|---|
| `spec/models/inbox_widget_config_spec.rb` (3.01) | 15 | 0 |
| `spec/models/inbox_widget_triggers_schema_spec.rb` (3.02) | 10 | 0 |
| `spec/models/inbox_widget_appearance_spec.rb` (3.18 + 3.18c) | 16 | 0 |
| `spec/models/inbox_widget_approach_spec.rb` (3.20) | 13 | 0 |
| `spec/models/inbox_widget_home_intents_spec.rb` (§B.4) | 11 | 0 |
| `spec/services/widget_profile_spec.rb` (3.03) | 16 | 0 |
| `spec/controllers/.../inboxes_controller_widget_config_spec.rb` (API) | 19 | 0 |
| `spec/requests/widget_configuration_payload_spec.rb` (3.04) | 13 | 0 |
| `spec/requests/widget_configuration_builder_parity_spec.rb` (0.6, restaurada) | 1 | 0 |
| **Subtotal Ruby** (rodado junto, uma vez) | **114** | **0** |
| `Settings.widgetAppearance.spec.js` (vitest, 3.18 front) | 5 | 0 |
| **Total** | **119** | **0** |

### 4.2 Vermelho antes do verde — medido, não afirmado

| Bloco | Sabotagem | Resultado |
|---|---|---|
| 3.02 | validação de schema desligada | 8 de 10 falham |
| 3.18 backend | as duas validações desligadas | 6 de 12 falham |
| 3.18 front | `Settings.vue` anterior (via `git stash`) | 4 de 5 falham |
| 3.04 | projeção trocada pelo hash cru | 5 de 13 falham |
| 0.6 | `WIDGET_CONFIG_PARITY_SABOTAGE=erb` / `=jbuilder` | falha nos dois sentidos, nomeando a chave e o arquivo |

### 4.3 Regressão — comparação maçã com maçã, duas vezes

**Suíte ampla** (`spec/models`, `spec/controllers/api/v1/widget`, `spec/requests`,
`inboxes_controller_spec`), rodada no commit base (`c06ba1824e`) e nesta branch, com os specs novos
excluídos por `--exclude-pattern` para que o conjunto de arquivos seja **exatamente o mesmo**:

```
base   : 1561 examples, 22 failures, 39 pending
branch : 1561 examples, 22 failures, 39 pending
diff das listas de falhas: IDÊNTICAS
```

**Os 15 arquivos que falham, rodados isolados**, nos dois lados:

```
base   : 395 examples, 21 failures
branch : 395 examples, 21 failures
diff das listas de falhas: IDÊNTICAS
```

Nenhuma falha nova. As pré-existentes são de FK de `funnels` no `account.delete`, health do WhatsApp,
branded email layout, flows, `switch_locale` e afins — nada que esta trilha tenha tocado.

`bundle exec rubocop` nos 46 arquivos das pastas tocadas: **0 ofensas**. A única ofensa que
permanece no repositório nessa vizinhança é o `Metrics/ClassLength` de `inbox.rb`, que já existia
(`182/175` antes, `183/175` depois da linha do `include`).

Chaves de i18n conferidas nos dois idiomas por script: `pt_BR - en` e `en - pt_BR` são conjuntos
**vazios** em `inboxWidget.json`.

### 4.4 Um susto que valeu a investigação — e uma armadilha desta base

A primeira comparação da suíte ampla deu **22 falhas na base contra 31 na branch**, com nove delas em
`flow_*_spec` e uma em `message_sequence_enrollment_spec` — arquivos que esta trilha não toca. A
mensagem de falha era estranha:

```
expected collection contained:  [#<FlowStepLog id: 3, ...>]
actual collection contained:    [#<FlowStepLog id: 3, ...>]
the missing elements were:      [#<FlowStepLog id: 3, ...>]
```

O mesmo registro, do mesmo id, "faltando" e "sobrando" ao mesmo tempo. `ActiveRecord::Base#==`
compara `instance_of?(self.class)` — dois objetos idênticos só falham assim quando a **classe foi
recarregada no meio da suíte** e existem duas constantes `FlowStepLog` vivas.

A causa: `config/environments/test.rb:11` traz `config.cache_classes = false`, e **eu editei
arquivos de `app/models/concerns/` enquanto a suíte rodava em background** (o run começou 13:34:53 e
o commit `bd78983e13` é de 13:41:05). O file watcher recarregou as classes no meio da execução.

**Fica registrado como armadilha desta base:** nesta configuração, editar código com uma suíte longa
rodando em background produz falhas fantasma em specs que ninguém tocou. Um relatório que tivesse
copiado aquele "31 falhas" teria acusado uma regressão que não existe — e um que tivesse ignorado a
diferença teria escondido uma que poderia existir. A resposta é medir de novo sem tocar em nada — e foi o que a §4.3 fez: **1561 / 22 / listas
idênticas** dos dois lados.
