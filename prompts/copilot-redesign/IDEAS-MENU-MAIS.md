# Menu "+" do Reply Box — Brainstorm de Ideias

> Gerado em 2026-05-05 por @aiox-master squad para o Chat SPX (Simplex).
> Status: **PROPOSTA** — aguardando aprovação do Walisson antes de implementar.
> Escopo: itens do dropdown "+" (mais ações) do composer de mensagens em conversas WhatsApp/multi-canal.

---

## 0. TL;DR (executivo)

- **Content Templates é Twilio-only**: o item só aparece em inboxes Twilio/WhatsApp (gate via `isATwilioWhatsAppChannel` em `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:283`). Não tem nada a ver com WAHA. Para ChatSPX (que usa WAHA + WhatsApp Cloud API) o item nunca aparece, então **manter como está** — sem mudança.
- **WhatsApp Templates (HSM)** continuam aparecendo apenas para inboxes que têm `message_templates` populados — Cloud API e 360Dialog populam automático; **WAHA não suporta HSM** porque HSM exige aprovação Meta (canal oficial). Atual gate (linha 280: `templates && templates.length`) já lida com isso corretamente.
- **Top 5 itens novos recomendados (em ordem)**: (1) Respostas rápidas / canned responses no menu "+" (já existe atalho `/`, mas falta entrada visual); (2) Inserir localização / endereço; (3) Compartilhar contato (vCard); (4) Pedir avaliação CSAT; (5) Inserir link de pagamento (Asaas/Mercado Pago/Pix copia-e-cola). Os 4 primeiros são nativos WAHA/Cloud, sem dependência externa.
- **Não recomendo agora**: enquetes, listas, botões CTA — só funcionam em Cloud API oficial e exigem aprovação Meta; baixo ROI para a base atual de WAHA.
- **Risco principal**: o "+" virou catch-all. Sem disciplina, vai virar menu de 15 itens onde ninguém acha nada. Recomendo agrupar visualmente (Anexos / Templates / Ações).

---

## 1. Estado atual

### 1.1 Itens do menu "+" hoje

Auditado em `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:2344-2400` (composer "wa" estilo WhatsApp) e `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue:345-393` (composer legacy).

| Item | Ícone | Gate | Backend |
|------|-------|------|---------|
| Anexar arquivo | `i-lucide-paperclip` | `showFileUpload \|\| isOnPrivateNote` | universal (ActiveStorage) |
| Agendar mensagem | `i-lucide-calendar-clock` | `currentChat.id` | universal (em dev por outro squad) |
| WhatsApp Templates (HSM) | `i-lucide-message-square-text` | `showWhatsappTemplates` (templates fetched do canal) | **só Cloud API + 360Dialog** |
| Content Templates (Twilio) | `i-lucide-message-square-text` | `showContentTemplates` (`isATwilioWhatsAppChannel`) | **só Twilio** |
| Inserir artigo (Help Center) | `i-lucide-file-text` | `enableInsertArticleInReply` | universal |
| Editor avançado (popout) | `i-lucide-text` | sempre | universal |

Botões fora do "+" (já no composer, não duplicar):
- Emoji picker (`i-lucide-smile`)
- Audio recorder (`i-lucide-mic`)
- Send (`i-lucide-send-horizontal`)

### 1.2 Sobre WAHA — o que ele suporta de envio

Auditado em `app/services/waha/api_service.rb`. O serviço atual expõe apenas:
- `list_sessions / create / start / stop / restart / delete`
- `edit_message`, `get_messages`
- `get_qr_code`, `get_session_me`
- `get_lid_phone_number`, `check_contact_exists`, `get_groups`
- `create_chatwoot_app`

**Importante**: o envio de mensagens via WAHA hoje é feito pelo app `chatwoot` injetado dentro do WAHA (ver `create_chatwoot_app`), não direto via API. Isso significa que features novas (poll, location, vCard) **exigem implementar wrappers explícitos** em `Waha::ApiService`.

