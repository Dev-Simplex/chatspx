# Plano — Download em massa de mídias (Galeria + Conversa)

| | |
|---|---|
| **Data** | 2026-06-11 |
| **Status** | Planejamento — aguardando aprovação para implementar |
| **Solicitante** | Ederson (Simplex) |
| **Público-alvo deste doc** | Dev que vai implementar |
| **Telas afetadas** | Galeria (`/app/accounts/:id/gallery`) e painel de conversa (aba "Mídias e Arquivos") |
| **Stack** | Rails 7.1 + Sidekiq + ActiveStorage (backend) · Vue 3 + Vuex (dashboard) |

---

## 1. Contexto e problema

Hoje o operador baixa mídia **uma por uma**:

- **No chat:** cada imagem/vídeo tem botão de download individual (bolha ou lightbox). Para salvar 40 fotos de uma conversa, são 40 cliques.
- **Na Galeria** (`https://tozi.chatspx.app/app/accounts/6/gallery`): existe seleção múltipla, mas o botão "Baixar" tem **limite hard-coded de 5 arquivos** e dispara 5 downloads soltos no navegador — sem ZIP, sem progresso, sem opção de "baixar tudo".

Pedido do usuário: **seletor para baixar em massa** (dezenas/centenas de mídias de uma vez), tanto na galeria quanto a partir de uma conversa.

---

## 2. O que JÁ existe no código (mapeado em 2026-06-11)

> Importante: **boa parte do trabalho de UI já está pronta na galeria.** O que falta de verdade é o caminho de download em massa (ZIP no backend) e a seleção na tela de conversa.

### 2.1 Galeria — seleção múltipla JÁ implementada

| Peça | Arquivo | Detalhe |
|---|---|---|
| Estado de seleção | `app/javascript/dashboard/routes/dashboard/gallery/GalleryPage.vue:30` | `const selection = ref(new Set())` — local no componente (não no store). `toggleSelect` (l.58-63), `selectAll` (l.69-71), `clearSelection` (l.65-67). Seleção **zera ao trocar de aba** (watch, l.96). |
| Toolbar de seleção | `app/javascript/dashboard/routes/dashboard/gallery/components/GallerySelectToolbar.vue` | Aparece quando `selection.size > 0` (GalleryPage l.175-181). Ações atuais: Baixar, Compartilhar (`navigator.share`), Selecionar tudo, Limpar. |
| **Limite atual** | `GallerySelectToolbar.vue:36` | `if (downloadable.length > 5)` → alerta `GALLERY.ACTIONS.DOWNLOAD_LIMIT` ("Limite de 5 arquivos por vez") e aborta. |
| Download atual | `GallerySelectToolbar.vue:13-47` | `downloadOne()` cria `<a download>` por arquivo, em cadeia com delay de 250ms. Sem ZIP, sem progresso, sem retry. |
| `selectAll` | `GalleryPage.vue:69-71` | Seleciona **só os registros já carregados** (paginação de 30, infinite scroll) — não "todos do filtro" no servidor. |
| Checkboxes nos itens | `MediaGrid.vue:154`, `DocumentList.vue:130-131` | Emitem `toggleSelect`. |
| Download no lightbox | `MediaLightbox.vue:54-55` | `<a :href="item.dataUrl" :download="item.filename">`. |

### 2.2 Galeria — backend

- **Endpoint:** `GET /api/v1/accounts/:account_id/attachments` (+ `/links`) — rotas em `config/routes.rb:212-216`.
- **Controller:** `app/controllers/api/v1/accounts/attachments_controller.rb`
  - 30 itens/página (`RESULTS_PER_PAGE`, l.4), cache de 5 min por usuário+filtro (l.71-79).
  - Filtros: `type` (csv de file_types), `inbox_id`, `contact_id`, `before`, `after`, `q`, `sort` (l.82-84).
  - **Escopo de visibilidade** (l.92-104): agente só vê attachments de inboxes em que está atribuído (`Current.user.assigned_inboxes`, l.156-157).
  - **Regra de produto** `exclude_incoming_whatsapp` (l.110-115): mídia *incoming* de canais WhatsApp/API não aparece na galeria.
  - **Dedup** por window function (`ROW_NUMBER` particionado por byte_size+filename+sender+hora, l.121-138).
- **Payload** (`app/views/api/v1/accounts/attachments/index.json.jbuilder`): `id, message_id, thumb_url, data_url, file_size, file_type, extension, filename, created_at, conversation{id, display_id, inbox_id}, sender`.
- **Store/API client front:** `app/javascript/dashboard/store/modules/gallery.js` (normalização l.67-92) e `app/javascript/dashboard/api/gallery.js`.

