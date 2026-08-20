# Onda 0 · Bloco 0.5 — o gate de peso que mede o GRAFO

> **Worktree:** `/home/chatwoot/chatwoot-redesenho-build` · **branch:** `redesenho-build`
> **Substitui:** o WIP `cd911c7682` (commitado interrompido e **não validado**)
> **Data:** 17/08/2026 · **Estado:** fechado, com todos os aceites executados por mecanismo.

---

## 0. O que este bloco entrega, em uma frase

O gate de peso do widget deixa de medir **a casca** (o chunk de entrada, 27.830 B gzip) e passa
a medir **o grafo** (o fecho transitivo dos imports estáticos, 422.599 B gzip). Com isso o teto
de 300 kB que já estava declarado no `package.json` aparece violado em **+122.599 B (+40,87%)** —
e o gate **nasce vermelho**, de propósito.

---

## 1. A decisão que mudou em relação ao WIP `cd911c7682`

O WIP no disco tinha o gate **verde**. Ele colocou `widgetGraphGzip: 422_599` — o próprio número
medido — e chamou isso de "teto de regressão", argumentando (no artefato anterior deste arquivo)
que a §2.2 nomeia só duas condições de falha e que o grafo seria apenas *reporte*.

O coordenador reabriu e decidiu o contrário, e a decisão está escrita na §12.3 do PLANO-MESTRE
**antes** desta execução:

> *"o bloco 0.5 deixa de ser 'instale um gate' e passa a ser 'instale um gate que vai nascer
> vermelho'. O teto de 300 kB não se afrouxa para acomodar o número; quem o baixa é o bloco 1.08."*

Executei essa decisão. O `LIMITS.widgetGraphGzip` voltou a **300.000 B** e o gate **falha** (exit 1)
desde o primeiro dia. Não é teto novo: é o mesmo número que o `size-limit` já declarava para
`public/vite/assets/widget-*.js` — cobrado agora do artefato certo.

**Registro honesto da tensão:** o risco **R17** do plano é exatamente *"o gate de peso é ligado com
tetos inalcançáveis → o time desliga o gate"*, e a mitigação que o plano previa era *"os 5 tetos
entram um a um, cada um junto da tarefa que o torna alcançável"* — o que sustentaria a leitura do
WIP. A decisão do coordenador é a outra, e ela endereça o R17 por outro caminho: **não pelo número,
pela mensagem** (seção 3). Deixo os dois lados escritos porque quem ler isto daqui a três meses
precisa saber que houve escolha, e qual.

---

## 2. Arquivos

| arquivo | o quê |
|---|---|
| `scripts/widget-size.mjs` | reescrito — teto 300 kB, linha de base do dia, trava do Leaflet por conteúdo, veredito que separa dívida de regressão |
| `package.json` | `size-limit` só com os dois orçamentos do `sdk.js`; `size` roda os **dois** gates sempre (era `&&`) |
| `.github/workflows/size-limit.yml` | dois steps, o do grafo com `if: always()`; comentário corrigido (o do WIP justificava o afrouxamento) |
| `playwright.strict.config.js` | **removido** — era instrumento de medição descartável, não fazia parte da suíte |

Nenhum arquivo de `app/`, `enterprise/`, `db/`, `config/` ou `spec/e2e/**` foi alterado. As
sabotagens tocaram `app/` temporariamente e foram revertidas byte-a-byte (seção 4).

---

## 3. Como o gate evita virar ruído sem afrouxar o teto

CI permanentemente vermelho treina gente a ignorar CI. A defesa **não** é baixar o teto — é a
mensagem. Toda falha se classifica em uma de duas listas:

- **DÍVIDA CONHECIDA** — já estava aqui, rastreada, com dono nomeado (o bloco **1.08**).
- **REGRESSÃO NOVA** — entrou agora; é de quem está lendo o vermelho.

