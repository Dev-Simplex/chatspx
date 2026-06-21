# Prompt de teste — "Clareza Total" nos PDFs de Relatório ChatSPX

## Objetivo
Aplicar **9 princípios de clareza** a **TODOS os relatórios** em PDF, de modo que
**qualquer pessoa — inclusive uma criança — entenda cada número e cada gráfico sem explicação**.
A meta final é: **todo gráfico de todo relatório tem uma legenda visual ao lado** dizendo o que
cada cor/tonalidade significa (princípio 9), além da narrativa em linguagem humana.

**Como cobrir os 10 sem risco:** os gráficos são **helpers compartilhados**
(`Reports::PdfChartHelper`). Melhorar o helper (ex.: legenda no `pdf_heatmap`) **propaga
automaticamente** a clareza para todos os relatórios que usam aquele gráfico. Então a maior
parte do ganho vem de poucos pontos centrais, não de editar 10 arquivos um a um.

**Estratégia segura e faseada (não quebrar nada):**
1. **Fase 1 — piloto de validação visual:** `conversations` (exercita quase tudo: manchete, semáforo,
   tradução, melhor/pior, meta, legenda de gráfico, heatmap, narrativa). Serve só para revisar o visual.
2. **Fase 2 — propagar pelos helpers:** legendas e melhorias nos helpers de gráfico → cobrem os 10.
3. **Fase 3 — varredura relatório a relatório:** garantir que cada tópico/seção de cada PDF
   (NPS, CSAT, bot, conversations, overview, agent, inbox, team, label, sla) tem legenda e linguagem clara.
- Piloto alternativo p/ carinhas 😀/😐/😞 + herói/vilão por atendente: `nps` ou `csat`.

## Regra de ouro (teste de aceite)
> Pegue o PDF, mostre para alguém que **nunca usou o ChatSPX**. Em **10 segundos** ela deve dizer:
> (1) o que aconteceu, (2) se foi bom ou ruim, (3) o que fazer. Se não conseguir, falhou.

---

## Restrições inegociáveis (manter o padrão "Tozi-grade")
- **Zero JS / zero Chart.js.** Todo gráfico é SVG calculado em Ruby (`Reports::PdfChartHelper`).
- Reusar o design system existente: partials em `app/views/reports/pdf/`
  (`_callout`, `_kpi_band`, `_hero_stat`, `_conclusion`, `_recommendations`, `_data_table`…),
  CSS em `_shared_css.html.erb`, layout `layouts/reports/pdf.html.erb`.
- **Nunca recalcular métrica** — reusar os builders V2 via `Reports::PdfDataResolver`.
- Tempos **sempre** humanizados via `Reports::TimeFormatPresenter` — nunca segundos crus.
- `print-color-adjust: exact` (cores no print), fontes Inter embutidas — não mexer.
- Emojis: usar como **glifos de texto** (a fonte de print do Chromium renderiza; validar no smoke).
  Se algum emoji não renderizar no PDF, cair para o ícone SVG equivalente em `_callout`/badge.

---

## Os 9 princípios → tarefas concretas

### 1. Manchete que qualquer um entende (topo do relatório)
- **Backend** (`PdfDataResolver`): cada `*_data` passa a devolver `headline:` — uma frase
  em português de gente, gerada dos números. Ex. conversations:
  > 📈 "No período sua equipe atendeu **142 conversas** — **18% a mais** que o período anterior,
  >  e os clientes esperaram **menos** pela 1ª resposta. Período bom!"
- **Template**: novo partial `app/views/reports/pdf/_headline.html.erb` (frase grande, amigável,
  com 1 emoji de humor) renderizado **antes de tudo**, acima do `_callout` atual.
- Reaproveitar a lógica de threshold que já gera os callouts.

### 2. Semáforo + carinhas (linguagem universal)
- **Helper novo** `pdf_status(value, metric:)` → `{ color:, emoji:, word: }`
  com base nas metas (ver princípio 5). Verde = bom, amarelo = atenção, vermelho = ruim.
- **CSS** (`_shared_css`): classe `.status-dot` (bolinha colorida) + `.status-dot--good/warn/bad`.
- **`_kpi_band`**: aceitar `status:` no card → renderiza a bolinha ao lado do valor.
- **Carinhas** (CSAT/NPS): 😀 fã/promotor · 😐 neutro/passivo · 😞 insatisfeito/detrator —
  ao lado das faixas na distribuição e no resumo.
