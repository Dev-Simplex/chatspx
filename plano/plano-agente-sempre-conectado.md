# Plano — Agente ChatSPX conectado "any time" (fim do "Desconectado" ao voltar a aba)

> Pesquisa multiagente (9 agentes: 7 frentes web + 1 código + 1 síntese) — 2026-07-10.
> Sintoma real: agente deixa a aba em segundo plano / máquina ociosa por muito tempo; ao voltar, aparece "Desconectado".

## 1. Causa-raiz (específica deste sintoma)

O socket **já volta sozinho** ao retornar à aba: o `ConnectionMonitor` interno do `@rails/actioncable` 6.1.3 tem seu próprio listener de `visibilitychange` e chama `connection.reopen()` ~200ms após a aba ficar visível (stale >6s ou não-open). O que o agente vê como "Desconectado" é uma **corrida de UI**, não falta de reconexão: (a) o `NetworkNotification.vue` acende o banner OFFLINE **síncrono e sem grace** no evento `WEBSOCKET_DISCONNECT` (`updateWebsocketStatus`, linha 56-59); e (b) a camada própria do app **não escuta visibilitychange/focus/pageshow** e só limpa o banner via um loop de `setTimeout` com backoff que satura em 30s (`reconnectAttempts` nunca é zerado durante a queda — linha 122) e que é *throttled* em background (Chrome clampa timers de aba oculta a 1/s, e a 1/min após 5min). Resultado: socket vivo de novo em ~1s, mas o banner fica preso porque nada no app força um `checkConnection` imediato na volta.

Casos onde nem a lib resolve: **máquina dormiu com aba em foreground** (não dispara visibilitychange) e **bfcache** (dispara `pageshow`, não visibilitychange) — ambos sem nenhum hook no código hoje.

⚠️ Achado extra: **mismatch de versão** — o cliente JS empacotado é `@rails/actioncable` **6.1.3** contra servidor `actioncable` **7.1.5.2**.

## 2. Métodos ranqueados

| Método | Como funciona | Quem usa | Esforço | Impacto | Encaixe no nosso stack |
|---|---|---|---|---|---|
| **A. Debounce/grace no banner** | Só pinta OFFLINE se ainda caído após ~2.5s; reconexão sub-segundo nunca aparece | Slack, Gmail, Linear, Discord | Baixo (1 arquivo) | **Alto** — ataca o sintoma literal | Cirúrgico em `NetworkNotification.vue` |
| **B. `connected` callback na subscription** | App ouve o reopen da lib direto em vez de esperar o poll de `isOpen()` | Padrão SDK realtime | Baixo (~3 linhas) | **Alto** — fecha o maior gap de latência | `BaseActionCableConnector.js:42-53` |
| **C. reopen-on-return (visibilitychange+focus+pageshow+online) + reset do backoff** | Força reopen imediato + `reconnectAttempts=0` + `checkConnection()` na volta | socket.io, Pusher, Phoenix, Centrifugo | Baixo-médio | **Alto** — cobre sleep foreground e bfcache que a lib erra | mesmo arquivo, cauda do constructor |
| **D. REST catch-up no retorno** | Chama `window.reconnectService.handleRouteSpecificFetch()` no retorno (gap-fill por `updatedWithin`) | — (já existe) | Baixo (reuso) | Médio-alto — corretude de dados sem tocar servidor | reusa `ReconnectService.js:120` |
| E. Bump `@rails/actioncable` 6.1.3→7.1.x | `recordMessage()` (qualquer frame reseta staleness), casa com server 7.1.5.2 | Rails default | Baixo (rebuild Vite) | Médio — robustez sob alto volume | mismatch de versão hoje |
| F. Cable standalone / 2 réplicas web | Deploy não derruba 100% dos WS de uma vez (Redis adapter já compartilha estado) | GitLab, apps Rails multi-instância | Médio | Alto p/ deploy | units já templados `.1`, nginx já tem `upstream` |
| G. Heartbeat cliente→servidor com pong-timeout | Detecta socket zumbi (readyState mente pós-sleep) em ~2s | Phoenix, Pusher | Médio (RoomChannel + client) | Médio | reusa `update_presence` de 20s |
| H. SharedWorker (1 WS quente entre abas) | Timers de worker escapam do throttling; conexão quente ao voltar | Pusher, AnyCable | Médio-alto | Alto p/ background | reescreve bootstrap do cable |
| I. AnyCable-Go + reliable streams | WS sobrevive a restart do Rails; replay de msgs perdidas sem re-auth | ClickFunnels, CoinGecko, Doximity | Alto (infra Go+gRPC) | Muito alto | fase 2 estratégica |

