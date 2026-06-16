# Plano de Implementação — PDFs de Relatórios Brandeados (ChatSPX)

> **Tipo:** Planejamento de engenharia (executável na VM de homologação)
> **Autor:** Orion (AIOX Master) · **Data:** 2026-06-08
> **Ambiente alvo:** `homologacao` (VM `192.168.8.232`, user `chatwoot`, branch `nicolas`)
> **Origem:** auditoria de NPS da Tozi → demanda do supervisor por relatórios premium self-service
> **Artefatos relacionados:** `.aiox/audit-nps-tozi-2026-06-08/` (laudo NPS, PDF modelo, mapas dos relatórios)

---

## 0. Resumo executivo

Hoje a aba **Relatórios** só exporta **CSV cru, sem marca**. O objetivo é dar a cada relatório um **PDF executivo brandeado ChatSPX**, gerado pela plataforma com um clique ("Baixar PDF" ao lado do "Exportar CSV").

A boa notícia: **não precisamos de tecnologia nova.** O motor de PDF (`ferrum_pdf` / Chromium headless) **já está em produção** gerando o PDF de transcrição de conversas. O trabalho é **generalizar esse pipeline** de "1 relatório de conversa" para "N relatórios", com um sistema de design compartilhado.

**Princípio central:** uma engine + um design system + N relatórios. A "Fundação" (shell reutilizável) concentra ~70% do esforço; cada relatório novo depois custa **1 template (~30-60 linhas) + 1 branch no resolver de dados**. Os cálculos de métrica **já existem** nos builders — não recriamos nada disso.

---

## 1. Estado atual (o que reaproveitar)

### 1.1. O que sai hoje quando o usuário exporta
- Todos os relatórios → **CSV** via `downloadHelper.js` (`Blob` `text/csv`), arquivo `{tipo}-report-dd-MM-yyyy.csv`. Dados crus, **sem logo, sem gráfico, sem análise**.
- **Não existe nenhum PDF na aba de relatórios.**

### 1.2. A engine de PDF que JÁ existe (a base de tudo)
Gem: **`ferrum_pdf ~> 3.1`** (`Gemfile`) — Chromium headless via CDP, **sem Node**.
Config: `config/initializers/ferrum_pdf.rb` → `browser_path = ENV['CHROMIUM_PATH'] || '/snap/bin/chromium'`, `headless: 'new'`, `no-sandbox`, A4, `print_background: true`.

Fluxo de referência (export de conversa) — **estes são os arquivos a clonar/generalizar:**

| Papel | Arquivo |
|---|---|
| Controller | `app/controllers/api/v2/accounts/conversations/pdf_exports_controller.rb` |
| Service (núcleo) | `app/services/conversations/pdf_export_service.rb` |
| Template HTML | `app/views/conversations/pdf_export.html.erb` |
| Helper de template | `app/helpers/conversations/pdf_export_helper.rb` |
| Job assíncrono | `app/jobs/conversations/export_pdf_job.rb` |
| Model + storage | `app/models/conversation_pdf_export.rb` (status enum, `has_one_attached :file`, `download_url` assinado, sha256) |
| Rota | `config/routes.rb` (`resources :pdf_exports, only: %i[create show]`) |

O service faz exatamente: **`ApplicationController.renderer.render(template:, assigns:)` → HTML → `FerrumPdf.render_pdf(html:, pdf_options:)` → bytes → ActiveStorage**. É genérico por natureza: troca o template e os dados, e serve qualquer relatório.

