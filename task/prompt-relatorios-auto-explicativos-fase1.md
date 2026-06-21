# PROMPT DE EXECUÇÃO — Relatórios Auto-Explicativos (Fase 1: Conversas)

> Cole este prompt inteiro em um novo chat do Claude Code, dentro do projeto **chat spx `nicolas.chatspx`** (`/home/chatwoot/chatwoot`).

---

## 0. Contexto e regras de ouro (LEIA ANTES DE TUDO)

Você vai implementar a **Fase 1** de uma feature chamada **"Relatórios Auto-Explicativos"** no Chatwoot (fork SPX). O objetivo é levar para a **tela web** a mesma inteligência narrativa (semáforo 🟢🟡🔴, destaque, ponto de atenção, insights) que já existe no **motor de PDF de relatórios** — começando pelo relatório de **Conversas**.

**Stack:** Ruby on Rails (backend) + Vue 3 / Vuex / vue-i18n (frontend, em `app/javascript/dashboard`). Charts em Chart.js. Testes backend em RSpec.

### Regras de ouro (não negociáveis)
1. **Trabalhe em uma branch dedicada.** Antes de tudo: `git status` e `git branch`. Crie `git checkout -b feat/relatorios-auto-explicativos` a partir da branch atual (`nicolas`). NÃO faça commit direto em `master` nem em `producao`.
2. **NUNCA rode migrations destrutivas.** Esta fase **não cria nenhuma migration nem altera o schema**. Se você sentir que precisa de uma, PARE e pergunte — provavelmente é um erro de entendimento.
3. **SEMPRE leia o arquivo real antes de editar.** Os caminhos/linhas abaixo são guias; o código pode ter mudado. Confirme o conteúdo com Read antes de qualquer Edit. Não confie cegamente em números de linha.
4. **Não quebre o PDF.** A lógica narrativa hoje vive em `app/services/reports/pdf_data_resolver.rb` e é usada pela geração de PDF. Vamos *extrair* parte dela para um serviço compartilhado e fazer o resolver passar a chamá-lo. O comportamento do PDF deve permanecer **idêntico**. Rode os specs de PDF depois (ver Fase 5).
5. **Backend NÃO devolve texto traduzido.** Ele devolve o veredito **estruturado** (`level`, valores, ratio, delta). A frase em linguagem natural é montada no **frontend via i18n** — o produto é multi-idioma e não pode ser travado em português.
6. **Sem regressão de API.** O campo `signals` é **aditivo**. Nenhum campo existente do JSON de `summary` pode sumir ou mudar de tipo.
7. **Faça commits pequenos por bloco** (A→E, ver Fase 6). Rode os testes do bloco antes de seguir para o próximo.
8. **Não introduza dependências novas** (nenhum `npm install` / `bundle add`). Use o que já existe.
9. Se algo divergir do plano (arquivo não existe, assinatura diferente, teste vermelho que não entende), **PARE e relate** em vez de improvisar.

---

## 1. Decisões já travadas (não reabrir)
- **Narrativa:** backend devolve signal **estruturado**; frontend monta a frase via **i18n**. (Decisão final.)
- **Escopo Fase 1:** apenas o relatório de **Conversas** (`Index.vue`), ponta a ponta. CSAT/NPS ficam para a Fase 2.
- **Benchmarks (metas):** permanecem **fixos** nos valores atuais, MAS o novo serviço deve **receber os benchmarks como parâmetro** (com default), preparado para virar configurável por conta no futuro — sem refazer.

---

## 2. O que já existe no código (referência — confirme lendo)

### 2.1 Benchmarks (a "fonte da verdade" do veredito)
Arquivo: `app/services/reports/pdf_benchmarks.rb`

```ruby
BENCHMARKS = {
  first_response:  { goal: 300,    green: 300,    yellow: 900,    lower_better: true  }, # 5min / 15min
  resolution:      { goal: 14_400, green: 14_400, yellow: 86_400, lower_better: true  }, # 4h / 24h
  reply:           { goal: 600,    green: 600,    yellow: 1800,   lower_better: true  }, # 10min / 30min
  resolution_rate: { goal: 80,     green: 80,     yellow: 60,     lower_better: false }  # 80% / 60%
}.freeze

# Cores de status: good '#2dc46f' | warn '#ffc53d' | bad '#e54666'
# level_for(value, bench):
#   se lower_better:  good se value <= green ; warn se value <= yellow ; senão bad
#   se !lower_better: good se value >= green ; warn se value >= yellow ; senão bad
# severity: good=0, warn=1, bad=2
```
Há também métodos auxiliares como `goal(metric)` e o mapeamento de cores. **Leia o arquivo inteiro** para ver as assinaturas públicas exatas (`level_for`, `goal`, `status`, `severity`, cores).

