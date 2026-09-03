# Onda 1 · Trilha ORIGEM — relatório de execução

**Worktree:** `/home/chatwoot/chatwoot-o1-origem` · **Branch:** `o1-origem`
**Dispatch Orca:** `task_cab80d02520c` / `ctx_8db948481e93`
**Ordem executada (dura):** 1.20 → 1.18 → 1.19 → 1.22
**Banco:** `chatwoot_test_o1origem` (`RAILS_ENV=test`, `POSTGRES_DATABASE` pinado). Nenhum banco de
dev/produção foi tocado. Nenhum push, nenhum PR, nenhum deploy, nenhum restart, nenhuma migration.

## 0. Infra da medição

`config/database.yml` resolve o banco de teste por `ENV.fetch('POSTGRES_DATABASE', 'chatwoot_test')`.
Como há três outros executores no mesmo PostgreSQL, esta trilha roda em banco dedicado
**`chatwoot_test_o1origem`**. Runner pinado em `scratchpad/rspec.sh` — ele força
`RAILS_ENV=test` **explicitamente**, porque o `.env` desta VM é o de homologação e tem
`RAILS_ENV=production`; herdar esse env seria rodar spec contra o banco de homologação.

```bash
$ ./scratchpad/rspec.sh <arquivos>     # RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test_o1origem
```

---

## Nota de proveniência do bloco 1.20 — **herdado e revalidado**, não escrito nesta dispatch

Quem abrir este log daqui a um mês vai encontrar o 1.20 fechado por um commit que **nenhum executor
desta dispatch escreveu**. Sem este parágrafo, a leitura óbvia é "entrou código sem dono". Não é:

| | |
|---|---|
| **Origem do commit** | `76286ea99a`, criado pelo **coordenador** no resgate do merge da v4.16.2 que uma sessão anterior deixou pendente no disco (`write-tree` + `commit-tree`), etiquetado na tag **`resgate-o1-origem`**. É fast-forward puro sobre `c06ba1824e`. O worktree já nasceu adiantado — foi resgate, não contaminação |
| **O que esta dispatch fez com ele** | **não aceitou pelo recibo.** Revertí os **3 arquivos de produção** — `lib/url_helper.rb`, `app/models/conversation.rb`, `enterprise/app/services/captain/assistant/runner_state_helper.rb` — para `c06ba1824e` e rodei a mesma suíte |
| **Vermelho** (3 arquivos revertidos) | **22 examples, 17 failures** |
| **Verde** (código do commit) | **22 examples, 0 failures** |
| **Banco** | `chatwoot_test_o1origem` |
| **Decisão** | do coordenador, registrada na dispatch: manter `76286ea99a` como o 1.20 fechado e seguir 1.18 → 1.19 → 1.22 em cima dele. Refazer produziria o mesmo código com SHA diferente e perderia o rastro do resgate |

O `git log` sozinho não carrega essa diferença. Este documento carrega.

---

## Bloco 1.20 — Parar de destruir o dado na escrita ✅ **FECHADO** (`76286ea99a`)

### O defeito, no código

`app/models/conversation.rb:628-632` (o plano cita `:536-539`; pós-merge o método desceu para `:628`):

```ruby
def validate_referer_url
  return unless additional_attributes['referer']

  self['additional_attributes']['referer'] = nil unless url_valid?(additional_attributes['referer'])
end
```

`url_valid?` usa `URI.parse`, que no Ruby 3.4 é o parser **RFC 3986** — estrito. Medi o que ele
reprova, e não é lixo: é URL de site de cliente.

| URL crua | `url_valid?` hoje |
|---|---|
| `https://loja.exemplo.com.br/produtos/tenis nike?utm_source=google&utm_medium=cpc` | **false** |
| `https://loja.exemplo.com.br/produtos/[promo]/tenis?utm_source=google` | **false** |
| `https://loja.exemplo.com.br/p?filtro[]=azul` | true (colchete na **query** passa; no **path** não) |

Reprovar significava `referer = nil` **e a conversa salvava normalmente**. É o que explica os
**0 de 3.180** de [M12] — e por que o banco não distingue "o SDK nunca mandou" de "a validação
destruiu": os dois produzem `referer: null`.

### A correção

Lógica em `lib/url_helper.rb` (arquivo **0/0** no merge do upstream — arbitragem **A6**), no modelo
só a chamada. Três garantias que valem a pena registrar:

1. **URL que já valida sai intacta.** A normalização do `Addressable` só roda no caminho de
   recuperação — sem isso o bloco reescreveria silenciosamente URL boa (case do host, porta
   default, re-encode do path).
2. **Escapar não promove esquema.** `javascript:`, `data:` e `file:` continuam reprovados *depois*
   de normalizados — medido em spec próprio, porque essa é a razão de o `url_valid?` existir.
3. **O que não valida nem assim vai para `additional_attributes['referer_raw']`**, truncado em
   2048 — nunca `nil` silencioso. E `referer_raw` antigo é apagado quando a URL passa a validar.

