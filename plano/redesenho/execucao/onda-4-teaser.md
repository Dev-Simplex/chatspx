# Onda 4 · Trilha WIDGET — o teaser e os três níveis de abordagem

> **Worktree:** `/home/chatwoot/chatwoot-o1-widget` · **branch:** `o1-widget`
> **Blocos:** 4.06 (teaser) · 4.19 (degradação por familiaridade) · 4.20 (auto-open) · 4.21 (instrumentação)
> **Base:** merge de `redesenho-integra` (122 commits) sobre `a05846e7d5`, sem conflitos.
> **Data:** 19/08/2026
>
> **Regra que rege este arquivo:** todo aceite tem um **mecanismo executado**, e cada capítulo mostra
> a saída REAL do vermelho ANTES e do verde depois.

---

## ⚠️ ANTES DE UMA LINHA DE CÓDIGO — a folga do `sdk.js` é menos da metade da anunciada

O briefing desta trilha publicou **3.650 B gzip** de folga, citando o número que **eu mesmo** medi no
bloco 1.23. Aquele número estava certo **naquele dia**. Medi de novo logo após o merge, antes de
projetar qualquer coisa:

```
teto A13      15.360 B gzip
sdk.js HOJE   13.748 B gzip   (39.099 B crus)
FOLGA          1.612 B gzip   (10,5%)
```

**O merge acrescentou +2.038 B gzip ao `sdk.js`.** A folga real é **menos da metade** da anunciada.

**De onde veio** (`git diff --stat` no grafo do SDK, entre `a05846e7d5` e o merge):

| arquivo | linhas | no bundle? |
|---|---|---|
| `sdk/titleFlasher.js` | +71 | **sim** (bloco 4.11, piscar do título) |
| `sdk/bubbleHelpers.js` | +209 | sim |
| `sdk/IFrameHelper.js` | +124 | sim |
| `sdk/sdk.js` | +50 | sim |
| `sdk/constants.js` | +10 | sim |
| `shared/helpers/brMasks.js` | +475 | **não** — `grep` no artefato dá 0; é do dashboard/prechat |

Verifiquei o `brMasks` justamente porque 475 linhas assustam: ele **não** entra no SDK. Não há
gordura óbvia a cortar.

**Por que isto está no topo do relatório e não numa nota de rodapé.** O plano chama o 4.06 de *"o
maior consumidor de bytes do host em todo o plano"* e lista DOM + gatilho composto + cookie de
dispensa + avatar + chips + i18n + `all: revert`. **Projetar isso para 3.650 B e projetar para
1.612 B são dois projetos diferentes.** Descobrir no fim, com o código escrito, seria exatamente a
surpresa cara que o próprio briefing descreveu ao publicar a folga.

**Consequência de projeto, assumida sem pedir autorização:** o décimo aceite do 4.06 — *um
componente, duas formas; Discreto é o Chamativo com foto e chips ocultos por CSS* — deixa de ser
elegância e vira **necessidade aritmética**. Cada etapa terá o delta medido com `stash`, publicado
cru.

**Escalado ao coordenador** — o relay estava sem cliente no momento do envio, então fica aqui, que é
o que dura. Duas perguntas que são decisão dele, não minha:
1. Se 1.612 B não bastarem para os quatro blocos, a saída **não pode** ser subir o teto (a A13 é
   explícita). As saídas legítimas são **(a)** carregar parte sob demanda, como 5.08/5.09/5.10 já
   fazem, ou **(b)** cortar escopo declaradamente.
2. Vale revisar se o **4.11** (`titleFlasher`) precisava ser *eager*. Não é meu bloco e não encostei;
   registro apenas que ele está no arquivo que **100% dos visitantes de todos os sites** baixam,
   para piscar o título da aba.

---

## O contrato do 4.04, lido contra o código — **CASA**

O briefing pediu para conferir e escalar se divergisse. Não diverge:

| O que o contrato diz | O que o código faz | ✓ |
|---|---|---|
| Schema em `widget_triggers_schema.rb`, com `APPROACHES` e `MOBILE_APPROACHES` | `:17` `%w[discreet bold aggressive]`; `:20` `%w[discreet bold]` | ✓ |
| `approach_mobile` recusa `aggressive` | o enum do schema (`:89`) não o inclui — 422 vem do próprio JSON Schema | ✓ |
| Falta o SDK consumir `widget_triggers` | `grep` em `sdk/` e `entrypoints/` → **nada**. É o meu bloco | ✓ |

E uma verificação que o contrato não pedia, mas que o meu próprio defeito do 1.02 ensinou a fazer —
**os dois montadores de config emitem a chave**:

```
show.html.erb:60             widgetTriggers: <%= …resolved_widget_triggers.to_json… %>
create.json.jbuilder:46      json.widget_triggers @web_widget.inbox.resolved_widget_triggers
```

