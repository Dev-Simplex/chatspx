# KICKOFF — Execução autônoma: Agente ChatSPX "sempre conectado" (F0 + aviso offline em níveis)

> Plano executável **fim-a-fim**, pensado pra rodar autônomo (agente ou `/loop`) com **loop de auto-validação**.
> Base técnica e "porquê": `plano/plano-agente-sempre-conectado.md` (pesquisa multiagente 2026-07-10).
> Escopo desta execução: **SÓ FRONT** (zero backend, zero infra). Ambiente: `.232` (homologação). Data: 2026-07-10.

---

## 0. Objetivo & definição de "pronto"
Acabar com o banner **"Desconectado" preso** ao voltar de aba em background/idle, E — quando estiver offline **de verdade** — mostrar um aviso **prominente** (barra full-width no topo, padrão WhatsApp Web/Slack/Gmail), **sem bloquear** o trabalho.
**Pronto** = todos os critérios de aceite (§6) verdes no Playwright **light+dark**, na homolog, sem regressão, com o WIP do Paulo/Nicolas intocado.

## 1. Decisões travadas (não reabrir)
- **F0 (4 mudanças):** (B) callback `connected` na subscription; (C) reopen-on-return (`visibilitychange`+`focus`+`pageshow` persisted); (A) debounce/grace no banner; (D) REST catch-up no retorno.
- **Aviso offline em NÍVEIS** (escalada, igual às empresas — confirmado na pesquisa: WhatsApp Web barra amarela no topo, Slack escala quando sustentado, Gmail "reconnecting… / offline"):
  - **N0** (`< 2.5s` caído): **nada** (grace).
  - **N1** (`2.5s–8s`): **pill discreto** atual "Reconectando…" (topo-esquerda).
  - **N2** (`> 8s`, sustentado): **barra full-width no topo** "Sem conexão em tempo real · reconectando…" (âmbar), **não-bloqueante**, some ao reconectar. ← o "mais visual" pedido.
  - **Reconectou:** "Reconectado" ~2s e some (já existe).
- **Composer:** hint sutil "Offline — sua mensagem será enviada ao reconectar" quando N2; **NÃO desabilitar o envio** — o ChatSPX já tem envio otimista + `reconcilePendingMessages` (o `ReconnectService` reenvia sozinho ao voltar), então travar seria PIOR.
- ❌ Sem modal central. ❌ Sem toast. ❌ Sem bloqueio do composer.
- Thresholds em **constantes tunáveis**: `GRACE_MS=2500`, `SUSTAINED_MS=8000`.

## 2. Pré-condições / ambiente (LER antes de tocar)
- Branch alvo: `homologacao` (origin). O working tree local da `.232` está **sujo com WIP do Paulo/Nicolas** → **NÃO commitar o working tree direto**. Commit via **worktree limpa do `origin/homologacao`** + `git -c core.hooksPath=/dev/null` (husky quebrado: `.husky/_/husky.sh` ausente).
- **Antes de editar**, confirmar que os arquivos-alvo NÃO estão no WIP (`git status --short <arquivo>`); se algum estiver → **PARAR e avisar**.
- Playwright: script node com `require('/home/chatwoot/chatwoot/node_modules/playwright')`, headless `--no-sandbox`; user de teste dedicado `playwright-test@simplex.local` / `Test123456!` (conta 3) — **NUNCA** resetar senha de conta real; login via `input[name=email_address]` + `input[name=password]`.
- Build front: `NODE_OPTIONS=--max-old-space-size=8192` (OOM do Vite) + **conferir `public/vite/.vite/manifest.json` mtime novo** (exit 0 do precompile mente).
- Validar **light E dark** + DOM walker (sem i18n leak, ícones certos, contraste).

## 3. Implementação (passo a passo — snippets exatos em `plano/plano-agente-sempre-conectado.md §3`)
### Passo 1 — `app/javascript/shared/helpers/BaseActionCableConnector.js`
- Callback `connected` na subscription (ao lado de `disconnected:`, L47): `reconnectAttempts=0` + `clearReconnectTimer()` + `checkConnection()`.
- Na cauda do constructor (após L68): `handleReturnToForeground` (gate `if (!conn.isOpen()) conn.reopen()` + reset backoff + `checkConnection()` + `window.reconnectService?.handleRouteSpecificFetch?.()`) e listeners `visibilitychange`/`focus`/`pageshow(persisted)`.
- Cleanup dos 3 listeners em `disconnect()` (L134-146) — guardar refs.

### Passo 2 — estado em NÍVEIS — `app/javascript/dashboard/components/NetworkNotification.vue` (+ novo `ConnectionStatusBar.vue`)
- Trocar `updateWebsocketStatus` (L56-59) por **grace cancelável** (`GRACE_MS`) → N1; adicionar 2º timer (`SUSTAINED_MS`) que seta `isSustained=true` → N2. Cancelar ambos em `handleReconnecting`, `handleReconnectionCompleted`, `onBeforeUnmount`.
- **N1** = pill atual (discreto). **N2** = **barra full-width no topo** — criar `components-next/banner/ConnectionStatusBar.vue` (âmbar, `role="status"` `aria-live="polite"`, light+dark), montar no shell (`App.vue`, acima do conteúdo — sticky/topo). O pill vira N1; a barra é N2.
- i18n: `NETWORK.NOTIFICATION.SUSTAINED_OFFLINE` (pt: "Sem conexão em tempo real · reconectando…") em `en` **e** `pt_BR`.

