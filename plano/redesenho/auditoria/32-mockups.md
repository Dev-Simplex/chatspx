# 32 — Auditoria adversarial dos mockups

> **O que é este documento.** Uma varredura hostil dos nove arquivos de
> `plano/redesenho/mockups/`, feita para achar onde eles **não** estão à altura. Não é revisão de
> cortesia: parti da hipótese de que há problemas sérios e fui atrás deles com o navegador aberto.
>
> **Nenhum arquivo do repositório foi alterado.** O único artefato desta task é este markdown.
>
> **Data:** 12/08/2026 · **Branch:** `homologacao` · **Método:** Playwright + Chromium 145
> (`--no-sandbox --disable-dev-shm-usage`), axe-core 4.10.2 injetado, medição de contraste pelo
> **pixel renderizado** (Pillow), seis combinações de viewport × tema, mais `forced-colors: active`,
> `prefers-reduced-motion: reduce`, zoom 200% (640 px CSS), reflow 320 px e text-spacing forçado.

---

## 0. Veredito em uma página

**Podem ser mostrados a um cliente? Sim — os três do widget e os dois de configuração 22/23, com
uma ressalva de roteiro. Não, ainda, o 20, o 21 e o `index.html`.**

O trabalho não é fraco. O widget (`10-widget-*`) é a peça mais forte do conjunto: bate a
especificação do relatório 16 §3 em 20 das 22 medidas que conferi uma a uma, tem foco visível em
100% dos controles, movimento desligável por token e resolve na raiz o defeito que originou o
estudo — o header verde saía com texto branco a 2,27:1 e agora sai com texto **preto a 9,24:1**,
medido no pixel. Isso é entrega real.

O que derruba o conjunto é outra coisa: **os nove arquivos não são um sistema, são quatro autores
com o mesmo arquivo de tokens**. Isso aparece em números, não em impressão:

| Sintoma | Medida |
|---|---|
| Tamanhos de `<h1>` diferentes em 9 páginas | **5** (16, 18, 20, 22, 34 px) |
| Larguras máximas de conteúdo | **3** (1120, 1200, 1280 px) |
| Raios do "cartão de seção" | **2** (16 px em 20/21, 12 px em 22/23) |
| Navegações de configuração incompatíveis | **2** (7 abas `role=tab` × 4 links `aria-disabled`) |
| Densidade explicativa entre telas de config | **3,4×** (15,6 × 4,6 palavras por controle) |
| Cores literais fora dos blocos de fundação | **83** (28 no `20`, 22 no `21`, 32 no `index`) |
| Aderência do widget aos primitivos `wui-` | **3 de 112 elementos**; **0 de 14 botões** usam `wui-btn` |

E três coisas que reprovam critério da WCAG, não gosto:

1. **`Esc` não fecha o painel do widget** e o foco não entra nele ao abrir — os dois estão no
   checklist de aceite do próprio 16 §8.3.
2. **Seis alvos do widget ficam abaixo de 44 px no viewport mobile**, contra o que
   `primitivos.css` declara no cabeçalho e o 16 §8.3 exige.
3. **Em `forced-colors: active`, o skeleton, o tooltip e o ponto de presença desaparecem
   completamente** — porque a estratégia de "anel de 1 px" do sistema de elevação usa `box-shadow`,
   e `box-shadow` é descartado nesse modo. O LEIA-ME §8.6 declarou esse cenário "não verificado";
   verifiquei, e há defeito.

E um problema de apresentação que é o mais provável de estourar numa demonstração ao vivo: **as sete
abas do topo das telas 20 e 21 não fazem nada quando clicadas.** Clicar em "Gatilhos" é o gesto mais
natural do mundo diante daquela tela, e a resposta é o silêncio.

---

## 1. Método, e o que ele custou em falsos alarmes

Declaro isto antes dos achados porque me obrigou a apagar quatro deles.

- **Contraste:** medido por composição da cor computada (`color` + opacidade acumulada dos
  ancestrais) sobre a **moda dos pixels da caixa**, lida de screenshot real. Não da string CSS.
- **Estados:** cada cena/controle clicado, com espera de 700 ms e de 4,2 s (as cenas do widget têm
  roteiros com `after.delay` de 1.600 e 3.000 ms), e comparação por hash de screenshot da viewport
  e por `outerHTML` + `--brand` computada + `data-theme`.
- **Teclado:** `Tab` real, elemento a elemento, lendo `outlineWidth/Style/Offset`, `boxShadow` e o
  nome acessível calculado (aria-label → label → aria-labelledby → texto → title → placeholder).

**Quatro achados que levantei e derrubei** — ficam registrados porque um relatório que só mostra o
que sobreviveu não deixa auditar o auditor:

| Suspeita | Por que caiu |
|---|---|
| "A lista de mensagens estoura o painel: `log` de 971 px dentro de 640, `overflow: visible`, 422 px cortados acima" | O scroll está no pai (`.wchat-body`, `overflow-y: auto; flex: 1; min-height: 0`). Medido: `scrollTop` 481 de 971/490, `noFim: true`. **Comportamento correto de chat.** |
| "axe acusa 4 violações de contraste no preview escuro da tela 20 (1,15:1 e 1,06:1)" | Falso positivo do axe (o `transform: scale(.8)` do palco confunde o cálculo de fundo). Medido no pixel: **8,54:1** no `#pvFrase` e **9,24:1** no nome do header. |
| "O indicador de digitando não tem nome acessível" | Tem: `role="status"` + `aria-label="Sol está digitando"` no `.wui-typing`. Eu tinha medido o `<div>` pai. |
| "Os mockups 20/21 embutem uma fundação forkada" | `tokens.css` e `primitivos.css` embutidos são **byte a byte idênticos** ao `shared/` nos oito arquivos. Meu extrator tinha casado com texto dentro de um comentário HTML. |
| "O botão de fechar do preview (`.pvw__hd-x`, 21 px, sem nome) reprova 4.1.2 e 2.5.8" | Tem `aria-hidden="true"` **e** `tabindex="-1"`: é decoração declarada, não controle. Correto como está. O que sobra é o irmão dele — ver M1 |

Também: sete das oito páginas acusaram "cortes" no teste de reflow que são `.wui-sr-only`
(clipagem intencional) e `.wui-skeleton` (sem texto). Descontei todos.

---

## 2. Achados por severidade

### BLOQUEADOR

Nenhum. Não há nada nestes arquivos que impeça a conversa sobre a direção visual acontecer. Digo
isso explicitamente porque a missão pedia para não inventar problema onde não há.

---

### GRAVE

#### G1 · `Esc` não fecha o painel, e o foco não entra nele ao abrir

**Evidência.** `10-widget-marketing.html` (1400×950) e `10-widget-mobile.html` (390×844). Foco no
launcher → `Enter` → painel abre (`data-open="true"`, `aria-expanded="true"`) → `Escape` →

```
apos Esc: {"aberto": "true", "panelVis": "visible", "ariaExpanded": "true"}
foco    : button.wchat-launcher | Fechar o chat        (desktop)
foco    : body.wui                                      (mobile)
```

Nas duas viewports o painel continua aberto. No desktop o foco fica no launcher; no mobile — onde o
launcher recebe `display: none` ao abrir — o foco cai no `<body>`, e a partir dali o `Tab` recomeça
pelo topo da página do site do cliente: contei **28 tabulações** sem entrar no painel.

