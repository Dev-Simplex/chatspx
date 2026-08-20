# Onda 5 — Trilha MOVIMENTO, DARK, i18n e PESO

- **Worktree:** `/home/chatwoot/chatwoot-o5-movimento`
- **Branch:** `o5-movimento` (base: `redesenho-integra` @ `4954ed5837`)
- **Autor:** executor único deste worktree
- **Início:** 2026-08-18

## Estado dos blocos

| Bloco | Título | Estado |
|---|---|---|
| 2.17 | i18n: "mandat…ório" → "obrigatório", erro por campo, traduções mecânicas | ✅ **PRONTO** |
| 2.10 | Dark mode completo (`auto`, classe no `<html>`, `color-scheme`, reativo) | ✅ **PRONTO** |
| 2.14 | Degradação do launcher (bundle falhou → canal alternativo) | ✅ **PRONTO** |
| 2.13 | Telemetria de erro do widget (GlitchTip, sem PII) | ✅ **PRONTO** |
| 2.08 | Movimento + `prefers-reduced-motion` / `prefers-contrast` / `forced-colors` | 🚧 **BLOQUEADO por 2.03** (trilha `o5-primitivos`) |
| 2.18 | Peso, 2ª rodada (vendor chunk, FormKit lazy, i18n sob demanda) | 🚧 **BLOQUEADO por 2.\*** (fechamento da Onda 5) |

---

## Nota ao coordenador (início)

Recebi a task por texto colado. Working tree estava limpo e sem relatório: confirmo que **não**
estava com a task antes desta mensagem — o despacho anterior não chegou aqui. Comecei do zero,
na ordem 2.17 → 2.10 → 2.14 → 2.13.

---

# Bloco 2.17 — i18n do widget ✅

**Aceite (§2.2):** «`grep -rn "mandat"+"ório" widget/i18n/` vazio; nenhum rótulo acessível em
inglês com interface em pt-BR».

## O que estava errado (medido, não suposto)

Três defeitos distintos, sendo que só o primeiro estava no enunciado:

1. **`pt_BR.json:70`** — `"Nome Completo é mandatório"`. Além do anglicismo, o Title Case
   (`Nome Completo`, `Número de Telefone`) é decalque do inglês.

2. **Erro de obrigatoriedade igual para todos os campos.** `PreChat/Form.vue` mandava ao FormKit
   `required: $t('PRE_CHAT_FORM.REQUIRED')` → a palavra **"Obrigatório"**, idêntica para todos.
   Com três campos em branco o visitante via a mesma palavra três vezes, sem saber a qual campo
   ela se referia; o leitor de tela anunciava a mesma coisa três vezes.
   Enquanto isso, `PRE_CHAT_FORM.FIELDS.<CAMPO>.REQUIRED_ERROR` existia **traduzido nos 40
   locales e não era lido por componente nenhum** — código morto de i18n:

   ```
   $ grep -rn "REQUIRED_ERROR" app/javascript/widget --include=*.vue --include=*.js
   (nenhum resultado)
   ```

3. **Três rótulos acessíveis em inglês**, com o documento declarando `lang="pt-BR"`:
   `ChatHeader.vue:41` `alt="avatar"`, `ChatHeaderExpanded.vue:41` `alt="Avatar"`,
   `ImageBubble.vue:25` `alt="Picture message"`. É o texto que o leitor de tela pronuncia — com
   fonemas portugueses, porque o documento é pt-BR.

## Mecanismo de aceite

Dois arquivos, porque são duas naturezas — e a distância entre elas é que produziu o defeito 2
(dicionário certo, marcação apontando para outro lugar):

| Arquivo | Cobre |
|---|---|
| `app/javascript/widget/i18n/specs/ptBrQualidade.spec.js` | o **dicionário**: varre os 40 `locale/*.json` pelo anglicismo, e exige as chaves novas em `en` **e** `pt_BR`, com a asserção extra de que as duas **não são a mesma string** (copiar o inglês é o jeito mais comum de "traduzir" e passar num teste de presença) |
| `app/javascript/widget/components/specs/rotulosPtBr.spec.js` | a **marcação**: o `alt` que cada componente de fato renderiza, e o valor de cada mensagem de obrigatoriedade |

O arquivo de spec **não escreve o termo do aceite por extenso**, de propósito: o aceite é um
`grep` literal, e um comentário citando o termo faria o comando devolver o próprio teste como se
fosse defeito. (Foi o que aconteceu na primeira versão — 3 falsos positivos.)

## Vermelho ANTES, medido restaurando o código antigo

```
× usa a mensagem própria de cada campo padrão   → expected 'Obrigatório' to be 'Nome completo é obrigatório'
× as três mensagens são DISTINTAS entre si      → expected 1 to be 3
× ChatHeader: alt traduzido                     → expected 'avatar' to be 'Foto do agente'
× ChatHeaderExpanded: alt traduzido             → expected 'Avatar' to be 'Foto do agente'
× ImageBubble: alt traduzido                    → expected 'Picture message' to be 'Imagem enviada na conversa'
× a mensagem de nome completo usa "obrigatório" → expected 'Nome Completo é mandat…' to be 'Nome completo é obrigatório'
```

`expected 1 to be 3` é a asserção que prova o defeito 2: as três mensagens colapsavam em uma só.

O vermelho dos dois `ChatHeader` foi **remedido** depois de o spec mudar de configuração (ver
"Armadilha" abaixo), restaurando `alt="avatar"`/`alt="Avatar"` no lugar — não herdei a medição
antiga.

## Verde depois

- os dois specs do bloco: **67 asserções, todas verdes**
- suíte inteira do widget: **46 arquivos, 367 testes, 0 falhas**
- `npx eslint` nos 7 arquivos tocados: **0 erros, 0 avisos**
- aceite literal: `grep -rn "mandat…ório" app/javascript/widget/i18n/` → **vazio**

## CONTRATO exposto por este bloco

O bloco cria uma ponta de contrato nova; registro como a task pede (nome, tipo, default,
comportamento na ausência):

**`getRequiredMessage({ field, t }) -> string`** — `app/javascript/widget/helpers/preChatFieldMessages.js`

| Entrada | Resultado | Na ausência |
|---|---|---|
| `field.name` ∈ `{fullName, emailAddress, phoneNumber}` | `PRE_CHAT_FORM.FIELDS.<CHAVE>.REQUIRED_ERROR` | — |
| outro `name`, **com** `field.label` | `PRE_CHAT_FORM.FIELD_IS_REQUIRED` interpolando `{label}` | — |
| outro `name`, **sem** `field.label` | `PRE_CHAT_FORM.REQUIRED` | **degradação declarada**: é exatamente o comportamento de hoje. Sem rótulo não há como nomear o campo, e "O campo &nbsp; é obrigatório", com o buraco no meio, é pior que a genérica |

**Chaves i18n novas** (em `en` e `pt_BR`; os outros 38 locales caem no fallback `en` do vue-i18n
— não há guarda de paridade de locales neste repo, confirmado por busca):

| Chave | pt_BR | en |
|---|---|---|
| `PRE_CHAT_FORM.FIELD_IS_REQUIRED` | `O campo {label} é obrigatório` | `{label} is required` |
| `A11Y.AGENT_AVATAR` | `Foto do agente` | `Agent avatar` |
| `A11Y.IMAGE_ATTACHMENT` | `Imagem enviada na conversa` | `Image sent in the conversation` |

**Por que `O campo {label}` e não `{label} é obrigatório`:** a tradução mecânica de `{label} is
required` produz "Empresa é obrigatório" — o adjetivo concorda com o rótulo, que pode ser
feminino. Prefixar "O campo" prende a concordância no masculino de "campo" e vale para qualquer
rótulo, sem uma chave por gênero. Está coberto por asserção.

## Armadilha encontrada (e a lição)

Montar `ChatHeader.vue`/`ChatHeaderExpanded.vue` com `mocks: { $t }` + `createI18n({legacy:true})`
**quebra**: os dois são `<script setup>`, e o vue-i18n legado tenta ESCREVER `this.$t` na
instância — o proxy de `<script setup>` recusa
(`'set' on proxy: trap returned falsish for property '$t'`). O spec usa
`legacy: false` + `globalInjection: true`, que é o caminho que o app de verdade usa.
`a11y.spec.js` (bloco 1.06) não bateu nisso porque os componentes que ele monta são Options API.

## Fora de escopo, deixado de propósito (para o coordenador decidir)

