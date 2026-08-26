// Transporte da definition: copiar/colar blocos (Ctrl+C/Ctrl+V) e exportar/importar o fluxo
// inteiro como arquivo. Tudo puro (sem DOM, sem store) para ficar testável — quem chama cuida
// do clipboard do navegador e do download.
//
// REGRA DE OURO: um bloco colado nunca pode herdar o id de origem. Ids colidindo fundiriam dois
// blocos num só e reescreveriam arestas alheias. Toda entrada externa (colar de outra aba,
// importar arquivo) passa por remapeamento de id + normalização de forma.

export const NODES_KIND = 'chatspx.flow.nodes';
export const FLOW_KIND = 'chatspx.flow';
export const IO_VERSION = 1;

const asArray = value => (Array.isArray(value) ? value : []);

// Gerador de ids livres, à prova de ids sem dígito ("trigger", "n_final") vindos de fluxos
// legados/importados — que num esquema baseado em "maior número + 1" colidiriam em silêncio.
export const createIdFactory = existingIds => {
  const taken = new Set(asArray(existingIds).map(String));
  let cursor = taken.size + 1;
  return () => {
    while (taken.has(`n${cursor}`)) cursor += 1;
    const id = `n${cursor}`;
    taken.add(id);
    return id;
  };
};

// ---------------------------------------------------------------- copiar / colar

export const serializeNodes = (nodes, edges = []) => {
  const ids = new Set(asArray(nodes).map(node => String(node.id)));
  return {
    kind: NODES_KIND,
    version: IO_VERSION,
    nodes: asArray(nodes).map(node => structuredClone(node)),
    // Só as arestas INTERNAS à seleção viajam; uma aresta para fora apontaria para um id que
    // pode não existir no destino.
    edges: asArray(edges)
      .filter(edge => ids.has(String(edge.from)) && ids.has(String(edge.to)))
      .map(edge => structuredClone(edge)),
  };
};

export const parseNodesPayload = raw => {
  const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (!data || data.kind !== NODES_KIND || !Array.isArray(data.nodes)) {
    return null;
  }
  if (!data.nodes.length) return null;
  return { nodes: data.nodes, edges: asArray(data.edges) };
};

// Cola a seleção numa definition, com ids novos e um deslocamento visual para o bloco colado
// não ficar exatamente por cima do original. Devolve { definition, ids } — `ids` na ordem em que
// os nós foram colados (quem chama seleciona o primeiro).
export const pasteNodes = (definition, payload, offset = { x: 48, y: 48 }) => {
  const nodes = asArray(definition?.nodes);
  const edges = asArray(definition?.edges);
  const nextId = createIdFactory(nodes.map(node => node.id));
  const idMap = new Map();

  const pasted = payload.nodes.map(source => {
    const clone = structuredClone(source);
    const id = nextId();
    idMap.set(String(source.id), id);
    clone.id = id;
    if (clone.position) {
      clone.position = {
        x: Math.round(clone.position.x + offset.x),
        y: Math.round(clone.position.y + offset.y),
      };
    }
    return clone;
  });

  const pastedEdges = payload.edges
    .filter(edge => idMap.has(String(edge.from)) && idMap.has(String(edge.to)))
    .map(edge => ({
      ...structuredClone(edge),
      from: idMap.get(String(edge.from)),
      to: idMap.get(String(edge.to)),
    }));

  return {
    definition: {
      ...definition,
      nodes: [...nodes, ...pasted],
      edges: [...edges, ...pastedEdges],
    },
    ids: pasted.map(node => node.id),
  };
};

// ---------------------------------------------------------------- exportar / importar

export const serializeFlow = flow => ({
  kind: FLOW_KIND,
  version: IO_VERSION,
  name: flow.name || '',
  trigger_type: flow.trigger_type || 'manual',
  trigger_config: flow.trigger_config || {},
  definition: {
    nodes: asArray(flow.definition?.nodes),
    edges: asArray(flow.definition?.edges),
  },
});

// Nome de arquivo previsível e seguro em qualquer sistema: só letras/números/hífen.
export const fileNameFor = name => {
  const slug = String(name || 'fluxo')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
  return `${slug || 'fluxo'}.flow.json`;
};

// Lê um arquivo exportado. Lança Error com uma chave i18n na mensagem quando o conteúdo não é um
// fluxo válido — o canvas nunca deve substituir o grafo em edição por lixo.
// O `webhook_token` é DESCARTADO de propósito: ele identifica o flow de origem no endpoint
// público e é backend-autoritativo (Flow#ensure_webhook_token). Importar um fluxo não pode
// sequestrar o gatilho de outro.
export const parseFlowFile = raw => {
  let data;
  try {
    data = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch (error) {
    throw new Error('INVALID_JSON');
  }
  if (!data || typeof data !== 'object') throw new Error('INVALID_SHAPE');

  // Aceita tanto o envelope exportado quanto uma `definition` crua colada de outro lugar.
  const definition = data.kind === FLOW_KIND ? data.definition : data;
  if (!definition || !Array.isArray(definition.nodes)) {
    throw new Error('INVALID_SHAPE');
  }
  if (!definition.nodes.every(node => node && typeof node === 'object')) {
    throw new Error('INVALID_SHAPE');
  }

  const { webhook_token: _discarded, ...triggerConfig } =
    data.trigger_config && typeof data.trigger_config === 'object'
      ? data.trigger_config
      : {};

  return {
    name: typeof data.name === 'string' ? data.name : '',
    trigger_type: data.trigger_type,
    trigger_config: triggerConfig,
    definition: {
      nodes: definition.nodes.map(node => {
        // O token do webhook também é ecoado no nó `trigger` (só para exibição) — sai junto.
        const { webhook_token: _echo, ...rest } = node;
        return { ...rest, id: String(node.id) };
      }),
      edges: asArray(definition.edges)
        .filter(edge => edge && edge.from && edge.to)
        .map(edge => ({
          ...edge,
          from: String(edge.from),
          to: String(edge.to),
        })),
    },
  };
};
