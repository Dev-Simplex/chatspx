# Plano de Correções UI/UX — 2026-04-28

> **Contexto:** auditoria solicitada por Walisson após o redesign workspace-v2 (WhatsApp-fiel) introduzir regressões visuais e funcionais. Investigação feita ao vivo em `https://hmlchat.simplexsolucoes.com.br` (conta 5 — Realizare) via Playwright logado, com inspeção de DOM, screenshots e leitura de código.

## Resumo executivo

**9 itens** — **6 reportados** + **3 descobertos** no varrer (VoiceCallButton quebrado, DateSeparator com warning de tipo, hover do bubble por validar). Inclui agora **B9 — Galeria lenta** (`/app/accounts/:id/gallery`) com plano completo de performance + skeleton fundamentado em best practices 2026 (content-visibility, srcset/sizes, AVIF/WebP, fetchpriority, IntersectionObserver via VueUse, prefers-reduced-motion). Estimativa total: ~40min para B1-B8 + ~2-3h para B9 (se backend optimization incluso).

**Decisões aprovadas pelo Walisson:**
- **B5**: manter o **botão flutuante captain** (`SidepanelSwitch`); remover o sparkle duplicado do header.
- **B1**: o toggle do contact panel já existe como botão flutuante junto ao captain — só precisa parar de esconder em desktop.
- **B6**: manter o componente `MessageSignatureMissingAlert` funcional (não apagar o arquivo); remover apenas a renderização permanente no `ReplyBox`.

---

## Mapa de bugs

| ID | Severidade | Bug | Arquivo principal |
|----|-----------|-----|-------------------|
| B1 | 🔴 P0 | Painel de Contatos travado aberto em desktop (toggle some) | `ConversationView.vue` + `SidepanelSwitch.vue` |
| B2 | 🔴 P0 | `VoiceCallButton` não registrado → componente quebra silenciosamente | `ContactInfo.vue` |
| B3 | 🟠 P1 | Botão `+` de reactions sobrepondo borda inferior do bubble | `MessageReactions.vue` + `Base.vue` |
| B4 | 🟠 P1 | Botão Star com `translate-x-full` (fora do bubble, hover difícil) | `Base.vue` |
| B5 | 🟠 P1 | Sparkle do Copilot duplicado no header da conversa | `ConversationHeader.vue` |
| B6 | 🟠 P1 | Banner "assinatura não configurada" permanente | `ReplyBox.vue` |
| B7 | 🟡 P2 | `DateSeparator` recebe `Date` mas declara prop `String` (warning) | `DateSeparator.vue` |
| B8 | 🟡 P2 | Validar regressão do hover original do bubble (chevron `v`) | `Base.vue` |
| B9 | 🔴 P0 | Galeria lenta + sem skeleton (spinner full-screen, query backend ineficiente) | `GalleryPage.vue`, `MediaGrid.vue`, `attachments_controller.rb` |

---

## B1 — Restaurar toggle do contact panel (P0)

**Sintoma**
Em desktop (viewport ≥ 1280px) o painel direito de Contatos fica permanente. Clicar no nome do contato no header não fecha. Botão flutuante de toggle (`i-lucide-user` em `SidepanelSwitch`) está oculto.

**Causa raiz**
1. `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue:142-155` força `return true` quando `viewportWidth >= 1280` (regra "WhatsApp-fiel" introduzida durante o redesign).
2. `app/javascript/dashboard/components-next/Conversation/SidepanelSwitch.vue:32` define `isDesktopAlwaysOnContact = windowWidth >= 1280` e a linha **99** esconde o botão de contact toggle com `v-if="!isDesktopAlwaysOnContact"`.

**Correção**
- `ConversationView.vue`: remover o bloco `if (this.viewportWidth >= 1280) return true;` em `shouldShowSidebar`. Sempre respeitar `uiSettings.is_contact_sidebar_open` (default já é `true` em primeiro acesso).
- `SidepanelSwitch.vue`: remover o `v-if="!isDesktopAlwaysOnContact"` da linha 99 e a `computed isDesktopAlwaysOnContact` (linhas 30-32) — deixa o botão `i-lucide-user` flutuante sempre visível, junto ao calendar (agendar) e captain.
- `ConversationView.vue`: remover também o listener `onResize` e o `viewportWidth` ref que ficaram órfãos após a regra sair.

