# F2 — Auditoria de front-end: Relatórios, Campanhas, Kanban/Funil

**Ambiente:** `http://localhost:3000` (mesmo código de `chatspx.app` / homologação, VM .232)
**Conta:** 3 — Simplex Tecnologia (606 conversas, 16 inboxes)
**Usuário:** `playwright-test@simplex.local` (admin)
**Ferramenta:** Playwright 1.59.1, Chromium headless
**Viewports:** 1440×900 e 1280×800 · **Temas:** claro e escuro
**Data:** 29/07/2026
**Screenshots:** `plano/auditoria-front/evidencias-f2/`

---

## Resumo

35 achados com evidência. O mais grave é um **número errado apresentado como verdade** no Painel do Kanban
(mostra 585 cartões/152 abertos quando o funil tem 85/48), seguido de um **botão que nunca funciona em 14 telas**
("Baixar PDF", quebrado por um caminho de Chromium inexistente) e um **botão ilegível no tema claro**
("Ativar Tempo Real", 1,39:1 de contraste).

O padrão dominante é **i18n**: o produto exige pt-BR, mas datas, meses e unidades de tempo saem em inglês em
praticamente toda a área de Relatórios (`Jul 23 - Jul 29, 2026`, `23-Jul`, `41 Day 8 Hr`, `6 Min 40 Sec`).
Todas essas falhas têm origem em ~5 linhas de código — conserto barato, ganho visível em todas as telas.