**O que a spec pedia.** 16 §8.3, checklist operacional, três itens seguidos:
`[ ] Foco entra no painel ao abrir` · `[ ] **Esc fecha o painel** e o foco volta ao launcher` ·
`[ ] Em modal (mobile), o conteúdo de fundo é inert`.

**Consequência.** Um visitante de teclado que abre o chat por engano no celular não tem como sair
sem varrer a página inteira. E como o mockup é a peça que valida o desenho, esse comportamento
simplesmente não foi desenhado — vai chegar na implementação como "detalhe esquecido", que é
exatamente o que o mockup existe para impedir. Critérios afetados: **SC 2.1.2 (No Keyboard Trap, A)**
na prática, **SC 2.4.3 (Focus Order, A)** no mobile.

**Correção.** P — um `keydown` no painel e o `focus()` de retorno. O desenho não muda.

---

#### G2 · Seis alvos do widget ficam abaixo de 44 px no viewport mobile

**Evidência.** `10-widget-mobile.html`, viewport 390×844, `has_touch`, medindo só dentro de
`.wchat-stage`:

| Alvo | Medido | Cena |
|---|---:|---|
| `button.wchat-send` (enviar) | **40 × 40** | todas |
| `button.wchat-chip` (quick reply) | 68–171 × **40** | 05, 09 |
| `button.wchat-csat__opt` | **42** × 44 | 15 |
| `button.wchat-file__dl` (baixar anexo) | **40 × 40** | 12 |
| `button.wchat-branding__act` ("Continuar no WhatsApp") | 168 × **32** | todas |
| `textarea.wchat-composer__ta` | 152 × **40** | todas |

**Mecanismo, e é aqui que dói.** `primitivos.css` §18 promove a 44 px **todos** os primitivos
(`.wui-btn`, `.wui-tab`, `.wui-chip`, `.wui-input`, `.wui-textarea`, `.wui-select`, `.wui-check`,
`.wui-switch`). A media query equivalente do widget promove **dois** elementos:

```css
.wchat-stage.is-mobile .wchat-hbtn,
.wchat-stage.is-mobile .wchat-cbtn { width: var(--w-touch-mobile); height: var(--w-touch-mobile); }
```

O widget reimplementou botão, chip e campo com prefixo `wchat-` em vez de usar ou estender os
primitivos — e ao reimplementar, perdeu a regra. A conta da aderência, medida no DOM renderizado
dentro de `.wchat-stage` (cena "Quick replies", que tem 7 chips e o composer completo):

```
elementos no widget: 112   ·   com classe wui-: 3   ·   com classe wchat-: 66
botões: 14                 ·   botões usando wui-btn: 0
única classe de primitivo em uso: wui-tabular
```

Dos 75 primitivos da fundação, o widget usa **um utilitário** (`wui-tabular`) e, na cena de
digitando, o `wui-typing`. Botão, chip, campo, badge, avatar, card e skeleton foram todos refeitos.

**Consequência.** O botão de enviar e o CTA de handoff — os dois controles que carregam a conversão
inteira — ficam abaixo do alvo que o próprio 16 §8.3 lista como item de aceite
("Alvos ≥ **44×44** no viewport mobile"). Não reprova o SC 2.5.8 (que pede 24), mas reprova o
checklist da casa e o SC 2.5.5 (AAA) que a spec adotou de propósito.

**Correção.** P para o CSS. **M** se a decisão certa for a estrutural: fazer `.wchat-send`,
`.wchat-chip` e `.wchat-branding__act` herdarem de `.wui-btn`/`.wui-chip` em vez de existirem em
paralelo — que é o que impede o próximo esquecimento.

---

#### G3 · Em `forced-colors: active`, três componentes desaparecem

**Evidência.** `00-sistema-visual.html`, contexto com `forced_colors="active"`, valores computados:

| Componente | `background` | `border` | `box-shadow` | Resultado |
|---|---|---|---|---|
| `.wui-skeleton` | `rgb(255,255,255)` (Canvas) | `0px none` | **`none`** | invisível sobre Canvas |
| `.wui-tip__bubble` (tooltip) | `rgb(255,255,255)` (Canvas) | `0px none` | **`none`** | invisível sobre Canvas |
| `.wui-avatar__dot` (presença) | `rgb(255,255,255)` | `2px solid rgb(255,255,255)` | `none` | invisível |
| `.wui-badge` | `rgb(255,255,255)` | `0px none` | `none` | sem delimitação (texto sobrevive) |
| `.wui-card` | Canvas | **`1px solid`** | `none` | **sobrevive** |
| `.wui-banner--danger` | Canvas | **`1px solid`** | `none` | **sobrevive** |

**Mecanismo.** `tokens.css` §4.3 apoia a distinção em `--w-elev-N-ring: 0 0 0 1px CanvasText`, um
`box-shadow`. **O Chromium descarta `box-shadow` inteiro em `forced-colors`** — medido: `none` nos
seis componentes acima, inclusive nos que declaram o anel. Quem sobrevive é só quem tem `border`
real, e `primitivos.css` §19 dá borda a cinco classes (`.wui-btn`, `.wui-card`, `.wui-chip`,
`.wui-banner`, `.wui-typing`) e a nenhuma das três que somem. Pior: a regra
`.wui-skeleton::after { display: none }` desliga o brilho, o que deixa o skeleton em nada absoluto.

**Consequência.** Um usuário de alto contraste do Windows, ao carregar uma conversa, vê uma área
completamente vazia durante a espera — sem skeleton, sem spinner, sem sinal. E perde o indicador de
presença online/offline por completo. O §8.6 do LEIA-ME lista `forced-colors: active` como
"não verificado"; esta é a verificação.

**Achado adjacente, mesmo bloco:** **18 dos 34 tokens de cor não são remapeados** sob
`forced-colors` — `--w-danger`, `--w-warning`, `--w-success`, `--w-info`, os quatro `-subtle`,
`--w-on-danger`, `--w-surface-inverse`, `--w-on-inverse`, `--w-skeleton-base`, `--w-skeleton-sheen`,
`--w-brand-hover`, `--w-brand-pressed`, `--w-brand-subtle` e mais quatro. O que acontece com eles
fica a cargo do que o navegador force — que é o oposto de projetar.

**Correção.** P: trocar os anéis por `border` real nos três componentes e completar o mapeamento.

---

#### G4 · O preview do widget corta conteúdo, sem rolagem, a 200% de zoom e a 320 px

**Evidência.** `.pv__palco` nos mockups 20 e 21, `overflow: hidden` nos dois eixos:

| Viewport | Arquivo | `scrollWidth`/`clientWidth` | `scrollHeight`/`clientHeight` |
|---|---|---|---|
| 640 px (= 200% em 1280) | 20 | 411 / 382 | **760 / 608** |
| 640 px | 21 | — | **480 / 384** |
| 320 px (reflow) | 20 | **363 / 286** | 760 / 502 |
| 320 px | 21 | **363 / 286** | 480 / 317 |
| text-spacing forçado | 20 | 411 / 382 | `.pvw__corpo` **317 / 237** |

Não há barra de rolagem: o `overflow` é `hidden`, não `auto`.

**Consequência.** A 200% de zoom, o cliente que está configurando a caixa de entrada perde 152 px do
preview pela base — o composer e o rodapé somem. A 320 px perde 77 px de largura. Reprova
**SC 1.4.4 (Resize text, AA)** e **SC 1.4.10 (Reflow, AA)**, e reprova justamente no componente que
dá razão de existir à tela. Os dois critérios estão na tabela do 16 §8.3.