Varri `pt_BR.json` inteiro por decalque; sobraram estes, e **não** os corrigi:

| Chave | Hoje | Deveria ser | Por que parei |
|---|---|---|---|
| `START_CONVERSATION` | `Iniciar Conversa` | `Iniciar conversa` | renderizado nos snapshots `prechat-form-*` |
| `END_CONVERSATION` | `Finalizar Conversa` | `Finalizar conversa` | renderizado no cabeçalho |
| `DAY_NAMES.MONDAY` | `Segunda-Feira` | `Segunda-feira` | inconsistente com os outros **seis** dias, que já são minúsculos |
| `PORTAL.POPULAR_ARTICLES` | `Artigos Populares` | `Artigos populares` | tela do portal |
| `COMPONENTS.FILE_BUBBLE.DOWNLOAD` | `Download` | `Baixar` | única string do widget idêntica ao inglês |

**Motivo de parar:** o harness e2e roda em `locale: 'pt_BR'`
(`spec/e2e/widget/harness/host-server.mjs:43`), então os 16 PNGs de
`spec/e2e/widget/snapshots/` foram capturados com essas strings. Mudá-las move a régua visual do
projeto, e a regra é explícita: **snapshot que muda é achado a investigar, nunca baseline a
regravar**. Nenhuma delas é necessária para o aceite do 2.17, que já está cumprido.
São 5 linhas de JSON; se o coordenador autorizar mover a régua, aplico e regravo com o diff lido.

Também deixei `FIELDS.MESSAGE.ERROR` (`"Mensagem muito curta"`) como está: ela é usada como
mensagem de `required`, então um campo **vazio** produz "muito curta". É defeito de UX real, mas
corrigi-lo mexe na string do `en` (upstream) e não pertence a este aceite.


---

# Bloco 2.10 — dark mode completo ✅  (commit `0ba948d95e`)

**Aceite (§2.2):** «Sem `darkMode` configurado e SO escuro, o widget abre escuro; trocar o tema do
SO reflete **sem remount**».

## Quatro defeitos, dos quais três só aparecem juntos

**1 · O default `light` estava escrito em três lugares.**
`getDarkMode` caía em `DARK_MODE[0]`; o store do widget nascia `'light'` e reafirmava `'light'` no
destructuring do `config-set`. Passa a `auto` — por uma **constante `DEFAULT_DARK_MODE` explícita**,
não pela posição no array: reordenar uma lista de valores válidos parece cosmético e trocaria o tema
de todo cliente que não configurou nada.

**2 · A preferência do SO não era reativa** — este é o coração do aceite:

```js
const systemPreference = computed(getSystemPreference);  // ← lê matchMedia().matches
```

Um `computed` do Vue só reavalia quando uma dependência **reativa** muda, e `matchMedia().matches`
não é uma: é leitura simples de propriedade. O valor **congelava na primeira avaliação**. Com
`darkMode: 'auto'`, quem trocasse o tema do sistema com o chat aberto ficava preso no tema antigo
**até remontar o widget** — exatamente o que o aceite proíbe. Agora é `ref` + ouvinte de `change`
(com `addListener` para Safari < 14, que é justamente o navegador que sobra num widget embarcado),
liberado em `onScopeDispose`.

**3 · O tema não chegava ao documento.** A classe `dark` ia só nas `div`s raiz do `App.vue`. Faltava
o `<html>` — e faltava `color-scheme`, que é o que manda o navegador desenhar em escuro o que a
folha de estilo **não** pinta: barra de rolagem, `caret`, realce de seleção, controles nativos.
Painel escuro com barra de rolagem clara ao lado.

> Correção de diagnóstico durante o trabalho: **existia** um `color-scheme` no widget, mas só na
> `div` da conversa (`.light-scheme`/`.dark-scheme`). Duas lacunas, não uma: o **valor** errado
> (defeito 4) e o **escopo** errado (o `:root`).

**4 · `ConversationWrap` decidia pelo valor cru** (`darkMode === 'dark'`). Com o default virando
`auto`, essa comparação passa a ser sempre falsa no caso mais comum: o painel inteiro escurecia e
só a área das mensagens ficava com `color-scheme: light`.

## A armadilha que quase entrou no código

A forma óbvia de ligar o tema ao documento **está errada e falha em silêncio**:

```js
watch(prefersDarkMode, applyDocumentTheme, { immediate: true });   // ❌
```

O `watch` chama o callback com `(novo, antigo, onCleanup)`, e o `antigo` cai no parâmetro `doc` de
`applyDocumentTheme(prefersDark, doc = document)`. Na **primeira** chamada `antigo` é `undefined` e
o default salva; da **segunda** em diante `doc` é um booleano, `doc?.documentElement` é `undefined`
e a função sai sem fazer nada. Funcionaria na abertura e pararia **exatamente na troca de tema**,
que é o que o aceite mede.

Escrevi essa versão, percebi ao revisar, e corrigi pela raiz: o `watch` foi embrulhado em
`watchDocumentTheme()`, para o erro ser impossível no ponto de uso. Há teste que reprova a forma
ingênua — medido:

```
× acompanha claro → escuro → claro na MESMA ligação   → expected false to be true
✓ aplica o valor inicial sem esperar por uma troca      ← passa, e é o que engana
```

## Mecanismos de aceite

| Onde | Arquivo | Asserções |
|---|---|---|
| unidade — defaults e reatividade | `widget/composables/specs/darkModeAuto.spec.js` | 11 |
| unidade — documento | `widget/helpers/specs/documentTheme.spec.js` | 6 |
| unidade — `div` da conversa | `widget/components/specs/darkScheme.spec.js` | 5 |
| Ruby — página de teste | `spec/controllers/widget_tests_controller_spec.rb` | 2 |
| **Chromium real** | `spec/e2e/widget/darkMode.spec.js` | **5** |

## Vermelho ANTES, medido restaurando o código antigo

```
× cai em "auto" quando o cliente não configurou nada  → expected 'light' to be 'auto'
× o estado inicial já é "auto"                        → expected 'light' to be 'auto'
× acompanha a troca de tema do SO na MESMA instância  → expected false to be true
× registra exatamente um ouvinte de `change`          → expected +0 to be 1
× "auto" com sistema escuro → dark-scheme             → não inclui 'dark-scheme'
× as duas classes do elemento nunca se contradizem    → expected false to be true
```

## Verde em navegador de verdade — 5/5

```
✓ sem `darkMode` configurado e SO ESCURO, o widget abre escuro
✓ sem `darkMode` configurado e SO CLARO, o widget abre claro
✓ trocar o tema do SO reflete SEM REMOUNT
✓ escolha explícita do cliente vence a preferência do SO
✓ a área da conversa não contradiz o documento
```

"Sem remount" não é afirmação: o teste **marca a instância viva** (`window.marcaDeInstanciaE2E`)
antes da troca e confere que a marca sobreviveu. Se algo remontasse, ela sumiria.

## CONTRATO exposto por este bloco

| Chave | Tipo | Default | Na ausência |
|---|---|---|---|
| `DEFAULT_DARK_MODE` (`sdk/constants.js`) | string | `'auto'` | — |
| `chatwootSettings.darkMode` | `'light' \| 'auto' \| 'dark'` | `'auto'` | valor inválido ou ausente → `'auto'` |
| `appConfig.state.darkMode` | idem | `'auto'` | vale entre o mount e o `config-set` |
| `useDarkMode().prefersDarkMode` | `Ref<boolean>` | — | sem `matchMedia` → `false` (claro), sem lançar |
| `:root` / `:root.dark` → `color-scheme` | CSS | `light` / `dark` | classe posta por `helpers/documentTheme.js` |

**Compatibilidade:** quem escreveu `darkMode: 'light'` no snippet **continua com claro** — há
asserção para isso em unidade e em navegador. A mudança de default não vira mudança de
comportamento de quem já decidiu.

## Efeito colateral deliberado

`app/controllers/widget_tests_controller.rb` também passa a ter default `auto`. É a página que a
equipe usa para conferir o widget: enquanto ela abrisse `light`, a ferramenta de conferência
mostraria um comportamento que nenhum cliente novo tem. O override por `?dark_mode=` continua.

---

# Bloco 2.14 — degradação do launcher ✅  (commit `caa08e85f3`)

**Aceite (§2.2):** «Bloqueando o bundle no devtools, o link alternativo aparece».

## O que estava errado

