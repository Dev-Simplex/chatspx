# TASK 06 — UX, Padrões de Interface e Conversão em Chat de Site

> **Fase:** estudo puro. Nenhuma implementação, nenhum código alterado.
> **Data da pesquisa:** 11 de agosto de 2026.
> **Escopo:** catalogar os padrões de UX/UI de *web chat widget* praticados pelo mercado
> (Brasil e global, com a **Leadster** como referência principal) e reunir a evidência
> pública sobre conversão, separando estudo independente de material de venda de fornecedor.
> **Destino:** guiar o redesenho visual e comportamental do widget web do ChatSPX.

---

## SUMÁRIO

- [0. Método, escopo e convenções de leitura](#0-método-escopo-e-convenções-de-leitura)
- [1. Anatomia do widget](#1-anatomia-do-widget)
  - [1.1 Launcher / bolha](#11-launcher--bolha)
  - [1.2 Estados do widget](#12-estados-do-widget)
  - [1.3 Header](#13-header)
  - [1.4 Corpo / lista de mensagens](#14-corpo--lista-de-mensagens)
  - [1.5 Composer](#15-composer)
  - [1.6 Rodapé e branding](#16-rodapé-e-branding)
  - [1.7 Tabela comparativa de medidas](#17-tabela-comparativa-de-medidas-reais)
- [2. Mensagem proativa, teaser e nudge](#2-mensagem-proativa-teaser-e-nudge)
- [3. Formulário conversacional vs formulário estático](#3-formulário-conversacional-vs-formulário-estático)
- [4. Componentes de mensagem](#4-componentes-de-mensagem)
- [5. Sinais de vida](#5-sinais-de-vida)
- [6. Bot → humano (handoff)](#6-bot--humano-handoff)
- [7. Dark mode, temas, branding e customização](#7-dark-mode-temas-branding-e-customização)
- [8. Acessibilidade percebida e mobile-first](#8-acessibilidade-percebida-e-mobile-first)
- [9. Anti-padrões e reclamações reais](#9-anti-padrões-e-reclamações-reais)
- [10. Evidência de conversão](#10-evidência-de-conversão)
- [11. Copy e tom](#11-copy-e-tom)
- [12. LGPD e consentimento na UX](#12-lgpd-e-consentimento-na-ux)
- [13. Observação de campo — quem usa o quê](#13-observação-de-campo--quem-usa-o-quê)
- [14. IMPLICAÇÕES PARA O CHATSPX](#14-implicações-para-o-chatspx)
- [15. Lacunas de pesquisa e o que não foi possível verificar](#15-lacunas-de-pesquisa-e-o-que-não-foi-possível-verificar)
- [16. Fontes](#16-fontes)

---

## 0. Método, escopo e convenções de leitura

### 0.1 O que foi feito

1. **Pesquisa web** sobre padrões de UX de chat, benchmarks de conversão, acessibilidade,
   LGPD e reclamações de usuário final.
2. **Leitura de documentação primária de fornecedores** (Intercom, Zendesk / Sunshine
   Conversations, Crisp, Leadster) — sempre que possível a página oficial, não o resumo de
   terceiro.
3. **Inspeção de assets públicos** via `curl`: download do loader do Crisp
   (`https://client.crisp.chat/l.js`), do shim do Intercom (`https://widget.intercom.io/widget/…`)
   e varredura de HTML servido de ~30 sites brasileiros e globais para identificar qual
   widget cada um usa.
4. **Leitura do código-fonte do widget do próprio ChatSPX/Chatwoot** (`app/javascript/sdk/`
   e `app/javascript/widget/`) — apenas leitura, nenhum arquivo alterado — para permitir a
   comparação ponto a ponto na seção 14.

### 0.2 Convenções de marcação

Todo bloco relevante é marcado com uma destas etiquetas:

| Etiqueta | Significado |
|---|---|
| **[FATO VERIFICADO]** | Fui à fonte primária e li o dado. URL sempre presente. |
| **[FATO — FORNECEDOR]** | Número real e publicado, mas por quem vende a solução. Enviesado por construção. |
| **[FATO — AGREGADOR]** | Número que circula em posts de "N estatísticas de live chat". Frequentemente sem metodologia rastreável. Baixa confiança. |
| **[INFERÊNCIA]** | Conclusão minha a partir das evidências. Não é fato. |
| **[NÃO VERIFICADO]** | Procurei e não consegui confirmar. Registrado para não virar mito. |

### 0.3 Aviso metodológico importante sobre a seção 10

A literatura de "estatísticas de live chat" é **dominada por marketing**. A maior parte dos
números que circula ("live chat aumenta conversão em X%") vem de blogs de fornecedores que
citam outros blogs de fornecedores, num ciclo sem estudo original rastreável. Na seção 10
eu classifico cada número por **nível de confiança** e digo explicitamente quando a
metodologia não está publicada. **Não use nenhum número marcado como AGREGADOR para
justificar decisão de produto sem replicar o teste internamente.**

---

## 1. Anatomia do widget

O widget de chat de site consolidou-se num vocabulário visual muito estável nos últimos
~10 anos. As peças são sempre as mesmas; o que varia são medidas, raios de canto e quanto
de "app" cada fornecedor coloca dentro da janela.

```
                                   ┌─────────────────────────┐
                                   │  HEADER                 │ ← avatar(es), nome, status,
                                   │  ◄ [av][av] Empresa  ✕  │   tempo de resposta, ações
                                   ├─────────────────────────┤
                                   │                         │
                                   │  ┌────────────────┐     │
                                   │  │ msg do agente  │     │ ← CORPO / lista de mensagens
                                   │  └────────────────┘     │   (scroll, ancorado embaixo)
                                   │     ┌──────────────┐    │
                                   │     │ msg do user  │    │
                                   │     └──────────────┘    │
                                   │  [ Quick reply 1 ]      │
                                   │  [ Quick reply 2 ]      │
                                   │  ●●● digitando…         │ ← sinal de vida
                                   ├─────────────────────────┤
                                   │ 😊 📎 Digite…      ➤   │ ← COMPOSER
                                   ├─────────────────────────┤
                                   │  Desenvolvido por X     │ ← RODAPÉ / branding
                                   └─────────────────────────┘
                                                       ┌────┐
                                                       │ 💬 │ ← LAUNCHER / bolha
                                                       └────┘
```

### 1.1 Launcher / bolha

**[FATO VERIFICADO]** Medidas reais extraídas do CSS do SDK do Chatwoot/ChatSPX
(`app/javascript/sdk/sdk.js`, lido em 11/08/2026):

| Propriedade | Valor no ChatSPX hoje |
|---|---|
| Diâmetro (padrão) | `64px × 64px` |
| Diâmetro (variante `--flat`) | `56px × 56px` |
| `border-radius` (padrão) | `100px` (círculo perfeito) |
| `border-radius` (variante `--flat`) | `0` (quadrado) |
| Offset inferior | `bottom: 20px` |
| Offset lateral | `right: 20px` (ou `left: 20px` na variante `woot-elements--left`) |
| Ícone SVG interno | `24px × 24px`, `margin: 20px` |
| Sombra | `0 8px 24px rgba(0,0,0,.16)`; no hover vai a `0 8px 32px rgba(0,0,0,.4)` |
| Cor padrão | `#2dc46f` |
| `z-index` | `2147483000` |
| Contador de não lidas | pseudo-elemento `::after` de `12px × 12px`, `background:#ff4040`, `border-radius:100%`, `top:0; right:0`, borda branca de `2px` |
| Variante "expandida" (bolha com texto) | `height: 48px !important; width: auto`, texto `16px/500`, `padding-right: 20px`, ícone `20px` com `margin: 14px 8px 14px 16px`, `bottom: 24px` |
| Transição de abertura | `transform 300ms ease, opacity 100ms ease`; ao esconder, `translateX(8px) scale(.75) rotate(-30deg)` |

**[FATO VERIFICADO]** O launcher do ChatSPX é um `<button>` real (`chatBubble = document.createElement('button')`),
com `title = 'Open chat window'`, e ao fechar o widget o foco volta para ele
(`chatBubble.focus()` em `bubbleHelpers.js`). Isso é um acerto de acessibilidade que muitos
concorrentes não têm.

**[FATO VERIFICADO]** A Intercom **não permite** alterar o tamanho do launcher padrão nem o
tamanho da janela do Messenger; quem quiser outro tamanho precisa construir um *custom
launcher* e usar `custom_launcher_selector`. O que é configurável oficialmente é
`alignment` (`left`/`right`), `horizontal_padding`, `vertical_padding`, `z_index` e
`messenger_style_id`.
Fonte: <https://developers.intercom.com/installing-intercom/web/customization> e
<https://www.intercom.com/help/en/articles/2894-create-a-custom-launcher>

**[FATO VERIFICADO]** A Intercom recomenda logo do launcher em **PNG/JPG/GIF quadrado de
72×72px** com fundo transparente, e imagem de header de **800×600px**.
Fonte: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>

**[FATO VERIFICADO]** O Zendesk Web Widget (Classic) **não permite** customizar forma nem
tamanho; só posição via `offset`.
Fonte: <https://support.zendesk.com/hc/en-us/articles/4408819992090-How-do-I-change-the-shape-and-size-of-the-Chat-Web-Widget-Classic>

**[FATO VERIFICADO]** O Sunshine Conversations (Zendesk) é a exceção: expõe
`displayStyle` (`button` ou `tab`), `buttonIconUrl`, `buttonWidth` e `buttonHeight`
como parâmetros de integração.
Fonte: <https://docs.smooch.io/guide/web-messenger/>

**[FATO VERIFICADO]** A Leadster expõe, na tela de design do assistente: título do
assistente, posição na tela (esquerda/direita), espaçamento em relação às bordas laterais,
avatar (galeria ou upload, incluindo ícone do WhatsApp), idioma, **tamanho da foto em três
variações (Padrão, Média, Reduzida)** e **posição da chamada (ao lado do avatar ou acima
dele)**.
Fonte: <https://help.leadster.com.br/article/38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente>

**Convergência observada — o "padrão de fato" do launcher:**

| Atributo | Valor dominante no mercado |
|---|---|
| Posição | Canto inferior direito |
| Diâmetro | 56–64px (dedo confortável; alvo de toque ≥ 44px do WCAG com folga) |
| Offset | 16–25px das duas bordas |
| Forma | Círculo (a variante quadrada existe mas é minoria) |
| Ícone | Balão de fala genérico; segunda opção é o logo da marca |
| Estado aberto | O ícone vira um "X" (rotação/cross-fade), não some |
| Badge de não lidas | Ponto vermelho no canto superior direito, com ou sem número |

**[FATO — AGREGADOR / BAIXA CONFIANÇA]** Circula a afirmação de que "89% dos widgets usam o
canto inferior direito" e que "posicionar em outro lugar reduz engajamento em 25–40%".
Fonte: <https://widget-chat.com/blog/chatbot-ui-design-best-practices/>. **Não há
metodologia publicada.** Trate o "89%" como folclore quantificado: a *direção* (inferior
direito é o padrão) é obviamente verdadeira e confirmável por observação; o *número* não é
verificável.

**[INFERÊNCIA]** O motivo do canto inferior direito não é estético: é que ali é o único
canto que (a) não colide com menu/logo/carrinho, (b) fica no alcance do polegar em mobile
direito, e (c) já é onde o usuário aprendeu a procurar. Mudar de canto custa aprendizado
e não compra nada. **Não invente aqui.**

**Colisões de canto — o problema real de 2026:** o canto inferior direito hoje disputa
espaço com banner de cookies (LGPD), botão flutuante de WhatsApp, botão "voltar ao topo",
selo de reCAPTCHA e o próprio widget. **[INFERÊNCIA]** Qualquer widget sério em 2026
precisa de: `verticalPadding`/`horizontalPadding` configuráveis, uma API para elevar o
launcher quando o banner de cookies aparece, e a capacidade de esconder o launcher
inteiramente (`hide_default_launcher`) delegando a abertura a um elemento do site.

### 1.2 Estados do widget

Catálogo dos estados que um widget de site precisa representar:

| Estado | Descrição | Como o mercado faz |
|---|---|---|
| **Fechado (idle)** | Só o launcher visível | Bolha circular, sem badge |
| **Fechado com não lidas** | Agente respondeu mas o painel está fechado | Badge numérico/ponto no launcher + (opcional) preview da mensagem em card flutuante |
| **Teaser / nudge** | Balão de texto ao lado da bolha, sem abrir o painel | Card com avatar + 1–2 linhas de copy + "X" próprio. Ver seção 2. |
| **Aberto** | Painel completo | Janela ancorada acima do launcher |
| **Minimizado** | Volta ao fechado, mantendo histórico | Padrão universal; o histórico persiste por cookie/localStorage |
| **Fullscreen mobile** | Painel ocupa 100% da viewport | Padrão universal abaixo de ~640–668px |
| **Expandido (desktop wide)** | Painel mais largo para conteúdo rico | Intercom passou a permitir expandir a largura do Messenger para respostas longas da Fin |
| **Offline / fora do horário** | Sem agente disponível | Formulário de recado + promessa de retorno. Ver seção 6. |
| **Erro de conexão** | Websocket caiu | Faixa/banner no topo do corpo |

**[FATO VERIFICADO]** O ChatSPX/Chatwoot já implementa um estado adicional interessante,
o **"unread view"** (`has-unread-view`): quando há mensagem não lida com o widget fechado,
o *holder* muda de forma (`border-radius: 0`, `min-height: 80px`, `bottom: 94px`, sem
sombra) e mostra a prévia da mensagem sobre o launcher, com botões "Ver novas mensagens"
e "Fechar" (chaves `UNREAD_VIEW.VIEW_MESSAGES_BUTTON` / `CLOSE_MESSAGES_BUTTON` no i18n).
Fonte: `app/javascript/sdk/sdk.js` e `app/javascript/widget/i18n/locale/pt_BR.json`.

**[FATO VERIFICADO]** A Intercom mudou o comportamento do Messenger para que o cliente
"entre direto na conversa", removendo passos extras para iniciar um chat novo, e
redesenhou os cards de resposta da Fin para deixar claro quem está atendendo (Fin, Workflow
ou humano) — mudança disponível para todos desde 27/01/2025.
Fonte: <https://www.intercom.com/changes/en/80878-new-ui-for-fin-answers-and-handover-to-teammates-in-the-messenger>

**[FATO VERIFICADO]** A Leadster tem dois estados de "sumiço" configuráveis:
**ocultação pós-conversão** (assistente fica invisível por 7 dias após conversão
confirmada) e **ocultação de leads desqualificados** (invisível por 7 dias para leads
descartados/incompletos). Também expõe **Fullscreen** (ocupação de tela inteira
sobrepondo conteúdo) e um **botão de reinício** para o usuário recomeçar a conversa.
Fonte: <https://help.leadster.com.br/article/38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente>

**[INFERÊNCIA]** O "esconder por 7 dias após converter" da Leadster é o detalhe de produto
mais subestimado do catálogo inteiro. É a diferença entre um widget que respeita o usuário
e um que continua vendendo para quem já comprou. Custa quase nada implementar (cookie +
regra) e elimina a reclamação nº 1 da seção 9 ("me perseguem pelo site todo").

### 1.3 Header

Composição típica, do mais comum ao menos comum:

1. **Avatar(es)** — um avatar do agente atual, ou uma pilha sobreposta de 2–3 avatares da
   equipe ("stacked avatars"). O ChatSPX já tem um componente `GroupedAvatars.vue` para isso.
2. **Nome** — nome da empresa (padrão) ou nome do atendente quando já há um designado.
3. **Linha de status** — "Estamos conectados" / "Normalmente responde em alguns minutos".
   **[FATO VERIFICADO]** O ChatSPX tem essa família de strings pronta em pt-BR:
   `TEAM_AVAILABILITY.ONLINE = "Estamos conectados"`, `OFFLINE = "Estamos ausentes no
   momento"`, `BACK_AS_SOON_AS_POSSIBLE = "Estaremos de volta em breve"`, e
   `REPLY_TIME.{IN_A_FEW_MINUTES, IN_A_FEW_HOURS, IN_A_DAY, BACK_IN_HOURS, BACK_IN_MINUTES,
   BACK_AT_TIME, BACK_ON_DAY, BACK_TOMORROW, BACK_IN_SOME_TIME}`.
4. **Ações** — fechar (✕), minimizar (–), voltar (‹), menu de overflow (⋯) com
   "solicitar transcrição por e-mail", "encerrar conversa", "iniciar nova conversa".
   **[FATO VERIFICADO]** O ChatSPX tem `EMAIL_TRANSCRIPT.BUTTON_TEXT = "Solicitar uma
   transcrição de conversa"`, `END_CONVERSATION = "Finalizar Conversa"` e
   `START_NEW_CONVERSATION = "Iniciar uma nova conversa"`.
5. **Fundo** — cor sólida, gradiente ou imagem.
   **[FATO VERIFICADO]** A Intercom aceita cor sólida, gradiente **ou imagem** no header,
   com efeito de fade opcional, cor de texto configurável e **logo separado para light e
   dark**. Fonte: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>

**[INFERÊNCIA]** O header é onde o widget "promete". Toda promessa quebrada aqui
(diz "responde em alguns minutos" e responde em 4 horas; mostra avatar de gente que não
existe) vira desconfiança. A recomendação é: **derive a string de tempo de resposta de
dados reais da inbox, não de um campo digitado pelo cliente.**

### 1.4 Corpo / lista de mensagens

Regras estruturais que se repetem em todos os fornecedores:

- **Ancoragem embaixo**: a lista rola até o fim; mensagem nova empurra para cima.
- **Assimetria esquerda/direita**: agente à esquerda, usuário à direita. Universal.
- **Agrupamento por autor**: mensagens consecutivas do mesmo autor colam, com só a última
  mostrando timestamp e "rabinho" da bolha.
- **Separadores de data**: "Hoje" / "Ontem" / data.
  **[FATO VERIFICADO]** O ChatSPX tem `TODAY = "Hoje"` e `YESTERDAY = "Ontem"`.
- **Largura máxima da bolha**: tipicamente 75–85% da largura do corpo.
- **Comprimento de linha**: **[FATO — AGREGADOR]** recomenda-se 50–65 caracteres por linha
  e no máximo 2–3 frases por bolha
  (<https://widget-chat.com/blog/chatbot-ui-design-best-practices/>). Isso bate com a
  tipografia clássica (45–75 caracteres), então a *direção* é sólida mesmo sem o estudo.
- **Botão de reenvio em falha**:
  **[FATO VERIFICADO]** o ChatSPX já tem `MESSAGE_BUBBLE.RETRY = "Enviar mensagem
  novamente"` e `ERROR_MESSAGE = "Não foi possível enviar, tente novamente"`.

### 1.5 Composer

| Elemento | Presença no mercado | Observação |
|---|---|---|
| Campo de texto multilinha com auto-grow | Universal | Enter envia, Shift+Enter quebra linha |
| Placeholder | Universal | **[FATO VERIFICADO]** ChatSPX: `CHAT_PLACEHOLDER = "Digite sua mensagem"` |
| Botão de envio | Universal | Ícone de avião/seta; desabilitado com campo vazio |
| Seletor de emoji | Muito comum | **[FATO VERIFICADO]** ChatSPX tem `EMOJI.PLACEHOLDER`, `NOT_FOUND` e `ARIA_LABEL = "Seletor de emoji"` |
| Anexo de arquivo | Comum | **[FATO VERIFICADO]** ChatSPX tem `FILE_SIZE_LIMIT` com interpolação de `{MAXIMUM_FILE_UPLOAD_SIZE}` |
| Gravação de áudio | Emergente | Comum em WhatsApp, raro em web chat |
| Responder-a (reply/quote) | Emergente | **[FATO VERIFICADO]** ChatSPX tem `FOOTER_REPLY_TO.REPLY_TO = "Respondendo a:"` e componentes `ReplyToChip.vue` / `FooterReplyTo.vue` |
| Bloqueio do composer durante fluxo de bot | Divergente | Ver discussão abaixo |

**Ponto de projeto controverso — travar ou não o composer durante um fluxo guiado:**

**[FATO VERIFICADO]** A pesquisa de campo diz que os dois extremos perdem.
Quem só oferece botão sofre com "usuários não usam bots como apps — eles querem conversar,
não clicar em botões" (<https://uxdesign.cc/honey-i-built-a-chatbot-but-no-one-will-click-on-my-buttons-b713290c0029>).
Quem só oferece campo livre sofre com o problema de descoberta do NN/g: sem sinal do que o
sistema faz, o usuário não sabe o que pedir.

**[FATO VERIFICADO — NN/g]** "Quando um chatbot abre com um vago 'Como posso ajudar?', os
usuários não têm nenhum sinal sobre o que o sistema consegue responder. Quando abre com
três consultas de exemplo nomeadas e limitadas ao seu domínio, o usuário consegue dizer em
cinco segundos se a ferramenta vai funcionar para ele."
Fonte: síntese da pesquisa do Nielsen Norman Group sobre chatbots
(<https://blog.experientia.com/nielsen-norman-group-on-the-user-experience-of-chatbots/>).

**[INFERÊNCIA — recomendação]** Padrão híbrido: **botões visíveis + campo livre sempre
habilitado.** Se o usuário digitar algo fora das opções, o bot reconhece por intenção ou
responde "não entendi, mas posso te levar para um humano". Nunca desabilite o campo.

### 1.6 Rodapé e branding

**[FATO VERIFICADO]** O ChatSPX tem `POWERED_BY = "Desenvolvido por Chatwoot"` — string de
marca do upstream que aparece no rodapé do widget quando o branding não é removido.

Padrões de mercado:
- **Branding removível em plano pago**: praticamente todos.
- **Link para política de privacidade**: comum no mercado brasileiro (seção 12).
- **Altura do rodapé**: geralmente 28–40px, tipografia 11–12px, opacidade reduzida.

### 1.7 Tabela comparativa de medidas reais

| Fornecedor | Launcher | Janela (desktop) | Mobile | Fonte |
|---|---|---|---|---|
| **ChatSPX / Chatwoot** | 64×64 (flat: 56×56), `bottom/right: 20px`, `radius: 100px` | `width: 400px`, `height: calc(90% - 64px - 20px)`, `max-height: 640px`, `min-height: 250px`, `bottom: 104px`, `radius: 16px` — acima de `min-width: 667px` | `≤ 667px`: `height:100%; width:100%; top:0; right:0` (fullscreen). Launcher some ao abrir (`bottom:60px; opacity:0; visibility:hidden`) | `app/javascript/sdk/sdk.js` (leitura direta) |
| **Crisp** | não exposto no loader | breakpoints internos observados no loader: `280`, `320`, `420` | idem | `https://client.crisp.chat/l.js` v4.9.2 (download direto) |
| **Intercom** | **não customizável**; logo 72×72px | **não customizável**; largura expansível para respostas da Fin | fullscreen | <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger> |
| **Zendesk Web Widget (Classic)** | **não customizável** | **não customizável**; só `offset` | fullscreen | <https://support.zendesk.com/hc/en-us/articles/4408819992090-How-do-I-change-the-shape-and-size-of-the-Chat-Web-Widget-Classic> |
| **Sunshine Conversations** | `buttonWidth` / `buttonHeight` configuráveis; `displayStyle: button\|tab` | não documentado | não documentado | <https://docs.smooch.io/guide/web-messenger/> |
| **Leadster** | avatar em 3 tamanhos (Padrão/Média/Reduzida); posição da chamada ao lado ou acima | não publicado em px | Fullscreen opcional | <https://help.leadster.com.br/article/38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente> |

**[FATO VERIFICADO — nota técnica]** O loader do Crisp (`l.js`, v4.9.2, baixado em
11/08/2026) contém, além dos breakpoints `280/320/420`, uma lista de **user agents
explicitamente ignorados**: `Trident`, `Googlebot`, `Bingbot`, `Slurp`, `DuckDuckBot`,
`Baiduspider`, `YandexBot`, `GTmetrix`, **`Lighthouse`**, `Acunetix`, `Ahrefs`,
`SemrushBot`, `SiteAuditBot`, `SplitSignalBot`, `HeadlessChrome`.

**[INFERÊNCIA]** Incluir `Lighthouse` e `GTmetrix` nessa lista significa que **o widget não
carrega quando alguém está medindo performance da página**. É uma decisão de produto
deliberada para não aparecer nos relatórios de Core Web Vitals do cliente. É engenhoso e
eticamente cinzento — o site fica rápido na medição e lento para o usuário real. Não
recomendo copiar; recomendo resolver o peso de verdade (ver 8.4).

---

## 2. Mensagem proativa, teaser e nudge

Esta é a área com maior distância entre "o que o fornecedor vende" e "o que o usuário
final sente".

### 2.1 Taxonomia — três coisas diferentes que o mercado chama de "proativo"

| # | Padrão | O que faz | Intrusividade | Reversibilidade |
|---|---|---|---|---|
| **A** | **Teaser / balão ao lado da bolha** | Card pequeno com avatar + 1–2 linhas, ao lado ou acima do launcher. O painel **não** abre. | Baixa | Alta — tem "✕" próprio, não bloqueia nada |
| **B** | **Auto-open (chat abre sozinho)** | O painel completo se abre sem clique | Alta | Média — precisa fechar a janela inteira |
| **C** | **Interstitial / overlay** | Ocupa a tela ou escurece o fundo | Muito alta | Baixa — é modal |

**[INFERÊNCIA — a distinção que mais importa]** A reclamação de usuário final (seção 9) é
massivamente contra **B e C**, quase nunca contra **A**. Um teaser é um convite que fica no
canto; um auto-open é um vendedor que entra na frente do produto que você está lendo. A
Leadster, que é o benchmark brasileiro de conversão, é notavelmente um caso de **A**: o
"call-to-action inteligente" aparece como chamada de texto ao lado do avatar (a própria
configuração expõe "posição da chamada: ao lado do avatar ou acima dele"), não como janela
que se abre sozinha.
Fonte da configuração: <https://help.leadster.com.br/article/38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente>

### 2.2 Gatilhos praticados

| Gatilho | Descrição | Evidência |
|---|---|---|
| **Tempo na página** | Dispara após N segundos | **[FATO — AGREGADOR]** recomendação de 5–10s após o load, uma vez por sessão (<https://widget-chat.com/blog/chatbot-ui-design-best-practices/>) |
| **Profundidade de scroll** | Dispara após X% da página | **[FATO — AGREGADOR]** 40% como piso para filtrar bounce; 60–70% como alternativa confiável em mobile (<https://www.crazyegg.com/blog/exit-popup/>) |
| **Exit intent** | Mouse sai pela borda superior | **[FATO — FORNECEDOR]** exit-intent converte em média **2,81%**, com o decil superior em **19,63%** (dados Wisepops, set/2025, citados em <https://www.crazyegg.com/blog/exit-popup/>) |
| **Página específica** | Preço, checkout, produto | Universal |
| **Origem de tráfego** | Anúncio pago vs orgânico | Central na proposta da Leadster |
| **Retorno / visita repetida** | Segunda visita | Comum |
| **Inatividade** | Parado por N segundos | Comum |

**[FATO — FORNECEDOR]** Combinar exit-intent com chat proativo recupera "20–30% mais
visitantes que estão saindo do que só o popup".
Fonte: <https://www.crazyegg.com/blog/exit-popup/>. **Nível de confiança: baixo** — é
material de uma ferramenta de CRO, sem amostra publicada.

**[FATO — FORNECEDOR]** "Sites com convites proativos convertem 40% mais do que reativos" e
"chat proativo aumenta o engajamento em 3–5× sobre o reativo".
Fontes: <https://www.freshworks.com/live-chat/proactive-chat/> e agregadores.
**Nível de confiança: baixo.** É o número mais repetido do setor e não achei o estudo
original. **[INFERÊNCIA]** A direção quase certamente é verdadeira (convidar > esperar);
a magnitude, não.

### 2.3 Frequência e dispensa — as regras que o mercado converge

**[FATO — AGREGADOR, mas consensual em várias fontes independentes]**

1. **Uma vez por sessão.** Não repetir o teaser depois de dispensado na mesma sessão.
2. **Respeitar o "não".** Se o usuário fechou, o widget fica minimizado e não insiste.
   "Respeitar o 'não, obrigado' é tão importante quanto oferecer ajuda."
3. **No máximo um re-ping** para um usuário silencioso.
4. **Nunca antes de o usuário conseguir ler o título da página.**

Fontes: <https://widget-chat.com/blog/chatbot-ui-design-best-practices/>,
<https://getstream.io/blog/chat-ux/>

**[FATO — AGREGADOR]** "55% dos consumidores dispensam ferramentas de IA que interrompem a
navegação." Fonte: <https://clutch.co/resources/fix-your-chatbot-ux>. **Sem metodologia
publicada — baixa confiança no número, alta plausibilidade na direção.**

### 2.4 O que os usuários realmente dizem sobre isso

**[FATO VERIFICADO]** Thread do Hacker News (item 24834779), citações literais de usuários
reais:

> **dheera:** "I absolutely despise those pop-up 'Can I help you' boxes on product websites"
>
> **GordonS:** "The only ones I really despise are the ones that pop open _as soon_ as you
> open the page — I haven't even read the damned _page title_ yet"
>
> **GordonS:** "the ones I _really_ despise with a burning passion are the ones like above,
> but which follow you around the whole site like some kind of demented Clippy 2.0"
>
> **dheera:** "It completely disrupts my flow as a reader in trying to understand the product"
>
> **alias_neo:** "walking into a physical store and having the clerk harass you the second
> you walk in"
>
> **dirktheman:** "it's like entering a store, only to have your way virtually blocked by a
> pushy salesman"
>
> **amelius:** "Except the salesman turns out to be a bot with the IQ of a three year old"
>
> **vertis:** "Yep, It's not just Clippy, it's anything that I would want to dismiss and
> then it doesn't persist"

Fonte: <https://news.ycombinator.com/item?id=24834779>

**[INFERÊNCIA]** Note que **nenhuma** dessas reclamações é sobre a existência do chat. Todas
são sobre **momento** (antes de ler), **persistência** (não lembra que foi dispensado) e
**competência** (o bot é burro). Isso desenha o requisito com precisão cirúrgica:
o teaser pode existir, desde que chegue tarde, morra ao ser dispensado e tenha algo útil a
dizer.

### 2.5 Especificação de teaser recomendada (para o designer reproduzir)

**[INFERÊNCIA — síntese das evidências acima]**

```
┌──────────────────────────────────────┐
│ ┌──┐                              ✕  │  ← "✕" próprio, alvo ≥ 32×32px
│ │AV│  Ana · Consultora                │  ← nome real + papel, 13px/600
│ └──┘  Vi que você está vendo os       │  ← copy: 2 linhas, ≤ 90 caracteres
│       planos. Posso ajudar?           │     máx. 15px/400, line-height 1.4
└──────────────────────────────────────┘
                              ┌────┐
                              │ 💬 │
                              └────┘
```

- Largura: 260–300px em desktop; `calc(100vw - 32px)` com máximo de 320px em mobile.
- Posição: alinhado à direita, `bottom` = topo do launcher + 12px de gap.
- Entrada: `translateY(8px) → 0` + `opacity 0 → 1`, 200–250ms, `ease-out`. **Sem bounce.**
  **Sem som.**
- Delay mínimo: 8s de permanência na página **e** 30% de scroll (ou entrada em página de
  alta intenção).
- Dispensa: "✕" fecha, grava cookie de sessão, **não** reaparece.
- Clique no corpo do teaser: abre o painel já com a mensagem no histórico.

---

## 3. Formulário conversacional vs formulário estático

Esta é a tese comercial central da Leadster e a parte com melhor evidência quantitativa do
relatório inteiro.

### 3.1 A evidência de que "uma pergunta por vez" ganha

| Achado | Número | Fonte | Confiança |
|---|---|---|---|
| Formulários multi-etapa vs página única | **25,4%** mais conclusões | Formstack, análise de **650.000+** submissões | **Alta** — amostra publicada |
| Idem, taxas absolutas | **13,85%** (multi-etapa) vs **4,53%** (página única) | Formstack | **Alta** |
| Formulários conversacionais vs tradicionais | **+15% a +40%** de conclusão | Agregação incluindo Typeform (2,6 mi de formulários) | Média |
| Typeform (autodeclarado) | conclusão **>50%** vs média de mercado 20–30% | Typeform | **Baixa — fornecedor** |
| Popups conversacionais | **15,2%** de conversão média | OptiMonk | **Baixa — fornecedor** |
| Formulários curtos (< 5 campos) | formato tradicional empata ou **ganha** | agregação | Média |
| Vantagem conversacional concentra-se em | formulários de **6+ campos** | agregação | Média |

Fontes: <https://tinycommand.com/blogs/conversational-forms-vs-traditional-forms-which-is-better-for-your-business>,
<https://www.typeform.com/blog/interactive-form-boost-conversions>,
<https://gnosari.com/blog/conversational-completion-rates>

**[INFERÊNCIA — a leitura correta desses dados]** O ganho **não** vem de "ser um chat".
Vem de três coisas que o formato conversacional impõe por construção:
1. **Uma pergunta por tela** — reduz a carga cognitiva percebida do formulário inteiro.
2. **Lógica condicional** — "pule os galhos irrelevantes e um formulário de 20 perguntas
   parece 6, que é exatamente o ponto"
   (<https://fomr.io/blog/conversational-form-builder>).
3. **Progresso visível** — ver 3.4.

Se o seu formulário tem 3 campos, **converter para chat não vai ajudar**. A evidência é
explícita nisso.

### 3.2 Quantas perguntas antes de pedir o contato

**[FATO VERIFICADO — Baymard]** No checkout de e-commerce, o fluxo médio em 2024 tem
**5,1 etapas e 11,3 campos**; a Baymard sustenta que **a maioria dos sites precisa de
apenas 8 campos**; **17% dos usuários já abandonaram por complexidade do checkout**; e o
número que importa para a UX é o **número de campos, não o número de etapas**.
Histórico: 11,8 campos (2021) → 12,7 (2019) → 11,3 (2024).
Fonte: <https://baymard.com/blog/checkout-flow-average-form-fields>

**[FATO — AGREGADOR]** "As taxas de conclusão caem 4–6% para cada campo além do oitavo."
Circula atribuído à Baymard, mas **não localizei esse número no artigo primário** —
o artigo fala em "8 campos bastam", não na derivada. **Marcado como não verificado.**

**[FATO VERIFICADO — comportamento]** Bots que começam com botões guiados e só introduzem
texto livre depois de **duas ou três trocas estruturadas** capturaram **41% mais perfis de
lead completos**. Fonte: <https://blog.bothero.ai/best-chatbot-interfaces-what-separates-bots-people-actually-use-from-ones-they-immediately-close>.
**Confiança: média** — é post de fornecedor, mas com número específico e mecanismo plausível.

**[INFERÊNCIA — ordem recomendada de perguntas]** A ordem que a evidência sustenta:

```
1. Chamada / intenção      → botão   "O que você procura?"        [3–4 opções]
2. Qualificação leve       → botão   "Para quantas pessoas?"       [3–4 opções]
3. Qualificação leve 2     → botão   "Quando você precisa?"        [3–4 opções]
   ─── ponto de compromisso: o usuário já investiu 3 cliques ───
4. Nome                    → texto
5. Contato (e-mail OU WhatsApp — não os dois)  → texto com máscara
6. (opcional) Empresa/cargo → texto — só se B2B e só se realmente usado
```

Racional: as três primeiras são **zero-fricção** (clique, não digitação) e criam
*progresso investido* antes de qualquer pedido de dado pessoal. O pedido de contato chega
quando o custo psicológico de abandonar já é maior que o de responder.

### 3.3 Redução de perguntas por enriquecimento automático

**[FATO VERIFICADO]** A Leadster "identifica automaticamente a localização dos leads
através do IP do visitante, diminuindo o número de perguntas de qualificação".
Fonte: <https://leadster.com.br/blog/leadster-como-funciona/>

**[INFERÊNCIA]** Este é o padrão certo e é subutilizado. Tudo que dá para inferir não deve
ser perguntado: cidade/estado (IP), dispositivo, página de origem, campanha (UTM),
horário, se é retorno (cookie). Cada pergunta eliminada é uma etapa a menos no funil.
Em BR, com CEP dá para trazer endereço via ViaCEP e eliminar 4 campos.

### 3.4 Barra de progresso

**[FATO VERIFICADO — estudo acadêmico]** O **efeito de progresso dotado** (*endowed
progress effect*), de Nunes & Dreze (USC, 2006): no experimento do lava-jato, o grupo de
controle com cartão de 8 selos teve **19%** de conclusão; o grupo com cartão de 10 selos e
**2 selos já carimbados** teve **34%**, apesar de exigir exatamente o mesmo número de ações.
Fonte (secundária, mas descrevendo o estudo original):
<https://fomr.io/blog/form-progress-bar>

**[FATO — AGREGADOR]** Barras de progresso em formulários multi-página produzem tipicamente
**+10% a +15%** de conclusão. Mesma fonte.

**[FATO — AGREGADOR]** Caso relatado: pesquisa NPS de 15 perguntas reconstruída como fluxo
conversacional, uma pergunta por tela + barra de progresso, subiu de **11% para 38%** de
conclusão. Fonte: <https://gnosari.com/blog/conversational-completion-rates>.
**Confiança: baixa** (caso único, fornecedor), mas a magnitude é coerente com o Formstack.

**[INFERÊNCIA]** Em chat, a barra de progresso literal fica estranha. O equivalente
funcional é: **"Pergunta 2 de 4"** discreto no header, ou uma linha de pontos. E aplique
o *endowed progress*: se são 4 perguntas, comece o indicador em 1/5 já preenchido porque
"o usuário já disse que quer falar com você" — isso é honesto, não manipulativo, desde que
o número total seja verdadeiro.

### 3.5 Validação inline, máscaras BR e erro amigável

**[FATO VERIFICADO]** O ChatSPX já tem uma base decente de validação no pre-chat form
(`app/javascript/widget/i18n/locale/pt_BR.json`):

| Campo | Chaves existentes |
|---|---|
| Nome completo | `LABEL`, `PLACEHOLDER`, `REQUIRED_ERROR = "Nome Completo é mandatório"` |
| E-mail | `REQUIRED_ERROR`, `VALID_ERROR` |
| Telefone | `PLACEHOLDER`, `REQUIRED_ERROR`, `DIAL_CODE_VALID_ERROR = "Por favor, selecione um código de país"`, `VALID_ERROR`, `DROPDOWN_EMPTY`, `DROPDOWN_SEARCH = "Selecione o país"` |
| Mensagem | `LABEL`, `PLACEHOLDER`, `ERROR = "Mensagem muito curta"` |
| Genéricos | `IS_REQUIRED = "é obrigatório"`, `REQUIRED = "Obrigatório"`, `REGEX_ERROR = "Forneça uma entrada válida"`, `CHAT_FORM.INVALID.FIELD = "Campo inválido"` |

**[INFERÊNCIA]** Problemas visíveis nessa base para o mercado brasileiro:
1. `"Nome Completo é mandatório"` — "mandatório" é tradução mecânica de *mandatory*.
   Em pt-BR se diz **"obrigatório"**. É um erro de tom que o usuário percebe.
2. `REGEX_ERROR = "Forneça uma entrada válida"` — mensagem genérica é o pior tipo de erro:
   diz que está errado sem dizer o que é certo.
3. **Não há nada de CPF, CNPJ ou CEP.** Para um fluxo de captação brasileiro isso é lacuna
   estrutural.

**Máscaras e validações brasileiras que um widget de captação precisa
([FATO VERIFICADO] quanto aos formatos; as bibliotecas citadas confirmam o padrão em
<https://gaintime.github.io/br-validator/>):**

| Campo | Máscara | Validação | Mensagem de erro amigável recomendada |
|---|---|---|---|
| Celular | `(00) 00000-0000` | 11 dígitos, 3º dígito = 9, DDD válido | "Faltou um dígito. O celular tem 11 números com o DDD." |
| Fixo | `(00) 0000-0000` | 10 dígitos | "Confere o DDD? Parece que faltou um número." |
| CPF | `000.000.000-00` | dígitos verificadores (mód. 11) | "Esse CPF não confere. Dá uma olhadinha?" |
| CNPJ | `00.000.000/0000-00` | dígitos verificadores (mód. 11) | "Esse CNPJ não confere. Pode conferir?" |
| CPF **ou** CNPJ no mesmo campo | alterna por comprimento (11 → CPF, 14 → CNPJ) | idem | "Pode ser CPF ou CNPJ — os dois valem." |
| CEP | `00000-000` | 8 dígitos + consulta ViaCEP | "Não achei esse CEP. Quer digitar o endereço?" |
| E-mail | — | validar formato; **sugerir correção de domínio** (`gmial.com` → `gmail.com`) | "Você quis dizer **@gmail.com**?" |
| Data | `00/00/0000` | data real | "Essa data não existe. Confere o mês?" |

**Regras de UX de validação que o mercado converge ([FATO VERIFICADO] na
<https://gaintime.github.io/br-validator/>, que valida **no `blur`**, não a cada tecla):**

1. **Validar no blur, não no keypress.** Marcar erro enquanto a pessoa ainda está digitando
   é hostil.
2. **Máscara aplicada durante a digitação** (isso sim em tempo real) — a máscara ajuda, a
   validação atrapalha.
3. **Aceitar entrada suja e limpar por trás.** Se a pessoa colar `+55 (11) 99999-9999` ou
   `11999999999`, os dois devem funcionar.
4. **Erro perto do campo, nunca em modal.**
5. **Erro diz o que fazer, não o que aconteceu.** "E-mail inválido" ✗ → "Faltou o @ no
   e-mail" ✓.
6. **Nunca perca o que já foi digitado** ao errar.
7. **Em chat, o erro é uma mensagem do bot**, não um label vermelho. O bot responde
   "Hmm, esse número parece incompleto — pode mandar de novo com o DDD?" e o campo volta.
   Isso é mais gentil que o formulário e é a vantagem estrutural do formato conversacional.

---

## 4. Componentes de mensagem

### 4.1 Catálogo canônico

| # | Componente | O que é | Onde é padrão | Limites reais conhecidos |
|---|---|---|---|---|
| 1 | **Texto** | Bolha simples | Universal | — |
| 2 | **Markdown / rich text** | Negrito, itálico, lista, link, código | Comum | **[FATO VERIFICADO]** Sunshine Conversations: `htmlText` limitado a **4.096 caracteres** |
| 3 | **Link com preview** | Card de URL | Comum | **[FATO VERIFICADO]** ChatSPX tem `ATTACHMENTS.fallback.CONTENT = "compartilhou uma URL"` |
| 4 | **Quick replies** | Botões que substituem digitação e somem após o clique | Universal | **[FATO VERIFICADO]** Sunshine: até **11** quick replies; ações `reply` **não podem** ser misturadas com outros tipos na mesma mensagem |
| 5 | **Botões persistentes** | Botões que permanecem no histórico | Comum | **[FATO VERIFICADO]** Sunshine: máx. **10 ações** por mensagem |
| 6 | **Card / compound** | Imagem + título + descrição + botões | Universal | **[FATO VERIFICADO]** Sunshine: até **3 ações** por card |
| 7 | **Carrossel** | Cards com scroll horizontal | Universal | **[FATO VERIFICADO]** Sunshine: até **10 itens**, 3 ações por item |
| 8 | **Lista** | Itens com scroll vertical | Comum | **[FATO VERIFICADO]** Sunshine converte lista → carrossel no Web SDK; suporte nativo só em Messenger e WeChat |
| 9 | **Imagem** | Foto, sticker, GIF | Universal | **[FATO VERIFICADO]** ChatSPX: `ImageBubble.vue`, `ATTACHMENTS.image.CONTENT = "Mensagem de imagem"` |
| 10 | **Vídeo** | Player inline | Comum | **[FATO VERIFICADO]** ChatSPX: `VideoBubble.vue` |
| 11 | **Áudio** | Player com waveform | Emergente na web | **[FATO VERIFICADO]** ChatSPX: `ATTACHMENTS.audio.CONTENT = "Mensagem de áudio"` |
| 12 | **Arquivo** | Download com nome e tamanho | Universal | **[FATO VERIFICADO]** ChatSPX: `FileBubble.vue`, `FILE_BUBBLE.DOWNLOAD = "Download"`, `UPLOADING = "Enviando..."` |
| 13 | **Formulário embutido** | Vários campos numa bolha | Comum | **[FATO VERIFICADO]** Sunshine: campos `text`, `email`, `integer`, `decimal`, `select`. **Aviso oficial: "Do not use form messages to collect sensitive information, such as financial or payment details."** ChatSPX tem `FORM_BUBBLE.SUBMIT = "Enviar"` |
| 14 | **Calendário / agendamento** | Escolha de horário inline | Comum em vendas | **[FATO VERIFICADO]** Leadster integra Google Calendar; a função é liberada **por vendedor**, a **R$ 49,00/mês** por vendedor |
| 15 | **Pagamento** | Checkout no chat | Raro na web | Sunshine desaconselha coleta de dado financeiro em `form` |
| 16 | **CSAT / avaliação** | Estrelas ou polegares no fim | Universal | **[FATO VERIFICADO]** ChatSPX: `CSAT.TITLE = "Avalie sua conversa"`, `SUBMITTED_TITLE`, `PLACEHOLDER = "Conte-nos mais..."` |
| 17 | **Transferência para humano** | Card de sistema | Universal | Ver seção 6 |
| 18 | **Mensagem de sistema** | "Ana entrou na conversa" | Universal | Estilo distinto: centralizado, sem bolha, cinza |
| 19 | **Artigo da base de conhecimento** | Card de artigo | Comum | **[FATO VERIFICADO]** ChatSPX: `template/Article.vue`, `PORTAL.POPULAR_ARTICLES = "Artigos Populares"`, `VIEW_ALL_ARTICLES` |
| 20 | **Localização** | Mapa | Raro na web | **[FATO VERIFICADO]** ChatSPX: `ATTACHMENTS.location.CONTENT = "Localização"` |
| 21 | **Chamada de vídeo** | Entrar em sala | Emergente | **[FATO VERIFICADO]** ChatSPX: integração Dyte com `CLICK_HERE_TO_JOIN = "Clique aqui para entrar"` e `LEAVE_THE_ROOM = "Sair da ligação"` |

Fontes principais desta tabela:
<https://developer.zendesk.com/documentation/conversations/messaging-platform/programmable-conversations/structured-messages/>,
<https://docs.smooch.io/guide/web-messenger/>,
<https://help.leadster.com.br/article/112-como-utilizar-a-funcao-do-google-calendar-na-leadster>,
e leitura direta de `app/javascript/widget/components/` e do i18n pt-BR do ChatSPX.

### 4.2 Limites de canal — a restrição que o design tem de respeitar

Se o widget web e o WhatsApp compartilham o mesmo motor de conversa (que é o caso do
ChatSPX), o **denominador comum é o WhatsApp**, que é muito mais restritivo:

**[FATO VERIFICADO — limites do WhatsApp Business]**

| Elemento | Limite |
|---|---|
| Botões de resposta rápida (template) | **3 botões**, texto de até **20 caracteres** |
| Botões "Options" (Cloud API) | até **24 caracteres** |
| Reply buttons (declaração Meta) | **25 caracteres** |
| Itens de lista | máximo **10 opções**; botão de até **24 caracteres**; item de até **23 caracteres** |
| Título | **24 caracteres** (com suporte a emoji) |
| Header de texto | **60 caracteres** |

Fontes: <https://www.engagespark.com/support/whatsapp-business-limits/>,
<https://docs.haptik.ai/whatsapp-bots/how-to-use-whatsapp-list-and-buttons>,
<https://www.interakt.shop/interakt-academy/list-messages-and-reply-buttons/>

**[FATO VERIFICADO]** Existe uma issue aberta no próprio Chatwoot sobre isso —
"WhatsApp Interactive Messages with Button Texts Over Limit are Incorrectly Handled"
(issue #8288). Ou seja: **o upstream já sabe que estoura o limite e trata errado.**
Fonte: <https://github.com/chatwoot/chatwoot/issues/8288>

**[INFERÊNCIA]** O editor de fluxo do ChatSPX deveria **validar contra o limite mais
restritivo do canal alvo no momento da edição**, mostrando contador de caracteres, e não
descobrir na entrega. Se o mesmo fluxo roda em web e WhatsApp, o limite do WhatsApp vira
o contrato do design.

### 4.3 Quick replies — quantos botões?

**[FATO — FORNECEDOR, mas com mecanismo plausível]**
- Mostrar **2 a 4 opções**; cinco ou mais causa paralisia de decisão.
- Bots que apresentam **mais de 4 botões** de uma vez têm **22% mais abandono em mobile**
  do que bots com revelação progressiva.
Fonte: <https://blog.bothero.ai/best-chatbot-interfaces-what-separates-bots-people-actually-use-from-ones-they-immediately-close>

**[FATO VERIFICADO — contraponto]** Há um artigo de UX bem conhecido documentando o
problema oposto: "Honey, I built a chatbot, but no one will click on my buttons" — usuários
ignoram os botões e digitam.
Fonte: <https://uxdesign.cc/honey-i-built-a-chatbot-but-no-one-will-click-on-my-buttons-b713290c0029>

**[INFERÊNCIA — resolução]** Os dois achados não se contradizem: botões aumentam a
**conclusão do fluxo guiado**; texto livre aumenta a **satisfação e a cobertura de casos
fora do script**. O desenho correto tem os dois simultaneamente, com os botões como
sugestão visível e o campo sempre aberto.

### 4.4 Especificação visual de quick reply (para o designer)

**[INFERÊNCIA — síntese]**

- Chips com `border-radius` alto (16–20px), borda de 1px na cor de ação, fundo transparente
  ou muito claro, texto na cor de ação.
- Altura mínima **40px** (alvo de toque), padding horizontal 14–16px.
- Layout: empilhados verticalmente quando o texto é longo; em linha (com wrap) quando são
  chips curtos.
- Alinhamento: à direita, colados ao lado do usuário — o chip é a *resposta dele*.
- Ao clicar: o chip vira bolha de usuário na conversa e os outros chips **somem**
  (não ficam clicáveis).
- Estado desabilitado (mensagem antiga): chips de mensagens anteriores ficam com opacidade
  reduzida e não clicáveis, para não confundir.

---

## 5. Sinais de vida

"Sinais de vida" são os elementos que convencem o visitante de que existe alguém (ou algo
competente) do outro lado. É onde o chat ganha ou perde credibilidade em segundos.

### 5.1 Indicador de digitando

**[FATO VERIFICADO — pesquisa acadêmica]** O estudo "The Chatbot is typing… — The Role of
Typing Indicators in Human-Chatbot Interaction" encontrou que **latência maior de resposta
reduz a satisfação do cliente, mas a presença do indicador de digitando mitiga esse efeito
negativo**, porque os clientes percebem maior senso de presença social.
Fonte: <https://www.researchgate.net/publication/328744481_The_Chatbot_is_typing_-_The_Role_of_Typing_Indicators_in_Human-Chatbot_Interaction>

**[FATO VERIFICADO — pesquisa acadêmica]** Trabalho sobre agentes virtuais com LLM
identifica que **latência acima de ~4 segundos degrada a qualidade de experiência**, e que
"conversational fillers" naturais melhoram o tempo de resposta *percebido*, especialmente
em condições de alto atraso.
Fonte: <https://arxiv.org/pdf/2507.22352>

**[FATO — AGREGADOR]** "O indicador de digitando reduz o tempo de espera percebido em
20–40% em ambientes de live chat." Fonte: <https://chatboq.com/blogs/typing-indicator>.
**Sem metodologia — baixa confiança no número; a direção é confirmada pela literatura
acadêmica acima.**

**[FATO — AGREGADOR]** Tendemos a **superestimar a espera passiva em cerca de 36%** — ou
seja, esperar sem feedback parece muito mais longo do que é.
Fonte: <https://smart-interface-design-patterns.com/articles/designing-better-loading-progress-ux/>

**Padrão de implementação observado:** IA gera a resposta inteira, e então a "solta" com
atraso artificial e animação de digitação, para que a resposta instantânea não pareça
abrupta e o usuário perceba o atraso como processamento natural.
Fonte: <https://insertchat.com/glossary/typing-indicator>

**[FATO VERIFICADO]** O ChatSPX já tem `AgentTypingBubble.vue`.

**[INFERÊNCIA — parâmetros recomendados]**
- Bot: mostrar o indicador por **600ms a 1,5s** antes de mensagens curtas; escalar com o
  tamanho da resposta (≈ 30–40 caracteres por 100ms), com teto de **3s**.
- Nunca ultrapassar **4s** sem soltar algo (o limiar do estudo acima).
- Se a resposta demorar mais que 4s, trocar o "digitando" por um estado explícito
  ("Estou consultando isso, um segundo…").
- Humano: indicador reflete digitação **real**, sem simulação. Simular digitação de humano
  é mentira e cai na seção 9.
- Animação: 3 pontos com opacidade/translação em sequência, ciclo de ~1,2s. Respeitar
  `prefers-reduced-motion` (trocar por um pulso suave de opacidade).

### 5.2 Avatar do agente

**[FATO VERIFICADO — pesquisa acadêmica]** Avatares e fotografias de rosto geram
inferências de traço semelhantes quanto a atratividade, dominância e confiabilidade.
Fonte: <https://pmc.ncbi.nlm.nih.gov/articles/PMC12759104/>

**[FATO VERIFICADO — pesquisa acadêmica]** Existe efeito **vale da estranheza** em
chatbots de e-commerce: a comparação entre avatares hiper-realistas animados e avatares
cartunescos estáticos afeta *eeriness*, confiança e intenção comportamental, com a
familiaridade do avatar moderando o efeito.
Fonte: <https://www.tandfonline.com/doi/full/10.1080/10447318.2022.2121038>

**[INFERÊNCIA]** Implicação prática direta: **ou você usa foto real de pessoa real, ou usa
ilustração assumidamente ilustração.** O meio-termo — avatar 3D quase-humano, ou foto de
banco de imagem com nome inventado — é onde mora o desconforto e a desconfiança.

**Padrões observados:**
- **Avatar único** do agente designado.
- **Pilha de avatares** da equipe (2–4 sobrepostos, com o mais recente na frente) —
  comunica "tem gente aqui" sem prometer uma pessoa específica.
  **[FATO VERIFICADO]** ChatSPX tem `GroupedAvatars.vue`.
- **Avatar do bot** claramente distinto do avatar humano.
- **Fallback**: iniciais em círculo com cor derivada do nome.
  **[FATO VERIFICADO]** ChatSPX tem `THUMBNAIL.AUTHOR.NOT_AVAILABLE = "Indisponível"`.

**[FATO VERIFICADO]** A Intercom permite mostrar/ocultar as fotos dos agentes ("Team
avatars") na home do Messenger.
Fonte: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>

**[FATO VERIFICADO]** A Leadster deixa escolher avatar de uma galeria ou fazer upload
próprio, **incluindo o ícone do WhatsApp como avatar** — o que é uma jogada de UX
interessante: o avatar sinaliza o canal de destino antes mesmo da conversa começar.
Fonte: <https://help.leadster.com.br/article/38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente>

### 5.3 Timestamps e recibos de leitura

**[FATO VERIFICADO — padrão dominante]** O WhatsApp popularizou o padrão de três estados:
**um tique cinza** (enviado), **dois tiques cinza** (entregue), **dois tiques azuis** (lido).
Esse é o vocabulário que o usuário brasileiro já domina.
Fonte: <https://ably.com/topic/read-receipts>

**Estados canônicos:** `sending` → `sent` → `delivered` → `read` → (`failed`).

**[INFERÊNCIA — cuidado importante]** "Visto" em chat de site é uma faca de dois gumes.
No WhatsApp o "visto" é simétrico (os dois lados veem). Num widget de site, mostrar ao
visitante que o agente **leu e não respondeu** cria uma dívida explícita e visível, e
transforma cada segundo de silêncio em irritação medida. **Recomendação: mostrar
`sent`/`delivered`/`failed` sempre; mostrar `read` apenas quando houver garantia de SLA de
resposta, ou não mostrar.**

**Timestamps:** o padrão é mostrar hora relativa/curta na última mensagem de cada grupo
(ex.: "14:32"), com o dia em separador. Timestamp em toda mensagem polui.

### 5.4 Status online/offline e tempo de resposta exibido

**[FATO VERIFICADO]** O ChatSPX tem toda a família de strings pronta (listada em 1.3),
inclusive `REPLY_TIME.BACK_IN_MINUTES`, `BACK_AT_TIME`, `BACK_ON_DAY`, `BACK_TOMORROW` —
ou seja, o modelo já suporta promessa de retorno calculada, não só estática.

**[FATO VERIFICADO]** A Intercom configura "reply expectations" e horários de funcionamento
em nível de **workspace e de time**, com a opção "Show office hours after team assignment".
Tem também um campo de **"Special notice"** para avisar sobre atrasos, com suporte
multilíngue.
Fonte: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>

**Benchmarks reais de tempo de resposta que dão base para a promessa:**

| Métrica | Valor | Fonte | Confiança |
|---|---|---|---|
| Tempo médio de primeira resposta em live chat | **1min 35s** | Tidio, Customer Service Benchmark Report 2025 | Média (fornecedor, mas com relatório publicado) |
| Consumidores que esperam resposta imediata | **82%** | agregação | Baixa |
| Definem "imediato" como ≤ 10 minutos | ~**60%** | agregação | Baixa |
| Querem resposta em ≤ 10 min | **90%** | agregação | Baixa |
| Esperam resposta em ≤ 2 min | **60%** | agregação | Baixa |
| Regra tradicional de fila | **80% dos chats atendidos em 20s** | prática de contact center | Média |

Fontes: <https://www.tidio.com/blog/live-chat-statistics/>,
<https://www.gethelpable.com/blog/live-chat-response-time-benchmarks>

**[FATO — AGREGADOR]** Taxas de abandono em live chat rondam **50%** quando o cliente não
recebe resposta rápida.
Fonte: <https://www.alexanderjarvis.com/what-is-live-chat-abandonment-rate-in-ecommerce/>

**[INFERÊNCIA]** A regra de ouro: **nunca prometa mais rápido do que o seu p75 real**.
E derive a string automaticamente da métrica da inbox. Um widget que diz "responde em
alguns minutos" e demora 2 horas destrói mais confiança do que um que diz honestamente
"respondemos em até 1 dia útil".

### 5.5 Nome e foto reais do atendente

**[FATO VERIFICADO]** Desde 2023 a FTC alerta que chatbots humanizados e não rotulados
podem enganar consumidores razoáveis — "especialmente se você adicionar sinais como nomes
humanos ou avatares, ou alegações sobre expertise". A orientação inclui evitar rótulos como
"Concierge" se não disser que é IA.
Fonte: <https://caseclerk.ai/blog/do-law-firm-ai-chatbots-have-to-disclose-theyre-bots-california-bot-law-ftc-guidance-and-eu-ai-act-requirements-for-2025>

**[FATO VERIFICADO]** A lei da Califórnia (Bolstering Online Transparency Act, 2019) torna
ilegal usar bot para interagir com pessoa na Califórnia **com intenção de enganar sobre sua
identidade artificial** para enganar sobre o conteúdo da comunicação. A divulgação precisa
ser "clara, conspícua e razoavelmente desenhada para informar".
Fontes: <https://djholtlaw.com/is-your-ai-chat-bot-illegal-a-comprehensive-legal-guide-to-californias-bot-disclosure-act/>,
<https://www.termsfeed.com/blog/ca-bot-disclosure-law/>

**[FATO — AGREGADOR]** **14% dos consumidores perderiam a confiança** numa empresa se
interagissem com um agente de IA que não deixa claro que é IA.
Fonte: <https://www.zendesk.com/blog/ai/productivity/ai-customer-service-statistics/>

**[INFERÊNCIA]** Independente de obrigação legal no Brasil (não há lei específica de
disclosure de bot — ver seção 12), a recomendação de produto é inequívoca: **rotule o bot
como bot**. O ganho de curto prazo de fingir ser humano é apagado pelo custo do momento em
que o usuário descobre — e ele sempre descobre.

---

## 6. Bot → humano (handoff)

### 6.1 O contexto de preferência do usuário — a base do problema

**[FATO VERIFICADO]** Os números de preferência humano vs IA em 2025–2026 são consistentes
e desconfortáveis para quem vende bot:

| Achado | Número | Fonte |
|---|---|---|
| Preferem interagir com humano vs agente de IA | **84,7%** | Metrigy, estudo 2025–26 (<https://www.nojitter.com/customer-experience/consumers-overwhelmingly-prefer-human-agents-in-the-era-of-ai>) |
| Americanos que ainda preferem humano | **79%** | idem |
| Preferem IA sobre humano | apenas **8%** | SurveyMonkey, 2025 (<https://www.surveymonkey.com/curiosity/customer-service-statistics/>) |
| Frustração com agentes de IA (out/2025 → abr/2026) | **54% → 59%** | estudo com 6.000 pessoas (<https://www.answerconnect.com/blog/news/consumers-turning-away-from-ai-customer-service/>) |
| Desligariam se conectados a IA (out/2025 → abr/2026) | **29% → 31%** | idem |
| Preferem humano para fraude/segurança | **70%** | <https://www.surveymonkey.com/curiosity/customer-service-statistics/> |
| Preferem humano para rastrear pedido | apenas **19%** | idem |

**[INFERÊNCIA — a leitura correta]** Não é "IA ruim, humano bom". É **dependência de
contexto e de risco**: para tarefa simples e de baixo risco (rastrear pedido), 81% aceitam
IA; para tarefa de alto risco (fraude), 70% exigem humano. O design tem de rotear por
risco percebido, não por custo.

**[FATO VERIFICADO — o argumento decisivo]** "Estudos mostram que quando os clientes sabem
que podem alcançar um humano facilmente, eles frequentemente são **mais pacientes** e mais
dispostos a interagir primeiro com o chatbot."
Fonte: <https://cobbai.com/blog/chatbot-escalation-best-practices>

**[INFERÊNCIA]** Isso inverte a intuição de quem projeta bot para deflexão: **esconder o
botão "falar com humano" reduz a tolerância ao bot.** Deixar a saída visível aumenta o
tempo que a pessoa dá ao bot. A saída visível é *pró-deflexão*, não contra.

### 6.2 Gatilhos de escalonamento praticados

| Gatilho | Descrição |
|---|---|
| **Pedido explícito** | "quero falar com atendente", "humano", "atendimento" |
| **Falha repetida de intenção** | 2 respostas de "não entendi" seguidas |
| **Sentimento negativo** | análise de sentimento na mensagem |
| **Palavra-chave crítica** | "cancelar", "reclamação", "Procon", "advogado", "fraude" |
| **Alto valor** | lead qualificado acima de um limiar |
| **Tempo no fluxo** | usuário preso há N minutos |

Fonte de consolidação: <https://www.atys.pro/blog/automacao/handoff-humano-chatbot-atendente-2026>

**[FATO VERIFICADO]** A operação em 2026 é descrita como precisando de "gatilhos
automáticos, reconhecimento de intenção, análise de sentimento e a capacidade de o atendente
assumir a conversa com todo o histórico e contexto." Mesma fonte.

### 6.3 O que o handoff bem feito faz

**[FATO VERIFICADO]** Consolidação das melhores práticas:

1. **Comunicar a transferência.** "O silêncio durante uma transferência faz o usuário se
   perguntar se foi esquecido ou desconectado."
2. **Preservar contexto integralmente.** Histórico + dados coletados vão junto, para o
   cliente **não precisar reexplicar**.
3. **Dar posição na fila ou tempo estimado.** "Mostrar posição na fila em vez de tempo
   estimado parece mais real e menos volátil." Recomenda-se reportar profundidade de fila e
   ETA na janela do chat, **atualizando a cada 60–90 segundos**.
4. **Aos 2 minutos, oferecer alternativa.** "Você prefere um retorno por telefone ou
   acompanhamento por e-mail?"

Fontes: <https://cobbai.com/blog/chatbot-escalation-best-practices>,
<https://www.eesel.ai/blog/best-practices-for-human-handoff-in-chat-support>,
<https://standardbeagle.com/chatbot-handoff-ux/>

**[FATO VERIFICADO — como a Leadster faz]** "Seus atendentes são notificados quando o lead
quiser um atendimento humano, e seu atendente recebe todas as informações coletadas no
fluxo e já entende o objetivo do lead." O produto se posiciona explicitamente como **"sem
filas"**, com resposta instantânea, e permite **configurar dias da semana e horário em que
o Live Chat fica disponível**, além de **exibir o chat apenas quando houver atendente
online**. Leads podem ser distribuídos entre vendedores via "Roleta do WhatsApp".
Fontes: <https://leadster.com.br/live-chat/> e
<https://help.leadster.com.br/article/349-leadster-live-chat>

**[INFERÊNCIA]** A opção "só exibe o chat quando há atendente online" é uma escolha de
produto muito forte e pouco copiada: em vez de prometer e falhar, some. Reduz frustração
a zero ao custo de perder o lead noturno. Para um produto de captação, o certo é o
**híbrido**: o bot continua captando fora do horário, mas o rótulo muda honestamente.

### 6.4 Fora do horário

**[FATO VERIFICADO — princípio central]** "A primeira regra é simples: faça a promessa
corresponder à realidade. Fingir que você está online quando não está é uma das formas mais
rápidas de irritar clientes."
Fonte: <https://www.gethelpable.com/blog/live-chat-outside-business-hours>

**Práticas consolidadas:**
- Coletar nome, e-mail e descrição do problema, e informar quando haverá resposta,
  **o mais específico possível** — ex.: "em até 12 horas".
- "Mensagens offline devem parecer úteis, não desculpas."
- Fora do horário o widget não deve virar beco sem saída: deixe a IA responder as dúvidas
  comuns e colete e-mail, nome e intenção para o follow-up.
Fontes: <https://www.jivochat.com/blog/communication/offline-messages.html>,
<https://www.oscarchat.ai/blog/live-chat-availability-best-practices/>

**[FATO VERIFICADO]** O ChatSPX já tem a estrutura de strings para isso, inclusive as
variantes de retorno calculado (`BACK_IN_HOURS`, `BACK_AT_TIME`, `BACK_ON_DAY`,
`BACK_TOMORROW`) e o componente `Availability/` + `TeamAvailability.vue`.

### 6.5 Especificação do card de handoff (para o designer)

**[INFERÊNCIA — síntese]**

```
        ─────────────────────────────────────────
             🔄  Transferindo para um atendente
             Você é o 2º da fila · ~3 min
        ─────────────────────────────────────────

        ┌──┐  Ana entrou na conversa
        │AV│  ─────────────────────────
        └──┘
        ┌────────────────────────────────┐
        │ Oi, Marcos! Vi que você quer    │  ← agente já sabe o nome e o assunto:
        │ saber sobre o plano Pro.        │     prova de que o contexto passou
        └────────────────────────────────┘
```

- Mensagem de sistema: centralizada, sem bolha, 12–13px, cor secundária, separadores finos.
- Atualizar a posição na fila a cada 60–90s (fonte 6.3).
- Aos 120s sem agente: injetar card com botões `[ Receber por e-mail ]`
  `[ Receber no WhatsApp ]` `[ Continuar esperando ]`.
- A primeira frase do humano **deve** referenciar algo que o bot já coletou. É o sinal mais
  barato e mais eficaz de que a transferência funcionou.

---

## 7. Dark mode, temas, branding e customização

### 7.1 Dark mode

**[FATO VERIFICADO]** A Intercom oferece três modos de tema: **Light** (sempre claro),
**Dark** (sempre escuro) e **Match System** (segue a preferência do dispositivo). Cada tema
exige **paleta de cores e logo separados**. No mobile SDK, o dark mode requer versões
mínimas: **iOS 19.0.0** e **Android 17.0.0**.
Fonte: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>

**[NÃO VERIFICADO]** Não consegui confirmar em documentação oficial o estado do suporte a
dark mode em Zendesk Web Widget, Crisp e Tidio — a busca só retornou páginas comparativas
de terceiros sem detalhe. Registrado como lacuna.

**[FATO VERIFICADO — armadilha técnica no ChatSPX]** O CSS do SDK do ChatSPX contém
`color-scheme: normal` no iframe do widget:

```css
.woot-widget-holder iframe {
  border: 0;
  color-scheme: normal;
  height: 100% !important;
  width: 100% !important;
  max-height: 100vh !important;
}
```

**[INFERÊNCIA]** `color-scheme: normal` neutraliza a herança do esquema de cor do site
hospedeiro no iframe. Isso é bom (o widget não fica escuro por acidente quando o site é
escuro) e ruim (o widget precisa decidir o tema sozinho). Qualquer trabalho de dark mode no
widget tem de considerar essa linha explicitamente — ela é o ponto onde o tema do host
para de valer.

**[INFERÊNCIA — modelo recomendado]** Três estados, igual à Intercom: `light` | `dark` |
`auto` (via `prefers-color-scheme` **dentro do iframe**). O `auto` deve ser o padrão.
Marca precisa de duas versões de logo e de duas variantes da cor de ação (a cor da marca
raramente tem contraste suficiente nos dois fundos).

### 7.2 O que é customizável no mercado

| Recurso | Intercom | Zendesk (Classic) | Sunshine Conv. | Crisp | Leadster | ChatSPX hoje |
|---|---|---|---|---|---|---|
| Cor primária/ação | ✅ | ✅ | ✅ `brandColor`, `conversationColor`, `actionColor` | ✅ | não publicado | ✅ (`woot-widget-bubble` background, `--flat`, `--lighter`) |
| Posição L/R | ✅ | ✅ (`offset`) | ✅ | ✅ | ✅ | ✅ (`woot-elements--left/right`) |
| Padding H/V | ✅ | ✅ | — | ✅ | ✅ ("espaçamento") | parcial |
| Tamanho do launcher | ❌ | ❌ | ✅ (`buttonWidth`/`buttonHeight`) | — | ✅ (3 tamanhos de foto) | ❌ (fixo em 64/56) |
| Ícone/logo do launcher | ✅ (72×72) | ✅ | ✅ `buttonIconUrl` | ✅ | ✅ (galeria + upload) | parcial |
| Header com imagem/gradiente | ✅ (800×600) | ❌ | ✅ `backgroundImageUrl` | — | — | ❌ |
| Dark mode | ✅ (3 modos) | não verificado | não verificado | não verificado | não verificado | ❌ |
| Remover branding | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (`POWERED_BY`) |
| Launcher customizado (elemento do site) | ✅ `custom_launcher_selector` | ✅ | ✅ | ✅ | ✅ (botão com `window.neurolead.open()`) | ✅ (`hideMessageBubble` + API) |
| Som de notificação | — | ✅ | ✅ `soundNotificationEnabled` | — | — | — |
| Textos customizados | ✅ (45 idiomas) | ✅ | ✅ `customText` | ✅ | ✅ | ✅ (i18n completo) |

**[FATO VERIFICADO]** A Leadster documenta abertura por botão do site com
`<button onclick="event.stopPropagation();window.neurolead.open();">`.
Fonte: <https://help.leadster.com.br/article/46-como-inserir-o-chat-em-um-botao-popup-no-seu-site>

**[FATO VERIFICADO]** A Leadster recomenda inserir o script **antes do `</body>`**, "assim
nosso script é o último a carregar no seu site, sem afetar o tempo de carregamento da
página".
Fonte: <https://help.leadster.com.br/article/37-instalar-o-codigo-via-html>

**[FATO VERIFICADO]** A Intercom aceita **domínios confiáveis com wildcard**
(`*.example.com`), duração de sessão customizável, cookies seguros HTTPS-only e recomenda
**autenticação JWT** para verificação de identidade.
Fonte: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>

### 7.3 Customização percebida pelo cliente final (o comprador do produto)

**[INFERÊNCIA]** Do ponto de vista do cliente que contrata o widget, "customizável" na
prática significa quatro coisas, nessa ordem de importância:

1. **A cor bate com a minha marca** — inegociável, é o primeiro teste.
2. **O meu logo aparece** — segundo teste.
3. **Os textos estão no meu tom e no meu idioma** — o terceiro, e o mais negligenciado.
4. **Não aparece o nome do fornecedor** — o quarto, e sempre associado a plano pago.

O que **não** entra na lista percebida: tamanho da bolha, raio do canto, animação. Note
que Intercom e Zendesk simplesmente **não deixam** mudar tamanho e ninguém deixa de comprar
por causa disso. **[INFERÊNCIA]** Investir esforço de engenharia em "widget totalmente
skinnável" tem ROI baixo; investir em "cor + logo + textos + branding removível" tem ROI
alto.

---

## 8. Acessibilidade percebida e mobile-first

### 8.1 Acessibilidade — os requisitos que aparecem repetidamente

**[FATO VERIFICADO]** Consolidação dos checklists WCAG 2.2 AA aplicados a chat widget:

| Requisito | Detalhe |
|---|---|
| **Transcrição anunciável** | Marcar o container como `role="log"` ou `role="region"` com `aria-live="polite"`, para novas respostas serem anunciadas **sem roubar o foco** |
| **Sem pulo de scroll** | Anexar mensagens suavemente, sem levar o scroll para longe do ponto de foco |
| **Focus trap condicional** | Prender o foco **apenas quando o widget está aberto**, nunca quando minimizado |
| **Launcher focável** | Alcançável por Tab |
| **Foco ao abrir** | Ao abrir, o foco vai para o campo de mensagem |
| **Foco ao fechar** | Retorna para o launcher |
| **Todas as ações por teclado** | Enviar, anexar, avaliar — sem atalhos escondidos |
| **Indicador de foco visível** | Com contraste conforme WCAG |
| **Sem armadilha de teclado** | Ordem de foco lógica |

Fontes: <https://threada.ai/blog/wcag-22-chat-widget-accessibility-checklist/>,
<https://www.testdevlab.com/blog/accessible-live-chats-tips-for-designing-creating-and-testing>,
<https://www.livechat.com/success/chat-widget-accessibility/>,
<https://www.cognigy.com/product-updates/webchat-accessibility-wcag-best-practices>

**[FATO VERIFICADO]** "A maioria das pessoas usa Tab e Shift+Tab para percorrer o conteúdo,
e se o usuário não consegue interagir com o cliente de chat com esses comandos, ele não
consegue se comunicar."
Fonte: <https://www.boia.org/blog/5-quick-tips-for-accessible-live-chat>

**[FATO VERIFICADO — o que o ChatSPX já acerta]**
- O launcher é `<button>` real, não `<div>` com `onclick`.
- O foco volta ao launcher ao fechar (`chatBubble.focus()`).
- `title = 'Open chat window'` no botão.
- Existe `EMOJI.ARIA_LABEL = "Seletor de emoji"` no i18n.
- Existe `BUBBLE.LABEL = "Fale conosco no chat"` em pt-BR.

**[INFERÊNCIA — o que provavelmente falta]** O `title` do launcher está **hardcoded em
inglês** no `bubbleHelpers.js` (`target.title = 'Open chat window'`) enquanto existe a chave
`BUBBLE.LABEL` traduzida — ou seja, o leitor de tela de um usuário brasileiro
provavelmente ouve inglês. Isso é vazamento de i18n na camada de acessibilidade e é
exatamente o tipo de coisa que passa despercebido em teste visual.

### 8.2 Acessibilidade percebida (a dimensão de UX, não de conformidade)

**[INFERÊNCIA]** Conformidade técnica não é a mesma coisa que "sinto que consigo usar
isso". A dimensão percebida tem quatro elementos:

1. **Alvo de toque generoso.** O launcher de 56–64px passa folgado nos 44px do WCAG; mas o
   "✕" do teaser e o "✕" do header frequentemente têm 20px. É ali que a mão treme.
2. **Contraste do texto secundário.** Timestamps, "Desenvolvido por", status — quase sempre
   em cinza claro sobre branco, quase sempre abaixo de 4.5:1.
3. **Texto que cresce.** Se o usuário tem o navegador em 200%, o widget continua usável ou
   o composer some?
4. **Movimento.** Bolha que pulsa/quica é um problema real para quem tem sensibilidade
   vestibular. `prefers-reduced-motion` deve desligar tudo isso.

### 8.3 Mobile-first

**[FATO VERIFICADO — o dado que muda a prioridade]**

| Métrica | Valor | Fonte |
|---|---|---|
| Tráfego mobile global | **62–64%** (desktop ~35%, tablet ~2%) | Statcounter, jan/2026, citado em <https://sqmagazine.co.uk/mobile-vs-desktop-statistics/> |
| Tráfego mobile em e-commerce | até **70%** das visitas | <https://sqmagazine.co.uk/e-commerce-conversion-rate-statistics/> |
| Conversão desktop | **3,5–4,0%** | idem |
| Conversão mobile | **1,8–2,5%** | idem |
| Brasil — participação mobile nos minutos digitais | **72%** | <https://sqmagazine.co.uk/mobile-vs-desktop-statistics/> |

**[INFERÊNCIA]** O Brasil é mais mobile que a média global e converte menos em mobile.
Isso significa que **a maior oportunidade isolada de conversão de um widget brasileiro está
na experiência mobile**, não na desktop. Um widget que é excelente em desktop e "aceitável"
em mobile está otimizando os 28% errados.

**[FATO VERIFICADO — o problema técnico nº 1 do mobile]** O bug do `100vh` no iOS Safari:
o navegador calcula a viewport como (barra superior + documento + barra inferior) = 100vh,
sem incluir as barras que aparecem/somem. Quando o teclado virtual aparece, ele é
**sobreposto** ao conteúdo: a *visual viewport* é redimensionada, mas a *layout viewport*
não. Resultado prático: **o composer ancorado embaixo fica enterrado sob o teclado.**
Fontes: <https://dev.to/maciejtrzcinski/100vh-problem-with-ios-safari-3ge9>,
<https://www.htmhell.dev/adventcalendar/2024/4/>

**Soluções verificadas:**
1. **`dvh`** (dynamic viewport height) — ajusta-se à viewport visível atual; funciona em
   iOS Safari e Android recentes; fallback para `100vh` em iOS muito antigo via
   feature-test.
2. **`interactiveWidget: 'resizes-content'`** no meta viewport para Android/Chromium
   redimensionar o conteúdo com o teclado.
3. `visualViewport` API como último recurso (mais frágil, exige listeners).
Fonte: <https://www.franciscomoretti.com/blog/fix-mobile-keyboard-overlap-with-visualviewport>

**[FATO VERIFICADO — estado atual do ChatSPX]** O CSS do SDK usa `100vh` e `100%`, sem
`dvh` em lugar nenhum:

```css
@media only screen and (max-width: 667px) {
  .woot-widget-holder { height: 100%; right: 0; top: 0; width: 100%; }
  .woot-widget-holder iframe { min-height: 100% !important; }
  .woot-widget-holder.has-unread-view { max-height: 100vh; }
}
```
e `.woot-widget-holder iframe { max-height: 100vh !important; }`.

**[INFERÊNCIA]** O `max-height: 100vh` combinado ao fullscreen mobile é exatamente o padrão
que produz o composer enterrado sob o teclado no iOS. É um candidato forte a bug real de
campo do widget do ChatSPX em iPhone.

**Outros pontos mobile-first:**
- **Breakpoint**: o ChatSPX usa `667px` (a largura do iPhone 6/7/8 em landscape). É um
  breakpoint datado; o mercado hoje trabalha em `640px` ou `768px`.
- **Launcher some ao abrir**: o ChatSPX faz isso (`bottom: 60px; opacity: 0`), o que é
  correto — em fullscreen a bolha não faz sentido.
- **Fechar em fullscreen**: com o painel em 100% da tela, o "✕" do header é a única saída.
  Precisa ser generoso e no canto que o polegar alcança. **[INFERÊNCIA]** vale também
  suportar o botão "voltar" do Android e o gesto de arrastar para baixo.
- **Teclado abrindo desloca a lista**: ao abrir o teclado, a última mensagem tem de
  continuar visível.

### 8.4 Peso e performance do widget

**[FATO — FORNECEDOR/ANALÍTICO]** "Os widgets de chat mais pesados (Zendesk, Tawk.to)
carregam de **500 a 750 KB** de JavaScript, enquanto alternativas mais leves como Zoho Desk
e Crisp ficam abaixo de **155 KB**. Em média, um widget de chat adiciona **300 a 600 ms** de
bloqueio de main thread — suficiente para empurrar um INP que passaria para a faixa de
'needs improvement'."
Fonte: <https://www.pagespeedfix.com/blog/third-party-scripts-core-web-vitals/>.
**Confiança: média** — é uma consultoria de performance, com números específicos e método
plausível, mas sem dataset publicado.

**[FATO VERIFICADO — Google]** Quando o tempo de carregamento vai de 1s para 3s, a
probabilidade de bounce sobe **32%**; de 1s para 5s, sobe **90%**.
Fonte primária amplamente citada (Google/SOASTA), reportada em
<https://www.pagespeedfix.com/blog/third-party-scripts-core-web-vitals/>

**Padrão de mitigação verificado:** em vez de carregar o widget após o `load`, esperar a
**primeira interação real** do visitante (`mousemove`, `scroll`, `touchstart`) e só então
carregar o script — garantindo zero impacto em Core Web Vitals para quem nunca interage.
Fonte: <https://www.corewebvitals.io/pagespeed/chat-widget-perfect-core-web-vitals>

**[INFERÊNCIA]** Isso é a resposta honesta ao truque do Crisp de ignorar o Lighthouse
(seção 1.7): em vez de esconder o widget do medidor, **não carregue o widget até que ele
seja necessário**. O resultado no relatório é o mesmo; a diferença é que o usuário real
também ganha.

---

## 9. Anti-padrões e reclamações reais

### 9.1 Catálogo de anti-padrões

Ordenados por gravidade percebida na evidência coletada.

| # | Anti-padrão | Evidência | Por que dói |
|---|---|---|---|
| **A1** | **Abrir sozinho antes de o usuário ler a página** | "The only ones I really despise are the ones that pop open _as soon_ as you open the page — I haven't even read the damned _page title_ yet" (HN 24834779) | Rouba a atenção antes de haver qualquer relacionamento |
| **A2** | **Perseguir o usuário pelo site inteiro** | "which follow you around the whole site like some kind of demented Clippy 2.0" (HN) | Sinaliza que a dispensa não foi registrada |
| **A3** | **Não persistir a dispensa** | "anything that I would want to dismiss and then it doesn't persist" (HN) | Transforma cada navegação numa nova negociação |
| **A4** | **Bot incompetente disfarçado de gente** | "the salesman turns out to be a bot with the IQ of a three year old" (HN) | Expectativa alta + entrega baixa = raiva |
| **A5** | **Empilhamento de overlays** | Nielsen: "subscription box slides into view, a cookie banner covers the bottom, and a chat widget bounces in from the corner"; o usuário "deve dispensar uma pilha de sobreposições antes de conseguir ver a página" (<https://www.uxtigers.com/post/ui-annoyances>) | Custo de dispensa multiplicado |
| **A6** | **Som / autoplay** | Nielsen: **92%** acham autoplay irritante, **88%** o chamam de intrusivo, **mais de um terço abandona o site** (<https://www.uxtigers.com/post/ui-annoyances>) | Viola controle do usuário; toca em contexto errado (trabalho, aula) |
| **A7** | **Widget que cobre o conteúdo que o usuário quer** | Nielsen: "chat pode ser útil quando o usuário pede, mas quando é agressivo e sobrepõe a informação que o usuário quer, a experiência azeda rapidamente" | Inverte a prioridade: o site serve o vendedor, não o visitante |
| **A8** | **"Como posso ajudar?" sem sinalizar o escopo** | NN/g: com prompt vago o usuário "não tem sinal do que o sistema consegue responder"; com 3 exemplos nomeados, decide em 5 segundos | Falha de descoberta — o problema estrutural de CUI |
| **A9** | **Fluxo linear que quebra ao primeiro desvio** | NN/g: chatbots "têm dificuldade quando os usuários se desviam desses fluxos"; "a experiência parece suave quando os usuários dão as respostas esperadas, e o problema ocorre assim que o usuário sai do roteiro" | O usuário real sempre sai do roteiro |
| **A10** | **Sem saída para humano** | "quando os clientes sabem que podem alcançar um humano facilmente, eles são mais pacientes" (<https://cobbai.com/blog/chatbot-escalation-best-practices>) | Esconder a saída reduz a paciência com o bot |
| **A11** | **Prometer online e não responder** | "Fingir que você está online quando não está é uma das formas mais rápidas de irritar clientes" (<https://www.gethelpable.com/blog/live-chat-outside-business-hours>) | Quebra de promessa explícita e verificável |
| **A12** | **Bot não rotulado como bot** | FTC alerta contra chatbots humanizados não rotulados, "especialmente se você adiciona sinais como nomes humanos ou avatares"; **14%** perderiam confiança | Engano descoberto = confiança zero |
| **A13** | **Pedir dado antes de entregar valor** | Baymard: **17%** abandonam por complexidade; o que importa é o número de campos | Custo antes de benefício |
| **A14** | **Erro genérico** | "Forneça uma entrada válida" (string real do ChatSPX) | Diz que errou sem dizer como acertar |
| **A15** | **Silêncio na transferência** | "O silêncio durante uma transferência faz o usuário se perguntar se foi esquecido" | Ansiedade sem informação |
| **A16** | **Peso do script** | 500–750 KB de JS; +32% de bounce entre 1s e 3s | Custo de conversão antes mesmo do primeiro clique |
| **A17** | **Roubar o foco do leitor de tela** | Checklists WCAG: `aria-live="polite"`, não `assertive` | Interrompe a leitura da página |
| **A18** | **Composer travado no fluxo do bot** | "usuários não usam bots como apps — eles querem conversar, não clicar em botões" | Remove a única saída de quem tem pergunta fora do menu |
| **A19** | **Mais de 4 botões de uma vez** | **+22%** de abandono em mobile vs revelação progressiva | Paralisia de decisão em tela pequena |
| **A20** | **Vale da estranheza no avatar** | Estudo sobre uncanny valley em chatbots de e-commerce afeta *eeriness*, confiança e intenção de compra | Avatar quase-humano incomoda mais que ilustração assumida |

### 9.2 A analogia que os usuários usam espontaneamente

**[FATO VERIFICADO]** Três usuários independentes, na mesma thread, chegaram à mesma
metáfora sem se coordenar:

> "walking into a physical store and having the clerk harass you the second you walk in"
> — *alias_neo*
>
> "it's like entering a store, only to have your way virtually blocked by a pushy salesman"
> — *dirktheman*

**[INFERÊNCIA]** Essa convergência é o achado qualitativo mais útil do relatório. O modelo
mental do usuário para chat proativo é **loja física**. Isso dá um teste de design simples e
que qualquer pessoa da equipe consegue aplicar sem treinamento:

> **Teste do vendedor:** se um vendedor de loja fizesse isso comigo — nesse momento, com
> essa frase, nesse tom, essa quantidade de vezes — eu acharia normal ou sairia da loja?

Um vendedor que diz "fique à vontade, se precisar estou ali" ao te ver parado na prateleira
de preços por dois minutos: **normal**. Um vendedor que entra na sua frente na porta:
**você sai**.

### 9.3 O que faz fechar a aba (síntese)

**[INFERÊNCIA — ordenado por severidade estimada a partir da evidência]**

1. Som inesperado (Nielsen: >1/3 abandona o site por autoplay).
2. Modal que cobre o conteúdo antes de qualquer leitura.
3. Impossibilidade de fechar / "✕" minúsculo ou escondido.
4. Bot que não entende nada e não oferece humano.
5. Pedido de e-mail/telefone antes de qualquer valor entregue.
6. Widget que reaparece depois de dispensado.

### 9.4 O que gera desconfiança (distinto de irritação)

**[INFERÊNCIA]** Irritação faz fechar a aba; desconfiança faz não comprar mesmo ficando.

1. Nome humano + foto de banco de imagem em cima de um bot.
2. "Ana está digitando…" quando é a IA gerando.
3. "Estamos online" quando é 23h de domingo.
4. Promessa de tempo de resposta que não se cumpre no primeiro teste.
5. Pedir CPF sem explicar por quê.
6. Nenhuma menção a privacidade num formulário que coleta telefone.

---

## 10. Evidência de conversão

Esta é a seção mais importante e a que exige mais disciplina. **Leia a advertência
metodológica antes da tabela.**

### 10.0 Advertência metodológica

O corpus público de "estatísticas de live chat" tem três camadas:

1. **Estudos com amostra publicada** (Leadster/Panorama, Formstack, Baymard, Nunes & Dreze,
   Drift/433 empresas). São poucos, e são os únicos que sustentam decisão.
2. **Relatórios de fornecedor com metodologia parcial** (Tidio Benchmark Report, Forrester,
   Metrigy, SurveyMonkey). Úteis, com viés conhecido.
3. **Posts de "N estatísticas"** que citam uns aos outros num ciclo fechado. A maior parte
   dos números famosos ("live chat aumenta conversão em 20%", "chat proativo converte 40%
   mais") vive aqui e **não tem estudo original localizável**.

**[INFERÊNCIA]** Números da camada 3 devem ser tratados como *hipóteses de direção*, nunca
como magnitude. Se uma decisão de produto depende da magnitude, a única saída é medir
internamente.

### 10.1 Benchmarks brasileiros — Leadster / Panorama de Geração de Leads

Este é **o melhor dado brasileiro público** e o mais relevante para o ChatSPX, porque é
sobre o nosso mercado, com amostra grande e publicado anualmente há 5 edições.

**[FATO VERIFICADO — metodologia]**

| Edição | Sites | Acessos | Leads | Segmentos |
|---|---|---|---|---|
| **2026** (dados de 2025) | **2.425** | **173,6 milhões** | **3,4 milhões** | 17 |
| **2025** (dados de 2024) | **2.861** | **167 milhões** | **3,7 milhões** | 17 |

Fontes: <https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil/> e
<https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil-2025/>

**Viés a declarar [INFERÊNCIA]:** a amostra é composta **exclusivamente de clientes da
Leadster** — ou seja, sites que já decidiram usar marketing conversacional. Não é uma
amostra representativa da web brasileira. Serve muito bem como *benchmark relativo entre
segmentos e canais*; serve mal como "a taxa de conversão do Brasil".

**[FATO VERIFICADO] Taxa de conversão mediana geral, série histórica:**

| Ano de referência | Mediana | Movimento |
|---|---|---|
| 2024 | 3,15% (implícito) | — |
| **2025** | **2,98%** | −0,17 p.p. (3º ano consecutivo de queda) |
| **2026 (parcial/atual)** | **3,07%** | recuperação |

Fontes: <https://leadster.com.br/blog/panorama-geracao-de-leads-2025/> e
<https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil/>

**[FATO VERIFICADO] Taxa de conversão por segmento (dados de 2025, 17 segmentos):**

| # | Segmento | Conversão |
|---|---|---|
| 1 | Telefonia e Internet | **5,40%** |
| 2 | Marketing e Publicidade | **4,80%** |
| 3 | Jurídico | **4,45%** |
| 4 | Seguros | **4,18%** |
| 5 | Saúde | **4,07%** |
| 6 | Venda de Serviços | **3,91%** |
| 7 | Indústria e Fabricação | **3,81%** |
| 8 | Financeiro | **3,23%** |
| — | **Média geral** | **2,98%** |
| 9 | Varejo | **2,80%** |
| 10 | Agências de Viagens | **2,75%** |
| 11 | Educacional | **2,67%** |
| 12 | Logística e Transporte | **2,64%** |
| 13 | Tecnologia e TI | **2,06%** |
| 14 | Software | **1,95%** |
| 15 | Energia | **1,90%** |
| 16 | Consultoria | **1,55%** |
| 17 | Imóveis | **1,52%** |

Fonte: <https://leadster.com.br/blog/taxa-de-conversao-por-segmento/>

**[FATO VERIFICADO] Por canal de origem (2026):**

| Canal | Conversão | Observação |
|---|---|---|
| **IA / ChatGPT** | **7,80%** | eficiência 2,5× maior que a participação de tráfego |
| **Google Ads** | **3,41%** | mediana |
| **Google (geral)** | **3,4%** | |
| **Orgânico** | **2,39%** | **44,51%** dos leads com score alto — o canal mais qualificado |

Fonte: <https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil/> e
<https://leadster.com.br/panorama-geracao-de-leads/>

**[FATO VERIFICADO]** Adoção de IA em geração de leads passou de ~4% em 2025, liderando em
Marketing (13,33%), Venda de Produtos (9,31%) e Tecnologia (8,97%).
Fonte: <https://leadster.com.br/panorama-geracao-de-leads/>

**[INFERÊNCIA — o achado mais acionável de toda a seção 10]** O tráfego vindo de IA
(ChatGPT e similares) converte a **7,80%**, mais que o dobro da mediana de 3,07% e mais que
o dobro do Google Ads. Isso muda a estratégia de captação: **quem chega via IA já veio
qualificado e com intenção formada**, e o widget deveria detectar esse referrer e mudar a
abordagem (menos qualificação, mais ação direta).

**[FATO VERIFICADO]** Registro histórico do posicionamento da Leadster: "mais de 300 sites,
gerando 30 mil leads por mês", com claim de "aumento de até 300% no volume de leads".
Fonte: <https://www.rdstation.com/integracoes/leadster-marketing-conversacional/>.
**Classificação: [FATO — FORNECEDOR]** para o "até 300%" — é claim de marketing, sem
metodologia. O "até" faz o trabalho pesado.

### 10.2 Chat vs formulário — a comparação central

| Achado | Número | Fonte | Confiança | Comentário |
|---|---|---|---|---|
| Formulários multi-etapa vs página única | **+25,4%** de conclusão | Formstack, **650.000+** submissões | **ALTA** | Amostra publicada; não é sobre chat, é sobre fracionamento |
| Idem, absolutos | **13,85%** vs **4,53%** | Formstack | **ALTA** | |
| Conversão de chat (chat-to-conversion) | **10–20%** | agregadores | BAIXA | Denominador ambíguo: % de *quem conversou*, não de *quem visitou* |
| Formulários web estáticos | **2–3%** | agregadores | BAIXA | Mesmo problema de denominador |
| Canais conversacionais com IA | **15–25%** | agregadores | BAIXA | |
| Sites B2B com live chat vs só formulário | **4,5× mais leads** | agregadores | BAIXA | Sem controle de confundidores |
| Leads de chat convertem | **8× mais rápido** | agregadores | BAIXA | |
| Conversacional vs tradicional | **+15% a +40%** | agregação incl. Typeform (2,6 mi formulários) | MÉDIA | |
| Typeform autodeclarado | **>50%** vs 20–30% do mercado | Typeform | **BAIXA — fornecedor** | |
| Popup conversacional | **15,2%** média | OptiMonk | **BAIXA — fornecedor** | |
| Formulários < 5 campos | tradicional **empata ou ganha** | agregação | MÉDIA | **Contraevidência importante** |

Fontes: <https://which-50.com/chat-to-conversion-rate-statistics-by-industry/>,
<https://tinycommand.com/blogs/conversational-forms-vs-traditional-forms-which-is-better-for-your-business>,
<https://databox.com/forms-vs-chat>,
<https://wonderchat.io/blog/b2b-website-conversion-report-2026>

**[FATO VERIFICADO — contraevidência que precisa constar]** Uma análise comparativa conclui
que **"live chat gera mais leads, mas formulários geram leads mais comprometidos"**.
Fonte: <https://databox.com/forms-vs-chat>

**[INFERÊNCIA — a armadilha do denominador]** A comparação "chat 10–20% vs formulário 2–3%"
é quase certamente **inválida como está publicada**, porque compara denominadores
diferentes:
- Formulário: conversões ÷ **visitantes da página**.
- Chat: conversões ÷ **pessoas que engajaram o chat**.

Quem abriu o chat já se autosselecionou como interessado. Comparar os dois é como comparar
a taxa de fechamento de um vendedor com a taxa de entrada de gente na loja. **A comparação
honesta é conversões-de-chat ÷ visitantes-totais**, e nesse denominador o número da Leadster
(mediana de ~3%) é o que temos de mais confiável para o Brasil.

### 10.3 Impacto de mensagem proativa

| Achado | Número | Fonte | Confiança |
|---|---|---|---|
| Sites com convite proativo vs reativo | **+40%** de conversão | Freshworks e agregadores | **BAIXA** |
| Engajamento proativo vs reativo | **3–5×** | agregadores | **BAIXA** |
| Redução de abandono de carrinho | **até −30%** | agregadores | **BAIXA** |
| Exit-intent (média) | **2,81%** de conversão | Wisepops, set/2025 | MÉDIA |
| Exit-intent (decil superior) | **19,63%** | Wisepops | MÉDIA |
| Exit-intent de e-mail | **1,8%** | Wisepops/OptiMonk | MÉDIA |
| Exit-intent de carrinho abandonado | **17,12%** (2025) | OptiMonk | MÉDIA |
| Exit-intent + chat simultâneo vs só popup | **+20–30%** de recuperação | CrazyEgg | **BAIXA** |
| Consumidores que dispensam IA que interrompe | **55%** | Clutch | **BAIXA** |

Fontes: <https://www.freshworks.com/live-chat/proactive-chat/>,
<https://www.crazyegg.com/blog/exit-popup/>,
<https://clutch.co/resources/fix-your-chatbot-ux>

**[NÃO VERIFICADO]** Procurei especificamente por um teste A/B público comparando
**teaser (balão ao lado) vs auto-open (painel abre sozinho)** e **não encontrei nenhum dado
comparativo publicado**. As fontes tratam isso como variável de A/B test recomendado, sem
resultado agregado. **Esta é a lacuna mais importante do relatório** — e é exatamente a
decisão que mais importa para o redesenho.
Fonte da constatação: <https://www.oscarchat.ai/blog/ab-test-chat-widget-conversions/>

### 10.4 Tempo de resposta × conversão

| Achado | Número | Fonte | Confiança |
|---|---|---|---|
| Contato em ≤ 5 min vs 30 min | **21× mais qualificação** | Lead Response Management Study / HBR | **ALTA** — estudo acadêmico/HBR |
| Esperar 5 min | risco de perder o lead **10×** maior | Drift | MÉDIA |
| Empresas que levam **> 5 dias úteis** para responder um lead do site | **55%** | Drift, State of Conversational Marketing | MÉDIA |
| Empresas testadas que responderam em ≤ 5 min | apenas **7%** de 433 | Drift | **ALTA** — metodologia publicada |
| Dos 10 mais rápidos, quantos usavam live chat | **todos os 10** | Drift | **ALTA** |
| Das 433 empresas, quantas usavam live chat | apenas **14%** | Drift | **ALTA** |
| Contato em ≤ 1 min | **+391%** de probabilidade de conversão | agregadores | BAIXA |

**Metodologia do estudo Drift [FATO VERIFICADO]:** a Drift preencheu formulários de lead,
demo e vendas em **433 sites B2B** e mediu quanto tempo cada empresa levou para responder,
por qualquer canal.
Fontes: <https://ainora.lt/blog/lead-response-time-statistics-every-study-2026>,
<https://setsmart.io/blog/lead-response-time-statistics>

**[INFERÊNCIA]** O estudo Drift é o dado mais forte a favor de chat de site que existe, e
ele **não fala de conversão de chat**: fala que **quem usa chat responde rápido, e quem
responde rápido qualifica 21× mais**. O mecanismo é a velocidade, não a interface. Um
widget lento a responder não herda esse benefício.

### 10.5 Chat com IA vs humano

| Achado | Número | Fonte | Confiança |
|---|---|---|---|
| Preferem humano a IA | **84,7%** (Metrigy) / **79%** / **93%** | Metrigy 2025-26, agregadores | MÉDIA a BAIXA (dispersão grande) |
| Preferem IA a humano | **8%** | SurveyMonkey 2025 | MÉDIA |
| Frustração com IA (out/25 → abr/26) | **54% → 59%** | estudo com 6.000 pessoas | MÉDIA |
| Desligariam ao serem conectados a IA | **29% → 31%** | idem | MÉDIA |
| Preferem humano para fraude/segurança | **70%** | SurveyMonkey | MÉDIA |
| Preferem humano para rastrear pedido | **19%** | SurveyMonkey | MÉDIA |
| Perderiam confiança se a IA não se identificasse | **14%** | Zendesk | BAIXA |
| Consumidores que acharam o chatbot **mais atencioso** que o humano | **69%** | Salesforce State of Service (citado) | **BAIXA — contradiz o resto** |
| Chatbots elevaram conversão | **+23%** | Glassix | **BAIXA — fornecedor** |
| Empresas relatando leads mais qualificados com IA | **64%** | agregadores | BAIXA |
| Custo por interação | **~US$ 0,50** (bot) vs **~US$ 6,00** (humano) | agregadores | BAIXA |

Fontes: <https://www.nojitter.com/customer-experience/consumers-overwhelmingly-prefer-human-agents-in-the-era-of-ai>,
<https://www.surveymonkey.com/curiosity/customer-service-statistics/>,
<https://www.answerconnect.com/blog/news/consumers-turning-away-from-ai-customer-service/>,
<https://www.glassix.com/article/study-shows-ai-chatbots-enhance-conversions-and-resolve-issues-faster>

**[INFERÊNCIA]** A dispersão (79% / 84,7% / 93% preferem humano, mas 69% acharam o bot mais
atencioso) revela que essas pesquisas medem coisas diferentes: **preferência declarada**
(quase sempre pró-humano) vs **satisfação experimentada** (frequentemente pró-bot, quando o
bot funciona). Para produto, a leitura é: **não pergunte ao usuário se ele quer bot — ele
vai dizer que não. Entregue um bot bom com saída fácil para humano e meça o comportamento.**

### 10.6 Live chat e conversão — os números clássicos

| Achado | Número | Fonte | Confiança |
|---|---|---|---|
| Visitantes que usam web chat vs os que não usam | **2,8× mais propensos a converter** | Forrester | MÉDIA — Forrester é independente, mas o dado circula sem o relatório |
| Aumento de ticket médio | **+10%** | Forrester | MÉDIA |
| Aumento de receita por hora de chat | **+48%** | Forrester | MÉDIA |
| "Chatters" gastam por compra | **+60%** | Invesp | BAIXA |
| Aumento típico de conversão ao adicionar live chat | **+20%** | agregadores | BAIXA |
| Live chat eleva conversão geral | **+10–30%** | agregadores | BAIXA |
| E-commerce com chat | **até +70%** | agregadores | **MUITO BAIXA** |

Fontes: <https://www.forrester.com/blogs/retailers-without-chat-a-missed-opportunity/>,
<https://knockknockapp.ai/blogs/7-studies-that-prove-live-chat-boosts-your-conversion-rate/>,
<https://www.campaignmonitor.com/resources/knowledge-base/how-much-does-live-chat-increase-conversions/>

**[INFERÊNCIA — o confundidor que ninguém controla]** O "2,8× mais propensos a converter"
da Forrester é **correlação, não causalidade**. Quem abre o chat é quem tem dúvida séria e
intenção de compra. Não sabemos quanto do 2,8× é o chat causando conversão e quanto é a
intenção causando as duas coisas. Nenhum dos estudos citados usa grupo de controle
randomizado.

### 10.7 CSAT em chat

**[FATO — AGREGADOR, mas consistente]**

| Canal da pesquisa | Taxa de resposta |
|---|---|
| **In-chat, ao fim da conversa** | **30–40%** |
| CSAT geral | 20–30% comum, >40% forte |
| CSAT em site (não in-chat) | 8–15% |
| Link em e-mail de follow-up | **5–10%** (o pior) |
| Dos que avaliam, quantos deixam comentário | **30–40%** |

Fontes: <https://supp.support/blog/how-to-set-up-csat-surveys>,
<https://www.customersure.com/guides/survey-response-rates/>

**[INFERÊNCIA]** O CSAT in-chat é o canal de feedback com melhor taxa de resposta que
existe, por uma margem de 3–6× sobre e-mail. Se o ChatSPX já tem a UI de CSAT (e tem),
**usá-la por padrão é dinheiro no chão que ninguém está pegando**.

### 10.8 Abandono e número de perguntas

| Achado | Número | Fonte | Confiança |
|---|---|---|---|
| Campos médios no checkout (2024) | **11,3** (era 11,8 em 2021 e 12,7 em 2019) | Baymard | **ALTA** |
| Campos necessários | **8** | Baymard | **ALTA** |
| Etapas médias do checkout | **5,1** | Baymard | **ALTA** |
| Abandono por complexidade do checkout | **17%** | Baymard | **ALTA** |
| Abandono médio de carrinho | **70,22%** (50 estudos) | Baymard | **ALTA** |
| Ganho de conversão com melhor design de checkout | **~35%** em sites grandes | Baymard | **ALTA** |
| Queda de conclusão por campo além do 8º | "4–6%" | atribuído à Baymard | **NÃO VERIFICADO** — não localizei no artigo primário |
| Meta de abandono em funil conversacional | **< 30%** | agregadores | BAIXA |
| Abandono de live chat sem resposta rápida | **~50%** | agregadores | BAIXA |
| Botões guiados antes de texto livre (2–3 trocas) | **+41%** de perfis completos | BotHero | MÉDIA |
| Mais de 4 botões de uma vez | **+22%** de abandono em mobile | BotHero | MÉDIA |

Fonte principal: <https://baymard.com/blog/checkout-flow-average-form-fields>

### 10.9 Por dispositivo

| Métrica | Desktop | Mobile |
|---|---|---|
| Participação de tráfego (global, jan/2026) | ~35% | **62–64%** |
| Participação de tráfego (e-commerce) | ~30% | **até 70%** |
| Conversão | **3,5–4,0%** | **1,8–2,5%** |
| Brasil — minutos digitais | — | **72%** |

Fonte: <https://sqmagazine.co.uk/mobile-vs-desktop-statistics/>,
<https://sqmagazine.co.uk/e-commerce-conversion-rate-statistics/>

### 10.10 Tabela-resumo — o que eu usaria para decidir

**[INFERÊNCIA]** Se eu tivesse que citar só cinco números numa reunião de produto, seriam
estes — todos com metodologia publicada:

| # | Número | O que sustenta | Confiança |
|---|---|---|---|
| 1 | **Mediana de conversão de sites BR: 2,98% (2025) / 3,07% (2026)**, com 17 segmentos entre 1,52% e 5,40% | Meta realista; nenhuma promessa de "300%" | **ALTA** (mas amostra = clientes Leadster) |
| 2 | **Multi-etapa converte 13,85% vs 4,53% de página única** (650k submissões) | Fracionar a pergunta é o mecanismo real, não "ser chat" | **ALTA** |
| 3 | **8 campos bastam; 17% abandonam por complexidade** | Teto duro para o formulário conversacional | **ALTA** |
| 4 | **Responder em ≤5 min qualifica 21× mais; só 7% de 433 empresas conseguem** | O valor do chat é a velocidade | **ALTA** |
| 5 | **Barra de progresso: +10–15%; progresso dotado 19% → 34%** | Custo de implementação quase nulo | **ALTA** (estudo acadêmico) |

---

## 11. Copy e tom

### 11.1 Exemplos reais brasileiros com taxa de conversão medida

**[FATO VERIFICADO]** Este é o material mais valioso de copy que encontrei: a Leadster
publica chamadas reais **com a taxa de conversão de cada uma**, por segmento. Transcrição
literal:

**Jurídico**
| Chamada | Conversão |
|---|---|
| "Procurando Advogado Trabalhista?" | 2,14% |
| "Vamos descobrir como podemos ajudar no seu caso?" | 2,00% |
| "Vamos dar andamento no seu divórcio?" | 2,00% |

**Seguros**
| Chamada | Conversão |
|---|---|
| "Vamos descobrir qual é o plano ideal pra você?" | **6,60%** |
| "Quer falar com nosso consultor agora mesmo?" | 6,20% |
| "Vamos consultar o Preço para a sua Cotação em 5 min?" | 6,00% |

**Financeiro**
| Chamada | Conversão |
|---|---|
| "Vamos descobrir qual é o serviço ideal para sua necessidade?" | **6,60%** |
| "Gostaria de realizar seu orçamento em 5 min?" | **6,60%** |
| "Descubra se você está pagando juros abusivos em 5 minutos" | 6,50% |

**Educacional**
| Chamada | Conversão |
|---|---|
| "Quer conhecer o Curso Ideal pra você?" | 5,70% |
| "Quer saber mais sobre o método?" | 5,50% |
| "Quer receber uma proposta personalizada para matrícula?" | 5,40% |

**Telefonia / Internet**
| Chamada | Conversão |
|---|---|
| "Posso ajudar você a encontrar o melhor plano de internet?" | 4,50% |
| "Deseja uma internet fibra óptica de alta velocidade com suporte local?" | 4,50% |
| "Que tal um desconto especial?" | 4,40% |

**Software**
| Chamada | Conversão |
|---|---|
| "Quer ver uma Demonstração Personalizada para a sua empresa?" | 4,30% |
| "Quer saber como (insira o principal benefício que seu produto entrega)" | 4,20% |
| "Quer saber quanto vai custar o seu Projeto?" | 3,90% |

**Venda de bens e serviços**
| Chamada | Conversão |
|---|---|
| "Gostaria de saber mais sobre o (nome do produto)?" | 4,20% |
| "Gostaria de uma negociação especial de preços?" | 4,20% |
| "Quer saber mais sobre as soluções indicadas pra você?" | 4,10% |

**B2B**
| Chamada | Conversão |
|---|---|
| "Quer saber como (insira o principal benefício que seu produto entrega)" | 3,60% |
| "Está precisando (insira a principal necessidade dos clientes)" | 3,20% |
| "Gostaria de ter acesso ao nosso catálogo com preços?" | 3,20% |

**Imobiliário**
| Chamada | Conversão |
|---|---|
| "Quer receber mais detalhes desse imóvel no seu WhatsApp?" | 2,60% |
| "Temos uma condição especial pra você. Quer saber qual é?" | 2,60% |
| "Quer ajuda para encontrar o imóvel ideal?" | 2,40% |

Fonte: <https://leadster.com.br/blog/textos-para-chatbots/>

### 11.2 Padrões de copy que emergem desses dados

**[INFERÊNCIA — análise dos 27 exemplos acima]**

| Padrão | Observação | Exemplo |
|---|---|---|
| **Pergunta, nunca afirmação** | 26 dos 27 exemplos terminam em "?" | "Vamos descobrir…?" |
| **Primeira pessoa do plural ("vamos")** | As duas maiores conversões (6,60%) usam "Vamos descobrir…" | Convida a fazer *junto*, não pede permissão para vender |
| **Promessa de tempo curto** | "em 5 min" aparece nas 3 primeiras de Financeiro e Seguros | Reduz o custo percebido de entrar |
| **"pra você" / "para a sua empresa"** | onipresente | Personalização gramatical barata e eficaz |
| **Verbo de descoberta** | "descobrir", "conhecer", "saber" | Enquadra como ganho de informação, não como compra |
| **Especificidade do segmento** | "Advogado Trabalhista", "fibra óptica", "juros abusivos" | Genérico converte menos que específico |
| **Nenhum emoji** | zero emojis nos 27 exemplos | ver 11.4 |
| **Sem "Olá, como posso ajudar?"** | nenhuma ocorrência | Confirma o achado do NN/g (A8) |
| **Menção ao canal de destino** | "no seu WhatsApp" | Reduz ansiedade sobre o que vem depois |

**[INFERÊNCIA]** A regra sintática que resume tudo:

> **[Verbo de descoberta na 1ª pessoa do plural ou 2ª pessoa] + [benefício específico do
> segmento] + [para você] + [restrição de tempo, se houver] + "?"**

Exemplos derivados: "Vamos descobrir qual plano cabe no seu orçamento?" /
"Quer ver quanto custaria o seu projeto em 2 minutos?"

### 11.3 Personalização por página e por origem

**[FATO VERIFICADO]** A Leadster comercializa "chamadas inteligentes" que consideram
contexto para chamar a atenção do visitante de forma mais efetiva e personalizada, e
suporta **personalizar conversas por dispositivo**.
Fontes: <https://help.leadster.com.br/article/47-como-configurar-as-chamadas-inteligentes>,
<https://leadster.com.br/blog/leadster-como-funciona/>

**[FATO — FORNECEDOR]** "Personalização tende a aumentar taxas de conversão em até 40%."
Fonte: <https://leadster.com.br/blog/leadster-como-funciona/>. **Confiança baixa** — claim
de marketing, "até 40%".

**[INFERÊNCIA — matriz de personalização recomendada]**

| Dimensão | Sinal disponível | Como usar na copy |
|---|---|---|
| **Página** | URL / path | `/precos` → "Ficou com dúvida em algum plano?" ; `/produto/X` → "Quer saber se o X atende o seu caso?" |
| **Origem** | `document.referrer`, UTM | Google Ads → foco na promessa do anúncio; **IA/ChatGPT → ir direto ao ponto (converte 7,80%)**; orgânico → mais educativo |
| **Dispositivo** | user agent | Mobile → copy mais curta, oferta de WhatsApp |
| **Recorrência** | cookie | 2ª visita → "Que bom te ver de novo. Continuamos de onde parou?" |
| **Horário** | hora local | Fora do horário → mudar promessa de retorno |
| **Geo** | IP | Cidade/estado — e **pular a pergunta de localização** |
| **Profundidade** | scroll | > 70% de um artigo longo → oferecer o material em PDF por e-mail |

### 11.4 Emoji

**[FATO VERIFICADO — pesquisa acadêmica, resultado dependente de contexto]**

- Em comunicação **informacional ou de saúde**, emojis **prejudicaram** a qualidade de
  informação percebida e a profissionalidade; participantes relataram **menor intenção de
  recomendar ou usar** o chatbot que respondia a autorrevelação com emoji.
  Fonte: <https://www.sciencedirect.com/science/article/pii/S074756322600052X>
- Em contextos **informais** (recomendação de restaurante), emojis **aumentaram**
  atratividade, competência e credibilidade percebidas vs chatbot só-texto.
  Fonte: <https://www.tandfonline.com/doi/abs/10.1080/10510974.2020.1725082>
- **Congruência importa**: quando o emoji está semanticamente alinhado com o texto, o
  usuário percebe o chatbot como mais competente, o que aumenta a satisfação.
  Fonte: <https://link.springer.com/article/10.1007/s43039-025-00126-w>
- Em contexto profissional, emojis **prejudicam** percepções de profissionalidade — mas um
  estilo de linguagem informal **reverte** esse efeito negativo.
  Fonte: <https://online.ucpress.edu/collabra/article/12/1/147309/217078/Emojis-at-Work-The-Effects-of-Emoji-Use-on>
- Há diferença cultural: participantes chineses foram largamente **não afetados** pela
  presença de emoji.
  Fonte: <https://www.sciencedirect.com/science/article/pii/S074756322600052X>

**[INFERÊNCIA — regra prática]** Emoji funciona quando (a) o assunto é leve, (b) a
linguagem ao redor já é informal, e (c) o emoji é congruente com o texto. Emoji **não**
funciona em assunto sério (saúde, jurídico, financeiro, cobrança) nem colado a linguagem
formal. Note que **os 27 exemplos brasileiros de maior conversão da Leadster não têm um
único emoji** — o que é consistente com o fato de que os segmentos de maior conversão
(seguros, financeiro, jurídico) são exatamente os de assunto sério.

**Recomendação:** emoji **desligado por padrão**, com controle por conta/fluxo. No máximo
um por mensagem, nunca no meio da frase.

### 11.5 Português do Brasil — armadilhas específicas

**[INFERÊNCIA]**

| Armadilha | Errado | Certo |
|---|---|---|
| Tradução mecânica | "é mandatório" | "é obrigatório" |
| Você/tu inconsistente | mistura na mesma sessão | fixar "você" |
| Formalidade excessiva | "Prezado usuário, solicitamos que…" | "Pode me dizer seu nome?" |
| Gerundismo | "vou estar verificando" | "vou verificar" / "já verifico" |
| Estrangeirismo desnecessário | "aguarde nosso follow-up" | "a gente te retorna" |
| Erro genérico | "Forneça uma entrada válida" | "Faltou o @ no e-mail" |
| Chamada sem sujeito | "Ajuda?" | "Posso te ajudar com os planos?" |
| Gênero presumido | "Bem-vindo!" | "Boas-vindas!" / "Que bom te ver!" |

### 11.6 A primeira mensagem — checklist

**[INFERÊNCIA — síntese de NN/g + dados Leadster]** A primeira mensagem tem 5 segundos para
fazer três coisas:

1. **Dizer quem fala** — nome + papel, ou "assistente virtual" se for bot.
2. **Sinalizar o escopo** — 2 a 4 opções concretas, não "como posso ajudar?".
3. **Convidar com baixo custo** — a primeira ação deve ser um clique, não digitação.

```
┌──┐ Ana · Consultora ChatSPX
│AV│ ──────────────────────────
└──┘
┌────────────────────────────────────┐
│ Oi! Vi que você está vendo os      │  ← contexto da página
│ planos. Posso te ajudar a          │  ← "vamos/posso" + benefício
│ escolher o ideal pro seu time?     │  ← "pra você/seu"
└────────────────────────────────────┘
        [ Ver preços ]  [ Falar com alguém ]  [ Só olhando ]
                                                    ↑
                         "Só olhando" é a saída digna — reduz a
                         sensação de estar sendo abordado
```

**[INFERÊNCIA]** A opção "Só olhando" (ou "Depois eu vejo") é um detalhe pequeno com efeito
grande: dá ao usuário uma saída que **não é** o "✕", transformando a dispensa numa
interação registrada — o que serve tanto ao usuário (não se sente perseguido) quanto ao
produto (você aprende quantos dispensam e em que página).

---

## 12. LGPD e consentimento na UX

### 12.1 O que a LGPD exige que aparece na interface

**[FATO VERIFICADO]** Requisitos consolidados aplicados a chatbots no Brasil:

- A conformidade com a LGPD é essencial para qualquer empresa que use chatbots e algoritmos
  no tratamento de dados pessoais.
- O consentimento deve ser obtido de forma **clara, transparente e informada**, com
  explicação em **linguagem simples e acessível** sobre como os dados serão coletados,
  armazenados e usados pelo chatbot.
- O titular pode **solicitar exclusão**, anonimização ou bloqueio dos dados, **revogar o
  consentimento a qualquer momento** e receber os dados em formato estruturado.
- Problemas de conformidade recorrentes: **coleta automática de dados sem aviso prévio** e
  **textos longos e confusos** que atrapalham o entendimento.

Fontes: <https://www.contabeis.com.br/artigos/69603/lgpd-para-chatbots-e-ia-como-garantir-a-conformidade/>,
<https://getbots.com.br/blog/lgpd-chatbots-para-empresas-devem-estar-adequados-a-legislacao/>,
<https://ageubot.com.br/blog/politica-privacidade-chatbot/>,
<https://inbot.com.br/chatbots/como-adequar-seu-chatbot-a-lgpd/>

### 12.2 O que o mercado brasileiro efetivamente faz

**[FATO VERIFICADO — padrão de texto observado]** O padrão dominante em sites brasileiros é
o consentimento implícito por continuidade: *"Ao continuar navegando, você concorda com
nossa Política de Privacidade"*, e variantes como *"Ao utilizar nossos serviços, você
concorda com a coleta, armazenamento e uso das informações descritas nesta Política de
Privacidade"*.
Fontes: <https://www.chatbrasil.net/Privacidade/>, <https://appconversinha.com/privacy>

**[INFERÊNCIA — o diagnóstico honesto]** Na prática, o mercado brasileiro de chat de site
faz o **mínimo defensável e frequentemente menos que isso**:

| Prática | Frequência observada | Adequação |
|---|---|---|
| Link para política de privacidade no rodapé do widget | comum | mínimo |
| Aviso de uma linha antes de pedir dado | ocasional | razoável |
| Checkbox de opt-in explícito no chat | raro | seria o correto para marketing |
| Consentimento por continuidade ("ao continuar você concorda") | dominante | **frágil** — a LGPD pede consentimento livre, informado e inequívoco |
| Base legal declarada (consentimento vs legítimo interesse) | raríssimo | — |
| Botão de excluir meus dados dentro do chat | praticamente inexistente | — |

**[INFERÊNCIA]** O consentimento por continuidade é frágil para **finalidade de marketing**.
Para responder a uma dúvida iniciada pelo próprio titular, "execução de procedimentos
preliminares relacionados a contrato" ou legítimo interesse são bases mais sólidas que
consentimento. Mas **enviar campanha depois** (o que é o objetivo do widget de captação)
é outra finalidade e precisa de consentimento próprio. **Esta distinção — atender ≠ fazer
marketing depois — é onde quase todo widget brasileiro está exposto.**

*(Isto é leitura de produto, não parecer jurídico. Vale validar com jurídico antes de virar
requisito.)*

### 12.3 Padrão de UX recomendado para consentimento em chat

**[INFERÊNCIA]**

```
Momento 1 — abertura do chat: NADA. Não peça nada.
            (a pessoa ainda não deu dado nenhum)

Momento 2 — antes do primeiro dado pessoal (nome/telefone/e-mail):
            uma linha discreta, 11–12px, abaixo do campo:

            ┌────────────────────────────────────────────────┐
            │ Seus dados são usados só para te responder.     │
            │ Saiba mais na Política de Privacidade.          │
            └────────────────────────────────────────────────┘

Momento 3 — se houver intenção de marketing posterior:
            checkbox EXPLÍCITO, desmarcado por padrão:

            ☐ Quero receber novidades e ofertas por e-mail/WhatsApp
```

Regras:
- **Nunca** pré-marcar o checkbox de marketing.
- **Nunca** bloquear o atendimento por recusa do opt-in de marketing.
- O link da política **abre em nova aba**, jamais dentro do widget (perder a conversa por
  clicar na política é um anti-padrão silencioso).
- O texto na altura do campo, não num modal antes do chat — o modal antes do chat empilha
  com o banner de cookies e cai no anti-padrão A5.

### 12.4 Colisão com o banner de cookies

**[INFERÊNCIA]** Desde a consolidação da LGPD, praticamente todo site brasileiro tem banner
de cookies no rodapé — exatamente onde fica o launcher. Isso cria:
1. **Sobreposição visual** — o launcher fica atrás ou por cima do banner.
2. **Empilhamento de dispensa** — o usuário tem de fechar duas coisas (anti-padrão A5,
   Nielsen).
3. **Ordem errada** — o teaser aparecendo antes de o banner de cookies ser resolvido.

**Recomendação:** (a) API para o site informar a altura do banner de cookies e o widget se
deslocar; (b) **não disparar teaser enquanto o banner de cookies estiver visível**;
(c) detecção automática de elementos `position: fixed` no canto inferior como fallback.

### 12.5 Nota sobre disclosure de bot no Brasil

**[FATO VERIFICADO]** Nos EUA, a Califórnia tem lei explícita (Bolstering Online
Transparency Act) exigindo divulgação de bot em certas condições, e é o **único estado**
com lei desse tipo; fora dela, a FTC atua via proibição geral de práticas enganosas.
Fontes: <https://www.termsfeed.com/blog/ca-bot-disclosure-law/>,
<https://www.internetlawyer-blog.com/are-you-required-to-disclose-when-website-users-are-interacting-with-an-ai-bot/>

**[NÃO VERIFICADO]** Não localizei, nesta pesquisa, lei brasileira específica que **obrigue**
a divulgar que o interlocutor é um bot. O PL de IA e o CDC podem alcançar o tema por
princípio de transparência, mas **não confirmei** nenhuma norma vigente específica.
Registrado como lacuna, não como fato.

**[INFERÊNCIA]** Independente de obrigação, rotular é a decisão certa: o custo é uma linha
de texto; o risco de não rotular é o item A12 da seção 9.

---

## 13. Observação de campo — quem usa o quê

### 13.1 Método

Varredura via `curl` (User-Agent de Chrome desktop) do HTML servido pelas home pages, com
detecção por assinatura de script (`widget.intercom.io`, `static.zdassets.com`,
`js.driftt.com`, `code.tidio.co`, `client.crisp.chat`, `code.jivosite.com`,
`hs-scripts.com`, `embed.tawk.to`, `sdk.chatwoot`, etc.), em 11/08/2026.

**Limitação importante [FATO VERIFICADO]:** o método só enxerga o que está no HTML inicial.
Sites em SPA (React/Next com hidratação) ou que injetam o widget via Google Tag Manager
aparecem como "nenhum detectado". Portanto **ausência aqui não é prova de ausência de
widget** — as detecções positivas são confiáveis, as negativas não.

### 13.2 Resultados — Brasil

| Site | Detectado |
|---|---|
| leadster.com.br | **Leadster** |
| resultadosdigitais.com.br | RD Station, Front |
| rdstation.com | RD Station, link WhatsApp, Front |
| linx.com.br | RD Station, Front |
| totvs.com | RD Station, HubSpot |
| movidesk.com | **Zenvia** |
| take.net | HubSpot, **Blip**, link WhatsApp |
| hostgator.com.br | **JivoChat** |
| omie.com.br | HubSpot |
| gympass.com | HubSpot, link WhatsApp |
| pipefy.com | HubSpot, LiveChat |
| locaweb.com.br | link WhatsApp |
| magazineluiza.com.br | — (SPA) |
| americanas.com.br | — (SPA) |
| nubank.com.br | — (SPA) |
| contaazul.com | — (SPA) |
| sympla.com.br | — (SPA) |
| zenvia.com | — (SPA) |

### 13.3 Resultados — global

| Site | Detectado |
|---|---|
| chatwoot.com | **Chatwoot** |
| crisp.chat | **Crisp**, LiveChat |
| zendesk.com | **Zendesk**, LiveChat, Front |
| hubspot.com | **HubSpot** |
| intercom.com | HubSpot |
| tidio.com | Tidio, JivoChat, HubSpot, Tawk, LiveChat, Gorgias *(página comparativa — menciona todos)* |
| stripe.com | Front |
| shopify.com | Front |
| notion.com | HubSpot, Front |
| atlassian.com | HubSpot, Front |

### 13.4 Leituras

**[FATO VERIFICADO]** A Intercom não usa Intercom na própria home (detectou HubSpot).
**[INFERÊNCIA]** Provavelmente o widget é injetado por GTM/SPA e o `curl` não vê. Não é
conclusão de que não usam.

**[INFERÊNCIA — o achado mais relevante para o ChatSPX]** No Brasil, o padrão dominante nas
empresas de médio/grande porte **não é um widget de chat**: é o **link de WhatsApp** e, em
segundo lugar, o **formulário de RD Station / HubSpot**. Os grandes varejistas
(Magalu, Americanas) e o Nubank não expõem widget de chat no HTML inicial da home. Isso
significa que:

1. O concorrente real do nosso widget web no Brasil é o **botão de WhatsApp**, não o
   Intercom.
2. Qualquer widget web brasileiro que não trate o WhatsApp como destino de primeira classe
   está brigando contra o hábito nacional.
3. A jogada da Leadster de permitir **o ícone do WhatsApp como avatar do assistente**
   (seção 5.2) e de ter chamadas do tipo "Quer receber mais detalhes no seu WhatsApp?"
   (2,60% de conversão, seção 11.1) não é detalhe: é o reconhecimento de que o web chat
   brasileiro é, muitas vezes, **uma antessala do WhatsApp**.

---

## 14. IMPLICAÇÕES PARA O CHATSPX

Recomendações apenas — nenhuma implementação, nenhum código. Ordenadas por
**(impacto esperado ÷ esforço)**, com a evidência que sustenta cada uma.

### 14.1 Correções de alto impacto e baixo esforço

| # | Recomendação | Evidência | Seção |
|---|---|---|---|
| **R1** | **Corrigir "mandatório" → "obrigatório"** e revisar todo o i18n pt-BR do widget por tradução mecânica. | String real: `"Nome Completo é mandatório"` | 3.5 |
| **R2** | **Trocar `REGEX_ERROR = "Forneça uma entrada válida"` por erros específicos por campo.** Erro deve dizer o que fazer. | Anti-padrão A14; Baymard | 3.5, 9.1 |
| **R3** | **Traduzir o `title` do launcher.** Hoje é `'Open chat window'` hardcoded em `bubbleHelpers.js`, enquanto `BUBBLE.LABEL = "Fale conosco no chat"` existe traduzido e não é usado. Vazamento de i18n na camada de acessibilidade. | Leitura de código | 8.1 |
| **R4** | **Ligar CSAT por padrão.** A UI já existe (`CSAT.TITLE = "Avalie sua conversa"`). CSAT in-chat tem 30–40% de resposta contra 5–10% de e-mail. | Benchmarks de CSAT | 10.7 |
| **R5** | **Trocar `100vh` por `dvh` com fallback** no CSS do SDK e revisar o fullscreen mobile com teclado aberto. Forte candidato a bug real em iOS. | Bug documentado do `100vh`; código atual usa `max-height: 100vh` | 8.3 |
| **R6** | **Derivar a string de tempo de resposta de métrica real da inbox**, em vez de valor configurado à mão. As chaves `REPLY_TIME.*` já suportam isso. | "Faça a promessa corresponder à realidade"; anti-padrão A11 | 5.4, 6.4 |

### 14.2 Comportamento proativo — a decisão mais importante

| # | Recomendação | Evidência |
|---|---|---|
| **R7** | **Implementar teaser (balão ao lado da bolha), nunca auto-open do painel.** Toda a reclamação documentada de usuário final é contra o auto-open; nenhuma é contra o teaser. | HN 24834779; Nielsen |
| **R8** | **Gatilho composto, nunca só tempo:** mínimo de 8s **e** 30% de scroll, ou entrada em página de alta intenção. Nunca antes de o usuário ler o título da página. | Recomendações consolidadas de trigger; citação literal do GordonS |
| **R9** | **A dispensa é permanente na sessão e persistida por cookie por N dias.** Um "✕" que não persiste é o item A3. | "anything that I would want to dismiss and then it doesn't persist" |
| **R10** | **Copiar a "ocultação pós-conversão" da Leadster:** sumir por 7 dias depois que o visitante converteu, e para leads desqualificados. Custo baixíssimo, mata o anti-padrão A2. | Config documentada da Leadster |
| **R11** | **Nenhum som. Nunca. Nem opcional-ligado-por-padrão.** 92% acham autoplay irritante; >1/3 abandona o site. | Jakob Nielsen, Top 10 UI Annoyances |
| **R12** | **Botão "Só olhando" na primeira mensagem** como dispensa digna e mensurável. | Inferência; reduz sensação de abordagem |
| **R13** | **Rodar A/B interno de teaser vs auto-open.** Não existe dado público comparando os dois — é a maior lacuna do estudo, e nós temos frota para medir. | Lacuna registrada em 10.3 |

### 14.3 Formulário conversacional

| # | Recomendação | Evidência |
|---|---|---|
| **R14** | **Teto de 8 campos no fluxo inteiro.** Baymard: 8 bastam; 17% abandonam por complexidade; o que conta é o nº de campos, não de etapas. | Baymard (confiança ALTA) |
| **R15** | **Ordem: 3 perguntas de clique antes de pedir qualquer dado pessoal.** Bots que guiam por 2–3 trocas antes de texto livre capturam +41% de perfis completos. | BotHero; endowed progress |
| **R16** | **Pedir e-mail OU WhatsApp, nunca os dois.** Cada campo é fricção; no Brasil o WhatsApp é o canal real. | Baymard; observação de campo 13.4 |
| **R17** | **Máscaras e validadores BR nativos** (celular, fixo, CPF, CNPJ, CPF-ou-CNPJ no mesmo campo, CEP com ViaCEP, data), validando **no blur**, com máscara aplicada na digitação, aceitando entrada suja. Hoje o widget não tem nada disso. | Padrão BR consolidado |
| **R18** | **Enriquecimento automático para eliminar perguntas:** cidade/estado por IP, UTM, dispositivo, recorrência, endereço por CEP. | Prática documentada da Leadster |
| **R19** | **Indicador de progresso** ("Pergunta 2 de 4") com *endowed progress* honesto. +10–15% de conclusão; 19% → 34% no estudo original. | Nunes & Dreze (2006); confiança ALTA |
| **R20** | **Erro do bot é mensagem do bot**, não label vermelho. É a vantagem estrutural do formato conversacional e hoje não é explorada. | Inferência |

### 14.4 Componentes e limites de canal

| # | Recomendação | Evidência |
|---|---|---|
| **R21** | **Validar limites de canal no editor de fluxo**, não na entrega. WhatsApp: 3 botões de 20 chars, lista de 10 itens de 23–24 chars, título 24, header 60. Já existe issue aberta no upstream (#8288) sobre estourar limite e tratar errado. | Limites Meta; issue Chatwoot #8288 |
| **R22** | **2 a 4 quick replies por vez, com revelação progressiva.** >4 botões = +22% de abandono em mobile. | BotHero |
| **R23** | **Nunca desabilitar o composer durante fluxo guiado.** Botões + campo livre sempre, simultaneamente. | NN/g (descoberta) + "no one will click on my buttons" (comportamento) |
| **R24** | **Primeira mensagem com 2–4 opções nomeadas e concretas**, jamais "Como posso ajudar?". O usuário decide em 5s se a ferramenta serve. | NN/g |

### 14.5 Sinais de vida e handoff

| # | Recomendação | Evidência |
|---|---|---|
| **R25** | **Botão "falar com humano" sempre visível.** Esconder a saída *reduz* a paciência com o bot; deixar visível aumenta a deflexão. Contraintuitivo e bem sustentado. | Cobbai / literatura de escalonamento |
| **R26** | **Rotular o bot como bot, sempre.** Nome de bot ≠ nome humano; avatar de bot ≠ foto de pessoa. | FTC; 14% perdem confiança |
| **R27** | **Nunca simular digitação de humano.** Simular digitação de *bot* é aceitável e recomendado (600ms–3s, teto de 4s); simular a de humano é mentira. | Estudo do typing indicator; anti-padrão A12 |
| **R28** | **Fila com posição, atualizada a cada 60–90s**, e aos 120s oferecer `[Receber por e-mail]` `[Receber no WhatsApp]` `[Continuar esperando]`. | Práticas de handoff consolidadas |
| **R29** | **A primeira frase do humano deve citar o que o bot coletou.** É o sinal mais barato de que a transferência funcionou. | "sem precisar reexplicar" |
| **R30** | **`read` receipt: não mostrar** por padrão. Mostrar `sent`/`delivered`/`failed` sempre. "Lido e não respondido" é dívida visível. | Inferência sobre assimetria do padrão WhatsApp |
| **R31** | **Fora do horário o widget continua captando**, com promessa honesta e específica ("respondemos em até X"). As chaves `BACK_AT_TIME`/`BACK_TOMORROW` já existem. | "A promessa tem de corresponder à realidade" |

### 14.6 Visual, tema e acessibilidade

| # | Recomendação | Evidência |
|---|---|---|
| **R32** | **Dark mode em três estados** (`light`/`dark`/`auto`), com `auto` como padrão. Atenção: `color-scheme: normal` no iframe do SDK é o ponto onde o tema do host para de valer. | Modelo da Intercom; leitura do CSS atual |
| **R33** | **Priorizar o quarteto percebido: cor + logo + textos + branding removível.** Tamanho de bolha e raio de canto não vendem — Intercom e Zendesk nem deixam mudar. | Comparativo 7.2 |
| **R34** | **Respeitar `prefers-reduced-motion`** em todas as transições da bolha (hoje há `rotate(45deg)`, `scale(.75)`, `translateX`). | Acessibilidade percebida |
| **R35** | **Auditar contraste do texto secundário** (timestamps, status, "Desenvolvido por") e o tamanho dos alvos de "✕". | WCAG 2.2 AA |
| **R36** | **`role="log"` + `aria-live="polite"` na lista**, foco no composer ao abrir, foco no launcher ao fechar (isto último já está certo). | Checklists WCAG para chat |
| **R37** | **Atualizar o breakpoint de `667px` para `640px` ou `768px`.** 667px é a largura do iPhone 6/7/8 em landscape — está datado. | Leitura do CSS atual |
| **R38** | **API de offset para o banner de cookies**, e não disparar teaser enquanto o banner estiver visível. | Colisão LGPD × launcher; anti-padrão A5 |

### 14.7 Performance

| # | Recomendação | Evidência |
|---|---|---|
| **R39** | **Carregar o widget na primeira interação real** (`mousemove`/`scroll`/`touchstart`), não no `load`. Zero impacto em Core Web Vitals para quem nunca interage. | corewebvitals.io |
| **R40** | **Não copiar o truque do Crisp de ignorar Lighthouse/GTmetrix.** Resolve o relatório e não resolve o usuário. Fazer R39 dá o mesmo resultado de forma honesta. | Leitura do `l.js` v4.9.2 |
| **R41** | **Orçamento de peso explícito:** referência de mercado é 155 KB (leves) a 750 KB (pesados). Medir onde estamos. | pagespeedfix |

### 14.8 Copy e captação (Brasil)

| # | Recomendação | Evidência |
|---|---|---|
| **R42** | **Adotar a fórmula de chamada validada:** `[verbo de descoberta em 1ª pessoa do plural] + [benefício específico do segmento] + [pra você] + [tempo curto] + "?"`. As duas chamadas de maior conversão (6,60%) usam "Vamos descobrir…". | 27 chamadas com conversão medida |
| **R43** | **Biblioteca de chamadas por segmento pré-carregada no produto**, com as taxas de referência da tabela 11.1 como expectativa realista. | Leadster / Panorama |
| **R44** | **Emoji desligado por padrão**, com controle por conta. Os 27 exemplos de maior conversão no Brasil não têm nenhum. | Literatura acadêmica de emoji + dados BR |
| **R45** | **Detectar referrer de IA (ChatGPT e similares) e mudar a abordagem:** esse tráfego converte a 7,80%, mais que o dobro da mediana e do Google Ads. Menos qualificação, mais ação direta. | Panorama 2026 |
| **R46** | **Tratar o WhatsApp como destino de primeira classe** do widget web: avatar de WhatsApp, chamada "Quer receber no seu WhatsApp?", handoff explícito. No Brasil o concorrente real do nosso widget é o botão de WhatsApp, não o Intercom. | Varredura de campo 13.2 + prática da Leadster |
| **R47** | **Metas realistas nos materiais do produto:** mediana brasileira de 2,98–3,07%; 1,52% (imóveis) a 5,40% (telefonia). Nunca prometer "300%". | Panorama, 5 edições |

### 14.9 Consentimento

| # | Recomendação | Evidência |
|---|---|---|
| **R48** | **Aviso de privacidade de uma linha na altura do primeiro campo pessoal**, não modal antes do chat. | Requisitos LGPD + anti-padrão A5 |
| **R49** | **Separar "atender" de "fazer marketing depois":** checkbox explícito e **desmarcado** para marketing, sem bloquear o atendimento se recusado. É onde quase todo widget BR está exposto. | Leitura de LGPD (validar com jurídico) |
| **R50** | **Link da política abre em nova aba**, nunca dentro do widget. | Inferência — perder a conversa por clicar na política é anti-padrão silencioso |

### 14.10 O teste que resume tudo

**[INFERÊNCIA]** Se a equipe de produto e design só levar uma coisa deste documento, que
seja o **Teste do Vendedor** (seção 9.2):

> Se um vendedor de loja física fizesse exatamente isto comigo — neste momento da minha
> visita, com esta frase, neste tom, esta quantidade de vezes — eu acharia normal, ou eu
> sairia da loja?

Três usuários independentes chegaram espontaneamente a essa metáfora na mesma discussão.
É o modelo mental real do usuário, e é um teste que qualquer pessoa da equipe aplica sem
treinamento e sem dado.

---

## 15. Lacunas de pesquisa e o que não foi possível verificar

Registro explícito, para que nada aqui vire mito interno.

| # | Item | Status |
|---|---|---|
| L1 | **Teaser vs auto-open** — nenhum teste A/B público com resultado comparativo | **NÃO VERIFICADO.** É a lacuna mais importante. Recomendação R13: medir internamente. |
| L2 | "Conclusão cai 4–6% por campo além do 8º" (atribuído à Baymard) | **NÃO VERIFICADO** — não localizado no artigo primário |
| L3 | "89% dos widgets no canto inferior direito"; "outro canto reduz engajamento 25–40%" | **NÃO VERIFICADO** — sem metodologia |
| L4 | Dark mode em Zendesk Web Widget, Crisp e Tidio | **NÃO VERIFICADO** — documentação oficial não localizada |
| L5 | Dimensões exatas em px do widget da Leadster | **NÃO VERIFICADO** — não publicadas; a doc fala em "Padrão/Média/Reduzida" |
| L6 | Snippet de instalação literal da Leadster | **NÃO VERIFICADO** — a doc remete ao painel autenticado; `curl` na home foi bloqueado/lento (Cloudflare). Confirmado apenas que a home carrega asset Leadster e que existe `window.neurolead.open()` |
| L7 | Lei brasileira específica de disclosure de bot | **NÃO VERIFICADO** — não localizada norma vigente específica |
| L8 | Relatório original da Forrester com o "2,8×" | **NÃO VERIFICADO** — o número circula sem o relatório acessível |
| L9 | Estudo original de "chat proativo converte 40% mais" | **NÃO VERIFICADO** — só fornecedores e agregadores |
| L10 | Widgets em SPAs brasileiras (Magalu, Americanas, Nubank, Sympla, Conta Azul, Zenvia) | **INCONCLUSIVO** — método por `curl` não enxerga injeção via SPA/GTM. Ausência ≠ ausência de widget. |
| L11 | Peso em KB do widget do ChatSPX | **NÃO MEDIDO** — fora do escopo desta task (é estudo, não medição de produto). R41. |
| L12 | Taxa de conversão do widget do ChatSPX na frota | **NÃO MEDIDO** — não há benchmark interno para comparar com os 2,98–3,07% da mediana brasileira |

---

## 16. Fontes

### 16.1 Fontes primárias — documentação de fornecedor

- Intercom — Set up and customize the Messenger: <https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger>
- Intercom — Customizing the Messenger (dev): <https://developers.intercom.com/installing-intercom/web/customization>
- Intercom — Create a custom launcher: <https://www.intercom.com/help/en/articles/2894-create-a-custom-launcher>
- Intercom — New UI for Fin answers and handover: <https://www.intercom.com/changes/en/80878-new-ui-for-fin-answers-and-handover-to-teammates-in-the-messenger>
- Zendesk — Structured messages: <https://developer.zendesk.com/documentation/conversations/messaging-platform/programmable-conversations/structured-messages/>
- Sunshine Conversations — Web Messenger: <https://docs.smooch.io/guide/web-messenger/>
- Zendesk — shape and size of the Chat Web Widget (Classic): <https://support.zendesk.com/hc/en-us/articles/4408819992090-How-do-I-change-the-shape-and-size-of-the-Chat-Web-Widget-Classic>
- Leadster — Design e exibição do assistente: <https://help.leadster.com.br/article/38-como-alterar-as-opcoes-de-design-e-exibicao-do-assistente>
- Leadster — Instalar via HTML: <https://help.leadster.com.br/article/37-instalar-o-codigo-via-html>
- Leadster — Chat em botão/popup (`window.neurolead.open()`): <https://help.leadster.com.br/article/46-como-inserir-o-chat-em-um-botao-popup-no-seu-site>
- Leadster — Live Chat: <https://help.leadster.com.br/article/349-leadster-live-chat> e <https://leadster.com.br/live-chat/>
- Leadster — Google Calendar: <https://help.leadster.com.br/article/112-como-utilizar-a-funcao-do-google-calendar-na-leadster>
- Leadster — Chamadas inteligentes: <https://help.leadster.com.br/article/47-como-configurar-as-chamadas-inteligentes>
- Chatwoot — issue #8288 (limites de botão WhatsApp): <https://github.com/chatwoot/chatwoot/issues/8288>

### 16.2 Fontes primárias — assets baixados

- `https://client.crisp.chat/l.js` — crisp-client v4.9.2, build `4ea1f89`, baixado em 11/08/2026
- `https://widget.intercom.io/widget/…` — shim do loader, baixado em 11/08/2026
- Código do ChatSPX lido localmente (somente leitura): `app/javascript/sdk/sdk.js`,
  `app/javascript/sdk/bubbleHelpers.js`, `app/javascript/widget/components/`,
  `app/javascript/widget/i18n/locale/pt_BR.json`

### 16.3 Estudos e pesquisa (maior confiança)

- Baymard — Checkout Optimization: Minimize Form Fields: <https://baymard.com/blog/checkout-flow-average-form-fields>
- Leadster — Panorama de Geração de Leads no Brasil: <https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil/>
- Leadster — Panorama 2025: <https://leadster.com.br/panorama-de-geracao-de-leads-no-brasil-2025/> e <https://leadster.com.br/blog/panorama-geracao-de-leads-2025/>
- Leadster — Taxa de conversão por segmento: <https://leadster.com.br/blog/taxa-de-conversao-por-segmento/>
- Leadster — Textos para chatbots (59 exemplos com conversão): <https://leadster.com.br/blog/textos-para-chatbots/>
- Drift / lead response — compilação de estudos (MIT, HBR, Drift): <https://ainora.lt/blog/lead-response-time-statistics-every-study-2026> e <https://setsmart.io/blog/lead-response-time-statistics>
- Nunes & Dreze (2006), endowed progress effect — descrito em <https://fomr.io/blog/form-progress-bar>
- Formstack / Typeform / conversational forms — <https://tinycommand.com/blogs/conversational-forms-vs-traditional-forms-which-is-better-for-your-business>
- "The Chatbot is typing…" (typing indicators): <https://www.researchgate.net/publication/328744481_The_Chatbot_is_typing_-_The_Role_of_Typing_Indicators_in_Human-Chatbot_Interaction>
- Mitigating Response Delays in LLM-powered Virtual Agents: <https://arxiv.org/pdf/2507.22352>
- Uncanny valley em chatbots de e-commerce: <https://www.tandfonline.com/doi/full/10.1080/10447318.2022.2121038>
- Avatares vs fotos — inferências de traço: <https://pmc.ncbi.nlm.nih.gov/articles/PMC12759104/>
- Emoji em chatbots (saúde/informacional): <https://www.sciencedirect.com/science/article/pii/S074756322600052X>
- "A Bot and a Smile" (emoji, contexto informal): <https://www.tandfonline.com/doi/abs/10.1080/10510974.2020.1725082>
- Congruência emoji-texto e satisfação: <https://link.springer.com/article/10.1007/s43039-025-00126-w>
- Emojis at Work (competência/adequação): <https://online.ucpress.edu/collabra/article/12/1/147309/217078/Emojis-at-Work-The-Effects-of-Emoji-Use-on>
- Nielsen Norman Group sobre UX de chatbots (síntese): <https://blog.experientia.com/nielsen-norman-group-on-the-user-experience-of-chatbots/>

### 16.4 UX, anti-padrões e acessibilidade

- Jakob Nielsen — Top 10 UI Annoyances: <https://www.uxtigers.com/post/ui-annoyances>
- Hacker News — thread sobre popups "Can I help you": <https://news.ycombinator.com/item?id=24834779>
- "Why Conversational Interfaces are taking us back to the Dark Ages of Usability": <https://uxdesign.cc/why-conversational-interfaces-are-taking-us-back-to-the-dark-ages-of-usability-fa45fefb446b>
- "Honey, I built a chatbot, but no one will click on my buttons": <https://uxdesign.cc/honey-i-built-a-chatbot-but-no-one-will-click-on-my-buttons-b713290c0029>
- WCAG 2.2 Chat Widget Accessibility Checklist: <https://threada.ai/blog/wcag-22-chat-widget-accessibility-checklist/>
- TestDevLab — Accessible live chats: <https://www.testdevlab.com/blog/accessible-live-chats-tips-for-designing-creating-and-testing>
- LiveChat — Chat widget accessibility: <https://www.livechat.com/success/chat-widget-accessibility/>
- Cognigy — Webchat accessibility WCAG: <https://www.cognigy.com/product-updates/webchat-accessibility-wcag-best-practices>
- BOIA — 5 quick tips for accessible live chat: <https://www.boia.org/blog/5-quick-tips-for-accessible-live-chat>
- 100vh no iOS Safari: <https://dev.to/maciejtrzcinski/100vh-problem-with-ios-safari-3ge9>
- interactive-widget / viewport: <https://www.htmhell.dev/adventcalendar/2024/4/>
- Teclado móvel e dvh: <https://www.franciscomoretti.com/blog/fix-mobile-keyboard-overlap-with-visualviewport>
- Core Web Vitals com chat widget: <https://www.corewebvitals.io/pagespeed/chat-widget-perfect-core-web-vitals>
- Third-party scripts e Core Web Vitals: <https://www.pagespeedfix.com/blog/third-party-scripts-core-web-vitals/>

### 16.5 Handoff, disponibilidade e CSAT

- Cobbai — Chatbot escalation best practices: <https://cobbai.com/blog/chatbot-escalation-best-practices>
- eesel — Human handoff best practices: <https://www.eesel.ai/blog/best-practices-for-human-handoff-in-chat-support>
- Standard Beagle — Chatbot handoff UX: <https://standardbeagle.com/chatbot-handoff-ux/>
- Atys — Handoff humano no chatbot (2026): <https://www.atys.pro/blog/automacao/handoff-humano-chatbot-atendente-2026>
- Helpable — Live chat outside business hours: <https://www.gethelpable.com/blog/live-chat-outside-business-hours>
- JivoChat — Offline messages: <https://www.jivochat.com/blog/communication/offline-messages.html>
- Oscar Chat — Live chat availability best practices: <https://www.oscarchat.ai/blog/live-chat-availability-best-practices/>
- CSAT response rates: <https://supp.support/blog/how-to-set-up-csat-surveys> e <https://www.customersure.com/guides/survey-response-rates/>

### 16.6 Benchmarks de conversão (confiança variável — ver classificação nas tabelas)

- Which-50 — Chat-to-conversion by industry: <https://which-50.com/chat-to-conversion-rate-statistics-by-industry/>
- Databox — Forms vs chat: <https://databox.com/forms-vs-chat>
- Wonderchat — B2B Website Conversion Benchmark 2026: <https://wonderchat.io/blog/b2b-website-conversion-report-2026>
- Forrester — Retailers without chat: <https://www.forrester.com/blogs/retailers-without-chat-a-missed-opportunity/>
- Freshworks — Proactive chat: <https://www.freshworks.com/live-chat/proactive-chat/>
- CrazyEgg — Exit-intent popup playbook: <https://www.crazyegg.com/blog/exit-popup/>
- Tidio — Live chat statistics: <https://www.tidio.com/blog/live-chat-statistics/>
- Helpable — Live chat response time benchmarks: <https://www.gethelpable.com/blog/live-chat-response-time-benchmarks>
- SQ Magazine — Mobile vs desktop: <https://sqmagazine.co.uk/mobile-vs-desktop-statistics/>
- SQ Magazine — E-commerce conversion rate: <https://sqmagazine.co.uk/e-commerce-conversion-rate-statistics/>
- Metrigy via No Jitter — preferência por humano: <https://www.nojitter.com/customer-experience/consumers-overwhelmingly-prefer-human-agents-in-the-era-of-ai>
- SurveyMonkey — Customer service statistics 2026: <https://www.surveymonkey.com/curiosity/customer-service-statistics/>
- AnswerConnect — Consumers turning away from AI: <https://www.answerconnect.com/blog/news/consumers-turning-away-from-ai-customer-service/>
- Zendesk — AI customer service statistics: <https://www.zendesk.com/blog/ai/productivity/ai-customer-service-statistics/>
- Glassix — AI chatbots e conversão: <https://www.glassix.com/article/study-shows-ai-chatbots-enhance-conversions-and-resolve-issues-faster>
- BotHero — Best chatbot interfaces: <https://blog.bothero.ai/best-chatbot-interfaces-what-separates-bots-people-actually-use-from-ones-they-immediately-close>
- Widget-chat — Chatbot UI design best practices: <https://widget-chat.com/blog/chatbot-ui-design-best-practices/>
- Clutch — Fix your chatbot UX: <https://clutch.co/resources/fix-your-chatbot-ux>
- GetStream — Chat UX best practices: <https://getstream.io/blog/chat-ux/>
- Gnosari — Conversational completion rates: <https://gnosari.com/blog/conversational-completion-rates>
- Oscar Chat — A/B test chat widget: <https://www.oscarchat.ai/blog/ab-test-chat-widget-conversions/>

### 16.7 LGPD, consentimento e disclosure

- Contábeis — LGPD para chatbots e IA: <https://www.contabeis.com.br/artigos/69603/lgpd-para-chatbots-e-ia-como-garantir-a-conformidade/>
- Getbots — LGPD e chatbots: <https://getbots.com.br/blog/lgpd-chatbots-para-empresas-devem-estar-adequados-a-legislacao/>
- AgeuBot — Política de privacidade para chatbots: <https://ageubot.com.br/blog/politica-privacidade-chatbot/>
- InBot — Adequar chatbot à LGPD: <https://inbot.com.br/chatbots/como-adequar-seu-chatbot-a-lgpd/>
- TermsFeed — California bot disclosure law: <https://www.termsfeed.com/blog/ca-bot-disclosure-law/>
- Holt Law — California BOT Disclosure Act: <https://djholtlaw.com/is-your-ai-chat-bot-illegal-a-comprehensive-legal-guide-to-californias-bot-disclosure-act/>
- CaseClerk — FTC guidance e disclosure de IA: <https://caseclerk.ai/blog/do-law-firm-ai-chatbots-have-to-disclose-theyre-bots-california-bot-law-ftc-guidance-and-eu-ai-act-requirements-for-2025>

### 16.8 Limites de canal (WhatsApp)

- engageSPARK — WhatsApp Business limits: <https://www.engagespark.com/support/whatsapp-business-limits/>
- Haptik — WhatsApp lists and buttons: <https://docs.haptik.ai/whatsapp-bots/how-to-use-whatsapp-list-and-buttons>
- Interakt — List messages and reply buttons: <https://www.interakt.shop/interakt-academy/list-messages-and-reply-buttons/>

### 16.9 Validação e máscaras BR

- br-validator (validação no `blur`, CPF/CNPJ/telefone/CEP/ViaCEP): <https://gaintime.github.io/br-validator/>

---

*Documento produzido em 11/08/2026 como estudo. Nenhum arquivo de código do repositório foi
modificado. Todas as observações sobre o widget do ChatSPX vieram de leitura do código-fonte
em `app/javascript/sdk/` e `app/javascript/widget/`.*
