# 31 — Auditoria adversarial: os planos são executáveis?

> **O que é este documento.** Uma varredura hostil de `PLANO-MESTRE.md` e dos quatro planos de
> frente (`22-plano-widget.md`, `23-plano-config-dashboard.md`, `24-plano-backend-dados.md`,
> `25-plano-tracking-integracao.md`), feita sob a hipótese de que há problemas sérios e com o
> objetivo de achá-los. Onde não achei, digo que não achei.
>
> **Postura.** Nenhuma afirmação marcada `[MEDIDO]` ou `[FATO]` foi aceita por estar marcada. Refiz
> as medições que sustentam as arbitragens e conferi **46 referências `arquivo:linha`** uma a uma no
> HEAD `ee87f5e799`.
>
> **Regra dura cumprida:** nenhum arquivo do repositório e nenhum artefato auditado foi alterado.
> Este markdown é o único arquivo escrito.
>
> **Data:** 12/08/2026 · **Branch:** `homologacao` · **HEAD:** `ee87f5e799` · **Tags locais usadas:**
> `v4.12.1`, `v4.16.2`.

---

## 1. Veredito, primeiro

**O plano não está executável como está — mas o que falta é pequeno perto do que existe.**

A qualidade das medições é alta e verificável: reproduzi o CSS do widget em **1.103.132 bytes**
(bate byte a byte), os **63,5%** de regras de ícone (bate: 63,5%), o **grafo eager de 575,1 KiB
gzip / 2,58 MB crus** (bate nas duas unidades), as **25 linhas / 29 ocorrências** de `n-brand`, o
limiar de luminância **0,17913** (bate na quinta casa) e o `!isCards` duplicado. Isso não é um plano
escrito de memória.

O que trava a execução são **quatro coisas**, nesta ordem:

1. **Um pré-requisito de backend inteiro desapareceu na consolidação** (BE-2: o lar onde tema,
   posição, offsets e formato do lançador passam a ser gravados). Sem ele, a Onda 3 tem um critério
   de aceite oficial que **é impossível de satisfazer** — e é justamente o critério que o próprio
   plano destaca como "o teste que falha hoje". **BLOQUEADOR.**
2. **Nenhuma das 10 arbitragens do PLANO-MESTRE foi propagada aos planos de frente.** Os quatro
   documentos continuam dizendo o contrário, com linha e parágrafo. O `mtime` confirma: os planos de
   frente são de 13:53–14:03 e o mestre é de 16:01; nenhum foi tocado depois. Como o próprio mestre
   declara que "os planos das frentes continuam sendo a fonte de verdade do detalhe de cada tarefa",
   o dev vai ler a fonte errada. **BLOQUEADOR.**
3. **A chave `widget_tracking` é aceita no strong params na Onda 3 (3.01) e só ganha validação na
   Onda 5 (5.01).** São duas ondas de janela em que qualquer agente com a inbox atribuída lê o que
   for gravado ali — que é exatamente o risco R6 que o plano declara mitigar. E o aceite de 3.01
   ("nenhum segredo aceito ali") não tem mecanismo que o sustente. **GRAVE.**
4. **Três critérios de aceite numéricos estão errados ou enfraquecidos**, sendo um deles uma
   regressão introduzida pelo próprio mestre (o grep de 1.04 deixou `shared/` de fora, enquanto o
   plano 22 o incluía). **GRAVE / MÉDIO.**

Nada disso invalida o plano. Tudo é corrigível em **P** (dois dias de escrita, zero código). A §9
lista o que precisa mudar antes da primeira linha.

---

## 2. O que refiz, e o que isso custou de confiança

| Medição do plano | Como refiz | Resultado |
|---|---|---|
| CSS do widget = 1.103.132 B | `stat` no artefato do manifest (`widget-EcEcykJV.css`) | **1.103.132** — exato |
| 63,5% do CSS são regras de ícone | regex de blocos `.i-*` sobre o CSS real | **63,5%** — exato |
| Grafo eager ~575 KiB / 2,58 MB crus | fecho transitivo do `manifest.json` + `gzip -9` | **575,1 KiB / 2.519 KiB (2,58 MB)** — exato |
| 25 linhas / 29 ocorrências de `n-brand` | `grep -rn` em `widget/`+`sdk/`+`shared/` | **25 / 29** — exato |
| Limiar WCAG 0,17913 | `sqrt(0,0525) − 0,05` | **0,17912878…** — exato |
| M1 (churn de 24 arquivos) | `git diff --numstat` nas duas tags | **23 de 24 conferem**; 1 célula em branco esconde +253/−14 |
| M2 (`validate_referer_url` byte-idêntico) | `git show` nas 3 versões | **confere** (334 → 405 → 536) |
| M3 (o que a v4.16.2 mudou em `Webhooks::Trigger`) | diff completo v4.12.1 × v4.16.2 × HEAD | **parcialmente falso** — ver A-03 |
| M4 (throttle plural × rota singular) | `git show v4.16.2` + `routes.rb:609` | **confere**, nos dois lados |
| M9 (sem colisão de migration) | `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` | **vazio** — confere |
| M10 (`conversation_resolved` fora do catálogo) | `webhook.rb:32` no HEAD e na v4.16.2 | **confere** |
| M11 (`WidgetBuilder.vue` órfão) | `stat` + `grep -rn` | **13.198 B, 443 linhas, zero referências** — confere |
| Contrastes de aceite (9,24 / 6,85 / 2,25) | fórmula WCAG em Python | **um confere, dois erram** — ver A-09 |
| "~74 custom properties no preview" | `grep -cE '^\s*--[a-z0-9-]+:'` | **62** — ver A-11 |

**Leitura honesta:** as medições de **peso e de código** são as mais confiáveis que já vi num plano
deste porte. As medições de **contraste** e as de **churn do fork** são as fracas — e as duas
sustentam critérios de aceite.

---

## 3. Achados classificados

### BLOQUEADOR

---

#### A-01 · O pré-requisito BE-2 sumiu na consolidação, e a Onda 3 tem um aceite impossível

**Evidência.**
`23-plano-config-dashboard.md:1396` define **BE-2** como pedido de backend: *"Configuração de
apresentação hoje presa ao snippet: tema, posição, offsets, tipo e texto do lançador, esconder
bolha, estilo do painel… Hoje vive em `localStorage` (**D1**)"*. Três tarefas do plano 23 dependem
dele — **T1.9**, **T1.10** e **T1.14** (`:1310`, `:1311`, `:1315`).

O defeito que BE-2 corrige é real e conferido por mim no código:

```
Settings.vue:350-352   widgetBuilderStorageKey() → `widgetBubble_${inbox.id}`
Settings.vue:507-512   LocalStorage.set(key, { position, type, launcherTitle })
Settings.vue:418-420   LocalStorage.get(key)
constants/localStorage.js:3   WIDGET_BUILDER: 'widgetBubble_'
```

Todas as quatro referências conferem exatamente.

No `PLANO-MESTRE.md`, **BE-2 não aparece nenhuma vez** (`grep "BE-" PLANO-MESTRE.md` devolve BE-4,
BE-6, BE-7, BE-8 e BE-1 — nunca BE-2, BE-3 ou BE-5). O bloco **3.01** (`PLANO-MESTRE.md:327`)
declara **três** chaves de topo — `widget_profile`, `widget_triggers`, `widget_tracking` — e
**nenhuma delas comporta aparência**. O bloco **3.09** (`:335`) pede a "Tela 1 completa (tema,
lançador, offsets, textos…)" com arquivos `appearance/` ⚪ + `Settings.vue` + i18n, e dependência
só de 3.08 (medidor de contraste).

E o critério de pronto da Onda 3, item 5 (`PLANO-MESTRE.md:593`):

> *"Mudar a posição para 'esquerda', salvar e reabrir **em outro navegador e como outro
> administrador**: continua 'esquerda'."*

