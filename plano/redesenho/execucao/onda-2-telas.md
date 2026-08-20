# Onda 2 — trilha TELAS (blocos 3.06 a 3.11)

Worktree: `/home/chatwoot/chatwoot-o2-config-telas` · branch `o2-config-telas` · base `c06ba1824e`
Executor: terminal `term_a0408847` · task `task_cc99fe621bb5`

Este arquivo é escrito **conforme avanço**, não no fim. Cada bloco tem: o que a base tinha, o que
foi feito, o mecanismo que executa o aceite, e o resultado REAL do mecanismo.

---

## 0. O estado da base, medido antes de escrever a primeira linha

A instrução do dispatch diz que a base é "a branch integrada da Onda 0 e da Onda 1". **Não é o que
o disco mostra**, e isso muda o que esta trilha consegue fechar sozinha. Medição:

```
$ git log --oneline -1            → c06ba1824e (test(manual): pagina de live chat…)
$ git worktree list               → o1-widget 7d3f593cd5 · o1-backend ea32db14b4
                                    o1-bridge 6bd3604db0 · o1-origem 76286ea99a
                                    o2-config-backend c06ba1824e  ← mesma base que eu
```

`o2-config-telas` aponta para **o mesmo commit** que `o2-config-backend`: a Onda 1 está em quatro
branches ainda **não** integrados, e a trilha de backend da Onda 2 ainda não commitou.

Consequência verificada arquivo a arquivo (não inferida):

| Dependência declarada na tabela mestra | Onde deveria estar | Existe na minha base? |
|---|---|---|
| **3.01** — as 4 chaves em `additional_attributes` + strong params | `app/models/inbox.rb:50`, `inboxes_controller.rb` | **não** — `store_accessor` só tem `pin_mode, pinned_conversation_ids` |
| **3.03** — `WidgetProfile.resolve` | `app/services/widget_profile.rb` | **não** — arquivo inexistente |
| **3.04** — as 4 chaves nos 2 montadores | `show.html.erb`, `configs/create.json.jbuilder` | **não** |
| **3.18** — schema de `widget_appearance` + precedência + saída do `localStorage` | schema ⚪, `inbox.rb` | **não** |
| **1.01** — folha de tokens do widget | `widget/assets/scss/_tokens.scss` | **não** — arquivo inexistente |
| **1.02** — derivação dos 7 tokens no servidor | `app/services/widget_tokens.rb` | **não** |

**Decisão desta trilha, declarada em vez de silenciada:** não entrego zero. O contrato de dados que
falta está **escrito** e é preciso — nomes de chave, enums, limites e a derivação numérica estão no
`PLANO-MESTRE §2.2` (3.01, 3.18, 3.20), no `23-plano-config-dashboard §B.0.2/§B.2` e nos arquivos de
referência `plano/redesenho/shared/{tokens.css,on-brand.js}`. Escrevo o front contra **esse**
contrato, com o mecanismo de aceite que a camada de front consegue executar sozinha, e marco em cada
bloco, nominalmente, o aceite que **só** fecha depois da integração com a trilha de backend.
Nenhum aceite numérico foi afrouxado; os que não são executáveis aqui estão listados como
**bloqueados**, com o bloco que os destrava.

---

## Bloco 3.06 — o rascunho, a barra de salvar e a confirmação ao sair (T1.1, T1.2)

Commit local `a7b954408c`. Arquivos novos, todos em `settings/inbox/widget/` (pasta que o upstream
não tem — a defesa de merge da §B.0.1):

| Arquivo | O que é |
|---|---|
| `composables/widgetConfigFields.js` | o mapa canônico dos campos que as 4 telas editam, com `scope` (`inbox`/`channel`/`additional`) e os defaults de fábrica de `widget_appearance`, `widget_triggers`, `widget_tracking` e `widget_profile` |
| `composables/useInboxWidgetConfig.js` | carga, rascunho, `isDirty`, `dirtyFields`, payload mínimo, `discard()` e `save()` |
| `composables/useUnsavedChangesGuard.js` | as três saídas que levam o rascunho embora |
| `composables/widgetFieldLabels.js` | chave lógica → chave de i18n, e a lista `KNOWN_FIELD_PATHS` que torna a cobertura verificável |
| `WidgetSaveBar.vue` | "N alterações não salvas" · Descartar · Salvar |
| `WidgetUnsavedChangesDialog.vue` | o aviso que **lista nominalmente** o que se perde |

**Duas decisões que não são estilo, e a razão medida de cada uma:**

1. **O campo de grupo viaja inteiro no `PATCH`.** `inboxes_controller.rb` (`update`) faz
   `(@inbox.additional_attributes || {}).merge(...)` — merge de **primeiro nível**. Mandar
   `widget_appearance: { position: 'left' }` substituiria o objeto e apagaria tema, offsets e o
   resto. O rascunho guarda o objeto completo e o payload manda o objeto completo; o merge raso
   então preserva as **outras três** chaves, que é exatamente o que a arbitragem A1 comprou.
