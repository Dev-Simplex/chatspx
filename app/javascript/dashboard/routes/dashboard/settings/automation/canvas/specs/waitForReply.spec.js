import {
  repliesFromInteractiveNode,
  interactiveOptionsForWait,
} from '../waitForReply';

describe('repliesFromInteractiveNode', () => {
  it('returns an empty array for a nullish prev node', () => {
    expect(repliesFromInteractiveNode(null)).toEqual([]);
    expect(repliesFromInteractiveNode(undefined)).toEqual([]);
  });

  it('returns an empty array when prev is not a send_interactive action', () => {
    expect(repliesFromInteractiveNode({ type: 'trigger' })).toEqual([]);
    expect(repliesFromInteractiveNode({ type: 'router' })).toEqual([]);
    expect(
      repliesFromInteractiveNode({
        type: 'action',
        action_name: 'send_message',
      })
    ).toEqual([]);
    // a wait_for_reply is not a send_interactive either
    expect(repliesFromInteractiveNode({ type: 'wait_for_reply' })).toEqual([]);
  });

  it('returns an empty array when send_interactive has no items', () => {
    expect(
      repliesFromInteractiveNode({
        type: 'action',
        action_name: 'send_interactive',
      })
    ).toEqual([]);
    expect(
      repliesFromInteractiveNode({
        type: 'action',
        action_name: 'send_interactive',
        action_params: [],
      })
    ).toEqual([]);
    expect(
      repliesFromInteractiveNode({
        type: 'action',
        action_name: 'send_interactive',
        action_params: [{ content: 'Pick one', items: [] }],
      })
    ).toEqual([]);
  });

  it('maps each option { title, value } to { key: value, label: title }', () => {
    const prev = {
      type: 'action',
      action_name: 'send_interactive',
      action_params: [
        {
          content: 'How can we help?',
          items: [
            { title: 'Schedule a visit', value: 'schedule', description: '' },
            { title: 'Talk to sales', value: 'sales', description: 'x' },
          ],
        },
      ],
    };
    // key === option value === the reply id the contact sends back === edge.branch
    expect(repliesFromInteractiveNode(prev)).toEqual([
      { key: 'schedule', label: 'Schedule a visit' },
      { key: 'sales', label: 'Talk to sales' },
    ]);
  });

  it('drops options without a value (no branch key to route on)', () => {
    const prev = {
      type: 'action',
      action_name: 'send_interactive',
      action_params: [
        {
          items: [
            { title: 'Kept', value: 'a' },
            { title: 'Dropped — blank value', value: '' },
            { title: 'Dropped — no value' },
          ],
        },
      ],
    };
    expect(repliesFromInteractiveNode(prev)).toEqual([
      { key: 'a', label: 'Kept' },
    ]);
  });

  it('coerces the value to a string key and defaults a missing title to an empty label', () => {
    const prev = {
      type: 'action',
      action_name: 'send_interactive',
      action_params: [
        {
          items: [{ value: 42 }],
        },
      ],
    };
    expect(repliesFromInteractiveNode(prev)).toEqual([
      { key: '42', label: '' },
    ]);
  });
});

// A chave da resposta TEM de ser byte-a-byte igual ao `value` enviado. Listar as opções que
// chegam ao nó é o que permite trocar o campo digitado por um select no editor.
describe('interactiveOptionsForWait', () => {
  const menu = (id, items) => ({
    id,
    type: 'action',
    action_name: 'send_interactive',
    action_params: [{ content: 'Escolha:', items }],
  });

  it('lista as opções do bloco interativo que desemboca no nó', () => {
    const definition = {
      nodes: [
        menu('n1', [
          { title: 'Boleto', value: 'boleto' },
          { title: 'Vendas', value: 'vendas' },
        ]),
        { id: 'n2', type: 'wait_for_reply', replies: [] },
      ],
      edges: [{ from: 'n1', to: 'n2' }],
    };
    expect(interactiveOptionsForWait(definition, 'n2')).toEqual([
      { key: 'boleto', label: 'Boleto' },
      { key: 'vendas', label: 'Vendas' },
    ]);
  });

  it('junta as opções de vários blocos que chegam no mesmo nó, sem repetir', () => {
    const definition = {
      nodes: [
        menu('n1', [{ title: 'Boleto', value: 'boleto' }]),
        menu('n2', [
          { title: 'Boleto', value: 'boleto' },
          { title: 'Vendas', value: 'vendas' },
        ]),
        { id: 'n3', type: 'wait_for_reply', replies: [] },
      ],
      edges: [
        { from: 'n1', to: 'n3' },
        { from: 'n2', to: 'n3' },
      ],
    };
    expect(interactiveOptionsForWait(definition, 'n3').map(o => o.key)).toEqual(
      ['boleto', 'vendas']
    );
  });

  it('devolve vazio quando o que chega não é um bloco interativo', () => {
    const definition = {
      nodes: [
        { id: 'n1', type: 'action', action_name: 'send_message' },
        { id: 'n2', type: 'wait_for_reply' },
      ],
      edges: [{ from: 'n1', to: 'n2' }],
    };
    expect(interactiveOptionsForWait(definition, 'n2')).toEqual([]);
  });

  it('tolera entradas ausentes', () => {
    expect(interactiveOptionsForWait(null, 'n1')).toEqual([]);
    expect(interactiveOptionsForWait({ nodes: [], edges: [] }, null)).toEqual(
      []
    );
  });
});
