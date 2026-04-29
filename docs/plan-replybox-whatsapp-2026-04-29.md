# Plano — ReplyBox WhatsApp-fiel (escopo completo)

> **Data:** 2026-04-29
> **Pedido por:** Walisson
> **Objetivo:** Redesenhar a área de digitação (ReplyBox) do ChatSPX para ficar visualmente o mais idêntico possível ao WhatsApp Web, mantendo todas as features do Chatwoot (Reply/Private toggle, Copilot IA, anexos múltiplos, canned responses, signature, bubble menu de formatação).
> **Validação:** Playwright comparando before/after pixel-a-pixel + checklist visual com referência WhatsApp Web 2025/2026.

---

## 1. Estado atual (medido via Playwright em hmlchat 2026-04-29)

**Altura medida:** 209px (estado idle, viewport 1600x900)
**Estrutura:** 3 camadas verticais

```
┌─────────────────────────────────────────────────────────────── ~52px ──┐
│ [Responder | Mensagem Privada]                       ✨Copilot  ⛶Expand │
├──────────────────────────────────────────────────────────────  ~80px ──┤
│ ┌─────────────────────────────────────────────────────────────────────┐ │
│ │ Shift + enter para nova linha. Digite '/' para selecionar Resposta.  │ │
│ │                                                                      │ │
│ └─────────────────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────  ~52px ──┤
│ 😀  ➕                                              🎤   ┌──────────┐ │
│                                                          │ ➤ Enviar │ │
│                                                          └──────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

**Estado modo Privada** (ainda mais alto, fundo amarelo):
- Mesma estrutura, mas com `bg-n-amber-3/40` ou similar
- Placeholder: "A mensagem será visível apenas para agentes"

**Problemas identificados:**

| # | Problema | Impacto vs WhatsApp |
|---|----------|---------------------|
| A1 | TopPanel ocupa 52px só pro toggle | WhatsApp não tem toggle, só input direto |
| A2 | Botões Copilot ✨ + Expand ⛶ no canto, vazio no meio | WhatsApp não tem isso visível ocioso |
| B1 | ProseMirror menubar (Bold/Italic/Undo/Redo) sempre presente | WhatsApp não mostra menu de formatação |
| B2 | Placeholder verbose | WhatsApp usa só "Type a message" / "Mensagem" |
| C1 | Input com border + sombra forte, fundo branco isolado | WhatsApp: pill cinza claro, integrado no flow |
| C2 | Botão Send retangular com label "Enviar (↵)" | WhatsApp: circular verde, ícone só |
| C3 | Mic separado do input | WhatsApp: mic alterna no MESMO botão Send (mic se vazio, send se texto) |
| D1 | Outlines `outline-1 outline` em todos os botões | WhatsApp: sem outlines, só hover bg sutil |
| D2 | Cores `bg-n-slate-9/10` cinza neutro | WhatsApp tem palette própria (#F0F2F5 / #202C33) |
| E1 | 209px de altura | WhatsApp: ~62px |

---

## 2. Estado-alvo (WhatsApp Web 2025/2026)

**Altura-alvo:** 60-65px estado idle. Cresce só quando `Privada` ativa, anexos pendentes, ou Copilot expandido.

```
┌──────────────────────────────────────────────────────────────  ~62px ──┐
│  😀  ➕  │  Mensagem...                              │  🎤 / ➤        │
│  └─┬─┘   │  ↑ pill bg #FFF (light) ou #2A3942 (dark) │  └─┬─┘         │
│    └ size-9 rounded-full hover:bg-alpha               │     └ size-10  │
│       gap-1 entre eles                                       circular  │
│                                                              verde     │
└─────────────────────────────────────────────────────────────────────────┘
                                                  ↑ alterna mic↔send
                                                    via hasMessageContent
