import EditHook from '../EditHook.vue';

// ChatSPX (item 26) — o lado do FRONT do defeito "editar integração apaga a credencial".
//
// O upstream passou a filtrar `settings` por `app.visible_properties` no `_hook.json.jbuilder`.
// Isolado isso é mais seguro: não devolve segredo no JSON. Mas esta tela é 100% do fork (o
// upstream não tem tela de editar hook) e foi escrita quando `hook.settings` vinha completo: ela
// gravava '' no campo que chegou `undefined` e reenviava tudo, e o `update!` sobrescrevia o jsonb.
// Resultado: a credencial era destruída no banco, com 200 OK e sem log.
//
// Os métodos são options API puros, então dá para exercitá-los com um `this` sintético — sem
// montar o componente (que puxa store e o composable useIntegrationHook) e sem navegador.
const { settingKeysMissingFromServer, parseInitialValues, buildHookPayload } =
  EditHook.methods;

// openai depois do merge: `visible_properties` é ['label_suggestion'], então a resposta do
// servidor NÃO traz `api_key`, embora ela exista gravada no banco.
const FORM_SCHEMA = [
  { name: 'api_key', label: 'API Key', type: 'text', validation: 'required' },
  { name: 'label_suggestion', label: 'Label suggestion', type: 'checkbox' },
];

const buildContext = (settingsFromServer, typedValues = null) => {
  const context = {
    hook: { id: 7, settings: settingsFromServer },
    integration: { settings_form_schema: FORM_SCHEMA },
    formItems: FORM_SCHEMA,
  };
  context.keysMissingFromServer = settingKeysMissingFromServer.call(context);
  context.values = typedValues ?? parseInitialValues.call(context);
  return context;
};

describe('EditHook — não reenviar chave que o servidor não devolveu', () => {
  it('identifica como ausente a chave filtrada por visible_properties', () => {
    const context = buildContext({ label_suggestion: false });

    expect(context.keysMissingFromServer).toEqual(['api_key']);
    // O form continua mostrando o campo vazio — é isso que tornava o reenvio destrutivo.
    expect(context.values).toEqual({ api_key: '', label_suggestion: false });
  });

  it('omite do payload a credencial que o usuário não digitou', () => {
    const context = buildContext({ label_suggestion: false });
    context.values.label_suggestion = true;

    const payload = buildHookPayload.call(context);

    // A asserção que pega o defeito: antes, o payload trazia `api_key: ''`.
    expect(payload).toEqual({ settings: { label_suggestion: true } });
    expect('api_key' in payload.settings).toBe(false);
  });

  it('envia a credencial quando o usuário realmente digita uma nova', () => {
    const context = buildContext({ label_suggestion: false });
    context.values.api_key = 'sk-nova';

    expect(buildHookPayload.call(context)).toEqual({
      settings: { api_key: 'sk-nova', label_suggestion: false },
    });
  });

  it('reenvia normalmente a chave que o servidor devolveu, inclusive vazia', () => {
    // `label_suggestion` é visível: esvaziá-la é intenção do usuário, não resíduo do filtro.
    const context = buildContext({ label_suggestion: 'ligado' });
    context.values.label_suggestion = '';

    expect(buildHookPayload.call(context)).toEqual({
      settings: { label_suggestion: '' },
    });
  });

  it('não quebra o parse de campo JSON quando ele é omitido do payload', () => {
    // dialogflow: `credentials` é JSON e também some da resposta. Antes, `JSON.parse('')`
    // levantaria SyntaxError ao montar o payload de um campo que sequer deve ser enviado.
    const jsonSchema = [
      { name: 'project_id', type: 'text' },
      { name: 'credentials', type: 'textarea', validation: 'JSON' },
    ];
    const context = {
      hook: { id: 9, settings: { project_id: 'proj-1' } },
      integration: { settings_form_schema: jsonSchema },
      formItems: jsonSchema,
    };
    context.keysMissingFromServer = settingKeysMissingFromServer.call(context);
    context.values = parseInitialValues.call(context);

    expect(context.keysMissingFromServer).toEqual(['credentials']);
    expect(buildHookPayload.call(context)).toEqual({
      settings: { project_id: 'proj-1' },
    });
  });
});