`Channel::WebWidget#web_widget_script` — o snippet que o cliente cola no site dele — só tinha
`g.onload`. Quando o `sdk.js` **não** carrega (bloqueador de conteúdo, `script-src` da CSP do site,
rede do visitante, CDN fora), **nada acontecia**: nenhum launcher, nenhum aviso, e o visitante
ficava sem canal de contato sem que o dono do site soubesse. `onload` que nunca dispara não é erro
para ninguém.

## Onde a correção precisa morar

**No snippet, não no bundle.** É o único código que ainda roda quando o bundle é justamente o que
falhou. Qualquer solução dentro de `sdk.js` seria inútil no cenário do aceite.

## Dois gatilhos, porque são dois modos de falha

| Gatilho | Cobre |
|---|---|
| `g.onerror` | o navegador **sabe** que a requisição falhou (404, DNS, CSP) |
| prazo de 8 s | parte dos bloqueadores apenas **descarta** a requisição: o `<script>` fica pendente sem falhar nem carregar — **o caso mais comum dos dois**, e `onerror` não o pega |

E uma trava contra o falso positivo do prazo em rede lenta: `entrypoints/sdk.js` chama
`window.chatwootFallback?.hide?.()` ao subir. O `?.` não é decoração — o snippet **antigo**, já
colado no site de clientes que existem hoje, não define `chatwootFallback`, e uma chamada direta
quebraria o widget deles no primeiro deploy.

## Como a divergência de junção foi fechada

A cicatriz nº 4 da onda é um defeito de junção: dois lados certos sozinhos, contrato divergindo no
meio. Aqui havia o risco exato — o snippet do Ruby e o snippet que o teste de navegador serve.

Em vez de reescrevê-lo à mão no harness:

1. `spec/e2e/fallback/fixtures/snippet.html` é **gerado** por `web_widget_script`;
2. um exemplo de RSpec compara o fixture com o snippet atual, **byte a byte**, e falha dizendo qual
   arquivo regerar;
3. o harness do navegador serve esse fixture, trocando `__BASE_URL__`/`__WEBSITE_TOKEN__`.

A normalização do `BASE_URL` é por padrão (`sub(/var BASE_URL="[^"]*";/)`) e **não** por `gsub` do
valor de `FRONTEND_URL`: essa variável é vazia em boa parte dos ambientes e `gsub('', x)` insere `x`
entre todos os caracteres — o teste passaria ou falharia conforme o `.env` da máquina, que é o
oposto de uma guarda. Confirmado verde com `FRONTEND_URL` vazio **e** preenchido.

Para regerar o fixture depois de uma mudança deliberada no snippet:

```bash
POSTGRES_DATABASE=chatwoot_o5mov_test FRONTEND_URL="__BASE_URL__" \
  bundle exec rails runner -e test '
    require "factory_bot_rails"; include FactoryBot::Syntax::Methods
    w = build(:channel_widget); w.account.locale = "pt_BR"
    def w.website_token = "__WEBSITE_TOKEN__"
    File.write("spec/e2e/fallback/fixtures/snippet.html", w.web_widget_script)'
```

## CONTRATO exposto por este bloco

| Chave | Tipo | Default | Na ausência |
|---|---|---|---|
| `chatwootSettings.fallbackUrl` | string (URL) | `BASE_URL + "/widget?website_token=<token>"` | usa o default — a página própria do chat |
| `chatwootSettings.fallbackLabel` | string | `I18n.t('widget.fallback.label')` no idioma da **conta** | pt-BR: "Falar por outro canal" · en: "Talk to us another way" |
| `window.chatwootFallback.show()` | fn | — | definida pelo snippet; ausente no snippet antigo |
| `window.chatwootFallback.hide()` | fn | — | chamada por `sdk.js` com `?.` — **ausência é esperada e tratada** |
| `#cw-fallback-link` | id do `<a>` | — | usado para não duplicar o link |

Cores do link saem de `WidgetTokens` — a **mesma** fonte WCAG que pinta o launcher (bloco 1.02), em
vez de uma quarta fórmula de contraste. O rótulo é serializado com `to_json`: uma aspa vinda da
tradução fecharia a string JS e sabotaria justamente o caminho de degradação que este bloco cria
(há asserção para isso).

## Mecanismos e resultado

- **12 exemplos de RSpec** (`spec/models/channel/web_widget_fallback_snippet_spec.rb`) — contrato do
  snippet + paridade com o fixture. **Vermelho antes: 9 de 11.**
- **8 testes em Chromium real** (`spec/e2e/fallback/launcherFallback.spec.js`) — `page.route().abort()`
  é o bloqueio do devtools, automatizado. **8/8 verdes em 9 s.**

Vermelho medido restaurando o snippet antigo no fixture: **7 de 8 falham** (`element(s) not found`).
O único que passa é "o link NÃO aparece quando o bundle carrega" — correto, o comportamento antigo
também não mostrava link.

As asserções perguntam ao motor o valor **computado** — geometria, `opacity`, `visibility`,
`position` e a razão de contraste WCAG entre fundo e texto —, não a folha de estilo.

## LIMITE CONHECIDO, para o coordenador

Quem **já colou** o snippet antigo no site continua com ele. Não há como alcançar esses sites daqui:
o snippet é, por definição, a única parte que o cliente hospeda. Só passa a valer para quem copiar o
snippet de novo. Se isso for inaceitável, a alternativa seria servir o snippet por um loader fino e
estável (`/packs/js/loader.js`) — mas isso é mudança de arquitetura, não deste bloco.

---

# RESPOSTAS AOS DOIS AVISOS DO COORDENADOR

## 1 · Portas fixas do harness (3038 / 3999 / 8899)

**Cumprido.** Quando o aviso chegou eu tinha uma corrida em andamento; ela **terminou sozinha**
(5/5 verdes) e **não iniciei nenhuma outra**. Conferi que não sobrou processo meu:

```
LISTEN 127.0.0.1:3999  → pid 1033260, cwd /home/chatwoot/chatwoot-o1-bridge
LISTEN 127.0.0.1:3038  → pid 1031115, cwd /home/chatwoot/chatwoot-o1-bridge
```

As portas estão com a `o1-bridge` desde 14:05 — que é quem tem a janela. Nada meu.

O bloco **2.14**, feito depois do aviso, roda com **config próprio**
(`spec/e2e/fallback/playwright.config.js`, sem `webServer`) e servidor **em porta efêmera**
(`listen(0)`, dentro do processo do teste). Não precisei escolher número nenhum acima de 3070 —
o sistema dá a porta e ninguém disputa. Custo: **9 segundos** para 8 testes, contra 4–8 min do
harness de porta fixa. Se ajudar outras trilhas, o padrão está em
`spec/e2e/fallback/harness/hostServer.js` e é copiável.

### PEDIDO DE JANELA (uma corrida, quando couber)

`spec/e2e/widget/darkMode.spec.js` **já rodou 5/5 verde**. Depois disso acrescentei a ele três
asserções de **cor computada** (item 2 abaixo) que ainda **não** foram executadas. Preciso de
**uma corrida** de `--project=widget` para fechá-las — e ela **já cobre também** a regressão da
matriz, porque o arquivo do dark mode é irmão do `widget.spec.js` no mesmo projeto.

Enquanto a janela não vem, o aceite do 2.10 está sustentado pelo que **já foi medido em Chromium**
(classe no `<html>`, `color-scheme` computado, marca de instância provando "sem remount").

## 2 · Aceite de aparência verificado só em jsdom

**Resposta direta: nenhum aceite meu está nesse estado.** Detalhando bloco a bloco:

| Bloco | Aceite é de aparência? | Onde foi provado |
|---|---|---|
| **2.17** | **Não** — é de texto (`alt`, mensagem de erro, string de locale). jsdom é o instrumento adequado: o que está sob teste é o **conteúdo** do atributo, não cascata. | vitest + os 16 snapshots do widget rodaram com ele aplicado e **nenhum PNG moveu** |
| **2.10** | **Sim** | **Chromium real**, 5/5: `getComputedStyle(raiz).colorScheme`, classe no `<html>`, marca de instância. **Não** inspecionei folha de estilo |
| **2.14** | **Sim** (o link visível) | **Chromium real**, 8/8: geometria, `opacity`, `visibility`, `position` e razão de contraste WCAG, todos **computados** |

