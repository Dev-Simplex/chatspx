# Onda 5 · Balões e render — trilha `o1-bridge`

**Worktree:** `/home/chatwoot/chatwoot-o1-bridge` · **branch:** `o1-bridge`
**Data:** 19/08/2026 · **Autor:** único nesta branch

## O que foi entregue

| Commit | O quê |
|---|---|
| `21128153c7` | **2.04** — superfície da lista, textura, separador em pílula, auto-scroll condicional, botão "descer" |
| `0d1a2dfa42` | **merge** de `redesenho-integra` — o `v-memo` e o `AiHandoffMark` no mesmo `v-for` |
| `44971344cc` | **fix 2.12** — a alegação de que o `v-memo` estava medido não tinha lastro |
| `dc00c2e82f` | **2.08** — movimento, `prefers-reduced-motion`, `prefers-contrast`, `forced-colors` |
| `7fc33ddebe` | **regravação** dos 8 baselines da lista de conversa — e só os 8 |

Os commits `b8b8d3e07c` (2.03) e `c1ba616759` (2.12) já existiam e não foram refeitos.

---

## 1. O trabalho órfão: continuei, não descartei

O worktree tinha ~15 arquivos não commitados de uma instância anterior. **Li tudo antes de escrever
qualquer linha, concluí que prestava e continuei.** O que me convenceu não foi a aparência do
código: foi ter medido os vermelhos restaurando o código antigo, em vez de supor que os testes
cobriam o que diziam cobrir.

| Sabotagem aplicada | Medido |
|---|---|
| auto-scroll incondicional (o `updated()` de antes) | `scrollTop` 2000 onde o aceite exige 1200 |
| `handleScroll` sem throttle | 120 execuções/s contra o teto de 11 |
| textura de volta ao PNG antigo | 88.534 B contra o teto de 30.720 B, e assinatura PNG onde o exame exige RIFF/WEBP |

O único ajuste que fiz no que encontrei foi um comentário que citava um token inexistente
(`--w-surface-raised`); o código usa `n-solid-1`.

---

## 2. Bloco 2.04 — a lista

**Aceites:** mensagem chegando com o visitante 300 px acima não o arranca; textura < 30 KB.

- **300 px acima:** medido em Chromium (`spec/e2e/widget/scroll.spec.js`), o `scrollTop` não se
  move. A tolerância é 80 px — não 0, porque o navegador arredonda `scrollTop` em DPR fracionário;
  não 300, porque aí o salto voltaria para quem lê histórico.
- **Textura:** 24.354 B contra teto de 30.720 B. Eram dois PNG (88.534 B + 96.098 B) com o mesmo
  desenho em cores diferentes; virou **uma máscara** com a cor em token.

### O que os PNG de diff pegaram e nenhum teste pegaria

A textura nova estava **mais pesada que a original**. Medi amostrando a faixa de fundo sem balões:

| tema | superfície → traço (antes) | antes | com `0.15` |
|---|---|---|---|
| claro | (254,254,254) → (226,226,226) | 1,284:1 | **1,409:1** |
| escuro | (3,3,4) → (31,31,31) | 1,251:1 | **1,612:1** |

No escuro era ~30% mais forte. A causa: **um único `0.15` servia os dois temas, e o olho não compõe
igual nos dois sentidos** — clarear um fundo escuro pesa mais que escurecer um claro com a mesma
opacidade. A opacidade passou a ter valor por tema (`0.11` e `0.075`), resolvido para reencontrar a
régua original. Medido de volta: **1,280:1 e 1,251:1**.

E criei o aceite que faltava, porque *"leve" sem régua é adjetivo*: teto de **1,30:1** no traço
composto, de `getComputedStyle`, nos dois temas. Vermelho medido restaurando `0.15`.

---

## 3. Bloco 2.08 — movimento e as três preferências

`prefers-reduced-motion` **não é "desligar animação"**. É entregar o mesmo estado final sem o
percurso. O botão "descer" troca o `behavior` do `scrollTo` de `smooth` para `auto`: quem pediu
menos movimento **continua chegando ao fim**. O par de exames prova isso **pelo destino** — os dois
terminam em `scrollTop` 2000 e só o percurso difere. Um exame que só afirmasse o `behavior` seria
satisfeito por uma implementação que não rola.