### 2.3 Conversa (chat) — estado atual

- **Aba "Mídias e Arquivos":** `app/javascript/dashboard/routes/dashboard/conversation/ConversationMedia.vue`, renderizada no `ContactPanel.vue:154-166`. Agrupa em imagens/vídeos/áudios/documentos/links, 9 por seção + "mostrar mais". **Sem seleção, sem download em massa.**
- **Fonte de dados:** action `fetchAllAttachments` (`store/modules/conversations/actions.js:177-208`, com guard anti-loop) → `GET /api/v1/accounts/:account_id/conversations/:id/attachments` (40/página).
- **⚠️ Gap descoberto:** o endpoint (`app/controllers/api/v1/accounts/conversations_controller.rb:33-43`) filtra `file_type: [:image, :video, :ig_reel]` — **as seções de áudio e documentos da aba ficam sempre vazias** hoje. Precisa ampliar o filtro junto com esta feature.
- **Download individual:** lightbox `GalleryView.vue:225-237` usa `downloadFile` de `@chatwoot/utils` (fetch blob → `<a download>`); bolha de imagem em `components-next/message/bubbles/Image.vue:39-49`; arquivos via `<a href>` direto.

### 2.4 Backend — blocos reutilizáveis (e o que falta)

- **❌ Não existe gem de ZIP** no Gemfile (nem rubyzip, nem zip_kit — conferido no Gemfile.lock). Precisa adicionar.
- **✅ Padrão de export assíncrono pronto para espelhar:** a feature de export de PDF de conversa (já no fork) tem exatamente a anatomia que precisamos:
  - Model `ConversationPdfExport` (`app/models/conversation_pdf_export.rb`): enum `status` (pending/processing/completed/failed), `filters` jsonb, `audit_meta` jsonb, `expires_at`, `has_one_attached :file`, `download_url` assinada com `expires_in: 24.hours, disposition: 'attachment'` (l.37-45).
  - Job `Conversations::ExportPdfJob` (fila `:low`) — marca processing → gera → attach → completed/failed.
  - Controller v2 `pdf_exports_controller.rb` — `POST` retorna `202 Accepted` com o record; front faz polling.
- **Outros padrões:** `Account::ContactsExportJob` (attach + mailer com link); mailer `AdministratorNotifications::AccountNotificationMailer#contact_export_complete`.
- **Infra de entrega de arquivo:** `production.rb:40` usa `X-Accel-Redirect`; nginx tem `location /send_file_accel/` com `sendfile`/`aio threads` (`deployment/nginx_chatwoot.conf:100-113`) — download do ZIP pronto sai por aí, sem ocupar o Puma. Timeouts proxy 900s.
- **Notificações in-app** (`app/models/notification.rb:38-47`): enum **fechado** de tipos — adicionar tipo novo mexe em backend+front. **Evitar no v1** (polling resolve, igual ao PDF export).
- **Sidekiq:** fila `:low` é a usada por exports (config/sidekiq.yml).
- **Attachment model** (`app/models/attachment.rb`): `has_one_attached :file` (l.39), enum `file_type` (l.42), `file_url`/`download_url`/`thumb_url` (l.54-73), e atenção ao caso **Instagram incoming**: `data_url` vira `external_url` (l.105-121) — pode **não ter blob local**.

---

## 3. Objetivo e requisitos

### Requisitos funcionais

- **RF1** — Na **Galeria**, baixar os itens selecionados como **um único arquivo .zip**, sem o limite de 5.
- **RF2** — Na Galeria, opção **"Selecionar tudo do filtro"** (todos os N itens que o filtro atual retorna no servidor, não só os 30 carregados na tela) e baixar esse conjunto.
- **RF3** — Na **conversa**, na aba "Mídias e Arquivos": modo de seleção com checkboxes + botão **"Baixar selecionados (.zip)"**.
- **RF4** — Na conversa, atalho **"Baixar todas as mídias"** (1 clique, sem selecionar 1 a 1) — com filtro opcional por tipo (fotos/vídeos/áudios/documentos).
- **RF5** — Feedback de progresso durante a geração (X de Y arquivos) e download automático quando pronto.
- **RF6** — Estrutura interna do ZIP organizada e nomes de arquivo legíveis (ver §5.6); itens não baixáveis listados num `_manifest.txt`.
- **RF7** — Manter o download direto (sem zip) para lotes pequenos — comportamento atual, com limite ajustado.

### Requisitos não-funcionais

