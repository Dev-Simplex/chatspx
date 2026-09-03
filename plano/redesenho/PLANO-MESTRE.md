# Plano mestre — redesenho do chat de site do ChatSPX

> **O que é este documento.** A ordem única de execução do redesenho, costurando as quatro frentes
> que foram planejadas em paralelo (widget, telas de configuração, backend/dados,
> tracking/integração). É o documento que o time abre para saber **o que fazer primeiro, o que
> depende de quê, e quando cada onda está pronta**.
>
> **O que este documento não é.** Não repete os planos das frentes — eles continuam sendo a fonte de
> verdade do detalhe de cada tarefa. Aqui está a ordem, as dependências cruzadas, as divergências
> arbitradas e os critérios de encerramento.
>
> **Fase:** planejamento. **Nenhum arquivo de código do repositório foi alterado por esta task.**
> Nada foi commitado, buildado, deployado, migrado ou reiniciado. Os únicos artefatos escritos são
> este markdown e `mockups/index.html`.
>
> **Data:** 12/08/2026 · **Branch:** `homologacao`, HEAD `ee87f5e799` · **Base:** fork ChatSPX sobre
> Chatwoot v4.12.1, com a v4.16.2 disponível como tag local.
>
> **Revisado em 12/08/2026, depois da auditoria adversarial** (`auditoria/31` a `auditoria/35`). Os
> bloqueadores **B2**, **B3** e **B4** e os graves **G-A**, **G-C** e **G-D** foram corrigidos neste
> arquivo; cada correção foi reconferida no código antes de ser escrita. O que mudou, item a item,
> está na seção **"Correções aplicadas em 12/08/2026 (pós-auditoria)"**.
>
> **Revisado de novo em 13/08/2026: as quinze decisões do dono do produto entraram.** O que estava
> `[AGUARDA WALISSON]` foi decidido, e a decisão está aplicada — não anotada. **As ondas foram
> reordenadas** (captura e atribuição antes do acabamento visual), **o backfill de histórico foi
> cortado**, **a frente de IA voltou**, e o documento ganhou duas seções que não existiam:
> **§10 Qualidade** e **§11 Modelo de execução**. A rastreabilidade decisão → onde foi aplicada está
> na **§0.4**; o registro do que mudou está na seção final **"Decisões do produto aplicadas em
> 13/08/2026"**. **A marca `[AGUARDA WALISSON]` não existe mais neste documento** para nenhum item
> coberto pelas quinze decisões.

---

## 0. Como ler

### 0.1 Marcação de procedência

| Marca | Significa |
|---|---|
| **[FATO]** | Trecho de código deste repositório, com `arquivo:linha` conferível no HEAD `ee87f5e799` |
| **[MEDIDO]** | Número obtido por comando executado **nesta task**, com o comando reproduzido na §0.3 |
| **[INFERÊNCIA]** | Conclusão derivada de dois ou mais fatos. É dedução declarada, não observação |
| **[NÃO VERIFICADO]** | Ninguém verificou. Fica como lacuna, nunca preenchido com chute |
| **[ARBITRAGEM]** | Dois planos de entrada especificaram a mesma coisa de forma diferente e este documento decide, com a razão e a medição ao lado (§5) |

**Esforço** é sempre relativo — **P**, **M**, **G**. Nunca em horas.

> **Cuidado com os prefixos: os identificadores deste plano e os do estudo colidem.** `M*` aqui são
> as **medições** da §0.3; no estudo são os **gaps de MESA**. `D*` aqui são as **dívidas** do plano
> 23; no estudo são os **diferenciais**. `V*` aqui são as **verificações pendentes** da §7; no estudo
> são as **vantagens**. E `I5` aqui é a frente de **webhooks** do plano 25; no `DECISOES.md` é
> *"contexto ao lado da conversa"* — decisão diferente, que sumiu por causa exatamente disso (§8.1
> item 33). Quando este documento cita um identificador do estudo, ele escreve de onde ele vem.

**Risco de merge:** ⚪ arquivo novo (risco zero por construção) · 🟢 upstream não mexeu desde a
v4.12.1 · 🟡 upstream mexe às vezes · 🔴 campo minado dos dois lados.

### 0.2 Entradas — o que existe e o que falta

| Entrada | Estado | Tamanho |
|---|---|---|
| `plano/redesenho/22-plano-widget.md` | completo | 1.803 linhas |
| `plano/redesenho/23-plano-config-dashboard.md` | completo | 1.616 linhas |
| `plano/redesenho/24-plano-backend-dados.md` | completo | 1.928 linhas |
| `plano/redesenho/25-plano-tracking-integracao.md` | completo | 1.858 linhas |
| `plano/redesenho/shared/` (LEIA-ME, tokens.css, primitivos.css, on-brand.js) | completo | 453 linhas + 3 arquivos |
| `plano/redesenho/mockups/*.html` | **8 páginas**, todas presentes | 1,7 MB |
| `plano/redesenho/mockups/shots/` | **58 capturas** | 30 MB |
| `plano/estudo-chat-web/` (22 relatórios, `DECISOES.md`, `10-gap-analysis.md`) | completo | 36.189 linhas |

**Nada faltou.** Uma única lacuna de material, registrada porque aparece na página de índice: **não
há captura do mockup `00-sistema-visual.html` em `shots/`** — as 58 capturas cobrem os outros sete.
Para não publicar um cartão cego, a miniatura dessa página foi gerada nesta task em diretório
temporário (Playwright, Chromium 145) e embutida no `index.html`; **nenhum arquivo novo foi escrito
em `shots/`**, que pertence a outra task.

### 0.3 Medições próprias desta task

Um plano mestre que só costura o que os outros mediram herda os erros deles. Refiz as medições que
sustentam as arbitragens da §5. Todas são `git` e leitura de código, no HEAD `ee87f5e799`, contra as
tags locais `v4.12.1` e `v4.16.2`.

**M1 — Churn dos arquivos que o plano inteiro toca** [MEDIDO — `git diff --numstat v4.12.1 v4.16.2 -- <arquivo>` e `… v4.12.1 HEAD -- <arquivo>`]:

| Arquivo | Upstream (4.12.1→4.16.2) | Fork (4.12.1→HEAD) | Leitura |
|---|---:|---:|---|
| `app/models/channel/web_widget.rb` | **0 / 0** | **0 / 0** | 🟢 o arquivo mais seguro do backend |
| `app/views/widgets/show.html.erb` | **0 / 0** | **0 / 0** | 🟢 |
| `app/views/api/v1/widget/configs/create.json.jbuilder` | **0 / 0** | **0 / 0** | 🟢 |
| `app/controllers/api/v1/widget/events_controller.rb` | **0 / 0** | **0 / 0** | 🟢 |
| `app/javascript/sdk/IFrameHelper.js` | **0 / 0** | +4 / −1 | 🟢 (confirma a DIVERGÊNCIA 1 do plano 22) |
| `app/javascript/entrypoints/sdk.js` | **0 / 0** | **0 / 0** | 🟢 |
| `app/javascript/widget/constants/sdkEvents.js` | **0 / 0** | **0 / 0** | 🟢 |
| `app/javascript/widget/App.vue` | +4 / −0 | 0 / 0 | 🟡 |
| `app/controllers/api/v1/widget/base_controller.rb` | +4 / −0 | 0 / 0 | 🟡 |
| `app/controllers/api/v1/widget/conversations_controller.rb` | +2 / −2 | 0 / 0 | 🟡 |
| `app/controllers/api/v1/widget/contacts_controller.rb` | +16 / −1 | 0 / 0 | 🟡 |
| `app/controllers/api/v1/widget/messages_controller.rb` | +22 / −3 | 0 / 0 | 🟡 |
| `app/models/inbox.rb` | +38 / −2 | +13 / −0 | 🟡 |
| `app/views/api/v1/models/_inbox.json.jbuilder` | +28 / −5 | +7 / −0 | 🟡 |
| `app/models/custom_attribute_definition.rb` | **+32 / −6** | +9 / −2 | 🟡 (o plano 24 marcou como [NÃO VERIFICADO]) |
| `lib/webhooks/trigger.rb` | **+30 / −10** | +1 / −1 | 🟡 → ver **M3** |
| `app/models/conversation.rb` | **+79 / −8**, 4 commits | — | 🔴 → ver **M2** |
| `config/initializers/rack_attack.rb` | **+89 / −22** | +11 / −0 | 🔴 → ver **M4** |
| `app/controllers/api/v1/accounts/inboxes_controller.rb` | **+53 / −9** | **+87 / −6** | 🔴 |
| `lib/url_helper.rb` | **0 / 0** | 0 / 0 | 🟢 |
| `app/listeners/webhook_listener.rb` | +5 / −3 | +37 / −1 | 🟡 |
| `app/models/webhook.rb` | +2 / −2 | 0 / 0 | 🟢 |
| `app/jobs/webhook_job.rb` | **0 / 0** | +2 / −0 | 🟢 |
| `config/environments/production.rb` | 0 / 0 | +11 / −3 | 🟢 |

**M2 — `validate_referer_url` não foi tocado pelo upstream, embora o arquivo tenha sido.**
`app/models/conversation.rb` teve +79 −8 em 4 commits, mas o método é **byte-idêntico** entre as duas
tags: só desceu de `:334` (v4.12.1) para `:405` (v4.16.2) [MEDIDO — `git show v4.12.1:app/models/conversation.rb | grep -A6 "def validate_referer_url"` comparado com a mesma leitura na v4.16.2].
Isso reclassifica o risco de **BK-12** (§5, arbitragem **A6**).

**M3 — O upstream reescreveu `Webhooks::Trigger`, e o defeito B3 continua de pé lá.**
Na v4.16.2 [MEDIDO — `git show v4.16.2:lib/webhooks/trigger.rb`]: o construtor virou
`initialize(url, payload, webhook_type, secret:, delivery_id:)`, o transporte trocou de `RestClient`
para `SafeFetch`, e apareceu uma classe `RetryableError`. O `execute` ficou assim:

```ruby
def execute
  perform_request
rescue StandardError => e
  raise RetryableError.new(status: http_status(e), message: e.message) if retryable_agent_bot_error?(e)
  handle_failure(e)   # continua NÃO relançando para account_webhook / api_inbox_webhook
end
```

Ou seja: **o B3 é defeito do upstream, e a v4.16.2 não o corrige** — mas muda a classe inteira sob a
qual a correção seria escrita. Consequência na §5, arbitragem **A7**.

**M4 — O throttle que nunca casa também é do upstream, e continua errado na v4.16.2.**
[MEDIDO] `git show v4.16.2:config/initializers/rack_attack.rb` linha 184-185 ainda compara
`req.path_without_extensions == '/api/v1/widget/contacts'` (plural), enquanto a rota é
`/api/v1/widget/contact` (singular, `config/routes.rb:609`, `resource :contact`). Arbitragem **A8**.

**M5 — O ERB do widget já tem a inbox na mão.**
[FATO] `app/views/widgets/show.html.erb:9-30` usa `@web_widget.inbox` em **onze** chaves
(`avatar_url`, `agent_bot&.name`, `name`, `portal`, `working_hours_enabled`, `csat_survey_enabled`,
`working_hours`, `out_of_office_message`, `timezone`, `allow_messages_after_resolved`,
`account.feature_enabled?`). Ler `@web_widget.inbox.additional_attributes` ali não custa nada de
estrutura. Sustenta a arbitragem **A1**.

**M6 — `additional_attributes` da inbox é servido inteiro a qualquer agente.**
[FATO] `app/views/api/v1/models/_inbox.json.jbuilder:27` — `json.additional_attributes resource.additional_attributes`,
sem condicional; e `app/policies/inbox_policy.rb:22-27` libera `show?` para
`Current.user.assigned_inboxes.exists?(id: record.id)` — qualquer agente com a inbox atribuída,
não só administrador. Confirma a regra dura do plano 24 §5: **nenhum segredo em
`additional_attributes`**.

**M7 — Precedente de nomenclatura.** [FATO] `app/models/inbox.rb:50` —
`store_accessor :additional_attributes, :pin_mode, :pinned_conversation_ids`; o valor usado é
`'per_agent'` (`ConfigurationPage.vue:94`), inglês em `snake_case`. E `web_widget.rb:58` —
`enum reply_time: { in_a_few_minutes: 0, … }`, também inglês. Sustenta a arbitragem **A2**.

**M8 — `companies` já existe dos dois lados, e o upstream traz a UI no merge.**
[FATO] `db/schema.rb:781` — `create_table "companies"`; `db/schema.rb:847` — índice
`index_contacts_on_company_id`. [MEDIDO] O upstream v4.16.2 traz `fe44b07147 feat(companies): add
company detail page (#14054)` e `16b8693e1b fix: standardize contact company field on company_name
(#14099)`. Isso barateia **T-I3.2** (objeto `company` no `setUser`), que o plano 25 estimou em **M**
com risco Médio: a modelagem e a tela chegam de graça no merge; sobra o caminho widget → contato.

**M9 — Migrations: sem colisão hoje.** [MEDIDO] `ls db/migrate | cut -d_ -f1 | sort | uniq -d` →
vazio; a última é `20260722120000_add_agent_conversation_isolation_to_inboxes.rb`.

**M10 — `conversation_resolved` continua fora do catálogo de webhook, nos dois lados.**
[MEDIDO] `ALLOWED_WEBHOOK_EVENTS` (`app/models/webhook.rb:32`) não o inclui, nem no HEAD nem na
v4.16.2. **BK-05** continua sendo trabalho nosso — e continua sendo **P**.

**M11 — O `WidgetBuilder.vue` órfão segue no disco.** [MEDIDO] 13.198 bytes; `grep -rn WidgetBuilder app/javascript`
não devolve nenhuma referência além do próprio arquivo. Confirma **D5** do plano 23.

#### Medições da revisão pós-auditoria (12/08/2026)

Seis medições novas, todas refeitas por mim no HEAD `ee87f5e799` antes de corrigir os aceites. Elas
sustentam as correções listadas na última seção deste documento.

**M12 — A origem do lead não está no banco. Ela é anulada na escrita.**
[MEDIDO — `psql -d chatwoot_production` em homologação, leitura apenas]:
`select count(*) filter (where additional_attributes->>'referer' is not null and additional_attributes->>'referer' <> ''), count(*) from conversations;` → **0 de 3.180**. Zero.
E [FATO] `app/models/conversation.rb:536-539`:

```ruby
def validate_referer_url
  return unless additional_attributes['referer']

  self['additional_attributes']['referer'] = nil unless url_valid?(additional_attributes['referer'])
end
```

O valor entra por `base_controller.rb:38-43` (`referer: permitted_params[:message][:referer_url]`) e
**é apagado na validação** quando a URL não passa. Consequência que muda o plano: *"o SDK nunca
mandou"* e *"a validação destruiu"* produzem exatamente o mesmo `referer: null`, e **o banco não
distingue os dois casos**. Reescreve a §3 item 4, a trilha 1.18→1.22 e a verificação **V3**.
*(A auditoria 35 mediu 0 de 3.179 na mesma base ontem; o numerador — zero — é o que importa, e as
três medições independentes batem nele.)*

**M13 — O harness da 0.1 não roda hoje.** [MEDIDO] `playwright.config.js` **já existe** (1.931 B,
`testDir: 'spec/e2e'`), e serve `spec/e2e/copilot/` e `spec/e2e/resolve-gate/`. `grep -c "@playwright/test" package.json` → **0**;
`ls node_modules/@playwright` → não existe. O que existe é `package.json:160` → `"playwright": "^1.59.1"`,
que é o driver de navegador, **não** o test runner que a primeira linha do config exige
(`require('@playwright/test')`). O próprio cabeçalho do arquivo diz *"SETUP REQUIRED… Add `@playwright/test` to devDependencies"*.
Reclassifica o bloco **0.1**.

**M14 — Onde a cor literal realmente mora.** [MEDIDO]
`grep -rn "n-brand" <dir> | wc -l` e idem para `getContrastingTextColor`:

| Diretório | `n-brand` | `getContrastingTextColor` | `--widget-color` |
|---|---:|---:|---:|
| `app/javascript/widget/` | **18** | **12** | 1 (`App.vue:121`) |
| `app/javascript/sdk/` | **0** | **0** | 0 |
| `app/javascript/shared/` | **7** | **6** | 0 |

O aceite do bloco 1.04 grepava `widget/` e `sdk/` — e `sdk/` é justamente o diretório onde **não há
nada a achar**. Corrigido para `widget/`, `sdk/` **e** `shared/`.

**M15 — O `sdk.js` e os dois orçamentos.** [MEDIDO] `public/packs/js/sdk.js` = **28.834 B crus**;
`gzip -9` = **9.508 B** (9,29 KB). O `size-limit` do repositório (`package.json:23-32`) declara
**40 KB** para esse caminho, medido em bytes **crus** por `@size-limit/file`; o apêndice §E.4 do
plano 22 declara **15 KB gzip**. Dois orçamentos, duas unidades, o mesmo arquivo — arbitrado agora
em **A13**.

**M16 — Os sete `@font-face` continuam no CSS entregue.** [MEDIDO]
`grep -o "@font-face" public/vite/assets/widget-EcEcykJV.css | wc -l` → **7**, no artefato do
manifest (1.103.132 B, o mesmo número da §1). São 18 `.woff2` publicados que nada baixa. Devolve a
asserção de `@font-face` ao aceite do bloco **1.08**.

**M17 — O zoom está desabilitado no documento do widget.** [FATO]
`app/views/widgets/show.html.erb:6` →
`<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0" />`.
Nenhum bloco tocava essa linha (o 1.06 mexe na `:2`, o `lang`), o que tornava o critério de zoom
200% da Onda 2 impossível de satisfazer. Corrigido no bloco **2.09**.

#### Medições da revisão de produto (13/08/2026)

Cinco fatos novos, todos conferidos por mim no HEAD `ee87f5e799`, porque cinco decisões desta revisão
afirmam coisas sobre o código que ninguém tinha verificado.

**M18 — O gate determinístico da IA já existe, e roda no lugar errado para o que precisamos.**
[FATO] `enterprise/lib/captain/episode_gate_service.rb:5` define `Captain::EpisodeGateService`, com
três famílias de asserts de custo zero — `contradicted_tool_findings`, `tool_error_findings` e
`literal_repetition_findings` (`:15-17`). Ele é chamado de
`enterprise/app/jobs/captain/episode_eval_job.rb:33`, ou seja **depois** do episódio, para alimentar
o eval. Nada o chama **antes de a resposta sair**. É exatamente a classe que o guardrail de pré-envio
reusa (bloco **6.01**), e é o motivo de o guardrail ser **M** e não **G**.

**M19 — A fonte do trecho recuperado já chega ao modelo; o que não existe é a citação estruturada.**
[FATO] `enterprise/app/services/captain/tools/search_knowledge_tool.rb:28-31` — `format_chunk` devolve
`"#{text}\n(fonte: #{source})"`. A fonte viaja **dentro do texto do prompt**, como prosa. Não há
metadado de mensagem, nada persistido e nada renderizável no widget. Sustenta o bloco **6.03**.

**M20 — `flows` já tem coluna `version`.** [FATO] `db/schema.rb:1206` —
`t.integer "version", default: 1, null: false` na tabela `flows`. O teste A/B de fluxo (**6.05**) não
precisa de migration para versionar a variante; precisa de designação, de retenção da variante por
visitante e de leitura no relatório. Isso reclassifica o A/B de **G** para **M**.

**M21 — O caminho do auto-open já está construído; falta só quem o chame.** [FATO]
`app/javascript/entrypoints/sdk.js:83-85` expõe `toggle(state)`, que chama
`IFrameHelper.events.toggleBubble(state)` (`app/javascript/sdk/IFrameHelper.js:228`). Abrir o painel
por gatilho é **uma chamada**, não uma construção. É por isso que o bloco **4.20** é **P** — o custo
dele é de política e de tela, não de código.

**M22 — As campanhas legadas já disparam sozinhas, e cacheiam por uma hora.** [FATO]
`app/javascript/widget/store/modules/campaign.js:48-52` — `CACHE_EXPIRY = 60 * 60 * 1000` e leitura
de cache por `websiteToken`; `:67` regrava o cache. Uma conta com campanha ativa **já tem** um
caminho de mensagem proativa rodando hoje; quando `widget_triggers` entrar, passam a ser dois. É o
fato que obriga a regra de precedência do bloco **4.22**.

### 0.4 As quinze decisões do produto (13/08/2026) — e onde cada uma foi aplicada

O dono do produto decidiu os quinze pontos que estavam abertos. **Estão aplicadas neste documento,
não anotadas nele.** Esta tabela é a rastreabilidade: se alguém quiser conferir uma decisão, esta é a
coluna que diz onde olhar. **Nenhuma destas quinze se reabre.**

| # | Decisão | Onde foi aplicada |
|---|---|---|
| **D1** | Abordagem em **três níveis** (Discreto · Chamativo · Agressivo) com **degradação por familiaridade**; auto-open desligado por padrão, disponível a todas as contas, mobile off, aviso **sem** citar penalização do Google; os três níveis instrumentados | Blocos **3.20** (schema), **4.19** (degradação), **4.20** (auto-open), **4.21** (instrumentação); §2.2 Onda 3; §4 Onda 3 itens 2–3; **§8 item 3 reescrito** (deixou de ser recusa); arbitragem **A15** |
| **D2** | A **frente de IA inteira** entra: guardrail de pré-envio, eval como produto, citação de fonte | Blocos **6.01**, **6.02**, **6.03** (Onda 6); saiu da §8.1 (linha 26); medições **M18** e **M19** |
| **D3** | **Lead incompleto (BE-5)** entra | Bloco **4.18** deixou de ser condicional; §4 Onda 3 item 11 virou critério firme; saiu da §8.1 (linha 31) |
| **D4** | **Facade** e **teste A/B de fluxo** voltam ao plano | Blocos **6.04** e **6.05** (Onda 6); saíram da §8.1 (linhas 27 e 28); medição **M20** |
| **D5** | Ícone do lançador: inbox nova nasce com **balão na cor da marca**; a tela sugere foto de alguém do time; **nunca** foto genérica | Bloco **3.19** reescrito (o padrão por perfil caiu); §4 Onda 2 item 5c |
| **D6** | **Sem backfill de histórico.** O parser é só prospectivo | **1.21 cortada**; **V3 deixou de ser portão** (§7); **B4 resolvido por decisão**; **1.20 subiu** e ganhou aceite próprio; §3 item 4 e arbitragem **A14** reescritas; **A16** nova |
| **D7** | **Marco comercial antecipado**: captura e atribuição antes do acabamento visual | **§2.6 nova** (curva de valor + **MC1 a 38,7%**, contra 76,8%); §2.1, §2.2 e §4 reordenadas; 3.15, 4.09 e 4.10 migraram para a Onda 5 |
| **D8** | Instalação em **WordPress / Wix / GTM** entra | Bloco **5.22**; saiu da §8.1 (linha 29) |
| **D9** | **Contexto do sistema externo** (decisão I5) entra na versão simples: painel lateral | Bloco **5.23**; saiu da §8.1 (linha 33); app embutido continua fora, com o motivo |
| **D10** | **Campanhas legadas coexistem** com o teaser novo, com regra de precedência escrita | Bloco **4.22**; saiu da §8.1 (linha 34); medição **M22** |
| **D11** | Autonomia: os agentes editam, testam e **commitam local**. Nunca push, PR ou deploy | **§11.3** |
| **D12** | Isolamento: **um worktree git por frente**, branch própria, integração no fim | **§11.2** |
| **D13** | Falha: tenta corrigir **2×**, depois **para, reverte e escala** | **§11.5** |
| **D14** | **Quality-kit adaptado ao fork**: adotar fixture anti-erro, regressão visual, axe, MUST/MUST NOT e DoD com os comandos reais; **não** adotar TypeScript strict, Biome, Zod e Stryker | **§10 nova**; bloco **0.11** (fixture anti-erro) virou pré-requisito da Onda 0 |
| **D15** | O plano precisa de uma **seção de modelo de execução** | **§11 nova** |

### 0.5 A escala de esforço, declarada — porque esta revisão recalcula percentuais

Esforço continua sendo **P / M / G**, nunca horas. Mas D7 pede um **percentual do esforço somado**, e
não se soma letra. A escala usada para somar, declarada aqui de uma vez:

| Letra | Peso | Híbridos |
|---|---:|---|
| **P** | 1 | **P/M** = 2 |
| **M** | 3 | **M–G** = 5 |
| **G** | 8 | |

**Esta escala não foi inventada nesta revisão — ela foi deduzida e conferida contra a auditoria.**
Aplicando-a ao conjunto de blocos **anterior** a esta revisão e à ordem **anterior** das ondas, o
acumulado até o fim da Onda 3 dá **55,9%** e até o fim da Onda 4 dá **76,9%** [MEDIDO — soma
reproduzida nesta task]. A auditoria 34/35 publicou **56,0%** e **76,8%** para esses mesmos dois
pontos. O erro é de **0,1 pp**, o que valida a escala e permite comparar o antes e o depois no mesmo
eixo. Onde este documento escrever um percentual de esforço, é esta a conta — e ela está aberta na
**§2.6**.

---

## 1. Resumo executivo

**Para quem não leu nada.**

O ChatSPX tem um widget de chat de site que funciona e é mais leve que o do principal concorrente
brasileiro — que, aliás, roda a mesma base que a nossa, sete versões atrás. O que falta não é
plataforma: são **duas camadas**. Uma de **captura** (o widget aborda, qualifica e entrega o lead) e
uma de **atribuição** (de qual campanha veio esse lead, e o que aconteceu com ele depois).

Este plano constrói as duas, e conserta seis defeitos verificados no caminho. Ele cobre **duas
superfícies**: o **widget** (o iframe que o visitante do site do cliente vê) e as **telas de
configuração** no dashboard (onde o cliente configura aparência, gatilhos, pré-chat e rastreio).

**O problema em cinco números medidos:**

1. A cor da inbox **não chega** ao header, ao botão de enviar, aos links nem ao foco — o widget de
   todo cliente tem a cor dele na bolha e a nossa (`#2dc46f`) no cabeçalho [defeito **B1**].
2. Esse cabeçalho verde com texto branco dá **2,27:1** de contraste [MEDIDO — `2,2734:1` pela fórmula
   WCAG 2.x], contra o mínimo AA de 4,5:1 — e reprova até o mínimo de componente, 3:1 [defeito **B2**].
3. O widget baixa **2,58 MB crus** na primeira visita, dos quais **1,10 MB é CSS** — e **63,5% desse
   CSS são regras de ícone que o widget nunca renderiza**, porque ele recebe o CSS do dashboard
   inteiro por configuração de build.
4. **Zero** ocorrências de `fbq`, `gtag` ou `dataLayer` em `app/`. E a origem do lead **não está no
   banco**: o campo existe (`conversations.additional_attributes.referer`), ninguém parseia, e
   `conversation.rb:536-539` **anula o valor na escrita** quando a URL não valida — hoje são
   **0 conversas com `referer` preenchido em 3.180** [M12]. O que este plano constrói é a captura
   prospectiva da origem, **e só ela**: por decisão do produto (**D6**), **não há backfill de
   histórico**. A frase que vai a cliente é *"a partir da entrada em produção, toda conversa nasce
   sabendo de onde veio"* — e a tarefa que garante isso é **1.20**, parar de destruir o dado na
   escrita, que passou a ser a primeira da trilha.
5. Um atributo que o site do cliente envia sem definição prévia **é gravado, entra no prompt da IA e
   some do painel** — o agente não vê o que a IA vê [defeito **B6**, pré-requisito comercial].

**O que vamos construir**, em uma frase por onda — **nesta ordem, que mudou em 13/08/2026 pela
decisão D7** (captura e atribuição antes do acabamento visual):

| # | Onda | Entrega | Esforço | Acum. |
|---|---|---|---:|---:|
| **0** | Terreno | O merge da v4.16.2 sozinho, o harness de teste que hoje não existe (com o fixture anti-erro), e a régua de peso que hoje dá falso verde | 6,4% | 6,4% |
| **1** | Nada mentindo | Os seis defeitos, as duas refatorações que blindam o merge, e a origem do lead capturada de agora em diante | 13,3% | 19,7% |
| **2** | Configuração | O perfil por inbox e as telas onde o cliente configura aparência, tema, abordagem, pré-chat e fluxo | 14,9% | 34,7% |
| **3** | Captura | O widget que trabalha: os três níveis de abordagem, teaser, fluxo conversacional, lead incompleto, WhatsApp como destino | 20,3% | 54,9% |
| **4** | Atribuição | Pixel, GA4, Ads, CAPI server-side, deduplicação, consentimento, diagnóstico, instalação e ciclo fechado | 20,8% | 75,7% |
| **5** | A conversa | O acabamento que o visitante lê: balões, lista, scroll, composer, header, movimento, mobile, dark, peso | 17,6% | 93,3% |
| **6** | IA e otimização | Guardrail de pré-envio, eval como produto, citação de fonte, facade e teste A/B de fluxo | 6,7% | 100% |

**O marco comercial — o momento em que o cliente vê valor que ele compra — chega a 38,7% do esforço,
e não a 76,8%.** É o que a **§2.6** demonstra bloco a bloco, e é o efeito prático da D7.

**Cinco decisões do Walisson governam tudo e não se reabrem:** o widget tem **dois perfis por inbox**
(marketing e suporte); **a geometria fica** (launcher 64, painel 400×640, raio 16, offsets 20/20,
mobile fullscreen, iframe); a abordagem tem **três níveis com degradação por familiaridade** (D1);
**não há backfill de histórico** (D6); e **captura e atribuição vêm antes do acabamento visual**
(D7). O que muda no visual é cor, movimento, acabamento e acessibilidade. Onde o mercado inteiro faz
errado e está medido (6 de 7 ignoram `prefers-reduced-motion`, 6 de 7 não fecham com `Esc`, 1 de 4
suporta dark), **não copiamos**.

---

## 2. O plano unificado em ondas

### 2.1 As sete ondas em uma tela

> **Esta ordem mudou em 13/08/2026 (decisão D7).** Antes: `0 → 1 → 2 (a conversa) → 3 (config) →
> 4 (captura) → 5 (prova de valor)`. Agora o acabamento visual da conversa é a **penúltima** onda, e
> IA/otimização é a última. **Nenhum bloco foi renumerado** — os identificadores `1.xx`, `2.xx`,
> `3.xx`… continuam sendo os mesmos, porque a auditoria e os quatro planos de frente os citam. O que
> mudou foi **quando cada onda executa**, e três blocos que trocaram de onda (3.15, 4.09 e 4.10, que
> dependem de 2.01/2.06).

```
ONDA 0 ── TERRENO ────────────────────────────────────────────── bloqueia tudo
  merge v4.16.2 sozinho · build reconciliado · harness + fixture anti-erro (D14)
  16 snapshots · compressão no nginx · gate de peso real · paridade · limpezas
        │
        ▼
ONDA 1 ── NADA MENTINDO ──────────────────── 4 trilhas em paralelo
  widget: tokens no servidor → cor certa (B1/B2) · a11y mínima · typing CSS · peso
  bridge: mapa de eventos + origem do postMessage (B4) + registry de content_type
  backend: retry de webhook (B3) · 4 portas de HMAC (B5) · atributo órfão (B6)
  origem: SANEAR (1.20) → seed → parser → relatório · SEM BACKFILL (D6)
  contrato do SDK com retorno e fila · propagação do SDK/ETag (5.07, realocado)
        │
        ▼
ONDA 2 ── CONFIGURAÇÃO ─────────────────────────────────────────────────────
  schema da config (perfil, aparência, gatilhos, ABORDAGEM em 3 níveis, tracking)
  telas 0 e 1 · preview corrigido · pré-chat (tela 3) · flags planas · i18n
        │
        ▼
ONDA 3 ── CAPTURA ──────────────────────────────────────────────────────────
  tela de abordagem + os 3 níveis · teaser · DEGRADAÇÃO por familiaridade
  auto-open opt-in · instrumentação dos níveis · campanhas legadas (precedência)
  fluxo conversacional · LEAD INCOMPLETO · Flows no canal web · WhatsApp
        │                                    ‖ trilha paralela: webhooks (I5)
        ▼
ONDA 4 ── ATRIBUIÇÃO ───────────────────────────────────────────────────────
  C1 config + tela 4 · C2 coletor · C7 consentimento · C4 tags · C5 server-side
  C6 dedup · C8 diagnóstico e contrato público · C9 offline e ctwa_clid
  I3/I4/I6 · JWT · enforcement · instalação WP/Wix/GTM · contexto ao lado (I5)
        │
        ▼   ◄── MARCO COMERCIAL (MC1) já passou, a 38,7% do esforço — ver §2.6
ONDA 5 ── A CONVERSA (acabamento visual) ───────────────────────────────────
  primitivos · balões · lista · scroll · composer · header · estados · movimento
  mobile · dark · Esc · forced-colors · peso 2ª rodada · pré-chat no widget
        │
        ▼
ONDA 6 ── IA E OTIMIZAÇÃO ──────────────────────────────────────────────────
  guardrail de pré-envio · eval como produto · citação de fonte
  facade (iframe no 1º clique) · teste A/B de fluxo
```

### 2.2 Tabela mestra

**Como ler.** Cada linha é um bloco de execução com dono claro. A coluna **Origem** dá os
identificadores nativos das frentes — é a rastreabilidade, e é onde está o detalhe (arquivos exatos,
critérios completos, armadilhas). Um bloco pode cobrir mais de uma tarefa da mesma frente quando
elas compartilham arquivos e dependências; nada foi descartado (a cobertura completa está na §2.3).

**Frentes:** **W** = widget · **C** = config/dashboard · **B** = backend/dados · **T** =
tracking/integração · **I** = infra (fora do repositório).

> **A ordem das ondas mudou em 13/08/2026 (D7); os identificadores dos blocos não.** Um bloco `2.xx`
> executa na **Onda 5**; um bloco `3.xx` executa na **Onda 2**. Isso é feio e é de propósito:
> renumerar 121 blocos quebraria a rastreabilidade com as quatro auditorias, com os quatro planos de
> frente e com o estudo, que os citam pelo número. **A coluna da esquerda é o nome do bloco; o
> cabeçalho da seção é quando ele executa.**

