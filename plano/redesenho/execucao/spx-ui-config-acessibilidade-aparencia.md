# As 3 falhas de acessibilidade da tela de Aparência — o que era, o que virou

> **Trilha:** `spx-ui-config` · **Commit local:** `21e620f981` · **Data:** 27/08/2026
> **Base:** `20d8c8febe` (`spx-ui-config`), worktree `/home/chatwoot/chatwoot-spx-ui-config`
> **Nada foi empurrado, nenhum PR aberto, nenhuma VM tocada.**

## 0. O baseline, medido antes de escrever qualquer linha

```
npx playwright test --config=spec/e2e/appearance/appearance.playwright.config.js
→ 3 failed, 8 passed (4.7m)
```

| Teste | Tema | O que reprovava |
|---|---|---|
| `appearance.spec.js:71` | claro | 1 texto abaixo de 4,5:1 |
| `appearance.spec.js:142` | claro | 8 violações graves não-herdadas |
| `appearance.spec.js:142` | escuro | 7 violações graves não-herdadas |

O relatório do axe, com número e não descrição (rodado por um spec de diagnóstico temporário,
removido antes do commit):

**Claro — 8 novas, em 2 regras**

| regra | impacto | alvo | medida |
|---|---|---|---|
| `color-contrast` | serious | `.object-cover > .select-none` | `#008573` sobre `#ccf3ea` = **3.81** |
| `label` | **critical** | `#theme-light`, `#theme-dark`, `#theme-auto` | sem nome acessível |
| `label` | **critical** | `#position-left`, `#position-right` | sem nome acessível |
| `label` | **critical** | `#launcher-standard`, `#launcher-expanded_bubble` | sem nome acessível |

**Escuro — 7 novas:** as mesmas sete de `label`.

E as duas que a lista `HERDADAS` já cobria, que continuaram cobertas e **não** foram mexidas:
`.text-n-blue-11` (`#2dc46f` sobre `#f0f2f5` = 2.02) e `.scale-[0.98]` (`#2dc46f` sobre `#f5f6f6`
= 2.09) — as duas do `TabBar`.

Medição própria do teste `:71`, claro: `"SD"` `rgb(0,133,115)` sobre `rgb(204,243,234)` =
**3.8187:1**.

## 1. Defeito 1 — o avatar do preview, e por que ele é uma regressão de NOME

`next/avatar/Avatar.vue` escolhe o par de cores das iniciais assim:

```js
const index = props.name.length % AVATAR_COLORS.light.length;   // 6 pares de hex CRAVADOS
```

`WidgetFooter.vue` passava `name="C"` — um caractere, índice 1, par âmbar, que passava por acaso.
O commit `c9c376c587` trocou aquele "C" cravado pelo nome real da caixa, que é o certo (o preview
tem de mostrar o que o visitante vai ver). Só que `"Site da Simplex"` tem 15 caracteres, `15 % 6`
dá 3, e o índice 3 é o par teal `['#CCF3EA', '#008573']` — que são exatamente `--teal-4` e
`--teal-11`. **A Radix garante o step 11 em 4,5:1 contra os steps 1–3, não contra o 4.**

Ou seja: ninguém mexeu em cor. O defeito entrou por um **nome**, e teria voltado no próximo nome
de cliente com o comprimento errado. Corrigir a cor daquele par não resolveria — o sorteio
continuaria sem piso.

**A correção** fixa o par, em token e nunca em hex, em `widget-preview/previewAvatarAccent.js`:

```js
bg: 'rgb(var(--slate-4))',   text: 'rgb(var(--slate-12))',
darkBg: 'rgb(var(--slate-4))', darkText: 'rgb(var(--slate-12))',
```

Duas decisões que valem registro:

1. **Token, não hex.** `--slate-4`/`--slate-12` são reapontados por `.wp-theme-light` e
   `.wp-theme-dark` (`Widget.vue`), então o avatar segue o tema do **preview** — o que o cliente
   escolheu — e não o do painel. Consumir a custom property é o oposto de copiar a paleta: é a
   mesma fonte única que o D4 estabeleceu, e o `previewTokens.spec.js` já distingue as duas coisas.
2. **`darkBg`/`darkText` repetem a mesma var de propósito.** O `Avatar` aplica
   `dark:!bg-[var(--dark-bg)]` pela classe `.dark` do **painel**. Apontando as duas pontas para a
   mesma custom property, o painel escuro não sequestra o avatar de um preview claro — que é o
   defeito que esta onda inteira existe para não repetir.

Aplicado também em `WidgetTeaser.vue`: mesmo componente, mesmo sorteio, e ali o nome é o do
remetente, ainda mais livre.