### Asserção (5) — onde `referer_raw` vazaria

- **Widget:** não vazaria. `app/views/api/v1/widget/conversations/{index,create}.json.jbuilder` não
  serializam `additional_attributes`. Virou guarda de não-regressão no request spec, não afirmação.
- **Prompt de IA: vazaria, e vazava.** O caminho é único e está mapeado:
  `RunnerStateHelper#build_conversation_state` (`enterprise/app/services/captain/assistant/`) copia
  `additional_attributes` **inteiro** para o state, e
  `enterprise/lib/captain/prompts/snippets/conversation.liquid` itera o hash inteiro **dentro do
  system prompt**. O vermelho mostrou o valor cru renderizado:

  ```
  - referer: https://loja.exemplo.com.br/ok?utm_source=google
  - referer_raw: javascript:alert(document.cookie)
  ```

  Filtro em `slice_attrs` (`BLOCKED_ADDITIONAL_ATTRIBUTES`), que cobre conversa **e** contato.

### Mecanismo, vermelho e verde

| | antes | depois |
|---|---|---|
| `url_helper_spec` + `conversations_referer_spec` + `runner_state_helper_referer_raw_spec` | **22 examples, 17 failures** | **22 examples, 0 failures** |

_(Números remedidos nesta dispatch, no banco `chatwoot_test_o1origem`. O relatório da sessão
descartada dizia "21 examples" no vermelho — a contagem de exemplos não muda ao reverter o código
de produção, então o número certo é 22 nas duas colunas. As 17 falhas batem.)_

Os 5 que já passavam no vermelho: os 2 `url_valid?` legados, a guarda do widget (que já era verde —
por isso ela é guarda, não aceite) e `state` preservando `referer`.

As cinco asserções do aceite, uma a uma:

| # | Asserção | Mecanismo | Medido |
|---|---|---|---|
| 1 | espaço não escapado preserva a origem | `conversations_referer_spec.rb:46` | `.../tenis%20nike?utm_source=google&utm_medium=cpc` lido do banco |
| 2 | colchete cru idem | `conversations_referer_spec.rb:56` | `.../%5Bpromo%5D/tenis?utm_source=google` lido do banco |
| 3 | o resto vai para `referer_raw`, nunca `nil` silencioso | `conversations_referer_spec.rb:66` | `referer=nil`, `referer_raw='javascript:alert(document.cookie)'` |
| 4 | request spec grava as 3 formas e lê as 3 de volta **do banco** | `conversations_referer_spec.rb:76` | 3 POST reais; releitura por `Conversation.where(...).pick(:additional_attributes)`; `preenchidos == 3` |
| 5 | `referer_raw` não vai ao widget nem ao prompt de IA | `conversations_referer_spec.rb:99` + `runner_state_helper_referer_raw_spec.rb` | corpo da resposta sem `referer_raw`; prompt renderizado sem `referer_raw` e sem o valor cru |

### Não-regressão

`spec/models/conversation_spec.rb` + `spec/controllers/api/v1/widget` + `agent_runner_service_spec`
+ `spec/helpers` + `contact_identify_action_spec` + `campaign_spec` + `spec/jobs/avatar`:
**411 examples, 8 failures**. As 8 são **pré-existentes na base**: rodei os mesmos 4 arquivos com as
minhas 3 mudanças em `git stash` e deu **52 examples, 8 failures — as mesmas 8** (SSRF/avatar,
`toggle_status`, dyte). Nenhuma é minha.

`rubocop` nos 6 arquivos: **no offenses detected**.

---

## Bloco 1.18 — Seed idempotente das definições de origem ✅ **FECHADO**

### Por que este bloco vem antes do parser

Sem `CustomAttributeDefinition`, o valor grava em `custom_attributes` e **não aparece no painel nem
vira filtrável**. O dado existe no banco e some da vista — que é, para o cliente, a mesma coisa que
não existir. É a nota **[R19 §D.3]** do plano de tracking, e é por isso que 1.18 é dependência dura
de 1.19.

### O catálogo — uma lista só, num lugar só

`app/services/tracking/origin_attributes.rb` (arquivo novo). Se cada frente inventar a sua lista, o
painel mostra `utm_source` duas vezes com normalizações diferentes — é o conflito nº 5 da
§Integração do plano de tracking.

| Escopo | Prefixo | Chaves | Total |
|---|---|---|---|
| Conversa | `last_` | 6 UTM + 6 click ids + `referrer_host`, `landing_path`, `origin_kind` | **15** |
| Contato | `first_` | 6 UTM + `referrer_host`, `landing_path`, `origin_kind` (write-once) | **9** |
| | | | **24** |

**Os click ids ficam fora do contato de propósito.** Click id é da sessão, não da pessoa, e a regra
do plano para ele no contato é *"mais recente não vazio, com timestamp"* (C9) — que é **o oposto**
de write-once. Misturar as duas regras na mesma chave produz dado que mente sobre o que representa.