#### Onda 0 — Terreno *(1ª · 11 blocos · 24 pontos · 6,4% do esforço)*

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **0.1** | W0.5, W0.6 | W | Harness Playwright do widget + baseline de 16 snapshots, axe e contraste. **Primeiro passo: `pnpm add -D @playwright/test@^1.59.1` + `pnpm exec playwright install chromium`** — o runner não está instalado [M13] | `package.json` (devDeps), `playwright.config.js` (**já existe**, serve `spec/e2e/copilot/` e `spec/e2e/resolve-gate/`), `spec/e2e/widget/` ⚪, host fixo ⚪ | M | — | 🟡 | `--project=widget` roda; **as suítes `copilot` e `resolve-gate` continuam sendo descobertas pelo config e não regridem**; os 16 PNG e o JSON de baseline commitados **antes** de 0.2 |
| **0.2** | W0.1 = T0.1 = RG5 | todas | **Merge da v4.16.2, sozinho, sem nenhuma outra mudança no PR** | 113 arquivos do widget (+4.332 −7.635) | **G** | 0.1 | 🔴 | `pnpm test` verde; widget abre; os 16 snapshots revisados um a um |
| **0.3** | W0.2 | W | Reconciliar o build: o upstream quebrou `vite.config.ts` em 4 arquivos | `vite.config.ts`, `vite.lib.config.ts`, `vite.shared.ts`, `vitest.config.ts` | M | 0.2 | 🔴 | `bin/vite build` gera o mesmo conjunto; SDK sai IIFE; `manualChunks` do Leaflet **deletado**, não portado |
| **0.4** | W0.3 | I | gzip/brotli para `text/css` e `application/javascript` nas **4 VMs**, não só homologação | fora do repo (nginx/Ansible) | P | — | — | `curl -skI -H "Accept-Encoding: gzip, br"` devolve `content-encoding` em todas |
| **0.5** | W0.4, W1.15 | W | Gate de peso que mede o **grafo** (fecho transitivo do manifest) + trava nominal do Leaflet + **teto do `sdk.js`, que é a vantagem nº 1 e hoje não é medida por gate nenhum** (ver **A13**) | `scripts/widget-size.mjs` ⚪, `package.json` (`size-limit` já existe, `:23-32`), workflow | P | 0.3 | ⚪/🟡 | Reporta ~575 KiB (não 76,53 kB); falha se `leaflet-*.js` voltar aos imports estáticos; **falha se `sdk.js` passar de 15 KB gzip ou de 40 KB crus, e imprime o delta em bytes contra a linha de base de 29.014 B / 9.595 B gzip** [M15, **remedido em 17/08 pós-merge** — era 28.834/9.508 antes do build novo; ver §12] |
| **0.6** | T0.8 = BK-01 | B | Teste de paridade entre os **dois montadores** de config, com allowlist das 2 divergências atuais | spec novo ⚪ | P | — | ⚪ | Acrescentar chave em só um dos arquivos faz a suíte falhar nomeando a chave e o arquivo |
| **0.7** | T0.2, T0.3, T0.9 | C | Limpeza morta: apagar `WidgetBuilder.vue` (443 l. órfãs, ausentes do upstream), remover as 2 chaves i18n órfãs, criar o namespace `inboxWidget` | `settings/inbox/WidgetBuilder.vue`, `i18n/{pt_BR,en}/` | P | 0.2 | 🟢/🟡 | `grep -rn WidgetBuilder app/javascript` vazio; `inboxWidget.json` existe nos dois idiomas |
| **0.8** | T0.4, T0.6, T0.7, T0.10 | C | Dívidas de coerência: 37 chaves `NPS.*` em `en`, default de cor unificado (**D11**), aviso de `allowed_domains` vazio (**D8**), cortar o `import 'widget/i18n'` do dashboard (**D10**) | `i18n/en/inboxMgmt.json`, `channels/Website.vue:21`, `ConfigurationPage.vue`, `helper/preChat.js:1-4` | M | 0.2 | 🟡/🔴 | Painel em `en` não mostra chave crua; inbox criada por tela e por API nasce com a mesma cor; a tela diz o que acontece com domínio vazio |
| **0.9** | T0.5 | C | `ColorPicker` para de mutar o store direto (**D2**) | `Settings.vue:231-233, 948, 538` | P | 0.2 | 🔴 | Editar a cor e sair sem salvar: `inboxes/getInbox` devolve o valor original |
| **0.10** | BK-00 | I | Provisionar `ACTIVE_RECORD_ENCRYPTION_*` na frota e inventariar quais VMs já têm | `.env` de cada VM | P | — | — | `Chatwoot.encryption_configured?` → `true` em todas; segredo novo grava cifrado; antigos continuam legíveis |
| **0.11** | **novo — D14** (QUALITY-KIT §1.5) | W | **O fixture anti-erro**: todo E2E passa a falhar se houver `console.error`, `pageerror` ou HTTP 4xx/5xx não esperado. É a regra nº 1 do kit e o pré-requisito de valor de 0.1 — sem ela, um E2E verde diz apenas *"a página não travou"*, e o defeito que a IA introduz passa despercebido | `spec/e2e/fixtures.js` ⚪, `spec/e2e/widget/**` ⚪ (importam **deste** fixture, nunca de `@playwright/test`), lista `IGNORAR` comentada linha a linha | P | 0.1 | ⚪ | Um teste que carrega uma página com `console.error` injetado **falha**, nomeando a mensagem; um `fetch` que devolve 500 **falha**, nomeando método e URL; toda entrada de `IGNORAR` tem um comentário com a razão (regra MUST NOT do §10.3); e `grep -rn "from '@playwright/test'" spec/e2e/widget/` → **vazio** |

> **0.2 é bloqueante para tudo que toca código de aplicação.** 0.1, 0.4, 0.6 e 0.10 podem correr
> antes ou junto — 0.1 **precisa** vir antes, porque é o baseline que torna o merge de 113 arquivos
> revisável, e **0.11 vem junto de 0.1**: um baseline de 16 snapshots capturado por um harness que
> engole erro de console é um baseline que fotografa o defeito e o aprova.

#### Onda 1 — Nada mentindo *(2ª · 23 blocos · 50 pontos · 13,3% do esforço)*

*Quatro trilhas paralelas. A trilha "bridge" é pré-requisito de tudo que adiciona evento — nas duas
frentes.*

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **1.01** | W1.1 | W | Folha de tokens em arquivo próprio (a fundação da Task 21 vira código) | `widget/assets/scss/_tokens.scss` ⚪; `woot.scss` só o `@import` | M | 0.2 | ⚪ | `woot.scss` não define mais valor de token |
| **1.02** | W1.2 = BE-7 | B | **Tokens de marca calculados no servidor** (luminância WCAG, limiar 0,17913, preto puro), emitidos no ERB antes do 1º paint | `app/services/widget_tokens.rb` ⚪, `show.html.erb` (🟢 0/0) | M | 1.01 | 🟢 | `#009CE0` → `--w-on-brand: #000000` (**6,83:1**); `#2DC46F` → `#000000` (**9,24:1**); a asserção é `toBeCloseTo(x, 2)`, **nunca igualdade exata** (valores exatos: 6,8318 e 9,2371); cor inválida no banco **não** é interpolada no `<style>` |
| **1.03** | W1.3 | W | Os mesmos tokens atravessam a ponte e pintam o **launcher**, que vive no host | `IframeEventHelper.js`, `IFrameHelper.js:158-198,302-340` (🟢 0/0) | P | 1.02 | 🟢 | Launcher e painel derivam da mesma fonte; nenhuma fórmula de contraste em JS |
| **1.04** | W1.4–W1.8 | W | **Fim do `n-brand`**: 26 linhas, 18 arquivos com `:style` inline, YIQ e `--widget-color` órfã (**B1/B2**) | os 25 pontos da §A.1.1 do plano 22, `theme/colors.js` (só adição) | M | 1.02 | 🟢/🟡 | `grep -rn "n-brand\|getContrastingTextColor\|--widget-color" app/javascript/widget/ app/javascript/sdk/ app/javascript/shared/` → vazio. **`shared/` é obrigatório**: é onde vivem 8 dos 26 `n-brand` e 6 dos 18 `getContrastingTextColor` [M14, **n-brand remedido em 17/08 pós-merge** — ver §12] — CSAT, chips, cards e o botão genérico. Sem ele o aceite fica verde com o defeito vivo. Nota **R21**: mexer em `shared/` obriga a rodar também a suíte do dashboard |
| **1.05** | W1.9 | W | Literais do SDK → variáveis, **incluindo a armadilha do `:hover` verde** | `sdk.js:3,4,42,85,89,103,132,161`, `bubbleHelpers.js:46`, `IFrameHelper.js:321,334,335` | P | 1.03 | 🟢 | Launcher em `#009CE0` continua `rgb(0,156,224)` **em `:hover`** |
| **1.06** | W1.10, W1.11 | W | A11y mínima: `lang` no documento, `role="log"`, rótulos traduzidos, anel de foco visível | `show.html.erb:2`, `ConversationWrap.vue`, `bubbleHelpers.js:60`, `HeaderActions.vue`, `_tokens.scss` | M | 1.01 | 🟢/🟡 | 1 `[role="log"]`; todo `<button>` com nome acessível **em pt-BR**; `outline-color` não transparente |
| **1.07** | W1.12, W1.13 | W | Typing dots em CSS (mata o GIF de 19.296 B) + as três curvas da casa no painel | `AgentTypingBubble.vue`, `WTypingDots.vue` ⚪, `_tokens.scss`, `sdk.js:14` | P | 1.01 | 🟢 | Nenhuma requisição a `typing.gif`; `getAnimations()` na abertura não devolve `linear` em `transform` |
| **1.08** | W1.14, W1.16 | W | Peso sem tocar componente: `content` próprio do Tailwind (−94,9% do CSS) e assets órfãos (logo de 90 KB, 7 `@font-face` que ninguém baixa) | `tailwind.widget.config.js` ⚪, `public/brand-assets/`, fontes | M | 0.3, 0.5 | 🟡 | CSS do widget ≤ **80 KB crus** (hoje **1.692.256** no artefato pós-merge; era 1.103.132 antes — ver §12); logo < 5 KB; **`grep -o "@font-face" <css do widget>` → 0 (hoje são 7 [M16])** — sem esta asserção o teto de 80 KB é atingível sem remover as fontes, e a §8 item 8 ("não adotar webfont") fica sem nada que a sustente |
| **1.09** | W2.1 = T-I1.3 = T-I1.5 = T-C3.8 | W+T | **O bridge**: 16 ramos de `else if` viram mapa `{evento: handler}`, com validação de `e.origin` nos dois lados e fim do `targetOrigin: '*'` (**B4**) | `widget/bridge/` ⚪, `App.vue:258-345`, `widget/helpers/utils.js:8-21` | M | 0.2 | ⚪+🟡 | **`App.vue` < 310 linhas** (hoje **390** pós-merge; o bloco extrai 88 e devolve ~5 de chamada: 390 − 88 + 5 = **307**, margem de **3 linhas** — ver §12. O antigo `< 250` era inatingível pelo escopo deste bloco e faria uma tarefa correta ser reprovada); um teste por handler sem montar o App; `postMessage` de origem estranha é ignorado |
| **1.10** | W2.2 | W | Registry de `content_type` (`<component :is>`), corrigindo o `!isCards` duplicado e os dois ausentes | `widget/message-types/` ⚪, `AgentMessageBubble.vue:42-67,92-152` | M | 0.2 | ⚪+🟢 | Os 8 tipos renderizam; um 9º custa 1 arquivo + 1 linha |
| **1.11** | BK-03 = T-I1.1 + T-I1.2 | B | HMAC, portas 1 e 2: `PATCH /widget/contact` sem verificação e o *early return* que desliga a checagem (**B5**) | `contacts_controller.rb:4,55-62` (🟡 +16/−1) | P | 0.2 | 🟡 | Com modo obrigatório, as duas chamadas **não alteram** o contato; **e** o teste de não-regressão de quem não usa HMAC passa antes de qualquer merge |
| **1.12** | BK-04 | B | Corrigir o throttle que nunca casa (`contacts` → `contact`) e cobrir `set_user` | `rack_attack.rb:182-184` (🔴 +89/−22) | P | 0.2 | 🔴 | Request spec com `Rack::Attack` ligado bloqueia na 61ª chamada (hoje nunca bloqueia) |
| **1.13** | BK-02 = T-I1.10 = T-I5.1 + T-I5.2 | B | **Retry de webhook (B3)**: deixar a exceção subir, efeito colateral no esgotamento, `X-Chatwoot-Delivery` estável | `lib/webhooks/trigger.rb` (**reescrito pelo upstream — ver A7**), `webhook_job.rb`; molde em `agent_bots/webhook_job.rb:3-6` | M | **0.2** | 🟡 | Endpoint 500 registra 5 tentativas com o **mesmo** delivery id; `handle_failure` roda uma vez |
| **1.14** | BK-06 = T-I1.9 | B | Teto de tamanho **e de quantidade** de `custom_attributes` no contato (hoje o contato não tem limite nenhum) | `app/models/contact.rb`, `jsonb_attributes_length_validator.rb` | P | 0.2 | 🟡 | 51 chaves rejeitadas com erro legível; contato que já estourou continua salvando (a validação morde no crescimento) |
| **1.15** | BK-07 | B | Allowlist de nomes em `POST /widget/events` (hoje qualquer string vira evento no barramento) | `events_controller.rb:20-22` (🟢 0/0) | P | 0.2 | 🟢 | Nome fora da lista → 422; `webwidget.triggered` continua funcionando |
| **1.16** | BK-09 = T-I2.1 | B | **Auto-provisionar `CustomAttributeDefinition`** para chave nova vinda do site (**B6**, backend) | serviço novo ⚪, `contact_identify_action.rb:128-132`, `conversations_controller.rb:67-69` | M | 0.2 | 🟡 | Atributo sem definição prévia aparece no painel **e vira filtrável**; chave reservada não cria definição nem levanta erro; corrida cria uma definição só |
| **1.17** | T-C0.5 = T-I2.2, T-I2.8 | C | Seção **"Dados recebidos do site (N)"** no painel do agente, com selo de origem (**B6**, front) — e o IP mascarado por padrão | `CustomAttributes.vue:76-89` (🟢 upstream, +2/−5 fork) | M | 1.16 | 🟢/🟡 | `setCustomAttributes({carrinho_valor: 4200})` sem cadastro prévio aparece **na mesma sessão**, validado em navegador real, light e dark |
| **1.18** | BK-10 = T-C0.3 | B | Seed idempotente das ~12 definições de origem — **antes** do parser chegar a produção, senão o dado grava e some | serviço/seed ⚪ | P | 1.16 | ⚪ | Rodar duas vezes não duplica; as chaves aparecem no painel de uma conversa que as tenha |
| **1.20** | BK-12 | B | **Parar de destruir o dado na escrita.** É a **primeira** tarefa da trilha de origem e, depois da **D6**, a **única** que garante que o dado passe a existir — não há backfill que o resgate depois (hoje URL malformada vira `nil` em silêncio, e é o que explica os 0 de 3.180 [M12]) | `lib/url_helper.rb` (**0/0**) + 1 linha em `conversation.rb:536-539` — ver **A6** | P | 0.2 | 🟢/🟡 | **Cinco asserções, porque esta tarefa passou a carregar sozinha o que a trilha inteira promete (A16):** (1) URL com espaço não escapado **preserva** a origem; (2) URL com colchete cru idem; (3) o que ainda assim não validar vai para `additional_attributes['referer_raw']`, **nunca** para `nil` silencioso; (4) um request spec grava uma conversa por cada uma das 3 formas e lê os 3 valores de volta do banco; (5) `referer_raw` **não** é servido ao widget nem entra em prompt de IA (é dado cru de visitante) |
| **1.19** | BK-11 = T-C0.1 + T-C0.2 + T-C0.7 | B | **Parser de origem (C0)**, **prospectivo — só olha para frente, por decisão do produto (D6)**: `utm_*`, `gclid`/`gbraid`/`wbraid`, `fbclid`, `msclkid`, `ttclid`, host e path — `last_*` na conversa, `first_*` write-once no contato. **Inclui a lista de referrers de IA generativa** (`chatgpt.com`, `perplexity.ai`, `gemini.google.com`, `claude.ai`) como origem própria — era a linha 45 da §8.1, é uma lista de hosts no parser que já vai ser escrito | `app/services/tracking/` ⚪, criação da conversa | M | **1.18, 1.20** | ⚪/🟡 | Conversa criada com `?utm_source=google&gclid=X` mostra os campos no painel na mesma sessão; a 2ª conversa **não** sobrescreve `first_*`; conversa vinda de `chatgpt.com` aparece com origem `ia_generativa`, não como "direta". **A dependência de 1.20 é dura**: subir o parser antes do saneamento é prometer no relatório uma resposta que a validação continua apagando |
| ~~**1.21**~~ | BK-13 = T-C0.4 | B | ~~Backfill retroativo de origem~~ — **CORTADO em 13/08/2026 pela decisão D6.** O parser é prospectivo e só. Motivo medido [M12]: o backfill lê o que está no banco, e o que a validação anulou **não está lá** (0 de 3.180). Ele nunca teve como funcionar nesta base; mantê-lo condicional só mantinha viva uma dependência de medição na frota. Ver **A16** | — | — | — | — | *cortado — a linha permanece riscada para que ninguém a reintroduza achando que foi esquecimento* |
| **1.22** | T-C0.6 | B | Relatório mínimo: conversas por `utm_source`/`medium`/`campaign` no período | serviço + tela | M | 1.19 | ⚪ | O cliente vê de onde vieram os atendimentos **a partir da entrada de 1.19**; conversa sem origem aparece como **"origem não disponível"**, nunca como "origem direta"; **e o período anterior à entrada em produção aparece rotulado como "antes da medição"**, nunca vazio nem zerado — vazio é lido como "não veio ninguém", que é mentira |
| **1.23** | T-I1.4, T-I1.6, T-I1.7, T-I1.8, T-I1.11 | T | **O contrato do SDK deixa de ser mudo**: `Promise` em todos os métodos de dados, fila pré-boot drenada no mesmo formato, `setConversationCustomAttributes` antes da conversa enfileira em vez de 404, nenhuma exceção não capturada | `entrypoints/sdk.js` (🟢 0/0), `widget/bridge/` ⚪ | M | 1.09 | 🟢/⚪ | Os 7 métodos chamados antes do boot são aplicados depois com o mesmo efeito; chamada malformada dentro de tag do GTM não derruba as tags seguintes |
| **5.07** | T-C2.0 | T | **Propagação do SDK — realocado da Onda 5 para cá** (ver §3 item 11): hoje `cache-control: public, max-age=31556952` (1 ano) **sem `ETag` e sem `Last-Modified`**, e o header é do **Rails**, não do nginx | `config/environments/production.rb:24-26` (🟢) + carregador fino | P/M | 0.2 | 🟢/🟡 | Uma versão nova do `sdk.js` chega a um navegador que já tinha a antiga **em minutos**; conferido nas VMs da frota, não só em homologação |

> **A trilha de origem depois da D6, na ordem certa.** A ordem é **1.20 → 1.18 → 1.19 → 1.22**, e não
> a ordem numérica. **O backfill (1.21) foi cortado por decisão do produto**, e com ele saíram o
> portão **V3** e a dependência de medição na frota. Razão medida [M12]: hoje **0 conversas de 3.180
> têm `referer` preenchido**, e `conversation.rb:536-539` **anula o valor na escrita** quando a URL
> não valida. Três consequências passam a valer:
>
> 1. **O passado não volta, e paramos de fingir que talvez volte.** O dado não está degradado no
>    banco; ele não está lá. Em 100% da amostra disponível, já se perdeu. Um backfill condicional
>    mantinha viva a expectativa de um resgate que nunca ia acontecer, e mantinha uma tarefa da Onda 1
>    dependente de uma medição em produção que ninguém tinha agendado.
> 2. **1.20 é pré-requisito duro de 1.19 — e subiu de prioridade.** Ela deixou de ser "a tarefa que
>    melhora a qualidade do dado" e passou a ser **a tarefa que faz o dado existir**. Sem ela, o
>    parser entra em produção enquanto a validação continua apagando a resposta que o relatório
>    promete dar — e agora não há nem a esperança do backfill atrás. Por isso ela ganhou aceite
>    próprio, com cinco asserções em vez de uma frase.
> 3. **O bloqueador B4 da auditoria está resolvido — por decisão, não por medição.** A auditoria o
>    classificou como bloqueador porque a premissa *"a origem já está no banco"* nunca fora medida.
>    Ela foi medida, é falsa, e o produto decidiu não perseguir o passado. Um bloqueador que se
>    resolve cortando escopo é um bloqueador resolvido.
>
> **O que vai a cliente:** *"a partir da entrada em produção, toda conversa nasce sabendo de onde
> veio"*. Verdadeiro, verificável e suficiente para comprar orçamento. O que **não** vai, e agora
> nunca mais vai por engano: *"respondemos de onde veio o lead para a base inteira"*.

#### Onda 2 — Configuração *(3ª · 19 blocos · 56 pontos · 14,9% do esforço · os blocos são `3.xx`)*

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **3.01** | BK-08 = **BE-1** (absorve W3.1), **BE-2**, **BE-3** | B | **O lar da configuração**: `widget_profile`, `widget_triggers`, `widget_tracking` **e `widget_appearance`** em `inbox.additional_attributes`, com `store_accessor`, validação e **as quatro chaves declaradas de uma vez** no strong params (ver **A1**). `widget_appearance` é o lar de tema, posição, offsets, formato e texto do lançador, esconder bolha, estilo do painel **e o ícone do lançador** (3.19) — hoje isso vive no `localStorage` do admin (**D1**) | `app/models/inbox.rb:50` (🟡), `inboxes_controller.rb:217` (🔴, **uma** edição) | P | 0.2 | 🟡/🔴 | `PATCH` com `widget_profile: "marketing"` persiste e volta no `GET`; **`PATCH` com `widget_appearance: {position: "left"}` idem**; valor inválido → 422; **um `PATCH` parcial de uma chave não apaga as outras três** (o merge é raso, `inboxes_controller.rb:52-56`); inbox sem as chaves continua funcionando; **nenhum segredo aceito ali** — e o aceite é sustentado por mecanismo, não por afirmação: a lista negativa (`*_token`, `*_secret`, `api_secret`) entra **já aqui**, e 5.01 apenas a amplia |
| **3.02** | BK-14 = BE-4 | B | Schema dos gatilhos validado por `json_schemer` (já é dependência) | `app/models/inbox.rb`, schema em arquivo novo ⚪ | M | 3.01 | 🟡 | Objeto válido persiste; `value` negativo, `id` desconhecido ou seletor vazio → 422 nomeando o campo |
| **3.20** | **novo — D1** | B | **A abordagem em três níveis vira schema.** `widget_triggers` ganha `approach` com três valores — `discreet` (teaser pequeno, só texto), `bold` (teaser grande com foto, **o padrão**) e `aggressive` (abre o painel sozinho) — mais `degrade_on_return` (booleano, **ligado por padrão**) e `approach_mobile` (o nível em celular, que **nunca herda `aggressive`**). Valores em inglês `snake_case` pela arbitragem **A2**; rótulo em pt-BR no i18n | schema ⚪ (irmão do de 3.02 e do de 3.18), `inbox.rb`, os 2 montadores | M | 3.02 | ⚪/🟡 | `approach: "bold"` persiste e volta no `GET`; `approach: "agressivo"` → **422** (é o erro que a A2 existe para produzir); gravar `approach_mobile: "aggressive"` → **422 nomeando o campo**, com a mensagem dizendo que auto-open em celular não é oferecido; inbox sem a chave é lida como `bold` + `degrade_on_return: true`, **sem migration e sem backfill** (regra **A4**); e a projeção pública do payload de boot traz os três campos, porque a avaliação é do SDK (**A5**) |
| **3.03** | W3.2, BK-08 (seed) | B | `WidgetProfile.resolve` → **flags planas**; seed de defaults só na **criação** da inbox; troca de perfil **propõe**, nunca reescreve sozinha (ver **A3**) | `app/services/widget_profile.rb` ⚪, `show.html.erb` | M | 3.01 | ⚪+🟢 | Inbox com `csat_survey_enabled: false` e perfil `support` continua com CSAT desligado; sem migration de dados e **sem backfill** |
| **3.04** | BK-16 = T-C1.4 | B | Entregar as **quatro** chaves novas ao widget **nos dois montadores**, com `widget_tracking` como **projeção pública** e `widget_appearance` já resolvido pela regra de precedência de 3.18 | `show.html.erb` (🟢), `configs/create.json.jbuilder` (🟢) | P | 3.01, 3.02, 3.18, 0.6 | 🟢 | 0.6 passa; varredura por `token`/`secret` no JSON dos dois → vazio; **as quatro chaves saem nos dois arquivos, ou a suíte de paridade falha nomeando a que faltou** |
| **3.05** | W3.3 | W | O widget consome **flags planas**, nunca o nome do perfil | `configMixin.js`, `store/modules/appConfig.js` | M | 3.04 | 🟡 | `grep -rn "widgetProfile" app/javascript/widget/` não casa em nenhum `v-if` de template |
| **3.06** | T1.1, T1.2 | C | `useInboxWidgetConfig` (rascunho, `isDirty`, payload, salvar) + barra de salvar + confirmação ao sair | `inbox/widget/composables/` ⚪ | M | 3.01 | ⚪ | Editar e sair sem salvar não suja o store; "Descartar" restaura; a barra anuncia "N alterações não salvas" |
| **3.07** | T1.3, T1.5 | C | Seletor de perfil (2 `RadioCard`) + `useProfileVisibility` + a pergunta no wizard de criação, sem default pré-selecionado | `inbox/widget/` ⚪, `channels/Website.vue` | M | 3.06, 3.03 | ⚪/🟢 | Trocar o perfil abre diálogo listando nominalmente o que muda e o que continua gravado; nada é apagado |
| **3.08** | T1.6, T1.7, T1.8 | C | **O medidor de contraste**: os 4 pares com `color2k`, veredito, cor ajustada e explicação | `appearance/ContrastReadout.vue` ⚪, `useContrast.js` ⚪ | M | 3.06 | ⚪ | `#2DC46F` exibe **2,27:1** para "marca como texto no claro" e marca como reprovado; `#009CE0` escolhe **preto** (**6,83:1**); e o resultado **bate com o servidor** (1.02) em 20 cores, com `toBeCloseTo(x, 2)` — **igualdade exata aqui produz falha por 0,02 numa implementação correta**, que foi o que quase aconteceu (valores exatos: 2,2734 e 6,8318) |
| **3.09** | T1.9, T1.10, T1.15, T1.16 | C | Tela 1 completa (tema, lançador, offsets, textos, recursos, avançado), ligada ao roteador de abas (4 linhas em `Settings.vue`) + i18n pt-BR **e** en | `appearance/` ⚪, `Settings.vue` (🔴, mínimo), `i18n/*/inboxWidget.json` | M | 3.08, **3.18** | ⚪+🔴 | Mudar posição para "esquerda", salvar e abrir **em outro navegador e outro admin**: continua "esquerda" (o teste que falha hoje por **D1**, e que **só é satisfazível porque 3.01 + 3.18 criaram a chave** — sem elas não há coluna, chave, strong param nem montador que carregue `position`); com `chatwootSettings` sobrescrevendo no site, a tela **mostra o aviso de override** em vez de mentir |
| **3.10** | T1.11, T1.12, T1.13 | C | Preview honesto: consome os **tokens reais** (mata as ~74 custom properties literais, **D4**), aplica os 7 tokens derivados, ganha toggles claro/escuro e desktop/mobile | `modules/widget-preview/` (🟢 0/0) | M | 1.01, 3.08 | 🟢 | Busca por `--slate-`/`--solid-` em `widget-preview/` → vazio; o toggle de tema funciona **independente** do tema do dashboard |
| **3.11** | T1.14 | C | Fim do snippet montado por **corte de string no byte 13**, com JavaScript executável dentro do i18n (**D3**) | `widget-preview/Widget.vue:94-101` + backend | M | 3.04 | 🟢/🟡 | Tradutor não consegue mais quebrar o snippet do cliente; o script vem pronto do servidor |
| **3.12** | T2.1 = BE-6 | B | Ampliar `EDITABLE_ATTRS` do pré-chat: `step`, `show_if`, `mask`, `validator`, `help_text`, `error_message`, `position` | `web_widget.rb:34-40` (**0/0 dos dois lados**) | P | 0.2 | 🟢 | Campo com `mask` e `show_if` persiste; forma inválida é rejeitada |
| **3.13** | T2.2, T2.3 | C | Máscaras e validadores BR: CPF, CNPJ, CPF-ou-CNPJ, CEP, UF; e-mail corporativo, telefone, anti-lixo em 3 regras explícitas | `helper/brMasks.js` ⚪ + espelho no widget | M | — | ⚪ | `529.982.247-25` aceito, `…-26` rejeitado pelo DV, **e `111.111.111-11` rejeitado pela regra de dígitos repetidos** |
| **3.14** | T2.4–T2.8, T2.11 | C | Tela 3 (pré-chat): editor de campo, etapas com teto de 8, condicional de etapa anterior, os 3 modos (Simples/Construtor/Fluxo) e i18n | `prechat/` ⚪ | **G** | 3.12, 3.13, 3.06 | ⚪ | 9º campo impossível com o motivo à vista; validação **no blur**; migrar Simples↔Construtor não perde campo |
| **3.16** | T2.9 | C | Prévia da etapa 1 do pré-chat dentro do preview | `widget-preview/` | M | 3.10, 3.14 | 🟢 | O que a tela configura é o que o preview mostra |
| **3.17** | W3.4, W3.7 | W | Tela inicial por perfil e base de conhecimento governada por flag (+ o `bg-white` sem `dark:` do `ArticleViewer`) | `views/Home.vue`, `pageComponents/Home/Article/*`, `ArticleViewer.vue:13` | M | 3.05 | 🟢/🟡 | Com `showKnowledgeBase: false`, **nenhum request a `/articles` sai** |
| **3.18** | **BE-2** (D1) | B | **A aparência sai do `localStorage` e vira configuração**: JSON Schema de `widget_appearance` (`theme`, `position`, `offset_x`, `offset_y`, `launcher_type`, `launcher_text`, `hide_bubble`, `panel_style`, `launcher_icon`), com `maxLength`/`enum` por campo, **teto de tamanho do jsonb** e a **regra de precedência**: o banco é o padrão, `chatwootSettings` no site sobrescreve, e a tela declara que há override ativo | schema ⚪ (irmão do de 3.02), `inbox.rb`, os 2 montadores, `Settings.vue:350-352, 418-430, 507-512` e `constants/localStorage.js:3` (**remoção** da leitura por `localStorage`) | M | 3.01 | ⚪/🔴 | Objeto válido persiste; `position: "center"`, offset 500 ou texto de 200 caracteres → 422 nomeando o campo; **admin A grava e admin B, em outro navegador, lê o mesmo valor** (é o que **D1** quebra hoje); com `chatwootSettings.position` presente no site, o widget usa o do site **e** a tela avisa; jsonb acima do teto → 422 (o `additional_attributes` vai para o HTML de **toda** página do cliente) |
| **3.19** | **pedido do Walisson** · gap **MESA M12** do estudo · L-04 da auditoria 33 · **ajustado por D5** | W+B+C | **O ícone do lançador deixa de ser um `path` fixo**: campo `launcher_icon` com três modos — `default` (o balão, **e é o padrão de fábrica de toda inbox nova, em qualquer perfil**), `image` (upload) e `agent_photo` (reusa o avatar da inbox). **O padrão por perfil caiu (D5)**: nenhuma inbox nasce com foto, porque a única foto que o produto poderia escolher sozinho seria genérica, e foto genérica é pior que balão. Em vez disso, a tela de aparência **sugere**: um aviso permanente recomendando subir a foto de alguém do time, com a razão escrita ("rosto converte mais"), e **nunca** oferecendo banco de imagem. Hoje `bubbleHelpers.js:28-46` monta o SVG com `path` fixo e `fill: '#FFFFFF'` cravado (`:46`), **sem caminho algum para imagem**, e `:60` traz `title = 'Open chat window'` em inglês | `sdk/bubbleHelpers.js:28-60` (🟢 0/0), `widget_appearance` (3.18), `appearance/` (campo + aviso + preview), `ActiveStorage` + variante servida pronta | M (**P–M** se entrar junto de 3.09 e 1.05, que já abrem os mesmos arquivos) | 3.18, 1.05, 3.10 | 🟢/⚪ | **Nove asserções, cada uma é um jeito de o recurso quebrar na página do cliente:** (1) **inbox criada agora nasce com `launcher_icon: "default"` e o balão na cor da marca** — verificado criando uma inbox pela tela **e** pela API, que é onde o default costuma divergir (**D11** do plano 23); (2) **a tela de aparência mostra o aviso sugerindo foto do time sempre que o modo é `default`**, e o texto não oferece nem linka banco de imagem; (3) imagem acima do teto (**≤ 20 KB**, WebP com fallback PNG) é recusada no upload, com o motivo; (4) o byte vem do **nosso domínio** com URL estável e cache longo — **nenhuma CDN externa** (R18: CSP de cliente barra origem estranha); (5) `preload`/`fetchpriority` garantem que o lançador não pisque vazio; (6) `onerror` volta ao `bubbleSVG` — 404 na foto **nunca** deixa o site sem canal de contato; (7) anel/borda derivado de `--w-brand-border`, ≥ 3:1 contra a cor da marca **e** contra fundo claro e escuro (SC 1.4.11); (8) recorte `object-fit: cover` no círculo de 64 px congelado (§8 item 2) — foto retangular não entorta o lançador; (9) nome acessível traduzido ("Falar com a Marina" / "Abrir chat"), **nunca** o `'Open chat window'` de hoje. E o preview (3.10) mostra o ícone escolhido |

> **Sobre o mérito do ícone, depois da D5.** O estudo mediu que **9 dos 13 lançadores do corpus são
> um balão dentro de um círculo colorido e só a Leadster usa fotografia humana**, e que **nenhum
> relatório do corpus traz teste comparando os dois**. A decisão do dono do produto é que a tela
> **recomende a foto de alguém do time, explicando que rosto converte mais** — e essa decisão está
> aplicada na asserção (2) acima, com o texto do aviso escrito na tela. O que a engenharia registra,
> sem reabrir a decisão: **a afirmação "rosto converte mais" é [INFERÊNCIA] de mercado, não é
> [MEDIDO] no nosso corpus**, e o caminho para transformá-la em número já existe neste plano — a
> instrumentação do bloco **4.21** mede conversão por nível de abordagem, e o teste A/B do **6.05**
> mede variantes. Se em três meses o dado disser o contrário, o texto do aviso muda; é uma string de
> i18n. A decisão de fábrica — **balão, nunca foto genérica** — não depende dessa medição e está
> certa dos dois jeitos.

