# Spec — Envio de Arquivos: Feedback, Limites e Animações

> **Objetivo:** todo envio de arquivo tem feedback claro; nada falha em silêncio; nada fica preso esperando reload; limites impostos antes do upload; e uma camada de animações premium e consistente com o WhatsApp.
> **Para:** dev de implementação.

---

## 1. Problema

Ao enviar um arquivo, o agente **não sabe se foi**:
1. **Sem feedback de upload** — não há barra/anel de progresso; só um ⏰ no balão.
2. **Limites não impostos** — inbox WAHA não tem limite por tipo (cai em 40 MB) e o backend só valida `WebWidget` → arquivo grande sai e o WhatsApp recusa.
3. **Falha silenciosa (WAHA)** — o app externo recebe o webhook (200); se o WAHA falha de fato, ninguém reporta de volta → mensagem fica `sent` para sempre.
4. **"Precisa recarregar"** — a mensagem otimista trava em `progress` quando o socket fica _stale_; não há reconciliação/retry ao reconectar.
5. **Detalhes** — áudio com erro engolido, botão retry sem debounce (duplica), "colar arquivo" ignorado no composer novo para WhatsApp.

---

## 2. Limites (fonte da verdade)

| Tipo | Meta Oficial (`whatsapp_cloud`) | WAHA (`Channel::Api`) |
|---|---|---|
| Imagem | 5 MB | 16 MB |
| Vídeo | 16 MB | **100 MB** _(confirmar com o dono do WAHA; se a engine recusar, usar 16 MB)_ |
| Áudio | 16 MB | 16 MB |
| Documento | 100 MB | 100 MB |
| Sticker | 100 KB / 500 KB | — |

- Teto de infra (nginx) = 256 MB; **não** é o limite de produto.
- Frontend Meta já valida certo (`fileUploadRules.ts`). **WAHA hoje não tem regra (cai em 40 MB).** Backend só valida `WebWidget`.

---

## 3. Fluxo exato

### 3.1 Atual (hoje)

**Anexar → enviar (comum):**
```
1. Anexa (browse/drag/paste) → fileUploadMixin/useFileUpload
   - DirectUpload OU FormData inline  (SEM onUploadProgress)
2. Abre AttachmentPreviewModal (sem progresso)
3. Enviar → createPendingMessageAndSend
   - cria mensagem otimista { id: UUID, echo_id: UUID, status: 'progress' }
   - commit ADD_MESSAGE (status progress)  → ⏰ no balão
4. POST /conversations/{id}/messages (echo_id no payload)
5a. 200 → commit ADD_MESSAGE (status 'sent'); reconcilia por echo_id → ✓
5b. erro → commit status 'failed' + toast (pode vir vazio em erro de rede)
6. message.created chega pelo ActionCable → confirma/atualiza
```

**Por canal (passo do "vai pro WhatsApp"):**
- **Meta Cloud (inbox 91):** `SendReplyJob → Whatsapp::SendOnWhatsappService` envia mídia por **link** (`attachment.download_url`); erro da Meta volta em `message.external_error` → **visível**.
- **WAHA (inboxes 61/62, `Channel::Api`):** `SendReplyJob → SendEmailNotificationService` (no-op p/ WAHA). A mídia real é enviada pelo **app externo `chatwoot-waha-app`**, que consome o `webhook_url` da inbox e posta no WAHA (`/api/sendFile|sendImage|...`). Status volta só por **polling** (`Waha::MessageStatusSyncService`, que **nunca marca `failed`**).

**Onde quebra:**
- Upload sem progresso (passo 1-3).
- Sem validação por tipo/canal antes do upload (passo 1).
- WAHA: se o app externo responde 200 mas o WAHA falha → erro perdido (passo 5/6), fica `sent` para sempre.
- Socket _stale_ → pending nunca sai de `progress` (passo 6); pode ser cortada pelo trim de 500 msgs ou silenciada pela flag `hasNewerMessages`.

### 3.2 Alvo (como deve ficar)

