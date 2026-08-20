# TASK 10 — Síntese: gap analysis e mapa de oportunidades do widget de site do ChatSPX

> **Documento de decisão. Estudo puro — nenhuma linha de código foi escrita ou alterada.**
> Data: 11 de agosto de 2026. Base: relatórios 01 a 09 desta mesma pasta.
> Repositório de referência: `/home/chatwoot/chatwoot`, branch `homologacao`, HEAD `ee87f5e799`,
> upstream declarado Chatwoot `v4.12.1` (`config/app.yml`).
> Este é o único arquivo que esta task escreveu. Os relatórios 01–09 não foram modificados.

---

## 0. Como ler este documento

| Marcador | Significado |
|---|---|
| **[F]** | **Fato** trazido de um dos relatórios 01–09, onde já está verificado com fonte primária (URL ou `arquivo:linha`). A referência entre parênteses aponta o relatório e a seção de origem. |
| **[I]** | **Inferência minha**, derivada do cruzamento dos relatórios. Não é afirmação de fonte. |
| **[NV]** | **Não verificado** por nenhum dos relatórios de entrada. Registrado como lacuna, nunca preenchido com chute. |
| **[DIV]** | **Divergência** entre relatórios de entrada. Aponto os dois lados e digo em qual confio mais e por quê. |

Nada aqui foi inventado. Onde os relatórios de origem marcaram algo como não verificado, eu mantive o marcador.
Quando um número aparece sem fonte no texto, é porque está na tabela imediatamente acima ou abaixo dele.

### 0.1 Estado das entradas

Todos os nove relatórios existem e estão completos (verificado: 19.635 linhas, 1,25 MB no total).
Nenhum estava faltando ou truncado. Li os nove antes de escrever.

| Relatório | Linhas | Fonte dominante | Confiabilidade da base |
|---|---:|---|---|
| 01 — Leadster produto | 2.582 | site, KB (202 artigos), sitemaps, plugin WP | Alta — fonte primária pública |
| 02 — Leadster técnico | 2.390 | bundle de produção **e build de debug não minificado** | **Altíssima** — código-fonte original deles |
| 03 — Players globais | 2.763 | docs oficiais + medição em Chromium headless | Alta |
| 04 — Players BR/LATAM | 1.546 | páginas oficiais de preço + assets baixados | Alta, com várias lacunas declaradas |
| 05 — Arquitetura de widgets | 3.011 | especificações, MDN, medições, código local | Alta |
| 06 — UX e conversão | 2.270 | literatura de UX + benchmarks + código local | Média-alta (a seção de conversão é honesta sobre o corpus fraco) |
| 07 — Tracking/Pixel/GA4 | 2.223 | docs oficiais Meta/Google + bundle Leadster | **Altíssima** |
| 08 — IA em chats | 1.232 | páginas oficiais de fornecedores + código local | Alta |
| 09 — Auditoria do nosso widget | 1.618 | leitura direta do repositório + medição de bundle | **Altíssima** |

### 0.2 Divergências entre os relatórios de entrada (obrigatório declarar)

| # | Item | Relatório A | Relatório B | Meu veredito |
|---|---|---|---|---|
| **DIV-1** | Dark mode do ChatSPX | 09 §9: **✅ existe** (`composables/useDarkMode.js`, `light`/`dark`/`auto`); 03 §8.1: ✅ "acima da média" | 06 §7.2: **❌ ChatSPX hoje** | **Vale o 09 e o 03.** O 09 cita o arquivo; o 06 provavelmente olhou só o CSS do SDK. **Temos dark mode.** |
| **DIV-2** | Nº de locales do widget | 09 §2.2: **51 arquivos** de locale (MEDIDO) | 05 §10.1: **55 arquivos** | Diferença de 4 arquivos, sem impacto de decisão. Uso "≈51–55". Vale conferir antes de virar material de venda. |
| **DIV-3** | Peso do grafo crítico do widget | 09 §12: **588.943 B gzip** (2,58 MB cru) | 05 §14.1: **586,9 KB gzip** (9,5 loader + 577,4 app) | Mesma ordem de grandeza; a diferença (~2 KB) é o que cada um incluiu no grafo. **Uso ~587 KB gzip.** |
| **DIV-4** | Conversão por segmento (Leadster) | 01 §3.4: Panorama **2026** — Jurídico 5,42%, Energia 5,33%, Imóveis 1,32% | 06 §10.1: tabela rotulada "dados de 2025" — Telefonia 5,40%, Jurídico 4,45%, Imóveis 1,52% | **Os números do 06 são a edição 2025 (dados de 2024)**, e o rótulo dele está deslocado em uma edição. Uso a série do 01, que bate com a metodologia declarada. |
| **DIV-5** | Adoção de IA em geração de leads no Brasil | 08 §5.3: **6,60%** das empresas | 06 §10.1: "passou de ~4% em 2025" | Compatíveis se lidos como séries diferentes (2025 → 2026). Uso **6,60% (Panorama 2026)**. |
| **DIV-6** | Eventos que o ChatSPX expõe ao site host | 09 §4.5: **7 eventos** (`ready`, `opened`, `closed`, `error`, `on-message`, `on-start-conversation`, `postback`) | 03 §8.0: lista **4** | O 09 é a auditoria direta do repo e enumera arquivo:linha. **São 7.** |
| **DIV-7** | Isolamento do widget da Leadster | 01 §6.4: "não há indício de Shadow DOM; isolamento por prefixo de classe" | 02 §5.1: **verificado** — 0 `attachShadow`, 0 iframes, 239 `!important` | Concordam; o 02 é a versão medida e é a que cito. |

Nenhuma dessas divergências muda uma recomendação deste documento. A **DIV-4** muda um número de material de marketing e por isso está registrada.

---

## Sumário

