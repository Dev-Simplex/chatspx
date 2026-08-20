# TASK 01 — Leadster: produto, negócio e metodologia

> **Estudo puro. Nenhuma linha de código do ChatSPX foi tocada.**
> Documento produzido em 11/08/2026 a partir exclusivamente de fontes públicas
> (site institucional, base de conhecimento oficial, bundles JS públicos servidos
> em CDN aberto, sitemaps, plugin no repositório do WordPress, imprensa e
> plataformas de review). Nenhum login, nenhum scraping autenticado, nenhum
> paywall contornado.

---

## SUMÁRIO

| # | Seção | O que traz |
|---|-------|-----------|
| 0 | [Convenções e método](#0-convenções-e-método) | Como distinguir fato de inferência neste doc |
| 1 | [A empresa](#1-a-empresa-história-fundadores-capital-tração) | História, Neurologic→Leadster, fundadores, sede, aportes, tração |
| 2 | [A tese: Marketing Conversacional](#2-a-tese-marketing-conversacional) | Origem (Drift), adaptação BR, promessas numéricas |
| 3 | [Panorama de Geração de Leads no Brasil](#3-panorama-de-geração-de-leads-no-brasil--o-ativo-de-marketing-mais-forte-da-empresa) | Benchmarks completos: segmento, device, canal, B2B/B2C, WhatsApp |
| 4 | [Linha de produto 2025/2026](#4-linha-de-produto-20252026) | Website Suite, WhatsApp Suite, Shopbot, Live Chat, Agentes de IA |
| 5 | [Anatomia do produto (visão de quem configura)](#5-anatomia-do-produto--a-visão-de-quem-configura) | Editor, blocos, máscaras, condicionais, gatilhos, A/B, design |
| 6 | [Dissecação técnica do widget](#6-dissecação-técnica-do-widget-de-captura) | Snippet, loader, endpoints, telemetria, eventos GA/Meta |
| 7 | [ACHADO CENTRAL: a Suite de atendimento é um Chatwoot](#7-achado-central-a-suite-de-atendimento-da-leadster-é-um-chatwoot-white-label) | Prova documental, versão, implicações |
| 8 | [Integrações](#8-integrações) | Nativas, webhook (payload real), iPaaS, eventos de mídia |
| 9 | [Preços e planos](#9-preços-e-planos) | Tabela de features por plano, valores, add-ons, cancelamento |
| 10 | [Mapa da central de ajuda](#10-mapa-da-central-de-ajuda--a-superfície-real-do-produto) | 202 artigos, 31 categorias, 6 coleções |
| 11 | [Blog e conteúdo](#11-blog-e-conteúdo-a-máquina-de-demanda) | Teses repetidas, funil de conteúdo, GEO/AI-SEO |
| 12 | [Concorrentes](#12-concorrentes-como-a-própria-leadster-se-compara) | Os 12 que eles próprios citam |
| 13 | [Críticas e limitações](#13-críticas-limitações-e-reclamações-públicas) | Reclame Aqui, Capterra, AppSumo, B2B Stack |
| 14 | [Síntese: o que a Leadster realmente vende](#14-síntese-o-que-a-leadster-realmente-vende) | Leitura estratégica |
| 15 | [**IMPLICAÇÕES PARA O CHATSPX**](#15-implicações-para-o-chatspx) | Achados acionáveis |
| A | [Anexos](#anexo-a--índice-completo-dos-202-artigos-da-base-de-conhecimento) | Índice dos 202 artigos, endpoints, fontes |

---

## 0. Convenções e método

Cada afirmação relevante recebe uma marcação:

- **[FATO]** — verificado diretamente na fonte, com URL. Quando é transcrição
  literal, vem entre aspas.
- **[INFERÊNCIA]** — dedução minha a partir dos fatos. Pode estar errada.
- **[NÃO VERIFICADO]** — não consegui confirmar em fonte pública. Nunca inventei
  número, preço, endpoint ou funcionalidade.
- **[DIVERGÊNCIA]** — fontes públicas conflitam entre si; registro as duas.

### 0.1 Fontes primárias usadas

| Fonte | URL | O que rendeu |
|---|---|---|
| Site institucional | `https://leadster.com.br/` | Posicionamento, cases, promessas numéricas |
| Sitemap do site | `https://leadster.com.br/sitemap.xml` | 264 URLs — mapa completo da superfície de marketing |
| Base de conhecimento | `https://help.leadster.com.br` | **202 artigos** — a superfície real do produto |
| Sitemap da KB | `https://help.leadster.com.br/sitemap.xml` | 31 categorias, 6 coleções, 202 artigos |
| CDN pública | `https://cdn.leadster.com.br/` | Bucket GCS listável; bundles do widget |
| Loader do widget | `https://cdn.leadster.com.br/neurolead/neurolead.min.js` | 456.101 bytes — API, endpoints, telemetria |
| App do widget (legado) | `https://cdn.leadster.com.br/app/client/scripts.min.js` | 288.008 bytes |
| Plugin WordPress | `https://wordpress.org/plugins/leadster-marketing-conversacional/` | Snippet oficial de instalação, em código-fonte |
| App de atendimento | `https://atendimento.leadster.com.br/` | `window.globalConfig` exposto — prova do Chatwoot |
| Panorama 2026 | `https://leadster.com.br/blog/panorama-geracao-de-leads-2026/` | Benchmarks 2025 |
| Página de preços | `https://leadster.com.br/preco/` | Planos e valores |

**Nota metodológica sobre bloqueios:** a partir de determinado ponto o site
`leadster.com.br` (hospedado em Vercel) passou a responder *Vercel Security
Checkpoint* para `curl`, e algumas páginas retornaram HTTP 403 ao fetcher. As
páginas afetadas estão marcadas como **[NÃO VERIFICADO]** onde relevante:
`/agencias-parceiras/`, `/como-funciona/`, `/marketing-conversacional/` e
`getleadster.com/pt/pricing/`. **Nenhuma tentativa de contornar esse bloqueio foi
feita.**

---

## 1. A empresa: história, fundadores, capital, tração

### 1.1 Identidade e origem

**[FATO]** A Leadster nasceu com o nome **Neurologic** e fez o rebrand para
Leadster. O próprio blog da empresa mantém o post de anúncio:
`https://leadster.com.br/blog/neurologic-agora-e-leadster/` e o artigo de KB
nº 69, *"Neurologic agora é Leadster"*
(`https://help.leadster.com.br/article/69-neurologic-agora-e-leadster`).

**[FATO]** O rastro da marca antiga permanece vivo dentro do produto até hoje, o
que é uma pista forte de que o núcleo técnico é o mesmo de 2018–2021:

- A API JavaScript pública do widget ainda se chama **`window.neurolead`** — e é
  assim que a própria documentação atual ensina a abrir o chat programaticamente:
  `<button onclick="event.stopPropagation();window.neurolead.open();">`
  (`https://help.leadster.com.br/article/46-como-inserir-o-chat-em-um-botao-popup-no-seu-site`).
- A variável de identificação do site é **`window.neuroleadId`**.
- O arquivo servido pela CDN é **`/neurolead/neurolead.min.js`**.
- Dentro do bundle há URLs residuais para `https://cdn.neurologic.com.br/neurolead/…`.
- Artigos de KB ainda têm slugs com o nome antigo:
  `24-como-integro-minhas-plataformas-com-a-neurologic-utilizando-o-zapier`,
  `57-como-integrar-a-neurologic-ao-crm-piperun`,
  `59-como-integrar-a-neurologic-ao-jivochat`,
  `61-como-integrar-neurologic-a-exact-sales`.
- O payload de webhook documentado ainda exibe `"email_from":"leads@neurologic.com.br"`
  e `"email_subject":"Novo lead gerado [Neurologic]"`
  (`https://help.leadster.com.br/article/58-como-configurar-uma-integracao-via-webhook`).

**[INFERÊNCIA]** O produto de captura (o widget) é um ativo antigo, escrito
originalmente por volta de 2018–2020, que foi sendo incrementado. A empresa
trocou de marca mas não reescreveu o core do widget. Isso importa: significa que
a vantagem competitiva deles **não está na sofisticação técnica do widget**, e
sim no que foi construído em volta (metodologia, conteúdo, benchmarks, distribuição).

### 1.2 Fundadores e liderança

| Nome | Papel | Fonte |
|---|---|---|
| **Fabrício Toledo** | Cofundador e **CEO** | [Exame](https://exame.com/negocios/startup-de-marketing-conversacional-recebe-r-35-milhoes-em-rodada-liderada-por-ex-alunos-da-fgv/); aparece em vídeos da KB (arts. 77, 88, 128) |
| **Gustavo Luby** | Cofundador e **CMO** | [Exame](https://exame.com/negocios/startup-de-marketing-conversacional-recebe-r-35-milhoes-em-rodada-liderada-por-ex-alunos-da-fgv/); citado como CMO na KB art. 75 e 246 |
| **André Silveira** | **CTO** | `https://leadster.com.br/blog/leadster-e-confiavel/` |

**[FATO]** Idades na época do aporte (jan/2023): Gustavo Luby, 25; Fabrício
Toledo, 24 — [Exame](https://exame.com/negocios/startup-de-marketing-conversacional-recebe-r-35-milhoes-em-rodada-liderada-por-ex-alunos-da-fgv/).

**[FATO]** Os fundadores criaram a startup logo após concluírem o ensino médio
técnico em tecnologia, com a tese de que "o futuro da interação entre pessoas,
empresas e computadores seria por conversa"
(`https://leadster.com.br/blog/leadster-e-confiavel/`).

### 1.3 Sede

**[FATO]** **Rua José Loureiro, 464 — Centro — Curitiba/PR — CEP 80010-000**
(`https://leadster.com.br/blog/leadster-e-confiavel/`). Confirmado
indiretamente por todos os telefones comerciais publicados na KB serem DDD **41**
(Curitiba): `+55 41 98794-4624` (comercial, art. 68), `(41) 99524-3564` e
`(41) 99162-5792` (ativação do Live Chat, art. 349), `(41) 99107-4307`
(WhatsApp Suite, art. 330).

### 1.4 Linha do tempo oficial

**[FATO]** Extraída de `https://leadster.com.br/sobre/`:

| Ano | Marco |
|---|---|
| 2018 | Lançamento da plataforma inicial de chatbot para sites |
| 2020 | Integrações nativas com CRM e ferramentas de marketing |
| 2021 | Rebrand Neurologic → Leadster; aporte de **R$ 1 milhão** |
| 2022 | **1.000 clientes pagantes** |
| 2024 | IA integrada em todos os processos; lançamento do **Leadster AI** |
| 2025 | Lançamento do **ShopBot** e do **Leadster WhatsApp** |
| 2026 | Visão declarada: completar o stack de produto, meta de **5.000+ clientes** |

**[DIVERGÊNCIA] Ano de fundação.** O site institucional e o blog dizem **2018**.
Um perfil de terceiros (Tracxn) indica **2015**. Prevalece 2018 por ser fonte
primária. **[DIVERGÊNCIA] Ano do rebrand:** o blog da própria empresa diz
**março de 2021**; a Exame diz **2022**. Prevalece 2021 (fonte primária).

### 1.5 Capital captado

| Rodada | Valor | Data | Investidores | Fonte |
|---|---|---|---|---|
| Anjo / pré-seed | **R$ 1 milhão** | 2021 (pós-rebrand) | **Aimorés Ventures** (Natan Sztamfater), **Prana Capital** (Bruno Peroni) | `leadster.com.br/sobre/`, `leadster.com.br/blog/leadster-e-confiavel/` |
| Seed | **R$ 3,5 milhões** | jan/2023 | **GVAngels** (liderou, R$ 2,2 mi — grupo de anjos ex-alunos da FGV), **Silver Angels** e follow-on | [Exame](https://exame.com/negocios/startup-de-marketing-conversacional-recebe-r-35-milhoes-em-rodada-liderada-por-ex-alunos-da-fgv/), [Startupi](https://startupi.com.br/leadster-marketing-conversacional-aporte/) |

**[FATO]** Total público ≈ **R$ 4,5 milhões**. Um agregador (Crunchbase/Tracxn)
converte para ~US$ 873 mil.

**[INFERÊNCIA]** Isto é *capital muito baixo* para o alcance de mercado que
construíram. Não há rodada Série A pública. **[NÃO VERIFICADO]:** rodadas após
jan/2023, valuation, ARR atual.

### 1.6 Tração declarada

**[FATO]** Números publicados em `https://leadster.com.br/sobre/`:

| Métrica | Valor declarado |
|---|---|
| Clientes ativos | **3.000+** |
| Usuários impactados | **116 milhões** |
| Integrações realizadas | **2.000+** |
| Leads gerados | **5+ milhões** |

**[FATO]** Números de imprensa (jan/2023 — [Exame](https://exame.com/negocios/startup-de-marketing-conversacional-recebe-r-35-milhoes-em-rodada-liderada-por-ex-alunos-da-fgv/)):
~**2.800 clientes** (pagos + gratuitos); receita 2021 de **R$ 1,7 milhão**;
crescimento 2022 **acima de 200%**; duas unidades de negócio (corporativo B2B e
imobiliário/construção) contribuindo **50% cada** para a receita.

**[FATO]** Clientes nominais citados: Neogrid, ENGIE, iFood Benefícios, Totvs
(Exame); iFood, VR Gente, Chaves na Mão, Sankhya, ENGIE, Neil Patel, BG Pactual,
ClickSign, Rockefeller, Mundo do Marketing, Orgânica, Winnin, Swile, Boa Vista,
Esri, DNA de Vendas, Jacuzzi (home do site).

**[FATO]** Tamanho da equipe: **11–50 funcionários** (perfil LinkedIn/Tracxn,
jul/2024). **[NÃO VERIFICADO]:** headcount atual em 2026.

**[FATO]** O plugin oficial no WordPress.org tem **4.000+ instalações ativas**
(versão 1.3.2, última atualização há ~2 anos) —
`https://wordpress.org/plugins/leadster-marketing-conversacional/`.

**[INFERÊNCIA]** Com ~3.000 clientes, ~50 pessoas e ~R$4,5 mi captados, a
Leadster é uma operação **enxuta e eficiente em capital**, não uma startup
inflada. O crescimento veio de conteúdo + metodologia, não de queima de caixa.

---

## 2. A tese: Marketing Conversacional

### 2.1 De onde veio o conceito

**[FATO]** "Conversational Marketing" é uma **categoria criada deliberadamente
pela Drift** (EUA). O livro fundador é *Conversational Marketing: How the
World's Fastest Growing Companies Use Chatbots to Generate Leads 24/7/365*, de
**David Cancel** (CEO da Drift) e **Dave Gerhardt** (funcionário nº 6, VP de
Marketing), publicado pela Wiley (ISBN 9781119541837).

**[FATO]** A origem operacional do conceito: David Cancel ligou para Dave
Gerhardt e disse *"acho que a gente devia se livrar de todos os nossos
formulários"*. Trocaram formulário por conversa iniciada na própria página, a
conversão disparou, e a Drift passou a evangelizar isso em artigos e
conferências. A estratégia declarada de Gerhardt: *"você pode ser o primeiro ou
pode re-segmentar o mercado e criar uma categoria"* — a Drift não inventou o
chatbot, inventou um **novo caso de uso para uma tecnologia existente**.
(Fontes: [Amazon/livro](https://www.amazon.com/Conversational-Marketing-Companies-Chatbots-Generate/dp/1119541832),
[Concurate](https://concurate.com/drift-marketing-strategy-coin-a-new-term/),
[Lochhead](https://lochhead.com/029-dave-gerhardt/)).

### 2.2 A adaptação brasileira da Leadster

**[INFERÊNCIA — com base forte]** A Leadster executou no Brasil exatamente a
mesma jogada da Drift, com quatro adaptações que a tornam mais forte aqui do que
a matriz americana seria:

1. **Trocaram "agendar reunião com SDR" por "capturar lead + jogar no WhatsApp".**
   A Drift é B2B-enterprise, focada em book-a-meeting. A Leadster é
   pequena-e-média-empresa brasileira, e o destino final do lead no Brasil é
   quase sempre o WhatsApp. **[FATO]** o Panorama 2026 mostra que **75,96% das
   empresas analisadas usam WhatsApp**.
2. **Produziram o dado próprio do mercado brasileiro** (o Panorama — seção 3).
   A Drift vendia opinião; a Leadster vende **benchmark**. Um cliente que
   descobre que converte 1,8% num setor cuja mediana é 3,07% já está pré-vendido.
3. **Precificaram em real e por faixa de tráfego**, não por assento — coerente
   com o bolso do mercado SMB brasileiro.
4. **Empacotaram a metodologia como conteúdo de topo de funil** e viraram
   referência de SEO em "geração de leads" no Brasil.

**[FATO]** A própria empresa se descreve como tendo *"Metodologia Própria de
Marketing Conversacional unindo 5 anos de aprendizado na construção de chatbots
com as melhores práticas de otimização de conversão online"*
(readme do plugin WordPress oficial).

### 2.3 As promessas numéricas que eles repetem

**[FATO]** Da home `https://leadster.com.br/`:

| Promessa | Origem declarada |
|---|---|
| **+201%** de geração de leads | case iFood |
| **+295%** | case Tozi |
| **+310%** | case Revenda Mais |
| **+316%** | case Ashcroft |
| **+48%** de leads vs. o formulário principal | case Sankhya |
| **+113%** em conversão | case Rafael Cássio (`/agentes-de-ai/`) |
| **49 reuniões qualificadas em 3 meses** | case Contraktor (`/agentes-de-ai/`) |

**[FATO]** Números "de dor de mercado" que usam para criar urgência (home):

- **97%** dos visitantes abandonam o site sem converter.
- **63%** dos leads não são atendidos a tempo.
- Tempo médio de resposta: **1 dia, 5 horas e 17 minutos**.
- **58%** dos leads convertem fora do horário comercial.

**[FATO]** Números da metodologia repetidos na KB:

- *"Empresas que qualificam seus leads aumentam em 50% as suas vendas, com um
  custo 33% menor de time"* (arts. 105 e 88).
- Personalização de fluxo por página *"tende a aumentar suas taxas de conversão
  em até 40%"* (art. 33).
- Chamadas inteligentes: *"aumento de até 20% nas conversões"* — "levantamento
  interno" (art. 47).
- Teste A/B: *"Conseguimos dobrar a Conversão em leads apenas adicionando a
  frase 'em 5 min' na chamada do chat"* (art. 28).
- Chatbot captura *"3x mais informações comparado com formulário"*
  (`/formularios-vs-leadster/`).
- Citação da Twilio: *"90% dos consumidores querem falar com as empresas através
  de mensagens"* (`/formularios-vs-leadster/`).
- Comparativo visual: Formulários **150 leads** | WhatsApp **230 leads** |
  Leadster **450 leads** (`/formularios-vs-leadster/`).
- Leadster AI resolve **78% dos atendimentos** automaticamente; ativação em
  **12 minutos**; aumento de conversão **até 50%** (`/leadster-ai/`).
- Ativação do produto: *"aproximadamente 4 minutos sem conhecimento de
  programação"* (`/preco/`).

**[INFERÊNCIA — importante]** Nenhuma dessas promessas percentuais tem
metodologia publicada. São *cases*, não experimentos controlados. O número
honesto e auditável da empresa é o do Panorama (seção 3), que é agregado e vem
com metodologia explícita. **Ao mirar a Leadster, o ChatSPX deve copiar o
Panorama (defensável) e não a retórica de "+316%" (indefensável).**

---

## 3. Panorama de Geração de Leads no Brasil — o ativo de marketing mais forte da empresa

**[FATO]** Relatório anual, gratuito, baseado na própria base de clientes.
Está na **5ª edição** (Panorama 2026, com dados coletados ao longo de 2025).
Fontes: `https://leadster.com.br/blog/panorama-geracao-de-leads-2026/` e
`https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil-2026/`.

### 3.1 Metodologia (declarada)

| Edição | Sites analisados | Leads | Acessos | Período dos dados |
|---|---|---|---|---|
| **Panorama 2026** (5ª ed.) | **2.425** | **3,4 milhões** | **173 milhões** | 2025 |
| **Panorama 2025** | **2.861** | **3,7 milhões** | **167 milhões** | 2024 |

**[FATO]** 17 segmentos de mercado analisados no Panorama 2026.

**[INFERÊNCIA]** Curioso: o Panorama 2026 tem **menos sites** (2.425 vs 2.861) e
**menos leads** (3,4 vs 3,7 mi) que o anterior, mas **mais acessos** (173 vs
167 mi). Ou a base de clientes encolheu em número e cresceu em porte, ou mudaram
o critério de corte amostral. Não há explicação pública. **[NÃO VERIFICADO].**

### 3.2 Série histórica da conversão mediana do mercado brasileiro

**[FATO]**

| Edição (dados de) | Conversão mediana | Variação |
|---|---|---|
| Panorama 2024 (dados 2023) | **3,15%** | — |
| Panorama 2025 (dados 2024) | **2,98%** | −0,17 p.p. |
| Panorama 2026 (dados 2025) | **3,07%** | **+0,09 p.p.** |

**[FATO]** *"pela 1ª vez em 5 anos, a conversão voltou a subir"* — narrativa
central do Panorama 2026. Antes disso, houve **três anos consecutivos de queda**
(coberto pela imprensa: [E-Commerce Brasil](https://www.ecommercebrasil.com.br/noticias/conversao-de-leads-digitais-cai-pelo-terceiro-ano-consecutivo-no-brasil-aponta-pesquisa),
[Mundo do Marketing](https://mundodomarketing.com.br/conversao-de-leads-volta-a-crescer-no-brasil-apos-tres-anos-de-queda)).

### 3.3 Faixas de performance

**[FATO]**

| Faixa | Panorama 2025 | Panorama 2026 |
|---|---|---|
| Baixa performance | 1,07% | **1,02%** |
| Mediana (mercado) | 2,98% | **3,07%** |
| Alta performance | 7,27% | **7,90%** |

**[INFERÊNCIA]** O intervalo entre baixa e alta performance **abriu**
(de 6,20 p.p. para 6,88 p.p.). Quem sabe operar conversão está se distanciando de
quem não sabe — exatamente o argumento comercial que sustenta a venda de
metodologia junto com o software.

### 3.4 Conversão por segmento — Panorama 2026 (dados 2025)

**[FATO]** Segmentos capturados na extração (dos 17 analisados):

| # | Segmento | Conversão mediana |
|---|---|---|
| 1 | **Jurídico** | **5,42%** |
| 2 | Energia | 5,33% |
| 3 | Seguros | 5,10% |
| 4 | Financeiro | 5,04% |
| 5 | Telefonia | 3,89% |
| 6 | Tecnologia | 2,07% |
| 7 | Software | 1,83% |
| 8 | Consultoria | 1,71% |
| 9 | **Imóveis** | **1,32%** (lanterna) |

**[NÃO VERIFICADO]:** os demais segmentos dos 17 (Saúde, Indústria, Educacional,
Logística, Marketing e Publicidade, Venda de Produtos etc.) não apareceram com
valor numérico de 2026 nas páginas públicas acessadas — só no PDF, que exige
cadastro (não baixei, por ser conteúdo com formulário).

### 3.5 Conversão por segmento — Panorama 2025 (dados 2024)

**[FATO]** Reproduzido por veículo terceiro que teve acesso ao estudo
([Agendor](https://www.agendor.com.br/blog/panorama-de-geracao-de-leads-no-brasil/)):

| Segmento | Taxa mediana 2024 | Variação |
|---|---|---|
| Telefonia e Internet | **5,40%** | +16,4% |
| Marketing e Publicidade | 4,80% | +33% |
| Jurídico | 4,45% | −0,36 p.p. |
| Seguros | 4,18% | — |
| Saúde | 4,07% | — |
| Indústria | 3,81% | +0,09 p.p. |
| Financeiro | 3,23% | −0,73 p.p. |
| Logística e Transporte | 2,64% | +10,9% |
| Consultoria | 1,55% | queda |
| Imóveis | 1,52% | queda |

**[FATO]** Setores em queda forte em 2024: Energia −23,1%; Educacional −21,5%;
Venda de Produtos −16,9%; Tecnologia e TI −14,5%; Software −7,1%.

**[INFERÊNCIA]** Comparando as duas tabelas, **Energia saltou de queda de 23%
para 5,33% (2º lugar) e Financeiro de 3,23% para 5,04%**. É uma virada grande
demais em um ano para ser puramente orgânica. Provável mudança de composição da
amostra. Tratar as séries entre edições com cautela.

### 3.6 Conversão por dispositivo

**[FATO]** Panorama 2026:

| Dispositivo | Conversão | Fatia do tráfego |
|---|---|---|
| **Desktop** | **3,50%** | 25,6% |
| **Mobile** | 3,37% | **74,4%** |

**[FATO]** Panorama 2025: variação desktop −0,01 p.p.; mobile **+0,23 p.p.**

**[INFERÊNCIA — muito relevante para o ChatSPX]** Três em cada quatro acessos são
mobile, mas o desktop ainda converte melhor. O gap está fechando (mobile subiu
0,23 p.p. enquanto desktop ficou estável). **Isso justifica tecnicamente o
recurso de "fluxo e design separados para mobile e desktop" que a Leadster
vende** (arts. 84 e 95) — e é o argumento mais forte para qualquer produto de
chat web em 2026: **o mobile é onde está o volume e onde a experiência ainda é
pior.**

### 3.7 Conversão por canal de aquisição

**[FATO]** Panorama 2026 — a manchete do estudo:

| Canal | Conversão | % dos leads gerados | % do tráfego |
|---|---|---|---|
| **IA Generativa** | **7,80%** | — | — |
| Meta Ads | 3,91% | 15,83% | 9,48% |
| Google Ads | 3,41% | 26,85% | 23,40% |
| Busca Orgânica | 2,39% | 16,11% | 27,91% |
| Acesso Direto | 1,74% | — | 15,72% |

**[FATO]** Comparativo entre edições:

| Canal | 2025 | 2026 | Δ |
|---|---|---|---|
| Meta Ads | 3,40% | 3,91% | +0,51 |
| Google Ads | 3,28% | 3,41% | +0,13 |
| **LinkedIn Ads** | 1,88% | **2,97%** | **+1,09** |
| Busca Orgânica | 2,32% | 2,39% | +0,07 |
| Acesso Direto | 2,08% | **1,74%** | **−0,34** |

**[FATO]** *"a inteligência artificial estreou como o canal de maior conversão,
com 7,80%, contra 3,4% do Google, gerando 2,5x mais leads em relação à sua
fatia de tráfego."*

**[INFERÊNCIA — o achado mais importante do Panorama]** Tráfego vindo de
ChatGPT/Perplexity/Gemini converte **mais que o dobro** de qualquer mídia paga.
Faz sentido: quem chega por uma resposta de LLM já passou por uma triagem de
intenção — chega com a dúvida resolvida e a decisão quase tomada. **Isso muda a
prioridade de qualquer roadmap de chat web: rastrear e atribuir tráfego de IA
generativa vira feature, não curiosidade.**

**[FATO — corroborando]** A Leadster já otimiza explicitamente para isso. O
`robots.txt` deles (`https://leadster.com.br/robots.txt`) faz **allow explícito**
para: `GPTBot`, `ChatGPT-User`, `OAI-SearchBot`, `OAI-AdsBot`, `Google-Extended`,
`anthropic-ai`, `Claude-Web`, `PerplexityBot`, `Applebot-Extended`. E a home tem
CTAs que abrem **ChatGPT, Claude, Perplexity, Grok e Google AI Mode** já com um
prompt pré-preenchido vendendo a Leadster. Existe até artigo de KB
**nº 409 — "Como enviar conversões da Leadster ao ChatGPT Ads"**.

### 3.8 Qualidade do lead por canal (leadscore 4–5)

**[FATO]** Panorama 2026:

| Canal | % de leads qualificados |
|---|---|
| **Busca Orgânica** | **44,5%** |
| Mercado geral | 42,9% |
| IA Generativa | 40,2% |
| Google Ads | 40,1% |
| Meta Ads | 39,7% |
| LinkedIn Ads | 35,1% |

**[INFERÊNCIA]** IA generativa converte mais (7,80%) mas qualifica *ligeiramente
pior* que orgânico (40,2% vs 44,5%). Ou seja: **volume alto, qualidade média**.
Orgânico continua sendo o canal de melhor lead.

### 3.9 B2B vs B2C

**[FATO]**

| Métrica | B2B | B2C |
|---|---|---|
| Conversão mediana (2026) | **2,53%** | **3,39%** |
| % de leads qualificados | 36,7% | 48% |
| Conversão mediana (2025) | 2,50% | 3,28% |

### 3.10 WhatsApp — o dado que define o mercado brasileiro

**[FATO]** Panorama 2026:

| Recorte | Valor |
|---|---|
| Empresas que usam WhatsApp | **75,96%** |
| Conversão **com** WhatsApp | **3,20%** |
| Conversão **sem** WhatsApp | **2,66%** |
| **Delta** | **+0,54 p.p. (+20,3% relativo)** |

**[FATO]** Panorama 2025, recorte B2B: adoção de redirecionamento para WhatsApp
**78,78%**; conversão com WhatsApp **3,12%**; sem WhatsApp **2,52%**
(delta +0,60 p.p.).

**[INFERÊNCIA]** Este é *o* número que justifica a existência comercial da
Leadster no Brasil e que a Drift jamais teria. Colocar um botão de WhatsApp no
fim do fluxo vale ~20% de conversão relativa. Qualquer chat web brasileiro que
não tenha handoff nativo para WhatsApp está deixando ~20% na mesa.

### 3.11 Fora do horário comercial

**[FATO]** Panorama 2026: **43,8%** dos leads chegam fora do horário comercial.
Por canal: IA Generativa **47,98%**; Busca Orgânica **47,76%**.
A home reforça com o número de **58%** convertendo fora do horário comercial.

**[INFERÊNCIA]** Quase metade da demanda chega quando não há ninguém para
atender. É o argumento de venda do agente de IA — e é um argumento verdadeiro,
não retórico.

### 3.12 Maturidade digital (índice próprio, Panorama 2025)

**[FATO]** A Leadster criou um "Índice de Maturidade Digital" por segmento
(escala 0–10), com três eixos: mídia paga, orgânico e vendas.

| Segmento | Índice geral | Mídia paga | Orgânico | Vendas | Detalhe |
|---|---|---|---|---|---|
| Indústria | 6,07 | 6,0 | 6,6 | 5,6 | 38,44% com links parametrizados; 46,43% integram CRM |
| Logística | — | **9,8** (maior de todos) | 4,3 | 5,7 | — |
| Jurídico | **5,03** (menor) | — | — | — | 19,24% com links parametrizados; 31,43% integram CRM |

**[FATO]** Uso de CRM em B2B: **54,13%** integram CRM (Financeiro 61,11%;
Indústria 46,43%).

**[INFERÊNCIA]** Metade do mercado B2B brasileiro **não integra o lead ao CRM**.
Isso é um espaço enorme e é exatamente onde a Leadster ancora a venda de
"integrações nativas".

---

## 4. Linha de produto 2025/2026

**[FATO]** A Leadster hoje é composta por **quatro produtos** e um conjunto de
add-ons. Fontes: `https://leadster.com.br/sobre/`, `/agentes-de-ai/`,
`/leadster-ai/`, KB arts. 330, 349, 285.

### 4.1 Mapa de produtos

| Produto | O que é | Canal | Status |
|---|---|---|---|
| **Leadster (Website Suite)** | Chatbot de fluxo para captura e qualificação no site | Site | Core, maduro |
| **Leadster AI / Assistente AI** | Agente de IA generativa (RAG sobre base própria) plugável dentro do fluxo | Site (e WhatsApp) | Lançado 2024 |
| **Leadster WhatsApp Suite** | Plataforma de atendimento + chatbot + SDR de IA no WhatsApp | WhatsApp, Messenger, E-mail | Lançado 2025, *"fase inicial de lançamento"* (art. 330) |
| **ShopBot** | Agente de IA para e-commerce (recomendação de produtos) | Site de e-commerce | Lançado 2025 |
| **Leadster Live Chat** | Atendimento humano em tempo real no site | Site | *"(novo)"* na tabela de preços; exclusivo do plano Pro/Full |

### 4.2 Website Suite (o produto core)

**[FATO]** É o chatbot de fluxo. Substitui o formulário por uma conversa
sequencial que capta dados, qualifica e distribui. Detalhado na seção 5.

### 4.3 Leadster AI / Assistente AI

**[FATO]** Configuração em 3 passos (art. 221):
1. **Identificador** para o assistente.
2. **Comportamento** — escolha entre 3 modelos pré-definidos:
   - *Qualificar leads* — gerar leads qualificados para o comercial;
   - *Atendimento ao visitante* — tirar dúvidas em tempo real;
   - *Para e-commerce* — recomendação de produtos (ShopBot).
3. **Mensagem de fallback** para quando não souber responder.

**[FATO]** Base de conhecimento (RAG) aceita (arts. 220, 285, 286):
- **URLs** — uma a uma, ou *"Adicionar múltiplas páginas"* (informa a URL base e
  seleciona páginas), ou **Sitemap XML** (importa tudo), ou **Google Shopping**
  (produtos, com recomendação).
- **Documentos**: `.pdf`, `.doc`, `.docx`, `.odt`, `.txt` — **máximo 10 MB por
  arquivo**.

**[FATO]** Boas práticas recomendadas pela própria empresa (art. 220): estruturar
em **formato FAQ**, usar **markdown**, usar **hashtags (#) para categorizar cada
pergunta**, textos curtos, e **agrupar perguntas diferentes que levam à mesma
resposta**.

**[FATO]** Modelo usado: *"Inteligência Artificial do ChatGPT"* — declarado em
`https://leadster.com.br/blog/leadster-ai/`. **[NÃO VERIFICADO]:** qual modelo
específico (GPT-4o, GPT-5 etc.).

**[FATO]** Funcionalidades do bloco de IA dentro do fluxo:
- **Análise de intenção** (art. 251): a IA detecta intenções **pré-definidas pela
  Leadster** e desvia automaticamente para uma condicional. *"Ainda não existe a
  possibilidade de criar intenções, mas nosso time de produto já está trabalhando
  nisso"* — **limitação declarada**.
- **Conversa proativa** (art. 257): a IA inicia o contato. Aceita comando em
  linguagem natural com variável, ex.: `"Dê um bom dia bem animado para o {{@name}}"`.
- **Botão de encerramento** (art. 284): aparece em cada resposta da IA **apenas
  se o bloco de IA não for o último do fluxo**. Texto customizável
  (ex.: *"Quero falar com um atendente"*).
- **Analytics do assistente** (art. 245): visitantes atendidos, duração média,
  perguntas por visitante, total de perguntas, **respondidas vs não respondidas**,
  avaliações satisfatórias/insatisfatórias.
- **Histórico de mensagens** (art. 283): todas as conversas, com filtro por fluxo,
  conversa e avaliação.

**[FATO]** Preço: **a partir de R$ 220/mês**, cobrado por **volume mensal de
interações**; 14 dias grátis; clientes existentes têm "condições especiais"
(`https://leadster.com.br/blog/leadster-ai/`). No plano Full vem incluso
*"a partir de 100 respostas"* (art. 244).

### 4.4 Leadster WhatsApp Suite

**[FATO]** Três modelos de uso, ativáveis de forma independente ou combinada
(art. 330):
1. **Plataforma de Atendimento** — inbox multi-atendente com histórico centralizado.
2. **Chatbot com Fluxo no WhatsApp** — replica a lógica de fluxo da Leadster.
3. **Agente de IA para WhatsApp (SDR IA)** — atende, responde, agenda reuniões.

**[FATO]** Usa o **número de WhatsApp Business já existente**, via
**WhatsApp Business API (Cloud API)** e também no modo **Coexistence**.

**[FATO]** Regras de **FUP (follow-up) do SDR IA** — art. 370, muito específico:
- Lead que **finaliza** o fluxo → integração dispara **imediatamente**.
- Lead **incompleto** → integração só dispara **após o ciclo de FUPs**.
- FUPs ocorrem em: **5 minutos**, **1 hora**, **até 4 horas**.
- Último FUP até **21h**, de segunda a sábado.
- Lead que entra em delay após 21h → enviado às **9h do próximo dia útil**.
- **Domingo**: FUPs e disparos automáticos **desabilitados**.
- Se um **operador assume** a conversa → lead é removido da IA e a integração
  dispara na hora, como **lead incompleto**. Vale inclusive no domingo.

**[FATO]** Limitações documentadas do modo **Coexistence** (art. 376) — lista
honesta e útil:
- Throughput: **20 msg/s** em Coexistence vs **80 msg/s** em API dedicada.
- App não aberto por **14 dias** no telefone principal → desconecta.
- Mensagens de dispositivos companheiros (WhatsApp Windows, WearOS) **não
  disparam webhooks**.
- **Chamadas de voz não suportadas** pela API nesse modo.
- **Broadcast lists** do app ficam desativadas.
- Não sincronizam: **grupos**, mensagens que desaparecem, *view once*.
- **Echo messages** (enviadas pelo app) **não abrem a janela de 24h**, não
  disparam automações, não iniciam conversas.
- **Sem selo azul (OBA)** diretamente; requer Meta Verified for Business.
- Número em Coexistence **não migra entre WABAs** sem desconectar antes.

**[FATO]** Erros da Meta com artigo dedicado (mostra maturidade operacional):
`63016` (fora da janela 24h), `63024` (destinatário inválido), `63032`
(restrição/experimento Meta), `63049` (mensagem de marketing bloqueada),
`131042` (business eligibility / payment issue), `131049`.

**[FATO]** Configuração de **"Conversa única"** (art. 393) — decisão de arquitetura
exposta ao usuário:
- **Bloqueio ativado** → contato mantém **uma única conversa contínua**; não
  passa de novo pela IA; cai direto no atendente.
- **Bloqueio desativado** → **múltiplas conversas**; passa pela IA sempre.

### 4.5 ShopBot

**[FATO]** Agente de IA para e-commerce, com domínio próprio
(`https://shopbot.leadster.com.br`). Configuração em 5 etapas (art. 285):
criar agente → integrar e-commerce (opcional) → adicionar conteúdo → testar →
adicionar ao fluxo.

**[FATO]** Integrações de e-commerce nativas (10 opções declaradas), com artigo
por plataforma: **Shopify** (280), **Nuvemshop** (273), **Tray** (272),
**WooCommerce** (271), **VTEX** (274), **Loja Integrada** (275), **Megazord**
(276), **WBuy** (277), **Bagy** (278).

**[FATO]** Ingestão de catálogo via **XML do Google Shopping** (art. 287).

### 4.6 Live Chat

**[FATO]** Art. 349. Atendimento humano em tempo real no site. Configurações:
- Exibir **nome do atendente** nas mensagens.
- **Horário e dias** específicos de disponibilidade.
- Exibir **apenas quando houver atendente online**.

**[FATO]** Disponível apenas no **plano Full/Pro** — e a ativação é **manual, por
contato com pessoa nominal** (a KB publica e-mail e WhatsApp de duas
funcionárias). **[INFERÊNCIA]** Isso indica produto **recém-lançado e ainda não
self-service** — provavelmente em rollout controlado.

---

## 5. Anatomia do produto — a visão de quem configura

Esta seção é a mais importante para efeito de benchmark. Foi montada lendo os
202 artigos da base de conhecimento.

### 5.1 O editor de fluxo: 3 etapas, não canvas

**[FATO]** O editor **não é um canvas de nós arrastáveis**. É um **wizard linear
de 3 passos** (arts. 29, 75):

| Etapa | Nome | O que contém |
|---|---|---|
| **1** | **Personalize para seu público** | Regras de página e campanha; design do chat; acionadores; personalização por device |
| **2** | **Qualifique seus leads** | Chamada de conversão; chamadas inteligentes; fluxo de perguntas e respostas; blocos |
| **3** | **Integre com seus sistemas** | E-mails de recebimento; integrações; variáveis personalizadas; política de privacidade (LGPD) |

**[FATO]** Dentro da etapa 2, o fluxo é uma **lista vertical de blocos** com
código de cor:
- **Azul** = mensagem/pergunta do assistente.
- **Verde** = resposta do visitante.
Adiciona-se com um botão **"Adicionar bloco"**.

**[FATO]** O redesign do editor foi feito *"após um período de pesquisas com
nossos clientes"* e o objetivo declarado foi tornar a edição *"mais intuitiva e
auto explicativa"* em **três passos** (art. 75).

**[INFERÊNCIA — decisão de produto deliberada e inteligente]** Eles
**rejeitaram o canvas visual** (que é o padrão de Landbot, Typebot, ManyChat) em
favor de um wizard linear. O trade-off: perde-se expressividade em fluxos
complexos, mas ganha-se **tempo até o primeiro valor** — coerente com a promessa
de "ativação em 4 minutos" e com o público SMB, que não tem analista de
automação. Como não há canvas, a ramificação é feita por **blocos condicionais
aninhados**, não por arestas.

### 5.2 Catálogo de blocos

**[FATO]** Consolidado dos arts. 29, 50, 112, 119, 129, 223, 250, 306, 384 e
confirmado no bundle JS (seção 6):

| Categoria | Bloco | Observações |
|---|---|---|
| Conteúdo | **Mensagem do bot** | Aceita link inline (art. 40): URL, texto âncora, título interno, modo de abertura (mesma janela / nova aba) |
| Coleta | **Resposta do Usuário** | Com máscara (ver 5.3) |
| Coleta | **Lista de opções** | Permite colar várias opções de uma vez separadas por `;` (art. 231). Recomendação: **não passar de 10 opções** (art. 13) |
| Lógica | **Condicional** | Campo + operador + itens. Operadores: *igual a, diferente de, contém, maior que, menor que* |
| Lógica | **Múltiplas condicionais** | Botão "Nova condicional" — combina critérios (E lógico) |
| Ação | **Redirecionar para WhatsApp** | Com horário, roleta, mensagem pré-preenchida |
| Ação | **Redirecionar para link** | Só disponível em blocos de mensagem do bot (art. 129) |
| Ação | **Agendamento de Reunião** | Google Calendar (ver 5.7) |
| Ação | **Direcionamento para JivoChat** | Legado (art. 29) |
| IA | **Assistente IA** | Um assistente por bloco |
| Tracking | **Enviar eventos GA/Meta Ads** | Client-side (art. 250) |
| Tracking | **Enviar eventos GA/Meta Ads via API** | Server-side/CAPI (art. 384) |

**[FATO]** Ações terminais dentro de uma condicional (art. 50, 117, 252):
- **Descartar lead desqualificado** — o contato é removido e **não é enviado nem
  por e-mail nem por integrações**.
- **Encerrar conversa/fluxo** — finaliza a jornada naquele ponto.

### 5.3 Máscaras e validações — o catálogo completo

**[FATO]** Arts. 306 e 124. Este é um dos pontos mais fortes do produto e o mais
"brasileiro" dele:

| Grupo | Máscara | Comportamento documentado |
|---|---|---|
| **Datas** | Aniversário | dia/mês/ano (ex.: 27/11/1993) |
| | Data | Abre **calendário**; seleciona dias a partir da data de abertura do chat |
| | Hora | Abre **relógio**; período (AM/PM), horas e minutos |
| **Documentos** | **CPF** | **Valida o formato** — não aceita CPF aleatório |
| | **CNPJ** | **Valida o formato** — não aceita CNPJ aleatório |
| | CPF ou CNPJ | Aceita ambos |
| **Endereços** | **CEP** | 8 dígitos |
| | Cidade | Texto aberto |
| | **Estado** | Abre **menu lateral** (no desktop) com a lista de UFs |
| | **Estado + Cidade** | Menu de UF e, na sequência, a cidade |
| **Moedas** | Real | Campo pré-preenchido com `R$` |
| | Dólar | Pré-preenchido com `US$` |
| | Euro | — |
| **Outros** | E-mail | Aceita qualquer domínio |
| | **E-mail corporativo** | **Rejeita** `@gmail.com`, `@hotmail.com` etc. |
| | Nome | Texto aberto |
| | Número | Numérico puro |
| | **Telefone** | DDD + número (11 dígitos) |
| | **Telefone Internacional** | Identifica DDI; **pré-seleção de país** (novidade) |
| | Texto livre | — |

**[FATO]** **Validação restrita** (novidade, art. 124): bloqueia números
inválidos — sequências com todos os dígitos iguais (`111111111`) e blocos de
números repetidos.

**[FATO]** Há um JSON público de cidades por estado usado pelo widget:
`https://cdn.leadster.com.br/leadster/state_cities.json`.

**[INFERÊNCIA]** CPF/CNPJ/CEP com validação real, UF+cidade em cascata e
validação anti-lixo em telefone são **exatamente o que um produto americano não
tem**. É um fosso pequeno mas verdadeiro contra Drift/Intercom/Tidio no Brasil.

### 5.4 Campos obrigatórios e leads completos vs incompletos

**[FATO]** Conceito central do modelo de dados (arts. 42, 77, 78):
- **Lead completo** = respondeu **todas** as perguntas do fluxo.
- **Lead incompleto** = abandonou no meio.
- Toda integração permite escolher **qual tipo** receber: *Novo lead completo*,
  *Novo lead incompleto*, ou *Novo lead* (todos — **recomendado** pela própria
  Leadster, art. 57).
- **Campos obrigatórios** funcionam como **filtro**: se o lead não responder um
  campo obrigatório, **você não recebe o lead** em lugar nenhum.

**[FATO — armadilha documentada]** *"Você **não pode utilizar campos obrigatórios
dentro de condicionais**, pois nem todos os seus leads passarão por aquela
pergunta"* (art. 42). É a causa nº 1 de "não estou recebendo leads".

**[INFERÊNCIA]** Esse é um **bug de design exposto como documentação**. A
plataforma deveria detectar campo obrigatório dentro de ramo condicional e
avisar no editor. Ponto fraco copiável ao contrário: quem faz melhor, valida no
editor.

### 5.5 Segmentação: regras de página e campanha

**[FATO]** Art. 33. Modo de combinação: *"Páginas que obedecem **todas** as
regras"* (AND) ou *"**qualquer** regra"* (OR). **8 tipos de regra**:

| # | Regra | Uso |
|---|---|---|
| 1 | **Contém a URL ou palavra** | Segmenta por path dentro do mesmo domínio |
| 2 | **Não contém a URL ou palavra** | Exclusão |
| 3 | **O domínio contém** | Multi-domínio |
| 4 | **O domínio não contém** | Exclusão por domínio |
| 5 | **É página inicial** | Só a home |
| 6 | **Origem é Google Ads** | Só tráfego do Google Ads |
| 7 | **Origem é Facebook Ads** | Só tráfego do Meta |
| 8 | **Parâmetro de URL** | Regras por UTM (art. 60) |

**[FATO]** O mesmo script serve **quantos sites/domínios quiser** — o limite do
plano é a **soma de acessos ou leads de todos os sites** (art. 17).

**[FATO]** Personalização por device (art. 84): pode-se ativar
**"Design personalizado para Mobile e Desktop"** e
**"Fluxo personalizado para Mobile e Desktop"** — este último cria **dois fluxos
totalmente distintos**, com perguntas diferentes, número de etapas diferente e
chamadas diferentes. Recomendação da empresa: mobile = fluxo rápido e direto;
desktop = abordagem consultiva e detalhada.

### 5.6 Acionadores (gatilhos) — 7 tipos, até 3 simultâneos

**[FATO]** Art. 263. *"Você pode ativar **até 3 acionadores ao mesmo tempo**"* e
tudo é configurável **independentemente para desktop e mobile**:

| # | Acionador | Detalhe documentado |
|---|---|---|
| 1 | **Tempo na Tela** | Ativo por padrão. Ex.: 60s desktop, 10s mobile |
| 2 | **Tempo de Inatividade** | Reengaja quem parou de interagir |
| 3 | **Scroll na Página** | Percentual. Ex.: 60% da página |
| 4 | **Número de Cliques na Página** | Ex.: 10 cliques desktop, 20 mobile |
| 5 | **Clique em Elemento da Página** *(novo)* | Por **seletor CSS** — classe ou ID |
| 6 | **Número de Páginas Acessadas** | Ex.: após 4 páginas |
| 7 | **Cursor Fora da Tela** | **Exit intent** |

**[FATO]** Há a opção *"Abrir o chat somente se **um dos** acionadores for
verdadeiro"* (OR entre gatilhos).

**[FATO]** **Controle de frequência**: *"Mostrar uma vez a cada 30 dias"* para
quem já acessou.

**[FATO]** Acionador por CSS (art. 312) — limitações declaradas com honestidade:
- *"O campo de classe CSS aceita **apenas uma classe por vez**. Cada espaço
  inserido é interpretado como uma nova classe."*
- Há **limite de caracteres** no campo.
- *"Se outro elemento do seu site usar essa mesma classe, ele também abrirá a
  Leadster."*
- Pode disparar **ao clicar** ou **ao visualizar o elemento na tela**.

**[FATO]** **4 formatos de exibição** (art. 263):
1. **Chat Padrão** — canto da tela.
2. **Chat Padrão Focalizado** — igual, mas **escurece o fundo do site**.
3. **Pop-up** — janela cobrindo parcialmente a tela.
4. **Tela Cheia** — 100% da tela.

**[FATO]** Confirmado no bundle JS: `"default"`, `"popUp"`, `"fullscreen"`.

### 5.7 Agendamento de reunião

**[FATO]** Art. 112. Integração com **Google Calendar**. Configuração:
- Título do evento (nome no Google Agenda).
- Conexão OAuth por vendedor; link para a equipe se cadastrar.
- Duas listas: **"Contas sincronizadas disponíveis"** e **"Contas ativas"**.
- **Obrigatório** haver um campo de **e-mail** no fluxo (o lead vira convidado).
- Grade de horários, com padrão baseado em horário comercial.

**[FATO]** Configurações avançadas:
- **Frequência de horários**: de **15 em 15 minutos até 1 em 1 hora**.
- **Período máximo de agendamento**: **30 dias**.
- **Tolerância**: tempo mínimo entre a conversão e o horário agendável.
- **Buffer** antes/depois de eventos: **15 minutos a 1 hora**.

**[FATO]** **Preço do add-on: R$ 49,00 por vendedor/mês** (art. 112) — um dos
poucos preços de add-on publicados.

**[FATO]** Tratamento de falha de OAuth: se o token expira ou é revogado, a
plataforma exibe aviso em vermelho no fluxo e na área de Agendamentos, **e envia
e-mail automático** ao usuário afetado. Art. 377 ensina a marcar o app como
**Trusted** no Google Admin Console, e publica o **Client ID** real:
`506299201262-pimm7jb954hf6c251g2f1vf307tctbak.apps.googleusercontent.com`.

**[INFERÊNCIA]** Esse tratamento de token revogado (banner + e-mail + tutorial de
Workspace) é maturidade operacional real. É o tipo de detalhe que só existe
depois de muito chamado de suporte.

### 5.8 Handoff para WhatsApp

**[FATO]** Arts. 19, 62, 83, 383:
- Bloco **"Redirecionar para WhatsApp"** com: mensagem de introdução acima do
  botão, número, **horário e dias de atendimento**, e **mensagem pré-preenchida**
  que o lead envia ao clicar.
- Opção **"Abrir WhatsApp automaticamente"**.
- A mensagem pré-preenchida aceita **variáveis de resposta do usuário** — pode
  levar **todos** os dados coletados (art. 62).
- **Horário de atendimento**: o botão só aparece nos horários configurados.
- **Roleta de WhatsApp**: até **12 números** no mesmo botão, distribuição
  **aleatória** (art. 83). *Exclusivo do plano Full.*
- **Rastreamento de origem** (art. 383): ativa-se *"Rastrear origem das
  conversas"* e informa o campo de telefone do fluxo (ex.: `{{phone}}`).
  ⚠️ **Só funciona para clientes da WhatsApp Suite**; não funciona no Leadster Leads.

**[FATO — o artigo mais didático da base]** Art. 398 mapeia os **4 cenários de
atribuição de origem no WhatsApp**:

| Cenário | Rastreio | Solução |
|---|---|---|
| 1. Mensagem direta ao número | ❌ **Não identificado** | *"Sem solução automática disponível"* |
| 2. Lead veio pelo site com Leadster | ✅ **Identificado** | Ativar rastreamento no módulo de botão |
| 3. Campanha Click to WhatsApp (Meta) | ◉ **Em beta** | Disponível em breve |
| 4. Botão de WhatsApp de terceiro no site | ❌ **Não identificado** | Substituir pelo botão nativo |

**[FATO]** Parâmetros capturados automaticamente no cenário 2: `utm_source`,
`utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, **`gclid`** (Google),
**`fbclid`** (Meta) e *"outros parâmetros de rastreio presentes na URL"*.
Art. 267 adiciona **`lclid`** (LinkedIn).

**[INFERÊNCIA]** O art. 398 é, na prática, uma **peça de vendas disfarçada de
documentação**: ele explica tecnicamente por que o botão de WhatsApp de terceiros
quebra a atribuição e conclui recomendando trocar pelo da Leadster. É um padrão
de conteúdo excelente e replicável.

### 5.9 Teste A/B

**[FATO]** Art. 28. Variáveis testáveis: **Chamada**, **Foto do avatar**,
**Pergunta do fluxo**.
- Split fixo **50/50**.
- Recomendação: aguardar **pelo menos 5.000 visualizações** antes de decidir.
- Métricas comparadas: leads gerados, visualizações do chat, conversão por versão.
- Botão **"Usar esta versão"** promove a vencedora para 100% do tráfego.
- Histórico de testes fica salvo.
- ⚠️ **Não é possível editar ou excluir um fluxo enquanto um teste A/B está
  rodando.**
- Disponível a partir do plano **Pro**.

**[INFERÊNCIA]** Não há teste multivariado, nem split configurável, nem
significância estatística automática ("aguarde 5.000 visualizações" é uma regra
de bolso, não um cálculo). É um A/B **simples e honesto** — e mesmo assim é o
recurso que eles mais citam como gerador de resultado.

### 5.10 Chamada de conversão e chamadas inteligentes

**[FATO]** A **chamada de conversão** é o balão-teaser que aparece antes do chat
abrir. Regra editorial da empresa (arts. 14, 92): **máximo ~50 caracteres**,
*"deve ser entendida com uma passada de olho"*.

**[FATO]** Palavras-chave que, segundo eles, aumentam volume de leads:
*"Descobrir, Veja aqui, rápido, em 5 minutos, Aprovado, Menor preço, Melhor
condição, Exclusiva, Melhores opções"*. Exemplos publicados:
- *"Vamos consultar o preço para sua cotação em 5 min?"*
- *"Vamos agendar a revisão do seu veículo agora?"*
- *"Gostaria de descobrir o melhor consórcio para você?"*

**[FATO]** **Chamadas inteligentes** (art. 47): chamadas **alternativas** que
rotacionam se o visitante não converte na principal. **Tempo mínimo de variação:
20 segundos.** Múltiplas variações via "Adicionar variação". Ganho declarado:
**até 20%**.

**[FATO]** **Chamadas geradas por IA** (arts. 128, 248): informa-se a URL e a IA
gera **5 sugestões** de chamada. Também funciona a partir do Dashboard →
"Páginas mais acessadas" → "criar fluxo". Requer conta paga ou trial e script
implementado; analisa as **10 páginas mais acessadas** e os últimos **30 dias**.

### 5.11 Design e exibição

**[FATO]** Art. 38. Opções expostas:
- **Título do assistente** (cabeçalho).
- **Espaçamento em relação à borda** — existe explicitamente para **não conflitar
  com a barra de cookies LGPD** (art. 64).
- **Posição**: esquerda ou direita.
- **Posição da chamada de conversão**: ao lado do avatar ou acima.
- **Tamanho da foto/chamada**: Padrão, Média ou Reduzida.
- **Avatar**: galeria ou upload próprio. *Novidade:* **avatar com a imagem do
  WhatsApp** como opção padrão.
- **Idioma do assistente** (art. 100).

**[FATO]** Configurações avançadas:
- **Cancelar pré-visualização em tempo real**.
- **Exibição em tela cheia (fullscreen)**.
- **Ocultar chatbot após conversão** — some por **7 dias** para quem já converteu.
- **Ocultar chatbot após conversão de lead descartado ou incompleto** — também
  **7 dias**.
- **Exibir botão para reiniciar chatbot** ao final do fluxo.

**[FATO]** Idiomas da plataforma (art. 236): **Português (Brasil), Português
(Portugal), Inglês e Espanhol** — este último *"apenas para scripts e chamadas"*.

**[INFERÊNCIA]** Não há personalização de **cor** exposta na documentação de
design — só avatar, posição, tamanho e título. **[NÃO VERIFICADO]:** se há
seletor de cor primária no painel. Se realmente não houver, é uma lacuna
significativa e fácil de superar.

### 5.12 Página de captura (chat sem site)

**[FATO]** Art. 79. Gera um **link hospedado** com o fluxo em tela cheia, sem
precisar implementar em site nenhum. Casos de uso sugeridos: enviar por WhatsApp,
bio do Instagram, campanhas específicas. A URL base identificada no bundle é
`https://app.leadster.com.br/capture` (e `https://app.getleadster.com/capture`
na versão internacional).

**[INFERÊNCIA]** É a resposta deles ao Typeform/Landbot. Custo de implementação
zero e vira um ativo distribuível — recurso de altíssimo ROI para o esforço.

### 5.13 Variáveis, atributos e permissões

**[FATO]** **Variáveis personalizadas** (art. 371, etapa 3 do editor): já vêm as
5 UTMs como **padrão**; pode-se criar outras. Boas práticas publicadas: sem
espaços, sem acentos, minúsculas com underline.

**[FATO]** **Atributos personalizados** (art. 372) — aplicam-se a **Conversas** ou
**Contatos**. Campos: *Aplica-se, Nome para exibição, **Chave** (imutável),
Descrição, Tipo*. Tipos: **texto, número, link, data, lista, checkbox**. Suporta
**validação por Regex**.

**[FATO]** **Funções personalizadas** (art. 369) — perfis de acesso com estas
permissões:
- Gerenciar todas as conversas
- Gerenciar conversas não atribuídas e atribuídas ao usuário
- Gerenciar conversas em que participa
- Gerenciar contatos
- Gerenciar relatórios
- Gerenciar base de conhecimento

**[FATO]** **2FA** disponível (art. 74) via Google Authenticator ou Twilio Authy,
com códigos de recuperação exibidos **uma única vez**.

### 5.14 Relatórios e analytics

**[FATO]** **Analytics por fluxo** (art. 115):

| Métrica | Definição documentada |
|---|---|
| **Chats Abertos** | Número total de chats visualizados |
| **Conversas Iniciadas** | Quantas pessoas começaram a conversar |
| **Total de Leads** | Quantos preencheram até o final |
| **Dropout** | Etapa exata onde o usuário abandonou. *"Se não houver abandono, o Dropout não é exibido"* |
| **Redirecionamento para WhatsApp** | ⚠️ Só tem dados se a **Roleta** estiver ativa — mostra números, leads por número e telefones preenchidos |
| **Redirecionamento para Agendamento** | E-mail do responsável, quantidade e % de leads que agendaram, lista de leads com data |

**[FATO]** **Dashboard** — "Páginas mais acessadas" (art. 265): URL, visitantes,
**leads por página**, **% de conversão**, se há **fluxo personalizado ativo**, e
botão de **otimização** (editar fluxo existente ou criar novo para aquela URL).

**[FATO]** **Aba de Leads** (art. 101): filtro por qualificação; *novidade:*
mostra **de qual dispositivo** (Desktop/Mobile) o lead converteu.

**[FATO]** **Exportação** (art. 234): planilha `.xlsx` enviada por e-mail.
Filtros: e-mail destinatário, fluxo (um ou todos), data (**máximo 1 ano**),
versão (**Compacta antiga** — 3 abas; **Completa nova** — aba única; **Completa
por fluxo** — uma aba por fluxo).

**[FATO]** **Relatórios automáticos** (art. 405): agendamento com data do primeiro
envio e periodicidade em dias; múltiplos destinatários; histórico de envios com
status de falha. ⚠️ *"Não é possível editar uma programação após a criação"* —
tem que excluir e recriar.

**[FATO]** **Relatórios semanais** por e-mail vêm **ativados por padrão** e podem
ser removidos (art. 49).

**[FATO]** **Super Dashboard (Leadster × Reportei)** — art. 246: traz dados de
**Google Ads, Meta Ads e LinkedIn Ads** para dentro do dashboard da Leadster:
**Investimento × Conversões**, **Eventos de Conversão por Canal** (LinkedIn não
expõe), e **Campanhas** detalhadas. Grátis para clientes pagos em qualquer plano;
14 dias para free.

**[FATO]** **Lead scoring** (art. 105): define-se **uma nota de qualificação para
cada resposta** do fluxo; leads passam a ser filtráveis por nível.
⚠️ *"Não será possível visualizar a classificação dos leads gerados antes da
configuração"* — **sem recálculo retroativo**.

### 5.15 LGPD

**[FATO]** Art. 51. Campo **"Política de Privacidade (LGPD)"** na etapa 3 do
editor; cola-se a URL e ela passa a ser exibida no chat.

**[FATO]** Postura de compliance declarada (`/blog/leadster-e-confiavel/`):
programa de governança de dados LGPD, firewall Cloudflare, 2FA, criptografia, e
*"nenhum acesso direto do time da Leadster aos dados de leads dos clientes"*.
**[NÃO VERIFICADO]:** auditoria externa, ISO 27001, SOC 2.

---

## 6. Dissecação técnica do widget de captura

Toda esta seção é **[FATO]**, verificada baixando os arquivos públicos.

### 6.1 O snippet oficial de instalação

Extraído do código-fonte do plugin oficial no WordPress.org
(`leadster-marketing-conversacional/views/script-code.php`):

```html
<!--BEGIN LEADSTER SCRIPT-->
<script>
  (function (w, d, s, c) {
    try {
      var h = d.head || d.getElementsByTagName("head")[0];
      var e = d.createElement("script");

      e.setAttribute("src", s);
      e.setAttribute("charset", "UTF-8");
      e.defer = true;

      w.neuroleadId = c;
      h.appendChild(e);
    } catch (e) {}
  })(window, document, "https://cdn.leadster.com.br/neurolead/neurolead.min.js", "<IDENTIFICADOR>");
</script>
<!--END LEADSTER SCRIPT-->
```

**Leitura do snippet:**
- **`defer = true`** — não bloqueia render.
- **Injetado no `<head>`** pelo plugin; a documentação manual (art. 37) recomenda
  *antes de `</body>`*, justificando: *"dessa forma o nosso script é o último a
  ser carregado em seu site, sem afetar o tempo de carregamento da página"*.
- **Um único parâmetro de configuração**: `window.neuroleadId`. Sem objeto de
  settings, sem chaves de API no cliente.
- Todo o corpo está dentro de **`try/catch` vazio** — falha silenciosa, nunca
  quebra o site do cliente.

### 6.2 Métodos de instalação suportados

**[FATO]** Art. 36 — quatro vias: **WordPress** (plugin ou `footer.php`),
**Google Tag Manager** (tag HTML personalizado + trigger *All Pages* + marcar
*"Suporte para document.write"*), **Wix** (Configurações → Avançado → Código
Personalizado, "Todas as páginas" + "Body - fim"), e **HTML manual**.
Há ainda artigos para **RD Station Landing Pages** (arts. 56 e 118).

### 6.3 Tamanho dos bundles

| Arquivo | URL | Tamanho |
|---|---|---|
| Loader/app atual | `https://cdn.leadster.com.br/neurolead/neurolead.min.js` | **456.101 bytes** (~445 KB) |
| App legado | `https://cdn.leadster.com.br/app/client/scripts.min.js` | **288.008 bytes** (~281 KB) |

**[INFERÊNCIA]** ~445 KB não-comprimido é **pesado** para um widget de captura.
Com gzip/brotli deve cair para algo entre 110–150 KB. É carregado com `defer`, o
que mitiga, mas ainda é um bundle grande para um chat de formulário. Não há
indício de code splitting por feature.

### 6.4 Stack do widget

**[FATO]** Evidências no bundle:
- Runtime **Preact/JSX** (funções `_jsx`/`_jsxs` compiladas: `(0,i.Y)(...)`,
  `(0,i.FD)(...)`), bundling **Webpack** (formato `{421:(t,e,n)=>{...}}`).
- Prefixo CSS **`nld-`** em todas as classes (`nld-chatbot`, `nld-bubble`,
  `nld-conversation`, `nld-calendar`, `nld-backdrop`, `nld-fullscreen`,
  `nld-typing-indicator`, `nld-brand-footer`, ...).
- Bibliotecas identificadas: **date-fns**, **uuid**, **prop-types**.
- Fonte carregada de `https://fonts.googleapis.com/css2`.

**[INFERÊNCIA]** Preact + prefixo próprio de CSS = escolha correta para widget
embutido (bundle menor que React, colisão de estilo minimizada). Não há indício
de **Shadow DOM** no bundle — o isolamento é por prefixo de classe, o que é
frágil contra CSS agressivo do site hospedeiro.

### 6.5 Endpoints da API do widget

**[FATO]** Base construída no bundle como:

```js
mn = `${gn()}/api/chatbot`
```

Onde `gn()` resolve para `https://app.leadster.com.br` (BR),
`https://app.getleadster.com` (internacional), `https://qa.leadster.com.br` (QA)
ou `http://localhost` (dev).

**Endpoints identificados:**

| Endpoint | Uso inferido |
|---|---|
| `${API}/leads` | Criação do lead |
| `${API}/lead/{guid}/sync` | Sincronização incremental do lead (a cada resposta) |
| `${API}/events` | Telemetria de eventos |
| `${API}/scripts/search` | Descoberta de qual fluxo exibir (regras de página) |
| `${API}/script_versions/{scriptVersionId}/notifications/random` | Chamadas inteligentes / rotação de chamada |
| `${API}/users/check-email` | Validação de e-mail |
| `/script-blocks/whatsapp-phone` | Resolução do número na roleta de WhatsApp |
| `/tracking` | Rastreamento |

**[INFERÊNCIA — arquitetura importante]** A existência de
**`/lead/{guid}/sync`** significa que o lead é criado **na primeira resposta** e
**atualizado incrementalmente** a cada bloco respondido. É exatamente por isso
que existe o conceito de "lead incompleto" — eles capturam o parcial. Isso é uma
decisão de produto muito boa: o abandono ainda gera dado.

### 6.6 Variáveis globais e API pública

**[FATO]** Identificadas no bundle:

| Global | Função |
|---|---|
| `window.neuroleadId` | **Identificador do site** (o único obrigatório) |
| `window.neurolead` | Objeto principal da API |
| `window.neurolead.open()` | **Abre o chat** (documentado, arts. 46 e 118) |
| `window.neurolead.send` | Envio |
| `window.neurolead._trackEvent` | Tracking de evento |
| `window.neurolead.dataQueue` | Fila de dados |
| `window.neurolead.corsToken` | Token CORS |
| `window.neurolead.elChatbot.remove` | Remoção do elemento do DOM |
| `window.neuroleadCompanyId` | ID da empresa |
| `window.neuroleadScriptId` | ID do fluxo |
| `window.neuroleadDefaultScript` | Fluxo padrão |
| `window.neuroleadPSId` | — |
| `window.neuroleadLanguage` | Idioma |
| `window.neuroleadUser` | Usuário |
| `window.neuroleadsPreferredVersions` | Versões preferidas |
| `window.neuroleadLeadDemoMode` | Modo demo |
| `window.neuroleadEventDevMode` | Modo dev de eventos |

### 6.7 Telemetria coletada do visitante

**[FATO]** O bundle monta um objeto de contexto com:

```js
{
  category:         "mobile" | "desktop",   // via regex de User-Agent
  language:         navigator.language || navigator.userLanguage,
  screenResolution: `${window.screen.width}x${window.screen.height}`,
  operatingSystem:  "Android" | "Windows" | "MacOS" | "Linux" | "Unknown"
}
```

**[FATO]** Parâmetros de campanha capturados: `utm_source`, `utm_medium`,
`utm_campaign`, `utm_content`, `utm_term`, `gclid`, `fbclid`, além de
`referrer`, `session_id`, `guid`, `device`.

**[FATO]** Chaves de armazenamento local: `leadster_ai_interaction`,
`leadster_hide_tooltip`, `neuroleadsPreferredVersions`, `neuroleadUser`.

### 6.8 Eventos disparados para Google e Meta

**[FATO]** Chamadas encontradas literalmente no bundle:

```js
// Meta / Facebook Pixel
fbq("init", t)
fbq("track", "PageView")
fbq("track", t)
fbq("trackSingle", t, e)
fbq("track", this.metadata.fbqConversionEvents[0])

// Google
gtag("js", new Date)
gtag("config", t)
gtag("event", "new_lead")
gtag("event", "Leadster", { event_category: "new_lead" })
gtag("event", i, { event_category: "Neurologic" })   // <- marca antiga viva
gtag("event", "leadster_ai_interaction")
gtag("event", "conversion", { send_to: this.metadata.gtagConversionId, event_callback: ... })
gtag("event", this.metadata.gaConversionEvent[1], { event_category: ... })
gtag("get", t, e, cb)
```

E o evento canônico interno: **`event: "new_lead"`**.

**[FATO]** Scripts de terceiros carregados pelo próprio widget:
`https://connect.facebook.net/en_US/fbevents.js` e
`https://www.googletagmanager.com/gtag/js`.

**[INFERÊNCIA]** O widget **injeta o pixel do Meta e o gtag por conta própria**
caso o site não os tenha (art. 250 confirma: *"usaremos os IDs já cadastrados na
sua página para enviar"*). Isso é conveniente para o cliente e é um vetor de
diferenciação — mas também significa que o widget **adiciona duas requisições de
terceiros** ao site do cliente.

### 6.9 Envio server-side (CAPI)

**[FATO]** Art. 384 documenta o bloco **"Enviar eventos GA/Meta Ads via API"**:
- **Meta Ads**: credencial com **nome, Pixel Code e token de acesso** (via
  conexão OAuth com a Meta).
- **Google Ads (via GA4)**: credencial com **nome, Measurement ID e API Secret**.
- **"Envio avançado de parâmetros"**: mapeia **nome, e-mail, telefone, cidade,
  estado** coletados no fluxo para os campos de *matching* da plataforma.
- Justificativa declarada: *"Melhor correspondência de dados com as plataformas
  (match)"*, *"Maior precisão na mensuração"*.

**[INFERÊNCIA]** Isso é **Conversions API (CAPI) do Meta + Measurement Protocol
do GA4**, com *advanced matching*. É um recurso sofisticado e caro de construir —
e é **o diferencial técnico mais real do produto**, porque resolve o problema de
perda de sinal por bloqueio de cookies/ITP. Muito mais relevante que a UI do chat.

### 6.10 Outros recursos do CDN

**[FATO]** O bucket GCS `neuro-cdn` é **público e listável**
(`https://cdn.leadster.com.br/` retorna XML de listagem). Assets identificados:
- `https://cdn.leadster.com.br/leadster/state_cities.json` — cidades por UF.
- `https://cdn.leadster.com.br/leadster/app/image/flags.png` — sprite de bandeiras
  (telefone internacional).
- `https://cdn.leadster.com.br/neurolead/img/avatar.png`, `restart_chat.png`,
  `wpp_logo.png`.
- `app/modules/*.js` — **módulos por cliente**: `imobille.js`, `jornaldocarro.js`,
  `jornaldocarro_prod.js`, `kontaazul.js`, `moving.js`, `ibge_localidades.js`,
  `postmon.js`, `autoclose.js`, `redirect.js`, `neurologic.js` (última
  modificação: 10/04/2024). Há espelho em `app/qa/modules/`.

**[INFERÊNCIA]** Os "módulos" nomeados por cliente (`imobille`, `jornaldocarro`,
`kontaazul`, `moving`) revelam que existe (ou existiu) um mecanismo de
**customização por cliente via JS carregado sob demanda**
(`${CDN}/modules/${nome}`) — provavelmente para integrações sob medida
(`postmon` é uma API de CEP; `ibge_localidades` é lista de municípios do IBGE).
É uma válvula de escape para pedidos de enterprise. Também é uma **dívida
técnica**: código de cliente hospedado em CDN pública.

---

## 7. ACHADO CENTRAL: a Suite de atendimento da Leadster é um Chatwoot white-label

Este é o achado mais importante deste estudo para o ChatSPX.

### 7.1 A prova

**[FATO]** Os domínios `https://atendimento.leadster.com.br/` e
`https://chat.leadster.com.br/` servem uma aplicação cujo HTML expõe, no próprio
`window.globalConfig`, o seguinte objeto (transcrição literal, sem edição):

```json
{
  "LOGO": "https://storage.googleapis.com/neuro-cdn/leadster/ico/atendimento/512x512%20atendimento.png",
  "INSTALLATION_NAME": "Leadster",
  "WIDGET_BRAND_URL": "https://leadster.com.br",
  "TERMS_URL": "https://leadster.com.br/terms-of-service",
  "BRAND_URL": "https://leadster.com.br",
  "BRAND_NAME": "Leadster",
  "PRIVACY_URL": "https://leadster.com.br/privacy-policy",
  "DISPLAY_MANIFEST": false,
  "CREATE_NEW_ACCOUNT_FROM_DASHBOARD": false,
  "CHATWOOT_INBOX_TOKEN": null,
  "API_CHANNEL_NAME": null,
  "DIRECT_UPLOADS_ENABLED": false,
  "HCAPTCHA_SITE_KEY": null,
  "LOGOUT_REDIRECT_LINK": "/app/login",
  "DEPLOYMENT_ENV": "self-hosted",
  "INSTALLATION_PRICING_PLAN": "enterprise",
  "APP_VERSION": "4.5.2",
  "ENABLE_ACCOUNT_SIGNUP": false,
  "FB_APP_ID": "2119622611895742",
  "INSTAGRAM_APP_ID": "3225426607634212",
  "FACEBOOK_API_VERSION": "v17.0",
  "WHATSAPP_APP_ID": "2119622611895742",
  "WHATSAPP_CONFIGURATION_ID": "1115582787328582",
  "IS_ENTERPRISE": true,
  "GOOGLE_OAUTH_CLIENT_ID": "64968605958-rtfd1rom5du0bm44tj2rn6e879f65uqa.apps.googleusercontent.com",
  "GOOGLE_OAUTH_CALLBACK_URL": "https://atendimento.leadster.com.br/google/callback",
  "GIT_SHA": "de9c0db3e5e75d8cf51e4cd4a01034672e5a0c41"
}
```

**Chaves decisivas:** `CHATWOOT_INBOX_TOKEN`, `INSTALLATION_NAME`,
`INSTALLATION_PRICING_PLAN: "enterprise"`, `IS_ENTERPRISE: true`,
`DEPLOYMENT_ENV: "self-hosted"`, `APP_VERSION: "4.5.2"`, `GIT_SHA`.
São **exatamente** os nomes de configuração do Chatwoot.

**[FATO]** Evidências corroborantes no mesmo HTML:
- `<meta name="csrf-param" content="authenticity_token">` → **Rails**.
- Assets em **`/vite/assets/dashboard-*.js`** e `dashboard-*.css` → build Vite do
  dashboard do Chatwoot.
- Módulos com nomes idênticos aos do Chatwoot: `useBranding-*.js`,
  `IframeLoader-*.js`, `DashboardIcon-*.js`, `vue-dompurify-html-*.js` → **Vue**.

### 7.2 Corroboração pela documentação

**[FATO]** A base de conhecimento da própria Leadster descreve a WhatsApp Suite
com o vocabulário **literal** do Chatwoot:

| Termo na KB da Leadster | Artigo | Equivalente no Chatwoot |
|---|---|---|
| **Caixa de entrada** | 400, 401, 403 | Inbox |
| **Agentes** | 319, 396, 400 | Agents |
| **Etiquetas** | 322, 355, 373 | Labels |
| **Respostas prontas** | 323, 354 | Canned responses |
| **Atributos personalizados** (Conversa/Contato) | 372 | Custom attributes |
| **Funções personalizadas** | 369 | Custom roles (enterprise) |
| **Automações** (evento → condições → ações) | 326 | Automation rules |
| **CSAT** (emoji ou estrelas, msg ≤200 chars) | 324 | CSAT |
| **SLA** (1ª resposta / próxima resposta / resolução) | 325 | SLA policies |
| **Campanhas** | 344 | Campaigns |
| **Painel de Aplicativos** | 339 | Dashboard Apps |
| **Conversa única / Bloquear para conversa única** | 393 | `lock_to_single_conversation` |

**[FATO — a prova mais conclusiva]** O art. 339 lista as integrações disponíveis
na "Leadster WhatsApp Suite": **Webhooks, Painel de Aplicativos, OpenAI,
Dialogflow, Tradutor do Google, Dyte e LeadSquared**.

Esta é, item por item e na mesma ordem conceitual, **a lista de integrações
nativas do Chatwoot**. "Dyte" (vídeo/voz) e "LeadSquared" (CRM indiano) não têm
nenhuma relação com o mercado brasileiro nem com a proposta da Leadster — só
estão ali porque **vieram de fábrica no Chatwoot**.

**[FATO]** As permissões de "Funções personalizadas" (art. 369) são a lista
exata de permissões de Custom Roles do Chatwoot enterprise:
*conversation_manage, conversation_unassigned_manage,
conversation_participating_manage, contact_manage, report_manage,
knowledge_base_manage*.

### 7.3 Conclusão e comparação de versões

**[CONCLUSÃO — FATO, não inferência]** A **Leadster WhatsApp Suite** e o
**Leadster Live Chat** são um **Chatwoot self-hosted, edição enterprise,
versão 4.5.2**, white-labelado como Leadster. O produto proprietário deles é o
**widget de captura (`neurolead`)** e o painel de fluxos em
`app.leadster.com.br` — que é uma aplicação **separada** (Rails com Sprockets +
Webpacker: `/assets/application-*.css`, `/packs/js/application-*.js`).

**[FATO]** Comparação direta com o ChatSPX (verificado no repositório local):

| | Leadster (atendimento) | **ChatSPX** |
|---|---|---|
| Base | Chatwoot | Chatwoot |
| **Versão** | **4.5.2** | **4.12.1** (`config/app.yml`, `package.json`) |
| Edição | enterprise, self-hosted | enterprise, self-hosted |
| Branding | `INSTALLATION_NAME: "Leadster"` | ChatSPX |

**[INFERÊNCIA]** O ChatSPX está **7 minor versions à frente** da Leadster na
mesma base de código. Tudo que a Leadster vende como "WhatsApp Suite",
"Live Chat", "CSAT", "SLA", "Automações", "Campanhas", "Etiquetas", "Respostas
prontas", "Atributos personalizados", "Funções personalizadas", "Painel de
Aplicativos" — **o ChatSPX já tem, e em versão mais nova.**

**[INFERÊNCIA — a leitura estratégica]** Isto reposiciona completamente o
problema. A Leadster **não é um concorrente com uma plataforma superior**. É um
concorrente que:
1. usa **o mesmo motor de atendimento que nós** (mais velho);
2. tem, por cima dele, **um produto de captura web que nós não temos**;
3. e tem, em volta de tudo, **uma metodologia, um benchmark anual e uma máquina
   de conteúdo que valem mais que o software**.

A distância entre ChatSPX e Leadster **não é de plataforma de atendimento — é de
camada de aquisição e de narrativa.**

---

## 8. Integrações

### 8.1 Integrações nativas (Website Suite)

**[FATO]** Art. 82: *"Atualmente, possuímos integrações nativas com 20
plataformas"*. Lista publicada:

| # | Plataforma | Artigo dedicado |
|---|---|---|
| 1 | **RD Station Marketing** | 20, 44, 66 |
| 2 | **HubSpot** | 76 |
| 3 | **Salesforce** | 111 |
| 4 | **Bitrix24** | 109 |
| 5 | **ActiveCampaign** | 81 |
| 6 | **PipeRun** | 57 |
| 7 | **Exact Sales** | 61 |
| 8 | **Zoho** | 408 |
| 9 | **Contact2Sales** | 402 |
| 10 | **Sirena** | 91 |
| 11 | **Lahar** | 89 |
| 12 | **Fleeg** | 90 |
| 13 | **Praedium** (imobiliário) | 87 |
| 14 | **FolloWise / Dealerspace** (automotivo) | 262 |
| 15 | **Google Sheets** | 229 |
| 16 | HouseCRM | via modelo genérico |
| 17 | E-Goi | via modelo genérico |
| 18 | ANAPRO | via modelo genérico |
| 19 | SIMPLE PACK | via modelo genérico |
| 20 | F1 SALES | via modelo genérico |

**[FATO]** A home fala em *"200+ integrações nativas com CRMs"* e o
`/agentes-de-ai/` em *"200+ plataformas nativas"* — **[DIVERGÊNCIA]** com o
número 20 da própria KB. **[INFERÊNCIA]** o "200+" provavelmente soma as
plataformas alcançáveis via Zapier/Pluga/Albato. Marketing infla; a KB é honesta.

**[FATO]** Ressalva importante: a integração nativa é com **RD Station
*Marketing***. Para **RD Station *CRM*** *"deve ser integrado com integradores
como Webhook, Pluga ou Zapier"* (art. 20). Exige plano **PRO ou superior** do RD.

**[FATO]** Salesforce: acesso à API só nas edições *Professional, Performance,
Enterprise, Unlimited e Developer* — e na Professional o acesso à API **deve ser
comprado à parte**.

### 8.2 iPaaS

**[FATO]** **Zapier** (art. 24, via *Webhooks by Zapier* → *Catch Hook*),
**Pluga** (art. 86, brasileiro), **Albato** (art. 226) — os dois últimos com
*"+1000 plataformas"*.

### 8.3 Webhook — o payload real

**[FATO]** Art. 58 documenta **dois formatos** de POST.

**Com campos mapeados** (flat, limpo):
```json
{
  "phone": "(41) 99999-9999",
  "name": "André",
  "email": "andre@neurologic.com.br",
  "url": "http://localhost:8000/"
}
```

**Sem mapeamento** (payload completo):
```json
{
  "lead": {
    "id": "7151042b-3ee3-9eac-19d3-fadcd342d13b",
    "data": {
      "url": "http://localhost:8000/",
      "nome": "André",
      "e_mail": "andre@neurologic.com.br",
      "telefone": "(41) 99999-9999"
    },
    "script": {
      "id": 8025,
      "name": "Principal - editando",
      "default": true,
      "enabled": true,
      "ab_test_id": null,
      "company_id": 10,
      "discarded_at": null,
      "script_rule_id": 7778,
      "script_version_id": 59945,
      "privacy_policy_url": null
    },
    "synced": false,
    "email_to": "felipe@test.com",
    "lead_data": [
      { "key": "1::Telefone", "step": 1, "value": "(41) 99999-9999", "created_at": "2020-11-05T14:11:32.642-03:00" },
      { "key": "9999::URL",   "step": 1, "value": "http://localhost:8000/", "created_at": "2020-11-05T14:11:32.646-03:00" },
      { "key": "2::Nome",     "step": 2, "value": "André", "created_at": "2020-11-05T14:11:38.507-03:00" },
      { "key": "3::E-Mail",   "step": 3, "value": "andre@neurologic.com.br", "created_at": "2020-11-05T14:11:45.707-03:00" }
    ],
    "script_id": 8025,
    "created_at": "2020-11-05T14:11:32.636-03:00",
    "email_from": "leads@neurologic.com.br",
    "updated_at": "2020-11-05T14:11:45.723-03:00",
    "integrations": {},
    "email_subject": "Novo lead gerado [Neurologic]",
    "script_version_id": 59945
  }
}
```

**[INFERÊNCIA — modelo de dados revelado]** O payload expõe a arquitetura
interna: **`script`** = fluxo; **`script_version`** = versão publicada do fluxo
(controle de versão de fluxo!); **`script_rule`** = regra de página;
**`ab_test_id`** = vínculo com teste A/B; **`lead_data`** = array de respostas
com **`key` no formato `{ordem}::{Nome do campo}`**, **`step`** e
**`created_at` por resposta** (permite medir tempo entre perguntas);
**`discarded_at`** = soft delete; **`synced`** = flag de sincronização com
integrações. É um modelo bem pensado. O `created_at` por resposta é o que
alimenta o gráfico de **Dropout**.

**[FATO]** Suporte a **JSON Web Tokens (JWT)** na configuração de webhook
(título do art. 58). Contact2Sales usa campo **"Chave Bearer JWT"** (art. 402).

### 8.4 Gestão de erros de integração

**[FATO]** Recurso maduro e pouco comum:
- **"Eventos recentes com erro"** (aba Integração).
- **Relatórios de erro por e-mail** com frequência de **1, 7 ou 30 dias**,
  múltiplos destinatários (art. 308).
- **Reenvio em massa ou individual** dos leads com erro; com visualização do
  motivo do erro por lead (art. 309).

**[INFERÊNCIA]** Uma **dead-letter queue com UI**. É exatamente o tipo de recurso
que só se constrói depois de perder leads de cliente e apanhar por isso.

### 8.5 Integrações de mídia e analytics

**[FATO]**
- **GA4 / Google Analytics**: eventos automatizados (art. 120), configuração
  manual (art. 122), e conversão no **Google Ads** a partir do GA (art. 211).
- **Meta Pixel**: eventos automatizados (art. 120).
- **Gerenciamento de disparo de eventos de marketing**: Meta Ads (art. 363) e
  GA4 (art. 375).
- **ChatGPT Ads**: art. 409 — *"Como enviar conversões da Leadster ao ChatGPT Ads"*.
- **Reportei**: Super Dashboard (art. 246).

---

## 9. Preços e planos

### 9.1 Modelo de precificação

**[FATO]** Arts. 67, 242–244: *"Nossas assinaturas pagas são baseadas nas
**funcionalidades** da ferramenta, e pela **quantidade de acessos** que há no seu
site"*. Faixas a partir de **1.000 acessos mensais**.

**[FATO]** Ciclos: **mensal, trimestral, semestral e anual**. Pagamento:
**boleto, cartão de crédito e PIX**. Desconto anual: **20%** (`/preco/`).

### 9.2 Valores publicados

**[FATO]** `https://leadster.com.br/preco/` (faixa de entrada, 1.000 acessos/mês,
cobrança anual com 20% de desconto):

| Plano | Valor | Limite de leads | Fluxos | Acessos |
|---|---|---|---|---|
| **Free** | **R$ 0** | **15 leads/mês** | **1 fluxo** (a página de preços) / **3 fluxos** (art. 241) | até 1.000 |
| **Starter** | **R$ 142/mês** | Ilimitados | **3** (página) / **5** (art. 242 e 67) | até 1.000 |
| **Pro** | **R$ 154/mês** | Ilimitados | **Ilimitados** | até 1.000 |
| **Full** | *não publicado na página* | Ilimitados | Ilimitados | — |

**[DIVERGÊNCIA]** O limite de fluxos do Free e do Starter difere entre a página
de preços (1 e 3) e os artigos de KB 241/242/67 (3 e 5). **[INFERÊNCIA]** os
artigos de KB parecem desatualizados em relação à página de preços; ou a página
de preços foi reestruturada recentemente (ela lista apenas Free/Starter/Pro,
enquanto a KB descreve Free/Starter/Pro/**Full**).

**[FATO]** Outro valor real publicado: art. 313 (programa de indicação) cita
*"um plano anual de **R$ 559/mês**"* como exemplo — evidência de que as faixas
superiores de tráfego chegam facilmente a esse patamar.

**[NÃO VERIFICADO]:** a tabela completa de preço por faixa de acessos
(3.000, 10.000, 50.000...). A página só expõe a faixa de entrada; acima disso é
proposta comercial.

**[NÃO VERIFICADO — preço internacional]:** `getleadster.com/pt/pricing/` está
protegido por *Vercel Security Checkpoint* e não pôde ser lido diretamente.
**Indício** (via resumo do Capterra, não confirmado na fonte): plano *Starter*
US$ 47/mês (até 1.000 visitantes) e *Traction* US$ 77/mês (até 3.000).
**Tratar como não confirmado.**

### 9.3 Matriz de funcionalidades por plano

**[FATO]** Transcrição consolidada do art. 67 e da página `/preco/`:

| Funcionalidade | Free | Starter | Pro | Full |
|---|:---:|:---:|:---:|:---:|
| Limite de leads | 15/mês | Ilimitado | Ilimitado | Ilimitado |
| Limite de fluxos | 3 | 5 | Ilimitado | Ilimitado |
| Dashboard de performance | ✔ | ✔ | ✔ | ✔ |
| Redirecionamento de WhatsApp | ✔ | ✔ | ✔ | ✔ |
| Página de captura | ✔ | ✔ | ✔ | ✔ |
| Integrações com CRM | ✔ | ✔ | ✔ | ✔ |
| Eventos para Google e Meta Ads | ✔ | ✔ | ✔ | ✔ |
| Suporte | Ticket | Chat ao vivo | Chat + WhatsApp | Chat + WhatsApp |
| Chamadas inteligentes | — | ✔ | ✔ | ✔ |
| Onboarding em grupo | — | ✔ | ✔ | ✔ |
| Onboarding individual | — | — | ✔ | ✔ |
| **Lead scoring** | — | — | ✔ | ✔ |
| **Analytics dos fluxos** | — | — | ✔ | ✔ |
| Redirecionamento por link | — | — | ✔ | ✔ |
| Localização dos leads | — | — | ✔ | ✔ |
| **Teste A/B** | — | — | ✔ | ✔ |
| **Leadster AI** | — | — | — | ✔ (a partir de 100 respostas) |
| Gerente de contas executivo | — | — | — | ✔ |
| Geração de chamadas com IA | — | — | — | ✔ |
| **Roleta do WhatsApp** | — | — | — | ✔ |
| **Agendamento de reuniões** | — | — | — | ✔ |
| Dashboard de mídia (Reportei) | — | — | — | ✔ |
| **Live Chat** *(novo)* | — | — | — | ✔ |

**[INFERÊNCIA]** O gating é agressivo e bem desenhado: **teste A/B e analytics de
fluxo só no Pro** (os dois recursos que provam ROI), e **roleta de WhatsApp +
agendamento + IA só no Full** (os que geram dependência operacional). Um cliente
que ativa roleta e agendamento **não sai mais**.

### 9.4 Trial e plano gratuito

**[FATO]** Arts. 48, 241:
- **14 dias grátis**, **sem cartão de crédito**.
- Ao fim dos 14 dias: se gerou **menos de 15 leads (proporcional)** → migra
  automaticamente para o **plano gratuito** (15 leads/mês).
- Se ultrapassou → *"nossa equipe entrará em contato para te apresentar os
  benefícios de assinar um plano"*.
- *"Reforçamos que **não realizamos nenhum tipo de migração de plano
  automático**"* e *"não há cobranças automáticas"*.
- O plano gratuito vale **enquanto** o cliente ficar sob 15 leads/mês.

### 9.5 Cancelamento

**[FATO]** Art. 204:
- **Mensal**: exige **aviso prévio de 30 dias** (previsto em contrato).
- **Trimestral / semestral / anual**: pode cancelar a qualquer momento, mas
  **não há previsão de reembolso**.
- **Plano gratuito**: basta remover o script e pedir exclusão da conta.
- Fluxo: contato com Customer Success, ou pelo painel em
  *nome → Assinatura → "Deseja cancelar sua Assinatura?"*.

**[INFERÊNCIA]** Cancelamento **não é self-service completo** — o caminho
principal é falar com CS. Combinado com as reclamações públicas sobre
cancelamento (seção 13), é um ponto de atrito real.

### 9.6 Add-ons e programas

**[FATO]**
- **Agendamento Google Calendar**: **R$ 49,00/vendedor/mês** (art. 112).
- **Leadster AI**: **a partir de R$ 220/mês**, por volume de interações.
- **Programa de indicação** (art. 313): **R$ 150 em vale-presente** por
  assinatura indicada (liberado em até 30 dias), indicado ganha **10% de
  desconto**, **sem limite de indicações**, cupom e link não são cumulativos.
- **AppSumo**: existiu um deal (LTD) com **white label / remoção do logo**
  disponível **apenas para planos Leadster AppSumo** (art. 239), via
  *Minha Agência → White Label → Sua Logo*.

**[INFERÊNCIA]** A existência de white-label restrito ao AppSumo indica que
**white-label não é oferecido no produto padrão** — relevante para quem quiser
competir oferecendo revenda a agências.

### 9.7 Programa de agências

**[NÃO VERIFICADO]** As páginas `/agencias-parceiras/` e
`/agencias-parceiras/programa/` retornaram HTTP 403 ao fetcher e *Vercel Security
Checkpoint* ao curl. **[FATO]** o que se sabe: existem no sitemap as rotas
`/agencias-parceiras/`, `/agencias-parceiras/programa/`,
`/agencias-parceiras/termo-de-compromisso/`, `/conta_agencia/` e
`/geracao-de-leads/agencias/`; e o painel tem uma seção **"Minha Agência"**
(art. 239). Comissões, tiers e requisitos: **não verificados**.

---

## 10. Mapa da central de ajuda — a superfície real do produto

**[FATO]** `https://help.leadster.com.br` roda em **Help Scout Docs**. O sitemap
(`/sitemap.xml`) expõe **240 URLs**: **6 coleções**, **31 categorias** e
**202 artigos**.

### 10.1 Coleções

| Coleção | Slug |
|---|---|
| Tudo sobre o seu fluxo | `4-tudo-sobre-o-seu-fluxo` |
| Gerencie seus Leads | `1-gerencie-seus-leads` |
| Configurações da conta | `7-configuracoes-da-conta` |
| Integração | `96-integracao` |
| Assistente AI | `217-assistente-ai` |
| **WhatsApp Suite** | `314-whatsapp-suite` |

### 10.2 As 31 categorias — o organograma funcional do produto

**[FATO]**

**Produto core / fluxo:**
`288-aumentar-taxa-de-conversao` · `290-personalize-o-conteudo-do-seu-fluxo` ·
`291-fluxos-personalizados-por-pagina` · `292-design-e-exibicao-do-seu-fluxo` ·
`289-qualificacao-condicionais-e-lead-scoring` · `294-pagina-de-captura` ·
`296-teste-ab` · `293-recebimento-de-leads-whatsapp-e-e-mail` ·
`297-como-monitorar-os-eventos-do-chatbot` ·
`399-rastrear-origem-e-disparar-eventos-de-conversao` · `11-performance` ·
`279-recebimento-de-lead`

**Conta e implementação:**
`300-conheca-a-leadster` · `303-implementacao` · `302-configuracoes-da-conta` ·
`367-conta` · `70-marca`

**Integrações:**
`207-tutoriais-de-integracoes-nativas` ·
`208-tutoriais-de-integracoes-nao-nativas` ·
`268-configuracoes-adicionais-das-integracoes` ·
`209-com-quais-ferramentas-posso-integrar-a-leadster`

**IA:**
`269-como-configurar-a-assistente-ia` · `270-shopbot`

**WhatsApp Suite / atendimento:**
`388-agente-no-whatsapp` · `348-live-chat` · `318-configuracoes` ·
`337-gestao-de-conversas` · `345-campanhas-de-whatsapp` ·
`332-templates-e-utilidades` · `335-relatorio` · `331-erros-e-correcoes`

**[INFERÊNCIA — leitura do mapa]** Das 31 categorias, **9 são exclusivas da
WhatsApp Suite/atendimento** e apenas **2 são de IA**. A KB inteira, que começou
como documentação de um chatbot de site, hoje tem **quase um terço dedicado à
plataforma de atendimento (= Chatwoot)**. Isso confirma para onde a empresa está
migrando o centro de gravidade do produto: **de captura para atendimento**.

O índice completo dos 202 artigos está no [Anexo A](#anexo-a--índice-completo-dos-202-artigos-da-base-de-conhecimento).

---

## 11. Blog e conteúdo: a máquina de demanda

### 11.1 Escala

**[FATO]** O sitemap principal tem **264 URLs**. Descontando o blog, há
**~150 páginas** de produto, landing pages, calculadoras, cases e "jornadas".

### 11.2 Tipologia dos ativos de conteúdo

**[FATO]** Categorias identificadas no sitemap:

| Tipo | Exemplos de rota |
|---|---|
| **Comparativos "X vs Leadster"** | `/formularios-vs-leadster/`, `/chatbot-vs-leadster/`, `/chat-online-vs-leadster/`, `/botao-do-whatsapp-vs-leadster/` |
| **Playbook de estratégias** (18 páginas) | `/estrategias-para-gerar-leads-com-chatbots/*` — chatbot no blog, como botão, como página, dentro do conteúdo, para anúncios, para outbound, para VSL de infoproduto, para e-commerce, teste A/B, download de materiais ricos, análise de desistência, agendamento, atendimento de time interno... |
| **Verticais** | `/geracao-de-leads/{b2b, imobiliaria, juridico, educacional, investimento, software, agencias}` |
| **Estudos de caso** (17) | `/estudo-de-caso/{sankhya, catolica, contraktor, espresso, isaac, junta, kenlo, log10, organica-digital, rafael-cassio, recurso-para-multas, revenda-mais, unity-4-e-dryve, vr, sdr-ia-registrou-marcas, leadster-ai}` |
| **Ferramentas gratuitas** (lead magnets) | `/gerador-de-link-whatsapp/`, `/contador-de-caracteres/`, `/calculadora/whatsapp/`, `/checklist-diagnostico-queda-leads/` |
| **Conteúdo gamificado** | `/enfrentando-dragoes-marketing/` com "jornadas" de conteúdo, mídia paga e pré-vendas |
| **Fluxos prontos** | `/fluxos/{como-criar-um-chatbot-gratis-leadster, falar_com_time, gerador-de-leads, melhores-chatbots}` |
| **Sazonal** | `/black-friday-2025/{leadster, shopbot, whatsapp}` |

### 11.3 As teses que eles repetem

**[FATO]** Consolidado do blog e das landing pages:

1. **"Formulários estão mortos"** — título literal de post
   (`blog.leadster.com.br/formularios-para-captacao-de-leads/`). Argumento:
   *"interface estática criada na fundação da internet"*, *"formulário longo é
   igual a baixa conversão"*, *"leads sem filtro, nenhuma qualificação"*.
2. **"Chatbot conversacional > botão de WhatsApp > formulário"** — sempre nessa
   ordem, com os números 450 / 230 / 150 leads.
3. **"Qualificar antes de passar para vendas"** — +50% de vendas com −33% de
   custo de time.
4. **"O problema não é tráfego, é conversão"** — o 97% que abandona.
5. **"Responder rápido é o diferencial"** — 63% não atendidos a tempo; 1 dia 5h
   17min de tempo médio.
6. **"O benchmark é nosso"** — o Panorama como autoridade.

### 11.4 GEO / otimização para LLM

**[FATO — e é o movimento mais moderno que eles fizeram]**

- `robots.txt` com **allow explícito** para `GPTBot`, `ChatGPT-User`,
  `OAI-SearchBot`, `OAI-AdsBot`, `Google-Extended`, `anthropic-ai`, `Claude-Web`,
  `PerplexityBot`, `Applebot-Extended`.
- A home tem CTAs que abrem **ChatGPT, Claude, Perplexity, Grok e Google AI Mode**
  com um prompt longo já escrito, do tipo: *"Sou gerente de marketing e estou
  buscando maneiras de aumentar a geração de leads qualificados e vendas da minha
  empresa pelo Site e WhatsApp. Quero entender o que faz a Leadster diferente de
  um chat comum..."*.
- Artigo de KB **409** sobre enviar conversões para o **ChatGPT Ads**.
- E o Panorama 2026 elege **IA generativa como o canal de maior conversão (7,80%)**.

**[INFERÊNCIA]** Eles fecharam o ciclo: **produzem o dado que prova que o canal
de IA converte melhor**, **otimizam o site para ser lido pelos LLMs**, e
**vendem a mensuração desse canal**. É uma jogada de posicionamento de primeira
linha e é o que mais vale copiar deles em 2026.

---

## 12. Concorrentes: como a própria Leadster se compara

**[FATO]** `https://leadster.com.br/blog/comparativo-leadster/` compara
**12 concorrentes** em **7 critérios** (Foco, Tipo de ferramenta, Canais,
Principais recursos, Vantagens e desvantagens, Planos, Avaliação):

| # | Concorrente | Categoria |
|---|---|---|
| 1 | **HubSpot** | CRM + marketing all-in-one |
| 2 | **Pipedrive (LeadBooster)** | CRM + add-on de chat |
| 3 | **ActiveCampaign** | Automação de marketing |
| 4 | **Landbot** | Construtor de chatbot conversacional |
| 5 | **Merlin** | Chatbot |
| 6 | **Intercom** | Atendimento + engajamento |
| 7 | **Tawk.to** | Live chat gratuito |
| 8 | **JivoChat** | Live chat (já foi *integração* deles — art. 59) |
| 9 | **Take Blip** | Plataforma conversacional BR (enterprise) |
| 10 | **Zendesk** | Atendimento |
| 11 | **Movidesk** | Help desk BR |
| 12 | **Tidio** | Live chat + chatbot |

**[FATO]** Posicionamento declarado deles no comparativo:
*"Única ferramenta voltada 100% para a geração de leads"*. Vantagens que
enfatizam: fluxos e conversas ilimitadas em qualquer plano pago, **preço em
real**, nota **4,9/5** e **93% de satisfação**.

**[INFERÊNCIA — o mapa competitivo real]** A lista revela como se enxergam:
não competem com Zendesk/Movidesk (atendimento) nem com HubSpot (CRM). Competem
por **um orçamento de marketing**, não de suporte. O eixo é
*"quem transforma tráfego em lead"*. **Notável: o Chatwoot não aparece na lista
— nem como concorrente, nem como fornecedor.**

---

## 13. Críticas, limitações e reclamações públicas

Esta seção é deliberadamente honesta, conforme pedido.

### 13.1 Notas agregadas

**[FATO]**

| Plataforma | Nota | Base | Fonte |
|---|---|---|---|
| **Capterra** | **4,5 / 5** (facilidade 4,6; atendimento 4,6) | **11 reviews** | [Capterra](https://www.capterra.com/p/248283/Leadster/reviews/) |
| **B2B Stack** | **4,9 / 5** | **4 avaliações** | [B2B Stack](https://www.b2bstack.com.br/product/leadster/avaliacoes) |
| **AppSumo** | **4,6 / 5** | — | [AppSumo](https://appsumo.com/products/leadster/reviews/) |
| **Reclame Aqui** | **sem reputação calculada** | menos de 10 reclamações avaliadas | [Reclame Aqui](https://www.reclameaqui.com.br/empresa/leadster/) |

**[INFERÊNCIA]** As bases são **pequenas demais** (4 e 11 reviews) para
sustentar o "4,9/5" que usam no marketing. Não é fraude — é amostra pequena.
O dado do Reclame Aqui (sem reputação por baixo volume) é, na prática, um bom
sinal: uma empresa com 3.000 clientes e menos de 10 reclamações avaliadas não
tem crise de satisfação.

### 13.2 Reclamações no Reclame Aqui

**[FATO]** Temas identificados na listagem pública
(`https://www.reclameaqui.com.br/empresa/leadster/lista-reclamacoes/`) —
a página bloqueou fetch direto (HTTP 403), então os temas vêm do índice de busca:

1. **Acesso/senha**: plataforma reconhece o e-mail mas rejeita a senha correta.
2. **Cancelamento**: dificuldade de cancelar; encaminhamento para um WhatsApp
   que não responde.
3. **Cobranças**: e-mails informando débito no cartão de crédito.
4. **Prospecção não autorizada**: obtenção de e-mails sem autorização e spam
   comercial.

**[INFERÊNCIA]** Os itens 2 e 3 conversam diretamente com a política de
cancelamento (aviso prévio de 30 dias, sem reembolso em planos longos, CS como
canal principal). O item 4 é sério: uma empresa que vende LGPD-compliance sendo
acusada de prospecção não autorizada. **[NÃO VERIFICADO]:** desfecho das
reclamações e resposta da empresa.

### 13.3 Contras citados por usuários (Capterra)

**[FATO]** Citações literais:
- *"O valor para contratar a ferramenta me deixou a desejar"*
- *"A parte de integração talvez seja algo que precise de atenção"*
- *"O lead ser descartado automaticamente caso não responda uma pergunta
  obrigatória"*
- *"Um BI mais robusto com mais informações sobre as conversões"*
- Processo de integração com CRM complexo
- Limitações no direcionamento condicional de fluxos
- Impossibilidade de extrair relatórios simplificados de fluxos com condicionais

**[FATO]** B2B Stack: integração com RD Station *"precisa ser bem configurada,
pois algumas vezes há problemas com campos"*; preço; crashes ocasionais;
customização limitada.

**[FATO]** AppSumo: crashes ocasionais; opções de customização limitadas;
**"limited developer-friendly features like custom HTML or JavaScript SDK
integration"**; há review pública intitulada *"Leave a lot to be desired"*.

### 13.4 Limitações declaradas pela própria Leadster

**[FATO]** A KB é honesta sobre limites — lista consolidada:

| Limitação | Artigo |
|---|---|
| **Não dá para criar intenções próprias** na análise de intenção da IA | 251 |
| Campo obrigatório **não funciona dentro de condicional** (e o lead se perde) | 42 |
| **Não é possível editar/excluir fluxo** enquanto roda um teste A/B | 28 |
| Lead scoring **não recalcula histórico** | 105 |
| Acionador CSS aceita **apenas uma classe**, com limite de caracteres | 312 |
| Analytics de WhatsApp **só tem dados se a Roleta estiver ativa** | 115 |
| Rastreio de origem no WhatsApp **só para clientes da WhatsApp Suite** | 383 |
| Click to WhatsApp (Meta) ainda **em beta** | 398 |
| Mensagem direta ao WhatsApp: **sem solução de atribuição** | 398 |
| **Não é possível editar** uma programação de relatório automático | 405 |
| Exportação limitada a **1 ano** de período | 234 |
| Espanhol **apenas para scripts e chamadas**, não para a plataforma | 236 |
| Chat em botão: *"exige desenvolvimento técnico de sua equipe, **não realizamos a instalação**"* | 46, 210 |
| RD Station **CRM** não tem integração nativa (só Marketing) | 20 |
| Coexistence: 11 limitações listadas | 376 |
| Campanhas **não geram histórico individual** até o contato responder | 344 |

**[FATO]** Artigos ainda **"Em construção 🚧"**: 396 (adicionar atendentes na
caixa de entrada), 305 (criar caixa de entrada do chat realtime — corpo vazio),
50 (segundo vídeo de múltiplas condicionais). Artigos 39 e 109 retornaram corpo
vazio.

**[INFERÊNCIA]** Os artigos vazios/em construção concentram-se justamente na
**área nova (Live Chat / realtime / WhatsApp Suite)** — mais uma confirmação de
que essa parte está em rollout e não está madura.

### 13.5 Onde o produto é genuinamente fraco

**[INFERÊNCIA]** Consolidando fatos e reviews:

1. **Sem SDK/API para desenvolvedor.** Não há documentação pública de API REST
   para criar fluxos, ler leads ou automatizar a plataforma. A única "API" é a
   `window.neurolead.open()`. Reclamação explícita no AppSumo.
2. **Editor linear limita fluxos complexos.** Ótimo para o caso simples; teto
   baixo para o caso avançado (queixa de "limitações no direcionamento
   condicional").
3. **BI raso.** Reclamação recorrente. Não há funil customizável nem coorte;
   o Analytics é por fluxo e a exportação é `.xlsx` por e-mail.
4. **Bundle pesado** (~445 KB não-comprimido) sem Shadow DOM.
5. **Cancelamento com atrito** e cobrança recorrente sem self-service pleno.
6. **Preço percebido como alto** para o valor entregue no Starter.

---

## 14. Síntese: o que a Leadster realmente vende

**[INFERÊNCIA — leitura estratégica consolidada]**

A Leadster **não vende um chatbot**. Vende três coisas empacotadas, e o software
é a menos importante das três:

**1) Uma metodologia com nome próprio.** "Marketing Conversacional" é uma
categoria importada da Drift e reancorada no Brasil. O cliente não compra
"um widget"; compra "a forma certa de captar lead". A KB inteira é escrita nesse
tom: cada tutorial técnico vem embrulhado numa aula de conversão (arts. 13, 14,
88, 93, 95 são **videoaulas**, não tutoriais).

**2) O benchmark do mercado brasileiro.** O Panorama é o ativo mais defensável
que eles têm. É gerado de graça pela própria operação (dado que já existe no
banco), custa quase nada para produzir, gera imprensa espontânea todo ano, e
transforma cada conversa de vendas num diagnóstico: *"seu setor converte 3,07%;
você está em 1,8%"*. **Nenhum concorrente brasileiro tem isso.**

**3) Um software competente, não excepcional.** O widget é sólido, muito bem
adaptado ao Brasil (CPF/CNPJ/CEP/UF, WhatsApp, roleta, horário) e tem uma jóia
técnica real (CAPI + advanced matching). Mas é um bundle antigo, de marca antiga,
sem SDK, sem canvas e com BI raso. E a plataforma de atendimento **não é deles —
é Chatwoot 4.5.2**.

**A conclusão que interessa:** a barreira de entrada contra a Leadster **não é
tecnológica**. É **narrativa e de dado**. Quem tiver a plataforma (temos, e mais
nova) precisa construir (a) a camada de captura web e (b) o benchmark
proprietário.

---

## 15. IMPLICAÇÕES PARA O CHATSPX

> Apenas recomendações. Nenhuma linha de código, nenhuma implementação.
> Ordenadas por **impacto ÷ esforço**.

### 15.1 O reenquadramento estratégico (leia isto primeiro)

**A descoberta da seção 7 muda a pergunta.** A pergunta não é mais *"como
construímos algo do tamanho da Leadster?"*. É *"por que estamos atrás de um
concorrente que roda o mesmo motor que nós, em versão mais velha?"*.

| | Leadster | ChatSPX |
|---|---|---|
| Plataforma de atendimento | Chatwoot **4.5.2** | Chatwoot **4.12.1** ✅ |
| Live chat no site | Chatwoot widget (rollout manual, plano Full) | Já temos ✅ |
| CSAT, SLA, Automações, Campanhas, Labels, Canned, Custom Attributes, Custom Roles | Chatwoot | Já temos ✅ |
| Agente de IA | Leadster AI (RAG, GPT) | Captain ✅ |
| **Widget de captura conversacional para site** | **`neurolead` (proprietário)** | **❌ NÃO TEMOS** |
| **Benchmark anual do mercado** | **Panorama (5 edições)** | **❌ NÃO TEMOS** |
| **Metodologia com nome** | **Marketing Conversacional** | **❌ NÃO TEMOS** |

**Recomendação 0 — a mais importante:** tratar o gap como sendo de **duas peças
específicas** (widget de captura + narrativa/benchmark), não como um gap de
plataforma. Isso reduz drasticamente o escopo do problema.

### 15.2 Produto: o widget de captura conversacional

O Chatwoot já tem um widget web (`packs/widget`), mas ele é um **widget de
suporte** (abrir conversa com um atendente), não um **widget de captura**
(conduzir um fluxo de perguntas até virar um lead qualificado). São produtos
diferentes com a mesma casca.

**R1 — Modo "fluxo de captura" no widget existente. [alto impacto / médio esforço]**
Aproveitar a casca do widget do Chatwoot e adicionar um modo em que, antes (ou em
vez) de abrir conversa com humano, o visitante percorre um fluxo. Ganha-se de
graça: renderização, i18n, tema, posicionamento, persistência, realtime.

**R2 — Editor em 3 etapas, não canvas. [alto impacto / baixo esforço]**
A Leadster testou e escolheu wizard linear. Copiar essa decisão: *Público →
Perguntas → Integrações*. Canvas é bonito em demo e caro em manutenção; wizard
entrega "time to first lead" em minutos. Ramificação por bloco condicional
aninhado.

**R3 — Máscaras brasileiras como prioridade zero. [alto impacto / baixo esforço]**
CPF, CNPJ, CPF-ou-CNPJ, CEP, UF (menu), UF+Cidade em cascata, telefone BR (DDD+9),
telefone internacional com pré-seleção de DDI, e-mail corporativo (bloqueia
domínios gratuitos), moeda BRL, data, hora, aniversário. **Mais a "validação
restrita"** (bloquear `111111111` e blocos repetidos). Isto é barato de fazer e é
literalmente o fosso que separa produto brasileiro de produto importado. Já temos
`state_cities`-equivalente disponível publicamente (IBGE).

**R4 — Lead incompleto com sync incremental. [alto impacto / médio esforço]**
Copiar a arquitetura revelada pelo endpoint `/lead/{guid}/sync`: **criar o
registro na primeira resposta e atualizar a cada bloco**, gravando `created_at`
por resposta. Isso dá de graça: (a) captura de abandono, (b) o gráfico de
**Dropout** por etapa, (c) medição de tempo entre perguntas. É o alicerce de todo
o analytics de conversão — sem isso, não há como provar ROI ao cliente.

**R5 — Os 7 acionadores, com até 3 simultâneos e config separada por device.
[alto impacto / baixo-médio esforço]**
Tempo na tela, inatividade, scroll %, nº de cliques, clique em seletor CSS,
nº de páginas, exit intent. Mais controle de frequência ("uma vez a cada N dias").
E os 4 formatos: padrão, padrão focalizado (escurece o fundo), pop-up, tela cheia.
**Nota de qualidade:** onde a Leadster aceita só uma classe CSS, aceitar
**seletor CSS completo** — supera o concorrente com esforço marginal.

**R6 — Handoff para WhatsApp de primeira classe. [altíssimo impacto / baixo esforço]**
O dado é definitivo: **+0,54 p.p. de conversão (+20% relativo)** e **76% de
adoção**. Bloco com: mensagem de introdução, número, horário/dias de atendimento,
mensagem pré-preenchida **com variáveis do fluxo**, abertura automática opcional,
e **roleta de N números**. A Leadster limita a 12 e cobra no plano mais caro —
espaço óbvio para superar.

**R7 — Página de captura hospedada. [alto impacto / baixo esforço]**
Mesmo fluxo, em tela cheia, com URL própria, sem precisar instalar em site nenhum.
Distribuível por WhatsApp, bio do Instagram, QR code. ROI enorme pelo esforço.

**R8 — Segmentação por página e campanha (8 regras, AND/OR). [médio/baixo]**
Contém/não contém URL, domínio contém/não contém, é home, origem Google Ads,
origem Meta Ads, parâmetro de URL. Multi-domínio com o mesmo script.

**R9 — Fluxo e design separados por mobile e desktop. [médio impacto / médio esforço]**
Justificado pelo dado: 74,4% do tráfego é mobile e converte pior. Recomendação
editorial embutida no produto (mobile = curto e direto).

**R10 — A/B test simples. [médio impacto / médio esforço]**
Split 50/50 em chamada, avatar e pergunta. **Melhorar o concorrente:** mostrar
significância estatística em vez de "aguarde 5.000 visualizações", e **permitir
editar o fluxo durante o teste** (limitação declarada deles).

### 15.3 Mensuração — onde está o diferencial técnico real

**R11 — Conversions API server-side (Meta CAPI + GA4 Measurement Protocol) com
advanced matching. [altíssimo impacto / alto esforço]**
Este é **o recurso mais valioso do arsenal da Leadster** e o menos visível.
Mapear nome, e-mail, telefone, cidade, estado coletados no fluxo para os campos
de matching. Resolve perda de sinal por ITP/bloqueio de cookies. É o que faz o
cliente de mídia paga ficar dependente. Credenciais necessárias:
Meta (Pixel + token OAuth) e GA4 (Measurement ID + API Secret).

**R12 — Captura e propagação universal de identificadores de campanha.
[alto impacto / baixo esforço]**
5 UTMs + `gclid` + `fbclid` + `lclid` (+ considerar `msclkid`, `ttclid`),
persistidos na sessão e **anexados ao contato/conversa** e a **todo webhook e
integração**. É pré-requisito de tudo em atribuição.

**R13 — Atribuição de origem no WhatsApp, incluindo Click-to-WhatsApp.
[alto impacto / médio esforço]**
Reproduzir a matriz de 4 cenários do art. 398 — e **ganhar no cenário 3**: a
Leadster ainda tem Click-to-WhatsApp da Meta **em beta**. É uma janela aberta.

**R14 — Dropout por etapa como métrica de primeira classe. [alto impacto / baixo esforço]**
Gráfico mostrando exatamente em qual pergunta o visitante desiste. É a métrica
que transforma o produto em ferramenta de otimização e não só de captura.

**R15 — Relatório de "páginas mais acessadas × conversão × tem fluxo?" com CTA de
criação. [alto impacto / baixo esforço]**
Copiar direto do art. 265. É um **motor de ativação embutido no produto**: mostra
ao cliente a página com muito tráfego e sem fluxo, e oferece criar. Brilhante e
barato.

**R16 — Dead-letter queue de integrações com UI. [médio impacto / baixo esforço]**
"Eventos recentes com erro" + reenvio individual/em massa + relatório por e-mail
(1/7/30 dias). Barato, e evita a pior experiência possível: perder lead de cliente
em silêncio.

### 15.4 IA

**R17 — Reposicionar o Captain como "agente de captura", não só de suporte.
[alto impacto / médio esforço]**
Os 3 comportamentos da Leadster (qualificar leads / atender visitante /
e-commerce) são presets de prompt, não tecnologia. Já temos o motor.

**R18 — Ingestão por sitemap XML e seleção múltipla de páginas.
[médio impacto / baixo esforço]**
A Leadster aceita sitemap inteiro, múltiplas URLs selecionáveis, e
`.pdf/.doc/.docx/.odt/.txt` até 10 MB. Vale igualar o mínimo.

**R19 — Análise de intenção — e permitir intenções customizadas.
[alto impacto / médio esforço]**
A IA detecta intenção e desvia o fluxo. A Leadster **não permite criar intenções
próprias** e admite isso na documentação. É a lacuna mais explícita e mais fácil
de superar de todo o produto deles.

**R20 — Regras de follow-up (FUP) configuráveis. [médio impacto / médio esforço]**
Eles usam 5min / 1h / 4h, corte às 21h, retomada às 9h do dia útil, domingo
desligado, e disparo imediato se um humano assume. É um bom default. **Superar:
tornar configurável** em vez de fixo.

**R21 — Botão "falar com humano" em toda resposta da IA. [baixo esforço]**
Regra da Leadster: aparece se o bloco de IA não for o último. Simples e correto.

### 15.5 Marketing, dado e narrativa (onde está o maior ROI)

**R22 — Publicar um "Panorama" próprio. [altíssimo impacto / médio esforço]**
**Esta é a recomendação de maior retorno de todo o documento.**
Já temos os dados dentro do banco de todas as VMs da frota (conversas, tempo de
resposta, primeira resposta, resolução, canal, horário, taxa de atendimento fora
do horário comercial). A Leadster publica conversão de site; nós podemos publicar
**o benchmark de atendimento conversacional do Brasil**: tempo médio de primeira
resposta por setor, % de conversas fora do horário comercial, taxa de resolução
por canal, impacto de IA no tempo de resposta, CSAT por setor. **Ninguém tem esse
dado publicado no Brasil.** Requisitos inegociáveis: agregação, anonimização,
consentimento contratual, metodologia publicada.

**R23 — Nomear uma metodologia. [alto impacto / baixo esforço]**
A Drift criou "Conversational Marketing"; a Leadster importou. Categoria se cria,
não se descobre. Um nome próprio para o que fazemos (captura + atendimento +
IA num só motor) vale mais que dez features.

**R24 — Otimizar para LLM (GEO) desde já. [alto impacto / baixo esforço]**
`robots.txt` com allow explícito para GPTBot, ChatGPT-User, OAI-SearchBot,
PerplexityBot, anthropic-ai, Claude-Web, Google-Extended, Applebot-Extended.
Conteúdo estruturado em FAQ. CTAs que abrem os assistentes com prompt
pré-preenchido. **Justificativa dura:** pelo dado da própria Leadster, tráfego de
IA generativa converte **7,80%** — mais que o dobro do Google Ads.

**R25 — Comparativos "X vs ChatSPX". [médio impacto / baixo esforço]**
Eles têm `/formularios-vs-leadster/`, `/chatbot-vs-leadster/`,
`/botao-do-whatsapp-vs-leadster/`, `/chat-online-vs-leadster/`. É SEO de fundo de
funil, barato e converte. Faltaria só ser factualmente honesto — o que, no nosso
caso, é fácil, porque a comparação técnica nos favorece.

**R26 — Documentação como produto. [médio impacto / médio esforço]**
202 artigos com vídeo, exemplos reais, limitações declaradas e boas práticas. A KB
deles é uma **peça de vendas e de retenção**, não um custo de suporte. Copiar o
padrão do art. 398 (documentação que explica um problema técnico real e conclui
recomendando a solução própria).

### 15.6 O que NÃO copiar

**N1 — Promessas percentuais sem metodologia.** "+316% de leads" é indefensável.
Publicar dado agregado com metodologia é melhor comercialmente e não cria passivo.

**N2 — Campo obrigatório dentro de condicional descartando lead em silêncio.**
Bug de design que eles documentam em vez de corrigir. Validar no editor.

**N3 — Travar o fluxo durante teste A/B.**

**N4 — Lead scoring sem recálculo retroativo.**

**N5 — Cancelamento sem self-service.** Aparece nas reclamações públicas.

**N6 — Bundle monolítico de ~445 KB sem Shadow DOM.** Fazer code splitting por
recurso e isolar estilos de verdade.

**N7 — Módulos de cliente hospedados em CDN pública e listável.** O bucket
`neuro-cdn` expõe `imobille.js`, `jornaldocarro.js`, `kontaazul.js`, `moving.js`
para qualquer um. Customização por cliente deve ser dado, não arquivo público.

**N8 — Deixar rastro de marca antiga no produto.** `neurolead`, `Neurologic`,
`leads@neurologic.com.br` em payload de 2026. Se o ChatSPX renomear algo, migrar
de verdade.

### 15.7 Sequenciamento sugerido

| Onda | Itens | Racional |
|---|---|---|
| **1 — Fundação de dado** | R12, R14, R4, R16 | Sem captura de UTM/clid, lead incompleto e dropout, nada mais se mede. Barato. |
| **2 — Widget mínimo viável** | R1, R2, R3, R6, R7 | O menor produto que já compete: fluxo + máscaras BR + WhatsApp + página hospedada. |
| **3 — Conversão** | R5, R8, R9, R15, R10 | Acionadores, segmentação, device, motor de ativação, A/B. |
| **4 — Diferenciação** | R11, R13, R17, R19 | CAPI server-side, atribuição WhatsApp, IA de captura com intenções customizáveis. |
| **5 — Narrativa** | **R22**, R23, R24, R25, R26 | Pode e deve começar **em paralelo à onda 1** — não depende de código. |

**Observação final:** a onda 5 (R22 — o Panorama) é a única recomendação deste
documento que **não depende de nenhuma linha de código** e é, ao mesmo tempo, a
de maior retorno estratégico. Se apenas uma coisa for feita a partir deste
estudo, que seja essa.

---

## ANEXO A — Índice completo dos 202 artigos da base de conhecimento

**[FATO]** Extraído de `https://help.leadster.com.br/sitemap.xml` em 11/08/2026.
Formato: `{id}-{slug}`. Serve como mapa da superfície funcional do produto.

### A.1 Fluxo, editor e conversão (produto core)

```
13-como-faco-para-meu-cliente-responder-as-perguntas-ate-o-final
14-como-criar-chamadas-com-altas-taxas-de-conversao
26-meus-leads-estao-chegando-sem-o-nome-da-pergunta
28-como-criar-um-teste-a-b
29-como-editar-as-perguntas-do-fluxo-na-leadster
33-como-configurar-as-regras-de-pagina
38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente
39-como-utilizar-variaveis-de-resposta-do-usuario-no-fluxo        [corpo vazio]
40-como-adicionar-links-no-fluxo
47-como-configurar-as-chamadas-inteligentes
50-como-criar-condicionais
51-como-adicionar-politica-de-privacidade-lgpd
60-como-usar-parametros-de-url
64-como-alterar-o-posicionamento-de-meu-assistente-para-evitar-conflitos-com-elementos-do-site
75-novo-editor-de-fluxo-da-leadster
77-como-utilizar-a-funcao-de-campos-obrigatorios-e-descartar-leads
79-como-utilizar-o-assistente-como-pagina-de-captura
83-como-utilizar-as-funcionalidades-de-horario-de-atendimento-e-roleta-de-whatsapp
84-como-configurar-a-personalizacao-de-fluxos-por-device-desktop-mobile
88-como-usar-a-leadster-para-qualificar-seus-leads-de-forma-automatica
92-como-configurar-a-chamada-de-conversao
93-como-gerar-mais-leads-com-chamadas-inteligentes
95-como-conversar-de-forma-relevante-de-acordo-com-o-dispositivos-desktop-mobile
100-como-editar-o-idioma-do-assistente
102-quais-as-possibilidades-de-personalizacao-do-meu-fluxo
105-como-usar-a-funcao-de-qualificacao-de-leads
117-como-descartar-leads-desqualificados-utilizando-condicionais
124-funcoes-dos-campos-customizados
128-como-melhorar-as-conversoes-utilizando-as-chamadas-geradas-pela-inteligencia-artificial
129-como-adicionar-um-redirecionamento-de-link-ao-fluxo
231-como-configurar-o-campo-lista-de-opcoes
248-chamadas-com-ai
250-como-configurar-o-bloco-de-envio-de-eventos
252-como-encerrar-o-fluxo-em-uma-condicional
263-como-configurar-os-novos-acionadores-do-chat-da-leadster
265-paginas-mais-acessadas
306-mascaras-de-resposta-como-configurar
312-como-configurar-o-acionador-por-css-no-chat-da-leadster
371-como-configurar-variaveis-personalizadas-em-seu-fluxo
384-como-configurar-o-bloco-de-envio-avancado-de-parametros-api
```

### A.2 Implementação e instalação

```
17-onde-encontro-o-codigo-de-implementacao-da-ferramenta
23-como-instalar-o-codigo-da-ferramenta-no-wordpress
25-como-instalar-a-ferramenta-pelo-google-tag-manager
27-como-instalar-a-ferramenta-no-wix
36-instrucoes-para-ativar-o-chat
37-instalar-o-codigo-via-html
41-o-que-fazer-quando-meu-assisitente-nao-esta-sendo-exibido-no-site
46-como-inserir-o-chat-em-um-botao-popup-no-seu-site
56-como-instalar-o-assistente-dentro-de-lps-do-rdstation
118-como-inserir-o-chat-em-um-botao-dentro-de-uma-lp-do-rdstation
210-como-inserir-o-chat-em-um-botao-no-wordpress
304-primeiros-passos
```

### A.3 Leads, dashboard e relatórios

```
30-como-alterar-o-assunto-do-e-mail
42-o-que-fazer-quando-nao-estou-recebendo-os-leads
49-como-desativar-relatorios-semanais
78-entenda-a-diferenca-de-leads-completos-e-incompletos
101-como-funciona-a-aba-de-leads-da-minha-dashboard
104-principais-funcoes-da-dashboard
107-para-onde-vao-os-leads-gerados-na-leadster
115-como-utilizar-a-tela-de-analytics-da-leadster
119-adicionar-ou-remover-e-mails-de-recebimento-dos-leads
234-como-exportar-o-relatorio-de-leads
246-leadster-reportei
405-como-configurar-relatorios-automaticos
```

### A.4 Integrações

```
20-como-integrar-a-ferramenta-ao-rdstation
24-como-integro-minhas-plataformas-com-a-neurologic-utilizando-o-zapier
44-o-que-fazer-quando-meus-leads-nao-estao-sendo-registrados-no-rd
57-como-integrar-a-neurologic-ao-crm-piperun
58-como-configurar-uma-integracao-via-webhook
59-como-integrar-a-neurologic-ao-jivochat
61-como-integrar-neurologic-a-exact-sales
62-como-enviar-dados-do-lead-para-o-whatsapp
66-como-personalizar-seu-indentificador-na-integracao-com-rd-station
76-como-integrar-a-leadster-ao-hubspot
81-como-integrar-a-leadster-ao-active-campaign
82-com-quais-plataformas-consigo-integrar-a-leadster
86-como-integrar-a-leadster-com-outras-ferramentas-atraves-do-pluga
87-como-integrar-a-leadster-com-a-praedium
89-como-integrar-a-leadster-a-plataforma-lahar
90-como-integrar-a-leadster-com-a-fleeg
91-como-integrar-a-leadster-ao-sirena
109-como-integrar-a-leadster-ao-bitrix24                          [corpo vazio]
111-como-integrar-a-leadster-ao-salesforce
112-como-utilizar-a-funcao-do-google-calendar-na-leadster
120-como-configurar-os-eventos-do-pixel-da-meta-e-o-ga4-de-maneira-automatizada
122-como-configurar-o-google-analytics-para-enviar-eventos-de-conversoes
211-como-configurar-o-google-analytics-como-conversao-no-google-ads
226-como-integrar-a-leadster-ao-albato
229-como-integrar-a-leadster-ao-google-sheets
262-integracao-leadster-x-followise-dealerspace
267-como-enviar-o-identificador-de-campanhas-na-integracao
308-como-enviar-um-relatorio-de-erro-de-integracao
309-como-reenviar-os-leads-com-erro-na-integracao
377-ajuste-no-google-workspace-para-evitar-perda-de-acesso-ao-google-calendar
402-como-integrar-a-leadster-ao-contact2sales
408-com-integrar-a-leadster-ao-zoho
409-como-enviar-conversoes-da-leadster-ao-chatgpt-ads
```

### A.5 IA (Assistente AI e ShopBot)

```
220-aprenda-como-produzir-um-conteudo-de-ia
221-como-o-assistente-ai-ajuda-no-seu-processo-de-geracao-de-leads
223-como-configurar-o-bloco-de-ai-no-seu-fluxo
232-como-corrigir-erro-na-pagina-de-chamadas-com-ai
245-como-utilizar-o-analytics-do-assistente-ai
251-como-adicionar-condicionais-de-intencao-leadster-ia
257-conversa-por-ia
271-como-integrar-com-woocomerce
272-como-integrar-com-a-tray
273-como-integrar-com-a-nuvem-shop
274-como-integrar-shopbot-a-vtex
275-como-integrar-com-a-loja-integrada
276-como-integracao-a-megazord
277-como-integrar-com-wbuy
278-como-integrar-com-a-bagy
280-como-integrar-com-a-shopify
283-como-verificar-o-historico-de-mensagens-da-ia
284-como-utilizar-o-botao-de-encerramento-da-ia
285-como-configurar-a-ia-para-shopbot
286-como-adicionar-ou-substituir-conteudo-na-base-de-conhecimento-na-ia
287-como-subir-meus-produtos-na-shopbot-em-xml-google-shopping
380-erro-monitoramento-de-vendas-shopbot
390-como-criar-uma-mensagem-de-transbordo-para-evitar-perguntas-repetidas-da-ia
```

### A.6 WhatsApp Suite / Live Chat / atendimento (a camada Chatwoot)

```
305-como-criar-uma-caixa-de-entrada-do-chat-realtime               [corpo vazio]
319-como-cadastrar-agente-no-whatsapp-suite
320-como-criar-um-time-na-whatsapp-suite
322-como-criar-etiquetas
323-como-configurar-resposta-prontas
324-oque-e-e-como-configurar-o-csat
325-como-configurar-sla
326-como-configurar-uma-automacao-no-whatsapp-suite
328-como-aumentar-a-entrega-de-mensagens-com-templates-de-utilidade
329-modelos-de-mensagem-classificados-como-utilidade-pelo-whatsapp
330-whatsapp-leadster
333-como-responder-e-gerenciar-as-conversas
334-como-exportar-relatorios-no-whatsapp-suite
339-integracoes-no-whatsapp-suite-visao-geral-das-ferramentas
340-adicionar-usuario-na-sua-conta-da-meta-business
341-configurar-disparo-de-mensagem-automatica-para-novo-lead-no-rd-station
342-como-enviar-um-template-quando-a-janela-de-24h-expira-no-whatsapp-suite
343-como-ativar-notificacoes-no-whatsapp-suite
344-como-disparar-campanhas-em-massa-via-whatsapp-na-leadster
346-como-importar-contatos-na-leadster
349-leadster-live-chat
350-como-ativar-horario-comercial-e-mensagem-de-ausencia-no-whatsapp-suite
352-como-aplicar-o-sla-na-caixa-de-entrada
353-como-atribuir-um-agente-na-conversa
354-como-enviar-uma-resposta-pronta-na-conversa
355-como-atribuir-uma-etiqueta-na-conversa
356-como-encerrar-uma-conversa-status-da-conversa
357-erro-63016-mensagem-fora-da-janela-de-24h
358-erro-63032-restricao-do-whatsapp-experimento-da-meta
359-erro-63024-destinatario-invalido-no-whatsapp
360-erro-63049-mensagem-de-marketing-bloqueada-pela-meta
362-perfil-administrador-e-agente-whatsapp-suite
363-como-configurar-o-gerenciamento-de-disparo-de-eventos-de-marketing-meta-ads
365-erro-131049
366-como-iniciar-um-contato-no-whatsapp-suite
368-como-adicionar-um-contato-no-whatsapp-suite
369-como-configurar-funcoes-personalizadas
370-regras-de-fup-do-sdr-ia-e-disparo-de-integracoes
372-como-configurar-atributos-personalizados
373-como-adicionar-etiquetas-em-massa
374-como-exportar-conversas
375-como-configurar-o-gerenciamento-de-disparo-de-eventos-de-marketing-ga4
376-limitacoes-e-consideracoes-do-whatsapp-coexistence
379-como-criar-templates-de-whatsapp
381-como-criar-um-template-com-imagem
382-como-criar-fluxos-de-disparos-via-whatsapp-na-leadster
383-como-rastrear-a-origem-do-redirecionamento-para-o-whatsapp
385-erro-de-visualizacao-de-mensagem-na-plataforma
386-como-configurar-variaveis-nos-templates-de-whatsapp
387-como-reconectar-um-numero-apos-desconexao-no-modo-coexistence
389-como-ativar-ou-desativar-o-agente-de-acordo-com-o-horario-comercial
391-erro-131042-business-eligibility-payment-issue
392-como-personalizar-o-fluxo-de-conversa-de-acordo-com-a-mensagem-inicial-no-whatsapp
393-conversa-unica-como-funciona-e-quando-usar
395-erro-numero-nao-esta-no-formato-correto
396-como-adicionar-os-atendentes-na-caixa-de-entrada                [em construção]
397-como-criar-um-template-com-botao
398-como-identificar-a-origem-das-suas-conversoes-no-whatsapp
400-como-adicionar-um-agente-a-caixa-de-entrada
401-como-configurar-o-messenger-como-caixa-de-entrada
403-como-reconectar-uma-caixa-de-entrada-de-e-mail
404-como-configurar-o-tracking-de-dados-do-whatsapp
406-como-disparar-um-flow-de-whatsapp-a-partir-de-um-webhook
407-como-configurar-o-link-de-redirecionamento-whatsapp-suite
```

### A.7 Conta, planos e institucional

```
35-como-alterar-minha-senha-ou-e-mail-de-acesso
48-como-funciona-o-teste-gratis
67-conheca-nossos-planos
68-como-alterar-o-plano
69-neurologic-agora-e-leadster
73-como-acessar-as-informacoes-de-pagamento-da-minha-conta
74-como-habilitar-a-autenticacao-em-dois-fatores
99-como-habilitar-novos-acessos
103-nosso-produto
204-como-funciona-o-cancelamento
236-como-alterar-o-idioma-da-plataforma
239-como-remover-a-logotipo-da-leadster-appsumo
241-como-funciona-o-plano-gratuito
242-como-funciona-o-plano-starter
243-como-funciona-o-plano-pro
244-como-funciona-o-plano-full
313-como-funciona-o-programa-de-indicacao-da-leadster
```

---

## ANEXO B — Endpoints e globais do widget (referência rápida)

**[FATO]** Consolidado da seção 6.

```
# Instalação
CDN loader   : https://cdn.leadster.com.br/neurolead/neurolead.min.js  (456.101 B)
App legado   : https://cdn.leadster.com.br/app/client/scripts.min.js   (288.008 B)
Config global: window.neuroleadId = "<IDENTIFICADOR>"

# Base da API (montada no bundle)
mn = `${origin}/api/chatbot`
origin ∈ { https://app.leadster.com.br,   # BR
           https://app.getleadster.com,   # internacional
           https://qa.leadster.com.br,    # QA
           http://localhost }             # dev

# Endpoints
POST  ${API}/leads
POST  ${API}/lead/{guid}/sync
POST  ${API}/events
GET   ${API}/scripts/search
GET   ${API}/script_versions/{scriptVersionId}/notifications/random
POST  ${API}/users/check-email
      /script-blocks/whatsapp-phone
      /tracking

# Página de captura hospedada
https://app.leadster.com.br/capture
https://app.getleadster.com/capture

# Assets públicos
https://cdn.leadster.com.br/leadster/state_cities.json
https://cdn.leadster.com.br/leadster/app/image/flags.png
https://cdn.leadster.com.br/neurolead/img/{avatar,restart_chat,wpp_logo}.png
https://cdn.leadster.com.br/app/modules/{imobille,jornaldocarro,kontaazul,moving,
                                         ibge_localidades,postmon,autoclose,redirect}.js

# API pública JS
window.neurolead.open()
window.neurolead.send
window.neurolead._trackEvent
window.neurolead.dataQueue
window.neurolead.corsToken
window.neurolead.elChatbot.remove
window.neuroleadCompanyId / ScriptId / DefaultScript / PSId / Language /
       User / sPreferredVersions / LeadDemoMode / EventDevMode

# Telemetria do visitante
{ category: "mobile"|"desktop", language, screenResolution, operatingSystem }
utm_source, utm_medium, utm_campaign, utm_content, utm_term,
gclid, fbclid, referrer, session_id, guid, device

# Eventos
event: "new_lead"
gtag("event","new_lead") | gtag("event","Leadster",{event_category:"new_lead"})
gtag("event","leadster_ai_interaction") | gtag("event","conversion",{send_to:...})
fbq("track", ...) | fbq("trackSingle", ...)

# Storage
leadster_ai_interaction, leadster_hide_tooltip,
neuroleadsPreferredVersions, neuroleadUser

# CSS
prefixo de classe: nld-*   (sem Shadow DOM identificado)
```

---

## ANEXO C — Fontes

### Primárias (Leadster)
- `https://leadster.com.br/` · `/sobre/` · `/preco/` · `/leadster-ai/` · `/agentes-de-ai/` · `/formularios-vs-leadster/`
- `https://leadster.com.br/sitemap.xml` · `https://leadster.com.br/robots.txt`
- `https://leadster.com.br/blog/panorama-geracao-de-leads-2026/`
- `https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil-2026/`
- `https://leadster.com.br/blog/comparativo-leadster/`
- `https://leadster.com.br/blog/leadster-ai/`
- `https://leadster.com.br/blog/leadster-e-confiavel/`
- `https://leadster.com.br/blog/neurologic-agora-e-leadster/`
- `https://help.leadster.com.br` + `/sitemap.xml` + **202 artigos**
- `https://cdn.leadster.com.br/` (bucket GCS `neuro-cdn`, público e listável)
- `https://atendimento.leadster.com.br/` · `https://chat.leadster.com.br/` · `https://app.leadster.com.br/`
- `https://shopbot.leadster.com.br`
- `https://wordpress.org/plugins/leadster-marketing-conversacional/` + ZIP do plugin

### Imprensa e perfis
- [Exame — aporte de R$ 3,5 milhões](https://exame.com/negocios/startup-de-marketing-conversacional-recebe-r-35-milhoes-em-rodada-liderada-por-ex-alunos-da-fgv/)
- [Startupi — GVAngels e Silver Angels](https://startupi.com.br/leadster-marketing-conversacional-aporte/)
- [Gazz Conecta — startup curitibana](https://gazzconecta.com.br/gazz-conecta/investimentos-e-aportes/leadster-startup-curitibana-marketing-conversacional-levanta-35-milhoes-reais/)
- [E-Commerce Brasil — 3º ano de queda](https://www.ecommercebrasil.com.br/noticias/conversao-de-leads-digitais-cai-pelo-terceiro-ano-consecutivo-no-brasil-aponta-pesquisa)
- [Mundo do Marketing — conversão volta a crescer](https://mundodomarketing.com.br/conversao-de-leads-volta-a-crescer-no-brasil-apos-tres-anos-de-queda)
- [Agendor — Panorama 2025 detalhado](https://www.agendor.com.br/blog/panorama-de-geracao-de-leads-no-brasil/)
- [RD Station — página de integração](https://www.rdstation.com/integracoes/leadster-marketing-conversacional/)

### Reviews
- [Capterra](https://www.capterra.com/p/248283/Leadster/reviews/) · [B2B Stack](https://www.b2bstack.com.br/product/leadster/avaliacoes) · [AppSumo](https://appsumo.com/products/leadster/reviews/) · [Reclame Aqui](https://www.reclameaqui.com.br/empresa/leadster/)

### Contexto da categoria (Drift)
- [Conversational Marketing — David Cancel & Dave Gerhardt (Wiley)](https://www.amazon.com/Conversational-Marketing-Companies-Chatbots-Generate/dp/1119541832)
- [Concurate — como a Drift criou a categoria](https://concurate.com/drift-marketing-strategy-coin-a-new-term/)
- [Lochhead — Dave Gerhardt sobre criação de categoria](https://lochhead.com/029-dave-gerhardt/)

### Interna (ChatSPX, só leitura)
- `config/app.yml` e `package.json` → versão **4.12.1**

---

*Fim do TASK 01. Nenhum arquivo de código foi modificado. Nenhum acesso*
*autenticado foi realizado. Todos os artefatos analisados são públicos.*