- **Legenda fixa de 1 linha** no rodapé da capa: "🟢 bom · 🟡 atenção · 🔴 precisa melhorar".

### 3. Traduza o "tecniquês" (cada KPI se explica)
- `_kpi_band`: novo local opcional `meaning:` por card → caption de 1 frase abaixo do valor
  (classe `.kpi-meaning`, cinza, pequena). Ex.:
  - "1ª resposta" → *"quanto tempo o cliente espera pela primeira resposta"*
  - "Resolução" → *"quanto tempo até o problema ser resolvido"*
- Renomear rótulos técnicos para humanos no template (sem alterar as chaves do resolver).

### 4. Sempre responder "isso é bom ou ruim?" (delta com contexto)
- **Backend**: `PdfDataResolver` calcula o **período anterior** de mesma duração
  (`previous_range`) e devolve `comparison:` por métrica:
  `{ current:, previous:, delta_pct:, better: <bool> }`.
  ⚠️ **Direção importa**: para tempos (FRT, resolução), **menor é melhor** → queda = `better: true`.
- **Helper/partial** de delta: seta + cor + texto curto, **direção-aware**:
  - `⏱️ 3 min ▼ 30% mais rápido 🎉` (verde, mesmo sendo seta pra baixo)
  - `😞 detratores 8% ▲ +2 pts — fique de olho` (vermelho)
- Renderizar o delta ao lado de cada KPI herói.

### 5. Mostre a meta, não só o resultado
- **Config de metas/limiares** (constante nova, ex. `Reports::PdfBenchmarks` ou `BENCHMARKS` no resolver):
  por métrica, `{ goal:, green:, yellow: }` (ex. FRT: meta 5 min). Documentar a origem dos números.
- **Texto**: "Sua meta é responder em até **5 min**. Você está em **3 min** ✅".
- **Linha de meta no gráfico**: estender `pdf_bar_chart` e `pdf_line_chart` com
  `goal:` (numérico) + `goal_label:` → desenha **linha tracejada** horizontal na altura do valor-meta
  (`y = plot_h - (goal/max)*(plot_h-14)`) com rótulo. Reusar `chart_text`.

### 6. Herói e vilão (com nome)
- **Backend**: resolver devolve `highlight:` (o melhor) e `attention:` (o que precisa de atenção),
  com nome real da entidade. Ex.:
  - 🏆 **Destaque:** Maria — NPS 78, a mais querida pelos clientes
  - ⚠️ **Atenção:** caixa "WhatsApp Vendas" — tempo de resposta subiu
- **Template**: 2 callouts (`variant: success` e `variant: warning`) ou um `_split_table` com badges.

### 7. Legenda automática nos gráficos (o gráfico se explica)
- **Backend**: computar insights e devolver string pronta. Ex. heatmap →
  `heatmap_insight: "terça e quarta, às 14h"` (re-bucketização que já existe acha o pico).
- **Template**: caption abaixo de cada gráfico (classe `.chart-caption`):
  > 🔥 "Os horários mais movimentados são **terça e quarta, às 14h**. Reforce a equipe nesses momentos."

### 8. Estrutura narrativa — 3 perguntas, nesta ordem
Reordenar as seções do template do piloto para responderem, com títulos explícitos:
1. **O que aconteceu?** → manchete (princ. 1) + 1 número herói grande (`_hero_stat`).
2. **Melhorou ou piorou?** → KPIs com delta vs período anterior (princ. 4) + gráficos com meta (princ. 5).
3. **O que fazer agora?** → `_recommendations` (hoje no fim) **promovido** e em destaque.

### 9. Legenda visual ao lado de CADA gráfico (chave de cores/tonalidade) — OBRIGATÓRIO
> Este é o ponto central: nenhum gráfico pode aparecer "nu". Sempre que houver cor ou tom,
> precisa haver uma **chave ao lado (ou logo abaixo)** dizendo o que cada cor/tonalidade significa,
> em 1 frase. Sem isso, o leitor não sabe se "azul-escuro" é muito ou pouco.

