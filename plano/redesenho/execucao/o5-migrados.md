# Onda 5 — Os três blocos migrados (3.15 · 4.09 · 4.10)

* **Worktree:** `/home/chatwoot/chatwoot-o5-migrados` · **Branch:** `o5-migrados`
* **Base:** `eb31616f31` — `redesenho-integra` com 125 commits, 2.01 dentro
* **Data:** 18/08/2026

| Bloco | Estado | Commit |
|---|---|---|
| **3.15** — o widget honra `show_if`/`step`/`mask`/`validator` | ✅ **FECHADO** | `87d1fd6333` |
| **4.10** — CSAT redesenhado e conteúdo rico | 🚧 em curso | — |
| **4.09** — identidade de IA | ✅ **FECHADO** (2.06 destravou) | `a06cd8af7b` |

O worktree **não existia** quando esta trilha começou; foi criado com
`git worktree add -b o5-migrados … redesenho-integra`, então o merge da base nasceu feito (não há
commit de merge: a branch parte da ponta da integra). `node_modules` foi instalado no próprio
worktree em vez de apontar para o de outra trilha — symlink me acorrentaria a um diretório que não
é meu e que pode sumir.

---

## 1. Bloco 3.15 — o contrato, conferido chave por chave

O coordenador pediu: *ler o contrato da trilha de pré-chat antes de escrever, e dizer se ele casa
com o que foi implementado; divergindo, escalar em vez de acertar direto com eles.*

**Não conferi o relatório: conferi o código.** A fonte é
`app/models/channel/web_widget/pre_chat_form_schema.rb`, o que o 3.12 gravou.

### 1.1 Sete chaves de campo — produtor × consumidor

| Chave | Schema Ruby (produtor) | Consumidor do widget (3.15) | Casa? |
|---|---|---|---|
| `step` | `integer`, 1–8 (`MAX_STEP`) | `stepOf()`; fora da faixa ou ausente → etapa **1** | ✅ |
| `position` | `integer`, 0–99 | **não consumido** — ver §1.4 | ⚠️ declarado |
| `mask` | `[string, null]`, enum `cpf cnpj cpf_cnpj cep uf phone` + `nil` + `''` | `maskFieldValue()` delega a `applyMask` do 3.13; `null`/`''`/desconhecida → valor intacto | ✅ |
| `validator` | `[string, null]`, 11 nomes + `nil` + `''` | `fieldErrorFor()` delega a `validateFieldValue` do 3.13 | ✅ |
| `help_text` | `[string, null]`, ≤ 160 | renderizado no `:help` do campo | ✅ |
| `error_message` | `[string, null]`, ≤ 160 | vence o catálogo, **menos** em `REQUIRED` (§1.3) | ✅ |
| `show_if` | `object`, `required: [field, operator]`, `additionalProperties: false` | `evaluateCondition()` | ✅ |

`show_if` por dentro: `field` (string 1–100), `operator` (enum `is is_not contains filled`),
`value` (`[string, null]`, ≤ 200). Os quatro operadores estão implementados e testados um a um.

**Veredito: o contrato casa. Nenhuma divergência a escalar.** O vocabulário do widget não é
paralelo — ele **importa** o do 3.13 (`widget/helpers/brMasks` reexporta `shared/helpers/brMasks`),
exatamente como a §6.4 do relatório de pré-chat pede. Não há segundo dicionário para divergir.

### 1.2 As três formas de `show_if` — decididas, não deduzidas em runtime

O coordenador herdou a pergunta do defeito que aquela trilha achou **depois** da suíte verde
("Sempre mostrar" gravava `show_if: null` contra um schema `type: object` — 422 na operação mais
banal). Deste lado, a pergunta é o que o widget faz quando a chave chega ausente, nula ou vazia.

| Forma que chega | Decisão | Testado em |
|---|---|---|
| **ausente** (`undefined`) | campo **visível** | `preChatFieldRules.spec.js` |
| **`null`** | campo **visível** | idem |
| **`{}` vazio** | campo **visível** | idem |
| `operator` ausente ou fora do vocabulário | campo **visível** | idem |
| `is`/`is_not`/`contains` **sem `value`** | campo **visível** | idem |
| `field` apontando para campo **inexistente** | campo **visível** | idem |
| bem formada e **satisfeita** | campo visível | junção |
| bem formada e **não satisfeita** | campo **escondido** | junção |