**Arquivos**
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue` (linhas 63-101 e 142-155)
- `app/javascript/dashboard/components-next/Conversation/SidepanelSwitch.vue` (linhas 30-32 e 99)

**Validação**
- Abrir conversa em viewport 1440px → painel deve estar aberto na primeira vez.
- Clicar no botão flutuante `i-lucide-user` → painel fecha; clicar de novo → reabre.
- Clicar no nome do contato no header → toggla também (handler já em `ConversationHeader.vue:44-47`).

---

## B2 — Registrar `VoiceCallButton` em `ContactInfo` (P0)

**Sintoma**
Console emite `[Vue warn]: Failed to resolve component: VoiceCallButton` em loop. No painel de contato, o botão "Chamada" (entre "Nova Mensagem" e "Editar Contato") não renderiza — fica como custom element vazio (`<voicecallbutton ...></voicecallbutton>`).

**Causa raiz**
`app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` usa `<VoiceCallButton>` no template (linha 263) mas:
- não tem `import` do componente;
- não está em `components: { ... }` (linhas 24-32).
- O comentário `/* eslint-disable vue/no-undef-components */` na linha 2 confirma que alguém sabia mas suprimiu o lint.

**Correção**
Adicionar:
```js
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
// ...
components: {
  ContactInfoRow,
  EditContact,
  Thumbnail,
  ComposeConversation,
  SocialIcons,
  ContactMergeModal,
  ExportConversationModal,
  VoiceCallButton,
},
```
E remover o `eslint-disable` da linha 2.

**Arquivos**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`

**Validação**
- Recarregar uma conversa → botão "Chamada" (telefone) deve aparecer entre "Nova Mensagem" e "Editar Contato" no grid de 5 ações.
- Console limpo (sem warning de resolve).

---

## B3 — Reações `+` sobrepondo borda do bubble (P1)

**Sintoma**
O botão "+" para abrir o picker de emojis fica posicionado em cima do canto inferior direito do bubble, criando sobreposição visual. Pior: o `hover:opacity-100` é do próprio botão, então em estado normal ele está invisível e o usuário não tem como saber que existe.

**Causa raiz**
`app/javascript/dashboard/components-next/message/MessageReactions.vue:69`:
```html
<button class="reaction-trigger absolute top-0 right-0 -translate-y-1/2 translate-x-1/2 ...
               opacity-0 hover:opacity-100 ...">+</button>
```
O wrapper `<div class="relative mt-1">` fica logo abaixo do bubble, e `top-0 -translate-y-1/2` empurra o botão metade para cima — sobrepondo o final do bubble. `Base.vue:143-150` chama o componente com `class="mt-1"` (gap entre bubble e reactions), mas não cria contexto de hover relacionado ao bubble.

**Correção**
1. Em `MessageReactions.vue`: usar o group já existente (`group/bubble` no `Base.vue:105`) para revelar o trigger:
   - Trocar `opacity-0 hover:opacity-100` por `opacity-0 group-hover/bubble:opacity-100 focus-within:opacity-100`.
   - Reposicionar para o canto interno do bubble (não fora). Sugestão: alinhar ao MessageStarToggle (mesma linha externa, lado oposto), ou colocar inline no rodapé do bubble.
2. Em `Base.vue`: mudar a classe `mt-1` do MessageReactions para `mt-0` (eliminar o salto) e considerar mover o componente para DENTRO do bubble (depois do `<slot />` e antes do `<MessageMeta />`) só quando há reactions agregadas. O picker fica fora.

**Implementação proposta**
- Estrutura do `Base.vue`:
  - `<div class="relative group/bubble">`
    - `<div class="bubble">` slot + meta + chips de reactions agregadas (movidas para cá)
    - `<MessageStarToggle absolute top-2 right-2 group-hover/bubble:opacity-100 ...>` (dentro do bubble)
    - `<MessageReactionsPicker absolute top-2 right-10 group-hover/bubble:opacity-100 ...>` (botão `+` dentro do bubble, ao lado da estrela)
- Splitar `MessageReactions.vue` em duas peças seria ideal: `MessageReactionsPicker` (só o `+` e o picker) e `MessageReactionsBar` (só os chips). MAS para minimizar churn, manter um componente só com slot/prop de modo (`mode="picker" | "chips"`).

**Arquivos**
- `app/javascript/dashboard/components-next/message/MessageReactions.vue`
- `app/javascript/dashboard/components-next/message/bubbles/Base.vue`

**Validação**
- Hover em bubble → "+" aparece no canto superior do bubble (mesma altura do star), sem cobrir conteúdo.
- Click em "+" → picker continua abrindo.
- Reagir a um emoji → chip aparece DENTRO do bubble, no rodapé, sem novo overlap.

---

## B4 — Star com `translate-x-full` (P1)