E a dívida carrega a **linha de base do dia em que o gate nasceu** (422.599 B, 17/08/2026), sem a
qual piorar de 41% para 60% seria invisível — o gate vermelho ficaria cego. Saída real no estado
limpo:

```
    TETO (JS eager) ...   300.000 B gzip
    medido ............   422.599 B gzip
    ESTOURO ........... +122.599 B   (+40,87% acima do teto)

    ▸ DÍVIDA CONHECIDA E RASTREADA — isto NÃO é regressão sua.
      Este gate NASCE VERMELHO por decisão registrada antes da sua PR
      (PLANO-MESTRE §12.3). O `size-limit` antigo dizia verde porque
      media o chunk de entrada (27.830 B) em vez do grafo.
      O teto NÃO se afrouxa para acomodar o número.

      QUEM DERRUBA: bloco 1.08 — `content` próprio do Tailwind para o
      widget (...); depois o 2.18, que fecha o JS eager em ≤ 150 KB gzip.

    linha de base ..... 422.599 B gzip  (17/08/2026, ...)
    contra a base ..... +0 B (+0,00%)   tolerância de ruído de build: ±256 B

═══ VEREDITO ═══
VERMELHO · dívida conhecida apenas (1) — nenhuma regressão nova
  ...
  Nada do que está vermelho acima entrou com a sua mudança.
```

Quando há regressão junto, a mesma seção muda de voz e **divide o estouro** (medido na sabotagem
da seção 4.3):

```
    ▸ DESTE ESTOURO, +122.599 B JÁ EXISTIA — dívida conhecida da
      §12.3, rastreada, com dono (bloco 1.08). Os outros
      +43.533 B ENTRARAM COM A SUA MUDANÇA (ver logo abaixo).
    ...
    ▸ REGRESSÃO NOVA — O GRAFO PIOROU DEPOIS QUE O GATE NASCEU.
      A dívida herdada era +40,87% acima do teto; com a sua mudança são +55,38%.
```

No GitHub Actions (`GITHUB_ACTIONS=true`) a regressão nova sai como `::error` e a dívida como
`::warning` — o step falha nos dois casos, mas o que salta aos olhos é o que é acionável.

---

## 4. Aceites — cada um com o mecanismo que o executou

Todas as provas usam **`bin/vite build` / `pnpm build:sdk` reais**. Nenhuma usa manifest-fixture:
um gate provado contra artefato montado não está provado. (Fixtures aparecem só na seção 5, para
provar que o gate **aborta** em vez de reportar verde.)

### 4.1 (a) o gate reporta o grafo, não o chunk de entrada — **OK**

Build limpo do worktree, `bin/vite build`:

| medida | valor |
|---|---|
| módulos JS no fecho estático | **15** |
| JS eager | 1.295.718 B crus · **422.599 B gzip** (412,69 KiB) |
| CSS eager (2 arq.) | 1.693.678 B crus · 156.382 B gzip |
| **GRAFO TOTAL** | 2.989.396 B crus · **578.981 B gzip (565,41 KiB)** |
| chunk de entrada (o que o glob media) | 96.497 B crus · **27.830 B gzip** |
| fontes `.woff2` | 773.684 B crus (7 arq.) |

Razão grafo/casca em gzip: **20,8×**. É o falso verde que o bloco fecha.

### 4.2 (b) sabotagem do Leaflet → vermelho; desfeita → volta ao estado — **OK**

Esta prova rendeu **o achado mais importante do bloco**, e ela só rendeu porque foi feita com
build real. Foram três tentativas, e as duas primeiras corrigiram o desenho:

**Tentativa 1 — `import('leaflet')` → `import LStatic from 'leaflet'` no `LocationPickerModal.vue`.**
Gate ficou **verde**, e está **certo**: o modal é ele próprio lazy (`defineAsyncComponent` no
`ReplyBox.vue:47`), então o Leaflet virou import estático *de um chunk dinâmico* e continua fora do
first-paint. O Rollup **inlinou** os 149 KB dentro do chunk do modal
(`LocationPickerModal-*.js`: 12.781 B → 162.523 B). Sabotagem mal desenhada, não falha do gate.

