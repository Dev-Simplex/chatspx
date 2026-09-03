# 19 — Contexto do visitante na prática: o que passar e o que fazer com isso

> **Onda:** Estudo do chat de site — trilha Integração
> **Data:** 12/08/2026
> **Escopo:** o **QUE** e o **PARA QUÊ** do contexto do visitante. O **COMO** técnico
> (protocolo, HMAC, SDK, sequência de chamadas) está nas tasks 17 e 18.
> **Regime:** fase de estudo. Nada foi implementado, nenhum arquivo de código foi tocado.

---

## Como ler este documento

| Marcador | Significa |
|---|---|
| `[MEDIDO]` | Número/comportamento lido diretamente na fonte primária — código deste repositório (com `arquivo:linha`) ou screenshot capturado nesta sessão. Reproduzível. |
| `[FATO]` | Afirmação de documentação oficial do fornecedor, com URL. Não executei o produto. |
| `[INFERÊNCIA]` | Conclusão minha, derivada de fatos/medições que estão explicitados logo ao lado. |
| `[NÃO VERIFICADO]` | Não consegui confirmar. Fica registrado como buraco, não como afirmação. |

**Sobre o rigor exigido nesta onda.** Onde eu li o código, digo "li o código". Onde eu
executei, digo que executei. **Eu não executei o ChatSPX nesta task** — a regra da
task veda login, e o painel do agente exige sessão autenticada. Portanto: todo o
inventário da Parte D é **leitura de código-fonte**, não observação de tela rodando.
Isso é uma limitação real e está marcada em cada afirmação. Uma segunda diferença que
mantenho separada o tempo todo: **o que o backend grava** ≠ **o que o painel renderiza**.
São coisas distintas neste produto, e é justamente aí que mora o maior gap.

Screenshots capturados nesta sessão via Playwright (Chromium headless,
`--no-sandbox --disable-dev-shm-usage`, viewport 1440×900) em
`plano/estudo-chat-web/integracao/shots/`.

---

## 0. Sumário executivo

Cinco conclusões, todas sustentadas por medição:

1. **O ChatSPX tem o cano, mas não tem a torneira nem o copo.** O SDK aceita atributos
   arbitrários, o backend grava tudo, o Captain injeta tudo no prompt — mas o **painel do
   agente só renderiza atributos que tenham uma `CustomAttributeDefinition` previamente
   cadastrada** (`CustomAttributes.vue:77`). Atributo enviado pelo site sem cadastro
   prévio: **grava no banco, entra no prompt da IA, e é invisível para o atendente.**

2. **O atendente que abre uma conversa vinda do site vê quase nada por padrão.** Navegador,
   SO, IP, página de origem e idioma existem — dentro de um accordion que nasce **fechado**
   (`useUISettings.js:172`), na **6ª posição** da lista (`useUISettings.js:4-17`).

3. **O mercado líder virou a chave: o LLM produz atributo estruturado, não consome atributo
   cru.** O Fin **não consulta custom attributes diretamente** — para dado vivo usa Data
   Connectors (API tipada sob demanda); e em compensação **classifica** cada conversa em
   atributos (Issue Type, Sentiment, Urgency, Spam) que alimentam roteamento e relatório.
   O ChatSPX faz exatamente o oposto: despeja tudo no prompt e não devolve nada estruturado.

4. **Existe uma superfície de prompt injection aberta pelo canal do site.** Qualquer JS na
   página do cliente — inclusive o próprio visitante pelo console — chama
   `setConversationCustomAttributes()`; o backend aceita chave arbitrária sem allowlist
   (`conversations_controller.rb:68`); e `conversation.liquid` interpola cada par
   chave/valor **direto no system prompt**, sem delimitador, sem sanitização. A flag
   `feature_contact_attributes` protege o **contato**, mas **não protege a conversa**
   (`agentable.rb:23`). O Intercom resolve isso com um toggle por atributo
   ("Require verified updates"); nós não temos equivalente.

5. **Coletamos o histórico de navegação e jogamos fora.** O widget instala um
   `MutationObserver` que detecta toda mudança de URL (`DOMHelpers.js:49-74`), mas o
   resultado só dispara campanha e sobrescreve uma variável global. **Não existe tabela de
   páginas visitadas no schema** — o Crisp, o Intercom e o HubSpot mostram essa timeline.

---

# PARTE A — O catálogo de contexto por tipo de negócio

## A.0 Antes da lista: os três tipos de contexto

Misturar esses três é o erro que transforma painel em lixo visual. A distinção não é
acadêmica — ela decide **onde o dado mora**, **quanto tempo vive** e **quem pode escrever nele**.

| Tipo | O que é | Vive em | Quem escreve | Exemplo |
|---|---|---|---|---|
| **Identidade** | Quem é a pessoa. Estável, atravessa conversas. | Contato | Backend autenticado | `plano`, `cliente_desde`, `cpf_hash` |
| **Estado** | Como a conta/pedido está agora. Muda sozinho. | **Não deve ser copiado** — deve ser buscado na hora | Sistema de origem | saldo, status de entrega, fatura vencida |
| **Intenção** | O que ele está fazendo nesta visita. Morre com a conversa. | Conversa | Front do site | produto sendo visto, carrinho, origem da campanha |