**Consequência concreta.** Um dev executa 3.01 → 3.06 → 3.08 → 3.09 inteiros, entrega a Tela 1, e o
aceite falha — porque não existe coluna, chave jsonb, strong param nem montador que carregue
`position`. Ele vai então improvisar: ou grava dentro de `widget_profile` (quebra a validação de
inclusão que 3.01 exige), ou abre uma quarta chave de topo no `inboxes_controller.rb:217` (o arquivo
🔴 que a arbitragem A1 existe para tocar **uma vez só** — e a segunda edição destrói a economia de
risco que o mestre chama de "a maior de todo o plano", §9 frase 2). Nenhuma das duas saídas é boa, e
as duas acontecem sob pressão de prazo, sem revisão de arquitetura.

**Agravante.** **D1 é o único dos 11 defeitos do plano 23 sem bloco que o corrija.** D2→0.9,
D3→3.11, D4→3.10, D5→0.7, D6/D7→0.7/0.8, D8→0.8, D9→0.6, D10→0.8, D11→0.8. D1 aparece só como
*critério de aceite* de uma tarefa que não o corrige.

**Correção: P.** Acrescentar a quarta chave de topo `widget_appearance` à tarefa 3.01 (mesma edição
do strong params, custo zero de risco adicional), com JSON Schema em 3.02, entrega nos dois
montadores em 3.04, e a regra de precedência que o BE-2 já especifica (*banco é o padrão,
`chatwootSettings` no site sobrescreve, e a tela avisa que há override ativo*).

---

#### A-02 · Nenhuma arbitragem foi propagada — e o mestre manda o dev ler a fonte que ficou errada

**Evidência.** `PLANO-MESTRE.md:8-10` declara: *"Não repete os planos das frentes — **eles continuam
sendo a fonte de verdade do detalhe de cada tarefa**"*. As dez arbitragens da §5 alteram esse
detalhe. Nenhum dos quatro planos foi atualizado (`ls -l`: planos de frente 13:53–14:03, mestre
16:01, nenhum tocado desde).

| Arbitragem | O mestre decide | O plano de frente ainda diz | Linha |
|---|---|---|---|
| **A1** | sem migration, jsonb | *"Recomendação: coluna nova `widget_profile` em `channel_web_widgets`, como enum"* + `add_column :channel_web_widgets, :widget_profile…` | `22:552`, `22:573` |
| **A1** | idem | *"Critério de aceite, verificável e **obrigatório em W3.1**: rodar os 16 snapshots antes da migration / rodar a migration / rodar de novo"* | `22:663-670` |
| **A2** | valores `support` \| `marketing` | *"`widget_profile` com valores `suporte`/`marketing`; `nil` lido como `suporte`"* | `24:1613` |
| **A3** | perfil **propõe**, nunca reescreve | *"O perfil **não é lido pelo widget**. Ele **define os defaults** que são gravados"* + tabela que grava `pre_chat_form_enabled`, `csat_survey_enabled`, `continuity_via_email` | `23:720-731` |
| **A4** | sem backfill | **T1.4** *"Backfill: toda inbox Website existente vira `suporte`"* e **BE-3** *"+ backfill de todas as existentes"* | `23:1305`, `23:1397` |
| **A5** | avaliação client-side, config no boot | *"o servidor devolve **um** teaser e **um** conjunto de gatilhos já filtrados"* + BE-4 *"**Endpoint que devolve já filtrado** por host+path+query+dispositivo"* | `23:907`, `23:1398` |
| **A6** | sanear em `url_helper.rb` + 1 linha no modelo | *"**Não tocar:** `app/models/conversation.rb` (a validação de `referer` fica como está)"* | `25:231` |
| **A7** | BK-02 depende do merge | *"**BK-02** · **P** · **dep: —** · merge: **Baixo**"* | `24:1580` |

**Consequência concreta.** O dev de backend abre o plano 24 (é o dele), lê BK-08 e grava
`"suporte"`. O dev de frontend abre o plano 22 §B.3 e escreve
`widgetProfile: '<%= @web_widget.widget_profile %>'` no ERB — um método que, sob A1, não existe. O
dev de config abre o plano 23 e implementa o `useProfileVisibility` sobre o modelo "perfil grava
defaults", que contradiz o `WidgetProfile.resolve` → flags planas do bloco 3.03. Três pessoas, três
arquiteturas, o mesmo sprint.

O caso **A3** é o mais caro: `22:522-548` e `23:718-731` não são detalhes divergentes, são
**arquiteturas incompatíveis**. No 22, o servidor resolve o perfil em flags que o widget lê em
runtime; no 23, o perfil não chega ao widget e existe só como preset de escrita. O mestre arbitra a
favor do 22 (bloco 3.03), mas quem executar a Tela 0 pelo plano 23 constrói o outro.

**Correção: P.** Ou (a) um bloco `> ARBITRADO — ver PLANO-MESTRE §5 A_x` no topo de cada seção
afetada dos quatro planos, ou (b) uma linha no cabeçalho de cada plano dizendo *"onde este documento
divergir do PLANO-MESTRE, o mestre vence — as divergências conhecidas são A1…A12"*. A opção (a) é
melhor e continua sendo P.

---

### GRAVE

---

#### A-03 · A medição M3 afirma como novidade do merge algo que já existe hoje, e uma das três consequências de A7 cai

**Evidência.** `PLANO-MESTRE.md:97-100` diz:

> *"Na v4.16.2 [MEDIDO — `git show v4.16.2:lib/webhooks/trigger.rb`]: **o construtor virou**
> `initialize(url, payload, webhook_type, secret:, delivery_id:)`…"*

Refiz o `git show` na **v4.12.1**:

```ruby
# git show v4.12.1:lib/webhooks/trigger.rb  — linha 4
def initialize(url, payload, webhook_type, secret: nil, delivery_id: nil)
```

**Byte-idêntico.** O construtor não "virou" nada: já era assim na base do fork, e o `diff
v4.12.1..HEAD` do arquivo inteiro é **uma linha** (`perform_later(conversation…)` →
`perform_later(conversation.id…)`).

Consequência direta: a **consequência prática nº 2 da arbitragem A7** (`PLANO-MESTRE.md:794-795`) —
*"o item `delivery_id` estável entre tentativas fica **mais barato** depois do merge: o upstream já
passa `delivery_id:` pelo construtor"* — é **falsa**. Não fica mais barato depois do merge; já está
disponível hoje.

**O que M3 acertou:** a troca `RestClient` → `SafeFetch`, a classe `RetryableError` nova, e o
diagnóstico central de que **o defeito B3 continua de pé na v4.16.2** (o `raise` só vale para
`agent_bot_webhook`; account e api_inbox seguem engolindo). Isso confirmei linha a linha.

**Consequência concreta.** A decisão de A7 (esperar o merge) continua certa pelo argumento do
`SafeFetch` — mas está sustentada por um tripé em que uma perna é inventada. Pior: o `retry_on
StandardError, wait: :polynomially_longer, attempts: 5` do `webhook_job.rb:3` é **do fork** (o
upstream não tem, nos dois lados: 0/0). Ninguém escreveu isso em lugar nenhum, e é a informação que
diz **de quem é o retry que o bloco 1.13 vai fazer funcionar**. Se alguém decidir "aplicar o patch
upstream" (decisão N8, citada em A7), o patch upstream sozinho não resolve nada aqui, porque o
`retry_on` que ele destravaria não existe lá.

**Correção: P.** Reescrever M3 com o diff correto e remover a consequência 2 de A7; acrescentar uma
linha registrando que o `retry_on` é divergência nossa.

---

#### A-04 · `widget_tracking` fica duas ondas aceito sem validação, e o aceite de 3.01 não tem mecanismo

**Evidência.** Bloco **3.01** (`PLANO-MESTRE.md:327`), Onda 3: declara `widget_profile`,
`widget_triggers` e `widget_tracking` *"de uma vez"* no strong params, com aceite *"**nenhum segredo
aceito ali**"*. O bloco **3.02** valida **só os gatilhos** por `json_schemer`. O bloco que recusa
chave com cara de segredo é **5.01** (`:371`), na **Onda 5**, e sua dependência declarada é 3.01.

