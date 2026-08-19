/**
 * FormKit sob demanda — bloco 2.18.
 *
 * O FormKit é usado por UM componente do widget: `PreChat/Form.vue`, na rota
 * `prechat-form`. Mas `entrypoints/widget.js` registrava o plugin no boot, e
 * import estático no entrypoint é o que define o first-paint: a biblioteca
 * inteira era baixada por TODO visitante, inclusive os das inboxes que não têm
 * pré-chat ligado. Medido no grafo: 49.792 B gzip.
 *
 * Aqui o plugin é instalado na primeira vez que a rota do pré-chat monta.
 * `app.use()` não exige ser chamado antes de `mount()` — o que ele exige é
 * rodar antes de o primeiro `<FormKit>` renderizar, e é por isso que a view
 * espera esta promessa antes de desenhar o formulário.
 *
 * A promessa é memorizada (e não um booleano): duas idas à rota em sequência
 * rápida chamariam `app.use()` duas vezes com a segunda ainda no ar.
 */
let promessa = null;

export const garantirFormKit = app => {
  if (promessa) return promessa;
  promessa = (async () => {
    const [
      { plugin, defaultConfig },
      { startsWithPlus, isPhoneNumberValidWithDialCode },
    ] = await Promise.all([
      import('@formkit/vue'),
      import('shared/helpers/Validators'),
    ]);
    app.use(
      plugin,
      defaultConfig({
        rules: {
          startsWithPlus: ({ value }) => startsWithPlus(value),
          isValidPhoneNumber: ({ value }) =>
            isPhoneNumberValidWithDialCode(value),
        },
      })
    );
  })();
  return promessa;
};
