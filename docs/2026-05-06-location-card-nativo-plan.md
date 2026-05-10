# Location/Contact — Card Nativo no Painel + Filtro de Lixo do App Externo

> **Status:** 📋 Planejamento aprovado — pronto pra execução
> **Data:** 2026-05-06
> **Autor:** Walisson (Simplex) + orquestração via aiox-master
> **Branch alvo:** `homologacao` (working tree)
> **Escopo:** Backend (Rails) + Frontend (Vue) — sem deploy do app WAHA externo
> **Tempo estimado:** 1-2h trabalho efetivo

## TL;DR

No painel do agente, mensagens de localização aparecem com 2 bubbles confusos: (1) endereço bruto do Nominatim como texto longão, (2) card "📱 Enviado via API / 📍 Localização compartilhada / 🔗 Ver no mapa" gerado pelo app WAHA externo. Além disso, quando o app externo bate erro interno (timestamp NaN), ele posta o stack-trace técnico no painel.

**Solução decidida:** limpar o `content` da Message location no `share_location` (deixar vazio), garantir que o `LocationBubble.vue` nativo renderize com endereço Nominatim como subtítulo, e estender o filtro de echo (`waha_echo?`) pra também suprimir mensagens-erro técnicas vindas do app externo.

**Impossível mexer na raiz:** o app `chatwoot-waha-app` (Node.js) roda em Docker fora do nosso controle — solução fica só do lado Chatwoot, tratando o app externo como caixa-preta ruidosa.

---

## 1. Contexto histórico (a saga até aqui)

Esta é a 5ª iteração de uma série de fixes em outbound location/contact via WAHA. Ordem cronológica:

### Round 1 — Bypass do app externo
- **Bug:** App externo (`chatwoot-waha-app`, Node.js) recebia webhook do Chatwoot pra location/contact e tentava enviar como `POST /api/sendFile` com `file:{filename:"",url:""}` → `ERR_INVALID_URL`.
- **Fix:** Criado `Waha::OutboundSpecialMessageService` que dispara `/api/sendLocation` e `/api/sendContactVcard` direto via WAHA REST. `WebhookListener#message_created` desvia o fluxo pra esse service quando attachment é location/contact, suprimindo o webhook normal pro app externo.
- **Arquivos:** `app/services/waha/outbound_special_message_service.rb`, `app/listeners/webhook_listener.rb`.

### Round 2 — Endpoint sendContactVcard quebrado
- **Bug:** WAHA GoWS PLUS engine retorna 500 com `Cannot read properties of undefined (reading 'map')` no endpoint `/api/sendContactVcard` mesmo com payload correto.
- **Fix:** Sempre usar `send_text_with_vcard` (vCard 3.0 inline via `/api/sendText`), independente de `source` (manual/agente).

### Round 3 — JID errado (LID + 9-extra brasileiro + UUID)
- **3 bugs combinados:**
  1. `contact_inbox.source_id` às vezes é **LID** (Long ID 20+ dígitos) — WAHA aceita 200 OK mas vai pro vazio.
  2. **9-extra brasileiro:** DDD 66 (Sinop) tem números antigos sem o "9". Mandar `5566992442207` (13 dígitos) vira fantasma; canônico é `556692442207` (12 dígitos).
  3. **UUID em Channel::Api genérico:** quando inbox é Channel::Api puro, `source_id` é UUID (`a8182041-4dec-...`). Extrair dígitos disso virava lixo.
- **Fix:** `Waha::OutboundSpecialMessageService#chat_id` agora:
  - Detecta JID vs E.164 vs UUID via regex (helper `candidate_digits`).
  - Cai pra `contact.phone_number` (E.164) quando source_id é UUID.
  - Sempre passa por `Waha::ApiService#check_contact_exists` que retorna o `chatId` canônico (resolve LID e 9-extra).
- **Validação runtime:** ack=READ confirmado no celular do destinatário.

### Round 4 — Duplicação 5x
- **Bug:** `WebhookListener#message_updated` chamava `OutboundSpecialMessageService` a cada update de status (sent → delivered → read), reenviando location 5x.
- **Fix:** `message_updated` apenas suprime webhook (não reenvia REST). Idempotência interna em `OutboundSpecialMessageService#perform`: se `message.source_id.present?`, retorna `false`.