**O alerta ainda melhorou o 2.10.** Eu media `color-scheme` — que é o **sinal** de tema — mas não a
**cor que saiu**. Um `!important` de terceiro poderia prender a superfície numa cor com o
`color-scheme` correto ao lado, e meu teste diria verde. Acrescentei ao `darkMode.spec.js` a
luminância relativa WCAG **computada** de `#app`:

```
escuro → expect(luminancia).toBeLessThan(0.1)
claro  → expect(luminancia).toBeGreaterThan(0.5)
e depois da troca de tema, sem remount → toBeLessThan(0.1)
```

Essas três asserções são as que aguardam a janela. Registro para não haver dúvida: **elas estão
escritas e ainda não executadas** — as outras cinco do arquivo já rodaram verdes.

Sobre o catch-all que mordeu a `o2-config-telas`: procurei o mesmo padrão do lado do widget.
`.dark .bg-n-solid-1 { … !important }` é do **skin do dashboard**, e o CSS do widget é compilado por
`tailwind.widget.config.js`, cujo `content` **não** inclui `dashboard/**` (bloco 1.08). O widget não
carrega aquela folha. Mas isso é leitura de configuração — ou seja, raciocínio, não medição. É
exatamente por isso que a asserção de luminância entrou: ela mede o resultado, e vale
independentemente de eu ter acertado o raciocínio.

---

# ACHADO PRÉ-EXISTENTE NA BASE — não é meu, e não vou regravar

Ao rodar a matriz completa do widget encontrei **duas falhas que existem na base limpa**
(`redesenho-integra` @ `4954ed5837`), sem nenhuma alteração minha. Verifiquei restaurando a árvore
ao HEAD e rodando de novo:

| Cenário | `baseline.json` diz | Medição real (base **e** com minhas mudanças) |
|---|---|---|
| `home-light-mobile` | `{critical: 1, serious: 2}` | `{critical: 0, serious: 2}` |
| `home-dark-mobile`  | `{critical: 1, serious: 2}` | `{critical: 0, serious: 2}` |

**A a11y melhorou e o número da régua ficou para trás** — alguma trilha já mergeada corrigiu a
violação crítica que só existia no viewport mobile da home e não atualizou `baseline.json`.
Repare que `home-*-desktop` já registra `critical: 0`, o que reforça a leitura.

**Não regravei.** A régua é do projeto e a decisão é sua. O que posso afirmar com medição:
o número **está** desatualizado em relação à base, e não é efeito de nenhum dos meus três blocos.

Uma terceira falha, `messages-light-desktop`, foi **flaky**: falhou por `TimeoutError` de 8 s ao
localizar a âncora na minha corrida e **passou na base**, no mesmo commit, minutos depois. Não é
regressão determinística.

## Outro gate quebrado que consertei no caminho

`scss-lint` (gem parada desde 2019) não conhece a propriedade `color-scheme` e devolve **exit 1**
por `PropertySpelling`. Quando isso acontece, o `lint-staged` mata as tarefas irmãs com **SIGKILL** e
imprime:

```
✖ eslint --fix failed to spawn:
  Command was terminated with SIGKILL: eslint --fix …
```

**A mensagem culpa o eslint e o problema é do scss.** Custou duas tentativas de commit até eu medir
o exit code do `scss-lint` isolado. Corrigi **ensinando** o linter via `extra_properties` — não
desligando a regra, que existe para pegar erro de digitação — e deixei o aviso escrito no
`.scss-lint.yml` para quem cair nisso depois.

---

# BLOCOS BLOQUEADOS

## 2.08 — movimento, `prefers-reduced-motion`, `prefers-contrast`, `forced-colors`

**BLOQUEADO por 2.03**, da trilha `o5-primitivos`. Não implementei nada dele: 2.03 e 2.08 tocam
`_tokens.scss` e os mesmos componentes, e duas trilhas escrevendo o mesmo arquivo é o que a regra de
um-autor-por-worktree existe para impedir.

Levantei o terreno para quando destravar, sem escrever código:
- `_tokens.scss` **já tem** as três curvas da casa (`--w-ease-standard`, `--w-ease-enter`,
  `--w-ease-exit`) e um `@media (prefers-contrast: more)` que sobe o anel de foco para 3px — insumo
  pronto, vindo do 1.01;
- **não existe** nenhum `@media (prefers-reduced-motion)` no widget hoje (verificado por busca);
- `forced-colors` também não aparece em lugar nenhum — os dois balões dependem só de
  `background-color`, que é justamente o que o modo de cores forçadas substitui, então a
  distinguibilidade que o aceite pede vai exigir uma borda ou marca não-cromática.

## 2.18 — peso, segunda rodada

**BLOQUEADO por 2.\*** — é bloco de fechamento e depende da Onda 5 inteira, inclusive do 2.08 e do
que a `o5-primitivos` produzir. `0.5` já está na base ✅.

Terreno levantado, também sem escrever código:
- já existe `pnpm size` (`size-limit` + `scripts/widget-size.mjs`) — o mecanismo do aceite numérico
  do bloco **já está no repo**, não precisa ser inventado;
- há uma **tensão real entre 2.13 e 2.18** que registro agora para não ser descoberta tarde: o
  aceite do 2.18 exige `window.__SENTRY__` **undefined** dentro do iframe, então a telemetria do
  2.13 **não pode** ser o SDK do Sentry embarcado no widget. Ver a seção do 2.13 abaixo.

---

# Bloco 2.13 — telemetria de erro do widget ✅  (commit `a7badd02d5`)

**Aceite (§2.2):** «Erro forçado aparece no GlitchTip **com PII removida**; nada vaza para o
`window.onerror` do site do cliente».

## O que estava errado

**14 `catch (error) { // Ignore error }`** espalhados pelo widget e **zero** observabilidade.
Quando o widget quebrava no site de um cliente, ninguém ficava sabendo — nem nós, nem ele. O
primeiro sinal era o cliente reclamando que "o chat sumiu".

## A decisão de arquitetura, e por que ela não é o SDK do Sentry

**O aceite do 2.18 exige `window.__SENTRY__` undefined dentro do iframe.** Isso não é um detalhe
que se contorna depois: o SDK do Sentry sozinho pesa mais que o orçamento inteiro de JS do widget
(≤ 150 KB gzip), e o widget é baixado por visitante em rede móvel no site de terceiro. Se eu
tivesse embarcado o SDK aqui, o 2.18 nasceria bloqueado pelo meu próprio bloco.

Então a telemetria é um **POST cru** — sem SDK, sem instrumentação global, sem monkey-patch de
`fetch`.

**Para o nosso servidor, e não direto para o GlitchTip.** Três razões concretas:

1. O documento do widget é servido pelo **nosso** domínio → o POST é **same-origin**. Direto ao
   GlitchTip seria cross-origin e morreria na `connect-src` de qualquer cliente com CSP apertada —
   justamente os clientes cujos problemas mais queremos enxergar.
2. `SENTRY_DSN` já está configurado por VM na frota. Mandar do navegador exigiria publicar um DSN
   no HTML de cada widget e configurá-lo de novo em cada VM.
3. O servidor faz a **segunda raspagem**. Confiar só no cliente para remover dado pessoal é confiar
   em código que roda na máquina de outra pessoa.

## CONTRATO exposto por este bloco

**`POST /api/v1/widget/telemetry`** — lista **fechada** de chaves, nos dois lados
(`CHAVES_DO_ENVELOPE` no JS, `params.permit` no controller):

| Chave | Tipo | Default | Na ausência |
|---|---|---|---|
| `website_token` | string | — | **sem ele o cliente não envia**; no servidor, 404 |
| `name` | string | `'Error'` | vira `'Error'` |
| `message` | string | `''` | truncada em 1000 (o reticências conta para o limite) |
| `stack` | string | `''` | truncada em 4000 |
| `url` | string | `''` | **sem query string** — cortada nos dois lados |
| `release` | string \| null | `null` | vai `null` |
| `context.origem` | string | `'desconhecida'` | **só esta chave atravessa** o contexto |

Resposta: **sempre `204`**, mesmo sem Sentry configurado. O widget não tem o que fazer com uma
falha daqui, e devolver erro só o levaria a tentar de novo. Chave fora da lista é **descartada, não
rejeitada** — um 4xx faria o widget insistir, e telemetria não pode virar tráfego de retentativa no
site do cliente.

**Limites de volume:** teto de 10 por sessão + deduplicação por `(name, message, origem)` no
cliente; **20/min por IP** no `Rack::Attack`.

