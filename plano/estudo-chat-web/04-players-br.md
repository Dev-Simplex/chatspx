# TASK 04 — Players Brasil / LATAM e concorrentes diretos da Leadster

> **Estudo de mercado — chat de site, marketing conversacional e atendimento omnichannel no Brasil**
> Documento de pesquisa para o projeto ChatSPX (fork de Chatwoot).
> **Data da coleta:** 11 de agosto de 2026. Todos os preços, planos e páginas foram consultados nesta data.
> **Fase:** estudo puro. Nenhuma implementação, nenhuma alteração de código.

---

## COMO LER ESTE DOCUMENTO

Cada afirmação relevante é marcada com um de três selos:

| Selo | Significado |
|------|-------------|
| **[FATO]** | Verificado diretamente na fonte primária (página oficial do fornecedor, documentação oficial, arquivo público baixado via `curl`). URL sempre citada. |
| **[FATO-2]** | Verificado apenas em fonte secundária (blog de terceiro, comparativo de concorrente, agregador). Tratar com desconfiança — muitos desses blogs são conteúdo de marketing de players rivais. |
| **[INFERÊNCIA]** | Leitura minha a partir dos fatos. Não é dado do fornecedor. |
| **[NÃO VERIFICADO]** | Tentei e não consegui confirmar. Registrado explicitamente para não virar invenção. |

**Regra que segui:** nenhum número, preço, endpoint, evento ou feature foi escrito sem origem. Onde a fonte é fraca, o selo diz isso.

---

## SUMÁRIO

