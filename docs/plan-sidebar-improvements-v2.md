# Plano FINAL — Melhorias UX Sidebar v2 (5 itens)

**Data:** 2026-04-27
**Branch:** `homologacao` (working tree, sem commit ainda)
**Autor:** Orion (aiox-master) para Walisson

---

## Decisões fechadas com Walisson

| # | Decisão |
|---|---------|
| Item 4 | **Versão B** — redesenhar status pill (botão primário inline + kebab) |
| Item 5a | Galeria **GLOBAL** (cross-conversation, igual Media Hub WhatsApp) |
| Item 5b | Entry point **no sidebar principal** (rota dedicada `/gallery`) |
| Item 5c | **Mídia + Documentos + Links** todos na primeira entrega |
| Lordicon `ltjljakp` | **System family**, mesma URL para idle e active (`https://cdn.lordicon.com/ltjljakp.json`). Active state usa bold stroke (mesma lógica do fallback Wired já implementada no `LordIconIcon.vue`). Tratamento idêntico aos demais ícones do sidebar. |
| Download múltiplo | ≤5 itens: sequencial (`<a download>`), >5: zip server-side via job assíncrono |
| Commit | **NÃO commitar nada.** Tudo em working tree até Walisson aprovar visualmente. |

---

## Sumário Executivo (re-escopado)

| # | Item | Esforço | Risco |
|---|------|---------|-------|
| 1 | Auto-marcar notificação como lida ao abrir conversa pelo dashboard | S (~15min) | Baixo |
| 2 | Refinar botão de busca (sidebar collapsed) | S (~10min) | Baixo |
| 3 | Scrollbar condicional no sidebar | S (~10min) | Baixo |
| 4 | Status pill — Versão B (redesenho) | M (~45min) | Médio |
| 5 | **Galeria Global** (Mídia+Docs+Links) com sidebar entry | **XL (~10-14h)** | Alto |

**Total estimado:** ~12-16h end-to-end (galeria global é o grosso).

---

## Item 1 — Auto-marcar notificação como lida ao abrir conversa pelo dashboard

### Problema
Hoje `notifications/read` só dispara em `InboxList.vue:94` (clique explícito no card). Abrir a conversa pelo dashboard normal NÃO some a notificação da aba nem decrementa o sino.

### Solução
Estender `markMessagesRead` em `messageReadActions.js` para também despachar `notifications/read` matching por `primary_actor_id == conversationId` e `primary_actor_type === 'Conversation'`.

```js
// app/javascript/dashboard/store/modules/conversations/actions/messageReadActions.js
markMessagesRead: async ({ commit, dispatch, rootGetters }, data) => {
  try {
    const response = await ConversationApi.markMessageRead(data);
    commit(SET_CONVERSATION_LAST_SEEN, {
      id: data.id,
      data: { agent_last_seen_at: response.data.agent_last_seen_at,
              unread_count: response.data.unread_count },
    });

    // NEW: auto-clear matching notification
    const notifications = rootGetters['notifications/getNotifications'] || [];
    const match = notifications.find(
      n => !n.read_at &&
           n.primary_actor_type === 'Conversation' &&
           Number(n.primary_actor_id) === Number(data.id)
    );
    if (match) {
      dispatch('notifications/read', {
        id: match.id,
        primaryActorType: match.primary_actor_type,
        primaryActorId: match.primary_actor_id,
        unreadCount: rootGetters['notifications/getUnreadCount'],
      }, { root: true });
    }
  } catch (error) { /* silent */ }
}
```

**Edge case:** Se o usuário não abriu a aba Notificações ainda, `notifications/getNotifications` está vazio. Nesse caso, despachar diretamente:
```js
NotificationsAPI.read('Conversation', Number(data.id)); // server-side marca
dispatch('notifications/unReadCount'); // refetch contador do sino
```

### Arquivos
- `app/javascript/dashboard/store/modules/conversations/actions/messageReadActions.js`

### Validação
1. Abrir conversa pelo dashboard → sino decrementa.
2. Abrir aba Notificações → item já aparece como lido.
3. Abrir conversa pela aba Notificações → comportamento atual mantido (sem double-fire).

---

## Item 2 — Refinar botão de busca (sidebar collapsed)