A arbitragem A1 (`:688-690`) declara a regra dura: *"nenhum segredo em `additional_attributes`,
porque qualquer agente com a inbox atribuída o lê"* — regra que confirmei no código:

```
app/views/api/v1/models/_inbox.json.jbuilder:27   json.additional_attributes resource.additional_attributes   # sem condicional
app/policies/inbox_policy.rb:22-27                Current.user.assigned_inboxes.exists?(id: record.id)        # qualquer agente
```

(e a linha 24 do policy ainda faz `return true if @user.is_a?(AgentBot)` — o mestre não menciona
que agent bots também leem).

**Consequência concreta.** Entre a Onda 3 e a Onda 5 existe uma chave jsonb de topo, aberta
(`widget_tracking: {}` no permit), sem schema, cujo conteúdo é servido inteiro no `GET` de inbox
para qualquer agente e para qualquer agent bot. É exatamente o risco **R6** do próprio plano. Basta
um cliente-piloto colar um Pixel + `access_token` na primeira tela improvisada para o vazamento
acontecer antes de a validação existir. E o aceite de 3.01 — *"nenhum segredo aceito ali"* — não é
verificável na entrega de 3.01, porque nada o implementa: a tarefa passa no code review por
afirmação.

**Correção: P.** Ou (a) 3.01 declara só `widget_profile`, `widget_triggers` e `widget_appearance`, e
`widget_tracking` entra junto com 5.01 (custo: uma segunda edição no arquivo 🔴 — aceitável, e
declarada); ou (b) 3.01 já traz o schema mínimo de `widget_tracking` com a lista negativa
(`*_token`, `*_secret`, `api_secret`), e 5.01 apenas o amplia. Recomendo (b).

---

#### A-05 · O mestre enfraqueceu o critério de aceite do plano 22 e deixa o defeito B1/B2 vivo no CSAT, nos chips e nos cards

**Evidência.** O aceite do bloco **1.04** (`PLANO-MESTRE.md:279`):

```
grep -rn "n-brand\|getContrastingTextColor\|--widget-color" widget/ sdk/  → vazio
```

O aceite das tarefas de origem, no plano 22 (`22:1469-1470`, W1.5 e W1.6):

```
W1.5: grep -rn "n-brand" app/javascript/widget/ app/javascript/shared/         → 0
W1.6: grep -rn "getContrastingTextColor" app/javascript/widget/ app/javascript/shared/ → 0
```

**O mestre trocou `shared/` por `sdk/`.** Não é equivalente: o inventário do próprio plano 22
(§A.1.1, itens **19 a 25**) coloca **7 dos 25 pontos de `n-brand` dentro de `shared/`**, e a família
5 (§A.1.5) coloca mais **5 arquivos** de `getContrastingTextColor` lá. Conferi todos no código:

| Ponto do plano 22 | Arquivo:linha real | Confere? |
|---|---|---|
| #19 | `shared/components/Button.vue:34` → `bg-n-brand hover:brightness-110` | ✅ |
| #20 | `shared/components/Spinner.vue:16` → `before:!border-t-n-brand` | ✅ |
| #21 | `shared/components/ChatOption.vue:44` → `border-n-brand` | ✅ |
| #22 | `shared/components/CustomerSatisfaction.vue:122` → `border-t-n-brand` | ✅ |
| #23 | `shared/components/CustomerSatisfaction.vue:191` → `focus:outline-n-brand` | ✅ |
| #24 | `shared/components/CardButton.vue:60` → `text-n-brand` | ✅ |
| #25 | `shared/components/ui/MultiselectDropdownItems.vue:167` → `focus:border-n-brand` | ✅ |

**Consequência concreta.** O grep do mestre fica **verde** com o CSAT (`CustomerSatisfaction.vue`),
os chips de resposta rápida (`ChatOption.vue`), os botões de card (`CardButton.vue`, `ChatForm.vue`)
e o botão genérico (`Button.vue`) ainda pintando com `#2dc46f` fixo e ainda calculando texto por YIQ
— dentro do widget, na tela do visitante. O defeito B1/B2, que é a bandeira da Onda 1
(*"o produto para de mentir"*), sobrevive nas quatro superfícies mais visíveis depois do balão. E o
critério de pronto da Onda 1, item 3 (`PLANO-MESTRE.md:547`), repete o grep enfraquecido — então o
encerramento da onda também dá falso verde.

**Correção: P.** `grep -rn "n-brand\|getContrastingTextColor\|--widget-color" app/javascript/widget/
app/javascript/sdk/ app/javascript/shared/` → vazio, nos dois lugares (bloco 1.04 e §4 Onda 1).
Acrescentar à mesma tarefa a nota do risco **R21** (mexer em `shared/` exige rodar também a suíte do
dashboard, porque `shared/` serve dashboard, portal e survey).

---

#### A-06 · Fundir W1.4–W1.8 num bloco só perdeu duas tarefas, dois arquivos e rebaixou um risco 🔴

**Evidência.** A §2.3 diz que W1.4–W1.8 estão no bloco **1.04**. A coluna *Arquivos* do 1.04 lista:
*"os 25 pontos da §A.1.1, `theme/colors.js` (só adição)"*, risco **🟢/🟡**.

O que ficou de fora:

- **W1.7** (`22:1471`) — *"Despintar a rampa `--iris-*`"*, arquivos `woot.scss:193,255,272`, risco
  **🔴** (o plano 22 marca `woot.scss` como campo minado). Nem o arquivo nem o risco aparecem no
  bloco 1.04.
- **W1.8** (`22:1472`) — *"Alvo de contraste parametrizável"*, arquivo
  `shared/helpers/colorHelper.js:12-29`, com o diagnóstico de que *"hoje o alvo é fixo em 3,1,
  correto para componente (SC 1.4.11) e insuficiente para texto (SC 1.4.3)"*. Não aparece.

**Consequência concreta.** Quem executar pelo mestre entrega 1.04 sem tocar `colorHelper.js` — e o
`adjustColorForContrast` continua mirando 3,1:1 para texto, que é a norma errada. Isso vaza direto
para 3.08 (o medidor de contraste da tela) e para 1.02 (a derivação no servidor), cujo aceite exige
que os dois *"produzam o mesmo hex para 20 cores"*: um deles vai mirar 4,5 e o outro 3,1. O bug
aparece como "o medidor da tela discorda do widget" em plena Onda 3, com dois times envolvidos.

E o risco declarado do bloco cai de 🔴 para 🟢/🟡 sem que nada tenha mudado no `woot.scss`.

**Correção: P.** Recolocar `woot.scss:193,255,272` e `shared/helpers/colorHelper.js:12-29` na coluna
de arquivos do 1.04, e o risco para 🔴 (ou quebrar 1.04 em dois blocos, que é o mais honesto: o
`woot.scss` é a única parte 🔴 do conjunto).

---

#### A-07 · A promessa de rastreabilidade tem três furos, e um deles é uma tarefa de conformidade

**Evidência.** A §2.3 se chama *"Cobertura — nada ficou de fora"* e a §2.2 declara que a coluna
*Origem* *"dá os identificadores nativos das frentes — é a rastreabilidade"*. Extraí a coluna Origem
dos 106 blocos (expandindo faixas como `T-C2.1–T-C2.8`) e cruzei com os identificadores definidos em
cada plano:

| Frente | Definidos | Não citados em nenhuma coluna Origem |
|---|---:|---|
| 22 (W\*) | 58 | **0** |
| 25 (T-C\*/T-I\*) | 124 | **0** |
| 24 (BK-\*) | 39 | **BK-33, BK-36, BK-37** |
| 23 (T\*/BE-\*) | 64 | **T1.4** (eliminada, declarado) · **BE-1, BE-2, BE-3, BE-5, BE-8** |