2. **A confirmação ao sair cobre três saídas, não uma.** Trocar de aba dentro de `Settings.vue`
   **não passa pelo router** (`updateRouteWithoutRefresh` usa `window.history.replaceState`,
   `Settings.vue:622-634`) — um guard de rota sozinho não veria essa saída. Por isso o composable
   expõe `requestLeave(acao)` para a troca de aba, registra `onBeforeRouteLeave` **na forma que
   devolve promessa** (chamar `next()` duas vezes é erro no vue-router) e prende `beforeunload`.

### O mecanismo, e o que ele mediu

`npx vitest run …/inbox/widget/` — **66 testes** no fecho do bloco. Os que executam o aceite:

| Aceite do bloco | Teste |
|---|---|
| "Editar e sair sem salvar não suja o store" | `editar NÃO suja o objeto do store (D2)` — lê o objeto do store depois de editar dois campos |
| "'Descartar' restaura" | `Descartar restaura o gravado` |
| "a barra anuncia 'N alterações não salvas'" | 3 testes: singular, plural e `en`, comparando o **texto renderizado** |

**A força dos testes foi medida, não afirmada.** Injetei duas mutações no composable — escrever no
objeto do store, e mandar só o subcampo alterado do grupo — e rodei:

```
× editar NÃO suja o objeto do store (D2)
× salva o mínimo que mudou, com o grupo inteiro e formData: false
× buildPayload > manda o grupo INTEIRO — o merge do servidor é raso
  Tests  3 failed | 14 passed (17)
```

Mutações revertidas (`grep -c MUTACAO` → 0) e a suíte voltou a 66/66.

### O que este bloco **não** fecha, e por quê

O aceite de persistência de verdade depende de **3.01** — sem as quatro chaves no strong params, o
`PATCH` que o composable monta é aceito pelo controller mas descartado no `permit`. O composable já
manda no formato que 3.01 declara.

---

## Bloco 3.08 — o medidor de contraste (T1.6, T1.7, T1.8)

Arquivos: `composables/useContrast.js`, `appearance/ContrastReadout.vue`,
`appearance/BrandColorField.vue`, `scripts/gerar-fixture-tokens-marca.mjs` e
`spec/fixtures/widget_brand_tokens.json`.

### O aceite numérico, e ele fechou nos números exatos

```
✓ #2DC46F como texto em fundo claro da 2,27:1 e REPROVA
    ratio = 2,273443…   →  toBeCloseTo(2.2734, 2)   ·  passes = false
✓ #009CE0 escolhe PRETO para o texto sobre a marca, com 6,83:1
    ratio = 6,831750…   →  toBeCloseTo(6.8318, 2)   ·  a escolha errada (branco) daria 3,07:1
```

A asserção é `toBeCloseTo(x, 2)` como o plano exige — igualdade exata em duas casas falharia por
0,02 numa implementação **correta**, e foi o que quase aconteceu nesta execução.

### As 20 cores: a fixture não foi escrita à mão nem gerada por quem ela verifica

Este era o ponto onde o teste podia virar tautologia: se a tabela de referência saísse da mesma
função que o teste verifica, ele provaria apenas que a função concorda consigo mesma.

`scripts/gerar-fixture-tokens-marca.mjs` mede no **Chromium** (Playwright), lendo o **pixel
renderizado** de um canvas para cada expressão `oklch(from … min(l,.51) c h)` e
`color-mix(in oklab, …)` — isto é, a implementação de referência da spec CSS Color 4, que é o que o
`tokens.css` da Task 21 escreve. São 20 cores × 2 temas × 7 tokens = **280 valores**.

Resultado do cruzamento com `useContrast.js`:

```
279 de 280 valores batem EXATAMENTE (mesmo hex)
  1 diverge: #7c3aed, tema claro, --w-brand-readable  →  nós #732de2, Chromium #742de2
```

A divergência é de **1/255 num canal**: o canal R cai em **115,4985**, a 0,0015 do meio do intervalo
de arredondamento. Medida também em float32 (115,49854), o que descarta precisão de ponto flutuante
como causa. Ela está **declarada no teste**, nominalmente, e o teste falha se aparecer uma **segunda**
divergência ou se alguma passar de 1/255 — em vez de ser escondida sob um `toBeCloseTo` generoso.

### O que a tela mostra

Os quatro pares da §B.2.3, cada um com a razão da cor crua, o veredito e — quando reprova — a cor
ajustada com a razão dela. E a frase que explica, com os dois números e as duas cores:

> Em fundo claro, #2DC46F como texto dá 2,27:1 — abaixo do mínimo legível. Links e rótulos usarão
> #00802F (5,09:1). O preenchimento continua #2DC46F.

O medidor **informa e nunca impede o salvamento**, e nunca usa `opacity` para simular estado
(regra C10: opacidade muda a luminância e invalidaria a própria conta exibida).

**Nenhuma das 20 cores fica sem saída:** um teste percorre os 4 pares das 20 cores e exige que o
valor **resolvido** (depois do ajuste) passe no alvo — 4,5:1 para texto, 3:1 para borda.

### O que este bloco não fecha

O cruzamento com **1.02** (`WidgetTokens` em Ruby) — o serviço não existe nesta base. A fixture foi
posta em `spec/fixtures/widget_brand_tokens.json` justamente para 1.02 consumir do lado Ruby: quando
ele existir, o teste dele lê o mesmo arquivo e o cruzamento fecha nas duas pontas.

---

## A base integrada chegou no meio do caminho — e ela mudou o 3.08

Depois de 3.06 e 3.08 commitados, o coordenador avisou que existe `redesenho-integra` com a Onda 0
inteira, quase toda a Onda 1 e as três trilhas de config. Mergeei (`9218df1a37`) e a primeira coisa
que fiz foi conferir o que isso mudava no que eu já tinha escrito. Mudou, e muito:

**`WidgetTokens` (bloco 1.02) não deriva a marca como o `shared/tokens.css` da Task 21.** Medido,
lendo o arquivo:

| | `plano/redesenho/shared/tokens.css` (a fundação dos mockups) | `app/services/widget_tokens.rb` (o que roda) |
|---|---|---|
| marca como texto | `oklch(from … min(l, 0.51) c h)` | mistura em **RGB**, passos de 5%, até cruzar 4,5:1 |
| superfície escura | `#17171a` | **`#121213`** |
| hover / pressed | 8% / 14% em OKLab | **10% / 18%** em RGB |
| nomes | `--w-brand-border`, `--w-brand-subtle`, `--w-focus-ring` | `--w-brand-active`, `--w-brand-readable-dark`, `--w-focus-ring-color` |

O plano decide esse empate de forma explícita (§B.2.3): **"a derivação canônica é a do servidor"**.
Então quem estava errado era a tela, não o servidor — e uma tela que exibe 5,09:1 para uma cor que
o widget vai renderizar em 4,83:1 é exatamente o "a tela mente" que o bloco existe para impedir.

Correção aplicada (commit `53ab9ae426`):

- `useContrast.js` passou a reproduzir `WidgetTokens`, com os mesmos nomes de token;
- a fixture das 20 cores deixou de ser medida no Chromium e passou a ser **gerada pelo próprio
  servidor** — `scripts/gerar-fixture-tokens-marca.rb` instancia `WidgetTokens`. O gerador `.mjs` foi
  removido para não deixar duas verdades no repositório;
- resultado: **20 cores × 7 tokens batem hex a hex, sem exceção nenhuma**. A divergência de 1/255 que
  o cruzamento com o Chromium tinha desapareceu junto com a fonte errada;
- os dois números do aceite não mudaram (2,27:1 e 6,83:1). Mudou a cor ajustada que a tela oferece:
  **#1D824A (4,83:1)**, que é a que o widget realmente usa.

Registro para o coordenador: se alguém quiser a derivação em OKLCH do `tokens.css`, a mudança é no
**servidor** (1.02) e a tela acompanha por construção — o spec cruza os dois lados e falha sozinho.

---

## Bloco 3.10 — o preview honesto (T1.11, T1.12, T1.13)

Commit `ce5b47aa6e`.

### D4 — as ~74 custom properties literais

O `<style scoped>` do preview trazia uma cópia da paleta do widget. Duas cópias da mesma paleta
divergem sem ninguém perceber, porque quem muda o widget não tem motivo para abrir o preview.

O que foi feito, e por que não foi um simples "apagar":

1. Os quatro blocos de declaração saíram de `widget/assets/scss/_tokens.scss` para
   `_tokens_values.scss`, como **mixins** (`widget-palette-light`, `widget-palette-dark`,
   `widget-brand-light`, `widget-brand-dark`). O `_tokens.scss` continua sendo quem aplica em
   `:root`/`.dark`.
2. **O CSS do widget é idêntico byte a byte** — compilei os dois com `sass` e comparei:
   `5924 bytes` antes, `5924 bytes` depois, `diff` vazio. É o que garante que os 16 snapshots do
   widget não se movem por causa desta refatoração.
3. O preview aplica os **mesmos mixins** sob `.wp-theme-light` / `.wp-theme-dark`. Em **classe**,
   nunca em `:root`: `:root` ali repintaria o dashboard inteiro com a paleta do widget.

### O tema do preview era o tema do painel