### Problema
HTML atual em `Sidebar.vue:932-947`:
- `outline outline-1 outline-n-weak` cria contorno duplo destoante dos itens do nav.
- `bg-n-button-color` destaca demais para um item secundário.
- Tamanho 32×32 não casa com tamanho dos demais ícones (44×44 com ícone 26px).

### Solução
Espelhar visual dos itens do nav: sem outline, hover sutil, mesma família de ícones, container 44×44 (`size-11`) com `rounded-lg`.

```vue
<RouterLink
  v-else
  data-hover-host
  :to="{ name: 'search' }"
  class="flex items-center justify-center size-11 rounded-lg
         text-n-slate-11 hover:bg-n-alpha-1 dark:hover:bg-n-slate-9/40
         hover:text-n-slate-12 transition-colors"
  :title="t('SIDEBAR.SEARCH_PLACEHOLDER')"
>
  <LordIconIcon
    :src="LORDICON.search.idle"
    :src-active="LORDICON.search.active"
    :family="LORDICON.search.family"
    fallback-lucide="i-lucide-search"
    :size="22"
    class="text-current"
  />
</RouterLink>
```

### Arquivos
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:932-947`

---

## Item 3 — Scrollbar condicional no sidebar

### Problema
`Sidebar.vue:951` usa `overflow-y-scroll` (sempre reserva o trilho) + `no-scrollbar` (esconde via webkit). Em algumas combinações isso vaza um trilho cinza vazio. Usuário relatou visualmente.

### Solução
Trocar `overflow-y-scroll` → `overflow-y-auto`. Resultado: só renderiza scroll quando há overflow real.

```vue
<nav
  class="grid overflow-y-auto flex-grow gap-2 pb-5 no-scrollbar min-w-0"
  :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
>
```

Aplicar mesma troca em `SidebarSubGroup.vue:114`.

### Arquivos
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:951`
- `app/javascript/dashboard/components-next/sidebar/SidebarSubGroup.vue:114`

---

## Item 4 — Status Pill (Versão B — redesenho)

### Problema
Pill atual: `[ícone] Aberta [▼]` + popover com 3 opções. Walisson:
> "isso aqui está bem vago. As vezes a pessoa não entende. E o popover que tem opção de 'em andamento' não faz sentido."

### Diagnóstico
1. **"Aberta"** é semanticamente confuso (qualquer não-resolvida é "aberta").
2. Popover com 3 opções é cognitive overhead — 90% das mudanças são `open ↔ resolved`.
3. "Em andamento" (mapeado como `pending`) confunde porque o label sugere "esperando o cliente".

### Solução B — Redesenho

**Layout novo no header da conversa:**
```
[Status Badge]  [Botão Primário]  [⋯ Kebab]
```

#### a) Status Badge (read-only, informativo)

Pill compacto mostrando o status semântico atual. **Não é clicável para mudar status** — só informa. Cor por estado (mantém WhatsApp-skin):

| Status backend | Label novo | Cor |
|----------------|------------|-----|
| `open` + assignee | "Em atendimento" | verde n-brand |
| `open` sem assignee | "Não atribuída" | âmbar |
| `pending` | "Aguardando triagem" | azul |
| `snoozed` | "Adiada até {hora}" | cinza |
| `resolved` | "Resolvida" | cinza |

#### b) Botão Primário (ação contextual)

Contexto-aware. Aparece em destaque (verde solid):

| Status atual | Botão primário | Ação |
|--------------|----------------|------|
| open / pending | "Resolver ✓" | `toggleStatus('resolved')` |
| snoozed | "Reabrir" | `toggleStatus('open', null)` |
| resolved | "Reabrir" | `toggleStatus('open', null)` |

#### c) Kebab `⋯` (overflow)

Menu com ações secundárias. Itens dependem do status atual:

| Status atual | Itens no kebab |
|--------------|----------------|
| open + assignee | Adiar, Marcar como Aguardando, Reatribuir |
| open sem assignee | Atender (assume), Adiar |
| pending | Atender, Adiar, Resolver |
| snoozed | Resolver |
| resolved | Adiar (re-snooze), (já reabre pelo botão primário) |

#### Componentização