### 1.3. Os dados (builders) que JÁ calculam tudo — NÃO recriar métrica
| Fonte | Entrega |
|---|---|
| `app/builders/v2/report_builder.rb` + `v2/reports/*SummaryBuilder` | agentes, inboxes, times, labels (sumário + timeseries) |
| `app/builders/v2/reports/conversations/metric_builder.rb` / `report_builder.rb` | conversas: sumário (FRT, p50/p90, resolução) + séries |
| `app/builders/v2/reports/agent_summary_builder.rb` / `base_summary_builder.rb` | métricas por agente a partir de `reporting_events` |
| `app/helpers/api/v2/accounts/heatmap_helper.rb` | dados de heatmap 7d×24h (tráfego/resoluções, por quantil) |
| `app/controllers/api/v2/accounts/live_reports_controller.rb` | métricas do Overview (open/unattended/...) |
| `nps_responses_controller#metrics` + scope `NpsResponse.trusted` | NPS (promotores/detratores/score), já filtrando suspeitos |
| `csat_survey_responses_controller#metrics` | CSAT (distribuição 1-5, satisfação, taxa) |

---

## 2. Arquitetura alvo

```
[Botão "Baixar PDF" na view do relatório]  (Vue, herdado por todas as rotas)
        │ POST /api/v2/accounts/:id/report_pdf_exports  {report_type, filtros}
        ▼
[Reports::PdfExportsController#create]  → cria ReportPdfExport(pending) → enfileira job
        │
        ▼
[Reports::PdfExportJob]  (queue :low)
        │
        ▼
[Reports::PdfExportService(report_type, filtros)]
        ├─ resolve_data: case report_type → chama o BUILDER existente
        ├─ render_html: ApplicationController.renderer.render(
        │       template: "reports/pdf/#{report_type}",   # partial por relatório
        │       layout:   "reports/pdf/layout")           # shell SPX compartilhado
        └─ FerrumPdf.render_pdf(html:, pdf_options:)  → bytes
        │
        ▼
[ActiveStorage attach no ReportPdfExport] → status: completed → signed download_url
        │ GET .../report_pdf_exports/:id (poll) → { status, download_url }
        ▼
[Front baixa o PDF]
```

**Compartilhado (escrito 1 vez):** controller, job, model, service genérico, layout ERB + CSS SPX + partials de bloco (KPI band, tabela, chart, heatmap), helper de charts SVG, botão Vue.
**Por relatório (custo marginal):** 1 partial ERB que escolhe os blocos + 1 branch no `resolve_data`.

---

## 3. Sistema de design SPX (o "shell")

### 3.1. Tokens de marca (de `public/brand/manual-marca-spx.md`)
- **Verde primário** `#2dc46f` (hover `#008c70`) — **≤10% da página** (só destaques/deltas/barras).
- **Fontes:** Inter (corpo) + InterDisplay (títulos). WOFF2 em `public/vite/assets/Inter*.woff2` / `InterDisplay*.woff2`.
- **Página** off-white `#f9fafb`; **cards** brancos; **borda OU sombra, nunca os dois**.
- **Texto:** primário `#111b21`, secundário `#667781`; linhas `#e9edef`.
- **Semânticas:** success `#2dc46f`, warning `#ffc53d`, error `#e54666`.

### 3.2. ⚠️ Lições do PDF-modelo (já validadas — não repetir os erros)
1. **Logo:** usar a **oficial `logo_dark.svg`** (wordmark "ChatSPX" branco) na masthead verde; `logo.svg` (verde) em fundo branco. **NÃO usar `logo_thumbnail-branca.svg`** — é PNG embrulhado e renderiza como contorno fantasma. Para símbolo pequeno em fundo escuro, usar o **vetor inline recortado** (paths do `logo_thumbnail2.svg` com `fill-rule:evenodd`, branco).
2. **Fontes:** **embutir** os WOFF2 via `@font-face` com `url()` **relativo/absoluto acessível** e `font-display:block`; o Chromium do `ferrum_pdf` renderiza server-side — garantir que os arquivos de fonte estejam acessíveis ao processo (caminho absoluto `file://` ou asset servido). Sem isso, cai em fallback.
3. **Backgrounds:** `print-color-adjust: exact` em tudo que tem cor de fundo (senão o Chromium "lava" as cores).
4. **Paginação:** `@page { size:A4; margin:0 }` + padding interno; `break-inside: avoid` em cards/linhas; controlar overflow por página (no modelo, a pág. 3 transbordou por excesso de conteúdo — dividir cedo).
5. **Charts sem JS:** o Chromium do ferrum não roda Chart.js de forma confiável no fluxo server-side; **renderizar gráficos como SVG calculado em Ruby** (ver §5.3).