O escuro vinha de `.dark .widget-wrapper` — a classe que o dashboard põe no `<html>`. O cliente não
conseguia ver o widget escuro sem trocar o próprio painel. Agora há toggle próprio (e outro para
celular), e todos os `dark:` que dependiam do tema global saíram dos três componentes filhos: a
variável já muda de valor com a classe do wrapper, que é como o widget real funciona.

### A cor deixou de ser a cor crua

`background: props.color` virou os tokens derivados. Junto com isso morreu o `text-white` cravado no
balão do visitante (`WidgetBody.vue`) — o preview reproduzia **o próprio defeito** que esta onda
conserta: texto branco sobre o verde da marca, 2,27:1. Agora é `bg-w-brand text-w-on-brand`, e o
`WidgetBody` deixou de receber `config` (era por ali que uma cor que o widget não usa entrava).

### O mecanismo

13 testes. O aceite literal do bloco é um deles; os outros existem porque **um grep vazio com valores
errados passaria**:

| Pergunta | Como é respondida | Resultado |
|---|---|---|
| sobrou cópia? | grep por `--slate-`/`--solid-`/`--iris-`/… em `widget-preview/` | vazio |
| o preview aplica os mesmos valores? | compila os **dois** SCSS com `sass` e compara declaração a declaração | `.wp-theme-light` ≡ `:root` do widget · `.wp-theme-dark` ≡ `.dark` do widget |
| o `@import` do SFC resolve mesmo? | compila com `url` da origem, como o Vite resolve | passa |
| o preview declara em `:root`? | regex no CSS compilado, sem comentários | não |
| o toggle é independente do dashboard? | liga o toggle **sem** `.dark` no `<html>`; e põe `.dark` no `<html>` com o toggle desligado | escuro no 1º, claro no 2º |
| os tokens derivados chegam? | lê o `style` do wrapper | `--w-on-brand: #000000`, `--w-brand-readable: #1d824a` |

---

## Bloco 3.07 — o seletor de perfil (T1.3, T1.5)

Commit `db5269ab68`. Arquivos: `WidgetProfileSelector.vue`, `WidgetProfileSwitchDialog.vue`,
`composables/useProfileVisibility.js`, e a pergunta em `channels/Website.vue`.

**O que o bloco protege.** Trocar o perfil **propõe**; nunca reescreve. O diálogo lista, com caixa
marcável, cada valor que mudaria — e grava só o que for marcado. O que já está do jeito que o novo
perfil propõe **não entra na lista**: mostrar "ligar o CSAT" com o CSAT já ligado treina o
administrador a clicar sem ler.

E diz, por escrito, o que a arbitragem A3 garante: *"Nada é apagado. Toda configuração do perfil
anterior fica no banco, inerte, e volta se você voltar o perfil."*

**A regra dura da §B.1.3 virou código:** perfil **esconde**, não remove. `hiddenSectionsFor` lista o
que some, e `showOtherProfile` traz tudo de volta pelo link "mostrar configurações de {outro
perfil}". Seção que não está na matriz aparece nos dois perfis — a coluna "sempre" é maior do que
parece, e o default tem de ser ela.

**No wizard:** a pergunta entra sem default pré-selecionado e o botão de criar espera a resposta.
Radio já marcado é o mesmo que não perguntar.

**Mecanismo:** 20 testes. Os que executam o aceite: o diálogo conferido **string a string** em pt-BR
(as quatro propostas e a frase do "nada é apagado"), desmarcar um item o tira do `apply`, cancelar
não emite nada, e um teste que prova que **calcular a proposta não muta** o objeto de valores
gravados.

**Bloqueado até 3.01/3.03:** gravar o perfil de fato (strong params) e as propostas de CSAT e
continuidade, que dependem do `WidgetProfile.resolve`.

---

## Bloco 3.09 — a tela de aparência (T1.9, T1.10, T1.15, T1.16)

Commit `20088e67df`.

### Os sítios gastos em `Settings.vue`, declarados antes de editar

A §12.4 diz que o bloco 3.09 "parte de zero orçamento e precisa declarar os seus sítios antes de
editar". São **seis**, e o diff é de +19 linhas, sem alterar o sentido de nenhuma linha existente:

| # | Sítio | Por quê |
|---|---|---|
| 1 | `import AppearancePage` | — |
| 2 | registro em `components` | — |
| 3 | a aba nova no array `tabs`, só para inbox de site | é o roteador de abas |
| 4 | o `v-if="selectedTabKey === 'appearance'"` no template | — |
| 5 | `onTabChange` passa a consultar a tela antes de trocar | **a troca de aba não passa pelo router** (`history.replaceState`), então nenhum guard de rota a vê; sem isto, sair da aba com dez campos pendentes os perde em silêncio |
| 6 | o `ref="appearancePage"` que dá acesso a esse guard | — |

