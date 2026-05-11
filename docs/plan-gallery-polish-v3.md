# Plano v3 — Polir Galeria (alinhamento, ícones, filtro WhatsApp)

**Data:** 2026-04-27
**Branch:** `homologacao` (working tree, sem commit)
**Origem:** feedback Walisson após /qa-playwright da galeria v1

---

## Problemas detectados via Playwright na hmlchat

### A. Stickers WhatsApp poluindo a aba Mídia
Inboxes do account 3 = todas `Channel::Api` (WAHA-WhatsApp) + 1 `Channel::WebWidget`.
A aba Mídia mostra centenas de **stickers `.webp`** que entraram via integração WhatsApp.
Visualmente aparecem como padrões "QR-like" (transparência + pattern de sticker).

**Impressão do usuário:** "esse é da nossa API, sabe. não faz muito sentido."
- Walisson reconhece que `Channel::Api` é a integração interna de WhatsApp.
- Não faz sentido a galeria global misturar:
  - Mídia útil (foto/vídeo/áudio que o agente trocou com o cliente)
  - Stickers que o cliente mandou (lixo visual, sem valor de busca)

### B. Documentos duplicados
Mesma `.pdf` aparece 6+ vezes seguidas com tamanhos idênticos.
Provável causa: forward múltiplo via WAHA gera múltiplos `Attachment` registros para o mesmo blob.
Não é bug do controller — o banco realmente tem dupes.

### C. Ícones lucide dentro da galeria
Auditoria via JS: **66 elementos `i-lucide-*`** vs 12 `lord-icon` na página.
- Tabs (Mídia / Documentos / Links): `i-lucide-image`, `i-lucide-file`, `i-lucide-link`
- Toolbar de ações (Baixar / Compartilhar / Limpar): `i-lucide-download`, `i-lucide-share-2`, `i-lucide-x`
- Cards de mídia: ícones lucide dentro dos overlays
- Empty state: `i-lucide-inbox`, `i-lucide-loader-2`

**Pedido Walisson:** ícones internos devem ser **system family do Lordicon**, igual ao sidebar.

### D. Outros achados menores
- Contador "1706 itens" no header — fica no estado da última requisição feita (mostra docs ao trocar de aba sem zerar).
- Empty state genérico — quando documentos vêm vazios, ainda aparecem 41 ".oga" sem nome.
- Em hmlchat as URLs de Active Storage apontam para `chatspx.app` (FRONTEND_URL config) — fora do escopo deste plano, mas explica eventuais 404 visuais em prod-staging.

---

## Decisões a confirmar com Walisson

| # | Pergunta | Default proposto |
|---|----------|------------------|
| 1 | "Inboxes WhatsApp" = filtrar **todas** `Channel::Api`? | **Sim** — incluindo `Channel::Whatsapp` e `Channel::TwilioSms` com `medium='whatsapp'`. |
| 2 | Filtrar **só stickers** ou **todas as mídias** vindas de WhatsApp? | **Só stickers + figurinhas** (extension `.webp` + tamanho < 100KB, ou content_attributes que indique `sticker`). Foto/vídeo/áudio enviados pelo cliente continuam visíveis. |
| 3 | Documentos duplicados (dupes reais no banco): deduplicar por `file_size + filename + sender + diff_min < 5min`? | **Sim, deduplicar na query** (DISTINCT ON ou GROUP BY). |
| 4 | Lordicon system para tudo dentro da galeria? Ou só tabs + toolbar? | **Tabs + toolbar + empty state** (cards mantêm lucide pro overlay sutil). |
| 5 | Adicionar toggle "Mostrar stickers" como opt-in oculto? | **Não** — manter simples, esconder de vez. |

---

## Item 1 — Filtro server-side de stickers/mídias WhatsApp

### Backend — `AttachmentsController#index`

Adicionar filtro WHERE para excluir mídias com características de sticker WhatsApp:

```ruby
# app/controllers/api/v1/accounts/attachments_controller.rb

WHATSAPP_CHANNEL_TYPES = %w[
  Channel::Api
  Channel::Whatsapp
].freeze

def base_scope
  inbox_ids = visible_inbox_ids
  return Attachment.none if inbox_ids.blank?

  scope = Attachment.joins(message: { conversation: :inbox })
                    .where(messages: { account_id: Current.account.id })
                    .where(conversations: { inbox_id: inbox_ids })
  scope = exclude_whatsapp_stickers(scope)  # NEW
  scope = filter_by_inbox(scope)
  scope = filter_by_contact(scope)
  scope = filter_by_date_range(scope)
  filter_by_query(scope)
end

private

def exclude_whatsapp_stickers(scope)
  # Sticker WhatsApp = .webp pequeno (<100KB) vindo de inbox WhatsApp.
  # Estrutura: ActiveStorage blob → content_type / byte_size.
  scope.joins("LEFT JOIN active_storage_attachments asa ON asa.record_id = attachments.id AND asa.record_type = 'Attachment' AND asa.name = 'file'")
       .joins("LEFT JOIN active_storage_blobs asb ON asb.id = asa.blob_id")
       .where.not(
         "(inboxes.channel_type IN (:wa) OR (inboxes.channel_type = :twilio AND inboxes.medium = 'whatsapp')) AND asb.content_type = 'image/webp' AND asb.byte_size < 100000",
         wa: WHATSAPP_CHANNEL_TYPES, twilio: 'Channel::TwilioSms'
       )
end
```

**Alternativa simples (Plano B se A não pegar todos):** filtrar por `content_attributes->>'message_type' = 'sticker'` ou por presença de `content_attributes->'sticker'`.

### Spec a adicionar

```ruby
# spec/controllers/api/v1/accounts/attachments_controller_spec.rb
it 'excludes whatsapp stickers from media tab' do
  whatsapp_inbox = create(:inbox, account: account, channel_type: 'Channel::Api')
  conversation = create(:conversation, inbox: whatsapp_inbox)
  message = create(:message, conversation: conversation)
  sticker = create_sticker_attachment(message)  # .webp, 50KB
  photo = create_photo_attachment(message)     # .jpg, 500KB

  get "/api/v1/accounts/#{account.id}/attachments", headers: agent.create_new_auth_token

  ids = JSON.parse(response.body)['payload'].map { |a| a['id'] }
  expect(ids).to include(photo.id)
  expect(ids).not_to include(sticker.id)
end
```

---

## Item 2 — Deduplicação de documentos

Adicionar `DISTINCT ON (filename, byte_size, sender_id, date_trunc('hour', created_at))` na query de Documentos:

```ruby
def base_scope_documents
  base_scope.select("DISTINCT ON (asb.byte_size, attachments.message_id) attachments.*")
            .joins(...)  # já joinou blob no filtro de stickers
end
```

**Alternativa minimal:** apenas no front, manter cache de `${filename}_${byte_size}` e suprimir dupes consecutivos.

---

## Item 3 — Lordicon system nas tabs e toolbar

### Constants — adicionar 5 novos icons

```js
// app/javascript/dashboard/constants/lordicons.js — appendar:
galleryMedia:      { idle: 'https://cdn.lordicon.com/{TBD}.json', active: '...', family: 'system' },
galleryDocuments:  { idle: 'https://cdn.lordicon.com/{TBD}.json', active: '...', family: 'system' },
galleryLinks:      { idle: 'https://cdn.lordicon.com/{TBD}.json', active: '...', family: 'system' },
galleryDownload:   { idle: 'https://cdn.lordicon.com/{TBD}.json', active: '...', family: 'system' },
galleryShare:      { idle: 'https://cdn.lordicon.com/{TBD}.json', active: '...', family: 'system' },
```

**Ação Walisson:** confirmar slugs system family do Lordicon (mesma família já usada — `system-outline-72-*`).
Sugestões pesquisando lordicon.com/icons/system:
- Mídia: `photo` (`ltjljakp.json` já tem) → reuse `gallery`
- Documentos: `file-text` ou `document`
- Links: `link` ou `chain`
- Download: `download` (`fdxqrdfe.json` candidato)
- Share: `share` (`hroklero.json` candidato)

Se Walisson não passar slugs, usar fallback wired family (igual sidebar) com bold stroke no active.

### Componentes a atualizar