O plano diz "~12 definições": são as 12 chaves canônicas de `T-C0.1` (6 UTM + 6 click ids). As 3
derivadas (`referrer_host`, `landing_path`, `origin_kind`) vêm do enunciado do **1.19**, e sem
definição elas não apareceriam no painel. Daí 15 + 9 = **24**, e não 12 — o número está medido no
spec, não estimado.

### `origin_kind` não tem o valor "direta"

Valores: `busca_paga`, `busca_organica`, `social`, `ia_generativa`, `email`, `referencia`,
**`nao_disponivel`**. Não existe `direta`. Quando não há dado, o valor é `nao_disponivel` — chamar
ausência de dado de "origem direta" é exatamente a mentira que o **1.22** proíbe no relatório, e
ela começaria aqui, no vocabulário. O spec tem asserção negativa para isso.

### Idempotência: cria o que falta, nunca reescreve o que existe

`app/services/tracking/origin_definitions_seeder.rb` — um `pluck` por escopo, cria só o que falta.
Definição existente **não é tocada**: se o cliente renomeou "Origem da campanha (última)" para
"Fonte do lead", a curadoria dele é dele. Corrida resolvida pelo índice único
`(attribute_key, attribute_model, account_id)`, com o `rescue` confirmando o efeito desejado antes
de engolir a exceção.

Nome no **idioma da conta** (`config/locales/tracking_origin.{pt_BR,en}.yml`, arquivos novos —
nenhum `.yml` compartilhado foi tocado), com `en` como fallback.

Entrada de operação: `bundle exec rake tracking:seed_origin_definitions` (`ACCOUNT_ID=<id>` limita
a uma conta). **Não foi executada contra nenhum banco desta VM** — só no banco de teste, pelo spec.

### Mecanismo, vermelho e verde

O vermelho aqui **não pode ser "apagar o arquivo"**: sem a constante, os specs nem carregam, e
"3 errors outside of examples" não mede comportamento nenhum. O vermelho medido é o **efeito
neutralizado** — o serviço existe, `perform` devolve `[]`:

| | examples | failures |
|---|---|---|
| **Vermelho** (`perform` → `[]`) | 19 | **13** |
| **Verde** | 19 | **0** |

Os 6 que passam no vermelho são os que **não dependem do efeito**: o exemplo que mede o estado
ANTES do seed (o defeito), a guarda de colisão com `STANDARD_ATTRIBUTES`, e as leituras de painel
que já respondiam vazio. Eles são guarda, não aceite.

### As duas asserções do aceite, uma a uma

| Aceite | Mecanismo | Medido |
|---|---|---|
| **"Rodar duas vezes não duplica"** | `origin_definitions_seeder_spec.rb` — 2ª passagem devolve `[]` e o count fica em 24; e a task rodada 2× imprime `48 criadas` depois `0 criadas` | 24 → 24 |
| **"As chaves aparecem no painel de uma conversa que as tenha"** | `spec/requests/.../tracking_origin_definitions_spec.rb` — bate nas **duas** chamadas que compõem o painel: `GET custom_attribute_definitions` (nome + tipo) e `GET conversations/:display_id` (valor) | `last_utm_source` = `Origem da campanha (última)` / `text`; `last_origin_kind` = `list` com `ia_generativa` e `nao_disponivel`, **sem** `direta`; conversa devolve `google`/`cpc`/`institucional_agosto`/`Cj0KCQ-exemplo`/`busca_paga` |
| _(extra)_ vira **filtrável** | `POST conversations/filter` com `custom_attribute_type: conversation_attribute` | devolve **só** a conversa `utm_source=google`, não a `meta` |
| _(extra)_ preserva curadoria | renomeia para "Fonte do lead", roda o seed de novo | continua "Fonte do lead" |

`rubocop` nos 6 arquivos: **no offenses detected**.

### Arquivos

| Arquivo | Estado |
|---|---|
| `app/services/tracking/origin_attributes.rb` | **novo** |
| `app/services/tracking/origin_definitions_seeder.rb` | **novo** |
| `lib/tasks/tracking_origin.rake` | **novo** |
| `config/locales/tracking_origin.pt_BR.yml` · `.en.yml` | **novos** |
| `spec/services/tracking/origin_definitions_seeder_spec.rb` | **novo** |
| `spec/requests/api/v1/accounts/tracking_origin_definitions_spec.rb` | **novo** |
| `spec/lib/tasks/rake/task_tracking_origin_spec.rb` | **novo** |

Zero arquivo compartilhado tocado ⇒ risco de merge ⚪, como o plano previu.

---

## Bloco 1.19 — Parser de origem (C0), prospectivo ✅ **FECHADO**

### O achado que mudou o desenho do bloco: **não existe `document.referrer` em C0**

O plano fala em "host e path" e o aceite fala em *"conversa vinda de `chatgpt.com`"*. Fui ver o que
o SDK realmente manda, e o que chega ao backend **não é** o referrer externo:

```js
// app/javascript/sdk/DOMHelpers.js:51-53
let oldHref = document.location.href;
const referrerHost = document.location.host;
onLocationChange({ referrerURL: oldHref, referrerHost });
// → widget/api/endPoints.js:19 → message[referer_url]
```

