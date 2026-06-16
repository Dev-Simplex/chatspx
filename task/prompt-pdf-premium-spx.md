# PROMPT — Elevar os PDFs de Relatórios ChatSPX ao padrão premium (Tozi-grade)

> Cole este prompt em uma sessão do Claude Code aberta no repositório, branch `nicolas`, ambiente de homologação.
> Antes de escrever qualquer código, **leia os arquivos reais citados** — eles já existem e funcionam; você vai *refinar*, não recomeçar.

---

## Papel e objetivo

Você é um engenheiro full-stack (Rails + Vue) trabalhando no fork **ChatSPX** (base Chatwoot). A feature de **exportar relatórios como PDF brandeado** já existe e está entregue em v1: cada relatório da aba **Relatórios** tem um botão **"Baixar PDF"** que dispara um job, gera o PDF via Chromium headless e devolve um link assinado. Os 10 relatórios funcionam e geram PDF válido.

**O problema:** os PDFs atuais são corretos mas *visualmente simples* — KPI band + uma tabela, página única. O cliente quer a qualidade do **laudo de auditoria NPS da Tozi** (anexo `Relatorio-NPS-Tozi-SPX.pdf`): um documento executivo premium de várias páginas, com capa, callouts, gauge, gráficos, tabelas com barras de desempenho e rodapé paginado.

**Seu trabalho:** elevar **todos os 10 relatórios** do padrão atual (v1) ao padrão premium "Tozi-grade" (v2), construindo primeiro um **design system compartilhado** (blocos + primitivas de gráfico SVG) e depois reaproveitando-o em cada relatório. O **NPS é a referência pixel-a-pixel** (temos o modelo Tozi exato) — comece por ele como prova de conceito ponta a ponta e depois propague os blocos para os demais.

Regra de ouro: **a métrica já está calculada** no resolver (`Reports::PdfDataResolver`) reusando os builders existentes. Não recrie cálculo. O grosso do trabalho é **view/CSS/helpers de gráfico**. Onde faltar dado (séries temporais, heatmap), adicione um branch no resolver reusando os builders que **já produzem** essas séries — nunca recalcule à mão.

---

## 1. O que já existe (reusar — NÃO reconstruir)

Pipeline genérico, funcionando. Leia antes de mexer:

| Papel | Arquivo |
|---|---|
| Model (status enum, ActiveStorage, sha256, `download_url`, `SUPPORTED_REPORT_TYPES`) | `app/models/report_pdf_export.rb` |
| Controller (`create`/`show`, poll) | `app/controllers/api/v1/accounts/report_pdf_exports_controller.rb` |
| Job (queue, attach, status) | `app/jobs/reports/pdf_export_job.rb` |
| Service (renderer → `FerrumPdf.render_pdf`) | `app/services/reports/pdf_export_service.rb` |
| **Resolver de dados** (todos os 10 tipos, reusa builders reais) | `app/services/reports/pdf_data_resolver.rb` |
| Layout shell (masthead + period + yield) | `app/views/layouts/reports/pdf.html.erb` |
| CSS compartilhado | `app/views/reports/pdf/_shared_css.html.erb` |
| Blocos atuais | `app/views/reports/pdf/_kpi_band.html.erb`, `_data_table.html.erb`, `_summary_report.html.erb` |
| Templates por relatório | `app/views/reports/pdf/{nps,csat,bot,conversations,overview,sla,agent,inbox,team,label}.html.erb` |
| Helper de fontes base64 | `app/helpers/reports/pdf_asset_helper.rb` |
| Helper de gráficos (HOJE só `pdf_progress_bar` + `pdf_nps_distribution`) | `app/helpers/reports/pdf_chart_helper.rb` |
| Front: botão / store (create+poll) / api | `app/javascript/dashboard/components/reports/DownloadPdfButton.vue`, `store/modules/reportPdfExports.js`, `api/reportPdfExports.js` |
| i18n do botão | `app/javascript/dashboard/i18n/locale/{en,pt_BR}/report.json` (`REPORT.DOWNLOAD_PDF`) |
| **Engine de referência** (espelhar escolhas comprovadas: footer, margens) | `app/services/conversations/pdf_export_service.rb`, `app/views/conversations/pdf_export.html.erb`, `app/helpers/conversations/pdf_export_helper.rb` |
| Tokens de marca | `public/brand/manual-marca-spx.md` |