**Tentativa 2 — a de cima + `ReplyBox.vue` importando o modal estaticamente.** Agora o Leaflet
entra no fecho eager de `entrypoints/dashboard.js`. Medido:

| | limpo | sabotado | delta |
|---|---|---|---|
| `dashboard-*.js` cru | 6.805.869 B | 6.978.349 B | **+172.480 B** |
| `dashboard-*.js` gzip | 1.628.209 B | 1.677.889 B | **+49.680 B** |
| ocorrências de `leaflet-container` | 0 | 1 | — |
| arquivos `leaflet-*.js` **no manifest** | 0 | **0** | — |

E aqui está o achado: **a trava nominal — a que o aceite da §2.2 pede palavra por palavra — ficou
VERDE.** O Rollup não recriou o chunk `leaflet-*.js`; inlinou o Leaflet dentro de
`assets/dashboard-Bv2q3s3W.js`, e nenhum arquivo com "leaflet" no nome sobrou no manifest. Quem
pegou foi a **trava por conteúdo**:

```
    (i)  nominal — `leaflet-*.js` no fecho estático
         OK — nenhum                                    ← FALSO VERDE
    (ii) por conteúdo — [leaflet-container, leaflet-pane] dentro do fecho
         FALHA — assets/dashboard-Bv2q3s3W.js carrega o Leaflet no fecho de entrypoints/dashboard.js
```

**O WIP `cd911c7682` estava cego para isso.** Ele *declarava* `LEAFLET_SIGNATURES` e descrevia o
ponto cego num comentário de 8 linhas — mas **a constante nunca era usada em lugar nenhum do
script**. Só a trava nominal existia. Implementei a (ii) neste bloco.

**Tentativa 3 (seção 4.3)** pôs o Leaflet direto no `entrypoints/widget.js`: aí o Rollup manteve o
chunk separado e **as duas travas pegaram** (`trava: nominal + conteúdo`) — o que confirma que os
dois modos ocorrem na prática e que nenhuma das duas travas é redundante.

**Desfeito e rebuildado**, o gate volta ao estado exato: Leaflet OK nas duas travas, grafo
**422.599 B gzip, +0 B contra a linha de base**. Reprodutibilidade byte-exata para o mesmo fonte.

### 4.3 (b-bis) sabotagem do grafo → regressão nova acusada — **OK**

Eixo que eu acrescentei; a regra "todo aceite numérico tem um mecanismo que o executa" me obriga a
prová-lo. `import LeafletNoWidget from 'leaflet'` no `entrypoints/widget.js`, build real:

| | limpo | sabotado |
|---|---|---|
| módulos JS | 15 | **16** |
| JS eager gzip | 422.599 B | **466.132 B** |
| contra a linha de base | +0 B | **+43.533 B (+10,30%)** |
| estouro do teto | +40,87% | **+55,38%** |

Veredito: `VERMELHO · 2 REGRESSÃO(ÕES) NOVA(S) + 1 dívida(s) conhecida(s)`. Revertido e rebuildado.

### 4.4 (c) `sdk.js` acima do teto → vermelho com delta contra 29.014 / 9.595 — **OK**

Duas sabotagens, cada uma isolando **um** teto, ambas com `pnpm build:sdk` real:

| sabotagem | cru | gzip | veredito |
|---|---|---|---|
| **C1** +15.600 chars compressíveis | **44.641 B** ✗ (teto 40.000, +4.641) | 9.794 B ✓ | falha só o cru |
| **C2** +9.000 chars base64 incompressível | 38.041 B ✓ | **16.628 B** ✗ (teto 15.000, +1.628) | falha só o gzip |
| **restaurado** | 29.014 B ✓ | 9.595 B ✓ | `DELTA cru +0 B · gzip +0 B` |

