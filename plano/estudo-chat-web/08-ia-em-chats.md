# TASK 08 — IA em chat de site: agentes, deflection e o que mudou em 2025/2026

> **Status:** estudo puro. Nenhum arquivo de código foi alterado. Único artefato produzido: este documento.
> **Data da pesquisa:** 11 de agosto de 2026.
> **Autor:** worker de pesquisa (task_0f51e6fae6bb).
> **Escopo:** estado da arte de IA aplicada a chat de site (widget web), com auditoria honesta do que o ChatSPX já entrega via Captain.

---

## SUMÁRIO

- [0. Como ler este documento](#0-como-ler-este-documento)
- [1. O que mudou em 2025/2026 — a linha do tempo que reposicionou o mercado](#1-o-que-mudou-em-20252026--a-linha-do-tempo-que-reposicionou-o-mercado)
- [2. Os agentes de IA de atendimento, um a um](#2-os-agentes-de-ia-de-atendimento-um-a-um)
  - [2.1 Intercom Fin](#21-intercom-fin-hoje-apenas-fin)
  - [2.2 Zendesk AI agents (Ultimate + Forethought)](#22-zendesk-ai-agents-ultimate--forethought)
  - [2.3 Sierra](#23-sierra)
  - [2.4 Decagon](#24-decagon)
  - [2.5 Ada](#25-ada-adacx)
  - [2.6 Forethought](#26-forethought-agora-dentro-da-zendesk)
  - [2.7 Salesforce Agentforce](#27-salesforce-agentforce)
  - [2.8 HubSpot Breeze](#28-hubspot-breeze-customer-agent)
  - [2.9 Freshworks Freddy](#29-freshworks-freddy-ai-agent)
  - [2.10 Tidio Lyro](#210-tidio-lyro)
  - [2.11 Crisp](#211-crisp-magicreply--hugo)
  - [2.12 Drift / Salesloft](#212-drift--salesloft-o-cadáver-do-conversational-marketing)
  - [2.13 Qualified Piper](#213-qualified-piper--o-vizinho-da-leadster-no-enterprise)
  - [2.14 Tabela comparativa consolidada](#214-tabela-comparativa-consolidada)
- [3. Precificação por resolução: anatomia, críticas e efeito de mercado](#3-precificação-por-resolução-anatomia-críticas-e-efeito-de-mercado)
- [4. Arquitetura de referência de um agente de IA de chat de site](#4-arquitetura-de-referência-de-um-agente-de-ia-de-chat-de-site)
- [5. Métricas: o dicionário e os números públicos](#5-métricas-o-dicionário-e-os-números-públicos)
- [6. IA do lado do ATENDENTE (agent-side / copiloto)](#6-ia-do-lado-do-atendente-agent-side--copiloto)
- [7. IA do lado do MARKETING — o território da Leadster](#7-ia-do-lado-do-marketing--o-território-da-leadster)
- [8. Voz e multimodal em chat de site](#8-voz-e-multimodal-em-chat-de-site)
- [9. Riscos e governança](#9-riscos-e-governança)
- [10. Open source e o que dá para reaproveitar](#10-open-source-e-o-que-dá-para-reaproveitar)
- [11. AUDITORIA: o que o ChatSPX/Captain já tem hoje](#11-auditoria-o-que-o-chatspxcaptain-já-tem-hoje)
- [12. IMPLICAÇÕES PARA O CHATSPX](#12-implicações-para-o-chatspx)
- [13. Fontes consultadas](#13-fontes-consultadas)

---

## 0. Como ler este documento

O usuário pediu explicitamente para separar o que é fato verificado do que é inferência. As convenções são:

| Marcador | Significado |
|---|---|
| **[FATO]** | Verificado em fonte primária (site oficial do fornecedor, help center oficial, press release, repositório de código, API pública). URL sempre citada. |
| **[FATO-2ª]** | Número/afirmação que só encontrei em fonte secundária (blog de concorrente, agregador de preços, imprensa especializada). Tratar com desconfiança: boa parte do conteúdo de preço de IA em 2026 é *content marketing* de concorrente. |
| **[INFERÊNCIA]** | Leitura minha a partir dos fatos. Não é afirmação do fornecedor. |
| **[NÃO VERIFICADO]** | Não consegui confirmar. Está aqui porque a lacuna importa. |
| **[CÓDIGO]** | Verificado por leitura direta do repositório `/home/chatwoot/chatwoot` na branch `homologacao`, com caminho de arquivo citado. |

Aviso importante sobre a qualidade das fontes de preço: **quase todo resultado de busca por "X pricing 2026" é blog de concorrente** (eesel.ai, myaskai.com, getmacha.com, featurebase.app, fin.ai/learn, decagon.ai/glossary). Eles têm incentivo direto para inflar o custo do rival. Sempre que consegui a página oficial, usei ela; onde só havia secundária, marquei `[FATO-2ª]`.

---

## 1. O que mudou em 2025/2026 — a linha do tempo que reposicionou o mercado

Esta seção existe porque o pedido foi "o que mudou". A resposta curta: **o chat de site deixou de ser um canal e virou um produto de resolução vendido por unidade de trabalho executado.** A consolidação foi brutal e o modelo comercial mudou de assento para desfecho.

### 1.1 Linha do tempo verificada

| Data | Evento | Fonte |
|---|---|---|
| 13/03/2024 | **[FATO]** Zendesk anuncia aquisição da **Ultimate** ("industry-leading provider of service automation") | [prnewswire.com](https://www.prnewswire.com/news-releases/zendesk-to-acquire-ultimate-302088192.html) |
| 2024 | **[FATO-2ª]** Zendesk adquire **Klaus** e transforma em Zendesk QA (WEM suite) | [eesel.ai](https://www.eesel.ai/blog/customer-support-quality-assurance-tools) |
| Fev/2024 | **[FATO-2ª]** Salesloft adquire **Drift** | [eesel.ai](https://www.eesel.ai/blog/drift-ai) |
| 15/05/2025 | **[FATO]** Salesforce introduz o modelo **Flex Credits** do Agentforce, substituindo o preço fixo por conversa | [help.salesforce.com](https://help.salesforce.com/s/articleView?id=004811240&language=en_US&type=1) |
| Mai/2025 | **[FATO-2ª]** **Klarna reverte** a substituição de ~700 agentes por IA e volta a contratar humanos | [Forbes](https://www.forbes.com/sites/quickerbettertech/2025/05/18/business-tech-news-klarna-reverses-on-ai-says-customers-like-talking-to-people/) |
| Dez/2025 | **[FATO-2ª]** ANPD publica **Mapa de Temas Prioritários 2026-2027** com IA como um dos quatro eixos de fiscalização | [martinelli.adv.br](https://www.martinelli.adv.br/anpd-publica-mapa-de-temas-prioritarios-2026-2027-e-atualiza-a-agenda-regulatoria-2025-2026/) |
| Fev/2026 | **[FATO]** Ada lança o **Unified Reasoning Engine** (patent-pending) | [ada.cx](https://www.ada.cx/media-center/press-release/ada-launches-industrys-first-unified-reasoning-engine/) |
| 06/03/2026 | **[FATO-2ª]** Clari + Salesloft anunciam o **sunset gradual do Drift**, com a 1mind como sucessora | [eesel.ai](https://www.eesel.ai/blog/drift-ai) / [myaskai.com](https://myaskai.com/blog/drift-alternatives-2026) |
| 11/03/2026 | **[FATO]** Zendesk assina acordo definitivo para adquirir a **Forethought** | [zendesk.com newsroom](https://www.zendesk.com/newsroom/articles/forethought-acquisition/) |
| ~Mar/2026 | **[FATO]** Intercom publica *"From resolutions to outcomes"* — muda a unidade de cobrança do Fin de "resolução" para "outcome" | [intercom.com/blog](https://www.intercom.com/blog/from-resolutions-to-outcomes-evolving-how-fin-delivers-value/) |
| 14/04/2026 | **[FATO]** HubSpot move Breeze Customer Agent e Prospecting Agent para **outcome-based pricing** (US$ 0,50/conversa resolvida) | [hubspot.com/company-news](https://www.hubspot.com/company-news/hubspots-customer-agent-and-prospecting-agent-now-you-pay-when-the-task-is-complete) |
| 04/06/2026 | **[FATO-2ª]** Forethought vira add-on comprável dentro da Zendesk | [corebee.ai](https://corebee.ai/blog/zendesk-forethought-acquisition-2026) |
| 15/06/2026 | **[FATO]** **Salesforce assina acordo para comprar a Fin (ex-Intercom) por ~US$ 3,6 bilhões**; fechamento previsto para o Q4 do ano fiscal de 2027 | [salesforce.com press release](https://www.salesforce.com/news/press-releases/2026/06/15/salesforce-signs-definitive-agreement-to-acquire-fin/) / [TechCrunch](https://techcrunch.com/2026/06/15/salesforce-acquires-ai-customer-service-platform-fin-for-3-6b/) |
| 02/08/2026 | **[FATO]** Entram em aplicação as obrigações de transparência do **Artigo 50 do EU AI Act** — chatbots precisam se identificar como IA | [artificialintelligenceact.eu](https://artificialintelligenceact.eu/article/50/) |

### 1.2 As cinco mudanças estruturais

**(a) A unidade de venda deixou de ser o assento.** Fin, Zendesk, HubSpot, Sierra e Agentforce cobram por trabalho executado, não por licença de usuário. **[FATO]** Ver seção 3.

**(b) O "chatbot de fluxo" morreu comercialmente.** O Drift — que *inventou* a categoria "conversational marketing" — está em sunset. **[FATO-2ª]** O sucessor apontado (1mind) vende "AI digital teammates" que aparecem em vídeo. **[INFERÊNCIA]** Isso é o sinal mais claro de que árvore de decisão sem LLM virou commodity de baixo valor: quem só tem fluxo não sustenta preço.

**(c) A régua de qualidade migrou de "deflection" para "resolução verificada".** A Zendesk hoje **verifica a resolução com um LLM** antes de cobrar. **[FATO]** — *"each resolution is verified by a language model"*, [support.zendesk.com](https://support.zendesk.com/hc/en-us/articles/5352026794010-About-automated-resolutions-for-AI-agents).

**(d) A arquitetura virou "constelação de modelos + supervisores", não um prompt gigante.** **[FATO]** A Sierra declara usar **15+ modelos** ("frontier, open-weight, and proprietary models, depending on the job to be done") com **supervisores rodando em paralelo** revisando cada resposta ([sierra.ai](https://sierra.ai/blog/constellation-of-models)). A Ada descreve o Reasoning Engine como "constellation of language models" com raciocínio duplo (imediato + background) ([ada.cx](https://www.ada.cx/media-center/press-release/ada-launches-industrys-first-unified-reasoning-engine/)).

**(e) A conta de "IA substitui humano" foi publicamente rasgada.** **[FATO-2ª]** A Klarna havia declarado que a IA fazia o trabalho de 700 pessoas, com 2,3 milhões de conversas em um mês e tempo de resolução caindo de 11 minutos para menos de 2, com estimativa de US$ 40 milhões/ano de economia — e reverteu, recontratando humanos para disputas, reembolsos complexos e casos de dificuldade financeira ([Forbes](https://www.forbes.com/sites/quickerbettertech/2025/05/18/business-tech-news-klarna-reverses-on-ai-says-customers-like-talking-to-people/), [Entrepreneur](https://www.entrepreneur.com/business-news/klarna-ceo-reverses-course-by-hiring-more-humans-not-ai/491396)).

---

## 2. Os agentes de IA de atendimento, um a um

### 2.1 Intercom Fin (hoje apenas "Fin")

**O que faz. [FATO]** Agente autônomo que resolve consultas ponta a ponta em live chat, e-mail, WhatsApp, SMS, telefone e Slack, com API própria ([fin.ai/pricing](https://fin.ai/pricing/), [salesforce.com press release](https://www.salesforce.com/news/press-releases/2026/06/15/salesforce-signs-definitive-agreement-to-acquire-fin/)). Funciona *dentro* do Intercom ou como camada em cima de outro helpdesk ("Fin over any helpdesk").

**Como é treinado. [FATO]** Conhecimento vem de conteúdo ingerido (help center, sites, snippets, PDFs) mais camadas de configuração comportamental: *Guidance*, *Tasks* e *Actions*. A página de preços lista Copilot, Operator e analytics como camadas separadas.
**[NÃO VERIFICADO]** Não consegui abrir o artigo de help específico de "Guidance and Tasks" (retornou 404 no fetch); a descrição acima vem da página de preços e do blog oficial.

**Promessa de resolução. [FATO]** O blog oficial *From resolutions to outcomes* cita **taxa média de resolução de 76%** ([intercom.com/blog](https://www.intercom.com/blog/from-resolutions-to-outcomes-evolving-how-fin-delivers-value/)).
**[FATO-2ª]** Materiais de terceiros citam 67% de média sobre 7.000+ clientes e 40M+ conversas, e uma "Performance Guarantee" de US$ 1M atrelada a um piso de 65% para contas qualificadas ([callsphere.ai](https://callsphere.ai/blog/vw1b-intercom-fin-ai-67-percent-resolution)).
**[FATO-2ª / contraditório]** Uma análise independente afirma que a taxa em produção fica em **45–53%**, não os 76% anunciados ([clonedesk.ai](https://clonedesk.ai/blog/intercom-fin-limitations)).
**[INFERÊNCIA]** A divergência 45–76% não é ruído: é a diferença entre *"conversas em que o Fin entrou"* e *"conversas totais do canal"*, e entre bases de conhecimento maduras e imaturas. Qualquer número de resolução sem denominador declarado é inútil.

**Como cobra. [FATO]** Página oficial de preços ([fin.ai/pricing](https://fin.ai/pricing/)):
- Resolution — **US$ 0,99**
- Procedure handoff — **US$ 0,99**
- Disqualification — **US$ 0,99**
- **Lead qualification — US$ 9,99**
- Mínimo de **50 outcomes/mês**
- Dentro do Intercom, some **US$ 29 por assento de helpdesk/mês**
- Copilot: **US$ 35 por usuário/mês**
- Pro: a partir de **US$ 99/mês**
- Voz: preço sob consulta **[FATO-2ª]** ([featurebase.app](https://www.featurebase.app/blog/fin-ai-pricing))
- Sem taxa de setup/integração/plataforma; trial de 14 dias com outcomes ilimitados

**Definição de resolução — a mais explícita do mercado. [FATO]** ([intercom.com/help](https://www.intercom.com/help/en/articles/8205718-fin-resolutions)):
> *"A resolution is a type of outcome that is counted when, following Fin's last answer in a conversation, the customer either confirms the answer was satisfactory (confirmed resolution), or exits the conversation without requesting further assistance (assumed resolution)."*

Não conta: resposta a saudação sem conteúdo; pergunta esclarecedora sem resposta do cliente; e **se o cliente volta pedindo mais ajuda, a cobrança anterior é revertida**.

---

### 2.2 Zendesk AI agents (Ultimate + Forethought)

**O que faz. [FATO]** Duas camadas: *Essential* (incluída nos planos Suite, deflection básica) e *Advanced* (agente autônomo cobrado por resolução), esta última construída sobre a aquisição da Ultimate. Com a Forethought, entram agentes de resolução (Solve), triagem (Triage), assistência ao humano (Assist) e descoberta de lacunas de conhecimento (Discover) **[FATO-2ª]** ([eesel.ai](https://www.eesel.ai/blog/forethought-review)).

**Como cobra — e como define resolução. [FATO]** ([support.zendesk.com](https://support.zendesk.com/hc/en-us/articles/5352026794010-About-automated-resolutions-for-AI-agents)):
- *"Automated resolutions are the unit of measurement used for calculating and billing your account for AI agent usage"*
- AI agents (messaging e e-mail): conta quando há pelo menos um *use case* identificado com resposta fornecida **e** a verificação por LLM confirma que o cliente ficou satisfeito sem escalação
- Legacy messaging: 72 horas de inatividade com feedback positivo ou sem feedback, e resposta confirmada como relevante
- Legacy autoreplies: usuário clica no artigo sugerido **e** o ticket é resolvido antes de resposta humana
- **Não conta:** Answer Bot for Slack, Article Recommendation API, recomendações para agentes humanos, testes no Admin Center, ambientes sandbox

**[INFERÊNCIA]** A Zendesk é o único fornecedor que documentou explicitamente uma *verificação por LLM* como pré-requisito de cobrança. Isso é, ao mesmo tempo, o maior avanço de honestidade e o maior risco de disputa contratual do modelo — o juiz do que você paga é um modelo do próprio fornecedor.

**Preço. [FATO-2ª]** ~US$ 2 por automated resolution em pay-as-you-go, ~US$ 1,50 com volume comprometido; Suite a partir de US$ 55/agente/mês (anual); Copilot ~US$ 50/agente/mês ([eesel.ai](https://www.eesel.ai/blog/understanding-zendesk-ai-pricing-a-complete-pay-per-resolution-guide), [voiceflow.com](https://www.voiceflow.com/blog/zendesk-ai-agents)). **Não verificado em fonte primária.**

---

### 2.3 Sierra

**O que faz. [FATO]** Plataforma de agentes de CX fundada por Bret Taylor. Arquitetura "Agent OS": abstrações modulares de tarefa, orquestração e roteamento automáticos, **supervisores em paralelo** revisando cada resposta ([sierra.ai/blog/constellation-of-models](https://sierra.ai/blog/constellation-of-models)).

> **[FATO]** *"agents built on Sierra are assembled using 15+ frontier, open-weight, and proprietary models, depending on the job to be done."*

Modelos escolhidos por tarefa: baixa latência para gestão de pedidos, alta precisão para classificar comportamento suspeito, contexto longo para conteúdo denso, modelos especializados em tom. Failover automático entre provedores para tarefas críticas, monitorando latência, taxa de erro e timeouts.

**Agent SDK. [FATO-2ª]** Metas declarativas, guardrails determinísticos, skills componíveis (triage, respond, confirm) e CI/CD via GitHub Actions ([sierra.ai/product/agent-sdk](https://sierra.ai/product/agent-sdk)).

**Como cobra. [FATO]** Outcome-based: paga-se quando o agente atinge um desfecho pré-definido (resolução, retenção de cancelamento, transação concluída). Escalações normalmente não geram cobrança.
**[FATO-2ª]** ~US$ 1,50 por interação resolvida; taxa negociada caso a caso e não publicada ([valueaddvc.com](https://valueaddvc.com/blog/how-does-sierra-ai-make-money-outcome-based-pricing-enterprise-agents-and-the-business-model-breakdown), [coworker.ai](https://coworker.ai/blog/sierra-ai-pricing)).

**Contribuição técnica pública relevante. [FATO]** A Sierra mantém o **τ-bench / τ²-bench**, benchmark de agente de atendimento com domínios *retail*, *airline* e *telecom*, onde o agente recebe um toolset e um **documento de política** e precisa executar o pedido do usuário respeitando a política ([github.com/sierra-research/tau2-bench](https://github.com/sierra-research/tau2-bench)).
**[INFERÊNCIA]** Isso é o mais próximo de um "padrão de eval de agente de atendimento" que existe hoje, e é onde o ChatSPX deveria se medir se quiser vender confiabilidade em vez de demo.

---

### 2.4 Decagon

**O que faz. [FATO]** Plataforma agêntica de CX centrada em **AOPs (Agent Operating Procedures)** — linguagem natural para descrever o procedimento, com validações críticas executadas em **código** ([decagon.ai/product/aop](https://decagon.ai/product/aop), [decagon.ai/resources/why-we-built-aop](https://decagon.ai/resources/why-we-built-aop)):
> *"AOPs combine the power and flexibility of natural language with the precision and rigor of code."*
> *"executing key validation steps in code — to ensure that sensitive actions, such as processing refunds or verifying customer identities, are handled securely."*

Complementos: **Watchtower** (QA always-on em produção) e **Simulations** (rodar lotes de simulações, ajustar AOP/base de conhecimento, re-rodar para validar) ([decagon.ai/resources/decagon-simulations](https://decagon.ai/resources/decagon-simulations)).

**Como cobra — e por que rejeita o modelo por resolução. [FATO]** Post oficial ([decagon.ai/blog/pricing-ai-agents](https://decagon.ai/blog/pricing-ai-agents)):
- Oferece **per-conversation** (taxa fixa por conversa, desconto por volume) e **per-resolution** (taxa maior, sem custo em escalação)
- Critica o per-resolution em três frentes: definição ambígua — *"If a frustrated customer stops responding, does that count as resolved?"* —, falta de transparência que gera renegociação constante, e incentivo desalinhado a "resoluções parciais"
- *"A vast majority of our customers gravitate towards per-conversation pricing"*

**[FATO-2ª]** Taxa de plataforma ~US$ 50 mil/ano cobrindo canais, integrações, AOPs, Watchtower, testes e analytics; ~US$ 0,99 por conversa; ACV mediano ~US$ 386 mil (faixa US$ 95 mil–590 mil+) ([eesel.ai](https://www.eesel.ai/blog/decagon-pricing), [quiq.com](https://quiq.com/blog/decagon-pricing/)). **Não verificado em fonte primária.**

**[INFERÊNCIA]** O argumento da Decagon é o melhor contra-argumento público ao modelo Fin, e vindo de um concorrente direto tem peso: a definição de resolução é o *ponto de captura* do modelo — quem escreve a definição escreve a fatura.

---

### 2.5 Ada (ada.cx)

**O que faz. [FATO]** Unified Reasoning Engine, lançado em fevereiro de 2026, patent-pending: uma única "IA cérebro" aplicando as mesmas políticas e conhecimento em voz, chat e e-mail, em vez de árvores separadas por canal ([ada.cx](https://www.ada.cx/media-center/press-release/ada-launches-industrys-first-unified-reasoning-engine/)). Arquitetura de **raciocínio duplo**: respostas imediatas para consultas simples e processamento em background para tarefas multi-passo, sem travar a conversa.

**Como é treinado. [FATO]** Responde a partir de artigos de conhecimento ingeridos: bases conectadas, crawl do site público, artigos autorados na Ada e push via Knowledge API. Usa contexto compartilhado do cliente, lógica de negócio, políticas, SOPs e APIs, com múltiplas camadas de salvaguarda.

**Promessa. [FATO-2ª]** Ada anuncia até **83%** de automated resolution ([getmacha.com](https://www.getmacha.com/blog/ada-ai-complete-guide)).

**Como cobra. [FATO-2ª]** Não publica preço. Estimativas: início ~US$ 30 mil/ano, US$ 1–3,50 por resolução, contratos enterprise US$ 100 mil–300 mil+/ano. **Mudou de outcome-based para conversation-based** depois de descobrir que clientes enterprise preferem custo previsível atrelado a volume ([featurebase.app](https://www.featurebase.app/blog/ada-cx-pricing), [corepiper.com](https://corepiper.com/blog/ada-ai-review-2026-pricing-worth-it/)).

**[INFERÊNCIA]** Ada foi quem **popularizou** a métrica "Automated Resolution" contra "deflection" — e é quem **abandonou** o preço por resolução. Isso reforça a tese da Decagon: a métrica é boa para medir, ruim para faturar.

---

### 2.6 Forethought (agora dentro da Zendesk)

**[FATO]** Zendesk assinou acordo definitivo em 11/03/2026 e concluiu a aquisição ([zendesk.com](https://www.zendesk.com/newsroom/press-releases/zendesk-completes-acquisition-of-forethought/)).
**[FATO-2ª]** Valor acima de US$ 200 milhões, maior aquisição da Zendesk em duas décadas; disponível como add-on a partir de 04/06/2026 ([computerweekly.com](https://www.computerweekly.com/news/366639959/Zendesk-to-acquire-Forethought-in-major-agentic-AI-play), [corebee.ai](https://corebee.ai/blog/zendesk-forethought-acquisition-2026)).

Produtos: **Solve** (resolução autônoma em chat, e-mail e voz, treinado em tickets históricos + help center), **Triage** (roteamento), **Assist** (copiloto), **Discover** (lacunas de conhecimento). **[FATO-2ª]**

Preço não publicado; três tiers (Basic, Professional, Enterprise) todos por cotação, tipicamente volume mensal de tickets ou conversas automatizadas. **[FATO-2ª]**

---

### 2.7 Salesforce Agentforce

**Como cobra. [FATO]** ([help.salesforce.com](https://help.salesforce.com/s/articleView?id=004811240&language=en_US&type=1)):
- **Flex Credits: US$ 500 por 100.000 créditos**
- Cada ação consome **20 Flex Credits = US$ 0,10 por ação**
- Modelo alternativo: **US$ 2 por conversa**
- Clientes Enterprise Edition ou superior recebem 100.000 Flex Credits via Salesforce Foundations
- Modelo flexível introduzido em **15/05/2025**, substituindo o preço fixo de US$ 2/conversa
> *"Flex Credits ensure you only pay for the actions Agentforce performs, such as updating customer records, automating workflows, or resolving cases."*

**[FATO-2ª]** Ação de voz custa 30 créditos (US$ 0,15); em sandbox 16 e 24 créditos. Uma ação cobre até **10.000 tokens**; acima disso, é cobrada como múltiplas ações (15.000 tokens = 2 ações = US$ 0,20) ([agencyq.com](https://www.agencyq.com/insights/article/agentforce-flex-credits-real-cost-math), [jitendrazaa.com](https://www.jitendrazaa.com/blog/salesforce/salesforce-agentforce-credits-cost-model-complete-guide-2026/)).

**[INFERÊNCIA]** O Agentforce é o único que cobra por **passo de raciocínio**, não por desfecho. Isso torna o custo de um agente verboso (que chama 8 tools antes de responder) 8× o de um agente enxuto — um incentivo econômico direto a *engenharia de agente*, não a marketing de agente. É o modelo mais alinhado com o custo real de inferência e o mais difícil de orçar.

---

### 2.8 HubSpot Breeze Customer Agent

**Como cobra. [FATO]** ([hubspot.com/company-news](https://www.hubspot.com/company-news/hubspots-customer-agent-and-prospecting-agent-now-you-pay-when-the-task-is-complete)):
- **Customer Agent: US$ 0,50 por conversa resolvida (50 créditos HubSpot)** — antes era US$ 1,00 cobrado independentemente do desfecho
- **Prospecting Agent: US$ 1,00 por lead recomendado para abordagem (100 créditos)** — antes era mensalidade recorrente por contato inscrito
- Vigência: **14 de abril de 2026**
- Justificativa oficial: *"Outcome-based pricing removes that risk. You pay when it works, full stop."*
- Números citados pela HubSpot: Customer Agent resolve **65% das conversas** e reduz o tempo de resolução em **39%**

**[FATO-2ª]** Créditos inclusos: 500 (Starter), 3.000 (Professional), 5.000 (Enterprise); crédito avulso a US$ 10 por 1.000. Exige assento Service Hub Pro/Enterprise a partir de US$ 90/assento/mês mais onboarding ([resolve247.ai](https://resolve247.ai/blog/hubspot-breeze-pricing-change/), [fastslowmotion.com](https://www.fastslowmotion.com/hubspot-breeze-pricing/)).

**[INFERÊNCIA]** US$ 0,50 é hoje o **piso público** do mercado de agente de atendimento entre grandes plataformas. É a referência a bater se o ChatSPX for precificar IA por unidade.

---

### 2.9 Freshworks Freddy AI Agent

**[FATO-2ª]** ([eesel.ai](https://www.eesel.ai/blog/freshdesk-freddy-ai-pricing)):
- Freshdesk Classic, AI Agent de e-mail: **US$ 49 por 100 sessões ≈ US$ 0,49/sessão**
- Freshdesk Omni, AI Agent de web chat (Freshbot): **≈ US$ 0,10/sessão**
- Primeiras **500 sessões incluídas**

**Ponto importante: a unidade é *sessão*, não resolução.** **[INFERÊNCIA]** Isso muda a economia por completo — você paga mesmo quando o bot falha. Em compensação, é o preço unitário mais barato da tabela, e para chat de site (US$ 0,10) é uma ordem de grandeza abaixo do Fin.

**[NÃO VERIFICADO]** Não confirmei esses valores na página oficial de preços da Freshworks.

---

### 2.10 Tidio Lyro

**Como cobra. [FATO]** ([tidio.com/pricing](https://www.tidio.com/pricing/)):
- Starter US$ 24,17/mês (100 conversas faturáveis; inclui 50 conversas Lyro, uma única vez)
- Growth a partir de US$ 49,17/mês
- Plus a partir de US$ 300/mês + uso
- Premium sob consulta, **com "Guaranteed 50% Lyro AI resolution rate"**
- Lyro standalone a partir de **US$ 32,50/mês para 50 conversas de IA**
- Modelo de "conversas faturáveis": só conta interação que recebe resposta de agente humano

**Promessa. [FATO-2ª]** Lyro anuncia **67% de resolução**; análises independentes reportam **40–60%** na prática ([myaskai.com](https://myaskai.com/blog/tidio-ai-complete-guide-2026)).

**[INFERÊNCIA]** O Tidio é o competidor mais próximo do ChatSPX em perfil de cliente (PME, chat de site, preço acessível) — e o "guaranteed 50% resolution rate" no tier caro é a jogada comercial mais copiável do estudo inteiro: transformar o medo do comprador ("e se não funcionar?") em cláusula contratual.

---

### 2.11 Crisp (MagicReply / Hugo)

**[FATO-2ª]** Planos 2026: Free (US$ 0), Mini (US$ 45/mês), Essentials (US$ 95/mês), Plus (US$ 295/mês), Enterprise (custom). MagicReply e cenários de chatbot ficam nos tiers superiores. IA limitada a 50 usos/mês no Essentials; uso ilimitado só no Plus. **Hugo** é o agente autônomo, com claim de resolver até 60% dos tickets a ~US$ 0,05 cada, empacotado nos planos pagos sem SKU próprio ([myaskai.com](https://myaskai.com/blog/crisp-ai-complete-guide-2026), [featurebase.app](https://www.featurebase.app/blog/crisp-pricing)).

**[NÃO VERIFICADO]** Nenhum desses números foi confirmado em página oficial da Crisp.

**[INFERÊNCIA]** A Crisp é o único do grupo que mantém IA **empacotada** em assinatura fixa em vez de vender por unidade. Para PME brasileira que odeia conta variável, é o modelo mais fácil de vender — e é o modelo que o ChatSPX já pratica com o Captain.

---

### 2.12 Drift / Salesloft: o cadáver do "conversational marketing"

**[FATO-2ª]** Drift adquirido pela Salesloft em fev/2024, dobrado na Revenue Orchestration Platform; fusão com Clari em dez/2025; em **06/03/2026** Clari + Salesloft anunciam **sunset gradual do Drift**, com a **1mind** como sucessora exclusiva para clientes existentes. Sem data de EOL pública até mai/2026 ([eesel.ai](https://www.eesel.ai/blog/drift-ai), [wiserreview.com](https://wiserreview.com/blog/drift-alternatives/)).

**[INFERÊNCIA]** Este é o dado mais importante do estudo para o produto do ChatSPX. O Drift é o *ancestral direto* do modelo Leadster: substituir formulário estático por conversa proativa no site. Ele morreu não porque a ideia era ruim, mas porque **a camada de valor migrou do fluxo para o raciocínio**. Um widget que só faz pergunta-resposta scriptada, por melhor que converta, não sustenta preço em 2026.

---

### 2.13 Qualified Piper — o vizinho da Leadster no enterprise

**[FATO-2ª]** ([marketbetter.ai](https://marketbetter.ai/blog/qualified-review-2026/), [knock-ai.com](https://www.knock-ai.com/blog/qualified-pricing)):
- Piper engaja visitantes em tempo real por chat, **voz e vídeo**, faz follow-up por e-mail e agenda reuniões
- Preço de tabela ~US$ 68 mil/ano para 25 usuários; negociado tipicamente para US$ 40–50 mil; exige stack Salesforce (US$ 30–60 mil)
- Recursos: AI SDR Agent Studio, Piper Spotlight, segmentação de contas com *waterfall enrichment*, integrações com Salesforce e 20+ sistemas de GTM, roteamento avançado
- Limitação declarada: **inbound only** — converte os ~3% de visitantes que iniciam conversa e perde os 97% que saem em silêncio

**[INFERÊNCIA]** Piper é a Leadster com orçamento enterprise: mesma tese (conversa no site → lead qualificado → reunião), com enriquecimento de dados e agendamento nativos. O gap "97% saem em silêncio" é exatamente onde proatividade contextual (seção 7) vira produto.

---

### 2.14 Tabela comparativa consolidada

| Produto | O que é | Fonte de conhecimento | Unidade cobrada | Preço público | Promessa de resolução | Verificação de resolução |
|---|---|---|---|---|---|---|
| **Fin** (ex-Intercom) | Agente autônomo omnicanal + Copilot | Help center, sites, PDFs, snippets + Guidance/Tasks/Actions | Outcome (resolution / procedure handoff / disqualification / lead qualification) | **US$ 0,99** (US$ 9,99 lead qualification); mín. 50/mês; +US$ 29/assento; Copilot US$ 35/user **[FATO]** | 76% (blog oficial) **[FATO]**; 67% média e piso 65% garantido **[FATO-2ª]**; 45–53% em produção **[FATO-2ª contraditório]** | Confirmada ou presumida; reembolsa se cliente volta **[FATO]** |
| **Zendesk AI agents** | Essential (bundled) + Advanced (Ultimate) + Forethought | Help center, tickets históricos | Automated resolution | ~US$ 2 PAYG / ~US$ 1,50 comprometido **[FATO-2ª]** | Não publicada | **LLM verifica satisfação sem escalação** **[FATO]** |
| **Sierra** | Agent OS, 15+ modelos, supervisores paralelos | Conhecimento + políticas + skills componíveis | Outcome negociado | Não publicado; ~US$ 1,50 **[FATO-2ª]** | Não publicada | Definição contratual caso a caso **[FATO-2ª]** |
| **Decagon** | AOPs (NL + código) + Watchtower + Simulations | Base de conhecimento + AOPs + tools | **Conversa** (preferido) ou resolução | ~US$ 50k/ano plataforma + ~US$ 0,99/conversa **[FATO-2ª]** | Não publicada | Critica explicitamente a definição de resolução **[FATO]** |
| **Ada** | Unified Reasoning Engine (dual reasoning) | Bases conectadas, crawl do site, artigos Ada, Knowledge API **[FATO]** | **Conversa** (migrou de outcome) **[FATO-2ª]** | Não publicado; US$ 30k–300k/ano **[FATO-2ª]** | Até 83% **[FATO-2ª]** | — |
| **Forethought** | Solve / Triage / Assist / Discover | Tickets históricos + help center | Volume de tickets ou conversas | Não publicado **[FATO-2ª]** | Não publicada | — |
| **Agentforce** | Agentes no Salesforce | Data Cloud, Knowledge, Flows | **Ação** (20 Flex Credits) ou conversa | **US$ 0,10/ação**; US$ 2/conversa; US$ 500/100k créditos **[FATO]** | Não publicada | Cobra por passo, não por desfecho |
| **HubSpot Breeze** | Customer Agent + Prospecting Agent | Knowledge Base + CRM | **Conversa resolvida** / lead recomendado | **US$ 0,50** e **US$ 1,00** **[FATO]** | **65% de resolução, −39% no tempo** (oficial) **[FATO]** | Task completion |
| **Freshworks Freddy** | AI Agent (e-mail e chat) + Copilot | Base de conhecimento | **Sessão** | ~US$ 0,49/sessão e-mail; ~US$ 0,10/sessão chat; 500 inclusas **[FATO-2ª]** | Não publicada | Não verifica desfecho |
| **Tidio Lyro** | Agente para PME/e-commerce | Site, FAQ, produtos | Conversa Lyro | US$ 32,50/mês por 50 conversas; **50% garantido no Premium** **[FATO]** | 67% anunciado **[FATO-2ª]**; 40–60% real **[FATO-2ª]** | — |
| **Crisp (Hugo/MagicReply)** | Agente + sugestão de resposta | Help center + cenários | **Assinatura** (IA empacotada) | Plus US$ 295/mês (IA ilimitada) **[FATO-2ª]** | ~60% a ~US$ 0,05 **[FATO-2ª]** | — |
| **Drift/Salesloft** | Conversational marketing | Fluxos + playbooks | — | **Em sunset desde 03/2026** **[FATO-2ª]** | — | — |
| **Qualified Piper** | AI SDR inbound (chat, voz, vídeo) | CRM + enriquecimento | Contrato anual | ~US$ 40–68 mil/ano **[FATO-2ª]** | — | Reuniões agendadas |
| **Chatwoot Captain** | Assistente + Copilot + Smart FAQs + Memories | Help center, docs, conversas | **Crédito de IA** | Startups US$ 19 (300 créditos), Business US$ 39 (500), Enterprise US$ 99 (800); overage **US$ 20/1.000 créditos** **[FATO]** | Não publicada | — |

---

## 3. Precificação por resolução: anatomia, críticas e efeito de mercado

### 3.1 Por que isso mudou o mercado

**[INFERÊNCIA fundamentada]** O modelo por resolução resolveu um problema comercial real: em 2023–2024, o comprador de chatbot pagava assinatura e assumia 100% do risco de o bot não funcionar. A promessa "pague quando funcionar" (HubSpot: *"You pay when it works, full stop"* **[FATO]**) eliminou a principal objeção de compra, e por isso foi copiada por Intercom, Zendesk, Sierra, Salesforce e HubSpot em menos de 18 meses.

O efeito colateral é que **a definição de "funcionou" virou uma cláusula contratual com preço**. Quem escreve a definição ganha dinheiro.

### 3.2 As quatro unidades de cobrança em disputa

| Unidade | Quem usa | Vantagem para o comprador | Risco para o comprador |
|---|---|---|---|
| **Por resolução / outcome** | Fin, Zendesk, Sierra, HubSpot | Só paga quando dá certo | A definição de "certo" é do vendedor; conta imprevisível |
| **Por conversa** | Decagon (preferido), Ada, Freshworks (sessão) | Previsível, fácil de orçar | Paga por falha |
| **Por ação / passo** | Salesforce Agentforce | Alinhado ao custo real de inferência | Impossível de orçar antes de rodar; penaliza agente verboso |
| **Por crédito / assinatura** | Chatwoot Captain, Crisp | Simples, cabe em plano SaaS | Cliente não sabe quanto custa cada interação |

### 3.3 As definições, lado a lado

| Fornecedor | Definição literal | Reversão? |
|---|---|---|
| **Fin** | *"following Fin's last answer... the customer either confirms the answer was satisfactory (confirmed resolution), or exits the conversation without requesting further assistance (assumed resolution)"* **[FATO]** | **Sim** — se o cliente volta pedindo mais ajuda, a cobrança é revertida **[FATO]** |
| **Zendesk** | Pelo menos um use case identificado com resposta, **mais verificação por LLM** de que o cliente ficou satisfeito sem escalação **[FATO]** | Não documentada |
| **Zendesk legacy (messaging)** | 72h de inatividade com feedback positivo ou sem feedback, resposta confirmada como relevante **[FATO]** | — |
| **HubSpot** | "conversa resolvida" / "lead recomendado para abordagem" **[FATO]** — critério operacional não detalhado no anúncio | Não documentada |
| **Decagon** | Se recusa a definir; aponta o buraco: *"If a frustrated customer stops responding, does that count as resolved?"* **[FATO]** | — |

### 3.4 As críticas ao modelo (documentadas)

1. **"Abandono = sucesso" é o vício central.** **[FATO]** A "assumed resolution" do Fin conta o cliente que *desistiu* como resolvido. A Decagon nomeia exatamente esse problema. Um cliente frustrado que fecha o widget e liga para o call center gera receita para o vendedor de IA e custo para o comprador — duas vezes.
2. **Renegociação permanente.** **[FATO]** Decagon: falta de transparência "causaria renegociações constantes sobre o significado de sucesso".
3. **Incentivo a resolução parcial.** **[FATO]** Decagon: o modelo "poderia incentivar resoluções parciais em vez de respostas de qualidade".
4. **Ada, que criou a bandeira, abandonou a cobrança.** **[FATO-2ª]** Migrou para conversation-based porque enterprise prefere previsibilidade.
5. **Custo imprevisível no orçamento anual.** **[FATO-2ª]** Recorrente em todas as análises: não dá para modelar a fatura sem dados de uso históricos.

### 3.5 A economia comparada (referência de custo)

| Item | Valor | Fonte |
|---|---|---|
| Chat humano por conversa | **US$ 6 a US$ 12** | **[FATO-2ª]** [unthread.io](https://unthread.io/blog/customer-support-cost-per-resolution-statistics/) |
| Contato humano (geral) | US$ 8 a US$ 15 | **[FATO-2ª]** idem |
| Resolução automatizada | **US$ 0,50 a US$ 2,00** | **[FATO-2ª]** idem |
| Diferencial típico citado | ~12× | **[FATO-2ª]** [eesel.ai](https://www.eesel.ai/blog/chatbot-vs-live-agent) |
| Modelo de melhor resultado em 2026 | Híbrido: IA resolve 60–70%, humano fica com empatia/julgamento | **[FATO-2ª]** [lorikeetcx.ai](https://www.lorikeetcx.ai/articles/contact-center-benchmarks) |

**[INFERÊNCIA]** Mesmo assumindo que os números secundários estejam inflados a favor da IA, a ordem de grandeza (1 dólar vs 10 dólares) é robusta e explica por que o mercado inteiro se moveu. Mas note: US$ 0,99 por resolução só é barato se comparado a **agente humano**; comparado ao **custo de inferência real** (centavos), a margem do fornecedor é enorme. Isso é o espaço onde um player self-hosted como o ChatSPX compete.

### 3.6 Cláusulas de defesa para quem compra (checklist)

**[INFERÊNCIA]** Derivado das definições acima. Se algum dia o ChatSPX comprar ou revender um agente de terceiro, ou se for negociar cláusula de garantia com cliente:

- [ ] Resolução exige **sinal positivo do cliente** (thumbs up, "obrigado", CSAT ≥ N), não apenas ausência de retorno
- [ ] **Janela de reabertura** definida (ex.: 7 dias). Retorno dentro da janela reverte a cobrança
- [ ] **Escalação para humano nunca é cobrada**
- [ ] Conversas de **teste/sandbox/QA** não contam (a Zendesk documenta isso; exija por escrito)
- [ ] Direito a **auditar a amostra** de conversas cobradas
- [ ] **Teto mensal** de outcomes com alerta em 80%
- [ ] Cláusula de **piso de qualidade** (CSAT do bot mínimo), não só piso de volume

---

## 4. Arquitetura de referência de um agente de IA de chat de site

Esta seção descreve o pipeline canônico que emerge da leitura cruzada de Fin, Zendesk, Sierra, Decagon e Ada, e do que já existe no Captain. Cada bloco traz: **o que é**, **o que o mercado faz**, **o estado do ChatSPX**.

```
                   ┌──────────────────────────────────────────────────────────────┐
                   │  INGESTÃO (offline / assíncrona)                             │
                   │  site crawl · help center · PDF · Notion/Drive · tickets     │
                   │  históricos · APIs de catálogo                               │
                   └───────────────┬──────────────────────────────────────────────┘
                                   ▼
                   ┌──────────────────────────────────────────────────────────────┐
                   │  NORMALIZAÇÃO → CHUNKING → CONTEXTUALIZAÇÃO → EMBEDDING      │
                   │  vector store (pgvector/HNSW) + índice lexical (tsvector/BM25)│
                   └───────────────┬──────────────────────────────────────────────┘
                                   ▼
  visitante ──►  ┌─────────────────────────────────────────────────────────────────┐
   (widget)      │  RUNTIME DO AGENTE                                              │
                 │  1. guardrail de ENTRADA (PII, injection, escopo)               │
                 │  2. roteador / classificador de intenção                        │
                 │  3. recuperação HÍBRIDA (vetor + lexical) → fusão RRF → rerank  │
                 │  4. loop de raciocínio + TOOLS (consultar pedido, agendar, ...) │
                 │  5. geração ancorada (grounding) + CITAÇÃO de fonte             │
                 │  6. guardrail de SAÍDA / SUPERVISOR (política, tom, fato)       │
                 │  7. decisão: responder · perguntar · HANDOFF                    │
                 └───────┬──────────────────────────────┬──────────────────────────┘
                         ▼                              ▼
              ┌────────────────────┐        ┌────────────────────────────────┐
              │ MEMÓRIA            │        │ HANDOFF COM DOSSIÊ             │
              │ episódica/perfil   │        │ resumo · motivo · time · fila  │
              └────────────────────┘        └────────────────────────────────┘
                         │
                         ▼
   ┌─────────────────────────────────────────────────────────────────────────────┐
   │  OFFLINE: EVAL (LLM-as-judge + gates determinísticos) · SIMULAÇÕES ·         │
   │  QA de produção · detecção de lacuna de conhecimento · observabilidade/custo │
   └─────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Ingestão de conteúdo

**Mercado. [FATO]** Ada ingere: bases de conhecimento conectadas, **crawl do site público**, artigos autorados na própria Ada, e **push via Knowledge API** ([ada.cx](https://www.ada.cx/media-center/press-release/ada-launches-industrys-first-unified-reasoning-engine/)). Forethought treina em **tickets históricos** além do help center **[FATO-2ª]**. Fin ingere help center, sites, PDFs e snippets **[FATO]**.

**ChatSPX. [CÓDIGO]** `Captain::Document` (`enterprise/app/models/captain/document.rb`) suporta três origens:
- URL com crawl (`Captain::Documents::CrawlJob`, com `FirecrawlService` e `SimplePageCrawlService`)
- **PDF anexado** (`has_one_attached :pdf_file`, limite de 10 MB, validação de content-type)
- **Conteúdo inline** colado pelo operador (sentinela `TEXT:` no `external_link`, não passa por crawl)

Limite de 200.000 caracteres por documento e gate de plano (`ensure_within_plan_limit` contra `account.usage_limits[:captain][:documents]`).

**Gap. [INFERÊNCIA]** Não há conector nativo para Notion, Google Drive, Confluence nem ingestão de **tickets históricos resolvidos** como corpus (o `ConversationFaqService` gera FAQ de conversa, mas é outra coisa: gera Q&A, não indexa o ticket).

### 4.2 Chunking e contextualização

**Mercado / referência técnica. [FATO]** A Anthropic publicou o resultado que virou padrão de facto ([anthropic.com/news/contextual-retrieval](https://www.anthropic.com/news/contextual-retrieval)):

| Técnica | Taxa de falha de recuperação (top-20) | Redução |
|---|---|---|
| RAG tradicional (baseline) | 5,7% | — |
| Contextual Embeddings | 3,7% | **−35%** |
| Contextual Embeddings + Contextual BM25 | 2,9% | **−49%** |
| + Reranking (150 candidatos → top-20) | **1,9%** | **−67%** |

O mecanismo: antes de embutir o chunk, prefixa-se um contexto explicativo gerado por LLM ("Este trecho é de um SEC filing da ACME Corp no Q2 2023") — assim o chunk deixa de ser um fragmento órfão.

**ChatSPX. [CÓDIGO]** Implementado. `Captain::Llm::DocumentChunkingService` faz o chunking; `Captain::Llm::ContextualChunkService` gera o contexto por chunk (1 chamada LLM por chunk); a coluna `contextual_content` guarda o resultado e `embed_text` prefere ela ao conteúdo cru (`enterprise/app/models/captain/document_chunk.rb:94-96`). Há um interruptor de custo: `contextual_chunks_enabled?` em `assistant.rb:94-96` permite desligar via `config['contextual_chunks'] = false`.

**[INFERÊNCIA]** Isso coloca o ChatSPX **acima** da média de mercado nesse bloco específico. Poucos produtos de PME implementam contextual retrieval.

### 4.3 Vector store e recuperação

**ChatSPX. [CÓDIGO]** `captain_document_chunks` tem:
- `embedding :vector(1536)` com índice **HNSW** (`idx_cap_doc_chunks_embedding_hnsw`)
- `content_search :tsvector` com índice **GIN** (`idx_cap_doc_chunks_fulltext`)
- Busca híbrida real: `hybrid_search` combina `nearest_neighbors(:embedding, ..., distance: 'cosine')` com `websearch_to_tsquery` e funde os dois rankings por **Reciprocal Rank Fusion (RRF, k=60)** — `enterprise/app/models/captain/document_chunk.rb:44-92`
- Três modos de conhecimento por assistente: `faq` (padrão/legado), `chunks`, `hybrid` (`assistant.rb:80-90`)

**Gap. [CÓDIGO + INFERÊNCIA]** O próprio código deixa o TODO escrito:
> `# Ponto de extensão: aplicar um reranker (cross-encoder/Cohere) sobre o resultado.`

Ou seja: temos os dois primeiros degraus do gráfico da Anthropic (−49%) e **falta o terceiro** (−67%). O `fulltext_candidates` usa configuração `'simple'` do tsquery, sem stemming português — para pt-BR isso perde plural e conjugação.

### 4.4 Grounding e citação de fonte

**Mercado. [FATO]** Fin e Ada respondem apenas a partir do conteúdo ingerido, com citação. Ada aplica "múltiplas camadas de salvaguarda".

**ChatSPX. [CÓDIGO]** Existe, mas é **opt-in por flag**: `config['feature_citation']` liga um bloco de instruções no prompt exigindo citações numeradas no formato `[[n](URL)]`, tanto no copiloto quanto no agente (`enterprise/app/services/captain/llm/system_prompts_service.rb:91-100, 156-165`). O prompt do agente instrui: *"Do not use your own understanding and training data to provide an answer"*.

**[INFERÊNCIA]** A citação estar desligada por padrão é uma escolha defensável em WhatsApp (link numerado polui a mensagem), mas em **chat de site é o oposto**: a citação é o principal mecanismo de confiança e o antídoto barato contra o caso Air Canada (seção 9.1).

### 4.5 Guardrails

**Mercado. [FATO]** Sierra usa **supervisores em paralelo** revisando cada resposta gerada, verificando fatos, aplicando política e redirecionando conversas que saem do trilho ([sierra.ai](https://sierra.ai/blog/constellation-of-models)). Decagon executa as validações sensíveis (reembolso, verificação de identidade) **em código, não em prompt** ([decagon.ai](https://decagon.ai/resources/why-we-built-aop)).

**Open source. [FATO]** NeMo Guardrails (Apache 2.0, 6.923 estrelas em 11/08/2026 — verificado via API do GitHub) cobre rails de entrada, saída, diálogo e uso de tool via a DSL Colang ([github.com/NVIDIA-NeMo/Guardrails](https://github.com/NVIDIA-NeMo/Guardrails)). **[FATO-2ª]** Latência de 15–60 ms p50 com classificador pequeno co-localizado; o projeto carrega disclaimer de beta ([spheron.network](https://www.spheron.network/blog/nemo-guardrails-production-deployment-llm-gpu-cloud/)). **[FATO-2ª]** Llama Guard 3 é classificador aberto de 8B com taxa de falso-positivo ~1/3 da do GPT-4 no benchmark publicado pela Meta ([cowork.ink](https://cowork.ink/blog/ai-agent-guardrails/)).

**ChatSPX. [CÓDIGO]** Guardrails existem como **campo de prompt**, não como camada executável: `captain_assistants.guardrails :jsonb` e `response_guidelines :jsonb` entram no `prompt_context` (`assistant.rb:171-187`) e são renderizados no template Liquid. Não há supervisor de saída, nem classificador, nem validação determinística pré-ação.

**[INFERÊNCIA]** Este é o **maior gap arquitetural** do ChatSPX frente a Sierra/Decagon. Guardrail em prompt é sugestão; guardrail em código é garantia. A boa notícia: já existe um precedente no repo — o `Captain::EpisodeGateService` (seção 11.6) faz exatamente asserts determinísticos, só que **depois** do fato, em modo eval. A mesma lógica movida para *antes do envio* vira supervisor.

### 4.6 Tools / function calling

**Mercado. [FATO]** Chatwoot upstream documenta Custom Tools como endpoints HTTP com timeout de **30 segundos** e headers de contexto `X-Chatwoot-Account-Id`, `X-Chatwoot-Conversation-Id`, `X-Chatwoot-Contact-Email` **[FATO-2ª]** ([deepwiki](https://deepwiki.com/chatwoot/chatwoot/9.1-captain-ai-system), [chatwoot.com/blog](https://www.chatwoot.com/blog/captain-custom-tools)).

**ChatSPX. [CÓDIGO]** Dois caminhos:
1. **Built-in**, declarados em `config/agents/tools.yml` (**22 tools**) e resolvidos por convenção `Captain::Tools::{PascalCase(id)}Tool` (`enterprise/app/models/concerns/captain_tools_helpers.rb:24-27`)
2. **Custom**, tabela `captain_custom_tools` com `endpoint_url`, `http_method` (GET/POST), `auth_type` (none/bearer/basic/api_key), `param_schema` validado por JSON Schema, `request_template`/`response_template` e flag `copilot_only`. Validação de destino via `Concerns::SafeEndpointValidatable` (anti-SSRF).

As 22 tools built-in (fato verificado em `config/agents/tools.yml`):

| Categoria | Tools |
|---|---|
| Conhecimento | `faq_lookup`, `search_knowledge` |
| Conversa | `add_private_note`, `add_label_to_conversation`, `update_priority`, `resolve_conversation`, `atualizar_resumo`, `registrar_observacao`, `registrar_assunto` |
| Contato/CRM | `add_contact_note`, `salvar_info_lead` |
| Roteamento | `handoff`, `transferir_para_agente` |
| Follow-up | `programar_followup` |
| Voz | `responder_em_audio` (ElevenLabs) |
| Verticais imobiliário (Vista/Tozi) | `buscar_imovel`, `buscar_empreendimento`, `enviar_fotos_imovel`, `enviar_localizacao_imovel` |
| Localização (Google) | `enviar_localizacao`, `buscar_lugar`, `buscar_localizacao` |

**[INFERÊNCIA]** 7 das 22 tools são **verticais de um cliente só** (imobiliária Tozi, cidade de Sinop). Isso é dívida de produto: elas estão no catálogo global, aparecem para toda conta, e o `tools.yml` é o registro único. Não invalida a arquitetura — o mecanismo de custom tools é o caminho certo — mas mostra que o sistema foi endurecido por um caso de uso.

**Gap crítico. [CÓDIGO]** Nenhuma tool de **e-commerce/pedido/pagamento** (consultar status de pedido, rastrear entrega, emitir 2ª via de boleto) nem de **agendamento em calendário**. Para chat de site B2C, essas são as duas tools que mais deflectem volume.

### 4.7 Memória

**Mercado. [FATO]** Zendesk CX Trends 2026: **83% dos líderes de CX** dizem que "memory-rich AI agents are the key to truly personalized customer journeys" ([cxtrends.zendesk.com](https://cxtrends.zendesk.com/)). Chatwoot upstream vende "Memories" como pilar do Captain ([chatwoot.com/captain](https://www.chatwoot.com/captain)).

**ChatSPX. [CÓDIGO]** Três mecanismos distintos:
- `feature_memory` no `config` do assistente
- `Captain::Llm::ContactNotesService` e `ContactAttributesService` — extraem notas e atributos do contato a partir da conversa e gravam no CRM (prompts em `system_prompts_service.rb:61-87`)
- **Carryover entre episódios**: `ConversationEvalService#carryover_context` recupera o resumo dos até 3 atendimentos anteriores do mesmo contato para o juiz não marcar falso "ignorou contexto" (`enterprise/lib/captain/conversation_eval_service.rb`)
- Tool `atualizar_resumo` mantém um "resumo vivo do atendimento" em custom attribute

**[INFERÊNCIA]** A memória do ChatSPX é **de avaliação e de CRM**, não de runtime: o carryover alimenta o juiz, não o agente. O agente recebe `custom_attributes` do contato no `build_state` (`agent_runner_service.rb:200-210`), então há memória de perfil — mas não há recuperação semântica de conversas passadas ("da última vez você me disse X").

### 4.8 Handoff para humano com contexto

**ChatSPX. [CÓDIGO]** É o bloco mais maduro do sistema. `Captain::Conversation::HumanHandoffService` (`enterprise/app/services/captain/conversation/human_handoff_service.rb`):
- **Idempotente** — se `custom_attributes['aguardando_humano_desde']` já existe, não refaz (evita dossiê duplicado)
- Cria **nota privada com o dossiê** antes de passar
- `bot_handoff!` abre a conversa e dispara eventos
- Resolve o time: `team_id` explícito validado na conta (proteção contra alucinação de ID pelo LLM) → fallback para `config['team_id']` do agente → nunca fica sem fila
- Aciona `Spx::Distribuicao::DistribuirService` (rodízio) quando o time tem política
- Dispara mensagem de fora-de-horário quando aplicável, exceto em conversa de campanha
- **Modelo A**: a IA **não solta** a conversa no handoff — segue respondendo até um humano puxar a atribuição

A descrição da `HandoffTool` merece destaque porque documenta um aprendizado real de produto:
> *"Gatilho POSITIVO: o handoff não é só pra 'quando você não consegue' — é o passo normal de passar um lead qualificado pra uma pessoa fechar. A descrição antiga ('when unable to assist further') fazia a IA quase nunca chamar o tool [...] então nenhum lead chegava ao humano."*

**[INFERÊNCIA]** Esse é um insight que não está em nenhum blog de fornecedor e vale mais que metade dos números de marketing deste relatório: **a descrição da tool de handoff determina a taxa de handoff**. Uma IA que atende bem nunca se considera "incapaz".

### 4.9 Avaliação, simulação e test-gate

**Mercado. [FATO]** Decagon: Watchtower (QA always-on em produção) + Simulations (lotes de simulação → ajusta AOP/conhecimento → re-roda para validar) ([decagon.ai/resources/decagon-simulations](https://decagon.ai/resources/decagon-simulations)); *"The future of AI agents is test-driven"*. Sierra: τ²-bench com política declarada e tool-calling dual ([github.com/sierra-research/tau2-bench](https://github.com/sierra-research/tau2-bench)).

**ChatSPX. [CÓDIGO]** Sistema de eval próprio, e é bom:
- `Captain::ConversationEpisode` — segmenta a conversa em **episódios** (unidade de atendimento), não avalia o blob inteiro
- `Captain::ConversationEvalService` — LLM-as-a-judge com schema estruturado (`ConversationEvalSchema`) devolvendo: `representatividade` (filtra ruído: interno/outra_empresa/bot/teste), `interesse`, `intencao`, `funil`, `conduzido_por`, `handoff_timing`, `nota` 0–10, `resumo`, `objecoes` e **auditoria resposta-a-resposta** (`respostas_problematicas`) com 16 categorias de falha: `alucinacao`, `info_incorreta`, `nao_respondeu_pergunta`, `narrou_ferramenta`, `tom_robotico`, `repeticao`, `exemplo_copiado`, `quebrou_regra`, `promessa_indevida`, `handoff_ausente`, `handoff_tardio`, `fora_horario_mal_tratado`, `contradisse_tool`, `nao_chamou_tool_obrigatoria`, `usou_tool_errada`, `ignorou_erro_da_tool`, `outro`
- O transcript entregue ao juiz **intercala as tool calls na posição cronológica** com args e resultado (`[TOOL nome args=... => resultado]`) — o juiz vê o que a ferramenta devolveu
- `Captain::EpisodeGateService` — **gates determinísticos de custo zero, no padrão τ-bench/BFCL**, com o comentário no código dizendo isso explicitamente: detecta (a) `contradisse_tool` — a busca devolveu resultados e a IA respondeu "não encontrei"; (b) `ignorou_erro_da_tool`; (c) `repeticao` literal (bot-loop)
- Chave e modelo de LLM **dedicados ao eval** (`EVAL_OPEN_AI_API_KEY`, `EVAL_OPEN_AI_MODEL`) para isolar custo, rate-limit e blast radius
- O eval **não consome cota do Captain** (o retorno omite a chave `:message` que o `BaseTaskService` usa para cobrar)
- `AgentRunnerService#run_raw` existe especificamente para callers de eval/test-gate inspecionarem tool_calls e handoffs crus

**[INFERÊNCIA]** Este bloco é **competitivo com Decagon Watchtower** em ambição e mais explícito em taxonomia de falha. O que falta é o outro lado: **simulação** (rodar personas sintéticas contra o agente antes do deploy) e **regressão automatizada em CI**.

### 4.10 Feedback loop / lacunas de conhecimento

**Mercado. [FATO]** Chatwoot upstream: "Smart FAQs — identifica lacunas de conhecimento detectando perguntas frequentes não documentadas" ([chatwoot.com/captain](https://www.chatwoot.com/captain)). Forethought: **Discover** faz o mesmo **[FATO-2ª]**.

**ChatSPX. [CÓDIGO]** `Captain::Llm::ConversationFaqService` + `FaqGeneratorService` + `PaginatedFaqGeneratorService` (para PDFs longos, por faixa de página, com flag `has_content`) geram FAQ a partir de conteúdo e de conversas. `Captain::RetriageService` re-classifica.

### 4.11 Observabilidade e custo

**ChatSPX. [CÓDIGO]** `Captain::Assistant::AgentRunnerService` instala instrumentação OpenTelemetry/**Langfuse** quando `ChatwootApp.otel_enabled?`, com trace name `llm.captain_v2` e atributos dinâmicos: `account_id` como user, e metadata `assistant_id`, `conversation_id`, `conversation_display_id`, `channel_type`, `source`, mais o input do trace. Há um callback que marca `credit_used = false` quando a run terminou em handoff (`write_credits_used_metadata`).

**[INFERÊNCIA]** O `credit_used` é, na prática, **o embrião de um modelo de cobrança por outcome**: já existe a decisão "esta run gerou valor ou foi handoff?" gravada no trace. Falta apenas materializar isso em contador de billing.

---

## 5. Métricas: o dicionário e os números públicos

### 5.1 Dicionário — as definições que o mercado confunde de propósito

| Métrica | Definição precisa | Armadilha |
|---|---|---|
| **Deflection rate** | % de **todos** os contatos de suporte (portfólio, todos os canais) que nunca chegaram a um humano | Métrica de portfólio. Não diz se o cliente foi ajudado |
| **Containment rate** | % das conversas **que entraram no canal automatizado** e terminaram nele | Métrica de canal. Denominador menor → número sempre maior |
| **Resolution rate** | % de conversas em que o problema foi efetivamente resolvido | Depende inteiramente da definição de "resolvido" (seção 3.3) |
| **Escalation rate** | % de conversas do bot que foram para humano | Complemento do containment; **baixo demais é sintoma ruim**, não bom |
| **CSAT do bot** | Satisfação medida só na coorte atendida pelo bot | Viés de sobrevivência: quem desistiu não responde pesquisa |
| **Hallucination rate** | % de respostas com afirmação não sustentada pela fonte | Quase nunca medida em produção; só em benchmark |
| **Cost per resolution** | Custo total (licença + inferência + humano) ÷ resoluções | Fornecedor conta só a própria taxa |
| **Time to first response** | Tempo até a primeira resposta | Com IA tende a zero e deixa de discriminar; migrar para *time to resolution* |
| **FCR (first contact resolution)** | Resolvido no primeiro contato, sem retorno em N dias | A janela N é o parâmetro que ninguém declara |

### 5.2 Tabela de números públicos, com fonte e grau de confiança

| Nº | Métrica | Valor | Fonte | Confiança |
|---|---|---|---|---|
| 1 | Resolução média do Fin | **76%** | [intercom.com/blog](https://www.intercom.com/blog/from-resolutions-to-outcomes-evolving-how-fin-delivers-value/) | **[FATO]** — dado do próprio fornecedor |
| 2 | Resolução do Fin (7.000+ clientes, 40M+ conversas) | 67% | [callsphere.ai](https://callsphere.ai/blog/vw1b-intercom-fin-ai-67-percent-resolution) | **[FATO-2ª]** |
| 3 | Piso garantido do Fin (Performance Guarantee US$ 1M) | 65% | idem | **[FATO-2ª]** |
| 4 | Resolução do Fin em produção (análise independente) | **45–53%** | [clonedesk.ai](https://clonedesk.ai/blog/intercom-fin-limitations) | **[FATO-2ª — contradiz #1]** |
| 5 | Resolução do HubSpot Customer Agent | **65%**, com **−39%** no tempo de resolução | [hubspot.com](https://www.hubspot.com/company-news/hubspots-customer-agent-and-prospecting-agent-now-you-pay-when-the-task-is-complete) | **[FATO]** |
| 6 | Automated resolution da Ada | até 83% | [getmacha.com](https://www.getmacha.com/blog/ada-ai-complete-guide) | **[FATO-2ª]** |
| 7 | Resolução do Lyro (anunciada) | 67% | [myaskai.com](https://myaskai.com/blog/tidio-ai-complete-guide-2026) | **[FATO-2ª]** |
| 8 | Resolução do Lyro (prática) | 40–60% | idem | **[FATO-2ª]** |
| 9 | Resolução garantida do Tidio Premium | **50%** (cláusula contratual) | [tidio.com/pricing](https://www.tidio.com/pricing/) | **[FATO]** |
| 10 | Hugo (Crisp) | ~60% a ~US$ 0,05 | [myaskai.com](https://myaskai.com/blog/crisp-ai-complete-guide-2026) | **[FATO-2ª]** |
| 11 | Deflection mediana tier-1 (enterprise) | 41,2%; top quartil 58,7% | [digitalapplied.com](https://www.digitalapplied.com/blog/customer-service-ai-agent-statistics-2026-data) citando Zendesk/Salesforce | **[FATO-2ª]** |
| 12 | Deflection por intenção | reembolso e reset de senha 70%+; reclamação nuançada <25% | idem | **[FATO-2ª]** |
| 13 | CSAT IA pura vs humano | 4,1/5 vs 4,3/5; fluxo híbrido reduz o gap a 0,05 ponto | idem | **[FATO-2ª]** |
| 14 | CSAT por intenção | reset de senha 4,41/5; status de reembolso 4,32/5; reclamação 3,34/5; disputa de cobrança 3,61/5 | idem | **[FATO-2ª]** |
| 15 | Piloto agêntico vs produção | 64% das equipes rodaram piloto em 2026; só **27%** têm ao menos um canal em produção plena | idem | **[FATO-2ª]** |
| 16 | Expectativa de resposta mais rápida | **88%** dos clientes | [cxtrends.zendesk.com](https://cxtrends.zendesk.com/) | **[FATO]** |
| 17 | Expectativa de 24/7 | **74%** dos consumidores | idem | **[FATO]** |
| 18 | Memória como chave de personalização | **83%** dos líderes de CX | idem | **[FATO]** |
| 19 | Abandono por questão não resolvida | **85%** dos líderes de CX confirmam | idem | **[FATO]** |
| 20 | Preferência por multimodal (texto+imagem+vídeo na mesma conversa) | **76%** dos consumidores | idem | **[FATO]** |
| 21 | Expectativa de explicação sobre decisão de IA | **95%** dos consumidores | idem | **[FATO]** |
| 22 | Aumento na demanda por transparência | **63%** dos clientes | idem | **[FATO]** |
| 23 | Falha de recuperação RAG: baseline → contextual → +BM25 → +rerank | 5,7% → 3,7% → 2,9% → **1,9%** | [anthropic.com](https://www.anthropic.com/news/contextual-retrieval) | **[FATO]** |
| 24 | Alucinação de modelos de fronteira (HHEM, sumarização) | 1,0–2,5% em 2026 (era 3–8% em 2023) | [suprmind.ai](https://suprmind.ai/hub/ai-hallucination-rates-and-benchmarks/) citando Vectara | **[FATO-2ª]** |
| 25 | τ-bench: melhor score histórico do board original | 69,2% retail / 46,0% airline (Claude 3.5 Sonnet 20241022) | [benchmarkingagents.com](https://benchmarkingagents.com/tau-bench/) | **[FATO-2ª]** |
| 26 | Custo de chat humano por conversa | US$ 6–12 | [unthread.io](https://unthread.io/blog/customer-support-cost-per-resolution-statistics/) | **[FATO-2ª]** |
| 27 | Custo de resolução automatizada | US$ 0,50–2,00 | idem | **[FATO-2ª]** |
| 28 | Klarna: volume da IA | 2,3M conversas/mês; 11min → <2min; ~US$ 40M/ano | [Forbes](https://www.forbes.com/sites/quickerbettertech/2025/05/18/business-tech-news-klarna-reverses-on-ai-says-customers-like-talking-to-people/) | **[FATO-2ª]** |

### 5.3 Números do mercado brasileiro (Leadster — fonte primária, e a melhor que existe em pt-BR)

**[FATO]** Panorama de Geração de Leads 2026 ([leadster.com.br/panorama-geracao-de-leads](https://leadster.com.br/panorama-geracao-de-leads/)) — base: **2.425 sites, 173,6 milhões de acessos, 3,4 milhões de leads, 17 segmentos**.

| Corte | Valor |
|---|---|
| **Conversão mediana** | **3,07%** (+0,09 p.p. vs 2025) |
| Alta performance | 7,90% |
| Baixa performance | 1,02% |
| **Melhores segmentos** | Jurídico 5,42% · Energia 5,33% · Seguros 5,10% · Financeiro 5,04% · Saúde 4,08% |
| **Piores segmentos** | Imóveis **1,32%** · Software 1,83% · Consultoria 1,71% |
| Por canal | Meta Ads 3,91% · Google Ads 3,41% · LinkedIn Ads 2,97% · Orgânico 2,39% · Direto 1,74% |
| Dispositivo | Mobile 3,37% (74,39% dos acessos) · Desktop 3,50% (25,61%) |
| B2B vs B2C | 2,53% vs 3,39% |
| Qualificação | **44,51%** dos leads de tráfego orgânico têm score alto |
| **Adoção de IA em geração de leads** | **6,60%** das empresas |
| Redirecionamento para WhatsApp | **75,96%** |
| Integração com CRM | **47,34%** |
| Tráfego vindo de assistentes de IA | 170,5 mil acessos (**0,10%** do total): ChatGPT 78,36% · Perplexity 8,42% · Gemini 5,87% |

**[INFERÊNCIA — três leituras que importam para o ChatSPX]**

1. **Apenas 6,60% das empresas brasileiras usam IA em geração de leads.** O mercado que a Leadster mede está praticamente virgem. A janela de diferenciação é agora e é ampla — não é um mercado onde "todo mundo já tem IA".
2. **75,96% redirecionam para WhatsApp.** No Brasil, o widget de site **não é o destino, é a rampa**. Qualquer IA de chat de site que não continue a conversa no WhatsApp está resolvendo o problema errado. Isso é uma vantagem estrutural do ChatSPX, que já é forte em WhatsApp.
3. **Imóveis converte 1,32%, o pior de 17 segmentos** — e é exatamente o vertical em que o Captain do ChatSPX foi endurecido (tools Vista/Tozi). Vender ganho de conversão nesse segmento é vender contra o pior benchmark do país, o que é bom argumento comercial e mau argumento de expectativa.

### 5.4 O caso contra deflection rate

**[FATO-2ª]** As críticas estão bem documentadas ([twig.so](https://www.twig.so/blog/deflection-rate-vanity-metric-cx-numbers-that-matter), [certainly.io](https://certainly.io/blog/cx-deflection-rate-myth-csat-tradeoff), [myaskai.com](https://myaskai.com/blog/containment-vs-deflection-vs-resolution)):
- *"Deflection rate measures how often a human is avoided. It does not measure whether the customer was helped."*
- *"A deflection number without an outcome number is a vanity metric."*
- *"many CX organisations are quietly trading 18 to 25 CSAT points for a containment number that looks great in a board pack"*
- Correção proposta: emparelhar com uma checagem de resolução ou CSAT **sobre a coorte deflectida**

### 5.5 O painel honesto — proposta

**[INFERÊNCIA]** Seis números, sempre juntos, sempre com denominador declarado:

| # | Métrica | Como calcular |
|---|---|---|
| 1 | **Resolução confirmada** | Conversas com sinal **positivo explícito** do cliente ÷ conversas atendidas pela IA |
| 2 | **Taxa de retorno em 7 dias** | Contatos "resolvidos" que voltaram com o mesmo assunto ÷ resolvidos. **É o antídoto ao vício "abandono = sucesso"** |
| 3 | **CSAT da coorte deflectida** | CSAT medido **só** em quem não falou com humano |
| 4 | **Escalation rate com timing** | % de handoff + distribuição `no_prazo` / `tardio` / `precisava_nao_fez` — o ChatSPX **já produz isso** no `ConversationEvalSchema` |
| 5 | **Findings por 100 respostas** | `respostas_problematicas` do eval, quebrado por categoria e severidade — proxy operacional de alucinação |
| 6 | **Custo total por resolução** | (inferência + infra + minutos de humano gastos em conversas escaladas) ÷ resoluções confirmadas |

---

## 6. IA do lado do ATENDENTE (agent-side / copiloto)

O lado do atendente é onde o ROI é mais fácil de provar e a régua de risco é mais baixa — o humano revisa antes de enviar.

### 6.1 O que o mercado vende

| Capacidade | Quem entrega | Preço quando destacado |
|---|---|---|
| Copiloto conversacional | Fin Copilot, Zendesk Copilot, Forethought Assist, Freddy Copilot, Chatwoot Captain Copilot | Fin **US$ 35/user/mês** (US$ 29 anual) **[FATO]**; Zendesk ~US$ 50/agente/mês **[FATO-2ª]** |
| Sugestão de resposta / rascunho | todos | incluso |
| Resumo de conversa | todos | incluso |
| Tradução instantânea | Chatwoot Captain **[FATO]** ([chatwoot.com/captain](https://www.chatwoot.com/captain)) | incluso |
| Ajuste de tom / expandir / encurtar | Intercom, Zendesk, Crisp MagicReply | incluso |
| **QA automático de 100% das conversas** | Zendesk QA (ex-Klaus) **[FATO-2ª]**, MaestroQA/Rippit **[FATO-2ª]** | add-on |

**[FATO-2ª]** Zendesk QA: *"AutoQA, which scores 100% of conversations across channels using out-of-the-box categories (tone, empathy, solution) plus custom prompt-based criteria"*; MaestroQA rebrandeou para **Rippit** em março de 2026 ([eesel.ai](https://www.eesel.ai/blog/customer-support-quality-assurance-tools), [solidroad.com](https://solidroad.com/resources/best-klaus-zendesk-qa-alternatives)).

**[FATO]** A Intercom cobra Copilot separado do agente autônomo e dá **10 conversas de Copilot grátis por mês** para cada assento Full ([fin.ai/pricing](https://fin.ai/pricing/)) — modelo de amostra grátis para criar hábito.

### 6.2 O que o ChatSPX tem — auditoria do copiloto

**[CÓDIGO]** `Captain::Copilot::ChatService` (`enterprise/app/services/captain/copilot/chat_service.rb`) arma **32 tools** para o copiloto:

| Grupo | Tools |
|---|---|
| Conhecimento | `SearchDocumentation`, `GetArticle`, `SearchArticles` |
| Conversa (leitura) | `GetConversation`, `GetConversationFull`, `SearchConversations`, `SearchMessages`, `GetConversationAnalysis` |
| Conversa (ação) | `AssignConversation`, `AddLabel`, `RemoveLabel`, `ChangeStatus`, `ChangePriority`, `SnoozeConversation`, `TransferToInbox`, `ResolveConversation`, `SendMessage`, `SendTemplate` |
| Contato | `GetContact`, `SearchContacts`, `GetContactConversations`, `UpdateContact`, `SetCustomAttributes`, `AddNoteToContact` |
| Operação/gestão | `GetAccountStats`, `GetAgentWorkload`, `GetTeamInfo`, `GetLabels`, `GetAgents`, `GetInboxInfo`, `GetCsatData` |
| Externo | `SearchLinearIssues` |

Além disso, custom tools da conta também ficam disponíveis ao copiloto.

**[CÓDIGO]** Streaming: o endpoint SSE `POST /api/v1/accounts/:account_id/captain/copilot_threads/:copilot_thread_id/stream` usa `ActionController::Live` com justificativa arquitetural registrada no próprio arquivo (ordem de token é requisito inegociável; SSE dá ordem de graça), com teto de duração, heartbeat de detecção de cliente morto, lock por thread e botão de parar determinístico.

**[CÓDIGO]** Frontend: `app/javascript/dashboard/components-next/ai-assistant/` tem 7 componentes Vue + 14 composables + 21 arquivos de spec (~4.550 linhas). Destaques:
- `useTypewriter`, `useCopilotStream`, `sseParser` — streaming com efeito de digitação
- `useSmartSuggestions` — banner proativo por prioridade: (1) cliente esperando > 5 min, (2) sentimento negativo em `additional_attributes.sentiment`, (3) thread longa > 10 mensagens; dismissível por conversa com TTL de 7 dias
- `useAITour`, `useCopilotShortcuts`, `useComposerInsert` (inserir resposta no compositor)
- **`utils/sanitizePII.js`** — sanitização de PII em duas camadas (front + backend `lib/captain/pii_sanitizer.rb`), com padrões brasileiros: **CNPJ, telefone BR, CPF, cartão com validação Luhn**, e-mail e CEP (estes dois desligados por padrão). O comentário do arquivo declara a filosofia: *"false-positive cost > false-negative cost in this domain"*

**[INFERÊNCIA]** O `sanitizePII.js` com CPF/CNPJ/Luhn é um diferencial genuíno para o mercado brasileiro que nenhum fornecedor internacional entrega pronto. É material de venda, não só de compliance.

**Gaps do copiloto. [INFERÊNCIA]**
- Não há **QA automático de 100% das conversas** exposto ao gestor. O motor existe (`ConversationEvalService` + `EpisodeGateService` produzem exatamente o que um AutoQA produz), mas está posicionado como eval interno, não como produto de gestão de qualidade.
- Não há ajuste de tom / expandir / encurtar como ação de um clique no compositor.
- Não há coaching por agente (score histórico por atendente ao longo do tempo).

---

## 7. IA do lado do MARKETING — o território da Leadster

### 7.1 O que a Leadster faz, verificado

**[FATO]** ([leadster.com.br/como-funciona](https://leadster.com.br/como-funciona/), [leadster.com.br/chatbot-leadster](https://leadster.com.br/chatbot-leadster/), [leadster.com.br/gere-leads-qualificados-com-chatgpt](https://leadster.com.br/gere-leads-qualificados-com-chatgpt/)):
- Chatbot de marketing que capta, qualifica e distribui leads 24h
- **Régua de qualificação** configurável: o cliente define o que é lead quente e monta perguntas/respostas de acordo
- **Lead Scoring** por critérios pré-determinados
- Personalização da abordagem por visitante usando ChatGPT — a própria Leadster afirma que **personalizar a comunicação aumenta a geração de leads em 202%**
- Fluxos e chamadas prontas, testadas, criados na plataforma com poucos cliques

### 7.2 O stack de marketing conversacional com IA (mercado)

| Função | O que é | Quem faz |
|---|---|---|
| **Qualificação automática** | IA conduz a conversa até extrair BANT/critérios e classifica | Leadster **[FATO]**, Qualified Piper **[FATO-2ª]**, Fin (outcome "lead qualification" a **US$ 9,99**) **[FATO]** |
| **Desqualificação** | Identificar e encerrar quem não é ICP — evita queimar o time comercial | Fin cobra "disqualification" como outcome próprio (US$ 0,99) **[FATO]** |
| **Scoring** | Pontuação por critérios / comportamento | Leadster **[FATO]**; 44,51% dos leads orgânicos com score alto **[FATO]** |
| **Roteamento inteligente** | Direcionar para o vendedor certo por região/produto/carga | Qualified (roteamento avançado) **[FATO-2ª]**; ChatSPX já tem `Spx::Distribuicao` **[CÓDIGO]** |
| **Agendamento** | Marcar reunião dentro da conversa | Piper agenda automaticamente **[FATO-2ª]**; Fin lista agendamento entre as ações |
| **Enriquecimento** | Completar dados da empresa a partir de e-mail/domínio | Piper: "waterfall enrichment" **[FATO-2ª]** |
| **Personalização por origem** | Abordagem muda por UTM, página, campanha, dispositivo | Leadster (personalização por visitante) **[FATO]** |

### 7.3 O gap que ninguém fechou

**[FATO-2ª]** A limitação declarada do Qualified: *"It converts the 3% of website visitors who start a conversation but misses the 97% who leave silently."*

**[INFERÊNCIA]** Este é o ponto de alavanca do produto. O widget clássico é **reativo**: espera o clique. A Leadster já resolve metade disso com chamada proativa configurada por página. A parte não resolvida por ninguém de forma convincente é a **proatividade contextual guiada por IA**: usar UTM + página + tempo na página + rolagem + histórico do contato para decidir *se*, *quando* e *com que frase* abordar — e aprender com o resultado. Isso é um problema de bandit/otimização em cima de um agente, não de fluxo.

### 7.4 O que o ChatSPX tem de marketing hoje

**[CÓDIGO]**
- `salvar_info_lead` — grava status do lead e descrição curta na conversa, marca follow-up; o `tools.yml` documenta um status `nao_qualificado` (histórico de commits confirma: *"status nao_qualificado no salvar_info_lead (triagem sem re-abordar)"*)
- `programar_followup` + `Captain::Conversation::FollowupJob` — cutucada programada se o cliente não responde; quando as cutucadas in-window esgotam, escala para humano via `HumanHandoffService`
- `ConversationEvalSchema` classifica **`funil`** em `lead_novo` / `qualificando` / `qualificado` / `handoff` / `frio` e **`interesse`** em `alto`/`medio`/`baixo`/`nenhum` — ou seja, **já existe scoring de lead por LLM**, só que dentro do eval e não exposto como produto
- `Spx::Distribuicao::DistribuirService` — roteamento com política de rodízio por time
- `state[:campaign]` no contexto do agente (`CAMPAIGN_STATE_ATTRIBUTES`) — o agente sabe de qual campanha veio o contato

**[INFERÊNCIA]** O ChatSPX tem **as peças de um produto de marketing conversacional já construídas e desconectadas**: scoring existe (no juiz), roteamento existe (na distribuição), follow-up existe (no job), status de lead existe (na tool). O que não existe é a **tela de marketing** que amarra isso: funil de leads do widget, taxa de qualificação por origem, e um agente que se comporta diferente conforme UTM/página.

---

## 8. Voz e multimodal em chat de site

### 8.1 Imagem enviada pelo visitante

**[FATO]** **Fin Vision** ([intercom.com/help](https://www.intercom.com/help/en/articles/10696494-how-fin-vision-understands-images)):
- Analisa screenshots, fotos e imagens de documentos (recibos, formulários) em chat e e-mail
- Usa LLM multimodal para gerar **descrição textual estruturada**, que é adicionada ao histórico da conversa
- **Sem configuração e sem custo adicional**
- Os modelos de visão são **explicitamente instruídos a não extrair PII** (números de cartão, CVV, documentos)
- Imagens armazenadas temporariamente e deletadas depois

**[FATO]** Zendesk CX Trends 2026: **76% dos consumidores escolheriam a empresa que permite texto, imagens e vídeo na mesma conversa sem reiniciar** ([cxtrends.zendesk.com](https://cxtrends.zendesk.com/)).

**ChatSPX. [CÓDIGO]** Suporte multimodal existe no caminho de entrada: `AgentRunnerService#build_context` preserva arrays multimodais com entradas `image_url` para o runner restaurar com anexos; `OpenAiMessageBuilderService.extract_text_and_attachments` monta `RubyLLM::Content` com anexos; `ResponseBuilderJob#collect_previous_messages` documenta que blocos de imagem só podem ir em turnos de **user** (a API rejeita `image` em turnos de assistant) e converte outgoing com anexo em placeholder textual. Há `Captain::Behavior::MediaPipelineService`.

**[INFERÊNCIA]** Temos o encanamento. O que não temos é o **produto** (nome, tela, garantia de não-extração de PII declarada ao cliente) nem validação de que funciona no **widget web** — o caminho foi endurecido para WhatsApp.

### 8.2 Voz

**[FATO]** ElevenLabs (ElevenAgents) entrega widget de voz para site via snippet HTML, com chat e voz na mesma thread, deploy em telefone/web/mobile/WhatsApp, e é **LLM-agnóstico** (modelos próprios ou OpenAI/Anthropic/Google/custom) ([elevenlabs.io/docs/eleven-agents/overview](https://elevenlabs.io/docs/eleven-agents/overview), [elevenlabs.io/agents/omnichannel](https://elevenlabs.io/agents/omnichannel)).

**[FATO-2ª]** Divisão de forças em 2026: *"OpenAI leads on reasoning, Voiceflow on workflow control, Bland on scale, Hume on emotional intelligence, and ElevenLabs on vocal realism"* ([getstream.io](https://getstream.io/blog/best-ai-voice-agents/)).

**[FATO-2ª]** Fin Voice existe mas tem **preço sob consulta**, fora do modelo de US$ 0,99/outcome ([featurebase.app](https://www.featurebase.app/blog/fin-ai-pricing)). Agentforce cobra 30 créditos (US$ 0,15) por ação de voz **[FATO-2ª]**.

**ChatSPX. [CÓDIGO]** Já existe `Captain::ElevenLabsTtsService` e a tool `responder_em_audio` ("Responde o cliente com voice note (voz exclusiva do agente via ElevenLabs) quando ele pede áudio"), gateada por `voice_id` configurado no assistente (a tool nem entra no toolset sem a config — `assistant.rb:157-160`).

**[INFERÊNCIA]** Temos **TTS** (a IA fala), não temos **voice agent** (conversa por voz full-duplex com barge-in). A distância entre os dois é grande: precisa de STT em streaming, VAD, gestão de turno e latência sub-segundo. Para chat de **site**, voz é hoje um diferencial de nicho — o dado da Leadster (75,96% redireciona para WhatsApp) sugere que áudio no WhatsApp vale mais que voz no widget para o mercado brasileiro.

### 8.3 Cobrowsing / leitura de tela

**[FATO-2ª]** Estado da arte em 2026 ([chatbeacon.ai](https://www.chatbeacon.ai/features/cobrowse-screenshare), [fullview.io](https://www.fullview.io/products/cobrowsing), [cohere.io](https://cohere.io/cobrowse)):
- Sem download/plugin, funciona em Chrome/Safari/Firefox/Edge incluindo mobile
- **Mascaramento de campos sensíveis** (senha, pagamento) obrigatório; sessões criptografadas com controle de acesso
- Integração com IA: *"AI chatbots can detect frustration and automatically offer a co-browse session"*
- Distinção: **cobrowse** = agente vê e interage com o navegador do cliente; **screen share** = agente vê a tela inteira

**ChatSPX. [CÓDIGO]** Não existe. Nenhuma referência a cobrowse/screen share no repositório.

---

## 9. Riscos e governança

### 9.1 Alucinação com consequência comercial — os casos públicos

**Moffatt v. Air Canada — o precedente que define o campo. [FATO-2ª, mas com consenso de múltiplas fontes jurídicas]**

- Jake Moffatt pediu reembolso alegando ter confiado em orientação incorreta do chatbot da Air Canada sobre tarifas de luto (*bereavement fares*)
- O chatbot afirmou que ele poderia solicitar a tarifa **retroativamente** — contradizendo outra página do próprio site
- O **British Columbia Civil Resolution Tribunal** decidiu por **negligent misrepresentation** e condenou a companhia
- A Air Canada argumentou que **o chatbot era uma entidade legal separada**, responsável pelos próprios atos. O tribunal rejeitou: a empresa responde por toda a informação do seu site, venha de página estática ou de chatbot
- Indenização: **CAN$ 812,02**

Fontes: [McCarthy Tétrault](https://www.mccarthy.ca/en/insights/blogs/techlex/moffatt-v-air-canada-misrepresentation-ai-chatbot), [American Bar Association](https://www.americanbar.org/groups/business_law/resources/business-law-today/2024-february/bc-tribunal-confirms-companies-remain-liable-information-provided-ai-chatbot/), [CanLII](https://www.canlii.org/en/commentary/doc/2025CanLIIDocs1963).

**[INFERÊNCIA]** O valor é irrisório; o precedente não. A lição operacional em uma frase: **se o agente pode fazer promessa comercial (preço, prazo, política, desconto), essa promessa vira obrigação da empresa.** Daí a regra de projeto: informação com consequência comercial só sai do agente **com citação de fonte e com a fonte sendo a política oficial**, ou não sai.

**Klarna. [FATO-2ª]** Já detalhado (seções 1.2 e 5.2). A lição: containment alto com CSAT em queda é dívida, não ganho. A empresa reverteu e passou a usar humanos para disputas, reembolsos complexos e situações de dificuldade financeira.

### 9.2 Prompt injection via mensagem do visitante

**[FATO]** **LLM01:2025 Prompt Injection é a vulnerabilidade nº 1 do OWASP Top 10 para aplicações LLM** ([genai.owasp.org](https://genai.owasp.org/llmrisk/llm01-prompt-injection/)).

**[FATO-2ª]** Cenários específicos de chat de atendimento: injetar prompt no chatbot para "ignorar diretrizes anteriores, consultar bases privadas e enviar e-mails", levando a acesso não autorizado e escalação de privilégio; um chatbot de varejo com acesso a histórico de pedidos e capacidade de processar reembolso é alvo direto; agentes podem "executar comandos maliciosos, de emitir reembolsos a modificar registros, sem aprovação humana" ([obsidiansecurity.com](https://www.obsidiansecurity.com/blog/prompt-injection), [stackhawk.com](https://www.stackhawk.com/blog/owasp-llm01-prompt-injection/)).

**[FATO-2ª]** *"Prompt hacking (both injection and jailbreaking) remain unsolved problems and likely are impossible to solve entirely"* ([The Prompt Report, arXiv](https://arxiv.org/pdf/2406.06608)).

**[FATO]** Literatura de defesa arquitetural: *Design Patterns for Securing LLM Agents against Prompt Injections* ([arXiv 2506.08837](https://arxiv.org/pdf/2506.08837)); *IPIGuard*, defesa por grafo de dependência de tools contra injeção indireta ([arXiv 2508.15310](https://arxiv.org/pdf/2508.15310)).

**Vetor específico do chat de site. [INFERÊNCIA]** O widget web é o canal **mais** exposto: anônimo, sem verificação de identidade, sem custo de criação de "conta", e o atacante pode iterar centenas de tentativas. Pior que no WhatsApp, onde há um número de telefone atrás. Duas superfícies de risco no ChatSPX:
1. **Injeção direta** na mensagem do visitante tentando forçar tool call (`resolve_conversation`, `update_priority`, `add_label`, ou uma custom tool que chama API do cliente)
2. **Injeção indireta** através de conteúdo ingerido: se o `CrawlJob` indexa uma página que um terceiro consegue editar (comentários, wiki, marketplace), o texto malicioso entra na base e é servido como conhecimento confiável

**Mitigação que o mercado usa. [FATO]** Decagon: validações sensíveis **em código**, não em prompt. Sierra: **supervisores** revisando cada resposta. Essa é a resposta certa e nenhuma das duas confia no prompt.

### 9.3 Vazamento de dados e PII

**[FATO]** Fin Vision instrui explicitamente os modelos de visão a **não extrair PII** de imagens e deleta as imagens após período curto ([intercom.com/help](https://www.intercom.com/help/en/articles/10696494-how-fin-vision-understands-images)).

**ChatSPX. [CÓDIGO]** Defesa em profundidade real e específica para o Brasil: `sanitizePII.js` (front) + `lib/captain/pii_sanitizer.rb` (backend), mascarando CNPJ, telefone BR, CPF e cartão (com Luhn), com e-mail e CEP opcionais. O `ConversationEvalService` também tem `deep_sanitize` removendo bytes nulos e caracteres de controle C0 antes de gravar no Postgres.

**Gaps. [INFERÊNCIA]**
- Não há **retenção declarada** de transcrições enviadas ao provedor de LLM
- Não há **DPA/contrato de subprocessador** exposto ao cliente final no produto
- Não há **opt-out por conversa** ("não usar esta conversa para melhoria")
- O `build_state` envia `contact.custom_attributes` inteiro para o LLM (`agent_runner_service.rb:207`) — se a conta guarda CPF ou dado sensível em custom attribute, ele vai no prompt. O `sanitize_attr` do `SystemPromptsService` trunca em 200 caracteres, mas **não mascara**

### 9.4 Regulação

#### 9.4.1 EU AI Act, Artigo 50 — em vigor desde 2 de agosto de 2026

**[FATO]** ([artificialintelligenceact.eu/article/50](https://artificialintelligenceact.eu/article/50/), [digital-strategy.ec.europa.eu](https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act)):
- Sistemas que interagem diretamente com pessoas — **chatbots, agentes de IA e avatares** — devem ser projetados para que as pessoas saibam que estão interagindo com IA
- Para chatbot, a notificação deve ser dada **antes ou no início mesmo da conversa**, de forma **clara e distinguível**
- Exceção quando é óbvio para "uma pessoa razoavelmente bem informada, observadora e circunspecta" — mas a Comissão aplica leitura **restritiva**, limitando a casos em que "quase não resta dúvida"
- Alcance extraterritorial: provedores fora da UE entram no escopo se colocam o sistema no mercado da UE ou se o output é usado na UE
- Penalidades: **€ 15 milhões ou 3% do faturamento mundial**

#### 9.4.2 Califórnia — B.O.T. Act (SB 1001)

**[FATO]** ([leginfo.legislature.ca.gov](https://leginfo.legislature.ca.gov/faces/billTextClient.xhtml?bill_id=201720180SB1001)): assinada em 2018, vigente desde 01/07/2019. Ilegal usar bot para se comunicar com pessoa na Califórnia **com intenção de enganar sobre a identidade artificial** para induzir compra/venda ou influenciar voto. Não há responsabilidade se houver divulgação clara, conspícua e razoavelmente desenhada para informar que é um bot.
**[FATO-2ª]** Enforcement pelo Attorney General, com multas citadas de até US$ 2.500 por violação ([disclosed.sh](https://disclosed.sh/learn/law/ca)) — **o valor não foi verificado no texto da lei**.

#### 9.4.3 Brasil — LGPD, ANPD e PL 2338/2023

**[FATO-2ª]** PL 2338/2023 aprovado por unanimidade no plenário do Senado em **10/12/2024**; em tramitação na Câmara dos Deputados; votação em plenário estava prevista para **27/05/2026** com relatório final do dep. Aguinaldo Ribeiro apresentado em 19/05 ([Senado — matéria 157233](https://www25.senado.leg.br/web/atividade/materias/-/materia/157233), [entercastconsulting.com.br](https://www.entercastconsulting.com.br/blog/marco-legal-ia-brasil-votacao-camara-maio-2026)). Modelo europeu: classificação por risco (excessivo, alto, baixo/moderado), direitos de transparência/explicação/contestação, criação do SIA, sanções de até **R$ 50 milhões** por infração.
**[NÃO VERIFICADO]** Se a votação de 27/05/2026 efetivamente ocorreu e qual o resultado.

**[FATO-2ª]** ANPD publicou em dez/2025 o **Mapa de Temas Prioritários 2026-2027** com IA entre os quatro eixos centrais de fiscalização; e a **Nota Técnica nº 12/2025**, resultado de Tomada de Subsídios sobre tratamento automatizado e IA frente à LGPD, consolidando contribuições sobre transparência algorítmica, revisão de decisões automatizadas, governança de IA e uso de dados pessoais em treinamento ([machertecnologia.com.br](https://www.machertecnologia.com.br/lgpd-anpd-inteligencia-artificial-nota-tecnica-12-2025/), [martinelli.adv.br](https://www.martinelli.adv.br/anpd-publica-mapa-de-temas-prioritarios-2026-2027-e-atualiza-a-agenda-regulatoria-2025-2026/)). Critérios de avaliação sinalizados: **transparência (o titular sabe que está interagindo com IA?)**, mitigação de viés, segurança da informação e impactos sobre direitos (**art. 20 da LGPD — revisão de decisões automatizadas**).

**[INFERÊNCIA]** Mesmo sem o PL 2338 aprovado, o **art. 20 da LGPD já existe hoje** e dá ao titular direito de solicitar revisão de decisão automatizada que afete seus interesses. Um agente que **desqualifica** um lead ou **nega** um atendimento está tomando decisão automatizada. Isso é um argumento concreto para o ChatSPX registrar o "porquê" de cada decisão do agente — coisa que o `reasoning` do `ResponseSchema` já captura, mas que não é exposta a nenhum titular.

#### 9.4.4 A expectativa do consumidor supera a lei

**[FATO]** Zendesk CX Trends 2026 ([cxtrends.zendesk.com](https://cxtrends.zendesk.com/)):
- **95% dos consumidores esperam explicação sobre decisões feitas por IA**
- **63% relatam demanda crescente por transparência** em relação ao ano anterior

**[INFERÊNCIA]** Ou seja: mesmo fora da UE, esconder que é um bot é mau produto antes de ser risco legal. E existe uma leitura de negócio: como o Fin não cobra resolução quando "apenas responde a uma saudação", **declarar-se IA no primeiro turno não custa nada** no modelo de outcome — não há incentivo econômico contra a transparência.

### 9.5 Checklist de governança para chat de site com IA

**[INFERÊNCIA]** Consolidação do que foi levantado acima:

| # | Controle | Justificativa |
|---|---|---|
| 1 | Declarar "sou uma IA" no primeiro turno, de forma clara e distinguível | EU AI Act art. 50 **[FATO]**; SB 1001 **[FATO]**; 95% dos consumidores **[FATO]** |
| 2 | Citação de fonte em toda afirmação com consequência comercial | Precedente Air Canada **[FATO-2ª]** |
| 3 | Validação **em código** (não em prompt) antes de qualquer ação sensível | Padrão Decagon **[FATO]** |
| 4 | Supervisor de saída antes do envio | Padrão Sierra **[FATO]** |
| 5 | Lista de tópicos proibidos com resposta canônica (preço fora de tabela, promessa de prazo, jurídico, saúde) | Redução de superfície de alucinação |
| 6 | Sanitização de PII na entrada e antes do prompt | Já existe no ChatSPX **[CÓDIGO]** |
| 7 | Segregar conteúdo ingerido não confiável (páginas editáveis por terceiros) | Injeção indireta **[FATO]** |
| 8 | Log auditável: prompt, tools chamadas, resultado, resposta, versão do prompt | Art. 20 LGPD; ANPD **[FATO-2ª]** |
| 9 | Retenção declarada e opt-out de uso da conversa | LGPD |
| 10 | Handoff garantido a pedido do cliente ("quero falar com humano" nunca é negado) | Lição Klarna **[FATO-2ª]** |
| 11 | Rate limit por sessão do widget e detecção de padrão de injeção | Anonimato do canal web **[INFERÊNCIA]** |
| 12 | Teto de gasto por conta com kill switch | Controle de custo |

---

## 10. Open source e o que dá para reaproveitar

### 10.1 Panorama verificado (API do GitHub, consultada em 11/08/2026)

**[FATO]** Números coletados diretamente de `api.github.com/repos/{owner}/{repo}`:

| Projeto | Estrelas | Licença (SPDX) | Linguagem | Último push |
|---|---:|---|---|---|
| **langflow-ai/langflow** | 153.060 | **MIT** | Python | 11/08/2026 |
| **langgenius/dify** | 152.109 | NOASSERTION (licença própria) | TypeScript | 11/08/2026 |
| **open-webui/open-webui** | 148.499 | NOASSERTION | Python | 11/08/2026 |
| **FlowiseAI/Flowise** | 55.325 | NOASSERTION | TypeScript | 10/08/2026 |
| **chatwoot/chatwoot** | 35.726 | NOASSERTION (MIT + enterprise) | Ruby | 11/08/2026 |
| **RasaHQ/rasa** | 21.290 | **Apache-2.0** | Python | 24/07/2026 |
| **botpress/botpress** | 14.857 | **MIT** | TypeScript | 11/08/2026 |
| **baptisteArno/typebot.io** | 10.251 | NOASSERTION (AGPL para a maior parte) | TypeScript | 10/08/2026 |
| **NVIDIA-NeMo/Guardrails** | 6.923 | NOASSERTION (Apache-2.0 declarado no projeto) | Python | 11/08/2026 |

**[INFERÊNCIA importante sobre licença]** `NOASSERTION` significa que o GitHub não conseguiu classificar automaticamente — quase sempre indica **licença modificada com restrições comerciais**. Para Dify, Open WebUI e Typebot isso precisa de leitura jurídica antes de qualquer reuso em produto vendido. Langflow (MIT), Rasa (Apache-2.0) e Botpress (MIT) são as três licenças limpas da lista.

### 10.2 Avaliação de reaproveitamento para o ChatSPX

| Projeto | O que é | Serve para reaproveitar? |
|---|---|---|
| **Chatwoot Captain** | Base do que já usamos | **É a base.** O ChatSPX já está muito à frente do upstream aqui (seção 11) |
| **Rasa** | Orquestração de agente self-hosted, NLU profunda, RBAC, audit log, multicanal, voz. Strong Performer no Forrester Wave Q2/2026 **[FATO-2ª]** ([rasa.com](https://rasa.com/blog/rasa-vs-botpress)) | **Não.** Stack Python paralela, custo de integração alto, e o Captain já resolve orquestração |
| **Botpress** | Builder visual + código, cloud como caminho suportado, **sem voz nativa** **[FATO-2ª]** | **Não.** Sobreposição direta com o que temos |
| **Typebot** | Formulários conversacionais bonitos **[FATO-2ª]** ([eesel.ai](https://www.eesel.ai/blog/open-source-chatbot-platforms)) | **Como referência de UX** de pré-chat/qualificação, não como dependência |
| **Dify / Flowise / Langflow** | Orquestração LLM low-code, RAG visual | **Referência de UX de construtor.** Como dependência: não — licença duvidosa (Dify/Flowise) e stack estranha |
| **Open WebUI** | Front multi-LLM | Não aplicável ao caso |
| **NeMo Guardrails** | Rails de entrada/saída/diálogo/tool, DSL Colang, Apache-2.0 **[FATO]** | **Talvez, como referência de design.** Como dependência em produção: o próprio projeto carrega disclaimer de beta **[FATO-2ª]**, e é Python — o ChatSPX é Ruby |
| **Llama Guard 3** | Classificador aberto 8B de segurança **[FATO-2ª]** | **Como serviço externo**, sim: um endpoint de classificação chamado antes/depois da geração cabe na arquitetura atual sem trazer Python para dentro do monolito |
| **τ²-bench (Sierra)** | Benchmark de agente de atendimento com política declarada **[FATO]** | **Sim, como metodologia.** Adaptar o formato (política + toolset + personas) para gerar simulações do Captain |

**[INFERÊNCIA]** A conclusão honesta é que **não há nada de open source que valha trazer como dependência**. O que vale é copiar **três metodologias**: (1) o formato de política + toolset + persona do τ²-bench para simulação, (2) a separação entre rail de entrada/saída/tool do NeMo, (3) o padrão AOP da Decagon (linguagem natural para procedimento, código para validação sensível).

---

## 11. AUDITORIA: o que o ChatSPX/Captain já tem hoje

> Toda esta seção é **[CÓDIGO]** — leitura direta do repositório em `/home/chatwoot/chatwoot`, branch `homologacao`, em 11/08/2026. Nada foi modificado.

### 11.1 Superfície do sistema

| Camada | Quantidade | Onde |
|---|---:|---|
| Models Captain | 11 | `enterprise/app/models/captain/*.rb` + `captain_inbox.rb` |
| Services Captain | 70+ arquivos | `enterprise/app/services/captain/**` |
| Lib Captain (tools + eval) | 30+ arquivos | `enterprise/lib/captain/**` |
| Jobs Captain | 15 | `enterprise/app/jobs/captain/**` |
| Controllers Captain | 11 | `enterprise/app/controllers/api/v1/accounts/captain/*.rb` |
| Tools built-in (agente) | **22** | `config/agents/tools.yml` |
| Tools do copiloto | **32** | `Captain::Copilot::ChatService::TOOL_CLASSES` |
| Componentes Vue do painel de IA | 7 + 14 composables + 21 specs (~4.550 linhas) | `app/javascript/dashboard/components-next/ai-assistant/` |
| Prompts Liquid | 5 + snippets | `enterprise/lib/captain/prompts/` |
| Feature flags | `captain_integration`, `captain_integration_v2`, `captain_tasks` | `config/features.yml` |

### 11.2 Modelo de dados

| Tabela | Papel | Colunas notáveis |
|---|---|---|
| `captain_assistants` | Agente | `config` jsonb, **`guardrails` jsonb**, **`response_guidelines` jsonb**, `behavior` (store_accessor: `debounce_seconds`, `business_hours_config`, `humanizer_config`, `media_pipeline_config`, `router_config`, `copilot_trigger_config`, `dedup_config`) |
| `captain_documents` | Fonte de conhecimento | `content` (máx 200k chars), `external_link` (sentinelas `PDF:` e `TEXT:`), `status` (in_progress/available), `pdf_file` anexado (10 MB) |
| `captain_document_chunks` | Unidade de RAG | `embedding vector(1536)` **HNSW**, `content_search tsvector` **GIN**, **`contextual_content`**, `position`, `metadata` |
| `captain_assistant_responses` | FAQ Q&A | caminho legado/padrão de conhecimento |
| `captain_scenarios` | Sub-agente por tarefa | `instruction`, `tools` jsonb, `enabled`; vira **agente com handoff** no runtime |
| `captain_custom_tools` | Tool HTTP por conta | `endpoint_url`, `http_method`, `auth_type` (none/bearer/basic/api_key), `param_schema` (JSON Schema), `request_template`, `response_template`, `copilot_only` |
| `captain_inboxes` | Elegibilidade agente×inbox | permite N assistants por inbox, bloqueia duplicata |
| `captain_assistant_logs` | Eventos do agente | usado no eval como "eventos do sistema" |
| `conversation_episode` | Unidade de atendimento | `seq`, `first_message_id`, `last_message_id`, `started_at`, `ended_at` |
| `conversation_eval` | Veredito do juiz | `funil`, `resumo`, `nota`, findings |
| `tool_call` | Traço de tool | `tool_name`, `args`, `result_preview`, `status`, `error` |

### 11.3 O runtime do agente

`Captain::Assistant::AgentRunnerService` (304 linhas) roda sobre a gem `agents` (ai-agents), com `max_turns: 100`. Pontos notáveis:

- **Multi-agente com handoff bidirecional**: `build_and_wire_agents` registra os agentes de cenário como handoff do agente principal **e** o agente principal como handoff de cada cenário (volta possível)
- **Estado tipado** injetado no contexto: `CONVERSATION_STATE_ATTRIBUTES`, `CONTACT_STATE_ATTRIBUTES`, `CONTACT_INBOX_STATE_ATTRIBUTES` (inclui `hmac_verified`), `CAMPAIGN_STATE_ATTRIBUTES`
- **Anti-papagaio**: `fallback_replays_history?` compara a resposta com as 12 últimas saídas da conversa, inclusive quebrando pelo humanizer em bolhas, para não reemitir fala antiga
- **Fallback de handoff**: quando o último turno é handoff e `result.output` vem vazio, recupera o texto da última mensagem do assistente para que a fala de transição chegue ao cliente
- **Marcador removido do contexto**: `aguardando_humano_desde` é retirado do `custom_attributes` antes de ir ao LLM porque sua presença empurrava o modelo ao silêncio mesmo com pergunta nova
- **Instrumentação Langfuse/OTel** com metadata rica e flag `credit_used`

### 11.4 Camada de comportamento — o que não existe no upstream

`enterprise/app/services/captain/behavior/` implementa 7 serviços que **não existem no Chatwoot upstream** e que são, na prática, a camada de "realismo" do agente:

| Serviço | O que faz |
|---|---|
| `HumanizerService` | Quebra a resposta em bolhas, como pessoa digitando |
| `DebounceService` | Agrupa mensagens rápidas do cliente antes de responder |
| `DedupService` | Evita resposta duplicada |
| `BusinessHoursChecker` | Comportamento diferente dentro/fora do horário |
| `RouterService` | Guards técnicos: ignora `activity`, conteúdo vazio, e **grupos de WhatsApp por padrão seguro** (`SKIP_GROUPS_DEFAULT = true`, tri-estado que respeita config explícita) |
| `MediaPipelineService` | Pipeline de mídia |
| `CopilotTriggerService` | Gatilho do copiloto |

### 11.5 Ciclo de encerramento e follow-up

| Componente | Papel |
|---|---|
| `ConversationCompletionService` | LLM decide se a conversa está completa e pode ser auto-resolvida. **Não consome cota** (omite `:message`) e prefere a chave de sistema para não gastar crédito do cliente |
| `PendingClosureService` + `InboxPendingConversationsResolutionJob` | Fila "aguardando encerramento": IA propõe fechar, humano revisa |
| `FollowupJob` + `programar_followup` | Cutucada programada; ao esgotar as cutucadas in-window, escala para humano pelo `HumanHandoffService` |
| `AssignmentKickJob`, `DebouncedResponseJob` | Orquestração de atribuição e resposta |

### 11.6 O sistema de eval — o ativo mais subvalorizado

Já detalhado em 4.9. Resumo do que existe e é raro:

- Segmentação em **episódios** (`EpisodeSegmenterService`, 176 linhas)
- **LLM-as-a-judge** com schema estruturado e 16 categorias de falha
- Transcript com **tool calls intercaladas cronologicamente**, com args e resultado
- **Gates determinísticos** (`EpisodeGateService`) declaradamente no padrão τ-bench/BFCL, detectando `contradisse_tool`, `ignorou_erro_da_tool` e `repeticao` literal
- **Carryover** de vereditos anteriores do mesmo contato, a custo zero de LLM
- **Chave e modelo de LLM dedicados** ao eval, isolando custo e blast radius
- `EpisodeEvalJob`, `ConversationEvalJob`, `ConversationEvalSchedulerJob` — roda em lote agendado

**[INFERÊNCIA]** Comparando com o mercado: isso é o **Watchtower da Decagon** construído por dentro. A diferença é que a Decagon vende Watchtower como produto e o ChatSPX o mantém como ferramenta interna sem tela.

### 11.7 Comparação honesta: ChatSPX vs Fin vs Lyro vs Sierra

| Capacidade | ChatSPX/Captain | Fin | Lyro | Sierra |
|---|---|---|---|---|
| Ingestão: URL/crawl | ✅ Firecrawl + crawler simples | ✅ | ✅ | ✅ |
| Ingestão: PDF | ✅ (10 MB, paginado) | ✅ | ✅ | ✅ |
| Ingestão: texto colado | ✅ | ✅ | ✅ | ✅ |
| Ingestão: Notion/Drive/Confluence | ❌ | ✅ | parcial | ✅ |
| Ingestão: tickets históricos como corpus | ❌ (só gera FAQ) | ✅ | — | ✅ |
| Chunking contextual (Anthropic) | ✅ **acima da média** | não divulgado | ❌ | provável |
| Busca híbrida vetor+lexical | ✅ RRF k=60 | não divulgado | ❌ | ✅ |
| Reranker (cross-encoder) | ❌ **TODO no código** | provável | ❌ | ✅ |
| Stemming pt-BR no full-text | ❌ (usa `'simple'`) | n/a | n/a | n/a |
| Citação de fonte | ⚠️ existe, **desligada por padrão** | ✅ padrão | parcial | ✅ |
| Guardrails em prompt | ✅ | ✅ | ✅ | ✅ |
| **Guardrail executável / supervisor** | ❌ | provável | ❌ | ✅ **explícito** |
| **Validação de ação sensível em código** | ❌ | provável | ❌ | ✅ (padrão Decagon) |
| Tools built-in | ✅ 22 | ✅ | limitado | ✅ |
| Custom tools HTTP (com anti-SSRF) | ✅ | ✅ Actions | ❌ | ✅ SDK |
| Tools de e-commerce/pedido | ❌ | ✅ | ✅ | ✅ |
| Agendamento em calendário | ❌ | ✅ | ❌ | ✅ |
| Multi-agente / handoff entre especialidades | ✅ cenários + `transferir_para_agente` | ✅ | ❌ | ✅ |
| Memória de perfil / CRM | ✅ notas + atributos | ✅ | parcial | ✅ |
| Memória semântica de conversas passadas | ❌ | ✅ | ❌ | ✅ Agent Data Platform |
| Handoff com dossiê, time e distribuição | ✅ **muito bom** | ✅ | básico | ✅ |
| Copiloto com tools de ação | ✅ **32 tools** | ✅ | ❌ | ✅ Live Assist |
| Streaming SSE com cancelamento | ✅ | ✅ | — | ✅ |
| Eval LLM-as-judge com taxonomia | ✅ **acima da média** | não exposto | ❌ | ✅ |
| Gates determinísticos | ✅ | não exposto | ❌ | ✅ |
| **Simulação pré-deploy** | ❌ | não exposto | ❌ | ✅ |
| **QA de produção como produto/tela** | ❌ (motor existe) | ✅ | ❌ | ✅ |
| Observabilidade LLM (Langfuse/OTel) | ✅ | interno | ❌ | ✅ |
| Sanitização PII pt-BR (CPF/CNPJ/Luhn) | ✅ **diferencial** | genérico | ❌ | genérico |
| Multimodal: imagem do cliente | ⚠️ encanamento pronto, não é produto | ✅ **Fin Vision** | ❌ | ✅ |
| TTS / voice note | ✅ ElevenLabs | ✅ | ❌ | ✅ |
| Voice agent full-duplex | ❌ | ✅ Fin Voice | ❌ | ✅ |
| Cobrowsing | ❌ | ❌ | ❌ | ❌ |
| Cobrança por outcome | ❌ (crédito/assinatura) | ✅ | ❌ | ✅ |
| Métrica de resolução exposta ao cliente | ❌ | ✅ | ✅ | ✅ |
| Declaração "sou IA" no primeiro turno | ❌ **não verificado como padrão** | ✅ | ✅ | ✅ |

### 11.8 Veredito da auditoria

**Onde estamos acima da média de mercado para o nosso porte:**
1. **Contextual retrieval + busca híbrida com RRF** — implementação de qualidade que muitos fornecedores caros não têm.
2. **Sistema de eval com episódios, taxonomia de 16 falhas e gates determinísticos** — é Watchtower feito em casa.
3. **Handoff** — idempotente, com dossiê, roteamento de time validado contra alucinação, distribuição por rodízio e out-of-office. Melhor que a maioria.
4. **Camada de comportamento** (humanizer, debounce, dedup, horário, router) — não existe no upstream e é o que faz o agente parecer gente no WhatsApp.
5. **Sanitização PII brasileira** — CPF/CNPJ/Luhn é diferencial de mercado local.
6. **Copiloto com 32 tools de ação** — o copiloto do ChatSPX *executa*, não só sugere.

**Onde estamos claramente atrás:**
1. **Nenhum guardrail executável.** Guardrail é campo de prompt. Sierra e Decagon têm supervisor e validação em código. Este é o gap nº 1.
2. **Sem reranker.** Está escrito como TODO no próprio código. É o degrau que leva a falha de recuperação de 2,9% para 1,9% **[FATO Anthropic]**.
3. **Citação desligada por padrão.** Em chat de site isso é risco jurídico (Air Canada) e perda de confiança.
4. **Sem simulação pré-deploy.** O eval é post-mortem. Decagon roda simulação antes.
5. **Sem tools de e-commerce/agendamento.** As duas categorias que mais deflectem em B2C.
6. **Nenhuma métrica de resolução exposta ao cliente.** Não sabemos dizer ao cliente "sua IA resolveu X%". O mercado inteiro vende esse número.
7. **Multimodal e voz existem como encanamento, não como produto.**
8. **Sem declaração automática "sou uma IA"** — não encontrei isso como comportamento padrão do sistema.

**O que é proibitivo hoje [INFERÊNCIA]:**
- **Voice agent full-duplex** — exige STT em streaming, VAD, gestão de turno, latência sub-segundo. Não compensa: para o mercado brasileiro, áudio no WhatsApp (que já temos) vale mais que voz no widget.
- **Cobrowsing** — precisa de infraestrutura de sessão, mascaramento de campo e compatibilidade cross-browser. Nenhum concorrente direto oferece; é aposta cara.
- **Constelação de 15+ modelos com failover** (Sierra) — exige volume e orçamento de FinOps que não temos hoje. O que dá para fazer é a versão pobre: 2 modelos (rápido/barato para classificação e roteador, forte para resposta final).
- **Fine-tuning de modelo próprio** — sem base rotulada em escala, não paga.

---

## 12. IMPLICAÇÕES PARA O CHATSPX

> Recomendações apenas. Nenhuma linha de código sugerida, conforme a instrução.

### 12.1 As cinco decisões de produto que este estudo sugere

**D1 — Expor o eval como produto de qualidade, não como ferramenta interna.**
Já temos o motor (episódios + juiz + gates + 16 categorias de falha). O mercado vende isso como Watchtower (Decagon) e AutoQA (Zendesk QA), com preço de add-on. Uma tela que mostre ao gestor "estas 7 respostas da sua IA tiveram problema esta semana, com o trecho e o porquê" é a coisa de maior valor/esforço do inventário inteiro. **[INFERÊNCIA]**

**D2 — Publicar um número de resolução, com denominador declarado.**
Todo concorrente vende um número (Fin 76%, HubSpot 65%, Lyro 67%, Ada 83%) **[FATO]**. Não temos nenhum. Mas o estudo mostra que o número sozinho é vazio: a recomendação é publicar o **conjunto de seis** da seção 5.5, com destaque para a **taxa de retorno em 7 dias** — que nenhum concorrente publica e é justamente o antídoto ao vício "abandono = sucesso" que a Decagon denuncia. Isso é posicionamento de honestidade, e é defensável. **[INFERÊNCIA]**

**D3 — Guardrail executável antes de guardrail de prompt.**
Mover a lógica do `EpisodeGateService` de "depois do fato, no eval" para "antes do envio, no runtime" transforma auditoria em prevenção com quase zero pesquisa nova. É o gap nº 1 versus Sierra/Decagon e o mais barato de fechar porque o código de detecção já existe e está testado. **[INFERÊNCIA]**

**D4 — Citação de fonte ligada por padrão no canal web.**
Não em todos os canais: no WhatsApp, `[[1](url)]` polui. Mas o widget de site é onde o cliente é anônimo, o risco jurídico é maior (Air Canada) e o link é natural. A flag já existe (`feature_citation`); é decisão de default por canal, não desenvolvimento. **[INFERÊNCIA]**

**D5 — Declarar "sou uma IA" no primeiro turno do widget.**
EU AI Act art. 50 em vigor desde 02/08/2026 **[FATO]**; SB 1001 na Califórnia **[FATO]**; 95% dos consumidores esperam explicação **[FATO]**; ANPD sinaliza transparência como critério de fiscalização **[FATO-2ª]**. E, comercialmente, não custa nada: o Fin não cobra resolução por responder saudação **[FATO]**. É a mudança de menor esforço e maior redução de risco do documento inteiro.

### 12.2 Prioridade sugerida (impacto × esforço)

| # | Item | Impacto | Esforço | Por quê |
|---|---|---|---|---|
| 1 | Declaração "sou IA" no primeiro turno (widget) | Alto | Mínimo | Conformidade + confiança; zero custo comercial |
| 2 | Citação de fonte por padrão no canal web | Alto | Baixo | Flag já existe; mitiga risco Air Canada |
| 3 | Tela de QA a partir do eval existente | Muito alto | Médio | Motor pronto; vira SKU vendável |
| 4 | Painel de 6 métricas com taxa de retorno em 7 dias | Alto | Médio | Diferenciação por honestidade |
| 5 | Guardrail executável (gates movidos para pré-envio) | Muito alto | Médio | Fecha o gap nº 1 reusando código testado |
| 6 | Reranker sobre o resultado do RRF | Alto | Médio | −67% de falha de recuperação **[FATO Anthropic]**; TODO já escrito |
| 7 | Stemming pt-BR no índice full-text | Médio | Baixo | `'simple'` perde plural/conjugação em português |
| 8 | Tools de pedido/rastreio e agendamento | Alto | Médio-alto | As duas categorias que mais deflectem em B2C |
| 9 | Simulação pré-deploy com personas sintéticas (formato τ²-bench) | Alto | Alto | Metodologia pública; transforma deploy em teste |
| 10 | Memória semântica de conversas passadas do contato | Médio | Alto | 83% dos líderes de CX apontam memória como chave **[FATO]** |
| 11 | Fin Vision equivalente como produto no widget | Médio | Médio | Encanamento existe; 76% dos consumidores querem multimodal **[FATO]** |
| 12 | Limpeza das 7 tools verticais do `tools.yml` global | Médio | Baixo | Dívida de produto: tools de um cliente no catálogo de todos |
| — | Voice agent full-duplex | Baixo (BR) | Muito alto | 75,96% do mercado brasileiro vai para WhatsApp **[FATO Leadster]** |
| — | Cobrowsing | Baixo | Muito alto | Nenhum concorrente direto oferece |

### 12.3 Sobre o modelo comercial

**[INFERÊNCIA]** Três leituras do que o estudo mostrou:

1. **Não copie o preço por resolução.** A Ada criou a métrica e abandonou a cobrança; a Decagon a rejeita publicamente; os clientes preferem previsibilidade. Para PME brasileira, conta variável em dólar é veneno comercial.
2. **Copie a garantia, não a unidade.** O movimento mais inteligente da tabela é o do Tidio: **"Guaranteed 50% Lyro AI resolution rate"** no tier premium **[FATO]**. Mantém a assinatura previsível (que o mercado brasileiro quer) e transfere o risco de execução para o fornecedor (que é o que trava a venda). O ChatSPX pode fazer isso porque **tem o eval para medir** — o concorrente que não mede não consegue garantir.
3. **A referência de piso é US$ 0,50** (HubSpot) **[FATO]**, não US$ 0,99. Se algum dia houver SKU por unidade, é contra esse número que ele será comparado.
   - `credit_used` no trace do `AgentRunnerService` já é o embrião do contador. **[CÓDIGO]**

### 12.4 Sobre o posicionamento no Brasil

**[INFERÊNCIA]** Os três fatos brasileiros do estudo compõem uma tese de posicionamento:

- **6,60% das empresas usam IA em geração de leads** **[FATO Leadster]** — o mercado está aberto; não é preciso ganhar de fornecedor internacional, é preciso chegar antes do concorrente local.
- **75,96% redirecionam para WhatsApp** **[FATO Leadster]** — o widget é rampa, não destino. O produto certo é **"IA que começa no site e continua no WhatsApp com o mesmo contexto"**, e essa é exatamente a arquitetura que o ChatSPX já tem (mesmo `Captain::Assistant` servindo inboxes diferentes via `captain_inboxes`, com N assistants elegíveis por inbox). **[CÓDIGO]** Nenhum concorrente internacional entrega isso bem no Brasil.
- **Sanitização de CPF/CNPJ com Luhn** **[CÓDIGO]** + argumento LGPD/ANPD é venda direta a quem tem jurídico exigente.

### 12.5 O que NÃO fazer

**[INFERÊNCIA]**

1. **Não perseguir taxa de deflection.** É métrica de vaidade documentada, e a Klarna pagou publicamente o preço de otimizá-la.
2. **Não construir voice agent full-duplex agora.** O dado brasileiro não sustenta.
3. **Não trazer NeMo Guardrails, Dify ou Rasa como dependência.** Stack estranha, licenças duvidosas em parte da lista, e sobreposição com o que já temos. Copiar metodologia, não código.
4. **Não expandir `config/agents/tools.yml` com mais verticais de cliente.** O caminho é `captain_custom_tools`, que já existe, é por conta e tem validação anti-SSRF.
5. **Não prometer taxa de resolução sem definir o denominador.** É exatamente onde Fin (76% vs 45–53%) e Lyro (67% vs 40–60%) perdem credibilidade nas análises independentes.

---

## 13. Fontes consultadas

### Fornecedores — páginas oficiais (primárias)
- Fin — preços: https://fin.ai/pricing/
- Intercom — definição de resolução do Fin: https://www.intercom.com/help/en/articles/8205718-fin-resolutions
- Intercom — de resoluções para outcomes: https://www.intercom.com/blog/from-resolutions-to-outcomes-evolving-how-fin-delivers-value/
- Intercom — Fin Vision: https://www.intercom.com/help/en/articles/10696494-how-fin-vision-understands-images
- Zendesk — automated resolutions: https://support.zendesk.com/hc/en-us/articles/5352026794010-About-automated-resolutions-for-AI-agents
- Zendesk — CX Trends 2026: https://cxtrends.zendesk.com/
- Zendesk — aquisição da Forethought: https://www.zendesk.com/newsroom/articles/forethought-acquisition/ e https://www.zendesk.com/newsroom/press-releases/zendesk-completes-acquisition-of-forethought/
- Zendesk/PR Newswire — aquisição da Ultimate: https://www.prnewswire.com/news-releases/zendesk-to-acquire-ultimate-302088192.html
- Salesforce — preços do Agentforce: https://help.salesforce.com/s/articleView?id=004811240&language=en_US&type=1
- Salesforce — acordo para adquirir a Fin: https://www.salesforce.com/news/press-releases/2026/06/15/salesforce-signs-definitive-agreement-to-acquire-fin/
- HubSpot — outcome-based pricing: https://www.hubspot.com/company-news/hubspots-customer-agent-and-prospecting-agent-now-you-pay-when-the-task-is-complete
- Sierra — constelação de modelos: https://sierra.ai/blog/constellation-of-models
- Sierra — Agent SDK: https://sierra.ai/product/agent-sdk
- Sierra — τ²-bench: https://github.com/sierra-research/tau2-bench
- Decagon — precificação de agentes: https://decagon.ai/blog/pricing-ai-agents
- Decagon — AOPs: https://decagon.ai/product/aop e https://decagon.ai/resources/why-we-built-aop
- Decagon — simulações: https://decagon.ai/resources/decagon-simulations
- Ada — Unified Reasoning Engine: https://www.ada.cx/media-center/press-release/ada-launches-industrys-first-unified-reasoning-engine/
- Tidio — preços: https://www.tidio.com/pricing/
- Chatwoot — preços: https://www.chatwoot.com/pricing
- Chatwoot — Captain: https://www.chatwoot.com/captain
- Chatwoot — Custom Tools: https://www.chatwoot.com/blog/captain-custom-tools
- ElevenLabs — ElevenAgents: https://elevenlabs.io/docs/eleven-agents/overview e https://elevenlabs.io/agents/omnichannel
- Leadster — Panorama de Geração de Leads 2026: https://leadster.com.br/panorama-geracao-de-leads/
- Leadster — como funciona: https://leadster.com.br/como-funciona/
- Leadster — chatbot: https://leadster.com.br/chatbot-leadster/
- Leadster — leads com ChatGPT: https://leadster.com.br/gere-leads-qualificados-com-chatgpt/

### Técnicas e pesquisa
- Anthropic — Contextual Retrieval: https://www.anthropic.com/news/contextual-retrieval
- OWASP — LLM01:2025 Prompt Injection: https://genai.owasp.org/llmrisk/llm01-prompt-injection/
- Design Patterns for Securing LLM Agents against Prompt Injections: https://arxiv.org/pdf/2506.08837
- IPIGuard: https://arxiv.org/pdf/2508.15310
- The Prompt Report: https://arxiv.org/pdf/2406.06608
- τ-bench (OpenReview): https://openreview.net/forum?id=roNSXZpUDN
- NVIDIA NeMo Guardrails: https://github.com/NVIDIA-NeMo/Guardrails e https://docs.nvidia.com/nemo/guardrails/latest/index.html

### Regulação e jurisprudência
- EU AI Act, Artigo 50: https://artificialintelligenceact.eu/article/50/
- Comissão Europeia — FAQ sobre transparência (art. 50): https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act
- California SB 1001: https://leginfo.legislature.ca.gov/faces/billTextClient.xhtml?bill_id=201720180SB1001
- Perkins Coie — análise do SB 1001: https://perkinscoie.com/insights/update/i-am-robot-californias-new-law-requires-disclosure-use-bots
- McCarthy Tétrault — Moffatt v. Air Canada: https://www.mccarthy.ca/en/insights/blogs/techlex/moffatt-v-air-canada-misrepresentation-ai-chatbot
- American Bar Association — Moffatt v. Air Canada: https://www.americanbar.org/groups/business_law/resources/business-law-today/2024-february/bc-tribunal-confirms-companies-remain-liable-information-provided-ai-chatbot/
- CanLII — comentário de caso: https://www.canlii.org/en/commentary/doc/2025CanLIIDocs1963
- Senado Federal — PL 2338/2023: https://www25.senado.leg.br/web/atividade/materias/-/materia/157233
- Câmara dos Deputados — Comissão Especial de IA: https://www2.camara.leg.br/atividade-legislativa/comissoes/comissoes-temporarias/especiais/57a-legislatura/comissao-especial-sobre-inteligencia-artificial-pl-2338-23
- ANPD — documentos técnicos e orientativos: https://www.gov.br/anpd/pt-br/centrais-de-conteudo/documentos-tecnicos-orientativos

### Imprensa
- Forbes — reversão da Klarna: https://www.forbes.com/sites/quickerbettertech/2025/05/18/business-tech-news-klarna-reverses-on-ai-says-customers-like-talking-to-people/
- Entrepreneur — Klarna recontrata: https://www.entrepreneur.com/business-news/klarna-ceo-reverses-course-by-hiring-more-humans-not-ai/491396
- TechCrunch — Salesforce adquire a Fin: https://techcrunch.com/2026/06/15/salesforce-acquires-ai-customer-service-platform-fin-for-3-6b/
- CNBC — Salesforce/Fin: https://www.cnbc.com/2026/06/15/salesforce-ai-customer-service-fin-acquistion.html
- Computer Weekly — Zendesk/Forethought: https://www.computerweekly.com/news/366639959/Zendesk-to-acquire-Forethought-in-major-agentic-AI-play
- CMSWire — Zendesk Relate 2026: https://www.cmswire.com/customer-experience/zendesk-unveils-autonomous-ai-workforce-at-relate-2026/

### Fontes secundárias usadas com ressalva (blogs de concorrentes e agregadores)
eesel.ai · myaskai.com · getmacha.com · featurebase.app · coworker.ai · quiq.com · voiceflow.com · clonedesk.ai · callsphere.ai · digitalapplied.com · unthread.io · lorikeetcx.ai · twig.so · certainly.io · marketbetter.ai · knock-ai.com · wiserreview.com · corebee.ai · corepiper.com · valueaddvc.com · resolve247.ai · fastslowmotion.com · agencyq.com · jitendrazaa.com · chatarmin.com · suprmind.ai · solidroad.com · cowork.ink · spheron.network · getstream.io · benchmarkingagents.com · rasa.com/blog · disclosed.sh · machertecnologia.com.br · martinelli.adv.br · entercastconsulting.com.br

### Repositório (leitura, sem modificação)
`enterprise/app/models/captain/*.rb` · `enterprise/app/models/captain_inbox.rb` · `enterprise/app/models/concerns/captain_tools_helpers.rb` · `enterprise/app/services/captain/**` · `enterprise/app/jobs/captain/**` · `enterprise/app/controllers/api/v1/accounts/captain/*.rb` · `enterprise/lib/captain/**` · `config/agents/tools.yml` · `config/features.yml` · `app/javascript/dashboard/components-next/ai-assistant/**`

### Lacunas declaradas (não verificado)
- Artigo oficial da Intercom sobre configuração de Guidance/Tasks/Actions (URL testada retornou 404)
- Preço oficial da Zendesk por automated resolution (só fontes secundárias)
- Página oficial de preços da Freshworks para Freddy AI Agent
- Página oficial de preços da Crisp para Hugo/MagicReply
- Comunicado oficial de sunset do Drift pela Salesloft/Clari
- Se a votação do PL 2338/2023 na Câmara ocorreu em 27/05/2026 e qual o resultado
- Valor exato da multa do SB 1001 no texto da lei
- Data exata do post "From resolutions to outcomes" da Intercom (o conteúdo cita 76% em junho de 2026)
- Se o widget web do ChatSPX declara "sou uma IA" por padrão (não localizei o comportamento no código lido)

---

**Fim do relatório.** Nenhum arquivo de código foi modificado. Único artefato: este documento.