O botão que "some" ao clicar, relatado pelo Walisson, **não foi reproduzido** nesta área — mas achei dois
candidatos ao sintoma que o usuário descreveria assim (#2 e #3).

---

## Achados

| # | sev | rota/tela | o que acontece | evidência | conserto sugerido |
|---|-----|-----------|----------------|-----------|-------------------|
| 1 | **P0** | `/kanban` → aba **Painel** | O Painel ignora o funil selecionado e conta a **conta inteira**. Mostra "CARTÕES 585 / ABERTAS 152" e a tabela "Abertos 152 · Resolvidos 433" — enquanto o mesmo funil, no mesmo cabeçalho, diz "85 itens" e as colunas dizem 48/0/37. Um gestor lê 152 abertos onde há 48. | API do funil: `GET /funnels/9/funnel_items?stage_id=25` → **48** itens; `stage_id=26` → **0**; `stage_id=27` → **37**. Painel exibe 152/0/433. Banco (conta 3 inteira): `open=152, resolved=433` — bate com o Painel, não com o funil. `evidencias-f2/kanban-Painel.png` vs `kanban-light.png` | Passar `funnel_id` na query que alimenta o Painel, como já é feito em `funnel_items`. Enquanto não passar, a aba não deve dizer "CRM KANBAN" no título do bloco. |
| 2 | **P1** | **14 telas** de `/reports/*` e `/live/in_service` | **"Baixar PDF" nunca gera PDF.** O backend aceita (`202`), o job falha 1,5 s depois e o front mostra um toast que some em ~2 s. Nenhuma das 14 telas consegue exportar PDF. | `POST /api/v1/accounts/3/report_pdf_exports` → `202 {"status":"pending"}`; `GET .../5` → `200 {"status":"failed","error_message":"Errno::ENOENT: No such file or directory - /snap/bin/chromium"}`. `ls /snap/bin/chromium` → não existe. `config/initializers/ferrum_pdf.rb:13` usa `ENV.fetch('CHROMIUM_PATH', '/snap/bin/chromium')` e `CHROMIUM_PATH` não está no `.env`. | Definir `CHROMIUM_PATH` no `.env` para o Chromium real da VM (ou instalar o pacote). Depender de caminho `snap` fixo quebra em qualquer VM de cliente que não use snap — vale trocar o default por uma busca em `PATH`. |
| 3 | **P1** | `/live/in_service` (tema **claro**) | Botão **"Ativar Tempo Real"** com texto branco sobre cinza claro: praticamente invisível. É o principal controle da tela. No tema escuro está legível — o defeito é só no claro. | Contraste medido **1,39:1** (mínimo 4,5:1). `color: rgb(255,255,255)` sobre `background: rgb(217,219,223)`. Origem: `CreepyButton.vue:85-88` — `text-white` fixo + `bg-n-slate-5` no estado inativo. Recorte: `evidencias-f2/btn-tempo-real.png` | No estado inativo, trocar `text-white` por uma cor de texto do tema (`text-n-slate-12`), ou escurecer o fundo inativo. O `text-white` só faz sentido junto com `bg-n-teal-5` (estado ativo). |
| 4 | **P1** | **todas** as telas de `/reports/*` | Seletor de período mostra a data **em inglês**: `Jul 23 - Jul 29, 2026`. Aparece em Conversas, Agentes, Caixas, Times, Rótulos, CSAT, SLA, Bot e nos 4 relatórios antigos. | Texto lido do DOM em 12 rotas. Origem: `components/ui/DatePicker/components/DatePickerButton.vue:43` e `:47` — `format(startDate, 'MMM d, yyyy')` do date-fns **sem `{ locale }`**. | `import { ptBR } from 'date-fns/locale'` e usar `format(d, 'dd/MM/yyyy', { locale: ptBR })`. O padrão certo já existe no repo: `Kanban/ScheduleDateTimePicker.vue:149`. |
| 5 | **P1** | `/reports/overview` | Heatmaps "Tráfego de conversa" e "Resoluções" rotulam as linhas com **mês em inglês**: `Quinta-feira / Jul 23, 2026`. Metade da linha em pt-BR, metade em inglês, lado a lado. | `evidencias-f2/rep-overview-light.png`. Origem: `components/heatmaps/BaseHeatmap.vue:54` — `format(new Date(dateString), 'MMM d, yyyy')` sem locale. | Mesmo conserto do #4: `format(d, 'dd/MM/yyyy', { locale: ptBR })`. |
| 6 | **P1** | `/reports/bot` e demais gráficos de barra | Eixo X em inglês: `23-Jul`, `24-Jul`, …, `29-Jul`. | `evidencias-f2/rep-bot-light.png`. Origem: `ReportContainer.vue:107`, `:109`, `:118` — `format(..., 'dd-MMM')` sem locale; `:113` — `'MMM-yyyy'`. | `format(d, 'dd/MM', { locale: ptBR })` para dia e `'MMM/yy'` com locale para mês. |
| 7 | **P1** | `/reports/conversation`, `/reports/agents_overview`, `/reports/inboxes_overview`, `/reports/teams_overview`, `/reports/labels_overview` | **Unidades de tempo em inglês** nos números principais: `6 Min 40 Sec`, `41 Day 8 Hr`, `16 Day 22 Hr`, `1 Sec`, `meta 4 Hr`, `meta 10 Min`. São os valores que o gestor lê primeiro. | Lido do DOM em 5 rotas. Origem: `formatTime()` de `@chatwoot/utils` (`dist/utils.esm.js:925-953`) — strings `" Min"`, `" Sec"`, `" Hr"`, `" Day"` **hardcoded**, sem passar por i18n. | Criar um `formatDuration()` local no dashboard que use `$t` (`REPORT.UNITS.DAY/HOUR/MIN/SEC`) e trocar os imports de `formatTime`. Mexer na lib externa não é necessário. |
| 8 | **P1** | `/campaigns/live_chat` e `/campaigns/sms` | O estado vazio desenha **cartões de campanha falsos, em inglês, com marca de terceiro**: "Chatbot Assistance", "PaperLayer Website", "Alexa Rivera", `Hello! Enjoying our product? Share your feedback on G2 and earn a $25 Amazon coupon: https://chwt.app/g2-review`, `Oct 24, 1:13 PM`. Num produto white-label, isso expõe a marca do upstream (Chatwoot) para o cliente final. | `evidencias-f2/camp-sms-light.png`, `camp-livechat-light.png`. Origem: `components-next/Campaigns/EmptyState/CampaignEmptyStateContent.js` — dados fixos com `chatwoot.com`, "PaperLayer", cupom Amazon. | Traduzir para pt-BR e trocar por exemplos genéricos da Simplex, ou remover o mockup e deixar só o texto do estado vazio (que já é bom). |
| 9 | **P1** | `/kanban` (quadro) | Chips de tempo do cartão colapsam para **largura zero** — "21 dias", "6 dias", "2 meses", "26 dias" ficam **invisíveis**. É a informação que a própria tela de "Legenda e ajuda" ensina a ler. | Medido: `scrollWidth=39px, clientWidth=0px` para "21 dias"; idem "6 dias" (35→0), "2 meses" (47→0). Wrapper: `flex min-w-0 max-w-[120px] items-center gap-1 rounded-full px-1.5` com apenas 27-30px de largura real. | O `min-w-0` no wrapper permite o colapso total. Dar `min-w-fit` ao chip (ou `flex-shrink-0` ao texto) e deixar o `max-w-[120px]` cuidar do limite superior. |
| 10 | **P1** | `/kanban` (quadro) | Telefone do contato truncado para `+5…` no cartão. Identificar o contato pelo número fica impossível. | `+5566996822686`: `scrollWidth=93px, clientWidth=26px`. Idem `+5566996350491` (93→27) e `+556690000041` (86→23). Tem `title`, mas exige hover. | Mesmo conserto do #9 — o número precisa de ~95px. Se o cartão não comporta, mostrar os 4 últimos dígitos (`…6822686`) em vez de cortar o prefixo, que é sempre igual. |
| 11 | **P1** | todo o produto (botão primário verde) | Contraste **2,27:1** no botão primário: "Criar campanha", "Baixar relatórios de conversas/agentes/entrada/time/etiquetas/CSAT/SLA", "Exportar CSV", "Agendar Mensagem". Menos da metade do mínimo. | `color: rgb(255,255,255)` sobre `rgb(45,196,111)` = **2,27:1** (mínimo 4,5:1). Medido em 9 telas, nos dois temas. | Escurecer o verde do botão primário para ~`#1B8F4D` (dá ~4,6:1 com branco) **ou** usar texto escuro sobre o verde atual. Mexe numa variável só e conserta o produto inteiro. |
| 12 | **P1** | `/campaigns/whatsapp` | Data da campanha em inglês com AM/PM: `Enviado de SimplexIA ativado Jun 10, 5:34 PM`. Além do idioma, a frase está quebrada — "ativado" é tradução literal de "on". | `evidencias-f2/camp-whatsapp-light.png`. Origem: `components-next/Campaigns/CampaignCard/SMSCampaignDetails.vue:39` — `messageStamp(new Date(scheduledAt), 'LLL d, h:mm a')`. | `'dd/MM, HH:mm'` com locale ptBR, e reescrever a frase para "Enviado de SimplexIA em 10/06, 17:34". |
| 13 | **P1** | `/reports/csat`, `/reports/nps`, `/reports/conversation` | O bloco AUTO-INSIGHTS mostra **a mesma métrica como "Destaque" e como "Ponto de atenção" ao mesmo tempo**. No CSAT: "Destaque: Satisfação, meta 85%" ao lado de "Ponto de atenção: Satisfação, meta 85% — precisa melhorar". No NPS idem, com 0 respostas e todos os cards em `--`. | `evidencias-f2/rep-csat-light.png`, `rep-nps-light.png` | Quando não há dado suficiente, esconder o bloco (ou mostrar "sem dados no período"). Nunca eleger a mesma métrica para os dois lados. |
| 14 | **P1** | `/kanban` → Painel | Gráfico "Carga por agente": rótulos do eixo X **rotacionados e sobrepostos** entre si, ilegíveis; "Playwright Test" escapa da borda direita do card. A série usa **azul**, destoando do verde da marca usado no gráfico ao lado. | `evidencias-f2/kanban-Painel.png` — card termina em x=1424 e o rótulo passa dele. | Rotacionar 90° (não ~45°) ou truncar o nome em 12 caracteres com tooltip; aumentar a margem inferior do gráfico. Alinhar a cor à paleta dos outros gráficos. |
| 15 | **P1** | `/reports/agent` (relatório antigo) | **Chave de i18n crua na tela**: o botão mostra literalmente `REPORT.DOWNLOAD_AGENT_REPORTS`. | Lido do DOM: `<span class="min-w-0 truncate">REPORT.DOWNLOAD_AGENT_REPORTS</span>`. As telas irmãs (`/reports/inboxes`, `/label`, `/teams`) mostram o texto certo. | Adicionar a chave `REPORT.DOWNLOAD_AGENT_REPORTS` em `i18n/locale/pt_BR/report.json` (as outras três já existem). |
| 16 | **P1** | `/reports/sla` | Mostra **"TAXA DE ACERTO 100%"** com "Nº DE CONVERSAS 0". 100% de nada. Um gestor conclui que o SLA está perfeito. | `evidencias-f2/rep-sla-light.png` — os três cards: 100% / 0 / 0. | Com denominador 0, exibir `--` (como o NPS já faz) em vez de 100%. |
| 17 | **P2** | `/reports/bot` | Números que se contradizem no mesmo bloco: "Nº DE CONVERSAS **0**" e "TOTAL DE RESPOSTAS **0**", mas logo abaixo "CONTAGEM DE RESOLUÇÃO **7**". Além disso "TEMPO DE RESOLUÇÃO" é exibido como **0%** — tempo em porcentagem. | `evidencias-f2/rep-bot-light.png` | Revisar a origem das 4 métricas do topo (provavelmente filtram por período diferente do gráfico). Trocar a unidade de "Tempo de resolução" de % para duração. |
| 18 | **P2** | `/campaigns/*` → "Criar campanha" | O formulário abre como **popover sem overlay e sem `role="dialog"`**. O conteúdo atrás continua visível e clicável; leitor de tela não anuncia diálogo; o foco não fica preso. | `document.querySelectorAll('[role=dialog]').length === 0`; nenhum elemento `position:fixed` cobrindo a viewport; `document.elementFromPoint(400,400)` retorna `MAIN.flex-1 px-6 overflow-y-auto` (o conteúdo de trás). | Adicionar `role="dialog"` + `aria-modal="true"`, backdrop e focus trap — ou usar o componente de diálogo que o resto do produto já usa. |
| 19 | **P2** | `/campaigns/*` → "Criar campanha" | O botão **"Criar" desabilitado usa exatamente a mesma cor do habilitado**. Não dá para saber que o formulário está incompleto. Nenhum campo indica ser obrigatório. | `disabled=true` com `color: rgb(255,255,255)`, `background: rgb(45,196,111)` — mesmos valores do estado ativo. Contraste 2,27:1. `evidencias-f2/camp-wa-modal.png` | Aplicar o estado desabilitado do design system (fundo acinzentado + `cursor: not-allowed`) e marcar os campos obrigatórios. |
| 20 | **P2** | `/live/in_service` | Agentes sem conversa ("Jailson Costa", "Rogerio José da Silva") renderizam um **card em branco** — nenhuma mensagem de estado vazio. Nos dois temas. | `evidencias-f2/rep-live_in_service-light.png` e `d-live-dark.png` | Exibir "Nenhuma conversa em atendimento" dentro do card, como o Kanban já faz na coluna vazia. |
| 21 | **P2** | `/live/in_service` | Os cards de agente têm altura fixa e **cortam o último item ao meio**, sem indicação de que há mais conteúdo ("Angela Tozi", "Nilton Rocha" aparecem seccionados horizontalmente). | `evidencias-f2/rep-live_in_service-light.png` | Ajustar a altura para um número inteiro de linhas, ou aplicar um degradê no fim da lista sinalizando rolagem. |
| 22 | **P2** | `/kanban` a **1280px** | O placeholder **"Criar Etapa" fica parcialmente fora da tela** e não há como rolar até ele. | Medido em 1280×800: borda direita do botão em `right=1356px`, viewport `clientWidth=1280px` — 76px fora. `document.documentElement.scrollWidth === clientWidth`, ou seja, a página **não** rola horizontalmente para alcançá-lo. `evidencias-f2/w-kanban-1280.png` | Dar `overflow-x: auto` ao contêiner de colunas. Hoje a coluna extra simplesmente some em telas de 1280px. |
| 23 | **P2** | CSV de `/reports/conversation` | Cabeçalho do arquivo com **data em ISO, não pt-BR**: `Reportando o período 2026-07-23 a 2026-07-29`. "Reportando o período" é tradução literal de "Reporting period". Os títulos das colunas misturam capitalizações: "Mensagens Recebidas" e "Mensagens enviadas" na mesma linha. | Arquivo baixado: `conversation-report-29-07-2026.csv` (265 bytes), conteúdo lido. | `Período do relatório: 23/07/2026 a 29/07/2026`. Padronizar as colunas em capitalização de frase. |
| 24 | **P2** | `/reports/nps` | O NPS usa **um layout de filtros diferente de todas as outras telas de relatório**: 4 selects em caixa branca, em vez do chip "Últimos 7 dias" + "Adicionar filtro" usado nas outras 11 telas. O select "Selecionar caixa de entrada" quebra em 2 linhas e fica mais alto que os vizinhos. | `evidencias-f2/rep-nps-light.png` vs `rep-csat-light.png` | Migrar o NPS para o mesmo cabeçalho de filtros das outras telas de relatório. |
| 25 | **P2** | `/kanban` (toolbar) | **12 botões de 28×28px sem `aria-label`** (só `title`): Kanban, Lista, Agenda, Painel, Visão compacta, Mostrar capas de etiqueta, Automações, Editar Funil, Excluir Funil, Criar Funil… Todos são ícone puro. Alvo recomendado: 44×44. | Medido: `w=28,h=28` nos 12; `aria-label=null` em 10 deles (só "Priorizar por tempo de espera" e "Legenda e ajuda" têm). | Aumentar a área clicável para ≥44×44 (padding, sem crescer o ícone) e copiar o `title` para `aria-label`. |
| 26 | **P2** | banner global (visível em todas as telas auditadas) | O botão **"Recusar" tem 24×24px** e o "Ir para Conexões" 127×**24**px — muito abaixo de 44px de altura. O texto do banner está a 4,37:1. | Medido em 16 rotas: `24x24` e `127x24`. Contraste `rgb(255,255,255)` sobre `rgb(220,62,66)` = 4,37:1 (mínimo 4,5). | Aumentar a altura dos dois para 44px e escurecer levemente o vermelho do banner. |
| 27 | **P2** | modais de campanha | **Dois rótulos diferentes para o mesmo campo** no mesmo módulo: "Selecione uma caixa de entrada" (WhatsApp) e "Selecionar caixa de entrada" (SMS). | `evidencias-f2/camp-wa-modal.png` vs `camp-sms-modal.png` | Padronizar em "Caixa de entrada" (rótulo) — o verbo pertence ao placeholder, não ao label. |
| 28 | **P2** | modais de campanha | Placeholders com **"Por favor"**: `Por favor, digite o título da campanha`, `Por favor, insira a mensagem da campanha`. Tradução literal de "Please enter…"; em pt-BR o placeholder não pede licença. | `evidencias-f2/camp-sms-modal.png` | "Título da campanha", "Mensagem que será enviada". |
| 29 | **P2** | `/kanban` → Lista | A coluna **"AGENDADAS"** exibe o valor **"Nenhum"** — concordância errada (deveria ser "Nenhuma"). As colunas "ETAPA" e "STATUS" repetem a mesma informação ("Abertos" / "Aberto"). | `evidencias-f2/kanban-Lista.png` | Trocar para "Nenhuma"; avaliar remover uma das duas colunas redundantes. |
| 30 | **P3** | `/reports/overview`, seletor de período, nomes de funil | `text-transform: capitalize` aplicado a frases em pt-BR: **"Todos Os Times"**, **"Manutenção & Prestadores"**, **"Intervalo De Data"**. Title case é convenção do inglês. | `getComputedStyle().textTransform === 'capitalize'` nos três. | Remover o `capitalize` desses seletores e escrever o texto já com a capitalização correta no i18n. |
| 31 | **P3** | `/reports/overview` | Dias da semana com capitalização inconsistente na mesma coluna: **"Segunda-Feira"** (F maiúsculo) entre "Terça-feira", "Quinta-feira", "Quarta-feira" (f minúsculo). | `evidencias-f2/rep-overview-light.png` | Vem do mesmo `capitalize` do #30 atuando sobre um hífen. Resolver junto. |
| 32 | **P3** | `/reports/conversation`, `/reports/bot` | Legenda dos gráficos renderizada como **`( Total )`**, com espaços dentro dos parênteses. | Lido do DOM nas duas rotas. | `(Total)`. |
| 33 | **P3** | `/kanban` → Painel | Título de bloco usando **"&"** em vez de "e": "Envelhecimento & SLA por coluna". | `evidencias-f2/kanban-Painel.png` | "Envelhecimento e SLA por coluna". |
| 34 | **P3** | `/kanban` → Agenda | Os eventos aparecem só como **"Conversa #652"**, sem o nome do contato — três agendamentos idênticos em dias diferentes. O número no canto de cada dia (o "1") não tem explicação. | `evidencias-f2/kanban-Agenda.png` | Mostrar o nome do contato no evento e dar um `title` ao contador do dia. |
| 35 | **P3** | `/reports/overview` vs `/live/in_service` | Dois números para o que o usuário lê como a mesma coisa: overview diz "Conversas Abertas **152**", live diz "Chamados em atendimento **155**". A diferença são as 3 pendentes (confirmado no banco), mas nada na tela explica isso. | Banco conta 3: `open=152, pending=3, resolved=433`. | Uniformizar o rótulo ou acrescentar um tooltip dizendo o que cada número inclui. |

---

## Os 5 primeiros para o dev júnior

Escolhidos por conserto claro, risco baixo e ganho visível.

1. **#4 + #5 + #6 — datas em inglês nos relatórios.** Três arquivos, mesma correção: acrescentar
   `{ locale: ptBR }` às chamadas `format()` do date-fns em `DatePickerButton.vue:43,47`,
   `BaseHeatmap.vue:54` e `ReportContainer.vue:107,109,113,118`. O padrão correto já está no repo
   (`Kanban/ScheduleDateTimePicker.vue:149`). Conserta 12 telas de uma vez.

2. **#15 — chave `REPORT.DOWNLOAD_AGENT_REPORTS` crua na tela.** Adicionar uma linha em
   `i18n/locale/pt_BR/report.json`. As três chaves irmãs já existem — é copiar o padrão. 5 minutos.

3. **#3 — botão "Ativar Tempo Real" ilegível.** Em `CreepyButton.vue:85-88`, mover o `text-white`
   para dentro do `:class` condicional, junto com `bg-n-teal-5`, e usar `text-n-slate-12` no estado
   inativo. Contraste sobe de 1,39:1 para acima de 4,5:1.

4. **#8 — cartões-fantasma em inglês nas Campanhas.** Editar
   `Campaigns/EmptyState/CampaignEmptyStateContent.js`: traduzir os textos e trocar
   "PaperLayer"/`chatwoot.com`/"$25 Amazon coupon" por exemplos da Simplex. Tira a marca do
   concorrente da tela do cliente.

5. **#9 + #10 — chips e telefone invisíveis no cartão do Kanban.** Trocar `min-w-0` por `min-w-fit`
   no wrapper dos chips. Um utilitário de CSS devolve informação que hoje é renderizada com 0px de
   largura. Vale pedir para conferir a 1280px depois.

> Fora da lista mas de dono diferente: **#2 (Baixar PDF)** é o achado de maior impacto de todos
> (14 telas), mas o conserto é definir `CHROMIUM_PATH` no `.env` — tarefa de infra, não de front.

---

## O que NÃO foi testado (e por quê)

- **Envio real de campanha** — NÃO TESTADO. Regra de segurança da auditoria: as inboxes `Channel::Api`
  da conta 3 apontam para a WAHA de produção. Validei que o formulário abre, que os campos existem e
  que o botão "Criar" fica desabilitado sem preenchimento; não cliquei em "Criar".
- **Exclusão de campanha / de funil / de etapa** — NÃO EXECUTADO. Verifiquei no código que a exclusão
  de campanha passa por diálogo de confirmação (`WhatsAppCampaignsPage.vue:41-44` e
  `SMSCampaignsPage.vue:31-34`), então **não é** um caso de exclusão sem confirmação. Não abri o
  diálogo real para não arriscar confirmar por engano.
- **Relatórios com dado denso** — os relatórios de Agentes, Times, Caixas, Rótulos, CSAT, SLA e NPS
  estão majoritariamente com `--`/0 no período padrão de 7 dias nesta base. Testei que carregam, que o
  seletor de período funciona (mudei para "Últimos 30 dias" e os dados recarregaram) e que o
  drill-down por agente funciona (`/reports/agents/6?from=…&to=…&range=last7days`). **Defeitos de
  gráfico que só aparecem com volume alto — legenda cheia, tooltip perto da borda — não puderam ser
  avaliados** nessas telas.
- **Tooltip dos gráficos** — NÃO TESTADO em profundidade. Os gráficos são canvas/SVG que não expõem o
  conteúdo do tooltip no DOM; testar exigiria hover coordenada a coordenada com comparação de imagem.
- **Botão que "some" ao clicar** (relatado pelo Walisson) — **NÃO REPRODUZIDO** nesta área. Testei
  clique em todos os botões visíveis de Relatórios, Campanhas e Kanban: nenhum desapareceu. Os dois
  candidatos ao sintoma são o **#2** (clica em "Baixar PDF", o feedback dura 2s e nada acontece) e o
  **#3** (o botão "Ativar Tempo Real" é tão claro que parece ter sumido).
- **Kanban com muitos itens** — o quadro carrega 85 cartões de uma vez, sem paginação; rolei a coluna
  8 vezes e a contagem não mudou. **Não consegui avaliar o comportamento com scroll infinito** porque
  este funil não tem mais itens do que já vêm na primeira carga.
- **Drag & drop** — TESTADO E FUNCIONA. Movi um cartão de "Abertos" para "Em Andamento" (48→47, 0→1),
  sem erro de JS nem HTTP, e **devolvi o cartão para a coluna original** (47→48, 1→0). Estado
  restaurado. Único ponto: não há confirmação visual (toast) da mudança.
- **Emoji em tofu e `cdn.lordicon.com`** — desconsiderados por serem limitação do servidor de teste.
  Verifiquei que a falta do lordicon **não** deixa nenhum ícone ou botão invisível nas telas desta área.
