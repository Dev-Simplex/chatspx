# Grupo A, itens #1 e #5 — o 5.23 que nunca pousou e a junção 4.05 ↔ 4.06

> Trilha `spx-grupo-a-1-5`, worktree `/home/chatwoot/chatwoot-spx-grupo-a-1-5`, a partir de
> `homologacao` em `6d56c722c8`. Nada foi pushado, nenhum banco de produção foi tocado, nenhum
> build foi disparado. O rspec usou `POSTGRES_DATABASE=chatwoot_test_grupoa15`, dedicado.

---

## 1. Item #1 — bloco 5.23 "Recebido do site": era integração, e era mesmo

A `ESTADO-BLOCOS-24ago.md` §7 chama este item de "o maior retorno por hora da lista", e o
briefing avisa que relatório de trilha fala do worktree dela, não da árvore. **Conferido arquivo
por arquivo antes de copiar qualquer coisa**, que é o que o aviso pedia:

| Verificação | Resultado |
|---|---|
| Caminhos tocados por `758f8d6111` | 13 |
| Ausentes da árvore | **6** — `SiteContext.vue`, `helper/originAttributes.js`, 3 specs e o verificador em Chromium |
| Presentes, mas com a mudança do bloco aplicada? | **Nenhum.** `grep -rn "SiteContext\|site_context" app/javascript/dashboard/` voltava **vazio** |

Ou seja: o `o4-instalacao.md` declara o bloco entregue e **nada dele estava na árvore** — nem os
arquivos novos, nem as chaves de i18n, nem a âncora em `useUISettings.js`, nem o import no
`ContactPanel.vue`. A auditoria estava certa e o relatório de trilha, não.

O `git cherry-pick -n 758f8d6111` aplicou com auto-merge nos 3 arquivos que divergiram desde
agosto (`useUISettings.js`, os dois `conversation.json`) e **sem conflito**. Conferi o resultado
do auto-merge à mão, porque auto-merge limpo não é auto-merge correto: a lista
`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` mudou de conteúdo desde o commit original
(`previous_conversation` ocupa hoje a posição de `contact_notes`), e o que importa é que
`site_context` tenha ficado **colado em `contact_attributes`** — ficou.

### O que foi medido

| Ferramenta | Escopo | Resultado |
|---|---|---|
| vitest | `SiteContext.spec.js`, `siteContextStoreShape.spec.js`, `originAttributes.spec.js`, `useUISettings.spec.js` | **4 arquivos, 47 testes, 0 falhas** |
| `site-context-contrast.check.mjs` | Chromium real, os dois temas | **8/8**; selo 15,57 no claro e 12,13 no escuro (mínimo AA: 4,5) |
| eslint | os 4 arquivos do bloco | **0 erros** (2 avisos, herdados do commit original) |

Os 47 batem exatamente com o que a mensagem do commit original declarava, o que é a conferência
de que nada se perdeu no transporte.

---

## 2. Item #5 — bloco 4.05: a junção estava rompida em DOIS pontos, não um

A auditoria descreve o defeito conhecido. Ao instrumentá-lo apareceu um segundo, mais grave, no
mesmo caminho — e ele explica por que o primeiro nunca foi notado em produção.

### 2.1 O defeito que a auditoria nomeou

`TeaserComposer.vue` edita `title`/`message` da campanha de chat ao vivo da inbox. O teaser do
host mostrava `canal.welcomeTagline || canal.welcomeTitle` (`sdk/teaser.js:180`) — **outro campo,
editado em outra tela**. O preview da própria Tela 2 já mostra `campanha.message`
(`TriggersPage.vue:143-145`), então o preview mentia. Com o gatilho novo ligado (4.22) a campanha
legada para de disparar, e o texto escrito no compositor deixa de aparecer em lugar nenhum.

### 2.2 O defeito que apareceu ao medir: **o teaser não era montado em site nenhum**