**Capacidades nativas do WAHA** (https://waha.devlike.pro/docs):
- Texto (free, todos engines)
- Localização (free, todos engines)
- Contato vCard (free, todos engines)
- Reactions (free, todos engines)
- Edit/Delete mensagem (free, todos engines)
- Forward (free)
- Typing indicators (free)
- Imagem / Voz / Vídeo / Arquivo (**WAHA Plus**, todos engines)
- Polls (**WAHA Plus**, NOWEB / WEBJS / GOWS — Plus é o plano usado pela Simplex)
- Listas (**WAHA Plus**)
- Buttons reply (**WAHA Plus**)
- Custom link preview (**WAHA Plus**)
- Status/stories (**WAHA Plus**)
- **HSM templates: NÃO** — exige número aprovado Meta + Cloud API. WAHA usa session WhatsApp Web.

---

## 2. Sobre Content Templates (resposta direta à pergunta do W.)

**Pergunta**: Hoje só funciona com WhatsApp Cloud API oficial ou também com WAHA?

**Resposta**: **Nenhum dos dois** — Content Templates é uma feature **Twilio-exclusiva**.

### 2.1 Evidências no código

- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:282-284`:
  ```js
  showContentTemplates() {
    return this.isATwilioWhatsAppChannel && !this.isPrivate;
  }
  ```
- `app/models/channel/twilio_sms.rb:9`: campos `content_templates` e `content_templates_last_updated` existem **só** no model `Channel::TwilioSms`.
- `app/services/twilio/template_sync_service.rb`: serviço de sincronização vive sob namespace `Twilio::`, faz chamada à API Twilio Content (`https://content.twilio.com/...`).
- `app/services/twilio/template_processor_service.rb`: parser específico de templates Twilio.
- `app/views/api/v1/models/_inbox.json.jbuilder:76`: `json.content_templates resource.channel.try(:content_templates)` — só responde quando channel é Twilio (Twilio SMS / Twilio WhatsApp).

### 2.2 O que isso significa pro Chat SPX

- **Inboxes WAHA**: nunca veem o item "Content Templates". Não precisa fazer nada — o gate `showContentTemplates` já retorna `false`.
- **Inboxes WhatsApp Cloud API (oficial)**: também não veem "Content Templates", apenas "WhatsApp Templates" (HSM via `message_templates` do model `Channel::Whatsapp`).
- **Inboxes Twilio WhatsApp**: veem ambos — "WhatsApp Templates" e "Content Templates" (Content é o builder novo da Twilio que substitui o template tradicional).

### 2.3 Recomendação

- **Manter o item visível como está** — ele já é condicional ao Twilio, não atrapalha quem usa WAHA.
- **Não fazer "tooltip explicativo"** — o usuário WAHA nunca vê o botão, então não precisa explicar nada. Adicionar tooltip seria gold-plating.
- **Renomear i18n** (cosmético): hoje o label é hardcoded `"Content Templates"` em `ReplyBottomPanel.vue:371` (sem i18n!). Isso é um bug menor — quando estivermos editando o componente, mover para `CONVERSATION.FOOTER.CONTENT_TEMPLATES_TWILIO` (en) e "Templates Twilio" (pt-BR) para deixar claro que é Twilio.
- **Não há WAHA equivalente disso**: Twilio Content Templates é o sistema de "templates ricos" da Twilio (com HSM + non-HSM unificados, com botões/listas/CTAs). WAHA não tem analog porque WAHA é canal não-oficial — o botão equivalente em WAHA seriam **canned responses** (que já existem via `/`).

---

## 3. Brainstorm — ideias adicionais

Para cada ideia: descrição, caso de uso (persona BR concreta), suporte por backend, esforço, impacto, risco, e se já existe upstream.

### 3.1 Respostas rápidas (canned responses) no "+"

- **O que é**: Atalho visual para o picker de canned responses que hoje só é acessível digitando `/` no editor.
- **Caso de uso típico**: Atendente da clínica odontológica que ainda não memorizou o atalho `/` — clica no "+", vê "Respostas rápidas", abre o picker. Na maioria dos atendimentos a primeira mensagem é uma de 5-6 respostas pré-definidas ("Bom dia, tudo bem?", "Posso ajudar?", lista de horários, etc).
- **Suporte por backend**:
  - WAHA: sim — é só template de texto local, expandido client-side.
  - Cloud API: sim — idem.
- **Esforço de impl**: **S** (canned responses já existem totalmente — `app/models/canned_response.rb` + UI `cannedMenu`. É só adicionar `<DropdownItem>` apontando para `toggleCannedMenu`).
- **Impacto esperado**: **L** — discoverability é o maior bug invisível: muito atendente não sabe que `/` existe. Pesquisa interna Chatwoot upstream tem várias issues sobre isso.
- **Risco**: nenhum.
- **Onde já existe no Chatwoot upstream?**: Canned responses sim, mas **não há entry point no menu "+"** — só pelo atalho `/`. Seria adição genuína.

### 3.2 Inserir localização / endereço

- **O que é**: Mini-modal que aceita endereço (busca via Nominatim/Google Maps autocomplete) ou coordenadas, e envia como mensagem de localização nativa do WhatsApp.
- **Caso de uso típico**: Imobiliária mostrando o imóvel: "O apartamento fica em Rua X, nº Y, Bairro Z" → envia card de localização clicável que abre direto no Maps do cliente. Hoje tem que copiar endereço em texto. Clínica enviando o endereço da unidade no agendamento.
- **Suporte por backend**:
  - WAHA: **sim, free tier** — `POST /api/sendLocation`. Nativo, todos engines.
  - Cloud API: **sim** — `type: location` (https://developers.facebook.com/docs/whatsapp/cloud-api/messages/location-messages/).
- **Esforço de impl**: **M** — backend wrapper em `Waha::ApiService` (~30 linhas), backend wrapper em `Whatsapp::Providers::WhatsappCloudService` (~30 linhas), modal Vue com input de endereço + autocomplete (~150 linhas), integração ReplyBox (~50 linhas). Total ~5 dias úteis.
- **Impacto esperado**: **M-L** — vertical imobiliária pede muito. Vertical clínica/escola também. E-commerce delivery talvez.
- **Risco**: precisa decidir provider de geocoding (Nominatim free / Google Maps com chave). Nominatim tem rate limit baixo, Google custa (mas Simplex já usa Google em outros pontos? checar).
- **Onde já existe no Chatwoot upstream?**: **NÃO**. O Chatwoot atual não tem location picker no composer. Existe parser de `attachment.type = location` para *receber* localização, mas não para *enviar*. Seria diferenciador real.

### 3.3 Compartilhar contato (vCard)

- **O que é**: Selecionar um contato da agenda do Chat SPX (clientes/leads cadastrados) e enviar como vCard nativo do WhatsApp.
- **Caso de uso típico**: Atendente da imobiliária encaminhando: "Esse é o telefone do nosso corretor especializado, Fulano: [vCard]" → cliente clica e adiciona à agenda direto. Hoje copia/cola texto. Idem para clínica indicando especialista, escola indicando coordenador.
- **Suporte por backend**:
  - WAHA: **sim, free tier** — `POST /api/sendContactVcard`.
  - Cloud API: **sim** — `type: contacts`.
- **Esforço de impl**: **M** — backend wrappers (idem 3.2), modal de seleção de contato reusa o `ContactSearch` que já existe (`app/javascript/dashboard/components/widgets/conversation/contact/ContactInfo.vue`), gera vCard string. ~3-4 dias.
- **Impacto esperado**: **M** — uso menor que localização, mas alto valor pra B2B (dispatcher pra técnico, recepção pra especialista).
- **Risco**: privacidade — não vazar telefone de contato sem consentimento. UI precisa deixar claro que vai compartilhar.
- **Onde já existe no Chatwoot upstream?**: **NÃO**. Mesma situação de localização.

### 3.4 Pedir avaliação CSAT (CSAT survey)

- **O que é**: Botão que dispara a CSAT survey nativa do Chatwoot na conversa atual, sem precisar abrir o menu de ações da conversa.
- **Caso de uso típico**: Atendente terminou um atendimento bom — antes de fechar a conversa, manda CSAT. Hoje a CSAT é automática (no resolve) ou exige acessar o menu de conversa, que tem 4 cliques.
- **Suporte por backend**:
  - WAHA: **parcial** — CSAT do Chatwoot é renderizado pelo widget web. Para WhatsApp, hoje o Chatwoot envia link CSAT externo (`csat.chatwoot.com/...`). Funciona em qualquer canal incluindo WAHA.
  - Cloud API: **sim** — pode enviar template CSAT aprovado (já tem `csat_template_service.rb`!).
- **Esforço de impl**: **S-M** — `app/services/whatsapp/csat_template_service.rb` já existe. É só expor "Send CSAT now" no menu "+". ~2-3 dias.
- **Impacto esperado**: **M** — métricas de CSAT são lifeblood de SaaS de atendimento. Aumentar coleta = melhor visibilidade.
- **Risco**: timing — disparar CSAT no meio da conversa é UX ruim. Precisa de confirmação ("Tem certeza? Isso encerra a conversa pro cliente avaliar.").
- **Onde já existe no Chatwoot upstream?**: CSAT existe, mas **não há atalho no composer** — só dispara automático no resolve.

### 3.5 Link de pagamento (Pix / Asaas / Mercado Pago)

- **O que é**: Gerar link de cobrança/pagamento dentro do composer e enviar pro cliente. Pode ser Pix copia-e-cola, link Asaas, Mercado Pago, Stripe, ou apenas QR code de Pix.
- **Caso de uso típico**: Clínica fechando consulta: "Tudo certo, segue link pra pagar a consulta de R$ 250" → cliente paga e volta confirmando. Imobiliária mandando link de sinal de aluguel. E-commerce de pequenos vendedores fechando venda no WhatsApp.
- **Suporte por backend**: **independente do canal** — é gerar um link e mandar como mensagem.
- **Esforço de impl**: **L** — exige integração com gateway (Asaas é o mais comum no Brasil pra PMEs), modelo de armazenar credenciais por conta, conciliação de status (pago/pendente). ~2-3 semanas.
- **Impacto esperado**: **L** (talvez XL) — esse é o feature que fecha contrato. Pesquisas (Take Blip / Sebrae) mostram que 60%+ de PMEs no Brasil fecham vendas via WhatsApp, e a fricção de pagamento é o ponto de atrito.
- **Risco**: alto — armazenar tokens de gateway exige criptografia at-rest (já temos via `attr_encrypted`?), compliance LGPD, suporte a falha de gateway, reconciliação. Não é "ideia simples".
- **Onde já existe no Chatwoot upstream?**: **NÃO**. Existem apps tipo "Shopify integration" mas nada nativo Brasil.

### 3.6 Inserir mídia da galeria de assets (cards/imagens reusáveis)

- **O que é**: Biblioteca de imagens/PDFs/vídeos pré-cadastrados pela conta (catálogo de produtos, política de cancelamento, ficha técnica) que o atendente seleciona em vez de fazer upload toda vez.
- **Caso de uso típico**: Imobiliária com 50 imóveis ativos — ao invés de o atendente buscar foto no Drive/Dropbox toda vez, abre a galeria e clica no imóvel. Escola enviando o pacote de matrícula. Clínica com lista de procedimentos com fotos antes/depois.
- **Suporte por backend**:
  - WAHA: **sim** (Plus) — `POST /api/sendImage` ou `sendFile`.
  - Cloud API: **sim**.
- **Esforço de impl**: **L** — exige novo model `MediaLibraryItem` ou uso do Active Storage com tags, UI de upload/organização, busca/filtro. ~2 semanas.
- **Impacto esperado**: **M-L** — depende muito da vertical. Imobiliária e e-commerce extraem muito valor; clínica nem tanto.
- **Risco**: storage cost — se virar dump de fotos, conta cresce. Precisa quota.
- **Onde já existe no Chatwoot upstream?**: **NÃO** nativo. Existe upload por mensagem mas não galeria reutilizável. Existe o Help Center articles, que é parecido mas pra texto.

### 3.7 Captain (IA) sugerir resposta

- **O que é**: Botão que invoca o Captain pra sugerir uma resposta baseada no contexto da conversa, e cola no editor pra revisão.
- **Caso de uso típico**: Atendente cansado, conversa longa — clica "Captain sugere" e ganha primeira versão pra editar.
- **Suporte por backend**: já existe — `app/javascript/dashboard/composables/useCopilotReply.js` está integrado. Falta apenas item no "+".
- **Esforço de impl**: **S** — wrapper sobre o que já existe. ~1 dia.
- **Impacto esperado**: **M** — bom, mas o Copilot já tem botão próprio (toggle do composer). Adicionar duplicata no "+" pode confundir. Talvez melhor manter onde está.
- **Risco**: redundância visual.
- **Onde já existe no Chatwoot upstream?**: Captain já tem entry point próprio. **Não recomendo duplicar**.

### 3.8 Reagir à mensagem do cliente (atalho rápido)

- **O que é**: Não é envio de mensagem, mas reação 👍❤️😂 a uma mensagem específica.
- **Caso de uso típico**: Cliente manda foto do problema, atendente reage com 👍 enquanto resolve, sem responder texto. Reduz a sensação de "abandonou a conversa".
- **Suporte por backend**:
  - WAHA: **sim, free tier** — `POST /api/reaction`.
  - Cloud API: **sim** — `type: reaction`.
- **Esforço de impl**: **S-M** — UI já existe parcialmente (Chatwoot tem `MessageReactions` em components-next). Falta integrar com WAHA e gate por canal. ~3 dias.
- **Impacto esperado**: **S-M** — feature "delight", baixo uso mas alta satisfação. Não vai vender contrato.
- **Risco**: **isso não pertence ao menu "+" do composer**. Reação é por-mensagem (hover na mensagem), não global. Recomendo descartar do escopo "+" — feature válida, mas não nesse menu.
- **Onde já existe no Chatwoot upstream?**: parcialmente.

### 3.9 Enquete / Poll

- **O que é**: Composer abre formulário "pergunta + opções" e envia poll nativo WhatsApp.
- **Caso de uso típico**: Escola perguntando "Qual horário fica melhor pra reunião?" com 3 opções. Imobiliária validando "Qual desses 3 imóveis você quer agendar visita?".
- **Suporte por backend**:
  - WAHA: **sim, mas exige WAHA Plus** + engine NOWEB/WEBJS/GOWS. `POST /api/sendPoll`.
  - Cloud API: **NÃO nativamente** — Cloud API não suporta poll (poll é feature do app, não da Business API). Workaround é interactive list (mas é diferente).
- **Esforço de impl**: **M-L** — backend wrapper, captura de votos via webhook (`poll.vote` event), persistência dos resultados, UI de visualizar votos. ~1.5-2 semanas.
- **Impacto esperado**: **S-M** — feature legal, mas niche. Maioria dos atendimentos B2C resolve com lista numerada em texto.
- **Risco**: **assimetria de canal** — poll funciona em WAHA mas não em Cloud API. Clientes que migram de WAHA pra Cloud (move pra oficial) perderiam a feature. Confusing.
- **Onde já existe no Chatwoot upstream?**: **NÃO**.

### 3.10 Mensagem com botões CTA (Cloud API interactive)

- **O que é**: Cloud API permite mandar mensagem com 1-3 botões "reply" não-template (não exige aprovação Meta). Cliente clica e a resposta volta como mensagem normal.
- **Caso de uso típico**: "Vamos confirmar o agendamento? [Sim] [Reagendar] [Cancelar]" — UX muito mais limpa que pedir cliente digitar 1/2/3.
- **Suporte por backend**:
  - WAHA: **só Plus** — `POST /api/send/buttons/reply`.
  - Cloud API: **sim** — `type: interactive, interactive.type: button`.
- **Esforço de impl**: **L** — UI de builder de botões (1-3 opções), serialização correta pro Cloud API e pro WAHA (formatos diferentes!), captura de resposta no webhook. ~2 semanas.
- **Impacto esperado**: **M-L** — alto pra fluxos de qualificação/agendamento, baixo pra atendimento aberto.
- **Risco**: **assimetria** novamente. WAHA Plus + Cloud API ambos suportam, mas com payloads diferentes — abstração custa esforço de QA.
- **Onde já existe no Chatwoot upstream?**: parcialmente — input_select já existe (`message.content_type === 'input_select'`), mas é mais voltado pra bot/agent automation que composer manual. Adaptar é viável.

### 3.11 Lista de seleção (interactive list)

- **O que é**: Mensagem com menu "tipo SAC" — 1 botão CTA que abre lista com até 10 opções selecionáveis.
- **Caso de uso típico**: "Qual setor você precisa? [Atendimento] → [Vendas] [Suporte] [Financeiro] [Cancelamento] ...". Bom pra triagem inicial sem bot.
- **Suporte por backend**:
  - WAHA: Plus — `POST /api/sendList`.
  - Cloud API: sim — `interactive.type: list`.
- **Esforço de impl**: **M-L** — similar a 3.10. ~1.5 semanas.
- **Impacto esperado**: **S-M** — overlap com 3.10 (botões). Em atendimento humano (não bot), uso é raro porque o atendente já está conversando com a pessoa específica.
- **Risco**: redundante com botões.
- **Onde já existe no Chatwoot upstream?**: **NÃO** no composer manual.

### 3.12 Inserir variável dinâmica do contato

- **O que é**: Atalho pra inserir `{{contact.name}}`, `{{contact.last_visit}}`, `{{conversation.id}}`, etc, com preview ao vivo.
- **Caso de uso típico**: Atendente escrevendo "Olá {{contact.name}}, como posso ajudar hoje?" — vê na hora "Olá João, como posso ajudar hoje?". Hoje canned responses já fazem isso, mas nem todo mundo digita `/`.
- **Suporte por backend**: independente — é só template engine local.
- **Esforço de impl**: **S** — Chatwoot já tem `MessageVariables` mixin (`app/javascript/dashboard/components/widgets/conversation/MessageVariables.js`). É só plugar no menu. ~2 dias.
- **Impacto esperado**: **S** — uso baixo no dia-a-dia, mas tira dúvida pra novato.
- **Risco**: nenhum.
- **Onde já existe no Chatwoot upstream?**: parcialmente — variáveis existem, mas o pop-up de inserir não tem entrada via menu "+".

### 3.13 Inserir agendamento (slot picker)

- **O que é**: Mostra calendário do atendente (Google Calendar / agenda interna), atendente seleciona horário e envia confirmação.
- **Caso de uso típico**: Clínica agendando consulta "Tem horário sexta 14h?" → atendente abre slot picker, seleciona 14h sexta, envia mensagem com confirmação + cria evento Google.
- **Suporte por backend**: **integração externa** — exige Calendly/Google Calendar/Cal.com. Nada nativo.
- **Esforço de impl**: **XL** — integração Google Calendar OAuth, modelo de slots, conflito, fuso horário. ~3-4 semanas.
- **Impacto esperado**: **L** pra clínica/salão/escritório de advocacia. Baixo pra outras verticais.
- **Risco**: alto — escopo grande, integração frágil (Google API depreciações).
- **Onde já existe no Chatwoot upstream?**: **NÃO**.

### 3.14 GIF picker (Tenor/Giphy)

- **O que é**: Buscar e enviar GIF.
- **Caso de uso típico**: Atendimento informal (consumidor jovem), "obrigado!" + gif comemorativo.
- **Suporte por backend**:
  - WAHA Plus: sim — envia como vídeo MP4.
  - Cloud API: sim — `type: video` (WhatsApp converte gif pra video).
- **Esforço de impl**: **M** — Giphy/Tenor SDK, cache de busca, conversão pra mp4. ~1 semana.
- **Impacto esperado**: **S** — público B2B brasileiro raramente manda GIF em atendimento. Mais nicho.
- **Risco**: chave Giphy/Tenor (free com rate limit), conteúdo NSFW (filtro on-by-default).
- **Onde já existe no Chatwoot upstream?**: Crisp/Intercom têm. Chatwoot **não**.

### 3.15 Sticker picker

- **O que é**: Enviar sticker WhatsApp.
- **Caso de uso típico**: Idem GIF — fechamento positivo.
- **Suporte por backend**:
  - WAHA Plus: sim, mas formato `.webp` específico.
  - Cloud API: sim.
- **Esforço de impl**: **M-L** — biblioteca de stickers exige design ou licenciamento. ~1.5 semanas.
- **Impacto esperado**: **S** — niche.
- **Risco**: licenciamento.
- **Onde já existe no Chatwoot upstream?**: **NÃO**.

### 3.16 Mark as urgent / priorizar conversa

- **O que é**: Não é envio, é setar prioridade da conversa atual.
- **Caso de uso típico**: Atendente percebe que conversa virou urgente → marca como prioridade alta sem precisar abrir o painel direito.
- **Suporte**: nativo Chatwoot (já tem campo `priority` no model `Conversation`).
- **Esforço**: **S** — 1 dia.
- **Impacto**: **S-M**.
- **Risco**: **não pertence ao menu "+"** — esse menu é "ações sobre a mensagem que vai sair", não "ações sobre a conversa". Vai confundir taxonomia. Recomendo descartar daqui.
- **Onde já existe upstream?**: priority já existe, mas em painel lateral.

---

## 4. Recomendação priorizada (top 5)

| # | Item | Justificativa | Trigger pra reabrir conversa |
|---|------|---------------|------------------------------|
| 1 | **Respostas rápidas (canned) no "+"** | Custo S, impacto L. Discoverability é o maior problema invisível do composer. Atendente novato encontra o botão sem precisar saber atalho. Implementação trivial. | Se métrica de uso de canned subir <10% após 2 semanas, reverter. |
| 2 | **Inserir localização** | Custo M, impacto M-L pra imobiliária/clínica/escola (verticais-alvo Simplex). Funciona em WAHA free + Cloud API. Diferenciador real vs Chatwoot vanilla. | Se nenhuma conta usar nas primeiras 2 semanas, reavaliar com pesquisa de cliente. |
| 3 | **Compartilhar contato (vCard)** | Custo M, impacto M. Funciona free em ambos canais. Reaproveita ContactSearch existente. Resolve uso real B2B (passar técnico/especialista). | Idem 2. |
| 4 | **Pedir CSAT agora** | Custo S-M. CSAT é métrica core de SaaS de atendimento — facilitar disparo aumenta coleta. Já temos CSAT template service implementado. | Acompanhar conversion rate CSAT (envios → respostas). |
| 5 | **Link de pagamento (Asaas/Pix)** | Custo L mas impacto XL pra fechar contrato. **Esse é o feature que vende.** PMEs brasileiras fecham venda no WhatsApp e pagamento é o gargalo. Não dá pra fazer rápido — é projeto separado. | Roadmap de Q3, não bloqueia entregar 1-4. |

### Agrupamento visual recomendado no menu

Pra evitar virar lista de 12 itens, agrupar com seções (DropdownBody com headers ou separators):

```
[Anexos]
  Anexar arquivo
  Localização
  Contato

[Conteúdo]
  Respostas rápidas
  WhatsApp Templates (HSM) (se Cloud)
  Content Templates (se Twilio)
  Inserir artigo (se Help Center)

[Ações]
  Agendar mensagem
  Pedir avaliação (CSAT)
  Editor avançado
```

---

## 5. O que NÃO recomendo (e por quê)

| Item | Motivo |
|------|--------|
| Enquetes/Polls | Assimetria WAHA-Plus vs Cloud (Cloud não suporta poll). Niche para atendimento humano. Investir esforço em feature que metade dos clientes não usa. |
| Botões CTA / Lista interactive | Custo L, audiência real é bot/agent automation, não atendente humano. Melhor parquear pra projeto "Agentes IA" (`feature/agentes-ia`). |
| GIF picker | Público B2B brasileiro raramente usa em atendimento profissional. ROI baixo. |
| Sticker picker | Idem GIF + custo de design/licenciamento. |
| Slot picker / agendamento integrado | Escopo XL (Google Calendar OAuth). Vale como produto separado, não como item de menu. |
| Captain "sugerir resposta" no "+" | Já existe entry point dedicado. Duplicar confunde. |
| Reagir à mensagem | Não pertence a esse menu (é per-message, não composer). Feature válida mas em outro contexto. |
| Marcar conversa como urgente | Não pertence ao menu "+" (é sobre conversa, não sobre mensagem). Quebra taxonomia. |
| Galeria de assets reusáveis | Custo L, impacto depende muito da vertical. Bom pra v2, não v1. |
| Variáveis dinâmicas | Custo S mas overlap forte com canned responses (que já fazem isso). Implementar canned no "+" cobre 90% do caso. |

---

## 6. Questões abertas (decisão Walisson antes de ir pra dev)

1. **Localização — provider de geocoding**: Nominatim (free, rate limit) ou Google Maps (custo $$/1000 req)? Tem chave Google ativa em algum lugar do Chat SPX que possa reaproveitar? Ou aceitamos input manual de lat/lng (sem autocomplete) na v1?

2. **Suporte de localização/contato em WAHA Plus**: a Simplex está em Plus, certo? Confirmar antes de assumir features Plus (poll, list, button) — embora os top 5 não dependam disso (location/vCard são free).

3. **Link de pagamento — qual gateway?** Asaas é o mais comum no Brasil. Mercado Pago tem audiência maior mas API mais chata. Pix-only com QR (sem gateway) é o mais simples e cobre 80% do caso. Decisão de produto, não técnica.

4. **CSAT manual — afeta resolução automática?** Hoje CSAT dispara no resolve. Se atendente disparar manualmente antes do resolve, qual é o comportamento? Permitir múltiplos CSATs por conversa? Bloquear o auto-CSAT no resolve subsequente?

5. **Agrupamento visual** (sugestão da seção 4): aceitar headers/dividers no DropdownBody ou manter lista flat? Visualmente headers ficam mais escaláveis mas exigem componente de dropdown que aceite isso (verificar `DropdownBody` em `dashboard/components-next/dropdown-menu/`).

6. **Renomear "Content Templates" → "Templates Twilio"** (i18n): aprovação cosmética. É bug menor (string hardcoded), bom corrigir junto.

7. **Quando entrar no menu de WhatsApp inboxes que NÃO têm templates HSM aprovados** (cliente usa Cloud mas não cadastrou template): o item "WhatsApp Templates" some. Está ok ou queremos mostrar disabled com tooltip "Aprovar templates em Settings"?

8. **Ordem dos itens importa**: hoje no `ReplyBox.vue` está "Anexar / Agendar / Templates / Inserir artigo / Editor avançado". Manter ordem ou reordenar com novos itens? Sugestão minha está na seção 4 (agrupado).

9. **Composer "wa" vs legacy**: hoje o ChatSPX usa o composer estilo WhatsApp (`hasWaPill = true`). O `ReplyBottomPanel.vue` legacy também tem o "+", mas em layout diferente. Sincronizar ambos ou apenas atualizar o "wa"?

10. **Captain Copilot e o "+"**: o Copilot tem ativação própria (toggle do composer). Se o usuário clicar no "+" durante Copilot ativo, o que acontece? Hoje o "+" provavelmente fica oculto (linha 588: `!this.copilot.isActive.value`). Confirmar.

---

## 7. Apêndice — Referências de código

- Composer "wa" (ChatSPX skin WhatsApp): `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:2330-2400`
- Composer legacy (Chatwoot original): `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue:345-393`
- Gate `showContentTemplates`: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:282-284`
- Gate `showWhatsappTemplates`: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:275-281`
- Service WAHA atual (a estender): `app/services/waha/api_service.rb`
- Service Cloud API (a estender): `app/services/whatsapp/providers/whatsapp_cloud_service.rb`
- Service Twilio Content Templates: `app/services/twilio/template_sync_service.rb` + `template_processor_service.rb`
- Model `Channel::TwilioSms` (campo `content_templates`): `app/models/channel/twilio_sms.rb:9-10`
- Model `Channel::Whatsapp` (provider Cloud / 360): `app/models/channel/whatsapp.rb:43-50`
- ScheduledMessageForm (em dev): `app/javascript/dashboard/components-next/Kanban/ScheduledMessageForm.vue`
- Captain integration no composer: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:143-165`
- WAHA docs: https://waha.devlike.pro/docs/

## 8. Apêndice — Notas sobre concorrentes

Pesquisa rápida (EXA/web search) — não encontrou benchmarks UX detalhados específicos do menu "+" de chat composer 2025-2026. O que aparece em alto nível:

- **Crisp**: composer tem áudio, vídeo, GIF, file, "shortcuts" (canned), notes. Sem location/vCard nativo. Polished mas vertical SaaS B2B (não otimizado pra WhatsApp BR).
- **Intercom**: composer foca em macros/saved replies, attachments, Fin (AI). Não tem features WhatsApp-específicas (público é web app primarily).
- **JivoChat**: composer é simples — texto, emoji, attachment, áudio. Não tem ações ricas.
- **Take Blip**: composer rico em automação (botões, listas, fluxos), mas é builder de bot, não composer humano. Comparação não-direta.
- **Tawk.to**: composer minimal, foco em web chat.
- **Z-API / Twilio Studio**: similar ao Take Blip — voltado pra builder.

**Conclusão**: ninguém tem o "menu + perfeito" — Chatwoot está em posição razoável. Os ganhos vêm de **localização/vCard/pagamento** (especificidade mercado BR), não de copiar concorrentes.

---

## 9. Apêndice — Verticais e o que cada uma pede

Notas qualitativas (sem pesquisa formal — viés de exposição Simplex). Útil pra debate de priorização.

### 9.1 Imobiliária
- **Top pain**: passar fotos do imóvel, endereço completo clicável, agenda de visita, contato do corretor responsável.
- **Itens "+" relevantes**: localização (3.2), vCard (3.3), galeria assets (3.6), link de pagamento (3.5 — sinal de aluguel/reserva).
- **Não relevantes**: poll, sticker, GIF.

### 9.2 Clínica / consultório
- **Top pain**: confirmação de consulta, lembrete, endereço da unidade, link de pagamento, ficha de anamnese.
- **Itens "+" relevantes**: localização (endereço da clínica), CSAT (3.4), link pagamento (3.5), agendamento (3.13 quando viável).
- **Cuidado LGPD**: dados de saúde — não logar conteúdo de mensagens em telemetria.

### 9.3 Escola / curso
- **Top pain**: lista de matrículas/turmas, comprovante de pagamento, calendário escolar, contato dos coordenadores, comunicado em massa.
- **Itens "+" relevantes**: galeria assets (3.6 — fichas de matrícula), vCard (3.3 — coordenador), poll (3.9 — apesar do risco de assimetria).
- **Não relevantes**: link de pagamento individual (escolas usam boleto via gateway próprio em geral).

### 9.4 E-commerce / pequeno vendedor
- **Top pain**: catálogo de produto, link de pagamento, status de pedido, prazo de entrega.
- **Itens "+" relevantes**: link pagamento (3.5 = matar/morrer), galeria (3.6), botões CTA (3.10 — "Confirmar / Cancelar pedido").
- **Cuidado**: integração com plataforma de e-commerce (Shopify, Yampi, Nuvemshop) é projeto à parte.

### 9.5 Suporte técnico / SaaS
- **Top pain**: KB articles, links de tutorial, anexar logs, escalar pra L2.
- **Itens "+" relevantes**: inserir artigo (já existe), respostas rápidas (3.1), variáveis dinâmicas (3.12 — IDs de ticket).

---

## 10. Apêndice — Roadmap sugerido

Se o Walisson aprovar os top 5, ordem de execução sugerida:

### Sprint 1 (1 semana) — discoverability
- 3.1 Respostas rápidas no "+" — 1-2 dias
- Renomear "Content Templates" → i18n correto — 0.5 dia
- Reorganização visual do menu (agrupamento) — 1-2 dias
- Audit de gates (garantir que itens só aparecem quando relevantes) — 0.5 dia

### Sprint 2 (2 semanas) — features WhatsApp nativas
- 3.2 Localização — 5 dias
- 3.3 vCard — 4 dias
- Testes E2E nos dois canais (WAHA + Cloud) — 1 dia

### Sprint 3 (1 semana) — CSAT manual
- 3.4 Pedir CSAT agora — 3 dias
- Ajuste de comportamento auto-CSAT vs manual — 2 dias

### Sprint 4+ (3-4 semanas) — pagamento (projeto separado)
- 3.5 Link de pagamento (Asaas como POC) — 3-4 semanas
- Tratar como projeto independente, não bloquear sprints anteriores.

### Backlog parqueado (avaliar após sprint 4)
- Galeria de assets (3.6)
- Polls (3.9) — só se demanda explícita
- Botões CTA (3.10) — coordenar com squad `feature/agentes-ia`
- Slot picker / agendamento (3.13) — projeto grande à parte

---

**Fim do documento**. Aguardando review do Walisson para priorizar e abrir tasks.
