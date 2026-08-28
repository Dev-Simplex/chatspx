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

  // ── O GATILHO É O VALOR, NÃO A CHAVE ────────────────────────────────────
  //
  // O que o formulário GUARDA e o que a pessoa LEU não são a mesma coisa em dois
  // dos oito tipos de campo do painel (`custom_attribute_definition.rb:58`):
  //
  //   `list`      → o FormKit guarda a POSIÇÃO na lista ('0', '1', …), porque
  //                 `getOptions` monta as opções indexadas por posição.
  //   `checkbox`  → o FormKit guarda um BOOLEANO, não texto.
  //
  // E o `value` da condicional é um campo de texto livre no painel
  // (`ConditionEditor.vue:112`, um `Input`, sem enum e sem tipo): quem configura
  // digita "Empresa", que é o que está escrito na tela. Comparar "Empresa" com
  // '0' nunca casa — o campo condicional simplesmente não aparece, e nada avisa.
  //
  // Estes testes usam a forma REAL dos três gatilhos, e não `type: 'text'`.
  describe('o gatilho resolve o VALOR antes de comparar', () => {
    const dependente = extra =>
      campo({
        name: 'cnpj',
        show_if: { field: 'tipo', operator: 'is', value: 'Empresa', ...extra },
      });

    const nomes = (fields, values) =>
      visibleFields(fields, values).map(f => f.name);

    describe('gatilho de LISTA (type: list) — o painel grava a posição', () => {
      const gatilho = campo({
        name: 'tipo',
        label: 'Tipo',
        type: 'list',
        values: ['Empresa', 'Pessoa física'],
      });

      it('posição 0 É "Empresa": o dependente aparece', () => {
        expect(nomes([gatilho, dependente()], { tipo: '0' })).toEqual([
          'tipo',
          'cnpj',
        ]);
      });

      it('posição 1 não é "Empresa": o dependente some', () => {
        expect(nomes([gatilho, dependente()], { tipo: '1' })).toEqual(['tipo']);
      });

      it('is_not compara o rótulo, então NÃO inverte por causa da posição', () => {
        const condicional = dependente({ operator: 'is_not' });
        expect(nomes([gatilho, condicional], { tipo: '0' })).toEqual(['tipo']);
        expect(nomes([gatilho, condicional], { tipo: '1' })).toEqual([
          'tipo',
          'cnpj',
        ]);
      });

      it('contains procura dentro do rótulo, não dentro do número', () => {
        const condicional = dependente({
          operator: 'contains',
          value: 'física',
        });
        expect(nomes([gatilho, condicional], { tipo: '1' })).toEqual([
          'tipo',
          'cnpj',
        ]);
        expect(nomes([gatilho, condicional], { tipo: '0' })).toEqual(['tipo']);
      });

      it('lista não respondida ("") não está preenchida', () => {
        const condicional = dependente({ operator: 'filled' });
        expect(nomes([gatilho, condicional], { tipo: '' })).toEqual(['tipo']);
        expect(nomes([gatilho, condicional], { tipo: '0' })).toEqual([
          'tipo',
          'cnpj',
        ]);
      });

      it('posição fora da lista devolve o valor cru — falha aberta, não some', () => {
        // Lista encurtada no painel depois de o visitante já ter respondido.
        const condicional = dependente({
          operator: 'is_not',
          value: 'Empresa',
        });
        expect(nomes([gatilho, condicional], { tipo: '9' })).toEqual([
          'tipo',
          'cnpj',
        ]);
      });

      it('o rótulo gravado direto (payload legado) continua casando', () => {
        expect(nomes([gatilho, dependente()], { tipo: 'Empresa' })).toEqual([
          'tipo',
          'cnpj',
        ]);
      });
    });

    describe('gatilho de SELECT — o mesmo campo, com o type que o widget usa', () => {
      const gatilho = campo({
        name: 'tipo',
        label: 'Tipo',
        type: 'select',
        values: ['Empresa', 'Pessoa física'],
      });

      it('posição 0 É "Empresa"', () => {
        expect(nomes([gatilho, dependente()], { tipo: '0' })).toEqual([
          'tipo',
          'cnpj',
        ]);
      });

      it('posição 1 não é', () => {
        expect(nomes([gatilho, dependente()], { tipo: '1' })).toEqual(['tipo']);
      });
    });

    describe('gatilho de CAIXA (type: checkbox) — o FormKit guarda booleano', () => {
      const gatilho = campo({
        name: 'aceito',
        label: 'Aceito ser contatado',
        type: 'checkbox',
      });
      const caixa = extra =>
        campo({
          name: 'cnpj',
          show_if: { field: 'aceito', operator: 'filled', ...extra },
        });

      it('DESMARCADO não está preenchido — `false` não é conteúdo', () => {
        expect(nomes([gatilho, caixa()], { aceito: false })).toEqual([
          'aceito',
        ]);
      });

      it('nunca tocado também não está preenchido', () => {
        expect(nomes([gatilho, caixa()], {})).toEqual(['aceito']);
      });

      it('MARCADO está preenchido', () => {
        expect(nomes([gatilho, caixa()], { aceito: true })).toEqual([
          'aceito',
          'cnpj',
        ]);
      });

      it('is com afirmativo casa com a caixa marcada', () => {
        const condicional = caixa({ operator: 'is', value: 'sim' });
        expect(nomes([gatilho, condicional], { aceito: true })).toEqual([
          'aceito',
          'cnpj',
        ]);
        expect(nomes([gatilho, condicional], { aceito: false })).toEqual([
          'aceito',
        ]);
      });

      it('is com negativo casa com a caixa desmarcada', () => {
        const condicional = caixa({ operator: 'is', value: 'não' });
        expect(nomes([gatilho, condicional], { aceito: false })).toEqual([
          'aceito',
          'cnpj',
        ]);
        expect(nomes([gatilho, condicional], { aceito: true })).toEqual([
          'aceito',
        ]);
      });

      it('is_not é a negação exata', () => {
        const condicional = caixa({ operator: 'is_not', value: 'true' });
        expect(nomes([gatilho, condicional], { aceito: false })).toEqual([
          'aceito',
          'cnpj',
        ]);
        expect(nomes([gatilho, condicional], { aceito: true })).toEqual([
          'aceito',
        ]);
      });

      it('texto que não é sim nem não numa caixa → falha aberta', () => {
        // "Empresa" numa caixa de seleção é engano de configuração: a condição
        // não teria como ser satisfeita nunca. Mostra.
        const condicional = caixa({ operator: 'is', value: 'Empresa' });
        expect(nomes([gatilho, condicional], { aceito: false })).toEqual([
          'aceito',
          'cnpj',
        ]);
      });
    });
  });

  describe('os quatro operadores, um a um', () => {
    // O terceiro parâmetro são os CAMPOS, e não os nomes: o gatilho precisa
    // trazer o `type` para o valor ser resolvido antes da comparação.
    const gatilhoTexto = [{ name: 'x', type: 'text' }];
    const comOperador = (operator, value) =>
      evaluateCondition(
        { field: 'x', operator, value },
        { x: 'Empresa Ltda' },
        gatilhoTexto
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
      const preenchido = values =>
        evaluateCondition(
          { field: 'x', operator: 'filled' },
          values,
          gatilhoTexto
        );

      expect(preenchido({ x: 'a' })).toBe(true);
      expect(preenchido({ x: '   ' })).toBe(false);
      expect(preenchido({})).toBe(false);
    });

    it('is / is_not / contains SEM value são malformados → falha aberta', () => {
      ['is', 'is_not', 'contains'].forEach(operator => {
        expect(
          evaluateCondition({ field: 'x', operator }, { x: 'a' }, gatilhoTexto)
        ).toBe(true);
        expect(
          evaluateCondition(
            { field: 'x', operator, value: null },
            { x: 'a' },
            gatilhoTexto
          )
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

  // ── `position`: a ordem do painel é a ordem do visitante ────────────────
  //
  // `position` é gravado pelo painel (`preChatModel.js#reorderStep`) e é ele que
  // define a ordem que o administrador VÊ ao arrastar os campos. O widget o
  // ignorava: renderizava na ordem do array, então arrastar um campo na tela de
  // configuração não mudava nada no site do cliente.
  //
  // A regra é a MESMA do painel (`preChatModel.js#fieldsOfStep`), copiada com o
  // porquê junto: campo sem `position` vai para o FIM, porque a tela antiga não
  // grava a chave e tratar ausência como zero embaralharia o formulário inteiro
  // na primeira reordenação.
  describe('position — a ordem que o painel mostra é a que o visitante vê', () => {
    it('ordena por position dentro da etapa', () => {
      const fields = [
        campo({ name: 'b', position: 1 }),
        campo({ name: 'a', position: 0 }),
      ];

      expect(fieldsForStep(fields, 1).map(f => f.name)).toEqual(['a', 'b']);
    });

    it('campo SEM position vai para o FIM, nunca para a frente', () => {
      const fields = [
        campo({ name: 'legado' }),
        campo({ name: 'ordenado', position: 0 }),
      ];

      expect(fieldsForStep(fields, 1).map(f => f.name)).toEqual([
        'ordenado',
        'legado',
      ]);
    });

    it('empate de position preserva a ordem do array', () => {
      const fields = [
        campo({ name: 'primeiro', position: 2 }),
        campo({ name: 'segundo', position: 2 }),
      ];

      expect(fieldsForStep(fields, 1).map(f => f.name)).toEqual([
        'primeiro',
        'segundo',
      ]);
    });

    it('a ordenação é por etapa, e não atravessa etapas', () => {
      const fields = [
        campo({ name: 'e2', step: 2, position: 0 }),
        campo({ name: 'e1', step: 1, position: 9 }),
      ];

      expect(fieldsForStep(fields, 1).map(f => f.name)).toEqual(['e1']);
      expect(fieldsForStep(fields, 2).map(f => f.name)).toEqual(['e2']);
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