**Rejeitados (ilusão — não gastar tempo):** Service Worker segurando WS (morre ~30s ocioso; keep-alive de WS só em SW de *extensão* Chrome 116+), Screen Wake Lock (auto-liberado quando a aba fica oculta), Web Push como "revive silencioso" (WebKit exige `userVisibleOnly:true`). Keepalive de cliente no freeze/sleep também é inútil: heartbeat E timer de reconexão congelam juntos, e enquanto a aba está só *throttled* o **ping de 3s do servidor** (`BEAT_INTERVAL=3`) já mantém o socket e derrota o idle de 100s da Cloudflare sozinho.

## 3. O que EXATAMENTE adicionar (amarrado ao código)

Arquivos:
- `app/javascript/shared/helpers/BaseActionCableConnector.js`
- `app/javascript/dashboard/components/NetworkNotification.vue`
- `app/javascript/dashboard/helper/ReconnectService.js`

### 3.1 `connected` callback (Método B) — `BaseActionCableConnector.js:42-53`

Hoje a subscription define só `updatePresence`, `received`, `disconnected` (linha 42-53) — **não há `connected`**, então quando a lib reabre o socket o app nunca é avisado. Adicionar, ao lado de `disconnected:` (linha 47):

```js
connected: () => {
  if (this.isDestroyed) return;
  this.reconnectAttempts = 0;   // hoje só zera no branch de sucesso, linha 99
  this.clearReconnectTimer();
  this.checkConnection();       // reusa o dance isOpen→onReconnect (92-105)
},
```

Isso sozinho já elimina a espera pelo poll de até 30s: o `checkConnection()` (92-105) vê `isOpen()===true`, dispara `onReconnect()` → `WEBSOCKET_RECONNECT` → refetch → `WEBSOCKET_RECONNECT_COMPLETED`.

### 3.2 reopen-on-return (Método C) — cauda do constructor, após linha 68

```js
this.handleReturnToForeground = () => {
  if (this.isDestroyed) return;
  const conn = this.consumer.connection;
  if (!conn.isOpen()) conn.reopen();   // mesmo padrão do ConnectionMonitor da lib
  this.reconnectAttempts = 0;
  this.clearReconnectTimer();
  this.checkConnection();
  window.reconnectService?.handleRouteSpecificFetch?.(); // Método D, gap-fill
};
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') this.handleReturnToForeground();
});
window.addEventListener('focus', this.handleReturnToForeground);
window.addEventListener('pageshow', e => { if (e.persisted) this.handleReturnToForeground(); });
```

- `visibilitychange` → troca de aba (reforça a lib, elimina os 200ms + poll).
- `focus` → foco de janela sem troca de aba.
- `pageshow` persisted → **bfcache** (back/forward), que a lib não pega.
- Gate `if (!conn.isOpen()) conn.reopen()` evita matar um handshake em voo e brigar com o `visibilityDidChange` interno da lib.
- **Cleanup** em `disconnect()` (134-146): remover os 3 listeners (guardar refs).

### 3.3 Debounce no banner (Método A) — `NetworkNotification.vue:56-59`

```js
const DISCONNECT_GRACE_MS = 2500;
let graceTimer = null;
const updateWebsocketStatus = () => {
  isDisconnected.value = true;
  clearTimeout(graceTimer);
  graceTimer = setTimeout(() => {
    if (isDisconnected.value) showNotification.value = true; // ainda caído → mostra
  }, DISCONNECT_GRACE_MS);
};
```

Cancelar `graceTimer` no início de `handleReconnectionCompleted` (61-67) e `handleReconnecting` (69-77), e no `onBeforeUnmount` (105-107). Reconexão dentro de 2.5s nunca acende OFFLINE. **Manter** o banner para quedas reais >2.5s.

### 3.4 Resumability pragmática (Método D) — reuso, sem servidor

Já chamado dentro do `handleReturnToForeground`. Roteia p/ `ReconnectService.handleRouteSpecificFetch` (`ReconnectService.js:120`) → janela `updatedWithin`. Honestidade: essa janela por `updated_at` **perde** eventos que não mexem em `updated_at` (delete de msg, read, presence) — resumability real por sequence-id é projeto de servidor (fase 3). O REST catch-up cobre ~80% e já existe. Bônus barato: estender `handleOnlineEvent` (`ReconnectService.js:46-50`) p/ também disparar reconnect-check no `online`.

## 4. Como os apps grandes fazem (credibilidade)

