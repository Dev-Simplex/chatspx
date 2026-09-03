# Onda 0 — Auditoria semântica do merge v4.16.2 · ÁREA A4: DASHBOARD + i18n

- **Worktree:** `/home/chatwoot/chatwoot-redesenho-merge` · **branch** `redesenho-merge`
- **SHAs:** BASE `899fce1c92` (v4.12.1) · NOSSO `f26db6ee81` · DELES `70e284a044` (v4.16.2) · MERGE `93571c69db` (HEAD)
- **Área:** 267 arquivos de `app/javascript/dashboard/` (84 i18n + 183 componentes)
- **Composição real do TSV da área:** 248 MERGE_REAL · 10 PEGOU_NOSSO · 5 APAGADO · 3 PEGOU_DELES · 1 IDENTICO
  > O briefing dizia "39 PEGOU_NOSSO · 6 APAGADO". A contagem real do
  > `area-front-dashboard.tsv` é a de cima — os números do briefing são de outro recorte.
  > Auditei 100% dos 19 não-MERGE_REAL, como manda o método.

---

## PASSADA 1 — i18n (84 arquivos)

### Método

Script `i18n_keys.py`: para cada arquivo extrai as 4 versões via `git show <sha>:<path>`,
achata o JSON em conjunto de chaves totalmente qualificadas (`A.B.C`), e compara
**conjuntos de chaves**, não valores. Três classificações de perda:

- `lost` = chaves em NOSSO ausentes no MERGE
- `lost_ours` = subconjunto de `lost` que **não existia na BASE** → customização ChatSPX destruída
- `lost_upstream_removed` = subconjunto de `lost` que existia na BASE e o upstream removeu de propósito

### Resultado agregado — a boa notícia

```
84 arquivos i18n auditados
11 chaves perdidas no total (3 em pt_BR/integrations.json, 8 em en/integrations.json)
 0 chaves com lost_ours  → NENHUMA string criada pelo ChatSPX foi destruída pelo merge
 0 arquivos i18n desaparecidos
 0 locales desaparecidos (56 → 57; o upstream ADICIONOU `uz`)
+2 arquivos por locale: onboarding.json e sessionLimit.json (pt_BR já vem traduzido)
```

**Verificação cruzada executada:** `lost - lost_upstream_removed - lost_ours = ∅` em todos os
84 arquivos. Ou seja, **toda** chave perdida é remoção deliberada do upstream v4.16.2, nenhuma
é acidente do merge.

### As 11 chaves perdidas, uma a uma

| chave | arquivo | existia na BASE? | upstream removeu? | usada por componente no MERGE? |
|---|---|---|---|---|
| `CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.LABEL` | pt_BR + en | sim | sim | **não** (órfã) |
| `CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.DESCRIPTION` | pt_BR + en | sim | sim | **não** (órfã) |
| `CAPTAIN.DOCUMENTS.RELATED_RESPONSES.DESCRIPTION` | pt_BR + en | sim | sim | **não** (`DocumentDetails.vue:72,359` usa `.TITLE` e `.EMPTY`, que sobreviveram) |
| `CAPTAIN.RESPONSES.PENDING_FAQS` | **só en** | sim | sim | não — porque `Pending.vue` foi apagado |
| `CAPTAIN.RESPONSES.BULK_APPROVE_BUTTON` | **só en** | sim | sim | não — idem |
| `CAPTAIN.RESPONSES.BULK_APPROVE.SUCCESS_MESSAGE` | **só en** | sim | sim | não — idem |
| `CAPTAIN.RESPONSES.BULK_APPROVE.ERROR_MESSAGE` | **só en** | sim | sim | não — idem |
| `CAPTAIN.RESPONSES.EMPTY_STATE.NO_PENDING_TITLE` | **só en** | sim | sim | não — idem |

Verificação de uso (`git grep <chave> 93571c69db -- '*.vue' '*.js'`) devolveu **vazio** para
todas as cinco chaves acima. Nenhuma tela do merge mostra chave crua *hoje*.

### ACHADO i18n-1 — RISCO: assimetria `en` × `pt_BR` no fluxo de FAQ pendente

Confirmado por leitura direta do MERGE:

```
en/integrations.json    @93571c69db → CAPTAIN.RESPONSES.PENDING_FAQS        = null (removida)
                                      CAPTAIN.RESPONSES.BULK_APPROVE        = null (removida)
                                      CAPTAIN.RESPONSES.EMPTY_STATE.NO_PENDING_TITLE = null

pt_BR/integrations.json @93571c69db → CAPTAIN.RESPONSES.PENDING_FAQS        = "FAQs pendentes"
                                      CAPTAIN.RESPONSES.BULK_APPROVE        = {SUCCESS_MESSAGE, ERROR_MESSAGE}
                                      CAPTAIN.RESPONSES.EMPTY_STATE.NO_PENDING_TITLE = "Não há mais FAQs pendentes para revisão"
```

Os outros 54 locales (`am`, `ar`, `az`, `bg`, `bn`, `ca`, `cs`, `da`, …) **também mantiveram**
as chaves — confirmado em `integrations.json:1088` / `:1097` / `:1163` de cada um. É o padrão do
upstream: ele remove só de `en` e deixa os locales traduzidos órfãos até a próxima sync do Crowdin.

**Por que isso é RISCO e não OK:** este é o par exato do ACHADO 2 do coordenador
(`captain/responses/Pending.vue` apagado). Quando o fix restaurar o `Pending.vue`, ele vai
referenciar chaves que **só existem em pt_BR**. Um agente com a conta em inglês verá
`CAPTAIN.RESPONSES.PENDING_FAQS` literal na tela. **O fix do achado 2 está incompleto sem
restaurar as 5 chaves de `en/integrations.json`.**

### ACHADO i18n-2 — DÍVIDA (não é perda): 95 chaves novas do upstream sem pt_BR

Checagem inversa (`ptbr_debt.py`): chave presente em `en@MERGE`, ausente em `pt_BR@MERGE`,
e que **não existia** em `en@NOSSO` (logo, é chave nova trazida pelo v4.16.2).

| arquivo | faltam em pt_BR | NOVAS do upstream | pré-existentes |
|---|---|---|---|
| `inboxMgmt.json` | 46 | **46** | 0 |
| `integrations.json` | 31 | **31** | 0 |
| `conversation.json` | 20 | **14** | 6 |
| `settings.json` | 4 | **4** | 0 |
| `integrationApps.json` | 7 | 0 | 7 (dívida anterior ao merge) |
| **TOTAL** | 108 | **95** | 13 |

Blocos afetados (regra da casa: pt-BR é prioridade, toda string nova entra em pt_BR **e** en):

```
CONVERSATION.CAPTAIN_GENERATION.*            12 chaves  ← geração de resposta por IA na conversa
INBOX_MGMT.ACCOUNT_HEALTH.*                  46 chaves  ← tela de saúde do número WhatsApp (nova)
CAPTAIN.FAQ_SUGGESTIONS.*                    24 chaves  ← substituto do fluxo "pending" no upstream
CAPTAIN.RESPONSES.SUGGESTIONS_BANNER.*        2 chaves
CONVERSATION.CARD_CONTEXT_MENU.*              2 chaves
DATA_IMPORTS.ALERTS/TABLE.*                   3 chaves
APP_GLOBAL.ACCOUNT_SUSPENDED / CAPTAIN.OVERVIEW.KNOWLEDGE / CAPTAIN.RESPONSES.ERRORS + resto
```

Nota de leitura: `CAPTAIN.FAQ_SUGGESTIONS.*` (24 chaves novas, sem pt_BR) é **o que o upstream
pôs no lugar** do fluxo `RESPONSES` pendente que ele apagou. Quem for corrigir o achado 2
precisa decidir antes: restaurar o nosso fluxo `pending`, adotar o `FAQ_SUGGESTIONS` deles, ou
manter os dois. A dívida de tradução muda conforme a decisão.

### Valores alterados em pt_BR — todos legítimos

15 chaves mudaram de valor em `pt_BR`/`en`/`pt` sem sumir. Em **todas**, `BASE == NOSSO` e
`MERGE == DELES` — ou seja, nós nunca tínhamos tocado nelas e o merge apenas aceitou o texto
novo do upstream. **Nenhuma regressão de português para inglês.** Exemplos verificados:

```
pt_BR/integrations.json  CAPTAIN.PLAYGROUND.HEADER      "Playground"          → "Área de testes"     (melhora)
pt_BR/report.json        BOT_REPORTS...RESOLUTION_RATE  "Tempo de resolução"  → "Taxa de resolução"  (correção real: a métrica é taxa, não tempo)
pt_BR/chatlist.json      CHAT_LIST.LINK_TO_STORY        "Vá para o Story"     → "Ir para o Story"
pt/conversation.json     CONVERSATION.REPLYBOX.COPILOT_THINKING  "Copilot is thinking" (EN cru) → "Copiloto está pensando"  (upstream traduziu; ganho)
```

### Locales que não usamos

Confirmado que **não sumiram** e que **não perderam chaves**: `hy` (94 valores traduzidos pelo
upstream), `ms` (260), `zh_TW` (247 + 123 em generalSettings), `am` (42), `tl` (11), e os 45
demais com 2 chaves novas cada. `zh_TW/generalSettings.json` é o único `PEGOU_DELES` de i18n
da área — 123 valores traduzidos, 0 chaves perdidas, 0 chaves nossas: **OK**.

### Tabela por arquivo — 84 de 84