## Dois defeitos que os próprios testes pegaram durante a escrita

**1 · `NameError` em toda VM sem `SENTRY_DSN`.** A gem `sentry-ruby` só é carregada quando a
variável existe (`config/application.rb:24`) — sem ela **a constante `Sentry` não existe**. Meu
`Sentry.initialized?` levantaria `NameError`, e o endpoint de telemetria devolveria **500
exatamente nas instalações que não têm observabilidade nenhuma**. Corrigido com
`defined?(Sentry) && Sentry.initialized?`, e há exemplo rodando **sem** `stub_const` que cobre esse
ambiente cru.

**2 · Rota apontando para arquivo inexistente.** `resource :telemetry` mapeia para
`telemetries#create` — o Rails pluraliza. Só apareceu porque o spec de request bateu no endpoint de
verdade e recebeu 404.

## Mecanismos de aceite

| Onde | Arquivo | Asserções |
|---|---|---|
| unidade — reporter e scrub | `widget/helpers/specs/telemetry.spec.js` | 17 |
| unidade — **o elo** `catch` → reporter | `widget/store/modules/specs/telemetriaNosCatches.spec.js` | 6 |
| RSpec — serviço e 2ª raspagem | `spec/services/widget/error_report_spec.rb` | 19 |
| RSpec — endpoint e throttle | `spec/controllers/api/v1/widget/telemetry_controller_spec.rb` | 8 |
| **Chromium real** | `spec/e2e/telemetry/telemetria.spec.js` | **6** |

O spec do **elo** existe porque sem ele alguém poderia remover a chamada de um `catch` e todo o
resto continuaria verde: o widget voltaria a engolir erro em silêncio com a telemetria intacta e
nada para registrar. A origem é assertada **por valor** — copiar-colar deixando a origem do vizinho
é o defeito silencioso deste bloco (a telemetria funciona, os números batem, e a triagem procura no
arquivo errado).

### Sobre a validação por `127.0.0.1` — a cicatriz nº 1

O spec do throttle manda `REMOTE_ADDR` fora da safelist. E há um exemplo **deliberadamente
estranho** que afirma que, **a partir de 127.0.0.1, 25 requisições passam sem nenhum 429** — ele
documenta a armadilha e, se a safelist um dia sair, falha avisando que os outros dois podem ser
simplificados.

### O teste de navegador, e por que ele não é tautológico

A montagem imita produção: página **pai** (o site do cliente) com `window.onerror` e
`unhandledrejection` armados acumulando num array, **iframe** com o documento do widget, e o
endpoint real registrando o corpo recebido. O módulo servido ao iframe é o
`widget/helpers/telemetry.js` **de verdade**, empacotado pelo **esbuild em tempo de execução** —
sem cópia, sem artefato commitado, sem passo manual de regeneração. Se o módulo mudar, o teste roda
o novo.

O caso que mais importa: com o endpoint **fora do ar** (`route().abort()`), o array de vazamentos
do pai continua **vazio**. É a prova de que a rejeição do reporter não escapa e não transforma um
erro *registrado* num erro *não tratado* — no documento de outra empresa.

## Vermelho ANTES

Restaurando `// Ignore error` num sítio e desligando a raspagem, **7 asserções caem**:

```
× store/contacts#get                      → expected "spy" to be called with arguments…
× some com e-mail em qualquer posição     → 'joao.silva@empresa.com.br' ≠ '[email]'
× some com telefone                       → '+55 11 98765-4321' ≠ '[telefone]'
× some com CPF e CNPJ                     → '123.456.789-09' ≠ '[documento]'
× some com o que parece credencial        → 'Bearer abc.def.ghi' ≠ '[credencial]'
× atravessa estruturas aninhadas
× leva mensagem, pilha e origem, raspadas
```

## PENDENTE DE AUTORIZAÇÃO — a metade do aceite que eu não executei

O aceite diz «aparece **no GlitchTip**». Eu medi contra um **receptor local que fala o mesmo
protocolo do endpoint**, provando que o corpo emitido é exatamente o que o servidor espera e que
ele chega raspado.

**Não disparei evento de teste contra o GlitchTip de produção** (`glitchtip.chatspx.app`), e digo
isso na cara: ele recebe a frota inteira, e injetar erro sintético ali polui a triagem real de
outras pessoas — a mesma triagem de 8.987 erros/dia que já custou trabalho para limpar.

Se você autorizar, o fechamento é barato e eu executo:

```bash
# numa VM de homologação, com SENTRY_DSN apontando para um PROJETO DEDICADO de teste
curl -s -X POST https://<host>/api/v1/widget/telemetry \
  -H 'Content-Type: application/json' \
  -d '{"website_token":"<token>","name":"TesteBloco213",
       "message":"erro forcado com email teste@exemplo.com e tel +55 11 98765-4321",
       "context":{"origem":"validacao-2.13"}}'
# esperado no GlitchTip: "[widget] TesteBloco213: erro forcado com email [email] e tel [telefone]"
```

O que preciso de você: **um projeto GlitchTip dedicado ao teste** (não o do cliente) ou a
confirmação de que pode ir no projeto de homologação.

---

# RESUMO DA ENTREGA

| Bloco | Commit | Unidade | Ruby | Navegador |
|---|---|---|---|---|
| **2.17** i18n | `3b509afbcd` | 67 | — | via 16 snapshots (nenhum moveu) |
| **2.10** dark mode | `0ba948d95e` | 22 | 2 | **5** (Chromium) |
| **2.14** launcher | `caa08e85f3` | — | 12 | **8** (Chromium) |
| **2.13** telemetria | `a7badd02d5` | 23 | 27 | **6** (Chromium) |

**Suíte completa ao final:** JS `54 arquivos / 440 testes / 0 falhas`; Ruby dos meus blocos
`47 exemplos / 0 falhas`; `eslint` e `rubocop` limpos em tudo que toquei. Nenhum `--no-verify`,
nenhum gate desligado, nenhum aceite afrouxado.

**Duas falhas Ruby pré-existentes** (`conversations_controller_spec.rb:272` e
`dyte_controller_spec.rb:37`) foram verificadas restaurando as pontas Ruby ao commit da base e
rodando de novo: **falham igual**. Não são minhas e não as toquei.

## Banco de teste usado

`chatwoot_o5mov_test`, criado por mim, dedicado a este worktree — nunca o de desenvolvimento nem o
de produção. Comando:

```bash
POSTGRES_DATABASE=chatwoot_o5mov_test RAILS_ENV=test bundle exec rails db:create db:schema:load
```

## Nada de push, PR, deploy ou restart

Quatro commits locais em `o5-movimento`. O Puma da porta 3000 desta VM não foi tocado; os
servidores que subi foram Node em porta **efêmera**, dentro do processo do teste.

---

# SOBRE O `worker_done` — não consegui emitir, e por quê

Tentei, do meu próprio terminal, exatamente como a task manda:

```
orca orchestration send --type worker_done --subject "…" --outcome succeeded \
  --report-path "…/o5-movimento.md" --files-modified "…" --json
```

Resposta:

```json
{ "ok": false, "error": { "code": "dispatch_capability_invalid",
                          "message": "The Dispatch capability is missing." } }
```

**A causa é a mesma que você já tinha diagnosticado.** A task chegou aqui **colada como texto**, não
por despacho — então este terminal nunca recebeu o preamble com `taskId`, `dispatchId` e a
capability. Sem eles o `worker_done` é recusado, e é assim que deve ser: o recibo comprova
proveniência.

**O que eu deliberadamente NÃO fiz**, e quero que fique registrado:

- **não** criei um Run nem usei `run-use` para me vincular a um existente;
- **não** rodei `orchestration check`.

O motivo é concreto: `check --wait` **consome a FIFO** do Run, e um segundo processo lendo o
mailbox tira mensagens do coordenador de verdade — é um incidente que já aconteceu nesta base. Um
`worker_done` que eu fabricasse a partir de um Run que não me despachou também seria proveniência
falsa, que é exatamente o que o guia de orquestração manda não fazer.

**Então a entrega é este arquivo** — como a própria task prevê: *"A entrega é o arquivo do
relatório, não o `worker_done`."*

## O que eu diria por mensagem, já que a mensagem não sai