```
app/javascript/dashboard/routes/dashboard/gallery/components/
├── GalleryTabs.vue          — trocar i-lucide → LordIconIcon
├── GallerySelectToolbar.vue — Download/Share/Clear → LordIconIcon
└── GalleryPage.vue          — empty state icon
```

### Padrão de uso (mesmo do sidebar)

```vue
<LordIconIcon
  :src="LORDICON.galleryDownload.idle"
  :src-active="LORDICON.galleryDownload.active"
  :family="LORDICON.galleryDownload.family"
  fallback-lucide="i-lucide-download"
  :size="16"
  class="text-current"
/>
```

---

## Item 4 — Total count consistente por aba

Hoje `meta.totalCount` reflete a última request. Trocar para um total **por aba**:

```js
// gallery.js (store) — já tem $state.meta[tab].totalCount, então só usar getter por tab
// GalleryPage.vue — usar `meta.totalCount` que já é `getMeta(tab)`. Verificar se template referencia
```

Bug provável: o template usa `meta.totalCount` direto. Já está correto. **Ler novamente para validar — pode ser falso positivo do QA.**

---

## Item 5 — Empty state com Lordicon + texto correto

```vue
<!-- GalleryPage.vue empty state -->
<LordIconIcon
  :src="LORDICON.galleryEmpty.idle"
  :family="LORDICON.galleryEmpty.family"
  fallback-lucide="i-lucide-inbox"
  :size="40"
  class="opacity-50"
/>
```

Empty state ainda mostra "Nenhuma mídia compartilhada ainda" mesmo quando docs estão presentes — bug é só no comportamento que detectei na screenshot ao trocar de aba sem reset. Validar.

---

## Sequência de execução

```
DIA 1 — confirmar decisões 1-5 com Walisson
DIA 1 — Item 1 (filtro stickers): backend + spec  ~1h
DIA 1 — Item 2 (deduplicação docs): backend       ~30min
DIA 1 — Item 3 (Lordicon tabs/toolbar): frontend  ~45min
DIA 1 — Item 4+5 (polimento total/empty): front   ~20min
DIA 1 — recompile + restart + QA Playwright       ~20min

Total: ~3h
```

---

## Riscos & mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Filtro de sticker pega fotos `.webp` legítimas | Médio | Limitar por `byte_size < 100000`; expor toggle dev pra debugar |
| `DISTINCT ON` muda paginação Kaminari | Baixo | Usar subquery OR aplicar dedupe só no payload do JSON |
| Slugs Lordicon system indisponíveis | Baixo | Fallback wired (igual sidebar) com stroke bold no active |
| URLs Active Storage apontando para chatspx.app na hmlchat | Crítico (já existe) | **Fora deste plano** — investigar separadamente FRONTEND_URL/`config/initializers/active_storage.rb` |

---

## Checklist de aceitação (DOD)

- [ ] Aba Mídia não mostra mais stickers WhatsApp
- [ ] Aba Documentos não mostra dupes consecutivos do mesmo arquivo
- [ ] Tabs (Mídia/Docs/Links) com Lordicon system
- [ ] Toolbar (Baixar/Compartilhar/Limpar) com Lordicon system
- [ ] Empty state com Lordicon
- [ ] Contador no header reflete a aba ativa
- [ ] `pnpm eslint` e `bundle exec rubocop -a` sem offenses
- [ ] Recompile assets + restart `chatwoot.target` em hmlchat
- [ ] QA Playwright: 0 erros JS, screenshots aprovados visualmente
- [ ] Sem commit (working tree até Walisson aprovar)

---

## Dúvidas que **eu preciso** que você confirme antes de executar

1. **Vai liberar slugs do Lordicon system pra esses 5 ícones (Mídia/Docs/Links/Download/Share)?** Ou usa fallback wired igual sidebar?
2. **Filtrar `Channel::Api` inteiro ou só stickers `.webp` pequenos?** O nuclear remove TUDO de WhatsApp; o cirúrgico mantém foto/áudio/pdf úteis.
3. **Deduplicar docs no banco ou no front?** No banco é mais correto; no front é mais simples.

— Orion, orquestrando o sistema 🎯