- **Componente reutilizável novo** `app/views/reports/pdf/_chart_legend.html.erb`, com 2 modos:
  - `items: [{ color:, label: }]` → lista de bolinhas/quadradinhos coloridos + rótulo (categórico).
  - `scale: { colors: [...], low: "menos", high: "mais" }` → barra de gradiente com rótulo nas pontas (tonalidade).
  - CSS no `_shared_css`: `.chart-legend`, `.chart-legend--scale`, `.legend-swatch`, `.legend-label`.
- **Aplicar a todos os tipos de gráfico** (são helpers compartilhados → cobre os 10 relatórios):
  - **Heatmap** (`pdf_heatmap`): desenhar uma **escala de tonalidade vertical à DIREITA do grid**
    — exatamente onde está o retângulo vermelho do exemplo enviado. 5 tons da paleta, de claro
    ("menos conversas") a escuro ("mais conversas"), com rótulos "menos ↕ mais". Reservar ~70px
    à direita (aumentar `width` do SVG, **sem** encolher as células). Título curto acima:
    *"Cada quadradinho = 1 hora. Quanto mais escuro, mais conversas."*
  - **Barras** (`pdf_bar_chart`): legenda "🟩 conversas no dia" + (se houver) rótulo da linha de meta.
  - **Linha** (`pdf_line_chart`): legenda "🟩 tempo médio · 🔻 linha tracejada = sua meta" +
    nota "quanto mais baixo, melhor".
  - **Gauge** (`pdf_gauge`): já tem as 4 zonas (Crítico/Aperfeiçoar/Qualidade/Excelência) — garantir
    os rótulos e a faixa de valores legíveis; nada a recolorir.
  - **Distribuição de notas** (`pdf_nps_distribution`): mini-legenda
    "😀 promotor (verde) · 😐 passivo (amarelo) · 😞 detrator (vermelho)".
  - **Composição empilhada** (`pdf_composition_bar`): já possui `composition_legend` com % — manter.
- **Compatibilidade (não quebrar):** todo novo parâmetro de legenda é **opcional com default que
  reproduz o comportamento atual**. Ex.: `pdf_heatmap(grid, palette:, legend: true)` — se alguém
  chamar sem `legend:`, o default liga a legenda, mas o gráfico continua válido e do mesmo tamanho útil.

### Matriz de cobertura — cada gráfico × sua legenda (todos os relatórios)
| Relatório | Gráficos/tópicos visuais | Legenda a garantir |
|---|---|---|
| conversations | barras (conversas/dia), linha (1ª resposta), heatmap tráfego, tabela velocidade | escala heatmap + legenda barra/linha + caption |
| overview | heatmap tráfego, heatmap resoluções, tabelas | 2 escalas de heatmap (tráfego e resoluções, paletas distintas) + caption |
| nps | gauge, distribuição 0–10, tabela por atendente | zonas do gauge + carinhas/cores da distribuição |
| csat | distribuição 1–5, composição, tabela por atendente | carinhas/cores + legenda da composição |
| bot | barras (resoluções/handoffs), tabela por caixa | legenda de cor por série + caption |
| agent/inbox/team | barras/linha de tendência, tabela resumo | legenda barra/linha + status nas colunas |
| label | tabela resumo, tendência | legenda + status |
| sla | composição/hit-rate, tabela de violações | legenda de cor (cumprido vs violado) |

> Regra prática: **abriu um gráfico colorido → tem que ter chave de cor ao lado.** Varrer os 10
> e marcar cada gráfico desta matriz como ✅ legenda presente.

---

## Arquivos que o teste deve tocar
- `app/services/reports/pdf_data_resolver.rb` — `headline`, `comparison`/`previous_range`,
  `highlight`/`attention`, `heatmap_insight`, metas.
- `app/helpers/reports/pdf_chart_helper.rb` — `pdf_status`, `goal:` em bar/line chart,
  **escala de legenda no `pdf_heatmap`** (princ. 9), parâmetros `legend:` opcionais.
- `app/views/reports/pdf/_headline.html.erb` (novo), `_chart_caption.html.erb` (novo),
  **`_chart_legend.html.erb` (novo, princ. 9)**.
- `app/views/reports/pdf/_kpi_band.html.erb` — `status:` e `meaning:`.
- `app/views/reports/pdf/_shared_css.html.erb` — `.status-dot*`, `.kpi-meaning`, `.chart-caption`,
  **`.chart-legend*` / `.legend-swatch` / `.legend-label`**, legenda da capa.