| arquivo | classe triagem (linhas nossas) | veredito | o que se perdeu | evidência | correção proposta |
|---|---|---|---|---|---|
| `i18n/locale/en/conversation.json` | MERGE_REAL (749) | OK | - | 855 chaves NOSSO / 900 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/conversation.json` | MERGE_REAL (745) | OK | - | 849 chaves NOSSO / 882 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/automation.json` | MERGE_REAL (515) | OK | - | 517 chaves NOSSO / 522 MERGE / 0 perdidas | - |
| `i18n/locale/en/automation.json` | MERGE_REAL (515) | OK | - | 517 chaves NOSSO / 522 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/integrations.json` | MERGE_REAL (473) | RISCO | CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.DESCRIPTION; CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.LABEL; CAPTAIN.DOCUMENTS.RELATED_RESPONSES.DESCRIPTION | 901 chaves NOSSO / 1022 MERGE / 3 perdidas | ver seção CORREÇÕES |
| `i18n/locale/en/integrations.json` | MERGE_REAL (414) | RISCO | CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.DESCRIPTION; CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.LABEL; CAPTAIN.DOCUMENTS.RELATED_RESPONSES.DESCRIPTION; CAPTAIN.RESPONSES.BULK_APPROVE.ERROR_MESSAGE; CAPTAIN.RESPONSES.BULK_APPROVE.SUCCESS_MESSAGE; CAPTAIN.RESPONSES.BULK_APPROVE_BUTTON; CAPTAIN.RESPONSES.EMPTY_STATE.NO_PENDING_TITLE; CAPTAIN.RESPONSES.PENDING_FAQS | 890 chaves NOSSO / 1036 MERGE / 8 perdidas | ver seção CORREÇÕES |
| `i18n/locale/pt_BR/settings.json` | MERGE_REAL (344) | OK | - | 814 chaves NOSSO / 926 MERGE / 0 perdidas | - |
| `i18n/locale/en/settings.json` | MERGE_REAL (311) | OK | - | 813 chaves NOSSO / 929 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/report.json` | MERGE_REAL (219) | OK | - | 513 chaves NOSSO / 531 MERGE / 0 perdidas | - |
| `i18n/locale/en/report.json` | MERGE_REAL (219) | OK | - | 513 chaves NOSSO / 531 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/inboxMgmt.json` | MERGE_REAL (156) | OK | - | 801 chaves NOSSO / 869 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/contact.json` | MERGE_REAL (122) | OK | - | 475 chaves NOSSO / 481 MERGE / 0 perdidas | - |
| `i18n/locale/en/contact.json` | MERGE_REAL (120) | OK | - | 475 chaves NOSSO / 481 MERGE / 0 perdidas | - |
| `i18n/locale/en/inboxMgmt.json` | MERGE_REAL (85) | OK | - | 764 chaves NOSSO / 876 MERGE / 0 perdidas | - |
| `i18n/locale/pt/conversation.json` | MERGE_REAL (53) | OK | - | 325 chaves NOSSO / 358 MERGE / 0 perdidas | - |
| `i18n/locale/lt/conversation.json` | MERGE_REAL (30) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/fr/conversation.json` | MERGE_REAL (30) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/zh_TW/general.json` | MERGE_REAL (28) | OK | - | 29 chaves NOSSO / 29 MERGE / 0 perdidas | - |
| `i18n/locale/zh_TW/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 363 MERGE / 0 perdidas | - |
| `i18n/locale/zh_CN/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/vi/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ur_IN/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ur/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/uk/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/tr/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/tl/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/th/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ta/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/sv/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/sr/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/sq/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/sl/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/sk/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/sh/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ru/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ro/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/pl/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/no/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/nl/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ne/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ms/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 363 MERGE / 0 perdidas | - |
| `i18n/locale/ml/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/lv/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ko/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ka/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ja/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/it/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/is/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/id/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/hy/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 363 MERGE / 0 perdidas | - |
| `i18n/locale/hu/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/hr/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/hi/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/he/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/fi/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/fa/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/et/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/es/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/el/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/de/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/da/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/cs/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ca/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/bn/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/bg/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/az/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/ar/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/am/conversation.json` | MERGE_REAL (28) | OK | - | 308 chaves NOSSO / 345 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/campaign.json` | MERGE_REAL (27) | OK | - | 133 chaves NOSSO / 135 MERGE / 0 perdidas | - |
| `i18n/locale/en/campaign.json` | MERGE_REAL (27) | OK | - | 133 chaves NOSSO / 135 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/chatlist.json` | MERGE_REAL (21) | OK | - | 74 chaves NOSSO / 76 MERGE / 0 perdidas | - |
| `i18n/locale/en/integrationApps.json` | MERGE_REAL (17) | OK | - | 39 chaves NOSSO / 40 MERGE / 0 perdidas | - |
| `i18n/locale/en/chatlist.json` | MERGE_REAL (15) | OK | - | 74 chaves NOSSO / 76 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/index.js` | MERGE_REAL (12) | OK | - | 1 chaves NOSSO / 1 MERGE / 0 perdidas | - |
| `i18n/locale/en/index.js` | MERGE_REAL (12) | OK | - | 1 chaves NOSSO / 1 MERGE / 0 perdidas | - |
| `i18n/locale/zh_TW/generalSettings.json` | PEGOU_DELES (7) | OK | - | 170 chaves NOSSO / 170 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/components.json` | MERGE_REAL (6) | OK | - | 28 chaves NOSSO / 39 MERGE / 0 perdidas | - |
| `i18n/locale/pt/settings.json` | MERGE_REAL (4) | OK | - | 584 chaves NOSSO / 696 MERGE / 0 perdidas | - |
| `i18n/locale/en/components.json` | MERGE_REAL (4) | OK | - | 28 chaves NOSSO / 39 MERGE / 0 perdidas | - |
| `i18n/locale/lv/settings.json` | MERGE_REAL (2) | OK | - | 580 chaves NOSSO / 692 MERGE / 0 perdidas | - |
| `i18n/locale/fr/helpCenter.json` | MERGE_REAL (2) | OK | - | 495 chaves NOSSO / 603 MERGE / 0 perdidas | - |
| `i18n/locale/fr/agentBots.json` | MERGE_REAL (2) | OK | - | 63 chaves NOSSO / 71 MERGE / 0 perdidas | - |
| `i18n/locale/pt_BR/macros.json` | MERGE_REAL (1) | OK | - | 72 chaves NOSSO / 76 MERGE / 0 perdidas | - |
| `i18n/locale/en/macros.json` | MERGE_REAL (1) | OK | - | 72 chaves NOSSO / 76 MERGE / 0 perdidas | - |
---

## PASSADA 2 — componentes (183 arquivos)

### Método (duas peneiras, porque a primeira mente)

**Peneira 1 — `lost_lines.py`:** extrai `git diff BASE NOSSO -- <f> | grep '^+'`, normaliza
whitespace, e testa se cada linha nossa ainda aparece no texto do MERGE.
Resultado bruto: 48 arquivos com ≥1 linha nossa ausente, liderados por
`ConversationCard.vue` com **337 de 400 linhas nossas ausentes (84%)**.

**Esse número é falso.** O upstream reescreveu o `ConversationCard.vue` de Options API para
`<script setup>`; as 337 "linhas perdidas" são em maioria `export default {`, `components: {`,
`props: {` — boilerplate que deixou de existir por mudança de sintaxe, não de comportamento.
Reportar 84% de perda ali seria mentira.

**Peneira 2 — `lost_symbols.py`:** em vez da linha, o **símbolo forte** — identificador,
classe CSS custom (`wa-*`, `ai-*`, `animate-*`), variável CSS (`--wa-*`), chave i18n
`MAIÚSCULA.PONTUADA`, literal hex de cor — que aparece nas nossas linhas adicionadas **e não
existe nem no BASE nem no DELES** (logo, só pode ter vindo de nós). Reduziu para 23 arquivos.

**Peneira 3 — filtro global:** todo símbolo ausente do seu arquivo é procurado no **repositório
inteiro do MERGE** (`git archive` da árvore + varredura em 5.616 arquivos). Símbolo achado em
outro arquivo = **migrou** (realocação legítima); símbolo ausente de tudo = **candidato a PERDA
real**. Restaram **29 símbolos** em 9 arquivos.

Foi essa terceira peneira que salvou o diagnóstico do `ChatList.vue` — ver abaixo.

### ACHADO A4-1 — RISCO MÁXIMO: o layout expandido renderiza um card SEM o isolamento por agente

Este é o achado mais grave da área e **não aparece em nenhuma das peneiras automáticas**, porque
nenhum arquivo nosso perdeu linha: o upstream inseriu um **caminho de renderização paralelo**.

Cadeia de renderização no MERGE:

```
ChatList.vue:11        import ConversationList from './ConversationList.vue'   ← arquivo NOVO do upstream
ConversationList.vue:37  const showExpandedCards = computed(
                           () => props.isOnExpandedLayout && isLgScreen.value)
ConversationList.vue:81  <ConversationItem :show-expanded="showExpandedCards" />
ConversationItem.vue:185 <ConversationCardExpanded v-if="showExpanded" ... />   ← card 100% UPSTREAM
ConversationItem.vue:203 <ConversationCard v-else ... />                        ← NOSSO card customizado
```

`ConversationList.vue` **não existe em NOSSO** — é arquivo novo trazido pelo v4.16.2. Em NOSSO,
`ChatList.vue` renderizava `ConversationItem` direto, e `ConversationItem.vue` tinha **um só**
card (`ConversationCard.vue`, o nosso). O merge aceitou o novo par de arquivos do upstream e com
ele o segundo card.

Verificação, símbolo a símbolo, do que `ConversationCardExpanded.vue` + `CardContent.vue` têm:

| customização ChatSPX | `ConversationCard.vue` (condensado) | `ConversationCardExpanded.vue` (expandido) |
|---|---|---|
| `useAgentIsolation` / `isMessageRestricted` → preview `🔒` | ✅ linha 42, 69–79 | ❌ **0 ocorrências** |
| chip de IA (`isAIAssignee`, `aiAccentVars`, `.ai-chip`) | ✅ linha 89–100, 221 | ❌ **0 ocorrências** |
| destaque âmbar "não atendida e minha" (`isUnattendedAndMine`, `animate-sidebar-attention`) | ✅ linha 103–113, 175 | ❌ **0 ocorrências** |
| `hasValidContent` + cadeia de fallback da última mensagem | ✅ linha 48–68 | ❌ `getLastMessage()` puro, linha 35 |

**Por que é alcançável — e por que já está ligado para parte da frota.** `isOnExpandedLayout` sai
de uma preferência gravada no banco:

```js
// routes/dashboard/conversation/ConversationView.vue:121
isOnExpandedLayout() {
  const { LAYOUT_TYPES: { CONDENSED } } = wootConstants;
  const { conversation_display_type: conversationDisplayType = CONDENSED } = this.uiSettings;
  return conversationDisplayType !== CONDENSED;
}
```

`conversation_display_type` vive em `users.ui_settings` e é alternado pelo botão do
`SwitchLayout.vue` no header da lista. `isLgScreen` = viewport ≥ **1024px**
(`constants/globals.js:59`) — a esmagadora maioria dos desktops de atendimento. Ou seja:
**todo agente da frota que em algum momento clicou em "expandir" já tem `expanded` gravado**, e
no primeiro carregamento após o deploy passa a ver o card do upstream — sem clicar em nada.

**A consequência que importa não é visual.** O isolamento por agente existe para impedir que o
agente A veja o conteúdo de mensagem restrita ao agente B. No card condensado o preview vira
`🔒`; no card expandido o preview mostra `getLastMessage(props.chat)` **cru**. O texto da última
mensagem restrita passa a ser legível na lista de conversas por quem não deveria lê-lo. Isso é
vazamento de conteúdo entre agentes, não perda de estilo.

**Severidade: RISCO (com efeito de vazamento).** Não é DADO — nada é gravado ou apagado errado —
mas é a única linha desta auditoria que muda quem consegue ler o quê.

### ACHADO A4-2 — o falso positivo que quase virou laudo: `ChatList.vue`

Registro porque ilustra o custo de parar na primeira peneira. Treze símbolos nossos somem do
`ChatList.vue` no MERGE: `TeamSelectionModal`, `showTransferTeamModal`,
`onConfirmAgentTransferTeam`, `cancelAgentTransferTeamSelection`, `showBulkAssignResolveDialog`,
`bulkAssignResolveRequiresTeam`, `bulkAssignResolveCount`, `onConfirmBulkAssignResolve`,
`onCancelBulkAssignResolve`, `CONVERSATION.SELECT_TEAM_FOR_TRANSFER_TITLE/DESCRIPTION`.

O composable `useBulkActions.js` do MERGE **continua com toda a lógica** (linhas 61, 157, 178,
237, 327–329, 406–409, 449, 474, e o `return` das linhas 501–512). Diagnóstico ingênuo: "state
setado, nenhum modal escuta, a ação em massa trava em silêncio".

**Errado.** O filtro global encontrou os consumidores no arquivo novo:

```
conversationBulkActions/Index.vue:7    import { useBulkActions } from '.../useBulkActions.js'
conversationBulkActions/Index.vue:65     onAssignTeamsForBulk: onAssignTeam,
conversationBulkActions/Index.vue:74–77  showBulkAssignResolveDialog, bulkAssignResolveRequiresTeam, onConfirmBulkAssignResolve
conversationBulkActions/Index.vue:240    :show="showBulkAssignResolveDialog"
```

O upstream inverteu o desenho: antes o `ChatList` chamava o composable e passava handlers por
prop/evento para o `Index.vue`; agora o `Index.vue` chama o composable ele mesmo e renderiza os
dois modais internamente. Como é a **mesma instância** de componente chamando `useBulkActions()`,
os `ref` batem. **Veredito: OK.** Nada se perdeu; tudo desceu um nível na árvore.

### ACHADO A4-3 — PERDA: persistência do estado de subgrupo da sidebar

`components-next/sidebar/SidebarSubGroup.vue` — MERGE = 183 linhas, DELES = 182. O único delta
sobre o upstream é o nosso null-guard do scroll:

```js
// MERGE, linha 112 (nosso, sobreviveu)
const container = scrollableContainer.value;
if (!container) return;
```

Tudo o mais que construímos foi descartado. Em NOSSO (`git diff BASE NOSSO`, linhas 39–90):

```js
const subgroupKey       = computed(() => `${props.parentName}/${props.name}`);
const sidebarSubgroupState = computed(() => uiSettings.value?.sidebar_subgroup_state || {});
const storedExpandedState  = computed(() => sidebarSubgroupState.value[subgroupKey.value]);
const isSubgroupExpanded   = computed(() => {
  if (hasActiveChild.value) return true;
  return storedExpandedState.value !== undefined ? storedExpandedState.value : true;
});
const setSubgroupExpanded = value => {
  updateUISettings({ sidebar_subgroup_state: { ...sidebarSubgroupState.value, [subgroupKey.value]: value } });
};
const toggleSubgroup = () => setSubgroupExpanded(!isSubgroupExpanded.value);
```

Confirmado: `grep -rn "sidebar_subgroup_state"` na árvore inteira do MERGE devolve **vazio**.
Os props `name` e `parentName` (que compunham a chave) também sumiram — o upstream passa
`:name="`${name}:${child.name}`"` mas não `parentName`, e no lugar da persistência fez o
subgrupo **herdar** `isExpanded` do grupo pai (`SidebarGroup.vue:401`).

Comportamento perdido: o agente que colapsava um subgrupo específico perde a preferência; todo
reload devolve o subgrupo ao estado do pai. Os valores já gravados em `users.ui_settings`
continuam no banco (nada é apagado) — ficam órfãos.

### ACHADO A4-4 — PERDA: o card de documento do Captain e o visualizador junto

Dois arquivos, um fluxo.

**(a) `components-next/captain/assistant/DocumentCard.vue`** — BASE 126 · NOSSO 116 ·
DELES 264 · MERGE 212. O merge adotou o card do upstream por inteiro:

```js
// MERGE, linhas 13–18 — tudo upstream
import Icon from '.../icon/Icon.vue';
import CardLayout from '.../CardLayout.vue';
import DropdownMenu from '.../dropdown-menu/DropdownMenu.vue';
import Button from '.../button/Button.vue';
import Checkbox from '.../checkbox/Checkbox.vue';
import DocumentSyncStatus from '.../DocumentSyncStatus.vue';
```

Nosso card (AiBadge/AiDropdown, ícone colorido `#1faa59` PDF / `#30b0c7` link, `statusInfo` com
TRAINED/PROCESSING/FAILED, clique no card abrindo o documento) foi 100% descartado. `AiBadge.vue`
e `AiDropdown.vue` continuam no repo, usados por outras telas de Agentes IA — a perda é só aqui.

Efeito colateral em i18n: `CAPTAIN.DOCUMENTS.STATUS.{TRAINED,PROCESSING,FAILED}` continuam nos
JSONs (pt_BR: "Treinado"/"Processando"/"Falhou") mas **nenhum `.vue` do MERGE as referencia** —
viraram chaves órfãs.

**(b) `routes/dashboard/captain/documents/Index.vue`** — três símbolos ausentes do repo inteiro:
`DocumentViewerModal`, `handleViewDocument`, `showViewer`. Nosso diff BASE→NOSSO tinha:

```js
import DocumentViewerModal from 'dashboard/components-next/captain/assistant/DocumentViewerModal.vue';
const showViewer = ref(false);
const handleViewDocument = () => { showViewer.value = true; };
// dentro de handleAction:
} else if (action === 'view') { handleViewDocument(); }
// no template:
<DocumentViewerModal v-model="showViewer" :captain-document="selectedDocument" />
```

No MERGE: `DocumentViewerModal.vue` **existe no repo** (2.354 bytes) e **nenhum arquivo o
importa** — `grep -rln "DocumentViewerModal"` na árvore devolve vazio. Componente órfão; a ação
"ver documento" morreu.

Sobreviveu: `FEATURE_FLAGS.CAPTAIN_V2` (linha 333) — a nossa troca de flag foi preservada.
Voltou o que tínhamos tirado: `LimitBanner` (linhas 24 e 390), o banner de limite de plano do
Chatwoot Cloud, agora visível na frota self-hosted.

### ACHADO A4-5 — PERDA: o preview de mensagem restrita perdeu o texto

`components/widgets/conversation/ConversationCard.vue`. Nosso computed (NOSSO, linhas 296–308):

```js
// Mensagem a exibir no preview. Se restrita por agente, troca o conteúdo por 🔒 +
// "Conteúdo restrito" e remove anexos/atributos, mantendo só quem enviou poder ver.
previewMessage() {
  const msg = this.lastMessageInChat;
  if (!msg || !this.isLastMessageRestrictedByAgent) return msg;
  return { ...msg, content: `🔒 ${this.$t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')}`, ... };
}
```

MERGE, linhas 69–79:

```js
const previewMessage = computed(() => {
  const message = lastMessageInChat.value;
  if (!message || !isMessageRestricted(message, props.inbox)) return message;
  return { ...message, content: '🔒', attachments: [], content_attributes: {}, content_type: 'text' };
});
```

O `t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')` sumiu: o preview passa de
"🔒 Conteúdo restrito" para um cadeado sozinho. A chave existe e está traduzida no MERGE
(`pt_BR/conversation.json:617` = "Conteúdo restrito") e segue em uso no `Message.vue:268` —
a regressão é só do card. Regressão pequena, correção trivial, mas é comportamento nosso que
sumiu sem o upstream ter pedido.

Falso positivo verificado no mesmo arquivo: `ai-badge-shimmer` "sumiu" porque o merge o
**renomeou** para `ai-chip-shimmer` (MERGE linhas 329, 332) e mudou a duração de 2,8s para 3,5s.
A animação e o `@media (prefers-reduced-motion: reduce)` estão lá. **OK.**

### ACHADO A4-6 — RISCO: `actionCable.js` chama um `computed` ref como se fosse função

Defeito **introduzido pelo merge**: não existe em nenhum dos dois lados isoladamente.

```js
// NOSSO   f26db6ee81:helper/actionCable.js:14   const isImpersonating = () => !!SessionStorage.get(SESSION_STORAGE_KEYS.IMPERSONATION_USER);
//                                        :129   if (isImpersonating()) return;          ✅ coerente

// DELES   70e284a044:helper/actionCable.js:18   const { isImpersonating } = useImpersonation();
//                                        :89    if (isImpersonating.value) return;      ✅ coerente

// MERGE   93571c69db:helper/actionCable.js:14   const { isImpersonating } = useImpersonation();   ← lado DELES
//                                        :144   if (isImpersonating()) return;                    ← lado NOSSO  ❌
```

`useImpersonation()` devolve um **`computed` ref**, não uma função:

```js
// composables/useImpersonation.js (idêntico nos três lados)
export function useImpersonation() {
  const isImpersonating = computed(() => SessionStorage.get(SESSION_STORAGE_KEYS.IMPERSONATION_USER));
  return { isImpersonating };
}
```

Chamar um `ComputedRefImpl` lança `TypeError: isImpersonating is not a function`.

**Onde estoura:** dentro de `onPresenceUpdate` — o handler que o ActionCable dispara a cada
broadcast de presença, constantemente e para todos os usuários logados. As três `dispatch`
seguintes (`contacts/updatePresence`, `agents/updatePresence`, `setCurrentUserAvailability`)
nunca executam. Efeito para o cliente: **os indicadores online/offline de agentes e contatos
congelam** no estado do carregamento inicial, e o GlitchTip da frota recebe o mesmo TypeError em
volume alto.

**Não há mecanismo que pegue isso hoje.** `helper/specs/actionCable.spec.js` mocka o composable
como `isImpersonating: { value: false }` (linha 13) — o mock está correto —, mas o spec **não
exercita `onPresenceUpdate`; nenhum `it()` o chama.** O bug passa verde. A correção precisa vir
com um teste que invoque o handler.

O outro consumidor no MERGE está certo: `SidebarProfileMenuStatus.vue:63` usa `isImpersonating.value`.

### ACHADO A4-7 — confirmação independente do DADO nº 1 (o purge das FAQ pendentes)

Auditei pelo lado do front e o laço fecha — com um detalhe que muda a leitura do risco.

**O upstream não matou o fluxo, ele o trocou de tabela.** A rota antiga não dá 404:

```js
// routes/dashboard/captain/captain.routes.js:97–104  (MERGE)
{
  path: frontendURL('accounts/:accountId/captain/:assistantId/faqs/pending'),
  redirect: to => ({ name: 'captain_assistants_faq_suggestions', params: to.params, query: to.query }),
},
```

A tela nova lê **outra tabela**:

```js
// api/captain/faqSuggestions.js
class CaptainFaqSuggestions extends ApiClient {
  constructor() { super('captain/faq_suggestions', { accountScoped: true }); }
```

```
db/migrate/20260713184351_create_captain_faq_suggestions.rb   → create_table :captain_faq_suggestions   (tabela NOVA, vazia)
enterprise/app/models/captain/faq_suggestion.rb               → modelo novo
```

E a migration do purge é irreversível, sem cópia:

```ruby
# db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb  (íntegra)
class PurgePendingCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def up
    execute('DELETE FROM captain_assistant_responses WHERE status = 0')
  end

  def down; end
end
```

**Não existe migration alguma que copie `captain_assistant_responses WHERE status = 0` para
`captain_faq_suggestions`.** Verificado arquivo a arquivo em `db/migrate` do MERGE.

Sequência real na frota: o `DELETE` apaga as FAQ pendentes vivas → o agente abre o link antigo →
é redirecionado para a tela nova → a tela consulta `captain_faq_suggestions`, que está vazia →
**não sobra rastro nem tela onde procurar**. `def down;end` significa que o rollback do Rails não
devolve nada. A única recuperação é backup de banco.

O que perdemos de nosso no `Pending.vue` em si é pequeno (2 linhas: `FEATURE_FLAGS.CAPTAIN` →
`CAPTAIN_V2` e a remoção do `LimitBanner`). O problema não é o arquivo; é o dado.

Liga com o **ACHADO i18n-1**: as 5 chaves `CAPTAIN.RESPONSES.*` do fluxo pendente foram removidas
de `en/integrations.json` e **mantidas em pt_BR e nos outros 54 locales**. Se a decisão for
restaurar o fluxo, restaurar as chaves de `en` faz parte do fix.

### ACHADO A4-8 — os PEGOU_NOSSO de voz: descarte coerente, verificado

O briefing apontava `VoiceCall.vue` (371 linhas do upstream descartadas), `useCallSession.js`
(317) e `FloatingCallWidget.vue` (184) como o maior descarte do merge, e pedia para confirmar se
o front descartado combina com o back aceito. **Combina.** Verificações:

| verificação | resultado |
|---|---|
| `enterprise/app/models/channel/voice.rb` no MERGE | ✅ existe |
| `db/migrate/..._drop_channel_voice.rb` e `..._add_voice_to_channel_twilio_sms.rb` (as duas do upstream) | ✅ **ausentes** do MERGE — descartadas, coerente |
| `app/models/channel/twilio_sms.rb` MERGE vs NOSSO | ✅ **idêntico** — não pegou os campos de voz do upstream |
| contrato que o front lê: `additional_attributes.call_status` / `call_direction` | ✅ continua sendo gravado — `voice/inbound_call_builder.rb:65`, `outbound_call_builder.rb:62`, `call_status/manager.rb:21`, `call_session_sync_service.rb:31` |
| `ConversationCard.vue` MERGE lê o contrato certo? | ✅ MERGE:84-85 usa `props.chat.additional_attributes?.call_status` (**nosso**) e descartou o `last.call.status` do upstream |
| assinatura de `getInboxIconByType` | ✅ MERGE:171 tem 3 params `(type, medium, variant='fill')` — o 4º (`voiceEnabled`) do upstream não entrou, e **nenhum** dos 30 chamadores passa 4 args |
| `FloatingCallWidget.vue` no path antigo | ✅ existe; `Dashboard.vue` importa `components/widgets/FloatingCallWidget.vue`, que o upstream tinha movido para `components-next/call/` |

**Conclusão: o RISCO que o briefing temia não se materializou.** O descarte foi consistente em
front, back, migrations e helpers. Duas sobras de higiene, sem efeito funcional:

- `components-next/Conversation/ConversationCard/VoiceCallStatus.vue` (versão do upstream) coexiste
  com o nosso `components/widgets/conversation/VoiceCallStatus.vue`. Props idênticos
  (`status`, `direction`) — sem risco de contrato. Cada card usa o seu.
- O teste `uses the voice glyph for a voice-enabled inbox`, que o upstream adicionou a
  `composeConversationHelper.spec.js`, foi descartado junto — correto, testaria comportamento que
  não temos.

### Nota de higiene (pré-existente, não é defeito do merge)

`Message.vue.backup` e `ConversationCard.vue.backup` estão versionados. Entraram pelo commit
`c42a446322 local: minhas alterações`, **já estavam em NOSSO** e não vieram do upstream. Registro
só porque o `ConversationCard.vue.backup` é a única fonte de `::v-deep` que sobrou na árvore e
polui grep de auditoria.

### Tabela por arquivo — 183 de 183

| arquivo | classe triagem (linhas nossas) | veredito | o que se perdeu | evidência | correção |
|---|---|---|---|---|---|
| `components/widgets/conversation/ReplyBox.vue` | MERGE_REAL (2311) | OK | - | 0 símbolos nossos ausentes (1417 linhas nossas verificadas) | - |
| `components/widgets/conversation/ConversationCard.vue` | MERGE_REAL (904) | PERDA | texto "Conteúdo restrito" no preview de msg restrita (só sobrou o cadeado) | MERGE:75 `content: '🔒'` vs NOSSO:303 `` `🔒 ${$t(...RESTRICTED_SUBTITLE)}` `` | C-5 |
| `components-next/sidebar/Sidebar.vue` | MERGE_REAL (794) | OK | - | 0 símbolos nossos ausentes (324 linhas nossas verificadas) | - |
| `components/widgets/WootWriter/CopilotMenuBar.vue` | MERGE_REAL (749) | OK | - | 0 símbolos nossos ausentes (322 linhas nossas verificadas) | - |
| `components/ChatList.vue` | MERGE_REAL (683) | OK | - | símbolos realocados: CONVERSATION.SELECT_TEAM_FOR_TRANSFER_DESCRIPTION, CONVERSATION.SELECT_TEAM_FOR_TRANSFER_TITLE, SELECT_TEAM_FOR_TRANSFER_DESCRIPTION | - |
| `components-next/message/Message.vue` | MERGE_REAL (621) | OK | - | 0 símbolos nossos ausentes (417 linhas nossas verificadas) | - |
| `routes/dashboard/conversation/ConversationAction.vue` | MERGE_REAL (513) | OK | - | 0 símbolos nossos ausentes (289 linhas nossas verificadas) | - |
| `store/modules/conversations/actions.js` | MERGE_REAL (513) | OK | - | 0 símbolos nossos ausentes (266 linhas nossas verificadas) | - |
| `components-next/message/MessageList.vue` | MERGE_REAL (467) | OK | - | 0 símbolos nossos ausentes (292 linhas nossas verificadas) | - |
| `components/widgets/conversation/ConversationHeader.vue` | MERGE_REAL (437) | OK | - | 0 símbolos nossos ausentes (289 linhas nossas verificadas) | - |
| `components/widgets/conversation/MessagesView.vue` | MERGE_REAL (416) | OK | - | símbolos realocados: renderiza, suficiente | - |
| `assets/scss/_next-colors.scss` | MERGE_REAL (373) | OK | - | 0 símbolos nossos ausentes (188 linhas nossas verificadas) | - |
| `composables/chatlist/useBulkActions.js` | MERGE_REAL (366) | OK | - | 0 símbolos nossos ausentes (180 linhas nossas verificadas) | - |
| `store/modules/specs/conversations/getters.spec.js` | MERGE_REAL (334) | OK | - | 0 símbolos nossos ausentes (63 linhas nossas verificadas) | - |
| `store/modules/conversations/index.js` | MERGE_REAL (330) | OK | - | 0 símbolos nossos ausentes (139 linhas nossas verificadas) | - |
| `components/widgets/conversation/components/GalleryView.vue` | MERGE_REAL (314) | OK | - | símbolos realocados: #25d366 | - |
| `routes/dashboard/conversation/contact/ContactInfo.vue` | MERGE_REAL (312) | OK | - | símbolos realocados: Action, Additional, Ambos | - |
| `api/inbox/message.js` | MERGE_REAL (311) | OK | - | 0 símbolos nossos ausentes (175 linhas nossas verificadas) | - |
| `components-next/NewConversation/ComposeConversation.vue` | MERGE_REAL (257) | OK | - | símbolos realocados: Always, Legacy, behavior | - |
| `store/modules/conversations/specs/mutations.spec.js` | MERGE_REAL (247) | OK | - | símbolos realocados: REMOVE_PENDING_MESSAGE | - |
| `assets/scss/_base.scss` | MERGE_REAL (246) | OK | - | 0 símbolos nossos ausentes (167 linhas nossas verificadas) | - |
| `store/modules/specs/conversations/actions.spec.js` | MERGE_REAL (236) | OK | - | 0 símbolos nossos ausentes (111 linhas nossas verificadas) | - |
| `components/widgets/WootWriter/ReplyBottomPanel.vue` | MERGE_REAL (221) | OK | - | 0 símbolos nossos ausentes (100 linhas nossas verificadas) | - |
| `components-next/NewConversation/components/ComposeNewConversationForm.vue` | PEGOU_NOSSO (205) | RISCO | descarte de voz correto, mas levou junto `w-full md:w-[42rem]` (responsividade mobile do modal) | DELES trocou `w-[42rem]` por `w-full md:w-[42rem]`; MERGE = NOSSO | C-8 |
| `store/modules/conversations/getters.js` | MERGE_REAL (193) | OK | - | 0 símbolos nossos ausentes (99 linhas nossas verificadas) | - |
| `components-next/Contacts/ContactsSidebar/ContactHistory.vue` | PEGOU_NOSSO (174) | OK | - | 0 símbolos nossos ausentes (98 linhas nossas verificadas) | - |
| `components-next/captain/assistant/DocumentCard.vue` | MERGE_REAL (148) | PERDA | card iOS/glass do Captain: AiBadge, AiDropdown, ícone #1faa59/#30b0c7, statusInfo, clique→visualizar | MERGE:13-18 importa CardLayout/DropdownMenu/Button/Checkbox/DocumentSyncStatus (upstream puro) | C-4 |
| `mixins/fileUploadMixin.js` | MERGE_REAL (145) | OK | - | 0 símbolos nossos ausentes (77 linhas nossas verificadas) | - |
| `components-next/Conversation/ConversationCard/ConversationCard.vue` | MERGE_REAL (141) | OK | - | 0 símbolos nossos ausentes (106 linhas nossas verificadas) | - |
| `store/modules/conversations/helpers/specs/actionHelpers.spec.js` | MERGE_REAL (134) | OK | - | 0 símbolos nossos ausentes (56 linhas nossas verificadas) | - |
| `routes/dashboard/settings/canned/EditCanned.vue` | MERGE_REAL (129) | OK | - | 0 símbolos nossos ausentes (99 linhas nossas verificadas) | - |
| `components-next/Contacts/ContactsDetailsLayout.vue` | MERGE_REAL (127) | OK | - | 0 símbolos nossos ausentes (66 linhas nossas verificadas) | - |
| `App.vue` | MERGE_REAL (122) | OK | - | 0 símbolos nossos ausentes (93 linhas nossas verificadas) | - |
| `components/widgets/conversation/specs/ConversationCard.spec.js` | MERGE_REAL (121) | OK | - | símbolos realocados: AgentBot, assigneeLabel, buildChat | - |
| `components-next/message/chips/Audio.vue` | MERGE_REAL (117) | OK | - | 0 símbolos nossos ausentes (70 linhas nossas verificadas) | - |
| `routes/dashboard/settings/inbox/Settings.vue` | MERGE_REAL (117) | OK | - | 0 símbolos nossos ausentes (68 linhas nossas verificadas) | - |
| `components-next/sidebar/SidebarGroup.vue` | MERGE_REAL (111) | OK | - | símbolos realocados: permitido, verificar | - |
| `components/widgets/WootWriter/AudioRecorder.vue` | MERGE_REAL (111) | OK | - | símbolos realocados: currentAudioUrl | - |
| `routes/dashboard/conversation/ContactPanel.vue` | MERGE_REAL (111) | OK | - | 0 símbolos nossos ausentes (67 linhas nossas verificadas) | - |
| `components-next/Conversation/ConversationCard/CardMessagePreviewWithMeta.vue` | MERGE_REAL (110) | OK | - | 0 símbolos nossos ausentes (69 linhas nossas verificadas) | - |
| `routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue` | MERGE_REAL (108) | OK | - | 0 símbolos nossos ausentes (66 linhas nossas verificadas) | - |
| `components-next/Contacts/ContactsForm/ContactsForm.vue` | MERGE_REAL (107) | OK | - | 0 símbolos nossos ausentes (74 linhas nossas verificadas) | - |
| `routes/dashboard/contacts/pages/ContactManageView.vue` | MERGE_REAL (101) | OK | - | 0 símbolos nossos ausentes (55 linhas nossas verificadas) | - |
| `api/inbox/conversation.js` | MERGE_REAL (99) | OK | - | 0 símbolos nossos ausentes (61 linhas nossas verificadas) | - |
| `components-next/NewConversation/helpers/composeConversationHelper.js` | MERGE_REAL (99) | OK | - | 0 símbolos nossos ausentes (71 linhas nossas verificadas) | - |
| `helper/actionCable.js` | MERGE_REAL (96) | RISCO | merge cruzou destructuring de DELES com chamada de NOSSO → TypeError em runtime | MERGE:14 `const { isImpersonating } = useImpersonation()` + MERGE:144 `if (isImpersonating())` — o composable devolve um `computed` ref | C-2 |
| `routes/dashboard/settings/reports/ReportContainer.vue` | MERGE_REAL (94) | OK | - | 0 símbolos nossos ausentes (63 linhas nossas verificadas) | - |
| `routes/dashboard/settings/canned/AddCanned.vue` | MERGE_REAL (93) | OK | - | 0 símbolos nossos ausentes (70 linhas nossas verificadas) | - |
| `store/modules/conversationStats.js` | MERGE_REAL (92) | OK | - | símbolos realocados: mediumDebouncedFetchMetaData | - |
| `modules/conversations/components/MessageContextMenu.vue` | MERGE_REAL (83) | OK | - | 0 símbolos nossos ausentes (40 linhas nossas verificadas) | - |
| `components/widgets/conversation/contextMenu/Index.vue` | MERGE_REAL (80) | OK | - | 0 símbolos nossos ausentes (37 linhas nossas verificadas) | - |
| `composables/useFileUpload.js` | MERGE_REAL (75) | OK | - | 0 símbolos nossos ausentes (36 linhas nossas verificadas) | - |
| `components/widgets/WootWriter/ReplyTopPanel.vue` | MERGE_REAL (74) | PERDA | prop `isCopilotActive` sumiu; NOSSO ReplyBox.vue:2778 passava `:is-copilot-active="copilot.isActive.value"` | MERGE: prop ausente de `props:{}` (linha 23); `grep -rn is-copilot-active` no MERGE = vazio | C-7 |
| `components-next/Conversation/SidepanelSwitch.vue` | MERGE_REAL (73) | OK | - | 0 símbolos nossos ausentes (30 linhas nossas verificadas) | - |
| `components/widgets/AttachmentsPreview.vue` | MERGE_REAL (70) | OK | - | 0 símbolos nossos ausentes (50 linhas nossas verificadas) | - |
| `routes/dashboard/settings/canned/Index.vue` | MERGE_REAL (69) | OK | - | 0 símbolos nossos ausentes (46 linhas nossas verificadas) | - |
| `store/modules/contacts/mutations.js` | MERGE_REAL (63) | OK | - | 0 símbolos nossos ausentes (18 linhas nossas verificadas) | - |
| `components-next/sidebar/SidebarSubGroup.vue` | MERGE_REAL (62) | PERDA | persistência do estado de subgrupo em uiSettings.sidebar_subgroup_state | `grep -rn sidebar_subgroup_state` na árvore do MERGE = vazio; MERGE:183 linhas ≈ DELES:182 | C-3 |
| `modules/search/components/SearchResultConversationItem.vue` | MERGE_REAL (61) | PERDA | item compacto de busca (avatar + InboxName, sem CardLayout) | MERGE:96-99 volta ao `<CardLayout>` do upstream; difere de DELES só no `voiceEnabled` | C-6 |
| `components-next/sidebar/SidebarCollapsedPopover.vue` | MERGE_REAL (60) | OK | - | 0 símbolos nossos ausentes (36 linhas nossas verificadas) | - |
| `components-next/NewConversation/components/ActionButtons.vue` | MERGE_REAL (56) | OK | - | 0 símbolos nossos ausentes (33 linhas nossas verificadas) | - |
| `store/modules/conversations/helpers/actionHelpers.js` | MERGE_REAL (54) | OK | - | 0 símbolos nossos ausentes (41 linhas nossas verificadas) | - |
| `components-next/NewConversation/components/InboxSelector.vue` | MERGE_REAL (52) | OK | - | 0 símbolos nossos ausentes (26 linhas nossas verificadas) | - |
| `store/modules/auth.js` | MERGE_REAL (52) | OK | - | 0 símbolos nossos ausentes (11 linhas nossas verificadas) | - |
| `components/widgets/conversation/ConversationBox.vue` | MERGE_REAL (51) | OK | - | 0 símbolos nossos ausentes (42 linhas nossas verificadas) | - |
| `routes/dashboard/settings/labels/EditLabel.vue` | MERGE_REAL (51) | OK | - | 0 símbolos nossos ausentes (43 linhas nossas verificadas) | - |
| `components/widgets/conversation/ConversationBasicFilter.vue` | MERGE_REAL (49) | OK | - | 0 símbolos nossos ausentes (29 linhas nossas verificadas) | - |
| `store/modules/accounts.js` | MERGE_REAL (49) | OK | - | 0 símbolos nossos ausentes (30 linhas nossas verificadas) | - |
| `routes/dashboard/settings/reports/components/WootReports.vue` | MERGE_REAL (48) | OK | - | 0 símbolos nossos ausentes (34 linhas nossas verificadas) | - |
| `components-next/message/bubbles/Base.vue` | MERGE_REAL (47) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `routes/dashboard/conversation/conversation.routes.js` | MERGE_REAL (46) | OK | - | 0 símbolos nossos ausentes (18 linhas nossas verificadas) | - |
| `routes/dashboard/Dashboard.vue` | PEGOU_NOSSO (45) | OK | - | 0 símbolos nossos ausentes (37 linhas nossas verificadas) | - |
| `components-next/sidebar/SidebarProfileMenu.vue` | MERGE_REAL (44) | OK | - | 0 símbolos nossos ausentes (27 linhas nossas verificadas) | - |
| `store/mutation-types.js` | MERGE_REAL (44) | OK | - | 0 símbolos nossos ausentes (40 linhas nossas verificadas) | - |
| `store/modules/contactConversations.js` | MERGE_REAL (42) | OK | - | 0 símbolos nossos ausentes (32 linhas nossas verificadas) | - |
| `components-next/sidebar/SidebarGroupHeader.vue` | MERGE_REAL (41) | OK | - | 0 símbolos nossos ausentes (29 linhas nossas verificadas) | - |
| `components/widgets/conversation/conversationBulkActions/AgentSelector.vue` | APAGADO (40)| OK | nada — a regra D-11 migrou | upstream renomeou p/ BulkAgentActions.vue (commit 2435d7503c); `diff DELES MERGE` mostra só o nosso enxerto: import useReplyAssignmentGate + `items = isAssignmentGateEnabled.value ? [] : [...]` | - |
| `routes/dashboard/settings/reports/Index.vue` | MERGE_REAL (40) | OK | - | 0 símbolos nossos ausentes (29 linhas nossas verificadas) | - |
| `api/specs/inbox/conversation.spec.js` | MERGE_REAL (39) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `composables/spec/useAgentsList.spec.js` | MERGE_REAL (38) | OK | - | 0 símbolos nossos ausentes (15 linhas nossas verificadas) | - |
| `routes/dashboard/contacts/pages/ContactsIndex.vue` | MERGE_REAL (38) | OK | - | 0 símbolos nossos ausentes (28 linhas nossas verificadas) | - |
| `routes/dashboard/helpcenter/helpcenter.routes.js` | MERGE_REAL (38) | OK | - | 0 símbolos nossos ausentes (26 linhas nossas verificadas) | - |
| `helper/specs/automationHelper.spec.js` | MERGE_REAL (37) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `components-next/sidebar/SidebarGroupSeparator.vue` | PEGOU_DELES (36) | PERDA | separador clicável (collapsible + emit toggle) — metade do mesmo recurso do SidebarSubGroup | MERGE byte-idêntico ao upstream; `defineEmits(['toggle'])` nosso sumiu | C-3 |
| `routes/dashboard/settings/integrations/SingleIntegrationHooks.vue` | MERGE_REAL (36) | OK | - | 0 símbolos nossos ausentes (17 linhas nossas verificadas) | - |
| `store/modules/inboxes.js` | MERGE_REAL (36) | OK | - | símbolos realocados: allowlist, configured, conversation | - |
| `components-next/sidebar/SidebarGroupLeaf.vue` | MERGE_REAL (35) | OK | - | símbolos realocados: collapsed | - |
| `components/widgets/WootWriter/Editor.vue` | MERGE_REAL (35) | OK | - | 0 símbolos nossos ausentes (29 linhas nossas verificadas) | - |
| `components/Accordion/AccordionItem.vue` | MERGE_REAL (34) | OK | - | 0 símbolos nossos ausentes (16 linhas nossas verificadas) | - |
| `store/modules/specs/conversations/mutations.spec.js` | MERGE_REAL (33) | OK | - | 0 símbolos nossos ausentes (17 linhas nossas verificadas) | - |
| `components-next/Editor/Editor.vue` | IDENTICO (32) | OK | - | 0 símbolos nossos ausentes (13 linhas nossas verificadas) | - |
| `routes/dashboard/captain/captain.routes.js` | MERGE_REAL (30) | OK | - | 0 símbolos nossos ausentes (11 linhas nossas verificadas) | - |
| `store/modules/integrations.js` | MERGE_REAL (29) | OK | - | 0 símbolos nossos ausentes (20 linhas nossas verificadas) | - |
| `composables/spec/useMacros.spec.js` | MERGE_REAL (28) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `composables/useAgentsList.js` | MERGE_REAL (28) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `api/contacts.js` | MERGE_REAL (26) | OK | - | 0 símbolos nossos ausentes (15 linhas nossas verificadas) | - |
| `components-next/NewConversation/helpers/specs/composeConversationHelper.spec.js` | PEGOU_NOSSO (25) | OK | - | 0 símbolos nossos ausentes (11 linhas nossas verificadas) | - |
| `components-next/combobox/ComboBox.vue` | MERGE_REAL (25) | OK | - | 0 símbolos nossos ausentes (18 linhas nossas verificadas) | - |
| `components/Modal.vue` | MERGE_REAL (25) | OK | - | 0 símbolos nossos ausentes (7 linhas nossas verificadas) | - |
| `api/captain/response.js` | MERGE_REAL (24) | OK | - | 0 símbolos nossos ausentes (12 linhas nossas verificadas) | - |
| `api/conversations.js` | MERGE_REAL (24) | OK | - | 0 símbolos nossos ausentes (12 linhas nossas verificadas) | - |
| `components/widgets/mentions/MentionBox.vue` | PEGOU_NOSSO (24) | RISCO | mantém `::v-deep` (combinador depreciado no Vue 3) — upstream migrou para `:deep()` | MERGE = NOSSO; upstream trocou `.canned-item__button::v-deep` por `:deep(...)`; vue ^3.5.12 / @vitejs/plugin-vue ^5.2.4 | C-9 |
| `routes/dashboard/settings/labels/AddLabel.vue` | MERGE_REAL (24) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `api/captain/document.js` | MERGE_REAL (22) | OK | - | 0 símbolos nossos ausentes (15 linhas nossas verificadas) | - |
| `routes/dashboard/settings/macros/MacroEditor.vue` | MERGE_REAL (22) | OK | - | 0 símbolos nossos ausentes (16 linhas nossas verificadas) | - |
| `components-next/dropdown-menu/DropdownMenu.vue` | MERGE_REAL (21) | OK | - | 0 símbolos nossos ausentes (8 linhas nossas verificadas) | - |
| `composables/spec/useCaptain.spec.js` | MERGE_REAL (21) | OK | - | 0 símbolos nossos ausentes (8 linhas nossas verificadas) | - |
| `routes/dashboard/captain/documents/Index.vue` | MERGE_REAL (21) | PERDA | DocumentViewerModal / handleViewDocument / showViewer; LimitBanner do Cloud voltou | `grep -rln DocumentViewerModal` no MERGE = vazio (componente órfão, 2.354 B); MERGE:24,390 LimitBanner | C-4 |
| `api/specs/inbox/message.spec.js` | MERGE_REAL (20) | OK | - | 0 símbolos nossos ausentes (10 linhas nossas verificadas) | - |
| `components-next/combobox/ComboBoxDropdown.vue` | MERGE_REAL (20) | OK | - | 0 símbolos nossos ausentes (11 linhas nossas verificadas) | - |
| `components/widgets/conversation/conversationBulkActions/Index.vue` | MERGE_REAL (20) | OK | - | símbolos realocados: #2dc46f, teamSelected | - |
| `routes/dashboard/settings/account/Index.vue` | MERGE_REAL (20) | OK | - | 0 símbolos nossos ausentes (19 linhas nossas verificadas) | - |
| `components-next/HelpCenter/HelpCenterLayout.vue` | MERGE_REAL (19) | OK | - | símbolos realocados: semibold | - |
| `routes/dashboard/conversation/ContactConversations.vue` | MERGE_REAL (19) | OK | - | 0 símbolos nossos ausentes (6 linhas nossas verificadas) | - |
| `store/modules/contacts/actions.js` | MERGE_REAL (19) | OK | - | 0 símbolos nossos ausentes (7 linhas nossas verificadas) | - |
| `api/inboxes.js` | MERGE_REAL (18) | OK | - | 0 símbolos nossos ausentes (10 linhas nossas verificadas) | - |
| `components-next/Contacts/ContactsCard/ContactsCard.vue` | MERGE_REAL (18) | OK | - | 0 símbolos nossos ausentes (13 linhas nossas verificadas) | - |
| `store/index.js` | MERGE_REAL (18) | OK | - | 0 símbolos nossos ausentes (18 linhas nossas verificadas) | - |
| `composables/useUISettings.js` | MERGE_REAL (17) | OK | - | 0 símbolos nossos ausentes (14 linhas nossas verificadas) | - |
| `routes/dashboard/dashboard.routes.js` | MERGE_REAL (17) | OK | - | 0 símbolos nossos ausentes (15 linhas nossas verificadas) | - |
| `components/widgets/conversation/ConversationSidebar.vue` | MERGE_REAL (16) | OK | - | 0 símbolos nossos ausentes (11 linhas nossas verificadas) | - |
| `helper/specs/URLHelper.spec.js` | MERGE_REAL (16) | OK | - | 0 símbolos nossos ausentes (10 linhas nossas verificadas) | - |
| `components-next/Campaigns/CampaignCard/CampaignCard.vue` | MERGE_REAL (14) | OK | - | 0 símbolos nossos ausentes (12 linhas nossas verificadas) | - |
| `store/modules/contacts/getters.js` | MERGE_REAL (14) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `api/specs/contacts.spec.js` | MERGE_REAL (13) | OK | - | 0 símbolos nossos ausentes (7 linhas nossas verificadas) | - |
| `components/widgets/VideoCallButton.vue` | MERGE_REAL (13) | OK | - | 0 símbolos nossos ausentes (8 linhas nossas verificadas) | - |
| `components/widgets/conversation/components/SLACardLabel.vue` | MERGE_REAL (13) | OK | - | 0 símbolos nossos ausentes (6 linhas nossas verificadas) | - |
| `store/modules/specs/contacts/mutations.spec.js` | MERGE_REAL (13) | OK | - | 0 símbolos nossos ausentes (7 linhas nossas verificadas) | - |
| `components-next/HelpCenter/ArticleCard/ArticleCard.vue` | MERGE_REAL (12) | OK | - | 0 símbolos nossos ausentes (6 linhas nossas verificadas) | - |
| `components/widgets/conversation/contextMenu/menuItem.vue` | MERGE_REAL (12) | OK | - | 0 símbolos nossos ausentes (10 linhas nossas verificadas) | - |
| `composables/useCallSession.js` | PEGOU_NOSSO (11) | OK | - | 0 símbolos nossos ausentes (5 linhas nossas verificadas) | - |
| `routes/index.js` | MERGE_REAL (11) | OK | - | 0 símbolos nossos ausentes (7 linhas nossas verificadas) | - |
| `api/enterprise/account.js` | MERGE_REAL (10) | OK | - | 0 símbolos nossos ausentes (5 linhas nossas verificadas) | - |
| `components-next/Inbox/InboxCard.vue` | PEGOU_NOSSO (10) | OK | - | 0 símbolos nossos ausentes (7 linhas nossas verificadas) | - |
| `components-next/Settings/SettingsToggleSection.vue` | MERGE_REAL (10) | OK | - | 0 símbolos nossos ausentes (5 linhas nossas verificadas) | - |
| `components-next/message/bubbles/VoiceCall.vue` | PEGOU_NOSSO (10) | OK | - | 0 símbolos nossos ausentes (6 linhas nossas verificadas) | - |
| `components/widgets/conversation/VoiceCallStatus.vue` | PEGOU_NOSSO (10) | OK | - | 0 símbolos nossos ausentes (6 linhas nossas verificadas) | - |
| `composables/useMacros.js` | MERGE_REAL (10) | OK | - | 0 símbolos nossos ausentes (8 linhas nossas verificadas) | - |
| `constants/globals.js` | MERGE_REAL (10) | OK | - | 0 símbolos nossos ausentes (10 linhas nossas verificadas) | - |
| `components-next/HelpCenter/PortalSwitcher/PortalSwitcher.vue` | MERGE_REAL (8) | OK | - | 0 símbolos nossos ausentes (4 linhas nossas verificadas) | - |
| `components-next/sidebar/ChannelLeaf.vue` | MERGE_REAL (8) | OK | - | 0 símbolos nossos ausentes (5 linhas nossas verificadas) | - |
| `components/widgets/FloatingCallWidget.vue` | PEGOU_NOSSO (8) | OK | - | 0 símbolos nossos ausentes (2 linhas nossas verificadas) | - |
| `components/widgets/conversation/conversationBulkActions/TeamActions.vue` | APAGADO (8)| PERDA | skin WhatsApp local (bg-n-solid-1/#233138, --wa-list-border, fill-white, i-lucide-search) | renomeado p/ BulkTeamActions.vue, byte-idêntico ao upstream; `bg-n-alpha-3 backdrop-blur-[4px]` reaparece em BulkTeamActions.vue:110 | C-10 |
| `routes/dashboard/settings/inbox/Index.vue` | MERGE_REAL (7) | OK | - | 0 símbolos nossos ausentes (4 linhas nossas verificadas) | - |
| `routes/dashboard/settings/reports/BotReports.vue` | MERGE_REAL (7) | OK | - | 0 símbolos nossos ausentes (5 linhas nossas verificadas) | - |
| `routes/dashboard/settings/teams/Index.vue` | MERGE_REAL (7) | OK | - | 0 símbolos nossos ausentes (4 linhas nossas verificadas) | - |
| `components-next/HelpCenter/CategoryCard/CategoryCard.vue` | MERGE_REAL (6) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `helper/URLHelper.js` | MERGE_REAL (6) | OK | - | 0 símbolos nossos ausentes (6 linhas nossas verificadas) | - |
| `routes/dashboard/settings/billing/components/CreditPackageCard.vue` | MERGE_REAL (6) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `components/ConversationItem.vue` | MERGE_REAL (5) | RISCO | passa a escolher entre 2 cards; o expandido não tem nenhuma customização ChatSPX | ConversationItem.vue:185 `<ConversationCardExpanded v-if="showExpanded">` | C-1 |
| `routes/dashboard/captain/responses/Index.vue` | MERGE_REAL (5) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `routes/dashboard/captain/responses/Pending.vue` | APAGADO (5) | PERDA | tela do fluxo de FAQ pendente apagada; nossa custom era FEATURE_FLAGS.CAPTAIN_V2 + remoção do LimitBanner | arquivo ausente do MERGE; rota `/faqs/pending` agora redireciona (captain.routes.js:97-104) para a tela nova, que lê OUTRA tabela | C-0 |
| `routes/dashboard/settings/automation/constants.js` | MERGE_REAL (5) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `routes/dashboard/settings/macros/constants.js` | MERGE_REAL (5) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `routes/dashboard/settings/reports/components/heatmaps/HeatmapDateRangeSelector.vue` | MERGE_REAL (5) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `api/captain/assistant.js` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (2 linhas nossas verificadas) | - |
| `components-next/phonenumberinput/PhoneNumberInput.vue` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (2 linhas nossas verificadas) | - |
| `components/widgets/conversation/conversationBulkActions/LabelActions.vue` | APAGADO (4)| PERDA | skin WhatsApp local (bg-n-solid-1/#233138, --wa-list-border, fill-white) | renomeado p/ BulkLabelActions.vue, byte-idêntico ao upstream | C-10 |
| `components/widgets/conversation/conversationBulkActions/UpdateActions.vue` | APAGADO (4)| PERDA | skin WhatsApp local (bg-n-solid-1/#233138, --wa-list-border, fill-white) | renomeado p/ BulkUpdateActions.vue, byte-idêntico ao upstream | C-10 |
| `featureFlags.js` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `helper/automationHelper.js` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `helper/routeHelpers.js` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (4 linhas nossas verificadas) | - |
| `modules/search/components/SearchView.vue` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (2 linhas nossas verificadas) | - |
| `routes/dashboard/settings/settings.routes.js` | MERGE_REAL (4) | OK | - | 0 símbolos nossos ausentes (4 linhas nossas verificadas) | - |
| `components-next/captain/assistant/ScenariosCard.vue` | MERGE_REAL (3) | OK | - | 0 símbolos nossos ausentes (2 linhas nossas verificadas) | - |
| `components-next/message/constants.js` | MERGE_REAL (3) | OK | - | 0 símbolos nossos ausentes (2 linhas nossas verificadas) | - |
| `composables/useAutomationValues.js` | MERGE_REAL (3) | OK | - | 0 símbolos nossos ausentes (3 linhas nossas verificadas) | - |
| `components-next/Companies/CompaniesHeader/components/CompanySortMenu.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/Contacts/ContactsHeader/components/ContactSortMenu.vue` | PEGOU_DELES (2) | OK | - | símbolos realocados: #233138, --wa-list-border, --wa-list-border-dark | - |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorHeader.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/HelpCenter/Pages/CategoryPage/CategoryDialog.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/NewConversation/components/ContentTemplateSelector.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/captain/assistant/AddNewScenariosDialog.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/captain/pageComponents/switcher/AssistantSwitcher.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components/ChannelSelector.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components/IntersectionObserver.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `routes/dashboard/conversation/Macros/MacroPreview.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `routes/dashboard/settings/macros/MacroProperties.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `routes/dashboard/settings/reports/components/heatmaps/BaseHeatmapContainer.vue` | MERGE_REAL (2) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/Contacts/Pages/ContactsList.vue` | MERGE_REAL (1) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
| `components-next/captain/pageComponents/emptyStates/ResponsePageEmptyState.vue` | MERGE_REAL (1) | OK | - | 0 símbolos nossos ausentes (0 linhas nossas verificadas) | - |
| `composables/spec/useAutomation.spec.js` | MERGE_REAL (1) | OK | - | 0 símbolos nossos ausentes (1 linhas nossas verificadas) | - |
---

## ACHADO A4-9 — RISCO: `quoted_email_reply` virou flag morto (e ainda ocupa um bit)

Descoberto ao auditar `featureFlags.js` (MERGE_REAL, 4 linhas nossas — o motor automático deu
OK, o achado veio do diff manual).

| versão | `featureFlags.js` | gate no `ReplyBox.vue` |
|---|---|---|
| BASE v4.12.1 | `QUOTED_EMAIL_REPLY: 'quoted_email_reply'` (linha 43) | `isQuotedEmailReplyEnabled()` + `if (!isAnEmailChannel \|\| !isQuotedEmailReplyEnabled) return false` |
| NOSSO | idem (linha 43) | idem (linha 671–682) |
| DELES v4.16.2 | **removido** | **removido** — `quotedReplyPreference()` só checa `isAnEmailChannel` (linha 411) |
| MERGE | **removido** | **removido** (linha 704) — seguiu o upstream, coerente |

O merge acompanhou o upstream, que promoveu o recurso a GA. **Mas `config/features.yml` do MERGE
ainda declara o flag:**

```yaml
# config/features.yml:222–224 (MERGE)
- name: quoted_email_reply
  display_name: Quoted Email Reply
  enabled: false
```

Duas consequências:

1. **Discrepância admin × comportamento.** O super admin vê "Quoted Email Reply: desligado" e o
   recurso está ligado para toda conta com canal de e-mail. Ninguém consegue desligá-lo.
2. **Um bit desperdiçado no bitmask que já estourou.** Este é um flag morto ocupando slot em
   `feature_flags` — exatamente a coluna do ACHADO 3 do coordenador.

**Recomendação explícita: NÃO remover a entrada do `features.yml`.** Remover um flag do meio da
lista remapeia o bit de todos os que vêm depois — é precisamente o dano que o achado 3 tenta
evitar. Documentar como flag morto e deixar o slot queimado é mais barato que remapear a frota.
Fora do meu escopo de arquivos; passo ao executor de `config/`.

---

## CORREÇÕES PROPOSTAS, EM ORDEM DE GRAVIDADE

Nenhuma foi aplicada — esta auditoria é somente-leitura.

### C-1 — RISCO (vazamento de conteúdo entre agentes) · card expandido sem isolamento

**Arquivo:** `app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCardExpanded.vue`
(e `CardContent.vue`)

Opção A (recomendada, menor superfície) — **neutralizar o caminho novo** até portar as
customizações. Em `app/javascript/dashboard/components/ConversationList.vue:37`:

```diff
-const showExpandedCards = computed(
-  () => props.isOnExpandedLayout && isLgScreen.value
-);
+// ChatSPX: o ConversationCardExpanded do upstream não implementa o isolamento por agente
+// (preview 🔒), o chip de IA nem o destaque de não-atendida. Até que sejam portados,
+// a lista usa sempre o nosso ConversationCard. Ver onda-0-auditoria-dashboard.md, ACHADO A4-1.
+const showExpandedCards = computed(() => false);
```

Opção B (correta a longo prazo) — portar as quatro customizações para
`ConversationCardExpanded.vue`, espelhando `ConversationCard.vue`:

```js
// 1. isolamento por agente (o item que vaza conteúdo)
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
const { isMessageRestricted } = useAgentIsolation();
const previewMessage = computed(() => {
  const message = lastMessageInChat.value;
  if (!message || !isMessageRestricted(message, props.inbox)) return message;
  return {
    ...message,
    content: `🔒 ${t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')}`,
    attachments: [], content_attributes: {}, content_type: 'text',
  };
});
// e passar :last-message="previewMessage" ao <CardContent>, não lastMessageInChat
// 2. isAIAssignee + aiChipStyle (aiAccentVars)   — copiar de ConversationCard.vue:89–100
// 3. isUnattendedAndMine + animate-sidebar-attention — copiar de ConversationCard.vue:103–113, 175
// 4. hasValidContent + cadeia de fallback         — copiar de ConversationCard.vue:48–68
```

**Aceite (mecanismo que o executa, não afirmação):** estender
`components/widgets/conversation/specs/ConversationCard.spec.js` — que já monta chat/assignee —
com um bloco `describe('ConversationCardExpanded — isolamento por agente')` que monta o card
expandido com uma última mensagem restrita a outro agente e **asserta o valor exato do preview**:

```js
expect(wrapper.find('[data-testid="message-preview"]').text())
  .toBe('🔒 Conteúdo restrito');          // valor exato, não truthy/length
expect(wrapper.text()).not.toContain(RESTRICTED_MESSAGE_BODY);  // o texto cru não pode vazar
```

Enquanto a Opção A estiver em vigor, o mesmo teste deve provar que `showExpandedCards` é `false`
com `isOnExpandedLayout=true` e viewport ≥1024px.

### C-2 — RISCO · `actionCable.js` chama `computed` ref como função

**Arquivo:** `app/javascript/dashboard/helper/actionCable.js:144`

```diff
   onPresenceUpdate = data => {
-    if (isImpersonating()) return;
+    if (isImpersonating.value) return;
     this.app.$store.dispatch('contacts/updatePresence', data.contacts);
     this.app.$store.dispatch('agents/updatePresence', data.users);
     this.app.$store.dispatch('setCurrentUserAvailability', data.users);
   };
```

**Aceite:** `helper/specs/actionCable.spec.js` hoje **não exercita `onPresenceUpdate`** — o bug
passa verde. O fix precisa vir com o teste que faltava. O mock da linha 13
(`isImpersonating: { value: false }`) já está correto e serve:

```js
it('dispatches presence updates when not impersonating', () => {
  const data = { contacts: { 1: 'online' }, users: { 7: 'busy' } };
  actionCable.onPresenceUpdate(data);
  expect(mockDispatch).toHaveBeenCalledWith('contacts/updatePresence', data.contacts);
  expect(mockDispatch).toHaveBeenCalledWith('agents/updatePresence', data.users);
  expect(mockDispatch).toHaveBeenCalledWith('setCurrentUserAvailability', data.users);
});
```

Com a linha 144 como está, esse teste falha com `TypeError` — é o mecanismo que prova o defeito
antes e a correção depois.

### C-3 — PERDA · persistência do estado de subgrupo da sidebar

**Arquivos:** `components-next/sidebar/SidebarSubGroup.vue`, `SidebarGroupSeparator.vue`,
`SidebarGroup.vue` (quem passa os props)

Reintroduzir sobre a versão do upstream (não reverter o arquivo — o upstream trouxe
`showTreeLine`, `sortOptions`, `endTreeLine`, que queremos manter):

```js
// SidebarSubGroup.vue — reaplicar por cima do upstream
import { useUISettings } from 'dashboard/composables/useUISettings';
const props = defineProps({ /* ...upstream... */, parentName: { type: String, required: true } });
const { uiSettings, updateUISettings } = useUISettings();

const subgroupKey          = computed(() => `${props.parentName}/${props.name}`);
const sidebarSubgroupState = computed(() => uiSettings.value?.sidebar_subgroup_state || {});
const storedExpandedState  = computed(() => sidebarSubgroupState.value[subgroupKey.value]);
const isSubgroupExpanded   = computed(() => {
  if (hasActiveChild.value) return true;
  return storedExpandedState.value !== undefined ? storedExpandedState.value : true;
});
const setSubgroupExpanded = value =>
  updateUISettings({
    sidebar_subgroup_state: { ...sidebarSubgroupState.value, [subgroupKey.value]: value },
  });
const toggleSubgroup = () => setSubgroupExpanded(!isSubgroupExpanded.value);
```

Substituir `v-show="isExpanded"` (upstream, linha 132) por `v-show="isSubgroupExpanded"` e ligar
`toggleSubgroup` ao `@toggle` do `SidebarGroupSeparator` — restaurando também o `collapsible` +
`defineEmits(['toggle'])` que o `SidebarGroupSeparator.vue` perdeu (PEGOU_DELES). Em
`SidebarGroup.vue:394`, adicionar `:parent-name="name"`.

**Aceite:** `sidebar_subgroup_state` gravado no `uiSettings` sobrevive a reload — testável com
mock de `useUISettings` assertando a **chave e o valor exatos** de `updateUISettings`:
`expect(updateUISettings).toHaveBeenCalledWith({ sidebar_subgroup_state: { 'conversations/inboxes': false } })`.

**Dado gravado:** os valores antigos em `users.ui_settings.sidebar_subgroup_state` **não foram
apagados** pelo merge — voltam a ser lidos assim que o código for restaurado. Não há perda de dado.

### C-4 — PERDA · card de documento do Captain e visualizador

**Arquivos:** `components-next/captain/assistant/DocumentCard.vue`,
`routes/dashboard/captain/documents/Index.vue`

Decisão de produto antes do patch: o card do upstream traz recursos que não tínhamos
(`DocumentSyncStatus`, `Checkbox` para seleção em massa, `responsesCount`, `syncStaleAfterHours`).
Recomendo **manter o card do upstream e reenxertar só o que é nosso**:

```diff
  <!-- DocumentCard.vue, sobre a versão do upstream -->
+ import AiBadge from 'dashboard/components-next/agents-ui/AiBadge.vue';
+ const statusInfo = computed(() => {
+   if (props.status === 'available')   return { variant: 'on',   label: t('CAPTAIN.DOCUMENTS.STATUS.TRAINED') };
+   if (props.status === 'in_progress') return { variant: 'warn', label: t('CAPTAIN.DOCUMENTS.STATUS.PROCESSING') };
+   if (props.status === 'failed')      return { variant: 'err',  label: t('CAPTAIN.DOCUMENTS.STATUS.FAILED') };
+   return null;
+ });
+ // e no menu, a entrada que reabre o visualizador:
+ { label: t('CAPTAIN.DOCUMENTS.OPTIONS.VIEW_DOCUMENT'), value: 'view', icon: 'i-lucide-eye' }
```

```diff
  <!-- documents/Index.vue -->
+ import DocumentViewerModal from 'dashboard/components-next/captain/assistant/DocumentViewerModal.vue';
+ const showViewer = ref(false);
+ const handleViewDocument = () => { showViewer.value = true; };
  const handleAction = ({ action, id }) => {
      ...
      } else if (action === 'viewRelatedQuestions') { handleShowRelatedDocument(); }
+     else if (action === 'view') { handleViewDocument(); }
  };
+ <DocumentViewerModal v-model="showViewer" :captain-document="selectedDocument" />
```

Isso volta a dar consumidor ao `DocumentViewerModal.vue` (hoje órfão no repo) e às chaves
`CAPTAIN.DOCUMENTS.STATUS.*` / `OPTIONS.VIEW_DOCUMENT` (hoje órfãs nos JSONs, já traduzidas).

Decisão separada: o `LimitBanner` (banner de limite de plano do Chatwoot Cloud) voltou em
`documents/Index.vue:24,390`. Nós o havíamos removido de propósito. Remover de novo é 2 linhas.

### C-5 — PERDA · preview de mensagem restrita perdeu o texto

**Arquivo:** `components/widgets/conversation/ConversationCard.vue:75`

```diff
 const previewMessage = computed(() => {
   const message = lastMessageInChat.value;
   if (!message || !isMessageRestricted(message, props.inbox)) return message;
   return {
     ...message,
-    content: '🔒',
+    content: `🔒 ${t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')}`,
     attachments: [],
     content_attributes: {},
     content_type: 'text',
   };
 });
```

A chave já existe e está traduzida no MERGE (`pt_BR/conversation.json:617` = "Conteúdo restrito",
`en/conversation.json:639` = "Restricted content"). `t` já está no escopo do arquivo.

**Aceite:** asserção de valor exato — `expect(preview.content).toBe('🔒 Conteúdo restrito')`.

### C-6 — PERDA · item compacto do resultado de busca

**Arquivo:** `modules/search/components/SearchResultConversationItem.vue`

Reaplicar nosso template (router-link direto com `flex p-2 rounded-xl cursor-pointer
hover:bg-n-slate-2`, avatar + `InboxName`) sobre a versão do MERGE, **preservando** a única
diferença que o merge já resolveu certo: `getInboxIconByType(channelType, medium)` sem o 4º
argumento `voiceEnabled` (coerente com o descarte do front de voz — ver ACHADO A4-8).
Perda puramente visual; sem risco de dado.

### C-7 — PERDA · prop `isCopilotActive` do `ReplyTopPanel`

**Arquivos:** `components/widgets/WootWriter/ReplyTopPanel.vue` (prop) e
`components/widgets/conversation/ReplyBox.vue` (quem passava)

Restaurar o prop:

```diff
   props: {
     mode: { type: String, default: REPLY_EDITOR_MODES.REPLY },
+    isCopilotActive: { type: Boolean, default: false },
```

e a passagem no `ReplyBox.vue` (em NOSSO era a linha 2778):

```diff
   <ReplyTopPanel
     ...
+    :is-copilot-active="copilot.isActive.value"
```

Antes de aplicar, confirmar no `ReplyTopPanel.vue` do MERGE se o template ainda tem algum ramo
que dependia do prop; se o upstream reescreveu essa região (ele mexeu nos "in-pill copilot/expand
buttons", ver comentário na linha 123), o reenxerto pode ser desnecessário. **Marcar como
verificar-antes-de-aplicar**, não aplicar às cegas.

### C-8 — RISCO leve · responsividade mobile do modal de nova conversa

**Arquivo:** `components-next/NewConversation/components/ComposeNewConversationForm.vue`

O descarte do bloco de voz do upstream (correto) levou junto uma melhoria não relacionada:

```diff
-    class="w-[42rem] divide-y divide-n-strong ..."
+    class="w-full md:w-[42rem] divide-y divide-n-strong ..."
```

Em viewport < 42rem o modal estoura a tela. Uma linha, sem efeito colateral.

### C-9 — RISCO leve · `::v-deep` depreciado no `MentionBox.vue`

**Arquivo:** `components/widgets/mentions/MentionBox.vue`

```diff
-.canned-item__button::v-deep .button__content {
+.canned-item__button :deep(.button__content) {
```

`::v-deep` como combinador está depreciado no Vue 3 e é candidato a remoção do compilador SFC.
O projeto está em `vue ^3.5.12` / `@vitejs/plugin-vue ^5.2.4` — hoje ainda compila (com aviso),
mas quebra silenciosamente (estilo não aplicado, sem erro de build) numa atualização futura.
O upstream já fez essa migração; o `PEGOU_NOSSO` a descartou por tabela.
Após aplicar, a única ocorrência restante de `::v-deep` na árvore fica no
`ConversationCard.vue.backup` — arquivo morto, ver nota de higiene.

### C-10 — PERDA · skin WhatsApp dos três dropdowns de ação em massa

**Arquivos:** `conversationBulkActions/BulkTeamActions.vue`, `BulkUpdateActions.vue`,
`BulkLabelActions.vue` (sucessores de `TeamActions`, `UpdateActions`, `LabelActions`)

Contexto que muda a decisão: o upstream reescreveu os três para usar o
`components-next/dropdown-menu/DropdownMenu.vue` compartilhado — e **esse componente manteve a
nossa skin** no merge:

```
DropdownMenu.vue:140  class="bg-n-solid-1 border border-n-weak absolute rounded-xl ... animate-dropdown-in"   ← nosso
DropdownMenu.vue:242  ... hover:bg-n-slate-3/50 ...                                                          ← nosso
DropdownMenu.vue:244  'bg-n-slate-3/50': item.isSelected                                                     ← nosso
```

Ou seja, a maior parte do skin volta sozinha pelo componente compartilhado. Restam **duas
regressões pontuais**, e a correção certa é no `DropdownMenu.vue`, não nos três arquivos:

```diff
  <!-- DropdownMenu.vue:166 — o cabeçalho de grupo voltou ao vidro do upstream -->
- class="px-2 py-2 text-xs mb-0 font-medium text-n-slate-11 uppercase tracking-wide sticky top-0 z-10 bg-n-alpha-3 backdrop-blur-sm truncate min-w-0"
+ class="px-2 py-2 text-xs mb-0 font-medium text-n-slate-11 uppercase tracking-wide sticky top-0 z-10 bg-n-solid-1 truncate min-w-0"
```

e o divisor, que era `border-t border-n-weak my-1` no nosso e sumiu do MERGE.

Fora do `DropdownMenu`, sobra o footer sticky do `BulkTeamActions.vue:110`
(`bg-n-alpha-3 backdrop-blur-[4px]`) — mesmo padrão de vidro que o skin ChatSPX substitui por
sólido. Três ocorrências, correção mecânica.

**Não** reverter os arquivos para os antigos `TeamActions.vue`/`LabelActions.vue`/`UpdateActions.vue`:
a arquitetura nova (o `Index.vue` chamando `useBulkActions()` direto) está correta e é o que faz
o `TeamSelectionModal` e o `AssignAndResolveDialog` de bulk continuarem funcionando — ver
ACHADO A4-2.

### C-0 — DADO · o purge das FAQ pendentes (fora dos meus arquivos, registro o laço)

A correção pertence ao executor de `db/migrate` + `enterprise/app/models`. Do lado do front, o
que **precisa acompanhar** a decisão dele:

1. Se a decisão for **preservar as FAQ pendentes**: restaurar
   `routes/dashboard/captain/responses/Pending.vue` (com a nossa customização:
   `FEATURE_FLAGS.CAPTAIN_V2` e sem `LimitBanner`), devolver a rota nomeada
   `captain_assistants_responses_pending` no lugar do `redirect` em `captain.routes.js:97–104`,
   restaurar a entrada no `AssistantSwitcher.vue` e o `router.push` de `responses/Index.vue:191`.
   **E restaurar as 5 chaves em `en/integrations.json`** (`CAPTAIN.RESPONSES.PENDING_FAQS`,
   `BULK_APPROVE_BUTTON`, `BULK_APPROVE.{SUCCESS,ERROR}_MESSAGE`,
   `EMPTY_STATE.NO_PENDING_TITLE`) — elas continuam presentes em pt_BR e nos outros 54 locales;
   só `en` as perdeu (ACHADO i18n-1).
2. Se a decisão for **adotar o `FaqSuggestions` do upstream**: exigir uma migration de
   **transferência** `captain_assistant_responses(status=0) → captain_faq_suggestions` **antes**
   da `20260714123000_purge_pending_captain_assistant_responses`, e traduzir as 24 chaves
   `CAPTAIN.FAQ_SUGGESTIONS.*` para pt_BR (ACHADO i18n-2).

Em nenhum cenário rodar a migration de purge como está: `def down; end` a torna irreversível.

### Dívida de tradução (não bloqueia, mas é regra da casa)

95 chaves novas do upstream entraram em `en` e não em `pt_BR`. Regra permanente: pt-BR é
prioridade e toda string nova entra em pt_BR **e** en. Ordem sugerida pelo que o agente vê primeiro:

1. `INBOX_MGMT.ACCOUNT_HEALTH.*` — 46 chaves (tela nova de saúde do número WhatsApp)
2. `CAPTAIN.FAQ_SUGGESTIONS.*` — 24 chaves (**depende da decisão do C-0**)
3. `CONVERSATION.CAPTAIN_GENERATION.*` — 12 chaves (geração de resposta por IA na conversa)
4. resto — 13 chaves (`DATA_IMPORTS.*`, `CONVERSATION.CARD_CONTEXT_MENU.*`,
   `CAPTAIN.RESPONSES.SUGGESTIONS_BANNER.*`, `APP_GLOBAL.ACCOUNT_SUSPENDED`,
   `CAPTAIN.OVERVIEW.KNOWLEDGE`, `CAPTAIN.RESPONSES.ERRORS`)

Mais 13 chaves de dívida **anterior** ao merge (7 em `integrationApps.json`, 6 em
`conversation.json`) — fora do escopo desta auditoria, registradas para não se perderem.

---

## CONTAGEM POR VEREDITO

### i18n (84 arquivos)

| veredito | nº | quais |
|---|---|---|
| OK | 82 | 0 chaves perdidas, 0 chaves nossas destruídas |
| RISCO | 2 | `en/integrations.json` e `pt_BR/integrations.json` — assimetria das chaves do fluxo pendente (ACHADO i18n-1) |
| PERDA | 0 | — |
| DADO | 0 | — |

### Componentes (183 arquivos)

| veredito | nº |
|---|---|
| OK | 168 |
| PERDA | 11 |
| RISCO | 4 |
| DADO | 0 |

**Os 11 PERDA:** `SidebarSubGroup.vue` · `SidebarGroupSeparator.vue` ·
`captain/assistant/DocumentCard.vue` · `captain/documents/Index.vue` ·
`captain/responses/Pending.vue` (APAGADO) · `ConversationCard.vue` ·
`SearchResultConversationItem.vue` · `ReplyTopPanel.vue` ·
`conversationBulkActions/TeamActions.vue` · `UpdateActions.vue` · `LabelActions.vue` (os três APAGADO/renomeados).

**Os 4 RISCO:** `components/ConversationItem.vue` (achado A4-1, o mais grave da área) ·
`helper/actionCable.js` (A4-6, bug em runtime) · `ComposeNewConversationForm.vue` (A4-8/C-8) ·
`MentionBox.vue` (C-9).

Duas ressalvas de precisão sobre esta contagem:

- **`components/ConversationList.vue` não aparece na tabela** porque não está no TSV da área: é
  arquivo **novo** do upstream, nunca teve customização nossa, e por isso a triagem mecânica não
  o listou. Ele é metade do achado A4-1 (a linha 37 é o que liga o card sem isolamento) e a
  correção C-1 mexe nele. Isto é uma limitação do recorte de 267 arquivos, não um descuido: um
  arquivo que só o upstream tem nunca entra numa triagem que parte de "o que nós customizamos".
- **`featureFlags.js` recebeu OK na tabela** — corretamente, para o recorte deste arquivo. O
  RISCO A4-9 que descrevo acima mora em `config/features.yml`, que não pertence a esta área.

### Total da área

| veredito | nº |
|---|---|
| **OK** | **250** |
| **PERDA** | **11** |
| **RISCO** | **6** |
| **DADO** | **0 nesta área** — o DADO nº 1 confirmado (A4-7) mora em `db/migrate` e `enterprise/app/models`, fora dos 267 arquivos deste recorte |

**COBERTURA: 267 de 267 arquivos da área auditados.**

Detalhamento da cobertura: 100% dos 5 APAGADO, 100% dos 10 PEGOU_NOSSO, 100% dos 3 PEGOU_DELES e
o 1 IDENTICO foram lidos um a um. Os 248 MERGE_REAL foram percorridos inteiros pelo motor
automático de três peneiras (linha nossa → símbolo forte → filtro global no repo) e os 23 que
acusaram sinal foram investigados manualmente com leitura das quatro versões.

### O que a auditoria automática NÃO teria pego

Registro em favor de quem for repetir o método: **o achado mais grave da área (A4-1) é invisível
para qualquer diff arquivo-a-arquivo.** Nenhum arquivo nosso perdeu uma linha; o upstream
adicionou dois arquivos novos (`ConversationList.vue`, `ConversationCardExpanded.vue`) que
desviam o fluxo de renderização para longe do nosso código. Da mesma forma, o A4-6 (`actionCable`)
só aparece cruzando as **quatro** versões — no MERGE isolado a linha parece normal.

Uma auditoria de merge que só compare NOSSO×MERGE arquivo a arquivo dá verde nos dois.