**Sintoma**
Botão de favoritar mensagem fica fora do bubble (à direita ou à esquerda dependendo da orientação). Pode ser cortado por overflow do MessagesView, e a área de hover é difícil de alcançar.

**Causa raiz**
`app/javascript/dashboard/components-next/message/bubbles/Base.vue:135-142`:
```html
<MessageStarToggle ...
  class="absolute top-1 -translate-y-1/2 ..."
  :class="orientation === ORIENTATION.RIGHT
    ? 'left-0 -translate-x-full pl-1'
    : 'right-0 translate-x-full pr-1'" />
```

**Correção**
Posicionar **dentro do bubble**, no canto superior, com fundo translúcido:
```html
<MessageStarToggle ...
  class="absolute top-1.5 opacity-0 group-hover/bubble:opacity-100 focus-within:opacity-100 transition-opacity"
  :class="orientation === ORIENTATION.RIGHT ? 'left-1.5' : 'right-1.5'" />
```
Removendo `translate-x-full` e `-translate-y-1/2`. Ajustar fundo do botão para `bg-n-solid-1/80 backdrop-blur-sm` para não competir com o conteúdo.

**Arquivos**
- `app/javascript/dashboard/components-next/message/bubbles/Base.vue` (linhas 135-142)
- `app/javascript/dashboard/components-next/message/MessageStarToggle.vue` (ajustar bg do botão)

**Validação**
- Hover em qualquer bubble → estrela aparece no canto superior (esquerdo se mensagem do agente, direito se do contato), claramente dentro do bubble.
- Click ativa/desativa a estrela com optimistic update.

---

## B5 — Remover sparkle duplicado do header (P1)

**Sintoma**
Header da conversa tem botão sparkle (`i-lucide-sparkles`) que abre o Copilot — função idêntica ao botão flutuante captain (`i-woot-captain`) do `SidepanelSwitch`. Dois caminhos para a mesma ação.

**Decisão Walisson**
Manter o **flutuante captain**; remover o sparkle do header.

**Causa raiz**
`app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue:446-453`.

**Correção**
Remover o bloco `<ButtonV4 ... icon="i-lucide-sparkles" ... @click="toggleCopilotPanel" />`. Limpar imports não usados (`toggleCopilotPanel` se for o único caller).

**Arquivos**
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`

**Validação**
- Header da conversa tem só: status actions, SLA, search (lupa), MoreActions (3-dots). Sem sparkle.
- Botão captain flutuante continua abrindo o painel Copilot.

---

## B6 — Esconder banner permanente de assinatura (P1)

**Sintoma**
Texto "A assinatura da mensagem não está configurada. Por favor, configure-a nas configurações do perfil. Clique aqui para atualizar" aparece sempre acima do reply box. WAHA já injeta assinatura externa, então a feature interna de signature não é usada.

**Decisão Walisson**
Manter o **componente funcional** (não apagar `MessageSignatureMissingAlert.vue` nem o getter `getMessageSignature` etc). Só não exibir mais o banner.

**Causa raiz**
`app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:1769-1776` renderiza `<MessageSignatureMissingAlert>` quando `isSignatureEnabledForInbox && !isSignatureAvailable && isDefaultEditorMode`. Como o WAHA channel tem signature enabled mas o usuário não configurou no perfil interno, o banner sempre aparece.

**Correção**
Remover apenas o trecho `<MessageSignatureMissingAlert v-if="..." class="mb-2" />` do template em `ReplyBox.vue:1769-1776`. Manter:
- O `import MessageSignatureMissingAlert from './MessageSignatureMissingAlert.vue'` (linha 18) — pode ficar; não causa overhead em runtime se não renderizar.
- O componente em `components: { ... MessageSignatureMissingAlert }` (linha 98) — idem.
- O arquivo `MessageSignatureMissingAlert.vue` em si.
- Os getters/store relacionados.

> **Alternativa mais limpa (opcional):** trocar a condição para `false` ou para um feature flag tipo `isFeatureEnabledonAccount(currentAccount.id, 'message_signature_alert')` — assim qualquer cliente que QUEIRA o aviso pode reativar via flag. Recomendo seguir o caminho simples (apagar o uso) e abrir flag depois se outro cliente pedir.

**Arquivos**
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`

**Validação**
- Abrir uma conversa, no reply box não deve mais aparecer o banner.
- Funcionalidade de assinatura no Profile Settings continua intacta (clicar em "Configurar assinatura" no perfil ainda funciona).

---

## B7 — `DateSeparator` aceitar `Date` (P2)