`referer_url` é **`document.location.href`** — a URL da página do próprio cliente em que o chat
abriu. `document.referrer` **não é coletado em lugar nenhum** do SDK nem do widget
(`grep -rn "document.referrer" app/javascript/sdk app/javascript/widget` → **0 ocorrências**).
E não podia ser diferente: coletar referrer externo e landing page da sessão é **C2**
(`T-C2.1`), outra onda, e toca o SDK — que é da trilha WIDGET, não desta.

Isso tem duas consequências, e as duas foram tratadas em vez de escondidas:

**1. Duas chaves do catálogo do 1.18 estavam com nome mentiroso, e foram renomeadas neste bloco:**

| Antes (1.18) | Agora | Por quê |
|---|---|---|
| `referrer_host` | **`page_host`** | era o host do **próprio site do cliente**, não o site de origem |
| `landing_path` | **`page_path`** | era a página **em que o chat abriu**, não a landing page da sessão |

Manter os nomes antigos seria batizar de origem um dado que é destino — e a landing page real só
existe a partir de C2 **[R19 §B.3]**. Custo do renome: 4 linhas de catálogo, 4 de locale e 2 de
spec, tudo dentro da trilha. Custo de não renomear: um relatório que diz "veio de loja.com.br"
sobre o visitante que já estava em loja.com.br.

**2. A detecção de IA generativa passa pelo `utm_source`, não pelo referrer.** E funciona porque é
assim que essas ferramentas se identificam: o ChatGPT carimba `utm_source=chatgpt.com` nos links
que abre, a Perplexity usa `utm_source=perplexity`. O parser cobre host exato
(`chatgpt.com`, `chat.openai.com`, `perplexity.ai`, `gemini.google.com`, `bard.google.com`,
`claude.ai`, `copilot.microsoft.com`) **e** token de marca (`chatgpt`, `openai`, `perplexity`,
`gemini`, `bard`, `claude`, `copilot`) — a mesma lista serve ao referrer real quando C2 chegar.
**Limitação declarada:** visitante que vem de uma IA generativa por link **sem** o parâmetro fica
como `nao_disponivel`, não como `ia_generativa`. C2 fecha isso; C0 não tem como.

### O parser

`app/services/tracking/origin_parser.rb` (novo). Recebe a URL **já saneada pelo 1.20** — é a
dependência dura da ordem: sem o 1.20, `.../tenis nike?utm_source=google` chegaria aqui como `nil`
e o parser leria o vazio que a validação deixou.

| Decisão | Por quê |
|---|---|
| `utm_source`/`utm_medium`/`utm_campaign` em **minúsculas** | são as 3 que o relatório do 1.22 agrupa; `Google` e `google` em colunas separadas é o relatório mentindo sobre duas campanhas (conflito nº 5 da §Integração) |
| click id **nunca** normalizado | `gclid` é case-sensitive por definição; downcase o inutiliza para o import offline (C9) |
| chave da query lida sem case (`UTM_Source` → `utm_source`) | o site do cliente escreve como quiser |
| parâmetro vazio **não** vira string vazia | ausência é ausência; `utm_source=''` no painel é ruído que parece dado |
| truncado em 255 | query string de campanha chega a KBs; sem teto ela entra inteira no painel e no prompt |

**Precedência do `origin_kind`** (a ordem É a regra):

`busca_paga` (gclid/gbraid/wbraid/msclkid ou medium pago) → `email` → **`ia_generativa`** →
`social` (fbclid/ttclid, medium ou source social) → `busca_organica` → `referencia` →
**`nao_disponivel`**.

`ia_generativa` **antes** de `busca_organica` não é estilo: sem isso `gemini.google.com` cairia em
"google" e a origem de IA apareceria como busca orgânica. Tem spec dedicado para exatamente isso.
E o fundo do poço é `nao_disponivel`, **nunca "direta"** — não sabemos que o acesso foi direto,
sabemos que não recebemos dado, e as duas coisas não são a mesma.

### A escrita

`app/services/tracking/origin_recorder.rb` (novo) + 4 linhas em `conversation.rb`:

```ruby
before_create :record_last_origin   # mesmo INSERT ⇒ o painel tem na primeira leitura
after_create  :record_first_origin  # write-once no contato + garante as definições (1.18)
```

- **`last_*` na conversa**, em `custom_attributes` (não `additional_attributes`) — é o caminho que
  o painel mostra e o filtro alcança **[R15 §B12.3]**.
- **`first_*` no contato, write-once POR CHAVE.** Chave que já existe não é tocada, nem com valor
  novo. E o contato **só é carimbado quando há sinal de campanha**: gravar
  `first_origin_kind=nao_disponivel` na primeira visita travaria o write-once para sempre, e a
  campanha que trouxe a pessoa na segunda visita nunca mais entraria. A conversa registra o que
  houve; o contato espera.
