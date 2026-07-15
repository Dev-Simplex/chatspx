# Restaurar funções (anexo, áudio, reações, reply, editar/apagar, menções) no redesign do chat interno

> Prompt de implementação autossuficiente — todos os caminhos, pontos de inserção, contratos e tokens estão embutidos. Gerado em 2026-07-07 a partir de auditoria em 3 frentes (UI da página antiga, contrato store/backend, mapa dos componentes do redesign).

## Objetivo
A página no ar do chat interno é o **redesign** (`app/javascript/dashboard/routes/dashboard/internalChat/pages/InternalChatRedesign.vue` + `components/redesign/*`). Ele é visualmente superior mas **regrediu em funcionalidade**: não envia/exibe anexos, não grava áudio, não tem reações, reply, editar/apagar nem inbox de menções. **Backend, store Vuex e API JÁ suportam tudo** — só falta a camada visual. A tarefa é **portar essas funções da página antiga (`InternalChatIndex.vue`) para os componentes do redesign**, sem inventar backend.

## Restrição inviolável — NÃO regredir o redesign
- **ADICIONE** aos componentes existentes; **não** substitua nem reescreva do zero. Preserve o layout, a tela vazia nova (logo + "Nova conversa"), o composer atual, os popovers de compose/notificação, tudo que já está lá.
- Mantenha o padrão do redesign: **strings PT hard-coded** com `<!-- eslint-disable vue/no-bare-strings-in-template -->` (não migrar para i18n `t('INTERNAL_CHAT.*')` — o redesign não usa).
- **Não** toque em backend/rotas/model/store/API — eles estão prontos e corretos. Se achar que precisa, pare e reavalie: quase certamente não precisa.
- Inputs custom **sempre** com a classe `reset-base` (senão o padding global do Tailwind vence — ver memória `global-input-padding-reset-base`).

## Contexto — o que já está pronto (não recriar)
**Store** `app/javascript/dashboard/store/modules/internalChat.js` (actions prontas):
- `sendMessage({ channelId, content, attachments=[], mentionedUserIds=[], replyToId=null, sharedConversationId=null, echoId=null })` — **já é multipart**; passe `File` crus no array `attachments`. Insere bolha otimista `status:'progress'` se `echoId` presente; erro → `status:'failed'`. (linhas 178-228)
- `editMessage({ channelId, messageId, content })` (330) · `deleteMessage({ channelId, messageId })` (339, soft-delete) · `reactToMessage({ channelId, messageId, emoji })` (344, toggle) · `fetchMentions()` (135) · `searchMessages(q)` (min 2 chars, 148) · `sendTyping` (354).
- Getters: `getMentions` (47), `getSearchResults` (48).

**API** `app/javascript/dashboard/api/internalChat.js` — `sendMessage` monta `FormData` com `attachments[]`, `mentioned_user_ids[]`, `reply_to_id`, `echo_id` (65-73). `editMessage`/`deleteMessage`/`reactToMessage`/`getMentions`/`searchMessages` prontos.

**Cada mensagem do store já traz**: `id`, `echo_id`, `content` (null se deleted), `attachments:[{id,filename,url}]`, `reactions:{emoji:[userId,...]}`, `reply_to:{id,user_name,content}`, `edited`(bool), `deleted`(bool), `mentioned_user_ids`, `status`(`progress`/`failed`), `user:{id,name,avatar_url}`, `created_at`(epoch).

**Shapes importantes**:
- Respostas de create/edit/delete/react têm o **mesmo shape** de mensagem → sempre `UPDATE_MESSAGE`/`APPEND_MESSAGE` com o objeto retornado.
- `mentions`/`search` retornam shape **diferente** (`_search_result`: `{id, internal_channel_id, channel_type, channel_title, content, created_at, user}`) — são resultados navegáveis, não mensagens.
- **Delete é soft**: a msg volta com `deleted:true, content:null, attachments:[]` → renderize "mensagem apagada", **não** remova da lista.