```

**Linhas opcionais acima do composer** (só quando ativas):

```
┌─ Quote/Reply preview (se respondendo a msg) ────────────────────────────┐
│ ┃ Walisson · "ola"                                          [X fechar] │
└────────────────────────────────────────────────────────────────────────┘
┌─ Anexos pendentes (se uploads selecionados) ────────────────────────────┐
│ [thumb1.png X] [thumb2.pdf X] [+ add]                                   │
└────────────────────────────────────────────────────────────────────────┘
┌─ Banner de modo Privada (chip amarelo slim) ────────────────────────────┐
│ 🔒 Modo nota privada · clique pra trocar p/ resposta                    │
└────────────────────────────────────────────────────────────────────────┘
[ COMPOSER ATÉ AQUI ]
```

**Bubble menu de formatação** (aparece flutuante ao selecionar texto):
```
                ┌──────────────────────────────────┐
                │ B  𝐼  ̲U  S  </>  link             │
                └──────────────────────────────────┘
        ↑ surge ao destacar texto, some ao deselecionar
```

---

## 3. Princípios de design

1. **WhatsApp-first em estado ocioso** — sem texto, sem anexo, modo Reply: parece WhatsApp 100%
2. **Chatwoot-features on-demand** — Copilot, Privada, formatação aparecem quando o agente precisa
3. **Reduzir altura vertical** de 209px → 62px no estado base (compressão ~70%)
4. **Sem outlines redundantes** — bg cinza unificado, hover alpha sutil
5. **Não remover features** — só reorganizar visualmente; toda funcionalidade preservada
6. **Email inbox = exceção** — modo email mantém ReplyEmailHead atual (não cabe no padrão WhatsApp)

---

## 4. Decisões assumidas (revisar com Walisson)

Estas são as decisões que assumi ao redigir o plano. Walisson pode mudar qualquer uma:

| # | Decisão | Padrão assumido | Alternativa |
|---|---------|-----------------|-------------|
| **D1** | Toggle Reply/Privada | Chip slim amarelo SÓ visível em modo Privada (default Reply é silent). Switch via shortcut `Ctrl+Shift+P` ou clique no chip | (a) Sempre visível como pill compacta (b) Esconder dentro do menu kebab (`⋮`) |
| **D2** | Botão Copilot ✨ | Ícone separado roxo no canto direito do input pill (size-7), ao lado do mic/send | Mover pra dentro do bubble menu de formatação |
| **D3** | Botão Expand ⛶ | Ícone size-7 no canto direito, mas **escondido em hover do composer** (aparece só quando passa mouse) | Sempre visível |
| **D4** | Send button cor | Verde WhatsApp `#00A884` (token novo `--wa-send-bg`) | Manter `n-brand` (verde ChatSPX atual) |
| **D5** | Feature flag | **NÃO** — flip direto. Working tree → testar → commit | Usar `wa_composer_v2` em UISettings se quiser rollback gradual |
| **D6** | Anexos popover | Popover ao clicar `+` com 5 opções: Foto, Vídeo, Áudio, Documento, Contato | Manter input genérico atual (single click) |
| **D7** | Bubble menu formatação | Implementar real (lib `prosemirror-view` + custom plugin) | Esconder menubar via CSS, contar com atalhos `Ctrl+B/I/U` |
| **D8** | Placeholder | "Mensagem" (igual WhatsApp pt-BR) | "Mensagem... (Shift+Enter pra nova linha, / pra resposta pronta)" |

**Recomendação minha (Orion):** todos os defaults da coluna "padrão assumido". É o que mais se aproxima de WhatsApp sem comprometer features ChatSPX.

---

## 5. Tokens novos (`tailwind.config.js` + `_chat-spx-tokens.scss`)

```scss
:root {
  /* WhatsApp composer light */
  --wa-composer-bg:           #F0F2F5;  /* fundo do reply-box */
  --wa-composer-input-bg:     #FFFFFF;  /* fundo do input pill */
  --wa-composer-icon:         #54656F;  /* cor dos ícones (emoji, plus, mic) */
  --wa-composer-send-bg:      #00A884;  /* botão send circular verde */
  --wa-composer-send-fg:      #FFFFFF;
  --wa-composer-placeholder:  #667781;
  --wa-composer-private-bg:   #FFF8C5;  /* chip slim modo privada */
  --wa-composer-private-fg:   #6B5800;
  --wa-composer-copilot:      #8B5CF6;  /* roxo ChatSPX, mantido */
}

.dark {
  --wa-composer-bg:           #202C33;
  --wa-composer-input-bg:     #2A3942;
  --wa-composer-icon:         #AEBAC1;
  --wa-composer-send-bg:      #00A884;
  --wa-composer-send-fg:      #FFFFFF;
  --wa-composer-placeholder:  #8696A0;
  --wa-composer-private-bg:   #533F03;
  --wa-composer-private-fg:   #FFD43B;
  --wa-composer-copilot:      #A78BFA;
}
```