- **Origem é enriquecimento**: os dois callbacks têm `rescue` que reporta ao tracker de exceção.
  Um referer exótico não pode impedir a conversa de nascer — tem spec que faz o parser explodir e
  exige a conversa no banco assim mesmo.

### Mecanismo, vermelho e verde

Vermelho = as 2 linhas de callback removidas de `conversation.rb` (o parser continua lá, intacto —
o que se mede é o produto ter passado a usar o parser, não o parser existir):

| | examples | failures |
|---|---|---|
| **Vermelho** (callbacks removidos) | 41 | **7** |
| **Verde** | 41 | **0** |

Os 34 que passam no vermelho são os do parser puro (30) e os que medem ausência — eles provariam
que sabemos ler uma query string, e é justamente por isso que o aceite deste bloco é end-to-end.

### As três asserções do aceite, uma a uma

| # | Aceite | Mecanismo | Medido |
|---|---|---|---|
| 1 | conversa com `?utm_source=google&gclid=X` mostra os campos no painel **na mesma sessão** | `conversation_origin_spec.rb` — POST real do widget, releitura **do banco** por `pick(:custom_attributes)`, e `GET conversations/:display_id` como o agente | `last_utm_source=google`, `last_gclid=Cj0KCQ`, `last_page_host=loja.exemplo.com.br`, `last_page_path=/tenis`, `last_origin_kind=busca_paga` — no banco **e** no painel |
| 2 | a 2ª conversa **não** sobrescreve `first_*` | 2 POSTs, campanhas diferentes | contato mantém `first_utm_source=google`/`first_utm_campaign=primeira`/`first_gclid=AAA`; a conversa nova registra `last_utm_source=meta`; e `first_fbclid=BBB` entra, porque write-once é **por chave** |
| 3 | `chatgpt.com` vira `ia_generativa`, **não** "direta" | POST com `utm_source=chatgpt.com`, mais perplexity/gemini/claude | `last_origin_kind=ia_generativa` no banco e no painel; e um exemplo varre 3 URLs exigindo que **nenhuma** receba `direta` |
| _(extra)_ | a URL que o 1.20 recupera também é parseada | POST com espaço cru no path | `utm_source=google`, `utm_medium=cpc`, `busca_paga` — a ordem 1.20→1.19 medida, não afirmada |

### Não-regressão

`conversation_spec` + `spec/controllers/api/v1/widget` + `spec/services/tracking` + `spec/helpers`
+ os specs de origem: **370 examples, 2 failures**. As 2 são **pré-existentes na base** — rodei os
mesmos 2 arquivos com o 1.19 inteiro em `git stash` e deu **22 examples, 2 failures, as mesmas 2**
(`toggle_status` e `dyte`). Nenhuma é minha.

`rubocop` nos 7 arquivos: **no offenses detected**.

---

## Bloco 1.22 — Relatório mínimo de origem ✅ **FECHADO**

### O marco da medição, sem estado novo e sem configuração que alguém esqueça

O aceite exige distinguir *"não veio ninguém"* de *"veio, mas ninguém anotava de onde"*. Para isso
o relatório precisa saber **quando a medição entrou**. Em vez de criar coluna, flag ou variável de
ambiente, o marco é o `created_at` da definição **`last_origin_kind`** da conta — ela nasce
exatamente quando o 1.18 provisiona aquela conta, seja pela rake do deploy ou pela primeira
conversa com origem. Dado que já existe, já é por conta, e ninguém pode esquecer de preencher.

Conta sem essa definição = conta nunca medida ⇒ o período **inteiro** é "antes da medição".

### As duas regras que impedem este relatório de mentir

| Regra | Onde vive | O que aconteceria sem ela |
|---|---|---|
| Conversa medida sem origem sai com `value: null` e é rotulada **"origem não disponível"** | `OriginDimensionTable.vue` | virava "origem direta" — inventar que o visitante digitou a URL quando só faltou dado |
| Período anterior ao marco sai **contado**, nunca vazio nem zerado | `Tracking::OriginReport#before_measurement` + a faixa na tela | uma tela vazia sobre 12 conversas reais, lida como "não veio ninguém" |

E a linha de "não disponível" **conta no total** — somar só quem tem origem daria um total que não
fecha com o número de conversas, e o cliente perderia a noção de cobertura. Tem asserção para isso:
`linhas.sum(:count) == measured.conversations_count`.

### Estrutura

| Camada | Arquivo | Nota |
|---|---|---|
| Serviço | `app/services/tracking/origin_report.rb` ⚪ | agrupa por `utm_source`, `utm_medium`, `utm_campaign` e `origin_kind`; teto de 50 linhas por dimensão |
| Endpoint | `app/controllers/api/v2/accounts/origin_reports_controller.rb` ⚪ | `GET /api/v2/accounts/:id/origin_report` |
| Rota | `config/routes.rb` (+2 linhas) | |
| Tela | `ConversationOriginReports.vue` ⚪ + `components/OriginDimensionTable.vue` ⚪ | |
| Ligação | `api/reports.js`, `reports.routes.js`, `Sidebar.vue`, `i18n/*/settings.json` (+1 linha cada) | |
| i18n | `i18n/locale/{pt_BR,en}/originReports.json` ⚪ | arquivos novos; nenhum `.json` grande foi reescrito |