## Contrato backend (referência — já implementado)
- `POST /internal_channels/{id}/internal_messages` — create; lê `content`, `attachments[]` (multipart), `mentioned_user_ids`, `reply_to_id`, `shared_conversation_id`, `echo_id`. Guard `channel_member?` (403). Sem strong params, sem `content_attributes`.
- `PATCH .../internal_messages/{mid}` — edit (autor-only, seta `edited_at`). `DELETE .../{mid}` — soft-delete (autor OU admin). `POST .../{mid}/react` — toggle emoji (membro).
- `GET /internal_channels/mentions` (GIN `mentioned_user_ids @>`) · `GET /internal_channels/search?q=` (ILIKE, min 2).
- Model `internal_message.rb`: `has_many_attached :attachments`, `MAX_ATTACHMENT_SIZE=100.megabytes` (validação → 422), `belongs_to :reply_to` (FK `reply_to_id`), coluna jsonb `reactions`, `edited_at`, `deleted_at` (`soft_delete!` zera content/attachments), `echo_id` transiente.

## Plano de execução (nesta ordem)

### FASE 0 — Desbloqueador (fazer PRIMEIRO)
**`InternalChatRedesign.vue`, `threadItems` (linhas ~152-177):** hoje ele **achata** a mensagem (`{content, time, mine, senderName, avatarSrc, read}`). Isso impede o bubble de ver anexos/reações/reply/edited/deleted. **Enriqueça o item com os campos crus**: `id`, `attachments`, `reactions`, `reply_to`, `edited`, `deleted`, `mentioned_user_ids`, `status`. Sem isso, nada da Fase 2 tem dado. (o pai já importa `getUuid` e já lê `threadAttachments` para o InfoPanel.)

### FASE 1 — Composer (`components/redesign/ChatComposer.vue`)
Hoje só texto+emoji, `emit('send', content)`. Mude para `emit('send', { content, attachments, replyToId })` e trate no pai.
- **Anexo**: botão `i-lucide-paperclip` + `<input ref type="file" multiple class="hidden">`. Copie de `InternalChatIndex.vue:1964-1985`; handlers `onPickFile`(561), `onFilesSelected`(562-578, usa `checkFileSizeLimit`/`HARD_MAXIMUM_FILE_UPLOAD_SIZE` de `shared/helpers/FileHelper`), `removeFile`(579).
- **Preview de anexos (chips)** acima do pill: fonte `1903-1913`.
- **Barra "respondendo a X"** acima do preview: fonte `1883-1901` (`bg-n-alpha-1 border-l-2 border-n-brand rounded-r-lg`, ícone `i-lucide-reply`, nome+trecho, botão `i-lucide-x` → emite cancel). Receba `defineProps({ replyingTo })`.
- **Áudio (feature NOVA — não existe na página antiga)**: botão `i-lucide-mic`; reuse `dashboard/components/widgets/WootWriter/AudioRecorder.vue` (emits `recordStart`/`finishRecord {blob}`/`recordError`); jogue o `blob` no array `attachments`.
- **`send()`**: permita enviar só-anexo (`if (!content && !attachments.length) return`). Fonte `641-668`.

### FASE 2 — Bolha (`components/redesign/MessageBubble.vue`)
Adicione `defineEmits(['react','edit','delete','reply','openMenu','retry'])`. Ponha `class="group"` no wrapper externo (para o hover do menu).
- **Citação de reply** antes do `<p>`: fonte `1672-1687` (click → scroll até a msg).
- **"editado"** dentro do `<p>`: fonte `1724-1728` (`text-[10px] opacity-60`).
- **"apagada"** via `message.deleted` (itálico, `i-lucide-ban`): fonte `1520-1527`.
- **Anexos** após o `<p>`: fonte `1731-1765` (imagem `max-w-[220px] rounded-lg`; arquivo `i-lucide-paperclip`+filename; áudio → detectar por extensão e usar `<audio controls>` ou `components-next/message/bubbles/Audio.vue`).
- **Chips de reação** abaixo do balão: fonte `1797-1817`; lógica `reactionEntries`(770)/`iReacted`(771); destaque `border-n-brand bg-n-brand/10`.
- **Menu de ação (⋯) + picker de reação** dentro do wrapper `relative`: fonte `1571-1647`. Botão `i-lucide-ellipsis` `opacity-0 group-hover:opacity-100 focus:opacity-100`; toolbar `rounded-full shadow-lg` com Responder/Reagir/Editar(só minha)/Apagar(só minha); picker de reação = array fixo `QUICK_EMOJIS = ['👍','❤️','😂','🎉','✅','🙏']` (687); backdrop click-outside `fixed inset-0 z-10`. Long-press mobile: `@touchstart`(450ms)/`@touchend`/`@contextmenu.prevent` (704-708, 1564-1567).
- **Editar inline**: textarea com `@keydown.enter.exact.prevent` salvar / `@keydown.esc` cancelar: fonte `1529-1552`.