### 3.3. Os 6 blocos do shell
| Bloco | Spec |
|---|---|
| **Masthead/cover** | Faixa verde no topo; `logo_dark.svg` à esquerda; título InterDisplay ~28px; subtítulo = período + flag business hours. Único uso "grande" do verde. |
| **Period header** | Intervalo de datas, agrupamento (dia/semana/mês), business hours on/off. Cinza, Inter 11px. |
| **KPI band** | Grid 3-4 cards: label (Inter 11px uppercase) + valor (InterDisplay 24px) + delta opcional (verde/vermelho). Card branco, borda OU sombra. |
| **Chart block** | Container branco + título; barras verde `#2dc46f`, linha overlay cinza; heatmap por quantil (azul tráfego / verde resoluções). SVG server-side. |
| **Table block** | Header off-white uppercase; zebra sutil; números à direita; tempos via `formatTime` (s→min/h/d). |
| **Footer** | "Gerado em {data} · Agrupado por {período} · ChatSPX · Simplex Soluções" + nº de página. Sem logo repetido. |

---

## 4. Especificação por relatório

(Métricas reais dos mapas — `.aiox/audit-nps-tozi-2026-06-08/relatorios-mapas.json`.)

| Relatório | KPI band | Charts | Tabela | PDF? |
|---|---|---|---|---|
| **Conversas** | FRT médio, p50/p90 FRT, p50/p90 FRT-após-transferência, customer waiting | grid 8 cards bar/line + heatmap tráfego | resumo opcional | ✅ carro-chefe |
| **Visão Geral** | open, unattended, unassigned, pending, online/busy/offline | 2 heatmaps 7d×24h | agentes + times (open/unattended) | ✅ maior payoff visual |
| **Agentes** | Conversations, Avg FRT, Avg Resolution, Avg Reply | 3 trend charts (conversas, FRT, resolução) | Agente · convs · FRT · FRTA · resolução · reply · resolved | ✅ alto valor |
| **Caixas** | Avg FRT, p50/p90, Avg Reply, FRTA (8 cards) | grid 8 bar/line | Inbox · tipo · métricas | ✅ clone de Agentes |
| **NPS** | Total, NPS Score, Response Rate, Promotores/Passivos/Detratores %, Blocked | barra distribuição 0-10 (verm/âmbar/verde) | Contato · agente · nota · classe | ✅ **começar aqui** (design pronto) |
| **CSAT** | Total, Satisfaction Score, Response Rate | stacked bar distribuição 1-5 | breakdown + amostra de feedbacks | ✅ |
| **Times** | convs, Avg FRT, FRT-após-transf, resolução, customer waiting, resolution count | timeseries opcional | Time · métricas | ✅ 1 página |
| **Bot** | conversation_count, message_count, resolution_rate, handoff_rate | 2 timeseries (resoluções/handoffs) | — | ✅ leve |
| **SLA** | Hit Rate %, nº misses, nº SLAs | barra de tipos de breach | top breaches (conv, policy, assignee, inbox, team) | ✅ enterprise |
| **Etiquetas** | total, convs, Avg FRT, resolução | — | Label · métricas | ⚠️ só tabela — baixa prioridade |

---

## 5. Plano de arquivos (o que criar)

### 5.1. Backend — compartilhado
```
db/migrate/XXXXXX_create_report_pdf_exports.rb
app/models/report_pdf_export.rb
app/controllers/api/v2/accounts/report_pdf_exports_controller.rb
app/jobs/reports/pdf_export_job.rb
app/services/reports/pdf_export_service.rb
app/services/reports/pdf_data_resolver.rb        # case report_type → builder
app/helpers/reports/pdf_chart_helper.rb          # SVG bar/line/heatmap
config/routes.rb                                  # nova rota (editar)
```