A contagem total de 277 (`58+56+39+80+44`) **confere**, e os 106 blocos também (10/23/18/17/17/21).
O problema é qualitativo:

- **BK-36** (filtro por inbox) e **BK-37** (assinar os três caminhos) — o *trabalho* está no bloco
  4.13, que cita `T-I5.3/5.4/5.5`. Só o identificador se perdeu. **MENOR.**
- **BK-33** (`24:1729-1731`) — *"Consentimento… incluindo o kill switch por conta e por inbox… com
  consentimento negado, nenhum evento sai para destino externo e o motivo fica registrado na
  entrega (`discarded`)"*. O bloco 5.09 cobre o consentimento **no SDK e no payload**; o kill switch
  aparece só no aceite de 5.14. **A leitura do consentimento dentro dos jobs de entrega
  server-side** — que é o que impede o evento de sair — não é escopo declarado de nenhum bloco.
  Para uma frente cuja verificação V2 é jurídica, isso é **GRAVE**.
- **BE-5** (`23:1399`) — *"**Lead incompleto**: persistir resposta parcial de pré-chat antes da
  conversa existir"*. Citado como dependência em `23:1079` e `23:1155`. Não virou bloco, **e não
  está na §8 ("O que NÃO vamos fazer")**. Num plano cuja tese é captura de lead, "salvar o lead que
  abandonou no meio do formulário" some sem decisão registrada. **GRAVE.**

**Consequência concreta.** Numa reunião de escopo, "lead incompleto" volta como surpresa — e volta
depois de 3.14 e 4.03 estarem construídas sem ele, que é quando fica caro. E o kill switch de
consentimento vira descoberta no code review de 5.11.

**Correção: P.** Três linhas: BK-33 vira bloco próprio (ou entra explicitamente em 5.11), BE-5 entra
na §8 com o motivo (ou vira bloco na Onda 4), e BK-36/BK-37 entram na coluna Origem de 4.13.

---

### MÉDIO

---

#### A-08 · `App.vue < 250 linhas` não é alcançável pelo escopo do bloco 1.09

**Evidência.** `App.vue` tem **386 linhas** (`<script>` 1–359, `<template>` 361–382, `<style>`
384–386). O bloco 1.09 extrai `App.vue:258-345` — **88 linhas** — para `widget/bridge/`. Trocando o
bloco por uma chamada de ~5 linhas: **386 − 88 + 5 = 303 linhas**.

O aceite exige **< 250**. Faltam 53 linhas que nenhuma tarefa do plano identifica.

**Consequência concreta.** A tarefa é executada corretamente e reprovada no aceite. O dev então (a)
extrai mais coisa por conta própria, sem plano — em cima de `App.vue`, que o upstream mexeu (+4/−0)
— ou (b) o revisor libera o aceite "porque é só um número", e a partir daí todo aceite numérico do
plano vira negociável. A segunda é pior e é a mais provável.

**Nota de precisão:** o bloco fala em *"16 ramos de `else if`"*. São **1 `if` + 15 `else if`** (16
ramos, 15 `else if`). Irrelevante para a execução, citado por completude.

**Correção: P.** Ou baixar o aceite para `< 310 linhas`, ou nomear o que mais sai (os candidatos
óbvios são `createWidgetEvents`, `sendLoadedEvent`/`sendRNWebViewLoadedEvent` e o bloco de
`setColorScheme`).

---

#### A-09 · Dois dos três contrastes de aceite estão errados, e o mesmo par aparece com dois valores

**Evidência.** Calculei pela fórmula WCAG 2.x (luminância relativa, `sRGB`):

| Par | O que o plano diz | Real | Onde |
|---|---|---|---|
| `#2DC46F` sobre preto | **9,24:1** (mestre) / **9,35:1** (plano 22) | **9,2371:1** | `MESTRE:277` × `22:1466` × `23:836` |
| `#009CE0` sobre preto | **6,85:1** (mestre, 22 **e** 23) | **6,8318:1** | `MESTRE:277`, `22:1466`, `23:1433` |
| branco sobre `#2DC46F` | **2,25:1** (§1 e `23:816`) / **2,27:1** (§4 Onda 1 item 2) | **2,2734:1** | `MESTRE:174` × `MESTRE:546` |

O mestre acerta o 9,24 (e o plano 22 erra), erra o 6,85 junto com os outros dois, e apresenta o
**mesmo par de cores** como 2,25 no resumo executivo e 2,27 no critério de pronto — sem que nada
distinga os dois contextos (é `text-white` sobre `bg-n-brand` nos dois casos; conferi
`ChatHeader.vue:45` e `_conversation.scss:185`).

**Consequência concreta.** O aceite de 1.02 e de 3.08 é *"o resultado bate com o servidor em 20
cores"*. Se o teste for escrito com os números do documento, ele falha por 0,02 e alguém passa meio
dia procurando bug numa implementação correta. E o "2,25:1" é o **primeiro número do resumo
executivo** — o número que vai para o slide.

**Correção: P.** Corrigir os três valores e escrever os aceites com tolerância declarada
(`toBeCloseTo(x, 2)`), não com igualdade exata.

---

#### A-10 · O harness da 0.1 é tratado como arquivo novo, e não é — e a dependência que ele precisa não existe

**Evidência.** Bloco **0.1** (`PLANO-MESTRE.md:254`): arquivos *"`playwright.config.js`,
`spec/e2e/widget/` ⚪, host fixo ⚪"*, risco de merge **⚪** — que a legenda define como *"arquivo
novo (risco zero **por construção**)"*. Idem em W0.5 (`22:1454`).

No repositório:

```
playwright.config.js                    JÁ EXISTE (testDir: 'spec/e2e', 2 projects definidos)
spec/e2e/copilot/                       15 specs
spec/e2e/resolve-gate/                  existe
@playwright/test                        AUSENTE do package.json e do node_modules
```

O próprio cabeçalho do `playwright.config.js` diz: *"SETUP REQUIRED (one-time, before first run): 1.
Add `@playwright/test` to devDependencies… 2. Install browsers"*.