O sítio 5 é o único que não é encanamento, e ele existe porque medi o caminho: `updateRouteWithoutRefresh`
troca a URL sem navegar.

### O que a tela resolve

Tema, posição, offsets, formato e texto do lançador viviam no `localStorage` do navegador do
administrador (**D1**). Admin A configurava "esquerda"; admin B, em outro navegador, via "direita".
Agora isso é configuração da inbox, em `widget_appearance`, e o `PATCH` leva o objeto inteiro.

E há o aviso de override: quando o site do cliente define o campo em `chatwootSettings`, a tela
**nomeia o campo e avisa** em vez de mentir. Sem a chave de override o aviso não aparece — ausência
de dado nunca vira aviso falso.

### O mecanismo, e o que ele mede

11 testes na tela, 9 nos campos:

| Aceite | Teste | Resultado |
|---|---|---|
| posição vem da inbox, não do `localStorage` | lê o radio marcado com `widget_appearance.position = 'left'` e checa que o `localStorage` está vazio | passa |
| mudar para "esquerda" e salvar | confere o `PATCH`: `additional_attributes.widget_appearance.position === 'left'` | passa |
| offset fora da faixa | digita 500 → o campo mostra 120 | passa |
| override visível | com `widget_appearance_overrides: ['position','theme']`, o banner nomeia "Posição do lançador" e "Modo de tema" | passa |
| preview segue o rascunho | digita no título → o preview muda e `inbox.welcome_title` **não** | passa |
| sair da aba com pendência | `requestLeave` devolve `false`, o diálogo abre e **lista** "Posição do lançador" | passa |

**O que NÃO fecha aqui, e é honesto dizer:** "salvar e abrir em outro navegador e outro admin"
depende de **3.01** (strong params) e **3.18** (schema). Hoje o `PATCH` sai correto e o servidor
descarta a chave no `permit`. O teste que tenho executa a metade que é minha — que o payload sai
certo —, e a outra metade fecha na integração.

---

## Bloco 3.11 — o snippet (T1.14)

Commit `ee7cdb09ce`.

**O defeito, e ele chegava ao site do cliente.** O preview cortava o script do servidor no **byte
13** (`script.substring(0, 13)`) e injetava no buraco
`t('INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS')` — uma chave de **tradução** cujo conteúdo era
JavaScript executável: `window.chatwootSettings = {options};`. Duas formas de quebrar: um tradutor
mexendo na planilha de tradução quebrava o código que o cliente cola no site, em **57 idiomas**; e o
corte por posição fixa quebrava sozinho se o servidor mudasse um espaço no começo do script.

**A correção.** O snippet exibido passa a ser exatamente o que o servidor escreve. As opções que
aquele bloco injetava não precisam mais viajar no snippet: moram em `widget_appearance` e o servidor
as entrega no boot. `chatwootSettings` continua valendo como override deliberado do site — e quando
existe, a tela avisa (3.09).

A chave saiu dos **57 locales** — só ela, uma chave por arquivo, sem reformatação: `git diff
--numstat` dá 57 adições e 114 remoções, que é exatamente a linha da chave mais a vírgula da linha
anterior.