Mapear como utilities Tailwind via `tailwind.config.js > theme.extend.colors`:

```js
'wa-composer': {
  bg: 'var(--wa-composer-bg)',
  input: 'var(--wa-composer-input-bg)',
  icon: 'var(--wa-composer-icon)',
  send: 'var(--wa-composer-send-bg)',
  'send-fg': 'var(--wa-composer-send-fg)',
  placeholder: 'var(--wa-composer-placeholder)',
  'private-bg': 'var(--wa-composer-private-bg)',
  'private-fg': 'var(--wa-composer-private-fg)',
  copilot: 'var(--wa-composer-copilot)',
},
```

Uso: `bg-wa-composer-bg`, `text-wa-composer-icon`, etc.

---

## 6. Plano em fases (escopo completo)

### Fase A — Remover TopPanel; chip Privada slim

**Arquivos:**
- `app/javascript/dashboard/components/widgets/conversation/ReplyTopPanel.vue`
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` (template + script)

**Mudanças:**

1. Em `ReplyTopPanel.vue`: simplificar drasticamente — só renderizar quando `isOnPrivateNote === true` OR `copilot.isActive`. Caso contrário, retorna `<!--v-if-->` (vazio).
2. Em modo Privada: renderizar chip compacto:
   ```vue
   <div class="flex items-center gap-2 px-3 py-1.5 bg-wa-composer-private-bg text-wa-composer-private-fg text-xs font-medium border-b border-n-amber-6/30">
     <Icon icon="i-lucide-lock" class="size-3.5" />
     <span>{{ $t('CONVERSATION.REPLYBOX.PRIVATE_NOTE_BANNER') }}</span>
     <button class="ml-auto underline-offset-2 hover:underline" @click="$emit('set-reply-mode', 'reply')">
       {{ $t('CONVERSATION.REPLYBOX.SWITCH_TO_REPLY') }}
     </button>
   </div>
   ```
3. Em modo Reply (default): TopPanel não renderiza nada visualmente. Toggle disponível via:
   - Shortcut `Ctrl+Shift+P` (já implementado em `useKeyboardShortcuts`)
   - Botão dentro do menu kebab `⋮` (próxima fase, ou ícone no `+` popover)

4. Em `ReplyBox.vue`: remover o slot do TopPanel quando modo Reply, manter apenas em Privada/Copilot

**i18n adicionar:**
```json
// pt_BR/conversation.json
"REPLYBOX": {
  "PRIVATE_NOTE_BANNER": "Modo nota privada — visível só para agentes",
  "SWITCH_TO_REPLY": "Trocar para resposta"
}
// en/conversation.json
"REPLYBOX": {
  "PRIVATE_NOTE_BANNER": "Private note mode — visible only to agents",
  "SWITCH_TO_REPLY": "Switch to reply"
}
```

**Tempo:** 2h

---

### Fase B — Esconder ProseMirror menubar; bubble menu na seleção

**Arquivos:**
- `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue`
- (novo) `app/javascript/shared/helpers/editor/bubbleMenuPlugin.js`

**B1 — Esconder menubar (15min):**

Adicionar CSS no `Editor.vue` ou global:
```css
.reply-box .ProseMirror-menubar-wrapper > .ProseMirror-menubar {
  display: none !important;
}
```

Atalhos `Ctrl+B/I/U` continuam funcionando via ProseMirror keymap default.

**B2 — Bubble menu real (5h):**

Criar plugin ProseMirror que:
1. Escuta `EditorView.update` e `selectionchange`
2. Quando selection !== empty E selection.from !== selection.to:
   - Calcula bounding rect da seleção via `view.coordsAtPos`
   - Renderiza um `<div>` flutuante (Vue Teleport para body) com botões Bold, Italic, Underline, Strike, Code, Link
3. Posiciona acima da seleção com 8px de offset, fade-in 100ms
4. Dispara comandos do prosemirror-commands (`toggleMark(schema.marks.strong)`, etc)
5. Some quando seleção colapsa ou clique fora

Exemplo (esqueleto):
```js
import { Plugin, PluginKey } from 'prosemirror-state';