| Preferência | Efeito | Medido em Chromium |
|---|---|---|
| `prefers-reduced-motion: reduce` | `animation-duration: 0s`, estado final preservado | opacity 1, transform `none`, duração `0s`; sem a preferência, `0.16s` |
| `forced-colors: active` | textura fora, borda em `CanvasText` | textura `none`, borda `1px rgb(0,0,0)` — e lista e balão **ambos** `rgb(255,255,255)`, o que mostra que sem a borda o balão sumiria |
| `prefers-contrast: more` | textura fora, borda cumprindo 1.4.11 | **3,035:1** no claro (`#8a8a8a`), **3,029:1** no escuro (`#6c6c6c`) |

Isso cobra a promessa que o 2.03 deixou escrita e adiou: sem a preferência a borda do escuro mede
1,72:1, e subir para todos seria um contorno visível em volta de cada balão — decisão de desenho que
o plano não tomou. **Com a preferência ligada, quem tomou foi o visitante.** Os dois valores são o
cinza *mais próximo da superfície* que ainda atinge 3:1: cumprir o mínimo mantém o desenho o mais
perto possível do original.

### Um defeito achado dentro do próprio verde

A primeira versão punha `border-color: #8a8a8a` direto na regra do balão sob `@media
(prefers-contrast: more)`. **Passava** — com 4,608:1 no escuro, porque a declaração direta vence o
`var()` e impunha a cor do claro aos dois temas, deixando o `#6c6c6c` como código morto. **O aceite
de 3:1 nunca pegaria isso: 4,6 é maior que 3.** Quem pegou foram os valores impressos pelo próprio
teste. As duas cores viraram token, por tema.

---

## 4. O merge: as duas features cabem, e o juiz não era juiz

O conflito em `ConversationWrap.vue` tinha uma armadilha silenciosa. Compilei as quatro formas com o
compilador do próprio Vue 3.5.12 e olhei se `_isMemoSame` aparece no código gerado:

| forma | `_isMemoSame` |
|---|---|
| A · `v-for` + `v-memo` no mesmo elemento (o 2.12) | presente |
| B · `v-memo` dentro do `<template v-for>` (a ingênua) | **ausente — ignorado em silêncio** |
| C · `v-memo` **no próprio** `<template v-for>` | presente |
| D · wrapper `<div>` real | presente |

Ficou **C**: o marcador continua irmão da mensagem (4.09 intacto), o memo continua ativo (2.12
intacto), e nenhum nó extra entra no DOM — o que D custaria, um `<div>` por linha, para sempre.
**Nada foi sacrificado, então não houve o que conciliar com a outra trilha.**

### O achado maior: o spec do 2.12 não media o `v-memo`

Os três exemplos de `memoDaLinha.spec.js` **passam com o `v-memo` removido por completo**. Não era
teste mal escrito — era **teste na camada errada**: o Vue já não re-renderiza um filho cujas props
não mudaram (`shouldUpdateComponent`), e o espião contava o render do *filho*, que já não acontecia.
O `v-memo` age uma camada antes, evitando **criar** o VNode — trabalho do *pai*, que espião nenhum
no filho enxerga.

O commit `c1ba616759` afirmava que estava medido. Corrigido por cima em `44971344cc`, sem reescrever
história.

### A armadilha que vale para qualquer teste sobre saída de compilador

A primeira versão do exame novo lia `ConversationWrap.render.toString()` e procurava `isMemoSame`.
**Passava nas duas formas, inclusive na quebrada.** Em dev o Vue **preserva os comentários do
template dentro da render function**, e o comentário que eu tinha acabado de escrever explicando a
armadilha diz `_isMemoSame` por extenso — o teste estava lendo a própria documentação e se
declarando satisfeito.

> **Asserção sobre código *gerado* passa a enxergar o código-*fonte* quando os comentários
> sobrevivem à compilação.** A correção é compilar o template com `comments: false`.

---

## 5. Defeito de junção

`aiHandoff.spec.js` (bloco 4.09) stubava `DateSeparator`, que o 2.04 substituiu por
`WDateSeparator`. Com o nome antigo **o stub não pega**, o componente real monta e `formatDate`
estoura com `Invalid time value` na data simbólica `'hoje'` do arquivo. **Dez exemplos vermelhos,
zero defeito de produto.** Um stub que deixa de pegar não falha dizendo "stub não aplicado" — falha
no componente real, apontando para o lugar errado. É ponta de contrato do meu bloco (eu renomeei o
componente), então a correção foi minha.

---

## 6. Achado de harness — vale para qualquer trilha que meça preferência de mídia

**`test.use({ reducedMotion, forcedColors, contrast })` não chega ao contexto no projeto `widget`
deste repositório.** Medido: com ele, as três consultas respondem `false` dentro *e* fora do iframe;
com `page.emulateMedia()`, respondem `true`.