`IFrameHelper.montarTeaserSeConfigurado` lia `window.chatwootWebChannel` — e esse objeto é escrito
por `app/views/widgets/show.html.erb`, que é o documento do **iframe**. **A página do site do
cliente nunca o teve.** O canal chega ao host pela ponte, em `config.channelConfig`
(`widget/helpers/IframeEventHelper.js:49`), e `onLoad` — o único chamador — não o repassava.

Consequência: `abordagemNovaNoAr({})` era falso em todo site real, e o bloco 4.06 inteiro (teaser,
degradação 4.19, auto-open 4.20, telemetria 4.21) **não montava nada**.

**Por que ninguém viu.** Os dois mecanismos de verificação do 4.06 passam ao largo desta linha:

- `sdk/specs/approach.spec.js:53` faz `window.chatwootWebChannel = {...}` à mão antes de chamar
  `montarTeaserSeConfigurado` — a fixture cria o global que a produção não tem;
- `sdk/specs/browser/teaser.check.mjs` mede **CSS sobre HTML escrito dentro do próprio
  verificador** (`const pagina = nivel => ...`); ele nunca boota o SDK.

Nenhum dos dois é ruim no que se propõe. Os dois são cegos para "o objeto existe neste
documento?", e **nenhum spec antigo chegava a olhar o texto do balão** — `welcomeTagline` estava
nas fixtures dos dois arquivos e não era asserido em lugar nenhum. Foi por isso que os dois
defeitos couberam sob 10/10 em Chromium e 25 testes verdes.

### 2.3 O conserto, e por que a precedência foi para o servidor

`Channel::WebWidget#teaser_text` resolve **campanha vinculada → `welcome_tagline` →
`welcome_title`** e o resultado viaja pronto em `chatwootWebChannel.teaserText`. O host passou a
fazer **uma** leitura: `canal.teaserText || ''`.

Três razões, nesta ordem:

1. **É o padrão que este payload já segue.** O host consome decisão, não recalcula política — é o
   que 1.02/1.03 fizeram com a cor e o 3.19 com o ícone do lançador. Precedência escrita em dois
   lugares diverge no primeiro ajuste, e essa divergência é literalmente o defeito do 2.1.
2. **O `sdk.js` tem teto** (bloco 0.5, aceite A13) e a auditoria mediu **6 bytes** de folga no
   gzip. Trocar uma cadeia de três leituras por uma **devolve** bytes. Medido com esbuild sobre
   `teaser.js` + `IFrameHelper.js`, minificados: **−13 B crus, −10 B gzip**. O gate não é
   ameaçado por esta trilha; ele continua vermelho pelo que a §5.3 já nomeia (grafo, bloco 1.08).
3. `teaser_campaign` **não filtra por `enabled`**, e a ausência é decisão declarada no código:
   `enabled` governa o disparo do motor **legado**; quem liga e desliga o teaser é
   `widget_triggers.enabled` (4.22). Filtrar aqui faria o texto recém-salvo sumir por causa de um
   interruptor de outra tela, sem aviso nenhum.

O critério de "qual é a campanha vinculada" espelha o da tela: `ongoing`, da inbox, menor `id` —
o mesmo que `campaigns/getLiveChatCampaigns` produz. Se os dois divergirem, o cliente edita uma
campanha e o visitante recebe outra, que é o defeito que o bloco existe para não ter.

### 2.4 Os testes ACUSAM — e cada um foi visto vermelho antes de ficar verde

Nenhum destes é do tipo "afirma ausência". Todos põem **dois textos diferentes** no mesmo cenário
(a campanha e a tagline) e exigem o da campanha; um exemplo que mandasse só o texto novo passaria
no código velho por acidente do fallback.

| Camada | Arquivo | Vermelho comprovado |
|---|---|---|
| Modelo | `spec/models/channel/web_widget_teaser_spec.rb` | Sabotagem `teaser_text = welcome_tagline` (o comportamento antigo do host) → **4 de 10 falham**, incluindo "acompanha a edição da campanha" |
| Boot ponta a ponta | `spec/requests/widgets/teaser_payload_spec.rb` | Sabotagem do ERB emitindo `welcome_tagline` em `teaserText` → **3 de 4 falham** |
| Host | `app/javascript/sdk/specs/teaserCampanha.spec.js` | Rodado contra a árvore original: **3 de 5 falham**, e o do grupo 2 falha com `expected null not to be null` — o teaser não existia |