export const bubbleMenuKey = new PluginKey('bubbleMenu');

export function bubbleMenuPlugin({ onShow, onHide, onMove }) {
  return new Plugin({
    key: bubbleMenuKey,
    view(view) {
      return {
        update(view, lastState) {
          const { state } = view;
          const { from, to, empty } = state.selection;
          if (empty || !state.selection.$from.parent.isTextblock) {
            onHide();
            return;
          }
          const start = view.coordsAtPos(from);
          const end = view.coordsAtPos(to);
          const left = (start.left + end.left) / 2;
          const top = start.top - 8;
          onShow({ left, top });
        },
        destroy() { onHide(); },
      };
    },
  });
}
```

E componente Vue `<MessageEditorBubbleMenu>` com Teleport pro body.

**Tempo:** B1=15min, B2=5h. **Total fase B: 5h15min.**

---

### Fase C — Single composer pill (bottom bar)

**Arquivos:**
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` (template + style)

**Mudanças:**

1. Substituir o `<div class="flex justify-between p-3">` final por:

```vue
<div
  class="flex items-end gap-2 px-3 py-2 bg-wa-composer-bg"
  :class="{ 'bg-wa-composer-private-bg/30': isOnPrivateNote }"
>
  <!-- Cluster ações esquerda -->
  <div class="flex items-center gap-1 flex-shrink-0 self-end pb-0.5">
    <button
      class="size-9 rounded-full flex items-center justify-center text-wa-composer-icon hover:bg-n-alpha-2 transition-colors"
      :title="$t('CONVERSATION.REPLYBOX.EMOJI')"
      @click="toggleEmojiPicker"
    >
      <Icon icon="i-lucide-smile" class="size-5" />
    </button>
    <button
      class="size-9 rounded-full flex items-center justify-center text-wa-composer-icon hover:bg-n-alpha-2 transition-colors"
      :title="$t('CONVERSATION.REPLYBOX.ATTACH')"
      @click="toggleAttachmentPopover"
    >
      <Icon icon="i-lucide-plus" class="size-5" />
    </button>
  </div>

  <!-- Pill central com input -->
  <div
    class="flex-1 min-w-0 flex items-center gap-2 bg-wa-composer-input rounded-2xl px-3 py-1.5 min-h-9 max-h-32 overflow-y-auto"
  >
    <!-- ProseMirror sem menubar -->
    <WootMessageEditor
      ref="messageEditor"
      v-model="message"
      class="flex-1 min-w-0 wa-composer-editor"
      :placeholder="$t('CONVERSATION.REPLYBOX.PLACEHOLDER')"
      :min-height="1"
      :is-private="isOnPrivateNote"
    />

    <!-- Copilot ✨ pequeno no canto direito do pill -->
    <button
      v-if="canShowCopilot"
      class="size-7 rounded-full flex items-center justify-center text-wa-composer-copilot hover:bg-wa-composer-copilot/10 flex-shrink-0"
      :title="$t('CONVERSATION.COPILOT_TITLE')"
      @click="copilot.toggleEditor"
    >
      <Icon icon="i-lucide-sparkles" class="size-4" />
    </button>

    <!-- Expand ⛶ pequeno (visível só em hover) -->
    <button
      class="size-7 rounded-full flex items-center justify-center text-wa-composer-icon hover:bg-n-alpha-2 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
      :title="$t('CONVERSATION.REPLYBOX.EXPAND')"
      @click="togglePopout"
    >
      <Icon icon="i-lucide-maximize-2" class="size-3.5" />
    </button>
  </div>

  <!-- Ação direita: alterna mic ↔ send -->
  <button
    v-if="hasMessageContent"
    class="size-10 rounded-full flex items-center justify-center bg-wa-composer-send text-wa-composer-send-fg hover:brightness-110 active:scale-95 transition-all flex-shrink-0 self-end"
    :disabled="isSending"
    :title="$t('CONVERSATION.SEND')"
    @click="sendMessage"
  >
    <Icon icon="i-lucide-send" class="size-5" />
  </button>
  <button
    v-else
    class="size-10 rounded-full flex items-center justify-center text-wa-composer-icon hover:bg-n-alpha-2 transition-colors flex-shrink-0 self-end"
    :title="$t('CONVERSATION.REPLYBOX.RECORD')"
    @click="startAudioRecord"
  >
    <Icon icon="i-lucide-mic" class="size-5" />
  </button>
</div>
```