### FASE 3 — Thread (`components/redesign/MessageThread.vue`)
Repasse os emits do bubble ao pai (`@react/@edit/@delete/@reply/@retry` na linha do `<MessageBubble>` ~58). Mantenha o estado de menu/picker **local ao bubble** (mais limpo que centralizar).

### FASE 4 — Menções + busca de conteúdo
- **Inbox de menções**: botão `i-lucide-at-sign`. **Lugar recomendado: `ChatSidebar.vue`** (sempre montada; menções são cross-channel, `fetchMentions` não é por canal), no header da sidebar (~109-129, padrão do botão `i-lucide-bell`) emitindo `@open-mentions`. O pai (`InternalChatRedesign.vue`) abre um painel/aside com a lista, dispara `fetchMentions()`, itera `getMentions` (cada item: `channel_title`+hora / `user.name`: `content`; click → abre o canal). Fonte `489-515`, `1330-1415`.
- **Busca de conteúdo**: a busca da sidebar hoje só filtra **nomes** localmente. Para busca cross-channel real, ligue ao `searchMessages(q)` (debounce 300ms, min 2 chars) exibindo `getSearchResults` no mesmo painel. Reuse o padrão de painel flutuante que a sidebar já tem (compose/settings).

### FASE 5 — Pai (`InternalChatRedesign.vue`) — handlers
`onSend({content,attachments,replyToId,mentionedUserIds})` → `sendMessage` com `echoId=getUuid()`; `onReact/onEdit/onDelete/onReply/onRetry/openMentions` → dispatches correspondentes (fontes `758-768`, `726`, `744`, `776-783`, `672-680`, `488-490`). `replyingTo` = novo `ref` passado como prop ao composer. Reuse o modal de confirmação já existente (`showClearConfirm`, ~467-497) para o Apagar, ou a confirmação inline da fonte `1649-1670`.

## Tabela — arquivo → função → ponto de inserção → fonte a copiar
| Arquivo alvo (redesign) | Função | Linha alvo | Fonte (InternalChatIndex.vue) |
|---|---|---|---|
| InternalChatRedesign.vue | **Enriquecer `threadItems`** (pré-req) | 152-177 | — |
| ChatComposer.vue | Botão anexo + input file | ~68 | 1964-1985; handlers 561-579 |
| ChatComposer.vue | Preview de anexos (chips) | antes de 48 | 1903-1913 |
| ChatComposer.vue | Barra "respondendo a X" | antes de 48 | 1883-1901 |
| ChatComposer.vue | Botão/gravação de áudio | ~68 | *novo* — `WootWriter/AudioRecorder.vue` |
| ChatComposer.vue | `send()` c/ anexo+reply | 34-41 | 641-668 |
| MessageBubble.vue | Emits de ação + `group` no wrapper | após 6 / linha 11 | — |
| MessageBubble.vue | Citação de reply | antes de 30 | 1672-1687 |
| MessageBubble.vue | Anexos (img/arq/áudio) | após 30 | 1731-1765 |
| MessageBubble.vue | Indicador "editado" | dentro do `<p>` ~30 | 1724-1728 |
| MessageBubble.vue | Estado "apagada" | 30 (via `message.deleted`) | 1520-1527 |
| MessageBubble.vue | Chips de reação | após 42 | 1797-1817 |
| MessageBubble.vue | Menu ⋯ + picker de reação | dentro de 23 | 1571-1647 |
| MessageBubble.vue | Editar inline | — | 1529-1552 |
| MessageThread.vue | Re-emitir eventos do bubble | 58 (+ emits após 7) | — |
| MessageThread.vue | Menu/long-press por msg | 35 ou no bubble | 1564-1567 |
| ChatSidebar.vue | Botão/painel de menções | header ~109-129 | 489-515, 1330-1415 |
| ChatSidebar.vue | Busca global de conteúdo | 285-298 | `searchMessages` (store 148) |
| InternalChatRedesign.vue | onSend/onReact/onEdit/onDelete/onReply/onRetry/openMentions | ~212-298 | 641-680, 758-768, 726, 744, 776-783, 488-490 |