**Consequência concreta.** Três coisas. (1) O risco não é ⚪: mexer nos `projects` de um config que
serve duas suítes existentes pode derrubar a suíte de Copilot, e o plano não menciona que elas
existem. (2) O aceite *"`--project=widget` roda"* depende de um `pnpm add -D @playwright/test` +
`playwright install chromium` que nenhuma tarefa declara — e 0.1 é a **primeira tarefa do plano
inteiro**, bloqueante do merge. (3) A afirmação da §3 e da §9 frase 6 (*"não existe um teste de
render de componente do widget hoje"*) é verdadeira — conferi os 33 specs, todos de helper/store/
composable, nenhum monta componente — mas o plano trata o terreno como vazio quando há um esqueleto
meio construído (e, hoje, inexecutável).

**Correção: P.** Reclassificar 0.1 para 🟡, listar `package.json` entre os arquivos tocados, e
acrescentar ao aceite que as suítes `copilot` e `resolve-gate` continuam sendo descobertas pelo
config.

---

#### A-11 · A tabela M1 tem uma célula em branco no arquivo mais perigoso do plano

**Evidência.** `PLANO-MESTRE.md:83`:

| Arquivo | Upstream | Fork | Leitura |
|---|---:|---:|---|
| `app/models/conversation.rb` | **+79 / −8**, 4 commits | **—** | 🔴 → ver **M2** |

Todas as outras 23 linhas da tabela trazem número nas duas colunas. Refiz:

```
git diff --numstat v4.12.1 HEAD -- app/models/conversation.rb  →  253  14
```

**+253 / −14 no fork.** É o segundo maior churn de fork da tabela inteira.

**Consequência concreta.** A arbitragem **A6** conclui que *"o risco real é o **deslocamento** do
arquivo (que o merge resolve), não o conflito no método"*, e rebaixa BK-12 de risco **Médio** para
**Baixo**. A conclusão sobre o **método** continua correta — conferi que `validate_referer_url` é
byte-idêntico nas três versões (v4.12.1:334 → v4.16.2:405 → HEAD:536). Mas a conclusão sobre o
**arquivo** foi tirada com metade da medição: um merge de `conversation.rb` com +79/−8 de um lado e
+253/−14 do outro não é um deslocamento, é um merge de três vias substancial. O dev que ler M1
conclui que o fork não mexeu no arquivo e não se prepara para isso.

**Correção: P.** Preencher a célula e reescrever a última frase de A6: a decisão (lógica no helper
0/0, uma linha de chamada no modelo) continua certa — e fica **mais** justificada com o número real,
não menos.

---

#### A-12 · O parser de origem (1.19) não depende do saneamento do `referer` (1.20), e o texto do plano diz que deveria

**Evidência.** Coluna *Depende* da tabela mestra: **1.19** dep `1.18`; **1.20** dep `0.2`. A §3 item
4 (`PLANO-MESTRE.md:487-489`) diz: *"ele entrega origem para 100% das conversas **cujo `referer`
sobreviveu à validação** — não para 100% da base. **Por isso 1.20 (sanear antes de anular) anda
junto**"*.

"Anda junto" não é dependência. Nada no grafo impede 1.19 ir a produção antes de 1.20.

**Consequência concreta.** Se o parser subir primeiro, as conversas com URL malformada (espaço não
escapado, colchete cru) entram no período de parser-ativo/saneamento-inativo produzindo
`referer = nil` e origem em branco — e o backfill (1.21) só recupera o que estiver no banco, que já
foi anulado. É perda silenciosa de dado no exato entregável que o plano vende como "o argumento que
compra orçamento".

**Correção: P.** `1.19 dep: 1.18, 1.20`.

---

#### A-13 · 5.12 depende de 5.11 e precede 5.11 — o único ponto do grafo que se lê como ciclo

**Evidência.** Coluna *Depende* do bloco 5.12: `5.11 (precede o modo com PII)`. A §3 item 9
(`:512-514`) reforça: *"o modo 'sem PII' (5.12) deve ser construído **antes** do modo com PII"*.

**Consequência concreta.** Quem montar cronograma a partir da coluna *Depende* (que é o uso
declarado da tabela) coloca 5.12 depois de 5.11 inteira, e perde exatamente o objetivo da separação:
ir ao ar sem esperar o jurídico (verificação V2). É o único item cuja dependência precisa ser lida
em prosa para não ser executada ao contrário.

**Correção: P.** Quebrar 5.11 em `5.11a` (fila, retry, DLQ, normalização — sem PII) e `5.11b`
(campos de PII hasheados, dep: `5.11a` + V2), e 5.12 vira parte de 5.11a. Isso também resolve
metade de A-14.

---

#### A-14 · Cinco blocos escondem mais de três tarefas dentro de um "G"

**Evidência.** O plano declara em §2.2 que *"um bloco pode cobrir mais de uma tarefa da mesma frente
quando elas compartilham arquivos e dependências"*. Em cinco casos o bloco virou um projeto:

| Bloco | Esf. | O que absorve | Contagem real |
|---|:---:|---|---|
| **5.11** | G | T-C5.1–T-C5.10 + BK-32 | **11 tarefas**, 3 APIs de terceiro (CAPI, MP, Enhanced Conversions), hash, retry, DLQ |
| **5.06** | G | T-C1.3/1.5/1.6/1.8 + T4.1–T4.5, T4.8–T4.10 | **13 tarefas**, 4 sub-abas |
| **5.21** | G | T-C9.1–T-C9.10 + BK-40 | **11 tarefas**, 2 integrações + migration + janela de 90 dias |
| **4.04** | G | T3.1–T3.6 + T3.9 | **7 tarefas** |
| **5.02** | G | T-C1.2/1.7 + BK-30 + **fluxo OAuth de duas plataformas** | migration + modelo + controller + policy + 2 OAuth |

**Consequência concreta.** Um "G" que é 11 tarefas não é estimável nem paralelizável nem
verificável por incremento: ou está pronto ou não está, e a primeira notícia de atraso chega no
fim. **5.02** é o mais agudo: ele mistura uma tarefa de infraestrutura de segurança (tabela com
`encrypts`, `audited`, serialização que nunca devolve o segredo) com **dois fluxos OAuth de
terceiros** — que dependem de app review da Meta e do Google, prazo externo que o plano não menciona
em lugar nenhum (nem na §6, nem nas verificações da §7).

**Correção: M.** Quebrar 5.02 em "credencial colada à mão" (que destrava 5.11 e não depende de
ninguém de fora) e "OAuth de um clique" (que depende de app review); quebrar 5.11 conforme A-13. Os
outros três podem ficar, desde que o aceite seja por sub-aba/sub-gatilho.

---

#### A-15 · O agregado "C0 = P" do plano 25 não bate com as suas próprias sub-tarefas

**Evidência.** `25:795` (tabela A.14): *"**C0** parser retroativo · esforço **P**"*. As sub-tarefas
da §A.2 do mesmo documento: T-C0.1 **P**, T-C0.2 **P**, T-C0.3 **P**, T-C0.4 **M**, T-C0.5 **M**,
T-C0.6 **M**, T-C0.7 **P** — três **M** dentro de um agregado **P**.

O mestre corrigiu isso na prática (1.18 P, 1.19 M, 1.21 M, 1.22 M), mas quem ler o plano 25 para
dimensionar a frente lê "P".

**Consequência concreta.** A frente de tracking é apresentada como começando por algo barato. Quem
usar a tabela A.14 para prometer prazo promete errado por um fator de ~3.

**Correção: P.** Corrigir o agregado para **M**.

---

### MENOR

- **A-16 · `theme/colors.js:123` está errado — é `:227`.** O plano 22 (`22:206`) afirma, marcado
  `[FATO]`: *"`bg-n-brand` resolve por `theme/colors.js:123` → `brand: '#2dc46f'`"*. A linha 123
  desse arquivo é `2: 'rgb(var(--iris-2) / <alpha-value>)'`. O valor correto é **`theme/colors.js:227`**
  (e o arquivo fica na **raiz** do repositório, não em `app/javascript/`). Curiosamente a referência
  à v4.16.2 (`:229`) está **certa**. *Consequência:* pequena — o dev acha o símbolo por grep em 10
  segundos. Registrado porque é a **única referência `arquivo:linha` errada** que achei em 46
  conferidas, e está marcada `[FATO]`.

- **A-17 · "O fork só trocou o valor" em `theme/colors.js` é falso.** O diff é **+15/−15**: além do
  `brand`, o fork trocou a rampa `woot.*` inteira de `blue`/`blueDark` para `green`/`greenDark` e
  acrescentou `teal-text`/`teal-border`. *Consequência:* o bloco 1.04 marca o arquivo como "só
  adição" e risco 🟡; a região do `brand` na v4.16.2 tem vizinhança diferente (`portal:` no lugar de
  `background:`), então o merge conflita ali. Vale uma linha de aviso.

- **A-18 · "~74 custom properties" no preview são 62.** `grep -cE '^\s*--[a-z0-9-]+:'` em
  `widget-preview/Widget.vue` (arquivo inteiro, 329 linhas) devolve **62**. O bloco 254–328 citado
  está correto e a conclusão (paleta duplicada em literal, dessincroniza em silêncio) é verdadeira.
  Erro de ~19% num número marcado `[MEDIDO]`.

- **A-19 · `show.html.erb:9-30` usa a inbox em 12 chaves, não 11.** A medição M5 lista onze e
  esquece `utcOffset` (`:27`, que também lê `@web_widget.inbox.timezone`). A conclusão que M5
  sustenta (o ERB já tem a inbox na mão → arbitragem A1) fica **mais** forte, não menos.