- **RNF1 — Memória:** gerar o ZIP em streaming para arquivo temporário; **nunca** montar o ZIP inteiro em RAM (vídeos de centenas de MB × centenas de itens). Pico de RAM alvo: ~1 chunk (≤10 MB) por job.
- **RNF2 — Infra Cloudflare:** `*.chatspx.app` passa pelo Cloudflare; resposta síncrona longa arrisca 524 (~100s sem resposta). A geração tem que ser **assíncrona** (job), e o download final é de um blob estático (rápido de iniciar).
- **RNF3 — Disco:** ZIPs são temporários: expiração + purge automático. Cap de tamanho por solicitação.
- **RNF4 — Segurança:** revalidar **no servidor** o acesso a cada attachment (mesmo escopo de visibilidade da tela de origem). IDs vindos do front nunca são confiáveis.
- **RNF5 — Auditoria (LGPD):** exportação em massa de mídia de clientes deve registrar quem pediu, quando, de onde (IP) e o quê.
- **RNF6 — Não regredir:** cache da galeria, dedup e regra `exclude_incoming_whatsapp` continuam valendo no que o usuário vê e baixa pela galeria.

### Fora de escopo (v1)

- Seleção múltipla dentro do lightbox/preview (GalleryView/MediaLightbox).
- Notificação in-app via `Notification` (enum fechado) e e-mail com link — candidatos a v2.
- App mobile.
- Persistir seleção da galeria ao trocar de aba.

---

## 4. Decisão de arquitetura

### Opções avaliadas