**Por que controller próprio e não mais uma action no `ReportsController`:** aquele arquivo já está
em **177 linhas com o teto de 175** do `Metrics/ClassLength` — ofensa **pré-existente na base**
(medida com o arquivo byte-idêntico ao `HEAD`: `git diff` vazio e o rubocop acusando 177/175).
Acrescentar ali empurraria o número para 188 e a saída fácil seria afrouxar o gate — pagar dívida
alheia com o orçamento do próximo. O controller novo entra em 0 ofensas.

**Por que subcomponente para a tabela:** `$t(chave_dinâmica)` escapa do rastreio do lint de i18n e
vira string faltando em produção sem ninguém perceber. Com o título chegando por prop, cada uma das
4 chamadas usa chave **literal** — `npx eslint` passa sem warning, não com warning silenciado.

### Mecanismo, vermelho e verde

Dois vermelhos, porque são duas camadas e cada uma pode mentir sozinha. Nos dois casos o vermelho é
a **implementação ingênua** — a que qualquer um escreveria sem o aceite na mão:

| Camada | Vermelho (o quê) | examples | failures | Verde |
|---|---|---|---|---|
| Backend | serviço ignora o marco: agrupa o período inteiro, `before_measurement` = 0 | 13 | **5** | **13, 0 failures** |
| Tela | `labelFor` devolve o valor cru e a faixa "antes da medição" some | 7 | **3** | **7, 0 passed** |

### As três asserções do aceite, uma a uma

| # | Aceite | Mecanismo | Medido |
|---|---|---|---|
| 1 | o cliente vê de onde vieram os atendimentos **a partir da entrada de 1.19** | `origin_report_spec.rb` + `origin_reports_controller_spec.rb` (HTTP real, admin autenticado) | `source: [google→1, null→1]`, `medium`, `campaign` e `origin_kind: [busca_paga→1, nao_disponivel→1]`; conversa de 20 dias atrás **não** entra na contagem por origem |
| 2 | conversa sem origem = **"origem não disponível"**, nunca "origem direta" | `ConversationOriginReports.spec.js` (linha renderizada) + asserção no corpo HTTP | linha 2 renderiza `ORIGIN_REPORTS.UNAVAILABLE`; `expect(buscar.body).not_to include('direta')`; `wrapper.text()` sem `direta`/`direct` |
| 3 | período anterior à entrada = **"antes da medição"**, nunca vazio nem zerado | faixa `data-testid="before-measurement"` + `covers_whole_range` | conta nunca medida: faixa com `count: 7` e **nenhuma** tabela de zeros renderizada; conta medida no meio: `count: 12` mais a data de início |

### Não-regressão

Trilha inteira (1.18 + 1.19 + 1.20 + 1.22, serviços, endpoints, widget, modelo e rake):
**211 examples, 0 failures**. Suíte JS de relatórios: **3 arquivos, 13 tests, 0 failures**.
`rubocop` nos arquivos tocados: **no offenses** (a única ofensa que aparece é a do
`reports_controller.rb`, pré-existente e com o arquivo intacto). `npx eslint` nos 6 arquivos de
front: **limpo, sem warnings**.

### Validação em navegador real — **26 OK, 0 FALHA**, light e dark

Feita com janela autorizada pelo coordenador. Puma isolado na **3058** (a 3000, que é o ChatSPX de
homologação, ficou intacta e foi conferida no fim: **200**), banco dedicado
`chatwoot_o1origem_ui` criado por `db:schema:load` — nenhuma migration contra dev ou produção.

**Bateu no IP real (`192.168.8.232`), nunca em `127.0.0.1`** — e isso não é formalidade: o
`Rack::Attack` **bloqueou o login** durante as sondagens
(`[Rack::Attack][Blocked] path: "/auth/sign_in"`, limite `login/ip` = 5 por 5 min). Por
`127.0.0.1` a safelist teria pulado o throttle e essa metade do caminho nunca teria executado.

**A armadilha do Vite também apareceu**: o primeiro `assets:precompile` levou **8m58s**, mas o
Rails em produção lê o manifest do Vite **uma vez, no boot** — o Puma que já estava de pé
continuava servindo o bundle anterior, e a tela mostrava o código velho com o build novo no disco.
Cada rodada de correção exigiu rebuild **e** reinício do Puma, conferidos por `mtime` do
`public/vite/.vite/manifest.json`, nunca por código de saída.

#### Os três defeitos que só o navegador mostrou (commit `dc1192f57e`)

Nenhum deles apareceu no build verde, nos 13 specs verdes nem nos 7 tests de componente verdes.