2. Computed `hasMessageContent`:
   ```js
   const hasMessageContent = computed(() =>
     (message.value || '').trim().length > 0 || hasAttachments.value
   );
   ```

3. Group hover no parent: adicionar `class="group"` no `.reply-box` raiz pra `group-hover:` funcionar pro botão expand.

**Tempo:** 3h

---

### Fase D — Popover de anexos com 5 opções

**Arquivo:** novo `app/javascript/dashboard/components/widgets/conversation/AttachmentPopover.vue`

```vue
<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      ref="popoverEl"
      :style="popoverStyle"
      class="fixed z-50 bg-n-solid-1 dark:bg-n-solid-2 rounded-xl shadow-lg border border-n-weak py-2 min-w-[200px]"
    >
      <button
        v-for="option in options"
        :key="option.id"
        class="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-n-alpha-2 transition-colors text-left"
        @click="selectOption(option)"
      >
        <span class="size-8 rounded-full flex items-center justify-center" :class="option.bgClass">
          <Icon :icon="option.icon" class="size-4 text-white" />
        </span>
        <span class="text-sm text-n-slate-12">{{ $t(option.label) }}</span>
      </button>
    </div>
  </Teleport>
</template>

<script setup>
const options = [
  { id: 'image', label: 'CONVERSATION.REPLYBOX.ATTACH_IMAGE', icon: 'i-lucide-image', bgClass: 'bg-violet-500', accept: 'image/*' },
  { id: 'video', label: 'CONVERSATION.REPLYBOX.ATTACH_VIDEO', icon: 'i-lucide-video', bgClass: 'bg-rose-500', accept: 'video/*' },
  { id: 'audio', label: 'CONVERSATION.REPLYBOX.ATTACH_AUDIO', icon: 'i-lucide-music', bgClass: 'bg-orange-500', accept: 'audio/*' },
  { id: 'document', label: 'CONVERSATION.REPLYBOX.ATTACH_DOC', icon: 'i-lucide-file-text', bgClass: 'bg-blue-500', accept: '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.txt' },
  { id: 'contact', label: 'CONVERSATION.REPLYBOX.ATTACH_CONTACT', icon: 'i-lucide-user', bgClass: 'bg-emerald-500', accept: null /* abre modal */ },
];
</script>
```

Lógica: cada option dispara `<input type="file" accept=...>` correspondente, ou modal de Contact picker.

**Tempo:** 2h

---

### Fase E — Polimento: animações, transições

**Arquivo:** `ReplyBox.vue` (style)

1. Mic ↔ Send crossfade 150ms:
   ```vue
   <Transition name="composer-action" mode="out-in">
     <button v-if="hasMessageContent" key="send">...</button>
     <button v-else key="mic">...</button>
   </Transition>
   ```
   ```css
   .composer-action-enter-active, .composer-action-leave-active {
     transition: opacity 150ms ease, transform 150ms ease;
   }
   .composer-action-enter-from, .composer-action-leave-to {
     opacity: 0;
     transform: scale(0.85);
   }
   ```

2. Chip Privada slide-down ao ativar:
   ```vue
   <Transition name="slide-down">
     <ReplyTopPanel v-if="isOnPrivateNote || copilot.isActive" ... />
   </Transition>
   ```

