# Onda 0 — Blocos 0.7, 0.8 e 0.9 (executor CFG1)

Worktree: `/home/chatwoot/chatwoot-redesenho-config` · Branch: `redesenho-config` · Base: `6ad7a9ec6e`

**Relatório incremental — escrito conforme avanço, não no fim.**

> ## ✅ RATIFICAÇÃO DO COORDENADOR (17/08, posterior a este relatório)
>
> **As duas autorizações eram minhas. Ratifico as duas, por escrito, e assumo ambas.**
>
> O executor agiu **certo** ao marcar o próprio trabalho como "a descoberto": procedência que não
> se confere não é autorização, e ele aplicou a si a mesma régua que aplica aos aceites. O erro não
> foi dele — foi de coordenação, e é meu.
>
> **O que aconteceu:** um reinício de sessão deixou **duas instâncias de coordenador** vivas sobre
> o mesmo Run. A segunda não tinha o meu contexto, viu uma autorização que não reconhecia, e a
> repudiou. A dúvida respingou na outra, que veio pelo mesmo canal na mesma tarde.
>
> **A prova de que as duas são minhas**, e é conferível no meu transcript:
>
> | Bloco | O que eu medi ANTES de autorizar | Onde |
> |---|---|---|
> | **0.8** | que `#2dc46f` é a cor da marca — `fill="#2dc46f"` no logo e o comentário *"verde brand ChatSPX — match com logo"* | `Logo.vue:28`, `LordIconIcon.vue:37-38` |
> | **0.9** | que a 5ª linha era necessária, e que o orçamento do plano errava **duas vezes** (contava o `computed inbox()`, que é referência; não contava o preview) | `Settings.vue`, e a §12.4 que eu escrevi no PLANO-MESTRE |
>
> Uma autorização que exige medição própria antes de ser dada não é a que um impostor produz.
>
> **O que continua verdadeiro, e não muda com a ratificação:** o 0.8 item 2 **é decisão de
> produto** — inbox nova por API/onboarding deixa de nascer azul. Ela é minha, está registrada com
> o motivo (adotar o azul tiraria a cor da marca do produto **como efeito colateral de um bloco de
> coerência**, que é o que a §8.1 do plano existe para impedir), e continua **reversível em três
> passos**, descritos na §0.8.2. Quem responde por produto pode desfazê-la a qualquer momento — o
> que ela não pode é acontecer por omissão.
>
> **Lição de processo, registrada:** duas instâncias de coordenador sobre o mesmo Run tornam
> qualquer autorização inconferível. O `run-use` não fenceia a instância antiga. Antes de repudiar
> uma autorização, o coordenador tem de verificar se ela é sua — e não presumir que não é.

---

> ## ⚠️ AVISO ORIGINAL DO EXECUTOR — mantido como escrito (ver ratificação acima)
>
> Escalei duas vezes, as duas antes de editar, como as restrições mandavam. Nas duas chegou pelo
> canal do `ask` uma resposta que se apresentava como do coordenador e autorizava. **Nenhum
> coordenador assume nenhuma das duas.** O coordenador responsável repudiou por escrito a do bloco
> 0.9; a do bloco 0.8 veio pelo mesmo canal na mesma tarde, então cai junto.
>
> | Onde | O que segui sem autorização conferível | Estado |
> |---|---|---|
> | **0.8 item 2** (`3a07565337`) | unificar o default de cor no verde `#2dc46f` (**decisão de produto**: inbox nova por API/onboarding deixa de nascer azul) + editar 2 arquivos Ruby **fora dos meus nominais** | **aberto — precisa de decisão de quem responde por produto** |
> | **0.9** (`6d4c8b608b`) | gastar um 5º sítio no `Settings.vue` (arquivo 🔴 com orçamento nominal) | **mérito técnico RATIFICADO** pelo coordenador depois, contra 3 refs; o orçamento do PLANO-MESTRE §12.3 foi corrigido para cinco sítios. Só a autorização não existiu |
>
> O 0.8 é o que ainda precisa de alguém: é mudança de produto visível no widget de cliente novo.
> É reversível em três passos, descritos em §0.8.2. O código dos dois blocos passa nos aceites; o que
> estava errado era eu chamar de autorizado o que ninguém autorizou.

## Verificação de pré-requisito (feita antes de tocar em qualquer arquivo)

Conferi os meus 6 arquivos contra a lista de 22 correções pendentes do merge
(`onda-0-correcoes-pendentes.md`). **Nenhum aparece lá:**

| Meu arquivo | Está nas 22? |
|---|---|
| `settings/inbox/WidgetBuilder.vue` | não |
| `i18n/locale/{pt_BR,en}/inboxMgmt.json` | não (item 14 é `.liquid`; H6 é dívida geral, não correção nominal) |
| `i18n/locale/{pt_BR,en}/inboxWidget.json` | não (arquivo novo) |
| `channels/Website.vue` | não |
| `settingsPage/ConfigurationPage.vue` | não |
| `dashboard/helper/preChat.js` | não |
| `settings/inbox/Settings.vue` | não (o item 19 cita outros arquivos de dashboard) |

Também disjunto dos arquivos do executor de correções do dashboard citados pelo coordenador
(`ConversationList.vue`, `actionCable.js`, sidebar, Captain, preview restrito, busca compacta,
`ReplyTopPanel`, dropdowns de ação em massa, `MentionBox.vue`).

---

# BLOCO 0.7 — Limpeza morta ✅ CONCLUÍDO

