# Plano técnico — 3 ideias do menu "+"

> Gerado em 2026-05-05 por @aiox-master squad
> Escopo: viabilidade técnica detalhada das 3 ideias APROVADAS pelo Walisson
> Repo: `/home/chatwoot/chatwoot` · branch `homologacao`
> Stack: Rails + Vue 3 Composition + Tailwind + WAHA + WhatsApp Cloud API

---

## TL;DR

| # | Ideia | Esforço | Risco | Recomendação |
|---|-------|--------|-------|--------------|
| 1 | Respostas rápidas no "+" | **S — 6h** | nenhum | **Implementar agora** (quick win) |
| 2 | Inserir localização | **M — 22h** | médio (geocoder) | **Implementar agora** (1 sprint) |
| 3 | Compartilhar contato (vCard) | **M-L — 28h** | privacidade + WAHA Chatwoot App handshake | **Fazer depois** (validar entrega de attachments tipo `contact` via webhook chatwoot-app antes) |

**Total combinado: ~56h dev (~1.5 sprint).** Os 3 reaproveitam infra existente — o modelo `Attachment` já tem enums `:location` e `:contact`, com colunas `coordinates_lat/long`, `external_url`, `fallback_title`, `meta jsonb`. O parsing inbound já existe em `app/services/whatsapp/incoming_message_base_service.rb:164` e `:194`. Falta o **caminho outbound** (composer → backend → provider).

**Decisão crítica preliminar (validar com Walisson):** o canal WAHA usado pela Simplex passa mensagens via `Channel::Api` + `webhook_url` apontando pra `WAHA Chatwoot App`. Não temos como saber se o WAHA Chatwoot App suporta repassar attachments com `file_type=location`/`contact` sem testar — recomendo fazer um spike de 2h **antes** de iniciar idea 2/3 (testar enviar uma message com attachment location pelo Channel::Api e checar se o WAHA Chatwoot App entrega no WhatsApp como location nativa). Se não suportar, plano B é ChatSPX chamar WAHA REST direto (`POST /api/sendLocation`) — mas exige novo wrapper no Channel::Api.

---

## 1. Respostas rápidas (canned responses) no menu "+"

### A. Estado atual no codebase

**Backend (100% pronto):**
- Model: `app/models/canned_response.rb` (linha 13: `class CannedResponse < ApplicationRecord`)
- Controller: `app/controllers/api/v1/accounts/canned_responses_controller.rb` (CRUD completo)
- Store association: `app/models/account.rb:111` (`has_many :canned_responses, dependent: :destroy_async`)

**Frontend (90% pronto, só falta entry point):**
- Componente picker: `app/javascript/dashboard/components/widgets/conversation/CannedResponse.vue` (52 linhas — usa `MentionBox`, fetcha via `$store.dispatch('getCannedResponse', { searchKey })`).
- Trigger atual: digitar `/` no editor — implementado em `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue:294-299`:
  ```js
  createSuggestionPlugin({
    trigger: '/',
    showMenu: showCannedMenu,
    searchTerm: cannedSearchTerm,
    isAllowed: () => !props.isPrivate,
  })
  ```
- Watch que emite pro pai: `Editor.vue:328-330` (`emit('toggleCannedMenu', !props.isPrivate && updatedValue)`).
- Pai escuta: `ReplyBox.vue:2407` (`@toggle-canned-menu="toggleCannedMenu"`) → `ReplyBox.vue:1095` (handler `toggleCannedMenu(value)`).

**Onde adicionar entrada no "+":**
- Composer "wa" (estilo WhatsApp, padrão ChatSPX): `ReplyBox.vue:2335-2374` (DropdownContainer com `i-lucide-plus` em :2344).
- Composer legacy: `ReplyBottomPanel.vue:345-393` (mesmo dropdown, `i-lucide-plus` em :349).

### B. O que precisa ser construído