- [1. Resumo executivo](#1-resumo-executivo)
- [2. Matriz de paridade — 68 capacidades × 4 colunas](#2-matriz-de-paridade--68-capacidades--4-colunas)
- [3. Classificação dos gaps nos quatro baldes](#3-classificação-dos-gaps-nos-quatro-baldes)
- [4. A frente de TRACKING, camada por camada](#4-a-frente-de-tracking-camada-por-camada)
- [5. Roadmap em ondas](#5-roadmap-em-ondas)
- [6. Riscos e armadilhas](#6-riscos-e-armadilhas)
- [7. Perguntas em aberto para o Walisson decidir](#7-perguntas-em-aberto-para-o-walisson-decidir)
- [Anexo A — Rastreabilidade: de onde veio cada bloco](#anexo-a--rastreabilidade-de-onde-veio-cada-bloco)

---

## 1. Resumo executivo

### 1.1 O que o mercado faz

**O widget de chat deixou de ser um canal e virou duas coisas diferentes, vendidas para dois compradores diferentes.**

Para o comprador de **suporte** (Intercom, Zendesk, Gorgias, Ada), o widget virou um **mini-aplicativo**: base de conhecimento, tickets, tours, checklists, pesquisas, notícias — chat é uma aba dentro dele **[F, 03 §0]**. O modelo comercial migrou de assento para **resultado de IA**: Intercom cobra **US$ 0,99 por outcome**, HubSpot **US$ 0,50 por conversa resolvida**, Zendesk verifica a resolução com um LLM antes de faturar **[F, 08 §2, §3]**.

Para o comprador de **marketing** (Leadster, Cliengo, e o cadáver do Drift), o widget é uma **máquina de captura**: fluxo conversacional que substitui o formulário, gatilhos de abertura, teste A/B de chamada, qualificação, lead scoring e — o mais importante e o menos visível — **atribuição de mídia paga ponta a ponta** **[F, 01, 02, 07]**.

Três fatos do mercado brasileiro amarram tudo:

1. **A conversão mediana de site no Brasil é 3,07%** (2.425 sites, 173,6 milhões de acessos, 3,4 milhões de leads), variando de **1,32% em imóveis a 5,42% em jurídico** **[F, 01 §3, Panorama 2026 — https://leadster.com.br/panorama-geracao-de-leads/]**.
2. **75,96% das empresas redirecionam para o WhatsApp**, e quem redireciona converte **+0,54 p.p. (+20% relativo)** **[F, 01 §3.10]**. No Brasil, o widget de site **não é o destino: é a rampa**.
3. **Só 6,60% das empresas brasileiras usam IA em geração de leads** **[F, 08 §5.3]**. O mercado está praticamente virgem.

E um quarto fato, que é o mais estranho e o mais útil: **o tráfego vindo de IA generativa (ChatGPT, Perplexity, Gemini) converte a 7,80%** — mais que o dobro do Google Ads **[F, 01 §3.7]** — embora ainda represente apenas 0,10% do tráfego **[F, 08 §5.3]**.

### 1.2 Onde estamos

O achado central dos relatórios 01 e 02, e o que reposiciona o problema inteiro:

> **A Leadster — o principal concorrente brasileiro deste estudo — roda Chatwoot 4.5.2 como backend de atendimento humano.** Verificado por três provas independentes: `GET https://atendimento.leadster.com.br/api` devolve `{"version":"4.5.2",...}`, o host seta o cookie `_chatwoot_session`, e o `window.globalConfig` do HTML expõe `CHATWOOT_INBOX_TOKEN`, `INSTALLATION_NAME: "Leadster"`, `IS_ENTERPRISE: true`. O widget deles abre `wss://atendimento.leadster.com.br/cable` assinando `RoomChannel` com `pubsub_token` **[F, 02 §7.1–7.2; 01 §7]**.

**Nós estamos 7 minor versions à frente da mesma base (4.12.1 vs 4.5.2) [F, 01 §7.3].** Tudo que a Leadster vende como WhatsApp Suite, Live Chat, CSAT, SLA, Automações, Campanhas, Etiquetas, Respostas prontas, Atributos personalizados e Funções personalizadas **já temos, e mais novo**.

O que eles têm e nós não temos são **duas peças**, não uma plataforma:

1. **Uma camada de captura conversacional no site** (fluxo, gatilhos, A/B, máscaras brasileiras, dropout, lead incompleto).
2. **Uma camada de atribuição de mídia** (UTM/gclid/fbclid persistidos, Pixel/GA4/Ads client-side, CAPI e Measurement Protocol server-side com PII hasheada).

Fora isso, temos vantagens reais e mensuráveis sobre eles: o loader do host pesa **28,8 KB contra 456,1 KB deles — 15,9× mais leve [F, 02 §8.1]**; temos API pública com 14 métodos e 7 eventos contra **um** método e **zero** eventos **[F, 02 §11.1; 09 §4]**; temos verificação de identidade HMAC com escopo de conversa, que eles **não têm** **[F, 02 §11.3]**; e nossa reconexão de WebSocket (backoff exponencial com jitter, watchdog de 15 s, reconexão em `visibilitychange`/`focus`/`pageshow`) está acima da média do mercado, enquanto a deles **desiste após 5 tentativas de 1 segundo** **[F, 05 §14.3]**.

E temos um passivo próprio, que precisa ser dito com todas as letras: **a customização visual do ChatSPX quebrou o `widget_color` por inbox**. O header e o botão de enviar viraram verde `#2dc46f` fixo porque `bg-n-brand` é uma cor literal no CSS gerado, não uma custom property. Resultado: **todo cliente do SaaS tem hoje um widget com a cor dele na bolha e a nossa no cabeçalho** **[F, 09 §13.2 item 3]**. Isso é bug de produto white-label, não detalhe de estilo.

### 1.3 A tese

**[I]** Três frases:

1. **O gap não é de plataforma, é de camada de aquisição.** A Leadster provou isso ao adotar a nossa base. Enquadrar o trabalho como "construir um concorrente da Leadster" superdimensiona o problema em uma ordem de grandeza; o correto é "construir a camada que falta sobre uma base que já é mais forte".
2. **A alavanca de maior valor por esforço é a atribuição, não a interface.** O ChatSPX está sentado sobre exatamente o dado que Meta e Google mais querem — e-mail e telefone validados, com IP, user-agent e desfecho comercial — e hoje **não manda nada**: zero ocorrências de `fbq`, `gtag` ou `dataLayer` em `app/` **[F, 07 §6.2; 09 §11]**. Pior: **a origem já está no banco**, crua, em `conversations.additional_attributes.referer`, e ninguém parseia **[F, 07 §6.1]**.
3. **No Brasil, o concorrente do nosso widget é o botão de WhatsApp, não o Intercom.** A varredura de campo mostra que os grandes sites brasileiros (Magalu, Americanas, Nubank, Locaweb) não expõem widget de chat na home — expõem link de WhatsApp ou formulário RD/HubSpot **[F, 06 §13.2]**. Um widget que trate WhatsApp como destino de primeira classe, costurando identidade e transcript, ocupa um espaço que **nenhum player inspecionado documenta ter ocupado** **[F, 04 §8.2; 05 §9.7]**.

---

## 2. Matriz de paridade — 68 capacidades × 4 colunas

**Legenda:** ✅ tem · 🟡 parcial / com limitação relevante · ❌ não tem · ❔ não verificado nos relatórios de entrada

**Colunas:**
- **Leadster** — o concorrente brasileiro de referência (relatórios 01, 02, 04, 07).
- **Intercom** — o benchmark global de produto (relatório 03).
- **BR** — coluna combinada RD Station Conversas / Octadesk / Huggy; a sigla entre parênteses diz **qual dos três** sustenta a marca (relatório 04).
- **ChatSPX** — nosso estado hoje (relatório 09, auditoria direta do repositório).

### Bloco A — Instalação e integração (1–8)

| # | Capacidade | Leadster | Intercom | BR (RD/Octa/Huggy) | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 1 | Snippet de 1 script colável, com falha silenciosa | ✅ | ✅ | ✅ | ✅ | Nosso snippet vem de `web_widget.rb:64-82`; o deles tem `try/catch` vazio e uma só global (`neuroleadId`) |
| 2 | Stub global síncrono com fila antes do bundle | ✅ | ✅ | ✅ (Huggy `$_Huggy`) | ❌ | 20/20 dos globais fazem; nós só temos API depois do `chatwoot:ready` **[F, 05 §15.2 item 14]** |
| 3 | Instalação documentada em WordPress / Wix / GTM | ✅ (plugin WP oficial, 4.000+ instalações) | ✅ | ✅ | ❔/❌ | Requisito "obrigatório" na lista do mercado BR **[F, 04 §12.1 item 2]** |
| 4 | `baseUrl` configurável / self-host | ❌ (CDN fixo) | ❌ | ❌ | ✅ | Vantagem estrutural nossa **[F, 02 §12.1]** |
| 5 | API JS pública rica no host | 🟡 (1 método: `open()`) | ✅ (22 métodos) | ✅ (Huggy: 26 métodos + 9 eventos) | ✅ (14 métodos) | Ganhamos da Leadster com folga **[F, 02 §11.1]** |
| 6 | Eventos `CustomEvent` no `window` do host | ❌ (zero) | ✅ (4 hooks) | ✅ (Huggy `subscribe`) | ✅ (7 eventos) | **[F, 09 §4.5; 02 §11.1]** |
| 7 | Ponto de montagem customizado no DOM do cliente | ✅ (`#nld-custom-container`) | ✅ (`custom_launcher_selector`) | ✅ (Kommo `mode:'frame'`) | ❌ | Barato e pedido; ver gap **M3** |
| 8 | Modo inline/embutido (não flutuante) | ❌ | ❌ | ✅ (Blip `withTarget`, Kommo `frame`, Zenvia `room`) | ❌ | Habilita "página de contato" e Central de Ajuda embutida |

### Bloco B — Arquitetura, peso e robustez (9–18)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 9 | Isolamento real (iframe ou Shadow DOM) | ❌ (DOM direto + 239 `!important`) | ✅ iframe | 🟡 (Zenvia iframe; Huggy/Octa ❔) | ✅ iframe | **Vantagem nossa. Não abrir mão** |
| 10 | Loader leve (< 40 KB) separado do app | ❌ (monolito 456 KB) | ✅ (3,1 KB) | ❔ | ✅ (28,8 KB / 9,5 KB gz) | **15,9× mais leve que a Leadster no host [F, 02 §8.1]** |
| 11 | App carregado sob demanda (facade / lazy) | ❌ | ✅ | ❔ | ❌ | Carregamos **~587 KB gzip para 100% dos visitantes**, dos quais 3–10% abrem o chat **[F, 05 §15.0]** |
| 12 | CSS enxuto (sem arrastar o app inteiro) | 🟡 (embutido no JS) | ✅ | ❔ | ❌ | **1,10 MB cru / 106 KB gz** — o Tailwind do dashboard inteiro entra no widget **[F, 09 §12]** |
| 13 | Chunks limpos (sem dependência morta) | ❔ | ✅ | ❔ | ❌ | **Leaflet: 150 KB cru / 43 KB gz** no grafo crítico de um widget que nunca mostra mapa **[F, 09 §12]** |
| 14 | Orçamento de bytes vigiado em CI | ❔ | ❔ | ❔ | 🟡 | `size-limit` só vigia o entry de 62 KB; ignora CSS e chunks compartilhados **[F, 09 §12]** |
| 15 | Reconexão realtime robusta | ❌ (1 s fixo, desiste em 5) | ✅ | ❔ | ✅ | Backoff + jitter + `visibilitychange`/`focus`/`pageshow` + watchdog 15 s/25 s **[F, 05 §14.3]** |
| 16 | Retomada de mensagens perdidas | ❌ (nenhuma) | ✅ | ❔ | ✅ | `syncLatestMessages` com `after=<lastMessageId>` **[F, 09 §8]** |
| 17 | Preservação de estado em SPA | ❌ (destrói e remonta) | ✅ | ❔ | 🟡 | Cobrimos Turbo/Turbolinks/Astro; **não** cobrimos React/Vue Router puros **[F, 02 §12.5]** |
| 18 | Fila offline / retry de mensagem | ❔ | ❔ | ❔ | ❌ | `catch` → `status:'failed'` e acabou **[F, 05 §15.2 item 9]** |

### Bloco C — Proatividade e UX de abordagem (19–28)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 19 | Teaser/balão de convite (sem auto-open) | ✅ (com rotação e typing de 2 s) | ✅ | ✅ (JivoChat "convites proativos") | 🟡 | Temos campanha, não teaser com rotação |
| 20 | Gatilho por tempo na página | ✅ | ✅ | ✅ | ✅ | `timeOnPage` na campanha |
| 21 | Gatilho por scroll (%) | ✅ | ❔ | ❔ | ❌ | `PageScroll` deles é 6 linhas **[F, 02 §9.4]** |
| 22 | Gatilho por exit intent | ✅ (`CursorOutside`, 200 ms de confirmação) | ✅ (HubSpot tem) | ❔ | ❌ | |
| 23 | Gatilho por inatividade / nº de cliques / nº de páginas | ✅ (3 gatilhos) | ❔ | ❔ | ❌ | |
| 24 | Gatilho por seletor CSS do site | ✅ (`clicked_at`, 1 classe só) | ✅ (`custom_launcher_selector`) | ❔ | ❌ | Podemos superar aceitando **seletor completo** |
| 25 | Configuração de gatilho **separada** para desktop e mobile | ✅ | ❔ | ❔ | ❌ | Não é toggle: são duas configs independentes **[F, 02 §9.4]** |
| 26 | Controle de frequência / cooldown por gatilho | ✅ (cookie `cooldown_{tipo}_{device}_{scriptId}`) | ❔ | ❔ | 🟡 | Nosso snooze é **global de 1 hora**, não por campanha **[F, 09 §6.6]** |
| 27 | Ocultar após conversão (N dias) | ✅ (7 dias, inclusive para lead descartado) | ❔ | ❔ | 🟡 | Nossa regra é "nunca mais para quem já conversou" — pior dos dois mundos |
| 28 | Esconder o widget quando o teclado virtual abre (mobile) | ✅ (`focusin`) | ❔ | ❔ | ❌ | Detalhe de UX barato e sensível **[F, 02 §9.8]** |

### Bloco D — Captura, qualificação e formulário conversacional (29–40)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 29 | Fluxo conversacional de qualificação no widget | ✅ (o produto é isso) | 🟡 (Fin) | 🟡 (bots) | ❌ | Temos Flows no produto, **não acionável pelo widget web** **[F, 09 §9]** |
| 30 | Editor de fluxo sem canvas (wizard de 3 etapas) | ✅ | — | ❔ | ❌ | Decisão deliberada deles; "ativação em 4 minutos" **[F, 01 §5.1]** |
| 31 | Pre-chat form | ✅ | 🟡 | ✅ | ✅ | Nosso FormKit é bom; **por padrão nenhum campo vem habilitado** **[F, 09 §6.1]** |
| 32 | Pre-chat multi-etapa / campos condicionais | ✅ (condicionais aninhadas) | ❔ | ❔ | ❌ | `pre_chat_form_options` já é jsonb; falta o front |
| 33 | Máscaras/validações BR (CPF, CNPJ, CEP, UF+cidade, tel, e-mail corporativo) | ✅ **(único completo do mercado)** | ❌ | 🟡 (Huggy tem os campos, não a validação de fluxo) | ❌ | Inclui módulos `ibge_localidades.js` e `postmon.js` no CDN deles **[F, 04 §9.2]** |
| 34 | Validação anti-lixo (bloquear `111111111`) | ✅ | ❔ | ❔ | ❌ | |
| 35 | Quick replies / botões no primeiro turno | ✅ | ✅ | ✅ (Cliengo `[[A, B]]`) | 🟡 | Só a partir de mensagem do agente/bot com `content_type` específico **[F, 09 §9]** |
| 36 | Lead incompleto com sync incremental por resposta | ✅ (`/lead/{guid}/sync`) | ❔ | ❔ | ❌ | É o alicerce de todo o analytics de conversão **[F, 01 §6.5]** |
| 37 | Dropout por etapa (onde o visitante desiste) | ✅ | ❔ | ❌ | ❌ | Métrica que transforma o produto em ferramenta de otimização |
| 38 | Lead scoring por resposta | ✅ (`option_scores` no bloco + plano Pro) | ❔ | ❌ | 🟡 | **Temos scoring por LLM** no `ConversationEvalSchema` (`funil`, `interesse`), mas dentro do eval, não exposto **[F, 08 §7.4]** |
| 39 | Teste A/B (chamada, avatar, pergunta) | ✅ (50/50, versionado por mensagem, grude em localStorage) | ❔ | ❌ | ❌ | Eles travam edição durante o teste — dá para superar **[F, 01 §5.9]** |
| 40 | Página de captura hospedada (chat sem site) | ✅ | ❌ | ❌ | ❌ | Custo baixo, ativo distribuível por WhatsApp/bio **[F, 01 §5.12]** |

### Bloco E — Canais, handoff e continuidade (41–46)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 41 | Redirect para WhatsApp com mensagem pré-preenchida | ✅ (com variáveis do fluxo) | ❌ | ✅ (Huggy `openWhatsapp`) | ❌ | **Obrigatório no Brasil** **[F, 04 §12.1 item 11]** |
| 42 | Roleta/distribuição entre N números no redirect | ✅ (até 12, plano Full) | ❌ | ❌ | ❌ | Espaço óbvio para superar |
| 43 | Handoff site→WhatsApp costurando identidade + transcript | ❌ | ❌ | ❌ | ❌ | **Ninguém faz.** É a maior oportunidade aberta **[F, 04 §8.2; 05 §9.7]** |
| 44 | Continuidade entre sessões/dispositivos | 🟡 (localStorage, morre em anônima) | ✅ | ✅ (Zenvia `_zid`, Blip 30 dias) | ✅ | Cookie com `baseDomain` (subdomínios) + HMAC entre dispositivos |
| 45 | Continuidade da conversa por e-mail | ❔ | ✅ | ❔ | ✅ | `continuity_via_email` default `true` — vantagem estrutural **[F, 05 §15.1]** |
| 46 | Base de conhecimento / artigos dentro do widget | ❌ | ✅ (Space "Help") | 🟡 (Huggy `openKnowledgeBase`) | 🟡 | Temos os 6 mais lidos; **não temos busca** **[F, 09 §9]** |

### Bloco F — IA (47–54)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 47 | Agente de IA com RAG sobre base própria | ✅ (URL, sitemap, PDF 10 MB) | ✅ (Fin) | ✅ (Octadesk WOZ) | ✅ | Captain **[F, 08 §11]** |
| 48 | Contextual retrieval + busca híbrida com RRF | ❔ | ❔ | ❌ | ✅ | **Acima da média de mercado** — HNSW + tsvector + RRF k=60 **[F, 08 §4.2–4.3]** |
| 49 | Reranker sobre o resultado | ❔ | provável | ❌ | ❌ | TODO escrito no nosso próprio código; é o degrau de 2,9%→1,9% de falha **[F, 08 §11.7]** |
| 50 | Ingestão por sitemap XML / múltiplas páginas | ✅ | ✅ | ❔ | 🟡 | Temos crawl, PDF e texto colado; falta sitemap e conectores |
| 51 | Análise de intenção com desvio de fluxo | ✅ (**mas não deixa criar intenções próprias**) | ✅ | ❔ | 🟡 | Lacuna declarada por eles — a mais fácil de superar **[F, 01 §4.3]** |
| 52 | Handoff para humano com dossiê, time e distribuição | ❔ | ✅ | 🟡 | ✅ | Idempotente, com nota privada, validação de `team_id` e rodízio **[F, 08 §4.8]** |
| 53 | Guardrail executável / supervisor de saída | ❌ | provável | ❌ | ❌ | **Gap nº 1 da nossa IA** frente a Sierra/Decagon **[F, 08 §11.8]** |
| 54 | Eval/QA de produção como produto para o gestor | ❌ | ✅ | ❌ | 🟡 | **O motor existe** (episódios, 16 categorias, gates determinísticos) e não tem tela **[F, 08 §11.6]** |

### Bloco G — Tracking e atribuição (55–63)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 55 | Captura e persistência de UTM/`gclid`/`fbclid` | ✅ (~40 params em cookies `ll_*`, 30 dias) | 🟡 (aceita UTM em `intercomSettings`) | 🟡 (Huggy tem artigo) | ❌ | **Zero ocorrências** de `utm_`/`gclid`/`fbclid` em `app/` **[F, 09 §11]** |
| 56 | Recriar `_fbc`/`_gcl_aw` como cookie first-party | ✅ | ❌ | ❔ | ❌ | Contorno de ITP; algoritmo de `subdomainIndex` documentado **[F, 07 §2.7]** |
| 57 | Disparo client-side no Meta Pixel | ✅ (`track`, sem `trackSingle`) | ❌ | ❔ | ❌ | Eles vazam evento para todos os pixels da página — dá para fazer melhor **[F, 07 §4.1.3]** |
| 58 | Disparo client-side em GA4 / Google Ads | ✅ (`gtag('event')` + `send_to`) | ✅ (app oficial, 9 eventos) | ❔ | ❌ | |
| 59 | `dataLayer.push` documentado | ✅ (parcial) | ✅ | ❔ | ❌ | 3 issues abertas há 3 anos no upstream pedindo isso **[F, 07 §6.4]** |
| 60 | Meta CAPI server-side com PII hasheada | ✅ (hash no navegador, `credential_id`) | ❌ | 🟡 (RD só em landing pages) | ❌ | **É o diferencial técnico real da Leadster** **[F, 07 §4.1.5]** |
| 61 | GA4 Measurement Protocol + Enhanced Conversions | ✅ (`client_id`+`session_id`+`sha256_*`) | ❌ | ❔ | ❌ | |
| 62 | Deduplicação por `event_id` (Pixel × CAPI) | ❌ | — | ❌ | ❌ | **Ninguém faz — nem a Leadster.** Barato e verificável **[F, 07 §4.10]** |
| 63 | Import de conversão offline (venda → Ads/Meta) | ❔ | ❌ | 🟡 (via CRM) | ❌ | **Espaço em branco do mercado** **[F, 07 §4.10]** |

### Bloco H — Segurança, identidade e conformidade (64–68)

| # | Capacidade | Leadster | Intercom | BR | ChatSPX | Nota curta |
|---:|---|:---:|:---:|:---:|:---:|---|
| 64 | Verificação de identidade do visitante | ❌ (nenhuma) | ✅ JWT HS256 (HMAC deprecado) | 🟡 (Huggy JWT; Octadesk **sem hash**) | ✅ HMAC-SHA256 com escopo | **Vantagem nossa e subutilizada** **[F, 03 §5.3; 02 §11.3]** |
| 65 | Enforcement "só usuários verificados" (toggle) | ❌ | 🟡 (congelado p/ novas contas) | ❌ | 🟡 | Temos `hmac_mandatory`; falta a coexistência clara com anônimo |
| 66 | Restrição de domínio validada no servidor | ❌ (**host ecoado do parâmetro; ACAO `*`**) | ✅ (wildcard) | ❔ | 🟡 | Temos `allowed_domains` → `frame-ancestors`, **mas vazio por padrão** **[F, 05 §15.2 item 3; 02 §11.2]** |
| 67 | Consentimento LGPD dentro do widget | 🟡 (link de política; `consentRequired` default **false**) | ❔ | 🟡 (Zenvia `znv-opt-in`) | ❌ | Gap generalizado do mercado — logo, oportunidade **[F, 04 §9.1]** |
| 68 | Acessibilidade (aria-live, foco, rótulo traduzido) | ❌ (0 `aria-*`, 1 `role`) | ❔ | 🟡 (Zenvia tem `aria-*` no bundle) | ❌ | **2 `aria-label` no widget inteiro**; bolha com `title` em inglês hardcoded **[F, 09 §13.2 item 6]** |

### 2.1 Placar consolidado

**[I]** Contando só as 68 linhas acima, com 🟡 valendo meio ponto:

| Coluna | ✅ | 🟡 | ❌ | ❔ | Leitura |
|---|---:|---:|---:|---:|---|
| **Leadster** | 38 | 5 | 17 | 8 | Forte em captura e atribuição; fraca em arquitetura, segurança e a11y |
| **Intercom** | 27 | 5 | 17 | 19 | Forte em produto e identidade; **não faz Meta Pixel nem WhatsApp** |
| **BR (RD/Octa/Huggy)** | 15 | 12 | 12 | 29 | Widget é item de checklist; muita coisa não é documentada publicamente |
| **ChatSPX** | 22 | 12 | 30 | 4 | Base sólida; **todo o buraco está em captura, atribuição, proatividade e polimento** |

**[I]** O padrão é limpo e conta a história do documento inteiro: **perdemos em quase tudo que o comprador de marketing olha e ganhamos em quase tudo que o engenheiro olha.**

---

## 3. Classificação dos gaps nos quatro baldes

### 3.1 🔴 MESA — todo mundo tem, nós não temos (constrange na venda)

Critério: presente em **4 ou mais** dos players inspecionados, ou explicitamente listado como "obrigatório" pelo relatório 04 §12.1.

| # | Gap | Quem tem | Evidência | Esforço |
|---|---|---|---|:---:|
| **M1** | **Captura de UTM / `gclid` / `fbclid` / referrer / landing page** | Leadster, Cliengo, Huggy, Kommo, JivoChat | 09 §11: busca exaustiva retorna **zero** | **P** |
| **M2** | **Disparo de evento de conversão para o site do cliente** (`dataLayer`, GA4, Pixel) | Leadster, Cliengo, JivoChat (17 eventos), Intercom, Tidio, Drift, HubSpot | 07 §6.2 | **M** |
| **M3** | **Gatilhos de proatividade além de URL+tempo** (scroll, exit intent, inatividade, cliques, nº de páginas, seletor CSS), com config separada por device | Leadster (7 gatilhos), JivoChat, Huggy, Cliengo, Zenvia | 09 §6.6 vs 02 §9.4 | **M** |
| **M4** | **Validação/máscara brasileira no pre-chat** (CPF, CNPJ, CEP, UF+cidade, telefone, e-mail corporativo) | Leadster (única completa); Huggy tem os campos | 04 §12.1 item 7 | **M** |
| **M5** | **`widget_color` funcionando no header e no botão de enviar** | 20/20 dos players | 09 §13.2 item 3 — **regressão nossa** | **P** |
| **M6** | **Peso: app carregado sob demanda** | Intercom, Zendesk, Crisp, Chaport (loader < 5 KB) | 09 §12: 587 KB gz para 100% dos visitantes | **G** |
| **M7** | **Contador de não lidas exposto ao host + eventos `connected`/`disconnected`** | 15/20 dos globais | 03 §8.1 | **P** |
| **M8** | **`open()` / `close()` explícitos e idempotentes** | 20/20 | 03 §8.1 | **P** |
| **M9** | **Primeira mensagem com 2–4 opções nomeadas** (quick replies proativas) | Cliengo, Leadster, Botmaker | 06 §14.4 R24 | **P** |
| **M10** | **Aviso/consentimento LGPD visível antes da coleta** | Zenvia (`znv-opt-in`), Leadster (link), obrigatório por lei | 04 §12.1 item 20 | **M** |
| **M11** | **Acessibilidade mínima** (`aria-live`, foco ao abrir, rótulo traduzido da bolha) | Zenvia, LiveChat | 09 §13.2 item 6 | **M** |
| **M12** | **Persistir posição/tipo/título da bolha no servidor** | todos | 09 §10.2 — hoje só em `localStorage` do dashboard, e o cliente não sabe disso | **P** |
| **M13** | **Analytics do widget** (chats abertos, conversas iniciadas, leads, dropout) | Leadster, JivoChat, Cliengo | 01 §5.14 | **M** |
| **M14** | **Instalação documentada em WordPress / Wix / GTM** | todos | 04 §12.1 item 2 | **P** |
| **M15** | **Stub queue no snippet** (API utilizável antes do bundle carregar) | 20/20 | 05 §15.2 item 14 — "~200 bytes eliminam uma classe inteira de bug" | **P** |

**[I]** Destes 15, **oito são P (pequenos)**. M5 é literalmente uma correção de regressão. M1, M7, M8, M12, M15 são de baixa complexidade e alto retorno em comparativo comercial. **Não fazer os P é escolha, não restrição.**

### 3.2 🟢 DIFERENCIAL — poucos têm, valeria muito para o nosso ICP

| # | Diferencial | Quem tem hoje | Por que vale para nós | Esforço |
|---|---|---|---|:---:|
| **D1** | **CAPI + GA4 Measurement Protocol server-side com credencial por conta** | só a Leadster no Brasil | Recupera os **20–40%** de eventos perdidos por adblock/ITP; o chat é a única superfície do site que coleta e-mail **e** telefone validados, os dois campos de maior peso em EMQ **[F, 07 §2.5]** | **G** |
| **D2** | **Deduplicação por `event_id` entre Pixel e CAPI** | **ninguém**, nem a Leadster | Argumento técnico verificável: "seu Events Manager não conta duas vezes" **[F, 07 §4.10]** | **P** (dado D1) |
| **D3** | **Import de conversão offline** (venda fechada 30 dias depois volta ao Ads com valor real) | **ninguém** no chat brasileiro | Muda a otimização de campanha de volume para receita. Janela do `gclid`: 90 dias **[F, 07 §3.7]** | **G** |
| **D4** | **`ctwa_clid` — atribuição de Click-to-WhatsApp** | Leadster **em beta**; ninguém mais | Resolve a "attribution black hole" do CTWA, que o cliente não consegue resolver sozinho. **Podemos valer mais aqui do que no pixel do site** **[F, 07 §2.10]** | **M** |
| **D5** | **Handoff site→WhatsApp costurando identidade, transcript e origem** | **ninguém documenta** | +20% de conversão relativa é o prêmio do WhatsApp **[F, 01 §3.10]**; o código curto opaco no `?text=` é o mecanismo **[F, 05 §9.7]** | **M** |
| **D6** | **Enforcement de identidade como toggle de 1 clique + JWT sob demanda** | só o Front tem o toggle; Zendesk/Kustomer/Gladly têm o JWT | Já temos `hmac_verified` no banco. Vira argumento de venda para banco, saúde e jurídico **[F, 03 §8.2 D1/D2]** | **M** |
| **D7** | **Contrato de design tokens com validação de contraste** | **ninguém entrega bem** | Resolve N1 do relatório 03 e, de quebra, o nosso bug de contraste do header verde (2,3:1 contra o mínimo AA de 4,5:1) **[F, 09 §16.4 A6]** | **M** |
| **D8** | **QA/eval de IA exposto como produto de gestão** | Decagon (Watchtower), Zendesk QA | **O motor já existe** — episódios, LLM-as-judge com 16 categorias de falha, gates determinísticos no padrão τ-bench **[F, 08 §11.6]**. É a coisa de maior valor/esforço do inventário inteiro | **M** |
| **D9** | **Guardrail executável (gates movidos do eval para o pré-envio)** | Sierra, Decagon | Fecha o gap nº 1 da nossa IA reusando código já testado **[F, 08 §12.1 D3]** | **M** |
| **D10** | **Citação de fonte ligada por padrão no canal web + declaração "sou uma IA" no 1º turno** | Fin, Ada | A flag `feature_citation` **já existe**; é decisão de default por canal. EU AI Act art. 50 em vigor desde 02/08/2026; 95% dos consumidores esperam explicação **[F, 08 §9.4]** | **P** |
| **D11** | **Calendário de feriados brasileiros no horário de atendimento** | Huggy **cobra por isso** em tabela de preço | Lacuna pequena, concreta e vendável **[F, 04 §12.2 R4]** | **P** |
| **D12** | **Página de captura hospedada** | Leadster, Typeform/Landbot | Ativo distribuível por WhatsApp/bio/QR, custo de implementação zero para o cliente **[F, 01 §5.12]** | **M** |
| **D13** | **Benchmark próprio publicado ("Panorama" do atendimento)** | Leadster (5 edições) | **Não depende de código.** Temos o dado na frota: tempo de 1ª resposta por setor, % fora do horário, resolução por canal, impacto da IA **[F, 01 §15.5 R22]** | **M** (não é engenharia) |
| **D14** | **Detectar referrer de IA generativa e mudar a abordagem** | ninguém | Esse tráfego converte a **7,80%** — mais que o dobro do Google Ads **[F, 01 §3.7]** | **P** |
| **D15** | **A/B por mensagem, versionado, com "grude" da variante** | Leadster (com a limitação de travar edição) | Podemos superar: significância estatística real em vez de "aguarde 5.000 visualizações" **[F, 01 §5.9]** | **M** |

### 3.3 ⚪ RUÍDO — o mercado tem, mas não muda jogo para nós

| # | Item | Quem tem | Por que é ruído para o nosso ICP |
|---|---|---|---|
| **N1** | Voice agent full-duplex | Fin Voice, ElevenLabs, Sierra | **75,96% do mercado brasileiro migra para o WhatsApp** **[F, 01 §3.10]**; áudio no WhatsApp (que já temos via `responder_em_audio`) vale mais que voz no widget **[F, 08 §12.2]** |
| **N2** | Cobrowsing / screen share | Fullview, Cohere, ChatBeacon | Nenhum concorrente direto oferece; infraestrutura cara **[F, 08 §11.8]** |
| **N3** | Tours, checklists, surveys e news dentro do widget | só o Intercom | É produto de onboarding de SaaS B2B americano, não de captura de lead brasileiro |
| **N4** | Widget "totalmente skinnável" (tamanho de bolha, raio, animação) | vários | Intercom e Zendesk **nem deixam mudar tamanho** e ninguém deixa de comprar por isso. O que é percebido é **cor + logo + textos + branding removível**, nessa ordem **[F, 06 §7.3]** |
| **N5** | Launcher fatiado em 4–5 iframes | Trengo, tawk.to, Gorgias | Custo de memória em mobile sem ganho proporcional **[F, 03 §8.2 Nível 3]** |
| **N6** | Preço por resolução/outcome | Fin, Zendesk, HubSpot, Sierra | A Ada **criou** a métrica e **abandonou** a cobrança; a Decagon a rejeita publicamente; PME brasileira odeia conta variável em dólar **[F, 08 §12.3]** |
| **N7** | Bloquear Lighthouse/GTmetrix/HeadlessChrome | Crisp | Gaming de auditoria; quebra nossos próprios testes Playwright **[F, 03 §8.2]** |
| **N8** | Constelação de 15+ modelos com failover | Sierra | Exige volume e FinOps que não temos. A versão pobre (2 modelos: barato para roteamento, forte para resposta) já captura quase todo o ganho **[F, 08 §11.8]** |
| **N9** | Multimarca por `messenger_style_id` | Intercom | Nossa multi-tenancy já é por inbox; o problema real é o `widget_color` estar quebrado (M5), não faltar multimarca |
| **N10** | NPS renderizado no widget | — | Temos a aba de config e não achamos a renderização **[F, 09 §9]**; CSAT in-chat responde 30–40% contra 5–10% de e-mail e já existe **[F, 06 §10.7]**. Priorizar CSAT, não NPS |
| **N11** | Fine-tuning de modelo próprio | — | Sem base rotulada em escala, não paga **[F, 08 §11.8]** |
| **N12** | Migrar realtime para SSE | — | Jogaria fora ActionCable maduro + a reconexão que já está acima da média, para ganhar uma retomada que **já temos** via `after=` **[F, 05 §15.5]** |

### 3.4 🔵 NOSSA VANTAGEM — temos e o mercado não tem, ou temos melhor

| # | Vantagem | Contra quem | Evidência | Está sendo usada comercialmente? |
|---|---|---|---|:---:|
| **V1** | **Loader 15,9× mais leve no site do cliente** (28,8 KB vs 456,1 KB) | Leadster | 02 §8.1 | ❌ **Não.** É argumento de venda pronto e nunca dito |
| **V2** | **Isolamento real por iframe** (a Leadster tem 239 `!important` e vaza CSS nos dois sentidos) | Leadster, Crisp, Botpress | 02 §5.1–5.3 | ❌ |
| **V3** | **API pública com 14 métodos + 7 eventos** (Leadster: 1 método, 0 eventos) | Leadster, Octadesk | 02 §11.1; 09 §4 | ❌ |
| **V4** | **Verificação de identidade HMAC com escopo de conversa** e `hmac_verified` persistido | Leadster (não tem), Octadesk e Kommo (não assinam) | 02 §11.3; 04 §6.2 | ❌ |
| **V5** | **Reconexão realtime endurecida** (backoff+jitter, watchdog 15 s/25 s, `visibilitychange`/`focus`/`pageshow`) | Leadster desiste após 5 tentativas de 1 s | 05 §14.3 | ❌ |
| **V6** | **Preservação de estado em SPA** (a Leadster destrói e remonta, perdendo a conversa) | Leadster | 02 §12.5 | ❌ |
| **V7** | **i18n com ~51–55 locales, RTL e pt-BR 100% traduzido** (85/85 chaves) | Leadster tem 3 idiomas | 09 §9; 05 §10.1 | ❌ |
| **V8** | **`frame-ancestors` por inbox + rate limiting embutido + sanitização em profundidade** (markdown-it `html:false` + DOMPurify) | Leadster: `ACAO: *` e host ecoado do parâmetro | 05 §15.1; 02 §11.2 | ❌ |
| **V9** | **Continuidade de conversa por e-mail** | widgets front-only | 05 §15.1 | ❌ |
| **V10** | **Contextual retrieval + busca híbrida com RRF k=60** | acima da média de mercado para o nosso porte | 08 §4.2–4.3 | ❌ |
| **V11** | **Sistema de eval com episódios, 16 categorias de falha e gates determinísticos** | é "o Watchtower da Decagon feito em casa" | 08 §11.6 | ❌ |
| **V12** | **Camada de comportamento** (humanizer, debounce, dedup, horário, router) — não existe no upstream | ninguém do mercado documenta | 08 §11.4 | 🟡 |
| **V13** | **Sanitização de PII brasileira** (CPF, CNPJ, cartão com Luhn, telefone BR) em duas camadas | nenhum fornecedor internacional entrega pronto | 08 §6.2 | ❌ |
| **V14** | **A mesma IA no site e no WhatsApp**, com o mesmo contexto (`captain_inboxes`) | ninguém internacional entrega isso bem no Brasil | 08 §12.4 | 🟡 |
| **V15** | **Self-hosted / open-source: sem risco de descontinuação** | Drift morreu; Userlike virou Lime; Intercom virou Fin e foi comprada pela Salesforce por US$ 3,6 bi | 03 §2 | ❌ |
| **V16** | **Estamos 7 minor versions à frente da base do principal concorrente BR** (4.12.1 vs 4.5.2) | Leadster | 01 §7.3 | ❌ |

**[I] O achado mais desconfortável desta tabela:** de 16 vantagens verificáveis, **nenhuma está sendo usada como argumento comercial** e duas estão parcialmente. Isso é gap de narrativa, não de engenharia — e é o mais barato de fechar de todo o documento.

---

## 4. A frente de TRACKING, camada por camada

> Esta seção existe porque foi pedida explicitamente. Ela responde a uma pergunta:
> **o que exatamente falta para o ChatSPX entregar "Meta Pixel + Google (GA4/GTM/Ads) nativos" no widget?**

### 4.0 Ponto de partida — três fatos e uma restrição

**[F, 07 §6.2]** Hoje não existe **nenhuma** ocorrência de `fbq`, `gtag`, `dataLayer` ou `googletagmanager` em `app/`. O que existe (`AnalyticsHelper` com Amplitude, `LOG_ROCKET_PROJECT_ID`) é telemetria do **dashboard do agente**, não do visitante. Não confundir as duas coisas em nenhuma comunicação interna.

**[F, 07 §6.1] O achado mais acionável de todo o estudo:** a origem **já está no banco**. O SDK envia `document.location.href` completo — **com query string** — como `message[referer_url]`, e o backend grava em `conversations.additional_attributes.referer`. Ou seja: **os UTMs, o `gclid` e o `fbclid` de todas as conversas já capturadas estão lá, em texto, e ninguém parseia.** Ressalvas: `Conversation#validate_referer_url` anula o campo se a URL for inválida, e o valor é a URL do **momento do envio**, não a landing page da sessão.

**[F, 09 §6.5] Cuidado com o nome:** `referer` no nosso schema **não é** o `document.referrer` do navegador. É a página onde o visitante estava. **Hoje não sabemos de onde o lead veio, apenas onde ele estava.**

**Restrição arquitetural não-negociável [F, 07 §6.3]:** o widget roda em iframe de outra origem. Ele **nunca** enxerga `window.fbq` nem `window.dataLayer` do site do cliente. Portanto:
- todo **disparo de tag** tem de morar no **SDK (parent)**;
- toda **leitura de cookie de marketing** (`_fbp`, `_fbc`, `_ga`, `_gcl_aw`) tem de morar no **SDK**;
- a ponte já existe: `IFrameHelper.events.onEvent({eventIdentifier, data})` → `dispatchWindowEvent` (`IFrameHelper.js:206`). **Basta estendê-la.**

### 4.1 As oito camadas, com o que falta em cada uma

#### C0 — Parser retroativo do `referer` já gravado · esforço **P**

O que falta: um parser sobre `conversations.additional_attributes.referer` que extraia `utm_*`, `gclid`, `fbclid`, `msclkid`, `ttclid` e os exponha como atributos legíveis no painel e como filtro.

Por que é a primeira coisa a fazer **[I]**: entrega "de onde veio esse lead?" para **100% da base, retroativamente**, sem tocar no widget, sem negociar com Meta nem Google, sem risco de merge. É a fase que compra credibilidade para pedir orçamento das outras.

Cuidados: `automation_rules` **já aceita `referer` como atributo condicional** (`automation_rule.rb:38`) **[F, 07 §6.1]** — dá para criar regra "se referer contém `utm_source=google` então adicionar label" **hoje**, sem nenhuma linha de código.

#### C1 — Configuração por inbox · esforço **M**

| Campo | Tipo | Obrigatório | Observação |
|---|---|---|---|
| Meta Pixel ID | string | não | se vazio, só `dataLayer` |
| Meta Access Token | secret | não | idealmente por **OAuth**, não colado à mão |
| `test_event_code` | string | não | só em modo teste |
| GA4 Measurement ID | string | não | **autodetectável** varrendo o `dataLayer` por `['config', ID]` |
| GA4 API Secret | secret | não | só para Measurement Protocol |
| Google Ads `send_to` | string | não | `AW-XXXX/label` |
| Google Ads OAuth | conexão | não | para offline import |
| Mapa de eventos | tabela | sim | qual evento ChatSPX vira qual evento em cada destino |
| Valor do lead | número/regra | não | é o que destrava campanha por ROAS |
| Modo de consentimento | enum | sim | `sem CMP` / `aguardar consentimento` / `sempre negado` |

**Escopo: por inbox, não por conta** — agências e clientes multi-site precisam de pixels diferentes por site **[F, 07 §7.5]**.

**[I] O ponto que quebra a promessa "cola um ID e funciona":** Pixel ID e Measurement ID são públicos e triviais. **Access token da Meta, `api_secret` do GA4 e OAuth do Google Ads não são.** Ou se resolve com OAuth de um clique (como a Leadster faz com o `credential_id`), ou o server-side não sai do papel para o cliente médio. Isso é requisito de produto, não detalhe técnico.

**Onde encaixar com menos atrito de merge [F, 09 §15.3]:** `inbox.additional_attributes` (jsonb livre, sem migration, sem tocar em `EDITABLE_ATTRS`). **Atenção:** toda config nova precisa entrar em **dois lugares** — `app/views/widgets/show.html.erb` **e** `app/views/api/v1/widget/configs/create.json.jbuilder` — senão web e mobile divergem **[F, 09 §6.2]**.

#### C2 — Coletor de origem no SDK · esforço **M**

O que precisa ler, no `window` do cliente (não no iframe):
- `location.search`: `utm_source|medium|campaign|term|content|id`, `gclid`, `gbraid`, `wbraid`, `fbclid`, `msclkid`, `ttclid`, `lclid`;
- `document.referrer` e a **landing page** da sessão;
- derivar `_fbc` de `fbclid` no formato `fb.{subdomainIndex}.{ts}.{fbclid}` e `_gcl_aw` no formato `GCL.{unix}.{gclid}`, TTL 90 dias **[F, 07 §2.7, §3.7]**;
- ler `_fbp`, `_ga`, `_ga_<ID>`, `_gcl_aw` — **por allowlist explícita**, nunca `document.cookie` inteiro (crítica direta à Leadster, que copia todos os cookies) **[F, 07 §4.1.5]**;
- `gtag('get', ID, 'client_id'|'session_id')` **com timeout de 1 s** e fallback para leitura do cookie `_ga`/`_ga_<ID>` — a implementação da Leadster é a referência aqui **[F, 07 §3.3]**.

Modelo de atribuição **[F, 07 §5.2]**: gravar **os dois** conjuntos.
- `first_utm_*`, `first_referrer`, `first_landing_page`, `first_seen_at` → **write-once**, nunca sobrescrito.
- `last_utm_*`, `last_referrer`, `last_landing_page` → sobrescritos **só** quando a nova sessão tiver algum parâmetro de campanha ou referrer externo. Navegação interna **não zera** a origem (erro clássico).
- `gclid`/`fbclid` → o mais recente não vazio, com timestamp.

**Persistir no servidor, não só no navegador.** Safari/ITP corta storage escrito por JS para **7 dias** — o que significa que hoje até o nosso `cw_conversation` (expira em 365 dias) já vira novo visitante em 7 dias no Safari **[F, 07 §5.5]**.

**Rota de menor risco de merge [F, 09 §15.5]:** o front **já envia** `custom_attributes` no `POST /widget/conversations` e o controller **já os aceita**. Preencher esse objeto é **zero conflito**; estender `additional_attributes` no `base_controller` conflita a cada bump.

#### C3 — Contrato de eventos · esforço **P/M**

Prefixo fixo `chatspx_`, `snake_case`, ≤ 40 caracteres (limite do GA4). Doze eventos, dos quais **seis** nascem com `event_id` para deduplicação **[F, 07 §7.2]**:

| # | Evento ChatSPX | Meta | GA4 | Ads | Server-side |
|---:|---|---|---|---|:---:|
| 1 | `chatspx_widget_loaded` | — | — | — | não |
| 2 | `chatspx_widget_opened` | `ChatOpened` (custom) | custom | — | opcional |
| 3 | `chatspx_conversation_started` | **`Contact`** | custom | — | **sim** |
| 4 | `chatspx_prechat_submitted` | **`CompleteRegistration`** | custom | — | **sim** |
| 5 | `chatspx_lead` | **`Lead`** | **`generate_lead`** | `conversion` | **sim** |
| 6 | `chatspx_lead_qualified` | `QualifiedLead` (custom) | **`qualify_lead`** | secundária | **sim** |
| 7 | `chatspx_lead_disqualified` | — | **`disqualify_lead`** | — | opcional |
| 8 | `chatspx_agent_engaged` | — | **`working_lead`** | — | opcional |
| 9 | `chatspx_meeting_scheduled` | **`Schedule`** | custom | conversão | **sim** |
| 10 | `chatspx_conversation_resolved` | — | custom | — | opcional |
| 11 | `chatspx_deal_won` | **`Purchase`** (offline) | **`close_convert_lead`** | **Offline Import** | **só server** |
| 12 | `chatspx_deal_lost` | — | **`close_unconvert_lead`** | — | opcional |

**[I]** Vale registrar que a família `generate_lead` / `qualify_lead` / `working_lead` / `disqualify_lead` / `close_convert_lead` / `close_unconvert_lead` é **exatamente** o modelo mental de um chat de qualificação, e **nenhum fornecedor de chat estudado usa ela completa** — todos param em `generate_lead` ou inventam nomes próprios **[F, 07 §3.2]**.

**Gap de infraestrutura que precisa ser fechado antes:** hoje **não existe** evento de conversa criada com `conversation_id`, nem de pre-chat submetido, nem de CSAT respondido **[F, 09 §4.5]**. O `chatwoot:on-start-conversation` é **intenção**, não conclusão. Sem esses eventos, não há o que disparar. A boa notícia: o padrão `IFrameHelper.events.onEvent` permite adicionar evento novo **sem tocar no SDK** — é o ponto de extensão mais barato do sistema inteiro **[F, 09 §15.1]**.

#### C4 — Ponte de tags no SDK (client-side) · esforço **M**

Três estratégias possíveis, e a recomendação é **oferecer as três com precedência explícita** **[F, 07 §2.4]**:
1. Se há Pixel ID configurado **e** existe `window.fbq` → **`trackSingle`** naquele ID (a Leadster usa `track` e vaza o evento para todos os pixels da página — a própria Meta avisa disso).
2. Se há Pixel ID e **não** existe `fbq` → instalar com **`skipPageView = true`** e disparar `trackSingle`.
3. **Sempre, em paralelo** → `dataLayer.push` com nome prefixado.

Regras duras:
- código **aditivo** (`window.gtag = window.gtag || ...`), nunca destrutivo — sobrescrever o `gtag` do cliente quebra a medição do site inteiro dele **[F, 07 §3.1]**;
- `send_to` explícito no GA4;
- **nunca instalar um GA4 nosso** no site do cliente. A Leadster instala `G-43W2WYML5H` por padrão, desligável só por uma flag global não documentada. Sob LGPD isso é tratamento de dados do visitante do cliente para finalidade própria do fornecedor **[F, 07 §4.1.2]**;
- **nenhuma PII crua** no `dataLayer` nem nos params do `fbq` — o `dataLayer` é legível por qualquer script da página.

**Cuidado de peso [F, 07 §6.3]:** o `sdk.js` hoje tem 28,8 KB e um orçamento declarado de 40 KB. A ponte de tags precisa ser carregada **sob demanda**, só quando há configuração ativa na inbox — senão o widget engorda para todo cliente por causa de uma feature que poucos usam.

#### C5 — Fila server-side (CAPI + Measurement Protocol + Enhanced Conversions) · esforço **G**

| Peça | O que exige |
|---|---|
| Job por evento, idempotente pelo `event_id` | Sidekiq; DLQ visível no painel |
| Normalização **antes** do hash | Meta: só dígitos com DDI; Google: **E.164**. Telefone sem código de país simplesmente não casa |
| SHA-256 | e-mail (trim+lowercase), telefone, nome, sobrenome, cidade, estado, país, `external_id` |
| Nunca hashear | `fbp`, `fbc`, `client_ip_address`, `client_user_agent` — hashear quebra o matching |
| Janelas | CAPI 7 dias (62 offline); MP 72 h de backdating (48 h para atribuição); Ads 90 dias de `gclid` (63 dias com PII) |
| IP e UA | **do visitante**, nunca do servidor ChatSPX — é o erro que destrói o EMQ |
| Retry | backoff exponencial, 5 tentativas (a Leadster usa 3) + DLQ |

**Decisão de projeto:** hashear **no servidor**, não no navegador. A Leadster hasheia no cliente com `crypto.subtle` — decisão de privacidade elegante, mas o servidor deles não pode renormalizar um telefone mal formatado, e o hash errado perde o match **em silêncio**. Nós **já temos o dado em claro** no nosso banco; hashear no servidor é mais robusto **[F, 07 §7.5 decisão 1]**.

**Regra dura de GA4 [F, 07 §3.4]:** **ou** o evento vai pelo navegador **ou** pelo Measurement Protocol — nunca os dois para o mesmo evento lógico. O GA4 **não tem** deduplicação nativa; se você mandar `generate_lead` pelos dois caminhos, ele conta duas vezes.

#### C6 — Deduplicação · esforço **P** (se C5 existir)

A chave é o par **(`event_id`, `event_name`)**, com janela de **48 horas** **[F, 07 §2.6]**. O `event_id` deve **nascer no backend** (junto com o registro do evento), ser devolvido ao widget e propagado ao SDK para o `fbq`. Nascer no navegador é possível, mas fica frágil se a aba fechar antes do POST.

**[I]** Este é o item de melhor relação "impacto de credibilidade ÷ esforço" da frente inteira: **nem a Leadster faz**, e é verificável pelo cliente em 30 segundos no Events Manager dele.

#### C7 — Consentimento · esforço **M**

- Método novo no SDK, do tipo `setConsent({ad_storage, analytics_storage, ad_user_data, ad_personalization})`, para o CMP do cliente chamar.
- Estado padrão **configurável por conta**: quem declara operar sob CMP começa negado.
- Eventos client-side só disparam com `granted`; eventos server-side carregam o campo `consent` no payload do MP.
- **Ordem importa**: a Google avisa textualmente que *"if your consent code is called out of order, consent defaults won't work"* **[F, 07 §3.8]**.
- ANPD: cookies **não necessários** exigem consentimento livre, informado, inequívoco e granular, com revogação fácil **[F, 07 §3.9]**. Pixel e GA4 são, sem discussão, não necessários.
- **[NV]** Se a Simplex já tem DPA/aditivo contratual cobrindo o envio de PII hasheada a Meta/Google em nome dos clientes. **Precisa de verificação jurídica antes do lançamento.**

#### C8 — Relatório, auditoria e diagnóstico · esforço **M**

- Log por evento: `event_id`, destino, `event_name`, **lista de nomes** dos campos enviados (não os valores), timestamp, status HTTP, erro, EMQ quando disponível.
- Kill switch por conta e por inbox; retenção configurável (sugestão: 90 dias).
- Painel de diagnóstico com modo teste (`test_event_code`).
- **Exibir o EMQ estimado** no painel como métrica de saúde da integração **[F, 07 §2.8]** — um chat bem instrumentado consegue nove sinais (`em`, `ph`, `fn`, `ln`, `external_id`, IP, UA, `fbp`, `fbc`), o que deveria colocar o cliente na faixa 8+ sem esforço dele.
- **O ponto fraco documentado da Leadster é a documentação** — o artigo oficial deles sobre eventos é essencialmente um vídeo, sem especificação escrita de nomes, parâmetros ou payloads **[F, 07 §4.1.7]**. Uma página pública de contrato de eventos ganha a preferência de agências e times de dados, que são quem escolhe essa categoria de ferramenta.

### 4.2 Tabela consolidada de esforço

| Camada | O que entrega | Esforço | Depende de | Risco de merge com upstream |
|---|---|:---:|---|---|
| **C0** parser retroativo | "de onde veio o lead" para 100% da base | **P** | nada | **Nenhum** (backend novo, isolado) |
| **C1** config por inbox | onde o cliente cola os IDs | **M** | — | Baixo, se usar `additional_attributes` |
| **C2** coletor de origem no SDK | first/last touch, `_fbc`/`_gcl_aw`, `client_id` | **M** | C1 | Baixo (via `custom_attributes`) |
| **C3** contrato de eventos | o que disparar e quando | **P/M** | — | **Muito baixo** (`sdkEvents.js` tem 7 linhas) |
| **C4** ponte de tags | pixel/GA4/Ads no site do cliente | **M** | C1, C3 | Médio (mexe no SDK) |
| **C5** fila server-side | recupera os 20–40% perdidos | **G** | C1, C3 | **Nenhum** (código novo) |
| **C6** dedup `event_id` | credibilidade verificável | **P** | C4, C5 | Nenhum |
| **C7** consentimento | conformidade LGPD/GDPR | **M** | C4, C5 | Baixo |
| **C8** relatório e auditoria | suporte e prova de valor | **M** | C5 | Nenhum |
| **C9** offline import + `ctwa_clid` | ciclo fechado (espaço em branco) | **G** | C5 + funil no ChatSPX | Nenhum |

**[I] Ordem inegociável:** C0 antes de tudo. É o único item que entrega valor **sem** depender de credencial de terceiro, **sem** tocar no widget e **sem** risco de merge. Fazer C4 antes de C0 é construir a vitrine antes de saber se há estoque.

### 4.3 O que verificar antes de começar

| # | Item | Por quê |
|---|---|---|
| 1 | **[NV]** O webhook do WhatsApp Cloud API / WAHA entrega hoje o objeto `referral` com `ctwa_clid`? | D4 depende disso e ninguém checou **[F, 07 §8.4 lacuna 7]** |
| 2 | **[NV]** Existe DPA/aditivo cobrindo envio de PII hasheada a Meta/Google? | C7 e C5 dependem disso |
| 3 | **[NV]** Quantas conversas na frota têm `referer` com `utm_`/`gclid`/`fbclid` hoje? | Dimensiona o valor imediato de C0 |
| 4 | **[NV]** Quais headers de cache o nginx da frota devolve para `/packs/`? | O `sdk.js` **não tem fingerprint**; um deploy que mude o SDK depende disso para propagar **[F, 09 §4.1]** |

---

## 5. Roadmap em ondas

> Estimativas **relativas** (P/M/G), nunca em horas. "Critério de pronto" é o que precisa ser verdade para a onda estar encerrada.

### Onda 1 — Parar de constranger

**Objetivo:** eliminar o que é indefensável numa demo, numa auditoria ou num comparativo. Nada aqui é feature nova.

| Item | Origem | Esforço | Nota |
|---|---|:---:|---|
| Devolver o `widget_color` ao header, botão de enviar, ícones e link do pre-chat | M5 / 09 §16.1 R1 | **P** | Trocar `bg-n-brand`/`text-white` hardcoded por `rgb(var(--widget-color))` |
| Declarar `chat-bg` e `shadow-focus` no tema, ou remover as classes | 09 §16.1 R2 | **P** | Hoje geram **zero CSS**; o design pretendido não está no ar |
| `emitter.$emit` → `emitter.emit` | 09 §16.1 R3 | **P** | Erro de transcrição por e-mail é engolido e quebra o console |
| Alinhar expiração do cookie (365 d) com a do JWT (180 d) | 09 §16.1 R4 | **P** | Elimina a janela de 185 dias em que o visitante recorrente vira lead novo **em silêncio** |
| `addEventListener` em vez de `window.onmessage =` + validar `event.origin` nos dois lados | 05 §15.2 P0 #1 | **P** | Hoje qualquer script na página pode gravar `cw_conversation` (fixação de sessão) |
| `allowed_domains` preenchido no onboarding com o `website_url` que já é obrigatório | 05 §15.2 P0 #3 | **P** | Hoje qualquer site do mundo embute o widget de qualquer conta |
| Cookie com `secure` quando HTTPS | 05 §15.2 P0 #4 | **P** | |
| Tirar o **Leaflet** do grafo do widget | 09 §16.2 P1 | **P** | **−150 KB cru / −43 KB gzip** por uma linha de configuração do Vite |
| `size-limit` cobrindo JS **e** CSS, com falha no CI | 09 §16.2 P3 | **P** | Hoje o orçamento está verde enquanto o widget pesa 20× mais |
| `role="log"` + `aria-live="polite"`, `aria-label` traduzido na bolha, `type="button"` | M11 / 09 §16.4 | **M** | Falha WCAG 4.1.3 (AA). O `title="Open chat window"` é o único texto do widget fora do i18n |
| Auditar contraste do header verde `#2dc46f` com texto branco | 09 §16.4 A6 | **P** | ~2,3:1 contra o mínimo AA de 4,5:1 (**[NV]** — não foi medido, só estimado) |

**Dependências:** nenhuma.
**Risco de merge:** **baixo**. Nove dos onze itens tocam arquivos que o upstream quase não altera. A exceção são os componentes visuais do widget, que já estão poluídos por nós.
**Critério de pronto:** um cliente novo instala o widget, vê a **cor dele** no header, o `size-limit` falha se alguém regredir o peso, e uma auditoria axe-core no widget não acusa violação crítica.

---

### Onda 2 — Saber de onde vem o lead

**Objetivo:** responder "de qual campanha veio este atendimento?" para 100% da base, e devolver isso ao cliente na forma que ele já usa (GA4, Pixel, GTM).

| Item | Origem | Esforço | Nota |
|---|---|:---:|---|
| **C0** — parser retroativo de `additional_attributes.referer` + exibição e filtro no painel | §4.1 | **P** | **Comece por aqui.** Zero dependência externa |
| **C2** — coletor de origem no SDK (first/last touch, `_fbc`/`_gcl_aw`, `client_id`/`session_id`, allowlist de cookies) | §4.1 | **M** | Persistir no servidor por causa do ITP |
| **C3** — contrato de eventos + emissão de `conversation-created`, `prechat-submitted`, `csat-submitted`, `message-sent` via `onEvent` | §4.1 | **P/M** | **Zero mudança no SDK** — ponto de extensão barato |
| **C1** — configuração de tracking por inbox | §4.1 | **M** | Em `inbox.additional_attributes`; lembrar dos **dois lugares** (ERB + jbuilder) |
| **C4** — ponte de tags no SDK (`trackSingle`, `send_to`, `dataLayer` sempre, `skipPageView`) | §4.1 | **M** | Carregada sob demanda, para não engordar o loader |
| **M13** — analytics do widget: chats abertos, conversas iniciadas, leads, conversão por página | 01 §5.14 | **M** | Precisa do lead incompleto (Onda 3) para o dropout completo |
| **D14** — detectar referrer de IA generativa e marcar a conversa | 01 §3.7 | **P** | Canal que converte a 7,80% |
| Página pública de documentação do contrato de eventos | 07 §4.1.7 | **P** | É onde a Leadster é fraca; é onde agência decide |

**Dependências:** Onda 1 (o `postMessage` endurecido, para não construir em cima de um buraco de segurança).
**Risco de merge:** **baixo a médio.** C0, C1 e C3 são aditivos. C4 mexe no SDK — recomendação do relatório 09 §15.4: **refatorar a cadeia de 17 `else if` do `App.vue:258-345` para um mapa `{evento: handler}` antes** de adicionar métodos novos. Um mapa isola conflito por linha; a cadeia garante conflito.
**Critério de pronto:** o cliente cola dois IDs, abre o Gerenciador de Anúncios e o GA4 dele, e **vê o lead do chat aparecer**. E qualquer conversa antiga do banco mostra `utm_source` no painel.

---

### Onda 3 — Fazer o widget trabalhar

**Objetivo:** sair de "widget reativo que espera o clique" para "widget que aborda, qualifica e entrega ao WhatsApp com contexto". É a onda que fecha o gap de produto com a Leadster.

| Item | Origem | Esforço | Nota |
|---|---|:---:|---|
| **M3** — 7 gatilhos de abertura, com config **separada** desktop/mobile e cooldown por gatilho | 02 §16.3 | **M** | O contrato `BaseTrigger` deles é um bom desenho. Superar aceitando **seletor CSS completo** (eles aceitam 1 classe) |
| Teaser com rotação de chamadas + typing de 2 s + continuidade (última notificação vira 1ª mensagem) | 02 §9.7 | **M** | **Teaser, nunca auto-open** — toda reclamação documentada de usuário é contra o auto-open **[F, 06 §14.2 R7]** |
| Frequência: dispensa persistida, ocultar 7 dias após conversão | 06 §14.2 R9/R10 | **P** | |
| **M4** — máscaras e validadores BR no pre-chat (CPF, CNPJ, CPF-ou-CNPJ, CEP, UF+cidade, telefone, e-mail corporativo, anti-lixo) | 04 §12.2 R1 | **M** | Usar IBGE para municípios; validar **no blur**, aceitar entrada suja |
| **M9** — primeira mensagem com 2–4 opções nomeadas; nunca "Como posso ajudar?" | 06 §14.4 R24 | **P** | Máximo 4 botões: >4 = +22% de abandono em mobile |
| Pre-chat multi-etapa com condicionais; teto de **8 campos** no fluxo inteiro | 06 §14.3 R14 | **M** | `pre_chat_form_options` já é jsonb |
| **M36** — lead incompleto com sync incremental por resposta | 01 §15.2 R4 | **M** | Alicerce do dropout, da captura de abandono e do tempo entre perguntas |
| Dropout por etapa como métrica de primeira classe | 01 §15.3 R14 | **P** | (depois do item acima) |
| **D5** — handoff site→WhatsApp com roleta, mensagem pré-preenchida com variáveis, **código opaco no `?text=`** para costurar identidade e transcript | 05 §9.7 | **M** | **Ninguém faz isso.** É o item de maior diferenciação da onda |
| **D11** — calendário de feriados brasileiros no horário de atendimento | 04 §12.2 R4 | **P** | A Huggy cobra por isso em tabela de preço |
| **M10** — aviso de privacidade de uma linha na altura do primeiro campo pessoal (não modal) + checkbox **desmarcado** e separado para marketing | 06 §14.9 | **M** | Nenhum player BR faz direito |
| CSAT ligado por padrão | 06 §14.1 R4 | **P** | A UI já existe; CSAT in-chat responde 30–40% contra 5–10% de e-mail |
| **M6** — facade: o iframe só nasce no primeiro clique (ou quando há campanha/não lida) | 05 §15.3 Fase 2 | **G** | **Antes disso, resolver o CSS de 1,10 MB** — facade adia o problema, não emagrece |
| **M1/M12/M14/M15/M7/M8** — pendências de mesa restantes | §3.1 | **P** cada | Stub queue, `open()`/`close()`, contador de não lidas, persistir bolha no servidor, docs de instalação |

**Dependências:** Onda 2 (a origem precisa existir antes de personalizar a abordagem por origem).
**Risco de merge:** **médio a alto.** Esta onda mexe em `App.vue`, `AgentMessageBubble.vue` e no pre-chat — exatamente as áreas que o relatório 09 §15.8 marca como "não mexa antes de refatorar". **Recomendação:** as refatorações M1/M2 do relatório 09 (mapa de eventos no `App.vue`, `<component :is>` no `AgentMessageBubble`) entram **no começo desta onda**, não no fim.
**Critério de pronto:** um visitante que chega por anúncio, rola 50% da página e para de mexer recebe um teaser contextual, responde 4 perguntas com máscara brasileira, é distribuído para um vendedor no WhatsApp — e o atendente recebe a conversa **com a origem, o transcript e a qualificação** já anexados.

---

### Onda 4 — Provar valor e fechar o ciclo

**Objetivo:** transformar o widget de "gerador de lead" em "prova de ROI", e usar a IA que já temos como diferencial declarado.

| Item | Origem | Esforço | Nota |
|---|---|:---:|---|
| **C5** — fila server-side: Meta CAPI + GA4 Measurement Protocol + Enhanced Conversions | §4.1 | **G** | Recupera os 20–40% perdidos por adblock/ITP |
| **C6** — dedup por `event_id` | §4.1 | **P** | **Ninguém faz.** Verificável pelo cliente em 30 s |
| **C7** — Consent Mode + `setConsent` no SDK | §4.1 | **M** | |
| **C8** — log de auditoria, painel de diagnóstico, modo teste, EMQ exibido | §4.1 | **M** | Reduz o custo operacional de "não apareceu no Gerenciador" |
| **D4** — `ctwa_clid` do webhook do WhatsApp → CAPI `business_messaging` | 07 §2.10 | **M** | Depende da verificação #1 da §4.3. **Pode valer mais que o pixel do site** |
| **D3/C9** — offline conversion import (venda fechada → Ads/Meta com valor real) | 07 §3.7 | **G** | Janela do `gclid`: 90 dias. **Espaço em branco do mercado** |
| **D10** — citação de fonte ligada por padrão no canal web + declaração "sou uma IA" no 1º turno | 08 §12.1 D4/D5 | **P** | A flag já existe; é decisão de default por canal |
| **D9** — guardrail executável: mover os gates do `EpisodeGateService` do eval (pós-fato) para o pré-envio | 08 §12.1 D3 | **M** | Reusa código já testado; fecha o gap nº 1 da nossa IA |
| **D8** — tela de QA a partir do eval existente ("estas 7 respostas da sua IA tiveram problema esta semana") | 08 §12.2 item 3 | **M** | Motor pronto; vira SKU vendável |
| Painel de 6 métricas honestas, com **taxa de retorno em 7 dias** | 08 §5.5 | **M** | Nenhum concorrente publica isso; é o antídoto ao vício "abandono = sucesso" |
| **D6** — toggle "só aceitar usuários verificados" + JWT sob demanda (mantendo HMAC por compatibilidade) | 03 §8.2 D1/D2 | **M** | Já temos `hmac_verified` no banco |
| **D7** — contrato de design tokens com validação de contraste no painel | 03 §8.3 N1 | **M** | Resolve na raiz a classe de bug do header verde |
| **D13** — publicar o "Panorama" próprio do atendimento brasileiro | 01 §15.5 R22 | **M** | **Não depende de código.** Pode começar em paralelo à Onda 1 |
| **D12** — página de captura hospedada | 01 §15.2 R7 | **M** | |

**Dependências:** Ondas 2 e 3 (sem origem capturada e sem lead qualificado, não há o que mandar server-side).
**Risco de merge:** **baixo.** Quase tudo é código novo em `enterprise/` ou em serviços isolados.
**Critério de pronto:** o cliente vê no Gerenciador de Anúncios dele um evento `Lead` com origem **Browser e Server**, total **não dobrado**, EMQ ≥ 7 — e, 30 dias depois, a venda fechada aparece como conversão com valor real.

---

### 5.1 Visão de conjunto

```
Onda 1 ── higiene ──────────► "não constrange mais"
   │                            cor certa, sem buraco de segurança, a11y mínima, −43 KB
   ▼
Onda 2 ── origem ───────────► "sei de onde vem o lead"
   │                            C0 retroativo, coletor, eventos, dataLayer, GA4/Pixel client
   ▼
Onda 3 ── captura ──────────► "o widget trabalha sozinho"
   │                            gatilhos, teaser, máscaras BR, lead incompleto, WhatsApp costurado
   ▼
Onda 4 ── prova ────────────► "provo o ROI e a qualidade"
                                CAPI/MP, dedup, offline, ctwa_clid, QA de IA, tokens de tema

  ┌──────────────────────────────────────────────────────────────────────┐
  │ Em paralelo, sem depender de código: D13 (Panorama próprio),         │
  │ narrativa das 16 vantagens da §3.4, e a documentação pública         │
  │ do contrato de eventos.                                              │
  └──────────────────────────────────────────────────────────────────────┘
```

---

## 6. Riscos e armadilhas

### 6.1 Merge com o upstream Chatwoot

| Risco | Evidência | Mitigação |
|---|---|---|
| **A cadeia de 17 `else if` do `App.vue:258-345` conflita em todo merge** | 09 §15.4 | Refatorar para mapa `{evento: handler}` **antes** de adicionar métodos. Um mapa isola conflito por linha; a cadeia garante conflito |
| **O `v-if` composto do `AgentMessageBubble.vue:92-152` conflita** | 09 §15.2 | Refatorar para `<component :is>` com mapa de `content_type` — **reduz** a superfície de conflito em vez de aumentá-la |
| **A paleta remapeada em `woot.scss:182-378` (`iris`/`blue` virando verde) conflita a cada bump** | 09 §14 | Introduzir tokens **novos** (`--spx-*`) em vez de sequestrar os existentes |
| **`base_controller.rb#permitted_params` é área de alto atrito** | 09 §15.5 | Preferir `custom_attributes`, que o front **já envia** e o controller **já aceita**. Zero conflito |
| **Toda config nova precisa entrar em dois lugares** (`show.html.erb` + `configs/create.json.jbuilder`) | 09 §6.2 | Documentar no `PRODUCT.md`. Esquecer um dos dois faz web e mobile divergirem silenciosamente |
| **Bits livres em `channel_web_widgets.feature_flags` só a partir do 6** | 09 §15.3 | Configuração estruturada nova vai em `additional_attributes` (jsonb), não em bitmask |
| **Colisão de timestamp de migration em merges do fork** | memória do projeto | Detectar com `uniq -d` antes de subir; `git mv` para timestamp único |
| Upstream lançar tracking antes de nós | 07 §6.4 | **Baixo.** Três issues (#5965, #7642, #7981) abertas há 3 anos sem entrega. Manter a implementação isolada em módulo próprio de qualquer forma |

### 6.2 Peso do bundle

| Risco | Evidência | Mitigação |
|---|---|---|
| **O widget já pesa ~587 KB gzip para 100% dos visitantes** | 09 §12; 05 §14.1 | Onda 1 tira o Leaflet (−43 KB) e trava o orçamento no CI; Onda 3 ataca o CSS de 1,10 MB e o facade |
| **A ponte de tags engorda o `sdk.js`**, que é script de terceiro no site do cliente | 07 §7.6 | Carregar sob demanda, só com config ativa. Orçamento explícito de bytes para o loader |
| **Facade sem emagrecer é esconder o problema** | 05 §15.5 | Resolver o CSS **antes** do facade. A ordem importa |
| Os 2 PNGs de fundo (~90 KB cada) no primeiro paint, sem WebP/AVIF e sem preload | 09 §14 | Converter ou substituir por gradiente/SVG |

### 6.3 LGPD e conformidade

| Risco | Evidência | Mitigação |
|---|---|---|
| **Processar PII do visitante para enviar a Meta/Google faz de nós operador por conta do cliente** | 07 §3.9 | Precisa estar em contrato/DPA e visível no painel: lista de destinos por inbox, log de campos enviados, botão de desligar, retenção definida. **[NV]** se já existe |
| **PII vazando para o `dataLayer`** (legível por qualquer script da página) | 07 §7.6 | Regra dura: PII só server-side, só hasheada. Teste que barre campos sensíveis no payload client-side |
| **Token da Meta / `api_secret` do GA4 vazando para o navegador** | 07 §7.6 | Segredos nunca saem do backend; nunca aparecem em endpoint público do widget |
| **Consentimento com padrão permissivo** (o erro da Leadster: `consentRequired` default `false`) | 02 §10.4 | Padrão configurável por conta; quem declara CMP começa negado |
| **Decisão automatizada da IA sobre o lead** (desqualificar é decisão automatizada — art. 20 da LGPD) | 08 §9.4.3 | O `reasoning` do `ResponseSchema` já captura o porquê; falta expor. ANPD colocou IA entre os 4 eixos de fiscalização 2026-2027 |
| **EU AI Act art. 50 em vigor desde 02/08/2026** — chatbot precisa se identificar como IA, com alcance extraterritorial | 08 §9.4.1 | D10. Multa de € 15 mi ou 3% do faturamento mundial |
| **Contato criado no page-load, antes de qualquer interação** | 09 §13.2 item 12 | Base inflada com registros anônimos e ruído em relatório. É upstream, mas com tráfego real vira custo e problema de qualidade de dado |

### 6.4 CSP e ambiente dos sites clientes

| Risco | Evidência | Mitigação |
|---|---|---|
| **Quebrar a medição do site do cliente** (sobrescrever `gtag`, duplicar `PageView`) | 07 §7.6 | Código aditivo, `skipPageView`, `trackSingle`/`send_to`, e "somente `dataLayer`" como padrão seguro |
| **CSP do cliente bloqueando nossos hosts** | 05 §6.4 | Separar loader / assets / API em hosts distintos permite CSP granular. Documentar a lista de hosts |
| **`/packs/js/sdk.js` sem fingerprint nem SRI** | 09 §4.1 | Um deploy que mude o SDK depende inteiramente dos headers de cache do nginx. Versionar por path antes de pensar em SRI |
| **Adblock derrubando o client-side** | 07 §2.5 | ~31,5% dos visitantes bloqueiam o Pixel; GA4 5–15% (40–60% em público técnico). **É a justificativa do server-side**, não um detalhe |
| **`MutationObserver` na `<body>` do cliente com `subtree: true`** | 09 §13.2 item 10 | Ruído contínuo no main thread do site alheio. Trocar por Navigation API / patch de `history` |

### 6.5 Custo de IA

| Risco | Evidência | Mitigação |
|---|---|---|
| **Widget web é o canal mais exposto a prompt injection**: anônimo, sem custo de criar "conta", atacante itera centenas de vezes | 08 §9.2 | Rate limit por sessão do widget; validação de ação sensível **em código**, não em prompt (padrão Decagon); D9 |
| **Injeção indireta via conteúdo ingerido** (página editável por terceiro que entra no `CrawlJob`) | 08 §9.2 | Segregar conteúdo não confiável na base |
| **Alucinação com consequência comercial** — precedente *Moffatt v. Air Canada*: a empresa responde pelo que o chatbot diz | 08 §9.1 | D10 (citação de fonte); informação com consequência comercial só sai com fonte oficial |
| **Custo variável de inferência sem teto** | 08 §9.5 item 12 | Teto de gasto por conta com kill switch |
| **`build_state` envia `contact.custom_attributes` inteiro ao LLM** — se a conta guarda CPF em custom attribute, ele vai no prompt | 08 §9.3 | O `sanitize_attr` trunca em 200 caracteres mas **não mascara** |

### 6.6 Navegadores e plataforma

| Risco | Evidência | Mitigação |
|---|---|---|
| **Safari/ITP apaga storage escrito por JS em 7 dias** | 07 §5.5 | Persistir origem **no servidor**. Isso já é problema hoje: nosso `cw_conversation` "de 365 dias" não sobrevive 7 dias de inatividade no Safari |
| **Cookie sem `Partitioned`** tende a ser bloqueado pelo Chrome | 05 §15.2 P0 #4 | |
| **Breakpoint mobile divergente** (667 px no CSS vs 668 px no JS) e datado | 09 §10.3; 06 §14.6 R37 | 667 px é a largura do iPhone 6/7/8 em landscape |
| **`user-scalable=0, maximum-scale=1`** viola WCAG 1.4.4 (AA) | 05 §15.2 P1 #12 | Substituível por `font-size: 16px` nos inputs |
| **Sem `dvh`/`visualViewport`/`safe-area`** — composer sob o teclado em mobile | 05 §15.2 P1 #11 | 74,4% do tráfego brasileiro é mobile **[F, 01 §3.6]** |
| **Zero observabilidade no widget** — ~20 `catch { // Ignore error }` | 09 §9 | Já temos GlitchTip na frota; falta instrumentar o widget com cliente isolado e scrubbing de PII |

### 6.7 O risco que não é técnico

**[I]** O maior risco deste plano não está em nenhuma tabela acima: é **executar as ondas 2, 3 e 4 e continuar sem contar a história**. Das 16 vantagens verificáveis da §3.4, **nenhuma** aparece hoje em material comercial. O ChatWoot BR — que roda a mesma base MIT — publica preço, 14 páginas de comparação contra todos os players, verticalização e LGPD como bullet **[F, 04 §4.20.1]**. A barreira contra a Leadster não é tecnológica; é narrativa. Um roadmap de engenharia sem D13 (o Panorama) e sem a página de comparação entrega produto melhor e mercado igual.

---

## 7. Perguntas em aberto para o Walisson decidir

> Cada uma com as opções reais, o que muda, e a minha recomendação. São as decisões que **não** dá para tomar lendo os relatórios.

### Q1 — Qual é o comprador-alvo do widget?

| Opção | O que significa |
|---|---|
| **(a) Marketing** — o widget é produto de captura, vendido ao gestor de tráfego/agência | Concorrência rala no Brasil (só Leadster, Cliengo, JivoChat); exige Ondas 2 e 3 completas |
| (b) Operação — o widget continua sendo canal de atendimento | Guerra de preço na faixa R$ 69–599 com ChatWoot BR, Nexloo, Umbler, CWMKT |
| (c) TI — widget como SDK embutível no produto do cliente | Mercado menor, lock-in técnico alto |

**Recomendação: (a), sem abandonar (b).** É a "Posição B" do relatório 04 §11.3: manter a base de atendimento e **adicionar** a captura. É a única leitura em que o widget vira ativo de receita em vez de item de checklist, e o quadrante site+marketing está rarefeito no Brasil. **Consequência prática:** o widget passa a ter dois compradores e duas telas de configuração, e isso precisa ser assumido no roadmap.

### Q2 — Arquitetura: manter iframe, migrar para Shadow DOM, ou híbrido?

| Opção | Trade-off |
|---|---|
| **(a) Híbrido** — iframe para o painel, Shadow DOM para o chrome (bolha, badge, teaser) | Resolve três problemas de uma vez: `aria-live` no documento do cliente, badge sem carregar o app, e o facade que corta ~570 KB |
| (b) Manter tudo em iframe | Simples, mas mantém o peso e a a11y ruim |
| (c) Migrar para DOM direto (como a Leadster) | Trocaria 577 KB por dívida infinita de CSS. A Leadster tem 239 `!important` para provar |

**Recomendação: (a).** É a conclusão convergente de 03 §8.2 (D8), 05 §15.3 e 02 §16.2. **É a decisão que precisa ser tomada antes de qualquer código da Onda 3**, porque muda onde o teaser é implementado.

### Q3 — O motor do fluxo de captura: construir novo no widget, ou reusar o Flows?

| Opção | Trade-off |
|---|---|
| **(a) Reusar o motor Flows** e tornar acionável pelo widget web | Aproveita o que já existe; o gap declarado é exatamente "Flows não é acionável pelo widget" **[F, 09 §9]** |
| (b) Motor novo, client-side, como a Leadster (fluxo inteiro no JSON do bootstrap) | Percepção de velocidade (zero round-trip por resposta), mas duplica motor |
| (c) Híbrido: fluxo servido pelo backend, executado no cliente | O que a Leadster faz na prática |

**Recomendação: (c), com o Flows como fonte de verdade.** O relatório 02 §16.4 mostra o padrão certo: `path`, `host`, `query` e `platform` vão no bootstrap e **o servidor decide qual fluxo entregar** — regra de segmentação auditável e alterável sem deploy de front. **Ressalva:** enviar allowlist de parâmetros, não a query crua (a Leadster coleta PII acidental assim).

### Q4 — Onde hashear a PII para CAPI/Enhanced Conversions?

| Opção | Trade-off |
|---|---|
| **(a) Servidor** | Já temos o dado em claro; permite normalizar e corrigir. Evita hash errado silencioso |
| (b) Navegador (`crypto.subtle`, como a Leadster) | PII crua nunca sai do navegador — elegante, mas o servidor não pode consertar telefone mal formatado |

**Recomendação: (a).** Com a ressalva de que o argumento de privacidade de (b) merece figurar na comunicação: podemos dizer que **o dado já é nosso** (o chat é nosso), então hashear no servidor não amplia a exposição.

### Q5 — Instalar tag faltante no site do cliente?

| Opção | Trade-off |
|---|---|
| **(a) Sim, opt-in explícito por inbox**, com aviso de que passaremos a injetar script de terceiro | Resolve o cliente que não tem pixel; mantém a governança dele |
| (b) Sim, por padrão (como a Leadster) | Risco de duplicidade e de LGPD |
| (c) Nunca; só `dataLayer` | Zero risco, mas transfere 100% do trabalho ao cliente — atrito que mata adoção em PME sem agência |

**Recomendação: (a).** E, em qualquer cenário, **nunca instalar um GA4 nosso** no site do cliente — a Leadster faz isso (`G-43W2WYML5H`) e é a prática mais indefensável do bundle deles.

### Q6 — Enforcement de identidade verificada: ligar por padrão?

| Opção | Trade-off |
|---|---|
| **(a) Toggle por inbox, com modo "somente aviso" durante a migração** | Não quebra cliente existente; vira argumento de venda para banco/saúde/jurídico |
| (b) Ligado por padrão em inbox nova | Mais seguro, mas exige modo anônimo coexistente e mensagens de erro claras **em português** |
| (c) Deixar como está | Perde uma vantagem que já temos no banco |

**Recomendação: (a) agora, (b) depois**, quando existir o debugger de token. Só **um** dos 20 players globais tem esse toggle de forma simples (o Front) — é diferencial disponível **[F, 03 §8.3 N2]**.

### Q7 — Modelo comercial da IA: manter crédito/assinatura ou ir para outcome?

| Opção | Trade-off |
|---|---|
| **(a) Manter assinatura e copiar a *garantia*, não a unidade** | O movimento do Tidio ("Guaranteed 50% Lyro AI resolution rate" no tier premium) transfere o risco de execução para nós mantendo a conta previsível — e **só podemos garantir porque temos o eval para medir** |
| (b) Cobrar por resolução/outcome | A Ada criou a métrica e **abandonou** a cobrança; a Decagon a rejeita publicamente; PME brasileira odeia conta variável em dólar |

**Recomendação: (a).** Se algum dia houver SKU por unidade, o piso público a bater é **US$ 0,50** (HubSpot), não US$ 0,99.

### Q8 — Contribuir o tracking upstream ou manter proprietário?

| Opção | Trade-off |
|---|---|
| **(a) Manter proprietário, isolado em módulo próprio** | Diferencial comercial; três issues abertas há 3 anos indicam que o upstream não vai entregar |
| (b) Contribuir upstream | Some do nosso diff de merge, mas some também do nosso diferencial |
| (c) Híbrido: contribuir o que é infraestrutura (validação de `origin`, `targetOrigin`, stub queue), manter proprietário o que é produto | |

**Recomendação: (c).** O patch de `targetOrigin` do `IFrameHelper.sendMessage` que já fizemos é candidato natural a upstream — se aceito, some do nosso diff de graça **[F, 09 §16.6 M7]**.

### Q9 — Publicar o "Panorama" próprio?

| Opção | Trade-off |
|---|---|
| **(a) Sim** — benchmark anual do atendimento conversacional brasileiro, a partir do dado agregado da frota | É a recomendação de maior retorno de todo o estudo e **não depende de código**. Requisitos inegociáveis: agregação, anonimização, **consentimento contratual** e metodologia publicada |
| (b) Não | Continuamos disputando feature contra quem disputa autoridade |

**Recomendação: (a), começando em paralelo à Onda 1.** É a única recomendação que não compete por tempo de engenharia. **Bloqueio real:** o consentimento contratual dos clientes da frota para uso agregado do dado — **[NV]**, precisa de resposta jurídica antes de qualquer coleta.

### Q10 — O que fazer com as tools verticais de um cliente só no `tools.yml` global?

| Opção | Trade-off |
|---|---|
| **(a) Migrar as 7 tools verticais (Vista/Tozi, Sinop) para `captain_custom_tools`** | O mecanismo por conta já existe e tem validação anti-SSRF. Limpa o catálogo global |
| (b) Deixar como está | Tools de um cliente aparecem para toda conta; o `tools.yml` é registro único |

**Recomendação: (a).** É dívida de produto conhecida e barata **[F, 08 §12.2 item 12]**. Não é urgente, mas cada vertical nova torna a limpeza mais cara.

---

## Anexo A — Rastreabilidade: de onde veio cada bloco

| Seção deste documento | Relatórios de origem |
|---|---|
| §1 Resumo executivo | 01 §7, §15.1 · 02 §7, §16.1 · 04 §11 · 06 §13.4 · 07 §0 · 08 §5.3 · 09 §1 |
| §2 Matriz de paridade | 01 §5, §6 · 02 §9, §11, §12 · 03 §6 · 04 §5.2, §12.1 · 07 §4.10, §6.5 · 08 §11.7 · 09 §9 |
| §3.1 Mesa | 04 §12.1 (lista do obrigatório) · 03 §8.1 · 09 §9, §13 |
| §3.2 Diferencial | 03 §8.3 · 07 §4.10, §7 · 08 §12 · 01 §15 |
| §3.3 Ruído | 03 §8.2 nível 3 · 06 §7.3 · 08 §11.8, §12.5 · 05 §15.5 |
| §3.4 Nossa vantagem | 02 §12.7 · 03 §8.0 · 05 §15.1 · 08 §11.8 · 09 §14 |
| §4 Tracking | **07 inteiro**, principalmente §2, §3, §5, §6, §7 · 09 §11 |
| §5 Roadmap | 09 §16.7 · 05 §15.3 · 07 §7.4 · 01 §15.7 · 02 §16.11 · 08 §12.2 |
| §6 Riscos | 09 §15 · 05 §15.2, §15.5 · 07 §7.6 · 08 §9 · 04 §10.3 |
| §7 Perguntas | cruzamento de todos |

### A.1 Lacunas herdadas que este documento não resolve

Registro para que nada vire mito interno. Todas vêm marcadas como não verificadas nos relatórios de entrada:

1. **[NV]** Se o webhook do WhatsApp Cloud API / WAHA entrega o objeto `referral` com `ctwa_clid` hoje (07 §8.4).
2. **[NV]** Se a Simplex tem DPA/aditivo cobrindo envio de PII hasheada a Meta/Google (07 §8.4).
3. **[NV]** Se existe teste A/B público comparando **teaser vs auto-open** — é a lacuna mais importante do relatório 06, e temos frota para medir internamente (06 §15 L1).
4. **[NV]** Snippet, API e nível real de customização do webchat de RD Conversas, Digisac, Poli, Movidesk e Fortics — tudo atrás de painel autenticado (04 §13).
5. **[NV]** Se a Leadster oferece deduplicação, consent mode ou conversão offline — sem documentação pública e não inferível do bundle (07 §8.4).
6. **[NV]** Se o widget do ChatSPX declara "sou uma IA" por padrão — não localizado no código lido (08 §13).
7. **[NV]** Contraste medido do header verde `#2dc46f` com texto branco (09 §16.4 A6 estima ~2,3:1, sem medir).
8. **[NV]** Headers de cache que o nginx da frota devolve para `/packs/` (09 §4.1).

---

**Fim do documento.** Nenhum arquivo de código foi modificado. Os relatórios 01–09 não foram alterados. O único artefato produzido por esta task é este markdown.