### 2.2 Lógica narrativa atual (a ser parcialmente extraída)
Arquivo: `app/services/reports/pdf_data_resolver.rb` (~790 linhas). Métodos relevantes (confirme as linhas):
- `conversations_signals` (~356–365): monta array de 3 sinais (1ª resposta, resolução, taxa de resolução), cada um com `label/value/human/metric/kind/status/ratio`.
- `signal_ratio(signal)` (~368–372): razão value↔goal (para `:rate` é `goal/value`, para `:time` é `value/goal`).
- `conversations_highlight` (~375–378) e `conversations_attention` (~380–388): escolhem o melhor/pior sinal.
- `signal_phrase(signal)` (~390–394): monta a FRASE em PT (ex.: "Taxa de resolução: 90% (meta 80%) — bom."). **Essa parte de texto NÃO vai para a API** — fica só no PDF.

### 2.3 Endpoint que a tela já consome
Arquivo: `app/controllers/api/v2/accounts/reports_controller.rb`
- Action `summary` (~13–14, monta resposta em ~157–162 via `build_summary`).
- Builder dos números: `app/builders/v2/reports/conversations/metric_builder.rb` (método `summary`, ~5–21). Já retorna `conversations_count`, `avg_first_response_time`, `avg_first_response_time_after_assignment`, `avg_resolution_time`, `resolutions_count`, `reply_time`, percentis p50/p90, contagens, e o bloco `previous` (período anterior).

### 2.4 Frontend
- `app/javascript/dashboard/routes/dashboard/settings/reports/Index.vue` — tela de Conversas. Ordem no template: `ReportHeader` → `ReportFilters` → `SpeedInsightsPanel` → `ReportContainer`.
- `app/javascript/dashboard/routes/dashboard/settings/reports/ReportContainer.vue` (~184–220) — grid de gráficos; cada métrica renderiza `ChartStats` + `BarChart`. Métricas: `CONVERSATIONS`, `INCOMING_MESSAGES`, `OUTGOING_MESSAGES`, `FIRST_RESPONSE_TIME`, `FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT`, `RESOLUTION_TIME`, `RESOLUTION_COUNT`, `REPLY_TIME`.
- `app/javascript/dashboard/routes/dashboard/settings/reports/components/ChartElements/ChartStats.vue` (~27–36 `trendColor`, ~60–76 render da seta/percentual). É aqui que entra a pílula de semáforo.
- `app/javascript/dashboard/composables/useReportMetrics.js` — `calculateTrend(key)`, `isAverageMetricType(key)`, `displayMetric(key)`. Consome `accountSummary` (com `.previous`).
- Store: `app/javascript/dashboard/store/modules/reports.js` — getter `getAccountSummary`. State `accountSummary` já inclui `previous`.
- API client: `app/javascript/dashboard/api/reports.js` — `getSummary(...)`.
- i18n: `app/javascript/dashboard/i18n/locale/en/report.json` e `.../pt_BR/report.json`. Estrutura: `REPORT.METRICS.<METRICA>.{NAME,DESC,INFO_TEXT,TOOLTIP_TEXT}` e `REPORT.INSIGHTS.*`.

### 2.5 Shape atual do `accountSummary` (exemplo real)
```jsonc
{
  "conversations_count": 1240,
  "incoming_messages_count": 5,
  "outgoing_messages_count": 3,
  "avg_first_response_time": 450,
  "avg_first_response_time_after_assignment": 300,
  "avg_resolution_time": 14000,
  "resolutions_count": 980,
  "reply_time": 540,
  "p50_first_response_time": 150, "p90_first_response_time": 800,
  "p50_first_response_time_after_assignment": 100, "p90_first_response_time_after_assignment": 700,
  "first_response_count": 100, "first_response_after_assignment_count": 50,
  "previous": { "conversations_count": 1100, "avg_first_response_time": 550, "avg_resolution_time": 16000, "resolutions_count": 900, "reply_time": 600 }
}
```
> Nota: a **taxa de resolução** (`resolution_rate`) NÃO vem pronta — calcule como `resolutions_count / conversations_count * 100` (proteja contra divisão por zero). Confirme se o builder já expõe algo equivalente antes de recalcular.