**Frontend apenas (sem backend):**
- Adicionar `<DropdownItem>` em **2 lugares** (composer "wa" + legacy):
  - Label: `$t('CONVERSATION.REPLYBOX.CANNED_RESPONSES_PICKER')`
  - Icon: `i-lucide-zap` (já em uso pelo ChatSPX para canned-related, ver `Sidebar.vue:809` e `ScheduleDateTimePicker.vue:87`)
  - `:click` → handler novo `triggerCannedMenu()` que injeta `/` no editor (truque ProseMirror: chamar `editorView.dispatch(tr.insertText('/'))`) ou expor método público no Editor `openCannedMenu()`.
- Gate: `v-if="!isOnPrivateNote && enableCannedResponses"`.
- Método novo no `ReplyBox.vue`:
  ```js
  triggerCannedMenu() {
    this.$refs.messageEditor?.openCannedMenu();
  }
  ```
- Método público novo em `Editor.vue` (expor via `defineExpose`):
  ```js
  function openCannedMenu() {
    if (props.isPrivate || !props.enableCannedResponses) return;
    showCannedMenu.value = true;
    cannedSearchTerm.value = '';
    editorView?.focus();
  }
  defineExpose({ openCannedMenu });
  ```
- i18n: adicionar key em `app/javascript/dashboard/i18n/locale/en/conversation.json` e `pt_BR/conversation.json`:
  - `CONVERSATION.REPLYBOX.CANNED_RESPONSES_PICKER` = `"Quick replies"` / `"Respostas rápidas"`

**Backend:** zero alterações.

**Provider:** zero — canned responses são expandidas client-side no editor antes de enviar.

### C. Esforço estimado

| Task | Tempo | Complexidade |
|------|-------|--------------|
| Adicionar `defineExpose({ openCannedMenu })` em `Editor.vue` | 1h | trivial |
| Adicionar `<DropdownItem>` em `ReplyBox.vue` (composer wa) | 1h | trivial |
| Adicionar `<DropdownItem>` em `ReplyBottomPanel.vue` (legacy) | 1h | trivial |
| Adicionar i18n keys (en + pt_BR) | 0.5h | trivial |
| Testar manual em dev (Playwright/manual) | 1.5h | baixa |
| Eslint/Rubocop/build assets | 1h | trivial |
| **Total** | **6h** | — |

### D. Riscos

- **Posicionamento do popup**: o `MentionBox` é posicionado absolute pelo cursor do editor. Se o usuário abrir pelo `+` sem ter cursor ativo, o popup pode aparecer offscreen. **Mitigar**: forçar `editorView.focus()` antes de mostrar, e se o editor estiver vazio, simular um caret no fim.
- **Permissão Meta**: nenhuma — é UX local.
- **WAHA Plus only**: não — é texto puro.
- **Quebra retrocompat**: nenhuma — é addition only.
- **Bibliotecas externas**: nenhuma.

### E. Snippet de implementação conceitual

```vue
<!-- ReplyBox.vue (e ReplyBottomPanel.vue): adicionar dentro do DropdownBody -->
<DropdownItem
  v-if="!isOnPrivateNote"
  :label="$t('CONVERSATION.REPLYBOX.CANNED_RESPONSES_PICKER')"
  icon="i-lucide-zap"
  :click="triggerCannedMenu"
/>

<!-- methods em ReplyBox.vue -->
methods: {
  triggerCannedMenu() {
    this.$refs.messageEditor?.openCannedMenu();
  },
}

<!-- Editor.vue: novo método exposto -->
function openCannedMenu() {
  if (props.isPrivate) return;
  showCannedMenu.value = true;
  cannedSearchTerm.value = '';
  editorView?.focus();
}
defineExpose({ openCannedMenu });
```

Fluxo: `[click no +]` → DropdownItem dispara `triggerCannedMenu` → ReplyBox chama `messageEditor.openCannedMenu()` → Editor seta `showCannedMenu=true` → `<CannedResponse>` renderiza (já existe via `v-if="shouldShowCannedResponses"` em `Editor.vue:875-879`) → atendente clica num canned → emit `replace` → `insertSpecialContent('cannedResponse', content)` (`Editor.vue:689`).

### F. Recomendação