O Crisp formaliza exatamente essa separação: *"Conversation/session data e contact data não
são a mesma coisa — use conversation data para a troca atual e contact data para contexto
estável de perfil"* `[FATO]`
([help.crisp.chat](https://help.crisp.chat/en/article/what-is-custom-data-and-why-is-it-powerful-43jgi3/)).

**A regra prática que sai daí:** contexto de **estado** é o que mais tenta as pessoas a
copiar para dentro do chat — e é justamente o que **nunca** deve ser copiado. Saldo
copiado às 14h e lido pelo agente às 16h é pior que saldo ausente: parece verdade e não é.
Estado se busca na hora (Data Connector / Dashboard App), não se sincroniza.

**A regra de decisão para cada campo candidato** — quatro perguntas, e só entra quem passa:

1. **Muda a primeira frase do atendente?** Se o agente escreveria a mesma coisa com ou sem
   o campo, o campo é ruído.
2. **É estado ou é foto?** Se muda sozinho depois de gravado, não copia — busca.
3. **O que quebra se estiver errado?** Campo que direciona ação (rota, cobrança, desconto)
   precisa de origem autenticada. Campo decorativo pode vir do front.
4. **Precisa mesmo do valor, ou o derivado basta?** `nascimento: 1987-04-12` vs
   `faixa_etaria: 35-44`. Quase sempre o derivado basta — e ele não é PII sensível.

---

## A.1 E-commerce

O que o atendente precisa saber antes de ler a primeira mensagem.

| Campo | Onde mora | De onde o site tira | Por que muda o atendimento |
|---|---|---|---|
| `carrinho_valor` | Conversa | `cart.total_price` (Shopify AJAX Cart API `/cart.js`) | Separa "dúvida" de "carrinho de R$ 4.200 travado" — decide prioridade |
| `carrinho_itens` | Conversa | `cart.items[].title` (máx. 3 + contador) | Permite responder sobre o produto sem perguntar |
| `produto_atual` | Conversa | `product.handle` / dataLayer da PDP | O visitante está olhando **agora** — é a intenção mais quente que existe |
| `cupom_aplicado` | Conversa | `cart.discount_codes` | Metade dos contatos em checkout é cupom que não pegou |
| `etapa_checkout` | Conversa | contexto de checkout (cart / checkout / thank-you) | Fricção no pagamento pede resposta diferente de dúvida de frete |
| `pedido_aberto_id` | Conversa | último pedido não entregue | Ancora a conversa num pedido específico |
| `status_entrega` | **Buscar na hora** | transportadora / ERP | **Estado** — copiar produz mentira envelhecida |
| `cliente_recorrente` | Contato | `customer.orders_count > 1` | Cliente fiel com problema é risco de churn, não ticket comum |
| `ticket_medio` | Contato | `total_spent / orders_count` | Alçada de desconto sem pedir aprovação |
| `ltv_faixa` | Contato | faixa, não valor exato | Prioridade sem expor financeiro do cliente |

**Fonte técnica do carrinho:** Shopify expõe cart attributes como pares chave/valor no
carrinho e no checkout; atributos prefixados com `_` ficam ocultos ao comprador `[FATO]`
([shopify.dev](https://shopify.dev/docs/api/checkout-ui-extensions/2026-07-rc/target-apis/checkout-apis/attributes-api)).
O Gorgias documenta o caminho inverso — anexar o tracking dele aos cart/checkout attributes
`[FATO]` ([developers.gorgias.com](https://developers.gorgias.com/docs/how-to-attach-gorgias-tracking-data-to-shopify-cart-and-checkout-attributes)).

**Nota de realidade sobre o carrinho ao vivo:** o Gorgias **removeu** a visão de carrinho
ao vivo do sidebar do agente, "para melhorar performance e confiabilidade da plataforma"
`[FATO]` ([eesel.ai citando docs Gorgias](https://www.eesel.ai/blog/gorgias-shopify)).
`[INFERÊNCIA]` Manter estado ao vivo de um sistema externo dentro do painel é caro e
frágil mesmo para quem é especialista na vertical. Reforça a regra: **foto no atributo,
estado no card sob demanda.**

**PII — o que NÃO passar em e-commerce:** número de cartão (nem os 4 últimos — se precisar,
que venha do gateway no card sob demanda), CPF completo (use hash ou máscara `***.***.789-**`),
endereço completo (use cidade/UF), e-mail/telefone **dentro de custom attribute** (já são
campos nativos de contato; duplicar espalha PII por mais um lugar que ninguém audita).

---

## A.2 SaaS

| Campo | Onde mora | De onde o site tira | Por que muda o atendimento |
|---|---|---|---|
| `plano` | Contato | subscription do billing | Define alçada, SLA e tom |
| `trial_dias_restantes` | Contato | `trial_ends_at - hoje` | Trial no dia 12/14 é venda, não suporte |
| `mrr_faixa` | Contato | faixa, nunca valor exato | Prioridade sem expor receita no painel |
| `papel_usuario` | Contato | role no app | Admin pergunta outra coisa que membro |
| `conta_id` / `workspace` | Contato | app | Liga a pessoa à empresa |
| `uso_ultimos_7d` | Contato | analytics do produto | Separa "não consegue" de "não usa" |
| `feature_flags_ativas` | Conversa | flags da sessão | Bug que só existe atrás de flag |
| `fatura_vencida` | **Buscar na hora** | billing | **Estado** — muda a cada pagamento |
| `ultimo_erro_visto` | Conversa | último `error_id` da sessão | O maior atalho de diagnóstico que existe |
| `versao_app` / `build` | Conversa | build da sessão | Bug já corrigido em versão mais nova |

O `ultimo_erro_visto` é o campo mais subestimado da lista. `[INFERÊNCIA]` Ele transforma o
primeiro turno inteiro do atendimento ("o que apareceu na tela?" → "não lembro") em zero
turnos. Vale mais que MRR para tempo de resolução.

**Como o mercado descreve o conjunto mínimo de SaaS:** "user data, previous conversations,
ticket status, and linked documentation" em toda thread; account/subscription details
incluindo plan tier e MRR; trial status `[FATO]`
([gleap.io](https://www.gleap.io/blog/live-chat-saas-guide),
[usepylon.com](https://www.usepylon.com/blog/saas-customer-support-what-it-is-best-practices)).

**PII — o que NÃO passar em SaaS:** token de sessão / API key (é a tentação clássica do
"pra facilitar o debug"; vira credencial em texto puro num jsonb sem criptografia), senha
sob qualquer forma, conteúdo de dados do cliente (nomes de projetos e registros do usuário
final dele — você vira controlador de dado de terceiro sem contrato), MRR exato.

---

## A.3 Imobiliária, automotivo e educação — as verticais fortes no Brasil

Estas três compartilham uma característica que muda tudo: **o objeto de interesse é o
contexto**. Não é "o cliente tem plano X" — é "ele está olhando **este** imóvel/carro/curso
agora". O contexto é de intenção, mora na conversa, e é altamente perecível.

### Imobiliária

| Campo | Onde mora | Origem |
|---|---|---|
| `imovel_codigo` | Conversa | código na URL da página do imóvel |
| `imovel_tipo` / `dormitorios` | Conversa | ficha do imóvel |
| `imovel_valor` | Conversa | ficha |
| `finalidade` (compra/aluguel) | Conversa | contexto da página |
| `bairro_regiao` | Conversa | ficha |
| `faixa_preco_buscada` | Contato | filtros usados na busca |
| `financiamento_simulado` | Conversa | simulador do site |
| `entrada_disponivel` | Contato | qualificação |
| `imoveis_vistos` (últimos 3) | Conversa | histórico de navegação |

**Contexto de mercado BR:** os CRMs dominantes — **VistaSoft, Tecimob, Jetimob** — expõem API
ou webhook, permitindo consultar estoque em tempo real e registrar o lead qualificado com
histórico `[FATO]`
([blog.aleffpepper.com](https://blog.aleffpepper.com/posts/2026-04-08-chatbot-whatsapp-imobiliaria-qualificar-lead/)).
Portais relevantes: VivaReal, ZAP, OLX `[FATO]` (mesma fonte).

**Nota interna:** o ChatSPX **já tem** integração Vista em produção. `[MEDIDO]`
`enterprise/lib/captain/tools/enviar_fotos_imovel_tool.rb` grava na conversa os atributos
`fotos_ultimo_envio_at`, `codigos_buscados` e `property_code` (linhas 24, 34, 65, 147, 155).
`[INFERÊNCIA]` Como nenhum desses tem `CustomAttributeDefinition` cadastrada por padrão
(não há seed no repositório), eles caem na regra do `CustomAttributes.vue:77` e **não
aparecem no painel**. A IA sabe quais imóveis mandou; o corretor que assume a conversa, não.

### Automotivo

| Campo | Onde mora | Origem |
|---|---|---|
| `veiculo_modelo` / `ano` / `versao` | Conversa | página do veículo |
| `novo_ou_seminovo` | Conversa | página |
| `veiculo_valor` | Conversa | ficha |
| `tem_troca` + `veiculo_troca` | Contato | qualificação |
| `entrada_disponivel` | Contato | simulador |
| `interesse_test_drive` | Conversa | CTA clicado |
| `origem_portal` | Contato | Webmotors / iCarros / OLX |

A triagem canônica da vertical: *"modelo de interesse, novo ou seminovo, faixa de preço,
condição de financiamento desejada"* e *"se há um carro para troca"* `[FATO]`
([socialhub.pro](https://www.socialhub.pro/blog/chatbot-ia-whatsapp-concessionaria-veiculos/),
[chatclipy.com.br](https://chatclipy.com.br/crm-para-concessionarias-venda-mais-veiculos-com-whatsapp-e-ia/)).

**Alerta de PII específico da vertical:** as fontes descrevem coleta de **CPF** para simulação
de financiamento e menção a **RENAVAM** para troca `[FATO]` (mesmas fontes). São dois dos
dados mais sensíveis que existem, e o padrão do setor é coletá-los no chat. **Não devem
virar custom attribute em texto puro.** Se a simulação precisa deles, o caminho é: coletar
no sistema de financiamento (fora do chat) e trazer de volta só o **resultado**
(`simulacao_aprovada: true`, `parcela_estimada: 1.240`).

### Educação

| Campo | Onde mora | Origem |
|---|---|---|
| `curso_interesse` | Conversa | página do curso |
| `modalidade` (presencial/EAD/híbrido) | Conversa | página |
| `unidade_campus` | Conversa | seletor / CEP |
| `turno` | Conversa | página |
| `valor_mensalidade` | Conversa | ficha |
| `processo_seletivo` (vestibular/ENEM/transferência) | Conversa | CTA |
| `ja_e_aluno` | Contato | área do aluno |
| `ciclo_matricula` | Conversa | calendário |
| `bolsa_interesse` (ProUni/FIES/desconto) | Conversa | página de bolsas |

Chatbots do setor consomem *"listas de cursos disponíveis, campus mais próximo por CEP, e
autenticação de área do aluno"* `[FATO]`
([blog.lyceum.com.br](https://blog.lyceum.com.br/chatbot-para-instituicao-de-ensino/)).

**PII crítica:** se `ja_e_aluno = true`, o visitante pode ser **menor de idade**. Nota,
frequência e situação financeira são dado educacional protegido. `[INFERÊNCIA]` Passar
`ja_e_aluno` e `matricula_id` é suficiente; nota e financeiro se buscam autenticados.

---

## A.4 Serviços e B2B

| Campo | Onde mora | Origem |
|---|---|---|
| `empresa` | Contato | formulário / enriquecimento por domínio de e-mail |
| `cargo` | Contato | formulário |
| `porte_empresa` | Contato | enriquecimento |
| `segmento` | Contato | enriquecimento |
| `origem_campanha` (utm_*) | Conversa | query string da landing |
| `pagina_entrada` | Conversa | primeira URL da sessão |
| `estagio_funil` | Contato | CRM |
| `ja_e_cliente` | Contato | CRM |
| `dono_da_conta` | Contato | CRM |
| `materiais_baixados` | Contato | histórico |

O `dono_da_conta` é o que evita o pior erro de B2B: `[INFERÊNCIA]` um atendente genérico
respondendo uma conta que já tem executivo dedicado. É contexto barato que previne dano caro.

**Sobre UTM:** o Intercom trata `utm_campaign`, `utm_source`, `utm_medium`, `utm_content`,
`utm_term` como **atributos padrão** da JS API, não como custom `[FATO]`
([developers.intercom.com](https://developers.intercom.com/installing-intercom/web/attributes-objects)).
`[INFERÊNCIA]` Bom sinal de que atribuição de campanha é considerada contexto de primeira
classe — não algo que cada cliente deveria ter que cadastrar à mão.

---

## A.5 A lista negativa transversal — o que NUNCA passar como atributo

Vale para todas as verticais. O critério: **o que não pode virar linha de texto num jsonb
sem criptografia, replicado para o prompt de um LLM e visível a qualquer agente da conta.**

| Nunca passar | Por quê | O que passar no lugar |
|---|---|---|
| Cartão, CVV, validade | PCI-DSS. Um jsonb não é ambiente de cartão. | Nada. Cobrança fora do chat. |
| Senha, token, API key, session ID | Credencial em texto puro | Nada |
| CPF/CNPJ completo | Identificador nacional, dado de fraude | Hash, ou máscara `***.***.789-**` |
| RG, CNH, RENAVAM, passaporte | Documento | Só flag de verificação |
| Dado de saúde, biometria, religião, política, orientação, origem racial | **Dado sensível — LGPD art. 5º II**, exige base legal específica | Não passar |
| Endereço completo | Excesso para atender | Cidade/UF |
| Data de nascimento exata | Combinada com nome, reidentifica | Faixa etária |
| Saldo, limite, valor exato de dívida | Financeiro | Faixa ou flag |
| Conteúdo de mensagem privada de terceiro | Você vira controlador de dado alheio | Não passar |

**Base legal — o ponto que o time comercial esquece.** A LGPD define consentimento como
*"manifestação livre, informada e inequívoca"* para *"finalidade determinada"*, e
autorizações genéricas podem ser consideradas nulas `[FATO]`
([arpensp.org.br/ConJur](https://www.arpensp.org.br/noticia/97288),
[dataguide.com.br](https://dataguide.com.br/consentimento-digital-shoppings-incorporadoras/)).
`[INFERÊNCIA]` Um banner de cookies genérico **não cobre** enviar CPF e simulação de
financiamento para dentro do chat. Cada categoria de dado precisa de finalidade declarada.

**Contraste medido que vale destacar aqui:** o Intercom declara *"For privacy and security
reasons, we do not provide the IP addresses of users/visitors"* — rastreia cidade/país
derivados do IP, mas **não expõe o IP** `[FATO]`
([intercom.com/help/1722980](https://www.intercom.com/help/en/articles/1722980-how-intercom-tracks-and-stores-data)).
O ChatSPX **exibe o IP bruto no painel** para qualquer agente: `[MEDIDO]`
`ConversationInfo.vue:43,78-81` renderiza `created_at_ip` sob o rótulo
`CONTACT_PANEL.IP_ADDRESS`, gravado em `widgets_controller.rb:69` e
`configs_controller.rb:42`. São decisões **opostas** sobre o mesmo dado.

**Retenção:** o Intercom expira visitantes não vistos há **9 meses** — *"We will
automatically delete the entire record and event history of visitors who have not visited
your site in 9 months"* `[FATO]` (mesma URL). `[MEDIDO]` Não encontrei política equivalente
de expurgo de visitante no ChatSPX.

---

# PARTE B — Como o mercado exibe isso para o atendente

## B.1 Anatomia do painel lateral

| | **Intercom** | **Zendesk** | **HubSpot** | **Gorgias** | **Crisp** | **ChatSPX (hoje)** |
|---|---|---|---|---|---|---|
| Local | Painel direito ("Details") | App tray direita | Sidebar direita | Sidebar direita | Painel direito | Painel direito |
| Largura | `[NÃO VERIFICADO]` | **320px** fixo com `location.flexible: false` `[FATO]` | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | **320px** (`md`) / **360px** (`2xl`) `[MEDIDO]` |
| Organização | Seções + apps fixáveis | Cards de app empilhados | Cards por objeto CRM | Widgets arrastáveis | Widgets colapsáveis | Accordions arrastáveis `[MEDIDO]` |
| Tipagem dos campos | **8 formatos** `[MEDIDO]` | **11 tipos** de campo `[FATO]` | Tipado por propriedade | Tipado (Shopify) | Aparenta string livre `[MEDIDO]` | **8 tipos** `[MEDIDO]` |
| Editável pelo agente | Sim `[FATO]` | Sim | Sim | Sim | Sim `[MEDIDO]` | Sim `[MEDIDO]` |
| Reordenável | Sim (pin/edit apps) `[FATO]` | Sim | Sim | Sim (drag & drop) `[FATO]` | `[NÃO VERIFICADO]` | Sim `[MEDIDO]` |
| Timeline de páginas | Sim — app dedicado `[FATO]` | Via app | Sim (timeline CRM) `[FATO]` | `[NÃO VERIFICADO]` | Sim — "last browsed pages" `[FATO]` | **Não existe** `[MEDIDO]` |
| Mostra IP | **Não, por política** `[FATO]` | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | Mostra mapa de geolocalização `[MEDIDO]` | **Sim, IP bruto** `[MEDIDO]` |

**Medições e como foram obtidas:**

- **Zendesk 320px** — *"se quiser que o iframe do seu app fique fixo em 320px, defina
  `location.flexible` como false"*; apps são responsivos por padrão `[FATO]`
  ([developer.zendesk.com](https://developer.zendesk.com/api-reference/apps/apps-support-api/ticket_sidebar/)).
  Screenshot: `shots/zendesk-ticket-sidebar-doc.png`.
- **ChatSPX 320/360px** — `[MEDIDO]` `ConversationSidebar.vue:59`:
  `md:w-[320px] md:min-w-[320px] ... 2xl:min-w-[360px] 2xl:w-[360px]`. Em telas
  abaixo de `md`, vira overlay `w-full max-w-sm` sobre a conversa. Convergência
  interessante: nós e o Zendesk chegamos no mesmo 320px por caminhos independentes.
- **Intercom 8 formatos** — `[MEDIDO]` no screenshot `shots/intercom-cvda-doc-img2.png`,
  capturado da doc oficial: o dropdown "Format" lista **Text, List, Number, Decimal Number,
  Boolean, Date & Time, Reference, File upload**.
- **Zendesk 11 tipos** — drop-down, multi-select, checkbox, text, multi-line, numeric,
  decimal, date, regex, **credit card**, lookup relationship `[FATO]`
  ([support.zendesk.com](https://support.zendesk.com/hc/en-us/articles/4408838961562-About-custom-fields-and-custom-field-types)).
  Máximo de **2000 opções** por dropdown/multiselect `[FATO]` (mesma fonte).
  Campos de usuário/organização são visíveis **só ao time** — end users não veem `[FATO]`
  ([support.zendesk.com](https://support.zendesk.com/hc/en-us/articles/4408822051866-Adding-custom-fields-to-users)).
  `[INFERÊNCIA]` O tipo **credit card** existir como tipo nativo é revelador: em vez de
  proibir, o Zendesk deu um tipo que mascara e trata o dado adequadamente.
- **ChatSPX 8 tipos** — `[MEDIDO]` `custom_attribute_definition.rb:47`:
  `enum attribute_display_type: { text: 0, number: 1, currency: 2, percent: 3, link: 4,
  date: 5, list: 6, checkbox: 7 }`. Empatamos com o Intercom em quantidade. **Não temos**
  `Reference` (ponteiro para outro registro) nem `File upload`; **temos** `currency` e
  `percent`, que eles não têm como formato dedicado.
- **Intercom 5.000 CvDAs** por workspace; 250 atributos de texto por tipo de conversa/ticket;
  até 1.000 opções de lista por import CSV `[FATO]`
  ([intercom.com/help/6546210](https://www.intercom.com/help/en/articles/6546210-create-and-use-conversation-data-attributes-cvdas-in-the-inbox)).
  `[MEDIDO]` O ChatSPX **não tem limite** de quantidade de definições — só unicidade por
  `(attribute_key, attribute_model, account_id)`.

**O painel do Crisp, observado.** Screenshot `shots/crisp-custom-data-doc-img2.png`
(imagem da doc oficial, capturada nesta sessão). `[MEDIDO]` **nesse print**: o painel
direito tem, de cima para baixo — avatar + nome + e-mail clicável + empresa + ícone de
rede social; botão primário "View {Nome} Profile" em azul de largura total; e três seções
colapsáveis: **Quick jump**, **Segments for conversation**, **Visitor data**. A seção
"Visitor data" está **expandida por padrão** nesse print e renderiza pares chave/valor em
tabela zebrada, com barra colorida à esquerda de cada chave. Campos visíveis:
`company_size`, `user_id`, `website_id`, `plan`, `plan_price`, `is_trialing`.
Em `shots/crisp-custom-data-doc-img1.png` (tela de perfil, superfície **diferente**) há um
contador **"Data for Antoine — 23"** e um **mapa de geolocalização**.
*Distinção que não vou achatar:* o contador e o mapa foram observados na **tela de perfil**,
não no painel da conversa. Não afirmo que apareçam no painel lateral.

**Gorgias — o que a sidebar mostra:** perfil do cliente, histórico e últimos pedidos,
status de fulfillment/tracking, e dados de apps conectados (Recharge, Loop Returns,
AfterShip, Yotpo) `[FATO]` ([eesel.ai](https://www.eesel.ai/blog/gorgias-shopify)). O
agente pode **agir** — refund, cancel, duplicate, edit de pedido Shopify — sem sair do
ticket `[FATO]` (mesma fonte). Widget customizável por drag & drop via ícone de engrenagem
`[FATO]` (mesma fonte).

`[INFERÊNCIA]` O diferencial do Gorgias não é *mostrar* mais dado — é **transformar dado em
ação no mesmo lugar**. Painel que só informa obriga o agente a trocar de aba; painel que
age fecha o loop. Nenhum campo de texto substitui um botão "Reembolsar".

**HubSpot:** sidebar direita mostra associações do contato — empresa, negócio, ticket —
mais segmentos, anexos e conversas anteriores `[FATO]`
([knowledge.hubspot.com](https://knowledge.hubspot.com/inbox/use-the-conversations-inbox)).
`[INFERÊNCIA]` É o único dos cinco cujo painel é primariamente **grafo de objetos
relacionados**, não lista de pares chave/valor. Faz sentido: o produto é o CRM, o inbox é
uma vista dele.

---

## B.2 Apps embutidos: as três arquiteturas

Esta é a comparação mais importante da Parte B, porque é onde o ChatSPX diverge
estruturalmente — não em polimento, em **arquitetura**.

| | **Intercom Canvas Kit** | **Zendesk Apps** | **ChatSPX / Chatwoot Dashboard Apps** |
|---|---|---|---|
| Modelo | Servidor devolve **JSON declarativo**; Intercom renderiza nativo | **Iframe** com SDK JS | **Iframe** cru |
| Onde aparece | 5 locais, incluindo painel de detalhes da conversa `[FATO]` | App tray à direita (`ticket_sidebar`) `[FATO]` | **Aba que substitui a conversa** `[MEDIDO]` |
| Convive com a conversa | **Sim** — card ao lado | **Sim** — tray ao lado | **Não** — esconde as mensagens `[MEDIDO]` |
| Ciclo de vida | `initialize` → `configure` → `submit` `[FATO]` | `client.get()` / `client.invoke()` `[FATO]` | Um `postMessage` no `load` + refetch sob pedido `[MEDIDO]` |
| Componentes | Text, Button, Input, Data Table, Dropdown, List… `[FATO]` | HTML livre no iframe | HTML livre no iframe |
| Atualização ao vivo | **Live Canvas** — atualiza sem interação `[FATO]` | Polling do próprio app | Só no load ou sob pedido `[MEDIDO]` |
| Autenticidade do payload | **HMAC-SHA256** em `X-Body-Signature` `[FATO]` | Assinatura do ZAF | **Nenhuma** `[MEDIDO]` |
| Granularidade do dado enviado | Payload delimitado pelo Intercom | App pede o que precisa via `client.get()` | **Tudo de uma vez** `[MEDIDO]` |

**Medições do nosso lado — `DashboardApp/Frame.vue`:**

- `[MEDIDO]` Linhas 33-39: o contexto enviado é
  `{ conversation: <currentChat inteiro>, contact: <contato inteiro>, currentAgent: {id, name, email} }`.
  Não há seleção de campos. **É tudo ou nada.**
- `[MEDIDO]` Linhas 79-91: um único `postMessage` no `@load` do iframe, com
  `targetOrigin` derivado da URL configurada (linhas 71-78) — isso está correto e evita
  broadcast para `*`. Não há assinatura do corpo: o app de terceiro **não tem como provar**
  que a mensagem veio mesmo do ChatSPX.
- `[MEDIDO]` Linhas 62-67: o refetch responde a `event.data === 'chatwoot-dashboard-app:fetch-info'`
  **sem verificar `event.origin`**. Qualquer frame que consiga postar na janela dispara o
  reenvio. `[INFERÊNCIA]` O impacto prático é limitado (o reenvio vai para o `targetOrigin`
  correto, não para o solicitante), mas é um listener sem validação de origem.
- `[MEDIDO]` `ConversationBox.vue:143-180`: o app vira **aba** (`<woot-tabs>`, linha 143).
  Na linha **159**, `<div v-show="!activeIndex">` esconde o `MessagesView` inteiro sempre
  que uma aba de app está ativa.

**Confirmação visual independente:** `shots/chatwoot-dashboard-apps-doc-img3.png`, capturado
da documentação oficial do Chatwoot, mostra exatamente isso — abas
`Messages | Customer Orders` no topo, e com "Customer Orders" ativa a área de mensagens
**desapareceu**, dando lugar a uma tela cheia de pedidos com botões Refund/Cancel/View Details.
`[MEDIDO]` — código e print oficial concordam.

`[INFERÊNCIA]` Esse é o ponto arquitetural mais consequente do documento. Um app que
**esconde a conversa** não é contexto — é destino. O agente lê o pedido, volta para a aba
de mensagens, e agora precisa lembrar o que leu. O Intercom e o Zendesk colocam o card
**ao lado** justamente porque contexto só serve enquanto você está lendo a mensagem.
Nossa arquitetura de Dashboard App resolve "integrar sistema externo" e **não resolve**
"dar contexto ao atendente" — são problemas diferentes que hoje compartilham o mesmo recurso.

---

## B.3 Histórico e timeline do visitante

| Produto | O que mostra | Profundidade |
|---|---|---|
| **Intercom** | App "Recent page views" no sidebar do Inbox | **até 20** visitas ao expandir com "See all" `[FATO]` |
| **Intercom** | Eventos: primeira vez, última vez, contagem total | Page views e interações com Help Center por padrão `[FATO]` |
| **Crisp** | Widget "last browsed pages" + "profile events" | `[NÃO VERIFICADO]` |
| **HubSpot** | Timeline do registro CRM (atividades associadas) | `[NÃO VERIFICADO]` |
| **Gorgias** | Pedidos anteriores + tracking | `[NÃO VERIFICADO]` |
| **ChatSPX** | **Nada** | — `[MEDIDO]` |

- Intercom, 20 páginas: `[FATO]`
  ([intercom.com/help/9277565](https://www.intercom.com/help/en/articles/9277565-recent-page-views-app)).
  O app precisa ser **fixado** via "Edit apps" — não vem ligado `[FATO]` (mesma fonte).
  Funciona para users **e** leads `[FATO]` (mesma fonte). Para *visitors* anônimos:
  `[NÃO VERIFICADO]`.
- Modelo de evento do Intercom: *"Events record the first and last time a user does
  something and the total amount of times they do something"* `[FATO]`
  ([intercom.com/help/216](https://www.intercom.com/help/en/articles/216-record-customer-activity-with-event-tracking)).
  `[INFERÊNCIA]` É um modelo **agregado** (primeira/última/contagem), não um log completo —
  barato de armazenar e suficiente para atendimento. Vale copiar a ideia.
- Crisp: widgets de conversa incluem *"contact details, conversation routing, visitor
  device, segments, last browsed pages, profile events"* `[FATO]`
  ([help.crisp.chat](https://help.crisp.chat/en/article/getting-started-with-the-crisp-inbox-opv83/)).
- **ChatSPX:** `[MEDIDO]` `grep create_table db/schema.rb` → das **125** tabelas, as únicas
  com "event" no nome são `reporting_events`, `reporting_events_rollups` e `sla_events` —
  todas de métrica de atendimento. **Não existe tabela de navegação de visitante.**

**E aqui está a ironia medida.** `[MEDIDO]` `sdk/DOMHelpers.js:49-74` — o widget instala um
`MutationObserver` sobre o `<body>` (`childList: true, subtree: true`) e, a cada mutação,
compara `document.location.href` com o valor anterior. Ou seja: **detecta toda navegação,
inclusive em SPA**. E o que faz com isso? `[MEDIDO]` `widget/App.vue:275-284`: dispara
`initCampaigns` e faz `window.referrerURL = referrerURL`. Só. O valor é **sobrescrito** a
cada página.

`[INFERÊNCIA]` Consequência direta: o campo "Iniciado a partir de" que o agente vê **não é
a landing page** — é a URL em que o visitante estava no instante em que a conversa foi
criada (`base_controller.rb:42` lê `permitted_params[:message][:referer_url]`, alimentado
por `widget/api/endPoints.js:18` com o `referrerURL` corrente). Se ele entrou por um anúncio,
navegou por cinco páginas e só então abriu o chat, **a origem real da campanha se perdeu**.
A infraestrutura de captura existe e funciona; o que falta é persistir.

---

# PARTE C — O que a IA faz com o contexto

## C.1 Os quatro usos

1. **Personalizar.** Com Identity Verification ligada, o Fin recebe atributos básicos e os
   usa para tratar pelo nome, considerar localização e ajustar o tom `[FATO]`
   ([intercom.com/help/12508017](https://www.intercom.com/help/en/articles/12508017-fin-as-a-customer-agent-for-service-sales-and-more) e cobertura relacionada).
2. **Qualificar.** Nas verticais BR, é o uso dominante: o bot coleta modelo/faixa de
   preço/financiamento e entrega ao vendedor um lead já triado `[FATO]`
   ([socialhub.pro](https://www.socialhub.pro/blog/chatbot-ia-whatsapp-concessionaria-veiculos/)).
3. **Rotear.** Escalation Rules do Intercom são **determinísticas sobre dado**:
   *"Customer plan IS Pro"*, *"Customer Sentiment is angry"* `[FATO]`
   ([intercom.com/help/11680403](https://www.intercom.com/help/en/articles/11680403-how-to-create-fin-attributes)).
4. **Decidir escalar.** Duas camadas no Intercom: **Escalation Rules** (determinística,
   sobre atributo) e **Escalation Guidance** (linguagem natural, cenário) `[FATO]` (mesma fonte).

`[INFERÊNCIA]` A separação em duas camadas é a parte inteligente. Regra determinística é
auditável e testável; guidance em linguagem natural cobre o resto. Quem tenta fazer tudo
por prompt perde a auditabilidade; quem tenta fazer tudo por regra não cobre a cauda longa.

## C.2 A virada de 2026: o LLM **produz** atributo estruturado

Aqui precisei desfazer uma contradição entre fontes — e o resultado muda a recomendação.

- Materiais de terceiros afirmam que o Fin "acessa e usa Custom Data Attributes ao gerar
  respostas".
- A documentação **oficial** do Intercom sobre Data Connectors diz o contrário: o Fin
  **não consegue consultar custom attributes ou dados de evento diretamente**, e *"To
  enable Fin to respond with real-time asset data, set up Data Connectors so Fin can access
  external data sources via API"* `[FATO]`
  ([intercom.com/help/9916183](https://www.intercom.com/help/en/articles/9916183-best-practices-when-using-data-connectors-with-fin)).

**Fica registrada a discrepância**, e eu fico com a fonte primária. `[NÃO VERIFICADO]`:
não testei o produto para arbitrar em definitivo.

O que é inequívoco é a direção oposta do fluxo. **Fin Attributes** são atributos que o Fin
**preenche**: *"Fin Attributes automatically classifies every conversation"*, em momentos-chave
(quando conclui, ao escalar, ao fechar) `[FATO]`
([intercom.com/help/11680403](https://www.intercom.com/help/en/articles/11680403-how-to-create-fin-attributes)).
Categorias documentadas: **Issue Type** (Billing, Projects, Account Management), **Sentiment**
(Positive/Neutral/Negative), **Urgency** (Urgent/High/Normal/Low), **Spam Detection**
(Spam/Legitimate) `[FATO]` (mesma fonte). E o destino: *"use the detected attribute values in
Escalation Rules, Workflows, and Reporting"* e *"All detected attribute data flows into
Intercom reports for deep insight — no manual tagging required"* `[FATO]` (mesma fonte).

`[INFERÊNCIA]` Esta é a tese central da Parte C, e ela é contraintuitiva:

> O caminho maduro **não** é enfiar mais contexto no prompt. É **tipar a entrada** (dado
> vivo via API sob demanda, não copiado) e **estruturar a saída** (o LLM devolve atributos
> tipados que alimentam roteamento, filtro e relatório).

Um LLM lendo 40 pares chave/valor de qualidade duvidosa gasta contexto e ganha pouco.
Um LLM que classifica cada conversa em quatro dimensões confiáveis produz dado que a
operação inteira consome — inclusive sem IA.

**No nosso caso, o desenho está invertido:** `[MEDIDO]` `conversation.liquid:9-18` despeja
todos os `custom_attributes` **e** todos os `additional_attributes` da conversa no prompt;
`contact.liquid:8-17` faz o mesmo com o contato. E `[MEDIDO]` a tool
`Captain::Tools::Copilot::SetCustomAttributesService` permite ao LLM **escrever** atributos —
mas com `param :attributes, type: :string` recebendo **JSON livre**
(`set_custom_attributes_service.rb:9`), sem schema, sem enum, sem validação contra as
definições cadastradas. `[INFERÊNCIA]` Resultado: o LLM pode inventar `sentimento`,
`sentiment`, `humor_cliente` em conversas diferentes, e nenhum deles aparece no painel nem
é filtrável — porque não há `CustomAttributeDefinition` correspondente. É o pior dos dois
mundos: consome tudo e produz nada aproveitável.

## C.3 Risco: prompt injection e vazamento de PII

### C.3.1 O risco, em geral

Prompt injection é **#1 no OWASP Top 10 for LLM Applications 2025** `[FATO]`
([owasp.org](https://owasp.org/www-project-top-10-for-large-language-model-applications/assets/PDF/OWASP-Top-10-for-LLMs-v2025.pdf)).
A variante que importa aqui é a **indireta**: instruções escondidas dentro de conteúdo que
o sistema vai ingerir depois, sem o atacante nunca tocar na interface de prompt `[FATO]`
([lakera.ai](https://www.lakera.ai/blog/indirect-prompt-injection)). Notas e campos de CRM
são citados explicitamente como vetor: *"malicious instructions hide in places most teams
never monitor, including CRM notes"* `[FATO]` (mesma fonte).

Mitigações recomendadas pelo OWASP: tratar todo conteúdo recuperado como não confiável e
**separá-lo/demarcá-lo** claramente; restringir o comportamento do modelo por system prompt;
validar entrada **e** saída; defesa em profundidade com menor privilégio e humano no loop
para ações sensíveis; teste adversarial regular `[FATO]`
([oligo.security](https://www.oligo.security/academy/owasp-top-10-llm-updated-2025-examples-and-mitigation-strategies),
[aembit.io](https://aembit.io/blog/owasp-top-10-llm-risks-explained/)).
Padrão estrutural mais citado: **Dual-LLM** — um modelo em quarentena lê o não confiável,
outro privilegiado executa, e os dois não compartilham camada `[FATO]`
([searchengineland.com](https://searchengineland.com/prompt-injection-brand-ai-workflows-risk-483819)).

### C.3.2 O que o mercado faz especificamente com atributos vindos do browser

O Intercom tem um controle **por atributo**: `[FATO]`
([intercom.com/help/11087109](https://www.intercom.com/help/en/articles/11087109-securing-the-data-you-send-via-the-messenger))

- A opção chama-se **"Require verified updates"**.
- *"When this setting is enabled, any attempts to set or update attributes through the
  Messenger are ignored unless they come from an authenticated request."*
- *"The data is ignored. Intercom will not apply updates unless the JWT is present and valid."*
- Vale para atributos **padrão e customizados** — *"You must lock down all attributes,
  standard and custom"*.
- Caminho: **Settings → Data → People → [atributo] → toggle "Require verified updates"**.
- Configuração **workspace-wide**; o backend precisa estar pronto antes de ligar.
- Na JS API, o efeito é explícito: *"Se um custom attribute foi configurado para impedir
  atualizações via Messenger, aquele valor será ignorado"* `[FATO]`
  ([developers.intercom.com](https://developers.intercom.com/installing-intercom/web/attributes-objects)).
- Intercom também recomenda **JWT** no lugar do HMAC `user_hash` legado — *"Identity
  Verification will not receive any future updates"* `[FATO]`
  ([intercom.com/help/10807823](https://www.intercom.com/help/en/articles/10807823-migrating-from-identity-verification-to-messenger-security-with-jwts)).
- E, sobre o Fin especificamente, alerta para dois cenários: usuário malicioso alterando os
  próprios atributos, e manipulação de dados no sistema de terceiro antes da sincronização
  `[FATO]` ([intercom.com/help/9916183](https://www.intercom.com/help/en/articles/9916183-best-practices-when-using-data-connectors-with-fin)).

Sobre injection propriamente: o Intercom afirma acompanhar novas técnicas e ajustar a
estratégia de prompting defensivo, e migrar para modelos mais robustos `[FATO]`
([intercom.com/blog](https://www.intercom.com/blog/data-privacy-security-ai-chatbots/)).
`[INFERÊNCIA]` É mitigação probabilística, não garantia — coerente com o próprio OWASP,
que registra não estar claro se existe método infalível.

Do lado de PII exibida, o Zendesk vende **ADPP** como add-on: destaque automático de PII
(nomes, e-mails, cartões) em comentários e anexos PDF, com redação por clique ou automática
via trigger `[FATO]`
([support.zendesk.com](https://support.zendesk.com/hc/en-us/articles/6669399593882-Automatically-detecting-sensitive-information-for-redaction-ADPP-add-on)).

### C.3.3 A cadeia no ChatSPX — passo a passo, com arquivo:linha

Reconstruí a cadeia lendo o código. **Não executei o ataque** — a regra da task veda tocar
em ambiente. Portanto: cada elo é `[MEDIDO]`; a conclusão de ponta a ponta é `[INFERÊNCIA]`.

| # | Elo | Evidência | Marcador |
|---|---|---|---|
| 1 | O SDK expõe `setConversationCustomAttributes(obj)` no `window.$chatwoot`, chamável por qualquer JS da página — inclusive pelo console do visitante | `entrypoints/sdk.js:157-165` | `[MEDIDO]` |
| 2 | Vira `postMessage` para o iframe do widget, que despacha para a store | `widget/App.vue:304-309` | `[MEDIDO]` |
| 3 | Autenticação é `website_token` (público, está no snippet do site) + `X-Auth-Token` (JWT do widget, no cookie do visitante). **Nenhum HMAC** para atributos de conversa | `website_token_helper.rb:1-21` | `[MEDIDO]` |
| 4 | Strong params aceitam **qualquer chave**: `custom_attributes: {}` | `widget/conversations_controller.rb:100` | `[MEDIDO]` |
| 5 | Grava com **substituição total**, sem allowlist, sem checar definições: `conversation.update!(custom_attributes: permitted_params[:custom_attributes])` | `widget/conversations_controller.rb:68` | `[MEDIDO]` |
| 6 | Única validação: **1500 caracteres por chave** (strings) e 9.999.999.999 (inteiros). **Sem limite de número de chaves** | `jsonb_attributes_length_validator.rb:14-22` + `conversation.rb:80-81` | `[MEDIDO]` |
| 7 | O snippet do prompt interpola **cada par** como linha `- chave: valor`, sem delimitador, sem escape | `prompts/snippets/conversation.liquid:9-13` | `[MEDIDO]` |
| 8 | A conversa **sempre** entra no contexto. A flag `feature_contact_attributes` gateia **só o contato** | `agentable.rb:19-25` (`contact: config['feature_contact_attributes'].present? ? state[:contact] : nil`) | `[MEDIDO]` |
| 9 | Esse contexto é renderizado dentro do system prompt do agente | `prompts/runtime_context.liquid:4-20` | `[MEDIDO]` |

`[INFERÊNCIA]` Encadeando 1→9: **texto arbitrário controlado pelo lado do site chega ao
system prompt do agente de IA, sem sanitização, sem delimitação e sem limite de volume.**
O teto por chave é 1500 caracteres, mas como não há teto de quantidade de chaves, o volume
total é efetivamente ilimitado — o que também é vetor de custo e de esvaziamento de contexto,
não só de injection.

**Dois agravantes medidos:**

- `[MEDIDO]` O contato **não tem** a validação de comprimento. `grep` por
  `jsonb_attributes_length` em `app/models/contact.rb` retorna vazio — a validação existe
  em `conversation.rb:80-81` e não no contato. Ou seja, `custom_attributes` de contato não
  têm nem o teto de 1500 caracteres.
- `[MEDIDO]` A flag `feature_contact_attributes` nasce **desligada**
  (`AssistantBasicSettingsForm.vue:63`: `config.feature_contact_attributes || false`).
  `[INFERÊNCIA]` Isso é bom para o contato — e torna ainda mais anômalo que a conversa
  não tenha controle nenhum.

**A assimetria que importa, dita com precisão:** o Intercom permite travar atributo por
atributo contra escrita vinda do Messenger. No ChatSPX, `[MEDIDO]` não existe nenhum campo
no modelo `CustomAttributeDefinition` (`custom_attribute_definition.rb`, schema nos
comentários do topo) que expresse "este atributo não pode ser escrito pelo widget" — as
colunas são `attribute_description`, `attribute_display_name`, `attribute_display_type`,
`attribute_key`, `attribute_model`, `attribute_values`, `default_value`, `regex_cue`,
`regex_pattern`. Não há coluna de origem, confiança ou visibilidade.

### C.3.4 Vazamento de PII pelo Dashboard App

`[MEDIDO]` `DashboardApp/Frame.vue:33-39` envia o objeto de conversa **inteiro** e o contato
**inteiro** para o iframe de terceiro. Não há seleção de campos nem consentimento por campo.
`[INFERÊNCIA]` Um Dashboard App instalado para mostrar rastreio de entrega recebe também
e-mail, telefone, todos os custom attributes, IP e histórico da conversa. O Zendesk resolve
isso invertendo o fluxo (o app **pede** o que precisa via `client.get()`); o Intercom
resolve entregando payload delimitado e assinado.

---

# PARTE D — O nosso estado (leitura de código, sem executar)

> **Método e limite.** Tudo nesta parte vem de leitura do código-fonte em
> `/home/chatwoot/chatwoot`, branch `homologacao`, em 12/08/2026. Eu **não** abri o painel
> logado. Onde eu digo "o agente vê", leia como "o código renderiza" — a inferência do que
> aparece na tela está marcada como tal. Validação em navegador real com conta de teste
> fica como pendência explícita.

## D.1 Onde o contexto mora

| Camada | Coluna | Escrito por | Marcador |
|---|---|---|---|
| Contato | `additional_attributes` (jsonb) | Backend: `created_at_ip`, `city`, `country`, `country_code`, `company_name` | `[MEDIDO]` |
| Contato | `custom_attributes` (jsonb) | SDK `setCustomAttributes`, API, agente, Copilot | `[MEDIDO]` |
| Conversa | `additional_attributes` (jsonb) | Backend na criação: `browser_language`, `browser{...}`, `initiated_at`, `referer` | `[MEDIDO]` |
| Conversa | `custom_attributes` (jsonb) | SDK `setConversationCustomAttributes`, API, agente, IA | `[MEDIDO]` |
| Conta | `custom_attribute_definitions` | Admin, em Configurações | `[MEDIDO]` |

**Tipagem:** `[MEDIDO]` 8 tipos (`custom_attribute_definition.rb:47`), mais `regex_pattern`
e `regex_cue` para validação (linhas 27-31 do schema). **Chaves reservadas:** `[MEDIDO]`
`STANDARD_ATTRIBUTES` (linhas 22-26) impede colidir com `status`, `priority`, `assignee_id`,
`inbox_id`, `team_id`, `display_id`, `campaign_id`, `labels`, `browser_language`,
`country_code`, `referer`, `created_at`, `last_activity_at` (conversa) e `name`, `email`,
`phone_number`, `identifier`, `country_code`, `city`, `created_at`, `last_activity_at`,
`referer`, `blocked` (contato).

`[INFERÊNCIA]` A tipagem e o regex existentes são bons — comparáveis ao Intercom em
quantidade de formatos. O problema não é a modelagem da definição; é que **nada obriga o
dado a passar por ela**.

## D.2 O que o painel renderiza — inventário honesto

**Ordem padrão dos blocos** `[MEDIDO]` (`useUISettings.js:4-17`):
`conversation_media` → `group_participants` → `conversation_actions` → `kanban_status` →
`macros` → **`conversation_info`** → **`contact_attributes`** → `contact_notes` →
`previous_conversation` → `conversation_participants` → `linear_issues` → `shopify_orders`.

**Estado inicial dos accordions** `[MEDIDO]` (`useUISettings.js:172`):
`isContactSidebarItemOpen: key => !!uiSettings.value[key]` — chave ausente ⇒ `false`.
Exceções que abrem por padrão: **Mídias e Arquivos** e **Integrantes**, que usam
`!== false` (`ContactPanel.vue:58-60` e `116-118`).

`[INFERÊNCIA]` Logo: **"Informações da conversa" e "Atributos do contato" nascem fechados**,
na 6ª e 7ª posição. O contexto do site está, na tela, atrás de rolagem **e** de um clique.

**Fixo no topo, sempre visível** `[MEDIDO]` (`ContactPanel.vue:177-179`, `ContactInfo.vue:347-366`):
avatar, nome, e-mail, telefone, `identifier`, `company_name` (de `additional_attributes`),
localização — seguidos de `ConversationSummary` (só com `FEATURE_FLAGS.CAPTAIN_V2` ligada,
`ConversationSummary.vue:22,84`) e `ConversationChecklist`.

**Dentro de "Informações da conversa"** `[MEDIDO]` (`ConversationInfo.vue:45-84`) — e cada
linha só aparece se tiver valor (`.filter(attribute => !!attribute.content.value)`, linha 83):

| Rótulo | Origem | Observação |
|---|---|---|
| Iniciado em | `additional_attributes.initiated_at.timestamp` | |
| Idioma do navegador | `additional_attributes.browser_language` | traduzido por `getLanguageName` |
| Iniciado a partir de | `additional_attributes.referer` | **link clicável** (linhas 101-109) |
| Navegador | `browser.browser_name + browser_version` | |
| SO | `browser.platform_name + platform_version` | |
| Endereço IP | `contact.additional_attributes.created_at_ip` | **IP bruto, sem máscara** |

`[INFERÊNCIA]` São **seis** linhas de contexto automático. Um agente de e-commerce, ao abrir
uma conversa do site, aprende: em que navegador a pessoa está, em que SO, em que idioma, de
que URL, quando começou, e o IP. **Nada sobre o que ela estava comprando.**

## D.3 O gap estrutural: o painel só mostra o que foi cadastrado antes

Este é o achado que mais impacta o redesenho.

`[MEDIDO]` `customAttributes/CustomAttributes.vue:76-89`:

```
const filteredCustomAttributes = computed(() =>
  attributes.value.map(attribute => {
    const hasValue = attribute.attribute_key in customAttributes.value;
    ...
```

A iteração é sobre `attributes` — as **definições cadastradas**
(`getters['attributes/getAttributesByModel']`, linhas 47-49) — e **não** sobre os valores
efetivamente gravados em `custom_attributes`.

`[INFERÊNCIA]` Consequência exata: um atributo enviado pelo site via
`setCustomAttributes({ carrinho_valor: 4200 })`, sem definição prévia cadastrada por um
admin, é **gravado no banco**, é **injetado no prompt do Captain**, e é **invisível no
painel**. Não há aviso, não há estado vazio explicando, não há "N atributos não mapeados".
Ele simplesmente não existe para o atendente.

`[MEDIDO]` O mesmo vale para **filtro**: `custom_attribute_filter_helper.rb:40-46` faz
`find_by(attribute_key:)` nas definições e, se não achar, `attribute_data_type` fica nulo e
`custom_attribute_query` retorna string vazia (linha 6). Sem definição, **não dá para
filtrar**.

`[MEDIDO]` E para **relatório**: `grep custom_attributes` em `app/services/reports/` e
`enterprise/app/services/reports/` retorna vazio. Atributos **não entram em relatório**.

`[MEDIDO]` E para **export CSV** de contatos: `contacts_export_job.rb:41` faz
`(column_names.presence || default_columns) & Contact.column_names` — só colunas reais da
tabela; default é `id, name, email, phone_number` (linha 65). `[INFERÊNCIA]` Na melhor
hipótese sai o jsonb inteiro despejado numa célula; não há seleção de chave individual.

**Contraste com o Intercom:** lá, o dado detectado *"flows into Intercom reports for deep
insight — no manual tagging required"* `[FATO]`
([intercom.com/help/11680403](https://www.intercom.com/help/en/articles/11680403-how-to-create-fin-attributes)).

**Efeito colateral menos óbvio, também medido:** `[MEDIDO]` `CustomAttributes.vue:123-130`
exibe apenas os **5 primeiros** elementos combinados; o resto fica atrás de "Mostrar mais".
E `[MEDIDO]` linha 260 — `:disabled="!showAllAttributes"` — a reordenação por arraste **só
funciona depois de expandir**. `[INFERÊNCIA]` Como as 6 linhas estáticas de navegador/SO/IP
entram na **mesma** lista combinada que os atributos de negócio (`combinedElements`, linhas
96-121), o corte em 5 tende a ser consumido por elas: o `carrinho_valor` fica atrás do
"Mostrar mais", abaixo do IP.

## D.4 Os dez gaps, consolidados

| # | Gap | Evidência | Impacto |
|---|---|---|---|
| 1 | Atributo sem definição prévia é invisível no painel | `CustomAttributes.vue:77` | **Crítico** — integração "funciona" e não aparece |
| 2 | Contexto do site nasce fechado, na 6ª posição | `useUISettings.js:4-17,172` | **Alto** |
| 3 | Sem histórico de páginas visitadas (mesmo coletando) | `db/schema.rb`; `DOMHelpers.js:49-74` | **Alto** |
| 4 | `referer` é a URL do momento do envio, não a landing | `base_controller.rb:42`; `App.vue:282` | **Alto** — perde atribuição |
| 5 | Atributos não entram em relatório | `grep` em `services/reports/` | **Alto** |
| 6 | Nenhum controle de "não escrever pelo widget" | `custom_attribute_definition.rb` (sem coluna) | **Crítico (segurança)** |
| 7 | Contexto vai cru para o prompt, sem delimitador | `conversation.liquid:9-18`; `agentable.rb:23` | **Crítico (segurança)** |
| 8 | Dashboard App esconde a conversa | `ConversationBox.vue:157-180` | **Alto (UX)** |
| 9 | Dashboard App recebe tudo, sem assinatura | `Frame.vue:33-39,79-91` | **Médio-alto (privacidade)** |
| 10 | IP bruto exibido; sem política de expurgo de visitante | `ConversationInfo.vue:43,78-81` | **Médio (LGPD)** |

---

# O QUE FALTA NO CHATSPX

Recomendações. Sem código de implementação — é decisão de produto, não de sprint.

## 1. Fechar o buraco número um: atributo sem definição não pode sumir

**O problema, em uma frase:** hoje um cliente integra o site, os dados chegam, o painel não
muda, e a conclusão dele é "não funcionou".

**Três caminhos, em ordem de preferência:**

- **(a) Auto-provisionar a definição.** Chave nova chegando pelo widget cria automaticamente
  uma `CustomAttributeDefinition` do tipo `text`, marcada como **não confiável** (ver item 3),
  com display name derivado da chave. O admin depois refina tipo e rótulo. É o que torna a
  integração "funciona de primeira".
- **(b) Renderizar os órfãos numa seção separada.** Um bloco "Dados recebidos do site (N)",
  visualmente distinto dos atributos curados, listando o que veio sem definição.
- **(c) No mínimo, avisar.** Um contador discreto: "3 atributos recebidos não estão
  configurados — configurar".

`[INFERÊNCIA]` (a) e (b) juntos são o desenho certo: provisiona, e separa visualmente o
curado do cru. (c) sozinho é remendo.

## 2. Redesenhar a hierarquia do painel em torno de "por que esta pessoa está falando comigo"

O que o redesenho deveria inverter:

- **Contexto de negócio antes de contexto técnico.** `carrinho_valor` e `produto_atual` no
  topo; navegador e SO num bloco "Técnico", recolhido. O agente precisa de navegador/SO em
  uma conversa em cada vinte — e hoje eles ocupam a cota de 5 itens visíveis.
- **Um bloco de contexto do site aberto por padrão**, com no máximo 3-4 campos priorizados,
  seguindo o critério do item A.0 ("muda a primeira frase?").
- **Separar visualmente por origem**: verificado (backend/JWT) vs recebido do site vs
  preenchido pela IA vs digitado pelo agente. O Crisp já usa barra colorida à esquerda da
  chave (`shots/crisp-custom-data-doc-img2.png`); é um padrão barato e legível.
- **Não misturar as linhas estáticas técnicas com os atributos de negócio na mesma lista
  cortada em 5.** Hoje elas competem pela mesma cota.

## 3. Trazer o equivalente ao "Require verified updates"

A `CustomAttributeDefinition` precisa de um conceito de **origem confiável**. Mínimo viável:
um campo que diga se aquele atributo pode ou não ser escrito pelo widget, e o backend
ignorando silenciosamente as escritas bloqueadas — exatamente o comportamento documentado
pelo Intercom (*"The data is ignored"*).

Complementos que andam junto:
- **Teto de quantidade de chaves** por conversa/contato vindas do widget (hoje só há teto de
  1500 caracteres por chave, e nenhum no contato).
- **Estender ao contato** a validação de comprimento que hoje só existe na conversa.
- **Avaliar JWT** no lugar do HMAC atual para identificação — é a direção declarada do
  Intercom, com o HMAC legado em modo de manutenção.

## 4. Tratar o contexto no prompt como conteúdo não confiável

Alinhado ao OWASP LLM01. Três mudanças de desenho, em ordem de retorno:

1. **Allowlist**: só atributos com definição cadastrada **e** marcados como aptos a ir para a
   IA entram no prompt. Hoje vai tudo.
2. **Delimitação explícita**: o bloco de atributos precisa estar demarcado como dado, não
   como instrução, com aviso ao modelo de que ali não há comandos.
3. **Simetria com o contato**: a conversa precisa de um gate equivalente ao
   `feature_contact_attributes`. Hoje o contato é protegido e a conversa não — e a conversa
   é justamente a que o site escreve com mais liberdade.

`[INFERÊNCIA]` (1) e (2) resolvem a maior parte do risco com custo baixo. Dual-LLM é a
resposta estrutural, mas é desproporcional para o estágio atual.

## 5. Persistir o que já coletamos: páginas visitadas

A instrumentação existe e funciona (`DOMHelpers.js:49-74`). Falta armazenar.

Recomendação `[INFERÊNCIA]`: copiar o modelo **agregado** do Intercom (primeira vez, última
vez, contagem) em vez de log completo — barato e suficiente. Guardar as **últimas ~20**
páginas da sessão (mesmo número do app do Intercom) e, separadamente, a **landing page real**
com os UTMs. Isso conserta o gap 4: hoje a origem de campanha se perde se a pessoa navegar
antes de abrir o chat.

## 6. Fazer a IA produzir atributo estruturado, não só consumir texto

A inversão descrita em C.2. Concretamente:

- Um conjunto pequeno de atributos **preenchidos pela IA** com **enum fechado** — no espírito
  do Fin Attributes (tipo de assunto, sentimento, urgência, spam). O ChatSPX já tem a via de
  escrita (`SetCustomAttributesService`); o que falta é **schema**: hoje o parâmetro é JSON
  livre em string, o que garante chaves inconsistentes entre conversas.
- Esses atributos precisam **valer para alguma coisa**: filtro, roteamento e relatório.
  Atributo que não entra em relatório é anotação, não dado.
- Provisionar as definições correspondentes junto com a feature — senão caem no gap 1 e a IA
  escreve para o vazio.

## 7. Repensar o Dashboard App: contexto ao lado, não no lugar da conversa

O modelo em aba resolve "abrir um sistema externo". Não resolve "dar contexto".

Recomendação `[INFERÊNCIA]`: um segundo formato — **card no painel lateral**, convivendo com
a conversa, no espírito do `ticket_sidebar` (Zendesk) e do Canvas Kit (Intercom). Manter a
aba para o caso "tela cheia". E, no card:

- **Enviar só o necessário** — hoje vai a conversa e o contato inteiros.
- **Assinar o payload** para o app poder verificar a origem (o Intercom usa HMAC-SHA256 em
  `X-Body-Signature`).
- **Validar `event.origin`** no listener de refetch (`Frame.vue:62-67`).

## 8. Publicar um catálogo de contexto por vertical

Menos código, mais produto. O que trava a adoção não é a API — é o cliente não saber o que
mandar. As tabelas da Parte A são o rascunho de um material de onboarding: para cada
vertical, os 5-8 campos que mudam o atendimento, de onde tirar, e o que **não** mandar.

`[INFERÊNCIA]` Um preset por vertical que já cria as definições tipadas (e-commerce, SaaS,
imobiliária, automotivo, educação, B2B) resolve simultaneamente o gap 1 e o problema de
"campo vazio no painel" que motivou esta task.

## 9. Encarar a decisão de PII de frente

Três pontos concretos, na ordem em que eu resolveria:

1. **IP.** O Intercom decidiu não expor. Nós expomos bruto para qualquer agente. Se o IP tem
   uso real (antifraude), ele pertence a um perfil restrito — não à visão padrão. Mascarar
   por padrão é a opção conservadora e barata.
2. **Expurgo de visitante.** Não encontrei política equivalente aos 9 meses do Intercom.
   Visitante que nunca voltou acumulando IP, navegador e atributos indefinidamente é
   exposição sem contrapartida.
3. **Verticais que coletam documento.** Automotivo (CPF, RENAVAM) e educação (menor de idade)
   são os casos onde o padrão do setor colide com a LGPD. O produto deveria **dificultar** a
   coisa errada: tipo de atributo que mascara na exibição, e recusa explícita a aceitar
   padrões de cartão em campo de texto livre. O Zendesk oferece um tipo `credit card` nativo
   exatamente por isso.

---

## Pendências e limites deste relatório

Registrados como buracos, não disfarçados:

1. **Não executei o painel do ChatSPX logado.** Todo o inventário da Parte D é leitura de
   código. Validar em navegador real (light e dark) com conta de teste fica pendente.
2. **Larguras de painel** de Intercom, HubSpot, Gorgias e Crisp: `[NÃO VERIFICADO]` — não há
   número em doc pública e não tenho acesso aos produtos.
3. **Contradição Fin × custom attributes** (C.2): registrei as duas versões e fiquei com a
   fonte primária. Não arbitrei por teste.
4. **Profundidade da timeline** de Crisp, HubSpot e Gorgias: `[NÃO VERIFICADO]`.
5. **Recent page views para visitors anônimos** (Intercom): a doc fala em users e leads;
   sobre anônimos, `[NÃO VERIFICADO]`.
6. **Limite total de custom fields por conta no Zendesk**: `[NÃO VERIFICADO]`.
7. **A cadeia de prompt injection (C.3.3) não foi executada** — cada elo é medido, a
   conclusão de ponta a ponta é inferência. Confirmar em ambiente isolado, nunca em produção.

---

## Screenshots

Todos em `plano/estudo-chat-web/integracao/shots/`, capturados nesta sessão via Playwright
(Chromium headless, viewport 1440×900):

| Arquivo | Conteúdo |
|---|---|
| `intercom-cvda-doc.png` | Doc de Conversation Data Attributes |
| `intercom-cvda-doc-img2.png` | **Dropdown com os 8 formatos de atributo do Intercom** |
| `intercom-cvda-doc-img1/3/4.png` | Telas de criação e uso de CvDA |
| `intercom-canvas-kit-doc.png` | Doc do Canvas Kit |
| `zendesk-ticket-sidebar-doc.png` | Doc da location `ticket_sidebar` |
| `crisp-custom-data-doc-img1.png` | **Perfil do contato no Crisp** — "Data for Antoine 23" + mapa |
| `crisp-custom-data-doc-img2.png` | **Painel lateral do Crisp dentro da conversa** — widget "Visitor data" |
| `crisp-custom-data-doc-img3.png` | Configuração de custom data |
| `chatwoot-dashboard-apps-doc-img3.png` | **Dashboard App como aba que esconde a conversa** |
| `chatwoot-dashboard-apps-doc-img1/2/4.png` | Configuração de Dashboard Apps |
| `hubspot-inbox-doc.png` | Doc do conversations inbox |
| `gorgias-shopify-doc.png` | Página da integração Gorgias × Shopify |

---

## Fontes

**Intercom**
- [Create and use conversation data attributes (CvDAs)](https://www.intercom.com/help/en/articles/6546210-create-and-use-conversation-data-attributes-cvdas-in-the-inbox)
- [Tracking user data in Intercom](https://www.intercom.com/help/en/articles/320-tracking-user-data-in-intercom)
- [How Intercom tracks and stores data](https://www.intercom.com/help/en/articles/1722980-how-intercom-tracks-and-stores-data)
- [Recent page views app](https://www.intercom.com/help/en/articles/9277565-recent-page-views-app)
- [Record customer activity with event tracking](https://www.intercom.com/help/en/articles/216-record-customer-activity-with-event-tracking)
- [How to create Fin Attributes](https://www.intercom.com/help/en/articles/11680403-how-to-create-fin-attributes)
- [Fin as a Customer Agent](https://www.intercom.com/help/en/articles/12508017-fin-as-a-customer-agent-for-service-sales-and-more)
- [Best practices when using Data connectors with Fin](https://www.intercom.com/help/en/articles/9916183-best-practices-when-using-data-connectors-with-fin)
- [Securing the data you send via the Messenger](https://www.intercom.com/help/en/articles/11087109-securing-the-data-you-send-via-the-messenger)
- [Migrating from Identity Verification to Messenger Security with JWTs](https://www.intercom.com/help/en/articles/10807823-migrating-from-identity-verification-to-messenger-security-with-jwts)
- [Canvas Kit](https://developers.intercom.com/docs/canvas-kit)
- [JavaScript API: Attributes & Objects](https://developers.intercom.com/installing-intercom/web/attributes-objects)
- [How Intercom ensures data privacy and safety in the age of AI](https://www.intercom.com/blog/data-privacy-security-ai-chatbots/)

**Zendesk**
- [Ticket and New Ticket sidebar](https://developer.zendesk.com/api-reference/apps/apps-support-api/ticket_sidebar/)
- [About custom fields and custom field types](https://support.zendesk.com/hc/en-us/articles/4408838961562-About-custom-fields-and-custom-field-types)
- [Adding custom fields to users](https://support.zendesk.com/hc/en-us/articles/4408822051866-Adding-custom-fields-to-users)
- [Automatically detecting sensitive information for redaction (ADPP)](https://support.zendesk.com/hc/en-us/articles/6669399593882-Automatically-detecting-sensitive-information-for-redaction-ADPP-add-on)

**Crisp**
- [Getting started with Custom Datas](https://help.crisp.chat/en/article/what-is-custom-data-and-why-is-it-powerful-43jgi3/)
- [Getting started with the Crisp Inbox](https://help.crisp.chat/en/article/getting-started-with-the-crisp-inbox-opv83/)
- [$crisp Methods — Web Chat SDK](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/dollar-crisp/)

**HubSpot / Gorgias / Shopify**
- [A guide to the conversations inbox](https://knowledge.hubspot.com/inbox/use-the-conversations-inbox)
- [The Gorgias & Shopify Integration](https://www.gorgias.com/blog/gorgias-shopify-integration)
- [Gorgias for Shopify (análise eesel AI)](https://www.eesel.ai/blog/gorgias-shopify)
- [Attach Gorgias tracking data to Shopify Cart and Checkout attributes](https://developers.gorgias.com/docs/how-to-attach-gorgias-tracking-data-to-shopify-cart-and-checkout-attributes)
- [Shopify Attributes API](https://shopify.dev/docs/api/checkout-ui-extensions/2026-07-rc/target-apis/checkout-apis/attributes-api)

**Chatwoot (upstream)**
- [How to use Dashboard Apps?](https://www.chatwoot.com/hc/user-guide/articles/1677691702-how-to-use-dashboard-apps)

**Segurança de IA**
- [OWASP Top 10 for LLM Applications 2025 (PDF)](https://owasp.org/www-project-top-10-for-large-language-model-applications/assets/PDF/OWASP-Top-10-for-LLMs-v2025.pdf)
- [OWASP Top 10 LLM 2025 — exemplos e mitigações (Oligo)](https://www.oligo.security/academy/owasp-top-10-llm-updated-2025-examples-and-mitigation-strategies)
- [OWASP Top 10 LLM Risks Explained (Aembit)](https://aembit.io/blog/owasp-top-10-llm-risks-explained/)
- [Indirect Prompt Injection (Lakera)](https://www.lakera.ai/blog/indirect-prompt-injection)
- [How prompt injection puts your brand and AI workflows at risk (Search Engine Land)](https://searchengineland.com/prompt-injection-brand-ai-workflows-risk-483819)
- [Designing agents to resist prompt injection (OpenAI)](https://openai.com/index/designing-agents-to-resist-prompt-injection/)

**Verticais Brasil**
- [Chatbot com IA no WhatsApp para imobiliária qualificar lead](https://blog.aleffpepper.com/posts/2026-04-08-chatbot-whatsapp-imobiliaria-qualificar-lead/)
- [Chatbot Imobiliário: integração com CRM (CV CRM)](https://cvcrm.com.br/blog/chatbot-imobiliario/)
- [Chatbot IA para Concessionária de Veículos em 2026 (SocialHub)](https://www.socialhub.pro/blog/chatbot-ia-whatsapp-concessionaria-veiculos/)
- [CRM para Concessionárias (Chatclipy)](https://chatclipy.com.br/crm-para-concessionarias-venda-mais-veiculos-com-whatsapp-e-ia/)
- [Arquitetura e uso de chatbots para instituições de ensino (Lyceum)](https://blog.lyceum.com.br/chatbot-para-instituicao-de-ensino/)
- [Jornada do aluno no WhatsApp (OmniChat)](https://omni.chat/blog/jornada-do-aluno-no-whatsapp/)

**LGPD**
- [O consentimento previsto na LGPD (ConJur / Arpen-SP)](https://www.arpensp.org.br/noticia/97288)
- [Consentimento digital: o que a LGPD realmente exige (Data Guide)](https://dataguide.com.br/consentimento-digital-shoppings-incorporadoras/)
- [Cookies e Banners de Consentimento: LGPD e ANPD em 2026 (LegalSuite)](https://legalsuite.com.br/blog/digital-cookies-banner-lgpd-2026)

**SaaS / boas práticas**
- [Live Chat for SaaS: The Complete Guide (Gleap)](https://www.gleap.io/blog/live-chat-saas-guide)
- [SaaS Customer Support: What It Is & Best Practices (Pylon)](https://www.usepylon.com/blog/saas-customer-support-what-it-is-best-practices)

**Código-fonte do ChatSPX** (branch `homologacao`, 12/08/2026) — arquivos citados com linha
ao longo do documento: `app/javascript/entrypoints/sdk.js`, `app/javascript/sdk/DOMHelpers.js`,
`app/javascript/widget/App.vue`, `app/javascript/widget/api/endPoints.js`,
`app/controllers/api/v1/widget/base_controller.rb`,
`app/controllers/api/v1/widget/conversations_controller.rb`,
`app/controllers/api/v1/widget/contacts_controller.rb`,
`app/controllers/concerns/website_token_helper.rb`,
`app/models/custom_attribute_definition.rb`, `app/models/conversation.rb`,
`app/models/contact.rb`, `app/models/jsonb_attributes_length_validator.rb`,
`app/models/channel/web_widget.rb`, `app/services/filters/custom_attribute_filter_helper.rb`,
`app/jobs/account/contacts_export_job.rb`,
`app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`,
`app/javascript/dashboard/routes/dashboard/conversation/ConversationInfo.vue`,
`app/javascript/dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue`,
`app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`,
`app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue`,
`app/javascript/dashboard/components/widgets/conversation/ConversationBox.vue`,
`app/javascript/dashboard/components/widgets/DashboardApp/Frame.vue`,
`app/javascript/dashboard/composables/useUISettings.js`,
`enterprise/lib/captain/prompts/runtime_context.liquid`,
`enterprise/lib/captain/prompts/snippets/conversation.liquid`,
`enterprise/lib/captain/prompts/snippets/contact.liquid`,
`enterprise/app/models/concerns/agentable.rb`,
`enterprise/app/services/captain/llm/assistant_chat_service.rb`,
`enterprise/app/services/captain/tools/copilot/set_custom_attributes_service.rb`,
`enterprise/lib/captain/tools/enviar_fotos_imovel_tool.rb`, `db/schema.rb`.