- **Reconnect-on-return é norma:** socket.io recomenda `window.addEventListener('focus', ()=>socket.connect())`; Pusher/Phoenix/Centrifugo/socket.io reconectam em tab-return via visibilitychange+focus+online.
- **Banner com grace, nunca instantâneo:** Slack só mostra a barra amarela após falha *sustentada*; Discord "Connecting…" cinza auto-resolvível; Gmail "Trying to reconnect… in Ns". Guias websocket.org/oneuptime: "surface the indicator after the first failed retry, not immediately".
- **Resumability por sequence-id** (padrão-ouro, opcional): Discord `RESUME` (session_id+seq), Linear `lastSyncId`, Centrifugo offset+epoch, socket.io `connectionStateRecovery`.
- **Sobreviver a deploy:** AnyCable-Go em produção (ClickFunnels, CoinGecko, Doximity) segura os WS enquanto o Rails reinicia.

## 5. Roadmap F0 → F3

**F0 — Já, barato, mata o sintoma (1 PR, front-only, ~40 linhas, 2-3 arquivos):** 3.1 `connected` callback + 3.2 reopen-on-return + 3.3 debounce + 3.4 catch-up. Zero backend/infra. Resolve visibilitychange, focus, bfcache e sleep-foreground. Validar via Playwright light+dark simulando visibilitychange / `chrome://discards` (Freeze).

**F1 — Higiene/robustez (baixo):** bump `@rails/actioncable` 6.1.3 → ^7.1.5 (casa com server; `recordMessage()`); atenção OOM do Vite (`NODE_OPTIONS=--max-old-space-size=8192`). Verificar por VM: Cloudflare Network→WebSockets = ON; ping de 3s nos WS frames (DevTools); nginx já ok. Heartbeat pong-timeout no `RoomChannel` (Método G) p/ socket zumbi pós-sleep.

**F2 — Estrutural de deploy (médio):** cable standalone ou 2ª réplica web (`chatwoot-web.2` PORT=3001 no `upstream`; Redis adapter já compartilha estado). Trocar `systemctl restart chatwoot.target` por **rolling restart**. Outage total de WS no deploy vira blip de ~50% auto-curável.

**F3 — Teto "any time" real (alto, opcional):** SharedWorker (Método H) e/ou AnyCable-Go + reliable streams (Método I). Só depois de F0-F2. Ressalva AnyCable: no restore o Rails não recebe callbacks disconnect/unsubscribed — revisar presença (`update_presence` 20s / `OnlineStatusTracker`) ou `sessions_ttl:0`.

## 6. Fontes

- Rails ConnectionMonitor (visibilityDidChange→reopen): https://github.com/rails/rails/blob/v6.1.3/actioncable/app/javascript/action_cable/connection_monitor.js
- recordMessage / staleness (rails#42336): https://github.com/rails/rails/issues/42336
- Server PONG / half-open (rails#29307, PR#50039): https://github.com/rails/rails/issues/29307 · https://github.com/rails/rails/pull/50039
- Page Lifecycle API: https://developer.chrome.com/docs/web-platform/page-lifecycle-api
- Timer throttling Chrome 88: https://developer.chrome.com/blog/timer-throttling-in-chrome-88
- Freezing on Energy Saver: https://developer.chrome.com/blog/freezing-on-energy-saver
- bfcache: https://web.dev/articles/bfcache
- Page Visibility API: https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API
- WS reconnection (grace/debounce): https://websocket.org/guides/reconnection/ · https://oneuptime.com/blog/post/2026-01-24-websocket-reconnection-logic/view
- socket.io reconnect-on-focus / connectionStateRecovery: https://socket.io/docs/v4/client-socket-instance/ · https://socket.io/docs/v4/connection-state-recovery
- Cloudflare WebSockets (idle 100s): https://developers.cloudflare.com/network/websockets/
- Safari não emite onclose ao cair rede (WebKit 247943): https://bugs.webkit.org/show_bug.cgi?id=247943
- SharedWorker (Pusher / cable-shared-worker): https://pusher.com/blog/reduce-websocket-connections-with-shared-workers/ · https://github.com/le0pard/cable-shared-worker
- AnyCable reliable streams: https://docs.anycable.io/anycable-go/reliable_streams · https://evilmartians.com/chronicles/enter-anycable-v1-4-reliable-real-time-features-for-apps-of-any-size
- Action Cable standalone / rolling: https://guides.rubyonrails.org/action_cable_overview.html
- Discord gateway RESUME / Linear sync / Centrifugo recovery: https://docs.discord.com/developers/events/gateway · https://github.com/wzhudev/reverse-linear-sync-engine · https://centrifugal.dev/docs/server/history_and_recovery