**O princípio, e ele é uma escolha, não um acidente: condição malformada ou ausente NUNCA esconde
campo. Falha aberta.**

A razão é a **assimetria do dano**. Esconder por engano um campo obrigatório deixa o visitante com
um formulário que não fecha e sem nada para corrigir — ele perde o canal de contato, e o cliente
perde o lead. Mostrar um campo a mais é incômodo cosmético. Entre os dois erros possíveis, este
consumidor escolhe sempre o barato.

O único caso que exige nuance é o **campo que existe mas está vazio**: aí a condição é honrada
(fica escondido), porque é literalmente a funcionalidade funcionando — o gatilho ainda não foi
respondido. Um teste separa os dois casos, para ninguém "simplificar" um no outro depois.

### 1.3 Duas decisões de comportamento que o contrato não determina

1. **`error_message` do administrador NÃO substitui `REQUIRED`.** Ela foi escrita para explicar um
   formato ("Confira o CPF do titular"); num campo vazio ela troca a instrução certa por uma
   confusa. O catálogo vence só nesse código.
2. **Erro de formato aparece no `blur`, não a cada tecla.** Acusar "CPF inválido" no terceiro
   dígito é ruído, e ruído em formulário de captura faz o visitante desistir. `touchedFields`
   registra quem já foi visitado.

### 1.4 O que NÃO foi implementado, e está declarado

**`position` (0–99) não é honrado pelo widget.** Não está no título do bloco — que nomeia
`mask`/`validator`/`step`/`show_if` — e ordenar campos é mudança de layout, não de regra. Fica
registrado como chave do contrato **que o produtor grava e o consumidor ignora**, que é
exatamente a categoria que a §6.4 do relatório de pré-chat manda declarar em vez de deixar
implícita. Se a ordenação for desejada, é bloco próprio.

### 1.5 O defeito de junção que esta trilha achou e fechou

`onSubmit` destrinchava os quatro campos padrão de `formValues` **direto**, sem passar por
`enabledPreChatFields`:

```js
const { emailAddress, fullName, phoneNumber, message } = this.formValues;
```

Cenário real: o visitante responde "empresa", digita o e-mail, muda para "pessoa". O campo some da
tela — **e o valor velho viajava no envio assim mesmo.** É a mesma forma do pior defeito desta
execução: cada lado certo sozinho, errado na junção. Corrigido, com teste que monta o componente,
troca a resposta do gatilho e confere o payload emitido.

### 1.6 O ponto de alavanca, e por que ele é uma linha só

`enabledPreChatFields` é a fonte de que derivam **quatro** consumidores: o que renderiza, o que é
validado, o que é enviado (`conversationCustomAttributes` / `contactCustomAttributes`) e o que
conta para o rascunho de lead do 4.18 (`filledAnswers`, `stoppedAt`). Filtrar por `visibleFields()`
**ali** faz o `show_if` valer para os quatro de uma vez. É o que permitiu a casca: 428 linhas de
`Form.vue` continuaram no lugar.

### 1.7 Mecanismo e resultado real

| Arquivo | Testes | O que prova |
|---|---|---|
| `widget/helpers/specs/preChatFieldRules.spec.js` | **44** | a regra isolada + paridade das 12 chaves de i18n |
| `widget/components/PreChat/specs/Form.conditional.spec.js` | **17** | a **junção**, com o componente montado |

**Vermelho provado restaurando o `Form.vue` original no lugar** — não imaginando que o teste
cobre:

```
Tests  12 failed | 5 passed (17)
  → expected [ 'tipo', 'cnpj', 'message' ] to not include 'cnpj'
  → expected 'a@b.com' to be undefined
  → expected '52998224725' to be '529.982.247-25'
  → wrapper.vm.delegatedErrors is not a function
```

