# Cache Stale no Frontend ChatSPX — Investigação 2026-04-19

**Contexto**: servidor HML serve bundles novos (`dashboard-D1U_11Tr.js` / `dashboard-CIglcyQ6.css`), headers corretos (`max-age=0, private, must-revalidate` no HTML, hash no asset), confirmado via Playwright headless. Walisson continua vendo versão antiga.

## Causas NAO-obvias investigadas

### 1. Cloudflare / CDN em front do Nginx — DESCARTADO
DNS `hmlchat.simplexsolucoes.com.br` -> CNAME `simplexti.ddns.net` -> A `177.65.155.246` (IP direto Simplex, HostGator NS). Response headers NAO tem `cf-ray`, `cf-cache-status`, `via`, `x-cache`. Nao ha CDN intermediario. Hipotese eliminada. Validar: `dig +short hmlchat.simplexsolucoes.com.br` (ja feito).

### 2. Service Worker residual — **CAUSA RAIZ MUITO PROVAVEL**
`/home/chatwoot/chatwoot/public/sw.js` existe e e servido publicamente com `cache-control: public, max-age=31556952` (1 ano). `app/javascript/dashboard/App.vue:147` chama `verifyServiceWorkerExistence()` no mount do dashboard, que invoca `navigator.serviceWorker.register('/sw.js')` (ver `app/javascript/dashboard/helper/pushHelper.js:18`). Qualquer sessao passada do Walisson instalou esse SW. Ele intercepta requests e pode servir assets antigos pre-cacheados, e o proprio `sw.js` so re-fetcha a cada 24h. Ctrl+Shift+R NAO desregistra SW — so bypassa HTTP cache do browser.
Ref: https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers e https://gist.github.com/Rich-Harris/fd6c3c73e6e707e312d7c5d7d0f3b2f9
**Validar**: F12 -> Application -> Service Workers. Se aparecer `sw.js` registrado para o dominio -> clicar **Unregister** + **Clear storage**.

### 3. DevTools "Disable cache" so com DevTools aberto — CONFIRMADO
A flag "Disable cache" na aba Network so tem efeito enquanto a janela DevTools estiver **aberta** (pode ficar undocked/minimizada). Fechou -> cache volta. Fonte oficial: https://developer.chrome.com/blog/devtools-tips-36
**Validar**: abrir DevTools, marcar "Disable cache" na Network tab, deixar aberto e recarregar.

### 4. HSTS + includeSubDomains — DESCARTADO para cache de assets
HSTS (`max-age=31536000; includeSubDomains`) so forca HTTPS, NAO cacheia HTML/CSS/JS. Nao causa stale content.
Ref: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security

### 5. Vite Ruby manifest.json desync — POSSIVEL mas improvavel aqui
Bug conhecido: precompile pode gerar hashes diferentes em builds sucessivos, e `rails assets:clobber` e necessario quando manifest fica stale.
Ref: https://github.com/ElMassimo/vite_ruby/issues/362
**Validar no servidor**: `grep dashboard /home/chatwoot/chatwoot/public/vite/.vite/manifest.json` — ja confirmou que bate com o bundle servido, entao nao e esse o caso.

### 6. Nginx proxy_cache — DESCARTADO
Chatwoot nginx padrao NAO usa `proxy_cache` para HTML. Response header nao tem `x-cache` nem `age`. Nao ha layer extra.
Ref: https://blog.nginx.org/blog/nginx-caching-guide

### 7. Browser extensions (uBlock/Stylus/Dark Reader) — POSSIVEL
Extensoes que injetam CSS proprio podem sobrescrever variaveis Tailwind. Dark Reader e famoso por "sequestrar" cores em dashboards.
Ref: https://news.ycombinator.com/item?id=38098424
**Validar**: abrir o site em janela **Incognito** (extensoes desabilitadas por default) e comparar.

### 8. Proxy corporativo Simplex — POSSIVEL
Maquina dele pode estar atras de squid/pfSense com cache proprio. Mas como assets tem hash unico no filename, so HTML seria afetado — e ja serve `must-revalidate`.
**Validar**: `curl -sI https://hmlchat.simplexsolucoes.com.br` na maquina dele e comparar `etag` com o do servidor.

---

## RECOMENDACAO FINAL PARA WALISSON — EXECUTAR NESTA ORDEM

**Passo 1 — Desregistrar Service Worker (99% chance de ser isso):**
Chrome -> F12 -> aba **Application** -> **Service Workers** (menu lateral) -> se aparecer `sw.js` -> clicar **Unregister**. Logo abaixo, **Storage** -> **Clear site data** (marcar tudo) -> **Clear site data**.

**Passo 2 — Limpar cache completo do dominio:**
`chrome://settings/content/all` -> buscar `hmlchat.simplexsolucoes.com.br` -> **Delete** (apaga cookies + storage + cache daquele site so).

**Passo 3 — Testar em Incognito com DevTools:**
Ctrl+Shift+N (Incognito) -> F12 antes de navegar -> aba **Network** -> marcar **Disable cache** -> ir em `https://hmlchat.simplexsolucoes.com.br` -> logar -> confirmar visualmente. Se em Incognito aparecer novo e na janela normal nao -> e cache local 100% confirmado.

---

## Sources

- [MDN — Using Service Workers](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers)
- [Rich-Harris — Stuff I wish I'd known about service workers](https://gist.github.com/Rich-Harris/fd6c3c73e6e707e312d7c5d7d0f3b2f9)
- [Chrome DevTools Tips — Caching Demystified](https://developer.chrome.com/blog/devtools-tips-36)
- [vite_ruby issue #362 — different hashes](https://github.com/ElMassimo/vite_ruby/issues/362)
- [MDN — Strict-Transport-Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security)
- [Vite PWA — Unregister Service Worker](https://vite-pwa-org.netlify.app/guide/unregister-service-worker)
- [love2dev — How to uninstall a service worker](https://love2dev.com/blog/how-to-uninstall-a-service-worker/)