## Design tokens a respeitar (para não destoar)
- Marca/superfícies: `bg-n-brand`/`text-n-brand`, `bg-n-solid-1`, `bg-n-alpha-1`(sutil)/`-2`(forte), `border-n-weak`, overlay `bg-n-alpha-black2`. Texto `text-n-slate-12/11/10/9`. Destrutivo `text-n-ruby-11`, `hover:bg-n-ruby-3`.
- Balões: minhas `bg-n-brand text-white rounded-br-md`; outras `bg-n-alpha-2 text-n-slate-12 rounded-bl-md`. Reação ativa `border-n-brand bg-n-brand/10`. Mention `bg-n-brand/15 text-n-brand`.
- Ícones: `<span class="i-lucide-*">` (nunca `<svg>`). Botão-ícone: `inline-flex items-center justify-center w-9 h-9 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12`; ativo `text-n-brand bg-n-alpha-2`.
- Raios: composer `rounded-2xl`, painéis `rounded-xl`, chips `rounded-full`, botões pequenos `rounded-lg`. Menu flutuante: backdrop `fixed inset-0 z-10` + painel `absolute z-20 border shadow-lg rounded-xl bg-n-solid-1 border-n-weak`.
- Reply bar: `bg-n-alpha-1 border-l-2 border-n-brand rounded-r-lg`.

## Componentes reusáveis (não recriar)
`components-next/avatar/Avatar.vue` · `shared/components/emoji/EmojiInput.vue` (já no composer) · `WootWriter/AudioRecorder.vue` (áudio) · `components-next/message/bubbles/Audio.vue` (player) · `shared/helpers/FileHelper` (`checkFileSizeLimit`, `HARD_MAXIMUM_FILE_UPLOAD_SIZE=100`) · `widget/helpers/uuid` (`getUuid`, já importado no pai).

## Verificação (staging `nicolas.chatspx.app`)
1. `RAILS_ENV=production NODE_OPTIONS="--max-old-space-size=8192" bundle exec rails assets:precompile` + `sudo /bin/systemctl restart chatwoot.target`.
2. QA com Playwright, 2 agentes (elevar RT-A a admin se precisar de auditoria, depois reverter). Confirmar, um a um: enviar arquivo (progresso→check), receber/ver anexo, gravar/enviar áudio, reagir (chip + contador + toggle), responder (barra + citação + scroll), editar (badge "editado"), apagar (vira "mensagem apagada" nos dois lados, tempo real), inbox de menções lista e abre o canal, busca por conteúdo retorna. Verificar **dark mode**.
3. Não commitar `public/version.json`. `eslint --fix` nos arquivos tocados; `check_vue_template_refs` limpo. Commits atômicos por fase, com `Co-Authored-By: Claude Opus 4.8`.

## Cuidados que já custaram bug antes
- `threadItems` achatado é o desbloqueador — faça a Fase 0 antes de tudo.
- `echo_id` é obrigatório para o estado otimista/retry; sem ele a msg só aparece após o HTTP.
- Delete é soft — renderize, não remova.
- `reset-base` em todo input custom.
- Enviar só-anexo (sem texto) deve funcionar.
- `sendMessage` já é multipart — passe `File` crus, não pré-serialize para signed_id.