**Os 2 que passam são os que afirmam o comportamento de HOJE** (campo visível segue visível; campo
visível segue sendo enviado) — são a guarda contra esconder demais, e é bom que já passassem.

Suíte do widget depois: **68 arquivos, 688 testes, verde**. Widget + shared: **100 arquivos,
1123 testes, verde**.

### 1.8 i18n

13 chaves novas em `PRE_CHAT_FORM`, em **pt_BR e en**: 12 em `VALIDATION` (uma por código que o
3.13 devolve) e `CONTINUE`. Paridade conferida 12 × 12, e há teste que a executa.

As chaves saem de um **mapa fechado e literal** (`VALIDATION_MESSAGE_KEYS`), não de chave
interpolada. O lint `@intlify/vue-i18n/no-dynamic-keys` não consegue verificar chave montada em
runtime — uma que faltasse em `en` só apareceria como texto cru na tela de um visitante
estrangeiro. O único `eslint-disable` do arquivo está justificado no código e **aponta para o
teste que faz a conferência que o lint não faz**.

> **Nota de lint:** sobram 3 warnings da mesma regra em `a11y.spec.js`, `darkScheme.spec.js` e
> `typingDots.spec.js` — **pré-existentes, das trilhas 1.06 e 1.07**. Não toquei em arquivo alheio.

### 1.9 Um fixture meu que estava errado, e como descobri

O teste da regra anti-lixo usava `'asdfgh'` como nome-lixo. **Não é:** a regra do 3.13 marca por
ausência de vogal, menos de 2 caracteres, ou três repetidos — e `asdfgh` tem vogal. O teste falhou,
e a correção foi **ler a regra** e trocar por `'bcdfg'` (sem vogal), com o motivo escrito no
próprio teste. Um fixture que passasse por engano mediria a minha suposição, não o helper.

---

## 2. Bloco 4.10 — CSAT redesenhado e conteúdo rico

**Aceite (§2.2):** *`role="radiogroup"` com rótulo textual por opção; alvos 44×44; máximo 3 botões
por card.*

### 2.1 Um achado de localização, antes de qualquer código

A lista de arquivos do bloco diz `CustomerSatisfaction.vue`, `StarRating.vue`, `ChatCard.vue`.
**Os três vivem em `app/javascript/shared/components/`, não em `widget/components/`.**

Consequência imediata, e ela é regra: **R21 se aplica** — mexer em `shared/` obriga a rodar
também a suíte do dashboard, porque os mesmos componentes são renderizados nos dois lados.

### 2.2 O defeito de junção que apareceu ao ler o i18n

`CSAT_RATINGS` (em `shared/constants/messages.js`) declara, para cada opção, um
`translationKey: 'CSAT.RATINGS.POOR'`. Medido:

| Bundle | `CSAT.RATINGS` |
|---|---|
| dashboard (`csatMgmt.json`) | ✅ `POOR FAIR AVERAGE GOOD EXCELLENT` |
| **widget** (`pt_BR.json`) | ❌ **não existia** |

O componente é renderizado **nos dois**. Hoje nada quebrava porque o widget nunca usava o
`translationKey` — ele renderizava só o emoji. **No instante em que o rótulo passasse a ser usado
como nome acessível, o widget mostraria a chave crua ao visitante.** É a mesma família do defeito
que custou caro nesta onda: cada lado certo sozinho.

Corrigido antes de usar: as cinco chaves entraram em `pt_BR` **e** `en` do widget, com **texto
limpo** — o do dashboard traz o emoji dentro da string (`"😞Ruim"`), e como nome acessível isso faz
o leitor de tela anunciar o símbolo antes da palavra. Um teste executa a regra.

### 2.3 Os três defeitos do `StarRating`, cada um visível na tela de alguém