3. Bubble menu de formatação fade-in 100ms ao aparecer

4. Send button: scale `0.95` ao apertar (`active:scale-95`)

5. Input pill foca: `ring-2 ring-wa-composer-send/20` em focus-within (subtle glow)

**Tempo:** 1h

---

### Fase F — i18n e textos

Atualizar:
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`
- `app/javascript/dashboard/i18n/locale/en/conversation.json`

```json
"REPLYBOX": {
  "PLACEHOLDER": "Mensagem",  // pt_BR
  "PLACEHOLDER_WHATSAPP": "Mensagem",
  "PLACEHOLDER_EMAIL": "Escreva uma resposta...",  // mantém antigo pra email
  "EMOJI": "Emoji",
  "ATTACH": "Anexar",
  "ATTACH_IMAGE": "Foto",
  "ATTACH_VIDEO": "Vídeo",
  "ATTACH_AUDIO": "Áudio",
  "ATTACH_DOC": "Documento",
  "ATTACH_CONTACT": "Contato",
  "RECORD": "Gravar áudio",
  "SEND": "Enviar",
  "EXPAND": "Expandir",
  "PRIVATE_NOTE_BANNER": "Modo nota privada — visível só para agentes",
  "SWITCH_TO_REPLY": "Trocar para resposta"
}
```

```json
// en/conversation.json
"REPLYBOX": {
  "PLACEHOLDER": "Message",
  "PLACEHOLDER_EMAIL": "Write a reply...",
  "EMOJI": "Emoji",
  "ATTACH": "Attach",
  "ATTACH_IMAGE": "Photo",
  "ATTACH_VIDEO": "Video",
  "ATTACH_AUDIO": "Audio",
  "ATTACH_DOC": "Document",
  "ATTACH_CONTACT": "Contact",
  "RECORD": "Record voice message",
  "SEND": "Send",
  "EXPAND": "Expand",
  "PRIVATE_NOTE_BANNER": "Private note mode — visible only to agents",
  "SWITCH_TO_REPLY": "Switch to reply"
}
```

**Tempo:** 30min

---

### Fase G — Responsividade e adaptações

1. **Email inbox**: detectar via `inboxIsEmail` computed → renderizar layout antigo (com `ReplyEmailHead`, signature, etc). NÃO aplicar tema WhatsApp em email.
2. **Mobile** (`< 640px`): manter layout pill, mas reduzir ícones pra `size-8` e gap-1
3. **Modo popout** (`reply-box--popout`): manter funcional, layout WhatsApp adapta com largura maior
4. **Teclado virtual mobile**: `min-h-9 max-h-32` permite crescimento até 4 linhas

**Tempo:** 1h

---

## 7. Validação Playwright (before/after)

Criar script `scripts/visual-tests/replybox-whatsapp.js` (não commitar — fica em `.gitignore` ou tmp/):

```js
const { chromium } = require('playwright');

const STATES = ['idle', 'typing', 'private', 'with-attachment', 'copilot-active'];