---

## 3. CONTRATO DE DADOS (a única mudança de API)

A action `summary` passa a incluir **um campo aditivo** `signals`. Tudo o mais permanece igual.

```jsonc
{
  // ...todos os campos atuais, incluindo "previous"...
  "signals": [
    {
      "metric": "first_response",   // "first_response" | "resolution" | "reply" | "resolution_rate"
      "value": 450,                 // valor cru (segundos para tempos; % para rate)
      "goal": 300,                  // meta do benchmark
      "level": "warn",              // "good" | "warn" | "bad"  (vem de PdfBenchmarks.level_for)
      "ratio": 1.5,                 // value/goal (time) ou goal/value (rate); proteja div/0
      "delta_pct": -18,             // variação vs previous (arredondado); null se sem previous
      "is_highlight": false,        // true no melhor sinal (menor severity, melhor ratio)
      "is_attention": true          // true no pior sinal; nenhum true se tudo "good"
    }
    // ... um por métrica avaliável
  ]
}
```
Regras:
- `level` deve vir EXATAMENTE de `Reports::PdfBenchmarks.level_for` (mesma fonte do PDF).
- Exatamente **um** `is_highlight: true` quando houver ao menos um sinal; `is_attention: true` apenas se existir algum sinal com level != good (se tudo estiver bom, nenhum `is_attention`).
- `delta_pct`: positivo = subiu vs período anterior; o significado de "bom/ruim" depende de `lower_better` (o frontend interpreta isso). Se `previous` ausente/zero → `null`.

---

## 4. IMPLEMENTAÇÃO — BACKEND

### Bloco A — `Reports::MetricSignalsBuilder` (novo serviço) + spec
**Criar** `app/services/reports/metric_signals_builder.rb`:
- Construtor: `initialize(summary:, previous: nil, benchmarks: Reports::PdfBenchmarks::BENCHMARKS)`.
  - `summary` e `previous` são hashes com chaves string ou símbolo — normalize o acesso (use `with_indifferent_access` ou `.to_h.symbolize_keys`).
  - `benchmarks` é parâmetro com default (preparação para metas configuráveis — decisão travada).
- Método público `build` → retorna `Array<Hash>` no formato do contrato (seção 3).
- Para cada métrica avaliável, mapeie a chave do summary:
  - `first_response`  → `avg_first_response_time`
  - `resolution`      → `avg_resolution_time`
  - `reply`           → `reply_time`
  - `resolution_rate` → calculado: `resolutions_count / conversations_count * 100` (0 se denominador 0)
- `level` ← `Reports::PdfBenchmarks.level_for(value, benchmarks[metric])` (confirme a assinatura real no arquivo).
- `ratio` ← reusar a mesma lógica de `signal_ratio` (rate: `goal/[value,1].max`; time: `value/goal`); proteja contra goal 0.
- `delta_pct` ← `((value - prev) / prev * 100).round` quando `prev` presente e != 0; senão `nil`.
- `is_highlight`/`is_attention`: ordene por `severity` (good<warn<bad) e desempate por `ratio`. Marque o melhor como highlight; marque o pior como attention **apenas se** seu level != good.
- Não levante exceção com summary vazio/zerado — retorne sinais com valores 0 e levels coerentes (degradação graciosa).

**Criar** `spec/services/reports/metric_signals_builder_spec.rb` cobrindo:
- Um caso `good`, um `warn`, um `bad` por métrica (valores nos limites dos benchmarks).
- Cálculo correto de `resolution_rate` e proteção div/0 (conversations_count = 0).
- `delta_pct` com e sem `previous` (e previous zero → `nil`).
- Marcação de exatamente um `is_highlight`; `is_attention` ausente quando tudo `good`.
- Que passar `benchmarks:` customizado muda os levels (prova de que é configurável).