| # | Defeito | Correção |
|---|---|---|
| 1 | "Por tipo de origem" exibia **`busca_paga`, `nao_disponivel`, `ia_generativa`** — valor de máquina na cara do cliente | prop `valueLabels` + chaves i18n **literais**. As outras 3 dimensões seguem mostrando o valor cru **de propósito**: ali é o que o site do cliente escreveu, e traduzir seria reescrever a campanha dele |
| 2 | **Duas linhas de indisponível** na mesma tabela — `nao_disponivel` (parser rodou, não achou) e ausência da chave (conversa sem referer). Depois de traduzidas virariam duas linhas com rótulo **idêntico** e contagens diferentes: lê-se como tela quebrada | unificadas numa linha no serviço; a distinção continua no banco |
| 3 | **Contraste WCAG AA**: faixa "antes da medição" em **4,43** e cabeçalhos/percentuais em **4,14**, abaixo do mínimo de 4,5 | `amber-11 → amber-12`, `slate-11 → slate-12` |

Os dois primeiros ganharam asserção que os teria pegado: a suíte JS foi de **7 para 15 tests** e o
spec do serviço de 13 para **17 examples**.

#### O que ficou fora, com a medida que sustenta a decisão

Os demais textos abaixo de AA na tela (avatar, descrição do `ReportHeader`, date picker) são do
**design system**. Medi a tela **pré-existente** `/reports/overview` com o mesmo walker:
**15 textos abaixo de AA**, incluindo *"Em tempo real"* com razão **1,0**. Corrigir isso é outro
bloco — o meu fecha com **0 textos abaixo de AA nos elementos do 1.22**.

#### O item do menu lateral — o que dá para afirmar, e o que não dá

**Não dá para validar o item na barra lateral, e não é por causa deste bloco.** Este fork usa o
rail WhatsApp-fiel (`Sidebar.vue:280` — `isEffectivelyCollapsed = !isMobile`, desktop **sempre**
colapsado). Medido: **zero links `/reports/` no DOM em qualquer estado** — depois de clicar no
ícone, depois de dois cliques, na própria rota de relatórios — e isso vale para **todos** os
relatórios, inclusive os que já existiam antes desta onda. O clique no ícone navega para o
primeiro filho do grupo (`SidebarGroup.vue:265`) sem nunca expor a lista.

O que **está** provado: o item foi registrado no mesmo array dos irmãos (`newReportRoutes`), e o
grupo "Relatórios" da barra **fica marcado como ativo** na rota nova, em light e dark — asserção
que passa nas duas passagens. É comportamento pré-existente do fork, e o item novo herda
exatamente o mesmo tratamento dos outros relatórios.

#### O que o walker verificou, ponto a ponto

| Verificação | light | dark |
|---|---|---|
| grupo "Relatórios" ativo na rota nova | OK | OK |
| faixa "antes da medição": **tela = 10, banco = 10** (esperado vindo do banco, não de literal) | OK | OK |
| linha "origem não disponível" presente em `utm_source` | OK | OK |
| tipo de origem traduzido: `Busca paga · origem não disponível · Redes sociais · IA generativa` | OK | OK |
| nenhum `snake_case` exposto | OK | OK |
| a palavra **"direta"** não aparece na tela | OK | OK |
| chaves de i18n cruas | 0 | 0 |
| ícones/imagens que não carregam | 0 | 0 |
| `body.dark` bate com o tema pedido | OK | OK |
| contraste AA nos elementos do 1.22 | **0 abaixo** | **0 abaixo** |
| erros de console | 0 | 0 |

O único erro de console do ambiente é um **503 do `WahaConnectionsController`** (polling do
WhatsApp, não configurado neste banco isolado). Foi filtrado **com o motivo declarado no código do
walker**, não silenciado em bloco.

#### Limpeza

Puma da 3058 derrubado, banco `chatwoot_o1origem_ui` removido, `scratchpad/` fora do commit.
**Porta 3000 conferida no fim: 200.**


---

## Varredura de config do widget (pedida pelo coordenador, 18/08) — **nada a fazer nas duas pontas**

`git diff --name-only c06ba1824e..HEAD` lista 35 arquivos. **Nenhum** é `show.html.erb` ou
`create.json.jbuilder`, e nenhuma linha adicionada em `app/`, `config/`, `lib/` ou `enterprise/`
menciona `channelConfig`, `websiteToken`, `api_host` ou `hasAConnectedAgentBot`. Esta trilha não
acrescentou, renomeou nem removeu chave de configuração pública do widget.

### Mas a varredura achou uma superfície minha que estava sem asserção

`app/views/api/v1/widget/conversations/create.json.jbuilder:10` serializa
`json.custom_attributes @conversation.custom_attributes` — que é **exatamente onde o 1.19 grava os
`last_*`**. A origem **volta para o visitante** no payload de criação da conversa.

É aceitável, e por um motivo estreito que vale escrever: **o dado é dele** — veio da query string
da própria página que ele abriu, então não há informação nova ali. O que não pode voltar é dado
cru não validado, e esse fica em `additional_attributes` (`referer_raw`), que o jbuilder **não**
serializa. O que faltava era o teste que fixa isso: se alguém amanhã gravar em `custom_attributes`
da conversa algo que o visitante não deveria ver, agora fica vermelho e nomeia a chave
(commit `a03fe28a9d`, 13 examples / 0 failures).