async function captureState(page, state) {
  const replyBox = page.locator('.reply-box').first();

  switch (state) {
    case 'typing':
      await page.locator('.ProseMirror[contenteditable]').click();
      await page.keyboard.type('Olá, esta é uma mensagem de teste WhatsApp-fiel');
      break;
    case 'private':
      await page.locator('button:has-text("Mensagem Privada"), button:has-text("Private Note")').first().click();
      break;
    // ...
  }
  await page.waitForTimeout(500);

  const box = await replyBox.boundingBox();
  await page.screenshot({
    path: `/tmp/replybox-after-${state}.png`,
    clip: { x: box.x, y: box.y, width: box.width, height: box.height + 20 },
  });

  // Métricas
  return {
    state,
    height: box.height,
    width: box.width,
  };
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 } });
  const page = await ctx.newPage();

  // login + abrir conv (igual hoje)
  // ...

  const metrics = [];
  for (const state of STATES) {
    metrics.push(await captureState(page, state));
  }

  console.log('=== Métricas pós-redesign ===');
  console.table(metrics);

  // Asserções
  const idle = metrics.find(m => m.state === 'idle');
  if (idle.height > 80) {
    console.error(`FAIL: idle altura ${idle.height}px deveria ser <= 80px (target 62px)`);
    process.exit(1);
  }
  console.log('✅ Altura idle dentro do target');

  await browser.close();
})();
```

**Asserções de sucesso:**

| Estado | Altura máxima esperada | Observação |
|--------|-----------------------|------------|
| idle (sem texto) | ≤ 80px (target 62) | sem chip Privada, sem anexo |
| typing (com texto curto) | ≤ 80px | botão send aparece |
| typing-multiline (4 linhas) | ≤ 160px | input pill cresce |
| private | ≤ 110px | + chip slim em cima |
| with-attachment | ≤ 160px | + linha de thumbs |
| copilot-active | manter atual | usa ReplyTopPanel |

**Comparação visual com referência WhatsApp:**

Não temos acesso programático ao WhatsApp Web (login QR exigido). Vou anexar referência estática:
- `docs/refs/whatsapp-web-composer-light.png` — captura manual (Walisson pode pegar)
- `docs/refs/whatsapp-web-composer-dark.png` — idem

Validação humana: agente que executar deve abrir lado a lado o screenshot pós-redesign e a referência WhatsApp Web, confirmar visualmente.

---

## 8. Checklist visual pós-implementação

- [ ] Estado idle tem ~62px de altura
- [ ] Sem outlines em nenhum botão
- [ ] Send button é circular verde `#00A884`
- [ ] Mic aparece quando texto vazio, send aparece quando há texto
- [ ] Placeholder é "Mensagem" (pt-BR) / "Message" (en)
- [ ] Emoji + Plus são ícones lucide size-5 sem outline
- [ ] Input pill tem `bg-white` (light) / `bg-#2A3942` (dark)
- [ ] Reply-box geral tem `bg-#F0F2F5` (light) / `bg-#202C33` (dark)
- [ ] Chip Privada aparece amarelo slim só quando `isOnPrivateNote`
- [ ] Toggle Reply/Private acessível via shortcut `Ctrl+Shift+P`
- [ ] Copilot ✨ é ícone roxo size-7 dentro do input pill
- [ ] Expand ⛶ é size-7 escondido até hover
- [ ] ProseMirror menubar (Bold/Italic/etc) NÃO aparece visualmente
- [ ] Ctrl+B/I/U continuam aplicando formatação (atalhos)
- [ ] Bubble menu de formatação aparece flutuante ao selecionar texto
- [ ] Popover de anexos abre ao clicar `+` com 5 opções (Foto, Vídeo, Áudio, Documento, Contato)
- [ ] Email inbox mantém layout original (ReplyEmailHead, signature)
- [ ] Mobile (<640px) layout adapta sem quebrar
- [ ] i18n pt_BR e en atualizados

---

## 9. Riscos e mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Bubble menu real quebra ProseMirror existente | Média | Alto | Implementar B2 em PR separado APÓS validar B1 (só esconder menubar) funcionar |
| Toggle Privada via shortcut confunde usuários | Baixa | Médio | Documentar em `/help` interno; chip clicável quando ativo |
| Copilot perde proeminência | Média | Médio | Manter visível como ícone size-7 sempre; Walisson pode preferir tamanho maior |
| Cores WhatsApp clashes com brand ChatSPX | Baixa | Baixo | Send button mantém verde WhatsApp ou vira `n-brand` (decisão D4) |
| Email inbox quebra | Alta se não tratado | Alto | `v-if="!inboxIsEmail"` em todo o novo composer; manter ReplyBox antigo pra email |
| Anexos popover popover_position quebra | Média | Médio | Usar Teleport + getBoundingClientRect (padrão do priority menu) |

---

## 10. Plano de execução completo