### 5.2. Views — shell + blocos + por-relatório
```
app/views/reports/pdf/layout.html.erb            # shell SPX (masthead, css, footer)
app/views/reports/pdf/_kpi_band.html.erb
app/views/reports/pdf/_data_table.html.erb
app/views/reports/pdf/_chart.html.erb
app/views/reports/pdf/_heatmap.html.erb
app/views/reports/pdf/shared.css.erb             # CSS SPX inline (importado pelo layout)
# por relatório (1 cada):
app/views/reports/pdf/_nps.html.erb
app/views/reports/pdf/_csat.html.erb
app/views/reports/pdf/_bot.html.erb
app/views/reports/pdf/_agent_overview.html.erb
app/views/reports/pdf/_inbox_summary.html.erb
app/views/reports/pdf/_team.html.erb
app/views/reports/pdf/_conversations.html.erb
app/views/reports/pdf/_overview.html.erb
app/views/reports/pdf/_sla.html.erb
# (_label.html.erb opcional)
```

### 5.3. Frontend
```
app/javascript/dashboard/components/reports/DownloadPdfButton.vue   # novo, herdado por todas as views
app/javascript/dashboard/store/modules/reportPdfExports.js          # action create + poll
app/javascript/dashboard/api/reportPdfExports.js
# editar cada *ReportsIndex.vue / CsatResponses.vue / NetPromoterScoreReports.vue p/ incluir o botão
```

---

## 6. Esqueletos de referência (scaffolding — não é o código final)

### 6.1. Model + migration
```ruby
# db/migrate/XXXXXX_create_report_pdf_exports.rb
class CreateReportPdfExports < ActiveRecord::Migration[7.1]
  def change
    create_table :report_pdf_exports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :requester_user, foreign_key: { to_table: :users }
      t.string  :report_type, null: false        # nps, csat, agent_overview, ...
      t.integer :status, default: 0, null: false  # pending/processing/completed/failed
      t.jsonb   :filters,    default: {}           # since, until, business_hours, group_by, scope_id
      t.jsonb   :audit_meta, default: {}
      t.string  :sha256
      t.bigint  :file_size
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.string  :error_message
      t.timestamps
    end
  end
end
```
```ruby
# app/models/report_pdf_export.rb
class ReportPdfExport < ApplicationRecord
  belongs_to :account
  belongs_to :requester_user, class_name: 'User', optional: true
  has_one_attached :file
  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  def download_url(expires_in: 24.hours)
    return unless file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(
      file, host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
      expires_in: expires_in, disposition: 'attachment'
    )
  end
end
```

### 6.2. Service genérico (espelha `Conversations::PdfExportService`)
```ruby
# app/services/reports/pdf_export_service.rb
module Reports
  class PdfExportService
    Result = Struct.new(:bytes, :sha256, keyword_init: true)

    def initialize(export:)
      @export = export
    end

    def call
      data = Reports::PdfDataResolver.new(
        account: @export.account, report_type: @export.report_type, filters: @export.filters
      ).resolve
      html = render_html(data)
      bytes = FerrumPdf.render_pdf(html: html, pdf_options: pdf_options)
      Result.new(bytes: bytes, sha256: Digest::SHA256.hexdigest(bytes))
    end

    private

    def render_html(data)
      ApplicationController.renderer.render(
        template: "reports/pdf/#{@export.report_type}",
        layout:   'reports/pdf/layout',
        assigns:  { data: data, export: @export, account: @export.account,
                    period: @export.filters.slice('since', 'until', 'business_hours') }
      )
    end

    def pdf_options
      { format: :A4, print_background: true, prefer_css_page_size: true,
        margin_top: 0, margin_bottom: 0, margin_left: 0, margin_right: 0 }
    end
  end
end
```