Extrair o pill+ações para um componente novo:
```
app/javascript/dashboard/components-next/Conversation/ConversationStatusActions.vue
```

Recebe `chat`, emite `change-status`, `assign-self`, `open-snooze-dialog`. Mantém `ConversationHeader.vue` enxuto.

#### i18n

```json
// app/javascript/dashboard/i18n/locale/pt_BR/conversation.json
"HEADER": {
  "STATUS_BADGE": {
    "OPEN_ASSIGNED": "Em atendimento",
    "OPEN_UNASSIGNED": "Não atribuída",
    "PENDING": "Aguardando triagem",
    "SNOOZED_UNTIL": "Adiada até %{time}",
    "SNOOZED_NEXT_REPLY": "Adiada",
    "RESOLVED": "Resolvida"
  },
  "STATUS_ACTIONS": {
    "RESOLVE": "Resolver",
    "REOPEN": "Reabrir",
    "TAKE": "Atender",
    "SNOOZE": "Adiar",
    "MARK_PENDING": "Marcar como Aguardando",
    "REASSIGN": "Reatribuir"
  }
}
```

### Arquivos
- **Novo:** `app/javascript/dashboard/components-next/Conversation/ConversationStatusActions.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue:228-289` — substituir bloco
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` — strings novas
- `app/javascript/dashboard/assets/scss/_wa-skin.scss:1465-1493` — repensar paleta dos badges

### Validação
- Cada estado renderiza badge + botão + kebab corretos.
- Toggle status pelo botão primário funciona em todos estados.
- Kebab abre/fecha com click-outside.
- Dark mode com cores adequadas.
- Mobile: badge pode esconder, botão primário fica visível, kebab também.

---

## Item 5 — Galeria GLOBAL (Mídia + Documentos + Links)

### Visão
Página dedicada acessível pelo sidebar, mostrando **TODA** a mídia/docs/links que o agente tem acesso, agregando todas as conversas. Inspiração: WhatsApp Media Hub (rolled out nov/2025).

### Arquitetura

#### Backend — endpoint NOVO

`GET /api/v1/accounts/:account_id/attachments`

Query params:
- `type=image,video,file,audio,link` — filtro de tipo (default: `image,video`)
- `q=<termo>` — busca em caption/sender/filename
- `inbox_id=<id>` — filtro por inbox
- `contact_id=<id>` — filtro por contato
- `sort=date_desc|date_asc|size_desc|size_asc` (default: `date_desc`)
- `before=<iso>` / `after=<iso>` — range de datas
- `page=<n>` (paginação 30 por página)

Response payload:
```json
{
  "data": {
    "payload": [
      {
        "id": 123,
        "file_type": "image",
        "data_url": "https://...thumbnail-200.jpg",
        "preview_url": "https://...preview-800.jpg",
        "original_url": "https://...original.jpg",
        "file_name": "foto.jpg",
        "file_size": 245678,
        "created_at": "2026-04-27T10:30:00Z",
        "message_id": 4567,
        "conversation": { "id": 89, "display_id": 12, "inbox_id": 3 },
        "sender": { "id": 7, "name": "João", "type": "Contact", "thumbnail": "..." },
        "caption": "olha que legal"
      }
    ],
    "meta": {
      "current_page": 1,
      "total_pages": 89,
      "total_count": 2670
    }
  }
}
```

**Implementação Rails:**
```ruby
# app/controllers/api/v1/accounts/attachments_controller.rb (NOVO)
class Api::V1::Accounts::AttachmentsController < Api::V1::Accounts::BaseController
  ALLOWED_TYPES = %w[image video file audio ig_reel].freeze
  RESULTS_PER_PAGE = 30

  def index
    types = parse_types
    @attachments = scope_for_user
                     .where(file_type: types)
                     .includes(:file_attachment, message: [:sender, :conversation])
                     .order(sort_clause)
                     .page(params[:page]).per(RESULTS_PER_PAGE)
    @attachments_count = @attachments.total_count
  end

  def links
    @messages = links_scope
                  .order(created_at: :desc)
                  .page(params[:page]).per(RESULTS_PER_PAGE)
    @messages_count = @messages.total_count
  end

  private

  def scope_for_user
    # Respeita permissões de inbox do agente
    inbox_ids = Current.user.assigned_inboxes.where(account_id: Current.account.id).pluck(:id)
    Attachment.joins(message: :conversation)
              .where(conversations: { inbox_id: inbox_ids })
              .merge(filter_by_inbox)
              .merge(filter_by_contact)
              .merge(filter_by_date_range)
              .merge(filter_by_query)
  end

  def links_scope
    # Messages contendo http(s) URLs no content
    Current.account.messages
           .where("content ~* ?", '\bhttps?://[^\s]+')
           .joins(conversation: :inbox)
           .where(conversations: { inbox_id: visible_inbox_ids })
           .merge(filter_by_query_in_content)
  end

  def parse_types
    requested = (params[:type] || 'image,video').split(',')
    requested & ALLOWED_TYPES
  end

  def sort_clause
    case params[:sort]
    when 'date_asc' then { created_at: :asc }
    when 'size_desc' then { byte_size: :desc } # joined ActiveStorage::Blob
    when 'size_asc' then { byte_size: :asc }
    else { created_at: :desc }
    end
  end