### Passo 3 — hint no composer (SEM bloqueio)
- `grep -rl "ReplyBox\|composer" app/javascript/dashboard` → achar o componente do campo de resposta. Ler o estado de conexão sustentada (via store/emitter/`BUS_EVENTS`). Quando N2: faixa sutil acima do input "Offline — sua mensagem será enviada ao reconectar". **Não** desabilitar o botão enviar.
- i18n: `CONVERSATION.REPLYBOX.OFFLINE_HINT` en + pt_BR.

### Passo 4 — catch-up + bônus
- Catch-up já vem do `handleReturnToForeground` (Passo 1). Bônus barato: estender `handleOnlineEvent` (`ReconnectService.js:46-50`) p/ também disparar reconnect-check imediato no evento `online`.

## 4. LOOP de validação (auto-heal — máx **5** iterações)
Repetir até TODOS os aceites (§6) verdes **OU** 5 iterações:
1. `eslint --fix` nos arquivos tocados (0 erros).
2. Build front (vite dev em porta isolada OU `NODE_OPTIONS=8192 rake assets:precompile`) — conferir manifest mtime novo.
3. Playwright (**light E dark**) simulando, via `emitter.emit(BUS_EVENTS.WEBSOCKET_DISCONNECT/_RECONNECT/_RECONNECT_COMPLETED)` e eventos DOM:
   - (a) micro-queda `<2.5s` → banner **NÃO** aparece.
   - (b) queda 3–5s → **N1** (pill).
   - (c) queda `>8s` → escala pra **N2** (barra topo) + hint no composer.
   - (d) voltar de aba (`visibilitychange visible` / `focus` / `pageshow persisted`) → reconecta na hora, N1/N2 somem, refetch dispara.
   - (e) enviar mensagem em N2 → **não** bloqueado.
4. Falhou algum → ler o erro, **corrigir o arquivo**, voltar ao passo 1 (self-heal).
5. 5 iterações sem fechar → **PARAR**, salvar screenshots+logs no scratchpad, reportar o que travou (não forçar).

## 5. Commit + deploy (após LOOP verde)
- Patch dos arquivos tocados → aplicar em **worktree limpa** de `origin/homologacao` → commit `feat(realtime): reconecta ao voltar à aba + aviso offline escalonado (fim do "Desconectado" preso)` com `core.hooksPath=/dev/null` → `push origin homologacao`.
- Revalidar na homolog rodando (chatspx.app) após precompile+restart.
- **Produção = NÃO auto-deploy.** É FRONT → exige precompile. Cherry-pick **só desse commit** p/ `producao` (worktree) + push; entregar o **prompt de deploy** pra `.229` (git pull + `NODE_OPTIONS=8192 assets:precompile` + conferir manifest mtime + restart; frota via `deploy.sh`, Tozi incluída, FABRICA fora). **Aguardar aval do Walisson antes da frota.**

## 6. Critérios de aceite (checklist)
- [ ] Voltar de aba (troca de aba / foco / bfcache) reconecta em `<1s` e o banner **não** fica preso.
- [ ] Máquina "dormindo" com aba em foreground → ao mexer (`focus`) reconecta.
- [ ] Reconexão `<2.5s` → banner nunca acende.
- [ ] Queda 2.5–8s → **N1** discreto.
- [ ] Queda `>8s` → **N2** barra topo full-width (light+dark, i18n pt/en, a11y `aria-live`).
- [ ] Composer em N2 → hint sutil, envio **não** bloqueado, msg reenvia ao voltar.
- [ ] Sem regressão: presence, stale-watchdog, refetch-on-reconnect OK; specs `ReconnectService`/`actionCable` verdes.
- [ ] WIP Paulo/Nicolas intocado.

## 7. Rollback
`git revert <commit>` + redeploy (front → precompile+restart). Zero migration, zero infra → rollback trivial e seguro.

## 8. Riscos & mitigação
- Vite OOM → `NODE_OPTIONS=8192` + checar manifest mtime (senão bundle velho).
- Husky quebrado → `core.hooksPath=/dev/null` / `--no-verify`.
- Working tree sujo → worktree limpa + patch (nunca commit direto).
- Corrida com o `visibilityDidChange` interno da lib → gate `if (!conn.isOpen())`.
- Throttling real → testar também via `chrome://discards` (Freeze), além do `visibilitychange` simulado.
- Barra N2 cobrir o topbar → montar no fluxo do layout (empurrar) ou z-index/altura conferidos no Playwright.

## 9. Como rodar autônomo
Um agente (ou `/loop`) executa **§3 → §4 (loop self-heal até verde ou 5x) → §5 (só até o push na homolog) → PARA e reporta**. Sem pausa humana **dentro** do loop; a única pausa obrigatória é **antes do deploy de produção/frota** (aval do Walisson). Nenhum passo toca produção nem WIP alheio.