```
1. Anexar → VALIDA tamanho por tipo+canal ANTES
   - excede → chip amigável no preview ("Vídeo até 16 MB nesta linha"); não sobe.
2. Upload com PROGRESSO real (onUploadProgress) → anel circular % no thumbnail + cancelar (X).
3. Enviar → mensagem otimista 'progress' (⏰).
4. POST → 200: anel faz sweep→100% → checkmark desenhado + pop do balão (status 'sent').
            erro: shake + status 'failed' + "Reenviar" inline (toast nunca vazio).
5. Confirmação de entrega/leitura (✓ → ✓✓ → ✓✓ azul) via status-sync.
6. Se o socket cair e voltar → reconcilePendingMessages():
   - checa echo_id no servidor; existe → atualiza p/ sent/delivered;
   - não existe → retry automático (≤3x); falhou 3x → 'failed'.
   - usuário VÊ a pendente resolver (mesma animação sweep→check). Sem reload.
7. WAHA: falha real de envio é reportada (PUT /messages/{id} status=failed) OU
   o status-sync marca 'failed' após X sem ACK → agente vê "Falha ao enviar".
```

---

## 4. Implementação

### F1 — Limites por tipo/canal (~1–2 d)
- `@chatwoot/utils → fileUploadRules.ts`: adicionar regra para `Channel::Api`/WAHA (hoje cai no default 40 MB) com os valores da §2. _(é dep externa — avaliar override local vs. PR upstream.)_
- `composables/useFileUpload.js` + `mixins/fileUploadMixin.js`: validar tamanho **por tipo+canal antes** de `DirectUpload`/attach; mensagem clara (`CONVERSATION.FILE_SIZE_LIMIT` com o limite do canal).
- `app/models/attachment.rb#validate_file_size`: estender a validação para `Channel::Whatsapp` e `Channel::Api` (hoje só `WebWidget`); rede de segurança server-side com erro amigável.
- Config: `WAHA_MAX_VIDEO_SIZE_MB` (+ por tipo se necessário).

### F2 — Feedback + Animações (~3–4 d)
- **Progresso:** propagar `onUploadProgress` (preferir indirect upload + axios `onUploadProgress`, ou DirectUpload custom) → **anel de progresso** (§5).
- `components-next/message/MessageStatus.vue`: morph ⏰→✓, sweep→check + pop, _wipe_ azul nos tiques (§5).
- `components-next/message/MessageError.vue` + `Message.vue#handleRetry`: shake na falha + **debounce/flag `isRetrying`** (não duplicar).
- `components/widgets/WootWriter/AudioRecorder.vue` (~linhas 89-117): `try/catch` no `convertAudio` → `emit('recordError')` + toast + Sentry.
- `AttachmentPreviewModal` + régua de anexos: entrada com stagger + chip de limite (§5).
- `<TransitionGroup>` na lista de mensagens e na régua de anexos (FLIP, §5).
- Composer novo (`components-next/NewConversation/ComposeConversation.vue` / `ActionButtons.vue`): habilitar paste/anexo também para WhatsApp (hoje só Email/Web).

### F3 — Falha silenciosa WAHA (~1–2 d + coordenação)
- **Opção A (preferida):** o `chatwoot-waha-app` reporta sucesso/erro do envio chamando `PUT /api/v1/accounts/{id}/conversations/{conv}/messages/{id}` com `status=failed&external_error=...` (endpoint **já existe**). _Depende do dono desse app externo._
- **Opção B (só Chatwoot):** `Waha::MessageStatusSyncService` marca `failed` quando uma outgoing com anexo fica sem ACK por X min e não aparece no WAHA (cuidado com falso-positivo). + idempotência por `external_id`.

### F4 — Reconciliação / fim do "reload" (~3–5 d)
- `helper/ReconnectService.js#onReconnect`: novo `reconcilePendingMessages()` — varre mensagens `progress`/`failed`, checa `echo_id` no servidor, atualiza ou faz retry (≤3x), depois fetch normal.
- Backend: garantir que **broadcasts sempre incluam `echo_id`** (match 100%).
- `store/modules/conversations/index.js`: tratar o trim de 500 (`MESSAGE_WINDOW_SIZE`) e a flag `hasNewerMessages` para não descartar/silenciar pendentes.
- Aproveitar o watchdog de _stale_ (25 s) em `shared/helpers/BaseActionCableConnector.js` para disparar a reconciliação.

### F5 — Estrutural (depois)
- Direct Upload S3/MinIO (tira blob do Puma) — base p/ upload de mídia grande sem travar web.
- Realtime AnyCable + observabilidade (latência de broadcast).

---

## 5. Sistema de Animações

> Regra: animar **só `transform` e `opacity`** (GPU). Fiel ao WhatsApp. Reusar tokens `--wa-composer-*` existentes. Animação serve à clareza — todo estado tem feedback.