Delta contra a linha de base §12 impresso em bytes **e** em porcentagem nos dois casos
(C1: `cru +15.627 B (+53,86%)`; C2: `gzip +7.033 B (+73,30%)`).

**Cruzamento independente:** rodei `pnpm exec size-limit` sobre o mesmo artefato C2 — ele também
reprova o gzip e sai 1, por outro caminho de código. Os dois concordam no veredito e divergem no
número (17,34 kB × 16.628 B): compressores diferentes. No artefato limpo a divergência é de ~45 B
(9,64 kB × 9.595 B). Nenhuma das duas divergências chega perto de mover um veredito, mas ficam
registradas para quem comparar os dois logs.

### 4.5 (d) eslint e vitest não pioram

Ver seção 7.

---

## 5. O gate nunca sai verde por não ter conseguido medir

Quatro bordas, todas executadas. Aqui — e só aqui — uso manifest de fixture, porque o que se prova
é o **abort**, não um número:

| borda | esperado | obtido |
|---|---|---|
| manifest inexistente | exit 2 | **exit 2** |
| manifest sem `entrypoints/widget.js` | exit 2 | **exit 2** |
| import sem entrada no manifest (grafo incompleto) | exit 2 | **exit 2** |
| `sdk.js` ausente | falha, não "ignora" | **exit 1**, como regressão nova |

Além disso, medir com `--manifest`/`--sdk` fora dos caminhos do build imprime um aviso no topo —
*"NÃO vale como gate"* — para que nenhuma execução fora do build possa ser colada como prova.

---

## 6. Divergências entre número herdado e número medido

A task me deu números para reaproveitar e pediu que divergências fossem ditas. São quatro:

| origem | número herdado | medido por mim | comentário |
|---|---|---|---|
| task / §12 | JS eager **422.599 B gzip** | **422.599 B** | bate exato, em 3 builds limpos |
| §2.2 (aceite) | grafo **~575 KiB** | **565,41 KiB** | −1,7%; a ordem de grandeza é a mesma e o ponto do aceite se sustenta |
| §2.2 (aceite) | casca **76,53 kB** | **27,83 kB** | não bate com nada de hoje; o próprio §12.3 já corrigiu para 27,89 kB — o 76,53 é pré-merge |
| §12.3 | JS eager **416,28 kB gzip** (38% acima) | **422,60 kB** (40,87% acima) | +6,3 kB; a §12.3 é anterior ao build atual desta árvore |

**Ruído de build (achado novo).** O gzip do grafo **não** é bit-a-bit reprodutível entre builds de
códigos diferentes: cada chunk carrega no corpo os nomes hasheados dos seus imports e o próprio
`sourceMappingURL`, e trocar o hash muda a compressão. Medido re-hasheando os 15 arquivos do grafo
50 vezes: **amplitude de 57 B**, desvio de −10 a +47 B contra o real. Dois builds reais de códigos
ligeiramente diferentes deram 422.596 e 422.590. Já builds do **mesmo** fonte deram 422.599
**exato** nas três vezes.

Por isso o eixo de regressão declara **±256 B** de tolerância (~4,5× a amplitude medida, 0,06% do
valor): ruído de nome não dispara alarme, e qualquer mudança de código que mereça uma linha no CI
passa muito longe disso. **O teto de 300 kB não tem tolerância nenhuma** — a tolerância vive só no
eixo secundário, o de regressão contra a linha de base.

---

## 7. (d) Suítes de referência — não pioraram

| suíte | referência da task | medido | veredito |
|---|---|---|---|
| `pnpm eslint` | 786 problemas (103 errors, 683 warnings) | **786 problemas (103 errors, 683 warnings)** | **idêntico** |
| `pnpm exec vitest --no-watch` | 4586 passed, 0 failed | **4586 passed, 0 failed** (463 arquivos, 502 s) | **idêntico** |