**Correção.** P: `overflow: auto` no palco, ou reduzir a escala do preview junto com o viewport.

---

#### G5 · A duplicata de tokens dos mockups 20/21 já dessincronizou — em menos de um dia

**Evidência.** Os dois arquivos copiam literalmente o corpo dos temas de `tokens.css` para as
classes `.pv-claro` / `.pv-escuro`. O comentário no 20 antecipa o problema com honestidade
("Isso NÃO deve ser copiado para o código — copiar é exatamente o defeito D4 do plano 23 §A.12").
Só que a cópia **já divergiu entre os dois mockups**:

| Token | `.pv-claro`/`.pv-escuro` no 20 | no 21 |
|---|---|---|
| `--w-elev-0` / `--w-elev-0-ring` | copiados | **ausentes** |
| `--w-elev-3` / `--w-elev-3-ring` | copiados | **ausentes** |
| `--w-surface-overlay`, `--w-surface-active`, `--w-text-subtle`, `--w-brand-subtle`, `--w-skeleton-*`, `--w-surface-inverse`, `--w-on-inverse` | **ausentes** | **ausentes** |

**Consequência.** Um preview em tema escuro dentro de uma página em tema claro herda o
`--w-surface-overlay`, o `--w-text-subtle` e o skeleton **claros** — e, no mockup 21, também as
sombras claras nos níveis 0 e 3. É a dessincronização silenciosa que a nota do próprio arquivo
descreve, acontecendo dentro do próprio conjunto de mockups, entre dois arquivos escritos no mesmo
dia. É a melhor prova possível de que a recomendação anotada no rodapé (criar
`.wui-theme-light` / `.wui-theme-dark` no `tokens.css`) **não é opcional**.

**Correção.** P — e é pré-requisito, não sugestão: enquanto não existir, qualquer tela nova com
preview vai recriar a mesma cópia parcial.

---

#### G6 · A navegação principal das telas de configuração não navega

**Evidência.** Método: recarregar a página, clicar, comparar `outerHTML` + `--brand` + `data-theme`.

| Tela | Controle | Resultado |
|---|---|---|
| 20 | 7 abas `.wui-tab` (Aparência…Instalação) | **INERTE** (nenhuma) |
| 21 | 7 abas `.wui-tab` | **INERTE** |
| 22 / 23 | 3 links de nav lateral | `href="#"` + `aria-disabled="true"` — inertes por construção |
| 23 | Reconectar, Desconectar, Substituir, Salvar alterações, Descartar | **INERTE** (5 de 5) |

Os arquivos `20` e `21` até têm um link direto um para o outro (`→ tela 2: gatilhos`), mas é um link
solto de 104 × 16 px na barra de andaime — não é a navegação da tela.

**Consequência.** Numa demonstração, o primeiro gesto de qualquer pessoa diante de uma barra de abas
é clicar na aba seguinte. Nas telas 20 e 21 isso não produz nada — nem troca, nem navegação, nem
sinal de "não implementado". Quem apresenta tem de explicar; quem recebe o link sozinho conclui que
está quebrado. E no 23, o botão "Salvar alterações" — o mais importante da tela — é inerte enquanto
as cinco abas internas funcionam, o que é uma inconsistência de expectativa dentro do mesmo arquivo.

**Ressalva justa:** mockup não precisa implementar tudo. Mas um controle que existe, tem aparência
de habilitado e não responde é pior que um controle ausente. Os links `aria-disabled` do 22/23
resolvem isso — só que resolvem mentindo: comunicam que aquelas abas estão **desabilitadas no
produto**, quando na verdade elas são os arquivos 20 e 21 do lado.

**Correção.** P: transformar as abas em `<a href="21-config-gatilhos.html">` onde o arquivo existe, e
marcar as demais com um rótulo explícito ("nesta onda não") em vez de `aria-disabled`.

---

#### G7 · O `index.html` é a única página que não usa o sistema que ele apresenta

**Evidência.** Não importa `tokens.css` nem `primitivos.css`. Reimplementa um sistema paralelo:

| | `index.html` | fundação |
|---|---|---|
| Cores literais | **32** | 0 permitidas |
| Nomes de token | `--surface`, `--text`, `--r1`, `--s1`, `--dur` | `--w-surface`, `--w-text`, `--w-radius-*` |
| Raios fora da escala | **20 de 31** (5 px, 999 px) | 0 |
| Pesos fora de {400,500,600,700} | **15** (peso `650`) | 0 |
| Tamanhos fora da escala | **114** (14,5 · 12,6 · 13,5 · 11,5 · 16,5 · 19 px) | ≤ 1 |
| Stack de fonte | `-apple-system` | `system-ui` |
| Cor de acento | `#0F7A52` / `#4ADE80` inventados | `--w-brand-readable` já entrega isso |
| `<h1>` | **34 px / peso 650** | maior do conjunto é 22 px |

O comentário do arquivo justifica o `#0F7A52` com a medição de contraste correta (5,35:1) — o
raciocínio está certo. O problema é que **esse valor já existe no sistema**: `--w-brand-readable` é,
por definição, a marca cortada em `min(l, 0.51)` para atingir 4,5:1. O token foi reinventado à mão
ao lado do token que faz exatamente aquilo.

**Consequência.** A porta de entrada — a primeira tela que o cliente abre — é a única que não
demonstra o sistema. Abrir o índice e depois um mockup mostra duas tipografias, dois pesos de título
e dois raios. E qualquer ajuste futuro em `tokens.css` não chega ao índice.

**Correção.** P: importar a fundação e trocar 32 literais por tokens. É o P de menor esforço da lista
inteira, e remove a única página do conjunto que contradiz a própria tese.

---

### MÉDIO

#### M1 · Um botão sem nome acessível (`critical` no axe) — e o irmão dele mostra qual era o padrão

`20-config-perfil-aparencia.html`, `#pvLauncher`, nos dois temas: *"Element does not have inner text
that is visible to screen readers; aria-label attribute does not exist or is empty"*. Único
`critical` do conjunto inteiro. **SC 4.1.2 (A).**

O markup explica: o SVG é `aria-hidden`, o `<span>Fale com a gente</span>` está `hidden` (só aparece
na variante "Ícone + texto") e sobra um `<button>` mudo:

```html
<button class="pvw__launcher" id="pvLauncher" type="button" tabindex="-1">
  <svg … aria-hidden="true">…</svg>
  <span id="pvLancTexto" hidden>Fale com a gente</span>
</button>
```

O irmão dele, o X de fechar do mesmo preview, resolve certo — `aria-hidden="true"` + `tabindex="-1"`,
declarando que é representação e não controle. O launcher esqueceu metade. Não é focável por Tab, mas
é alcançável na navegação por elementos do leitor de tela, que vai anunciar "botão" e nada mais.
Correção: **P** — uma palavra.

#### M2 · O rótulo do dispensar do teaser afirma uma medida que o elemento não tem

`21-config-gatilhos.html`, viewport 390: `button.tsr__x` renderiza **21,1 × 21,1 px** e carrega
`aria-label="Dispensar (alvo de 32 × 32)"`. Causa: um botão de 26 px dentro de um palco em
`transform: scale(.8)`.