- **A-20 · Duas tarefas com dependência "—" tocam código que o merge 0.2 vai mexer.** O plano declara
  em §2.1 (`:265`) que *"0.2 é bloqueante para tudo que toca código de aplicação"*, e em §2.5 repete
  como regra dura. Mas **2.17** (dep `—`) edita `app/javascript/widget/i18n/locale/pt_BR.json`, que
  está entre os 113 arquivos do widget que o merge muda. *Consequência:* conflito bobo, resolvido em
  minutos — mas é uma contradição interna com uma regra que o plano trata como inegociável.

- **A-21 · Dois blocos usam curinga na coluna de dependência.** `2.18` dep `0.5, 2.*` e, no plano 22,
  `W3.1` dep `W2.*`. O plano 22 abre a §F afirmando *"nenhuma tarefa depende de algo que venha
  depois dela"* — verdade — mas `W2.*` não é uma dependência acionável. *Consequência:* quem monta
  quadro Kanban não sabe se 2.18 espera 2.01–2.17 inteiras ou só as de peso (2.01, 2.05, 2.09).

- **A-22 · O aceite do bloco 1.08 perdeu a asserção de `@font-face`.** W1.16 (`22:1480`) exige
  *"nenhum `@font-face` no CSS do widget"*; o bloco 1.08 do mestre só cobre "CSS ≤ 80 KB" e "logo
  < 5 KB". *Consequência:* o teto de 80 KB pode ser atingido sem remover os 7 `@font-face`, e a §8
  item 8 (*"não adotar webfont"*) fica sem asserção que a sustente.

- **A-23 · `interactive_action.rb:19-23` cobre 5 constantes, não as citadas.** O plano 24 (BK-22)
  cita `:19-23` para "os mesmos limites de conteúdo que o WhatsApp já enforça". As linhas reais são
  19–23 (`INTERACTIVE_ITEMS_LIMIT` … `INTERACTIVE_BODY_LIMIT`) — **confere**. Registrado como
  não-achado para o leitor não achar que pulei.

- **A-24 · `update_channel` é `:125-133`, não `:125-132`.** Plano 22 §B.2. Off-by-one no `end`.

### COSMÉTICO

- O bloco 1.09 e o plano 22 dizem "16 ramos de `else if`"; são 1 `if` + 15 `else if`.
- `23:1292` (T0.6) aponta `channels/Website.vue:22` e `23:541` (D11) aponta `:21` para o mesmo fato.
  A linha correta é **21** (`channelWidgetColor: '#2dc46f'`).
- O mestre transcreve `req.path_without_extensions` ao citar o HEAD; no HEAD o método ainda tem o
  typo do upstream (`path_without_extentions`), corrigido só na v4.16.2. A conclusão de M4 não muda,
  mas o dev que grepar pela grafia correta no HEAD não acha nada.

---

## 4. Tabela de conferência das referências `arquivo:linha`

46 referências, escolhidas por peso (as que sustentam arbitragem, defeito verificado ou critério de
aceite), espalhadas pelos cinco documentos. **Taxa de acerto: 45/46 = 97,8%.**

| # | Doc | Referência citada | O que o plano afirma | Verificação no HEAD | Veredito |
|---:|:---:|---|---|---|:---:|
| 1 | M | `config/routes.rb:609` | rota é `resource :contact` (singular) | `resource :contact, only: [:show, :update]` | ✅ |
| 2 | M | `show.html.erb:9-30` | inbox usada em 11 chaves | usada em **12** (falta `utcOffset`) | ⚠️ |
| 3 | M | `_inbox.json.jbuilder:27` | serve `additional_attributes` inteiro, sem condicional | idêntico | ✅ |
| 4 | M | `inbox_policy.rb:22-27` | `show?` liberado a agente com inbox atribuída | idêntico (+ `AgentBot` na `:24`) | ✅ |
| 5 | M | `inbox.rb:50` | precedente `store_accessor :additional_attributes` | idêntico | ✅ |
| 6 | M | `ConfigurationPage.vue:94` | valor gravado é `'per_agent'` | idêntico | ✅ |
| 7 | M | `web_widget.rb:58` | `enum reply_time` em inglês | idêntico | ✅ |
| 8 | M | `db/schema.rb:781` / `:847` | `companies` e índice já existem | idênticos | ✅ |
| 9 | M | `webhook.rb:32` | `conversation_resolved` fora do catálogo | confere no HEAD **e** na v4.16.2 | ✅ |
| 10 | M | `rack_attack.rb:182-184` | throttle plural × rota singular | confere nos dois lados | ✅ |
| 11 | M | `agent_bots/webhook_job.rb:3-6` | molde do `retry_on` que relança | idêntico | ✅ |
| 12 | M | `events_controller.rb:20-22` | `permit(:name, …)` sem allowlist | idêntico | ✅ |
| 13 | M | `events_controller.rb:4-8` | responde `head :no_content` | idêntico | ✅ |
| 14 | M | `contact_identify_action.rb:128-132` | `deep_merge` de `custom_attributes` | idêntico | ✅ |
| 15 | M | `CustomAttributes.vue:76-89` | painel itera **definições** | idêntico | ✅ |
| 16 | M | `_conversation.scss:50-74,106-118` | agrupamento por irmão adjacente | `+ .agent-message-wrap` presente | ✅ |
| 17 | M | `ConversationWrap.vue:63-173` | `mounted`/`updated` com scroll | idêntico | ✅ |
| 18 | M | `Messages.vue:22` | classe `bg-n-chat-bg` morta | presente | ✅ |
| 19 | M | `sdk.js:147,242-290` + `IFrameHelper.js:341-347` | breakpoints 667/667/668 coexistem | `min-width:667`, `max-width:667`, `max-width:668` | ✅ |
| 20 | M | `useDarkMode.js:20` + `App.vue:369-381` | `dark` no `<div>`, não no `<html>` | confere | ✅ |
| 21 | M | `useMessageFormatter.js:19` / `MessageFormatter.js:109` | nova instância de MarkdownIt por chamada | `new MessageFormatter(...)` dentro de `formatMessage` | ✅ |
| 22 | M | `widget/i18n/locale/pt_BR.json:70` | `"mandatório"` | `"Nome Completo é mandatório"` | ✅ |
| 23 | M | `entrypoints/widget.js:32-40` | FormKit carregado no eager | `app.use(plugin, defaultConfig({...}))` | ✅ |
| 24 | M | `inboxes_controller.rb:217` | ponto único do strong params | `{ additional_attributes: [...] }` | ✅ |
| 25 | M | `inboxes_controller.rb:52-56` | merge **raso** de `additional_attributes` | `(@inbox.additional_attributes \|\| {}).merge(...)` | ✅ |
| 26 | M | `widget-preview/Widget.vue:94-101` | snippet por `substring(0, 13)` | idêntico | ✅ |
| 27 | M | `web_widget.rb:34-40` | `EDITABLE_ATTRS` a ampliar | idêntico | ✅ |
| 28 | M | `ArticleViewer.vue:13` | `bg-white` sem variante dark | `<div class="bg-white h-full">` | ✅ |
| 29 | M | `widget/messages_controller.rb:15-28` | `update` de `input_email` não gera `incoming` | confere | ✅ |
| 30 | M | `automation_rule_listener.rb:299-312` | `resume_pending_reply` exige `message.incoming?` | idêntico | ✅ |
| 31 | M | `webhook_listener.rb:130-146` | entrega a todos os `account_type` | idêntico | ✅ |
| 32 | M | `_webhook.json.jbuilder:6` | `json.secret webhook.secret` exposto | idêntico | ✅ |
| 33 | M | `system_prompts_service.rb:312-322` | atributos do contato entram no prompt | idêntico | ✅ |
| 34 | M | `production.rb:23-26` | `max-age` de 1 ano vindo do **Rails** | idêntico | ✅ |
| 35 | M | `incoming_message_base_service.rb:194` | `referral` copiado inteiro | idêntico | ✅ |
| 36 | M | `account.rb:190-193` | bitmask cheio → `internal_attributes` | confere (`features.yml` tem **65** entradas) | ✅ |
| 37 | 22 | `theme/colors.js:123` | `brand: '#2dc46f'` | está em **`:227`** (e na raiz do repo) | ❌ |
| 38 | 22 | os **25** pontos de `n-brand` (§A.1.1) | 25 linhas / 29 ocorrências | **25 / 29** — conferi as 25 uma a uma | ✅ |
| 39 | 22 | `IFrameHelper.js:181` | SDK já lê `channelConfig.widgetColor` | idêntico | ✅ |
| 40 | 22 | `inboxes_controller.rb:135-137` / `:145-148` | caminho do update de canal | idênticos (`:125-132` é `:125-133`) | ✅ |
| 41 | 22 | `AgentMessageBubble.vue:42-67,92-152` | 8 computed, `!isCards` duplicado, 2 ausentes | **confirmado**: `!isCards` duas vezes; `isIntegrations`/`isTemplateEmail` fora da guarda | ✅ |
| 42 | 23 | `Settings.vue:350-352, 418-430, 507-512` + `localStorage.js:3` | posição/tipo/título no `localStorage` | as quatro conferem | ✅ |
| 43 | 23 | `Settings.vue:231-233` × `:948` × `:538` | `ColorPicker` muta o getter do store | as três conferem | ✅ |
| 44 | 23 | `widgets_controller.rb:79-86` | `allowed_domains` vazio remove `X-Frame-Options` | `allow_iframe_requests` em 79–86 | ✅ |
| 45 | 24 | `conversation.rb:80-81`, `custom_attribute_definition.rb:35-38,73-78`, `custom_attribute_filter_helper.rb:6,40-46`, `events/types.rb:23`, `integrations/hook.rb:92-96`, `flow.rb:42`, `application.rb:113-121`, `Gemfile:37` | 8 âncoras de BK-06/09/05/14/21/00 | **8 de 8** conferem | ✅ |
| 46 | 25 | `base_controller.rb:38-44` (linha 42 grava `referer`, linha 44 é `custom_attributes`) | ponto de entrada de C0 | confere **linha a linha** | ✅ |