**Implementar agora.** Esforço S, impacto L (discoverability). Quick win clássico — atendentes novos da Clara Tozi (piloto) não vão saber do atalho `/`; entry point visual resolve. Zero risco técnico, zero dependência externa, reaproveita 100% do que existe. Faz sentido como **primeira PR** desta tríade pra validar o padrão de adicionar items no menu "+".

---

## 2. Inserir localização

### A. Estado atual no codebase

**Inbound (parser de location recebida — 100% pronto):**
- `app/services/whatsapp/incoming_message_base_service.rb:85` (`attach_location if message_type == 'location'`)
- `app/services/whatsapp/incoming_message_base_service.rb:164-175`:
  ```ruby
  def attach_location
    location = messages_data.first['location']
    location_name = location['name'] ? "#{location['name']}, #{location['address']}" : ''
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      coordinates_lat: location['latitude'],
      coordinates_long: location['longitude'],
      fallback_title: location_name,
      external_url: location['url']
    )
  end
  ```
- Twilio também: `app/services/twilio/incoming_message_service.rb:20` e `:190`.

**Modelo Attachment (100% pronto):**
- `app/models/attachment.rb:42`: enum tem `:location => 4` (e `:contact => 8`).
- Colunas existentes: `coordinates_lat :float`, `coordinates_long :float`, `fallback_title :string`, `external_url :string` (linhas 6-10 do schema).
- `app/models/attachment.rb:127-134`: `location_metadata` já formatado pra push event.

**Renderização (100% pronta):**
- `app/javascript/dashboard/components-next/message/bubbles/Location.vue` já existe — referencia `attachment.value.coordinatesLat/Long`.
- Fixture: `app/javascript/dashboard/components-next/message/fixtures/textWithMedia.js` tem exemplo.

