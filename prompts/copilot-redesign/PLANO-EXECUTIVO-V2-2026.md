# Plano Executivo V2 — Chat SPX, sprint pós-redesign Copilot

> Gerado em 2026-05-05 por @aiox-master (Orion) com squad de pesquisa + dev.
> Status: **APROVADO PRA EXECUÇÃO AUTÔNOMA** após decisões UX do Walisson.
> Branch: `homologacao` · VM: 192.168.8.232 (homologação) · Build: `RAILS_ENV=production rake assets:precompile`.
> Restart: `sudo systemctl restart chatwoot.target`.

---

## 0. TL;DR (executivo)

5 frentes paralelas, todas **autônomas** (build + restart + validação Playwright dual-theme + commit working tree):

| # | Frente | Squad | Esforço | Tema(s) | Crítico |
|---|--------|-------|:-------:|:------:|:------:|
| **F1** | Respostas rápidas — modal novo no `+` com busca (sem categorias na V1) | Agent A | 6h | light + dark | ⭐ |
| **F2** | Inserir localização — picker Leaflet + Nominatim + geolocation | Agent B | 22h | light + dark | ⭐⭐ |
| **F3** | Compartilhar contato (vCard) — 3 fontes (agente/contato/livre) | Agent C | 28h | light + dark | ⭐⭐ |
| **F4** | Fix tabs Minhas/Não atribuídas/Todos — fade + chevron + swipe | Agent D | 4h | light + dark | ⭐ |
| **F5** | Fix grid actions contato — encurtar i18n + fallback só-ícone | Agent E | 1.5h | light + dark | ⭐ |
| **Total** | 5 squads em paralelo | | **~63.5h** | | |

**Princípio orientador**: tudo deve ser óbvio pra atendente que NUNCA usou esse software antes ("usuário burro" é nosso baseline UX). Linguagem humana em pt-BR, sem jargão técnico (nada de "ISO", "lat/lng", "coordenadas", "vCard 3.0", "HSM", "WAHA"). Só verbos do dia-a-dia ("Compartilhar localização", "Enviar contato", "Resposta pronta", etc).

**Validação dupla**: cada frente é validada em **light** e **dark** via Playwright em viewport notebook (1366×768) — esse é o caso mais comum dos atendentes Simplex.

---

## 0.1 Spike obrigatório PRÉ-Sprint-3 (decidido após review crítico)

Antes de disparar F2 (Localização) e F3 (vCard), Orion roda **1 spike de 1h** pra confirmar o caminho de outbound WAHA. Existe ambiguidade conhecida: `Channel::Whatsapp::PROVIDERS = %w[default whatsapp_cloud]` (não inclui `waha`); o envio real passa por `Whatsapp::SendOnWhatsappService` → provider — e a Chat SPX usa **Chatwoot WAHA App** que recebe webhooks Chatwoot e traduz pra calls WAHA. Adicionar método em `Waha::ApiService` resolve só metade.

**Spike — passos**:
1. Localizar conversa real WhatsApp em `Account.find_by!(name: 'Simplex Tecnologia')` (id pode variar entre ambientes — sempre lookup por nome).
2. Via Rails console (rodar no servidor de homologação):
   ```ruby
   account = Account.find_by!(name: 'Simplex Tecnologia')
   conv = account.conversations.where.not(id: nil).order(created_at: :desc).find { |c| c.inbox.channel_type.to_s.include?('Whatsapp') }
   sender = AccountUser.where(account: account, role: :administrator).first&.user || account.users.first
   m = conv.messages.create!(
     message_type: :outgoing, content: 'spike location',
     sender: sender,
     attachments_attributes: [{
       file_type: :location, coordinates_lat: -15.6, coordinates_long: -56.1,
       fallback_title: 'Cuiabá'
     }]
   )
   puts m.id
   ```
3. Confirmar visualmente no celular destinatário se chegou como localização ou como texto/erro.
4. Decidir:
   - **Sucesso** → caminho `attachment` com enums já existentes (`Attachment#file_type` enum tem `location:4`). F2/F3 ficam SIMPLES (só frontend + i18n).
   - **Falha** → fallback REST direto: criar provider `Channel::Whatsapp::Providers::WahaService` (registrar em `PROVIDERS`), com `send_location(coords)`/`send_contact_vcard(...)`. Custo +6h por feature.
5. Documentar resultado em `EXECUTION-LOG.md` antes de disparar Sprint 3.

**Decisão única de modelo de dado** (resolver ambiguidade):
- F2 Localização → `attachment.file_type = :location`, `coordinates_lat`, `coordinates_long`, `fallback_title` (endereço). NÃO usar `additional_attributes.location` (descartado). Bubble `components-next/message/bubbles/Location.vue` JÁ espera exatamente este formato.
- F3 vCard → `attachment.file_type = :contact` (enum existe).

---

## 0.2 Ordem fixa do menu "+" do ReplyBox (canônica)

Pra evitar dança de ordem entre as 3 frentes que tocam `ReplyBox.vue` (F1, F2, F3) e manter o menu coerente após o merge, **a ordem é congelada**:

| # | Item | Ícone | Origem | Status |
|---|------|-------|--------|:------:|
| 1 | Anexar arquivo | `i-lucide-paperclip` | já existe | ✅ |
| 2 | Agendar mensagem | `i-lucide-calendar-clock` | sprint anterior | ✅ |
| 3 | Templates WhatsApp (HSM) | `i-lucide-file-badge` | já existe | ✅ |
| 4 | Templates Content (Twilio Content) | `i-lucide-message-square-text` | já existe | ✅ |
| 5 | Resposta pronta | `i-lucide-message-square-quote` | **F1** | 🆕 |
| 6 | Compartilhar localização | `i-lucide-map-pin` | **F2** | 🆕 |
| 7 | Compartilhar contato | `i-lucide-user-round-plus` | **F3** | 🆕 |