### 5.1 Tokens
```css
--motion-instant: 80ms; --motion-fast: 160ms; --motion-base: 240ms;
--motion-slow: 360ms;  --motion-drama: 520ms;

--ease-out-expo:     cubic-bezier(0.16, 1, 0.3, 1);
--ease-in-out-quart: cubic-bezier(0.76, 0, 0.24, 1);
--ease-out-back:     cubic-bezier(0.34, 1.56, 0.64, 1);

/* spring (util JS): pop = { stiffness: 380, damping: 26 }; soft = { 210, 30 } */
```

### 5.2 Coreografia por estado
1. **Anexar:** thumbnail `scale .82→1` + `opacity 0→1` + `translateY 12→0`, `--motion-base`/`--ease-out-back`. Multi-arquivo: **stagger 40 ms**.
2. **Drag-drop:** overlay com blur fade `--motion-fast`; borda tracejada "respirando" (pulse 2 s); no drop os thumbs "voam" do cursor à régua (FLIP).
3. **Enviando:** **anel circular** `stroke-dashoffset` amarrado ao % real + shimmer no traço + glow pulsante atrás do balão; X (cancelar) no hover. Indeterminado = anel girando (linear) com cauda cometa.
4. **Enviado:** anel faz **sweep→100%**, **checkmark desenhado** (`stroke-dashoffset`, `--motion-base`/`--ease-out-expo`) e **pop** do balão (`scale 1→1.03→1`, spring pop). ⏰→✓ é morph.
5. **Tiques:** 2º tique desliza ao lado do 1º ao entregar; ao ler, ambos viram azul com **wipe** L→R (`clip-path inset`), `--motion-base`.
6. **Falha:** **shake** horizontal (3 osc., 8→0 px, `--motion-slow`) + ícone vermelho; ⟳ retry gira 360° ao clicar e a msg re-entra na animação de envio.
7. **Limite excedido:** thumbnail com flash de borda vermelha (2 pulsos) + **chip amigável desce** do topo do preview (`translateY -8→0` + fade).
8. **Áudio:** waveform desenhada L→R ao gravar; processing = anel indeterminado; ao enviar, waveform "comprime" no balão.
9. **Entrada na lista:** balão com pop (spring) + lista acima desliza (FLIP via `<TransitionGroup>` move-class) — sem pulo.
10. **Reconciliação:** pendente travada que se resolve executa o mesmo **sweep→check** — o agente vê resolver.

### 5.3 Acessibilidade
Sob `prefers-reduced-motion: reduce`: trocar springs/shake/glow por **fade simples** (≤ `--motion-fast`), sem overshoot/wipe. Nenhum estado depende só de animação (sempre há ícone/texto).

### 5.4 Stack
Vue `<Transition>`/`<TransitionGroup>` (+ FLIP move-class); CSS custom properties (tokens); spring via `@vueuse/motion` (ou wrapper mínimo) só nos pops/FLIP; SVG `stroke-dashoffset` para anel e check.

---

## 6. Critérios de aceite
- [ ] Anexar mostra **anel de progresso** com % real; multi-arquivo com stagger.
- [ ] Arquivo acima do limite do canal é **bloqueado antes de subir**, com chip amigável (não toast técnico).
- [ ] Sucesso = sweep→check + pop; entrega/leitura = tiques (✓ → ✓✓ → ✓✓ azul).
- [ ] Falha (rede, canal, oversize, WAHA) = **shake + "Reenviar"**; toast **nunca vazio**.
- [ ] Retry **não duplica** (debounce/flag).
- [ ] Áudio que falha ao converter mostra aviso (não engole o erro).
- [ ] Socket cair e voltar → pendentes **se reconciliam sem reload** (e o usuário vê resolver).
- [ ] WAHA: falha real de envio fica **visível** ao agente.
- [ ] `prefers-reduced-motion` respeitado.

## 7. Testes
- Enviar imagem/vídeo/áudio/doc em inbox **Meta** e **WAHA**: progresso → check.
- Anexar oversize por tipo (img 8 MB, vídeo 50 MB) → bloqueio com mensagem.
- Simular erro de rede (offline no meio do POST) → shake + retry sem duplicar.
- Derrubar o WebSocket, enviar, religar → pendente resolve sozinha.
- `prefers-reduced-motion: reduce` → fades simples, sem spring/shake.

## 8. Métricas de sucesso
- 0 mensagens com anexo presas em `progress`/`sent` >10 min sem causa real.
- 100% dos envios com feedback visível (progresso/sucesso/falha).
- Oversize bloqueado no front (queda das falhas tardias de mídia).
- Falha de envio WAHA visível ao agente.
