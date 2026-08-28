import net from 'node:net';

/**
 * Uma porta livre e EXCLUSIVA para o socket de HMR de um harness Vite.
 *
 * ── O defeito que isto conserta ───────────────────────────────────────────────
 *
 * `server.hmr: false` NÃO desliga o socket de HMR quando o Vite roda em
 * `middlewareMode`. Em `vite/dist/node` a decisão é esta:
 *
 *     const hmr = isObject(config.server.hmr) && config.server.hmr;  // false
 *     const hmrPort = hmr && hmr.port;                               // false
 *     const port = hmrPort || 24678;                                 // 24678
 *
 * Ou seja: com `hmr: false` o Vite cai no DEFAULT 24678 e sobe ali um servidor
 * WebSocket próprio — em `*:24678`, todas as interfaces. E o documento dos
 * harness carrega `/@vite/client` de propósito (é ele que injeta o CSS em modo
 * dev; sem ele a página não tem estilo, e medir cor sem estilo não mede nada).
 *
 * Com DOIS harness assim vivos na mesma execução — `capture/` e `citacao/`, que
 * são o mesmo projeto `widget` do `playwright.config.js` —, o segundo não
 * consegue subir e imprime `WebSocket server error: Port 24678 is already in
 * use`. O `/@vite/client` dele então aperta a mão com o socket do PRIMEIRO, cujo
 * token é outro, e leva `Unexpected response code: 400`. Isso vira
 * `console.error` + `pageerror`, e o fixture anti-erro (bloco 0.11) reprova o
 * teste — por um defeito de harness, não do produto.
 *
 * Reproduzido em 28/08 subindo os dois harness no mesmo processo: o `capture`
 * fica com `*:24678` e o `citacao` imprime o "already in use".
 *
 * Porta ZERO não serve como atalho: `hmrPort || 24678` trata `0` como ausente e
 * volta ao default. Por isso pedimos ao sistema uma porta livre aqui e passamos
 * o NÚMERO adiante.
 *
 * O mesmo vale entre worktrees: como o socket nasce em `*:` (todas as
 * interfaces), duas cópias do repositório rodando a suíte ao mesmo tempo
 * disputariam a 24678 uma da outra.
 */
export const portaHmrLivre = () =>
  new Promise((resolve, reject) => {
    const sonda = net.createServer();
    sonda.unref();
    sonda.on('error', reject);
    sonda.listen(0, '127.0.0.1', () => {
      const { port } = sonda.address();
      sonda.close(() => resolve(port));
    });
  });

export default portaHmrLivre;