**Outbound (NÃO existe):**
- `Whatsapp::Providers::WhatsappCloudService#send_message` (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:2-12`) só roteia entre `send_attachment_message`, `send_interactive_text_message`, `send_text_message`. **Nenhuma rota pra `type: 'location'`.**
- `send_attachment_message` (linha 117-138) só trata image/audio/video/document — usa `attachment.download_url`, ignora coordenadas.
- `Whatsapp::Providers::Whatsapp360DialogService` (linha 74-94) idêntico — só media files.
- `Waha::ApiService` (`app/services/waha/api_service.rb:9-106`) **não tem método pra send** — o envio hoje é via Channel::Api → webhook → WAHA Chatwoot App. WAHA tem `POST /api/sendLocation` nativo e free, mas não está exposto.

**UI:** zero — não existe `LocationPicker` nem botão de localização em nenhum lugar do composer.

### B. O que precisa ser construído

**Frontend:**
- **Novo componente** `app/javascript/dashboard/components/widgets/conversation/LocationPicker.vue` (~180 linhas):
  - Modal com input de busca (autocomplete via Nominatim ou Google Maps Geocoding)
  - Mapa preview (Leaflet + OpenStreetMap = zero custo, ou Google Maps com chave)
  - Campos resultantes: `latitude`, `longitude`, `name`, `address`
  - Botão "Enviar localização"
- Adicionar `<DropdownItem>` em `ReplyBox.vue:2347-2373` e `ReplyBottomPanel.vue:356-392`:
  - Icon: `i-lucide-map-pin`
  - Label: `CONVERSATION.REPLYBOX.SEND_LOCATION`
  - Gate: `v-if="canSendLocation"` (whitelist canais: WAHA via Channel::Api + WhatsApp Cloud + 360Dialog + Twilio WhatsApp)
- Action no store: `dashboard/store/modules/conversations.js` — novo `sendLocation({ conversationId, latitude, longitude, name, address })`
- API client: `dashboard/api/inbox/message.js` — novo `sendLocation(...)` que faz `POST /api/v1/accounts/:account_id/conversations/:id/messages` com payload especial.
- i18n: novas keys em en/pt_BR:
  - `CONVERSATION.REPLYBOX.SEND_LOCATION`
  - `CONVERSATION.REPLYBOX.LOCATION_PICKER.TITLE`
  - `CONVERSATION.REPLYBOX.LOCATION_PICKER.SEARCH_PLACEHOLDER`
  - `CONVERSATION.REPLYBOX.LOCATION_PICKER.SEND_BUTTON`

**Backend:**
- Estender `Messages::MessageBuilder` (`app/builders/messages/message_builder.rb`) ou parameter-passing em `MessagesController#create` pra aceitar `attachments[][file_type]=location` + `coordinates_lat/long/external_url/fallback_title`. Hoje o create message só aceita File via `multipart/form-data`. Precisa aceitar JSON inline com metadata de location (~30 linhas).
- Estender providers — **adicionar `send_location_message` em ambos**:
  - `app/services/whatsapp/providers/whatsapp_cloud_service.rb` — novo método (~25 linhas):
    ```ruby
    def send_location_message(phone_number, message)
      attachment = message.attachments.first
      response = HTTParty.post(
        "#{phone_id_path}/messages",
        headers: api_headers,
        body: {
          messaging_product: 'whatsapp',
          to: phone_number,
          type: 'location',
          location: {
            latitude: attachment.coordinates_lat,
            longitude: attachment.coordinates_long,
            name: attachment.fallback_title,
            address: attachment.external_url || ''
          }
        }.to_json
      )
      process_response(response, message)
    end
    ```
  - `app/services/whatsapp/providers/whatsapp_360_dialog_service.rb` — análogo.
  - Mudar dispatch em ambos `send_message`: `if attachments.present? && attachments.first.file_type == 'location' → send_location_message`.
- **WAHA via Channel::Api**: o webhook outbound (`webhook_listener.rb:120-126`) já manda payload com `attachments[]` incluindo `file_type` e `coordinates_lat/long`. **Spike de 2h pra confirmar que o WAHA Chatwoot App reconhece esse shape e dispara `sendLocation` no WhatsApp**. Se não reconhecer:
  - Plano B: criar `Waha::ApiService#send_location(session_name, chat_id, lat, long, name)` (~20 linhas) chamando `POST /api/sendLocation`, e novo job `Waha::SendLocationJob` ou adicionar método `send_message` no `Channel::Api` que checa se inbox tem `waha_session_name` e roteia direto pra WAHA antes do webhook.

**Provider chamadas exatas:**
- **WAHA**: `POST /api/sendLocation` body `{ session, chatId, latitude, longitude, title }` — free tier, todos engines (WEBJS/NOWEB/GOWS).
- **Cloud API**: `POST /v13.0/{phone_id}/messages` body `{ messaging_product: "whatsapp", to, type: "location", location: { latitude, longitude, name, address } }`.

**Sem migration** — colunas já existem em `attachments`.

### C. Esforço estimado

| Task | Tempo | Complexidade |
|------|-------|--------------|
| **Spike**: testar WAHA Chatwoot App com attachment file_type=location | 2h | desconhecido |
| Componente Vue `LocationPicker.vue` (modal + busca + map preview) | 6h | média |
| Integração Leaflet (vendoring + Tailwind override) | 2h | baixa |
| Estender `MessagesController#create` pra aceitar location attachment | 2h | média |
| `send_location_message` em `WhatsappCloudService` | 1h | trivial |
| `send_location_message` em `Whatsapp360DialogService` | 0.5h | trivial |
| Wrapper `Waha::ApiService#send_location` (se spike falhar) | 1.5h | média |
| Action store + API client | 1h | baixa |
| Adicionar item no menu "+" (2 composers) | 1h | trivial |
| i18n en/pt_BR | 0.5h | trivial |
| Specs Ruby (provider services) | 2h | média |
| Specs JS (LocationPicker mount) | 1h | baixa |
| Manual QA (envio real Cloud + WAHA) | 1.5h | baixa |
| **Total** | **22h** | — |

### D. Riscos

- **Geocoder provider**: Nominatim free tem rate limit baixo (1 req/s, atribuição obrigatória) — pode estourar com vários atendentes simultâneos. Google Maps Geocoding custa US$5/1000 calls após free tier de US$200/mês. **Mitigar**: cache server-side de queries (Redis 24h TTL), debounce 400ms no input, ou começar com Nominatim e migrar pra Google só se houver demanda.
- **Mapa**: Leaflet + OSM tile = livre. Google Maps JS precisa chave + billing ativo.
- **WAHA Chatwoot App handshake**: principal incógnita — **spike obrigatório antes** de fechar escopo.
- **Permissão Meta**: nenhuma — `type: location` é unauth-template, livre.
- **WAHA Plus only**: NÃO — `sendLocation` é free tier todos engines.
- **Quebra retrocompat**: nenhuma — addition only no path de envio.
- **Privacidade**: localização pode ser do contato, não do atendente. UI deve deixar claro que é "localização que você está enviando" (não geolocation do navegador do atendente).

### E. Snippet de implementação conceitual

```js
// dashboard/api/inbox/message.js (novo método)
sendLocation({ conversationId, latitude, longitude, name, address }) {
  return axios.post(`${this.url}/${conversationId}/messages`, {
    content: name || address,
    message_type: 'outgoing',
    attachments: [{
      file_type: 'location',
      coordinates_lat: latitude,
      coordinates_long: longitude,
      fallback_title: name,
      external_url: address,
    }],
  });
}
```

```ruby
# app/services/whatsapp/providers/whatsapp_cloud_service.rb — extend send_message
def send_message(phone_number, message)
  @message = message
  if message.attachments.first&.file_type == 'location'
    send_location_message(phone_number, message)
  elsif message.attachments.present?
    send_attachment_message(phone_number, message)
  elsif message.content_type == 'input_select'
    send_interactive_text_message(phone_number, message)
  else
    send_text_message(phone_number, message)
  end
end
```

Fluxo: `[click no + → Localização]` → `LocationPicker` modal → atendente busca endereço → Nominatim retorna lat/long → submit chama `sendLocation` → API cria Message com Attachment (file_type=location, coordinates) → `Whatsapp::SendOnWhatsappService` → `provider_service.send_message` → router detecta `file_type=location` → POST Cloud API com `type: location`. Para WAHA, o webhook do Channel::Api dispara e o WAHA Chatwoot App (ou wrapper REST plano B) faz `POST /api/sendLocation`.

### F. Recomendação

**Implementar agora.** Custo M (22h, ~1 sprint), impacto M-L pras verticais-alvo (imobiliária, clínica, escola — todas mencionadas pelo Walisson como piloto). Diferenciador real vs Chatwoot vanilla (não tem). Zero permissão Meta exigida. **Pre-condição**: spike de 2h confirmando comportamento do WAHA Chatwoot App. Se o spike mostrar que precisa de wrapper REST direto pra WAHA, somar +4h de plano B (total 26h, ainda dentro de sprint).

---

## 3. Compartilhar contato (vCard)

### A. Estado atual no codebase

**Inbound (parser de contato recebido — 100% pronto):**
- `app/services/whatsapp/incoming_message_base_service.rb:194-212`:
  ```ruby
  def attach_contact(contact)
    phones = contact[:phones]
    phones = [{ phone: 'Phone number is not available' }] if phones.blank?
    name_info = contact['name'] || {}
    contact_meta = { firstName: name_info['first_name'], lastName: name_info['last_name'] }.compact
    phones.each do |phone|
      @message.attachments.new(
        account_id: @message.account_id,
        file_type: file_content_type(message_type),
        fallback_title: phone[:phone].to_s,
        meta: contact_meta
      )
    end
  end
  ```
- Telegram: `app/services/telegram/incoming_message_service.rb:185` (`file_type: :contact`).

**Modelo Attachment:**
- `app/models/attachment.rb:42` — enum tem `:contact => 8`.
- `app/models/attachment.rb:152-157` — `contact_metadata` retorna `{ fallback_title, meta }` (meta jsonb com firstName/lastName/etc).

**Renderização (100% pronta):**
- `app/javascript/dashboard/components-next/message/bubbles/Contact.vue` — já renderiza, com botão "abrir contato" (`openContactNewTab`), busca por número (`filterContactByNumber` via `contacts/filter`), cria contato se não existe.
- Fixture em `textWithMedia.js:107`.

**Outbound (NÃO existe):**
- Nenhum serviço Whatsapp/Cloud/360Dialog/Twilio expõe envio de contact. WAHA tem `POST /api/sendContactVcard` nativo free, idem Cloud API `type: contacts`.
- Não há `to_vcard` no `Contact` model.

**UI:**
- Não existe `ContactPicker` reutilizável no composer. Existe seleção de contato dentro de "Forward message" (`app/services/messages/forward_service.rb`) via `ContactSearch` — mas é form de busca de contato pra **destinatário**, não pra anexar como conteúdo.
- Existe `app/javascript/dashboard/components/widgets/conversation/contact/` — mas é o painel lateral, não picker.

### B. O que precisa ser construído

**Frontend:**
- **Novo componente** `ContactPickerModal.vue` (~200 linhas):
  - Search input (debounced) que dispara `$store.dispatch('contacts/search', { q })`
  - Lista virtualizada de contatos (paginação cliente-lado)
  - Seleção múltipla (WhatsApp permite enviar mais de 1 vCard numa msg — Cloud API `contacts: []` aceita array)
  - Preview do vCard que será enviado (nome + telefone + email)
  - Botão "Enviar contato"
- Adicionar `<DropdownItem>` em `ReplyBox.vue:2347-2373` e `ReplyBottomPanel.vue:356-392`:
  - Icon: `i-lucide-user-round` ou `i-lucide-id-card`
  - Label: `CONVERSATION.REPLYBOX.SHARE_CONTACT`
  - Gate: `v-if="canShareContact"` (mesma whitelist da localização)
- Action store: `sendContact({ conversationId, contactIds })`
- API client: novo método `sendContact`
- i18n: keys correspondentes

**Backend:**
- Novo helper `Contact#to_vcard_string` em `app/models/contact.rb` (~25 linhas) gerando vCard 3.0:
  ```ruby
  def to_vcard_string
    [
      'BEGIN:VCARD',
      'VERSION:3.0',
      "FN:#{name}",
      "TEL;TYPE=CELL:#{phone_number}",
      email.present? ? "EMAIL:#{email}" : nil,
      'END:VCARD'
    ].compact.join("\n")
  end
  ```
- Estender `MessagesController#create` pra aceitar `attachments[][file_type]=contact` + `meta` + `fallback_title` (~20 linhas).
- Estender providers:
  - `WhatsappCloudService#send_contact_message` (~30 linhas) — payload Cloud API:
    ```json
    { "messaging_product": "whatsapp", "to": "...", "type": "contacts",
      "contacts": [{ "name": { "formatted_name": "...", "first_name": "..." },
                     "phones": [{ "phone": "...", "type": "CELL" }] }] }
    ```
  - `Whatsapp360DialogService#send_contact_message` — análogo.
- **WAHA**: idem location — depende do WAHA Chatwoot App suportar `attachment.file_type=contact` no payload do webhook outbound. Se não suportar, criar `Waha::ApiService#send_contact_vcard(session, chat_id, vcard_string)` chamando `POST /api/sendContactVcard`.

**Provider chamadas exatas:**
- **WAHA**: `POST /api/sendContactVcard` body `{ session, chatId, contacts: [{ vcard: "BEGIN:VCARD..." }] }` — free tier todos engines.
- **Cloud API**: `POST /v13.0/{phone_id}/messages` body com `type: "contacts"`, array `contacts[]` com name + phones.

**Sem migration** — usa `attachments.meta` jsonb.

### C. Esforço estimado

| Task | Tempo | Complexidade |
|------|-------|--------------|
| Spike validação WAHA Chatwoot App com file_type=contact | 1h | desconhecido (compartilhado com idea 2) |
| Helper `Contact#to_vcard_string` + spec | 1h | trivial |
| `ContactPickerModal.vue` (search + multi-select + preview) | 8h | média |
| Estender `MessagesController#create` pra contact attachment | 2h | média |
| `send_contact_message` em `WhatsappCloudService` | 1.5h | baixa |
| `send_contact_message` em `Whatsapp360DialogService` | 1h | baixa |
| Wrapper `Waha::ApiService#send_contact_vcard` (se necessário) | 2h | média |
| Action store + API client | 1.5h | baixa |
| Adicionar item no menu "+" (2 composers) | 1h | trivial |
| Modal de confirmação ("Confirmar compartilhar telefone X?") | 2h | baixa |
| i18n en/pt_BR | 1h | trivial |
| Specs Ruby (vcard + provider) | 3h | média |
| Specs JS (picker + flow) | 2h | média |
| Manual QA (envio real, abrir vCard recebido em iOS+Android) | 1h | baixa |
| **Total** | **28h** | — |

### D. Riscos

- **Privacidade / LGPD**: compartilhar telefone de **outro contato** sem consentimento é violação LGPD. **Mitigar**: modal de confirmação explícito, log de auditoria (quem compartilhou qual contato pra quem), idealmente flag por conta `contact_sharing_enabled`. Walisson precisa decidir se quer este gate.
- **vCard format**: WhatsApp iOS rende vCard 3.0 e 4.0 OK, mas Android antigo às vezes só lê 3.0. Usar 3.0 por compat.
- **WAHA Chatwoot App handshake**: idem location — incógnita.
- **Permissão Meta**: nenhuma para Cloud API — `type: contacts` é unauth-template.
- **WAHA Plus only**: NÃO — `sendContactVcard` é free tier todos engines.
- **Quebra retrocompat**: nenhuma.
- **Bibliotecas externas**: nenhuma — vCard 3.0 é texto puro, gerado inline.
- **Volume**: Cloud API aceita até 257 contatos por msg, mas UX deve limitar a ~5 por sanidade.

### E. Snippet de implementação conceitual

```ruby
# app/models/contact.rb (extend)
def to_vcard_string
  parts = [
    'BEGIN:VCARD',
    'VERSION:3.0',
    "FN:#{name}",
    "N:#{name};;;;",
  ]
  parts << "TEL;TYPE=CELL:#{phone_number}" if phone_number.present?
  parts << "EMAIL:#{email}" if email.present?
  parts << 'END:VCARD'
  parts.join("\n")
end
```

```ruby
# app/services/whatsapp/providers/whatsapp_cloud_service.rb
def send_contact_message(phone_number, message)
  contacts_payload = message.attachments.map do |att|
    {
      name: { formatted_name: att.fallback_title, first_name: att.meta&.dig('firstName') || att.fallback_title },
      phones: [{ phone: att.meta&.dig('phone') || att.fallback_title, type: 'CELL' }]
    }
  end
  HTTParty.post(
    "#{phone_id_path}/messages",
    headers: api_headers,
    body: { messaging_product: 'whatsapp', to: phone_number, type: 'contacts', contacts: contacts_payload }.to_json
  ).then { |r| process_response(r, message) }
end
```

Fluxo: `[click no + → Compartilhar contato]` → `ContactPickerModal` → atendente busca/seleciona N contatos → preview vCard → confirma → API cria Message com N attachments (file_type=contact, meta com firstName/lastName/phone) → provider router detecta `file_type=contact` → Cloud API `type: contacts` ou WAHA `sendContactVcard` (uma chamada por contato no WAHA, ou um array no Cloud).

### F. Recomendação

**Fazer depois (após idea 1 e 2 entregues).** Custo M-L (28h), impacto M, mais risco LGPD que as outras 2. Recomendo:
- **Bloquear**: confirmar com Walisson se quer flag de privacidade (consentimento) e log de auditoria — isso muda escopo (+8h se sim).
- **Spike conjunto** com idea 2: investigar handshake WAHA Chatwoot App pra location E contact ao mesmo tempo (1h cobre ambos).
- **Ordem**: entregar 1 (canned) → 2 (location) → validar uso real → só então 3 (contact). Se idea 2 mostrar que WAHA Chatwoot App não suporta esse shape, idea 3 fica mais cara (precisa wrapper REST WAHA, +2h).

---

## Sequência sugerida de implementação

| Sprint | PR | Conteúdo | Pré-requisito |
|--------|----|----------|---------------|
| **Sprint 1, semana 1** | PR-1 | Idea 1 (canned no "+") | nenhum |
| **Sprint 1, semana 1** | Spike | 2h investigar WAHA Chatwoot App com `attachment.file_type=location` no webhook outbound | `waha-spike` em VM dev |
| **Sprint 1, semana 1-2** | PR-2 | Idea 2 (localização) — backend providers + LocationPicker.vue + i18n | spike concluído |
| **Sprint 2, semana 1** | PR-3 (opcional) | Idea 2 plano B (`Waha::ApiService#send_location` + roteamento Channel::Api) — só se spike falhar | spike falhou |
| **Sprint 2, semana 2-3** | PR-4 | Idea 3 (vCard) — `Contact#to_vcard_string` + ContactPickerModal + providers | idea 2 estabilizada em homolog |

**Justificativa:**
- Idea 1 primeiro porque é S, sem risco, valida o padrão de "DropdownItem novo no menu +" que as outras 2 vão reusar.
- Idea 2 antes de Idea 3 porque tem maior impacto (verticais imobiliária/clínica) e o spike resolve a incógnita WAHA pra ambas.
- Se o spike mostrar incompatibilidade WAHA, Idea 3 herda o wrapper REST de Idea 2 (custo marginal -2h em Idea 3).
- Não fazer 2 e 3 na mesma PR: 1 PR = 1 ideia, fácil de revisar/reverter.

---

## Questões abertas pro Walisson

1. **Consentimento LGPD na Idea 3**: você quer flag por conta (`contact_sharing_enabled`) e log de auditoria? Adiciona ~8h mas blinda contra reclamação. Default: **sim, com flag desligada por padrão**, ativada por admin.
2. **Geocoder na Idea 2**: começar com **Nominatim free** (com cache Redis) ou já investir em **Google Maps Geocoding** (custo previsível)? Recomendação técnica: Nominatim com cache, migrar se houver demanda.
3. **Mapa preview na Idea 2**: vale o esforço de incluir Leaflet ou só mostrar lat/long + endereço em texto? Decisão UX — Leaflet adiciona ~40KB no bundle. Recomendação: **sim, vale** — atendente confirma visualmente que pegou o lugar certo.
4. **Posicionamento do menu "+" na Idea 1**: usar ícone `i-lucide-zap` (alinhado com o resto do ChatSPX para "rápido") ou `i-lucide-message-square-quote` (mais semântico "resposta pronta")? Recomendação: `i-lucide-zap` (consistência interna).
5. **Multi-select na Idea 3**: deixar atendente enviar múltiplos contatos numa mesma msg ou limitar a 1 por msg pra simplificar UX? WhatsApp suporta múltiplos, mas UX fica densa. Recomendação: **multi até 5**.
6. **Spike WAHA**: você tem ambiente WAHA dev acessível ou tenho que pedir ao @devops pra subir uma session de teste? Idealmente reusar `hmlchat` com inbox dedicada de teste.
7. **Inbox routing pra envio**: o gate `canSendLocation` / `canShareContact` deve checar `inbox.channel_type` (whitelist) ou usar feature flag `LOCATION_PICKER_ENABLED` por conta? Recomendação: gate por channel_type (técnico) + sem feature flag (simplicidade).

---

> **Resumo executivo:** os 3 itens são tecnicamente viáveis e reaproveitam a infra inbound já existente (modelo `Attachment` com enums/colunas prontos, parsers WhatsApp/Twilio, components-next/Location.vue + Contact.vue). O esforço total é ~56h dev (~1.5 sprint). O único bloqueador é o spike WAHA Chatwoot App de 2h — definir antes se attachments tipo location/contact no payload do webhook outbound do Channel::Api são repassados ao WhatsApp ou se precisamos wrapper REST direto.