### 6.3. Resolver de dados (o único ponto que conhece cada relatório no backend)
```ruby
# app/services/reports/pdf_data_resolver.rb
module Reports
  class PdfDataResolver
    def initialize(account:, report_type:, filters:)
      @account, @report_type, @filters = account, report_type, filters
    end

    def resolve
      case @report_type
      when 'nps'   then nps_data
      when 'csat'  then csat_data
      when 'agent_overview' then agent_data
      # ... demais relatórios chamam os builders JÁ existentes
      else raise ArgumentError, "report_type desconhecido: #{@report_type}"
      end
    end

    private

    def nps_data
      scope = @account.nps_responses.trusted   # reusa scope anti-fraude
      # reusar a mesma lógica do nps_responses_controller#metrics
      { kpis: {...}, distribution: scope.group(:score).count, ... }
    end
    # csat_data, agent_data: idem, chamando MetricBuilder / AgentSummaryBuilder / heatmap_helper
  end
end
```

### 6.4. Controller + Job + rota
```ruby
# app/controllers/api/v2/accounts/report_pdf_exports_controller.rb
class Api::V2::Accounts::ReportPdfExportsController < Api::V1::Accounts::BaseController
  def create
    export = Current.account.report_pdf_exports.create!(
      report_type: params.require(:report_type),
      requester_user: Current.user,
      filters: filter_params.to_h,
      audit_meta: { ip: request.remote_ip, ua: request.user_agent, name: Current.user.name }
    )
    Reports::PdfExportJob.perform_later(export.id)
    render json: { id: export.id, status: export.status }
  end

  def show
    export = Current.account.report_pdf_exports.find(params[:id])
    render json: { status: export.status, download_url: export.completed? ? export.download_url : nil }
  end

  private

  def filter_params
    params.permit(:since, :until, :business_hours, :group_by, :scope_id, :scope_type)
  end
end
```
```ruby
# app/jobs/reports/pdf_export_job.rb
module Reports
  class PdfExportJob < ApplicationJob
    queue_as :low
    def perform(export_id)
      export = ReportPdfExport.find(export_id)
      export.update!(status: :processing, started_at: Time.current)
      result = Reports::PdfExportService.new(export: export).call
      export.file.attach(io: StringIO.new(result.bytes),
                         filename: "#{export.report_type}_#{export.id}.pdf",
                         content_type: 'application/pdf')
      export.update!(status: :completed, sha256: result.sha256,
                     file_size: result.bytes.bytesize, completed_at: Time.current)
    rescue => e
      export&.update(status: :failed, error_message: e.message)
      raise
    end
  end
end
```
```ruby
# config/routes.rb (dentro de namespace api/v2 accounts)
resources :report_pdf_exports, only: %i[create show]
```

### 6.5. Layout shell (ERB) — resumo
```erb
<%# app/views/reports/pdf/layout.html.erb %>
<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8">
  <style><%= render 'reports/pdf/shared.css' %></style>
</head><body>
  <section class="page">
    <div class="mast">
      <img class="mlogo" src="<%= pdf_asset('logo_dark.svg') %>" alt="ChatSPX">
      <div class="doc"><%= @data[:title] %><b>ChatSPX</b></div>
    </div>
    <div class="pad">
      <%= render "reports/pdf/period_header", period: @period %>
      <%= yield %>   <%# o partial do relatório injeta KPI band / charts / table %>
    </div>
    <div class="foot">Gerado em <%= l(Time.current) %> · ChatSPX · Simplex Soluções</div>
  </section>
</body></html>
```
> `pdf_asset` = helper que devolve caminho absoluto `file://` (ou base64) dos logos/fontes acessível ao Chromium server-side.