end
```

**Performance backend:**
- Índice composto: `messages(account_id, created_at DESC)` (já existe).
- Índice em `attachments(file_type)` (verificar — provavelmente já tem).
- Pagination keyset (não offset) se total > 10k attachments para evitar `ORDER BY offset` lento. Fase 2 se necessário.
- Eager loading agressivo (`includes`) para evitar N+1.
- ActiveStorage variants: gerar 200×200 e 800×600 sob demanda (cacheado pelo S3/disco).

**Roteamento:**
```ruby
# config/routes.rb (dentro de namespace api/v1/accounts)
resources :attachments, only: [:index] do
  collection do
    get :links
  end
end
```

#### Frontend — Estrutura

**Rota nova:**
```js
// app/javascript/dashboard/routes/dashboard/gallery/gallery.routes.js (NOVO)
{
  path: 'gallery',
  name: 'gallery',
  component: () => import('./GalleryPage.vue'),
  meta: { permissions: ['administrator', 'agent'] },
}
```

**Componentes:**
```
app/javascript/dashboard/routes/dashboard/gallery/
├── GalleryPage.vue              (entry, tabs, filters, search bar, multi-select toolbar)
├── components/
│   ├── GalleryTabs.vue          (Mídia | Documentos | Links)
│   ├── GalleryFilters.vue       (inbox, contato, range data, sort)
│   ├── GallerySearchBar.vue     (busca debounced)
│   ├── GallerySelectToolbar.vue (download / forward / share quando selecionado)
│   ├── MediaGrid.vue            (grid virtual de fotos+vídeos)
│   ├── MediaItem.vue            (item individual com lazy thumbnail)
│   ├── MediaLightbox.vue        (preview ampliado ao clicar)
│   ├── DocumentList.vue         (lista virtual de docs/áudio)
│   ├── DocumentItem.vue         (linha com ícone, nome, tamanho, sender, conversa)
│   ├── LinkList.vue             (lista virtual de links)
│   └── LinkItem.vue             (preview rico: og:image, og:title, og:description)
└── composables/
    ├── useGalleryAttachments.js (fetch + cache + pagination)
    ├── useGalleryLinks.js       (fetch + extração)
    ├── useGallerySelection.js   (multi-select state)
    └── useGalleryFilters.js     (URL query sync para deeplink)
```

**API client:**
```js
// app/javascript/dashboard/api/gallery.js (NOVO)
import ApiClient from './ApiClient';
class GalleryAPI extends ApiClient {
  constructor() { super('attachments', { accountScoped: true }); }
  list({ types, inboxId, contactId, sort, before, after, q, page }) { /* ... */ }
  links({ q, inboxId, contactId, sort, page }) { /* ... */ }
}
export default new GalleryAPI();
```

**Store:**
```
app/javascript/dashboard/store/modules/gallery/
├── index.js
├── actions.js
├── getters.js
├── mutations.js
└── types.js
```

**Sidebar entry:**
```js
// app/javascript/dashboard/components-next/sidebar/sidebarItems.js
{
  name: 'gallery',
  icon: 'gallery',           // novo entry em LORDICON
  label: 'SIDEBAR.GALLERY',
  toState: '/gallery',
  toStateName: 'gallery',
  permissions: ['administrator', 'agent'],
}
```

```js
// app/javascript/dashboard/constants/lordicons.js
gallery: {
  idle: 'https://cdn.lordicon.com/ltjljakp.json',  // confirmado
  active: 'https://cdn.lordicon.com/ltjljakp.json', // TODO: solid pair quando disponível
  family: 'system',
}
```

**i18n:**
```json
// pt_BR/sidebar.json
"GALLERY": "Galeria"