## 2. Defeito 2 — sete radios sem nome acessível, e por que o remendo está no campo

`RadioCard.vue` renderiza o título num `<h3>` e o `<input type="radio">` ao lado, sem amarrar um ao
outro. O axe é explícito: *"does not have an implicit (wrapped) `<label>` … `aria-label` attribute
does not exist … `aria-labelledby` … does not exist"*.

A correção de raiz são três linhas no próprio componente — `id` no `<h3>`, `id` no `<p>` da
descrição, `aria-labelledby` no `input` — e resolveria **todo radio-cartão do painel** de uma vez.
`dashboard/components-next/radioCard/` não está no recorte desta trilha. Perguntei ao coordenador
por `orca orchestration ask`; **o pedido expirou em 18 minutos sem resposta**. Então o rótulo ficou
nos campos — `<label class="sr-only" :for>` em `ThemeModeField.vue` e `LauncherField.vue` —, que é
o remédio que o próprio axe pede, e a raiz **fica escalada**.

Duas escolhas de posicionamento, as duas medidas e não deduzidas:

- **O label mora dentro do grid.** `sr-only` posiciona em `absolute`, e um filho absoluto não é
  item de grid. Medido no navegador depois da mudança: o container continua com **3 filhos no
  fluxo**, `grid-template-columns: 280px 280px`, cartões nos topos `[328, 328, 430]` e larguras
  `[280, 280, 280]` — o `auto-fit` do bloco anterior não se mexeu. Os três labels: `position:
  absolute`, 1 px de largura.
- **`sr-only`, não visível.** O texto já está no `<h3>` do cartão. Repeti-lo na tela seria corrigir
  um defeito de leitor de tela criando um defeito de olho.

## 3. O que NÃO foi feito, de propósito

`spec/e2e/appearance/appearance.spec.js` **não foi tocado** (`git diff --stat` vazio para ele):

- nada entrou na lista `HERDADAS`;
- o limiar continua `item.razao < 4.5`;
- as tags continuam `['wcag2a', 'wcag2aa']`.

## 4. Os testes que acusam — o vermelho de cada um, provado

**`widget-preview/specs/previewAvatarAccent.spec.js`** não pergunta "passou um accent?" — essa
pergunta passa com qualquer cor. Ele lê `widget/assets/scss/_tokens_values.scss`, resolve as vars
do accent contra os valores reais dos dois mixins e mede a razão. Apontado para o par antigo:

```
× no tema claro o accent fica em 4,5:1 ou mais
  → expected 3.8186934358651348 to be greater than or equal to 4.5
```

**3.8187** — o mesmo número que o Chromium mediu na tela. A primeira asserção do arquivo é a
auto-verificação dessa conta, para o teste não passar medindo nada.

**`appearance/specs/radioCardLabels.spec.js`** exige, para cada radio, um `<label>` cujo `for` case
com o `id` **e** que tenha texto. Removidos os labels do `ThemeModeField`:

```
× os tres modos de tema tem `<label for>` com texto
  → o radio theme-light ficou sem nome acessivel: expected null to be truthy
× o rotulo nao aparece na tela — o texto ja esta no cartao
  → expected [] to have a length of 3 but got +0
```

## 5. O verde final

```
npx playwright test --config=spec/e2e/appearance/appearance.playwright.config.js
→ 11 passed (4.2m)                                    (era 3 failed, 8 passed)

npx vitest run app/javascript/dashboard/routes/dashboard/settings/inbox/widget/appearance/specs/ \
              app/javascript/dashboard/modules/widget-preview/specs/
→ Test Files 9 passed (9) · Tests 62 passed (62)

npx eslint <os 7 arquivos>  → 0 errors
```

Axe depois, pelo mesmo diagnóstico: **claro — 1 regra grave, 2 nós, os dois herdados**
(`.text-n-blue-11` 2.02 e `.scale-[0.98]` 2.09); **escuro — 0 regras graves**; e **0 textos abaixo
de 4,5:1 nos dois temas**.

## 6. Pendente, com dono fora desta trilha

1. **`RadioCard.vue` sem rótulo.** Três linhas resolvem o painel inteiro; feito isso, os
   `<label sr-only>` que deixei nos dois campos podem sair. Enquanto não for feito, o defeito segue
   de pé em toda outra tela que usa `RadioCard`.
2. **`RadioCard.vue` faz `:name="id"`** — cada radio recebe um `name` diferente, então não existe
   grupo de radio de verdade e a navegação por seta não anda entre as opções. Só registro; não é
   uma das 3 falhas.
3. **As duas herdadas do `TabBar`** continuam onde estavam, na lista, com o dono que já tinham.