### 6.6. Charts em SVG puro (helper Ruby) — sem JS
```ruby
# app/helpers/reports/pdf_chart_helper.rb  (ideia)
def svg_bar_chart(series, w: 520, h: 140, color: '#2dc46f')
  max = series.map { _1[:value] }.max.to_f
  bw  = w / series.size
  bars = series.each_with_index.map do |pt, i|
    bh = max.zero? ? 0 : (pt[:value] / max * (h - 20))
    %(<rect x="#{i*bw+4}" y="#{h-bh}" width="#{bw-8}" height="#{bh}" rx="3" fill="#{color}"/>)
  end.join
  %(<svg viewBox="0 0 #{w} #{h}" width="100%">#{bars}</svg>).html_safe
end
```
Heatmap: reusar `HeatmapHelper` (já dá a matriz por quantil) e desenhar `<td>`/`<div>` coloridos.

### 6.7. Botão Vue (herdado por todas as views)
```vue
<!-- DownloadPdfButton.vue -->
<template>
  <woot-button icon="arrow-download" variant="smooth" :is-loading="loading" @click="onClick">
    {{ $t('REPORT.DOWNLOAD_PDF', { default: 'Baixar PDF' }) }}
  </woot-button>
</template>
<script>
export default {
  props: { reportType: String, filters: Object },
  data: () => ({ loading: false }),
  methods: {
    async onClick() {
      this.loading = true;
      const { id } = await this.$store.dispatch('reportPdfExports/create',
        { reportType: this.reportType, ...this.filters });
      // poll show até status=completed → window.open(download_url)
      this.loading = false;
    },
  },
};
</script>
```

---

## 7. Ondas de rollout, esforço e critérios de aceite

| Onda | Entrega | Esforço | Pronto quando… |
|---|---|---|---|
| **0 — Fundação** | shell (layout+css+blocos) + service/resolver/controller/job/model + migration + botão Vue | **L (~3-4 dias)** | botão dispara job → PDF em branco com masthead/footer SPX baixa via link assinado |
| **1 — NPS** | `_nps.html.erb` + branch `nps_data` (reusa design do PDF-modelo) | **XS (~0,5 dia)** | PDF NPS = o modelo de `.aiox/...` gerado pela plataforma com filtros da tela |
| **2 — CSAT** | `_csat` + `csat_data` | **S** | distribuição 1-5 + KPIs + amostra de feedbacks |
| **3 — Bot** | `_bot` + `bot_data` | **S** | KPI band + 2 timeseries |
| **4 — Agentes** | `_agent_overview` + `agent_data` | **M** | tabela densa + 3 trend charts |
| **5 — Caixas** | `_inbox_summary` (clone do Agentes) | **XS** | idem agentes p/ inboxes |
| **6 — Times** | `_team` | **S** | tabela + KPI band |
| **7 — Conversas** | `_conversations` + heatmap | **M** | 8 cards + speed insights + heatmap |
| **8 — Visão Geral** | `_overview` + 2 heatmaps + 2 tabelas | **M** | maior payoff visual |
| **9 — SLA** | `_sla` (enterprise) | **S** | hit rate + tabela de breaches |
| — | Etiquetas (opcional) | XS | só table block |

**Estimativa total: ~9-12 dias.** O grosso é a onda 0; depois é incremental.
**Recomendação:** entregar **Onda 0 + Onda 1 (NPS)** como PoC ponta-a-ponta antes de seguir.

---

## 8. Como construir/testar na homologação

> A homolog é o lugar certo pra isso (não-crítico, `auto_approve`, branch própria). Sequência segura de promoção depois: homolog → AWS (ff via bundle) → produção → Tozi por último.

1. **Branch:** trabalhar em `homologacao` (ou feature branch a partir dela). Commits locais; push/PR via @devops.
2. **Migration:** `RAILS_ENV=production bundle exec rails db:migrate` (homolog roda em production env). ActiveStorage **já existe** (export de conversa usa) — sem setup extra.
3. **Chromium:** já configurado (`/snap/bin/chromium`) e validado (gera o PDF de conversa). Conferir `CHROMIUM_PATH` no `.env` se necessário.
4. **Fontes/logos no PDF:** garantir que `pdf_asset` aponte para caminho acessível ao processo do Chromium (cuidado com confinamento do snap — preferir **base64 embutido** ou caminho sob o home do app, não `/tmp`).
5. **Teste rápido sem UI (rails runner/console):**
   ```ruby
   e = Account.find(1).report_pdf_exports.create!(report_type:'nps', filters:{'since'=>'2026-01-01','until'=>'2026-06-08'})
   Reports::PdfExportJob.perform_now(e.id)
   puts e.reload.status, e.download_url
   ```