**Sintoma**
Console emite `[Vue warn]: Invalid prop: type check failed for prop "date". Expected String with value "Tue Feb 10 2026 12:30:13 GMT+0000 (Hora Coordenada Universal)", got Date`.

**Causa raiz**
- `app/javascript/dashboard/components-next/message/MessageList.vue:312-315` passa `:date="new Date(getItemDate(item) * 1000)"` (Date object).
- `app/javascript/shared/components/DateSeparator.vue:5-9` declara `date: { type: String, required: true }`.

**Correção**
Em `DateSeparator.vue`: `type: [String, Date]`. Renderização não quebra porque o `formatDate` helper já aceita ambos via `new Date(this.date)`.

**Arquivos**
- `app/javascript/shared/components/DateSeparator.vue`

**Validação**
- Console sem warnings de DateSeparator.
- Separadores de data (10 de fevereiro de 2026, etc) continuam exibindo corretamente.

---

## B8 — Validar regressão do hover do bubble (P2)

**Sintoma potencial**
Após adicionar wrapper `<div class="relative group/bubble">` no `Base.vue`, o ChatActionsMenu original (chevron "v" que aparece no canto superior do bubble no hover) pode ter perdido referência de hover ou ficado abaixo de overlays.

**Hipótese**
Não há prova ainda de regressão — o "v" foi visto na screenshot `audit_bubble_hover_clip.png`. Mas o z-index das novas camadas (`MessageStarToggle`, `MessageReactions`) pode competir.

**Correção (preventiva)**
Após aplicar B3 + B4, validar visualmente que o "v" continua aparecendo no hover. Se sumir, adicionar `z-10` no wrapper do menu original e `z-0` na camada de star/reactions.

**Validação**
- Hover em bubble → "v" (ChatActionsMenu) aparece como antes.
- Clicar no "v" → menu abre normalmente (Reply, Copy, Translate, Delete, etc).

---

---

## B9 — Galeria lenta + skeleton (P0)

> **Pesquisa 2026 aplicada:** content-visibility CSS dá 7x ganho de render inicial<sup>[web.dev]</sup>; AVIF é ~20% menor que WebP<sup>[tworowstudio]</sup>; skeleton wave L→R é percebido como mais rápido que pulse e que spinner<sup>[NN/g]</sup>; `prefers-reduced-motion` é mandatório para acessibilidade<sup>[Adrian Roselli]</sup>; `loading="lazy"` é nativo e suficiente para below-the-fold, mas LCP precisa `eager + fetchpriority="high"`<sup>[Core Web Vitals]</sup>; Rails ActiveStorage exige `with_attached_file` + `with_all_variant_records` para evitar N+1<sup>[Saeloun, Searls]</sup>.

### Sintoma
`https://chatspx.app/app/accounts/5/gallery` (e `https://hmlchat.simplexsolucoes.com.br/.../gallery`) demora vários segundos pra carregar. Durante a espera só aparece um spinner centralizado (`<span class="i-lucide-loader-2 animate-spin">`). Tela inteira fica em branco até a primeira página chegar — sensação de "travado" em vez de "carregando".

### Causa raiz (frontend + backend)

**Frontend — `app/javascript/dashboard/routes/dashboard/gallery/GalleryPage.vue:184-189`**
```html
<div v-if="uiFlags.isFetching && !records.length" ...>
  <span class="i-lucide-loader-2 animate-spin" />
</div>
```
- Spinner em vez de skeleton (UX percebida pior).
- Tela inteira ocupada por loader, sem indicar a estrutura que vai aparecer.
- Search dispara `gallery/setFilter` → `dispatch('refresh')` → limpa records e mostra spinner novamente. **Toda busca == flash de spinner.**
- Cache em `state.cache` (Map JS em memória) evita re-fetch mas: (i) não persiste entre F5; (ii) refresh hard sempre paga o custo total.

**Frontend — `MediaGrid.vue`**
- Cards `<article>` sem `content-visibility: auto` nem `contain-intrinsic-size` → browser renderiza TODOS os cards no DOM mesmo que estejam fora da viewport.
- `<img loading="lazy" decoding="async" fetchpriority="low">` está OK para below-the-fold, mas falta `width/height` explícitos → CLS quando a imagem carrega.
- Sem `srcset/sizes` → mesma URL servida para thumbnail 200px e fullscreen 1440px.
- Sem `<picture>` AVIF/WebP fallback → JPEGs originais grandes.
- Sem placeholder progressivo (BlurHash, dominant-color, ou srcset com 1px tiny preview).
- Para 5000+ items: DOM cresce indefinidamente após scroll. Sem virtualização.