| # | Defeito | Correção |
|---|---|---|
| 1 | `aria-label="Star 3"` — **inglês cravado** numa conta pt-BR | sai do i18n, e diz a escala inteira ("3 estrelas de 5"): "3" sozinho não informa de quanto |
| 2 | cinco `<button>` soltos — o leitor anunciava cinco botões independentes, sem dizer que escolher um desmarca os outros nem a posição na escala | `role="radiogroup"` + `role="radio"` + `aria-checked` |
| 3 | alvo de ~32 px (`p-1` em volta de ícone de 24) | **44×44** (SC 2.5.8) sem mudar o tamanho do ícone — cresce só a área clicável |

Veio junto o **teclado**, porque `radiogroup` sem setas é papel mentindo: `tabindex` rotativo (um
ponto de parada no Tab, no selecionado ou no primeiro) e setas que **escolhem**, não só movem o
foco — que é o comportamento do papel e evita o estado "focado mas não marcado", indistinguível de
nada ter acontecido para quem usa leitor de tela.

O mesmo tratamento foi aplicado ao grupo de **emojis** do `CustomerSatisfaction.vue`, que tinha o
mesmo desenho. Lá havia um detalhe a mais: `@apply outline-none` apagava o anel de foco — num
controle que agora é `radiogroup`, isso deixaria quem navega por teclado sem saber onde está. O
anel voltou, vindo dos tokens da inbox.

### 2.4 `ChatCard` — o teto de 3, e por que ele é do consumidor

O corte é no componente, não no servidor, de propósito: o servidor pode mandar quantas ações
quiser (outros canais renderizam o mesmo payload com outras regras); quem limita é quem desenha.
Cortar aqui também significa que **uma automação mal configurada não deforma a bolha do
visitante** — o card é 224 px dentro de um painel de 400, e com quatro ações empilhadas a decisão
deixa de ser escolha e vira lista para ler.

Aproveitei uma violação vizinha que estava à mão: o `<img>` do card não tinha `alt` e renderizava
mesmo sem `src`. Agora é decorativo (`alt=""` + `aria-hidden`) — o título e a descrição logo abaixo
dizem a mesma coisa em texto, e sem `alt` o leitor de tela lia a URL do arquivo.

### 2.5 Mecanismo — e o que jsdom NÃO pode provar

| Mecanismo | Asserções | O que prova |
|---|---|---|
| `shared/components/specs/csatAccessibility.spec.js` | **25** | papéis, `aria-checked`, rótulos traduzidos, `tabindex` rotativo, setas, teto de 3 |
| `shared/components/specs/browser/csat-target-size.check.mjs` | **6** | **44×44 medido em Chromium**, com valor computado |

O alvo de 44×44 **não pode** ser provado em jsdom: ele não faz layout e devolve `0×0` para tudo —
um teste de tamanho lá fica verde com o defeito vivo. O verificador segue o padrão que o **1.06**
deixou: compila as utilities do Tailwind de verdade, extrai as classes **dos próprios SFCs** (não
escreve fixture) e pergunta ao motor.

E ele mede um modo de falha que só o navegador revela: **`min-width`/`min-height` não fazem nada em
`display: inline`**. Se alguém trocar o `inline-flex` por um utilitário que volte a `inline`, o
alvo desmancha em silêncio e o teste de marcação continua passando. Medido:

```
  ok   estrela: alvo renderizado >= 44x44 (SC 2.5.8)      medido 44x44px
  ok   estrela: display honra min-width/min-height        display computado = flex
  ok   emoji:   alvo renderizado >= 44x44 (SC 2.5.8)      medido 44x44px
  ok   emoji:   display honra min-width/min-height        display computado = flex
  6/6 asserções passaram
```

**Vermelho provado restaurando os componentes originais no lugar**, um por um:

```
StarRating + CustomerSatisfaction originais → Tests  10 failed | 15 passed (25)
ChatCard original                            → 4 failures adicionais
csat-target-size.check.mjs                   → "FALHA: nao localizei as classes nos SFCs"
```

O vermelho do verificador de navegador é de **extração**, e é o desejável: sem a classe no SFC ele
se recusa a medir, em vez de medir uma fixture própria e dar verde.

### 2.6 O que falta do 4.10 — lista nomeada, com o bloco que destrava cada item

O coordenador pediu esta lista no formato que a trilha do 3.19 usou. **PARCIAL com pendência
nomeada vale; sem lista vira dívida invisível.**

