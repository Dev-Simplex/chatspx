// Layout em ÁRVORE (top-down) determinístico para o canvas Flow. Substitui o antigo
// empilhamento linear por índice (y = index * altura): posiciona cada nó seguindo as
// ARESTAS/ramos — filhos abaixo do pai e, quando um nó tem várias saídas (condition Sim/Não,
// rotas do router), os ramos abrem em COLUNAS lado a lado, sem sobreposição.
//
// Três passos, todos O(nós + arestas) e puros:
//  1. PROFUNDIDADE (y lógico) = caminho MAIS LONGO desde uma raiz, ignorando arestas de retorno
//     (as que fecham ciclo). Assim um nó em que vários ramos CONVERGEM (o "encerrar" no fim de
//     um menu) fica abaixo de TODOS os pais, e nenhuma aresta precisa subir por cima dos cards.
//  2. COLUNA (x) por DFS "próxima coluna livre": cada FOLHA consome a próxima coluna; cada nó
//     interno é CENTRALIZADO sobre o intervalo dos filhos (média das colunas extrema esq/dir).
//     Duas folhas nunca compartilham coluna e subárvores irmãs nunca se sobrepõem na horizontal.
//  3. y REAL de cada nível = altura do card MAIS ALTO daquele nível + folga. O card não tem
//     altura fixa (ver estimateNodeHeight): antes disso um `wait_for_reply` com muitas respostas
//     invadia o nível de baixo — era a causa dos blocos sobrepostos em fluxos grandes.
//
// Invariante que sai daí (coberto por spec): dois cards NUNCA se sobrepõem. No mesmo nível eles
// ficam a pelo menos 1 coluna (H_SPACING ≥ NODE_WIDTH) porque subárvores ocupam faixas de coluna
// disjuntas; entre níveis vizinhos o próximo nível começa abaixo da base do card mais alto.
//
// A `definition` continua a fonte da verdade — este módulo só DERIVA posições para os nós
// que ainda não têm uma `position` manual (arrastada pelo usuário); ver FlowCanvasView.

// Largura do card do nó (FlowNode = w-64 = 256px). Como todos os nós têm a mesma largura,
// ancorar pelo canto superior-esquerdo já centraliza o pai sobre os filhos (mesma constante
// some dos dois lados), sem precisar deslocar por NODE_WIDTH/2.
export const NODE_WIDTH = 256;

// Altura ESTIMADA do card. O FlowNode NÃO tem altura fixa: cada porta de ramo é uma linha na
// lista, então um `wait_for_reply` com 8 respostas fica ~4× mais alto que uma ação. Os números
// espelham o template do FlowNode (py-2.5 + família + rótulo + subtítulo; cada porta é um <li>
// text-xs com py-0.5 e gap-1, precedidos de mt-1.5). São ESTIMATIVAS — erram por poucos pixels
// e só alimentam o espaçamento vertical, que ainda soma V_GAP por cima.
const NODE_BASE_HEIGHT = 80;
const PORT_ROW_HEIGHT = 24;
const PORTS_BLOCK_MARGIN = 6;

// Passo entre colunas (centro a centro). O corredor VAZIO entre dois cards vizinhos vale
// H_SPACING - NODE_WIDTH, e é por ele que a aresta de um ramo desce: o smoothstep sai pela
// borda DIREITA do card (as portas do FlowNode são Position.Right) e vira 20px depois dela.
// É também onde o pill do ramo é desenhado ("Vendas de Veículos" ≈ 110px). Com os 64px antigos
// o pill cobria o card vizinho e ficava ilegível; 128px o acomodam dentro do corredor.
export const H_SPACING = NODE_WIDTH + 128; // 384

// Avanço vertical de um nível cujo card mais alto é um card PADRÃO (sem portas) — o caso do
// fluxo linear. Níveis com cards mais altos empurram o próximo nível na mesma proporção
// (ver levelOffsets), então V_SPACING é o PISO, não a regra fixa de antes.
export const V_SPACING = 220;

// Folga real entre a base de um card e o topo do card de baixo. É onde a curva do smoothstep
// faz a volta (ela corre na horizontal 20px acima do alvo) e onde o pill do ramo pousa.
const V_GAP = V_SPACING - NODE_BASE_HEIGHT; // 140