A paridade está de pé dos dois lados. Se estivesse só no ERB, o 4.06 morreria no dia em que o
`widgets_controller` for apagado — que é o TODO do upstream que derrubou o meu 1.02.


---

## 4.06 — O teaser, e o achado que o pagou

**Veredito: FECHADO** · commit `c7a0c2641f` · **delta no `sdk.js`: −1.035 B gzip**

O bloco que o plano chama de *"o maior consumidor de bytes do host em todo o plano"* fechou
**devolvendo** bytes ao orçamento. Não por mágica — pela sequência abaixo, que vale mais registrada
do que o resultado.

### A sequência, com os números de cada passo

| passo | `sdk.js` gzip | delta |
|---|---|---|
| base pós-merge | 13.748 B | — |
| **+ teaser** (CSS + JS, escrito enxuto) | 15.648 B | **+1.900** ✗ estoura 288 B |
| tentativa de `import()` dinâmico | 15.731 B | **+1.983** ✗ pior |
| **+ documentação para fora da string** | **12.713 B** | **−1.035** ✓ folga 2.647 B |

### Por que o `import()` dinâmico não funciona no SDK — medido, não suposto

`vite.lib.config.ts` usa **`inlineDynamicImports: true`**, e o comentário do próprio arquivo explica:
o SDK precisa ser **um IIFE único**. O import dinâmico foi **inlinado** e ainda somou o overhead do
wrapper — piorou. Fica registrado para quem propuser isso de novo: **carregar sob demanda no SDK
exige mudar o contrato de entrega** (servir um segundo arquivo), e isso não é decisão de executor.

### O achado: comentário dentro de template string é **dado**, não comentário

`SDK_CSS` é uma template string. **O minificador não remove comentário de dentro de string.**

```
5.616 B crus de comentário dentro do SDK_CSS  =  2.924 B gzip no artefato
```

**Mais que a folga inteira do teto**, baixado por 100% dos visitantes de todos os sites de todos os
clientes — desde sempre. Havia comentário meu, dos blocos 1.05 e 1.07, e de outros blocos: a conta é
coletiva e a minha parte é grande.

**Nenhuma documentação foi apagada.** Os 13 blocos foram movidos para um comentário JS **antes** da
constante, cada um ancorado no seletor que explica. O minificador remove de lá; o fonte continua
documentado. Conferido no artefato: `TEASER`, `lançador` e `armadilha` → **0**; `woot-teaser` → **16**
(o CSS sobreviveu inteiro). E o check de browser ganhou uma **guarda** que falha se voltar comentário
para dentro da string.

### Os aceites, e os mecanismos que os executam

**jsdom** (`specs/teaser.spec.js`, 10 exemplos) — gatilho, cookie, montagem:

```
✓ 1.  oito segundos SOZINHOS não disparam — o gatilho é composto
✓ 1b. rolagem sozinha também não dispara
✓ 1c. com as DUAS condições aparece, e aparece uma vez só
✓ 1d. numa página que NÃO ROLA, o tempo basta — decisão declarada
✓ 2.  dispensado, grava cookie e não volta na próxima montagem
✓ 3.  com banner de cookie visível na página, não dispara
✓ 4.  o painel NÃO abre sozinho em nenhum caminho
✓ 6.  tem role="status" e NÃO recebe foco
✓ 8.  com teaserEnabled: false o código NÃO é montado
✓ 10. Discreto e Chamativo são o MESMO DOM, com classe diferente
```

**Chromium** (`specs/browser/teaser.check.mjs`, 10 asserções, **sem tocar no harness trancado**) —
o que só o navegador sabe: alvo de dispensa **44×44** (o do Olark tem 9,8×9,8), Discreto escondendo
foto e chip **por CSS**, `prefers-reduced-motion` zerando a transição, e a guarda dos comentários.

### Uma decisão que precisa de aval

**Em página que não rola, o tempo basta.** Exigir 30% de rolagem de uma landing de uma tela seria
exigir o impossível, e o teaser nunca apareceria ali. O aceite 1 protege contra aparecer para quem
abriu a aba e foi embora; nesse caso o sinal de presença é o tempo. Está em exemplo próprio
(`1d`), e se o produto preferir o oposto **é uma linha em `aoRolar`** — o exemplo vira o seu
contrário.

### O que veio de graça por respeitar o contrato

Zero dado novo na ponte: foto, texto e tempo de resposta já viajavam em `chatwootWebChannel`. Zero
biblioteca. E o contrato do 4.04 ao pé da letra — `enabled` ausente significa **não disparar nada**, e
o nível vem **resolvido do servidor**: o host consome a decisão, não recalcula política. É a mesma
regra do 1.03 com a cor.