| # | Item do aceite | Estado | Destrava em | Por que não é meu |
|---|---|---|---|---|
| 1 | `role="radiogroup"` com rótulo textual por opção | 🟢 **ENTREGUE** | — | — |
| 2 | alvos **44×44** | 🟢 **ENTREGUE** (medido em Chromium) | — | — |
| 3 | máximo **3 botões** por card | 🟢 **ENTREGUE** | — | — |
| 4 | **CSAT nunca antes do encerramento** | 🔴 **ABERTO** | **backend** — quem cria a mensagem de CSAT é o servidor | O componente não recebe sinal de encerramento. Esconder no widget um CSAT que o servidor mandou é tratar sintoma: a mensagem continua no histórico e no relatório |
| 5 | **polegar para IA** (novo modo de exibição) | 🔴 **ABERTO** | **backend** + `shared/constants/messages.js` | `CSAT_DISPLAY_TYPES` hoje tem só `emoji` e `star`. É constante compartilhada com o dashboard **e** com o backend que grava o tipo; criar o valor só no consumidor é a assimetria que a paridade **0.6** existe para pegar |

**Nenhum dos dois é trabalho de front escondido atrás de uma decisão de produto** — os dois exigem
que alguém do lado do servidor decida e grave. Enquanto isso não existir, o widget não tem o que
consumir.

### 2.7 O que NÃO foi entregue deste bloco, e está declarado

O título do bloco tem duas metades. A **primeira** (CSAT acessível, alvos, teto de 3) está
entregue e medida. Da segunda, dois itens ficam **abertos**:

1. **"nunca antes do encerramento"** — o widget não decide *quando* a mensagem de CSAT é criada;
   quem cria é o servidor. O componente não tem sinal de encerramento para consultar. Fazer o
   widget esconder um CSAT que o servidor mandou seria tratar sintoma. **É trabalho de backend, e
   não está no meu worktree.**
2. **"polegar para IA"** — exige um `CSAT_DISPLAY_TYPES` novo (hoje só `emoji` e `star`), que é
   constante compartilhada com o dashboard **e** com o backend que grava o tipo. Criar o valor só
   do lado do consumidor produziria exatamente a assimetria que a suíte de paridade 0.6 existe
   para pegar.

Os dois estão registrados aqui em vez de improvisados. Se o coordenador quiser, viram bloco com a
ponta de backend junto.

---

## 3. Bloco 4.09 — identidade de IA ✅

**Destravou** quando o 2.06 fechou. Base remergeada (`git merge redesenho-integra`, sem conflito).

**Aceite (22-plano-widget W3.9):** *"Simulando handoff, as 3 aparecem; simulando volta à IA, as 3
também. Nunca roxo como marcador — contra o azul, colapsa para ΔE 1,8 em deuteranopia."*

### 3.1 O contrato com o servidor, lido no código

O widget precisa saber quem escreveu cada mensagem. **Não supus o campo** — fui ao serializer:
`api/v1/widget/messages/index.json.jbuilder` emite `message.sender.push_event_data`, cujo `type` é:

| `sender.type` | Origem | Atendente |
|---|---|---|
| `user` | `app/models/user.rb:153` | humano |
| `agent_bot` | `app/models/agent_bot.rb:64` | **IA** |
| `captain_assistant` | `enterprise/.../captain/assistant.rb:116` | **IA** |

Os dois últimos são exatamente o que o servidor chama de `bot_response?`
(`app/models/message.rb:411`). **Se o backend acrescentar um terceiro tipo de bot, ele entra nesta
lista** — e enquanto não entrar, cai em `unknown`, que não mente.

> **Regra do arquivo: na dúvida, NÃO diz que é IA.** Rotular de assistente o que pode ser gente —
> ou o contrário — é pior do que não rotular, porque o rótulo passa a ser ruído em vez de
> informação. Sem `sender`, com tipo desconhecido, em mensagem do visitante ou de atividade: sempre
> `unknown`, e o rótulo não aparece.

### 3.2 As três marcações, e onde cada uma vive