**Dado já resolvido por relatório** (em `pdf_data_resolver.rb` — confira os métodos):
- **nps**: `kpis` (total, nps_score, response_rate, promoters/passives/detractors + `_pct`, blocked), `distribution` (0–10 com `band`), `agents` (name, total, nps_score, positive_pct).
- **csat**: `kpis` (satisfaction, avg_rating, response_rate, satisfied/neutral/unsatisfied), `distribution` (1–5 colorida), `feedbacks` (amostra 12), `agents`.
- **bot**: `kpis` (resolution_rate, conversations, messages, handoff_rate, resolutions, handoffs), `inboxes`.
- **conversations**: `kpis` (8 métricas de velocidade), `table`. ⚠️ **Sem série temporal / sem heatmap hoje.**
- **overview**: `kpis` (open/unattended/unassigned/pending — snapshot live), `agents_table`, `teams_table`. ⚠️ **Sem heatmap hoje.**
- **sla**: `kpis` (hit_rate, total, breaches, compliance), `by_policy`, `breaches_table`.
- **agent/inbox/team/label**: `kpis` (entities, conversations, resolved, avg_frt, avg_resolution), `table`. ⚠️ **Sem trend chart hoje.**

---

## 2. A régua de qualidade — o modelo Tozi decomposto

O laudo Tozi (5 páginas) é construído com estes blocos. **Transforme cada um num partial/helper reutilizável** do design system:

| # | Bloco | O que é (no modelo Tozi) | Vira |
|---|---|---|---|
| 1 | **Capa / masthead premium** | Faixa verde, símbolo ChatSPX, sobrescrito ("RELATÓRIO DE AUDITORIA · CONFIDENCIAL"), título display ~28px, parágrafo-subtítulo | Evoluir `layouts/reports/pdf.html.erb` |
| 2 | **Meta strip** | 4 colunas: CLIENTE · PERÍODO · BASE ANALISADA · EMISSÃO | `_meta_strip.html.erb` (campos data-driven por relatório) |
| 3 | **Callout / verdict** | Caixa com tint verde, ícone ✓, headline + parágrafo ("Não há indício de manipulação…") | `_callout.html.erb` (variants: `success`/`warning`/`info`/`neutral`) |
| 4 | **Hero stat + composição** | Número gigante (`86`) + label + pill de zona, ao lado de barra segmentada empilhada + legenda com contagens | `_hero_stat.html.erb` + `_composition_bar.html.erb` |
| 5 | **Gauge / escala** | Barra gradiente −100→+100 com marcador na posição do score + rótulos de zona (Crítico/Aperfeiçoar/Qualidade/Excelência) | helper `pdf_gauge(...)` (SVG) |
| 6 | **Seções numeradas + check-cards** | "1 Como a auditoria foi conduzida" + cards com ✓, título e descrição (metodologia) | `_section` (já existe o título) + `_check_cards.html.erb` |
| 7 | **Distribuição** | Barras horizontais por nota, cor por faixa | `pdf_nps_distribution` (já existe — manter) |
| 8 | **Tabela com barra de desempenho** | Atendente · avaliações · barra proporcional colorida por zona · badge do índice | `_perf_table.html.erb` (generalizar o que NPS/CSAT/SLA já fazem inline) |
| 9 | **Split table** | Duas tabelas lado a lado ("Avaliou — nota preservada" / "Não avaliou") | `_split_table.html.erb` |
| 10 | **Recomendações** | Grid de cards numerados (1–4) com título + texto | `_recommendations.html.erb` |
| 11 | **Conclusão** | Caixa escura (fundo `#0f1f17`), símbolo, texto com destaque verde | `_conclusion.html.erb` |
| 12 | **Rodapé paginado** | "Relatório gerado por ChatSPX · Simplex Soluções" (esq.) + "Título · **pág. X/Y**" (dir.) em **toda** página | footer do Chromium (`display_header_footer` + `footer_template` com `.pageNumber`/`.totalPages`) — ver §4 |
| — | **Gráficos** que faltam | barra vertical (série temporal), linha/sparkline, heatmap 7d×24h | helpers `pdf_bar_chart`, `pdf_line_chart`, `pdf_heatmap` (SVG, §3) |