Rode: `bundle exec rspec spec/services/reports/metric_signals_builder_spec.rb`

### Bloco B — Refatorar o resolver para usar o builder + expor na API
1. Em `app/services/reports/pdf_data_resolver.rb`: faça `conversations_signals` / `highlight` / `attention` **delegarem** ao `MetricSignalsBuilder` para o veredito (level/ratio/escolha de melhor-pior), mantendo a montagem das **frases PT** (`signal_phrase`) onde já está — o PDF continua gerando texto. Objetivo: zero mudança visível no PDF, mas sem duplicar a regra de benchmark.
   - Se a refatoração ficar arriscada/extensa, é aceitável nesta fase **apenas** garantir que o builder existe e é usado pela API (passo 2), e deixar o resolver intocado — desde que você confirme que não há divergência de números. Anote a decisão no commit.
2. Em `app/controllers/api/v2/accounts/reports_controller.rb`, action `summary`: adicione `signals` ao JSON, algo como:
   ```ruby
   summary = build_summary(:summary) # (use o nome/forma real existente)
   signals = Reports::MetricSignalsBuilder.new(
     summary: summary, previous: summary[:previous] || summary['previous']
   ).build
   render json: summary.merge(signals: signals)
   ```
   Confirme como o controller monta a resposta hoje (pode já fazer `render json:` direto) e adapte sem alterar os campos existentes.
3. Ajuste o request spec: `spec/controllers/api/v2/accounts/reports_controller_spec.rb` (ou request spec equivalente — localize-o) para asseverar que `summary` agora inclui `signals` com a forma do contrato. Não remova asserts existentes.

Rode os specs de reports backend:
`bundle exec rspec spec/services/reports spec/builders/v2/reports spec/controllers/api/v2/accounts/reports_controller_spec.rb`

**Validação manual recomendada após B:** suba o app e faça um GET autenticado em `/api/v2/accounts/:id/reports/summary?...` para inspecionar o `signals` real antes de tocar no frontend.

---

## 5. IMPLEMENTAÇÃO — FRONTEND

### Bloco C — Composable + semáforo no card
1. **Criar** `app/javascript/dashboard/composables/useReportNarrative.js`:
   - Função que recebe um `signal` e retorna `{ tone, icon, colorClass, label, phrase }` usando `vue-i18n` (`useI18n`/`global.t`) — sem texto hardcoded.
   - `tone`/cor a partir de `signal.level` (`good`→verde, `warn`→amarelo, `bad`→vermelho); reutilize as classes de cor do design system já usadas em `ChartStats.vue` (ex.: tokens `n-*`/Tailwind do projeto).
   - Helpers: `phraseFor(signal)` (frase de insight de gráfico), `summaryFor(signals)` (extrai highlight/attention para o TL;DR).
2. **Editar** `ChartStats.vue`: receber o `signal` da métrica (via prop nova, ex.: `:signal="..."`, vindo de `ReportContainer.vue`). Após o bloco da seta de tendência (~60–76), renderizar uma **pílula de status** (cor + palavra traduzida "dentro da meta / atenção / precisa melhorar"). Se a métrica não tiver signal (ex.: incoming_messages), não renderize a pílula — degradação graciosa.

### Bloco D — TL;DR + insight por gráfico + glossário
3. **Criar** `app/javascript/dashboard/routes/dashboard/settings/reports/components/ReportNarrativeSummary.vue`:
   - Props: `signals` (array). Renderiza um painel (mesmo padrão visual de `SpeedInsightsPanel.vue`) com **destaque 🏆** (signal `is_highlight`) e **ponto de atenção ⚠️** (signal `is_attention`), em frases i18n.
   - Se `signals` vazio/carregando, não renderiza nada (ou skeleton). Nunca quebra a tela.
4. **Editar** `Index.vue`: importar e inserir `<ReportNarrativeSummary :signals="accountSummary.signals || []" />` **após** `ReportFilters` e **antes** de `SpeedInsightsPanel`. Garanta que `accountSummary` (getter `getAccountSummary`) já é acessível ali.
5. **Editar** `ReportContainer.vue`: para cada métrica do grid, passar o `signal` correspondente para `ChartStats` e renderizar, **sob o gráfico** (após ~217), uma frase curta `phraseFor(signal)` (insight automático). Métricas sem signal não recebem frase.
6. **Glossário:** revisar os `INFO_TEXT`/tooltips dos cards de Conversas — garantir que toda métrica tenha tooltip em linguagem simples. Atualizar textos em ambos os locales (próximo bloco).