### Round 5 — Echo do pseudo-card
- **Bug:** App externo postava 6s depois um pseudo-card "📱 Enviado via API / 📍 Localização compartilhada / 🔗 Ver no mapa" via `POST /messages`, criando bubble duplicado no painel.
- **Fix:** Estendido `waha_echo?` em `messages_controller.rb` com `WAHA_ECHO_MARKER_LOCATION` e `WAHA_ECHO_MARKER_CONTACT`. Echos suprimidos.

### Estado pós-Round 5 (atual)
- ✅ Destinatário recebe location nativa (mapa clicável WhatsApp).
- ✅ Sem duplicação no envio.
- ❌ Painel mostra endereço bruto Nominatim no `content` (longão e feio).
- ❌ App externo às vezes posta erros técnicos (`⚠️ Não foi possível receber / error: insert into "app_chatwoot_chatwoot_messages" ... timestamp NaN`).
- ❌ Cliente perdeu o pseudo-card "📍 Localização compartilhada" formatado e quer algo nativo no lugar.

---

## 2. Estado atual do código (auditoria)

### 2.1 Componente nativo do Chatwoot
**Já existe:** `app/javascript/dashboard/components-next/message/bubbles/Location.vue`

- Importado em `app/javascript/dashboard/components-next/message/Message.vue:48` como `LocationBubble`.
- Recebe `attachment` (props) com:
  - `coordinates_lat`, `coordinates_long`
  - `fallback_title` (endereço Nominatim atualmente)
  - `data_url` (montado por `Attachment#location_metadata` em `app/models/attachment.rb:127-139`)

### 2.2 `share_location` (controller)
**Arquivo:** `app/controllers/api/v1/accounts/conversations/messages_controller.rb:112`

- Cria `Message` com `content` = endereço bruto Nominatim concatenado com link Google Maps (vindo do frontend).
- Cria `Attachment` com `file_type: location`, `coordinates_lat/long`, `fallback_title`.
- **Problema:** o `content` poluído é renderizado como bolha de texto separada, ao lado do `LocationBubble`.

### 2.3 Frontend `LocationPickerModal`
**Arquivo:** `app/javascript/dashboard/components-next/location/LocationPickerModal.vue`

- Faz reverse-geocoding via Nominatim (`?addressdetails=1&accept-language=pt-BR`).
- Hoje passa `content` = endereço completo + link maps no payload do `share_location`.
- Já tem `enableHighAccuracy: true, timeout: 15000, maximumAge: 0` (Round anterior).

### 2.4 Filtros de echo já existentes
**Arquivo:** `app/controllers/api/v1/accounts/conversations/messages_controller.rb:4-10`

```ruby
WAHA_ECHO_MARKER_API = 'Enviado via API'
WAHA_ECHO_MARKER_LOCATION = 'Localização compartilhada'
WAHA_ECHO_MARKER_CONTACT = 'Contato compartilhado'
WAHA_ECHO_MARKER_EDITED = 'Editado no WhatsApp'
WAHA_ECHO_MARKERS_SPECIAL = [WAHA_ECHO_MARKER_LOCATION, WAHA_ECHO_MARKER_CONTACT, WAHA_ECHO_MARKER_EDITED].freeze
```

`waha_echo?(content)` retorna true quando content casa com `WAHA_ECHO_MARKER_API` + qualquer um dos especiais.

### 2.5 App WAHA externo (caixa-preta)
- Roda em **Docker** fora desta VM (192.168.8.232).
- Endpoint: `https://waha.simplexsolucoes.com.br/webhooks/chatwoot/simplexteste/chatwoot-simplexteste` (config no `inbox.channel.webhook_url`).
- **NÃO temos como mexer.** Continua postando lixo, precisamos filtrar lá no inbound.

---

## 3. Decisões aprovadas (Walisson)

| # | Pergunta | Decisão |
|---|----------|---------|
| 1 | `content` da Message location | **(a)** Vazio — só o `LocationBubble` aparece no painel |
| 2 | Endereço Nominatim completo | **(a)** Subtítulo dentro do `LocationBubble`, embaixo do mapa |
| 3 | Acesso ao repo do app externo | **Não** — Docker fora do nosso controle. Tratar como caixa-preta. |

**Implicação:** vamos pra **Opção A + reforço da B** (filtros agressivos contra ruído do app externo).

---

## 4. Plano de execução

### Passo 1 — Limpar `content` no `share_location`

**Arquivo:** `app/controllers/api/v1/accounts/conversations/messages_controller.rb`

**Mudança:** método `share_location` (linha ~112). Receber o endereço bruto do frontend mas **NÃO colocar no `content`**. Salvar:
- `content` = `''` (vazio)
- `fallback_title` do attachment = endereço Nominatim completo
- `additional_attributes['location']['address']` = mesmo endereço (redundância pra resiliência futura)