O exemplo central é o aceite ao pé da letra: salva `"Frete grátis hoje"`, lê; salva
`"Últimas unidades com 20% off"`, lê de novo; exige que o segundo seja diferente do primeiro. Com
a junção rompida os dois voltam `"Estamos online"` e a asserção final denuncia.

O request spec renderiza a **página de verdade** e ainda cobre o escape: mensagem de campanha com
aspas e `</script>` não pode quebrar o literal JavaScript — é entrada de usuário dentro de um
`<script>` com `.html_safe`.

Duas fixtures mortas foram corrigidas de passagem: `teaser.spec.js` e `approach.spec.js` traziam
`welcomeTagline` num objeto que o código não lê mais. Fixture que nomeia campo ignorado é
armadilha para quem ler depois.

---

## 3. O que ficou de fora, e por quê

| O quê | Por quê |
|---|---|
| **O preview ainda diverge da produção quando não há campanha** | `TriggersPage.vue:143-145` faz `if (!texto) return null` — sem campanha, o preview não mostra teaser; a produção mostra a tagline. Alinhar é uma linha, mas `TriggersPage.vue` é arquivo do bloco 4.04 e a trilha não é dona dele. **Nomeado, não consertado.** |
| **`teaserEnabled` e `teaserDismissLabel` continuam ausentes do payload** | `montarTeaser` lê os dois (`teaserEnabled === false`, `teaserDismissLabel \|\| 'Dispensar'`) e **nenhum é emitido pelo ERB**. O 8º aceite do 4.06 ("com `teaserEnabled: false` o código não é montado") não tem como ser exercido em produção, e o rótulo de dispensa está cravado em português para toda a frota. Mesma classe do defeito 2.2, achado no mesmo caminho — mas é do 4.06, não do 4.05. |
| **Rebuild do `sdk.js` e nova medição do gate 0.5** | Exige build, que escreve em `public/`, disputado com a trilha do peso (2.18). O delta foi medido na fonte minificada, e é negativo. |
| **`WTeaserCard.vue` (`widget/ui/`)** | É da trilha dos primitivos (2.01/2.02/2.07), fora da propriedade desta. |

---

## 4. Tudo o que rodou nesta trilha

| Comando | Resultado |
|---|---|
| `npx vitest run` — os 4 specs do 5.23 | **47 testes, 0 falhas** |
| `node .../site-context-contrast.check.mjs` | **8/8** em Chromium real, dois temas |
| `npx vitest run app/javascript/sdk/` + os specs do 5.23 | **29 arquivos, 353 testes, 0 falhas** |
| `npx vitest run` — gatilhos + preview + store de campanha do widget | **36 arquivos, 256 testes, 0 falhas** |
| `bundle exec rspec` — modelos de canal + views do widget + `campaign_spec` + controller do widget + o request spec novo, **numa corrida só, com a árvore parada** | **145 exemplos, 0 falhas** |
| `bundle exec rubocop` — os 3 arquivos Ruby | **0 offenses** |
| `npx eslint` — os arquivos JS tocados | **0 erros** |

### 4.1 A nota do `autoBuild`, porque ela vai morder o próximo

O `config/vite.json` tem `autoBuild: true` no ambiente `test`. Em worktree nova, o primeiro spec
que renderiza `widgets/show.html.erb` dispara um **`vite build --mode test` inteiro dentro da
suíte** — e ele volta a disparar a cada edição de arquivo em `app/javascript/`. Aqui isso custou
**10min50s** numa corrida de 9 exemplos; a mesma corrida com o manifest quente e a árvore parada
levou **39 s**.

Durante o build o processo `ruby` fica em `futex_wait_queue`, com **CPU zero e I/O zero** — a
assinatura exata de um deadlock. Não é: o `node` filho está trabalhando. Confirmado aqui olhando
`ps --ppid <pid>`, que mostrava `pnpm exec vite build --mode test` vivo.