// pt_BR (novo arquivo) gallery.json
"GALLERY": {
  "TITLE": "Galeria",
  "TABS": {
    "MEDIA": "Mídia",
    "DOCUMENTS": "Documentos",
    "LINKS": "Links"
  },
  "SEARCH_PLACEHOLDER": "Buscar por nome, contato ou descrição",
  "EMPTY": {
    "MEDIA": "Nenhuma mídia compartilhada ainda",
    "DOCUMENTS": "Nenhum documento compartilhado ainda",
    "LINKS": "Nenhum link compartilhado ainda"
  },
  "SORT": {
    "DATE_DESC": "Mais recente",
    "DATE_ASC": "Mais antigo",
    "SIZE_DESC": "Maior tamanho",
    "SIZE_ASC": "Menor tamanho"
  },
  "FILTERS": {
    "ALL_INBOXES": "Todas as caixas",
    "ALL_CONTACTS": "Todos os contatos",
    "DATE_RANGE": "Período"
  },
  "ACTIONS": {
    "DOWNLOAD": "Baixar",
    "FORWARD": "Encaminhar",
    "SHARE": "Compartilhar",
    "OPEN_CONVERSATION": "Abrir conversa",
    "SELECT_ALL": "Selecionar tudo",
    "DESELECT": "Limpar seleção"
  }
}
```

### Performance — checklist obrigatório

1. **Virtual scroll** com windowing manual (não importar lib pesada).
   - Renderizar só items visíveis ± buffer de 6 linhas.
   - Reusar nodes via `v-for :key="item.id"`.
2. **Lazy thumbnails:**
   - Backend serve variant 200×200 (`representation(resize_to_limit: [400, 400])`).
   - `<img loading="lazy" decoding="async" fetchpriority="low">`.
   - Placeholder blur (LQIP) opcional, fase 2.
3. **Paginação infinita** com `IntersectionObserver` na sentinela (last 3 rows).
4. **Cache no store** por combinação de filtros (`Map<filterKey, page[]>`).
5. **Debounce busca** 300ms.
6. **Preview lightbox**:
   - Carrega `preview_url` (800×600) primeiro.
   - `original_url` apenas em "ver original" ou ao baixar.
   - Revoga blob URLs ao fechar.
7. **Cancellation:** AbortController nos fetches em troca de aba/filtro.
8. **Backend:**
   - `account.attachments.includes(:blob, message: [:sender, :conversation])`.
   - `EXPLAIN ANALYZE` na query principal antes de subir.
   - Considerar índice parcial em `attachments(file_type)` para `image, video, file`.
9. **Multi-select:** state isolado em composable, não toca DOM (Set de IDs).
10. **Download múltiplo:** zip server-side se > 5 arquivos OU sequência de `<a download>` se ≤ 5.

### Lordicon `ltjljakp` — FECHADO

- **System family** (igual aos demais ícones do sidebar).
- **Idle:** `https://cdn.lordicon.com/ltjljakp.json` ✓
- **Active:** mesma URL (`ltjljakp`), com bold stroke aplicado via lógica já existente no `LordIconIcon.vue` para o estado ativo. Sem dependência de solid pair.

### Integração com features existentes

- **Forward:** reusar `ConversationApi.forwardMessage(messageId, conversationIds, contactIds)`.
- **Open conversation:** `router.push({ name: 'inbox_conversation', params: { conversation_id: ... } })`.
- **Permissões:** respeitar `Current.user.assigned_inboxes` no backend (essencial — agente não pode ver mídia de inboxes que não tem acesso).
- **Audit/log:** considerar log de "agente baixou em massa" para compliance (fase 2).

### Estimativa Item 5

