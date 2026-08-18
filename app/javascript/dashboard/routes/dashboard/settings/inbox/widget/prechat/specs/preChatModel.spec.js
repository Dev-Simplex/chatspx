import {
  MAX_ENABLED_FIELDS,
  MAX_STEPS,
  applyOrder,
  canAddStep,
  conditionSources,
  danglingConditions,
  deriveMode,
  resolveMode,
  disableField,
  enableField,
  enabledCount,
  fieldsOfStep,
  groupByStep,
  isAtFieldLimit,
  isConditionComplete,
  stepCount,
  stepOf,
  toBuilder,
  toSimple,
} from '../preChatModel';

const field = (name, extra = {}) => ({
  name,
  label: name,
  field_type: 'standard',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

// A forma que a frota tem hoje: 3 habilitados e uma cauda de atributos
// personalizados desabilitados, gravados pela tela antiga.
const legacyForm = [
  field('fullName'),
  field('emailAddress', { type: 'email' }),
  field('phoneNumber'),
  ...Array.from({ length: 9 }, (_, i) =>
    field(`attr_${i}`, { enabled: false, field_type: 'contact_attribute' })
  ),
];

describe('preChatModel — teto de campos (aceite 21)', () => {
  it('conta campo habilitado, não entrada do array', () => {
    expect(legacyForm).toHaveLength(12);
    expect(enabledCount(legacyForm)).toBe(3);
    expect(isAtFieldLimit(legacyForm)).toBe(false);
  });

  it('trava exatamente no oitavo campo habilitado', () => {
    const eight = Array.from({ length: 8 }, (_, i) => field(`f${i}`));
    expect(enabledCount(eight)).toBe(MAX_ENABLED_FIELDS);
    expect(isAtFieldLimit(eight)).toBe(true);
    expect(isAtFieldLimit(eight.slice(0, 7))).toBe(false);
  });

  it('o nono campo é impossível: habilitar no teto devolve a lista intacta', () => {
    const full = [
      ...Array.from({ length: 8 }, (_, i) => field(`f${i}`)),
      field('extra', { enabled: false }),
    ];

    const after = enableField(full, 'extra');

    expect(enabledCount(after)).toBe(8);
    expect(after.find(f => f.name === 'extra').enabled).toBe(false);
  });

  it('libera de novo assim que um campo sai', () => {
    const full = Array.from({ length: 8 }, (_, i) => field(`f${i}`));
    const after = disableField(full, 'f0');

    expect(enabledCount(after)).toBe(7);
    expect(isAtFieldLimit(after)).toBe(false);
  });
});

describe('preChatModel — etapas', () => {
  it('campo sem step é da etapa 1', () => {
    expect(stepOf({ name: 'x' })).toBe(1);
    expect(stepOf({ name: 'x', step: 3 })).toBe(3);
  });

  it('conta etapas pelos campos habilitados e para no teto de 8', () => {
    const twoSteps = [field('a'), field('b', { step: 2 })];
    expect(stepCount(twoSteps)).toBe(2);
    expect(canAddStep(twoSteps)).toBe(true);

    const eightSteps = Array.from({ length: 8 }, (_, i) =>
      field(`f${i}`, { step: i + 1 })
    );
    expect(stepCount(eightSteps)).toBe(MAX_STEPS);
    expect(canAddStep(eightSteps)).toBe(false);
  });

  it('etapa vazia no meio não some da lista — o construtor precisa mostrá-la', () => {
    const withGap = [field('a', { step: 1 }), field('c', { step: 3 })];
    const groups = groupByStep(withGap);

    expect(groups.map(g => g.step)).toEqual([1, 2, 3]);
    expect(groups[1].fields).toEqual([]);
    expect(groups[2].fields.map(f => f.name)).toEqual(['c']);
  });

  it('ordena por position; campo sem position vai para o fim, não para a frente', () => {
    const fields = [
      field('c', { position: 2 }),
      field('a', { position: 0 }),
      field('b', { position: 1 }),
      field('d'),
    ];

    expect(fieldsOfStep(fields, 1).map(f => f.name)).toEqual([
      'a',
      'b',
      'c',
      'd',
    ]);
  });

  it('formulário legado inteiro, sem position nenhum, mantém a ordem do array', () => {
    const fields = [field('nome'), field('email'), field('telefone')];

    expect(fieldsOfStep(fields, 1).map(f => f.name)).toEqual([
      'nome',
      'email',
      'telefone',
    ]);
  });

  it('reordenar reescreve position só da etapa mexida', () => {
    const fields = [
      field('a', { position: 0 }),
      field('b', { position: 1 }),
      field('z', { step: 2, position: 0 }),
    ];

    const after = applyOrder(fields, 1, ['b', 'a']);

    expect(after.find(f => f.name === 'b').position).toBe(0);
    expect(after.find(f => f.name === 'a').position).toBe(1);
    expect(after.find(f => f.name === 'z').position).toBe(0);
  });
});

describe('preChatModel — condicional só de etapa anterior (aceite 27)', () => {
  const threeSteps = [
    field('nome', { step: 1 }),
    field('email', { step: 2 }),
    field('cpf', { step: 3 }),
  ];

  it('a etapa 1 não tem de onde depender', () => {
    expect(conditionSources(threeSteps, 1)).toEqual([]);
  });

  it('a etapa 3 vê as etapas 1 e 2, e nunca a si mesma', () => {
    expect(conditionSources(threeSteps, 3).map(f => f.name)).toEqual([
      'nome',
      'email',
    ]);
  });

  it('campo desabilitado não serve de origem — ele não é perguntado', () => {
    const withDisabled = [
      field('nome', { step: 1, enabled: false }),
      field('email', { step: 1 }),
    ];

    expect(conditionSources(withDisabled, 2).map(f => f.name)).toEqual([
      'email',
    ]);
  });

  it('o operador "preenchido" dispensa valor; os outros exigem', () => {
    expect(isConditionComplete({ field: 'a', operator: 'filled' })).toBe(true);
    expect(isConditionComplete({ field: 'a', operator: 'is' })).toBe(false);
    expect(
      isConditionComplete({ field: 'a', operator: 'is', value: ' ' })
    ).toBe(false);
    expect(
      isConditionComplete({ field: 'a', operator: 'is', value: 'sim' })
    ).toBe(true);
    expect(isConditionComplete({ operator: 'filled' })).toBe(false);
  });

  it('nomeia a condicional que ficou apontando para campo que sumiu', () => {
    const broken = [
      field('nome', { step: 1, enabled: false }),
      field('cpf', { step: 2, show_if: { field: 'nome', operator: 'filled' } }),
    ];

    expect(danglingConditions(broken)).toEqual([
      { name: 'cpf', target: 'nome' },
    ]);
  });

  it('desligar um campo limpa a condicional de quem dependia dele', () => {
    const fields = [
      field('nome', { step: 1 }),
      field('cpf', { step: 2, show_if: { field: 'nome', operator: 'filled' } }),
    ];

    const after = disableField(fields, 'nome');

    expect(after.find(f => f.name === 'cpf').show_if).toBeUndefined();
    expect(danglingConditions(after)).toEqual([]);
  });
});

describe('preChatModel — os modos e a migração (aceite 28)', () => {
  it('lê Simples quando não há etapa, condicional, máscara nem validador', () => {
    expect(deriveMode({ pre_chat_fields: legacyForm })).toBe('simple');
    expect(deriveMode({})).toBe('simple');
  });

  it('lê Construtor quando qualquer recurso avançado está em uso', () => {
    expect(deriveMode({ pre_chat_fields: [field('a', { step: 2 })] })).toBe(
      'builder'
    );
    expect(deriveMode({ pre_chat_fields: [field('a', { mask: 'cpf' })] })).toBe(
      'builder'
    );
    expect(
      deriveMode({ pre_chat_fields: [field('a', { validator: 'cpf' })] })
    ).toBe('builder');
    expect(
      deriveMode({
        pre_chat_fields: [
          field('a', { show_if: { field: 'b', operator: 'filled' } }),
        ],
      })
    ).toBe('builder');
  });

  it('o modo gravado ganha do derivado — a intenção do admin não é adivinhada', () => {
    const simpleContent = { mode: 'builder', pre_chat_fields: legacyForm };

    expect(deriveMode(simpleContent)).toBe('simple');
    expect(resolveMode(simpleContent)).toBe('builder');
  });

  it('sem modo gravado — o caso de toda a frota hoje — vale o derivado', () => {
    expect(resolveMode({ pre_chat_fields: legacyForm })).toBe('simple');
    expect(resolveMode({ pre_chat_fields: [field('a', { step: 2 })] })).toBe(
      'builder'
    );
  });

  it('modo fora do enum cai no derivado, e não trava a tela num modo ingravável', () => {
    expect(resolveMode({ mode: 'avancado', pre_chat_fields: legacyForm })).toBe(
      'simple'
    );
  });

  it('o modo Fluxo é um dos três e sobrevive ao resolve', () => {
    expect(resolveMode({ mode: 'flow', pre_chat_fields: legacyForm })).toBe(
      'flow'
    );
  });

  it('Simples → Construtor não perde campo e explicita etapa e posição', () => {
    const after = toBuilder(legacyForm);

    expect(after).toHaveLength(legacyForm.length);
    expect(enabledCount(after)).toBe(3);
    expect(after.slice(0, 3).map(f => [f.step, f.position])).toEqual([
      [1, 0],
      [1, 1],
      [1, 2],
    ]);
    // O que estava desligado continua desligado e sem step inventado.
    expect(after[3]).toEqual(legacyForm[3]);
  });

  it('Construtor → Simples não apaga campo, e devolve o que a volta custa', () => {
    const builder = [
      field('nome', { step: 1 }),
      field('email', { step: 2 }),
      field('cpf', { step: 3, show_if: { field: 'nome', operator: 'filled' } }),
      field('desligado', { step: 2, enabled: false }),
    ];

    const { fields, ignoredSteps, droppedConditions } = toSimple(builder);

    expect(fields).toHaveLength(4);
    expect(enabledCount(fields)).toBe(3);
    expect(fields.filter(f => f.enabled).map(f => f.step)).toEqual([1, 1, 1]);
    expect(fields.find(f => f.name === 'cpf').show_if).toBeUndefined();
    expect(ignoredSteps).toEqual([2, 3]);
    expect(droppedConditions).toEqual(['cpf']);
  });

  it('ida e volta Simples → Construtor → Simples devolve os mesmos campos', () => {
    const roundTrip = toSimple(toBuilder(legacyForm)).fields;

    expect(roundTrip.map(f => f.name)).toEqual(legacyForm.map(f => f.name));
    expect(roundTrip.filter(f => f.enabled).map(f => f.name)).toEqual([
      'fullName',
      'emailAddress',
      'phoneNumber',
    ]);
  });
});
