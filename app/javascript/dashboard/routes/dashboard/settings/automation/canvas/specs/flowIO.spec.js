import { describe, it, expect } from 'vitest';
import {
  serializeNodes,
  parseNodesPayload,
  pasteNodes,
  serializeFlow,
  parseFlowFile,
  fileNameFor,
  createIdFactory,
  NODES_KIND,
  FLOW_KIND,
} from '../flowIO';

const node = (id, extra = {}) => ({
  id,
  type: 'action',
  action_name: 'send_message',
  action_params: ['oi'],
  position: { x: 10, y: 20 },
  ...extra,
});

const definition = () => ({
  nodes: [node('n1'), node('n2')],
  edges: [{ from: 'n1', to: 'n2' }],
});

describe('createIdFactory', () => {
  it('nunca devolve um id já ocupado', () => {
    const next = createIdFactory(['n1', 'n2', 'n3']);
    expect([next(), next()]).toEqual(['n4', 'n5']);
  });

  // Ids sem dígito ("trigger") vêm de fluxos legados; um esquema "maior número + 1" colidiria.
  it('lida com ids sem número', () => {
    const next = createIdFactory(['trigger', 'n1']);
    expect(next()).not.toBe('n1');
  });
});

describe('copiar/colar blocos', () => {
  it('serializa só as arestas internas à seleção', () => {
    const payload = serializeNodes([node('n1')], [{ from: 'n1', to: 'n2' }]);
    expect(payload.kind).toBe(NODES_KIND);
    expect(payload.edges).toEqual([]);
  });

  it('mantém a aresta quando os dois lados estão na seleção', () => {
    const payload = serializeNodes(
      [node('n1'), node('n2')],
      [{ from: 'n1', to: 'n2' }]
    );
    expect(payload.edges).toHaveLength(1);
  });

  // Herdar o id de origem fundiria dois blocos num só e reescreveria arestas alheias.
  it('cola com id novo, sem tocar nos existentes', () => {
    const { definition: next, ids } = pasteNodes(
      definition(),
      serializeNodes([node('n1')])
    );
    expect(ids).toHaveLength(1);
    expect(['n1', 'n2']).not.toContain(ids[0]);
    expect(next.nodes.map(n => n.id)).toEqual(['n1', 'n2', ids[0]]);
    expect(next.edges).toEqual([{ from: 'n1', to: 'n2' }]);
  });

  it('desloca o bloco colado para não ficar por cima do original', () => {
    const { definition: next, ids } = pasteNodes(
      definition(),
      serializeNodes([node('n1')])
    );
    const pasted = next.nodes.find(n => n.id === ids[0]);
    expect(pasted.position).toEqual({ x: 58, y: 68 });
  });

  it('remapeia as arestas internas ao colar', () => {
    const payload = serializeNodes(
      [node('n1'), node('n2')],
      [{ from: 'n1', to: 'n2' }]
    );
    const { definition: next, ids } = pasteNodes(definition(), payload);
    expect(next.edges).toContainEqual({ from: ids[0], to: ids[1] });
  });

  it('não copia por referência (editar o colado não mexe no original)', () => {
    const source = definition();
    const { definition: next, ids } = pasteNodes(
      source,
      serializeNodes([source.nodes[0]])
    );
    next.nodes.find(n => n.id === ids[0]).action_params[0] = 'alterado';
    expect(source.nodes[0].action_params[0]).toBe('oi');
  });

  it('ignora conteúdo de clipboard que não é um bloco', () => {
    expect(parseNodesPayload('{"kind":"outra-coisa"}')).toBeNull();
    expect(
      parseNodesPayload(JSON.stringify({ kind: NODES_KIND, nodes: [] }))
    ).toBeNull();
  });
});

describe('exportar/importar fluxo', () => {
  it('exporta com envelope identificável', () => {
    const payload = serializeFlow({
      name: 'Menu',
      definition: definition(),
      trigger_type: 'conversation_event',
      trigger_config: { event_name: 'conversation_created' },
    });
    expect(payload.kind).toBe(FLOW_KIND);
    expect(payload.definition.nodes).toHaveLength(2);
  });

  it('faz round-trip do envelope', () => {
    const payload = serializeFlow({ name: 'Menu', definition: definition() });
    const parsed = parseFlowFile(JSON.stringify(payload));
    expect(parsed.name).toBe('Menu');
    expect(parsed.definition.edges).toEqual([{ from: 'n1', to: 'n2' }]);
  });

  it('aceita uma definition crua', () => {
    const parsed = parseFlowFile(JSON.stringify(definition()));
    expect(parsed.definition.nodes).toHaveLength(2);
  });

  // O token identifica o flow de ORIGEM no endpoint público: importar não pode sequestrá-lo.
  it('descarta o webhook_token na importação', () => {
    const parsed = parseFlowFile(
      JSON.stringify({
        kind: FLOW_KIND,
        name: 'x',
        trigger_config: { webhook_token: 'segredo', event_name: 'a' },
        definition: {
          nodes: [{ id: 't', type: 'trigger', webhook_token: 'segredo' }],
          edges: [],
        },
      })
    );
    expect(parsed.trigger_config.webhook_token).toBeUndefined();
    expect(parsed.trigger_config.event_name).toBe('a');
    expect(parsed.definition.nodes[0].webhook_token).toBeUndefined();
  });

  it('descarta aresta sem ponta', () => {
    const parsed = parseFlowFile(
      JSON.stringify({ nodes: [node('n1')], edges: [{ from: 'n1' }] })
    );
    expect(parsed.definition.edges).toEqual([]);
  });

  it('recusa arquivo inválido', () => {
    expect(() => parseFlowFile('nao é json')).toThrow('INVALID_JSON');
    expect(() => parseFlowFile('{"nodes": "x"}')).toThrow('INVALID_SHAPE');
    expect(() => parseFlowFile('{"nodes": [1]}')).toThrow('INVALID_SHAPE');
  });
});

describe('fileNameFor', () => {
  it('gera um nome seguro a partir do nome do fluxo', () => {
    expect(fileNameFor('Menu — Atenção!')).toBe('menu-atencao.flow.json');
  });

  it('cai num nome padrão quando não há nome', () => {
    expect(fileNameFor('')).toBe('fluxo.flow.json');
    expect(fileNameFor('###')).toBe('fluxo.flow.json');
  });
});