**Backend — `app/controllers/api/v1/accounts/attachments_controller.rb:13-24`**
```ruby
def index
  base = base_scope.where(file_type: requested_types)
  deduped_ids = deduplicate_documents(base)             # carrega TODOS os IDs em memória
  @attachments = Attachment.where(id: deduped_ids)
                           .includes(...)
                           .reorder(sort_clause)
                           .page(page_param).per(RESULTS_PER_PAGE)
  @attachments_count = @attachments.total_count
end
```
- `deduplicate_documents` faz query com `DISTINCT ON (...)` em **toda a tabela base** e retorna `.map(&:id)` — para 50k attachments, materializa 50k IDs em memória ANTES de paginar. **N+inteiro de I/O**.
- `joins('JOIN active_storage_attachments asa ...')` + `joins('JOIN active_storage_blobs asb ...')` adicionam dois JOINs grandes só para deduplicar.
- `links` action: `Current.account.messages.where('content ~* ?', '\bhttps?://[^\s]+')` — regex **sem índice** em coluna text. Para conta com 100k+ mensagens, faz seq scan completo. **~3-8s só nessa query.**
- `includes` está correto (`{ file_attachment: [:blob] }, { message: [...] }`) — não é o gargalo principal.

### Correção — fases incrementais

#### Fase 1 (15min) — Skeleton + content-visibility (ganho percebido instantâneo)

1. Criar componente `app/javascript/dashboard/routes/dashboard/gallery/components/MediaGridSkeleton.vue`:
   - Mesma grid (`grid-cols-[repeat(auto-fill,minmax(180px,1fr))]`).
   - 12-24 cards skeleton com `aspect-square rounded-2xl bg-n-solid-2 animate-pulse` (ou wave shimmer com gradient deslizante L→R via `@keyframes`).
   - `role="status"` + `aria-busy="true"` + `aria-label="Carregando galeria"` para screen reader (NN/g + Adrian Roselli).
   - `@media (prefers-reduced-motion: reduce) { animation: none }` — fundo estático.
   - Contraste 3:1 mínimo entre skeleton e fundo (WCAG).

2. Equivalentes para outras tabs:
   - `DocumentListSkeleton.vue` (linhas com avatar circular + 2 linhas de texto).
   - `LinkListSkeleton.vue` (cards horizontais com title + url stub).

3. `GalleryPage.vue`: substituir o spinner condicional por:
   ```html
   <MediaGridSkeleton v-if="uiFlags.isFetching && !records.length && tab === 'media'" />
   <DocumentListSkeleton v-else-if="uiFlags.isFetching && !records.length && tab === 'documents'" />
   <LinkListSkeleton v-else-if="uiFlags.isFetching && !records.length" />
   ```

4. `MediaGrid.vue:59` — adicionar `content-visibility: auto` + `contain-intrinsic-size: 0 220px` no `<article>` (220px = altura aproximada com aspect-square 180px + label):
   ```html
   <article
     class="group ... [content-visibility:auto] [contain-intrinsic-size:0_220px]"
   >
   ```
   **Resultado esperado**: render inicial até 7× mais rápido em listas grandes (web.dev).

5. `<img>` no `MediaGrid.vue:70-78`: adicionar `width/height` explícitos para eliminar CLS:
   ```html
   <img
     :src="item.thumbUrl || item.dataUrl"
     :width="item.width || 400"
     :height="item.height || 400"
     :alt="item.filename || ''"
     loading="lazy"
     decoding="async"
     fetchpriority="low"
     class="w-full h-full object-cover ..."
   />
   ```

6. **Não exibir skeleton para refresh causado por search** quando já há records — usar overlay `aria-busy="true"` sobre os existentes, sem clear, padrão "stale-while-revalidate":
   - Em `gallery.js refresh action`: NÃO commitar `SET_RECORDS` com array vazio antes do fetch. Commitar `SET_UI_FLAG isRefreshing: true` e só substituir records quando o novo array chegar.

#### Fase 2 (45min) — Lazy real com IntersectionObserver + skeleton por card

1. Wrapper de imagem `<MediaThumb>` com IntersectionObserver via `useIntersectionObserver` do **VueUse** (já é dependência transitiva — verificar):
   - Estado inicial: skeleton local (mesmo bg do card).
   - Quando entra em viewport (rootMargin 200px): troca para `<img>` com `loading="lazy" decoding="async"`.
   - `onLoad`: fade-in opacity 0→100 em 200ms.
   - `onError`: ícone fallback (i-lucide-image-off).

