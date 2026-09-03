/**
 * MECANISMO DE ACEITE DO BLOCO 3.15.
 *
 * Aceite (§2.2): "Campo condicional só aparece quando a condição é satisfeita;
 * erro específico por campo."
 *
 * O contrato produtor está fechado pela trilha de pré-chat (3.12/3.13) e vive em
 * `app/models/channel/web_widget/pre_chat_form_schema.rb`. Este arquivo é a ponta
 * CONSUMIDORA dele. Cada vocabulário abaixo foi conferido contra o schema Ruby,
 * não contra o relatório — relatório não é prova.
 */
import ptBR from 'widget/i18n/locale/pt_BR.json';
import en from 'widget/i18n/locale/en.json';
import {
  CONDITION_OPERATORS,
  VALIDATION_MESSAGE_KEYS,
  evaluateCondition,
  fieldErrorFor,
  fieldsForStep,
  maskFieldValue,
  stepsOf,
  visibleFields,
} from '../preChatFieldRules';

const campo = (extra = {}) => ({
  name: 'cpf',
  label: 'CPF',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

describe('3.15 — o widget honra show_if / step / mask / validator', () => {
  describe('vocabulário: bate com o schema Ruby do 3.12', () => {
    it('os quatro operadores, e só eles', () => {
      expect(CONDITION_OPERATORS).toEqual([
        'is',
        'is_not',
        'contains',
        'filled',
      ]);
    });
  });

  describe('as 12 chaves de mensagem existem NAS DUAS línguas', () => {
    // Fecha o buraco que o lint aponta e não consegue verificar: a chave é
    // indexada por código em runtime, então uma que faltasse em `en` só
    // apareceria como texto cru na tela de um visitante estrangeiro.
    const resolve = (dicionario, chave) =>
      chave.split('.').reduce((no, parte) => (no ?? {})[parte], dicionario);

    it.each(Object.entries(VALIDATION_MESSAGE_KEYS))(
      '%s tem texto em pt_BR e em en',
      (code, chave) => {
        expect(typeof resolve(ptBR, chave)).toBe('string');
        expect(resolve(ptBR, chave).length).toBeGreaterThan(0);
        expect(typeof resolve(en, chave)).toBe('string');
        expect(resolve(en, chave).length).toBeGreaterThan(0);
      }
    );

    it('e as duas línguas têm exatamente o mesmo conjunto', () => {
      expect(Object.keys(ptBR.PRE_CHAT_FORM.VALIDATION).sort()).toEqual(
        Object.keys(en.PRE_CHAT_FORM.VALIDATION).sort()
      );
    });
  });

  // ── AS TRÊS FORMAS DO show_if, decididas e testadas ──────────────────────
  //
  // A trilha de pré-chat achou, DEPOIS da suíte verde, que "Sempre mostrar"
  // gravava `show_if: null` contra um schema que declara `type: object` — 422 na
  // operação mais banal. A pergunta equivalente deste lado é o que o widget faz
  // quando a chave chega ausente, nula ou como objeto vazio.
  //
  // PRINCÍPIO, e ele decide as três: condição malformada ou ausente NUNCA esconde
  // campo. Esconder campo obrigatório deixa o visitante com um formulário que não
  // fecha e sem recurso; mostrar campo a mais é incômodo cosmético. A assimetria
  // do dano decide a direção — falha ABERTA.
  describe('as três formas de show_if', () => {
    it('AUSENTE → campo visível (não há condição)', () => {
      expect(visibleFields([campo()], {})).toHaveLength(1);
    });

    it('null → campo visível (o schema recusa gravar, mas o widget não pode sumir)', () => {
      expect(visibleFields([campo({ show_if: null })], {})).toHaveLength(1);
    });

    it('objeto VAZIO → campo visível (falta field e operator: malformada)', () => {
      expect(visibleFields([campo({ show_if: {} })], {})).toHaveLength(1);
    });

    it('condição sem operator, ou com operator fora do vocabulário → visível', () => {
      expect(
        visibleFields([campo({ show_if: { field: 'plano' } })], {})
      ).toHaveLength(1);
      expect(
        visibleFields(
          [
            campo({
              show_if: { field: 'plano', operator: 'regex', value: 'x' },
            }),
          ],
          { plano: 'pro' }
        )
      ).toHaveLength(1);
    });
  });

  describe('condição bem formada: o campo só aparece quando ela é satisfeita', () => {
    const condicional = campo({
      name: 'cnpj',
      show_if: { field: 'tipo', operator: 'is', value: 'empresa' },
    });
    const gatilho = campo({ name: 'tipo' });

    it('escondido enquanto a condição não é satisfeita', () => {
      const visiveis = visibleFields([gatilho, condicional], {
        tipo: 'pessoa',
      });
      expect(visiveis.map(f => f.name)).toEqual(['tipo']);
    });

    it('aparece quando é satisfeita — o aceite literal do bloco', () => {
      const visiveis = visibleFields([gatilho, condicional], {
        tipo: 'empresa',
      });
      expect(visiveis.map(f => f.name)).toEqual(['tipo', 'cnpj']);
    });

    it('gatilho ainda não respondido mantém o dependente escondido', () => {
      expect(
        visibleFields([gatilho, condicional], {}).map(f => f.name)
      ).toEqual(['tipo']);
    });
  });

  describe('os quatro operadores, um a um', () => {
    const comOperador = (operator, value) =>
      evaluateCondition(
        { field: 'x', operator, value },
        { x: 'Empresa Ltda' },
        ['x']
      );

    it('is — compara sem diferenciar caixa nem espaço em volta', () => {
      expect(comOperador('is', 'empresa ltda')).toBe(true);
      expect(comOperador('is', '  Empresa Ltda  ')).toBe(true);
      expect(comOperador('is', 'outra')).toBe(false);
    });

    it('is_not — a negação exata de is', () => {
      expect(comOperador('is_not', 'empresa ltda')).toBe(false);
      expect(comOperador('is_not', 'outra')).toBe(true);
    });

    it('contains — substring, sem diferenciar caixa', () => {
      expect(comOperador('contains', 'LTDA')).toBe(true);
      expect(comOperador('contains', 'MEI')).toBe(false);
    });

    it('filled — ignora value e olha só se há conteúdo', () => {
      expect(
        evaluateCondition({ field: 'x', operator: 'filled' }, { x: 'a' }, ['x'])
      ).toBe(true);
      expect(
        evaluateCondition({ field: 'x', operator: 'filled' }, { x: '   ' }, [
          'x',
        ])
      ).toBe(false);
      expect(
        evaluateCondition({ field: 'x', operator: 'filled' }, {}, ['x'])
      ).toBe(false);
    });

    it('is / is_not / contains SEM value são malformados → falha aberta', () => {
      ['is', 'is_not', 'contains'].forEach(operator => {
        expect(
          evaluateCondition({ field: 'x', operator }, { x: 'a' }, ['x'])
        ).toBe(true);
        expect(
          evaluateCondition({ field: 'x', operator, value: null }, { x: 'a' }, [
            'x',
          ])
        ).toBe(true);
      });
    });
  });

  describe('referência a campo que não existe → falha aberta', () => {
    it('condição apontando para campo inexistente não mata o campo dependente', () => {
      // Um campo cuja condição nunca pode ser satisfeita é indistinguível de
      // erro de digitação na configuração. Mesma assimetria: falha aberta.
      const orfao = campo({
        name: 'cnpj',
        show_if: { field: 'campo_que_nao_existe', operator: 'filled' },
      });
      expect(visibleFields([orfao], {}).map(f => f.name)).toEqual(['cnpj']);
    });

    it('mas campo que existe e está vazio honra a condição (é a feature funcionando)', () => {
      const dependente = campo({
        name: 'cnpj',
        show_if: { field: 'tipo', operator: 'filled' },
      });
      expect(
        visibleFields([campo({ name: 'tipo' }), dependente], {}).map(
          f => f.name
        )
      ).toEqual(['tipo']);
    });
  });

  describe('step — as etapas', () => {
    const fields = [
      campo({ name: 'a', step: 1 }),
      campo({ name: 'b', step: 2 }),
      campo({ name: 'c' }),
    ];

    it('campo sem step é etapa 1 — o default do contrato', () => {
      expect(fieldsForStep(fields, 1).map(f => f.name)).toEqual(['a', 'c']);
    });

    it('a etapa 2 traz só o que é dela', () => {
      expect(fieldsForStep(fields, 2).map(f => f.name)).toEqual(['b']);
    });

    it('stepsOf devolve as etapas ocupadas, ordenadas e sem buraco duplicado', () => {
      expect(stepsOf(fields)).toEqual([1, 2]);
    });

    it('step fora de 1..8 cai na etapa 1 em vez de sumir da tela', () => {
      expect(
        fieldsForStep([campo({ name: 'z', step: 99 })], 1).map(f => f.name)
      ).toEqual(['z']);
      expect(
        fieldsForStep([campo({ name: 'z', step: 0 })], 1).map(f => f.name)
      ).toEqual(['z']);
    });

    it('campo escondido por show_if não conta para as etapas', () => {
      const comCondicao = [
        campo({ name: 'a', step: 1 }),
        campo({
          name: 'b',
          step: 2,
          show_if: { field: 'a', operator: 'is', value: 'sim' },
        }),
      ];
      expect(stepsOf(visibleFields(comCondicao, { a: 'nao' }))).toEqual([1]);
      expect(stepsOf(visibleFields(comCondicao, { a: 'sim' }))).toEqual([1, 2]);
    });
  });

  describe('mask — delega ao helper do 3.13, não reimplementa', () => {
    it('cpf mascara enquanto digita', () => {
      expect(maskFieldValue('52998224725', campo({ mask: 'cpf' }))).toBe(
        '529.982.247-25'
      );
    });

    it('campo sem mask devolve o valor intacto', () => {
      expect(maskFieldValue('52998224725', campo())).toBe('52998224725');
    });

    it('mask fora do vocabulário devolve o valor intacto — não come o que foi digitado', () => {
      expect(maskFieldValue('abc123', campo({ mask: 'banana' }))).toBe(
        'abc123'
      );
    });

    it('mask null e string vazia (que o schema aceita) não quebram', () => {
      expect(maskFieldValue('abc', campo({ mask: null }))).toBe('abc');
      expect(maskFieldValue('abc', campo({ mask: '' }))).toBe('abc');
    });
  });

  describe('validator — erro ESPECÍFICO por campo', () => {
    const t = key => `t:${key}`;

    it('CPF com DV errado devolve erro específico, não a mensagem genérica', () => {
      const erro = fieldErrorFor(
        campo({ validator: 'cpf' }),
        '529.982.247-26',
        {
          t,
        }
      );
      expect(erro).toEqual({
        message: 't:PRE_CHAT_FORM.VALIDATION.CPF',
        severity: 'error',
      });
    });

    it('CPF válido não devolve erro', () => {
      expect(
        fieldErrorFor(campo({ validator: 'cpf' }), '529.982.247-25', { t })
      ).toBeNull();
    });

    it('a regra anti-lixo avisa (warning), não trava o envio', () => {
      // `bcdfg` é lixo pela regra do 3.13 por NÃO TER VOGAL. Escolhido depois de
      // ler a regra: `asdfgh` tem vogal e NÃO é lixo — um fixture que passasse
      // por engano mediria a minha suposição, não o helper.
      const erro = fieldErrorFor(campo({ validator: 'junk_name' }), 'bcdfg', {
        t,
      });
      expect(erro).toEqual({
        message: 't:PRE_CHAT_FORM.VALIDATION.JUNK_NAME',
        severity: 'warning',
      });
    });

    it('nome plausível NÃO é marcado como lixo', () => {
      expect(
        fieldErrorFor(campo({ validator: 'junk_name' }), 'Marina Souza', { t })
      ).toBeNull();
    });

    it('error_message do campo VENCE a mensagem do catálogo', () => {
      const erro = fieldErrorFor(
        campo({ validator: 'cpf', error_message: 'Confira o CPF do titular' }),
        '529.982.247-26',
        { t }
      );
      expect(erro.message).toBe('Confira o CPF do titular');
    });

    it('campo obrigatório vazio devolve o código REQUIRED', () => {
      const erro = fieldErrorFor(campo({ required: true }), '   ', { t });
      expect(erro).toEqual({
        message: 't:PRE_CHAT_FORM.VALIDATION.REQUIRED',
        severity: 'error',
      });
    });

    it('campo ESCONDIDO por show_if não é validado — nem se for obrigatório', () => {
      // Sem isto, um campo condicional obrigatório e invisível trava o envio
      // para sempre, e o visitante não tem o que corrigir.
      const escondido = campo({
        name: 'cnpj',
        required: true,
        show_if: { field: 'tipo', operator: 'is', value: 'empresa' },
      });
      const visiveis = visibleFields([campo({ name: 'tipo' }), escondido], {
        tipo: 'pessoa',
      });
      expect(visiveis.map(f => f.name)).not.toContain('cnpj');
    });
  });
});