Tokens (de `public/brand/manual-marca-spx.md` — já refletidos no `_shared_css`): verde `#2dc46f` (hover `#008c70`, **≤10% da página**), página `#f9fafb`, card branco, **borda OU sombra, nunca os dois**, texto `#111b21`/`#667781`, linhas `#e9edef`, success `#2dc46f` / warning `#ffc53d` / error `#e54666`. Fontes Inter (corpo) + InterDisplay (títulos).

---

## 3. Trabalho A — Design system compartilhado (~70% do esforço, escrito 1 vez)

1. **Primitivas de gráfico SVG** em `app/helpers/reports/pdf_chart_helper.rb` (manter o padrão atual: SVG calculado em Ruby, `html_safe` controlado, **zero JS** — o Chromium do ferrum não roda Chart.js de forma confiável):
   - `pdf_gauge(value:, min:, max:, zones:)` — barra gradiente + marcador + rótulos de zona.
   - `pdf_bar_chart(series, color:)` — barras verticais para série temporal (conversas/dia, resoluções/dia…).
   - `pdf_line_chart(series)` / sparkline — tendência (FRT, resolução).
   - `pdf_heatmap(matrix)` — 7 linhas (dias) × 24 colunas (horas), célula colorida por quantil (azul tráfego / verde resoluções).
   - `pdf_composition_bar(segments)` — barra empilhada (promotores/passivos/detratores; satisfeito/neutro/insatisfeito).
   - Mantenha `pdf_progress_bar` e `pdf_nps_distribution`.
2. **Partials de bloco** novos em `app/views/reports/pdf/`: `_meta_strip`, `_callout`, `_hero_stat`, `_composition_bar`, `_check_cards`, `_perf_table`, `_split_table`, `_recommendations`, `_conclusion`. Cada um recebe `locals` simples (data-driven) e é agnóstico ao relatório.
3. **CSS** em `_shared_css.html.erb`: estender com as classes dos novos blocos. Respeitar **`print-color-adjust: exact`** em todo elemento colorido, **`break-inside: avoid`** em cards/linhas/seções, e a regra do verde ≤10%.
4. **Layout/capa**: evoluir `layouts/reports/pdf.html.erb` para a masthead premium (sobrescrito + título display + subtítulo) e renderizar `_meta_strip` logo abaixo. Manter o **símbolo vetor inline** atual (paths de `logo_thumbnail2.svg`) — **não** trocar por `logo_dark.svg` (PNG embrulhado, borra).
5. **Rodapé paginado por página** (§4).

---

## 4. Rodapé com paginação "pág. X/Y" (ponto técnico crítico)

O modelo Tozi tem rodapé em **todas** as páginas com número de página. O `pdf_export_service.rb` hoje zera as margens (`margin_*: 0`). Para footer nativo do Chromium:
- Passe em `pdf_options`: `display_header_footer: true`, um `margin_bottom` reservado (~16mm), e `footer_template` (HTML pequeno usando as classes do Chromium `.pageNumber` / `.totalPages`, com `font-size:9px`). Cabeçalho vazio (`header_template: '<span></span>'`).
- **Verifique a API real do `ferrum_pdf`** (nomes podem ser `display_header_footer`/`footer_template` em snake_case) e espelhe o que o **export de conversa** já faz, se ele resolve isso. Se o footer nativo não cooperar com `prefer_css_page_size`, alternativa: rodapé `position:fixed; bottom:0` repetido + CSS counters — mas teste a numeração real.
- Aceite: abrir o PDF e ver "pág. 1/N … N/N" correto, sem sobrepor conteúdo.

---

## 5. Trabalho B — Reescrever cada relatório no padrão premium

Para cada um, monte a página com os blocos do §2 usando o **dado já resolvido** (§1). Onde marcado ⚠️, **adicione antes o branch de dado no resolver** reusando o builder indicado (ele já entrega a série; só montar a estrutura):