- `app/views/reports/pdf/*.html.erb` — Fase 1 reordena o piloto na narrativa de 3 perguntas;
  Fase 3 varre os 10 garantindo legenda + linguagem clara em cada tópico (matriz de cobertura).

## Validação (rodar tudo)
1. **Smoke do piloto** (homolog roda em `production`, seed vive em 2026 — passar **epoch**, não string):
   ```bash
   RAILS_ENV=production dotenv bundle exec rails runner '
     acct = Account.find(1)
     f = { "since" => 6.months.ago.to_i, "until" => Time.current.to_i, "business_hours" => false }
     exp = acct.report_pdf_exports.create!(report_type: "conversations", filters: f, audit_meta: {})
     Reports::PdfExportJob.perform_now(exp.id)
     puts exp.reload.status; puts exp.file_size
     # baixar/abrir o blob para inspeção visual
   '
   ```
2. **Inspeção visual** do PDF — aplicar a "regra de ouro" (10s, criança entende) e conferir a
   **legenda ao lado de cada gráfico** (matriz de cobertura).
3. **Smoke dos 10** (rodar a cada mudança em helper compartilhado — garante que nada quebrou):
   ```bash
   RAILS_ENV=production dotenv bundle exec rails runner '
     acct = Account.find(1)
     f = { "since" => 6.months.ago.to_i, "until" => Time.current.to_i, "business_hours" => false }
     %w[nps csat bot conversations overview agent inbox team label sla].each do |rt|
       exp = acct.report_pdf_exports.create!(report_type: rt, filters: f, audit_meta: {})
       Reports::PdfExportJob.perform_now(exp.id)
       puts "#{rt}: #{exp.reload.status} #{exp.file_size}"
     end
   '
   ```
   Todos devem sair `completed` com tamanho > 0.
4. `bundle exec rubocop` nos arquivos Ruby tocados (PdfChartHelper está no Exclude de ModuleLength).
5. Specs: `spec/services/reports/` e `spec/jobs/reports/` continuam passando (+ casos novos do delta/headline).

## Critério de aceite
- [ ] PDF do piloto passa na "regra de ouro" (validação humana).
- [ ] Manchete, semáforo, tradução, delta bom/ruim, linha de meta, herói/vilão, legenda de gráfico
      e narrativa de 3 perguntas presentes e corretos.
- [ ] **Cada gráfico colorido de CADA um dos 10 relatórios tem legenda de cor/tonalidade ao lado**
      (matriz de cobertura toda ✅) — em especial a **escala de tonalidade à direita do heatmap**.
- [ ] Emojis renderizam no PDF (ou caem para SVG).
- [ ] Os 10 relatórios continuam gerando PDF válido; rubocop/eslint/specs limpos.

## ⚠️ Segurança — NÃO quebrar o projeto (regras do implementador)
- **Somente aditivo.** Não remover nem renomear helper/partial/local existente. Toda mudança em
  assinatura de helper é **parâmetro novo opcional com default** que mantém o comportamento atual.
- **Não tocar** no `Reports::PdfExportService`, no rodapé nativo do Chromium, nas fontes embutidas
  nem no `print-color-adjust` (já funcionam — risco alto, ganho zero).
- **Não recalcular métrica** — só ler o que o resolver já produz e re-bucketizar/derivar.
- **Validar a cada etapa**, não só no fim: depois de cada mudança em helper compartilhado, rodar o
  smoke dos **10** (abaixo) e confirmar `completed` + tamanho > 0 para todos antes de seguir.
- **Trabalhar em branch** `nicolas` (atual), **sem commitar** — promoção via @devops. Não fazer deploy
  automático; restart `chatwoot.target` só após pré-voo (carregar classes/templates) para evitar crash-loop.
- Se um gráfico ficar maior por causa da legenda, **aumentar a largura do SVG**, nunca encolher a
  área útil de dados (não espremer as células do heatmap).

## Como promover depois (fora do teste)
homolog → AWS → produção → Tozi. Build de assets só se houver mudança de frontend
(estes PDFs são server-side, normalmente só precisa restart `chatwoot.target` para recarregar Ruby).