**Leitura.** 97,8% de acerto em referências de código é excepcional para 729 citações num corpus de
10.708 linhas. O erro achado (#37) é irrelevante na prática. **As afirmações sobre o código são
confiáveis.** Os problemas do plano estão na **consolidação**, não na apuração.

---

## 5. Grafo de dependências

Extraí a coluna *Depende* dos 106 blocos e montei o grafo.

**O que está certo, e é raro:**

- **Zero ciclos.**
- **Zero dependências para frente**: nenhum bloco depende de um bloco de onda posterior.
- **Zero referências a blocos inexistentes.**
- O caminho crítico declarado na §2.4 (`0.1 → 0.2 → 0.3 → 1.01 → 1.02 → …`) é consistente com a
  tabela.

**Os cinco problemas:**

```
                      ┌─────────────────────────────────────────────┐
   0.1 ──► 0.2 ──► 0.3 ──► 0.5 ──► 1.08                             │
    │        │                                                      │
    │        ├──► 1.01 ──► 1.02 ──► 1.03 ──► 1.05 ──► 2.14 / 4.06   │
    │        │       │        └──► 1.04  ⚠️ [A-05/A-06]             │
    │        ├──► 1.09 ──► 1.23 ──► 5.09 / 5.16 / 5.17              │
    │        │       └──► 2.11 / 2.13 / 5.03                        │
    │        ├──► 1.16 ──► 1.17 / 1.18 ──► 1.19 ──► 1.21 ──► 1.22   │
    │        │                              ▲                       │
    │        │                    ✖ FALTA  1.20  [A-12]             │
    │        ├──► 1.20 (sanear)                                     │
    │        └──► 3.01 ──► 3.02 / 3.03 / 3.06 / 5.01 / 5.18         │
    │                 │        └──► 3.04 ──► 3.05 ──► 3.17          │
    │                 │                 └──► 3.11                   │
    │                 ✖ FALTA widget_appearance (BE-2)  [A-01]      │
    │                 ⚠ widget_tracking sem schema até 5.01 [A-04]  │
    │                                                               │
    └── 0.4 / 0.6 / 0.10 (paralelos, sem dep)                       │
                                                                    │
   2.01 ──► 2.02…2.09  ⟶  2.18 dep "2.*"  ⚠ curinga [A-21]          │
   5.02 ──┐                                                         │
   5.03 ──┴──► 5.11 ⇄ 5.12  ⚠ lê-se como ciclo [A-13]               │
             └──► 5.13 / 5.14 / 5.21                                │
```

| # | Problema | Bloco | Gravidade |
|---|---|---|---|
| G1 | **Dependência inexistente**: 3.09 exige persistência de aparência que nenhum bloco cria | 3.01/3.09 | **BLOQUEADOR** |
| G2 | **Dependência faltando**: 1.19 (parser) deveria depender de 1.20 (saneamento) | 1.19 | MÉDIO |
| G3 | **Dependência que se lê como ciclo**: 5.12 dep 5.11 **e** precede 5.11 | 5.12 | MÉDIO |
| G4 | **Curinga**: `2.*` e (no plano 22) `W2.*` não são dependências acionáveis | 2.18, W3.1 | MENOR |
| G5 | **Regra própria violada**: 2.17 tem dep `—` e toca arquivo do merge | 2.17 | MENOR |

**Dependência externa bem tratada, e vale o elogio de uma linha:** 5.11 (`verif. 2 — DPA`) e 5.21
(`verif. 1 — CTWA`) declaram bloqueio externo **na própria coluna de dependência**. É o tratamento
certo, e é raro. O que falta é o mesmo para o **app review da Meta e do Google** em 5.02 (A-14).

---

## 6. Contradições entre os cinco documentos

Além das oito arbitragens não propagadas (A-02), três contradições que **não** são arbitragem — ou
seja, ninguém as viu:

1. **Arquitetura do perfil (22 × 23).** `22:597-636` faz o servidor resolver o perfil em
   `profileConfig` (11 flags planas) entregue ao widget; `23:718-731` afirma que *"o perfil vive só
   no dashboard"* e o widget nunca o vê. O mestre escolhe o modelo do 22 (bloco 3.03) mas **não
   registra a divergência na §5** — então ela não aparece nem como arbitragem, e o plano 23 fica
   internamente coerente com uma arquitetura descartada.

2. **`profileConfig` tem 11 chaves no 22 e um conjunto diferente no 23.** `22:612-626` lista
   `showKnowledgeBase`, `showConversationList`, `teaserEnabled`, `teaserDelayMs`,
   `teaserScrollPercent`, `captureFlow`, `primaryExit`, `csatOnResolve`, `emailContinuity`,
   `homeLayout`, `aiLabelPersistent`; `23:722-731` fala de `pre_chat_form_enabled`,
   `continuity_via_email`, `csat_survey_enabled` e "Central de Ajuda". Os nomes não se cruzam. O
   bloco 3.03 do mestre diz "flags planas" sem fixar a lista. *Consequência:* o backend entrega um
   contrato e o front consome outro, e a descoberta é em integração.

3. **Onde a lista de gatilhos é avaliada (A5) tem uma segunda ordem que ninguém arbitrou.** O
   mestre decide client-side; mas `23:1339-1345` faz **T3.1, T3.2 e T3.7 dependerem de BE-4**, cuja
   definição (`23:1398`) é *"endpoint que devolve já filtrado"*. Sob A5, BE-4 muda de natureza — e
   as três tarefas do plano 23 passam a depender de 3.02 (schema no jsonb), não de um endpoint.
   Ninguém reescreveu BE-4.

---

## 7. Onde eu não achei nada relevante

Digo explicitamente, para não parecer que pulei:

- **Precisão das referências de código.** Uma errada em 46. Não há padrão de invenção.
- **Medições de peso.** Reproduzi quatro delas e todas bateram, uma com precisão de byte.
- **Ciclos no grafo e ordenação das ondas.** Não há.
- **Cobertura numérica.** 277 tarefas e 106 blocos conferem na soma e na distribuição por onda.
- **A lista §8 ("o que NÃO vamos fazer").** 25 recusas, cada uma com um número que a sustenta.
  Não achei nenhuma recusa arbitrária, e não achei item que devesse estar na lista e esteja fora —
  **com a exceção do BE-5 (A-07)**, que não está nem dentro nem fora.
- **As sete verificações pendentes da §7.** Estão bem construídas: cada uma diz quem responde, se
  bloqueia e o que muda conforme a resposta. A V3 inclusive antecipa que "volume baixo é achado, não
  fracasso" — é o tipo de honestidade que faz o plano ser confiável.
- **Os riscos R1–R25.** Não achei risco declarado que seja falso. Achei riscos **não** declarados —
  estão na §8 abaixo.

---

## 8. Riscos que o plano não declara

| # | Risco | Por que importa | Onde deveria estar |
|---|---|---|---|
| **N1** | **App review da Meta e do Google** para o OAuth de um clique (5.02) é prazo externo de semanas, fora do controle do time | 5.02 bloqueia 5.11, 5.21 e a Onda 5 inteira. É a segunda dependência externa mais cara do plano, e a §7 lista sete verificações sem incluí-la | §7 (como V8) e coluna *Depende* de 5.02 |
| **N2** | **`shared/` é consumido por dashboard, portal e survey** — e 12 dos pontos de cor do inventário estão lá | O R21 declara o risco, mas o **aceite** de 1.04 nem sequer olha para `shared/` (A-05). Risco declarado com mitigação que não fecha | Aceite de 1.04 |
| **N3** | **A suíte e2e existente (`spec/e2e/copilot`, 15 specs) não roda hoje** — falta `@playwright/test` | 0.1 é a primeira tarefa do plano e vai mexer no config dessa suíte. Se ela já estiver vermelha/inexecutável, ninguém percebe que 0.1 a quebrou | Bloco 0.1 |
| **N4** | **O merge da v4.16.2 vai trazer o rename `path_without_extentions` → `path_without_extensions`** | O fork tem +11/−0 em `rack_attack.rb`; se alguma dessas linhas usar a grafia antiga, o merge compila e **o throttle para de casar em silêncio** — o mesmo modo de falha que BK-04 existe para corrigir | Bloco 0.2 e 1.12 |
| **N5** | **`conversation.rb` tem +253/−14 de fork** (A-11) | O merge desse arquivo é trabalho real, não deslocamento. Não está na lista de armadilhas do 0.2 (que só fala dos 113 arquivos do widget) | Bloco 0.2 |
| **N6** | **Nenhum bloco declara quem opera a frota** nas tarefas de infra (0.4 nginx, 0.10 chaves) | As duas são "fora do repo" e bloqueiam ondas inteiras (0.10 bloqueia a Onda 5 por completo, e o próprio plano diz isso). Sem dono nomeado, tarefa de infra sem código é a que mais atrasa | §2.2, coluna nova de dono, ou §7 |

---

## 9. O que precisa mudar antes de começar

Sete itens. **Todos são escrita, nenhum é código. O conjunto é P** — cabe num dia de trabalho de uma
pessoa que já conhece os documentos.

**Bloqueantes (sem isto, a Onda 3 não fecha e três devs constroem coisas diferentes):**

1. **Criar `widget_appearance` como quarta chave de topo no bloco 3.01**, com schema em 3.02 e
   entrega em 3.04, absorvendo BE-2 e o defeito D1. *(A-01)*
2. **Propagar as arbitragens** — um bloco `> ARBITRADO (PLANO-MESTRE §5 A_x)` no topo de cada seção
   contradita dos quatro planos: `22:552`, `22:663`, `23:720`, `23:1305`, `23:1397`, `23:907`,
   `23:1398`, `24:1613`, `24:1580`, `25:231`. *(A-02)*
3. **Fixar a lista canônica de flags de `profileConfig`** num só lugar (o mestre, bloco 3.03), e
   apontar 22 §B.3 e 23 §B.1.4 para ela. *(§6 itens 1 e 2)*

**Antes da primeira linha de código da onda correspondente:**

4. **Fechar a janela de `widget_tracking`**: schema com lista negativa já em 3.01, ou tirar a chave
   de 3.01 e levá-la para 5.01. *(A-04)*
5. **Corrigir os aceites que estão errados ou frouxos**: o grep de 1.04 passa a incluir `shared/`;
   os contrastes viram 9,24 / 6,83 / 2,27 com tolerância declarada; `App.vue < 310`; `@font-face` de
   volta em 1.08. *(A-05, A-08, A-09, A-22)*
6. **Consertar o grafo**: `1.19 dep 1.18, 1.20`; quebrar `5.11` em a/b e realocar `5.12`; trocar
   `2.*` e `W2.*` por listas; `2.17 dep 0.2`. *(A-12, A-13, A-21, A-20)*
7. **Fechar os furos de rastreabilidade**: BK-33 vira bloco (ou entra em 5.11 nominalmente), BE-5
   entra na §8 com motivo ou vira tarefa, BK-36/BK-37 entram na coluna Origem de 4.13. *(A-07)*

**Recomendado, não bloqueante:**

8. Corrigir M1 (célula de `conversation.rb`), M3 (o construtor não mudou) e a consequência 2 de A7;
   recolocar `woot.scss` e `colorHelper.js` no bloco 1.04; reclassificar 0.1 para 🟡 com
   `package.json` na lista; acrescentar os seis riscos da §8. *(A-03, A-06, A-10, A-11, N1–N6)*

---

## 10. Fecho — a resposta à pergunta

**"Está à altura?"**

A apuração está. Refiz as medições mais caras do plano e elas batem — algumas com precisão de byte,
uma com precisão de cinco casas decimais. Das 46 referências `arquivo:linha` que conferi uma a uma,
**45 estão certas**. O inventário de 25 pontos de cor literal está correto ponto a ponto. O
diagnóstico dos seis defeitos é verdadeiro no código, hoje, e eu verifiquei cada um. Isso não é um
plano escrito para impressionar; é um plano escrito por quem abriu os arquivos.

A **consolidação** não está. Ela perdeu um pré-requisito de backend inteiro (BE-2), deixou uma
tarefa de conformidade sem dono (BK-33), apagou uma feature de produto sem decidir sobre ela (BE-5),
enfraqueceu um critério de aceite em relação ao plano de origem (o grep de `shared/`), abriu uma
janela de duas ondas num campo que ela mesma classifica como risco de segurança, e — o mais caro de
todos — arbitrou dez divergências sem escrever a arbitragem onde o dev vai ler.

Esse último ponto é o que separa "plano bom" de "plano executável". O mestre diz, na primeira
página, que os planos de frente continuam sendo a fonte de verdade do detalhe. São 7.205 linhas de
detalhe que hoje contradizem, com todas as letras, as decisões que o mestre tomou. Um dev competente
não trava nesse plano — **ele executa a coisa errada com confiança**, que é pior, porque não gera
pergunta.

O conserto é de um dia de escrita. Sem ele, o primeiro sprint entrega uma migration que a arbitragem
A1 eliminou, uma tela cujo aceite não fecha, e um valor de enum em português que o resto do plano lê
em inglês.

---

*Auditoria produzida em 12/08/2026 sobre `PLANO-MESTRE.md`, `22-plano-widget.md`,
`23-plano-config-dashboard.md`, `24-plano-backend-dados.md` e `25-plano-tracking-integracao.md`
(7.205 + 1.005 linhas), com verificação independente no HEAD `ee87f5e799` e contra as tags locais
`v4.12.1` e `v4.16.2`. **Nenhum arquivo do repositório e nenhum artefato auditado foi alterado.**
Onde não verifiquei, está escrito que não verifiquei.*
