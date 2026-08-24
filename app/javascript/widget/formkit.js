/**
 * FormKit SOB DEMANDA — bloco 2.18.
 *
 * `entrypoints/widget.js` instalava o plugin do FormKit no boot, com
 * `defaultConfig()`, o que trazia `@formkit/core`, `inputs`, `rules`,
 * `validation`, `i18n`, `observer` e `utils` — 203.437 B renderizados no
 * fecho de first-paint de TODO visitante, inclusive dos widgets que nem têm
 * pré-chat ligado, que são a maioria.
 *
 * `components/PreChat/Form.vue` é o único consumidor do FormKit no widget, e
 * só a rota `prechat-form` o monta. O plugin passa a ser instalado no
 * `beforeResolve` dessa rota — que já resolve o componente por `import()`.
 *
 * `app.use()` DEPOIS do `mount()` é legítimo em Vue 3: `createAppAPI#use` não
 * consulta `isMounted`, apenas registra o plugin e chama `install(app)`. O
 * `app.component('FormKit', …)` de dentro do FormKit é lido na hora do
 * render, e o render desta rota ainda não aconteceu quando o guard resolve.
 */

/**
 * As rotas que montam `components/PreChat/Form.vue`.
 *
 * ESTA LISTA TEM DE ACOMPANHAR `widget/router.js`. Uma rota nova que renderize
 * o formulário e não esteja aqui não quebra o build, não quebra o lint e não
 * quebra nenhum teste de componente: quebra o pré-chat no site do cliente, em
 * produção, com o formulário sem os campos. `specs/formKitSobDemanda.spec.js`
 * percorre o grafo de imports de cada rota do widget e ACUSA exatamente isso.
 */
export const ROTAS_COM_FORMKIT = ['prechat-form'];

/**
 * Devolve um `ensureFormKit()` idempotente para este `app`.
 *
 * A promessa é memoizada porque duas navegações rápidas para o pré-chat
 * chamariam o guard duas vezes, e `app.use()` do mesmo plugin duas vezes
 * emite «Plugin has already been applied» no console do site do cliente.
 */
export const criarInstaladorDeFormKit = app => {
  let instalacao = null;

  return () => {
    if (instalacao) return instalacao;

    instalacao = Promise.all([
      import('@formkit/vue'),
      import('../shared/helpers/Validators'),
    ]).then(([{ plugin, defaultConfig }, validators]) => {
      app.use(
        plugin,
        defaultConfig({
          rules: {
            startsWithPlus: ({ value }) => validators.startsWithPlus(value),
            isValidPhoneNumber: ({ value }) =>
              validators.isPhoneNumberValidWithDialCode(value),
          },
        })
      );
    });

    return instalacao;
  };
};