| Sub-item | Esforço |
|----------|---------|
| Backend: AttachmentsController + routes + spec | 1.5h |
| Backend: índices DB + EXPLAIN | 0.5h |
| Frontend: API client + store | 1h |
| Frontend: GalleryPage + tabs + filters + search | 2h |
| Frontend: MediaGrid (virtual scroll + lazy) | 2h |
| Frontend: DocumentList + LinkList | 1.5h |
| Frontend: Lightbox + multi-select toolbar | 1.5h |
| Frontend: Sidebar entry + rota + i18n | 0.5h |
| QA Playwright + dark mode + edge cases | 1h |

**Total Item 5: ~11h.**

---

## Sequência de execução

```
DIA 1 (manhã, ~45min):
  3. Scrollbar  →  2. Botão busca  →  1. Auto-mark notif

DIA 1 (tarde, ~45min):
  4. Status pill v B (componente novo + i18n + skin)

DIAS 2-3 (~11h):
  5. Galeria global
     5.1 Backend: controller + routes + spec
     5.2 Frontend: API + store
     5.3 Frontend: GalleryPage + tabs + filters
     5.4 Frontend: MediaGrid virtual + lazy thumbnails
     5.5 Frontend: DocumentList + LinkList
     5.6 Frontend: Lightbox + multi-select + actions
     5.7 Frontend: sidebar entry + rota + i18n
     5.8 QA + dark mode

COMMIT: working tree até "TUDO TUDO" pronto, conforme regra do Walisson.
```

---

## Riscos & mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Galeria global lenta com >10k attachments | Alto | Pagination keyset + virtual scroll + thumbs server-side |
| Permissões vazando mídia entre inboxes | **Crítico** | Filtro server-side via `Current.user.assigned_inboxes` |
| Thumbnails crescendo S3 sem TTL | Médio | ActiveStorage variants são cacheadas; monitorar storage |
| Solid pair Lordicon indisponível | Baixo | Fallback bold stroke já implementado |
| Status pill v B confunde quem usava v atual | Médio | Manter labels claros + tooltip explicando ações |
| Múltiplos selecionados → request grande | Médio | Limitar select a 100 itens na fase 1; zip server-side se > 5 |
| Links extraídos por regex pegam falso positivo (ex: emails) | Baixo | Regex restritivo `\bhttps?://[^\s]+\b` + sanitize URL |
| Notificações double-fire (Item 1) | Baixo | Verificar `match` antes de despachar; idempotente server-side |

---

## Pendências externas — TODAS FECHADAS

1. ~~Lordicon solid pair~~ → System family + bold stroke no active (lógica existente).
2. ~~Download múltiplo~~ → ≤5 sequencial, >5 zip server-side.
3. **Forward** → permite forward para múltiplas conversas (UI fase 1, reusa `forwardMessage` API).

---

## Checklist de aceitação (DOD)

- [ ] Item 1: abrir conversa pelo dashboard zera notificação
- [ ] Item 2: botão busca coerente visualmente com sidebar
- [ ] Item 3: scrollbar não aparece em telas largas sem overflow
- [ ] Item 4: 5 estados (open assigned/unassigned, pending, snoozed, resolved) renderizam badge + botão correto
- [ ] Item 4: kebab funciona com click-outside
- [ ] Item 5: rota `/gallery` acessível pelo sidebar
- [ ] Item 5: 3 tabs (Mídia/Docs/Links) carregam dados reais
- [ ] Item 5: busca + sort + filtros (inbox, contato, data) funcionam
- [ ] Item 5: multi-select + download/forward/share/abrir conversa funcionam
- [ ] Item 5: scroll de 1000+ items mantém 60fps
- [ ] Item 5: dark mode em todos componentes
- [ ] Item 5: permissões respeitadas (agente só vê inboxes atribuídas)
- [ ] `pnpm eslint` sem erros
- [ ] `bundle exec rubocop -a` sem offenses
- [ ] Recompile + restart `chatwoot.target` em hmlchat
- [ ] QA Playwright em conta real

---

**Pronto para executar quando você der o GO.** Pode mandar "executa" e eu sigo na sequência sugerida (3 → 2 → 1 → 4 → 5), em working tree, sem commit até estar TUDO TUDO pronto.