### A lição do 0.6 aplicada ao meu próprio aceite

*Teste ausente é indistinguível de teste que passa.* Então verifiquei a guarda da asserção (5) do
1.20 **nos dois sentidos**, com sabotagem em vez de só rodar e ver verde:

| | mecanismo | resultado |
|---|---|---|
| **sabotado** | `json.additional_attributes` acrescentado ao jbuilder do widget | **vermelho**, nomeando `referer_raw` no corpo da resposta |
| **restaurado** | `git diff` do `app/views/` vazio | **5 examples, 0 failures** |

A proteção **roda** — não apenas passa.


---

## Auditoria de contagem (alerta do coordenador sobre `0 examples, 0 failures`)

O alerta me obrigou a auditar os meus próprios números, e a auditoria **achou duas coisas** —
uma no meu ferramental e uma num número que eu escrevi.

### 1. O ponto cego era do meu grep, não do banco

Eu filtrava a saída do rspec com `grep -E "^[0-9]+ examples"`. Esse padrão **não casa
`1 example`** — o rspec escreve o singular sem "s". Duas execuções da varredura de config
(`-e "referer_raw…"` e `:100`) saíram **silenciosas** por isso, e eu segui adiante sem parar.

Reexecutadas com `grep -E "^[0-9]+ examples?,"`: **1 example, 0 failures** cada — elas rodavam.
Não houve dano *neste* caso, porque a conclusão veio da sabotagem (vermelho positivo) e da
restauração (`5 examples, 0 failures`). Mas o ponto cego era real: um arquivo que degenerasse para
um único exemplo teria produzido **silêncio**, e silêncio se lê como "sem falhas" exatamente como
o `0 examples, 0 failures` que o coordenador descreve.

### 2. Contagem por arquivo — todos com N > 0, conferidos contra o esperado

| Arquivo | N | bloco |
|---|---|---|
| `url_helper_spec.rb` | 12 | 1.20 |
| `conversations_referer_spec.rb` | 5 | 1.20 |
| `runner_state_helper_referer_raw_spec.rb` | 5 | 1.20 |
| | **22** | **= o 22 reportado** ✔ |
| `origin_definitions_seeder_spec.rb` | 12 | 1.18 |
| `tracking_origin_definitions_spec.rb` | 5 | 1.18 |
| `task_tracking_origin_spec.rb` | 2 | 1.18 |
| | **19** | **= o 19 reportado** ✔ |
| `origin_parser_spec.rb` | 30 | 1.19 |
| `conversation_origin_spec.rb` | 13 | 1.19 |
| | **43** | 41 na época + 2 do commit `a03fe28a9d` ✔ |
| `origin_report_spec.rb` | 10 | 1.22 |
| `origin_reports_controller_spec.rb` | 6 | 1.22 |
| | **16** | 15 na época + 1 exemplo separado por `RSpec/MultipleExpectations` ✔ |
| **Total da trilha** | **100** | |
| Bateria com não-regressão | **216, 0 failures** | |

### 3. Um número que eu escrevi está errado — e fica registrado aqui

A mensagem do commit `dc1192f57e` afirma *"15 tests JS (eram 7) e **17 examples no serviço**"*.
**O 17 não existe.** O `origin_report_spec.rb` foi de **8 para 10** examples (os 2 novos são a
unificação de indisponível e a guarda de que ela não toca as outras dimensões), e o do controller
de 5 para 6. O número de tests JS (15, eram 7) está certo.

Não reescrevi a mensagem de commit: rebase apagaria o rastro de um erro que vale ficar visível.
A correção mora aqui, no documento que é a referência da trilha.

### 4. O runner já usava a técnica segura, por acidente feliz

`scratchpad/rspec.sh` sempre leu as credenciais com
`grep -E '^POSTGRES_...' /home/chatwoot/chatwoot/.env`, nunca com `set -a; . .env` — então nunca
tropeçou no `<` sem aspas do `MAILER_SENDER_EMAIL`. E a primeira execução desta trilha **falhou
exatamente com o sintoma do alerta**:

```
PG::ConnectionBad: connection to server at "127.0.0.1" failed: fe_sendauth: no password supplied
0 examples, 0 failures, 3 errors occurred outside of examples
```

Foi diagnosticado como falha de credencial, não lido como verde — e o runner pinado nasceu daí.

### 5. Paridade de config: não se aplica a esta trilha

`spec/requests/widget_configuration_builder_parity_spec.rb` **não existe nesta base** (a `o1-origem`
sai de `c06ba1824e`, anterior à restauração em `redesenho-integra`). Como a varredura da seção
anterior mostrou que esta trilha **não tocou nenhuma das duas pontas de config**, não mergeei a
`redesenho-integra` só para rodá-la — o merge traria código de outras trilhas para dentro de um
branch que está fechado e reportado. Se o coordenador quiser o resultado cru mesmo assim, é um
comando, e eu rodo.