Isso é a diferença entre emular e *achar* que emulou. Um arquivo escrito com `test.use` passa em
todas as asserções que esperem o comportamento padrão e falha só nas que exigem a preferência — o
sintoma é o produto parecer não ter as regras.

---

## 7. Os 8 snapshots — e os 6 que não são meus

Os 8 de `messages` e `rich-types` foram regravados por três causas, todas viradas em asserção
numérica **antes** da regravação (`superficie.spec.js`): superfície tokenizada, pílula
(156×24, raio 9999px, `<time>`, sem altura fixa) e padding 16/12/8. `home`, `prechat-form` e
`unread` seguem **byte-idênticos**, conferidos por md5 — é a lista do que *não* mudou que prova o
escopo.

### `--update-snapshots` não se limita ao que mudou

**`--update-snapshots` regrava tudo que a corrida tocou, não só o que falhou.** Ele reescreveu
**14 dos 20**. Quem confia nele e commita o resultado leva junto qualquer baseline que estivesse
desatualizada por outro motivo — e o commit fica com a assinatura de quem rodou.

Conferi os 6 extras por pixel esperando recompressão; não era:

| baseline | pixels diferentes |
|---|---|
| `home-light-mobile` | 16.050 (4,88%) |
| `home-dark-mobile` | 24.377 (7,41%) |
| `prechat-form-light-desktop` | 58.851 (26,09%) |
| `prechat-form-light-mobile` | 89.194 (27,10%) |
| `prechat-form-dark-desktop` | 67.680 (30,00%) |
| `prechat-form-dark-mobile` | 89.196 (27,10%) |

Revertidos com `git checkout` e reconferidos por md5. Rodando os 20 de novo, **os 6 falham de
verdade** — acima do teto de 0,01 da config. Não são meus: não toquei em `home` nem em `prechat`, e
nenhum dos dois cenários passa por `ConversationWrap`.

Os 4 de prechat rastreiam para `87d1fd6333 — feat(3.15)`, que alterou 155 linhas de
`PreChat/Form.vue` e **não tocou em nenhum baseline**. Passou porque, entre aquele commit e esta
corrida, **ninguém rodou os 20** — aquele bloco não previa harness. O deslocamento do `home` mobile
é no cabeçalho, território do bloco **2.06**, de outra trilha. Ambos escalados ao coordenador, que
está roteando. **Não regravei o defeito de outra trilha por cima.**

**Sem a conferência por hash, seis arquivos de outras trilhas teriam entrado no meu commit sem
ninguém notar — e dois deles carregando um defeito real.**

---

## 8. Contratos (pontas de contato com outras trilhas)

| Chave | Tipo | Default | Na ausência |
|---|---|---|---|
| `--w-surface-sunken` | cor | declarada só no tema claro | fundo transparente; o balão perde a separação |
| `--w-texture-ink` | canais crus (`0 0 0`), consumidos por `rgb()` | por tema | `::before` sem cor, textura some |
| `--w-texture-opacity` | número | `0.11` claro / `0.075` escuro | `opacity: 1`, textura chapada |
| `--w-texture-size` | comprimento | `400px` | tile no tamanho natural da máscara |
| `--w-bubble-border` | cor | só no escuro; **nos dois** sob `prefers-contrast: more` | fallback `transparent` — correto no claro |
| `comportamentoDeRolagem()` | `'auto'` \| `'smooth'` | `'smooth'` | sem `matchMedia`, devolve `'smooth'`: a ausência da API não tira o movimento de todos |

`WDateSeparator` substituiu `DateSeparator` **dentro do widget**. Specs que montam
`ConversationWrap` precisam stubar pelo nome novo. O compartilhado continua no dashboard.

---

## 9. Estado dos testes

- **Unidade:** 124 arquivos, 1.416 exemplos, verde (widget + shared).
- **Chromium:** `scroll.spec.js` 3/3, `superficie.spec.js` 10/10, `movimento.spec.js` 6/6.
- **`widget.spec.js`:** 14/20 verde. Os 6 vermelhos são os pré-existentes da seção 7, **não** deste
  bloco.

Nenhum serviço externo foi acionado: o harness serve SDK, widget e host locais, e as mensagens são
injetadas por rota interceptada e por `commit` no store.

---

## 10. O que fica pendente

1. Os **6 baselines divergentes** de `home-*-mobile` e `prechat-form-*` — escalado, aguardando
   roteamento. A autoria do deslocamento do `home` mobile não foi rastreada.
2. `--update-snapshots` reescrevendo 14 de 20 é comportamento do Playwright 1.59 nesta config, não
   defeito desta trilha; quem for regravar baseline aqui precisa conferir por hash.