| Opção | Como | Prós | Contras | Veredito |
|---|---|---|---|---|
| **A. Só subir o limite do front** | Trocar o `5` por `30` no toolbar; downloads soltos | 1 linha; zero backend | Não escala (30 diálogos de download), sem zip, sem "todos do filtro", navegador pode bloquear | ❌ Como solução. ✅ Como *quick win* paliativo (§12, F0) |
| **B. ZIP síncrono em streaming** (gem `zip_kit`, resposta chunked) | Controller streama o zip na própria request | UX imediata, sem disco | Gem nova + interação delicada com Puma/nginx buffering/**Cloudflare 524**; ocupa worker Puma por minutos; sem retry | ❌ |
| **C. ZIP assíncrono (job Sidekiq + polling + blob)** | `POST` cria registro → job gera zip em tempfile → attach no ActiveStorage → front faz polling → download automático | Robusto na infra atual (CF, X-Accel), espelha padrão **já existente** (`ConversationPdfExport`), progresso real, auditável, retry | Latência de segundos até iniciar; consome disco temporário | ✅ **Recomendada** |

### Benchmark de mercado (por que ZIP)

Navegador não salva N arquivos numa pasta sem um prompt por arquivo — por isso o mercado inteiro converge para ZIP: **Google Drive/Photos** (zip na hora para seleções médias), **Google Takeout** (job assíncrono + link que expira em 7 dias para exports grandes), **Dropbox** (zip até ~20 GB), **iCloud web** (zip), **Slack** (export assíncrono com link). WhatsApp Web não tem download em massa — esta feature é diferencial. O desenho abaixo é o híbrido Google: direto para lote pequeno, zip assíncrono com link expirável para o resto.

### Arquitetura escolhida (C) — visão geral

```
[Galeria ou Conversa]
   │  POST /api/v1/accounts/:id/attachment_bulk_downloads
   │       { attachment_ids: [...] }  OU  { filters: {...}, select_all: true }
   ▼
AttachmentBulkDownload (record, status: pending) ──► 202 Accepted {id}
   │ enfileira
   ▼
Attachments::BulkDownloadJob (fila :low)
   │ status: processing; processed_count atualizado a cada 10 itens
   │ Zip::OutputStream → Tempfile (streaming chunk a chunk, RAM ~constante)
   │ + _manifest.txt (itens ok + itens pulados e motivo)
   ▼
export.file.attach(zip) ; status: completed
   ▲
   │ polling GET .../attachment_bulk_downloads/:id  (a cada 2,5s)
   │
[Front] quando completed → <a href=download_url> automático + toast
        download_url = rails_blob_url(expires_in: 24h, disposition: attachment)
        (servido via X-Accel/nginx sendfile, fora do Puma)

Purge: job diário apaga exports com expires_at vencido (blob + record)
```

**Regra de UX no botão "Baixar" da galeria:** seleção ≤ **10** itens → download direto como hoje (sobe o limite de 5→10); acima disso (ou clique explícito em "Baixar .zip") → fluxo ZIP.

---

## 5. Especificação backend

### 5.1 Gem

```ruby
# Gemfile (seção de utilidades)
gem 'rubyzip', '~> 2.3'
```

`rubyzip` (não `zip_kit`): não precisamos de streaming HTTP (opção B descartada), e sim de escrita incremental em tempfile — `Zip::OutputStream` cobre. Gem madura, sem extensão nativa.

### 5.2 Migration (additive, segura p/ painel Deploy)

```ruby
# db/migrate/XXXXXXXXXXXXXX_create_attachment_bulk_downloads.rb
class CreateAttachmentBulkDownloads < ActiveRecord::Migration[7.1]
  def change
    create_table :attachment_bulk_downloads do |t|
      t.references :account, null: false, index: true
      t.references :requester_user, index: true            # User que pediu
      t.references :conversation, index: true              # preenchido no modo "conversa"
      t.integer :status, null: false, default: 0           # pending/processing/completed/failed
      t.jsonb :params, null: false, default: {}            # attachment_ids OU filters (+select_all)
      t.integer :total_count, default: 0                   # itens a processar
      t.integer :processed_count, default: 0               # progresso
      t.integer :skipped_count, default: 0
      t.bigint :total_bytes, default: 0
      t.text :error_message
      t.jsonb :audit_meta, null: false, default: {}        # ip, user_agent, origem (gallery|conversation)
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at, index: true                  # p/ purge
      t.timestamps
    end
    add_index :attachment_bulk_downloads, [:account_id, :requester_user_id, :status],
              name: 'idx_bulk_downloads_on_account_requester_status'
  end
end
```

### 5.3 Model

```ruby
# app/models/attachment_bulk_download.rb — espelhar ConversationPdfExport
class AttachmentBulkDownload < ApplicationRecord
  belongs_to :account
  belongs_to :requester_user, class_name: 'User'
  belongs_to :conversation, optional: true
  has_one_attached :file

  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  MAX_FILES       = 500
  MAX_TOTAL_BYTES = 2.gigabytes
  RETENTION       = 7.days

  def download_url
    return nil unless file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(
      file, host: ENV.fetch('FRONTEND_URL'), expires_in: 24.hours, disposition: 'attachment'
    )
  end
end
```

### 5.4 Rotas + Controller

```ruby
# config/routes.rb — junto do resources :attachments existente (l.212-216)
resources :attachment_bulk_downloads, only: [:create, :show]
```

`app/controllers/api/v1/accounts/attachment_bulk_downloads_controller.rb`:

- **`create`** — dois modos, mutuamente exclusivos:
  - `{ attachment_ids: [1,2,3] }` (seleção manual — galeria ou conversa);
  - `{ filters: { type:, inbox_id:, contact_id:, conversation_id:, before:, after:, q: }, select_all: true }` ("selecionar tudo do filtro" / "baixar todas da conversa").
  - Resolve o escopo (ver §5.5), valida caps **antes** de enfileirar:
    - `count > MAX_FILES` → `422` `{ error: 'too_many_files', limit: 500, requested: N }`;
    - `sum(byte_size) > MAX_TOTAL_BYTES` (via `joins(file_attachment: :blob).sum('active_storage_blobs.byte_size')`) → `422` `{ error: 'too_large', ... }`;
    - escopo vazio → `422` `{ error: 'nothing_to_download' }`.
  - **Anti-abuso:** no máximo **1 export ativo** (pending/processing) por usuário → `429` se já houver.
  - Cria o record com `audit_meta` (`requester_user_id/name/email`, `ip: request.remote_ip`, `user_agent`, `origin`), `total_count`, `expires_at: RETENTION.from_now`; enfileira `Attachments::BulkDownloadJob.perform_later(id)`; responde **`202`** com o JSON do record.
- **`show`** — retorna `{ id, status, total_count, processed_count, skipped_count, file_size, download_url, error_message }`. **Só o `requester_user` (ou administrator) pode consultar.**

### 5.5 Resolução de escopo e autorização (ponto mais sensível)

Regra de ouro: **o usuário só baixa em massa o que já vê na tela de origem.**

| Modo | Escopo | Regras aplicadas |
|---|---|---|
| Galeria (ids ou filters sem `conversation_id`) | Mesmo escopo do `attachments#index` | `visible_inbox_ids` (assigned_inboxes), `exclude_incoming_whatsapp`, **dedup** (window function), filtros type/inbox/contact/datas/q |
| Conversa (`conversation_id` presente) | `conversation.attachments` | `authorize @conversation, :show?` (Pundit `ConversationPolicy` — inbox/team do agente). **Sem** a regra de WhatsApp (na conversa o agente vê tudo nas bolhas, inclusive incoming) |
| `attachment_ids` | Interseção `ids ∩ escopo` acima | IDs fora do escopo são **silenciosamente descartados** (e contados em `skipped`) — nunca 500, nunca vazar mídia de inbox alheia |

**Refactor obrigatório:** extrair `base_scope`/`exclude_incoming_whatsapp`/`deduped_attachments_scope` do `attachments_controller.rb` (l.92-138) para um objeto reutilizável (ex.: `Attachments::GalleryScopeBuilder.new(user:, account:, params:)`), usado pelo index **e** pelo bulk download. Sem isso as regras divergem na primeira manutenção.

### 5.6 Service de geração do ZIP

`app/services/attachments/bulk_download_zip_service.rb`:

```ruby
# Esqueleto da lógica central
Zip::OutputStream.open(tempfile.path) do |zos|
  scope.includes(file_attachment: :blob, message: :conversation).find_each do |att|
    unless att.file.attached?                       # IG external_url, blob purgado…
      skipped << [att.id, 'sem arquivo armazenado']; next
    end
    # STORED (sem compressão): mídia já é comprimida (JPEG/MP4) — recomprimir
    # gasta CPU para ~0% de ganho; zip vira só "envelope" (padrão Google/Dropbox)
    zos.put_next_entry(entry_name(att), nil, nil, Zip::Entry::STORED)
    att.file.blob.download { |chunk| zos.write(chunk) }  # streaming ~5MB/chunk, RAM constante
    bump_progress!                                  # processed_count += 1 (update a cada 10)
  rescue StandardError => e
    skipped << [att.id, e.class.name]               # 1 arquivo corrompido não mata o lote
  end
  zos.put_next_entry('_manifest.txt')
  zos.write(manifest_text)                          # lista ok + pulados com motivo
end
export.file.attach(io: File.open(tempfile.path),
                   filename: zip_filename, content_type: 'application/zip')
```

**Convenção de nomes dentro do ZIP:**

```
conversa-{display_id}/{YYYY-MM-DD_HHMMSS}_{filename_original_sanitizado}{ext}
# colisão de nome → sufixo " (1)", " (2)"…
# sem conversa associada → pasta "outros/"
# zip_filename: midias_{account_id}_{YYYYMMDD_HHMMSS}.zip
#   modo conversa: conversa_{display_id}_midias_{...}.zip
```

Sanitização: remover `/ \ : * ? " < > |` e controlar UTF-8 (rubyzip grava entry names com flag UTF-8 — testar abertura no Windows Explorer, ver §11).

### 5.7 Job

`app/jobs/attachments/bulk_download_job.rb` — espelho do `Conversations::ExportPdfJob`:

- `queue_as :low`; `retry_on StandardError, wait: 5.minutes, attempts: 3`; em falha final → `status: :failed` + `error_message`.
- `started_at`/`completed_at`; tempfile **sempre** removido em `ensure`.
- Logar início/fim com `account_id`, `requester_user_id`, contagens e bytes (auditoria, RNF5).

### 5.8 Purge (retenção)

`app/jobs/attachments/purge_expired_bulk_downloads_job.rb`, agendado **diário** via sidekiq-cron (`config/schedule.yml`, junto dos demais jobs recorrentes):

- `AttachmentBulkDownload.where('expires_at < ?', Time.current)` → `file.purge` + `destroy`.
- Bônus: marcar como `failed` exports presos em `processing` há > 2h (job morto por restart de VM).

---

## 6. Especificação frontend

### 6.1 Galeria

**API client** — `app/javascript/dashboard/api/gallery.js`: adicionar `createBulkDownload(payload)` e `getBulkDownload(id)`.

**Store** — `app/javascript/dashboard/store/modules/gallery.js`:

```js
state.bulkDownload = { id: null, status: null, totalCount: 0, processedCount: 0, downloadUrl: null, error: null }
// actions: startBulkDownload({ attachmentIds | filters }), pollBulkDownload(id), resetBulkDownload()
// polling: setInterval 2500ms; parar em completed/failed; timeout de segurança 15min
```

**`GallerySelectToolbar.vue`** (mudança principal):

1. Botão **"Baixar"**: seleção ≤ 10 → fluxo direto atual (trocar o `5` da l.36 por `10`); > 10 → cai automaticamente no fluxo ZIP.
2. Botão novo **"Baixar .zip (N)"** — sempre visível com seleção ativa.
3. Estados do fluxo ZIP no toolbar: `Preparando… (X/Y)` (barra/percentual via polling) → download automático (`<a href=downloadUrl>` programático) + toast de sucesso → erro: toast com mensagem do backend (limites de 500/2GB com texto claro).
4. **"Selecionar tudo do filtro"**: quando o usuário clica "Selecionar tudo" e `meta.totalCount > records carregados`, exibir banner no toolbar (padrão Gmail): *"Os 30 itens visíveis estão selecionados. Selecionar todos os **{totalCount}** do filtro"*. Nesse modo o store marca `selectionScope: 'filter'` e o `startBulkDownload` envia `{ filters: <filtros atuais do state>, select_all: true }` em vez de IDs. Qualquer mudança de filtro/aba reseta o modo.

**`GalleryPage.vue`**: repassar `meta.totalCount` e os filtros atuais ao toolbar; nenhum outro comportamento muda.

### 6.2 Conversa — aba "Mídias e Arquivos"

**`ConversationMedia.vue`:**

1. Header da aba ganha **"Baixar todas (N)"** → `startBulkDownload({ filters: { conversation_id }, select_all: true })`. É o caso de uso nº 1 do usuário — 1 clique, zero seleção.
2. Botão "Selecionar": entra em modo seleção — checkbox sobreposto em cada thumbnail/linha (imagens, vídeos, áudios, documentos), contador + "Baixar selecionados (.zip)" + "Cancelar" em barra fixa no rodapé do painel.
3. Reusar as mesmas actions do store (módulo `gallery` ou extrair composable `useBulkDownload.js` compartilhado — preferir o composable, a galeria e a conversa têm ciclos de vida diferentes).

**Backend correlato (gap do §2.3):** ampliar `conversations_controller.rb#attachments` (l.35) para `file_type: [:image, :video, :ig_reel, :audio, :file]`. Verificado: o lightbox não quebra — `provider.js:120-159` já filtra image/video/ig_reel no front antes de montar o carrossel. Com isso as seções de áudio/documentos da aba passam a funcionar (hoje sempre vazias).

### 6.3 i18n

Novas chaves em `en/gallery.json` + **`pt_BR/gallery.json`** (e `conversation.json` p/ a aba):

```
GALLERY.BULK.DOWNLOAD_ZIP        "Baixar .zip ({count})"
GALLERY.BULK.PREPARING           "Preparando arquivo… ({processed}/{total})"
GALLERY.BULK.READY               "Download iniciado."
GALLERY.BULK.SELECT_ALL_FILTER   "Selecionar todos os {total} do filtro"
GALLERY.BULK.ERROR_TOO_MANY      "Máximo de {limit} arquivos por download. Refine o filtro."
GALLERY.BULK.ERROR_TOO_LARGE     "Seleção excede {limit}. Divida em lotes menores."
GALLERY.BULK.ERROR_ACTIVE        "Você já tem um download em preparação. Aguarde concluir."
CONVERSATION_MEDIA.DOWNLOAD_ALL  "Baixar todas ({count})"
CONVERSATION_MEDIA.SELECT        "Selecionar"
```

Atualizar também `GALLERY.ACTIONS.DOWNLOAD_LIMIT` (en + pt_BR, `pt_BR/gallery.json:42`) de "5" para "10".

---

## 7. Limites e configuração (defaults propostos)

| Constante | Valor | Onde | Racional |
|---|---|---|---|
| `DIRECT_DOWNLOAD_LIMIT` (front) | 10 | GallerySelectToolbar | Acima disso o navegador vira spam de diálogos |
| `MAX_FILES` | 500 | model | Cobre "baixar a conversa inteira" típica com folga |
| `MAX_TOTAL_BYTES` | 2 GB | model | Protege disco/tempo de job; uploads são ≤40MB cada (`MAXIMUM_FILE_UPLOAD_SIZE`) |
| `RETENTION` | 7 dias | model + purge job | Disco é finito nas VMs |
| Polling | 2,5 s | front | Equilíbrio responsividade × carga |
| Exports ativos por usuário | 1 | controller | Anti-abuso simples |

Sem ENV novas obrigatórias (constantes no model; se quiser, aceitar override por ENV depois).

---

## 8. Edge cases (tratamento obrigatório)

| Caso | Tratamento |
|---|---|
| Attachment **sem blob** (Instagram incoming usa `external_url` — `attachment.rb:105-121`; blob purgado) | Pular + registrar no `_manifest.txt` + `skipped_count` |
| Erro de leitura num arquivo (corrompido/IO) | `rescue` por item; lote continua; item vai pro manifest |
| IDs fora do escopo do usuário | Descartar silenciosamente (contam como skipped) — **teste de segurança dedicado** |
| Colisão de nomes no ZIP | Sufixo ` (1)`, ` (2)`… |
| Filename com caracteres inválidos/emoji | Sanitizar (§5.6) |
| Tudo pulado (0 baixáveis) | `status: failed`, `error_message: 'nenhum arquivo disponível'` |
| Duplo clique no botão | Disable + regra de 1 export ativo (429) |
| VM/Sidekiq reiniciado no meio | Retry (3×); preso >2h em processing → failed pelo purge job |
| Seleção feita, filtro mudou antes do download | Front limpa seleção ao mudar filtro/aba (comportamento atual mantido) |
| Dedup da galeria × "selecionar tudo do filtro" | Escopo do bulk usa o **mesmo** scope dedupado → contagem do banner = conteúdo do zip |

---

## 9. Auditoria e segurança (resumo)

- `audit_meta` em todo export: quem, quando, IP, user-agent, origem (gallery/conversation), filtros usados.
- Log estruturado no job (início/fim/erro, contagens, bytes).
- `download_url` assinada, expira em 24h, `disposition: attachment`.
- `show` do export restrito ao requester (ou admin).
- Revalidação de escopo server-side em **todos** os modos (§5.5).
- **Decisão de produto em aberto** (§14): liberar para todo agente (paridade com o que ele já baixa 1-a-1 hoje) ou restringir a administradores. Default proposto: **todo agente, com auditoria**.

---

## 10. Plano de testes

### Specs (RSpec)

- **Model:** enum, caps, `download_url` (com/sem file).
- **Service:** zip gerado abre e contém os arquivos esperados; manifest lista pulados; naming/colisões; attachment sem blob não explode; progresso atualiza.
- **Job:** transições de status; retry; tempfile removido mesmo com exceção; failed com `error_message`.
- **Request specs (controller):**
  - 202 + record nos dois modos (ids / filters+select_all);
  - 422 too_many_files / too_large / nothing_to_download; 429 export ativo;
  - **segurança:** agente A não baixa attachment de inbox que não é dele (via ids e via filters); agente não consulta export de outro usuário; modo conversa respeita `ConversationPolicy`;
  - galeria: zip por filtro bate com o index dedupado (mesma contagem).
- **Front (vitest):** actions/mutations do bulk no store; toolbar renderiza estados (idle/preparando/erro); banner "selecionar todos do filtro" aparece só quando `totalCount > carregados`.

### Manual (homologação — VM 8.100/paulao antes de Tozi)

1. Galeria: selecionar 8 → download direto (sem zip). Selecionar 60 → zip; abrir no Windows Explorer e macOS (nomes acentuados ok).
2. "Selecionar todos do filtro" com ~300 itens incl. vídeos → acompanhar progresso; conferir RAM do worker Sidekiq durante o job (`ps`/`free -h`) — deve ficar estável.
3. Conversa: "Baixar todas" numa conversa com fotos+vídeos+áudios+documentos; conferir pastas/manifest.
4. Lote com mídia Instagram incoming (sem blob) → manifest lista, zip não falha.
5. Estourar caps (>500 / >2GB) → mensagens claras.
6. Em `tozi.chatspx.app` (atrás do Cloudflare): baixar zip ~1,5GB completo.
7. Conferir purge: export com `expires_at` no passado some (record + blob) após o job diário.

---

## 11. Fases, entregáveis e estimativa

| Fase | Conteúdo | Estimativa |
|---|---|---|
| **F0 — Quick win (opcional, dia 0)** | Subir limite direto 5→10 (`GallerySelectToolbar.vue:36`) + i18n en/pt_BR. Sem backend. Alivia a dor enquanto o resto é feito | 0,5 h |
| **F1 — Backend** | Gem rubyzip; migration; model; refactor `GalleryScopeBuilder`; service; job; purge job + schedule; controller + rotas; specs | 2,5–3,5 dias |
| **F2 — Galeria FE** | API client, store/composable `useBulkDownload`, toolbar (zip + progresso + select-all-do-filtro), i18n, specs | 1,5–2 dias |
| **F3 — Conversa FE** | Ampliar tipos no endpoint da conversa; "Baixar todas"; modo seleção na aba; i18n; specs | 1–1,5 dias |
| **F4 — QA + deploy** | Roteiro manual (§10), ajustes, rollout (§13) | 1 dia |
| **Total** | | **~6–8 dias dev** |

Ordem: F1 → F2 → F3 (F2 e F3 compartilham o composable; F3 depende só do endpoint de F1). F0 pode sair imediatamente, independente do resto.

---

## 12. Critérios de aceite

1. ✅ Na galeria, selecionar 200 itens (ou "todos do filtro") e receber **um** `.zip` com todos os arquivos baixáveis + `_manifest.txt`.
2. ✅ Na conversa, "Baixar todas" entrega zip com **todas** as mídias da conversa (incl. áudios e documentos, que hoje nem aparecem na aba).
3. ✅ Progresso visível durante a geração; download inicia sozinho ao concluir.
4. ✅ Lotes ≤10 continuam baixando direto, sem zip (sem regressão do fluxo atual).
5. ✅ Agente não consegue, por nenhum modo (ids/filtros), baixar mídia de inbox à qual não tem acesso (spec cobrindo).
6. ✅ Job de 2GB não passa de ~300MB de RSS no worker Sidekiq.
7. ✅ Zips somem sozinhos após 7 dias.
8. ✅ Funciona atrás do Cloudflare (Tozi) sem 524.

---

## 13. Rollout / deploy (frota Chat SPX)

- **Branch:** desenvolver na branch base do fork e propagar via fluxo normal; **Tozi por último** via cherry-pick para a branch `tozi` (working tree da VM é divergente — seguir o processo de reconciliação vigente, não aplicar à mão na VM).
- **Migration:** apenas `create_table` (additive) — segura para o botão Deploy do painel (que roda `db:migrate`). Mesmo assim: `db:migrate:status` antes de restart (regra da casa).
- **Gem nova (`rubyzip`):** deploy precisa de `bundle install` (fluxo padrão cobre; nas AWS sem GitHub, via bundle git como de costume).
- **Front:** precompile necessário. **Restart: somente o usuário executa** (regra da casa) — preparar tudo e avisar.
- **sidekiq-cron:** novo job no `config/schedule.yml` carrega no restart do Sidekiq.
- Sem ENV novas, sem mudança de nginx (o `/send_file_accel/` existente já serve os blobs).

---

## 14. Decisões em aberto (responder antes da F1)

| # | Decisão | Default proposto |
|---|---|---|
| 1 | Zip liberado para **todo agente** ou só admin? | Todo agente (ele já baixa 1-a-1 hoje), com auditoria |
| 2 | Caps: 500 arquivos / 2 GB ok? | Sim |
| 3 | Retenção do zip: 7 dias ok? | Sim |
| 4 | Enviar **e-mail** com link além do download automático? | Não no v1 (polling resolve); avaliar no v2 |
| 5 | Executar o **quick win F0** (limite 5→10) já? | Sim — custo ~zero |
| 6 | Na conversa, "Baixar todas" inclui mídias **incoming de WhatsApp** (que a galeria esconde)? | Sim — na conversa o agente já vê tudo; manter paridade com a tela |

---

## 15. Referências de código (índice rápido p/ o dev)

| O quê | Onde |
|---|---|
| Toolbar de seleção da galeria (limite 5) | `app/javascript/dashboard/routes/dashboard/gallery/components/GallerySelectToolbar.vue:36` |
| Página da galeria (seleção local) | `app/javascript/dashboard/routes/dashboard/gallery/GalleryPage.vue:30,58-71,96,175-181` |
| Store/API da galeria | `app/javascript/dashboard/store/modules/gallery.js` · `app/javascript/dashboard/api/gallery.js` |
| Controller da galeria (escopo/dedup/cache) | `app/controllers/api/v1/accounts/attachments_controller.rb:92-138,156-157` |
| Rotas attachments | `config/routes.rb:212-216` |
| Aba mídias da conversa | `app/javascript/dashboard/routes/dashboard/conversation/ConversationMedia.vue` (+ `ContactPanel.vue:154-166`) |
| Endpoint attachments da conversa (filtro a ampliar) | `app/controllers/api/v1/accounts/conversations_controller.rb:33-43` |
| Action fetchAllAttachments (guard anti-loop) | `app/javascript/dashboard/store/modules/conversations/actions.js:177-233` |
| Download individual (lightbox) | `.../components/GalleryView.vue:225-237` (helper `downloadFile` de `@chatwoot/utils`) |
| Model Attachment (URLs, IG external_url) | `app/models/attachment.rb:39,42,54-73,105-121` |
| **Padrão a espelhar (export assíncrono)** | `app/models/conversation_pdf_export.rb` · `app/jobs/conversations/export_pdf_job.rb` · `app/controllers/api/v2/accounts/conversations/pdf_exports_controller.rb` |
| Export com mailer (padrão alternativo) | `app/jobs/account/contacts_export_job.rb` |
| X-Accel / nginx | `config/environments/production.rb:40-46` · `deployment/nginx_chatwoot.conf:100-113` |
| Filas Sidekiq | `config/sidekiq.yml` (usar `:low`) |
| i18n galeria | `app/javascript/dashboard/i18n/locale/{en,pt_BR}/gallery.json` |