> **Onda 5 / trilha MOVIMENTO — 4 de 6 blocos entregues, 2 bloqueados por dependência.**
>
> Prontos e commitados localmente: **2.17** (`3b509afbcd`), **2.10** (`0ba948d95e`), **2.14**
> (`caa08e85f3`), **2.13** (`a7badd02d5`). Working tree limpo, nada pushado.
>
> Bloqueados e **não tocados**: **2.08** (falta **2.03**, da `o5-primitivos`) e **2.18** (bloco de
> fechamento, falta a Onda 5 inteira). Levantei o terreno dos dois sem escrever código — inclusive
> uma tensão que vale saber agora: **o aceite do 2.18 proíbe o SDK do Sentry dentro do iframe**, e é
> por isso que o 2.13 foi feito como POST cru em vez de SDK embarcado. Os dois blocos se
> contradiziam na leitura ingênua.
>
> **Duas coisas dependem de você:**
>
> 1. **Uma janela do harness de porta fixa.** `darkMode.spec.js` já rodou 5/5 verde; depois disso
>    acrescentei **3 asserções de cor computada** (por causa do seu aviso do catch-all) que ainda
>    não executei. Uma corrida basta, e ela já cobre a matriz junto.
> 2. **Autorização para o GlitchTip.** A metade "aparece no GlitchTip" do aceite do 2.13 está medida
>    contra receptor local. Não disparei contra o GlitchTip de produção porque ele recebe a frota
>    inteira e injetar erro sintético polui a triagem real. Me diga o projeto dedicado e eu fecho —
>    o comando está no relatório.
>
> **Um achado que não é meu e não regravei:** `baseline.json` diz `critical: 1` para
> `home-light-mobile` e `home-dark-mobile`; a medição real é **0**, e falha **igual na base limpa**
> (verifiquei restaurando a árvore ao commit `4954ed5837` e rodando de novo). A a11y melhorou e o
> número da régua ficou para trás. A decisão de mexer na régua é sua.
>
> **Um gate quebrado que consertei no caminho:** `scss-lint` não conhece `color-scheme` e devolve 1;
> aí o `lint-staged` mata as tarefas irmãs com SIGKILL e imprime `eslint --fix failed to spawn` — a
> mensagem culpa o eslint e o problema é do scss. Ensinei o linter via `extra_properties` (não
> desliguei a regra) e deixei o aviso escrito no `.scss-lint.yml`, porque isso vai morder outra
> trilha assim que alguém encostar num `.scss`.

---

# JANELA DO HARNESS — o que a corrida achou (e não era o que eu esperava)

Usei a janela para a matriz **completa**, não só as 3 asserções novas — porque o 2.10 declara
`color-scheme` no `:root`, e isso podia mover pixel. Moveu. **A corrida pagou por si.**

## ACHADO 1 — regressão visual que EU introduzi

`unread-dark-desktop` e `unread-dark-mobile` falharam em `toHaveScreenshot`:
**66.912 pixels, 60% da imagem.** Li o diff antes de qualquer outra coisa, e o que ele mostra é
inequívoco:

| | fundo do documento |
|---|---|
| baseline (esperado) | claro / transparente — os balões flutuam sobre o site |
| **com o meu 2.10** | **preto opaco**, cobrindo a área inteira do iframe |

**O que isso seria na tela do cliente:** uma tarja preta sobre o site dele, toda vez que houvesse
mensagem não lida com tema escuro. Nenhum teste de unidade veria — jsdom não tem canvas de UA.

### A primeira correção estava errada, e eu só soube porque medi

Corrigi com `background-color: transparent` no `:root`. O diff caiu de 60% para 39% e eu quase
relatei "resolvido" a partir de uma **lista parcial de saída** — os `unread-*` são os últimos
cenários da matriz e ainda não tinham rodado quando olhei. **Não estava resolvido.**

Em vez de tentar de novo às cegas, perguntei ao Chromium. Um probe pequeno, em Chromium próprio
(sem harness, sem porta fixa, ~10 s), com a estrutura real do documento:

```
:root.dark { color-scheme: dark }                             → canvas rgb(18,18,18)
:root.dark { color-scheme: dark; background: transparent }    → canvas rgb(18,18,18)
   + `background: transparent` também no `body`               → canvas rgb(18,18,18)
:root.dark .woot-widget-app { color-scheme: dark }            → canvas rgb(255,255,255) ✅
                                        …e `color-scheme` do painel = dark ✅
```

**A causa:** o agente de usuário pinta o canvas do documento com a cor do esquema quando o elemento
raiz não tem fundo próprio — e declarar `transparent` **não desliga isso**: um raiz transparente faz
o canvas cair no padrão do UA, que sob `color-scheme: dark` é escuro. Não há CSS que evite; só não
declarar `color-scheme` no raiz.

### A correção definitiva, e a divergência do aceite que eu preciso declarar

`color-scheme` passou para o **container do app** (`.woot-widget-app`, classe nova ao lado do
`id="app"` em `views/widgets/show.html.erb`) em vez do `:root`.

**Isso diverge da letra do aceite**, que diz «`color-scheme` no `:root`». Declaro em vez de mudar em
silêncio:

- **o efeito que o aceite busca está inteiro**: `color-scheme` é herdado, então a barra de rolagem da
  lista de mensagens, o `caret` do composer e os controles do pré-chat — todos dentro do container —
  continuam escuros. Medido: `color-scheme` computado do painel = `dark`;
- **o que se perde é a barra de rolagem do DOCUMENTO**, que não existe: quem rola no widget é a
  lista, não o documento;
- **a letra do aceite, aplicada literalmente, entrega uma tarja preta no site do cliente.** O aceite
  está errado nesse ponto, e é isso que estou escalando.

Se você preferir a letra, o caminho seria condicionar a classe do `<html>` à rota (não aplicar no
unread) — mas aí o unread perde o tema escuro, o que me parece pior. **A decisão é sua.**

O seletor é por classe e não `#app` porque `scss-lint` recusa seletor de id — e a regra tem razão:
id em folha de estilo é especificidade que ninguém sobrescreve depois.

## ACHADO 2 — a minha própria asserção nova estava passando pelo motivo errado

Este é o mais desconfortável de escrever, e é exatamente o que o seu aviso sobre jsdom previa —
só que aconteceu **dentro do teste de navegador**.

As 3 asserções de luminância apontavam para `#app` e subiam pelos ancestrais atrás de um fundo
opaco. Como o documento do widget é transparente, o laço chegava ao topo sem achar nada e devolvia
`rgba(0, 0, 0, 0)` → **luminância 0**. Resultado:

```
tema CLARO   → expect(0).toBeGreaterThan(0.5)   ✘ reprovou  (foi assim que eu descobri)
tema ESCURO  → expect(0).toBeLessThan(0.1)      ✓ PASSOU — pelo motivo errado
```

**A asserção certa, no elemento errado.** Se o caso claro não existisse, eu teria relatado
"luminância medida em Chromium" com um teste que nunca mediu cor nenhuma.

**Correção:** medir `#app > div` — a superfície que de fato pinta — e uma guarda nova,
`exigirSuperficieOpaca()`, que **reprova quando o alfa é menor que 1**, com a mensagem
`"superfície transparente (rgba(0,0,0,0)) — não há cor computada para medir"`. Sem essa guarda, o
mesmo falso verde volta na próxima vez que alguém mexer no seletor.

## ACHADO 3 — as duas falhas pré-existentes, ainda presentes

`home-light-mobile` e `home-dark-mobile` continuam reprovando por `baseline.measurements[...].axe`
(`critical: 1` esperado, `0` medido). É o que você já corrigiu na `redesenho-integra` trocando a
igualdade por teto — **eu ainda não mergeei os 108 commits**, então elas aparecem aqui. Não são
minhas e não as toquei.

## As três corridas

| corrida | resultado |
|---|---|
| 1ª | 20 passed, **5 failed** — 2 pré-existentes + **2 snapshots movidos** + 1 asserção minha |
| 2ª (`transparent` no `:root`) | 21 passed, 4 failed — a asserção de luminância passou a medir certo; **os 2 snapshots continuavam movidos** (60% → 39%) |
| 3ª (`color-scheme` no container) | ver abaixo |

---

# GLITCHTIP — PAREI, como você mandou. E o motivo não era o esperado

Você autorizou com três limites, e o primeiro deles é onde eu travei: **projeto dedicado, nunca um
de cliente**. Não existe nenhum projeto de teste no GlitchTip — só os **seis de VM/cliente**
(`agn`, `catatau`, `homologacao`, `producao`, `sentinela`, `tozi`). Tentei criar `redesenho-teste`
e **não consegui**. Não usei nenhum existente.