**Pseudocódigo:**
```ruby
def share_location
  message = conversation.messages.build(
    message_type: :outgoing,
    account_id: conversation.account_id,
    inbox_id: conversation.inbox_id,
    sender: current_user,
    content: '',  # vazio — render fica a cargo do LocationBubble
    additional_attributes: { 'location' => { 'address' => params[:address] } }
  )
  message.attachments.new(
    account_id: conversation.account_id,
    file_type: :location,
    coordinates_lat: params[:lat],
    coordinates_long: params[:lng],
    fallback_title: params[:address]  # endereço completo Nominatim
  )
  message.save!
  render json: message
end
```

(Validar contrato real do método olhando o arquivo antes de editar — pode estar usando `MessageBuilder` ou similar.)

### Passo 2 — Atualizar `LocationPickerModal.vue`

**Arquivo:** `app/javascript/dashboard/components-next/location/LocationPickerModal.vue`

**Mudança:** ao chamar `MessageAPI.shareLocation` (ou equivalente), passar:
- `content`: deixar vazio ou omitir
- `address`: endereço completo do reverse-geocoding (Nominatim) → vai pra `attachment.fallback_title`
- `lat`, `lng`: coordenadas

**Validar payload:** garantir que o body do POST não esteja injetando o `📍 Localização` ou link Maps no content (era o comportamento antigo).

### Passo 3 — Render no `LocationBubble.vue`

**Arquivo:** `app/javascript/dashboard/components-next/message/bubbles/Location.vue`

**Mudança:** garantir que renderize:
- **Topo:** mapa estático (Google Static Maps API ou Leaflet preview com lat/lng — ver o que já está implementado)
- **Subtítulo:** `attachment.fallback_title` (endereço Nominatim), com truncate em 2-3 linhas e CSS pra não quebrar layout
- **Botão/link:** "Abrir no Maps" → `https://www.google.com/maps?q=LAT,LNG`

**Padrão visual:** seguir Tailwind only, paleta `bg-n-solid-1`, `dark:bg-[#202c33]`, etc. (sem CSS custom).

**Verificar primeiro:** o componente atual já mostra o subtítulo? Se sim, só ajustar estilo; se não, adicionar.

### Passo 4 — Estender filtro de echo pra mensagens-erro técnicas

**Arquivo:** `app/controllers/api/v1/accounts/conversations/messages_controller.rb`

**Adicionar:**
```ruby
WAHA_ERROR_MARKERS = [
  '⚠️ Não foi possível',
  '❌ Não há mais tentativas',
  'ChatWoot API Error',
  'API Error: Request failed',
  'error: insert into',
  '0NaN-NaN-NaN',
  'Invalid URL',
  'ERR_INVALID_URL',
  'app_chatwoot_chatwoot_messages',
  'Tentativa: 3 / 3'
].freeze

def waha_error_message?(content)
  return false if content.blank?
  WAHA_ERROR_MARKERS.count { |marker| content.include?(marker) } >= 2
end
```

**Onde aplicar:** no `create` (POST /messages do api inbox), antes de criar a Message:
```ruby
if waha_echo?(message_params[:content]) || waha_error_message?(message_params[:content])
  return render json: { status: 'suppressed', reason: ... }
end
```

**Por que `>= 2 markers`:** evitar falso-positivo quando alguém digita uma frase casual contendo 1 marker.

### Passo 5 — Limpeza do banco (opcional, só homologação)

Apagar mensagens-lixo já existentes na inbox 43 (homologação) pra Walisson ver o painel limpo imediatamente:

```ruby
# Rails runner
markers = WAHA_ERROR_MARKERS  # mesma lista
deleted = 0
Message.where(inbox_id: 43).where('created_at >= ?', 6.hours.ago).find_each do |m|
  hits = markers.count { |k| m.content.to_s.include?(k) }
  if hits >= 2
    m.destroy
    deleted += 1
  end
end
puts "DELETED=#{deleted}"
```

⚠️ **NÃO rodar em produção** sem revisar.

### Passo 6 — Specs

**Arquivo:** `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb`

**Adicionar 4 cenários:**
1. `share_location` cria Message com `content` vazio + attachment com fallback_title preenchido.
2. Echo location continua suprimido (mantém comportamento existente).
3. Mensagem-erro técnica (`⚠️ Não foi possível` + `error: insert into`) → suprimida com reason `waha_error_message`.
4. Mensagem legítima com 1 marker isolado ("Não foi possível terminar agora") → criada normalmente (não suprimida).