| Relatório | Layout premium alvo | Dado extra a resolver |
|---|---|---|
| **nps** ⭐ | **Pixel-match do modelo Tozi**: capa+meta strip → `_callout` verdict (data-driven: "X detratores e Y notas 0 preservados") → `_hero_stat` (nps_score) + `_composition_bar` → `pdf_gauge(-100..100)` → distribuição → `_perf_table` por atendente (barra colorida + badge) → `_recommendations` → `_conclusion`. | — (tudo já existe) |
| **csat** | capa+meta → hero (satisfaction%) + composition (1–5) → distribuição → `_perf_table` por atendente → amostra de feedbacks (`_split_table` ou tabela) → conclusão | — |
| **bot** | capa+meta → KPI band → `pdf_bar_chart` resoluções/dia + handoffs/dia → tabela por caixa | `bot` timeseries via `reporting_events` agrupados por dia |
| **conversations** | capa+meta → KPI band (8 cards) → `pdf_bar_chart` conversas/dia + `pdf_line_chart` FRT → **`pdf_heatmap` tráfego** → tabela de velocidade | série temporal via `V2::Reports::Conversations::ReportBuilder`; heatmap via `Api::V2::Accounts::HeatmapHelper` |
| **overview** | capa+meta → KPI band → **2 heatmaps** (tráfego + resoluções) → tabelas agente/time com `_perf_table` | 2 matrizes via `HeatmapHelper` |
| **agent** | capa+meta → KPI band → 3 trend charts (conversas, FRT, resolução) → `_perf_table` densa | séries por agente via `V2::Reports::ReportBuilder` (timeseries) |
| **inbox** | clone de **agent** para caixas | idem agent |
| **team** | capa+meta → KPI band → tabela + callout-resumo | opcional timeseries |
| **label** | capa+meta → KPI band → tabela (só tabela; baixa prioridade) | — |
| **sla** | capa+meta → KPI band → `pdf_composition_bar` por tipo de breach → `_perf_table` por política → tabela de descumprimentos | — (guardar `ChatwootApp.enterprise?`, já feito) |

**Narrativa data-driven:** os blocos editoriais (callout/verdict, recomendações, conclusão) devem ser **gerados a partir dos números**, não texto fixo. Ex.: o callout do NPS se monta de `kpis[:detractors]`/`distribution`; a conclusão resume score + zona. Para relatórios sem narrativa óbvia, o callout vira um **highlight automático** (ex.: "FRT médio: 2m11s · p90: 8m04s") e a conclusão um parágrafo-resumo. **Não invente fatos** que o dado não suporta.

---

## 6. Restrições inegociáveis (gotchas já resolvidos — não regredir)

- **Fontes**: embutidas base64 via `pdf_font_face_css` (glob em `public/vite/assets`, nomes com hash). Não hardcode hash, não use caminho `file://` solto (snap confinado).
- **Logo da masthead**: símbolo **vetor inline** (paths de `logo_thumbnail2.svg`). **Nunca** `logo_thumbnail-branca.svg` nem `logo_dark.svg` (PNG embrulhado → contorno fantasma/borrado).
- **Cores**: `print-color-adjust: exact` em todo elemento colorido + `print_background: true` (senão o Chromium "lava" as cores).
- **Gráficos**: **SVG calculado em Ruby**, zero JS/Chart.js.
- **Paginação**: `@page { size:A4; margin:0 }` (já está), `break-inside: avoid` em cards/linhas; dividir seções cedo p/ não transbordar (no modelo Tozi a pág. 3 estourou — controle o volume, use top-N nas tabelas).
- **NPS anti-fraude**: usar o scope **`.trusted`** (já no resolver) — exclui suspeitos.
- **Timezone**: `America/Manaus` (constante `TZ` no resolver).
- **Verde ≤10%** da área da página — só destaques/barras/deltas.
- **Volume**: dataset grande não pode travar o job (`queue :low`); reusar limites dos builders, top-N em tabelas.

---

## 7. Sequência de execução