2. Trocar `loading="lazy"` nativo por essa combinação dá controle fino do skeleton **por imagem** (não bloco inteiro), e permite adicionar BlurHash/dominant-color depois sem refactor.

3. Para a primeira "fileira" visível (primeiros 4-6 cards above-the-fold) — usar `loading="eager"` + `fetchpriority="high"` para LCP:
   ```html
   <img
     :loading="index < 6 ? 'eager' : 'lazy'"
     :fetchpriority="index < 6 ? 'high' : 'low'"
     ...
   />
   ```

#### Fase 3 (1-2h) — Backend optimization (deduplicação + index regex)

1. `attachments_controller#deduplicate_documents`:
   - **Opção A (rápida, sem migration):** trocar `DISTINCT ON + map(&:id)` por subquery deduplicada com `ROW_NUMBER() OVER (PARTITION BY ...)` mantendo paginação no SQL:
     ```ruby
     dedup_sql = base
       .joins('JOIN active_storage_attachments asa ON asa.record_id = attachments.id ...')
       .joins('JOIN active_storage_blobs asb ON asb.id = asa.blob_id')
       .select(Arel.sql(<<~SQL))
         attachments.*,
         ROW_NUMBER() OVER (
           PARTITION BY asb.byte_size, asb.filename, messages.sender_id, messages.sender_type,
                        date_trunc('hour', attachments.created_at)
           ORDER BY attachments.created_at DESC
         ) AS dedup_rn
       SQL
       .to_sql
     @attachments = Attachment
       .from("(#{dedup_sql}) AS attachments")
       .where('dedup_rn = 1')
       .includes(...)
       .reorder(sort_clause)
       .page(page_param).per(RESULTS_PER_PAGE)
     ```
   - **Opção B (longo prazo):** adicionar coluna `dedup_key` (hash de byte_size+filename+sender+hour) populada por trigger ou job, com índice → `Attachment.where(...).distinct_on(:dedup_key)` em <50ms.
   - Manter `with_attached_file` scope ou explícito `includes({ file_attachment: :blob })` para evitar N+1 em representations<sup>[Saeloun, Searls]</sup>.

2. `attachments_controller#links_scope` — substituir regex por:
   - **Opção A (rápida):** índice GIN com pg_trgm:
     ```sql
     CREATE EXTENSION IF NOT EXISTS pg_trgm;
     CREATE INDEX CONCURRENTLY index_messages_on_content_url
       ON messages USING gin (content gin_trgm_ops)
       WHERE content ~* '\bhttps?://[^\s]+';
     ```
   - **Opção B (mais limpa):** já temos coluna `content_attributes` jsonb — extrair URLs no momento da criação e gravar em `content_attributes->>'urls'` como array. Indexar `(content_attributes->'urls')` GIN. Query passa a ser `WHERE content_attributes ? 'urls'`. Migration de backfill.

3. **Cache de página por filtro**:
   - `Rails.cache.fetch("gallery:#{Current.account.id}:#{cache_key}", expires_in: 5.minutes)` envolvendo `deduped_ids + meta`. Invalidar em `Attachment` after_create/destroy do account.

4. Adicionar **`Cache-Control: private, max-age=60`** nos endpoints de attachments → CDN/browser cache.

5. Considerar gerar variants menores via `image_processing` no upload:
   - thumb_400.webp, thumb_800.webp, thumb_400.avif, thumb_800.avif.
   - Servir via `srcset/sizes` no `<img>` ou `<picture>` no frontend.
   - **Nota:** isso é refactor maior; só fazer se Fase 1+2 não derem performance suficiente.

### Arquivos a modificar (B9)

**Frontend (Fase 1+2):**
- `app/javascript/dashboard/routes/dashboard/gallery/GalleryPage.vue` (substituir spinner)
- `app/javascript/dashboard/routes/dashboard/gallery/components/MediaGrid.vue` (content-visibility, width/height, MediaThumb wrapper)
- **NOVO:** `app/javascript/dashboard/routes/dashboard/gallery/components/MediaGridSkeleton.vue`
- **NOVO:** `app/javascript/dashboard/routes/dashboard/gallery/components/DocumentListSkeleton.vue`
- **NOVO:** `app/javascript/dashboard/routes/dashboard/gallery/components/LinkListSkeleton.vue`
- **NOVO:** `app/javascript/dashboard/routes/dashboard/gallery/components/MediaThumb.vue` (Fase 2)
- `app/javascript/dashboard/store/modules/gallery.js` (refresh action stale-while-revalidate)
- `app/javascript/dashboard/i18n/locale/{en,pt_BR}/gallery.json` (chave `LOADING` para aria-label)