**Arquivo:** novo `spec/requests/api/v1/accounts/conversations/messages_share_location_spec.rb` (request spec) — opcional mas recomendado pra cobrir ponta-a-ponta o `share_location`.

### Passo 7 — Build + restart

```bash
cd /home/chatwoot/chatwoot
NODE_OPTIONS="--max-old-space-size=8192" RAILS_ENV=production bundle exec rake assets:precompile
sudo -n systemctl restart chatwoot.target
```

### Passo 8 — Validação manual (Walisson)

1. Abrir conversa de teste em `https://hmlchat.simplexsolucoes.com.br` (homologação local).
2. Clicar **+** → **Compartilhar localização** → mover mapa → **Enviar**.
3. **Esperado no painel:**
   - Apenas **1 bubble** com mapa + endereço como subtítulo
   - Sem "📱 Enviado via API"
   - Sem "📍 Localização compartilhada / 🔗 Ver no mapa"
4. **Esperado no celular do destinatário:**
   - Card de localização nativo do WhatsApp (sem mudança — já estava OK)
5. Aguardar 30s — confirmar que **NÃO aparecem** mensagens-lixo (`⚠️ Não foi possível...` etc).

---

## 5. Critérios de aceite

- [ ] `bundle exec rspec spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` passa 100%
- [ ] `pnpm eslint` em `LocationPickerModal.vue` e `Location.vue` sem erros
- [ ] `bundle exec rubocop -a` sem offenses
- [ ] Build assets sem warning de erro (warnings de chunk size > 500kB são OK)
- [ ] No painel: 1 bubble por mensagem location, sem texto duplicado
- [ ] No celular destinatário: location nativa chega normalmente
- [ ] Mensagens-erro técnicas do app externo NÃO aparecem mais
- [ ] Mensagens reais do destinatário continuam chegando (não pegou no filtro errado)
- [ ] Working tree only — nenhum commit feito (regra do projeto)

---

## 6. Riscos & mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Falso-positivo no `waha_error_message?` (mensagem legítima do destinatário casa com 2 markers) | Baixa | Médio | Threshold `>= 2 markers`; markers escolhidos são fortemente técnicos (texto SQL, emoji ⚠️ + ❌, "Tentativa: 3/3"). Spec cobre caso negativo. |
| `LocationBubble` não renderizar bem no dark mode | Média | Baixo | Validar com Playwright em dark mode antes de reportar pronto. |
| `share_location` quebrar pra inboxes não-WAHA (Channel::Whatsapp Cloud, Twilio etc) | Baixa | Alto | A mudança é só de `content` vazio + `fallback_title` rico — não toca no fluxo de outbound de outros canais. Manter spec cobrindo Channel::Whatsapp pra garantir. |
| Apagar mensagem-lixo do banco em homologação afetar histórico relevante | Baixa | Médio | Limitar query a `created_at >= 6.hours.ago` E `hits >= 2 markers`. **Nunca rodar em produção.** |
| Frontend cacheado no navegador do agente — não pegar bundle novo | Alta | Baixo | Ctrl+Shift+R no navegador. Documentar no aviso final. |

---

## 7. Riscos NÃO mitigados (limitações conhecidas)

1. **App externo continua bugado:** o `Date(undefined).toISOString()` que gera `0NaN-NaN-NaN` permanece. Se aparecerem novas variações de mensagens-erro com markers diferentes, vão escapar do filtro. Ação contínua: adicionar markers novos quando aparecerem.

2. **Sem deploy automático pra `chatspx.app`:** os fixes ficam só na homologação. Walisson precisa promover pro SaaS via processo de deploy (fora do escopo deste plano).

3. **Pseudo-card antigo do app externo:** mesmo com filtro, mensagens-lixo já persistidas no banco antes do filtro continuam visíveis. Passo 5 (limpeza) só afeta homologação.

---

## 8. Apêndice A — Comandos úteis

### Rodar specs
```bash
cd /home/chatwoot/chatwoot && eval "$(rbenv init -)" 2>/dev/null
bundle exec rspec spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb \
                  spec/services/waha/outbound_special_message_service_spec.rb \
                  spec/listeners/webhook_listener_spec.rb 2>&1 | tail -10
```

### Build + restart
```bash
NODE_OPTIONS="--max-old-space-size=8192" RAILS_ENV=production bundle exec rake assets:precompile
sudo -n systemctl restart chatwoot.target
```