| # | Marcação | Onde | Como sabe |
|---|---|---|---|
| 1 | **sistema** | `AiHandoffMark.vue` ⚪ no fluxo da conversa, via `ConversationWrap` | `annotateHandoffs()` percorre o grupo **em ordem** — handoff é uma *transição*, só se sabe comparando com quem falou antes |
| 2 | **header** | `ChatHeader.vue`, rótulo persistente | `currentAttendant()` resolvido em `ViewWithHeader` e passado pronto |
| 3 | **bolha** | `AgentMessage.vue`, rótulo colado na mensagem | `attendantOf(this.message)` — da **própria** mensagem |

**A bolha deriva da própria mensagem, não herda o estado atual** — e isso é o detalhe que importa:
numa conversa que trocou de atendente, o visitante que rola para trás tem de ver quem escreveu
*aquela* mensagem. Herdar faria a conversa inteira parecer ter vindo de quem atende agora.

O **primeiro** atendente da conversa não gera marcação: ninguém foi transferido, a conversa começou
ali. Marcar isso encheria toda conversa de um aviso que não informa nada.

### 3.3 "Nunca roxo" — e por que a resposta é mais forte que trocar de cor

O aceite proíbe roxo porque, contra o azul, ele colapsa para ΔE 1,8 em deuteranopia. **Mas trocar
roxo por outra cor só empurra o problema.** O que este bloco faz é **não usar cor como sinal**:

* os dois marcadores — "entrou a equipe" e "voltou o assistente" — são pintados **iguais**;
* quem os distingue é a **frase**, diferente nos dois casos;
* o texto é lido por leitor de tela, por quem não distingue cor e por quem está no sol.

O verificador em Chromium mede as duas coisas: que nenhum é roxo, **e que os dois têm a mesma cor
computada** — se alguém um dia colorir um de verde e o outro de vermelho "para ajudar", o teste
reprova, porque isso recria a dependência de cor que o aceite ataca.

### 3.4 O cabeçalho e a cor da marca

O coordenador avisou: o header é pintado com a cor da marca, então cravar cor quebra toda inbox que
não usa o verde padrão. O rótulo usa `var(--w-on-brand, #ffffff)` — a decisão de contraste que o
servidor já calculou por luminância (bloco 1.02). Há teste que lê o arquivo e exige o token.

> **Dívida vizinha, registrada e NÃO tocada:** o resto do cabeçalho (`title`, ícone de voltar,
> ponto de online) usa `text-white` **cravado**. Numa inbox de marca clara, esses elementos ficam
> ilegíveis — meu rótulo estaria certo e a linha de cima errada. **Não é do 4.09** e não o
> reescrevi; fica anotado para quem cuidar do cabeçalho.

### 3.5 `aria-busy` no streaming

`role="log"` já existia (bloco 1.06). Acrescentei `aria-busy`, **sempre presente**, alternando
`true`/`false`. Atributo ausente e `false` não são a mesma coisa para leitor de tela: o primeiro é
indefinido, o segundo **afirma** que a região está estável.

### 3.6 Mecanismo e resultado real

| Arquivo | Asserções | Motor |
|---|---|---|
| `widget/helpers/specs/aiIdentity.spec.js` | **23** | vitest (regra pura) |
| `widget/components/specs/aiHandoff.spec.js` | **17** | vitest (as 3 marcações montadas) |
| `widget/components/specs/browser/handoff-mark-color.check.mjs` | **9** | **Chromium**, claro **e** escuro |

**Vermelho provado restaurando os quatro componentes originais no lugar** — as marcações somem, o
header não tem rótulo, e o teste do token acusa `'<script setup>\nimport { toRef } from…' to contain
'var(--w-on-brand'`.

### 3.7 Duas fraquezas do MEU mecanismo, achadas por sabotagem

Sabotar em vez de só rodar e ver verde encontrou dois buracos que eu mesmo tinha aberto:

**1. A medição não estava medindo.** A primeira versão do verificador não carregava os valores dos
tokens. `text-n-slate-11` compila para `color: rgb(var(--slate-11) / …)`; com `--slate-11`
indefinido a função inteira é inválida e o Chromium devolve **preto herdado**. O check dava 4/4 —
**e teria dado 4/4 igual se a classe fosse roxa**. Corrigido lendo os mixins de
`_tokens_values.scss`, e há agora uma asserção que **reprova se a cor vier preto puro**, porque
preto puro ali é sinal de fixture quebrado, não de aprovação.

**2. Um `color:` cru escapava.** O verificador extraía só o `@apply`. Sabotando com
`color: #7c3aed` escrito direto na folha, ele não via. Agora leva o bloco `&__texto` **inteiro** —
utilitárias e declarações. Re-sabotado: `rgb(124, 58, 237)` → FAIL nos dois marcadores e nos dois
temas.

### 3.8 Um achado sobre a paleta deste fork

A primeira versão do verificador proibia `n-iris` pelo nome, junto de `purple`/`violet`/`indigo`.
**Está errado neste fork:** medido em `_tokens_values.scss`, `--iris-9: 45 196 111` — que é o
`#2dc46f`, **o verde da marca**. A paleta "iris" foi rebrandeada e o nome herdado do Radix já não
descreve o que ela é. Proibi-la barraria uma cor da casa e daria falso positivo. **Quem decide se há
roxo é a medição, não o nome da classe** — e isso está escrito no verificador.

## 4. Números e estado final

| Suíte | Arquivos | Testes | Estado |
|---|---|---|---|
| widget + shared + **dashboard** (R21) | **520** | **5480** | verde |

Mecanismos acrescentados por esta trilha:

| Arquivo | Asserções | Motor |
|---|---|---|
| `widget/helpers/specs/preChatFieldRules.spec.js` | 44 | vitest |
| `widget/components/PreChat/specs/Form.conditional.spec.js` | 17 | vitest (componente montado) |
| `shared/components/specs/csatAccessibility.spec.js` | 25 | vitest |
| `shared/components/specs/browser/csat-target-size.check.mjs` | 6 | **Chromium real** |
| **total** | **92** | |

i18n: **18 chaves novas**, todas em `pt_BR` **e** `en`, paridade conferida por teste —
13 em `PRE_CHAT_FORM` (12 `VALIDATION` + `CONTINUE`) e 5 + 5 + 2 em `CSAT`.

**Nenhum snapshot foi tocado.** Os 20 do widget continuam intactos — nada nesta trilha muda
pixel do que eles cobrem: 3.15 acrescenta comportamento condicional (o default renderiza como
antes) e 4.10 cresce área clicável sem mudar o tamanho do ícone.

### 4.1 Commits

| Commit | Bloco |
|---|---|
| `87d1fd6333` | 3.15 |
| `d4c71439d8` | 4.10 (**parcial** — pendências nomeadas na §2.6) |
| `a06cd8af7b` | 4.09 |

### 4.2 Números depois do 4.09

| Suíte | Arquivos | Testes | Estado |
|---|---|---|---|
| widget + shared + dashboard | **528** | **5643** | 5641 verdes, **2 falhas pré-existentes** |

**As 2 falhas não são desta trilha.** São `triggers.enabled` e `triggers.triggers` em
`dashboard/.../widget/specs/inboxWidgetI18n.spec.js`, introduzido pela trilha do **3.08**
(`edd4844e5c`) e trazido no merge da integra. Conferido do jeito que não deixa dúvida: guardei
minhas mudanças com `git stash -u` e rodei o spec — **falham igual**. Não toquei no bundle de i18n
do dashboard e **não consertei chave alheia**.

Mecanismos acrescentados no 4.09:

| Arquivo | Asserções | Motor |
|---|---|---|
| `widget/helpers/specs/aiIdentity.spec.js` | 24 | vitest |
| `widget/components/specs/aiHandoff.spec.js` | 17 | vitest (montado) |
| `widget/components/specs/browser/handoff-mark-color.check.mjs` | 9 | **Chromium**, claro e escuro |

**Total da trilha: 132 asserções** (92 dos dois primeiros blocos + 40 do 4.09), em 9 arquivos.

