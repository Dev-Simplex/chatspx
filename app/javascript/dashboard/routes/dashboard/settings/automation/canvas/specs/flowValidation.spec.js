import { describe, it, expect } from 'vitest';
import { validateDefinition, errorsOf, warningsOf } from '../flowValidation';

const interactive = (id, content, items) => ({
  id,
  type: 'action',
  action_name: 'send_interactive',
  action_params: [{ content, items }],
});

const wait = (id, replies, extra = {}) => ({
  id,
  type: 'wait_for_reply',
  replies,
  fallback_key: 'fallback',
  ...extra,
});

const OPTIONS = [
  { title: 'Boleto em aberto', value: 'Boleto em aberto' },
  { title: 'QRCode', value: 'QRCode' },
];

// Grafo saudável: menu com corpo → espera as duas opções → cada uma ligada, com fallback.
const healthy = () => ({
  nodes: [
    interactive('n1', 'Escolha uma opção:', OPTIONS),
    wait('n2', [{ key: 'Boleto em aberto' }, { key: 'QRCode' }]),
    {
      id: 'n3',
      type: 'action',
      action_name: 'add_label',
      action_params: ['a'],
    },
  ],
  edges: [
    { from: 'n1', to: 'n2' },
    { from: 'n2', to: 'n3', branch: 'Boleto em aberto' },
    { from: 'n2', to: 'n3', branch: 'QRCode' },
    { from: 'n2', to: 'n3' },
  ],
});

const keysOf = findings => findings.map(f => f.key);

describe('validateDefinition', () => {
  it('não reclama de um grafo completo', () => {
    expect(validateDefinition(healthy())).toEqual([]);
  });

  // A regressão que motivou o módulo: corpo em branco = mensagem recusada pela Meta.
  it('bloqueia send_interactive sem corpo', () => {
    const graph = healthy();
    graph.nodes[0].action_params[0].content = '   ';
    const errors = errorsOf(validateDefinition(graph));
    expect(keysOf(errors)).toContain(
      'AUTOMATION.CANVAS.VALIDATION.INTERACTIVE_BODY_REQUIRED'
    );
    expect(errors[0].nodeId).toBe('n1');
  });

  it('bloqueia send_interactive sem nenhuma opção com título', () => {
    const graph = healthy();
    graph.nodes[0].action_params[0].items = [{ title: '  ', value: 'x' }];
    expect(keysOf(errorsOf(validateDefinition(graph)))).toContain(
      'AUTOMATION.CANVAS.VALIDATION.INTERACTIVE_ITEMS_REQUIRED'
    );
  });

  it('bloqueia opção sem valor', () => {
    const graph = healthy();
    graph.nodes[0].action_params[0].items = [{ title: 'Ok', value: '' }];
    expect(keysOf(errorsOf(validateDefinition(graph)))).toContain(
      'AUTOMATION.CANVAS.VALIDATION.INTERACTIVE_VALUE_REQUIRED'
    );
  });

  it('bloqueia mensagem de texto vazia', () => {
    const graph = healthy();
    graph.nodes.push({
      id: 'n4',
      type: 'action',
      action_name: 'send_message',
      action_params: [''],
    });
    expect(keysOf(errorsOf(validateDefinition(graph)))).toContain(
      'AUTOMATION.CANVAS.VALIDATION.MESSAGE_BODY_REQUIRED'
    );
  });

  it('bloqueia wait_for_reply sem resposta esperada', () => {
    const graph = healthy();
    graph.nodes[1].replies = [];
    expect(keysOf(errorsOf(validateDefinition(graph)))).toContain(
      'AUTOMATION.CANVAS.VALIDATION.WAIT_REPLIES_REQUIRED'
    );
  });

  // Sem fallback e sem timeout o walker não acha aresta, encerra o run e a resposta certa
  // seguinte é descartada — foi o que travou os submenus n40/n46 da AGN.
  it('avisa sobre wait_for_reply sem fallback e sem timeout', () => {
    const graph = healthy();
    graph.edges = graph.edges.filter(
      edge => !(edge.from === 'n2' && edge.branch == null)
    );
    expect(keysOf(warningsOf(validateDefinition(graph)))).toContain(
      'AUTOMATION.CANVAS.VALIDATION.WAIT_FALLBACK_MISSING'
    );
  });

  it('não avisa de fallback quando há timeout habilitado', () => {
    const graph = healthy();
    graph.edges = graph.edges.filter(
      edge => !(edge.from === 'n2' && edge.branch == null)
    );
    graph.nodes[1].timeout = { enabled: true, value: 1, unit: 'hours' };
    expect(keysOf(warningsOf(validateDefinition(graph)))).not.toContain(
      'AUTOMATION.CANVAS.VALIDATION.WAIT_FALLBACK_MISSING'
    );
  });

  // Um espaço a mais na chave e a resposta certa cai no fallback — silencioso e caríssimo.
  it('avisa quando a chave não casa nenhuma opção enviada', () => {
    const graph = healthy();
    graph.nodes[1].replies = [{ key: 'Boleto em aberto ' }, { key: 'QRCode' }];
    graph.edges = graph.edges.map(edge =>
      edge.branch === 'Boleto em aberto'
        ? { ...edge, branch: 'Boleto em aberto ' }
        : edge
    );
    const warnings = warningsOf(validateDefinition(graph));
    const unmatched = warnings.find(
      f => f.key === 'AUTOMATION.CANVAS.VALIDATION.WAIT_KEY_UNMATCHED'
    );
    expect(unmatched.params.key).toBe('Boleto em aberto ');
  });

  it('avisa sobre saída rotulada sem conexão', () => {
    const graph = healthy();
    graph.edges = graph.edges.filter(edge => edge.branch !== 'QRCode');
    const warnings = warningsOf(validateDefinition(graph));
    expect(
      warnings.find(
        f => f.key === 'AUTOMATION.CANVAS.VALIDATION.PORT_NOT_CONNECTED'
      ).params.key
    ).toBe('QRCode');
  });

  it('tolera definition vazia/ausente', () => {
    expect(validateDefinition(undefined)).toEqual([]);
    expect(validateDefinition({})).toEqual([]);
  });
});