**O mecanismo que impede a volta** é o que fecha o aceite ("tradutor não consegue mais quebrar o
snippet do cliente"): `i18n/specs/noExecutableJs.spec.js` varre **todas** as strings de **todos** os
idiomas e falha se alguma tiver atribuição em `window`/`document`, chamada de DOM, chamada do
`chatwootSDK` ou função anônima. Os padrões são de código, não de prosa — uma frase pode falar de
"janela" ou pedir para colar uma tag `<script>`, e isso é texto legítimo.

**Vermelho conferido:** reintroduzi a chave em `pt_BR` e a suíte derrubou **3 testes**, nomeando o
idioma e a chave. Chave removida de novo, verde de volta.

---

## A validação em navegador — e o que ela reprovou depois de 4.959 testes verdes

Commit `738c215de9`. Harness próprio: `spec/e2e/appearance/` (servidor Vite na **3061**, config
Playwright **próprio** — não usa nem toca as portas 3038/3999/8899 do harness do widget, que o
coordenador trancou).

A suíte JS inteira estava verde: **495 arquivos, 4.959 testes**. O navegador reprovou **quatro**
coisas, e nenhuma delas era alcançável pelo jsdom — porque jsdom não computa cor, não resolve custom
property e não aplica `!important`.

### 1. O skin do dashboard sequestrava o preview *(o mais grave)*

Medido por CDP (`CSS.getMatchedStylesForNode`) no `.widget-wrapper`, com o dashboard escuro:

```
.bg-n-solid-1            → background-color: rgb(var(--solid-1) / …)     ← o que eu queria
.dark .bg-n-solid-1      → background-color: #111b21 !important          ← o que venceu
```

`_wa-skin.scss:1840` e vizinhas forçam, no tema escuro, `.bg-n-solid-1/2/3`, `.bg-n-background` e
`[class*='text-n-slate-12|11|10|9']` com `!important`. **`!important` vence variável**: o painel do
preview ficava `#111b21` mesmo com `--solid-1: 255 255 255` corretamente herdado do meu wrapper.

Ou seja: o aceite do bloco 3.10 — *"o toggle de tema funciona independentemente do tema do
dashboard"* — **passava no vitest e falhava no Chromium**. O vitest só vê a classe trocar.

**Correção:** um namespace `wp` em `theme/colors.js`, lendo as **mesmas** custom properties do widget
(`--solid-1`, `--slate-12`…). O preview usa `bg-wp-surface`, `text-wp-text`, `bg-wp-online` — que
nenhum seletor do skin alcança. Nenhum valor de cor nasceu aí; e o grep do aceite (`--slate-`/
`--solid-` em `widget-preview/`) **continua vazio**, porque a citação do token está no arquivo de
tema, que é exatamente o lugar onde tokens viram classes.

### 2. Texto sem cor própria ficava preto no tema escuro

`1,13:1` — preto (`rgb(0,0,0)`) sobre `#0b141a`. O `body` do dashboard **não** define `color`
(conferido em `_woot.scss` e `_wa-skin.scss`): quem não declara herda o preto do navegador. A tela
passou a declarar a própria cor de texto, e assim não depende de quem a hospeda.

### 3. Quatro violações sérias/críticas de a11y que eram minhas

| `axe` | O que era | Correção |
|---|---|---|
| `button-name` | o lançador do preview, sem nome acessível | `aria-label` traduzido |
| `image-alt` | o logo do branding do preview | `alt=""` + `aria-hidden` (é decorativo) |
| `label` ×2 | `welcome-title` e `welcome-tagline` — o `<label>` do `SettingsFieldSection` **não tem `for`** (é o defeito que a §B.0.5 manda não repetir) | `aria-label`, que o `Input` repassa ao `<input>` |
| `select-name` | os dois `Select` — o componente **não repassa atributos** ao `<select>`, então `aria-label` cairia no wrapper | `<label>` envolvente com texto `sr-only` |
| `role-img-alt` | o `Avatar` ilustrativo do rodapé do preview | `aria-hidden` no wrapper |

E o `opacity-90` do branding saiu: opacidade muda a luminância e invalida o contraste calculado
(regra C10) — era ele que derrubava o "Desenvolvido por" para 2,77:1 no escuro.

### 4. O meu próprio DOM walker tinha 89 falsos positivos

Ele media contêineres (`<li>`) cujo texto mora em filhos com cor própria. Corrigido para medir só
elementos com **texto direto**. Registro porque um teste que grita errado 89 vezes é um teste que
ninguém lê na 90ª.

### O que fica em aberto, nomeado

Duas violações de contraste **não nascem nesta tela** e estão listadas uma a uma no teste (id +
seletor + razão), de modo que qualquer violação **nova** reprove:

| Componente | Medida | Por que não corrijo aqui |
|---|---|---|
| `ColorPicker` | `#2dc46f` sobre `#f0f2f5` = **2,02:1** | é componente compartilhado do dashboard; corrigir localmente seria remendo |
| `TabBar` (aba ativa) | mesma cor de marca como texto = **2,09:1** | idem |

É literalmente a doença que o medidor desta tela denuncia — **a marca usada como texto sem
ajuste** —, acontecendo dentro do próprio painel. Escalado ao coordenador.

### Resultado final da validação

```
11/11 no Chromium, nos dois temas do dashboard:
  · renderiza sem erro de console e sem chave de i18n crua      (light e dark)
  · o medidor exibe 2,27:1 e marca "ajustamos"                  (light e dark)
  · nenhum texto abaixo de 4,5:1 contra o próprio fundo         (light e dark)
  · axe-core sem violação crítica/séria                         (light e dark)
  · com o dashboard CLARO, o toggle escurece SÓ o preview       (255,255,255 → 23,23,26)
  · com o dashboard ESCURO, o preview começa claro              (255,255,255)
  · o balão do visitante: fundo #2dc46f, texto PRETO, 9,24:1
```

---

## Fecho — o que ficou pronto, o que ficou bloqueado

| Bloco | Commit | Estado |
|---|---|---|
| **3.06** | `a7b954408c` | pronto |
| **3.08** | `edd4844e5c` + `53ab9ae426` | pronto — cruzamento com o servidor fecha hex a hex em 20 cores |
| **3.10** | `ce5b47aa6e` + `738c215de9` | pronto |
| **3.07** | `db5269ab68` | pronto no front; gravar o perfil espera **3.01**, as propostas esperam **3.03** |
| **3.09** | `20088e67df` + `738c215de9` | pronto no front; a persistência ponta a ponta espera **3.01 + 3.18** |
| **3.11** | `ee7cdb09ce` | pronto |

**Suíte JS completa:** 495 arquivos, **4.959 testes**, verdes. (O runner emite 3 erros de
*source-map* do `vite-node` sob carga — `SyntaxError: Invalid regular expression … Stack overflow`
dentro de `extractSourceMap`. É infraestrutura do vitest, não código nosso: some ao rodar os mesmos
arquivos isoladamente, e o processo termina com exit 0.)

**O que a trilha de backend precisa saber:**

1. O front já manda no formato de 3.01: `additional_attributes.widget_appearance` viaja **inteiro**
   no `PATCH` (merge raso do controller), e `widget_profile` vai no create do wizard.
2. O aviso de override de 3.09 lê `additional_attributes.widget_appearance_overrides` — uma lista de
   nomes de campo. Se 3.18 escolher outro nome ou outra forma, é uma linha na tela; mas **enquanto a
   chave não existir, o aviso simplesmente não aparece** (ausência de dado não vira aviso falso).
3. `spec/fixtures/widget_brand_tokens.json` é gerado por `scripts/gerar-fixture-tokens-marca.rb` a
   partir do próprio `WidgetTokens`. Se 1.02 mudar a fórmula, regenere a fixture e o spec do
   dashboard acusa a divergência no mesmo comando.

---

## Segunda passada pela base integrada — e os bloqueios caíram

Depois do fecho acima, mergeei `redesenho-integra` de novo (`4ed230a04a`) e o terreno tinha mudado:
**3.01, 3.03 e 3.18 existem**. `app/models/concerns/widget_configurable.rb` declara as quatro chaves
com `store_accessor`, `inboxes_controller.rb:264-266` as permite, `WidgetAppearanceSchema` valida a
aparência e `app/services/widget_profile.rb` resolve o perfil.

Com o servidor no lugar, a primeira coisa foi comparar os dois lados. **Divergiam em cinco pontos**,
e cada um é uma forma de a tela mentir:

| campo | tela (antes) | servidor (3.18) | o que a tela dizia de errado |
|---|---|---|---|
| `theme` | `auto` | **`light`** | descrevia um estado que a inbox não tem |
| `offset_x` / `offset_y` | 20 | **0** | idem |
| teto do offset | 120 | **200** | recusava 150 px que o servidor aceita |
| teto do texto do lançador | 40 | **64** | inventava um limite que ninguém aplica |
| `home_intents` | não existia | `[]` | **apagaria o campo**: o objeto do grupo viaja inteiro no `PATCH`, então um rascunho que não o carrega o zera a cada salvamento que só mexeu na posição |

Corrigido em `3e320a0ece`, com o mecanismo que impede a volta:
`specs/widgetAppearanceContract.spec.js` **lê o arquivo Ruby** — `DEFAULTS`, `MAX_OFFSET`,
`MAX_LAUNCHER_TEXT`, `THEMES`, `POSITIONS`, `LAUNCHER_TYPES`, `PANEL_STYLES` — e falha nomeando o
campo que se separou. Vermelho conferido antes da correção (acusou `theme: auto` × `light`).

E `d9425919b4` fecha o outro elo: o teste lê `inboxes_controller.rb` e exige que as quatro chaves que
o mapa da tela produz estejam no `permit`. **Uma chave que a tela envia e o `permit` não conhece é
descartada em silêncio** — a tela mostra "salvo", o banco não muda, e o administrador só descobre ao
recarregar. Vermelho conferido: renomear `widget_appearance` → `widget_appearence` derruba o teste.

**Fronteira com a trilha PRE-CHAT:** eles acrescentaram `preChatEnabled` e `preChat` ao
`widgetConfigFields.js` — aditivo, no fim da lista, sem tocar no que já estava, exatamente como
combinado. Merge por união, sem conflito.

### Estado final dos aceites

| Aceite | Antes | Agora |
|---|---|---|
| 3.06 — rascunho, descartar, "N alterações" | ✅ | ✅ |
| 3.07 — diálogo lista o que muda; nada é apagado | ✅ front · gravação bloqueada | ✅ (3.01/3.03 no lugar) |
| 3.08 — 2,27:1 · 6,83:1 · 20 cores × 7 tokens | ✅ (cruzamento com 1.02) | ✅ |
| 3.09 — posição persiste; aviso de override | metade (payload) | ✅ payload + contrato com schema e `permit`; a leitura de ponta a ponta é dos specs Ruby de 3.18 |
| 3.10 — grep vazio; toggle independente | ✅ jsdom | ✅ **e no Chromium**, depois de achar o `!important` do skin |
| 3.11 — tradutor não quebra o snippet | ✅ | ✅ |

### Revalidação final no navegador, depois do alinhamento com o servidor

Rodei o Playwright de novo **depois** de mudar os defaults (o verde anterior era de antes), para não
reportar resultado velho: **11/11**, nos dois temas do dashboard. O harness foi encerrado e a porta
3061 liberada.

### Sobre a paridade 0.6 (recado do coordenador)

Conferido commit a commit, não afirmado: **nenhum dos meus dez commits toca**
`app/views/widgets/show.html.erb` nem `app/views/api/v1/widget/configs/create.json.jbuilder`. O que
esta trilha mexe é o caminho inverso — o que a tela **envia** no `PATCH` —, e esse elo passou a ter
mecanismo próprio (`widgetAppearanceContract.spec.js` cruza defaults, tetos, enums e o `permit`).

E a lição do "teste que não existe é indistinguível de teste que passa" foi aplicada aos mecanismos
desta trilha: cada aceite foi verificado nos **dois sentidos**, com sabotagem embutida —

| Sabotagem | O que caiu |
|---|---|
| escrever no objeto do store dentro do composable | 3 testes de `useInboxWidgetConfig` |
| mandar só o subcampo do grupo no `PATCH` | os mesmos 3 |
| reintroduzir `SCRIPT_SETTINGS` com JavaScript no i18n | 3 testes, nomeando idioma e chave |
| renomear `widget_appearance` → `widget_appearence` no mapa | o teste do `permit`, nomeando a chave |
| trocar o default de `theme` | o teste de contrato, nomeando o campo |

---

## Paridade 0.6 rodada de verdade nesta trilha — resultado cru

**Antes de rodar, uma correção de premissa que interessa ao coordenador:** o
`spec/requests/widget_configuration_builder_parity_spec.rb` **já estava na minha base**, e não veio
da restauração. Ele entrou por `ad5c637f26` (o commit do bloco 3.04, da trilha de backend), e é
**byte a byte** o arquivo do commit original do 0.6:

```
$ diff <(git show 1a45399b2a:spec/requests/widget_configuration_builder_parity_spec.rb) \
       spec/requests/widget_configuration_builder_parity_spec.rb
(vazio)

$ git merge-base --is-ancestor 5184a6f209 HEAD   →  não   (a restauração é posterior ao meu merge)
```

Ou seja: a rede chegou às trilhas que mergearam 3.04, pela porta do 3.04. O merge da restauração vai
ser trivial — mesmo conteúdo.

### As duas pontas, conferidas com os olhos primeiro

| chave | `show.html.erb` | `create.json.jbuilder` |
|---|---|---|
| perfil | `widgetProfile` (:58) | `widget_profile` (:29) |
| flags planas | `profileConfig` (:59) | `profile_config` (:30) |
| gatilhos | `widgetTriggers` (:60) | `widget_triggers` (:31) |
| tracking | `widgetTracking` (:61) | `widget_tracking` (:32) |
| **aparência** | `widgetAppearance` (:62) | `widget_appearance` (:33) |

As cinco estão nos dois lados. As de topo seguem a convenção de cada arquivo (camelCase no ERB,
snake_case no JSON) e o spec normaliza.

### E depois rodada, com banco dedicado

```
$ eval "$(grep -E '^POSTGRES_(HOST|USERNAME|PASSWORD|PORT)=' …/.env | sed 's/^/export /')"
$ export RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test_o2telas
$ bundle exec rails db:create db:schema:load     → Created database (138 tabelas)
$ bundle exec rspec spec/requests/widget_configuration_builder_parity_spec.rb

  Missing from app/views/api/v1/widget/configs/create.json.jbuilder: ["tokens"]
  Missing from app/views/widgets/show.html.erb: []

  Diff:
   "app/views/api/v1/widget/configs/create.json.jbuilder" => ["api_host"],
  -"app/views/widgets/show.html.erb" => ["hasAConnectedAgentBot"],
  +"app/views/widgets/show.html.erb" => ["hasAConnectedAgentBot", "tokens"],

  Finished in 5 minutes 31 seconds
  1 example, 1 failure
```

**`1 example`, e 1 é o número esperado** — o arquivo tem um único exemplo (`:27`). Não é o
`0 examples, 0 failures` que passa por verde.

**A única divergência é `tokens`** (bloco 1.02, trilha do widget). Nenhuma chave desta trilha falta
em nenhum dos dois lados; não toquei nem consertei chave alheia.

**Registro de honestidade:** este foi o **único** `rspec` que esta trilha rodou. Tudo o mais que
reportei é `vitest` e Playwright. Onde o relatório diz que a leitura de ponta a ponta da aparência é
coberta pelos specs Ruby de 3.18, isso é atribuição de responsabilidade — **não** um teste que eu
tenha executado.