**Backend (Fase 3):**
- `app/controllers/api/v1/accounts/attachments_controller.rb`
- **NOVO:** `db/migrate/YYYYMMDDHHMMSS_add_url_index_to_messages.rb` (Opção A)
- ou `db/migrate/YYYYMMDDHHMMSS_extract_urls_from_messages.rb` + backfill job (Opção B)

### Validação (B9)

- **Lighthouse mobile**: LCP < 2.5s, CLS < 0.1, TBT < 200ms na rota `/gallery`.
- **Chrome DevTools Performance tab**: render inicial < 500ms até primeiro paint do skeleton; primeiro paint do conteúdo real < 1.5s para 30 items.
- **Manual**: F5 na galeria → skeleton aparece **instantâneo** (sem flash branco) → conteúdo substitui em fade-in.
- **Search**: digitar no campo → grid existente fica com `aria-busy=true` (overlay sutil) sem clear → resultado novo entra em fade-in.
- **Scroll**: 1000+ items → memória estável (não cresce indefinidamente). DevTools "Layers" mostra apenas itens visíveis renderizados.
- **prefers-reduced-motion**: skeleton sem animação shimmer, fundo estático.
- **Backend** (`bullet` gem ou `pg_stat_statements`): query `attachments#index` < 200ms para conta com 50k attachments. `links` action < 100ms com índice.

### Critérios de aceitação (B9)

- [ ] Skeleton visível em **todas** as tabs (media/documents/links) durante fetch inicial.
- [ ] Skeleton respeita `prefers-reduced-motion`.
- [ ] `role="status"` + `aria-busy` + screen reader announce "Carregando galeria" → "Galeria carregada".
- [ ] Cards com `content-visibility: auto` + `contain-intrinsic-size`.
- [ ] Imagens com `width/height` (sem CLS).
- [ ] First paint < 500ms; LCP < 2.5s na rota.
- [ ] Search não causa flash em branco.
- [ ] Backend: query index < 200ms com >50k attachments (Fase 3).

---

## Plano de execução

| # | Ação | Arquivos | Tempo | Bloqueia |
|---|------|----------|-------|----------|
| 1 | B1 — Remover força de "sempre aberto" + restaurar toggle flutuante | ConversationView.vue, SidepanelSwitch.vue | 8min | — |
| 2 | B2 — Registrar VoiceCallButton | ContactInfo.vue | 2min | — |
| 3 | B5 — Remover sparkle duplicado do header | ConversationHeader.vue | 2min | — |
| 4 | B6 — Esconder banner de assinatura | ReplyBox.vue | 1min | — |
| 5 | B7 — Aceitar Date no DateSeparator | DateSeparator.vue | 1min | — |
| 6 | B3 + B4 — Reposicionar reactions e star dentro do bubble | MessageReactions.vue, Base.vue, MessageStarToggle.vue | 12min | — |
| 7 | B8 — Validação visual do hover original | — | 5min | depois de #6 |
| 8 | Build com cache-bust + restart `chatwoot.target` | — | 4min | depois de tudo |
| 9 | Smoke Playwright logado + screenshots de cada correção | scripts/audit_ui_after.mjs | 5min | depois de #8 |
| 10 | Reportar resultado em pt-BR com screenshots | — | 2min | depois de #9 |
| 11 | **B9 Fase 1** — skeleton + content-visibility + width/height + stale-while-revalidate | GalleryPage.vue, MediaGrid.vue, +3 Skeleton.vue novos, gallery.js, gallery.json | 15min | — |
| 12 | **B9 Fase 2** — MediaThumb com IntersectionObserver + LCP eager nos primeiros cards | MediaThumb.vue (novo), MediaGrid.vue | 45min | depois de #11 |
| 13 | **B9 Fase 3** — backend dedup com window function + index regex links + cache 5min | attachments_controller.rb, migration nova | 1-2h | depois de #11 |
| 14 | Lighthouse + smoke Playwright + Chrome DevTools profile | scripts/audit_gallery.mjs | 10min | depois de #13 |

**Total B1-B8:** ~42min. **Total com B9 completo (Fase 1+2+3):** ~3-4h.

> **Recomendação de entrega incremental:** B1-B8 + B9 Fase 1 (+15min) é o pacote "ganho percebido imediato" — pode ir para validação do Walisson. B9 Fase 2-3 fazer depois como performance second-pass se necessário.

## Critérios de aceitação