6. **Precompile do front** (pro botão aparecer): `pnpm build` / `bundle exec rake assets:precompile` conforme o fluxo da VM. **Não dar restart** — apenas preparar e avisar o responsável (regra da frota).
7. **Validação visual:** abrir o PDF gerado, conferir masthead (logo ChatSPX nítida), KPIs, charts, paginação (sem corte), rodapé.

---

## 9. Riscos e armadilhas (gotchas)

| Risco | Mitigação |
|---|---|
| **Snap Chromium confinado** não lê `/tmp` nem dirs ocultos | Servir fontes/logos por caminho sob o home do app **ou base64 embutido** no HTML |
| **Fontes caem em fallback** no render server-side | `@font-face` com WOFF2 embutido/base64 + `font-display:block`; validar visualmente |
| **Cores "lavadas"** no PDF | `print-color-adjust: exact` em todo elemento colorido + `print_background: true` |
| **Conteúdo transborda a página** (visto no PDF-modelo) | `break-inside: avoid` em cards; dividir seções cedo; testar com volume real |
| **Chart.js não roda** no fluxo ferrum | Charts como **SVG calculado em Ruby** (§6.6) — zero JS |
| **Dataset grande** (ex.: Conversas com período longo) trava o job | reusar paginação/limites dos builders; top-N em tabelas; job em queue `:low` |
| **NPS: notas infladas** do bug antigo | usar scope **`.trusted`** (igual ao `#metrics`) — já exclui suspeitos |
| **Timezone** | seguir o padrão do export de conversa (America/Manaus) para datas |
| **Permissão/escopo** | herdar autorização do controller de reports (admin/agent conforme já é) |
| **i18n do botão** | adicionar chave `REPORT.DOWNLOAD_PDF` (pt-BR + en) |

---

## 10. Checklist do 1º PR (Fundação + NPS)

- [ ] Migration `report_pdf_exports` + model com ActiveStorage + `download_url`
- [ ] `Reports::PdfExportService` + `PdfDataResolver` (com branch `nps`)
- [ ] Controller `report_pdf_exports` (create/show) + rota
- [ ] Job `Reports::PdfExportJob` (attach + status + erro)
- [ ] Layout shell `reports/pdf/layout.html.erb` + `shared.css.erb` (tokens SPX, fontes embutidas, logo_dark.svg)
- [ ] Partials de bloco `_kpi_band`, `_data_table`, `_chart` + `PdfChartHelper`
- [ ] Partial `_nps.html.erb` portando o design de `.aiox/audit-nps-tozi-2026-06-08/relatorio-fonte.html`
- [ ] `DownloadPdfButton.vue` + store/api + plugar na `NetPromoterScoreReports.vue`
- [ ] i18n `REPORT.DOWNLOAD_PDF`
- [ ] Teste via `rails runner` (gera PDF NPS) + teste pela UI na homolog
- [ ] Validação visual (logo nítida, sem corte de página, cores ok)
- [ ] Specs: service gera bytes PDF válidos; controller cria export + enfileira; job completa

---

## Anexos
- Laudo NPS + PDF-modelo + fonte HTML: `.aiox/audit-nps-tozi-2026-06-08/`
- Mapas estruturados dos 10 relatórios: `.aiox/audit-nps-tozi-2026-06-08/relatorios-mapas.json`
- Síntese de produto/design: `.aiox/audit-nps-tozi-2026-06-08/PLANO-PDFs-Relatorios-SPX.md`
- Manual de marca: `public/brand/manual-marca-spx.md`
- Engine de referência: `app/services/conversations/pdf_export_service.rb`