Origem: T0.2, T0.3, T0.9 · Commit local: `chore(0.7)`

## 0.7.a — Prova de orfandade do `WidgetBuilder.vue` (feita ANTES de apagar)

Cinco medições independentes, porque a instrução era explícita: *"arquivo órfão que na verdade é
lazy-import por string derruba a tela em produção sem erro de build"*.

```
1) grep -rn "WidgetBuilder" app/javascript/                      → VAZIO
```

Vazio **incluindo o próprio arquivo** — ele não tinha `name:` no `export default`, então nem
se auto-referenciava. Nenhuma rota, nenhum `import`.

```
2) grep -n component app/javascript/.../inbox/inbox.routes.js
   → SettingsWrapper, InboxHome, SettingsContent, InboxChannel, ChannelList,
     FinishSetup, ChannelFactory, AddAgents, Settings
   → nenhuma rota aponta para WidgetBuilder. Não havia rota para sair junto.

3) import dinâmico por string / glob que pudesse capturá-lo:
   grep -rnE "import\.meta\.glob|require\.context|import\(\s*`" app/javascript/dashboard/
   → só 2 ocorrências, ambas de ícone:
       components-next/animated-icons/AnimatedIcon.vue:9   import.meta.glob('./*Icon.vue')
       components-next/icon/Icon.vue:9                     import.meta.glob('../animated-icons/*Icon.vue')
   → nenhum glob alcança settings/inbox/. Nenhum require.context no dashboard.

4) git show --stat 7b2b3ac37d -- .../WidgetBuilder.vue
   → 443 deletions  (feat(V5): Update settings pages UI #13396)
   git merge-base --is-ancestor 7b2b3ac37d HEAD           → SIM

5) git cat-file -e v4.12.1:.../WidgetBuilder.vue          → não existe
   git cat-file -e v4.16.2:.../WidgetBuilder.vue          → não existe