| # | Fase | Arquivos | Tempo estimado |
|---|------|----------|----------------|
| 1 | A — TopPanel + chip Privada | `ReplyTopPanel.vue`, `ReplyBox.vue` | 2h |
| 2 | B1 — Esconder menubar (CSS) | `ReplyBox.vue` (style global) | 15min |
| 3 | C — Single composer pill | `ReplyBox.vue` (template + style + script) | 3h |
| 4 | D — Popover anexos | novo `AttachmentPopover.vue` + `ReplyBox.vue` | 2h |
| 5 | E — Animações | `ReplyBox.vue` (style), `Transition` Vue | 1h |
| 6 | F — i18n | `pt_BR/conversation.json`, `en/conversation.json` | 30min |
| 7 | G — Responsividade + email | `ReplyBox.vue` (computed + condicionais) | 1h |
| 8 | Tokens — `tailwind.config.js` + scss | 30min |
| 9 | Build + restart + smoke test | — | 30min |
| 10 | Playwright validação | `tmp/replybox-test.js` | 1h |
| 11 | B2 — Bubble menu real (opcional, mas Walisson quer "tudo") | `Editor.vue`, novo `bubbleMenuPlugin.js` + `BubbleMenu.vue` | 5h |

**Total realista:** **~16h** (2 dias de trabalho focado)

---

## 11. Plano de rollback

Working tree, sem commits intermediários. Se quebrar algo:

```bash
git restore app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue
git restore app/javascript/dashboard/components/widgets/conversation/ReplyTopPanel.vue
git restore app/javascript/dashboard/components/widgets/WootWriter/Editor.vue
rm app/javascript/dashboard/components/widgets/conversation/AttachmentPopover.vue
git restore app/javascript/dashboard/i18n/locale/pt_BR/conversation.json
git restore app/javascript/dashboard/i18n/locale/en/conversation.json
git restore tailwind.config.js
git restore app/javascript/dashboard/assets/scss/  # se tokens criados
RAILS_ENV=production bundle exec rails assets:precompile
sudo systemctl restart chatwoot.target
```

---

## 12. Perguntas em aberto pra Walisson

(Refletindo as decisões D1-D8 da seção 4. Cada uma tem padrão recomendado mas Walisson pode mudar.)

1. **Toggle Privada**: chip slim só em modo Privada, ou pill compacta sempre visível? *(default: chip slim só ativo)*
2. **Copilot**: ícone roxo size-7 no canto direito do input, ou esconder em menu kebab? *(default: ícone visível)*
3. **Send cor**: verde WhatsApp `#00A884` ou manter `n-brand`? *(default: verde WhatsApp)*
4. **Feature flag**: usar `wa_composer_v2` em UISettings ou flip direto? *(default: flip direto, working tree, rollback via git)*
5. **Anexos**: popover bonito com 5 opções ou input genérico (single click)? *(default: popover, mais WhatsApp)*
6. **Bubble menu formatação**: implementar real (5h) ou só esconder menubar (15min)? *(default: implementar real porque Walisson disse "tudo")*
7. **Placeholder**: "Mensagem" ou manter texto longo atual? *(default: "Mensagem", igual WhatsApp)*

Se aceitar todos os defaults, me dá o OK e eu (ou agent executor) parto pro código.

---

## 13. Referências

- WhatsApp Web atual (2025/2026, conhecimento Orion):
  - Composer slim ~62px altura
  - Cores: `#F0F2F5` light, `#202C33` dark
  - Send button verde `#00A884`
  - Input pill background branco / dark `#2A3942`
- WhatsApp para iOS/Android: idem mesmo design system
- ChatSPX features atuais: Reply/Private toggle, Copilot, anexos, signature, canned responses, bubble menu (não tem ainda)
- Bubliography:
  - https://www.codewithfaraz.com/content/114/create-a-whatsapp-web-interface-clone-using-html-and-css
  - https://www.creative-tim.com/twcomponents/component/whatsapp-web-clone

---

## 14. Output esperado pós-execução

Working tree com:
- 3 arquivos Vue modificados (ReplyBox, ReplyTopPanel, Editor)
- 1 arquivo Vue novo (AttachmentPopover)
- 2 i18n atualizados (pt_BR, en)
- 1 tailwind.config.js atualizado
- 0 commits (esperando aprovação Walisson + commit consolidado P5)
- 6+ screenshots Playwright em `/tmp/replybox-after-*.png` provando estados visuais