### Inspecionar Message location no Rails
```ruby
m = Message.last  # ou Message.find(ID)
puts "content=#{m.content.inspect}"
puts "additional=#{m.additional_attributes.inspect}"
a = m.attachments.first
puts "attachment: type=#{a&.file_type} lat=#{a&.coordinates_lat} lng=#{a&.coordinates_long} fallback=#{a&.fallback_title.inspect}"
```

### Limpar mensagens-lixo (só homologação)
```bash
bundle exec rails runner '
  markers = ["⚠️ Não foi possível", "❌ Não há mais tentativas", "ChatWoot API Error",
             "error: insert into", "0NaN-NaN-NaN", "Invalid URL", "ERR_INVALID_URL",
             "app_chatwoot_chatwoot_messages", "Tentativa: 3 / 3"]
  deleted = 0
  Message.where(inbox_id: 43).where("created_at >= ?", 6.hours.ago).find_each do |m|
    if markers.count { |k| m.content.to_s.include?(k) } >= 2
      puts "DELETING MID=#{m.id} CONTENT=#{m.content.to_s[0..80]}"
      m.destroy
      deleted += 1
    end
  end
  puts "TOTAL=#{deleted}"
'
```

---

## 9. Apêndice B — Arquivos relevantes (índice)

| Arquivo | Linha | Papel |
|---------|-------|-------|
| `app/controllers/api/v1/accounts/conversations/messages_controller.rb` | 4-10 | Constantes filtro WAHA (estender) |
| `app/controllers/api/v1/accounts/conversations/messages_controller.rb` | ~112 | Método `share_location` (limpar `content`) |
| `app/services/waha/outbound_special_message_service.rb` | — | Bypass outbound location/contact (já implementado, não mexer) |
| `app/services/waha/api_service.rb` | — | Cliente HTTP WAHA (já implementado) |
| `app/listeners/webhook_listener.rb` | — | Suprime webhook normal pra Channel::Api WAHA com location/contact (já implementado) |
| `app/javascript/dashboard/components-next/location/LocationPickerModal.vue` | — | Modal envio (ajustar payload — não mandar content poluído) |
| `app/javascript/dashboard/components-next/message/bubbles/Location.vue` | — | Card nativo de render (garantir subtítulo bonito) |
| `app/javascript/dashboard/components-next/message/Message.vue` | 48 | Importa `LocationBubble` (não mexer) |
| `app/models/attachment.rb` | 42, 127-139 | enum `file_type=4 location` + `location_metadata` (não mexer) |
| `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` | 114-181 | Specs filtro echo (estender) |
| `spec/services/waha/outbound_special_message_service_spec.rb` | — | Specs do service (não mexer — já cobre 12 cenários) |

---

## 10. Apêndice C — Histórico de specs/fixes (regression test surface)

Estes specs **devem continuar passando** após as mudanças deste plano:

1. `Waha::OutboundSpecialMessageService`
   - 12 cenários: location, contact saved, contact manual, idempotência (source_id present), UUID fallback pra contact.phone_number, error handling
2. `Waha::ApiService`
   - send_location, send_contact_vcard (plural array), send_text_with_vcard, build_vcard, check_contact_exists
3. `WebhookListener`
   - message_created Channel::Api WAHA com location bypassa webhook normal
   - message_updated Channel::Api WAHA com location NÃO reenvia REST
   - mensagem texto regular segue webhook normal
4. `MessagesController`
   - `share_location` (após mudança) → content vazio
   - `waha_echo?` suprime echo location/contact
   - `waha_error_message?` (NOVO) suprime mensagens-erro técnicas
   - Mensagem com 1 marker isolado → não suprime

Total esperado: **45+ specs passando, 0 falhas.**

---

## 11. Próximos passos (após este plano)

1. **Implementar este plano** — sequencial, passos 1→8.
2. **Deploy pra `chatspx.app`** — fora do escopo deste documento, depende de processo do time.
3. **Próxima fase opcional:** dado que `Waha::OutboundSpecialMessageService` agora cobre location/contact, avaliar **deprecação completa do app `chatwoot-waha-app`** — substituir por bypass direto também pra outros tipos de mensagem (texto, imagem, áudio, vídeo, documento). Reduz superfície de bugs e remove o ruído do painel na fonte. Tarefa grande, fora deste plano.

---

**FIM DO DOCUMENTO.** Auto-contido — qualquer agente/dev pode pegar este `.md` sozinho e executar sem contexto adicional.