- [1. Sumário executivo — os 12 achados que importam](#1-sumário-executivo--os-12-achados-que-importam)
- [2. Metodologia e limites da pesquisa](#2-metodologia-e-limites-da-pesquisa)
- [3. Mapa do mercado: as cinco categorias](#3-mapa-do-mercado-as-cinco-categorias)
- [4. Players — seção por player](#4-players--seção-por-player)
  - [4.1 Leadster (referência comparativa)](#41-leadster--referência-comparativa)
  - [4.2 RD Station Conversas (ex-Tallos)](#42-rd-station-conversas-ex-tallos)
  - [4.3 Octadesk](#43-octadesk)
  - [4.4 Huggy](#44-huggy)
  - [4.5 JivoChat](#45-jivochat)
  - [4.6 Take Blip / Blip](#46-take-blip--blip)
  - [4.7 Zenvia](#47-zenvia)
  - [4.8 Movidesk](#48-movidesk)
  - [4.9 Kommo (ex-amoCRM)](#49-kommo-ex-amocrm)
  - [4.10 Cliengo](#410-cliengo)
  - [4.11 Poli Digital (ex-Polichat)](#411-poli-digital-ex-polichat)
  - [4.12 Nexloo](#412-nexloo)
  - [4.13 Digisac](#413-digisac)
  - [4.14 ChatGuru](#414-chatguru)
  - [4.15 Umbler Talk](#415-umbler-talk)
  - [4.16 Botmaker](#416-botmaker)
  - [4.17 Weni (VTEX)](#417-weni-vtex)
  - [4.18 Chatvolt](#418-chatvolt)
  - [4.19 Fortics SZ.chat](#419-fortics-szchat)
  - [4.20 O ecossistema "Chatwoot-based" nacional](#420-o-ecossistema-chatwoot-based-nacional)
- [5. Tabela comparativa geral](#5-tabela-comparativa-geral)
- [6. Anatomia técnica dos widgets](#6-anatomia-técnica-dos-widgets)
- [7. Precificação praticada no Brasil](#7-precificação-praticada-no-brasil)
- [8. WhatsApp vs chat de site — o eixo que define o mercado](#8-whatsapp-vs-chat-de-site--o-eixo-que-define-o-mercado)
- [9. Práticas locais: LGPD, CPF/CNPJ, telefone, horário, tom de voz](#9-práticas-locais-lgpd-cpfcnpj-telefone-horário-tom-de-voz)
- [10. Reviews e reclamações públicas](#10-reviews-e-reclamações-públicas)
- [11. Mapa de posicionamento e onde o ChatSPX se encaixa](#11-mapa-de-posicionamento-e-onde-o-chatspx-se-encaixa)
- [12. IMPLICAÇÕES PARA O CHATSPX](#12-implicações-para-o-chatspx)
- [13. Lacunas de pesquisa](#13-lacunas-de-pesquisa)
- [14. Fontes](#14-fontes)

---

## 1. SUMÁRIO EXECUTIVO — OS 12 ACHADOS QUE IMPORTAM

**1. O chat de site virou um canal secundário na maioria das plataformas brasileiras — e alguns players simplesmente não têm.**
A Nexloo lista, na sua própria página de planos, WhatsApp, Instagram/Facebook, E-mail, Telegram e TikTok — **e nenhum webchat** [FATO — https://nexloo.com/planos/]. O ChatGuru se descreve como plataforma de WhatsApp (WhatsApp Web, API Oficial/WABA, modelo CoEX), sem menção a webchat na home [FATO — https://chatguru.com.br/]. Ou seja: parte relevante do mid-market brasileiro abandonou o chat de site.

**2. Quem manteve o webchat, manteve como "canal na lista", não como produto.**
Octadesk ("Chat no Site" dentro do Octa Conversas) [FATO — https://www.octadesk.com/integracoes], Digisac (Webchat como página de canal) [FATO — https://digisac.com.br/canais/webchat], Poli Digital ("Canal de Webchat/Site" na grade de planos) [FATO — https://poli.digital/planos/], Fortics SZ.chat (webchat entre 14 canais) [FATO — https://www.fortics.com.br/tabela-de-precos-sz-chat/]. Em todos, o marketing e a precificação giram em torno do WhatsApp.

**3. Só três categorias de player tratam o widget de site como o produto:** os "chat de captura" (Leadster, Cliengo), os live-chat clássicos (JivoChat) e as infra de canal com widget embarcado (Blip Chat, Zenvia Chat, Botmaker Webchat).

**4. A Leadster está migrando de "captura" para "atendimento".**
O plano Pro passou a listar **"chat online (novo)"** [FATO — https://leadster.com.br/preco/] e existe um produto **Leadster Live Chat** com atendimento humano em tempo real, horários configuráveis e exibição condicionada a operador online, disponível no **plano Full** [FATO — https://help.leadster.com.br/article/349-leadster-live-chat]. O player que nasceu "anti-live-chat" hoje vende live chat.

**5. O ticket brasileiro é bimodal e a distância é brutal.**
Faixa PME self-service: R$ 56–R$ 600/mês (ChatWoot BR, Nexloo, Umbler Talk, Leadster, Botmaker Standard). Faixa mid-market com vendas consultivas: R$ 989–R$ 4.999/mês (Huggy Custom, RD Conversas, Poli, Octadesk, Fortics). Não existe quase nada entre R$ 600 e R$ 989 — é um vale de posicionamento. [INFERÊNCIA sobre a estrutura; os valores individuais são [FATO], ver §7]

**6. Taxa de implantação e fidelidade são norma no mid-market, não exceção.**
Poli Digital: taxa de implantação **a partir de R$ 1.197,90** [FATO — https://poli.digital/planos/]. RD Conversas: ativação de WhatsApp **R$ 1.999** e integração de chatbot com RD Marketing/CRM **R$ 3.799** [FATO — https://tallos.com.br/planos/]. Zenvia: setup de **USD 137 a USD 842** conforme plano [FATO — https://zenvia.com/en/prices/]. Octadesk: onboarding cobrado à parte [FATO-2 — https://www.socialhub.pro/blog/octadesk-preco-e-planos-2026-comparativo-custo-beneficio/].

**7. A unidade de cobrança dominante deixou de ser "usuário" e virou "conversa única / DAU".**
Blip: DAUs, com conversa adicional a R$ 1,40 (Plus) e R$ 1,25 (Super) [FATO — https://www.blip.ai/planos/]. Octadesk: DAU consumido só quando o cliente responde [FATO — https://www.octadesk.com/planos-e-precos]. RD Conversas: "clientes únicos atendidos/mês" (1.000 / 3.000 / 5.000+) [FATO — https://tallos.com.br/planos/]. Nexloo: pacotes de conversas (1.000 / 2.000 / 6.000) [FATO]. Isso é herança direta do modelo de cobrança do WhatsApp.

**8. A "carteira de créditos" do WhatsApp é um segundo faturamento, sempre à parte.**
RD Conversas: carteira mínima de **R$ 300**, validade 12 meses, consumida por template enviado; se zerar, vira pós-pago na fatura [FATO — https://tallos.com.br/planos/]. Poli: pacotes de crédito de R$ 18 (100 créditos, R$ 0,18/un.) a R$ 120 (1.000 créditos) [FATO]. Zenvia: pacotes de canal separados do plano de software [FATO].

**9. Existe um ecossistema nacional inteiro construído em cima do Chatwoot — e ele já concorre com o ChatSPX.**
O **ChatWoot BR** (chatwoot.app.br) é um SaaS gerenciado de Chatwoot em português, com preços R$ 56/usuário/mês a R$ 664/mês, WhatsApp via QR incluso sem taxa por mensagem, e páginas de comparação explícitas *vs* Octadesk, Zenvia, Intercom, RD Station Conversas, Huggy, Poli Digital, JivoChat, Take Blip, Movidesk, Umbler Talk [FATO — https://chatwoot.app.br/precos]. Há ainda CWMKT (R$ 399–R$ 1.099/mês, whitelabel), Conexão Azul (revenda whitelabel) e BotAtende (whitelabel a R$ 10.000/ano) [FATO / FATO].

**10. O widget "que vira WhatsApp" é feature de primeira classe nos players de captura.**
O plano gratuito da Leadster já inclui **"redirecionamento para WhatsApp"** [FATO — https://leadster.com.br/preco/] e o plano Pro tem **"roleta de WhatsApp"** (distribuição entre números). O bundle da Huggy expõe `Huggy.openWhatsapp()`, `Huggy.openTelegram()`, `Huggy.openButtons()` e o tópico de evento `channel-open:whatsapp` [FATO — https://huggydigital.github.io/docs/pt/huggy-chat.html]. O script do Cliengo carrega um `loadWhatsAppWidget()` e tem flag `whatsAppActive` [FATO — arquivo baixado].

**11. Localização real (não tradução) é vantagem competitiva verificável.**
O bundle da Leadster carrega validadores e mensagens de erro nativas para **CPF, CNPJ, CPF/CNPJ, CEP, telefone, data DD/MM/AAAA e e-mail corporativo** — inclusive uma mensagem específica de "talvez esteja faltando um acento" [FATO — `neurolead.min.js`, 456 KB, baixado de https://cdn.leadster.com.br/neurolead/neurolead.min.js]. A Huggy documenta `custom_fields` com chaves `cpf_of_the_contact_customer` e `cnpj_of_the_company_customer` [FATO]. Huggy tem, em plano pago, **"Controle de feriados"** como item de tabela de preços [FATO — https://www.huggy.io/pt-br/pricing].

**12. O widget de site brasileiro é, tecnicamente, um iframe com uma API JS pequena.**
Blip Chat, Zenvia Chat e Cliengo montam `<iframe>`; Huggy e Kommo expõem objeto global com dezenas de métodos; Octadesk usa evento `on0ctaChatReady` + `octadesk.chat.login()`. Nenhum deles é um Web Component ou Shadow DOM na versão que consegui inspecionar. [FATO — ver §6]

---

## 2. METODOLOGIA E LIMITES DA PESQUISA

### 2.1 O que foi feito

1. **Busca web** por player (proposta, preço, canais, reviews).
2. **Download direto (`curl`) das páginas oficiais de planos** — porque as buscas retornam com frequência blogs de concorrentes com números desatualizados ou distorcidos. Todas as páginas foram convertidas para texto e os valores lidos do HTML bruto.
3. **Download e inspeção de assets públicos**: bundles JS de widget, arquivos de configuração de widget, plugin WordPress oficial (`.zip` do repositório do WordPress.org), listagem pública de bucket CDN.
4. **Detecção de widget instalado nos próprios sites dos fornecedores** — rodando `grep` sobre o HTML da home de cada player, para ver qual widget cada um usa em si mesmo (dogfooding ou não).

### 2.2 O que NÃO foi feito (e por quê)

- **Nenhum login, nenhum trial, nenhum scraping autenticado.** Isso significa que telas internas de configuração de widget (onde o snippet é gerado) não foram vistas. Onde a documentação pública não mostra o snippet, está marcado como [NÃO VERIFICADO].
- **Nenhum contato comercial.** Preços "sob consulta" ficaram sob consulta.
- **Nenhuma tentativa de burlar WAF/paywall.** Alguns sites (Leadster `/live-chat/`, help.blip.ai, Digisac `/planos/`, Conexão Azul, esaas.com.br) retornaram 403 ou checkpoint. Registrado como limitação.

### 2.3 Fontes que exigem desconfiança explícita

Uma parte grande do "conteúdo comparativo" brasileiro sobre essas ferramentas é **marketing de concorrente**. Nos resultados de busca apareceram repetidamente: `socialhub.pro`, `botaihub.com.br`, `tudoprawhats.com.br`, `zapfunil.com`, `botzila.io`, `interaflow.ai`, `mercabot.com.br`, `chatsac.com`, `nexloo.com/blog`. Todos são vendedores de solução concorrente escrevendo sobre rivais. **Nada desses sites foi usado como [FATO].** Quando é a única fonte disponível, o selo é [FATO-2] e o texto diz que é fonte interessada.

### 2.4 Cotação

Onde o preço original está em USD (Zenvia, Cliengo, Kommo internacional), **mantive em USD** e não converti — converter criaria número inventado. Onde houve conversão em fonte terceira, marquei.

---

## 3. MAPA DO MERCADO: AS CINCO CATEGORIAS

O enunciado da task propõe quatro categorias. A pesquisa mostrou que são **cinco**, porque o ecossistema whitelabel/open-source virou categoria própria no Brasil.

### Categoria A — Chat de captura / marketing conversacional
**Quem:** Leadster, Cliengo, (Invent, Drift no comparativo internacional).
**O que vendem:** mais leads no site. A métrica é taxa de conversão do visitante em lead.
**Quem compra:** **marketing** (gestor de tráfego, agência, head de growth).
**Unidade de cobrança:** visitas do site / conversas.
**Widget:** é o produto inteiro.

### Categoria B — Atendimento omnichannel / helpdesk
**Quem:** Octadesk, Huggy, Movidesk, Zenvia Customer Cloud, Digisac, Poli Digital, Nexloo, ChatGuru, Umbler Talk, Fortics SZ.chat.
**O que vendem:** organizar N atendentes em cima de canais (majoritariamente WhatsApp).
**Quem compra:** **operação / suporte / comercial** (gerente de atendimento, dono de PME).
**Unidade de cobrança:** usuário, DAU/conversa única, ou mensagem.
**Widget:** item de checklist.

### Categoria C — CRM com chat
**Quem:** Kommo, RD Station (Conversas + CRM + Marketing).
**O que vendem:** funil. A conversa é insumo do pipeline.
**Quem compra:** **vendas**.
**Unidade de cobrança:** usuário (Kommo) ou clientes atendidos/mês (RD).
**Widget:** existe (Kommo tem "website chat button" em todos os planos), mas é porta de entrada do lead no CRM.

### Categoria D — Infraestrutura de canal / plataforma de bots enterprise
**Quem:** Take Blip, Botmaker, Weni (VTEX), Zenvia (na perna de BSP/canais).
**O que vendem:** conectividade oficial, escala, SLA, compliance com Meta.
**Quem compra:** **TI / enterprise / integrador**.
**Unidade de cobrança:** conversa/DAU + seats + setup.
**Widget:** existe como SDK sério (Blip Chat, Botmaker Webchat Designer), porque enterprise precisa embutir chat em portal próprio.

### Categoria E — Whitelabel / open-source gerenciado (a categoria "chatwoot-based")
**Quem:** ChatWoot BR, CWMKT, Conexão Azul, BotAtende, ChatLabel/WhatsLabel, XAMA, e um mercado difuso de revendedores.
**O que vendem:** a mesma plataforma dos outros, mas em BRL, com marca do revendedor, sem taxa por mensagem, e frequentemente com WhatsApp via QR (não-oficial).
**Quem compra:** **agências, integradores, TI de PME, e o próprio cliente final que quer fugir de cobrança em dólar**.
**Unidade de cobrança:** usuário, conexões, ou licença anual de revenda.
**Widget:** herdado do Chatwoot upstream (o "Chat ao vivo no site" está listado explicitamente na página de recursos de um desses revendedores [FATO — https://chatwoot.com.br/precos]).

**[INFERÊNCIA]** O ChatSPX está hoje na Categoria E por origem (fork de Chatwoot) e na Categoria B por uso (operação de atendimento). Não está na Categoria A — e é exatamente lá que o widget web tem valor de venda próprio.

---

## 4. PLAYERS — SEÇÃO POR PLAYER

---

### 4.1 Leadster — referência comparativa

> Tratada aqui **apenas como referência**, conforme o escopo da task. A dissecação profunda do widget dela pertence a outra task deste estudo.

#### Proposta de valor e ICP
Plataforma de **marketing conversacional** que se posiciona como "a primeira 100% brasileira" [FATO-2 — resultado de busca sobre leadster.com.br]. A tese é substituir formulário estático por conversa proativa que qualifica e entrega lead. O ICP é **marketing** — a compra é do gestor de tráfego/agência, não do gerente de atendimento.

#### Planos e preços [FATO — https://leadster.com.br/preco/]

| Plano | Preço | Visitas/mês | Leads | Fluxos | Suporte |
|---|---|---|---|---|---|
| Free | R$ 0/mês | até 1.000 | 15/mês | 1 | Ticket |
| Starter | R$ 142/mês (anual) | até 1.000 | Ilimitados | 3 | Chat ao vivo |
| Pro | R$ 154/mês (anual) | até 1.000 | Ilimitados | Ilimitados | Chat + WhatsApp |

Notas verificadas na mesma página: cobrança anual com **20% de desconto**; **teste grátis de 14 dias sem cartão**; o preço **escala com o tráfego** (a faixa mostrada é a de 1.000 visitas/mês); mais de 2.000 integrações via Zapier/Webhook.

Free já inclui: **redirecionamento para WhatsApp**, páginas de captura, integrações com CRM, eventos Google/Meta, dashboard de performance.
Starter adiciona: chamadas inteligentes, lead scoring, analytics de fluxo, redirecionamento por link, localização do lead, **teste A/B**.
Pro adiciona: **Leadster AI**, gerente de conta dedicado, geração de chamadas por IA, **roleta de WhatsApp**, agendamento de reuniões, super dashboard de mídia, **chat online (novo)**.

#### Produtos além do Website Suite [FATO]
- **WhatsApp Suite** — mesmos fluxos e agentes dentro do WhatsApp [FATO-2 — https://help.leadster.com.br/article/311-whatsapp-leadster].
- **ShopBot** — vendedor virtual com IA para e-commerce, hospedado em `shopbot.leadster.com.br` (URL confirmada dentro do bundle) [FATO].
- **Leadster Live Chat** — atendimento humano em tempo real no site, com exibição do nome do operador, janelas de horário/dia configuráveis e opção de só exibir o chat quando há operador online. Disponível no **plano Full** [FATO — https://help.leadster.com.br/article/349-leadster-live-chat].

#### Widget — o que é verificável de fora [FATO]
Snippet oficial, extraído do plugin WordPress publicado pela própria Leadster (`views/script-code.php`):

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
  })(window, document,
     "https://cdn.leadster.com.br/neurolead/neurolead.min.js",
     "<?php echo esc_attr($leadster_script_code) ?>");
</script>
<!--END LEADSTER SCRIPT-->
```
*(baixado de https://downloads.wordpress.org/plugin/leadster-marketing-conversacional.zip)*

Fatos técnicos do bundle `neurolead.min.js` (456.101 bytes, baixado):
- Globais expostas: `neuroleadId`, `neuroleadCompanyId`, `neuroleadScriptId`, `neuroleadLanguage`, `neuroleadUser`, `neuroleadPSId`, `neuroleadEventDevMode`, `neuroleadLeadDemoMode`, `neuroleadsPreferredVersions`, `neurolead`, `neuroIngest`.
- API pública documentada para abrir por botão: `window.neurolead.open()` [FATO-2 — https://help.leadster.com.br/article/46-como-inserir-o-chat-em-um-botao-popup-no-seu-site].
- Integrações de tracking embutidas no bundle: `dataLayer`, `gtag`, `fbq`, `ga(`, com carregamento de `connect.facebook.net/en_US/fbevents.js` e `googletagmanager.com/gtag/js`.
- Redirecionamento nativo para `https://wa.me/`.
- i18n de fábrica: **pt-BR, es e fr** (strings completas para os três).
- **Validadores brasileiros nativos**: CPF (25 ocorrências de `CPF`), CNPJ (36 de `cnpj`), CPF/CNPJ combinado, CEP, telefone, data DD/MM/AAAA, e "e-mail corporativo válido" (bloqueio de e-mail pessoal — típico de B2B).
- Instalação suportada via HTML, **Google Tag Manager** (com "suporte a document.write" marcado) e plugin WordPress [FATO-2 — base de conhecimento Leadster].

**[INFERÊNCIA]** A Leadster é o benchmark de *localização* do widget, não de arquitetura. O diferencial verificável não é técnico-sofisticado: é ter regra de negócio brasileira dentro do fluxo (CPF, CNPJ, CEP, e-mail corporativo, roleta de WhatsApp) e um funil de mídia paga acoplado (gtag/fbq/dataLayer de fábrica).

---

### 4.2 RD Station Conversas (ex-Tallos)

#### Identidade
A Tallos foi absorvida pela RD Station: `tallos.com.br/planos` **é** a página de planos do RD Station Conversas, e o site da Tallos serve o mesmo frontend Next.js da RD (`marketing-rdstation-frontend.pages.dev`) [FATO — detecção de scripts em ambos os domínios].

#### Proposta de valor e ICP
Centralizar e automatizar atendimento em WhatsApp, Instagram, Chat e outros, com chatbots e agentes de IA, **amarrado ao ecossistema RD Marketing + RD CRM** [FATO — https://tallos.com.br/planos/]. ICP: **PME e mid-market brasileiro de marketing e vendas** que já é cliente RD.

#### Planos e preços [FATO — https://tallos.com.br/planos/]

| Plano | Preço | Franquia |
|---|---|---|
| Basic | **R$ 989/mês** | até 1.000 clientes atendidos/mês |
| Pro | **R$ 2.699/mês** | até 3.000 clientes/mês |
| Advanced | sob consulta | a partir de 5.000 clientes/mês, usuários ilimitados |

Definição oficial de "cliente atendido", transcrita: *"Um cliente atendido é um contato único que iniciou atendimento pelo WhatsApp ou respondeu um disparo ativo da empresa. São contabilizados apenas uma vez dentro do mês, independente de quantas vezes interagiram com a empresa."* [FATO]

**Custos além da mensalidade** [FATO, mesma página]:
- **Carteira de Créditos** — pagamento à parte, obrigatória para enviar templates de Marketing, Utilidade ou Autenticação. Crédito **anual, em R$, validade 12 meses, mínimo R$ 300**. Se zerar, o excedente vira **pós-pago na fatura seguinte**.
- Isenções: mensagens **iniciadas pelo cliente** (serviço) e mensagens originadas de **anúncios Click-to-WhatsApp via Meta Ads** não são cobradas dessa carteira.
- Implementação opcional: **ativação de WhatsApp R$ 1.999**; **integração de chatbot com RD Marketing ou RD CRM R$ 3.799**.
- A página exibia banner de **"Economize 10%"** (ciclo anual).

#### Widget de site
Existe: é o **"Widget Chat"** do RD Station Conversas, configurado em **Menu superior > Canais > Configurar Canais**, permitindo inserir o chat no site, conversar com visitantes e **coletar dados cadastrais do visitante** [FATO-2 — central de ajuda RD, https://ajuda.rdstation.com/s/article/Integração-com-chat-do-site]. Há documentação específica de "Atualizações de personalização no Widget" [FATO — existência do artigo em help.rdstation.com.br, que hoje redireciona para ajuda.rdstation.com].
**[NÃO VERIFICADO]:** snippet exato, opções de cor/posição, campos configuráveis e se há remoção de marca. A documentação detalhada está atrás de redirecionamento para portal Salesforce com conteúdo dinâmico.

#### WhatsApp vs site
Desequilíbrio total a favor do WhatsApp. A franquia do plano conta **cliente que iniciou atendimento pelo WhatsApp ou respondeu disparo** — o texto oficial nem menciona o webchat na definição da unidade cobrada [FATO]. Os produtos anunciados na navegação são "Agentes de IA (WhatsApp)", "Chatbot para WhatsApp", "Campanhas de WhatsApp", "CRM de Vendas por WhatsApp" [FATO].

#### Integrações nacionais
Nativa e profunda com **RD Station Marketing e RD Station CRM** — é o argumento central [FATO]. Isso é, no Brasil, uma barreira de entrada relevante: RD Station é o CRM/automação de marketing mais difundido no SMB nacional. [INFERÊNCIA]

#### Posicionamento vs Chatwoot/open source
Proprietário, fechado, vendido em pacote com o resto da suíte RD. Aparece como alvo explícito de comparação por revendedor Chatwoot nacional ("vs RD Station Conversas") [FATO — https://chatwoot.app.br/precos].

---

### 4.3 Octadesk

#### Proposta de valor e ICP
Plataforma de atendimento "de marketing a vendas e pós-venda", com três produtos declarados: **Octachat** (conversacional), **Octadesk** (helpdesk/ticket) e **WOZ** (IA generativa própria) [FATO — https://www.octadesk.com/integracoes, FAQ oficial]. ICP: **mid-market brasileiro de e-commerce e serviços**, com operação de suporte estruturada (SLA, tickets). Empresa do ecossistema Locaweb.

#### Planos e preços [FATO — https://www.octadesk.com/planos-e-precos]

| Plano | Preço | Conversas/DAUs | Usuários | Usuário adicional |
|---|---|---|---|---|
| One | **R$ 2.499/mês** | 3.000 | Ilimitados | R$ 130/mês |
| Flow (mais popular) | **R$ 4.399/mês** | 5.500 | Ilimitados | R$ 120/mês |
| Nexus (enterprise) | sob consulta | 9.000 | Ilimitados | R$ 100/mês |

Regra de cobrança transcrita da página: **"O DAU só é consumido quando o cliente responde"** — não conta no envio [FATO]. Todos os planos incluem: WhatsApp (API Oficial), Instagram, Facebook, **chat/widget**, Woz AI Agent, Woz Copilot, transcrição de áudio, campanhas em massa no WhatsApp, API pública, webhooks, pesquisa de satisfação, relatórios em tempo real, perfis de acesso customizados. O módulo Helpdesk exige taxa por usuário. Sem cobrança extra de IA em nenhum tier [FATO].
Onboarding cobrado à parte [FATO-2 — socialhub, fonte interessada].

#### Widget de site — o mais bem documentado publicamente entre os omnichannel BR
Configuração em **Configurações > Outros canais > Chat no site** (perfil admin), em três etapas: (1) aparência — **cor e posicionamento**; (2) apresentação — **título do chat, apresentar equipe de atendimento, mensagens online/offline**; (3) **formato de autenticação do usuário e comportamentos do chat**. O script é **gerado conforme as preferências selecionadas** e copiado ao final da página [FATO — https://help.octadesk.com/a/como-instalar-o-chat-no-meu-site/].

Auto-login (identificação automática do visitante) [FATO — https://help.octadesk.com/a/chat-do-site-identificado-automaticamente-auto-login/]:

```javascript
window.addEventListener('on0ctaChatReady', function () {
  octadesk.chat.login({
    name: "nome teste",
    email: "email@octa.com",
    customFields: [
      {
        id: 'codigo_campo_customizado',
        value: 'Informacao do contato',
        domainType: 2          // sempre 2 para campos de pessoa/contato
      }
    ]
  });
});
```

Suporte declarado a instalação em páginas estratégicas, blogs, aplicações e software [FATO]. Existe até um módulo AngularJS comunitário para embutir o OctaChat (`InCeres/angular-octadesk`) [FATO — repositório público no GitHub].

#### WhatsApp vs site
Equilíbrio maior que a média do mercado — a Octadesk vem do mundo helpdesk, então e-mail/ticket/chat têm peso real. Ainda assim, o "Octa Conversas" é descrito como plataforma de **chat-commerce** que conecta "WhatsApp (API Oficial), Instagram Direct, Facebook Messenger e Chat no Site" — o webchat aparece por último na enumeração oficial [FATO].

#### Integrações nacionais
Nativas com **RD Station, HubSpot, Pipedrive e Salesforce** (declarado no FAQ oficial) [FATO]. Dentro do ecossistema Locaweb: **Tray, Bling, King, Vindi, Bagy** [FATO-2 — botaihub, fonte interessada]. Há também "Superintegrações" para conectar o bot a sistemas próprios [FATO — https://kb.octadesk.com/docs/superintegracoes].

#### Curiosidade verificada
A home da própria Octadesk é **Webflow com HubSpot**, e carrega um `disable-hubspot-chatbot.js` — ou seja, o site institucional não roda o widget da Octadesk como chat principal [FATO — inspeção do HTML de https://www.octadesk.com/]. **[INFERÊNCIA]** Sinal de que o webchat não é o produto que eles usam para vender a si mesmos.

---

### 4.4 Huggy

#### Proposta de valor e ICP
"Plataforma completa de Atendimento Digital", vendida por times (Marketing, Suporte, Sucesso do Cliente, Vendas) e por produtos (Flow, Gatilhos, Contatos, Chatbots, Mobile, Analítico, Inbox, Omnichannel, Integrações, **Huggy Chat**, Conversation Page) [FATO — https://www.huggy.io/pt-br/pricing]. Base declarada: **mais de 4.000 empresas** [FATO]. Empresa baiana, ICP PME→mid-market.

#### Planos e preços [FATO — https://www.huggy.io/pt-br/pricing]

| Plano | Preço | Usuário incluso | Usuário adicional |
|---|---|---|---|
| Starter | **R$ 0,00/mês** | 1 conectado | + R$ 69,90/mês |
| Intermediário | **a partir de R$ 579/mês** | 1 conectado | + R$ 119,90/mês |
| Custom | **a partir de R$ 989/mês** | 1 conectado | + R$ 189,90/mês |

Anual economiza **20%**. Sem multa de cancelamento e sem fidelidade (declarado na página) [FATO]. Onboarding de implantação disponível para todos os planos (opcional).

Escada de features (transcrita):
- **Starter**: gestão de contatos, fila de atendimento, envio de arquivos, multicontas, indicadores, app móvel, todos os canais (com restrição de WhatsApp).
- **Intermediário**: + departamentos, **horário de funcionamento**, timeline do contato, campos personalizados, espiar chat, múltiplos relatórios, API/Webhook, workflows, histórico de atendimento.
- **Custom**: + dashboard, distribuição automática, histórico ilimitado, workflows ilimitados, flows ilimitados.

Itens da tabela comparativa que importam para o mercado BR [FATO]: **Controle de feriados** ("configure um horário de atendimento especial durante os feriados"), **Multicontas** (mesmo agente em várias contas Huggy), **Horário de funcionamento** (avisa o cliente fora do horário).

Canais: **Huggy Chat (site), Telegram, Messenger, E-mail, SMS, VoIP, WhatsApp Business API** (via provedores oficiais; restrito no Starter). Precificação de mensagem WhatsApp por quantidade e categoria [FATO].

#### Widget de site — o mais rico em API pública que encontrei no Brasil
Snippet oficial [FATO — https://huggydigital.github.io/docs/pt/huggy-chat.html]:

```html
<!-- Init code Huggy Chat -->
<script>
  var $_Huggy = {
    defaultCountry: '+55',
    widget_id: '0001',
    company: "0001"
  };
  (function(i,s,o,g,r,a,m){
    i[r]={context:{id:'8551dbde3f168db249381597eea81c71'}};
    a=o;o=s.createElement(o);o.async=1;o.src=g;
    m=s.getElementsByTagName(a)[0];m.parentNode.insertBefore(o,m);
  })(window,document,'script','https://js.huggy.chat/widget.min.js?v=8.0.0','pwz');
</script>
```

Note o **`defaultCountry: '+55'` como padrão de fábrica** — DDI brasileiro hard-coded no exemplo oficial.

Propriedades de configuração (`$_Huggy`): `name`, `phone`, `email`, `channelGreeting` (texto do "Me chame no WhatsApp/Telegram", default `"Oi"`), `afterLoad`, `beforeLoad`, `defaultCountry`.
Objeto separado `huggyData` — declarado **antes** da inicialização — carrega `variables: [{key, value}]` para alimentar o flow sem depender do chat já existir.

Métodos do objeto global `Huggy` (lista completa da doc oficial):
`showButton()`, `hideButton()`, `showChats()`, `hideChats()`, `openBox()`, `closeBox()`, `openButtons()`, `openChatByID(id)`, `openEmail()`, `openKnowledgeBase()`, `openMessenger()`, `openPhone()`, `openTelegram()`, `openWhatsapp()`, `recreateAttendance()`, `removeChats(id)`, `sendMessage(text)`, `setData()`, `setEmail()`, `setName()`, `setPhone(DDI, tel)`, `showTrigger(id)`, `startTrigger(id, position, message)`, `subscribe(topico, call)`, `login(authObject)`, `logout()`.

Tópicos de evento suportados por `subscribe`: `channel-open:whatsapp`, `channel-close:widget`, `box-opened:email`, `box-opened:phone`, `box-opened:chat`, `box-opened`, `box-closed`, `chat:message`, `chat:created`.

O payload de `chat:created` traz `authHash`, `chatID`, `customerSiteID`, `department`, `hash`, `presence`, `server: "https://ct.huggy.io"`, `smartTriggerID`, `token`, `whatsapp`.

Identificação segura do visitante: `window.huggyData = { userIdentifier, userHash, variables }`, com `userHash` sendo **JWT HS256** assinado com secret do painel — a doc traz exemplo completo em PHP [FATO]. Isso é exatamente o mesmo padrão do `identifier_hash` do Chatwoot.

`setData` aceita `custom_fields` com tokens do painel; o exemplo oficial usa literalmente `cpf_of_the_contact_customer` e `cnpj_of_the_company_customer` [FATO].

Há SDKs Android, iOS e Ionic [FATO — índice da doc].

Curiosidade: a própria doc da Huggy roda um widget com `var $_PowerZAP = {...}` apontando para `js.huggy.chat/widget.min.js` — resquício do nome antigo do produto ("PowerZAP"), ainda visível na variável do loader (`'pwz'`) [FATO — HTML da página de docs].

#### WhatsApp vs site
Huggy é dos poucos que mantêm o webchat como **canal de produto nomeado** ("Huggy Chat") com página própria, doc própria e SDK mobile. Mesmo assim, WhatsApp é o canal comercialmente destacado e o único com precificação por mensagem [FATO].

#### Ferramentas gratuitas de captação (relevante como tática)
A Huggy publica **"Botão Flutuante do WhatsApp"** e **"Gerador de Link do WhatsApp"** como ferramentas gratuitas no menu do site [FATO]. **[INFERÊNCIA]** É isca de topo de funil para o mesmo público que buscaria "botão de WhatsApp no site".

---

### 4.5 JivoChat

#### Proposta de valor e ICP
É o **live chat clássico** do mercado brasileiro: "chat online grátis para sites". Vende messenger completo para site/e-commerce com Chat, Telefone, E-mail, Messenger, Telegram e WhatsApp [FATO — https://www.jivochat.com.br/pricing/]. ICP: **PME e e-commerce**, compra self-service, ticket baixo. Empresa de origem estrangeira (JivoSite) com operação brasileira forte.

#### Planos e preços [FATO — https://www.jivochat.com.br/pricing/]

| Plano | Preço (anual) | Destaques |
|---|---|---|
| **FREE** | R$ 0 — **inclui 5 operadores** | Chat online para site, Telegram, Facebook, Viber, E-mail, Callback, formulários offline, apps desktop/mobile |
| **BASE** (Básico) | **R$ 63/operador/mês** | Convites proativos, **botões pré-chat**, monitoramento de visitantes em tempo real, respostas prontas com assistente automático, anti-spam, JivoChat CRM |
| **PRO** (Profissional) | **R$ 126/operador/mês** | Instagram, Mercado Livre, Telefonia Plus, mensagens de voz, integração com chatbots, resgate de chats |
| **VIP** (Empresarial) | **R$ 238/operador/mês** | **SDK Mobile, roteamento de chats, videochamadas, Chat API** |

Teste grátis de 14 dias nos pagos.

**Add-ons cobrados à parte** [FATO, mesma página]:

| Add-on | Preço |
|---|---|
| WhatsApp | R$ 175/mês |
| Jivo Marketing | R$ 35/mês |
| Assistente IA (OpenAI) | R$ 84/mês |
| Módulo Instagram | R$ 35/mês |
| Mercado Livre | R$ 27/mês |
| Telefonia Plus | R$ 23/mês |
| Chamadas de vídeo | R$ 122/operador/mês |
| **Agente IA** ("resolução automática de até 80% das conversas") | **R$ 343/mês** |

#### Widget de site
É o produto. O loader público responde em `https://code.jivosite.com/widget/{ID}` — baixei um bundle de **18.483 bytes** que localiza a própria tag via `document.currentScript`, `script[jv-id]` ou `script[data-jv-id]`, e valida padrões de URL `widget/{id}`, `/script/widget/{id}` e `/script/geo-widget/{id}` [FATO — arquivo baixado].
**[INFERÊNCIA]** A existência de `geo-widget` sugere variação de widget por geolocalização (roteamento regional), o que faz sentido para operações multi-loja.

Features de widget confirmadas na página de planos: **convites proativos**, **botões pré-chat**, **monitoramento de visitantes em tempo real**, **formulários offline**, **callback** (agendar ligação) [FATO].

#### WhatsApp vs site
Inverso da média brasileira: o site é o núcleo, e **WhatsApp é add-on pago de R$ 175/mês** [FATO]. **[INFERÊNCIA]** Isso é uma anomalia estrutural no mercado BR e provavelmente explica por que o Jivo perde terreno para plataformas WhatsApp-first no SMB nacional.

#### Distribuição
Presente nos marketplaces de e-commerce nacionais: **Loja Integrada** e conteúdo oficial na **Nuvemshop** [FATO — https://lojaintegrada.com.br/loja-aplicativos/jivochat/ e https://www.nuvemshop.com.br/blog/jivochat/].

#### Reviews
Nota média **3,8/5 na B2B Stack**, com melhor nota em custo/benefício, seguida de facilidade de uso, suporte e funcionalidades [FATO-2 — B2B Stack via resultado de busca; a página de produto existe em https://www.b2bstack.com.br/product/jivochat].

---

### 4.6 Take Blip / Blip

#### Proposta de valor e ICP
A plataforma **enterprise** de canais conversacionais do Brasil. Provedor oficial Meta (BSP). ICP: **grandes empresas e integradores**, com venda 100% consultiva.

#### Planos e preços
A página pública de planos expõe **Plus / Super / Enterprise** com limites, mas **não expõe o preço-base** no HTML servido [FATO — https://www.blip.ai/planos/; verifiquei o HTML de 1.022.945 bytes e os valores de mensalidade não estão lá].

Limites e preços marginais que **estão** públicos [FATO — mesma página]:

| Recurso | Plus | Super | Enterprise |
|---|---|---|---|
| Atendentes | até 30 | até 50 | ilimitados |
| Conversas únicas (DAUs) | 2 mil/mês | 5 mil/mês | sob demanda |
| Conversa adicional | **R$ 1,40** | **R$ 1,25** | n/a |
| Atendente adicional | **R$ 150** | **R$ 100** | n/a |
| Suporte | dias úteis, comercial | todos os dias, qualquer hora | todos os dias, qualquer hora |
| SLA declarado | 99,5% | 99,5% | — |

Definição oficial de DAU, transcrita: *"conversas contabilizadas a partir do envio ou recebimento de qualquer tipo de mensagem via Blip entre 0h e 23h59 do mesmo dia. São contabilizadas uma única vez por canal... Contam como conversas únicas o atendimento humano (via Blip Desk) e as notificações ativas, além de mensagens por chatbots."* [FATO]

**Blip Go** (tier SMB): valores divergem entre fontes secundárias — R$ 99/mês, R$ 299/mês, e R$ 179,90–R$ 399,90 quando revendido pela **Claro Empresas** [FATO-2 — bossbot.uk, botaihub, mobiletime.com.br]. A página oficial de ajuda (`help.blip.ai`) retornou **403** nas minhas tentativas. **[NÃO VERIFICADO]** — não use nenhum desses números como referência firme.

#### Widget de site — o SDK mais sério do mercado brasileiro
Repositório público oficial: `takenet/blip-chat-widget` [FATO — https://raw.githubusercontent.com/takenet/blip-chat-widget/master/README.md].

```html
<script src="https://unpkg.com/blip-chat-widget@1.11.*" type="text/javascript"></script>
<script>
  (function () {
    window.onload = function () {
      new BlipChat()
        .withAppKey('YOUR-APP-KEY')
        .withButton({"color":"#2CC3D6"})
        .build();
    }
  })();
</script>
```

Também distribuído como módulo npm (`import { BlipChat } from "blip-chat-widget"`).

Parâmetros opcionais documentados: `withAppKey`, `withButton` (cor e ícone), `withAuth` (tipo de auth, identidade e senha), `withAccount`, `withEventHandler`, `withTarget` (elemento que conterá o chat — permite chat inline, não só bolha), `withCustomStyle`, `withCustomCommonUrl`, `withCustomSearchParams`.

Eventos: `OnEnter`, `OnLeave`, `OnLoad`, `OnCreateAccount`.
Auth: modo *guest* mantém o mesmo `userIdentity` gerado por **30 dias**; modo DEV exige `userIdentity` e `userPassword`.
`withAccount` aceita `fullName`, `email`, `phoneNumber`, `city`.
Envio programático: `blipClient.sendMessage({type: "text/plain", content: "Start"})`.
Restrição operacional documentada: é preciso **cadastrar todos os domínios** do site no portal, senão o widget não funciona.
Recomendação oficial notável: *"For publishing purposes, download the script and make a reference to it locally. CDN may have availability problems and cause BLiP Chat instability."* [FATO]

#### Detecção
O site `blip.ai` roda WordPress + Elementor e carrega um script próprio de bot em `https://www.blip.ai/scripts-bot/javascript/2023-v1-main.js`, que por sua vez escolhe entre `2023-v2-main-hml.js` e `2023-v2-main-prod.js` conforme a URL conter `hml-` [FATO — arquivo baixado; o loader de homologação está exposto em produção].

#### Posicionamento
Sem plano gratuito e sem self-service na plataforma principal; o funil é diagnóstico → proposta → contrato → onboarding com Professional Services [FATO-2 — botaihub]. Reputação Reclame Aqui citada como 8,2/10 com 97,6% de resolução [FATO-2 — botaihub, fonte interessada].

---

### 4.7 Zenvia

#### Identidade e escopo
Empresa brasileira listada na NASDAQ (ZENV), no mercado desde 2003. Consolidou várias aquisições sob o guarda-chuva **Zenvia Customer Cloud**: a **Sirena** virou **Zenvia Conversion**, e a **Movidesk** foi absorvida ("Movidesk agora é Zenvia") [FATO — https://www.movidesk.com/planos/ exibe literalmente "Movidesk agora é Zenvia"; FATO-2 para a linhagem Sirena→Conversion].

#### Planos e preços [FATO — https://zenvia.com/en/prices/, versão em inglês, valores em USD]

| Plano | Mensalidade | Usuários | Interactionz | Usuário adicional | Interactionz adicional | Setup |
|---|---|---|---|---|---|---|
| Starter | **USD 0** | 1 | 100 | — | USD 1 | USD 137 no 1º mês se ativar WhatsApp |
| Specialist | **USD 130** | 10 | 500 | USD 53 | USD 0,28 | USD 137 no 1º mês |
| Expert | **USD 390** | 30 | 2.000 | USD 32 | USD 0,21 | USD 421 no 1º mês |
| Professional | **USD 845** | 50 | 5.000 | USD 22 | USD 0,19 | USD 842 no 1º mês |
| Enterprise | sob consulta | sob consulta | sob consulta | sob consulta | sob consulta | sob consulta |

**Pacote de canal é separado do plano de software** [FATO]. A calculadora oficial converte volume em pacote; exemplos de pacotes exibidos: até 1.088 SMS **ou** 362 WhatsApp; 3.202 SMS ou 1.066 WhatsApp; 6.804 SMS ou 2.262 WhatsApp; 14.517 SMS ou 4.831 WhatsApp — com a nota de que o cliente pode **combinar canais** dentro do pacote. Totais compostos exibidos na página: **USD 410/mês** e **USD 865/mês** (plano + pacote) [FATO].

Distinção oficial cobrada: **"WhatsApp Business"** = iniciado pela empresa; **"WhatsApp User"** = iniciado pelo consumidor; ambos faturados por sessão de 24 horas [FATO].

Fonte secundária dá os equivalentes em BRL (Starter grátis, Specialist R$ 600, Expert R$ 1.800, Professional R$ 3.900, ativação de WhatsApp a partir de R$ 649) [FATO-2 — tudoprawhats, fonte interessada]. **Não use esses BRL como oficial.**

#### Widget de site — verificado por engenharia reversa do próprio site da Zenvia
O site institucional carrega `https://static.zenvia.com/embed/js/zenvia-chat.min.js` (15.746 bytes, baixado e analisado) [FATO]. Achados do bundle:

- Constrói um **`<iframe>`** apontando para `https://chat.zenvia.com`.
- Carrega CSS externo `https://static.zenvia.com/embed/css/zenvia-chat.min.css`.
- Objeto de configuração `embeddedConfiguration` com a flag **`continuousConversation`**.
- **Cookie `_zid`** — UUID v4 gerado via `window.crypto.getRandomValues`, gravado com `path=/; SameSite=Lax; Secure`, usado para **continuidade de conversa entre sessões**. Se `continuousConversation` for falso, não persiste.
- Detecção de dispositivo por `Math.max(screen.width, screen.height) >= 1280 ? "desktop" : "mobile"`.
- Modo **`room`** (inline) além do modo bolha: aplica classes `znv-is-inline` e `znv-is-active`.
- Parâmetros de layout suportados: `width`, `height`, `marginBottom`, `marginRight`, `title`, `placeholder`, `color`.
- Classes CSS públicas: `znv-chat`, `znv-chat-container`, `znv-chat-header`, `znv-chat-header-close`, `znv-float-button`, `znv-iframe`, `znv-is-active`, `znv-is-inline`, **`znv-opt-in`**, `znv-opt-in-close`, `znv-opt-in-link`, `znv-opt-in-text`.
- Suporte a `markdown` e modo `buttonless`.
- Atributos de acessibilidade presentes no bundle: `aria-label`, `aria-live`, `aria-disabled`, `aria-invalid`, `role="alert"`, `role="status"`.
- Guard de duplicidade: lança `Error("Skipping duplicated zenvia-chat.js loading!")`.
- Mensagem interna `ZNV_REQUEST_SNAPSHOT` (postMessage host↔iframe).

**[INFERÊNCIA]** O bloco `znv-opt-in` (com texto, link e botão de fechar, removido do DOM ao abrir o chat) é, na prática, **o convite proativo com link — provavelmente para política de privacidade**. É a implementação mais próxima de "consentimento no widget" que encontrei em código real no mercado brasileiro.

#### WhatsApp vs site
A Zenvia é BSP: o WhatsApp é a receita. O webchat existe (é o `zenvia-chat`), está incluído em pacotes de canal e é usado pela própria empresa no site institucional — **dogfooding confirmado** [FATO].

#### Integrações nacionais
Conectores nativos declarados com **Omie** (base de contatos), **Bling** (gestão de vendas), **Olist** e **Microvix** [FATO-2 — https://zenvia.com/en/data-integration/native-connectors/ citado em resultado de busca; não consegui abrir a página diretamente por bloqueio de rede].

---

### 4.8 Movidesk

#### Estado atual
**Movidesk agora é Zenvia.** O site exibe: *"O sistema de atendimento que você conhece evoluiu e se tornou Zenvia Customer Cloud"* [FATO — https://www.movidesk.com/planos/].

#### Preço público [FATO — mesma página]
> **"Planos a partir de: R$ 700/mês • 10 usuários • 500 Interactionz"**
> (Interactionz = "créditos de interações que ocorrem dentro do software")

Fonte secundária menciona modelo alternativo de R$ 199,90 por agente/mês com mínimo de 5 agentes [FATO-2 — xpay.sh/saasworthy; **conflita** com o valor oficial da página; não use].

#### Proposta de valor e ICP
Helpdesk brasileiro clássico: gestão completa de tickets, configurações de ticket, **contratos de SLA**, automações e alertas, **atendimento conversacional por chat**, relatórios e recursos de IA generativa (resumo de conversa, análise de sentimento, sugestão de resposta) [FATO]. ICP: **operações de suporte estruturadas** (B2B, software, serviços).

#### Chat / widget
Descrição oficial: *"Gerencie chats de WhatsApp, Facebook Messenger, Instagram e **WebChat**, adicionando solicitações às filas de atendimento. Selecione ou atribua chats automaticamente e **converta conversas em tickets em tempo real**."* [FATO]
**[INFERÊNCIA]** O modelo mental aqui é diferente de todos os outros: no Movidesk, a conversa do site **vira ticket**, não vira lead. É o único player da lista onde o webchat alimenta um SLA formal.

**[NÃO VERIFICADO]:** snippet de instalação, opções de customização visual e API JS do WebChat Movidesk.

---

### 4.9 Kommo (ex-amoCRM)

#### Proposta de valor e ICP
**CRM conversacional**: o funil é o produto, e as mensagens (WhatsApp, Instagram Direct, Messenger, Telegram) são o combustível. Rebranding de amoCRM para Kommo em 2021 [FATO-2 — kommo.com/blog e comparativos]. ICP: **times de vendas de PME**, muito forte no Brasil via rede de parceiros/implementadores.

#### Planos e preços [FATO — https://www.kommo.com/pricing/]

| Plano | Preço (USD/usuário/mês) | Leads ativos | Canais | AI Agents | Créditos de IA/mês/usuário |
|---|---|---|---|---|---|
| Base | **USD 15** | 2.500 | 1 WhatsApp + Instagram | — | 750 |
| Advanced | **USD 25** | 5.000 | 3 WhatsApp + 3 Instagram | até 3 | 1.250 |
| Pro | **USD 45** | 10.000 | ilimitados | até 50 | 2.250 |
| Enterprise | customizado | customizado | customizado | customizado | — |

**Live chat / botão de chat no site está em todos os planos** ("Website chat button") [FATO].
Salesbot (construtor de bot) disponível em todos os planos [FATO].

Preços em BRL divulgados por **parceiro oficial** brasileiro (não é a Kommo): Advanced R$ 110/usuário/mês, Pro R$ 197/usuário/mês, com 14 dias de trial e bônus de parceria [FATO-2 — calculadorakommo.com.br, que é revendedor; tratar como preço de canal, não de tabela].

#### Widget de site — API pública bem documentada [FATO — https://pt-developers.kommo.com/docs/botão-de-chat-do-site-via-api]

Objeto de configuração `window.crmPluginConfig`, que precisa existir **antes** do código do botão:
- `hidden` — booleano, oculta o botão no load;
- `color` — sobrescreve a cor do botão (aceita hex/rgb/rgba);
- `onlinechat.mode` — **`'widget'`** (pop-up) ou **`'frame'`** (container customizado na página);
- `onlinechat.user_id` — vincula a sessão de chat entre dispositivos;
- `locale` — objeto com `extends` apontando para idioma base (**`'en'`, `'es'`, `'pt'`**) e sobrescrita de strings individuais (ex.: `compose_placeholder`, `new_messages`), incluindo formatação de data/hora em sintaxe **date-fns**;
- `theme` — cores de fundo, texto de sistema, header (opcional), balões de mensagem entrada/saída, altura do compose (**máx. 170px**) e botão de enviar.

Função global `crmPlugin()` com as ações: `'runChatShow'`, `'runChatHide'`, `'runDestroy'`, `'sendKeyActionHook'`.
Callbacks: `'onChatShow|onChatHide'`, `'onChatReady'`, `'onButtonClick'`, `'onConversationsChange'`.
Transferência de dados para o CRM: `crm_plugin.setMeta()` — passa contato/lead, campos customizados, notas e parâmetros de bot para os registros associados.
Distribuição: **plugin WordPress oficial gratuito** ("Website Chat Button: Kommo integration") no repositório do WordPress.org, exigindo conta Kommo [FATO].
Customizações declaradas: animação do botão e posicionamento **esquerda/direita** [FATO-2 — kommo.com/support].

**[INFERÊNCIA]** O `onlinechat.mode: 'frame'` da Kommo e o `withTarget` do Blip são a mesma ideia: permitir o chat **embutido numa página**, não só como bolha. É um requisito recorrente de quem quer página de contato dedicada.

---

### 4.10 Cliengo

#### Proposta de valor e ICP
Concorrente direto da Leadster em **LATAM** (origem argentina): chatbot que conversa com o visitante 24/7 e **captura dados de contato**, qualifica e roteia [FATO — https://www.cliengo.com/pricing/]. ICP: **marketing e vendas de PME**, com forte presença em imobiliárias e automotivo (há um "Agente Inmobiliario" no menu do produto) [FATO].

#### Planos e preços [FATO — https://www.cliengo.com/pricing/, em USD]

| Plano | Preço | Agentes | Chatbots | Conversas |
|---|---|---|---|---|
| Starter | **USD 45/mês** | 2 | 3 programáveis | 500 |
| Premium | **USD 119/mês** | 3 | 10 com IA | 2.000 |
| Business | **USD 259/mês** | 5 | até 20 com IA | 4.000 |
| Corporate | sob consulta | +5 | +20 | +4.000 |

Definição oficial de conversa: **"equivalentes a una sesión de 24 hs."** [FATO] — mesmo modelo de janela do WhatsApp aplicado ao webchat.
Trial de **14 dias sem cartão** [FATO].
Business adiciona **envio de mensagens salientes (HSM)** e **integração com WhatsApp API** — com o aviso explícito de que **o preço não inclui os custos da Meta** [FATO].
Google Ads é integração destacada em todos os planos [FATO].
Fonte da empresa afirma integração com "80% dos CRMs" e +1.300 apps [FATO-2 — material de parceiro].

#### Widget de site — o mais transparente tecnicamente de todos (por acidente)
O snippet é `https://s.cliengo.com/weboptimizer/{companyId}/{websiteId}.js`, colado antes de `</body>` em todas as páginas [FATO — https://help.cliengo.com/hc/es/articles/115002656327].

Baixei um desses arquivos de uma conta real e pública (3.819 bytes). **O arquivo é a configuração inteira do widget em texto claro** [FATO]. Estrutura verificada:

```javascript
window.Cliengo = {};
window.Cliengo.chatConfig = {
  "companyId": "...", "websiteId": "...",
  "whiteLabelId": "...", "whiteLabelName": "",
  "googleAdWordsConversionId": "", "googleAnalyticsId": "",
  "chatbotName": "Memo",
  "overrideConversation": { "salute": "", "chatbotName": "" },
  "phone": "+52...",
  "title": "...",
  "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "businessHoursConfiguration": null,
  "conversionPixels": "", "webSnippet": [],
  "customFeedbackImageUrl": "",
  "widgetIcon": "LIGHT_STROKE",
  "widgetStyle": "BAR",
  "chatWindowColor": "#cb9a22", "iconColor": "",
  "cliengoMeetings": "false",
  "chatWindowTitle": "Chat de ventas",
  "chatWindowInputPlaceholder": "Escribe un mensaje...",
  "chatInitialMessage": "<p ...>¡Hola! ...</p>[[Opção A, Opção B, Opção C]]",
  "chatIsWritingMessage": " está escribiendo...",
  "chatSaluteTimeInSeconds": 2,
  "avatarImgUrl": "https://res.cloudinary.com/.../avatar.png",
  "planType": "CLIENGO_FREE",
  "vertical": "OTHER",
  "formHooksEnabled": false,
  "automaticRemarketingEnabled": true,
  "chatEnabled": false,
  "poweredBy": { "text": "Usamos Cliengo ", "link": "https://www.cliengo.com/?utm_source=usamos_cliengo&utm_medium=chat", "img": "..." },
  "customPoweredByUtms": "", "softDisable": false,
  "hasConvertedLead": false,
  "CDN_URL_DOMAIN": "//d47r8x2gwo1do.cloudfront.net",
  "WS_CHATBOT_URL": "wss://chatbot.cliengo.com",
  "sessionPath": "/s/{companyId}/{websiteId}",
  "cacheVersion": "...", "debug": false,
  "whatsAppActive": false,
  "lang": "es", "widgetVersion": "2.0",
  "redirectToWPLite": false
};
var host = 'https://lw2.cliengo.com';
// injeta <script id="mainclgo" src="https://lw2.cliengo.com/mainclgo.bundle.js"
//   data-company-id data-source-id data-host async>
// e chama loadWhatsAppWidget()
```

Fatos que esse arquivo revela sobre o produto:
- **Whitelabel é nativo** (`whiteLabelId`, `whiteLabelName`, `customPoweredByUtms`) — e o "Usamos Cliengo" com UTM é o modelo de crescimento viral do plano gratuito.
- **Horário comercial** é configuração de primeira classe (`businessHoursConfiguration`).
- **Botões de resposta rápida** são codificados **dentro da própria mensagem inicial** com a sintaxe `[[Opção A, Opção B]]` — solução de baixa cerimônia, muito prática.
- **Delay de saudação** configurável em segundos (`chatSaluteTimeInSeconds: 2`).
- **Estilo de widget** com enum (`widgetStyle: "BAR"`, `widgetIcon: "LIGHT_STROKE"`).
- **Remarketing automático** (`automaticRemarketingEnabled`).
- Transporte é **WebSocket** (`wss://chatbot.cliengo.com`).
- Existe um caminho de "WP Lite" (`redirectToWPLite`) e um `loadWhatsAppWidget()` separado, com `whatsAppActive` como chave.
- Vertical do cliente é parte da config (`vertical`), sugerindo templates por segmento.
- Há um `token` JWT no arquivo público.

Também há **plugin WordPress oficial** [FATO — https://wordpress.org/plugins/cliengo/] e guias de instalação para Jimdo, WPML, PrestaShop e "só em algumas seções" [FATO — help.cliengo.com].

#### API
`https://connect.cliengo.com/v1/` com `GET /contacts`, `GET /conversations`, `GET /whatsapp/templates`, `POST /whatsapp/messages`, autenticação `Authorization: Bearer` [FATO — https://developers.cliengo.com/docs/javascript-api].

---

### 4.11 Poli Digital (ex-Polichat)

#### Identidade
Polichat virou **Poli Digital** (o domínio antigo redireciona) [FATO-2 — tudoprawhats]. Parceiro oficial Meta [FATO — https://poli.digital/parceiro-meta/]. Comunicação da própria empresa: **8 anos de Poli** e **1.200 empresas** [FATO — banner em https://poli.digital/planos/].

#### Estrutura de produto [FATO — navegação oficial]
- **Poli Chat** — multiatendimento (vários atendentes em um número).
- **Poli Flow** — CRM com funil, tarefas, agendamento.
- **Poli Marketing** — painel de marketing.
- **Poli Pay** — catálogo, carrinho e link de pagamento dentro da conversa [FATO-2 — tudoprawhats].

#### Planos e preços [FATO — https://poli.digital/planos/]

| Plano | Mensalidade | Usuários inclusos | Usuário adicional | Créditos inclusos |
|---|---|---|---|---|
| Entrada | **R$ 369,90/mês** | 3 | R$ 129,90/mês | 250 |
| Inicial | **R$ 849,90/mês** | 7 | R$ 119,90/mês | 250 |
| Expansão | **R$ 1.399,90/mês** | 12 | R$ 109,90/mês | 500 |
| Ilimitado | **R$ 4.999,90/mês** | ilimitados | **sem custo** | 1.000 |

**Taxa de implantação e configuração: a partir de R$ 1.197,90** — em todos os planos [FATO].
**Conta oficial de WhatsApp adicional: R$ 269,90/mês por canal** [FATO].
Pacotes de crédito avulsos [FATO]: 100 créditos R$ 18 (R$ 0,18/un.), 250 por R$ 40 (R$ 0,16), 500 por R$ 70 (R$ 0,14), 1.000 por R$ 120 (R$ 0,12).
Aviso oficial: os valores de mensagem da API oficial seguem a **política de precificação da Meta** e estão sujeitos a alteração [FATO].
Contrato de 12 meses [FATO-2 — tudoprawhats].

#### Canais na grade de planos [FATO]
Ligações VoIP, Disparador em Massa, **1 Conta Oficial de WhatsApp**, Canal de Instagram, Canal de Facebook Messenger, **Canal de Webchat/Site**, organização de clientes em carteiras.

**[FATO]** O webchat existe e está na tabela de planos. **[NÃO VERIFICADO]:** snippet, customização e API JS do webchat da Poli.

#### WhatsApp vs site
WhatsApp-first sem ambiguidade: o produto é vendido como "um número, vários atendentes", e o webchat é linha de tabela.

---

### 4.12 Nexloo

#### Proposta de valor e ICP
"WhatsApp Múltiplos Usuários, Chatbots de IA, CRM, integração de canais" — autodescrita como "plataforma de atendimento nº1 do Brasil" [FATO — https://nexloo.com/]. Razão social no rodapé: **Evolvy Comunicação Omnichannel Ltda** [FATO]. ICP: **PME que quer preço baixo e usuários ilimitados**.

#### Planos e preços [FATO — https://nexloo.com/planos/]

| Plano | Mensalidade | Conversas | Disparos inclusos |
|---|---|---|---|
| START | **R$ 149,00** | até 1.000 | — |
| PLANTONISTA (mais popular) | **R$ 349,00** | até 2.000 | 500 |
| PRO+ | **R$ 599,00** | até 6.000 | 1.000 |

Todos com **conexões de WhatsApp ilimitadas, usuários ilimitados, CRM Kanban incluso, contas de e-mail ilimitadas, Telegram ilimitado**. START não tem Agente de IA nem Typebot/Fluxos; PLANTONISTA e PRO+ têm ambos.

Serviços extras [FATO]: WhatsApp adicional R$ 49,90; Instagram/Facebook adicional R$ 39,90; e-mail adicional R$ 19,90; Telegram adicional R$ 19,90; **1.000 conversas adicionais R$ 89,90**; 1.000 disparos adicionais R$ 49,90; **hora técnica R$ 150,00**.
Trial de **7 dias sem cartão** [FATO]. O formulário de trial pede **Nome, WhatsApp com DDD, CPF/CNPJ e e-mail corporativo** [FATO — campos do formulário na página].

#### Widget de site
**Não existe menção a webchat/chat de site** nem na página de planos nem na página de solução [FATO — https://nexloo.com/planos/ e https://nexloo.com/solucao/]. Canais citados: WhatsApp, Instagram/Facebook, E-mail, Telegram, TikTok.

**Detalhe revelador**: o próprio site da Nexloo usa o plugin WordPress **`click-to-chat-for-whatsapp`** para o botão de contato — não um widget próprio [FATO — inspeção do HTML de https://nexloo.com/]. **[INFERÊNCIA]** Uma plataforma de atendimento que resolve o próprio contato do site com um plugin genérico de botão de WhatsApp é o retrato mais claro do que aconteceu com o chat de site no Brasil.

---

### 4.13 Digisac

#### Proposta de valor e ICP
Multiatendimento consolidado: "atenda no WhatsApp, Instagram, Facebook, **WebChat**, Telegram, SMS ou e-mail, tudo centralizado" [FATO — https://digisac.com.br/]. ICP: **PME e mid-market**, muito forte em contabilidades e serviços (há distribuição via Contábil Store) [FATO-2].

#### Preços
**Não são públicos.** Todas as URLs candidatas (`/planos-e-precos-digisac`, `/planos/`, `/precos/`) retornaram **404**, e a home direciona para "solicitar uma demonstração com nossos consultores" [FATO — testado; texto do FAQ oficial]. Valores citados por fonte secundária (Premium Lite R$ 299/mês até 3 atendentes; Premium Pro R$ 589/mês; Premium Enterprise R$ 1.369/mês) vêm de blog de concorrente [FATO-2 — socialhub.pro]. **[NÃO VERIFICADO]**.
Formas de pagamento declaradas por terceiro: boleto, cartão recorrente ou Pix [FATO-2].

#### Widget de site — a melhor página de venda de webchat do mercado BR
A Digisac tem uma landing page dedicada ao **Webchat**, e o copy é o melhor diagnóstico do problema que o chat de site resolve no Brasil [FATO — https://digisac.com.br/canais/webchat, transcrito]:

> *"Seu site recebe visitas, mas não gera conversas?"* — com quatro dores nomeadas: **Resposta Demorada** ("o visitante busca a concorrência em segundos"), **Fricção no Contato** ("o time comercial depende de formulários estáticos que ninguém quer preencher"), **Abandono de Leads** ("leads quentes abandonam o site sem deixar rastro de sua intenção"), **Falta de Inteligência** ("não há registro imediato da intenção do cliente para retargeting").
> *"Quem responde primeiro, vende mais."*

Features declaradas do webchat: atendimento em tempo real, **captura automática de leads**, integração com CRM, **widget personalizável** ("adapte cores, mensagens e identidade visual à sua marca"), histórico completo, integração multicanal (a conversa entra no mesmo painel do WhatsApp/Instagram), **distribuição automática** para o setor correto, registro imediato de contato [FATO].

**[NÃO VERIFICADO]:** snippet, API JS e nível real de customização.

---

### 4.14 ChatGuru

#### Proposta de valor e ICP
Automação de WhatsApp para "operações complexas". Canais suportados, conforme a própria home: **WhatsApp Web, API Oficial (WABA) e modelo CoEX** — **sem Instagram, sem webchat, sem chat de site** [FATO — https://chatguru.com.br/].
Números declarados: **+6.000 clientes em 9 países**; verticais de direito, saúde, bem-estar e educação; cita IBMEC, Havaianas e Wizard como clientes [FATO].
Argumentos de venda quantificados na home: "converte até 40% mais respondendo mais rápido", "reduz absenteísmo clínico em até 50%", "automatiza cobranças reduzindo inadimplência em 60%", "atende 2x mais contatos sem aumentar a equipe" [FATO — copy da própria empresa; são claims de marketing, não dados auditados].

#### Planos e preços
Planos nomeados: **Essencial, Performance, Profissional** [FATO — https://chatguru.com.br/planos-e-precos/]. A página mostra "A partir de" e "2 usuários", mas **os valores numéricos não são renderizados no HTML servido** — a conversão é sempre "Falar com um especialista" / "Quero uma demonstração" [FATO].
Valores de fonte secundária: ~R$ 692/mês para 1 usuário + 1 número + R$ 500 de instalação; ou USD 49 (Basic, 3 agentes) e USD 109 (Pro, 8 agentes) [FATO-2 — tudoprawhats e multiwasap, ambos interessados; **os dois conjuntos são incompatíveis entre si**]. **[NÃO VERIFICADO]**.

#### Posição no estudo
**[INFERÊNCIA]** ChatGuru é o exemplo puro do player brasileiro que **decidiu não ter chat de site**. Vale como contraponto: é possível construir um negócio de +6.000 clientes no Brasil ignorando completamente o webchat.

---

### 4.15 Umbler Talk

#### Proposta de valor e ICP
Braço de atendimento da Umbler (hospedagem gaúcha). Centraliza WhatsApp, Telegram, Instagram e Messenger, com CRM de WhatsApp e chatbot [FATO-2 — páginas de produto da Umbler citadas nos resultados; a página `/talk/precos` retornou 404 na minha tentativa]. ICP: **micro e pequena empresa**, ticket muito baixo, venda self-service dentro da base de hospedagem.

#### Planos e preços [FATO-2 — socialhub.pro e help.umbler.com; **não confirmados em página oficial de preços**]
- **Basic**: R$ 69/mês para **2 atendentes** (exige plano anual), com a maioria dos recursos do Professional.
- **Professional**: R$ 79/atendente/mês (anual) ou R$ 99/mês (trimestral).
- Tier superior: R$ 109/atendente/mês (anual) ou R$ 129/mês (trimestral).
Há registro público de reajuste do produto anterior "uTalk" em 24/09/2022 [FATO — https://blog.umbler.com/br/utalk-reajuste-de-precos/].

**[NÃO VERIFICADO]:** existência e características de widget de chat de site no Umbler Talk. As páginas encontradas falam de WhatsApp, Telegram, Instagram e Messenger.

**[INFERÊNCIA]** Umbler Talk é a faixa de preço mais baixa entre plataformas de atendimento com marca conhecida no Brasil — e é o piso que qualquer produto self-service brasileiro precisa considerar.

---

### 4.16 Botmaker

#### Proposta de valor e ICP
Plataforma LATAM (origem argentina) de **agentes de IA multicanal**: chat, e-mail e voz. Canais: WhatsApp, Instagram, Facebook Messenger, Facebook Workplace, Google Business Messages, **Mercado Livre**, Slack, Microsoft Teams, Telegram, **Webchat**, Apple Messages for Business [FATO — https://www.botmaker.com/pt-br/precos]. Selos declarados: **WhatsApp BSP — Meta Oficial** e **SOC 2 Type II** [FATO]. ICP: **mid-market e enterprise LATAM**.

#### Planos e preços [FATO — https://www.botmaker.com/pt-br/precos]

| Plano | Mensalidade | Conversas/mês | Licenças de atendente | Excedente por conversa |
|---|---|---|---|---|
| Standard | **R$ 600** | até 900 | 10 gratuitas | **R$ 0,46** |
| Scale | **R$ 1.100** | até 1.800 | 10 gratuitas | **R$ 0,40** |
| Pro | **R$ 2.250** | até 4.300 | 20 gratuitas | **R$ 0,31** |
| Enterprise | sob consulta | orçamento personalizado | — | — |

Todos: **criação de conta na plataforma grátis**, **até 300 conversas iniciais grátis**, **quantidade ilimitada de bots**, suporte via tickets.
**Criar conta de WhatsApp Business Platform custa R$ 500, cobrado uma única vez** [FATO].
Dois modelos de serviço: **Account Manager** (especialista configura) e **Self-Service** (cliente configura, doc online, atendimento em horário comercial) [FATO].

#### Widget de site — "Webchat Designer"
É um produto nomeado dentro da plataforma [FATO — https://botmaker.com/en/platform/functions]. Customização declarada: **nome, logo, cores, tamanhos, fontes e objetos visíveis**; biblioteca de **temas** prontos; **menu persistente** sempre visível levando a fluxos do chatbot; abas de configuração **Instalação / Geral (posicionamento, formas de exibição, tipografia) / Personalização (cores e estilos)** [FATO — https://help.botmaker.com/pt/help/7947490493588934594 e /2710269571575244651].
**[NÃO VERIFICADO]:** o snippet em si (a doc diz que o código está na aba Instalação, dentro do painel autenticado).

**[INFERÊNCIA]** O "Webchat Designer" com temas e tipografia é o nível de customização visual mais alto que encontrei documentado publicamente entre os players que atuam no Brasil — acima do que Octadesk, Digisac e Poli descrevem.

---

### 4.17 Weni (VTEX)

#### Identidade e evento societário
Fundada em 2012 em Maceió (AL). **Adquirida pela VTEX** [FATO — https://vtex.com/pt-pt/blog/vtex-adquire-weni-cx-potenciada-por-ia/ e cobertura em startups.com.br, braziljournal.com]. Valor não divulgado oficialmente; fontes próximas ao negócio indicaram **menos de US$ 5 milhões** com earnout de três anos para os cinco fundadores [FATO-2 — Brazil Journal]. Base declarada de **160 clientes**, incluindo Stone, Raízen, Cruzeiro do Sul, Cencosud e Prezunic [FATO-2 — cobertura de imprensa]. Plano declarado: virar unidade de negócio independente dentro da VTEX e ser oferecida aos **2.600 clientes de e-commerce da VTEX** [FATO-2].

#### Produto
Plataforma **open-source** de automação de comunicação com IA própria, com suporte declarado a mais de 180 idiomas e dialetos, mentorada e financiada pelo **UNICEF Innovation Fund** [FATO-2 — materiais de parceiros e Capterra]. Canais integrados: WhatsApp, WhatsApp API, Telegram, Slack, Microsoft Teams, Discord, Instagram, Facebook, **RocketChat**, Infobip, Viber, Twitter/X, JioChat [FATO-2 — Capterra/GetApp].

#### Preços
**[NÃO VERIFICADO]** — não há tabela pública de preços da Weni em BRL que eu tenha conseguido confirmar.

#### Relevância para o ChatSPX
**[INFERÊNCIA]** A Weni é o precedente mais próximo do ChatSPX em modelo (base open-source brasileira, integração com canais, IA própria) e o desfecho é instrutivo: apesar de clientes enterprise e selo UNICEF, o desfecho foi aquisição por valor modesto por um player de plataforma (VTEX) que queria o pedaço de CX. Ou seja: **plataforma conversacional isolada tem teto; acoplada a uma plataforma de negócio (e-commerce, CRM), tem valor**.

---

### 4.18 Chatvolt

#### Proposta de valor e ICP
Plataforma **brasileira** de agentes de IA: "chatbots inteligentes para WhatsApp, Instagram e **sites**, com mais de 50 modelos de IA", treináveis com dados da empresa (RAG) [FATO — título e descrição de https://www.chatvolt.ai/]. ICP: **PME, criadores e agências** — a distribuição é fortemente via YouTube/curso gratuito, não via vendas consultivas [FATO — múltiplos vídeos de "Minicurso ChatVolt" e "Curso Gratuito Chatvolt"].

#### Preços
A página `/pricing` é **SPA renderizada no cliente** — o HTML servido tem 15.113 bytes e contém apenas o título; nenhum valor está no documento inicial [FATO — testado em `chatvolt.ai/pricing`, `www.chatvolt.ai/pt-BR/pricing` e via WebFetch]. Fonte secundária cita "a partir de R$ 97/mês" e existência de plano gratuito limitado [FATO-2 — expandenegocios.com.br]. **[NÃO VERIFICADO]**.

#### Widget de site
Declarado ("sites" entre os canais), mas **[NÃO VERIFICADO]** em snippet, customização ou whitelabel.

**[INFERÊNCIA]** Chatvolt representa a nova safra brasileira: preço baixo, IA-first, distribuição por conteúdo, e o site como canal de terceira ordem depois de WhatsApp e Instagram.

---

### 4.19 Fortics SZ.chat

#### Proposta de valor e ICP
Empresa fundada em 2003, **+2 mil clientes** no Brasil, LATAM e EUA [FATO-2 — materiais da própria Fortics via resultado de busca]. Plataforma omnichannel com IA. ICP: **mid-market e contact center**.

#### Planos e preços [FATO — https://www.fortics.com.br/tabela-de-precos-sz-chat/]

| Plano | Mensalidade | Mensagens inclusas | Valor por mensagem |
|---|---|---|---|
| FLEX + IA (até 50 mil msgs) | **R$ 838** | 1.000 | R$ 0,04 pré / R$ 0,048 pós |
| GROWTH + IA (acima de 50 mil) | **R$ 2.838** | 50.000 | R$ 0,012 pré / R$ 0,015 pós |
| PREMIUM + IA (acima de 430 mil) | sob consulta | 430.000 | melhor preço por mensagem |

**Atendentes e canais ilimitados em todos os planos** — modelo raro no Brasil [FATO]. Desconto progressivo por volume [FATO].

#### Canais [FATO]
**14 canais**, incluindo **webchat bidirecional**, WhatsApp, Facebook, Instagram, Microsoft Teams, Telegram, Google Chat, Signal, YouTube, Mercado Livre, **Reclame Aqui**, e-mail, SMS e voz.

**[INFERÊNCIA]** Ter **Reclame Aqui como canal nativo** é uma feature 100% brasileira que nenhum player internacional tem, e é um exemplo perfeito de "localização real". Idem "Signal" e "Google Chat" — cauda longa que só faz sentido em contact center.

#### Integração nacional relevante
A Fortics anuncia integração com **RD Station** [FATO — https://www.fortics.com.br/rd-station-integrado-ao-fortics-sz-chat/].

---

### 4.20 O ecossistema "Chatwoot-based" nacional

Esta é a categoria mais importante para o ChatSPX, porque é onde ele já compete — mesmo sem ter escolhido competir.

#### 4.20.1 ChatWoot BR (chatwoot.app.br) — o concorrente mais direto que encontrei

**Identidade declarada** [FATO — rodapé de https://chatwoot.app.br/precos]:
> *"ChatWoot BR é um serviço da Milesi Bastos Soluções em Informática LTDA (CNPJ 07.753.829/0001-04), construído sobre o projeto open-source Chatwoot (licença MIT). Não somos afiliad[os]..."* (texto truncado no HTML capturado)

**Posicionamento, transcrito** [FATO]:
> *"Ferramentas caras em dólar — Intercom, Zendesk, Zenvia — todas cobram em dólar ou com preços complexos. Setup pago. Taxa por mensagem. Para uma equipe de 10 pessoas, o custo passa de R$1.000/mês fácil. Existe um jeito melhor. E custa a partir de R$67/usuário/mês."*
> *"Feito para o Brasil. Não traduzido — construído."*
> *"A única caixa de entrada gerenciada com IA nativa — própria (open-source, sem lock-in) e de padrão oficial — por menos de R$500."*

**Planos** [FATO — https://chatwoot.app.br/precos]:

| Plano | Preço | Agentes | Inboxes | Números WhatsApp | IA |
|---|---|---|---|---|---|
| Empreendedor | **R$ 56/usuário/mês** | até ~8 | 3 | 1 (QR) | AI Tasks, sem "Eva" |
| Profissional | **R$ 414/mês** | até 10 | 15 | 5 inclusos | AI Tasks + Eva autônoma em 1 inbox |
| Empresarial | **R$ 664/mês** | até 20 | sem limite público | 10 inclusos | AI Tasks + Eva em até 3 inboxes |
| Custom | sob consulta | negociado | negociado | negociado | Eva negociada |

- **WhatsApp extra: R$ 57/número** em todos os planos [FATO].
- Profissional adiciona: Facebook e Instagram, CRM integrado, **Agent Bots**, integrações (**N8N**, API), onboarding guiado gratuito (1 hora), relatórios avançados.
- Empresarial adiciona: **instância dedicada**, Help Center, Campanhas, **domínio customizado**, propriedade e exportação de dados, onboarding white-glove (2+ horas).
- Comercial: **7 dias grátis**, **30 dias de garantia com devolução de 100%**, "pague 10 meses, ganhe 12" no anual, **Pix, cartão e boleto**, sem taxa de setup e sem fidelidade.
- **WhatsApp via QR Code incluído em todos os planos**, com API oficial (Meta Cloud) como opção. Argumento textual: **"R$0 por mensagem — sem cobrança por conversa, mensagem ou resolução; o custo não cresce com o volume."** [FATO]
- LGPD como argumento de venda: **"DPA incluso na contratação. Exportação de dados por API. Retenção configurável."** [FATO]

**Páginas de comparação publicadas** [FATO — rodapé]: vs Octadesk, vs Zenvia, vs Intercom, vs Chatwoot Cloud, vs RD Station Conversas, vs Huggy, vs Poli Digital, vs JivoChat, vs Take Blip, vs Movidesk, vs Globalbot, vs Umbler Talk, vs Letalk, vs NeoAssist.
**Verticais publicadas** [FATO]: clínicas e consultórios, contabilidade, imobiliárias, e-commerce.

**[INFERÊNCIA] Isto é o playbook completo que o ChatSPX poderia executar** — e alguém já está executando: mesma base (Chatwoot MIT), preço em BRL, WhatsApp sem taxa por mensagem, IA nomeada ("Eva"), verticalização, comparativos SEO contra todos os players, LGPD como feature.

#### 4.20.2 Outras operações whitelabel

| Operação | Modelo | Preços verificados |
|---|---|---|
| **CWMKT** (cwmkt.com.br) | SaaS whitelabel multicanal, canais: chat website, e-mail, WhatsApp, Facebook/Instagram, SMS, Telegram, Line, API; Typebot, OpenAI, webhooks, CRM, Kanban, N8N, Perfex CRM, RD Station, Shopify | Pessoal **R$ 399/mês** (15 conexões), Negócios **R$ 499** (25), Empresas **R$ 799** (50), Plus Grow **R$ 1.099** (75); empresas e usuários ilimitados [FATO] |
| **BotAtende** (botatende.com.br/whitelabel) | Licença de revenda whitelabel; "autonomia completa... marca própria" | **R$ 10.000,00/anual**, parcelável em 10x no cartão, à vista em boleto ou Pix [FATO] |
| **Conexão Azul** (portal.conexaoazul.com) | "Plano Pessoal Revenda Chatwoot Whitelabel" — 25 conexões, empresas/usuários ilimitados, Canal Chat Website, agendador, e-mail, WhatsApp, Facebook/Instagram, SMS, Telegram, Line, Canal API, **TypeBot integrado, N8N, Perfex CRM** | Página retornou **403** na coleta; features de resultado de busca [FATO-2]; preço **[NÃO VERIFICADO]** |
| **chatwoot.com.br** | Portal em português com página `/precos` que reproduz a lista de recursos do Chatwoot upstream traduzida (etiquetas, equipes, notas privadas, segmentos, **horário comercial**, registros de auditoria, relatórios CSAT, ações em massa, capacidade do agente, **Chat ao vivo no site**) | Lista de recursos [FATO]; valores **[NÃO VERIFICADO]** |
| **ChatLabel / WhatsLabel**, **XAMA**, **Central Zap** (curso), **Chat Inteligente**, **Chat2Desk Brasil** | Revenda/whitelabel e treinamento para revender Chatwoot como produto próprio | Valores **[NÃO VERIFICADO]** |

**[INFERÊNCIA]** O que essa categoria prova: (a) o Chatwoot é, no Brasil, uma **commodity de infraestrutura**, não um diferencial; (b) o diferencial está em **canal WhatsApp sem taxa por mensagem, marca, suporte em português, verticalização e IA**; (c) o mercado de revenda cobra R$ 399–R$ 1.099/mês por "conexões", o que é uma unidade de cobrança **completamente diferente** da do mercado formal (DAU/conversa/usuário).

---

## 5. TABELA COMPARATIVA GERAL

### 5.1 Preço, unidade de cobrança e entrada

| Player | Categoria | Menor plano pago | Maior plano público | Unidade cobrada | Taxa de setup | Trial |
|---|---|---|---|---|---|---|
| Leadster | A – captura | R$ 142/mês (anual) | R$ 154/mês (anual) | visitas do site | não declarada | 14 dias, sem cartão |
| Cliengo | A – captura | USD 45/mês | USD 259/mês | conversas (sessão 24h) | não declarada | 14 dias, sem cartão |
| JivoChat | B – live chat | R$ 63/operador | R$ 238/operador | operador + add-ons | não declarada | 14 dias |
| Octadesk | B – omnichannel | R$ 2.499/mês | R$ 4.399/mês (Nexus sob consulta) | DAU | onboarding à parte [FATO-2] | não declarado |
| Huggy | B – omnichannel | R$ 579/mês | R$ 989+/mês | usuário conectado | onboarding opcional | não declarado |
| Digisac | B – omnichannel | não público | não público | não público | não público | demonstração |
| Poli Digital | B – omnichannel | R$ 369,90/mês | R$ 4.999,90/mês | usuários + créditos | **a partir de R$ 1.197,90** | teste grátis |
| Nexloo | B – omnichannel | R$ 149/mês | R$ 599/mês | conversas | não declarada | 7 dias, sem cartão |
| ChatGuru | B – WhatsApp | não público | não público | não público | R$ 500 [FATO-2] | não informado |
| Umbler Talk | B – omnichannel | R$ 69/mês [FATO-2] | R$ 109/atendente [FATO-2] | atendente | não declarada | não verificado |
| Fortics SZ.chat | B – contact center | R$ 838/mês | R$ 2.838/mês | mensagens | não declarada | não verificado |
| Movidesk | B – helpdesk | R$ 700/mês | sob consulta | usuário + Interactionz | não declarada | teste grátis |
| RD Conversas | C – CRM+chat | R$ 989/mês | R$ 2.699/mês | clientes únicos/mês | R$ 1.999 / R$ 3.799 (opcionais) | não declarado |
| Kommo | C – CRM | USD 15/usuário | USD 45/usuário | usuário + leads ativos | não declarada | 14 dias |
| Take Blip | D – infra | não público | não público | DAU + seats | Professional Services | não |
| Botmaker | D – infra | R$ 600/mês | R$ 2.250/mês | conversas | **R$ 500** (conta WABA) | conta grátis |
| Zenvia | D – infra/BSP | USD 130/mês | USD 845/mês | usuário + Interactionz + pacote de canal | USD 137–842 | Starter grátis |
| Weni (VTEX) | D – infra | não público | não público | não público | não público | não verificado |
| Chatvolt | E/B – IA | não verificado | não verificado | não verificado | não verificado | plano free [FATO-2] |
| ChatWoot BR | E – Chatwoot SaaS | R$ 56/usuário | R$ 664/mês | usuário/plano fixo | **sem taxa** | 7 dias + garantia 30 dias |
| CWMKT | E – whitelabel | R$ 399/mês | R$ 1.099/mês | conexões | não declarada | não verificado |
| BotAtende | E – whitelabel | R$ 10.000/ano | — | licença anual | — | não verificado |

### 5.2 Widget de site — existe? como é?

| Player | Webchat? | Snippet público? | API JS pública? | Customização documentada | Whitelabel / remover marca |
|---|---|---|---|---|---|
| Leadster | **Sim** (+ Live Chat humano no Full) | **Sim** (via plugin WP) | `window.neurolead.open()` | fluxo, cores, avatar (painel) | não verificado |
| Cliengo | **Sim** (núcleo) | **Sim** | config JSON pública | cor, ícone, estilo BAR, título, placeholder, delay, avatar, horário | **Sim** — `whiteLabelId` + `poweredBy` customizável |
| JivoChat | **Sim** (núcleo) | **Sim** (`code.jivosite.com/widget/{id}`) | Chat API no plano VIP | convites proativos, botões pré-chat, formulário offline | não verificado |
| Huggy | **Sim** ("Huggy Chat") | **Sim** | **~26 métodos + 9 tópicos de evento** | canais no widget, saudação, base de conhecimento, gatilhos | não verificado |
| Octadesk | **Sim** ("Chat no Site") | gerado no painel | `octadesk.chat.login()` + evento `on0ctaChatReady` | cor, posição, título, equipe, msg online/offline, auth | não verificado |
| Take Blip | **Sim** (Blip Chat) | **Sim** (npm/unpkg) | builder com 9 métodos + 4 eventos | cor, ícone, `withCustomStyle`, `withTarget` (inline) | não verificado |
| Zenvia | **Sim** (Zenvia Chat) | script embed público | postMessage/iframe | width, height, margens, título, placeholder, cor, modo inline, opt-in | não verificado |
| Botmaker | **Sim** (Webchat Designer) | no painel | não verificado | **nome, logo, cores, tamanho, fonte, objetos, temas, menu persistente** | não verificado |
| Kommo | **Sim** ("chat button") | no painel + plugin WP | `crmPlugin()` + 5 callbacks + `setMeta()` | tema completo, locale, modo widget/frame, lado, animação | não verificado |
| RD Conversas | **Sim** (Widget Chat) | no painel | não verificado | "atualizações de personalização" (artigo dedicado) | não verificado |
| Digisac | **Sim** (Webchat) | não verificado | não verificado | "cores, mensagens e identidade visual" | não verificado |
| Poli Digital | **Sim** ("Canal de Webchat/Site") | não verificado | não verificado | não verificado | não verificado |
| Movidesk | **Sim** (WebChat → vira ticket) | não verificado | não verificado | não verificado | não verificado |
| Fortics SZ.chat | **Sim** (webchat bidirecional) | não verificado | não verificado | não verificado | não verificado |
| Nexloo | **Não encontrado** | — | — | — | — |
| ChatGuru | **Não encontrado** | — | — | — | — |
| Chatvolt | declarado ("sites") | não verificado | não verificado | não verificado | não verificado |
| Weni | via canais (RocketChat etc.) | não verificado | não verificado | não verificado | open-source |
| ChatWoot BR / CWMKT / Conexão Azul | **Sim** (herdado do Chatwoot) | Chatwoot upstream | Chatwoot SDK (`$chatwoot`) | Chatwoot upstream | **Sim** (é o modelo de negócio) |

### 5.3 Peso do canal: WhatsApp vs chat de site

| Player | Peso WhatsApp | Peso chat de site | Evidência |
|---|---|---|---|
| ChatGuru | **100%** | 0% | canais declarados: só WhatsApp [FATO] |
| Nexloo | ~90% | 0% | planos sem webchat [FATO] |
| Poli Digital | ~90% | 5% | "um número, vários atendentes"; webchat é linha de tabela [FATO] |
| RD Conversas | ~90% | 10% | franquia conta cliente que iniciou **pelo WhatsApp** [FATO] |
| Digisac | ~80% | 20% | landing dedicada de webchat, mas produto vendido como WhatsApp [FATO] |
| Take Blip | ~80% | 20% | BSP; mas SDK de webchat maduro e público [FATO] |
| Zenvia | ~75% | 25% | pacote de canal SMS/WhatsApp; webchat próprio em uso no site [FATO] |
| Huggy | ~70% | 30% | "Huggy Chat" é produto nomeado com SDK [FATO] |
| Octadesk | ~65% | 35% | herança helpdesk (e-mail/chat/ticket) [FATO] |
| Botmaker | ~60% | 40% | Webchat Designer é função destacada [FATO] |
| Kommo | ~60% | 40% | chat button em todos os planos [FATO] |
| Movidesk | ~40% | 60% | webchat vira ticket; núcleo é helpdesk [FATO] |
| Cliengo | ~30% | 70% | WhatsApp API só no Business [FATO] |
| Leadster | ~25% | 75% | núcleo é site; WhatsApp é destino do redirect [FATO] |
| JivoChat | ~15% | 85% | **WhatsApp é add-on de R$ 175/mês** [FATO] |

**[INFERÊNCIA]** Os pesos acima são estimativa minha a partir do que cada empresa destaca em página oficial de produto/preço — não são dados de receita.

---

## 6. ANATOMIA TÉCNICA DOS WIDGETS

Compilado das seis implementações que consegui inspecionar em código ou documentação oficial completa.

### 6.1 Padrão de carregamento

| Player | Padrão | Observação |
|---|---|---|
| Leadster | script `defer` + global `neuroleadId` antes do append | bundle único de **456 KB** |
| Huggy | IIFE clássica `(function(i,s,o,g,r,a,m){...})` com `async=1` | injeta antes do primeiro `<script>` do documento |
| Cliengo | **JS de configuração por cliente** (`{companyId}/{websiteId}.js`) que injeta o bundle real | config em texto claro, cacheável por CDN |
| JivoChat | loader que se auto-localiza via `document.currentScript` / `script[jv-id]` | **18 KB** de loader |
| Blip Chat | `<script src="unpkg.com/blip-chat-widget@1.11.*">` + builder no `window.onload` | recomenda **hospedar localmente**, não confiar no CDN |
| Zenvia | script embed + CSS externo + `<iframe>` | guard anti-duplicação com `throw` |
| Kommo | `window.crmPluginConfig` **antes** do código do botão | modo `widget` ou `frame` |
| Octadesk | script gerado no painel + `addEventListener('on0ctaChatReady')` | auth por evento, não por config |

**[INFERÊNCIA]** Dois padrões de identidade coexistem: **config-antes-do-script** (Huggy `$_Huggy`/`huggyData`, Kommo `crmPluginConfig`, Cliengo config file) e **evento-depois-do-script** (Octadesk `on0ctaChatReady`, Blip `withEventHandler`). O primeiro é mais simples para quem instala via GTM; o segundo é mais robusto para SPA.

### 6.2 Identificação segura do visitante (anti-spoofing)

| Player | Mecanismo | Algoritmo |
|---|---|---|
| Huggy | `userIdentifier` + `userHash` (JWT) | **HMAC-SHA256** com secret do painel; exemplo oficial em PHP |
| Blip Chat | `withAuth({authType, userIdentity, userPassword})`; guest mantém identidade **30 dias** | tipos DEV/guest documentados em wiki |
| Octadesk | `octadesk.chat.login({name, email, customFields})` | **sem hash** — confia no cliente |
| Kommo | `onlinechat.user_id` para vincular sessões entre dispositivos | sem hash documentado |
| Cliengo | `token` JWT embutido no arquivo de config público | público, portanto não é segredo |
| Chatwoot (upstream, base do ChatSPX) | `identifier_hash` HMAC-SHA256 | mesma família da Huggy |

**[INFERÊNCIA]** A Huggy e o Chatwoot implementam o mesmo padrão correto. Octadesk e Kommo, pelo que está documentado publicamente, aceitam identidade não assinada — o que permite um visitante se passar por outro. Isso é um argumento técnico defensável a favor do ChatSPX.

### 6.3 Superfície de API JS — ranking por riqueza

1. **Huggy** — 26 métodos + 9 tópicos de evento + login/logout + `setData` com `custom_fields`.
2. **Kommo** — 4 ações + 5 callbacks + `setMeta()` + tema completo + locale com date-fns.
3. **Blip Chat** — 9 métodos de builder + 4 eventos + `sendMessage` + `withTarget`.
4. **Cliengo** — configuração declarativa muito rica, API imperativa pobre.
5. **Octadesk** — 1 método público documentado (`login`) + 1 evento.
6. **Leadster** — `open()` documentado; resto é painel.

### 6.4 Features de widget que aparecem em mais de um player

| Feature | Quem tem (verificado) |
|---|---|
| Convite proativo / gatilho por tempo | JivoChat ("convites proativos"), Huggy (`showTrigger`/`startTrigger`), Cliengo (`chatSaluteTimeInSeconds`), Zenvia (`znv-opt-in`) |
| Botões de resposta rápida | Cliengo (`[[A, B, C]]` na mensagem), Leadster (fluxo), Botmaker (menu persistente) |
| Modo inline / embutido na página | Blip (`withTarget`), Kommo (`mode: 'frame'`), Zenvia (`room` / `znv-is-inline`) |
| Menu de canais dentro do widget | Huggy (`openButtons()` → Telegram, WhatsApp, E-mail, Messenger) |
| Base de conhecimento no widget | Huggy (`openKnowledgeBase()`) |
| Agendar ligação (callback) | Huggy (`openPhone()`), JivoChat (recurso "Callback") |
| Horário comercial no widget | Cliengo (`businessHoursConfiguration`), Leadster Live Chat (dias/horários), Huggy (plano Intermediário+) |
| Só exibir se houver atendente online | Leadster Live Chat [FATO] |
| Continuidade de conversa entre sessões | Zenvia (`continuousConversation` + cookie `_zid`), Blip (guest 30 dias) |
| Formulário offline | JivoChat |
| Monitoramento de visitantes em tempo real | JivoChat (plano Básico+) |
| Videochamada no chat | JivoChat (add-on R$ 122/operador) |
| Whitelabel / powered-by customizável | Cliengo (`whiteLabelId`, `customPoweredByUtms`) |
| Redirect para WhatsApp a partir do widget | Leadster (free), Huggy (`openWhatsapp`), Cliengo (`loadWhatsAppWidget`) |

---

## 7. PRECIFICAÇÃO PRATICADA NO BRASIL

### 7.1 As faixas reais (todos os valores [FATO], salvo indicação)

**Faixa 0 — grátis / isca (R$ 0)**
Leadster Free (1.000 visitas, 15 leads), JivoChat Free (**5 operadores**), Huggy Starter (1 usuário), Zenvia Starter (1 usuário, 100 interações), Botmaker (conta grátis + 300 conversas iniciais).
**[INFERÊNCIA]** O plano gratuito no Brasil não é gerador de receita — é gerador de instalação e, no caso do Cliengo, de backlink viral ("Usamos Cliengo" com UTM).

**Faixa 1 — micro/PME self-service (R$ 56 – R$ 350/mês)**
ChatWoot BR Empreendedor R$ 56/usuário · JivoChat Básico R$ 63/operador · Umbler Talk R$ 69 (2 atendentes) [FATO-2] · Nexloo START R$ 149 · Nexloo PLANTONISTA R$ 349 · Leadster Starter R$ 142 · Leadster Pro R$ 154.

**Faixa 2 — PME estruturada (R$ 350 – R$ 700/mês)**
Poli Entrada R$ 369,90 · CWMKT R$ 399–499 · ChatWoot BR Profissional R$ 414 · Huggy Intermediário R$ 579 · Nexloo PRO+ R$ 599 · Botmaker Standard R$ 600 · ChatWoot BR Empresarial R$ 664 · Movidesk a partir de R$ 700.

**Vale (R$ 700 – R$ 830/mês)** — praticamente vazio.

**Faixa 3 — mid-market (R$ 830 – R$ 1.500/mês)**
Fortics FLEX R$ 838 · Poli Inicial R$ 849,90 · Huggy Custom R$ 989 · RD Conversas Basic R$ 989 · Botmaker Scale R$ 1.100 · CWMKT Plus Grow R$ 1.099 · Poli Expansão R$ 1.399,90.

**Faixa 4 — mid-market alto / enterprise-lite (R$ 2.000 – R$ 5.000/mês)**
Botmaker Pro R$ 2.250 · Octadesk One R$ 2.499 · RD Conversas Pro R$ 2.699 · Fortics GROWTH R$ 2.838 · Octadesk Flow R$ 4.399 · Poli Ilimitado R$ 4.999,90.

**Faixa 5 — enterprise (sob consulta)**
Take Blip, Zenvia Enterprise, Octadesk Nexus, RD Advanced, Weni, Fortics PREMIUM, Kommo Enterprise.

### 7.2 Custos que não aparecem na mensalidade

| Custo | Quem cobra | Valor |
|---|---|---|
| Taxa de implantação | Poli Digital | a partir de **R$ 1.197,90** |
| Ativação de WhatsApp | RD Conversas | **R$ 1.999** |
| Integração de chatbot com CRM | RD Conversas | **R$ 3.799** |
| Criação de conta WABA | Botmaker | **R$ 500** (uma vez) |
| Setup de plataforma | Zenvia | **USD 137 – USD 842** |
| Carteira de créditos WhatsApp | RD Conversas | mínimo **R$ 300**, validade 12 meses |
| Pacote de créditos | Poli Digital | R$ 18 (100) a R$ 120 (1.000) |
| Canal WhatsApp adicional | Poli Digital | **R$ 269,90/mês** |
| Canal WhatsApp adicional | Nexloo | **R$ 49,90/mês** |
| Número WhatsApp adicional | ChatWoot BR | **R$ 57/mês** |
| WhatsApp como add-on | JivoChat | **R$ 175/mês** |
| Hora técnica | Nexloo | **R$ 150** |
| Conversa/DAU excedente | Blip R$ 1,40 / R$ 1,25 · Botmaker R$ 0,46 / R$ 0,40 / R$ 0,31 · Nexloo R$ 89,90 por 1.000 · Zenvia USD 0,19–1,00 |
| Atendente adicional | Blip R$ 150 / R$ 100 · Octadesk R$ 130/120/100 · Huggy R$ 69,90/119,90/189,90 · Poli R$ 129,90/119,90/109,90 · Zenvia USD 22–53 |

### 7.3 O que essas faixas permitem entregar

**[INFERÊNCIA]** Com ticket de R$ 149–R$ 600/mês (a faixa onde vive a maioria absoluta das PMEs brasileiras), a matemática de suporte humano não fecha para atendimento consultivo. Isso explica três padrões observáveis no mercado:
1. **Onboarding cobrado à parte** (Poli, RD, Zenvia, Botmaker) — o setup vira centro de lucro que banca a implantação.
2. **"Hora técnica" avulsa** (Nexloo, R$ 150) — desacopla suporte de plano.
3. **Contrato de 12 meses** (Poli [FATO-2]) — amortiza o CAC.
E explica também por que **ChatWoot BR anuncia "sem taxa de setup e sem fidelidade" como diferencial** [FATO]: é ataque direto a esses três padrões.

---

## 8. WHATSAPP VS CHAT DE SITE — O EIXO QUE DEFINE O MERCADO

### 8.1 O contexto de mercado (números)

[FATO-2 — Panorama/Super Panorama Mobile Time/Opinion Box, via https://www.mobiletime.com.br/noticias/09/06/2026/whatsapp-super-panorama/ — pesquisa de instituto, mas acessada por notícia, não pelo relatório original]:
- WhatsApp instalado em **98,3%** dos smartphones brasileiros.
- Está na **tela inicial de 64,8%** dos aparelhos (era 53% em 2025).
- **97%** dos usuários abrem o app todos os dias ou quase.
- **79,5%** conversaram com marcas/empresas pelo app ao menos uma vez nos últimos 12 meses.

**[INFERÊNCIA]** Contra esse pano de fundo, um widget de site no Brasil não compete com o WhatsApp — ou ele **alimenta** o WhatsApp, ou ele precisa justificar por que o visitante deveria conversar num canal que não é o dele.

### 8.2 As quatro estratégias observadas de "chat do site que vira WhatsApp"

**Estratégia 1 — Redirect puro (click-to-WhatsApp)**
O widget é um botão que abre `wa.me/...` com mensagem pré-preenchida. Verificado: Leadster tem `https://wa.me/` no bundle e "redirecionamento para WhatsApp" já no plano gratuito [FATO]; Huggy expõe `openWhatsapp()` e `channelGreeting` (texto padrão "Oi") [FATO]; a própria Huggy publica ferramentas gratuitas de "Botão Flutuante do WhatsApp" e "Gerador de Link do WhatsApp" [FATO]; Nexloo usa literalmente o plugin `click-to-chat-for-whatsapp` no próprio site [FATO].
**Perda:** o contexto da navegação (página, UTM, produto visto) se perde se não for embutido no texto do link.

**Estratégia 2 — Captura antes do redirect (qualifica, depois manda)**
O bot do site coleta nome/telefone/interesse, **grava o lead**, e só então redireciona. É o modelo da Leadster (fluxo de qualificação → redirect + **roleta de WhatsApp** distribuindo entre vendedores no plano Pro) [FATO].
**Ganho:** o lead existe no CRM mesmo se a conversa no WhatsApp nunca acontecer. **[INFERÊNCIA]** Este é o padrão que o mercado brasileiro de marketing considera correto hoje.

**Estratégia 3 — Mesmo inbox, canais distintos (continuidade por contato)**
O webchat e o WhatsApp caem na mesma caixa de entrada e no mesmo contato. É o que Digisac descreve explicitamente ("a conversa entra instantaneamente no painel da Digisac, junto com WhatsApp, Instagram e outros canais... sem precisar trocar de plataforma ou aba") [FATO], e o que Octadesk descreve no Octa Conversas [FATO].
**Limite verificado:** ninguém documenta **fusão automática de identidade** entre a sessão anônima do site e o número de WhatsApp. **[INFERÊNCIA]** Na prática, o merge depende do visitante informar o telefone no webchat.

**Estratégia 4 — Continuidade técnica de sessão no próprio widget**
Zenvia com `continuousConversation` + cookie `_zid` [FATO]; Blip com identidade de guest persistente por **30 dias** [FATO]. Isso resolve continuidade **dentro do canal site**, não entre canais.

**[INFERÊNCIA] O buraco do mercado:** ninguém que eu inspecionei documenta publicamente uma ponte real "sessão anônima do site → conversa de WhatsApp identificada → mesmo histórico", com o handoff carregando o transcript. Isso é uma oportunidade de produto concreta.

### 8.3 O fator regulatório/econômico: o preço da mensagem

[FATO-2 — cobertura de imprensa e materiais de fornecedores; **não confirmei na documentação oficial da Meta**]:
- O WhatsApp Business API migrou de cobrança **por conversa de 24h** para **por mensagem** (per-message pricing), com o template cobrado por categoria (marketing, utilidade, autenticação) e país.
- Há relatos de retomada de cobrança de **mensagens de serviço** dentro da janela de 24h a partir de **1º de outubro de 2026**, com valor estimado em torno de **R$ 0,035** por mensagem no Brasil.
- Mensagens originadas de anúncios **Click-to-WhatsApp** têm isenção — o que a RD Station confirma na própria página de planos [FATO].

**[INFERÊNCIA] Consequência direta:** se o WhatsApp passa a cobrar por resposta, o **canal de site fica relativamente mais barato**. A Mobile Time publicou justamente uma matéria com a tese de que a cobrança por resposta "vai fortalecer apps próprios" [FATO — título da matéria em https://www.mobiletime.com.br/noticias/31/07/2026/whatsapp-apps-proprios/]. Um webchat próprio tem custo marginal por mensagem **zero**. Este é, hoje, o melhor argumento econômico para investir no widget web — e ele não existia dois anos atrás.

---

## 9. PRÁTICAS LOCAIS: LGPD, CPF/CNPJ, TELEFONE, HORÁRIO, TOM DE VOZ

### 9.1 LGPD e consentimento no chat

O consenso das fontes jurídicas/técnicas brasileiras [FATO-2 — https://www.ecommercebrasil.com.br/artigos/lgpd-dados-pessoais-chatbots, https://www.contabeis.com.br/artigos/69603/lgpd-para-chatbots-e-ia-como-garantir-a-conformidade/, e políticas publicadas por operadores como Globalbot e Pacto Global]:

1. Dados coletados por chatbot ficam **imediatamente sujeitos à LGPD**.
2. O bot deve **pedir permissão antes de coletar**, com mensagem inicial explicando **quais dados** e **para qual finalidade**.
3. O consentimento precisa ser **claro, transparente e informado**, com **opção de revogação a qualquer momento**.
4. **Minimização**: coletar só o essencial; revisar se dá para coletar menos.
5. Medidas de segurança: criptografia, controle de acesso, monitoramento e auditoria.
6. Informar que o titular pode **solicitar exclusão** a qualquer momento.

**O que existe em produto, verificado:**
- **Zenvia**: bloco `znv-opt-in` no widget, com `znv-opt-in-text`, `znv-opt-in-link` e `znv-opt-in-close`, removido do DOM ao abrir o chat [FATO — bundle].
- **Leadster**: URL `https://leadster.com.br/privacidade` e `https://www.getleadster.com/privacy/` embutidas no bundle do widget [FATO].
- **ChatWoot BR**: vende LGPD como feature — **"DPA incluso na contratação. Exportação de dados por API. Retenção configurável."** [FATO]
- **Chatwoot upstream** (base do ChatSPX): "Registros de auditoria — rastreie e acompanhe as atividades da conta" está na lista de recursos [FATO — https://chatwoot.com.br/precos].

**[INFERÊNCIA]** A implementação real de consentimento no widget brasileiro é rasa: checkbox/link de política antes de abrir, e ponto. Nenhum player que inspecionei documenta granularidade de finalidade, prova de consentimento com timestamp, ou fluxo de revogação dentro do chat. É um gap de conformidade generalizado — e, portanto, um diferencial disponível.

### 9.2 CPF, CNPJ, CEP, telefone — validação como requisito de produto

| Player | Evidência |
|---|---|
| Leadster | Mensagens de erro nativas: *"Desculpe, não entendi o seu CPF."*, *"...seu CNPJ."*, *"...seu CPF/CNPJ."*, *"...seu CEP."*, *"...seu telefone."*, *"...seu aniversário. DD/MM/AAAA"*, *"Por favor, informe um endereço de e-mail corporativo válido."*, *"Desculpe, não entendi sua resposta. Talvez esteja faltando um acento."* [FATO — bundle] |
| Huggy | `custom_fields` com `cpf_of_the_contact_customer`, `cnpj_of_the_company_customer`, `date_of_birth_customer`, `corporate_e_mail_customer`, `comercial_phone_customer`, `activation_time_of_the_contact_customer` [FATO — doc oficial] |
| Huggy | `defaultCountry: '+55'` como padrão do snippet e `setPhone(DDI, telefone)` com DDI separado [FATO] |
| Nexloo | Formulário de trial exige **CPF/CNPJ** e **e-mail corporativo** [FATO] |
| Cliengo | Config tem `phone` com DDI e módulos de localidade; a Leadster carrega `state_cities.json` e `flags.png` do próprio CDN [FATO] |
| Leadster | Módulos públicos no CDN incluem `ibge_localidades.js` e `postmon.js` — **integração com base do IBGE e com serviço de CEP** [FATO — listagem do bucket https://cdn.leadster.com.br/] |

**[INFERÊNCIA]** A existência de `ibge_localidades.js` e `postmon.js` como módulos de fluxo na Leadster mostra o nível de localização que o mercado brasileiro de captura já atingiu: **o fluxo do chatbot consulta CEP e lista de municípios do IBGE dentro da conversa**. Isso não é tradução — é engenharia para o Brasil.

### 9.3 Horário comercial, feriados e fora de expediente

| Player | Recurso | Fonte |
|---|---|---|
| Huggy | **"Horário de funcionamento"** (avisa o cliente fora do horário) — plano Intermediário+ | [FATO] tabela de preços |
| Huggy | **"Controle de feriados"** — "configure um horário de atendimento especial durante os feriados ou ocasiões específicas" | [FATO] tabela de preços |
| Cliengo | `businessHoursConfiguration` na config pública do widget | [FATO] arquivo baixado |
| Leadster Live Chat | dias e horários configuráveis; exibir só quando há operador online | [FATO] help oficial |
| Octadesk | mensagens **online/offline** configuráveis na etapa 2 do widget | [FATO] help oficial |
| JivoChat | **formulários offline** | [FATO] página de planos |
| Chatwoot upstream | "Horário comercial — informe aos clientes que você não está disponível" | [FATO] lista de recursos |

**[INFERÊNCIA]** "Controle de feriados" como **linha de tabela de preço** (Huggy) é sinal claro: no Brasil, feriado municipal/estadual quebra a operação de atendimento e o mercado paga por isso. O Chatwoot upstream tem horário comercial, mas **não tem calendário de feriados brasileiro** — é uma lacuna específica e barata de fechar.

### 9.4 Tom de voz, português coloquial e emojis

Evidências de linguagem em produto real:
- Digisac usa no próprio widget de demonstração: *"Perfeito! O Webchat permite centralizar tudo isso. Gostaria de agendar uma demonstração?"* / *"Sim, por favor!"* [FATO — HTML da página de webchat].
- Nexloo abre o widget do site com *"Heey, vamos conversar?"* [FATO].
- Poli usa *"🔴 ESTAMOS AO VIVO!"* e *"Acessível, simples e pronto pra usar!"* [FATO].
- Cliengo usa *"está escribiendo..."* como indicador de digitação configurável [FATO].
- Zenvia suporta **markdown** dentro das mensagens do widget [FATO — bundle].
- ChatWoot BR escreve *"Quem tá atendendo esse cliente?"* — coloquial com supressão do "es" [FATO].

**[INFERÊNCIA]** O registro dominante é **informal-profissional**: segunda pessoa ("você"), contrações coloquiais, emoji com parcimônia (👥, 🔴, 🚀), exclamação frequente. Widget que fala como manual de software soa importado. O indicador de digitação e as reticências fazem parte do "tom" tanto quanto o texto.

### 9.5 Telefone obrigatório

**[INFERÊNCIA a partir dos fatos]** O telefone é, na prática, o campo-chave do lead brasileiro — não o e-mail. Evidências: Huggy tem `setPhone(DDI, telefone)` como método de primeira classe e `defaultCountry: '+55'` no snippet padrão; a Leadster valida telefone e tem redirect para `wa.me`; a Nexloo pede "WhatsApp com DDD" **antes** do e-mail no próprio formulário de trial; o Blip aceita `phoneNumber` em `withAccount`. Um widget brasileiro que trata telefone como campo opcional secundário está desalinhado com a prática do mercado.

---

## 10. REVIEWS E RECLAMAÇÕES PÚBLICAS

**Aviso metodológico:** não consegui abrir diretamente as páginas do Reclame Aqui, Capterra BR e B2B Stack (bloqueio/anti-bot). Os números abaixo vêm de **agregadores e blogs**, alguns de concorrentes. Todos são **[FATO-2]** e alguns conflitam entre si. As **URLs canônicas** ficam registradas para verificação manual futura.

### 10.1 Notas citadas

| Player | Nota citada | Fonte da citação | URL canônica para conferir |
|---|---|---|---|
| Octadesk | **9,1/10** no Reclame Aqui com 32 reclamações (snapshot 30/04/2026); outra citação diz **8,5/10** com 23 reclamações e **93,3% resolvidas** | botaihub | https://www.reclameaqui.com.br/empresa/octadesk/ |
| Take Blip | **8,2/10**, 97,6% de resolução | botaihub | https://www.capterra.com/p/200367/Blip/ |
| Huggy | **Sem selo formal** no Reclame Aqui (empresa não pediu verificação); reclamações registradas sem nota; tempo médio de resposta **2 dias e 13 horas** | botaihub | https://www.reclameaqui.com.br/empresa/huggy/lista-reclamacoes/ |
| JivoChat | **3,8/5** na B2B Stack (melhor nota em custo-benefício) | B2B Stack via busca | https://www.b2bstack.com.br/product/jivochat |
| Movidesk | **CSAT médio de 95%** (dado autodeclarado) | material Movidesk | https://www.capterra.com/p/192413/Movidesk/ |
| Zenvia | citada como **RA1000** | botaihub | https://www.reclameaqui.com.br/ |

### 10.2 Temas recorrentes de reclamação (títulos públicos)

**Octadesk** — títulos de reclamações reais indexadas [FATO — os títulos existem como URLs públicas no Reclame Aqui]:
- *"Plataforma muito mal desenvolvida e suporte tenebroso"*
- *"Dificuldade de Cancelamento e Reembolso"*
- *"MUITO CUIDADO AO CONTRATAR A OCTADESK - PÉSSIMA EXPERIÊNCIA"*
- *"Insatisfação com o atendimento e as soluções oferecidas pela plataforma"*
- *"As 10 coisas que descobri em 1 mês de uso."*
Temas citados por agregador [FATO-2]: falta de notificação de novas atribuições, conversas furando o tratamento do bot, fluxos de automação aplicados ao produto errado, tempo médio de resposta de **14 dias e 10 horas**, dificuldade de cancelamento.

**Huggy** — títulos reais indexados [FATO]:
- *"Huggy parou nossa operação."*
- *"Oscilação da plataforma, todos os dias!"*
- *"Cancelamento da plataforma"*
- *"Descaso com os seus clientes!!"*
- *"Problemas com o serviço e falta de resposta da empresa"*
Temas: instabilidade, dificuldade de cancelamento, número do usuário vinculado à empresa.

### 10.3 O que isso ensina

**[INFERÊNCIA]** Os três eixos de insatisfação que se repetem no mercado brasileiro são, em ordem: **(1) estabilidade da plataforma** ("parou nossa operação", "oscilação todos os dias"), **(2) atrito de cancelamento** (aparece em Octadesk e Huggy), **(3) suporte pós-venda lento**. Nenhum dos três é sobre falta de feature. Isso é coerente com o fato de o ChatWoot BR ter escolhido anunciar exatamente **"sem multas de cancelamento, sem fidelidade, 30 dias de garantia"** — está vendendo contra a dor documentada dos concorrentes, não contra a funcionalidade deles [FATO — comparação entre https://chatwoot.app.br/precos e https://www.huggy.io/pt-br/pricing, que também anuncia "sem multas de cancelamento, sem contrato de fidelidade"].

---

## 11. MAPA DE POSICIONAMENTO E ONDE O CHATSPX SE ENCAIXA

### 11.1 Mapa em dois eixos

Eixo X: **quem compra** (Marketing → Vendas → Operação/Suporte → TI).
Eixo Y: **onde vive a conversa** (Site → Multicanal → WhatsApp puro).

```
                        SITE
                          ▲
        JivoChat ●        │        ● Cliengo
                          │
             Leadster ●   │
                          │   ● Botmaker (Webchat Designer)
   ─────────────────────  │  ─────────────────────────────
        Movidesk ●        │        ● Kommo
                          │
      Octadesk ●     MULTICANAL     ● Zenvia    ● Take Blip
                          │
        Huggy ●           │        ● Fortics SZ.chat
                          │
       Digisac ●          │        ● RD Station Conversas
                          │
         Poli ●           │        ● Weni/VTEX
                          │
      Nexloo ●            │        ● ChatGuru
                          ▼
                    WHATSAPP PURO

  Marketing ◄──────────────────────────────► TI / Enterprise
```

**[INFERÊNCIA]** Duas observações sobre esse mapa:
1. O **quadrante superior-esquerdo** (site + marketing) está **rarefeito**: só Leadster, Cliengo e JivoChat. É o quadrante com maior margem e menor concorrência local — e é exatamente o quadrante que exige um widget bom.
2. O **quadrante inferior** (WhatsApp puro) está **saturado** e em guerra de preço: Nexloo a R$ 149, Umbler a R$ 69, dezenas de whitelabels a R$ 399.

### 11.2 Onde o ChatSPX está hoje

**[INFERÊNCIA, baseada no que é público e na natureza do produto]**
- **Categoria:** E (Chatwoot-based) executando função B (atendimento omnichannel).
- **Comprador atual:** operação/suporte.
- **Canal dominante:** WhatsApp.
- **Widget web:** herdado do Chatwoot upstream — funcional, com `identifier_hash` HMAC-SHA256 correto, SDK `$chatwoot`, horário comercial, campanhas e pré-chat form.
- **Concorrente mais direto identificado:** **ChatWoot BR** (mesma base, mesmo país, mesma proposta, posicionamento mais afiado e preço público).

### 11.3 Onde poderia se encaixar

**[INFERÊNCIA]** Três posições possíveis, em ordem de esforço:

**Posição A — "omnichannel BR com preço honesto" (onde já está).**
Concorrentes: ChatWoot BR, Digisac, Poli, Nexloo, Huggy. Guerra de preço, diferenciação difícil, widget não vende.

**Posição B — "atendimento + captura no site" (o híbrido).**
Manter a base omnichannel e **adicionar o que Leadster/Cliengo fazem no site**: fluxo proativo, qualificação, validadores BR, roleta de WhatsApp, tracking de mídia. O comprador passa a ter **duas portas** (marketing e operação). Concorrência no quadrante superior-esquerdo é rala.

**Posição C — "infra de canal com widget embutível" (SDK-first).**
Widget como componente que o cliente embute no produto dele (`withTarget` / `mode:'frame'`), com API rica. Comprador é TI. Mercado menor, mas com lock-in técnico alto.

**Recomendação [INFERÊNCIA]:** **Posição B.** É a única que usa o widget web como ativo de receita em vez de item de checklist, e é onde o mercado brasileiro tem menos oferta.

---

## 12. IMPLICAÇÕES PARA O CHATSPX

> Apenas recomendações. Nenhum código, nenhuma implementação.
> A pergunta que a task pede para responder: **o que um cliente brasileiro considera obrigatório num chat de site hoje?**

### 12.1 A tabela do obrigatório

Classifiquei cada item por quantos players verificados o têm. **"Obrigatório"** = presente em 4+ dos players inspecionados, ou explicitamente vendido como diferencial por 2+.

| # | Requisito | Status no mercado | Evidência |
|---|---|---|---|
| 1 | **Snippet de uma linha, colável antes de `</body>`, funcionando via Google Tag Manager** | Obrigatório | Todos os 8 com snippet público; Leadster documenta GTM explicitamente |
| 2 | **Plugin/tutorial para WordPress, Wix, Nuvemshop, Loja Integrada** | Obrigatório | Leadster (WP oficial), Cliengo (WP oficial + Jimdo + WPML), Kommo (WP oficial), JivoChat (Loja Integrada, Nuvemshop), Huggy (Wix, WP) |
| 3 | **Cor + posição (esquerda/direita) + avatar + título configuráveis sem código** | Obrigatório | Octadesk, Cliengo, Botmaker, Kommo, Digisac, Blip |
| 4 | **Mensagem proativa com delay configurável** | Obrigatório | Cliengo (`chatSaluteTimeInSeconds`), JivoChat ("convites proativos"), Huggy (`startTrigger`), Zenvia (opt-in) |
| 5 | **Botões de resposta rápida no primeiro turno** | Obrigatório | Cliengo (`[[A, B]]`), Leadster (fluxo), Botmaker (menu persistente) |
| 6 | **Captura de nome + telefone com DDD antes de escalar** | Obrigatório | Huggy (`setPhone(DDI,tel)`, `defaultCountry:'+55'`), Leadster, Nexloo, Digisac |
| 7 | **Validação nativa de CPF, CNPJ, CEP, telefone e data DD/MM/AAAA** | Obrigatório para captura; raro fora dela | **Só a Leadster tem completo** (verificado no bundle) — é a maior lacuna competitiva disponível |
| 8 | **Horário comercial + mensagem fora de expediente + formulário offline** | Obrigatório | Huggy, Cliengo, Octadesk, JivoChat, Leadster Live Chat, Chatwoot upstream |
| 9 | **Calendário de feriados brasileiros** | Diferencial pago | Huggy cobra por isso na tabela de planos; **ninguém mais tem** |
| 10 | **Só exibir o chat quando há atendente online** | Diferencial | Leadster Live Chat |
| 11 | **Botão/redirect para WhatsApp com mensagem pré-preenchida e contexto** | Obrigatório | Leadster (free), Huggy (`openWhatsapp`+`channelGreeting`), Cliengo, Nexloo |
| 12 | **Roleta/distribuição entre números ou vendedores no redirect** | Diferencial de alto valor | Leadster (plano Pro) |
| 13 | **Identificação assinada do visitante (HMAC/JWT)** | Obrigatório para B2B/área logada | Huggy (HS256), Blip, Chatwoot upstream — Octadesk e Kommo **não** documentam assinatura |
| 14 | **Passagem de variáveis/contexto para o fluxo antes do chat existir** | Obrigatório | Huggy (`huggyData.variables`), Cliengo (`webSnippet`), Kommo (`setMeta`) |
| 15 | **Captura automática de UTM e parâmetros de URL** | Obrigatório | Huggy tem artigo dedicado; Leadster embute gtag/fbq/dataLayer |
| 16 | **Disparo de eventos para GA4/GTM/Meta Pixel na conversão** | Obrigatório para o comprador de marketing | Leadster (nativo no bundle), Cliengo (`googleAdWordsConversionId`, `googleAnalyticsId`, `conversionPixels`) |
| 17 | **Continuidade de conversa entre sessões/páginas** | Obrigatório | Zenvia (`continuousConversation` + `_zid`), Blip (guest 30 dias) |
| 18 | **Modo inline/embutido além da bolha** | Diferencial técnico | Blip (`withTarget`), Kommo (`mode:'frame'`), Zenvia (`room`) |
| 19 | **API JS com abrir/fechar/enviar/identificar + eventos** | Obrigatório | Huggy (26 métodos), Kommo, Blip |
| 20 | **Aviso de privacidade/opt-in visível antes da coleta** | Obrigatório por LGPD, raro na prática | Só Zenvia tem bloco dedicado (`znv-opt-in`) |
| 21 | **Whitelabel: remover "powered by" ou trocar por marca própria** | Obrigatório no mercado de revenda BR | Cliengo (`whiteLabelId`), toda a categoria E |
| 22 | **Preço em BRL, com Pix e boleto** | Obrigatório | ChatWoot BR vende isso como diferencial central |
| 23 | **Mobile responsivo com comportamento diferente de desktop** | Obrigatório | Zenvia detecta desktop/mobile por `screen` no bundle |
| 24 | **Indicador de digitação e transcrição/histórico visível ao visitante** | Obrigatório | Cliengo (`chatIsWritingMessage`), Huggy (`showChats/hideChats`, "Histórico da conversa" no bundle da Leadster) |

### 12.2 As sete recomendações acionáveis

**R1 — Fechar a lacuna de validadores brasileiros no widget.**
A Leadster é o único player com CPF/CNPJ/CEP/telefone/data/e-mail-corporativo validados **dentro do fluxo do widget**, com mensagens de erro em português natural. Isso é diferencial verificável, barato de replicar e **imediatamente perceptível** para o comprador brasileiro. Inclui integração com base de municípios (IBGE) e consulta de CEP — a Leadster serve os dois como módulos de fluxo no próprio CDN.

**R2 — Tratar o handoff site→WhatsApp como funcionalidade de produto, não como link.**
Nenhum player inspecionado documenta a ponte completa: sessão anônima do site → captura → redirect com contexto → conversa de WhatsApp **amarrada ao mesmo contato e histórico**. Todos param no redirect (Estratégia 1 ou 2 da §8.2). Um handoff que preserve transcript, UTM, página de origem e atribuição de vendedor (roleta) é vantagem competitiva real e não existe pronta no mercado.

**R3 — Fazer da economia da mensagem um argumento explícito.**
Com a Meta cobrando por mensagem (e com relatos de cobrança de mensagens de serviço a partir de out/2026), o custo marginal do webchat próprio é **zero**. O ChatWoot BR já explora meia dessa tese ("R$0 por mensagem" no WhatsApp via QR). A tese completa — *"desloque o volume repetitivo para o canal que não tem tarifa por mensagem"* — ainda não foi ocupada por ninguém e favorece exatamente quem tem widget próprio bom.

**R4 — Calendário de feriados + horário por equipe/fila como feature nomeada.**
A Huggy cobra por "Controle de feriados" em tabela de preço. O Chatwoot upstream tem horário comercial, mas não tem feriados brasileiros (nacionais, estaduais, municipais). É uma lacuna pequena, concreta e vendável.

**R5 — Consentimento LGPD dentro do widget, com prova.**
Ninguém faz direito. O padrão do mercado é link para política e nada mais. Implementar opt-in com finalidade explícita, registro com timestamp e caminho de revogação transforma um requisito legal em argumento de venda — precedente: o ChatWoot BR já usa "DPA incluso, exportação por API, retenção configurável" como bullet de página de preço.

**R6 — Não competir na Posição A (guerra de preço WhatsApp).**
A faixa R$ 69–R$ 599 está saturada (Umbler, Nexloo, CWMKT, ChatWoot BR) e o teto de valor por cliente é baixo. A faixa R$ 989–R$ 4.999 exige venda consultiva, onboarding pago e SLA. O caminho que usa o widget como ativo é a **Posição B** (§11.3): manter a base de atendimento e adicionar captura de marketing no site.

**R7 — Assumir que a base Chatwoot é commodity e diferenciar acima dela.**
Existem no mínimo 6 operações brasileiras vendendo Chatwoot whitelabel/gerenciado, uma delas (ChatWoot BR) com posicionamento, preço público, verticalização e 14 páginas de comparação contra os grandes. A base MIT não é vantagem — vantagem é **o que foi construído em cima**: IA aplicada ao contexto brasileiro, validadores, feriados, handoff, LGPD, integrações nacionais (RD Station, Bling, Omie, Pipedrive, Tiny, Conta Azul, Asaas).

### 12.3 O que **não** fazer (com base no que o mercado mostrou)

- **Não tratar o widget como "canal na lista".** Quem fez isso (Poli, Nexloo, ChatGuru) chegou ao ponto de não ter widget nenhum ou usar plugin genérico no próprio site.
- **Não cobrar por mensagem no canal próprio.** É o custo do WhatsApp que o cliente já odeia; replicá-lo no webchat destrói o único argumento econômico do canal.
- **Não amarrar taxa de implantação alta.** Poli (R$ 1.197,90), RD (R$ 1.999 + R$ 3.799) e Zenvia (USD 137–842) criam a dor que ChatWoot BR e Huggy vendem contra ("sem taxa de setup", "sem fidelidade").
- **Não replicar identidade não assinada.** Octadesk e Kommo aceitam `login()` sem hash; é um problema de segurança, não um atalho de UX.
- **Não confiar em CDN de terceiro para o widget** — a recomendação está na doc oficial do próprio Blip (*"CDN may have availability problems and cause BLiP Chat instability"*), e a Huggy expõe versão fixa no `?v=8.0.0`.

---

## 13. LACUNAS DE PESQUISA

Itens que **não** consegui verificar e que ficam registrados como pendência, não como conclusão:

| # | Lacuna | Motivo |
|---|---|---|
| 1 | Preço-base dos planos Plus/Super do Blip | Não está no HTML público de blip.ai/planos |
| 2 | Preço do Blip Go | help.blip.ai retorna 403; fontes secundárias divergem (R$ 99 / R$ 299 / R$ 179,90–399,90) |
| 3 | Preços oficiais da Digisac | Todas as URLs de planos retornam 404; site direciona para demonstração |
| 4 | Preços numéricos do ChatGuru | Renderizados via JS; página serve só "A partir de" |
| 5 | Preços do Chatvolt | SPA client-side; nenhum valor no HTML servido |
| 6 | Preços da Weni pós-VTEX | Nenhuma tabela pública encontrada |
| 7 | Preços oficiais do Umbler Talk | `/talk/precos` retornou 404; valores vêm de blog de concorrente |
| 8 | Snippet e API do widget da Digisac, Poli, Movidesk, Fortics e RD Conversas | Documentação atrás de painel autenticado ou portal dinâmico |
| 9 | Snippet do Botmaker Webchat | Doc diz que está na aba Instalação do painel |
| 10 | Existência de webchat no Umbler Talk | Não encontrei confirmação |
| 11 | Notas atuais de Reclame Aqui, Capterra BR e B2B Stack | Bloqueio anti-bot; usei citações de terceiros com selo [FATO-2] |
| 12 | Documentação oficial da Meta sobre per-message pricing e cobrança de service messages em out/2026 | Só encontrei cobertura secundária; **verificar em developers.facebook.com antes de usar em decisão** |
| 13 | Preços de Conexão Azul, ChatLabel, XAMA, Chat Inteligente | 403 ou sem tabela pública |
| 14 | Se algum player brasileiro implementa merge automático de identidade site↔WhatsApp | Nenhuma doc pública encontrada; a ausência é indício, não prova |
| 15 | Política de whitelabel/remoção de marca da maioria dos players | Só Cliengo expõe isso publicamente |

---

## 14. FONTES

### 14.1 Páginas oficiais de planos e produto (baixadas e lidas)

- Leadster — preços: https://leadster.com.br/preco/
- Leadster — Live Chat (help): https://help.leadster.com.br/article/349-leadster-live-chat
- Leadster — instalação via HTML: https://help.leadster.com.br/article/37-instalar-o-codigo-via-html
- Leadster — instalação via GTM: https://help.leadster.com.br/article/25-como-instalar-a-ferramenta-pelo-google-tag-manager
- Leadster — botão/pop-up: https://help.leadster.com.br/article/46-como-inserir-o-chat-em-um-botao-popup-no-seu-site
- Leadster — WhatsApp Suite: https://help.leadster.com.br/article/311-whatsapp-leadster
- Leadster — plugin WordPress: https://wordpress.org/plugins/leadster-marketing-conversacional/
- RD Station Conversas / Tallos — planos: https://tallos.com.br/planos/
- RD Station Conversas — produto: https://www.rdstation.com/produtos/conversas/
- RD Station — widget de chat (ajuda): https://ajuda.rdstation.com/s/article/Integração-com-chat-do-site
- Octadesk — planos: https://www.octadesk.com/planos-e-precos
- Octadesk — integrações e FAQ: https://www.octadesk.com/integracoes
- Octadesk — instalar chat no site: https://help.octadesk.com/a/como-instalar-o-chat-no-meu-site/
- Octadesk — auto-login: https://help.octadesk.com/a/chat-do-site-identificado-automaticamente-auto-login/
- Octadesk — superintegrações: https://kb.octadesk.com/docs/superintegracoes
- Huggy — preços: https://www.huggy.io/pt-br/pricing
- Huggy — doc do Huggy Chat: https://huggydigital.github.io/docs/pt/huggy-chat.html
- Huggy — central de ajuda do widget: https://help.huggy.io/chat-online
- JivoChat — planos: https://www.jivochat.com.br/pricing/
- Blip — planos: https://www.blip.ai/planos/
- Blip Chat Widget — README oficial: https://github.com/takenet/blip-chat-widget
- Zenvia — preços: https://zenvia.com/en/prices/
- Movidesk — planos: https://www.movidesk.com/planos/
- Kommo — pricing: https://www.kommo.com/pricing/
- Kommo — botão de chat via API: https://pt-developers.kommo.com/docs/botão-de-chat-do-site-via-api
- Kommo — plugin WordPress: https://wordpress.org/plugins/website-chat-button-kommo-integration/
- Cliengo — pricing: https://www.cliengo.com/pricing/
- Cliengo — instalação: https://help.cliengo.com/hc/es/articles/115002656327
- Cliengo — API: https://developers.cliengo.com/docs/javascript-api
- Cliengo — plugin WordPress: https://wordpress.org/plugins/cliengo/
- Poli Digital — planos: https://poli.digital/planos/
- Poli Digital — parceiro Meta: https://poli.digital/parceiro-meta/
- Nexloo — planos: https://nexloo.com/planos/
- Nexloo — solução: https://nexloo.com/solucao/
- Digisac — webchat: https://digisac.com.br/canais/webchat
- Digisac — home: https://digisac.com.br/
- ChatGuru — home: https://chatguru.com.br/
- ChatGuru — planos: https://chatguru.com.br/planos-e-precos/
- Botmaker — preços: https://www.botmaker.com/pt-br/precos
- Botmaker — funções/Webchat Designer: https://botmaker.com/en/platform/functions
- Botmaker — integrar webchat: https://help.botmaker.com/pt/help/2710269571575244651
- Botmaker — personalizar webchat: https://help.botmaker.com/pt/help/7947490493588934594
- Fortics SZ.chat — tabela de preços: https://www.fortics.com.br/tabela-de-precos-sz-chat/
- Fortics — integração RD Station: https://www.fortics.com.br/rd-station-integrado-ao-fortics-sz-chat/
- ChatWoot BR — preços: https://chatwoot.app.br/precos
- ChatWoot BR — home: https://chatwoot.app.br/
- chatwoot.com.br — recursos/preços: https://chatwoot.com.br/precos
- CWMKT — home: https://cwmkt.com.br/
- BotAtende — whitelabel: https://botatende.com.br/whitelabel/
- Conexão Azul — revenda Chatwoot whitelabel: https://portal.conexaoazul.com/shop/plano-pessoal-revenda-chatwoot-whitelabel-466

### 14.2 Assets públicos baixados e inspecionados

- `https://cdn.leadster.com.br/neurolead/neurolead.min.js` — 456.101 bytes
- `https://cdn.leadster.com.br/` — listagem pública do bucket (1.000 chaves na primeira página; 194 arquivos `.js`, incluindo `app/modules/ibge_localidades.js`, `app/modules/postmon.js`, `app/modules/neurologic.js`, `ecommerce/widget-ecommerce.min.js`, `editor/neurologic-flowchart-editor.js`)
- `https://downloads.wordpress.org/plugin/leadster-marketing-conversacional.zip` — plugin oficial com `views/script-code.php`
- `https://static.zenvia.com/embed/js/zenvia-chat.min.js` — 15.746 bytes
- `https://code.jivosite.com/widget/{id}` — 18.483 bytes
- `https://s.cliengo.com/weboptimizer/{companyId}/{websiteId}.js` — 3.819 bytes (config pública de conta real)
- `https://www.blip.ai/scripts-bot/javascript/2023-v1-main.js`
- `https://raw.githubusercontent.com/takenet/blip-chat-widget/master/README.md`

### 14.3 Imprensa e institutos

- Mobile Time / Opinion Box — Super Panorama: https://www.mobiletime.com.br/noticias/09/06/2026/whatsapp-super-panorama/
- Mobile Time — cobrança por resposta e apps próprios: https://www.mobiletime.com.br/noticias/31/07/2026/whatsapp-apps-proprios/
- Mobile Time — Claro Empresas e Blip Go: https://www.mobiletime.com.br/noticias/10/08/2026/claro-empresas-disponibi/
- VTEX — aquisição da Weni: https://vtex.com/pt-pt/blog/vtex-adquire-weni-cx-potenciada-por-ia/
- Brazil Journal — VTEX/Weni: https://braziljournal.com/vtex-faz-aquisicao-para-crescer-no-pos-venda/
- Startups.com.br — VTEX/Weni: https://startups.com.br/negocios/ma/vtex-adquire-weni-para-fortalecer-cx-e-pos-venda/

### 14.4 LGPD

- E-Commerce Brasil: https://www.ecommercebrasil.com.br/artigos/lgpd-dados-pessoais-chatbots
- Contábeis: https://www.contabeis.com.br/artigos/69603/lgpd-para-chatbots-e-ia-como-garantir-a-conformidade/

### 14.5 Reviews (URLs canônicas — não abertas diretamente)

- Reclame Aqui — Octadesk: https://www.reclameaqui.com.br/empresa/octadesk/
- Reclame Aqui — Huggy: https://www.reclameaqui.com.br/empresa/huggy/lista-reclamacoes/
- B2B Stack — Octadesk: https://www.b2bstack.com.br/product/octadesk/avaliacoes
- B2B Stack — JivoChat: https://www.b2bstack.com.br/product/jivochat
- B2B Stack — Umbler Talk: https://www.b2bstack.com.br/product/umbler-talk
- B2B Stack — Zenvia Conversion: https://www.b2bstack.com.br/product/zenvia-conversion
- Capterra — Leadster: https://www.capterra.com/p/248283/Leadster/
- Capterra — Octadesk: https://www.capterra.com/p/192993/Octadesk/
- Capterra — Movidesk: https://www.capterra.com/p/192413/Movidesk/
- Capterra — Blip: https://www.capterra.com/p/200367/Blip/
- Capterra — Weni: https://www.capterra.com/p/228010/Weni/
- Capterra — Cliengo: https://www.capterra.com/p/158756/Cliengo/
- Capterra — JivoChat: https://www.capterra.com/p/178227/JivoChat/
- Capterra — Kommo: https://www.capterra.com/p/120048/Kommo/

### 14.6 Fontes secundárias usadas com ressalva ([FATO-2])

Todas são de operadores concorrentes ou agregadores comerciais. Listadas para rastreabilidade, **não** como autoridade:
`socialhub.pro`, `botaihub.com.br`, `tudoprawhats.com.br`, `zapfunil.com`, `botzila.io`, `bossbot.uk`, `chatbotscape.com`, `xpay.sh`, `multiwasap.com`, `expandenegocios.com.br`, `calculadorakommo.com.br`, `edialog.com.br`, `zaptrend.com.br`, `hyperflow.global`, `maxbot.com.br`, `chatlabs.com.br`, `dinamicasp.com.br`, `contabilstore.org.br`, `centralzap.com.br`, `chatinteligente.com.br`, `chat2desk.com.br`, `whatslabel.com`, `xama.pro`.

---

*Fim do documento. Coleta encerrada em 11/08/2026. Nenhum arquivo de código do repositório foi modificado.*