**Regra**: Cada agente que adicionar item DEVE inserir o `<DropdownItem>` no slot indicado acima (índice 1-based no template). Se o slot anterior ainda não existe (porque outro agente não terminou), inserir no fim e deixar TODO comment "ajustar ordem após merge F{N}".

Itens 3 e 4 (Templates WhatsApp/Content) ficam visíveis condicionalmente conforme o channel (já é assim hoje).

---

## 1. Decisões UX (com pesquisa 2026)

### 1.1 Localização — Nominatim free + geolocation híbrido (resp. **A+D**)

**Decisão**: usar [Leaflet](https://leafletjs.com/) (42KB, líder open-source mobile-friendly) + [Nominatim/OpenStreetMap](https://nominatim.org/) (zero-cost, sem chave) + `navigator.geolocation` pra "usar minha localização atual".

**Por quê**: pesquisa 2026 mostra que [Nominatim é a stack padrão pra address search free](https://www.geopostcodes.com/blog/open-street-maps-address-search/), e Leaflet é o lightweight mobile-first standard. Zero custo recorrente, zero chave de API (importante pra revenda Simplex). Geolocation native + fallback search resolve 95% dos casos de uso (atendente quer mandar local atual ou buscar endereço de cliente).

**UX pra usuário leigo**:
- Modal full-width com mapa em cima
- Botão grande verde "📍 Usar minha localização atual"
- OU campo de busca "Digite um endereço ou CEP"
- Mapa atualiza com pin arrastável
- Preview "Você vai enviar: Rua X, 123 — Centro, Cuiabá/MT"
- Botão "Enviar localização" / "Cancelar"

**Endpoint backend**: WAHA tem `POST /api/sendLocation` no tier free, todos engines (WEBJS/NOWEB/GOWS/WPP) — payload `{session, chatId, latitude, longitude, accuracy?}` ([fonte](https://waha.devlike.pro/docs/how-to/send-messages/)).

### 1.2 vCard — 3 fontes, sem aviso LGPD (resp. **D + C**)

**Decisão**: modal com 3 abas no topo:
- **"Outro agente"** — lista de agentes da equipe
- **"Contato salvo"** — search nos contacts da conta
- **"Telefone livre"** — input nome + telefone manual

Sem aviso de consentimento (Walisson confirmou que confia no atendente, em linha com [práticas de share de vCards via Microsoft 365 e similares](https://support.microsoft.com/en-us/office/share-contacts-as-vcards-ee4f63f4-94f9-4861-8340-4517590d9459)).

**UX pra usuário leigo**:
- Aba ativa fica com sublinhado verde brand
- Cada fonte mostra preview do cartão antes de enviar (avatar + nome + telefone)
- Botão "Enviar contato" embaixo

**Endpoint backend**: WAHA `POST /api/sendContactVcard` tier free, todos engines — payload `{session, chatId, contactId}`. Pra "telefone livre" (não tem contactId), endpoint precisa **gerar vCard 3.0** server-side e enviar via outro fluxo (provavelmente attachment do tipo `contact`). Plano B: usar `POST /api/sendText` com a string vCard formatada.

### 1.3 Respostas rápidas — modal grande com search (resp. **B**)

**Decisão**: modal próprio com:
- Search bar grande no topo (~⌘K command palette pattern, conforme [Chatwoot v2.10 docs](https://www.chatwoot.com/blog/v2-10-0/))
- Lista única de respostas (sem categorias) com preview do conteúdo + shortcode (badge)
- Click → fecha modal e injeta no editor

**Por quê SEM categorias na V1**: schema `canned_responses` em `db/schema.rb:291` só tem `account_id`, `short_code`, `content`, `created_at`, `updated_at`. NÃO existe coluna `category` nem `tags`. Adicionar categorias exigiria migração + UI de gerenciamento — fora do escopo. Search por shortcode/content cobre 95% dos casos.

**Por quê não reusar `/`**: o atalho `/` é menu inline, não tem espaço pra preview longo. Modal grande dá UX premium e reduz fricção pra atendente leigo que não conhece o atalho.

**Reuso**:
- Já existe componente de canned responses em `app/javascript/dashboard/components/widgets/conversation/CannedResponse.vue` (a confirmar) — vamos extender, não duplicar
- Endpoint backend: `/api/v2/accounts/{id}/canned_responses` já existe

### 1.4 Tabs Minhas/Não atribuídas/Todos — fade + chevron desktop, swipe mobile (resp. **B**)

**Decisão**: fade gradient nas bordas + setas `‹›` aparecem só quando há overflow + suporte swipe touch em mobile.

**Por quê**: pesquisa 2026 mostra que [Carbon Design System, GitLab Pajamas e Material UI](https://carbondesignsystem.com/components/tabs/usage/) seguem esse padrão. [Pesquisa específica](https://kevinyank.com/posts/horizontal-scrolling/) confirma:
- Chevrons aparecem só com overflow real (combined width > container width)
- 45% opacity inativos, 90% no hover
- Notion usa esse padrão (gradient + arrows)
- 20% dos usuários AINDA esperam setas mesmo em touch

**A11y obrigatórios**:
- `role="tablist"` no `<ul>`, `role="tab"` em cada `<button>`
- `aria-selected="true"` na ativa
- ArrowLeft/Right por teclado faz scroll
- `scrollIntoView({ inline: 'nearest' })` ao focar tab fora da viewport

### 1.5 Grid actions contato — encurtar i18n com fallback só-ícone (resp. **A** + **B**)

**Decisão**: encurtar labels pra 1 palavra ("Mensagem"/"Editar"/"Mesclar"/"Excluir") + endurecer regras CSS de quebra. Se ainda apertar em alguma viewport (testar 320/375/414/768), fallback automático pra só-ícones com tooltip.

**Padrão**: WhatsApp Web e Telegram usam labels de 1 palavra com ícone em cima. iOS Action Sheet idem. Esse é o padrão "thumb-friendly" 2026.

---

## 2. Pipeline de execução (sprints + paralelismo)

### Sprint 1 — Quick wins (paralelo, ~5h elapsed total)
- **F4** Tabs scroll (Agent D) — 4h
- **F5** Grid actions (Agent E) — 1.5h

Squad D e E em paralelo. Build + restart + Playwright dual-theme + commit ao final.

### Sprint 2 — Respostas rápidas (Agent A, ~6h)
- F1 modal de canned responses (sem categorias — V1 simples)

Sozinho pra evitar conflito em ReplyBox.vue (que F2 e F3 também tocam).

### Sprint 3 — Localização + vCard (paralelo, ~22-28h)
- **F2** Localização (Agent B)
- **F3** vCard (Agent C)

Os dois adicionam item ao menu `+` do ReplyBox + componentes novos. Conflito de merge resolvido sequencialmente: A faz commit antes, B faz rebase mental antes de mexer em ReplyBox.

### Validação final consolidada
- Build + restart + Playwright matrix completa (5 frentes × 2 temas × 3 viewports)
- Commit consolidado com Co-Authored-By: Squad

---

## 3. Squad — missão por agente (cada um é um general-purpose Agent)

Cada bloco abaixo é o **prompt literal** que vou disparar pro agente. NÃO incluir comentários — cada agente recebe APENAS sua seção.

---

### 3.1 Agent A — Respostas rápidas no menu `+` (F1, 6h)

```
Você é um Vue 3/Tailwind dev sênior + UX especialista em chat composer.
Repo: /home/chatwoot/chatwoot · Branch: homologacao.

MISSÃO: Adicionar item "Resposta pronta" no menu "+" do ReplyBox que abre um modal grande com busca + preview (lista única, SEM categorias — schema não suporta na V1), permitindo o atendente leigo encontrar uma resposta sem precisar saber do atalho `/`.

DECISÃO UX (já aprovada pelo Walisson):
- Modal próprio (NÃO reusar o popup inline do `/`).
- Search bar grande no topo, foco automático ao abrir.
- Lista única de respostas (sem sidebar, SEM categorias — schema não suporta).
- Cada item: preview de até 3 linhas + shortcode (badge cinza à direita).
- Click numa resposta → fecha modal + injeta conteúdo no editor (substitui texto selecionado se houver).
- Esc fecha; setas ↑↓ navegam; Enter seleciona.
- Texto pt-BR humano: "Resposta pronta", "Buscar resposta...", "Nenhuma resposta encontrada".

ARQUIVOS:
1. CRIAR `app/javascript/dashboard/components-next/canned-response/CannedResponseModal.vue`
   - Layout: Dialog com width="2xl", header "Resposta pronta", search bar abaixo, lista única (sem sidebar de categorias), footer com hint "↑↓ navegar · Enter usar · Esc fechar".
   - Props: `show: Boolean`, `searchableQuery: String` (busca inicial pré-preenchida pelo `/foo` se vier do atalho).
   - Emits: `close`, `select` (payload: `{ id, content, shortCode }`).
   - Reusa store getters: `useMapGetter('cannedResponse/getCannedResponses')`. Se store não tem getter, usar `cannedResponse/get` ou similar — buscar via `grep -rn "cannedResponse" app/javascript/dashboard/store --include="*.js"`.
   - Respostas filtradas por search (shortCode OU conteúdo).
   - **NÃO IMPLEMENTAR categorias / tags / sidebar** — schema `canned_responses` (db/schema.rb:291) só tem `short_code` + `content`. Categorização exigiria migração e fica fora do escopo V1.
2. EDITAR `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`
   - Adicionar `<DropdownItem>` no menu `+`, label "Resposta pronta", icon `i-lucide-message-square-quote`. **Slot 5** conforme seção 0.2 do plano (após Templates Content, antes de Localização). Se F2/F3 ainda não foram aplicadas, inserir no fim e deixar TODO comment.
   - Click chama `openCannedResponseModal()` que seta `showCannedResponseModal = true`.
   - Renderizar `<CannedResponseModal :show="showCannedResponseModal" @close="..." @select="onCannedSelect" />` no template.
   - `onCannedSelect({ content })` deve injetar `content` no editor (use mecanismo existente do `/` shortcut como referência: provavelmente `replaceText` na ProseMirror instance).
3. i18n:
   - `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`:
     - `CONVERSATION.REPLYBOX.CANNED_RESPONSE_MENU` = "Resposta pronta"
     - `CONVERSATION.REPLYBOX.CANNED_MODAL.TITLE` = "Resposta pronta"
     - `CONVERSATION.REPLYBOX.CANNED_MODAL.SEARCH_PLACEHOLDER` = "Buscar resposta..."
     - `CONVERSATION.REPLYBOX.CANNED_MODAL.NO_RESULTS` = "Nenhuma resposta encontrada"
     - `CONVERSATION.REPLYBOX.CANNED_MODAL.HINT` = "↑↓ navegar · Enter usar · Esc fechar"
   - `en/conversation.json` espelhado em inglês.
4. Acessibilidade:
   - `role="dialog"` (do Dialog wrapper), `aria-labelledby` apontando pro header.
   - Search input com `aria-label`.
   - Lista com `role="listbox"`, items com `role="option"` e `aria-selected`.
   - Foco automático no search input ao abrir.

VALIDAÇÃO:
- `cd /home/chatwoot/chatwoot && pnpm exec eslint <arquivos editados> --fix`
- Build: `NODE_OPTIONS="--max-old-space-size=8192" RAILS_ENV=production bundle exec rake assets:precompile` exit 0
- Restart: `sudo systemctl restart chatwoot.target`
- Playwright (criar `/tmp/test_f1_canned.py`): em viewport 1366x768, login com **conta dedicada** `playwright-test@simplex.local` / `Pl4ywR1ght!Test` (NÃO usar `sup@` — Walisson perde acesso). Abrir conversa via "Não atribuídas" se "Minhas" estiver vazio, clicar `+` no editor, clicar "Resposta pronta", validar que modal abre com search focado, digitar "ola" e validar filtragem, capturar screenshot em light + dark, ESC fecha modal.
- Não duplicar test_violet_no_btn.py — escrever script novo.

NÃO mexer em outros itens do menu. NÃO commitar — só working tree.

Reportar: arquivos alterados, lint OK, build exit, screenshots paths, qualquer pitfall observado durante a implementação.
```

---

### 3.2 Agent B — Inserir localização (F2, 22h)

```
Você é um Vue 3 + Rails dev sênior. Tem experiência com Leaflet/OpenStreetMap.
Repo: /home/chatwoot/chatwoot · Branch: homologacao.

MISSÃO: Adicionar item "Compartilhar localização" no menu "+" do ReplyBox. Abre modal com 2 caminhos: usar minha localização atual (geolocation) OU buscar endereço (Nominatim free). Quando confirma, envia mensagem de localização real via WAHA `POST /api/sendLocation` (tier free, todos engines).

DECISÃO UX (Walisson aprovou A+D híbrido — Nominatim + geolocation):
- Modal full-width (max-w-2xl), header "Compartilhar localização".
- Topo: 2 botões em grid lado-a-lado:
  1. "📍 Usar minha localização atual" (verde brand, primary)
  2. "🔍 Buscar endereço" (neutro, secondary) — abre input de busca
- Mapa Leaflet abaixo (300px altura) com pin no ponto selecionado, arrastável.
- Preview embaixo: "Você vai enviar: <endereço completo geocode reverso>"
- Botões: "Enviar localização" (primary verde) | "Cancelar" (ghost)
- Erros humanos: "Permissão de localização negada", "Não conseguimos encontrar esse endereço".

ARQUIVOS:

### Frontend
1. INSTALAR `leaflet` + `@types/leaflet`:
   - `cd /home/chatwoot/chatwoot && pnpm add leaflet`
   - Confirmar package.json + pnpm-lock.yaml.
2. CRIAR `app/javascript/dashboard/components-next/location/LocationPickerModal.vue`:
   - Composition API, sem scoped CSS.
   - Imports: Leaflet via `import L from 'leaflet'` + CSS `'leaflet/dist/leaflet.css'` (importar em main.ts ou local).
   - State: `mode = 'idle' | 'geo' | 'search'`, `query`, `searchResults[]`, `selectedLocation: { lat, lng, label }`, `loading`.
   - Action "Usar minha localização atual": `navigator.geolocation.getCurrentPosition(...)`, success → centrar mapa + selectedLocation, error → mensagem humana.
   - Action "Buscar endereço": fetch debounced (300ms) `https://nominatim.openstreetmap.org/search?format=jsonv2&q=<encoded>&countrycodes=br&limit=8`. Header obrigatório: `User-Agent: ChatSPX-Simplex-LocationPicker/1.0` (requisito Nominatim). Lista resultados clicáveis abaixo do input.
   - Mapa Leaflet com tiles OSM (`https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png`), atribuição obrigatória "© OpenStreetMap contributors".
   - Pin arrastável: ao soltar, fazer reverse geocoding via `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=...&lon=...` pra atualizar o label.
   - Emit `select({ latitude, longitude, address })` no submit; `close` no cancel/ESC.
3. EDITAR `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`:
   - Adicionar `<DropdownItem>` no menu `+`, label "Compartilhar localização", icon `i-lucide-map-pin`. **Slot 6** conforme seção 0.2 do plano (após "Resposta pronta" da F1, antes de "Compartilhar contato" da F3). Se F1 ainda não foi aplicada, inserir no fim e deixar TODO comment.
   - Lógica: abre modal, no `select` chama action do store `sendMessage` com payload de localização.
4. i18n pt_BR + en:
   - `LOCATION.MENU` = "Compartilhar localização" / "Share location"
   - `LOCATION.MODAL_TITLE` = "Compartilhar localização" / "Share location"
   - `LOCATION.USE_MY_CURRENT` = "Usar minha localização atual" / "Use my current location"
   - `LOCATION.SEARCH_ADDRESS` = "Buscar endereço" / "Search an address"
   - `LOCATION.SEARCH_PLACEHOLDER` = "Digite um endereço, CEP ou ponto" / "Type an address, ZIP or place"
   - `LOCATION.PREVIEW` = "Você vai enviar: {address}" / "You will send: {address}"
   - `LOCATION.SEND` = "Enviar localização" / "Send location"
   - `LOCATION.CANCEL` = "Cancelar" / "Cancel"
   - `LOCATION.PERMISSION_DENIED` = "Permissão de localização negada. Verifique nas configurações do navegador." / "Location permission denied. Check your browser settings."
   - `LOCATION.NOT_FOUND` = "Não encontramos esse endereço. Tente outro." / "We didn't find this address. Try another."
   - `LOCATION.LOADING` = "Buscando..." / "Searching..."
   - Coloque sob namespace `CONVERSATION.LOCATION` ou `LOCATION` direto (decida pela coerência com vizinhos no JSON).

### Backend
5. EDITAR `app/services/waha/api_service.rb`:
   - Adicionar método `send_location(session:, chat_id:, latitude:, longitude:, accuracy: nil)`:
     ```ruby
     def send_location(session:, chat_id:, latitude:, longitude:, accuracy: nil)
       payload = { session: session, chatId: chat_id, latitude: latitude, longitude: longitude }
       payload[:accuracy] = accuracy if accuracy
       post('api/sendLocation', payload)
     end
     ```
6. INTEGRAR no fluxo de envio outbound:
   - Investigar como Chatwoot dispara mensagens com `attachment.file_type='location'` (já implementado pra inbound conforme análise prévia).
   - Caminho provável: `app/builders/messages/message_builder.rb` ou `app/services/whatsapp/send_on_whatsapp_service.rb` precisa identificar mensagens com `additional_attributes={'location': {...}}` e rotear pra `Waha::ApiService#send_location` em vez do envio normal.
   - Spike de 2h: tentar primeiro com payload do tipo `attachment` (file_type=location, coordinates_lat, coordinates_long). Se WAHA Chatwoot App não traduzir corretamente, fallback é wrapper REST direto.
7. EDITAR Message model (se necessário):
   - Confirmar que `additional_attributes` jsonb suporta `{location: {lat, lng, address}}`. Já existe coluna no schema.

### Renderização inbound
8. Verificar se `app/javascript/dashboard/components-next/message/bubbles/Location.vue` JÁ existe (foi mencionado na análise). Se sim, garantir que renderiza outbound também (provavelmente já faz).

VALIDAÇÃO:
- ESLint + RuboCop (`bundle exec rubocop -a`) limpos
- Spec backend Ruby: criar `spec/services/waha/api_service_spec.rb` com `describe '#send_location'` mockando POST.
- Build assets exit 0
- Restart serviço
- Playwright dual-theme:
  - Mock geolocation no Playwright: `page.context.grant_permissions(['geolocation'], origin='https://hmlchat...')` + `page.context.set_geolocation({'latitude': -15.6, 'longitude': -56.1})` (Cuiabá).
  - Abrir modal, clicar "Usar localização atual", validar pin no mapa em coords corretas, clicar "Enviar localização".
  - Validar bubble outbound aparece no chat com mapa preview.
  - Repetir busca por endereço: digitar "Avenida Paulista", selecionar primeiro resultado, validar pin, enviar.
- NÃO commitar.

PITFALLS conhecidos:
- Nominatim tem rate limit de 1 req/segundo. Implementar debounce + warning UI.
- CORS: browser pode bloquear chamada direta pra nominatim.openstreetmap.org. Se sim, criar proxy Rails simples em `app/controllers/api/v2/accounts/locations/search_controller.rb` que faz a requisição server-side. Decidir baseado em teste — começar com client-direct, se falhar, proxy.
- Leaflet bundling:
  1. Ícone do pin default não carrega via Vite por padrão. Solução: importar manualmente `import iconUrl from 'leaflet/dist/images/marker-icon.png'` e setar `L.Icon.Default.prototype._getIconUrl`.
  2. **Bundle size** — Leaflet (~42KB gzip) NÃO deve cair no chunk principal e penalizar todo dashboard. Adicionar em `vite.config.mts` (ou `vite.config.js`) dentro de `build.rollupOptions.output.manualChunks`:
     ```js
     manualChunks: {
       leaflet: ['leaflet'],
     }
     ```
     Validar com `pnpm exec vite build --mode production` que existe `leaflet-*.js` separado em `public/vite/assets/`. Se já existe `manualChunks` configurado, mesclar a entrada nova sem remover as existentes.
  3. Confirmar lazy import: `LocationPickerModal.vue` deve ser importado via `defineAsyncComponent(() => import('...'))` em `ReplyBox.vue` pra não puxar Leaflet até o usuário clicar no menu.
- WAHA outbound de location via attachment-builder pode ou não funcionar. Spike obrigatório de 1h antes de prosseguir (seção 0.1).

Reportar: arquivos alterados, decisão sobre CORS proxy (sim/não), spike WAHA outbound (sucesso/fallback REST direto), screenshots, build/lint/spec status.
```

---

### 3.3 Agent C — Compartilhar contato vCard (F3, 28h)

```
Você é um Vue 3 + Rails dev sênior, atento a privacy/LGPD.
Repo: /home/chatwoot/chatwoot · Branch: homologacao.

MISSÃO: Adicionar item "Compartilhar contato" no menu "+" do ReplyBox. Modal com 3 abas (Outro agente / Contato salvo / Telefone livre). Quando confirma, envia mensagem de contato real via WAHA `POST /api/sendContactVcard`.

DECISÃO UX (Walisson aprovou D — 3 fontes — e C — sem aviso LGPD):
- Modal max-w-xl com 3 abas no topo (estilo Tabs já existentes no projeto):
  1. "Outro agente" — lista todos agentes da equipe (excluindo o atendente atual)
  2. "Contato salvo" — search nos contacts da conta
  3. "Telefone livre" — form com input nome + input telefone
- Aba ativa com sublinhado verde brand (mesmo estilo das tabs Minhas/Não atribuídas).
- Cada aba mostra preview do cartão antes de enviar (avatar + nome + telefone).
- Botões: "Enviar contato" (primary verde) | "Cancelar" (ghost).
- SEM modal de confirmação LGPD — Walisson decidiu confiar no atendente.

ARQUIVOS:

### Frontend
1. CRIAR `app/javascript/dashboard/components-next/share-contact/ShareContactModal.vue`:
   - 3 abas com state `activeTab = 'agent' | 'contact' | 'manual'`.
   - Aba "Outro agente": fetch de `useMapGetter('agents/getAgents')` (a confirmar). Lista com avatar+nome+email, click marca como selecionado.
   - Aba "Contato salvo": search bar + lista paginada chamando endpoint `/api/v2/accounts/{id}/contacts/search?q=`. Lista com avatar+nome+telefone, click seleciona.
   - Aba "Telefone livre": 2 inputs (nome obrigatório, telefone obrigatório com máscara BR `+55 (XX) XXXXX-XXXX`). Validação: telefone ≥10 dígitos. Preview ao digitar.
   - Preview do cartão (sempre visível embaixo das 3 abas): avatar, nome, telefone, badge "Outro agente" / "Contato salvo" / "Manual".
   - Submit emit `select({ name, phone, contactId?, source })`.
2. EDITAR `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`:
   - Adicionar `<DropdownItem>` "Compartilhar contato", icon `i-lucide-user-round-plus`. **Slot 7** (último) conforme seção 0.2 do plano. Se F1/F2 ainda não foram aplicadas, inserir no fim mesmo (já é a última posição final).
3. i18n pt_BR + en:
   - `SHARE_CONTACT.MENU` = "Compartilhar contato"
   - `SHARE_CONTACT.MODAL_TITLE` = "Compartilhar contato"
   - `SHARE_CONTACT.TAB_AGENT` = "Outro agente"
   - `SHARE_CONTACT.TAB_CONTACT` = "Contato salvo"
   - `SHARE_CONTACT.TAB_MANUAL` = "Telefone livre"
   - `SHARE_CONTACT.SEARCH_AGENT` = "Buscar agente..."
   - `SHARE_CONTACT.SEARCH_CONTACT` = "Buscar contato..."
   - `SHARE_CONTACT.MANUAL_NAME` = "Nome"
   - `SHARE_CONTACT.MANUAL_PHONE` = "Telefone (com DDD)"
   - `SHARE_CONTACT.PREVIEW_HEADING` = "Pré-visualização"
   - `SHARE_CONTACT.SEND` = "Enviar contato"
   - `SHARE_CONTACT.CANCEL` = "Cancelar"
   - `SHARE_CONTACT.PHONE_INVALID` = "Telefone inválido. Inclua DDD (10 ou 11 dígitos)."
   - `SHARE_CONTACT.NO_AGENTS` = "Sem outros agentes na equipe."
   - `SHARE_CONTACT.NO_CONTACTS_FOUND` = "Nenhum contato encontrado."
   - en/ traduzido.

### Backend
4. EDITAR `app/services/waha/api_service.rb`:
   - Adicionar método `send_contact_vcard(session:, chat_id:, contact_id:)`:
     ```ruby
     def send_contact_vcard(session:, chat_id:, contact_id:)
       payload = { session: session, chatId: chat_id, contactId: contact_id }
       post('api/sendContactVcard', payload)
     end
     ```
   - Adicionar fallback `send_text_with_vcard(session:, chat_id:, vcard_string:)` pra fonte "Telefone livre" — gera texto vCard 3.0 e envia via `POST /api/sendText`. Formato vCard padrão:
     ```
     BEGIN:VCARD
     VERSION:3.0
     FN:Maria Silva
     TEL;TYPE=CELL:+5565999991234
     END:VCARD
     ```
5. ENDPOINT novo `POST /api/v2/accounts/{id}/conversations/{conv_id}/share_contact`:
   - Aceita body `{ source: 'agent'|'contact'|'manual', name, phone, contact_id? }`.
   - Decide qual chamada WAHA fazer.
   - Cria Message no banco com `additional_attributes: { contact: { name, phone, source } }`.
   - Spec: `spec/controllers/api/v2/accounts/conversations/share_contact_controller_spec.rb`.

### Renderização inbound
6. Verificar componente `app/javascript/dashboard/components-next/message/bubbles/Contact.vue` (existe segundo análise prévia). Garantir que renderiza outbound também.

VALIDAÇÃO:
- ESLint + RuboCop limpos
- Specs backend passando
- Build + restart
- Playwright dual-theme: testar 3 abas, fluxo completo de cada uma, validar mensagem outbound aparece no chat.
- NÃO commitar.

PITFALLS:
- "Telefone livre" exige geração de vCard server-side se WAHA `sendContactVcard` exigir contactId persistido. Se exigir, criar contato silencioso primeiro (sem afetar lista) ou usar fallback `sendText`.
- Validação de telefone BR: usar lib `phonelib` ou regex simples `\+?55?\d{10,11}`.
- Privacidade: não enviar avatar de contato como attachment — só nome+telefone bastam pro vCard.

Reportar: arquivos alterados, decisão sobre fallback sendText vs sendContactVcard pra "telefone livre", screenshots dual-theme das 3 abas + envio bem-sucedido, build/lint/spec status.
```

---

### 3.4 Agent D — Fix tabs scroll (F4, 4h)

```
Você é um UI engineer especializado em Tailwind/CSS responsivo + a11y.
Repo: /home/chatwoot/chatwoot · Branch: homologacao.

MISSÃO: Garantir que as tabs Minhas/Não atribuídas/Todos da lista de conversas SEMPRE tenham um indicador visual de overflow (fade + chevrons em desktop, fade + swipe em mobile) e nunca cortem invisivelmente o último item.

DECISÃO UX (Walisson aprovou B — fade+swipe mobile, fade+setas desktop):
- Mobile (<768px): só fade gradient nas bordas + scroll touch nativo (swipe).
- Desktop (≥768px): fade + setas `‹›` que aparecem só quando há overflow real.
- Setas: 45% opacity inativas, 90% no hover. Click rola ~150px.
- A11y: ArrowLeft/Right por teclado, scrollIntoView no foco, role="tablist" + role="tab" + aria-selected.

REFERÊNCIAS 2026 (best practices pesquisadas):
- Carbon Design System tabs (chevron pattern): https://carbondesignsystem.com/components/tabs/usage/
- Notion gradient fade pattern (citado em https://kevinyank.com/posts/horizontal-scrolling/)
- Material UI 7 ScrollableTabs: https://mui.com/material-ui/react-tabs/

ARQUIVOS A MODIFICAR (já mapeados no PLAN-FIX-CONVERSATION-TABS.md):
1. `app/javascript/dashboard/components/ui/Tabs/Tabs.vue` (componente raiz)
2. `app/javascript/dashboard/components/ui/Tabs/TabsItem.vue` (item)
3. `app/javascript/dashboard/assets/scss/_wa-skin.scss` (estilos `.wa-tab-item`)
4. Consumer real: `app/javascript/dashboard/components/widgets/ChatTypeTabs.vue` (path confirmado via `find`; NÃO existe em `components-next/`)

PASSO A PASSO:

1. Ler PLAN-FIX-CONVERSATION-TABS.md em prompts/copilot-redesign/ pra entender análise prévia.
2. Em Tabs.vue:
   - Adicionar refs `containerRef`, `listRef`, `hasOverflowLeft`, `hasOverflowRight`.
   - `onMounted` + `useResizeObserver(listRef, computeOverflow)` + scroll listener.
   - `computeOverflow()`: recalcula `hasOverflowLeft = scrollLeft > 4`, `hasOverflowRight = scrollWidth - clientWidth - scrollLeft > 4`. Threshold 4px (não 20 que mascara).
   - Renderizar `<button class="tabs-chevron tabs-chevron-left md:flex hidden" v-if="hasOverflowLeft">...</button>` e direita similar.
   - Renderizar overlays de fade: `<div class="absolute left-0 top-0 bottom-0 w-8 bg-gradient-to-r from-n-solid-1 to-transparent pointer-events-none" v-if="hasOverflowLeft" />` e direita.
   - Tab focus: ao receber foco, scroll pra mostrar (`el.scrollIntoView({ inline: 'nearest', block: 'nearest', behavior: 'smooth' })`).
   - Keyboard: ArrowLeft/Right rola 150px; Home rola pro início; End rola pro fim.
3. Em TabsItem.vue:
   - Adicionar `role="tab"`, `:aria-selected="isActive"`, `tabindex="0"`.
   - Adicionar `<ul role="tablist">` no Tabs.vue parent.
4. SCSS `.wa-tab-item` em _wa-skin.scss:
   - Hover/focus styles unificados (focus-visible:ring).
   - Active state já existe; preservar.
5. Confirmar `no-scrollbar` continua aplicada (esconde scrollbar nativa em favor da nossa solução visual).

CASOS DE EDGE A TESTAR:
- 3 tabs com badges 1 dígito (Minhas 2 / Não atribuídas 35 / Todos 55) em viewport 1280, 1366, 1440, 1920.
- 3 tabs com badges 3+ dígitos (Minhas 999 / Não atribuídas 1.2k / Todos 5.5k).
- Mobile 375 — sem setas, só fade + swipe.
- Touch device sem mouse — keyboard nav funciona.
- Dark mode: gradient correto (de `n-solid-1` no light, `n-slate-2` no dark).
- prefers-reduced-motion: scroll behavior 'auto' em vez de 'smooth'.

VALIDAÇÃO PLAYWRIGHT (matriz):
| Viewport | Tema | Cenário |
|----------|:----:|---------|
| 375x667  | light | swipe touch funciona, fade visível |
| 375x667  | dark  | idem |
| 1280x720 | light | fade+chevron visíveis, click rola |
| 1280x720 | dark  | idem |
| 1366x768 | light | fade+chevron visíveis (caso Walisson) |
| 1366x768 | dark  | idem |
| 1920x1080| light | sem overflow, sem chevron |
| 1920x1080| dark  | idem |

Capturar screenshots em /tmp/ e gerar relatório.

NÃO commitar.

Reportar: arquivos alterados, screenshots, lint OK, casos edge cobertos, observações sobre prefers-reduced-motion.
```

---

### 3.5 Agent E — Fix grid actions contato (F5, 1.5h)

```
Você é um UI engineer Tailwind. Repo: /home/chatwoot/chatwoot · Branch: homologacao.

MISSÃO: Corrigir o grid de ações do contato (Nova Mensagem / Editar / Mesclar / Excluir) que tem labels longos sobrepondo botões adjacentes em qualquer viewport.

DECISÃO UX (Walisson aprovou A com fallback B):
- **Padrão A**: encurtar i18n pra 1 palavra ("Mensagem"/"Editar"/"Mesclar"/"Excluir") + endurecer regras CSS (`white-space: nowrap`, `text-overflow: ellipsis`, `overflow: hidden`, `text-align: center`).
- **Fallback B**: se em viewport ≤320px ou ≤375 ainda apertar, condicionalmente esconder labels (`@media (max-width: 360px) { .wa-action-label { @apply sr-only; } }`) e mostrar tooltip com label completo.

REFERÊNCIAS:
- WhatsApp Web action sheet pattern (1 palavra + ícone)
- iOS Action Sheet (https://developer.apple.com/design/human-interface-guidelines/action-sheets)

ARQUIVOS (já mapeados em PLAN-FIX-CONTACT-ACTIONS-GRID.md):
1. `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` (path confirmado via `find`; NÃO existe em `components-next/contacts/`)
2. `app/javascript/dashboard/assets/scss/_wa-skin.scss:1723-1729` (`.wa-action-label`)
3. `app/javascript/dashboard/i18n/locale/pt_BR/contact.json` ou contacts.json (textos)
4. `app/javascript/dashboard/i18n/locale/en/contact.json`

PASSO A PASSO:
1. Ler PLAN-FIX-CONTACT-ACTIONS-GRID.md.
2. Localizar keys i18n atuais: `grep -rn "Nova Mensagem\|Editar Contato\|Mesclar contatos\|Excluir Contato" app/javascript/dashboard/i18n`.
3. ENCURTAR labels:
   - "Nova Mensagem" → "Mensagem"
   - "Editar Contato" → "Editar"
   - "Mesclar contatos" → "Mesclar"
   - "Excluir Contato" → "Excluir"
   - Idem em en (curtos: "Message"/"Edit"/"Merge"/"Delete").
4. Endurecer SCSS de `.wa-action-label`:
   ```scss
   .wa-action-label {
     // existente: font-size, line-height, text-align, etc
     overflow: hidden;
     text-overflow: ellipsis;
     white-space: nowrap;
     max-width: 100%;
     text-align: center;
   }
   @media (max-width: 360px) {
     .wa-action-btn .wa-action-label {
       @apply sr-only;
     }
   }
   ```
5. Garantir tooltip com label COMPLETO continua funcionando (`v-tooltip="$t('CONTACT.ACTIONS.MESSAGE_TOOLTIP_FULL')"` se quiser; ou reusar a key encurtada).

VALIDAÇÃO PLAYWRIGHT (matriz):
| Viewport | Tema | Cenário esperado |
|----------|:----:|------------------|
| 320x568  | light | labels escondidos (sr-only), só ícones, tooltip funciona |
| 320x568  | dark  | idem |
| 375x667  | light | labels visíveis truncados se preciso, sem sobreposição |
| 375x667  | dark  | idem |
| 768x1024 | light | labels completos, sem overflow |
| 1366x768 | light | labels completos |

Capturar screenshots cada caso.

NÃO commitar.

Reportar: arquivos alterados, screenshots, lint OK, decisão sobre 360px breakpoint (mantido ou ajustado).
```

---

## 4. Validação Playwright (matriz consolidada)

Após cada sprint, **OBRIGATÓRIO** validar tudo via Playwright. Squad Orquestrador (eu mesmo) consolida ao final:

```
Frente | Tema | Viewport (LV) | Test path
-------|------|---------------|----------
F1 Resp.rápidas | light/dark | 1366x768  | /tmp/test_f1_canned.py
F2 Localização  | light/dark | 1366x768  | /tmp/test_f2_location.py
F3 vCard        | light/dark | 1366x768  | /tmp/test_f3_vcard.py
F4 Tabs scroll  | light/dark | 375/1280/1366/1440/1920 | /tmp/test_f4_tabs.py
F5 Grid actions | light/dark | 320/375/768/1366 | /tmp/test_f5_grid.py
```

Login pra todos os tests: **conta dedicada** `playwright-test@simplex.local` / `Pl4ywR1ght!Test`. NUNCA logar com `sup@simplexsolucoes.com.br` em scripts automatizados (regra de ouro: Walisson perde acesso se a senha bater errado e dispara lockout). Account de testes: `Account.find_by!(name: 'Simplex Tecnologia')` (lookup por nome — `id` pode variar entre ambientes); essa account já tem conversas WhatsApp reais e Captain habilitado.

---

## 5. Definition of Done — checklist por frente

Para cada frente passar pra "done":

- [ ] Código Vue + Rails escrito e atende decisão UX
- [ ] i18n pt_BR + en adicionado, sem strings hardcoded em templates
- [ ] ESLint sem erros novos
- [ ] RuboCop sem offenses novas (se mexeu Ruby)
- [ ] Specs Vue (vitest) — só onde fizer sentido (lógica complexa); mudanças puramente visuais não exigem
- [ ] Specs Ruby (rspec) — para todo método novo em service/controller
- [ ] Build assets:precompile exit 0
- [ ] Restart aplicado, serviço active
- [ ] Playwright dual-theme em viewport notebook (1366×768) passou
- [ ] Screenshots em /tmp/copilot-screens-v3/
- [ ] EXECUTION-LOG.md atualizado com timestamp + arquivos + observações
- [ ] Working tree only — sem commit ainda

Commit final consolidado é prerrogativa do Walisson (eu não comito sem autorização).

---

## 6. Riscos + fallbacks

| Risco | Probabilidade | Impacto | Mitigação |
|-------|:-------------:|:-------:|-----------|
| WAHA outbound location/vcard não funcionar via attachment-builder | Média | Alta | Wrapper REST direto em `Waha::ApiService` (custo +4-6h por feature) |
| Nominatim CORS bloqueia chamada client | Baixa | Média | Proxy controller Rails `/api/v2/accounts/{id}/locations/search` |
| Leaflet não bundleia bem com Vite (ícones quebrados) | Média | Baixa | Workaround conhecido: importar marker-icon manualmente |
| Tabs com prefers-reduced-motion ignorado | Baixa | Baixa | Adicionar `@media (prefers-reduced-motion: reduce) { .smooth-scroll { scroll-behavior: auto !important; } }` |
| Account de homologação esquecer de habilitar Captain | Baixa | Baixa | Documentar no test setup |
| Senha sup@ resetada por engano de novo | Média | Alta | Memória `feedback_no_resetar_senha_real.md` carregada — usar conta como está |

---

## 7. Referências externas (research 2026)

- **Canned responses UX**: [Chatwoot v2.10 keyboard shortcuts + draft replies](https://www.chatwoot.com/blog/v2-10-0/), [Chatwoot Command Bar](https://www.chatwoot.com/features/command-bar/), [Modal UX best practices — Eleken 2025](https://www.eleken.co/blog-posts/modal-ux), [Chat UX best practices — GetStream](https://getstream.io/blog/chat-ux/)
- **Localização**: [Leaflet (42KB, lib leader)](https://leafletjs.com/), [Nominatim OSM Wiki](https://wiki.openstreetmap.org/wiki/Nominatim), [Building OSM Address Search — GeoPostcodes](https://www.geopostcodes.com/blog/open-street-maps-address-search/), [WAHA send-messages docs](https://waha.devlike.pro/docs/how-to/send-messages/)
- **vCard**: [Microsoft Office vCard guidance](https://support.microsoft.com/en-us/office/share-contacts-as-vcards-ee4f63f4-94f9-4861-8340-4517590d9459), [WAHA sendContactVcard issue #528](https://github.com/devlikeapro/waha/issues/528), [Best vCard tools 2025 — Spreadly](https://spreadly.app/en/blog/vcard-online-tools)
- **Tabs scroll a11y**: [Carbon Design System tabs](https://carbondesignsystem.com/components/tabs/usage/), [Material UI scrollable tabs](https://mui.com/material-ui/react-tabs/), [GitLab Pajamas tabs](https://design.gitlab.com/components/tabs/), [Horizontal scrolling — Kevin Yank](https://kevinyank.com/posts/horizontal-scrolling/), [PatternFly mobile tabs issue #1034](https://github.com/patternfly/patternfly-design/issues/1034)
- **WAHA endpoints**: confirmado tier free + todos engines pra `sendLocation` e `sendContactVcard` ([fonte oficial](https://waha.devlike.pro/docs/how-to/send-messages/))

---

**FIM DO PLANO. Pronto pra disparar via prompt-de-disparo.md.**