// Quantas linhas de PORTA o card desenha. Espelha `branchPorts` do FlowNode — que NÃO é a mesma
// lista de `branchOrder` (abaixo): o fallback do wait_for_reply é uma porta VISÍVEL, mas a aresta
// que sai dela é gravada sem `branch`. Aqui só interessa o que ocupa altura na tela.
const portRowCount = node => {
  if (!node) return 0;
  if (node.type === 'condition') return 2;
  if (node.type === 'router') {
    return (Array.isArray(node.routes) ? node.routes.length : 0) + 1;
  }
  if (node.type === 'wait_for_reply') {
    const replies = Array.isArray(node.replies) ? node.replies.length : 0;
    return replies + (node.timeout?.enabled ? 1 : 0) + 1;
  }
  return 0;
};

// Altura estimada do card em px. Exportada para as specs poderem provar a não-sobreposição com
// o mesmo retângulo que o layout usa para se espaçar.
export const estimateNodeHeight = node => {
  const rows = portRowCount(node);
  if (!rows) return NODE_BASE_HEIGHT;
  return NODE_BASE_HEIGHT + PORTS_BLOCK_MARGIN + rows * PORT_ROW_HEIGHT;
};

// Ordem estável das portas de saída de um nó, para os ramos abrirem sempre na mesma ordem:
// condition → Sim (esquerda) / Não (direita); router → rotas na ordem declarada + fallback
// por último (extrema direita); wait_for_reply → respostas na ordem + timeout, com o fallback
// (aresta SEM rótulo) caindo por último naturalmente (keyOf '' → rank fora da ordem). Espelha
// branchPorts do FlowNode.
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
  if (node.type === 'wait_for_reply') {
    const keys = (Array.isArray(node.replies) ? node.replies : []).map(reply =>
      String(reply.key)
    );
    keys.push('timeout');
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
  const ids = nodes.map(node => String(node.id));

  // Filhos de cada nó, calculados UMA vez, na ordem de ramo (branchOrder). Arestas sem ramo
  // (linear) ou de ramo desconhecido vão para o fim, preservando a ordem da definition. Arestas
  // órfãs (ponta inexistente) são ignoradas para não gerar filhos-fantasma.
  const childrenById = new Map(ids.map(id => [id, []]));
  edges.forEach(edge => {
    if (edge.to == null) return;
    const from = String(edge.from);
    const to = String(edge.to);
    if (!byId.has(from) || !byId.has(to)) return;
    childrenById.get(from).push(edge);
  });
  childrenById.forEach((list, id) => {
    const order = branchOrder(byId.get(id));
    const keyOf = edge => (edge.branch == null ? '' : String(edge.branch));
    const portRank = edge => {
      const index = order.indexOf(keyOf(edge));
      return index === -1 ? order.length : index;
    };
    childrenById.set(
      id,
      list
        .map((edge, index) => ({ edge, index }))
        .sort(
          (a, b) => portRank(a.edge) - portRank(b.edge) || a.index - b.index
        )
        .map(item => String(item.edge.to))
    );
  });

  // Raízes = nós que nenhuma aresta aponta (tipicamente o gatilho). Ordem da definition para
  // determinismo; várias raízes são tiladas lado a lado (compartilham o contador de colunas).
  // Se um ciclo puro não deixar nenhuma raiz, começa pelo 1º nó para ainda posicionar tudo.
  const targeted = new Set();
  childrenById.forEach(kids => kids.forEach(kid => targeted.add(kid)));
  let roots = ids.filter(id => !targeted.has(id));
  if (!roots.length) roots = [ids[0]];

  // PASSO 1 — arestas de RETORNO. Uma aresta é de retorno quando aponta para um nó que ainda
  // está na pilha da DFS: é ela que fecha o ciclo. Só essas ficam de fora do cálculo de
  // profundidade (senão o ciclo empurraria a si mesmo para sempre). Arestas de CONVERGÊNCIA
  // (dois ramos caindo no mesmo nó) contam — é justamente o que empurra o nó compartilhado
  // para baixo de todos os pais.
  const ON_STACK = 1;
  const DONE = 2;
  const visitState = new Map();
  const backEdges = new Set();
  const edgeKey = (from, to) => `${from}\u0000${to}`;
  const classify = id => {
    visitState.set(id, ON_STACK);
    childrenById.get(id).forEach(kid => {
      const state = visitState.get(kid);
      if (state === ON_STACK) backEdges.add(edgeKey(id, kid));
      else if (state !== DONE) classify(kid);
    });
    visitState.set(id, DONE);
  };
  roots.forEach(id => {
    if (!visitState.has(id)) classify(id);
  });
  ids.forEach(id => {
    if (!visitState.has(id)) classify(id);
  });

  // Profundidade = caminho mais longo até aqui (0 para quem não tem pai). Sem as arestas de
  // retorno o grafo é acíclico, então a recursão memoizada termina; `resolving` é só cinto.
  const parentsById = new Map(ids.map(id => [id, []]));
  childrenById.forEach((kids, id) => {
    kids.forEach(kid => {
      if (!backEdges.has(edgeKey(id, kid))) parentsById.get(kid).push(id);
    });
  });
  const depthById = new Map();
  const resolving = new Set();
  const depthOf = id => {
    if (depthById.has(id)) return depthById.get(id);
    if (resolving.has(id)) return 0;
    resolving.add(id);
    const depth = parentsById
      .get(id)
      .reduce((deepest, parent) => Math.max(deepest, depthOf(parent) + 1), 0);
    resolving.delete(id);
    depthById.set(id, depth);
    return depth;
  };
  ids.forEach(depthOf);

  // PASSO 3 (pré-calculado) — o y de cada nível. Não é `profundidade * V_SPACING`: um nível com
  // um card alto (router/wait_for_reply com muitas portas) precisa empurrar o nível seguinte na
  // altura desse card, senão os dois se sobrepõem. Piso em NODE_BASE_HEIGHT para que um nível
  // só de cards padrão continue avançando exatamente V_SPACING.
  const tallestByDepth = [];
  nodes.forEach(node => {
    const depth = depthById.get(String(node.id)) || 0;
    tallestByDepth[depth] = Math.max(
      tallestByDepth[depth] || 0,
      estimateNodeHeight(node)
    );
  });
  const levelOffsets = [0];
  for (let depth = 1; depth < tallestByDepth.length; depth += 1) {
    levelOffsets[depth] =
      levelOffsets[depth - 1] +
      Math.max(NODE_BASE_HEIGHT, tallestByDepth[depth - 1] || 0) +
      V_GAP;
  }
  const yFor = id => levelOffsets[depthById.get(id) || 0] || 0;

  const visited = new Set();
  let nextColumn = 0;
  const takeColumn = () => {
    const column = nextColumn;
    nextColumn += 1;
    return column;
  };

  // PASSO 2 — DFS: uma folha consome a próxima coluna livre; um nó interno é centralizado sobre
  // o intervalo (1ª..última) das colunas dos filhos. `visited` blinda contra ciclos e filhos
  // compartilhados (grafo convergente): a 2ª aresta que chega a um nó já colocado é ignorada
  // no posicionamento (a linha ainda é desenhada pelo Vue Flow, agora sempre para BAIXO porque
  // a profundidade veio do caminho mais longo).
  const place = id => {
    if (visited.has(id)) return null;
    visited.add(id);
    const kids = childrenById.get(id).filter(kid => !visited.has(kid));
    let column;
    if (!kids.length) {
      column = takeColumn();
    } else {
      const cols = kids.map(kid => place(kid)).filter(value => value != null);
      column = cols.length
        ? (cols[0] + cols[cols.length - 1]) / 2
        : takeColumn();
    }
    positions.set(id, { x: Math.round(column * H_SPACING), y: yFor(id) });
    return column;
  };

  roots.forEach(root => place(root));

  // Ilha inteiramente presa em ciclo (nenhum nó dela é raiz): trata o primeiro nó alcançado como
  // raiz da ilha, para ela entrar na árvore em vez de empilhar tudo na origem.
  ids.forEach(id => {
    if (!visited.has(id)) place(id);
  });

  // Rede de segurança: qualquer nó que a DFS não alcançou ganha uma coluna própria — nunca
  // fica sem posição.
  nodes.forEach(node => {
    const id = String(node.id);
    if (!positions.has(id)) {
      positions.set(id, {
        x: Math.round(takeColumn() * H_SPACING),
        y: yFor(id),
      });
    }
  });

  return positions;
}