**Ressalva importante, e ela reduz a gravidade:** o elemento tem `tabindex="-1"` — é a representação
do teaser dentro do preview, não um controle funcional. Portanto **não reprova o SC 2.5.8**, e
retirei esse critério da conta. O que sobra é a peça afirmando por escrito um número que ela não
entrega, num arquivo cuja tese inteira é "toda medida vem de medição". O 16 §3.2 fixa 32 × 32
justamente *corrigindo* o dismiss de 9,8 px do Olark; se um cliente ou um dev medir a régua na tela,
encontra 21. Correção: **P** — ou o rótulo perde o parêntese, ou o preview compensa a escala.

#### M3 · O preview do widget não é o widget

Medido lado a lado, mesma viewport, cena de conversa:

| Propriedade | `10-widget-*` | preview no `20` | spec 16 |
|---|---|---|---|
| Padding do balão | `12px 16px` | **`8px 12px`** | `12px 16px` (DV-3) |
| Canto de origem | 6 px (última do grupo) | **4 px** | 6 px (DV-4/DV-5) |
| `max-width` do balão | 82,0% (medido: 308,3 / 376) | **76%** | 82% (DV-2) |
| Horário | **fora** do balão | **dentro** do balão | fora (§3.4: "Por que o horário fica fora do balão") |
| Sombra do balão | nenhuma | **`--w-elev-0`** | **nenhuma** (§3.5.1, marcado "CORRIGE") |
| Padding do header | `8px 12px` | **`16px`** | `8px 12px` (§3.3) |
| Raio do composer | 12 px | **0 px** | 12 px (§3.9) |
| Borda do composer | `--w-border-strong` (3,37:1) | **`--w-border`** (1,28:1) | ≥ 3:1 (§8.1) |

As duas últimas linhas têm consequência além da estética: a borda do campo de digitação com
`--w-border` reprova o **SC 1.4.11**, e a divergência D2 do próprio LEIA-ME existe exatamente para
impedir esse uso. O resto tem consequência de credibilidade: o cliente aprova, no preview, um balão
com sombra, horário interno e canto de 4 px, e recebe outro.

Correção: P por item; **M** se a decisão for a correta — o preview passar a montar o mesmo markup do
widget em vez de uma segunda implementação.

#### M4 · Dois shells de configuração incompatíveis

A mesma tela de configuração de inbox aparece com duas navegações:

| | 20 e 21 | 22 e 23 |
|---|---|---|
| Navegação | 7 abas `role="tab"`, 44 px, `.wui-tabs` | 4 links `.cfg-nav`, 46 px |
| Largura máx. do conteúdo | 1200 px | 1280 px |
| Raio do cartão de seção | **16 px** (o raio de *painel*, pelo LEIA-ME §5.5) | 12 px (correto: "12 = campo e cartão") |
| Cabeçalho da página | avatar + nome + chip de perfil | breadcrumb + h1 + toggle |
| `<h1>` | 16 px | 20 px |

Um cliente que veja as quatro em sequência vê dois produtos. Correção: **M** — alguém tem de
escolher um shell e refazer o outro par.

#### M5 · No mockup 23, dois níveis de navegação têm a mesma voz

Medido: nav lateral 14 px / peso 500 / altura 46 px / sublinhado de 2 px; abas internas 14 px /
peso 600 / altura 44 px / sublinhado no ativo. Mesmo tamanho, mesma cor de ativo (o mesmo
`oklch(0.51 …)`), alturas separadas por 2 px, empilhadas uma sob a outra. A hierarquia entre "em que
tela estou" e "em que aba desta tela estou" fica a cargo de um único degrau de peso tipográfico.
Um diretor de arte devolve isso. Correção: P (tamanho, cor ou tratamento — qualquer um dos três).

#### M6 · O teaser continua se movendo sob `prefers-reduced-motion`

`--w-dur-teaser-in` foi classificado no bloco "opacidade pura sobrevive, teto de 100 ms" de
`tokens.css` §4.1. Mas o keyframe que a usa move:

```css
@keyframes wchat-teaser-in { from { opacity: 0; transform: translateY(8px); } to { … } }
```

Medido com `reduced_motion=reduce`: todas as demais durações vão a `1ms`/`0s`;
`--w-dur-teaser-in` fica em **100 ms**, e a animação inclui `transform`. Contraria a regra do próprio
bloco ("transição de transform → nenhuma") e o 16 §3.2, que nomeia o teaser: *"Sem animação sob
`prefers-reduced-motion` — aparece direto"*. É o único elemento que a spec citou pelo nome, e é o que
sobrou se mexendo. Correção: P.

#### M7 · Em `forced-colors`, todo texto secundário ativo é pintado como desabilitado

`tokens.css` §4.3 mapeia `--w-text-muted: GrayText` e `--w-text-subtle: GrayText`. `GrayText` é a
cor que o sistema operacional reserva para **conteúdo inativo**. Com esse mapeamento, nome do autor,
horário, linha de status do header, descrição de cartão, cabeçalho de tabela, placeholder e rodapé
de branding passam todos a "cinza de desabilitado" — verificado na captura do catálogo em alto
contraste, onde a descrição inteira dos cartões e o cabeçalho da tabela mudam de cor.