## O que eu descobri tentando — e vale para a equipe inteira

**A criação de projeto está quebrada nesta instância**, e não é limitação do meu acesso. A prova é
que a **própria interface** falha:

```
POST /api/0/teams/simplex/spx/projects/   →  404      (clicando "Create Project" no painel)
GET  /api/0/teams/simplex/spx/projects/   →  200      (a rota EXISTE)
GET  /api/0/teams/simplex/spx/            →  200
GET  /api/0/teams/simplex/spx/members/    →  []       ← o time NÃO TEM MEMBROS
```

Fiz login real no painel (`dev@simplexsolucoes.com.br`), preenchi o formulário, cliquei em
**Create Project** — e capturei o `POST` que o próprio front dispara. **404.** Ou seja: quem tentar
criar um projeto pela UI hoje vai bater no mesmo muro, sem mensagem de erro na tela.

**A causa mais provável:** o time `spx` está com a lista de membros **vazia**, e `dev@` tem papel
`member` na org (o `owner` é `admin@chatspx.app`). O GlitchTip responde 404 — não 403 — quando o
usuário não pertence ao time do projeto. Isso nunca apareceu antes porque **os seis projetos foram
criados por `manage.py shell`**, contornando a UI: ninguém precisou ser membro.

## Por que eu parei aqui em vez de contornar

O contorno existe e é de um comando — adicionar `dev@` ao time `spx`, ou criar o projeto por
`manage.py shell` via SSH na cyaws. **Não fiz nenhum dos dois**, por dois motivos:

1. **Você mandou parar**, e a instrução foi explícita.
2. Mais importante: **alterar papel/membership no GlitchTip da frota é administração de acesso**,
   que é uma categoria diferente de "criar um projeto de teste" — e essa você não me delegou. É
   mudança de permissão numa instância que atende seis clientes.

## O que preciso de você (qualquer um dos três destrava)

| opção | o que é | custo |
|---|---|---|
| **A** | você adiciona `dev@simplexsolucoes.com.br` ao time `spx` (ou me autoriza a fazê-lo) | 1 clique no painel; eu sigo sozinho daqui |
| **B** | você cria o projeto `redesenho-teste` e me passa o DSN | 1 minuto |
| **C** | me autoriza o `manage.py shell` na cyaws, como foi feito com os seis originais | SSH + 1 comando |

Assim que houver projeto dedicado, o fechamento é este — e o evento **se identifica como teste no
próprio conteúdo**, como você exigiu, para ninguém investigar um incidente que nunca houve:

```bash
curl -s -X POST https://<host-homologacao>/api/v1/widget/telemetry \
  -H 'Content-Type: application/json' \
  -d '{"website_token":"<token>",
       "name":"TesteSinteticoBloco213",
       "message":"[TESTE SINTETICO - bloco 2.13, ignorar] erro forcado com email teste@exemplo.com, tel +55 11 98765-4321 e cpf 123.456.789-09",
       "context":{"origem":"validacao-2.13-teste-sintetico"}}'
```

Esperado no painel, com a PII já removida pelas DUAS raspagens:

```
[widget] TesteSinteticoBloco213: [TESTE SINTETICO - bloco 2.13, ignorar] erro forcado com
email [email], tel [telefone] e cpf [documento]
tags: source=web_widget · origem=validacao-2.13-teste-sintetico
```

## Registro para a próxima pessoa

- **Projeto usado: NENHUM** — nada foi enviado ao GlitchTip nesta execução.
- **Projeto pretendido:** `redesenho-teste`, org `simplex`, time `spx` (a criar).
- **Credenciais e DSNs** já estão em `reference_glitchtip_observabilidade` (memória) — não repito
  segredo aqui.
- **Armadilha documentada:** a UI de criação de projeto retorna 404 silencioso enquanto o time
  estiver sem membros. Quem for criar projeto novo tropeça nisso.

## ACHADO 4 — o ponto de montagem do widget existe em DOIS arquivos

Ao mover o `color-scheme` para uma classe no container do app, acrescentei `.woot-widget-app` em
`app/views/widgets/show.html.erb`. A corrida seguinte reprovou **os cinco** testes de dark mode com
`TimeoutError: locator.evaluate` — o seletor não existia.

Motivo: `spec/e2e/widget/harness/widget-server.mjs:140` tem a **própria cópia** do elemento de
montagem:

```html
<div id="app" class="h-full"></div>     <!-- ERB de produção -->
<div id="app" class="h-full"></div>     <!-- harness e2e, cópia manual -->
```

**É a cicatriz nº 4 outra vez**, num lugar que ninguém tinha olhado: dois documentos escrevendo o
mesmo contrato, cada um certo sozinho. Custou **sete minutos de corrida** para aparecer, na forma
de um timeout que parece problema de rede.

Sincronizei o harness **e** deixei a guarda: `app/javascript/widget/specs/appMountParity.spec.js`
compara o conjunto de classes dos dois arquivos e reprova nomeando o que falta —

```
× o ERB de produção e o harness e2e montam com as MESMAS classes
  → expected [ 'h-full' ] to deeply equal [ 'h-full', 'woot-widget-app' ]
```

**8 milissegundos** contra sete minutos. O arquivo mora em `app/javascript/widget/specs/` e não ao
lado do harness porque o vitest só varre `app/**` — uma guarda que o runner não enxerga não guarda
nada, e eu descobri isso tentando.

A segunda asserção é por valor (`toContain('woot-widget-app')`) porque, se alguém remover a classe
dos **dois** arquivos, a primeira continuaria verde e o tema escuro do painel sumiria em silêncio.

## ACHADO 5 — uma crase derrubou o harness inteiro, e a mensagem culpa a porta

Ao documentar a sincronização acima, escrevi o comentário no `widget-server.mjs` com crases
markdown — `` `app/views/...` ``. Só que o HTML daquele arquivo vive **dentro de uma template
literal**, e crase fecha template literal. Resultado:

```
SyntaxError: Unexpected identifier 'app'
Error: Process from config.webServer was not able to start. Exit code: 1
```

**É exatamente a mensagem que você descreveu como sintoma de contenção de porta** — e desta vez o
arquivo estava mesmo quebrado. Vale para a tranca: `"webServer was not able to start"` tem **duas**
causas possíveis, e antes de acusar a porta vale abrir o log do `[WebServer]`, que traz o
`SyntaxError` de verdade algumas linhas acima.

Corrigido tirando as crases, com um aviso escrito no próprio comentário para o próximo. Agora o
módulo é verificado antes de qualquer corrida com:

```bash
node --input-type=module -e "import('./spec/e2e/widget/harness/widget-server.mjs')"
```

**1 segundo** contra 7 minutos de corrida perdida. Recomendo pôr isso antes de qualquer
`playwright test --project=widget` que tenha mexido no harness.

## RESULTADO DA JANELA — corrida 5, a que fecha

```
23 passed | 2 failed  (5,0 min)

✓ os 16 snapshots, INCLUSIVE unread-dark-desktop e unread-dark-mobile
✓ os 5 do darkMode.spec.js, inclusive as 3 asserções novas de cor computada
✗ home-light-mobile   ← pré-existente (baseline axe, já corrigido na integra)
✗ home-dark-mobile    ← pré-existente (idem)
```

**As duas únicas falhas são as pré-existentes que você já corrigiu na `redesenho-integra`.**
Nenhuma é minha, e nenhum snapshot foi regravado — a regressão foi **corrigida no código**, que era
o certo.

Commit: `fd1feebe34`. Suíte JS ao final: **55 arquivos / 442 testes / 0 falhas**
(inclui a guarda de paridade nova). `eslint`, `scss-lint` e `rubocop` limpos.

### Custo desta janela, com honestidade

Foram **5 corridas**, não 1. O que consumiu:

| corrida | o que revelou |
|---|---|
| 1 | a regressão do canvas (2 snapshots) + o falso verde da minha asserção |
| 2 | que `background: transparent` **não** resolve — a correção óbvia estava errada |
| 3 | que o ponto de montagem existe em dois arquivos (o harness não tinha a classe) |
| 4 | que uma crase no meu comentário derrubou o `webServer` |
| 5 | ✅ verde, menos as 2 pré-existentes |