Ambas rodaram na árvore final, depois de todas as sabotagens terem sido revertidas.

**Ressalva honesta sobre o escopo do eslint.** O script `pnpm eslint` do repositório cobre
`app/**/*.{js,vue}` — **não** cobre `scripts/`. Ou seja, `scripts/widget-size.mjs` não entra nesses
786 problemas, nem entrava quando era o WIP. Lintei o arquivo à parte:

- os erros de `prettier/prettier` **foram corrigidos** (`prettier --write`), e conferi que a saída
  do gate é byte-a-byte idêntica antes e depois da formatação;
- sobram **19 erros** de estilo do guia airbnb: 16 × `no-restricted-syntax` (`for...of`),
  1 × `no-continue`, 2 × `no-bitwise` (os `1 << 28` de `maxBuffer`). Não os persegui: o arquivo está
  fora do escopo do lint do repositório, e trocar `for...of` sobre `Set` por `reduce` pioraria a
  legibilidade de um script cuja clareza é metade do seu valor. **Não adicionei `eslint-disable`** —
  mascarar seria pior do que registrar. Fica anotado para quem um dia ampliar o escopo do lint.

O `lint-staged` também cobre só `app/**/*.{js,vue}` e `*.scss`, então o `pre-commit` do husky não
toca estes arquivos: o commit foi feito **sem `--no-verify`**.

---

## 8. Commit e estado do worktree

`92345fbcf6` — `chore(0.5): gate de peso mede o grafo e nasce vermelho no teto de 300 kB`.
Feito com `git reset --soft HEAD~1` + commit novo: **substitui** o WIP `cd911c7682`, que sai do
histórico da branch. Sem `--no-verify` (o `pre-commit` do husky rodou: `lint-staged` não encontrou
arquivos no seu escopo e o `check_vue_template_refs` conferiu 224 arquivos, 0 problemas). **Sem push.**

Depois do commit, o worktree tem apenas o que já estava sujo quando recebi a task:
`public/version.json` (reescrito por todo `bin/vite build`) e `test-results/` (untracked, de
rodadas de Playwright anteriores). Não toquei em nenhum dos dois. **Não rodei
`pnpm exec playwright test`** em momento algum.

### Como reproduzir

```bash
bin/vite build && pnpm build:sdk   # o gate exige artefato de build real
node scripts/widget-size.mjs       # relatório completo; exit 1 (dívida)
node scripts/widget-size.mjs --json
pnpm size                          # size-limit + gate, os dois sempre
```

---

## 9. O que fica pendente para outros blocos

1. **A dívida em si.** O gate fica vermelho até o **1.08** (`content` próprio do Tailwind:
   1.692.256 B de CSS eager com 7 `@font-face`) e o **2.18** (JS eager ≤ 150 KB gzip). Quando um
   deles fechar, quem o fechar **baixa `GRAPH_BASELINE.gzip`** — o gate imprime o valor novo e o
   lembrete quando detecta melhora acima da tolerância.
2. **`public/vite/assets/` não é limpo entre builds.** Sobraram artefatos de 13:39, 14:59, 15:16 e
   15:38 lado a lado durante as provas. O gate lê pelo manifest e é imune, mas qualquer medição por
   glob no diretório (inclusive a que o `size-limit` fazia) casa lixo de builds antigos. Vale um
   `rm -rf public/vite/assets` antes de medir; não mexi nisso porque é fora do escopo do bloco.
3. **O manifest não lista todos os chunks.** O `leaflet-src-*.js` (150.113 B) existia no disco,
   era importado por um chunk dinâmico, e **não aparecia no manifest** — nem como chave, nem em
   `imports`. Para o teto de *first-paint* isso é indiferente (esses chunks são, por definição,
   dinâmicos). Mas fica anotado: um futuro teto de peso **total** não pode ser construído só sobre
   o manifest.