### Bloco E — i18n
7. Em `en/report.json` e `pt_BR/report.json`, adicionar um bloco novo, por exemplo `REPORT.NARRATIVE`:
   ```jsonc
   "NARRATIVE": {
     "LEVEL": { "GOOD": "dentro da meta", "WARN": "atenção", "BAD": "precisa melhorar" },
     "HIGHLIGHT_TITLE": "Destaque", "ATTENTION_TITLE": "Ponto de atenção",
     "ALL_GOOD": "Todos os indicadores estão dentro da meta — mantenha o ritmo.",
     "INSIGHT_BETTER": "{pct}% melhor que o período anterior",
     "INSIGHT_WORSE": "{pct}% pior que o período anterior",
     "VS_GOAL": "meta {goal}"
   }
   ```
   - Use placeholders `{...}` compatíveis com o vue-i18n do projeto (confira a sintaxe usada nos arquivos atuais).
   - **As chaves devem ser idênticas em en e pt_BR** (só os valores mudam). Em `en` escreva em inglês.
   - Enriquecer os `INFO_TEXT` das métricas de Conversas com explicações de gente (ex.: FRT = tempo até a 1ª resposta humana).

**Build/lint front:** rode o lint do projeto (ex.: `yarn eslint` / `pnpm lint` conforme o repo usa) nos arquivos alterados. Não rode build de produção sem necessidade.

---

## 6. ORDEM DE EXECUÇÃO E COMMITS

Execute e **comite por bloco**, rodando os testes do bloco antes de avançar:
1. **A** — `MetricSignalsBuilder` + spec. → commit `feat(reports): metric signals builder com benchmarks parametrizáveis`
2. **B** — resolver delega + API expõe `signals` + request spec. → commit `feat(reports): expor signals no endpoint summary v2`
3. **C** — composable + pílula de semáforo no ChartStats. → commit `feat(reports): semáforo de meta nos cards de conversas`
4. **D** — TL;DR + insight por gráfico + tooltips. → commit `feat(reports): resumo executivo e insights na tela de conversas`
5. **E** — i18n en/pt_BR. → commit `i18n(reports): textos da camada narrativa`

Mensagem de commit deve terminar com:
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## 7. CRITÉRIOS DE ACEITE (verifique ao final)
- [ ] `GET /api/v2/.../reports/summary` retorna `signals` no formato do contrato, **sem** ter removido/alterado nenhum campo pré-existente.
- [ ] `level` de cada signal coincide com o que o `PdfBenchmarks` julgaria (mesma fonte do PDF).
- [ ] Specs novos e existentes **verdes**: `bundle exec rspec spec/services/reports spec/builders/v2/reports` + o request spec do controller.
- [ ] Os specs do PDF continuam verdes (PDF inalterado): `bundle exec rspec spec/services/reports/pdf_export_service_spec.rb spec/jobs/reports`.
- [ ] Na tela de Conversas: aparece o TL;DR (destaque + atenção), pílula 🟢🟡🔴 nos cards com benchmark, e uma frase de insight sob cada gráfico relevante.
- [ ] Trocar o idioma da conta (pt_BR ↔ en) traduz toda a narrativa — **nada em PT hardcoded** na tela.
- [ ] Métricas sem benchmark (mensagens entrada/saída) não exibem pílula nem frase quebrada.
- [ ] Lint do frontend sem novos erros nos arquivos tocados.
- [ ] Nenhuma migration criada; schema intocado.

---

## 8. SE ALGO DER ERRADO
- Teste vermelho que você não entende, assinatura de método diferente do descrito, ou campo de API ausente → **PARE e relate** o que encontrou, não improvise mudanças no schema ou na API.
- Em dúvida sobre quebrar o PDF → rode os specs de PDF (seção 7) e compare a saída antes/depois.
- Mantenha o escopo: **somente Conversas**. CSAT/NPS/Agent/Inbox/Team/Label são Fase 2.