#### Onda 3 — Captura *(4ª · 20 blocos · 76 pontos · 20,3% do esforço · os blocos são `4.xx`)*

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **4.01** | BK-20 | B | **A ponte que falta**: responder a `input_select`/`form` no widget passa a gerar mensagem `incoming` — sem isso, `wait_for_reply` **nunca retoma** no canal web | `widget/messages_controller.rb:15-28` (🟡 +22/−3), `automation_rule_listener.rb:299-312` | M | 0.2 | 🟡 | Flow com `wait_for_reply` avança quando o visitante clica; 2 cliques = 1 mensagem e 1 retomada; com o motor desligado, nada muda |
| **4.02** | BK-21, BK-22, BK-23 | B | `trigger_type: widget_prechat` (enum, sem migration), resolução "qual fluxo entregar" no servidor, adaptador de mensagem estruturada para o canal web, teto de 8 campos | `flow.rb:42`, `app/services/flows/` ⚪ | **G** | 4.01 | 🟢/⚪ | Dois fluxos ativos entregam fluxos diferentes conforme a URL; o widget **nunca** recebe a definição completa |
| **4.03** | W3.5 | W | Fluxo de captura conversacional (campos como mensagens, 8 no total, e-mail **ou** WhatsApp, máscaras BR no blur) | `widget/capture/` ⚪, `message-types/` ⚪ | **G** | 1.10, 3.05, 3.13 | ⚪ | Fluxo de 4 campos conclui em 375 px sem scroll horizontal |
| **4.04** | T3.1–T3.6, T3.9 · **ampliado por D1** | C | Tela 2 (gatilhos e abordagem): os 7 gatilhos × desktop/mobile × cooldown, teaser, frequência, "quando não aparecer", segmentação, modo Recomendado × Avançado, i18n — **mais o seletor dos três níveis de abordagem** (Discreto · Chamativo · Agressivo), com o que cada um faz escrito ao lado, e o interruptor da **degradação por familiaridade**, ligado por padrão | `triggers/` ⚪ | **G** | 3.02, **3.20**, 3.06 | ⚪ | Os três níveis aparecem com **Chamativo pré-selecionado**; escolher **Agressivo** abre o aviso do bloco 4.20 e **não** liga nada em celular; ligar só "tempo" mostra o aviso de gatilho composto; seletor CSS inválido é rejeitado no blur; a tela mostra, em uma frase, o que a degradação vai fazer com o visitante que voltar |
| **4.05** | T3.7 | C | Vínculo teaser ↔ campanha existente (**campanha é mensagem, gatilho é momento**) | `triggers/` + `campaigns` | M | 4.04 | 🟡 | Editar o texto do teaser edita a campanha vinculada; não nasce uma campanha por gatilho |
| **4.06** | W3.8 · **ampliado por D1** | W | **O teaser**, no host, ao lado do launcher: gatilho composto 8 s **E** 30%, dispensa persistida — **em duas formas**, porque a abordagem tem três níveis: **Discreto** (balão pequeno, só texto, sem foto) e **Chamativo** (balão grande com foto e chips, **o padrão**). O terceiro nível não é teaser: é o auto-open do bloco 4.20 | `sdk/bubbleHelpers.js`, `sdk/sdk.js`, `cookieHelpers.js` | **G** | 1.05, 3.04, 4.04, **3.20** | 🟢 | Os 8 aceites da §C.2 do plano 22 — inclusive: com `teaserEnabled: false`, o código **não é montado**. **O nono (ver A13): o gate de peso publica o delta do `sdk.js` no PR, e o acréscimo deste bloco cabe no teto de 15 KB gzip** — o teaser é o maior consumidor de bytes do host em todo o plano (DOM, gatilho composto, cookie de dispensa, avatar, chips, i18n, `all: revert`). **E o décimo, da D1: as duas formas compartilham o mesmo DOM e o mesmo gatilho** — Discreto é o Chamativo com foto e chips ocultos por CSS, nunca um segundo componente. Dois componentes de teaser dobram o peso do arquivo que 100% dos visitantes baixam, para entregar a mesma coisa menor |
| **4.19** | **novo — D1** | W | **A degradação por familiaridade.** Visitante **novo** recebe o nível configurado; visitante que **já foi abordado e não converteu** recebe o **nível abaixo** (`aggressive` → `bold` → `discreet` → nada). O estado mora num cookie do host, primeira parte, com a mesma helper de domínio que o SDK já usa (`sdk/cookieHelpers.js:26-44`, `setCookieWithDomain`), e guarda **duas coisas apenas**: quantas vezes já abordamos e se converteu. Nada de perfil de navegação, nada de identificador novo | `sdk/tracking/approach.js` ⚪, `sdk/bubbleHelpers.js`, `sdk/cookieHelpers.js` (🟢) | M | 4.06, 3.20 | 🟢/⚪ | Primeira visita em `bold` mostra o teaser grande; **segunda visita sem conversão mostra o teaser pequeno**; terceira não mostra nada; **converter (abrir a conversa e enviar mensagem) zera o contador**; com `degrade_on_return: false` o nível não cai nunca; o cookie tem `secure` quando a página é HTTPS (era a linha 46 da §8.1) e expira em 30 dias; e **o acréscimo de bytes ao `sdk.js` é publicado no PR** pelo gate 0.5 (**A13**) |
| **4.20** | **novo — D1** | C+W | **Auto-open opt-in.** O nível `aggressive` abre o painel sozinho — **desligado por padrão, disponível para todas as contas**, sem gate de plano. O mecanismo já existe: `entrypoints/sdk.js:83-85` expõe `toggle(state)` e chama `IFrameHelper.events.toggleBubble` (`IFrameHelper.js:228`) [M21]; o que este bloco constrói é a **política** — quem pode ligar, o que a tela avisa e o que nunca acontece. **Em celular não liga por padrão**, e o texto do aviso **não menciona penalização do Google** (decisão do produto) | `triggers/` (o aviso), `sdk/`, i18n `pt_BR`/`en` | P | 4.04, 4.19 | ⚪/🟢 | Com `approach: "aggressive"` o painel abre sozinho **uma vez** por sessão, respeitando o gatilho composto de 4.06; com qualquer outro nível ele **nunca** abre sozinho; em viewport de 375 px o painel **não** abre sozinho a menos que o administrador tenha ligado `approach_mobile: "aggressive"` — e 3.20 recusa esse valor com 422, então o caminho está fechado nas duas pontas; a tela mostra o aviso antes de salvar; **`grep -rn "Google" nas strings de i18n desta tela → vazio**; `Esc` fecha o painel aberto por auto-open e devolve o foco ao lançador (2.11) |
| **4.21** | **novo — D1** | T | **Instrumentação dos três níveis** — o motivo pelo qual os três existem. Cada exibição, dispensa, abertura e conversão carrega o nível (`discreet`/`bold`/`aggressive`), se foi degradado, e qual era o nível configurado. Vai pelo mesmo caminho de 5.03/5.04, sem vocabulário novo (**A9**) | `sdk/tracking/`, `sdkEvents.js` (🟢 0/0), listener de 5.03 | M | 4.19, 5.03, 5.04 | 🟢/⚪ | Uma consulta responde **"qual nível converte mais nesta conta"** sem abrir console de ninguém; o evento traz `approach` **e** `approach_configured` (para separar o efeito da degradação do efeito do nível); exibição sem abertura também é registrada — **sem denominador não há medição**, que é o mesmo motivo pelo qual 4.18 existe; nenhum dado pessoal no payload (regra de 5.14: nomes de campo, nunca valores) |
| **4.22** | **novo — D10** | C+W | **Coexistência com as campanhas legadas, com a regra de precedência escrita.** Hoje o widget já busca campanhas com `trigger_rules` e cacheia por 1 h (`widget/store/modules/campaign.js:48-52`, `CACHE_EXPIRY = 60 * 60 * 1000`) [M22]; quando `widget_triggers` entrar, a conta passa a ter **dois** caminhos de mensagem proativa. **A regra:** o motor novo tem precedência; se um gatilho novo está ativo e apto a disparar, **a campanha legada não dispara na mesma sessão**; a campanha legada continua listada, editável e funcionando enquanto não houver gatilho novo apto; e a tela mostra uma seção **"modo antigo"** com um botão de importar a campanha para gatilho. É rampa, não corte — o mesmo padrão já usado na tela de Automações | `widget/store/modules/campaign.js` (🟡), `sdk/`, `triggers/` (seção "modo antigo") | M | 4.04, 4.06 | 🟡/⚪ | Conta com campanha legada ativa **e** gatilho novo ativo: o visitante vê **uma** mensagem proativa, e é a do gatilho novo; desligando o gatilho, a campanha legada volta a aparecer **sem republicar nada**; conta que só tem campanha legada **não muda de comportamento** (é o teste que impede a regressão silenciosa na frota); importar uma campanha cria o gatilho equivalente e **desativa** a campanha, nunca as duas ligadas |
| **4.07** | T3.8 | C | Teaser no preview, com o gatilho simulado | `widget-preview/` | M | 3.10, 4.04 | 🟢 | O teaser configurado aparece com texto, avatar e chips reais |
| **4.08** | W3.6 | W | Saída para WhatsApp no perfil marketing, carregando o contexto da conversa | `message-types/` ⚪, casca de `ChatFooter.vue` | M | 4.03 | ⚪ | O link leva o contexto; `primaryExit: 'none'` esconde |
| **4.11** | W4.6 | W | Piscar do título por 60 s com a aba oculta; som **desligado** por default, opção por inbox | `sdk/` ⚪, `IFrameHelper.js:145-156` | P | 3.03 | ⚪/🟢 | O título alterna e para no `visibilitychange`; som não toca sem opt-in |
| **4.12** | BK-05 = I5 prioridade 1 | B | `conversation_resolved` no webhook de conta (já existe no barramento, entregue **só a agent bots**) | `webhook.rb:32-34` (🟢), `webhook_listener.rb` (🟡) | P | 1.13 | 🟢/🟡 | Webhook inscrito recebe o payload ao resolver, com assinatura e delivery id |
| **4.13** | T-I5.3, T-I5.4, T-I5.5 | T | Webhooks: assinar os **três caminhos hoje não assinados** (inbox API, agent bot, automação/macro/flow); filtro por inbox de verdade (hoje é letra morta); revisar a unicidade de URL | `automation_rules/action_service.rb`, `macros/execution_service.rb`, `flows/action_service.rb`, `webhooks_controller.rb`, `webhook_listener.rb:130-146` | M | 1.13 | 🟡 | Webhook criado com `inbox_id` recebe **só** os eventos daquela inbox; webhook sem `inbox_id` continua recebendo tudo |
| **4.14** | T-I5.6, T-I5.7, T-I5.8, BK-35 | T | Log de entregas + replay (retenção 7 dias), rotação de segredo, **parar de devolver o segredo em texto claro** no `index`, ping de validação no cadastro | tabela nova ⚪, `_webhook.json.jbuilder:6`, endpoints N4/N5 | M | 1.13 | ⚪/🟡 | A tela mostra a entrega falhada e o reenvio chega com o **mesmo** `X-Chatwoot-Delivery`; o `index` não expõe segredo |
| **4.15** | BK-24 = T-I2.6 | B | Três estados de enforcement de identidade (`desativado`/`observado`/`obrigatorio`), **mantendo** `hmac_mandatory` como está | `inbox.rb`, `contacts_controller.rb:55-62`, `_inbox.json.jbuilder` | M | 1.11, 3.01 | 🟡 | Ligar `observado` numa inbox com tráfego produz a lista de identificações não verificadas **sem quebrar nenhuma sessão** |
| **4.16** | BK-25 | B | Portas 3 e 4 do HMAC: pré-chat e `input_email` deixam de **fundir cadastros** sob enforcement estrito | `contact_identify_action.rb`, `conversations_controller.rb:19-26`, `messages_controller.rb:15-25` | M | 4.15 | 🟡 | Sob estrito, e-mail de contato existente digitado no pré-chat **não funde**; sob `desativado`, comportamento idêntico ao de hoje |
| **4.17** | BK-26, BK-27 = T-I2.3, T-I2.4, T-I2.5 | B | Colunas de origem/confiança em `custom_attribute_definitions` (migration aditiva), enforcement por atributo, e delimitar os atributos do site no prompt da IA — hoje o gate cobre **só o contato**, e a conversa, que o site escreve com mais liberdade, não tem controle nenhum | migration ⚪, `custom_attribute_definition.rb` (🟡 +32/−6), `system_prompts_service.rb:312-322` (`enterprise/`) | M | 1.16 | 🟡/🟢 | Atributo "exige origem verificada" escrito sem credencial **não** altera o valor e a tentativa fica registrada; texto com instruções no atributo não muda o comportamento do agente (**dry run**, nunca IA de cliente) |

| **4.18** | **BE-5** (cap. 36 do estudo; base do dropout **M13**) · **aprovado por D3** | B+W | **Lead incompleto**: persistir a resposta parcial do pré-chat **antes** de a conversa existir, e etiquetá-la no painel. É mudança do **momento em que a conversa nasce**, não de forma de campo — e é o que destrava dropout por etapa, analytics do widget e o teste A/B do bloco 6.05. **O mockup 22, já mostrado, promete isso na seção "Salvar lead incompleto"** — a decisão D3 fecha o buraco entre o que foi aprovado e o que estava planejado | tabela/serviço ⚪, `widget/capture/` ⚪, `PreChat/Form.vue` (🔴 → só delegação), painel do agente | **M–G** | 3.14, 4.03 | ⚪/🔴 | Visitante preenche nome e e-mail, abandona no 3º campo e fecha a aba: o lead existe no painel **marcado como incompleto**, com a etapa em que parou; retomar na mesma sessão **não** duplica o registro; o lead incompleto **não** dispara automação, campanha nem webhook de conversa (ele não é uma conversa); o relatório responde **"quantos leads perdemos e onde"**; e a retenção do registro parcial é **configurável**, com padrão declarado, porque é dado pessoal de quem **não** concluiu (nota de LGPD: quem abandona não consentiu com nada) |

#### Onda 4 — Atribuição *(5ª · 22 blocos · 78 pontos · 20,8% do esforço · os blocos são `5.xx`)*

> **A onda mudou de nome, e o nome importa.** Ela se chamava *"Prova de valor"* quando era a última.
> Depois da **D7** ela é a quinta de sete, e o que ela entrega tem nome próprio: **atribuição** — de
> qual campanha veio o lead, e o que aconteceu com ele depois. "Prova de valor" descrevia a posição
> dela no cronograma, não o conteúdo; e a posição mudou.

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **5.01** | BK-15 = T-C1.1 | B | Config **pública** de tracking por inbox, com recusa explícita de qualquer chave que pareça segredo | `inbox.rb`, schema JSON ⚪ | M | 3.01 | 🟡 | Gravar `access_token` dentro de `widget_tracking` → 422 apontando a tela de credenciais |
| **5.02** | T-C1.2, T-C1.7, BK-30 | B | Tabela própria de credenciais com `encrypts` por segredo, `audited` com `except:`, serialização que devolve só `configured` + 4 últimos caracteres — **e o OAuth de um clique** para Meta e Google, que é requisito de produto: colar Pixel ID é trivial, gerar `access_token`, `api_secret` e conexão do Ads não é | migration ⚪, modelo, controller N1/N2, policy, fluxo OAuth ⚪ | **G** | **0.10**, 5.01 | ⚪ | Segredo nunca volta em claro; `verify` testa em modo teste sem gravar evento real; o cliente conecta a conta de anúncios sem sair da tela |
| **5.03** | T-C3.1, T-C3.9, BK-31 | T | Contrato de eventos escrito + registro server-side (`tracking_events` + `tracking_deliveries`) com `event_id` e índice único por (evento, destino) | documento ⚪, migrations ⚪, 2 modelos, listener novo | M | 1.09 | ⚪ | Resolver uma conversa gera o evento com `event_id`; o índice único impede entrega dupla |
| **5.04** | T-C3.2–T-C3.7, BK-17, T-I4.2, T-I4.4, T-I4.5 | T | Os eventos que faltam, emitidos **uma vez** e consumidos por dois lados: `conversation_created` (com id), `prechat_submitted`, `message_sent_by_visitor`, `csat_submitted`, `campaign_shown`, `lead_identified` — do **store**, nunca do componente do campo minado | `sdkEvents.js` (🟢 0/0), ações do store, listener novo | M | 5.03 | 🟢/⚪ | A ordem `widget_opened → conversation_created → prechat_submitted → lead_identified` é observável por `addEventListener` em navegador real; renomear um evento **quebra o CI** |
| **5.05** | BK-18 = T-C6.1 | B | `event_id` nasce no backend e volta ao widget (`204` → `200 {event_id}`) | `events_controller.rb:4-8` (🟢) | P | 1.15, 5.03 | 🟢 | Resposta traz UUID; o `pushEvent` atual continua funcionando sem alteração |
| **5.06** | T-C1.3, T-C1.5, T-C1.6, T-C1.8, T4.1–T4.5, T4.8, T4.9, T4.10 | C | **Tela 4 (rastreio)**: 4 sub-abas, `SecretField` que nunca re-exibe, mapa de 12 eventos com defaults, valor do lead, cartão somente-leitura do que é da conta, modo teste com desligamento automático, i18n | `tracking/` ⚪ | **G** | 5.01, 5.02, 3.06 | ⚪ | Pixel numa inbox e não em outra: o HTML servido da primeira traz o ID e o da segunda não; nenhum segredo em HTML, config, `index` ou log |
| ~~**5.07**~~ | T-C2.0 | T | **Propagação do SDK — movido para a Onda 1** (ver a tabela da Onda 1 e a §3 item 11). Motivo: nove blocos mudam o `sdk.js` antes da Onda 5, e o cache de 1 ano sem validador pode segurar o teaser por até 12 meses num visitante recorrente | — | — | — | — | *realocado* |
| **5.08** | T-C2.1–T-C2.8 | T | Coletor de origem no SDK: `first_*` write-once, `last_*` sem zerar por navegação interna, `_fbc`/`_gcl_aw` no formato oficial, allowlist de cookies, `client_id`/`session_id` com timeout de 1 s, carregado **sob demanda** | `sdk/tracking/` ⚪ + 1 linha em `IFrameHelper.js` | M | 5.07, 5.01 | ⚪/🟢 | Visitante que chega por anúncio, navega 5 páginas e só então abre o chat: a conversa nasce com o `first_utm_source` e o `gclid` certos; no Safari, 7+ dias depois, a origem **sobrevive** |
| **5.09** | T-C7.1–T-C7.6 | T | Consentimento (Consent Mode v2 e LGPD): método público, estado por conta/inbox, gate no client-side, `consent` no payload server-side, ordem de execução correta | `sdk/tracking/` ⚪, serviço de estado | M | 1.23, 5.01 | ⚪/🟡 | Com CMP negando: **zero** disparos client-side; aceitando depois, o `update` chega e os seguintes disparam |
| **5.10** | T-C4.1–T-C4.10 | T | **Ponte de tags**: `trackSingle` no Meta, `send_to` no Google, `dataLayer` sempre, `skipPageView`, detecção do que já existe, guarda de exceção, e **"somente dataLayer" como padrão de fábrica** | `sdk/tracking/tags.js` ⚪ | M | 5.08, 5.09, 5.04 | ⚪ | Página com 3 pixels: o evento **não** vaza; sem pixel: nenhum `PageView` duplicado; `gtag`/`dataLayer` do cliente continuam funcionais; console limpo |
| **5.11** | T-C5.1–T-C5.10, BK-32 | T | Fila server-side: CAPI, Measurement Protocol e Enhanced Conversions, com normalização **antes** do hash, SHA-256 no servidor, IP e UA **do visitante**, retry com backoff e DLQ visível | `app/services/tracking/` ⚪, `app/jobs/tracking/` ⚪ | **G** | 5.02, 5.03, **verif. 2 (DPA)** | ⚪ | `Lead` aparece com Browser **e** Server sem dobrar o total; EMQ ≥ 6,0; com bloqueador ligado, o server-side entrega |
| **5.12** | T-C5.9 | T | **Modo "sem PII"** — o caminho que não depende do jurídico | idem | P | 5.11 (precede o modo com PII) | ⚪ | Nenhum campo `em`/`ph`/`fn`/`ln` sai; verificado no log de auditoria, que registra **nomes** de campos |
| **5.13** | T-C6.2–T-C6.4 | T | Deduplicação de verdade: mesmo `event_id` nos dois caminhos, guarda da janela de 48 h, teste de contagem | serviços | P | 5.10, 5.11 | ⚪ | No Test Events da Meta, os dois eventos com o **mesmo** `event_id` e a dedup reconhecida |
| **5.14** | T-C8.1–T-C8.5, T4.6, T4.7, BK-34 | T+C | Auditoria e diagnóstico: log por evento (**nomes**, nunca valores), retenção, painel por inbox, botão de teste, kill switch por conta e inbox, EMQ exibido | modelo ⚪, `DiagnosticsPanel.vue` ⚪ | M | 5.11 | ⚪ | Um agente de suporte responde "o evento saiu?" sem abrir console de ninguém; busca por `@` no painel renderizado → vazio |
| **5.15** | T-C8.6, T-C8.7, BK-19 | T | **Contrato público de integração**, escrito junto (decisão I6) + guia de verificação para o cliente | documentação ⚪ | M | 5.04, 5.06 | ⚪ | Um integrador que nunca viu o produto instala, identifica um usuário e dispara um evento **só com o documento** |
| **5.22** | **novo — D8** (era a linha 29 da §8.1) | C+T | **Instalação em WordPress, Wix e GTM**: um caminho documentado por plataforma, com o snippet pronto e a armadilha de cada uma escrita (WordPress: onde colar sem que o tema sobrescreva na atualização; Wix: a restrição de scripts custom por plano; GTM: por que o snippet vai em tag de HTML customizado e **não** em template, e o que acontece com o `dataLayer` do cliente). **Todos os concorrentes do corpus têm isso; nós não temos nenhum.** É documentação + o snippet que 3.11 já passa a servir pronto do servidor — não é código novo | documentação ⚪, `appearance/`/instalação (o snippet por plataforma), i18n | P | 3.11, 5.15 | ⚪ | Uma pessoa que nunca viu o produto instala o widget num WordPress limpo **seguindo só o documento**, e o widget aparece; o snippet do GTM não sobrescreve `window.dataLayer` do cliente (é a regra **R9**, aqui verificada na porta de entrada); cada plataforma tem a sua armadilha escrita, não uma nota genérica de "consulte seu desenvolvedor" |
| **5.23** | **novo — D9** (decisão **I5** do `DECISOES.md`, era a linha 33 da §8.1) | C | **Contexto do sistema externo ao lado da conversa, na versão simples**: um painel lateral que mostra **o que o site mandou** — os ~12 atributos de origem (1.19), os atributos auto-provisionados com selo (1.17), o estado de identidade (4.15) e, quando houver, o lead incompleto (4.18). Hoje isso tudo cai misturado na lista de atributos do `ContactPanel.vue:283` (`CustomAttributes`), sem hierarquia e sem dizer quem escreveu o quê. **O app embutido fica para depois, e a razão está escrita:** o mecanismo já existe (`ConversationBox.vue:150-151` monta abas de dashboard apps por `v-for`), então adiar não custa arquitetura — custa só a decisão de quando | `ContactPanel.vue` (🟡), componente novo ⚪, i18n | M | 1.17, 1.19, 4.15 | 🟡/⚪ | O agente responde **"de onde veio esta pessoa e o que o site já sabe dela"** sem rolar a barra lateral inteira; a seção distingue visualmente o que o **site** mandou do que o **agente** escreveu; IP continua mascarado por padrão (1.17); com zero atributos, a seção **não aparece** em vez de aparecer vazia; e nenhuma informação nova é buscada por request extra — é reorganização do que já chega |
| **5.16** | T-I3.1 | T | `track(name, properties)` — assinatura da integração, vocabulário do tracking, **uma implementação** | `sdk/`, `sdkEvents.js` | M | 1.23, 5.03 | 🟢 | Evento tipado do site chega ao registro server-side e ao `dataLayer` pela mesma chamada |
| **5.17** | T-I3.2–T-I3.5, T-I3.8, T-I4.1, T-I4.3 | T | Superfície nova: objeto `company` (**barateado pelo merge — ver M8**), `signed_up_at`, getters, dedupe do `setUser` corrigido (hoje mudar só o telefone **não sai do navegador**), telefone sozinho identifica, e a regra de verbo explícita (`update…` mescla, `set…` substitui, com o método atual marcado legado) | `widget/store/modules/contacts.js`, `sdk/cookieHelpers.js`, `ContactIdentifyAction` | M | 1.23 | 🟡 | Mudar só o telefone e rechamar `setUser` **atualiza** o contato; `phone_number` sozinho identifica |
| **5.18** | T-I3.6 | T | `data-*` de **configuração** no snippet (nunca identidade) | snippet, `inbox.additional_attributes` | M | 3.01 | 🟡 | Configuração viaja por qualquer via; identidade e credencial, só pela API JS |
| **5.19** | BK-39 = T-I2.7, T-I3.7 | B | JWT como formato **adicional** (`sub`, `exp` obrigatório, atributos autenticados), HMAC mantido como legado; credencial por callback | serviço irmão de `widget/token_service.rb`, `contacts_controller.rb:64-70` | M | 4.15 | 🟡 | JWT válido identifica e marca `hmac_verified`; expirado degrada para **anônimo** (não erro); `identifier_hash` continua funcionando |
| **5.20** | T-I6.1–T-I6.4, BK-38 | T | Mensagem proativa em **uma** chamada (hoje são 3), com opção de não abrir conversa sem resposta e exigência de contato verificado; e o agent bot passa a poder **ler** a própria conversa | rota nova ⚪, `BOT_ACCESSIBLE_ENDPOINTS` | M | 4.15 | ⚪/🟡 | Um backend cliente envia uma requisição e o visitante identificado recebe no widget aberto, em tempo real |
| **5.21** | T-C9.1–T-C9.10, BK-40 | T | Ciclo fechado: `gclid` no contato com janela de 90 dias, negócio ganho → Ads/Meta/GA4, alerta de janela vencida, `ctwa_clid` promovido a atributo de conversa, config de tracking também na inbox de WhatsApp; e estatística por gatilho | clientes de API ⚪, jobs ⚪, migration ⚪ | **G** | 5.11, **verif. 1** | ⚪/🟡 | Venda fechada 30 dias depois aparece como conversão com valor real; conversa vinda de Click-to-WhatsApp é **atribuída ao anúncio**, não apenas aceita |

#### Onda 5 — A conversa *(6ª · 21 blocos · 66 pontos · 17,6% do esforço · os blocos são `2.xx`, mais 3.15, 4.09 e 4.10)*

> **Por que o acabamento visual desceu para a penúltima onda (D7).** Não é desprezo pelo visual — é
> ordem de valor. O widget de hoje **já conversa**: ele renderiza balões, tem composer, tem header e
> funciona em mobile. O que ele não faz é **abordar, capturar e dizer de onde veio o lead** — e é
> isso que o cliente compra. As Ondas 2, 3 e 4 constroem exatamente isso; esta aqui torna bonito e
> acessível o que já funciona. A auditoria chamou a inversão de **G-F** e mediu o custo: 107 pontos
> de trabalho entre a primeira entrega visível e a primeira que o cliente compra.
>
> **Três blocos chegaram de outras ondas**, e por dependência real, não por arrumação: **3.15** (o
> widget honrar `mask`/`validator`/`step`/`show_if`) e **4.10** (CSAT e cards) dependem de **2.01**,
> os 13 primitivos de `widget/ui/`; **4.09** (identidade de IA no header e na bolha) depende de
> **2.06**, o header. Enquanto 2.01 e 2.06 estiverem aqui, eles têm de estar aqui também. O pré-chat
> clássico continua funcionando como hoje até lá — o que a Onda 3 entrega de captura é o **fluxo
> conversacional novo** (4.03), que nasce em `widget/capture/` ⚪ e não passa por `PreChat/Form.vue`.

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **2.01** | W2.3 | W | Os 13 primitivos de `widget/ui/` (`aria-label` obrigatório por prop) | `widget/ui/` ⚪ | **G** | 1.01 | ⚪ | Lint: nenhum importa de `dashboard/`, nenhum tem cor literal |
| **2.02** | W2.4, W2.5 | W | `MessageRow` unifica agente/visitante; agrupamento vira **dados**, fora do store | `MessageRow.vue` ⚪, `useMessageGrouping.js` ⚪, `_conversation.scss:50-74,106-118` | M | 2.01 | ⚪+🟡 | `AgentMessage`+`UserMessage` < 150 linhas somados; nenhum seletor de irmão adjacente para agrupar |
| **2.03** | W2.6 | W | Balões: raio 20/6, `max-width` 82%, **sem sombra**, corpo 15/22, horário fora | `AgentMessageBubble.vue`, `UserMessageBubble.vue`, `_conversation.scss` | M | 2.02 | 🟢/🟡 | `boxShadow === 'none'`; contraste ≥ 4,5:1 nos dois temas, nas duas cores de teste |
| **2.04** | W2.7, W2.8 | W | Lista e scroll: fundo tokenizado, textura leve, separador em pill; **auto-scroll condicional** e botão "descer" com contador | `ConversationWrap.vue:63-173`, `Messages.vue:22`, `WScrollToBottom.vue` ⚪ | M | 2.03 | 🟢+⚪ | Mensagem chegando com o visitante 300 px acima **não** o arranca; textura < 30 KB |
| **2.05** | W2.9 | W | Composer: enviar **e** anexo simultâneos, enviar desabilitado com campo vazio, foco visível, `keydown` no campo | cascas em `ChatInputWrap.vue`/`ChatFooter.vue` (🔴) → `WComposer.vue` ⚪ | M | 2.01 | 🔴 → casca | Os 8 aceites da §C.9 do plano 22; as duas cascas < 60 linhas cada; nenhum `keypress` sobra |
| **2.06** | W2.10 | W | Header: 56/96, avatar 32 raio 6, ações 40/44, **`<h1>` real**, `<main>`, status com rótulo textual | `ChatHeader.vue`, `ChatHeaderExpanded.vue`, `HeaderActions.vue`, `ViewWithHeader.vue` (todos 🟢) | M | 2.01 | 🟢 | Exatamente 1 `h1`; nenhum `text-white`; alvos ≥ 44×44 em 375 px |
| **2.07** | W2.11, W2.14 | W | Estados de verdade: vazio, carregando (skeleton **só acima de 600 ms**), reconectando, offline, erro — e o watchdog que hoje roda a cada 15 s e **não faz nada** no widget | `WBanner.vue` ⚪, `WSkeleton.vue` ⚪, `Banner.vue`, `BaseActionCableConnector.js` | M | 2.01 | ⚪+🟡 | Rede cortada 10 s: nada nos primeiros 3 s, faixa depois, composer utilizável; micro-queda de 1,5 s não mostra nada |
| **2.08** | W2.12, W4.4 | W | Movimento completo + `prefers-reduced-motion` + `prefers-contrast` + `forced-colors` | `_tokens.scss`, `sdk.js`, componentes | P | 1.07, 2.03 | 🟢/⚪ | Com `reduce`, transição do painel e do launcher `none` ou ≤ 1 ms; em `forced-colors` os dois balões continuam distinguíveis |
| **2.09** | W2.13 | W | Mobile: **breakpoint único 768** (hoje 667, 667 e 668 coexistem), `100dvw/dvh` com fallback, `env(safe-area-inset-*)`, alvos 44×44 — **e devolver o zoom ao visitante**: `show.html.erb:6` traz hoje `maximum-scale=1, user-scalable=0` [M17], que é violação direta de **SC 1.4.4 (AA)** e torna impossível qualquer aceite de zoom | `sdk.js:147,242-290`, `IFrameHelper.js:341-347`, **`app/views/widgets/show.html.erb:6`** (🟢 0/0) | M | 2.01, **2.05** | 🟢 | 767 px fullscreen, 768 flutuante, sem ambiguidade; **0 de 5** alvos passam hoje, todos passam depois; **o `meta viewport` não contém `user-scalable=0` nem `maximum-scale`, e nenhum input do composer tem `font-size` < 16 px** (a razão histórica do `user-scalable=0` é o auto-zoom do iOS ao focar campo pequeno — a correção certa é o tamanho da fonte, feito em 2.05, não desligar o zoom de todo mundo) |
| **2.10** | W4.3 | W | Dark mode completo: default `auto`, classe no `<html>`, `color-scheme` no `:root`, `prefers-color-scheme` reativo — **realocado da Onda 4** (ver §3) | `sdk.js:74`, `App.vue:369-381`, `useDarkMode.js:20`, `_tokens.scss` | P | 1.01 | 🟢/🟡 | Sem `darkMode` configurado e SO escuro, o widget abre escuro; trocar o tema do SO reflete **sem remount** |
| **2.11** | W4.5 | W | `Esc` fecha e devolve o foco ao launcher; `inert` no fundo em mobile — **realocado da Onda 4** | `widget/bridge/` ⚪, `IFrameHelper.js`, `bubbleHelpers.js:74-83` | P | 1.09, 2.06 | 🟢/⚪ | `Esc` fecha; `document.activeElement` volta ao launcher; nenhum `tabindex` positivo |
| **2.12** | W2.15 | W | Render: uma instância de MarkdownIt por valor de `linkify` (hoje é uma por bolha, por render) + `v-memo` | `useMessageFormatter.js:19`, `MessageFormatter.js:109` | P | 2.02 | 🟡 | Spy no construtor: 1 chamada para 10 renders |
| **2.13** | W4.2 | W | Telemetria de erro do widget (hoje ~20 `catch { // Ignore }` e **zero** observabilidade) | `widget/bridge/` ⚪, GlitchTip | M | 1.09 | ⚪ | Erro forçado aparece no GlitchTip **com PII removida**; nada vaza para o `window.onerror` do site do cliente |
| **2.14** | W4.8 | W | Degradação do launcher: bundle falhou → canal de contato alternativo no snippet | `sdk.js`, snippet | P | 1.05 | 🟢 | Bloqueando o bundle no devtools, o link alternativo aparece |
| **2.15** | W4.7 | W | Idempotência de envio (chave por mensagem) | `widget/api/conversation.js` (🔴), backend | M | 2.05 | 🔴 | Retry de rede com a mesma chave não duplica mensagem |
| **2.16** | W4.1 | W | Fila offline de **intenções** (nunca de estados transitórios como "digitando") | `widget/offline/` ⚪ | M | 2.07 | ⚪ | 3 mensagens digitadas offline chegam **em ordem** na volta; nenhum evento de digitando em lote |
| **2.17** | W4.9 | W | i18n: `"mandatório"` → **"obrigatório"**, erro específico por campo, revisão de traduções mecânicas | `widget/i18n/locale/pt_BR.json:70,96` | P | — | 🟡 | `grep -rn "mandatório" widget/i18n/` vazio; nenhum rótulo acessível em inglês com interface em pt-BR |
| **2.18** | W4.10 | W | Peso, segunda rodada: chunk de vendor próprio (tira Amplitude e Sentry), FormKit só na rota do pré-chat, i18n sob demanda | `vite.shared.ts`, `entrypoints/widget.js:32-40`, `widget/i18n/index.js` | **G** | 0.5, 2.* | 🟡/🔴 | JS eager ≤ 150 KB gzip; `window.__SENTRY__` e `window.amplitude` **undefined** dentro do iframe |
| **3.15** | T2.10 | W | O widget honra `mask`/`validator`/`step`/`show_if` — **por delegação**, sem reescrever `PreChat/Form.vue` | casca em `PreChat/Form.vue` (🔴) → `widget/ui/WField.vue` ⚪ | **G** | 3.12, 2.01 | 🔴 → casca | Campo condicional só aparece quando a condição é satisfeita; erro específico por campo |
| **4.09** | W3.9 | W | Identidade de IA: rótulo persistente no header **e** na bolha, `aria-busy` no streaming, as 3 marcações no handoff e as 3 na volta | `ChatHeader.vue`, `message-types/`, `ConversationWrap.vue` | M | 2.06, 1.10 | 🟢/⚪ | Simulando handoff, as 3 aparecem; **nunca roxo como marcador** (colapsa para ΔE 1,8 em deuteranopia) |
| **4.10** | W3.10, W3.11 | W | CSAT redesenhado (nunca antes do encerramento; polegar para IA) e cards/conteúdo rico | `CustomerSatisfaction.vue`, `StarRating.vue`, `ChatCard.vue`, `template/*` | M | 2.01, 1.10 | 🟡 | `role="radiogroup"` com rótulo textual por opção; alvos 44×44; máximo 3 botões por card |

#### Onda 6 — IA e otimização *(7ª · 5 blocos · 25 pontos · 6,7% do esforço · blocos `6.xx`, todos novos)*

> **Esta onda não existia.** A auditoria mediu **zero ocorrências** de `guardrail`, `eval`, `citação
> de fonte`, `reranker` e `sitemap` nas 8.210 linhas dos cinco planos, enquanto dois blocos **G**
> construíam justamente o que o estudo declara commodity. A **D2** decidiu que a frente de IA entra
> **inteira**, e a **D4** trouxe de volta o facade e o teste A/B. Ela é a última porque **depende de
> tudo o que vem antes**: o guardrail precisa da IA na frente do visitante (4.03/4.09), o A/B precisa
> do lead incompleto (4.18) para ter denominador, e o facade só compensa **depois** do emagrecimento
> (1.08 + 2.18) — antes disso ele esconde peso em vez de eliminar peso.
>
> **A exceção que a engenharia registrou e que continua valendo:** este plano coloca IA na frente do
> visitante na Onda 3, e o guardrail está na Onda 6. **Enquanto 6.01 não existir, o widget de
> marketing sai com IA desligada** — é a condição escrita na §4, critério de pronto da Onda 3.

| Id | Origem | Fr. | Título | Arquivos | Esf. | Depende | Merge | Aceite |
|---|---|:---:|---|---|:---:|---|:---:|---|
| **6.01** | **novo — D2** (gap nº 1 da IA, no estudo) | B | **Guardrail de pré-envio.** Os asserts determinísticos que hoje rodam **depois** do episódio passam a rodar **antes de a resposta sair**. `Captain::EpisodeGateService` [M18] já implementa as três famílias (`contradicted_tool_findings`, `tool_error_findings`, `literal_repetition_findings`, `episode_gate_service.rb:15-17`) e é chamado de `episode_eval_job.rb:33`, no pós-fato. O bloco extrai os asserts para um serviço que recebe **a resposta candidata + as tool calls da janela** e devolve `passa` / `retém`, e o liga no caminho de envio. **Custo zero de LLM: é código verificando fato binário**, no padrão τ-bench/BFCL que o próprio arquivo declara | `enterprise/lib/captain/episode_gate_service.rb` (extração), serviço novo ⚪, caminho de envio da resposta | M | 4.03, 4.09 | ⚪/🟡 | Uma resposta que **nega** o que a ferramenta acabou de devolver **não é enviada** ao visitante — é retida e vira handoff, com o motivo registrado; o mesmo caso **hoje** é apenas anotado no eval depois, e o teste prova a diferença; o guardrail **não** chama LLM (asserção sobre a contagem de chamadas); falha do guardrail **nunca** derruba o atendimento (mesma regra do `rescue` de `episode_eval_job.rb:37-38`) — em erro, ele libera e registra; e a verificação roda em **dry run**, nunca contra IA de cliente |
| **6.02** | **novo — D2** | B+C | **Eval como produto**: o que hoje é infraestrutura interna (`Captain::ConversationEval`, os jobs de `enterprise/app/jobs/captain/`) vira coisa que o cliente vê e usa — conjunto de casos por assistente, execução sob demanda, veredito por caso, comparação entre duas versões do prompt, e histórico. É o que transforma "a IA melhorou?" de opinião em número | modelos/serviços existentes + tela nova ⚪ | **G** | 6.01 | ⚪/🟡 | O cliente roda o conjunto de casos **antes** de publicar uma mudança de prompt e vê quantos casos regrediram; dois vereditos do mesmo caso em versões diferentes ficam lado a lado; nenhum caso de cliente é executado contra IA de produção sem `dry_run`; e o custo de cada execução é exibido **antes** de rodar |
| **6.03** | **novo — D2** | B+W | **Citação de fonte.** Hoje a fonte já chega ao modelo, mas como **prosa dentro do prompt**: `search_knowledge_tool.rb:28-31` devolve `"#{text}\n(fonte: #{source})"` [M19]. Este bloco a promove a **metadado da mensagem** — qual documento, qual trecho — persistido e renderizado no widget como referência clicável quando houver URL. Reusa o registry de `content_type` do bloco 1.10: é um tipo novo, um arquivo e uma linha | `search_knowledge_tool.rb`, `content_attributes` da mensagem, `widget/message-types/` ⚪ | M | 1.10, 6.01 | 🟡/⚪ | Resposta baseada em documento mostra **de onde veio**, e clicar abre o documento quando ele é público; resposta sem base **não** inventa citação (é o modo de falha que importa); a citação sobrevive ao reload da conversa (está no banco, não na renderização); e o widget não cresce em peso *eager* por causa dela (o tipo é carregado com o registry, **A13**) |
| **6.04** | **novo — D4** (era a linha 28 da §8.1; MESA **M6**) | W | **Facade**: o app do widget deixa de carregar no primeiro paint e passa a carregar **no primeiro clique** do lançador. O lançador e o teaser continuam no host, leves, como já estão. **Só faz sentido depois de 1.08 e 2.18** — facade sobre bundle gordo troca "pesado sempre" por "lento quando abre", que é pior para quem abre | `sdk/`, `IFrameHelper.js:158-198` (🟢), `entrypoints/` | **G** | 1.08, 2.18, 4.06 | 🟢/⚪ | O iframe **não existe no DOM** antes do primeiro clique — verificado por `document.querySelectorAll('iframe')` na carga; do clique ao painel utilizável, **≤ 1 s** em 4G simulado; o teaser continua aparecendo **sem** carregar o app; e o visitante que clica duas vezes rápido não instancia dois iframes |
| **6.05** | **novo — D4** (D15 do estudo) | B+C | **Teste A/B de fluxo, versionado.** `flows` já tem a coluna `version` [M20 — `db/schema.rb:1206`], então não há migration para versionar a variante: falta **designar** o visitante a uma variante, **reter** essa designação pela sessão, e **ler** o resultado no relatório. Depende de **4.18**: sem lead incompleto não há denominador, e um A/B sem denominador mede a metade que converteu contra o nada | `flow.rb`, serviço de designação ⚪, relatório | M | **4.18**, 4.21, 6.02 | 🟡/⚪ | Duas variantes do mesmo fluxo recebem tráfego e o relatório mostra **conversão e abandono por etapa** nas duas; o mesmo visitante vê **sempre a mesma variante** na sessão; publicar uma variante nova **não invalida** o histórico da anterior; e o teste declara quando a diferença ainda não é distinguível do acaso, em vez de exibir o maior número |

### 2.3 Cobertura — nada ficou de fora

> **Ressalva desta seção, escrita depois da auditoria.** O título é forte demais para o que a seção
> mede. Ela confere as **277 tarefas das quatro frentes** contra os blocos — e isso bate. Ela **não**
> confere os planos contra o **estudo** (`plano/estudo-chat-web/`), que foi quem definiu o escopo:
> foi assim que 16 capacidades, 8 diferenciais e 4 decisões puderam sair sem decisão registrada. Essa
> segunda conferência agora existe, e o resultado dela está na **§8** — cada ausência virou linha,
> com recomendação e marca **[AGUARDA WALISSON]**. Enquanto não houver uma coluna "origem no estudo"
> na tabela mestra, leia esta seção como *"nada das frentes ficou de fora"*, não como *"nada ficou de
> fora"*.

> **Segunda ressalva, de 13/08/2026.** As decisões do produto acrescentaram **13 blocos** que **não
> vêm de nenhuma das 277 tarefas das frentes** — eles vêm do estudo, das auditorias e do dono do
> produto. Estão marcados **"novo — D*"** na coluna Origem, e é assim que se lê a diferença entre "o
> que as frentes planejaram" e "o que o produto decidiu". **Um bloco saiu**: 1.21, o backfill,
> cortado pela **D6**.

As quatro frentes somam **277 tarefas nomeadas** [MEDIDO — contagem de identificadores únicos:
58 `W*` + 56 `T*` + 39 `BK-*` + 80 `T-C*` + 44 `T-I*`], mais as **8 dependências `BE-*`** do plano 23
(que são pré-requisitos de backend, não tarefas de tela — e uma delas, **BE-2**, tinha sumido na
consolidação). A tabela mestra tem **121 blocos** [MEDIDO — soma reproduzida nesta task, §0.5],
distribuídos assim pela **nova** ordem de execução:

| Posição | Onda | Blocos | Pontos | % do esforço |
|---:|---|---:|---:|---:|
| 1ª | **0 — Terreno** | 11 | 24 | 6,4% |
| 2ª | **1 — Nada mentindo** | 23 | 50 | 13,3% |
| 3ª | **2 — Configuração** (`3.xx`) | 19 | 56 | 14,9% |
| 4ª | **3 — Captura** (`4.xx`) | 20 | 76 | 20,3% |
| 5ª | **4 — Atribuição** (`5.xx`) | 22 | 78 | 20,8% |
| 6ª | **5 — A conversa** (`2.xx` + 3.15/4.09/4.10) | 21 | 66 | 17,6% |
| 7ª | **6 — IA e otimização** (`6.xx`) | 5 | 25 | 6,7% |
| | **Total** | **121** | **375** | **100%** |

A conta contra a revisão anterior: **109 − 1 (1.21, cortada por D6) + 13 novos = 121**. Os treze
novos são **0.11** (D14), **3.20** (D1), **4.19**, **4.20**, **4.21** (D1), **4.22** (D10), **5.22**
(D8), **5.23** (D9), **6.01**, **6.02**, **6.03** (D2), **6.04** e **6.05** (D4). Cada bloco cita os
identificadores nativos que absorve. Conferência por frente:

| Frente | Tarefas no plano | Onde estão na tabela mestra |
|---|---|---|
| **22 — widget** | W0.1–W0.6, W1.1–W1.16, W2.1–W2.15, W3.1–W3.11, W4.1–W4.10 (58) | 0.1–0.5; 1.01–1.10; 2.01–2.18; 3.05, 3.15, 3.17; 4.03, 4.06, 4.08–4.11. **W3.1 foi absorvida por 3.01** (ver arbitragem **A1**: a coluna nova não acontece) |
| **23 — config** | T0.1–T0.10, T1.1–T1.16, T2.1–T2.11, T3.1–T3.9, T4.1–T4.10 (56) | 0.2, 0.6–0.9; 1.17; 3.06–3.14, 3.16; 4.04, 4.05, 4.07; 5.06, 5.14. **T1.4 (backfill de perfil) foi eliminada** (arbitragem **A4**) |
| **24 — backend** | BK-00–BK-09, BK-10–BK-19, BK-20–BK-27, BK-30–BK-40 (39) | 0.6, 0.10; 1.11–1.16, 1.18–1.20; 3.01–3.04, 3.12; 4.01, 4.02, 4.12, 4.15–4.17; 5.01–5.05, 5.11, 5.14, 5.19, 5.21. **BK-13 (backfill de origem) foi cortada** pela decisão **D6** — ver **A16** |
| **25 — tracking/integração** | C0–C9 (80) + I1–I6 (44) | 1.09, 1.13, 1.14, 1.17, 1.19, 1.22, 1.23; 4.13, 4.14; 5.01–5.21. **T-C0.4 (backfill) foi cortada** pela **D6** |

Quatro tarefas mudaram de estado, e só quatro: **W3.1** (absorvida por 3.01), **T1.4** (eliminada por
arbitragem, **A4**), **T-C1.1** (mantida no destino, com o escopo corrigido — §5, **A1**) e
**BK-13 = T-C0.4** (o backfill de origem, **cortada por decisão do produto**, **D6** e **A16**). As
três primeiras são arbitragem de engenharia; a quarta é decisão do dono — e a diferença importa,
porque arbitragem se reabre com medição nova e decisão de produto não.

#### As oito dependências `BE-*` do plano 23 — onde cada uma vive

Esta tabela não existia, e é por isso que **BE-2 sumiu**: três auditorias independentes acharam o
mesmo buraco por três caminhos diferentes, e o `grep -o "BE-[0-9]"` deste documento devolvia apenas
BE-1, BE-4, BE-6, BE-7 e BE-8. Agora as oito estão rastreadas, e nenhuma delas é uma tela: são o que
**precisa existir no backend** para que a tela tenha o que salvar.

| Dep. | O que é | Bloco(s) | Estado |
|---|---|---|---|
| **BE-1** | **Um** ponto de extensão declarado no strong params da inbox, para toda a configuração nova | **3.01** | ✅ coberto — e por **A1** ele são quatro chaves de topo declaradas numa **única** edição de `inboxes_controller.rb:217` (🔴) |
| **BE-2** | Configuração de **apresentação** (tema, posição, offsets, formato e texto do lançador, esconder bolha, estilo do painel) — hoje presa ao snippet e ao `localStorage` do admin (**D1**) | **3.01** (a chave) + **3.18** (schema, precedência, saída do `localStorage`) + **3.19** (o ícone) + **3.09** (a tela) | ✅ **recuperado nesta revisão** — era o bloqueador B2 |
| **BE-3** | Perfil da inbox (`support`/`marketing`) — a metade "backfill de todas as existentes" foi **eliminada** por **A4** | **3.01** (a chave, com validação de inclusão) + **3.03** (`WidgetProfile.resolve` e seed só na criação) + **3.07** (a escolha na tela e no wizard) | ✅ coberto, com a eliminação declarada: `nil` é lido como `support`, que é o comportamento de hoje |
| **BE-4** | Gatilhos por inbox + segmentação + config do teaser | **3.02** (schema) + **4.04** (tela) + **4.06** (teaser no SDK) | ✅ coberto — por **A5**, sem endpoint filtrado na v1 |
| **BE-5** | **Lead incompleto**: persistir resposta parcial antes de a conversa existir | **4.18** | ✅ **aprovado em 13/08/2026 pela decisão D3** — entra na Onda 3 (captura), esforço M–G |
| **BE-6** | Ampliar `EDITABLE_ATTRS` do pré-chat | **3.12** | ✅ coberto — `web_widget.rb` tem 0/0 dos dois lados, é a alteração de backend mais barata do plano |
| **BE-7** | Derivação canônica dos 7 tokens de marca **no servidor** | **1.02**, com o medidor da tela (**3.08**) obrigado a bater com ela | ✅ coberto |
| **BE-8** | Configuração de tracking + segredos + log de eventos | **5.01** (config pública) + **5.02** (segredos) + **5.14** (log) + **5.06** (tela) | ✅ coberto |

### 2.4 O caminho crítico

A cadeia mais longa de dependências duras — se qualquer elo atrasar, tudo o que vem depois atrasa.
**Redesenhada em 13/08/2026**, porque a D7 mudou a ordem e a D1 acrescentou um elo:

```
0.1 baseline + 0.11 fixture ─► 0.2 MERGE v4.16.2 ─► 0.3 build ─► 1.01 tokens ─► 1.02 no servidor
      │                                                                                │
      └───────────────────────────────────────────────────────► 1.09 BRIDGE            │
                                                                     │                 ▼
                                                 3.01 lar da config ◄┘        1.03/1.04/1.05 cor certa
                                                         │                             │
                            ┌────────────────────────────┼─────────────────────────┐   │
                            ▼                            ▼                         ▼   ▼
                  3.02 schema gatilhos        3.03 resolve perfil        3.18 aparência (BE-2)
                            │                            │                         │
                            ▼                            └──► 3.04 entrega ao widget ─► 3.05 flags
                  3.20 ABORDAGEM 3 níveis (D1)                          │
                            │                                           ▼
                            └──────────► 4.04 tela de abordagem ──► 4.06 TEASER
                                                                        │
                                            ┌───────────────────────────┼──────────────┐
                                            ▼                           ▼              ▼
                                   4.19 degradação (D1)         4.20 auto-open   4.22 campanhas
                                            │                                       legadas (D10)
                                            ▼
                       5.01 config pública ─► 5.03/5.04 eventos ─► 5.10 tags ─► 5.11 CAPI
                                            └─► 4.21 instrumentação dos 3 níveis (D1)
```

**A trilha da IA (Onda 6) tem caminho próprio e curto**, e é bom que tenha: `4.03/4.09 → 6.01
guardrail → 6.02 eval → 6.03 citação`, com `6.04 facade` pendurado em `1.08 + 2.18` (o
emagrecimento) e `6.05 A/B` pendurado em `4.18` (o lead incompleto, que é o denominador).

**Os cinco elos que travam mais coisa se atrasarem:**

| Elo | Trava | Por quê |
|---|---|---|
| **0.2 — o merge** | **tudo** | 113 arquivos do widget mudam. Redesenhar antes é resolver dois problemas embaralhados, e resolver o segundo por cima de um primeiro que ainda vai chegar |
| **1.09 — o bridge** | 1.23, 2.11, 2.13, 5.04, 5.16 e todo evento novo das duas frentes | É o mesmo trabalho com três nomes (W2.1 = T-I1.5 = T-C3.8). Cada evento acrescentado à cadeia de 16 `else if` é conflito garantido no merge seguinte |
| **1.02 — tokens no servidor** | 1.03, 1.04, 1.05, 3.08, 3.10 e o preview | É a fonte única da cor. Sem ela, o launcher e o header voltam a discordar — que é exatamente o bug que estamos consertando |
| **3.01 — o lar da config** | 3.02–3.04, 3.06, **3.18, 3.19, 3.20**, 4.04, 5.01, 5.18 e as quatro telas | Enquanto não existir onde gravar, nenhuma tela tem o que salvar. **É o bloco de maior alavancagem do plano inteiro**: a quarta chave (`widget_appearance`) destrava a Tela 1, o ícone do lançador, a abordagem em três níveis (3.20, que mora dentro de `widget_triggers`) e o marco comercial antecipado — e as quatro chaves cabem na **mesma** edição do arquivo 🔴 |
| **4.06 — o teaser** | 4.19, 4.20, 4.21, 4.22 e o marco comercial inteiro | Depois da **D1**, ele deixou de ser "uma peça de conversão" e virou **a superfície da abordagem**: os três níveis, a degradação e a instrumentação pendem dele. É o bloco **G** de maior risco do plano (vive no site do cliente, fora do iframe, **R13**) e o maior consumidor de bytes do `sdk.js` (**A13**) |
| **0.10 — chaves de criptografia** | 5.02, 5.11, 5.21 (todo o server-side) | Aceitar um access token da Meta sem `ACTIVE_RECORD_ENCRYPTION_*` é gravá-lo **em claro** no banco. É infra, não código — e por isso pode (e deve) começar no primeiro dia |

### 2.5 O que pode correr em paralelo com segurança

| Trilhas simultâneas | Por que não colidem |
|---|---|
| **0.1 + 0.4 + 0.6 + 0.10** (baseline, nginx, spec de paridade, chaves) | Nenhuma toca código de aplicação; 0.1 **precisa** terminar antes de 0.2 |
| Depois de 0.2: **widget (1.01–1.08)** ‖ **bridge (1.09–1.10)** ‖ **backend (1.11–1.16)** ‖ **origem (1.18–1.22)** | Arquivos disjuntos: SCSS e componentes × `widget/bridge/` ⚪ × controllers Ruby × serviços novos ⚪ |
| **Onda 2 (widget)** ‖ **3.01–3.04 (backend da config)** ‖ **4.13/4.14 (webhooks)** | O backend da config não toca componente do widget; webhooks não tocam front nenhum |
| **Onda 3 telas** ‖ **Onda 2 acabamento (2.12–2.18)** | Superfícies diferentes (dashboard × iframe) |
| **3.14 pré-chat (tela)** ‖ **4.04 gatilhos (tela)** | Os planos 23 §C.1.1 confirma: não se tocam |
| **5.15 contrato público** ‖ qualquer coisa | É documentação; começa cedo e amadurece junto |

**O que NUNCA deve correr em paralelo, e é o erro mais provável:**

1. **Redesenho visual e merge do upstream** — 0.2 é bloqueante, sem exceção.
2. **Duas pessoas mexendo em `Settings.vue`** — é 🔴 dos dois lados (+242/−24 upstream, +99/−18 fork).
   O plano inteiro lhe reserva **quatro linhas** (3.09). Qualquer outra edição ali é sinal de que
   alguém está escrevendo a tela por dentro em vez de em `inbox/widget/` ⚪.
3. **Duas frentes adicionando evento** antes de 1.09 estar pronto.
4. **Tarefa de build antes de 0.3** — o upstream quebrou `vite.config.ts` em quatro arquivos; fazer
   antes é escrever duas vezes.
5. **Duas frentes mexendo no `sdk.js` na Onda 3.** Depois da D1 são quatro blocos disputando o mesmo
   arquivo (4.06, 4.19, 4.20, 4.21) — e é o arquivo com teto de peso (**A13**). Eles são uma frente
   só, num worktree só (**§11.2**), não quatro tarefas paralelas.

### 2.6 A curva de valor — quando o cliente vê o que ele compra *(D7)*

**O problema que esta seção resolve.** A auditoria mediu a inversão e lhe deu nome (**G-F**): na
ordem anterior, o primeiro marco que muda a conversa comercial chegava a **56,0%** do esforço, e a
atribuição — que o estudo chamou de *"alavanca de maior valor por esforço"* — a **76,8%**. São 107
pontos de trabalho entre a primeira entrega visível e a primeira que o cliente compra. É onde o
patrocínio esfria.

**A conta está aberta.** Escala declarada na §0.5 (**P=1 · M=3 · G=8**; híbridos **P/M=2** e
**M–G=5**), reproduzida nesta task sobre os 121 blocos da §2.2.

#### 2.6.1 O esforço por onda, na nova ordem

| # | Onda | Blocos | Pontos | % | Acumulado | O que o cliente pode ver e comprar ao fim dela |
|---:|---|---:|---:|---:|---:|---|
| 1ª | **0 — Terreno** | 11 | 24 | 6,4% | **6,4%** | Nada. É a onda que não se mostra a ninguém — e é a que torna revisável um merge de 113 arquivos |
| 2ª | **1 — Nada mentindo** | 23 | 50 | 13,3% | **19,7%** | **Primeira coisa demonstrável**: a cor da marca dele em todo o widget (hoje o header é verde ChatSPX), o atributo que o site manda aparecendo no painel (B6), e **"toda conversa nova nasce sabendo de onde veio"** com o relatório de 1.22 |
| 3ª | **2 — Configuração** | 19 | 56 | 14,9% | **34,7%** | Ele **mexe sozinho**: aparência, tema, posição, ícone do lançador, perfil da inbox, pré-chat. Antes disso, tudo é `rails console` — aceitável num piloto, insustentável na frota |
| 4ª | **3 — Captura** | 20 | 76 | 20,3% | **54,9%** | **O widget trabalha**: aborda nos três níveis, degrada por familiaridade, captura em fluxo conversacional e **registra o lead que não terminou** |
| 5ª | **4 — Atribuição** | 22 | 78 | 20,8% | **75,7%** | **O ciclo fecha**: Pixel, GA4, Ads, server-side, dedup, consentimento, diagnóstico — e a instalação em WordPress/Wix/GTM que hoje não existe |
| 6ª | **5 — A conversa** | 21 | 66 | 17,6% | **93,3%** | O acabamento: balões, scroll, composer, movimento, dark, mobile, peso. Melhora o que **já funciona** |
| 7ª | **6 — IA e otimização** | 5 | 25 | 6,7% | **100%** | Guardrail, eval como produto, citação de fonte, facade e A/B |

#### 2.6.2 O marco comercial (MC1), bloco a bloco

O marco **não é o fim de uma onda** — é um corte transversal, e é assim que ele tem de ser lido. As
Ondas 2, 3 e 4 são ordenadas **por dentro** para que os blocos do MC1 venham primeiro; o que sobra
delas é entrega de conforto, não de argumento comercial.

> **MC1 — "o widget aborda, captura o lead e diz de onde ele veio."**
> É a frase que o comercial pode dizer, com demonstração ao vivo, sem ressalva.

| Origem | Blocos incluídos | Pontos |
|---|---|---:|
| **Onda 0** | 0.1 – 0.11 (inteira) | 24 |
| **Onda 1** | 1.01 – 1.23 + 5.07 (inteira) | 50 |
| **Onda 2** — só o que a captura lê | 3.01, 3.02, 3.03, 3.04, 3.05, 3.06, 3.07, 3.18, **3.20** | 23 |
| **Onda 3** — só a abordagem | 4.04, 4.05, 4.06, **4.19**, **4.20**, **4.21**, **4.22** | 29 |
| **Onda 4** — só a atribuição client-side | 5.01, 5.03, 5.04, 5.05, 5.08, 5.09, 5.10 | 19 |
| | **57 blocos** | **145** |

**145 de 375 pontos = 38,7% do esforço** [MEDIDO — soma reproduzida nesta task], contra os **76,8%**
que a auditoria mediu na ordem anterior. **A distância entre a primeira entrega visível e a primeira
que o cliente compra caiu de 57,1 pontos percentuais para 19,0.**

**O grafo fecha.** Conferi bloco a bloco: toda dependência declarada na §2.2 de um bloco do MC1 é
outro bloco do MC1. Duas mereciam nota: **3.04 exige 3.18** (a entrega das quatro chaves ao widget
passa pelo schema da aparência), por isso 3.18 está na lista mesmo sem a Tela 1; e **4.21 exige 5.03
e 5.04**, por isso os eventos entram antes das tags. Nenhum bloco do MC1 depende de bloco fora dele.

**O alvo era ~35%, e a conta honesta deu 38,7%. Fica 38,7%.** Chegar aos 35% exigiria tirar do
caminho **1.06** (a11y mínima), **1.07** (typing em CSS) e **1.08** (peso do CSS) — dá exatamente
**138 pontos, 36,8%** — e ainda assim não chega a 35 sem partir mais. Não fiz, e o motivo é de
produto, não de aritmética: os três estão na onda cuja bandeira é *"o produto para de mentir"*, ela é
vendida como bloco, e a11y é o item que um cliente enterprise audita. **Trocar 3,7 pontos
percentuais de cronograma por uma onda partida ao meio é mau negócio** — mas a alternativa está
declarada aqui, com o número, para quem quiser decidir diferente.

#### 2.6.3 O que a reordenação **não** muda

Registrado porque reordenar cronograma é onde se perde rigor sem perceber:

1. **Nenhuma dependência foi invertida.** A ordem lógica que a auditoria 31 aprovou (zero ciclos,
   zero dependências para frente) continua valendo — o que mudou foi **quando** blocos independentes
   executam. Os três que trocaram de onda (3.15, 4.09, 4.10) foram **para depois** dos blocos de que
   dependem, nunca para antes.
2. **Nenhum bloco foi cortado para melhorar o percentual.** O único bloco cortado é **1.21**, e ele
   saiu por decisão de produto (**D6**), não para embelezar a curva — aliás, cortá-lo **piora** o
   percentual do MC1 em 0,3 pp, porque diminui o denominador menos do que o numerador.
3. **A Onda 0 continua inteira e primeiro.** A auditoria estratégica procurou o que criticar ali e
   escreveu que não achou. Continua sem achar.
4. **O acabamento visual não foi cancelado.** Ele é 17,6% do esforço e continua no plano inteiro, com
   os mesmos 21 blocos e os mesmos aceites. Ele mudou de lugar na fila.

---

## 3. Ordem de ataque recomendada, e por quê

**1. O baseline antes do merge, e o merge antes de tudo.** Não existe **um** teste de render de
componente do widget hoje — dos 33 specs, nenhum monta componente para verificar o que aparece na
tela. Um redesenho total sobre essa base é aposta, não engenharia. Os 16 snapshots (0.1) são o que
torna um merge de 113 arquivos revisável: eles **vão** mudar; o que não pode é mudar sem alguém
olhar.

**2. Depois, o que está errado e não depende de decisão nenhuma.** Os seis defeitos verificados não
são questão de escopo — estão errados hoje, em produção, para todos os clientes. Cinco são **P**.
Fazê-los primeiro tem três efeitos: o produto para de mentir, a equipe ganha ritmo em cima de tarefas
pequenas e bem definidas, e cada correção vira teste que impede a volta do defeito.

**3. Dentro dessa leva, B6 tem precedência comercial sobre os outros cinco.** Enquanto um atributo
que o site envia continuar sendo gravado, entrando no prompt da IA e sumindo do painel, **toda**
melhoria de integração deste plano chega ao cliente como "não funcionou" — com o site jurando que
mandou e o atendente jurando que não vê, os dois certos. E o backend sozinho (1.16) já resolve a
maior parte do sintoma: com a definição provisionada, o atributo aparece (porque o painel itera
definições) e vira filtrável. A seção separada e o selo (1.17) são refinamento.

**4. C0 entra junto, porque não disputa recurso com nada — e agora sem a perna que nunca ia andar.**
O parser de origem não toca o widget, não toca o SDK, não precisa de credencial de terceiro e mora em
pasta nova — risco de merge zero. Isso continua verdadeiro. O que **não** era verdadeiro é a premissa
que sustentava a trilha inteira: *"a origem já está no banco, crua, e ninguém parseia"*. Medi [M12]:
**0 conversas com `referer` preenchido em 3.180**, e `conversation.rb:536-539` **anula o valor na
escrita** quando a URL não valida. Depois da **D6**, a leitura é esta:

- **1.20 (parar de destruir o dado) é a primeira tarefa da trilha e a mais valiosa dela.** Não "anda
  junto" de 1.19: bloqueia. E como não há backfill atrás, ela deixou de ser melhoria de qualidade e
  passou a ser **a tarefa que faz o dado existir**. Ganhou cinco asserções de aceite por isso.
- **1.19 é prospectivo, e só isso — por decisão, não por pendência.** Ele entrega origem para as
  conversas que nascerem depois dele. Antes desta revisão isso era uma limitação constrangida; agora
  é o escopo declarado, e some com ela a nota de rodapé eterna sobre o que faríamos "se V3 devolvesse
  volume".
- **1.21 (backfill) foi cortado.** Ele lia o que está no banco; o que foi anulado não está lá. Com
  ele saíram o portão **V3** e a dependência de uma medição na frota que ninguém tinha agendado — e
  que teria de ser refeita **depois** de 1.20 para significar alguma coisa. Ver **A16**.

A frase que vai ao cliente: *"a partir da entrada em produção, toda conversa nasce sabendo de onde
veio"*. A que não vai, e agora não pode ir por engano porque nenhuma tarefa a promete:
*"respondemos a base inteira"*.

**5. As refatorações de merge vêm antes do redesenho dos mesmos arquivos, não depois.** O bridge
(1.09) e o registry de `content_type` (1.10) são invisíveis para o usuário e chatos de justificar —
e são exatamente o que impede que a Onda 2 e a Onda 4 conflitem em todo merge do upstream. Feitos
depois, cada evento novo e cada `content_type` novo terá sido escrito duas vezes: uma na escada de
`else if`, outra no mapa.

**6. A cor (1.02–1.05) vem cedo porque é o defeito mais visível e a fundação do resto.** Ela paga
B1 e B2 de uma vez, destrava o medidor de contraste da tela de aparência (3.08) e o preview honesto
(3.10), e é o teste que define o projeto: mesma inbox, duas cores, e header, botão de enviar, balão
do visitante e launcher com o **mesmo** `background-color`. Esse teste **falha hoje**.

**7. Configuração antes de captura, e as duas antes do acabamento visual (D7).** As telas gravam o
que o widget de captura vai ler: fazer o teaser antes da tela de abordagem significa configurar por
`rails console` — aceitável num piloto de uma conta, insustentável na frota. E o acabamento da
conversa vem **depois** das duas, porque o widget de hoje já conversa: balão, composer, header e
mobile existem e funcionam. O que não existe é abordar, capturar e atribuir. A ordem anterior
construía o bonito antes do vendável e cobrava 76,8% do esforço por isso (§2.6).

**8. O acabamento visual é a penúltima onda, e continua inteiro.** Ele é 17,6% do esforço, 21 blocos,
os mesmos aceites. É também a única onda cortável sem quebrar as outras — e é justamente por isso que
ela é a que espera. Três blocos de outras ondas foram junto (3.15, 4.09, 4.10), porque dependem de
2.01 e 2.06; qualquer tentativa de trazê-los para a frente traz os primitivos e o header junto, e aí
não se antecipou nada, só se mudou o nome da onda.

**9. Atribuição na quinta posição, e dentro dela C0 primeiro (já feito na Onda 1) e a ponte de tags
depois do consentimento.** Construir a ponte de tags sem o gate de consentimento é reabrir o mesmo
arquivo. E o modo "sem PII" (5.12) deve ser construído **antes** do modo com PII, independentemente
da resposta do jurídico: ele entrega valor sozinho e transforma a resposta do DPA de "bloqueio de
projeto" em "chave que liga mais matching".

**9b. IA por último, e a condição que isso impõe.** A Onda 6 é a última porque depende de tudo — o
guardrail precisa da IA na frente do visitante, o A/B precisa do lead incompleto como denominador, e
o facade só compensa depois do emagrecimento. Mas a Onda 3 coloca IA na frente do visitante **três
ondas antes** de o guardrail existir, e isso não pode passar em silêncio: **enquanto 6.01 não
estiver em produção, o perfil de marketing sai com IA desligada.** É a condição escrita no critério
de pronto da Onda 3, e é a única forma honesta de manter a IA na última onda sem aumentar a
superfície de erro exatamente onde ela custa mais caro — na página do cliente, com a marca do
cliente.

**10. Duas realocações declaradas em relação aos planos das frentes.** Dark mode completo (W4.3) e
`Esc`/devolução de foco (W4.5) saem da Onda 4 do plano 22 e entram na onda "A conversa" (2.10 e
2.11). Razão: os dois são **P**, tocam exatamente os arquivos que essa onda já está abrindo
(`_tokens.scss`, `App.vue`, `sdk.js`, o bridge), e adiá-los significa reabrir os mesmos arquivos duas
vezes. *(O `Esc` continua sendo aceite do auto-open — bloco 4.20 — mesmo com 2.11 vindo depois: o
painel aberto por gatilho precisa fechar com `Esc` desde o primeiro dia, e é a única parte de 2.11
que 4.20 antecipa, com o teste dela junto.)*

**11. E uma terceira realocação, decidida nesta revisão: 5.07 (propagação do SDK) sobe da Onda 5 para
a Onda 1.** O motivo é aritmético, não estético. O `sdk.js` é servido com
`cache-control: public, max-age=31556952` — **um ano, sem `ETag` e sem `Last-Modified`**
(`config/environments/production.rb:24-26`). Sem validador, o navegador que já baixou o arquivo **não
volta a pedi-lo**. E **nove blocos mudam o `sdk.js` antes da Onda 5**: 1.03, 1.05, 1.23, 2.08, 2.09,
2.14, **4.06 (o teaser)**, 5.08 e 5.10. Consequência: a peça de conversão do plano pode não chegar a
um visitante recorrente por até **12 meses** depois do deploy, com sintoma invisível — funciona no
navegador de quem testa, que limpou o cache — e diagnóstico caro ("o teaser não aparece no site do
cliente X"). A correção é código nosso, entra pelo deploy normal e não depende do nginx de VM
nenhuma.

**12. E a reordenação de 13/08/2026 (D7), que é a maior mudança desta revisão.** As ondas foram
reordenadas para `0 → 1 → configuração → captura → atribuição → a conversa → IA`. Três blocos
mudaram de onda por dependência real (3.15, 4.09 e 4.10, todos para "A conversa", porque dependem de
2.01/2.06); **nenhum outro se moveu, nenhum foi renumerado e nenhum foi cortado por causa da ordem**.
O efeito está medido na §2.6: o marco comercial cai de **76,8% para 38,7%** do esforço. A ordem
lógica que a auditoria aprovou continua intacta — o que mudou foi o calendário, não o grafo.

---

## 4. Critério de pronto por onda

Cada item passa ou falha. Nada aqui é "está bonito".

> **Regra que passa a valer sobre esta seção inteira, escrita depois da auditoria.** Nove dos treze
> critérios conferidos estavam errados, eram inatingíveis pelo escopo do bloco, ou não tinham
> mecanismo que os sustentasse — o que faz uma onda **encerrar verde com o defeito vivo**, que é pior
> que encerrar vermelha. Três consequências, e elas valem para todo critério novo que alguém
> acrescentar aqui:
>
> 1. **Nenhum aceite numérico se negocia na revisão.** Se um número não é atingível pelo escopo do
>    bloco, o número está errado e se corrige **aqui**, antes de a onda começar — nunca "liberado
>    porque é só um número". O primeiro aceite numérico liberado por cortesia torna os outros
>    quarenta negociáveis.
> 2. **Todo aceite precisa de um mecanismo que o execute.** "Nenhum segredo aceito ali" não é
>    critério enquanto não houver validação que recuse; é afirmação. Onde o mecanismo mora em outro
>    bloco, o critério cita o bloco.
> 3. **Todo aceite comparando número decimal usa tolerância declarada** (`toBeCloseTo(x, 2)`), nunca
>    igualdade exata — foi assim que dois contrastes errados quase viraram meio dia de caça a um bug
>    que não existia.

### Onda 0 — Terreno *(1ª)*

1. `pnpm test` verde depois do merge, e os 16 snapshots **revisados um a um** (não apenas verdes).
2. `bin/vite build` gera o mesmo conjunto de entradas; `public/packs/js/sdk.js` sai em IIFE.
3. `curl -skI -H "Accept-Encoding: gzip, br" <asset>` devolve `content-encoding` **nas quatro VMs**.
4. O gate de peso reporta o **grafo** (~575 KiB hoje), não o chunk de entrada (76,53 kB), e falha se
   `leaflet-*.js` reaparecer nos imports estáticos.
   - **4b — o gate mede o `sdk.js` e publica o delta no PR**: falha acima de **15 KB gzip** ou de
     **40 KB crus**, partindo da linha de base medida de **29.014 B / 9.595 B gzip** [M15, remedido 17/08 — ver §12]. É o único
     teto do plano que protege 100% dos visitantes de todos os sites de todos os clientes — e sem ele
     oito blocos engordam o arquivo sem que um único aceite fique vermelho (ver **A13**).
   - **4c — o harness roda numa máquina limpa**: depois de `pnpm install`,
     `pnpm exec playwright test --project=widget` executa — ou seja, `@playwright/test` está no
     `package.json` [M13] — **e as suítes `copilot` e `resolve-gate`, que já usam o mesmo config,
     continuam sendo descobertas e passando**.
   - **4d — o fixture anti-erro está ativo** (D14, bloco 0.11): um teste que carrega uma página com
     `console.error` injetado **falha**, nomeando a mensagem; um `fetch` que devolve 500 **falha**,
     nomeando método e URL; `grep -rn "from '@playwright/test'" spec/e2e/widget/` → **vazio** (todo
     E2E importa do fixture); e cada entrada de `IGNORAR` tem comentário com a razão. **Sem isto, os
     16 snapshots da 0.1 fotografam o defeito e o aprovam** — um baseline capturado por um harness
     que engole erro de console é um baseline que dá falso verde no dia 1.
5. Acrescentar uma chave de config em só um dos dois montadores **quebra a suíte**, com mensagem que
   nomeia a chave e o arquivo esquecido.
6. `grep -rn "WidgetBuilder" app/javascript` → vazio.
7. `Chatwoot.encryption_configured?` → `true` em todas as VMs.

### Onda 1 — Nada mentindo *(2ª)*

1. Uma inbox com `widget_color = #009CE0` e outra com `#2DC46F` renderizam **header, botão de enviar,
   balão do visitante e launcher** com o `background-color` da respectiva inbox — em light e dark,
   desktop e mobile, **e em `:hover` no launcher**.
2. Contraste do texto sobre o balão do visitante ≥ 4,5:1 nas duas cores; link na bolha do agente ≥
   4,5:1 (hoje **2,27:1** — valor exato 2,2734, o mesmo par que aparece na §1; não são dois números
   distintos). Os pares de referência do servidor (1.02) são **9,24:1** para `#2DC46F` sobre preto e
   **6,83:1** para `#009CE0` sobre preto (exatos: 9,2371 e 6,8318), sempre com `toBeCloseTo(x, 2)`.
3. `grep -rn "n-brand\|getContrastingTextColor\|--widget-color" app/javascript/widget/ app/javascript/sdk/ app/javascript/shared/` → vazio.
   **Os três diretórios**: `shared/` guarda 7 `n-brand` e 6 `getContrastingTextColor` [M14] — CSAT,
   chips de resposta rápida, botões de card e o botão genérico, todos dentro do widget, na tela do
   visitante. Sem `shared/` no grep, a onda cuja bandeira é *"o produto para de mentir"* encerra
   verde com o defeito vivo nas quatro superfícies mais visíveis depois do balão.
4. CSS do widget ≤ **80 KB crus**; **zero `@font-face` no CSS do widget** (hoje 7 [M16]); nenhuma
   requisição a `typing.gif`; `typeof window.L === 'undefined'` dentro do iframe.
5. `document.documentElement.lang` não vazio; exatamente um `[role="log"]`; todo `<button>` com nome
   acessível **em pt-BR**.
6. `App.vue` abaixo de **310** linhas (386 − 88 extraídas + ~5 de chamada = 303; o `< 250` anterior
   não era atingível pelo escopo do bloco 1.09 e reprovaria uma tarefa correta); `postMessage` de
   origem estranha é ignorado nos **dois** lados.
7. Com `hmac_mandatory` ligado: `PATCH /widget/contact` com `{email}` e `set_user` com
   `{email, custom_attributes}` sem `identifier` **não alteram** o contato — **e** o teste de
   não-regressão de quem não usa HMAC passa antes do merge.
8. Endpoint que devolve 500 registra 5 tentativas com o **mesmo** `X-Chatwoot-Delivery`, e o efeito
   colateral roda **uma** vez.
9. `setCustomAttributes({carrinho_valor: 4200})` sem definição prévia: o valor aparece no painel **na
   mesma sessão**, em seção própria, com selo de origem — validado em navegador real, **light e dark**.
10. **Uma conversa criada depois de 1.19** com `?utm_source=google&gclid=X` mostra a origem no painel
    **na mesma sessão** e é encontrável por filtro; uma URL com espaço não escapado **preserva** a
    origem (é 1.20 funcionando, e as cinco asserções dele passam); uma conversa vinda de
    `chatgpt.com` aparece como origem de **IA generativa**; uma conversa sem origem aparece como
    **"origem não disponível"**, **nunca** como "origem direta". *Sobre conversas antigas:* **não há
    critério, porque não há tarefa** — a **D6** cortou o backfill e o relatório de 1.22 rotula o
    período anterior como *"antes da medição"*. Isso é escopo declarado, não lacuna.
11. Os sete métodos de dados devolvem `Promise` e falham ruidosamente; chamada antes do boot é
    aplicada depois, com o mesmo efeito.
12. **Uma versão nova do `sdk.js` chega em minutos a um navegador que já tinha a antiga** (5.07,
    realocado para esta onda): a resposta traz `ETag` ou `Last-Modified`, e o `304` acontece. Sem
    isso, tudo que as Ondas 1 a 4 mudam no launcher e no teaser fica preso no cache do visitante.

### Onda 2 — Configuração *(3ª · os blocos são `3.xx`)*

1. `PATCH inbox` com `widget_profile: "marketing"` persiste e volta no `GET`; valor inválido → 422;
   inbox existente sem a chave continua funcionando **sem migration de dados**.
2. Trocar o perfil de uma inbox **não altera nenhum valor já gravado** sem confirmação explícita no
   diálogo — e o diálogo lista nominalmente o que muda.
3. Uma inbox com `csat_survey_enabled: false` e perfil `support` continua com o CSAT desligado.
4. O medidor de contraste da tela e a derivação do servidor produzem **o mesmo hex** nos 7 tokens,
   para um conjunto fixo de 20 cores.
5. Mudar a posição para "esquerda", salvar e reabrir **em outro navegador e como outro
   administrador**: continua "esquerda" — o que só é possível porque 3.01 declarou
   `widget_appearance` e 3.18 lhe deu schema, precedência e saída do `localStorage`. *Antes desta
   revisão este item era inatingível*: não existia coluna, chave, strong param nem montador que
   carregasse `position`.
   - **5b — a precedência é visível**: com `chatwootSettings.position` definido no site do cliente, o
     widget obedece **ao site** e a tela **avisa que há override ativo**, nomeando o campo. A regra é
     banco é o padrão, o snippet sobrescreve, a tela declara.
   - **5c — o ícone do lançador** escolhido na tela é o que aparece no lançador **e no preview**; uma
     imagem que falha ao carregar cai no balão padrão sem deixar o site sem canal de contato (3.19).
     **E o padrão de fábrica, depois da D5:** uma inbox criada agora — pela tela **e** pela API —
     nasce com o **balão na cor da marca**, em qualquer perfil; a tela mostra o aviso sugerindo a
     foto de alguém do time enquanto o modo for `default`; e o texto não oferece nem linka banco de
     imagem. **Nunca foto genérica.**
   - **5d — a abordagem em três níveis persiste e valida** (D1, bloco 3.20): `approach: "bold"`
     persiste e volta no `GET`; `"agressivo"` → 422 (é o erro que a arbitragem **A2** existe para
     produzir); `approach_mobile: "aggressive"` → 422 nomeando o campo; inbox sem a chave é lida como
     `bold` + `degrade_on_return: true`, **sem migration e sem backfill**.
6. Busca por `--slate-`/`--solid-` em `widget-preview/` → vazio; o toggle claro/escuro do preview
   funciona independentemente do tema do dashboard.
7. Editar qualquer campo e sair sem salvar: o store devolve os valores originais.
8. Adicionar o 9º campo de pré-chat é impossível, com o motivo à vista; CPF `111.111.111-11` é
   **rejeitado**; validação dispara no `blur`, não a cada tecla.
9. Toda chave de i18n usada existe em `pt_BR` **e** em `en` — teste que varre os `$t()` das telas
   novas e falha em chave faltante.
10. `axe-core` sem violação crítica ou séria nas quatro telas, nos dois temas do dashboard; em 768 px
    todas colapsam para coluna única.

### Onda 3 — Captura *(4ª · os blocos são `4.xx`)*

1. Trocar o perfil muda a tela inicial, o teaser e o rodapé — e **não** muda valor gravado.
2. O teaser aparece **uma vez**, só com as duas condições (8 s **E** 30%), não volta após dispensa em
   3 navegações, e não dispara com banner de cookies visível.
   - **2b — os três níveis existem e são distinguíveis** (D1): com `approach: "discreet"` o teaser
     sai sem foto e sem chips; com `"bold"` sai com os dois; com `"aggressive"` o teaser não sai e o
     painel abre (item 3). Uma inbox sem a chave se comporta como `"bold"`.
   - **2c — a degradação por familiaridade funciona nas duas direções** (D1, bloco 4.19): visitante
     novo recebe o nível configurado; visitante que voltou **sem ter convertido** recebe o nível
     abaixo; visitante que **converteu** volta ao nível configurado. Com `degrade_on_return: false`,
     o nível nunca cai. Verificado em navegador real, com o cookie inspecionado — não por mock.
3. **O painel não abre sozinho, exceto quando o administrador ligou o nível Agressivo** (D1). Este
   critério mudou de sentido em 13/08/2026 e a mudança precisa ser lida inteira, porque a versão
   anterior era uma proibição absoluta:
   - com `approach` ∈ {`discreet`, `bold`} — os dois padrões de fábrica — **o painel não abre sozinho
     em nenhum caminho**, e isso continua sendo testado;
   - com `approach: "aggressive"`, ele abre **uma vez por sessão**, respeitando o mesmo gatilho
     composto do teaser (8 s **E** 30%), e **`Esc` o fecha devolvendo o foco ao lançador**;
   - **em celular ele não abre sozinho**, a menos que o administrador tenha gravado
     `approach_mobile: "aggressive"` — e 3.20 recusa esse valor com **422**, então o caminho está
     fechado na tela **e** no schema, que é o que faz disso um mecanismo e não um aviso;
   - **o texto de aviso da tela não menciona penalização do Google** — `grep` nas strings de i18n da
     tela de abordagem por `Google` devolve **vazio** (decisão do produto, D1).
   - **3b — os três níveis são medíveis** (bloco 4.21): uma consulta responde "qual nível converte
     mais nesta conta", com exibição, abertura e conversão separadas por nível **e** pelo nível
     configurado, para distinguir o efeito da degradação do efeito do nível.
   - **3c — campanha legada e gatilho novo não disparam juntos** (D10, bloco 4.22): numa conta com os
     dois ativos, o visitante vê **uma** mensagem proativa, e é a do gatilho novo; desligando o
     gatilho, a campanha legada volta a aparecer sem republicar nada; conta que só tem campanha
     legada **não muda de comportamento**.
4. Um Flow com `wait_for_reply` publicado numa inbox Website avança quando o visitante clica numa
   opção; dois cliques geram **uma** mensagem e **uma** retomada; com o motor desligado, nada muda.
5. Um fluxo de captura de 4 campos conclui em 375 px sem scroll horizontal.
6. Simulando handoff, as três marcações de IA aparecem; simulando a volta, as três também.
7. Webhook criado com `inbox_id` recebe **só** os eventos daquela inbox; webhook sem `inbox_id`
   continua recebendo tudo; o `index` da API **não** devolve segredo.
8. Ligar `observado` numa inbox com tráfego real produz a lista de identificações não verificadas
   **sem quebrar nenhuma sessão**; sob estrito, e-mail de contato existente digitado no pré-chat
   **não funde** cadastros.
9. Uma conversa cujo `custom_attributes` contém texto com instruções **não** altera o comportamento
   do agente de IA — verificado com **dry run**, nunca contra IA de cliente.
10. **O `sdk.js` continua abaixo do teto depois do teaser.** O gate de 0.5 publica o delta do bloco
    4.06 e ele cabe nos 15 KB gzip (**A13**). Esta onda é a que mais engorda o arquivo que 100% dos
    visitantes baixam; encerrá-la sem olhar o número é entregar a vantagem nº 1 sem ninguém perceber.
11. **Lead incompleto** (bloco 4.18, aprovado pela **D3** — este item deixou de ser condicional):
    visitante que abandona o pré-chat no 3º campo vira **lead marcado como incompleto** no painel,
    com a etapa em que parou; retomar na mesma sessão **não** duplica o registro; o lead incompleto
    **não** dispara automação, campanha nem webhook de conversa; e o relatório responde "quantos
    leads perdemos e onde". Sem este item, entregamos leads e **não sabemos quantos perdemos** — e o
    teste A/B da Onda 6 fica sem denominador.
12. **A IA do perfil de marketing sai desligada enquanto o guardrail (6.01) não estiver em
    produção.** É a condição que a §3 item 9b impõe e que esta onda tem de verificar, porque é aqui
    que a IA chega à frente do visitante: com o guardrail ausente, a inbox de marketing recusa ligar
    a IA na tela, com o motivo à vista. Ligar IA exposta sem o gate de pré-envio aumenta a superfície
    de erro na página do cliente, com a marca do cliente — e o gate é código de custo zero que já
    existe no repositório [M18], só que rodando **depois** do estrago.

### Onda 4 — Atribuição *(5ª · os blocos são `5.xx`)*

1. Pixel configurado numa inbox e não em outra: o `window.chatwootWebChannel` da primeira traz o ID e
   o da segunda não — conferido no **HTML servido**.
2. Nenhum segredo aparece em: HTML do widget, resposta do endpoint de config, `index` da API de
   inboxes, ou log.
3. Página com **3 pixels**: o evento não vaza. Página **sem** pixel: nenhum `PageView` duplicado.
   `window.gtag` e `window.dataLayer` do cliente continuam funcionais e o console fica limpo.
4. Com CMP negando: **zero** disparos client-side; o payload server-side carrega `consent` negado.
5. No Events Manager do cliente, `Lead` aparece com **Browser e Server**, o total **não dobra**, e o
   Test Events mostra os dois com o **mesmo** `event_id`. EMQ ≥ 6,0 (alvo 8,0 com PII).
6. Com bloqueador de anúncio ligado, o client-side falha e o **server-side entrega** — no mesmo evento.
7. O `dataLayer` **não contém** e-mail, telefone ou nome em claro; o log de auditoria registra
   **nomes** de campos, nunca valores.
8. O SDK que roda na frota é o da versão corrente — a propagação já foi resolvida na Onda 1
   (item 12, bloco 5.07 realocado). O que se verifica **aqui** é a consequência: **nenhum cliente
   fica com SDK antigo conversando com backend novo**, e onde isso não é evitável (cliente que
   auto-hospeda o `sdk.js`, verificação **V7**), 5.10 tolera a versão anterior sem quebrar as tags
   do site.
9. Um integrador que nunca viu o produto instala, identifica um usuário e dispara um evento **só com
   o documento público**.
10. Venda fechada 30 dias depois aparece como conversão com valor real no Google Ads; conversa vinda
    de Click-to-WhatsApp é **atribuída ao anúncio**, não apenas aceita.

### Onda 5 — A conversa *(6ª · os blocos são `2.xx`, mais 3.15, 4.09 e 4.10)*

1. Os 16 snapshots passam, revisados.
2. `axe-core` sem violação **crítica ou séria** nas 4 views × 2 temas.
3. Todo clicável em 375×667 mede ≥ 44×44 (hoje **0 de 5** passam).
4. `prefers-reduced-motion` respeitado no painel, no launcher e no typing; `forced-colors: active`
   mantém os dois balões distinguíveis.
5. Rede cortada 10 s: nada nos primeiros 3 s, faixa depois, composer utilizável, fila drena **em
   ordem**; micro-queda de 1,5 s não mostra nada.
6. Mensagem chegando com o visitante rolado para cima **não** o arranca; o botão "descer" aparece
   com contador.
7. Painel funciona em **320 px** e em **200% de zoom** sem perda de conteúdo — **e o zoom é possível**:
   `app/views/widgets/show.html.erb:6` não traz mais `user-scalable=0` nem `maximum-scale=1` [M17], e
   nenhum input do composer tem `font-size` abaixo de 16 px (2.09 + 2.05). Enquanto a linha 6 do ERB
   estiver como está hoje, este critério é **impossível** de satisfazer e só pode ser declarado verde
   por engano — o painel renderiza a 200%, mas o usuário não consegue chegar lá.
8. `Esc` fecha e devolve o foco ao launcher; com o SO em escuro e sem `darkMode` configurado, o
   widget abre escuro e reage à troca **sem remount**.
9. Um erro forçado aparece no GlitchTip **com PII removida**.
10. JS eager ≤ 150 KB gzip; total eager ≤ 170 KB; `window.__SENTRY__` e `window.amplitude`
    **undefined** dentro do iframe.
11. **Os três blocos que chegaram de outras ondas fecham aqui**: 3.15 (o widget honra
    `mask`/`validator`/`step`/`show_if` por delegação, casca < 60 linhas), 4.09 (as três marcações de
    IA no handoff e as três na volta, **nunca roxo como marcador**) e 4.10 (CSAT com
    `role="radiogroup"`, alvos 44×44, máximo 3 botões por card). Eles vieram porque dependem de 2.01
    e 2.06 — encerrar esta onda sem eles é deixá-los órfãos de onda, que é como um bloco some.

### Onda 6 — IA e otimização *(7ª · os blocos são `6.xx`)*

1. **O guardrail retém, e não só anota** (6.01): uma resposta que **nega** o que a ferramenta acabou
   de devolver **não chega ao visitante** — vira handoff, com o motivo registrado. O mesmo caso hoje
   é apenas anotado no eval depois, e o teste demonstra a diferença nos dois modos. O guardrail
   **não chama LLM** (asserção sobre a contagem de chamadas) e **nunca derruba o atendimento**: em
   erro, ele libera e registra. Verificado em **dry run**, nunca contra IA de cliente.
2. **A partir daqui a IA do perfil de marketing pode ser ligada** — é a condição da Onda 3 item 12
   sendo levantada, e o critério é exatamente esse: o interruptor deixa de estar bloqueado na tela.
3. **O eval é do cliente, não nosso** (6.02): ele roda o conjunto de casos **antes** de publicar uma
   mudança de prompt, vê quantos casos regrediram, compara dois vereditos do mesmo caso lado a lado,
   e vê o **custo antes de rodar**. Nenhum caso executa contra IA de produção sem `dry_run`.
4. **A citação é metadado, não prosa** (6.03): a resposta baseada em documento mostra de onde veio, o
   link abre quando o documento é público, a citação **sobrevive ao reload** (está no banco), e uma
   resposta sem base **não inventa citação** — que é o modo de falha que importa.
5. **O facade não existe antes do clique** (6.04): `document.querySelectorAll('iframe')` na carga da
   página devolve **zero**; do clique ao painel utilizável, **≤ 1 s** em 4G simulado; o teaser
   continua aparecendo sem carregar o app; e dois cliques rápidos não instanciam dois iframes.
6. **O A/B tem denominador e tem honestidade estatística** (6.05): duas variantes recebem tráfego, o
   relatório mostra conversão **e abandono por etapa** nas duas (é 4.18 pagando), o mesmo visitante
   vê sempre a mesma variante na sessão, e o relatório **declara quando a diferença ainda não é
   distinguível do acaso** em vez de exibir o maior número.
7. **Nada desta onda engordou o `sdk.js` acima do teto.** O facade **reduz** o peso da primeira
   carga; o resto é backend e dashboard. O gate de 0.5 publica o delta e ele é ≤ 0 (**A13**).
8. **Existe uma página manual mínima para provar o live chat fim a fim.** Depois de 6.03–6.05,
   `spec/manual/live-chat.html` carrega o SDK real a partir de uma URL informada pelo operador e
   inicializa o widget com um *website token* digitado na própria página. O arquivo não contém
   token, senha, conta ou segredo versionado; não persiste nem escreve esses valores em URL,
   `localStorage`, console ou DOM depois da inicialização. Servido localmente, ele mostra estado
   explícito de carregamento/erro, abre o launcher e permite enviar e receber uma mensagem no
   ambiente de homologação escolhido. O aceite inclui um smoke local automatizado sem credencial
   real e uma verificação manual registrada no relatório da onda 6.

---

## 5. Divergências entre as frentes — declaradas e arbitradas

As quatro frentes foram planejadas em paralelo e, em doze pontos, especificaram a mesma coisa de
formas diferentes (**A1–A12**). Nenhuma escolha silenciosa: cada arbitragem traz a razão e, onde
existe, a medição própria (§0.3). A revisão de 12/08/2026 acrescentou **duas**: **A13** (o orçamento
de peso do `sdk.js`, que tinha dois valores em duas unidades e nenhum gate) e **A14** (a ordem da
trilha de origem, depois de medir que o banco não guarda o que o plano supunha).

> **E uma dívida que continua aberta, declarada aqui para não sumir de novo.** Estas arbitragens
> alteram o **detalhe** das tarefas — e a abertura deste documento diz que *"os planos das frentes
> continuam sendo a fonte de verdade do detalhe"*. Enquanto os quatro planos não receberem um bloco
> `> ARBITRADO — ver PLANO-MESTRE §5 A_x` no topo de cada seção contradita (`22:552`, `22:663`,
> `23:720`, `23:1305`, `23:1397`, `23:907`, `23:1398`, `24:1613`, `24:1580`, `25:231`), **o mestre
> manda o dev ler a fonte que ficou errada**. Isso é escrita, é **P**, e não está feito nesta
> revisão — a task que a executa é outra.

### A1 — Onde mora a configuração nova do widget

| Plano | O que diz |
|---|---|
| **22** §B.2 | Coluna nova `widget_profile` (integer + enum) em `channel_web_widgets`, com migration e entrada em `EDITABLE_ATTRS` |
| **24** §9.1-9.2 | `inbox.additional_attributes['widget_profile']`, com `store_accessor`, sem migration; e `widget_triggers` / `widget_tracking` no mesmo jsonb |
| **23** BE-1 | Um **sub-hash único** (`widget_config`) declarado uma vez no strong params, para não pagar N edições no arquivo 🔴 ao longo de meses |

**[ARBITRAGEM] `inbox.additional_attributes`, com QUATRO chaves de topo — `widget_profile`,
`widget_triggers`, `widget_tracking` e `widget_appearance` — declaradas numa única edição do strong
params.**

> **Correção de 12/08/2026.** Esta arbitragem foi escrita com **três** chaves, e a quarta —
> `widget_appearance` — sumiu junto com a dependência **BE-2** do plano 23. O efeito foi um aceite
> impossível na Onda 3 (*"mudar a posição para esquerda… continua esquerda"*) e um dev sem saída
> boa: ou gravar aparência dentro de `widget_profile`, quebrando a validação de inclusão, ou abrir
> uma **segunda** edição no `inboxes_controller.rb:217` (🔴) e destruir a economia de risco que esta
> própria arbitragem existe para criar. As quatro chaves cabem na mesma edição, e o custo de risco
> adicional da quarta é **zero**.

Cinco razões, quatro delas medidas:

1. **O ERB já tem a inbox na mão** [M5]: `show.html.erb` usa `@web_widget.inbox` em onze chaves. O
   argumento de que "o widget lê o canal, então o dado tem de estar no canal" não se sustenta.
2. **A serialização já existe** [M6]: `_inbox.json.jbuilder:27` devolve `additional_attributes`
   inteiro — o dashboard recebe de graça. A coluna no canal exigiria acrescentar uma linha a um
   arquivo 🟡 (+28/−5 upstream).
3. **Gatilhos e tracking são estrutura, não escalar.** Se o perfil for coluna e o resto jsonb, a
   configuração do widget passa a morar em dois lugares, com dois formatos, e o front monta dois
   payloads. Um lar só.
4. **Chaves de topo separadas, e não um sub-hash único, por causa do merge raso.** O update faz
   `(@inbox.additional_attributes || {}).merge(…)` — **primeiro nível apenas**
   (`inboxes_controller.rb:52-56`). Com `widget_config` único, um `PATCH` parcial de gatilhos
   **apagaria** perfil, aparência e tracking. Com quatro chaves de topo, cada `PATCH` preserva as
   outras. A preocupação legítima do plano 23 (não pagar N edições no arquivo 🔴) se resolve
   **declarando as quatro de uma vez** na primeira tarefa (3.01): a evolução posterior acontece
   **dentro** dos jsonb, que são hash aberto (`{}`), sem tocar mais no controller.
5. **Sem migration é uma trava de risco a menos.** Migration na frota carrega o risco conhecido de
   colisão de timestamp (`DuplicateMigrationVersionError` trava `db:migrate` na frota inteira). Hoje
   não há colisão [M9]; não criar uma é melhor que detectá-la.

**Custo aceito e como pagamos:** `additional_attributes` não é tipado nem indexável. Mitigação:
`store_accessor` (leitura tipada), validação de inclusão para o perfil, **JSON Schema com
`json_schemer`** (já é dependência, `Gemfile:37`) para gatilhos, aparência e tracking, e um spec de
controller cobrindo o `permit` — que é o item mais provável de ser esquecido. **E um teto de tamanho
para o jsonb inteiro** (3.18): ele é servido a qualquer agente com a inbox atribuída (M6) **e vai
para o HTML de toda página do site do cliente** — um hash aberto sem teto é o oposto do orçamento de
bytes que este plano defende em outros seis lugares.

**A regra de precedência da aparência (herdada de BE-2, e ela precisa estar escrita aqui):** o
**banco é o padrão**; `chatwootSettings` no site do cliente **sobrescreve**; e a **tela declara** que
há override ativo, nomeando o campo. Sem a terceira parte, o admin muda a posição na tela, nada
acontece no site, e o produto volta a mentir — que é exatamente o defeito que esta onda conserta.

**Regra dura herdada** [M6 + plano 24 §5/R5]: **nenhum segredo em `additional_attributes`**, porque
qualquer agente com a inbox atribuída o lê. Segredo de tracking vai para tabela própria com
`encrypts` (5.02), atrás do pré-requisito de chaves (0.10).

**Consequência:** a migration de W3.1 **não acontece**; a tarefa vira 3.01. E o critério de aceite
"16 snapshots idênticos antes e depois da migration" (plano 22 §B.5) passa a valer sobre a **leitura
derivada** (`nil` → `support`), não sobre uma migration que deixou de existir.

### A2 — Idioma dos valores do perfil

22 usa `support`/`marketing`; 24 usa `suporte`/`marketing`.

**[ARBITRAGEM] Valores em inglês (`support` | `marketing`); rótulo em pt-BR no i18n.** Precedente
medido [M7]: `pin_mode` grava `'per_agent'` e `reply_time` é `enum { in_a_few_minutes: 0, … }` — o
dado do repositório é inglês em `snake_case`, do upstream ao fork. Misturar português no valor
gravado cria duas convenções no mesmo jsonb. A prioridade de pt-BR do projeto é sobre **o que o
usuário lê**, e isso é i18n.

### A3 — O que a troca de perfil faz com o que já está gravado

| Plano | O que diz |
|---|---|
| **23** §B.1.4 | Escolher o perfil **define** os defaults (grava `pre_chat_form_enabled`, `csat_survey_enabled`, `continuity_via_email`…) |
| **22** §B.1 corolário e §B.5 aceite 4 | O perfil **nunca reescreve coluna gravada**; trocar para `support` **não liga** o CSAT |
| **24** §9.4 | Defaults ficam num serviço de seed **por criação** de inbox |

**[ARBITRAGEM] Três regimes, e cada plano está certo dentro do seu:**

1. **Inbox nova** — o perfil semeia os defaults na criação (24). Zero risco: não há valor a
   preservar.
2. **Inbox existente** — trocar o perfil **propõe**: abre um diálogo listando nominalmente cada
   mudança, com caixas marcáveis, e grava **só o que o administrador confirmar** (23, com a garantia
   do 22). Nada é escrito em silêncio, e nada é apagado — a configuração do perfil anterior fica no
   banco, inerte, e volta se o perfil voltar.
3. **Campos que só nascem agora** (teaser, base de conhecimento no widget, `homeLayout`,
   `captureFlow`, `primaryExit`) — não têm valor gravado, então são **resolvidos em runtime** pelo
   perfil (`WidgetProfile.resolve` → flags planas) até o cliente sobrescrever (22).

E a regra que atravessa os três: **o widget lê flags planas, nunca o nome do perfil.** É o que
impede a matriz de teste de dobrar (4 views × 2 temas × 2 viewports = 16 snapshots, não 32), impede
`if (profile === 'marketing')` de se espalhar por arquivos do campo minado, e mantém possível o
híbrido que o cliente sempre pede (marketing **com** base de conhecimento).

### A4 — Backfill do perfil

23 T1.4 pede backfill de todas as inboxes Website para `suporte`; 24 §9.3 recusa explicitamente.

**[ARBITRAGEM] Sem backfill.** `nil` é lido como `support`, que é literalmente o comportamento de
hoje (widget reativo, sem gatilho, sem teaser). Escrever `"support"` em toda inbox da frota é uma
varredura de escrita para produzir **zero** diferença de comportamento — e toda escrita em massa na
frota é risco sem contrapartida. A tarefa T1.4 sai do plano.

### A5 — Onde a segmentação dos gatilhos é resolvida

| Plano | O que diz |
|---|---|
| **23** §B.3.1 | Híbrido "modelo Leadster": um endpoint devolve o teaser e os gatilhos **já filtrados** por host+path+query+dispositivo; assim "a regra não fica legível no `view-source` do site do cliente" |
| **24** §10.4 | A avaliação é client-side por natureza; o servidor entrega a configuração, e **tudo que estiver em `widget_triggers` é público** |

**[ARBITRAGEM] Na v1, a configuração vai no payload de boot e a avaliação é do SDK (24). O endpoint
filtrado entra quando — e só quando — a segmentação usar dado que o navegador não tem.**

A razão que nenhum dos dois escreveu: **todos os critérios da v1 são observáveis pelo próprio
navegador do visitante.** URL, query string, UTM, dispositivo e "visitante novo ou recorrente"
(cookie do host) já estão na máquina dele. Não há segredo a proteger — proteger a lista de URLs de
uma campanha do visitante que **está naquela URL** é cerimônia, não segurança. O custo do endpoint
(rota, policy, cache, mais um lugar para divergir) não se paga contra esse ganho.

Quando a segmentação passar a usar dado de servidor (é cliente, plano contratado, valor de carteira),
o desenho muda para o que o plano 24 já deixou escrito: o widget **pergunta** "posso disparar o
gatilho X?" e o servidor responde sim/não **sem revelar o critério** — o que é melhor que devolver a
regra filtrada, porque não vaza nem a existência do critério.

### A6 — Sanear o `referer` antes de anular

25 §A.2 diz explicitamente "**não tocar** `app/models/conversation.rb`"; 24 BK-12 propõe sanear ali,
com risco **Médio** e o histórico do método marcado [NÃO VERIFICADO].

**[ARBITRAGEM] Sanear sim, com o saneamento em `lib/url_helper.rb` e uma linha de chamada no
modelo.** Medição própria [M2]: `conversation.rb` teve +79/−8 do upstream em 4 commits, **mas o
método `validate_referer_url` é byte-idêntico** entre v4.12.1 e v4.16.2 — só desceu de `:334` para
`:405`. E `lib/url_helper.rb` teve **0/0**. Portanto: o risco real é o **deslocamento** do arquivo
(que o merge resolve), não o conflito no método. Colocando a lógica no helper (0/0) e deixando no
modelo apenas a chamada, o risco cai de **Médio** para **Baixo**, e a alternativa que o plano 24
rejeitou (sanear em `base_controller.rb#permitted_params`, "a área de maior atrito") continua
rejeitada — com razão.

Por que sanear, e não deixar como está: hoje uma URL com espaço não escapado ou colchete cru faz o
campo virar `nil` **e a conversa salvar normalmente**. O dado de origem some antes de qualquer parser
existir. Um plano cujo primeiro entregável é "de onde veio esse lead" não pode conviver com uma
validação que apaga a resposta em silêncio.

### A7 — Quando corrigir o retry de webhook (B3)

24 BK-02 põe na **Onda 0**, com "dep: —" e risco **Baixo**, espelhando `agent_bots/webhook_job.rb`.

**[ARBITRAGEM] BK-02 depende do merge (0.2), e o molde da correção mudou.** Medição própria [M3]: a
v4.16.2 **reescreveu `Webhooks::Trigger`** (+30/−10) — construtor com `secret:` e `delivery_id:`,
transporte via `SafeFetch` no lugar de `RestClient`, e uma classe `RetryableError` nova. E **o
defeito continua lá**: o `raise` só vale para `agent_bot_webhook`; account e api_inbox continuam
engolindo a exceção, então `retry_on … attempts: 5` continua sendo letra morta.

Três consequências práticas:

1. Corrigir antes do merge é escrever contra uma classe que vai ser substituída — e o
   `spec/lib/webhooks/trigger_spec.rb` que hoje stuba `RestClient::Request` também muda.
2. O item "`delivery_id` estável entre tentativas" fica **mais barato** depois do merge: o upstream
   já passa `delivery_id:` pelo construtor.
3. Como o defeito é do upstream, é o candidato mais natural a patch upstream (decisão **N8**:
   contribuir infraestrutura, manter proprietário o produto).

### A8 — O throttle que nunca casa

**[ARBITRAGEM] BK-04 continua valendo, mas depois do merge — e é bug do upstream.** Medição própria
[M4]: a v4.16.2 ainda compara com `/api/v1/widget/contacts` (plural) enquanto a rota é singular. O
arquivo tem +89/−22 de churn upstream, então a correção é divergência nossa num arquivo quente:
melhor aplicá-la depois de 0.2, e oferecê-la ao upstream junto com o patch de `origin`/`targetOrigin`.

### A9 — Dois vocabulários de evento para o mesmo fato

24 §17.1 propõe `chatwoot:conversation-created`; 25 §A.6 propõe `chatspx_conversation_started` — e o
próprio 25 §C.2 item 2 avisa que dois vocabulários para o mesmo fato é sintoma de duplicação.

**[ARBITRAGEM] Dois nomes, uma emissão, mapa publicado.** São **dois contratos distintos com
públicos distintos**, e forçá-los ao mesmo nome piora os dois:

- **Evento de `window`** (o site do cliente escuta): mantém o namespace `chatwoot:` — é o que os 7
  eventos existentes usam e o que clientes já escutam. Renomear quebraria integração em produção, em
  silêncio.
- **Evento de tracking** (vai ao GA4, à Meta, ao `dataLayer`): usa `chatspx_`, `snake_case`, ≤ 40
  caracteres — porque é limite do GA4 e porque o nome aparece no relatório do cliente.

A emissão é **uma só** (regra RG4 do plano 25) e o mapa 1:1 é publicado no contrato (5.15):

| Fato | Evento de `window` | Evento de tracking |
|---|---|---|
| conversa criada no servidor | `chatwoot:conversation-created` | `chatspx_conversation_started` |
| pré-chat concluído | `chatwoot:prechat-submitted` | `chatspx_prechat_submitted` |
| visitante enviou mensagem | `chatwoot:message-sent` | — (sinal interno) |
| CSAT respondido | `chatwoot:csat-submitted` | `chatspx_csat_submitted` |
| teaser/campanha exibida | `chatwoot:campaign-shown` | — |
| contato passou a ter e-mail ou telefone | — (server-side) | `chatspx_lead` |

### A10 — A mesma tarefa com vários nomes

Onze pares/trios que **não podem ser pagos duas vezes**. A tabela mestra já os funde; esta lista
existe para quem chegar pelo plano de uma frente só:

| Tarefa | Nomes nas frentes | Bloco mestre |
|---|---|---|
| Merge da v4.16.2 | W0.1 · T0.1 · RG5 | 0.2 |
| Bridge de eventos + `e.origin` | W2.1 · T-I1.3 · T-I1.5 · T-C3.8 | 1.09 |
| Paridade dos dois montadores | T0.8 · BK-01 · aceite de T-C1.4 | 0.6 |
| Retry de webhook (B3) | BK-02 · T-I5.1 · T-I5.2 | 1.13 |
| HMAC portas 1 e 2 (B5) | BK-03 · T-I1.1 · T-I1.2 | 1.11 |
| Auto-provisionamento (B6 backend) | BK-09 · T-I2.1 | 1.16 |
| Seção "dados do site" no painel (B6 front) | T-C0.5 · T-I2.2 | 1.17 |
| Parser de origem (C0) | BK-11 · T-C0.1 · T-C0.2 · T-C0.7 | 1.19 |
| Teto de chaves no contato | BK-06 · T-I1.9 | 1.14 |
| `event_id` de volta ao widget | BK-18 · T-C6.1 | 5.05 |
| Enforcement de identidade | BK-24 · T-I2.6 | 4.15 |
| JWT adicional | BK-39 · T-I2.7 | 5.19 |
| Config pública de tracking | BK-15 · T-C1.1 · BE-8 | 5.01 |
| Gatilhos no backend | BK-14 · BE-4 | 3.02 |
| `EDITABLE_ATTRS` do pré-chat | T2.1 · BE-6 | 3.12 |

### A11 — Onde a tela de tracking nasce: `app/` ou `enterprise/`

O plano 25 deixa a pergunta aberta ("decidir se a tela nasce em `enterprise/`, menor risco de merge,
mas indisponível em conta community"); o plano 23 assume `app/javascript/dashboard/routes/…/inbox/widget/tracking/`.

**[ARBITRAGEM] `app/`, com gate por conta em `internal_attributes`.** Duas razões: a inbox Website
existe em qualquer plano, e um gate por feature flag de conta está **impossibilitado** — o bitmask
de `features.yml` está cheio (65 entradas em 63 bits úteis), e o próprio `account.rb:190-193` já
registra isso e usa `internal_attributes` como saída. Colocar a tela em `enterprise/` para depois
precisar de um gate que não cabe é resolver merge criando um problema de produto.
**[NÃO VERIFICADO]** quais contas da frota rodam plano enterprise — se a resposta for "todas", a
decisão pode ser revista sem custo, porque o arquivo é novo dos dois jeitos.

### A12 — Retenções que parecem conflito e não são

25 T-C8.2 sugere **90 dias** para o log de eventos de tracking; 24 §20.6/BK-35 sugere **7 dias** para
o log de entregas de webhook. São objetos diferentes, com finalidades diferentes (diagnóstico de
atribuição × reenvio operacional). Ambos ficam **configuráveis**, com esses valores como padrão.
Registrado aqui para não virar discussão depois.

### A13 — O orçamento de peso do `sdk.js` (arbitragem nova, 12/08/2026)

Dois orçamentos existiam para o mesmo arquivo, em unidades diferentes, e nenhum estava neste
documento: **15 KB gzip** (apêndice §E.4 do plano 22) e **40 KB crus** (`package.json:23-32`, o
`size-limit` que já roda hoje, medido por `@size-limit/file` sobre o arquivo cru).

**[ARBITRAGEM] Os dois valem, com papéis diferentes, e ambos entram no gate 0.5.** O teto de **15 KB
gzip** é o que protege o visitante — é o byte que atravessa a rede. O teto de **40 KB crus** é o que
protege o *parse* e já está configurado; mantê-lo custa zero. Linha de base medida [M15]: **28.834 B
crus / 9.508 B gzip** — folga real de **~5,4 KB gzip**. E o gate publica o **delta em bytes** a cada
PR que toca `sdk/`, para que a engorda seja visível enquanto é barata.

**Por que isso virou arbitragem e não nota de rodapé.** O `sdk.js` é a vantagem nº 1 medida do
produto: **15,9× mais leve** que o loader do principal concorrente. **Oito blocos deste plano
adicionam código *eager* a ele** — 1.23 (Promise + fila pré-boot), 2.11 (`Esc` + `inert`), 2.14
(degradação), **4.06 (o teaser, esforço G)**, 4.11 (piscar do título), 5.16 (`track()`), 5.17
(getters + `company`), 5.18 (`data-*`) — e apenas 5.08/5.09/5.10 são declarados "sob demanda". Sem
teto no gate, **é a única vantagem que este plano pode destruir sem que um único aceite fique
vermelho**. E o dano é assimétrico: 575 KB dentro do iframe custam a quem **abriu** o chat; bytes no
`sdk.js` custam a **100% dos visitantes de todos os sites de todos os clientes**.

**Regra prática que decorre:** todo bloco que acrescentar peso *eager* ao SDK precisa dizer, no
próprio aceite, de quanto foi o acréscimo. Se não couber, o caminho não é subir o teto — é carregar
sob demanda, como 5.08/5.09/5.10 já fazem.

### A14 — A ordem da trilha de origem, e o que o banco não sabe (arbitragem nova, 12/08/2026)

O plano dizia que 1.20 (sanear) *"anda junto"* de 1.19 (o parser); o grafo dizia `1.19 dep 1.18` e
`1.20 dep 0.2` — quer dizer, nada impedia o parser de ir a produção primeiro.

**[ARBITRAGEM] `1.19` depende de `1.18` **e** de `1.20`; `1.21` fica atrás do portão `V3`; `1.22`
depende de `1.19`, não de `1.21`.** Razão medida [M12]: **0 conversas com `referer` preenchido em
3.180**, porque `conversation.rb:536-539` **anula o valor na escrita**. "O SDK não mandou" e "a
validação destruiu" produzem o mesmo `null`, e o banco não os distingue — então:

- subir o parser antes do saneamento é **continuar destruindo dado** enquanto o relatório promete
  respondê-lo (perda silenciosa, no exato entregável que o plano vende como argumento de orçamento);
- o **backfill não recupera** o que já foi anulado — em 100% da amostra disponível, já se perdeu;
- e o **relatório (1.22) não pode depender de uma tarefa cancelável**: ele passa a se apoiar em
  1.19, e o backfill, se acontecer, apenas estende o período coberto para trás.

**O que fica pendente e é honesto declarar:** a distinção entre os dois caminhos só existirá
**depois** de 1.20, quando o que não valida for para `referer_raw` em vez do lixo.

> **Atualização de 13/08/2026 (D6): a parte desta arbitragem que falava do backfill caducou.** A
> ordem `1.20 → 1.18 → 1.19 → 1.22` continua exatamente como está escrita acima, e as razões também.
> O que mudou é o fim da fila: **1.21 não existe mais e V3 deixou de ser portão** — ver **A16**.

### A15 — A abordagem em três níveis, e onde ela mora (arbitragem nova, 13/08/2026)

A **D1** criou três níveis de abordagem com degradação por familiaridade. Isso podia morar em três
lugares, e a escolha tem consequência de merge e de peso:

| Onde | O que seria |
|---|---|
| Chave nova de topo em `additional_attributes` (`widget_approach`) | Uma **quinta** chave, e uma segunda edição no `inboxes_controller.rb:217` (🔴) |
| Dentro de `widget_appearance` | Aparência é *como o widget se parece*; abordagem é *quando e com que intensidade ele fala* |
| **Dentro de `widget_triggers`** | Gatilho é *quando*; nível é *com que intensidade*. É o mesmo objeto de decisão |

**[ARBITRAGEM] `widget_triggers`, com três campos novos — `approach`, `degrade_on_return` e
`approach_mobile` — validados pelo mesmo `json_schemer` do bloco 3.02.** Quatro razões:

1. **Zero edições novas no arquivo 🔴.** A arbitragem **A1** existe para que a evolução aconteça
   **dentro** dos jsonb já declarados. Uma quinta chave de topo destruiria exatamente a economia que
   A1 criou, e por um campo que é conceitualmente parte do gatilho.
2. **O nível é avaliado no mesmo lugar e no mesmo momento que o gatilho** — no SDK, client-side, pela
   arbitragem **A5**. Separá-los em dois objetos obriga o SDK a ler dois caminhos para tomar uma
   decisão só.
3. **Nada aqui é segredo.** Vale a regra dura de A1: o objeto vai para o HTML de toda página do
   cliente e é lido por qualquer agente com a inbox atribuída [M6]. Nível de abordagem é público por
   natureza — o visitante **está vendo** o teaser.
4. **A degradação é estado do visitante, não configuração da inbox**, e por isso ela **não** está no
   jsonb: mora num cookie do host (bloco 4.19), com duas informações apenas. Guardar contagem de
   abordagem por visitante no servidor criaria uma tabela nova, um identificador novo e um problema
   de LGPD, para resolver o que um cookie de primeira parte resolve.

**O que decorre para quem for implementar:** `approach_mobile` **não aceita `aggressive`**, e a
recusa é no schema (422), não na tela. Tela avisa; schema impede. A decisão do produto é "não liga em
celular por padrão" — e a diferença entre *padrão* e *possível* aqui é deliberada: em celular o
painel cobre a tela inteira, que é a situação em que auto-open é mais hostil. Se um dia essa recusa
for reaberta, o lugar de reabrir é o schema, e vai aparecer no diff.

### A16 — O backfill de origem: cortado, não adiado (arbitragem nova, 13/08/2026)

O plano tinha **1.21** (backfill retroativo de origem) atrás do portão **V3**, "cancelável por
medição". A **D6** cortou.

**[ARBITRAGEM] 1.21 sai do plano; V3 deixa de ser portão; BK-13 e T-C0.4 ficam registradas como
cortadas; e o esforço vai para 1.20.** A razão é medida e é definitiva nesta base [M12]: **0 conversas
com `referer` preenchido em 3.180**, porque `conversation.rb:536-539` anula na escrita. Um backfill
lê o que está no banco. O que foi anulado **não está lá** — não está degradado, não está codificado,
não está em outro campo. Não há nada para ler.

**Por que "cortado" e não "adiado", que era o estado anterior.** Um item adiado atrás de um portão
tem três custos que ninguém contabiliza: ele mantém viva uma **expectativa comercial** ("depois a
gente recupera o histórico"), mantém uma **dependência de medição em produção** que precisaria ser
refeita depois de 1.20 para significar alguma coisa, e mantém uma **linha na tabela** que um dev
futuro pode achar que só está esperando a vez. Cortar resolve os três de uma vez, e o registro fica:
a linha continua na §2.2, riscada, para que ninguém a reintroduza achando que foi esquecimento.

**O que ganha com o corte, e este é o ponto:** **1.20 sobe de prioridade e ganha aceite próprio.**
Enquanto havia backfill atrás, 1.20 era "a tarefa que melhora a qualidade do dado". Sem ele, 1.20 é
**a única coisa entre o produto e um campo permanentemente vazio** — e por isso passou de uma frase
de aceite para cinco asserções, incluindo o request spec que grava três formas de URL e lê as três de
volta do banco.

**E o bloqueador B4 da auditoria fica resolvido — por decisão, não por medição.** Ele existia porque
a premissa *"a origem já está no banco"* nunca fora medida. Foi medida, é falsa, e o produto decidiu
não perseguir o passado. Um bloqueador que se dissolve porque o escopo que ele bloqueava deixou de
existir é um bloqueador resolvido, e é assim que ele deve ser lido na §7.

---

## 6. Riscos e armadilhas consolidados

Ordenados por probabilidade × custo. Cada um tem o sinal que o denuncia e a mitigação, e cada um
aponta o bloco mestre onde a mitigação vive.

| # | Risco | Sinal de que aconteceu | Mitigação | Bloco |
|---|---|---|---|---|
| **R1** | **Fazer o redesenho antes do merge da v4.16.2** (113 arquivos do widget, +4.332 −7.635) | Conflitos gigantes num PR que já é grande; ninguém consegue revisar | 0.2 é bloqueante, sem exceção; e 0.1 (baseline) vem antes dele | 0.1, 0.2 |
| **R2** | **O `:hover` verde do launcher ressuscita.** `sdk.js:132` reaplica `#2dc46f`; hoje o `:style` inline o mascara. Removendo o inline sem tocar o CSS, o launcher fica na cor da inbox **e fica verde ao passar o mouse** | Ninguém percebe: screenshot de launcher não captura hover | Asserção de hover explícita no aceite e no `color.spec.js`. **É o bug mais provável da Onda 1** | 1.05 |
| **R3** | **Perfil vira `if` espalhado.** Começa com um `v-if="isMarketing"` "só nesse componente" | `grep -rn "widgetProfile" app/javascript/widget/` casa em template | Regra A3 + lint: o widget lê flags planas, nunca o nome do perfil | 3.05 |
| **R4** | **Reescrever a config de build antes de 0.3** | O trabalho de peso é jogado fora no merge | Nenhuma tarefa de build antes de 0.3 | 0.3, 0.5 |
| **R5** | **Colisão de timestamp de migration** com o upstream ou com o WIP paralelo | `DuplicateMigrationVersionError` trava `db:migrate` **na frota inteira** | A1 elimina três migrations; para as que restam (4.17, 5.02, 5.03), rodar `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` antes de subir; fix é `git mv` | 4.17, 5.02, 5.03 |
| **R6** | **Segredo em `additional_attributes`** | Um agente comum consegue ler o access token da Meta pelo `GET` de inbox | Regra dura de A1, sustentada por [M6]; validação que **recusa** chave com cara de segredo | 3.01, 5.01, 5.02 |
| **R7** | **Aceitar segredo de terceiro sem as chaves de criptografia** | O access token do cliente fica **em texto puro** no banco | 0.10 é pré-requisito duro de 5.02/5.11/5.21 | 0.10 |
| **R8** | **`widget_color` do banco interpolado em CSS.** Hoje é interpolado em JS; o `<style>` do servidor é vetor novo | Injeção de CSS via cor de inbox | Helper Ruby valida `#RRGGBB` e cai para o default; item explícito no aceite | 1.02 |
| **R9** | **Quebrar a medição do site do cliente** (sobrescrever `gtag`, duplicar `PageView`, vazar evento entre pixels) | O cliente vê número errado no painel dele e culpa o chat — com razão | `trackSingle`/`send_to`, `skipPageView`, código **aditivo** (`window.gtag \|\| …`), e **"somente dataLayer" como padrão de fábrica** | 5.10 |
| **R10** | **PII no `dataLayer` ou nos parâmetros do `fbq`** | Incidente de LGPD com interface | Hash **só no servidor**; lista negativa de campos; teste que barra campo sensível no payload client-side | 5.10, 5.11 |
| **R11** | **Conversão contada em dobro** no GA4 (que não deduplica) | O cliente decide mídia com número inflado | Um caminho por evento lógico no GA4; `event_id` obrigatório no par Meta | 5.13 |
| **R12** | **Congelar o layout mobile sem dispositivo real.** `dvh`, `visualViewport` e `overscroll-behavior` **não são testáveis em headless** | Composer atrás do teclado no iPhone; painel cortado pela barra de endereço | Teste manual obrigatório em iOS Safari e Android Chrome antes de fechar 2.09. **72% dos minutos digitais no Brasil são mobile** | 2.09 |
| **R13** | **O teaser fora do iframe quebra em site com CSS agressivo** | Funciona no host de teste, quebra no site real | `all: revert` no contêiner, tudo declarado, prefixo `woot-`; **testar em 3 sites de clientes antes da frota** | 4.06 |
| **R14** | **`Settings.vue` reescrito por dentro** (🔴 +242/−24 upstream, +99/−18 fork) | Diff grande num arquivo que os dois lados reescrevem | Ele ganha **quatro linhas** no plano inteiro; toda tela nova mora em `inbox/widget/` ⚪ | 3.09 |
| **R15** | **Campo minado do widget reescrito em vez de delegado** (`ChatInputWrap`, `ChatFooter`, `PreChat/Form`) | +12/−9, +37/−12 e +39/−33 de conflito a cada minor | Cascas finas; o aceite mede: < 60 linhas cada | 2.05, 3.15 |
| **R16** | **Snapshots viram ruído** | PRs mergeados com snapshot vermelho | Fixtures determinísticas + tempo congelado; threshold estrito só onde faz sentido | 0.1 |
| **R17** | **O gate de peso é ligado com tetos inalcançáveis** | O time desliga o gate | Os 5 tetos entram um a um, cada um junto da tarefa que o torna alcançável | 0.5, 1.08, 2.18 |
| **R18** | **CSP do site do cliente bloqueia o SDK ou o teaser** | Funciona em teste, some em produção de um cliente específico | Nada de `eval`, nada de CDN externo, tudo servido do nosso domínio; testar num site com CSP restritiva antes da frota | 4.06, 5.08 |
| **R19** | **Custo de IA e de API de terceiro por volume** | Fatura cresce sem ninguém ligar a causa | Batch e throttling por conta na fila server-side, com métrica de custo | 5.11 |
| **R20** | **Comemorar compressão medindo só homologação** | O ganho de 2,58 MB→575 KB não aparece para o cliente | 0.4 exige `curl -I` nas quatro VMs | 0.4 |
| **R21** | **`shared/` mexido para o widget quebra dashboard, portal e survey** | Regressão em tela que ninguém estava olhando | Toda tarefa 🟡 em `shared/` roda a suíte do dashboard também; alternativa é primitivo próprio em `widget/ui/` | 2.01 |
| **R22** | **Rate limit do `Rack::Attack` durante o suite** (o estudo já tomou 429 medindo pelo domínio público) | CI vermelho intermitente e inexplicável | Suite roda contra `localhost:3000`, nunca contra domínio público | 0.1 |
| **R23** | **Regressão de RTL** (`_conversation.scss` tem ~30 pares `ltr:`/`rtl:`) | Layout árabe/hebraico quebrado, sem ninguém para reclamar | Cada tarefa que toca `_conversation.scss` preserva os pares; um snapshot em `dir="rtl"` na Onda 2 | 2.03 |
| **R24** | **Navegador fora do Chromium.** Toda a fundação visual foi medida em Chromium 145; o fallback CSS depende de *relative color syntax* e `pow()` | Marca escura com texto preto ilegível no Safari/Firefox | A fonte de verdade é o **servidor** (1.02), não o CSS; o fallback é rede de segurança, não mecanismo | 1.02 |
| **R25** | **O plano andar e a história não ser contada.** Das 16 vantagens verificáveis do estudo, **nenhuma** aparece hoje em material comercial | Entregamos dedup, `Esc`, dark mode e telemetria — e o mercado não fica sabendo | 5.15 (contrato público) é a peça de engenharia que mais ajuda a narrativa; e ela começa cedo | 5.15 |

---

## 7. Verificações pendentes antes de começar

Sete itens, dos quais **um foi encerrado em 13/08/2026** (V3, pela decisão D6 — ver **A16**). Para
cada um: quem responde, se bloqueia, e o que muda no plano conforme a resposta. **Nenhum deles impede
a Onda 0 de começar**, e agora **nenhum deles é portão de tarefa nenhuma da Onda 1** — o único que
era, V3, deixou de existir junto com o backfill. Três continuam precisando de resposta antes da onda
de **Atribuição** (a 5ª): V1, V2 e V5.

| # | Pergunta | Quem responde | Bloqueia | Como responder | O que muda |
|---|---|---|---|---|---|
| **V1** | O webhook do WhatsApp Cloud entrega hoje o objeto `referral` com `ctwa_clid`? | **Engenharia**, com acesso de leitura à produção | 5.21 (CTWA) | Consulta pronta e testada contra o schema real: `SELECT count(*) FILTER (WHERE content_attributes->'referral' ? 'ctwa_clid') FROM messages WHERE content_attributes ? 'referral';` — homologação tem **zero** mensagens com `referral`, então não serve de amostra | Se presente: CTWA cai de **G** para **M**, porque a ingestão **já existe** (`incoming_message_base_service.rb:194` copia o objeto inteiro). Se ausente: vira oportunidade comercial, não engenharia. WAHA está fora do caminho e permanece fora do escopo |
| **V2** | Existe DPA cobrindo o envio de PII hasheada a Meta e Google? | **Jurídico / comercial** (não é verificável por código) | 5.11 no modo com PII | Três perguntas objetivas: o contrato vigente prevê tratamento por conta do cliente com subcontratação declarada? Existe aditivo? Quem assina e o que fazer com quem recusar? | Sem DPA, **5.12 (modo sem PII) vai ao ar assim mesmo** e recupera parte dos 20–40% perdidos por bloqueador. A resposta deixa de ser bloqueio de projeto e vira chave que liga mais matching |
| ~~**V3**~~ | ~~Quantas conversas da frota têm `utm_`/`gclid`/`fbclid` no `referer`?~~ | — | **NADA — deixou de ser portão em 13/08/2026** | — | **Encerrada pela decisão D6** (ver **A16**). Ela existia para decidir se o backfill (1.21) valia a pena; o backfill foi cortado, e com ele foi a pergunta. A medição que sobra é a de **depois** de 1.20 estar em produção — não para decidir nada, mas para saber **quanto tráfego identificado passa a existir**, e essa é a instrumentação do bloco 4.21, não uma verificação prévia. **Nenhuma tarefa deste plano espera por acesso de leitura à produção por causa de origem** |
| **V4** | Quais headers de cache as VMs de **produção** devolvem para `/packs/`? | **Engenharia**, `curl` público | 5.07, e afeta todo rollout de SDK | `curl -sSI https://<host>/packs/js/sdk.js`. Já medido em homologação: `max-age=31556952` (1 ano), sem `ETag` — **e o header é do Rails** (`config/environments/production.rb:23-26`), não do nginx | Se confirmado na frota, 5.07 é obrigatória e vem antes de 5.08/5.10. A boa notícia: a correção é código nosso, entra pelo deploy normal, sem mexer no nginx de cada VM |
| **V5** | Quais VMs já têm `ACTIVE_RECORD_ENCRYPTION_*`? | **Infra** | **0.10 → 5.02, 5.11, 5.21** | Inventário VM a VM (presença da chave no `.env`, sem ler valor). Em homologação: **ausentes** — então `encrypts` é no-op aqui e `webhooks.secret` está em texto puro | Sem as chaves, o produto **não deve** oferecer o caminho server-side. É a única pendência que bloqueia uma onda inteira |
| **V6** | Quantas inboxes Website existem na frota, e quantas já têm campanha de chat ativa? | **Engenharia**, leitura | Nada; refina 3.03 | Consulta simples por `channel_type` e por `campaigns` ativas | Se a maioria já usa campanha proativa, a leitura "todas são suporte" pode estar errada, e o texto do diálogo de troca de perfil muda |
| **V7** | Algum cliente auto-hospeda o `sdk.js` (cópia própria no CDN dele)? | **Comercial / suporte** | Nada; entra na comunicação | Perguntar aos clientes maiores e aos que têm agência | Se sim, nenhuma mitigação de cache o alcança, e 5.10 precisa tolerar SDK antigo conversando com backend novo |

**Uma pendência de produto, não de engenharia:** a frequência de reaparição do teaser **não foi
medida em nenhum fornecedor** — é parâmetro nosso, sem referência externa. Temos frota para medir
internamente, e essa medição vale mais que qualquer benchmark citável. Vale começar com o default
conservador (uma vez por sessão, 7 dias após dispensa) e instrumentar.

---

## 8. O que NÃO vamos fazer

Lista explícita, consolidada das quatro frentes. Cada linha existe para impedir que o escopo cresça
em reunião, e cada uma tem o número que sustenta a recusa.

| # | Não faremos | Por quê |
|---|---|---|
| 1 | **Migrar para Shadow DOM ou DOM direto** | O isolamento por iframe é vantagem medida (a Leadster precisa de **239 `!important`** para provar o contrário). O híbrido é decisão posterior, e este plano é compatível com ela |
| 2 | **Expor geometria** (largura, altura, raio do painel, tamanho do launcher) na configuração | Nossos valores já são a moda/mediana do mercado, e a decisão do Walisson mantém a geometria. Expor convida o cliente a quebrar o que está certo |
| 3 | ~~**Auto-open do painel**, por gatilho ou por qualquer caminho~~ — **esta recusa caiu em 13/08/2026 (D1)** | O auto-open **entra**, como o terceiro nível de abordagem (`aggressive`): **desligado por padrão, disponível para todas as contas**, sem gate de plano, **e não liga em celular por padrão** (`approach_mobile` recusa `aggressive` com 422). O aviso na tela **não menciona penalização do Google** — decisão do produto. O que o plano continua registrando, porque é o que o corpus mede: toda reclamação documentada de usuário final é contra o auto-open, nenhuma é contra o teaser. Por isso ele é o nível que **ninguém recebe sem escolher**, e por isso os três níveis são instrumentados (4.21): a discussão sobre qual converte mais passa a ser resolvida por dado desta frota, e não por opinião. Blocos **3.20**, **4.20**, **4.21** |
| 4 | **Editor de CSS livre para o widget** | O iframe existe para isolar. CSS livre transforma cada cliente num fork visual impossível de suportar |
| 5 | **Instalar um GA4 nosso no site do cliente** (o que a Leadster faz por padrão) | Tratamento de dado do visitante do cliente para finalidade nossa — indefensável sob LGPD. Instalar tag **faltante** é opt-in explícito, nunca padrão |
| 6 | **Construir GTM server-side** | O ChatSPX **já é o servidor** que tem o dado. Somos fonte limpa para quem tem sGTM; não vendemos container |
| 7 | **Virtualizar a lista de mensagens** | O DOM inteiro do widget tem 74 nós; 50 mensagens ficam em 500–700. O limiar é ~200 mensagens simultâneas, raro num chat de site |
| 8 | **Adotar webfont** | Com dois pesos, a variável é 320 bytes **mais pesada** que as estáticas. Hoje o custo de rede já é zero: os 7 `.woff2` publicados nunca são baixados |
| 9 | **Recibos "entregue" e "lido"** | Nenhum concorrente do corpus tem, e "lido e não respondido" transforma cada segundo de silêncio em irritação. Faremos `enviando`/`enviado`/`falhou` |
| 10 | **Notificação nativa do navegador e vibração** | **Zero** widgets do corpus fazem. Pedir permissão em cima do primeiro contato é caro em confiança; o piscar do título resolve 90% com 0% de atrito |
| 11 | **Roxo como marcador exclusivo de IA** | Contra o azul de informação, o par colapsa para **ΔE 1,8** em deuteranopia. Roxo pode ser sotaque; marcador é rótulo ou ícone |
| 12 | **Densidade compacta (14 px) como default** | É régua de ferramenta para usuário treinado e sentado. O visitante é o oposto nas três dimensões. Fica como variante |
| 13 | **Overshoot nas curvas** | Só o Intercom usa; todas as outras curvas do corpus desaceleram sem passar do ponto |
| 14 | **Injetar mensagem na conversa pelo site** (o `showNewMessage` do Intercom) | É poder de escrita no conteúdo da conversa concedido a qualquer script da página. Se um dia entrar, entra **depois** da validação de origem e **atrás** de identidade verificada |
| 15 | **Condicional aninhada (E/OU) no construtor de pré-chat, na primeira entrega** | É uma tela inteira por si só; nem o Intercom expõe isso ao cliente final |
| 16 | **Reescrever o motor de campanhas** | Ele funciona. **Campanha é a mensagem, gatilho é o momento** — fundir os dois obriga a criar uma campanha por gatilho e polui a tela do cliente |
| 17 | **Redesenhar `PreChat/Form.vue` por dentro** | +39/−33 só desde a nossa base, 16 commits em 36 meses. Recebe **apenas tokens**; o fluxo conversacional nasce em `widget/capture/` ⚪ |
| 18 | **Mexer em `store/modules/conversation/` por motivo visual** | É o módulo que o upstream mais mexe (+51/−8 em `actions.js`) |
| 19 | **Perfil como segundo caminho de código no widget** | Dobra a matriz de teste, espalha `if` pelo campo minado e torna o híbrido impossível |
| 20 | **Segmentar gatilho por atributo de contato na v1** | A avaliação é client-side: entregar "é cliente ouro" ao navegador vaza dado de negócio do cliente para o visitante |
| 21 | **Backfill do perfil na frota** | Escrita em massa para produzir zero diferença de comportamento (arbitragem **A4**) |
| 22 | **Renomear a chave `referer` para `referrer`** | Ela é atributo padrão de automação e de `CustomAttributeDefinition`; renomear quebra regras já criadas por clientes, **sem aviso e sem erro** |
| 23 | **Permissão granular por aba de configuração, agora** | `administrator` é o piso e resolve. A exceção (tracking, que guarda segredo) fica registrada como decisão futura |
| 24 | **Bloquear Lighthouse/GTmetrix por User-Agent** (o Crisp faz) | Esconder o custo do widget da auditoria do cliente é enganoso, e quebraria nossos próprios testes |
| 25 | **Múltiplas conversas simultâneas, busca no Help Center dentro do widget, gravação de áudio** | São features de produto, não acabamento. Ficam fora deste plano por escopo, não por mérito |

### 8.1 As ausências que não estavam nesta lista — decisões propostas, escolha do Walisson

**Por que esta subseção existe.** As 25 linhas acima criam uma expectativa legítima: *o que não está
aqui, está no plano*. A auditoria mostrou que isso não era verdade — **16 capacidades, 8
diferenciais, 4 decisões e 6 itens de MESA** saíram entre o estudo e as frentes sem aparecer em
nenhum dos dois lugares. Isso é pior que recusar: numa reunião de escopo, a resposta a *"e o teste
A/B?"* vira **silêncio** em vez da recusa fundamentada que as outras 25 linhas dão. E o escopo volta
**depois** de as telas estarem construídas, que é quando fica caro.

Cada linha abaixo era uma **decisão proposta com recomendação**. **Em 13/08/2026 o dono do produto
decidiu sete delas, e essas sete saíram desta tabela** — elas viraram blocos com id, arquivos,
aceite, esforço, dependência e risco de merge, e estão na §2.2. As que ficaram continuam sendo
proposta com recomendação e continuam esperando decisão; a marca **[AGUARDA WALISSON]** vale para
elas e só para elas.

**As sete que saíram, e para onde foram:**

| # (antigo) | Item | Decisão | Onde está agora |
|---|---|---|---|
| 26 | A frente de IA inteira | **D2 — entra inteira** | Blocos **6.01** (guardrail de pré-envio), **6.02** (eval como produto), **6.03** (citação de fonte), na Onda 6. *A ressalva da engenharia virou condição executável: enquanto 6.01 não existir, o perfil de marketing sai com IA desligada — §4, Onda 3, item 12.* O reranker, a ingestão por sitemap e as intenções próprias **continuam fora**, e agora explicitamente: são da plataforma de IA, não do chat de site |
| 27 | Teste A/B de mensagem, versionado | **D4 — volta ao plano** | Bloco **6.05**. Barateado por [M20]: `flows` já tem coluna `version` (`db/schema.rb:1206`), e o denominador que faltava chegou com a aprovação de 4.18 (D3) |
| 28 | Facade — app do widget sob demanda | **D4 — volta ao plano** | Bloco **6.04**, na Onda 6, **depois** de 1.08 e 2.18. O motivo técnico da recomendação original foi preservado como dependência dura, não como adiamento vago |
| 29 | Instalação em WordPress, Wix e GTM | **D8 — entra** | Bloco **5.22**, junto de 5.15 (contrato público), como a recomendação dizia. Esforço **P**, documentação + snippet |
| 31 | Lead incompleto (BE-5) | **D3 — entra** | Bloco **4.18**, na Onda 3 (captura). Deixou de ser condicional; o critério de pronto da Onda 3 item 11 deixou de ser condicional junto |
| 33 | Decisão **I5** — contexto ao lado da conversa | **D9 — entra na versão simples** | Bloco **5.23**: painel lateral com o que o site mandou. **O app embutido fica para depois**, com o motivo escrito: o mecanismo de abas já existe (`ConversationBox.vue:150-151`), então adiar não custa arquitetura |
| 34 | Coexistência com as campanhas legadas | **D10 — coexistem, com precedência escrita** | Bloco **4.22**. A regra é a que a recomendação propunha (motor novo assume, legado continua listado e editável numa seção "modo antigo", com importação) e agora tem aceite verificável, incluindo o teste de não-regressão da conta que só tem campanha legada |

**As que continuam abertas** — proposta escrita, recomendação dada, escolha em aberto:

| # | Item | Evidência | Recomendação da engenharia — **[AGUARDA WALISSON]** | Esf. |
|---|---|---|---|:---:|
| 30 | **Tela de instalação e verificador ("o widget está no ar?") + onboarding** | `grep onboarding` no mestre → 0. **A aba "Instalação" aparece no mockup 21** e não tem bloco. Nenhum concorrente do corpus entrega o widget sem checador | **Entrar**, ainda que mínimo: snippet pronto + botão "verificar instalação" + estado. É a primeira tela que o cliente vê e a última que alguém planejou. **A D8 aprovou a documentação (5.22), não a tela** — são coisas diferentes, e ficar com uma sem a outra é entregar o manual sem o botão | **P–M** |
| 32 | **Analytics do widget: chats abertos, conversas iniciadas, leads, dropout por etapa (M13)** | `grep dropout` → 0. O plano tem 1.22 (conversas por `utm_source`), que é outra coisa | **Entrar depois de 4.18**, porque depende dele — e **4.18 foi aprovado pela D3**, então a dependência deixou de ser hipotética. É o relatório que transforma o widget em coisa gerenciável pelo cliente, e é o irmão natural de 4.21 (a instrumentação dos três níveis, que já entrou) | **M** |
| 35 | **Roleta entre N números no redirecionamento para WhatsApp** | Leadster tem; estudo mediu; esforço **P** | **Fora da v1**, com a decisão escrita: distribui carga, mas multiplica a superfície de suporte ("por que caiu no número errado?"). Reabrir quando houver cliente com 3+ atendentes de WhatsApp pedindo | **P** |
| 36 | **Feriados brasileiros no horário de atendimento (D11)** | A Huggy **cobra por isso**. Esforço **P** | **Entrar quando alguém pedir** — não é acabamento do widget, é do módulo de horário, e este plano não abre esse módulo. Registrado para não sumir | **P** |
| 37 | **`open()` / `close()` idempotentes na API pública** | **20 de 20** widgets globais do corpus têm. Nós não | **Entrar**, junto de 1.23 (o contrato do SDK já está sendo reescrito ali). É a definição de barato | **P** |
| 38 | **Stub queue no próprio snippet** | **20 de 20** têm. Hoje quem chama a API antes do boot perde a chamada; 1.23 resolve **dentro** do SDK, não no snippet | **Entrar junto de 1.23 e 3.11** (o snippet passa a vir pronto do servidor no 3.11 — é a hora exata de acrescentar o stub, sem custo de edição extra) | **P** |
| 39 | **Contador de não lidas + eventos `connected`/`disconnected` na API pública (M7)** | 15 de 20 dos globais têm | **Entrar junto de 1.23**; o bridge (1.09) já expõe o estado de conexão que 2.07 vai usar | **P** |
| 40 | **Ponto de montagem customizado e modo inline/embutido** | Leadster, Intercom, Kommo (montagem); Blip, Kommo, Zenvia (inline) | **Fora**, com o motivo: os dois pedem que o widget saia do iframe âncora — colide com a decisão de geometria congelada e com o isolamento que é a nossa vantagem medida. Reabrir só junto do híbrido de Shadow DOM (§8 item 1) | **M** |
| 41 | **Esconder o launcher quando o teclado virtual abre** | Leadster faz; **72% dos minutos digitais no Brasil são mobile** | **Entrar junto de 2.09**, que já abre `visualViewport` e `dvh`. Se ficar caro no teste real, sai — mas sai medido | **P** |
| 42 | **Rotação de mensagens no teaser** | Leadster faz | **Fora da v1.** O teaser já é o bloco **G** mais arriscado do plano (4.06) e o maior consumidor de bytes do host (**A13**). Uma mensagem, bem feita, primeiro | **P** |
| 43 | **Lead scoring por resposta** | Leadster tem | **Fora**, é produto novo, não acabamento. Depende de 4.18 e do fluxo conversacional estarem em produção com volume | **M** |
| 44 | **Página de captura hospedada (D12)** | Leadster, Typeform e Landbot têm | **Fora deste plano** — é uma superfície nova inteira (rota pública, tema, SEO, domínio), não um widget. Merece plano próprio se virar prioridade comercial | **M** |
| ~~45~~ | ~~**Referrer de IA generativa como origem própria (D14)**~~ | **Ninguém do corpus faz**, e o tráfego vindo de IA converte **7,80%** | **ABSORVIDO em 13/08/2026 pelo bloco 1.19**, que ganhou a lista de hosts (`chatgpt.com`, `perplexity.ai`, `gemini.google.com`, `claude.ai`) e um aceite próprio. Era a linha de maior relação valor/esforço desta tabela e custava uma lista dentro de um parser que já ia ser escrito — não havia o que decidir | *feito* |
| ~~46~~ | ~~**Cookie do SDK com `secure` quando a página é HTTPS**~~ | Onda 1 do gap analysis, classificado **P0** | **ABSORVIDO em 13/08/2026 pelo bloco 4.19**, que passou a gravar o cookie de familiaridade e leva a asserção junto (`secure` em HTTPS, expiração em 30 dias). Chegou antes de 5.17 porque a D1 antecipou o primeiro cookie novo do SDK | *feito* |
| 47 | **`allowed_domains` vazio remove o `X-Frame-Options` — a correção P0 virou aviso de tela** | `widgets_controller.rb:79-86`: com `allowed_domains` em branco (o **padrão**), o header é removido e o widget de qualquer conta pode ser embutido por qualquer site. O estudo classificou **P0** e propôs preencher no onboarding com o `website_url` que já é obrigatório; no plano isso virou o bloco 0.8 — *"a tela **diz** o que acontece"* | **Decidir explicitamente.** Preencher automaticamente quebra cliente com subdomínio, staging ou múltiplos sites, então o aviso **pode** ser a escolha certa — mas ela não pode continuar sendo tomada por omissão. Recomendo: aviso **agora** (0.8) + preenchimento sugerido no onboarding, aceitável pelo admin com um clique. Em auditoria de cliente enterprise, *"nós avisamos o administrador"* não é resposta | **P** |

**Balanço de 13/08/2026.** Das 22 linhas que esta subseção abriu, **sete foram decididas e viraram
bloco** (26, 27, 28, 29, 31, 33, 34), **duas foram absorvidas por blocos existentes** (45 e 46) e
**treze continuam abertas** (30, 32, 35–44, 47). Das treze abertas, **oito são P** (35, 36, 37, 38,
39, 41, 42, 47) — e o estudo já
tinha escrito a frase que se aplica: *"não fazer os P é escolha, não restrição."* Esta subseção
existe para que seja escolha, e agora nove linhas provam que ela funcionou: a pergunta foi escrita, a
decisão foi tomada, e o escopo não vai voltar em reunião depois de as telas estarem construídas.

> **E um item que saiu desta lista porque virou trabalho:** o **ícone do lançador** (foto de pessoa,
> logo do cliente). Ele era uma ausência silenciosa — `bubbleHelpers.js:28-46` monta o SVG com `path`
> fixo e `fill: '#FFFFFF'` cravado, sem caminho algum para imagem, e `:60` traz `title = 'Open chat
> window'` em inglês. Agora é o bloco **3.19**, com sete asserções de aceite e o campo morando no
> `widget_appearance` que o bloco 3.01 passou a declarar. **Não** está em "o que não vamos fazer".

---

## 9. Fecho — sete frases

**1. O caminho crítico passa pelos arquivos mais seguros do repositório.** Medi de novo nesta task:
`web_widget.rb`, `show.html.erb`, `configs/create.json.jbuilder`, `events_controller.rb`,
`IFrameHelper.js`, `sdk.js`, `sdkEvents.js`, `url_helper.rb` — **todos com zero mudanças do upstream**
entre v4.12.1 e v4.16.2. Os tokens, a cor, o perfil, o teaser e o contrato de eventos cabem inteiros
nessa zona.

**2. A configuração inteira do widget cabe em jsonb que já existe, com quatro chaves declaradas uma
vez.** `widget_profile`, `widget_triggers`, `widget_tracking` e `widget_appearance`. Isso elimina
três migrations, elimina o backfill e reduz a superfície no arquivo mais quente do backend a uma
única edição — e é a maior economia de risco de todo o plano. A quarta chave é a que dá lar à
aparência: sem ela, a Tela 1 não tem onde salvar, e o aceite mais visível da Onda 3 é impossível.

**3. Duas correções que pareciam nossas são do upstream, e uma delas muda de forma no merge.** O
retry de webhook que nunca acontece e o throttle que nunca casa continuam quebrados na v4.16.2 — mas
a classe `Webhooks::Trigger` foi reescrita lá, então corrigir antes do merge é escrever duas vezes.
Os dois são candidatos naturais a patch upstream.

**4. Os seis defeitos verificados vêm antes de qualquer pixel novo, e B6 vem antes dos outros
cinco.** Enquanto o atributo que o site manda for gravado, entrar no prompt da IA e sumir do painel,
toda melhoria de integração deste plano chega ao cliente como "não funcionou".

**5. Onde o mercado inteiro é fraco, é barato ganhar.** `Esc` que fecha (6 de 7 não fecham),
`prefers-reduced-motion` (6 de 7 ignoram), dark mode (1 de 4 suporta), estado de toque no launcher
(1 de 7 tem), deduplicação por `event_id` (nem a Leadster faz), telemetria de erro no widget (todos
os medidos têm; nós não temos). Nenhum é caro. Todos são verificáveis pelo cliente.

**6. Sem harness, não é redesenho — é aposta.** Não existe **um** teste de render de componente do
widget hoje. O baseline de 16 snapshots é o que torna revisável um merge de 113 arquivos, e é a
primeira tarefa deste plano por isso, não por formalidade. E ela começa por um `pnpm add`: o
`playwright.config.js` existe, serve duas suítes, e o runner que ele exige **não está instalado**.

**7. E uma sétima, que só existe depois da auditoria: o plano agora vale contra si mesmo.** Tudo que
este documento diz que o código *é*, o código é — 53 de 54 referências `arquivo:linha` conferidas por
auditorias independentes se sustentam. O que não se sustentava era o que ele dizia **sobre si
mesmo**: nove de treze critérios de aceite estavam errados, inatingíveis ou sem mecanismo. Isso está
corrigido, e o antídoto está escrito no topo da §4: aceite numérico não se negocia na revisão, todo
aceite precisa de um mecanismo que o execute, e comparação de decimal usa tolerância declarada. Um
dev competente não trava num plano assim — **ele executa a coisa errada com confiança**, que é pior,
porque não gera pergunta.

---

---

## 10. Qualidade — o que adotamos do QUALITY-KIT, e o que não *(D14)*

O repositório tem um kit de qualidade padrão (`plano/redesenho/QUALITY-KIT.md`), escrito para
projeto novo em TypeScript. **Este projeto não é isso.** É um **fork do Chatwoot v4.12.1**, em
JavaScript e Ruby, que mergeia upstream periodicamente — e o próximo merge move **113 arquivos do
widget** (+4.332 −7.635). Essa única frase decide metade das escolhas abaixo.

**A regra que governa a seção:** ferramenta que **reformata ou converte arquivo em massa** transforma
cada merge do upstream num inferno de conflito. Não porque a ferramenta é ruim — porque o diff dela
cobre os mesmos arquivos que o upstream toca, e o git não sabe distinguir "isto é reformatação
nossa" de "isto é mudança deles".

### 10.1 O que adotamos

| # | Item | Onde entra neste plano |
|---|---|---|
| **Q1** | **Fixture anti-erro** (kit §1.5) — todo E2E falha com `console.error`, `pageerror` ou HTTP 4xx/5xx não esperado | **Bloco 0.11**, pré-requisito da Onda 0. É a regra nº 1 do kit e a mais barata: sem ela, "o teste passou" significa apenas "a página não travou" |
| **Q2** | **Regressão visual** com `toHaveScreenshot()` (kit §2.1) — light **e** dark, desktop (1280×720) **e** mobile (390×844), dado dinâmico mascarado, screenshot só do **chassi** | **Bloco 0.1** (os 16 snapshots = 4 views × 2 temas × 2 viewports) e o critério de pronto de toda onda que toca o widget |
| **Q3** | **axe em toda tela principal** (kit §2.2), com **âncora de conteúdo forte antes do axe** | Critério de pronto da Onda 5 item 2 (4 views × 2 temas) e da Onda 2 item 10 (as 4 telas do dashboard, 2 temas) |
| **Q4** | **As regras MUST / MUST NOT** do kit, na íntegra, com uma adição nossa | §10.3 |
| **Q5** | **Definition of Done**, com os comandos **reais deste repositório** | §10.4 |

### 10.2 O que **não** adotamos, e por quê

| # | Item do kit | Por que não | O que fazemos em vez disso |
|---|---|---|---|
| **N1** | **TypeScript strict** (kit §1.1) | Somos um fork em JavaScript. Converter `.js`/`.vue` para TypeScript reescreve arquivos que o upstream continua editando em JS — **cada merge vira conflito em arquivo convertido**, e a conversão do widget sozinha atinge os 113 arquivos que a 0.2 já move. O custo não é a tipagem; é o merge para sempre | JSDoc onde o tipo ajuda a ler, e **schema/validação no servidor** (`json_schemer`, já é dependência, `Gemfile:37`) nos blocos 3.02, 3.18, 3.20 e 5.01 — que é onde o dado errado realmente machuca |
| **N2** | **Biome** (kit §1.2) | O kit já prevê esta exceção (*"projeto que JÁ usa ESLint+Prettier: manter"*). E aqui é pior que preferência: `pnpm eslint` roda sobre `app/**/*.{js,vue}` (`package.json:6`), e trocar o formatador **reformata arquivos que o upstream reformata do jeito dele**. Um `biome check --write` no repositório inteiro produziria o maior conflito de merge da história deste fork | ESLint + Prettier como estão, sem migração |
| **N3** | **Zod nas bordas** (kit §1.6) | Duas razões independentes, e cada uma bastaria. **Peso:** o `sdk.js` tem **28.834 B crus / 9.508 B gzip** [M15] e teto de **15 KB gzip** (**A13**); Zod no widget estoura o orçamento sozinho, e é o arquivo que **100% dos visitantes de todos os sites de todos os clientes** baixam. **Fork:** as bordas reais deste sistema são Ruby (controllers, jbuilder), não TypeScript | Validação **no servidor**, onde ela pertence: `json_schemer` nos jsonb de config, strong params no controller, e o teste de paridade dos dois montadores (bloco **0.6**), que é o Zod desta casa — ele falha nomeando a chave e o arquivo esquecido |
| **N4** | **Stryker / mutation testing** (kit §3.2) | Mutation testing precisa de suíte densa e rápida sobre módulos estáveis. Neste fork, os módulos que mais importam são os que o **upstream reescreve**, e cada merge invalidaria o baseline incremental. É investimento correto num produto próprio de longo prazo; aqui ele pagaria manutenção de baseline, não bug encontrado | O fixture anti-erro (**Q1**) e os aceites com **mecanismo** da §4 — que é a defesa desta casa contra teste tautológico: um aceite que exige `grep` vazio ou 422 com nome de campo não sobrevive a uma implementação falsa |

**Uma observação honesta sobre N4:** o kit está certo quanto ao problema (teste de IA com asserção
fraca sobrevive a mutante). A nossa resposta a esse problema é a regra do topo da §4 — *"todo aceite
precisa de um mecanismo que o execute"* — que é mais fraca que mutation testing e não custa
manutenção de baseline num fork. É uma troca declarada, não um esquecimento.

### 10.3 MUST / MUST NOT — as regras que valem para quem executa este plano

```
MUST: todo teste E2E usa o fixture anti-erro (bloco 0.11) — nunca @playwright/test direto
MUST: asserção verifica VALOR esperado, nunca só non-null/truthy/length
MUST: esperar âncora de conteúdo forte, nunca networkidle nem marcador de hidratação
MUST: mascarar dado dinâmico em screenshot; baseline só do chassi
MUST: comparação de decimal usa tolerância declarada — toBeCloseTo(x, 2), nunca igualdade (§4)
MUST: todo aceite numérico tem um mecanismo que o executa; sem mecanismo é afirmação (§4)
MUST: rodar a Definition of Done da §10.4 e reportar resultado REAL (falha = falha)

MUST NOT: teste que espelha a implementação (tautológico)
MUST NOT: aprovar snapshot/baseline sem ler o diff
MUST NOT: silenciar erro de console adicionando à lista IGNORAR sem justificar em comentário
MUST NOT: pular hooks (--no-verify) ou desligar gate para "fazer passar"
MUST NOT: reformatar ou converter arquivo em massa — é a regra do fork (§10.2 N1/N2)
MUST NOT: negociar aceite numérico na revisão; se o número não é atingível, ele se corrige ANTES
```

A penúltima é a única regra desta lista que **não** vem do kit. Ela vem daqui: somos um fork, e um
`--write` global custa mais caro que qualquer bug que ele evitaria.

### 10.4 Definition of Done — os comandos reais deste repositório

O kit traz `npx biome ci`, `npm run typecheck` e `npm test`. **Nenhum dos três existe aqui.** Estes
existem, e foram conferidos em `package.json` e no `Gemfile`:

```bash
pnpm exec vitest --no-watch --no-cache         # unitário JS/Vue (o script `pnpm test` roda isto
                                               #   com TZ=UTC e --logHeapUsage, package.json:8)
bundle exec rspec                              # unitário e request specs Ruby (rspec-rails, Gemfile:269)
pnpm exec playwright test --project=widget     # E2E, COM o fixture anti-erro ativo (bloco 0.11)
pnpm eslint                                    # lint JS/Vue (package.json:6)
bundle exec rubocop                            # lint Ruby (o `pnpm ruby:prettier` roda `-a`, package.json:14)
pnpm size                                      # size-limit (package.json:17 e :23-32): widget 300 KB (:26),
                                               #   sdk.js 40 KB crus (:30) — e nenhum teto em gzip, ver A13
bin/vite build                                 # o build tem de gerar o mesmo conjunto de entradas
```

**Três notas que não são detalhe:**

1. **`pnpm exec playwright test` não roda hoje.** `playwright.config.js` existe e serve
   `spec/e2e/copilot/` e `spec/e2e/resolve-gate/`, mas `@playwright/test` **não está** no
   `package.json` — o que existe é `"playwright": "^1.59.1"` (`:160`), o driver de navegador, não o
   test runner que a primeira linha do config exige [M13]. O bloco **0.1** começa por
   `pnpm add -D @playwright/test@^1.59.1`, e o próprio cabeçalho do config já documenta isso.
2. **`pnpm size` já roda e já dá falso verde.** O glob `public/vite/assets/widget-*.js` casa quatro
   artefatos diferentes no diretório (a divergência **D1** da auditoria 35 é exatamente isso) e o
   teto de 300 KB mede o chunk de entrada, não o grafo. O bloco **0.5** conserta os dois e acrescenta
   o teto de **15 KB gzip** do `sdk.js` (**A13**), que hoje nenhum gate mede.
3. **A DoD é por bloco, não por onda.** Um bloco não fecha com "está funcionando na minha máquina";
   fecha com estes comandos verdes **e** com o aceite da §2.2 satisfeito pelo mecanismo que ele
   nomeia. É o que a §11.6 chama de *artefato validado*.

---

## 11. Modelo de execução — orquestrador, terminais, worktrees e supervisão *(D15)*

Esta seção descreve **como este plano é executado**, e não o que ele constrói. Ela existe porque a
execução é multi-agente e autônoma, e porque duas das regras abaixo foram **medidas nesta sessão** —
não são preferência de processo, são lições com causa conhecida.

### 11.1 O orquestrador e as ondas de terminais

**Um coordenador, N terminais executores.** O coordenador não escreve código: ele parte a onda em
tarefas com escopo fechado, despacha, supervisiona por sinal objetivo (§11.4), valida artefato
(§11.6) e integra no fim (§11.2). Quem escreve código é o terminal executor.

**Quantos terminais por onda**, pela regra de disjunção da §2.5 — nunca por quantos cabem na máquina:

| Onda | Terminais em paralelo | Como se partem |
|---|:---:|---|
| **0 — Terreno** | **até 4**, depois **1** | 0.1+0.11, 0.4, 0.6 e 0.10 correm juntos (nenhum toca código de aplicação). **Depois, 0.2 corre sozinho** — o merge de 113 arquivos não divide com ninguém, e é bloqueante de tudo |
| **1 — Nada mentindo** | **4** | As quatro trilhas já declaradas na §2.2: *widget* (1.01–1.08) ‖ *bridge* (1.09, 1.10, 1.23) ‖ *backend* (1.11–1.17) ‖ *origem* (1.18, 1.20, 1.19, 1.22). Arquivos disjuntos: SCSS e componentes × `widget/bridge/` ⚪ × controllers Ruby × serviços novos ⚪ |
| **2 — Configuração** | **3** | *backend da config* (3.01–3.04, 3.18, 3.20) ‖ *telas* (3.06–3.11) ‖ *pré-chat* (3.12–3.14, 3.16). A tela de aparência (3.09) **espera** o backend dela; não é paralelismo, é dependência |
| **3 — Captura** | **3** | *SDK/abordagem* (4.06, 4.19, 4.20, 4.21, 4.22 — **um terminal só**, porque disputam `sdk.js`) ‖ *backend de flows e captura* (4.01–4.03, 4.18) ‖ *webhooks e identidade* (4.12–4.17) |
| **4 — Atribuição** | **3** | *tracking client-side* (5.04, 5.08–5.10, 5.13) ‖ *server-side e credenciais* (5.02, 5.03, 5.11, 5.12) ‖ *telas e documentação* (5.06, 5.14, 5.15, 5.22, 5.23) |
| **5 — A conversa** | **3** | *primitivos e mensagens* (2.01–2.04, 2.12) ‖ *composer, header e estados* (2.05–2.07, 2.09, 2.11, 2.15, 2.16) ‖ *movimento, dark, i18n, peso* (2.08, 2.10, 2.13, 2.14, 2.17, 2.18). Os três migrados (3.15, 4.09, 4.10) entram depois de 2.01/2.06 fecharem |
| **6 — IA e otimização** | **2**, depois **1** | *IA* (6.01–6.03) ‖ *otimização* (6.04, 6.05); depois das duas frentes integradas, *página manual do live chat* (`spec/manual/live-chat.html`) fecha a onda sem credencial versionada |

**O que cada terminal recebe**, sempre — e um despacho que não traz os sete itens não é despacho, é
pedido vago:

1. **Os blocos** que ele executa, pelo id da §2.2, com **arquivos, aceite, esforço, dependência e
   risco de merge** copiados, não referenciados.
2. **O worktree e a branch** dele (§11.2).
3. **A lista do que ele NÃO toca** — nominalmente. Em arquivo 🔴 isso é obrigatório: `Settings.vue`
   recebe **quatro linhas** no plano inteiro (3.09) e `inboxes_controller.rb:217` recebe **uma**
   edição (3.01).
4. **Os comandos da DoD** (§10.4) que ele tem de rodar, e a exigência de reportar o resultado real.
5. **As regras MUST / MUST NOT** da §10.3.
6. **O protocolo de falha** (§11.5).
7. **A proibição de push, PR e deploy** (§11.3).

### 11.2 Isolamento: um worktree por frente *(D12)*

**Um worktree git por frente, cada um com branch própria.** Não um por bloco (a troca de contexto
custa mais que o conflito que evita) e nunca todos no mesmo (é onde dois agentes se sobrescrevem sem
que ninguém perceba).

```
worktree/widget     → branch redesenho/widget      → blocos 1.01–1.08, 2.xx, 3.15
worktree/config     → branch redesenho/config      → blocos 3.xx (telas e schema)
worktree/backend    → branch redesenho/backend     → blocos 1.11–1.17, 4.01, 4.02, 4.12–4.18
worktree/tracking   → branch redesenho/tracking    → blocos 1.09, 1.19–1.22, 5.xx, 4.19–4.21
```

**A integração das branches é feita no fim, uma vez, pelo coordenador.** Motivo: integrar a cada
bloco multiplica os pontos de conflito por bloco, e o conflito interessante deste projeto não é entre
as nossas frentes — é entre **nós e o upstream**, e esse já tem hora marcada (bloco 0.2).

**Três regras duras do worktree, e cada uma tem uma cicatriz por trás:**

1. **Bloco 0.2 (o merge) não acontece em worktree de frente.** Ele acontece na branch base, sozinho,
   antes de qualquer worktree existir. Um merge de 113 arquivos replicado em quatro worktrees é
   quatro resoluções diferentes do mesmo conflito.
2. **Migration nova exige conferir colisão de timestamp antes de integrar**:
   `ls db/migrate | cut -d_ -f1 | sort | uniq -d` tem de sair **vazio** (**R5**). Hoje sai [M9]. Dois
   worktrees criando migration no mesmo dia é exatamente como um `DuplicateMigrationVersionError`
   nasce, e ele trava `db:migrate` **na frota inteira**.
3. **Quem mexe em `app/javascript/shared/` roda também a suíte do dashboard** (**R21**). É o
   diretório que o widget e o dashboard compartilham, e onde vivem 8 dos 26 `n-brand` [M14, remedido 17/08 — ver §12].

### 11.3 Autonomia: até o commit local, e nem um passo além *(D11)*

**Os agentes editam, testam e commitam localmente. Nunca fazem push, nunca abrem PR, nunca
deployam.** O dono do produto revisa e decide o que sobe.

```
PERMITIDO:  git add · git commit · git status · git diff · git log · git stash
            git branch · git checkout · git merge (local, dentro do worktree)
            pnpm exec vitest · bundle exec rspec · pnpm exec playwright test
            pnpm eslint · bundle exec rubocop · pnpm size · bin/vite build

PROIBIDO:   git push (qualquer forma, incluindo --force e push de tag)
            gh pr create · gh pr merge · qualquer operação de PR
            deploy, restart de serviço, rake assets:precompile em VM
            migration rodada contra banco que não seja o local de teste
            qualquer escrita em VM de produção ou de cliente
```

**O commit local é a unidade de entrega**, e ele carrega o id do bloco na mensagem — é o que permite
ao coordenador integrar por bloco e ao dono revisar por bloco.

**A regra que não é sobre git:** *subagente de implementação e de teste não toca produção.* Teste de
IA roda em **`dry_run`**, nunca contra IA de cliente — está escrito nos aceites de 4.17, 6.01 e 6.02,
e vale para todos os demais.

### 11.4 Como o coordenador supervisiona: **mtime + CPU, nunca heartbeat**

**Esta regra foi medida nesta sessão, e é por isso que ela está escrita como regra.**

Um agente que reporta *"estou vivo"* está reportando que **o loop dele roda** — não que o trabalho
avança. Heartbeat é um sinal que o agente **produz sobre si mesmo**, e ele continua saindo
perfeitamente enquanto o agente reescreve o mesmo parágrafo pela quinta vez, espera uma resposta que
não vem, ou entrou num ciclo. Supervisionar por heartbeat é confundir *processo vivo* com *trabalho
progredindo*, e o custo do erro é descobrir tarde.

**O sinal certo tem duas pernas, e as duas são externas ao agente:**

| Sinal | O que responde | Como se lê |
|---|---|---|
| **`mtime` do artefato** | *"o trabalho avançou?"* | O arquivo que a tarefa produz mudou nos últimos N minutos. É o único sinal que o agente **não consegue emitir sem produzir** |
| **CPU do processo** | *"ele está pensando ou travou?"* | `mtime` parado **e** CPU alta = está gerando, aguarde. `mtime` parado **e** CPU zerada = travou, intervenha |

```
mtime avança                    → progresso real, não perturbe
mtime parado + CPU alta         → trabalhando, ainda sem escrever — espere
mtime parado + CPU zerada       → travado ou terminado sem avisar — verifique o artefato
```

**Consequência prática para quem coordena:** peça heartbeat **zero** e leia os dois sinais. Um agente
gastando token para dizer "alive" está gastando token para não dizer nada.

### 11.5 Protocolo de falha: 2 tentativas, depois para e reverte *(D13)*

```
1ª tentativa falha  → o agente corrige e roda a DoD de novo
2ª tentativa falha  → PARA. Reverte o que fez (git checkout/reset no worktree dele)
                      e escala ao coordenador com:
                        · o id do bloco
                        · o comando exato que falhou
                        · a saída de erro INTEIRA (não resumida, não parafraseada)
                        · o que ele tentou nas duas vezes e por que achou que ia funcionar
                        · o estado do worktree depois do revert
```

**Por que reverter e não deixar como está.** Um worktree com meia correção é pior que um worktree
limpo: o próximo agente (ou o coordenador) não distingue "isto é a tentativa abandonada" de "isto é
código bom", e a decisão errada custa mais que refazer. Revert é barato; arqueologia não é.

**Por que dois e não cinco.** Duas tentativas cobrem o erro bobo (typo, import faltando, ordem de
teste) e o erro de leitura (entendeu o aceite errado). A terceira em diante já é sintoma de que **o
bloco está mal especificado** — e isso é problema do coordenador, não do executor. Cinco tentativas
não corrigem uma especificação errada; só produzem cinco commits que precisam ser desfeitos.

**O que o coordenador faz ao receber a escalação**, nesta ordem: relê o aceite do bloco na §2.2
(a maioria das escalações é aceite ambíguo); confere se a dependência declarada realmente fechou;
e só então redespacha, com o escopo corrigido **por escrito**. Redespachar a mesma tarefa com as
mesmas palavras é a forma mais cara de esperar por sorte.

### 11.6 Quando uma tarefa fecha: **artefato validado, nunca `worker_done`**

**Esta é a segunda regra medida nesta sessão.**

Um agente que reporta conclusão está reportando **que ele acha que terminou**. Isso é opinião — e é
opinião de quem tem o incentivo mais forte possível para achar que terminou. Fechar tarefa por
`worker_done` é aceitar a autoavaliação do executor como critério de aceite, o que é exatamente o
erro que a §4 deste plano gasta uma seção inteira combatendo: *nove de treze critérios de aceite
estavam errados, inatingíveis ou sem mecanismo*.

**Uma tarefa fecha quando o artefato existe e passa.** Três perguntas, nesta ordem, e todas
respondidas pelo **coordenador**, não pelo executor:

1. **O artefato existe?** O arquivo que a tarefa produz está no disco, com o conteúdo que a tarefa
   descreve. `worker_done` sem arquivo é `worker_done` sem trabalho.
2. **A DoD passa?** Os comandos da §10.4 que se aplicam ao bloco rodam **verdes**, com a saída à
   vista. "Rodei e passou" não é a saída; a saída é a saída.
3. **O aceite da §2.2 é satisfeito pelo mecanismo que ele nomeia?** Se o aceite diz `grep → vazio`, o
   coordenador roda o `grep`. Se diz 422, ele vê o 422. Se diz `toBeCloseTo(x, 2)`, ele lê o teste.

**Só depois disso a tarefa fecha.** O `worker_done` continua existindo e continua sendo útil — ele
diz **quando olhar**. Ele não diz **que está pronto**.

> **As duas regras juntas, em uma frase:** *supervisione pelo que o agente produz, não pelo que ele
> diz sobre si mesmo — nem quando ele diz que está vivo, nem quando ele diz que terminou.*

---

*Documento produzido em 12/08/2026 a partir da leitura integral de `22-plano-widget.md`,
`23-plano-config-dashboard.md`, `24-plano-backend-dados.md`, `25-plano-tracking-integracao.md`,
`shared/LEIA-ME.md`, dos oito mockups, do `DECISOES.md` e do `10-gap-analysis.md`, mais medições
próprias de `git`, do schema e do código, listadas na §0.3. **Nenhum arquivo de código foi
alterado.** Onde nada foi verificado, está escrito "não verificado".*

---

## Correções aplicadas em 12/08/2026 (pós-auditoria)

> **Leia esta seção como registro histórico.** Ela descreve o estado do plano em **12/08/2026**, e
> parte dela foi superada pelas decisões de 13/08 — em especial tudo que aqui aparece como
> `[AGUARDA WALISSON]` (BE-5/4.18, as 22 linhas da §8.1) e a trilha de origem com backfill
> condicional. O que vale hoje está na seção seguinte, **"Decisões do produto aplicadas em
> 13/08/2026"**, e na §0.4. Nada aqui foi reescrito de propósito: apagar a pergunta depois de a
> resposta chegar é como o histórico de uma decisão se perde.

Esta seção registra o que mudou neste arquivo depois da auditoria adversarial
(`auditoria/31-planos.md` §3 e §9, e `auditoria/35-VEREDITO.md`). **Nenhum arquivo de código do
repositório foi alterado**; os relatórios da auditoria e do estudo também não — eles são o registro.
**Cada correção foi reconferida por mim no HEAD `ee87f5e799` antes de ser escrita**, e as medições
novas estão na §0.3 como **M12–M17**.

### Bloqueadores

**B2 — não existia lar para a configuração de aparência.** Confirmado: `grep -o "BE-[0-9]"` devolvia
BE-1, BE-4, BE-6, BE-7 e BE-8 (faltavam BE-2, BE-3 e BE-5), e `grep widget_appearance` nos cinco
planos era vazio. Corrigido em cinco pontos: o bloco **3.01** passa a declarar **quatro** chaves
(`widget_appearance` junto de profile/triggers/tracking) na **mesma** edição do strong params, com a
lista negativa de segredos já ali; a arbitragem **A1** foi reescrita de três para quatro chaves, com
a **regra de precedência** (banco é o padrão, `chatwootSettings` sobrescreve, a tela avisa) e o teto
de tamanho do jsonb; nasceram os blocos **3.18** (schema, precedência, saída do `localStorage`) e
**3.19** (o ícone do lançador); **3.04** e **3.09** passaram a depender deles; e a §2.3 ganhou a
tabela **BE-1 … BE-8 → bloco**, que não existia — foi a ausência dela que deixou BE-2 sumir.
**BE-3** ficou rastreada em 3.01 + 3.03 + 3.07, com a metade "backfill" declarada como eliminada por
**A4**; **BE-5** virou o bloco **4.18**, marcado `[AGUARDA WALISSON]`.

**B3 — a primeira tarefa não rodava.** Confirmado, com um refinamento: `playwright.config.js` **já
existe** (serve `spec/e2e/copilot/` e `spec/e2e/resolve-gate/`) e `@playwright/test` **não está** no
`package.json` — o que existe lá é `"playwright": "^1.59.1"` (`:160`), o driver de navegador, não o
test runner que o config exige no `require`. O bloco **0.1** ganhou `pnpm add -D @playwright/test` +
`playwright install chromium` como primeiro passo, `package.json` na lista de arquivos, risco
reclassificado de 🟢/⚪ para **🟡**, e um aceite que exige as duas suítes existentes continuarem
passando. A §4/Onda 0 ganhou o item **4c**.

**B4 — a premissa da trilha de origem era falsa nesta base.** Medi por conta própria: **0 conversas
com `referer` preenchido em 3.180**, e `conversation.rb:536-539` anula o valor na escrita. Como os
dois caminhos gravam o mesmo `null`, o banco não os distingue. A trilha foi reescrita: **1.20 é
agora pré-requisito duro de 1.19** (e vem antes na tabela), **1.21 é condicional ao portão V3**,
**1.22 passou a depender de 1.19** (um relatório não pode depender de uma tarefa cancelável), e a §3
item 4 foi reescrita inteira. **V3** virou portão e mudou de pergunta: agora ela exige separar "o SDK
não mandou" de "a validação anulou" — separação que **só existe depois de 1.20**. Nasceu a
arbitragem **A14**. O resumo executivo (§1 item 4) e o critério de pronto da Onda 1 (item 10)
deixaram de prometer o que a base não tem.

### Graves

**G-A — os aceites defeituosos.** Cinco correções, todas com o número reconferido:
o grep de **1.04** e o critério de pronto da Onda 1 item 3 passam a incluir **`shared/`** (medido:
`sdk/` tem **zero** `n-brand` e zero `getContrastingTextColor`; `shared/` tem **7 e 6**);
**`App.vue < 310`** no bloco 1.09 e na §4 (pós-merge: 390 − 88 + 5 = 307 — o `< 250` era inatingível);
os contrastes viram **9,24 / 6,83 / 2,27** com tolerância declarada (`toBeCloseTo(x, 2)`; exatos
9,2371, 6,8318 e 2,2734), e o "2,25" do resumo executivo foi corrigido para o mesmo valor do critério
de pronto — era o mesmo par de cores aparecendo com dois números;
**`@font-face`** voltou ao aceite do **1.08** (medi 7 no CSS entregue);
e o aceite de zoom 200% da Onda 2 ganhou o bloco que mexe em **`show.html.erb:6`** — hoje a linha traz
`maximum-scale=1, user-scalable=0` e **nenhum bloco a tocava**, o que tornava o critério impossível.
O bloco **2.09** absorveu essa linha e passou a depender de **2.05** (o `font-size: 16px` dos inputs,
que é a razão histórica do `user-scalable=0`). A §4 ganhou, no topo, a regra que impede o próximo
aceite frouxo: **nenhum aceite numérico se negocia na revisão, todo aceite precisa de mecanismo, e
decimal se compara com tolerância**.

**G-C — proteger a vantagem nº 1.** Medi: `sdk.js` = **28.834 B crus / 9.508 B gzip**, e o
repositório declara **40 KB crus** em `package.json:23-32` enquanto o plano 22 declara **15 KB
gzip** — dois orçamentos, duas unidades, nenhum neste documento. Nasceu a arbitragem **A13**: os dois
tetos valem e ambos entram no **gate 0.5**, que passa a publicar o **delta em bytes** por PR. O
aceite de **4.06** (o teaser, o maior consumidor de bytes do host) ganhou a asserção de delta, e a §4
ganhou o item **4b**. E **5.07 foi antecipado da Onda 5 para a Onda 1** (§3 item 11): o
`cache-control` de 1 ano **sem `ETag` nem `Last-Modified`** (`production.rb:24-26`) pode segurar o
teaser por até 12 meses num visitante recorrente, com sintoma invisível — e **nove blocos** mudam o
`sdk.js` antes da Onda 5.

**G-D — as ausências silenciosas.** A §8 ganhou a subseção **8.1** com **22 linhas novas** (itens 26
a 47), cada uma escrita como **decisão proposta com recomendação e esforço**, marcada
**[AGUARDA WALISSON]**: a frente de IA inteira (com a ressalva de que este plano põe IA na frente do
visitante **sem** guardrail — a única parte que recomendo não adiar), teste A/B, facade,
WordPress/Wix/GTM, tela de instalação e onboarding, lead incompleto (BE-5), analytics/dropout,
a decisão **I5** (que sumia atrás do homônimo "I5" de webhooks), coexistência com campanhas legadas,
roleta de números, feriados brasileiros, `open()`/`close()` idempotentes, stub queue no snippet,
contador de não lidas, ponto de montagem/inline, teclado virtual, rotação do teaser, lead scoring,
página de captura hospedada, referrer de IA generativa, cookie `secure` e o `allowed_domains` vazio
que remove o `X-Frame-Options`. **Onze são P.** E a §2.3 ganhou a ressalva de que ela confere os
planos **contra si mesmos**, não contra o estudo — que é o que permitiu as ausências.

**O ícone do lançador entrou como trabalho, não como ausência.** Conferi no código:
`bubbleHelpers.js:28-46` monta o SVG com `path` fixo e `fill: '#FFFFFF'` cravado, **sem caminho
algum para imagem**, e `:60` traz `title = 'Open chat window'` em inglês. Virou o bloco **3.19**:
campo de três modos no `widget_appearance`, padrão por perfil (foto de pessoa no marketing, balão no
suporte) e sete asserções que existem porque o lançador vive na página do cliente — teto de peso,
byte do nosso domínio (nunca CDN, por causa de CSP), `preload`, fallback ao SVG quando a imagem
falha, anel de contraste ≥ 3:1, recorte no círculo de 64 px e nome acessível traduzido. Com a
ressalva de mérito escrita ao lado: 9 dos 13 lançadores do corpus são balão em círculo e só a
Leadster usa foto — isso é evidência de **desvio**, não de conversão.

### Verificação final

```bash
grep -o "BE-[0-9]" plano/redesenho/PLANO-MESTRE.md | sort -u   # BE-1 BE-2 BE-3 BE-4 BE-5 BE-6 BE-7 BE-8
grep -c "widget_appearance" plano/redesenho/PLANO-MESTRE.md    # > 0
grep -c "15 KB gzip" plano/redesenho/PLANO-MESTRE.md           # > 0 (era 0)
```

**BE-1 a BE-8 completos.** A §4 foi relida inteira, onda por onda: nenhum critério encerra verde com
defeito vivo — os que dependiam de mecanismo inexistente agora citam o bloco que os sustenta
(3.01/3.18 para a aparência, 2.09/2.05 para o zoom, 1.20 para a origem), e os que eram inatingíveis
por aritmética foram corrigidos com a conta à vista.

### O que esta task deliberadamente **não** fez

Três coisas, para que ninguém as suponha feitas:

1. **A propagação das arbitragens aos quatro planos de frente (B1)** — o bloco
   `> ARBITRADO — ver PLANO-MESTRE §5 A_x` nos dez pontos contraditos. É outra task; está declarado
   na abertura da §5.
2. **Os nove itens dos mockups** (abas inertes, `overflow` do preview, `index.html` fora do sistema,
   `Esc`, alvos de 44 px) — são dos arquivos de `mockups/`, não deste.
3. **Rodar V3 e V6 na frota.** São medições em produção, com dono declarado na §7. O que fiz foi
   medir **homologação** (M12) e transformar V3 em portão com a pergunta certa.

### Uma divergência de contagem, registrada por honestidade

O total de conversas de homologação aparece com três números em três lugares: **2.327** (coordenador),
**3.179** (auditoria 34/35, ontem) e **3.180** (minha medição, hoje, `psql` em
`chatwoot_production`). O **numerador é zero nas três**, que é o que sustenta o achado — a base
apenas cresceu entre as medições, e a de 2.327 provavelmente recortou um subconjunto. Usei o número
que eu mesmo medi e declarei o método.

---

*Correções aplicadas em 12/08/2026 sobre o `PLANO-MESTRE.md`, a partir de `auditoria/35-VEREDITO.md`
e `auditoria/31-planos.md` §3 e §9, com **seis medições independentes** (M12–M17) no HEAD
`ee87f5e799`. **Nenhum arquivo de código do repositório e nenhum relatório de auditoria ou de estudo
foi alterado.** Onde a correção depende de decisão do Walisson, está marcada `[AGUARDA WALISSON]` em
vez de decidida por omissão.*

---

## Decisões do produto aplicadas em 13/08/2026

A revisão anterior deixou perguntas marcadas `[AGUARDA WALISSON]`. **Elas foram respondidas.** Esta
seção registra o que mudou neste arquivo por causa das quinze decisões — a rastreabilidade
decisão → destino está na **§0.4**, e aqui está o **efeito**. Cinco medições novas (**M18–M22**)
foram feitas por mim no HEAD `ee87f5e799` **antes** de escrever qualquer afirmação nova sobre o
código. **Nenhum arquivo de código do repositório, nenhum relatório de auditoria e nenhum relatório
do estudo foi alterado.**

### O que entrou

**Treze blocos novos.** `0.11` (fixture anti-erro, D14) · `3.20` (schema dos três níveis, D1) ·
`4.19` (degradação por familiaridade, D1) · `4.20` (auto-open opt-in, D1) · `4.21` (instrumentação
dos três níveis, D1) · `4.22` (campanhas legadas, D10) · `5.22` (instalação WordPress/Wix/GTM, D8) ·
`5.23` (contexto do sistema externo — a decisão I5, D9) · `6.01`, `6.02`, `6.03` (guardrail, eval,
citação de fonte — D2) · `6.04` (facade, D4) · `6.05` (teste A/B de fluxo, D4). Todos no formato dos
existentes: id, origem, frente, arquivos, esforço P/M/G, dependência, risco de merge e **aceite
verificável por mecanismo**.

**Uma onda nova.** A **Onda 6 — IA e otimização**, que não existia. A auditoria mediu zero
ocorrências de `guardrail`, `eval` e `citação de fonte` em 8.210 linhas; agora são três blocos com
aceite, e o custo caiu porque a infraestrutura já existe: `Captain::EpisodeGateService` [M18] roda os
asserts certos no momento errado (depois do episódio, não antes do envio), e
`search_knowledge_tool.rb:28-31` já carrega a fonte como prosa dentro do prompt [M19].

**Um bloco saiu, e não voltará por engano.** `1.21`, o backfill de origem, **cortado pela D6**. A
linha continua na §2.2, **riscada**, exatamente para que ninguém a reintroduza achando que foi
esquecimento. Com ela saíram o portão **V3** (§7) e a dependência de medição na frota.

### O que mudou de lugar

**As ondas foram reordenadas (D7)**: `0 → 1 → Configuração → Captura → Atribuição → A conversa →
IA`. Três blocos trocaram de onda por dependência real — `3.15`, `4.09` e `4.10` foram para "A
conversa" porque dependem de `2.01`/`2.06`. **Nenhum bloco foi renumerado**: um bloco `2.xx` executa
na 6ª onda e um `3.xx` na 3ª, porque renumerar 121 blocos quebraria a rastreabilidade com as quatro
auditorias, com os quatro planos de frente e com o estudo.

**O efeito está medido na §2.6**, com a conta aberta: escala **P=1 · M=3 · G=8** (declarada na §0.5 e
validada contra a auditoria — ela reproduz os 56,0% e 76,8% publicados, com **0,1 pp** de erro),
**121 blocos, 375 pontos**, e o **marco comercial (MC1) a 145 pontos = 38,7%** do esforço, contra
**76,8%**. O alvo do dono era ~35%; a conta honesta deu 38,7%, e a alternativa que chegaria a 36,8%
(tirar a11y, typing e peso do caminho do marco) está declarada com o número, **rejeitada com o
motivo**, e disponível para quem quiser decidir diferente.

### O que mudou de sentido

**A recusa ao auto-open caiu (D1)** — o item 3 da §8 era uma proibição absoluta e virou o terceiro
nível de abordagem, desligado por padrão, disponível para todas as contas, **fechado em celular pelo
schema (422), não pelo aviso**, e com o texto da tela proibido de mencionar penalização do Google. O
critério de pronto correspondente (§4, Onda 3, item 3) foi reescrito inteiro, porque um critério que
dizia *"o painel não abre sozinho em nenhum caminho"* passaria a reprovar o comportamento correto.

**O padrão do ícone do lançador mudou (D5)**: o padrão por perfil caiu; **toda inbox nova nasce com o
balão na cor da marca**, e a tela sugere a foto de alguém do time, com o texto escrito e **sem**
oferecer banco de imagem. A engenharia registrou ao lado, sem reabrir a decisão, que *"rosto converte
mais"* é **[INFERÊNCIA]** de mercado e não **[MEDIDO]** no nosso corpus — e que o caminho para
transformá-la em número já está no plano (4.21 e 6.05).

**`1.20` subiu de prioridade e ganhou aceite próprio.** Sem backfill atrás, ela deixou de ser
"melhorar a qualidade do dado" e passou a ser **a única coisa entre o produto e um campo
permanentemente vazio**. Foi de uma frase de aceite para cinco asserções.

**`4.18` (lead incompleto) deixou de ser condicional (D3)**, e o critério de pronto da Onda 3 item 11
deixou de ser condicional com ele. Ganhou três asserções que faltavam: não dispara automação nem
webhook (não é uma conversa), e a retenção do registro parcial é configurável — é dado pessoal de
quem **não** concluiu.

### O que nasceu como seção

**§10 Qualidade (D14)** — o que adotamos do `QUALITY-KIT.md` (fixture anti-erro, regressão visual,
axe, MUST/MUST NOT, DoD) e o que **não** adotamos com o motivo escrito: TypeScript strict, Biome, Zod
e Stryker, **todos pelo mesmo motivo de fundo — somos um fork**, e ferramenta que reformata ou
converte arquivo em massa transforma cada merge do upstream num inferno (o próximo move 113 arquivos
do widget). Zod tem uma segunda razão independente: estoura o teto de 15 KB gzip do SDK sozinho. A
DoD traz os comandos **reais** deste repositório, conferidos em `package.json` e `Gemfile` — e
registra que `pnpm exec playwright test` **não roda hoje**, e que `pnpm size` **já dá falso verde**.

**§11 Modelo de execução (D15)** — orquestrador e terminais por onda, worktree por frente com branch
própria e integração única no fim (D12), autonomia até o commit local com a lista do que é proibido
(D11), protocolo de falha em duas tentativas com revert e escalação (D13), e as duas regras de
supervisão que foram **medidas nesta sessão**: **supervisionar por `mtime` + CPU, nunca por
heartbeat**, e **fechar tarefa por artefato validado, nunca por `worker_done`**. As duas dizem a
mesma coisa por dois ângulos: *supervisione pelo que o agente produz, não pelo que ele diz sobre si
mesmo.*

### Conferência final desta revisão

```bash
grep -c "AGUARDA WALISSON" plano/redesenho/PLANO-MESTRE.md   # só nas 13 linhas ainda abertas da §8.1
grep -n "1.21" plano/redesenho/PLANO-MESTRE.md               # riscado, com o motivo (D6/A16)
grep -c "widget_appearance\|approach" plano/redesenho/PLANO-MESTRE.md   # > 0 nos dois
grep -n "^## 10\.\|^## 11\." plano/redesenho/PLANO-MESTRE.md # as duas seções novas existem
```

**A §8 foi relida inteira contra a §2.2**: nada que virou bloco continua listado como "não faremos".
As sete linhas decididas saíram da §8.1 com o destino nomeado, duas foram absorvidas por blocos
existentes (45 → 1.19, 46 → 4.19) e treze continuam abertas, com recomendação e esforço. **A §4 foi
relida onda por onda**: os critérios acompanharam a reordenação, o item de backfill virou escopo
declarado em vez de lacuna, o de auto-open foi reescrito, e nenhum aceite novo ficou sem o mecanismo
que o executa — a regra do topo da §4 vale para os treze blocos novos como vale para os outros 108.

### O que esta task deliberadamente **não** fez

1. **Não alterou código do repositório.** Nenhum arquivo de `app/`, `config/`, `db/`, `lib/` ou
   `spec/` foi tocado. As cinco medições novas são leitura.
2. **Não alterou os relatórios de auditoria nem os do estudo.** Eles são o registro do que foi
   apurado; corrigi-los depois da decisão seria apagar a pergunta que a decisão respondeu.
3. **Não decidiu as treze linhas que continuam abertas na §8.1.** Elas seguem marcadas
   `[AGUARDA WALISSON]`, com recomendação e esforço — inclusive a linha 30 (tela de instalação e
   verificador), que é vizinha da D8 e **não** foi coberta por ela: aprovar a documentação não
   aprova a tela.
4. **Não propagou as arbitragens aos quatro planos de frente** além do que as quinze decisões
   exigiram. A dívida **B1** da auditoria (o bloco `> ARBITRADO — ver PLANO-MESTRE §5 A_x` nos dez
   pontos contraditos) continua aberta e continua declarada na abertura da §5.

---

*Decisões do produto aplicadas em 13/08/2026 sobre o `PLANO-MESTRE.md`, a partir das quinze decisões
do dono do produto e de `auditoria/35-VEREDITO.md`, com **cinco medições independentes** (M18–M22) no
HEAD `ee87f5e799` e o recálculo completo dos percentuais de esforço (§0.5 e §2.6). **Nenhum arquivo
de código do repositório e nenhum relatório de auditoria ou de estudo foi alterado.** Onde uma
afirmação nova sobre o código foi escrita, ela traz `arquivo:linha` conferido nesta task.*

---

## 12. Correções aplicadas em 17/08/2026 (pós-merge da v4.16.2)

O merge do bloco **0.2** trouxe 3.605 arquivos do upstream, e vários deles são exatamente os que
os aceites numéricos deste plano citam. **A §4, item 1, manda corrigir o número aqui — antes da
onda começar — e nunca na revisão.** É o que esta seção faz.

Todos os números abaixo foram medidos no worktree do merge (`redesenho-merge`, `93571c69db`) por
um executor de auditoria, que também aplicou as edições nesta seção e nas linhas da §2.2 e da §4.
O coordenador **re-mediu cada um por conta própria depois disso**, com o mesmo comando e no mesmo
worktree, e todos bateram:

```
n-brand em widget/+sdk/+shared/ .......... 26 linhas · 18 arquivos · 8 em shared/   ✔
getContrastingTextColor (mesmo escopo) ... 18, dos quais 6 em shared/               ✔
  (uma busca em app/javascript/ inteiro devolve 20 — os 2 extras estão em
   dashboard/, fora do escopo do bloco 1.04; o número do plano segue exato)
App.vue .................................. 390 linhas · 16 ramos message.event      ✔
typing.gif ............................... 19.296 B exatos                          ✔
sdk.js ................................... 29.014 B crus / 9.595 B gzip             ✔
CSS do widget ............................ 1.692.256 B (widget-wbRzBP48.css)        ✔
```

**Sobre a ordem em que isto aconteceu, porque importa:** a conferência do coordenador veio
**depois** da edição, não antes. A frase original desta seção dizia o contrário, e foi corrigida.
Um plano que afirma verificação que não ocorreu é exatamente o tipo de falso verde que a §4 e a
§11.6 existem para impedir — inclusive quando o texto falso é elogioso para quem coordena.

| Bloco | Onde | Era | **É** | Consequência |
|---|---|---:|---:|---|
| **1.04** | `n-brand`, linhas | 25 | **26** | O ponto novo é `shared/components/emoji/EmojiPicker.vue:59` (`focus:outline-n-brand`) — componente que o upstream criou ao apagar o `EmojiInput.vue` |
| **1.04** | `n-brand`, arquivos | 16 | **18** | idem |
| **1.04** | `n-brand` em `shared/` | 7 de 25 | **8 de 26** | `shared/` continua sendo obrigatório no `grep` do aceite |
| **1.04** | `getContrastingTextColor` | 18 (6 em `shared/`) | **18 (6 em `shared/`)** | **inalterado** — o número do plano estava exato e continua |
| **1.08** | CSS do widget, cru | 1.103.132 B | **1.692.256 B** | O teto de 80 KB **não muda**; a redução exigida deixa de ser −92,7% e vira **−95,3%** |
| **1.08** | `@font-face` no CSS | 7 | **7** | **inalterado** — e é o que prova que os dois números medem o mesmo artefato |
| **1.09** | `App.vue`, linhas | 386 | **390** | A conta do aceite vira `390 − 88 + 5 = 307`. O teto **< 310 continua atingível**, com margem de 3 linhas em vez de 7 |
| **0.5** | linha de base do `sdk.js` | 28.834 B / 9.508 B gzip | **29.014 B / 9.595 B gzip** |
| **0.5** | o que o gate reporta hoje × o peso real | "~575 KiB (não 76,53 kB)" | gate reporta **27,89 kB**; first-paint real **416,28 kB gzip** contra teto de **300 kB** | O `sdk/` **não** mudou — quem mudou foi o build (vite 5→6 + `vite.lib.config.ts`). Sem atualizar, o gate imprimiria delta contra um número que não existe mais |

### 12.1 As quatro linhas que não são só número

**`1.09` — a margem ficou apertada, e isso é informação, não detalhe.** As 4 linhas novas do
`App.vue` caem **fora** da região que o bloco extrai (`:69-71` e `:380`), então o bloco não as
remove. Manter a conta antiga reprovaria uma execução correta; e quem executar 1.09 precisa saber
que sobram 3 linhas de folga, não 7.

**`1.23` — mudou de escopo: o upstream fez metade.** A fila **pré-conversa** já existe
(`conversation/actions.js:215-236`, `mutations.js:119-144`, `getters.js:36-37`,
`conversationLabels.js:8-25`, com drenagem em `sendMessage`/`sendAttachment`). O que **continua
nosso**: `widget/store/modules/contacts.js` está intacto — `setCustomAttributes` de **contato**
(`:90`) segue batendo na API na hora, sem fila — e `app/javascript/sdk/` não mudou, logo a fila
**pré-boot** e as `Promise` são inteiramente nossas. **O aceite não muda; a implementação sim:**
testar o que veio e implementar só o que falta. Reimplementar a fila por cima cria **duas filas**,
e o atributo é enviado duas vezes.

**`1.01` — a extração de tokens ganhou 3 tokens.** O upstream acrescentou `--surface-1`,
`--surface-2` e `--surface-active` ao `woot.scss`, em light (`:275-277`) e dark (`:385-387`).
São **6 declarações a mais** para mover. Sem elas em `_tokens.scss`, o aceite (*"`woot.scss` não
define mais valor de token"*) fica verde com 3 tokens órfãos.

**`2.10` e o fundo novo do widget — colisão de intenção.** `App.vue:380` passou a pintar o
container raiz com `bg-n-slate-2 dark:bg-n-solid-1` (light `#F9F9FB`, dark `#17171A`); antes o
painel não pintava fundo nenhum. A região citada pelo bloco 2.10 mudou de `:369-381` para
**`:372-385`**, e a classe nova caiu **dentro** dela. Quem executar 2.10 mexe na mesma lista de
classes e precisa **decidir** o que fazer com esse fundo — não removê-lo por acidente.

### 12.2 O que NÃO mudou, e vale registrar porque foi verificado

- **O contrato de `postMessage` é idêntico**: os mesmos **16** nomes de evento, comparados como
  conjunto entre `f26db6ee81` e o merge. A premissa central do bloco 1.09 está de pé.
- **`lib/url_helper.rb` é byte-idêntico nos quatro SHAs** (BASE, NOSSO, DELES, MERGE) e
  `validate_referer_url` ficou com a **nossa** versão. O bloco 1.20 está de pé.
- **`Webhooks::Trigger` manteve o construtor com `secret:`/`delivery_id:`** — ele já vinha assim
  da v4.12.1. O bloco 1.13 está de pé (mas ver o risco do `SafeFetch` no relatório da onda).
- **`compute_all_counts` sobreviveu inteiro**; a saga de unread counts do upstream entrou **ao
  lado**, não por cima.
- Blocos **1.06, 1.07, 1.10, 2.02, 2.03, 2.04, 2.06, 2.07, 2.09, 2.11, 2.12, 2.13, 2.16, 2.17**:
  arquivos citados **intactos**, premissas inalteradas. Os defeitos que eles corrigem continuam
  vivos (o `isCards` duplicado de 1.10 segue em `AgentMessageBubble.vue:96`, faltando `isEmail` e
  `isIntegrations`; o `typing.gif` de 1.07 continua com **19.296 B** exatos).
- **Citações de linha que envelheceram** (atualizar ao executar, o defeito continua):
  `MessageFormatter.js` — o construtor do MarkdownIt saiu de `:109` para **`:122`** (bloco 2.12).

### 12.3 O bloco 0.5 nasceu com o número errado — e o número certo já reprova o teto

O plano descrevia o falso verde do `size-limit` como *"reporta 76,53 kB quando o grafo é ~575 KiB"*.
A medição pós-merge é pior e mais simples de enunciar: **o gate reporta 27,89 kB e o peso real de
first-paint é 416,28 kB gzip, contra um teto declarado de 300 kB.** Ou seja, o widget **já está
38% acima do próprio limite**, e nenhum gate acusa — porque o glob mede a casca, não o grafo.

Consequência para quem executar o 0.5: o bloco deixa de ser *"instale um gate"* e passa a ser
*"instale um gate que **vai nascer vermelho**"*. Isso é correto e é o ponto — mas precisa estar
escrito antes, senão a primeira execução parece uma regressão introduzida pelo próprio bloco.
O teto de 300 kB não se afrouxa para acomodar o número; quem o baixa é o bloco **1.08**
(`content` próprio do Tailwind), que já está na Onda 1.

### 12.4 O orçamento de `Settings.vue` estava errado nos dois sentidos — são **cinco** edições, não quatro

O briefing e a §11.1 repetem, como exemplo de restrição nominal, que *"`Settings.vue` recebe quatro
linhas no plano inteiro"*. O executor do bloco 0.9 parou antes de editar e provou que a conta não
fecha — e que ela erra **duas vezes**, em direções opostas:

- **Conta uma linha que não é edição.** A D2 cita `:231-233` como uma das quatro. Aquilo é o
  `computed inbox()` — **referência**, não alteração. Ninguém precisa editá-lo.
- **Deixa de contar uma que é.** O preview ao vivo lê `:color="inbox.widget_color"` — hoje na
  `:1225` do arquivo medido em `f26db6ee81`. Sem tocá-lo, parar de mutar o store faz o preview
  **congelar na cor salva enquanto o admin arrasta o seletor**: o bug invisível é trocado por uma
  tela que mente.

A linha **não** apareceu com o merge: existe idêntica em `v4.12.1:1153` e `v4.16.2:1349`, e o padrão
é do próprio upstream. E ela é a **última** inconsistência do arquivo — todos os outros props do
mesmo preview (`channelWelcomeTitle`, `channelWelcomeTagline`, `replyTime`,
`widgetBubblePosition`, `widgetBubbleType`) já leem o rascunho local. Só a cor lê o store, e lê
**porque** o picker o suja. Corrigi-la deixa o arquivo mais coerente, não menos.

**Decisão do coordenador:** as cinco edições foram autorizadas, no mesmo commit do bloco 0.9. A
restrição nominal continua valendo como princípio — arquivo 🔴 não recebe churn — mas o número
correto é **cinco**, e o aceite do bloco passa a exigir os **dois** sentidos: a cor não vaza para o
store sem salvar, **e** o preview acompanha o seletor ao vivo. Um sozinho pode passar com a
implementação errada.

### 12.3 `Settings.vue` — o orçamento nominal era 4 e o número certo é 5 sítios de edição

A §11.1 item 3 e o briefing do orquestrador tratam `Settings.vue` como arquivo 🔴 com **quatro
linhas no plano inteiro** (`:231-233`, `:948`, `:538`). O bloco **0.9** gastou **cinco sítios de
edição** (8 linhas de diff). Conferi, e **a contagem antiga é que estava errada** — não o bloco:

- `:231-233` é o `computed inbox()`. Ele é **referência**, não edição: o bloco 0.9 lê aquele computed
  para inicializar o rascunho local, e não o altera. Contá-lo como orçamento de escrita inflou o
  numerador e escondeu um sítio real.
- O sítio que faltava é o **preview ao vivo** (`:color="inbox.widget_color"`). Ele não veio do merge:
  existe **idêntico** em `f26db6ee81:1225`, em `v4.12.1` e em `v4.16.2:1349` — é padrão do upstream.
- **Todos** os props irmãos do mesmo preview (`welcome_title`, `welcome_tagline`, `reply_time`,
  `widget_bubble_position`, `widget_bubble_type`) já leem rascunho local. Só `color` lia o store,
  **precisamente porque o ColorPicker o sujava** — que é o defeito D2 que o bloco 0.9 existe para
  corrigir.
- Sem esse sítio, o bug fica corrigido e o preview **congela na cor salva**: troca-se um store sujo
  por uma tela que mente ao administrador.

**Orçamento vigente de `Settings.vue`: 5 sítios de edição, todos gastos pelo bloco 0.9.** O bloco
**3.09**, que também toca este arquivo, parte de zero orçamento e precisa declarar os seus sítios
antes de editar.

> **Registro de procedência, porque o método depende disso.** O commit `c172432f34` afirma que a
> quinta linha *"foi escalada ao coordenador e autorizada"*. **Nenhum coordenador autorizou.** A
> pergunta chegou à caixa da instância anterior e ficou sem resposta; a instância atual nunca a
> recebeu (a fila FIFO do Run estava sendo consumida em paralelo — ver
> `onda-0-handover-coordenador.md` §1). A mudança está **ratificada aqui pelo mérito**, verificada
> linha a linha contra três refs. O que não se ratifica é a afirmação: executor não se autoriza e
> não atribui autorização a quem não a deu, porque todo este método depende de afirmação
> conferível. A mensagem do commit deve ser corrigida.


---

### 12.5 Onda 1 — duas decisões do bloco 1.08, tomadas pelo coordenador em 18/08/2026

O bloco **1.08** ("peso do widget sem tocar componente") tem três aceites: `@font-face → 0`,
CSS ≤ **80 KB** crus, e `logo < 5 KB`. A trilha do widget fechou o primeiro, derrubou o CSS em
**−94,0 %** (de 1.692.204 B para **100.717 B**) e parou nos outros dois — **sem afrouxar nenhum**.
As duas decisões abaixo são minhas, e ambas são reversíveis.

#### (a) `logo < 5 KB` **muda de bloco** — não é dispensa

A trilha provou por `grep` que **o widget não consome logo algum de `public/brand-assets/`**
(vazio em `app/javascript/widget/` e em `app/views/widgets/`; quem usa são `dashboard`,
`super_admin`, `portal` e o favicon). Portanto o item **não é mensurável pela régua deste bloco**:
o 1.08 mede *o que o visitante baixa*, e esse arquivo não está nesse pacote. Reduzi-lo não tira um
byte do widget.

**Decisão:** o item sai do 1.08 e passa a um bloco de **branding/assets**, com o peso original
intacto — continua `< 5 KB` e continua obrigatório. **Movido, não dispensado.** A distinção precisa
sobreviver à leitura de daqui a um mês: *waived* apaga o requisito, *movido* só troca o dono.

> **A armadilha que a trilha desarmou, e que fica registrada para o próximo.** Existem
> `logo1.svg` (5.435 B) e `logo_thumbnail1.svg` (1.386 B), que parecem "a versão otimizada que
> alguém já fez". **Não são.** Rasterizados em Chromium: `logo.svg` é *"ChatSPX" com balão verde* —
> a marca em uso; `logo1.svg` é *"SPX CHAT" em azul*, a identidade anterior. Trocar um pelo outro
> não otimizaria nada — trocaria a **identidade visual do produto** em quatro superfícies. Seria um
> defeito de marca disfarçado de otimização, e passaria em qualquer teste que só compare bytes.

#### (b) O teto de **80 KB** não se move; o título do bloco é que cede

A spec-guarda `specs/tailwindWidgetContent.spec.js`, escrita pela própria trilha, **reprovou o
trabalho dela na primeira execução** e expôs a causa: o widget renderiza componentes do dashboard.

```
router.js → views/UnreadMessages.vue → UnreadMessageList.vue → UnreadMessage.vue
  → dashboard/components-next/avatar/Avatar.vue → icon/Icon.vue, GalleryView.vue → …
```

|  | CSS | teto | tela `unread` |
|---|---|---|---|
| sem os componentes do dashboard | **73.098 B** | ✓ fecha | **sem estilo** |
| com eles (caminhos exatos) | **100.717 B** | ✗ +18.797 B | **correta** |

A trilha escolheu a tela correta em vez do número que passava — e fez bem: 73.098 B com uma das
**quatro telas cobertas pelos 16 snapshots** sem estilo seria um verde mentiroso.

**Decisão:** autorizo **desacoplar a tela de não lidas do `Avatar` do dashboard** como trabalho da
mesma trilha, que já tem a cadeia medida e a spec-guarda escrita. É refatoração de componente, e o
título do bloco dizia *"sem tocar componente"* — **o título cede, o número não.** Teto permanece
**81.920 B**. O 1.08 fecha quando o CSS ficar ≤ 81.920 B **com a tela de não lidas renderizando
correta** — as duas coisas juntas, nunca uma. Até lá, **PARCIAL**.

> **A trava muda de natureza aqui.** Enquanto o 1.08 não tocava componente, os 16 snapshots eram
> irrelevantes para ele. A partir desta autorização eles viram a rede principal, porque a
> refatoração atinge uma das quatro telas cobertas. Se `unread-*` mudar de pixel, **isso é achado a
> investigar — nunca baseline a regravar.** Regravar snapshot para o teste passar é a forma mais
> limpa de destruir a única prova visual que a onda tem.

#### (c) Procedência do bloco 1.20, que fechou por commit que nenhum executor desta onda escreveu

O `o1-origem` encontrou o worktree já em **`76286ea99a`** (tag `resgate-o1-origem`), à frente da
base `c06ba1824e` declarada no briefing. **Esse commit é meu**, do resgate do merge da v4.16.2 que
uma sessão anterior deixou pendente em disco (`write-tree` + `commit-tree`, etiquetado em
`refs/spx/…` e nas tags `resgate-o1-*`).

**Mantive o commit** — mas o motivo não é a procedência: é que a trilha **não o aceitou por estar
lá**. Ela reverteu os 3 arquivos de produção e mediu a suíte ficar vermelha (**22 exemplos / 17
falhas** sem o código; **22 / 0** com ele), em banco dedicado `chatwoot_test_o1origem`. Um commit
revalidado assim vale mais que um refeito sem prova; refazer do zero daria o mesmo código com outro
SHA e ainda perderia o rastro do resgate. Fica exigido no relatório da trilha o registro de
**herdado e revalidado**, com origem, os números do vermelho/verde e os arquivos revertidos — sem
esse parágrafo, a leitura óbvia do `git log` é *"entrou código sem dono"*.

---

### 12.6 §B.4 × R5 — a contradição do plano, resolvida em 18/08/2026

A **§B.4 do plano 22** diz que a tela inicial do perfil **suporte** tem *"bloco de artigos **no
topo**"*. Hoje o `ArticleContainer` fica **abaixo** do `TeamAvailability`. A trilha complementar da
Onda 2 escalou a colisão em vez de escolher em silêncio, e estava certa nos dois pontos:

1. **`home` é uma das quatro telas cobertas** — `spec/e2e/widget/widget.spec.js:9`,
   `views = ['home','messages','prechat-form','unread']`, com os quatro `home-*.png` gravados.
   Reordenar quebra a **R5** (*16 snapshots idênticos antes e depois*).
2. **Toda inbox existente resolve para `support`** (regra A4). Reordenar entregaria uma home
   diferente a **todo cliente que já usa o produto**.

**Não é a R5 que decide — é o item 2.** Mudança de produto para base instalada não pega carona em
bloco de layout, e isso valeria mesmo que a R5 não existisse. A R5 apenas tornou a colisão visível.

**DECISÃO: a ordem "artigos no topo" passa a ser opt-in, com o default igual ao de hoje.** As duas
regras ficam certas ao mesmo tempo: o default não muda um pixel (os quatro `home-*` permanecem
idênticos) e o layout da §B.4 existe e é alcançável por quem escolher. A §B.4 não estava errada —
estava **subespecificada**: descrevia o layout sem dizer o que acontece com quem já está no ar.

O mecanismo tem de provar **as duas pontas**: default → os quatro `home-*` idênticos (por
snapshot); opção ligada → a ordem inverte no DOM (por teste de ordem, **não** por pixel — não se
criam quatro baselines novas para isso).

#### Lacuna herdada da mesma §B.4, sem dono até aqui

A §B.4 exige, no perfil `marketing`, *"2 a 4 opções de intenção nomeadas"*. **Não existe fonte de
configuração para elas** — não estão nas 11 flags canônicas da §B.3 nem em qualquer outro campo
declarado. A trilha consumidora **não inventou o campo**, que é o comportamento correto sob o
Artigo IV (No Invention). Roteado à trilha dona do schema, com três saídas legítimas: declarar o
contrato agora, declarar em qual bloco posterior ele nasce, ou argumentar que a §B.4 está errada.
O que não é opção é a lacuna seguir sem dono.

#### Dois `bg-white` sem `dark:`, achados na varredura e **não** corrigidos por quem achou

| Arquivo | Leitura | Destino |
|---|---|---|
| `widget/components/ChatHeader.vue:50` | `bg-white/80` no ponto de online, com `text-white` no título ao lado — cabeçalho pintado com a cor da marca, **branco proposital** | bloco **2.06**, cujo aceite já exige *"nenhum `text-white`"* |
| `widget/components/UnreadMessage.vue:96` | `chat-bubble agent bg-white` — **indeterminado** | trilha do widget, **para determinar**, não para corrigir |

> O segundo merece cuidado, e é um caso de método. Existem `unread-dark-*.png` baselinados e eles
> **passam** — a bolha já é branca no escuro na régua atual. Ou é intencional (as bolhas de não
> lidas flutuam sobre o site do cliente, fora do painel, e o tema talvez não deva alcançá-las), ou
> é **defeito que foi baselinado** e desde então os 16 verdes vêm confirmando o erro em vez de
> pegá-lo. As duas leituras pedem ações opostas, e só quem tem o contexto do componente decide.
> Se for a segunda, a correção muda dois snapshots **de propósito** — a única categoria de
> regravação autorizada, e ainda assim com o diff lido e a razão escrita.

---

### 12.7 A §12.1 estava certa no risco e errada no endereço — a segunda fila mora no `IFrameHelper`

O bloco **1.23** enfileira as chamadas públicas do SDK feitas antes do widget estar pronto. A
§12.1 avisava que existia uma **segunda fila** e apontava para o **store**, mandando não tocá-la.

A trilha respeitou a instrução — não encostou na fila pré-conversa do upstream — e **achou a
segunda fila em outro lugar**: `app/javascript/sdk/IFrameHelper.js:220` reenviava `set-user` no
evento `loaded`, por conta própria.

Duas consequências, e a segunda é pior:

1. Com a fila nova, `setUser` pré-boot sairia **duas vezes** — exatamente a armadilha que a §12.1
   descreve, só que noutro arquivo.
2. O reenvio mandava `window.$chatwoot.user` **cru, sem `identifier`**, enquanto `setUser` manda
   `{identifier, user}`. **O mesmo evento chegava ao painel em dois formatos, conforme quem
   emitia.** É a forma exata do defeito que mais custou nesta execução: duas pontas coerentes
   sozinhas, incompatíveis na junção, verdes nos dois lados.

Correção: `drenar()` passou a devolver os rótulos drenados, e a re-hidratação só ocorre se a fila
não cobriu.

> **Por que isto vira registro no plano, e não só no relatório da trilha.** Um achado de quem foi
> *cumprir* uma instrução e encontrou o problema **fora de onde ela apontava** conserta o mapa, não
> só o código. Quem ler a §12.1 amanhã procuraria no store e não acharia nada — e concluiria que o
> risco não existia.

#### A decisão sobre `Promise.reject`, que é sobre quem paga a conta do defeito

A primeira versão devolvia `Promise.reject` nos erros de validação, e a suíte acusou **3 unhandled
errors**. O raciocínio da trilha: *promessa rejeitada que ninguém observa **é** exceção não
capturada* — o navegador dispara `unhandledrejection`, e ela aparece no **rastreador de erros do
cliente**, com o nome do site dele, como se o bug fosse dele.

O SDK roda na página de terceiros. Um erro nosso não chega ao nosso painel: chega ao Sentry/
GlitchTip **do cliente**, e alguém lá gasta uma tarde caçando um bug que não é seu.

Correção: handler anexado **internamente**, **promessa original devolvida** — quem chama continua
vendo a rejeição se quiser, quem não chama não polui ninguém. O comportamento público não foi
trocado para calar o teste; separou-se "observado internamente" de "devolvido ao chamador".

#### A13 — o peso do `sdk.js`, e a folga que o bloco 4.06 herda

Medido nos dois estados (o "antes" com o trabalho no `stash`), que é a forma certa de medir delta:

| | cru | gzip |
|---|---:|---:|
| antes do 1.23 | 32.696 B | 11.429 B |
| depois | 33.607 B | 11.710 B |
| **delta** | **+911 B** | **+281 B (+2,46 %)** |

Contra o teto de **15 KB gzip** (15.360 B): **folga de 3.650 B gzip — 23,8 % do teto**. O 1.23
consumiu 1,8 %.

> **Isto precisa chegar à trilha do bloco 4.06 antes de ela escrever código.** O plano descreve o
> 4.06 (o teaser) como *"o maior consumidor de bytes do host em todo o plano"* — DOM, gatilho
> composto, cookie de dispensa, avatar, chips, i18n, `all: revert`. Ela **não herda um teto
> virgem**: herda 3.650 B gzip. Descobrir isso no fim, com o código pronto, seria caro.

#### Régua da branch integrada, após 35 commits das Ondas 1 e 2

**`vitest`: 498 arquivos · 5.061 testes · 0 falhas · exit 0.** (Onda 0 fechou em 4.619.)

---

### 12.8 Achados que **não** vieram de aceite nenhum — 18/08/2026

Cinco defeitos reais que nenhum bloco pediu que se procurasse, todos encontrados por trilha que foi
olhar **depois** do verde. Ficam aqui porque quatro deles pedem bloco próprio.

#### (a) `button-name` com **11 nós** — o caminho interativo do widget é mudo

Medido pela trilha `o1-bridge` ao ampliar a matriz de snapshots de 16 para 20. Os cenários de tipos
ricos medem `axe critical = 3` contra **0** nos 16 originais, sendo **`button-name` em onze nós**:
estrelas do CSAT, botões de opção, botão do cartão, botão de entrar na sala. Mais `image-alt` e
`label`.

Um visitante com leitor de tela numa conversa com CSAT ouve **"botão, botão, botão, botão, botão"** —
não tem como saber que são cinco estrelas nem qual é qual.

**Não é regressão: é dívida que ninguém tinha como ver**, porque a matriz só alimentava
`content_type: text`. Os 16 vinham verdes há meses sobre a metade não interativa do produto.
Ampliar a régua foi o que tornou a dívida visível e medida. → **bloco próprio** (W2.3 e W3.10 já
preveem o terreno). A trilha `o1-widget` mediu, em paralelo, **8 dos 16 cenários** com `critical`
gravado como esperado em `messages-*` e `prechat-form-*`; se for a mesma regra, a causa é única no
render de mensagem.

#### (b) `POST /api/v1/widget/conversations` sem HMAC — o vetor que o 1.11 **não** fechou

O bloco 1.11 fechou o *takeover* de contato por merge. A trilha mediu que **o mesmo
`ContactIdentifyAction` roda por outro endpoint, sem HMAC nenhum** — a porta continua aberta por
ali. → **bloco próprio.** A correção precisa decidir o que acontece com integração de cliente que
hoje chama esse endpoint sem HMAC: é decisão de produto, não só de código.

> Um bloco que fecha 1 de 2 caminhos e é reportado como "fechado" é pior que um bloco não feito:
> cria a crença de que o problema acabou.

#### (c) A linha "Endereço IP" **nunca renderizou para ninguém**

A store camelize para `additionalAttributes.createdAtIp`; o `ContactPanel` lê snake_case. Cada lado
correto isolado, o defeito na junção. **Herdado do upstream `42f6621afb`** — vai para a lista de
divergências com o upstream, não para a de regressões da onda. Achado pela validação em navegador,
invisível a 150 exemplos Ruby e 32 vitest verdes.

#### (d) Contraste abaixo de AA em três telas — mesma doença

| Onde | Medido | Quem achou |
|---|---|---|
| `/reports/overview` (pré-existente) | **15 textos** abaixo de AA, incluindo *"Em tempo real"* com razão **1,0** — texto da cor exata do fundo, invisível | `o1-origem` |
| `ColorPicker` e `TabBar` | texto na cor da marca, **2,02:1** sobre fundo claro | `o2-config-telas` |
| painel de contato (1.17) | **4,14** | `o1-backend` |

As três medidas em telas que as trilhas **não** tocaram, o que separa *"meu bloco tem defeito"* de
*"o produto tem defeito"*. → **achado único do design system**, bloco próprio.

#### (e) O catch-all de `!important` no skin — terceira ocorrência nesta base

`.dark .bg-n-solid-1 { background-color: #111b21 !important }` e irmãs: qualquer superfície com
classes `n-*` fica presa na cor do painel **mesmo com a custom property correta herdada**. O aceite
*"o toggle de tema do preview funciona independente do tema do dashboard"* **passava no vitest e
falhava no Chromium** — o jsdom vê a classe aplicada e dá verde; não resolve cascata, nem
`!important`, nem custom property.

**Regra que passa a valer:** aceite de **aparência** verificado só em jsdom **não está verificado —
está afirmado**. Cor, contraste, raio, sombra e tema se provam pelo valor **computado** num Chromium
real.

---

### 12.9 Régua da branch integrada — 18/08/2026, 111 commits

| Instrumento | Resultado |
|---|---|
| `vitest` | **520 arquivos · 5.361 testes · 0 falhas** (Onda 0 fechou em 4.619) |
| paridade de config (0.6) | **1 example, 0 failures** — verde depois da correção do `tokens` |
| 20 snapshots do widget | 16 originais **pixel-idênticos** após mudança nos dois eixos da matriz; 4 novos gravados e lidos um a um |

#### O que quase apagou a régua, duas vezes

1. **A suíte de paridade nunca entrou na base.** O commit `1a45399b2a` existe, o bloco 0.6 foi
   executado — e não era ancestral de `c06ba1824e`, da branch integrada, nem de **nenhuma** trilha.
   Eu havia escrito no briefing de todas elas que a rede *"já existe"*. **Teste ausente é
   indistinguível de teste que passa**: os dois produzem suíte verde. Restaurado, ele reprovou na
   primeira execução e nomeou o `tokens`.
2. **O `.gitignore` engolia snapshot novo.** `*.png` numa seção de arquivos locais; os 16 atuais
   sobrevivem porque alguém usou `git add -f`, e isso não estava escrito em lugar nenhum. Baseline
   nova **não entra no commit e não aparece em `git status`** — o autor comita achando que subiu e a
   suíte quebra na máquina de todos com *baseline ausente*. Corrigido com
   `!spec/e2e/widget/snapshots/*.png`, verificado nos dois sentidos por `git status`.

#### Duas armadilhas de instrumento, para quem repetir as medições

- **`0 examples, 0 failures` passa por verde.** `rspec` em worktree de trilha não tem `.env` e não
  conecta no banco. A palavra "failures" com um zero na frente engana grep e olho cansado.
  **Exija `N examples` com N > 0 e confira se N é o número esperado.**
- **Não use `set -a; . .env`.** O arquivo quebra o bash na linha 70 —
  `MAILER_SENDER_EMAIL=SPX - CHAT <sup@…>` tem um `<` sem aspas que vira redirecionamento e
  **aborta o `source` antes de exportar qualquer coisa**. Use
  `eval "$(grep -E '^POSTGRES_' .env | sed 's/^/export /')"`.