É o mesmo erro conceitual que o LEIA-ME §5.2 corrige com rigor no tema normal ("`--w-text-subtle`
não serve para placeholder… só vale onde a WCAG isenta") e que reaparece aqui, com `muted` e
`subtle` colapsando no mesmo valor. Correção: P — `--w-text-muted: CanvasText`.

#### M8 · A densidade explicativa varia 3,4× entre telas do mesmo produto

Palavras em parágrafos explicativos por controle interativo:

| Tela | Controles | Parágrafos | Palavras | Palavras / controle |
|---|---:|---:|---:|---:|
| 21 · gatilhos | 63 | 20 | 291 | **4,6** |
| 22 · pré-chat | 89 | 24 | 485 | 5,4 |
| 20 · aparência | 58 | 25 | 452 | 7,8 |
| 23 · rastreio | 65 | 39 | 1.015 | **15,6** |

O 23 tem **77% de todo o texto da página** em prosa explicativa. Trechos como *"É a nota que a Meta
dá para a chance de reconhecer a pessoa do outro lado. Quanto maior, melhor a campanha aprende. Um
chat sai na frente aqui: ele pergunta nome e telefone, coisa que um pixel de página nunca tem."*
são bons na primeira visita e ruído a partir da segunda. Não é erro — é uma decisão que ninguém
tomou conscientemente para as quatro telas juntas. Correção: **M** (decisão de produto + reescrita).

#### M9 · Texto abaixo do piso de 12 px, incluindo dados que o usuário precisa copiar

O LEIA-ME §5.4 fixa "piso absoluto: 12 px". Medido nos nós de texto renderizados:

| Arquivo | Nós < 12 px | Menores casos |
|---|---:|---|
| `00-sistema-visual` | **181** | `code` a **10,8 px**; `.doc-sw__name`/`.doc-sw__val` a 11 px (×94) |
| `20-config` | 48 | `code` a 11,4 px |
| `22-config` | 37 | `code` a **11,04 px** — `intencao`, `prazo`, `nome`, `telefone` |
| `23-config` | 34 | `code` a 11,04 px |
| `index` | 8 | `.tag` a 11,5 px |
| `10-widget-*` | **0** | — |

Dois pesos diferentes aqui. No `00`, são os rótulos da própria documentação: a página que declara o
piso escreve **os nomes dos tokens** no menor texto que ela tem. No `22` e `23`, é pior: os
identificadores técnicos (`intencao`, `chatspx_lead`) são conteúdo de produto que o usuário vai ler
e copiar para o GTM, e são o texto menor da tela. Correção: P — um `font-size` mínimo no `code`.

#### M10 · Cinco escalas de título, porque o sistema não tem uma

| Arquivo | `<h1>` | `<h2>` |
|---|---|---|
| `index` | **34 px / 650** | 15 px / 650 |
| `00-sistema-visual` | 22 / 600 | 20 / 600 |
| `22`, `23` | 20 / 600 | 16–18 / 600 |
| `10-widget-*` | 18 / 600 | 40 / 700 (site host) |
| `20`, `21` | **16 / 600** | 16 / 600 |

A causa é real e é da fundação, não dos mockups: `tokens.css` só oferece `--w-text-title`
(16/24/600) como token de título, porque foi projetado para o widget. **Não há escala tipográfica de
página.** Cada autor inventou a sua. Correção: P na fundação (três tokens: `--w-text-page-title`,
`--w-text-section`, `--w-text-subsection`), depois P em cada arquivo.

#### M11 · Cinco cenas do widget não respondem ao clique com um estado próprio

Das 71 cenas dos três mockups (22 + 24 + 25), **todas respondem** — mas a cena
**"Digitando → resposta"** termina, nos três arquivos, em estado **byte a byte idêntico** à cena
anterior ("Conversa e agrupamento"): mesmo texto (646 caracteres, comparados), mesmo hash de
screenshot. A cena existe para mostrar a transição, que dura ~1,6 s; quem clicar e olhar 3 segundos
depois conclui que o botão não fez nada.

Mitigado pelo botão "Repetir a animação" no studio, que não é óbvio. Correção: P — ou um estado
final distinto, ou replay automático ao selecionar a cena.

---

### MENOR

| # | Achado | Evidência | Consequência |
|---|---|---|---|
| m1 | **43 de 43 `<button>` sem `type="button"`** no `00-sistema-visual` (todos os outros oito arquivos: 0 sem type) | `e.type === "submit"` em toda a varredura de Tab | É o catálogo de referência: quem copiar a marcação dos primitivos para dentro de um `<form>` do dashboard leva o submit acidental que o 16 §3.1 manda evitar |
| m2 | Header do widget mede **59 px**, spec pede 56 | `.wchat-header` h=59 (`min-height:56` + padding + conteúdo de 43 px) | 3 px. Nenhuma, além de o número da spec deixar de ser verdade |
| m3 | `<dl>` com `<p>` como filho direto — `serious` no axe nos três widgets | `dl element has direct children that are not allowed: p` | **SC 1.3.1 (A)**: a relação nome/valor quebra para o leitor de tela |
| m4 | Dois `banner` landmarks e `landmark-unique` no `10-widget-mobile` | `.wchat-panel > header` + o header do documento | O leitor de tela oferece dois "cabeçalhos" sem distinguir |
| m5 | `heading-order` inválido no `10-widget-mobile` (`h3` após `h1`) e no `20` (`#pvTitulo`) | axe, ambos os temas | Navegação por cabeçalho salta um nível |
| m6 | Conteúdo fora de landmark: 28 nós no `index`, 14 nos widgets, 11 no mobile; `index` sem `<main>` | `region` / `landmark-one-main` | Navegação por regiões degradada |
| m7 | `rgb(0 0 0 / 0.18)` literal em `primitivos.css` (sombra interna do `:active` do botão) | 1 ocorrência, replicada nos 8 arquivos que embutem a fundação | A própria fundação viola a regra 1 do LEIA-ME. Falta um token de sombra interna |
| m8 | `.dlg::backdrop { background: rgba(0,0,0,.5) }` no `20` | 1 ocorrência | Não existe token de scrim; a próxima modal vai inventar outro valor |
| m9 | 15 px de margem em `.mk-readout`/`.host__stat` (×10), 14 px em `dl.tk-kv`, peso `900` num `<b>` no `22` | fora da escala `0/2/4/8/12/16/20/24/32/40/48` e de {400,500,600,700} | Ruído. A escala é respeitada em 99% dos casos |
| m10 | Espaçamento de **20 px entre grupos temporais** (16 §3.4) não observado | gaps medidos na lista: `4, 4, 12, 4, 12, 4, 4` | O agrupamento temporal fica sem respiro próprio |

---

### COSMÉTICO

- **c1.** A barra de andaime ("MOCKUP · TASK 27 · TELA 1 DE 2 · Estado da tela: Editando / Não
  configurado / Salvo / Erro ao salvar") fica acima da tela real, com botões de 26 px fora do
  sistema de primitivos. Útil para quem audita, ruído para quem aprova. Vale um `?raw` ou um
  colapso.
- **c2.** Os previews dos mockups 20/21 rodam em `transform: scale(.8)`: o corpo de 15 px renderiza
  a 12 px na tela. O cliente aprova uma densidade 25% mais apertada do que a que vai receber.

---

## 3. Tabela de violações de token

Contagem: literais de cor (`#hex`, `rgb()`, `hsl()`, nomes CSS) em qualquer linha de declaração
dentro dos blocos de estilo **próprios** de cada arquivo — os blocos `<style id="tokens">` e
`<style id="primitivos">`, que são cópia byte a byte da fundação, foram excluídos.

| Arquivo | Literais | Onde |
|---|---:|---|
| `10-widget-marketing.html` | **0** | — |
| `10-widget-suporte.html` | **0** | — |
| `10-widget-mobile.html` | **0** | — |
| `22-config-prechat-fluxo.html` | **0** | — |
| `23-config-tracking.html` | **0** | — |
| `00-sistema-visual.html` | **1** | `rgb(0 0 0 / 0.18)` no `<style id="doc">` — cópia da linha do `primitivos.css` para forçar o estado `[data-force="hover"]` |
| `21-config-gatilhos.html` | **22** | `.pv-claro` / `.pv-escuro` (20) + `.gat__*` (2) |
| `20-config-perfil-aparencia.html` | **28** | `.pv-claro` / `.pv-escuro` (27) + `.dlg::backdrop` (1) |
| `index.html` | **32** | bloco `:root` inteiro — sistema paralelo |
| **Total** | **83** | |
| *(fora dos mockups)* `shared/primitivos.css` | **1** | `box-shadow: inset 0 2px 4px rgb(0 0 0 / 0.18)` no `.wui-btn--primary:active` |

**Leitura.** Cinco dos nove arquivos estão em zero, e os três do widget — os maiores, com 139 classes
próprias cada — não têm **nenhuma**. Isso é disciplina real. As 82 restantes concentram-se em três
lugares, e dois deles (`.pv-*` e o `index`) são o mesmo problema estrutural: falta um mecanismo de
tema escopado no `tokens.css`, então quem precisa de um sub-tema copia o bloco inteiro.

Nenhum `outline: none` em nenhum dos nove — a regra 4 do LEIA-ME foi respeitada integralmente.
Nenhum raio fora da escala nos oito arquivos que usam a fundação (`index.html`: 20 de 31 fora).

---

## 4. Matriz de consistência entre os nove

`✓` = conforme a fundação · `≈` = próprio mas coerente · `✗` = diverge

| Dimensão | 00 | 10-mkt | 10-sup | 10-mob | 20 | 21 | 22 | 23 | index |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Importa a fundação | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **✗** |
| Zero cor literal | ≈ (1) | ✓ | ✓ | ✓ | **✗** (28) | **✗** (22) | ✓ | ✓ | **✗** (32) |
| Raios na escala | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **✗** |
| Espaço na escala | ✓ | ≈ (15px ×10) | ≈ | ≈ | ✓ | ✓ | ✓ | ≈ (14px) | **✗** |
| Pesos em {400,500,600,700} | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ≈ (1×900) | ✓ | **✗** (650) |
| Piso de 12 px | **✗** (181) | ✓ | ✓ | ✓ | **✗** (48) | **✗** (36) | **✗** (37) | **✗** (34) | **✗** (8) |
| `system-ui` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **✗** |
| Largura máx. de conteúdo | 1120 | — | — | — | **1200** | **1200** | **1280** | **1280** | 1120 |
| Raio do cartão de seção | — | — | — | — | **16** | **16** | 12 | 12 | 16 |
| `<h1>` | 22 | 18 | 18 | 18 | **16** | **16** | 20 | 20 | **34** |
| `type="button"` | **✗** (0/43) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Foco visível em 100% | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Nome acessível (tabuláveis) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Nome acessível (todos, via axe) | ✓ | ✓ | ✓ | ✓ | **✗** (1) | ✓ | ✓ | ✓ | ✓ |
| Alvos ≥ 44 px no mobile (widget) | — | — | — | **✗** (6) | n/a | n/a | n/a | n/a | n/a |
| Alvos ≥ 24 px (SC 2.5.8) em 390 px | ✓ | ✓ | ✓ | ✓ | ✓ (no limite) | ✓ (no limite) | ✓ | ✓ | ≈ (links inline) |
| Zero requisição externa | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Zero erro de console | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Sem overflow horizontal (320/390/1400) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**O padrão que salta.** Os três widgets são um bloco coerente entre si e com a fundação. O `22` e o
`23` são outro bloco coerente. O `20` e o `21` são um terceiro. O `index` está sozinho. O `00`
é o catálogo e tem os defeitos de um catálogo (rótulos pequenos, botões de demonstração sem `type`).
Nenhuma divergência é grosseira — mas são quatro dialetos do mesmo idioma, e a única maneira de um
cliente não perceber é ver uma tela por vez.

**Um componente desenhado de duas formas.** O widget aparece nos nove arquivos: como implementação
(`10-*`), como preview (`20`, `21`, `22`) e como miniatura (`index`). As três implementações são
independentes. As divergências medidas estão no M3.

---

## 5. Acessibilidade, por critério WCAG 2.2

Fonte: axe-core 4.10.2 (tags `wcag2a`…`wcag22aa` + `best-practice`) nos nove arquivos × dois temas,
mais os testes manuais descritos na §1.

| Critério | Nível | Resultado | Onde |
|---|:--:|---|---|
| **1.3.1** Info and Relationships | A | **falha** | `<dl>` com `<p>` direto — 3 widgets |
| **1.4.1** Use of Color | A | **passa** | todo badge e status tem rótulo textual; verificado no catálogo em alto contraste |
| **1.4.3** Contraste mínimo | AA | **passa** com 1 ressalva | **478 nós de texto** medidos por pixel (`00`, `22`, `23`, `index` × 2 temas): **472 aprovam, 6 reprovam** — e as 6 são o mesmo caso: `.cfg-nav a[aria-disabled]` em **4,13:1** (`--w-text-subtle` #797d86 sobre branco). Isento pela WCAG por ser "componente inativo", mas os três links marcados assim **não são** inativos: são as outras telas do conjunto |
| **1.4.4** Resize text (200%) | AA | **falha** | `.pv__palco` corta 152 px sem rolagem nos mockups 20 e 21 (G4) |
| **1.4.10** Reflow (320 px) | AA | **falha** | mesmo elemento: 363 / 286 px. As barras de abas e a nav lateral **passam** (`overflow-x: auto`) |
| **1.4.11** Contraste não-textual | AA | **passa** com 1 ressalva | Ressalva: borda do composer do preview usa `--w-border` (1,28:1) em vez de `--w-border-strong` (M3) |
| **1.4.12** Text spacing | AA | **falha (leve)** | com espaçamento forçado: `.pvw__corpo` corta 80 px (mockup 20), `.pc-step__lab` corta 26 px (22), `.wchat-panel` corta 2 px (mobile) |
| **2.1.1** Teclado | A | **passa** | toda ação alcançável; ordem de Tab = ordem visual em todos os arquivos testados |
| **2.1.2** No keyboard trap | A | **falha na prática** | `Esc` não fecha o painel; no mobile o foco vai para o `body` (G1) |
| **2.2.2** Pause, stop, hide | A | **passa** | typing em loop para sob `prefers-reduced-motion`, com rótulo textual "digitando…" assumindo |
| **2.4.3** Focus order | A | **falha no mobile** | foco no `body` ao abrir o painel (G1) |
| **2.4.7** Foco visível | AA | **passa** | `outline: 2px solid` + `offset: 2px` em **202 de 202** controles tabulados em 6 arquivos. Zero `outline: none` no corpus |
| **2.4.11** Focus not obscured | AA | **não verificado** | exige rolar com foco ativo sob o painel; não exercitei |
| **2.5.5** Target size (enhanced) | AAA (adotado pelo 16 §8.3) | **falha** | 6 alvos do widget < 44 px no mobile (G2) |
| **2.5.8** Target size (minimum) | AA | **passa** | Nenhum controle **funcional** abaixo de 24 × 24 em 390 px. O menor é 24,0 exatos (swatches de cor, radios, botões de segmento do 20/21) — no limite, sem folga. Os dois elementos de 21,1 px são `tabindex="-1"` dentro de previews (M2) |
| **3.2.6** Consistent help | A | n/a | exige múltiplas páginas do site do cliente |
| **4.1.2** Name, role, value | A | **falha** | `#pvLauncher` sem nome acessível (M1) |
| **4.1.3** Status messages | AA | **passa** | `role="log" aria-live="polite"` na lista de mensagens, presente em 19 das 22 cenas do marketing (ausente só onde não há lista: painel abrindo, tela inicial, pré-chat); `role="alert"` no erro de envio e no offline; `role="status"` no teaser e no digitando |

**Resumo do axe.** 9 arquivos × 2 temas = 18 execuções. Um `critical` (`button-name`), quatro
`serious` (um `definition-list` × 3 arquivos, mais `color-contrast` no catálogo — ver abaixo) e o
resto `moderate` (`region`, `heading-order`, `landmark-*`). **As quatro violações de contraste que o
axe apontou no mockup 20 em tema escuro são falso positivo**, refutadas por medição de pixel (§1).

As duas do `00-sistema-visual` são **reais e intencionais**: `.wui-btn--secondary[data-loading]` a
3,36:1 e `.wui-btn--danger[data-loading]` a 3,37:1. São os estados `loading` renderizados no
catálogo — texto sobre botão em carregamento. O sistema não define contraste para esse estado, e o
catálogo o expõe. Vale um token ou uma nota; não vale ignorar.

---

## 6. Os estados: quantos existem, quantos funcionam

### Widget (`10-*`) — 71 cenas

| Arquivo | Cenas | Respondem ao clique | Estado visual distinto |
|---|---:|---:|---:|
| `10-widget-marketing` | 22 | **22** | 21 |
| `10-widget-suporte` | 24 | **24** | 23 |
| `10-widget-mobile` | 25 | **25** | 24 |

Zero erro de console, zero exceção de página nas 71. O único estado sem identidade própria é
"Digitando → resposta" (M11), nos três arquivos. Com espera de 4,2 s — necessária, porque os roteiros
têm `after.delay` de até 3.000 ms — todas as demais rendem screenshot distinto.

Verifiquei também que o estado que a cena promete está de fato no DOM e visível: na cena "Card", o
`.wchat-card` renderiza em `top: 494 / bottom: 727` dentro do painel (206–846), com a lista rolada
ao fim (`scrollTop 481` de `971/490`, `noFim: true`). O scroll funciona.

### Configuração (`20`–`23`)

Método: recarga da página antes de cada clique, comparação de `outerHTML` + `--brand` + `data-theme`.

| Tela | Controles testados | Respondem | Inertes |
|---|---:|---:|---|
| `20-config-perfil-aparencia` | 20 | **17** | 7 abas `.wui-tab` |
| `21-config-gatilhos` | 16 | **10** | 7 abas, "Adicionar atalho" |
| `22-config-prechat-fluxo` | 14 | **11** | "Recomeçar", 3 links de nav |
| `23-config-tracking` | 15 | **9** | Reconectar, Desconectar, Substituir, Salvar, Descartar, 3 links de nav |

O `<dialog>` de troca de perfil no mockup 20 é o melhor comportamento do conjunto: abre no clique do
radio, coloca o foco em "Cancelar", `Tab` circula dentro (com a parada nativa no `body`), `Esc` fecha
e o foco volta ao radio de origem. É a prova de que a equipe sabe fazer — o que torna a ausência do
mesmo cuidado no painel do widget (G1) mais difícil de explicar, não menos.

---

## 7. Aderência ao relatório 16 §2 e §3 — o mockup obedeceu ou inventou?

### §3 — o widget, medido componente a componente

| Item | Spec 16 | Medido | |
|---|---|---|:--:|
| Launcher | 64 × 64, raio full | 64 × 64, `9999px` | ✓ |
| Ícone do launcher | **32 × 32** (corrige os 24 de hoje) | 32 × 32 | ✓ |
| Badge de não lidas | 20 × 20, full, `--w-danger` | 20 × 20, full, `rgb(211,47,47)` | ✓ |
| Painel | 400 × 640, raio 16 | 400 × 640, `16px` | ✓ |
| Header | **56 px**, padding `8px 12px` | **59 px**, `8px 12px` | ≈ |
| Botões do header | 40 × 40, ícone 20 | 40 × 40, ícone 20 | ✓ |
| Teaser | 280 px, raio 16, dispensar 32 × 32 | 280 × 222, `16px`, 32 × 32 | ✓ |
| Balão | raio 20, padding `12px 16px`, sem sombra | 20, `12px 16px`, `box-shadow` transparente | ✓ |
| `max-width` do balão | **82%** | 308,3 / 376 = **82,0%** | ✓ |
| Avatar por mensagem | 28 × 28, só na última do grupo | 28 × 28 | ✓ |
| Separador de data | pill, altura 24 | `9999px`, 24 px | ✓ |
| Agrupamento | 4 px mesmo autor · 12 px autores diferentes · **20 px entre grupos temporais** | `4, 4, 12, 4, 12, 4, 4` — **sem os 20** | ✗ |
| Composer | mín. 48, raio 12, borda 1px | 50, `12px`, `1px --w-border-strong` | ✓ |
| Textarea | **16 px** (anti-zoom iOS) | 16 px | ✓ |
| Botão de enviar | **40 × 40**, full, `--w-brand` | 40 × 40, full — desabilitado em `--w-surface-sunken` com ícone muted, como a spec pede | ✓ |
| Chips | altura 40, full, padding `0 16`, `--w-text-button` | 40, `9999px`, `0px 16px`, 14 px | ✓ |
| Botão "descer" | 36 × 36, full, `--w-elev-1` | 36 × 36, `9999px` | ✓ |
| Card | raio 12 | 12 px | ✓ |
| Rodapé de branding | 12 px, altura 32 | 12 px, 32 px | ✓ |
| Typing | CSS puro, 3 × 7 px, ciclo 1200 ms, stagger 150 ms | `wui-typing` 1,2 s ×infinite, para sob reduced-motion | ✓ |
| `role="log"` na lista | obrigatório (§3.4: "o buraco mais sério do widget hoje") | `role="log" aria-live="polite"` | ✓ |

**20 de 22 conformes.** As duas divergências (header 59 em vez de 56; sem o respiro de 20 px entre
grupos temporais) são pequenas e não escondem decisão: parecem sobra de padding e omissão, não
escolha. **Onde o mockup inventou, inventou pouco — e não inventou para pior.**

### §2 — o sistema visual

O corpo de 15/22 (decisão DV-1), o raio de 20 no balão (DV-4), o padding de 12/16 (DV-3), o launcher
de 64 (DV-6) e a entrada de 200 ms da mensagem (DV-8) estão todos no valor arbitrado. A regra C1 —
contraste calculado, não escolhido — funciona de ponta a ponta: com `--brand: #2dc46f`, o texto sobre
a marca sai **preto**, medido no pixel a **9,24:1** no header, no balão do visitante e no launcher.
O problema que abriu o estudo está resolvido.

Onde a fundação **não** deu conta e os mockups tiveram de improvisar (e é justo registrar como
lacuna dela, não deles):

- **escala tipográfica de página** — não existe; cinco improvisos (M10);
- **tema escopado** (`.wui-theme-*`) — não existe; duas cópias de token (G5);
- **token de scrim** para `::backdrop` — não existe; um `rgba(0,0,0,.5)` literal (m8);
- **token de sombra interna** para o `:active` do botão — não existe; um `rgb(0 0 0 / 0.18)` literal
  dentro do próprio `primitivos.css` (m7);
- **token de texto secundário sobre a marca** — não existe; o preview resolve com `opacity: .75` e
  `.9` (o resultado passa em contraste — 6,0:1 e 8,2:1 medidos —, mas é ad hoc);
- **contraste do estado `loading`** — não definido; o catálogo expõe 3,36:1 e 3,37:1.

---

## 8. Zoom 200%, reflow, text-spacing e `forced-colors` — o que o §8.6 deixou em aberto

O LEIA-ME §8.6 declarou quatro cenários não verificados. Verifiquei os quatro.

| Cenário | Resultado |
|---|---|
| **Zoom 200%** (viewport 640 px CSS) | **1 falha real**: `.pv__palco` corta 152 px na vertical (mockup 20) e 96 px (mockup 21), com `overflow: hidden`. Todo o resto: `scrollWidth == clientWidth` nos 9, nenhum controle fora da viewport que não esteja numa barra rolável |
| **Reflow 320 px** | **1 falha real**: o mesmo `.pv__palco`, agora 363 / 286 px na horizontal. As barras de abas (`.wui-tabs`, 681 / 288) e a nav lateral (`.cfg-nav__in`, 706 / 320) **passam** — são `overflow-x: auto`, que o SC 1.4.10 permite. `index.html` passa limpo |
| **Text spacing** (lh 1,5 · ls 0,12em · ws 0,16em · ¶ 2em) | **3 cortes**: `.pvw__corpo` −80 px (mockup 20), `.pc-step__lab` −26 px (22), `.wchat-panel` −2 px (mobile). Nenhum overflow horizontal de documento |
| **`forced-colors: active`** | **3 componentes desaparecem** (G3) e o texto secundário vira `GrayText` (M7). O que sobrevive bem: header e balão do visitante em `Highlight`/`HighlightText` legíveis, chips distinguíveis por borda, chip selecionado em `Highlight`, textura removida, badges com rótulo textual preservado |
| **`prefers-reduced-motion`** (não listado, mas verificado) | **Passa**, com uma exceção: durações vão a `1ms`/`0s`, o typing para e o rótulo "digitando…" assume. A exceção é o teaser (M6) |
| **Outros navegadores** | Continua **não verificado** — só Chromium 145 aqui também |
| **Leitor de tela real** | Continua **não verificado** |

---

## 9. O que um diretor de arte reprovaria

Sem contemplação, e separando o que é gosto do que é erro.

**Erros de ofício:**

1. **Dois níveis de navegação com a mesma voz** no mockup 23 (M5). Isso é hierarquia, não estilo.
2. **Três caixas concêntricas** na coluna esquerda do 23: cartão de seção → cartão "Conexão" → caixa
   cinza do hint "Onde achar". Três bordas e três fundos para dizer uma coisa. O sistema tem
   `--w-elev-0` e `wui-card--flat` justamente para evitar isso.
3. **O raio de painel (16 px) usado em cartão** nos mockups 20 e 21, contra a semântica que o próprio
   LEIA-ME §5.5 declara ("12 = campo e cartão · 16 = painel"). Cartões grandes com raio de 16 leem
   como "janela", não como "seção".
4. **Ritmo vertical sem eixo comum**: 1120 / 1200 / 1280 px de largura útil em três arquivos do mesmo
   conjunto. Não é perceptível numa tela; é gritante numa apresentação em sequência.
5. **A menor tipografia da tela carregando o dado mais técnico** (M9). Nome de campo do pré-chat a
   11,04 px é o oposto da hierarquia que a tela pede.
6. **O `<h1>` de 16 px** dos mockups 20 e 21 — o mesmo tamanho do `<h2>` da mesma página, e menor
   que o título de cartão em várias outras. O nome da caixa de entrada é a informação mais
   importante da tela e é a que menos pesa.

**Gosto, e digo que é gosto:** a prosa explicativa do 23 (M8) é boa escrita e péssima densidade para
uma tela de configuração recorrente. A minha recomendação seria mover 60% dela para um popover de
ajuda e manter na tela só a frase que muda a decisão. Mas é uma decisão de produto, não um defeito.

**O que está bom e não vou gastar mais espaço elogiando:** a tela 20 é a peça de configuração mais
bem resolvida do conjunto — o par de cartões Marketing/Suporte com o radio no canto, o seletor de cor
com o valor de luminância ao lado e o preview ao vivo formam uma unidade que se explica sozinha. Os
três mockups do widget têm alinhamento óptico, agrupamento e contenção de balão corretos em todas as
22 cenas que abri.

---

## 10. Veredito e o que conserta

**Estes mockups podem ser mostrados a um cliente?**

- **`10-widget-marketing`, `10-widget-suporte`, `10-widget-mobile` — sim, hoje.** Com uma frase de
  ressalva na demonstração: a cena "Digitando → resposta" precisa do botão "Repetir a animação" para
  ser vista.
- **`22-config-prechat-fluxo`, `23-config-tracking` — sim**, avisando que os botões de ação não
  respondem (G6) e que os três links de navegação ao lado não levam a lugar nenhum.
- **`00-sistema-visual` — sim, para público técnico.** Não é peça de cliente.
- **`20-config-perfil-aparencia`, `21-config-gatilhos` — não antes de duas correções de P**: as sete
  abas mortas (G6) e o corte do preview em zoom (G4). Os dois são **P**.
- **`index.html` — não.** É a porta de entrada e é a única página que contradiz o sistema que
  apresenta (G7). Se o cliente abrir por ela, a primeira impressão do "sistema visual" é uma página
  que não o usa.

**A lista mínima para o conjunto ficar à altura**, em ordem de retorno sobre esforço:

| # | O que | Esforço | Por quê |
|---|---|:--:|---|
| 1 | Ligar as 7 abas dos mockups 20/21 a `href` reais; trocar `aria-disabled` por um rótulo honesto no 22/23 | **P** | É o defeito que estoura numa demo ao vivo |
| 2 | `overflow: auto` no `.pv__palco` | **P** | Fecha SC 1.4.4 e 1.4.10 |
| 3 | Portar o `index.html` para a fundação | **P** | Remove 32 literais e a única página que se contradiz |
| 4 | `Esc` fecha o painel + foco entra ao abrir + foco volta ao launcher | **P** | Três itens do checklist 16 §8.3, e é comportamento, não pintura — precisa estar no mockup para chegar no código |
| 5 | Promover `.wchat-send`, `.wchat-chip`, `.wchat-branding__act`, `.wchat-csat__opt`, `.wchat-file__dl` a 44 px no bloco mobile | **P** | Fecha o item de aceite de alvos mobile |
| 6 | `border` real (não `box-shadow`) para skeleton, tooltip e ponto de presença em `forced-colors`; `--w-text-muted: CanvasText`; mapear os 18 tokens restantes | **P** | Três componentes voltam a existir em alto contraste |
| 7 | Criar `.wui-theme-light` / `.wui-theme-dark` no `tokens.css` e apagar as duas cópias de `.pv-*` | **P** | Elimina 50 das 83 cores literais **e** a dessincronização que já começou |
| 8 | Três tokens de título de página na fundação e aplicar nos 9 | **P** | Fecha os cinco `<h1>` |
| 9 | `aria-hidden="true"` no `#pvLauncher` (igual ao irmão); tirar o "(alvo de 32 × 32)" do rótulo ou compensar a escala; `type="button"` nos 43 botões do catálogo | **P** | Fecha o único `critical` e duas afirmações que a peça não sustenta |
| 10 | Escolher **um** shell de configuração e refazer o outro par (largura, raio de cartão, `<h1>`, navegação) | **M** | É o que transforma quatro telas em um produto |
| 11 | Fazer o preview do widget montar o markup do widget, em vez de uma segunda implementação | **M** | Fecha as 8 divergências do M3 de uma vez e impede a nona |

Os itens 1 a 9 são todos **P**, e nove P somados continuam sendo **P**. Feitos eles, o conjunto passa
de "muito bom com furos incômodos" para "pode ir para o cliente sem ressalva". Os itens 10 e 11 são
**M** e são o que separa "nove mockups bons" de "um sistema".

---

## 11. O que esta auditoria não verificou

Digo para não passar por completa:

- **Outros navegadores.** Chromium 145 apenas, como todo o resto do projeto.
- **Leitor de tela real.** Os `role` e rótulos foram lidos do DOM; nenhum NVDA/VoiceOver rodou.
- **SC 2.4.11 (Focus not obscured).** Exige rolar a página com foco ativo sob o painel flutuante.
- **Dispositivo móvel real.** Teclado virtual, `dvh` com barra de endereço e `overscroll-behavior`
  no Safari continuam fora de alcance em headless — a mesma lacuna que o 16 §8.5 já registra.
- **Os quatro planos** (`22`–`25`) e o `PLANO-MESTRE.md`. Esta task auditou os nove mockups; as
  afirmações dos planos que toquei foram só as que os mockups materializam.
- **Conteúdo e copy em pt-BR.** Li o suficiente para julgar densidade, não para revisar redação.