i18n: **27 chaves novas** ao todo, todas em `pt_BR` **e** `en` — 13 em `PRE_CHAT_FORM`, 5+5+2 em
`CSAT`, 9 em `AI_IDENTITY`, todas com paridade conferida por teste e **sem emoji dentro do texto**.

### 4.3 Uma coisa para o coordenador decidir

1. **4.10 não está inteiro** e está marcado como tal: as duas metades abertas ("nunca antes do
   encerramento" e "polegar para IA") precisam de ponta de backend, e criá-las só do lado do
   consumidor é a assimetria que a paridade 0.6 existe para pegar. Não improvisei.
2. **Dívida vizinha no cabeçalho, registrada e não tocada:** `title`, ícone de voltar e ponto de
   online usam `text-white` **cravado**. Numa inbox de marca clara ficam ilegíveis — o meu rótulo
   estaria certo e a linha de cima errada. Não é do 4.09.

### 4.3 Uma observação de método

Duas vezes nesta trilha um **fixture meu** estava errado e o teste me corrigiu: `'asdfgh'` não é
lixo pela regra do 3.13 (tem vogal), e o campo de mensagem **entra** na última etapa por desenho.
Nos dois casos a correção foi ler a regra real e ajustar o teste — não afrouxar a asserção. Um
fixture que passa por engano mede a suposição de quem escreveu, não o código.

---

## 5. Recado ao coordenador (o `worker_done` não pôde ser enviado)

`orca orchestration send --type worker_done` respondeu **`Dispatch ctx_7afb1536c78b capability is
revoked`** — o contexto de dispatch é o da tarefa anterior (trilha `o2-config-resto`), e esta
realocação chegou por conversa direta, sem dispatch novo. Seguindo a regra do preâmbulo — *"se o
relay estiver sem coordenador, escreva tudo no relatório assim mesmo, inclusive o que você diria
por mensagem"* — fica aqui o que iria na mensagem.

**Resultado:** 3.15 **fechado** (`87d1fd6333`), 4.10 **parcial** (`d4c71439d8`), 4.09 **bloqueado
em 2.06** e não tocado.

**O contrato do pré-chat foi lido contra o CÓDIGO, não contra o relatório.** As sete chaves de
campo batem com o schema Ruby do 3.12, uma a uma — **nenhuma divergência a escalar**. A única
coisa que declaro é que `position`, que o produtor grava, **o widget não consome**: ordenar campo é
mudança de layout e não está no título do bloco.

**As três formas de `show_if` estão decididas e testadas** (§1.2): ausente, `null` e objeto vazio
deixam o campo **visível**, e a mesma resposta vale para operador desconhecido, para
`is`/`is_not`/`contains` sem `value`, e para condição apontando a campo inexistente. **Falha
aberta, por assimetria de dano.**

**Dois achados que mudam o que se pode assumir da base:**

1. Os três arquivos do 4.10 estão em `shared/`, não em `widget/components/` — **R21 se aplicou**, e
   a suíte do dashboard entrou no gate (520 arquivos / 5480 testes, verde).
2. `CSAT_RATINGS[].translationKey` apontava para chaves que existiam **só no bundle do dashboard**,
   num componente renderizado nos dois lados. Mesma família da paridade 0.6: nada quebrava porque
   ninguém usava o rótulo. Corrigido antes de usar.

**Um defeito de junção fechado no 3.15:** os quatro campos padrão saíam de `formValues` **direto**,
sem passar por `enabledPreChatFields` — campo preenchido e depois escondido pela troca de resposta
do gatilho ainda viajava com o valor velho.

**O que NÃO improvisei:** as duas metades abertas do 4.10 precisam de ponta de backend, e criá-las
só do lado do consumidor produz exatamente a assimetria que a paridade 0.6 existe para pegar.

**Higiene:** nenhum snapshot tocado; `--no-verify` não foi usado em momento nenhum; o worktree não
existia e foi criado com `git worktree add` a partir da `redesenho-integra`, com `node_modules`
próprio em vez de apontar para o de outra trilha.