As corridas 2, 3 e 4 foram erro meu, e três delas eram evitáveis por verificação de 1–10 segundos:
o probe de canvas (10 s) responderia a 2; a guarda de paridade (8 ms) responderia a 3; o
`node --input-type=module -e "import(...)"` (1 s) responderia a 4. **As três verificações agora
existem no repo**, então o próximo não paga esse pedágio.

### 🔓 TRANCA LIBERADA

Confirmei por `ss`: **3038/3999/8899 livres**, zero processos meus (`ps aux | grep playwright` = 0).
A janela é sua para repassar. Não iniciarei outra corrida sem liberação explícita.

---

# `worker_done` — segunda tentativa, erro DIFERENTE

Tentei de novo depois de fechar a janela. A recusa mudou:

| tentativa | resposta |
|---|---|
| 1ª (antes da janela) | `dispatch_capability_invalid` — "The Dispatch capability is missing" |
| 2ª (agora) | **"No owning Orca client is connected to the relay"** |

Ou seja: além de eu não ter a capability (a task chegou colada, sem preamble), **agora não há
coordenador conectado ao relay**. Continuo sem criar Run nem rodar `check`, pelo mesmo motivo de
antes: `check --wait` consome a FIFO de quem estiver coordenando, e proveniência fabricada é pior
que recibo ausente.

**Este arquivo é a entrega.** O que eu diria por mensagem, atualizado:

> **Janela do harness: usada e LIBERADA.** `ss` confirma 3038/3999/8899 livres, zero processos meus.
> Resultado final **23 passed / 2 failed**, e as 2 são as pré-existentes do baseline que você já
> corrigiu na integra. Os 16 snapshots e os 5 do dark mode, verdes.
>
> **A corrida achou uma regressão visual MINHA, e valeu cada minuto.** `color-scheme` no `:root`
> faz o agente de usuário pintar o canvas do documento: o `unread-dark` virou uma tarja preta sobre
> o site do cliente — 66.912 pixels, 60% da imagem. Corrigi movendo o `color-scheme` para o
> container do app. **Isso diverge da letra do aceite** ("`color-scheme` no `:root`") e está
> escalado, não mudado em silêncio: a letra, aplicada literalmente, entrega a tarja preta. O efeito
> que o aceite busca (barra de rolagem, `caret`, controles escuros) está inteiro, porque
> `color-scheme` é herdado.
>
> **E achei um falso verde meu**, do tipo exato que você alertou — só que dentro do teste de
> navegador: a asserção de luminância media `#app`, que é transparente, obtinha 0, e `0 < 0,1`
> **passava no tema escuro pelo motivo errado**. Só apareceu porque o caso claro existia. Agora
> mede a superfície que pinta, com uma guarda que reprova quando o alfa é menor que 1.
>
> **GlitchTip: parei, como você mandou** — e a razão não era a esperada. Não existe projeto
> dedicado, e **a criação está quebrada na instância**: a própria UI recebe 404 em
> `POST /api/0/teams/simplex/spx/projects/`, porque o time `spx` está **sem membros** (os seis
> projetos foram criados por `manage.py`, contornando a UI). Não usei projeto de cliente e **não
> alterei permissão nenhuma** — isso é administração de acesso numa instância que atende seis
> clientes, e você não me delegou. Três opções para destravar estão no relatório; qualquer uma
> resolve.
>
> **Cinco commits locais**, nada pushado: `3b509afbcd` (2.17), `0ba948d95e` (2.10), `caa08e85f3`
> (2.14), `a7badd02d5` (2.13), `fd1feebe34` (correção da regressão).
>
> **2.08 e 2.18 seguem bloqueados e intocados.** Não implementei 2.03 para me destravar.

---

# FALHA DO 2.13 NA INTEGRADA — a pista estava errada, e a causa é outra (commit `ed0f589a36`)

**Sintoma relatado:** `telemetry_controller_spec.rb:102` — a 21ª requisição devolve **204** onde o
teste espera **429**, com o exemplo irmão passando.

**Pista sugerida:** a safelist de `127.0.0.1` do `Rack::Attack`.

## Refutada — e é importante que fique claro por quê

Este arquivo **sempre** mandou `REMOTE_ADDR: 203.0.113.91`, fora da safelist. Ele foi escrito
justamente contra essa cicatriz, e tem um exemplo dedicado que a documenta ("o throttle é INVISÍVEL
a partir de 127.0.0.1"). Também confirmei que **spec e throttle são byte a byte idênticos** na
`redesenho-integra` — não foi divergência de merge:

```
md5 do spec: 5cfda8ec2f6dfe2e900a1276f4fa328d  (meu worktree)
md5 do spec: 5cfda8ec2f6dfe2e900a1276f4fa328d  (redesenho-integra)
rack_attack.rb:86  throttle('widget_telemetry/ip', limit: 20, period: 1.minute)   ← presente lá
```

Rodei o exemplo **4 vezes seguidas aqui: 4 verdes.** Ou seja, era intermitente — o que já descartava
a safelist, que seria determinística.

## A causa real, reproduzida ANTES de escrever qualquer correção

`Rack::Attack` conta por **janela fixa**: a chave do contador é `Time.now.to_i / period`. Escrevi um
spec temporário com relógio controlado:

```
travel_to('12:00:10') { 20.times { post }; post }   → 429   ✓ mesma janela
travel_to('12:00:59') { 20.times { post } }
travel_to('12:01:00') { post }                      → 204   ✓ O SINTOMA, reproduzido
```

Vinte requisições no fim de um minuto e a 21ª no minuto seguinte caem em **contadores diferentes**.
A 21ª passa com o IP certo, o throttle registrado e funcionando perfeitamente.

**Janela de falha:** as 21 requisições levam ~1 s contra uma janela de 60 s → **~1 em 60 execuções**.
Rara o bastante para passar na revisão e voltar depois, no pipeline de outra pessoa — que foi
exatamente o que aconteceu.

## O conserto é o teste, não o produto

O throttle está correto: janela fixa é o comportamento do `Rack::Attack`, não um defeito.
`travel_to` prende as 21 requisições na mesma janela, que é a condição sob a qual o limite existe.

E o outro lado da janela virou **asserção explícita** em vez de armadilha — um exemplo novo afirma
que a cota reabre no minuto seguinte:

> Na prática o teto é **20 por janela**, não 20 por minuto corrido: ao redor da virada cabem até 40
> em poucos segundos. Para telemetria isso é aceitável, e agora está **escrito** em vez de
> descoberto por alguém.

Resultado: **9 exemplos, 0 falhas** (era 8; o novo é o da virada). Suíte Ruby dos meus blocos:
**48 exemplos, 0 falhas**.

## Item 4 — auditoria dos vizinhos

| spec | conta limite? | depende do relógio? | veredito |
|---|---|---|---|
| `telemetry_controller_spec.rb` | sim, 3 exemplos | **sim** | ✅ corrigido |
| `widget/helpers/specs/telemetry.spec.js` | sim (`MAX_POR_SESSAO`) | **não** — contador em memória | imune por construção |
| `spec/e2e/telemetry/telemetria.spec.js` | sim (mesmo teto) | **não** | imune por construção |
| demais specs meus | não contam limite | — | fora do escopo |

**Era o único caso meu.** Os tetos do lado JS não têm janela nem relógio: são
`enviadosNestaSessao >= MAX_POR_SESSAO`, um inteiro em memória.

### Um vizinho com o mesmo defeito, que NÃO é meu

`spec/requests/rack_attack_widget_contact_spec.rb` (bloco **1.12**) faz `Array.new(60)` e
`60.times` sem `travel_to`, contra um throttle de **60/hora**. A chance de cruzar a virada é
~0,4% por execução em vez de ~1,7% — menor, mas é a **mesma falha**, e vai aparecer um dia no
pipeline de alguém.

**Não toquei**: é arquivo de outra trilha e alterá-lo geraria conflito. A correção é de uma linha —
envolver os exemplos em `travel_to(instante_fixo) do … end`, como fiz aqui.

## A lição que eu tiro disto

Um teste de throttle pode falhar por **dois** motivos independentes, e os dois produzem o mesmo
"esperava 429, veio 2xx":

1. **a requisição não passa pelo throttle** (safelist de localhost) — determinístico, falha sempre;
2. **a requisição passa, mas cruza a janela** — intermitente, falha ~1 em 60.

A intermitência é o que distingue os dois, e é de graça observar: quatro execuções seguidas
custaram um minuto e já apontavam para (2). **Ler o código sugeriu (1); medir mostrou (2).**