1. **Leia** os arquivos do §1 (resolver, layout, `_shared_css`, `nps.html.erb`, chart helper, service de conversa de referência) e o anexo Tozi.
2. **Design system** (§3): primitivas SVG + partials de bloco + CSS + capa + rodapé paginado (§4).
3. **NPS pixel-match** (§5 ⭐): reescreva `nps.html.erb` para reproduzir o laudo Tozi. **Esta é a PoC** — gere e compare lado a lado com o anexo antes de seguir.
4. **Valide** o NPS (smoke + visual). Só então **propague** os blocos para csat → bot → sla → agent → inbox → team → overview → conversations → label (deixe os que pedem dado novo — overview/conversations/agent/bot — para o fim de cada lote, adicionando o branch no resolver).
5. Garanta que o **botão "Baixar PDF" continua em todas as views** (já está; só confirme após mudanças no front, se houver).

---

## 8. Como validar (homologação — sem reiniciar serviço)

- **Smoke por tipo** (rails runner / console), p/ cada um dos 10:
  ```ruby
  e = Account.find(1).report_pdf_exports.create!(report_type:'nps', filters:{'since'=>'2026-01-01','until'=>'2026-06-08'})
  Reports::PdfExportJob.perform_now(e.id)
  puts e.reload.status, e.file_size, e.download_url
  ```
  (a conta #1 do homolog está **populada** via `task/pdf_demo_seed.rb` — ~140 conversas, nps/csat/sla/bot).
- **Specs**: rodar e manter verdes os specs existentes (`spec/services/reports/`, `spec/jobs/reports/`, `spec/requests/api/v1/accounts/report_pdf_exports_controller_spec.rb`, `spec/models/report_pdf_export_spec.rb`). Acrescente specs para as novas primitivas de gráfico e branches de dado.
- **Lint**: `rubocop` (backend) e `eslint` (front) limpos. Helpers SVG mantêm `# rubocop:disable Rails/OutputSafety` só no escopo necessário.
- **Front** (se mexer no Vue): `bundle exec vite build` — o homolog roda Puma em production, **sem vite dev server**, então precisa build. **Não reiniciar** o serviço — apenas preparar e avisar o responsável (regra da frota).
- **Visual**: abrir cada PDF e conferir — logo nítida, fontes Inter aplicadas (não fallback), cores não lavadas, gauge/charts corretos, **rodapé com pág. X/Y**, sem corte de conteúdo entre páginas, verde discreto.

---

## 9. Critérios de aceite (Tozi-grade)

- [ ] Design system: primitivas SVG (`pdf_gauge`, `pdf_bar_chart`, `pdf_line_chart`, `pdf_heatmap`, `pdf_composition_bar`) + partials (`_meta_strip`, `_callout`, `_hero_stat`, `_composition_bar`, `_check_cards`, `_perf_table`, `_split_table`, `_recommendations`, `_conclusion`) prontos e reutilizados.
- [ ] Capa premium (sobrescrito + título display + subtítulo) + meta strip 4-col em **todos** os 10 relatórios.
- [ ] **Rodapé com `pág. X/Y` em toda página** de todos os PDFs.
- [ ] **NPS reproduz o laudo Tozi** (capa, verdict callout, hero+composição, gauge −100..+100, distribuição, tabela por atendente com barra+badge, recomendações, conclusão).
- [ ] Charts reais onde o §5 pede (bot/agent timeseries, conversations/overview heatmap) — com dado vindo dos builders, não recalculado.
- [ ] Os 10 geram PDF válido no smoke; specs + rubocop + eslint verdes.
- [ ] Botão "Baixar PDF" presente e funcional em cada relatório.
- [ ] Nenhum gotcha do §6 regrediu (fontes base64, logo inline, cores exatas, SVG-only, `.trusted`, timezone).

---

## 10. Regras da frota (NÃO violar)

- Trabalhar **só na branch `nicolas`**, ambiente **homologação**. **Não commitar / não abrir PR** — commit e PR saem via **@devops**.
- **Não reiniciar** Puma/Sidekiq. Build de assets quando necessário, e avisar o responsável.
- Ordem de promoção depois (fora deste escopo): homolog → AWS → produção → Tozi por último.
- Migration já aplicada (`20260609120000_create_report_pdf_exports`); `schema.rb` está congelado e **não** reflete a tabela — não tente "consertar" o schema.
