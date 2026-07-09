// Layout em ÁRVORE (top-down) determinístico para o canvas Flow. Substitui o antigo
// empilhamento linear por índice (y = index * altura): posiciona cada nó seguindo as
// ARESTAS/ramos — filhos abaixo do pai e, quando um nó tem várias saídas (condition Sim/Não,
// rotas do router), os ramos abrem em COLUNAS lado a lado, sem sobreposição.
//
// Algoritmo (DFS "próxima coluna"): cada FOLHA consome a próxima coluna livre; cada nó
// interno é CENTRALIZADO sobre o intervalo dos filhos (média das colunas extrema esq/dir).
// Isso garante que duas folhas nunca compartilhem coluna e que subárvores irmãs jamais se
// sobreponham na horizontal. y = profundidade; x = coluna. Puro e O(nós + arestas).
//
// A `definition` continua a fonte da verdade — este módulo só DERIVA posições para os nós
// que ainda não têm uma `position` manual (arrastada pelo usuário); ver FlowCanvasView.

// Largura do card do nó (FlowNode = w-64 = 256px). Como todos os nós têm a mesma largura,
// ancorar pelo canto superior-esquerdo já centraliza o pai sobre os filhos (mesma constante
// some dos dois lados), sem precisar deslocar por NODE_WIDTH/2.
const NODE_WIDTH = 256;

// Passo entre colunas (centro a centro) e entre profundidades (topo a topo). Espaçados o
// bastante para caber o card (256px) + folga para as arestas e os pills de ramo, e para os
// nós mais altos (router com várias rotas) não colidirem com a linha de baixo.
export const H_SPACING = NODE_WIDTH + 64; // 320
export const V_SPACING = 220;

// Ordem estável das portas de saída de um nó, para os ramos abrirem sempre na mesma ordem:
// condition → Sim (esquerda) / Não (direita); router → rotas na ordem declarada + fallback
// por último (extrema direita). Espelha branchPorts do FlowNode.
const branchOrder = node => {
  if (!node) return [];
  if (node.type === 'condition') return ['true', 'false'];
  if (node.type === 'router') {
    const keys = (Array.isArray(node.routes) ? node.routes : []).map(route =>
      String(route.key)
    );
    keys.push(String(node.fallback_key || 'fallback'));
    return keys;
  }
  return [];
};

// Deriva um Map { id -> { x, y } } para TODOS os nós da definition. Sempre retorna uma
// posição finita para cada nó — nós desconectados ou presos em ciclo caem em colunas
// próprias, sem NaN e sem sobreposição óbvia.
export function computeTreeLayout(definition = {}) {
  const nodes = Array.isArray(definition.nodes) ? definition.nodes : [];
  const edges = Array.isArray(definition.edges) ? definition.edges : [];
  const positions = new Map();
  if (!nodes.length) return positions;

  const byId = new Map(nodes.map(node => [String(node.id), node]));

  // Filhos de um nó, na ordem de ramo (branchOrder). Arestas sem ramo (linear) ou de ramo
  // desconhecido vão para o fim, preservando a ordem da definition. Ignora arestas órfãs
  // (alvo inexistente) para não gerar filhos-fantasma.
  const childrenOf = id => {
    const node = byId.get(id);
    const order = branchOrder(node);
    const keyOf = edge => (edge.branch == null ? '' : String(edge.branch));
    const rank = edge => {
      const index = order.indexOf(keyOf(edge));
      return index === -1 ? order.length : index;
    };
    return edges
      .filter(
        edge =>
          String(edge.from) === id &&
          edge.to != null &&
          byId.has(String(edge.to))
      )
      .slice()
      .sort((a, b) => rank(a) - rank(b))
      .map(edge => String(edge.to));
  };

  // Raízes = nós que nenhuma aresta aponta (tipicamente o gatilho). Ordem da definition para
  // determinismo; várias raízes são tiladas lado a lado (compartilham o contador de colunas).
  // Se um ciclo puro não deixar nenhuma raiz, começa pelo 1º nó para ainda posicionar tudo.
  const targeted = new Set(
    edges.filter(edge => edge.to != null).map(edge => String(edge.to))
  );
  let roots = nodes
    .map(node => String(node.id))
    .filter(id => !targeted.has(id));
  if (!roots.length) roots = [String(nodes[0].id)];

  const visited = new Set();
  let nextColumn = 0;
  const takeColumn = () => {
    const column = nextColumn;
    nextColumn += 1;
    return column;
  };

  // DFS: uma folha consome a próxima coluna livre; um nó interno é centralizado sobre o
  // intervalo (1ª..última) das colunas dos filhos. `visited` blinda contra ciclos e filhos
  // compartilhados (grafo convergente): a 2ª aresta que chega a um nó já colocado é ignorada
  // no posicionamento (a linha ainda é desenhada pelo Vue Flow).
  const place = (id, depth) => {
    if (visited.has(id)) return null;
    visited.add(id);
    const kids = childrenOf(id).filter(kid => !visited.has(kid));
    let column;
    if (!kids.length) {
      column = takeColumn();
    } else {
      const cols = kids
        .map(kid => place(kid, depth + 1))
        .filter(value => value != null);
      column = cols.length
        ? (cols[0] + cols[cols.length - 1]) / 2
        : takeColumn();
    }
    positions.set(id, {
      x: Math.round(column * H_SPACING),
      y: depth * V_SPACING,
    });
    return column;
  };

  roots.forEach(root => place(root, 0));

  // Rede de segurança: qualquer nó que a DFS não alcançou (subgrafo órfão / ciclo) ganha uma
  // coluna própria — nunca fica sem posição.
  nodes.forEach(node => {
    const id = String(node.id);
    if (!positions.has(id)) {
      positions.set(id, { x: Math.round(takeColumn() * H_SPACING), y: 0 });
    }
  });

  return positions;
}