- [ ] Painel direito de Contatos fecha ao clicar no toggle flutuante; reabre normalmente.
- [ ] Botão "Chamada" (VoiceCallButton) renderiza no painel; console sem warning de resolve.
- [ ] Botão "+" de reactions só aparece no hover do bubble, dentro dele, sem cobrir conteúdo.
- [ ] Star renderiza dentro do bubble, no canto superior, no hover.
- [ ] Header da conversa não tem mais sparkle.
- [ ] Reply box não exibe banner de assinatura.
- [ ] Console limpo de warnings (DateSeparator, VoiceCallButton).
- [ ] ChatActionsMenu (chevron "v") continua funcionando.
- [ ] Build verde, restart sem erro, HTTP 200 na homepage.
- [ ] Screenshots de cada correção anexados ao report final.

## Plano de rollback

Working tree atual tem 61 arquivos modificados sem commit. Se algum dos 8 fixes acima quebrar produção:

```bash
git restore app/javascript/dashboard/...  # arquivos específicos
sudo systemctl restart chatwoot.target
```

Não há risco de regressão de banco — as correções são frontend-only (exceto que B2 mexe num componente que já existia mas estava quebrado).

## Próximos passos pós-fix

1. Validação manual do Walisson em hmlchat.
2. Se aprovado: commit Conventional contra `homologacao` (a serem agrupados com o redesign workspace-v2).
3. Atualizar `vault/01-Permanentes/Chat SPX.md` com a lição aprendida (uso de `eslint-disable` mascarando bug real, regra de viewport hardcoded em vez de UISetting, regex sem índice).

---

## Referências (best practices 2026 pesquisadas)

**Skeleton & UX**
- [NN/g — Skeleton Screens 101](https://www.nngroup.com/articles/skeleton-screens/) — wave L→R supera pulse e spinner em percepção de velocidade.
- [Adrian Roselli — More Accessible Skeletons](https://adrianroselli.com/2020/11/more-accessible-skeletons.html) — `role="status"`, `aria-busy`, screen reader announce.
- [LogRocket — Skeleton loading screen design](https://blog.logrocket.com/ux-design/skeleton-loading-screen-design/)
- [shefali.dev — Skeleton Screens: Why They Feel Faster](https://shefali.dev/skeleton-screens/)

**Performance — content-visibility**
- [web.dev — content-visibility: the new CSS property that boosts your rendering performance](https://web.dev/articles/content-visibility) — 7× ganho de render inicial.
- [DebugBear — Faster Rendering with the content-visibility CSS Property](https://www.debugbear.com/blog/content-visibility-api)
- [MDN — content-visibility](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/content-visibility)

**Imagens responsivas 2026**
- [Responsive Images Cheatsheet — srcset, sizes, picture in 2026](https://www.imagetourl.cloud/guides/responsive-images-cheatsheet/) — AVIF first, WebP, JPEG fallback; LCP eager + fetchpriority high.
- [Image Optimization in 2026: WebP/AVIF, DPR, and Lazy-Loading — Two Row Studio](https://tworowstudio.com/image-optimization-2026/) — AVIF ~20% menor que WebP.
- [Optimize images for Core Web Vitals](https://www.corewebvitals.io/pagespeed/optimize-images-for-core-web-vitals)
- [Optimize Web Images: A Complete Guide to WebP & AVIF (mar/2026)](https://www.mohtaweb.com/2026/03/optimize-web-images-webp-avif.html)

**IntersectionObserver Vue 3**
- [VueUse — useIntersectionObserver](https://vueuse.org/core/useintersectionobserver/) — composable nativo, baixo overhead.
- [CSS-Tricks — Lazy Loading Images with Vue.js Directives and Intersection Observer](https://css-tricks.com/lazy-loading-images-with-vue-js-directives-and-intersection-observer/)
- [DigitalOcean — Lazy Image Component Using the Intersection Observer API in Vue.js](https://www.digitalocean.com/community/tutorials/vuejs-lazy-image)

**Backend — Rails ActiveStorage N+1**
- [Saeloun Blog — Eager loading Active Storage models to avoid N+1](https://blog.saeloun.com/2020/03/06/eagerload-active-storage-models/) — `with_attached_file`, `with_all_variant_records`.
- [Justin Searls — What one must pass to includes() to include Active Storage attachments](https://justin.searls.co/posts/what-one-must-pass-to-includes-to-include-active-storage-attachments/)
- [a-chacon — Avoiding the problem of N+1 queries with ActiveStorage](https://a-chacon.com/en/on%20rails/2023/10/18/prevent-n1-active-storage.html)
- [Rails Guide — Active Storage Overview](https://edgeguides.rubyonrails.org/active_storage_overview.html)