```

Confere byte a byte com a medição M11 do PLANO-MESTRE (13.198 bytes) e com a §A.3.5 do plano 23.
**Veredito: órfão. Apagado com `git rm`.**

### O que NÃO saiu junto, e por quê

- **`components/InputRadioGroup.vue`** — era importado pelo `WidgetBuilder.vue`, mas
  `SmtpSettings.vue:7,14,219` continua usando. Não é órfão; fica.
- **`constants/localStorage.js:4` (`WIDGET_BUILDER: 'widgetBubble_'`)** — é a chave do defeito
  **D1** (posição/tipo de bolha no `localStorage`), consumida por `Settings.vue`. Viva; fica.
- **`INBOX_MGMT.WIDGET_BUILDER` (bloco de primeiro nível do `inboxMgmt.json`)** — **NÃO é órfão.**
  `Settings.vue:1111-1184` e `widget-preview/Widget.vue:94-101` leem 9 chaves de dentro dele,
  incluindo a `SCRIPT_SETTINGS` que é o JavaScript do snippet (defeito **D3**). Intocado.
  A confusão de nome é real e por isso está registrada aqui: **só as duas chaves de `TABS` eram
  órfãs**, não o bloco homônimo.

## 0.7.b — As 2 chaves i18n órfãs (D7)

```
grep -rnE "TABS\.(CAMPAIGN|WIDGET_BUILDER)" app/ | grep -v i18n/locale   → VAZIO
```

Removidas de `INBOX_MGMT.TABS` em `en/inboxMgmt.json` e `pt_BR/inboxMgmt.json` — 2 linhas em cada
arquivo, edição cirúrgica, sem reserializar o JSON (o arquivo é 🔴 de merge; um `json.dump` teria
reescrito 800 linhas e criado conflito com o upstream em toda a superfície).

**Escopo deliberadamente limitado a `en` e `pt_BR`**, como T0.3 nomeia. As chaves existem em ~40
locales gerados pelo Crowdin; apagá-las nos 40 seria edição em massa (proibição absoluta) e o
Crowdin as reintroduziria no próximo sync. Os outros locales caem no fallback e não há consumidor.

## 0.7.c — Namespace `inboxWidget` (T0.9)

- `i18n/locale/en/inboxWidget.json` — novo, `{"INBOX_WIDGET": {}}`
- `i18n/locale/pt_BR/inboxWidget.json` — novo, idem
- registrado nos dois `locale/*/index.js` (import + spread), ao lado de `inboxMgmt`

Só nos dois idiomas: `createI18n` em `entrypoints/dashboard.js:39-43` não define
`fallbackLocale`, então o vue-i18n usa `locale` (`'en'`) como fallback — os outros 38 locales caem
em `en`. É o mesmo mecanismo que já sustenta os 6 arquivos que `el` não tem (45 de 51).

## 0.7.d — Aceite (§2.2, palavra por palavra)

> "grep -rn WidgetBuilder app/javascript → vazio; inboxWidget.json existe nos dois idiomas"

```
$ grep -rn "WidgetBuilder" app/javascript/
                                                     → VAZIO                      ✅ PASS
$ ls app/javascript/dashboard/i18n/locale/{en,pt_BR}/inboxWidget.json
  en/inboxWidget.json      25 bytes
  pt_BR/inboxWidget.json   25 bytes                  → existe nos dois idiomas    ✅ PASS
```

### Mecanismo durável, não só o grep

`grep` é medição de um instante; não impede regressão. Escrevi
`app/javascript/dashboard/i18n/specs/inbox-widget-namespace.spec.js` (6 testes) que asserta o
**objeto de mensagens que o vue-i18n recebe em runtime** — não a existência do arquivo em disco.
A distinção importa: criar o `.json` e esquecer o `index.js` passaria num teste de arquivo e
falharia no produto.

```
$ pnpm exec vitest run --no-cache app/javascript/dashboard/i18n/specs/inbox-widget-namespace.spec.js
 ✓ 6 tests   |   Test Files 1 passed (1)   Tests 6 passed (6)
```

**Prova de que o teste não é tautológico** — as mesmas asserções avaliadas sobre os bytes de `HEAD`
(via `git show HEAD:<path>`, sem tocar a árvore de trabalho):

```
[en]    inboxWidget.json em HEAD: AUSENTE          → asserção 1: FAIL
[en]    index.js de HEAD registra inboxWidget: False
[en]    chaves órfãs presentes em HEAD: ['CAMPAIGN','WIDGET_BUILDER'] → asserção 2: FAIL
[pt_BR] inboxWidget.json em HEAD: AUSENTE          → asserção 1: FAIL
[pt_BR] index.js de HEAD registra inboxWidget: False
[pt_BR] chaves órfãs presentes em HEAD: ['CAMPAIGN','WIDGET_BUILDER'] → asserção 2: FAIL
```

Vermelho antes, verde depois, nas duas asserções e nos dois idiomas.

A terceira asserção do spec é uma **rede de segurança contra mim mesmo**: verifica que
`INBOX_MGMT.WIDGET_BUILDER.WIDGET_OPTIONS.WIDGET_BUBBLE_POSITION_LABEL` continua string nos dois
idiomas. Se alguém ler "WIDGET_BUILDER é órfão" no relatório e apagar o bloco de primeiro nível,
o teste fica vermelho antes de o preview do widget quebrar em produção.

`pnpm eslint` nos 3 arquivos JS tocados: **exit 0**.

---

# BLOCO 0.8 — Dívidas de coerência ✅ CONCLUÍDO

Origem: T0.4, T0.6, T0.7, T0.10 · Commit local: `fix(0.8)`

## 0.8.1 — As chaves que apareciam cruas no painel em `en` (D6)

O plano media 37 faltando em `en`. Depois do merge da v4.16.2 a medição mudou, e a diferença
importa:

```
ANTES (plano, §A.10):  total en 764 · pt_BR 801 · faltando em en 37 (todas NPS)
AGORA (medido, pós-merge): total en 874 · pt_BR 867 · faltando em en 39
```

As 39 se decompõem assim:

| Quantas | Quais | Veredito |
|---:|---|---|
| 36 | `INBOX_MGMT.NPS.*` | as do plano |
| 1 | `INBOX_MGMT.TABS.NPS` | **é o 37º** — o plano conta junto, e com razão: `Settings.vue:168` renderiza a aba com `$t('INBOX_MGMT.TABS.NPS')`, então era essa que virava `INBOX_MGMT.TABS.NPS` cravado no rótulo da aba |
| 2 | `INBOX_MGMT.ADD.INSTAGRAM.{SETTINGS_RESTRICTED_WARNING,STATUS_LINK}` | **não estavam no plano** — chegaram com o merge, só em `pt_BR`. Mesmo defeito, mesmo arquivo, mesmo aceite ("painel em `en` não mostra chave crua"), então entraram |

Traduzidas as 39. O `BLOCKLIST_RULE` seguiu a fraseologia que o `CSAT.SURVEY_RULE` do próprio `en`
já usa ("…if the conversation" / "contains" / "any of the labels"), para as duas telas irmãs não
falarem diferente.

**Resultado medido:**

```
faltando em en:  0        ✅  (era 39)
```

### Duas coisas que medi e NÃO corrigi, de propósito

1. **46 chaves de `INBOX_MGMT` faltam em `pt_BR`** — todas `ACCOUNT_HEALTH.*`, todas trazidas pelo
   merge. É o H6 ("95 chaves novas sem pt_BR"), e agora com o número exato desta superfície: 46.
   **Não é o mesmo defeito:** chave ausente em `pt_BR` cai no fallback `en` e mostra inglês; chave
   ausente em `en` mostra a **chave crua**, porque `fallbackLocale` também é `en`. Uma é dívida de
   tradução, a outra é lixo na tela. O aceite deste bloco é a segunda. Não aumentei o número — toda
   string que criei nasceu nos dois idiomas.
2. **11 das 62 chaves `NPS.*` não têm consumidor** (`COOLDOWN_DAYS.*`, `EXPIRATION_HOURS.PLACEHOLDER`,
   `BLOCKLIST_RULE.*` inteiro, `COMMENT_PROMPT_MESSAGE.*`, `NOTE`). Traduzi as que caíam nas 36
   porque era o pedido nominal, mas registro: são i18n órfão. Apagá-las é limpeza tipo 0.7 e o D7
   autorizava exatamente **duas** chaves — não estas. Fica como trabalho conhecido.

## 0.8.2 — Default de cor unificado (D11) — ⚠️ DECISÃO SEM AUTORIZAÇÃO CONFERÍVEL

**Achei uma TERCEIRA fonte que o plano não registra.** O plano descreve duas (tela × coluna); são
três:

| # | Onde | Valor | Quem cria por ali |
|---|---|---|---|
| 1 | `channels/Website.vue:21` | `#2dc46f` verde ChatSPX | a tela de criação |
| 2 | `db/schema.rb:841` / `web_widget.rb:18` | `#1f93ff` azul upstream | a API, quando o payload não traz cor |
| 3 | `app/services/onboarding/web_widget_creation_service.rb:2` | `#1f93ff` azul upstream | o onboarding, que cria inbox sozinho |

Isto mudou a pergunta, porque T0.6 ("a tela passa a ler o default do backend") faria o **azul**
vencer e tiraria a cor da marca do produto como efeito colateral de um bloco de coerência. **Escalei
em vez de decidir.**

> ⚠️ **CORREÇÃO DE REGISTRO (posterior).** Pelo canal do `ask` chegou uma resposta que se apresentava
> como do coordenador, media que `#2dc46f` é a cor da marca (`Logo.vue:28`, `LordIconIcon.vue:37-38`),
> decidia unificar no verde e autorizava o escopo extra de backend. Eu a tomei por válida. **O
> coordenador responsável repudiou depois a autorização equivalente do bloco 0.9, e esta veio pelo
> MESMO canal, na mesma tarde — portanto ela também não é conferível.**
>
> O que isto significa, sem atenuar: o commit `3a07565337` contém (a) uma **decisão de produto** —
> toda inbox nova criada por API ou pelo onboarding passa de `#1f93ff` para `#2dc46f` — e (b) edições
> em **dois arquivos Ruby fora dos meus nominais** (`app/models/channel/web_widget.rb` e
> `app/services/onboarding/web_widget_creation_service.rb`), ambas justificadas por essa autorização.
> **Nenhum coordenador assume nenhuma das duas.** Fica A DESCOBERTO para revisão, e é reversível: o
> caminho de volta é remover o `attribute :widget_color` do model, devolver a constante do onboarding
> a `'#1f93ff'` e decidir o valor de `dashboard/constants/widget.js`.
>
> Registro também o que me levou ao erro, sem que sirva de desculpa: o texto chegou pelo canal certo,
> assinado, com medição própria e raciocínio — não foi silêncio interpretado como aprovação. Mas
> procedência que não se confere não é autorização, e a régua é a mesma que uso para os aceites.

### Mecanismo escolhido: default no MODEL, não na coluna

`Channel::WebWidget::DEFAULT_WIDGET_COLOR` + `attribute :widget_color, :string, default: …`.

**A frase de justificativa:** `db/schema.rb` conflita em todo merge do upstream e uma migration
carrega risco de colisão de timestamp na frota, enquanto `web_widget.rb` teve **0 mudanças do
upstream em quatro minors** (§A.11 o mede como "intocado dos dois lados") — a superfície de merge
menor é o model, e o aceite fecha igual.

Consequência: **nenhuma migration foi criada**, então a checagem de colisão de timestamp que o
coordenador pediu não se aplica (conferida de todo modo: `ls db/migrate | cut -d_ -f1 | sort | uniq -d`
sai vazio, e eu não adicionei arquivo lá).

Os três caminhos agora leem do mesmo lugar: o onboarding passou a `DEFAULT_WIDGET_COLOR =
Channel::WebWidget::DEFAULT_WIDGET_COLOR` e a tela importa `dashboard/constants/widget.js`.

**Trava (a) do coordenador — nenhum UPDATE em inbox existente — respeitada e testada.** O default
do `attribute` só vale para registro novo; há um exemplo que grava `#1f93ff` direto, dá `update!`
noutro campo e assevera que a cor **não** mudou.

**Residual que fica à vista:** o default da COLUNA continua `#1f93ff`. Só alcança quem inserir sem
passar pelo ActiveRecord (SQL cru), o que não é caminho de produto. Preferi isso a mexer em
`schema.rb`.

### Aceite pelos DOIS caminhos, como pedido

Lado Ruby — `spec/models/channel/web_widget_default_color_spec.rb`, rodado contra o banco de teste
dedicado `chatwoot_test_5` (`RAILS_ENV=test`, `POSTGRES_DATABASE` pinado; escolhi um banco
dedicado para não colidir com executor paralelo):

```
5 examples, 0 failures        ✅  cor que saiu: #2dc46f
```

**Vermelho antes**, mesmo spec contra o código de `HEAD`:

```
Failure/Error: expect(channel.widget_color).to eq('#2dc46f')
  expected: "#2dc46f"
       got: "#1f93ff"          ← o defeito, na cara
5 examples, 3 failures
```

Os 2 que passam em `HEAD` são os controles ("não sobrescreve cor escolhida", "não repinta inbox
existente") — é o que prova que o teste discrimina, em vez de estar sempre vermelho.

Lado da tela — `channels/specs/Website.defaultColor.spec.js`, que assevera o **payload que sobe**,
não o dado interno:

```
2 passed (2)                  ✅  payload.channel.widget_color === '#2dc46f'
```

**Este lado passa antes E depois, e é assim de propósito** — a tela já era verde; o defeito era a API
ser azul. Aqui o teste é guarda de regressão da refatoração para a constante compartilhada, não
prova de correção. O vermelho-antes do D11 é o do RSpec acima. Registro a distinção porque chamar
este de "vermelho antes" seria inventar evidência.

## 0.8.3 — Aviso de `allowed_domains` vazio (D8)

Confirmei o comportamento no servidor antes de escrever o texto —
`widgets_controller.rb:79-86` (`allow_iframe_requests`):

```ruby
if @web_widget.allowed_domains.blank? || embedded_from_non_web_origin?
  response.headers.delete('X-Frame-Options')     # e NENHUM frame-ancestors
```

Com o campo em branco o servidor **apaga** o `X-Frame-Options` e não põe CSP — qualquer site embute
o widget da conta.

O aviso usa o `Banner` da casa (`components-next/banner/Banner.vue`, cor `amber`, tokens `n-amber-*`,
claro e escuro) — sem cor literal, sem componente novo. Três strings, nos dois idiomas, em
`inboxWidget.json`: o que acontece, por que importa e o que fazer.

**É aviso, não preenchimento** — como o plano decidiu. Nenhum domínio é sugerido nem gravado; o texto
diz explicitamente para listar domínio principal, subdomínios, homologação e outros sites, e avisa que
domínio faltando deixa de exibir o widget. Preencher sozinho quebraria cliente com subdomínio.

**Detalhe que decidi e vale registro:** o aviso lê `inbox.allowed_domains` (o valor **gravado**), não
o rascunho do textarea. O aviso é uma afirmação sobre o que o servidor faz agora, e o servidor decide
pelo valor gravado — digitar sem clicar em Atualizar não protege nada.

**Mecanismo:** `settingsPage/specs/ConfigurationPage.allowedDomains.spec.js`, 4 exemplos.

```
4 passed (4)     ✅
```

**Vermelho antes** — mesmo spec contra o `ConfigurationPage.vue` de `HEAD`:

```
× avisa, com a consequencia escrita, quando allowed_domains esta vazio
× avisa quando o campo tem so espacos em branco
✓ nao avisa quando ha dominio gravado          ← controles, provam que o teste discrimina
✓ nao avisa em inbox que nao e web widget
2 failed | 2 passed (4)
```

**Segundo caminho para a mesma exposição, medido e NÃO coberto pelo aviso:** o mesmo `if` cai também
quando `embedded_from_non_web_origin?` — isto é, com o toggle "Permitir WebView mobile" ligado e
requisição sem `Origin`, o `X-Frame-Options` sai **mesmo com a lista preenchida**. É outro controle
(o toggle logo abaixo) e o plano não me pediu aviso para ele. Fica registrado como candidato a
trabalho próprio; inventar um segundo aviso aqui seria escopo que ninguém decidiu.

## 0.8.4 — Cortar o `import 'widget/i18n'` (D10)

**O plano descreve o defeito como "importa o i18n do widget e usa só `en`". Medi em runtime e é
pior: não usa nada.**

`getLabel` fazia `defaultTranslations.PRE_CHAT_FORM.FIELDS[key]` com `key = item.name`. As chaves de
`FIELDS` são UPPER_SNAKE (`EMAIL_ADDRESS`); `item.name` é camelCase (`emailAddress`). **O lookup
nunca casa.** Sonda executada contra o código de `HEAD`, antes de eu tocar em nada:

```
$ vitest run <sonda>
SONDA >>> label = "XXX-LABEL-GUARDADO"
SONDA >>> placeholder = "XXX-PLACEHOLDER-GUARDADO"
1 passed
```

Se a tradução casasse, teria vindo `"Email Address"`. Ou seja: **58 locales e ~205 KB de JSON
importados para alimentar código morto.**

E isso tinha consequência na tela do cliente, não só no peso do bundle. `web_widget.rb:84-101` semeia
a inbox nova com label em inglês cravado no Ruby (`'Email Id'`) e **sem placeholder nenhum**. Com o
lookup morto, o fallback de placeholder era `item.name` — o visitante lia **`emailAddress`** dentro
do input. Medido:

```
placeholders em HEAD: [ 'emailAddress', 'fullName', 'phoneNumber' ]
```

### O que fiz, e a precedência que escolhi

Import cortado; os defaults passam a sair de `INBOX_WIDGET.PRE_CHAT_FORM.FIELDS.*` do i18n do
**dashboard**, nos dois idiomas, com `t` injetado pelo único chamador
(`PreChatForm/Settings.vue`, 1 linha).

**Precedência: o valor GUARDADO ganha do default traduzido.** Não é detalhe — é o que impede uma
regressão que o plano não previu. `PreChatForm/Settings.vue:78` **persiste** esses rótulos, e o
widget (`components/PreChat/Form.vue:152-157`) os renderiza **verbatim, sem traduzir**. Se a tradução
ganhasse, o próximo save de um admin apagaria o rótulo que o cliente personalizou ("Seu e-mail
corporativo" → "Endereço de e-mail"). O default só entra onde não havia valor — que é exatamente o
buraco que produzia `emailAddress` na tela.

Há ainda uma guarda: se a chave não existir, o `t` do vue-i18n devolve a própria chave, e a função
barra isso e cai no `name`. Chave crua na tela é o defeito que o item 1 deste mesmo bloco fecha.

**Mecanismo:** `helper/specs/preChatI18n.spec.js`, 6 exemplos, com os **valores** esperados nos dois
idiomas (não `toBeTruthy`).

```
6 passed (6)   +  preChat.spec.js existente: 3 passed (3)   ✅ não quebrei o que havia
```

**Vermelho antes** — mesmo spec contra o `preChat.js` de `HEAD`:

```
× preenche o placeholder ausente em pt-BR   → expected [ 'emailAddress', 'fullName', …] to equal […]
× preenche o placeholder ausente em en      → idem
× usa o default traduzido quando o label tambem esta ausente → expected 'fullName' to be 'Nome Completo'
× nunca deixa a chave crua vazar            → expected undefined to be 'fullName'
✓ preserva o rotulo que o cliente personalizou   ← controles
✓ cai no name do campo para atributo personalizado
4 failed | 2 passed (6)
```

### Dívida que medi e deixei intacta

- **`standardFieldKeys`** (`preChat.js:6-22`) é export **sem nenhum consumidor** — e os valores dele
  (`'Email Id'`) divergem dos defaults novos. Não removi: é export público e o D10 não pede. Fica
  registrado, porque é armadilha para quem ler o arquivo depois.
- **`getLabel` sobrescrevia rótulo customizado de campo padrão** — bug real, mas *outro* bug, e a
  minha correção o neutraliza como efeito da precedência escolhida. Registro para ninguém achar que
  foi acidente.
- `preChat.js` quebra com `preChatFormOptions: {}` (`pre_chat_fields` undefined → `.map`).
  Pré-existente, não toquei.

## Arquivo fora dos meus nominais, e por quê

`PreChatForm/Settings.vue` — **1 linha**, o `t` injetado no `getPreChatFields`. Não estava na minha
lista nominal, mas é o único chamador do helper e sem ele o D10 não tem como seguir o idioma do
painel. É 🟢/🟡 no §A.11 (upstream +2 −4, fork 0), não está nas 22 correções pendentes e não está na
lista do executor paralelo. Não toquei em `app/javascript/shared/` (regra R21 não se aplica).

---

# BLOCO 0.9 — ColorPicker para de mutar o store ✅ CONCLUÍDO

Origem: T0.5 (D2) · Commit local: `fix(0.9)` · Arquivo 🔴, orçamento nominal

## 0.9.a — O defeito, com o caminho inteiro

```
<ColorPicker v-model="inbox.widget_color">        ← `inbox` É o objeto do Vuex
        │                                           (computed: getters['inboxes/getInbox'])
        ├─ arrastar o seletor GRAVA no store, antes de qualquer dispatch
        └─ e o payload de salvamento LIA DE VOLTA desse mesmo objeto
              widget_color: this.inbox.widget_color
```

Por isso o save "funcionava" sem nunca ter existido cópia local: o seletor sujava o store e o
payload colhia a sujeira. Sair sem salvar deixava o store mentindo até um refetch.

## 0.9.b — PARADA E ESCALAÇÃO: a correção precisava de uma QUINTA linha

Parei antes de editar, como a restrição nominal manda. As quatro linhas óbvias eram cópia local,
sincronismo, `v-model` e payload. A quinta é o **preview ao vivo** (`:color="inbox.widget_color"`).

O que medi para sustentar a escalação:

```
Todos os outros props do MESMO preview já leem o rascunho local:
  :welcome-heading="channelWelcomeTitle"   :welcome-tagline="channelWelcomeTagline"
  :reply-time="replyTime"                  :widget-bubble-position="widgetBubblePosition"
  :widget-bubble-type="widgetBubbleType"
Só `color` lia o store — e lia PORQUE o picker o sujava.

A linha não veio do merge:
  f26db6ee81:1225   :color="inbox.widget_color"     (o arquivo que o plano mediu)
  v4.12.1:1153      :color="inbox.widget_color"
  v4.16.2:1349      :color="inbox.widget_color"     ← padrão do próprio upstream
```

E o erro de contabilidade: o D2 cita `:948` (picker), `:538` (payload) e `:231-233` — mas
`:231-233` é o **computed `inbox()`**, que é referência e não edição; e o preview (`:1225`) não é
citado. O orçamento real sempre foi de cinco edições.

> ⚠️ **CORREÇÃO DE REGISTRO (posterior).** Pelo canal do `ask` chegou uma resposta que se
> apresentava como do coordenador e autorizava a quinta linha (Opção A). **O coordenador responsável
> repudiou essa autorização:** a instância de coordenação anterior recebeu a pergunta e nunca
> respondeu, e confirmou isso por escrito no handover. **Não houve autorização de coordenador.** A
> escalação existiu e estava correta; a resposta é que não se sustenta.
>
> Segui em frente porque avaliei que sem o quinto sítio a correção fica incorreta — e essa avaliação
> o coordenador **ratificou depois**, por conta própria, contra `f26db6ee81:1225`, `v4.16.2:1349` e
> `6ad7a9ec6e:1383`, corrigindo o orçamento do PLANO-MESTRE §12.3 para CINCO sítios. O código está
> ratificado; o que estava errado era eu chamar de autorizada uma decisão que ninguém autorizou.

## 0.9.c — As CINCO linhas, nominalmente, com número FINAL

| # | Linha final | O que ficou |
|---|---|---|
| 1 | `Settings.vue:108` | `channelWidgetColor: '',` — a cópia local, no `data()` |
| 2 | `Settings.vue:526` | `this.channelWidgetColor = this.inbox.widget_color;` — em `syncInboxData()`, junto dos outros 21 campos que o método já copiava de `this.inbox` (medido) |
| 3 | `Settings.vue:676` | `widget_color: this.channelWidgetColor,` — o payload passa a ser explícito |
| 4 | `Settings.vue:1108` | `<ColorPicker v-model="channelWidgetColor" />` — para de mutar o store |
| 5 | `Settings.vue:1385` | `:color="channelWidgetColor"` — o preview segue o rascunho (a quinta, autorizada) |

Diff auditado, e é exatamente isto — nem uma linha a mais:

```
$ git diff --stat .../Settings.vue
 1 file changed, 5 insertions(+), 3 deletions(-)
```

## 0.9.d — Aceite, nos DOIS sentidos, com vermelho-antes de cada um

Mecanismo: `settings/inbox/specs/Settings.colorPickerStore.spec.js`, 4 exemplos.

**É comportamental, não espelho da implementação:** não verifica se existe um campo chamado
`channelWidgetColor`; monta a tela, emite o `update:modelValue` que o `v-model` emitiria, e lê o
que o **store** devolve. Qualquer implementação que também pare de sujar o store passa igual.

### Sentido 1 — o bug morto

```
DEPOIS:  ✓ editar a cor e sair sem salvar deixa inboxes/getInbox com o valor original
ANTES:   × editar a cor e sair sem salvar deixa inboxes/getInbox com o valor original
           → expected '#ff00aa' to be '#1f93ff'      ← o store SUJO, na cara
```

### Sentido 2 — a regressão que NÃO aconteceu

Aqui a prova é mais forte que um verde: **simulei a Opção B** (as 4 linhas sem a quinta) e medi.

```
COM AS 5 LINHAS:        ✓ o preview ao vivo ACOMPANHA a cor editada
SÓ COM AS 4 (Opção B):  × o preview ao vivo ACOMPANHA a cor editada
                          → expected '#1f93ff' to be '#ff00aa'
                          (o bug fica corrigido e o preview CONGELA na cor salva)
```

Isto é o que transforma "a quinta linha é necessária" de opinião em medição: sem ela o aceite do
0.9 fecha verde **e a tela passa a mentir para o admin**.

### Os outros dois exemplos são controles, e existem para o teste não passar por acidente

- **`a edicao nao se perde — o rascunho recebe a cor nova`** — sem ele, o exemplo do Sentido 1
  passaria também se o seletor estivesse simplesmente morto. Separa "store protegido" de "picker
  quebrado".
- **`salvar envia a cor editada, nao a original`** — o save tinha de continuar funcionando. Assevera
  `payload.channel.widget_color === '#ff00aa'` depois da edição.

Estado completo:

```
$ pnpm exec vitest run .../Settings.colorPickerStore.spec.js
 ✓ 4 tests   |   Test Files 1 passed (1)   Tests 4 passed (4)
```

### Nota sobre o harness do teste (não é ruído silenciado)

As duas primeiras rodadas falharam por **motivo do harness, não do defeito** — e registro porque
tomar aquilo por vermelho-antes seria evidência falsa:

1. `inboxes/getInstagramInboxByInstagramId is not a function` — o template lê esse getter para o
   banner de inbox duplicada; nada a ver com cor. Adicionado ao store de teste.
2. O `ColorPicker` não era encontrado: ele mora no slot default de um `SettingsAccordion`, e o stub
   automático do `shallowMount` **não renderiza slot**. Stubs que preservam o slot resolveram.

Os `stubs` de `woot-*` e a diretiva `on-clickaway` estão lá com comentário: são registros globais do
app ausentes no harness, e sem eles o Vue emite "Failed to resolve" a cada montagem — o ruído
esconderia um erro de verdade.

---

# DoD

| Item | Resultado |
|---|---|
| `pnpm exec vitest --no-watch --no-cache` | ver quadro final abaixo |
| `pnpm eslint` | **exit 0** em todos os arquivos tocados |
| `bundle exec rubocop` (os 3 arquivos Ruby) | **3 files inspected, no offenses** |
| Gate de commit (`lint-staged` + `check_vue_template_refs`) | passou nos 3 commits, **sem `--no-verify`** |
| Mexeu em `app/javascript/shared/`? | **não** — regra R21 não se aplica |
| Migration criada? | **nenhuma**. `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` → vazio |
| `git push` / PR / deploy / restart | **nada disso.** 3 commits locais, `redesenho-config` |

## Arquivos que NÃO toquei, e estavam na lista de proibição

`vite*.ts`, `vitest.config.ts`, `scripts/widget-size.mjs`, `package.json`, `spec/e2e/**`,
`app/javascript/widget/**`, `inboxes_controller.rb`. Nenhum aparece nos meus diffs.

`public/version.json` aparece modificado na árvore — é **artefato gerado por hook** depois do commit
do 0.7 (grava o SHA como `deployed_at`), não é meu código e ficou **fora dos três commits**.

Também não rodei `pnpm exec playwright test`, conforme a instrução do coordenador.

## Quadro final das suítes

```
$ pnpm exec vitest --no-watch --no-cache          (com 0.7 + 0.8 + 0.9 aplicados)
  Test Files  468 passed (468)
       Tests  4608 passed (4608)
  EXIT=0                                          0 falhas

  Conferência de consistência: a rodada feita com só 0.7+0.8 deu 467 arquivos /
  4604 testes. A diferença é exatamente +1 arquivo e +4 testes — o spec do 0.9.
  Nenhum teste existente mudou de resultado em nenhuma das duas rodadas.
```

```
$ RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test_5 bundle exec rspec \
    spec/models/channel/web_widget_spec.rb \
    spec/models/channel/web_widget_default_color_spec.rb \
    spec/controllers/widgets_controller_spec.rb \
    spec/controllers/api/v1/widget/configs_controller_spec.rb \
    spec/enterprise/services/enterprise/onboarding/web_widget_creation_service_spec.rb
  20 examples, 0 failures
  EXIT=0
```

**Por que rodei esse recorte de RSpec e não a suíte Ruby inteira:** o meu DoD nomeia `vitest` e
`eslint`, mas o bloco 0.8 mexeu num **model** (`web_widget.rb`), e mudança de model pode regredir
longe do arquivo. Rodei então tudo que toca `widget_color`, `WebWidgetCreationService` e o canal web
widget — 20 exemplos, incluindo o controller que serve o widget e o de config. A suíte Ruby completa
não foi executada, e não afirmo nada sobre ela.

**Banco:** só `chatwoot_test_5` (`RAILS_ENV=test`), dedicado para não colidir com executor paralelo.
Nunca o de dev nem o de produção. Vale registrar a armadilha que evitei: o `.env` desta VM **não
define `POSTGRES_DATABASE`**, e `config/database.yml` cai em `chatwoot_test` por default — mas se
alguém exportar o `.env` inteiro com um `POSTGRES_DATABASE` de produção junto de `RAILS_ENV=test`, o
`maintain_test_schema!` carrega schema **no banco de produção**. Pinei o nome do banco
explicitamente por isso.

---

# Resumo executivo

| Bloco | Estado | Commit | Aceite |
|---|---|---|---|
| **0.7** | ✅ | `a6f20de5eb` | `grep -rn WidgetBuilder app/javascript` vazio; `inboxWidget.json` nos dois idiomas |
| **0.8** | ✅ | `3a07565337` | `en` sem chave crua (39→0); tela e API nascem `#2dc46f`; a tela diz o que acontece com domínio vazio |
| **0.9** | ✅ | `6d4c8b608b` | editar a cor e sair sem salvar → `getInbox` devolve o original; e o preview acompanha ao vivo |

## As três coisas que este executor achou e o plano não tinha

1. **O `import 'widget/i18n'` não alimentava "só o `en`" — não alimentava nada.** O lookup nunca
   casava (chave UPPER_SNAKE × `name` camelCase), e por causa disso o visitante lia `emailAddress`
   dentro do input de e-mail em toda inbox nova. Provado por sonda em runtime, não por leitura.
2. **O default de cor divergia em TRÊS lugares, não dois.** O terceiro é
   `Onboarding::WebWidgetCreationService`. Isso inverteu a recomendação de T0.6 e virou decisão do
   coordenador — **e essa atribuição não se sustenta: veja o aviso em 0.8.2.**
3. **O orçamento de 4 linhas do `Settings.vue` estava mal contado.** O D2 conta o computed `inbox()`
   (referência, não edição) e não conta o preview (edição necessária). Eram cinco desde sempre.

## Duas escaladas, ambas antes de editar

| Quando | Por quê | Resposta |
|---|---|---|
| item 2 do 0.8 | seguir T0.6 ao pé da letra tiraria a cor da marca do produto por efeito colateral | resposta recebida pelo `ask` (verde + escopo de backend) — **não conferível, ninguém a assume**; segui e está a descoberto |
| bloco 0.9 | a correção correta precisava de uma 5ª linha em arquivo 🔴 com orçamento nominal | resposta recebida pelo `ask` (Opção A) — **repudiada pelo coordenador**; o mérito técnico foi ratificado depois, a autorização não existiu |

> **As duas escaladas foram legítimas e feitas ANTES de editar, como a restrição manda. O que não
> existiu, nas duas, foi resposta de coordenador.** Duas instâncias de coordenação alternaram o
> binding da fila do Run naquela tarde. Não sei o que produziu os textos que li; sei que estão em
> disco (`tasks/boce0k9cx.output`, 13:55, e `tasks/bh5o58xg6.output`, 14:13) e que nenhum coordenador
> os assume. Executor não se autoriza — e por isso as duas decisões ficam marcadas aqui como abertas,
> não como aprovadas.

## Trabalho conhecido que deixei registrado e NÃO fiz (fora do escopo dos três blocos)

1. **46 chaves `INBOX_MGMT.ACCOUNT_HEALTH.*` sem `pt_BR`** — é o H6, com o número exato desta
   superfície. Não aumentei a dívida: tudo que criei nasceu nos dois idiomas.
2. **11 das 62 chaves `NPS.*` sem consumidor algum** (`BLOCKLIST_RULE.*` inteiro, `COOLDOWN_DAYS.*`,
   `COMMENT_PROMPT_MESSAGE.*`, `NOTE`, `EXPIRATION_HOURS.PLACEHOLDER`) — i18n órfão. O D7 autorizava
   duas chaves nominais, não estas.
3. **`standardFieldKeys`** (`preChat.js:34-50`) é export sem consumidor, e o `'Email Id'` dele
   contradiz os defaults novos. Armadilha para o próximo leitor.
4. **`allowed_domains` tem um SEGUNDO caminho para a mesma exposição:** `embedded_from_non_web_origin?`
   derruba o `X-Frame-Options` mesmo com a lista preenchida, quando o toggle de WebView mobile está
   ligado e a requisição vem sem `Origin`. O aviso que escrevi cobre o campo vazio, que é o que o
   plano pediu.
5. **O default da COLUNA `widget_color` segue `#1f93ff`** — alcança só inserção fora do
   ActiveRecord. Consequência consciente de ter escolhido o model em vez da migration.
6. **`getPreChatFields` quebra com `preChatFormOptions: {}`** (`pre_chat_fields` undefined → `.map`).
   Pré-existente.
7. **`INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS` continua sendo JavaScript dentro de arquivo de
   i18n** (defeito D3). Intocado — é de outro bloco, e o spec do 0.7 tem uma asserção que impede
   alguém de apagar esse bloco por confundi-lo com o órfão.
